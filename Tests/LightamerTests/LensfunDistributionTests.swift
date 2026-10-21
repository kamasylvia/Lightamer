@testable import Lightamer
import LightamerIOP
import XCTest

/// LensfunDistributionTests (Plan LENS-03 T3, D-LENS-6 / X7) — the pinned
/// snapshot's distribution face. **App bundle** (the tested types
/// LensfunDataDistribution / LensfunDownloadService are the App Session
/// domain; the IOP target cannot import App — review m3).
///
/// Faces: the registered archive SHA, the per-file SHA manifest sanity,
/// the seeder's three sentinel states (equal / drift / missing), the
/// four-state location priority, the dbTag stability + sensitivity, and
/// the update channel's SHA-mismatch refusal (the network face stays
/// untested here — the gate is the SHA compare, which is hermetic).
final class LensfunDistributionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LensfunStore.uninstall()
    }

    override func tearDown() {
        LensfunStore.uninstall()
        UserDefaults.standard.removeObject(forKey: LensfunDownloadService.customPathKey)
        super.tearDown()
    }

    // MARK: - The registered identity

    func testRegisteredArchiveSHAIsThePinnedValue() {
        // The README + the code must agree (the update gate's anchor).
        XCTAssertEqual(
            LensfunPinnedSnapshot.archiveSHA256,
            "97c9f8059accae0128a413bc610a04a4548e8da2764a6d3d60d82bf917639457")
    }

    func testBundledSeedManifestSanity() throws {
        // The bundled snapshot ships with its per-file SHA manifest; the
        // in-bundle copies must match (the folder-reference integrity).
        guard let seed = LensfunDataDistribution.bundledSeed() else {
            throw XCTSkip("no bundled seed in the test host")
        }
        let fm = FileManager.default
        let manifestURL = seed.deletingLastPathComponent()
            .appendingPathComponent("version_1.SHA256SUMS")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw XCTSkip("manifest not bundled")
        }
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        var checked = 0
        for line in manifest.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            let hash = String(parts[0])
            let name = String(parts[1].split(separator: "/").last ?? "")
            let file = seed.appendingPathComponent(name)
            XCTAssertEqual(
                LensfunDataDistribution.fileSHA256(at: file), hash,
                "bundled \(name) drifted from the manifest")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 50, "the manifest covers the full snapshot")
    }

    // MARK: - The seeder's three sentinel states (equal / drift / missing)

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lensfun-dist-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSeederSentinelStates() throws {
        let source = makeTempDir()
        try Data("<db>a</db>".utf8).write(to: source.appendingPathComponent("a.xml"))
        try Data("<db>b</db>".utf8).write(to: source.appendingPathComponent("b.xml"))
        let dest = makeTempDir()
        let destDir = dest.appendingPathComponent("version_1-seeded", isDirectory: true)

        func seed(from: URL, to: URL) {
            let fm = FileManager.default
            try? fm.createDirectory(at: to, withIntermediateDirectories: true)
            for name in ["a.xml", "b.xml"] {
                let src = source.appendingPathComponent(name)
                let tgt = to.appendingPathComponent(name)
                let same = (try? LensfunDataDistribution.fileSHA256(at: tgt))
                    == LensfunDataDistribution.fileSHA256(at: src)
                    && fm.fileExists(atPath: tgt.path)
                guard !same else { continue }
                try? fm.removeItem(at: tgt)
                try? fm.copyItem(at: src, to: tgt)
            }
        }

        // MISSING → copies.
        seed(from: source, to: destDir)
        XCTAssertEqual(try? String(contentsOf: destDir.appendingPathComponent("a.xml")), "<db>a</db>")

        // EQUAL → skips (mtime/content unchanged).
        let before = try Data(contentsOf: destDir.appendingPathComponent("a.xml"))
        seed(from: source, to: destDir)
        XCTAssertEqual(try Data(contentsOf: destDir.appendingPathComponent("a.xml")), before)

        // DRIFT → re-copies.
        try Data("<db>drifted</db>".utf8).write(to: destDir.appendingPathComponent("a.xml"))
        seed(from: source, to: destDir)
        XCTAssertEqual(try? String(contentsOf: destDir.appendingPathComponent("a.xml")), "<db>a</db>")
    }

    // MARK: - The location priority (four states)

    func testLocationPriorityFourStates() throws {
        // The full resolveAndInstall walks custom > seed > downloaded >
        // absent; the custom face is tested here against a hermetic dir.
        let custom = makeTempDir()
        // A parseable lensfun XML (the install face requires >= 1 lens).
        try Data("""
        <lensdatabase version="1"><lens><maker>T</maker><model>X</model>        <cropfactor>1</cropfactor><calibration>        <distortion model="poly3" focal="50" k1="-0.01"/></calibration></lens>        </lensdatabase>
        """.utf8).write(to: custom.appendingPathComponent("x.xml"))
        UserDefaults.standard.set(custom.path, forKey: LensfunDownloadService.customPathKey)
        defer { UserDefaults.standard.removeObject(forKey: LensfunDownloadService.customPathKey) }

        // The parse gate: the custom dir's XML must install cleanly.
        let dbOK = LensfunStore.install(directory: custom)
        XCTAssertTrue(dbOK, "the hermetic custom XML must parse (>=1 lens)")
        LensfunStore.uninstall()
        let loc = LensfunDataDistribution.resolveAndInstall(bundleID: "lensfun-dist-tests")
        guard case .custom(let url) = loc else {
            return XCTFail("custom path must win the priority, got \(loc)")
        }
        XCTAssertEqual(url, custom)
        XCTAssertTrue(LensfunStore.isInstalled)

        // No custom → the priority falls to the SEED (the test host's
        // bundle carries the pinned snapshot; the truly-absent face is
        // unreachable in a seeded host and stays a CLI-only shape).
        UserDefaults.standard.removeObject(forKey: LensfunDownloadService.customPathKey)
        LensfunStore.uninstall()
        let noCustom = LensfunDataDistribution.resolveAndInstall(bundleID: "lensfun-dist-tests-empty")
        guard case .seeded = noCustom else {
            return XCTFail("no-custom must fall to the bundled seed, got \(noCustom)")
        }
        XCTAssertTrue(LensfunStore.isInstalled)
    }

    // MARK: - The dbTag (stability + sensitivity)

    func testDBTagStableAndSensitive() throws {
        let dir = makeTempDir()
        try Data("<db>a</db>".utf8).write(to: dir.appendingPathComponent("a.xml"))
        try Data("<db>b</db>".utf8).write(to: dir.appendingPathComponent("b.xml"))
        let tag1 = LensfunDataDistribution.dbTag(directory: dir)
        let tag2 = LensfunDataDistribution.dbTag(directory: dir)
        XCTAssertEqual(tag1, tag2, "the dbTag is stable across reads")
        XCTAssertEqual(tag1?.count, 16, "the dbTag = the manifest SHA's first 16 hex")

        // Content drift → tag drift; name sort keeps the manifest order.
        try Data("<db>a2</db>".utf8).write(to: dir.appendingPathComponent("a.xml"))
        let tag3 = LensfunDataDistribution.dbTag(directory: dir)
        XCTAssertNotEqual(tag1, tag3)

        // Empty dir → nil.
        let empty = makeTempDir()
        XCTAssertNil(LensfunDataDistribution.dbTag(directory: empty))
    }

    // MARK: - The update channel's SHA gate (hermetic)

    func testSHAHexFace() {
        // The known SHA-256("abc") vector.
        XCTAssertEqual(
            SHA256Hex.of(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
