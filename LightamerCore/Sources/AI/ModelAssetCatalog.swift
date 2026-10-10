import Foundation

/// Distribution tier for a model asset profile (KD-1 / D-M2-10-CONTEXT-7).
///
/// - `bundled`: ships inside the app bundle as a folder reference
///   (`<repo-root>/Resources/AIModels/<profile_id>/…`); never downloaded.
/// - `gitHubRelease`: downloaded at runtime from this repository's GitHub
///   Release (version-locked URL), with hf-mirror / Hugging Face fallback.
public enum ModelDistributionTier: Sendable, Equatable {
    case bundled
    case gitHubRelease
}

/// The model family discriminant (M4-3-01 KD-1). Derived — never stored:
/// `ModelAssetManifest.family` computes it from the existing fields, so
/// adding a profile cannot desynchronize a second stored marker. The
/// worker's open/run dispatch and the tests consume THIS one discriminant.
public enum ModelAssetFamily: Sendable, Equatable {
    /// CLIP embedding profiles (`embeddingDim != nil`).
    case clip
    /// Monocular-depth profiles (`inputShortEdge != nil` — a non-square
    /// static input edge pair is the depth face's marker).
    case depth
    /// Super-resolution / denoise tile profiles (the fall-through).
    case enhancement
}

/// Compiled-in manifest for one model asset profile.
///
/// This is the single constant source for downstream consumers (M2-10-02
/// embedding / M2-10-03 labeling / M2-10-06 enhancement): input tile sizes and
/// embedding dims are read from here, never re-typed at call sites.
public struct ModelAssetManifest: Sendable, Equatable {
    /// Stable key, e.g. `"chinese-clip-vitb16-int8"`. Also the on-disk
    /// directory name under the models root and the bundle subdirectory.
    public let profileID: String
    /// Upstream model repository id (HF repo id for CLIP profiles; the
    /// upstream git repository for the Real-ESRGAN family).
    public let modelID: String
    /// Upstream revision pin (HF commit SHA / git tag). Locks both the
    /// fallback download URL and the conversion provenance.
    public let revision: String
    /// Embedding dimension for CLIP-family profiles (512/768); `nil` for the
    /// enhancement family.
    public let embeddingDim: Int?
    /// Canonical square input edge in pixels.
    ///
    /// CLIP profiles: the vision-tower input edge (Chinese-CLIP ViT-B/16 =
    /// 224, empirically pinned from the HF `config.json`
    /// `vision_config.image_size` / `preprocessor_config.json` at revision
    /// `36e679e` — checker E4: never hard-code a different value).
    /// Enhancement profiles: the static tile base edge baked into the
    /// converted model (M2-10-06 tiles from this constant).
    ///
    /// Single constant source: pre-scaling legs in 02/03 read this value.
    public let inputSize: Int
    /// Canonical SHORT input edge for non-square models (M4-3-01 OQ-7:
    /// additive optional). `nil` = the square-input semantics (the five
    /// pre-depth profiles drift nowhere). The depth leg consumes the
    /// (inputSize, inputShortEdge) pair as its (long, short) static shape —
    /// the D-4 spike's single source (no call site re-types the numbers).
    public let inputShortEdge: Int?
    /// Text-tower languages, e.g. `["zh", "en"]` / `["multilingual"]`.
    public let textLanguages: [String]
    /// SPDX license name of the shipped weights.
    public let licenseName: String
    public let tier: ModelDistributionTier
    /// GitHub Release tag this profile downloads from (version-locked);
    /// `nil` for bundled profiles.
    public let releaseTag: String?
    /// Release asset file name (the distribution unit the store downloads
    /// and digests), e.g. `"jina-clip-v2-int8.mlpackage.zip"`. For bundled
    /// profiles this names the PRIMARY in-bundle model package.
    public let assetFileName: String
    /// Hugging Face fallback (hf-mirror first, then huggingface.co), pinned
    /// to the same `revision`. Inert for bundled profiles (kept for
    /// provenance/re-derivation by the conversion scripts).
    public let hfFallback: (repo: String, file: String)

    /// Explicit init: `inputShortEdge` defaults to nil so the five
    /// pre-depth profile constructions (and any test fixture) compile
    /// byte-for-byte unchanged — the additive-optional discipline
    /// (InstalledLut.relativePath precedent).
    public init(
        profileID: String,
        modelID: String,
        revision: String,
        embeddingDim: Int?,
        inputSize: Int,
        inputShortEdge: Int? = nil,
        textLanguages: [String],
        licenseName: String,
        tier: ModelDistributionTier,
        releaseTag: String?,
        assetFileName: String,
        hfFallback: (repo: String, file: String)
    ) {
        self.profileID = profileID
        self.modelID = modelID
        self.revision = revision
        self.embeddingDim = embeddingDim
        self.inputSize = inputSize
        self.inputShortEdge = inputShortEdge
        self.textLanguages = textLanguages
        self.licenseName = licenseName
        self.tier = tier
        self.releaseTag = releaseTag
        self.assetFileName = assetFileName
        self.hfFallback = hfFallback
    }

