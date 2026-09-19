import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Tone equalizer panel (Plan 03-05-T7) — the IOP-TONE-07 Inspector
// surface: the correction CURVE GRAPH (the SAME interpolation the apply
// kernel's LUT uses — CorrectionLUT.uiCurveSamples, the plan's "one code
// path, two consumers" acceptance) + the 9 EV band sliders + the
// detail-preservation controls (details / method / iterations) + the mask
// compensations (blending / feathering / quantization / boosts).
//
// Curve mapping (dt compute_lut_correction :1489-1512): the graph plots
// y = 0.5 − log2(gain)/4 over x ∈ [−8, 0] EV — gain 0.25..4 spans the
// full graph height (±2 EV compensation).
//
// D-H1 wiring: sliders are the drag-begin/tick/end trio (zero history
// during the drag, exactly ONE commit at the end); the pickers are
// discrete one-commit edits.
// ─────────────────────────────────────────────────────────────────────────

internal struct ToneEqualPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: ToneEqualModule.Params {
        PanelEditing.params(of: instance, as: ToneEqualModule.self)
            ?? ToneEqualModule.Params()
    }

    /// dt band order (noise → speculars) with the UI labels.
    private static let bands: [(String, WritableKeyPath<ToneEqualModule.Params, Float>, Float)] = [
        ("panel_toneequal_noise", \.noise, 0),
        ("panel_toneequal_ultra_deep_blacks", \.ultraDeepBlacks, 0),
        ("panel_toneequal_deep_blacks", \.deepBlacks, 0),
        ("panel_toneequal_blacks", \.blacks, 0),
        ("panel_toneequal_shadows", \.shadows, 0),
        ("panel_toneequal_midtones", \.midtones, 0),
        ("panel_toneequal_highlights", \.highlights, 0),
        ("panel_toneequal_whites", \.whites, 0),
        ("panel_toneequal_speculars", \.speculars, 0),
    ]

    var body: some View {
        Form {
            Section {
                ToneEqualCurveView(params: params)
                    .frame(height: 140)
                    .accessibilityIdentifier("inspector.toneequal.curve")
            } header: {
                Text("panel_toneequal_curve_section")
            }

            Section {
                Picker("panel_toneequal_details", selection: detailsBinding) {
                    Text("panel_toneequal_details_none").tag(ToneEqualDetails.none)
                    Text("panel_toneequal_details_averaged_guided").tag(ToneEqualDetails.averagedGuided)
                    Text("panel_toneequal_details_guided").tag(ToneEqualDetails.guided)
                    Text("panel_toneequal_details_averaged_eigf").tag(ToneEqualDetails.averagedEIGF)
                    Text("panel_toneequal_details_eigf").tag(ToneEqualDetails.eigf)
                }
                .accessibilityIdentifier("inspector.toneequal.details")
                Picker("panel_toneequal_method", selection: methodBinding) {
                    Text("panel_toneequal_method_mean").tag(ToneEqualMethod.mean)
                    Text("panel_toneequal_method_lightness").tag(ToneEqualMethod.lightness)
                    Text("panel_toneequal_method_value").tag(ToneEqualMethod.value)
                    Text("panel_toneequal_method_norm1").tag(ToneEqualMethod.norm1)
                    Text("panel_toneequal_method_norm2").tag(ToneEqualMethod.norm2)
                    Text("panel_toneequal_method_norm_power").tag(ToneEqualMethod.normPower)
                    Text("panel_toneequal_method_geomean").tag(ToneEqualMethod.geomean)
                }
                .accessibilityIdentifier("inspector.toneequal.method")
            } header: {
                Text("panel_toneequal_filter_section")
            }

            Section {
                ForEach(Self.bands, id: \.0) { band in
                    LightamerSlider(
                        label: String(localized: String.LocalizationValue(band.0)),
                        value: Double(params[keyPath: band.1]),
                        range: -2...2,
                        defaultValue: Double(band.2),
                        readoutFormat: "%+.2f",
                        unit: "EV",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { set(band.1, Float($0)) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                        onReset: { reset(band.1, band.2) },
                        accessibilityID: "inspector.slider.toneequal.\(band.0)"
                    )
                }
            } header: {
                Text("panel_toneequal_bands_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_toneequal_blending"),
                    value: Double(params.blending),
                    range: 0.01...100,
                    defaultValue: 5,
                    readoutFormat: "%.1f",
                    unit: "%",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.blending, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                    onReset: { reset(\.blending, 5) },
                    accessibilityID: "inspector.slider.toneequal.blending"
                )
                LightamerSlider(
                    label: String(localized: "panel_toneequal_iterations"),
                    value: Double(params.iterations),
                    range: 1...20,
                    defaultValue: 1,
                    readoutFormat: "%.0f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.iterations, Int($0.rounded())) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                    onReset: { reset(\.iterations, 1) },
                    accessibilityID: "inspector.slider.toneequal.iterations"
                )
                LightamerSlider(
                    label: String(localized: "panel_toneequal_feathering"),
                    value: Double(params.feathering),
                    range: 0.01...100,
                    defaultValue: 1,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.feathering, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                    onReset: { reset(\.feathering, 1) },
                    accessibilityID: "inspector.slider.toneequal.feathering"
                )
                LightamerSlider(
                    label: String(localized: "panel_toneequal_quantization"),
                    value: Double(params.quantization),
                    range: 0...2,
                    defaultValue: 0,
                    readoutFormat: "%.2f",
                    unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.quantization, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                    onReset: { reset(\.quantization, 0) },
                    accessibilityID: "inspector.slider.toneequal.quantization"
                )
            } header: {
                Text("panel_toneequal_smoothing_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_toneequal_contrast_boost"),
                    value: Double(params.contrastBoost),
                    range: -16...16,
                    defaultValue: 0,
                    readoutFormat: "%+.1f",
                    unit: "EV",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.contrastBoost, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                    onReset: { reset(\.contrastBoost, 0) },
                    accessibilityID: "inspector.slider.toneequal.contrast_boost"
                )
                LightamerSlider(
                    label: String(localized: "panel_toneequal_exposure_boost"),
                    value: Double(params.exposureBoost),
                    range: -16...16,
                    defaultValue: 0,
                    readoutFormat: "%+.1f",
                    unit: "EV",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.exposureBoost, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_toneequal")) },
                    onReset: { reset(\.exposureBoost, 0) },
                    accessibilityID: "inspector.slider.toneequal.exposure_boost"
                )
            } header: {
                Text("panel_toneequal_mask_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.toneequal")
    }

    private func set(_ keyPath: WritableKeyPath<ToneEqualModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ToneEqualModule.self) {
            edit.update(record)
        }
    }

    private func set(_ keyPath: WritableKeyPath<ToneEqualModule.Params, Int>, _ v: Int) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ToneEqualModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<ToneEqualModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func reset(_ keyPath: WritableKeyPath<ToneEqualModule.Params, Int>, _ v: Int) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: ToneEqualModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: ToneEqualModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_toneequal"))
        }
    }

    private var detailsBinding: Binding<ToneEqualDetails> {
        Binding(
            get: { params.details },
            set: { newMode in
                var p = params
                p.details = newMode
                applyDiscrete(p)
            }
        )
    }

    private var methodBinding: Binding<ToneEqualMethod> {
        Binding(
            get: { params.method },
            set: { newMode in
                var p = params
                p.method = newMode
                applyDiscrete(p)
            }
        )
    }
}

