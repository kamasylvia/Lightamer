import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorNodesPanelView (Plan M2-4-3 T1, KD-1/KD-3) — the Nodes rail panel:
// the linear chain "Develop → Grade×N → Display Transform" as a ZStack of
//
//   1. a Canvas EDGE layer (center-to-center connectors — the Canvas draws
//      lines ONLY and never participates in hit testing, `.allowsHitTesting
//      (false)`), and
//   2. a CARD layer of REAL SwiftUI views positioned via `.position` —
//      buttons/menus/gestures are native hit tests, ZERO hand-rolled
//      hit-testing (the KD-1 answer).
//
// Every coordinate comes from `NodeCanvasGeometry` (the pure-function source
// of truth); this file hand-rolls none. T1 mounts the skeleton (canvas +
// three card kinds + click-select); the interactions land in T3 (KD-3's
// menu/drag/lock/mix face).
// ─────────────────────────────────────────────────────────────────────────────

struct EditorNodesPanelView: View {

    @State private var model: NodesPanelModel
    @State private var containerSize: CGSize = .zero

    /// The active drag's drop index (nil = no drag → the indicator hides).
    /// T2 mounts the RENDER SITE; the T3 gesture is the only writer.
    @State private var dropIndex: Int?

    /// The Fit button's re-assert counter (the scroll-to-top trigger).
    @State private var fitToken = 0

    /// The canvas coordinate space name (drag + preference readbacks anchor
    /// here — ONE space shared by every geometry consumer).
    static let canvasSpace = "nodes.canvas"

    /// The scroll-to-top anchor id (the Fit button's target).
    private static let topAnchorID = "nodes.top"

    /// The panel's own subtle animation (the Fit scroll re-assert).
    private static let collapseAnimation: Animation = .easeInOut(duration: 0.15)

    init(editorState: EditorState, editingState: LayerEditingState) {
        _model = State(
            initialValue: NodesPanelModel(
                editorState: editorState, editingState: editingState))
    }

    var body: some View {
        GeometryReader { geo in
            content(container: geo.size)
                .onAppear { containerSize = geo.size }
                .onChange(of: geo.size) { _, newSize in containerSize = newSize }
        }
        .onChange(of: model.document?.nodes.map(\.id)) { model.pruneSelection() }
        .accessibilityIdentifier("editor.nodes.panel")
    }

    // MARK: - Content

    @ViewBuilder
    private func content(container: CGSize) -> some View {
        if let document = model.document {
            chainView(document, container: container)
        } else {
            // The rail panel is only reachable with an image open; the nil
            // face is a transient (image closing) — an honest empty group.
            Color.clear
        }
    }

