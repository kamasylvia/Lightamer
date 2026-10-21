import Foundation

// LensProjection — the projection-type catalog + CPU math (Plan LENS-03 T1,
// D-LENS-8).
//
// Portions Copyright 2026 Yurun Zi (Alcedo Studio contributors).
// Source: Alcedo Studio `src/edit/runtime/lens/metal/shader/lens_calib.metal`
// (the projection pair functions — FisheyeERect / ERectFishEye /
// EquisolidERect / ERectEquisolid / StereographicERect / ERectStereographic /
// OrthographicERect / ERectOrthographic and the two dispatch switches),
// GPL-3.0-only. Ported to Swift for Lightamer.
// Modified by Lightamer (2026-10-21): the Alcedo projection-type enum is
// re-spelled as a Swift case-per-slot enum (8 slots, additive-compile —
// the 3 inactive slots are compile-exhaustive with unreachable arms); the
// functions live in Double precision (the CPU golden face; the kernel
// counterpart mirrors in float). See NOTICE ("Alcedo Studio") for the
// provenance ledger. GPL-3.0 as part of Lightamer.
//
// DOMAIN CONVENTION (the L3 kernel header pins the fold): the projection
// functions act on CENTER-RELATIVE coordinates in the lens-normalized
// domain — our kernel's u domain ((p − c)/halfW) is the same ANGLE-DOMAIN
// shape (a global scale of Alcedo's normScale domain does not change the
// projection-function form). The evaluation order is the Alcedo live
// order (lens_calib.metal `lens_warp_rgba32f`): normalized output coords
// → ×1/resolved_scale → projection fold (target → equirectangular →
// source) → distortion → TCA — the L2 "×1/scale on the post-map offset"
// face moves to this slot (scale=1 is the exact identity either way; the
// L2 scale golden was re-pinned to the Alcedo order in this batch).

/// The projection type (8 slots, D-LENS-8: FOUR ACTIVE + three reserved +
/// the rectilinear identity base; String-Codable for the params face).
public enum LensProjection: String, Codable, Sendable, CaseIterable {
    /// The identity base (straight lines stay straight; the default).
    case rectilinear
    /// Equal-angle fisheye (the classic circular fisheye).
    case fisheye
    /// RESERVED (inactive slot — panoramic Cylindrical; no calibration
    /// data path, unreachable until a future batch activates it).
    case panoramic
    /// RESERVED (inactive slot — equirectangular; same).
    case equirectangular
    /// Equal-area fisheye.
    case orthographic
    /// Stereographic fisheye.
    case stereographic
    /// Equisolid fisheye.
    case equisolid
    /// RESERVED (inactive slot — Thoby fisheye; same).
    case thoby

    /// The four v1-ACTIVE types (the panel picker's data source; the
    /// reserved slots are compile-present but not user-selectable).
    public static let active: [LensProjection] = [
        .fisheye, .equisolid, .stereographic, .orthographic,
    ]

    /// The serde spelling for the reserved slots (compile-exhaustive —
    /// every switch over this enum must grow the arm, which then stays
    /// unreachable until the slot activates).
    public var isReserved: Bool {
        switch self {
        case .panoramic, .equirectangular, .thoby: return true
        case .rectilinear, .fisheye, .orthographic, .stereographic, .equisolid:
            return false
        }
    }

    /// The slot ordinal (the uniforms' int encoding; Alcedo enum order).
    public var slotIndex: Int {
        switch self {
        case .rectilinear: return 1
        case .fisheye: return 2
        case .panoramic: return 3
        case .equirectangular: return 4
        case .orthographic: return 5
        case .stereographic: return 6
        case .equisolid: return 7
        case .thoby: return 8
        }
    }

    /// Lenient decode: unknown spellings fall back to rectilinear (the
    /// identity base — never a crash on a foreign/persistent value).
    public static func decodeLenient(_ raw: String?) -> LensProjection {
        guard let raw, let v = LensProjection(rawValue: raw) else { return .rectilinear }
        return v
    }

    // MARK: - The CPU math (Alcedo port — see the file header)

