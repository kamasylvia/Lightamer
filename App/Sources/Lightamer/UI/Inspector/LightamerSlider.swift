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

    /// The readout scrub session (M7-6-01 UQ-L1) — nil between scrubs.
    @State private var scrubSession: LightamerSliderScrubSession?
    /// The row width feeding the travel→value map (measured in place).
    @State private var rowWidth: CGFloat = 0
    /// The Shift face for the 1/10-speed ticks (this SDK's DragGesture.Value
    /// carries no modifiers member — the macOS-15 `onModifierKeysChanged`
    /// observation is the SwiftUI-native channel).
    @State private var shiftActive = false

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
                // M7-6-01 (UQ-L1): the readout scrub — horizontal drag on
                // the number sweeps the value. The D-H1 three-callback face
                // is REUSED, never bypassed: begin → onDragBegin, per-tick →
                // onChange (setLiveParams, 0 history), end → onDragEnd
                // (commitContinuousEdit) — one scrub = one continuous
                // commit, exactly like a thumb drag. minimumDistance 3 is
                // the tap-vs-drag discrimination against the row's
                // double-click reset above.
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { gesture in
                            if scrubSession == nil {
                                // The first callback is the scrub begin
                                // (already ≥3pt in — the dead zone the
                                // minimumDistance itself owns, so the delta
                                // still starts at zero).
                                scrubSession = LightamerSliderScrubSession(
                                    startValue: value,
                                    startX: gesture.location.x,
                                    range: range,
                                    trackWidth: rowWidth)
                                onDragBegin()
                            }
                            let newValue = scrubSession?.tick(
                                atX: gesture.location.x,
                                shiftActive: shiftActive)
                            if let newValue {
                                onChange(newValue)
                            }
                        }
                        .onEnded { _ in
                            scrubSession?.end()
                            scrubSession = nil
                            onDragEnd()
                        }
                )
                .accessibilityHint(String(
                    localized: "slider_scrub_hint",
                    defaultValue: "横向拖动数字扫值——按住 Shift 以 1/10 速度细调。"))
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
        }
        .onModifierKeysChanged { _, newValue in
            shiftActive = newValue.contains(.shift)
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

// ─────────────────────────────────────────────────────────────────────────
// LightamerSliderScrubSession (M7-6-01 UQ-L1) — the readout scrub's PURE
// travel→value value type (the M3-1-02 YiyinSheetDragSession seam shape:
// the interaction discipline is asserted against the session, not the UI).
// Zero side effects — no history, no pipe dispatch, no persistence; the
// D-H1 three-callback face owns those (the view maps begin/tick/end onto
// onDragBegin/onChange/onDragEnd verbatim).
// ─────────────────────────────────────────────────────────────────────────
internal struct LightamerSliderScrubSession {

    let startValue: Double
    let startX: CGFloat
    let range: ClosedRange<Double>
    /// The travel scale (the row width — the component-width approximation;
    /// the SwiftUI Slider's internal track geometry is framework-owned).
    let trackWidth: CGFloat

    private(set) var tickCount = 0
    private(set) var lastValue: Double

    init(
        startValue: Double, startX: CGFloat,
        range: ClosedRange<Double>, trackWidth: CGFloat
    ) {
        self.startValue = startValue
        self.startX = startX
        self.range = range
        self.trackWidth = trackWidth
        self.lastValue = startValue
    }

    /// One live tick (the absolute drag x in the began coordinates): the
    /// pure map — full-row travel spans the range, Shift runs 1/10 speed
    /// (re-scaling the whole travel from the start point, the lightcraft
    /// semantic), the range clamps both ends.
    mutating func tick(atX x: CGFloat, shiftActive: Bool) -> Double {
        tickCount += 1
        let span = range.upperBound - range.lowerBound
        let speed: Double = shiftActive ? 0.1 : 1.0
        let scale = trackWidth > 0 ? Double(trackWidth) : 1
        let raw = startValue
            + Double(x - startX) / scale * span * speed
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        lastValue = clamped
        return clamped
    }

    /// Drag end: the settled value (the pairing convergence point — the
    /// caller clears the session and fires onDragEnd; one scrub = one
    /// begin/end pair).
    func end() -> Double {
        lastValue
    }
}
