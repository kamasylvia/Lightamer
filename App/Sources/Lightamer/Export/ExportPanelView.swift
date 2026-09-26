import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ExportPanelView (Plan 11-04 T4, EXP-03/04/07 面向面) — the export sheet.
//
//   • recipe INLINE EDITING (D-11-CONTEXT-3: memory-only, no persistence):
//     add/remove variants; per variant the sizing mode (original / long
//     edge / short edge — bound to the shared `YiyinExportSettings` model
//     per OQ-11-6 / percent — bound to `ExportVariant.scalePercent` per
//     EXP-03), DPI, the format spec (six formats, per-format knobs only),
//     the five-choice color space, the yiyin switch, and an explicit tag.
//   • ONE queue action: the selection (browser multi-select, else the
//     currently edited image) × M variants → N×M jobs in a single call
//     (EXP-07). The pre-export sidecar flush rides the panel's OWN
//     environment (D-03b: ExportState never touches the pipe).
//   • queue status: the two-layer progress + per-job rows with inline
//     errors, cancel + retry (OQ-11-4).
//   • the R4 large-TIFF warning slot (32f TIFF ≈ +1.6 GB at 100 MP).
//
// L010 discipline: `.accessibilityIdentifier` (never a container label)
// with stable `export.*` dotted keys; every user-facing string rides the
// catalog (L025 zh labels).
// ─────────────────────────────────────────────────────────────────────────────

internal struct ExportPanelView: View {

    let browserModel: SessionBrowserModel

