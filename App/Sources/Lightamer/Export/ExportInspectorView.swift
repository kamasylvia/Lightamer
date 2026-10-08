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
                    sectionDivider
                    metadataColorSection
                    sectionDivider
                    sdrSection
                    sectionDivider
                    ExportQueueFaceView(
                        jobRows: exportState.jobRows,
                        progress: exportState.progress,
                        canRun: pageCanRun,
                        targetsCount: targets.count,
                        onRun: { runExport() },
                        onClear: { Task { await exportState.cancelAllJobs() } },
                        onRetry: { id in Task { await exportState.retryJob(id) } },
                        onCancel: { id in Task { await exportState.cancelJob(id) } })
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(LightamerColors.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.page.root")
        // The prepare leg (the Alcedo QML:271-288 lifecycle's load half):
        // the destination + quality memories seed ONCE per mount — the
        // body re-reads only the seeded state.
        .task {
            guard !memoryLoaded else { return }
            memoryLoaded = true
            model.destinationOverride = exportState.loadM2LastDirectory()
            if let key = model.qualityKeyForFormat,
                let remembered = exportState.loadM2Quality(forKey: key) {
                model.activeQuality = remembered
            }
        }
        // The lifecycle's off-page write-back half (OQ-10: the quality
        // knobs remember across sessions).
        .onDisappear {
            writeBackQualityMemory()
        }
    }

    /// The quality memory write-back face (run + off-page; no-op when the
    /// active format has no knob).
    func writeBackQualityMemory() {
        guard let writeback = model.qualityMemoryWriteback else { return }
        exportState.storeM2Quality(writeback.value, forKey: writeback.key)
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
            // M3-1-03 KD-1: the collision-tier Picker (the M2-9-VALIDATION
            // 挂账#4 close-out — the tier names stay technical identifiers,
            // 语言纪律). Session state per the model field's ruling.
            Picker(String(localized: "export_collision_label"), selection: $model.collisionPolicy) {
                Text(String(localized: "export_collision_increment"))
                    .tag(ExportNamer.ExportCollisionPolicy.increment)
                Text(String(localized: "export_collision_fail"))
                    .tag(ExportNamer.ExportCollisionPolicy.fail)
                Text(String(localized: "export_collision_replace"))
                    .tag(ExportNamer.ExportCollisionPolicy.replace)
            }
            .accessibilityIdentifier("export.page.collision")
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

    // MARK: - Section 5: the run face (KD-4 装配点)

    /// The M2 目标集 (KD-4): the grid selection when the shell armed the
    /// provider, else the currently edited image, else empty.
    private var targets: [URL] {
        exportState.m2Targets(currentImageURL: editorState.loadedImageURL)
    }

    /// The page's run gate: naming + sizing domains (the model) AND a
    /// non-empty target set AND a resolvable destination.
    private var pageCanRun: Bool {
        model.canRun && !targets.isEmpty && displayDestination != nil
    }

    /// The batch enqueue (the queue section's add face): the pure KD-4
    /// assembly first (the state-layer seam — the picker value + the live
    /// projection resolve WITHOUT I/O), then the pre-export sidecar flush
    /// (the panel-hops-through-environment legacy posture — the current
    /// image's pending writes land before the queue reads) and the enqueue.
    private func runExport() {
        let assembly = model.makeRunAssembly(
            targets: targets,
            loadedImageURL: editorState.loadedImageURL,
            instances: editorState.instances,
            effectiveDrtRecord: editorState.history.effectiveDrtRecord(),
            destination: displayDestination)
        guard let assembly else { return }
        let software = ExportState.currentExifSoftware
        Task {
            await pipeCoordinator.flushSidecar()
            do {
                try await exportState.enqueueExportM2(
                    images: assembly.batch,
                    instancesOverrides: assembly.overrides,
                    drtRecord: assembly.drtRecord,
                    variant: assembly.variant,
                    destination: assembly.destination,
                    subfolder: assembly.subfolder,
                    namingPattern: assembly.pattern,
                    collisionPolicy: assembly.collisionPolicy,
                    exifSoftware: software)
                // The lifecycle write-backs (OQ-3 导出发起写回 + OQ-10).
                exportState.storeM2LastDirectory(assembly.destination)
                writeBackQualityMemory()
            } catch {
                editorState.presentToast(String(localized: "export_enqueue_failed"))
            }
        }
    }

    // MARK: - Section 3: Metadata & Color (OQ-6 / OQ-7)

    private var metadataColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "export_metadata_section"))
                .font(.subheadline.weight(.semibold))
            Toggle(String(localized: "export_metadata_include"), isOn: $model.metadataOn)
                .accessibilityIdentifier("export.page.metadata")
            Text(String(localized: "export_metadata_note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(String(localized: "export_embed_icc"), isOn: $model.embedICC)
                .accessibilityIdentifier("export.page.embed_icc")
            if iccStripUnavailableNoteVisible {
                Text(String(localized: "export_embed_icc_unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("export.page.icc_unavailable")
            }
            drtReadout
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.section.metadata")
    }

    /// The OMIT 不可达档 note (M2-9-03 handoff): the strip is typed-
    /// unsupported inside HEIC/AVIF/WebP — with embedICC off on those
    /// containers the page says so instead of staying silent.
    private var iccStripUnavailableNoteVisible: Bool {
        !model.embedICC
            && (model.formatKind == .heic || model.formatKind == .avif
                || model.formatKind == .webp)
    }

    /// The DRT encoding triple readout (OQ-7's UI expression): space /
    /// EOTF / peak from the CURRENT image's effective record (nil history
    /// record = the default record face; no image = hidden). The values
    /// stay verbatim rawValues — technical identifiers (语言纪律).
    @ViewBuilder
    private var drtReadout: some View {
        if editorState.loadedImageURL != nil {
            let record = editorState.history.effectiveDrtRecord() ?? DrtRecord()
            HStack(spacing: 6) {
                Text(String(localized: "export_drt_readout"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    verbatim: "\(record.encodingSpace.rawValue) · "
                        + "\(record.encodingEotf.rawValue) · "
                        + "\(Int(record.peakLuminance)) nits")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("export.page.drt_readout")
        }
    }

    // MARK: - Section 4: SDR Export (KD-2 节 4 / OQ-10 / OQ-12)

    private var sdrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "export_sdr_section"))
                .font(.subheadline.weight(.semibold))

            Picker(String(localized: "export_format_label"), selection: formatSelection) {
                ForEach(ExportM2FormatKind.allCases) { kind in
                    // L058: build the lookup key as a plain String FIRST — an
                    // interpolated String.LocalizationValue literal makes the
                    // catalog key "export_format_%@" (silent raw-key fallback).
                    Text(String(localized: String.LocalizationValue("export_format_" + kind.rawValue)))
                        .tag(kind)
                }
            }
            .accessibilityIdentifier("export.page.format")

            formatKnobs

            Picker(String(localized: "export_sizing_label"), selection: $model.sizingMode) {
                ForEach(ExportM2PanelModel.SizingMode.allCases) { mode in
                    Text(String(localized: String.LocalizationValue(mode.labelKey)))
                        .tag(mode)
                }
            }
            .accessibilityIdentifier("export.page.sizing_mode")

            sizingFields

            if model.sizingViolation {
                Label(String(localized: "export_sizing_invalid"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityIdentifier("export.page.sizing_invalid")
            }

            DisclosureGroup(String(localized: "export_advanced")) {
                Toggle(String(localized: "export_allow_upscale"), isOn: $model.allowUpscale)
                    .accessibilityIdentifier("export.page.allow_upscale")
                TextField(
                    String(localized: "export_max_edge"),
                    value: $model.maximumEdgePixels,
                    format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("export.page.max_edge")
            }
            .font(.subheadline)
            .accessibilityIdentifier("export.page.advanced")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.section.sdr")
    }

    /// The format switch ALSO swaps the quality memory in (OQ-10: each
    /// knob remembers its own value — a kind change loads that kind's
    /// remembered quality).
    private var formatSelection: Binding<ExportM2FormatKind> {
        Binding(
            get: { model.formatKind },
            set: { kind in
                writeBackQualityMemory()
                model.formatKind = kind
                if let key = model.qualityKeyForFormat,
                    let remembered = exportState.loadM2Quality(forKey: key) {
                    model.activeQuality = remembered
                }
            })
    }

    @ViewBuilder
    private var formatKnobs: some View {
        if model.hasQualityKnob {
            HStack {
                Text(String(localized: "export_quality_label"))
                Slider(value: $model.activeQuality, in: 0...1)
                    .accessibilityIdentifier("export.page.quality")
                Text("\(Int((model.activeQuality * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        switch model.formatKind {
        case .jpeg:
            EmptyView()
        case .png:
            depthPicker(["8", "16"], uses16: model.pngBitDepth == .sixteen) {
                model.pngBitDepth = $0 == 1 ? .sixteen : .eight
            }
        case .tiff:
            depthPicker(
                ["8", "16", "32f"],
                uses16: model.tiffBitDepth == .sixteen,
                uses32f: model.tiffBitDepth == .float32
            ) { depth in
                switch depth {
                case 0: model.tiffBitDepth = .eight
                case 1: model.tiffBitDepth = .sixteen
                default: model.tiffBitDepth = .float32
                }
            }
            Picker(String(localized: "export_tiff_compression_label"), selection: $model.tiffCompression) {
                Text(String(localized: "export_tiff_compression_none"))
                    .tag(ExportFormatSpec.TIFFCompression.none)
                Text(String(localized: "export_tiff_compression_lzw"))
                    .tag(ExportFormatSpec.TIFFCompression.lzw)
                Text(String(localized: "export_tiff_compression_zip"))
                    .tag(ExportFormatSpec.TIFFCompression.zip)
            }
            .accessibilityIdentifier("export.page.tiff_compression")
        case .heic:
            depthPicker(["8", "10"], uses16: model.heicBitDepth == .ten) {
                model.heicBitDepth = $0 == 1 ? .ten : .eight
            }
        case .avif:
            depthPicker(
                ["8", "10", "12"],
                uses16: model.avifBitDepth == .ten,
                uses32f: model.avifBitDepth == .twelve
            ) { depth in
                switch depth {
                case 0: model.avifBitDepth = .eight
                case 1: model.avifBitDepth = .ten
                default: model.avifBitDepth = .twelve
                }
            }
        case .webp:
            Toggle(String(localized: "export_webp_lossless"), isOn: $model.webpLossless)
                .accessibilityIdentifier("export.page.webp_lossless")
        }
    }

    /// The bit-depth row (the labels are the bit faces; "uses16/uses32f"
    /// keep the per-format enum mapping in ONE helper).
    private func depthPicker(
        _ labels: [String], uses16: Bool, uses32f: Bool = false,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        let selection = uses32f ? 2 : (uses16 ? 1 : 0)
        return Picker(String(localized: "export_bit_depth_label"), selection: Binding(
            get: { selection },
            set: { onChange($0)
            })) {
            ForEach(labels.indices, id: \.self) { index in
                Text(verbatim: labels[index]).tag(index)
            }
        }
        .accessibilityIdentifier("export.page.bit_depth")
    }

    /// The per-mode sizing fields (the显隐 contract: only the active
    /// mode's fields render; the domain guards ride the model's
    /// `sizingViolation` face — out-of-range values disable run, never
    /// silently clamp).
    @ViewBuilder
    private var sizingFields: some View {
        switch model.sizingMode {
        case .original:
            EmptyView()
        case .longEdge:
            TextField(
                String(localized: "export_sizing_long_edge_px"),
                value: $model.longEdgePx,
                format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
                .accessibilityIdentifier("export.page.long_edge_px")
        case .bounds:
            HStack {
                TextField(
                    String(localized: "export_sizing_bounds_w"),
                    value: $model.boundsWidth,
                    format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("export.page.bounds_w")
                TextField(
                    String(localized: "export_sizing_bounds_h"),
                    value: $model.boundsHeight,
                    format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("export.page.bounds_h")
            }
        case .physical:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField(
                        String(localized: "export_sizing_physical_w"),
                        value: $model.physicalWidth,
                        format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("export.page.physical_w")
                    TextField(
                        String(localized: "export_sizing_physical_h"),
                        value: $model.physicalHeight,
                        format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("export.page.physical_h")
                    Picker(String(localized: "export_sizing_unit"), selection: $model.physicalUnit) {
                        Text(String(localized: "export_unit_millimeters"))
                            .tag(YiyinExportSettings.ExportPhysicalUnit.millimeters)
                        Text(String(localized: "export_unit_centimeters"))
                            .tag(YiyinExportSettings.ExportPhysicalUnit.centimeters)
                        Text(String(localized: "export_unit_inches"))
                            .tag(YiyinExportSettings.ExportPhysicalUnit.inches)
                    }
                    .accessibilityIdentifier("export.page.physical_unit")
                }
                TextField(
                    String(localized: "export_sizing_dpi"),
                    value: $model.physicalDpi,
                    format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("export.page.physical_dpi")
            }
        }
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

    // MARK: Destination (section 1)

    /// The picked directory (nil = the memory/first-use fallback face).
    var destinationOverride: URL?
    var subfolderEnabled = false
    var subfolderName = ""

    // MARK: Naming (section 2)

    /// The template pattern (the built-in `{source}` preset seeds the
    /// first-use face — Alcedo's default pattern).
    var pattern = NamingTemplateStore.builtIns[0].pattern

    /// The collision-tier session face (M3-1-03 KD-1): Increment default =
    /// the historical `-1/-2` behavior byte-identical; the picked tier rides
    /// the run assembly into `enqueueExportM2` — the ENGINE-zero-diff UI
    /// exposure that closes M2-9-VALIDATION 挂账#4. NOT persisted: the M2-9
    /// memory-key family stays at six keys (the DECISIONS 会话态裁定 —
    /// Alcedo remembers directory/quality only, the tier is per-session).
    var collisionPolicy: ExportNamer.ExportCollisionPolicy = .increment

    /// The naming validity gate (KD-3: an invalid pattern disables the
    /// page's run/add actions — the shared single gate).
    var namingInvalid: Bool {
        ExportNamingEditor.parseFeedback(pattern) != nil
    }

    /// The typed parse error for the feedback face (nil = valid).
    var namingError: ExportFileNameTemplateError? {
        ExportNamingEditor.parseFeedback(pattern)
    }

    // MARK: Metadata & Color (section 3, OQ-6/OQ-7)

    /// The single metadata switch (the Alcedo QML:609-626 face — the fine
    /// granularity stays in the model, the UI v1 keeps one switch; the
    /// fixed strips and the editing-summary packet default ride
    /// `ExportMetadataPolicy.standard`).
    var metadataOn = true

    /// The output-ICC face (Alcedo ExportIccPolicy): EMBED default.
    var embedICC = true

    /// The OQ-6 face: STANDARD while on, NONE while off (the six carrier
    /// bools keep their model defaults — the UI never touches them in v1).
    func makeMetadataPolicy() -> ExportMetadataPolicy {
        metadataOn ? .standard : .none
    }

    // MARK: SDR Export (section 4, OQ-10/OQ-12)

    /// The format picker face (the six-format matrix; the keys reuse the
    /// legacy `export_format_*` catalog family).
    var formatKind: ExportM2FormatKind = .jpeg

    /// The four quality knobs (one per lossy format — OQ-10 A's separate
    /// memories). First-use default 0.95 (the Alcedo 95/100 face; the
    /// memory keys override on load).
    var jpegQuality = 0.95
    var heicQuality = 0.95
    var avifQuality = 0.95
    var webpQuality = 0.95

    var pngBitDepth: ExportFormatSpec.PNGBitDepth = .eight
    var tiffBitDepth: ExportFormatSpec.TIFFBitDepth = .sixteen
    var tiffCompression: ExportFormatSpec.TIFFCompression = .none
    var heicBitDepth: ExportFormatSpec.HEICBitDepth = .eight
    var avifBitDepth: ExportFormatSpec.AVIFBitDepth = .ten
    var webpLossless = false

    /// The quality knob's memory key (OQ-10's registered spellings).
    var qualityKeyForFormat: String? {
        ExportState.qualityKeysByFormat[formatKind.rawValue]
    }

    /// The ACTIVE format's quality (the slider binds the per-format knob;
    /// PNG/TIFF have no knob — the face returns the JPEG value untouched).
    var activeQuality: Double {
        get {
            switch formatKind {
            case .jpeg: return jpegQuality
            case .heic: return heicQuality
            case .avif: return avifQuality
            case .webp: return webpQuality
            case .png, .tiff: return jpegQuality
            }
        }
        set {
            switch formatKind {
            case .jpeg: jpegQuality = newValue
            case .heic: heicQuality = newValue
            case .avif: avifQuality = newValue
            case .webp: webpQuality = newValue
            case .png, .tiff: break
            }
        }
    }

    var hasQualityKnob: Bool {
        switch formatKind {
        case .jpeg, .heic, .avif, .webp: return true
        case .png, .tiff: return false
        }
    }

    // MARK: The sizing four modes (KD-2 节 4 — the Alcedo mode face; the
    // yiyin superset modes shortEdge/percent stay on the legacy panel)

    /// The page's sizing modes (the Alcedo ExportResizeMode quartet).
    enum SizingMode: String, CaseIterable, Identifiable {
        case original
        case longEdge
        case bounds
        case physical
        var id: String { rawValue }
        var labelKey: String {
            switch self {
            case .original: return "export_sizing_original"
            case .longEdge: return "export_sizing_long_edge"
            case .bounds: return "export_sizing_bounds"
            case .physical: return "export_sizing_physical"
            }
        }
    }

    var sizingMode: SizingMode = .original

    // Alcedo QML:27-46 first-use field defaults (longEdge 2048 / bounds
    // 2048×2048 / physical 210×297 mm @ 300 dpi).
    var longEdgePx = 2048
    var boundsWidth = 2048
    var boundsHeight = 2048
    var physicalWidth: Double = 210
    var physicalHeight: Double = 297
    var physicalUnit: YiyinExportSettings.ExportPhysicalUnit = .millimeters
    var physicalDpi = 300

    // OQ-12: the advanced fold's two knobs (defaults false/0).
    var allowUpscale = false
    var maximumEdgePixels = 0

    /// The model-domain violation face (nil = every field in range). The
    /// UI pins the MODEL domains (1...100_000 px / 1...2400 DPI / physical
    /// 0.01...100_000 — plan KD-2 节 4: UI 按模型域禁越界值; the Alcedo
    /// QML's narrower domains are NOT the contract — 01 DECISIONS records
    /// the difference).
    var sizingViolation: Bool {
        let pixelCap = YiyinExportSettings.maxTargetPixels
        func inPxRange(_ value: Int) -> Bool { value >= 1 && value <= pixelCap }
        switch sizingMode {
        case .original:
            break
        case .longEdge:
            guard inPxRange(longEdgePx) else { return true }
        case .bounds:
            guard inPxRange(boundsWidth), inPxRange(boundsHeight) else { return true }
        case .physical:
            guard YiyinExportSettings.physicalSizeRange.contains(physicalWidth),
                YiyinExportSettings.physicalSizeRange.contains(physicalHeight)
            else { return true }
            guard YiyinExportSettings.dpiRange.contains(physicalDpi) else { return true }
        }
        guard maximumEdgePixels >= 0, maximumEdgePixels <= pixelCap else { return true }
        return false
    }

    // MARK: The assembly input faces (KD-4's panel half)

    /// The sizing model from the current mode/fields.
    func makeSizing() -> YiyinExportSettings {
        let mode: YiyinExportSettings.OutputMode
        switch sizingMode {
        case .original:
            mode = .original
        case .longEdge:
            mode = .longEdge(px: longEdgePx)
        case .bounds:
            mode = .bounds(w: boundsWidth, h: boundsHeight)
        case .physical:
            mode = .physical(
                width: physicalWidth, height: physicalHeight,
                unit: physicalUnit, dpi: physicalDpi)
        }
        return YiyinExportSettings(
            mode: mode, dpi: physicalDpi,
            allowUpscale: allowUpscale, maximumEdgePixels: maximumEdgePixels)
    }

    /// The format spec from the picker + the per-format knobs.
    func makeFormat() -> ExportFormatSpec {
        switch formatKind {
        case .jpeg: return .jpeg(quality: jpegQuality)
        case .png: return .png(bitDepth: pngBitDepth)
        case .tiff: return .tiff(bitDepth: tiffBitDepth, compression: tiffCompression)
        case .heic: return .heic(quality: heicQuality, bitDepth: heicBitDepth)
        case .avif: return .avif(quality: avifQuality, bitDepth: avifBitDepth)
        case .webp: return .webp(quality: webpQuality, lossless: webpLossless)
        }
    }

    /// The variant the assembly consumes (KD-4): sizing × format + the
    /// metadata/ICC policy. The DRT record rides the assembly (T3) — the
    /// panel hands it over per run.
    func makeVariant() -> ExportVariant {
        ExportVariant(
            sizing: makeSizing(),
            format: makeFormat(),
            metadataPolicy: makeMetadataPolicy(),
            embedICC: embedICC)
    }

    /// The run-face assembly bundle (M3-1-03 KD-1): everything the queue
    /// enqueue consumes, resolved in ONE pure step — the state-layer seam
    /// that makes the collision-picker→queue path testable (the M2-9-04
    /// view-independent-faces discipline).
    struct RunAssembly {
        let batch: [URL]
        let overrides: [[ModuleInstance]?]
        let drtRecord: DrtRecord
        let variant: ExportVariant
        let pattern: String
        let collisionPolicy: ExportNamer.ExportCollisionPolicy
        let destination: URL
        let subfolder: String?
    }

    /// The run assembly (KD-4's panel half + M3-1-03 KD-1): the OPEN image
    /// rides the live projection (the same set a flush would persist);
    /// every other batch image keeps its DISK sidecar truth (nil override).
    /// The DRT record is the current image's effective face — `?? DrtRecord()`
    /// default. nil = the run-gate miss (empty targets / no destination).
    func makeRunAssembly(
        targets: [URL],
        loadedImageURL: URL?,
        instances: [ModuleInstance],
        effectiveDrtRecord: DrtRecord?,
        destination: URL?
    ) -> RunAssembly? {
        guard !targets.isEmpty, let destination else { return nil }
        let subfolder: String? = {
            guard subfolderEnabled else { return nil }
            let trimmed = subfolderName.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let overrides: [[ModuleInstance]?] = targets.map { url in
            (url.path == loadedImageURL?.path) ? instances : nil
        }
        return RunAssembly(
            batch: targets,
            overrides: overrides,
            drtRecord: effectiveDrtRecord ?? DrtRecord(),
            variant: makeVariant(),
            pattern: pattern,
            collisionPolicy: collisionPolicy,
            destination: destination,
            subfolder: subfolder)
    }

    /// The quality write-back snapshot: (key, value) for the ACTIVE format
    /// (the Alcedo lifecycle: the page writes on run + off-page — only the
    /// knob the user saw has a value worth remembering).
    var qualityMemoryWriteback: (key: String, value: Double)? {
        guard hasQualityKnob, let key = qualityKeyForFormat else { return nil }
        return (key, activeQuality)
    }

    /// The run gate (additive ANDs as sections land: naming + sizing; T3
    /// adds the targets/destination legs).
    var canRun: Bool {
        !namingInvalid && !sizingViolation
    }
}

/// The M2 page's format kinds (the six-format matrix; the rawValues are
/// the legacy `export_format_*` catalog key suffixes AND the memory-key
/// map's spellings).
enum ExportM2FormatKind: String, CaseIterable, Identifiable {
    case jpeg, png, tiff, heic, avif, webp
    var id: String { rawValue }
}
