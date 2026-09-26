//
//  ActivityCenterTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

/// Minuterie manuelle : `advance(by:)` exécute de façon synchrone les travaux échus.
@MainActor
final class ManualScheduler: ActivityScheduler {
    private final class Job {
        let fireAt: Date
        let action: @MainActor () -> Void
        var cancelled = false
        init(fireAt: Date, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.action = action
        }
    }

    private(set) var now = Date(timeIntervalSince1970: 1_000)
    private var jobs: [Job] = []

    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let job = Job(fireAt: now.addingTimeInterval(seconds), action: action)
        jobs.append(job)
        return ScheduledWork { job.cancelled = true }
    }

    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = jobs.filter({ !$0.cancelled && $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            now = next.fireAt
            next.cancelled = true
            next.action()
        }
        now = target
    }
}

@MainActor
final class ActivityCenterTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var center: ActivityCenter!

    override func setUp() async throws {
        scheduler = ManualScheduler()
        center = ActivityCenter(scheduler: scheduler)
    }

    func test_transient_expandsThenClears() {
        center.post(.charging)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .expanded))
        scheduler.advance(by: 2.1)
        XCTAssertNotNil(center.current)
        scheduler.advance(by: 0.2)
        XCTAssertNil(center.current)
    }

    func test_transient_collapsesToPersistent() {
        center.setPersistent(.charging, active: true)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .compact))
        center.post(.charging)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .expanded))
        scheduler.advance(by: 2.2)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .compact))
    }

    func test_persistentPriorities() {
        center.setPersistent(.charging, active: true)
        center.setPersistent(.stopwatch, active: true)
        XCTAssertEqual(center.current?.id, .stopwatch)
        center.setPersistent(.pomodoroPhase, active: true)
        XCTAssertEqual(center.current?.id, .pomodoroPhase)
        center.setPersistent(.pomodoroPhase, active: false)
        XCTAssertEqual(center.current?.id, .stopwatch)
    }

    func test_transientsAreQueued_inArrivalOrder() {
        center.post(.filesAdded(count: 2))
        center.post(.airDropSent)
        XCTAssertEqual(center.current?.id, .filesAdded(count: 2))
        scheduler.advance(by: 1.2)
        XCTAssertEqual(center.current?.id, .airDropSent)
        scheduler.advance(by: 1.2)
        XCTAssertNil(center.current)
    }

    func test_staleQueuedTransient_isDropped() {
        center.post(.lowBattery(percent: 10)) // 3 s
        center.post(.charging)                // attend 3 s, dure 2,2 s
        center.post(.unplugged)               // attend 5,2 s → abandonné
        scheduler.advance(by: 3)
        XCTAssertEqual(center.current?.id, .charging)
        scheduler.advance(by: 2.2)
        XCTAssertNil(center.current)
    }

    func test_sameTransient_extendsInsteadOfQueuing() {
        center.post(.charging)
        scheduler.advance(by: 2)
        center.post(.charging)
        scheduler.advance(by: 1)
        XCTAssertEqual(center.current?.id, .charging)
        scheduler.advance(by: 1.3)
        XCTAssertNil(center.current)
    }

    func test_suspension_dropsTransients_butKeepsPersistent() {
        center.setPersistent(.stopwatch, active: true)
        center.post(.charging)
        center.beginSuspension()
        XCTAssertEqual(center.current, ActivityDisplay(id: .stopwatch, mode: .compact))
        center.post(.airDropSent)
        XCTAssertEqual(center.current?.mode, .compact)
        center.endSuspension()
        XCTAssertFalse(center.isSuspended)
        scheduler.advance(by: 5)
        XCTAssertEqual(center.current, ActivityDisplay(id: .stopwatch, mode: .compact))
    }

    func test_observers_notifiedOncePerChange() {
        var received: [ActivityDisplay?] = []
        let observation = center.observe { received.append($0) }
        center.setPersistent(.charging, active: true)
        center.setPersistent(.charging, active: true)
        center.post(.charging)
        scheduler.advance(by: 2.2)
        XCTAssertEqual(received, [
            ActivityDisplay(id: .charging, mode: .compact),
            ActivityDisplay(id: .charging, mode: .expanded),
            ActivityDisplay(id: .charging, mode: .compact),
        ])
        observation.cancel()
        center.setPersistent(.charging, active: false)
        XCTAssertEqual(received.count, 3)
    }
}
