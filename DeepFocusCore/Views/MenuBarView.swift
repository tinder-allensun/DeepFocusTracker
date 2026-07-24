import SwiftUI
import SwiftData
import AppKit

/// The menu-bar popover: start a block when idle, watch the live timer and
/// per-app tallies while running, or review the summary when a block ends.
public struct MenuBarView: View {
    public init() {}

    @Environment(FocusController.self) private var focus
    @Environment(DashboardNavigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow
    // Ordering (most-recently-used first, capped) is applied by `LabelChooser`, so
    // just fetch the catalog here.
    @Query private var labels: [SessionLabel]

    @State private var labelText: String = ""
    @State private var targetMinutes: Int = 50
    @State private var useTarget: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if let session = focus.activeSession {
                runningView(session)
            } else if let summary = focus.lastSummary, let finished = focus.lastFinishedSession {
                SessionSummaryView(session: finished, summary: summary, onDone: { focus.dismissSummary() })
            } else {
                idleView
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
            Text("DeepFocusTracker").font(.headline)
            Spacer()
            Button {
                // Open the dashboard straight to the guide.
                navigator.pending = .guide
                DashboardWindow.show(openWindow)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("How to use")
        }
    }

    // MARK: Idle state

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What are you focusing on?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("e.g. Writing the spec", text: $labelText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(startBlock)

            let chips = LabelChooser.chips(from: labels)
            if !chips.isEmpty {
                // Wrap chips onto multiple rows rather than a horizontal scroll: a
                // macOS horizontal ScrollView won't scroll with a plain mouse wheel
                // and left the trailing chip clipped at the popover edge. Capped at 5
                // chips, so this is at most a couple of short rows.
                FlowLayout(spacing: 6) {
                    ForEach(chips) { label in
                        Button(label.name) { labelText = label.name }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .contextMenu {
                                // Right-click to drop the suggestion; recorded
                                // sessions keep their (string-copied) label.
                                Button("Delete “\(label.name)”", role: .destructive) {
                                    focus.deleteLabel(label)
                                }
                            }
                    }
                }
            }

            Toggle("Set a target", isOn: $useTarget)
                .toggleStyle(.checkbox)
            if useTarget {
                Stepper("\(targetMinutes) min target", value: $targetMinutes, in: 5...240, step: 5)
                    .controlSize(.small)
            }

            Button(action: startBlock) {
                Label("Start Focus Block", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: Running state

    private func runningView(_ session: FocusSession) -> some View {
        let now = focus.tick            // reading tick refreshes this view each second
        let usage = focus.liveUsage
        let elapsed = session.elapsed(asOf: now)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(session.label).font(.title3).bold().lineLimit(1)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(TimeFormat.clock(elapsed))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let target = session.targetDuration {
                    ProgressView(value: min(elapsed, target), total: target)
                    Text("of \(TimeFormat.clock(target)) target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let current = focus.currentAppName {
                Text("now: \(current)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !usage.perApp.isEmpty {
                Divider()
                liveUsageList(usage)
            }

            Button(role: .destructive) {
                focus.stop()
            } label: {
                Label("End Block", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func liveUsageList(_ usage: UsageSummary) -> some View {
        let top = Array(usage.perApp.prefix(4))
        let currentID = focus.currentBundleID
        // If the app you're currently in didn't make the top-4, pin it below so
        // the list never disagrees with the "now:" line.
        let pinnedCurrent: AppUsage? = {
            guard let currentID, !top.contains(where: { $0.bundleID == currentID }) else { return nil }
            return usage.perApp.first { $0.bundleID == currentID }
        }()

        VStack(alignment: .leading, spacing: 3) {
            ForEach(top) { app in
                usageRow(app, usage: usage, isCurrent: app.bundleID == currentID)
            }
            if let pinnedCurrent {
                usageRow(pinnedCurrent, usage: usage, isCurrent: true)
            }
            if usage.awaySeconds >= 1 {
                awayRow(usage.awaySeconds)
            }
        }
    }

    private func usageRow(_ app: AppUsage, usage: UsageSummary, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            // A fixed-width dot slot keeps every row aligned; only the current
            // app's dot is visible.
            Circle()
                .fill(isCurrent ? Color.green : Color.clear)
                .frame(width: 5, height: 5)
            Text(app.appName)
                .lineLimit(1)
                .fontWeight(isCurrent ? .semibold : .regular)
            Spacer()
            Text("\(Int((usage.fraction(of: app) * 100).rounded()))%")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(TimeFormat.clock(app.seconds))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
        .font(.caption)
    }

    private func awayRow(_ seconds: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.clear).frame(width: 5, height: 5)
            Text("Away").foregroundStyle(.secondary)
            Spacer()
            Text(TimeFormat.clock(seconds))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var footer: some View {
        HStack {
            Button {
                // Open the dashboard at its root (not wherever the stack was
                // last left).
                navigator.pending = .root
                DashboardWindow.show(openWindow)
            } label: {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    // MARK: Actions

    private func startBlock() {
        let target = useTarget ? TimeInterval(targetMinutes * 60) : nil
        focus.start(label: labelText, targetDuration: target)
        labelText = ""
    }
}
