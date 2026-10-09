import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// FilmDescriptorProbe (Plan M3-4-01 T2, KD-2) — the medium probe (RFC-023
// §8.1): a 1024×1 neutral ramp (pixels = 0.184·2^E, E uniform on
// [−12, +12]) through the REAL film sub-run — the payload assembly rides
// `PixelPipe.assembleFilmLeg` (the production film leg's own factory) and
// the dispatch rides the production `FilmMethodBox` with its run-context
// seam. NO parallel implementation of the chain exists anywhere here: the
// probe is definitionally correct because it is the same code path as the
// picture.
//
// PROBE CONFIG (auto exposure off): the neutral pack (the solve's M0/Y0),
// zero manual shifts, strength 1, record exposureEv 0, and gain = 1 —
// achieved by feeding the factory a NIL histogram (the solve's
// gain-rides-2^exposureEv face, which is 1 for the pristine record). The
// config constants are compile-time values and the tag folds into the
// descriptor cache key — a config change re-keys (never silently stale).
//
// L014: the read-back happens only after a queue fence — never across
// in-flight encoders.
// ─────────────────────────────────────────────────────────────────────────────

public enum FilmDescriptorProbe {

    /// The ramp's texel count (the §8.1 1024×1 shape).
    public static let rampLength = 1024
    /// The probe domain, stops relative to mid-gray.
    public static let domainMin = -12.0
    public static let domainMax = 12.0

    /// The probe identity tag — folded into the descriptor cache key (the
    /// config-change re-key face).
    public static let probeTag = "lightamer.film.descriptor.probe.v1"

    /// The probe's typed failure face: the payload assembly degraded (no
    /// device resources / unresolvable materials). The descriptor is a
    /// MEASUREMENT — a degraded probe is an error, never a fake number.
    public enum ProbeError: Error, Equatable, Sendable {
        case payloadAssemblyDegraded
    }

    /// Probe one material pair. Synchronous-in-async (one dispatch + one
    /// fence); the caller owns caching (`FilmDescriptorCache`).
    public static func probe(
        film: FilmProfile, paper: FilmProfile, materialPairHash: UInt64,
        metal: MetalContext
    ) async throws -> ProfileLatitudeDescriptor {
        // ① The ramp (programmatic; the [0,1] linear domain's far ends clip
        // — the plateaus ARE the Y_white/Y_black faces the reduce reads).
        var texels = [Float](repeating: 0, count: rampLength * 4)
        for index in 0..<rampLength {
            let e = domainMin
                + (domainMax - domainMin) * Double(index) / Double(rampLength - 1)
            let value = Float(0.184 * Foundation.pow(2.0, e))
            texels[index * 4 + 0] = value
            texels[index * 4 + 1] = value
            texels[index * 4 + 2] = value
            texels[index * 4 + 3] = 1.0
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: rampLength, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let input = metal.device.makeTexture(descriptor: descriptor),
            let output = metal.device.makeTexture(descriptor: descriptor)
        else { throw ProbeError.payloadAssemblyDegraded }
        texels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, rampLength, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: rampLength * 16)
        }

        // ② THE PRODUCTION ASSEMBLY (§8.1 same-code-path): the factory the
        // film leg itself uses — histogram nil = the auto-exposure-off face
        // (gain exactly 1, the neutral pack from the session solver).
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let assembled = PixelPipe.assembleFilmLeg(
            record: record, film: film, paper: paper,
            materialPairHash: materialPairHash, histogram: nil,
            plane: input, metal: metal)
        guard let payloads = assembled.payloads else {
            throw ProbeError.payloadAssemblyDegraded
        }

