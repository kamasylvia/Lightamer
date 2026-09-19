import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// SIGMOID — scene-referred log-logistic tone mapping (Plan 03-04-T3/T4,
// IOP-FILM-02). D-T2's sigmoid-first baseline: the panel/cache/golden
// template filmicrgb (plan 03-06) builds on.
//
// Darktable reference: `src/iop/sigmoid.c` (tree dc58cf0ba1, 982 lines)
//   - params v3      :57-73   contrast/skew/white/black + color_processing
//                              + hue_preservation + inset/rotation ×3 +
//                              purity + base_primaries
//   - commit_params  :318-407 → SigmoidDerivation (four scalars, Double)
//   - per_channel    :703-761  (kernel mirror: SigmoidKernels.metal)
//   - rgb_ratio      :566-654  (kernel mirror)
//   - primaries      :394-468  `_calculate_adjusted_primaries` (below)
//
// INPUT SEMANTICS: linear Rec2020 SCENE RGB (values > 1.0 legal; negatives
// defined through the desaturation step). This is the first scene-referred
// module in the pipe — display_white/black_target are OUTPUT-side params
// and ship with dt's defaults (SigmoidDerivation header carries the
// middle-grey-on-displayed-domain calibration caveat).
//
// PRIMARIES (dt sigmoid.c:394-468, AgX-lineage inset/rotation): the
// custom primaries are derived from the BASE profile's xy primaries +
// whitepoint via dt_rotate_and_scale_primary (custom_primaries.c:76-96)
// and the Lindbloom primaries→matrix builder
// (colorspaces.c:2571-2600); matrices chain:
//   pipe_to_base      = work RGB → base RGB   (identity when base == work —
//                       dt's pointer-equality branch, sigmoid.c:423-442)
//   base_to_rendering = base RGB → rendering (custom₁) RGB
//                       = M_out(custom₁) · M_in(base)
//   rendering_to_pipe = M_out(work)·M_in(base) · (M_out(custom₂)·M_in(base))⁻¹
//   (custom₁ = inset/rotation primaries; custom₂ additionally purity-
//   folded — sigmoid.c:445-467 structure).
//   DEVIATION (recorded): dt composes these through the transposed
//   dt_colormatrix storage whose product order (sigmoid.c:453/:464-466)
//   reads inverted against the applied-matrix direction chain; we
//   implement the documented direction semantics, which coincides with
//   dt EXACTLY on the default path (base == work, zero inset/rotation →
//   all three matrices ≈ identity) and on the base_to_pipe leg. The
//   golden per-channel case pins the default path; the nonzero-inset
//   path is pinned by the Swift↔Python dual implementation, NOT against
//   dt (the dt-side ambiguity is logged for the Phase 5 re-read).
//
// GOLDEN: synthesized references (L017 route — the Lab/float-export host
// findings apply chain-wide); dt-side evidence = XMP op_params adoption +
// uniform-flat PFM probes.
// ─────────────────────────────────────────────────────────────────────────

public enum SigmoidKernel {
    public static let perChannelFunction = "sigmoid_per_channel"
    public static let rgbRatioFunction = "sigmoid_rgb_ratio"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// dt `dt_iop_sigmoid_base_primaries_t` (sigmoid.c:47-54) — raw values
/// aligned for XMP fidelity.
public enum SigmoidBasePrimaries: Int, Codable, Hashable, Sendable {
    case workProfile = 0
    case rec2020 = 1
    case displayP3 = 2
    case adobeRGB = 3
    case sRGB = 4
}

/// dt `dt_iop_sigmoid_methods_type_t` (sigmoid.c:40-44).
public enum SigmoidColorProcessing: Int, Codable, Hashable, Sendable {
    case perChannel = 0
    case rgbRatio = 1
}

/// A matrix-profile definition: xy primaries + white (D65 for every
/// named profile — dt reads the same colorants from the ICC tags) with
/// the RGB⇄XYZ matrices built by the Lindbloom primaries builder (the
/// SAME code path dt's custom-primaries math uses).
public struct SigmoidProfile: Sendable {
    public let primaries: [SIMD2<Double>]
    public let white: SIMD2<Double>
    /// RGB → XYZ (dt `matrix_in` semantics).
    public let rgbToXYZ: [[Double]]
    /// XYZ → RGB (dt `matrix_out` semantics — the exact inverse).
    public let xyzToRGB: [[Double]]

