/// The v50 module-order table (FOUND-03) — a verbatim port of Darktable's
/// `v50_order[]` from `src/common/iop_order.c:298-415` (checked out at
/// https://github.com/darktable-org/darktable). ARCHITECTURE.md
/// Decision 3: Lightamer adopts Darktable's module positions as-is — the
/// table's placement comments (kept below) encode hard scene-referred
/// ordering constraints discovered over a decade of Darktable development.
///
/// Load-bearing properties (sidecar-stable from Phase 2 — the order value
/// rides in every history entry, so renumbering breaks decoding):
/// - The native rows (add-only family, each flagged at its row): skinSmooth
///   66.5 (07-2), textOverlay 66.7 (08-5), acesccIn/Out + eight M2-5-1
///   grade rows, filmPlacement 20.8 (M3-3-02) — 106 entries total (93
///   dt-verbatim + 13 native), positions 1.0 (`rawprepare`) → 78.0
///   (`gamma`). The dt discipline applies to EVERY native row: no
///   reordering, no renumbering, add-only.
/// - The deliberate 28.5 cluster: `channelmixerrgb` / `diffuse` /
///   `censorize` / `negadoctor` / `blurs` / `primaries` all share 28.5 —
///   the ONLY position collision in the table (they are mutually
///   independent scene-referred modules; Darktable tie-breaks by history
///   order). No other opName or position appears twice.
/// - `lut3d` sits at 36.0 but is LISTED out of numeric order in the C
///   source (between `filmicrgb` and `colisa`); the source listing order
///   is preserved here too — a verbatim port, not a re-sort.
public enum V50Order {