    @Environment(ExportState.self) private var exportState
    @Environment(SessionState.self) private var sessionState
    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var exportState = exportState
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "export_panel_title"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("export.button.close")
            }
            .padding()

            Form {
                recipeSection($exportState)
                destinationSection
                postActionsSection
                queueActionSection
                queueStatusSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 640)
    }

    // MARK: - Recipe (variants inline editing)

    private func recipeSection(_ state: Bindable<ExportState>) -> some View {
        Section(String(localized: "export_recipe_section")) {
            ForEach(state.recipe.indices, id: \.self) { index in
                VariantEditor(
                    variant: state.recipe[index],
                    variantNumber: index + 1,
                    onDelete: exportState.recipe.count > 1
                        ? { exportState.recipe.remove(at: index) } : nil
                )
            }
            .accessibilityIdentifier("export.list.variants")

            Button {
                exportState.recipe.append(ExportState.defaultVariant)
            } label: {
                Label(String(localized: "export_add_variant"), systemImage: "plus")
            }
            .accessibilityIdentifier("export.button.add_variant")

            if recipeHasFloat32TIFF {
                Label(
                    String(localized: "export_large_tiff_warning"),
                    systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                    .accessibilityIdentifier("export.warning.large_tiff")
            }
        }
    }

    private var recipeHasFloat32TIFF: Bool {
        exportState.recipe.contains { variant in
            if case .tiff(.float32, _) = variant.format { return true }
            return false
        }
    }

    // MARK: - Destination

    private var destinationSection: some View {
        Section(String(localized: "export_destination_section")) {
            HStack {
                Text(displayDestination)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "export_choose_directory")) {
                    chooseDestination()
                }
                .accessibilityIdentifier("export.button.choose_directory")
                if exportState.customDestination != nil {
                    Button(String(localized: "export_destination_reset")) {
                        exportState.customDestination = nil
                    }
                    .accessibilityIdentifier("export.button.reset_destination")
                }
            }
        }
    }

    private var displayDestination: String {
        if let custom = exportState.customDestination {
            return custom.path
        }
        guard let root = sessionState.currentSessionURL else {
            return String(localized: "export_no_session")
        }
        return ExportFileWriter.defaultDestination(for: root).path
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            exportState.customDestination = url
        }
    }

    // MARK: - Post-export actions (EXP-08, D-11-CONTEXT-6)

    private var postActionsSection: some View {
        Section(String(localized: "export_postactions_section")) {
            Toggle(
                String(localized: "export_postactions_run_script"),
                isOn: Binding(
                    get: { PostExportActions.wantsRunScript },
                    set: { PostExportActions.wantsRunScript = $0 }))
                .accessibilityIdentifier("export.toggle.postaction_script")

            HStack {
                Text(scriptDisplayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "export_postactions_choose_script")) {
                    chooseScript()
                }
                .accessibilityIdentifier("export.button.choose_script")
                if PostExportActions.scriptBookmark != nil {
                    Button(String(localized: "export_postactions_clear_script")) {
                        PostExportActions.scriptBookmark = nil
                    }
                    .accessibilityIdentifier("export.button.clear_script")
                }
            }

            Toggle(
                String(localized: "export_postactions_reveal"),
                isOn: Binding(
                    get: { PostExportActions.wantsRevealInFinder },
                    set: { PostExportActions.wantsRevealInFinder = $0 }))
                .accessibilityIdentifier("export.toggle.postaction_reveal")

            Text(String(localized: "export_postactions_script_note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scriptDisplayName: String {
        guard let url = PostExportActions.resolveScript() else {
            return String(localized: "export_postactions_no_script")
        }
        return url.path
    }

    /// The script pick — BY PATH (an executable FILE), never an inline
    /// command string (D-11-CONTEXT-6). A plain bookmark persists it.
    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "export_postactions_pick_message")
        if panel.runModal() == .OK, let url = panel.url {
            PostExportActions.storeScript(url)
        }
    }

    // MARK: - The queue action (EXP-07)

    private var queueActionSection: some View {
        Section {
            Button {
                runExport()
            } label: {
                Label(String(localized: "export_button"), systemImage: "square.and.arrow.up")
            }
            .disabled(!canExport)
            .accessibilityIdentifier("export.button.run")
        } header: {
            Text(exportTargetsSummary)
        }
    }

    private var canExport: Bool {
        // F-11-04-1: gate on the ACTUAL targets (not merely "an image is
        // loaded") — a loaded image outside the session (or a symlink-
        // spelling mismatch) must NOT leave the run button enabled with an
        // empty enqueue behind it.
        sessionState.currentSessionURL != nil && !exportTargetRelPaths.isEmpty
    }

    private var exportTargetsSummary: String {
        let count = exportTargetRelPaths.count
        return String(localized: "export_targets_header \(count) \(exportState.recipe.count)")
    }

    /// The export targets: the browser selection when one exists (the
    /// grid/culling multi-select), otherwise the currently edited image.
    /// The spelling-tolerant prefix match lives on ExportState
    /// (F-11-04-1, unit-tested there).
    private var exportTargetRelPaths: [String] {
        ExportState.targetRelPaths(
            selection: browserModel.selectedOrderedPaths,
            loadedImageURL: editorState.loadedImageURL,
            sessionRoot: sessionState.currentSessionURL)
    }

    private func runExport() {
        let relPaths = exportTargetRelPaths
        guard !relPaths.isEmpty, let root = sessionState.currentSessionURL else { return }
        // The pre-export sidecar flush rides the PANEL's environment
        // (D-03b): the edited image's pending writes land BEFORE the queue
        // reads the disk truth.
        Task {
            await pipeCoordinator.flushSidecar()
            let canvas = editorState.image.map {
                SIMD2(Int($0.ciImage.extent.width), Int($0.ciImage.extent.height))
            }
            let images = relPaths.map { rel in
                (url: root.appendingPathComponent(rel), relPath: rel)
            }
            do {
                try await exportState.enqueueExport(images: images, canvasSize: canvas)
            } catch {
                editorState.presentToast(String(localized: "export_enqueue_failed"))
            }
        }
    }

    // MARK: - Queue status (OQ-11-4 per-job rows)

    @ViewBuilder
    private var queueStatusSection: some View {
        Section(String(localized: "export_queue_section")) {
            if exportState.progress.total == 0 {
                Text(String(localized: "export_queue_idle"))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    ProgressView(
                        value: Double(exportState.progress.done),
                        total: Double(max(exportState.progress.total, 1)))
                    Text("\(exportState.progress.done)/\(exportState.progress.total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let phase = exportState.progress.activePhase {
                        Text(
                            phase == .rendering
                                ? String(localized: "export_job_state_rendering")
                                : String(localized: "export_job_state_encoding")
                        )
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                }
                .accessibilityIdentifier("export.progress.overall")

                Button(String(localized: "export_cancel_all")) {
                    Task { await exportState.cancelAllJobs() }
                }
                .accessibilityIdentifier("export.button.cancel_all")

                ForEach(exportState.jobRows, id: \.id) { row in
                    JobRow(
                        row: row,
                        onRetry: { Task { await exportState.retryJob(row.id) } },
                        onCancel: { Task { await exportState.cancelJob(row.id) } })
                }
            }
        }
    }
}

