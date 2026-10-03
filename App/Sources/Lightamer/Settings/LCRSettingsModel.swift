import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// LCRSettingsModel (Plan M2-10-07 T2, KD-1) — the Local Content Recognition
// settings page's pure-logic face (the ACASettingsModel shape: dependencies
// injected, zero business logic in the view).
//
// OWNERSHIP:
//   • the five-tier model list (the M2-10-01 Catalog) — per tier: the
//     profile name / embedding dim / license / byte size / distribution
//     badge (bundled vs download) / the ModelAssetStatus face;
//   • the actions — download & remove (release tiers), the fail-closed
//     「待发布」face for an unpublished digest, and the CLIP-family 换激活
//     (OQ-9-A: confirm → `registry.recomputeAll` enqueue; the progress rides
//     the shell's BackgroundTask bar — the page only shows the 「重算中」
//     state, never a second progress face);
//   • the compatibility-record reset (D-M2-10-CONTEXT-6: `CompatRecord
//     .resetAll()`, confirmed);
//   • the auto-labeling ask-mode three-choice (the M2-10-03 handoff's page
//     assignment) over `LabelingPreferences`;
//   • the readiness probe (KD-1: worker ping + bundled-asset presence —
//     the `.workerUnavailable` degradation's user-visible face);
//   • the local data-policy statement (本地推理不上云).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class LCRSettingsModel {

    // MARK: - Row face (the pure presentation projection — test-pinned)

    struct TierRow: Identifiable, Equatable {
        let manifest: ModelAssetManifest
        /// The published digest's byte count (nil = unpublished — the size
        /// column shows 「—」 and the release download stays disabled).
        let byteCount: Int?
        let status: ModelAssetStatus
        /// The current active semantic model's key (CLIP family only).
        let isActiveModel: Bool

        var id: String { manifest.profileID }

        /// The CLIP family (the 换激活 arm) — an embedding model.
        var isSemanticModel: Bool { manifest.embeddingDim != nil }

        /// Whether 换激活 may arm: an embedding model whose assets are
        /// actually usable (bundled / installed — never a download-only
        /// profile: re-embedding needs the weights on disk).
        var canActivate: Bool {
            guard isSemanticModel else { return false }
            switch status {
            case .bundled, .installed: return true
            default: return false
            }
        }

        /// The status column copy (the five/six-state direct mapping).
        var statusCopy: String {
            switch status {
            case .bundled:
                String(localized: "settings_lcr_status_bundled",
                       defaultValue: "Built in")
            case .installed:
                String(localized: "settings_lcr_status_installed",
                       defaultValue: "Installed")
            case .notInstalled:
                String(localized: "settings_lcr_status_not_installed",
                       defaultValue: "Not downloaded")
            case .downloading(let fraction):
                String(localized: "settings_lcr_status_downloading \(Int(fraction * 100))")
            case .corrupt:
                String(localized: "settings_lcr_status_corrupt",
                       defaultValue: "Corrupted — re-download to repair")
            case .digestUnpublished:
                String(localized: "settings_lcr_status_unpublished",
                       defaultValue: "Awaiting release")
            }
        }

        /// The row action face (the view renders exactly one).
        enum Action: Equatable {
            /// Download (release tiers with a published digest).
            case download
            /// Remove the installed copy (release tiers, installed).
            case remove
            /// Download disabled — the digest was never published.
            case awaitingRelease
            /// A download is in flight (no action button).
            case downloading
            /// Bundled — nothing to download or remove.
            case builtIn
        }

        var action: Action {
            switch status {
            case .bundled:
                return .builtIn
            case .installed:
                return .remove
            case .downloading:
                return .downloading
            case .digestUnpublished:
                return .awaitingRelease
            case .notInstalled, .corrupt:
                return .download
            }
        }

        /// The size column text (nil digest → 「—」).
        var sizeCopy: String? {
            guard let byteCount else { return nil }
            let mb = Double(byteCount) / (1024 * 1024)
            return String(localized: "settings_lcr_size_mb \(String(format: "%.0f", mb))")
        }
    }

    // MARK: - Readiness probe face

    enum Readiness: Equatable {
        case probing
        /// Worker answers AND the bundled CLIP assets are present.
        case ready
        /// The honest degradation face (the reason is display copy).
        case unavailable(String)
    }

    // MARK: - Dependencies (injected; tests drive every seam)

    private let store: ModelAssetStore
    private let compatRecord: CompatRecord
    private let labeling: LabelingPreferences
    /// The AI task registry (the recompute enqueue); nil = the arm surfaces
    /// its typed no-registry face (no open project / tests without one).
    private let registry: AIAnalysisRegistry?
    /// The active semantic model's key reader (the `semantic_model.active`
    /// row; nil = no open project).
    private let activeModelKeyProvider: @MainActor () async -> String?
    /// The worker liveness probe (a real ping; tests inject stubs).
    private let workerProbe: @MainActor () async -> Readiness

    // MARK: - Observable state

    private(set) var rows: [TierRow] = []
    private(set) var readiness: Readiness = .probing
    /// The 页内「重算中」state (the bar carries the progress itself).
    private(set) var recomputeActive = false
    private(set) var statusLine: String?
    private(set) var labelingMode: LabelingMode = .ask

    init(
        store: ModelAssetStore = ModelAssetStore(),
        compatRecord: CompatRecord = CompatRecord(
            path: CompatRecord.defaultPath()),
        labeling: LabelingPreferences = LabelingPreferences(),
        registry: AIAnalysisRegistry? = nil,
        activeModelKeyProvider: @escaping @MainActor () async -> String? = { nil },
        workerProbe: @escaping @MainActor () async -> Readiness = {
            // The PRODUCTION probe (KD-1): bundled-asset presence first (a
            // cheap file probe), then one real worker ping — the honest
            // 「AI 就绪」 line and the `.workerUnavailable` visibility.
            let locator = ModelLocator()
            let clip = ModelAssetCatalog.chineseClipViTB16Int8
            guard locator.bundledProfileURL(clip.profileID) != nil else {
                return .unavailable(String(
                    localized: "settings_lcr_probe_no_assets",
                    defaultValue: "AI model assets missing from the app bundle."))
            }
            let client = AIWorkerClient(
                record: CompatRecord(path: CompatRecord.defaultPath()))
            defer { Task { await client.stop() } }
            do {
                _ = try await client.ping()
                return .ready
            } catch {
                return .unavailable(String(
                    localized: "settings_lcr_probe_worker_unavailable \(String(describing: error))"))
            }
        }
    ) {
        self.store = store
        self.compatRecord = compatRecord
        self.labeling = labeling
        self.registry = registry
        self.activeModelKeyProvider = activeModelKeyProvider
        self.workerProbe = workerProbe
    }

    // MARK: - Load / refresh

    func refresh() async {
        labelingMode = labeling.mode
        readiness = await workerProbe()
        let activeKey = await activeModelKeyProvider()
        recomputeActive = !(registry?.isIdle ?? true)
        var built: [TierRow] = []
        for manifest in ModelAssetCatalog.allProfiles {
            let status = await store.status(for: manifest.profileID)
            let byteCount = ModelAssetDigests.digest(for: manifest.profileID)?
                .byteCount
            built.append(TierRow(
                manifest: manifest, byteCount: byteCount, status: status,
                isActiveModel: manifest.profileID == activeKey))
        }
        rows = built
    }

    // MARK: - Actions

    func download(_ profileID: String) async {
        do {
            try await store.download(profileID)
        } catch {
            statusLine = String(
                localized: "settings_lcr_download_failed \(String(describing: error))")
        }
        await refresh()
    }

    func remove(_ profileID: String) async {
        do {
            try await store.remove(profileID)
        } catch {
            statusLine = String(
                localized: "settings_lcr_remove_failed \(String(describing: error))")
        }
        await refresh()
    }

    /// The OQ-9-A 换激活 arm: enqueue the whole-library recompute under the
    /// new key (the confirm dialog lives in the view; this is the confirmed
    /// face). The old-key rows stay — 回切 = activate back.
    func enqueueRecompute(newModelKey: String) {
        guard let registry else {
            statusLine = String(
                localized: "settings_lcr_recompute_no_project",
                defaultValue: "No open project — the library recompute cannot be queued.")
            return
        }
        registry.enqueue(.recomputeAll(newModelKey: newModelKey))
        recomputeActive = true
    }

    /// The D-6 reset face (confirmed in the view).
    func resetCompatibilityRecord() {
        compatRecord.resetAll()
        statusLine = String(
            localized: "settings_lcr_compat_reset_done",
            defaultValue: "AI compatibility record cleared.")
    }

    // MARK: - Auto-labeling (the M2-10-03 assignment)

    func setLabelingMode(_ mode: LabelingMode) {
        labelingMode = mode
        labeling.store(mode)
    }

    func resetLabelingPreference() {
        labeling.reset()
        labelingMode = .ask
    }
}
