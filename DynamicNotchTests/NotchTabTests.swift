//
//  NotchTabTests.swift
//  DynamicNotchTests
//

import SwiftUI
import XCTest
@testable import DynamicNotch

final class NotchTabTests: XCTestCase {
    func test_order_andSymbols() {
        XCTAssertEqual(NotchTab.allCases, [.home, .files, .timers, .notes, .agenda])
        XCTAssertEqual(NotchTab.allCases.map(\.systemImage), ["house.fill", "tray.full.fill", "timer", "note.text", "calendar"])
    }

    func test_panelHeights() {
        XCTAssertEqual(NotchTab.home.panelHeight, 190)
        XCTAssertEqual(NotchTab.files.panelHeight, 190)
        XCTAssertEqual(NotchTab.timers.panelHeight, 190)
        XCTAssertEqual(NotchTab.notes.panelHeight, 220)
        XCTAssertEqual(NotchTab.agenda.panelHeight, 260)
    }

    func test_slideEdge_followsNavigationDirection() {
        XCTAssertEqual(NotchTab.slideEdge(from: .home, to: .agenda), .trailing)
        XCTAssertEqual(NotchTab.slideEdge(from: .agenda, to: .files), .leading)
        XCTAssertEqual(NotchTab.slideEdge(from: .notes, to: .notes), .trailing)
    }
}
