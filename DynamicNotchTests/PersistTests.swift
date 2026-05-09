//
//  PersistTests.swift
//  DynamicNotchTests
//
//  Round-trip + default-value coverage for the Persist / PublishedPersist
//  property wrappers and the FileStorage backend.
//
//  ─── Adding the test target in Xcode ───
//  1. File → New → Target → Test Bundle
//  2. Name: DynamicNotchTests
//  3. Drag every file under `DynamicNotchTests/` into the new target
//  4. In the test target's Build Phases, add the DynamicNotch target as a
//     "Target Dependency" so test files can `@testable import DynamicNotch`
//

import XCTest
@testable import DynamicNotch

final class PersistTests: XCTestCase {

    // MARK: round-trip

    func test_persist_roundTrip_simpleString() throws {
        let key = uniqueKey()
        let store = InMemoryStore()
        let persist = Persist(key: key, defaultValue: "alpha", engine: store)
        XCTAssertEqual(persist.wrappedValue, "alpha")

        // Mutate and re-read via a fresh wrapper backed by the same engine —
        // simulates what happens across app restarts.
        var mutable = persist
        mutable.wrappedValue = "beta"

        let reread = Persist(key: key, defaultValue: "alpha", engine: store)
        XCTAssertEqual(reread.wrappedValue, "beta", "value did not survive round trip")
    }

    func test_persist_defaultValue_isReturnedWhenStoreEmpty() {
        let store = InMemoryStore()
        let persist = Persist(key: uniqueKey(), defaultValue: 42, engine: store)
        XCTAssertEqual(persist.wrappedValue, 42)
    }

    func test_persist_defaultValue_isReturnedOnDecodeFailure() {
        let key = uniqueKey()
        let store = InMemoryStore()
        // Pre-seed garbage data the JSONDecoder can't make sense of.
        store.set(Data("not valid JSON".utf8), forKey: key)

        let persist = Persist(key: key, defaultValue: "fallback", engine: store)
        XCTAssertEqual(persist.wrappedValue, "fallback")
    }

    // MARK: helpers

    private func uniqueKey() -> String {
        "test_\(UUID().uuidString)"
    }
}

/// In-memory `PersistProvider` used by tests. Avoids touching the user's
/// `~/Documents/DynamicNotch/Config` folder during test runs.
private final class InMemoryStore: PersistProvider {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
}
