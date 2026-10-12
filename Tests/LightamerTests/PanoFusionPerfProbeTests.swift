@testable import LightamerCore
import Darwin
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoFusionPerfProbeTests (Plan M5-3-02 T5; KD-12) — the 200 MP × 8 pano
// budget probe (the M2-5/M5-2 env-gate convention: the default suite SKIPS
// this file; the approved directed round sets LIGHTAMER_PERF_PROBE=1
// explicitly and the numbers land in .work/gsd/phases/m5-3-pano/perf.md).
//
// THE PATH UNDER PROBE = the PRODUCTION pano faces, zero probe-side
// reimplementation: `panoValidMask` (the geometry pass), `PanoGain
// .samplePlane` + `PanoGain.gains` (the gain segment over the REAL staged
// planes), `panoFuseRows` band-paced over the crop (the tile fusion) with
// the `FloatTIFFWriter` streaming landing — the shipped memory shape (the
// 1 B/px valid mask + O(tile) accumulators + band-level staged reads +
// strip-level writes) and the shipped CPU cost. The ru_maxrss gate rides
// the test-direct machine check (8G, MEMFAIL = kill + streaming-shape
// review). NO GATE on the numbers (OQ-6: record; GPU-ization only if the
// probe falsifies the CPU budget — the decision escalates, never asserts).
//
// L077 RUNBOOK (the M5-2-02 three-incident lessons, all four steps): ① the
// staged writes are `synchronizeFile`d per file BEFORE the fusion reads
// (dirty page cache counts toward phys_footprint — the 8.1 GB probe kill);
// ② every PERF line rides STDERR unbuffered (the killed process loses the
// buffered stdout); ③ the $TMPDIR pattern dirs (la-stack-*/pano-probe-*)
// are swept BEFORE and AFTER the round (the killed process skips its defer
// — the ENOSPC harness lockup); ④ the round preflights df + swapusage and
// SKIPS (honestly, not failing) when the disk budget is not met — the
// staged set is 8 × 28.3 MP ≈ 3.6 GB and the product ≈ 3.2 GB.
//
// PROBE GEOMETRY (fixed): 8 sources of 6144×4608 (≈28.3 MP each, ≈3.6 GB
// staged — the first draft rode 8192×6144 ≈50 MP and was trimmed after the
// fusion-kill incident, see the property note below) on 10°-yaw cameras at
// f = 30 k — the first bounded-canvas round overshoots 200 MP so the shrink
// loop runs and lands just under the cap (the production mechanism decides
// the output size, KD-4).
// ─────────────────────────────────────────────────────────────────────────────

final class PanoFusionPerfProbeTests: XCTestCase {

    /// 6144×4608 ≈ 28.3 MP per source (×8 ≈ 3.6 GB staged). The first
    /// probe run rode 8192×6144 (≈6.4 GB staged) and the FUSION segment
    /// was system-killed at a 24 GB phys_footprint (the L077 signature
    /// despite the synced staged files) — the size trim halves the staged
    /// cache pressure while the CANVAS stays the 200 MP object under
    /// measurement (the DECISIONS note).
    private static let sourceWidth = 6144
    private static let sourceHeight = 4608
    private static let sources = 8
    private static let focal = 30000.0

    /// The disk budget: staged 3.6 GB + product ~3.2 GB + headroom.
    private static let minimumFreeBytes: UInt64 = 10 * 1024 * 1024 * 1024

