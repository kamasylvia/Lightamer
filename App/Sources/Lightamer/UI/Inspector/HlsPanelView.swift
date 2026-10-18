import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// HlsPanelView (Plan M2-5-2 T5, KD-3) — the Selective Color panel over the
// hls 8-bin model: a Target Hue swatch row (the 8 candidate hues) + four
// sliders (Hue Shift / Lightness / Chroma / Hue Smoothness — the Alcedo
// EditorLookPanel faces verbatim: ±30°, ±100, ±100, 1…180°).
//
// ZERO panel-side mapping logic: slider writes ride the HlsModule
// applyTargetEdit pure function (the P1 mapping the golden tests pin) and
// the smoothness write is a direct hRangeTable[bin] field edit + the
// hRange mirror (the D4 mapping's "同步不改动" leg). Bin switching is
// local display state — the stored 8-bin table is the only truth.
// ─────────────────────────────────────────────────────────────────────────

internal struct HlsPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    /// The selected target bin (UI display state — the model table is the
    /// truth; the Alcedo default target = bin 0).
    @State private var selectedBin: Int = 0

    private let params: HlsModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: HlsModule.self) ?? HlsModule.Params()
    }

    var body: some View {
        Form {
            Section {
                targetHueRow
            } header: {
                Text("panel_hls_target")
            }
            Section {
                LightamerSlider(
                    label: String(localized: "panel_hls_hueshift"),
                    value: Double(display.hueShift),
                    range: Double(-HlsModule.maxHueShiftDegrees)
                        ... Double(HlsModule.maxHueShiftDegrees),
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    unit: "°",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { value in
                        write { params in
                            params = HlsModule.applyTargetEdit(
                                params: params, targetBin: selectedBin,
                                dh: Float(value), dl: display.lightness,
                                ds: display.chroma)
                        }
                    },
                    onDragEnd: { edit.endEditing(label: historyLabel) },
                    onReset: {
                        write { params in
                            params = HlsModule.applyTargetEdit(
                                params: params, targetBin: selectedBin,
                                dh: 0, dl: display.lightness, ds: display.chroma)
                        }
                    },
                    accessibilityID: "inspector.slider.hls.hueshift"
                )
                LightamerSlider(
                    label: String(localized: "panel_hls_lightness"),
                    value: Double(display.lightness),
                    range: Double(HlsModule.adjUIMin) ... Double(HlsModule.adjUIMax),
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { value in
                        write { params in
                            params = HlsModule.applyTargetEdit(
                                params: params, targetBin: selectedBin,
                                dh: display.hueShift, dl: Float(value),
                                ds: display.chroma)
                        }
                    },
                    onDragEnd: { edit.endEditing(label: historyLabel) },
                    onReset: {
                        write { params in
                            params = HlsModule.applyTargetEdit(
                                params: params, targetBin: selectedBin,
                                dh: display.hueShift, dl: 0, ds: display.chroma)
                        }
                    },
                    accessibilityID: "inspector.slider.hls.lightness"
                )
                LightamerSlider(
                    label: String(localized: "panel_hls_chroma"),
                    value: Double(display.chroma),
                    range: Double(HlsModule.adjUIMin) ... Double(HlsModule.adjUIMax),
                    defaultValue: 0,
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { value in
                        write { params in
                            params = HlsModule.applyTargetEdit(
                                params: params, targetBin: selectedBin,
                                dh: display.hueShift, dl: display.lightness,
                                ds: Float(value))
                        }
                    },
                    onDragEnd: { edit.endEditing(label: historyLabel) },
                    onReset: {
                        write { params in
                            params = HlsModule.applyTargetEdit(
                                params: params, targetBin: selectedBin,
                                dh: display.hueShift, dl: display.lightness, ds: 0)
                        }
                    },
                    accessibilityID: "inspector.slider.hls.chroma"
                )
                LightamerSlider(
                    label: String(localized: "panel_hls_smoothness"),
                    value: Double(display.smoothness),
                    range: 1...180,
                    defaultValue: Double(HlsModule.Params().hRangeTable.first ?? 45),
                    readoutFormat: "%.0f",
                    unit: "°",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { value in
                        write { params in
                            params.hRangeTable[selectedBin] = Float(value)
                            params.hRange = Float(value) // the projection mirror
                        }
                    },
                    onDragEnd: { edit.endEditing(label: historyLabel) },
                    onReset: {
                        let identity = Float(HlsModule.Params().hRangeTable.first ?? 45)
                        write { params in
                            params.hRangeTable[selectedBin] = identity
                            params.hRange = identity
                        }
                    },
                    accessibilityID: "inspector.slider.hls.smoothness"
                )
            } header: {
                Text("panel_hls_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.hls")
    }

    // MARK: - Target Hue row (the 8 candidate swatches)

    @ViewBuilder
    private var targetHueRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<HlsModule.binCount, id: \.self) { bin in
                Circle()
                    .fill(Self.swatchColor(hueDegrees: params.hueBins[bin]))
                    .overlay(
                        Circle().stroke(
                            selectedBin == bin
                                ? LightamerColors.accent
                                : LightamerColors.textSecondary.opacity(0.4),
                            lineWidth: selectedBin == bin ? 2 : 1))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                    .onTapGesture { selectedBin = bin }
                    .accessibilityLabel(Text(String(
                        localized: "panel_hls_target_bin",
                        defaultValue: "Target Hue \(bin * 45)°")))
                    .accessibilityIdentifier("inspector.swatch.hls.\(bin)")
                    .accessibilityAddTraits(selectedBin == bin ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 2)
    }

    /// The candidate swatch color (the hue wheel position → HSB).
    private static func swatchColor(hueDegrees: Float) -> Color {
        Color(hue: Double(hueDegrees / 360), saturation: 0.8, brightness: 0.9)
    }

    // MARK: - Display + write faces (the testable seam)

    private var historyLabel: String {
        String(localized: "history_hls")
    }

    /// The selected bin's slider faces (display units: the stored adj row's
    /// lightness/chroma ride ×1000 — the Alcedo kAdjUiToParamScale).
    private var display: (
        hueShift: Float, lightness: Float, chroma: Float, smoothness: Float
    ) {
        Self.displayValues(of: params, bin: selectedBin)
    }

    static func displayValues(
        of params: HlsModule.Params, bin: Int
    ) -> (hueShift: Float, lightness: Float, chroma: Float, smoothness: Float) {
        let index = min(max(bin, 0), HlsModule.binCount - 1)
        let adj = params.adjTable[index]
        return (
            hueShift: adj.h,
            lightness: adj.l * HlsModule.adjUIToParamScale,
            chroma: adj.s * HlsModule.adjUIToParamScale,
            smoothness: params.hRangeTable[index]
        )
    }

    /// The one write funnel: the transform either rides applyTargetEdit
    /// (the P1 mapping) or edits the smoothness fields directly — ZERO
    /// other mapping logic.
    private func write(
        _ transform: (inout HlsModule.Params) -> Void
    ) {
        var p = params
        transform(&p)
        if let record = PanelEditing.updated(instance, params: p, as: HlsModule.self) {
            edit.update(record)
        }
    }
}

// MARK: - Provider

internal struct HlsPanelProvider: IOPPanelProvider {
    var opName: String { HlsModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(HlsPanelView(instance: instance, edit: edit))
    }
}
