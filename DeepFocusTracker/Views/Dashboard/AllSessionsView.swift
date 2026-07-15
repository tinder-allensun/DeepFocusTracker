import SwiftUI
import SwiftData

/// Value-based route to the full-history screen. A dedicated route type keeps the
/// dashboard's "See all" push value-based like every other link in the stack;
/// mixing in a destination-closure `NavigationLink { AllSessionsView() }` desyncs
/// the NavigationStack's typed path and can misroute Back into a session detail.
struct AllSessionsRoute: Hashable {}

/// The full, scrollable history of completed focus blocks. Tap a row to open its
/// detail; right-click to delete. Pushed from the dashboard's "See all".
struct AllSessionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FocusSession.start, order: .reverse) private var sessions: [FocusSession]

    @State private var pendingDelete: FocusSession?

    private var completed: [FocusSession] { sessions.filter { $0.end != nil } }

    var body: some View {
        Group {
            if completed.isEmpty {
                ContentUnavailableView(
                    "No focus blocks yet",
                    systemImage: "brain",
                    description: Text("Start a block from the menu bar to see it here.")
                )
            } else {
                List {
                    ForEach(completed) { session in
                        NavigationLink(value: session) {
                            row(session)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Sessions")
        // The system-injected NavigationStack back button overlaps the title and
        // won't take clicks in this LSUIElement dashboard Window; hide it and
        // drive the pop from our own toolbar button below.
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
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { session in
            Button("Delete", role: .destructive) {
                SessionHistory.delete(session, in: context)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { session in
            Text("This permanently removes “\(session.label)” and its recorded detail. This can't be undone.")
        }
    }

    private func row(_ session: FocusSession) -> some View {
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
    }
}