    func testPanoFusion200MPBudgetProbe() async throws {
        guard ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1"
        else {
            throw XCTSkip("perf probe runs only under LIGHTAMER_PERF_PROBE=1")
        }
        // L077 ③: sweep stale probe dirs before the round.
        Self.sweepProbeDirectories()
        // L077 ④: the disk preflight (df + swap) — record AND guard.
        Self.recordDiskState()
        guard Self.freeDiskBytes() > Self.minimumFreeBytes else {
            throw XCTSkip(
                "pano probe disk budget unmet (need > "
                    + "\(Self.minimumFreeBytes / 1_000_000_000) GB free)")
        }

        let sourceWidth = Self.sourceWidth
        let sourceHeight = Self.sourceHeight
        let sources = Self.sources

        // ── the geometry (known-truth grid: 10° yaws at f = 30 k) ────────
        let geometries: [PanoSourceGeometry] = (0..<sources).map { index in
            PanoSourceGeometry(
                width: sourceWidth, height: sourceHeight,
                focal: Self.focal,
                rotation: PanoCamera.rotation(fromAxisAngle: SIMD3(
                    0, (Double(index) - Double(sources - 1) / 2)
                        * 10 * Double.pi / 180, 0)))
        }
        let scale = PanoWarp.globalScale(focals: geometries.map(\.focal))
        let canvas = try PanoWarp.boundedCanvas(sources: geometries, scale: scale)
        Self.perf(
            "pano-canvas|\(canvas.width)×\(canvas.height)=\(canvas.width * canvas.height / 1_000_000)MP|scale=\(String(format: "%.0f", canvas.scale)) (initial \(String(format: "%.0f", scale)))")

        // ── the staged set (the real StagedSet; L077 ①: sync per file) ───
        let staging = StackMergeService.StagedSet(
            count: sources, width: sourceWidth, height: sourceHeight)
        defer {
            staging.cleanUp()
            Self.sweepProbeDirectories() // L077 ③: sweep after the round
        }
        var stageSeconds: [Double] = []
        for source in 0..<sources {
            let start = Date()
            try Self.writeSyntheticSource(
                staging: staging, index: source, width: sourceWidth,
                height: sourceHeight)
            stageSeconds.append(Date().timeIntervalSince(start))
        }
        for index in 0..<sources {
            let handle = try FileHandle(
                forWritingTo: staging.directory
                    .appendingPathComponent("pixels_\(index).f32"))
            try handle.synchronizeFile() // L077 ①: dirty pages → the volume
            try handle.close()
        }
        Self.perf(
            "pano-stage-io|per-source-seconds=\(stageSeconds.map { String(format: "%.2f", $0) }.joined(separator: ","))|total=\(String(format: "%.2f", stageSeconds.reduce(0, +)))")

        // ── the geometry pass (the REAL panoValidMask) ───────────────────
        let geometryStart = Date()
        let valid = StackMergeService.panoValidMask(
            sources: geometries, rois: canvas.rois, canvas: canvas)
        let geometrySeconds = Date().timeIntervalSince(geometryStart)
        let validPixels = valid.reduce(0) { $0 + Int($1) }
        Self.perf(
            "pano-geometry|seconds=\(String(format: "%.2f", geometrySeconds))|valid-mpx=\(validPixels / 1_000_000)")

        // ── the crop ─────────────────────────────────────────────────────
        let crop = try PanoCrop.innerCrop(
            valid: valid, width: canvas.width, height: canvas.height)
        Self.perf(
            "pano-crop|\(crop.width)×\(crop.height) at [\(crop.x0),\(crop.y0)]")

        // ── the gain segment (the REAL staged-sample face) ───────────────
        let gainStart = Date()
        let sampleSize = PanoGain.sampleCanvasSize(
            canvasWidth: canvas.width, canvasHeight: canvas.height)
        let sampleRatio = Double(sampleSize.width) / Double(max(1, canvas.width))
        var samplePlanes: [PanoGainSamplePlane] = []
        samplePlanes.reserveCapacity(sources)
        for index in 0..<sources {
            let source = geometries[index]
            samplePlanes.append(try PanoGain.samplePlane(
                rectX: Double(canvas.originX) * sampleRatio,
                rectY: Double(canvas.originY) * sampleRatio,
                width: sampleSize.width, height: sampleSize.height,
                scale: canvas.scale * sampleRatio, source: source,
                rowReader: { first, count in
                    try staging.readRows(
                        index: index, firstRow: first, rows: count,
                        bytesPerRow: source.width * 16)
                }))
        }
        let (gains, clipped) = PanoGain.gains(planes: samplePlanes, reference: 0)
        let gainSeconds = Date().timeIntervalSince(gainStart)
        Self.perf(
            "pano-gains|seconds=\(String(format: "%.2f", gainSeconds))|sample=\(sampleSize.width)×\(sampleSize.height)|clipped=\(clipped)|gains=\(gains.map { String(format: "%.3f", $0) }.joined(separator: ","))")

        // ── the tile fusion + the streaming strip-TIFF landing ───────────
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pano-probe-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let product = dir.appendingPathComponent("probe_pano.tif")
        let writer = try BandStreamer.FloatTIFFWriter(
            width: crop.width, height: crop.height, destination: product,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let gainFactors = gains.map { Float($0) }
        let fuseStart = Date()
        var fusedMPX = 0
        var firstRow = 0
        var bandIndex = 0
        while firstRow < crop.height {
            let rowCount = min(
                BandStreamer.defaultBandHeight, crop.height - firstRow)
            let band = try StackMergeService.panoFuseRows(
                staging: staging, sources: geometries, rois: canvas.rois,
                gains: gainFactors, canvas: canvas,
                cropX0: crop.x0, cropX1: crop.x1,
                firstRow: crop.y0 + firstRow, rowCount: rowCount)
            try writer.write(rows: band)
            fusedMPX += rowCount * crop.width
            firstRow += rowCount
            bandIndex += 1
            if bandIndex % 4 == 0 {
                Self.perf(
                    "pano-fuse-band|\(bandIndex)|footprint=\(Self.physFootprintMB())MB")
            }
        }
        try writer.finish()
        let fuseSeconds = Date().timeIntervalSince(fuseStart)
        let bytes = (try FileManager.default.attributesOfItem(
            atPath: product.path)[.size] as? Int) ?? 0
        Self.perf(
            "pano-fuse-stream|seconds=\(String(format: "%.2f", fuseSeconds))|fused-mpx=\(fusedMPX / 1_000_000)|throughput-mpxs=\(String(format: "%.1f", Double(fusedMPX) / 1_000_000 / fuseSeconds))|bytes=\(bytes)")
        Self.recordDiskState()
    }

    /// The footprint-growth diagnostic (the first full probe rounds died
    /// mid-fuse at a 24 GB phys_footprint): a MINIMAL fusion (2 sources,
    /// 2048×1536 staged, ~10 MP canvas) with per-band footprint reports —
    /// flat growth = the full probe's shape is scale-bounded; linear
    /// growth = a per-op retention this file must localize.
    func testPanoFusionFootprintDiagnostic() async throws {
        guard ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1"
        else {
            throw XCTSkip("perf probe runs only under LIGHTAMER_PERF_PROBE=1")
        }
        Self.sweepProbeDirectories()
        let sourceWidth = 2048
        let sourceHeight = 1536
        let geometries: [PanoSourceGeometry] = (0..<2).map { index in
            PanoSourceGeometry(
                width: sourceWidth, height: sourceHeight, focal: 8000,
                rotation: PanoCamera.rotation(fromAxisAngle: SIMD3(
                    0, (Double(index) - 0.5) * 8 * Double.pi / 180, 0)))
        }
        let canvas = try PanoWarp.boundedCanvas(
            sources: geometries,
            scale: PanoWarp.globalScale(focals: geometries.map(\.focal)))
        Self.perf(
            "pano-diag-canvas|\(canvas.width)×\(canvas.height)|start=\(Self.physFootprintMB())MB")
        let staging = StackMergeService.StagedSet(
            count: 2, width: sourceWidth, height: sourceHeight)
        defer {
            staging.cleanUp()
            Self.sweepProbeDirectories()
        }
        for index in 0..<2 {
            try Self.writeSyntheticSource(
                staging: staging, index: index, width: sourceWidth,
                height: sourceHeight)
        }
        let valid = StackMergeService.panoValidMask(
            sources: geometries, rois: canvas.rois, canvas: canvas)
        let crop = try PanoCrop.innerCrop(
            valid: valid, width: canvas.width, height: canvas.height)
        Self.perf("pano-diag-crop|\(crop.width)×\(crop.height)|after-mask=\(Self.physFootprintMB())MB")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pano-probe-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = try BandStreamer.FloatTIFFWriter(
            width: crop.width, height: crop.height, destination: dir
                .appendingPathComponent("diag.tif"),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let gains = [Float](repeating: 1, count: 2)
        var firstRow = 0
        var bandIndex = 0
        while firstRow < crop.height {
            let rowCount = min(
                BandStreamer.defaultBandHeight, crop.height - firstRow)
            let mode = ProcessInfo.processInfo.environment[
                "PANO_DIAG_MODE"] ?? "write"
            if mode != "reads-only" {
                let band = try StackMergeService.panoFuseRows(
                    staging: staging, sources: geometries, rois: canvas.rois,
                    gains: gains, canvas: canvas,
                    cropX0: crop.x0, cropX1: crop.x1,
                    firstRow: crop.y0 + firstRow, rowCount: rowCount)
                if mode != "fuse-only" {
                    try writer.write(rows: band)
                    if ProcessInfo.processInfo.environment["PANO_DIAG_SYNC"]
                        == "1" {
                        try writer.syncForDiagnostics()
                    }
                }
            } else {
                // The READS-ONLY arm: the same per-tile×source spans, no
                // gather, no output — the staged read path's own share.
                var strip: [Float] = []
                for tileX in stride(
                    from: crop.x0, to: crop.x1, by: 512) {
                    for (sourceIndex, source) in geometries.enumerated() {
                        _ = try staging.readRows(
                            index: sourceIndex,
                            firstRow: crop.y0 + firstRow,
                            rows: min(512, crop.height - firstRow),
                            bytesPerRow: source.width * 16, into: &strip)
                    }
                }
            }
            firstRow += rowCount
            bandIndex += 1
            Self.perf(
                "pano-diag-band|\(bandIndex)|mode=\(mode)|footprint=\(Self.physFootprintMB())MB")
        }
        try writer.finish()
        Self.perf("pano-diag-done|footprint=\(Self.physFootprintMB())MB")
    }

    // MARK: - The synthetic staged source (deterministic, chunked)

    /// One deterministic noise plane streamed to the staged file (row-wise
    /// writes — the plane itself never rides as one array).
    private static func writeSyntheticSource(
        staging: StackMergeService.StagedSet, index: Int,
        width: Int, height: Int
    ) throws {
        let url = staging.directory
            .appendingPathComponent("pixels_\(index).f32")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var state = UInt64(0xA5A5_5A5A_0000_0001 &+ UInt64(index))
        var row = [Float](repeating: 0, count: width * 4)
        for _ in 0..<height {
            for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let value = Float(Double(state >> 11) / 9_007_199_254_740_992.0)
                    * 0.7 + 0.15
                let base = x * 4
                row[base] = value
                row[base + 1] = value * 0.9
                row[base + 2] = value * 0.8
                row[base + 3] = 1
            }
            try handle.write(contentsOf: Data(bytes: row, count: width * 16))
        }
    }

    // MARK: - The L077 runbook faces

    private static func sweepProbeDirectories() {
        let temporary = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: temporary, includingPropertiesForKeys: nil)
        else { return }
        for item in contents
        where item.lastPathComponent.hasPrefix("la-stack-")
            || item.lastPathComponent.hasPrefix("pano-probe-") {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func freeDiskBytes() -> UInt64 {
        let values = try? URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true).resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey])
        if let free = values?.volumeAvailableCapacityForImportantUsage {
            return UInt64(max(0, free))
        }
        return 0
    }

    private static func recordDiskState() {
        let free = freeDiskBytes()
        let swapUsage = runTool("/usr/sbin/sysctl", ["vm.swapusage"])
            ?? runTool("/usr/bin/sysctl", ["vm.swapusage"]) ?? "unknown"
        perf(
            "pano-disk|free=\(free / 1_000_000_000)GB|swap=\(swapUsage.replacingOccurrences(of: "\n", with: " "))")
    }

    private static func runTool(_ path: String, _ arguments: [String])
        -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// The process phys_footprint in MB (task_vm_info — the same counter
    /// /usr/bin/time reports at exit; the mid-fusion growth locator).
    private static func physFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0,
                    &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / (1024 * 1024))
    }

    /// The PERF line face — stderr (UNBUFFERED, the L077 ② lesson) with
    /// the PERF| prefix the perf.md transcription greps for.
    private static func perf(_ line: String) {
        FileHandle.standardError.write(Data("PERF|\(line)\n".utf8))
    }
}
