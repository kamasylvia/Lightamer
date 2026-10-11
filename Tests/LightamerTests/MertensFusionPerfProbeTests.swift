@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensFusionPerfProbeTests (Plan M5-2-02 T4, KD-6) — the 100 MP × N=5
// fusion budget probe (the M2-5 env-gate convention: the default suite
// SKIPS this file; the approved directed round sets LIGHTAMER_PERF_PROBE=1
// explicitly and the numbers land in
// .work/gsd/phases/m5-2-mertens/perf.md).
//
// THE PATH UNDER PROBE = the PRODUCTION band-outer driver: synthetic
// 100 MP × 5 display planes staged to the REAL StagedSet, a synthetic
// staged soft mask (the deghost tier medium), synthetic 129-point
// identity LUTs — then `mertensBandOuterFuse` (the leg's own function,
// zero probe-side reimplementation) + the product write face. The probe
// therefore measures the shipped memory shape (staged N×16+1 B/px, the
// output plane 16 B/px, one strip group at a time) and the shipped CPU
// cost — the ru_maxrss gate rides the test-direct machine check (8G,
// MEMFAIL = kill + streaming-shape review).
//
// TIMING DISCIPLINE: every segment here is CPU wall clock around a
// synchronous, fully-draining call — the band-outer driver and the TIFF
// writer return only after their last byte (no GPU segment exists in this
// path: the Mertens fusion is pure CPU by design, OQ-6; the L014 fence
// rule targets GPU-adjacent reads and has no object here — recorded in
// perf.md).
//
// NO GATE: OQ-6's CPU-budget verdict = "record the numbers, GPU-ization
// only if the probe falsifies the CPU budget" — the fusion segment time
// is RECORDED, never asserted.
// ─────────────────────────────────────────────────────────────────────────────

final class MertensFusionPerfProbeTests: XCTestCase {

    /// ≈100 MP: 11648 × 8588 = 100,033,024 px.
    private static let width = 11648
    private static let height = 8588
    private static let sources = 5

    func testMertensFusion100MPBandOuterProbe() async throws {
        guard ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1" else {
            throw XCTSkip("perf probe runs only under LIGHTAMER_PERF_PROBE=1")
        }
        let width = Self.width
        let height = Self.height
        let sources = Self.sources
        let levels = MertensFusion.adaptiveLevels(minEdge: min(width, height))
        let halo = MertensFusion.haloRows(levels: levels)
        Self.perf("mertens-setup|width=\(width)|height=\(height)|sources=\(sources)|levels=\(levels)|halo=\(halo)")

        let staging = StackMergeService.StagedSet(
            count: sources, width: width, height: height)
        defer { staging.cleanUp() }

        // ── the staged pixel writes (one plane resident at a time — the
        // leg's stage-pass shape) ─────────────────────────────────────────
        var stageSeconds: [Double] = []
        for source in 0..<sources {
            let start = Date()
            let plane = Self.syntheticPlane(source: source, width: width, height: height)
            try staging.writePlaneForProbe(plane, index: source)
            stageSeconds.append(Date().timeIntervalSince(start))
        }
        // Force the staged files' dirty pages back to the volume: 8.1 GB
        // of dirty cache (N×16 B/px) counts toward the process footprint
        // until cleaned — on a 16 GB machine the first probe run died to
        // system memory pressure mid-fuse (ru_maxrss itself held at
        // 6248 MB). The sync is the honest staged-IO face: the bytes ARE
        // on disk before the fusion reads them back.
        for index in 0..<sources {
            let handle = try FileHandle(
                forWritingTo: staging.directory
                    .appendingPathComponent("pixels_\(index).f32"))
            try handle.synchronizeFile()
            try handle.close()
        }
        Self.perf("mertens-stage-io|per-source-seconds=\(stageSeconds.map { String(format: "%.2f", $0) }.joined(separator: ","))|total=\(String(format: "%.2f", stageSeconds.reduce(0, +)))")

        // ── the staged soft mask (synthetic — the deghost mask COMPUTE is
        // a stage-time concern measured separately; the fusion-side mask
        // channel read + substitution is this probe's deghost face) ──────
        let mask = Self.syntheticMask(width: width, height: height)
        try staging.writeMask(mask)

