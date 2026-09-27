import LightamerCore
import SwiftUI

// Plan 08-4 T1 (IOP-HDR-05) — the EDR control face: a floating top-trailing
// viewport capsule, the `SoftProofControlView` same-position sibling (the
// second display-leg runtime override).
//
// The copy discipline mirrors the soft proof face: display terms only — the
// toggle never suggests it alters the stored edit. (The headroom badge row
// lands with T3's `EDRHeadroomMonitor`.)
internal struct EDRControlView: View {

    @Environment(PipeCoordinator.self) private var pipeCoordinator

    var body: some View {
        Menu {
            Toggle(
                String(localized: "edr_toggle"),
                isOn: Binding(
                    get: { pipeCoordinator.edrDisplayEnabled },
                    set: { pipeCoordinator.setEDRDisplay($0) }
                )
            )
            .accessibilityIdentifier("edr.toggle")
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
