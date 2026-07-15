import SwiftUI
import SwiftData
import Charts
import AppKit

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

/// Aggregated view of your focus history across sessions.
struct DashboardView: View {
    @Query(sort: \FocusSession.start, order: .reverse) private var sessions: [FocusSession]
    @Query private var intervals: [AppInterval]

    private var completed: [FocusSession] { sessions.filter { $0.end != nil } }

    var body: some View {
        let insights = computeInsights()
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
        .frame(minWidth: 620, minHeight: 520)
        .onDisappear { DashboardWindow.didClose() }
    }

    // MARK: Data

    private func computeInsights() -> Insights {
        let records = completed.compactMap { session -> SessionRecord? in
            guard let end = session.end else { return nil }
            return SessionRecord(
                start: session.start,
                end: end,
                label: session.label,
                activeSeconds: session.activeSeconds,
                awaySeconds: session.awaySeconds
            )
        }
        let spans = intervals.map {
            AppSpan(bundleID: $0.appBundleID, appName: $0.appName, start: $0.start, duration: $0.duration)
        }
        return InsightsService.compute(sessions: records, appSpans: spans)
    }

    // MARK: Sections

    @ViewBuilder
    private func tiles(_ insights: Insights) -> some View {
        HStack(spacing: 14) {
            tile("Today", TimeFormat.clock(insights.todayActive), blocksCaption(insights.todayBlocks))
            tile("Streak", "\(insights.streakDays)", insights.streakDays == 1 ? "day" : "days")
            tile("Last 14 days", TimeFormat.clock(insights.windowActive), blocksCaption(insights.windowBlocks))
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
                    x: .value("Minutes", app.seconds / 60),
                    y: .value("App", app.appName)
                )
                .foregroundStyle(Color.accentColor)
            }
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
                    Text(TimeFormat.clock(label.seconds)).monospacedDigit().frame(width: 72, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func recentSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent blocks").font(.headline)
            if completed.isEmpty {
                emptyHint("No completed blocks yet. Start one from the menu bar.")
            } else {
                ForEach(Array(completed.prefix(15))) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.label).lineLimit(1)
                            Text(session.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(TimeFormat.clock(session.activeSeconds)).monospacedDigit()
                            if session.awaySeconds >= 1 {
                                Text("away \(TimeFormat.clock(session.awaySeconds))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout)
                    Divider()
                }
            }
        }
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
