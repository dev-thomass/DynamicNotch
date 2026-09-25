# DynamicNotchTests

XCTest target — unit tests for non-UI logic.

## Lancer les tests

    Tools/test.sh               # tous les tests
    Tools/test.sh PersistTests  # une seule classe

La cible `DynamicNotchTests` est branchée dans le projet. Pour ajouter un
fichier de test : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/MonTest.swift`.

## Files

| File | Covers |
|---|---|
| `PersistTests.swift` | `Persist` round-trip, default values, decode failures (uses an in-memory `PersistProvider` so the user's `~/Library/Application Support/DynamicNotch/Config` is never touched). |
| `DisplayPreferenceTests.swift` | `DisplayPreference` `Codable` round-trip, equality semantics. |
| `TrayDropFileStorageTimeTests.swift` | `TrayDrop.FileStorageTime.toTimeInterval` boundaries. |

## Adding tests

- Use `@testable import DynamicNotch` (the new target lets you reach `internal`
  symbols without changing visibility).
- Never touch `~/Library/Application Support/DynamicNotch/` from a test. Use mocks /
  `FileManager.default.temporaryDirectory` for filesystem tests.
- Keep tests deterministic — no real `NSScreen`, no real time, no real
  network (there's no network anyway, but the rule stands).
