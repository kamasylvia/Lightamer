import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// FOUND-03: the `IOPModule` contract and its reference conformance
/// (`PassthroughModule`). GPU-dependent tests guard on device availability
/// per the VALIDATION "Metal compute requires a GPU context" rule. Public
/// surface only.
final class IOPModuleTests: XCTestCase {

    /// FOUND-03: `PassthroughModule` conforms to `IOPModule` with the locked
    /// static surface (`opName`, `iopOrder`, `flags`, `defaultColorspace`).
    /// `iopOrder` 50.5 sits between `shadhi` (50.0) and `zonesystem` (51.0)
    /// and must NOT collide with any V50Order entry (Plan 06 spike check).
    func testPassthroughModuleConforms() throws {
        let module = PassthroughModule()
        XCTAssertNotNil(module) // concrete instantiation = conformance compiles
        XCTAssertEqual(PassthroughModule.opName, "passthrough_spike")
        XCTAssertEqual(PassthroughModule.iopOrder, 50.5)
        XCTAssertEqual(PassthroughModule.flags, [])
        XCTAssertEqual(PassthroughModule.defaultColorspace, .RGB)
        // Position sanity inside the V50Order range.
        XCTAssertGreaterThanOrEqual(PassthroughModule.iopOrder, 1.0)
        XCTAssertLessThanOrEqual(PassthroughModule.iopOrder, 78.0)
        // Phase 1 spike order must not collide with any real module slot.
        XCTAssertFalse(
            V50Order.entries.contains { $0.order == PassthroughModule.iopOrder },
            "passthrough_spike 50.5 must not collide with any V50Order entry"
        )
    }

    /// FOUND-03: `PassthroughModule.Params` is `Codable` (JSON round-trip)
    /// and `Hashable` (equal params hash equal + stable across processes —
    /// the Phase 2 pipe-cache key contract).
    func testPassthroughParamsCodableAndHashable() throws {
        let params = PassthroughModule.Params()

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(PassthroughModule.Params.self, from: data)
        XCTAssertEqual(decoded, params, "JSON round-trip must be value-preserving")

        XCTAssertEqual(params.hashValue, params.hashValue, "hash stable within a process")
        XCTAssertEqual(params.hashValue, decoded.hashValue, "equal params hash equal")
        XCTAssertEqual(params, PassthroughModule.Params())
    }

    /// FOUND-03 + success criterion #3: `process` on known texture contents
    /// is a true no-op — output == input bit-for-bit (float32 RGBA) through
    /// the texture-domain `dispatch2DTexture` path (02-02 lock #1).
    func testPassthroughProcessIsNoOp() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        let width = 6, height = 4
        let bytesPerRow = width * WorkingSpace.bytesPerPixel
        var input = [Float](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: input.count, by: 4) {
            input[index] = Float(index) / Float(input.count)
            input[index + 1] = 0.25
            input[index + 2] = 0.75
            input[index + 3] = 1.0
        }

        func makeTexture(usage: MTLTextureUsage) -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: WorkingSpace.pixelFormat, width: width, height: height,
                mipmapped: false
            )
            d.usage = usage
            d.storageMode = .shared
            return metal.device.makeTexture(descriptor: d)!
        }
        let inputTexture = makeTexture(usage: [.shaderRead])
        let outputTexture = makeTexture(usage: [.shaderWrite])
        inputTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: input, bytesPerRow: bytesPerRow
        )

        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        var piece = IOPiece()
        try await PassthroughModule().process(
            input: inputTexture, output: outputTexture,
            roiIn: roi, roiOut: roi,
            piece: &piece,
            metal: metal
        )
        // Drain: a command buffer committed after the kernel completes only
        // when the kernel has (same-queue FIFO).
        let drain = try XCTUnwrap(metal.commandQueue.makeCommandBuffer())
        drain.commit()
        await drain.completed()

        var output = [Float](repeating: -1, count: input.count)
        outputTexture.getBytes(
            &output, bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
        )

        XCTAssertEqual(
            input.map { $0.bitPattern }, output.map { $0.bitPattern },
            "pass-through process must be a bit-exact no-op"
        )
    }

    // MARK: - 04-01-T2: erased ROI forwarding round-trip

    /// Non-trivial ROI geometry probe (CPU-only — process is never called):
    /// shrink out by 2px per axis, expand in by 2px per axis.
    private struct ShrinkROIProbe: IOPModule {
        struct Params: Codable, Hashable {}
        static var opName: String { "roiprobe_stub" }
        static var iopOrder: Float { 10.0 }
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        func reloadDefaults(image: DecodedImage) async -> Params { Params() }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            roi = input
            roi.width = max(1, roi.width - 2)
            roi.height = max(1, roi.height - 2)
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            input = roi
            input.width += 2
            input.height += 2
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {}
    }

    /// 04-01-T2: `modifyROIOutErased` forwards through the box to the module.
    func testModifyROIOutErasedForwards() {
        let box = ModuleBox(module: ShrinkROIProbe())
        var out = ROI(x: 0, y: 0, width: 10, height: 8, scale: 1.0)
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 10, height: 8, scale: 1.0),
            piece: IOPiece()
        )
        XCTAssertEqual(out.width, 8, "erased forward must reach the module")
        XCTAssertEqual(out.height, 6)
    }

    /// 04-01-T2: `modifyROIInErased` forwards through the box to the module.
    func testModifyROIInErasedForwards() {
        let box = ModuleBox(module: ShrinkROIProbe())
        var input = ROI()
        box.modifyROIInErased(
            output: ROI(x: 0, y: 0, width: 10, height: 8, scale: 1.0),
            input: &input, piece: IOPiece()
        )
        XCTAssertEqual(input.width, 12, "erased backward must reach the module")
        XCTAssertEqual(input.height, 10)
    }

    /// 04-01-T2: a default-identity box is a no-op through the erased seam
    /// (every Phase 1-3 module stays byte-identical under negotiation).
    func testDefaultIdentityBoxErasedIsNoOp() {
        let box = ModuleBox(module: PassthroughModule())
        let full = ROI(x: 0, y: 0, width: 10, height: 8, scale: 1.0)
        var out = ROI()
        box.modifyROIOutErased(&out, input: full, piece: IOPiece())
        XCTAssertEqual(out, full, "identity forward must pass through")
        var input = ROI()
        box.modifyROIInErased(output: full, input: &input, piece: IOPiece())
        XCTAssertEqual(input, full, "identity backward must pass through")
    }
}
