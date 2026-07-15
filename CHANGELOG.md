# Changelog

Notable changes to DeepFocusTracker. Organized by MVP milestone until the first
tagged release; loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

- **M4 — Polish** (planned): a Settings window (default block length, idle
  timeout), launch-at-login via `SMAppService`, a `SettingsStore`, and small
  niceties (menu-bar template icon, empty states, About).
- **Packaging:** `scripts/package.sh` (Release build → installable / shareable
  zip) plus [PACKAGING.md](PACKAGING.md) covering the distribution options
  (ad-hoc, Developer ID + notarization, App Store).

## M3 — Insights dashboard — 2026-07-14

- **Added:** dashboard `Window` opened from the popover — today / streak /
  last-14-days tiles, an active-minutes-per-day trend (Swift Charts), top-apps
  and by-label breakdowns, and a recent-blocks list.
- **Added:** `InsightsService`, a pure aggregation of stored history.
- **Fixed:** SwiftData store migration — `FocusSession.activeSeconds` /
  `awaySeconds` now carry inline defaults so lightweight migration works;
  previously migration failed and the app silently ran in-memory (no persistence).

## M2 — App-usage tracking — 2026-07-14

- **Added:** per-app time + % tracking within a block (`ActivityMonitor`,
  `IdleDetector`, pure `UsageAggregator`), with idle **Away** detection.
- **Added:** live per-app tallies in the popover (current app always pinned +
  highlighted) and an end-of-block session summary (time + %, active vs. away,
  app-switch count).
- **Added:** self-healing SwiftData container (reset + in-memory fallback).
- **Changed:** removed focus/distraction categorization — the app records, the
  user interprets. Simplified the data model (dropped `FocusCategory` and
  `AppCategoryRule`).
- **Removed:** planned real-time nudges (didn't fit the no-judgment design).

## M1 — Menu-bar skeleton — 2026-07-14

- **Added:** menu-bar-only agent app (`MenuBarExtra`, `LSUIElement`), start/stop
  focus blocks with labels and an optional target, and a live status-bar counter
  (countdown / count-up / overtime).
- **Added:** SwiftData models and `FocusController` (session lifecycle, label
  seeding, open-session recovery).
- **Added:** hand-authored Xcode project (file-system synchronized groups),
  targeting macOS 15, ad-hoc signed to run locally.
