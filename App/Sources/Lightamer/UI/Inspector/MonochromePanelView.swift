import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Monochrome panel (Plan 05-05-T4, IOP-COLOR-06) — the Inspector surface
// for dt `monochrome`: Lab chroma color-wheel Canvas (click/drag sets the
// filter hue point a/b — dt gui_init/_monochrome_button_press/motion
// same interaction) + size + highlights sliders.
//
// WHEEL MAPPING (dt monochrome.c:406-420, PANEL_WIDTH=256): the wheel spans
// Lab a/b ∈ [−128, +128] (x = a·w/256 + w/2, y = b·h/256 + h/2 — dt :420).
// Radius is unbounded in dt (drag anywhere in the square); size is the
// separate scroll control (dt :542, ∈ [0.5, 3.0]). Double-click resets
// a/b/size to dt defaults (dt :482-488).
//
// D-H1 wiring: wheel drag = begin/live-ticks/end trio (exactly ONE history
// commit); sliders use LightamerSlider (same trio); resets = applyDiscrete
// one-commit. Values READ from the instance record. 280pt Inspector
// constraint: the wheel is 120pt (ColorBalanceRGBHueDisc precedent).
// ─────────────────────────────────────────────────────────────────────────

internal struct MonochromePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: MonochromeModule.Params {
        (try? instance.params(of: MonochromeModule.self)) ?? MonochromeModule.Params()
    }

    var body: some View {
        Form {
            Section {
                MonochromeColorWheel(
                    a: Double(params.a), b: Double(params.b),
                    onBegin: { edit.beginEditing() },
                    onChange: { setAB(Float($0), Float($1)) },
                    onEnd: { edit.endEditing(label: String(localized: "history_monochrome")) },
                    onReset: { resetAB() },
                    accessibilityID: "inspector.wheel.monochrome"
                )
                .frame(width: 120, height: 120)
                .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                Text("panel_monochrome_wheel_section")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_monochrome_size"),
                    value: Double(params.size), range: 0.5...3, defaultValue: 2,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.size, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_monochrome")) },
                    onReset: { reset(\.size, 2) },
                    accessibilityID: "inspector.slider.monochrome.size")
                LightamerSlider(
                    label: String(localized: "panel_monochrome_highlights"),
                    value: Double(params.highlights), range: 0...1, defaultValue: 0,
                    readoutFormat: "%.2f", unit: "",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.highlights, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_monochrome")) },
                    onReset: { reset(\.highlights, 0) },
                    accessibilityID: "inspector.slider.monochrome.highlights")
            } header: {
                Text("panel_monochrome_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.monochrome")
    }

    private func set(
        _ keyPath: WritableKeyPath<MonochromeModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: MonochromeModule.self) {
            edit.update(record)
        }
    }

    private func reset(
        _ keyPath: WritableKeyPath<MonochromeModule.Params, Float>, _ v: Float
    ) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: MonochromeModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_monochrome"))
        }
    }

    private func setAB(_ a: Float, _ b: Float) {
        var p = params
        p.a = a
        p.b = b
        if let record = PanelEditing.updated(instance, params: p, as: MonochromeModule.self) {
            edit.update(record)
        }
    }

    private func resetAB() {
        var p = params
        p.a = 0
        p.b = 0
        p.size = 2
        if let record = PanelEditing.updated(instance, params: p, as: MonochromeModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_monochrome"))
        }
    }
}

/// The Lab chroma wheel: a/b ∈ [−128, +128] square (dt PANEL_WIDTH=256),
/// neutral gray center, filter-size circle overlay (radius ∝ size —
/// dt :422 `width·0.22·size`), handle at (a, b). Click/drag sets (a, b)
/// with live ticks; double-click resets a/b/size to dt defaults.
internal struct MonochromeColorWheel: View {

    let a: Double
    let b: Double
    let onBegin: () -> Void
    let onChange: (Double, Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
    let accessibilityID: String

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // a/b backdrop: 8×8 chroma cells (dt _monochrome_draw :397-416 —
            // neutral gray modulated; UI tint only, no pipe semantics).
            let cells = 8
            for j in 0..<cells {
                for i in 0..<cells {
                    let ca = (Double(i) / Double(cells - 1) - 0.5) * 256
                    let cb = (Double(j) / Double(cells - 1) - 0.5) * 256
                    let sat = min(sqrt(ca * ca + cb * cb) / 128, 1.0)
                    let hue = atan2(cb, ca) / (2 * Double.pi) + 0.5
                    let rect = CGRect(
                        x: Double(i) / Double(cells) * w,
                        y: Double(j) / Double(cells) * h,
                        width: w / Double(cells), height: h / Double(cells))
                    var cell = Path()
                    cell.addRect(rect)
                    context.fill(cell, with: .color(wheelColor(hue: hue, sat: sat)))
                }
            }
            // Handle at (a, b): x = a·w/256 + w/2, y = b·h/256 + h/2
            // (dt :420; y down — dt flips, SwiftUI native down matches).
            let hx = a * w / 256 + w / 2
            let hy = b * h / 256 + h / 2
            var handle = Path()
            handle.addEllipse(in: CGRect(x: hx - 5, y: hy - 5, width: 10, height: 10))
            context.fill(handle, with: .color(.white))
            context.stroke(handle, with: .color(.black), lineWidth: 1)
        }
        .accessibilityIdentifier("\(accessibilityID).wheel")
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { onBegin() }
                    // location → a/b (dt :465-466, no y-flip — dt flips
                    // for cairo, SwiftUI y-down already matches hy above).
                    let w = 120.0, h = 120.0
                    let na = (Double(value.location.x) - w / 2) * 256 / w
                    let nb = (Double(value.location.y) - h / 2) * 256 / h
                    onChange(
                        min(max(na, -128), 128),
                        min(max(nb, -128), 128))
                }
                .onEnded { _ in onEnd() }
        )
        .onTapGesture(count: 2) { onReset() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("monochrome color wheel"))
        .accessibilityIdentifier(accessibilityID)
    }

    /// Display-P3 approximation of a chroma cell (UI tint only).
    private func wheelColor(hue: Double, sat: Double) -> Color {
        let x = 1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(hue * 6) % 6 {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        let gray: Double = 0.5
        return Color(.displayP3,
            red: gray + (r - gray) * sat,
            green: gray + (g - gray) * sat,
            blue: gray + (b - gray) * sat)
    }
}

internal struct MonochromePanelProvider: IOPPanelProvider {
    var opName: String { MonochromeModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(MonochromePanelView(instance: instance, edit: edit))
    }
}