    init(primaries: [SIMD2<Double>], white: SIMD2<Double>) {
        self.primaries = primaries
        self.white = white
        self.rgbToXYZ = SigmoidProfile.buildRGBToXYZ(primaries: primaries, white: white)
        self.xyzToRGB = SigmoidProfile.invert3(self.rgbToXYZ)
    }

    /// dt `_sanitizeY` (colorspaces.c:2584-2592).
    static func sanitizeY(_ y: Double) -> Double {
        if y < 2.220446049250313e-16 && y >= 0 { return 2.220446049250313e-16 }
        if y < 0 && y > -2.220446049250313e-16 { return y }
        return y
    }

    /// dt `dt_make_transposed_matrices_from_primaries_and_whitepoint`
    /// (colorspaces.c:2571-2600) in Double, returned as the logical
    /// RGB→XYZ matrix (Lindbloom RGB→XYZ from primaries + white).
    static func buildRGBToXYZ(primaries: [SIMD2<Double>], white: SIMD2<Double>) -> [[Double]] {
        // Column c of the logical matrix = (scale[c] · XYZ of primary c).
        var primaryXYZ = [[Double]](repeating: [0, 0, 0], count: 3)
        for c in 0..<3 {
            let y = sanitizeY(primaries[c].y)
            primaryXYZ[c] = [primaries[c].x / y, 1.0, (1.0 - primaries[c].x - y) / y]
        }
        // primaries_inverse = inverse of the primaries matrix (columns =
        // primaryXYZ); applied to the XYZ white → the white's RGB coords.
        var p = [[Double]](repeating: [0, 0, 0], count: 3) // row-major P[r][c] = primaryXYZ[c][r]
        for r in 0..<3 { for c in 0..<3 { p[r][c] = primaryXYZ[c][r] } }
        let wy = sanitizeY(white.y)
        let xyzWhite = [white.x / wy, 1.0, (1.0 - white.x - wy) / wy]
        let scale = solve3(p, xyzWhite)
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        for r in 0..<3 { for c in 0..<3 { m[r][c] = scale[c] * primaryXYZ[c][r] } }
        return m
    }

    /// Row-major 3×3 solve (Gaussian elimination with partial pivots).
    static func solve3(_ m: [[Double]], _ b: [Double]) -> [Double] {
        var a = m
        var x = b
        for col in 0..<3 {
            var pivot = col
            for row in (col + 1)..<3 where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            if pivot != col {
                a.swapAt(pivot, col)
                x.swapAt(pivot, col)
            }
            for row in (col + 1)..<3 {
                let f = a[row][col] / a[col][col]
                for k in col..<3 { a[row][k] -= f * a[col][k] }
                x[row] -= f * x[col]
            }
        }
        for row in stride(from: 2, through: 0, by: -1) {
            var sum = x[row]
            for k in (row + 1)..<3 { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    /// Exact 3×3 inverse (adjugate / determinant — LabRoundTrip.invert shape).
    static func invert3(_ m: [[Double]]) -> [[Double]] {
        let a = m[0], b = m[1], c = m[2]
        let det = a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])
        return [
            [
                (b[1] * c[2] - b[2] * c[1]) / det,
                (a[2] * c[1] - a[1] * c[2]) / det,
                (a[1] * b[2] - a[2] * b[1]) / det,
            ],
            [
                (b[2] * c[0] - b[0] * c[2]) / det,
                (a[0] * c[2] - a[2] * c[0]) / det,
                (a[2] * b[0] - a[0] * b[2]) / det,
            ],
            [
                (b[0] * c[1] - b[1] * c[0]) / det,
                (a[1] * c[0] - a[0] * c[1]) / det,
                (a[0] * b[1] - a[1] * b[0]) / det,
            ],
        ]
    }

    // Named base profiles (D65 white — dt's ICC colorants for these).
    public static let rec2020 = SigmoidProfile(
        primaries: [SIMD2(0.708, 0.292), SIMD2(0.170, 0.797), SIMD2(0.131, 0.046)],
        white: SIMD2(0.3127, 0.3290)
    )
    public static let displayP3 = SigmoidProfile(
        primaries: [SIMD2(0.680, 0.320), SIMD2(0.265, 0.690), SIMD2(0.150, 0.060)],
        white: SIMD2(0.3127, 0.3290)
    )
    public static let adobeRGB = SigmoidProfile(
        primaries: [SIMD2(0.6400, 0.3300), SIMD2(0.2100, 0.7100), SIMD2(0.1500, 0.0600)],
        white: SIMD2(0.3127, 0.3290)
    )
    public static let sRGB = SigmoidProfile(
        primaries: [SIMD2(0.6400, 0.3300), SIMD2(0.3000, 0.6000), SIMD2(0.1500, 0.0600)],
        white: SIMD2(0.3127, 0.3290)
    )

    static func profile(for base: SigmoidBasePrimaries) -> SigmoidProfile {
        switch base {
        case .workProfile, .rec2020: return .rec2020
        case .displayP3: return .displayP3
        case .adobeRGB: return .adobeRGB
        case .sRGB: return .sRGB
        }
    }
}

public enum SigmoidPrimaries {

