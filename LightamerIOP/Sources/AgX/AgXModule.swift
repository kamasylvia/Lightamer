import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// AgXModule (Plan 03-06-T6, IOP-FILM-03) — the Blender AgX-inspired filmic
// VARIANT (dt `src/iop/agx.c`, 2844 lines, modversion 7, v50 slot 45.5).
// Shares the sigmoid primaries infrastructure (SigmoidProfile /
// SigmoidPrimaries.rotateAndScalePrimary — the same dt_rotate_and_scale_
// primary + Lindbloom builder underneath).
//
// STRUCTURE (agx.c:794-964 commit → kernel_agx in AgXKernels.metal):
//   CPU  — _calculate_tone_mapping_params (the sigmoid-trapezoid curve
//          derivation: pivot/contrast/toe/shoulder scales + fallbacks)
//          + _get_primaries_params + the four matrices
//   GPU  — compress_into_gamut → log encode → curve → (look) → gamma
//          → (HSV hue restore) per pixel
//
// SCOPE NOTES:
//   - 「hatchless」 has NO dt counterpart (REQUIREMENTS IOP-FILM-03
//     note; 03-06-DECISIONS.md) — not implemented.
//   - The default path (base Rec2020 == work profile, zero inset/
//     rotation) has IDENTITY primaries matrices; dt's base profiles for
//     the non-default selections are ICC profiles whose primaries/white
//     are D50-adapted — Lightamer builds them from the D65 xy primaries
//     (SigmoidProfile, the sigmoid_smooth precedent). The look's luma
//     matrix follows the same builder (recorded deviation; the
//     agx_look/agx_primaries golden cases are dual-implementation-pinned,
//     not dt-pinned).
//   - The auto exposure keys (agx.c:1075-1117) are out of this plan's
//     scope (the filmic auto trio covers the plan's sampling surface).
//
// INPUT SEMANTICS: linear Rec2020 scene RGB (values may exceed 1.0; the
// kernel sanitizes to ±1e6 and drops NaNs — agx.cl kernel_agx). L006:
// float32 only.
// ─────────────────────────────────────────────────────────────────────────

public enum AgXKernel {
    public static let mainFunction = "kernel_agx"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// dt `dt_iop_agx_base_primaries_t` (agx.c:73-81).
public enum AgXBasePrimaries: Int, Codable, Hashable, Sendable {
    case exportProfile = 0
    case workProfile = 1
    case rec2020 = 2
    case displayP3 = 3
    case adobeRGB = 4
    case sRGB = 5
}

public final class AgXModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {

        // look (agx.c:99-103)
        public var lookLift: Float
        public var lookSlope: Float
        public var lookBrightness: Float
        public var lookSaturation: Float
        public var lookOriginalHueMixRatio: Float

        // log mapping (agx.c:106-109)
        public var rangeBlackRelativeEv: Float
        public var rangeWhiteRelativeEv: Float
        public var dynamicRangeScaling: Float

        // curve (agx.c:112-133)
        public var curvePivotX: Float
        public var curvePivotYLinearOutput: Float
        public var curveContrastAroundPivot: Float
        public var curveLinearRatioBelowPivot: Float
        public var curveLinearRatioAbovePivot: Float
        public var curveToePower: Float
        public var curveShoulderPower: Float
        public var curveGamma: Float
        public var autoGamma: Bool
        public var curveTargetDisplayBlackRatio: Float
        public var curveTargetDisplayWhiteRatio: Float

        // custom primaries (agx.c:136-160)
        public var basePrimaries: AgXBasePrimaries
        public var disablePrimariesAdjustments: Bool
        public var redInset: Float
        public var redRotation: Float
        public var greenInset: Float
        public var greenRotation: Float
        public var blueInset: Float
        public var blueRotation: Float
        public var masterOutsetRatio: Float
        public var masterUnrotationRatio: Float
        public var redOutset: Float
        public var redUnrotation: Float
        public var greenOutset: Float
        public var greenUnrotation: Float
        public var blueOutset: Float
        public var blueUnrotation: Float
        public var completelyReversePrimaries: Bool

