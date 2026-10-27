import Foundation
import Postbox
import SwiftSignalKit

public struct ChatHistorySummarySourceMessage: Equatable {
    public let id: EngineMessage.Id
    public let date: Int32
    public let authorName: String
    public let text: String

    public init(id: EngineMessage.Id, date: Int32, authorName: String, text: String) {
        self.id = id
        self.date = date
        self.authorName = authorName
        self.text = text
    }
}

public struct DebugLLMChatHistorySummaryConfig: Equatable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var maxMessages: Int

    public static let `default` = DebugLLMChatHistorySummaryConfig(
        baseURL: "https://openrouter.ai/api/v1",
        apiKey: "",
        model: "openrouter/free",
        maxMessages: 30
    )

    public init(baseURL: String, apiKey: String, model: String, maxMessages: Int) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxMessages = maxMessages
    }

    public var normalizedMaxMessages: Int {
        return min(100, max(1, self.maxMessages))
    }
}

public func parseChatHistorySummaryPayload(
    data: Data,
    peerId: EnginePeer.Id,
    messageNamespace: MessageId.Namespace,
    coveredMessageCount: Int32,
    knownMessageIds: Set<Int32>
) -> ChatHistorySummary? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return parseChatHistorySummaryPayload(
        object: object,
        peerId: peerId,
        messageNamespace: messageNamespace,
        coveredMessageCount: coveredMessageCount,
        knownMessageIds: knownMessageIds
    )
}

public func parseChatHistorySummaryPayload(
    object: [String: Any],
    peerId: EnginePeer.Id,
    messageNamespace: MessageId.Namespace,
    coveredMessageCount: Int32,
    knownMessageIds: Set<Int32>
) -> ChatHistorySummary? {
    let overview = (object["overview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let rawSections = object["sections"] as? [[String: Any]] ?? []

    var sections: [ChatHistorySummary.Section] = []
    for raw in rawSections {
        guard let kind = parseChatHistorySummarySectionKind(raw["kind"] as? String) else {
            continue
        }
        let text = (raw["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            continue
        }

        var citation: ChatHistorySummary.Citation?
        if let citationId = parseCitationMessageId(raw["citationMessageId"]), knownMessageIds.contains(citationId) {
            citation = ChatHistorySummary.Citation(
                title: "Open message",
                messageId: EngineMessage.Id(peerId: peerId, namespace: messageNamespace, id: citationId)
            )
        }

        sections.append(ChatHistorySummary.Section(kind: kind, text: text, citation: citation))
    }

    if overview.isEmpty && sections.isEmpty {
        return ChatHistorySummary(overview: "", sections: [], coveredMessageCount: 0)
    }

    return ChatHistorySummary(
        overview: overview,
        sections: sections,
        coveredMessageCount: coveredMessageCount
    )
}

public func extractOpenAIChatCompletionContent(data: Data) -> Data? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
        return nil
    }
    guard let message = first["message"] as? [String: Any] else {
        return nil
    }

    let contentString: String?
    if let content = message["content"] as? String {
        contentString = content
    } else if let parts = message["content"] as? [[String: Any]] {
        contentString = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    } else {
        contentString = nil
    }

    guard let content = contentString else {
        return nil
    }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return nil
    }
    if let jsonStart = trimmed.firstIndex(of: "{"), let jsonEnd = trimmed.lastIndex(of: "}") {
        let slice = trimmed[jsonStart...jsonEnd]
        return Data(slice.utf8)
    }
    return Data(trimmed.utf8)
}

public func normalizeOpenAICompatibleChatCompletionsURL(baseURL: String) -> URL? {
    var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    if normalized.hasSuffix("/chat/completions") {
        return URL(string: normalized)
    }
    return URL(string: normalized + "/chat/completions")
}

public func chatHistorySummarySourceText(for message: Message) -> String? {
    let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        return trimmed
    }

    for media in message.media {
        if media is TelegramMediaImage {
            return "[photo]"
        }
        if media is TelegramMediaFile {
            return "[file]"
        }
        if media is TelegramMediaWebpage {
            return "[link]"
        }
        if media is TelegramMediaMap {
            return "[location]"
        }
        if media is TelegramMediaContact {
            return "[contact]"
        }
        if media is TelegramMediaAction {
            return nil
        }
    }

    return nil
}

public func loadChatHistorySummarySourceMessages(
    account: Account,
    request: ChatHistorySummaryRequest,
    maxCount: Int
) -> Signal<[ChatHistorySummarySourceMessage], NoError> {
    let takeCount = min(100, max(1, maxCount))

    return account.postbox.aroundMessageHistoryViewForLocation(
        .peer(peerId: request.peerId, threadId: request.threadId),
        anchor: .upperBound,
        ignoreMessagesInTimestampRange: nil,
        ignoreMessageIds: Set(),
        count: takeCount,
        fixedCombinedReadStates: nil,
        topTaggedMessageIdNamespaces: Set(),
        tag: nil,
        appendMessagesFromTheSameGroup: false,
        namespaces: .not(Namespaces.Message.allNonRegular),
        orderStatistics: []
    )
    |> take(1)
    |> map { view, _, _ -> [ChatHistorySummarySourceMessage] in
        var mapped: [ChatHistorySummarySourceMessage] = []
        for entry in view.entries {
            let message = entry.message
            guard let text = chatHistorySummarySourceText(for: message) else {
                continue
            }
            let authorName: String
            if let author = message.author {
                authorName = author.debugDisplayTitle
            } else {
                authorName = "Unknown"
            }
            mapped.append(ChatHistorySummarySourceMessage(
                id: message.id,
                date: message.timestamp,
                authorName: authorName,
                text: text
            ))
        }

        mapped.sort { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id < rhs.id
        }

        if mapped.count > takeCount {
            return Array(mapped.suffix(takeCount))
        }
        return mapped
    }
}

