import CoreGraphics
import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// Plan 13-2 T2 — the soft-proof stage (COLOR-02): a coordinator-minted pipe
// segment inserted UPSTREAM of colorout (v50 gap 69.5, between the editing
// iops and colorout 70.0).
//
// **Pipeline shape (D-13-CONTEXT-4②):** linear Rec2020 → PRINTER ICC →
// linear Rec2020 — a ColorSync round trip. The forward leg maps working-
// space colors onto what the printer can actually produce (relative
// colorimetric + BPC per the T1 probe); the back leg expresses those paper
// colors back in the working space, so the DOWNSTREAM colorout+gamma display
// segment is untouched (the "existing display transform" stays byte-exact —
// the proof simulation rides entirely in this stage). In-gamut colors round
// trip EXACTLY (T1 probe §3.1: max delta 0.0000 on an AdobeRGB pair);
// out-of-gamut colors clip irreversibly — which is the simulation.
//
// **NOT a registry module (the zero-regression red line):** the coordinator
// mints the box at render time and inserts it ONLY while proof is ON. Proof
// OFF = the stage is absent from the chain entirely — the rendered chain is
// byte-identical to the pre-13-2 pipeline (the strongest form of the
// pass-through assertion). The box never enters `EditorState.instances`,
// never enters history records, never enters the sidecar, never enters the
// export chain (which `ExportChainBuilder` assembles from records).
//
// **L031 declaration:** this stage performs NO Metal kernel work and makes
// NO new GPU submissions — the ICC transform is CPU-side ColorSync
// (`CGColorConversionInfoConvertData`, T1 probe engine), with the texture
// read/write riding plain `getBytes`/`replace` behind the standard queue
// fence (L014; the `CIContextPool.convertTexture` pattern). `makeRouted
// CommandBuffer()` is untouched.
// ─────────────────────────────────────────────────────────────────────────────

public final class SoftProofStage: IOPModule {

    /// Empty params: the proof CONFIGURATION is per-run coordinator state
    /// (`softProofOverride`), folded into the hash via `stableID` — the
    /// stage is never user-parameterized and never persisted.
    public struct Params: Codable & Hashable, Sendable {
        public init() {}
    }

    /// Non-darktable op (no V50Order entry — the stage is coordinator-
    /// synthetic and must NEVER appear in a sidecar instance set; if a
    /// hand-crafted sidecar ever carries this op, the standard unknown-op
    /// degrade handles it because the registry does not register it).
    public static let opName = "lightamer_softproof"

    /// Upstream of colorout (70.0) by exactly half an iop slot.
    public static let iopOrder: Float = 69.5

    public static let flags: IOPFlags = []

    /// Input IS linear Rec2020 float32 (the pipe interior at this position).
    public static let defaultColorspace: IOPColorspace = .RGB

    /// The OOG round-trip threshold (T1 probe §3.1: in-gamut colors round
    /// trip at ≤1e-4; clipped colors diverge by ≥0.066 — three orders of
    /// magnitude of separation; 1e-3 is the mid guard band).
    public static let oogRoundTripThreshold: Float = 1e-3

