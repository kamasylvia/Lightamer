import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// LightamerSlider (Plan 03-02-T3, D-T6) — the ONE slider control every iop
// panel composes. Maps SwiftUI's editing lifecycle onto the D-H1 three-part
// API:
//
//   onEditingChanged(true)  → `onDragBegin()`   → beginContinuousEdit
//   Binding set (per tick)  → `onChange(value)` → setLiveParams (0 history)
//   onEditingChanged(false) → `onDragEnd()`     → commitContinuousEdit
//
// Extras per UI-SPEC: a numeric readout right of the label, double-click
// resets to `defaultValue` through `onReset` (the discrete one-commit
// semantics), token colors from `LightamerColors`, and a stable
// accessibilityIdentifier per L010 (identifiers never absorb children —
// labels live on the leaf Text views only).
// ─────────────────────────────────────────────────────────────────────────
internal struct LightamerSlider: View {

    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    /// Readout format (`%.2f` style); the unit is appended verbatim.
    var readoutFormat: String = "%.2f"
    var unit: String = ""

    /// Drag start (called once when the thumb grabs).
    let onDragBegin: () -> Void
    /// Per-tick value change while dragging OR programmatic.
    let onChange: (Double) -> Void
    /// Drag end (called once when the thumb releases).
    let onDragEnd: () -> Void
    /// Double-click reset target (nil = no reset affordance).
    var onReset: (() -> Void)?

    /// Stable AX identifier, e.g. `"inspector.slider.exposure.exposure"`.
    let accessibilityID: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
                .lineLimit(1)
                .accessibilityIdentifier("\(accessibilityID).label")

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in onChange(newValue) }
                ),
                in: range
            ) { dragging in
                if dragging {
                    onDragBegin()
                } else {
                    onDragEnd()
                }
            }
            .tint(LightamerColors.accent)
            .accessibilityIdentifier("\(accessibilityID).slider")

            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(LightamerColors.textPrimary)
                .frame(minWidth: 64, alignment: .trailing)
                .accessibilityIdentifier("\(accessibilityID).readout")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onReset?()
        }
        .accessibilityElement(children: .contain)
    }

    private var readout: String {
        String(format: readoutFormat + unit, value)
    }
}
