//
//  PomodoroNotifierTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class PomodoroNotifierTests: XCTestCase {
    func test_idle_hasNoMessage() {
        XCTAssertNil(PomodoroNotifier.message(enteringPhase: .idle, minutes: 0))
    }

    func test_breakEnd_announcesFocus() {
        let message = PomodoroNotifier.message(enteringPhase: .work, minutes: 25)
        XCTAssertEqual(message?.title, "Pause terminée")
        XCTAssertEqual(message?.body, "On reprend : 25 min de focus.")
    }

    func test_focusEnd_announcesBreakLength() {
        XCTAssertEqual(PomodoroNotifier.message(enteringPhase: .shortBreak, minutes: 5)?.body, "Pause de 5 min.")
        XCTAssertEqual(
            PomodoroNotifier.message(enteringPhase: .longBreak, minutes: 15)?.body,
            "Pause longue de 15 min, bien méritée."
        )
    }
}
