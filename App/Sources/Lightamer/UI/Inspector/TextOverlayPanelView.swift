import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// TextOverlayPanelView (Plan 08-5 T2) — the editing-time text layer panel:
// content / font / size / color / position / rotation / opacity (the v1
// face — stroke and shadow stay the additive seam, SC#4 has no literal).
//
// D-H1 三件套: text/slider edits live-tick (zero history), land exactly
// ONE layerScope commit at commit time; reset is a discrete one-commit
// edit. Grouped: the face keeps the five-knob panel shape (D-H1 三件套's
// grouped-section convention — content+font primary, geometry secondary).
// ─────────────────────────────────────────────────────────────────────────

internal struct TextOverlayPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: TextOverlayModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: TextOverlayModule.self) ?? TextOverlayModule.Params()
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: "panel_text_content_placeholder"),
                    text: Binding(
                        get: { params.content },
                        set: { newValue in set(\.content, newValue) }),
                    axis: .vertical)
                    .accessibilityIdentifier("inspector.text.textoverlay.content")
                TextField(
                    String(localized: "panel_text_font"),
                    text: Binding(
                        get: { params.fontName },
                        set: { newValue in set(\.fontName, newValue) }))
                    .accessibilityIdentifier("inspector.text.textoverlay.font")
                LightamerSlider(
                    label: String(localized: "panel_text_font_size"),
                    value: Double(params.fontSize),
                    range: 10...400,
                    defaultValue: 60,
                    readoutFormat: "%.0f",
                    unit: "px",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.fontSize, Float($0)) },
                    onDragEnd: { commit() },
                    onReset: { reset(\.fontSize, 60) },
                    accessibilityID: "inspector.slider.textoverlay.size")
            } header: {
                Text("panel_text_section_content")
            }
            Section {
                ColorPicker(
                    String(localized: "panel_text_color"),
                    selection: Binding(
                        get: {
                            Color(
                                red: Double(params.colorR),
                                green: Double(params.colorG),
                                blue: Double(params.colorB))
                        },
                        set: { color in
                            var p = params
                            // The panel colorspace is sRGB (the display
                            // convention); the value rides as the working
                            // RGB triple (the kernel does no matrix math —
                            // research §11.2).
                            let nsColor = NSColor(color).usingColorSpace(.deviceRGB)
                                ?? NSColor.white
                            p.colorR = Float(nsColor.redComponent)
                            p.colorG = Float(nsColor.greenComponent)
                            p.colorB = Float(nsColor.blueComponent)
                            if let record = PanelEditing.updated(
                                instance, params: p, as: TextOverlayModule.self) {
                                edit.applyDiscrete(
                                    record, label: String(localized: "history_textoverlay"))
                            }
                        }))
                    .accessibilityIdentifier("inspector.color.textoverlay")
            } header: {
                Text("panel_text_section_color")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_text_pos_x"),
                    value: Double(params.posX),
                    range: 0...1,
                    defaultValue: 0.5,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.posX, Float($0)) },
                    onDragEnd: { commit() },
                    onReset: { reset(\.posX, 0.5) },
                    accessibilityID: "inspector.slider.textoverlay.posx")
                LightamerSlider(
                    label: String(localized: "panel_text_pos_y"),
                    value: Double(params.posY),
                    range: 0...1,
                    defaultValue: 0.5,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.posY, Float($0)) },
                    onDragEnd: { commit() },
                    onReset: { reset(\.posY, 0.5) },
                    accessibilityID: "inspector.slider.textoverlay.posy")
                LightamerSlider(
                    label: String(localized: "panel_text_rotation"),
                    value: Double(params.rotationDegrees),
                    range: -180...180,
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    unit: "°",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.rotationDegrees, Float($0)) },
                    onDragEnd: { commit() },
                    onReset: { reset(\.rotationDegrees, 0) },
                    accessibilityID: "inspector.slider.textoverlay.rotation")
                LightamerSlider(
                    label: String(localized: "panel_text_opacity"),
                    value: Double(params.opacity),
                    range: 0...1,
                    defaultValue: 1,
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.opacity, Float($0)) },
                    onDragEnd: { commit() },
                    onReset: { reset(\.opacity, 1) },
                    accessibilityID: "inspector.slider.textoverlay.opacity")
            } header: {
                Text("panel_text_section_geometry")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.textoverlay")
    }

    // MARK: D-H1 legs

    private func commit() {
        edit.endEditing(label: String(localized: "history_textoverlay"))
    }

    private func set(_ keyPath: WritableKeyPath<TextOverlayModule.Params, String>, _ v: String) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: TextOverlayModule.self) {
            edit.update(record)
        }
    }

    private func set(_ keyPath: WritableKeyPath<TextOverlayModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: TextOverlayModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<TextOverlayModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: TextOverlayModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_textoverlay"))
        }
    }
}

internal struct TextOverlayPanelProvider: IOPPanelProvider {
    var opName: String { TextOverlayModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(TextOverlayPanelView(instance: instance, edit: edit))
    }
}
