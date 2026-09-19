import Foundation

// ─────────────────────────────────────────────────────────────────────────
// SigmoidDerivation (Plan 03-04-T3) — the CPU half of sigmoid (Plan 03-04
// T3/T4, IOP-FILM-02): dt's `commit_params` four-scalar derivation,
// transliterated from `src/iop/sigmoid.c:318-407` (tree dc58cf0ba1).
//
// The log-logistic model (sigmoid.c:300-316) has five free constants
// (magnitude, paper_exposure, film_fog, film_power, paper_power); the
// commit pins them from four user scalars (contrast, skew, display
// white/black targets) through the constraint set
//   f(scene_zero) = display_black_target
//   f(scene_grey) = MIDDLE_GREY (0.1845 — sigmoid.c:37)
//   f(scene_inf)  = display_white_target
//   slope at scene_grey driven by contrast only (skew-free reference slope
//   ratio) — sigmoid.c:325-330.
//
// PRECISION DEVIATION (recorded, L006 spirit): dt derives in float32
// (powf); this port derives in Double and publishes float32 to the
// kernel. The GPU kernel consumes float32 either way; the double
// derivation removes the powf accumulation noise so the synthesized
// golden references (float64) and the CPUDerivationTests cross-check
// agree at 1e-12 instead of inheriting ~1e-6 drift. The published
// scalars still quantize to the float32 grid the kernel sees.
//
// INPUT-SEMANTICS CAVEAT (plan Goal, RESEARCH §Summary#5): the
// display_white/black_target pair is an OUTPUT-side parameter — the
// defaults (100 / 0.0152) are input-domain independent and ship as-is.
// The scene-side defaults (MIDDLE_GREY anchor etc.) assume scene-linear
// input; on CIRAW displayed-domain RAW the middle-grey anchor needs
// per-camera calibration — a PRODUCT-SEMANTICS task, deliberately
// decoupled from the algorithm parity (which runs on synthetic
// scene-linear fixtures both sides consume).
// ─────────────────────────────────────────────────────────────────────────

public enum SigmoidDerivation {

    /// dt `MIDDLE_GREY` (sigmoid.c:37) — 18.45% scene grey.
    public static let middleGrey: Double = 0.1845

    /// The derivation delta (sigmoid.c:339).
    public static let delta: Double = 1e-6

    /// The kernel-facing scalars (dt `dt_iop_sigmoid_data_t` numeric half,
    /// sigmoid.c:160-174) — published float32.
    public struct Scalars: Equatable, Sendable {
        public var whiteTarget: Float
        public var blackTarget: Float
        public var paperExposure: Float
        public var filmFog: Float
        public var filmPower: Float
        public var paperPower: Float
        public var huePreservation: Float
    }

    /// Every intermediate in Double — the plan's "中间量日志钩子" and the
    /// CPUDerivationTests cross-check surface.
    public struct Trace: Equatable, Sendable {
        public var refSlope: Double
        public var paperPower: Double
        public var tempSlope: Double
        public var filmPower: Double
        public var whiteTarget: Double
        public var blackTarget: Double
        public var whiteGreyRelation: Double
        public var whiteBlackRelation: Double
        public var filmFog: Double
        public var paperExposure: Double
        public var huePreservation: Double
    }

    /// dt `_generalized_loglogistic_sigmoid` (sigmoid.c:300-316) — the
    /// stable-at-zero form of the film+paper model, Double for the CPU
    /// reference path (the kernel runs the float32 mirror).
    public static func generalizedLoglogisticSigmoid(
        value: Double,
        magnitude: Double,
        paperExposure: Double,
        filmFog: Double,
        filmPower: Double,
        paperPower: Double
    ) -> Double {
        let clampedValue = max(value, 0.0)
        // magnitude * pow(1 + paper_exp * pow(film_fog + value, -film_power), -paper_power)
        // rewritten around the pole at 0 (sigmoid.c:308-311):
        let filmResponse = pow(filmFog + clampedValue, filmPower)
        let paperResponse = magnitude * pow(filmResponse / (paperExposure + filmResponse), paperPower)
        // Safety check for very large floats that cause numerical errors
        return paperResponse.isNaN ? magnitude : paperResponse
    }

