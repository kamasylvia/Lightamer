import CoreGraphics
import CoreText
import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-3 T3 — the image-trio budget tests.
//
// The §RQ-14-8 budget table is CODE here: the default/ceiling values are
// asserted VERBATIM (the constants live ONCE in McpImageBudget — drifting a
// value turns the suite red). Plus: the CG contact-sheet composite with a
// CJK filename fixture (R9 — glyph + pixel-coverage assertions, no DIY OCR),
// the stale three-state semantics, and the ROI bounds negative.
// ─────────────────────────────────────────────────────────────────────────────

/// Sendable counter box for the injected render leg.
final class RenderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

final class McpCullingImageBudgetTests: XCTestCase {

    // MARK: - The budget table, verbatim (research §RQ-14-8)

    func testBudgetTableVerbatim() {
        // render_preview (the 14-2 half — constants live on THIS shared seam).
        XCTAssertEqual(McpImageBudget.renderPreviewLongEdge, 1024)
        XCTAssertEqual(McpImageBudget.renderPreviewQuality, 85)
        XCTAssertEqual(McpImageBudget.renderPreviewMaxLongEdge, 2048)
        XCTAssertEqual(McpImageBudget.renderPreviewMaxQuality, 90)
        // get_thumbnails: ≤20/请求, ~730KB request budget.
        XCTAssertEqual(McpImageBudget.thumbnailsMaxPerRequest, 20)
        // get_contact_sheet: cell 256/q80, ≤6×5=30 cells, 24px captions,
        // ≤2MB single-composite base64 ceiling.
        XCTAssertEqual(McpImageBudget.contactSheetCellSize, 256)
        XCTAssertEqual(McpImageBudget.contactSheetQuality, 80)
        XCTAssertEqual(McpImageBudget.contactSheetMaxCols, 6)
        XCTAssertEqual(McpImageBudget.contactSheetMaxRows, 5)
        XCTAssertEqual(McpImageBudget.contactSheetMaxCells, 30)
        XCTAssertEqual(McpImageBudget.contactSheetCaptionHeight, 24)
        XCTAssertEqual(McpImageBudget.contactSheetMaxBase64Bytes, 2_000_000)
        // get_detail_crop: longEdge 1024/q85, output ceiling 1536.
        XCTAssertEqual(McpImageBudget.detailCropLongEdge, 1024)
        XCTAssertEqual(McpImageBudget.detailCropQuality, 85)
        XCTAssertEqual(McpImageBudget.detailCropMaxLongEdge, 1536)
    }

    func testThumbnailsRequestOverTwentyRejected() async throws {
        let fixture = try await McpCullingToolsetTests.makeFixture { store in
            try await McpCullingToolsetTests.seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await McpCullingToolsetTests.makeRegistry(fixture)
        let paths: [McpJSON] = (0..<21).map { .string("p\($0).arw") }
        do {
            _ = try await registry.call(
                name: "get_thumbnails", arguments: ["relPaths": .array(paths)])
            XCTFail("expected invalidParams for 21 relPaths")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("20"))
        }
    }

