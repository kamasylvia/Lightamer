import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// UprightPanelView (Plan M9-3-T4) — the Guided Upright panel: the mode
// toggle (off / guided), the guides readout (count + clear), the
// draw-guides tool arm, the Constrain-Crop seat (the T3 funnel), and the
// double-warp advisory note (R-3: ashift.rotation ≠ 0 with non-empty
// guides means two bilinear warps — straighten into the guide solve
// instead). D-H1: each control lands ONE commit through the injected
// session (the standard panel edit-session semantics).
// ─────────────────────────────────────────────────────────────────────────

struct UprightPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession
    /// The current guides (the live/params projection the host read).
    var guides: [UprightModule.Guide]
    /// The current ashift rotation (the double-warp note's condition).
    var ashiftRotationDegrees: Double
    /// True while the viewport hosts the guide overlay (the tool armed).
    var toolActive: Bool

    var onModeChange: (UprightModule.Mode) -> Void = { _ in }
    var onGuidesChange: ([UprightModule.Guide]) -> Void = { _ in }
    var onToggleTool: () -> Void = {}
    var onConstrain: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The mode toggle (off / guided — the two-case enum, D-M9G-3).
            Picker(String(localized: "upright_mode_label"), selection: modeBinding) {
                Text(String(localized: "upright_mode_off")).tag(UprightModule.Mode.off)
                Text(String(localized: "upright_mode_guided")).tag(UprightModule.Mode.guided)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("upright.mode.picker")

            // The guides readout + clear (the persisted truth).
            HStack {
                Text(guidesReadout)
                    .font(.callout)
                    .accessibilityIdentifier("upright.guides.readout")
                Spacer()
                Button(String(localized: "upright_guides_clear")) {
                    onGuidesChange([])
                }
                .disabled(guides.isEmpty)
                .accessibilityIdentifier("upright.guides.clear")
            }

            // The draw-guides tool arm (the viewport overlay's switch).
            Button(toolActive ? String(localized: "upright_tool_done") : String(localized: "upright_tool_draw")) {
                onToggleTool()
            }
            .accessibilityIdentifier("upright.tool.toggle")
            .help(Text("upright_tool_help"))

            // The double-warp advisory (R-3): both warps active = two
            // bilinear resamples; straightening into the guide solve is
            // the single-pass route.
            if abs(ashiftRotationDegrees) > 1e-4 && !guides.isEmpty {
                Label {
                    Text(String(localized: "upright_double_warp_note"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("upright.double.warp.note")
            }

            // The Constrain-Crop seat (the T3 funnel's panel face).
            Button(String(localized: "crop_constrain")) {
                onConstrain()
            }
            .accessibilityIdentifier("upright.constrain")
        }
        .padding(12)
    }

    private var modeBinding: Binding<UprightModule.Mode> {
        Binding(
            get: {
                (try? instance.params(of: UprightModule.self))?.mode ?? .off
            },
            set: { onModeChange($0) })
    }

    private var guidesReadout: String {
        String(format: String(localized: "upright_guides_count"), guides.count)
    }
}

internal struct UprightPanelProvider: IOPPanelProvider {
    var opName: String { UprightModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        // The panel's live faces (guides/rotation) read through the
        // environment-provided state the host injects; this provider keeps
        // the registry seam (the panel itself takes the session for the
        // mode toggle's commit leg).
        AnyView(
            UprightPanelHost(
                instance: instance, edit: edit))
    }
}

/// The host bridge (the panel's live reads + the commit wiring — the
/// CropOverlayHost shape): reads upright/ashift from EditorState, lands
/// the commits through the injected session.
struct UprightPanelHost: View {
    let instance: ModuleInstance
    let edit: InspectorEditSession

    @Environment(EditorState.self) private var editorState
    @Environment(InspectorState.self) private var inspectorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    var body: some View {
        let uprightRecord = editorState.instances.first(where: { $0.opName == UprightModule.opName })
        let ashiftRecord = editorState.instances.first(where: { $0.opName == AshiftModule.opName })
        let rotation: Float = {
            guard let rec = ashiftRecord, let p = try? rec.params(of: AshiftModule.self) else { return 0 }
            return p.rotation
        }()
        let guides: [UprightModule.Guide] = {
            guard let rec = uprightRecord, let p = try? rec.params(of: UprightModule.self) else { return [] }
            return p.guides
        }()
        UprightPanelView(
            instance: instance,
            edit: edit,
            guides: guides,
            ashiftRotationDegrees: Double(rotation),
            toolActive: inspectorState.uprightGuidesToolActive,
            onModeChange: { mode in
                guard let record = uprightRecord else { return }
                var params = (try? record.params(of: UprightModule.self)) ?? UprightModule.Params()
                params.mode = mode
                var snapshot = record
                try? snapshot.setParams(params, as: UprightModule.self)
                pipeCoordinator.commitLinkedSnapshots(
                    [snapshot], label: String(localized: "history_upright_mode"))
            },
            onGuidesChange: { newGuides in
                guard let record = uprightRecord else { return }
                var params = (try? record.params(of: UprightModule.self)) ?? UprightModule.Params()
                params.guides = newGuides
                var snapshot = record
                try? snapshot.setParams(params, as: UprightModule.self)
                pipeCoordinator.commitLinkedSnapshots(
                    [snapshot], label: String(localized: "history_upright_guides"))
            },
            onToggleTool: {
                if inspectorState.uprightGuidesToolActive {
                    inspectorState.closeUprightGuidesTool()
                } else {
                    inspectorState.openUprightGuidesTool()
                }
            },
            onConstrain: {
                // the T3 funnel's panel seat (the same path the tool strip
                // wires; the display-plane probe + the crop commit).
                // E-1 family: the span IS the display texture size — the
                // old span(w0: display, ...) recomputed a phantom span
                // under rotation ≠ 0 and the probe's size guard silently
                // killed the seat.
                guard let cropRecord = editorState.instances.first(where: { $0.opName == CropModule.opName }),
                    let display = editorState.displayTexture
                else { return }
                let span = SIMD2(Double(display.width), Double(display.height))
                guard let probe = pipeCoordinator.contentOpaqueProbe(
                    span: SIMD2(Int(span.x), Int(span.y)))
                else { return }
                if let snapshot = CropToolRotation.constrainCropSnapshot(
                    crop: cropRecord, span: span, contentAt: probe) {
                    pipeCoordinator.commitLinkedSnapshots(
                        [snapshot], label: String(localized: "history_constrain"))
                }
            })
    }
}
