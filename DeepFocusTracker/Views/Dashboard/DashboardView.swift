import SwiftUI
import SwiftData
import Charts
import AppKit
import Observation

/// Opening a window from an `LSUIElement` agent needs the app to briefly become
/// a regular (Dock) app so the window can take focus; we revert on close.
enum DashboardWindow {
    static let id = "dashboard"

    static func show(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: id)
    }

    static func didClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Cross-scene navigation signal. The menu-bar popover and the dashboard live in
/// separate scenes, and a `Window` can't receive a value through `openWindow`, so
/// the popover states *where* the dashboard should be, and the dashboard consumes
/// it — on appear (opened from closed) or on change (already on screen).
@Observable
final class DashboardNavigator {
    /// Where the dashboard should land when it next opens or comes forward. A
    /// one-shot request: "Dashboard" asks for `.root`, "How to use" for `.guide`.
    /// Consuming it resets the stack, so a window closed mid-guide never reopens
    /// onto that stale, un-popped page.
    enum Destination { case root, guide }
    var pending: Destination?
}

/// Aggregated view of your focus history across sessions.
struct DashboardView: View {
    @Query(sort: \DayRollup.day) private var dayRollups: [DayRollup]
    @Query private var appRollups: [DayAppRollup]
    /// Windowed completed sessions — only needed for the by-label rollup.
    @Query private var windowSessions: [FocusSession]
    /// The latest handful of completed blocks for the "Recent" list.
    @Query private var recentSessions: [FocusSession]

    @Environment(DashboardNavigator.self) private var navigator
    /// Explicit stack path so the guide can be pushed programmatically (toolbar
    /// button or a deep-link from the popover), alongside the value-based links.
    @State private var path = NavigationPath()

    init(now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        _windowSessions = Query(
            filter: #Predicate<FocusSession> { $0.end != nil && $0.start >= windowStart },
            sort: \.start, order: .reverse
        )
        var recent = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.end != nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        recent.fetchLimit = 15
        _recentSessions = Query(recent)
    }

    var body: some View {
        let insights = computeInsights()
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    tiles(insights)
                    trendSection(insights)
                    if !insights.byApp.isEmpty { topAppsSection(insights) }
                    if !insights.byLabel.isEmpty { byLabelSection(insights) }
                    recentSection()
                }
                .padding(20)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        path.append(GuideRoute())
                    } label: {
                        Label("How it works", systemImage: "questionmark.circle")
                    }
                    .help("How it works")
                }
            }
            // Keep every push in this stack value-based (typed routes). Do NOT mix
            // in destination-closure links (`NavigationLink { SomeView() }`) —
            // mixing the two styles desyncs the stack and intermittently misroutes
            // Back (e.g. popping "All Sessions" jumps into a session detail).
            .navigationDestination(for: FocusSession.self) { session in
                SessionDetailView(session: session)
            }
            .navigationDestination(for: AllSessionsRoute.self) { _ in
                AllSessionsView()
            }
            .navigationDestination(for: GuideRoute.self) { _ in
                GuideView()
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        // Apply the popover's request when we first appear (opened from closed) or
        // when it changes while we're already on screen (brought forward). This
        // makes every open deterministic instead of reopening onto a stale stack.
        .onAppear { applyPendingDestination() }
        .onChange(of: navigator.pending) { _, pending in
            if pending != nil { applyPendingDestination() }
        }
        .onDisappear {
            // Don't reopen onto a page left mid-stack when the window was closed
            // without navigating back.
            path = NavigationPath()
            DashboardWindow.didClose()
        }
    }

    /// Consume a one-shot navigation request from the popover, resetting the stack
    /// so we always land exactly where asked (root or guide), never on leftovers.
    private func applyPendingDestination() {
        guard let destination = navigator.pending else { return }
        navigator.pending = nil
        path = NavigationPath()
        if destination == .guide {
            path.append(GuideRoute())
        }
    }

    // MARK: Data

    private func computeInsights() -> Insights {
        let days = dayRollups.map {
            DayStat(day: $0.day, activeSeconds: $0.activeSeconds, awaySeconds: $0.awaySeconds, blockCount: $0.blockCount)
        }
        let appDays = appRollups.map {
            AppDayStat(day: $0.day, bundleID: $0.bundleID, appName: $0.appName, seconds: $0.seconds)
        }
        let sessions = windowSessions.compactMap { session -> SessionRecord? in
            guard let end = session.end else { return nil }
            return SessionRecord(
                start: session.start,
                end: end,
                label: session.label,
                activeSeconds: session.activeSeconds,
                awaySeconds: session.awaySeconds
            )
        }
        return InsightsService.compute(days: days, appDays: appDays, sessions: sessions)
    }

    // MARK: Sections

    @ViewBuilder
    private func tiles(_ insights: Insights) -> some View {
        HStack(spacing: 14) {
            tile("Today", TimeFormat.compact(insights.todayActive), blocksCaption(insights.todayBlocks))
            tile("Streak", "\(insights.streakDays)", insights.streakDays == 1 ? "day" : "days")
            tile("Last 14 days", TimeFormat.compact(insights.windowActive), blocksCaption(insights.windowBlocks))
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func trendSection(_ insights: Insights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active time — last 14 days").font(.headline)
            if insights.windowActive == 0 {
                emptyHint("No focus blocks in the last 14 days.")
            } else {
                Chart(insights.daily) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.seconds / 60)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartYAxisLabel("min")
                .frame(height: 170)
            }
        }
    }

    @ViewBuilder
    private func topAppsSection(_ insights: Insights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top apps — last 14 days").font(.headline)
            Chart(insights.byApp) { app in
                BarMark(
                    x: .value("Focus time", app.seconds),
                    y: .value("App", app.appName)
                )
                .foregroundStyle(Color.accentColor)
            }
            // Self-labeling duration ticks (5m, 1h, …) instead of raw minutes like
            // "0.02" — the unit rides on each tick, so no single fixed axis unit.
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(TimeFormat.compact(seconds))
                        }
                    }
                }
            }
            .chartXAxisLabel("focus time")
            .frame(height: CGFloat(insights.byApp.count) * 30 + 24)
        }
    }

    @ViewBuilder
    private func byLabelSection(_ insights: Insights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By label — last 14 days").font(.headline)
            ForEach(insights.byLabel) { label in
                HStack {
                    Text(label.label).lineLimit(1)
                    Spacer()
                    Text(blocksCaption(label.blocks)).font(.caption).foregroundStyle(.secondary)
                    Text(TimeFormat.compact(label.seconds)).monospacedDigit().frame(width: 72, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func recentSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent blocks").font(.headline)
                Spacer()
                if !recentSessions.isEmpty {
                    NavigationLink("See all", value: AllSessionsRoute())
                }
            }
            if recentSessions.isEmpty {
                emptyHint("No completed blocks yet. Start one from the menu bar.")
            } else {
                ForEach(recentSessions) { session in
                    NavigationLink(value: session) { recentRow(session) }
                        .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private func recentRow(_ session: FocusSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.label).lineLimit(1)
                Text(session.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(TimeFormat.compact(session.activeSeconds)).monospacedDigit()
                if session.awaySeconds >= 1 {
                    Text("away \(TimeFormat.compact(session.awaySeconds))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.callout)
        .contentShape(Rectangle())
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func blocksCaption(_ count: Int) -> String {
        "\(count) block\(count == 1 ? "" : "s")"
    }
}