    /// The stale three states: fresh (no marker), stale default (marker +
    /// cached bytes, NO re-render), stale + regenerate (provider re-render,
    /// marker cleared). The render leg counts calls (the tier-B single-image
    /// rerun proof).
    func testStaleThreeStates() async throws {
        let fixture = try await McpCullingToolsetTests.makeFixture { store in
            try await store.withHandleForTesting { handle in
                let insert = try handle.prepare("""
                    INSERT INTO images (
                      path, dir, filename, has_edits, sidecar_present,
                      params_hash, thumb_params_hash, thumb_state, orphan_sidecar
                    ) VALUES (?, ?, ?, 1, 1, '111', '111', ?, 0)
                    """)
                try insert.bindText(1, "stale.arw")
                try insert.bindText(2, "Capture")
                try insert.bindText(3, "stale.arw")
                try insert.bindInt(4, 3)  // stale
                _ = try insert.step()
                let fresh = try handle.prepare("""
                    INSERT INTO images (
                      path, dir, filename, has_edits, sidecar_present,
                      params_hash, thumb_params_hash, thumb_state, orphan_sidecar
                    ) VALUES (?, ?, ?, 1, 1, '222', '222', ?, 0)
                    """)
                try fresh.bindText(1, "fresh.arw")
                try fresh.bindText(2, "Capture")
                try fresh.bindText(3, "fresh.arw")
                try fresh.bindInt(4, 2)  // rendered (fresh)
                _ = try fresh.step()
            }
        }
        defer { fixture.cleanup() }

        // The disk cache holds a "rendered" thumb for both rows; the
        // tier-B leg also materializes the SIDECAR, so both rows carry a
        // real .lra (the MetadataServiceTests writeImage pattern).
        let disk = ThumbnailDiskStore(sessionRoot: fixture.sessionRoot)
        let gradient = Self.makeGradientCGImage(width: 40, height: 30)
        for rel in ["stale.arw", "fresh.arw"] {
            let url = fixture.sessionRoot.appendingPathComponent(rel)
            try Data(repeating: 0xAB, count: 16).write(to: url)
            var history = HistoryStack()
            history.commit(
                ModuleInstance(
                    module: ExposureModule.self, multiName: "e",
                    params: ExposureModule.Params(exposure: 0.3)),
                label: "exposure")
            let document = LightamerSidecar(
                imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
                instances: history.effectiveInstances(), history: history,
                historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 42),
                appVersion: "mcp-budget", layerStack: nil)
            try JSONEncoder().encode(document).write(
                to: LightamerSidecar.sidecarURL(for: url))
            try disk.write(gradient, relPath: rel)
        }

