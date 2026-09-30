import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// ColorWheelsModule (Plan M2-5-1 T6; KD-6, D-M2-5-CONTEXT-2) — the LGG
// three-wheel catalog op ("Color Wheel"). Params are FIELD-FOR-FIELD the
// Alcedo color_wheel_model.hpp:34-50 payload: three ColorWheelControl
// {disc, strength, color_offset, luminance_offset} for lift/gamma/gain;
// lift identity = all-zero, gamma/gain identity = colorOffset (1,1,1).
//
// Runtime packing (Alcedo adjustment_runtime.cpp:242-255): ONLY colorOffset
// + luminanceOffset reach the pixels — disc/strength are the trackball's
// UI state and do NOT participate (the IsIdentity judgment mirrors that:
// disc/strength/luminanceOffset are excluded, per the .cpp IsIdentity).
//
// T1 CARRIER NOTE: param/op face only — kernel + registration land with the
// T6 commit (GradeCarrierKernelPending tripwire; op unregistered meanwhile).
// ─────────────────────────────────────────────────────────────────────────

/// One lift/gamma/gain wheel control — Alcedo `ColorWheelControl`
/// (color_wheel_model.hpp:34-40), JSON keys照抄 the .cpp ToJson spelling
/// (disc.x/y, strength, color_offset.x/y/z, luminance_offset).
public struct ColorWheelControl: Codable, Hashable, Sendable {

    /// The trackball's UI position (unit disc) — carried, not consumed by
    /// the pixel math (Alcedo packs only colorOffset+luminanceOffset).
    public var disc: SIMD2<Float>
    /// The trackball's UI magnitude scale — carried, not consumed.
    public var strength: Float
    /// The per-channel offset/multiplier the kernel actually applies.
    public var colorOffset: SIMD3<Float>
    /// The luminance leg the kernel folds per-channel (see the T6 kernel).
    public var luminanceOffset: Float

    public init(
        disc: SIMD2<Float> = SIMD2(0, 0),
        strength: Float = 1.0,
        colorOffset: SIMD3<Float> = SIMD3(0, 0, 0),
        luminanceOffset: Float = 0
    ) {
        self.disc = disc
        self.strength = strength
        self.colorOffset = colorOffset
        self.luminanceOffset = luminanceOffset
    }

    private enum CodingKeys: String, CodingKey {
        case disc
        case strength
        case colorOffset = "color_offset"
        case luminanceOffset = "luminance_offset"
    }

    private enum Pair: String, CodingKey { case x, y }
    private enum Triple: String, CodingKey { case x, y, z }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let discContainer = try c.nestedContainer(keyedBy: Pair.self, forKey: .disc)
        self.disc = SIMD2(
            try discContainer.decode(Float.self, forKey: .x),
            try discContainer.decode(Float.self, forKey: .y))
        self.strength = try c.decode(Float.self, forKey: .strength)
        let offsetContainer = try c.nestedContainer(keyedBy: Triple.self, forKey: .colorOffset)
        self.colorOffset = SIMD3(
            try offsetContainer.decode(Float.self, forKey: .x),
            try offsetContainer.decode(Float.self, forKey: .y),
            try offsetContainer.decode(Float.self, forKey: .z))
        self.luminanceOffset = try c.decode(Float.self, forKey: .luminanceOffset)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var discContainer = c.nestedContainer(keyedBy: Pair.self, forKey: .disc)
        try discContainer.encode(disc.x, forKey: .x)
        try discContainer.encode(disc.y, forKey: .y)
        try c.encode(strength, forKey: .strength)
        var offsetContainer = c.nestedContainer(keyedBy: Triple.self, forKey: .colorOffset)
        try offsetContainer.encode(colorOffset.x, forKey: .x)
        try offsetContainer.encode(colorOffset.y, forKey: .y)
        try offsetContainer.encode(colorOffset.z, forKey: .z)
        try c.encode(luminanceOffset, forKey: .luminanceOffset)
    }
}

public final class ColorWheelsModule: IOPModule {

    /// The three wheels (the per-wheel derived-offset anchors — Alcedo
    /// editor_cdl_trackball_model.cpp UpdateDerived's add_unity/invert flags
    /// fold into the kind).
    public enum WheelKind: String, Sendable, CaseIterable {
        case lift
        case gamma
        case gain
    }

