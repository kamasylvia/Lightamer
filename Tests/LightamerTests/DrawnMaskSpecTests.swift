@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-03 T3 — the drawn mask payload: sidecar spelling round-trip
/// (frozen ONE-WAY shape), the derived maskVersionHash (L013 explicit
/// folding), and the mask-plane cache key isolation (mask edit → mask
/// plane miss while every chain line stays a hit).
final class DrawnMaskSpecTests: XCTestCase {

    // ── fixtures ──

    /// Fixed UUIDs — the fixture is DETERMINISTIC (equal calls → equal
    /// specs → equal hashes; random ids would make the hash test tautology
    /// free but the equality claim empty).
    private static let ellipseID = UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!
    private static let gradientID = UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!
    private static let brushID = UUID(uuidString: "00000000-0000-0000-0000-00000000000c")!
    private static let pathID = UUID(uuidString: "00000000-0000-0000-0000-00000000000d")!
    private static let itemA = UUID(uuidString: "00000000-0000-0000-0000-00000000001a")!
    private static let itemB = UUID(uuidString: "00000000-0000-0000-0000-00000000001b")!

    private func makeDrawnSpec() -> MaskSpec {
        MaskSpec(
            version: 1,
            drawn: DrawnMaskSpec(
                forms: [
                    MaskForm(id: Self.ellipseID, kind: .ellipse(EllipseForm(
                        center: MaskPoint(x: 0.5, y: 0.5),
                        radiusX: 0.2, radiusY: 0.15,
                        rotationDegrees: 30, border: 0.1))),
                    MaskForm(id: Self.gradientID, kind: .gradient(GradientForm(
                        anchor: MaskPoint(x: 0.1, y: 0.9),
                        rotationDegrees: 45, compression: 0.25,
                        state: .sigmoidal))),
                    MaskForm(id: Self.brushID, kind: .brush(BrushStroke(
                        points: [
                            BrushPoint(
                                corner: MaskPoint(x: 0.2, y: 0.2),
                                ctrl1: MaskPoint(x: 0.25, y: 0.25),
                                ctrl2: MaskPoint(x: 0.3, y: 0.2)),
                            BrushPoint(
                                corner: MaskPoint(x: 0.4, y: 0.3),
                                ctrl1: MaskPoint(x: 0.35, y: 0.35),
                                ctrl2: MaskPoint(x: 0.4, y: 0.4)),
                        ],
                        radius: 0.05, hardness: 0.6, density: 0.8, opacity: 1.0))),
                    MaskForm(id: Self.pathID, kind: .path(PathForm(
                        nodes: [
                            PathNode(
                                corner: MaskPoint(x: 0.6, y: 0.6),
                                ctrl1: MaskPoint(x: 0.65, y: 0.6),
                                ctrl2: MaskPoint(x: 0.7, y: 0.65)),
                            PathNode(
                                corner: MaskPoint(x: 0.8, y: 0.8),
                                ctrl1: MaskPoint(x: 0.75, y: 0.75),
                                ctrl2: MaskPoint(x: 0.7, y: 0.8)),
                        ],
                        border: 0.02))),
                ],
                group: MaskGroupSpec(items: [
                    MaskGroupItem(formID: Self.itemA, op: .union, inverted: false, opacity: 1.0),
                    MaskGroupItem(formID: Self.itemB, op: .intersect, inverted: true, opacity: 0.5),
                ])))
    }

    // ── sidecar spelling round-trip ──

    /// drawn spec → sidecar record → JSON → decode → identical spec, and a
    /// second encode is BYTE-identical to the first (canonical writer —
    /// the frozen-spelling referee).
    func testDrawnPayloadSidecarRoundTrip() throws {
        let spec = makeDrawnSpec()
        let layer = AdjustmentLayer(name: "masked", mask: spec)
        let record = SidecarLayerRecord(layer)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SidecarLayerRecord.self, from: data)
        let restored = decoded.layer

        XCTAssertEqual(restored.mask, spec, "mask spec must survive the sidecar verbatim")
        // Byte stability is a CANONICAL-writer claim (L013: plain
        // JSONEncoder key order is unstable) — ParamsCoding sortedKeys.
        let canonical1 = ParamsCoding.encode(record)
        let canonical2 = ParamsCoding.encode(SidecarLayerRecord(restored))
        XCTAssertEqual(canonical1, canonical2, "canonical re-encode must be byte-stable")

