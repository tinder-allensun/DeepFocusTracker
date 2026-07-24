import SwiftUI
import SwiftData

/// Value-based route to the daily-review screen. A dedicated route type keeps the
/// dashboard's Today-tile push value-based like every other link in the stack;
/// mixing in a destination-closure `NavigationLink { TodayReviewView() }` desyncs
/// the NavigationStack's typed path and can misroute Back (see `AllSessionsRoute`).
struct TodayRoute: Hashable {}

/// A judgment-free recap of the current day: how many focus blocks, what each was
/// (chronological), and where the time went across them. Reached by tapping the
/// dashboard's "Today" tile. Records, doesn't judge — it shows the numbers and
/// lets you interpret them; tap any block for its full per-app detail.
///
/// The day boundary is captured when the screen opens (`now`), so a dashboard left
/// open across midnight keeps showing that day until it's reopened — a known,
/// accepted limitation that mirrors the rest of the dashboard.
struct TodayReviewView: View {
    @Environment(\.dismiss) private var dismiss

    /// Today's completed blocks, earliest first — drives the list + navigation, and
    /// (summed) the header. Filtered by `start` to match how `Rollups` buckets a
    /// block into a day, so the totals agree with the dashboard's "Today" tile.
    @Query private var sessions: [FocusSession]
    /// Today's per-app rollup rows (one per app) — the per-app breakdown, read from
    /// the denormalized rollup rather than scanning the `AppInterval` table.
    @Query private var appRollups: [DayAppRollup]

    private let now: Date
    private let calendar: Calendar

    init(now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let startOfToday = calendar.startOfDay(for: now)
        _sessions = Query(
            filter: #Predicate<FocusSession> { $0.end != nil && $0.start >= startOfToday },
            sort: \.start, order: .forward
        )
        _appRollups = Query(
            filter: #Predicate<DayAppRollup> { $0.day == startOfToday }
        )
    }

    var body: some View {
        let review = dayReview()
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(review)
                blocksSection(review)
                if !review.byApp.isEmpty { perAppSection(review) }
            }
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 420)
        .navigationTitle("Today")
        // See AllSessionsView: the system back button is buggy in this Window's
        // NavigationStack; hide it and drive the pop from our own toolbar button.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .help("Back to dashboard")
            }
        }
    }

    // MARK: Data

    /// Join the queried rows into value form and aggregate via the pure service.
    private func dayReview() -> DayReview {
        let records = sessions.compactMap { session -> SessionRecord? in
            guard let end = session.end else { return nil }
            return SessionRecord(
                start: session.start,
                end: end,
                label: session.label,
                activeSeconds: session.activeSeconds,
                awaySeconds: session.awaySeconds,
                switchCount: session.switchCount
            )
        }
        let appDays = appRollups.map {
            AppDayStat(day: $0.day, bundleID: $0.bundleID, appName: $0.appName, seconds: $0.seconds)
        }
        return InsightsService.dayReview(sessions: records, appDays: appDays, now: now, calendar: calendar)
    }

    // MARK: Sections

    private func header(_ review: DayReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(now.formatted(date: .complete, time: .omitted))
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                stat("Active", TimeFormat.compact(review.activeSeconds))
                Spacer()
                stat("Away", TimeFormat.compact(review.awaySeconds))
                Spacer()
                stat("Blocks", "\(review.blockCount)")
                Spacer()
                stat("Switches", "\(review.switchCount)")
            }
        }
    }

    @ViewBuilder
    private func blocksSection(_ review: DayReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your focus blocks today").font(.headline)
            if sessions.isEmpty {
                emptyHint("No focus blocks today yet. Start one from the menu bar.")
            } else {
                // A divider sits between every consecutive block for a steady
                // rhythm; where there's ≥ 1 min of off-focus time the gap connector
                // sits in that space, bracketed by dividers. Gaps are keyed by the
                // chronological index of the block before them (from dayReview,
                // whose ordering matches this @Query's `start` sort).
                let gapsByPreceding = Dictionary(
                    uniqueKeysWithValues: review.gaps.map { ($0.precedingIndex, $0) }
                )
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(value: session) { blockRow(session) }
                        .buttonStyle(.plain)
                    if index < sessions.count - 1 {
                        Divider()
                        if let gap = gapsByPreceding[index] {
                            gapRow(gap)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    /// The off-focus stretch between two blocks — a muted, non-interactive timeline
    /// connector, so it's instantly distinguishable from the (tappable) block rows.
    /// Neutral wording: the app recorded nothing here, so it makes no claim that you
    /// were idle.
    private func gapRow(_ gap: FocusGap) -> some View {
        HStack(spacing: 10) {
            // A short vertical tick reading as the connective "space between".
            RoundedRectangle(cornerRadius: 1)
                .fill(.tertiary)
                .frame(width: 2, height: 16)
            Text("off focus · \(TimeFormat.compact(gap.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Off focus for \(TimeFormat.compact(gap.duration))")
    }

    private func blockRow(_ session: FocusSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.label).lineLimit(1)
                Text(timeRange(session))
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

    @ViewBuilder
    private func perAppSection(_ review: DayReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where the time went today").font(.headline)
            ForEach(review.byApp) { app in
                HStack(spacing: 8) {
                    Text(app.appName).lineLimit(1)
                    Spacer()
                    Text("\(percent(app, of: review.activeSeconds))%")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Text(TimeFormat.compact(app.seconds))
                        .monospacedDigit().frame(width: 62, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }

    // MARK: Helpers

    /// Start–end clock range for a completed block (times only; the screen is
    /// already scoped to one day).
    private func timeRange(_ session: FocusSession) -> String {
        let startTime = session.start.formatted(date: .omitted, time: .shortened)
        guard let end = session.end else { return startTime }
        let endTime = end.formatted(date: .omitted, time: .shortened)
        return "\(startTime) – \(endTime)"
    }

    /// Per-app share of *active* (non-away) time, matching the session-detail and
    /// summary convention. Guards against divide-by-zero.
    private func percent(_ app: AppUsage, of active: TimeInterval) -> Int {
        guard active > 0 else { return 0 }
        return Int((app.seconds / active * 100).rounded())
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}
