# Contributing

DeepFocusTracker is a small, local-only macOS menu-bar app; the goal is a clean,
well-documented MVP. This guide covers setup and workflow — for design see
[ARCHITECTURE.md](ARCHITECTURE.md), and for the working conventions/gotchas see
[CLAUDE.md](CLAUDE.md).

## Prerequisites

- macOS 15.0 or later
- Xcode 26 (Swift 6.2 toolchain; the project builds in **Swift 5 language mode**)

## Getting started

```bash
open DeepFocusTracker.xcodeproj   # then press ⌘R
```

No developer team is required (ad-hoc "Sign to Run Locally"). It's a no-Dock-icon
agent — look for the 🧠 icon in the menu bar.

Command-line build:

```bash
xcodebuild -project DeepFocusTracker.xcodeproj -scheme DeepFocusTracker \
  -configuration Debug -derivedDataPath DerivedData build
```

## Project layout & design

See [ARCHITECTURE.md](ARCHITECTURE.md). The `DeepFocusTracker/` source folder uses
Xcode **file-system synchronized groups** — add or remove `.swift` files on disk
and they're picked up automatically; **no `project.pbxproj` editing.**

## Code style

- Swift + SwiftUI; match the surrounding code's style, naming, and comment density.
- UI runs on the main actor; shared state via `@Observable` (Observation).
- Keep pure logic (aggregation, formatting) free of SwiftUI/SwiftData imports.
- Comments explain *why*, not *what*.

## Testing & verification

- The pure logic (`UsageAggregator`, `InsightsService`, `TimeFormat`) is
  value-in/value-out and unit-testable. Add an XCTest target
  (`DeepFocusTrackerTests`) targeting those types when it's worth it.
- A green build is necessary but **not sufficient** for interactive features —
  run the app and drive the change (start a block, switch apps, open the
  dashboard).

## Gotchas

The traps already hit — SwiftData migration defaults, menu-bar label rendering,
`LSUIElement` window activation, timer isolation — are documented in
[CLAUDE.md](CLAUDE.md#gotchas-learned-the-hard-way). Read them before touching
those areas.

## Commits & docs

- Branch off `main` for non-trivial work.
- Use milestone-style commit subjects, and end messages with the
  `Co-Authored-By:` line (see [CLAUDE.md](CLAUDE.md#commit-conventions)).
- Keep docs current **in the same change**: [SPEC.md](SPEC.md) status/roadmap,
  [CHANGELOG.md](CHANGELOG.md), and [ARCHITECTURE.md](ARCHITECTURE.md) when the
  design changes.
- No remote is configured; if you add one, make it **private** (the commit hook
  will remind you).
