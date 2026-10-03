import CoreML
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AIInferenceService (Plan M2-10-02 KD-5 / T4 action 2) — the App-layer
// ASSEMBLY SINGLE POINT for local inference: the bundled Chinese-CLIP assets
// (folder reference via ModelLocator, the readiness probe) → the worker-
// process runner (AIWorkerClient, M2-10-05) → SemanticEngine, memoized.
//
// M2-10-05 SWITCH LINE: the pinned runner construction below swapped the
// InProcess conformer for the `--ai-worker` child process (OQ-5-A) — the
// engine/store/search faces are untouched (the KD-5 assembly-point
// rationale). InProcessMLModelRunner survives as the test fixture and as
// the worker's session object.
//
// FAIL-CLOSED (KD-5): any absent/broken asset (no bundle models, vocab
// unreadable, tokenizer construction failure) → nil, memoized — the
// honest「语义模型未就绪」face. NEVER a fake empty result (D8's 禁假开关,
// the search-dialog discipline). Runtime worker failures surface through
// the client's typed errors (unavailable/crashed/exhausted) — the same
// honest-face rule one layer out.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class AIInferenceService {

    /// The assembly single point (L036 spirit: one production read of the
    /// bundle topology, injected downward from here).
    static let shared = AIInferenceService()

    private var cachedEngine: SemanticEngine?
    private var loadFailed = false
    private let locator = ModelLocator()

    private init() {}

    /// The semantic searcher, or nil when the bundled CLIP assets are
    /// absent/broken (memoized both ways — first answer wins).
    func semanticSearcher() async -> (any SemanticSearching)? {
        await engine()
    }

    /// M2-10-03: the SAME memoized engine typed for the analysis registry
    /// (the AIAnalysisEngining seam — one assembly, two typed views; nil
    /// under the same fail-closed discipline).
    func analysisEngine() async -> (any AIAnalysisEngining)? {
        await engine()
    }

    /// The memoized assembly body (KD-5 single point).
    private func engine() async -> SemanticEngine? {
        if let cachedEngine { return cachedEngine }
        if loadFailed { return nil }
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        guard
            let vocabURL = locator.bundledAssetURL(
                "vocab.txt", profileID: clip.profileID),
            let vocab = try? String(contentsOf: vocabURL, encoding: .utf8),
            let tokenizer = try? WordPieceTokenizer(vocabText: vocab),
            // The bundled twin assets stay the MODEL-READINESS probe (the
            // nil「语义模型未就绪」face for absent models is unchanged) —
            // the worker process resolves and loads them on its own side
            // of the IPC, the editor side only needs the tokenizer.
            locator.bundledAssetURL(
                clip.assetFileName, profileID: clip.profileID) != nil,
            locator.bundledAssetURL(
                clip.assetFileName.replacingOccurrences(of: "-img.", with: "-txt."),
                profileID: clip.profileID) != nil
        else {
            loadFailed = true
            return nil
        }
        // ── M2-10-05: THE SWITCH LINE — the WORKER-PROCESS runner now sits
        // here (OQ-5-A); the `InProcessMLModelRunner(...)` construction this
        // replaces survives as the test fixture and as the worker's own
        // session object. Failures degrade through the worker client's
        // chain: an unreachable worker surfaces typed `.workerUnavailable`
        // (the honest feature-degraded face) — NEVER an in-process
        // fallback, which would put the crash risk back into the editor.
        let runner = AIWorkerClient(
            record: CompatRecord(path: CompatRecord.defaultPath()))
        let engine = SemanticEngine(runner: runner, tokenizer: tokenizer)
        cachedEngine = engine
        return engine
    }
}