        public init(
            lookLift: Float = 0,
            lookSlope: Float = 1,
            lookBrightness: Float = 1,
            lookSaturation: Float = 1,
            lookOriginalHueMixRatio: Float = 0.6,
            rangeBlackRelativeEv: Float = -10,
            rangeWhiteRelativeEv: Float = 6.5,
            dynamicRangeScaling: Float = 0.1,
            curvePivotX: Float = 0.606060606061,
            curvePivotYLinearOutput: Float = 0.18,
            curveContrastAroundPivot: Float = 3.0,
            curveLinearRatioBelowPivot: Float = 0,
            curveLinearRatioAbovePivot: Float = 0,
            curveToePower: Float = 1.5,
            curveShoulderPower: Float = 3.3,
            curveGamma: Float = 2.2,
            autoGamma: Bool = false,
            curveTargetDisplayBlackRatio: Float = 0,
            curveTargetDisplayWhiteRatio: Float = 1,
            basePrimaries: AgXBasePrimaries = .rec2020,
            disablePrimariesAdjustments: Bool = false,
            redInset: Float = 0,
            redRotation: Float = 0,
            greenInset: Float = 0,
            greenRotation: Float = 0,
            blueInset: Float = 0,
            blueRotation: Float = 0,
            masterOutsetRatio: Float = 1,
            masterUnrotationRatio: Float = 1,
            redOutset: Float = 0,
            redUnrotation: Float = 0,
            greenOutset: Float = 0,
            greenUnrotation: Float = 0,
            blueOutset: Float = 0,
            blueUnrotation: Float = 0,
            completelyReversePrimaries: Bool = false
        ) {
            self.lookLift = lookLift
            self.lookSlope = lookSlope
            self.lookBrightness = lookBrightness
            self.lookSaturation = lookSaturation
            self.lookOriginalHueMixRatio = lookOriginalHueMixRatio
            self.rangeBlackRelativeEv = rangeBlackRelativeEv
            self.rangeWhiteRelativeEv = rangeWhiteRelativeEv
            self.dynamicRangeScaling = dynamicRangeScaling
            self.curvePivotX = curvePivotX
            self.curvePivotYLinearOutput = curvePivotYLinearOutput
            self.curveContrastAroundPivot = curveContrastAroundPivot
            self.curveLinearRatioBelowPivot = curveLinearRatioBelowPivot
            self.curveLinearRatioAbovePivot = curveLinearRatioAbovePivot
            self.curveToePower = curveToePower
            self.curveShoulderPower = curveShoulderPower
            self.curveGamma = curveGamma
            self.autoGamma = autoGamma
            self.curveTargetDisplayBlackRatio = curveTargetDisplayBlackRatio
            self.curveTargetDisplayWhiteRatio = curveTargetDisplayWhiteRatio
            self.basePrimaries = basePrimaries
            self.disablePrimariesAdjustments = disablePrimariesAdjustments
            self.redInset = redInset
            self.redRotation = redRotation
            self.greenInset = greenInset
            self.greenRotation = greenRotation
            self.blueInset = blueInset
            self.blueRotation = blueRotation
            self.masterOutsetRatio = masterOutsetRatio
            self.masterUnrotationRatio = masterUnrotationRatio
            self.redOutset = redOutset
            self.redUnrotation = redUnrotation
            self.greenOutset = greenOutset
            self.greenUnrotation = greenUnrotation
            self.blueOutset = blueOutset
            self.blueUnrotation = blueUnrotation
            self.completelyReversePrimaries = completelyReversePrimaries
        }
    }

    public static let opName = "agx"
    public static let iopOrder: Float = 45.5
    public static let flags: IOPFlags = [.supportsBlending]
    public static let defaultColorspace: IOPColorspace = .RGB