public final class DebugLLMChatHistorySummaryProvider: ChatHistorySummaryProviding {
    private let account: Account
    private let config: DebugLLMChatHistorySummaryConfig
    private let session: URLSession
    private let queue: Queue

    public init(
        account: Account,
        config: DebugLLMChatHistorySummaryConfig,
        session: URLSession = .shared,
        queue: Queue = Queue(name: "ChatHistorySummaryLLM")
    ) {
        self.account = account
        self.config = config
        self.session = session
        self.queue = queue
    }

    public func summary(request: ChatHistorySummaryRequest) -> Signal<ChatHistorySummary, ChatHistorySummaryError> {
        let apiKey = self.config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = self.config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = self.config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty || baseURL.isEmpty || model.isEmpty {
            return .fail(.unavailable)
        }

        let takeCount = self.config.normalizedMaxMessages
        let account = self.account
        let session = self.session
        let queue = self.queue

        return loadChatHistorySummarySourceMessages(account: account, request: request, maxCount: takeCount)
        |> castError(ChatHistorySummaryError.self)
        |> mapToSignal { messages -> Signal<ChatHistorySummary, ChatHistorySummaryError> in
            if messages.isEmpty {
                return .single(ChatHistorySummary(overview: "", sections: [], coveredMessageCount: 0))
            }

            guard let urlRequest = makeOpenAIChatHistorySummaryRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                messages: messages
            ) else {
                return .fail(.unavailable)
            }

            let peerId = request.peerId
            let namespace = messages[0].id.namespace
            let knownIds = Set(messages.map { $0.id.id })
            let covered = Int32(messages.count)

            return Signal { subscriber in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    queue.async {
                        if error != nil {
                            subscriber.putError(.unavailable)
                            return
                        }
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                            subscriber.putError(.unavailable)
                            return
                        }
                        guard let content = extractOpenAIChatCompletionContent(data: data) else {
                            subscriber.putError(.unavailable)
                            return
                        }
                        guard let summary = parseChatHistorySummaryPayload(
                            data: content,
                            peerId: peerId,
                            messageNamespace: namespace,
                            coveredMessageCount: covered,
                            knownMessageIds: knownIds
                        ) else {
                            subscriber.putError(.unavailable)
                            return
                        }
                        subscriber.putNext(summary)
                        subscriber.putCompletion()
                    }
                }
                task.resume()
                return ActionDisposable {
                    task.cancel()
                }
            }
        }
    }
}

private func parseChatHistorySummarySectionKind(_ raw: String?) -> ChatHistorySummary.Section.Kind? {
    switch raw {
    case "keyPoints":
        return .keyPoints
    case "decisions":
        return .decisions
    case "actionItems":
        return .actionItems
    default:
        return nil
    }
}

private func parseCitationMessageId(_ value: Any?) -> Int32? {
    if let number = value as? Int32 {
        return number
    }
    if let number = value as? Int {
        return Int32(number)
    }
    if let number = value as? NSNumber {
        return number.int32Value
    }
    if let string = value as? String, let number = Int32(string) {
        return number
    }
    return nil
}

private func makeOpenAIChatHistorySummaryRequest(
    baseURL: String,
    apiKey: String,
    model: String,
    messages: [ChatHistorySummarySourceMessage]
) -> URLRequest? {
    guard let url = normalizeOpenAICompatibleChatCompletionsURL(baseURL: baseURL) else {
        return nil
    }

    let transcript = messages.map { message in
        "[\(message.id.id)] \(message.authorName): \(message.text)"
    }.joined(separator: "\n")

    let systemPrompt = """
    You summarize unread Telegram chat messages for a user who was away.
    Reply with JSON only, no markdown fences, matching this schema:
    {"overview":"string","sections":[{"kind":"keyPoints|decisions|actionItems","text":"string","citationMessageId":123}]}
    Rules:
    - overview: 1-3 sentences covering the chat while the user was away.
    - sections: 0-7 items. kind must be one of keyPoints, decisions, actionItems.
    - citationMessageId is optional and must be one of the numeric ids in square brackets from the transcript.
    - Match the language of the messages.
    - Do not invent facts that are not in the transcript.
    """

    // Avoid response_format — many OpenRouter free models reject it with 400.
    let body: [String: Any] = [
        "model": model,
        "temperature": 0.2,
        "messages": [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Transcript:\n\(transcript)"]
        ]
    ]

    guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
        return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60.0
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    // OpenRouter optionally uses these; harmless for other OpenAI-compatible hosts.
    request.setValue("https://telegram.org", forHTTPHeaderField: "HTTP-Referer")
    request.setValue("Telegram iOS Chat History Summary Debug", forHTTPHeaderField: "X-Title")
    request.httpBody = bodyData
    return request
}