        // The provider with a COUNTING test render leg (the injected-leg
        // test seam; SessionThumbnailProviderTests pattern).
        let renderBox = RenderCounter()
        let provider = SessionThumbnailProvider(
            sessionRoot: fixture.sessionRoot, store: fixture.store,
            disk: disk, memory: ThumbnailMemoryCache(),
            registry: ModuleRegistry(),
            decodeLeg: { _ in
                DecodedImage(
                    ciImage: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)),
                    rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
                    segmentationSkyMatte: nil, decoderVersionUsed: .v8)
            },
            renderLeg: { _ in
                await renderBox.increment()
                return gradient
            })

        let registry = await McpCullingToolsetTests.makeRegistry(
            fixture, thumbnailProvider: provider)

        // ① FRESH: no stale marker, bytes from the disk cache.
        let fresh = try await McpCullingToolsetTests.callJSON(
            registry, name: "get_thumbnails",
            arguments: ["relPaths": .array([.string("fresh.arw")])])
        let freshResults = try XCTUnwrap(fresh["results"] as? [[String: Any]])
        XCTAssertEqual(freshResults[0]["stale"] as? Bool, false)
        XCTAssertEqual(freshResults[0]["missing"] as? Bool, false)
        let freshCalls = await renderBox.value
        XCTAssertEqual(freshCalls, 0)

        // ② STALE, default: marker + CACHED bytes, no re-render.
        let stale = try await McpCullingToolsetTests.callJSON(
            registry, name: "get_thumbnails",
            arguments: ["relPaths": .array([.string("stale.arw")])])
        let staleResults = try XCTUnwrap(stale["results"] as? [[String: Any]])
        XCTAssertEqual(staleResults[0]["stale"] as? Bool, true)
        XCTAssertEqual(staleResults[0]["missing"] as? Bool, false)
        let staleCalls = await renderBox.value
        XCTAssertEqual(staleCalls, 0, "regenerate defaults to false")
        // The stale marker rides the manifest, NOT a typed error.
        let staleImageBlocks = stale.compactMap { _ in () }.count
        _ = staleImageBlocks

        // ③ STALE + regenerate=true: the provider route reruns, marker
        // clears (the tier-B single-image rerun through the EXISTING queue
        // face — the L031 consumption).
        let regen = try await McpCullingToolsetTests.callJSON(
            registry, name: "get_thumbnails",
            arguments: [
                "relPaths": .array([.string("stale.arw")]),
                "regenerate": .bool(true),
            ])
        let regenResults = try XCTUnwrap(regen["results"] as? [[String: Any]])
        let regenCalls = await renderBox.value
        XCTAssertGreaterThanOrEqual(regenCalls, 1, "the tier-B leg ran")
        XCTAssertEqual(regenResults[0]["missing"] as? Bool, false)
        // After a successful tier-B regen the row binds rendered state.
        let row = try await fixture.store.fetchRow(relPath: "stale.arw")
        XCTAssertEqual(row?.thumbState, SessionIndexSchema.ThumbState.rendered.rawValue)
    }

    func testContactSheetGridAndChineseCaption() async throws {
        let fixture = try await McpCullingToolsetTests.makeFixture { store in
            // R9 fixture: a CJK filename (never tofu) + a rated row + a
            // rejected row (the color-bar faces).
            try await McpCullingToolsetTests.seedRow(
                store, path: "晚霞-海边.NEF", rating: 4, flag: 1)
            try await McpCullingToolsetTests.seedRow(
                store, path: "reject-me.arw", flag: 2)
        }
        defer { fixture.cleanup() }

        // The composite runs on the CG face directly (pure CG, no Metal).
        let cell = McpImageBudget.contactSheetCellSize
        let caption = McpImageBudget.contactSheetCaptionHeight
        let image = Self.makeGradientCGImage(width: 320, height: 200)
        let rows: [SessionIndexRow] = (try await fixture.store.query(groups: []))
        let cells: [CGImage?] = [image, nil]
        let sheet = try McpCullingToolset.drawContactSheet(
            cells: cells, rows: rows, cols: 2, rowsCount: 1,
            cell: cell, captionHeight: caption)
        XCTAssertEqual(sheet.width, 2 * cell)
        XCTAssertEqual(sheet.height, cell + caption)

        // Pixel sampling: the FIRST cell carries the drawn photo (bright),
        // the caption band carries rendered text (non-uniform coverage) —
        // tofu boxes would give a uniform pattern; the glyph gate below
        // pins the CJK encoding independently.
        let sampled = Self.pixelCoverage(
            of: sheet, in: CGRect(x: 0, y: cell, width: cell, height: caption))
        XCTAssertGreaterThan(
            sampled, 0.01, "caption band must carry rendered ink (filename)")

        // The glyph gate: the system UI font CAN encode the CJK fixture
        // (a missing font/cascade maps every char to the .notdef glyph 0).
        let font = CTFontCreateWithName("PingFang SC" as CFString, 12, nil)
        var glyphs = [CGGlyph](repeating: 0, count: 4)
        let cjk = Array("晚霞海边".utf16)
        let encoded = CTFontGetGlyphsForCharacters(font, cjk, &glyphs, 4)
        XCTAssertTrue(encoded, "the UI font must map the CJK fixture")
        XCTAssertTrue(
            glyphs.contains { $0 != 0 }, "CJK chars must map to real glyphs")

        // The JPEG face: encode at the sheet quality and hold under the
        // 2MB base64 ceiling (the budget red line, sampled on real bytes).
        let jpeg = try McpCullingToolset.jpegData(
            from: sheet, quality: Double(McpImageBudget.contactSheetQuality) / 100)
        XCTAssertLessThanOrEqual(
            jpeg.base64EncodedString().utf8.count,
            McpImageBudget.contactSheetMaxBase64Bytes)
    }

    func testContactSheetArgumentGuards() async throws {
        let fixture = try await McpCullingToolsetTests.makeFixture { store in
            try await McpCullingToolsetTests.seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await McpCullingToolsetTests.makeRegistry(fixture)

        // cols > 6 → invalidParams.
        do {
            _ = try await registry.call(
                name: "get_contact_sheet",
                arguments: ["relPaths": .array([.string("nature.arw")]),
                            "cols": .int(7)])
            XCTFail("expected invalidParams for cols 7")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        // BOTH relPaths and filter → invalidParams (exactly one).
        do {
            _ = try await registry.call(
                name: "get_contact_sheet",
                arguments: [
                    "relPaths": .array([.string("nature.arw")]),
                    "filter": .object(["schemaVersion": .int(1), "rules": .array([])]),
                ])
            XCTFail("expected invalidParams for both sources")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        // NEITHER → invalidParams.
        do {
            _ = try await registry.call(name: "get_contact_sheet", arguments: [:])
            XCTFail("expected invalidParams for no source")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }

    /// ROI validation consumes the DECODED extent: an in-bounds crop
    /// returns bytes sized to the long edge; an out-of-bounds ROI is the
    /// typed roiOutOfBounds.
    func testDetailCropBoundsAndOutput() async throws {
        let fixture = try await McpCullingToolsetTests.makeFixture { store in
            try await McpCullingToolsetTests.seedRow(
                store, path: "crop-me.arw", width: 800, height: 600)
        }
        defer { fixture.cleanup() }
        try Data(repeating: 0xAB, count: 16).write(
            to: fixture.sessionRoot.appendingPathComponent("crop-me.arw"))
        let registry = await McpCullingToolsetTests.makeRegistry(
            fixture,
            decodeImage: { _ in Self.makeGradientCGImage(width: 800, height: 600) })

        // In-bounds 100×100 crop @ (10, 20) → long edge downscales to ≤1024
        // (a 100px crop is below the long edge — NO upscale).
        let output = try await registry.call(
            name: "get_detail_crop",
            arguments: [
                "relPath": .string("crop-me.arw"),
                "roi": .object([
                    "x": .int(10), "y": .int(20), "w": .int(100), "h": .int(100),
                ]),
            ])
        XCTAssertEqual(output.content.count, 2)
        guard case .text(let manifestJSON) = output.content[0],
            case .imageBase64(let base64, let mimeType) = output.content[1]
        else {
            return XCTFail("expected manifest + image")
        }
        XCTAssertEqual(mimeType, "image/jpeg")
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(manifestJSON.utf8)) as? [String: Any])
        XCTAssertEqual(manifest["outputWidth"] as? Int, 100)
        XCTAssertEqual(manifest["outputHeight"] as? Int, 100)
        XCTAssertGreaterThan(base64.utf8.count, 100)

        // Out-of-bounds → roiOutOfBounds (the typed negative).
        do {
            _ = try await registry.call(
                name: "get_detail_crop",
                arguments: [
                    "relPath": .string("crop-me.arw"),
                    "roi": .object([
                        "x": .int(700), "y": .int(500), "w": .int(200), "h": .int(200),
                    ]),
                ])
            XCTFail("expected roiOutOfBounds")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "roiOutOfBounds")
            XCTAssertTrue(error.message.contains("800×600"))
        }
    }

    // MARK: - Helpers

    /// A deterministic two-tone gradient (the non-uniform test image).
    static func makeGradientCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            let tone = CGFloat(x) / CGFloat(width)
            context.setFillColor(CGColor(gray: 0.1 + 0.7 * tone, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()!
    }

    /// Fraction of non-background pixels (luma > 0.3) in the rect — the
    /// pixel-sampling face (NOT OCR; the text-vs-blank discriminator).
    static func pixelCoverage(of image: CGImage, in rect: CGRect) -> Double {
        guard let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else { return 0 }
        let bpr = image.bytesPerRow
        let spp = image.bitsPerPixel / 8
        var inked = 0, total = 0
        for y in Int(rect.minY)..<min(Int(rect.maxY), image.height) {
            for x in Int(rect.minX)..<min(Int(rect.maxX), image.width) {
                let offset = y * bpr + x * spp
                let r = bytes[offset], g = bytes[offset + 1], b = bytes[offset + 2]
                let luma = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
                total += 1
                if luma > 76 { inked += 1 }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }
}
