import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// MaskToolbarView (Plan 06-05 T3.1/T3.2; Plan 07-3 T1/T2) — the mask
// drawing toolbar, a floating strip at the viewport's BOTTOM EDGE (視口下缘
// 浮层 — it must NOT grow the Inspector column, and the viewport keeps
// ≥50%).
//
// Content: the five tools (brush / eraser / gradient / ellipse / path —
// radio semantics via `LayerEditingState.setTool`) + the brush parameter
// popover (size / hardness / flow / opacity sliders; the cmd-drag size
// gesture is a Manual-Only item — L011) + the gradient profile toggle
// (linear / sigmoidal) + the AI GROUP (Plan 07-3):
//   「主体蒙版」  — layer A one-tap (offline built-in model); multi-subject
//                 frames raise the InstancePickerOverlay first.
//   「点击选取」  — layer B tap-to-segment entry, gated by the AIAssetPhase
//                 three-state (needsDownload → guided download action;
//                 downloading → spinner; ready → the segment edit mode).
//
// Disabled WITHOUT a selected layer (「选中层才可绘」— the disabled state is
// the plan's requirement); armed tools route the viewport to the
// MaskOverlayHost through the `LayerEditingState` machine.
//
// Panel四件套: L010 identifiers (`mask.toolbar`, `mask.tool.<name>`,
// `ai.mask.*`) + zh/en String Catalog + the floating-strip constraint +
// D-H1 (parameter sliders commit NOTHING — they are editing-mode state, not
// history; the stroke they produce commits once at stroke end).
// ─────────────────────────────────────────────────────────────────────────

internal struct MaskToolbarView: View {

    let metalContext: MetalContext?

    @Environment(LayerEditingState.self) private var editingState
    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    /// The layer-B asset phase — the SAME model the app-level
    /// AIDownloadPrompt observes (one state machine, D-07-CONTEXT-1).
    @Environment(AIDownloadModel.self) private var aiDownload
    /// The depth mask orchestration (M4-3-01) — app-root owned, the
    /// single DepthMaskService instance.
    @Environment(DepthMaskService.self) private var depthService

    @State private var showsBrushPopover = false

    /// The AI generation lifecycle (spinner + error toast face).
    @State private var aiPhase: AIGenerationPhase = .idle
    /// The depth generation lifecycle (the same three-state face).
    @State private var depthPhase: AIGenerationPhase = .idle
    /// Non-nil = the layer-A multi-subject picker is up.
    @State private var instanceCatalog: AIInstanceCatalog?
    /// The T7 sugar: the invert assembly rides the pending generation (the
    /// multi-subject picker's confirm consumes it).
    @State private var pendingInvert = false

    enum AIGenerationPhase: Equatable {
        case idle
        case running
        case failed(String)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MaskTool.allCases, id: \.rawValue) { tool in
                Button {
                    // Radio semantics: tapping the armed tool disarms it.
                    editingState.setTool(editingState.activeTool == tool ? nil : tool)
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.callout)
                        .frame(width: 24, height: 22)
                        .background(
                            editingState.activeTool == tool
                                ? LightamerColors.accent.opacity(0.4)
                                : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.borderless)
                .disabled(!hasSelection)
                .accessibilityLabel(Text(String(localized: String.LocalizationValue(tool.labelKey))))
                .accessibilityValue(
                    editingState.activeTool == tool ? Text("toggle_on") : Text("toggle_off"))
                .accessibilityIdentifier(tool.identifier)
            }

            Divider()
                .frame(height: 16)

