import AppKit
import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchPanelView (Plan M5-1-02 T6/T7, KD-6/KD-7; TRACK-04) — the
// colormatch panel: the solver picker, the multi-reference list with the
// per-row weight sliders, the Solve action, the strength D-H1 slider, and
// the readout (solver/effective/statsHash/support width/degrade note).
//
// PRESENTATION (L057): the reference file panel presents through
// `PanelPresentation.present` (the begin-seam) from inside a `Task` hop —
// `runModal` is banned on this path (the L057 grep gate).
//
// BEFORE/AFTER (TRACK-04): the inherited 9-4 face — the per-instance
// projectedState override renders the before plane against this instance's
// params; no new mechanism (the HIST-06 circuit is op-agnostic).
// ─────────────────────────────────────────────────────────────────────────────

internal struct ColorMatchPanelProvider: IOPPanelProvider {
    var opName: String { ColormatchModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(
            ColorMatchPanelView(
                instance: instance, editSession: edit))
    }
}

internal struct ColorMatchPanelView: View {

    let instance: ModuleInstance
    let editSession: InspectorEditSession

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(ColorMatchService.self) private var service

    @State private var model: ColorMatchPanelModel?
    @State private var selectedSolver: ColorMatchSolverKind = .gaussianOT

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear.onAppear {
                    model = ColorMatchPanelModel(
                        instance: instance, editorState: editorState,
                        pipeCoordinator: pipeCoordinator, service: service,
                        editSession: editSession)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ColorMatchPanelModel) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                solverPicker(model)
                Divider()
                referenceSection(model)
                Divider()
                solveSection(model)
                readoutSection(model)
                if let error = model.solveError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("colormatch.solveError")
                }
                if let degrade = model.degradeNote {
                    Text(degrade)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("colormatch.panel")
        // The committed-truth refresh seam (V2M-01 T1, defect D-1): every
        // re-render that carries a new instance value (instance switch /
        // post-commit re-render / MCP `apply_params` external writes /
        // undo-redo + version-swap rebuilds) re-seats the model's params
        // snapshot here — the binding gets stay pure local reads. Attached
        // on the non-nil `model` scope (the hook needs the unwrapped
        // model — CHECKER C-1).
        .onChange(of: instance) { _, newInstance in
            model.updateInstance(newInstance)
        }
    }

    // MARK: - The solver picker

    private func solverPicker(_ model: ColorMatchPanelModel) -> some View {
        Picker(String(localized: "colormatch_solver_label"), selection: $selectedSolver) {
            ForEach(ColorMatchSolverKind.allCases, id: \.self) { solver in
                Text(ColorMatchPanelModel.solverDisplayName(solver)).tag(solver)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("colormatch.solverPicker")
    }

    // MARK: - The reference list (KD-7, TRACK-02)

    private func referenceSection(_ model: ColorMatchPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("colormatch_references_label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    // L057: the file panel rides the begin-seam from a
                    // Task hop — never runModal inside the action frame.
                    Task { @MainActor in
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = true
                        panel.title = String(localized: "colormatch_references_pick_title")
                        if await PanelPresentation.present(panel) != nil {
                            for url in panel.urls { model.addReference(url: url) }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("colormatch.addReference")
                .accessibilityLabel(Text("colormatch_references_add"))
            }
            if model.references.isEmpty {
                Text("colormatch_references_empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.references) { row in
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { row.weight },
                            set: { model.setWeight($0, id: row.id) }),
                        in: ColorMatchPanelModel.weightRange)
                        .frame(width: 90)
                        .accessibilityIdentifier("colormatch.weight.\(row.id)")
                    Text(String(format: "%.2f", row.weight))
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(width: 30)
                    Button {
                        model.removeReference(id: row.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("colormatch.remove.\(row.id)")
                    .accessibilityLabel(Text("colormatch_references_remove"))
                }
            }
        }
    }

    // MARK: - Solve + strength

    private func solveSection(_ model: ColorMatchPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    model.solve(solver: selectedSolver, strength: model.params.strength)
                } label: {
                    if model.isSolving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("colormatch_solve_label")
                    }
                }
                .disabled(!model.hasImage || model.references.isEmpty || model.isSolving)
                .accessibilityIdentifier("colormatch.solve")
                Spacer()
            }
            HStack {
                Text("colormatch_strength_label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { model.params.strength },
                        set: { model.setStrengthLive($0) }),
                    in: ColorMatchPanelModel.strengthRange,
                    onEditingChanged: { editing in
                        // The D-H1 trio: the drag window opens/closes
                        // around the live ticks (exactly ONE history item
                        // per drag).
                        if editing {
                            model.beginStrengthDrag()
                        } else {
                            model.commitStrengthDrag()
                        }
                    })
                .accessibilityIdentifier("colormatch.strength")
                Text(String(format: "%.2f", model.params.strength))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 34)
            }
        }
    }

    // MARK: - The readout

    private func readoutSection(_ model: ColorMatchPanelModel) -> some View {
        let readout = model.readout
        return VStack(alignment: .leading, spacing: 2) {
            Text("colormatch_readout_header")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(readout.solver)
                .font(.caption)
            if readout.effective != readout.solver {
                Text(String(
                    localized: "colormatch_readout_effective",
                    defaultValue: "effective: \(readout.effective)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let hash = readout.statsHash {
                Text(String(
                    localized: "colormatch_readout_stats_hash",
                    defaultValue: "stats \(hash)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let support = readout.supportWidth {
                Text(support)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
