//
//  PomodoroProgressTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

@MainActor
final class PomodoroProgressTests: XCTestCase {
    func test_progress_isContinuousWhileRunning() {
        let model = PomodoroModel()
        XCTAssertEqual(model.progress(at: Date()), 0)
        model.performPrimary()
        let total = model.phaseTotal
        let later = Date().addingTimeInterval(total / 4)
        XCTAssertEqual(model.progress(at: later), 0.25, accuracy: 0.01)
        model.reset()
    }
}
