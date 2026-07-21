import SwiftUI
import SwiftData

/// Value-based route to the full-history screen. A dedicated route type keeps the
/// dashboard's "See all" push value-based like every other link in the stack;
/// mixing in a destination-closure `NavigationLink { AllSessionsView() }` desyncs
/// the NavigationStack's typed path and can misroute Back into a session detail.
struct AllSessionsRoute: Hashable {}

/// The full, scrollable history of completed focus blocks, paginated so it stays
/// bounded no matter how large the history grows. Tap a row to open its detail;
/// right-click to delete.
struct AllSessionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var limit = 100

    var body: some View {
        PaginatedSessionList(limit: limit, onShowMore: { limit += 100 })
            .navigationTitle("All Sessions")
            // See CLAUDE.md: hide the buggy system back button; drive the pop from
            // our own toolbar button.
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
}

/// The list body, in a child view so its `@Query` (with a growing `fetchLimit`)
/// is rebuilt whenever the page size changes — the dynamic-query pattern.
private struct PaginatedSessionList: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [FocusSession]

    private let limit: Int
    private let onShowMore: () -> Void

    @State private var pendingDelete: FocusSession?

    init(limit: Int, onShowMore: @escaping () -> Void) {
        self.limit = limit
        self.onShowMore = onShowMore
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.end != nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        _sessions = Query(descriptor)
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No focus blocks yet",
                    systemImage: "brain",
                    description: Text("Start a block from the menu bar to see it here.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
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
                    // If we filled the page, there may be more history to load.
                    if sessions.count >= limit {
                        Button("Show more", action: onShowMore)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
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
                Text(TimeFormat.compact(session.activeSeconds)).monospacedDigit()
                if session.awaySeconds >= 1 {
                    Text("away \(TimeFormat.compact(session.awaySeconds))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }
}
