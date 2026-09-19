import LightamerCore
import LightamerIOP
import SwiftUI
import simd

// ─────────────────────────────────────────────────────────────────────────
// Temperature / WB panel (Plan 03-02-T4, IOP-TONE-02) — three channel-gain
// sliders (the PERSISTED truth, dt temperature.c params semantics) + the
// Kelvin/tint DERIVED display pair + the preset picker + the D-T4 eyedropper
// button.
//
// Kelvin/tint semantics (module header divergences #1/#2): gains → K/tint
// through `WhiteBalanceMath.gainsToKelvinTint` (dt `_mul2temp` isomorphic);
// dragging the Kelvin or tint sliders re-derives gains through
// `WhiteBalanceMath.kelvinTintToGains` (Rec2020-native). The eyedropper
// arms the viewport mode; the picked linear Rec2020 color neutralizes via
// `gainsFromPicked` (dt temperature.c:1933-1955 verbatim) and lands as ONE
// discrete commit.
// ─────────────────────────────────────────────────────────────────────────
internal struct TemperaturePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @Environment(InspectorState.self) private var inspectorState

    private var params: TemperatureModule.Params {
        PanelEditing.params(of: instance, as: TemperatureModule.self)
            ?? TemperatureModule.Params()
    }

    /// Kelvin/tint derived from the persisted gains (dt `_mul2temp`).
    private var derived: (kelvin: Double, tint: Double) {
        WhiteBalanceMath.gainsToKelvinTint(gains: SIMD3<Double>(params.gains))
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_wb_kelvin"),
                    value: derived.kelvin,
                    range: WhiteBalanceMath.lowestKelvin...WhiteBalanceMath.highestKelvin,
                    defaultValue: WhiteBalanceMath.d65Kelvin,
                    readoutFormat: "%.0f",
                    unit: " K",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { k in setKelvinTint(kelvin: k, tint: derived.tint) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_wb")) },
                    onReset: { applyGains(SIMD3<Float>(repeating: 1), preset: .d65) },
                    accessibilityID: "inspector.slider.temperature.kelvin"
                )
                LightamerSlider(
                    label: String(localized: "panel_wb_tint"),
                    value: derived.tint,
                    range: WhiteBalanceMath.lowestTint...WhiteBalanceMath.highestTint,
                    defaultValue: 1,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { t in setKelvinTint(kelvin: derived.kelvin, tint: t) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_wb")) },
                    onReset: { resetTint() },
                    accessibilityID: "inspector.slider.temperature.tint"
                )
            } header: {
                Text("panel_wb_temperature_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_wb_red"),
                    value: Double(params.red),
                    range: 0...8,
                    defaultValue: 1,
                    onDragBegin: { edit.beginEditing() },
                    onChange: { v in setGain(\.red, v) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_wb")) },
                    onReset: { resetGain(\.red) },
                    accessibilityID: "inspector.slider.temperature.red"
                )
                LightamerSlider(
                    label: String(localized: "panel_wb_green"),
                    value: Double(params.green),
                    range: 0...8,
                    defaultValue: 1,
                    onDragBegin: { edit.beginEditing() },
                    onChange: { v in setGain(\.green, v) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_wb")) },
                    onReset: { resetGain(\.green) },
                    accessibilityID: "inspector.slider.temperature.green"
                )
                LightamerSlider(
                    label: String(localized: "panel_wb_blue"),
                    value: Double(params.blue),
                    range: 0...8,
                    defaultValue: 1,
                    onDragBegin: { edit.beginEditing() },
                    onChange: { v in setGain(\.blue, v) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_wb")) },
                    onReset: { resetGain(\.blue) },
                    accessibilityID: "inspector.slider.temperature.blue"
                )
            } header: {
                Text("panel_wb_gains_section")
            }

            Section {
                Picker("panel_wb_preset", selection: presetBinding) {
                    Text("panel_wb_preset_asshot").tag(TemperatureModule.Preset.asShot)
                    Text("panel_wb_preset_spot").tag(TemperatureModule.Preset.spot)
                    Text("panel_wb_preset_user").tag(TemperatureModule.Preset.user)
                    Text("panel_wb_preset_d65").tag(TemperatureModule.Preset.d65)
                    Text("panel_wb_preset_d65late").tag(TemperatureModule.Preset.d65Late)
                }
                .accessibilityIdentifier("inspector.temperature.preset")

                Button {
                    armEyedropper()
                } label: {
                    Label(
                        String(localized: "panel_wb_pick"),
                        systemImage: "eyedropper"
                    )
                }
                .accessibilityIdentifier("inspector.temperature.eyedropper")
                .accessibilityHint(Text("panel_wb_pick_hint"))
            } header: {
                Text("panel_wb_preset_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.temperature")
    }

    // MARK: - Param updates (the trio)

    private func setGain(_ keyPath: WritableKeyPath<TemperatureModule.Params, Float>, _ value: Double) {
        var p = params
        p[keyPath: keyPath] = Float(value)
        update(p)
    }

    private func resetGain(_ keyPath: WritableKeyPath<TemperatureModule.Params, Float>) {
        var p = params
        p[keyPath: keyPath] = 1
        applyDiscrete(p)
    }

    private func resetTint() {
        setKelvinTintDiscrete(kelvin: derived.kelvin, tint: 1)
    }

    private func setKelvinTint(kelvin: Double, tint: Double) {
        let gains = WhiteBalanceMath.kelvinTintToGains(kelvin: kelvin, tint: tint)
        var p = params
        p.red = Float(gains.x)
        p.green = Float(gains.y)
        p.blue = Float(gains.z)
        update(p)
    }

    private func setKelvinTintDiscrete(kelvin: Double, tint: Double) {
        let gains = WhiteBalanceMath.kelvinTintToGains(kelvin: kelvin, tint: tint)
        var p = params
        p.red = Float(gains.x)
        p.green = Float(gains.y)
        p.blue = Float(gains.z)
        applyDiscrete(p)
    }

    private func applyGains(_ gains: SIMD3<Float>, preset: TemperatureModule.Preset) {
        var p = TemperatureModule.Params(gains: gains, preset: preset)
        p.preset = preset
        applyDiscrete(p)
    }

    private func update(_ p: TemperatureModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: TemperatureModule.self) {
            edit.update(record)
        }
    }

    private func applyDiscrete(_ p: TemperatureModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: TemperatureModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_wb"))
        }
    }

    /// The preset picker round-trips the dt bit; picking D65 additionally
    /// snaps the gains to the D65 identity (the preset's Lightamer
    /// semantic — dt's D65-late CAT deferral is channelmixerrgb territory).
    private var presetBinding: Binding<TemperatureModule.Preset> {
        Binding(
            get: { params.preset },
            set: { newPreset in
                var p = params
                p.preset = newPreset
                if newPreset == .d65 {
                    p.red = 1
                    p.green = 1
                    p.blue = 1
                }
                applyDiscrete(p)
            }
        )
    }

    // MARK: - D-T4 eyedropper

    private func armEyedropper() {
        if inspectorState.isEyedropperActive {
            inspectorState.cancelEyedropper()
            return
        }
        inspectorState.beginEyedropper { picked in
            // dt temperature.c:1933-1955 verbatim: gains = clamp(1/picked),
            // green-normalized — then ONE discrete commit (D-H1 离散控件).
            let gains = WhiteBalanceMath.gainsFromPicked(picked)
            var p = TemperatureModule.Params(gains: gains, preset: .spot)
            p.preset = .spot
            applyDiscrete(p)
        }
    }
}

/// The temperature panel factory (registered in `InspectorState
/// .registerDefaultProviders`).
internal struct TemperaturePanelProvider: IOPPanelProvider {
    var opName: String { TemperatureModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(TemperaturePanelView(instance: instance, edit: edit))
    }
}
