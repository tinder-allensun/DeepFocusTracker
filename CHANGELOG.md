# Changelog

Notable changes to DeepFocusTracker. Organized by MVP milestone until the first
tagged release; loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- **Testable core + CI.** Extracted all logic and UI into a **`DeepFocusCore`**
  framework (the app target is now just the `@main` entry + scenes), and added a
  **Swift Testing** suite (`DeepFocusTrackerTests/`, 45 tests / 8 suites) covering
  the pure aggregators (`UsageAggregator`, `InsightsService`, `TimeFormat`,
  `LabelChooser`) and the SwiftData paths (`FocusController`, `Rollups`,
  `SessionHistory`), including a `DayRollup`/`DayAppRollup`-vs-raw consistency
  check. **GitHub Actions CI** runs `xcodebuild test` on every push / PR. The rule
  is now documented (CLAUDE.md → Testing): every behavioral change ships with tests
  and a green `xcodebuild test`.
- **In-app "How to use" guide** (`GuideView`) reached from a **?** in the popover
  header and the dashboard toolbar: how tracking works, a glossary of every metric
  (Active, Away, Switches, per-app %, Target, Streak) with how each is calculated,
  and the privacy stance.
- `TimeFormat.compact` — self-labeling durations (`45s`, `25m`, `1h 20m`) for
  aggregate totals.

### Changed

- Dashboard tiles/lists/by-label, session detail, and the end-of-block summary now
  show durations in the readable **compact** form instead of `MM:SS`; the top-apps
  chart x-axis shows compact time ticks (was unlabeled raw minutes like `0.02`).
  `clock()` (MM:SS) is now used only for the live menu-bar timer.

### Fixed

- Opening the dashboard could land on the guide (or another stale pushed screen)
  when it had been left open without navigating back. The popover now states its
  destination and the stack resets on close, so **Dashboard → overview** and
  **? → guide** every time.

### Docs

- ARCHITECTURE.md: new **"Units, storage & the formatting boundary"** section —
  seconds as the stored unit, and where human units get attached.

### Planned

- **M4 — Polish:** a Settings window (default block length, idle timeout),
  launch-at-login via `SMAppService`, a `SettingsStore`, and small niceties
  (menu-bar template icon, empty states, About).
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
