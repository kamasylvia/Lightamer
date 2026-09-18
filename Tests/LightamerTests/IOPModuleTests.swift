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

    /// FOUND-03 + success criterion #3: `process` on known buffer contents
    /// is a true no-op — output == input bit-for-bit (float32 RGBA), the
    /// full buffer↔texture staging path included.
    func testPassthroughProcessIsNoOp() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        let width = 6, height = 4
        let byteCount = width * height * WorkingSpace.bytesPerPixel
        var input = [Float](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: input.count, by: 4) {
            input[index] = Float(index) / Float(input.count)
            input[index + 1] = 0.25
            input[index + 2] = 0.75
            input[index + 3] = 1.0
        }

        let inputBuffer = try XCTUnwrap(
            metal.device.makeBuffer(bytes: &input, length: byteCount, options: .storageModeShared)
        )
        let outputBuffer = try XCTUnwrap(
            metal.device.makeBuffer(length: byteCount, options: .storageModeShared)
        )
        memset(outputBuffer.contents(), 0, byteCount)

        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await PassthroughModule().process(
            input: inputBuffer, output: outputBuffer,
            roiIn: roi, roiOut: roi,
            piece: IOPiece(),
            metal: metal
        )

        let outFloats = outputBuffer.contents().bindMemory(to: Float.self, capacity: input.count)
        var output = [Float](repeating: 0, count: input.count)
        for index in 0..<input.count { output[index] = outFloats[index] }

        XCTAssertEqual(
            input.map { $0.bitPattern }, output.map { $0.bitPattern },
            "pass-through process must be a bit-exact no-op"
        )
    }
}
