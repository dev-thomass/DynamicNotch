//
//  ActivityWiringTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

@MainActor
final class ActivityWiringTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10000)

    private func inputs(
        wings: Bool = true,
        plugged: Bool = false,
        hasBattery: Bool = true,
        stopwatch: Bool = false,
        pomodoro: Bool = false,
        music: Bool = false,
        eventIn minutes: Double? = nil
    ) -> ActivityWiring.Inputs {
        ActivityWiring.Inputs(
            wingsEnabled: wings, wingBattery: true, wingStopwatch: true, wingPomodoro: true, wingCalendar: true,
            battery: PowerSnapshot(
                hasBattery: hasBattery,
                level: 0.5,
                isPluggedIn: plugged,
                isCharging: plugged,
                minutesToFull: nil
            ),
            stopwatchHasTime: stopwatch, pomodoroActive: pomodoro, musicPlaying: music,
            nextEventStart: minutes.map { now.addingTimeInterval($0 * 60) }, now: now
        )
    }

    func test_nothingActive() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs()), [])
    }

    func test_charging_onlyWithBattery() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(plugged: true)), [.charging])
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(plugged: true, hasBattery: false)), [])
    }

    func test_wingsDisabled_disablesEverything() {
        XCTAssertEqual(
            ActivityWiring.activePersistent(inputs(wings: false, plugged: true, stopwatch: true, music: true)),
            []
        )
    }

    func test_timersAndMusic() {
        XCTAssertEqual(
            ActivityWiring.activePersistent(inputs(stopwatch: true, pomodoro: true, music: true)),
            [.stopwatch, .pomodoroPhase, .nowPlaying]
        )
    }

    func test_calendar_withinTheHourOnly() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(eventIn: 30)), [.calendarSoon])
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(eventIn: 90)), [])
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(eventIn: -5)), [])
    }

    func test_powerEventMapping() {
        XCTAssertEqual(ActivityWiring.activity(for: .pluggedIn), .charging)
        XCTAssertEqual(ActivityWiring.activity(for: .unplugged), .unplugged)
        XCTAssertEqual(ActivityWiring.activity(for: .lowBattery(percent: 10)), .lowBattery(percent: 10))
    }
}
