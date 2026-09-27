import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// SkinSmoothPanelView (Plan 07-3 T3) — the 25TH Inspector panel: the
// frequency-separation skin smoothing parameters (radius σ / strength a /
// detail-preserve t — D-07-CONTEXT-6's three sliders) + the variant slot
// (v1 = the single .twoBandGaussian case, DISABLED picker — the recorded
// v2 seam) + the「定位皮肤」action (SkinRegionService.locate → bake → the
// layer's mask slot — the SAME channel as the MaskToolbar AI masks) + the
// skin-mask display toggle (the hull−protect visualization).
//
// D-H1 三件套: slider drags live-tick (zero history), land exactly ONE
// layerScope commit at drag end; reset is a discrete one-commit edit.
//
// NON-SILENT faces (07-CONTEXT): yaw-gated faces surface as a toast with
// their index/angle; no faces / no usable face = an error toast, NEVER a
// bad mask (the generation-failure strictness).
// ─────────────────────────────────────────────────────────────────────────

internal struct SkinSmoothPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState

    @State private var locating = false

    private var params: SkinSmoothModule.Params {
        PanelEditing.params(of: instance, as: SkinSmoothModule.self)
            ?? SkinSmoothModule.Params()
    }

    var body: some View {
        Form {
            Section {
                // Human-unit ranges (the % sliders map to the params'
                // 0-1/0-0.2 fractions in the change legs — the shared
                // LightamerSlider stays untouched, 24-panel regression safe).
                LightamerSlider(
                    label: String(localized: "panel_skinsmooth_radius"),
                    value: Double(params.radius),
                    range: 1...32,
                    defaultValue: 8,
                    readoutFormat: "%.0f",
                    unit: " px",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.radius, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_skinsmooth")) },
                    onReset: { reset(\.radius, 8) },
                    accessibilityID: "inspector.slider.skinsmooth.radius"
                )
                LightamerSlider(
                    label: String(localized: "panel_skinsmooth_strength"),
                    value: Double(params.strength) * 100,
                    range: 0...100,
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0) / 100) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_skinsmooth")) },
                    onReset: { reset(\.strength, 0) },
                    accessibilityID: "inspector.slider.skinsmooth.strength"
                )
                LightamerSlider(
                    label: String(localized: "panel_skinsmooth_detail"),
                    value: Double(params.detailPreserve) * 500,
                    range: 0...100,
                    defaultValue: 10,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.detailPreserve, Float($0) / 500) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_skinsmooth")) },
                    onReset: { reset(\.detailPreserve, 0.02) },
                    accessibilityID: "inspector.slider.skinsmooth.detail"
                )

                // The v2 VARIANT SLOT (D-07-CONTEXT-6): one case in v1 —
                // the picker renders the seam, disabled until v2 cases land.
                Picker("panel_skinsmooth_variant", selection: Binding(
                    get: { params.variant },
                    set: { _ in } // v1: a single case — nothing to set
                )) {
                    Text("panel_skinsmooth_variant_twoband")
                        .tag(SkinSmoothModule.Variant.twoBandGaussian)
                }
                .pickerStyle(.menu)
                .disabled(true)
                .accessibilityIdentifier("inspector.picker.skinsmooth.variant")
            } header: {
                Text("panel_skinsmooth_section")
            }

            Section {
                Button {
                    Task { await locateSkin() }
                } label: {
                    HStack {
                        if locating {
                            ProgressView().controlSize(.small)
                            Text("skin_locate_running")
                        } else {
                            Image(systemName: "face.dashed")
                            Text("skin_locate")
                        }
                    }
                }
                .disabled(locating || editingState.selectedLayerID == nil)
                .accessibilityIdentifier("skin.locate")

                // The skin-mask display toggle (the hull−protect tint on
                // the SELECTED layer — the mask the locate baked).
                Toggle(String(localized: "skin_protect_toggle"), isOn: Binding(
                    get: { maskTintShown },
                    set: { setMaskTint($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(editingState.selectedLayerID == nil)
                .accessibilityIdentifier("skin.protect.toggle")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.skinsmooth")
    }

    // MARK: D-H1 legs

    private func set(_ keyPath: WritableKeyPath<SkinSmoothModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SkinSmoothModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<SkinSmoothModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SkinSmoothModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_skinsmooth"))
        }
    }

    // MARK: the skin-mask tint toggle

    private var maskTintShown: Bool {
        guard let id = editingState.selectedLayerID else { return false }
        return pipeCoordinator.maskOverlayRequest?.layerID == id
    }

    private func setMaskTint(_ shown: Bool) {
        guard let id = editingState.selectedLayerID else { return }
        pipeCoordinator.setMaskOverlayRequest(
            shown ? (id, 0.85, editingState.maskOverlayStyle) : nil)
    }

    // MARK:「定位皮肤」

    private func locateSkin() async {
        guard let metal = pipeCoordinator.detectionMetal(),
              let (input, width, height) = AIMaskEditing.decodeFrameInput(pipeCoordinator)
        else { return }
        locating = true
        defer { locating = false }
        do {
            let (plane, warnings) = try await SkinRegionService.locate(
                input: input, width: width, height: height)
            // NON-SILENT: every yaw-gated face surfaces (07-CONTEXT).
            for warning in warnings {
                if case .faceExcludedHighYaw(let index, let yaw, let limit) = warning {
                    edit.presentToast(String(localized: "skin_toast_yaw \(index) \(yaw) \(limit)"))
                }
            }
            _ = try await AIMaskEditing.commitRasterMask(
                plane: plane, source: .skin,
                decodeWidth: width, decodeHeight: height,
                label: String(localized: "history_ai_mask"),
                activateTool: nil, // stay on the skinSmooth panel
                coordinator: pipeCoordinator, editorState: editorState,
                editingState: editingState, metal: metal)
            edit.presentToast(String(localized: "skin_toast_ready"))
        } catch let error as SkinRegionError {
            edit.presentToast(
                error == .noFaces
                    ? String(localized: "skin_toast_no_face")
                    : String(localized: "skin_toast_generate_failed") + " (\(error))")
        } catch {
            edit.presentToast(String(localized: "skin_toast_generate_failed") + " (\(error))")
        }
    }
}

internal struct SkinSmoothPanelProvider: IOPPanelProvider {
    var opName: String { SkinSmoothModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(SkinSmoothPanelView(instance: instance, edit: edit))
    }
}
