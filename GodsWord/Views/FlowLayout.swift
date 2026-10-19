// FlowLayout.swift
// A left-to-right, top-to-bottom flow layout for the reader: words (and
// Strong's numbers) are placed inline and wrap like a paragraph, while each
// stays an individually tappable view (verse selection, dictionary lookup).

import SwiftUI

struct FlowLayout: Layout {
    var wordSpacing: CGFloat = 2
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0, !subviews.isEmpty else { return .zero }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            x += size.width + wordSpacing
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            // Top-align: shorter items (Strong's numbers, verse digits)
            // sit high like superscripts.
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + wordSpacing
        }
    }
}
