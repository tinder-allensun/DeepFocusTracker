# DeepFocusTracker

A privacy-first macOS menu-bar app for doing — and measuring — deep focus work.
Start a focus block (naming what you're working on) and DeepFocusTracker tracks
how focused you stayed, gently nudges you when you drift, and shows where your
focus goes over time. Everything stays local on your Mac.

See [`SPEC.md`](SPEC.md) for the full product specification.

## Status

**M1 (menu-bar skeleton) — shipped.** You can start/stop a focus block from the
menu bar, give it a label and an optional target, and watch a live counter in
the status bar (counts down to a target, up when there's none, `+overtime` past
it). Sessions persist locally via SwiftData.

Next up: automatic app-usage measurement + focus scoring (M2), gentle nudges
(M3), and the insights dashboard (M4).

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
├── App/                        App entry point + menu-bar scene
├── Models/                     SwiftData models + FocusCategory
├── Focus/                      FocusController (session lifecycle, live tick)
├── Views/                      Menu-bar popover + status-item label
└── Support/                    Shared helpers (time formatting)
SPEC.md                         Full MVP specification
```

Because the source uses a file-system synchronized group, you can add or remove
files in the `DeepFocusTracker/` folder from any editor (Zed, Finder, …) and
Xcode picks them up automatically.

## Privacy

No account, no network calls, no telemetry. All data is stored locally on your
Mac.