        // The typed mask record path too.
        let maskRecord = SidecarMaskSpec(spec)
        let maskData = try JSONEncoder().encode(maskRecord)
        let maskBack = try JSONDecoder().decode(SidecarMaskSpec.self, from: maskData)
        XCTAssertEqual(maskBack.spec, spec)
    }

    /// A PRE-06-03 document (mask = `{version}` only) decodes with
    /// drawn == nil — the optional additive field is non-destructive
    /// (06-CONTEXT specifics; Phase2Sidecar 06-01 compat continues).
    func testPreDrawnDocumentDecodesCompatibly() throws {
        let json = #"{"version": 1}"#
        let record = try JSONDecoder().decode(
            SidecarMaskSpec.self, from: Data(json.utf8))
        XCTAssertEqual(record.version, 1)
        XCTAssertNil(record.drawn)
        XCTAssertNil(record.spec.drawn)
        XCTAssertFalse(record.spec.hasDrawnForms)
    }

    /// The 06-01 shell spelling (`{version}` without drawn) stays readable
    /// from a full layer record too, and a degraded unknown-op copy keeps
    /// the mask verbatim.
    func testLayerRecordKeepsMaskThroughDegrade() throws {
        let layer = AdjustmentLayer(name: "x", chain: [
            ModuleInstance(module: TestGainModule.self, params: TestGainModule.Params(gain: 1.5)),
        ], mask: makeDrawnSpec())
        let record = SidecarLayerRecord(layer)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SidecarLayerRecord.self, from: data)
        XCTAssertEqual(decoded.degraded().mask, decoded.mask)
    }

    // ── maskVersionHash (the derived identity) ──

    /// Equal specs hash equally (same process — the FNV contract gives
    /// cross-process stability by construction over canonical bytes).
    func testStableHashEqualSpecsEqualHashes() {
        let a = makeDrawnSpec()
        let b = makeDrawnSpec()
        XCTAssertEqual(a.stableHash(), b.stableHash())
        XCTAssertNotEqual(a.stableHash(), 0)
    }

    /// ANY payload edit flips the hash; the hash NEVER enters the spec
    /// itself (derived, not persisted).
    func testStableHashFlipsOnEveryPayloadEdit() {
        let base = makeDrawnSpec()

        var movedEllipse = base
        if case var .ellipse(e) = movedEllipse.drawn!.forms[0].kind {
            e.center = MaskPoint(x: 0.51, y: 0.5)
            movedEllipse.drawn!.forms[0].kind = .ellipse(e)
        }
        XCTAssertNotEqual(base.stableHash(), movedEllipse.stableHash(), "point move flips hash")

        var flippedState = base
        if case var .gradient(g) = flippedState.drawn!.forms[1].kind {
            g.state = .linear
            flippedState.drawn!.forms[1].kind = .gradient(g)
        }
        XCTAssertNotEqual(base.stableHash(), flippedState.stableHash(), "state flip flips hash")

        var hardness = base
        if case var .brush(b) = hardness.drawn!.forms[2].kind {
            b.hardness = 0.61
            hardness.drawn!.forms[2].kind = .brush(b)
        }
        XCTAssertNotEqual(base.stableHash(), hardness.stableHash(), "brush param flips hash")

        // Version field participates (NDE-3).
        var bumped = base
        bumped.version = 2
        XCTAssertNotEqual(base.stableHash(), bumped.stableHash(), "version bump flips hash")
    }

    // ── mask-plane cache key isolation ──

    private final class BuildCounter: @unchecked Sendable { var value = 0 }

    /// A mask edit (new stableHash) flips ONLY the mask key; the layer's
    /// chain line (same position/hash/roi shape, ≥ 0 positions) is a
    /// different key namespace and survives untouched.
    func testMaskKeyIsolationFromChainKeys() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let cache = PipeCache()
        let builds = BuildCounter()
        let imageID = UUID()
        let layerID = UUID()
        let roi = ROI(x: 0, y: 0, width: 4, height: 4, scale: 1.0)

        let specA = makeDrawnSpec()
        var specB = specA
        if case var .ellipse(e) = specB.drawn!.forms[0].kind {
            e.center = MaskPoint(x: 0.52, y: 0.5)
            specB.drawn!.forms[0].kind = .ellipse(e)
        }
        XCTAssertNotEqual(specA.stableHash(), specB.stableHash())

        let chainKey = PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: 2,
            upstreamHash: 4242, roi: roi, layerID: layerID)
        let maskKeyA = PipeCacheKey.maskKey(
            imageID: imageID, pipeType: .preview, layerID: layerID,
            maskHash: specA.stableHash(), roi: roi)
        let maskKeyB = PipeCacheKey.maskKey(
            imageID: imageID, pipeType: .preview, layerID: layerID,
            maskHash: specB.stableHash(), roi: roi)

        // Cold: chain + maskA both miss (compared > 0).
        var before = builds.value
        _ = try await cache.plane(for: chainKey, byteCount: 1024) { [metal, builds] in
            builds.value += 1
            return Self.tinyTexture(metal)
        }
        _ = try await cache.plane(for: maskKeyA, byteCount: 64) { [metal, builds] in
            builds.value += 1
            return Self.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value - before, 2, "防空转 guard: two cold misses")

        // The MASK EDIT: mask B misses (re-rasterize), chain line HITS
        // (the chain never saw the mask edit — independence proven by a
        // make-closure that does NOT run, L020 ③).
        before = builds.value
        _ = try await cache.plane(for: chainKey, byteCount: 1024) { [metal, builds] in
            builds.value += 1
            return Self.tinyTexture(metal)
        }
        _ = try await cache.plane(for: maskKeyB, byteCount: 64) { [metal, builds] in
            builds.value += 1
            return Self.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value - before, 1, "mask edit: chain hit + mask miss")
        // mask A is still resident (the edit ADDS a line, not a sweep).
        before = builds.value
        _ = try await cache.plane(for: maskKeyA, byteCount: 64) { [metal, builds] in
            builds.value += 1
            return Self.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value - before, 0, "old mask plane survives")

        // The mask key classifies into the maskPlane tier (enforceBudget).
        XCTAssertEqual(maskKeyA.layerTier, .maskPlane)
    }

    private static func tinyTexture(_ metal: MetalContext) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }
}
