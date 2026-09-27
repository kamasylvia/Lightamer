@testable import Lightamer
@testable import LightamerCore
import CoreImage
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// StackMergeServiceTests (Plan 08-1 T1) — the service skeleton gates:
// cancel epoch (three gates), the progress window, the failure TYPING
// (decode/write hard failures are retry-able; the queue never auto-retries),
// the source-immutability red line, and the App-layer seam walkthrough.
//
// The legs are injected stubs (the 11-04 test seam) — the REAL pipeline
// lands in T2-T5 behind the same signatures.
// ─────────────────────────────────────────────────────────────────────────────

/// An async one-shot gate (the DispatchSemaphore wait faces are unavailable
/// from async contexts on this Swift).
private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

final class StackMergeServiceTests: XCTestCase {

    // MARK: - Stubs

    /// A minimal DecodedImage (the legs' return value; the CI payload is
    /// opaque to the skeleton gates).
    private static func stubDecodedImage() -> DecodedImage {
        let ci = CIImage(color: CIColor.gray).cropped(
            to: CGRect(x: 0, y: 0, width: 4, height: 4))
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// Two source files in a throwaway directory (synthetic fixtures —
    /// NEVER the workspace, L009).
    private func makeSources() throws -> (dir: URL, sources: [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stack-merge-t1-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        var sources: [URL] = []
        for index in 0..<2 {
            let url = dir.appendingPathComponent("src\(index).tif")
            try Data("fixture-\(index)".utf8).write(to: url)
            sources.append(url)
        }
        return (dir, sources)
    }

    private func makeService(
        decodeLeg: StackDecodeLeg? = nil,
        mergeLeg: StackMergeLeg? = nil
    ) throws -> StackMergeService {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        return try StackMergeService(
            device: device, decodeLeg: decodeLeg, mergeLeg: mergeLeg)
    }

    /// Poll until the (single) job reaches a terminal state.
    private static func awaitTerminal(
        _ service: StackMergeService, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) async -> StackMergeService.JobSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let first = snapshots.first, first.state.isTerminal {
                return first
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await service.snapshots().first
    }

    /// The happy-path merge leg: bumps the merge+write steps, writes a
    /// synthetic product file, reports a clean outcome.
    private static func happyMergeLeg(keeping dir: URL) -> StackMergeLeg {
        { work in
            // The merge segment (N) + write/sidecar (2) steps belong to the
            // leg's bump duty; the alignment N steps the service bumps.
            for _ in 0..<(work.sources.count + 2) {
                await work.progress.step()
            }
            let product = dir.appendingPathComponent("merged_hdr.tif")
            try Data([0xCA, 0xFE]).write(to: product)
            return StackMergeOutcome(
                productURL: product, holeFraction: 0.0,
                alignment: Array(repeating: "full", count: work.sources.count),
                exposureRatioVerified: Array(repeating: true, count: work.sources.count))
        }
    }

    // MARK: - Skeleton gates

    func testEnqueueNeedsTwoSources() async throws {
        let service = try makeService()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stack-merge-one-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let single = dir.appendingPathComponent("a.tif")
        try Data([0]).write(to: single)
        do {
            _ = try await service.enqueue(
                kind: .hdrMerge, sources: [single],
                params: .init(), sessionRoot: dir)
            XCTFail("enqueue with one source must throw")
        } catch let error as AppError {
            guard case .invalidParameter = error else {
                XCTFail("expected invalidParameter, got \(error)")
                return
            }
        }
    }

    func testHappyPathProgressWindowAndDone() async throws {
        let (dir, sources) = try makeSources()
        // deGhost OFF → total = N(align) + N(merge) + 2 = 6 for N=2.
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: Self.happyMergeLeg(keeping: dir))
        let snapshot = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        let progress = await service.progress()
        XCTAssertEqual(progress.total, 7)
        XCTAssertEqual(progress.done, 0)
        let terminal = await Self.awaitTerminal(service)
        XCTAssertEqual(terminal?.id, snapshot.id)
        XCTAssertEqual(terminal?.state.isTerminal, true)
        if case .done(let url) = terminal?.state {
            XCTAssertEqual(url.lastPathComponent, "merged_hdr.tif")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        } else {
            XCTFail("expected .done, got \(String(describing: terminal?.state))")
        }
        let final = await service.progress()
        XCTAssertEqual(final.done, final.total)
        XCTAssertEqual(final.done, 7)
    }

    func testDecodeFailureIsHardAndRetryable() async throws {
        let (dir, sources) = try makeSources()
        actor DecodeFlake {
            var calls = 0
            func next() -> Int { calls += 1; return calls }
        }
        let flake = DecodeFlake()
        let service = try makeService(
            decodeLeg: { _ in
                let call = await flake.next()
                if call == 1 {
                    throw AppError.decodeFailed("broken bracket (stub)")
                }
                return Self.stubDecodedImage()
            },
            mergeLeg: Self.happyMergeLeg(keeping: dir))
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        let failed = await Self.awaitTerminal(service)
        guard case .failed(let error)? = failed?.state else {
            XCTFail("expected .failed, got \(String(describing: failed?.state))")
            return
        }
        guard case .decodeFailed = error else {
            XCTFail("expected decodeFailed typing, got \(error)")
            return
        }
        guard let failedID = failed?.id else {
            XCTFail("missing job id")
            return
        }
        // The explicit retry re-queues at the tail and SUCCEEDS (no
        // automatic retry ever ran — the failed state was terminal).
        do {
            try await service.retry(jobID: failedID)
        } catch {
            XCTFail("retry of a failed job must not throw: \(error)")
        }
        let retried = await Self.awaitTerminal(service)
        if case .done = retried?.state {} else {
            XCTFail("expected .done after retry, got \(String(describing: retried?.state))")
        }
    }

    func testRetryNonFailedThrows() async throws {
        let (dir, sources) = try makeSources()
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: Self.happyMergeLeg(keeping: dir))
        let snapshot = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        // Retry a PENDING job → typed refusal (only .failed retries).
        do {
            try await service.retry(jobID: snapshot.id)
            XCTFail("retrying a non-failed job must throw")
        } catch let error as AppError {
            guard case .invalidParameter = error else {
                XCTFail("expected invalidParameter, got \(error)")
                return
            }
        }
    }

