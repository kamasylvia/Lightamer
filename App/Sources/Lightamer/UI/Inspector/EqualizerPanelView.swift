import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Equalizer panel (Plan 04-05-T5) — the IOP-DETAIL-04 Inspector surface:
// six band-gain sliders (g0..g4 residual bands + g5 coarse base; deltas
// ±2, multiplier = 1+delta). The curve Canvas is a stretch goal (defer —
// ToneEqualPanelView's Canvas is the copy pattern, plan T5 word).
//
// D-H1 wiring: drag trio per slider (zero history items while dragging,
// exactly ONE commit at drag end). Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

internal struct EqualizerPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: EqualizerModule.Params {
        PanelEditing.params(of: instance, as: EqualizerModule.self)
            ?? EqualizerModule.Params()
    }

    private static let bands: [(String, WritableKeyPath<EqualizerModule.Params, Float>)] = [
        ("panel_equalizer_g0", \.g0),
        ("panel_equalizer_g1", \.g1),
        ("panel_equalizer_g2", \.g2),
        ("panel_equalizer_g3", \.g3),
        ("panel_equalizer_g4", \.g4),
        ("panel_equalizer_g5", \.g5),
    ]

    private static let accessIDs = [
        "inspector.slider.equalizer.g0",
        "inspector.slider.equalizer.g1",
        "inspector.slider.equalizer.g2",
        "inspector.slider.equalizer.g3",
        "inspector.slider.equalizer.g4",
        "inspector.slider.equalizer.g5",
    ]

    var body: some View {
        Form {
            Section {
                ForEach(0..<Self.bands.count, id: \.self) { i in
                    LightamerSlider(
                        label: String(localized: String.LocalizationValue(Self.bands[i].0)),
                        value: Double(params[keyPath: Self.bands[i].1]),
                        range: -2...2,
                        defaultValue: 0,
                        readoutFormat: "%+.2f",
                        unit: "",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { set(Self.bands[i].1, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_equalizer")) },
                        onReset: { reset(Self.bands[i].1, 0) },
                        accessibilityID: Self.accessIDs[i]
                    )
                }
            } header: {
                Text("panel_equalizer_bands_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.equalizer")
    }

    private func set(_ keyPath: WritableKeyPath<EqualizerModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: EqualizerModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<EqualizerModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: EqualizerModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: EqualizerModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_equalizer"))
        }
    }
}

internal struct EqualizerPanelProvider: IOPPanelProvider {
    var opName: String { EqualizerModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(EqualizerPanelView(instance: instance, edit: edit))
    }
}
