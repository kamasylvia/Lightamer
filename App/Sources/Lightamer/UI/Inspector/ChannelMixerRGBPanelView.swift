import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// ChannelMixerRGB panel (Plan 05-03-T5, IOP-COLOR-02) — the Inspector
// surface for dt `channelmixerrgb` ("color calibration"): 3 output
// channels × 3 gain sliders + normalize toggles + saturation/lightness/
// grey groups + the illuminant zone (D/F/LED/blackbody/custom/camera
// Picker + per-family sub-Picker or x/y/temperature inputs + adaptation
// Picker + gamut + clip).
//
// COLOR-CHECKER ZONE (D-05-CONTEXT-5): v1 HIDES the profile/spot-mapping
// UI entirely — the params carry no color-checker fields (detection
// illuminants resolve nil and the panel disables them with a note).
// Values READ from the instance record. D-H1 trio on all sliders;
// Pickers/Toggles/resets = applyDiscrete one-commit. 280pt Inspector
// constraint: sliders full-width, pickers compact.
// ─────────────────────────────────────────────────────────────────────────

internal struct ChannelMixerRGBPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: ChannelMixerRGBModule.Params {
        (try? instance.params(of: ChannelMixerRGBModule.self)) ?? ChannelMixerRGBModule.Params()
    }

    var body: some View {
        Form {
            mixSection(
                title: String(localized: "panel_cmr_red"), row: params.red,
                set: { setChannel(0, $0) }, idPrefix: "red")
            mixSection(
                title: String(localized: "panel_cmr_green"), row: params.green,
                set: { setChannel(1, $0) }, idPrefix: "green")
            mixSection(
                title: String(localized: "panel_cmr_blue"), row: params.blue,
                set: { setChannel(2, $0) }, idPrefix: "blue")
            Section {
                Toggle(String(localized: "panel_cmr_normalize_r"),
                       isOn: discreteBinding(\.normalizeR))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.normalize_r")
                Toggle(String(localized: "panel_cmr_normalize_g"),
                       isOn: discreteBinding(\.normalizeG))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.normalize_g")
                Toggle(String(localized: "panel_cmr_normalize_b"),
                       isOn: discreteBinding(\.normalizeB))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.normalize_b")
            } header: {
                Text("panel_cmr_normalize_section")
            }
            Section {
                gainRow(title: String(localized: "panel_cmr_sat_r"), value: params.saturation.x,
                        range: -2...2, set: { setSat(0, $0) },
                        reset: { setSat(0, 0) }, id: "sat_r")
                gainRow(title: String(localized: "panel_cmr_sat_g"), value: params.saturation.y,
                        range: -2...2, set: { setSat(1, $0) },
                        reset: { setSat(1, 0) }, id: "sat_g")
                gainRow(title: String(localized: "panel_cmr_sat_b"), value: params.saturation.z,
                        range: -2...2, set: { setSat(2, $0) },
                        reset: { setSat(2, 0) }, id: "sat_b")
                Toggle(String(localized: "panel_cmr_normalize_sat"),
                       isOn: discreteBinding(\.normalizeSat))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.normalize_sat")
            } header: {
                Text("panel_cmr_saturation_section")
            }
            Section {
                gainRow(title: String(localized: "panel_cmr_light_r"), value: params.lightness.x,
                        range: -2...2, set: { setLight(0, $0) },
                        reset: { setLight(0, 0) }, id: "light_r")
                gainRow(title: String(localized: "panel_cmr_light_g"), value: params.lightness.y,
                        range: -2...2, set: { setLight(1, $0) },
                        reset: { setLight(1, 0) }, id: "light_g")
                gainRow(title: String(localized: "panel_cmr_light_b"), value: params.lightness.z,
                        range: -2...2, set: { setLight(2, $0) },
                        reset: { setLight(2, 0) }, id: "light_b")
                Toggle(String(localized: "panel_cmr_normalize_light"),
                       isOn: discreteBinding(\.normalizeLight))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.normalize_light")
            } header: {
                Text("panel_cmr_lightness_section")
            }
            Section {
                gainRow(title: String(localized: "panel_cmr_grey_r"), value: params.grey.x,
                        range: -2...2, set: { setGrey(0, $0) },
                        reset: { setGrey(0, 0) }, id: "grey_r")
                gainRow(title: String(localized: "panel_cmr_grey_g"), value: params.grey.y,
                        range: -2...2, set: { setGrey(1, $0) },
                        reset: { setGrey(1, 0) }, id: "grey_g")
                gainRow(title: String(localized: "panel_cmr_grey_b"), value: params.grey.z,
                        range: -2...2, set: { setGrey(2, $0) },
                        reset: { setGrey(2, 0) }, id: "grey_b")
                Toggle(String(localized: "panel_cmr_normalize_grey"),
                       isOn: discreteBinding(\.normalizeGrey))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.normalize_grey")
            } header: {
                Text("panel_cmr_grey_section")
            }
            illuminantSection
            Section {
                Picker(String(localized: "panel_cmr_adaptation"), selection: adaptationBinding) {
                    Text("panel_cmr_adapt_bradford_linear").tag(ChannelMixerAdaptation.linearBradford)
                    Text("panel_cmr_adapt_cat16").tag(ChannelMixerAdaptation.cat16)
                    Text("panel_cmr_adapt_bradford_full").tag(ChannelMixerAdaptation.fullBradford)
                    Text("panel_cmr_adapt_xyz").tag(ChannelMixerAdaptation.xyz)
                    Text("panel_cmr_adapt_rgb").tag(ChannelMixerAdaptation.rgb)
                }
                .accessibilityIdentifier("inspector.picker.channelmixerrgb.adaptation")
                LightamerSlider(
                    label: String(localized: "panel_cmr_gamut"),
                    value: Double(params.gamut), range: 0...12, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { setScalar(\.gamut, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixerrgb")) },
                    onReset: { resetScalar(\.gamut, 1) },
                    accessibilityID: "inspector.slider.channelmixerrgb.gamut")
                Toggle(String(localized: "panel_cmr_clip"),
                       isOn: discreteBinding(\.clip))
                    .accessibilityIdentifier("inspector.toggle.channelmixerrgb.clip")
                Picker(String(localized: "panel_cmr_version"), selection: versionBinding) {
                    Text("panel_cmr_version_1").tag(ChannelMixerVersion.v1)
                    Text("panel_cmr_version_2").tag(ChannelMixerVersion.v2)
                    Text("panel_cmr_version_3").tag(ChannelMixerVersion.v3)
                }
                .accessibilityIdentifier("inspector.picker.channelmixerrgb.version")
            } header: {
                Text("panel_cmr_output_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.channelmixerrgb")
    }

    // MARK: - Mix rows

    private func mixSection(
        title: String, row: SIMD4<Float>,
        set: @escaping ((Int, Float)) -> Void, idPrefix: String
    ) -> some View {
        // dt defaults: diagonal 1 for the channel's own row, else 0.
        let defaults: (Float, Float, Float) =
            idPrefix == "red" ? (1, 0, 0)
            : idPrefix == "green" ? (0, 1, 0) : (0, 0, 1)
        return Section {
            gainRow(title: title, value: row.x, range: -2...2,
                    set: { set((0, $0)) }, reset: { set((0, defaults.0)) },
                    id: "\(idPrefix)_r", defaultValue: Double(defaults.0))
            gainRow(title: title, value: row.y, range: -2...2,
                    set: { set((1, $0)) }, reset: { set((1, defaults.1)) },
                    id: "\(idPrefix)_g", defaultValue: Double(defaults.1))
            gainRow(title: title, value: row.z, range: -2...2,
                    set: { set((2, $0)) }, reset: { set((2, defaults.2)) },
                    id: "\(idPrefix)_b", defaultValue: Double(defaults.2))
        } header: {
            Text(title)
        }
    }

    private func gainRow(
        title: String, value: Float, range: ClosedRange<Double>,
        set: @escaping (Float) -> Void, reset: @escaping () -> Void, id: String,
        defaultValue: Double = 0
    ) -> some View {
        LightamerSlider(
            label: title,
            value: Double(value), range: range, defaultValue: defaultValue,
            readoutFormat: "%+.2f", unit: "",
            onDragBegin: { edit.beginEditing() },
            onChange: { set(Float($0)) },
            onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixerrgb")) },
            onReset: reset,
            accessibilityID: "inspector.slider.channelmixerrgb.\(id)")
    }

    // MARK: - Illuminant zone

    private var illuminantSection: some View {
        Section {
            Picker(String(localized: "panel_cmr_illuminant"), selection: illuminantBinding) {
                Text("panel_cmr_illum_pipe").tag(ChannelMixerIlluminant.pipe)
                Text("panel_cmr_illum_a").tag(ChannelMixerIlluminant.a)
                Text("panel_cmr_illum_d").tag(ChannelMixerIlluminant.d)
                Text("panel_cmr_illum_e").tag(ChannelMixerIlluminant.e)
                Text("panel_cmr_illum_f").tag(ChannelMixerIlluminant.f)
                Text("panel_cmr_illum_led").tag(ChannelMixerIlluminant.led)
                Text("panel_cmr_illum_bb").tag(ChannelMixerIlluminant.blackbody)
                Text("panel_cmr_illum_custom").tag(ChannelMixerIlluminant.custom)
                Text("panel_cmr_illum_camera").tag(ChannelMixerIlluminant.camera)
            }
            .accessibilityIdentifier("inspector.picker.channelmixerrgb.illuminant")
            if params.illuminant == .f {
                Picker(String(localized: "panel_cmr_fluo"), selection: fluoBinding) {
                    ForEach(0..<12, id: \.self) { i in
                        Text("F\(i + 1)").tag(ChannelMixerFluo(rawValue: i)!)
                    }
                }
                .accessibilityIdentifier("inspector.picker.channelmixerrgb.fluo")
            }
            if params.illuminant == .led {
                Picker(String(localized: "panel_cmr_led"), selection: ledBinding) {
                    Text("panel_cmr_led_b1").tag(ChannelMixerLED.b1)
                    Text("panel_cmr_led_b2").tag(ChannelMixerLED.b2)
                    Text("panel_cmr_led_b3").tag(ChannelMixerLED.b3)
                    Text("panel_cmr_led_b4").tag(ChannelMixerLED.b4)
                    Text("panel_cmr_led_b5").tag(ChannelMixerLED.b5)
                    Text("panel_cmr_led_bh1").tag(ChannelMixerLED.bh1)
                    Text("panel_cmr_led_rgb1").tag(ChannelMixerLED.rgb1)
                    Text("panel_cmr_led_v1").tag(ChannelMixerLED.v1)
                    Text("panel_cmr_led_v2").tag(ChannelMixerLED.v2)
                }
                .accessibilityIdentifier("inspector.picker.channelmixerrgb.led")
            }
            if params.illuminant == .d || params.illuminant == .blackbody
                || params.illuminant == .camera
            {
                LightamerSlider(
                    label: String(localized: "panel_cmr_temperature"),
                    value: Double(params.temperature), range: 1667...25000,
                    defaultValue: 5003,
                    readoutFormat: "%.0f", unit: "K",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { setScalar(\.temperature, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixerrgb")) },
                    onReset: { resetScalar(\.temperature, 5003) },
                    accessibilityID: "inspector.slider.channelmixerrgb.temperature")
            }
            if params.illuminant == .custom || params.illuminant == .camera {
                LightamerSlider(
                    label: String(localized: "panel_cmr_x"),
                    value: Double(params.x), range: 0...0.8, defaultValue: 0.333,
                    readoutFormat: "%.4f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { setScalar(\.x, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixerrgb")) },
                    onReset: { resetScalar(\.x, 0.333) },
                    accessibilityID: "inspector.slider.channelmixerrgb.x")
                LightamerSlider(
                    label: String(localized: "panel_cmr_y"),
                    value: Double(params.y), range: 0...0.8, defaultValue: 0.333,
                    readoutFormat: "%.4f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { setScalar(\.y, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_channelmixerrgb")) },
                    onReset: { resetScalar(\.y, 0.333) },
                    accessibilityID: "inspector.slider.channelmixerrgb.y")
            }
            if params.illuminant == .camera {
                // Divergence #1 note: commit-time daylight fallback.
                Text("panel_cmr_camera_note")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
            // v1 hides the color-checker profiling zone (D-05-CONTEXT-5).
            Text("panel_cmr_noprofile_note")
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
                .accessibilityIdentifier("inspector.note.channelmixerrgb.noprofile")
        } header: {
            Text("panel_cmr_illuminant_section")
        }
    }

    // MARK: - Mutations

    private func setChannel(_ channel: Int, _ component: (Int, Float)) {
        var p = params
        let (i, v) = component
        if channel == 0 { var r = p.red; r[i] = v; p.red = r }
        else if channel == 1 { var g = p.green; g[i] = v; p.green = g }
        else { var b = p.blue; b[i] = v; p.blue = b }
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
            edit.update(record)
        }
    }

    private func setSat(_ i: Int, _ v: Float) {
        var p = params
        var s = p.saturation; s[i] = v; p.saturation = s
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
            edit.update(record)
        }
    }

    private func setLight(_ i: Int, _ v: Float) {
        var p = params
        var l = p.lightness; l[i] = v; p.lightness = l
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
            edit.update(record)
        }
    }

    private func setGrey(_ i: Int, _ v: Float) {
        var p = params
        var g = p.grey; g[i] = v; p.grey = g
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
            edit.update(record)
        }
    }

    private func setScalar(_ keyPath: WritableKeyPath<ChannelMixerRGBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
            edit.update(record)
        }
    }

    private func resetScalar(_ keyPath: WritableKeyPath<ChannelMixerRGBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
        }
    }

    private func discreteBinding(_ keyPath: WritableKeyPath<ChannelMixerRGBModule.Params, Bool>) -> Binding<Bool> {
        Binding(
            get: { params[keyPath: keyPath] },
            set: { v in
                var p = params
                p[keyPath: keyPath] = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
                }
            })
    }

    private var illuminantBinding: Binding<ChannelMixerIlluminant> {
        Binding(
            get: { params.illuminant },
            set: { v in
                var p = params
                p.illuminant = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
                }
            })
    }

    private var fluoBinding: Binding<ChannelMixerFluo> {
        Binding(
            get: { params.illumFluo },
            set: { v in
                var p = params
                p.illumFluo = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
                }
            })
    }

    private var ledBinding: Binding<ChannelMixerLED> {
        Binding(
            get: { params.illumLED },
            set: { v in
                var p = params
                p.illumLED = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
                }
            })
    }

    private var adaptationBinding: Binding<ChannelMixerAdaptation> {
        Binding(
            get: { params.adaptation },
            set: { v in
                var p = params
                p.adaptation = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
                }
            })
    }

    private var versionBinding: Binding<ChannelMixerVersion> {
        Binding(
            get: { params.version },
            set: { v in
                var p = params
                p.version = v
                if let record = PanelEditing.updated(instance, params: p, as: ChannelMixerRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_channelmixerrgb"))
                }
            })
    }
}

internal struct ChannelMixerRGBPanelProvider: IOPPanelProvider {
    var opName: String { ChannelMixerRGBModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ChannelMixerRGBPanelView(instance: instance, edit: edit))
    }
}
