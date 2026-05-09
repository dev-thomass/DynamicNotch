# Privacy Policy — DynamicNotch

_Last updated: 2026-05-09_

DynamicNotch is a local-first macOS utility. This document explains what the app
does and does not do with your data, in plain language.

## TL;DR

- **No telemetry.** DynamicNotch never connects to the internet.
- **No analytics, no crash reporters, no third-party SDKs.**
- **No account, no sign-up.**
- Files you drop into DynamicNotch stay on your Mac.

## What DynamicNotch stores on disk

When you drop a file onto the notch, DynamicNotch keeps a **copy** of that file in
your home folder so you can re-access it from the tray later.

| Path | Purpose |
|---|---|
| `~/Documents/DynamicNotch/CopiedItems/<UUID>/<filename>` | The copy of each dropped file. |
| `~/Documents/DynamicNotch/CopiedItems/<UUID>/.preview.png` | A 128 px Quick Look thumbnail used by the tray UI. |
| `~/Documents/DynamicNotch/Config/*` | Your preferences (storage duration, language, display, opacity, …). Plain JSON. |
| `~/Documents/DynamicNotch/.instance.lock` | Empty file used by `flock(2)` to prevent two DynamicNotch instances from running simultaneously. |
| `$TMPDIR/<bundle-id>/` | Temporary working copies during a drop. Cleared on quit. |

These files are owned by your user, readable by other apps that have your
permission to read your home folder (e.g. Finder, Spotlight, Time Machine).

### Recommended exclusions

If you handle sensitive files, consider excluding DynamicNotch's storage from
backup tools and search indexers:

- **Time Machine**: System Settings → General → Time Machine → Options → Add
  `~/Documents/DynamicNotch`.
- **Spotlight**: System Settings → Spotlight → Search Privacy → Add
  `~/Documents/DynamicNotch`.

You can also reduce the retention window in Settings → Storage (default: 1 day).
After expiration, DynamicNotch deletes the cached copy automatically.

## What DynamicNotch does NOT do

- It does not phone home.
- It does not embed analytics, crash reporting, or any third-party SDK.
- It does not read files outside the ones you explicitly drop on the notch.
- It does not access your microphone, camera, contacts, calendar, location, or
  network.
- It does not modify or upload the original files — only copies them.

## Sharing & AirDrop

When you tap the AirDrop or Share panel inside the notch, DynamicNotch hands the
selected files to macOS's standard sharing services (`NSSharingService`). What
happens after that is governed by macOS itself and the destination service,
not by DynamicNotch.

## Open source

DynamicNotch is open source under the MIT license. You can audit every line of
code at <https://github.com/Lakr233/DynamicNotch> and verify the claims above.

## Questions

Open an issue on the GitHub repository.
