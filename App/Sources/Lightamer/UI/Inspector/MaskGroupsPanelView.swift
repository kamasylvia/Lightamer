import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MaskGroupsPanelView (Plan M2-7-2 T2, KD-3; M2MASK-06, D-M2-7-CONTEXT-7 A) —
// the Mask Groups panel: the grade-ordered projection of
// `PipelineDocument.maskGroups` + the per-item editing face.
//
// PURE CONSUMER (the OQ-7 B veto): the panel holds NO group/item state of
// its own — the document is a per-read derivation over the observed
// `editorState.layerStack` (the NodesPanelModel precedent), and every edit
// routes through the EXISTING faces:
//
//   drag group reorder → EditorState.apply(.reconnectGrade(...))  (the
//                        M2-4 OQ-9 "one mutation, two UI faces" rule)
//   item properties    → EditorState.applyLiveMaskEdit / commitMaskEdit
//                        (the `history_mask_item_*` key family; the bump
//                        rides the commit seam — write-point ⑤)
//   add / remove item  → MaskCommand.addMaskItem / .removeMaskItem via
//                        LayerEditingState.performMaskCommand(itemID:)
//   locked delete      → spec.deletionProtected + the EXISTING toast leg
//   Locate             → LayerEditingState.locateMask (selection + tab
//                        route)
//
// The panel's ONLY owned state is the per-row thumbnail bitmaps
// ((layerID, maskHash) → CGImage row state — KD-1's "panel dumb" rule);
// GPU submissions ride the MaskThumbnailRenderer (the unique MetalContext
// routing point, L031).
// ─────────────────────────────────────────────────────────────────────────────

internal struct MaskGroupsPanelView: View {

    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    /// The per-read document projection (no second storage).
    private var document: PipelineDocument? {
        editorState.layerStack.map(PipelineDocument.init)
    }

    /// The GPU + raster-directory seam for the thumbnail cells.
    var metal: MetalContext? { pipeCoordinator.detectionMetal() }
    var maskDirectory: URL? {
        pipeCoordinator.liveImageURL.map(RasterMaskStore.masksDirectory(forImageURL:))
    }

    /// The decoded frame aspect (the thumbnail window's shape source).
    var frameExtent: SIMD2<Int> {
        guard let extent = editorState.image?.ciImage.extent,
            extent.width >= 1, extent.height >= 1
        else { return SIMD2(3, 2) }
        return SIMD2(Int(extent.width), Int(extent.height))
    }

    var body: some View {
        // The projection reads at BODY scope (the observation transaction):
        // inside the LazyVStack's deferred closure the @Observable read is
        // NOT registered and the panel never re-renders on stack changes
        // (the T8 walkthrough caught exactly that — the empty hint stayed
        // up after the first layer was added).
        let groups = document?.maskGroups ?? []
        return VStack(alignment: .leading, spacing: 4) {
            Text("mask_groups_title")
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .accessibilityIdentifier("mask.groups.title")
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if groups.isEmpty {
                        Text("mask_groups_empty_hint")
                            .font(.caption2)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                    ForEach(groups, id: \.gradeNode.id) { group in
                        groupCard(group)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 150)
        }
        .accessibilityIdentifier("mask.groups.panel")
    }

    // MARK: one group card (the grade's mask group)

    @ViewBuilder
    private func groupCard(_ group: PipelineDocument.MaskGroup) -> some View {
        let layerID = group.gradeNode.layerID
        let locked = layerID.flatMap {
            editorState.adjustmentLayer(id: $0)?.mask?.deletionProtected
        } == true
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: group.gradeNode.isEnabled ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text(group.gradeNode.name)
                    .font(.caption)
                    .lineLimit(1)
                if !group.gradeNode.isEnabled, !group.masks.isEmpty {
                    // The「Locate unfinished node」badge: a mask sitting on
                    // a DISABLED grade (the Alcedo unfinished-node face).
                    Text("mask_groups_unfinished")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(
                            ThemeTokens.cardBorder, in: RoundedRectangle(cornerRadius: 3))
                        .help(String(localized: "mask_groups_unfinished_help"))
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .accessibilityIdentifier("mask.groups.lock")
                }
                if let layerID {
                    Button {
                        editingState.select(layerID)
                        editingState.performMaskCommand(
                            .addMaskItem, editorState: editorState)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("mask_groups_add_item"))
                    .accessibilityIdentifier("mask.groups.add.\(layerID.uuidString)")
                }
            }
            if group.masks.isEmpty {
                Text("mask_groups_no_masks")
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.leading, 12)
            }
            ForEach(group.masks, id: \.id) { item in
                if let layerID {
                    MaskItemRowView(
                        item: item, layerID: layerID, locked: locked,
                        maskDirectory: maskDirectory, frameExtent: frameExtent)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mask.groups.card.\(group.gradeNode.id.uuidString)")
    }
}

// MARK: - One mask row (its own draft state — the rename TextField needs a
// real write-back Binding; the parent re-renders per stack change and the
// row summary rides each render)

private struct MaskItemRowView: View {

