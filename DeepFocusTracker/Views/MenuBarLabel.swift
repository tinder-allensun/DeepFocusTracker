import SwiftUI

/// The status-bar item itself. Shows just the icon when idle, and the icon
/// plus the live counter (`menuBarTitle`) while a block is running. Reading
/// `focus.menuBarTitle` establishes an observation dependency on the
/// controller's per-second `tick`, so this re-renders every second.
struct MenuBarLabel: View {
    var focus: FocusController

    var body: some View {
        if let title = focus.menuBarTitle {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                Text(title)
            }
        } else {
            Image(systemName: "brain.head.profile")
        }
    }
}
