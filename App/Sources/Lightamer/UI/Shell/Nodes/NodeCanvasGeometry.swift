import CoreGraphics
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// NodeCanvasGeometry (Plan M2-4-3 T1, KD-1) — the pure-function geometry
// source of the node panel's vertical single-column chain:
//
//   Develop (endpoint)
//        │
//   Color Grade × N (cards)     ← centered column, fixed spacing
//        │
//   Display Transform (endpoint)
//
// ZERO UI DEPENDENCIES — CoreGraphics values only. The file lives in the App
// target because it serves the App panel, but it must stay constructible and
// testable without any view (the NodeCanvasGeometryTests machine check).
// The view layer derives EVERY position from here (cards, edges, the
// insertion indicator); no hand-rolled coordinates exist outside this file
// (KD-1: the geometry source of truth is a pure function).
// ─────────────────────────────────────────────────────────────────────────────

enum NodeCanvasGeometry {

    /// The read-only Film projection card's fixed identity (M3-3-03 T4,
    /// KD-4 — the PipelineDocument.displayTransformNodeID pattern: a
    /// compile-time App-side constant, NEVER a PipelineDocument NodeKind).
    /// The hex spells "F1LM0000-0000-0000-0000-000000000003".
    static let filmCardID = UUID(
        uuid: (0xF1, 0x4C, 0x4D, 0x30, 0x00, 0x00, 0x00, 0x00,
               0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03))

    // MARK: Layout constants (KD-1 — the single tuning table)

    /// The node card width (fits the 248pt expanded rail minus insets).
    static let cardWidth: CGFloat = 196
    /// The grade card height (name + enabled dot + mix slider).
    static let cardHeight: CGFloat = 64
    /// The develop/drt endpoint card height (shorter than a grade card).
    static let endpointHeight: CGFloat = 44
    /// The vertical gap between adjacent cards.
    static let verticalSpacing: CGFloat = 18
    /// The column's top inset inside the scroll container.
    static let topInset: CGFloat = 16
    /// The column's bottom inset inside the scroll container.
    static let bottomInset: CGFloat = 16

    // MARK: Layout

    /// One resolved layout (value type; equality = identical frames).
    struct Layout: Equatable {

        /// Card frames keyed by node id (canvas coordinates, y downward).
        let frames: [UUID: CGRect]

        /// The top-to-bottom node id order (the document's `nodes` order).
        let order: [UUID]

        /// The grade-segment ids only (the insertion domain — endpoints
        /// never receive a drop; the index space is `0...grades.count`).
        let grades: [UUID]

        /// The total column height (last frame's maxY + the bottom inset).
        let height: CGFloat

        /// The frame center (the edge endpoint anchor — edges connect card
        /// CENTERS, KD-1). Unknown id → `.zero` (never in practice: every
        /// id comes from the same document pass that built the layout).
        /// (`CGRect.center` is package-protected in this SDK — midX/midY.)
        func center(of id: UUID) -> CGPoint {
            guard let frame = frames[id] else { return .zero }
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        /// One connector segment: `start` = the upper card's center,
        /// `end` = the lower card's center; `nodeID` = the LOWER node the
        /// edge feeds (the segment is identified by its consumer).
        struct Edge: Equatable {
            let nodeID: UUID
            let start: CGPoint
            let end: CGPoint
        }

        /// The chain's connector segments — exactly `order.count - 1` of
        /// them (a linear chain), zero for empty/single-node layouts.
        func edges() -> [Edge] {
            guard order.count > 1 else { return [] }
            return zip(order, order.dropFirst()).map { upper, lower in
                Edge(nodeID: lower, start: center(of: upper), end: center(of: lower))
            }
        }
    }

    /// The card height for a node kind (endpoints are shorter). Exhaustive
    /// switch — no `default` arm (the checker discipline).
    static func cardHeight(for kind: PipelineDocument.NodeKind) -> CGFloat {
        switch kind {
        case .develop, .displayTransform: endpointHeight
        case .grade: cardHeight
        }
    }

