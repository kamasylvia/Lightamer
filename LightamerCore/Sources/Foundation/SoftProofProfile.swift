import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Plan 13-2 T2 — the soft-proof state (COLOR-02), the D-COL3 reservation's
// display-leg counterpart.
//
// **Per-run override semantics (the load-bearing contract, same shape as the
// `ColorOutModule.displayProfileOverride` / `exportTargetOverride` sockets —
// per-run DATA, L013: injection is not configuration):**
//
// A `SoftProofProfile` NEVER enters `Params`, NEVER enters the history stack,
// and NEVER enters the export chain. It is coordinator-level runtime state:
// the pipe carries the proof stage as a coordinator-minted box whose params
// stay EMPTY (the profile rides the box's `softProofOverride` property, and
// only its STABLE ID is folded into the cache-key hash — the environment-
// identity discipline `DisplayProfile.stableID` established). Consequences:
// - switching/toggling proof flips the soft-proof box's `paramsHash` → only
//   the keys at or below the proof stage flip; upstream planes survive;
// - no history item is ever recorded (the proof toggle is not an edit);
// - `ExportChainBuilder` never sees the stage (the export chain is built
//   from records, which never contain it) — exported pixels are bit-identical
//   with proof on or off;
// - the sidecar never round-trips a proof state (soft proofing is a VIEW
//   mode — "applied as the last transform before display, never baked into
//   the edit", REQUIREMENTS COLOR-02).
//
// **Engine (T1 probe, `13-2-probes.md` §4):** ColorSync/CG precise leg —
// `CGColorConversionInfoCreateFromList` + `CGColorConversionInfoConvertData`,
// float32 premultiplied-last little-endian. The public BPC switch
// (`kCGColorConversionBlackPointCompensation`, macOS 10.12+) is passed
// through (probe §3.2 proved the key is consumed). RGB printer profiles
// only: the CMYK ICC path is unreachable through every CG data-conversion
// channel (probe §2) — non-RGB printer profiles are REJECTED at
// construction, downgraded with an explicit note (probe §4.4).
// ─────────────────────────────────────────────────────────────────────────────

/// The soft-proof configuration: WHICH printer to simulate and HOW.
/// Value type; identity via `stableID` (the cache-invalidation atom).
public struct SoftProofProfile: @unchecked Sendable, Equatable {

    /// The rendering intent applied on the working→printer leg
    /// (`CGColorRenderingIntent` mirror). v1 accepts ONLY
    /// `.relativeColorimetric` (the soft-proof standard): the intent-
    /// selective constructor (`CGColorConversionInfoCreateFromList`) is a C
    /// varargs function the Swift bridge cannot call — T1 probe §1 + the
    /// execution-language caveat in 13-2-DECISIONS. The full enum is kept
    /// for the persisted/UI surface's forward compatibility; other values
    /// are a typed rejection (a silently wrong simulation would be worse).
    public enum Intent: String, Codable, Sendable, CaseIterable {
        case relativeColorimetric
        case perceptual
        case saturation
        case absoluteColorimetric
    }

    /// The printer ICC profile bytes (the identity truth — `stableID` hashes
    /// these; the sidecar NEVER sees them).
    public let printerICC: Data

    /// The parsed colorspace (immutable thread-safe CF type — `@unchecked
    /// Sendable` carries the CF immutability contract, same as
    /// `DisplayProfile.colorSyncFallback`).
    public let printerSpace: CGColorSpace

    /// Human-readable printer name (UI picker label).
    public let label: String

    /// Working→printer rendering intent (default: relative colorimetric,
    /// the soft-proof standard; dt `softproof` default).
    public var intent: Intent

    /// Black-point compensation (the T1 probe's public switch, passed
    /// through to ColorSync). Default ON (the soft-proof standard — the
    /// printer's paper black is lifted to display black so shadows are not
    /// crushed in the simulation).
    public var blackPointCompensation: Bool

    /// OOG gamut check (Plan 13-2 T3): ON = pixels the printer cannot
    /// reproduce are shown BLACK (dt softproof gamut-check semantics).
    public var gamutCheck: Bool

