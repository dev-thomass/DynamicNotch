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

    /// Au repos, la coque épouse l'encoche : aucun pixel noir hors de l'encoche.
    func test_closed_isExactlyTheHardwareNotch() {
        XCTAssertEqual(metrics(.closed), ShellMetrics(bodyWidth: 185, bodyHeight: 32, topRadius: 0, bottomRadius: 10, hasShadow: false))
    }

    /// Le survol n'élargit plus : il allonge de 3 pt vers le bas.
    func test_peek_growsDownOnly() {
        XCTAssertEqual(metrics(.peek), ShellMetrics(bodyWidth: 185, bodyHeight: 35, topRadius: 0, bottomRadius: 10, hasShadow: false))
    }

    func test_compact_addsTwoEqualWings_withEars() {
        let m = metrics(.compact(.charging))
        XCTAssertEqual(m.bodyWidth, 185 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(m.bodyHeight, 32)
        XCTAssertEqual(m.topRadius, 6)
        XCTAssertFalse(m.hasShadow)
    }

    func test_expanded_and_opened() {
        XCTAssertEqual(metrics(.expanded(.charging)), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 10, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.tab(.home))), ShellMetrics(bodyWidth: 640, bodyHeight: 190, topRadius: 10, bottomRadius: 28, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.tab(.notes))).bodyHeight, 220)
        XCTAssertEqual(metrics(.opened(.tab(.agenda))).bodyHeight, 260)
        XCTAssertEqual(metrics(.opened(.settings)).bodyWidth, 880)
    }

    func test_pill_states() {
        XCTAssertEqual(metrics(.closed, hardware: false), ShellMetrics(bodyWidth: 190, bodyHeight: 24, topRadius: 0, bottomRadius: 12, hasShadow: false))
        XCTAssertEqual(metrics(.peek, hardware: false), ShellMetrics(bodyWidth: 190, bodyHeight: 27, topRadius: 0, bottomRadius: 13.5, hasShadow: false))

        let compact = metrics(.compact(.charging), hardware: false)
        XCTAssertEqual(compact.bodyWidth, 190 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(compact.topRadius, 0)
        XCTAssertEqual(compact.bottomRadius, 12)

        XCTAssertEqual(metrics(.expanded(.charging), hardware: false), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 0, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.tab(.home)), hardware: false), ShellMetrics(bodyWidth: 640, bodyHeight: 190, topRadius: 0, bottomRadius: 28, hasShadow: true))
    }

    func test_motion() {
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .peek), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .peek, to: .closed), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .opened(.tab(.home))), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .closed), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .compact(.charging), to: .expanded(.charging)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .expanded(.charging), to: .compact(.charging)), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .opened(.settings)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.settings), to: .opened(.tab(.home))), .collapse)
    }

    /// Entre deux onglets : on compare la surface du panneau.
    func test_motion_betweenTabs_comparesPanelArea() {
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .opened(.tab(.agenda))), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.agenda)), to: .opened(.tab(.home))), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .opened(.tab(.files))), .expand)
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

    func test_expanded_growsWithTallNotch() {
        let tall = NotchPresentation.expanded(.charging).metrics(notch: CGSize(width: 200, height: 38), hasHardwareNotch: true, scale: 2)
        XCTAssertEqual(tall.bodyHeight, 86)
    }

    func test_stopwatchWing_fitsThreeDigitMinutes_andBatteryGlyph() {
        let text = WingLayout.textWidth("100:00")
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .stopwatch), text + 2 * WingLayout.padding)
        XCTAssertGreaterThanOrEqual(WingLayout.iconWidth, 25)
    }

    func test_hud_metrics_andMotion() {
        XCTAssertEqual(metrics(.hud(.volume)), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 10, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.hud(.brightness), hardware: false).topRadius, 0)
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .hud(.volume)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .hud(.volume), to: .compact(.charging)), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .hud(.volume), to: .hud(.brightness)), .expand)
    }
}
