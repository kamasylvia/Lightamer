import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// ACESccInModule / ACESccOutModule (Plan M2-5-1 T2, KD-2) — the ACEScc
// grade-domain envelope pair. Driver-constructed around each adjustment
// layer sub-run (D-M2-5-CONTEXT-3): NOT registered in the registry, NOT in
// sidecars, NOT on any add face — zero user-visible surface (AC#4). The
// constants live in ACESccMath.metal (the single constant source).
//
// The boxing condition is the checker-E2 narrowing: the effective chain
// must carry ≥1 grade-catalog op (GradeCatalog.item(opName:) query face —
// never a hand-copied whitelist). Pure non-catalog chains (develop/DRT/
// legacy ops only) pass through with zero cost.
// ─────────────────────────────────────────────────────────────────────────

/// The envelope entry (linear Rec2020 → ACEScc). opName matches the
/// LIGHTAMER V50Order row 20.5 (below exposure 21.0 — every catalog op
/// sorts inside the envelope).
public final class ACESccInModule: IOPModule {

    /// Constant op — no tunables.
    public struct Params: Codable, Hashable, Sendable {
        public init() {}
    }

    public static let opName = "acesccIn"

    public static let iopOrder: Float = 20.5

    public static let flags: IOPFlags = []

    public static let defaultColorspace: IOPColorspace = .RGB

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        // The constant hash (empty JSON) — this is what makes the envelope
        // cache-key-stable: levelHash folds ONLY paramsHash, so the same
        // chain hits the same keys across assemblies (KD-2).
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.inFunctionName,
            input: input,
            output: output
        )
    }
}

/// The envelope exit (ACEScc → linear Rec2020). Row 69.9 — the highest
/// below-floor position (terminal floor 70.0), so nothing escapes into the
/// display tail.
public final class ACESccOutModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        public init() {}
    }

    public static let opName = "acesccOut"

    public static let iopOrder: Float = 69.9

    public static let flags: IOPFlags = []

    public static let defaultColorspace: IOPColorspace = .RGB

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        try await metal.dispatch2DTexture(
            functionName: ACESccKernel.outFunctionName,
            input: input,
            output: output
        )
    }
}

/// Kernel names + bundle anchor (the ACESccConvert.metal pair).
public enum ACESccKernel {
    public static let inFunctionName = "grade_acescc_in"
    public static let outFunctionName = "grade_acescc_out"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// The driver seam installer (KD-2). `LayerCompositeDriver` lives in Core
/// which cannot import IOP (D-03) — IOP hands the boxing closure over at
/// populate time. The closure is pure over its input boxes and铸 a fresh
/// envelope pair per assembly (boxes are transient; plane keys ride the
/// layer UUID, hashes fold the constant envelope paramsHash).
public enum ACESccEnvelope {

    /// Whether this effective chain gets the envelope: ≥1 grade-catalog op
    /// (the checker-E2 narrowing — the GradeCatalog query face, never a
    /// copied whitelist).
    public static func needsEnvelope(_ boxes: [any ModuleBoxing]) -> Bool {
        boxes.contains(where: { GradeCatalog.item(opName: $0.opName) != nil })
    }

    /// The boxing itself: acesccIn + chain + acesccOut (v50 sort happens
    /// in the pipe walk — 20.5 first, 69.9 last by construction).
    public static func wrap(_ boxes: [any ModuleBoxing]) -> [any ModuleBoxing] {
        guard needsEnvelope(boxes) else { return boxes }
        return [
            ModuleBox(module: ACESccInModule(), instanceID: UUID()),
        ] + boxes + [ModuleBox(module: ACESccOutModule(), instanceID: UUID())]
    }

    /// Install the driver seam (called from `LightamerIOPRegistry.populate`
    /// — one line there; the default identity wrapper stays until install).
    public static func install() {
        LayerCompositeSeam.acesccEnvelope = Self.wrap
    }
}
