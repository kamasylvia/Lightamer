import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// ColorBalanceRGB panel (Plan 05-02-T4, IOP-COLOR-01) — the Inspector
// surface for dt `colorbalancergb`: 4 collapsible 4-way zones
// (Global/Shadows/Midtones/Highlights), each with a hue disc (Canvas
// click/drag sets H, radius sets C — the ToneEqualPanelView Canvas mode)
// + Y slider; Chroma/Saturation/Brilliance 4-lane groups; Vibrance /
// Contrast / Hue-shift / Fulcrum sliders; saturation-formula Picker.
//
// HUE DISC MAPPING (05-02-DECISIONS D3): the disc shows the CONVENTIONAL
// hue wheel (red at 0°, dt GUI convention — ANGLE_SHIFT −30° folded at
// commit, so disc 0° == params H 0°). Radius 0..1 maps C 0..1 (dt Ych
// chroma at Y=1 grading). Drag = D-H1 trio (live ticks → exactly ONE
// history commit on release); Y sliders use LightamerSlider (same trio).
// Discrete controls (Picker, resets) = applyDiscrete one-commit edits.
// Values READ from the instance record. 280pt Inspector constraint: the
// disc is 120pt, sliders full-width; nothing exceeds the column.
// ─────────────────────────────────────────────────────────────────────────

