import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// NLMeans panel (Plan 05-06-T5, IOP-DENOISE-02) — the Inspector surface
// for dt `nlmeans` ("astrophoto denoise"): 4 sliders (radius / strength /
// luma / chroma — dt gui_init :430-449 one-to-one).
//
// Slider ranges = dt's SOFT-MAX interactive extents (radius soft max 4,
// strength soft max 100 — dt :435,439; the hard maxima 10 / 100000 stay
// reachable through params programmatically; DECISIONS D-05-06-T5-1).
//
// D-H1 wiring: LightamerSlider trio (begin/live-ticks/end — exactly ONE
// history commit per drag); resets = applyDiscrete one-commit. Values
// READ from the instance record. 280pt Inspector constraint (sliders
// only — MonochromePanelView precedent).
// ─────────────────────────────────────────────────────────────────────────

internal struct NLMeansPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: NLMeansModule.Params {
        (try? instance.params(of: NLMeansModule.self)) ?? NLMeansModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_nlmeans_radius"),
                    value: Double(params.radius), range: 0...4, defaultValue: 2,
                    readoutFormat: "%.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.radius, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_nlmeans")) },
                    onReset: { reset(\.radius, 2) },
                    accessibilityID: "inspector.slider.nlmeans.radius")
                LightamerSlider(
                    label: String(localized: "panel_nlmeans_strength"),
                    value: Double(params.strength), range: 0...100, defaultValue: 50,
                    readoutFormat: "%.0f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_nlmeans")) },
                    onReset: { reset(\.strength, 50) },
                    accessibilityID: "inspector.slider.nlmeans.strength")
            } header: {
                Text("panel_nlmeans_section_denoise")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_nlmeans_luma"),
                    value: Double(params.luma), range: 0...1, defaultValue: 0.5,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.luma, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_nlmeans")) },
                    onReset: { reset(\.luma, 0.5) },
                    accessibilityID: "inspector.slider.nlmeans.luma")
                LightamerSlider(
                    label: String(localized: "panel_nlmeans_chroma"),
                    value: Double(params.chroma), range: 0...1, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.chroma, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_nlmeans")) },
                    onReset: { reset(\.chroma, 1) },
                    accessibilityID: "inspector.slider.nlmeans.chroma")
            } header: {
                Text("panel_nlmeans_section_channels")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.nlmeans")
    }

    private func set(
        _ keyPath: WritableKeyPath<NLMeansModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: NLMeansModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<NLMeansModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: NLMeansModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_nlmeans"))
        }
    }
}

internal struct NLMeansPanelProvider: IOPPanelProvider {
    var opName: String { NLMeansModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(NLMeansPanelView(instance: instance, edit: edit))
    }
}