            // Brush parameter popover (the parameter RING's panel leg; the
            // cmd-drag-on-viewport size gesture is Manual-Only registered).
            Button {
                showsBrushPopover.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .disabled(!hasSelection)
            .accessibilityLabel(Text("mask_brush_params"))
            .accessibilityIdentifier("mask.toolbar.brushparams")
            .popover(isPresented: $showsBrushPopover) {
                brushPopover
                    .padding(12)
                    .frame(width: 230)
            }

            // T5 (KD-5): the Follow Edges parameter section — the walker's
            // four parameters (the WIDTH passes through as the brush
            // radius) + the mode indicator + the empty-chain status hint.
            // EDITING-MODE state only: nothing here commits history.
            if editingState.activeTool == .followEdges {
                followEdgesSection
            }

            // Gradient profile toggle (linear ↔ sigmoidal, discrete).
            Picker("mask_gradient_profile", selection: Binding(
                get: { editingState.gradientState },
                set: { editingState.gradientState = $0 }
            )) {
                Text("mask_gradient_linear").tag(GradientState.linear)
                Text("mask_gradient_sigmoidal").tag(GradientState.sigmoidal)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 120)
            .disabled(editingState.activeTool != .gradient)
            .accessibilityIdentifier("mask.toolbar.gradientprofile")

            // 13-3 T5: the overlay display STYLE (On-Black / Rubylith /
            // 半透明) — a display-only enum; flipping it re-issues the
            // overlay request so the tint swaps without touching data.
            Picker("mask_overlay_style", selection: Binding(
                get: { editingState.maskOverlayStyle },
                set: { newValue in
                    editingState.maskOverlayStyle = newValue
                    refreshOverlayRequest()
                }
            )) {
                ForEach(MaskOverlayStyle.allCases, id: \.rawValue) { style in
                    Text(String(localized: String.LocalizationValue(style.labelKey)))
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 150)
            .disabled(!hasSelection)
            .accessibilityIdentifier("mask.toolbar.overlaystyle")

            aiGroup

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .accessibilityIdentifier("mask.toolbar")
        .task { await depthService.refresh() }
        // T4 (KD-4, checker E1): the completion-time ask sheet — the
        // `ask` behavior's one-shot face. The choice is NOT persisted
        // (M2-3 semantics: ask on every completion; no "don't ask again").
        .sheet(isPresented: Binding(
            get: { editingState.pendingMaskBehaviorAsk },
            set: { editingState.pendingMaskBehaviorAsk = $0 }
        )) {
            VStack(spacing: 16) {
                Text("mask_behavior_ask_title")
                    .font(.headline)
                Text("mask_behavior_ask_body")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                HStack(spacing: 12) {
                    Button {
                        // Keep: dismiss, zero history items.
                        editingState.pendingMaskBehaviorAsk = false
                    } label: {
                        Text("mask_behavior_ask_keep")
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mask.behavior.ask.keep")
                    Button {
                        // Move: the SAME one-item migration the newLayer
                        // behavior uses.
                        editingState.confirmMaskBehaviorMove(editorState: editorState)
                    } label: {
                        Text("mask_behavior_ask_move")
                    }
                    .accessibilityIdentifier("mask.behavior.ask.move")
                }
            }
            .padding(24)
        }
    }

    private var hasSelection: Bool { editingState.selectedLayerID != nil }

    // MARK: - Follow Edges parameters (T5, KD-5)

    /// The walker parameter section: mode indicator + contrast threshold +
    /// follow strength + the one-sided direction + the empty-chain status
    /// hint (KD-P1 KD-6's degrade face; the interaction leg clears it on
    /// success). Binding through explicit get/set pairs (the @Environment
    /// Observable projection has no $ — the brush popover's precedent).
    private var followEdgesSection: some View {
        func floatBinding(
            _ get: @escaping (LayerEditingState) -> Float,
            _ set: @escaping (LayerEditingState, Float) -> Void
        ) -> Binding<Float> {
            Binding(get: { get(editingState) }, set: { set(editingState, $0) })
        }
        return HStack(spacing: 10) {
            Picker("mask_follow_mode", selection: Binding(
                get: { editingState.followEdgesParams.mode },
                set: { editingState.followEdgesParams.mode = $0 }
            )) {
                Text("mask_follow_mode_streamline").tag(FollowEdgesMode.streamline)
                Text("mask_follow_mode_snap").tag(FollowEdgesMode.snap)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 140)
            .accessibilityIdentifier("mask.toolbar.follow.mode")

            slider(
                "mask_follow_threshold",
                value: floatBinding(
                    { $0.followEdgesParams.edgeThreshold },
                    { $0.followEdgesParams.edgeThreshold = $1 }),
                in: 0...1)

            slider(
                "mask_follow_strength",
                value: floatBinding(
                    { $0.followEdgesParams.followStrength },
                    { $0.followEdgesParams.followStrength = $1 }),
                in: 0...1)

            Button {
                editingState.followEdgesParams.direction =
                    editingState.followEdgesParams.direction >= 0 ? -1 : 1
            } label: {
                Image(systemName:
                    editingState.followEdgesParams.direction >= 0
                        ? "arrow.right" : "arrow.left")
                    .font(.callout)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("mask_follow_direction"))
            .accessibilityIdentifier("mask.toolbar.follow.direction")

            if editingState.followEdgesDegraded {
                Text("mask_follow_degraded_hint")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("mask.toolbar.follow.degraded")
            }
        }
    }

    /// Re-issue the CURRENT layer's overlay request with the live style
    /// (13-3 T5 — the style flip's re-render leg; the LayersPanel twin is
    /// `refreshMaskOverlayRequest`).
    private func refreshOverlayRequest() {
        guard let id = editingState.selectedLayerID,
              let layer = editorState.adjustmentLayer(id: id),
              layer.mask?.hasAnyPayload == true,
              editingState.showsMaskOverlay
        else {
            pipeCoordinator.setMaskOverlayRequest(nil)
            return
        }
        pipeCoordinator.setMaskOverlayRequest(
            (id, 0.85, editingState.maskOverlayStyle))
    }

    // MARK: - AI group (Plan 07-3 T1)

    @ViewBuilder
    private var aiGroup: some View {
        Divider()
            .frame(height: 16)

        // 主体蒙版 — layer A one-tap (offline, built-in model).
        Group {
            if aiPhase == .running {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 22)
                    .accessibilityLabel(Text("ai_mask_generating"))
                    .accessibilityIdentifier("ai.mask.progress")
            } else {
                Button {
                    Task { await generateSubjectMask(invert: false) }
                } label: {
                    Image(systemName: "person.crop.square.badge.camera")
                        .font(.callout)
                        .frame(width: 24, height: 22)
                        .background(
                            aiPhase == .running
                                ? LightamerColors.accent.opacity(0.4)
                                : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.borderless)
                .disabled(!hasSelection)
                .accessibilityLabel(Text("ai_mask_subject"))
                .accessibilityIdentifier("ai.mask.subject")

                // T7 (KD-7): the「主体以外」sugar — the SAME subject
                // generation with the invert assembly baked via the per-ref
                // invert bit (RasterMaskRef.invert). Zero new kernel, zero
                // AIMaskEditing/AIMaskService change.
                Button {
                    Task { await generateSubjectMask(invert: true) }
                } label: {
                    Image(systemName: "person.slash")
                        .font(.callout)
                        .frame(width: 24, height: 22)
                        .cornerRadius(4)
                }
                .buttonStyle(.borderless)
                .disabled(!hasSelection)
                .accessibilityLabel(Text("ai_mask_subject_inverted"))
                .accessibilityIdentifier("ai.mask.subject.inverted")
            }
        }
        .popover(item: $instanceCatalog) { catalog in
            InstancePickerOverlay(
                catalog: catalog,
                onConfirm: { plane in
                    instanceCatalog = nil
                    let invert = pendingInvert
                    pendingInvert = false
                    Task { await commitSubjectPlane(plane, invert: invert) }
                },
                onCancel: {
                    instanceCatalog = nil
                    pendingInvert = false
                })
        }

        // 点击选取 — layer B entry, the asset-phase gate.
        switch AIMaskEntryGate.layerBEntry(for: aiDownload.phase) {
        case .ready:
            Button {
                editingState.setSegmentActive(true)
            } label: {
                Image(systemName: "hand.tap")
                    .font(.callout)
                    .frame(width: 24, height: 22)
                    .background(
                        editingState.segmentActive
                            ? LightamerColors.accent.opacity(0.4)
                            : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .disabled(!hasSelection)
            .accessibilityLabel(Text("ai_mask_tap"))
            .accessibilityIdentifier("ai.mask.tap")
        case .downloading:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 24, height: 22)
                .accessibilityLabel(Text("ai_download_progress"))
                .accessibilityIdentifier("ai.mask.tap.downloading")
        case .needsDownload:
            Button {
                aiDownload.accept() // the guided one-time download
            } label: {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.callout)
                    .frame(width: 24, height: 22)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .disabled(!hasSelection)
            // GUI-20: the guided entry explains WHERE the model comes from
            // (system Vision assets) — the failure mode (no error, still
            // not ready) is surfaced by AIDownloadModel's alert.
            .help(String(localized: "ai_mask_download_help"))
            .accessibilityLabel(Text("ai_mask_download"))
            .accessibilityIdentifier("ai.mask.download")
        case .failed:
            Button {
                aiDownload.retry()
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 22)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("ai_download_retry"))
            .accessibilityIdentifier("ai.mask.tap.retry")
        }

        depthGroup
    }

    // MARK: - Depth group (M4-3-01 KD-6, OQ-4-A: ONE entry, zero parameter
    // face — 0.48/0.22 window and the 10/95 percentiles are named Core
    // constants, nothing here exposes them; far side = the invert bit).

    @ViewBuilder
    private var depthGroup: some View {
        Divider()
            .frame(height: 16)
        switch DepthEntryGate.map(service: depthService.entry, running: depthPhase == .running) {
        case .generating:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 22)
                .accessibilityLabel(Text("ai_mask_depth"))
                .accessibilityIdentifier("ai.mask.depth.progress")
        case .generate:
            Button {
                Task { await generateDepthMask() }
            } label: {
                Image(systemName: "square.stack.3d.up.forward")
                    .font(.callout)
                    .frame(width: 24, height: 22)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .disabled(!hasSelection)
            .accessibilityLabel(Text("ai_mask_depth"))
            .accessibilityIdentifier("ai.mask.depth")
        case .download(let armed):
            Button {
                Task {
                    await downloadAndGenerateDepth()
                }
            } label: {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.callout)
                    .frame(width: 24, height: 22)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .disabled(!armed || !hasSelection)
            .help(String(localized: "ai_mask_depth_download_help"))
            .accessibilityLabel(Text("ai_mask_depth_download"))
            .accessibilityIdentifier("ai.mask.depth.download")
        case .downloading(let fraction):
            ProgressView()
                .controlSize(.mini)
                .frame(width: 24, height: 22)
            Text(verbatim: "\(Int((fraction * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai.mask.depth.downloading")
        case .retry:
            Button {
                Task {
                    await downloadAndGenerateDepth()
                }
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 22)
                    .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("ai_download_retry"))
            .accessibilityIdentifier("ai.mask.depth.retry")
        }
    }

    // MARK: depth generation flows

    /// One depth generation (the service owns preview → worker → pipeline;
    /// the commit lands through the shared seam). The noDepthStructure
    /// face carries its own toast (the honest no-layering message).
    private func generateDepthMask() async {
        guard let metal = metalContext else { return }
        depthPhase = .running
        defer { if case .running = depthPhase { depthPhase = .idle } }
        do {
            try await depthService.generate(
                coordinator: pipeCoordinator, editorState: editorState,
                editingState: editingState, metal: metal)
            depthPhase = .idle
            editorState.presentToast(String(localized: "ai_toast_mask_ready"))
        } catch let error as AIMaskError {
            depthPhase = .idle
            if case .noDepthStructure = error {
                editorState.presentToast(
                    String(localized: "ai_toast_depth_no_structure"))
            } else {
                editorState.presentToast(
                    String(localized: "ai_toast_generate_failed") + " (\(error))")
            }
        } catch {
            depthPhase = .idle
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }

    /// The single-tap journey: download → extract → one generation (the
    /// service reports its own done/failed toasts and re-reads the gate).
    private func downloadAndGenerateDepth() async {
        guard let metal = metalContext else { return }
        await depthService.downloadThenGenerate(
            coordinator: pipeCoordinator, editorState: editorState,
            editingState: editingState, metal: metal)
    }

    // MARK: generation flows

    /// Layer A stage 1 → single subject bakes straight through; multiple
    /// subjects raise the instance picker. `invert` = the「主体以外」sugar
    /// (the SAME generation; the invert rides the per-ref bit).
    private func generateSubjectMask(invert: Bool) async {
        guard let metal = metalContext else { return }
        aiPhase = .running
        pendingInvert = invert
        defer { if case .running = aiPhase { aiPhase = .idle } }
        do {
            guard let (input, _, _) = AIMaskEditing.decodeFrameInput(pipeCoordinator) else {
                throw AIMaskError.invalidInput("no decoded frame for inference")
            }
            let catalog = try await AIMaskService.detectInstances(input: input)
            if catalog.instances.count > 1 {
                aiPhase = .idle
                instanceCatalog = catalog
            } else {
                let plane = try AIMaskService.subjectMask(from: catalog, selection: .all)
                try await commitAIMask(
                    plane: plane, source: .subject, invert: invert, metal: metal)
                aiPhase = .idle
            }
        } catch let error as AIMaskError {
            aiPhase = .failed("\(error)")
            pendingInvert = false
            editorState.presentToast(
                error == .noSubject
                    ? String(localized: "ai_toast_no_subject")
                    : String(localized: "ai_toast_generate_failed") + " (\(error))")
        } catch {
            aiPhase = .failed("\(error)")
            pendingInvert = false
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }

    /// The instance picker's confirmed subset.
    private func commitSubjectPlane(_ plane: AIMaskPlane, invert: Bool = false) async {
        guard let metal = metalContext else { return }
        aiPhase = .running
        defer { if case .running = aiPhase { aiPhase = .idle } }
        do {
            try await commitAIMask(
                plane: plane, source: .subject, invert: invert, metal: metal)
            aiPhase = .idle
        } catch {
            aiPhase = .failed("\(error)")
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }

    /// The shared commit channel (exactly ONE stackSnapshot item + the
    /// AI-06 landing form). `invert` rides the per-ref bit (KD-7's
    /// raster-first assembly — RasterMaskRef.invert, the 06-04 semantics).
    func commitAIMask(
        plane: AIMaskPlane, source: AIMaskSource, invert: Bool = false,
        metal: MetalContext
    ) async throws {
        guard let (input, width, height) = AIMaskEditing.decodeFrameInput(pipeCoordinator) else {
            throw AIMaskError.invalidInput("no decoded frame for the mask commit")
        }
        _ = input
        let ref = try await AIMaskEditing.commitRasterMask(
            plane: plane, source: source, invert: invert,
            decodeWidth: width, decodeHeight: height,
            label: String(localized: "history_ai_mask"),
            activateTool: .brush,
            coordinator: pipeCoordinator, editorState: editorState,
            editingState: editingState, metal: metal)
        _ = ref
        editorState.presentToast(String(localized: "ai_toast_mask_ready"))
    }

    /// The brush parameter sliders — EDITING-MODE state (no history; the
    /// values ride the NEXT stroke's BrushStroke record).
    private var brushPopover: some View {
        // @Environment(Observable) has no $ projection without @Bindable —
        // bind through explicit get/set pairs (the values are plain Floats).
        func bind(_ get: @escaping (LayerEditingState) -> Float, _ set: @escaping (LayerEditingState, Float) -> Void) -> Binding<Float> {
            Binding(
                get: { get(editingState) },
                set: { set(editingState, $0) })
        }
        return VStack(alignment: .leading, spacing: 8) {
            slider("mask_brush_size", value: bind({ $0.brushRadius }, { $0.brushRadius = $1 }), in: 0.005...0.3)
            slider("mask_brush_hardness", value: bind({ $0.brushHardness }, { $0.brushHardness = $1 }), in: 0...1)
            slider("mask_brush_flow", value: bind({ $0.brushFlow }, { $0.brushFlow = $1 }), in: 0.05...1)
            slider("mask_brush_opacity", value: bind({ $0.brushOpacity }, { $0.brushOpacity = $1 }), in: 0.05...1)
            Text("mask_brush_cmddrag_hint")
                .font(.caption2)
                .foregroundStyle(LightamerColors.textSecondary)
        }
    }

    private func slider(
        _ labelKey: String, value: Binding<Float>, in range: ClosedRange<Float>
    ) -> some View {
        HStack {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Float($0) }), in: Double(range.lowerBound)...Double(range.upperBound))
                .controlSize(.small)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
