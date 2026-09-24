import LightamerCore
import Observation
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// AIDownloadPrompt (Plan 07-1 T3) — the layer-B model first-launch prompt
// + progress + failure surface (D-07-CONTEXT-1, prompt-first policy).
//
// WIRING POINT (execution-period decision, recorded 07-1-DECISIONS
// D-07-1-T3-2): ContentView hosts the modifier — the prompt is app-global
// state, not per-editor; 07-3's MaskToolbar reuses the SAME AIAssetStore
// model for its three-state entry gate (never a second state machine).
//
// NON-SILENT failure red line: download failures stay visible (retry
// button) until dismissed; layer A is NEVER gated by this prompt.
// ─────────────────────────────────────────────────────────────────────────────

/// The App-side observable wrapper over `AIAssetStore` (the UI's single
/// state source for the layer-B asset phase).
@MainActor
@Observable
final class AIDownloadModel {

    /// The store under management (injectable for previews/tests).
    let store: AIAssetStore

    /// Mirrored phase (polled while visible).
    private(set) var phase: AIAssetPhase = .unknown

    /// Whether the one-time prompt should show (first launch, unanswered,
    /// assets not ready).
    private(set) var showPrompt = false

    /// The failure surface (non-silent): stays until the user retries or
    /// dismisses.
    private(set) var downloadError: String?

    private var pollTask: Task<Void, Never>?

    init(store: AIAssetStore = .shared) {
        self.store = store
    }

    /// Arm on app start: refresh the phase, evaluate the once-only offer.
    func bootstrap() async {
        await store.refreshStatus()
        phase = await store.currentPhase()
        showPrompt = AIAssetStore.shouldOfferFirstLaunchDownload(
            choice: .unanswered, phase: phase)
    }

    /// User accepted the first-launch offer → background download.
    func accept() {
        showPrompt = false
        AIAssetStore.recordPromptChoice(.accepted)
        startDownload()
    }

    /// User declined → the layer-B entry stays disabled-guided; the
    /// choice persists (the prompt never nags; 07-3 offers a manual
    /// download entry in the disabled state).
    func decline() {
        showPrompt = false
        AIAssetStore.recordPromptChoice(.declined)
    }

    /// Retry after a failure (always allowed — no terminal states).
    func retry() {
        downloadError = nil
        startDownload()
    }

    func dismissError() {
        downloadError = nil
    }

    private func startDownload() {
        pollTask?.cancel()
        // Indeterminate v1 (D-07-1-T3-2: the OS download is 3-11 ms —
        // below progress granularity; a Progress is non-Sendable and
        // cannot cross the actor hop, so the Subprogress seam stays on
        // the store for a future larger model).
        pollTask = Task { [weak self] in
            guard let self else { return }
            let store = self.store
            await store.download()
            var phase = await store.currentPhase()
            // Poll the downloading window (bounded: 30s).
            for _ in 0..<150 where phase.isDownloading {
                try? await Task.sleep(for: .milliseconds(200))
                phase = await store.currentPhase()
            }
            self.phase = phase
            if case .failed(let reason) = phase {
                self.downloadError = reason
                return
            }
            // GUI-20 (07-3 acceptance, 2026-09-24): a download that returned
            // WITHOUT an error but left the assets not-ready used to fall
            // back to the silent needsDownload guidance state — the user
            // pressed「下载模型」, nothing happened, nothing was said. The
            // no-error-not-provisioned signature is exactly the 07-1
            // test-entitlement / beta-provisioning family (the store probe
            // matrix that round could not distinguish); surface it through
            // the SAME non-silent alert with its own explanatory message.
            if case .notReady = phase {
                self.downloadError = String(
                    localized: "ai_download_not_ready_body")
            }
        }
    }
}

/// The prompt + progress + failure surfaces (attach to the app root).
/// Plan 07-3: the model rides the ENVIRONMENT (the app root owns it) —
/// MaskToolbar's layer-B entry gate observes the SAME instance (one state
/// machine, never two; 07-1 D-07-1-T3-2 wiring point kept).
internal struct AIDownloadPrompt: ViewModifier {
    @Environment(AIDownloadModel.self) private var model

    func body(content: Content) -> some View {
        content
            .task { await model.bootstrap() }
            .alert(
                String(localized: "ai_download_prompt_title"),
                isPresented: Binding(
                    get: { model.showPrompt },
                    set: { _ in model.decline() } // dismiss == decline (recorded)
                )
            ) {
                Button(String(localized: "ai_download_accept")) {
                    model.accept()
                }
                .accessibilityIdentifier("ai.download.accept")
                Button(String(localized: "ai_download_decline"), role: .cancel) {
                    model.decline()
                }
                .accessibilityIdentifier("ai.download.decline")
            } message: {
                Text(String(localized: "ai_download_prompt_message"))
            }
            .alert(
                String(localized: "ai_download_failed_title"),
                isPresented: Binding(
                    get: { model.downloadError != nil },
                    set: { if !$0 { model.dismissError() } }
                ),
                presenting: model.downloadError
            ) { _ in
                Button(String(localized: "ai_download_retry")) {
                    model.retry()
                }
                .accessibilityIdentifier("ai.download.retry")
                Button(String(localized: "alert_ok"), role: .cancel) {
                    model.dismissError()
                }
            } message: { reason in
                // Non-silent red line: the failure carries its reason.
                Text(String(localized: "ai_download_failed_message")) + Text("\n\(reason)")
            }
            // Download progress: a transient status line while assets are
            // in flight (non-blocking — layer A editing continues).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.phase.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "ai_download_progress"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("ai.download.progress")
                }
            }
    }
}
