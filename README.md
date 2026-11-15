# Anime Tracker (AniMay)

Personal anime tracker built with SwiftUI.

- Search anime via AniList
- Track status, progress, and scores
- Local-only storage (on device)

## Build unsigned IPA (GitHub Actions)

This repo includes a workflow that builds an **unsigned** `.ipa` on `macos-latest`.

1. Push to `main` or run the workflow manually (Actions → Build Unsigned iOS App → Run workflow).
2. Download the `ios-app-ipa` artifact when the run finishes.
3. Sideload with SideStore / AltStore / TrollStore (or any tool that accepts an unsigned IPA).

> Note: Unsigned IPAs cannot be installed through the App Store. You need a sideloading method and a free Apple ID (or other signing solution).

## Structure

```
AnimeTracker.swiftpm/   ← Swift Playgrounds / SwiftPM App package
.github/workflows/      ← CI that produces the IPA
```
