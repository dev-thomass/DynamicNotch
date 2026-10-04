//
//  NotchGeometryTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class NotchGeometryTests: XCTestCase {
    /// MacBook Pro 14" de référence (mesuré le 2026-09-24).
    private let reference = ScreenDescriptor(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        scale: 2,
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32),
        menuBarHeight: 32
    )

    func test_pixelAligned() {
        XCTAssertEqual(pixelAligned(663.3, scale: 2), 663.5)
        XCTAssertEqual(pixelAligned(663.2, scale: 2), 663.0)
        XCTAssertEqual(pixelAligned(663.5, scale: 1), 664.0)
    }

    func test_hardwareNotch_usesAuxiliaryAreas_notCentering() {
        let geometry = NotchGeometry(screen: reference)
        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 663, y: 950, width: 185, height: 32))
    }

    func test_hardwareNotch_onSecondaryScreenOrigin() {
        var screen = reference
        screen.frame.origin = CGPoint(x: -1512, y: 200)
        let geometry = NotchGeometry(screen: screen)
        XCTAssertEqual(geometry.notchRect, CGRect(x: -1512 + 663, y: 200 + 950, width: 185, height: 32))
    }

    func test_missingAuxiliaryAreas_fallsBackToRatio() {
        var screen = reference
        screen.auxiliaryTopLeft = nil
        screen.auxiliaryTopRight = nil
        let geometry = NotchGeometry(screen: screen)
        XCTAssertTrue(geometry.hasHardwareNotch)
        // 1512 × 0,12 = 181,44 → 181,5 ; centre 756 → x = 665,25 → 665,5
        XCTAssertEqual(geometry.notchRect, CGRect(x: 665.5, y: 950, width: 181.5, height: 32))
    }

    func test_noNotch_isMenuBarHighPill() {
        let screen = ScreenDescriptor(
            displayID: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1,
            safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil, menuBarHeight: 24
        )
        let geometry = NotchGeometry(screen: screen)
        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 865, y: 1056, width: 190, height: 24))
    }

    func test_forcePill_onNotchedScreen() {
        let geometry = NotchGeometry(screen: reference, forcePill: true)
        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 661, y: 950, width: 190, height: 32))
    }

    func test_windowFrame_isPixelAligned_andCenteredOnNotch() {
        let geometry = NotchGeometry(screen: reference)
        let frame = geometry.windowFrame
        XCTAssertEqual(frame.size, NotchGeometry.windowSize)
        XCTAssertEqual(frame.maxY, 982)
        XCTAssertEqual(frame.minX * 2, (frame.minX * 2).rounded())
        XCTAssertEqual(frame.minX + geometry.notchCenterXInWindow, geometry.notchRect.midX)
    }
}
