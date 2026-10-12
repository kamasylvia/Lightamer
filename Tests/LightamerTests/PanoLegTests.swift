@testable import LightamerCore
import CoreImage
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoLegTests (Plan M5-3-02 T4; KD-11 G1 leg-level closure) — the PRODUCTION
// pano leg driven through the service (synthetic decode legs + the REAL merge
// leg): the happy path (synthetic overlap scene lands `_pano.tif`), the G1
// leg-level bit-identity (double run, product bytes), the 3N+6 progress
// constant, the typed three-state vocabulary (disconnected / feature floor),
// the sRGB reimport domain (the REAL raster ingest chain), the provenance
// snapshot (canvas/gains/crop + the alignment labels), and the preview-gray
// drift guard (the fused buffer walk ≡ the 01 `rgbaEncoded` seam).
//
// FIXTURE: a blurred-LCG noise master (half-exact k/16 values — the
// CIContext RGBAh pass-through precondition) resampled through the TRUE
// rotation homographies (test-local H, the G2 anti-loop rule — deliberately
// no production warp code): noise neighborhoods are discriminative, so the
// REAL matching chain finds the true consensus (the PanoGoldenTests
// registered dot-field wrong-consensus finding is avoided by texture class,
// not by bypassing the chain). Every fixture lives in the TEMP domain with
// `defer` cleanup (L072).
// ─────────────────────────────────────────────────────────────────────────────

final class PanoLegTests: XCTestCase {

    private static let width = 720
    private static let height = 520
    private static let focal = 500.0
    private static let yaws: [Double] = [-10, 0, 10].map {
        $0 * Double.pi / 180
    }

    // MARK: - Fixtures

    /// The master texture, authored in the ENCODED domain then decoded:
    /// ~1000 varied dots (radius 2-8, encoded 0.78..0.96 per dot) on a
    /// noisy 0.10±0.04 encoded field — after the leg's in-place sRGB
    /// encode the preview carries the G1-class dot contrast (the
    /// probe-pinned fixture finding: authoring the texture directly in
    /// raw levels put the post-encode DoG contrast under the 0.0667 gate
    /// — 0 features; the decode-authoring restores it). The per-dot
    /// intensity/size variety + the noise context break the descriptor
    /// ties that produced the G2 wrong-consensus finding. All values
    /// k/64 (half-exact, 2^-6).
    private static func srgbDecode(_ encoded: Double) -> Double {
        let sign = encoded < 0 ? -1.0 : 1.0
        let value = abs(encoded)
        if value <= 0.04045 {
            return sign * value / 12.92
        }
        return sign * pow((value + 0.055) / 1.055, 2.4)
    }