/// The correction-curve graph — the SAME interpolation as the apply
/// kernel's LUT (CorrectionLUT.uiCurveSamples on the weights derived from
/// the CURRENT params). y = 0.5 − log2(gain)/4 (dt :1505-1508): the
/// ±2 EV compensation range fills the graph; the band handles mark the 9
/// user controls.
internal struct ToneEqualCurveView: View {

    let params: ToneEqualModule.Params

    var body: some View {
        Canvas { context, size in
            let sigma = params.smoothing
            guard let weights = CorrectionLUT.weights(bands: params.bands, sigma: sigma) else {
                return
            }
            let samples = CorrectionLUT.uiCurveSamples(
                weights: weights, sigma: sigma, samples: 256)

            func point(_ ev: Float, _ gain: Float) -> CGPoint {
                let x = size.width * CGFloat(ev + 8.0) / 8.0
                let y = size.height * CGFloat(0.5 - log2f(gain) / 4.0)
                return CGPoint(x: x, y: y)
            }

            // Midline + the ±1 EV gridlines.
            var grid = Path()
            for fraction in [0.25, 0.5, 0.75] {
                grid.move(to: CGPoint(x: 0, y: size.height * CGFloat(fraction)))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(fraction)))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

            var curve = Path()
            for (index, sample) in samples.enumerated() {
                let p = point(sample.ev, sample.gain)
                if index == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            context.stroke(curve, with: .color(.accentColor), lineWidth: 1.5)

            // The band handles (the 9 user gains, EV axis).
            let gainsEV = CorrectionLUT.channelGainsEV(weights: weights, sigma: sigma)
            var handles = Path()
            for (index, center) in CorrectionLUT.centersParams.enumerated() {
                let p = point(center, exp2f(gainsEV[index]))
                handles.addEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            }
            context.fill(handles, with: .color(.accentColor))
        }
    }
}

internal struct ToneEqualPanelProvider: IOPPanelProvider {
    var opName: String { ToneEqualModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ToneEqualPanelView(instance: instance, edit: edit))
    }
}