    func testWriteFailureIsHardWithEncodeTyping() async throws {
        let (dir, sources) = try makeSources()
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { _ in
                throw AppError.encodeFailed("disk full (stub)")
            })
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed(let error)? = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        guard case .encodeFailed = error else {
            XCTFail("expected encodeFailed typing, got \(error)")
            return
        }
    }

    func testMergeLegNotImplementedIsTypedFailure() async throws {
        let (dir, sources) = try makeSources()
        // Production merge leg (T1: the typed placeholder) behind a stub
        // decode — the placeholder is reached AFTER the align decode passes.
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() })
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        let terminal = await Self.awaitTerminal(service)
        guard case .failed(let error)? = terminal?.state else {
            XCTFail("expected .failed, got \(String(describing: terminal?.state))")
            return
        }
        guard case .notImplemented = error else {
            XCTFail("expected notImplemented, got \(error)")
            return
        }
    }

    // MARK: - Cancel gates (the three-gate epoch shape)

    func testCancelAllCancelsWithoutMerging() async throws {
        let (dir, sources) = try makeSources()
        let entered = AsyncGate()
        let release = AsyncGate()
        actor LegCounter {
            var merges = 0
            func merge() { merges += 1 }
        }
        let counter = LegCounter()
        let service = try makeService(
            decodeLeg: { _ in
                await entered.open()
                await release.wait()
                return Self.stubDecodedImage()
            },
            mergeLeg: { work in
                await counter.merge()
                return try await Self.happyMergeLeg(keeping: dir)(work)
            })
        let snapshot = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        // Deterministic window: wait until the decode is IN FLIGHT, then
        // cancelAll bumps the epoch — the in-flight decode finishes INTO
        // THE VOID (gate ① discards it) and the merge leg never runs.
        await entered.wait()
        await service.cancelAll()
        await release.open()
        let terminal = await Self.awaitTerminal(service)
        XCTAssertEqual(terminal?.id, snapshot.id)
        if case .cancelled = terminal?.state {} else {
            XCTFail("expected .cancelled, got \(String(describing: terminal?.state))")
        }
        let merges = await counter.merges
        XCTAssertEqual(merges, 0, "a cancelled job must not merge")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("merged_hdr.tif").path))
        let progress = await service.progress()
        XCTAssertEqual(progress.done, 0, "a fresh epoch resets the window")
        XCTAssertEqual(progress.total, 0)
    }

    func testCancelDuringDecodeStopsAtNextGate() async throws {
        let (dir, sources) = try makeSources()
        let entered = AsyncGate()
        let release = AsyncGate()
        let service = try makeService(
            decodeLeg: { _ in
                await entered.open()
                await release.wait()
                return Self.stubDecodedImage()
            },
            mergeLeg: Self.happyMergeLeg(keeping: dir))
        let snapshot = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        // Wait until the leg is INSIDE the first decode (in flight).
        await entered.wait()
        // Gate ③: the cancel lands mid-decode — honored at the NEXT
        // between-segment check.
        await service.cancel(jobID: snapshot.id)
        await release.open()
        let terminal = await Self.awaitTerminal(service)
        if case .cancelled = terminal?.state {} else {
            XCTFail("expected .cancelled, got \(String(describing: terminal?.state))")
        }
        // No product was written.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("merged_hdr.tif").path))
    }

    func testCancelAfterWriteBoundaryCompletesDone() async throws {
        let (dir, sources) = try makeSources()
        let wroteProduct = AsyncGate()
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: { work in
                let outcome = try await Self.happyMergeLeg(keeping: dir)(work)
                await wroteProduct.open()
                return outcome
            })
        let snapshot = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        await wroteProduct.wait()
        // The cancel lands after the write boundary — the job completes
        // .done honestly (the state never lies about disk).
        await service.cancel(jobID: snapshot.id)
        let terminal = await Self.awaitTerminal(service)
        if case .done = terminal?.state {} else {
            XCTFail("post-write cancel must complete .done, got \(String(describing: terminal?.state))")
        }
    }

    // MARK: - Source immutability (CONVENTIONS red line)

    func testSourcesRemainUnmodified() async throws {
        let (dir, sources) = try makeSources()
        let before: [(Data, Date)] = try sources.map { url in
            let data = try Data(contentsOf: url)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path)
            return (data, attributes[.modificationDate] as? Date ?? Date())
        }
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: Self.happyMergeLeg(keeping: dir))
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources, params: .init(deGhost: false),
            sessionRoot: dir)
        _ = await Self.awaitTerminal(service)
        for (index, url) in sources.enumerated() {
            let data = try Data(contentsOf: url)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path)
            XCTAssertEqual(data, before[index].0, "source bytes changed: \(url)")
            XCTAssertEqual(
                attributes[.modificationDate] as? Date, before[index].1,
                "source mtime changed: \(url)")
        }
    }

    // MARK: - The App-layer seam (menu → coordinator → service walkthrough)

    @MainActor
    func testCoordinatorHDRMergeSeamReachesService() async throws {
        let (dir, sources) = try makeSources()
        let service = try makeService(
            decodeLeg: { _ in Self.stubDecodedImage() },
            mergeLeg: Self.happyMergeLeg(keeping: dir))
        let coordinator = SessionCoordinator()
        coordinator.stackMergeService = service
        // The same wiring shape LightamerApp installs (the handler IS the
        // menu→service leg; the SwiftUI menu half is declarative).
        coordinator.hdrMergeHandler = { relPaths, deGhost in
            let urls = relPaths.map { dir.appendingPathComponent($0) }
            _ = try? await service.enqueue(
                kind: .hdrMerge, sources: urls,
                params: StackMergeService.MergeParams(deGhost: deGhost),
                sessionRoot: dir)
        }
        await coordinator.hdrMergeHandler?(
            sources.map(\.lastPathComponent), true)
        let terminal = await Self.awaitTerminal(service)
        if case .done = terminal?.state {} else {
            XCTFail("the seam-wired job must complete, got \(String(describing: terminal?.state))")
        }
    }

    // MARK: - CIRAW decode-timing first probe (perf.md anchor, no gate)

    /// RESEARCH §12's dominant segment pinned on the REAL decode chain
    /// (R7 消解): one 100 MP RAW through `RAWDecoder.decode` — the number
    /// lands in `.work/gsd/phases/08-hdr-stacking-effects/perf.md`.
    /// NO assertion on the duration (perf 口径 = 只记不设门).
    func testCIRAW100MPDecodeTimingProbe() async throws {
        let url = Fixtures.raf100MP
        try Fixtures.require(url)
        let decoder = RAWDecoder()
        let start = Date()
        let decoded = try await decoder.decode(url)
        let extent = decoded.ciImage.extent
        let megapixels = Double(extent.width * extent.height) / 1_000_000
        // The CIImage is LAZY — decode() only mints the filter. Force the
        // real CIRAW execution with two renders (the service's two passes):
        // ① a 1024px whole-frame thumbnail (the ALIGN pass shape) and ② a
        // full-extent float32 render (the MERGE pass shape).
        let context = CIContext()
        let scale = 1024.0 / CGFloat(max(extent.width, extent.height))
        let thumb = decoded.ciImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale))
        var thumbPixels = [UInt8](
            repeating: 0, count: 1024 * 768 * 4)
        context.render(
            thumb, toBitmap: &thumbPixels, rowBytes: 1024 * 4,
            bounds: CGRect(x: 0, y: 0, width: 1024, height: 768),
            format: CIFormat.RGBA8, colorSpace: WorkingSpace.colorSpace)
        let smallElapsed = Date().timeIntervalSince(start)

        let fullStart = Date()
        let width = Int(extent.width), height = Int(extent.height)
        let rowBytes = width * 16
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: rowBytes * height, alignment: 64)
        defer { buffer.deallocate() }
        context.render(
            decoded.ciImage, toBitmap: buffer, rowBytes: rowBytes,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        let fullElapsed = Date().timeIntervalSince(fullStart)
        print(
            "CIRAW-DECODE-PROBE: \(width)x\(height) "
                + "(\(String(format: "%.1f", megapixels))MP) RAW "
                + "\(decoded.decoderVersionUsed.rawValue) — align-pass "
                + "render \(String(format: "%.2f", smallElapsed))s, "
                + "merge-pass full float render "
                + "\(String(format: "%.2f", fullElapsed))s")
        XCTAssertGreaterThan(megapixels, 90, "the probe fixture must be ~100MP")
    }
}
