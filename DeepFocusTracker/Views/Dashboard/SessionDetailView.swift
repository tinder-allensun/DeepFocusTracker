import SwiftUI
import SwiftData

/// The full recorded detail for one completed focus block: where the time went
/// (per-app time + %), plus active / away / switches. Records, doesn't judge —
/// it shows the numbers and lets you interpret them, and lets you delete the
/// block if you don't want to keep it.
struct SessionDetailView: View {
    let session: FocusSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Just this session's spans (joined in memory into a `UsageSummary`).
    @Query private var intervals: [AppInterval]

    @State private var confirmingDelete = false

    init(session: FocusSession) {
        self.session = session
        let id = session.id
        _intervals = Query(
            filter: #Predicate<AppInterval> { $0.sessionID == id },
            sort: \.start
        )
    }

    /// Rebuild the per-app breakdown from the stored intervals, feeding the
    /// active/away/switch totals cached on the session at stop.
    private var summary: UsageSummary {
        let spans = intervals.map {
            AppSpan(bundleID: $0.appBundleID, appName: $0.appName, start: $0.start, duration: $0.duration)
        }
        return UsageAggregator.summarize(
            spans: spans,
            awaySeconds: session.awaySeconds,
            switchCount: session.switchCount
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsRow
                Divider()
                perAppSection
                Spacer(minLength: 8)
                deleteButton
            }
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 420)
        .navigationTitle(session.label)
        // See AllSessionsView: the buggy system back button is hidden here too;
        // the toolbar button below drives the pop reliably.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .help("Back")
            }
        }
        .confirmationDialog(
            "Delete this block?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                // Dismiss first so the view isn't rendering a deleted object.
                dismiss()
                SessionHistory.delete(session, in: context)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes “\(session.label)” and its recorded detail. This can't be undone.")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.label).font(.title2).bold().lineLimit(2)
            Text(dateRangeText).font(.callout).foregroundStyle(.secondary)
            if let target = session.targetDuration {
                Text("Target \(TimeFormat.clock(target))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top) {
            stat("Active", TimeFormat.clock(summary.activeSeconds))
            Spacer()
            stat("Away", TimeFormat.clock(summary.awaySeconds))
            Spacer()
            stat("Switches", "\(summary.switchCount)")
        }
    }

    @ViewBuilder
    private var perAppSection: some View {
        if summary.perApp.isEmpty {
            Text("No app activity recorded.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where the time went")
                    .font(.headline)
                ForEach(summary.perApp) { app in
                    HStack(spacing: 8) {
                        Text(app.appName).lineLimit(1)
                        Spacer()
                        Text("\(percent(app))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(TimeFormat.clock(app.seconds))
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete this block", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: Helpers

    private var dateRangeText: String {
        let day = session.start.formatted(date: .abbreviated, time: .omitted)
        let startTime = session.start.formatted(date: .omitted, time: .shortened)
        guard let end = session.end else {
            return "\(day) · started \(startTime)"
        }
        let endTime = end.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(startTime) – \(endTime) · \(TimeFormat.clock(session.elapsed()))"
    }

    private func percent(_ app: AppUsage) -> Int {
        Int((summary.fraction(of: app) * 100).rounded())
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
