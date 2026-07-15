# DeepFocusTracker — MVP Specification

_Last updated: 2026-07-14 · Status: M1 (menu-bar skeleton) shipped_

## 1. Overview

DeepFocusTracker is a privacy-first macOS menu-bar app that helps you do — and
measure — deep focus work. You start a **focus block** (naming what you're
working on), and the app quietly measures how much of that block was real deep
work vs. drift by watching your active application. It nudges you gently when
you wander, and shows you where your focus actually goes over time.

All data stays local on the Mac. No account, no network, no telemetry.

**Core loop:**

```
Start block (+ label)
   → app auto-measures active-app usage
   → gentle nudge on drift
   → block ends
   → focus score + summary
   → rolls into dashboard stats
```

## 2. Goals & non-goals

**Goals (MVP)**
- Make it effortless to start a focus block and see, afterward, how focused you were.
- Measure focus automatically so it doesn't rely purely on discipline/self-report.
- Surface trends over time (where does my deep work actually go?).
- Frictionless install — works with no scary system permissions.
- Fully local and private.

**Non-goals (MVP)**
- Not a to-do / project manager.
- Not an all-day background surveillance tracker (focus is measured *within blocks*).
- Not a website/app blocker (yet).
- No cloud sync or mobile companion (yet).

## 3. Product decisions (locked)

| Decision | Choice |
|---|---|
| Tracking approach | **Hybrid** — you start a session; app auto-measures app usage during it |
| Intervention on drift | **Gentle nudge** (soft, ignorable notification; rate-limited) |
| Organization | **Lightweight tasks/labels** (name + color per block) |
| Primary interface | **Menu bar + dashboard window** |
| Menu-bar counter | **Live MM:SS** — counts down to a target (**+overtime** past it), counts up when no target is set |
| Tracking granularity | **App-level only** (frontmost application; no window titles → no Accessibility permission) |
| Idle handling | Idle (no input for ~2 min) is **excluded** from the score, not counted against it |
| Breaks / Pomodoro | **Not in v1** — blocks are open-ended or single-target |

## 4. MVP feature set (in scope)

| # | Feature | Detail |
|---|---------|--------|
| 1 | **Menu-bar control** | Start/stop a focus block, with a live counter in the status bar (app icon + time) that **counts down** to a target — showing **+overtime** past it — or **counts up** when no target is set. Optional target duration (e.g. 50 min); live focus status once tracking lands (M2). |
| 2 | **Session labels** | Name each block or pick a reusable label (e.g. *Writing*, *Coding*, *Email*) with a color. |
| 3 | **Automatic focus measurement** | While a block runs, track the frontmost app and split time into **Focus / Neutral / Distraction**. Idle time detected and excluded. |
| 4 | **App categorization** | Sensible defaults (IDE = focus, social = distraction, etc.) + user can recategorize any app. Edits remembered globally. |
| 5 | **Gentle nudge** | If you sit on a Distraction app past a threshold (default 30s), a soft notification reminds you. Rate-limited so it never spams. |
| 6 | **Session summary** | On block end: focus score (% focused), time breakdown, and where the drift went. |
| 7 | **Dashboard window** | History list + daily/weekly totals, focus-score trend, breakdown by label and by app, and a simple daily streak. |
| 8 | **Settings** | Nudge threshold, default block length, category management, launch-at-login. |
| 9 | **Local & private** | No account, no network calls, no telemetry. Data in a local store on the Mac. |

## 5. Out of scope (candidates for v1.1+)

- Active app/website **blocking**
- In-browser **URL/tab tracking**
- Window-**title** tracking (optional opt-in, would add Accessibility permission for sharper scoring on browsers/chat)
- **All-day** automatic tracking (no session needed)
- Projects/goals hierarchy with targets
- Pomodoro **break** scheduling
- macOS **Focus-mode** / **Calendar** integration
- **iCloud sync** / iOS companion
- Data **export**
- AI insights

## 6. Data model (sketch)

- **FocusSession** — `id, label, start, end, targetDuration?, focusedSec, neutralSec, distractedSec, idleSec, focusScore, nudgeCount`
- **AppInterval** — `sessionId, appBundleId, appName, category, start, duration`
- **AppCategoryRule** — `bundleId → focus | neutral | distraction`
- **Label** — `name, color`
- **Settings** — `nudgeThresholdSec, defaultDurationMin, launchAtLogin, idleTimeoutSec`

## 7. Tracking & scoring behavior

- **Active-app detection** is event-driven via `NSWorkspace` activation notifications
  (record an `AppInterval` each time the frontmost app changes). No polling, no permission.
- Each interval is classified **Focus / Neutral / Distraction** via `AppCategoryRule`.
- **Idle detection** via input-event idle time; after `idleTimeoutSec` (~2 min) of no
  input, tracking pauses and that time is bucketed as idle (excluded from the score).
- **Focus score** = `focusedSec / (focusedSec + distractedSec)` — neutral and idle excluded.
- Handle **sleep/wake** and **screen lock** as idle boundaries.

## 8. Nudge behavior

- Trigger: frontmost app is a **Distraction** continuously for > `nudgeThresholdSec` (default 30s).
- Delivery: soft `UserNotifications` banner ("Still on task? You're in <App>").
- **Rate-limited**: at most one nudge per app per cooldown window to avoid spam.

## 9. Permissions

| Capability | Permission needed |
|---|---|
| Frontmost-app tracking | **None** (`NSWorkspace`) |
| Idle detection | **None** (input-event idle time) |
| Nudges | **Notifications** (prompted on first block) |
| Launch at login | **None** (`SMAppService`) |

_MVP intentionally requires no Accessibility or Screen Recording permission._

## 10. Tech stack (recommended)

- **Swift + SwiftUI**, targeting current macOS (deployment target macOS 15.0).
- Menu bar: `MenuBarExtra` (window style for the popover).
- Charts: **Swift Charts**.
- Persistence: **SwiftData** (local store).
- Active-app events: `NSWorkspace.didActivateApplicationNotification`.
- Notifications: `UserNotifications`. Launch-at-login: `SMAppService`.

## 11. Build milestones

1. **M1 — Skeleton ✅ (shipped):** menu-bar agent app + start/stop block + labels + live menu-bar counter (countdown / count-up / overtime) + SwiftData models. Builds & launches.
2. **M2 — Measurement:** active-app tracking + categorization + session summary.
3. **M3 — Nudges:** drift detection + rate-limited notifications.
4. **M4 — Insights:** dashboard window + charts (trend, by-label, by-app, streak).
5. **M5 — Polish:** settings + launch-at-login + category management + defaults.

## 12. Open questions / future

- Default category list — which apps ship as focus/neutral/distraction out of the box?
- Should very short blocks (< a few min) be discarded from stats?
- v1.1: opt-in window-level tracking toggle (adds Accessibility) for sharper browser/chat scoring.