    /// Alcedo editor_support color_wheel.hpp constants (the trackball UI
    /// face): strength is a 0...0.1 factor, the luminance master clamps
    /// ±1, and kEpsilon guards the normalization.
    public static let strengthRange: ClosedRange<Float> = (0.0...0.1)
    public static let luminanceRange: ClosedRange<Float> = (-1.0...1.0)
    static let kEpsilon: Float = 1.0e-6

    // MARK: - Trackball coordinate math (Plan M2-5-2 KD-2 — pure, testable)

    /// View point → unit-disc {x,y} (Alcedo ClampDiscPoint; y flipped —
    /// view y grows downward, the disc's +y is up), length clamped ≤ 1.
    public static func discFrom(
        point: SIMD2<Float>, relativeTo center: SIMD2<Float>, radius: Float
    ) -> SIMD2<Float> {
        let r = max(radius, 1)
        var d = (point - center) / r
        d.y = -d.y
        let length = sqrt(d.x * d.x + d.y * d.y)
        if length > 1 { d /= length }
        return d
    }

    /// Unit disc → the OFFSET from the wheel center in view points (the
    /// inverse of `discFrom`; the caller adds the center). y flipped back.
    public static func pointFrom(disc: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        SIMD2(disc.x, -disc.y) * max(radius, 1)
    }

    /// Alcedo HueToUnitRgb: h ∈ [0,1) → the six-sector hue RGB.
    public static func hueToUnitRgb(_ h: Float) -> SIMD3<Float> {
        let hh = h - floor(h)
        let scaled = hh * 6
        let sector = Int(floor(scaled)) % 6
        let f = scaled - floor(scaled)
        switch sector {
        case 0: return SIMD3(1, f, 0)
        case 1: return SIMD3(1 - f, 1, 0)
        case 2: return SIMD3(0, 1, f)
        case 3: return SIMD3(0, 1 - f, 1)
        case 4: return SIMD3(f, 0, 1)
        default: return SIMD3(1, 0, 1 - f)
        }
    }

    /// Alcedo DiscToCdlDelta: the disc position → the zero-sum RGB delta
    /// direction scaled by strength × disc-radius (the wheel's pixel-state
    /// derivation the UI performs on every drag).
    public static func cdlDelta(
        disc: SIMD2<Float>, strength: Float
    ) -> SIMD3<Float> {
        let x = disc.x, y = disc.y
        let r = min(max(sqrt(x * x + y * y), 0), 1)
        var h = atan2(y, x) / (2 * Float.pi)
        if h < 0 { h += 1 }
        let c = hueToUnitRgb(h)
        let m = (c.x + c.y + c.z) / 3
        var dr = c.x - m, dg = c.y - m, db = c.z - m
        let length = sqrt(dr * dr + dg * dg + db * db)
        let inv = 1 / (length + kEpsilon)
        dr *= inv; dg *= inv; db *= inv
        let scale = max(strength, 0) * r
        return SIMD3(dr, dg, db) * scale
    }

    /// The per-wheel derived colorOffset (Alcedo UpdateDerived): lift rides
    /// base 0, gamma/gain ride base 1 with gamma's delta INVERTED.
    public static func colorOffset(
        from disc: SIMD2<Float>, strength: Float, wheel: WheelKind
    ) -> SIMD3<Float> {
        let delta = cdlDelta(disc: disc, strength: strength)
        switch wheel {
        case .lift: return SIMD3(0, 0, 0) + delta
        case .gamma: return SIMD3(1, 1, 1) - delta
        case .gain: return SIMD3(1, 1, 1) + delta
        }
    }

    /// The per-wheel payload-identity reset (the double-click face): the
    /// wheel returns to the Params() default control — lift all-zero,
    /// gamma/gain colorOffset (1,1,1), disc zero, strength 1 (the payload
    /// pristine, byte-equal to the identityJSON components).
    public static func resetting(_ params: Params, wheel: WheelKind) -> Params {
        var p = params
        switch wheel {
        case .lift: p.lift = ColorWheelControl()
        case .gamma: p.gamma = ColorWheelControl(colorOffset: SIMD3(1, 1, 1))
        case .gain: p.gain = ColorWheelControl(colorOffset: SIMD3(1, 1, 1))
        }
        return p
    }

    /// Alcedo `ColorWheelPayload` (color_wheel_model.hpp:42-47).
    public struct Params: Codable, Hashable, Sendable {
        public var lift: ColorWheelControl
        public var gamma: ColorWheelControl
        public var gain: ColorWheelControl

