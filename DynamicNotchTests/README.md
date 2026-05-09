# DynamicNotchTests

XCTest target — unit tests for non-UI logic.

## One-time wiring (Xcode UI, ~30 s)

The `.swift` files here ship without an Xcode test target on purpose:
adding a `PBXNativeTarget` from outside Xcode is fragile. To enable them:

1. Open `DynamicNotch.xcodeproj` in Xcode.
2. **File → New → Target… → macOS → Test Bundle**.
3. Name it exactly `DynamicNotchTests`. **Set "Target to be Tested" to `DynamicNotch`**.
4. In the Project Navigator, drag every `.swift` file from this directory
   into the new `DynamicNotchTests` group (uncheck "Copy items if needed",
   check "DynamicNotchTests" in "Add to targets").
5. Build & test (⌘U).

The CI workflow (`.github/workflows/ci.yml`) auto-detects the target the
moment it appears in the project file — no further config needed.

## Files

| File | Covers |
|---|---|
| `PersistTests.swift` | `Persist` round-trip, default values, decode failures (uses an in-memory `PersistProvider` so the user's `~/Documents/DynamicNotch/Config` is never touched). |
| `DisplayPreferenceTests.swift` | `DisplayPreference` `Codable` round-trip, equality semantics. |
| `TrayDropFileStorageTimeTests.swift` | `TrayDrop.FileStorageTime.toTimeInterval` boundaries. |

## Adding tests

- Use `@testable import DynamicNotch` (the new target lets you reach `internal`
  symbols without changing visibility).
- Never touch `~/Documents/DynamicNotch/` from a test. Use mocks /
  `FileManager.default.temporaryDirectory` for filesystem tests.
- Keep tests deterministic — no real `NSScreen`, no real time, no real
  network (there's no network anyway, but the rule stands).