    /// dt `dt_rotate_and_scale_primary` (custom_primaries.c:76-96) —
    /// scale the primary toward/away from white and rotate it around the
    /// white point, clamped to the gamut triangle edge.
    static func rotateAndScalePrimary(
        _ profile: SigmoidProfile, scaling: Double, rotation: Double, index: Int
    ) -> SIMD2<Double> {
        let dx = profile.primaries[index].x - profile.white.x
        let dy = profile.primaries[index].y - profile.white.y
        let angle = atan2(dy, dx) + rotation
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let distanceToEdge = findDistanceToEdge(profile, cosAngle, sinAngle)
        return SIMD2(
            scaling * distanceToEdge * cosAngle + profile.white.x,
            scaling * distanceToEdge * sinAngle + profile.white.y
        )
    }

    /// custom_primaries.c:26-73 — the ray white → white+(cos,sin) against
    /// the three triangle edges, minimum positive intersection.
    static func findDistanceToEdge(
        _ profile: SigmoidProfile, _ cosAngle: Double, _ sinAngle: Double
    ) -> Double {
        // _determinant(a, b, c, d) = a·d − b·c
        func det(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double { a * d - b * c }
        func intersectLineSegments(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double, _ x4: Double, _ y4: Double) -> Double {
            let denominator = det(x1 - x2, x3 - x4, y1 - y2, y3 - y4)
            if denominator == 0 { return .greatestFiniteMagnitude }
            let t = det(x1 - x3, x3 - x4, y1 - y3, y3 - y4) / denominator
            return t >= 0 ? t : .greatestFiniteMagnitude
        }

        let x1 = profile.white.x, y1 = profile.white.y
        let x2 = x1 + cosAngle, y2 = y1 + sinAngle

        var distance = Double.greatestFiniteMagnitude
        for i in 0..<3 {
            let next = i == 2 ? 0 : i + 1
            let d = intersectLineSegments(
                x1, y1, x2, y2,
                profile.primaries[i].x, profile.primaries[i].y,
                profile.primaries[next].x, profile.primaries[next].y
            )
            distance = min(distance, d)
        }
        return distance
    }

    static func mul3(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z
        )
    }