        // ③ The production box dispatch (the run-context seam — set/clear
        // inside this synchronous window, runFilmLeg's own escape).
        let box = FilmMethodBox(record: assembled.method.record, method: assembled.method)
        var piece = IOPiece()
        box.commitParams(assembled.method, into: &piece)
        FilmMethodBox.runContext = payloads
        defer { FilmMethodBox.runContext = nil }
        try await box.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)

        // ④ L014 fence, then the read-back.
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var values = [Float](repeating: 0, count: rampLength * 4)
        values.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: rampLength * 16,
                from: MTLRegionMake2D(0, 0, rampLength, 1), mipmapLevel: 0)
        }

        // ⑤ THE SCAN FACE (the §8.1 measurement domain): the film leg's
        // output is the SCENE-REFERRED face (the print density re-inverted
        // to 10^e — the bake's step 6; its white end carries the film's
        // whole shoulder and runs far past 1.0). The MEDIUM the descriptor
        // measures is the PRINT: R = 10^(−D_print), D_print = the chain's
        // own forward system face (FilmPrintBake.systemDensity — the SAME
        // session terms the bake closed over: base projection, per-channel
        // Dmin, the K calibration, the neutral pack) evaluated at the
        // output's own e. Inverse∘forward on the chain's own functions —
        // no second implementation of the chain exists here (DECISIONS:
        // the scan-seam declaration). Upstream's own probe reads the same
        // domain (their §15.2 print spans [0.00443, 0.7051]).
        let pack = try FilmFilterPackSolver.solveNeutralPack(film: film, paper: paper)
        let packM = pack.magentaCC * FilmFilterPackSolver.magentaExposurePerCC
        let packY = pack.yellowCC * FilmFilterPackSolver.yellowExposurePerCC
        let base = try film.baseDensityProjection()
        var dmin = (
            r: Double.greatestFiniteMagnitude,
            g: Double.greatestFiniteMagnitude,
            b: Double.greatestFiniteMagnitude)
        for i in 0..<paper.logExposure.count {
            dmin.r = min(dmin.r, Double(paper.densityCurves[i][0]))
            dmin.g = min(dmin.g, Double(paper.densityCurves[i][1]))
            dmin.b = min(dmin.b, Double(paper.densityCurves[i][2]))
        }
        let eMid = Foundation.log10(FilmFilterPackSolver.midGraySceneLinear)
        let sessionMidGreenDensity = FilmFilterPackSolver.curveValue(
            film, channel: 1, at: eMid) + base.g - packM
        let calibration = FilmPrintBake.solveExposureCalibration(
            film: film, paper: paper, base: base,
            midGrayDensity: sessionMidGreenDensity,
            paperMid: (dmin.g + FilmPrintBake.maxGreen(paper)) / 2)
        var response = [Double](repeating: 0, count: rampLength)
        let dminPerChannel = [dmin.r, dmin.g, dmin.b]
        for index in 0..<rampLength {
            var reflectance = SIMD3<Double>.zero
            for c in 0..<3 {
                let out = Double(values[index * 4 + c])
                let eScene = Foundation.log10(max(out, 1e-30))
                let density = FilmPrintBake.systemDensity(
                    film: film, paper: paper, base: base, channel: c,
                    exposure: eScene, dmin: dminPerChannel[c],
                    calibration: calibration, packM: packM, packY: packY)
                reflectance[c] = Foundation.pow(10.0, -density)
            }
            response[index] =
                0.2627 * reflectance.x + 0.6780 * reflectance.y + 0.0593 * reflectance.z
        }

        // ⑥ The ISO 6846 reduction (the E1-corrected criteria) + the
        // reference mid-anchor reading (the paper's mid DENSITY linear
        // value — the K calibration places input 0.184 there, so the
        // crossing sits ≈ 0).
        guard let usefulShadow = FilmLatitudeReduce.usefulShadowEV(
            response, evMin: domainMin, evMax: domainMax),
            let usefulHighlight = FilmLatitudeReduce.usefulHighlightEV(
                response, evMin: domainMin, evMax: domainMax)
        else { throw ProbeError.payloadAssemblyDegraded }
        let paperMidLinear = paperMidDensityLinear(paper)
        let reference = FilmLatitudeReduce.firstCrossingEV(
            response, evMin: domainMin, evMax: domainMax, level: paperMidLinear)
            ?? 0

        return ProfileLatitudeDescriptor(
            evMin: domainMin, evMax: domainMax,
            usefulShadowEV: usefulShadow, usefulHighlightEV: usefulHighlight,
            referenceEV: reference,
            response: response.map { Float($0) },
            slope: FilmLatitudeReduce.slopes(response, evMin: domainMin, evMax: domainMax),
            materialPairHash: materialPairHash)
    }

    /// The paper's mid density as a LINEAR output value (the K
    /// calibration's own mid anchor: paperMidGreen = (dmin_g + dmax_g)/2 —
    /// the bake's formula; 10^(−D) converts to the working space's Y).
    public static func paperMidDensityLinear(_ paper: FilmProfile) -> Double {
        var dmin = Double.greatestFiniteMagnitude
        for i in 0..<paper.logExposure.count {
            dmin = min(dmin, Double(paper.densityCurves[i][1]))
        }
        let paperMidGreen = (dmin + FilmPrintBake.maxGreen(paper)) / 2
        return Foundation.pow(10.0, -paperMidGreen)
    }
}
