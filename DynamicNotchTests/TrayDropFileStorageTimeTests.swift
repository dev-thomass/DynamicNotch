//
//  TrayDropFileStorageTimeTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class TrayDropFileStorageTimeTests: XCTestCase {

    func test_oneHour_returnsExactly3600s() {
        XCTAssertEqual(TrayDrop.FileStorageTime.oneHour.toTimeInterval(customTime: 0), 3600)
    }

    func test_oneDay_returnsExactly86400s() {
        XCTAssertEqual(TrayDrop.FileStorageTime.oneDay.toTimeInterval(customTime: 0), 86_400)
    }

    func test_oneWeek_returnsExactly604_800s() {
        XCTAssertEqual(TrayDrop.FileStorageTime.oneWeek.toTimeInterval(customTime: 0), 604_800)
    }

    func test_never_returnsInfinity() {
        XCTAssertEqual(TrayDrop.FileStorageTime.never.toTimeInterval(customTime: 0), .infinity)
    }

    func test_custom_passesThroughCustomTime() {
        XCTAssertEqual(TrayDrop.FileStorageTime.custom.toTimeInterval(customTime: 12_345), 12_345)
    }
}
