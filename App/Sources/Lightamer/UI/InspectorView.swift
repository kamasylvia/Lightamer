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

    /// Terminal infrastructure ops — never listed as editable panels.
    private static let terminalOps: Set<String> = [
        ColorInModule.opName, ColorOutModule.opName, GammaModule.opName,
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

    /// Row height estimate: `.callout` line (~16pt) + 2×6pt vertical padding
    /// (InspectorRowView label padding). Conservative — if real rows are
    /// taller, the list scrolls slightly earlier, never clips.
    private static let estimatedRowHeight: CGFloat = 28

    /// The list container's `.padding(.vertical, 4)` (top + bottom).
    private static let listVerticalPadding: CGFloat = 8

    /// Maximum share of the column the module list may claim; the selected
    /// panel keeps the rest.
    private static let listMaxFraction: CGFloat = 0.38

    private var editableInstances: [ModuleInstance] {
        editorState.instances.filter { !Self.terminalOps.contains($0.opName) }
    }

    var body: some View {
        Group {
            if editorState.loadedImageURL == nil {
                ContentUnavailableView {
                    Label("no_image_selected", systemImage: "sliders")
                } description: {
                    Text("no_image_selected_body")
                }
            } else if editableInstances.isEmpty {
                ContentUnavailableView {
                    Label("inspector_no_modules", systemImage: "slider.horizontal.3")
                } description: {
                    Text("inspector_no_modules_body")
                }
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        moduleList
                            .frame(height: moduleListHeight(in: geo.size.height))
                        Divider()
                        selectedPanel
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
        let content = CGFloat(editableInstances.count)
            * Self.estimatedRowHeight + Self.listVerticalPadding
        return min(content, columnHeight * Self.listMaxFraction)
    }

    private var moduleList: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
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
                InspectorEditSession(coordinator: pipeCoordinator)
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
        let session = InspectorEditSession(coordinator: pipeCoordinator)
        if let selected = editableInstances.first(where: {
            $0.id.uuidString == inspectorState.selectedPanel
        }) ?? editableInstances.first {
            // Auto-select the first editable instance when nothing is set.
            let effective = inspectorState.selectedPanel.isEmpty ? selected : selected
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