    /// `(opName, order)` pairs, verbatim from `iop_order.c:298-415`
    /// (terminator `{ 0.0, "" }` entry excluded).
    public static let entries: [(opName: String, order: Float)] = [
        ("rawprepare", 1.0),
        ("invert", 2.0),
        ("temperature", 3.0),
        ("rasterfile", 3.1),
        ("highlights", 4.0),
        ("cacorrect", 5.0),
        ("hotpixels", 6.0),
        ("rawdenoise", 7.0),
        ("demosaic", 8.0),
        ("denoiseprofile", 9.0),
        ("bilateral", 10.0),
        ("rotatepixels", 11.0),
        ("scalepixels", 12.0),
        ("lens", 13.0),
        // correct chromatic aberrations after lens correction so that
        // lensfun does not reintroduce chromatic aberrations when trying
        // to correct them
        ("cacorrectrgb", 13.5),
        ("hazeremoval", 14.0),
        ("ashift", 15.0),
        ("flip", 16.0),
        ("enlargecanvas", 16.5),
        ("overlay", 16.7),
        ("clipping", 17.0),
        ("liquify", 18.0),
        ("spots", 19.0),
        ("retouch", 20.0),
        // LIGHTAMER: acesccIn — the grade-domain envelope entry (M2-5-1,
        // D-M2-5-CONTEXT-3): sits BELOW every catalog op (exposure 21.0 is
        // the lowest 18-catalog slot) so each layer sub-run enters ACEScc
        // before any in-domain grading. Driver-constructed, never
        // registered (KD-2) — this row only pins the sub-run sort position.
        ("acesccIn", 20.5),
        // LIGHTAMER-NATIVE ROW (NOT a dt entry — Plan M3-3-02 T4, KD-5):
        // filmPlacement (the RFC-023 scene-placement curve, FSIM-01) sits
        // between acesccIn (20.5) and exposure (21.0) — placement is the
        // FIRST grade-domain mapping ("Scene Placement is the first
        // mapping": camera WB/temp 3.0 runs in the RAW domain before it,
        // every other catalog op sorts above). The dt discipline (no
        // reorder / unique / add-only) applies exactly as to 66.5/66.7.
        ("filmPlacement", 20.8),
        ("exposure", 21.0),
        ("mask_manager", 22.0),
        ("tonemap", 23.0),
        // last module that need enlarged roi_in
        ("toneequal", 24.0),
        // should go after all modules that may need a wider roi_in
        ("crop", 24.5),
        ("graduatednd", 25.0),
        ("profile_gamma", 26.0),
        ("equalizer", 27.0),
        ("colorin", 28.0),
        ("channelmixerrgb", 28.5),
        ("diffuse", 28.5),
        ("censorize", 28.5),
        // Cineon film encoding comes after scanner input color profile
        ("negadoctor", 28.5),
        // physically-accurate blurs (motion and lens)
        ("blurs", 28.5),
        ("primaries", 28.5),
        // signal processing (denoising) -> needs a signal as scene-referred
        // as possible (even if it works in Lab)
        ("nlmeans", 29.0),
        // calibration to "neutral" exchange colour space -> improve colour
        // calibration of colorin and reproductibility of further edits
        // (styles etc.)
        ("colorchecker", 30.0),
        // desaturate fringes in Lab, so needs properly calibrated colours
        // in order for chromaticity to be meaningful,
        ("defringe", 31.0),
        // frequential operation, needs a signal as scene-referred as possible
        // to avoid halos
        ("atrous", 32.0),
        ("lowpass", 33.0),  // same
        ("highpass", 34.0), // same
        // same, worst than atrous in same use-case, less control overall
        ("sharpen", 35.0),
        // probably better if source and destination colours are neutralized
        // in the same colour exchange space, hence after colorin and
        // colorcheckr, but apply after frequential ops in case it does
        // non-linear witchcraft, just to be safe
        ("colortransfer", 37.0),
        ("colormapping", 38.0), // same
        // does exactly the same thing as colorin, aka RGB to RGB matrix
        // conversion, but coefs are user-defined instead of calibrated and
        // read from ICC profile. Really versatile yet under-used module,
        // doing linear ops, very good in scene-referred workflow
        ("channelmixer", 39.0),
        // module mixing view/model/control at once, usage should be discouraged
        ("basicadj", 40.0),
        // nudges hues towards a set of target nodes
        ("colorharmonizer", 40.5),
        ("colorbalance", 41.0), // scene-referred color manipulation
        // LIGHTAMER: colorWheels — lift/gamma/gain color wheels (M2-5-1,
        // D-M2-5-CONTEXT-2 OQ-2-A). Shares 41.0 with the UNREGISTERED dt
        // `colorbalance` row — the DECLARED collision exception (the 28.5
        // cluster precedent; colorWheels is a NEW op, dt colorbalance has
        // no Lightamer module; a future dt-colorbalance enablement re-homes
        // one of the two — declared in M2-5-1-DECISIONS in advance).
        ("colorWheels", 41.0),
        ("colorequal", 41.2),
        // LIGHTAMER: cat02WhiteBalance — creative CAT02 white balance in the
        // ACEScc grade domain (M2-5-1, KD-4; camera WB stays RAW Decode).
        ("cat02WhiteBalance", 41.4),
        // scene-referred color manipulation
        ("colorbalancergb", 41.5),
        // LIGHTAMER: contrast — the mid-grey-pivot lightness contrast
        // (Alcedo OkLab S-curve semantics; ≠ colisa's RGB scaling, KD-5).
        ("contrast", 41.6),
        // LIGHTAMER: white — scene-referred white-endpoint calibration
        // (KD-5). 41.8 was planned; 42.0 collides with the (unregistered)
        // dt rgbcurve row, so black takes 41.95 within the KD-3 ±0.05
        // escape (DECISIONS signed).
        ("white", 41.8),
        // LIGHTAMER: black — scene-referred black-endpoint calibration
        // (KD-5; 41.95 = the KD-3 ±0.05 move off the rgbcurve 42.0 slot).
        ("black", 41.95),
        // really versatile way to edit colour in scene-referred and
        // display-referred workflow
        ("rgbcurve", 42.0),
        // LIGHTAMER: saturation / tint / hls — the remaining ACEScc-domain
        // grade ops (M2-5-1, KD-5/KD-7): multiplicative saturation 0..4,
        // the independent tint scalar, and the 8-bin selective color table.
        ("saturation", 42.2),
        ("tint", 42.4),
        ("hls", 42.6),
        ("rgblevels", 43.0), // same
        // conversion from scene-referred to display referred,
        // reverse-engineered on camera JPEG default look
        ("basecurve", 44.0),
        // same, but different (parametric) approach
        ("filmic", 45.0),
        ("sigmoid", 45.3),
        ("agx", 45.5),
        ("filmicrgb", 46.0), // same, upgraded
        // apply a creative style or film emulation, possibly non-linear
        // (listed out of numeric order in the C source — verbatim port)
        ("lut3d", 36.0),
        // edit contrast while damaging colour
        ("colisa", 47.0),
        ("tonecurve", 48.0), // same
        ("levels", 49.0),    // same
        ("shadhi", 50.0),    // same
        ("zonesystem", 51.0),    // same
        ("globaltonemap", 52.0), // same
        // flatten local contrast while pretending do add lightness
        ("relight", 53.0),
        // improve clarity/local contrast after all the bad things we have
        // done to it with tonemapping
        ("bilat", 54.0),
        // now that the colours have been damaged by contrast manipulations,
        // try to recover them - global adjustment of white balance for
        // shadows and highlights
        ("colorcorrection", 55.0),
        ("colorcontrast", 56.0), // adjust chrominance globally
        ("velvia", 57.0),        // same
        ("vibrance", 58.0),      // same, but more subtle
        ("colorzones", 60.0),    // same, but locally
        ("bloom", 61.0),         // creative module
        ("colorize", 62.0),      // creative module
        ("lowlight", 63.0),      // creative module
        ("monochrome", 64.0),    // creative module
        ("grain", 65.0),         // creative module
        ("soften", 66.0),        // creative module
        // LIGHTAMER-NATIVE ROW (NOT a dt entry — Plan 07-2, D-07-CONTEXT-2,
        // the first and only non-dt row in this verbatim table): skinSmooth
        // (frequency-separation skin smoothing, AI-05) sits between soften
        // (66.0) and splittoning (67.0) — the blur/creative neighborhood,
        // RGB segment after colorin. The dt discipline (no reorder / unique
        // / add-only) applies to this row exactly as to the verbatim rows.
        ("skinSmooth", 66.5),
        // LIGHTAMER-NATIVE ROW (NOT a dt entry — Plan 08-5 T2, D-08-CONTEXT-9):
        // textOverlay (the editing-time text layer, IOP-FX-05) sits in the
        // 66.5–67.0 gap — after skinSmooth, before splittoning — well below
        // the 70.0 terminal tail floor (LayerCompositeDriver), so the layer-
        // mask eligibility holds; this is the ESSENTIAL division from the
        // yiyin watermark (77.0, terminal segment — the final-output
        // watermark, which stays untouched). The dt discipline (no reorder
        // / unique / add-only) applies to this row exactly as to 66.5.
        ("textOverlay", 66.7),
        ("splittoning", 67.0),   // creative module
        ("vignette", 68.0),      // creative module
        // try to salvage blown areas before ICC intents in LittleCMS2 do
        // things with them.
        ("colorreconstruct", 69.0),
        ("finalscale", 69.4),
        // LIGHTAMER: acesccOut — the grade-domain envelope exit (M2-5-1,
        // D-M2-5-CONTEXT-3): the HIGHEST below-floor position (terminal
        // floor 70.0, splittoning 67.0 below it) so every catalog op stays
        // inside the envelope and nothing escapes into the terminal tail.
        ("acesccOut", 69.9),
        ("colorout", 70.0),
        ("clahe", 71.0),
        ("overexposed", 73.0),
        ("rawoverexposed", 74.0),
        ("dither", 75.0),
        ("borders", 76.0),
        ("watermark", 77.0),
        ("gamma", 78.0),
    ]

    /// Look up a module's v50 position. Returns the first matching entry —
    /// for the deliberate 28.5 cluster this is the listing order above
    /// (all six share the same value, so the result is identical regardless).
    public static func order(for opName: String) -> Float? {
        entries.first { $0.opName == opName }?.order
    }
}
