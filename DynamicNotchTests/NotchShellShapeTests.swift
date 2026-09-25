//
//  NotchShellShapeTests.swift
//  DynamicNotchTests
//

import SwiftUI
import XCTest
@testable import DynamicNotch

final class NotchShellShapeTests: XCTestCase {
    private let canvas = CGRect(x: 0, y: 0, width: 948, height: 584)

    func test_bounds_includeEars() {
        let shape = NotchShellShape(centerX: 474, bodyWidth: 185, bodyHeight: 32, topRadius: 6, bottomRadius: 10)
        let bounds = shape.path(in: canvas).boundingRect
        XCTAssertEqual(bounds.minX, 474 - 92.5 - 6, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 474 + 92.5 + 6, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 32, accuracy: 0.001)
    }

    func test_pill_hasNoEars() {
        let shape = NotchShellShape(centerX: 474, bodyWidth: 190, bodyHeight: 24, topRadius: 0, bottomRadius: 12)
        let bounds = shape.path(in: canvas).boundingRect
        XCTAssertEqual(bounds.width, 190, accuracy: 0.001)
    }

    func test_radiiAreClamped() {
        let shape = NotchShellShape(centerX: 474, bodyWidth: 20, bodyHeight: 10, topRadius: 50, bottomRadius: 50)
        let path = shape.path(in: canvas)
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingRect.maxY, 10, accuracy: 0.001)
    }

    func test_animatableData_roundTrip() {
        var shape = NotchShellShape(centerX: 474, bodyWidth: 185, bodyHeight: 32, topRadius: 6, bottomRadius: 10)
        var data = shape.animatableData
        data.first.first = 340
        data.second.second = 24
        shape.animatableData = data
        XCTAssertEqual(shape.bodyWidth, 340)
        XCTAssertEqual(shape.bottomRadius, 24)
        XCTAssertEqual(shape.bodyHeight, 32)
    }
}
