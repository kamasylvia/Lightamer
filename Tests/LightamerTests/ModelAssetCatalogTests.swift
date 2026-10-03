import CryptoKit
import Foundation
import LightamerCore
import XCTest

/// ModelAssetCatalog invariants (plan M2-10-01 T1 / AC #1) + digest
/// fail-closed face + ModelLocator injection round-trips.
///
/// The bundled-digest/on-disk consistency test is RESOURCE-GATED (discipline
/// 6): in environments without the converted models it XCTSkips; it only
/// activates once T2 has populated `Resources/AIModels` and the digests.
final class ModelAssetCatalogTests: XCTestCase {

    // MARK: Catalog invariants (AC #1)

    func testProfileIDsAreUnique() {
        let ids = ModelAssetCatalog.allProfiles.map(\.profileID)
        XCTAssertEqual(ids.count, Set(ids).count, "profileID must be unique: \(ids)")
        XCTAssertEqual(ids.count, 5, "the catalog carries exactly five profiles")
    }

    func testBundledTierHasExactlyTwoProfiles() {
        XCTAssertEqual(
            ModelAssetCatalog.bundledProfiles.map(\.profileID),
            ["chinese-clip-vitb16-int8", "realesr-general-x4v3-fp16"]
        )
    }

    func testReleaseTagOnlyOnReleaseTier() {
        for profile in ModelAssetCatalog.allProfiles {
            switch profile.tier {
            case .bundled:
                XCTAssertNil(profile.releaseTag, "\(profile.profileID) bundled must have no release tag")
            case .gitHubRelease:
                XCTAssertFalse(
                    profile.releaseTag?.isEmpty ?? true,
                    "\(profile.profileID) release profile must pin a release tag"
                )
            }
        }
        XCTAssertEqual(
            Set(ModelAssetCatalog.releaseProfiles.map(\.releaseTag)),
            ["ai-models-v1"],
            "release profiles share the version-locked tag"
        )
    }

    func testEmbeddingDimLicenseAndLanguagesMatchResearchTable() {
        // RESEARCH-NOTES §6 volume/permission table (rulings OQ-1-B/2-A/3-B).
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        XCTAssertEqual(clip.embeddingDim, 512)
        XCTAssertEqual(clip.licenseName, "Apache-2.0")
        XCTAssertEqual(clip.textLanguages, ["zh", "en"])

        let jina = ModelAssetCatalog.jinaClipV2Int8
        XCTAssertEqual(jina.embeddingDim, 768)
        XCTAssertEqual(jina.licenseName, "Apache-2.0")
        XCTAssertEqual(jina.textLanguages, ["multilingual"])

        for id in ["realesr-general-x4v3-fp16", "real-esrgan-x4plus-fp16"] {
            let profile = ModelAssetCatalog.manifest(for: id)
            XCTAssertNotNil(profile)
            XCTAssertNil(profile?.embeddingDim, "enhancement family has no embedding dim")
            XCTAssertEqual(profile?.licenseName, "BSD-3-Clause")
        }
        let drunet = ModelAssetCatalog.drunetColorFP16
        XCTAssertNil(drunet.embeddingDim)
        XCTAssertEqual(drunet.licenseName, "MIT")
    }

    /// E4: the CLIP input size is the empirical 224² pin (HF config.json
    /// vision_config.image_size at the pinned revision) — never the 256²
    /// MobileCLIP2 figure. Enhancement profiles carry the 256 tile base.
    func testInputSizeEmpiricalPins() {
        XCTAssertEqual(ModelAssetCatalog.chineseClipViTB16Int8.inputSize, 224)
        XCTAssertEqual(ModelAssetCatalog.jinaClipV2Int8.inputSize, 512)
        for profile in [ModelAssetCatalog.realesrGeneralX4V3FP16,
                        ModelAssetCatalog.realESRGANX4PlusFP16,
                        ModelAssetCatalog.drunetColorFP16] {
            XCTAssertEqual(profile.inputSize, 256, "\(profile.profileID) tile base")
        }
    }

    func testManifestLookupRoundTrip() {
        for profile in ModelAssetCatalog.allProfiles {
            XCTAssertEqual(ModelAssetCatalog.manifest(for: profile.profileID), profile)
        }
        XCTAssertNil(ModelAssetCatalog.manifest(for: "no-such-profile"))
    }

    /// The revision pin locks the fallback URL family: HF fallback repo
    /// matches modelID for HF-native profiles.
    func testFallbackRepoMatchesModelIdentityForHFNativeProfiles() {
        XCTAssertEqual(
            ModelAssetCatalog.chineseClipViTB16Int8.hfFallback.repo,
            ModelAssetCatalog.chineseClipViTB16Int8.modelID
        )
        XCTAssertEqual(
            ModelAssetCatalog.jinaClipV2Int8.hfFallback.repo,
            ModelAssetCatalog.jinaClipV2Int8.modelID
        )
    }

    // MARK: Digest face (fail-closed)

