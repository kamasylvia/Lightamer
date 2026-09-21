import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// InspectorRowView (Plan 04-08-T4, GUI-5) — one module row: the enable
// circle is a REAL toggle button bound to `instance.enabled` (the true
// state source), the label selects the panel.
//
// dt semantics: enabled = filled circle (D-08-T4-1). The circle used to be
// a selection-driven decoration (`isSelected ? slider : circle.dashed` —
// invisible when selected, always hollow otherwise = GUI-5). Shape is now
// enabled-driven (`circle.fill` vs `circle.dashed`); selection keeps its
// color/background/text semantics.
//
// L010: the row container carries ONLY an identifier; the toggle button is
// a separate AX element (identifier + label + on/off value) so it stays
// reachable (GUI-5: "模块行按钮无独立启用开关子元素").
// ─────────────────────────────────────────────────────────────────────────

/// The testable row state: shape key + AX value, derived from the record.
internal struct InspectorRowModel: Equatable, Sendable {
    let opName: String
    let enabled: Bool
    let isSelected: Bool

    init(instance: ModuleInstance, isSelected: Bool) {
        self.opName = instance.opName
        self.enabled = instance.enabled
        self.isSelected = isSelected
    }

    /// SF Symbol for the enable circle (enabled = filled).
    var circleSymbol: String { enabled ? "circle.fill" : "circle.dashed" }

    /// AX value for the toggle ("on"/"off" map to localized keys).
    var toggleValueKey: String { enabled ? "toggle_on" : "toggle_off" }

    /// The toggled record (pure — the caller commits it discretely).
    static func toggled(instance: ModuleInstance) -> ModuleInstance {
        var record = instance
        record.enabled.toggle()
        return record
    }
}

internal struct InspectorRowView: View {

    let model: InspectorRowModel
    let label: String
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack {
            // 04-08-F3 (GUI-5 AX 通路)：自绘圆圈 Image 必须包在真实 Button
            // 内才有 AXPress —— 此处结构已是 Button（select 路径同构可按即
            // 验收 PASS 的反证）。央行加固两处 AX 语义，确保 AXPress 落到
            // action：① accessibilityAddTraits(.isButton) —— 纯 Image label
            // 的 Button 在 AX 树里曾被识别为静态图（无 Press 动作）；②
            // accessibilityAction(.default) 显式把 Press 路由到 onToggle，
            // 不依赖 SwiftUI 的隐式转发行（本轮 System Events click/AXPress
            // 均不触发 action 的直接修复；PanelWiring 语义测试钉住下层）。
            Button {
                onToggle()
            } label: {
                Image(systemName: model.circleSymbol)
                    .frame(width: 16)
                    .foregroundStyle(model.isSelected ? LightamerColors.accent : LightamerColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inspector.row.\(model.opName).toggle")
            .accessibilityLabel(Text("inspector_row_toggle"))
            .accessibilityValue(Text(LocalizedStringKey(model.toggleValueKey)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onToggle() }
            Button {
                onSelect()
            } label: {
                HStack {
                    Text(LocalizedStringKey(label))
                        .font(.callout)
                        .foregroundStyle(model.isSelected ? LightamerColors.textPrimary : LightamerColors.textSecondary)
                    Spacer()
                    if !model.enabled {
                        Text("inspector_module_disabled")
                            .font(.caption2)
                            .foregroundStyle(LightamerColors.textTertiary)
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inspector.row.\(model.opName)")
        }
        .padding(.horizontal, 12)
        .background(model.isSelected ? LightamerColors.surfaceRaised : Color.clear)
        .contentShape(Rectangle())
    }
}
