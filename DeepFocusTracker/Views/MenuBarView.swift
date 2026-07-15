import SwiftUI
import SwiftData
import AppKit

/// The menu-bar popover: start a block when idle, or watch the live timer and
/// end it while a block is running.
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
            } else {
                idleView
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(session.label).font(.title3).bold()
                Spacer()
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = session.elapsed(asOf: context.date)
                VStack(alignment: .leading, spacing: 4) {
                    Text(TimeFormat.clock(elapsed))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let target = session.targetDuration {
                        ProgressView(value: min(elapsed, target), total: target)
                        Text("of \(TimeFormat.clock(target)) target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