    let item: PipelineDocument.MaskItemSummary
    let layerID: UUID
    let locked: Bool
    let maskDirectory: URL?
    let frameExtent: SIMD2<Int>

    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    /// The rename draft (committed on submit — ONE item).
    @State private var nameDraft: String = ""

    private var liveMask: MaskSpec? { editorState.adjustmentLayer(id: layerID)?.mask }
    private var liveItem: (id: UUID, name: String?, enabled: Bool, opacity: Float, inverted: Bool)? {
        liveMask?.maskItems.first { $0.id == item.id }
    }

    var body: some View {
        HStack(spacing: 6) {
            MaskThumbnailChipView(
                layerID: layerID, mask: liveMask,
                metal: pipeCoordinator.detectionMetal(),
                maskDirectory: maskDirectory, frameExtent: frameExtent)
                .accessibilityIdentifier("mask.groups.chip.\(item.id.uuidString)")

            TextField(
                item.name ?? derivedName,
                text: Binding(
                    get: { nameDraft.isEmpty ? (item.name ?? "") : nameDraft },
                    set: { nameDraft = $0 }))
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit { commitRename() }
                .accessibilityIdentifier("mask.groups.name.\(item.id.uuidString)")

            Spacer()

            // enabled gate (one commit per toggle).
            Button {
                editorState.commitMaskEdit(
                    layerID: layerID,
                    label: String(localized: "history_mask_item_enabled")
                ) { mask in
                    mask.setItemEnabled(item.id, !(liveItem?.enabled ?? true))
                }
            } label: {
                Image(systemName: item.isEnabled ? "checkmark.square" : "square")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("mask_groups_item_enabled"))
            .accessibilityIdentifier("mask.groups.enabled.\(item.id.uuidString)")

            // invert bit (one commit per toggle).
            Button {
                editorState.commitMaskEdit(
                    layerID: layerID,
                    label: String(localized: "history_mask_item_inverted")
                ) { mask in
                    mask.setItemInverted(item.id, !(liveItem?.inverted ?? false))
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption2)
                    .opacity(item.isInverted ? 1 : 0.45)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("mask_groups_item_invert"))
            .accessibilityValue(item.isInverted ? Text("toggle_on") : Text("toggle_off"))
            .accessibilityIdentifier("mask.groups.invert.\(item.id.uuidString)")

            // Locate (selection + tab route; the unfinished-node jump).
            Button {
                editingState.locateMask(layerID: layerID)
            } label: {
                Image(systemName: "scope")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("mask_groups_locate"))
            .accessibilityIdentifier("mask.groups.locate.\(item.id.uuidString)")

            // Remove (the locked row intercepts inside the command leg —
            // the SAME double-leg toast as clear/fill).
            Button {
                editingState.select(layerID)
                editingState.performMaskCommand(
                    .removeMaskItem, itemID: item.id, editorState: editorState)
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .disabled(locked)
            .accessibilityLabel(Text("mask_groups_item_remove"))
            .accessibilityIdentifier("mask.groups.remove.\(item.id.uuidString)")
        }
        // The two continuous item properties on a SECOND line (D-H1: the
        // slider renders live, commits ONCE at drag end — the bump rides
        // the commit seam).
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("mask_groups_item_opacity")
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Slider(
                    value: Binding(
                        get: { Double(liveItem?.opacity ?? 1) },
                        set: { newValue in
                            editorState.applyLiveMaskEdit(layerID: layerID) { mask in
                                mask.setItemOpacity(item.id, Float(newValue))
                            }
                        }),
                    in: 0.0...1.0
                ) { dragging in
                    if !dragging { commitSlider("history_mask_item_opacity") { mask, current in
                        mask.setItemOpacity(item.id, current.opacity)
                    } }
                }
                .controlSize(.mini)
                .accessibilityLabel(Text("mask_groups_item_opacity"))
                .accessibilityIdentifier("mask.groups.opacity.\(item.id.uuidString)")
            }
            HStack(spacing: 4) {
                Text("mask_groups_item_feather")
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Slider(
                    value: Binding(
                        get: {
                            let live = editorState.adjustmentLayer(id: layerID)?
                                .mask?.drawn?.group?.items.first { $0.formID == item.id }
                            return Double(live?.feather ?? 0)
                        },
                        set: { newValue in
                            editorState.applyLiveMaskEdit(layerID: layerID) { mask in
                                mask.setItemFeather(item.id, Float(newValue))
                            }
                        }),
                    in: 0.0...5.0
                ) { dragging in
                    if !dragging {
                        // The dt gate applies at the render leg; the record
                        // keeps the raw value (the >0.1 gate is the combiner's).
                        editorState.commitMaskEdit(
                            layerID: layerID,
                            label: String(localized: "history_mask_item_feather")
                        ) { mask in
                            let live = editorState.adjustmentLayer(id: layerID)?
                                .mask?.drawn?.group?.items.first { $0.formID == item.id }
                            mask.setItemFeather(item.id, live?.feather ?? 0)
                        }
                    }
                }
                .controlSize(.mini)
                .accessibilityLabel(Text("mask_groups_item_feather"))
                .accessibilityIdentifier("mask.groups.feather.\(item.id.uuidString)")
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // KD-3 联动选中: row selection arms the layer scope and disarms
            // the tool (the overlay handles follow the existing gate).
            editingState.select(layerID)
            editingState.setTool(nil)
        }
    }

