import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Crop panel (Plan 04-02-T5) — the IOP-GEO-01 Inspector surface: aspect
// preset picker + four fraction sliders (left/top/right/bottom) + reset.
//
// D-H1 wiring: sliders are the drag-begin/tick/end trio (zero history
// during the drag, exactly ONE commit at the end); the preset picker +
// reset button are discrete one-commit edits. Values READ from the
// instance record (same record the overlay drives — panel/overlay同源,
// CropOverlayTests + the wiring test below pin it).
//
// ROTATION NOTE (SC#1): the "rotation micro-adjust" entry is 04-03
// ashift's panel — this panel leaves the linkage note, no stub slider.
// ─────────────────────────────────────────────────────────────────────────

internal struct CropPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: CropModule.Params {
        PanelEditing.params(of: instance, as: CropModule.self)
            ?? CropModule.Params()
    }

    var body: some View {
        Form {
            Section {
                Picker("panel_crop_aspect", selection: aspectBinding) {
                    Text("panel_crop_aspect_free").tag(CropAspectPreset.free)
                    Text("panel_crop_aspect_original").tag(CropAspectPreset.original)
                    Text("panel_crop_aspect_1x1").tag(CropAspectPreset.square1x1)
                    Text("panel_crop_aspect_4x3").tag(CropAspectPreset.ratio4x3)
                    Text("panel_crop_aspect_3x2").tag(CropAspectPreset.ratio3x2)
                    Text("panel_crop_aspect_16x9").tag(CropAspectPreset.ratio16x9)
                    Text("panel_crop_aspect_16x10").tag(CropAspectPreset.ratio16x10)
                }
                .accessibilityIdentifier("inspector.crop.aspect")
                Text("panel_crop_aspect_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            } header: {
                Text("panel_crop_aspect_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_crop_left"),
                    value: Double(params.left),
                    range: 0...(1 - 0.01),
                    defaultValue: 0,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.left, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_crop")) },
                    onReset: { reset(\.left, 0) },
                    accessibilityID: "inspector.slider.crop.left"
                )
                LightamerSlider(
                    label: String(localized: "panel_crop_top"),
                    value: Double(params.top),
                    range: 0...(1 - 0.01),
                    defaultValue: 0,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.top, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_crop")) },
                    onReset: { reset(\.top, 0) },
                    accessibilityID: "inspector.slider.crop.top"
                )
                LightamerSlider(
                    label: String(localized: "panel_crop_right"),
                    value: Double(params.right),
                    range: 0.01...1,
                    defaultValue: 1,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.right, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_crop")) },
                    onReset: { reset(\.right, 1) },
                    accessibilityID: "inspector.slider.crop.right"
                )
                LightamerSlider(
                    label: String(localized: "panel_crop_bottom"),
                    value: Double(params.bottom),
                    range: 0.01...1,
                    defaultValue: 1,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.bottom, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_crop")) },
                    onReset: { reset(\.bottom, 1) },
                    accessibilityID: "inspector.slider.crop.bottom"
                )
            } header: {
                Text("panel_crop_rect_section")
            }

            Section {
                Button(String(localized: "panel_crop_reset")) {
                    applyDiscrete(CropModule.Params())
                }
                .accessibilityIdentifier("inspector.crop.reset")
                Text("panel_crop_rotation_note")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            } header: {
                Text("panel_crop_actions_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.crop")
    }

    /// The preset picker is display-state only in v1 (the Params ratio
    /// bits ride for Phase 11; the overlay drag enforces the lock at
    /// edit time via `CropOverlayHost.preset` — the picker here selects
    /// the host preset through the record's ratio bits on commit).
    private var aspectBinding: Binding<CropAspectPreset> {
        Binding(
            get: {
                let p = params
                if p.ratioN == -1, p.ratioD == -1 { return .free }
                if p.ratioN == 0 { return .original }
                if p.ratioN == 1, p.ratioD == 1 { return .square1x1 }
                if p.ratioN == 4, p.ratioD == 3 { return .ratio4x3 }
                if p.ratioN == 3, p.ratioD == 2 { return .ratio3x2 }
                if p.ratioN == 16, p.ratioD == 9 { return .ratio16x9 }
                if p.ratioN == 16, p.ratioD == 10 { return .ratio16x10 }
                return .free
            },
            set: { preset in
                var p = params
                switch preset {
                case .free: p.ratioN = -1; p.ratioD = -1
                case .original: p.ratioN = 0; p.ratioD = 1
                case .square1x1: p.ratioN = 1; p.ratioD = 1
                case .ratio4x3: p.ratioN = 4; p.ratioD = 3
                case .ratio3x2: p.ratioN = 3; p.ratioD = 2
                case .ratio16x9: p.ratioN = 16; p.ratioD = 9
                case .ratio16x10: p.ratioN = 16; p.ratioD = 10
                }
                applyDiscrete(p)
            }
        )
    }

    private func set(_ keyPath: WritableKeyPath<CropModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: CropModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<CropModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: CropModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: CropModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_crop"))
        }
    }
}

internal struct CropPanelProvider: IOPPanelProvider {
    var opName: String { CropModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(CropPanelView(instance: instance, edit: edit))
    }
}