    /// The single-source family discriminant (KD-1). PRIORITY ORDER IS
    /// LOAD-BEARING (checker o2): `clip` is judged before `depth`, so a
    /// hypothetical future double-marked profile would silently land on
    /// clip — this doc comment pins the precedence; the six-profile
    /// exhaustiveness test is the behavioral lock.
    public var family: ModelAssetFamily {
        if embeddingDim != nil { return .clip }
        if inputShortEdge != nil { return .depth }
        return .enhancement
    }

    public static func == (lhs: ModelAssetManifest, rhs: ModelAssetManifest) -> Bool {
        lhs.profileID == rhs.profileID
            && lhs.modelID == rhs.modelID
            && lhs.revision == rhs.revision
            && lhs.embeddingDim == rhs.embeddingDim
            && lhs.inputSize == rhs.inputSize
            && lhs.inputShortEdge == rhs.inputShortEdge
            && lhs.textLanguages == rhs.textLanguages
            && lhs.licenseName == rhs.licenseName
            && lhs.tier == rhs.tier
            && lhs.releaseTag == rhs.releaseTag
            && lhs.assetFileName == rhs.assetFileName
            && lhs.hfFallback.repo == rhs.hfFallback.repo
            && lhs.hfFallback.file == rhs.hfFallback.file
    }
}

/// The five-profile compiled-in catalog (plan M2-10-01 KD-1).
///
/// Ruling provenance (not re-openable here):
/// - OQ-1-B: bundled default CLIP = Chinese-CLIP ViT-B/16 int8 (~190 MB,
///   Apache-2.0, zh+en text tower) — user ruling "偏质量".
/// - OQ-2-A: release semantic large profile = Jina-CLIP-v2 int8 only.
/// - OQ-3-B: enhancement split = realesr-general-x4v3 fp16 bundled (fast
///   tier) + Real-ESRGAN x4plus / DRUNet color fp16 release (quality tier).
public enum ModelAssetCatalog {
    // MARK: Bundled profiles

    /// Chinese-CLIP ViT-B/16, int8 weights + fp16 activations, L2-normalize
    /// folded into the graph. Vision tower + text tower ship as two
    /// .mlpackage siblings plus the WordPiece `vocab.txt`, all inside the
    /// bundle folder reference.
    ///
    /// E4 empirical pin (2026-10-03, via hf-mirror at revision `36e679e`):
    /// `config.json` → `vision_config.image_size = 224`, `patch_size = 16`;
    /// `preprocessor_config.json` → `size = {224, 224}`. 224 it is.
    public static let chineseClipViTB16Int8 = ModelAssetManifest(
        profileID: "chinese-clip-vitb16-int8",
        modelID: "OFA-Sys/chinese-clip-vit-base-patch16",
        revision: "36e679e65c2a2fead755ae21162091293ad37834",
        embeddingDim: 512,
        inputSize: 224,
        textLanguages: ["zh", "en"],
        licenseName: "Apache-2.0",
        tier: .bundled,
        releaseTag: nil,
        assetFileName: "chinese-clip-vitb16-img.mlpackage",
        hfFallback: (
            repo: "OFA-Sys/chinese-clip-vit-base-patch16",
            file: "pytorch_model.bin"
        )
    )

    /// realesr-general-x4v3 (SRVGGNet compact) fp16 — bundled fast-tier
    /// enhancement model. Static 256 tile base (M2-10-06 consumes this).
    public static let realesrGeneralX4V3FP16 = ModelAssetManifest(
        profileID: "realesr-general-x4v3-fp16",
        modelID: "xinntao/Real-ESRGAN",
        revision: "v0.2.5.0",
        embeddingDim: nil,
        inputSize: 256,
        textLanguages: [],
        licenseName: "BSD-3-Clause",
        tier: .bundled,
        releaseTag: nil,
        assetFileName: "realesr-general-x4v3-fp16.mlpackage",
        hfFallback: (
            repo: "qualcomm/Real-ESRGAN-General-x4v3",
            file: "realesr-general-x4v3-sr.pth"
        )
    )

    // MARK: GitHub Release profiles

