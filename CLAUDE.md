# CLAUDE.md

Working guide for Claude Code (and any coding agent or new contributor) in this
repo. **Product scope & roadmap:** [SPEC.md](SPEC.md). **Design details:**
[ARCHITECTURE.md](ARCHITECTURE.md). **Contributor workflow:**
[CONTRIBUTING.md](CONTRIBUTING.md).

## What this is

DeepFocusTracker — a local-only macOS menu-bar app (SwiftUI + SwiftData) that
records where your time goes during a focus block and shows it in a dashboard.
It **records, it does not judge** (no focus/distraction labels).

## Golden rules

- **Records, doesn't judge.** Never add automatic focus/distraction
  classification. The app reports; the user interprets.
- **Local & private.** No network calls, accounts, analytics, or telemetry.
- **Menu-bar agent.** No Dock icon in normal use (`LSUIElement`). Don't add a
  primary window; the dashboard is opened on demand.
- **MVP mindset.** Prefer the simplest thing that works and reads clearly. Keep
  measurement/aggregation logic pure and separate from UI.
- **Tests are the guardrail.** Every behavioral change ships with tests that
  cover it, and `xcodebuild test` must be green before you commit — this is how
  we stay confident a change (or a future refactor) didn't break the core. Pure
  logic gets a unit test; anything touching the store or rollups gets a SwiftData
  integration test. A green *build* alone is **not** sufficient. See
  [Testing](#testing-the-guardrail).

## Build, run, verify

Open in Xcode and run (⌘R):

```bash
open DeepFocusTracker.xcodeproj
```

Headless build (used for CI-style verification):

```bash
xcodebuild -project DeepFocusTracker.xcodeproj -scheme DeepFocusTracker \
  -configuration Debug -derivedDataPath DerivedData build
# built app:
open DerivedData/Build/Products/Debug/DeepFocusTracker.app
```

Run the test suite (**required** before commit — see [Testing](#testing-the-guardrail)):

```bash
xcodebuild test -project DeepFocusTracker.xcodeproj -scheme DeepFocusTracker \
  -configuration Debug -derivedDataPath DerivedData -destination 'platform=macOS'
```

- Ad-hoc signed ("Sign to Run Locally") — **no developer team required**.
- It's a menu-bar agent: look for the 🧠 status-bar icon (no Dock icon).
- **Verifying changes:** a green build is necessary but not sufficient. First,
  `xcodebuild test` must pass (and cover your change). Then, because live tracking
  and the dashboard are interactive, drive them in the running app (start a block,
  switch apps, open the dashboard). Pure logic is covered by the unit tests.

Ship a Release build (install locally or make a shareable zip) with
`scripts/package.sh` — see [PACKAGING.md](PACKAGING.md).

## Project layout

Two targets: the **app** (`DeepFocusTracker/` → `App/` + assets — just the `@main`
entry, `AppDelegate`, and scenes) and the **`DeepFocusCore` framework**
(`DeepFocusCore/` → `Models/`, `Focus/`, `Insights/`, `Views/`, `Support/`) that
holds all the logic and UI. Tests live in `DeepFocusTrackerTests/` and link the
framework directly. Responsibilities are in
[ARCHITECTURE.md](ARCHITECTURE.md#module-layout); testing is
[below](#testing-the-guardrail).

All three folders are **file-system synchronized groups**: add or remove `.swift`
files and Xcode picks them up — **no `project.pbxproj` editing** (adding a whole
new *target* is the rare exception that does).

`tmp/` at the repo root is a **git-ignored scratchpad** for generated documents
(plans, notes, throwaway analysis) — write those there, never into the tracked
tree.

## Conventions

- Swift + SwiftUI; match the surrounding style, naming, and comment density.
- UI runs on the main actor; shared state uses `@Observable` (Observation).
- Keep pure logic (aggregation, formatting) free of SwiftUI/SwiftData imports.
- **Units:** store and aggregate durations in **seconds** (`TimeInterval`); attach
  human units only in the view via `TimeFormat` — `clock` (MM:SS) for the live
  menu-bar timer, `compact` (`25m`, `1h 20m`) for aggregate totals. See
  ARCHITECTURE.md [Units, storage & the formatting boundary](ARCHITECTURE.md#units-storage--the-formatting-boundary).
- Comments explain *why*, not *what*; keep them where a future reader would trip.

## Testing (the guardrail)

Tests live in `DeepFocusTrackerTests/` and use **Swift Testing** (`@Test` /
`#expect`, `import Testing`). They link the **`DeepFocusCore` framework** directly
(`@testable import DeepFocusCore`) — the app isn't launched — and run in well under
a second via the `xcodebuild test` command above.

**The rule for any change:** add or update tests so the new behavior is covered,
and make `xcodebuild test` green *before* committing. This is the guardrail that
lets us refactor with confidence. Concretely:

- **Pure logic** (`UsageAggregator`, `InsightsService`, `TimeFormat`,
  `LabelChooser`, and any new value-in/value-out code) → a **unit test**. Inject
  `now` / `Calendar` for determinism (see `InsightsServiceTests`).
- **Anything touching the store or rollups** (`FocusController`, `Rollups`,
  `SessionHistory`, a new `@Model` or query) → a **SwiftData integration test**
  against an in-memory store (`TestStore.makeContext()`). If it creates or removes
  sessions/intervals, assert the `DayRollup` / `DayAppRollup` stay consistent (see
  `RollupsTests`, `RollupConsistencyTests`).
- **SwiftUI views** aren't unit-tested — verify those by driving the running app.

Adding test files needs no `project.pbxproj` editing (synced group). CI runs
`xcodebuild test` on every push / PR (`.github/workflows/ci.yml`).

## Gotchas (learned the hard way)

- **SwiftData migrations:** every *new non-optional* `@Model` attribute needs an
  inline default (e.g. `var x: TimeInterval = 0`). Without it, migrating an
  existing store fails and the app silently falls back to an in-memory store (no
  persistence). Watch the console for `CoreData … 134110 … Cannot migrate`.
- **Menu-bar label:** you can't render an SF Symbol *interpolated inside* a
  `Text` in the status bar. Use `HStack { Image(...) ; Text(...) }`.
- **Opening a window from the agent:** an `LSUIElement` app must flip
  `NSApp.setActivationPolicy(.regular)` + `activate()` to show a window, and
  revert to `.accessory` on close (see `DashboardWindow`).
- **NavigationStack back button (dashboard):** in the dashboard `Window`, the
  system-injected back button overlaps the pushed view's title and won't accept
  clicks. Hide it with `.navigationBarBackButtonHidden(true)` and supply your own
  toolbar `Button` wired to `@Environment(\.dismiss)` (see `AllSessionsView` /
  `SessionDetailView`).
- **NavigationStack — don't mix link styles:** keep **all** pushes value-based
  (`.navigationDestination(for:)` + `NavigationLink(value:)`). Mixing in a
  destination-closure link (`NavigationLink { SomeView() }`, e.g. the old
  "See all") desyncs the typed path and *intermittently* misroutes Back — popping
  one screen can jump into a detail view. Add a tiny `Hashable` route type
  (`AllSessionsRoute`) rather than a closure link.
- **Timers:** add to `RunLoop.main` in `.common` mode and use
  `MainActor.assumeIsolated { … }` inside the closure.
- **Store reset during dev:** the store lives at
  `~/Library/Application Support/DeepFocusTracker/Focus.store` (an explicit
  app-specific path, not SwiftData's generic `default.store`). If you change the
  schema and hit a migration wall, delete `Focus.store*` there (the container
  also self-heals).
- **Rollups back the dashboard — keep them consistent:** the dashboard's
  tiles / trend / streak / top-apps read `DayRollup` / `DayAppRollup`, *not* the
  raw tables. `Rollups.add` maintains them at `FocusController.stop()`;
  `Rollups.remove` decrements them in `SessionHistory.delete`. Any new path that
  creates or removes sessions/intervals must update the rollups too, or the
  dashboard drifts. Dev: launch with `SEED_TEST_DATA=<n>` to seed a fresh store
  (`TestDataSeeder`).
- **The core lives in a framework so it's testable.** `DeepFocusCore` (all of
  `Models/` / `Focus/` / `Insights/` / `Views/` / `Support/`) is a framework the
  app links + embeds; the app target is just the `@main` entry + scenes. That's
  what lets the tests `@testable import DeepFocusCore` and run **without launching
  the app**. The app-facing types the entry point uses (`FocusController`,
  `DashboardNavigator`, the three top-level views, `DashboardWindow.id`,
  `DeepFocusStore`) are `public`; everything else stays `internal` (tests reach it
  via `@testable`). Adding a `public` API? Keep the public surface minimal.
- **One `ModelContainer` per process in tests:** creating a *second*
  `ModelContainer` over the same `@Model` types in one process makes CoreData
  **trap** on the first `fetch`/`insert` ("multiple NSEntityDescriptions claim the
  NSManagedObject subclass"). So the tests share a single in-memory container
  (`TestStore.shared`); each test starts clean via `TestStore.makeContext()` —
  don't spin up per-test containers. Store-touching suites are `@MainActor`, which
  also serializes them so the shared container is race-free.
- **Git hook:** commits print a *"public repository"* warning (a corporate JAMF
  hook). This is expected and safe to ignore: the repo (`origin` →
  `github.com:tinder-allensun/DeepFocusTracker`) is **intentionally public**, so
  pushing there is fine.

## Commit conventions

- Milestone-style subject (e.g. `Add M2: per-app usage tracking within focus blocks`).
- End commit messages with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Keep `SPEC.md` (status/roadmap) and these docs in sync with the code in the
  same commit that changes behavior.

## Status

M1–M3 shipped; **M4 (polish: settings, launch-at-login)** is next. The
authoritative status/roadmap is [SPEC.md](SPEC.md) §10 — update it there, not here.
