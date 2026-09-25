@testable import LightamerCore
@testable import LightamerIOP
import CoreGraphics
import Foundation
import XCTest

/// Plan 08-2 T5 — the Logo double channel (embedded brand PDF set + user
/// uploads) and the user font management. All state lives in INJECTABLE
/// temp directories (the plan's 目录可注入 face); the embedded-PDF faces
/// read the app bundle.
final class YiyinFontStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yiyin-stores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // ── YiyinLogoStore: the embedded brand set ──

    func testEmbeddedBrandSetResolvesAllThirteen() {
        let store = YiyinLogoStore(userDirectory: tempDirectory)
        for brand in YiyinLogoStore.embeddedBrands {
            XCTAssertTrue(store.embeddedExists(make: brand, variant: .black), "\(brand)-b")
            XCTAssertTrue(store.embeddedExists(make: brand, variant: .white), "\(brand)-w")
        }
        XCTAssertEqual(YiyinLogoStore.embeddedBrands.count, 13)
        // An unknown brand → no asset (the Make text-degrade face).
        XCTAssertFalse(store.embeddedExists(make: "nosuchbrand", variant: .black))
    }

    func testEmbeddedRasterizationServesAspect() throws {
        let store = YiyinLogoStore(userDirectory: tempDirectory)
        let image = try XCTUnwrap(store.rasterizedEmbedded(make: "sony", variant: .black))
        // The sony page is 500×88 — the aspect survives rasterization.
        XCTAssertEqual(image.aspect, 500.0 / 88.0, accuracy: 0.02)
        XCTAssertEqual(image.image.height, YiyinLogoStore.rasterHeight)
    }

    // ── YiyinLogoStore: the user channel (typed degradation) ──

    private func makeTestPDF(width: CGFloat = 40, height: CGFloat = 20, red: Bool = false)
        -> Data
    {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            var box = CGRect(x: 0, y: 0, width: width, height: height) as CGRect?,
            let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { fatalError("pdf fixture context") }
        ctx.setFillColor(red: red ? 1 : 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.closePDF()
        return data as Data
    }

    func testUserLogoImportRoundTripAndTypedFailures() throws {
        let store = YiyinLogoStore(userDirectory: tempDirectory)
        let pdf = tempDirectory.appendingPathComponent("fixture.pdf")
        try makeTestPDF().write(to: pdf)

        let entry = try store.importLogo(named: "mylogo", from: pdf)
        XCTAssertEqual(entry.name, "mylogo")
        XCTAssertEqual(store.userLogoNames, ["mylogo"])
        // The artwork loads with the PDF's aspect.
        let image = try XCTUnwrap(store.userLogo(named: "mylogo"))
        XCTAssertEqual(image.aspect, 2.0, accuracy: 0.01)

        // Duplicate → typed.
        XCTAssertThrowsError(try store.importLogo(named: "mylogo", from: pdf)) { error in
            XCTAssertEqual(
                error as? YiyinLogoStore.LogoError, .alreadyExists(name: "mylogo"))
        }
        // Corrupt bytes with a .pdf extension → typed corruptPDF.
        let corrupt = tempDirectory.appendingPathComponent("corrupt.pdf")
        try Data("not a pdf".utf8).write(to: corrupt)
        XCTAssertThrowsError(try store.importLogo(named: "bad", from: corrupt)) { error in
            XCTAssertEqual(error as? YiyinLogoStore.LogoError, .corruptPDF(name: "bad"))
        }
        // Unsupported extension → typed.
        let woff = tempDirectory.appendingPathComponent("font.woff")
        try Data([0x77]).write(to: woff)
        XCTAssertThrowsError(try store.importLogo(named: "w", from: woff)) { error in
            XCTAssertEqual(error as? YiyinLogoStore.LogoError, .unsupportedFormat(name: "w"))
        }
        // Remove: file gone + registry row gone; removing again → typed.
        try store.removeLogo(named: "mylogo")
        XCTAssertEqual(store.userLogoNames, [])
        XCTAssertThrowsError(try store.removeLogo(named: "mylogo")) { error in
            XCTAssertEqual(error as? YiyinLogoStore.LogoError, .notFound(name: "mylogo"))
        }
    }

    func testUserLogoRegistryPersistsAcrossStoreInstances() throws {
        let dir = tempDirectory.appendingPathComponent("logos", isDirectory: true)
        let pdf = tempDirectory.appendingPathComponent("fixture.pdf")
        try makeTestPDF(red: true).write(to: pdf)
        let first = YiyinLogoStore(userDirectory: dir)
        _ = try first.importLogo(named: "persist", from: pdf)

        // A fresh store instance rescans the registry (the restart face).
        let second = YiyinLogoStore(userDirectory: dir)
        XCTAssertEqual(second.userLogoNames, ["persist"])
        XCTAssertNotNil(second.userLogo(named: "persist"))
    }

    func testProviderWiringServesMakeAndCustomSlots() throws {
        let store = YiyinLogoStore(userDirectory: tempDirectory)
        let pdf = tempDirectory.appendingPathComponent("fixture.pdf")
        try makeTestPDF().write(to: pdf)
        _ = try store.importLogo(named: "custom-art", from: pdf)
        let provider = store.provider()

        // The Make slot: the embedded SONY black artwork.
        let sony = provider(.logo(make: "sony", variant: .black))
        XCTAssertNotNil(sony)
        // Unknown brand → nil (the slot drop).
        XCTAssertNil(provider(.logo(make: "nope", variant: .black)))
        // The custom slot: the user artwork.
        XCTAssertNotNil(provider(.customLogo(name: "custom-art")))
        XCTAssertNil(provider(.customLogo(name: "missing")))
        // Literal slots never consult artwork.
        XCTAssertNil(provider(.text("just text")))
    }

    // ── YiyinFontStore ──

    /// A real, valid font file from the system (skipped when absent).
    private func systemFontSource() throws -> URL {
        let candidates = [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if URL(fileURLWithPath: path).pathExtension.lowercased() == "ttf" {
                return URL(fileURLWithPath: path)
            }
        }
        throw XCTSkip("no system .ttf available for the import test")
    }

    func testFontImportRegisterRemoveRoundTrip() throws {
        let dir = tempDirectory.appendingPathComponent("fonts", isDirectory: true)
        let store = YiyinFontStore(directory: dir)
        let source = try systemFontSource()

        let entry = try store.importFont(named: "My Font", from: source)
        XCTAssertEqual(entry.name, "My Font")
        XCTAssertEqual(store.installedNames, ["My Font"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(entry.fileName).path))
        // The session registration resolves a CTFont.
        XCTAssertNotNil(store.ctFont(named: "My Font", size: 24))

        // Duplicate → typed.
        XCTAssertThrowsError(try store.importFont(named: "My Font", from: source)) { error in
            XCTAssertEqual(error as? YiyinFontStore.FontError, .alreadyExists(name: "My Font"))
        }
        // Unsupported extension → typed.
        let otf = tempDirectory.appendingPathComponent("fake.woff")
        try Data([0x00]).write(to: otf)
        XCTAssertThrowsError(try store.importFont(named: "w", from: otf)) { error in
            XCTAssertEqual(error as? YiyinFontStore.FontError, .unsupportedFormat(name: "w"))
        }
        // Corrupt .ttf bytes → typed corruptFont.
        let corrupt = tempDirectory.appendingPathComponent("corrupt.ttf")
        try Data("garbage".utf8).write(to: corrupt)
        XCTAssertThrowsError(try store.importFont(named: "bad", from: corrupt)) { error in
            XCTAssertEqual(error as? YiyinFontStore.FontError, .corruptFont(name: "bad"))
        }
        // Remove → gone + typed notFound on repeat.
        try store.removeFont(named: "My Font")
        XCTAssertNil(store.entry(named: "My Font"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(entry.fileName).path))
        XCTAssertThrowsError(try store.removeFont(named: "My Font")) { error in
            XCTAssertEqual(error as? YiyinFontStore.FontError, .notFound(name: "My Font"))
        }
    }

    func testFontRegistryPersistsAcrossInstances() throws {
        let dir = tempDirectory.appendingPathComponent("fonts2", isDirectory: true)
        let source = try systemFontSource()
        let first = YiyinFontStore(directory: dir)
        _ = try first.importFont(named: "Persist", from: source)

        // A fresh instance rescans + re-registers for the session.
        let second = YiyinFontStore(directory: dir)
        XCTAssertEqual(second.installedNames, ["Persist"])
        XCTAssertNotNil(second.ctFont(named: "Persist", size: 12))
    }

    func testCorruptRegistryEntrySelfHeals() throws {
        // A registry row whose FILE vanished → the rescan drops it (the
        // degraded state is recorded, not silent-forever).
        let dir = tempDirectory.appendingPathComponent("fonts3", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ghost = YiyinFontStore.InstalledFont(
            name: "Ghost", fileName: "deadbeef.ttf", hash: 0)
        let registry = try JSONEncoder().encode(["Ghost": ghost])
        try registry.write(to: dir.appendingPathComponent("registry.json"))

        let store = YiyinFontStore(directory: dir)
        XCTAssertEqual(store.installedNames, [], "the ghost entry dropped on rescan")
    }

    func testSystemFamilyEnumerationNonEmpty() {
        let store = YiyinFontStore(directory: tempDirectory.appendingPathComponent("fonts4"))
        let families = store.availableSystemFontFamilies()
        XCTAssertGreaterThan(families.count, 10, "a real system has many families")
        XCTAssertTrue(families.contains("PingFang SC"), "the watermark default cascade face")
        // Sorted + no hidden faces.
        XCTAssertEqual(families, families.sorted())
        XCTAssertTrue(families.allSatisfy { !$0.hasPrefix(".") })
    }
}
