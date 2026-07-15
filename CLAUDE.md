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

- Ad-hoc signed ("Sign to Run Locally") — **no developer team required**.
- It's a menu-bar agent: look for the 🧠 status-bar icon (no Dock icon).
- **Verifying changes:** a green build is necessary but not sufficient. Live
  tracking and the dashboard are interactive — drive them in the running app
  (start a block, switch apps, open the dashboard). Pure logic can be reasoned
  about / unit-tested directly.

Ship a Release build (install locally or make a shareable zip) with
`scripts/package.sh` — see [PACKAGING.md](PACKAGING.md).

## Project layout

`DeepFocusTracker/` → `App/`, `Models/`, `Focus/`, `Insights/`, `Views/`,
`Support/`. Responsibilities are in [ARCHITECTURE.md](ARCHITECTURE.md#module-layout).
The project uses **file-system synchronized groups**: add or remove `.swift`
files in that folder and Xcode picks them up — **no `project.pbxproj` editing.**

## Conventions

- Swift + SwiftUI; match the surrounding style, naming, and comment density.
- UI runs on the main actor; shared state uses `@Observable` (Observation).
- Keep pure logic (aggregation, formatting) free of SwiftUI/SwiftData imports.
- Comments explain *why*, not *what*; keep them where a future reader would trip.

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
- **Git hook:** commits print a *"public repository"* warning (a corporate JAMF
  hook). A remote now exists (`origin` →
  `github.com:tinder-allensun/DeepFocusTracker`); the hook flags it as **public**,
  so confirm that's intended before pushing — this project is meant to be private.

## Commit conventions

- Milestone-style subject (e.g. `Add M2: per-app usage tracking within focus blocks`).
- End commit messages with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Keep `SPEC.md` (status/roadmap) and these docs in sync with the code in the
  same commit that changes behavior.

## Status

M1–M3 shipped; **M4 (polish: settings, launch-at-login)** is next. The
authoritative status/roadmap is [SPEC.md](SPEC.md) §10 — update it there, not here.
