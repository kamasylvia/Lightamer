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
                        sessionControls
                    }
                    latitudeSection
                    placementSection
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

    // MARK: - The session controls

    private var sessionControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(String(localized: "film_label_film", defaultValue: "Film")) {
                Picker(
                    String(localized: "film_label_film", defaultValue: "Film"),
                    selection: Binding(
                        get: { model?.record.filmStock ?? "" },
                        set: { model?.setFilmStock($0) }
                    )
                ) {
                    ForEach(model?.filmStocks ?? [], id: \.info.stock) { profile in
                        Text(verbatim: profile.info.name ?? profile.info.stock ?? "")
                            .tag(profile.info.stock ?? "")
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("film.film.picker")
            }
            row(String(localized: "film_label_paper", defaultValue: "Paper")) {
                Picker(
                    String(localized: "film_label_paper", defaultValue: "Paper"),
                    selection: Binding(
                        get: { model?.record.paperStock ?? "" },
                        set: { model?.setPaperStock($0) }
                    )
                ) {
                    ForEach(model?.paperStocks ?? [], id: \.info.stock) { profile in
                        Text(verbatim: profile.info.name ?? profile.info.stock ?? "")
                            .tag(profile.info.stock ?? "")
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("film.paper.picker")
            }
            shiftRow(
                String(localized: "film_label_yellow", defaultValue: "Yellow"),
                value: Binding(
                    get: { model?.record.yFilterShift ?? 0 },
                    set: { model?.setYShiftLive($0) }
                ),
                range: FilmPanelModel.shiftRange,
                readout: "\(Int(model?.record.yFilterShift ?? 0)) CC",
                axIdentifier: "film.y.slider")
            shiftRow(
                String(localized: "film_label_magenta", defaultValue: "Magenta"),
                value: Binding(
                    get: { model?.record.mFilterShift ?? 0 },
                    set: { model?.setMShiftLive($0) }
                ),
                range: FilmPanelModel.shiftRange,
                readout: "\(Int(model?.record.mFilterShift ?? 0)) CC",
                axIdentifier: "film.m.slider")
            shiftRow(
                String(localized: "film_label_strength", defaultValue: "Strength"),
                value: Binding(
                    get: { model?.record.strength ?? 1 },
                    set: { model?.setStrengthLive($0) }
                ),
                range: FilmPanelModel.strengthRange,
                readout: String(
                    format: "%.2f", Double(model?.record.strength ?? 1)),
                axIdentifier: "film.strength.slider")
            shiftRow(
                String(localized: "film_label_exposure", defaultValue: "Exposure"),
                value: Binding(
                    get: { model?.record.exposureEv ?? 0 },
                    set: { model?.setExposureLive($0) }
                ),
                range: FilmPanelModel.exposureRange,
                readout: String(
                    format: "%+.2f EV", Double(model?.record.exposureEv ?? 0)),
                axIdentifier: "film.exposure.slider")
            row(String(
                    localized: "film_label_content_adaptive",
                    defaultValue: "Content-Adaptive Offset"
                )) {
                Toggle(
                    String(localized: "film_label_content_adaptive", defaultValue: ""),
                    isOn: Binding(
                        get: { model?.record.contentAdaptiveShift ?? false },
                        set: { model?.setContentAdaptive($0) }
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
                if let readout = model?.solveReadout {
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
                    model?.forceResolve()
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .accessibilityIdentifier("film.solve.button")
            }
        }
    }

    // MARK: - The latitude section (FSIM-02, M3-4-01 KD-3)

    private var latitudeSection: some View {
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
            let luma = model?.latitudeStats?.perChannel[3] ?? []
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
            if let descriptor = model?.latitudeDescriptor {
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
    /// presented, never faked).
    private var shareReadoutRow: some View {
        Group {
            if let stats = model?.latitudeStats,
                let descriptor = model?.latitudeDescriptor,
                let shares = FilmPanelModel.latitudeShares(
                    histogram: stats,
                    belowEV: descriptor.usefulShadowEV,
                    aboveEV: descriptor.usefulHighlightEV) {
                HStack(spacing: 10) {
                    shareLabel(
                        String(localized: "latitude_share_below",
                               defaultValue: "Below"), shares.below,
                        "film.latitude.share.below")
                    shareLabel(
                        String(localized: "latitude_share_inside",
                               defaultValue: "Inside"), shares.inside,
                        "film.latitude.share.inside")
                    shareLabel(
                        String(localized: "latitude_share_above",
                               defaultValue: "Above"), shares.above,
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

    private func shareLabel(_ label: String, _ share: Double, _ axID: String)
        -> some View
    {
        Text(verbatim: "\(label) \(Int((share * 100).rounded()))%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(ThemeTokens.textSecondary)
            .accessibilityIdentifier(axID)
    }

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model?.latitudeStats == nil {
                Text(String(localized: "latitude_stats_missing",
                            defaultValue: "Film statistics not in yet."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            if model?.latitudeDescriptor == nil {
                Text(String(localized: "latitude_descriptor_missing",
                            defaultValue: "Descriptor unavailable for this pair — the dashed lines stay absent."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            if model?.placementAnchors.usedFallback == true {
                Text(String(localized: "latitude_fallback_note",
                            defaultValue: "Anchors on the no-film fallback constants."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - The placement editing section (KD-3; T1+T2 landed — the
    // hard order satisfied)

    @ViewBuilder
    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 2)
            Text(String(localized: "latitude_placement_section",
                        defaultValue: "Scene Placement"))
                .font(.callout.weight(.medium))
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(.horizontal, 8)
            if model?.placementTarget == nil {
                Button {
                    model?.addPlacement()
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
        let params = model?.placementParams ?? FilmPlacementModule.Params()
        let anchors = model?.placementAnchors
            ?? PlacementResolver.anchors(stats: nil, descriptor: nil)
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
                onDragBegin: { model?.beginPlacementDrag() },
                onChange: { model?.tickPlacement(highlights: $0, shadows: nil) },
                onDragEnd: { model?.endPlacementDrag() },
                onReset: { model?.resetPlacementSide(highlights: true) },
                accessibilityID: "film.placement.nh")
            LightamerSlider(
                label: String(localized: "latitude_label_ns",
                              defaultValue: "Shadow pull-back"),
                value: Double(params.shadowsPullBack),
                range: minimums.nS...capS,
                defaultValue: 0,
                readoutFormat: "%.2f",
                unit: " EV",
                onDragBegin: { model?.beginPlacementDrag() },
                onChange: { model?.tickPlacement(highlights: nil, shadows: $0) },
                onDragEnd: { model?.endPlacementDrag() },
                onReset: { model?.resetPlacementSide(highlights: false) },
                accessibilityID: "film.placement.ns")
            row(String(localized: "latitude_label_m",
                       defaultValue: "Roll-off m")) {
                HStack {
                    Stepper(
                        value: Binding(
                            get: { params.rolloff },
                            set: { model?.stepM($0) }
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
                        model?.runFit(m: params.rolloff)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .accessibilityIdentifier("film.placement.fit")
                    if let outcome = model?.lastFitOutcome, outcome.refusedByHMin {
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
    /// endpoint slopes) — read-only, Solve-style refresh.
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
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: String(
                format: "%@ %.2f EV    %@ %+.2f / %+.2f    %@ %.3f / %.3f",
                String(localized: "latitude_readout_core",
                       defaultValue: "Core"),
                coreWidth,
                String(localized: "latitude_readout_landing",
                       defaultValue: "Lands"),
                landingH, landingS,
                String(localized: "latitude_readout_slope",
                       defaultValue: "Slopes"),
                slopeH, slopeS))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(ThemeTokens.textSecondary)
            .accessibilityIdentifier("film.placement.readouts")
        }
    }

    /// The typed refusal rows (naming the slider — never a silent clamp).
    @ViewBuilder
    private var rejectionRows: some View {
        if let rejection = model?.lastPlacementRejection {
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
        if let outcome = model?.lastFitOutcome, outcome.sharedDeficit {
            Text(String(localized: "latitude_fit_shared",
                        defaultValue: "The medium's budget was short — the pull-backs were shared proportionally."))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .accessibilityIdentifier("film.placement.fit.shared")
        }
        if let outcome = model?.lastFitOutcome, outcome.sidesOff, !outcome.refusedByHMin {
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
                        model?.beginDrag()
                    } else {
                        model?.commitDrag()
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
