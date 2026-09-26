//
//  NotchPresentationTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class NotchPresentationTests: XCTestCase {
    private let notch = CGSize(width: 185, height: 32)

    private func metrics(_ p: NotchPresentation, hardware: Bool = true) -> ShellMetrics {
        p.metrics(notch: hardware ? notch : CGSize(width: 190, height: 24), hasHardwareNotch: hardware, scale: 2)
    }

    func test_closed_matchesHardwareNotch() {
        XCTAssertEqual(metrics(.closed), ShellMetrics(bodyWidth: 185, bodyHeight: 32, topRadius: 6, bottomRadius: 10, hasShadow: false))
    }

    func test_peek_isSlightlyLarger() {
        XCTAssertEqual(metrics(.peek), ShellMetrics(bodyWidth: 197, bodyHeight: 36, topRadius: 6, bottomRadius: 12, hasShadow: false))
    }

    func test_compact_addsTwoEqualWings() {
        let m = metrics(.compact(.charging))
        XCTAssertEqual(m.bodyWidth, 185 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(m.bodyHeight, 32)
        XCTAssertFalse(m.hasShadow)
    }

    func test_expanded_and_opened() {
        XCTAssertEqual(metrics(.expanded(.charging)), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 10, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.normal)), ShellMetrics(bodyWidth: 600, bodyHeight: 180, topRadius: 10, bottomRadius: 28, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.settings)).bodyWidth, 880)
    }

    func test_pill_hasNoEars_andRoundEnds() {
        XCTAssertEqual(metrics(.closed, hardware: false), ShellMetrics(bodyWidth: 190, bodyHeight: 24, topRadius: 0, bottomRadius: 12, hasShadow: false))
    }

    func test_pill_otherStates() {
        XCTAssertEqual(metrics(.peek, hardware: false), ShellMetrics(bodyWidth: 202, bodyHeight: 28, topRadius: 0, bottomRadius: 14, hasShadow: false))

        let compact = metrics(.compact(.charging), hardware: false)
        XCTAssertEqual(compact.bodyWidth, 190 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(compact.bodyHeight, 24)
        XCTAssertEqual(compact.topRadius, 0)
        XCTAssertEqual(compact.bottomRadius, 12)
        XCTAssertFalse(compact.hasShadow)

        XCTAssertEqual(metrics(.expanded(.charging), hardware: false), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 0, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.normal), hardware: false), ShellMetrics(bodyWidth: 600, bodyHeight: 180, topRadius: 0, bottomRadius: 28, hasShadow: true))
    }

    func test_motion() {
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .peek), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .peek, to: .closed), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .opened(.normal)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.normal), to: .closed), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .compact(.charging), to: .expanded(.charging)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .expanded(.charging), to: .compact(.charging)), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.normal), to: .opened(.settings)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.settings), to: .opened(.normal)), .collapse)
    }

    func test_motion_equalMagnitude_usesExpand() {
        XCTAssertEqual(NotchPresentation.motion(from: .compact(.charging), to: .compact(.stopwatch)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .expanded(.filesAdded(count: 2)), to: .expanded(.airDropSent)), .expand)
    }

    func test_wingWidth_fitsWidestValue_andIsPixelAligned() {
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .stopwatch), 36)
        let text = WingLayout.textWidth("100 %")
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .charging), text + 2 * WingLayout.padding)
        let total = WingLayout.wingsWidth(for: .charging, scale: 2)
        XCTAssertEqual(total * 2, (total * 2).rounded())
    }
}
