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
/// **Matching mechanics (host-verified 2026-09-19, `.work/plans/02-04/`):**
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
    /// Known families map to the system linear spaces; the fallback tries
    /// the profile's EXACT primaries first (Plan 13-2 T6 exact-TRC: a
    /// matrix-shaper ICC yields its calibrated-linear workalike via
    /// `CGColorSpaceCreateCalibratedRGB` at gamma 1.0 — primaries and white
    /// point precise, black point included when the profile carries it).
    /// LUT-class profiles (no XYZ shaper tags) keep the sRGB workalike, and
    /// the TRC encode itself stays gamma's sRGB curve in both cases (the
    /// display leg's encode is shared; for the overwhelmingly common
    /// sRGB-TRC display class the curve is exact).
    ///
    /// 13-2 T6 status: the fallback branch routes to the sRGB workalike —
    /// the exact-primaries variant exists (`CGColorSpace
    /// .linearVariantIfMatrixShaper`, test-pinned) but is DELIBERATELY not
    /// consumed by the render leg: a shared space instance interacting
    /// with the CI leg proved order-sensitive (the CullingPipeline
    /// collapse forensics, 13-2-DECISIONS D-13-2-7). The property keeps
    /// the baseline mapping; the render integration is deferred.
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

// MARK: - The exact-TRC helper (Plan 13-2 T6)

/// The rebuilt linear variants, keyed by the ICC byte hash. The colorout
/// fallback leg consults `linearVariantIfMatrixShaper` on EVERY render —
/// without this cache each call mints a FRESH `CGColorSpace` instance for
/// identical bytes, and the CIContext render behind the ColorSync leg keys
/// its internal state by space INSTANCE (the 13-2 regression forensics:
/// the per-render instance churn flipped the byte-exact render suite into
/// an intermittent all-black-plane flake; the baseline — the system
/// extendedLinearSRGB SINGLETON — was stable). One instance per profile,
/// forever: the CG type is immutable and thread-safe.
private enum LinearVariantCache {
    nonisolated(unsafe) static var storage: [UInt64: CGColorSpace] = [:]
    nonisolated(unsafe) static let nilSentinel = UInt64(0) // an absent entry ≠ a failed parse
    nonisolated(unsafe) static var failed: Set<UInt64> = []
    static let lock = NSLock()
}

extension CGColorSpace {

    /// The profile's LINEAR variant for a matrix-shaper ICC: parse the
    /// `rXYZ`/`gXYZ`/`bXYZ` (primaries), `wtpt` (media white) and `bkpt`
    /// (optional black) XYZ tags and rebuild the gamut at gamma 1.0 via
    /// `CGColorSpaceCreateCalibratedRGB` — the primaries/white are EXACT
    /// (the fallback leg's workalike approximation shrinks to the TRC
    /// encode alone; see `DisplayProfile.linearCGColorSpace`). nil for any
    /// profile without the shaper tags (LUT-class), for non-RGB models
    /// (CMYK), and for malformed tables — the caller keeps the sRGB
    /// workalike in every nil case. Results are CACHED per ICC-byte hash
    /// (including the nil verdicts — one parse per profile, one space
    /// instance per profile).
    ///
    /// ICC layout: 128-byte header, tag count at offset 128 (u32 BE), then
    /// 12-byte tag entries (signature, offset, size — all u32 BE); the
    /// XYZType payload is a 4-byte type signature + 4 reserved bytes +
    /// three s15Fixed16 numbers (u32 BE, value/65536).
    var linearVariantIfMatrixShaper: CGColorSpace? {
        guard let icc = copyICCData() as Data? else { return nil }
        let key = StableHash.hash(icc)
        LinearVariantCache.lock.lock()
        if let cached = LinearVariantCache.storage[key] {
            LinearVariantCache.lock.unlock()
            return cached
        }
        if LinearVariantCache.failed.contains(key) {
            LinearVariantCache.lock.unlock()
            return nil
        }
        LinearVariantCache.lock.unlock()

        let parsed = Self.parseLinearVariant(icc: icc)

        LinearVariantCache.lock.lock()
        if let parsed {
            LinearVariantCache.storage[key] = parsed
        } else {
            LinearVariantCache.failed.insert(key)
        }
        LinearVariantCache.lock.unlock()
        return parsed
    }

    private static func parseLinearVariant(icc: Data) -> CGColorSpace? {
        let space = CGColorSpace(iccProfileData: icc as CFData)
        guard let space, space.model == .rgb else { return nil }
        let bytes = [UInt8](icc)
        guard bytes.count > 132 else { return nil }
        let tagCount = bytes.beUInt32(at: 128)
        guard tagCount > 0, tagCount < 512 else { return nil }

        func xyzTag(_ signature: String) -> [Double]? {
            for i in 0..<Int(tagCount) {
                let entry = 132 + i * 12
                guard entry + 12 <= bytes.count else { return nil }
                let sig = String(bytes: bytes[entry..<(entry + 4)], encoding: .ascii)
                guard sig == signature else { continue }
                let offset = Int(bytes.beUInt32(at: entry + 4))
                // The XYZType element: 4-byte type signature ('XYZ ') +
                // 4-byte reserved + three s15Fixed16 numbers (20 bytes).
                guard offset + 20 <= bytes.count else { return nil }
                return (0..<3).map { Double(bytes.beInt32(at: offset + 8 + $0 * 4)) / 65536.0 }
            }
            return nil
        }
        guard let rXYZ = xyzTag("rXYZ"), let gXYZ = xyzTag("gXYZ"),
              let bXYZ = xyzTag("bXYZ"), let wXYZ = xyzTag("wtpt")
        else { return nil }
        guard rXYZ.count == 3, gXYZ.count == 3, bXYZ.count == 3, wXYZ.count == 3,
              wXYZ[1] != 0
        else { return nil }

        // Primaries as [rx, ry, gx, gy, bx, by]; white/black as [x, y, Y=1]
        // (CalibratedRGB expects the tristimulus with Y last).
        let primaries: [CGFloat] = [rXYZ[0], rXYZ[1], gXYZ[0], gXYZ[1], bXYZ[0], bXYZ[1]]
        let white: [CGFloat] = [
            CGFloat(wXYZ[0] / wXYZ[1]), CGFloat(wXYZ[2] / wXYZ[1]), 1.0,
        ]
        let black: [CGFloat]? = xyzTag("bkpt").map { b in
            [CGFloat(b[0] / max(b[1], 1e-6)), CGFloat(b[2] / max(b[1], 1e-6)), 1.0]
        }
        return CGColorSpace(
            calibratedRGBWhitePoint: white, blackPoint: black,
            gamma: [CGFloat](repeating: 1.0, count: 3), matrix: primaries)
    }
}

private extension Array where Element == UInt8 {
    func beUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
    func beInt32(at offset: Int) -> Int32 {
        Int32(bitPattern: beUInt32(at: offset))
    }
}
