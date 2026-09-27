import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// BloomPanelView (Plan 08-2 T3) — the bloom parameter panel: the dt
// `bloom.c:47-51` three-slider face verbatim — size / threshold / strength.
//
// D-H1 三件套: slider drags live-tick (zero history), land exactly ONE
// layerScope commit at drag end; reset is a discrete one-commit edit.
// ─────────────────────────────────────────────────────────────────────────

internal struct BloomPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: BloomModule.Params {
        PanelEditing.params(of: instance, as: BloomModule.self)
            ?? BloomModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_bloom_size"),
                    value: Double(params.size),
                    range: 0...100,
                    defaultValue: 20,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.size, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bloom")) },
                    onReset: { reset(\.size, 20) },
                    accessibilityID: "inspector.slider.bloom.size"
                )
                LightamerSlider(
                    label: String(localized: "panel_bloom_threshold"),
                    value: Double(params.threshold),
                    range: 0...100,
                    defaultValue: 90,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.threshold, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bloom")) },
                    onReset: { reset(\.threshold, 90) },
                    accessibilityID: "inspector.slider.bloom.threshold"
                )
                LightamerSlider(
                    label: String(localized: "panel_bloom_strength"),
                    value: Double(params.strength),
                    range: 0...100,
                    defaultValue: 25,
                    readoutFormat: "%.0f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bloom")) },
                    onReset: { reset(\.strength, 25) },
                    accessibilityID: "inspector.slider.bloom.strength"
                )
            } header: {
                Text("panel_bloom_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.bloom")
    }

    // MARK: D-H1 legs

    private func set(_ keyPath: WritableKeyPath<BloomModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: BloomModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<BloomModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: BloomModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_bloom"))
        }
    }
}

internal struct BloomPanelProvider: IOPPanelProvider {
    var opName: String { BloomModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(BloomPanelView(instance: instance, edit: edit))
    }
}
