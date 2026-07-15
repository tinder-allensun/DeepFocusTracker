# DeepFocusTracker

A privacy-first macOS menu-bar app for doing — and reviewing — deep focus work.
Start a focus block (naming what you're working on) and DeepFocusTracker records
how long you spend in each app during it — **no focus/distraction judgment** —
so you can review where your time actually went. Everything stays local on your
Mac.

See [`SPEC.md`](SPEC.md) for the full product specification.

## Status

**M1–M3 shipped.**

- **M1 — menu-bar skeleton:** start/stop a focus block from the menu bar, give it
  a label and an optional target, and watch a live counter in the status bar
  (counts down to a target, up when there's none, `+overtime` past it).
- **M2 — app-usage tracking:** while a block runs, the app records time spent in
  each frontmost app and the % of the block, with idle **Away** time detected
  separately. Live per-app tallies appear in the popover (the current app is
  always shown), and an end-of-block summary breaks down time + %, active vs.
  away, and an app-switch count. It records only — you interpret.
- **M3 — insights dashboard:** open a window from the menu bar with today / streak
  / last-14-days tiles, an active-minutes-per-day trend chart, top-apps and
  by-label breakdowns, and a recent-blocks history — aggregated from your saved
  sessions.

Next: **M4 — polish** (settings, launch-at-login).

## Requirements

- macOS 15.0 or later
- Xcode 26 (SwiftUI, SwiftData, Swift Charts)

## Build & run

Open the project in Xcode and press ⌘R:

```bash
open DeepFocusTracker.xcodeproj
```

DeepFocusTracker is a menu-bar-only agent (no Dock icon) — look for the 🧠 icon
in the status bar. It's signed to run locally, so no developer team is required.
(Opening the Dashboard briefly shows a Dock icon while its window is up.)

Or from the command line:

```bash
xcodebuild -project DeepFocusTracker.xcodeproj -scheme DeepFocusTracker \
  -configuration Debug -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/DeepFocusTracker.app
```

## Project structure

```
DeepFocusTracker.xcodeproj      Xcode project (build configuration only)
DeepFocusTracker/               Source (file-system synchronized group)
├── App/                        App entry point + menu-bar & dashboard scenes + SwiftData container
├── Models/                     SwiftData models (FocusSession, AppInterval, SessionLabel)
├── Focus/                      Session lifecycle + tracking:
│                                 FocusController, ActivityMonitor, IdleDetector, UsageAggregator
├── Insights/                   InsightsService — pure history aggregations (trends, streak, breakdowns)
├── Views/                      Menu-bar popover, status-item label, session summary,
│                                 and Dashboard/ (the insights window)
└── Support/                    Shared helpers (time formatting)
SPEC.md                         Full MVP specification
```

Because the source uses a file-system synchronized group, you can add or remove
files in the `DeepFocusTracker/` folder from any editor (Zed, Finder, …) and
Xcode picks them up automatically.

## Privacy

No account, no network calls, no telemetry. All data is stored locally on your
Mac, and the app makes no judgment about how you spend your time — it only
records where it went.
