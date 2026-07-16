import SwiftUI

/// Value-based route to the "How it works" guide. A dedicated route type keeps
/// this push value-based like every other link in the dashboard stack — see the
/// NavigationStack note in `DashboardView` / CLAUDE.md.
struct GuideRoute: Hashable {}

/// A static, scrollable explainer: how tracking works, what each number on the
/// summary / dashboard means and how it's calculated, and the privacy stance.
/// Reached from the dashboard's "?" toolbar button or the popover footer link.
/// Judgment-free like the rest of the app — it explains the measurements, it
/// doesn't tell you which apps are "good."
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                howItWorks
                theNumbers
                privacy
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("How it works")
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

    // MARK: Sections

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works").font(.title2).bold()
            Text("""
            Start a focus block from the menu bar and name what you're working on. \
            While it runs, DeepFocusTracker quietly notes which app is in front and \
            for how long. End the block to see where your time actually went.
            """)
            Text("""
            It records; you interpret. There are no “focus” or “distraction” labels — \
            just the numbers. Tracking is app-level only (which app is frontmost), \
            never window titles or content, so it needs no special permissions.
            """)
            .foregroundStyle(.secondary)
        }
    }

    private var theNumbers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The numbers").font(.title3).bold()

            term("Focus block", icon: "brain.head.profile",
                 "A stretch of focused work you start and end yourself, with a name and an optional target length.")
            term("Active", icon: "clock",
                 "Time spent working in apps during the block — the sum of how long each app was in front.")
            term("Away", icon: "moon.zzz",
                 "Idle or stepped-away time. It starts after about 2 minutes with no keyboard or mouse input (and when the screen locks or the Mac sleeps), and isn't charged to any app.")
            term("Switches", icon: "arrow.left.arrow.right",
                 "How many times you changed the frontmost app during the block — a plain, judgment-free measure of how fragmented it was. (Switches while you're Away aren't counted.)")
            term("Per-app %", icon: "percent",
                 "Each app's share of your Active time; Away time is left out. So the percentages split the time you were working, not the whole block.")
            term("Target", icon: "target",
                 "An optional goal length for a block. The menu-bar timer counts down to it and then shows “+” overtime; with no target it simply counts up.")
            term("Streak", icon: "flame",
                 "The number of days in a row you've completed at least one block, counting back from today (or yesterday if today is still empty).")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private by design").font(.title3).bold()
            Text("""
            Everything stays on this Mac. No account, no network, no analytics — \
            your focus history never leaves your computer.
            """)
            .foregroundStyle(.secondary)
        }
    }

    /// One glossary entry: a symbol, the term, and a plain-language explanation
    /// (including how it's calculated).
    private func term(_ name: String, icon: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
