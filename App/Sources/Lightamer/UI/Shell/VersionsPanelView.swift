import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// VersionsPanelView (Plan M2-8-2 T1, KD-1; D-M2-8-CONTEXT-6) — the Versions
// rail panel: the Alcedo `EditorVersionsPanel` semantics over the P1
// `VersionCoordinator` (the M2-4-3 nodes-panel precedent — the honest
// placeholder retires, the mount switches to the live panel):
//
//   • the version LIST (name / updated_at / the ACTIVE badge — the implicit
//     single-version state shows no badge because it shows no rows),
//   • the header buttons 新建 (`createFromScratch`) + 自当前分支新建
//     (`branchFromCurrent` — both create-ACTIVATE, P1 semantics),
//   • the row contextual menu: Rename (inline TextField, commit =
//     `rename`) + Remove… (a confirmationDialog → `remove` — the P1
//     reserved confirmation-discipline payoff),
//   • row TAP = `switch(to:)` (the Alcedo "切版本即时" — chain swap +
//     param replay, milliseconds), and
//   • the EMPTY-STATE guidance (slots empty = the implicit single version):
//     the placeholder copy upgrades to guidance + the two buttons stay
//     (guidance IS action),
//   • and the read-only face (M6-1-01 omp E-OMP-1 (d)): every write control
//     (create / branch / tap-switch / rename / remove) disables off the
//     coordinator's `isReadOnly` — the same-source boolean the gate backstop
//     reads.
//
// KD-1's name rule: default-name generation lives HERE (the UI layer —
// `versions_panel_default %lld`); the coordinator commands take explicit
// names. Commit-graph visualization is a signed non-goal (OQ-2-A).
// ─────────────────────────────────────────────────────────────────────────────

struct VersionsPanelView: View {

    @Environment(VersionCoordinator.self) private var versions
    @Environment(EditorState.self) private var editorState

    /// The inline-rename target + draft (nil = closed; the alert-free
    /// inline shape — the EditorNodesPanelView rename seam, in-row).
    @State private var renameTargetID: UUID?
    @State private var renameDraft: String = ""

    /// The Remove confirmation's pending target (nil = dialog closed).
    @State private var removeTargetID: UUID?

    // MARK: - Stable markers (the test seams — Nodes panel precedent)

    static let panelMarker = "editor.versions.panel"
    static let newButtonMarker = "editor.versions.new"
    static let branchButtonMarker = "editor.versions.branch"
    static func rowMarker(id: UUID) -> String { "editor.versions.row.\(id.uuidString)" }
    static func renameButtonMarker(id: UUID) -> String {
        "editor.versions.rename.\(id.uuidString)"
    }
    static func removeButtonMarker(id: UUID) -> String {
        "editor.versions.remove.\(id.uuidString)"
    }

    /// Whether the row slot is the ACTIVE version (the badge source). The
    /// implicit single-version state has no rows — no badge by construction
    /// (P1 KD-2's implicit semantics).
    static func isActive(_ slot: VersionSlot, activeID: UUID?) -> Bool {
        slot.id == activeID
    }

