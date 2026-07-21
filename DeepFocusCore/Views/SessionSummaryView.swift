import SwiftUI

/// Shown when a block ends: the per-app time + % breakdown for the user to
/// review and interpret. No judgment — just where the time went.
struct SessionSummaryView: View {
    let session: FocusSession
    let summary: UsageSummary
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Block complete — \(session.label)")
                .font(.headline)
                .lineLimit(1)

            HStack(alignment: .top) {
                stat("Active", TimeFormat.compact(summary.activeSeconds))
                Spacer()
                stat("Away", TimeFormat.compact(summary.awaySeconds))
                Spacer()
                stat("Switches", "\(summary.switchCount)")
            }

            Divider()

            if summary.perApp.isEmpty {
                Text("No app activity recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Where the time went")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(summary.perApp.prefix(6))) { app in
                    HStack(spacing: 8) {
                        Text(app.appName).lineLimit(1)
                        Spacer()
                        Text("\(percent(app))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(TimeFormat.compact(app.seconds))
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }

            Button(action: onDone) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 2)
        }
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
