import LightamerCore
import LightamerIOP
import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────
// LUT panel (Plan 12-5 T5; M2-5-3 tree upgrade) — the IOP-COLOR-08
// Inspector surface:
//   • 导入 (NSOpenPanel .cube → the library store root, content-dedup)
//   • 库列表 (M2-5-3: subdirectory tree — root rows + collapsible
//     subdirectory groups, BuiltIn leading; manual refresh button;
//     opening the panel rescans. Selection writes the registry key)
//   • 应用色彩空间 (sRGB default / displayP3 / rec2020 / proPhotoLinear)
//   • 插值 (tetrahedral default / trilinear — 3D tables only)
//   • 1D hint (no-domain-key files default to the sRGB face, §6.6)
//   • missing-entry state (degraded reference → identity + toast, D-10)
//
// D-H1 wiring: pickers = applyDiscrete one-commit; values READ from the
// instance record. Panel discipline: stable accessibility identifiers +
// a11y labels + zh catalog keys the same round (L025 zh label).
// ─────────────────────────────────────────────────────────────────────────

internal struct LutPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var libraryRevision = 0
    @State private var statusLine: String?
    /// The remember toggle (KD-4 ③, session-level, default ON): when set,
    /// encoding-picker changes write back to the library entry.
    @State private var rememberEncodings = true

    private var params: Lut3dModule.Params {
        PanelEditing.params(of: instance, as: Lut3dModule.self)
            ?? Lut3dModule.Params()
    }

    private var store: LutLibraryStore { LutLibraryStore.shared }

    var body: some View {
        Form {
            Section {
                Button {
                    // L057/F-1 family (FINDING-F, .ips 2026-10-07-0937):
                    // runModal nested inside the button-action dispatch
                    // corrupted button-closure lifetimes on cancel
                    // (SIGSEGV in swift release_dealloc). Hop the panel
                    // out of the transaction — the 7a4a603 menu fix shape.
                    Task { importLut() }
                } label: {
                    Label(String(localized: "panel_lut_import"), systemImage: "square.stack.3d.up.badge.plus")
                }
                .accessibilityIdentifier("inspector.button.lut.import")

                // M2-5-3 (M2GRADE-05): the library picker is a subdirectory
                // TREE (own view — root rows + collapsible groups). The
                // missing-reference toast/identity semantics are untouched.
                LutLibraryTreeView(params: params) { key in
                    var p = params
                    p.lutName = key
                    // M3-1-01 (KD-4 ①): a remembered pair rides the SAME
                    // single applyDiscrete commit; no memory = the encoding
                    // fields stay nil (the default-pair semantics — nothing
                    // written, the existing-document byte contract).
                    if let key,
                        let entry = store.entry(named: key),
                        let memory = LutEncodingPanelLogic.rememberedPair(forSelection: key, entry: entry)
                    {
                        p.inputEncoding = memory.input
                        p.outputEncoding = memory.output
                    }
                    applyDiscrete(p)
                    if store.isMissing(key) {
                        edit.presentToast(String(localized: "toast_lut_missing"))
                    }
                }
                .id(libraryRevision)

                Picker(String(localized: "panel_lut_colorspace"), selection: colorspaceSelection) {
                    ForEach(LutColorspace.allCases, id: \.self) { cs in
                        Text(colorspaceLabel(cs)).tag(cs)
                    }
                }
                .accessibilityIdentifier("inspector.picker.lut.colorspace")

                // M3-1-01 (M2GRADE-08, KD-4): the authoring-encoding pair —
                // scene/display grouped, visible only for a selected 3D LUT.
                // Picker changes are one applyDiscrete commit each; the
                // remember toggle rides the same store write face.
                if LutEncodingPanelLogic.showsEncodingPickers(
                    lutName: params.lutName, is1D: is1D)
                {
                    Picker(String(localized: "panel_lut_encoding_input"), selection: inputEncodingSelection) {
                        LutEncodingPickerGroups()
                    }
                    .accessibilityIdentifier("inspector.picker.lut.encoding.input")

                    Picker(String(localized: "panel_lut_encoding_output"), selection: outputEncodingSelection) {
                        LutEncodingPickerGroups()
                    }
                    .accessibilityIdentifier("inspector.picker.lut.encoding.output")

                    Toggle(isOn: $rememberEncodings) {
                        Text(String(localized: "panel_lut_remember_encodings"))
                    }
                    .accessibilityIdentifier("inspector.toggle.lut.remember-encodings")
                }

                if showInterpolation {
                    Picker(String(localized: "panel_lut_interpolation"), selection: interpolationSelection) {
                        Text(String(localized: "panel_lut_interpolation_tetrahedral"))
                            .tag(LutInterpolation.tetrahedral)
                        Text(String(localized: "panel_lut_interpolation_trilinear"))
                            .tag(LutInterpolation.trilinear)
                    }
                    .accessibilityIdentifier("inspector.picker.lut.interpolation")
                }

                if is1D {
                    Text(String(localized: "panel_lut_1d_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inspector.text.lut.1d-hint")
                }

                if store.isMissing(params.lutName) {
                    Text(String(localized: "panel_lut_missing"))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("inspector.text.lut.missing")
                }

                if let statusLine {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("panel_lut_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.lut")
        .onAppear {
            // M2-5-3: opening the panel rescans (the manual-refresh story
            // — FSEvents watching stays a v2 idea); the revision bump
            // re-reads the library faces.
            store.rescan()
            libraryRevision += 1
        }
    }

    // MARK: - Derived state

    private var colorspaceSelection: Binding<LutColorspace> {
        Binding(
            get: { params.colorspace },
            set: { cs in
                var p = params
                p.colorspace = cs
                applyDiscrete(p)
            })
    }

    private var interpolationSelection: Binding<LutInterpolation> {
        Binding(
            get: { params.interpolation },
            set: { interp in
                var p = params
                p.interpolation = interp
                applyDiscrete(p)
            })
    }

    /// The encoding picker bindings (KD-4 ②③): get = the params value (or
    /// the default pair id); set = ONE applyDiscrete commit + the
    /// remember-toggle write-back (entry absent = typed no-op).
    private var inputEncodingSelection: Binding<LutEncodingId> {
        encodingSelection(keyPath: \.inputEncoding)
    }

    private var outputEncodingSelection: Binding<LutEncodingId> {
        encodingSelection(keyPath: \.outputEncoding)
    }

    private func encodingSelection(
        keyPath: WritableKeyPath<Lut3dModule.Params, LutEncodingId?>
    ) -> Binding<LutEncodingId> {
        Binding(
            get: { params[keyPath: keyPath] ?? .linearRec2020 },
            set: { newValue in
                var p = params
                p[keyPath: keyPath] = newValue
                applyDiscrete(p)
                if rememberEncodings, let key = p.lutName,
                    store.entry(named: key) != nil
                {
                    store.updateRememberedEncodings(
                        named: key,
                        to: LutEncodingPanelLogic.writeBackPair(for: p))
                }
            })
    }

    private var selectedEntry: LutLibraryStore.InstalledLut? {
        guard let name = params.lutName else { return nil }
        return store.entry(named: name)
    }

    private var is1D: Bool { selectedEntry?.is1D == true }

    /// The interpolation picker only makes sense for a 3D table (1D is
    /// piecewise-linear by definition).
    private var showInterpolation: Bool { selectedEntry?.is1D != true }

    private func colorspaceLabel(_ cs: LutColorspace) -> String {
        switch cs {
        case .sRGB: return String(localized: "panel_lut_cs_srgb")
        case .displayP3: return String(localized: "panel_lut_cs_p3")
        case .rec2020: return String(localized: "panel_lut_cs_rec2020")
        case .proPhotoLinear: return String(localized: "panel_lut_cs_prophoto")
        }
    }

    // MARK: - Actions

    private func importLut() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "panel_lut_import")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "cube") ?? .data
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let entry = try store.importLut(from: url)
            libraryRevision += 1
            statusLine = String(localized: "panel_lut_imported") + " " + entry.name
            // Select the freshly imported table.
            var p = params
            p.lutName = entry.name
            applyDiscrete(p)
        } catch {
            statusLine = String(localized: "panel_lut_import_failed") + " " + error.localizedDescription
        }
    }

    private func applyDiscrete(_ p: Lut3dModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: Lut3dModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_lut"))
        }
    }
}

