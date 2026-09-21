import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Flip panel (Plan 04-08-T1, GUI-6) — the IOP-GEO-04 Inspector surface:
// EXIF-auto + 8-state orientation Picker (discrete one-commit each).
//
// dt reference: `src/iop/flip.c:gui_init` (4 buttons: rotate CCW/CW, flip
// H/V — XOR against the CURRENT orientation via `do_rotate`/`_flip_h`/
// `_flip_v`). Lightamer simplifies to a direct-state Picker (D-08-T1-1):
// same 8 `FlipOrientation` states as the kernel consumes, plus the EXIF
// `auto` seed (dt `ORIENTATION_NULL` default; a persisted `.auto` falls
// back to identity per FlipModule divergence #1).
//
// D-H1 wiring: the Picker is a discrete one-commit edit (aspect-preset
// picker pattern, CropPanelView). Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

internal struct FlipPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private var params: FlipModule.Params {
        PanelEditing.params(of: instance, as: FlipModule.self)
            ?? FlipModule.Params()
    }

    var body: some View {
        Form {
            Section {
                Picker("panel_flip_orientation", selection: orientationBinding) {
                    Text("panel_flip_auto").tag(FlipOrientation.auto)
                    Text("panel_flip_none").tag(FlipOrientation.none)
                    Text("panel_flip_flipH").tag(FlipOrientation.flipH)
                    Text("panel_flip_flipV").tag(FlipOrientation.flipV)
                    Text("panel_flip_rot180").tag(FlipOrientation.rot180)
                    Text("panel_flip_transpose").tag(FlipOrientation.transpose)
                    Text("panel_flip_rotCW90").tag(FlipOrientation.rotCW90)
                    Text("panel_flip_rotCCW90").tag(FlipOrientation.rotCCW90)
                    Text("panel_flip_transverse").tag(FlipOrientation.transverse)
                }
                .accessibilityIdentifier("inspector.flip.orientation")
                Text("panel_flip_exif_note")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            } header: {
                Text("panel_flip_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.flip")
    }

    private var orientationBinding: Binding<FlipOrientation> {
        Binding(
            get: { params.orientation },
            set: { applyDiscrete(FlipModule.Params(orientation: $0)) }
        )
    }

    private func applyDiscrete(_ p: FlipModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: FlipModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_flip"))
        }
    }
}

internal struct FlipPanelProvider: IOPPanelProvider {
    var opName: String { FlipModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(FlipPanelView(instance: instance, edit: edit))
    }
}
