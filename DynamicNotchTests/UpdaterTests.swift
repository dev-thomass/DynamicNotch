//
//  UpdaterTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class UpdaterTests: XCTestCase {
    private let feed = "https://github.com/dev-thomass/DynamicNotch/releases/latest/download/appcast.xml"

    func test_isConfigured_withFeedAndKey() {
        XCTAssertTrue(Updater.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": "abc="]))
    }

    func test_isNotConfigured_withoutKey() {
        XCTAssertFalse(Updater.isConfigured(["SUFeedURL": feed]))
        XCTAssertFalse(Updater.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": "  "]))
    }

    func test_isNotConfigured_withoutFeed() {
        XCTAssertFalse(Updater.isConfigured(["SUPublicEDKey": "abc="]))
        XCTAssertFalse(Updater.isConfigured(["SUFeedURL": "", "SUPublicEDKey": "abc="]))
    }

    /// Les builds locales / de test n'embarquent pas la clé : l'updater reste éteint.
    func test_testHostBuild_isNotConfigured() {
        XCTAssertFalse(Updater.isConfigured(Bundle.main.infoDictionary ?? [:]))
    }
}
