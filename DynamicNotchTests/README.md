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
| `PersistTests.swift` | `Persist` round-trip, default values, decode failures, and that creating a setting never writes it back (uses an in-memory `PersistProvider`). |
| `DisplayPreferenceTests.swift` | `DisplayPreference` `Codable` round-trip, equality semantics. |
| `TrayDropFileStorageTimeTests.swift` | `TrayDrop.FileStorageTime.toTimeInterval` boundaries. |
| `DataMigrationTests.swift` | `DataMigration.run` — copies only the still-used `Config` keys and `CopiedItems`, runs once (marker file), never overwrites an existing destination file, leaves the legacy `~/Documents/DynamicNotch` folder in place, no-ops when that folder is missing, and leaves no marker (so it retries) when the legacy folder is unreadable or a copy fails. |
| `NotchGeometryTests.swift` | `NotchGeometry` — pixel alignment, hardware-notch frame derived from the screen's auxiliary areas (not centering), fallback to a ratio-based pill when auxiliary areas are missing, secondary-screen origin handling, forced pill mode, and the reference-screen values (x = 663, width 185). |
| `NotchShellShapeTests.swift` | `NotchShellShape` — bounds that include the ears, the no-ears pill variant, corner-radius clamping, and the `animatableData` round-trip used for interpolated transitions. |
| `ActivityCenterTests.swift` | `ActivityCenter` — transient activities expand then clear, collapse into a persistent activity, are queued in arrival order, get dropped once stale (>5 s), extend instead of re-queuing when the same transient repeats, respect persistent priorities, keep persistents while dropping transients on suspension, replay the most recent transient posted during suspension when it ends (if < 5 s old, only on the last nested end), and notify observers once per change. |
| `PowerEventsTests.swift` | `BatteryMonitor` — parsing an `IOKit` power-source snapshot (internal battery, no battery, unknown time-to-full), and the plug/unplug/low-battery event mapping (edges, once-per-threshold, no warning below threshold at launch). |
| `NotchPresentationTests.swift` | `NotchPresentation` — closed state matches the hardware notch, peek grows 3 pt taller at the same width, compact adds two equal wings, expanded/opened states, pill has no ears and round ends, motion picks the right spring (including the equal-magnitude case), wing width fits the widest value (including 3-digit stopwatch minutes and the battery glyph) while staying pixel-aligned, the expanded state grows with a taller notch, and the HUD card shares the expanded metrics and springs. |
| `StopwatchModelTests.swift` | `StopwatchModel` — elapsed time accumulates across pauses, reset, and mm:ss.cc formatting. |
| `PomodoroModelTests.swift` | `PomodoroModel` — activity titles per phase, and that skipping a phase reports a phase change rather than a natural end. |
| `NotchViewModelTests.swift` | `NotchViewModel` ↔ `ActivityCenter` glue — adopts the activity already in progress at creation, suspends while open (balanced across repeated opens, `destroy()` and `showSettings()`), opens without an intermediate compact state, follows activity changes while closed but not while opened, sends a haptic only when the pointer enters the compact shell, and handles tabs (last tab on open, Files on a drag, slide direction, haptic on change only, `closeSettings()` back to the last tab with the slide edge reset to trailing), and the HUD (wins over activities and a peek, never interrupts the opened panel). |
| `ActivityWiringTests.swift` | `ActivityWiring` — nothing active at rest, charging only reported with a battery present, disabling wings disables everything, chrono/Pomodoro/music timers, calendar events only surfaced within the hour, and power-event-to-activity mapping. |
| `NotchTabTests.swift` | `NotchTab` — fixed order and SF Symbols, panel heights per tab, and the slide edge that follows the navigation direction. |
| `AgendaPlannerTests.swift` | `AgendaPlanner` — today/tomorrow split (all-day first, then by time), upcoming events (skips ended and all-day, limited), EventKit access mapping, and the stable per-occurrence entry id. |
| `PomodoroProgressTests.swift` | `PomodoroModel.progress(at:)` — 0 at rest, then continuous (a quarter of the phase gives 0.25) while a phase runs. |
| `ShareActivityTests.swift` | `ShareActivity` — the AirDrop sending state is counted (nested sends stay "sending" until the last `end()`) and never goes negative. |
| `MediaKeyTests.swift` | `MediaKeyEvent.decode` — the five handled `NX_KEYTYPE_*` codes, key down/up, auto-repeat, other subtypes and keys ignored, ⌥⇧ fine steps; `LevelStep.next` — 1/16 and 1/64 steps snapped to the grid and clamped to [0, 1]. `HUDIcon` symbols per level and mute. |
| `HUDControllerTests.swift` | `HUDController` — shows a state, hides it 1.5 s after the last change, each change extends the delay, observers notified once per change (uses `ManualScheduler`). |
| `SystemControlsSmokeTests.swift` | `CoreAudioVolumeControl` / `DisplayServicesBrightnessControl` — read-only smoke checks (levels in [0, 1]); never writes the real volume or brightness. |
| `MediaKeyRouterTests.swift` | `MediaKeyPolicy` / `MediaKeyRouter` with fake controls — consume vs pass through by setting, permission and availability; step applied on key down only; volume up unmutes; mute toggles; feedback sound on volume steps; external volume changes publish the HUD. |

## Isolation des données

Les tests tournent dans l'app hôte. Sous XCTest (`XCTestConfigurationFilePath`
présent), `main.swift` fait pointer `dataDirectory` vers un dossier temporaire
(`$TMPDIR/DynamicNotchTests-data`), vidé à chaque lancement, et ne touche pas
au dossier temporaire de l'app éventuellement en cours d'exécution. Les
réglages lus par les tests (`AppSettings.shared`, …) vivent donc là, jamais
dans `~/Library/Application Support/DynamicNotch/`. De plus, créer un réglage
ne l'écrit plus : seul un changement effectif crée le fichier.

## Adding tests

- Use `@testable import DynamicNotch` (the new target lets you reach `internal`
  symbols without changing visibility).
- Never touch `~/Library/Application Support/DynamicNotch/` from a test (the
  host already redirects `dataDirectory`, see above). Use mocks /
  `FileManager.default.temporaryDirectory` for filesystem tests.
- Keep tests deterministic — no real `NSScreen`, no real time, no real
  network (there's no network anyway, but the rule stands).
