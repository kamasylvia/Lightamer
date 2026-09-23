import LightamerCore
import LightamerIOP
import SwiftUI

/// Inspector column (D-T6, Plan 03-02-T3/T4) — the real iop panel stack.
///
/// Lists the loaded image's non-terminal instances (v50 order — the pipe
/// order), one row per instance; the selected instance's panel renders
/// below through the `IOPPanelProvider` registry (`InspectorState`). The
/// terminal trio (colorin/colorout/gamma) is infrastructure, not editing —
/// filtered out. The `InspectorEditSession` built here is the ONE façade
/// panels use for the D-H1 trio; sessions are cheap stateless adapters
/// over the coordinator.
internal struct InspectorView: View {

    @Environment(InspectorState.self) private var inspectorState
    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    // 06-05: the layer-selection state machine (nil selection = global).
    @Environment(LayerEditingState.self) private var editingState

    /// Terminal infrastructure ops — never listed as editable panels.
    private static let terminalOps: Set<String> = [
        ColorInModule.opName, ColorOutModule.opName, GammaModule.opName,
    ]

    /// D-06-CONTEXT-5 (06-05 UI face): geometry ops are BASE-ONLY — hidden
    /// from a layer's module list and from the「添加模块」menu (the driver's
    /// `layerGeometryViolation` fatal is the backstop). crop (24.5) and
    /// enlargecanvas (16.5) ride the same list: their `modifyROIOut` would
    /// break the cross-layer composite-window invariant exactly like the
    /// rejected slots (the 06-01 D-06-01-T4-1 open question resolved here).
    /// liquify (18.0) is DISTORT|GEOMETRY too — a layer-internal liquify
    /// changes the layer's output ROI and violates the composite window.
    private static let baseOnlyOps: Set<String> = [
        LensModule.opName, AshiftModule.opName, FlipModule.opName,
        CropModule.opName, "enlargecanvas", LiquifyModule.opName,
    ]

    // MARK: GUI-11/GUI-12 layout budget (2026-09-23 fix round)
    //
    // The module list used to be an UNCONSTRAINED VStack: 26-30 seeded rows
    // filled the whole column and pushed the selected module's PANEL body
    // below the visible area (AX-reachable, visually gone — FINDINGS 05-04
    // GUI-10/11, 05-05 GUI-12, 05-06/05-07 复发确认). The list now lives in
    // a ScrollView whose height = min(estimated content, 38% of the column)
    // — short chains hug their content (no dead gap), long chains scroll,
    // and the panel body keeps ≥62% of the column (≥240pt across the
    // supported window range, 990×695 included).
    //
    // 06-05: the LAYERS PANEL joins the column's top zone (≤~210pt fixed)
    // and the module list budget shrinks accordingly — the selected panel
    // body still keeps the majority of the column.

    /// Row height estimate: `.callout` line (~16pt) + 2×6pt vertical padding
    /// (InspectorRowView label padding). Conservative — if real rows are
    /// taller, the list scrolls slightly earlier, never clips.
    private static let estimatedRowHeight: CGFloat = 28

    /// The list container's `.padding(.vertical, 4)` (top + bottom).
    private static let listVerticalPadding: CGFloat = 8

    /// Maximum share of the column the module list may claim; the selected
    /// panel keeps the rest.
    private static let listMaxFraction: CGFloat = 0.30

    /// The active layer scope (nil = the global/base chain).
    private var activeLayerID: UUID? {
        // Self-healing: a structural undo can remove the selected layer —
        // a dangling id routes back to the global scope.
        guard let id = editingState.selectedLayerID,
              editorState.adjustmentLayer(id: id) != nil
                  || editorState.retouchLayer(id: id) != nil
        else { return nil }
        return id
    }

    /// 06-07: the selected RETOUCH layer (drives the retouch panel route).
    private var selectedRetouchLayer: RetouchLayer? {
        guard let id = editingState.selectedLayerID else { return nil }
        return editorState.retouchLayer(id: id)
    }

    /// The chain records the module list shows: the selected LAYER's chain
    /// (geometry ops hidden) or the global editable set.
    private var editableInstances: [ModuleInstance] {
        if let layerID = activeLayerID,
           let layer = editorState.adjustmentLayer(id: layerID) {
            return layer.chain.filter {
                !Self.terminalOps.contains($0.opName) && !Self.baseOnlyOps.contains($0.opName)
            }
        }
        return editorState.instances.filter { !Self.terminalOps.contains($0.opName) }
    }

    /// The「添加模块」templates for the layer scope: every registered
    /// editing op that is NOT base-only (the 24 panels + testgain minus
    /// geometry). Read from the GLOBAL seed — the layer record is a fresh
    /// identity clone (`addModuleToLayer`).
    private var addableTemplates: [ModuleInstance] {
        editorState.instances.filter { !Self.terminalOps.contains($0.opName) && !Self.baseOnlyOps.contains($0.opName) }
    }