    /// Full `_calculate_adjusted_primaries` (sigmoid.c:394-468) with the
    /// documented direction chain. Returns the three Float9 row-major
    /// matrices for the kernel buffer.
    public static func matrices(
        base: SigmoidBasePrimaries,
        insets: SIMD3<Double>,
        rotations: SIMD3<Double>,
        purity: Double
    ) -> (pipeToBase: [Float], baseToRendering: [Float], renderingToPipe: [Float]) {
        let work = SigmoidProfile.rec2020
        let baseProfile = SigmoidProfile.profile(for: base)

        // pipe ⇄ base (identity when base == work — dt's special case).
        let pipeToBase: [[Double]]
        let baseToPipe: [[Double]]
        if base == .workProfile {
            pipeToBase = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
            baseToPipe = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        } else {
            pipeToBase = matMul(baseProfile.xyzToRGB, work.rgbToXYZ)
            baseToPipe = matMul(work.xyzToRGB, baseProfile.rgbToXYZ)
        }

        // custom₁: inset + rotation primaries (sigmoid.c:444-453).
        var custom1 = [SIMD2<Double>](repeating: .zero, count: 3)
        for i in 0..<3 {
            custom1[i] = rotateAndScalePrimary(baseProfile, scaling: 1.0 - insets[i], rotation: rotations[i], index: i)
        }
        let custom1ToXYZ = SigmoidProfile.buildRGBToXYZ(primaries: custom1, white: baseProfile.white)
        // base → rendering = M_out(custom₁) · M_in(base) — the custom
        // matrix enters as its INVERSE (XYZ→custom direction).
        let baseToRendering = matMul(SigmoidProfile.invert3(custom1ToXYZ), baseProfile.rgbToXYZ)

        // custom₂: purity-folded primaries (sigmoid.c:455-459).
        var custom2 = [SIMD2<Double>](repeating: .zero, count: 3)
        for i in 0..<3 {
            let scaling = 1.0 - purity * insets[i]
            custom2[i] = rotateAndScalePrimary(baseProfile, scaling: scaling, rotation: rotations[i], index: i)
        }
        let custom2ToXYZ = SigmoidProfile.buildRGBToXYZ(primaries: custom2, white: baseProfile.white)
        // rendering₂ → base = M_out(base) · M_in(custom₂); the return leg
        // composes base→pipe with the inverse (base→rendering₂).
        let rendering2ToBase = matMul(baseProfile.xyzToRGB, custom2ToXYZ)
        let baseToRendering2 = SigmoidProfile.invert3(rendering2ToBase)
        let renderingToPipe = matMul(baseToPipe, baseToRendering2)

        return (flatten(pipeToBase), flatten(baseToRendering), flatten(renderingToPipe))
    }

    static func matMul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var out = [[Double]](repeating: [0, 0, 0], count: 3)
        for r in 0..<3 { for c in 0..<3 {
            out[r][c] = a[r][0] * b[0][c] + a[r][1] * b[1][c] + a[r][2] * b[2][c]
        } }
        return out
    }

    static func flatten(_ m: [[Double]]) -> [Float] {
        m.flatMap { $0.map { Float($0) } }
    }
}

/// The scene-referred log-logistic tone mapper.
public final class SigmoidModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {

        /// ∈ [0.1, 10], default 1.5 (sigmoid.c:59).
        public var middleGreyContrast: Float
        /// ∈ [-1, 1], default 0 (sigmoid.c:60).
        public var contrastSkewness: Float
        /// ∈ [20, 1600], default 100 (sigmoid.c:61) — output-side.
        public var displayWhiteTarget: Float
        /// ∈ [0, 15], default 0.0152 (sigmoid.c:62) — output-side.
        public var displayBlackTarget: Float
        /// per channel (default) / RGB ratio (sigmoid.c:63).
        public var colorProcessing: SigmoidColorProcessing
        /// ∈ [0, 100], default 100 (sigmoid.c:64).
        public var huePreservation: Float
        /// inset/rotation six-tuple (sigmoid.c:65-70), defaults 0.
        public var redInset: Float
        public var redRotation: Float
        public var greenInset: Float
        public var greenRotation: Float
        public var blueInset: Float
        public var blueRotation: Float
        /// ∈ [0, 1], default 0 (sigmoid.c:71).
        public var purity: Float
        /// base primaries (sigmoid.c:72, default work profile).
        public var basePrimaries: SigmoidBasePrimaries

