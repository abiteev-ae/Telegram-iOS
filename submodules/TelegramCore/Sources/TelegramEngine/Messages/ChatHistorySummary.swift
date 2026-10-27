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
    public struct Citation: Equatable {
        public let title: String
        public let messageId: EngineMessage.Id

        public init(title: String, messageId: EngineMessage.Id) {
            self.title = title
            self.messageId = messageId
        }
    }

    public struct Section: Equatable {
        public enum Kind: Equatable {
            case keyPoints
            case decisions
            case actionItems
        }

        public let kind: Kind
        public let text: String
        public let citation: Citation?

        public init(kind: Kind, text: String, citation: Citation?) {
            self.kind = kind
            self.text = text
            self.citation = citation
        }
    }

    public let overview: String
    public let sections: [Section]
    public let coveredMessageCount: Int32

    public init(overview: String, sections: [Section], coveredMessageCount: Int32) {
        self.overview = overview
        self.sections = sections
        self.coveredMessageCount = coveredMessageCount
    }

    public var isEmpty: Bool {
        return self.overview.isEmpty && self.sections.isEmpty
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
            let citation = request.previewMessageIds.last.map {
                ChatHistorySummary.Citation(title: "Перейти к обсуждению", messageId: $0)
            }
            signal = .single(ChatHistorySummary(
                overview: "За время вашего отсутствия команда обсудила подготовку следующего релиза, согласовала сроки и распределила оставшиеся задачи.",
                sections: [
                    ChatHistorySummary.Section(
                        kind: .keyPoints,
                        text: "Новая версия запланирована на пятницу. Перед публикацией команда проведёт финальную проверку сборки и обновит описание релиза.",
                        citation: citation
                    ),
                    ChatHistorySummary.Section(
                        kind: .decisions,
                        text: "Решили не переносить релиз и оставить текущий набор функций. Экспериментальную аналитику включат только для внутренней группы.",
                        citation: nil
                    ),
                    ChatHistorySummary.Section(
                        kind: .actionItems,
                        text: "Проверить критические сценарии, подготовить список изменений и подтвердить готовность сборки до конца четверга.",
                        citation: nil
                    )
                ],
                coveredMessageCount: max(1, request.messageLimit)
            ))
        case .empty:
            signal = .single(ChatHistorySummary(overview: "", sections: [], coveredMessageCount: 0))
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
