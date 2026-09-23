import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// ColorZones panel (Plan 05-04-T4, IOP-COLOR-05) — the Inspector surface
// for dt `colorzones`: L/C/h three-tab curve editor (CurveEditorView
// reuse — the same D-H1 node-drag contract as tonecurve) + select-by
// Picker + strength slider + mode Picker.
//
// Data flow: node drags map onto the D-H1 trio exactly like a slider
// (begin → live updates → ONE commit); pickers/sliders follow the
// tonecurve panel's discrete/live split. Values READ from the instance
// record (D-X1: panels never touch display textures).
//
// Hue-tab background: a hue color strip under the curve (the colorzones
// signature — select-h edits read against the hue ring). Drawn as a
// 1px-per-column gradient (HSV S=V=1, S lifted to 0.999 to match the
// parity hue_sweep fixture pedigree — cosmetic only).
// ─────────────────────────────────────────────────────────────────────────

internal struct ColorZonesPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private enum Tab: String, CaseIterable, Identifiable {
        case lightness, chroma, hue
        var id: String { rawValue }
    }

    @State private var tab: Tab = .hue

    private var params: ColorZonesModule.Params {
        (try? instance.params(of: ColorZonesModule.self)) ?? ColorZonesModule.Params()
    }

    private var nodes: [ToneCurveModule.Node] {
        switch tab {
        case .lightness: return params.curveL.map { .init(x: $0.x, y: $0.y) }
        case .chroma: return params.curveC.map { .init(x: $0.x, y: $0.y) }
        case .hue: return params.curveH.map { .init(x: $0.x, y: $0.y) }
        }
    }

    private var curveType: ToneCurveLUT.CurveType {
        switch tab {
        case .lightness: return params.typeL
        case .chroma: return params.typeC
        case .hue: return params.typeH
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("panel_cz_channel", selection: $tab) {
                    Text("panel_cz_channel_l").tag(Tab.lightness)
                    Text("panel_cz_channel_c").tag(Tab.chroma)
                    Text("panel_cz_channel_h").tag(Tab.hue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.colorzones.channel")

                ZStack(alignment: .bottom) {
                    if tab == .hue {
                        HueStrip()
                            .frame(height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .accessibilityIdentifier("inspector.colorzones.huestrip")
                    }
                    CurveEditorView(
                        nodes: nodes,
                        curveType: curveType,
                        onDragBegin: { edit.beginEditing() },
                        onNodesChanged: { updated in setNodes(updated) },
                        onDragEnd: { edit.endEditing(label: String(localized: "history_colorzones")) }
                    )
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Button("panel_cz_reset_flat") {
                        var p = params
                        setTabNodes(&p, ColorZonesModule.Params.identityNodes(
                            hueStyle: tab == .hue).map { .init(x: $0.x, y: $0.y) })
                        applyDiscrete(p, label: String(localized: "history_colorzones"))
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .font(.caption)
            } header: {
                Text("panel_cz_curves")
            }

            Section {
                Picker("panel_cz_select", selection: selectBinding) {
                    Text("panel_cz_select_l").tag(ColorZonesLUT.SelectChannel.lightness)
                    Text("panel_cz_select_c").tag(ColorZonesLUT.SelectChannel.chroma)
                    Text("panel_cz_select_h").tag(ColorZonesLUT.SelectChannel.hue)
                }
                .accessibilityIdentifier("inspector.colorzones.select")

                LightamerSlider(
                    label: String(localized: "panel_cz_strength"),
                    value: Double(params.strength), range: -100...100, defaultValue: 0,
                    readoutFormat: "%+.0f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { setStrength(Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorzones")) },
                    onReset: { resetStrength() },
                    accessibilityID: "inspector.slider.colorzones.strength")

                Picker("panel_cz_mode", selection: modeBinding) {
                    Text("panel_cz_mode_smooth").tag(ColorZonesLUT.ProcessMode.smooth)
                    Text("panel_cz_mode_strong").tag(ColorZonesLUT.ProcessMode.strong)
                }
                .accessibilityIdentifier("inspector.colorzones.mode")
            } header: {
                Text("panel_cz_options")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colorzones")
    }

    // MARK: - Node sets

    private func setNodes(_ updated: [ToneCurveModule.Node]) {
        var p = params
        setTabNodes(&p, updated.map { ColorZonesModule.Node(x: $0.x, y: $0.y) })
        update(p)
    }

    private func setTabNodes(_ p: inout ColorZonesModule.Params, _ updated: [ColorZonesModule.Node]) {
        switch tab {
        case .lightness: p.curveL = updated
        case .chroma: p.curveC = updated
        case .hue: p.curveH = updated
        }
    }

    // MARK: - Bindings / edits

    private var selectBinding: Binding<ColorZonesLUT.SelectChannel> {
        Binding(
            get: { params.channel },
            set: { newValue in
                var p = params
                p.channel = newValue
                applyDiscrete(p, label: String(localized: "history_colorzones"))
            }
        )
    }

    private var modeBinding: Binding<ColorZonesLUT.ProcessMode> {
        Binding(
            get: { params.mode },
            set: { newValue in
                var p = params
                p.mode = newValue
                applyDiscrete(p, label: String(localized: "history_colorzones"))
            }
        )
    }

    private func setStrength(_ v: Float) {
        var p = params
        p.strength = v
        update(p)
    }

    private func resetStrength() {
        var p = params
        p.strength = 0
        applyDiscrete(p, label: String(localized: "history_colorzones"))
    }

    private func applyDiscrete(_ p: ColorZonesModule.Params, label: String) {
        if let record = PanelEditing.updated(instance, params: p, as: ColorZonesModule.self) {
            edit.applyDiscrete(record, label: label)
        }
    }

    private func update(_ p: ColorZonesModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: ColorZonesModule.self) {
            edit.update(record)
        }
    }
}

/// The hue color strip behind the hue-tab curve editor (cosmetic only —
/// no params flow through it).
private struct HueStrip: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let n = max(Int(size.width), 1)
                for i in 0..<n {
                    let h = Double(i) / Double(n)
                    let (r, g, b) = hsvToRGB(h: h, s: 0.999, v: 1.0)
                    var path = Path()
                    path.addRect(CGRect(x: CGFloat(i), y: 0, width: 1, height: size.height))
                    context.fill(path, with: .color(Color(red: r, green: g, blue: b)))
                }
            }
        }
    }

    private func hsvToRGB(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6.0) % 6
        let f = h * 6.0 - Double(Int(h * 6.0))
        let p = v * (1.0 - s), q = v * (1.0 - f * s), t = v * (1.0 - (1.0 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

internal struct ColorZonesPanelProvider: IOPPanelProvider {
    var opName: String { ColorZonesModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ColorZonesPanelView(instance: instance, edit: edit))
    }
}
