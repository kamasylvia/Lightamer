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
    /// derivation the UI performs on every drag). The strength rides the
    /// UpdateDerived clamp (`clamp(strength, 0, kStrengthDefault)` — the
    /// payload pristine carries 1.0, so the un-clamped first drag would
    /// derive a 10× offset vs the Alcedo mapping).
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
        let scale = min(max(strength, 0), strengthRange.upperBound) * r
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

    /// Alcedo `ColorWheelPayload` (color_wheel_model.hpp:42-47). The v2
    /// tone-wheel payload adds the fourth wheel (`offset`) as an ADDITIVE
    /// OPTIONAL (Plan M9-4 T1, D-M9SP-2 — the 甲 form): its presence/absence
    /// is the v1/v2 SEMANTIC DISCRIMINATOR (absent = v1 semantics, converted
    /// on the fly by the render pre-resolve and the panel edit projection;
    /// present — even all-zero — = v2 tone-wheel semantics, read through).
    /// The synthesized Codable emits `offset` via encodeIfPresent, so an
    /// offset-nil Params encodes BYTE-IDENTICAL to the pre-M9-4 shape (the
    /// H-SP2 zero-drift negative test pins this).
    public struct Params: Codable, Hashable, Sendable {
        public var lift: ColorWheelControl
        public var gamma: ColorWheelControl
        public var gain: ColorWheelControl
        /// The v2 Offset wheel (all tones). Absent on every legacy shape.
        public var offset: ColorWheelControl?

        public init(
            lift: ColorWheelControl = ColorWheelControl(),
            gamma: ColorWheelControl = ColorWheelControl(colorOffset: SIMD3(1, 1, 1)),
            gain: ColorWheelControl = ColorWheelControl(colorOffset: SIMD3(1, 1, 1)),
            offset: ColorWheelControl? = nil
        ) {
            self.lift = lift
            self.gamma = gamma
            self.gain = gain
            self.offset = offset
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
    // The v3 mirror + memo (D-M9SP-2 补强② — see commitParams).
    private let mirrorLock = NSLock()
    private var paramsMirror: Params?
    private var toneWheelMemo: (hash: UInt64, buffer: any MTLBuffer)?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        // The v3 params mirror (D-M9SP-2 补强②): the frozen 16-float packing
        // below carries ONLY the three v1 wheels, so the v3 pre-resolve
        // needs the full quad — keep it (NSLock, uniformsBuffer 同款读写
        // 模式; read via toneWheelUniformsBuffer / lastCommittedParams).
        mirrorLock.lock()
        paramsMirror = params
        mirrorLock.unlock()
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

// ─────────────────────────────────────────────────────────────────────────
// v3 tone-wheel math (Plan M9-4 T1, X1 — the upstream color_wheel_tone
// .hpp/.cpp transliteration at commit e1effd8; GPL header + modifications
// live in ColorWheelsLegacyConvert.swift). The v1 faces above (constants,
// cdlDelta, colorOffset(from:), reference) stay BYTE-INTACT — the frozen
// views and the frozen packing consume them.
// ─────────────────────────────────────────────────────────────────────────
extension ColorWheelsModule {

    /// Disc stops at full radius (upstream color_wheel_model.hpp
    /// kDiscMaxStops — also the strength default).
    public static let discMaxStops: Float = 1.0
    /// Master slider limit in stops (upstream kMasterMaxStops).
    public static let masterMaxStops: Float = 2.0
    /// t = 0 (upstream color_wheel_tone.hpp kToneBlackEv).
    public static let toneBlackEv: Float = -6.0
    /// t = 1 (upstream kToneWhiteEv). R = the 12-stop tone range; middle
    /// grey sits at exactly t = 0.5.
    public static let toneWhiteEv: Float = 6.0
    /// White − Black in stops.
    public static let toneRangeEv: Double =
        Double(toneWhiteEv) - Double(toneBlackEv)
    /// ACEScc code values per stop (upstream color_encoding_math.h:125
    /// CE_ACESCC_B — the shipped f32 literal; cross-checked against
    /// Cat02WBMath.acesccEncode in the golden tests).
    static let acesccB: Float = 17.52
    /// ACEScc code value of 0.18 middle grey (upstream :127
    /// CE_ACESCC_MIDDLE_GREY).
    static let acesccMiddleGrey: Float = 0.4135884
    /// The v3 GPU kernel — THE ONLY new kernel of this batch (D-M9SP-9
    /// 申报面清单; the existing `grade_color_wheels` body stays byte-intact).
    public static let colorWheelsV3Kernel = "grade_color_wheels_v3"
    /// The v3 fold tag — the processForkHash payload (L013 StableHash
    /// domain; folded by PixelPipe.prepareChain when and ONLY when the
    /// resolved arm is .v3 — the「非 legacy 才折」contract, D-M9SP-8).
    public static let v3ForkTag = "lightamer.colorwheels.v3"

    // MARK: - v3 disc mapping (STOPS semantics — no strength clamp: unlike
    // the v1 cdlDelta 0...0.1 factor, v3 strength IS the stop scale)

    /// The disc point moved onto the unit circle when outside (upstream
    /// ClampDiscPoint); a non-finite point is the center.
    public static func clampDiscPoint(_ x: Float, _ y: Float) -> SIMD2<Float> {
        if !(x.isFinite && y.isFinite) { return .zero }
        let r = sqrt(x * x + y * y)
        if r <= 1 || r <= kEpsilon { return SIMD2(x, y) }
        let inv = 1 / r
        return SIMD2(x * inv, y * inv)
    }

    /// Per-channel stops of the disc point: zero mean, length
    /// `strength · radius`, hue direction (upstream DiscToChannelStops).
    public static func discToChannelStops(
        x: Float, y: Float, strength: Float
    ) -> SIMD3<Float> {
        let p = clampDiscPoint(x, y)
        let r = min(max(sqrt(p.x * p.x + p.y * p.y), 0), 1)
        var h = atan2(p.y, p.x) / (2 * Float.pi)
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

    /// The disc point whose `discToChannelStops` at `strength` is the
    /// zero-mean part of `stops`; outside the unit disc clamps onto the
    /// unit circle (upstream ChannelStopsToDisc — the UI back-fill and
    /// the convert face's disc inversion).
    public static func channelStopsToDisc(
        _ stops: SIMD3<Float>, strength: Float
    ) -> SIMD2<Float> {
        let mean =
            (Double(stops.x) + Double(stops.y) + Double(stops.z)) / 3
        let v = SIMD3<Double>(
            Double(stops.x) - mean, Double(stops.y) - mean, Double(stops.z) - mean)
        let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        if len <= Double(kEpsilon) || Double(strength) <= Double(kEpsilon) {
            return .zero
        }
        let r = min(len / Double(strength), 1.0)
        let angle = rgbHue(v) * 2 * Double.pi
        return SIMD2(Float(r * cos(angle)), Float(r * sin(angle)))
    }

    /// HSV hue in [0, 1) of rgb (upstream RgbHue — invariant under a
    /// constant added to every channel and under positive scaling).
    static func rgbHue(_ rgb: SIMD3<Double>) -> Double {
        let maximum = max(rgb.x, max(rgb.y, rgb.z))
        let minimum = min(rgb.x, min(rgb.y, rgb.z))
        let chroma = maximum - minimum
        if chroma <= 0 { return 0 }
        var sector = 0.0
        if maximum == rgb.x {
            sector = fmod((rgb.y - rgb.z) / chroma + 6, 6)
        } else if maximum == rgb.y {
            sector = (rgb.z - rgb.x) / chroma + 2
        } else {
            sector = (rgb.x - rgb.y) / chroma + 4
        }
        return sector / 6
    }

    /// Per-channel wheel value in stops: the disc stops + the master
    /// (upstream ControlChannelStops — THE rendering input form).
    public static func controlChannelStops(
        _ control: ColorWheelControl
    ) -> SIMD3<Float> {
        SIMD3(
            control.colorOffset.x + control.luminanceOffset,
            control.colorOffset.y + control.luminanceOffset,
            control.colorOffset.z + control.luminanceOffset)
    }

    // MARK: - Identity / discriminators

    /// v3 identity: the effective (v2-semantic) quad is ALL-ZERO across
    /// the four wheels (per-channel stops zero; disc/strength excluded —
    /// the same judgment form as the v1 `isIdentity`). For an offset-
    /// ABSENT (legacy) shape this is exactly the v1 judgment: the convert
    /// maps the v1-neutral exact to the zero quad, and any non-neutral
    /// legacy edit produces non-zero wheels — so `isIdentity(params)`
    /// stands in without paying the fit (D-M9SP-2 discriminator).
    public static func isIdentityV3(_ params: Params) -> Bool {
        if params.offset == nil { return isIdentity(params) }
        func neutral(_ c: ColorWheelControl) -> Bool {
            return c.colorOffset == .zero && c.luminanceOffset == 0
        }
        return neutral(params.lift) && neutral(params.gamma)
            && neutral(params.gain) && neutral(params.offset!)
    }

    /// The effective tone-wheel quad (D-M9SP-2 补强① single source): an
    /// offset-ABSENT shape is v1-semantic and converts on the fly; an
    /// offset-PRESENT shape (even all-zero) is v2-semantic and reads
    /// through. Consumed by the render pre-resolve AND the v3 panel's
    /// edit projection (first edit materializes the offset).
    public static func effectiveToneWheelParams(_ params: Params) -> Params {
        guard params.offset == nil else { return params }
        return ColorWheelsLegacyConvert.convertLegacyColorWheel(params)
    }

    // MARK: - Kernel params (the 14-float GPU face)

    /// GPU parameters of the four wheels (upstream `ToneWheelKernelParams`
    /// — resolved per channel from the wheel values in stops).
    public struct ToneWheelKernelParams: Equatable, Sendable {
        /// Offset as an ACEScc increment (per channel).
        public var offsetAcescc = SIMD3<Float>.zero
        /// Lift K / R.
        public var liftScale = SIMD3<Float>.zero
        /// Gamma exponent p (defaults 1).
        public var gammaExponent = SIMD3<Float>(1, 1, 1)
        /// Gain K / R.
        public var gainScale = SIMD3<Float>.zero
        /// ACEScc value at t = 0.
        public var toneBlackAcescc: Float = 0
        /// ACEScc width of the tone range (t = 0 to t = 1).
        public var toneRangeAcescc: Float = 1

        /// The kernel-buffer float layout (the `ToneWheelUniforms` order —
        /// 14 floats: offset3 / lift3 / gamma3 / gain3 / black / range).
        public var bufferFloats: [Float] {
            [
                offsetAcescc.x, offsetAcescc.y, offsetAcescc.z,
                liftScale.x, liftScale.y, liftScale.z,
                gammaExponent.x, gammaExponent.y, gammaExponent.z,
                gainScale.x, gainScale.y, gainScale.z,
                toneBlackAcescc, toneRangeAcescc,
            ]
        }
    }

    /// Upstream `GammaExponent`: `p = ln(max(0.5 + K/R, 0.05)) / ln(0.5)`.
    public static func gammaExponent(stops: Double) -> Double {
        let base = max(0.5 + stops / toneRangeEv, 0.05)
        return log(base) / log(0.5)
    }

    /// The 14-float GPU parameters of the four wheels (upstream
    /// `ResolveToneWheelKernelParams`). An offset-absent shape passes
    /// through `effectiveToneWheelParams` first (the conversion is the
    /// effective semantics — single source with the panel projection).
    public static func resolveToneWheelKernelParams(
        of params: Params
    ) -> ToneWheelKernelParams {
        let p = effectiveToneWheelParams(params)
        var out = ToneWheelKernelParams()
        let offset = controlChannelStops(p.offset ?? ColorWheelControl())
        let lift = controlChannelStops(p.lift)
        let gamma = controlChannelStops(p.gamma)
        let gain = controlChannelStops(p.gain)
        for ch in 0..<3 {
            out.offsetAcescc[ch] = offset[ch] / acesccB
            out.liftScale[ch] = lift[ch] / Float(toneRangeEv)
            out.gammaExponent[ch] = Float(gammaExponent(stops: Double(gamma[ch])))
            out.gainScale[ch] = gain[ch] / Float(toneRangeEv)
        }
        out.toneBlackAcescc = acesccMiddleGrey + toneBlackEv / acesccB
        out.toneRangeAcescc = Float(toneRangeEv) / acesccB
        return out
    }

    /// Lift, Gamma, and Gain on one ACEScc value (Float32 CPU form of the
    /// kernel's non-neutral branch; Offset is applied before this).
    static func applyLiftGammaGain(
        acescc: Float, black: Float, range: Float,
        liftScale: Float, gammaExponent: Float, gainScale: Float
    ) -> Float {
        var t = (acescc - black) / range
        t += liftScale * min(max(1 - t, 0), 1)
        if t > 0 && t < 1 {
            t = powf(t, gammaExponent)
        }
        t += gainScale * max(t, 0)
        return black + t * range
    }

    /// CPU reference of the GPU tone-wheel operation on one ACEScc texel
    /// (upstream `ApplyToneWheels` — the neutral early exit kept bit-exact:
    /// neutral Lift/Gamma/Gain leaves the value exact, only the Offset
    /// applies, as on the GPU).
    public static func applyToneWheels(
        _ acescc: Float, channel: Int, params: ToneWheelKernelParams
    ) -> Float {
        if params.liftScale[channel] == 0
            && params.gammaExponent[channel] == 1
            && params.gainScale[channel] == 0 {
            return acescc + params.offsetAcescc[channel]
        }
        return applyLiftGammaGain(
            acescc: acescc + params.offsetAcescc[channel],
            black: params.toneBlackAcescc, range: params.toneRangeAcescc,
            liftScale: params.liftScale[channel],
            gammaExponent: params.gammaExponent[channel],
            gainScale: params.gainScale[channel])
    }

    /// The Float64 reference mirror (the v3 golden gate — includes the
    /// conversion-materialization semantics: an offset-absent shape
    /// converts first, like the render pre-resolve).
    public static func referenceV3(
        acescc: SIMD3<Double>, params: Params
    ) -> SIMD3<Double> {
        let p = resolveToneWheelKernelParams(of: params)
        let black = Double(p.toneBlackAcescc)
        let range = Double(p.toneRangeAcescc)
        func channel(_ c: Double, _ ch: Int) -> Double {
            let lift = Double(p.liftScale[ch])
            let gexp = Double(p.gammaExponent[ch])
            let gain = Double(p.gainScale[ch])
            if lift == 0 && gexp == 1 && gain == 0 {
                return c + Double(p.offsetAcescc[ch])
            }
            return ColorWheelsLegacyConvert.applyLiftGammaGainFloat64(
                acescc: c + Double(p.offsetAcescc[ch]),
                black: black, range: range,
                liftScale: lift, gammaExponent: gexp, gainScale: gain)
        }
        return SIMD3(
            channel(acescc.x, 0), channel(acescc.y, 1), channel(acescc.z, 2))
    }

    // MARK: - v3 mirror read face (D-M9SP-2 补强② — commitParams 写, process 读)

    /// The last-committed params (the v3 pre-resolve's full-fidelity
    /// source — the frozen 16-float packing does NOT carry the offset
    /// wheel; box ownership disciplines commit/process into the same
    /// domain, like the uniformsBuffer).
    var lastCommittedParams: Params? {
        mirrorLock.lock()
        defer { mirrorLock.unlock() }
        return paramsMirror
    }

    /// The 14-float v3 uniforms buffer for the committed params (memo
    /// keyed by the piece's paramsHash — rebuilt only when the hash moves).
    func toneWheelUniformsBuffer(paramsHash: UInt64) -> (any MTLBuffer)? {
        mirrorLock.lock()
        defer { mirrorLock.unlock() }
        if let memo = toneWheelMemo, memo.hash == paramsHash {
            return memo.buffer
        }
        guard let mirror = paramsMirror else { return nil }
        let resolved = Self.resolveToneWheelKernelParams(of: mirror)
        var floats = resolved.bufferFloats
        let resolvedDevice = device ?? MTLCreateSystemDefaultDevice()
        guard
            let buffer = resolvedDevice?.makeBuffer(
                bytes: &floats, length: 14 * MemoryLayout<Float>.stride,
                options: .storageModeShared)
        else { return nil }
        toneWheelMemo = (hash: paramsHash, buffer: buffer)
        return buffer
    }
}
