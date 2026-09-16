/// PS-style blend modes (LAYER-05) — raw values ported from Darktable's
/// `dt_develop_blend_mode_t` (`src/develop/blend.h:44-91`,
/// `DEVELOP_BLEND_*` enum, minus the clamping/legacy variants).
///
/// ⚠ The raw Int values are FROZEN as of Phase 1: they persist into
/// sidecars from Phase 2 (LAYER-07), so renumbering any case breaks
/// decoding of every previously written sidecar. They mirror Darktable's
/// enum precisely so the Phase 6 `blendop` kernel port (from
/// `data/kernels/blendop.cl`) maps case-for-case.
///
/// Phase 6 note: Darktable ORs `DEVELOP_BLEND_REVERSE = 0x80000000`
/// (blend.h:89) into any mode to invert the blend — Lightamer can adopt
/// the same flag-bit trick without disturbing these values.
public enum BlendMode: Int, Sendable, Codable, CaseIterable {

    /// `DEVELOP_BLEND_NORMAL2` — the modern non-clamping normal.
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
    /// `DEVELOP_BLEND_LIGHTNESS`
    case luminosity = 0x10
    /// `DEVELOP_BLEND_CHROMATICITY`
    case saturation = 0x11
    /// `DEVELOP_BLEND_HUE`
    case hue = 0x12
    /// `DEVELOP_BLEND_COLOR`
    case color = 0x13
    /// `DEVELOP_BLEND_COLORADJUST` — closest PS color-dodge analog.
    case colorDodge = 0x16
    /// `DEVELOP_BLEND_DIFFERENCE2`
    case difference = 0x17

    // Darktable's full enum (blend.h:44-91) carries ~40 variants; this
    // skeleton ports the PS-canonical subset of REQUIREMENTS LAYER-05.
    // Additional modes extend this enum with NEW raw values only — never
    // renumber existing ones.
}