    // Piece buffer layout (floats):
    //   0..30   the dt `tone_mapping_params_t` mirror (25 floats + 6 ints
    //           packed as float flags — the kernel reads floats)
    //   31..39  pipe_to_base
    //   40..48  base_to_rendering
    //   49..57  rendering_to_pipe
    //   58..66  rendering_to_xyz (the look luminance matrix)
    static let bufferFloatCount = 67
    static let paramsOffset = 0
    static let pipeToBaseOffset = 31
    static let baseToRenderingOffset = 40
    static let renderingToPipeOffset = 49
    static let renderingToXYZOffset = 58

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

    // MARK: - Commit (agx.c:794-964 _calculate_tone_mapping_params)

    /// The derived curve — public for the CPUDerivation cross-check.
    public struct CurveDerivation: Equatable, Sendable {
        public var blackRelativeEv: Float
        public var rangeInEv: Float
        public var curveGamma: Float
        public var pivotX: Float
        public var pivotY: Float
        public var targetBlack: Float
        public var toePower: Float
        public var toeTransitionX: Float
        public var toeTransitionY: Float
        public var toeScale: Float
        public var needConvexToe: Bool
        public var toeFallbackCoefficient: Float
        public var toeFallbackPower: Float
        public var slope: Float
        public var intercept: Float
        public var targetWhite: Float
        public var shoulderPower: Float
        public var shoulderTransitionX: Float
        public var shoulderTransitionY: Float
        public var shoulderScale: Float
        public var needConcaveShoulder: Bool
        public var shoulderFallbackCoefficient: Float
        public var shoulderFallbackPower: Float
        public var lookLift: Float
        public var lookSlope: Float
        public var lookPower: Float
        public var lookSaturation: Float
        public var lookOriginalHueMixRatio: Float
        public var lookTuned: Bool
        public var restoreHue: Bool
    }

    static func epsilon() -> Float { 1e-6 }
    static func defaultGamma() -> Float { 2.2 }

    /// dt `_scale` (agx.c:531-557).
    public static func scale(
        limitX: Double, limitY: Double, transitionX: Double, transitionY: Double,
        slope: Double, power: Double
    ) -> Double {
        let projectedRise = slope * max(1e-6, limitX - transitionX)
        let actualRise = max(1e-6, limitY - transitionY)
        let tpr = pow(projectedRise, -power)
        let tar = pow(actualRise, -power)
        let base = max(1e-6, tar - tpr)
        return min(1e9, pow(base, -1.0 / power))
    }

