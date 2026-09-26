import LightamerCore
import LightamerIOP
import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────
// LUT panel (Plan 12-5 T5) — the IOP-COLOR-08 Inspector surface:
//   • 导入 (NSOpenPanel .cube → the library store, content-dedup)
//   • 库列表 (library picker → params.lutName; 无 = neutral blit)
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

                Picker(String(localized: "panel_lut_library"), selection: lutSelection) {
                    Text(String(localized: "panel_lut_none")).tag(String?.none)
                        .accessibilityLabel(String(localized: "panel_lut_none"))
                    ForEach(libraryNames, id: \.self) { name in
                        Text(displayName(name)).tag(String?(name))
                    }
                }
                .accessibilityIdentifier("inspector.picker.lut.library")

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
    }

    // MARK: - Derived state

    private var libraryNames: [String] {
        _ = libraryRevision  // view-scope rescan trigger after import
        return store.installedNames
    }

    private var lutSelection: Binding<String?> {
        Binding(
            get: { params.lutName },
            set: { name in
                var p = params
                p.lutName = name
                applyDiscrete(p)
                if store.isMissing(name) {
                    edit.presentToast(String(localized: "toast_lut_missing"))
                }
            })
    }

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

    private func displayName(_ name: String) -> String {
        if let entry = store.entry(named: name), let title = entry.title, !title.isEmpty {
            return "\(title) (\(name))"
        }
        return name
    }

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

internal struct LutPanelProvider: IOPPanelProvider {
    var opName: String { Lut3dModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LutPanelView(instance: instance, edit: edit))
    }
}
