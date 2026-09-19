import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Exposure panel (Plan 03-02-T4) — the FIRST D-H1 consumer. Two sliders
// (exposure EV ∈ [−18, 18], black ∈ [−1, 1]) + the mode bit shown disabled
// (deflicker is divergence #2 — the params round-trip but the mode is not
// implemented).
//
// Every drag maps onto the trio: begin → update (0 history) → end (exactly
// one HistoryItem). Values READ from the instance record; double-click
// resets to the identity default through the compressed discrete trio.
// ─────────────────────────────────────────────────────────────────────────
internal struct ExposurePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    /// The current params (decoded once per body evaluation; the record is
    /// the source of truth — after each commit the record changes identity
    /// and the view re-reads).
    private var params: ExposureModule.Params {
        PanelEditing.params(of: instance, as: ExposureModule.self)
            ?? ExposureModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_exposure_exposure"),
                    value: Double(params.exposure),
                    range: -18...18,
                    defaultValue: 0,
                    readoutFormat: "%+.2f",
                    unit: " EV",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { newValue in setExposure(Float(newValue)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_exposure")) },
                    onReset: { reset(\.exposure, to: 0) },
                    accessibilityID: "inspector.slider.exposure.exposure"
                )
                LightamerSlider(
                    label: String(localized: "panel_exposure_black"),
                    value: Double(params.black),
                    range: -1...(1 - 1e-6), // dt GUI domain: black < 1 keeps scale finite
                    defaultValue: 0,
                    readoutFormat: "%+.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { newValue in setBlack(Float(newValue)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_exposure")) },
                    onReset: { reset(\.black, to: 0) },
                    accessibilityID: "inspector.slider.exposure.black"
                )
            } header: {
                Text("panel_exposure_section")
            }

            Section {
                Picker("panel_exposure_mode", selection: modeBinding) {
                    Text("panel_exposure_mode_manual").tag(ExposureModule.Mode.manual)
                    Text("panel_exposure_mode_deflicker").tag(ExposureModule.Mode.deflicker)
                }
                .disabled(true) // deflicker NOT implemented (module divergence #2)
                .accessibilityIdentifier("inspector.exposure.mode")
                Text("panel_exposure_mode_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            } header: {
                Text("panel_exposure_mode_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.exposure")
    }

    /// The mode bit round-trips; flipping it is a discrete one-commit edit
    /// (disabled in v1 — the binding exists for the params round-trip).
    private var modeBinding: Binding<ExposureModule.Mode> {
        Binding(
            get: { params.mode },
            set: { newMode in
                var p = params
                p.mode = newMode
                applyDiscrete(p)
            }
        )
    }

    private func setExposure(_ value: Float) {
        var p = params
        p.exposure = value
        update(p)
    }

    private func setBlack(_ value: Float) {
        var p = params
        p.black = value
        update(p)
    }

    private func reset(_ keyPath: WritableKeyPath<ExposureModule.Params, Float>, to value: Float) {
        var p = params
        p[keyPath: keyPath] = value
        applyDiscrete(p)
    }

    private func update(_ p: ExposureModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: ExposureModule.self) {
            edit.update(record)
        }
    }

    private func applyDiscrete(_ p: ExposureModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: ExposureModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_exposure"))
        }
    }
}

/// The exposure panel factory (registered in `InspectorState
/// .registerDefaultProviders`).
internal struct ExposurePanelProvider: IOPPanelProvider {
    var opName: String { ExposureModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ExposurePanelView(instance: instance, edit: edit))
    }
}
