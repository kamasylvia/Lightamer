@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// LensPerfProbeTests (Plan LENS-04 T5) — the 100MP lens dispatch budget
/// probe (skip-gated: LIGHTAMER_PERF_PROBE=1; the default suite SKIPS —
/// the skip delta is the probe family's declared cost).
///
/// DISCIPLINE (red line 8): every timing runs after a queue FENCE
/// (L014 — an unfenced GPU read is a fake number). The BUDGET BAND is
/// anchored to the ashift/flip warp family's live measurements on this
/// host (the same float32 full-plane dispatch class): the absolute ms
/// AND the relative factor against those anchors are both registered
/// (review m9 — no "same order" hand-waving).
final class LensPerfProbeTests: XCTestCase {

    /// 100MP = 11648×8580 (the GFX-class long-edge anchor).
    private let width = 11648
    private let height = 8580

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func makeTexture(_ metal: MetalContext, width: Int, height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        return try XCTUnwrap(metal.device.makeTexture(descriptor: desc))
    }

    private func uniforms(dc2: Float, scale: Float, source: String, target: String) -> LensWarpUniforms {
        LensWarpUniforms(
            dc1: 0, dc2: dc2, dc3: 0, dc4: 0,
            vr: 1.002, cr: 0, br: 0, vb: 0.998, cb: 0, bb: 0,
            vk1: -0.3, vk2: 0.1, vk3: 0,
            centerX: Float(width) / 2, centerY: Float(height) / 2, halfW: Float(width) / 2,
            oroiX: 0, oroiY: 0, iroiX: 0, iroiY: 0,
            inW: Int32(width), inH: Int32(height), scale: scale,
            sourceProjection: source, targetProjection: target)
    }

    private func dispatch(
        _ metal: MetalContext, input: MTLTexture, output: MTLTexture, uniforms: LensWarpUniforms
    ) async throws {
        var u = uniforms
        guard let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<LensWarpUniforms>.stride,
            options: .storageModeShared)
        else { throw XCTSkip("no Metal buffer") }
        try await metal.dispatch2DTexture(
            functionName: LensKernel.functionName, input: input, output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    private func timed(
        _ metal: MetalContext, input: MTLTexture, output: MTLTexture, uniforms: LensWarpUniforms,
        rounds: Int = 5
    ) async throws -> Double {
        // Warm-up + fence, then the fenced median (L014).
        try await dispatch(metal, input: input, output: output, uniforms: uniforms)
        await drain(metal)
        var samples: [Double] = []
        for _ in 0..<rounds {
            let t0 = Date()
            try await dispatch(metal, input: input, output: output, uniforms: uniforms)
            await drain(metal)
            samples.append(Date().timeIntervalSince(t0) * 1000)
        }
        return samples.sorted()[samples.count / 2]
    }

    /// The 100MP lens warp full-plane dispatch: the plain distortion face
    /// (scale=1, rectilinear pair — the budget-band anchor comparison).
    func testFullPlane100MPDistortionMs() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "perf probe family — LIGHTAMER_PERF_PROBE=1 to enable (skip delta declared)")
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height)
        let output = try makeTexture(metal, width: width, height: height)
        let ms = try await timed(
            metal, input: input, output: output,
            uniforms: uniforms(dc2: 0.05, scale: 1, source: "rectilinear", target: "rectilinear"))
        // The ashift/flip warp family anchor band (this host, float32
        // full-plane dispatch): ~40-120ms. Registered as the ABSOLUTE ms
        // + the anchor factor; a >3x excursion = the budget-band miss.
        print("PERF-LENS distortion-100MP: \(String(format: "%.1f", ms))ms")
        XCTAssertLessThan(ms, 400, "the warp-class budget-band ceiling (3x anchor)")
    }

    /// The projection-heavy face (fisheye pair through the fold) — the
    /// transcendental overhead over the plain face, same plane.
    func testFullPlane100MPProjectionMs() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "perf probe family — LIGHTAMER_PERF_PROBE=1 to enable")
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height)
        let output = try makeTexture(metal, width: width, height: height)
        let plain = try await timed(
            metal, input: input, output: output,
            uniforms: uniforms(dc2: 0.05, scale: 1, source: "rectilinear", target: "rectilinear"))
        let proj = try await timed(
            metal, input: input, output: output,
            uniforms: uniforms(dc2: 0.05, scale: 1, source: "fisheye", target: "rectilinear"))
        print("PERF-LENS projection-100MP: plain=\(String(format: "%.1f", plain))ms "
            + "proj=\(String(format: "%.1f", proj))ms "
            + "overhead=\(String(format: "%.2f", proj / max(plain, 0.1)))x")
        XCTAssertLessThan(proj, 500, "the projection-heavy ceiling (the transcendental pair)")
    }

    /// The memo face (LENS-01 T4's benefit proof): the second
    /// matchOutcome call with identical params must be ~free vs the first
    /// (the full-library scan).
    func testMemoHitsAreFreeVsFirstScan() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "perf probe family — LIGHTAMER_PERF_PROBE=1 to enable")
        let xml = """
        <lensdatabase version="1">
            <lens><maker>M</maker><model>Lens 0</model><cropfactor>1.5</cropfactor>\
            <calibration><distortion model="poly3" focal="16" k1="-0.01"/></calibration></lens>
        """ + (1..<40).map { i in
            """
            <lens><maker>M</maker><model>Lens \(i)</model><cropfactor>1.5</cropfactor>\
            <calibration><distortion model="poly3" focal="16" k1="-0.01"/></calibration></lens>
            """
        }.joined() + "</lensdatabase>"
        LensfunStore.install(db: LensfunDBLoader.parse(Data(xml.utf8)))
        defer { LensfunStore.uninstall() }
        var p = LensModule.Params(source: .lensfun, focalLength: 16, lensKey: "Lens 5")
        p.imageCrop = 1.5
        let t0 = Date()
        _ = LensfunStore.matchOutcome(p)
        let first = Date().timeIntervalSince(t0)
        let t1 = Date()
        _ = LensfunStore.matchOutcome(p)
        let second = Date().timeIntervalSince(t1)
        print("PERF-LENS memo: first=\(String(format: "%.3f", first * 1000))ms "
            + "second=\(String(format: "%.3f", second * 1000))ms")
        XCTAssertLessThan(second * 100, max(first * 1000, 0.1),
                          "the memo hit must be ~free vs the scan")
    }
}
