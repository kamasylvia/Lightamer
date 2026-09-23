import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Bilateral panel (Plan 05-08-T4, IOP-DENOISE-03) — the Inspector surface
// for dt `bilateral` ("surface blur"): 4 sliders (radius / red / green /
// blue — dt gui_init one-to-one; the reserved slot is blob padding only).
//
// Slider ranges = dt's soft interactive extents (radius soft range 1-30,
// range sigmas soft max 0.1 @ 4 digits — dt gui_init; the hard maxima
// 50 / 1.0 stay reachable programmatically, NLMeansPanelView precedent).
//
// D-H1 wiring: LightamerSlider trio (begin/live-ticks/end — exactly ONE
// history commit per drag); resets = applyDiscrete one-commit. Values
// READ from the instance record. 280pt Inspector constraint (sliders
// only). 5D grid budget note: large-radius runs tile automatically via
// TilingPlan (D-05-08-T2-1) — no UI cap (dt has none either).
// ─────────────────────────────────────────────────────────────────────────

internal struct BilateralPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: BilateralModule.Params {
        (try? instance.params(of: BilateralModule.self)) ?? BilateralModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_bilateral_radius"),
                    value: Double(params.radius), range: 1...30, defaultValue: 15,
                    readoutFormat: "%.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.radius, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bilateral")) },
                    onReset: { reset(\.radius, 15) },
                    accessibilityID: "inspector.slider.bilateral.radius")
            } header: {
                Text("panel_bilateral_section_blur")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_bilateral_red"),
                    value: Double(params.red), range: 0.0001...0.1, defaultValue: 0.005,
                    readoutFormat: "%.4f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.red, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bilateral")) },
                    onReset: { reset(\.red, 0.005) },
                    accessibilityID: "inspector.slider.bilateral.red")
                LightamerSlider(
                    label: String(localized: "panel_bilateral_green"),
                    value: Double(params.green), range: 0.0001...0.1, defaultValue: 0.005,
                    readoutFormat: "%.4f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.green, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bilateral")) },
                    onReset: { reset(\.green, 0.005) },
                    accessibilityID: "inspector.slider.bilateral.green")
                LightamerSlider(
                    label: String(localized: "panel_bilateral_blue"),
                    value: Double(params.blue), range: 0.0001...0.1, defaultValue: 0.005,
                    readoutFormat: "%.4f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.blue, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_bilateral")) },
                    onReset: { reset(\.blue, 0.005) },
                    accessibilityID: "inspector.slider.bilateral.blue")
            } header: {
                Text("panel_bilateral_section_channels")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.bilateral")
    }

    private func set(
        _ keyPath: WritableKeyPath<BilateralModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: BilateralModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<BilateralModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: BilateralModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_bilateral"))
        }
    }
}

internal struct BilateralPanelProvider: IOPPanelProvider {
    var opName: String { BilateralModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(BilateralPanelView(instance: instance, edit: edit))
    }
}
