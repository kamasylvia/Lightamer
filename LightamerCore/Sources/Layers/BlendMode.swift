// ─────────────────────────────────────────────────────────────────────────────
// BlendMode — PS-style blend modes (LAYER-05). D-06-CONTEXT-2 resolution
// (Plan 06-01 T1): the raw Int values below are FROZEN as of Phase 1 (they
// persist into sidecars from Phase 2 — LAYER-07; renumbering any case breaks
// decoding of every previously written sidecar), and their SEMANTICS follow
// Darktable's MODERN formula set, NOT the historical formula of the enum slot
// the raw value happens to occupy in `dt_develop_blend_mode_t`
// (`src/develop/blend.h:44-91`).
//
// THREE-WAY MAPPING TABLE (raw value ↔ dt enum slot ↔ implemented semantics).
// Verified value-by-value against blend.h:44-91 (tree dc58cf0ba1):
//
// | raw   | dt enum slot (blend.h line)          | Lightamer case | implemented semantics (formula lands in 6-2)                          |
// |-------|--------------------------------------|----------------|-----------------------------------------------------------------------|
// | 0x01  | DEVELOP_BLEND_NORMAL_OBSOLETE (:47)  | normal         | **NORMAL2 modern formula** (dt's modern normal lives at 0x18, :70):   |
// |       | ("obsolete as it did clamping")      |                | `o = a·(1−op) + blend(a,b)·op`, no legacy clamping — the NORMAL2      |
// |       |                                      |                | branch of blendop.cl:646+. This is the modern-PS-normal equivalent.   |
// | 0x04  | DEVELOP_BLEND_MULTIPLY (:52)         | multiply       | dt MODERN multiply, linear Rec2020                                    |
// | 0x07  | DEVELOP_BLEND_SUBTRACT (:55)         | linearBurn     | dt SUBTRACT — the PS linear-burn analog                               |
// | 0x09  | DEVELOP_BLEND_SCREEN (:57)           | screen         | dt MODERN screen                                                      |
// | 0x0A  | DEVELOP_BLEND_OVERLAY (:58)          | overlay        | dt overlay — LINEAR Rec2020 domain (NOT the PS gamma-encoded variant) |
// | 0x0B  | DEVELOP_BLEND_SOFTLIGHT (:59)        | softLight      | dt softlight, linear Rec2020                                          |
// | 0x0C  | DEVELOP_BLEND_HARDLIGHT (:60)        | hardLight      | dt hardlight, linear Rec2020                                          |
// | 0x10  | DEVELOP_BLEND_LIGHTNESS (:64)        | luminosity     | dt LIGHTNESS (JzCzhz L-component swap)                                |
// | 0x11  | DEVELOP_BLEND_CHROMATICITY (:65)     | saturation     | dt CHROMATICITY (JzCzhz chroma swap)                                  |
// | 0x12  | DEVELOP_BLEND_HUE (:66)              | hue            | dt hue (shortest-path angle interpolation)                            |
// | 0x13  | DEVELOP_BLEND_COLOR (:67)            | color          | dt color (JzCzhz color swap)                                          |
// | 0x16  | DEVELOP_BLEND_COLORADJUST (:68)      | colorAdjust    | dt COLORADJUST ("blend in the ADJUSTED color only" special mode) —    |
// |       |                                      |                | **NOT** a PS color dodge. True PS dodge/burn arrive later as NEW raw  |
// |       |                                      |                | values (W3C Compositing-1, 6-2); case renamed from `colorDodge`.      |
// | 0x17  | DEVELOP_BLEND_DIFFERENCE2 (:69)      | difference     | dt DIFFERENCE2 (the modern difference; 0x08 is the deprecated one)    |
// | 0x02  | DEVELOP_BLEND_LIGHTEN (:48)          | lighten        | dt lighten — max(a,b) mix (added 06-02-T4; the Lab kernel's L-chroma  |
// |       |                                      |                | legs are Lab-specific and do not transpose to linear Rec2020)         |
// | 0x03  | DEVELOP_BLEND_DARKEN (:49)           | darken         | dt darken — min(a,b) mix (added 06-02-T4)                             |
// | 0x2A  | — (OUTSIDE dt's enum; free slot      | psColorDodge   | W3C Compositing-1 §color-dodge (added 06-02-T4). dt has no PS dodge;  |
// |       | audited against blend.h:44-91)       |                | the slot value 0x2A is beyond dt's 0x29 HARMONIC_MEAN — a sidecar     |
// |       |                                      |                | carrying it into dt would blend as normal there (documented loss)     |
// | 0x2B  | — (OUTSIDE dt's enum; free slot)     | psColorBurn    | W3C Compositing-1 §color-burn (added 06-02-T4)                        |
//
// FORMULA LANDMARK (06-02 complete): every case above now HAS its formula —
// the float64 source of truth is `BlendOpReference.swift` (IOP), the kernel
// `BlendOpKernels.metal` (compositeLayer), gated <1e-5 rel (arithmetic) /
// measured pow-chain floor (perceptual) by BlendOpParityTests.
//
// WHY values are not renumbered (D-06-CONTEXT-2, four reasons):
// 1. sidecar ONE-WAY format lock — raw values ride every `.lra` since
//    Phase 2; renumbering = breaking decode of all written documents.
// 2. Phase 1 freeze promise (the original header note) — planner-level
//    reversal costs more (trust + full regression) than the wrong-slot
//    cosmetic ever gains.
// 3. Darktable precedent — enum slots change formula across dt versions
//    (NORMAL → NORMAL2 evolution + `DEVELOP_BLEND_VERSION = 14`
//    versioning, blend.h:31). "Slot ≠ formula" IS dt semantics: the stored
//    value names the user-intent slot, behavior is defined by the
//    implementing version.
// 4. No user-visible loss — true PS color dodge gets a NEW raw value; the
//    NORMAL2 formula for `normal` IS modern normal.
//
// Case-rename safety: `BlendMode: Int, Codable` encodes the rawValue
// integer — case NAMES never reach the disk. Renaming `colorDodge` →
// `colorAdjust` is sidecar-neutral (regression-pinned: decode of
// `{"0x16 as Int"}`-bearing JSON yields `.colorAdjust` with the identical
// rawValue; LayerCoreTests).
//
// EXTENSION discipline (unchanged from Phase 1): additional modes extend
// this enum with NEW raw values only — never renumber existing ones.
// ─────────────────────────────────────────────────────────────────────────────

