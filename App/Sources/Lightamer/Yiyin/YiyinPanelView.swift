import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// YiyinPanelView (Plan 08-2 T6 watermark section; Plan 08-3 T1 integrates
// the BORDERS section) — the 印框/水印 Inspector panel. ONE panel, TWO
// sections, TWO module instances: the 印框 (borders) section commits into
// the BordersModule record and the 水印 (watermark) sections into the
// WatermarkModule record — whichever row dispatched the panel (D-08-3-T1-1:
// the sibling lookup rides the session; `liveEdited` keys on instance
// UUID, so interleaved section edits land as separate commits and ⌘Z
// reverts them independently).
//
// Template-row CRUD with STABLE identity rows (L010:
// `yiyin.template.row.<key>` — never an index), the {Field} inserter, the
// FontSetting cluster, the baseline/center alignment, the nine-grid anchor
// (D-08-CONTEXT-2), the logo opacity slider, and the date format.
//
// D-H1 三件套: continuous drags live-tick (zero history) and land exactly
// ONE commit at drag end; discrete controls (toggles/pickers/inserts)
// apply as ONE commit each. Values READ from the instance records.
//
// D-08-CONTEXT-4: no AUTO-attach — the seed carries enabled-neutral
// carriers; the「应用默认印框」button is the manual one-click entry (a
// default-preset apply = one discrete commit; D-08-3-T1-2).
//
// 280pt Inspector constraint: single-column Form, compact pickers, no
// side-by-side color wheels. The main viewport IS the preview (no panel
// canvas — the pipe renders live).
// ─────────────────────────────────────────────────────────────────────────

internal struct YiyinPanelView: View {

    /// The record whose row dispatched the panel (either yiyin op — the
    /// panel is dual-section regardless).
    let dispatched: ModuleInstance
    let edit: InspectorEditSession

    @State private var fontFamilies: [String] = []
    @State private var userFonts: [String] = []
    // The text-field buffers (commit on submit — a keystroke never
    // history-spams, D-H1 discrete face).
    @State private var dateFormatBuffer = ""
    @State private var patternBuffers: [String: String] = [:]
    @State private var colorBuffers: [String: String] = [:]
    @State private var borderColorBuffer = ""

    private var watermarkInstance: ModuleInstance? {
        dispatched.opName == WatermarkModule.opName
            ? dispatched : edit.siblingInstance(opName: WatermarkModule.opName)
    }

    private var bordersInstance: ModuleInstance? {
        dispatched.opName == BordersModule.opName
            ? dispatched : edit.siblingInstance(opName: BordersModule.opName)
    }

    private var params: WatermarkModule.Params {
        watermarkInstance.flatMap { PanelEditing.params(of: $0, as: WatermarkModule.self) }
            ?? WatermarkModule.Params.neutralSeed
    }

    private var bordersParams: BordersModule.Params {
        bordersInstance.flatMap { PanelEditing.params(of: $0, as: BordersModule.self) }
            ?? BordersModule.Params.neutralSeed
    }

    /// The current-mode accessories the mode Picker tags key on (the tag
    /// must match the LIVE mode value; switching modes preserves the other
    /// face's last value, yiyin's shared-config semantics).
    private var solidColor: String {
        if case .solid(let c) = bordersParams.mode { return c }
        return "#ffffff"
    }

    private var blurAmount: Double {
        if case .blur(let a) = bordersParams.mode { return a }
        return 100
    }