    /// projection → equirectangular (the pair-first half).
    public static func toEquirect(_ x: Double, _ y: Double, from p: LensProjection) -> (Double, Double) {
        switch p {
        case .rectilinear:
            // Alcedo ApplyProjectionRectERect.
            return (atan2(x, 1.0), atan2(y, (1.0 + x * x).squareRoot()))
        case .fisheye:
            // Alcedo ApplyProjectionFishEyeERect.
            let r = (x * x + y * y).squareRoot()
            guard r > eps else { return (0, 0) }
            let s = Darwin.sin(r) / r
            let vx = Darwin.cos(r)
            let vy = s * x
            return (Darwin.atan2(vy, vx), Darwin.atan(s * y / (vx * vx + vy * vy).squareRoot()))
        case .orthographic:
            // Alcedo ApplyProjectionOrthographicERect.
            let r = (x * x + y * y).squareRoot()
            let theta = r < 1.0 ? Darwin.asin(r) : Double.pi / 2
            let phi = Darwin.atan2(y, x)
            let s = theta <= eps ? 1.0 : Darwin.sin(theta) / theta
            let vx = Darwin.cos(theta)
            let vy = s * theta * Darwin.cos(phi)
            return (Darwin.atan2(vy, vx), Darwin.atan(s * theta * Darwin.sin(phi) / (vx * vx + vy * vy).squareRoot()))
        case .stereographic:
            // Alcedo ApplyProjectionStereographicERect.
            let rh = (x * x + y * y).squareRoot()
            let c = 2.0 * Darwin.atan(rh / 2.0)
            let sinc = Darwin.sin(c)
            let cosc = Darwin.cos(c)
            guard rh > eps else { return (0, .infinity) }
            let outY = Darwin.asin(y * sinc / rh)
            let outX = (abs(cosc) >= eps || abs(x) >= eps)
                ? Darwin.atan2(x * sinc, cosc * rh) : .infinity
            return (outX, outY)
        case .equisolid:
            // Alcedo ApplyProjectionEquisolidERect.
            let r = (x * x + y * y).squareRoot()
            let theta = r < 2.0 ? 2.0 * Darwin.asin(r / 2.0) : Double.pi / 2
            let phi = Darwin.atan2(y, x)
            let s = theta <= eps ? 1.0 : Darwin.sin(theta) / theta
            let vx = Darwin.cos(theta)
            let vy = s * theta * Darwin.cos(phi)
            return (Darwin.atan2(vy, vx), Darwin.atan(s * theta * Darwin.sin(phi) / (vx * vx + vy * vy).squareRoot()))
        case .panoramic, .equirectangular, .thoby:
            // Reserved slots: unreachable (D-LENS-8) — the identity keeps
            // the exhaustiveness compile-checked without inventing math.
            return (x, y)
        }
    }

    /// equirectangular → projection (the pair-second half).
    public static func fromEquirect(_ x: Double, _ y: Double, to p: LensProjection) -> (Double, Double) {
        switch p {
        case .rectilinear:
            // Alcedo ApplyProjectionERectRect.
            return (Darwin.tan(x), 1.0 / (Darwin.tan(y) * Darwin.cos(x)))
        case .fisheye:
            // Alcedo ApplyProjectionERectFishEye (EQUIDISTANT — the disk
            // radius IS the polar angle from the optical axis). The
            // theta-reflection skeleton (same shape as ERectRect /
            // ERectOrthographic below); M-1 fix: this arm previously
            // carried the STEREOGRAPHIC ksp formula (a verbatim duplicate
            // of the .stereographic arm — the acceptance's mis-
            // transcription finding; the round-trip golden pins the
            // corrected form).
            var xx = x
            var theta = -y + Double.pi / 2
            if theta < 0 { theta = -theta; xx += Double.pi }
            if theta > Double.pi { theta = 2.0 * Double.pi - theta; xx += Double.pi }
            let s = Darwin.sin(theta)
            let vx = s * Darwin.sin(xx)
            let vy = Darwin.cos(theta)
            let r = (vx * vx + vy * vy).squareRoot()
            let theta2 = Darwin.atan2(r, s * Darwin.cos(xx))
            let invR = r <= eps ? 0.0 : 1.0 / r
            return (theta2 * vx * invR, theta2 * vy * invR)
        case .orthographic:
            // Alcedo ApplyProjectionERectOrthographic.
            var xx = x
            var theta = -y + Double.pi / 2
            if theta < 0 { theta = -theta; xx += Double.pi }
            if theta > Double.pi { theta = 2.0 * Double.pi - theta; xx += Double.pi }
            let s = Darwin.sin(theta)
            let vx = s * Darwin.sin(xx)
            let vy = Darwin.cos(theta)
            let theta2 = Darwin.atan2((vx * vx + vy * vy).squareRoot(), s * Darwin.cos(xx))
            let phi2 = Darwin.atan2(vy, vx)
            let rho = Darwin.sin(theta2)
            return (rho * Darwin.cos(phi2), rho * Darwin.sin(phi2))
        case .stereographic:
            // Alcedo ApplyProjectionERectStereographic.
            let cosPhi = Darwin.cos(y)
            let ksp = 2.0 / (1.0 + cosPhi * Darwin.cos(x))
            return (ksp * cosPhi * Darwin.sin(x), ksp * Darwin.sin(y))
        case .equisolid:
            // Alcedo ApplyProjectionERectEquisolid.
            if abs(Darwin.cos(y) * Darwin.cos(x) + 1.0) <= eps {
                return (.infinity, .infinity)
            }
            let k1 = (2.0 / (1.0 + Darwin.cos(y) * Darwin.cos(x))).squareRoot()
            return (k1 * Darwin.cos(y) * Darwin.sin(x), k1 * Darwin.sin(y))
        case .panoramic, .equirectangular, .thoby:
            return (x, y)
        }
    }

    /// The backward-sampling fold: the OUTPUT-domain point → equirect →
    /// the SOURCE-domain sample point (Alcedo ApplyProjectionTransform
    /// pair; identity when the two projections coincide).
    public static func fold(
        _ x: Double, _ y: Double, source: LensProjection, target: LensProjection
    ) -> (Double, Double) {
        guard source != target else { return (x, y) }
        let (ex, ey) = toEquirect(x, y, from: target)
        return fromEquirect(ex, ey, to: source)
    }

    static let eps = 1e-8
}
