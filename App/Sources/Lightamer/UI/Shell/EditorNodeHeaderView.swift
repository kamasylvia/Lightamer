import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorNodeHeaderView (Plan M2-3-3 T2) — the adjustment stack's header: the
// node name + the focal/aperture/shutter/ISO readout (the Alcedo
// `EditorAdjustmentHeader` 0.3.0 form).
//
// M2-4 (Plan M2-4-2 T2): the node name is the SELECTION's —
// `PipelineDocument.displayTitle(for:)` owns the branch table (develop /
// grade name / DRT), and the unselected render keeps the v1 "Color Grade"
// constant face byte-identical (the M2-3-3 delivery contract). The EXIF legs
// read the CURRENT image's library row through the WorkspaceModel collection
// seam (one lookup, zero copying); missing columns render the "—"
// placeholder (the Alcedo empty convention).
// ─────────────────────────────────────────────────────────────────────────────

struct EditorNodeHeaderView: View {

    let workspace: WorkspaceModel

    // M2-4 (Plan M2-4-2 T2): the header reads the SELECTION through the
    // same environment objects the stack view already carries (no new
    // injection site — the values flow down the tree). With nothing
    // selected (or no stack) the render is the M2-3-3 constant face,
    // byte-identical.
    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState

    /// The graph projection of the loaded stack (nil = no image — the
    /// constants hold).
    private var document: PipelineDocument? {
        editorState.layerStack.map(PipelineDocument.init)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(nodeTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(nodeKindLabel)
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

    // MARK: - The node face (Plan M2-4-2 T2, KD-3)

    /// The node name — `PipelineDocument.displayTitle(for:)` owns the WHOLE
    /// branch table (develop → 「Develop」, grade → 层名, drt → 「Display
    /// Transform」, unselected → the "Color Grade" constant). The view adds
    /// no branching: a missing document keeps the unselected constant.
    private var nodeTitle: String {
        guard let document else {
            return String(localized: "editor_node_name", defaultValue: "Color Grade")
        }
        return document.displayTitle(for: editingState.selectedLayerID)
    }

    /// The kind subtitle follows the selected node's kind (exhaustive, no
    /// default); unselected keeps the existing `editor_node_kind` face.
    private var nodeKindLabel: String {
        switch document?.node(for: editingState.selectedLayerID)?.kind {
        case .develop:
            String(localized: "editor_node_kind", defaultValue: "Develop")
        case .grade:
            String(localized: "editor_node_kind_grade", defaultValue: "Color Grade")
        case .displayTransform:
            String(localized: "editor_node_kind_drt", defaultValue: "Display Transform")
        case nil:
            String(localized: "editor_node_kind", defaultValue: "Develop")
        }
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