        public init(
            lift: ColorWheelControl = ColorWheelControl(),
            gamma: ColorWheelControl = ColorWheelControl(colorOffset: SIMD3(1, 1, 1)),
            gain: ColorWheelControl = ColorWheelControl(colorOffset: SIMD3(1, 1, 1))
        ) {
            self.lift = lift
            self.gamma = gamma
            self.gain = gain
        }
    }

    public static let opName = "colorWheels"

    /// LIGHTAMER V50Order row 41.0 — shares the slot with the UNREGISTERED
    /// dt `colorbalance` row (the declared collision exception, KD-3).
    public static let iopOrder: Float = 41.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Alcedo color_wheel_model.cpp `IsIdentity` — VERBATIM judgment: lift
    /// all-zero (disc, colorOffset, luminanceOffset) AND gamma/gain
    /// colorOffset == (1,1,1). disc/strength (both wheels) and every
    /// luminanceOffset on gamma/gain do NOT participate (照抄).
    public static func isIdentity(_ params: Params) -> Bool {
        let lift = params.lift
        let liftOK =
            lift.disc.x == 0 && lift.disc.y == 0
            && lift.colorOffset.x == 0 && lift.colorOffset.y == 0
            && lift.colorOffset.z == 0 && lift.luminanceOffset == 0
        let gammaOK =
            params.gamma.colorOffset.x == 1 && params.gamma.colorOffset.y == 1
            && params.gamma.colorOffset.z == 1
        let gainOK =
            params.gain.colorOffset.x == 1 && params.gain.colorOffset.y == 1
            && params.gain.colorOffset.z == 1
        return liftOK && gammaOK && gainOK
    }

    public static let colorWheelsKernel = "grade_color_wheels"

    private let device: (any MTLDevice)?
    private var uniformsBuffer: (any MTLBuffer)?
    private var committedFlag: Float = -1

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        // The runtime packing (Alcedo behavior 11): colorOffset +
        // luminanceOffset ONLY — disc/strength are UI state and never
        // reach the pixels.
        var floats = [Float](repeating: 0, count: 16)
        floats[0] = Self.isIdentity(params) ? 0 : 1
        let controls = [params.lift, params.gamma, params.gain]
        for (index, control) in controls.enumerated() {
            floats[1 + index * 4 + 0] = control.colorOffset.x
            floats[1 + index * 4 + 1] = control.colorOffset.y
            floats[1 + index * 4 + 2] = control.colorOffset.z
            floats[1 + index * 4 + 3] = control.luminanceOffset
        }
        if uniformsBuffer == nil || committedFlag != floats[0] {
            let resolved = device ?? MTLCreateSystemDefaultDevice()
            uniformsBuffer = resolved?.makeBuffer(
                length: 16 * MemoryLayout<Float>.stride, options: .storageModeShared)
            committedFlag = floats[0]
        }
        guard let buffer = uniformsBuffer else {
            piece.data = nil
            return
        }
        floats.withUnsafeBytes {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: 16 * MemoryLayout<Float>.stride)
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
        guard let buffer = piece.data else { return }
        try await metal.dispatch2DTexture(
            functionName: Self.colorWheelsKernel,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    // MARK: - CPU reference (KD-8 — the golden test's Float64 mirror)

    /// The Float64 reference (Alcedo behavior 11): the per-channel
    /// lift/gamma/gain power ride on the ACEScc texels —
    /// sign(c)·|c + lift.color + lift.luma|^(1/max(gamma.color + gamma.luma,
    /// 1e-4)) · gain.color.
    public static func reference(acescc: SIMD3<Double>, params: Params) -> SIMD3<Double> {
        if isIdentity(params) { return acescc }
        func channel(
            _ c: Double, _ liftColor: Double, _ gammaColor: Double, _ gainColor: Double
        ) -> Double {
            let gammaLeg = max(gammaColor + Double(params.gamma.luminanceOffset), 1.0e-4)
            return copysign(
                pow(abs(c + liftColor + Double(params.lift.luminanceOffset)), 1.0 / gammaLeg), c
            ) * gainColor
        }
        return SIMD3(
            channel(
                acescc.x, Double(params.lift.colorOffset.x),
                Double(params.gamma.colorOffset.x), Double(params.gain.colorOffset.x)),
            channel(
                acescc.y, Double(params.lift.colorOffset.y),
                Double(params.gamma.colorOffset.y), Double(params.gain.colorOffset.y)),
            channel(
                acescc.z, Double(params.lift.colorOffset.z),
                Double(params.gamma.colorOffset.z), Double(params.gain.colorOffset.z)))
    }
}
