import Foundation
import Vision

// ─────────────────────────────────────────────────────────────────────────────
// AIAssetStatus (Plan 07-1 T3) — the layer-B model asset state machine
// (D-07-CONTEXT-1): assetStatus 三态 (notReady / downloading / ready +
// failed), `downloadAssets` wrapped with a Foundation `Progress` (the
// Subprogress consumer seam), and the first-launch pre-download policy
// entry (prompt-first: the user consents → background download; declined
// → the layer-B entry stays disabled-but-guided; layer A is NEVER
// affected).
//
// The App layer (AIDownloadPrompt) observes `phase`; 07-3's MaskToolbar
// consumes the SAME model for its three-state gating. Failure is NEVER
// silent: `.failed(reason)` surfaces through the prompt (retry allowed —
// the state machine returns to a downloadable state on retry).
//
// Testability: the probes are injectable closures — the state-machine
// tests script them without touching the real model (whose on-disk state
// depends on machine history).
// ─────────────────────────────────────────────────────────────────────────────

/// The observable phase of the layer-B model assets.
public enum AIAssetPhase: Sendable, Equatable {
    /// Never queried yet.
    case unknown
    /// `assetStatus == .notReady` — downloadable, layer B disabled.
    case notReady
    /// A download is in flight (the fraction mirrors the Foundation
    /// Progress when the OS reports one; -1 = indeterminate).
    case downloading(progress: Double)
    /// Assets present — layer B enabled.
    case ready
    /// The download (or status probe) failed — surfaced, retryable.
    case failed(String)

    /// The UI gate: only `.ready` enables the layer-B entry (the
    /// double-backend fallback boundary — D-07-CONTEXT-1: the FALLBACK IS
    /// AN ENTRY-LEVEL GATE, never a silent internal switch).
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// How a first-launch pre-download offer was answered (the prompt is
/// once-only; UserDefaults-backed — App state, but the policy lives here
/// so tests pin it).
public enum AIPromptChoice: String, Sendable {
    case unanswered
    case accepted
    case declined

    public static let defaultsKey = "ai.layerB.downloadPromptChoice"
}

public actor AIAssetStore {

    public static let shared = AIAssetStore()

    // Injectable seams (tests script these; production hits Vision).
    private let statusProbe: @Sendable () async -> DownloadableAssetsRequestStatus
    private let downloader: @Sendable (Progress?) async throws -> Void

    private(set) public var phase: AIAssetPhase = .unknown
    private var inFlightDownload = false

    public init(
        statusProbe: (@Sendable () async -> DownloadableAssetsRequestStatus)? = nil,
        downloader: (@Sendable (Progress?) async throws -> Void)? = nil
    ) {
        if let statusProbe {
            self.statusProbe = statusProbe
        } else {
            self.statusProbe = {
                let request = GenerateIterativeSegmentationRequest(
                    seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
                return await request.assetStatus
            }
        }
        if let downloader {
            self.downloader = downloader
        } else {
            self.downloader = { progress in
                let request = GenerateIterativeSegmentationRequest(
                    seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
                if let progress {
                    // The Subprogress consumer seam: a child of the caller's
                    // Progress feeds Vision's downloadAssets(progress:).
                    let sub = progress.subprogress(assigningCount: 100)
                    try await request.downloadAssets(progress: sub)
                } else {
                    try await request.downloadAssets()
                }
            }
        }
    }

    /// The current phase; `queried: true` refreshes from the probe when
    /// still `.unknown` (AIMaskService's inline gate uses this).
    public func currentPhase(queried: Bool = false) async -> AIAssetPhase {
        if queried, case .unknown = phase {
            await refreshStatus()
        }
        return phase
    }

    /// Query the OS asset status and fold it into the phase (a live
    /// download is never overwritten by a probe).
    public func refreshStatus() async {
        if inFlightDownload { return } // the in-flight download owns the phase
        let status = await statusProbe()
        switch status {
        case .notReady: phase = .notReady
        case .downloading: phase = .downloading(progress: -1)
        case .ready: phase = .ready
        case .error(let error):
            // A probe error on a ready machine must not demote the phase.
            if !phase.isReady { phase = .failed(String(describing: error)) }
        @unknown default:
            phase = .failed("unknown asset status: \(status)")
        }
    }

    /// Download the model assets (the consent-gated action). The phase
    /// walks `.notReady → .downloading → .ready` / `.failed(reason)`;
    /// retry after failure is always allowed (no terminal states).
    ///
    /// PROGRESS (D-07-1-T3-2): the fraction stays -1 (indeterminate) in
    /// v1 — the OS download is 3-11 ms in practice (benchmark), below any
    /// meaningful progress granularity; the UI shows a spinner. The
    /// `Progress` parameter wires the Subprogress consumer seam for a
    /// future larger model.
    public func download(progress: Progress? = nil) async {
        guard !inFlightDownload else { return }
        guard !phase.isReady else { return } // idempotent no-op when ready
        inFlightDownload = true
        phase = .downloading(progress: -1)
        do {
            try await downloader(progress)
            // The OS status is the source of truth — a "successful" call
            // that left assets not-ready reports the real state.
            let status = await statusProbe()
            switch status {
            case .ready: phase = .ready
            case .notReady: phase = .notReady
            case .downloading: phase = .downloading(progress: -1)
            case .error(let error): phase = .failed(String(describing: error))
            @unknown default: phase = .failed("unknown asset status: \(status)")
            }
        } catch {
            phase = .failed(String(describing: error))
        }
        inFlightDownload = false
    }

    /// Tests only: reset the machine to `.unknown`.
    public func resetForTesting() {
        phase = .unknown
        inFlightDownload = false
    }

    // MARK: - First-launch policy (D-07-CONTEXT-1)

    /// The first-launch pre-download policy: TRUE once, when the user
    /// never answered AND the assets are not ready. After consent the
    /// choice persists (UserDefaults) — the prompt never nags again.
    public static func shouldOfferFirstLaunchDownload(
        choice: AIPromptChoice, phase: AIAssetPhase,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let persisted = AIPromptChoice(
            rawValue: defaults.string(forKey: AIPromptChoice.defaultsKey) ?? "")
            ?? .unanswered
        let effective = persisted == .unanswered ? choice : persisted
        switch effective {
        case .unanswered:
            return !phase.isReady && !phase.isDownloading
        case .accepted, .declined:
            return false
        }
    }

    /// Record the user's answer (persisted).
    public static func recordPromptChoice(
        _ choice: AIPromptChoice, defaults: UserDefaults = .standard
    ) {
        defaults.set(choice.rawValue, forKey: AIPromptChoice.defaultsKey)
    }
}

extension AIAssetPhase {
    /// True while a download is in flight.
    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}
