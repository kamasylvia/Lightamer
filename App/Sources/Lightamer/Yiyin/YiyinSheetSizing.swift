import CoreGraphics
import Foundation
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// YiyinSheetSizing (Plan M3-1-02, KD-1/KD-3) — the pure clamp/convert math for
// the yiyin sheet's draggable edges. This is a SEMANTIC port of upstream PR
// #126's preview-splitter discipline (yiyin fork, MIT — zero code transplant,
// SwiftUI rewrite): absolute px bounds ∩ available-domain ratio bounds, ratio
// quantized to 3 decimals only at drag end.
//
// Upstream constants are ported VERBATIM (the sheet is the same "control
// panel width/height" semantic): px 120-720 / 160-560, ratio 0.15-0.75 /
// 0.35-0.92. The height cap 560 EQUALS the shipped default height — the M7
// checker note records this as INTENTIONAL (the sheet is a control panel:
// heights beyond 560 buy no content; keeping the upstream constant preserves
// the "never dragged = zero look change" anchor). Width adjusts both ways.
//
// Upstream's available-domain subtraction set (SPLITTER_SIZE + 15×2 gap +
// IMG_LIST_MIN 180 — image-list layout items) is NOT ported: our sheet has no
// image list, so the clamp is the plain two-domain intersection (DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

enum YiyinSheetSizing {

    // KD-1: px bounds (upstream PREVIEW_MIN/MAX_* verbatim).
    static let minWidth: CGFloat = 120
    static let maxWidth: CGFloat = 720
    static let minHeight: CGFloat = 160
    static let maxHeight: CGFloat = 560

    // KD-1: ratio bounds (upstream MIN/MAX_*_RATIO verbatim); the available
    // domain basis = the sheet's attaching container (workspace host face).
    static let minWidthRatio: CGFloat = 0.15
    static let maxWidthRatio: CGFloat = 0.75
    static let minHeightRatio: CGFloat = 0.35
    static let maxHeightRatio: CGFloat = 0.92

    // First-use constants = the shipped `.frame(width: 420, height: 560)`.
    // KD-1: absent ratio keys must reproduce the CURRENT look byte-for-byte;
    // the upstream persisted defaults (0.5 / 0.85) are deliberately NOT
    // first-use values (ratio × container ≠ the shipped size).
    static let defaultWidth: CGFloat = 420
    static let defaultHeight: CGFloat = 560

    /// Edge-handle hit area (≥ the upstream SPLITTER_SIZE 6 equivalent).
    static let handleThickness: CGFloat = 8

    // MARK: - Clamps (double clamp: px bounds ∩ ratio domain, then clamp)

    /// Clamp a live width into [px bounds] ∩ [container × ratio bounds].
    /// Degenerate domain (container too small for the intersection to be
    /// non-empty): returns the upper bound — the same value the upstream
    /// `min(max(px, lo), hi)` composition yields when lo > hi.
    static func clampWidth(
        _ width: CGFloat, containerWidth: CGFloat
    ) -> CGFloat {
        let lo = max(minWidth, containerWidth * minWidthRatio)
        let hi = min(maxWidth, containerWidth * maxWidthRatio)
        return min(max(width, lo), hi)
    }

    /// Height twin of `clampWidth` (height ratio domain 0.35-0.92).
    static func clampHeight(
        _ height: CGFloat, containerHeight: CGFloat
    ) -> CGFloat {
        let lo = max(minHeight, containerHeight * minHeightRatio)
        let hi = min(maxHeight, containerHeight * maxHeightRatio)
        return min(max(height, lo), hi)
    }

    // MARK: - Ratio conversion (the persisted face)

    /// The width ratio for a settled px, clamped into the ratio domain.
    static func widthRatio(
        fromPx px: CGFloat, containerWidth: CGFloat
    ) -> Double {
        guard containerWidth > 0 else { return minWidthRatio }
        let ratio = px / containerWidth
        return Double(min(max(ratio, minWidthRatio), maxWidthRatio))
    }

    /// Height twin of `widthRatio(fromPx:containerWidth:)`.
    static func heightRatio(
        fromPx px: CGFloat, containerHeight: CGFloat
    ) -> Double {
        guard containerHeight > 0 else { return minHeightRatio }
        let ratio = px / containerHeight
        return Double(min(max(ratio, minHeightRatio), maxHeightRatio))
    }

    /// Upstream `persistPreviewRatio` quantization: `round(ratio*1000)/1000`.
    /// Idempotent by construction (three significant decimals).
    static func quantize3(_ ratio: Double) -> Double {
        (ratio * 1000).rounded() / 1000
    }

    // MARK: - Settled resolution (ratio key → px)

    /// The settled width for a stored ratio. Absent ratio (first use) → the
    /// shipped 420 (KD-1's zero-look-change anchor); unknown container (no
    /// geometry yet) → the shipped constant too; a stored ratio resolves as
    /// container × ratio re-clamped into the intersection domain.
    static func resolvedWidth(
        ratio: Double?, containerWidth: CGFloat
    ) -> CGFloat {
        guard containerWidth > 0, let ratio else { return defaultWidth }
        return clampWidth(containerWidth * CGFloat(ratio), containerWidth: containerWidth)
    }

