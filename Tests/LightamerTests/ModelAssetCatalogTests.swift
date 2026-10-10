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
        XCTAssertEqual(ids.count, 6, "the catalog carries exactly six profiles (M4-3-01 depth additive)")
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

    /// In-repo truth: the three pre-depth release profiles are NOT yet
    /// uploaded → digests stay nil and `download` must refuse (fail-closed
    /// semantics tested end-to-end in ModelAssetStoreTests). The DEPTH
    /// profile's digest IS published at build time (M4-3-01 T1 — the
    /// digest-before-upload order is plan-sanctioned; a 404 download
    /// surfaces as typed allSourcesFailed, no half state).
    func testReleaseDigestsUnpublishedFailClosed() {
        for profile in ModelAssetCatalog.releaseProfiles
        where profile.profileID != ModelAssetCatalog.depthAnythingV2SmallF16.profileID {
            XCTAssertNil(
                ModelAssetDigests.digest(for: profile.profileID),
                "\(profile.profileID) release digest must stay nil until the asset is uploaded"
            )
        }
        XCTAssertNil(ModelAssetDigests.digest(for: "unknown-profile"))
    }

    /// M4-3-01 T1: the depth digest is published in-repo. The in-repo
    /// assertable face is the VALUE FORMAT + positive byte count; the
    /// byteCount==zip equality lives in the build script's self-check
    /// (checker m4 prescription ①) + M4-3-01-DECISIONS §1 (the zip is a
    /// repo-external machine artifact, invisible to LIB).
    func testDepthDigestPublishedValueFormat() throws {
        let digest = try XCTUnwrap(
            ModelAssetDigests.digest(for: ModelAssetCatalog.depthAnythingV2SmallF16.profileID),
            "depth digest must be published (build-depth-release-asset.sh)")
        XCTAssertEqual(digest.sha256Hex.count, 64, "SHA-256 hex length")
        XCTAssertTrue(digest.sha256Hex.allSatisfy(\.isHexDigit), "hex alphabet")
        XCTAssertEqual(digest.sha256Hex, digest.sha256Hex.lowercased(), "lowercase hex")
        XCTAssertGreaterThan(digest.byteCount, 40_000_000, "F16 zip sanity band")
        XCTAssertLessThan(digest.byteCount, 55_000_000, "F16 zip sanity band")
        XCTAssertTrue(digest.auxiliaryFiles.isEmpty, "single-archive release")
    }

    // MARK: Depth profile (M4-3-01 T1, OQ-7 + KD-1)

    func testDepthProfileInvariants() {
        let depth = ModelAssetCatalog.depthAnythingV2SmallF16
        XCTAssertEqual(depth.profileID, "depth-anything-v2-small-f16")
        XCTAssertEqual(depth.modelID, "apple/coreml-depth-anything-v2-small")
        XCTAssertEqual(depth.revision, "cfef6f6f2a70783dedc0bfae40cecbc2052285d3")
        XCTAssertEqual(depth.licenseName, "Apache-2.0", "Apache-2.0 all the way down (AC#12)")
        XCTAssertEqual(depth.tier, .gitHubRelease)
        XCTAssertEqual(depth.releaseTag, "ai-models-v1")
        XCTAssertEqual(depth.assetFileName, "depth-anything-v2-small-f16.mlpackage.zip")
        XCTAssertEqual(depth.inputSize, 518, "long edge")
        XCTAssertEqual(depth.inputShortEdge, 392, "short edge — D-4 spike pin (NOT the plan's transcribed 396)")
        XCTAssertNil(depth.embeddingDim)
        XCTAssertTrue(depth.textLanguages.isEmpty)
    }

    /// OQ-7 zero-drift: the five pre-depth profiles keep the square-input
    /// semantics (short edge nil) — the additive optional touches nothing.
    func testShortEdgeNilOnPreDepthProfiles() {
        for profile in ModelAssetCatalog.allProfiles
        where profile.family != .depth {
            XCTAssertNil(
                profile.inputShortEdge,
                "\(profile.profileID) must keep nil shortEdge (zero-drift)")
        }
    }

    /// The family discriminant's six-profile exhaustiveness (KD-1 single
    /// source; checker m5's routing钉 relies on this + o2's precedence).
    func testFamilyExhaustiveOverAllProfiles() {
        var counts: [ModelAssetFamily: Int] = [:]
        for profile in ModelAssetCatalog.allProfiles {
            counts[profile.family, default: 0] += 1
        }
        XCTAssertEqual(counts[.clip], 2, "chinese-clip + jina-clip")
        XCTAssertEqual(counts[.enhancement], 3, "realesr + x4plus + drunet")
        XCTAssertEqual(counts[.depth], 1, "depth-anything-v2-small-f16")
        XCTAssertEqual(counts.values.reduce(0, +), 6)
        // The precedence rule (o2): clip marker wins over a depth marker.
        XCTAssertEqual(
            ModelAssetCatalog.chineseClipViTB16Int8.family, .clip)
        XCTAssertEqual(
            ModelAssetCatalog.depthAnythingV2SmallF16.family, .depth)
        // == folds the additive line (the round-trip through the catalog
        // exercises the new comparison row).
        XCTAssertEqual(
            ModelAssetCatalog.manifest(for: "depth-anything-v2-small-f16"),
            ModelAssetCatalog.depthAnythingV2SmallF16)
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
