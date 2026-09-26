//
//  StopwatchModelTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class StopwatchModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    func test_elapsed_accumulatesAcrossPauses() {
        let model = StopwatchModel()
        model.toggle(at: t0)
        XCTAssertTrue(model.running)
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(5)), 5, accuracy: 0.001)
        model.toggle(at: t0.addingTimeInterval(5))
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(100)), 5, accuracy: 0.001)
        model.toggle(at: t0.addingTimeInterval(100))
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(102)), 7, accuracy: 0.001)
    }

    func test_reset() {
        let model = StopwatchModel()
        model.toggle(at: t0)
        model.reset()
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.hasTime)
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(10)), 0)
    }

    func test_formats() {
        XCTAssertEqual(StopwatchModel.minutesSeconds(65.9), "01:05")
        XCTAssertEqual(StopwatchModel.minutesSeconds(0), "00:00")
        let model = StopwatchModel()
        model.toggle(at: t0)
        XCTAssertEqual(model.formatted(at: t0.addingTimeInterval(61.25)), "01:01.25")
    }
}
