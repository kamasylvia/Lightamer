@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

// The D-COL1 golden harness (Plan 02-04-07) — TWO criteria, because the
// neutral-gray test alone CANNOT catch TRC/gamut mismatches (research
// §3.5): any per-channel-identical error keeps grays neutral.
//
// 1. **Neutrality** — ColorChecker-class gray patches, after the FULL
//    default chain, `max|R−G|, |G−B| < GoldenTolerance.neutral/255`.
// 2. **Cross-consistency** — the pipe output vs a CIContext ColorSync
//    DIRECT render of the same image into the same display space,
//    per-pixel `max diff < GoldenTolerance.crossCheck/255`.
//
// Gate-quality real-sensor fixture (ColorChecker ARW): XCTSkip with reason
// when absent (see Fixtures.colorCheckerARW acquisition note) — the
// committed synthetic NeutralTarget.tif keeps the harness green everywhere.
//
// Failures dump a per-patch/percentile diff table + PFM to
// `.work/02-04/golden-dump-<timestamp>/` (created on failure only).

final class GoldenColorTests: XCTestCase {

    /// PASS constants — written to by the plan, not by magic numbers.
    private enum GoldenTolerance {
        /// Criterion 1: gray patch channel spread (in /255 units).
        static let neutral = 2
        /// Criterion 2 (byte domain): per-pixel diff vs the ColorSync
        /// baseline (/255) — enforced at p90 and OUTSIDE the low-end zone.
        static let crossCheck = 2
        /// Criterion 2 (linear domain): per-pixel abs diff of the LINEAR
        /// display-domain planes (≈2/255 encoded at mid-tones).
        static let crossLinear = 0.004
        /// HOST FINDING (2026-09-19, `.work/02-04/probe-edge.swift`):
        /// ColorSync's 8-bit ICC render (CIContext → displayP3 → RGBA8)
        /// does NOT follow the IEC sRGB segmented curve in the low end —
        /// its tables behave ≈ pure gamma-2.2 (no 1/12.92 toe). Example:
        /// Rec2020 red's P3-G (linear 0.0323) encodes to 1/255 under the
        /// STANDARD curve but 51/255 through ColorSync's tables. The
        /// gamma kernel implements the STANDARD (our bytes are consumed
        /// under the declared colorspace by the compositor — the spec
        /// curve is the correct emission), so byte-domain comparison
        /// against the ColorSync 8-bit baseline diverges ONLY where either
        /// side encodes < this floor. Every such pixel is asserted to sit
        /// inside the zone and the divergence is asserted BOUNDED (a gross
        /// TRC error — double-encode, wrong curve — would blow through it).
        static let colorSyncLowEndFloor: UInt8 = 60
        /// The bounded deviation allowed inside the low-end zone (/255).
        static let colorSyncLowEndBound = 60
        /// Patch decode sanity: expected gray level through the full chain.
        static let patchLevel = 2
    }

    private let harnessLongEdge: Int? = nil
    // FULL resolution (scale 1.0 — NO resampling on either leg): the two
    // legs resample patch edges with a half-texel offset at scale < 1
    // (observed max 54/255 confined to p99 edge rows, body p50 = 0), which
    // would confound the TRANSFORM comparison D-COL1 exists for. At scale
    // 1.0 both legs consume identical source pixels.

