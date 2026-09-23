import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// DenoiseProfile panel (Plan 05-07-T6, IOP-DENOISE-01) — the Inspector
// surface for dt `denoiseprofile` ("denoise (profiled)"):
//   - mode Picker: NLMeans / Wavelets / NLMeans(Auto) / Wavelets(Auto);
//     VARIANCE listed DISABLED with the v1-scope note (D-05-CONTEXT-3).
//   - profile row: Auto(EXIF) / Manual ISO / Generic (dt reload_defaults
//     semantics — the a[0] == −1 sentinel resolves at load; the panel
//     surfaces what the params record carries, DECISIONS D-05-07-T6-2).
//   - 7 sliders (radius / nbhood / strength / shadows / bias / scattering
//     / central weight — dt gui ranges; interactive extents pinned in
//     DECISIONS D-05-07-T6-1, the hard maxima stay programmatic).
//   - Y0U0V0 | RGB color-mode Picker (wavelets only).
//   - the 7-band force curves (ALL / Y0U0V0 tabs — the wavelets channel
//     rows dt exposes; Canvas via DenoiseProfileModule.forceCurveSamples,
//     CorrectionLUT 同源模式).
//
// D-H1 wiring: LightamerSlider trio (exactly ONE history commit per drag)
// + applyDiscrete one-commit resets/picker flips. 280pt constraint
// (MonochromePanelView precedent). zh/en catalog + a11y IDs throughout.
// ─────────────────────────────────────────────────────────────────────────

