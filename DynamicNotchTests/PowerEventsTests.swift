//
//  PowerEventsTests.swift
//  DynamicNotchTests
//

import IOKit.ps
import XCTest
@testable import DynamicNotch

final class PowerEventsTests: XCTestCase {
    private func battery(_ capacity: Int, ac: Bool, charging: Bool = false, timeToFull: Int = -1) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: capacity,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: ac ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: charging,
            kIOPSTimeToFullChargeKey: timeToFull,
        ]
    }

    private func snapshot(_ percent: Int, ac: Bool) -> PowerSnapshot {
        PowerSnapshot(hasBattery: true, level: Double(percent) / 100, isPluggedIn: ac, isCharging: ac, minutesToFull: nil)
    }

    // MARK: parse

    func test_parse_internalBattery() {
        let s = PowerSnapshot.parse([battery(82, ac: true, charging: true, timeToFull: 70)])
        XCTAssertEqual(s, PowerSnapshot(hasBattery: true, level: 0.82, isPluggedIn: true, isCharging: true, minutesToFull: 70))
        XCTAssertEqual(s.percent, 82)
    }

    func test_parse_unknownTimeToFull_isNil() {
        XCTAssertNil(PowerSnapshot.parse([battery(50, ac: true, timeToFull: -1)]).minutesToFull)
    }

    func test_parse_noBattery() {
        let s = PowerSnapshot.parse([[kIOPSTypeKey: "UPS"]])
        XCTAssertFalse(s.hasBattery)
        XCTAssertTrue(s.isPluggedIn)
    }

    // MARK: detector

    func test_firstSnapshot_emitsNothing() {
        var detector = PowerEventDetector()
        XCTAssertEqual(detector.process(snapshot(15, ac: false)), [])
    }

    func test_plugAndUnplugEdges() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(60, ac: false))
        XCTAssertEqual(detector.process(snapshot(60, ac: true)), [.pluggedIn])
        XCTAssertEqual(detector.process(snapshot(61, ac: true)), [])
        XCTAssertEqual(detector.process(snapshot(61, ac: false)), [.unplugged])
    }

    func test_lowBattery_firesOncePerThreshold() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(21, ac: false))
        XCTAssertEqual(detector.process(snapshot(20, ac: false)), [.lowBattery(percent: 20)])
        XCTAssertEqual(detector.process(snapshot(19, ac: false)), [])
        XCTAssertEqual(detector.process(snapshot(10, ac: false)), [.lowBattery(percent: 10)])
        XCTAssertEqual(detector.process(snapshot(9, ac: false)), [])
    }

    func test_launchBelowThreshold_doesNotWarnUntilNextThreshold() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(15, ac: false))
        XCTAssertEqual(detector.process(snapshot(14, ac: false)), [])
        XCTAssertEqual(detector.process(snapshot(10, ac: false)), [.lowBattery(percent: 10)])
    }

    func test_unplugBelowThreshold_onlyEmitsUnplugged() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(15, ac: true))
        XCTAssertEqual(detector.process(snapshot(15, ac: false)), [.unplugged])
        XCTAssertEqual(detector.process(snapshot(10, ac: false)), [.lowBattery(percent: 10)])
    }

    func test_crossingTwoThresholdsAtOnce_emitsOnce() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(21, ac: false))
        XCTAssertEqual(detector.process(snapshot(9, ac: false)), [.lowBattery(percent: 9)])
        XCTAssertEqual(detector.process(snapshot(8, ac: false)), [])
    }
}
