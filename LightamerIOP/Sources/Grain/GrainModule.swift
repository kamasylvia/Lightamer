import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// GrainModule — Plan 08-2 T2, IOP-FX-02 (op "grain", v50 slot 65.0).
//
// Darktable reference (tree dc58cf0ba1): `src/iop/grain.c` (CPU-only iop).
//
//   - params :65-70,542-543 — THREE sliders verbatim: scale (coarseness;
//     the bauhaus slider multiplies the stored value by GRAIN_SCALE_FACTOR
//     = 213.2 and labels it "ISO" — the `~ISO of the film` semantics is
//     the stored-domain contract, NOT a second parameter — D-08-CONTEXT-6
//     ①: no separate ISO-sensitivity slider), strength (0-100, 25),
//     midtones_bias (0-100). **midtones_bias default 0** per the plan's
//     explicit face (research §14) — dt's current source annotation reads
//     $DEFAULT 100.0; the divergence is recorded (DECISIONS D-08-2-4),
//     the legacy_params migration comment (:77 "it produces the same
//     results as the old version") anchors 0 as the canonical v1 look.
//   - noise  : the 3-octave simplex verbatim (see the .metal header).
//   - seed   : `StableHash(canonicalParamsBytes ⊕ imageIdentity bytes)`
//     (FNV-1a 64 — L013; Swift `Hasher` banned). The imageIdentity
//     carrier = the box INSTANCE UUID (the sidecar-persisted record UUID
//     — paste recasts UUIDs cross-image, restore resurrects them), in-
//     jected at registration (`GrainModule(imageIdentity: id)`). The
//     cache-key invariant holds: PipeCacheKey already contains
//     (imageID, paramsHash) and the seed is their pure function —
//     same key ⇔ same seed within a process (DECISIONS D-08-2-1).
//   - luma injection on linear Rec2020 (the .metal header's domain
//     adaptation).
//
// SEED INSTANCE: DISABLED (dt default strength 25 is not pixel-identity;
// the creative-module disposition). strength 0 (enabled) takes the
// routed-blit value-identity fast path — L031: every GPU submission goes
// through the MetalContext routed acquisition point.
// ─────────────────────────────────────────────────────────────────────────

public enum GrainKernel {
    public static let functionName = "grain_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class GrainModule: IOPModule {

    /// dt GRAIN_SCALE_FACTOR (:44) — the bauhaus display factor: the UI
    /// shows `scale × 213.2` labelled ISO; the STORED param is dt's raw
    /// domain [20/213.2, 6400/213.2].
    public static let grainScaleFactor: Float = 213.2

    /// dt `dt_iop_grain_params_t` v2 (:65-70).
    public struct Params: Codable, Hashable, Sendable {
        /// dt `scale` — coarseness; stored domain
        /// [20/213.2, 6400/213.2], default 1600/213.2 (ISO 1600).
        public var scale: Float
        /// dt `strength` ∈ [0, 100] $DEFAULT 25.
        public var strength: Float
        /// dt `midtones_bias` ∈ [0, 100] — default 0 per the plan face
        /// (DECISIONS D-08-2-4 records the dt-annotation divergence).
        public var midtonesBias: Float

        public init(
            scale: Float = 1600.0 / GrainModule.grainScaleFactor,
            strength: Float = 25.0,
            midtonesBias: Float = 0.0
        ) {
            self.scale = scale
            self.strength = strength
            self.midtonesBias = midtonesBias
        }

        /// The UI-facing ISO readout (`scale × GRAIN_SCALE_FACTOR` — the
        /// dt bauhaus factor semantics, :540).
        public var iso: Double {
            Double(scale) * Double(GrainModule.grainScaleFactor)
        }
    }

    public static let opName = "grain"

    /// Darktable v50 order slot 65.0 — before soften (66.0); < the 70.0
    /// terminal floor → layer-mask eligible.
    public static let iopOrder: Float = 65.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// The pattern-identity carrier (the box instance UUID — see the
    /// header). Tests inject explicit UUIDs for the determinism contract.
    public let imageIdentity: UUID