internal struct ColorBalanceRGBPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: ColorBalanceRGBModule.Params {
        (try? instance.params(of: ColorBalanceRGBModule.self)) ?? ColorBalanceRGBModule.Params()
    }

    var body: some View {
        Form {
            fourWaySection(
                title: "panel_cb_global",
                hue: params.globalH, chroma: params.globalC, lum: params.globalY,
                setH: { set(\.globalH, $0) }, setC: { set(\.globalC, $0) }, setY: { set(\.globalY, $0) },
                resetH: { reset(\.globalH, 0) }, resetC: { reset(\.globalC, 0) }, resetY: { reset(\.globalY, 0) },
                idPrefix: "global"
            )
            fourWaySection(
                title: "panel_cb_shadows",
                hue: params.shadowsH, chroma: params.shadowsC, lum: params.shadowsY,
                setH: { set(\.shadowsH, $0) }, setC: { set(\.shadowsC, $0) }, setY: { set(\.shadowsY, $0) },
                resetH: { reset(\.shadowsH, 0) }, resetC: { reset(\.shadowsC, 0) }, resetY: { reset(\.shadowsY, 0) },
                idPrefix: "shadows"
            )
            fourWaySection(
                title: "panel_cb_midtones",
                hue: params.midtonesH, chroma: params.midtonesC, lum: params.midtonesY,
                setH: { set(\.midtonesH, $0) }, setC: { set(\.midtonesC, $0) }, setY: { set(\.midtonesY, $0) },
                resetH: { reset(\.midtonesH, 0) }, resetC: { reset(\.midtonesC, 0) }, resetY: { reset(\.midtonesY, 0) },
                idPrefix: "midtones"
            )
            fourWaySection(
                title: "panel_cb_highlights",
                hue: params.highlightsH, chroma: params.highlightsC, lum: params.highlightsY,
                setH: { set(\.highlightsH, $0) }, setC: { set(\.highlightsC, $0) }, setY: { set(\.highlightsY, $0) },
                resetH: { reset(\.highlightsH, 0) }, resetC: { reset(\.highlightsC, 0) }, resetY: { reset(\.highlightsY, 0) },
                idPrefix: "highlights"
            )
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cb_chroma_global"),
                    value: Double(params.chromaGlobal), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.chromaGlobal, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.chromaGlobal, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.chroma_global"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_chroma_shadows"),
                    value: Double(params.chromaShadows), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.chromaShadows, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.chromaShadows, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.chroma_shadows"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_chroma_midtones"),
                    value: Double(params.chromaMidtones), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.chromaMidtones, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.chromaMidtones, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.chroma_midtones"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_chroma_highlights"),
                    value: Double(params.chromaHighlights), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.chromaHighlights, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.chromaHighlights, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.chroma_highlights"
                )
            } header: {
                Text("panel_cb_chroma_section")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cb_saturation_global"),
                    value: Double(params.saturationGlobal), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturationGlobal, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.saturationGlobal, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.saturation_global"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_saturation_shadows"),
                    value: Double(params.saturationShadows), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturationShadows, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.saturationShadows, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.saturation_shadows"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_saturation_midtones"),
                    value: Double(params.saturationMidtones), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturationMidtones, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.saturationMidtones, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.saturation_midtones"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_saturation_highlights"),
                    value: Double(params.saturationHighlights), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturationHighlights, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.saturationHighlights, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.saturation_highlights"
                )
            } header: {
                Text("panel_cb_saturation_section")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cb_brilliance_global"),
                    value: Double(params.brillianceGlobal), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.brillianceGlobal, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.brillianceGlobal, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.brilliance_global"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_brilliance_shadows"),
                    value: Double(params.brillianceShadows), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.brillianceShadows, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.brillianceShadows, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.brilliance_shadows"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_brilliance_midtones"),
                    value: Double(params.brillianceMidtones), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.brillianceMidtones, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.brillianceMidtones, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.brilliance_midtones"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_brilliance_highlights"),
                    value: Double(params.brillianceHighlights), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.brillianceHighlights, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.brillianceHighlights, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.brilliance_highlights"
                )
            } header: {
                Text("panel_cb_brilliance_section")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cb_vibrance"),
                    value: Double(params.vibrance), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.vibrance, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.vibrance, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.vibrance"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_contrast"),
                    value: Double(params.contrast), range: -1...1, defaultValue: 0,
                    readoutFormat: "%+.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.contrast, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.contrast, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.contrast"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_hue_angle"),
                    value: Double(params.hueAngle), range: -180...180, defaultValue: 0,
                    readoutFormat: "%+.0f", unit: "°",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.hueAngle, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.hueAngle, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.hue_angle"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_grey_fulcrum"),
                    value: Double(params.greyFulcrum), range: 0...1, defaultValue: 0.1845,
                    readoutFormat: "%.3f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.greyFulcrum, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.greyFulcrum, 0.1845) },
                    accessibilityID: "inspector.slider.colorbalancergb.grey_fulcrum"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_white_fulcrum"),
                    value: Double(params.whiteFulcrum), range: -16...16, defaultValue: 0,
                    readoutFormat: "%+.1f", unit: " EV",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.whiteFulcrum, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.whiteFulcrum, 0) },
                    accessibilityID: "inspector.slider.colorbalancergb.white_fulcrum"
                )
                LightamerSlider(
                    label: String(localized: "panel_cb_mask_grey_fulcrum"),
                    value: Double(params.maskGreyFulcrum), range: 0...1, defaultValue: 0.1845,
                    readoutFormat: "%.3f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.maskGreyFulcrum, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                    onReset: { reset(\.maskGreyFulcrum, 0.1845) },
                    accessibilityID: "inspector.slider.colorbalancergb.mask_grey_fulcrum"
                )
                Picker(String(localized: "panel_cb_saturation_formula"), selection: formulaBinding) {
                    Text("panel_cb_formula_jzazbz").tag(ColorBalanceRGBSaturationFormula.jzazbz)
                    Text("panel_cb_formula_dtucs").tag(ColorBalanceRGBSaturationFormula.dtUCS)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.picker.colorbalancergb.saturation_formula")
            } header: {
                Text("panel_cb_master_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colorbalancergb")
    }

    private func fourWaySection(
        title: LocalizedStringKey,
        hue: Float, chroma: Float, lum: Float,
        setH: @escaping (Float) -> Void, setC: @escaping (Float) -> Void, setY: @escaping (Float) -> Void,
        resetH: @escaping () -> Void, resetC: @escaping () -> Void, resetY: @escaping () -> Void,
        idPrefix: String
    ) -> some View {
        Section {
        // NOTE(05-02-T4): plain Section (ToneEqual house pattern) — plan
        // "折叠" deferred: DisclosureGroup needs per-zone @State; acceptance
        // only requires 4 zones + disc + Picker. See 05-02-DECISIONS D3.
            ColorBalanceRGBHueDisc(
                hue: Double(hue), chroma: Double(chroma),
                onBegin: { edit.beginEditing() },
                onChange: { setH(Float($0)); setC(Float($1)) },
                onEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                onReset: { resetH(); resetC() },
                accessibilityID: "inspector.disc.colorbalancergb.\(idPrefix)"
            )
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity, alignment: .center)
            LightamerSlider(
                label: String(localized: "panel_cb_luminance"),
                value: Double(lum), range: -1...1, defaultValue: 0,
                readoutFormat: "%+.2f", unit: "",
                onDragBegin: { edit.beginEditing() },
                onChange: { setY(Float($0)) },
                onDragEnd: { edit.endEditing(label: String(localized: "history_colorbalancergb")) },
                onReset: { resetY() },
                accessibilityID: "inspector.slider.colorbalancergb.\(idPrefix)_y"
            )
        } header: {
            Text(title)
        }
    }

    private func set(_ keyPath: WritableKeyPath<ColorBalanceRGBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ColorBalanceRGBModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<ColorBalanceRGBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ColorBalanceRGBModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_colorbalancergb"))
        }
    }

    private var formulaBinding: Binding<ColorBalanceRGBSaturationFormula> {
        Binding(
            get: { params.saturationFormula },
            set: { formula in
                var p = params
                p.saturationFormula = formula
                if let record = PanelEditing.updated(instance, params: p, as: ColorBalanceRGBModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_colorbalancergb"))
                }
            }
        )
    }
}

