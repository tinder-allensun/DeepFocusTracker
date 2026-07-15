# DeepFocusTracker — MVP Specification

_Last updated: 2026-07-14 · Status: M1–M3 shipped; M4 (polish) next_

## 1. Overview

DeepFocusTracker is a privacy-first macOS menu-bar app that helps you do — and
review — deep focus work. You start a **focus block** (naming what you're
working on), and the app quietly records how long you spend in each application
during that block. It doesn't judge what's "focus" vs. "distraction" — it shows
you where your time actually went, and you interpret it.

All data stays local on the Mac. No account, no network, no telemetry.

**Core loop:**

```
Start block (+ label)
   → app records time spent per app while you work
   → block ends
   → per-app time + % summary
   → rolls into dashboard stats
```

## 2. Goals & non-goals

**Goals (MVP)**
- Make it effortless to start a focus block and see, afterward, where your time went.
- Record per-app usage automatically — no reliance on memory or self-report.
- Leave interpretation to you: the app reports, it doesn't judge focus vs. distraction.
- Surface trends over time (how much deep-work time, and where it goes).
- Frictionless install — no special system permissions.
- Fully local and private.

**Non-goals (MVP)**
- Not a to-do / project manager.
- Not an all-day background tracker (usage is recorded only *within blocks*).
- Not a website/app blocker.
- **Not a judge** — it won't label apps "focus" or "distraction"; it records, you decide.
- No cloud sync or mobile companion (yet).

## 3. Product decisions (locked)

| Decision | Choice |
|---|---|
| Tracking approach | **Hybrid** — you start a session; the app auto-records app usage during it |
| Focus judgment | **None** — the app records per-app time + %; you interpret it (no focus/distraction labels) |
| Organization | **Lightweight tasks/labels** (name + color per block) |
| Primary interface | **Menu bar + dashboard window** |
| Menu-bar counter | **Live MM:SS** — counts down to a target (**+overtime** past it), counts up when no target is set |
| Tracking granularity | **App-level only** (frontmost application; no window titles → no Accessibility permission) |
| Idle handling | Idle (no input ~2 min) is recorded as its own **"Away"** bucket, not attributed to any app |
| Breaks / Pomodoro | **Not in v1** — blocks are open-ended or single-target |

## 4. MVP feature set (in scope)

| # | Feature | Detail |
|---|---------|--------|
| 1 | **Menu-bar control** | Start/stop a focus block, with a live counter in the status bar (app icon + time) that **counts down** to a target — showing **+overtime** past it — or **counts up** when no target is set. Optional target duration (e.g. 50 min). |
| 2 | **Session labels** | Name each block or pick a reusable label (e.g. *Writing*, *Coding*, *Email*) with a color. |
| 3 | **Automatic app-usage tracking** | While a block runs, record time spent in each frontmost app and the **% of the block** it took, plus idle **"Away"** time. The current app is always shown. No focus/distraction judgment — just the numbers. |
| 4 | **Session summary** | On block end: per-app **time + %**, active vs. away time, and an **app-switch count**. You review and interpret it. |
| 5 | **Dashboard window** | Today/streak/last-14-days tiles, an active-minutes-per-day trend, per-app and per-label breakdowns, and a recent-blocks history — aggregated across sessions. |
| 6 | **Settings** | Default block length, idle timeout, launch-at-login. |
| 7 | **Local & private** | No account, no network calls, no telemetry. Data in a local store on the Mac. |

## 5. Out of scope (candidates for later)

- **Automatic focus/distraction classification** — deliberately omitted; the app records, you interpret.
- **Real-time nudges / drift interventions** — deferred (see note under §10); revisit once you've reviewed your own patterns.
- Active app/website **blocking**.
- In-browser **URL/tab tracking**.
- Window-**title** tracking (optional opt-in later; would add Accessibility permission for finer per-app context).
- **All-day** automatic tracking (no session needed).
- Projects/goals hierarchy with targets.
- Pomodoro **break** scheduling.
- macOS **Focus-mode** / **Calendar** integration.
- **iCloud sync** / iOS companion.
- Data **export**.

## 6. Data model (sketch)

- **FocusSession** — `id, label, start, end, targetDuration?, activeSeconds, awaySeconds`
- **AppInterval** — `sessionId, appBundleId, appName, start, duration`
- **SessionLabel** — `name, colorHex, createdAt`
- **Settings** — `defaultDurationMin, idleTimeoutSec, launchAtLogin` (`@AppStorage`-backed)

_A session's per-app time + % is derived from its `AppInterval`s; `activeSeconds` /
`awaySeconds` are cached on the session at stop for fast dashboard rollups._
_New non-optional attributes carry inline defaults (`= 0`) so SwiftData lightweight
migrations can populate existing rows._

## 7. Tracking behavior

- **Active-app detection** is event-driven via `NSWorkspace` activation notifications: each time the frontmost app changes, close the current span and record an `AppInterval` (bundle id, name, start, duration).
- **Idle / Away** via input-event idle time (`CGEventSource`): after `idleTimeoutSec` (~2 min) with no input, that time accrues to an **Away** bucket instead of the frontmost app; attribution resumes on the next input.
- **Per-app breakdown** = sum of each app's interval durations; **%** = per-app time ÷ active (non-away) time.
- **App-switch count** = number of frontmost-app changes during the block (an objective, judgment-free measure of fragmentation).
- **Sleep/wake** and **screen lock** are treated as span boundaries and count as Away.

## 8. Permissions

| Capability | Permission needed |
|---|---|
| Frontmost-app tracking | **None** (`NSWorkspace`) |
| Idle detection | **None** (input-event idle time) |
| Launch at login | **None** (`SMAppService`) |

_MVP requires **no special permissions** — no Accessibility, Screen Recording, or Notifications._

