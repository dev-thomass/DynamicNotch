//
//  ClipboardHistoryTests.swift
//  DynamicNotchTests
//

import AppKit
@testable import DynamicNotch
import XCTest

final class ClipboardEntriesTests: XCTestCase {
    func test_insert_putsNewestFirst() {
        var entries = ClipboardEntries()
        entries.insert("a")
        entries.insert("b")
        XCTAssertEqual(entries.items, ["b", "a"])
    }

    func test_duplicate_movesToTop() {
        var entries = ClipboardEntries()
        entries.insert("a")
        entries.insert("b")
        entries.insert("a")
        XCTAssertEqual(entries.items, ["a", "b"])
    }

    func test_blankText_isIgnored() {
        var entries = ClipboardEntries()
        entries.insert("  \n")
        XCTAssertTrue(entries.items.isEmpty)
    }

    func test_capacity_dropsOldest() {
        var entries = ClipboardEntries()
        for index in 0 ..< ClipboardEntries.capacity + 5 {
            entries.insert("\(index)")
        }
        XCTAssertEqual(entries.items.count, ClipboardEntries.capacity)
        XCTAssertEqual(entries.items.first, "\(ClipboardEntries.capacity + 4)")
        XCTAssertEqual(entries.items.last, "5")
    }
}

final class ClipboardPolicyTests: XCTestCase {
    func test_concealedCopies_areSkipped() {
        XCTAssertFalse(ClipboardPolicy.shouldRecord(types: [
            "public.utf8-plain-text",
            "org.nspasteboard.ConcealedType"
        ]))
        XCTAssertTrue(ClipboardPolicy.shouldRecord(types: ["public.utf8-plain-text"]))
    }
}

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func test_poll_recordsNewTextOnce() {
        let pasteboard = NSPasteboard(name: .init("DynamicNotchTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("bonjour", forType: .string)
        history.poll()
        history.poll()
        XCTAssertEqual(history.entries.items, ["bonjour"])
    }

    func test_concealedCopy_isNotRecorded() {
        let pasteboard = NSPasteboard(name: .init("DynamicNotchTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setString("motdepasse", forType: .string)
        pasteboard.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        history.poll()
        XCTAssertTrue(history.entries.items.isEmpty)
    }

    func test_copy_putsEntryBackOnTop() {
        let pasteboard = NSPasteboard(name: .init("DynamicNotchTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: pasteboard)

        for text in ["a", "b"] {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            history.poll()
        }
        history.copy("a")
        XCTAssertEqual(history.entries.items, ["a", "b"])
        XCTAssertEqual(pasteboard.string(forType: .string), "a")
    }
}
