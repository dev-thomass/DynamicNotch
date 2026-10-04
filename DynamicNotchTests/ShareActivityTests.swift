//
//  ShareActivityTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class ShareActivityTests: XCTestCase {
    func test_sendingState_isBalanced() {
        let activity = ShareActivity()
        XCTAssertFalse(activity.isSending)
        activity.begin()
        activity.begin()
        XCTAssertTrue(activity.isSending)
        activity.end()
        XCTAssertTrue(activity.isSending)
        activity.end()
        activity.end()
        XCTAssertFalse(activity.isSending)
    }
}