// MARK: - Library tree (M2-5-3, M2GRADE-05)

/// The subdirectory tree replacing the flat library picker: a manual
/// refresh button, the "None" row, root-level rows, then one collapsible
/// group per subdirectory (BuiltIn leading — the seeded film set).
/// Selection writes the registry KEY (the root-relative path) into
/// params; a legacy bare-name reference still displays as selected
/// through the store's resolution face WITHOUT being rewritten.
internal struct LutLibraryTreeView: View {

    let params: Lut3dModule.Params
    /// The selection write face (the panel's applyDiscrete + toast).
    let onSelect: (String?) -> Void

    @State private var revision = 0
    @State private var collapsedGroups: Set<String> = []

    private var store: LutLibraryStore { LutLibraryStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "panel_lut_library"))
                Spacer()
                Button {
                    store.rescan()
                    revision += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("inspector.button.lut.refresh")
                .accessibilityLabel(String(localized: "panel_lut_refresh"))
                .help(String(localized: "panel_lut_refresh"))
            }
            .font(.callout)

            row(key: nil, label: String(localized: "panel_lut_none"))
            let groups = libraryGroups
            ForEach(groups.filter { $0.path.isEmpty }, id: \.path) { group in
                ForEach(group.keys, id: \.self) { key in
                    row(key: key, label: displayName(for: key, groups: groups))
                }
            }
            ForEach(groups.filter { !$0.path.isEmpty }, id: \.path) { group in
                DisclosureGroup(isExpanded: expansion(group.path)) {
                    ForEach(group.keys, id: \.self) { key in
                        row(key: key, label: displayName(for: key, groups: groups))
                    }
                } label: {
                    Text(verbatim: group.path)
                        .font(.callout)
                        .foregroundStyle(LightamerColors.textSecondary)
                }
            }
        }
        .accessibilityIdentifier("inspector.picker.lut.library")
    }

    private var libraryGroups: [LutLibraryStore.LibraryGroup] {
        _ = revision
        return store.libraryGroups()
    }

    /// Expanded-by-default disclosure state per subdirectory path (the
    /// collapsed set only records what the user folded).
    private func expansion(_ path: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(path) },
            set: { expanded in
                if expanded {
                    collapsedGroups.remove(path)
                } else {
                    collapsedGroups.insert(path)
                }
            })
    }

    /// One selectable tree row (the selected entry shows a checkmark).
    private func row(key: String?, label: String) -> some View {
        let selected = store.displayKey(for: params.lutName) == key
        return Button {
            onSelect(key)
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(LightamerColors.textPrimary)
                if selected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(LightamerColors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            key.map { "inspector.button.lut.entry.\($0)" } ?? "inspector.button.lut.none")
    }

    /// The row label: the TITLE suffix when present. When the same FILE
    /// NAME lives in more than one group (root vs subdirectories), the
    /// relative path takes over — the KD-1 display disambiguation.
    private func displayName(
        for key: String, groups: [LutLibraryStore.LibraryGroup]
    ) -> String {
        guard let entry = store.entry(named: key) else { return key }
        let collisions = groups
            .flatMap { $0.keys }
            .compactMap { store.entry(named: $0) }
            .filter { $0.name == entry.name }
        let base = collisions.count > 1 ? entry.resolvedRelativePath : entry.name
        if let title = entry.title, !title.isEmpty {
            return "\(title) (\(base))"
        }
        return base
    }
}

