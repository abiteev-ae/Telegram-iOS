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
            unreadCount: 300,
            previewMessageIds: [messageId]
        )
        let provider = MockChatHistorySummaryProvider(delay: 0.0)
        let expectation = self.expectation(description: "Mock summary")

        let disposable = provider.summary(request: request).start(next: { summary in
            XCTAssertEqual(summary.coveredMessageCount, 300)
            XCTAssertEqual(summary.sections.first?.citation?.messageId, messageId)
            expectation.fulfill()
        })

        self.wait(for: [expectation], timeout: 1.0)
        disposable.dispose()
    }
}
