import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// MaskToolbarView (Plan 06-05 T3.1/T3.2) — the mask drawing toolbar, a
// floating strip at the viewport's BOTTOM EDGE (視口下缘浮层 — it must NOT
// grow the Inspector column, and the viewport keeps ≥50%).
//
// Content: the five tools (brush / eraser / gradient / ellipse / path —
// radio semantics via `LayerEditingState.setTool`) + the brush parameter
// popover (size / hardness / flow / opacity sliders; the cmd-drag size
// gesture is a Manual-Only item — L011) + the gradient profile toggle
// (linear / sigmoidal).
//
// Disabled WITHOUT a selected layer (「选中层才可绘」— the disabled state is
// the plan's requirement); armed tools route the viewport to the
// MaskOverlayHost through the `LayerEditingState` machine.
//
// Panel四件套: L010 identifiers (`mask.toolbar`, `mask.tool.<name>`, …) +
// zh/en String Catalog + the floating-strip constraint + D-H1 (parameter
// sliders commit NOTHING — they are editing-mode state, not history; the
// stroke they produce commits once at stroke end).
// ─────────────────────────────────────────────────────────────────────────

internal struct MaskToolbarView: View {

    @Environment(LayerEditingState.self) private var editingState

    @State private var showsBrushPopover = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MaskTool.allCases, id: \.rawValue) { tool in
                Button {
                    // Radio semantics: tapping the armed tool disarms it.
                    editingState.setTool(editingState.activeTool == tool ? nil : tool)
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.callout)
                        .frame(width: 24, height: 22)
                        .background(
                            editingState.activeTool == tool
                                ? LightamerColors.accent.opacity(0.4)
                                : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.borderless)
                .disabled(!hasSelection)
                .accessibilityLabel(Text(String(localized: String.LocalizationValue(tool.labelKey))))
                .accessibilityValue(
                    editingState.activeTool == tool ? Text("toggle_on") : Text("toggle_off"))
                .accessibilityIdentifier(tool.identifier)
            }

            Divider()
                .frame(height: 16)

            // Brush parameter popover (the parameter RING's panel leg; the
            // cmd-drag-on-viewport size gesture is Manual-Only registered).
            Button {
                showsBrushPopover.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .disabled(!hasSelection)
            .accessibilityLabel(Text("mask_brush_params"))
            .accessibilityIdentifier("mask.toolbar.brushparams")
            .popover(isPresented: $showsBrushPopover) {
                brushPopover
                    .padding(12)
                    .frame(width: 230)
            }

            // Gradient profile toggle (linear ↔ sigmoidal, discrete).
            Picker("mask_gradient_profile", selection: Binding(
                get: { editingState.gradientState },
                set: { editingState.gradientState = $0 }
            )) {
                Text("mask_gradient_linear").tag(GradientState.linear)
                Text("mask_gradient_sigmoidal").tag(GradientState.sigmoidal)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 120)
            .disabled(editingState.activeTool != .gradient)
            .accessibilityIdentifier("mask.toolbar.gradientprofile")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .accessibilityIdentifier("mask.toolbar")
    }

    private var hasSelection: Bool { editingState.selectedLayerID != nil }

    /// The brush parameter sliders — EDITING-MODE state (no history; the
    /// values ride the NEXT stroke's BrushStroke record).
    private var brushPopover: some View {
        // @Environment(Observable) has no $ projection without @Bindable —
        // bind through explicit get/set pairs (the values are plain Floats).
        func bind(_ get: @escaping (LayerEditingState) -> Float, _ set: @escaping (LayerEditingState, Float) -> Void) -> Binding<Float> {
            Binding(
                get: { get(editingState) },
                set: { set(editingState, $0) })
        }
        return VStack(alignment: .leading, spacing: 8) {
            slider("mask_brush_size", value: bind({ $0.brushRadius }, { $0.brushRadius = $1 }), in: 0.005...0.3)
            slider("mask_brush_hardness", value: bind({ $0.brushHardness }, { $0.brushHardness = $1 }), in: 0...1)
            slider("mask_brush_flow", value: bind({ $0.brushFlow }, { $0.brushFlow = $1 }), in: 0.05...1)
            slider("mask_brush_opacity", value: bind({ $0.brushOpacity }, { $0.brushOpacity = $1 }), in: 0.05...1)
            Text("mask_brush_cmddrag_hint")
                .font(.caption2)
                .foregroundStyle(LightamerColors.textSecondary)
        }
    }

    private func slider(
        _ labelKey: String, value: Binding<Float>, in range: ClosedRange<Float>
    ) -> some View {
        HStack {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Float($0) }), in: Double(range.lowerBound)...Double(range.upperBound))
                .controlSize(.small)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