    /// Height twin of `resolvedWidth(ratio:containerWidth:)`.
    static func resolvedHeight(
        ratio: Double?, containerHeight: CGFloat
    ) -> CGFloat {
        guard containerHeight > 0, let ratio else { return defaultHeight }
        return clampHeight(containerHeight * CGFloat(ratio), containerHeight: containerHeight)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// YiyinSheetDragSession — the per-axis drag window (upstream startResize →
// move → pointerup). Live ticks are PURE state (clamped px, zero persistence
// — the isDragging-early-return semantic); only `end` produces the 3-decimal
// quantized ratio for the caller to persist. Keeping the window as a value
// type lets YiyinSheetSizingTests machine-check the AC-3 discipline (defaults
// writes happen only after `end`) without instantiating the sheet.
// ─────────────────────────────────────────────────────────────────────────────

struct YiyinSheetDragSession {

    enum Axis {
        case width
        case height
    }

    let axis: Axis
    private let startPx: CGFloat
    private let containerSize: CGSize
    private(set) var livePx: CGFloat

    init(axis: Axis, startPx: CGFloat, containerSize: CGSize) {
        self.axis = axis
        self.startPx = startPx
        self.containerSize = containerSize
        self.livePx = startPx
    }

    /// One live tick (cumulative gesture translation): pure clamp, zero
    /// side effects — no history, no pipe dispatch, no defaults write.
    mutating func tick(translation: CGFloat) -> CGFloat {
        switch axis {
        case .width:
            livePx = YiyinSheetSizing.clampWidth(
                startPx + translation, containerWidth: containerSize.width)
        case .height:
            livePx = YiyinSheetSizing.clampHeight(
                startPx + translation, containerHeight: containerSize.height)
        }
        return livePx
    }

    /// Drag end: the settled px plus the quantized ratio to persist. The
    /// CALLER owns the write (the model's `…End` reaches YiyinSheetMetrics
    /// here and only here).
    func end() -> (px: CGFloat, ratio: Double) {
        switch axis {
        case .width:
            let ratio = YiyinSheetSizing.widthRatio(
                fromPx: livePx, containerWidth: containerSize.width)
            return (livePx, YiyinSheetSizing.quantize3(ratio))
        case .height:
            let ratio = YiyinSheetSizing.heightRatio(
                fromPx: livePx, containerHeight: containerSize.height)
            return (livePx, YiyinSheetSizing.quantize3(ratio))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// YiyinSheetResizeModel (KD-2) — the sheet's sizing state landing surface.
// The view binds to `resolvedWidth/Height` + `readout` and forwards gesture
// ticks; all persistence rides the injected `YiyinSheetMetrics` (KD-4: the
// view body never touches UserDefaults). Container change (the ResizeObserver
// equivalent) invalidates live px so the settled size re-derives from the
// stored ratios — the upstream "window rescales the pane by ratio" semantic.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class YiyinSheetResizeModel {

    private let metrics: YiyinSheetMetrics

    /// The attaching-container visible domain (workspace host face).
    private(set) var containerSize: CGSize = .zero

    /// Live/settled px from the most recent drag on each axis (nil = derive
    /// from the stored ratio). Stays after `end` so the readout shows the
    /// exact terminal value; cleared on container change.
    private(set) var liveWidth: CGFloat?
    private(set) var liveHeight: CGFloat?

    private(set) var isDragging = false

    private var widthSession: YiyinSheetDragSession?
    private var heightSession: YiyinSheetDragSession?

    init(metrics: YiyinSheetMetrics = YiyinSheetMetrics()) {
        self.metrics = metrics
    }

    // MARK: Domain face (the onGeometryChange / ResizeObserver equivalent)

    func containerChanged(to newSize: CGSize) {
        guard newSize != containerSize else { return }
        containerSize = newSize
        // Re-derive from the persisted ratios (upstream: container rescale
        // re-lays-out px = ratio × available domain).
        liveWidth = nil
        liveHeight = nil
    }

    // MARK: Resolved faces

    var resolvedWidth: CGFloat {
        if let liveWidth { return liveWidth }
        return YiyinSheetSizing.resolvedWidth(
            ratio: metrics.widthRatio(), containerWidth: containerSize.width)
    }

    var resolvedHeight: CGFloat {
        if let liveHeight { return liveHeight }
        return YiyinSheetSizing.resolvedHeight(
            ratio: metrics.heightRatio(), containerHeight: containerSize.height)
    }

    /// The live size readout — upstream `${Math.round(w)} × ${Math.round(h)}`
    /// verbatim (no localization key, AC 4).
    var readout: String {
        "\(Int(resolvedWidth.rounded())) × \(Int(resolvedHeight.rounded()))"
    }

    // MARK: The drag window (AC 3: zero writes until end)

    @discardableResult
    func widthTick(translation: CGFloat) -> CGFloat {
        if widthSession == nil {
            widthSession = YiyinSheetDragSession(
                axis: .width, startPx: resolvedWidth, containerSize: containerSize)
            isDragging = true
        }
        let px = widthSession!.tick(translation: translation)
        liveWidth = px
        return px
    }

    @discardableResult
    func heightTick(translation: CGFloat) -> CGFloat {
        if heightSession == nil {
            heightSession = YiyinSheetDragSession(
                axis: .height, startPx: resolvedHeight, containerSize: containerSize)
            isDragging = true
        }
        let px = heightSession!.tick(translation: translation)
        liveHeight = px
        return px
    }

    func widthEnd() {
        guard let session = widthSession else { return }
        let (px, ratio) = session.end()
        metrics.storeWidthRatio(ratio)
        liveWidth = px
        widthSession = nil
        if heightSession == nil { isDragging = false }
    }

    func heightEnd() {
        guard let session = heightSession else { return }
        let (px, ratio) = session.end()
        metrics.storeHeightRatio(ratio)
        liveHeight = px
        heightSession = nil
        if widthSession == nil { isDragging = false }
    }
}
