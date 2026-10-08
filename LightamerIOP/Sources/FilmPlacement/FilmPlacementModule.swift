import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// FilmPlacementModule (Plan M3-3-02 T4, KD-5) — the `filmPlacement` grade
// op (M3-2 OQ-M3-2-7 ①: RFC-023 semantics, NOT an exposure/contrast
// approximation). Scene placement in the print sense: the subject's
// exposure stays put, and the two pull-backs drag the scene's extremes
// back toward the medium — an EXACT identity core between two knees with
// smooth-min compression branches (RFC-023 §5.4, formula-level
// transcription; zero GPL code).
//
// Params = the two pull-backs (STOPS, ≥ 0) + the roll-off order m ([1, 8],
// default 2 — the lowest order with no curvature step at the knee, §5.5).
// The knees K and the rooms H are DERIVED on the CPU at commit time
// (RFC-023 §9.2: never typed), from fixed descriptor-absent anchors — the
// plan's simplified arm (the descriptor/histogram solve is M3-4 FSIM-02;
// DECISIONS registers the anchors + the m=1 closed form / m≥2
// bisection+Newton double-write).
//
// DOMAIN: ACEScc in/out (the op sits at v50 20.8, INSIDE the [20.5, 69.9]
// grade envelope — the layer sub-run wraps it; the curve math decodes to
// scene-linear, computes the scalar gain, re-encodes — the log₂ touches
// only the gain, the signal never becomes log).
//
// IDENTITY: both pull-backs zero = the early-exit copy — BIT-EXACT (the
// kernel no-op point; the GradeCatalog identityJSON pins it). The delta
// form (δ = ±(Δ − g_m(Δ)), k = exp2(δ)) keeps the core pixels untouched
// even when a branch is armed (the kernel returns the RAW pixel there).
// ─────────────────────────────────────────────────────────────────────────

public enum FilmPlacementKernel {
    /// MSL function name (`FilmPlacementKernels.metal`).
    public static let functionName = "film_placement"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class FilmPlacementModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Shadow pull-back, STOPS (≥ 0, default 0 = the shadow branch is
        /// OFF — the exact identity, RFC-023 §9.3's degenerate case).
        public var shadowsPullBack: Float
        /// Highlight pull-back, STOPS (≥ 0, default 0 = branch off).
        public var highlightsPullBack: Float
        /// Roll-off order m, [1, 8], default 2 (§5.5: the lowest order
        /// that removes the curvature step; m=1 keeps the corner).
        public var rolloff: Float

        public init(
            shadowsPullBack: Float = 0, highlightsPullBack: Float = 0, rolloff: Float = 2
        ) {
            self.shadowsPullBack = shadowsPullBack
            self.highlightsPullBack = highlightsPullBack
            self.rolloff = rolloff
        }

        private enum CodingKeys: String, CodingKey {
            case shadowsPullBack = "shadows_pull_back"
            case highlightsPullBack = "highlights_pull_back"
            case rolloff
        }
    }

    public static let rolloffRange: ClosedRange<Float> = (1.0...8.0)

    public static let opName = "filmPlacement"

    /// LIGHTAMER V50Order row 20.8 (KD-5): between acesccIn (20.5) and
    /// exposure (21.0) — "Scene Placement is the first mapping" (RFC-023):
    /// camera WB/temp 3.0 runs in the RAW domain first; the grade-domain
    /// placement sits at the envelope's very front, below every other
    /// catalog op. Add-only native row (the skinSmooth 66.5 discipline).
    public static let iopOrder: Float = 20.8

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// The module's clamp face (the ContrastModule pattern): rolloff into
    /// [1, 8]; pull-backs clamped non-negative (negative pull-back is
    /// meaningless — the branches PUSH the extremes out; the M3-4 panel
    /// owns the finer RFC-023 §9.2 validity UX).
    public static func clamped(_ params: Params) -> Params {
        Params(
            shadowsPullBack: max(params.shadowsPullBack, 0),
            highlightsPullBack: max(params.highlightsPullBack, 0),
            rolloff: min(max(params.rolloff, rolloffRange.lowerBound), rolloffRange.upperBound))
    }

