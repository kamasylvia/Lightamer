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
// Params v2 (M3-4-01 T1, KD-1) = the two pull-backs (STOPS, ≥ 0) + the
// roll-off order m ([1, 8], default 2) + the RESOLVED knees (additive
// optionals — RFC-023 §8.3's wire discipline: the wire carries resolved
// K/H, never the pull-backs alone, so changing the paper/descriptor can
// never silently move an existing edit). The knees are solved by the App
// resolver at parameter-commit time (the §9.2 exact landing: the scene
// extreme lands N stops from ITS OWN position, t = a ∓ N — M3-4-01
// replaced the M3-3 simplified arm t = C ∓ N, whose descriptor-absent
// anchors put the root in the deep-tangency regime; the m=1 closed form
// / m≥2 bracketed bisection+Newton double-write carries over verbatim).
// A v1 archive (nil knees): zero pull-backs = the exact identity;
// NON-zero pull-backs = the typed degrade to the default identity (the
// M3-3 corpus never carries one — the edit face did not ship; DECISIONS).
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
        // ── Params v2 (M3-4-01 T1, KD-1): the resolved knees. Additive
        // optionals — v1 archives decode with all four nil (byte-identical
        // wire for the zero pull-backs). All four present TOGETHER or all
        // nil (the resolver writes them as one unit; `hasResolvedKnees`).
        /// Shadow knee K_s, stops relative to mid-gray.
        public var kShadow: Double?
        /// Shadow room H_s (K_s → C_s), stops.
        public var hShadow: Double?
        /// Highlight knee K_h, stops relative to mid-gray.
        public var kHighlight: Double?
        /// Highlight room H_h (C_h → K_h), stops.
        public var hHighlight: Double?

        public init(
            shadowsPullBack: Float = 0, highlightsPullBack: Float = 0, rolloff: Float = 2,
            kShadow: Double? = nil, hShadow: Double? = nil,
            kHighlight: Double? = nil, hHighlight: Double? = nil
        ) {
            self.shadowsPullBack = shadowsPullBack
            self.highlightsPullBack = highlightsPullBack
            self.rolloff = rolloff
            self.kShadow = kShadow
            self.hShadow = hShadow
            self.kHighlight = kHighlight
            self.hHighlight = hHighlight
        }

        private enum CodingKeys: String, CodingKey {
            case shadowsPullBack = "shadows_pull_back"
            case highlightsPullBack = "highlights_pull_back"
            case rolloff
            case kShadow = "k_shadow"
            case hShadow = "h_shadow"
            case kHighlight = "k_highlight"
            case hHighlight = "h_highlight"
        }

        /// The v2 gate: all four resolved knees present (the resolver
        /// writes them as one unit; nil = a v1 archive face).
        public var hasResolvedKnees: Bool {
            kShadow != nil && hShadow != nil && kHighlight != nil && hHighlight != nil
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
    /// meaningless — the branches PUSH the extremes out; the panel owns the
    /// finer RFC-023 §9.2 validity UX). The RESOLVED KNEES RIDE THROUGH —
    /// they are wire state, not clamped inputs (M3-4-01 KD-1).
    public static func clamped(_ params: Params) -> Params {
        Params(
            shadowsPullBack: max(params.shadowsPullBack, 0),
            highlightsPullBack: max(params.highlightsPullBack, 0),
            rolloff: min(max(params.rolloff, rolloffRange.lowerBound), rolloffRange.upperBound),
            kShadow: params.kShadow, hShadow: params.hShadow,
            kHighlight: params.kHighlight, hHighlight: params.hHighlight)
    }

    // MARK: - The fallback anchors (DECISIONS-registered)

    /// Scene-extreme anchors, stops relative to mid-gray. M3-4-01 demoted
    /// these to the NO-FILM fallback face (the M3-3 constants, kept for the
    /// resolver's fallback arm + the golden anchors — the production
    /// anchors are the film stats' P99.9/P0.1 and the descriptor's
    /// useful EV pair, injected at the solve site).
    public static let sceneTopEV = 7.0
    public static let sceneBottomEV = -7.5
    /// Medium-boundary fallback anchors (the descriptor-absent C face).
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

    /// The per-side domain-guard floor: the landing must leave a positive
    /// room at the root, so a demand landing within this distance of the
    /// medium boundary is the typed invalid-demand face (§9.2 rule 1).
    public static let landingRoomFloor = 1e-3

    /// Solve (K, H) for one side from the pull-back N. LANDING SEMANTICS
    /// (M3-4-01 exact form, RFC-023 §9.2): the extreme lands N stops from
    /// ITS OWN position — t = a − N (highlights) / a + N (shadows) — so the
    /// pull-back reads directly off the scene (the M3-3 simplified arm
    /// t = C ∓ N landed the extreme at a distance from the boundary that
    /// ignored where the scene actually ended; its descriptor-absent
    /// anchors put the m≥2 root in a deep-tangency regime — the registered
    /// M3-3-03 defect). Validity: nothing may land beyond the boundary
    /// (§9.2 rule 1: highlights N ≥ a − C ⟹ t ≤ C; shadows N ≥ C − a ⟹
    /// t ≥ C), guarded at `landingRoomFloor` — violated demands answer
    /// NIL (the typed invalid-demand face; the caller names the slider).
    ///
    /// The knee solves K + σ·g_m(a−K; C−K) = t (σ = +1 highlights with
    /// f = K + g / −1 shadows with f = K − g). m=1: the closed form
    /// K = t ∓ √((t−a)(t−c)) — MINUS highlights / PLUS shadows (the
    /// branch-direction sign; the REJECTED root sits on the far side of C
    /// with a NEGATIVE room — pinned by the golden). m ≥ 2: F(K) is
    /// strictly INCREASING with the root's slope bounded away from zero
    /// (F'(K) = 1 − (1+w)^−(m+1)/m·(1 + w^((m+1)/m)) > 0 — exact-form
    /// roots: 0.3188/0.1672/0.0869/0.0447 for highlights m=1/2/4/8,
    /// 0.3493/0.1873 for shadows m=1/2 at the §6.1 anchors), so the
    /// bracketed bisection cannot fail and the fixed Newton polish
    /// converges in two or three steps (RFC-023 §9.2's prescribed shape).
    /// Deterministic: fixed iteration counts, no adaptive stepping.
    @discardableResult
    public static func solveKnee(
        pullBack: Double, rolloff m: Double, sceneExtreme a: Double, mediumBoundary c: Double
    ) -> KneeSolution? {
        guard pullBack > 0 else {
            return KneeSolution(active: false, knee: a, room: abs(c - a))
        }
        let negativeSide = a < 0   // shadows: the landing moves TOWARD mid
        // The exact landing: N stops from the scene extreme ITSELF.
        let t = negativeSide ? a + pullBack : a - pullBack
        // §9.2 rule 1's domain guard (the typed invalid-demand face):
        // highlights t ≤ C − floor / shadows t ≥ C + floor.
        let beyond = negativeSide ? (t < c + landingRoomFloor) : (t > c - landingRoomFloor)
        if beyond { return nil }
        // m=1 closed form (also the Newton seed for m ≥ 2). The SIGN is
        // side-dependent: the m=1 landing equation K ∓ g(K−a; K−C) = t
        // solves to K = t ± √((t−a)(t−c)) — MINUS on the highlights
        // (f = K + g) and PLUS on the shadows (f = K − g). The rejected
        // root sits across C with a negative room (H = C − K < 0) — the
        // physical-domain selection is this sign, and the golden pins the
        // rejected root's negative room as evidence.
        let s = ((a - t) * (c - t)).squareRoot()
        var knee = negativeSide ? t + s : t - s
        if m > 1 {
            // F(K) = K + σ·g_m(|a−K|; |C−K|) − t is strictly increasing
            // with the root slope bounded away from zero (exact form —
            // see the doc comment), so the 40-halving bisection is the
            // convergence workhorse and each of the 4 polish steps is
            // accepted ONLY inside the live bracket and only when it
            // improves |F| (fixed iteration counts, FSIM-01b posture).
            let shadow = negativeSide
            var lo = shadow ? c : -(abs(a) + abs(c) + pullBack + 10.0)
            var hi = shadow ? (abs(a) + abs(c) + pullBack + 10.0) : c
            // Deterministic bracket expansion (the deep-knee face): at high
            // m the branch engages slowly (the C^m contact), so the root can
            // sit far beyond the naive bound (m=8/N=8 at the §6.1 anchors
            // solves near K≈−60). F is strictly increasing, so walk the
            // loose end until the signs bracket — a pure function of the
            // inputs (bit-deterministic; fixed growth, no early exit).
            if !shadow {
                while residual(a: a, c: c, t: t, knee: lo, m: m) >= 0 {
                    lo -= max(16.0, abs(lo) * 0.5)
                }
            } else {
                while residual(a: a, c: c, t: t, knee: hi, m: m) <= 0 {
                    hi += max(16.0, abs(hi) * 0.5)
                }
            }
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

    /// The joint validity face (§9.2 rule 2 — the SINGLE source the App
    /// resolver consumes; `kneeOrderViolation` = the §6.4 fifth-row shape:
    /// the identity core collapsed/negative, the typed refusal names a
    /// pull-back slider — never a silent clamp).
    public enum PlacementValidity: Equatable, Sendable {
        case valid
        case kneeOrderViolation
    }

    public static func validateCoreOrder(
        highlights: KneeSolution, shadows: KneeSolution
    ) -> PlacementValidity {
        shadows.knee < highlights.knee ? .valid : .kneeOrderViolation
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

    /// The per-pixel scalar face (the CPU reference twin — the golden's
    /// dual-drive face): E = log2(powerNorm(rgb)/0.184) (floored), the
    /// branch delta, the gain k. Returns (k, onBranch) — `onBranch ==
    /// false` means the pixel sits in the identity core (k == 1 exactly).
    ///
    /// RESOLVED face (v2): the knees ride the params (RFC-023 §8.3 — the
    /// wire carries resolved K/H; the commit path and this twin consume
    /// the SAME struct, one truth). The v1 face (nil knees): zero
    /// pull-backs = the identity; NON-zero v1 = the typed degrade to the
    /// default identity (M3-4-01 裁决 4 — never a silent re-solve).
    public static func placementGain(
        _ rgb: SIMD3<Double>, params: Params
    ) -> (gain: Double, onBranch: Bool) {
        let clamped = Self.clamped(params)
        guard clamped.hasResolvedKnees,
            let kH = clamped.kHighlight, let hH = clamped.hHighlight,
            let kS = clamped.kShadow, let hS = clamped.hShadow
        else { return (1.0, false) }
        let ss = Double(rgb.x * rgb.x + rgb.y * rgb.y + rgb.z * rgb.z)
        let n = ss > 0
            ? Double(rgb.x * rgb.x * rgb.x + rgb.y * rgb.y * rgb.y + rgb.z * rgb.z * rgb.z) / ss
            : 0
        let e = Foundation.log2(max(n, Double(scalarFloor)) / 0.184)
        if clamped.highlightsPullBack > 0, e > kH {
            let delta = e - kH
            // Highlights compress DOWN: δ = −(Δ − g_m(Δ)) ≤ 0.
            let d = -(delta - smoothMin(delta, hH, Double(clamped.rolloff)))
            return (Foundation.exp2(d), true)
        }
        if clamped.shadowsPullBack > 0, e < kS {
            let delta = kS - e
            // Shadows compress UP: δ = +(Δ − g_m(Δ)) ≥ 0.
            let d = delta - smoothMin(delta, hS, Double(clamped.rolloff))
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
        // The identity faces: no armed branch (the exact identity), or a
        // v1 archive with NON-zero pull-backs (nil knees — the M3-4-01
        // 裁决 4 typed degrade: the resolve happens in the App resolver
        // BEFORE commit; a v1 non-zero archive is degraded to the default
        // identity, never re-solved against hidden anchors).
        guard armed, clamped.hasResolvedKnees,
            let kH = clamped.kHighlight, let hH = clamped.hHighlight,
            let kS = clamped.kShadow, let hS = clamped.hShadow
        else {
            // The identity point: no uniforms — the kernel takes the
            // bit-exact copy path off the flags alone.
            piece.data = nil
            committed = clamped
            return
        }
        // The knees arrive RESOLVED (the App solver's output — RFC-023
        // §9.2: solved once per commit on the CPU, never per pixel; the
        // commit just packs the uniforms, the FilmMethodBox solved-pack
        // shape).
        var u = FilmPlacementUniforms(
            K_h: Float(kH), H_h: Float(max(hH, 1e-6)),
            K_s: Float(kS), H_s: Float(max(hS, 1e-6)),
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