    /// dt `_calculate_tone_mapping_params` in Double.
    public static func deriveCurve(_ p: Params) -> CurveDerivation {
        var d = CurveDerivation(
            blackRelativeEv: 0, rangeInEv: 0, curveGamma: 0, pivotX: 0, pivotY: 0,
            targetBlack: 0, toePower: 0, toeTransitionX: 0, toeTransitionY: 0,
            toeScale: 0, needConvexToe: false, toeFallbackCoefficient: 0,
            toeFallbackPower: 0, slope: 0, intercept: 0, targetWhite: 0,
            shoulderPower: 0, shoulderTransitionX: 0, shoulderTransitionY: 0,
            shoulderScale: 0, needConcaveShoulder: false,
            shoulderFallbackCoefficient: 0, shoulderFallbackPower: 0,
            lookLift: 0, lookSlope: 0, lookPower: 0, lookSaturation: 0,
            lookOriginalHueMixRatio: 0, lookTuned: false, restoreHue: false
        )

        // look
        d.lookLift = p.lookLift
        d.lookSlope = p.lookSlope
        d.lookSaturation = p.lookSaturation
        let brightness = Double(p.lookBrightness)
        d.lookPower = Float(brightness < 1 ? 1.0 / sqrt(max(brightness, 1e-6)) : 1.0 / brightness)
        d.lookOriginalHueMixRatio = p.lookOriginalHueMixRatio
        d.lookTuned = p.lookSlope != 1.0 || p.lookBrightness != 1.0
            || p.lookLift != 0.0 || p.lookSaturation != 1.0
        d.restoreHue = p.lookOriginalHueMixRatio != 0.0

        // log mapping
        d.blackRelativeEv = p.rangeBlackRelativeEv
        d.rangeInEv = p.rangeWhiteRelativeEv - p.rangeBlackRelativeEv

        // pivot + gamma
        let pivotX = min(max(Double(p.curvePivotX), 1e-6), 1.0 - 1e-6)
        d.pivotX = Float(pivotX)
        if p.autoGamma {
            d.curveGamma = Float(
                pivotX > 0 && Double(p.curvePivotYLinearOutput) > 0
                    ? log2(Double(p.curvePivotYLinearOutput)) / log2(pivotX)
                    : Double(p.curveGamma)
            )
        } else {
            d.curveGamma = p.curveGamma
        }

        func pivotYAtGamma(_ gamma: Double) -> Double {
            pow(max(
                Double(p.curveTargetDisplayBlackRatio),
                min(Double(p.curvePivotYLinearOutput), Double(p.curveTargetDisplayWhiteRatio))
            ), 1.0 / gamma)
        }
        let pivotY = pivotYAtGamma(Double(d.curveGamma))
        d.pivotY = Float(pivotY)

        // slope (gamma-compensated contrast)
        let rangeAdjustedSlope = Double(p.curveContrastAroundPivot) * (Double(d.rangeInEv) / 16.5)
        let pivotYDefault = pivotYAtGamma(2.2)
        let derivativeCurrent = Double(d.curveGamma)
            * pow(max(1e-6, pivotY), Double(d.curveGamma) - 1.0)
        let derivativeDefault = 2.2 * pow(max(1e-6, pivotYDefault), 2.2 - 1.0)
        d.slope = Float(rangeAdjustedSlope / (derivativeCurrent / derivativeDefault))

        // toe
        d.targetBlack = Float(pow(Double(p.curveTargetDisplayBlackRatio), 1.0 / Double(d.curveGamma)))
        d.toePower = max(0.01, p.curveToePower)
        let remainingYBelow = Double(d.pivotY) - Double(d.targetBlack)
        let toeLengthY = remainingYBelow * Double(p.curveLinearRatioBelowPivot)
        var dxBelow = toeLengthY / Double(d.slope)
        d.toeTransitionX = Float(max(1e-6, pivotX - dxBelow))
        dxBelow = pivotX - Double(d.toeTransitionX)
        let toeDyBelow = Double(d.slope) * dxBelow
        d.toeTransitionY = Float(Double(d.pivotY) - toeDyBelow)
        let inverseToeLimitX = 1.0
        let inverseToeLimitY = 1.0 - Double(d.targetBlack)
        let inverseToeTransitionX = 1.0 - Double(d.toeTransitionX)
        let inverseToeTransitionY = 1.0 - Double(d.toeTransitionY)
        d.toeScale = Float(-scale(
            limitX: inverseToeLimitX, limitY: inverseToeLimitY,
            transitionX: inverseToeTransitionX, transitionY: inverseToeTransitionY,
            slope: Double(d.slope), power: Double(d.toePower)
        ))
        let toeLengthX = Double(d.toeTransitionX)
        let toeDyToLimit = max(1e-6, Double(d.toeTransitionY) - Double(d.targetBlack))
        let toeSlopeToLimit = toeDyToLimit / toeLengthX
        d.needConvexToe = toeSlopeToLimit > Double(d.slope)
        d.toeFallbackPower = Float(toeSlopeToLimit * toeLengthX / toeDyToLimit)
        d.toeFallbackCoefficient = Float(toeDyToLimit / pow(toeLengthX, Double(d.toeFallbackPower)))
        d.intercept = Float(Double(d.toeTransitionY) - Double(d.slope) * Double(d.toeTransitionX))

        // shoulder
        d.targetWhite = Float(pow(Double(p.curveTargetDisplayWhiteRatio), 1.0 / Double(d.curveGamma)))
        let remainingYAbove = Double(d.targetWhite) - Double(d.pivotY)
        let shoulderLengthY = remainingYAbove * Double(p.curveLinearRatioAbovePivot)
        var dxAbove = shoulderLengthY / Double(d.slope)
        d.shoulderTransitionX = Float(min(1.0 - 1e-6, pivotX + dxAbove))
        dxAbove = Double(d.shoulderTransitionX) - pivotX
        let shoulderDyAbove = Double(d.slope) * dxAbove
        d.shoulderTransitionY = Float(Double(d.pivotY) + shoulderDyAbove)
        d.shoulderPower = max(0.01, p.curveShoulderPower)
        d.shoulderScale = Float(scale(
            limitX: 1.0, limitY: Double(d.targetWhite),
            transitionX: Double(d.shoulderTransitionX),
            transitionY: Double(d.shoulderTransitionY),
            slope: Double(d.slope), power: Double(d.shoulderPower)
        ))
        let shoulderLengthX = 1.0 - Double(d.shoulderTransitionX)
        let shoulderDyToLimit = max(1e-6, Double(d.targetWhite) - Double(d.shoulderTransitionY))
        let shoulderSlopeToLimit = shoulderDyToLimit / shoulderLengthX
        d.needConcaveShoulder = shoulderSlopeToLimit > Double(d.slope)
        d.shoulderFallbackPower = Float(shoulderSlopeToLimit * shoulderLengthX / shoulderDyToLimit)
        d.shoulderFallbackCoefficient = Float(
            shoulderDyToLimit / pow(shoulderLengthX, Double(d.shoulderFallbackPower))
        )
        return d
    }