// MARK: - One variant's editor row

private struct VariantEditor: View {

    @Binding var variant: ExportVariant
    let variantNumber: Int
    let onDelete: (() -> Void)?

    private var sizingBinding: Binding<ExportPanelViewSizingKind> {
        Binding(
            get: {
                if variant.scalePercent != nil { return .percent }
                switch variant.sizing.mode {
                case .original: return .original
                case .longEdge: return .longEdge
                case .shortEdge: return .shortEdge
                }
            },
            set: { kind in
                switch kind {
                case .original:
                    variant.scalePercent = nil
                    variant.sizing.mode = .original
                case .longEdge:
                    variant.scalePercent = nil
                    variant.sizing.mode = .longEdge(px: currentLongEdgeValue)
                case .shortEdge:
                    variant.scalePercent = nil
                    variant.sizing.mode = .shortEdge(px: currentShortEdgeValue)
                case .percent:
                    variant.scalePercent = variant.scalePercent ?? 100
                }
            })
    }

    private var currentLongEdgeValue: Int {
        if case .longEdge(let px) = variant.sizing.mode { return px }
        return 2048
    }

    private var currentShortEdgeValue: Int {
        if case .shortEdge(let px) = variant.sizing.mode { return px }
        return 1080
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("#\(variantNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let onDelete {
                        Button(role: .destructive) { onDelete() } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("export.button.remove_variant")
                    }
                }

                // ── sizing (OQ-11-6: the SAME YiyinExportSettings model) ─
                Picker(String(localized: "export_sizing_label"), selection: sizingBinding) {
                    ForEach(ExportPanelViewSizingKind.allCases) { kind in
                        Text(String(localized: String.LocalizationValue(kind.titleKey)))
                            .tag(kind)
                    }
                }
                .accessibilityIdentifier("export.picker.sizing")

                switch sizingBinding.wrappedValue {
                case .longEdge:
                    TextField(
                        String(localized: "export_sizing_long_edge_px"),
                        value: pxBinding(.longEdgeFallback), format: .number.grouping(.never))
                        .frame(width: 110)
                        .accessibilityIdentifier("export.field.long_edge_px")
                case .shortEdge:
                    TextField(
                        String(localized: "export_sizing_short_edge_px"),
                        value: pxBinding(.shortEdgeFallback), format: .number.grouping(.never))
                        .frame(width: 110)
                        .accessibilityIdentifier("export.field.short_edge_px")
                case .percent:
                    TextField(
                        String(localized: "export_sizing_percent_value"),
                        value: percentBinding, format: .number.precision(.fractionLength(0...2)))
                        .frame(width: 110)
                        .accessibilityIdentifier("export.field.scale_percent")
                case .original:
                    EmptyView()
                }

                TextField(
                    String(localized: "export_sizing_dpi"),
                    value: dpiBinding, format: .number.grouping(.never))
                    .frame(width: 110)
                    .accessibilityIdentifier("export.field.dpi")

                // ── format ──────────────────────────────────────────────
                Picker(
                    String(localized: "export_format_label"),
                    selection: formatKindBinding
                ) {
                    ForEach(ExportPanelViewFormatKind.allCases) { kind in
                        Text(String(localized: String.LocalizationValue(kind.titleKey)))
                            .tag(kind)
                    }
                }
                .accessibilityIdentifier("export.picker.format")

                formatSpecificRows

                // ── color space (five choices, EXP-04) ──────────────────
                Picker(String(localized: "export_color_space_label"), selection: $variant.colorSpace) {
                    ForEach(ExportColorSpace.allCases, id: \.self) { space in
                        Text(space.rawValue).tag(space)
                    }
                }
                .accessibilityIdentifier("export.picker.color_space")

                // ── yiyin switch (EXP-05 shared config) ─────────────────
                Toggle(String(localized: "export_yiyin_toggle"), isOn: $variant.yiyin)
                    .accessibilityIdentifier("export.toggle.yiyin")