    // MARK: - The simplified-arm anchors (DECISIONS-registered)

    /// Scene-extreme anchors, stops relative to mid-gray (the fixed stand-in
    /// for the descriptor's measured P99.9/P0.1 — M3-4 replaces with the
    /// real histogram read; the INTERACTION SEMANTICS are final).
    public static let sceneTopEV = 7.0
    public static let sceneBottomEV = -7.5
    /// Medium-boundary anchors (where the paper's white/black sit on the
    /// same axis — the descriptor's C face).
    public static let mediumTopEV = 4.0
    public static let mediumBottomEV = -4.5

    /// The n_ref · 2^−24 floor (RFC-023 §5.8's domain guard).
    public static let scalarFloor = Float(0.184 * Foundation.pow(2.0, -24.0))

    // MARK: - The CPU knee solve (§9.2 — once per commit, never per pixel)

    /// The solved geometry for one side: knee + room. `active == false` for
    /// a zero pull-back (the branch is the exact identity, §9.3).
    public struct KneeSolution: Equatable, Sendable {
        public let active: Bool
        public let knee: Double
        public let room: Double
    }

    /// Solve (K, H) for one side from the pull-back N. LANDING SEMANTICS
    /// (the simplified arm; DECISIONS-registered): the extreme lands N
    /// stops INSIDE the medium boundary — t = C − N (highlights) / C + N
    /// (shadows) — because the branch asymptote is the boundary itself
    /// (f(a) = K + g_m(a−K; C−K) ≤ K + H = C always, so a "drag down by N
    /// from the scene top" landing needs the measured scene extreme; the
    /// descriptor arm restores the exact §9.2 form in M3-4). The knee
    /// solves K + σ·g_m(a−K; C−K) = t — the m=1 closed form
    /// K = t ∓ √((a−t)(C−t)) (§9.2; MINUS highlights / PLUS shadows —
    /// the branch-direction sign) for m == 1, the bracketed bisection +
    /// fixed Newton polish for m ≥ 2 (deterministic: fixed iteration
    /// counts, no adaptive stepping — the FSIM-01b posture).
    public static func solveKnee(
        pullBack: Double, rolloff m: Double, sceneExtreme a: Double, mediumBoundary c: Double
    ) -> KneeSolution {
        guard pullBack > 0 else {
            return KneeSolution(active: false, knee: a, room: abs(c - a))
        }
        let negativeSide = a < 0   // shadows: the landing moves TOWARD mid
        let t = negativeSide ? c + pullBack : c - pullBack
        // m=1 closed form (also the Newton seed for m ≥ 2). The SIGN is
        // side-dependent: the m=1 landing equation K ∓ g(K−a; K−C) = t
        // solves to K = t ± √((t−a)(t−c)) — MINUS on the highlights
        // (f = K + g) and PLUS on the shadows (f = K − g; expanding
        // (K−a)(K−c) = (K−t)(2K−a−c) gives u = t ± √((t−a)(t−c)) with the
        // sign following the branch's direction). (The golden batch's
        // independent derivation — M3-3-03; the shared `s` term is the
        // symmetric part, only the sign flips.)
        let s = ((a - t) * (c - t)).squareRoot()
        var knee = negativeSide ? t + s : t - s
        if m > 1 {
            // F(K) = K + σ·g_m(|a−K|; |C−K|) − t (σ = +1 highlights / −1
            // shadows) is strictly decreasing in K on BOTH sides with the
            // landing root a TANGENCY (F' → 0 there — the C^m contact), so
            // a bare Newton diverges. Safeguarded Newton: each of the 4
            // polish steps is accepted ONLY inside the live bracket and
            // only when it improves |F|; otherwise the ladder bisects (the
            // 40-halving bisection is the convergence workhorse — fixed
            // iteration counts, no adaptive stepping, FSIM-01b posture).
            let shadow = negativeSide
            var lo = shadow ? c : -(abs(a) + abs(c) + pullBack + 10.0)
            var hi = shadow ? (abs(a) + abs(c) + pullBack + 10.0) : c
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if residual(a: a, c: c, t: t, knee: mid, m: m) < 0 { lo = mid } else { hi = mid }
            }
            knee = (lo + hi) / 2
            for _ in 0..<4 {
                let r = residual(a: a, c: c, t: t, knee: knee, m: m)
                let d = residualDerivative(a: a, c: c, knee: knee, m: m)
                var next = d != 0 ? knee - r / d : knee
                if next <= lo || next >= hi {
                    next = (lo + hi) / 2   // fell outside: bisect instead
                }
                let nr = residual(a: a, c: c, t: t, knee: next, m: m)
                if abs(nr) <= abs(r) {
                    knee = next
                    if nr < 0 { lo = next } else { hi = next }
                } else {
                    knee = (lo + hi) / 2
                    if residual(a: a, c: c, t: t, knee: knee, m: m) < 0 { lo = knee } else { hi = knee }
                }
            }
        }
        return KneeSolution(active: true, knee: knee, room: abs(c - knee))
    }

    /// F(K) = K + σ·g_m(|a−K|; |C−K|) − t with σ = +1 highlights (the
    /// branch ABOVE the knee, f = K + g) / −1 shadows (f = K − g) —
    /// Float64 channel math.
    static func residual(a: Double, c: Double, t: Double, knee: Double, m: Double) -> Double {
        let delta = abs(a - knee)
        let room = abs(c - knee)
        let sign: Double = knee < c ? 1 : -1
        return knee + sign * smoothMin(delta, room, m) - t
    }

    /// F'(K) = 1 − (∂g/∂Δ + ∂g/∂H) — side-INDEPENDENT (the σ sign and the
    /// dΔ/dK / dH/dK signs cancel): the §5.4 pair
    /// g'_Δ = (1+w)^(−(m+1)/m), g'_H = (Δ/H)^(m+1)·(1+w)^(−(m+1)/m).
    static func residualDerivative(a: Double, c: Double, knee: Double, m: Double) -> Double {
        let delta = max(abs(a - knee), 1e-12)
        let room = max(abs(c - knee), 1e-12)
        let w = Foundation.pow(delta / room, m)
        let base = Foundation.pow(1 + w, -(m + 1) / m)
        let dgDDelta = base
        let dgDRoom = Foundation.pow(delta / room, m + 1) * base
        return 1 - (dgDDelta + dgDRoom)
    }

    /// The smooth-min family g_m(Δ) = Δ(1+(Δ/H)^m)^(−1/m) (Float64 —
    /// the kernel's pow-based branch, double-written).
    public static func smoothMin(_ delta: Double, _ room: Double, _ m: Double) -> Double {
        guard delta > 0, room > 0 else { return 0 }
        let w = Foundation.pow(delta / room, m)
        return delta * Foundation.pow(1 + w, -1 / m)
    }

    // MARK: - The scalar placement function (the CPU reference twin —
    // the M3-3-03 golden gate consumes the Float64 face)

    /// The per-pixel scalar face: E = log2(powerNorm(rgb)/0.184) (floored),
    /// the branch delta, the gain k. Returns (k, onBranch) — `onBranch ==
    /// false` means the pixel sits in the identity core (k == 1 exactly).
    public static func placementGain(
        _ rgb: SIMD3<Double>, params: Params
    ) -> (gain: Double, onBranch: Bool) {
        let clamped = Self.clamped(params)
        let ss = Double(rgb.x * rgb.x + rgb.y * rgb.y + rgb.z * rgb.z)
        let n = ss > 0
            ? Double(rgb.x * rgb.x * rgb.x + rgb.y * rgb.y * rgb.y + rgb.z * rgb.z * rgb.z) / ss
            : 0
        let e = Foundation.log2(max(n, Double(scalarFloor)) / 0.184)
        let hi = solveKnee(
            pullBack: Double(clamped.highlightsPullBack), rolloff: Double(clamped.rolloff),
            sceneExtreme: sceneTopEV, mediumBoundary: mediumTopEV)
        let lo = solveKnee(
            pullBack: Double(clamped.shadowsPullBack), rolloff: Double(clamped.rolloff),
            sceneExtreme: sceneBottomEV, mediumBoundary: mediumBottomEV)
        if hi.active, e > hi.knee {
            let delta = e - hi.knee
            // Highlights compress DOWN: δ = −(Δ − g_m(Δ)) ≤ 0.
            let d = -(delta - smoothMin(delta, hi.room, Double(clamped.rolloff)))
            return (Foundation.exp2(d), true)
        }
        if lo.active, e < lo.knee {
            let delta = lo.knee - e
            // Shadows compress UP: δ = +(Δ − g_m(Δ)) ≥ 0.
            let d = delta - smoothMin(delta, lo.room, Double(clamped.rolloff))
            return (Foundation.exp2(d), true)
        }
        return (1.0, false)
    }

    // MARK: - IOPModule

    private let device: (any MTLDevice)?
    private var uniformsBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        let clamped = Self.clamped(params)
        let armed = clamped.shadowsPullBack > 0 || clamped.highlightsPullBack > 0
        guard armed else {
            // The identity point: no uniforms — the kernel takes the
            // bit-exact copy path off the flags alone.
            piece.data = nil
            committed = clamped
            return
        }
        // The knees solve ONCE here (CPU, Float64) — never per pixel.
        let hi = Self.solveKnee(
            pullBack: Double(clamped.highlightsPullBack), rolloff: Double(clamped.rolloff),
            sceneExtreme: Self.sceneTopEV, mediumBoundary: Self.mediumTopEV)
        let lo = Self.solveKnee(
            pullBack: Double(clamped.shadowsPullBack), rolloff: Double(clamped.rolloff),
            sceneExtreme: Self.sceneBottomEV, mediumBoundary: Self.mediumBottomEV)
        var u = FilmPlacementUniforms(
            K_h: Float(hi.knee), H_h: Float(max(hi.room, 1e-6)),
            K_s: Float(lo.knee), H_s: Float(max(lo.room, 1e-6)),
            m: clamped.rolloff,
            flagHi: clamped.highlightsPullBack > 0 ? 1 : 0,
            flagLo: clamped.shadowsPullBack > 0 ? 1 : 0,
            nFloor: Self.scalarFloor)
        if uniformsBuffer == nil || committed != clamped {
            let resolved = device ?? MTLCreateSystemDefaultDevice()
            uniformsBuffer = resolved?.makeBuffer(
                length: MemoryLayout<FilmPlacementUniforms>.stride,
                options: .storageModeShared)
            committed = clamped
        }
        guard let buffer = uniformsBuffer else {
            piece.data = nil
            return
        }
        withUnsafeBytes(of: &u) {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: MemoryLayout<FilmPlacementUniforms>.stride)
        }
        piece.data = buffer
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let buffer = piece.data else {
            // The identity point: a routed blit copy (bit-exact — the
            // GradeCatalog identityJSON's kernel no-op contract).
            guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder()
            else {
                throw MetalError.deviceUnavailable
            }
            blit.copy(
                from: input, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: input.width, height: input.height, depth: 1),
                to: output, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()  // L008
            commandBuffer.commit()
            return
        }
        try await metal.dispatch2DTexture(
            functionName: FilmPlacementKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }
}

/// The MSL uniform mirror (16-byte stride alignment: 8 floats).
struct FilmPlacementUniforms {
    var K_h: Float
    var H_h: Float
    var K_s: Float
    var H_s: Float
    var m: Float
    var flagHi: Float
    var flagLo: Float
    var nFloor: Float
}