## 9. Tech stack

- **Swift + SwiftUI**, targeting current macOS (deployment target macOS 15.0).
- Menu bar: `MenuBarExtra` (window style for the popover). Dashboard: a `Window` scene.
- Charts: **Swift Charts** (dashboard).
- Persistence: **SwiftData** (local store; attribute defaults keep migrations lightweight, with a self-healing / in-memory fallback if a store can't be opened).
- Active-app events: `NSWorkspace.didActivateApplicationNotification`.
- Idle: `CGEventSource`. Launch-at-login: `SMAppService`.

## 10. Build milestones & implementation plan

Roadmap (details below). Every milestone ships something you can *see* working — see each **Verify** line.

| Milestone | Status | In one line |
|---|---|---|
| M1 — Skeleton | ✅ shipped | Menu-bar app, start/stop blocks, labels, live counter, SwiftData |
| M2 — Usage tracking | ✅ shipped | Per-app time + % during a block + session summary |
| M3 — Insights | ✅ shipped | Dashboard window: tiles, trend, breakdowns, recent history |
| M4 — Polish | ← next | Settings, launch-at-login |

### M1 — Skeleton ✅ (shipped)
- **Built:** menu-bar-only agent (`MenuBarExtra`, `LSUIElement`, `.accessory`); SwiftData models + `FocusController` (start/stop, recover open block, seed labels, 1 s tick); popover UI + status-item label with the live counter; `TimeFormat`.
- **Verify:** builds via `xcodebuild`; launches as a menu-bar agent; start/stop a block and watch the counter.

### M2 — Automatic app-usage tracking ✅ (shipped)
- **Goal:** while a block runs, record how long you spend in each app and what % of the block that was — **no focus/distraction judgment**. You review the breakdown.
- **Built:** active-app tracking (`AppInterval` per span); idle/Away detection; live popover tallies with the **current app always pinned/highlighted**; end-of-block **summary** (per-app time + %, active vs. away, app-switch count); self-healing SwiftData store.
- **Key files:** `Focus/ActivityMonitor.swift`, `Focus/IdleDetector.swift`, `Focus/UsageAggregator.swift` (pure), `Views/SessionSummaryView.swift`, plus `FocusController` + `MenuBarView`.
- **Permissions:** none.
- **Verified:** switched among apps live and watched the tallies + current-app pin; reviewed the end-of-block summary.

### M3 — Insights dashboard ✅ (shipped)
- **Goal:** a real window aggregating *many* sessions — history, trends, breakdowns.
- **Built:**
  - A **Dashboard window** opened from the popover's footer button.
  - Tiles: today's active time + blocks, current streak, last-14-days total.
  - Trend chart: active minutes/day over the last 14 days (Swift Charts).
  - Top-apps chart, a by-label breakdown, and a recent-blocks list.
- **Key files:**
  - `Window("…", id: DashboardWindow.id)` scene in the app; opened via `openWindow`.
  - `Views/Dashboard/DashboardView.swift` (incl. the `DashboardWindow` activation helper).
  - `Insights/InsightsService.swift` — pure aggregations (today, streak, daily buckets, per-app via `UsageAggregator`, per-label).
- **Apple-specific handling:** an `LSUIElement` agent has no normal windows, so opening the dashboard flips `NSApp.setActivationPolicy(.regular)` + `activate()` and reverts to `.accessory` on close (dropping back to a pure menu-bar app).
- **Migration fix (found while shipping M3):** `FocusSession.activeSeconds` / `awaySeconds` were non-optional with no default, so SwiftData couldn't migrate an existing store and silently fell back to in-memory (no persistence). Fixed with inline defaults (`= 0`) so lightweight migration populates existing rows.
- **Verified:** opened the dashboard against recorded history; confirmed the CoreData migration error is gone and sessions persist across relaunch.

### M4 — Polish (settings, launch-at-login)  ← next
- **Goal:** make it configurable and a good daily citizen.
- **Build:**
  - **Settings** window (`Settings` scene, ⌘,): default block length, idle timeout.
  - **Launch at login** toggle via `SMAppService.mainApp`.
  - Move thresholds out of hardcoded constants into a `SettingsStore`.
  - Menu-bar template icon, empty states, About.
- **Key files:**
  - `Settings/SettingsStore.swift` (`@Observable` over `@AppStorage`).
  - `Views/Settings/SettingsView.swift`.
  - `System/LoginItem.swift` (wraps `SMAppService`).
- **Approach:** feed `SettingsStore` values into `IdleDetector` and the block defaults. `SMAppService.mainApp.register()` / `.unregister()`, reflecting `.status`.
- **Verify:** toggle launch-at-login and confirm it in System Settings → Login Items; change the idle timeout and observe Away attribution change.

### Notes
- **Nudges were removed** by design: the app doesn't judge focus vs. distraction, so real-time "you're distracted" nudges don't fit. If wanted later, they'd be **user-defined** (you pick which apps or time thresholds trigger them), revisited after you've reviewed your own usage data.
- **Testing:** `UsageAggregator` (M2) and `InsightsService` (M3) are pure and kept separate from UI so they stay unit-testable; a formal XCTest target can be added when useful.
- **Settings** are `@AppStorage`-backed for MVP; the "Settings" entity is a `SettingsStore`, not a SwiftData model.

## 11. Open questions / future

- Should very short blocks (< a few min) be discarded from stats?
- Should the per-app **%** be of active time (default) or of the whole block including Away?
- Later: opt-in window-level tracking (adds Accessibility) for finer per-app context (e.g. which site in the browser).
- Later: optional, user-defined nudges once usage patterns are understood.
- Later: a real SwiftData migration plan (versioned schema) before there's data worth preserving.
