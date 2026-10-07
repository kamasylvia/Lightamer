import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorWorkspaceShellView (Plan M2-3-1 T2, P1 skeleton state) — the editor
// workspace's four-zone slot container. P1 delivers the SLOTS ONLY; P3 fills
// them (tool rail / viewport / filmstrip / scopes + adjustment stack — the
// OQ-3 活体壳策略 governs what lands where, and the empty-state copy family
// "<Feature> arrives in M2-x" is the honest-shell discipline).
//
// Zone order (the user revision, 2026-09-29): the FILMSTRIP rides the
// editor's LEFT edge as a vertical strip (the project's signature deviation
// from Alcedo's bottom filmstrip); then the tool rail; the viewport is the
// center hero; the scopes/adjustment column holds the trailing edge.
// ─────────────────────────────────────────────────────────────────────────────

struct EditorWorkspaceShellView: View {

    /// The shell routing state (P3 consumes the phase state; P1 renders the
    /// skeleton from the phase alone).
    let workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            slot(
                String(localized: "shell_editor_filmstrip_arrives",
                       defaultValue: "Filmstrip arrives in M2-3/P3"),
                width: 132,
                marker: "shell.editor.filmstrip.slot")
                .background(ThemeTokens.cardSurface)
            slot(
                String(localized: "shell_editor_toolrail_arrives",
                       defaultValue: "Tool rail arrives in M2-3/P3"),
                width: 56,
                marker: "shell.editor.toolrail.slot")
                .background(ThemeTokens.cardSurface)
            // The viewport hero (center, minimum-width protected).
            VStack(spacing: 8) {
                Text(String(localized: "shell_editor_viewport_arrives",
                            defaultValue: "Viewport arrives in M2-3/P3"))
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemeTokens.windowBackground)
            .accessibilityIdentifier("shell.editor.viewport.slot")
            slot(
                String(localized: "shell_editor_inspector_arrives",
                       defaultValue: "Scopes + adjustment stack arrive in M2-3/P3"),
                width: 240,
                marker: "shell.editor.inspector.slot")
                .background(ThemeTokens.cardSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.windowBackground)
    }

    /// One placeholder zone: the honest empty-state copy on the token
    /// surface, with a stable slot marker for the P3 wiring tests.
    private func slot(_ copy: String, width: CGFloat, marker: String) -> some View {
        VStack(spacing: 6) {
            Text(copy)
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(6)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .overlay(
            Rectangle()
                .fill(ThemeTokens.cardBorder)
                .frame(width: 1),
            alignment: .trailing
        )
        .accessibilityIdentifier(marker)
    }
}
