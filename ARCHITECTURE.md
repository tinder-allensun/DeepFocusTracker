# Architecture

DeepFocusTracker is a small, local-only macOS menu-bar app built with **SwiftUI**
and **SwiftData**. This document explains how it's put together and *why*. For
*what* it does and the roadmap, see [SPEC.md](SPEC.md); for day-to-day working
conventions, see [CLAUDE.md](CLAUDE.md).

## Design philosophy

- **Records, doesn't judge.** The app measures where your time went during a
  focus block (per-app time + %). It deliberately makes *no* focus-vs-distraction
  classification — you interpret the numbers. This keeps the app out of
  error-prone, personal value judgments and simplifies the whole system.
- **Local & private.** No account, no network, no telemetry. All data lives in a
  local SwiftData store.
- **Menu-bar agent.** It's an `LSUIElement` accessory app: no Dock icon, no main
  menu; the UI is a menu-bar popover plus an on-demand dashboard window.
- **Simple, testable core.** The measurement/aggregation logic is written as
  pure value-in/value-out functions, kept separate from SwiftUI and SwiftData so
  it stays easy to reason about and unit-test.

## Module layout

**Two targets.** The **app** (`DeepFocusTracker/`) is a thin shell — the `@main`
entry and the scenes. Everything else — models, the tracking engine, aggregation,
and all the SwiftUI — lives in the **`DeepFocusCore` framework** (`DeepFocusCore/`),
which the app links + embeds and the tests link directly. Splitting the core out
is what lets the tests `@testable import DeepFocusCore` without launching the app
(see [Testing](#testing)). Both source folders (and `DeepFocusTrackerTests/`) are
file-system **synchronized groups** — see [Build & packaging](#build--packaging).

| Target · Folder | Responsibility |
|---|---|
| **app** · `DeepFocusTracker/App/` | `@main` entry (`DeepFocusTrackerApp`), the `AppDelegate` (sets `.accessory` policy), and the two scenes (menu-bar + dashboard). Imports `DeepFocusCore`; holds no logic. |
| `DeepFocusCore/Models/` | SwiftData `@Model` types: `FocusSession`, `AppInterval`, `SessionLabel`, `DayRollup`, `DayAppRollup`. |
| `DeepFocusCore/Focus/` | The tracking engine: `FocusController` (session lifecycle + state), `ActivityMonitor` (frontmost-app timeline), `IdleDetector` (idle → Away), `UsageAggregator` (pure per-app rollup), `Rollups` (denormalized daily rollups), `SessionHistory` (delete a block + its intervals). |
| `DeepFocusCore/Insights/` | `InsightsService` — pure aggregation of history into dashboard figures. |
| `DeepFocusCore/Views/` | `MenuBarView` (popover), `MenuBarLabel` (status-item), `SessionSummaryView`, and `Dashboard/` (`DashboardView`, `TodayReviewView`, `AllSessionsView`, `SessionDetailView`, `GuideView`). |
| `DeepFocusCore/Support/` | Shared helpers: `TimeFormat` (formatting), `LabelChooser` (label ordering), and `DeepFocusStore` (the SwiftData `ModelContainer` factory). |

A small `public` surface (`FocusController`, `DashboardNavigator`, the three
top-level views, `DashboardWindow.id`, `DeepFocusStore`) is what the app entry
point consumes; everything else is `internal` and reached by tests via
`@testable`.

## Data model

Five SwiftData entities: the three core records below, plus two denormalized
**daily rollups** (`DayRollup`, `DayAppRollup`) that keep the dashboard fast at
scale (see [Scalability & rollups](#scalability--rollups)). `AppInterval` links to
its session by a plain `UUID` (`sessionID`), **not** a SwiftData relationship —
intervals are written in a batch when a block ends. Because there's no
relationship, there's also **no cascade delete**: removing a session must
explicitly delete its intervals too (see `SessionHistory.delete`), or they orphan.

```
FocusSession                         AppInterval
├─ id: UUID  ◄───────────────────────┤  sessionID: UUID
├─ label: String                     ├─ appBundleID: String
├─ start: Date                       ├─ appName: String
├─ end: Date?            (nil = live) ├─ start: Date
├─ targetDuration: TimeInterval?     └─ duration: TimeInterval
├─ activeSeconds: TimeInterval = 0
├─ awaySeconds:   TimeInterval = 0
└─ switchCount:   Int = 0

SessionLabel:  name (unique), colorHex, createdAt, lastUsed?   // reusable quick-pick labels

DayRollup:     day (unique), activeSeconds, awaySeconds, blockCount
DayAppRollup:  day, bundleID, appName, seconds       // unique (day, bundleID)
```

`activeSeconds` / `awaySeconds` / `switchCount` are **cached totals** written when
a block ends (the authoritative per-app detail is the `AppInterval` rows). They
carry inline defaults (`= 0`) so SwiftData lightweight migration can populate
existing rows — see [Persistence & migration](#persistence--migration). At the same
moment the block's totals are folded into that day's rollups (and subtracted again
on delete) — see [Scalability & rollups](#scalability--rollups).

`SessionLabel` is a standalone quick-pick **catalog**, *not* linked to
`FocusSession` (a session stores its label as a plain `String` copy, so renaming a
label never rewrites past sessions). `FocusController.start` upserts it for any
non-empty typed label — a **case-insensitive** in-memory match bumps the used
label's `lastUsed`, otherwise a new label is inserted — and the pure `LabelChooser`
orders the menu-bar chips most-recently-used first, then never-used seed defaults
(stable by `createdAt` then `name`), capped at 5. `lastUsed` is optional, so the
store migrates without a default. Right-clicking a chip calls
`FocusController.deleteLabel` (a plain `context.delete`); because the catalog is
unlinked from sessions, this drops only the suggestion — no recorded session or
rollup changes. (Deleting *every* label leaves the table empty, so
`seedDefaultLabelsIfNeeded` reseeds the defaults on next launch.)

## Units, storage & the formatting boundary

DeepFocusTracker keeps **one base unit end-to-end and attaches human-readable
units only at the view**. Durations are stored, aggregated, and computed as raw
**seconds**; the reader-facing unit (`s` / `m` / `h`, or `MM:SS`) is applied at
render time and is *never* persisted. This keeps the arithmetic correct and the
store freely reformattable.

### What the store actually holds

The SwiftData/SQLite columns are plain numbers — there is **no "unit" column**.
The unit is a *convention*, carried two ways: the `TimeInterval` type (Foundation
documents it as a count of seconds) and the field names (`…Seconds`).

| Field | Type | De facto unit |
|---|---|---|
| `FocusSession.activeSeconds` / `awaySeconds` | `TimeInterval` | seconds |
| `FocusSession.targetDuration` | `TimeInterval?` | seconds |
| `AppInterval.duration` | `TimeInterval` | seconds |
| `DayRollup.activeSeconds` / `awaySeconds` | `TimeInterval` | seconds |
| `DayAppRollup.seconds` | `TimeInterval` | seconds |
| `FocusSession.switchCount`, `DayRollup.blockCount` | `Int` | a count (dimensionless) |
| `FocusSession.start` / `end`, `DayRollup.day` | `Date` | an instant (not a duration) |

`start` / `end` are *instants*; a duration is their difference
(`end.timeIntervalSince(start)`) which — being a `TimeInterval` — is also seconds.
So storage and every calculation speak one language.

> **Guardrail:** because the unit isn't stored, the type + `…Seconds` naming *is*
> the contract. Writing minutes into an `activeSeconds` field would compile and
> persist happily, and everything downstream would be silently 60× off. Keep new
> duration fields typed `TimeInterval`, named for their unit, and written in
> seconds.

### The pipeline: seconds in, string out

```
SwiftData store          aggregation (pure)          view (SwiftUI)
activeSeconds = 1547  →  InsightsService /        →  TimeFormat.compact(1547)
(a Double)               UsageAggregator sum         → "25m"  (transient, unsaved)
                         = still seconds
```

- **Storage** — raw seconds.
- **Aggregation** — `UsageAggregator`, `InsightsService`, `Rollups` take seconds
  and return seconds (sums, per-app totals, streaks). No strings, no units — which
  is *why* they stay free of SwiftUI/SwiftData and unit-testable.
- **View** — the only layer that attaches a unit, via `TimeFormat`. The formatted
  string lives for one render and is recomputed on the next tick.

You sum **numbers, not strings**: `1500 + 3900 = 5400 → "1h 30m"`. Formatting last
is what lets totals, percentages, and reformats (localizing, a seconds-precision
toggle, …) happen without touching stored data or a migration.

### Formatters and when to use them (`Support/TimeFormat.swift`)

| Formatter | Output | Use for |
|---|---|---|
| `clock` | `MM:SS` / `H:MM:SS` | the **live, ticking** menu-bar timer and running-block popover *only* |
| `compact` | `45s` / `25m` / `1h 20m` | every **reviewed / aggregate** total — dashboard tiles, lists, by-label, session detail, end-of-block summary |

`compact` is *self-labeling* (the unit is in the string) and rounds to a sensible
granularity (seconds under a minute, whole minutes above), so an aggregate can't
be misread as a stopwatch. `clock` is precise-to-the-second and ticks — right for
a live counter, wrong for a 14-day total.

### Two values derived at read time (also presentation, not storage)

- **Per-app %** is not stored; it's `app.seconds ÷ activeSeconds` computed in
  `UsageSummary.fraction(of:)` — a fraction of *active* time (Away excluded).
- **Chart axes** plot the raw number — the top-apps `BarMark` uses
  `x: .value("Focus time", app.seconds)` — and only the **axis tick labels** run
  through `TimeFormat.compact`. The bars come from the data; the unit is painted
  onto the labels, the same boundary as everywhere else.

### Adding a new metric — the rule of thumb

1. **Store** it in its base unit, typed and named for that unit
   (`somethingSeconds: TimeInterval`, a `count: Int`, …).
2. **Aggregate** in that base unit, inside the pure services.
3. **Format** only in the view; add a `TimeFormat` helper for any new shape rather
   than hand-formatting inline.

## Runtime data flow

### A focus block, start → finish

```
User clicks Start (MenuBarView)
      │
      ▼
FocusController.start(label:target:)
      ├─ insert + save FocusSession (end = nil)
      ├─ recordLabelUse(label)           → upsert quick-pick catalog (bump/insert lastUsed)
      ├─ ActivityMonitor.start()         → seeds current app as the open span
      └─ startTicking()                  → 1 s timer drives the live counter/tallies
      │
      ▼  (while running)
NSWorkspace.didActivateApplicationNotification   IdleDetector (polls CGEventSource)
      │  frontmost app changed                    │  idle > threshold → Away
      ▼                                            ▼
ActivityMonitor  ── builds an in-memory timeline: [AppSpan] + awaySeconds + switchCount
      │
      ▼  (popover reads, refreshed each tick)
FocusController.liveUsage → UsageAggregator.summarize(...) → live per-app tallies
      │
      ▼
User clicks End (MenuBarView)
      │
      ▼
FocusController.stop()
      ├─ ActivityMonitor.stop() → (spans, awaySeconds, switchCount)
      ├─ persist one AppInterval per span
      ├─ cache activeSeconds / awaySeconds / switchCount on the FocusSession
      ├─ Rollups.add(...) → fold the block into DayRollup / DayAppRollup
      ├─ save
      └─ expose lastSummary → SessionSummaryView (end-of-block breakdown)
```

Key point: **during a block the per-app timeline is held in memory** by
`ActivityMonitor`; it's only written to the store (as `AppInterval` rows) when
the block ends. See [Known limitations](#known-limitations--future).

### The dashboard

```
DashboardView (wrapped in a NavigationStack)
  ├─ @Query DayRollup + DayAppRollup (small, O(days)) + windowed & recent FocusSession
  │     — NOT AppInterval: the interval table is never loaded here
  ├─ map → [DayStat] + [AppDayStat] + [SessionRecord]
  ├─ InsightsService.compute(...) → Insights { today, streak, daily[], byApp[], byLabel[] }
  ├─ render: tiles + Swift Charts trend + top-apps chart + by-label + recent list
  └─ drill-in: recent list / AllSessionsView → SessionDetailView
       (rebuilds one block's UsageSummary from its AppInterval rows; can delete)
```

The **detail** path is judgment-free like the rest of the app: `SessionDetailView`
re-runs `UsageAggregator.summarize` over just that block's `AppInterval` rows
(scoped `@Query` on `sessionID`), feeding the cached `awaySeconds` / `switchCount`
totals, and shows the same numbers the end-of-block summary does — just for a
historical block, with no per-app cap. Deleting routes through
`SessionHistory.delete` (session + its intervals, and it decrements that day's
rollups) behind a confirmation.

The **Today review** (`TodayReviewView`, pushed from the Today tile via the
value route `TodayRoute`) is the same judgment-free shape scoped to *one day*: it
queries today's completed sessions (by `start`, so it agrees with the tile's
`DayRollup`-backed total) plus today's `DayAppRollup`, and the pure
`InsightsService.dayReview` folds them into the day's totals, per-app breakdown,
and the **off-focus gaps** between consecutive blocks (rendered as a muted
timeline connector — neutral "off focus", not "idle", since the app records
nothing between blocks).
Like the rest of the dashboard it never scans `AppInterval` for the aggregate —
only the per-block drill-in does, one session at a time. Its day boundary is
captured at open (see [Known limitations](#known-limitations--future)).

## Scalability & rollups

The dashboard must stay fast with tens of thousands of sessions / hundreds of
thousands of intervals. It does, because it **never loads the full `AppInterval`
table** — the per-app chart reads a small denormalized rollup instead, and its
session reads are windowed/limited and indexed.

- `DayRollup` — one row per active day (`activeSeconds` / `awaySeconds` /
  `blockCount`). Powers the tiles, trend, and streak. O(days) — a few hundred rows
  even after years.
- `DayAppRollup` — one row per (day, app) (`seconds`). Powers the top-apps chart.

Both are maintained incrementally: `Rollups.add` folds a block in at
`FocusController.stop()`; `Rollups.remove` subtracts it in `SessionHistory.delete`.
Keeping them consistent on **both** paths is essential — the dashboard trusts the
rollups, not the raw rows. (Upserts must *accumulate*, and `#Unique`'s collision
behavior *replaces*, so `Rollups` fetch-or-creates and adds by hand.)

`#Index`es on `FocusSession.start`/`.end`, `AppInterval.(sessionID, start)`, and
the rollups' `day` keep every query off table scans. Because the working set is
small, all of it stays on the **main thread** — no background `@ModelActor`
needed; that would only matter for genuinely heavy work, which the rollups
eliminate.

**Dev benchmark:** launch the debug binary with `SEED_TEST_DATA=<n>` to populate a
fresh store with *n* synthetic sessions + intervals + rollups (`TestDataSeeder`),
to confirm the dashboard stays flat as the raw tables grow.

## Concurrency & state

- Everything user-facing runs on the **main actor**. `FocusController`,
  `ActivityMonitor`, and `IdleDetector` are `@MainActor`.
- UI state uses the **Observation** framework: `FocusController` is
  `@Observable`, injected into the menu-bar views via `.environment(...)`.
  Reading `focus.tick` (a 1 s-updated `Date`) in a view's body is what refreshes
  the live counter and tallies each second.
- **Timers** are created with `Timer(timeInterval:repeats:)` and added to
  `RunLoop.main` in `.common` mode (so they keep firing while the menu/popover
  is open). Their closures hop back onto the main actor with
  `MainActor.assumeIsolated { … }` (they already run on the main run loop).
- The project builds in **Swift 5 language mode** (`SWIFT_VERSION = 5.0`) to keep
  strict-concurrency checking out of the way for the MVP.

## Persistence & migration

- **Store:** a local SwiftData/SQLite store at an explicit app-specific path,
  `~/Library/Application Support/DeepFocusTracker/Focus.store` (+ `-wal` / `-shm`).
  The explicit `url:` avoids SwiftData's generic default (`…/default.store`),
  which is unnamespaced and could collide with another non-sandboxed SwiftData
  app. No CloudKit.
- **Container factory** (`DeepFocusTrackerApp.makeContainer()`) is *self-healing*:
  1. try to open the on-disk store;
  2. if that fails (e.g. an incompatible schema during development), delete the
     store files and retry with a fresh store;
  3. as a last resort, fall back to an **in-memory** store so the app still
     launches instead of hard-crashing.
- **Migration rule (important):** any *new non-optional* attribute must have an
  inline default (e.g. `var activeSeconds: TimeInterval = 0`). Without it,
  SwiftData can't populate the column for existing rows and lightweight
  migration fails — which previously caused a silent fall-through to the
  in-memory store (no persistence). This was the M3 migration fix.
- There is **no versioned migration plan yet** — acceptable while data is
  disposable; add one before real user data accumulates.

## Menu-bar agent & windows

- `LSUIElement = YES` (Info.plist, via `INFOPLIST_KEY_LSUIElement`) *and*
  `NSApp.setActivationPolicy(.accessory)` at launch make it a no-Dock-icon agent.
- The popover is a SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- The **dashboard** is a separate `Window` scene. Because an accessory app has no
  normal windows, opening it (`DashboardWindow.show`) flips the app to
  `.regular` + `NSApp.activate()` so the window can take focus and appear in the
  app switcher; closing it (`DashboardView.onDisappear`) reverts to `.accessory`.
- **Status-item label caveat:** the menu bar can't render an image *interpolated
  inside* a `Text`. Show icon + text as sibling views in an `HStack` instead.

## Build & packaging

- **Hand-authored `.xcodeproj`** (no XcodeGen/Tuist), **three targets**: the app,
  the **`DeepFocusCore`** framework (linked + embedded in the app), and the
  `DeepFocusTrackerTests` bundle (links the framework, no host). Each maps to a
  **file-system synchronized group**, so **add/remove `.swift` files on disk and
  they're picked up; no `project.pbxproj` editing** — except adding a whole new
  target.
- **Deployment target:** macOS 15.0. **Toolchain:** Xcode 26 / Swift 6.2 compiler
  in Swift 5 language mode.
- **Signing:** ad-hoc ("Sign to Run Locally", `CODE_SIGN_IDENTITY = "-"`) — no
  developer team required. No entitlements / App Sandbox yet.
- **Frameworks:** SwiftUI, SwiftData, Swift Charts, AppKit (`NSWorkspace`,
  `NSApplication`), CoreGraphics (`CGEventSource`).

## Key design decisions (and why)

- **No focus/distraction judgment** — classification is subjective and
  error-prone (a browser is work *or* a rabbit hole). Recording raw per-app time
  and letting the user interpret is more honest and much simpler.
- **App-level tracking only** — using `NSWorkspace` frontmost-app events needs
  *no* permission. Window-title tracking would be finer but requires
  Accessibility; deferred.
- **Event-driven, not polling** — react to `didActivateApplicationNotification`
  rather than sampling; cheaper and precise to the actual switch.
- **Idle → Away bucket** — so time you stepped away isn't blamed on whatever app
  was frontmost.
- **Pure aggregators** (`UsageAggregator`, `InsightsService`) — decoupled from
  SwiftUI/SwiftData for testability and reuse (the dashboard's per-app rollup
  reuses `UsageAggregator`).
- **Menu-bar agent** — a focus tool should be always-there but never in the way.
- **Hand-authored synced-group project** — no generator dependency; low
  maintenance; editable outside Xcode.
- **Self-healing store + attribute defaults** — dev-time robustness against
  schema churn without a full migration plan.

## Testing

A **Swift Testing** target, `DeepFocusTrackerTests/`, covers the whole non-UI core.
It's the guardrail: every behavioral change adds/updates tests and `xcodebuild test`
must be green before commit (CI enforces it). See
[CLAUDE.md](CLAUDE.md#testing-the-guardrail) for the working rule; this is the *why*.

**What's covered**

- **Pure aggregators** — `UsageAggregator`, `InsightsService`, `TimeFormat`,
  `LabelChooser`: value-in/value-out unit tests. `InsightsService`/`Rollups` take an
  injected `now` / `Calendar`, so windows, streaks, and day-keys are deterministic
  under a fixed UTC calendar.
- **SwiftData paths** — `FocusController` (start/stop lifecycle, label upsert,
  seeding, open-session recovery), `Rollups` (accumulate/decrement, row cleanup),
  and `SessionHistory` (delete session + intervals, no orphans): integration tests
  against an in-memory store. `RollupConsistencyTests` seeds data and asserts the
  denormalized rollups equal a full recompute from the raw rows — a direct guard on
  the [Scalability & rollups](#scalability--rollups) invariant.
- **Views** are *not* unit-tested — interactive behavior is verified by driving the
  running app.

**How it's wired (and why)**

- **Swift Testing, not XCTest** — `@Test` / `#expect` read more clearly and it's the
  current default in the Xcode 26 toolchain.
- **The core is a framework** (`DeepFocusCore`). The test bundle links it and does
  `@testable import DeepFocusCore`, so tests run as fast logic tests **without a
  host app** — and the app entry point carries no test-only code. (An *app* target's
  symbols aren't linkable without hosting it, which is why the core is a framework.)
- **One container per process.** Two `ModelContainer`s over the same `@Model` types
  in one process make CoreData trap ("multiple NSEntityDescriptions claim the
  NSManagedObject subclass"), so the tests share one in-memory container
  (`TestStore.shared`), wiped per test for isolation. Store-touching suites are
  `@MainActor`, which matches the app's isolation and serializes them so the shared
  container is race-free.

## Known limitations & future

- **Mid-block data is in memory** until the block ends; a crash mid-block loses
  that block's per-app detail (the open `FocusSession` is recovered on next
  launch, but its intervals aren't). Recovery restarts tracking from launch.
- **No versioned migration plan** (see Persistence & migration).
- **Per-app % is of active time** (excludes Away) — could be made configurable.
- **Single dashboard window**; no export. Blocks can be inspected and deleted,
  but not edited.
- **The dashboard's day window is captured at open.** `DashboardView` and
  `TodayReviewView` derive their `today` boundary from `now` at init, so a window
  left open across midnight keeps showing the prior day until it's reopened.
  Acceptable for a menu-bar app normally opened on demand; a day-rollover refresh
  is the fix if it becomes annoying.
- See [SPEC.md](SPEC.md) §11 for the running list of open questions.
