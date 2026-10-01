import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// LuminanceColorRangePanelView (Plan M2-7-2 T5, KD-5; M2MASK-05,
// D-M2-7-CONTEXT-6 A) — the Nitro-semantics quick panels over the EXISTING
// ParametricMask payload. ZERO new MaskType: the Luminance Range writes the
// luma channel's 4-point trapezoid, the Color Range writes the Cz/hz
// channel curves (slots 9/10) — all through the unified
// `EditorState.commitMaskEdit` seam (the `history_mask_range_*` key family;
// the write-point-⑤ bump inside).
//
// Slider contract (D-H1): the drag rewrites the payload LIVE through
// `applyLiveMaskEdit` (zero history, zero bump — the mask plane reassembles
// per tick), and the drag end commits ONCE through `commitMaskEdit`
// (exactly one item, one bump) reading the current live value back.
//
// The eyedropper's linear Rec2020 → JzCzhz conversion is the IOP
// `JzCzhz.fromRGB` SINGLE SOURCE (the L023 five-leg chain; Core cannot
// import IOP, so the Core mapping helpers consume the ALREADY-converted
// value — no second Jz implementation anywhere).
//
// UI boundary (OQ-6): the single-channel quick face ONLY — dt's 14-channel
// full blendif surface stays unexposed.
// ─────────────────────────────────────────────────────────────────────────────

internal struct LuminanceColorRangePanelView: View {

    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    /// The eyedropper sample (kernel-domain JzCzhz + the linear RGB it came
    /// from); nil = not sampled yet.
    @State private var sample: (rgb: SIMD3<Float>, jch: SIMD3<Double>)?
    @State private var isSampling = false

    /// The selected layer (nil = the panel shows its empty hint).
    private var layerID: UUID? { editingState.selectedLayerID }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mask_range_title")
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .accessibilityIdentifier("mask.range.title")
            if let layerID {
                luminanceSection(layerID)
                Divider()
                colorSection(layerID)
            } else {
                Text("mask_range_no_selection")
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
        .accessibilityIdentifier("mask.range.panel")
    }

    // MARK: the payload read face

    private func parametricPoints(_ layerID: UUID, channel: Int) -> [Float]? {
        editorState.adjustmentLayer(id: layerID)?.mask?
            .parametric?.channels.first { $0.channel == channel }?.curve.points
    }

    // MARK: Luminance Range (the luma 4-point trapezoid)