/// OptionSet for the flag bits Darktable ORs into a blend mode value
/// (`blend.h:89`): `DEVELOP_BLEND_REVERSE = 0x80000000` swaps the blend's
/// a/b operands — `a` (the below/composite plane) and `b` (this layer's
/// output) exchange roles. Lightamer stores the flag BESIDE the mode (not
/// OR-ed into `BlendMode.rawValue`) so the enum stays a clean slot table;
/// the composite engine reads both.
public struct BlendOptions: OptionSet, Sendable, Hashable, Codable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// `DEVELOP_BLEND_REVERSE` (blend.h:89) — swap a/b: the layer output
    /// becomes the base and the below-composite becomes the source.
    public static let reverse = BlendOptions(rawValue: 0x8000_0000)
}

public enum BlendMode: Int, Sendable, Codable, CaseIterable {

    /// dt slot 0x01 = NORMAL_OBSOLETE — implements the NORMAL2 modern
    /// formula (see the mapping table above).
    case normal = 0x01
    /// `DEVELOP_BLEND_MULTIPLY`
    case multiply = 0x04
    /// `DEVELOP_BLEND_SUBTRACT` — the PS linear-burn analog.
    case linearBurn = 0x07
    /// `DEVELOP_BLEND_SCREEN`
    case screen = 0x09
    /// `DEVELOP_BLEND_OVERLAY`
    case overlay = 0x0A
    /// `DEVELOP_BLEND_SOFTLIGHT`
    case softLight = 0x0B
    /// `DEVELOP_BLEND_HARDLIGHT`
    case hardLight = 0x0C
    /// `DEVELOP_BLEND_LIGHTNESS` (JzCzhz)
    case luminosity = 0x10
    /// `DEVELOP_BLEND_CHROMATICITY` (JzCzhz)
    case saturation = 0x11
    /// `DEVELOP_BLEND_HUE` (JzCzhz)
    case hue = 0x12
    /// `DEVELOP_BLEND_COLOR` (JzCzhz)
    case color = 0x13
    /// `DEVELOP_BLEND_COLORADJUST` — dt's "blend in adjusted color" mode
    /// (renamed from Phase 1's `colorDodge`; NOT a PS color dodge — the
    /// mapping table header has the full story).
    case colorAdjust = 0x16
    /// `DEVELOP_BLEND_DIFFERENCE2`
    case difference = 0x17
    /// `DEVELOP_BLEND_LIGHTEN` (06-02-T4) — max(a,b) mix.
    case lighten = 0x02
    /// `DEVELOP_BLEND_DARKEN` (06-02-T4) — min(a,b) mix.
    case darken = 0x03
    /// PS color dodge (06-02-T4) — NEW raw value 0x2A, OUTSIDE dt's enum
    /// (free-slot audit against blend.h:44-91: dt tops out at 0x29). The
    /// formula is W3C Compositing-1; a document carrying this value into
    /// dt would blend as normal there (documented one-way loss).
    case psColorDodge = 0x2A
    /// PS color burn (06-02-T4) — NEW raw value 0x2B, same audit story.
    case psColorBurn = 0x2B

    /// The dt `DEVELOP_BLEND_MODE_MASK = 0xFF` (blend.h:90) projection —
    /// the mode slot of a dt-style packed value with flag bits stripped.
    public var dtModeSlot: UInt32 {
        UInt32(bitPattern: Int32(rawValue)) & 0xFF
    }

    /// The dt-style packed value for this mode (no option flags set).
    public var dtPackedValue: UInt32 {
        UInt32(bitPattern: Int32(rawValue))
    }
}
