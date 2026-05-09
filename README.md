# DynamicNotch

A macOS notch utility that turns your MacBook's notch (or top center on
displays without one) into a multi-purpose, paged dock for quick widgets:
file drops, AirDrop, notes, Pomodoro, stopwatch, calendar, now-playing,
and more — all behind a clean, customisable design system.

> Forked from [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) and
> rebuilt around a widget-page architecture, a dedicated design system,
> and a full-French UI.

## Highlights

- **Multi-page widget panel** — group widgets by use case, navigate with
  chevrons in the header (`‹  2/3  ›`).
- **Built-in widgets**
  - **AirDrop** + generic file share
  - **Files** (drag-and-drop tray with auto-expiry)
  - **Notes** (quick scratchpad, debounced disk save)
  - **Stopwatch** (mm:ss.cc)
  - **Pomodoro** (configurable focus / break / long break durations)
  - **Now Playing** (MediaRemote-backed, play / pause / next / prev)
  - **Calendar** (next event in the next 24 h via EventKit)
- **Design system** — `DSTokens` (colors, spacing, radius, typography,
  motion) + `DSComponents` (buttons, cards, badges, pills, drop zones,
  notch header) used everywhere.
- **Settings** — appearance, behaviour, display picker (any external
  monitor with or without a hardware notch), storage, Pomodoro durations,
  reset.
- **Mac without a notch** — auto-falls back to a clean continuous-corner
  pill in the same screen position.
- **Native flock-based single instance**, focus-stealing avoidance, full
  EventMonitor throttling, accessibility labels everywhere.

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

Everything stays on your Mac. No telemetry, no analytics, no network
calls. See `Resources/Privacy.md` for the full breakdown.

## License

MIT — see [LICENSE](./LICENSE).

Inherits from NotchDrop's MIT license; new code is also MIT.
