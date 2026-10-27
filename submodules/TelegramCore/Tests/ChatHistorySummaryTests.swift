import XCTest
import SwiftSignalKit
@testable import TelegramCore

final class ChatHistorySummaryTests: XCTestCase {
    private let peerId = EnginePeer.Id(
        namespace: Namespaces.Peer.CloudGroup,
        id: EnginePeer.Id.Id._internalFromInt64Value(1)
    )

    func testResultMovesLoadingStateToReady() {
        let summary = ChatHistorySummary(
            overview: "Overview",
            sections: [
                ChatHistorySummary.Section(kind: .keyPoints, text: "Key point", citation: nil)
            ],
            coveredMessageCount: 12
        )

        let loading = reduceChatHistorySummaryState(state: .idle, event: .start(requestId: 1))
        let ready = reduceChatHistorySummaryState(
            state: loading,
            event: .result(requestId: 1, summary: summary)
        )

        XCTAssertEqual(ready, .ready(requestId: 1, summary: summary))
    }

    func testEmptyResultMovesLoadingStateToEmpty() {
        let loading = reduceChatHistorySummaryState(state: .idle, event: .start(requestId: 2))
        let empty = reduceChatHistorySummaryState(
            state: loading,
            event: .result(
                requestId: 2,
                summary: ChatHistorySummary(overview: "", sections: [], coveredMessageCount: 0)
            )
        )

        XCTAssertEqual(empty, .empty(requestId: 2))
    }

    func testStaleResultIsIgnored() {
        let loading = ChatHistorySummaryState.loading(requestId: 3)
        let staleSummary = ChatHistorySummary(
            overview: "Stale",
            sections: [],
            coveredMessageCount: 1
        )

        let result = reduceChatHistorySummaryState(
            state: loading,
            event: .result(requestId: 2, summary: staleSummary)
        )

        XCTAssertEqual(result, loading)
    }

    func testCancellationOnlyCancelsCurrentRequest() {
        let loading = ChatHistorySummaryState.loading(requestId: 4)

        XCTAssertEqual(
            reduceChatHistorySummaryState(state: loading, event: .cancel(requestId: 3)),
            loading
        )
        XCTAssertEqual(
            reduceChatHistorySummaryState(state: loading, event: .cancel(requestId: 4)),
            .idle
        )
    }

    func testMockProviderUsesPreviewMessageForCitation() {
        let messageId = EngineMessage.Id(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 10)
        let request = ChatHistorySummaryRequest(
            peerId: self.peerId,
            threadId: nil,
            messageLimit: 30,
            previewMessageIds: [messageId]
        )
        let provider = MockChatHistorySummaryProvider(delay: 0.0)
        let expectation = self.expectation(description: "Mock summary")

        let disposable = provider.summary(request: request).start(next: { summary in
            XCTAssertEqual(summary.coveredMessageCount, 30)
            XCTAssertEqual(summary.sections.first?.citation?.messageId, messageId)
            expectation.fulfill()
        })

        self.wait(for: [expectation], timeout: 1.0)
        disposable.dispose()
    }

    func testParsesSummaryPayloadAndDropsUnknownCitations() {
        let payload: [String: Any] = [
            "overview": "Team aligned on the release.",
            "sections": [
                [
                    "kind": "keyPoints",
                    "text": "Ship on Friday.",
                    "citationMessageId": 10
                ],
                [
                    "kind": "decisions",
                    "text": "Keep the current scope.",
                    "citationMessageId": 999
                ],
                [
                    "kind": "unknown",
                    "text": "Should be ignored"
                ]
            ]
        ]

        let summary = parseChatHistorySummaryPayload(
            object: payload,
            peerId: self.peerId,
            messageNamespace: Namespaces.Message.Cloud,
            coveredMessageCount: 4,
            knownMessageIds: [10, 11]
        )

        XCTAssertEqual(summary?.overview, "Team aligned on the release.")
        XCTAssertEqual(summary?.coveredMessageCount, 4)
        XCTAssertEqual(summary?.sections.count, 2)
        XCTAssertEqual(summary?.sections[0].kind, .keyPoints)
        XCTAssertEqual(
            summary?.sections[0].citation?.messageId,
            EngineMessage.Id(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 10)
        )
        XCTAssertEqual(summary?.sections[1].kind, .decisions)
        XCTAssertNil(summary?.sections[1].citation)
    }

    func testExtractsOpenAIChatCompletionJSONContent() throws {
        let nested = #"{"overview":"Hi","sections":[]}"#
        let envelope: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "content": "```json\n\(nested)\n```"
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [])
        let content = extractOpenAIChatCompletionContent(data: data)
        let object = try XCTUnwrap(content).withUnsafeBytes { buffer -> [String: Any]? in
            return try? JSONSerialization.jsonObject(with: Data(buffer)) as? [String: Any]
        }

        XCTAssertEqual(object?["overview"] as? String, "Hi")
    }

    func testNormalizesOpenAICompatibleBaseURLWithoutDoublingPath() {
        XCTAssertEqual(
            normalizeOpenAICompatibleChatCompletionsURL(baseURL: "https://openrouter.ai/api/v1")?.absoluteString,
            "https://openrouter.ai/api/v1/chat/completions"
        )
        XCTAssertEqual(
            normalizeOpenAICompatibleChatCompletionsURL(baseURL: "https://openrouter.ai/api/v1/")?.absoluteString,
            "https://openrouter.ai/api/v1/chat/completions"
        )
        XCTAssertEqual(
            normalizeOpenAICompatibleChatCompletionsURL(baseURL: "https://openrouter.ai/api/v1/chat/completions")?.absoluteString,
            "https://openrouter.ai/api/v1/chat/completions"
        )
    }
}
