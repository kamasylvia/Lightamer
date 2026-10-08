import LightamerCore
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
                } else if model.isPristine {
                    enableEntry
                } else {
                    sessionControls
                }
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("editor.stack.film.panel")
        .onAppear { model = FilmPanelModel(
            editorState: editorState, pipeCoordinator: pipeCoordinator) }
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
