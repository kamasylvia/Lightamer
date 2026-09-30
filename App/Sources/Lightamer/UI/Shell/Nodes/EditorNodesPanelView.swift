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

    /// The canvas coordinate space name (drag + preference readbacks anchor
    /// here — ONE space shared by every geometry consumer).
    static let canvasSpace = "nodes.canvas"

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

    private func chainView(_ document: PipelineDocument, container: CGSize) -> some View {
        let layout = NodeCanvasGeometry.layout(
            for: document.nodes, width: container.width)
        return ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                edgesCanvas(layout)
                cardsLayer(document, layout: layout)
            }
            .frame(width: container.width, height: layout.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The card layer — real views at the layout's resolved positions.
    private func cardsLayer(
        _ document: PipelineDocument, layout: NodeCanvasGeometry.Layout
    ) -> some View {
        ForEach(document.nodes) { node in
            card(for: node)
                .frame(
                    width: NodeCanvasGeometry.cardWidth,
                    height: layout.frames[node.id]?.height ?? 0)
                .position(layout.center(of: node.id))
        }
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

    /// The DRT endpoint: the grayed fixed placeholder (D-M2-4-CONTEXT-7).
    private func drtCard(_ node: PipelineDocument.Node) -> some View {
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