    /// Jina-CLIP-v2 int8 (834 MB HF-verified byte count) — release semantic
    /// large profile, 768-d Matryoshka (whole-vector storage here; any
    /// truncation policy belongs to M2-10-02).
    public static let jinaClipV2Int8 = ModelAssetManifest(
        profileID: "jina-clip-v2-int8",
        modelID: "jinaai/jina-clip-v2",
        revision: "e10d47f5691d0454a0fb5d13f46f2199b74cb436",
        embeddingDim: 768,
        inputSize: 512,
        textLanguages: ["multilingual"],
        licenseName: "Apache-2.0",
        tier: .gitHubRelease,
        releaseTag: "ai-models-v1",
        assetFileName: "jina-clip-v2-int8.mlpackage.zip",
        hfFallback: (
            repo: "jinaai/jina-clip-v2",
            file: "onnx/model_int8.onnx"
        )
    )

    /// Real-ESRGAN x4plus fp16 — release quality-tier enhancement model.
    /// Weights: BSD-3-Clause, upstream release tag v0.1.0
    /// (67,040,989-byte .pth, release-verified 2026-10-03).
    public static let realESRGANX4PlusFP16 = ModelAssetManifest(
        profileID: "real-esrgan-x4plus-fp16",
        modelID: "xinntao/Real-ESRGAN",
        revision: "v0.1.0",
        embeddingDim: nil,
        inputSize: 256,
        textLanguages: [],
        licenseName: "BSD-3-Clause",
        tier: .gitHubRelease,
        releaseTag: "ai-models-v1",
        assetFileName: "real-esrgan-x4plus-fp16.mlpackage.zip",
        hfFallback: (
            repo: "schwgHao/RealESRGAN_x4plus",
            file: "RealESRGAN_x4plus.pth"
        )
    )

    /// DRUNet (color) fp16 — release quality-tier denoise model (KAIR, MIT).
    public static let drunetColorFP16 = ModelAssetManifest(
        profileID: "drunet-color-fp16",
        modelID: "cszn/KAIR",
        revision: "v1.1",
        embeddingDim: nil,
        inputSize: 256,
        textLanguages: [],
        licenseName: "MIT",
        tier: .gitHubRelease,
        releaseTag: "ai-models-v1",
        assetFileName: "drunet-color-fp16.mlpackage.zip",
        hfFallback: (
            repo: "cszn/KAIR",
            file: "drunet_color.pth"
        )
    )

    // MARK: Depth profiles

    /// Depth Anything V2 Small — Apple's official Core ML F16 conversion
    /// (49.8 MB, Apache-2.0; ruling OQ-1-A: zero conversion, the official
    /// package IS the release unit).
    ///
    /// Static IMAGE input, 518 (W) × 392 (H) — the D-4 SPIKE pin
    /// (2026-10-10, MLModelDescription probed first-hand on the pinned
    /// revision): the plan's "396" was a research transcription; the real
    /// constraint is 392. `inputSize` carries the long edge (518), the
    /// additive `inputShortEdge` the short (392); the image-typed input
    /// means preprocessing is BAKED (no ImageNet normalization at call
    /// sites — KD-3 arm a). The output is a one-component 32-bit-half
    /// image, larger = nearer, roughly [0,1].
    public static let depthAnythingV2SmallF16 = ModelAssetManifest(
        profileID: "depth-anything-v2-small-f16",
        modelID: "apple/coreml-depth-anything-v2-small",
        revision: "cfef6f6f2a70783dedc0bfae40cecbc2052285d3",
        embeddingDim: nil,
        inputSize: 518,
        inputShortEdge: 392,
        textLanguages: [],
        licenseName: "Apache-2.0",
        tier: .gitHubRelease,
        releaseTag: "ai-models-v1",
        assetFileName: "depth-anything-v2-small-f16.mlpackage.zip",
        hfFallback: (
            repo: "apple/coreml-depth-anything-v2-small",
            file: "DepthAnythingV2SmallF16.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        )
    )

    // MARK: Queries

    /// All six profiles, bundled first.
    public static let allProfiles: [ModelAssetManifest] = [
        chineseClipViTB16Int8,
        realesrGeneralX4V3FP16,
        jinaClipV2Int8,
        realESRGANX4PlusFP16,
        drunetColorFP16,
        depthAnythingV2SmallF16,
    ]

    /// Profiles expected inside the app bundle (exactly two, OQ-1-B/OQ-3-B).
    public static let bundledProfiles: [ModelAssetManifest] = allProfiles.filter {
        $0.tier == .bundled
    }

    /// Profiles distributed through the version-locked GitHub Release.
    public static let releaseProfiles: [ModelAssetManifest] = allProfiles.filter {
        $0.tier == .gitHubRelease
    }

    public static func manifest(for profileID: String) -> ModelAssetManifest? {
        allProfiles.first { $0.profileID == profileID }
    }
}