    private func luminanceSection(_ layerID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("mask_range_luminance")
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
            bandBar(layerID)
            bandSlider(
                layerID, labelKey: "mask_range_dark", range: 0.0...1.0,
                read: { target in trapezoid(in: target).lowerBound },
                live: { target, dark in setTrapezoid(target, dark: dark) },
                identifier: "dark")
            bandSlider(
                layerID, labelKey: "mask_range_light", range: 0.0...1.0,
                read: { target in trapezoid(in: target).upperBound },
                live: { target, light in setTrapezoid(target, light: light) },
                identifier: "light")
            bandSlider(
                layerID, labelKey: "mask_range_feather", range: 0.0...0.5,
                read: { feather(in: $0) },
                live: { target, value in setFeather(target, value) },
                identifier: "feather")
        }
        .accessibilityIdentifier("mask.range.luminance")
    }

    /// The trapezoid bounds of the layer's luma curve (the defaults = the
    /// untuned quarter band).
    private func trapezoid(in layerID: UUID) -> ClosedRange<Double> {
        guard let points = parametricPoints(layerID, channel: 0), points.count == 4
        else { return 0.25...0.75 }
        return Double(points[1])...Double(points[2])
    }

    private func feather(in layerID: UUID) -> Double {
        guard let points = parametricPoints(layerID, channel: 0), points.count == 4
        else { return 0.1 }
        return Double(max(0, points[1] - points[0]))
    }

    /// The band bar (the selection window between the two handles).
    private func bandBar(_ layerID: UUID) -> some View {
        let band = trapezoid(in: layerID)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.5))
                Capsule()
                    .fill(LightamerColors.accent.opacity(0.6))
                    .frame(width: max(0, proxy.size.width * (band.upperBound - band.lowerBound)))
                    .offset(x: proxy.size.width * band.lowerBound)
            }
        }
        .frame(height: 6)
    }

    /// The LIVE leg: rewrite the luma trapezoid from the dragged bound.
    private func setTrapezoid(_ layerID: UUID, dark: Double? = nil, light: Double? = nil) {
        let band = trapezoid(in: layerID)
        let featherValue = feather(in: layerID)
        let d = Float(dark ?? band.lowerBound)
        let l = Float(light ?? band.upperBound)
        let points = ParametricMask.luminanceTrapezoid(
            dark: d, light: l, feather: Float(featherValue))
        editorState.applyLiveMaskEdit(layerID: layerID) { mask in
            var parametric = mask.parametric ?? ParametricMask(domain: .luma, channels: [])
            if parametric.domain == .jzczhz { parametric.domain = .luma }
            upsert(&parametric, .init(
                channel: 0, curve: ParametricMask.ChannelCurve(points: points)))
            mask.parametric = parametric
        }
    }

    private func setFeather(_ layerID: UUID, _ value: Double) {
        let band = trapezoid(in: layerID)
        let points = ParametricMask.luminanceTrapezoid(
            dark: Float(band.lowerBound), light: Float(band.upperBound), feather: Float(value))
        editorState.applyLiveMaskEdit(layerID: layerID) { mask in
            var parametric = mask.parametric ?? ParametricMask(domain: .luma, channels: [])
            if parametric.domain == .jzczhz { parametric.domain = .luma }
            upsert(&parametric, .init(
                channel: 0, curve: ParametricMask.ChannelCurve(points: points)))
            mask.parametric = parametric
        }
    }

    /// The COMMIT leg (one item, one bump — reads the CURRENT live value).
    private func commitLuminance(_ layerID: UUID) {
        let band = trapezoid(in: layerID)
        let featherValue = feather(in: layerID)
        let points = ParametricMask.luminanceTrapezoid(
            dark: Float(band.lowerBound), light: Float(band.upperBound),
            feather: Float(featherValue))
        editorState.commitMaskEdit(
            layerID: layerID,
            label: String(localized: "history_mask_range_luminance")
        ) { mask in
            var parametric = mask.parametric ?? ParametricMask(domain: .luma, channels: [])
            if parametric.domain == .jzczhz { parametric.domain = .luma }
            upsert(&parametric, .init(
                channel: 0, curve: ParametricMask.ChannelCurve(points: points)))
            mask.parametric = parametric
        }
    }

    // MARK: Color Range (the JzCzhz eyedropper + Cz/hz bands)

    private func colorSection(_ layerID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("mask_range_color")
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
            HStack(spacing: 8) {
                Button {
                    Task { await sampleDisplayCenter(layerID) }
                } label: {
                    if isSampling {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "eyedropper")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isSampling)
                .accessibilityLabel(Text("mask_range_sample"))
                .accessibilityIdentifier("mask.range.sample")
                if let sample {
                    // The swatch (the linear sample gamma-encoded for
                    // display only) + the domain readout.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(
                            red: gamma(sample.rgb.x), green: gamma(sample.rgb.y),
                            blue: gamma(sample.rgb.z)))
                        .frame(width: 18, height: 14)
                    Text(String(
                        format: "Cz %.3f  hz %.2f",
                        sample.jch.y, sample.jch.z))
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Text("mask_range_sample_hint")
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
                Spacer()
            }
            if sample != nil {
                bandSlider(
                    layerID, labelKey: "mask_range_cz_range", range: 0.0...0.5,
                    read: { Double(czWidth(in: $0)) },
                    live: { target, value in setCzBand(target, width: value) },
                    identifier: "czrange")
                bandSlider(
                    layerID, labelKey: "mask_range_color_feather", range: 0.0...0.5,
                    read: { Double(czFeatherWidth(in: $0)) },
                    live: { target, value in setCzBand(target, feather: value) },
                    identifier: "czfeather")
            }
        }
        .accessibilityIdentifier("mask.range.color")
    }

    private func czPoints(in layerID: UUID) -> [Float]? {
        parametricPoints(layerID, channel: ParametricMask.czChannel)
    }

    /// The Cz half-width in UI-domain points (p2 − p1).
    private func czWidth(in layerID: UUID) -> Float {
        guard let points = czPoints(in: layerID), points.count == 4 else { return 0.1 }
        return max(0, points[2] - points[1])
    }

    private func czFeatherWidth(in layerID: UUID) -> Float {
        guard let points = czPoints(in: layerID), points.count == 4 else { return 0.05 }
        return max(0, points[1] - points[0])
    }

    private func czBand(in layerID: UUID) -> ClosedRange<Double> {
        guard let points = czPoints(in: layerID), points.count == 4
        else { return 0...0 }
        return Double(points[1])...Double(points[2])
    }

    /// The LIVE leg for the Cz band geometry (the sampled center is stored
    /// in `sample`; the curves rewrite around it).
    private func setCzBand(_ layerID: UUID, width: Double? = nil, feather: Double? = nil) {
        guard let jch = sample?.jch else { return }
        let entries = ParametricMask.colorRangeEntries(
            cz: Float(jch.y), hz: Float(jch.z),
            range: Float(width ?? Double(czWidth(in: layerID))),
            feather: Float(feather ?? Double(czFeatherWidth(in: layerID))))
        editorState.applyLiveMaskEdit(layerID: layerID) { mask in
            var parametric = mask.parametric ?? ParametricMask(domain: .luma, channels: [])
            parametric.domain = .jzczhz
            for entry in entries { upsert(&parametric, entry) }
            mask.parametric = parametric
        }
    }

    private func commitColor(_ layerID: UUID) {
        guard let jch = sample?.jch else { return }
        let entries = ParametricMask.colorRangeEntries(
            cz: Float(jch.y), hz: Float(jch.z),
            range: czWidth(in: layerID), feather: czFeatherWidth(in: layerID))
        editorState.commitMaskEdit(
            layerID: layerID,
            label: String(localized: "history_mask_range_color")
        ) { mask in
            var parametric = mask.parametric ?? ParametricMask(domain: .luma, channels: [])
            parametric.domain = .jzczhz
            for entry in entries { upsert(&parametric, entry) }
            mask.parametric = parametric
        }
    }

    /// The eyedropper: the display plane's center pixel through the EXISTING
    /// linear-pipe sampling seam (`pickColor` — the aspect-fit center maps
    /// to the plane center for any viewport), then the SINGLE-SOURCE
    /// Rec2020 → JzCzhz chain. A fresh sample lands the band immediately
    /// (the Nitro flow: pick → the range appears), uncommitted until a
    /// slider drag ends (the live-leg semantics).
    private func sampleDisplayCenter(_ layerID: UUID) async {
        isSampling = true
        defer { isSampling = false }
        let color = await pipeCoordinator.pickColor(
            at: CGPoint(x: 100, y: 100), viewportSize: CGSize(width: 200, height: 200))
        guard let color else {
            editorState.presentToast(
                String(localized: "toast_mask_range_sample_failed",
                       defaultValue: "Nothing to sample — load an image first"))
            return
        }
        let rgb = SIMD3<Double>(Double(color.x), Double(color.y), Double(color.z))
        sample = (SIMD3<Float>(color.x, color.y, color.z), JzCzhz.fromRGB(rgb))
        setCzBand(layerID, width: 0.1, feather: 0.05)
    }

    // MARK: shared bits

    /// Upsert one channel entry (the payload's canonical array form).
    private func upsert(
        _ parametric: inout ParametricMask, _ entry: ParametricMask.ChannelEntry
    ) {
        if let index = parametric.channels.firstIndex(where: { $0.channel == entry.channel }) {
            parametric.channels[index] = entry
        } else {
            parametric.channels.append(entry)
        }
    }

    private func gamma(_ v: Float) -> Double {
        let clamped = max(0, min(1, Double(v)))
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    /// The D-H1 slider: the binding reads the LIVE payload (the thumb
    /// follows every tick's rewrite); the drag end commits ONCE.
    private func bandSlider(
        _ layerID: UUID, labelKey: String, range: ClosedRange<Double>,
        read: @escaping (UUID) -> Double,
        live: @escaping (UUID, Double) -> Void,
        identifier: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(width: 64, alignment: .leading)
            Slider(
                value: Binding(
                    get: { min(max(read(layerID), range.lowerBound), range.upperBound) },
                    set: { live(layerID, $0) }),
                in: range
            ) { dragging in
                if !dragging { commitFor(identifier, layerID) }
            }
            .controlSize(.mini)
            .accessibilityIdentifier("mask.range.\(identifier)")
        }
    }

    /// The drag-end commit dispatcher (each slider commits its OWN label —
    /// one item per interaction; an if-chain keeps the `default:` grep
    /// surface clean — 纪律 7's string-switch caveat).
    private func commitFor(_ identifier: String, _ layerID: UUID) {
        if identifier == "dark" || identifier == "light" || identifier == "feather" {
            commitLuminance(layerID)
        } else if identifier == "czrange" || identifier == "czfeather" {
            commitColor(layerID)
        }
    }
}
