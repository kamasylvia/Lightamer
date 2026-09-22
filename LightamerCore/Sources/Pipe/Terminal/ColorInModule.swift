import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// ARCHITECTURE NOTE — Lightamer colorin ≠ Darktable colorin (02-RESEARCH §3.1;
// this note is verbatim-worthy and Phase 3 authors MUST read it):
//
// The pipeline input is CIRAW-DEVELOPED imagery encoded in linear Rec2020
// (demosaic + white balance + camera matrix + baseline exposure + tone are
// ALL applied inside CIRAW — Phase 1 spike evidence, `01-RESEARCH.md`
// Open Question #7). Darktable's colorin (`colorin.c:1184-1243`) converts
// camera-RGB → working space because its input is rawprepare-stage sensor
// data; Lightamer's input is ALREADY working-space data.
//
// ⚠ Consequence for Phase 3+: scene-referred iops (filmic, sigmoid,
// colorbalancergb) operate on DISPLAYED-DOMAIN data (developed + baseline
// exposure baked in), NOT true scene-linear — mathematically NOT equivalent
// to Darktable operating on scene-linear. Golden tolerances for Phase 3+
// algorithm ports must be calibrated to this (02-RESEARCH §3.1, Risk #1).
// ─────────────────────────────────────────────────────────────────────────────

/// Kernel-name constants for `TerminalKernels.metal` (Core's own
/// default.metallib — resolved through `MetalContext`'s library walk, which
/// loads `Bundle(for: MetalContextMarker.self)` first; no registration call
/// needed for Core's own kernels).
public enum TerminalKernels {

    /// Bit-identical float4 copy (`terminal_copy`).
    public static let copy = "terminal_copy"

    /// Linear-Rec2020 → linear-display-gamut 3×3 matrix
    /// (`colorout_matrix`, function-constant `isP3` specialization).
    public static let coloroutMatrix = "colorout_matrix"

    /// sRGB segmented TRC encode → `.bgra8Unorm` (`gamma_encode`).
    public static let gammaEncode = "gamma_encode"
}

/// The `colorin` terminal module (v50 order 28.0) — the IDENTITY member of
/// the terminal trio.
///
/// 职责收缩为三件事(02-RESEARCH §3.1):
/// 1. **确认/断言输入在 working space**(DEBUG assert — 见 `process`);
/// 2. **COLOR-04 参数位预留**:`Params.inputProfile`(Phase 13+ 注入
///    DCP-style 输入 profile;`nil` = 信任 CIRAW 的内嵌矩阵/working-space
///    编码 — `CIRAWFilter` 不接受外部 DCP,STACK.md 边界表);
/// 3. **保持管线形状**:Darktable v50 链 28.0 位次保留,phase 3 的
///    scene-referred iop 全部挂在该位次之后。
///
/// `process` 经 `terminal_copy` 做一次位等同拷贝 — 缓存平面
/// write-once-then-readonly(02-02 lock #7),恒等模块也必须产出自己的
/// 输出平面,不得别名。
///
/// Not `Sendable` by design (same contract as every module instance — owned
/// by its `ModuleBox` / pipe run isolation domain).
public final class ColorInModule: IOPModule {

    /// COLOR-04 reservation (Phase 13+ DCP-style input profile injection).
    /// `nil` = trust CIRAW's embedded/working-space encode (the only mode
    /// Phase 2 implements; a non-nil value today is a documented no-op —
    /// the parameter is persisted so sidecars survive the upgrade).
    public struct Params: Codable & Hashable, Sendable {
        public var inputProfile: String?

        public init(inputProfile: String? = nil) {
            self.inputProfile = inputProfile
        }
    }

    public static let opName = "colorin"

    /// v50 order 28.0 (V50Order table, verbatim Darktable position).
    public static let iopOrder: Float = 28.0

    public static let flags: IOPFlags = []

    /// colorin IS the working-space boundary — its output is linear
    /// Rec2020 by definition.
    public static let defaultColorspace: IOPColorspace = .RGB

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        // D-H4 atom: StableHash FNV-1a over the JSON-encoded params — the
        // reference shape (LightamerIOP `TestGainModule.commitParams`).
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
    }

    /// Identity ROI (a copy does not resample).
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
        // The working-space assertion (职责 1): the pipe hands us float32
        // RGBA linear-Rec2020 planes; in DEBUG, catch a format regression
        // at the module boundary (the FOUND-02 contract).
        #if DEBUG
        assert(
            input.pixelFormat == WorkingSpace.pixelFormat,
            "colorin expects \(WorkingSpace.pixelFormat.rawValue) input (FOUND-02), got \(input.pixelFormat.rawValue)"
        )
        // 04-03: upstream geometric modules (ashift 15.0 < colorin 28.0)
        // legitimately hand a RESIZED plane (rotation AABB) — the pipe
        // guarantees content/roi consistency, not same-size. The copy
        // below spans the OUTPUT plane (roiOut-sized by construction).
        #endif
        try await metal.dispatch2DTexture(
            functionName: TerminalKernels.copy,
            input: input,
            output: output
        )
    }
}
