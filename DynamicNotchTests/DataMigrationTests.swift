//
//  DataMigrationTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class DataMigrationTests: XCTestCase {
    private var root: URL!
    private var legacy: URL { root.appendingPathComponent("legacy") }
    private var destination: URL { root.appendingPathComponent("destination") }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("DataMigrationTests-\(UUID().uuidString)")
        try fm.createDirectory(at: legacy.appendingPathComponent("Config"), withIntermediateDirectories: true)
        try fm.createDirectory(at: legacy.appendingPathComponent("CopiedItems/ABC"), withIntermediateDirectories: true)
        try Data("true".utf8).write(to: legacy.appendingPathComponent("Config/wingBattery"))
        try Data("0.95".utf8).write(to: legacy.appendingPathComponent("Config/notchOpacity"))
        try Data("\"x\"".utf8).write(to: legacy.appendingPathComponent("Config/prompterText"))
        try Data("note".utf8).write(to: legacy.appendingPathComponent("Config/quickNote.txt"))
        try Data("file".utf8).write(to: legacy.appendingPathComponent("CopiedItems/ABC/a.txt"))
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    func test_copiesKnownKeysOnly() {
        DataMigration.run(from: legacy, to: destination)
        let config = destination.appendingPathComponent("Config")
        XCTAssertTrue(fm.fileExists(atPath: config.appendingPathComponent("wingBattery").path))
        XCTAssertTrue(fm.fileExists(atPath: config.appendingPathComponent("quickNote.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: config.appendingPathComponent("notchOpacity").path))
        XCTAssertFalse(fm.fileExists(atPath: config.appendingPathComponent("prompterText").path))
    }

    func test_copiesTrayFiles() {
        DataMigration.run(from: legacy, to: destination)
        let file = destination.appendingPathComponent("CopiedItems/ABC/a.txt")
        XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), "file")
    }

    func test_runsOnlyOnce_andNeverOverwrites() throws {
        DataMigration.run(from: legacy, to: destination)
        let key = destination.appendingPathComponent("Config/wingBattery")
        try Data("false".utf8).write(to: key)
        DataMigration.run(from: legacy, to: destination)
        XCTAssertEqual(try String(contentsOf: key, encoding: .utf8), "false")
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent(DataMigration.markerName).path))
    }

    func test_leavesLegacyFolderInPlace() {
        DataMigration.run(from: legacy, to: destination)
        XCTAssertTrue(fm.fileExists(atPath: legacy.appendingPathComponent("Config/wingBattery").path))
    }

    func test_missingLegacyFolder_isHarmless() {
        DataMigration.run(from: root.appendingPathComponent("absent"), to: destination)
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent(DataMigration.markerName).path))
    }
}
