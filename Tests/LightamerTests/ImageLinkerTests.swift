import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImageLinkerTests (Plan M2-2-2 T2) — the KD-3 resolve/stale/relink data face:
//
//   • kind0 project-relative: the project directory RENAMES wholesale and
//     the row still resolves (the mount-point/move immunity re-pin)
//   • kind1 volume-relative: same-volume hit through the UUID fast path;
//     a recorded UUID no mounted volume carries → `.volumeAbsent`
//   • kind2 absolute: hit / file deleted → `.pathMissing`
//   • relink: a stale row re-pointed at a new directory rebuilds
//     kind/uuid/path correctly and resolves again
//
// All fixtures in NSTemporaryDirectory (L009: never external volume); the
// cross-volume legs ride the `uuidProbe` seam, never real hardware.
// ─────────────────────────────────────────────────────────────────────────────

final class ImageLinkerTests: XCTestCase {

    private var root: URL!
    private var projectDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("image-linker-\(UUID().uuidString)", isDirectory: true)
        projectDirectory = root.appendingPathComponent("Proj", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFile(_ path: String, bytes: [UInt8] = [0x41, 0x42]) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        return url
    }

    private func resolve(
        _ imagePath: String, kind: LibrarySchema.PathKind, uuid: String?,
        project: URL? = nil
    ) -> ImageLinkResolution {
        ImageLinker.resolve(
            imagePath: imagePath, pathKind: kind, volumeUUID: uuid,
            projectDirectory: project ?? projectDirectory)
    }

    // MARK: - kind0 (project-relative)

    func testKind0ResolvesUnderProjectDirectory() throws {
        try makeFile("Proj/Media/Card1/DSC00001.ARW")
        let resolution = resolve("Media/Card1/DSC00001.ARW", kind: .projectRelative, uuid: nil)
        XCTAssertEqual(
            resolution,
            .resolved(projectDirectory.appendingPathComponent("Media/Card1/DSC00001.ARW")))
    }

    func testKind0SurvivesWholeDirectoryRename() throws {
        // The mount-point-immunity semantic: the project directory renames
        // wholesale and the project-relative row STILL resolves (the KD-3
        // kind0 contract; moveProject's guarantee).
        try makeFile("Proj/Media/DSC00001.ARW")
        let renamed = root.appendingPathComponent("Proj-Renamed", isDirectory: true)
        try FileManager.default.moveItem(at: projectDirectory, to: renamed)
        let resolution = resolve(
            "Media/DSC00001.ARW", kind: .projectRelative, uuid: nil, project: renamed)
        XCTAssertEqual(
            resolution, .resolved(renamed.appendingPathComponent("Media/DSC00001.ARW")))
    }

    func testKind0MissingFileIsPathMissing() {
        XCTAssertEqual(
            resolve("Media/gone.ARW", kind: .projectRelative, uuid: nil),
            .stale(.pathMissing))
    }

    // MARK: - kind1 (volume-relative + UUID)

    func testKind1SameVolumeResolvesThroughUUIDFastPath() throws {
        let file = try makeFile("outside/DSC00002.ARW")
        // Store the carrier the way the importer does: UUID of the real
        // volume + path relative to the real mount point.
        let record = ImageLinker.record(for: file, projectDirectory: projectDirectory)
        XCTAssertEqual(record.pathKind, .volumeRelative, "same volume → kind1")
        let resolution = resolve(
            record.imagePath, kind: record.pathKind, uuid: record.volumeUUID)
        XCTAssertEqual(resolution, .resolved(file))
    }

    func testKind1RecordIsRelativeToVolumeRootNotProject() throws {
        // The kind1 spelling is relative to the MOUNT POINT (immune to
        // mount renames), NOT to the project directory — pin the shape.
        let file = try makeFile("outside/DSC00003.ARW")
        let record = ImageLinker.record(for: file, projectDirectory: projectDirectory)
        XCTAssertFalse(
            record.imagePath.hasPrefix("Proj/"),
            "kind1 must be volume-relative, got \(record.imagePath)")
        XCTAssertEqual(record.volumeUUID, ImageLinker.volumeUUID(of: file))
    }

    func testKind1UnknownUUIDIsVolumeAbsent() {
        // No mounted volume carries this UUID → the typed "why broken".
        XCTAssertEqual(
            resolve("somewhere/DSC00004.ARW", kind: .volumeRelative,
                    uuid: "00000000-0000-0000-0000-000000000000"),
            .stale(.volumeAbsent))
    }

    func testKind1NilUUIDIsVolumeAbsent() {
        XCTAssertEqual(
            resolve("somewhere/DSC00005.ARW", kind: .volumeRelative, uuid: nil),
            .stale(.volumeAbsent))
    }