    var body: some View {
        Group {
            if editorState.loadedImageURL == nil {
                ContentUnavailableView {
                    Label("no_image_selected", systemImage: "sliders")
                } description: {
                    Text("no_image_selected_body")
                }
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // 06-05 T1: the layer stack panel — the column's top
                        // fixed zone (bottom-to-top list + operations bar).
                        LayersPanelView()
                        Divider()
                        // 06-07: a SELECTED RETOUCH layer replaces the chain
                        // list + panel with the retouch surface — the stroke
                        // list IS the layer's edit (no iop chain to list).
                        if let retouch = selectedRetouchLayer {
                            RetouchPanelView(layer: retouch)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else {
                            moduleList
                                .frame(height: moduleListHeight(in: geo.size.height))
                            Divider()
                            selectedPanel
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("Inspector")
        .accessibilityHint(Text("a11y_inspector_hint"))
        // NO container accessibilityLabel — L010: it would absorb the rows.
    }

    // MARK: - Module list

    private func moduleListHeight(in columnHeight: CGFloat) -> CGFloat {
        // 06-05: the「添加模块」menu row joins the content when a layer is
        // selected — an empty layer chain must still show it (the 0-row
        // list used to collapse to the bare padding and CLIP the menu
        // into invisibility — GUI-14).
        let menuRow: CGFloat = activeLayerID != nil ? 30 : 0
        let content = CGFloat(editableInstances.count)
            * Self.estimatedRowHeight + Self.listVerticalPadding + menuRow
        return max(min(content, columnHeight * Self.listMaxFraction), menuRow + 8)
    }

    private var moduleList: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // 06-05: layer scope「添加模块」menu — a fresh identity
                // clone of the chosen global template lands in the layer
                // chain as ONE structure commit.
                if activeLayerID != nil {
                    Menu {
                        ForEach(addableTemplates, id: \.id) { template in
                            Button(localizedLabel(for: template.opName)) {
                                if let layerID = activeLayerID {
                                    _ = editorState.addModuleToLayer(
                                        layerID: layerID, template: template)
                                }
                            }
                        }
                    } label: {
                        Label("layers_add_module", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .accessibilityIdentifier("layers.addmodule")
                }
                ForEach(editableInstances, id: \.id) { instance in
                    row(for: instance)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(LightamerColors.surface)
        }
        .accessibilityLabel(Text("a11y_module_list"))
    }

    private func row(for instance: ModuleInstance) -> some View {
        InspectorRowView(
            model: InspectorRowModel(instance: instance, isSelected: inspectorState.selectedPanel == instance.id.uuidString),
            label: localizedLabel(for: instance.opName),
            onSelect: { inspectorState.selectPanel(instanceID: instance.id) },
            onToggle: {
                let record = InspectorRowModel.toggled(instance: instance)
                // 06-05: the session carries the ACTIVE scope — a layer
                // row's toggle lands in that layer's chain (one item).
                InspectorEditSession(coordinator: pipeCoordinator, layerScope: activeLayerID)
                    .applyDiscrete(record, label: String(localized: "history_toggle"), autoEnable: false)
            }
        )
    }

    private func localizedLabel(for opName: String) -> String {
        switch opName {
        case ExposureModule.opName: return String(localized: "module_exposure")
        case TemperatureModule.opName: return String(localized: "module_temperature")
        case CropModule.opName: return String(localized: "module_crop")
        case FlipModule.opName: return String(localized: "module_flip")
        case ColorBalanceRGBModule.opName: return String(localized: "history_colorbalancergb")
        case ChannelMixerRGBModule.opName: return String(localized: "history_channelmixerrgb")
        case ChannelMixerModule.opName: return String(localized: "history_channelmixer")
        case LiquifyModule.opName: return String(localized: "module_liquify")
        case ColorContrastModule.opName: return String(localized: "history_colorcontrast")
        case VibranceModule.opName: return String(localized: "history_vibrance")
        case VelviaModule.opName: return String(localized: "history_velvia")
        case ColorZonesModule.opName: return String(localized: "history_colorzones")
        case MonochromeModule.opName: return String(localized: "history_monochrome")
        // Plan 05-06-T5: nlmeans (05-03 precedent — a new op must land with
        // its zh display name the same round, not the raw opName fallback).
        case NLMeansModule.opName: return String(localized: "history_nlmeans")
        // Plan 05-07-T6: denoiseprofile (same precedent).
        case DenoiseProfileModule.opName: return String(localized: "history_denoiseprofile")
        // Plan 05-08-T4: bilateral (same precedent).
        case BilateralModule.opName: return String(localized: "history_bilateral")
        default: return opName
        }
    }
    // MARK: - Selected panel

    @ViewBuilder
    private var selectedPanel: some View {
        // 06-05: the session carries the ACTIVE layer scope — the SAME
        // panel views edit either the global chain or the layer chain
        // (the 24-panel zero-modification contract; D-H1 semantics are
        // scope-invariant).
        let session = InspectorEditSession(coordinator: pipeCoordinator, layerScope: activeLayerID)
        // Search the ACTIVE list only; a stale selection (e.g. a global
        // instance id while a layer is selected) falls through to the
        // first active row — never a cross-scope leak.
        let selected = editableInstances.first(where: {
            $0.id.uuidString == inspectorState.selectedPanel
        }) ?? editableInstances.first
        if let effective = selected {
            Group {
                if let panel = inspectorState.panelView(for: effective, edit: session) {
                    panel
                } else {
                    ContentUnavailableView {
                        Label("inspector_no_panel", systemImage: "questionmark.square")
                    } description: {
                        Text("inspector_no_panel_body")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("inspector.panel.container")
        }
    }
}
