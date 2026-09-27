//
//  HUDControllerTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class HUDControllerTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var hud: HUDController!

    override func setUp() async throws {
        scheduler = ManualScheduler()
        hud = HUDController(scheduler: scheduler)
    }

    func test_show_thenHidesAfterDuration() {
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(hud.current, HUDState(kind: .volume, level: 0.5))
        scheduler.advance(by: 1.4)
        XCTAssertNotNil(hud.current)
        scheduler.advance(by: 0.2)
        XCTAssertNil(hud.current)
        XCTAssertEqual(hud.lastShown, HUDState(kind: .volume, level: 0.5), "gardé pour la sortie animée")
    }

    func test_eachShow_extends() {
        hud.show(HUDState(kind: .volume, level: 0.5))
        scheduler.advance(by: 1.4)
        hud.show(HUDState(kind: .volume, level: 0.5625))
        scheduler.advance(by: 1.4)
        XCTAssertEqual(hud.current?.level, 0.5625)
        scheduler.advance(by: 0.2)
        XCTAssertNil(hud.current)
    }

    func test_observers_notifiedOnChanges_only() {
        var received: [HUDState?] = []
        let observation = hud.observe { received.append($0) }
        hud.show(HUDState(kind: .volume, level: 0.5))
        hud.show(HUDState(kind: .volume, level: 0.5))
        hud.show(HUDState(kind: .brightness, level: 0.3))
        scheduler.advance(by: 1.5)
        hud.hide()
        XCTAssertEqual(received, [
            HUDState(kind: .volume, level: 0.5),
            HUDState(kind: .brightness, level: 0.3),
            nil,
        ])
        observation.cancel()
    }
}
