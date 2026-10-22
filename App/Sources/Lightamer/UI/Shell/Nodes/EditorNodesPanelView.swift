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

    /// The read-only Film card's tap → the Film page (M3-3-03 T3/T4: the
    /// card is navigation, never an edit — the locked-endpoint selection
    /// semantics' sibling). OPTIONAL + injected (not @Environment): the
    /// NodeCanvasGeometryTests host this panel bare — a missing injection
    /// degrades the tap to a no-op, it must never crash the host.
    private weak var inspectorState: InspectorState?

    /// M7-5-01 face ④: the turn-taking gate source — OPTIONAL + injected
    /// (the same bare-host discipline as inspectorState above; the rail
    /// passes the environment-resolved coordinator).
    private weak var agentControl: AgentControlCoordinator?

    /// The active drag's drop index (nil = no drag → the indicator hides).
    @State private var dropIndex: Int?

    /// The card currently under a drag gesture (the scroll-lock arm — the
    /// ScrollView disables itself while a card drag is live, KD-1's
    /// double guard with the 6pt threshold).
    @State private var draggingNodeID: UUID?

    /// The rename alert's target + draft (nil = the alert is closed).
    @State private var renameTargetID: UUID?
    @State private var renameDraft: String = ""

    /// The live mix draft per card (the slider's drag buffer — the commit
    /// leg reads THIS, never a captured node snapshot, so a fast drag
    /// commits the exact final value).
    @State private var liveMixes: [UUID: Float] = [:]

    /// The Fit button's re-assert counter (the scroll-to-top trigger).
    @State private var fitToken = 0

    /// The canvas coordinate space name (drag + preference readbacks anchor
    /// here — ONE space shared by every geometry consumer).
    static let canvasSpace = "nodes.canvas"

    /// The scroll-to-top anchor id (the Fit button's target).
    private static let topAnchorID = "nodes.top"

    /// The panel's own subtle animation (the Fit scroll re-assert).
    private static let collapseAnimation: Animation = .easeInOut(duration: 0.15)

    init(
        editorState: EditorState, editingState: LayerEditingState,
        pipeCoordinator: PipeCoordinator? = nil,
        inspectorState: InspectorState? = nil,
        agentControl: AgentControlCoordinator? = nil
    ) {
        _model = State(
            initialValue: NodesPanelModel(
                editorState: editorState, editingState: editingState,
                pipeCoordinator: pipeCoordinator))
        self.inspectorState = inspectorState
        self.agentControl = agentControl
    }

    var body: some View {
        GeometryReader { geo in
            content(container: geo.size)
                .onAppear { containerSize = geo.size }
                .onChange(of: geo.size) { _, newSize in containerSize = newSize }
        }
        // M7-5-01 (D-M7-5-4 face ④): the node canvas + mask editing surface
        // go inert while the agent holds the control. OPTIONAL injection
        // (the inspectorState precedent — the bare test host degrades the
        // gate to open, never crashes it).
        .disabled(agentControl?.holdsControl ?? false)
        .onChange(of: model.document?.nodes.map(\.id)) { model.pruneSelection() }
        .alert(
            String(localized: "nodes_rename_title", defaultValue: "Rename Color Grade"),
            isPresented: renameAlertBinding
        ) {
            TextField(
                String(localized: "nodes_rename_field", defaultValue: "Name"),
                text: $renameDraft)
            Button(String(localized: "nodes_rename_ok", defaultValue: "Rename")) {
                if let id = renameTargetID, !renameDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty
                {
                    model.apply(.renameGrade(id: id, to: renameDraft))
                }
                renameTargetID = nil
            }
            Button(
                role: .cancel,
                action: { renameTargetID = nil }
            ) {
                Text(String(localized: "nodes_rename_cancel", defaultValue: "Cancel"))
            }
        }
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
            for: document.nodes, width: container.width,
            includesFilmCard: model.filmCard != nil)
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
                // KD-1's scroll-lock arm: while a card drag is live the
                // ScrollView yields (the 6pt threshold is the other guard).
                .scrollDisabled(draggingNodeID != nil)
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

    /// The panel header row: the「+」add-grade affordance (the stack-top
    /// AddClean — plan T3) and the Fit button (T2).
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                model.apply(.addCleanGrade(before: nil))
            } label: {
                Image(systemName: "plus")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("editor.nodes.add")
            .accessibilityLabel(Text(
                String(localized: "editor_nodes_add_grade", defaultValue: "Add Color Grade")))

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
        ZStack {
            ForEach(document.nodes) { node in
                card(for: node)
                    .frame(
                        width: NodeCanvasGeometry.cardWidth,
                        height: layout.frames[node.id]?.height ?? 0)
                    .background {
                        // BEFORE .position: the reader measures the card's own
                        // rect; resolving it in the canvas space folds the
                        // position transform in (the standard readback shape).
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: NodeCardFramesKey.self,
                                value: [node.id: proxy.frame(in: .named(Self.canvasSpace))]
                            )
                        }
                    }
                    .position(layout.center(of: node.id))
            }
            // M3-3-03 T4 (KD-4): the read-only Film projection card — a
            // real view at the layout's reserved slot (NOT a
            // PipelineDocument node; the geometry owns its frame via
            // NodeCanvasGeometry.filmCardID).
            if let filmCard = model.filmCard,
                let frame = layout.frames[NodeCanvasGeometry.filmCardID]
            {
                filmCardView(filmCard)
                    .frame(width: NodeCanvasGeometry.cardWidth, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .coordinateSpace(.named(Self.canvasSpace))
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
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeTokens.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            selected ? ThemeTokens.accent : ThemeTokens.cardBorder,
                            lineWidth: selected ? 1.5 : 1)
                }
        }
        // The lock trio FIRST (badge + content interception + hint); the
        // selection/navigation face attaches OUTSIDE it — selecting a
        // locked endpoint is navigation, not an edit (D-M2-4-CONTEXT-7:
        // develop 点选 = the global chain).
        .nodeLocked(node.isDeletionLocked, hint: { model.lockHint(node.id) })
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { model.select(node.id) }
        .contextMenu { menu(for: node) }
        .gesture(dragGesture(for: node))
        .accessibilityIdentifier(Self.cardMarker(for: node))
    }

    // MARK: - The KD-3 interaction face (T3)

    /// One card's context-menu action (the KD-3 table's command face — a
    /// value so the ACTION SET is machine-checkable).
    enum NodeCardAction: Equatable, CaseIterable {
        case rename
        case toggleEnabled
        case delete
        case insertGradeBefore
    }

    /// The action set per card kind — the KD-3 table verbatim: grades
    /// carry all four; the LOCKED ENDPOINTS carry NONE (no Delete, nothing
    /// to rename/toggle/insert into). Exhaustive switch, no `default` arm.
    static func availableActions(for node: PipelineDocument.Node) -> [NodeCardAction] {
        switch node.kind {
        case .develop, .displayTransform: []
        case .grade: NodeCardAction.allCases
        }
    }

    @ViewBuilder
    private func menu(for node: PipelineDocument.Node) -> some View {
        ForEach(Self.availableActions(for: node), id: \.self) { action in
            menuButton(action, for: node)
        }
    }

    @ViewBuilder
    private func menuButton(
        _ action: NodeCardAction, for node: PipelineDocument.Node
    ) -> some View {
        switch action {
        case .rename:
            Button(String(localized: "nodes_menu_rename", defaultValue: "Rename…")) {
                renameDraft = node.name
                renameTargetID = node.id
            }
        case .toggleEnabled:
            Button(
                node.isEnabled
                    ? String(localized: "nodes_menu_disable", defaultValue: "Disable")
                    : String(localized: "nodes_menu_enable", defaultValue: "Enable")
            ) {
                model.apply(.setGradeEnabled(id: node.id, enabled: !node.isEnabled))
            }
        case .delete:
            Button(
                role: .destructive,
                action: { model.apply(.removeGradeAndBridge(id: node.id)) }
            ) {
                Text(String(localized: "nodes_menu_delete", defaultValue: "Delete"))
            }
        case .insertGradeBefore:
            Button(String(
                    localized: "nodes_menu_insert_before",
                    defaultValue: "Insert Grade Before")) {
                model.apply(.addCleanGrade(before: node.id))
            }
        }
    }

    /// The drag-reconnect gesture (KD-1): 6pt threshold起步 (the scroll
    /// coexistence guard; the ScrollView's scrollDisabled is the other),
    /// the drop Y resolves through the PURE insertionIndex, the indicator
    /// echoes it live, and the release routes `reconnectGrade` — UNLESS
    /// the drop hit the card's own slot (the no-op position) or the card
    /// is locked (the view-level refusal; the shell's silent interception
    /// is the backstop).
    private func dragGesture(for node: PipelineDocument.Node) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                guard node.kind == .grade, !model.isLocked(node.id) else { return }
                draggingNodeID = node.id
                dropIndex = NodeCanvasGeometry.insertionIndex(
                    dragY: value.location.y,
                    in: currentLayout())
            }
            .onEnded { value in
                defer {
                    draggingNodeID = nil
                    dropIndex = nil
                }
                guard node.kind == .grade, !model.isLocked(node.id) else { return }
                let index = NodeCanvasGeometry.insertionIndex(
                    dragY: value.location.y, in: currentLayout())
                let currentSlot = model.document?.grades.firstIndex {
                    $0.id == node.id
                } ?? -1
                if index != currentSlot {
                    model.apply(.reconnectGrade(id: node.id, toPosition: index))
                }
            }
    }

    /// The layout the gesture closures resolve against (re-derived per
    /// event — pure and tens-of-nodes cheap; the container size state is
    /// kept current by the body's GeometryReader).
    private func currentLayout() -> NodeCanvasGeometry.Layout {
        NodeCanvasGeometry.layout(
            for: model.document?.nodes ?? [], width: containerSize.width)
    }

    /// The rename alert (the KD-3 Rename row): a text-field alert routed
    /// through `renameGrade`; an empty (whitespace-only) draft is a no-op.
    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTargetID != nil },
            set: { if !$0 { renameTargetID = nil } })
    }

    /// The Develop endpoint: name + RAW badge (the lock affordance rides
    /// the `.nodeLocked` trio, not the card content).
    private func developCard(_ node: PipelineDocument.Node) -> some View {
        HStack(spacing: 6) {
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
                .overlay {
                    Capsule().strokeBorder(ThemeTokens.cardBorder, lineWidth: 1)
                }
        }
        .padding(.horizontal, 10)
    }

    /// The grade card: name + enabled dot + mix % + the mix SLIDER (the
    /// KD-2 live/commit legs — drag = `setMixLive` zero history, release =
    /// `commitMix` EXACTLY one history item with the command face's key).
    private func gradeCard(_ node: PipelineDocument.Node) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            Slider(
                value: Binding(
                    get: { Double(liveMixes[node.id] ?? node.mix) },
                    set: { newValue in
                        liveMixes[node.id] = Float(newValue)
                        model.setMixLive(Float(newValue), nodeID: node.id)
                    }),
                in: 0...1
            ) { editing in
                if !editing {
                    if let value = liveMixes[node.id] {
                        model.commitMix(value, nodeID: node.id)
                    }
                    liveMixes[node.id] = nil
                }
            }
            .controlSize(.mini)
            .accessibilityLabel(Text(
                String(localized: "nodes_mix_label", defaultValue: "Mix")))
        }
        .padding(.horizontal, 10)
    }

    /// The DRT endpoint: the grayed fixed placeholder (D-M2-4-CONTEXT-7) —
    /// title + the "DRT arrives with M2-6" copy (plan T2's key).
    private func drtCard(_ node: PipelineDocument.Node) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
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

    /// The read-only Film card (M3-3-03 T4, KD-4): the material pair's
    /// names + the active state. NO edit face, NO commands, NO history —
    /// the tap opens the Film page (navigation, never an edit).
    private func filmCardView(_ card: NodesPanelModel.FilmCardProjection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(
                        card.isActive
                            ? ThemeTokens.accent : ThemeTokens.textSecondary)
                    .frame(width: 7, height: 7)
                Text(String(
                        localized: "editor_node_film",
                        defaultValue: "Film Simulation"))
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(card.isActive
                ? "\(card.filmName) · \(card.paperName)"
                : String(
                    localized: "editor_node_film_inactive",
                    defaultValue: "Inactive"))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeTokens.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            card.isActive ? ThemeTokens.accent : ThemeTokens.cardBorder,
                            lineWidth: card.isActive ? 1.5 : 1)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { inspectorState?.openFilmPage() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.filmCardMarker)
        .accessibilityLabel(Text(String(
            localized: "editor_node_film", defaultValue: "Film Simulation")))
        .accessibilityHint(Text(String(
            localized: "editor_node_film_hint",
            defaultValue: "Opens the film simulation panel")))
    }

    /// The Film card's AX marker (L010: a stable id).
    static let filmCardMarker = "editor.nodes.film"

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