    /// Resolve the vertical single-column layout for the document's nodes
    /// inside a `width`-wide canvas: top to bottom in the given order,
    /// horizontally centered, `verticalSpacing` between cards, insets
    /// around the column. An EMPTY node list → an empty layout of height 0.
    ///
    /// M3-3-03 T4 (KD-4): `includesFilmCard` reserves one endpoint-height
    /// slot for the read-only Film projection card BETWEEN the grades and
    /// the Display Transform endpoint (the film sub-run's physical seat:
    /// after the main chain's top plane, before the display tail). The card
    /// is NOT a PipelineDocument NodeKind (M2-4 zero-diff red line) — it is
    /// an App-side projection keyed by `filmCardID`, carried through the
    /// layout so the geometry source of truth owns every coordinate (the
    /// KD-1 discipline). Default false = the pre-T4 layout byte-for-byte.
    static func layout(
        for nodes: [PipelineDocument.Node], width: CGFloat,
        includesFilmCard: Bool = false
    ) -> Layout {
        var frames: [UUID: CGRect] = [:]
        var order: [UUID] = []
        var grades: [UUID] = []
        var y = topInset
        let filmSlotAfter = includesFilmCard
            ? nodes.last(where: { $0.kind == .displayTransform })?.id
            : nil
        for node in nodes {
            if node.id == filmSlotAfter {
                frames[filmCardID] = CGRect(
                    x: (width - cardWidth) / 2, y: y, width: cardWidth,
                    height: endpointHeight)
                order.append(filmCardID)
                y += endpointHeight + verticalSpacing
            }
            let h = cardHeight(for: node.kind)
            frames[node.id] = CGRect(
                x: (width - cardWidth) / 2, y: y, width: cardWidth, height: h)
            order.append(node.id)
            if node.kind == .grade { grades.append(node.id) }
            y += h + verticalSpacing
        }
        if includesFilmCard && filmSlotAfter == nil && !nodes.isEmpty {
            // No display-transform endpoint (never in practice — the chain
            // always ends with it): the film card trails the chain.
            frames[filmCardID] = CGRect(
                x: (width - cardWidth) / 2, y: y, width: cardWidth,
                height: endpointHeight)
            order.append(filmCardID)
            y += endpointHeight + verticalSpacing
        }
        let height = order.isEmpty ? 0 : y - verticalSpacing + bottomInset
        return Layout(frames: frames, order: order, grades: grades, height: height)
    }

    // MARK: The drop domain (the drag-reconnect pure function, KD-1)

    /// The drop index for a drag point at `dragY` (canvas Y): a GRADE-space    /// index `0...grades.count` (endpoints excluded from the TARGET space —
    /// the command face's reconnect position). The boundaries are the
    /// midpoints between adjacent GRADE cards PLUS the midpoint between the
    /// last grade and the DRT endpoint (so the zone below the last grade
    /// resolves to `grades.count`); a drag ON a card resolves to that
    /// card's own index (its own slot = the no-op position). An empty chain
    /// has nowhere to insert (always 0); out-of-range positions clamp (the
    /// plan's 钳制 clause).
    static func insertionIndex(dragY: CGFloat, in layout: Layout) -> Int {
        let centers = layout.grades.map { layout.center(of: $0).y }
        guard let first = centers.first else { return 0 }
        var boundaries: [CGFloat] =
            zip(centers, centers.dropFirst()).map { ($0 + $1) / 2 }
        // The bottom boundary: the midpoint of the last grade → the DRT
        // card (a linear chain always ends with that endpoint frame; the
        // fallback bounds the last zone at the last card's bottom edge).
        let lastCenter = centers.last ?? first
        if let drtCenter = layout.order.last.flatMap({ layout.frames[$0] })?.midY {
            boundaries.append((lastCenter + drtCenter) / 2)
        } else {
            boundaries.append(lastCenter + cardHeight / 2)
        }
        var index = 0
        for boundary in boundaries where dragY > boundary {
            index += 1
        }
        return index
    }

    /// The Y of the insertion indicator line for a drop index
    /// (`0...grades.count`): above the first grade, between the straddled
    /// pair, or below the last — nil when there are no grades (nothing to
    /// insert into, the indicator stays hidden).
    static func insertionLineY(index: Int, in layout: Layout) -> CGFloat? {
        let grades = layout.grades
        guard let firstID = grades.first,
            let firstFrame = layout.frames[firstID]
        else { return nil }
        guard index > 0 else { return firstFrame.minY - verticalSpacing / 2 }
        guard index < grades.count,
            let upper = layout.frames[grades[index - 1]],
            let lower = layout.frames[grades[index]]
        else {
            guard let lastID = grades.last,
                let lastFrame = layout.frames[lastID]
            else { return nil }
            return lastFrame.maxY + verticalSpacing / 2
        }
        return (upper.midY + lower.midY) / 2
    }

    // MARK: Fit (KD-1 — constant auto-fit, free zoom is a Deferred idea)

    /// The fit scale = min(1, container/content): content that fits renders
    /// at scale 1 (no scroll needed); taller content scales DOWN to fit. A
    /// zero/negative container never divides (returns 1 — the AC boundary).
    static func fitScale(contentHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0, contentHeight > containerHeight else { return 1 }
        return containerHeight / contentHeight
    }
}