    /// MSL mirror of `GrainUniforms`.
    struct Uniforms {
        var zoom: Float
        var strength: Float
        var midtonesBias: Float
        var gamma: Float
        var offset: Float
        var invScaleWd: Float
        var filtermul: Float
        var pad0: Float = 0
        var filter: Int32
        var roiX: Int32
        var roiY: Int32
        var pad1: Int32 = 0
    }

    public init(imageIdentity: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) {
        self.imageIdentity = imageIdentity
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committed = params
        piece.data = nil
    }

    private var committed: Params?

    // MARK: - the deterministic seed (research §8.1)

    /// `StableHash(canonicalParamsBytes ⊕ imageIdentity-UUID-bytes)` — the
    /// ONLY legal generator is StableHash (L013). Pure function: the
    /// PipeCacheKey invariant (same key ⇔ same seed) leans on it.
    public static func seed(params: Params, imageIdentity: UUID) -> UInt64 {
        let paramsHash = StableHash.hash(ParamsCoding.encode(params))
        let uuid = imageIdentity.uuid
        return withUnsafeBytes(of: uuid) { bytes in
            StableHash.combine(paramsHash, bytes)
        }
    }

    // MARK: - dt process :447-507 — the domain setup

    /// The Float uniforms the kernel consumes (float64 twins live in
    /// GrainReference). `internal` for the parity tests.
    static func uniforms(
        _ params: Params, seedOffset: Double,
        planeW: Int, planeH: Int, iscale: Float,
        roiIn: ROI, roiOut: ROI
    ) -> Uniforms {
        // dt: wd = min(buf_in dims) in ORIGINAL-image pixels.
        let origW = Double(planeW) / Double(max(iscale, 1e-9))
        let origH = Double(planeH) / Double(max(iscale, 1e-9))
        let wd = min(origW, origH)
        // grain.c:450 — the zoom (the stored scale, ISO/213.2 domain).
        let zoom = (1.0 + 8.0 * Double(params.scale) / 100.0) / 800.0
        // grain.c:484-487 — the lattice-downsampling gate + tap spacing.
        let filter = abs(roiOut.scale - 1.0) > 0.01
        let filtermul = Double(iscale) / (Double(roiOut.scale) * wd)
        let invScaleWd = 1.0 / (Double(roiIn.scale) * wd)
        return Uniforms(
            zoom: Float(zoom),
            strength: params.strength / 100.0,
            midtonesBias: params.midtonesBias,
            gamma: 1.0,
            offset: Float(seedOffset),
            invScaleWd: Float(invScaleWd),
            filtermul: Float(filtermul),
            filter: filter ? 1 : 0,
            roiX: Int32(roiIn.x),
            roiY: Int32(roiIn.y))
    }

    /// The seed → pattern offset quantum (dt's `% (roi.width·0.3)` filename
    /// quantum replaced by a FIXED 4096 for resolution independence —
    /// DECISIONS D-08-2-3).
    public static func seedOffset(seed: UInt64) -> Double {
        Double(seed % 4096)
    }

    // MARK: - ROI (identity — the noise never resamples)

    /// strength 0 ⇒ the delta is exactly zero — the routed-blit value
    /// identity. `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        p.strength == 0
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let params = committed else {
            throw MetalError.psoCreationFailed(GrainKernel.functionName, nil)
        }
        if isNeutral(params) {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let seed = Self.seed(params: params, imageIdentity: imageIdentity)
        var run = Self.uniforms(
            params, seedOffset: Self.seedOffset(seed: seed),
            planeW: piece.dscIn.width, planeH: piece.dscIn.height,
            iscale: piece.iscale, roiIn: roiIn, roiOut: roiOut)
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &run, length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: GrainKernel.functionName)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBuffer(runBuffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// Whole-window routed blit — L031: `makeRoutedCommandBuffer()` is the
    /// ONE queue-acquisition point (the 11-03 cross-queue flake).
    private func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008
        commandBuffer.commit()
    }
}
