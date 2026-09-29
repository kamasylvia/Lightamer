import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorAdjustmentStackView (Plan M2-3-3 T2, KD-2) — the seven-tab adjustment
// stack (the Alcedo `EditorAdjustmentStack` form): the tab rail + the routed
// page host + the global Preset entry.
//
// REHOMING MECHANISM (the 33-panel zero-diff contract, D12): the pages never
// modify a panel file — they INSTANCE the existing PanelViews through the
// `IOPPanelProvider` registry (`InspectorState.panelView(for:edit:)`) with
// the M1 `InspectorEditSession` D-H1 semantics (live ticks, exactly one
// commit per drag end, the active layer scope carried). The rows reuse the
// `InspectorRowView` host shape; the routing source is the
// `EditorTabRoutingTable` (the coded OQ-4 map).
//
// SPECIAL PAGES (the D3 活体壳 boundaries):
//   • Display Transform = Vignette + the "OpenDRT / ACES 2.0 arrive with
//     M2-6" placeholder section (checker E1: AgX stays unhoused — the M2-1
//     disabled face; the env=1 full-face opt-back rides the legacy flat
//     path, untouched).
//   • RAW Decode = the CIRAW parameter panel slot (T4 fills it; until then
//     the honest slot copy shows).
//   • Mask = the adjustment-layers panel (LayersPanelView) + the MaskToolbar
//     linkage note (the M2-7 Mask Groups replace this pre-home).
// ─────────────────────────────────────────────────────────────────────────────

struct EditorAdjustmentStackView: View {

    let workspace: WorkspaceModel

    @Environment(EditorState.self) private var editorState
    @Environment(InspectorState.self) private var inspectorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState

    /// The T4 RAW Decode panel's decode legs (the shell-owned actor + the
    /// coordinator's read-only Metal seam).
    private var rawDecodeMetal: MetalContext? { pipeCoordinator.detectionMetal() }

    /// The selected tab (the Alcedo default = the first page).
    @State private var selectedTab: EditorTabRoute = .tone
    /// The Geometry page's Advanced folded group (D6-only items; folded by
    /// default so the Alcedo IA face stays clean).
    @State private var advancedExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            EditorNodeHeaderView(workspace: workspace)
            Divider()
            tabBar
            Divider()
            if editorState.loadedImageURL == nil {
                ContentUnavailableView {
                    Label("no_image_selected", systemImage: "sliders")
                } description: {
                    Text("no_image_selected_body")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                pageContent(selectedTab)
            }
            Divider()
            // The global Preset entry (D4: the stack header zone carries
            // the M1 Inspector's bottom-zone panel face unchanged).
            PresetPanelView()
                .accessibilityIdentifier("editor.stack.preset.entry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ThemeTokens.cardSurface)
        .accessibilityIdentifier("editor.stack")
    }

    // MARK: - The tab rail (the Alcedo seven-tab sequence)

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(EditorTabRoute.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.label)
                        .font(.caption)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 7)
                        .foregroundStyle(
                            selectedTab == tab
                                ? ThemeTokens.textPrimary
                                : ThemeTokens.textSecondary)
                        .background(
                            selectedTab == tab
                                ? ThemeTokens.cardBorder
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.marker)
                .accessibilityLabel(Text(tab.label))
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - The routed page

