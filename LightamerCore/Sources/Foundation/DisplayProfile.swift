import AppKit
import CoreGraphics
import Foundation

/// The resolved display profile (D-COL2: follow the window's screen) — the
/// colorout fast-path selector (Plan 02-04-03).
///
/// **Matching table (reversible decision, additive to extend):** the Metal
/// constant-matrix fast path covers ONLY the two known families —
/// Display P3 and sRGB (research §3.2: virtually every Mac built-in panel
/// reports Display P3; external sRGB panels report sRGB). Anything else →
/// `.colorSyncFallback` (the CIContext/ColorSync precise path; also the
/// D-COL1 criterion-2 baseline).
///
/// **Matching mechanics (host-verified 2026-09-19, `.work/02-04/`):**
/// `NSColorSpace` has no `name` property on the macOS 27 SDK — plan wording
/// "`colorSpace.name` → matching table" is realized as, in order:
/// 1. `CGColorSpace.name` (the `kCGColorSpace…` registered names — set for
///    the system spaces, `nil` for custom display ICC profiles),
/// 2. `NSColorSpace` equality against the system `.displayP3` / `.sRGB`,
/// 3. ICC profile data equality (`NSColorSpace.iccProfileData`) — catches
///    displays whose active profile IS the system P3/sRGB profile file,
/// 4. anything else → `.colorSyncFallback(CGColorSpace)`.
///
/// Host note: the dev machine's panel (BenQ PD2705U, external) carries a
/// CUSTOM 524-byte ICC profile — `resolve` returns `.colorSyncFallback`
/// there; the fast-path unit tests drive the module with EXPLICIT profile
/// params instead of the screen (deterministic, host-independent), and the
/// screen-resolution test skip-with-logs per the plan's host-variance guard.
///
/// Phase 13 (COLOR-03) adds manual profile selection + printer/soft-proof
/// profiles on top of this enum (D-COL3).
public enum DisplayProfile: @unchecked Sendable, Equatable {

    /// Display P3 (the wide-gamut Apple panel family) — fast path,
    /// Rec2020→P3 linear constant matrix.
    case displayP3

    /// sRGB — fast path, Rec2020→sRGB linear constant matrix.
    case sRGB

    /// Any other profile — the CIContext/ColorSync precise leg. The payload
    /// is the display's actual colorspace (drives the color-managed present
    /// and Phase 13's exact-TRC work). `@unchecked Sendable`: CGColorSpace
    /// is an immutable, thread-safe CF type; the enum is a value snapshot.
    case colorSyncFallback(CGColorSpace)

    // MARK: Resolution

    /// Resolve a screen/window colorspace against the matching table.
    /// `nil` input (no screen reported — defensive) falls back to `.sRGB`:
    /// the safe common-denominator encoding, logged once by the caller.
    public static func resolve(_ colorSpace: NSColorSpace?) -> DisplayProfile {
        guard let colorSpace else { return .sRGB }
        let cgName = colorSpace.cgColorSpace?.name as String?
        // 1+2. Registered system names / direct equality.
        if colorSpace == .displayP3
            || cgName == "kCGColorSpaceDisplayP3"
            || cgName == "kCGColorSpaceExtendedDisplayP3" {
            return .displayP3
        }
        if colorSpace == .sRGB
            || cgName == "kCGColorSpaceSRGB"
            || cgName == "kCGColorSpaceExtendedSRGB" {
            return .sRGB
        }
        // 3. ICC-data identity (display profiles that literally ARE the
        // system profile files — name is nil but bytes match).
        if let icc = colorSpace.iccProfileData {
            if let p3ICC = NSColorSpace.displayP3.iccProfileData, icc == p3ICC {
                return .displayP3
            }
            if let srgbICC = NSColorSpace.sRGB.iccProfileData, icc == srgbICC {
                return .sRGB
            }
        }
        // 4. Unknown family → the precise ColorSync leg.
        if let cg = colorSpace.cgColorSpace {
            return .colorSyncFallback(cg)
        }
        return .sRGB // degenerate: no underlying CG space at all
    }

    /// The currently-active screen's profile (D-COL2: `NSScreen.main` until
    /// the coordinator injects the window's screen).
    public static func current() -> DisplayProfile {
        resolve(NSScreen.main?.colorSpace)
    }

    // MARK: Identity + derived spaces

    /// Case-level equality (not synthesized — the CGColorSpace payload is
    /// not Equatable; identity `===` is the right notion for fallback
    /// profiles).
    public static func == (lhs: DisplayProfile, rhs: DisplayProfile) -> Bool {
        switch (lhs, rhs) {
        case (.displayP3, .displayP3): return true
        case (.sRGB, .sRGB): return true
        case let (.colorSyncFallback(a), .colorSyncFallback(b)): return a === b
        default: return false
        }
    }

    /// Stable cache-key identity: the terminal-segment invalidation atom
    /// (a display change ⇒ colorout's `paramsHash` changes ⇒ every cache
    /// key at positions ≥ colorout flips, upstream planes survive — SC#2's
    /// terminal variant). FNV-1a 64 (StableHash — the only legal generator;
    /// Swift `Hasher` is process-seeded). Fallback profiles hash their ICC
    /// bytes so two monitors with the same profile share an identity.
    public var stableID: UInt64 {
        switch self {
        case .displayP3:
            return StableHash.hash("lightamer.display.displayP3")
        case .sRGB:
            return StableHash.hash("lightamer.display.sRGB")
        case .colorSyncFallback(let space):
            if let icc = space.copyICCData() as Data? {
                return StableHash.hash(icc)
            }
            let name = space.name as String? ?? "unnamed-\(space)"
            return StableHash.hash("lightamer.display.colorSync:\(name)")
        }
    }

    /// Human-readable label for logs (`Logger` category `color`).
    public var label: String {
        switch self {
        case .displayP3: return "Display P3 (fast path)"
        case .sRGB: return "sRGB (fast path)"
        case .colorSyncFallback(let space):
            let name = space.name as String? ?? "custom ICC"
            return "ColorSync fallback (\(name))"
        }
    }

    /// The LINEAR variant of the resolved target gamut — the colorout
    /// ColorSync leg's output encoding (colorout ALWAYS emits linear
    /// target-gamut float32; the TRC encode is gamma's job — D-COL4).
    /// Known families map to the system linear spaces; the fallback maps
    /// to linear sRGB — a DOCUMENTED workalike: exact primaries of the
    /// unknown profile land with Phase 13's full ICC support, and its TRC
    /// is approximated by gamma's sRGB curve (exact for the overwhelmingly
    /// common sRGB-TRC display class).
    public var linearCGColorSpace: CGColorSpace {
        switch self {
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        case .sRGB, .colorSyncFallback:
            return CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        }
    }

    /// The space the ENCODED output bytes live in (fast path: the matching
    /// gamut; fallback: the sRGB workalike gamut — see `linearCGColorSpace`).
    /// The editor viewport attaches this to the `CAMetalLayer` so the
    /// compositor interprets the gamma-encoded bytes without re-matching.
    public var displayCGColorSpace: CGColorSpace {
        switch self {
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        case .sRGB, .colorSyncFallback:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }
    }
}
