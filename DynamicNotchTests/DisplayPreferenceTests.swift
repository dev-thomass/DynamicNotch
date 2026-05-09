//
//  DisplayPreferenceTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class DisplayPreferenceTests: XCTestCase {

    // MARK: codable round-trip

    func test_codable_builtInWithNotch() throws {
        try assertRoundTrips(.builtInWithNotch)
    }

    func test_codable_mainAtResolveTime() throws {
        try assertRoundTrips(.mainAtResolveTime)
    }

    func test_codable_named_withSpecialCharacters() throws {
        try assertRoundTrips(.named("Studio Display – LG (USB-C)"))
    }

    // MARK: equality

    func test_named_equality_isCaseSensitive() {
        XCTAssertNotEqual(
            DisplayPreference.named("Built-in Retina Display"),
            DisplayPreference.named("built-in retina display")
        )
    }

    // MARK: display name

    func test_displayName_named_returnsRawString() {
        XCTAssertEqual(DisplayPreference.named("XDR").displayName, "XDR")
    }

    // MARK: helpers

    private func assertRoundTrips(_ pref: DisplayPreference, file: StaticString = #file, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(pref)
        let decoded = try JSONDecoder().decode(DisplayPreference.self, from: data)
        XCTAssertEqual(decoded, pref, file: file, line: line)
    }
}