    @ViewBuilder
    private func pageContent(_ tab: EditorTabRoute) -> some View {
        let session = InspectorEditSession(
            coordinator: pipeCoordinator, layerScope: activeLayerID)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                switch EditorTabRoutingTable.specialContent(for: tab) {
                case .layersPanel:
                    // The Mask page's pre-home: the adjustment-layers panel
                    // (M2-7 replaces it) + the viewport-toolbar linkage.
                    LayersPanelView()
                    maskToolbarLink
                case .rawDecodePanel:
                    // The T4 CIRAW panel (the slot's honest placeholder is
                    // gone — the panel is live).
                    RawDecodePanelView(
                        workspace: workspace,
                        decoder: workspace.editorDecoder,
                        metalContext: rawDecodeMetal)
                case .displayTransformPlaceholder:
                    drtPlaceholder
                case .none:
                    EmptyView()
                }
                pageRows(tab, session: session)
                selectedPanelBody(tab, session: session)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    /// The page's panel rows: main group first, the Advanced folded group
    /// last (Geometry's D6-only items). A descriptor with no instance in
    /// the active chain renders no row (the M1 chain-list semantics).
    private func pageRows(
        _ tab: EditorTabRoute, session: InspectorEditSession
    ) -> some View {
        let descriptors = EditorTabRoutingTable.panels(for: tab)
        let advanced = descriptors.filter { $0.isAdvancedGroup }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(
                descriptors.filter { !$0.isAdvancedGroup }, id: \.opName
            ) { descriptor in
                if let row = row(for: descriptor, session: session) {
                    row
                }
            }
            if !advanced.isEmpty {
                DisclosureGroup(isExpanded: $advancedExpanded) {
                    ForEach(advanced, id: \.opName) { descriptor in
                        if let row = row(for: descriptor, session: session) {
                            row
                        }
                    }
                } label: {
                    Text(String(
                        localized: "editor_stack_advanced",
                        defaultValue: "Advanced"))
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .accessibilityIdentifier("editor.stack.advanced")
            }
        }
    }

    /// The selected instance's panel body (the M1 selectedPanel shape —
    /// the ACTIVE chain's selection, never a cross-scope leak).
    @ViewBuilder
    private func selectedPanelBody(
        _ tab: EditorTabRoute, session: InspectorEditSession
    ) -> some View {
        let descriptors = EditorTabRoutingTable.panels(for: tab)
        let selected = scopeInstances.compactMap { instance -> (ModuleInstance, EditorPanelDescriptor)? in
            guard let descriptor = descriptors.first(where: {
                $0.opName == instance.opName
            }) else { return nil }
            return (instance, descriptor)
        }
        .first(where: { $0.0.id.uuidString == inspectorState.selectedPanel })
        ?? scopeInstances.compactMap { instance -> (ModuleInstance, EditorPanelDescriptor)? in
            guard let descriptor = descriptors.first(where: {
                $0.opName == instance.opName
            }) else { return nil }
            return (instance, descriptor)
        }
        .first
        if let (instance, _) = selected {
            Group {
                if let panel = inspectorState.panelView(for: instance, edit: session) {
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
            .accessibilityIdentifier("editor.stack.panel.container")
        }
    }

    // MARK: - Special pages

    /// The Display Transform placeholder (checker E1 勘误: NO AgX — the
    /// DRT arrives with M2-6; the honest-shell family copy).
    private var drtPlaceholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(String(
                    localized: "editor_stack_drt_placeholder",
                    defaultValue: "OpenDRT / ACES 2.0 arrive with M2-6"))
            } icon: {
                Image(systemName: "waveform.path.ecg")
            }
            .font(.caption)
            .foregroundStyle(ThemeTokens.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeTokens.cardBorder.opacity(0.15))
        .accessibilityIdentifier("editor.stack.drt.placeholder")
    }

    /// The Mask page's toolbar linkage (mask drawing happens on the
    /// viewport; the floating toolbar owns the tool face — M2-7 replaces).
    private var maskToolbarLink: some View {
        Label {
            Text(String(
                localized: "editor_stack_mask_link",
                defaultValue: "Mask tools draw on the viewport"))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
        } icon: {
            Image(systemName: "wand.and.stars")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityIdentifier("editor.stack.mask.link")
    }

    // MARK: - The M1 host shapes (scope + rows)

    /// The active layer scope (the M1 InspectorView rule verbatim: a
    /// dangling structural-undo id routes back to the global scope).
    private var activeLayerID: UUID? {
        guard let id = editingState.selectedLayerID,
            editorState.adjustmentLayer(id: id) != nil
                || editorState.retouchLayer(id: id) != nil
        else { return nil }
        return id
    }

    /// The chain records the page lists (the M1 editableInstances rule:
    /// the selected LAYER's chain minus base-only ops, or the global chain).
    private var scopeInstances: [ModuleInstance] {
        if let layerID = activeLayerID,
            let layer = editorState.adjustmentLayer(id: layerID) {
            return layer.chain.filter { !Self.baseOnlyOps.contains($0.opName) }
        }
        return editorState.instances
    }

    /// One panel row (the M1 InspectorRowView host shape + session scope).
    private func row(
        for descriptor: EditorPanelDescriptor, session: InspectorEditSession
    ) -> AnyView? {
        guard let instance = scopeInstances.first(where: {
            $0.opName == descriptor.opName
        }) else { return nil }
        let view = InspectorRowView(
            model: InspectorRowModel(
                instance: instance,
                isSelected: inspectorState.selectedPanel == instance.id.uuidString),
            label: localizedLabel(for: descriptor.opName),
            onSelect: { inspectorState.selectPanel(instanceID: instance.id) },
            onToggle: {
                let record = InspectorRowModel.toggled(instance: instance)
                InspectorEditSession(
                    coordinator: pipeCoordinator, layerScope: activeLayerID
                )
                .applyDiscrete(
                    record,
                    label: String(localized: "history_toggle"),
                    autoEnable: false)
            })
        return AnyView(view)
    }

    /// The panel display names (the M1 localizedLabel family; the default
    /// falls back to the raw opName — the M1 convention).
    private func localizedLabel(for opName: String) -> String {
        switch opName {
        case ExposureModule.opName: String(localized: "module_exposure")
        case TemperatureModule.opName: String(localized: "module_temperature")
        case CropModule.opName: String(localized: "module_crop")
        case FlipModule.opName: String(localized: "module_flip")
        case ColorBalanceRGBModule.opName: String(localized: "history_colorbalancergb")
        case ChannelMixerRGBModule.opName: String(localized: "history_channelmixerrgb")
        case ChannelMixerModule.opName: String(localized: "history_channelmixer")
        case LiquifyModule.opName: String(localized: "module_liquify")
        case ColorContrastModule.opName: String(localized: "history_colorcontrast")
        case VibranceModule.opName: String(localized: "history_vibrance")
        case VelviaModule.opName: String(localized: "history_velvia")
        case ColorZonesModule.opName: String(localized: "history_colorzones")
        case MonochromeModule.opName: String(localized: "history_monochrome")
        default: opName
        }
    }

    /// The M1 base-only ops (hidden from a layer's module list — the
    /// InspectorView constant's mirror; the layer driver's fatal backstop
    /// stays the coordinator's).
    private static let baseOnlyOps: Set<String> = [
        LensModule.opName, AshiftModule.opName, FlipModule.opName,
        CropModule.opName, LiquifyModule.opName,
    ]
}
