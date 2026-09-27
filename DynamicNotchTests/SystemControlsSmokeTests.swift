//
//  SystemControlsSmokeTests.swift
//  DynamicNotchTests
//
//  Lecture seule : ces tests ne modifient jamais le volume ni la luminosité.
//

import XCTest
@testable import DynamicNotch

@MainActor
final class SystemControlsSmokeTests: XCTestCase {
    func test_volume_readsWithinRange() {
        let volume = CoreAudioVolumeControl()
        XCTAssertTrue((0 ... 1).contains(volume.level))
        _ = volume.isMuted
        _ = volume.isSettable
        _ = volume.isMuteSettable
    }

    func test_brightness_readsWithinRange_whenAvailable() {
        let brightness = DisplayServicesBrightnessControl()
        if brightness.isAvailable {
            XCTAssertTrue((0 ... 1).contains(brightness.level))
        } else {
            XCTAssertEqual(brightness.level, 0)
        }
    }
}
