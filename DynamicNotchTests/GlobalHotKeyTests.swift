//
//  GlobalHotKeyTests.swift
//  DynamicNotchTests
//

import Carbon.HIToolbox
@testable import DynamicNotch
import XCTest

final class GlobalHotKeyTests: XCTestCase {
    func test_toggleCombo_isControlOptionN() {
        let combo = HotKeyCombo.toggleNotch
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(combo.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(combo.symbols, "⌃⌥N")
    }

    @MainActor
    func test_unregister_withoutRegister_isNoop() {
        let hotKey = GlobalHotKey(combo: .toggleNotch) {}
        hotKey.unregister()
        XCTAssertFalse(hotKey.isRegistered)
    }
}
