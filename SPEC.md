# DeepFocusTracker — MVP Specification

_Last updated: 2026-07-14 · Status: M1 shipped; M2 (app-usage tracking) in progress_

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
| 3 | **Automatic app-usage tracking** | While a block runs, record time spent in each frontmost app and the **% of the block** it took, plus idle **"Away"** time. No focus/distraction judgment — just the numbers. |
| 4 | **Session summary** | On block end: per-app **time + %**, active vs. away time, and an **app-switch count**. You review and interpret it. |
| 5 | **Dashboard window** | History list + daily/weekly totals, focused-time trend, per-app and per-label breakdowns, and a simple daily streak. |
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

## 9. Tech stack (recommended)

- **Swift + SwiftUI**, targeting current macOS (deployment target macOS 15.0).
- Menu bar: `MenuBarExtra` (window style for the popover).
- Charts: **Swift Charts** (dashboard).
- Persistence: **SwiftData** (local store).
- Active-app events: `NSWorkspace.didActivateApplicationNotification`.
- Idle: `CGEventSource`. Launch-at-login: `SMAppService`.

## 10. Build milestones & implementation plan

Roadmap (details below). Every milestone ships something you can *see* working — see each **Verify** line.

| Milestone | Status | In one line |
|---|---|---|
| M1 — Skeleton | ✅ shipped | Menu-bar app, start/stop blocks, labels, live counter, SwiftData |
| M2 — Usage tracking | ← in progress | Per-app time + % during a block + session summary |
| M3 — Insights | planned | Dashboard window: history, trends, breakdowns, streak |
| M4 — Polish | planned | Settings, launch-at-login |

### M1 — Skeleton ✅ (shipped)
- **Built:** menu-bar-only agent (`MenuBarExtra`, `LSUIElement`, `.accessory`); SwiftData models + `FocusController` (start/stop, recover open block, seed labels, 1 s tick); popover UI + status-item label with the live counter; `TimeFormat`.
- **Verify:** builds via `xcodebuild`; launches as a menu-bar agent; start/stop a block and watch the counter.

### M2 — Automatic app-usage tracking  ← in progress
- **Goal:** while a block runs, record how long you spend in each app and what % of the block that was — **no focus/distraction judgment**. You review the breakdown.
- **Build:**
  - Active-app tracking → one `AppInterval` per frontmost-app span (bundle id, name, start, duration).
  - Idle/Away detection → time with no input becomes its own **"Away"** line, so stepping away isn't blamed on whatever app was open.
  - Live popover: current app + running per-app tallies.
  - End-of-block **summary**: per-app **time + %** (of active time), total active vs. away, and an **app-switch count**.
- **Key files:**
  - `Focus/ActivityMonitor.swift` — subscribes to `NSWorkspace.didActivateApplicationNotification`; opens/closes app spans; treats sleep/wake + screen lock as boundaries.
  - `Focus/IdleDetector.swift` — `CGEventSource.secondsSinceLastEventType(...)` polled on a timer; routes idle time to Away.
  - `Focus/UsageAggregator.swift` — pure `[AppInterval] (+ away) → per-app totals + %, active/away totals, switch count`.
  - `Views/SessionSummaryView.swift`; updates to `FocusController` + `MenuBarView`.
- **Data-model changes (from M1):** drop `FocusCategory` + `AppCategoryRule` (no categorization); `AppInterval` drops `category`; `FocusSession` drops the focused/neutral/distracted/score/nudge fields and gains `activeSeconds` + `awaySeconds`.
- **Permissions:** none.
- **Verify:** watch the popover per-app tallies grow as you switch apps; read the end-of-block breakdown; `UsageAggregator` is a pure function (unit-testable); optional `os_log` on each switch.

### M3 — Insights dashboard
- **Goal:** a real window aggregating *many* sessions — history, trends, breakdowns.
- **Build:**
  - A **Dashboard window** opened from the popover ("Open Dashboard…").
  - Header: today's focused (active) time, # blocks, current streak.
  - Trend chart (active minutes / day, last 7/30 days) — Swift Charts.
  - Breakdown by app and by label (bar charts).
  - Session history list (date, label, duration, active vs. away).
- **Key files:**
  - A `Window("Dashboard", id: "dashboard")` scene; open via `openWindow(id:)`.
  - `Views/Dashboard/…` (DashboardView, TrendChart, BreakdownChart, SessionHistoryList, StreakView).
  - `Insights/InsightsService.swift` — pure aggregations (daily/weekly rollups, per-app, per-label, streak).
- **Apple-specific gotcha:** an `LSUIElement` agent has no normal windows — opening one needs `NSApp.setActivationPolicy(.regular)` + `NSApp.activate(...)` while the window is open (revert to `.accessory` on close), so the dashboard can take focus and appear in the app switcher.
- **Verify:** run a few blocks (or seed sample data under `#if DEBUG`), open the dashboard, confirm the numbers match; unit-test the aggregation + streak functions.

### M4 — Polish (settings, launch-at-login)
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
