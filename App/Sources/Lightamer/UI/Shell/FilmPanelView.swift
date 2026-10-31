import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelView (Plan M3-3-03 T3, KD-3) — the film-simulation page's live
// panel, DrtPanelView's structural twin: the enable entry for pristine
// documents; the film/paper pickers; the Y/M dual sliders (the D-H1 trio);
// the strength + exposure sliders; the content-adaptive Toggle; the solve
// readout row with the Solve button (the cache invalidation face). NO
// tolerance/histogram/descriptor face — FSIM-02 (M3-4). Material names are
// the assets' info.name (technical proper nouns, not translated).
//
// AR-01 T3 (audit M5): the three former `private var` sections are now
// their own View structs (SessionControlsView / LatitudeSectionView /
// PlacementSectionView) — computed properties share the panel's single
// invalidation boundary, so any model tick re-evaluated the whole panel
// (Canvas histogram + pickers + readouts included); the structs give each
// section its own boundary. Behavior-preserving: every binding is a
// line-for-line translation (live tick → setLive, drag end → commit
// untouched; the `model?.` optional chains dropped where the sub-view's
// non-optional `let model` makes them moot).
// ─────────────────────────────────────────────────────────────────────────────

internal struct FilmPanelView: View {

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(InspectorState.self) private var inspectorState

    @State private var model: FilmPanelModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let model {
                if !model.hasImage {
                    Text(String(
                            localized: "film_no_image",
                            defaultValue: "Open an image to edit the film session"))
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .padding(8)
                } else {
                if model.isPristine {
                    enableEntry
                } else {
                    SessionControlsView(model: model)
                    ProcessMigrationRow(inputs: ProcessMigrationInputs(
                        action: model.migrationAction,
                        onMigrate: { model.runMigration() }))
                }
                    LatitudeSectionView(model: model)
                    PlacementSectionView(model: model)
                }
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("editor.stack.film.panel")
        .onAppear { model = FilmPanelModel(
            editorState: editorState, pipeCoordinator: pipeCoordinator) }
        .task(id: model?.record.filmStock ?? "") {
            model?.refreshLatitudeDescriptor()
        }
        .task(id: model?.record.paperStock ?? "") {
            model?.refreshLatitudeDescriptor()
        }
    }

    // MARK: - Header (the page title + the close face)