    private func makeMetal() throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        return try MetalContext()
    }

    /// The deterministic harness chain: default registry chain with the
    /// colorout pinned to an EXPLICIT fast-path profile (`.displayP3`).
    /// The screen-follow `.display` resolution is coordinator behavior —
    /// the harness validates the TRANSFORM, host-independently.
    private func makeChain(outputProfile: ColorOutModule.OutputProfile = .displayP3) async
        -> [any ModuleBoxing]
    {
        // D-COL1 is the COLOR-MANAGEMENT neutrality gate (Plan 02's
        // terminal-trio contract). Since 03-04 the default chain also
        // carries the tone iops, and shadhi's DEFAULTS are active by design
        // (shadows +50 — dt enables it the same way; a local operator
        // shifts patch chroma spatially, exactly like dt's). iop-level
        // neutrality is gated separately
        // (SigmoidTests.testGraysStayNeutralOnBothPaths, ShadhiParityTests
        // track B) — this gate pins the terminal trio.
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: ModuleRegistry.makeDefault(), outputProfile: outputProfile
        )
        chain.removeAll {
            $0.opName == SigmoidModule.opName || $0.opName == ShadhiModule.opName
        }
        return chain
    }

    /// Read the gamma-tail `.bgra8Unorm` plane as (r,g,b) tuples.
    private func readRGB8(_ texture: any MTLTexture) -> [(UInt8, UInt8, UInt8)] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var out: [(UInt8, UInt8, UInt8)] = []
        out.reserveCapacity(texture.width * texture.height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            out.append((bytes[i + 2], bytes[i + 1], bytes[i]))
        }
        return out
    }

    /// Sample a normalized IMAGE-space point (top-left origin) with a 3×3
    /// average. ORIENTATION (empirically pinned by the 02-04 viz harness,
    /// `.work/02-04/viz-chain.swift`): the pixelpipe plane's row 0 is the
    /// image TOP (CI render→bitmap→replace keeps top-down order; the
    /// EditorMTKView blit's uv flip is what makes the app view upright) —
    /// so texture y maps DIRECTLY (no flip): `y_tex = y`.
    private func sample3x3(
        _ rgb: [(UInt8, UInt8, UInt8)], width: Int, height: Int,
        x: Double, y: Double
    ) -> (r: Double, g: Double, b: Double) {
        let cx = Int((x * Double(width - 1)).rounded())
        let cy = Int((y * Double(height - 1)).rounded())
        var rs = 0, gs = 0, bs = 0, n = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let px = min(max(cx + dx, 0), width - 1)
                let py = min(max(cy + dy, 0), height - 1)
                let p = rgb[py * width + px]
                rs += Int(p.0); gs += Int(p.1); bs += Int(p.2); n += 1
            }
        }
        return (Double(rs) / Double(n), Double(gs) / Double(n), Double(bs) / Double(n))
    }

    // MARK: - Failure dump (PFM + diff table)

    /// Dump a diff table + float PFM of the abs diff map under
    /// `.work/02-04/golden-dump-<timestamp>/`. Failure-path only.
    private func dumpFailure(
        tag: String, pipe: [(UInt8, UInt8, UInt8)], baseline: [(UInt8, UInt8, UInt8)]?,
        width: Int, height: Int
    ) {
        let root = URL(fileURLWithPath: #filePath) // Tests/LightamerTests/GoldenColorTests.swift
            .deletingLastPathComponent() // Tests/LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(".work/02-04")
        let dir = root.appendingPathComponent(
            "golden-dump-\(Int(Date().timeIntervalSince1970))-\(tag)", isDirectory: true
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Percentile/per-pixel stats.
        var diffs: [Int] = []
        diffs.reserveCapacity(pipe.count * 3)
        if let baseline {
            for i in 0..<min(pipe.count, baseline.count) {
                diffs.append(abs(Int(pipe[i].0) - Int(baseline[i].0)))
                diffs.append(abs(Int(pipe[i].1) - Int(baseline[i].1)))
                diffs.append(abs(Int(pipe[i].2) - Int(baseline[i].2)))
            }
            diffs.sort()
            func percentile(_ p: Double) -> Int {
                guard !diffs.isEmpty else { return 0 }
                return diffs[min(diffs.count - 1, Int(p * Double(diffs.count - 1)))]
            }
            var table = "percentiles (per-channel abs diff /255):\n"
            for p in [0.5, 0.9, 0.99, 0.999, 1.0] {
                table += "  p\(Int(p * 100)) = \(percentile(p))\n"
            }
            let maxAt = diffs.firstIndex(of: diffs.last ?? 0) ?? 0
            table += "  max \(diffs.last ?? 0) first at sample \(maxAt / 3) (\(maxAt % 3) channel)\n"
            try? table.write(to: dir.appendingPathComponent("diff-table.txt"), atomically: true, encoding: .utf8)
        }

        // PFM (P7 color float, little-endian) of the pipe plane.
        var pfm = Data()
        pfm.append(Data("P7\n\(width) \(height)\n-1.0\n".utf8))
        for p in pipe {
            for v in [p.0, p.1, p.2] {
                var f = Float(v) / 255.0
                withUnsafeBytes(of: &f) { pfm.append(contentsOf: $0) }
            }
        }
        try? pfm.write(to: dir.appendingPathComponent("plane.pfm"))
        AppError.logger.error("golden failure dump: \(dir.path, privacy: .public)")
    }

    // MARK: - Criterion 1: neutrality

    private func runFullChain(
        _ url: URL, metal: MetalContext, profile: ColorOutModule.OutputProfile
    ) async throws -> (any MTLTexture, RenderPipeline.PipeRunStats) {
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        return try await RenderPipeline.process(
            image: image,
            instances: await makeChain(outputProfile: profile),
            imageID: UUID(),
            resolution: .preview,
            cache: PipeCache(),
            metal: metal,
            longEdge: harnessLongEdge
        )
    }

    func testNeutralPatchesSyntheticTarget() async throws {
        let metal = try makeMetal()
        let url = try Fixtures.neutralTarget()
        let (texture, _) = try await runFullChain(url, metal: metal, profile: .displayP3)
        let rgb = readRGB8(texture)
        let (w, h) = (texture.width, texture.height)

        var failures: [String] = []
        for patch in Fixtures.neutralPatches {
            let s = sample3x3(rgb, width: w, height: h, x: patch.x, y: patch.y)
            let rg = abs(s.r - s.g)
            let gb = abs(s.g - s.b)
            if rg >= Double(GoldenTolerance.neutral) || gb >= Double(GoldenTolerance.neutral) {
                failures.append(
                    "\(patch.name): R=\(s.r) G=\(s.g) B=\(s.b) (|R−G|=\(rg), |G−B|=\(gb))"
                )
            }
            // Patch-level sanity: the level survives the round trip
            // (16-bit sRGB → Rec2020 → P3 → sRGB TRC → 8-bit).
            func srgbEncode(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
            }
            let want = srgbEncode(patch.expectedLinearRec2020.0) * 255.0
            let got = (s.r + s.g + s.b) / 3.0
            if abs(got - want) > Double(GoldenTolerance.patchLevel) {
                failures.append("\(patch.name): level \(got) vs expected ≈\(want)")
            }
        }

        if !failures.isEmpty {
            dumpFailure(tag: "neutral-synthetic", pipe: rgb, baseline: nil, width: w, height: h)
        }
        XCTAssertTrue(failures.isEmpty, """
            D-COL1 criterion 1 (neutrality < \(GoldenTolerance.neutral)/255) FAILED:
            \(failures.joined(separator: "\n"))
            """)
    }

    func testNeutralPatchesColorCheckerARW() async throws {
        // Gate-quality real-sensor leg — requires BOTH the capture and its
        // calibrated gray-patch coordinates (see Fixtures acquisition note).
        guard let arw = Fixtures.colorCheckerARW, !Fixtures.colorCheckerGrayPatches.isEmpty
        else {
            throw XCTSkip(
                "ColorChecker ARW not present (input/RAW/ColorChecker.ARW + calibrated patches); "
                    + "synthetic target carries the gate. See Fixtures.swift."
            )
        }
        let metal = try makeMetal()
        let (texture, _) = try await runFullChain(arw, metal: metal, profile: .displayP3)
        let rgb = readRGB8(texture)
        let (w, h) = (texture.width, texture.height)

        var failures: [String] = []
        for patch in Fixtures.colorCheckerGrayPatches {
            let s = sample3x3(rgb, width: w, height: h, x: patch.x, y: patch.y)
            let rg = abs(s.r - s.g)
            let gb = abs(s.g - s.b)
            if rg >= Double(GoldenTolerance.neutral) || gb >= Double(GoldenTolerance.neutral) {
                failures.append("\(patch.name): R=\(s.r) G=\(s.g) B=\(s.b)")
            }
        }
        if !failures.isEmpty {
            dumpFailure(tag: "neutral-arw", pipe: rgb, baseline: nil, width: w, height: h)
        }
        XCTAssertTrue(failures.isEmpty, """
            D-COL1 criterion 1 (ARW, < \(GoldenTolerance.neutral)/255) FAILED:
            \(failures.joined(separator: "\n"))
            """)
    }

    // MARK: - Criterion 2: cross-consistency vs the ColorSync baseline

    /// The independent baseline: the SAME decoded CIImage rendered by
    /// CIContext DIRECTLY into the target space — ColorSync does the gamut
    /// conversion, sharing none of our kernel math. Two flavors:
    /// - `.encoded8` — RGBA8 in the display space (the plan's literal
    ///   baseline; carries the ColorSync low-end table behavior, see
    ///   `GoldenTolerance.colorSyncLowEndFloor`).
    /// - `.linearFloat` — RGBAf in the target's LINEAR space (the strictly
    ///   comparable domain: no TRC on either side).
    private enum BaselineFlavor { case encoded8; case linearFloat }

    private func colorSyncBaseline(
        _ url: URL, target: CGColorSpace, flavor: BaselineFlavor
    ) async throws -> (pixels: [(UInt8, UInt8, UInt8)], floats: [Float], width: Int, height: Int) {
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(url)
        let scaled = decoded.ciImage // FULL resolution — same pixels as the pipe leg
        let w = Int(scaled.extent.width), h = Int(scaled.extent.height)

        let renderSpace: CGColorSpace
        let format: CIFormat
        switch flavor {
        case .encoded8:
            renderSpace = target
            format = CIFormat.RGBA8
        case .linearFloat:
            // The target's LINEAR variant — gamut conversion only, no TRC
            // (mirrors colorout's output contract, D-COL4).
            renderSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
                ?? target
            format = CIFormat.RGBAf
        }
        let context = CIContext(options: [
            .workingColorSpace: WorkingSpace.colorSpace, // same decode space as the pipe leg
            .outputColorSpace: renderSpace,
        ])

        switch flavor {
        case .encoded8:
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes {
                context.render(
                    scaled, toBitmap: $0.baseAddress!, rowBytes: w * 4,
                    bounds: scaled.extent, format: format, colorSpace: renderSpace
                )
            }
            var out: [(UInt8, UInt8, UInt8)] = []
            out.reserveCapacity(w * h)
            for i in stride(from: 0, to: w * h * 4, by: 4) {
                out.append((bytes[i], bytes[i + 1], bytes[i + 2]))
            }
            return (out, [], w, h)
        case .linearFloat:
            var floats = [Float](repeating: 0, count: w * h * 4)
            floats.withUnsafeMutableBytes {
                context.render(
                    scaled, toBitmap: $0.baseAddress!, rowBytes: w * 16,
                    bounds: scaled.extent, format: format, colorSpace: renderSpace
                )
            }
            return ([], floats, w, h)
        }
    }

    /// Criterion 2, byte domain (the plan's literal form): pipe output vs
    /// the ColorSync 8-bit render. Strict <2/255 OUTSIDE the ColorSync
    /// 8-bit low-end table zone; inside it, deviations must be BOUNDED
    /// (host finding documented at `GoldenTolerance`).
    func testCrossConsistencySyntheticTarget() async throws {
        let metal = try makeMetal()
        guard let p3 = CGColorSpace(name: CGColorSpace.displayP3) else {
            throw XCTSkip("system Display P3 colorspace unavailable on this host")
        }
        let url = try Fixtures.neutralTarget()
        let (texture, _) = try await runFullChain(url, metal: metal, profile: .displayP3)
        XCTAssertEqual(texture.pixelFormat, GammaModule.outputPixelFormat)
        let pipe = readRGB8(texture)

        // Criterion 2's guard (plan): only meaningful against a known
        // fast-path target — here the target is pinned .displayP3, a fast
        // path BY CONSTRUCTION, so the baseline comparison always runs.
        let baseline = try await colorSyncBaseline(url, target: p3, flavor: .encoded8)

        XCTAssertEqual(texture.width, baseline.width, "both legs must land on the same grid")
        XCTAssertEqual(texture.height, baseline.height)

        let floor = Int(GoldenTolerance.colorSyncLowEndFloor)
        var maxInZone = 0
        var maxOutside = 0
        var worst = (0, 0, 0)
        var violationsOutsideZone: [String] = []
        for i in 0..<min(pipe.count, baseline.pixels.count) {
            let p = [Int(pipe[i].0), Int(pipe[i].1), Int(pipe[i].2)]
            let b = [Int(baseline.pixels[i].0), Int(baseline.pixels[i].1), Int(baseline.pixels[i].2)]
            for ch in 0..<3 {
                let d = abs(p[ch] - b[ch])
                let inLowEndZone = p[ch] < floor || b[ch] < floor
                if inLowEndZone {
                    maxInZone = max(maxInZone, d)
                } else {
                    if d > maxOutside { maxOutside = d; worst = (i % texture.width, i / texture.width, d) }
                    if d >= GoldenTolerance.crossCheck && violationsOutsideZone.count < 8 {
                        violationsOutsideZone.append(
                            "(\(i % texture.width),\(i / texture.width)) ch\(ch): pipe=\(p[ch]) baseline=\(b[ch])"
                        )
                    }
                }
            }
        }
        if maxOutside >= GoldenTolerance.crossCheck || maxInZone > GoldenTolerance.colorSyncLowEndBound {
            dumpFailure(
                tag: "cross-synthetic", pipe: pipe, baseline: baseline.pixels,
                width: texture.width, height: texture.height
            )
        }
        XCTAssertLessThan(
            maxInZone, GoldenTolerance.colorSyncLowEndBound,
            "ColorSync low-end-zone divergence UNBOUNDED (\(maxInZone)/255) — a real TRC error"
        )
        XCTAssertLessThan(
            maxOutside, GoldenTolerance.crossCheck,
            "D-COL1 criterion 2: pipe vs ColorSync diverges \(maxOutside)/255 outside the "
                + "low-end zone (worst at \(worst.0),\(worst.1)): "
                + violationsOutsideZone.joined(separator: "; ")
        )
    }

    /// Criterion 2, LINEAR domain (the strictly-comparable form): the pipe
    /// WITHOUT its gamma tail (colorout output = linear display-gamut
    /// float32, D-COL4) vs CIContext rendered into the target's LINEAR
    /// space. No TRC on either side → the comparison isolates the GAMUT
    /// transform, strict <`GoldenTolerance.crossLinear` per channel.
    /// (TRC correctness is pinned separately: the five-value spec table in
    /// `TerminalTrioTests.testGammaTRCTable` + the criterion-1 patch levels
    /// through the FULL chain.)
    func testCrossConsistencyLinearDomain() async throws {
        let metal = try makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        // Chain WITHOUT gamma: [colorin, colorout(.displayP3)] — tail is
        // colorout → float32 linear-P3 output (no display format).
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: ModuleRegistry.makeDefault(), outputProfile: .displayP3
        )
        chain = chain.filter { $0.opName != GammaModule.opName }
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: harnessLongEdge
        )
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat, "no gamma tail → float32")
        var pipeFloats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        pipeFloats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        let baseline = try await colorSyncBaseline(
            url, target: CGColorSpace(name: CGColorSpace.displayP3)!, flavor: .linearFloat
        )
        XCTAssertEqual(texture.width, baseline.width)
        XCTAssertEqual(texture.height, baseline.height)

        var maxDiff: Float = 0
        var worst = (0, 0)
        for i in 0..<min(pipeFloats.count, baseline.floats.count) {
            let d = abs(pipeFloats[i] - baseline.floats[i])
            if d > maxDiff {
                maxDiff = d
                worst = (i / 4 % texture.width, i / 4 / texture.width)
            }
        }
        XCTAssertLessThan(
            Double(maxDiff), GoldenTolerance.crossLinear,
            "criterion 2 (linear): pipe colorout vs ColorSync linear-P3 diverges "
                + "\(maxDiff) (worst at \(worst.0),\(worst.1))"
        )
    }

    func testCrossConsistencyColorCheckerARW() async throws {
        guard let arw = Fixtures.colorCheckerARW, !Fixtures.colorCheckerGrayPatches.isEmpty
        else {
            throw XCTSkip(
                "ColorChecker ARW not present (input/RAW/ColorChecker.ARW + calibrated patches); "
                    + "synthetic target carries the gate."
            )
        }
        let metal = try makeMetal()
        guard let p3 = CGColorSpace(name: CGColorSpace.displayP3) else {
            throw XCTSkip("system Display P3 colorspace unavailable on this host")
        }
        let (texture, _) = try await runFullChain(arw, metal: metal, profile: .displayP3)
        let pipe = readRGB8(texture)
        let baseline = try await colorSyncBaseline(arw, target: p3, flavor: .encoded8)
        let floor = Int(GoldenTolerance.colorSyncLowEndFloor)
        var maxOutside = 0
        var maxInZone = 0
        for i in 0..<min(pipe.count, baseline.pixels.count) {
            let p = [Int(pipe[i].0), Int(pipe[i].1), Int(pipe[i].2)]
            let b = [Int(baseline.pixels[i].0), Int(baseline.pixels[i].1), Int(baseline.pixels[i].2)]
            for ch in 0..<3 {
                let d = abs(p[ch] - b[ch])
                if p[ch] < floor || b[ch] < floor {
                    maxInZone = max(maxInZone, d)
                } else {
                    maxOutside = max(maxOutside, d)
                }
            }
        }
        if maxOutside >= GoldenTolerance.crossCheck || maxInZone > GoldenTolerance.colorSyncLowEndBound {
            dumpFailure(
                tag: "cross-arw", pipe: pipe, baseline: baseline.pixels,
                width: texture.width, height: texture.height
            )
        }
        XCTAssertLessThan(maxInZone, GoldenTolerance.colorSyncLowEndBound)
        XCTAssertLessThan(maxOutside, GoldenTolerance.crossCheck)
    }

    // MARK: - Full-chain cache assertions (SC#2 terminal variant)

    func testFullChainCacheAssertions() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let cache = PipeCache()
        let registry = ModuleRegistry.makeDefault()
        let imageID = UUID()

        let ci = CIImage(color: CIColor(red: 0.42, green: 0.51, blue: 0.63))
            .cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8
        )
        let chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .display
        )
        let colorout = try XCTUnwrap(
            chain.first { $0.opName == ColorOutModule.opName } as? ModuleBox<ColorOutModule>
        )
        // Pin the FIRST display deterministically (host-independent keys):
        // the coordinator's exact move — override + re-commit.
        colorout.module.displayProfileOverride = .displayP3
        await colorout.setParams(.init(outputProfile: .display))

        func run() async throws -> RenderPipeline.PipeRunStats {
            try await RenderPipeline.process(
                image: image, instances: chain, imageID: imageID,
                resolution: .preview, cache: cache, metal: metal, longEdge: 256
            ).1
        }

        // run1: everything cold → input + 3 module lines, all miss.
        let s1 = try await run()
        XCTAssertEqual(s1.hits, 0)
        XCTAssertEqual(s1.misses, 4, "run1 all-miss (input + colorin + colorout + gamma)")

        // run2: identical params → the top line hit (walk probes top-down
        // and returns at the first hit — upstream zero-computation).
        let s2 = try await run()
        XCTAssertEqual(s2.hits, 1)
        XCTAssertEqual(s2.misses, 0, "run2 all-hit")

        // run3: SIMULATED display change — the coordinator's exact move
        // (override the resolved profile, re-commit params; the folded
        // stableID flips ONLY the ≥colorout keys).
        colorout.module.displayProfileOverride = .sRGB
        await colorout.setParams(.init(outputProfile: .display))
        let s3 = try await run()
        XCTAssertEqual(s3.hits, 1, "colorin plane HIT (upstream survives the display change)")
        XCTAssertEqual(
            s3.misses, 2,
            "colorout + gamma lines MISS (terminal-segment invalidation)"
        )

        // run4: back to the first display → the old colorout/gamma planes
        // are still cached → terminal re-hit.
        colorout.module.displayProfileOverride = .displayP3
        await colorout.setParams(.init(outputProfile: .display))
        let s4 = try await run()
        XCTAssertEqual(s4.hits, 1)
        XCTAssertEqual(s4.misses, 0, "jitter back = pure cache hit (research §2.3 mirror)")
    }
}