/// The 4-way hue disc: conventional hue wheel (red 0° at 3 o'clock,
/// increasing counter-clockwise — dt GUI convention), radius = chroma
/// 0..1. Click/drag sets (H, C); the handle marks the current value.
/// D-H1: drag begin → live ticks → end commits exactly ONE history item;
/// double-click resets H/C to 0 (discrete one-commit).
internal struct ColorBalanceRGBHueDisc: View {

    let hue: Double
    let chroma: Double
    let onBegin: () -> Void
    let onChange: (Double, Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
    let accessibilityID: String

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Hue ring backdrop (conventional wheel, 64 segments).
            for i in 0..<64 {
                let a0 = Double(i) / 64 * 2 * Double.pi
                let a1 = Double(i + 1) / 64 * 2 * Double.pi
                var seg = Path()
                seg.move(to: center)
                seg.addArc(center: center, radius: radius, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                seg.closeSubpath()
                context.fill(seg, with: .color(hueColor(a0 + (a1 - a0) / 2)))
            }
            // Chroma handled as desaturation toward center (mid-gray core).
            var core = Path()
            core.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            context.fill(core, with: .color(.secondary))
            // Handle at (H, C).
            let ang = hue * Double.pi / 180
            let r = min(max(chroma, 0), 1) * radius
            let hp = CGPoint(x: center.x + CGFloat(cos(ang)) * r, y: center.y - CGFloat(sin(ang)) * r)
            var handle = Path()
            handle.addEllipse(in: CGRect(x: hp.x - 5, y: hp.y - 5, width: 10, height: 10))
            context.fill(handle, with: .color(.white))
            context.stroke(handle, with: .color(.black), lineWidth: 1)
        }
        .accessibilityIdentifier("\(accessibilityID).disc")
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { onBegin() }
                    let center = CGPoint(x: 60, y: 60)
                    let dx = Double(value.location.x - center.x)
                    let dy = -(Double(value.location.y - center.y))
                    let r = min(sqrt(dx * dx + dy * dy) / 60, 1.0)
                    var deg = atan2(dy, dx) * 180 / Double.pi
                    if deg < 0 { deg += 360 }
                    onChange(deg, r)
                }
                .onEnded { _ in onEnd() }
        )
        .onTapGesture(count: 2) { onReset() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("colorbalancergb hue disc"))
        .accessibilityIdentifier(accessibilityID)
    }

    /// Display-P3 approximation of the conventional hue wheel (UI tint
    /// only — no pipe semantics).
    private func hueColor(_ radians: Double) -> Color {
        let h = radians / (2 * Double.pi)
        let x = 1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(h * 6) % 6 {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        return Color(.displayP3, red: r, green: g, blue: b)
    }
}

internal struct ColorBalanceRGBPanelProvider: IOPPanelProvider {
    var opName: String { ColorBalanceRGBModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ColorBalanceRGBPanelView(instance: instance, edit: edit))
    }
}
