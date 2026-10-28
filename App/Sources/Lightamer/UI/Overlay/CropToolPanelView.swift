import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// CropToolPanelView (Plan M9-3-T3) — the crop tool's rotate/straighten
// strip (the LR-position toolbar): the straighten slider (±45°, D-H1
// three-phase), the 90° step pair, the auto-straighten button, and
// Constrain Crop. The overlay's orbit handle and this slider funnel
// through the SAME linked-change path (the #742 single-funnel lesson) —
// the panel owns NO pipe state, everything exits through the callbacks.
//
// disable-not-unmount (M7-5 discipline): the strip stays mounted while
// the crop tool is active; buttons disable while a drag is in flight.
// ─────────────────────────────────────────────────────────────────────────

struct CropToolPanelView: View {

    /// The current ashift rotation (degrees; the slider's value).
    var rotationDegrees: Double
    /// True while an interactive edit is in flight (live window open) —
    /// the buttons sit disabled.
    var isEditing: Bool

    // The straighten slider's D-H1 trio.
    var onRotateBegin: () -> Void = {}
    var onRotateLive: (Double) -> Void = { _ in }
    var onRotateCommit: (Double) -> Void = { _ in }

    /// The 90° steps (true = clockwise).
    var onNinety: (Bool) -> Void = { _ in }
    /// The auto-straighten button (the segment-detection solve; nil
    /// availability disables the button).
    var autoStraightenAvailable: Bool
    var onAutoStraighten: () -> Void = {}
    /// Constrain Crop (the blank-edge shrink).
    var onConstrain: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            // Straighten slider (the LR position).
            Slider(
                value: Binding(
                    get: { rotationDegrees },
                    set: { newValue in onRotateLive(newValue) }
                ),
                in: -45...45
            ) { editing in
                if editing {
                    onRotateBegin()
                } else {
                    onRotateCommit(rotationDegrees)
                }
            }
            .frame(maxWidth: 260)
            .accessibilityIdentifier("crop.straighten.slider")
            .accessibilityLabel(Text("crop_straighten_label"))

            Text(verbatim: String(format: "%.1f°", rotationDegrees))
                .monospacedDigit()
                .font(.callout)
                .frame(width: 52)
                .accessibilityIdentifier("crop.straighten.value")

            Button {
                onNinety(false)
            } label: {
                Image(systemName: "rotate.left")
            }
            .disabled(isEditing)
            .accessibilityIdentifier("crop.rotate.ccw")
            .accessibilityLabel(Text("crop_rotate_ccw_label"))
            .help(Text("crop_rotate_ccw_label"))

            Button {
                onNinety(true)
            } label: {
                Image(systemName: "rotate.right")
            }
            .disabled(isEditing)
            .accessibilityIdentifier("crop.rotate.cw")
            .accessibilityLabel(Text("crop_rotate_cw_label"))
            .help(Text("crop_rotate_cw_label"))

            Button(String(localized: "crop_auto_straighten")) {
                onAutoStraighten()
            }
            .disabled(isEditing || !autoStraightenAvailable)
            .accessibilityIdentifier("crop.auto.straighten")
            .help(Text("crop_auto_straighten"))

            Button(String(localized: "crop_constrain")) {
                onConstrain()
            }
            .disabled(isEditing)
            .accessibilityIdentifier("crop.constrain")
            .help(Text("crop_constrain"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("crop.tool.panel")
    }
}