        // Synthetic 129-point identity LUTs (the substitution path with a
        // neutral map — the in-pass applySubstitution cost is the object).
        // ONE TRIPLE PER SOURCE (the leg's LUT array contract).
        let quantiles = MertensFusion.linspace(0, 100, 129)
        let identity = MertensFusion.ChannelLUT(xs: quantiles.map { Float($0) }, ys: quantiles.map { Float($0) })
        let luts = Array(
            repeating: [identity, identity, identity], count: sources)

        // ── the band-outer fusion (the production driver) ─────────────────
        var ghostUnion: [UInt8]? = [UInt8](repeating: 0, count: width * height)
        let fuseStart = Date()
        let output = try await StackMergeService.mertensBandOuterFuse(
            staging: staging, width: width, height: height, sources: sources,
            levels: levels, halo: halo,
            tier: .medium, luts: luts,
            shifts: Array(repeating: (dx: 0, dy: 0), count: sources),
            ghostUnion: &ghostUnion,
            progress: StackMergeProgress {},
            bumpBudget: sources)
        let fuseSeconds = Date().timeIntervalSince(fuseStart)
        let unionPixels = ghostUnion?.reduce(0) { $0 + Int($1) } ?? 0
        Self.perf("mertens-band-outer-fuse|seconds=\(String(format: "%.2f", fuseSeconds))|throughput-mpxs=\(String(format: "%.2f", Double(width * height) / 1_000_000 / fuseSeconds))|ghost-union-px=\(unionPixels)")

        // ── the product write (the landing face) ──────────────────────────
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mertens-probe-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let product = dir.appendingPathComponent("probe_mertens.tif")
        let writeStart = Date()
        try BandStreamer.writeFloatTIFF(
            output, width: width, height: height, to: product,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let writeSeconds = Date().timeIntervalSince(writeStart)
        let bytes = (try FileManager.default.attributesOfItem(
            atPath: product.path)[.size] as? Int) ?? 0
        Self.perf("mertens-product-write|seconds=\(String(format: "%.2f", writeSeconds))|bytes=\(bytes)")
    }

    /// The PERF line face — stderr (UNBUFFERED: the first probe run lost
    /// its buffered stdout to the abnormal exit) with the PERF| prefix the
    /// perf.md transcription greps for.
    private static func perf(_ line: String) {
        FileHandle.standardError.write(Data("PERF|\(line)\n".utf8))
    }

    /// A deterministic display-domain plane (half-exact checker + a
    /// per-source stepped block — the same fixture family as the leg tests,
    /// generated row-strip-wise into ONE resident plane per source).
    private static func syntheticPlane(
        source: Int, width: Int, height: Int
    ) -> [Float] {
        var plane = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let rowBase = y * width
            for x in 0..<width {
                let base = (rowBase + x) * 4
                let checker = ((x / 8) + (y / 8)) % 2 == 0
                var value: Float = checker ? 0.75 : 0.25
                if x >= 1000 + source * 800, x < 3000 + source * 800,
                   y >= height / 3, y < height / 3 + height / 8 {
                    value = 0.0625
                }
                plane[base] = value
                plane[base + 1] = value
                plane[base + 2] = value
                plane[base + 3] = 1
            }
        }
        return plane
    }

    /// A synthetic soft mask with the stepped block armed (the fusion pass
    /// reads it per band and substitutes against it).
    private static func syntheticMask(width: Int, height: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in (height / 3)..<(height / 3 + height / 8) {
            let rowBase = y * width
            for x in 1000..<(3000 + (sources - 1) * 800) {
                mask[rowBase + x] = 255
            }
        }
        return mask
    }
}

extension StackMergeService.StagedSet {
    /// Probe-side staged write (the MertensLegTests helper shape —
    /// duplicated here for bundle independence; EXPORT holds no IOP test
    /// file coupling).
    func writePlaneForProbe(_ plane: [Float], index: Int) throws {
        let width = self.width
        let height = self.height
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: width * height * 16, alignment: 64)
        plane.withUnsafeBufferPointer { source in
            buffer.copyMemory(
                from: UnsafeRawPointer(source.baseAddress!),
                byteCount: width * height * 16)
        }
        try writePixels(
            StackRenderedPlane(
                pointer: buffer, width: width, height: height,
                bytesPerRow: width * 16),
            index: index)
    }
}
