//
//  PomodoroModelTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class PomodoroModelTests: XCTestCase {
    func test_skip_reportsPhaseChange_notNaturalEnd() {
        let model = PomodoroModel()
        var events: [(PomodoroModel.Phase, Bool)] = []
        model.onPhaseChange = { events.append(($0, $1)) }

        model.performPrimary()
        XCTAssertEqual(model.phase, .work)
        XCTAssertTrue(events.isEmpty, "démarrer n'est pas une fin de phase")

        model.skip()
        XCTAssertNotEqual(model.phase, .work)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.0, model.phase)
        XCTAssertEqual(events.first?.1, false)
        model.reset()
    }

    func test_activityTitles() {
        XCTAssertEqual(PomodoroModel.Phase.work.activityTitle, "Au travail")
        XCTAssertEqual(PomodoroModel.Phase.shortBreak.activityTitle, "Pause")
        XCTAssertEqual(PomodoroModel.Phase.longBreak.activityTitle, "Pause longue")
    }
}
