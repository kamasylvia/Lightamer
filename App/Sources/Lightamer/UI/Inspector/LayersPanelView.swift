import LightamerCore
import LightamerIOP
import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────
// LayersPanelView (Plan 06-05 T1) — the C1-style adjustment-layer panel,
// mounted in the Inspector's top fixed zone (≤280pt budget; the viewport
// keeps ≥50% — the panel四件套 width rule).
//
// Layout (bottom-to-top composite order, the base layer pinned LAST):
//   [ toolbar: add / duplicate / mergeDown / delete ‖ 显示蒙版 toggle ]
//   [ layer rows, bottom-to-top: eye ‖ name (inline rename) + blend
//     Picker + opacity slider (D-H1) ‖ mask chip ]
//   [ base row: selection = the GLOBAL chain ]
//
// Every mutation lands EXACTLY ONE history item through `EditorState`:
//   add / duplicate / mergeDown / delete / reorder / rename / blend /
//   visibility / opacity drag-end / mask stroke-end — all stackSnapshot
//   型; layer-scoped module param edits ride the `layerScope` 型 (T4).
//
// Panel四件套 (the hard checklist): L010 accessibilityIdentifiers
// (`layer.row.<uuid>` — stable ids, NOT indexes) + zh/en String Catalog
// (every label below) + the 280pt constraint (fixed-height scroll region;
// never pushes the viewport) + D-H1 (opacity drag renders live, commits
// once at drag end).
// ─────────────────────────────────────────────────────────────────────────

internal struct LayersPanelView: View {

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState

    /// The picker order (dt slot semantics per D-06-02-T5-1 — the JzCzhz
    /// perceptual family carries its Lightamer naming).
    static let blendOrder: [LightamerCore.BlendMode] = [
        .normal, .multiply, .linearBurn, .screen, .overlay, .softLight,
        .hardLight, .lighten, .darken, .psColorDodge, .psColorBurn,
        .difference, .luminosity, .saturation, .hue, .color, .colorAdjust,
    ]

    static func blendLabel(
        _ mode: LightamerCore.BlendMode
    ) -> LocalizedStringResource {
        switch mode {
        case .normal: return "blend_normal"
        case .multiply: return "blend_multiply"
        case .linearBurn: return "blend_linear_burn"
        case .screen: return "blend_screen"
        case .overlay: return "blend_overlay"
        case .softLight: return "blend_soft_light"
        case .hardLight: return "blend_hard_light"
        case .lighten: return "blend_lighten"
        case .darken: return "blend_darken"
        case .psColorDodge: return "blend_color_dodge"
        case .psColorBurn: return "blend_color_burn"
        case .difference: return "blend_difference"
        case .luminosity: return "blend_luminosity"
        case .saturation: return "blend_saturation"
        case .hue: return "blend_hue"
        case .color: return "blend_color"
        case .colorAdjust: return "blend_color_adjust"
        }
    }

    /// ALL non-base layers (both kinds since 06-07 — the retouch rows
    /// render through `RetouchLayerRowView`).
    private var layers: [any Layer] {
        editorState.layerStack?.adjustmentLayers ?? []
    }

