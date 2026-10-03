import CoreML
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AIInferenceService (Plan M2-10-02 KD-5 / T4 action 2) — the App-layer
// ASSEMBLY SINGLE POINT for local inference: the bundled Chinese-CLIP assets
// (folder reference via ModelLocator) → InProcessMLModelRunner →
// SemanticEngine, memoized.
//
// M2-10-05 SWITCH LINE: the worker-process conformer lands there and
// REPLACES the `InProcessMLModelRunner(...)` construction below — the
// engine/store/search faces are untouched (the KD-5 assembly-point
// rationale). The comment pins the seam.
//
// FAIL-CLOSED (KD-5): any absent/broken asset (no bundle models, vocab
// unreadable, tokenizer construction failure, MLModel load failure) → nil,
// memoized — the honest「语义模型未就绪」face. NEVER a fake empty result
// (D8's 禁假开关, the search-dialog discipline).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class AIInferenceService {

    /// The assembly single point (L036 spirit: one production read of the
    /// bundle topology, injected downward from here).
    static let shared = AIInferenceService()

    private var cachedSearcher: (any SemanticSearching)?
    private var loadFailed = false
    private let locator = ModelLocator()

    private init() {}

    /// The semantic searcher, or nil when the bundled CLIP assets are
    /// absent/broken (memoized both ways — first answer wins).
    func semanticSearcher() async -> (any SemanticSearching)? {
        if let cachedSearcher { return cachedSearcher }
        if loadFailed { return nil }
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        guard
            let vocabURL = locator.bundledAssetURL(
                "vocab.txt", profileID: clip.profileID),
            let vocab = try? String(contentsOf: vocabURL, encoding: .utf8),
            let tokenizer = try? WordPieceTokenizer(vocabText: vocab),
            let imageURL = locator.bundledAssetURL(
                clip.assetFileName, profileID: clip.profileID),
            // The twin-tower naming is the bundle format's convention
            // (M2-10-01 built img/txt siblings; the catalog carries the
            // PRIMARY asset name only — the text twin derives from it).
            let textURL = locator.bundledAssetURL(
                clip.assetFileName.replacingOccurrences(of: "-img.", with: "-txt."),
                profileID: clip.profileID)
        else {
            loadFailed = true
            return nil
        }
        // ── M2-10-05: the worker-process runner replaces THIS line ──
        guard let runner = try? InProcessMLModelRunner(
            imageModelURL: imageURL, textModelURL: textURL,
            compileCacheDirectory: Self.compiledModelCache)
        else {
            loadFailed = true
            return nil
        }
        let engine = SemanticEngine(runner: runner, tokenizer: tokenizer)
        cachedSearcher = engine
        return engine
    }

    /// The compiled-model cache (a rebuildable Caches-class derivative —
    /// the bundled .mlpackage trees compile once, then load directly).
    private static var compiledModelCache: URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return caches
            .appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent("compiled-models", isDirectory: true)
    }
}
