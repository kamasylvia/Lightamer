import LightamerCore
import SwiftUI

// Plan 13-2 T4 — the soft-proof control face (COLOR-02): a floating
// top-trailing viewport capsule (the BeforeAfterHUD overlay slot's
// trailing sibling), collapsed to a small toggle button when proof is OFF.
//
// Faces:
//   • the proof toggle (Menu primary row; ⌥⌘P from the View menu drives
//     the same route);
//   • the printer picker — the installed ColorSync catalog, RECENT first,
//     non-RGB entries construct-fail with the typed rejection toast (the
//     T1 probe's CMYK downgrade shows as a message, not a broken list);
//   • the gamut check toggle (T3 black clipping);
//   • the OOG warning state — while proof + gamut check are active the
//     capsule spells out「色域外颜色已标黑」(display terms only: the copy
//     never suggests the simulation alters the stored edit).
internal struct SoftProofControlView: View {

    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(SoftProofState.self) private var softProofState

    var body: some View {
        Menu {
            Toggle(
                String(localized: "softproof_toggle"),
                isOn: Binding(
                    get: { softProofState.isActive },
                    set: { _ in softProofState.toggle(coordinator: pipeCoordinator) }
                )
            )
            .accessibilityIdentifier("softproof.toggle")

            Divider()

            Picker(String(localized: "softproof_printer_picker"), selection: selectionBinding) {
                if !softProofState.recentNames.isEmpty {
                    Section(String(localized: "softproof_recent")) {
                        ForEach(recentEntries, id: \.url.absoluteString) { entry in
                            Text(entry.name).tag(Optional(entry))
                        }
                    }
                }
                Section(String(localized: "softproof_all_printers")) {
                    ForEach(PrinterProfileCatalog.installedProfiles(), id: \.url.absoluteString) { entry in
                        Text(entry.name).tag(Optional(entry))
                    }
                }
            }
            .accessibilityIdentifier("softproof.printer_picker")

            Divider()

            Toggle(
                String(localized: "softproof_gamut_check"),
                isOn: Binding(
                    get: { softProofState.gamutCheck },
                    set: { softProofState.setGamutCheck($0, coordinator: pipeCoordinator) }
                )
            )
            .disabled(!softProofState.isActive)
            .accessibilityIdentifier("softproof.gamut_check")
        } label: {
            capsule
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("softproof.control")
    }

    /// The collapsed face: an active proof shows the printer name (+ the
    /// OOG warning line when the gamut check is on); OFF shows a bare
    /// toggle chip.
    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: softProofState.isActive ? "printer.filled.and.paper.fill" : "printer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(softProofState.isActive ? LightamerColors.accent : LightamerColors.textSecondary)
            if softProofState.isActive {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "softproof_active_label \(softProofState.profile?.label ?? "")"))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if softProofState.gamutCheck {
                        Text("softproof_oog_active")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("softproof_toggle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(LightamerColors.border, lineWidth: 1))
        // The rejection surfaces through the status toast (D-26 face).
        .onChange(of: softProofState.lastRejection) { _, rejection in
            guard let rejection else { return }
            pipeCoordinator.presentToast(rejection)
        }
    }

    private var selectionBinding: Binding<PrinterProfileCatalog.Entry?> {
        Binding(
            get: { softProofState.selectedEntry },
            set: { entry in
                guard let entry else { return }
                softProofState.select(entry: entry, coordinator: pipeCoordinator)
            }
        )
    }

    private var recentEntries: [PrinterProfileCatalog.Entry] {
        let names = softProofState.recentNames
        return PrinterProfileCatalog.installedProfiles().filter { names.contains($0.name) }
            .sorted { a, b in
                (names.firstIndex(of: a.name) ?? .max) < (names.firstIndex(of: b.name) ?? .max)
            }
    }
}
