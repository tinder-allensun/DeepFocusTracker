import SwiftUI
import SwiftData
import AppKit

/// The menu-bar popover: start a block when idle, watch the live timer and
/// per-app tallies while running, or review the summary when a block ends.
struct MenuBarView: View {
    @Environment(FocusController.self) private var focus
    @Query(sort: \SessionLabel.createdAt) private var labels: [SessionLabel]

    @State private var labelText: String = ""
    @State private var targetMinutes: Int = 50
    @State private var useTarget: Bool = false

    var body: some View {
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

            if !labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(labels) { label in
                            Button(label.name) { labelText = label.name }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
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
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(usage.perApp.prefix(4))) { app in
                HStack(spacing: 8) {
                    Text(app.appName).lineLimit(1)
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
            if usage.awaySeconds >= 1 {
                HStack(spacing: 8) {
                    Text("Away").foregroundStyle(.secondary)
                    Spacer()
                    Text(TimeFormat.clock(usage.awaySeconds))
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private var footer: some View {
        HStack {
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
