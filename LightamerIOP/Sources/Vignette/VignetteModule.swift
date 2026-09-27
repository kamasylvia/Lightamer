import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// VignetteModule — Plan 08-2 T1, IOP-FX-01 (op "vignette", v50 slot 68.0).
//
// Darktable reference (tree dc58cf0ba1): `src/iop/vignette.c` +
// `data/kernels/extended.cl:308-349` (the port master — the OpenCL form,
// cosine smoothing unconditional; research §17.3).
//
//   - params v4  :57-72  scale(0-200,80)/falloff_scale(0-200,50)/
//                        brightness(-1..1,-0.5)/saturation(-1..1,-0.5)/
//                        center ±1/whratio(0-2,1)/shape(0-5,1)/
//                        unbound(true)/autoratio(false) — VERBATIM.
//                        **dithering NOT ported** (D-08-CONTEXT-5 ③: an
//                        8-bit-output patch; the float32 chain's terminal
//                        dither iop owns that job — the dt CPU/OpenCL
//                        cosine divergence rides the same decision, §17.3).
//   - scale setup:719-786 buf dims are dt's ORIGINAL-image dims
//                        (piece->iwidth family): Lightamer recovers them
//                        as dscIn/iscale (L020 — dscIn is entry-scaled;
//                        the denoise radius-compensation precedent). The
//                        rest of the formulas are verbatim in ORIGINAL
//                        pixel space so the vignette is resolution-
//                        independent across the four pipe resolutions.
//   - kernel      : single dispatch, `vignette_apply` (the .metal header
//                        carries the per-pixel math provenance).
//
// SEED: DISABLED (the dt-verbatim defaults brightness −0.5/saturation
// −0.5 are NOT pixel-identity — the highpass/soften creative disposition:
// identity holds via the disabled piece; exposure-0EV style). The
// parameter-neutral VALUE identity (brightness 0 + saturation 0) takes
// the routed-blit fast path below — L031: EVERY GPU submission in this
// module (kernel AND blit) goes through the MetalContext routed
// acquisition point.
// ─────────────────────────────────────────────────────────────────────────

public enum VignetteKernel {
    public static let functionName = "vignette_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class VignetteModule: IOPModule {

    /// dt `dt_iop_vignette_params_t` v4 verbatim (vignette.c:57-72).
    /// dithering deliberately absent — D-08-CONTEXT-5 ③.
    public struct Params: Codable, Hashable, Sendable {
        /// dt `scale` ∈ [0, 200] $DEFAULT 80 — fall-off start (% of the
        /// largest image dimension).
        public var scale: Float
        /// dt `falloff_scale` ∈ [0, 200] $DEFAULT 50 — fall-off radius.
        public var falloffScale: Float
        /// dt `brightness` ∈ [-1, 1] $DEFAULT −0.5 — strength of the
        /// brightness reduction.
        public var brightness: Float
        /// dt `saturation` ∈ [-1, 1] $DEFAULT −0.5 — strength of the
        /// saturation reduction.
        public var saturation: Float
        /// dt `center.x` ∈ [-1, 1] $DEFAULT 0 — horizontal center.
        public var centerX: Float
        /// dt `center.y` ∈ [-1, 1] $DEFAULT 0 — vertical center.
        public var centerY: Float
        /// dt `autoratio` $DEFAULT false — w/h ratio follows the piece
        /// dimensions.
        public var autoratio: Bool
        /// dt `whratio` ∈ [0, 2] $DEFAULT 1 — width/height ratio (1-2
        /// interprets as h/w + 1, dt gui note verbatim).
        public var whratio: Float
        /// dt `shape` ∈ [0, 5] $DEFAULT 1 — the falloff shape exponent.
        public var shape: Float
        /// dt `unbound` $DEFAULT TRUE — whether the values are clipped.
        public var unbound: Bool

        public init(
            scale: Float = 80.0,
            falloffScale: Float = 50.0,
            brightness: Float = -0.5,
            saturation: Float = -0.5,
            centerX: Float = 0.0,
            centerY: Float = 0.0,
            autoratio: Bool = false,
            whratio: Float = 1.0,
            shape: Float = 1.0,
            unbound: Bool = true
        ) {
            self.scale = scale
            self.falloffScale = falloffScale
            self.brightness = brightness
            self.saturation = saturation
            self.centerX = centerX
            self.centerY = centerY
            self.autoratio = autoratio
            self.whratio = whratio
            self.shape = shape
            self.unbound = unbound
        }
    }

    public static let opName = "vignette"

    /// Darktable v50 order slot 68.0 — creative tail, BEFORE the 70.0
    /// terminal floor (`LayerCompositeDriver.terminalTailFloor`) → the
    /// layer-mask eligibility holds (Phase 7 layer stack API, zero new
    /// mechanism).
    public static let iopOrder: Float = 68.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// MSL mirror of `VignetteUniforms` (12 floats — the .metal struct).
    /// Narrowed from the float64 `uniformSetup` output — the formula has
    /// ONE source of truth.
    struct Uniforms {
        var xscale: Float
        var yscale: Float
        var roiCenterScaledX: Float
        var roiCenterScaledY: Float
        var exp1: Float
        var exp2: Float
        var dscale: Float
        var fscale: Float
        var brightness: Float
        var saturation: Float
        var unbound: Float
        var pad0: Float = 0