    /// The UI-side default name for a NEW version (KD-1: 「版本 N」 lives
    /// here, never in the coordinator). After the implicit materialize the
    /// new slot sits at index 1 — the ordinal mirrors the coordinator's
    /// slot growth (cosmetic only; identity is the UUID).
    static func defaultVersionName(slotsCount: Int) -> String {
        let ordinal = slotsCount == 0 ? 2 : slotsCount + 1
        return String(
            localized: "versions_panel_default",
            defaultValue: "Version \(ordinal)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if versions.slots.isEmpty {
                emptyState
            } else {
                versionList
            }
        }
        .accessibilityIdentifier(Self.panelMarker)
    }

    // MARK: - The header buttons (create / branch — both create-activate)

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                versions.createFromScratch(
                    name: Self.defaultVersionName(slotsCount: versions.slots.count))
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(versions.isReadOnly)
            .accessibilityIdentifier(Self.newButtonMarker)
            .accessibilityLabel(Text(String(
                localized: "versions_panel_new", defaultValue: "New Version")))

            Button {
                versions.branchFromCurrent(
                    name: Self.defaultVersionName(slotsCount: versions.slots.count))
            } label: {
                Image(systemName: "arrow.triangle.branch")
            }
            .buttonStyle(.borderless)
            .disabled(versions.isReadOnly)
            .accessibilityIdentifier(Self.branchButtonMarker)
            .accessibilityLabel(Text(String(
                localized: "versions_panel_branch",
                defaultValue: "Branch from Current")))

            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - The empty state (the implicit single version)

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(String(
                localized: "versions_panel_empty",
                defaultValue:
                    "Create multiple looks for this photo — each version keeps its own full editing history"))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Text(String(
                localized: "versions_panel_empty_implicit",
                defaultValue: "The current edits are the implicit first version."))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            // Guidance IS action: the two header buttons stay reachable.
            HStack(spacing: 12) {
                Button {
                    versions.createFromScratch(
                        name: Self.defaultVersionName(slotsCount: versions.slots.count))
                } label: {
                    Text(String(
                        localized: "versions_panel_new", defaultValue: "New Version"))
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(versions.isReadOnly)
                .accessibilityIdentifier(Self.newButtonMarker)

                Button {
                    versions.branchFromCurrent(
                        name: Self.defaultVersionName(slotsCount: versions.slots.count))
                } label: {
                    Text(String(
                        localized: "versions_panel_branch",
                        defaultValue: "Branch from Current"))
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(versions.isReadOnly)
                .accessibilityIdentifier(Self.branchButtonMarker)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - The version list (tap = switch; menu = rename/remove)

    private var versionList: some View {
        List(versions.slots) { slot in
            row(slot)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            removeDialogTitle,
            isPresented: removeDialogBinding,
            titleVisibility: .visible
        ) {
            Button(String(
                localized: "versions_panel_remove_button",
                defaultValue: "Remove"), role: .destructive) {
                if let id = removeTargetID {
                    versions.remove(id)
                }
                removeTargetID = nil
            }
            .disabled(versions.isReadOnly)
            Button(String(
                localized: "versions_panel_cancel", defaultValue: "Cancel"),
                role: .cancel
            ) {
                removeTargetID = nil
            }
        } message: {
            Text(String(
                localized: "versions_panel_remove_confirm",
                defaultValue:
                    "The version's edit history will be deleted. This cannot be undone."))
        }
    }

    private var removeDialogTitle: String {
        guard let id = removeTargetID,
            let slot = versions.slots.first(where: { $0.id == id })
        else {
            return String(
                localized: "versions_panel_remove_title",
                defaultValue: "Remove Version")
        }
        return String(
            localized: "versions_panel_remove_title_slot",
            defaultValue: "Remove “\(slot.name)”")
    }

    /// Whether the remove confirmation is presented (the binding form keeps
    /// the dialog target answerable — nil-safe either direction).
    private var removeDialogBinding: Binding<Bool> {
        Binding(
            get: { removeTargetID != nil },
            set: { presented in
                if !presented { removeTargetID = nil }
            })
    }

    @ViewBuilder
    private func row(_ slot: VersionSlot) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if renameTargetID == slot.id {
                TextField(
                    String(
                        localized: "versions_panel_rename_field",
                        defaultValue: "Name"),
                    text: $renameDraft
                )
                .font(.caption)
                .onSubmit { commitRename(slot) }
                .onExitCommand { renameTargetID = nil }
            } else {
                Text(slot.name)
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .lineLimit(1)
            }

            if Self.isActive(slot, activeID: versions.activeVersionID) {
                Text(String(
                    localized: "versions_panel_active", defaultValue: "Active"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        Capsule()
                            .stroke(ThemeTokens.accent.opacity(0.5), lineWidth: 1))
            }

            Spacer(minLength: 4)

            // The date convention mirrors the History rows (hour/minute/
            // second caption2 — the KD-1 list spec).
            Text(slot.updatedAt, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            // Inline rename stays exclusive — a tap elsewhere closes it.
            if renameTargetID == slot.id {
                commitRename(slot)
            } else {
                renameTargetID = nil
                versions.switchTo(slot.id)
            }
        }
        // E-OMP-1 (d): tap = switchTo is a write — read-only disables the
        // whole row face (the gesture sits INSIDE this modifier so the
        // blocked state is authoritative; menu items disable explicitly).
        .disabled(versions.isReadOnly)
        .contextMenu {
            Button {
                renameTargetID = slot.id
                renameDraft = slot.name
            } label: {
                Label(
                    String(
                        localized: "versions_panel_rename",
                        defaultValue: "Rename"),
                    systemImage: "pencil")
            }
            .disabled(versions.isReadOnly)
            .accessibilityIdentifier(Self.renameButtonMarker(id: slot.id))

            Button(role: .destructive) {
                removeTargetID = slot.id
            } label: {
                Label(
                    String(
                        localized: "versions_panel_remove",
                        defaultValue: "Remove…"),
                    systemImage: "trash")
            }
            .disabled(versions.isReadOnly)
            .accessibilityIdentifier(Self.removeButtonMarker(id: slot.id))
            // Removing the LAST version is legal — the P1 remove-last
            // semantics return to the implicit single-version state.
        }
        .accessibilityIdentifier(Self.rowMarker(id: slot.id))
        .accessibilityAddTraits(
            Self.isActive(slot, activeID: versions.activeVersionID)
                ? [.isSelected] : [])
    }

    /// The inline-rename commit (the coordinator trims + refuses empty).
    private func commitRename(_ slot: VersionSlot) {
        guard renameTargetID == slot.id else { return }
        versions.rename(slot.id, to: renameDraft)
        renameTargetID = nil
    }
}
