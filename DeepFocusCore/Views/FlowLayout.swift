import SwiftUI

/// A simple wrapping layout: lays subviews left-to-right and wraps to the next row
/// when the next one would overflow the proposed width. Used for the menu-bar label
/// chips so they wrap instead of clipping off the popover's edge (a horizontal
/// `ScrollView` didn't scroll with a plain mouse wheel and left the trailing chip
/// half-cut). Leading-aligned; rows are as tall as their tallest subview.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let contentWidth = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        // Occupy the full proposed width when we have a finite one, so `placeSubviews`
        // wraps against the same width and the reported height stays consistent; fall
        // back to the natural content width when unconstrained.
        let width = (proposal.width?.isFinite == true) ? proposal.width! : contentWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    // MARK: - Row packing

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Greedily pack subviews into rows, wrapping when the next subview would exceed
    /// `maxWidth` (but always keeping at least one subview per row).
    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row(items: [index], width: size.width, height: size.height)
            } else {
                current.items.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
