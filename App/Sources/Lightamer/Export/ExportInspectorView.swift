import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ExportInspectorView (Plan M2-9-04, OQ-1 A / KD-2) — the M2 Inspector Export
// page: the Alcedo `ExportInspectorPanel` five-section face in the Inspector
// column (the legacy sheet stays byte-frozen behind the gate; this page is
// the M2 face's ONLY export surface).
//
//   1. Destination — directory (+ memory write-back, OQ-3) + subfolder
//      (default OFF, localized default copy, OQ-11) + the effective path;
//   2. File Naming — the template editor (KD-3 / OQ-9);
//   3. Metadata & Color — the single metadata switch + ICC EMBED/OMIT +
//      the DRT encoding readout (OQ-6/OQ-7);
//   4. SDR Export — format/depth/quality (memory four, OQ-10) + the sizing
//      four modes + the advanced fold (OQ-12);
//   5. Queue — the four-state rows + progress (KD-2 节 5).
//
// Injection discipline (KD-4): this body NEVER reads UserDefaults — the
// memory keys ride `ExportState`'s injected-defaults faces (D-EXEC-1); the
// naming store is the injected `NamingTemplateStore` face.
// ─────────────────────────────────────────────────────────────────────────────

internal struct ExportInspectorView: View {

    @Environment(ExportState.self) private var exportState
    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(InspectorState.self) private var inspectorState

    /// The page's panel state (the Alcedo prepare/lifecycle host — view
    /// scope, NOT ExportState: the state object stays view-independent).
    @State private var model = ExportM2PanelModel()
    @State private var templateStore = NamingTemplateStore()
    @State private var memoryLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    destinationSection
                    sectionDivider
                    namingSection
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(LightamerColors.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.page.root")
        // The prepare leg (the Alcedo QML:271-288 lifecycle's load half):
        // the destination memory seeds ONCE per mount — the body re-reads
        // only the seeded state.
        .task {
            guard !memoryLoaded else { return }
            memoryLoaded = true
            model.destinationOverride = exportState.loadM2LastDirectory()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(String(localized: "export_panel_title"))
                .font(.headline)
            Spacer()
            Button {
                inspectorState.closeExportPage()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.page.close")
            .accessibilityLabel(Text(String(localized: "export_page_close")))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 6)
    }

    // MARK: - Section 1: Destination (OQ-3 / OQ-11)

    @ViewBuilder
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "export_destination_section"))
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(displayDestination?.path ?? String(localized: "export_m2_no_destination"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "export_choose_directory")) {
                    chooseDestination()
                }
                .accessibilityIdentifier("export.page.choose_directory")
                if model.destinationOverride != nil {
                    Button(String(localized: "export_destination_reset")) {
                        model.destinationOverride = nil
                    }
                    .accessibilityIdentifier("export.page.reset_destination")
                }
            }
            Toggle(String(localized: "export_destination_subfolder"), isOn: subfolderToggle)
                .accessibilityIdentifier("export.page.subfolder")
            if model.subfolderEnabled {
                TextField(
                    String(localized: "export_destination_subfolder_name"),
                    text: $model.subfolderName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("export.page.subfolder_name")
            }
            Text(verbatim: effectiveOutDirectory?.path ?? "—")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("export.page.effective_destination")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.section.destination")
    }

    /// The OQ-11 default copy arms when the toggle turns ON with an empty
    /// name (zh「导出」/ en "Processed" — the String Catalog双语 default).
    private var subfolderToggle: Binding<Bool> {
        Binding(
            get: { model.subfolderEnabled },
            set: { on in
                model.subfolderEnabled = on
                if on, model.subfolderName.isEmpty {
                    model.subfolderName = String(
                        localized: "export_destination_default_subfolder")
                }
            })
    }

    /// The display face: the picked override, else the seeded memory, else
    /// the first-use fallback (the first target's directory — OQ-3). nil =
    /// no memory AND no targets (the run gate stays disabled).
    private var displayDestination: URL? {
        model.destinationOverride ?? exportState.m2EffectiveDestination(
            firstTargetDirectory: firstTargetDirectory)
    }

    private var firstTargetDirectory: URL? {
        exportState.m2Targets(currentImageURL: editorState.loadedImageURL)
            .first?.deletingLastPathComponent()
    }

    /// The joined landing path (the Alcedo QML:84-89 effectiveOutDir face —
    /// display only; the queue's `landingDirectory` join is the write-side
    /// single source).
    private var effectiveOutDirectory: URL? {
        guard let base = displayDestination else { return nil }
        let trimmed = model.subfolderName.trimmingCharacters(in: .whitespaces)
        guard model.subfolderEnabled, !trimmed.isEmpty else { return base }
        return base.appendingPathComponent(trimmed, isDirectory: true)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.destinationOverride = url
            // OQ-3: the picker write-back (the memory key updates NOW, not
            // only on run — Alcedo's outDir memory lifecycle).
            exportState.storeM2LastDirectory(url)
        }
    }

    // MARK: - Section 2: File Naming (OQ-9 / KD-3)

    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "export_naming_section"))
                .font(.subheadline.weight(.semibold))
            ExportNamingEditor(
                pattern: $model.pattern,
                sampleStem: sampleStem,
                store: templateStore)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.section.naming")
    }

    /// The live-preview sample: the queue's first row name, else the
    /// current image's stem (KD-3).
    private var sampleStem: String? {
        if let first = exportState.jobRows.first {
            return first.imageURL.lastPathComponent
        }
        return editorState.loadedImageURL?
            .deletingPathExtension()
            .lastPathComponent
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExportM2PanelModel — the page's panel state (KD-2/KD-4). Pure panel face:
// the destination/naming/editing values live here; the ASSEMBLY input face
// (makeVariant / policy / quality memory write-back) grows with sections
// 3-5. The view-independent faces are the state-layer test target (KD-5).
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class ExportM2PanelModel {

    // Destination (section 1)
    /// The picked directory (nil = the memory/first-use fallback face).
    var destinationOverride: URL?
    var subfolderEnabled = false
    var subfolderName = ""

    // Naming (section 2)
    /// The template pattern (the built-in `{source}` preset seeds the
    /// first-use face — Alcedo's default pattern).
    var pattern = NamingTemplateStore.builtIns[0].pattern

    /// The naming validity gate (KD-3: an invalid pattern disables the
    /// page's run/add actions — the shared single gate).
    var namingInvalid: Bool {
        ExportNamingEditor.parseFeedback(pattern) != nil
    }

    /// The typed parse error for the feedback face (nil = valid).
    var namingError: ExportFileNameTemplateError? {
        ExportNamingEditor.parseFeedback(pattern)
    }

    /// The run gate as sections stand (T2 adds the sizing/domain leg; T3
    /// adds the targets/destination legs — additive ANDs).
    var canRun: Bool {
        !namingInvalid
    }
}
