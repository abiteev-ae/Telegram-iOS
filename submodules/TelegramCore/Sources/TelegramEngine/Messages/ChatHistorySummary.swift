import Foundation
import SwiftSignalKit

public struct ChatHistorySummaryRequest: Equatable {
    public let peerId: EnginePeer.Id
    public let threadId: Int64?
    /// How many recent messages (read or unread) to consider.
    public let messageLimit: Int32
    public let previewMessageIds: [EngineMessage.Id]

    public init(
        peerId: EnginePeer.Id,
        threadId: Int64?,
        messageLimit: Int32,
        previewMessageIds: [EngineMessage.Id]
    ) {
        self.peerId = peerId
        self.threadId = threadId
        self.messageLimit = messageLimit
        self.previewMessageIds = previewMessageIds
    }
}

public struct ChatHistorySummary: Equatable {
    public struct Item: Equatable {
        public let text: String
        public let messageId: EngineMessage.Id?

        public init(text: String, messageId: EngineMessage.Id? = nil) {
            self.text = text
            self.messageId = messageId
        }
    }

    public let overview: String
    public let keyPoints: [Item]
    public let decisions: [Item]
    public let actionItems: [Item]
    public let suggestedReplies: [String]
    public let coveredMessageCount: Int32

    public init(
        overview: String,
        keyPoints: [Item] = [],
        decisions: [Item] = [],
        actionItems: [Item] = [],
        suggestedReplies: [String] = [],
        coveredMessageCount: Int32
    ) {
        self.overview = overview
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.suggestedReplies = suggestedReplies
        self.coveredMessageCount = coveredMessageCount
    }

    public var isEmpty: Bool {
        return self.overview.isEmpty
            && self.keyPoints.isEmpty
            && self.decisions.isEmpty
            && self.actionItems.isEmpty
            && self.suggestedReplies.isEmpty
    }

    /// Plain-text dump for the clipboard.
    public var copyableText: String {
        var parts: [String] = []
        let trimmedOverview = self.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverview.isEmpty {
            parts.append(trimmedOverview)
        }
        if !self.keyPoints.isEmpty {
            parts.append((["Key Points:"] + self.keyPoints.map { "• \($0.text)" }).joined(separator: "\n"))
        }
        if !self.decisions.isEmpty {
            parts.append((["Decisions:"] + self.decisions.map { "• \($0.text)" }).joined(separator: "\n"))
        }
        if !self.actionItems.isEmpty {
            parts.append((["Action Items:"] + self.actionItems.map { "○ \($0.text)" }).joined(separator: "\n"))
        }
        if !self.suggestedReplies.isEmpty {
            parts.append((["Suggested Replies:"] + self.suggestedReplies.map { "• \($0)" }).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

public enum ChatHistorySummaryError: Error, Equatable {
    case unavailable
}

public protocol ChatHistorySummaryProviding: AnyObject {
    func summary(request: ChatHistorySummaryRequest) -> Signal<ChatHistorySummary, ChatHistorySummaryError>
}

public enum ChatHistorySummaryState: Equatable {
    case idle
    case loading(requestId: Int64)
    case ready(requestId: Int64, summary: ChatHistorySummary)
    case empty(requestId: Int64)
    case failed(requestId: Int64, error: ChatHistorySummaryError)

    fileprivate var requestId: Int64? {
        switch self {
        case .idle:
            return nil
        case let .loading(requestId), let .ready(requestId, _), let .empty(requestId), let .failed(requestId, _):
            return requestId
        }
    }
}

public enum ChatHistorySummaryEvent: Equatable {
    case start(requestId: Int64)
    case result(requestId: Int64, summary: ChatHistorySummary)
    case failure(requestId: Int64, error: ChatHistorySummaryError)
    case cancel(requestId: Int64)
}

public func reduceChatHistorySummaryState(
    state: ChatHistorySummaryState,
    event: ChatHistorySummaryEvent
) -> ChatHistorySummaryState {
    switch event {
    case let .start(requestId):
        return .loading(requestId: requestId)
    case let .result(requestId, summary):
        guard state.requestId == requestId else {
            return state
        }
        if summary.isEmpty {
            return .empty(requestId: requestId)
        } else {
            return .ready(requestId: requestId, summary: summary)
        }
    case let .failure(requestId, error):
        guard state.requestId == requestId else {
            return state
        }
        return .failed(requestId: requestId, error: error)
    case let .cancel(requestId):
        guard state.requestId == requestId else {
            return state
        }
        return .idle
    }
}

public final class MockChatHistorySummaryProvider: ChatHistorySummaryProviding {
    public enum Scenario {
        case success
        case empty
        case failure
    }

    private let scenario: Scenario
    private let responseDelay: Double
    private let queue: Queue

    public init(scenario: Scenario = .success, delay: Double = 0.45, queue: Queue = .mainQueue()) {
        self.scenario = scenario
        self.responseDelay = delay
        self.queue = queue
    }

    public func summary(request: ChatHistorySummaryRequest) -> Signal<ChatHistorySummary, ChatHistorySummaryError> {
        let signal: Signal<ChatHistorySummary, ChatHistorySummaryError>
        switch self.scenario {
        case .success:
            let citationId = request.previewMessageIds.last
            signal = .single(ChatHistorySummary(
                overview: "За время вашего отсутствия команда обсудила подготовку следующего релиза, согласовала сроки и распределила оставшиеся задачи.",
                keyPoints: [
                    ChatHistorySummary.Item(text: "Новая версия запланирована на пятницу.", messageId: citationId),
                    ChatHistorySummary.Item(text: "Перед публикацией будет финальная проверка сборки."),
                    ChatHistorySummary.Item(text: "Описание релиза обновят вместе с билдом.")
                ],
                decisions: [
                    ChatHistorySummary.Item(text: "Релиз не переносят.", messageId: citationId),
                    ChatHistorySummary.Item(text: "Экспериментальную аналитику включат только для внутренней группы.")
                ],
                actionItems: [
                    ChatHistorySummary.Item(text: "Проверить критические сценарии."),
                    ChatHistorySummary.Item(text: "Подготовить список изменений."),
                    ChatHistorySummary.Item(text: "Подтвердить готовность сборки до конца четверга.", messageId: citationId)
                ],
                suggestedReplies: [
                    "Отлично, держите в курсе по сборке.",
                    "Могу помочь с описанием релиза — напишите, что нужно."
                ],
                coveredMessageCount: max(1, request.messageLimit)
            ))
        case .empty:
            signal = .single(ChatHistorySummary(overview: "", coveredMessageCount: 0))
        case .failure:
            signal = .fail(.unavailable)
        }

        if self.responseDelay == 0.0 {
            return signal
        } else {
            return signal |> delay(self.responseDelay, queue: self.queue)
        }
    }
}
