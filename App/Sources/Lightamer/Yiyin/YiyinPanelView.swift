import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// YiyinPanelView (Plan 08-2 T6) — the 印框/水印 Inspector panel's WATERMARK
// section (the borders section integrates in Plan 08-3). Template-row CRUD
// with STABLE identity rows (L010: `yiyin.template.row.<key>` — never an
// index), the {Field} inserter, the FontSetting cluster, the baseline/
// center alignment, the nine-grid anchor (D-08-CONTEXT-2), the logo
// opacity slider, and the date format — every control committing into the
// WatermarkModule instance record.
//
// D-H1 三件套: continuous drags live-tick (zero history) and land exactly
// ONE commit at drag end; discrete controls (toggles/pickers/inserts)
// apply as ONE commit each. Values READ from the instance record.
//
// 280pt Inspector constraint: single-column Form, compact pickers, no
// side-by-side color wheels. The main viewport IS the preview (no panel
// canvas — the pipe renders live).
// ─────────────────────────────────────────────────────────────────────────

internal struct YiyinPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var fontFamilies: [String] = []
    @State private var userFonts: [String] = []
    // The text-field buffers (commit on submit — a keystroke never
    // history-spams, D-H1 discrete face).
    @State private var dateFormatBuffer = ""
    @State private var patternBuffers: [String: String] = [:]
    @State private var colorBuffers: [String: String] = [:]

    private var params: WatermarkModule.Params {
        PanelEditing.params(of: instance, as: WatermarkModule.self)
            ?? WatermarkModule.Params.neutralSeed
    }

    var body: some View {
        Form {
            watermarkSection
            templatesSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("yiyin.panel")
        .task {
            // The font lists load once per panel mount (system + user).
            let store = YiyinFontStore()
            fontFamilies = store.availableSystemFontFamilies()
            userFonts = store.installedNames
        }
    }

    // MARK: the watermark parameters section

    private var watermarkSection: some View {
        Section("panel_yiyin_watermark_section") {
            LightamerSlider(
                label: String(localized: "panel_yiyin_logo_opacity"),
                value: params.logoOpacity * 100,
                range: 0...100,
                defaultValue: 100,
                readoutFormat: "%.0f",
                unit: "%",
                onDragBegin: { edit.beginEditing() },
                onChange: { set(\.logoOpacity, $0 / 100) },
                onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_watermark")) },
                onReset: { set(\.logoOpacity, 1) },
                accessibilityID: "yiyin.slider.logoOpacity")

            LightamerSlider(
                label: String(localized: "panel_yiyin_line_spacing"),
                value: params.lineSpacing,
                range: 0...5,
                defaultValue: 0.4,
                readoutFormat: "%.1f",
                unit: " %",
                onDragBegin: { edit.beginEditing() },
                onChange: { set(\.lineSpacing, $0) },
                onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_watermark")) },
                onReset: { set(\.lineSpacing, 0.4) },
                accessibilityID: "yiyin.slider.lineSpacing")

            Picker("panel_yiyin_anchor", selection: Binding(
                get: { params.anchor },
                set: { set(\.anchor, $0) }
            )) {
                ForEach(anchorCases, id: \.0) { pair in
                    Text(LocalizedStringKey(pair.1)).tag(pair.0)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("yiyin.picker.anchor")

            TextField(
                "panel_yiyin_date_format",
                text: Binding(
                    get: { dateFormatBuffer.isEmpty ? params.dateFormat : dateFormatBuffer },
                    set: { dateFormatBuffer = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    set(\.dateFormat, dateFormatBuffer)
                    dateFormatBuffer = ""
                }
                .accessibilityIdentifier("yiyin.field.dateFormat")
        }
    }

    private var anchorCases: [(YiyinNineGridAnchor, String)] {
        [
            (.topLeft, "panel_yiyin_anchor_topLeft"),
            (.topCenter, "panel_yiyin_anchor_topCenter"),
            (.topRight, "panel_yiyin_anchor_topRight"),
            (.centerLeft, "panel_yiyin_anchor_centerLeft"),
            (.center, "panel_yiyin_anchor_center"),
            (.centerRight, "panel_yiyin_anchor_centerRight"),
            (.bottomLeft, "panel_yiyin_anchor_bottomLeft"),
            (.bottomCenter, "panel_yiyin_anchor_bottomCenter"),
            (.bottomRight, "panel_yiyin_anchor_bottomRight"),
        ]
    }

    // MARK: the template rows (CRUD)

    private var templatesSection: some View {
        Section("panel_yiyin_templates_section") {
            Button {
                var p = params
                let key = "custom-\(UUID().uuidString.prefix(8))"
                p.templates.append(YiyinTemplate(
                    key: key, name: String(localized: "panel_yiyin_new_template"),
                    pattern: "", use: false))
                apply(p, label: String(localized: "history_yiyin_template_add"))
            } label: {
                Label("panel_yiyin_template_add", systemImage: "plus")
            }
            .accessibilityIdentifier("yiyin.button.addTemplate")

            ForEach(params.templates, id: \.key) { template in
                templateRow(template)
                    .accessibilityIdentifier("yiyin.template.row.\(template.key)")
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: YiyinTemplate) -> some View {
        let index = params.templates.firstIndex { $0.key == template.key }
        DisclosureGroup {
            if let index {
                templateEditor(index: index, template: template)
            }
        } label: {
            Toggle(isOn: Binding(
                get: { template.use },
                set: { use in
                    var p = params
                    if let index = p.templates.firstIndex(where: { $0.key == template.key }) {
                        p.templates[index].use = use
                        apply(p, label: String(localized: "history_yiyin_watermark"))
                    }
                }
            )) {
                Text(template.name.isEmpty ? template.key : template.name)
                    .font(.callout)
            }
            .accessibilityIdentifier("yiyin.template.toggle.\(template.key)")
        }
    }

    @ViewBuilder
    private func templateEditor(index: Int, template: YiyinTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "panel_yiyin_template_pattern",
                text: Binding(
                    get: { patternBuffers[template.key] ?? template.pattern },
                    set: { patternBuffers[template.key] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let value = patternBuffers[template.key] {
                        var p = params
                        if let i = p.templates.firstIndex(where: { $0.key == template.key }) {
                            p.templates[i].pattern = value
                            apply(p, label: String(localized: "history_yiyin_watermark"))
                        }
                    }
                    patternBuffers.removeValue(forKey: template.key)
                }
                .accessibilityIdentifier("yiyin.template.pattern.\(template.key)")

            // The {Field} inserter (FieldSelect) — appends at the end,
            // ONE commit per insertion.
            Menu {
                ForEach(YiyinExifField.allCases, id: \.rawValue) { field in
                    Button(field.zhName) {
                        var p = params
                        let live = patternBuffers[template.key] ?? template.pattern
                        p.templates[index].pattern = live + "{\(field.rawValue)}"
                        patternBuffers.removeValue(forKey: template.key)
                        apply(p, label: String(localized: "history_yiyin_field_insert"))
                    }
                }
            } label: {
                Label("panel_yiyin_insert_field", systemImage: "curlybraces")
            }
            .accessibilityIdentifier("yiyin.template.insertField.\(template.key)")

            fontSetting(index: index, template: template)

            Picker("panel_yiyin_align", selection: Binding(
                get: { template.verticalAlign },
                set: { align in
                    var p = params
                    p.templates[index].verticalAlign = align
                    apply(p, label: String(localized: "history_yiyin_watermark"))
                }
            )) {
                Text("panel_yiyin_align_baseline").tag(YiyinVerticalAlign.baseline)
                Text("panel_yiyin_align_center").tag(YiyinVerticalAlign.center)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("yiyin.template.align.\(template.key)")

            Button(role: .destructive) {
                var p = params
                p.templates.removeAll { $0.key == template.key }
                apply(p, label: String(localized: "history_yiyin_template_delete"))
            } label: {
                Label("panel_yiyin_template_delete", systemImage: "trash")
            }
            .accessibilityIdentifier("yiyin.template.delete.\(template.key)")
        }
    }

    @ViewBuilder
    private func fontSetting(index: Int, template: YiyinTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("panel_yiyin_font", selection: Binding(
                get: { template.font.name },
                set: { family in
                    var p = params
                    p.templates[index].font.name = family
                    apply(p, label: String(localized: "history_yiyin_watermark"))
                }
            )) {
                Text("panel_yiyin_font_default").tag("")
                ForEach(userFonts, id: \.self) { family in
                    Text(family).tag(family)
                }
                ForEach(fontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("yiyin.template.font.\(template.key)")

            LightamerSlider(
                label: String(localized: "panel_yiyin_font_size"),
                value: template.font.sizePercent,
                range: 0.5...10,
                defaultValue: 2.2,
                readoutFormat: "%.1f",
                unit: " %",
                onDragBegin: { edit.beginEditing() },
                onChange: { value in
                    var p = params
                    p.templates[index].font.sizePercent = value
                    if let record = updatedRecord(p) {
                        edit.update(record)
                    }
                },
                onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_watermark")) },
                onReset: {
                    var p = params
                    if let i = p.templates.firstIndex(where: { $0.key == template.key }) {
                        p.templates[i].font.sizePercent = 2.2
                        apply(p, label: String(localized: "history_yiyin_watermark"))
                    }
                },
                accessibilityID: "yiyin.template.fontSize.\(template.key)")

            HStack {
                Toggle("panel_yiyin_bold", isOn: Binding(
                    get: { template.font.bold },
                    set: { bold in
                        var p = params
                        p.templates[index].font.bold = bold
                        apply(p, label: String(localized: "history_yiyin_watermark"))
                    }))
                    .accessibilityIdentifier("yiyin.template.bold.\(template.key)")
                Toggle("panel_yiyin_italic", isOn: Binding(
                    get: { template.font.italic },
                    set: { italic in
                        var p = params
                        p.templates[index].font.italic = italic
                        apply(p, label: String(localized: "history_yiyin_watermark"))
                    }))
                    .accessibilityIdentifier("yiyin.template.italic.\(template.key)")
            }
            .toggleStyle(.checkbox)

            Picker("panel_yiyin_case", selection: Binding(
                get: { template.font.caseType },
                set: { caseType in
                    var p = params
                    p.templates[index].font.caseType = caseType
                    apply(p, label: String(localized: "history_yiyin_watermark"))
                }
            )) {
                Text("panel_yiyin_case_default").tag(YiyinCaseType.default)
                Text("panel_yiyin_case_lower").tag(YiyinCaseType.lowcase)
                Text("panel_yiyin_case_upper").tag(YiyinCaseType.upcase)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("yiyin.template.case.\(template.key)")

            TextField(
                "panel_yiyin_color",
                text: Binding(
                    get: { colorBuffers[template.key] ?? template.font.color },
                    set: { colorBuffers[template.key] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let color = colorBuffers[template.key] {
                        var p = params
                        if let i = p.templates.firstIndex(where: { $0.key == template.key }) {
                            p.templates[i].font.color = color
                            apply(p, label: String(localized: "history_yiyin_watermark"))
                        }
                    }
                    colorBuffers.removeValue(forKey: template.key)
                }
                .accessibilityIdentifier("yiyin.template.color.\(template.key)")
        }
    }

    // MARK: D-H1 legs

    private func updatedRecord(_ params: WatermarkModule.Params) -> ModuleInstance? {
        PanelEditing.updated(instance, params: params, as: WatermarkModule.self)
    }

    /// A live tick (zero history).
    private func set(_ keyPath: WritableKeyPath<WatermarkModule.Params, Double>, _ v: Double) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = updatedRecord(p) {
            edit.update(record)
        }
    }

    /// A generic one-commit discrete write.
    private func set<Value>(
        _ keyPath: WritableKeyPath<WatermarkModule.Params, Value>, _ v: Value
    ) {
        var p = params
        p[keyPath: keyPath] = v
        apply(p, label: String(localized: "history_yiyin_watermark"))
    }

    private func apply(_ params: WatermarkModule.Params, label: String) {
        if let record = updatedRecord(params) {
            edit.applyDiscrete(record, label: label)
        }
    }
}

internal struct YiyinPanelProvider: IOPPanelProvider {
    var opName: String { WatermarkModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(YiyinPanelView(instance: instance, edit: edit))
    }
}