    private static func masterTexture(seed: UInt64 = 0xA5A5_5A5A_0000_00F1)
        -> [Float] {
        let count = width * height
        var state: UInt64 = seed
        var noise = [Double](repeating: 0, count: count)
        for index in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            noise[index] = Double(state >> 11) / 9_007_199_254_740_992.0
        }
        var horizontal = [Double](repeating: 0, count: count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for d in -1...1 {
                    let xx = min(max(x + d, 0), width - 1)
                    sum += noise[y * width + xx]
                }
                horizontal[y * width + x] = sum / 3
            }
        }
        var smooth = [Double](repeating: 0, count: count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for d in -1...1 {
                    let yy = min(max(y + d, 0), height - 1)
                    sum += horizontal[yy * width + x]
                }
                smooth[y * width + x] = sum / 3
            }
        }
        var lows = smooth.min() ?? 0
        var highs = smooth.max() ?? 1
        var master = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let unit = (smooth[index] - lows) / (highs - lows)
            master[index] = srgbDecode(0.10 + (unit - 0.5) * 0.08)
        }
        let sizeClasses: [Int] = [2, 3, 4, 5, 6, 7, 8]
        for _ in 0..<1000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let cx = Int((state >> 33) % UInt64(width - 20)) + 10
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let cy = Int((state >> 33) % UInt64(height - 20)) + 10
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let radius = sizeClasses[Int((state >> 33) % 7)]
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let encoded = 0.78 + Double((state >> 40) % 190) / 1000.0
            let linear = srgbDecode(encoded)
            for dy in -radius...radius {
                for dx in -radius...radius {
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    let xx = min(max(cx + dx, 0), width - 1)
                    let yy = min(max(cy + dy, 0), height - 1)
                    master[yy * width + xx] = linear
                }
            }
        }
        return master.map { Float(($0 * 64).rounded()) / 64.0 }
    }

    /// The TRUE view-k homography (master pixel → view-k pixel, centered
    /// coords): H = K·R_k·R_0ᵀ·K⁻¹ with R_0 = identity.
    private static func homography(_ yaw: Double) -> Mat3D {
        let k = PanoCamera.calibrationK(focal: focal)
        let rotation = PanoCamera.rotation(fromAxisAngle: SIMD3(0, yaw, 0))
        return Mat3D.mul(Mat3D.mul(k, rotation), k.inverted()!)
    }

    /// One view plane: the master resampled through H⁻¹ (bilinear,
    /// border-filled), RGB half-exact, alpha 1. `seed` swaps the master
    /// (the disconnected fixture's independent scene).
    private static func viewPlane(_ yaw: Double, seed: UInt64) -> Data {
        let master = masterTexture(seed: seed)
        let centerX = (Double(width) - 1) / 2
        let centerY = (Double(height) - 1) / 2
        let inverse = homography(yaw).inverted() ?? Mat3D.identity
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let centered = inverse.project(
                    Double(x) - centerX, Double(y) - centerY)
                let mx = centered.x + centerX
                let my = centered.y + centerY
                let ix = Int(mx.rounded(.down))
                let iy = Int(my.rounded(.down))
                var value: Double
                if ix >= 0, ix < width - 1, iy >= 0, iy < height - 1 {
                    let fx = mx - Double(ix)
                    let fy = my - Double(iy)
                    let top = Double(master[iy * width + ix]) * (1 - fx)
                        + Double(master[iy * width + ix + 1]) * fx
                    let bottom = Double(master[(iy + 1) * width + ix]) * (1 - fx)
                        + Double(master[(iy + 1) * width + ix + 1]) * fx
                    value = top * (1 - fy) + bottom * fy
                } else {
                    // The out-of-bounds fill = the WRAPPED master sample
                    // (a flat fill zeroes the DoG contrast — the
                    // probe-pinned 0-feature finding for the away-facing
                    // fixture view).
                    let wx = ((ix % width) + width) % width
                    let wy = ((iy % height) + height) % height
                    value = Double(
                        master[min(wy, height - 1) * width + min(wx, width - 1)])
                }
                // The half-exact quantization (k/64).
                value = (value * 64).rounded() / 64.0
                let base = (y * width + x) * 4
                floats[base] = Float(value)
                floats[base + 1] = Float(value)
                floats[base + 2] = Float(value)
                floats[base + 3] = 1
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private final class PayloadKeep: @unchecked Sendable {
        var payloads: [Data] = []
    }

    /// The decode leg: source file `srcN.tif` → the Nth synthetic view.
    /// `independentLast` gives the LAST index a fully independent master
    /// (a different scene — the disconnected fixture: no correspondence
    /// can exist, and the view stays textured so the feature floor clears).
    private static func panoDecodeLeg(
        yaws: [Double], keep: PayloadKeep, independentLast: Bool = false
    ) -> StackDecodeLeg {
        { url in
            let stem = url.lastPathComponent
                .replacingOccurrences(of: "src", with: "")
                .replacingOccurrences(of: ".tif", with: "")
            let index = Int(stem) ?? 0
            let last = index == yaws.count - 1
            let seed: UInt64 = independentLast && last
                ? 0xDEAD_BEEF_0000_0007 : 0xA5A5_5A5A_0000_00F1
            let data = viewPlane(yaws[index], seed: seed)
            keep.payloads.append(data)
            let ci = CIImage(
                bitmapData: data, bytesPerRow: width * 16,
                size: CGSize(width: width, height: height),
                format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
            return DecodedImage(
                ciImage: ci, rawTech: RAWTechnicalParams(),
                capture: CaptureMetadata(), segmentationSkyMatte: nil,
                decoderVersionUsed: .v8)
        }
    }

    private static func flatDecodeLeg(keep: PayloadKeep) -> StackDecodeLeg {
        { url in
            var floats = [Float](
                repeating: 0.5, count: width * height * 4)
            for index in stride(from: 3, to: floats.count, by: 4) {
                floats[index] = 1
            }
            let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
            keep.payloads.append(data)
            let ci = CIImage(
                bitmapData: data, bytesPerRow: width * 16,
                size: CGSize(width: width, height: height),
                format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
            return DecodedImage(
                ciImage: ci, rawTech: RAWTechnicalParams(),
                capture: CaptureMetadata(), segmentationSkyMatte: nil,
                decoderVersionUsed: .v8)
        }
    }

    private func makeSources(_ count: Int, prefix: String) throws
        -> (dir: URL, sources: [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        var sources: [URL] = []
        for index in 0..<count {
            let url = dir.appendingPathComponent("src\(index).tif")
            try Data("fixture-\(index)".utf8).write(to: url)
            sources.append(url)
        }
        return (dir, sources)
    }

    private func makeService(decodeLeg: StackDecodeLeg?) throws
        -> StackMergeService {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        // mergeLeg: nil = the PRODUCTION legs (the leg under test).
        return try StackMergeService(
            device: device, decodeLeg: decodeLeg)
    }

    private static func awaitTerminal(
        _ service: StackMergeService, timeout: TimeInterval = 120
    ) async -> StackMergeService.JobSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let first = snapshots.first, first.state.isTerminal {
                return first
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private static func readSidecar(_ product: URL) throws -> [String: Any] {
        let sidecarURL = LightamerSidecar.sidecarURL(for: product)
        let data = try Data(contentsOf: sidecarURL)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - The happy path (KD-10)

    func testHappyPathLandsSrgbPanoProduct() async throws {
        let (dir, sources) = try makeSources(3, prefix: "pano-leg")
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = PayloadKeep()
        let service = try makeService(
            decodeLeg: Self.panoDecodeLeg(yaws: Self.yaws, keep: keep))
        _ = try await service.enqueue(
            kind: .pano, sources: sources, params: .init(tag: nil),
            sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .done(let product)? = terminal?.state else {
            XCTFail("expected .done, got \(String(describing: terminal?.state))")
            return
        }
        XCTAssertTrue(
            product.lastPathComponent.contains("_pano"),
            "the pano tag: \(product.lastPathComponent)")
        // The reimport domain (the REAL raster ingest chain — the sRGB tag
        // the leg declared rides the product).
        let decoded = try await RAWDecoder().decode(product)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.transfer, .srgbPiecewise)
        XCTAssertEqual(description.referral, .displayReferred)
        XCTAssertNotEqual(description.origin, .defaultSrgb)
        XCTAssertNotNil(description.profileHash, "the ICC rides the product")
        // The extent = the inner crop (the decoded CIImage carries it).
        let extent = decoded.ciImage.extent
        XCTAssertGreaterThan(extent.width, 0)
        XCTAssertGreaterThan(extent.height, 0)
        // The provenance snapshot (KD-9).
        let sidecar = try Self.readSidecar(product)
        let provenance = try XCTUnwrap(
            sidecar["provenance"] as? [String: Any])
        XCTAssertEqual(provenance["kind"] as? String, "pano-merge")
        let algorithm = try XCTUnwrap(provenance["algorithm"] as? [String: Any])
        XCTAssertEqual(
            algorithm["name"] as? String,
            ProvenanceReplay.panoAlgorithmName)
        XCTAssertEqual(
            algorithm["implementationVersion"] as? String,
            ProvenanceReplay.panoImplementationVersion)
        let params = try XCTUnwrap(algorithm["params"] as? [String: Any])
        let canvas = try XCTUnwrap(params["panoCanvas"] as? [Int])
        XCTAssertEqual(canvas.count, 2)
        XCTAssertGreaterThan(canvas[0], 0)
        XCTAssertGreaterThan(canvas[1], 0)
        let gains = try XCTUnwrap(params["panoGains"] as? [Double])
        XCTAssertEqual(gains.count, 3)
        XCTAssertEqual(gains[0], 1.0, accuracy: 1e-6, "the reference pin")
        let crop = try XCTUnwrap(params["panoCrop"] as? [Int])
        XCTAssertEqual(crop.count, 4)
        XCTAssertLessThanOrEqual(crop[2] - crop[0], canvas[0])
        XCTAssertLessThanOrEqual(crop[3] - crop[1], canvas[1])
        // The alignment vocabulary (KD-9).
        let alignment = try XCTUnwrap(provenance["alignment"] as? [String])
        XCTAssertEqual(alignment.count, 3)
        XCTAssertEqual(alignment[0], "reference")
        XCTAssertTrue(alignment[1].hasPrefix("inliers="))
        XCTAssertTrue(alignment[2].hasPrefix("inliers="))
        // The crop extent matches the sidecar crop rectangle.
        XCTAssertEqual(Int(extent.width), crop[2] - crop[0])
        XCTAssertEqual(Int(extent.height), crop[3] - crop[1])
    }

    // MARK: - G1 leg-level closure (KD-11)

    func testDoubleRunProductsBitIdentical() async throws {
        let (dir, sources) = try makeSources(3, prefix: "pano-leg-idem")
        defer { try? FileManager.default.removeItem(at: dir) }
        var products: [URL] = []
        for run in 0..<2 {
            let keep = PayloadKeep()
            let service = try makeService(
                decodeLeg: Self.panoDecodeLeg(yaws: Self.yaws, keep: keep))
            _ = try await service.enqueue(
                kind: .pano, sources: sources, params: .init(tag: nil),
                sessionRoot: dir)
            let terminal = await Self.awaitTerminal(service)
            guard case .done(let product)? = terminal?.state else {
                XCTFail("run \(run): expected .done, got "
                    + "\(String(describing: terminal?.state))")
                return
            }
            products.append(product)
        }
        // The collision increment lands distinct names; the BYTES match.
        XCTAssertNotEqual(products[0].lastPathComponent, products[1].lastPathComponent)
        let first = try Data(contentsOf: products[0])
        let second = try Data(contentsOf: products[1])
        XCTAssertEqual(first, second, "the product bytes diverged")
    }

    // MARK: - The progress constant (KD-10: 3N+6)

    func testProgressDoneEqualsTotal() async throws {
        let (dir, sources) = try makeSources(3, prefix: "pano-leg-prog")
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = PayloadKeep()
        let service = try makeService(
            decodeLeg: Self.panoDecodeLeg(yaws: Self.yaws, keep: keep))
        _ = try await service.enqueue(
            kind: .pano, sources: sources, params: .init(tag: nil),
            sessionRoot: dir)
        let declared = await service.progress()
        XCTAssertEqual(declared.total, 3 * 3 + 6)
        _ = await Self.awaitTerminal(service)
        let progress = await service.progress()
        XCTAssertEqual(progress.done, progress.total, "the closed window")
        XCTAssertEqual(progress.total, 15)
    }

    // MARK: - The typed vocabulary (KD-10)

    func testDisconnectedTypedFailure() async throws {
        // The 4th view faces AWAY (95°) — the reference BFS closure misses
        // it (the merge.py:238 semantics).
        let (dir, sources) = try makeSources(4, prefix: "pano-leg-disc")
        defer { try? FileManager.default.removeItem(at: dir) }
        let yaws = Self.yaws + [95 * Double.pi / 180]
        let keep = PayloadKeep()
        let service = try makeService(
            decodeLeg: Self.panoDecodeLeg(
                yaws: yaws, keep: keep, independentLast: true))
        _ = try await service.enqueue(
            kind: .pano, sources: sources, params: .init(tag: nil),
            sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed(let error)? = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        guard case .invalidParameter(let message) = error else {
            XCTFail("expected invalidParameter, got \(error)")
            return
        }
        XCTAssertTrue(
            message.hasPrefix(PanoMatch.FailurePrefix.disconnected),
            "the disconnected prefix: \(message)")
    }

    func testFeatureFloorTypedFailure() async throws {
        // One flat source: the detector finds nothing — the merge.py
        // :223-224 semantics, the alignment prefix.
        let (dir, sources) = try makeSources(3, prefix: "pano-leg-flat")
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = PayloadKeep()
        let service = try makeService(
            decodeLeg: { url in
                if url.lastPathComponent == "src2.tif" {
                    return try await Self.flatDecodeLeg(keep: keep)(url)
                }
                return try await Self.panoDecodeLeg(
                    yaws: Self.yaws, keep: keep)(url)
            })
        _ = try await service.enqueue(
            kind: .pano, sources: sources, params: .init(tag: nil),
            sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed(let error)? = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        guard case .invalidParameter(let message) = error else {
            XCTFail("expected invalidParameter, got \(error)")
            return
        }
        XCTAssertTrue(
            message.hasPrefix(PanoMatch.FailurePrefix.alignment),
            "the alignment prefix: \(message)")
        XCTAssertTrue(
            message.contains("features"),
            "the feature-floor wording: \(message)")
    }

    // MARK: - The preview-gray drift guard (checker minor-2)

    func testPreviewGrayFromEncodedMatchesPanoFeatureSeam() {
        // The fused buffer walk must be BIT-IDENTICAL to the 01
        // `rgbaEncoded` face (the duplication's negative pin).
        let width = 97
        let height = 61 // below the preview cap → the straight-luma arm
        var floats = [Float](repeating: 0, count: width * height * 4)
        var state: UInt64 = 0xC0FFEE
        for index in stride(from: 0, to: floats.count, by: 4) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Float(Double(state >> 11) / 9_007_199_254_740_992.0)
            floats[index] = value
            floats[index + 1] = value * 0.5
            floats[index + 2] = value * 0.25
            floats[index + 3] = 1
        }
        // The plane OWNS the pointer (its deinit deallocates — no test-side
        // free; the double free was the probe-pinned abort).
        let plane = StackRenderedPlane(
            pointer: UnsafeMutableRawPointer.allocate(
                byteCount: width * height * 16, alignment: 64),
            width: width, height: height, bytesPerRow: width * 16)
        plane.pointer.copyMemory(from: floats, byteCount: width * height * 16)
        let fused = StackMergeService.panoPreviewGrayFromEncoded(plane)
        let seam = PanoFeature.preparePreviewGray(
            rgbaEncoded: floats, width: width, height: height)
        XCTAssertEqual(fused.width, seam.width)
        XCTAssertEqual(fused.height, seam.height)
        for index in fused.pixels.indices {
            XCTAssertEqual(
                fused.pixels[index].bitPattern, seam.pixels[index].bitPattern,
                "pixel \(index) diverged")
        }
    }

    func testPreviewGrayDownsampleArmMatchesPanoFeatureSeam() {
        // The >1200 long-edge arm: the fused walk rides the same box
        // formulas — pinned bit-identical through the downsample too.
        let width = 1600
        let height = 120
        var floats = [Float](repeating: 0, count: width * height * 4)
        var state: UInt64 = 0xBEEF
        for index in stride(from: 0, to: floats.count, by: 4) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Float(Double(state >> 11) / 9_007_199_254_740_992.0)
            floats[index] = value
            floats[index + 1] = value * 0.5
            floats[index + 2] = value * 0.25
            floats[index + 3] = 1
        }
        let plane = StackRenderedPlane(
            pointer: UnsafeMutableRawPointer.allocate(
                byteCount: width * height * 16, alignment: 64),
            width: width, height: height, bytesPerRow: width * 16)
        plane.pointer.copyMemory(from: floats, byteCount: width * height * 16)
        let fused = StackMergeService.panoPreviewGrayFromEncoded(plane)
        let seam = PanoFeature.preparePreviewGray(
            rgbaEncoded: floats, width: width, height: height)
        XCTAssertEqual(fused.width, seam.width)
        XCTAssertEqual(fused.height, seam.height)
        for index in fused.pixels.indices {
            XCTAssertEqual(
                fused.pixels[index].bitPattern, seam.pixels[index].bitPattern,
                "pixel \(index) diverged")
        }
    }

    // MARK: - G3②: the feather band + the weight normalization (KD-11)

    func testFeatherAlphaBandProfile() {
        // The 12%-short-edge band table (merge.py:279-281): a 200×100
        // source (short edge 100 → the 12 px band): outside = 0; the left
        // edge starts at the 0.001 floor; 12 px in = full weight; deep
        // inside = 1.
        let source = PanoSourceGeometry(
            width: 200, height: 100, focal: 500,
            rotation: Mat3D.identity)
        let points: [(mx: Float, my: Float, expected: Float)] = [
            (-1, 50, 0),          // outside (left)
            (200, 50, 0),         // outside (right — mx ≤ w−1 fails)
            (0, 50, 1.0 / 12),    // edge = mx+1 = 1 → 1/12 (the floor is sub-pixel-unreachable)
            (6, 50, 7.0 / 12),    // edge+6 of the 12 px band
            (12, 50, 1),          // the band's end
            (100, 50, 1),         // deep inside
            (100, -0.5, 0),       // outside (top)
            (100, 99, 1.0 / 12),  // the bottom-edge band starts (h−my = 1)
        ]
        for point in points {
            let alpha = StackMergeService.panoFeatherAlpha(
                mx: point.mx, my: point.my, source: source)
            XCTAssertEqual(
                alpha, point.expected, accuracy: 0.01,
                "alpha(\(point.mx), \(point.my)): \(alpha)")
        }
    }

    func testFusedRowsWeightNormalizationProfile() throws {
        // Two constant-color sources (0.3 / 0.7, gains 1) over one shared
        // canvas: the fused rows must equal the α-weighted mean — single
        // cover = own color, deep overlap = 0.5, and source A's feather
        // edge inside the overlap reads ≈ B's color (α_A → the 0.001
        // floor). This pins `accum/max(weight,1e-8)` end to end.
        let sourceWidth = 120
        let sourceHeight = 90
        func constantSource(_ color: Float, yaw: Double)
            -> PanoSourceGeometry {
            PanoSourceGeometry(
                width: sourceWidth, height: sourceHeight,
                focal: 120, rotation: PanoCamera.rotation(
                    fromAxisAngle: SIMD3(0, yaw, 0)))
        }
        let geometries = [
            constantSource(0.3, yaw: -6 * Double.pi / 180),
            constantSource(0.7, yaw: 6 * Double.pi / 180),
        ]
        let canvas = try PanoWarp.boundedCanvas(
            sources: geometries,
            scale: PanoWarp.globalScale(focals: geometries.map(\.focal)))
        let staging = StackMergeService.StagedSet(
            count: 2, width: sourceWidth, height: sourceHeight)
        defer { staging.cleanUp() }
        for (index, color) in [Float(0.3), Float(0.7)].enumerated() {
            var floats = [Float](
                repeating: 0, count: sourceWidth * sourceHeight * 4)
            for index2 in stride(from: 0, to: floats.count, by: 4) {
                floats[index2] = color
                floats[index2 + 1] = color
                floats[index2 + 2] = color
                floats[index2 + 3] = 1
            }
            // The plane OWNS the pointer (its deinit deallocates — no
            // test-side free; the double free was the probe-pinned abort).
            let plane = StackRenderedPlane(
                pointer: UnsafeMutableRawPointer.allocate(
                    byteCount: sourceWidth * sourceHeight * 16,
                    alignment: 64),
                width: sourceWidth, height: sourceHeight,
                bytesPerRow: sourceWidth * 16)
            plane.pointer.copyMemory(
                from: floats, byteCount: sourceWidth * sourceHeight * 16)
            try staging.writePixels(
                plane, index: index)
        }
        let valid = StackMergeService.panoValidMask(
            sources: geometries, rois: canvas.rois, canvas: canvas)
        let rows = try StackMergeService.panoFuseRows(
            staging: staging, sources: geometries, rois: canvas.rois,
            gains: [1, 1], canvas: canvas,
            cropX0: 0, cropX1: canvas.width,
            firstRow: canvas.height / 2, rowCount: 4)
        let outWidth = canvas.width
        // The single-cover bands read each source's own color.
        var sawOwnA = false
        var sawOwnB = false
        var sawMean = false
        for x in 0..<outWidth {
            let base = (2 * outWidth + x) * 4 // the middle row of the band
            let value = rows[base]
            guard value > 0.01 else { continue }
            if abs(value - 0.3) < 0.02 { sawOwnA = true }
            if abs(value - 0.7) < 0.02 { sawOwnB = true }
            if abs(value - 0.5) < 0.03 { sawMean = true }
        }
        XCTAssertTrue(sawOwnA, "source A's single-cover band")
        XCTAssertTrue(sawOwnB, "source B's single-cover band")
        XCTAssertTrue(sawMean, "the deep-overlap mean")
        // The valid mask matches the fused support (weight > 0).
        var covered = 0
        for x in 0..<outWidth
        where rows[(2 * outWidth + x) * 4] > 0.01 { covered += 1 }
        var validCount = 0
        let maskRow = (canvas.height / 2 + 2) * canvas.width
        for x in 0..<canvas.width where valid[maskRow + x] == 1 {
            validCount += 1
        }
        XCTAssertEqual(covered, validCount, "valid = weight > 0")
    }

    func testTwoPassCropEqualsNaiveFullCanvasFusion() throws {
        // The KD-5 G3 pin: fusing ONLY the crop window (pass 2's bounded
        // walk) lands BYTE-IDENTICAL rows to fusing the FULL canvas (the
        // naive single-pass reference) and cropping afterwards — the
        // per-pixel math carries no cross-pixel state, so the read-window
        // bounds cannot move a bit.
        let sourceWidth = 120
        let sourceHeight = 90
        var geometries: [PanoSourceGeometry] = []
        for yaw in [-6.0, 6.0] {
            geometries.append(PanoSourceGeometry(
                width: sourceWidth, height: sourceHeight, focal: 120,
                rotation: PanoCamera.rotation(
                    fromAxisAngle: SIMD3(0, yaw * Double.pi / 180, 0))))
        }
        let canvas = try PanoWarp.boundedCanvas(
            sources: geometries,
            scale: PanoWarp.globalScale(focals: geometries.map(\.focal)))
        let staging = StackMergeService.StagedSet(
            count: 2, width: sourceWidth, height: sourceHeight)
        defer { staging.cleanUp() }
        for (index, color) in [Float(0.3), Float(0.7)].enumerated() {
            var floats = [Float](
                repeating: 0, count: sourceWidth * sourceHeight * 4)
            for index2 in stride(from: 0, to: floats.count, by: 4) {
                floats[index2] = color
                floats[index2 + 1] = color
                floats[index2 + 2] = color
                floats[index2 + 3] = 1
            }
            // The plane OWNS the pointer (its deinit deallocates).
            let plane = StackRenderedPlane(
                pointer: UnsafeMutableRawPointer.allocate(
                    byteCount: sourceWidth * sourceHeight * 16,
                    alignment: 64),
                width: sourceWidth, height: sourceHeight,
                bytesPerRow: sourceWidth * 16)
            plane.pointer.copyMemory(
                from: floats, byteCount: sourceWidth * sourceHeight * 16)
            try staging.writePixels(plane, index: index)
        }
        let valid = StackMergeService.panoValidMask(
            sources: geometries, rois: canvas.rois, canvas: canvas)
        let crop = try PanoCrop.innerCrop(
            valid: valid, width: canvas.width, height: canvas.height)
        // pass 2: the crop-window fusion (the production walk).
        let windowed = try StackMergeService.panoFuseRows(
            staging: staging, sources: geometries, rois: canvas.rois,
            gains: [1, 1], canvas: canvas,
            cropX0: crop.x0, cropX1: crop.x1,
            firstRow: crop.y0, rowCount: crop.height)
        // naive: the FULL canvas fused, then cropped.
        let full = try StackMergeService.panoFuseRows(
            staging: staging, sources: geometries, rois: canvas.rois,
            gains: [1, 1], canvas: canvas,
            cropX0: 0, cropX1: canvas.width,
            firstRow: 0, rowCount: canvas.height)
        for row in 0..<crop.height {
            for x in 0..<crop.width {
                let windowedIndex = (row * crop.width + x) * 4
                let fullIndex = ((crop.y0 + row) * canvas.width
                    + crop.x0 + x) * 4
                for channel in 0..<4 {
                    XCTAssertEqual(
                        windowed[windowedIndex + channel].bitPattern,
                        full[fullIndex + channel].bitPattern,
                        "pixel (\(x), \(row)) ch \(channel) diverged")
                }
            }
        }
    }

    func testFuseRowsBandSpanGuardAsymmetricOriginX() throws {
        // E-omp-1 regression (M5-3-02-ACCEPTANCE-OMP §五): the band-span X
        // guard in `panoFuseRows` compared WORLD-frame ROI edges against
        // CANVAS-LOCAL crop bounds — any non-zero originX opens a kill
        // band of width |originX| where whole sources are silently
        // skipped (the 196 MP probe lost 3/8 sources). The symmetric
        // fixtures above were a systematic blind spot: their source right
        // edges stay positive in the angle frame while |originX| is small,
        // so the kill band never intersects a covered column. This
        // fixture shifts the geometry (±10° yaw at f = 800 → originX =
        // −478) so the LEFT source's exclusive columns sit inside the
        // kill band (exclusive end 279 vs world right edge 199). Two legs:
        //   • boundary overlap — the band window lies in the left
        //     source's EXCLUSIVE span, right of its world-frame right
        //     edge: the buggy comparison kills the source and the window
        //     fuses black; the fixed guard keeps it and the single-cover
        //     columns read its own color.
        //   • disjoint — the band window lies past the left source's
        //     LOCAL right edge, covered only by the right source: both
        //     guards skip the genuinely disjoint left source, and the
        //     fixed guard must still keep the right source (pre-fix this
        //     window fused black too — the buggy comparison kills the
        //     right source there as well).
        // The color pins subsume the span.count > 0 chain: a skipped
        // source leaves its covered columns black (weight 0 → the
        // `max(weight, 1e-8)` normalize).
        let sourceWidth = 720
        let sourceHeight = 520
        // yaw +10° lands LEFT (local [0, 677)), yaw −10° lands RIGHT.
        func constantSource(_ color: Float, yaw: Double) -> PanoSourceGeometry {
            PanoSourceGeometry(
                width: sourceWidth, height: sourceHeight, focal: 800,
                rotation: PanoCamera.rotation(
                    fromAxisAngle: SIMD3(0, yaw * Double.pi / 180, 0)))
        }
        let geometries = [
            constantSource(0.3, yaw: 10),
            constantSource(0.7, yaw: -10),
        ]
        let canvas = try PanoWarp.boundedCanvas(
            sources: geometries,
            scale: PanoWarp.globalScale(focals: geometries.map(\.focal)))
        // The asymmetric shape the regression depends on (loud if the
        // fixture geometry ever drifts).
        let leftROI = canvas.rois[0]
        let rightROI = canvas.rois[1]
        let worldRightLeft = leftROI.x + leftROI.width
        let leftLocalRight = worldRightLeft - canvas.originX
        let rightLocalLeft = rightROI.x - canvas.originX
        XCTAssertLessThan(canvas.originX, 0, "asymmetric origin required")
        XCTAssertLessThan(worldRightLeft, rightLocalLeft, "exclusive-span window must exist")
        let staging = StackMergeService.StagedSet(
            count: 2, width: sourceWidth, height: sourceHeight)
        defer { staging.cleanUp() }
        for (index, color) in [Float(0.3), Float(0.7)].enumerated() {
            var floats = [Float](
                repeating: 0, count: sourceWidth * sourceHeight * 4)
            for index2 in stride(from: 0, to: floats.count, by: 4) {
                floats[index2] = color
                floats[index2 + 1] = color
                floats[index2 + 2] = color
                floats[index2 + 3] = 1
            }
            // The plane OWNS the pointer (its deinit deallocates).
            let plane = StackRenderedPlane(
                pointer: UnsafeMutableRawPointer.allocate(
                    byteCount: sourceWidth * sourceHeight * 16,
                    alignment: 64),
                width: sourceWidth, height: sourceHeight,
                bytesPerRow: sourceWidth * 16)
            plane.pointer.copyMemory(
                from: floats, byteCount: sourceWidth * sourceHeight * 16)
            try staging.writePixels(plane, index: index)
        }
        let firstRow = canvas.height / 2
        let rowCount = 4

        // Leg 1 — boundary overlap: the window starts right of the left
        // source's world-frame right edge (inside the pre-fix kill band)
        // but ends before the right source's local left edge, so every
        // window column is single-covered by the left source.
        let overlapX0 = (worldRightLeft + rightLocalLeft) / 2
        let overlapX1 = rightLocalLeft - 10
        XCTAssertGreaterThan(overlapX0, worldRightLeft, "inside the kill band")
        let overlapRows = try StackMergeService.panoFuseRows(
            staging: staging, sources: geometries, rois: canvas.rois,
            gains: [1, 1], canvas: canvas,
            cropX0: overlapX0, cropX1: overlapX1,
            firstRow: firstRow, rowCount: rowCount)
        let overlapWidth = overlapX1 - overlapX0
        for x in 0..<overlapWidth {
            let value = overlapRows[(2 * overlapWidth + x) * 4]
            XCTAssertEqual(
                value, 0.3, accuracy: 0.02,
                "left source's exclusive column \(overlapX0 + x) must read " +
                    "its own color, got \(value)")
        }

        // Leg 2 — disjoint: the window starts right of the left source's
        // LOCAL right edge (genuinely disjoint — both guards must skip
        // it) and is covered only by the right source.
        let disjointX0 = leftLocalRight + 20
        let disjointX1 = disjointX0 + 60
        XCTAssertLessThanOrEqual(leftLocalRight, disjointX0, "genuinely disjoint")
        let disjointRows = try StackMergeService.panoFuseRows(
            staging: staging, sources: geometries, rois: canvas.rois,
            gains: [1, 1], canvas: canvas,
            cropX0: disjointX0, cropX1: disjointX1,
            firstRow: firstRow, rowCount: rowCount)
        let disjointWidth = disjointX1 - disjointX0
        for x in 0..<disjointWidth {
            let value = disjointRows[(2 * disjointWidth + x) * 4]
            XCTAssertEqual(
                value, 0.7, accuracy: 0.02,
                "right-source-only column \(disjointX0 + x) must read the " +
                    "right source's own color, got \(value)")
        }
    }

    // MARK: - The streaming writer (KD-9)

    func testFloatTIFFWriterRowBandsRoundTripThroughImageIO() throws {
        // The strip TIFF reads back through CGImageSource with the exact
        // geometry, the sRGB profile, and byte-identical pixel rows.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pano-writer-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let product = dir.appendingPathComponent("writer_probe.tif")
        let width = 37
        let height = 11
        var rows = [Float](repeating: 0, count: width * height * 4)
        var state: UInt64 = 0x1234
        for index in stride(from: 0, to: rows.count, by: 4) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Float(Double(state >> 11) / 9_007_199_254_740_992.0)
            rows[index] = value
            rows[index + 1] = value * 0.75
            rows[index + 2] = value * 0.5
            rows[index + 3] = 1
        }
        let writer = try BandStreamer.FloatTIFFWriter(
            width: width, height: height, destination: product,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        // Three strips: 5 + 5 + 1 rows (the last shrinks).
        try writer.write(rows: Array(rows[0..<(5 * width * 4)]))
        try writer.write(rows: Array(rows[(5 * width * 4)..<(10 * width * 4)]))
        try writer.write(rows: Array(rows[(10 * width * 4)...]))
        try writer.finish()
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(
            product as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, width)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, height)
        // The pixel rows round-trip byte-exactly (float32 strip data).
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
            source, 0, nil))
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        let provider = image.dataProvider
        let data = try XCTUnwrap(provider?.data)
        XCTAssertEqual(CFDataGetLength(data), width * height * 16)
        let bytes = CFDataGetBytePtr(data)
        rows.withUnsafeBufferPointer { buffer in
            let expected = UnsafeRawBufferPointer(buffer)
            let actual = UnsafeRawBufferPointer(
                start: bytes!, count: expected.count)
            for index in stride(from: 0, to: expected.count, by: 4) {
                XCTAssertEqual(
                    actual.loadUnaligned(fromByteOffset: index, as: UInt32.self),
                    expected.loadUnaligned(fromByteOffset: index, as: UInt32.self),
                    "float bits at \(index / 4) diverged")
            }
        }
    }
}
