import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportMetadataPolicy — the M2EXP-02 metadata strategy model (Plan M2-9-01
// T3, OQ-6). The FULL Alcedo ExportMetadataPolicy face (mode + six bools):
//
//   mode ∈ {standard, none}
//   exif / xmp / iptc             default true  (the STANDARD carriers)
//   location / serials / history  default false (the FIXED STRIPS — README's
//                                 "location, device serials, edit history
//                                 stay excluded")
//
// This plan delivers the MODEL only; the consumption legs (EXIF dictionary
// filtering, the XMP editing-summary packet's default-not-mounted face,
// the NONE short-circuit) are M2-9-03. The editing-summary XMP packet
// (D-11-CONTEXT-5) belongs to the `includeEditingHistory` carrier — under
// the default policy it is NOT mounted (OQ-6's semantic narrowing, the
// checker-E2 user-ruling face).
//
// Codable: a brand-new type with no legacy payloads — synthesized is safe
// (every field is present in anything this code ever wrote).
// ─────────────────────────────────────────────────────────────────────────────

/// One export's metadata strategy. Value type; rides `ExportVariant` as the
/// `metadataPolicy` carrier (default `.standard`).
public struct ExportMetadataPolicy: Codable, Hashable, Sendable {

    /// The coarse mode (Alcedo `ExportMetadataMode`). `standard` = the
    /// carrier bools decide; `none` = everything stripped (the bools are
    /// moot — the consumer short-circuits on the mode).
    public enum Mode: String, Codable, Hashable, Sendable {
        case standard
        case none
    }

    /// The coarse mode.
    public var mode: Mode

    /// The EXIF carrier (photo mechanics: exposure, lens, capture time).
    public var includeExif: Bool

    /// The XMP carrier. NOTE: the editing-summary XMP packet is NOT this
    /// carrier — it rides `includeEditingHistory` (OQ-6).
    public var includeXMP: Bool

    /// The IPTC carrier (descriptive/rights fields).
    public var includeIPTC: Bool

    /// GPS/location data — FIXED STRIP default (README parity).
    public var includeLocation: Bool

    /// Device/body serial numbers — FIXED STRIP default.
    public var includeSerials: Bool

    /// The editing history face: sidecar-lineage metadata INCLUDING the
    /// editing-summary XMP packet (D-11-CONTEXT-5) — FIXED STRIP default
    /// (the packet is not mounted under the default policy, M2-9-03
    /// consumes).
    public var includeEditingHistory: Bool

    /// The full field-by-field init (the M2-9-03 UI's fine-grain face).
    public init(
        mode: Mode = .standard,
        exif: Bool = true,
        xmp: Bool = true,
        iptc: Bool = true,
        location: Bool = false,
        serials: Bool = false,
        editingHistory: Bool = false
    ) {
        self.mode = mode
        self.includeExif = exif
        self.includeXMP = xmp
        self.includeIPTC = iptc
        self.includeLocation = location
        self.includeSerials = serials
        self.includeEditingHistory = editingHistory
    }

    /// The STANDARD default: the three carriers on, the three strips off
    /// (the Alcedo hpp defaults + the README "stay excluded" face — also
    /// the `ExportVariant.metadataPolicy` type default).
    public static let standard = ExportMetadataPolicy()

    /// The NONE extreme: everything stripped, bools moot (the consumer
    /// short-circuits on the mode).
    public static let none = ExportMetadataPolicy(
        mode: .none, exif: false, xmp: false, iptc: false,
        location: false, serials: false, editingHistory: false)
}
