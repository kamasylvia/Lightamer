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

    @State private var showsBrushPopover = false

    /// The AI generation lifecycle (spinner + error toast face).
    @State private var aiPhase: AIGenerationPhase = .idle
    /// Non-nil = the layer-A multi-subject picker is up.
    @State private var instanceCatalog: AIInstanceCatalog?

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
    }

    private var hasSelection: Bool { editingState.selectedLayerID != nil }

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
                    Task { await generateSubjectMask() }
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
            }
        }
        .popover(item: $instanceCatalog) { catalog in
            InstancePickerOverlay(
                catalog: catalog,
                onConfirm: { plane in
                    instanceCatalog = nil
                    Task { await commitSubjectPlane(plane) }
                },
                onCancel: { instanceCatalog = nil })
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
    }

    // MARK: generation flows

    /// Layer A stage 1 → single subject bakes straight through; multiple
    /// subjects raise the instance picker.
    private func generateSubjectMask() async {
        guard let metal = metalContext else { return }
        aiPhase = .running
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
                try await commitAIMask(plane: plane, source: .subject, metal: metal)
                aiPhase = .idle
            }
        } catch let error as AIMaskError {
            aiPhase = .failed("\(error)")
            editorState.presentToast(
                error == .noSubject
                    ? String(localized: "ai_toast_no_subject")
                    : String(localized: "ai_toast_generate_failed") + " (\(error))")
        } catch {
            aiPhase = .failed("\(error)")
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }

    /// The instance picker's confirmed subset.
    private func commitSubjectPlane(_ plane: AIMaskPlane) async {
        guard let metal = metalContext else { return }
        aiPhase = .running
        defer { if case .running = aiPhase { aiPhase = .idle } }
        do {
            try await commitAIMask(plane: plane, source: .subject, metal: metal)
            aiPhase = .idle
        } catch {
            aiPhase = .failed("\(error)")
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }

    /// The shared commit channel (exactly ONE stackSnapshot item + the
    /// AI-06 landing form).
    func commitAIMask(plane: AIMaskPlane, source: AIMaskSource, metal: MetalContext) async throws {
        guard let (input, width, height) = AIMaskEditing.decodeFrameInput(pipeCoordinator) else {
            throw AIMaskError.invalidInput("no decoded frame for the mask commit")
        }
        _ = input
        let ref = try await AIMaskEditing.commitRasterMask(
            plane: plane, source: source,
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