// ─────────────────────────────────────────────────────────────────────────────
// The locked-node interaction TRIO (Plan M2-4-3 T3, KD-3; CONTEXT Specific
// Ideas) — badge + interception + hint in ONE reusable modifier. The
// signature is GENERIC (no node semantics): M2-7's first-group lock
// consumes it verbatim. What this plan freezes is the trio's SEMANTICS
// (visible lock mark / disabled interactions / tap-for-hint), not the
// call sites — an M2-7 evolution is additive parameters (the plan's risk
// note). Selection/navigation attaches OUTSIDE the trio by design: a
// locked card is navigable, never editable (the D-M2-4-CONTEXT-7 face).
// ─────────────────────────────────────────────────────────────────────────────

/// The lock badge (the trio's visual arm; the stable AX marker).
struct NodeLockedBadge: View {

    /// The badge's AX marker (L010: stable ids — the AC5 machine check).
    static let marker = "editor.nodes.locked"

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.caption2)
            .foregroundStyle(ThemeTokens.textSecondary)
            .padding(4)
            .background { Circle().fill(ThemeTokens.cardSurface) }
            .overlay { Circle().strokeBorder(ThemeTokens.cardBorder, lineWidth: 1) }
            .accessibilityIdentifier(Self.marker)
    }
}

extension View {

    /// The locked-node trio: the BADGE at the top-trailing corner (tap →
    /// `hint`), the decorated view's interactions INTERCEPTED while locked
    /// (hit testing off — sliders/menus inside die with it), and the hint
    /// callback (the Alcedo `LockedNodeMaskPromptDialog` semantics as the
    /// caller's toast/handling). Unlocked = the view verbatim.
    func nodeLocked(_ locked: Bool, hint: @escaping () -> Void) -> some View {
        allowsHitTesting(!locked)
            .overlay(alignment: .topTrailing) {
                if locked {
                    NodeLockedBadge()
                        .onTapGesture(perform: hint)
                        .offset(x: 5, y: -5)
                }
            }
    }
}
