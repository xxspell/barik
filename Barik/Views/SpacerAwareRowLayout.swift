import SwiftUI

/// Tags a subview inside `SpacerAwareRowLayout` as a `spacer` pseudo-widget
/// slot, set at the call site from `item.id == "spacer"` — not inferred by
/// measuring the subview's rendered content, so it works identically whether
/// a spacer renders as the real flexible `Spacer()` (normal mode) or a small
/// fixed-size placeholder icon (live-edit mode).
struct RowSpacerFlag: LayoutValueKey {
    static let defaultValue: Bool = false
}

/// Lays out a row of widgets exactly like `HStack(spacing:)`, except every
/// subview tagged `RowSpacerFlag` gets its width computed by a formula
/// instead of SwiftUI's default "split leftover space equally among
/// flexible children" — see
/// `docs/superpowers/specs/2026-08-08-multi-spacer-even-distribution-design.md`
/// for the full derivation. With `N` spacers, they divide the row into
/// `N + 1` segments (`seg₀` before the first spacer, `segₙ` after the
/// last); the two edge segments stay pinned to the row's edges, and the
/// `N - 1` floating segments in between land with their centers on `k/N`
/// fractions of the row's total width.
struct SpacerAwareRowLayout: Layout {
    let spacing: CGFloat

    private let minGap: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalWidths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let spacerCount = subviews.filter { $0[RowSpacerFlag.self] }.count

        if let proposedWidth = proposal.width {
            return CGSize(width: proposedWidth, height: height)
        }

        // No explicit proposal (rare — this row is normally wrapped in
        // `.frame(maxWidth: .infinity)`): report an ideal size using each
        // spacer's minimum width rather than the old `Spacer()` default.
        let nonSpacerWidth = zip(subviews, naturalWidths)
            .filter { !$0.0[RowSpacerFlag.self] }
            .reduce(0) { $0 + $1.1 }
        let idealWidth = nonSpacerWidth
            + minGap * CGFloat(spacerCount)
            + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: idealWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let spacerIndices = subviews.indices.filter { subviews[$0][RowSpacerFlag.self] }
        let n = spacerIndices.count

        guard n > 0 else {
            placeLeftToRight(subviews: subviews, in: bounds)
            return
        }

        let naturalWidths = subviews.map { $0.sizeThatFits(.unspecified).width }

        // Segment i (i = 0...n) is the run of non-spacer subviews strictly
        // between spacerIndices[i-1] and spacerIndices[i] (segment 0 is
        // before the first spacer, segment n is after the last).
        var segmentWidths: [CGFloat] = []
        var previousBoundary = -1
        for spacerIndex in spacerIndices {
            segmentWidths.append(segmentWidth(naturalWidths, (previousBoundary + 1)..<spacerIndex))
            previousBoundary = spacerIndex
        }
        segmentWidths.append(segmentWidth(naturalWidths, (previousBoundary + 1)..<subviews.count))

        func halfWidth(_ segmentIndex: Int) -> CGFloat {
            let width = segmentWidths[segmentIndex]
            return (segmentIndex == 0 || segmentIndex == n) ? width : width / 2
        }

        let target = bounds.width / CGFloat(n)
        var gapWidths: [CGFloat] = []
        for (k, spacerIndex) in spacerIndices.enumerated() {
            let hasLeadingNeighbor = spacerIndex > 0
            let hasTrailingNeighbor = spacerIndex < subviews.count - 1
            let adjacentSpacingCount = (hasLeadingNeighbor ? 1 : 0) + (hasTrailingNeighbor ? 1 : 0)
            let raw = target - halfWidth(k) - halfWidth(k + 1) - CGFloat(adjacentSpacingCount) * spacing
            gapWidths.append(max(raw, minGap))
        }

        var x = bounds.minX
        var spacerCursor = 0
        for (offset, subview) in subviews.enumerated() {
            let width: CGFloat
            if subview[RowSpacerFlag.self] {
                width = gapWidths[spacerCursor]
                spacerCursor += 1
            } else {
                width = naturalWidths[offset]
            }
            let height = subview.sizeThatFits(.unspecified).height
            subview.place(
                at: CGPoint(x: x + width / 2, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: width, height: height)
            )
            x += width + spacing
        }
    }

    private func segmentWidth(_ naturalWidths: [CGFloat], _ range: Range<Int>) -> CGFloat {
        guard !range.isEmpty else { return 0 }
        let sum = range.reduce(CGFloat(0)) { $0 + naturalWidths[$1] }
        return sum + spacing * CGFloat(range.count - 1)
    }

    /// Defensive fallback if this layout is ever used on a row with no
    /// spacer at all — packs subviews left to right like a plain `HStack`.
    /// Should not normally be reached: callers only use this layout when a
    /// row is known to contain at least one spacer.
    private func placeLeftToRight(subviews: Subviews, in bounds: CGRect) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: x + size.width / 2, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
        }
    }
}
