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
            keyPoints: [ChatHistorySummary.Item(text: "Key point")],
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
                summary: ChatHistorySummary(overview: "", coveredMessageCount: 0)
            )
        )

        XCTAssertEqual(empty, .empty(requestId: 2))
    }

    func testStaleResultIsIgnored() {
        let loading = ChatHistorySummaryState.loading(requestId: 3)
        let staleSummary = ChatHistorySummary(
            overview: "Stale",
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

    func testMockProviderReturnsBulletsAndSuggestedReplies() {
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
            XCTAssertFalse(summary.keyPoints.isEmpty)
            XCTAssertFalse(summary.actionItems.isEmpty)
            XCTAssertEqual(summary.suggestedReplies.count, 2)
            XCTAssertEqual(summary.keyPoints.first?.messageId, messageId)
            XCTAssertFalse(summary.copyableText.isEmpty)
            expectation.fulfill()
        })

        self.wait(for: [expectation], timeout: 1.0)
        disposable.dispose()
    }

    func testParsesItemObjectsAndPlainStrings() {
        let longReply = String(repeating: "a", count: 200)
        let payload: [String: Any] = [
            "overview": "Team aligned on the release.",
            "keyPoints": [
                ["text": "Ship on Friday.", "citationMessageId": 10],
                "Update release notes.",
                ["text": "  "],
                ["text": "Unknown citation", "citationMessageId": 999]
            ],
            "decisions": [
                ["text": "Keep the current scope.", "citationMessageId": 11]
            ],
            "actionItems": ["Verify critical flows."],
            "suggestedReplies": ["Sounds good.", longReply, "Third", "Fourth ignored"]
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
        XCTAssertEqual(summary?.keyPoints.count, 3)
        XCTAssertEqual(summary?.keyPoints[0].text, "Ship on Friday.")
        XCTAssertEqual(
            summary?.keyPoints[0].messageId,
            EngineMessage.Id(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 10)
        )
        XCTAssertEqual(summary?.keyPoints[1].text, "Update release notes.")
        XCTAssertNil(summary?.keyPoints[1].messageId)
        XCTAssertEqual(summary?.keyPoints[2].text, "Unknown citation")
        XCTAssertNil(summary?.keyPoints[2].messageId)
        XCTAssertEqual(summary?.decisions.first?.messageId?.id, 11)
        XCTAssertEqual(summary?.actionItems.first?.text, "Verify critical flows.")
        XCTAssertEqual(summary?.suggestedReplies.count, 3)
        XCTAssertEqual(summary?.suggestedReplies[1].count, 120)
    }

    func testExtractsOpenAIChatCompletionJSONContent() throws {
        let nested = #"{"overview":"Hi","keyPoints":[],"decisions":[],"actionItems":[],"suggestedReplies":[]}"#
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