                // ── explicit tag (D-11-CONTEXT-4) ───────────────────────
                TextField(
                    String(localized: "export_output_tag_hint"),
                    text: tagBinding)
                    .accessibilityIdentifier("export.field.output_tag")
            }
        }
        .accessibilityIdentifier("export.group.variant_\(variantNumber)")
    }

    /// The format-kind picker face: reading projects the payload enum to
    /// its kind; switching swaps in that kind's DEFAULT spec (the user then
    /// tunes the knobs in the per-kind rows).
    private var formatKindBinding: Binding<ExportPanelViewFormatKind> {
        Binding(
            get: {
                switch variant.format {
                case .jpeg: return .jpeg
                case .png: return .png
                case .tiff: return .tiff
                case .heic: return .heic
                case .avif: return .avif
                case .webp: return .webp
                }
            },
            set: { kind in
                switch kind {
                case .jpeg: variant.format = .jpeg(quality: 0.9)
                case .png: variant.format = .png(bitDepth: .eight)
                case .tiff: variant.format = .tiff(bitDepth: .sixteen, compression: .zip)
                case .heic: variant.format = .heic(quality: 0.9, bitDepth: .eight)
                case .avif: variant.format = .avif(quality: 0.9, bitDepth: .ten)
                case .webp: variant.format = .webp(quality: 0.9, lossless: false)
                }
            })
    }

    // MARK: format knobs (per format — no cross-format soup)

    @ViewBuilder
    private var formatSpecificRows: some View {
        switch variant.format {
        case .jpeg(let quality):
            qualitySlider(quality) { variant.format = .jpeg(quality: $0) }
        case .heic(let quality, let depth):
            qualitySlider(quality) { variant.format = .heic(quality: $0, bitDepth: depth) }
            depthPicker(["8", "10"], selection: depth == .eight ? 0 : 1) { index in
                variant.format = .heic(
                    quality: quality, bitDepth: index == 0 ? .eight : .ten)
            }
        case .avif(let quality, let depth):
            qualitySlider(quality) { variant.format = .avif(quality: $0, bitDepth: depth) }
            depthPicker(
                ["8", "10", "12"],
                selection: [.eight, .ten, .twelve].firstIndex(of: depth) ?? 0
            ) { index in
                let depths: [ExportFormatSpec.AVIFBitDepth] = [.eight, .ten, .twelve]
                variant.format = .avif(quality: quality, bitDepth: depths[index])
            }
        case .png(let depth):
            depthPicker(["8", "16"], selection: depth == .eight ? 0 : 1) { index in
                variant.format = .png(bitDepth: index == 0 ? .eight : .sixteen)
            }
        case .tiff(let depth, let compression):
            depthPicker(
                ["8", "16", "f32"],
                selection: [.eight, .sixteen, .float32].firstIndex(of: depth) ?? 0
            ) { index in
                let depths: [ExportFormatSpec.TIFFBitDepth] = [.eight, .sixteen, .float32]
                variant.format = .tiff(bitDepth: depths[index], compression: compression)
            }
            Picker(
                String(localized: "export_tiff_compression_label"),
                selection: tiffCompressionBinding
            ) {
                Text(String(localized: "export_tiff_compression_none")).tag(0)
                Text(String(localized: "export_tiff_compression_lzw")).tag(1)
                Text(String(localized: "export_tiff_compression_zip")).tag(2)
            }
            .accessibilityIdentifier("export.picker.tiff_compression")
        case .webp(let quality, let lossless):
            qualitySlider(quality) { variant.format = .webp(quality: $0, lossless: lossless) }
            Toggle(
                String(localized: "export_webp_lossless"),
                isOn: Binding(
                    get: { lossless },
                    set: { variant.format = .webp(quality: quality, lossless: $0) }))
                .accessibilityIdentifier("export.toggle.webp_lossless")
        }
    }

    private func qualitySlider(_ quality: Double, setter: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(String(localized: "export_quality_label"))
            Slider(value: Binding(get: { quality }, set: setter), in: 0...1)
                .accessibilityIdentifier("export.slider.quality")
            Text("\(Int((quality * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func depthPicker(
        _ labels: [String], selection: Int, setter: @escaping (Int) -> Void
    ) -> some View {
        Picker(String(localized: "export_bit_depth_label"), selection: Binding(get: { selection }, set: setter)) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index]).tag(index)
            }
        }
        .accessibilityIdentifier("export.picker.bit_depth")
    }

    private var tiffCompressionBinding: Binding<Int> {
        Binding(
            get: {
                switch variant.format {
                case .tiff(_, .none): return 0
                case .tiff(_, .lzw): return 1
                case .tiff(_, .zip): return 2
                default: return 0
                }
            },
            set: { index in
                if case .tiff(let depth, _) = variant.format {
                    let compression: ExportFormatSpec.TIFFCompression =
                        [.none, .lzw, .zip][index]
                    variant.format = .tiff(bitDepth: depth, compression: compression)
                }
            })
    }

    private var dpiBinding: Binding<Int> {
        Binding(
            get: { variant.sizing.dpi },
            set: { variant.sizing.dpi = $0 })
    }

    private var percentBinding: Binding<Double> {
        Binding(
            get: { variant.scalePercent ?? 100 },
            set: { variant.scalePercent = $0 })
    }

    /// The px value face for the long/short-edge modes. `.longEdgeFallback`
    /// distinguishes the two modes inside one helper (an enum switch at the
    /// KeyPath site is not expressible — this is the typed sugar).
    private func pxBinding(_ face: ExportPanelPxFace) -> Binding<Int> {
        Binding(
            get: {
                switch (face, variant.sizing.mode) {
                case (_, .longEdge(let px)): return px
                case (_, .shortEdge(let px)): return px
                case (.longEdgeFallback, _): return 2048
                case (.shortEdgeFallback, _): return 1080
                }
            },
            set: { px in
                switch face {
                case .longEdgeFallback: variant.sizing.mode = .longEdge(px: px)
                case .shortEdgeFallback: variant.sizing.mode = .shortEdge(px: px)
                }
            })
    }

    private var tagBinding: Binding<String> {
        Binding(
            get: { variant.outputTag ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                variant.outputTag = trimmed.isEmpty ? nil : trimmed
            })
    }
}

