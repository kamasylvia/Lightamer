import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CullFaceModelTests (Plan LUMEN-B T4) — the cull face's APP-domain face:
// the CullViewLoader tiers (display 2560 / full-size judgment / fallback
// leg / LRU caps / production gate) and the face ROUTING state machine
// (AppPhase.cull through WorkspaceModel).
//
// The ±3 read-ahead's front-vs-tail ORDER is the ThumbnailProductionGate's
// own tested semantics (the bridge suite pins prioritize); here the
// read-ahead's OUTCOME face is pinned (the window populates the view LRU).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CullFaceModelTests: XCTestCase {

    // MARK: - Fixtures

    private var workDirectory: URL!
    private var sources: [URL] = []

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("culltests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        sources.removeAll()
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        super.tearDown()
    }

    /// A solid-color PNG of the given size (the ImageIO leg's input).
    private func makePNG(
        width: Int, height: Int, name: String
    ) throws -> URL {
        let url = workDirectory.appendingPathComponent("\(name).png")
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        sources.append(url)
        return url
    }

    /// The concurrent-execution box (the decode-leg observability face).
    final class ConcurrencyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = 0
        private(set) var maxInFlight = 0
        private(set) var calls = 0

        func enter() {
            lock.lock()
            inFlight += 1
            calls += 1
            if inFlight > maxInFlight { maxInFlight = inFlight }
            lock.unlock()
        }

        func leave() {
            lock.lock()
            inFlight -= 1
            lock.unlock()
        }
    }

    // MARK: - The display tier (embedded direct read, ≤2560)

    func testDisplayTierCapsAt2560AndHitsLRU() async throws {
        let url = try makePNG(width: 3000, height: 200, name: "wide")
        let loader = CullViewLoader()
        let first = await loader.displayImage(for: url)
        XCTAssertEqual(first?.width, 2560, "the display tier caps at 2560")
        XCTAssertEqual(first?.height, 171)
        let second = await loader.displayImage(for: url)
        XCTAssertEqual(second?.width, 2560)
        let count = await loader.productionCount
        XCTAssertEqual(count, 1, "the second request is an LRU hit")
        let order = await loader.orderForTesting()
        XCTAssertEqual(order.views, [url])
    }

    func testViewLRUEvictsBeyondCapacity() async throws {
        let loader = CullViewLoader()
        var urls: [URL] = []
        for index in 0..<(CullViewLoader.viewCapacity + 2) {
            urls.append(try makePNG(width: 32, height: 32, name: "v\(index)"))
        }
        for url in urls {
            _ = await loader.displayImage(for: url)
        }
        let order = await loader.orderForTesting()
        XCTAssertEqual(order.views.count, CullViewLoader.viewCapacity)
        XCTAssertEqual(order.views.first, urls[2], "the OLDEST views evict first")
        XCTAssertEqual(order.views.last, urls.last)
    }

    func testReadAheadPopulatesViewLRU() async throws {
        let loader = CullViewLoader()
        let center = try makePNG(width: 32, height: 32, name: "center")
        let neighbours = [
            try makePNG(width: 32, height: 32, name: "n1"),
            try makePNG(width: 32, height: 32, name: "n2"),
        ]
        _ = await loader.displayImage(for: center)
        await loader.readAhead(neighbours)
        // The window's productions complete asynchronously — poll until the
        // LRU carries them (bounded wait, the deterministic-enough face).
        for _ in 0..<100 {
            let order = await loader.orderForTesting()
            if order.views.count == 3 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let order = await loader.orderForTesting()
        XCTAssertEqual(order.views.count, 3, "the ±window populated the LRU")
    }

    // MARK: - The full_size judgment (table-driven, synthetic properties)

    func testFullSizeJudgmentTableDriven() async throws {
        let embedded = try makePNG(width: 800, height: 800, name: "embedded")

        // ≥50% → true (640k vs 1M sensor pixels).
        let bigLoader = CullViewLoader(properties: { _ in (1000, 1000) })
        let big = await bigLoader.fullImage(for: embedded)
        XCTAssertEqual(big?.isEmbedded, true, "640000 >= 0.5 * 1000000")

        // <50% → false (640k vs 4M sensor pixels).
        let smallLoader = CullViewLoader(properties: { _ in (2000, 2000) })
        let small = await smallLoader.fullImage(for: embedded)
        XCTAssertEqual(small?.isEmbedded, false, "640000 < 0.5 * 4000000")

        // Unknowable source dims → false (the honest fallback arm).
        let nilLoader = CullViewLoader(properties: { _ in nil })
        let unknown = await nilLoader.fullImage(for: embedded)
        XCTAssertEqual(unknown?.isEmbedded, false)
    }

    // MARK: - The fallback leg switch (gate ③'s cache route)

    func testFallbackLegServesWhenEmbeddedNotFullSize() async throws {
        let url = try makePNG(width: 640, height: 480, name: "smallsrc")
        let box = ConcurrencyBox()
        let loader = CullViewLoader(
            decodeLeg: { legURL in
                box.enter()
                defer { box.leave() }
                // A stand-in "RAW decode" — the same file's own bytes.
                guard let source = CGImageSourceCreateWithURL(legURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw AppError.decodeFailed("stand-in decode failed") }
                return image
            },
            properties: { _ in (4000, 3000) })
        let produced = await loader.fullImage(for: url)
        XCTAssertEqual(produced?.isEmbedded, false)
        XCTAssertNotNil(produced?.image)
        let fallbacks = await loader.fallbackDecodeCount
        XCTAssertEqual(fallbacks, 1, "the fallback decode leg ran once")
        // The verdict is cached — a second full ask rides the full LRU.
        let again = await loader.fullImage(for: url)
        XCTAssertEqual(again?.isEmbedded, false)
        let count = await loader.productionCount
        XCTAssertEqual(count, 1, "the second full ask is an LRU hit")
    }

    func testFullLRUCapIsTwo() async throws {
        let loader = CullViewLoader(properties: { _ in (4000, 3000) })
        var urls: [URL] = []
        for index in 0..<3 {
            urls.append(try makePNG(width: 40, height: 30, name: "f\(index)"))
        }
        for url in urls {
            _ = await loader.fullImage(for: url)
        }
        let order = await loader.orderForTesting()
        XCTAssertEqual(order.fulls.count, CullViewLoader.fullCapacity)
        XCTAssertEqual(order.fulls, [urls[1], urls[2]], "the oldest full evicts")
    }

    func testProductionGateCapsAtTwo() async throws {
        let box = ConcurrencyBox()
        let loader = CullViewLoader(
            decodeLeg: { legURL in
                box.enter()
                try? await Task.sleep(nanoseconds: 80_000_000)
                box.leave()
                guard let source = CGImageSourceCreateWithURL(legURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw AppError.decodeFailed("stand-in decode failed") }
                return image
            },
            properties: { _ in (4000, 3000) })
        var urls: [URL] = []
        for index in 0..<4 {
            urls.append(try makePNG(width: 40, height: 30, name: "g\(index)"))
        }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { _ = await loader.fullImage(for: url) }
            }
        }
        XCTAssertLessThanOrEqual(box.maxInFlight, CullViewLoader.fullCapacity)
        XCTAssertGreaterThanOrEqual(box.maxInFlight, 2, "the gate parallelizes to the cap")
    }

    // MARK: - The face routing state machine (AppPhase.cull)

    func testCullPhaseRoutingStateMachine() {
        let workspace = WorkspaceModel()
        XCTAssertEqual(workspace.phase, .library)
        workspace.openCull()
        XCTAssertEqual(workspace.phase, .cull)
        workspace.closeCull()
        XCTAssertEqual(workspace.phase, .library)
        // The single toggle answers the cull arm (the Esc semantics).
        workspace.openCull()
        workspace.switchPhase()
        XCTAssertEqual(workspace.phase, .library)
        // The editor round trip is untouched by the third face.
        workspace.openEditor(imageID: nil)
        XCTAssertEqual(workspace.phase, .editor)
        workspace.switchPhase()
        XCTAssertEqual(workspace.phase, .library)
    }
}