    /// The chain face (Plan M2-4-3 T2, KD-1 Fit): constant auto-fit — the
    /// content scales DOWN when it outgrows the container (`fitScale <
    /// 1`, no scrolling needed), renders at scale 1 otherwise. Free
    /// pan/zoom is a Deferred idea; the Fit button re-asserts the fit
    /// (scroll back to the chain head) — the v1 honest semantic.
    private func chainView(_ document: PipelineDocument, container: CGSize) -> some View {
        let layout = NodeCanvasGeometry.layout(
            for: document.nodes, width: container.width)
        let scale = NodeCanvasGeometry.fitScale(
            contentHeight: layout.height, containerHeight: container.height)
        return VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        edgesCanvas(layout)
                        cardsLayer(document, layout: layout)
                        insertionIndicator(layout)
                        Color.clear
                            .frame(height: 0)
                            .id(Self.topAnchorID)
                    }
                    .frame(width: container.width, height: layout.height)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: container.width, height: layout.height * scale)
                }
                .onAppear { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
                .onChange(of: fitToken) {
                    withAnimation(Self.collapseAnimation) {
                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The drop-indicator render site (the T3 drag gesture's visual echo —
    /// a line at the resolved index's Y; hidden outside a drag). Lines are
    /// never hit-testable (the KD-1 Canvas discipline extends here).
    @ViewBuilder
    private func insertionIndicator(_ layout: NodeCanvasGeometry.Layout) -> some View {
        if let dropIndex,
            let y = NodeCanvasGeometry.insertionLineY(index: dropIndex, in: layout)
        {
            RoundedRectangle(cornerRadius: 1)
                .fill(ThemeTokens.accent)
                .frame(width: NodeCanvasGeometry.cardWidth + 16, height: 2)
                .position(x: layout.frames.values.first?.midX ?? 0, y: y)
                .allowsHitTesting(false)
        }
    }

    /// The panel header row (the Fit affordance; the「+」add button is the
    /// T3 interaction face).
    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                fitToken += 1
            } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("editor.nodes.fit")
            .accessibilityLabel(Text(String(localized: "editor_nodes_fit", defaultValue: "Fit")))
            .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
    }

    /// The connector layer — lines ONLY, never hit-testable (KD-1).
    private func edgesCanvas(_ layout: NodeCanvasGeometry.Layout) -> some View {
        Canvas { context, _ in
            for edge in layout.edges() {
                var path = Path()
                path.move(to: edge.start)
                path.addLine(to: edge.end)
                context.stroke(
                    path, with: .color(ThemeTokens.cardBorder),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    /// The card layer — real views at the layout's resolved positions. The
    /// named canvas space + the per-card frame preference live here (the
    /// T2 machine check reads rendered geometry back through the REAL
    /// layout system — recorded as the AC3 机检方式 in DECISIONS).
    private func cardsLayer(
        _ document: PipelineDocument, layout: NodeCanvasGeometry.Layout
    ) -> some View {
        ForEach(document.nodes) { node in
            card(for: node)
                .frame(
                    width: NodeCanvasGeometry.cardWidth,
                    height: layout.frames[node.id]?.height ?? 0)
                .background(
                    // BEFORE .position: the reader measures the card's own
                    // rect; resolving it in the canvas space folds the
                    // position transform in (the standard readback shape).
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: NodeCardFramesKey.self,
                            value: [node.id: proxy.frame(in: .named(Self.canvasSpace))]
                        )
                    }
                )
                .position(layout.center(of: node.id))
        }
        .coordinateSpace(name: Self.canvasSpace)
    }

    // MARK: - Cards (the KD-3 information face)

    @ViewBuilder
    private func card(for node: PipelineDocument.Node) -> some View {
        let selected = model.selectedNodeID == node.id
        Group {
            switch node.kind {
            case .develop: developCard(node)
            case .grade: gradeCard(node)
            case .displayTransform: drtCard(node)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeTokens.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            selected ? ThemeTokens.accent : ThemeTokens.cardBorder,
                            lineWidth: selected ? 1.5 : 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { model.select(node.id) }
        .accessibilityIdentifier(Self.cardMarker(for: node))
    }

    /// The Develop endpoint: name + RAW badge + lock mark (D-M2-4-CONTEXT-7).
    private func developCard(_ node: PipelineDocument.Node) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(String(localized: "editor_node_develop", defaultValue: "Develop"))
                .font(.callout.weight(.medium))
                .foregroundStyle(ThemeTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "RAW")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ThemeTokens.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(
                    Capsule().strokeBorder(ThemeTokens.cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 10)
    }

    /// The grade card: name + enabled dot + mix % (the slider/menu/drag
    /// face lands in T3).
    private func gradeCard(_ node: PipelineDocument.Node) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(node.isEnabled ? ThemeTokens.accent : ThemeTokens.textSecondary)
                .frame(width: 7, height: 7)
            Text(node.name)
                .font(.callout)
                .foregroundStyle(ThemeTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(Int((Double(node.mix) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .padding(.horizontal, 10)
    }

    /// The DRT endpoint: the grayed fixed placeholder (D-M2-4-CONTEXT-7) —
    /// title + the "DRT arrives with M2-6" copy (plan T2's key).
    private func drtCard(_ node: PipelineDocument.Node) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text(String(localized: "editor_node_drt", defaultValue: "Display Transform"))
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(String(
                    localized: "editor_node_drt_placeholder",
                    defaultValue: "DRT arrives with M2-6"))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Markers (L010: stable AX ids)

    /// The card's AX marker — an exhaustive switch, no `default` arm.
    static func cardMarker(for node: PipelineDocument.Node) -> String {
        switch node.kind {
        case .develop: "editor.nodes.develop"
        case .grade: "editor.nodes.grade.\(node.id.uuidString)"
        case .displayTransform: "editor.nodes.drt"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The rendered-geometry readback face (Plan M2-4-3 T2, AC3 机检) — each card
// reports its frame in the canvas space through a preference; the
// NodeCanvasGeometryTests host the panel in an NSHostingView and assert the
// READ-BACK frames equal `NodeCanvasGeometry.layout` (the render frame =
// the pure-function layout, measured through the REAL SwiftUI layout
// system — not a mirror of the source). Production cost ≈ 0 (a preference
// nobody observes is never reduced); future overlay features may consume
// the same face.
// ─────────────────────────────────────────────────────────────────────────────

struct NodeCardFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(
        value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