        init(_ d: VignetteReference.Uniforms) {
            xscale = Float(d.xscale)
            yscale = Float(d.yscale)
            roiCenterScaledX = Float(d.roiCenterScaledX)
            roiCenterScaledY = Float(d.roiCenterScaledY)
            exp1 = Float(d.exp1)
            exp2 = Float(d.exp2)
            dscale = Float(d.dscale)
            fscale = Float(d.fscale)
            brightness = Float(d.brightness)
            saturation = Float(d.saturation)
            unbound = d.unbound ? 1.0 : 0.0
        }
    }

    // The uniforms are pure (params, roi-geometry) functions — computed
    // per run into a fresh shared buffer (the soften per-run-uniforms
    // shape); no committed uniforms buffer to keep alive. `committed` is
    // the box-owned param snapshot (the soften read-at-process precedent).
    private var committed: Params?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committed = params
        piece.data = nil
    }

    // MARK: - dt process :719-786 — the scale setup (uniforms)

    /// The dt scale setup, verbatim in ORIGINAL-image pixel space. `bufW`/
    /// `bufH` are the ORIGINAL dims (dt `buf_in->width` = the iwidth
    /// family); Lightamer passes `piece.dscIn.width / piece.iscale`.
    /// Returns the FLOAT64 setup — the reference's own input type — so the
    /// formula has ONE source of truth; the Float narrowing for the kernel
    /// rides `Uniforms.init(_:)`. `internal` for the parity tests.
    static func uniformSetup(
        _ params: Params, bufW: Double, bufH: Double,
        roiIn: ROI, roiOut: ROI
    ) -> VignetteReference.Uniforms {
        // vignette.c:722-729 — the centers (original px).
        let bufCenterX = bufW * 0.5
        let bufCenterY = bufH * 0.5
        let vignetteCenterX = bufCenterX + Double(params.centerX) * bufW / 2.0
        let vignetteCenterY = bufCenterY + Double(params.centerY) * bufH / 2.0
        // vignette.c:731-734 — the roi translation (buffer px).
        let roiCenterX = vignetteCenterX * Double(roiIn.scale) - Double(roiIn.x)
        let roiCenterY = vignetteCenterY * Double(roiIn.scale) - Double(roiIn.y)

        let xscale: Double
        let yscale: Double
        // vignette.c:736-758 — the w/h ratio legs.
        if params.autoratio {
            xscale = 2.0 / (bufW * Double(roiOut.scale))
            yscale = 2.0 / (bufH * Double(roiOut.scale))
        } else {
            let basis = 2.0 / (max(bufH, bufW) * Double(roiOut.scale))
            // w/h ratio 0-1 used as-is; 1-2 interprets as h/w + 1.
            if params.whratio <= 1.0 {
                yscale = basis
                xscale = yscale / Double(params.whratio)
            } else {
                xscale = basis
                yscale = xscale / (2.0 - Double(params.whratio))
            }
        }
        // vignette.c:759-763 — dscale + the aliasing-smoothing minimum
        // falloff (original-px domain).
        let dscale = Double(params.scale) / 100.0
        let minFalloff = 100.0 / min(bufW, bufH)
        let fscale = max(Double(params.falloffScale), minFalloff) / 100.0
        // vignette.c:764-766 — the shape exponents.
        let shape = max(Double(params.shape), 0.001)
        let exp1 = 2.0 / shape
        let exp2 = shape / 2.0
        // vignette.c:768-771 — the pre-scaled center.
        return VignetteReference.Uniforms(
            xscale: xscale, yscale: yscale,
            roiCenterScaledX: roiCenterX * xscale,
            roiCenterScaledY: roiCenterY * yscale,
            exp1: exp1, exp2: exp2,
            dscale: dscale, fscale: fscale,
            brightness: Double(params.brightness),
            saturation: Double(params.saturation),
            unbound: params.unbound)
    }

    // MARK: - Neutral predicate + process

    /// brightness 0 + saturation 0 ⇒ the kernel adds/multiplies NOTHING —
    /// the routed-blit value identity (the soften amount-0 shape). The
    /// SEED instance is DISABLED (see the header) — this predicate is the
    /// enabled-instance fast path.
    /// `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        p.brightness == 0 && p.saturation == 0
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
            throw MetalError.psoCreationFailed(VignetteKernel.functionName, nil)
        }
        if isNeutral(params) {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        // Stamp the per-run geometry legs into a fresh shared buffer
        // (float64 setup → Float narrowing — soften's per-run-uniforms
        // shape; never mutate a committed buffer mid-run).
        let setup = Self.uniformSetup(
            params,
            bufW: Double(piece.dscIn.width) / Double(max(piece.iscale, 1e-9)),
            bufH: Double(piece.dscIn.height) / Double(max(piece.iscale, 1e-9)),
            roiIn: roiIn, roiOut: roiOut)
        var run = Uniforms(setup)
        guard let runBuffer = metal.device.makeBuffer(
            bytes: &run, length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: VignetteKernel.functionName)
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

    /// Whole-window routed blit (dt `copy_image_roi` fast path). L031: the
    /// command buffer comes from `makeRoutedCommandBuffer()` — the ONE
    /// queue-acquisition point; a hardwired editor-queue blit races the
    /// export-chain compute cross-queue (the 11-03 flake).
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
        blit.endEncoding() // L008: encode close precedes commit, never defer
        commandBuffer.commit()
    }
}
