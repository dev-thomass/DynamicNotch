# Privacy Policy — DynamicNotch

_Last updated: 2026-09-30_

DynamicNotch is a local-first macOS utility. This document explains what the app
does and does not do with your data, in plain language.

## TL;DR

- **No telemetry.** The only network request is the update check (see below).
- **No analytics, no crash reporters.** The only third-party SDK is
  [Sparkle](https://sparkle-project.org), the standard open-source macOS updater.
- **No account, no sign-up.**
- Files you drop into DynamicNotch stay on your Mac.

## What DynamicNotch stores on disk

When you drop a file onto the notch, DynamicNotch keeps a **copy** of that file in
your home folder so you can re-access it from the tray later.

| Path | Purpose |
|---|---|
| `~/Library/Application Support/DynamicNotch/CopiedItems/<UUID>/<filename>` | The copy of each dropped file. |
| `~/Library/Application Support/DynamicNotch/CopiedItems/<UUID>/.preview.png` | A 128 px Quick Look thumbnail used by the tray UI. |
| `~/Library/Application Support/DynamicNotch/Config/*` | Your preferences (storage duration, language, display, opacity, …). Plain JSON. |
| `~/Library/Application Support/DynamicNotch/.instance.lock` | Empty file used by `flock(2)` to prevent two DynamicNotch instances from running simultaneously. |
| `$TMPDIR/<bundle-id>/` | Temporary working copies during a drop. Cleared on quit. |

These files are owned by your user, readable by other apps that have your
permission to read your home folder (e.g. Finder, Spotlight, Time Machine).

Older versions stored this data in `~/Documents/DynamicNotch`. On first
launch after updating, DynamicNotch copies the still-used files from that
folder into `~/Library/Application Support/DynamicNotch` once; the old
`~/Documents/DynamicNotch` folder is left in place afterwards (nothing is
deleted from it), so it is safe to remove by hand once you've confirmed the
new location has everything you need.

### Recommended exclusions

If you handle sensitive files, consider excluding DynamicNotch's storage from
backup tools and search indexers:

- **Time Machine**: System Settings → General → Time Machine → Options → Add
  `~/Library/Application Support/DynamicNotch`.
- **Spotlight**: System Settings → Spotlight → Search Privacy → Add
  `~/Library/Application Support/DynamicNotch`.

You can also reduce the retention window in Settings → Storage (default: 1 day).
After expiration, DynamicNotch deletes the cached copy automatically.

## Update checks

Builds published on GitHub Releases check for a new version once a day (and
when you click "Rechercher les mises à jour"). DynamicNotch downloads
`appcast.xml` from `github.com/dev-thomass/DynamicNotch/releases`, and the new
version's archive if you accept the update. The request carries only what any
download does (your IP address, reaching GitHub, and a User-Agent with the app
name and version); no system profile or identifier is sent. Downloaded updates
are rejected unless they carry a valid EdDSA signature.

Turn it off in Settings → Mises à jour → "Vérifier automatiquement".
Builds you compile yourself never check for updates.

## What DynamicNotch does NOT do

- It does not send any data about you or your files anywhere.
- It does not embed analytics or crash reporting.
- It does not read files outside the ones you explicitly drop on the notch.
- It does not access your microphone, camera, contacts or location. The
  calendar is read only if you allow it, to show your events in the Agenda
  tab; nothing leaves your Mac.
- It does not modify or upload the original files — only copies them.

## Sharing & AirDrop

When you tap the AirDrop or Share panel inside the notch, DynamicNotch hands the
selected files to macOS's standard sharing services (`NSSharingService`). What
happens after that is governed by macOS itself and the destination service,
not by DynamicNotch.

## Open source

DynamicNotch is open source under the MIT license. You can audit every line of
code at <https://github.com/dev-thomass/DynamicNotch> and verify the claims above.

## Questions

Open an issue on the GitHub repository.
