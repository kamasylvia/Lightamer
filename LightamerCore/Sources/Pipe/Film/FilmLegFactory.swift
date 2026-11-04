import Metal

// ─────────────────────────────────────────────────────────────────────────────
// FilmLegFactory (spektra-module P1 T2') — the PUBLIC wrapper around the
// sealed `PixelPipe.assembleFilmLeg` factory (the module face cannot call
// the internal static directly from LightamerIOP).
//
// SAME-SHAPE PASS-THROUGH: every parameter forwards verbatim; the factory
// bodies (`assembleDensityFilmLeg` / `assembleSpectralFilmLeg`) stay
// byte-identical (AC-T2'-3 pins the md5). This file is the ONLY new Core
// production surface the module's process step touches besides the two
// seams (FilmMaterialSeam / FilmStatsSeam).
// ─────────────────────────────────────────────────────────────────────────────

public enum FilmLegFactory {

    /// Assemble the film-leg payloads for a record (density/spectral arm
    /// selected by the run's resolved process — the factory's exhaustive
    /// switch, unchanged).
    public static func assemble(
        record: FilmRecord,
        film: FilmProfile?,
        paper: FilmProfile?,
        materialPairHash: UInt64,
        histogram: FilmStatsSeam.PlaneHistogram?,
        plane: any MTLTexture,
        metal: MetalContext,
        renderProcess: RenderProcessVersion
    ) -> FilmLegAssembly {
        PixelPipe.assembleFilmLeg(
            record: record, film: film, paper: paper,
            materialPairHash: materialPairHash, histogram: histogram,
            plane: plane, metal: metal, renderProcess: renderProcess)
    }
}