    /// The central-difference slope at MIDDLE_GREY under the given
    /// parameters (sigmoid.c:340-345 / :356-361 shapes).
    static func slopeAtGrey(
        magnitude: Double, paperExposure: Double, filmFog: Double,
        filmPower: Double, paperPower: Double
    ) -> Double {
        let high = generalizedLoglogisticSigmoid(
            value: middleGrey + delta, magnitude: magnitude, paperExposure: paperExposure,
            filmFog: filmFog, filmPower: filmPower, paperPower: paperPower
        )
        let low = generalizedLoglogisticSigmoid(
            value: middleGrey - delta, magnitude: magnitude, paperExposure: paperExposure,
            filmFog: filmFog, filmPower: filmPower, paperPower: paperPower
        )
        return (high - low) / 2.0 / delta
    }

    /// dt `commit_params` (sigmoid.c:318-392) verbatim in Double.
    /// - Parameters mirror the four user-facing scalars + hue preservation
    ///   (percent units, dt GUI domain).
    public static func derive(
        middleGreyContrast: Double,
        contrastSkewness: Double,
        displayWhiteTarget: Double,
        displayBlackTarget: Double,
        huePreservationPercent: Double
    ) -> (scalars: Scalars, trace: Trace) {
        // Reference slope for no skew and a normalized display
        // (sigmoid.c:332-345).
        let refFilmPower = middleGreyContrast
        let refPaperPower = 1.0
        let refMagnitude = 1.0
        let refFilmFog = 0.0
        let refPaperExposure = pow(refFilmFog + middleGrey, refFilmPower) * ((refMagnitude / middleGrey) - 1.0)
        let refSlope = slopeAtGrey(
            magnitude: refMagnitude, paperExposure: refPaperExposure,
            filmFog: refFilmFog, filmPower: refFilmPower, paperPower: refPaperPower
        )

        // Add skew (sigmoid.c:347-348).
        let paperPower = pow(5.0, -contrastSkewness)

        // Slope at low film power (sigmoid.c:350-361).
        let tempFilmPower = 1.0
        let tempWhiteTarget = 0.01 * displayWhiteTarget
        let tempWhiteGreyRelation = pow(tempWhiteTarget / middleGrey, 1.0 / paperPower) - 1.0
        let tempPaperExposure = pow(middleGrey, tempFilmPower) * tempWhiteGreyRelation
        let tempSlope = slopeAtGrey(
            magnitude: tempWhiteTarget, paperExposure: tempPaperExposure,
            filmFog: refFilmFog, filmPower: tempFilmPower, paperPower: paperPower
        )

        // The film power that fulfills the target slope (sigmoid.c:363-365).
        let filmPower = refSlope / tempSlope

        // The remaining parameters now that both powers are known
        // (sigmoid.c:367-379).
        let whiteTarget = 0.01 * displayWhiteTarget
        let blackTarget = 0.01 * displayBlackTarget
        let whiteGreyRelation = pow(whiteTarget / middleGrey, 1.0 / paperPower) - 1.0
        let whiteBlackRelation = pow(blackTarget / whiteTarget, -1.0 / paperPower) - 1.0

        let filmFog = middleGrey * pow(whiteGreyRelation, 1.0 / filmPower)
            / (pow(whiteBlackRelation, 1.0 / filmPower) - pow(whiteGreyRelation, 1.0 / filmPower))
        let paperExposure = pow(filmFog + middleGrey, filmPower) * whiteGreyRelation

        let huePreservation = min(max(0.01 * huePreservationPercent, 0.0), 1.0)

        let trace = Trace(
            refSlope: refSlope,
            paperPower: paperPower,
            tempSlope: tempSlope,
            filmPower: filmPower,
            whiteTarget: whiteTarget,
            blackTarget: blackTarget,
            whiteGreyRelation: whiteGreyRelation,
            whiteBlackRelation: whiteBlackRelation,
            filmFog: filmFog,
            paperExposure: paperExposure,
            huePreservation: huePreservation
        )
        let scalars = Scalars(
            whiteTarget: Float(whiteTarget),
            blackTarget: Float(blackTarget),
            paperExposure: Float(paperExposure),
            filmFog: Float(filmFog),
            filmPower: Float(filmPower),
            paperPower: Float(paperPower),
            huePreservation: Float(huePreservation)
        )
        return (scalars, trace)
    }
}
