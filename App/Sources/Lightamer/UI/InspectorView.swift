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
                VStack(spacing: 0) {
                    moduleList
                    Divider()
                    selectedPanel
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

    private var moduleList: some View {
        VStack(spacing: 0) {
            ForEach(editableInstances, id: \.id) { instance in
                row(for: instance)
            }
        }
        .padding(.vertical, 4)
        .background(LightamerColors.surface)
    }

    private func row(for instance: ModuleInstance) -> some View {
        let isSelected = inspectorState.selectedPanel == instance.id.uuidString
        return Button {
            inspectorState.selectPanel(instanceID: instance.id)
        } label: {
            HStack {
                Image(systemName: isSelected ? "slider.horizontal.3" : "circle.dashed")
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? LightamerColors.accent : LightamerColors.textSecondary)
                Text(LocalizedStringKey(localizedLabel(for: instance.opName)))
                    .font(.callout)
                    .foregroundStyle(isSelected ? LightamerColors.textPrimary : LightamerColors.textSecondary)
                Spacer()
                if !instance.enabled {
                    Text("inspector_module_disabled")
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? LightamerColors.surfaceRaised : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector.row.\(instance.opName)")
    }

    private func localizedLabel(for opName: String) -> String {
        switch opName {
        case ExposureModule.opName: return "module_exposure"
        case TemperatureModule.opName: return "module_temperature"
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
