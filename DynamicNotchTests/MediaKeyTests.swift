//
//  MediaKeyTests.swift
//  DynamicNotchTests
//

import AppKit
import XCTest
@testable import DynamicNotch

final class MediaKeyTests: XCTestCase {
    private func data1(code: Int, down: Bool, repeat isRepeat: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }

    func test_decode_knownKeys() {
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true), modifiers: []),
                       MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false, fine: false))
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 1, down: false), modifiers: [])?.key, .volumeDown)
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 7, down: true), modifiers: [])?.key, .mute)
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 2, down: true), modifiers: [])?.key, .brightnessUp)
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 3, down: true), modifiers: [])?.key, .brightnessDown)
    }

    func test_decode_upDownRepeatAndFine() {
        let up = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: false), modifiers: [])
        XCTAssertEqual(up?.isDown, false)
        let rep = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true, repeat: true), modifiers: [])
        XCTAssertEqual(rep?.isRepeat, true)
        let fine = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true), modifiers: [.option, .shift])
        XCTAssertEqual(fine?.fine, true)
        let optionOnly = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true), modifiers: [.option])
        XCTAssertEqual(optionOnly?.fine, false)
    }

    func test_decode_ignoresOtherEvents() {
        XCTAssertNil(MediaKeyEvent.decode(subtype: 7, data1: data1(code: 0, down: true), modifiers: []))
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 16, down: true), modifiers: []), "lecture/pause")
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 21, down: true), modifiers: []), "rétroéclairage clavier")
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: (0 << 16) | (0x0C << 8), modifiers: []), "état inconnu")
    }

    func test_levelStep() {
        XCTAssertEqual(LevelStep.next(level: 0.5, up: true, fine: false), 0.5625)
        XCTAssertEqual(LevelStep.next(level: 0.5, up: false, fine: false), 0.4375)
        XCTAssertEqual(LevelStep.next(level: 0.5, up: true, fine: true), 0.515625)
        XCTAssertEqual(LevelStep.next(level: 0.51, up: true, fine: false), 0.5625, "recalé sur la grille")
        XCTAssertEqual(LevelStep.next(level: 0.99, up: true, fine: false), 1)
        XCTAssertEqual(LevelStep.next(level: 0, up: false, fine: false), 0)
    }

    func test_hudIcon() {
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.5, isMuted: true), "speaker.slash.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0, isMuted: false), "speaker.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.2, isMuted: false), "speaker.wave.1.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.5, isMuted: false), "speaker.wave.2.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.9, isMuted: false), "speaker.wave.3.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .brightness, level: 0.3, isMuted: false), "sun.min.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .brightness, level: 0.7, isMuted: false), "sun.max.fill")
    }

    func test_hudState_percent() {
        XCTAssertEqual(HUDState(kind: .volume, level: 0.625).percent, 63)
        XCTAssertEqual(HUDState(kind: .brightness, level: 1).percent, 100)
    }
}