    /// The D-H1 commit leg for the item sliders: read the CURRENT live
    /// value back through the item facade and land it ONCE (the seam
    /// bumps — exactly one history item per drag).
    private func commitSlider(
        _ labelKey: String, _ apply: @escaping (inout MaskSpec, (id: UUID, name: String?, enabled: Bool, opacity: Float, inverted: Bool)) -> Void
    ) {
        editorState.commitMaskEdit(
            layerID: layerID,
            label: String(localized: String.LocalizationValue(labelKey))
        ) { mask in
            if let current = liveItem {
                apply(&mask, current)
            }
        }
    }

    /// The derived display name (KD-3: the Core `nextLayerName` single
    /// source — never a second ordinal algorithm).
    private var derivedName: String {
        guard let stack = editorState.layerStack else { return "Mask" }
        return stack.nextLayerName(base: String(localized: "mask_row_default_name"))
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        nameDraft = ""
        editorState.commitMaskEdit(
            layerID: layerID,
            label: String(localized: "history_mask_item_name")
        ) { mask in
            mask.setItemDisplayName(item.id, trimmed.isEmpty ? nil : trimmed)
        }
    }
}

// MARK: - The shared thumbnail chip (renderer output; T2's visual language)

/// The GPU thumbnail cell (KD-1): `MaskThumbnailRenderer` output — the ONE
/// visual language for the layer-row chip AND the Mask Groups rows. The
/// row state is exactly `(maskHash) → CGImage` (the "panel dumb" rule);
/// a nil spec / no GPU / empty payload shows the placeholder frame (never
/// a crash, never a quiet blank frame). The renderer creates no queue of
/// its own (AC9) — the caller's MetalContext is the only routing point.
internal struct MaskThumbnailChipView: View {

    let layerID: UUID
    let mask: MaskSpec?
    let metal: MetalContext?
    let maskDirectory: URL?
    let frameExtent: SIMD2<Int>

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(image, scale: 1, label: Text("layers_mask_chip"))
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary.opacity(0.4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(.secondary.opacity(0.5), lineWidth: 1)
                    }
            }
        }
        .frame(width: 34, height: 26)
        .task(id: mask?.stableHash()) { await render() }
    }

    /// The v1 geometry note (the display-overlay precedent): the mapper is
    /// the IDENTITY chain at the thumbnail scale — upstream frame-changing
    /// geometry may misalign the thumbnail the same way it may misalign
    /// the display tint (the shared follow-up).
    private func render() async {
        guard let mask, mask.hasAnyPayload, let metal else {
            image = nil
            return
        }
        let thumb = MaskThumbnailRenderer.thumbnailSize(forLayerWindow: frameExtent)
        let size = SIMD2<Double>(Double(thumb.x), Double(thumb.y))
        let mapper = GeometryPointMapper(frameSize: size, segments: [], outputSize: size)
        var cache = MaskThumbnailCache()
        image = try? await MaskThumbnailRenderer.render(
            spec: mask, size: MaskThumbnailRenderer.thumbLongEdge, metal: metal,
            mapper: mapper, maskDirectory: maskDirectory, cache: &cache)
    }
}