    /// Coordinator-injected proof state. nil = identity copy (defensive —
    /// the coordinator removes the box entirely when proof is OFF; a nil
    /// override inside a present box must still pass pixels through
    /// unchanged so no path can double-transform).
    public var softProofOverride: SoftProofProfile?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// The committed hash folds the override's `stableID` — a proof toggle
    /// or profile/intent/BPC/gamut change re-commits to a DIFFERENT hash,
    /// so only the keys at or below this stage flip (SC#2 discipline; the
    /// upstream planes survive). Same fold pattern as colorout's
    /// `DisplayProfile.stableID`.
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        lastCommittedOverride = softProofOverride
        let encoded = ParamsCoding.encode(params)
        var hash = StableHash.hash(encoded)
        if let override = softProofOverride {
            var proofID = override.stableID
            hash = withUnsafeBytes(of: &proofID) { StableHash.combine(hash, $0) }
        }
        piece.paramsHash = hash
    }

    /// Identity ROI (a per-pixel ICC transform resamples nothing).
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity ROI.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let profile = lastCommittedOverride ?? softProofOverride else {
            // Defensive identity: the coordinator removes this box when
            // proof is OFF; this path guarantees byte pass-through even if
            // a box without an override ever enters a chain.
            try await metal.dispatch2DTexture(
                functionName: TerminalKernels.copy, input: input, output: output)
            return
        }
        try await Self.applyProof(
            input: input, output: output, roiOut: roiOut,
            profile: profile, metal: metal)
    }

    /// The committed override (the box commits before the pipe runs the
    /// module — same `lastCommittedParams` discipline as ColorOutModule).
    private var lastCommittedOverride: SoftProofProfile?

    // MARK: - The ColorSync round trip (T1 probe engine)

    /// Proof-transform an ROI region: texture → CPU → forward ICC leg →
    /// backward ICC leg → texture. Pixel-independent, so an ROI window is
    /// exact (no halo, no neighbor dependence — tile-safe).
    ///
    /// Layout contract (T1 probe §1): float32 RGBA, premultiplied-last,
    /// little-endian — the pipe's `.rgba32Float` memory order with alpha=1
    /// (premultiplication by 1 is the identity, so the straight RGB values
    /// pass through the premul semantics untouched).
    static func applyProof(
        input: any MTLTexture,
        output: any MTLTexture,
        roiOut: ROI,
        profile: SoftProofProfile,
        metal: MetalContext
    ) async throws {
        let width = max(roiOut.width, 1)
        let height = max(roiOut.height, 1)
        let rowBytes = width * 16
        let byteCount = rowBytes * height

        // L014: getBytes does not wait for in-flight encoders — the empty
        // committed+waited buffer orders every prior pipe write first
        // (the CIContextPool.convertTexture pattern).
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()

        let source = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { source.deallocate() }
        let midway = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { midway.deallocate() }
        let destination = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { destination.deallocate() }

        input.getBytes(
            source, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(roiOut.x, roiOut.y, width, height), mipmapLevel: 0)

        // Forward leg: working space → printer (relative colorimetric + BPC).
        let forward = try conversionInfo(profile: profile)
        try convert(forward, width: width, height: height, from: source, to: midway)
        // Backward leg: printer → working space — the paper's colors
        // expressed back in linear Rec2020 for the untouched display segment.
        // The return leg keeps relative colorimetric (the paper-white →
        // display-white adaptation is what "shows the paper on screen"
        // means) with the same BPC setting (13-2-DECISIONS).
        let backward = try conversionInfo(profile: profile, backward: true)
        try convert(backward, width: width, height: height, from: midway, to: destination)

        // T3 (gamut check, dt softproof semantics): when armed, any pixel
        // whose proof round trip diverged beyond `oogRoundTripThreshold` —
        // i.e. the printer CANNOT reproduce it — is shown BLACK.
        if profile.gamutCheck {
            Self.blackClipOutOfGamut(source: source, result: destination, pixelCount: width * height)
        }

        output.replace(
            region: MTLRegionMake2D(roiOut.x, roiOut.y, width, height),
            mipmapLevel: 0, withBytes: destination, bytesPerRow: rowBytes)
    }

    /// The gamut-check clip: compare the round-trip result against the
    /// source; a pixel exceeding the threshold in ANY channel is out of the
    /// printer's gamut (the round trip is irreversible there — T1 probe
    /// §3.1) and is rendered BLACK (dt `softproof` gamut-check semantics).
    /// In-gamut pixels keep their proof values (round trip ≤1e-4).
    static func blackClipOutOfGamut(
        source: UnsafeMutableRawPointer, result: UnsafeMutableRawPointer, pixelCount: Int
    ) {
        let src = source.bindMemory(to: Float.self, capacity: pixelCount * 4)
        let dst = result.bindMemory(to: Float.self, capacity: pixelCount * 4)
        for px in 0..<pixelCount {
            let base = px * 4
            var outOfGamut = false
            for c in 0..<3 where abs(dst[base + c] - src[base + c]) > oogRoundTripThreshold {
                outOfGamut = true
                break
            }
            if outOfGamut {
                dst[base] = 0
                dst[base + 1] = 0
                dst[base + 2] = 0
                dst[base + 3] = 1
            }
        }
    }

    /// The `CGColorConversionInfo` for one leg. v1 = the default rendering
    /// intent + the BPC option (the Swift-reachable constructor; T1 probe
    /// §1 — `CreateFromList`'s per-leg intents are C-varargs only).
    static func conversionInfo(
        profile: SoftProofProfile, backward: Bool = false
    ) throws -> CGColorConversionInfo {
        let src = backward ? profile.printerSpace : WorkingSpace.colorSpace
        let dst = backward ? WorkingSpace.colorSpace : profile.printerSpace
        let options = [
            CGColor.conversionBlackPointCompensation: profile.blackPointCompensation
        ] as CFDictionary
        guard let info = CGColorConversionInfo(optionsSrc: src, dst: dst, options: options) else {
            throw AppError.invalidParameter(
                "SoftProofStage: CGColorConversionInfo unavailable for '\(profile.label)'"
                    + (backward ? " (backward leg)" : ""))
        }
        return info
    }

    /// One ColorSync data pass (premulLast + 32Little — the only float
    /// layout the API accepts, T1 probe §1).
    static func convert(
        _ info: CGColorConversionInfo, width: Int, height: Int,
        from source: UnsafeMutableRawPointer, to destination: UnsafeMutableRawPointer
    ) throws {
        var format = CGColorBufferFormat()
        format.version = 0
        format.bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
                | CGBitmapInfo.floatComponents.rawValue)
        format.bitsPerComponent = 32
        format.bitsPerPixel = 128
        format.bytesPerRow = width * 16
        guard info.convert(
            width: width, height: height, to: destination, format: format,
            from: source, format: format, options: nil)
        else {
            throw AppError.invalidParameter(
                "SoftProofStage: ColorSync data conversion failed")
        }
    }
}