    /// Validate + construct. Two typed rejections:
    /// - non-relative intents (the Swift-reachable constructor carries the
    ///   default rendering intent + the BPC option only — v1 supports the
    ///   soft-proof standard: relative colorimetric + BPC);
    /// - non-RGB printer ICCs: the T1 probe proved CMYK printer ICCs are
    ///   unreachable through the CG data-conversion channels
    ///   (13-2-probes.md §2) — photography printing (the soft-proof
    ///   audience) uses RGB driver profiles; a CMYK profile is a typed
    ///   rejection, not a silent wrong simulation.
    public init(
        printerICC: Data,
        label: String,
        intent: Intent = .relativeColorimetric,
        blackPointCompensation: Bool = true,
        gamutCheck: Bool = false
    ) throws {
        guard intent == .relativeColorimetric else {
            throw AppError.invalidParameter(
                "SoftProofProfile: intent '\(intent.rawValue)' is not supported in v1 "
                    + "(relative colorimetric only — see 13-2-DECISIONS)")
        }
        guard let space = CGColorSpace(iccProfileData: printerICC as CFData) else {
            throw AppError.invalidParameter(
                "SoftProofProfile: ICC data did not parse as a colorspace (\(label))"
            )
        }
        guard space.numberOfComponents == 3 else {
            throw AppError.invalidParameter(
                "SoftProofProfile: printer profile '\(label)' is not RGB "
                    + "(\(space.numberOfComponents) components — "
                    + "CMYK printer profiles are unsupported; see 13-2-probes.md §2)"
            )
        }
        self.printerICC = printerICC
        self.printerSpace = space
        self.label = label
        self.intent = intent
        self.blackPointCompensation = blackPointCompensation
        self.gamutCheck = gamutCheck
    }

    /// Construct from a colorspace (re-exports its ICC data when present).
    public init(printerSpace: CGColorSpace, label: String, intent: Intent = .relativeColorimetric,
                blackPointCompensation: Bool = true, gamutCheck: Bool = false) throws {
        guard let icc = printerSpace.copyICCData() as Data? else {
            throw AppError.invalidParameter(
                "SoftProofProfile: colorspace '\(label)' carries no ICC data")
        }
        try self.init(
            printerICC: icc, label: label, intent: intent,
            blackPointCompensation: blackPointCompensation, gamutCheck: gamutCheck)
    }

    /// Stable cache-key identity: the proof stage folds this into its
    /// `paramsHash`, so ANY profile/intent/BPC/gamut change flips exactly
    /// the keys at or below the stage (SC#2 terminal-variant discipline).
    /// ICC bytes hash (L013) ⊕ config — two profiles with the same ICC and
    /// config share an identity.
    public var stableID: UInt64 {
        var hash = StableHash.hash(printerICC)
        var intentID = StableHash.hash("lightamer.softproof.intent:\(intent.rawValue)")
        hash = withUnsafeBytes(of: &intentID) { StableHash.combine(hash, $0) }
        var bpcID = StableHash.hash("lightamer.softproof.bpc:\(blackPointCompensation)")
        hash = withUnsafeBytes(of: &bpcID) { StableHash.combine(hash, $0) }
        var gcID = StableHash.hash("lightamer.softproof.gamut:\(gamutCheck)")
        hash = withUnsafeBytes(of: &gcID) { StableHash.combine(hash, $0) }
        return hash
    }

    public static func == (lhs: SoftProofProfile, rhs: SoftProofProfile) -> Bool {
        lhs.stableID == rhs.stableID
    }
}

/// The installed ColorSync profile catalog (D-13-CONTEXT-4④: the printer
/// profile source = the system's installed ICC list; recency memory is the
/// UI layer's business, not a Core concern).
public enum PrinterProfileCatalog {

    public struct Entry: Hashable, Sendable {
        public let name: String
        public let url: URL

        /// Construct the soft-proof profile (throws for non-RGB profiles —
        /// the UI surfaces the typed message; see `SoftProofProfile.init`).
        public func makeProfile(
            intent: SoftProofProfile.Intent = .relativeColorimetric,
            blackPointCompensation: Bool = true,
            gamutCheck: Bool = false
        ) throws -> SoftProofProfile {
            let data = try Data(contentsOf: url)
            return try SoftProofProfile(
                printerICC: data, label: name, intent: intent,
                blackPointCompensation: blackPointCompensation, gamutCheck: gamutCheck)
        }
    }

    /// The system + user ColorSync profile directories, scan order stable
    /// (system first). Only `.icc`/`.icm` files; parse failures are skipped
    /// silently (broken profile files must not break the picker).
    public static func installedProfiles() -> [Entry] {
        let searchPaths: [String] = [
            "/System/Library/ColorSync/Profiles",
            "/Library/ColorSync/Profiles",
            NSHomeDirectory() + "/Library/ColorSync/Profiles",
        ]
        let fm = FileManager.default
        var seen = Set<String>()
        var entries: [Entry] = []
        for directory in searchPaths {
            guard let items = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for item in items.sorted() where item.lowercased().hasSuffix(".icc") || item.lowercased().hasSuffix(".icm") {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(item)
                guard seen.insert(url.path).inserted else { continue }
                entries.append(Entry(name: url.deletingPathExtension().lastPathComponent, url: url))
            }
        }
        return entries
    }
}
