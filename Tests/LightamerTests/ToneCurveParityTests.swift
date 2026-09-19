@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// ToneCurveParityTests (Plan 03-03-T3) — IOP-TONE-03.
//
// REFERENCE PROVENANCE: synthesized references (gen_fixtures.py refs,
// tonecurve section — the float64 evaluation of the documented shared
// semantic over the canonical fixtures). dt-cli probe route UNAVAILABLE
// for the Lab chain in this build (same piece-state corruption finding as
// colisa: the XMP IS adopted — tonecurve v5 blob `params ok`, 520-byte
// op_params in the library DB — but the export emits identity output for
// an S-curve case whose semantic value is 0.68). Parity gates: ParityGate
// dual gate (≥99.9% < 1e-5 relative with 1e-5 abs floor + 2e-4 envelope).
final class ToneCurveParityTests: XCTestCase {

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`bash input/golden/regenerate.sh` (Plan 03-03)"
            )
        }
        return url
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Case table (mirrors gen_fixtures.py TONECURVE_CASES)

    private static let sNodes: [ToneCurveModule.Node] = [
        .init(x: 0, y: 0), .init(x: 0.25, y: 0.15), .init(x: 0.5, y: 0.5),
        .init(x: 0.75, y: 0.85), .init(x: 1, y: 1),
    ]
    private static let abNodes: [ToneCurveModule.Node] = [
        .init(x: 0, y: 0), .init(x: 0.5, y: 0.5), .init(x: 1, y: 1),
    ]

    private var cases: [(name: String, params: ToneCurveModule.Params)] {
        [
            ("tonecurve_identity", ToneCurveModule.Params()),
            ("tonecurve_s_manual", ToneCurveModule.Params(
                curveL: Self.sNodes, curveA: Self.abNodes, curveB: Self.abNodes,
                autoscaleAb: .manual, unboundAb: true, preserveColors: .average)),
            ("tonecurve_s_rgb", ToneCurveModule.Params(
                curveL: Self.sNodes, curveA: Self.abNodes, curveB: Self.abNodes,
                autoscaleAb: .rgbLinked, unboundAb: true, preserveColors: .average)),
            ("tonecurve_perchannel", ToneCurveModule.Params(
                curveL: Self.sNodes, curveA: Self.abNodes, curveB: Self.abNodes,
                autoscaleAb: .rgbLinked, unboundAb: true, preserveColors: .none)),
        ]
    }

    // MARK: - CPU LUT unit tests

    /// Identity nodes → identity table within the sampling-grid resolution
    /// (the k/65535-vs-k/65536 grid mismatch bounds the error at 100/65535).
    func testIdentityNodesGiveIdentityLUT() {
        let table = ToneCurveLUT.buildTable(
            nodes: [(0, 0), (1, 1)], type: .monotoneHermite
        )
        for k in stride(from: 0, to: ToneCurveLUT.resolution, by: 977) {
            XCTAssertEqual(
                table[k], Double(k) / Double(ToneCurveLUT.resolution - 1),
                accuracy: 1.6e-5, "table[\(k)]"
            )
        }
    }

    /// Hermite monotonicity: random strictly-monotone node sets produce a
    /// monotone table (no overshoot).
    func testMonotoneHermiteNoOvershoot() {
        var seed: UInt64 = 0x74c0de
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        for _ in 0..<200 {
            var xs = [Double](repeating: 0, count: 6)
            for i in 1..<6 { xs[i] = xs[i - 1] + next() * 0.2 + 0.01 }
            var ys = [Double](repeating: 0, count: 6)
            for i in 1..<6 { ys[i] = ys[i - 1] + next() * 0.25 }
            let table = ToneCurveLUT.buildTable(nodes: Array(zip(xs, ys)), type: .monotoneHermite)
            for k in 1..<table.count {
                XCTAssertGreaterThanOrEqual(
                    table[k] + 1e-12, table[k - 1],
                    "overshoot at \(k) (nodes \(xs) \(ys))"
                )
            }
        }
    }

    /// The three interpolators agree on collinear nodes (all reduce to the
    /// straight line — the tridiagonal solver / tangents degenerate linearly).
    func testCollinearNodesAcrossAllTypes() {
        let nodes = [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0)]
        for type in [ToneCurveLUT.CurveType.monotoneHermite, .catmullRom, .cubicSpline] {
            let table = ToneCurveLUT.buildTable(nodes: nodes, type: type)
            for k in stride(from: 0, to: ToneCurveLUT.resolution, by: 733) {
                XCTAssertEqual(
                    table[k], Double(k) / Double(ToneCurveLUT.resolution - 1),
                    accuracy: 1.7e-5, "\(type) table[\(k)]"
                )
            }
        }
    }

    /// Extrapolation continuity: the power-law fit is anchored at
    /// (x_last, y(x_last)) — eval at 1.0 continues the table end.
    func testExtrapolationContinuity() {
        let tables = ToneCurveLUT.commit(
            nodesL: Self.sNodes.map { (Double($0.x), Double($0.y)) },
            nodesA: Self.abNodes.map { (Double($0.x), Double($0.y)) },
            nodesB: Self.abNodes.map { (Double($0.x), Double($0.y)) },
            typeL: .monotoneHermite, typeA: .monotoneHermite, typeB: .monotoneHermite,
            autoscaleAb: .manual
        )
        let anchor = tables.tableL[ToneCurveLUT.resolution - 1]
        XCTAssertEqual(IOPExpFit.evalD(tables.coeffsL, 1.0), anchor, accuracy: 1e-3)
        // Beyond the anchor the fit is finite and increasing (S-curve).
        let beyond = IOPExpFit.evalD(tables.coeffsL, 1.2)
        XCTAssertGreaterThan(beyond, anchor)
        // a/b left fits live in the MIRRORED coordinate (eval input is
        // 1 − a_in): at a_in = 0 the eval input is 1.0 and must reproduce
        // the mirrored anchor y0 = table_A[first-node sample] = −128.
        XCTAssertEqual(IOPExpFit.evalD(tables.coeffsALeft, 1.0),
                       tables.tableA[0], accuracy: 1e-3)
    }

    /// The RGB-linked derivation turns the L table into a G→G mapping that
    /// is identity for an identity curve (within the round-trip noise).
    func testRGBLinkedDerivationIdentity() {
        let tables = ToneCurveLUT.commit(
            nodesL: [(0, 0), (1, 1)],
            nodesA: Self.abNodes.map { (Double($0.x), Double($0.y)) },
            nodesB: Self.abNodes.map { (Double($0.x), Double($0.y)) },
            typeL: .monotoneHermite, typeA: .monotoneHermite, typeB: .monotoneHermite,
            autoscaleAb: .rgbLinked
        )
        for k in stride(from: 0, to: ToneCurveLUT.resolution, by: 499) {
            XCTAssertEqual(
                tables.tableL[k], Double(k) / Double(ToneCurveLUT.resolution - 1),
                accuracy: 5e-5, "derived G table[\(k)]"
            )
        }
    }

    // MARK: - Track A: kernel vs the synthesized references

    private static let trackAFixtures = [
        "stair_1d", "ramp_8ev", "gray_staircase", "flat_0ev", "saturated",
    ]

    func testToneCurveGoldenParity() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runToneCurvePipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size mismatch")
                    continue
                }
                if let message = ParityGate.failureMessage(
                    "\(caseName)×\(fixture)", pipe, golden.rgb
                ) {
                    failures.append(message)
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "tonecurve track A FAILED:\n" + failures.prefix(6).joined(separator: "\n"))
    }

    private func runToneCurvePipe(
        image: DecodedImage, params: ToneCurveModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let tonecurve = await registry.makeBox(opName: ToneCurveModule.opName)
        let tonecurveBox = try XCTUnwrap(tonecurve as? ModuleBox<ToneCurveModule>)
        await tonecurveBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), tonecurveBox]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return (rgb, texture.width, texture.height)
    }

    // MARK: - Track B: identity tonecurve inserted

    func testTrackBNeutralityWithToneCurveInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let tonecurve = await registry.makeBox(opName: ToneCurveModule.opName)
        let tonecurveBox = try XCTUnwrap(tonecurve as? ModuleBox<ToneCurveModule>)
        await tonecurveBox.setParams(.init()) // identity curves
        chain.append(tonecurveBox)
        chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        let rgb8 = try XCTUnwrap(texture.pixelFormat == .bgra8Unorm ? texture : nil)
        var bytes = [UInt8](repeating: 0, count: rgb8.width * rgb8.height * 4)
        bytes.withUnsafeMutableBytes {
            rgb8.getBytes(
                $0.baseAddress!, bytesPerRow: rgb8.width * 4,
                from: MTLRegionMake2D(0, 0, rgb8.width, rgb8.height), mipmapLevel: 0
            )
        }
        var failures: [String] = []
        for patch in Fixtures.neutralPatches {
            let cx = Int(patch.x * Double(rgb8.width - 1))
            let cy = Int(patch.y * Double(rgb8.height - 1))
            var rs = 0, gs = 0, bs = 0, n = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(cx + dx, 0), rgb8.width - 1)
                    let y = min(max(cy + dy, 0), rgb8.height - 1)
                    let p = (y * rgb8.width + x) * 4
                    rs += Int(bytes[p + 2]); gs += Int(bytes[p + 1]); bs += Int(bytes[p])
                    n += 1
                }
            }
            let (r, g, b) = (Double(rs) / Double(n), Double(gs) / Double(n), Double(bs) / Double(n))
            if abs(r - g) >= 2 || abs(g - b) >= 2 {
                failures.append("\(patch.name): |R−G|=\(abs(r - g)) |G−B|=\(abs(g - b))")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "track B neutrality with tonecurve inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Registration

    func testToneCurveRegisteredAtV50Slot48() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: ToneCurveModule.opName)
        _ = try XCTUnwrap(box as? ModuleBox<ToneCurveModule>)
        XCTAssertEqual(ToneCurveModule.opName, "tonecurve")
        XCTAssertEqual(ToneCurveModule.iopOrder, 48.0)
        XCTAssertEqual(ToneCurveModule.defaultColorspace, .Lab)
        let id = UUID()
        let restored = await registry.makeBox(opName: ToneCurveModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
