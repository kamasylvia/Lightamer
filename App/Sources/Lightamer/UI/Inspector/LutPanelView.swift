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

    private var params: Lut3dModule.Params {
        PanelEditing.params(of: instance, as: Lut3dModule.self)
            ?? Lut3dModule.Params()
    }

    private var store: LutLibraryStore { LutLibraryStore.shared }

    var body: some View {
        Form {
            Section {
                Button {
                    importLut()
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

internal struct LutPanelProvider: IOPPanelProvider {
    var opName: String { Lut3dModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LutPanelView(instance: instance, edit: edit))
    }
}