    /// In-repo truth: the three release profiles are NOT yet uploaded →
    /// digests stay nil and `download` must refuse (fail-closed semantics
    /// tested end-to-end in ModelAssetStoreTests).
    func testReleaseDigestsUnpublishedFailClosed() {
        for profile in ModelAssetCatalog.releaseProfiles {
            XCTAssertNil(
                ModelAssetDigests.digest(for: profile.profileID),
                "\(profile.profileID) release digest must stay nil until the asset is uploaded"
            )
        }
        XCTAssertNil(ModelAssetDigests.digest(for: "unknown-profile"))
    }

    /// RESOURCE-GATED. When the bundled digests are published (post-T2) the
    /// on-disk bundled assets must match them byte-for-byte (AC #2's
    /// catalog half; the store half lives in ModelAssetStoreTests).
    func testBundledDigestConsistentWithOnDiskAssets() throws {
        let locator = ModelLocator()
        guard locator.bundledRoot() != nil else {
            throw XCTSkip("bundled AIModels folder absent in this environment (resource gate)")
        }
        for profile in ModelAssetCatalog.bundledProfiles {
            guard let digest = ModelAssetDigests.digest(for: profile.profileID) else {
                // Conversion pipeline has not run for this profile yet (T2
                // ordering): nothing to verify here.
                continue
            }
            let primary = try XCTUnwrap(
                locator.bundledAssetURL(profile.assetFileName, profileID: profile.profileID),
                "digest published but primary asset missing: \(profile.profileID)"
            )
            // Directory artifacts (.mlpackage) verify via the canonical tree
            // hash — the SAME algorithm the digest-rewrite script used.
            XCTAssertEqual(
                try ModelAssetStore.artifactDigestHex(of: primary),
                digest.sha256Hex,
                "\(profile.profileID) primary digest mismatch"
            )
            XCTAssertEqual(
                try ModelAssetStore.artifactByteCount(of: primary),
                digest.byteCount,
                "\(profile.profileID) primary byte count mismatch"
            )
            for auxiliary in digest.auxiliaryFiles {
                let url = try XCTUnwrap(
                    locator.bundledAssetURL(auxiliary.fileName, profileID: profile.profileID),
                    "auxiliary missing: \(profile.profileID)/\(auxiliary.fileName)"
                )
                XCTAssertEqual(
                    try ModelAssetStore.artifactDigestHex(of: url),
                    auxiliary.sha256Hex,
                    "\(profile.profileID)/\(auxiliary.fileName) digest mismatch"
                )
            }
        }
    }

    // MARK: ModelLocator injection round-trips

    func testLocatorBundledProbeWithInjectedRoot() throws {
        let temp = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let profileDir = temp.appendingPathComponent("chinese-clip-vitb16-int8", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try Data("vocab".utf8).write(to: profileDir.appendingPathComponent("vocab.txt"))

        let locator = ModelLocator(bundledRootOverride: temp)
        XCTAssertEqual(locator.bundledRoot(), temp)
        XCTAssertEqual(
            locator.bundledProfileURL("chinese-clip-vitb16-int8"),
            profileDir
        )
        XCTAssertEqual(
            locator.bundledAssetURL("vocab.txt", profileID: "chinese-clip-vitb16-int8"),
            profileDir.appendingPathComponent("vocab.txt")
        )
        XCTAssertNil(locator.bundledProfileURL("missing-profile"))
        XCTAssertNil(locator.bundledAssetURL("missing.txt", profileID: "chinese-clip-vitb16-int8"))
    }

    func testLocatorBundledProbeNilWhenOverrideAbsent() throws {
        let temp = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let missing = temp.appendingPathComponent("does-not-exist")
        let locator = ModelLocator(bundledRootOverride: missing)
        XCTAssertNil(locator.bundledRoot())
        XCTAssertNil(locator.bundledProfileURL("chinese-clip-vitb16-int8"))
    }

    func testLocatorInstallationRootWithInjectedOverride() throws {
        let temp = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let locator = ModelLocator(installationRootOverride: temp)
        XCTAssertEqual(try locator.installationRoot(), temp)

        let profile = try locator.installedProfileURL("jina-clip-v2-int8")
        XCTAssertEqual(
            profile,
            temp.appendingPathComponent("jina-clip-v2-int8", isDirectory: true)
        )
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        // L009: the scratch directory is a SAME-PARENT sibling, never /tmp.
        let tmp = try locator.installedProfileTmpURL("jina-clip-v2-int8")
        XCTAssertEqual(tmp.deletingLastPathComponent(), temp)
        XCTAssertEqual(tmp.lastPathComponent, "jina-clip-v2-int8.tmp")
    }

    func testLocatorDefaultInstallationRootUnderAppSupport() throws {
        let locator = ModelLocator()
        let root = try locator.installationRoot()
        XCTAssertTrue(root.path.contains("Application Support"), "unexpected root: \(root.path)")
        XCTAssertTrue(root.path.hasSuffix("/Lightamer/models"), "unexpected root: \(root.path)")
        defer { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: Helpers

    static func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("modelasset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Streaming SHA-256 (CryptoKit) — the same digest discipline the store
    /// uses, never a mock hash (checker E1).
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