        public init(
            middleGreyContrast: Float = 1.5,
            contrastSkewness: Float = 0,
            displayWhiteTarget: Float = 100,
            displayBlackTarget: Float = 0.0152,
            colorProcessing: SigmoidColorProcessing = .perChannel,
            huePreservation: Float = 100,
            redInset: Float = 0,
            redRotation: Float = 0,
            greenInset: Float = 0,
            greenRotation: Float = 0,
            blueInset: Float = 0,
            blueRotation: Float = 0,
            purity: Float = 0,
            basePrimaries: SigmoidBasePrimaries = .workProfile
        ) {
            self.middleGreyContrast = middleGreyContrast
            self.contrastSkewness = contrastSkewness
            self.displayWhiteTarget = displayWhiteTarget
            self.displayBlackTarget = displayBlackTarget
            self.colorProcessing = colorProcessing
            self.huePreservation = huePreservation
            self.redInset = redInset
            self.redRotation = redRotation
            self.greenInset = greenInset
            self.greenRotation = greenRotation
            self.blueInset = blueInset
            self.blueRotation = blueRotation
            self.purity = purity
            self.basePrimaries = basePrimaries
        }
    }

    public static let opName = "sigmoid"
    public static let iopOrder: Float = 45.3
    public static let flags: IOPFlags = [.supportsBlending]
    public static let defaultColorspace: IOPColorspace = .RGB

    // Piece buffer layout (floats): 7 scalars + 3 × 9 matrix entries +
    // a trailing per-run kernel selector (1.0 = per channel).
    static let scalarsOffset = 0
    static let pipeToBaseOffset = 7
    static let baseToRenderingOffset = 16
    static let renderingToPipeOffset = 25
    static let colorProcessingFlagOffset = 34
    static let bufferFloatCount = 35

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: Commit (sigmoid.c:318-407 + :394-468)

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            let derivation = SigmoidDerivation.derive(
                middleGreyContrast: Double(params.middleGreyContrast),
                contrastSkewness: Double(params.contrastSkewness),
                displayWhiteTarget: Double(params.displayWhiteTarget),
                displayBlackTarget: Double(params.displayBlackTarget),
                huePreservationPercent: Double(params.huePreservation)
            )
            let s = derivation.scalars
            let matrices = SigmoidPrimaries.matrices(
                base: params.basePrimaries,
                insets: SIMD3<Double>(
                    Double(params.redInset), Double(params.greenInset), Double(params.blueInset)
                ),
                rotations: SIMD3<Double>(
                    Double(params.redRotation), Double(params.greenRotation),
                    Double(params.blueRotation)
                ),
                purity: Double(params.purity)
            )

            var floats = [Float](repeating: 0, count: Self.bufferFloatCount)
            floats[0] = s.whiteTarget
            floats[1] = s.blackTarget
            floats[2] = s.paperExposure
            floats[3] = s.filmFog
            floats[4] = s.filmPower
            floats[5] = s.paperPower
            floats[6] = s.huePreservation
            floats.replaceSubrange(Self.pipeToBaseOffset..<Self.pipeToBaseOffset + 9, with: matrices.pipeToBase)
            floats.replaceSubrange(Self.baseToRenderingOffset..<Self.baseToRenderingOffset + 9, with: matrices.baseToRendering)
            floats.replaceSubrange(Self.renderingToPipeOffset..<Self.renderingToPipeOffset + 9, with: matrices.renderingToPipe)
            floats[Self.colorProcessingFlagOffset] = params.colorProcessing == .perChannel ? 1.0 : 0.0

            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: Self.bufferFloatCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: Self.bufferFloatCount * MemoryLayout<Float>.size)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

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
        guard let buffer = piece.data else { return }
        // The kernel selector rides IN the piece buffer (float 34) so the
        // run is self-contained (the ColisaModule `committed` cache pattern
        // with a piece-state fallback).
        let perChannel = buffer.contents().assumingMemoryBound(to: Float.self)[Self.colorProcessingFlagOffset] == 1.0
        let functionName = perChannel
            ? SigmoidKernel.perChannelFunction
            : SigmoidKernel.rgbRatioFunction
        try await metal.dispatch2DTexture(
            functionName: functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }
}
