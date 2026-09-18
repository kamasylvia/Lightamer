/// The colorspace an `IOPModule`'s process step expects its input in —
/// the port of Darktable's `dt_iop_colorspace_type_t` (iop_api.h).
///
/// Lightamer's working space is linear Rec2020 scene-referred (FOUND-02),
/// so modules declaring `.RGB` process Rec2020-linear float32 data; the
/// Phase 2 terminal trio (`colorin` converts raw→RGB, `colorout`+`gamma`
/// convert RGB→display) brackets the chain exactly as in Darktable.
public enum IOPColorspace: Sendable {

    /// Camera-native sensor data (before `rawprepare`/`colorin` semantics).
    case raw

    /// Prepared sensor data (black/white-level applied, float normalised) —
    /// between `rawprepare` and `demosaic`/`colorin`.
    case rawPrepared

    /// Linear RGB in the working space (Rec2020, FOUND-02).
    case RGB

    /// CIE Lab (display-referred-era modules; Phase 3+ creative iops).
    case Lab
}
