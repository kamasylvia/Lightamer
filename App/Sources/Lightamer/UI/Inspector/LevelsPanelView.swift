import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Levels panel (Plan 03-03-T6) — mode picker (manual/automatic) + the
// three point sliders. The sliders are DUAL-ROLE, mirroring dt's stacked
// GUI (levels.c gui_changed): in MANUAL mode they edit the levels[3]
// points (normalized ×100 display); in AUTOMATIC mode they edit the
// percentile params (black/gray/white). Switching the mode is a discrete
// one-commit edit; automatic recomputes the points per render (the
// histogram wiring lives in the module — T5).
// ─────────────────────────────────────────────────────────────────────────

internal struct LevelsPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: LevelsModule.Params {
        PanelEditing.params(of: instance, as: LevelsModule.self)
            ?? LevelsModule.Params()
    }

    var body: some View {
        Form {
            Section {
                Picker("panel_levels_mode", selection: modeBinding) {
                    Text("panel_levels_mode_manual").tag(LevelsModule.Mode.manual)
                    Text("panel_levels_mode_automatic").tag(LevelsModule.Mode.automatic)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.levels.mode")

                if params.mode == .automatic {
                    Text("panel_levels_automatic_hint")
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                }
            } header: {
                Text("panel_levels_mode_section")
            }

            Section {
                pointSlider(
                    label: String(localized: "panel_levels_black"),
                    accessibilityID: "inspector.slider.levels.black",
                    index: 0
                )
                pointSlider(
                    label: String(localized: "panel_levels_gray"),
                    accessibilityID: "inspector.slider.levels.gray",
                    index: 1
                )
                pointSlider(
                    label: String(localized: "panel_levels_white"),
                    accessibilityID: "inspector.slider.levels.white",
                    index: 2
                )
            } header: {
                Text(params.mode == .automatic
                    ? String(localized: "panel_levels_percentiles_section")
                    : String(localized: "panel_levels_points_section"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.levels")
    }

    /// The dual-role point slider: manual → levels[index] (×100 display);
    /// automatic → the percentile field (black/gray/white per index).
    private func pointSlider(label: String, accessibilityID: String, index: Int) -> some View {
        let value: Double
        let range: ClosedRange<Double>
        if params.mode == .automatic {
            let raw: Float = index == 0 ? params.black : (index == 1 ? params.gray : params.white)
            value = Double(raw)
            range = 0...100
        } else {
            value = Double(params.levels.indices.contains(index) ? params.levels[index] : 0) * 100
            range = 0...100
        }
        return LightamerSlider(
            label: label,
            value: value,
            range: range,
            defaultValue: index == 1 ? 50 : (index == 0 ? 0 : 100),
            readoutFormat: "%.1f",
            unit: "",
            onDragBegin: { edit.beginEditing() },
            onChange: { setPoint(index: index, displayValue: $0) },
            onDragEnd: { edit.endEditing(label: String(localized: "history_levels")) },
            onReset: {
                var p = params
                if p.mode == .automatic {
                    let reset: Float = index == 0 ? 0 : (index == 1 ? 50 : 100)
                    if index == 0 { p.black = reset } else if index == 1 { p.gray = reset } else { p.white = reset }
                } else {
                    if p.levels.indices.contains(index) {
                        p.levels[index] = index == 1 ? 0.5 : (index == 0 ? 0 : 1)
                    }
                }
                applyDiscrete(p)
            },
            accessibilityID: accessibilityID
        )
    }

    private func setPoint(index: Int, displayValue: Double) {
        var p = params
        if p.mode == .automatic {
            let v = Float(displayValue)
            if index == 0 { p.black = v } else if index == 1 { p.gray = v } else { p.white = v }
        } else if p.levels.indices.contains(index) {
            p.levels[index] = Float(displayValue / 100)
        }
        if let record = PanelEditing.updated(instance, params: p, as: LevelsModule.self) {
            edit.update(record)
        }
    }

    private var modeBinding: Binding<LevelsModule.Mode> {
        Binding(
            get: { params.mode },
            set: { newMode in
                var p = params
                p.mode = newMode
                applyDiscrete(p)
            }
        )
    }

    private func applyDiscrete(_ p: LevelsModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: LevelsModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_levels"))
        }
    }
}

internal struct LevelsPanelProvider: IOPPanelProvider {
    var opName: String { LevelsModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LevelsPanelView(instance: instance, edit: edit))
    }
}