    /// dt `_get_primaries_params` + `_create_matrices` — the four Float9
    /// matrices for the kernel buffer. `baseProfile` maps the agx enum
    /// onto the shared sigmoid profile table (work/Rec2020 → Rec2020;
    /// `exportProfile` falls back to the work profile — the export leg is
    /// the same Rec2020 in this pipeline).
    static func primariesMatrices(_ p: Params) -> (
        pipeToBase: [Float], baseToRendering: [Float],
        renderingToPipe: [Float], renderingToXYZ: [Float]
    ) {
        var insets = SIMD3<Double>(
            Double(p.redInset), Double(p.greenInset), Double(p.blueInset))
        var rotations = SIMD3<Double>(
            Double(p.redRotation), Double(p.greenRotation), Double(p.blueRotation))
        var outset = SIMD3<Double>(
            Double(p.redOutset), Double(p.greenOutset), Double(p.blueOutset))
        var unrotation = SIMD3<Double>(
            Double(p.redUnrotation), Double(p.greenUnrotation), Double(p.blueUnrotation))
        var masterOutset = Double(p.masterOutsetRatio)
        var masterUnrotation = Double(p.masterUnrotationRatio)
        if p.disablePrimariesAdjustments {
            insets = .zero
            rotations = .zero
            outset = .zero
            unrotation = .zero
        } else if p.completelyReversePrimaries {
            outset = insets
            unrotation = rotations
            masterOutset = 1
            masterUnrotation = 1
        }

        // Base profile: agx enum → sigmoid table. workProfile/Rec2020 both
        // hit Rec2020 == the work profile (pipe_to_base identity).
        let base: SigmoidBasePrimaries
        switch p.basePrimaries {
        case .workProfile, .exportProfile, .rec2020: base = .workProfile
        case .displayP3: base = .displayP3
        case .adobeRGB: base = .adobeRGB
        case .sRGB: base = .sRGB
        }
        let baseProfile = SigmoidProfile.profile(for: base)
        let workProfile = SigmoidProfile.rec2020

        // pipe → base (identity when base == work — dt's pointer-equality
        // branch).
        let pipeToBase: [[Double]]
        let baseToPipe: [[Double]]
        if base == .workProfile {
            pipeToBase = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
            baseToPipe = pipeToBase
        } else {
            pipeToBase = SigmoidPrimaries.matMul(baseProfile.xyzToRGB, workProfile.rgbToXYZ)
            baseToPipe = SigmoidPrimaries.matMul(workProfile.xyzToRGB, baseProfile.rgbToXYZ)
        }

        // inbound: custom₁ (inset + rotation) rendering primaries.
        var custom1 = [SIMD2<Double>](repeating: .zero, count: 3)
        for i in 0..<3 {
            custom1[i] = SigmoidPrimaries.rotateAndScalePrimary(
                baseProfile, scaling: 1.0 - insets[i], rotation: rotations[i], index: i)
        }
        let renderingToXYZ = SigmoidProfile.buildRGBToXYZ(primaries: custom1, white: baseProfile.white)
        // base → rendering = M_in(custom₁) · M_out(base).
        let baseToRendering = SigmoidPrimaries.matMul(renderingToXYZ, baseProfile.xyzToRGB)

        // outbound: custom₂ (outset + unrotation via the master ratios).
        var custom2 = [SIMD2<Double>](repeating: .zero, count: 3)
        for i in 0..<3 {
            let scaling = 1.0 - masterOutset * outset[i]
            custom2[i] = SigmoidPrimaries.rotateAndScalePrimary(
                baseProfile, scaling: scaling,
                rotation: masterUnrotation * unrotation[i], index: i)
        }
        let custom2ToXYZ = SigmoidProfile.buildRGBToXYZ(primaries: custom2, white: baseProfile.white)
        // rendering₂ → base = M_in(custom₂) · M_out(base); invert it.
        let baseToRendering2 = SigmoidPrimaries.matMul(custom2ToXYZ, baseProfile.xyzToRGB)
        let renderingToBase = SigmoidProfile.invert3(baseToRendering2)
        let renderingToPipe = SigmoidPrimaries.matMul(renderingToBase, baseToPipe)

        return (
            SigmoidPrimaries.flatten(pipeToBase),
            SigmoidPrimaries.flatten(baseToRendering),
            SigmoidPrimaries.flatten(renderingToPipe),
            SigmoidPrimaries.flatten(renderingToXYZ)
        )
    }

