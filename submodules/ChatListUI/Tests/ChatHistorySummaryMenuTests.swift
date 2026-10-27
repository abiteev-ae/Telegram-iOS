import XCTest
@testable import ChatListUI

final class ChatHistorySummaryMenuTests: XCTestCase {
    func testSummaryMenuRequiresSafetyGatesButNotUnread() {
        XCTAssertTrue(canDisplayMockChatHistorySummary(
            isInternalBuild: true,
            isEnabled: true,
            isChatListSource: true,
            isCommunity: false,
            isPromo: false
        ))

        let unavailableVariants: [(Bool, Bool, Bool, Bool, Bool)] = [
            (false, true, true, false, false),
            (true, false, true, false, false),
            (true, true, false, false, false),
            (true, true, true, true, false),
            (true, true, true, false, true)
        ]

        for variant in unavailableVariants {
            XCTAssertFalse(canDisplayMockChatHistorySummary(
                isInternalBuild: variant.0,
                isEnabled: variant.1,
                isChatListSource: variant.2,
                isCommunity: variant.3,
                isPromo: variant.4
            ))
        }
    }
}
