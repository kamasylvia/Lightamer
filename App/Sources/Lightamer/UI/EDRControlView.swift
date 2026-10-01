import LightamerCore
import SwiftUI

// Plan 08-4 T1 (IOP-HDR-05) — the EDR control face: a floating top-trailing
// viewport capsule, the `SoftProofControlView` same-position sibling (the
// second display-leg runtime override).
//
// Faces:
//   • the HDR preview toggle (viewport-level, never a document parameter —
//     D-08-CONTEXT-12: no history item, no sidecar record, no export leg);
//   • the headroom badge slot (T3): the display's EDR headroom value, with
//     the「当前显示器无 EDR 余量」warning line at headroom == 1.0 (the P4
//     semantics: the toggle stays LEGAL on a headroom-1.0 display — the
//     compositor clamps >1.0 values to SDR white, no auto-fallback).
//
// The copy discipline mirrors the soft proof face: display terms only — the
// toggle never suggests it alters the stored edit.
internal struct EDRControlView: View {

    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(EDRHeadroomMonitor.self) private var headroomMonitor

    var body: some View {
        Menu {
            Toggle(
                String(localized: "edr_toggle"),
                isOn: Binding(
                    get: { pipeCoordinator.edrDisplayEnabled },
                    set: { pipeCoordinator.setEDRDisplay($0) }
                )
            )
            // M2-6-3 KD-4: the DRT tail OWNS the display surface while a
            // non-pristine DRT record is in effect — the manual toggle is
            // DISABLED there (置灰; the coordinator guard is the state
            // backstop — 旁路).
            .disabled(pipeCoordinator.drtTailActive)
            .accessibilityIdentifier("edr.toggle")

            Divider()
            // Headroom is a PASSIVE readout (T3): headroom > 1.0 renders as
            // extra brightness — never as a second color space (SC#3); at
            // exactly 1.0 (the P4 SDR-only rig) the toggle stays legal and
            // the warning line spells out the missing headroom.
            Group {
                if headroomMonitor.hasEDRHeadroom {
                    Text(String(localized: "edr_headroom_label \(String(format: "%.1f", headroomMonitor.headroom))"))
                        .foregroundStyle(Color.secondary)
                } else {
                    Text("edr_no_headroom")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 10))
            .accessibilityIdentifier("edr.headroom")
        } label: {
            capsule
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("edr.control")
    }

    /// The collapsed face: the active state lights the icon and spells the
    /// state; OFF shows a bare chip (the soft proof capsule's shape).
    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "hdr")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    pipeCoordinator.edrDisplayEnabled
                        ? LightamerColors.accent : LightamerColors.textSecondary)
            Text(String(localized: "edr_toggle"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    pipeCoordinator.edrDisplayEnabled
                        ? LightamerColors.accent : LightamerColors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(LightamerColors.border, lineWidth: 1))
    }
}
