/// The v50 module-order table (FOUND-03) — a verbatim port of Darktable's
/// `v50_order[]` from `src/common/iop_order.c:298-415` (checked out at
/// `/path/to/darktable`). ARCHITECTURE.md
/// Decision 3: Lightamer adopts Darktable's module positions as-is — the
/// table's placement comments (kept below) encode hard scene-referred
/// ordering constraints discovered over a decade of Darktable development.
///
/// Load-bearing properties (sidecar-stable from Phase 2 — the order value
/// rides in every history entry, so renumbering breaks decoding):
/// - 93 entries, positions 1.0 (`rawprepare`) → 78.0 (`gamma`).
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
        ("colorequal", 41.2),
        // scene-referred color manipulation
        ("colorbalancergb", 41.5),
        // really versatile way to edit colour in scene-referred and
        // display-referred workflow
        ("rgbcurve", 42.0),
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
        ("splittoning", 67.0),   // creative module
        ("vignette", 68.0),      // creative module
        // try to salvage blown areas before ICC intents in LittleCMS2 do
        // things with them.
        ("colorreconstruct", 69.0),
        ("finalscale", 69.4),
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