/// `LibraryImageRow` carries the path as a String — the URL face the loader
/// asks for (the makeRow helper bridges it).
extension LibraryImageRow {
    var urlAsURL: URL { URL(fileURLWithPath: imagePath) }
}

// ─────────────────────────────────────────────────────────────────────────────
// T5 (X7): the keymap table (the 表驱动 full case), the rating write leg
// (the plan-pinned single-batch mark write through a recorder stand-in for
// LibraryStore.setMetadataMarks), the advance-after-rating ordering, and
// the flag/colour semantics.
// ─────────────────────────────────────────────────────────────────────────────

extension CullFaceModelTests {

    /// The write-leg recorder (the 合成 store face — the box the model's
    /// fire-and-forget write Task lands in).
    final class WriteBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var writes: [(Int64, Int64?, Int64?, Int64?)] = []
        var count: Int { lock.lock(); defer { lock.unlock() }; return writes.count }
        func record(_ id: Int64, _ rating: Int64?, _ label: Int64?, _ flag: Int64?) {
            lock.lock()
            writes.append((id, rating, label, flag))
            lock.unlock()
        }
        func last() -> (Int64, Int64?, Int64?, Int64?)? {
            lock.lock(); defer { lock.unlock() }
            return writes.last
        }
    }

    private func makeEntry(
        id: Int64, rating: Int64? = nil, colorLabel: Int64? = nil, flag: Int64? = nil
    ) -> CullEntry {
        let url = workDirectory.appendingPathComponent("e\(id).png")
        let row = LibraryImageRow(
            id: id, imagePath: url.path, pathKind: 2, volumeUUID: nil,
            cameraMake: nil, cameraModel: nil, lensModel: nil, iso: nil,
            focalLength: nil, aperture: nil, exposure: nil, captureDate: nil,
            fileStem: "IMG_000\(id)", fileExt: "png", exifSearchText: nil,
            exifSearchWords: nil, rating: rating, colorLabel: colorLabel,
            keywords: nil, filename: "IMG_000\(id).png", dir: nil, flag: flag,
            note: nil, hasEdits: 0, paramsHash: nil, refCount: 0,
            addedTime: nil, modifiedTime: nil)
        return CullEntry(
            row: row, url: url, annotation: nil, sharpness: nil,
            eyesClosed: nil, rating: rating, colorLabel: colorLabel, flag: flag)
    }

    private func makeModel(_ entries: [CullEntry]) -> CullFaceModel {
        CullFaceModel(entries: entries, anchorID: entries.first?.id)
    }

    // MARK: - The keymap table (the full case sweep)

    func testKeymapTableCoversTheFullCase() {
        let expected: [(String, CullKeymap.Action)] = [
            ("G", .backToLibrary), ("g", .backToLibrary),
            ("D", .openEditor), ("d", .openEditor),
            ("0", .rating(0)), ("1", .rating(1)), ("2", .rating(2)),
            ("3", .rating(3)), ("4", .rating(4)), ("5", .rating(5)),
            ("P", .pick), ("X", .reject), ("U", .unflag),
            ("6", .colorLabel(1)), ("7", .colorLabel(2)),
            ("8", .colorLabel(3)), ("9", .colorLabel(4)),
            ("A", .toggleAdvance), ("C", .toggleCompare), ("F", .toggleFaces),
        ]
        for (character, action) in expected {
            XCTAssertEqual(CullKeymap.action(for: character), action, character)
        }
        // Unknown characters never map (the view's .ignored face).
        XCTAssertEqual(CullKeymap.action(for: "z"), nil)
        XCTAssertEqual(CullKeymap.action(for: " "), nil)
        XCTAssertEqual(CullKeymap.action(for: ""), nil)
    }

    // MARK: - The rating write leg + the projection refresh

    func testRatingWriteLegRecordsAndRefreshesProjection() async {
        let box = WriteBox()
        let model = makeModel([
            makeEntry(id: 1), makeEntry(id: 2),
        ])
        model.writeLeg = { id, rating, label, flag in
            box.record(id, rating, label, flag)
            await MainActor.run {
                model.applyWrittenMarks(
                    imageID: id, rating: rating, colorLabel: label, flag: flag)
            }
        }
        model.rate(rating: 4)
        // The write rides a fire-and-forget Task — bounded poll.
        for _ in 0..<100 where box.count == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(box.last()?.0, 1)
        XCTAssertEqual(box.last()?.1, 4)
        XCTAssertEqual(model.current?.rating, 4, "the live projection moved")
        XCTAssertEqual(model.index, 0, "no advance without the toggle")
    }

    func testAdvanceAfterRatingMovesAfterTheWrite() async {
        let box = WriteBox()
        let model = makeModel([
            makeEntry(id: 1), makeEntry(id: 2), makeEntry(id: 3),
        ])
        model.writeLeg = { id, rating, label, flag in
            box.record(id, rating, label, flag)
        }
        model.advanceAfterRating = true
        model.rate(rating: 5)
        // The advance is SYNCHRONOUS with the key (the write is async) —
        // the position moved immediately.
        XCTAssertEqual(model.index, 1, "A on: the write leg auto-advances")
        for _ in 0..<100 where box.count == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(box.last()?.0, 1)
    }

    // MARK: - The flag / colour semantics (the sidecar trio)

    func testFlagValuesMatchSidecarSemantics() async {
        let box = WriteBox()
        let model = makeModel([makeEntry(id: 7)])
        model.writeLeg = { id, rating, label, flag in
            box.record(id, rating, label, flag)
        }
        model.rate(flag: 1)  // P
        for _ in 0..<100 where box.count < 1 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(box.last()?.3, 1, "P = pick (1)")
        model.rate(flag: 2)  // X
        for _ in 0..<100 where box.count < 2 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(box.last()?.3, 2, "X = reject (2)")
        model.rate(flag: 0)  // U
        for _ in 0..<100 where box.count < 3 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(box.last()?.3, 0, "U = unflag (0)")
    }

    func testRepeatedColourLabelClears() async {
        let box = WriteBox()
        let model = makeModel([makeEntry(id: 9, colorLabel: 2)])
        model.writeLeg = { id, rating, label, flag in
            box.record(id, rating, label, flag)
        }
        model.rate(colorLabel: 2)  // the same label again → clear (0)
        for _ in 0..<100 where box.count == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(box.last()?.2, 0, "the repeated label toggles off")
        model.rate(colorLabel: 3)  // a different label → write
        for _ in 0..<100 where box.count < 2 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(box.last()?.2, 3)
    }

    // MARK: - The compare/burst model faces (the T5 navigation pins)

    func testRatingTargetsTheCompareCandidateWhenRightSideActive() async {
        let box = WriteBox()
        let model = makeModel([
            makeEntry(id: 1), makeEntry(id: 2),
        ])
        model.writeLeg = { id, rating, label, flag in box.record(id, rating, label, flag) }
        model.setCompare(true)
        XCTAssertTrue(model.activeRight)
        model.rate(rating: 3)
        for _ in 0..<100 where box.count == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(box.last()?.0, 2, "compare + right side: the candidate takes the keys")
    }
}