    var body: some View {
        VStack(spacing: 4) {
            toolbar
            if layers.isEmpty {
                Text("layers_empty_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            // Bottom-to-top display: reverse the composite order; the base
            // row pins BELOW everything (visually the stack's floor).
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(layers.reversed(), id: \.id) { layer in
                        Group {
                            if let retouch = layer as? RetouchLayer {
                                RetouchLayerRowView(layer: retouch)
                            } else if let adjustment = layer as? AdjustmentLayer {
                                LayerRowView(layer: adjustment)
                            }
                        }
                        .background {
                            // Drop target for the drag-reorder (1 commit
                            // at the drop; identities untouched — NDE-1).
                            DropReorderRegion(layerID: layer.id)
                        }
                    }
                    baseRow
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 190) // the 280pt budget (panel + toolbar)
        }
        .padding(.vertical, 4)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("layers.panel")
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                if let layer = editorState.addAdjustmentLayer() {
                    editingState.select(layer.id)
                    pipeCoordinator.setHotLayer(layer.id)
                }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_add"))
            .accessibilityIdentifier("layers.add")
            .disabled(editorState.layerStack == nil)

            // 06-07: the retouch layer (IOP-GEO-06) — its strokes are the
            // layer's edit; the viewport becomes the stroke editor while
            // the retouch surface is selected.
            Button {
                if let layer = editorState.addRetouchLayer() {
                    editingState.select(layer.id)
                    pipeCoordinator.setHotLayer(layer.id)
                }
            } label: {
                Image(systemName: "bandage")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_add_retouch"))
            .accessibilityIdentifier("layers.addRetouch")
            .disabled(editorState.layerStack == nil)

            Button {
                if let selected = editingState.selectedLayerID,
                   let copy = editorState.duplicateLayer(id: selected) {
                    editingState.select(copy.id)
                }
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_duplicate"))
            .accessibilityIdentifier("layers.duplicate")
            .disabled(editingState.selectedLayerID == nil)

            Button {
                if let selected = editingState.selectedLayerID {
                    editorState.mergeLayerDown(id: selected)
                    editingState.select(nil)
                }
            } label: {
                Image(systemName: "arrowshape.down.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_merge_down"))
            .accessibilityIdentifier("layers.merge")
            .disabled(editingState.selectedLayerID == nil)

            Button {
                if let selected = editingState.selectedLayerID {
                    editorState.removeLayer(id: selected)
                    editingState.select(nil)
                    pipeCoordinator.setHotLayer(nil)
                    pipeCoordinator.setMaskOverlayRequest(nil)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_delete"))
            .accessibilityIdentifier("layers.delete")
            .disabled(editingState.selectedLayerID == nil)

            Spacer()

            // 「显示蒙版」(the 06-3 render leg on the SELECTED layer).
            Button {
                editingState.showsMaskOverlay.toggle()
                refreshMaskOverlayRequest()
            } label: {
                Image(systemName: editingState.showsMaskOverlay ? "circle.dashed" : "eye.trianglebadge.exclamationmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_show_mask"))
            .accessibilityIdentifier("layers.showmask")
            .disabled(editingState.selectedLayerID == nil)
        }
        .padding(.horizontal, 6)
        .font(.callout)
    }

    /// Re-issue (or clear) the display overlay for the selected layer.
    private func refreshMaskOverlayRequest() {
        guard let id = editingState.selectedLayerID,
              let layer = editorState.adjustmentLayer(id: id),
              layer.mask?.hasAnyPayload == true,
              editingState.showsMaskOverlay
        else {
            pipeCoordinator.setMaskOverlayRequest(nil)
            return
        }
        pipeCoordinator.setMaskOverlayRequest(
            (id, 0.85, editingState.maskOverlayStyle))
    }

    /// The base layer row: selection = the global chain (nil layer scope).
    /// No eye (the base `isVisible` gates the whole composite — not a v1
    /// control) and no per-row operations.
    private var baseRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
            Text("layers_base_name")
                .font(.caption)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            Group {
                if editingState.selectedLayerID == nil {
                    LightamerColors.accent.opacity(0.25)
                } else {
                    Color.clear
                }
            }
            .background(DropReorderRegion(layerID: nil))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingState.select(nil)
            pipeCoordinator.setHotLayer(nil)
            pipeCoordinator.setMaskOverlayRequest(nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("layers_base_name"))
        .accessibilityIdentifier("layer.row.base")
    }
}

// MARK: - One layer row

private struct LayerRowView: View {
    let layer: AdjustmentLayer

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState

    /// The inline rename draft (committed on submit — ONE structure item).
    @State private var nameDraft: String = ""

    private var isSelected: Bool { editingState.selectedLayerID == layer.id }
    private var rowID: String { "layer.row.\(layer.id.uuidString)" }

    var body: some View {
        HStack(spacing: 6) {
            // ── visibility eye (1 structure commit per toggle) ──
            Button {
                var copy = layerSnapshot()
                copy.isVisible.toggle()
                editorState.commitLayerEdit(
                    copy, label: String(localized: "history_layer_visibility"))
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_visibility"))
            .accessibilityValue(layer.isVisible ? Text("toggle_on") : Text("toggle_off"))
            .accessibilityIdentifier(rowID + ".eye")

            // ── enable checkbox (13-3 T5: the `enabled` field's UI face —
            // the LayerCompositeDriver's per-layer render gate; 1 commit) ──
            Button {
                var copy = layerSnapshot()
                copy.enabled.toggle()
                editorState.commitLayerEdit(
                    copy, label: String(localized: "history_layer_enable"))
            } label: {
                Image(systemName: liveLayer()?.enabled == true
                    ? "checkmark.square" : "square")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_enable"))
            .accessibilityValue(liveLayer()?.enabled == true
                ? Text("toggle_on") : Text("toggle_off"))
            .accessibilityIdentifier(rowID + ".enable")

            // ── name (inline rename) + blend Picker + opacity ──
            VStack(alignment: .leading, spacing: 2) {
                TextField(
                    String(localized: "layers_name_placeholder"),
                    text: Binding(
                        get: { nameDraft.isEmpty ? layer.name : nameDraft },
                        set: { nameDraft = $0 }))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { commitRename() }
                    .accessibilityIdentifier(rowID + ".name")

                HStack(spacing: 4) {
                    Menu {
                        ForEach(LayersPanelView.blendOrder, id: \.rawValue) { mode in
                            Button {
                                guard mode != layer.blendMode else { return }
                                var copy = layerSnapshot()
                                copy.blendMode = mode
                                editorState.commitLayerEdit(
                                    copy, label: String(localized: "history_layer_blend"))
                            } label: {
                                Text(LayersPanelView.blendLabel(mode))
                            }
                        }
                    } label: {
                        Text(LayersPanelView.blendLabel(layer.blendMode))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .accessibilityLabel(Text("layers_blend"))
                    .accessibilityIdentifier(rowID + ".blend")

                    Spacer()

                    Slider(
                        value: Binding(
                            get: { Double(liveLayer()?.opacity ?? layer.opacity) },
                            set: { newValue in
                                // D-H1 live leg: render updates, ZERO history.
                                var copy = layerSnapshot()
                                copy.opacity = Float(newValue)
                                editorState.applyLiveLayer(copy)
                            }),
                        in: 0...1
                    ) { dragging in
                        if !dragging {
                            // D-H1 commit leg: exactly ONE structure item,
                            // reading the CURRENT live layer (the final
                            // tick's copy — never the render-time stale one).
                            guard let live = liveLayer() else { return }
                            editorState.commitLayerEdit(
                                live, label: String(localized: "history_layer_opacity"))
                        }
                    }
                    .controlSize(.mini)
                    .accessibilityLabel(Text("layers_opacity"))
                    .accessibilityIdentifier(rowID + ".opacity")
                }
            }

            // ── mask chip (T2: the GPU thumbnail — the renderer output is
            // the ONE visual language shared with the Mask Groups rows;
            // the CPU-schematic MaskChipView is RETIRED) ──
            MaskThumbnailChipView(
                layerID: layer.id, mask: layer.mask,
                metal: pipeCoordinator.detectionMetal(),
                maskDirectory: pipeCoordinator.liveImageURL.map(
                    RasterMaskStore.masksDirectory(forImageURL:)),
                frameExtent: chipFrameExtent)
                .accessibilityIdentifier(rowID + ".chip")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            Group {
                if isSelected {
                    LightamerColors.accent.opacity(0.25)
                } else {
                    Color.clear
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingState.select(layer.id)
            pipeCoordinator.setHotLayer(layer.id)
            refreshMaskOverlayRequest()
        }
        // 13-3 T5: the mask COMMAND face (Duplicate / Duplicate-and-
        // Invert / Fill / Clear / Reset Edits) on the row's context menu.
        // The command targets the RIGHT-CLICKED row (it selects first);
        // routing rides `LayerEditingState.performMaskCommand` → the
        // existing commit entries (each step ONE history item).
        // M2-7-2 (checker M5): the menu enumerates the panelMenuCases
        // WHITELIST — the item commands (add/removeMaskItem) are panel-row
        // actions with an itemID seam and never leak into the layer menu.
        .contextMenu {
            ForEach(MaskCommand.panelMenuCases, id: \.rawValue) { command in
                Button(String(localized: String.LocalizationValue(command.labelKey))) {
                    editingState.select(layer.id)
                    pipeCoordinator.setHotLayer(layer.id)
                    editingState.performMaskCommand(command, editorState: editorState)
                }
            }
        }
        // Drag source: a plain string UUID payload (the DropReorderRegion
        // decodes it into ONE `reorderLayer` commit at the drop).
        .onDrag {
            NSItemProvider(object: layer.id.uuidString as NSString)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(layer.name))
        .accessibilityIdentifier(rowID)
    }

    /// The decoded frame aspect for the thumbnail window (the chip's
    /// shape source; the no-image fallback keeps a 3:2 face).
    private var chipFrameExtent: SIMD2<Int> {
        guard let extent = editorState.image?.ciImage.extent,
            extent.width >= 1, extent.height >= 1
        else { return SIMD2(3, 2) }
        return SIMD2(Int(extent.width), Int(extent.height))
    }

    /// The CURRENT stack object for this row's id (the live leg replaces
    /// the stack's instance each tick — the render-time `layer` let can
    /// go stale mid-drag; history commits must read the live one).
    private func liveLayer() -> AdjustmentLayer? {
        editorState.adjustmentLayer(id: layer.id)
    }

    private func layerSnapshot() -> AdjustmentLayer {
        let source = liveLayer() ?? layer
        // A value copy with the SAME identity (the commit re-installs it).
        return AdjustmentLayer(
            id: source.id, name: source.name, isVisible: source.isVisible,
            opacity: source.opacity, blendMode: source.blendMode,
            blendOptions: source.blendOptions, enabled: source.enabled,
            chain: source.chain, mask: source.mask)
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != layer.name else {
            nameDraft = ""
            return
        }
        var copy = layerSnapshot()
        copy.name = trimmed
        editorState.commitLayerEdit(copy, label: String(localized: "history_layer_rename"))
        nameDraft = ""
    }

    private func refreshMaskOverlayRequest() {
        guard layer.mask?.hasAnyPayload == true, editingState.showsMaskOverlay else {
            pipeCoordinator.setMaskOverlayRequest(nil)
            return
        }
        pipeCoordinator.setMaskOverlayRequest(
            (layer.id, 0.85, editingState.maskOverlayStyle))
    }
}

// MARK: - Mask chip — RETIRED (Plan M2-7-2 T2)

// The CPU-schematic `MaskChipView` (the 06-05 v1 snapshot policy) is
// replaced by `MaskThumbnailChipView` (MaskGroupsPanelView.swift): the GPU
// thumbnail pass over the unchanged assembly — the documented follow-up
// from D-06-05-T1-1, now landed ("a low-res GPU plane snapshot" became the
// shared renderer; the schematic is gone, git-revert single-file reversible).

// MARK: - Drag-reorder drop region

/// The drop target behind one row: dropping a layer UUID on it moves the
/// dragged layer to this row's index — ONE `reorderLayer` commit
/// (stackSnapshot 型, undo restores the order). `layerID` nil = the base
/// row (target index 0).
private struct DropReorderRegion: View {
    let layerID: UUID?
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Color.clear
            .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let string = object as? String,
                          let dragged = UUID(uuidString: string)
                    else { return }
                    Task { @MainActor in
                        let layers = editorState.layerStack?.adjustmentLayers ?? []
                        guard let from = layers.firstIndex(where: { $0.id == dragged })
                        else { return }
                        let target = layerID.flatMap { id in
                            layers.firstIndex(where: { $0.id == id })
                        } ?? 0
                        guard target != from else { return }
                        editorState.reorderLayer(id: dragged, to: target)
                    }
                }
                return true
            }
    }
}

// MARK: - The retouch layer row (06-07)

/// The RetouchLayer row: the same eye / rename / blend / opacity surface
/// (the container reuse IS the point), with a STROKE-COUNT chip where the
/// adjustment row carries the mask chip (retouch is dt NO_MASKS — there is
/// no mask to chip; the strokes ARE the edit). All commits ride
/// `commitRetouchEdit` (exactly ONE structure item each).
private struct RetouchLayerRowView: View {
    let layer: RetouchLayer

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState

    @State private var nameDraft: String = ""

    private var isSelected: Bool { editingState.selectedLayerID == layer.id }
    private var rowID: String { "layer.row.\(layer.id.uuidString)" }

    var body: some View {
        HStack(spacing: 6) {
            // ── visibility eye (1 structure commit per toggle) ──
            Button {
                let copy = liveSnapshot()
                copy.isVisible.toggle()
                editorState.commitRetouchEdit(
                    copy, label: String(localized: "history_layer_visibility"))
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("layers_visibility"))
            .accessibilityValue(layer.isVisible ? Text("toggle_on") : Text("toggle_off"))
            .accessibilityIdentifier(rowID + ".eye")

            // ── name + blend + opacity ──
            VStack(alignment: .leading, spacing: 2) {
                TextField(
                    String(localized: "layers_name_placeholder"),
                    text: Binding(
                        get: { nameDraft.isEmpty ? layer.name : nameDraft },
                        set: { nameDraft = $0 }))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { commitRename() }
                    .accessibilityIdentifier(rowID + ".name")

                HStack(spacing: 4) {
                    Menu {
                        ForEach(LayersPanelView.blendOrder, id: \.rawValue) { mode in
                            Button {
                                guard mode != layer.blendMode else { return }
                                let copy = liveSnapshot()
                                copy.blendMode = mode
                                editorState.commitRetouchEdit(
                                    copy, label: String(localized: "history_layer_blend"))
                            } label: {
                                Text(LayersPanelView.blendLabel(mode))
                            }
                        }
                    } label: {
                        Text(LayersPanelView.blendLabel(layer.blendMode))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .accessibilityLabel(Text("layers_blend"))
                    .accessibilityIdentifier(rowID + ".blend")

                    Spacer()

                    Slider(
                        value: Binding(
                            get: { Double(liveLayer()?.opacity ?? layer.opacity) },
                            set: { newValue in
                                // D-H1 live leg: render updates, ZERO history.
                                var copy = liveSnapshot()
                                copy.opacity = Float(newValue)
                                editorState.applyLiveRetouch(copy)
                            }),
                        in: 0...1
                    ) { dragging in
                        if !dragging {
                            guard let live = liveLayer() else { return }
                            editorState.commitRetouchEdit(
                                live, label: String(localized: "history_layer_opacity"))
                        }
                    }
                    .controlSize(.mini)
                    .accessibilityLabel(Text("layers_opacity"))
                    .accessibilityIdentifier(rowID + ".opacity")
                }
            }

            // ── stroke-count chip (NO_MASKS: the shapes ARE the mask) ──
            Text(verbatim: "\(layer.strokes.count)")
                .font(.caption2)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background { RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.4)) }
                .accessibilityLabel(Text("layers_stroke_count"))
                .accessibilityValue("\(layer.strokes.count)")
                .accessibilityIdentifier(rowID + ".strokes")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            Group {
                if isSelected {
                    LightamerColors.accent.opacity(0.25)
                } else {
                    Color.clear
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingState.select(layer.id)
            pipeCoordinator.setHotLayer(layer.id)
        }
        .onDrag {
            NSItemProvider(object: layer.id.uuidString as NSString)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(layer.name))
        .accessibilityIdentifier(rowID)
    }

    private func liveLayer() -> RetouchLayer? {
        editorState.retouchLayer(id: layer.id)
    }

    private func liveSnapshot() -> RetouchLayer {
        let source = liveLayer() ?? layer
        return RetouchLayer(
            id: source.id, name: source.name, isVisible: source.isVisible,
            opacity: source.opacity, blendMode: source.blendMode,
            blendOptions: source.blendOptions, enabled: source.enabled,
            strokes: source.strokes)
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != layer.name else {
            nameDraft = ""
            return
        }
        let copy = liveSnapshot()
        copy.name = trimmed
        editorState.commitRetouchEdit(copy, label: String(localized: "history_layer_rename"))
        nameDraft = ""
    }
}