// The panel-local picker faces (kept OUT of ExportPanelView's namespace so
// the private VariantEditor can name them without nesting scoping dances).
private enum ExportPanelViewSizingKind: String, CaseIterable, Identifiable {
    case original, longEdge, shortEdge, percent
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .original: "export_sizing_original"
        case .longEdge: "export_sizing_long_edge"
        case .shortEdge: "export_sizing_short_edge"
        case .percent: "export_sizing_percent"
        }
    }
}

private enum ExportPanelViewFormatKind: String, CaseIterable, Identifiable {
    case jpeg, png, tiff, heic, avif, webp
    var id: String { rawValue }
    var titleKey: String { "export_format_\(rawValue)" }
}

private enum ExportPanelPxFace {
    case longEdgeFallback
    case shortEdgeFallback
}

// MARK: - One job row

private struct JobRow: View {
    let row: ExportJobSnapshot
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: stateIcon)
                .foregroundStyle(stateColor)
                .accessibilityIdentifier("export.job.icon_\(row.id.uuidString)")
            Text(row.imageURL.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(variantLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if case .failed(let error) = row.state {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button(String(localized: "export_retry")) { onRetry() }
                    .accessibilityIdentifier("export.button.retry")
            } else if !row.state.isTerminal {
                Button(String(localized: "export_cancel_one")) { onCancel() }
                    .accessibilityIdentifier("export.button.cancel_one")
            }
            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("export.job.state_\(row.id.uuidString)")
        }
        .accessibilityIdentifier("export.row.job")
    }

    private var variantLabel: String {
        guard let variant = row.variants.first else { return "" }
        return "\(variant.format.formatName) · \(variant.colorSpace.rawValue)"
    }

    private var stateIcon: String {
        switch row.state {
        case .pending: "clock"
        case .rendering, .encoding: "arrow.triangle.2.circlepath"
        case .done: "checkmark.circle"
        case .failed: "xmark.octagon"
        case .cancelled: "slash.circle"
        }
    }

    private var stateColor: Color {
        switch row.state {
        case .done: .green
        case .failed: .red
        case .cancelled: .secondary
        case .pending, .rendering, .encoding: .accentColor
        }
    }

    private var stateLabel: String {
        switch row.state {
        case .pending: String(localized: "export_job_state_pending")
        case .rendering: String(localized: "export_job_state_rendering")
        case .encoding: String(localized: "export_job_state_encoding")
        case .done: String(localized: "export_job_state_done")
        case .failed: String(localized: "export_job_state_failed")
        case .cancelled: String(localized: "export_job_state_cancelled")
        }
    }
}