    private var header: some View {
        HStack {
            Text(String(localized: "film_section", defaultValue: "Film Simulation"))
                .font(.callout.weight(.medium))
                .foregroundStyle(ThemeTokens.textPrimary)
            Spacer(minLength: 0)
            Button {
                inspectorState.closeFilmPage()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("film.close")
            .accessibilityLabel(Text(String(
                localized: "film_close", defaultValue: "Close")))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - The enable entry (pristine documents)

    private var enableEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(
                    localized: "film_pristine_hint",
                    defaultValue: "Enable film simulation to start a print session"))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
            Button {
                model?.enableFilm()
            } label: {
                Text(String(
                        localized: "film_enable",
                        defaultValue: "Enable Film Simulation"))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .accessibilityIdentifier("film.enable")
            .disabled(!(model?.filmStocks.isEmpty == false)
                || !(model?.paperStocks.isEmpty == false))
        }
        .padding(.horizontal, 8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProcessMigrationRow (Plan M8-3 T3) — the ONE new panel element the M8
// batch allows (D-M8-7's registered exception, M6-2 §6 挂账正主): the
// "Update to Current Process" row for documents still rendering the frozen
// density arm. Hidden for v2 documents (zero visual delta), guarded by the
// pure FilmMigrationAction model; the confirmation rides a SwiftUI sheet —
// the L057 seam (never a runModal). The sheet content takes INIT PARAMS
// only (no @Environment reads) — the M2-8 sheet-environment hazard class
// is structurally absent.
// ─────────────────────────────────────────────────────────────────────────────

/// The migration row's DECISION inputs (M9-4 T2, D-M9SP-7③/④): the row
/// is now PANEL-AGNOSTIC — the Film and ColorWheels panels mount the SAME
/// row with their own action leg (single row, single action; a
/// both-records document never shows two rows because the gate is shared
/// through the coordinator faces). The copy keys are the NEUTRAL
/// `panel_process_migrate_*` family (the film-era `panel_film_migrate_*`
/// keys stay in the catalog unreferenced — bytes untouched).
struct ProcessMigrationInputs {
    let action: FilmMigrationAction
    let onMigrate: () -> Void
}

struct ProcessMigrationRow: View {

    let inputs: ProcessMigrationInputs

    @State private var confirmPresented = false

    var body: some View {
        Group {
            if inputs.action.migratable {
                Button {
                    confirmPresented = true
                } label: {
                    Text(String(
                            localized: "panel_process_migrate_button",
                            defaultValue: "Update to Current Process"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .accessibilityIdentifier("film.migrate.button")
                .sheet(isPresented: $confirmPresented) {
                    MigrationConfirmSheet(inputs: inputs, presented: $confirmPresented)
                }
            }
        }
    }
}

/// The migration confirm sheet's content face (the
/// AdjustmentTransferSheetContent form: a self-sufficient content struct —
/// init-parameter injection, zero environment reads, so the sheet
/// hierarchy's environment snapshot cannot miss an injection).
struct MigrationConfirmSheet: View {

    let inputs: ProcessMigrationInputs
    @Binding var presented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(
                    localized: "panel_process_migrate_title",
                    defaultValue: "Update to Current Process?"))
                .font(.callout.weight(.medium))
            Text(String(
                    localized: "panel_process_migrate_body",
                    defaultValue: "This document still renders with the frozen previous process generation. Updating re-renders it with the current semantics. For older color-wheel documents the new wheels re-express the previous look (the previous rendering behavior is kept; a small approximation can remain at the range ends). Your edits and history stay untouched."))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
            HStack {
                Spacer(minLength: 0)
                Button(String(
                        localized: "panel_process_migrate_cancel",
                        defaultValue: "Cancel")) {
                    presented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("film.migrate.cancel")
                Button(String(
                        localized: "panel_process_migrate_confirm",
                        defaultValue: "Update")) {
                    presented = false
                    inputs.onMigrate()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("film.migrate.confirm")
            }
        }
        .padding(16)
        .frame(width: 320)
        .accessibilityIdentifier("film.migrate.sheet")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionControlsView (AR-01 T3 / audit M5) — the former `sessionControls`
// section as its own invalidation boundary: the material pickers, the four
// D-H1 sliders, the content-adaptive Toggle and the solve readout row.
// ─────────────────────────────────────────────────────────────────────────────

private struct SessionControlsView: View {

    let model: FilmPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(String(localized: "film_label_film", defaultValue: "Film")) {
                Picker(
                    String(localized: "film_label_film", defaultValue: "Film"),
                    selection: Binding(
                        get: { model.record.filmStock },
                        set: { model.setFilmStock($0) }
                    )
                ) {
                    // M9-2 (D-M92-7): BW stocks group under their own
                    // section header; the color set stays flat on top.
                    ForEach(model.filmStockSections, id: \.title) { section in
                        if let title = section.title {
                            Text(String(localized: "film_section_bw",
                                        defaultValue: "B&W"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .tag("__section__\(title)")
                        }
                        ForEach(section.stocks, id: \.info.stock) { profile in
                            Text(verbatim: profile.info.name ?? profile.info.stock ?? "")
                                .tag(profile.info.stock ?? "")
                        }
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("film.film.picker")
            }
            row(String(localized: "film_label_paper", defaultValue: "Paper")) {
                Picker(
                    String(localized: "film_label_paper", defaultValue: "Paper"),
                    selection: Binding(
                        get: { model.record.paperStock },
                        set: { model.setPaperStock($0) }
                    )
                ) {
                    ForEach(model.paperStockSections, id: \.title) { section in
                        if let title = section.title {
                            Text(String(localized: "film_section_bw",
                                        defaultValue: "B&W"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .tag("__section__\(title)")
                        }
                        ForEach(section.stocks, id: \.info.stock) { profile in
                            Text(verbatim: profile.info.name ?? profile.info.stock ?? "")
                                .tag(profile.info.stock ?? "")
                        }
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("film.paper.picker")
            }
            // M9-2 T2: the paper grade picker (visible when the bound
            // paper is a graded BW stock; the "None" entry = the solver's
            // own neutral pack — the zero-drift default).
            if !model.availableGradeKeys.isEmpty {
                row(String(localized: "film_label_grade",
                           defaultValue: "Grade")) {
                    Picker(
                        String(localized: "film_label_grade",
                               defaultValue: "Grade"),
                        selection: Binding(
                            get: { model.selectedGrade ?? "" },
                            set: { model.setGrade($0.isEmpty ? nil : $0) }
                        )
                    ) {
                        Text(String(localized: "film_grade_none",
                                    defaultValue: "None (auto)"))
                            .tag("")
                        ForEach(model.availableGradeKeys, id: \.self) { key in
                            Text(verbatim: key).tag(key)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("film.grade.picker")
                }
            }
            // M8-3+ T2 (R-M83P-1): the reversal print-mode section
            // (reversal films only — the B-route gate + the C-convergence
            // caption; negative films render nothing).
            if model.isReversalFilm {
                row(String(localized: "film_label_reversal",
                           defaultValue: "Print Mode")) {
                    Picker(
                        String(localized: "film_label_reversal",
                               defaultValue: "Print Mode"),
                        selection: Binding(
                            get: { model.selectedReversalPrintMode ?? "" },
                            set: { model.setReversalPrintMode(
                                $0.isEmpty ? nil : $0) }
                        )
                    ) {
                        Text(String(localized: "film_reversal_legacy",
                                    defaultValue: "Legacy (print exposure)"))
                            .tag("")
                        Text(String(localized: "film_reversal_direct",
                                    defaultValue: "Direct positive (scan neutral)"))
                            .tag(SpectralNeutralSolve.directPositiveMode)
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("film.reversal.picker")
                }
                Text(String(
                        localized: "film_reversal_converge",
                        defaultValue:
                            "Reversal printing converges onto print film (2383/2393) — the current paper stays until you switch."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                // The B-clamped caption (the "manual CC" honesty face —
                // the Y/M sliders below are the existing carrier).
                if model.directPositiveClamped == true {
                    Text(String(
                            localized: "film_reversal_manual_cc",
                            defaultValue:
                                "Direct-positive solve also wall-limited — trim with the Y/M shifts below."))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("film.reversal.manualcc")
                }
            }
            // M9-2 T4: the BW stock's granularity readout (published RMS +
            // the calibration layer's recommended strength; the one-click
            // apply = a plain grain params edit, D-M92-2).
            if let grain = model.bwGrainReadout {
                HStack {
                    Text(String(
                        format: String(
                            localized: "film_grain_readout",
                            defaultValue:
                                "Published RMS %d µm · recommended strength %.1f"),
                        grain.publishedRms, grain.recommendedStrength))
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                    Spacer(minLength: 0)
                    Button(String(
                        localized: "film_grain_apply",
                        defaultValue: "Apply")) {
                        model.applyRecommendedGrainStrength()
                    }
                    .font(.caption2)
                    .accessibilityIdentifier("film.grain.apply")
                }
                .padding(.vertical, 2)
            }
            // M9-2 T3 (D-M92-6): the SHOOT section — the taking (camera)
            // filter rides the film leg's INPUT side (spectral sensW
            // multiply), distinct from the Y/M dichroic enlarger shifts
            // below. The section hides when the store carries no table.
            if !model.availableCameraFilters.isEmpty {
                Divider().padding(.vertical, 6)
                Text(String(localized: "film_shoot_section",
                            defaultValue: "Shoot"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text(String(localized: "film_shoot_caption",
                            defaultValue:
                                "Lens filter at exposure — multiplies the film's spectral sensitivity; distinct from the enlarger's Y/M dichroic shifts below."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                row(String(localized: "film_shoot_filter",
                           defaultValue: "Filter")) {
                    Picker(
                        String(localized: "film_shoot_filter",
                               defaultValue: "Filter"),
                        selection: Binding(
                            get: { model.selectedCameraFilter ?? "" },
                            set: { model.setCameraFilter(
                                $0.isEmpty ? nil : $0) }
                        )
                    ) {
                        Text(String(localized: "film_shoot_none",
                                    defaultValue: "None"))
                            .tag("")
                        ForEach(model.availableCameraFilters, id: \.self) { name in
                            Text(verbatim: name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("film.filter.picker")
                }
                // The dual-source divergence note (w58's B-3 vs W2 gap —
                // the data face's own note, shown through an explicit
                // static-key format; closeout wording note: the M8 token
                // scan matches substrings, so this comment deliberately
                // avoids spelling the s-word it scans for).
                if let selected = model.selectedCameraFilter,
                    let note = model.cameraFilter(named: selected)?
                        .crossCheckNote {
                    Text(String(
                        format: String(
                            localized: "film_shoot_note",
                            defaultValue: "Data note: %@"),
                        note))
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
            }
            shiftRow(
                String(localized: "film_label_yellow", defaultValue: "Yellow"),
                value: Binding(
                    get: { model.record.yFilterShift },
                    set: { model.setYShiftLive($0) }
                ),
                range: FilmPanelModel.shiftRange,
                readout: "\(Int(model.record.yFilterShift)) CC",
                axIdentifier: "film.y.slider")
            shiftRow(
                String(localized: "film_label_magenta", defaultValue: "Magenta"),
                value: Binding(
                    get: { model.record.mFilterShift },
                    set: { model.setMShiftLive($0) }
                ),
                range: FilmPanelModel.shiftRange,
                readout: "\(Int(model.record.mFilterShift)) CC",
                axIdentifier: "film.m.slider")
            shiftRow(
                String(localized: "film_label_strength", defaultValue: "Strength"),
                value: Binding(
                    get: { model.record.strength },
                    set: { model.setStrengthLive($0) }
                ),
                range: FilmPanelModel.strengthRange,
                readout: String(
                    format: "%.2f", Double(model.record.strength)),
                axIdentifier: "film.strength.slider")
            shiftRow(
                String(localized: "film_label_exposure", defaultValue: "Exposure"),
                value: Binding(
                    get: { model.record.exposureEv },
                    set: { model.setExposureLive($0) }
                ),
                range: FilmPanelModel.exposureRange,
                readout: String(
                    format: "%+.2f EV", Double(model.record.exposureEv)),
                axIdentifier: "film.exposure.slider")
            row(String(
                    localized: "film_label_content_adaptive",
                    defaultValue: "Content-Adaptive Offset"
                )) {
                Toggle(
                    String(localized: "film_label_content_adaptive", defaultValue: ""),
                    isOn: Binding(
                        get: { model.record.contentAdaptiveShift },
                        set: { model.setContentAdaptive($0) }
                    )
                )
                .labelsHidden()
                .accessibilityIdentifier("film.content.toggle")
            }
            readoutRow
        }
    }

    /// The solve readout row (read-only) + the Solve button (the cache
    /// invalidation face).
    private var readoutRow: some View {
        row(String(localized: "film_label_readout", defaultValue: "Solve")) {
            HStack(spacing: 6) {
                if let readout = model.solveReadout {
                    Text(verbatim: String(
                        format: "M %.1f · Y %.1f · ×%.2f",
                        readout.magentaCC, readout.yellowCC, readout.gain))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .accessibilityIdentifier("film.readout.value")
                } else {
                    Text(String(
                            localized: "film_readout_unbound",
                            defaultValue: "Materials unbound"))
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .accessibilityIdentifier("film.readout.unbound")
                }
                Spacer(minLength: 4)
                Button(String(localized: "film_solve", defaultValue: "Solve")) {
                    model.forceResolve()
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .accessibilityIdentifier("film.solve.button")
            }
            // M8-3+ T2: the disclosed amber row (the wall-touch honesty
            // face — clamped pairs only; safe pairs render nothing).
            if model.solveClamped == true {
                Text(String(
                        localized: "film_disclosed_clamped",
                        defaultValue:
                            "Neutral unreached — wall-limited; showing the compensated fallback"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("film.disclosed.clamped")
            }
        }
    }

    // MARK: - Shared row shell (the DrtPanelView row shape)

    private func row(_ label: String, @ViewBuilder content: () -> some View)
        -> some View
    {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
        .padding(.vertical, 2)
    }
    /// One slider row: the D-H1 trio rides the shared bindings (live ticks
    /// re-render with zero items; the drag end commits exactly once).
    private func shiftRow(
        _ label: String, value: Binding<Float>, range: ClosedRange<Float>,
        readout: String, axIdentifier: String
    ) -> some View {
        row(label) {
            HStack {
                Slider(value: value, in: range) { editing in
                    if editing {
                        model.beginDrag()
                    } else {
                        model.commitDrag()
                    }
                }
                .accessibilityIdentifier(axIdentifier)
                Text(readout)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LatitudeSectionView (AR-01 T3 / audit M5) — the former `latitudeSection`
// section: the teaching notes, the EV-axis histogram Canvas, the
// below/inside/above share readouts (m9: each share renders through its own
// static format key — the verbatim label+percent concatenation broke zh word
// order) and the absence notes.
// ─────────────────────────────────────────────────────────────────────────────

private struct LatitudeSectionView: View {

    let model: FilmPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 2)
            Text(String(localized: "latitude_section", defaultValue: "Latitude"))
                .font(.callout.weight(.medium))
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(.horizontal, 8)
            // The two teaching notes (static keys — the RFC's semantics).
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "latitude_teaching_scene_vs_dev",
                            defaultValue: "Scene placement acts BEFORE the film; dev exposure acts AFTER it — they are not interchangeable."))
                Text(String(localized: "latitude_teaching_edr_output",
                            defaultValue: "EDR lives on the output side — it cannot recover highlights lost at the input."))
            }
            .font(.caption2)
            .foregroundStyle(ThemeTokens.textSecondary)
            .padding(.horizontal, 8)
            latitudeHistogram
            shareReadoutRow
            notes
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("film.latitude.section")
    }

    /// The EV-axis histogram (the native drawable span [−6.56, +2.44] —
    /// 256 bins × [0,1] linear through the bin→EV formula) + the useful
    /// pair's dashed lines (absent + noted without a descriptor).
    private var latitudeHistogram: some View {
        Canvas { context, size in
            let luma = model.latitudeStats?.perChannel[3] ?? []
            let maxCount = luma.max().map { Int($0) } ?? 0
            let barWidth = max(1.0, size.width / 256.0)
            for (bin, count) in luma.enumerated() {
                guard Int(count) > 0 else { continue }
                let h = maxCount > 0
                    ? Double(count) / Double(maxCount) * (size.height - 2) : 0
                let fraction = evFraction(FilmPanelModel.binEV(bin))
                guard fraction >= 0, fraction <= 1 else { continue }
                let rect = CGRect(
                    x: size.width * fraction, y: size.height - h,
                    width: barWidth, height: h)
                context.fill(
                    Path(rect), with: .color(ThemeTokens.textSecondary.opacity(0.65)))
            }
            if let descriptor = model.latitudeDescriptor {
                for ev in [descriptor.usefulShadowEV, descriptor.usefulHighlightEV] {
                    let x = size.width * min(max(evFraction(ev), 0), 1)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(
                        path, with: .color(.yellow),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("film.latitude.histogram")
    }

    private func evFraction(_ ev: Double) -> Double {
        (ev - FilmPanelModel.latitudeAxisMinEV)
            / (FilmPanelModel.latitudeAxisMaxEV - FilmPanelModel.latitudeAxisMinEV)
    }

    /// The below/inside/above shares (nil = the descriptor's absence is
    /// presented, never faked). m9 (AR-01 T3): each share renders through
    /// the ONE `latitude_share_value` format key (the label-arg + %lld
    /// slots — zh word order is the catalog's business) with the existing
    /// latitude_share_* label keys as the argument (they stay live — zero
    /// orphan catalog keys); the former `"\(label) \(pct)%"` verbatim
    /// concatenation is gone.
    private var shareReadoutRow: some View {
        Group {
            if let stats = model.latitudeStats,
                let descriptor = model.latitudeDescriptor,
                let shares = FilmPanelModel.latitudeShares(
                    histogram: stats,
                    belowEV: descriptor.usefulShadowEV,
                    aboveEV: descriptor.usefulHighlightEV) {
                HStack(spacing: 10) {
                    shareLabel(
                        String(localized: "latitude_share_value",
                               defaultValue: "\(String(localized: "latitude_share_below", defaultValue: "Below")) \(Int((shares.below * 100).rounded()))%"),
                        "film.latitude.share.below")
                    shareLabel(
                        String(localized: "latitude_share_value",
                               defaultValue: "\(String(localized: "latitude_share_inside", defaultValue: "Inside")) \(Int((shares.inside * 100).rounded()))%"),
                        "film.latitude.share.inside")
                    shareLabel(
                        String(localized: "latitude_share_value",
                               defaultValue: "\(String(localized: "latitude_share_above", defaultValue: "Above")) \(Int((shares.above * 100).rounded()))%"),
                        "film.latitude.share.above")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            } else {
                Text(String(localized: "latitude_histogram_placeholder",
                            defaultValue: "Histogram arrives with the first film render; the dashed lines need the descriptor."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func shareLabel(_ text: String, _ axID: String)
        -> some View
    {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(ThemeTokens.textSecondary)
            .accessibilityIdentifier(axID)
    }

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.latitudeStats == nil {
                Text(String(localized: "latitude_stats_missing",
                            defaultValue: "Film statistics not in yet."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            if model.latitudeDescriptor == nil {
                Text(String(localized: "latitude_descriptor_missing",
                            defaultValue: "Descriptor unavailable for this pair — the dashed lines stay absent."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            if model.placementAnchors.usedFallback == true {
                Text(String(localized: "latitude_fallback_note",
                            defaultValue: "Anchors on the no-film fallback constants."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
        .padding(.horizontal, 8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlacementSectionView (AR-01 T3 / audit M5) — the former `placementSection`
// section: the add button / the N_h·N_s·m·Fit editing face + the §9.2
// readouts (m9: side-by-side Texts replace the localized-label concatenation
// — zero new keys, the existing latitude_readout_* keys stay) + the typed
// refusal rows.
// ─────────────────────────────────────────────────────────────────────────────

private struct PlacementSectionView: View {

    let model: FilmPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 2)
            Text(String(localized: "latitude_placement_section",
                        defaultValue: "Scene Placement"))
                .font(.callout.weight(.medium))
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(.horizontal, 8)
            if model.placementTarget == nil {
                Button {
                    model.addPlacement()
                } label: {
                    Text(String(localized: "latitude_placement_add",
                                defaultValue: "Add Scene Placement"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("film.placement.add")
            } else {
                placementControls
            }
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("film.placement.section")
    }

    private var placementControls: some View {
        let params = model.placementParams ?? FilmPlacementModule.Params()
        let anchors = model.placementAnchors
        let minimums = PlacementResolver.sliderMinimums(anchors: anchors)
        let capH = max(minimums.nH, anchors.aH - anchors.cS)
        let capS = max(minimums.nS, anchors.cH - anchors.aS)
        let lo = Float(FilmPlacementModule.rolloffRange.lowerBound)
        let hi = Float(FilmPlacementModule.rolloffRange.upperBound)
        let mRange: ClosedRange<Float> = lo...hi
        return VStack(alignment: .leading, spacing: 2) {
            LightamerSlider(
                label: String(localized: "latitude_label_nh",
                              defaultValue: "Highlight pull-back"),
                value: Double(params.highlightsPullBack),
                range: minimums.nH...capH,
                defaultValue: 0,
                readoutFormat: "%.2f",
                unit: " EV",
                onDragBegin: { model.beginPlacementDrag() },
                onChange: { model.tickPlacement(highlights: $0, shadows: nil) },
                onDragEnd: { model.endPlacementDrag() },
                onReset: { model.resetPlacementSide(highlights: true) },
                accessibilityID: "film.placement.nh")
            LightamerSlider(
                label: String(localized: "latitude_label_ns",
                              defaultValue: "Shadow pull-back"),
                value: Double(params.shadowsPullBack),
                range: minimums.nS...capS,
                defaultValue: 0,
                readoutFormat: "%.2f",
                unit: " EV",
                onDragBegin: { model.beginPlacementDrag() },
                onChange: { model.tickPlacement(highlights: nil, shadows: $0) },
                onDragEnd: { model.endPlacementDrag() },
                onReset: { model.resetPlacementSide(highlights: false) },
                accessibilityID: "film.placement.ns")
            row(String(localized: "latitude_label_m",
                       defaultValue: "Roll-off m")) {
                HStack {
                    Stepper(
                        value: Binding(
                            get: { params.rolloff },
                            set: { model.stepM($0) }
                        ),
                        in: mRange,
                        step: 0.5
                    ) {
                        Text(verbatim: String(format: "%.1f", params.rolloff))
                            .font(.caption2.monospacedDigit())
                    }
                    .accessibilityIdentifier("film.placement.m")
                }
            }
            row(String(localized: "latitude_fit", defaultValue: "Fit")) {
                HStack(spacing: 6) {
                    Button(String(localized: "latitude_fit", defaultValue: "Fit")) {
                        model.runFit(m: params.rolloff)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .accessibilityIdentifier("film.placement.fit")
                    if let outcome = model.lastFitOutcome, outcome.refusedByHMin {
                        Text(String(localized: "latitude_fit_refused_hmin",
                                    defaultValue: "Refused: the recommended rooms would undercut the curvature floor (H < 3.0)."))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("film.placement.fit.refused")
                    }
                }
            }
            placementReadouts(params: params, anchors: anchors)
            rejectionRows
        }
        .padding(.horizontal, 8)
    }

    /// The §9.2 readouts (the identity core width / both landings / both
    /// endpoint slopes) — read-only, Solve-style refresh. m9 (AR-01 T3):
    /// side-by-side Texts (layout instead of concatenation — the former
    /// single `String(format:)` row baked localized labels into a verbatim
    /// pattern, breaking zh word order). Zero new keys: the existing
    /// latitude_readout_* labels carry; the numeric fragments render through
    /// format-style Texts (locale digits, the former %.2f/%+.2f/%.3f faces).
    private func placementReadouts(
        params: FilmPlacementModule.Params, anchors: PlacementAnchors
    ) -> some View {
        let coreWidth = (params.kHighlight ?? 0) - (params.kShadow ?? 0)
        let landingH = anchors.aH - Double(params.highlightsPullBack)
        let landingS = anchors.aS + Double(params.shadowsPullBack)
        let slopeH = params.kHighlight.map {
            PlacementResolver.endpointSlope(
                extreme: anchors.aH, boundary: anchors.cH, knee: $0,
                m: Double(params.rolloff))
        } ?? 1
        let slopeS = params.kShadow.map {
            PlacementResolver.endpointSlope(
                extreme: anchors.aS, boundary: anchors.cS, knee: $0,
                m: Double(params.rolloff))
        } ?? 1
        return HStack(spacing: 6) {
            Text(String(localized: "latitude_readout_core",
                        defaultValue: "Core"))
            Text(coreWidth, format: .number.precision(.fractionLength(2)))
            Text(verbatim: "EV")
            Text(String(localized: "latitude_readout_landing",
                        defaultValue: "Lands"))
            Text(landingH, format: .number.sign(
                strategy: .always(includingZero: true))
                .precision(.fractionLength(2)))
            Text(verbatim: "/")
            Text(landingS, format: .number.sign(
                strategy: .always(includingZero: true))
                .precision(.fractionLength(2)))
            Text(String(localized: "latitude_readout_slope",
                        defaultValue: "Slopes"))
            Text(slopeH, format: .number.precision(.fractionLength(3)))
            Text(verbatim: "/")
            Text(slopeS, format: .number.precision(.fractionLength(3)))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(ThemeTokens.textSecondary)
        .accessibilityIdentifier("film.placement.readouts")
    }

    /// The typed refusal rows (naming the slider — never a silent clamp).
    @ViewBuilder
    private var rejectionRows: some View {
        if let rejection = model.lastPlacementRejection {
            switch rejection {
            case .kneeOrder:
                Text(String(localized: "latitude_reject_knee_order",
                            defaultValue: "Knees crossed — the identity core collapsed. Reduce the highlight or the shadow pull-back."))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("film.placement.reject.knee")
            case .highlightDemand:
                Text(String(localized: "latitude_reject_highlight_demand",
                            defaultValue: "The highlight pull-back cannot land inside the medium."))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("film.placement.reject.nh")
            case .shadowDemand:
                Text(String(localized: "latitude_reject_shadow_demand",
                            defaultValue: "The shadow pull-back cannot land inside the medium."))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("film.placement.reject.ns")
            case .noInstance:
                EmptyView()
            }
        }
        if let outcome = model.lastFitOutcome, outcome.sharedDeficit {
            Text(String(localized: "latitude_fit_shared",
                        defaultValue: "The medium's budget was short — the pull-backs were shared proportionally."))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .accessibilityIdentifier("film.placement.fit.shared")
        }
        if let outcome = model.lastFitOutcome, outcome.sidesOff, !outcome.refusedByHMin {
            Text(String(localized: "latitude_fit_sides_off",
                        defaultValue: "A side's scene extreme sits inside the medium — that branch stays off."))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .accessibilityIdentifier("film.placement.fit.sidesoff")
        }
    }

    // MARK: - Shared row shell (the DrtPanelView row shape)

    private func row(_ label: String, @ViewBuilder content: () -> some View)
        -> some View
    {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
        .padding(.vertical, 2)
    }
}