internal struct DenoiseProfilePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var forceTab: ForceTab = .all
    @State private var manualISO: Double = 400

    internal enum ForceTab: String, CaseIterable, Identifiable {
        case all, y0u0v0
        var id: String { rawValue }
    }

    /// Profile handling derived from the params record: the a[0] == −1
    /// sentinel ⇒ Auto (commit re-resolves via the load-time store match);
    /// generic = the dt 1e-4 concrete; otherwise Manual ISO drives the
    /// auto resolution via `isoOverride`.
    private enum ProfileMode: String, CaseIterable, Identifiable {
        case autoExif, manual, generic
        var id: String { rawValue }
    }

    private var params: DenoiseProfileModule.Params {
        (try? instance.params(of: DenoiseProfileModule.self))
            ?? DenoiseProfileModule.Params()
    }

    private var profileMode: ProfileMode {
        if params.a.x < 0 { return .autoExif }
        if params.isoOverride != nil { return .manual }
        if params.a == SIMD3(repeating: 1e-4), params.b == SIMD3(repeating: 0) {
            return .generic
        }
        return .manual
    }

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "panel_dp_mode"),
                    selection: modeBinding
                ) {
                    Text("panel_dp_mode_nlmeans").tag(DenoiseProfileModule.Mode.nlmeans)
                    Text("panel_dp_mode_wavelets").tag(DenoiseProfileModule.Mode.wavelets)
                    Text("panel_dp_mode_variance")
                        .tag(DenoiseProfileModule.Mode.variance)
                        .disabled(true)
                    Text("panel_dp_mode_nlmeans_auto").tag(DenoiseProfileModule.Mode.nlmeansAuto)
                    Text("panel_dp_mode_wavelets_auto").tag(DenoiseProfileModule.Mode.waveletsAuto)
                }
                .pickerStyle(.menu)
                Text("panel_dp_mode_variance_note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("panel_dp_section_mode")
            }

            Section {
                Picker(
                    String(localized: "panel_dp_profile"),
                    selection: profileBinding
                ) {
                    Text("panel_dp_profile_auto").tag(ProfileMode.autoExif)
                    Text("panel_dp_profile_manual").tag(ProfileMode.manual)
                    Text("panel_dp_profile_generic").tag(ProfileMode.generic)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("inspector.picker.dp.profile")
                if profileMode == .manual {
                    LightamerSlider(
                        label: String(localized: "panel_dp_profile_iso"),
                        value: Double(params.isoOverride ?? manualISO),
                        range: 50...25600, defaultValue: 400,
                        readoutFormat: "%.0f", unit: "",
                        onDragBegin: { edit.beginEditing() },
                        onChange: { manualISO = $0; setISO($0) },
                        onDragEnd: {
                            edit.endEditing(
                                label: String(localized: "history_denoiseprofile"))
                        },
                        onReset: { setISO(400) },
                        accessibilityID: "inspector.slider.dp.iso")
                }
                LabeledContent {
                    Text(profileValueString).monospacedDigit()
                } label: {
                    Text("panel_dp_profile_summary")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("panel_dp_section_profile")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_dp_radius"),
                    value: Double(params.radius), range: 1...8, defaultValue: 1,
                    readoutFormat: "%.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.radius, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.radius, 1) },
                    accessibilityID: "inspector.slider.dp.radius")
                LightamerSlider(
                    label: String(localized: "panel_dp_nbhood"),
                    value: Double(params.nbhood), range: 1...15, defaultValue: 7,
                    readoutFormat: "%.0f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.nbhood, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.nbhood, 7) },
                    accessibilityID: "inspector.slider.dp.nbhood")
                LightamerSlider(
                    label: String(localized: "panel_dp_strength"),
                    value: Double(params.strength), range: 0...10, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.strength, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.strength, 1) },
                    accessibilityID: "inspector.slider.dp.strength")
                LightamerSlider(
                    label: String(localized: "panel_dp_shadows"),
                    value: Double(params.shadows), range: 0...1.8, defaultValue: 1,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.shadows, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.shadows, 1) },
                    accessibilityID: "inspector.slider.dp.shadows")
                LightamerSlider(
                    label: String(localized: "panel_dp_bias"),
                    value: Double(params.bias), range: -10...2, defaultValue: 0,
                    readoutFormat: "%.1f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.bias, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.bias, 0) },
                    accessibilityID: "inspector.slider.dp.bias")
                LightamerSlider(
                    label: String(localized: "panel_dp_scattering"),
                    value: Double(params.scattering), range: 0...3, defaultValue: 0,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.scattering, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.scattering, 0) },
                    accessibilityID: "inspector.slider.dp.scattering")
                LightamerSlider(
                    label: String(localized: "panel_dp_central"),
                    value: Double(params.centralPixelWeight), range: 0...2,
                    defaultValue: 0.1, readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.centralPixelWeight, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(
                            label: String(localized: "history_denoiseprofile"))
                    },
                    onReset: { reset(\.centralPixelWeight, 0.1) },
                    accessibilityID: "inspector.slider.dp.central")
            } header: {
                Text("panel_dp_section_denoise")
            }

            Section {
                Picker(
                    String(localized: "panel_dp_colormode"),
                    selection: colorModeBinding
                ) {
                    Text("panel_dp_colormode_y0u0v0")
                        .tag(DenoiseProfileModule.WaveletColorMode.y0u0v0)
                    Text("panel_dp_colormode_rgb")
                        .tag(DenoiseProfileModule.WaveletColorMode.rgb)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.picker.dp.colormode")
                Picker(
                    String(localized: "panel_dp_force_tab"),
                    selection: $forceTab
                ) {
                    Text("panel_dp_force_all").tag(ForceTab.all)
                    Text("panel_dp_force_y0u0v0").tag(ForceTab.y0u0v0)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.picker.dp.forcetab")
                ForceCurveView(
                    yRow: forceTab == .all ? params.y[0] : params.y[4],
                    uvRow: forceTab == .all ? nil : params.y[5]
                )
                .frame(height: 96)
                .accessibilityIdentifier("inspector.canvas.dp.force")
            } header: {
                Text("panel_dp_section_force")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.denoiseprofile")
    }

    // MARK: - bindings

    private var modeBinding: Binding<DenoiseProfileModule.Mode> {
        Binding(
            get: { params.mode },
            set: { newMode in
                var p = params
                p.mode = newMode
                applyDiscrete(p)
            }
        )
    }

    private var colorModeBinding: Binding<DenoiseProfileModule.WaveletColorMode> {
        Binding(
            get: { params.waveletColorMode },
            set: { newMode in
                var p = params
                p.waveletColorMode = newMode
                applyDiscrete(p)
            }
        )
    }

    private var profileBinding: Binding<ProfileMode> {
        Binding(
            get: { profileMode },
            set: { newMode in
                var p = params
                switch newMode {
                case .autoExif:
                    p.isoOverride = nil
                    // Re-arm the sentinel if concrete values were showing;
                    // commit re-resolves (dt :2698-2700).
                    p.a.x = -1
                case .manual:
                    p.a.x = params.a.x < 0 ? abs(params.a.x) : params.a.x
                    p.isoOverride = manualISO
                case .generic:
                    p.a = SIMD3(repeating: 1e-4)
                    p.b = SIMD3(repeating: 0)
                    p.isoOverride = nil
                }
                applyDiscrete(p)
            }
        )
    }

    private var profileValueString: String {
        if params.a.x < 0 {
            return String(
                format: "ISO·EXIF  a₁ %.3g  b₁ %.3g", params.a.y, params.b.y)
        }
        if let iso = params.isoOverride {
            return String(
                format: "ISO %.0f  a₁ %.3g  b₁ %.3g", iso, params.a.y, params.b.y)
        }
        return String(format: "a₁ %.3g", params.a.y)
    }

    // MARK: - editing helpers (D-H1)

    private func set(
        _ keyPath: WritableKeyPath<DenoiseProfileModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(
            instance, params: p, as: DenoiseProfileModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<DenoiseProfileModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func setISO(_ v: Double) {
        var p = params
        if p.a.x < 0 { p.a.x = abs(p.a.x) }
        p.isoOverride = v
        if let record = PanelEditing.updated(
            instance, params: p, as: DenoiseProfileModule.self) {
            edit.update(record)
        }
    }

    private func applyDiscrete(_ p: DenoiseProfileModule.Params) {
        if let record = PanelEditing.updated(
            instance, params: p, as: DenoiseProfileModule.self) {
            edit.applyDiscrete(
                record, label: String(localized: "history_denoiseprofile"))
        }
    }
}

/// One force curve graph — the anchors are the QUANTIZED values the
/// kernel consumes (`forceRow`), the polyline the SAME Catmull-Rom
/// evaluated at 64 samples (`forceCurveSamples`). In the Y0U0V0 tab the
/// U0V0 row rides dashed over the Y0 row.
internal struct ForceCurveView: View {

    let yRow: [Float]
    let uvRow: [Float]?

    var body: some View {
        Canvas { context, size in
            func point(_ x: Float, _ y: Float) -> CGPoint {
                CGPoint(
                    x: size.width * CGFloat(x),
                    y: size.height * CGFloat(1 - max(0, min(1, y))))
            }

            var grid = Path()
            for fraction in [0.25, 0.5, 0.75] {
                grid.move(to: CGPoint(x: 0, y: size.height * CGFloat(fraction)))
                grid.addLine(
                    to: CGPoint(x: size.width, y: size.height * CGFloat(fraction)))
            }
            context.stroke(
                grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

            var curve = Path()
            for (index, sample) in DenoiseProfileModule.forceCurveSamples(
                yRow: yRow).enumerated() {
                let p = point(sample.x, sample.y)
                if index == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            context.stroke(curve, with: .color(.accentColor), lineWidth: 1.5)

            if let uvRow {
                var uv = Path()
                for (index, sample) in DenoiseProfileModule.forceCurveSamples(
                    yRow: uvRow).enumerated() {
                    let p = point(sample.x, sample.y)
                    if index == 0 { uv.move(to: p) } else { uv.addLine(to: p) }
                }
                context.stroke(
                    uv, with: .color(.secondary), style: StrokeStyle(
                        lineWidth: 1.2, dash: [3, 2]))
            }

            // The 7 quantized anchor handles (band 0…6 on the k/6 grid).
            let anchors = DenoiseProfileModule.forceRow(yRow)
            var handles = Path()
            for (band, value) in anchors.enumerated() {
                let p = point(Float(band) / 6.0, value)
                handles.addEllipse(
                    in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            }
            context.fill(handles, with: .color(.accentColor))
        }
    }
}

internal struct DenoiseProfilePanelProvider: IOPPanelProvider {
    var opName: String { DenoiseProfileModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(DenoiseProfilePanelView(instance: instance, edit: edit))
    }
}