    // MARK: - IOPModule

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != params {
            let d = Self.deriveCurve(params)
            let m = Self.primariesMatrices(params)

            var floats = [Float](repeating: 0, count: Self.bufferFloatCount)
            floats[0] = d.blackRelativeEv
            floats[1] = d.blackRelativeEv + d.rangeInEv // max_ev (unused in kernel)
            floats[2] = d.rangeInEv
            floats[3] = d.curveGamma
            floats[4] = d.pivotX
            floats[5] = d.pivotY
            floats[6] = d.targetBlack
            floats[7] = d.toePower
            floats[8] = d.toeTransitionX
            floats[9] = d.toeTransitionY
            floats[10] = d.toeScale
            floats[11] = d.needConvexToe ? 1 : 0
            floats[12] = d.toeFallbackCoefficient
            floats[13] = d.toeFallbackPower
            floats[14] = d.slope
            floats[15] = d.intercept
            floats[16] = d.targetWhite
            floats[17] = d.shoulderPower
            floats[18] = d.shoulderTransitionX
            floats[19] = d.shoulderTransitionY
            floats[20] = d.shoulderScale
            floats[21] = d.needConcaveShoulder ? 1 : 0
            floats[22] = d.shoulderFallbackCoefficient
            floats[23] = d.shoulderFallbackPower
            floats[24] = d.lookLift
            floats[25] = d.lookSlope
            floats[26] = d.lookPower
            floats[27] = d.lookSaturation
            floats[28] = d.lookOriginalHueMixRatio
            floats[29] = d.lookTuned ? 1 : 0
            floats[30] = d.restoreHue ? 1 : 0
            floats.replaceSubrange(
                Self.pipeToBaseOffset..<Self.pipeToBaseOffset + 9, with: m.pipeToBase)
            floats.replaceSubrange(
                Self.baseToRenderingOffset..<Self.baseToRenderingOffset + 9, with: m.baseToRendering)
            floats.replaceSubrange(
                Self.renderingToPipeOffset..<Self.renderingToPipeOffset + 9, with: m.renderingToPipe)
            floats.replaceSubrange(
                Self.renderingToXYZOffset..<Self.renderingToXYZOffset + 9, with: m.renderingToXYZ)

            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: Self.bufferFloatCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!,
                        byteCount: Self.bufferFloatCount * MemoryLayout<Float>.size
                    )
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
        try await metal.dispatch2DTexture(
            functionName: AgXKernel.mainFunction,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }
}