    func testKind1UUIDMatchButFileGoneIsPathMissing() throws {
        // The volume IS present (project fast path matches) but the file
        // vanished — pathMissing, not volumeAbsent.
        let file = try makeFile("outside/DSC00006.ARW")
        let record = ImageLinker.record(for: file, projectDirectory: projectDirectory)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(
            resolve(record.imagePath, kind: record.pathKind, uuid: record.volumeUUID),
            .stale(.pathMissing))
    }

    // MARK: - kind2 (absolute + UUID)

    func testKind2ResolvesAbsolutePath() throws {
        let file = try makeFile("outside/DSC00007.ARW")
        let resolution = resolve(
            file.path, kind: .absolute, uuid: ImageLinker.volumeUUID(of: file))
        XCTAssertEqual(resolution, .resolved(file))
    }

    func testKind2DeletedFileIsPathMissing() throws {
        let file = try makeFile("outside/DSC00008.ARW")
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(resolve(file.path, kind: .absolute, uuid: nil), .stale(.pathMissing))
    }

    // MARK: - relink (rebuild kind/uuid/path)

    func testRelinkRebuildsCarrierForNewLocation() throws {
        // A stale row (volume gone) relinks at a fresh same-volume folder:
        // the rebuilt carrier is kind1/real-UUID again and resolves.
        try makeFile("fresh/DSC00009.ARW")
        let newSource = root.appendingPathComponent("fresh/DSC00009.ARW")
        let record = ImageLinker.relinkRecord(
            for: newSource, projectDirectory: projectDirectory)
        XCTAssertEqual(record.pathKind, .volumeRelative)
        XCTAssertEqual(record.volumeUUID, ImageLinker.volumeUUID(of: projectDirectory))
        let resolution = resolve(
            record.imagePath, kind: record.pathKind, uuid: record.volumeUUID)
        XCTAssertEqual(resolution, .resolved(newSource))
    }

    func testRecordDegradesTypedToAbsoluteWhenUUIDUnavailable() throws {
        let file = try makeFile("outside/DSC00010.ARW")
        // The probe returns nil (the unobtainable-UUID reality on some
        // filesystems) → the typed kind2 degradation, absolute path kept.
        let record = ImageLinker.record(
            for: file, projectDirectory: projectDirectory,
            uuidProbe: { _ in nil })
        XCTAssertEqual(record.pathKind, .absolute)
        XCTAssertNil(record.volumeUUID)
        XCTAssertEqual(record.imagePath, file.path)
    }

    func testRecordForcedCrossVolumeLegIsAbsolute() throws {
        let file = try makeFile("outside/DSC00011.ARW")
        // The probe seam (test-only): source and project on "different"
        // volumes → the absolute + UUID fallback.
        let record = ImageLinker.record(
            for: file, projectDirectory: projectDirectory,
            uuidProbe: { url in url.path.contains("Proj") ? "vol-p" : "vol-s" })
        XCTAssertEqual(record.pathKind, .absolute)
        XCTAssertEqual(record.volumeUUID, "vol-s")
        XCTAssertEqual(record.imagePath, file.path)
    }

    // MARK: - volume identity helpers

    func testVolumeRootPlusStoredRelativeReconstructsTheFile() throws {
        let file = try makeFile("outside/DSC00012.ARW")
        guard let rootURL = ImageLinker.volumeRoot(of: file) else {
            return XCTFail("statfs must resolve a mount point")
        }
        let relative = ImageLinker.relativePath(of: file, from: rootURL)
        // One of the two stored spellings (mount-relative or /-rooted,
        // the firmlink reality) must reconstruct the file exactly.
        let reconstructed = ImageLinker.kind1Candidates(
            imagePath: relative, volume: rootURL)
        XCTAssertTrue(
            reconstructed.contains(file),
            "candidates \(reconstructed.map(\.path)) must contain \(file.path)")
    }

    func testFirmlinkPathsStoreRootSpellingAndResolve() throws {
        // Root-volume temp paths (/var/folders/...) do NOT carry the Data
        // mount prefix (/System/Volumes/Data) — the stored spelling falls
        // back to /-rooted and still resolves through the UUID fast path.
        let file = try makeFile("outside/DSC00013.ARW")
        let record = ImageLinker.record(for: file, projectDirectory: projectDirectory)
        XCTAssertEqual(record.pathKind, .volumeRelative)
        guard let rootURL = ImageLinker.volumeRoot(of: file) else {
            return XCTFail("statfs must resolve a mount point")
        }
        if rootURL.path != "/" {
            XCTAssertFalse(
                file.path.hasPrefix(rootURL.path + "/"),
                "precondition: the fixture lives under a firmlink spelling")
        }
        XCTAssertEqual(
            ImageLinker.resolve(
                imagePath: record.imagePath, pathKind: record.pathKind,
                volumeUUID: record.volumeUUID, projectDirectory: projectDirectory),
            .resolved(file))
    }
}
