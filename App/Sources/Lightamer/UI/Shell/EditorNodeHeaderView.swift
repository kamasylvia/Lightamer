import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorNodeHeaderView (Plan M2-3-3 T2) — the adjustment stack's header: the
// node name + the focal/aperture/shutter/ISO readout (the Alcedo
// `EditorAdjustmentHeader` 0.3.0 form).
//
// v1 carries the "Color Grade" constant node name — the M2-4 node model
// replaces it with the real Develop→Grades→DRT chain (the 活体壳 boundary:
// the name is honest about being a fixed face). The EXIF legs read the
// CURRENT image's library row through the WorkspaceModel collection seam
// (one lookup, zero copying); missing columns render the "—" placeholder
// (the Alcedo empty convention).
// ─────────────────────────────────────────────────────────────────────────────

struct EditorNodeHeaderView: View {

    let workspace: WorkspaceModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(
                    localized: "editor_node_name",
                    defaultValue: "Color Grade"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(String(
                    localized: "editor_node_kind",
                    defaultValue: "Develop"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Text(focal)
                Text(aperture)
                Text(shutter)
                Text(iso)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(ThemeTokens.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.stack.nodeheader")
    }

    // MARK: - The EXIF legs (LibraryImageRow columns; nil → "—")

    private var focal: String {
        guard let focal = workspace.currentRow?.focalLength else { return dash }
        return String(format: "%.0f mm", focal)
    }

    private var aperture: String {
        guard let aperture = workspace.currentRow?.aperture, aperture > 0
        else { return dash }
        return String(format: "ƒ/%.1f", aperture)
    }

    private var shutter: String {
        guard let exposure = workspace.currentRow?.exposure, exposure > 0
        else { return dash }
        if exposure >= 1 {
            return String(format: "%.0f s", exposure)
        }
        return String(format: "1/%.0f s", 1.0 / exposure)
    }

    private var iso: String {
        guard let iso = workspace.currentRow?.iso else { return dash }
        return "ISO \(iso)"
    }

    private var dash: String {
        String(localized: "editor_node_exif_missing", defaultValue: "—")
    }
}
