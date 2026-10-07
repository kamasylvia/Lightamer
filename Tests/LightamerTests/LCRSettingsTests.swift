import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// LCRSettingsTests (Plan M2-10-07 T2, AC#1) — the LCR settings page's model
// face over a REAL ModelAssetStore + temp-dir locator (the E1 true-chain
// discipline) + a temp-path CompatRecord + a real AIAnalysisRegistry:
//
//   • the status → copy/action mapping (the six-state direct projection,
//     including the fail-closed 「待发布」 awaiting-release face)
//   • canActivate: embedding models with usable assets only — a download-only
//     semantic profile can never arm the recompute
//   • refresh(): the five catalog tiers + the release profiles' unpublished
//     digests surface as awaiting-release (the M2-10-01 fail-closed UI leg)
//   • 换激活 → the registry's recomputeAll ENQUEUE assertion (a real
//     registry drains the task; taskDidFinish carries the kind)
//   • the compatibility-record reset → file-gone terminal state
//   • the readiness probe three-state face (probing → ready / unavailable)
//   • the labeling three-choice round-trip + reset (the 03 assignment)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LCRSettingsTests: XCTestCase {

    private var suiteName: String!
    private var tempRoot: URL!
    private var locator: ModelLocator!
    private var assetStore: ModelAssetStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.lcr.\(UUID().uuidString)"
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lcr-tests-\(UUID().uuidString)", isDirectory: true)
        locator = ModelLocator(installationRootOverride: tempRoot)
        assetStore = ModelAssetStore(locator: locator)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeModel(
        registry: AIAnalysisRegistry? = nil,
        compatRecord: CompatRecord? = nil,
        workerProbe: @escaping @MainActor () async -> LCRSettingsModel.Readiness = { .ready },
        activeModelKeyProvider: @escaping @MainActor () async -> String? = { nil }
    ) -> LCRSettingsModel {
        LCRSettingsModel(
            store: assetStore,
            compatRecord: compatRecord ?? CompatRecord(
                path: tempRoot.appendingPathComponent("ai-compat.json")),
            labeling: LabelingPreferences(defaultsSuiteName: suiteName),
            registry: registry,
            activeModelKeyProvider: activeModelKeyProvider,
            workerProbe: workerProbe)
    }

    /// A real registry over nil providers: the drain fail-closes typed (the
    /// store-unavailable face) — the ENQUEUE assertion rides `taskDidFinish`.
    private func makeRegistry() -> AIAnalysisRegistry {
        AIAnalysisRegistry(
            backgroundRegistry: BackgroundTaskRegistry(),
            storeProvider: { nil },
            engineProvider: { nil },
            prototypesProvider: { nil },
            projectDirectoryProvider: { nil })
    }

    private func row(_ model: LCRSettingsModel, _ profileID: String)
        -> LCRSettingsModel.TierRow {
        model.rows.first { $0.manifest.profileID == profileID }!
    }

    // MARK: - 1: the status projection (pure face)

    func testStatusProjectionMapsEveryState() {
        let manifest = ModelAssetCatalog.chineseClipViTB16Int8

        func row(_ status: ModelAssetStatus) -> LCRSettingsModel.TierRow {
            LCRSettingsModel.TierRow(
                manifest: manifest, byteCount: 190_000_000, status: status,
                isActiveModel: false)
        }

        XCTAssertEqual(row(.bundled).action, .builtIn)
        XCTAssertEqual(row(.bundled).statusCopy, String(localized: "settings_lcr_status_bundled", defaultValue: "Built in"))
        XCTAssertEqual(row(.installed).action, .remove)
        XCTAssertEqual(row(.downloading(0.4)).action, .downloading)
        XCTAssertTrue(row(.downloading(0.4)).statusCopy.contains("40"))
        XCTAssertEqual(row(.corrupt).action, .download, "corrupt self-heals by re-download")
        XCTAssertEqual(
            row(.digestUnpublished).action, .awaitingRelease,
            "an unpublished digest is the fail-closed 「待发布」 face — download is refused")
        XCTAssertEqual(row(.notInstalled).action, .download)
        // The size face: a digest-less tier shows the placeholder.
        var unpublished = row(.digestUnpublished)
        unpublished = LCRSettingsModel.TierRow(
            manifest: manifest, byteCount: nil,
            status: .digestUnpublished, isActiveModel: false)
        XCTAssertNil(unpublished.sizeCopy)
        XCTAssertNotNil(row(.bundled).sizeCopy)
    }

    func testCanActivateRequiresUsableSemanticAssets() {
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        let realesr = ModelAssetCatalog.realesrGeneralX4V3FP16

        func row(_ manifest: ModelAssetManifest, _ status: ModelAssetStatus)
            -> LCRSettingsModel.TierRow {
            LCRSettingsModel.TierRow(
                manifest: manifest, byteCount: nil, status: status,
                isActiveModel: false)
        }

        XCTAssertTrue(row(clip, .bundled).canActivate)
        XCTAssertTrue(row(clip, .installed).canActivate)
        XCTAssertFalse(
            row(clip, .notInstalled).canActivate,
            "a download-only semantic profile cannot arm the recompute (no weights)")
        XCTAssertFalse(
            row(clip, .digestUnpublished).canActivate)
        XCTAssertFalse(
            row(realesr, .bundled).canActivate,
            "enhancement tiers are not semantic models — no activation arm")
    }

    // MARK: - 2: refresh over the real store (temp locator)

    func testRefreshBuildsFiveRowsWithFailClosedReleaseFaces() async {
        let model = makeModel(workerProbe: { .ready })
        await model.refresh()
        XCTAssertEqual(model.rows.count, 5, "the whole M2-10-01 catalog")
        XCTAssertEqual(model.readiness, .ready)

        // The two bundled profiles: present in the test host's bundle.
        XCTAssertEqual(row(model, "chinese-clip-vitb16-int8").action, .builtIn)
        XCTAssertEqual(row(model, "realesr-general-x4v3-fp16").action, .builtIn)

        // The three release profiles: digests unpublished (the 01 wave
        // fail-closed state) → 「待发布」 with no download button.
        for id in ["jina-clip-v2-int8", "real-esrgan-x4plus-fp16", "drunet-color-fp16"] {
            XCTAssertEqual(
                row(model, id).action, .awaitingRelease,
                "\(id) digest is nil — download refused, honest copy shown")
            XCTAssertNil(row(model, id).sizeCopy)
        }
    }

    func testRemoveDropsTheInstalledArtifactToTerminalState() async throws {
        // Seed an installed artifact for the CLIP profile in the temp root.
        // The compiled digest for jina is nil (unpublished), so the store
        // reads a digest-matching artifact through an INJECTED digest
        // provider (the .installed leg needs a published digest to verify).
        let manifest = ModelAssetCatalog.jinaClipV2Int8
        let profileDir = try locator.installedProfileURL(manifest.profileID)
        let artifact = profileDir.appendingPathComponent(manifest.assetFileName)
        let payload = Data("installed-artifact-stub".utf8)
        try payload.write(to: artifact)
        let digest = ModelAssetDigestEntry(
            sha256Hex: try ModelAssetStore.artifactDigestHex(of: artifact),
            byteCount: payload.count, auxiliaryFiles: [], generatedAt: "test")
        // The model sees a store whose digest provider knows the seeded
        // artifact (the store's other faces stay the real ones).
        let model = LCRSettingsModel(
            store: ModelAssetStore(
                manifestProvider: { ModelAssetCatalog.manifest(for: $0) },
                digestProvider: { $0 == manifest.profileID ? digest : nil },
                locator: locator),
            compatRecord: CompatRecord(
                path: tempRoot.appendingPathComponent("ai-compat.json")),
            labeling: LabelingPreferences(defaultsSuiteName: suiteName),
            registry: nil,
            activeModelKeyProvider: { nil },
            workerProbe: { .ready })
        await model.refresh()
        XCTAssertEqual(row(model, manifest.profileID).status, .installed)

        await model.remove(manifest.profileID)
        // Terminal state: the profile directory is GONE (tmp scratch too).
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: profileDir.path),
            "the reset face leaves no installed artifact behind")
        await model.refresh()
        // With the injected digest the profile is DOWNLOADABLE after removal
        // (notInstalled); the compiled digests for the release family are nil
        // — that fail-closed face is pinned by
        // testRefreshBuildsFiveRowsWithFailClosedReleaseFaces.
        XCTAssertEqual(row(model, manifest.profileID).status, .notInstalled)
    }

    // MARK: - 3: 换激活 → the registry enqueue (the OQ-9-A arm)

    func testActivateEnqueuesRecomputeAllIntoTheRegistry() async throws {
        let registry = makeRegistry()
        let finished = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AIAnalysisTaskKind, Error>) in
            var landed = false
            registry.taskDidFinish = { _, kind, _ in
                guard !landed else { return }
                landed = true
                continuation.resume(returning: kind)
            }
            let model = makeModel(
                registry: registry,
                workerProbe: { .ready },
                activeModelKeyProvider: { "chinese-clip-vitb16-int8" })
            // The activate face (the view's confirm-accept leg, verbatim).
            model.enqueueRecompute(newModelKey: "jina-clip-v2-int8")
            XCTAssertTrue(
                model.recomputeActive,
                "the page shows the 「重算中」 state immediately (the bar carries progress)")
        }
        guard case .recomputeAll(let key) = finished else {
            return XCTFail("expected a recomputeAll task, got \(finished)")
        }
        XCTAssertEqual(key, "jina-clip-v2-int8")
    }

    func testActivateWithoutARegistrySurfacesTypedCopy() {
        let model = makeModel(registry: nil)
        model.enqueueRecompute(newModelKey: "jina-clip-v2-int8")
        XCTAssertFalse(model.recomputeActive)
        XCTAssertNotNil(model.statusLine, "the no-registry face is honest copy")
    }

    // MARK: - 4: the compatibility-record reset (D-6)

    func testCompatResetDeletesTheFile() throws {
        let path = tempRoot.appendingPathComponent("ai-compat.json")
        let record = CompatRecord(path: path)
        // Seed a crash entry (the file exists on disk).
        record.record(
            machineKey: "MacTest/27A1", model: "chinese-clip-vitb16-int8",
            units: .all, detail: "boom")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        let model = makeModel(compatRecord: record)
        model.resetCompatibilityRecord()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path.path),
            "the reset face deletes the record file — every combination retries")
        XCTAssertNotNil(model.statusLine)
    }

    // MARK: - 5: the readiness probe three-state face

    func testReadinessProbeStates() async {
        let probing = makeModel(workerProbe: { .ready })
        XCTAssertEqual(probing.readiness, .probing, "before the first refresh")
        await probing.refresh()
        XCTAssertEqual(probing.readiness, .ready)

        let broken = makeModel(workerProbe: {
            .unavailable("worker unavailable: spawn failed")
        })
        await broken.refresh()
        XCTAssertEqual(broken.readiness, .unavailable("worker unavailable: spawn failed"))
    }

    func testActiveModelBadgeFollowsTheProvider() async {
        let model = makeModel(
            workerProbe: { .ready },
            activeModelKeyProvider: { "chinese-clip-vitb16-int8" })
        await model.refresh()
        XCTAssertTrue(row(model, "chinese-clip-vitb16-int8").isActiveModel)
        XCTAssertFalse(row(model, "jina-clip-v2-int8").isActiveModel)
    }

    // MARK: - 6: the labeling three-choice (the 03 assignment)

    func testLabelingModeRoundTripAndReset() {
        let model = makeModel(workerProbe: { .ready })
        XCTAssertEqual(model.labelingMode, .ask, "the safe default")
        model.setLabelingMode(.never)
        XCTAssertEqual(model.labelingMode, .never)
        // Persisted through the SAME preferences face (a fresh reader sees it).
        XCTAssertEqual(
            LabelingPreferences(defaultsSuiteName: suiteName).mode, .never)
        model.resetLabelingPreference()
        XCTAssertEqual(model.labelingMode, .ask)
        XCTAssertNil(
            UserDefaults(suiteName: suiteName)?
                .string(forKey: LabelingPreferences.modeKey),
            "the reset clears the key (back to the .ask fallback)")
    }
}