    var body: some View {
        Form {
            bordersSection
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

    // MARK: the borders (印框) parameters section — commits the BordersModule
    // instance (08-3 T1; yiyin main_img_w_rate 1-100 / margin 0-100 /
    // radius+shadow 0-50 with show-switches / bg_blur 0-100 slider ranges).

    private var bordersSection: some View {
        Section("panel_yiyin_borders_section") {
            if let instance = bordersInstance {
                bordersControls(instance: instance)
            } else {
                // D-08-CONTEXT-4 manual face: no record in the chain (old
                // sidecar restore) — the user mints one explicitly.
                Button {
                    applyBorders(
                        BordersModule.Params.neutralSeed, label:
                            String(localized: "history_yiyin_borders"),
                        existing: nil)
                } label: {
                    Label("panel_yiyin_add_borders", systemImage: "plus")
                }
                .accessibilityIdentifier("yiyin.button.addBorders")
            }
        }
    }

    @ViewBuilder
    private func bordersControls(instance: ModuleInstance) -> some View {
        Picker("panel_yiyin_bg_mode", selection: Binding(
            get: { bordersParams.mode },
            set: { mode in
                var p = bordersParams
                p.mode = mode
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            }
        )) {
            Text("panel_yiyin_bg_solid").tag(
                BordersModule.BackdropMode.solid(color: solidColor))
            Text("panel_yiyin_bg_blur").tag(
                BordersModule.BackdropMode.blur(amount: blurAmount))
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("yiyin.picker.bgMode")

        switch bordersParams.mode {
        case .solid(let color):
            TextField(
                "panel_yiyin_bg_color",
                text: Binding(
                    get: { borderColorBuffer.isEmpty ? color : borderColorBuffer },
                    set: { borderColorBuffer = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let value = borderColorBuffer.isEmpty ? color : borderColorBuffer
                    var p = bordersParams
                    p.mode = .solid(color: value)
                    applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
                    borderColorBuffer = ""
                }
                .accessibilityIdentifier("yiyin.field.bgColor")
        case .blur(let amount):
            LightamerSlider(
                label: String(localized: "panel_yiyin_blur_amount"),
                value: amount,
                range: 0...100,
                defaultValue: 100,
                readoutFormat: "%.0f",
                unit: " %",
                onDragBegin: { edit.beginEditing() },
                onChange: { value in
                    var p = bordersParams
                    p.mode = .blur(amount: value)
                    setBordersLive(p, instance: instance)
                },
                onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_borders")) },
                onReset: {
                    var p = bordersParams
                    p.mode = .blur(amount: 100)
                    applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
                },
                accessibilityID: "yiyin.slider.blurAmount")
        }

        LightamerSlider(
            label: String(localized: "panel_yiyin_main_rate"),
            value: bordersParams.mainImageWidthRate,
            range: 1...100,
            defaultValue: 90,
            readoutFormat: "%.0f",
            unit: " %",
            onDragBegin: { edit.beginEditing() },
            onChange: { value in
                var p = bordersParams
                p.mainImageWidthRate = value.rounded()
                setBordersLive(p, instance: instance)
            },
            onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_borders")) },
            onReset: {
                var p = bordersParams
                p.mainImageWidthRate = 90
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            },
            accessibilityID: "yiyin.slider.mainRate")

        LightamerSlider(
            label: String(localized: "panel_yiyin_min_margin"),
            value: bordersParams.miniTopBottomMargin,
            range: 0...100,
            defaultValue: 0,
            readoutFormat: "%.1f",
            unit: " %",
            onDragBegin: { edit.beginEditing() },
            onChange: { value in
                var p = bordersParams
                p.miniTopBottomMargin = value
                setBordersLive(p, instance: instance)
            },
            onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_borders")) },
            onReset: {
                var p = bordersParams
                p.miniTopBottomMargin = 0
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            },
            accessibilityID: "yiyin.slider.minMargin")

        Toggle("panel_yiyin_corner_radius", isOn: Binding(
            get: { bordersParams.cornerRadius != nil },
            set: { on in
                var p = bordersParams
                p.cornerRadius = on ? 2.1 : nil
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            }
        ))
        .accessibilityIdentifier("yiyin.toggle.cornerRadius")

        if let radius = bordersParams.cornerRadius {
            LightamerSlider(
                label: String(localized: "panel_yiyin_corner_radius_value"),
                value: radius,
                range: 0...50,
                defaultValue: 2.1,
                readoutFormat: "%.1f",
                unit: " %",
                onDragBegin: { edit.beginEditing() },
                onChange: { value in
                    var p = bordersParams
                    p.cornerRadius = value
                    setBordersLive(p, instance: instance)
                },
                onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_borders")) },
                onReset: {
                    var p = bordersParams
                    p.cornerRadius = 2.1
                    applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
                },
                accessibilityID: "yiyin.slider.cornerRadius")
        }

        Toggle("panel_yiyin_shadow", isOn: Binding(
            get: { bordersParams.shadow != nil },
            set: { on in
                var p = bordersParams
                p.shadow = on ? 6 : nil
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            }
        ))
        .accessibilityIdentifier("yiyin.toggle.shadow")

        if let shadow = bordersParams.shadow {
            LightamerSlider(
                label: String(localized: "panel_yiyin_shadow_value"),
                value: shadow,
                range: 0...50,
                defaultValue: 6,
                readoutFormat: "%.1f",
                unit: " %",
                onDragBegin: { edit.beginEditing() },
                onChange: { value in
                    var p = bordersParams
                    p.shadow = value
                    setBordersLive(p, instance: instance)
                },
                onDragEnd: { edit.endEditing(label: String(localized: "history_yiyin_borders")) },
                onReset: {
                    var p = bordersParams
                    p.shadow = 6
                    applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
                },
                accessibilityID: "yiyin.slider.shadow")
        }

        Picker("panel_yiyin_aspect", selection: Binding(
            get: { bordersParams.aspectRatio },
            set: { aspect in
                var p = bordersParams
                p.aspectRatio = aspect
                // yiyin onBGRateChange mutual exclusion (the module commit
                // force-clears too — the panel mirrors it for display).
                if aspect != nil { p.landscapeOutput = false }
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            }
        )) {
            Text("panel_yiyin_aspect_follow").tag(BordersModule.AspectRatio?.none)
            ForEach(aspectCases, id: \.1) { pair in
                Text(LocalizedStringKey(pair.1)).tag(BordersModule.AspectRatio?.some(pair.0))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("yiyin.picker.aspect")

        Toggle("panel_yiyin_landscape", isOn: Binding(
            get: { bordersParams.landscapeOutput },
            set: { on in
                var p = bordersParams
                p.landscapeOutput = on
                if on { p.aspectRatio = nil }
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            }
        ))
        .accessibilityIdentifier("yiyin.toggle.landscape")

        Toggle("panel_yiyin_adaptive", isOn: Binding(
            get: { bordersParams.adaptiveBackdrop },
            set: { on in
                var p = bordersParams
                p.adaptiveBackdrop = on
                applyBorders(p, label: String(localized: "history_yiyin_borders"), existing: instance)
            }
        ))
        .accessibilityIdentifier("yiyin.toggle.adaptive")

        // D-08-CONTEXT-4 / D-08-3-T1-2: the manual one-click default entry
        // (yiyin config defaults: rate 90 / radius 2.1 / shadow 6 / solid
        // #fff — ONE discrete commit; the commit auto-enables the module).
        Button {
            applyBorders(BordersModule.Params(
                mode: .solid(color: "#ffffff"),
                mainImageWidthRate: 90,
                cornerRadius: 2.1,
                shadow: 6),
                label: String(localized: "history_yiyin_default_apply"),
                existing: instance)
        } label: {
            Label("panel_yiyin_apply_default", systemImage: "wand.and.stars")
        }
        .accessibilityIdentifier("yiyin.button.applyDefault")
    }

    private var aspectCases: [(BordersModule.AspectRatio, String)] {
        [
            (BordersModule.AspectRatio(w: 1, h: 1), "panel_yiyin_aspect_1_1"),
            (BordersModule.AspectRatio(w: 3, h: 2), "panel_yiyin_aspect_3_2"),
            (BordersModule.AspectRatio(w: 2, h: 3), "panel_yiyin_aspect_2_3"),
            (BordersModule.AspectRatio(w: 4, h: 3), "panel_yiyin_aspect_4_3"),
            (BordersModule.AspectRatio(w: 3, h: 4), "panel_yiyin_aspect_3_4"),
            (BordersModule.AspectRatio(w: 16, h: 9), "panel_yiyin_aspect_16_9"),
            (BordersModule.AspectRatio(w: 9, h: 16), "panel_yiyin_aspect_9_16"),
        ]
    }

    // MARK: the watermark parameters section

    private var watermarkSection: some View {
        Section("panel_yiyin_watermark_section") {
            if watermarkInstance != nil {
                watermarkControls
            } else {
                Button {
                    applyWatermark(
                        WatermarkModule.Params.neutralSeed, label:
                            String(localized: "history_yiyin_watermark"))
                } label: {
                    Label("panel_yiyin_add_watermark", systemImage: "plus")
                }
                .accessibilityIdentifier("yiyin.button.addWatermark")
            }
        }
    }

    @ViewBuilder
    private var watermarkControls: some View {
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
        Group {
            if watermarkInstance != nil {
                templateRows
            }
        }
    }

    private var templateRows: some View {
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
        guard let instance = watermarkInstance else { return nil }
        return PanelEditing.updated(instance, params: params, as: WatermarkModule.self)
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
        applyWatermark(params, label: label)
    }

    /// A watermark one-commit discrete write; a nil chain record MINTS a
    /// fresh instance (the manual-attach face, D-08-CONTEXT-4).
    private func applyWatermark(_ params: WatermarkModule.Params, label: String) {
        let record = watermarkInstance.flatMap {
            PanelEditing.updated($0, params: params, as: WatermarkModule.self)
        } ?? ModuleInstance(module: WatermarkModule.self, params: params)
        edit.applyDiscrete(record, label: label)
    }

    // MARK: the borders D-H1 legs (the twin family over BordersModule.Params)

    /// A borders live tick (zero history — the drag face).
    private func setBordersLive(_ p: BordersModule.Params, instance: ModuleInstance) {
        if let record = PanelEditing.updated(instance, params: p, as: BordersModule.self) {
            edit.update(record)
        }
    }

    /// A borders one-commit discrete write; a nil chain record MINTS a
    /// fresh instance (the manual-attach face, D-08-CONTEXT-4).
    private func applyBorders(
        _ p: BordersModule.Params, label: String, existing: ModuleInstance?
    ) {
        let record = existing.flatMap {
            PanelEditing.updated($0, params: p, as: BordersModule.self)
        } ?? ModuleInstance(module: BordersModule.self, params: p)
        edit.applyDiscrete(record, label: label)
    }
}

/// 08-2 T6/08-3 T1: the SAME dual-section panel dispatches for BOTH yiyin
/// ops — the provider pair differs only in the opName key (the dispatched
/// record routes through `YiyinPanelView.dispatched`; the sibling rides the
/// session lookup).
internal struct YiyinPanelProvider: IOPPanelProvider {
    var opName: String { WatermarkModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(YiyinPanelView(dispatched: instance, edit: edit))
    }
}

internal struct YiyinBordersPanelProvider: IOPPanelProvider {
    var opName: String { BordersModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(YiyinPanelView(dispatched: instance, edit: edit))
    }
}
