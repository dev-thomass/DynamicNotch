# DynamicNotch

A macOS notch utility that turns your MacBook's notch (or top center on
displays without one) into a multi-purpose, paged dock for quick widgets:
file drops, AirDrop, notes, Pomodoro, stopwatch, calendar
and more — all behind a clean, customisable design system.

> Forked from [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) and
> rebuilt around a widget-page architecture, a dedicated design system,
> and a full-French UI.

## Highlights

- **Tabbed panel** — five tabs live around the notch (Home, Files, Timers,
  Notes, Agenda); the panel morphs out of the notch like the Dynamic Island.
- **Built-in widgets**
  - **AirDrop** + generic file share
  - **Files** (drag-and-drop tray with auto-expiry)
  - **Notes** (quick scratchpad, debounced disk save)
  - **Stopwatch** (mm:ss.cc)
  - **Pomodoro** (configurable focus / break / long break durations)
  - **Agenda** (today's events, next ones on Home, via EventKit)
  - *Now Playing is not in the tabbed panel for now; it comes back with the
    music task.*
- **Design system** — `DSTokens` (colors, spacing, radius, typography,
  motion) + `DSComponents` (buttons, modules, icon buttons, tab bar, badges,
  drop zones) used everywhere.
- **Settings** — appearance, behaviour, display picker (any external
  monitor with or without a hardware notch), storage, Pomodoro durations,
  reset.
- **Mac without a notch** — auto-falls back to a clean continuous-corner
  pill in the same screen position.
- **Native flock-based single instance**, focus-stealing avoidance, full
  EventMonitor throttling, accessibility labels everywhere.

## Install

Download the latest `.dmg` from
[Releases](https://github.com/dev-thomass/DynamicNotch/releases/latest) —
step-by-step guide (in French): [docs/INSTALLATION.md](docs/INSTALLATION.md).
Installed copies update themselves (Sparkle).

Publishing a new version: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Build

```bash
git clone https://github.com/dev-thomass/DynamicNotch.git
cd DynamicNotch
xcodebuild -project DynamicNotch.xcodeproj \
  -scheme DynamicNotch \
  -configuration Release \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

cp -R ~/Library/Developer/Xcode/DerivedData/DynamicNotch-*/Build/Products/Release/DynamicNotch.app ~/Applications/
open ~/Applications/DynamicNotch.app
```

For development, just open `DynamicNotch.xcodeproj` in Xcode and ⌘R.
Local builds don't embed the update key, so they never auto-update.

## Project layout

```
DynamicNotch/
├── DesignSystem/        Tokens + reusable components
├── Widgets/             One file per widget (Note, Pomodoro, NowPlaying, …)
├── NotchView*.swift     Window, view, view model, events
├── AppSettings.swift    Persisted preferences
└── …
```

## Privacy

Everything stays on your Mac. No telemetry, no analytics. The only network
request is the daily update check against this repository's GitHub Releases
(can be turned off in Settings). See `Resources/Privacy.md` for the full
breakdown.

## License

MIT — see [LICENSE](./LICENSE).

Inherits from NotchDrop's MIT license; new code is also MIT.
