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
| `DataMigrationTests.swift` | `DataMigration.run` — copies only the still-used `Config` keys and `CopiedItems`, runs once (marker file), never overwrites an existing destination file, leaves the legacy `~/Documents/DynamicNotch` folder in place, and no-ops when that folder is missing. |
| `NotchGeometryTests.swift` | `NotchGeometry` — pixel alignment, hardware-notch frame derived from the screen's auxiliary areas (not centering), fallback to a ratio-based pill when auxiliary areas are missing, secondary-screen origin handling, forced pill mode, and the reference-screen values (x = 663, width 185). |
| `NotchShellShapeTests.swift` | `NotchShellShape` — bounds that include the ears, the no-ears pill variant, corner-radius clamping, and the `animatableData` round-trip used for interpolated transitions. |
| `ActivityCenterTests.swift` | `ActivityCenter` — transient activities expand then clear, collapse into a persistent activity, are queued in arrival order, get dropped once stale (>5 s), extend instead of re-queuing when the same transient repeats, respect persistent priorities, keep persistents while dropping transients on suspension, and notify observers once per change. |
| `PowerEventsTests.swift` | `BatteryMonitor` — parsing an `IOKit` power-source snapshot (internal battery, no battery, unknown time-to-full), and the plug/unplug/low-battery event mapping (edges, once-per-threshold, no warning below threshold at launch). |
| `NotchPresentationTests.swift` | `NotchPresentation` — closed state matches the hardware notch, peek is slightly larger, compact adds two equal wings, expanded/opened states, pill has no ears and round ends, motion picks the right spring (including the equal-magnitude case), and wing width fits the widest value while staying pixel-aligned. |
| `StopwatchModelTests.swift` | `StopwatchModel` — elapsed time accumulates across pauses, reset, and mm:ss.cc formatting. |
| `PomodoroModelTests.swift` | `PomodoroModel` — activity titles per phase, and that skipping a phase reports a phase change rather than a natural end. |
| `ActivityWiringTests.swift` | `ActivityWiring` — nothing active at rest, charging only reported with a battery present, disabling wings disables everything, chrono/Pomodoro/music timers, calendar events only surfaced within the hour, and power-event-to-activity mapping. |

## Adding tests

- Use `@testable import DynamicNotch` (the new target lets you reach `internal`
  symbols without changing visibility).
- Never touch `~/Library/Application Support/DynamicNotch/` from a test. Use mocks /
  `FileManager.default.temporaryDirectory` for filesystem tests.
- Keep tests deterministic — no real `NSScreen`, no real time, no real
  network (there's no network anyway, but the rule stands).
