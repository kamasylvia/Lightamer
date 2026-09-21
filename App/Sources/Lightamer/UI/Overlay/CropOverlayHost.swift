import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// CropOverlayHost (Plan 04-02-T4) — the EditorAreaView ↔ CropOverlayView
// bridge: record ↔ fractions conversion + the D-H1 trio wiring.
//
// RECORD FLOW (T0 decision (a) — live-disabled + scrim):
// - live tick: snapshot with `enabled=false` + current drag fractions →
//   `setLiveParams` (full-frame render; overlay shows scrim + rect).
// - commit: snapshot with `enabled=true` + final fractions →
//   `commitContinuousEdit` (exactly ONE history item; window renders once).
//
// The host reads the crop record from `EditorState.instances`
// (record = source of truth, PanelEditing-style decode); unknown decode
// ⇒ full-frame overlay (never a crash). Aspect presets mirror dt's
// `aspect_list` subset (plan T4 action 4): free/original/1:1/4:3/3:2/
// 16:9/16:10 — the full dt list (letter/A4/golden/anamorphic…) stays a
// custom-ratio stretch goal (the Params bits already round-trip it).
// ─────────────────────────────────────────────────────────────────────────

/// dt `aspect_list` subset for the overlay/panel ratio lock
/// (`crop.c:1267-1290` — d:n with d ≥ n; sign flips orientation).
enum CropAspectPreset: String, CaseIterable, Sendable {
    case free
    case original
    case square1x1 = "1:1"
    case ratio4x3 = "4:3"
    case ratio3x2 = "3:2"
    case ratio16x9 = "16:9"
    case ratio16x10 = "16:10"

    /// (d, n) with d ≥ n; nil = freehand/original-resolved-at-drag.
    var dn: (d: Int, n: Int)? {
        switch self {
        case .free: return nil
        case .original: return nil
        case .square1x1: return (1, 1)
        case .ratio4x3: return (4, 3)
        case .ratio3x2: return (3, 2)
        case .ratio16x9: return (16, 9)
        case .ratio16x10: return (16, 10)
        }
    }

    /// Resolve to a w/h aspect for the drag lock. `original` reads the
    /// upstream plane (bufInROI analog — the display texture size here);
    /// free ⇒ nil.
    func aspect(upstreamSize: CGSize) -> Double? {
        switch self {
        case .free: return nil
        case .original:
            guard upstreamSize.width >= 1, upstreamSize.height >= 1 else { return nil }
            return Double(upstreamSize.width / upstreamSize.height)
        default:
            guard let dn else { return nil }
            return Double(dn.d) / Double(dn.n)
        }
    }
}

/// The bridge view (mounted by EditorAreaView's `.overlay`).
/// `cropRecord` nil ⇒ no overlay (crop instance absent — e.g. pristine
/// seed before T5, or a sidecar without crop). `displaySize` = the
/// display texture's pixel size (upstream geometry for `original`).
struct CropOverlayHost: View {

    var viewportSize: CGSize
    var displaySize: CGSize
    var cropRecord: ModuleInstance?
    var isDragging: Bool

    var onBegin: () -> Void = {}
    var onLive: (ModuleInstance) -> Void = { _ in }
    var onCommit: (ModuleInstance, String) -> Void = { _, _ in }

    /// The overlay's aspect preset (owned by the panel in T5; the host
    /// exposes it as state so the overlay drag locks without panel help).
    @State var preset: CropAspectPreset = .free

    var body: some View {
        if let record = cropRecord,
           let params = try? record.params(of: CropModule.self),
           displaySize.width >= 1, displaySize.height >= 1
        {
            let fitted = ViewportFit.fittedRect(
                viewportSize: viewportSize,
                textureSize: displaySize)
            if fitted.width >= 1, fitted.height >= 1 {
                CropOverlayView(
                    fittedRect: fitted,
                    cropRect: CropOverlayRect(
                        left: Double(params.left), top: Double(params.top),
                        right: Double(params.right), bottom: Double(params.bottom),
                        lockedAspect: preset.aspect(upstreamSize: displaySize)),
                    isDimmed: isDragging,
                    showsPhiGrid: false,
                    onBegin: onBegin,
                    onLive: { rect in
                        if let snapshot = liveSnapshot(from: record, rect: rect, enabled: false) {
                            onLive(snapshot)
                        }
                    },
                    onCommit: { rect in
                        if let snapshot = liveSnapshot(from: record, rect: rect, enabled: true) {
                            onCommit(snapshot, String(localized: "history_crop"))
                        }
                    }
                )
            }
        }
    }

    /// Fractions → typed params → record snapshot (same-UUID re-encode;
    /// the D-H4 hash flips through `setParams`).
    func liveSnapshot(
        from record: ModuleInstance, rect: CropOverlayRect, enabled: Bool
    ) -> ModuleInstance? {
        guard var params = try? record.params(of: CropModule.self) else { return nil }
        params.left = Float(rect.left)
        params.top = Float(rect.top)
        params.right = Float(rect.right)
        params.bottom = Float(rect.bottom)
        var snapshot = record
        snapshot.enabled = enabled
        do {
            try snapshot.setParams(params, as: CropModule.self)
            return snapshot
        } catch {
            return nil
        }
    }
}