// MARK: - Encoding panel logic (M3-1-01, KD-4 — testable without a view)

/// The encoding-picker decision logic, extracted so the App-level tests
/// drive the exact functions the panel body calls (the panel test stance:
/// programmatic, no UI — the PanelWiringTests discipline).
enum LutEncodingPanelLogic {

    /// The picker visibility rule: a selected 3D LUT (1D tables have no
    /// authoring-encoding semantics — the KD-3 boundary).
    static func showsEncodingPickers(lutName: String?, is1D: Bool) -> Bool {
        lutName != nil && !is1D
    }

    /// The remembered pair a library selection loads into params (KD-4 ①):
    /// the entry's memory when present; nil = keep the fields unset (the
    /// default-pair semantics — nothing written).
    static func rememberedPair(
        forSelection key: String?, entry: LutLibraryStore.InstalledLut?
    ) -> RememberedEncodings? {
        guard key != nil, let entry else { return nil }
        return entry.rememberedEncodings
    }

    /// The pair written back on a remember-ON picker change: the CURRENT
    /// params pair (defaults filled in).
    static func writeBackPair(for params: Lut3dModule.Params) -> RememberedEncodings {
        RememberedEncodings(
            input: params.inputEncoding ?? .linearRec2020,
            output: params.outputEncoding ?? .linearRec2020)
    }
}

/// The scene/display grouped picker content (the Alcedo
/// editor_lut_encoding_model grouping; the row labels are the catalog
/// display names — technical names stay untranslated per the DRT panel
/// convention).
struct LutEncodingPickerGroups: View {
    var body: some View {
        Section(String(localized: "panel_lut_group_scene")) {
            ForEach(LutEncodingCatalog.sceneEncodings, id: \.id) { row in
                Text(verbatim: row.displayName).tag(row.id)
            }
        }
        Section(String(localized: "panel_lut_group_display")) {
            ForEach(LutEncodingCatalog.displayEncodings, id: \.id) { row in
                Text(verbatim: row.displayName).tag(row.id)
            }
        }
    }
}

internal struct LutPanelProvider: IOPPanelProvider {
    var opName: String { Lut3dModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LutPanelView(instance: instance, edit: edit))
    }
}
