import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIRatingService (Plan M2-10-04 KD-3, M2AI-04, D-M2-10-CONTEXT-4, OQ-11-A) —
// the cull-rating orchestration over the single remote connection:
//
//   rubric assembly → remote completion (via AIProviderClient) → verdict
//   parse (clamp / sentinel) → `ai_rating` append → [CONFIRM GATE] →
//   `images.rating`
//
// WRITE ORDER (KD-3 literal): EVERY verdict lands in `ai_rating` first
// (append-only history — sentinel and real-star rows share the table); the
// REAL stars reach `images.rating` ONLY through the OQ-11-A confirm gate
// (`applyStars`, the single write face for it). There is NO rating undo
// infrastructure (rating is not part of the edit history) — the confirm gate
// IS the only protection, and the App-side AIRatingController owns the
// dialog/batch flow on top of it.
//
// SENTINEL (D-4 / the Alcedo `ai_rating.cpp:11-19` valid-judgment shape): a
// model that declines to rate (rating absent or 0) but gives reasons produces
// a rating-0 row with non-empty reasons. An out-of-range numeric rating
// (e.g. 7) CLAMPS into [1, 5].
//
// PROMPT PROFILE GUARDRAIL (M2AI-06 / D-5): every row carries
// `prompt_profile_id` = StableHash FNV-1a 64 over
// `rubric|protocol|model` (L013 DECIMAL STRING). A rubric/protocol/model
// change yields a new id — old rows stay detectable and selectively re-runnable.
// ─────────────────────────────────────────────────────────────────────────────

/// The rubric's output language (M2AI-04: 严格度 + 输出语言设置).
public enum AIRatingLanguage: String, Sendable, CaseIterable {
    case english
    case chinese
}

/// The parsed verdict. `stars` 0 = the reasons-only sentinel; 1-5 = real.
public struct AIRatingVerdict: Sendable, Equatable {
    public let stars: Int
    public let reasons: [String]

    public init(stars: Int, reasons: [String]) {
        self.stars = stars
        self.reasons = reasons
    }

    /// D-4: the reasons-only sentinel is a valid judgment when the identity
    /// rides the row and reasons are non-empty (the Alcedo IsValidReasonsOnly
    /// shape).
    public var isSentinel: Bool { stars == 0 }
}

public enum AIRatingError: Error, Equatable {
    /// The model's output had no JSON object / no parseable verdict.
    case malformedOutput(String)
    /// The confirm-gate write rejected a non-1..5 star value.
    case starsOutOfRange(Int)
}

public struct AIRatingService: Sendable {

    /// The stable task key for the rating registry family (append-only —
    /// re-runs APPEND history rows; the UNIQUE upsert discipline does not
    /// apply to ai_rating).
    public static let taskID = "rating"

    private let store: ProjectFileStore
    private let semantic: SemanticStore

    public init(store: ProjectFileStore) {
        self.store = store
        self.semantic = SemanticStore(store: store)
    }

    // MARK: - Rubric assembly (the prompt-profile identity source)

    /// The strictness-calibrated rubric (1 = 仅明显废片 … 5 = 展出标准),
    /// with the output-language directive and the JSON contract + the
    /// refusal (sentinel) instruction baked in. DETERMINISTIC TEXT: this
    /// string is the prompt-profile identity's input — editing it changes
    /// every future row's profile id (that is the guardrail working).
    public static func rubricText(
        strictness: Int, language: AIRatingLanguage
    ) -> String {
        let clamped = min(max(strictness, 1), 5)
        switch language {
        case .chinese:
            return """
            你是一名严谨的摄影评委，对一张照片进行评片。
            评分标准（1-5 星）：1 = 废片；2 = 有明显缺陷；3 = 可用；4 = 优秀；5 = 出色。
            严格度档位：\(Self.chineseStrictness(clamped))
            输出要求：只回复一个 JSON 对象，形如 {"rating": <1-5 的整数>, "reasons": ["理由一", "理由二"]}，理由用中文。
            如果这张照片差到无法给出任何星级，回复 {"rating": 0, "reasons": ["拒评理由"]}（rating 必须是 0）。
            """
        case .english:
            return """
            You are a rigorous photography judge rating one photograph.
            Rating scale (1-5 stars): 1 = reject; 2 = noticeable flaws; 3 = usable; 4 = excellent; 5 = outstanding.
            Strictness calibration: \(Self.englishStrictness(clamped))
            Output: reply with ONLY one JSON object of the form {"rating": <integer 1-5>, "reasons": ["reason one", "reason two"]}, with reasons written in English.
            If the photograph is too poor to receive any star level, reply {"rating": 0, "reasons": ["why"]} (rating must be 0).
            """
        }
    }

    private static func chineseStrictness(_ level: Int) -> String {
        switch level {
        case 1: return "1（宽松）——只把明显废片（脱焦、严重过曝/欠曝、主体缺失）打出低分，其余照片都给 3 星以上。"
        case 2: return "2（偏宽松）——明显废片打低分；有轻微技术缺陷的照片给 3 星，只有整体出色的照片才到 4-5 星。"
        case 3: return "3（平衡）——按构图、曝光、色彩、主体表现综合评定；中庸照片 3 星，亮点与硬伤都在理由中说明。"
        case 4: return "4（严格）——默认给 2-3 星；构图平庸或技术瑕疵（噪点、死黑、边缘崩坏）直接压到 2 星，4 星留给明显优秀之作。"
        default: return "5（严苛，展出标准）——只有无懈可击、达到展出/作品集水准的照片才给 5 星；一切可改进之处都是降星理由，多数照片应落在 1-2 星。"
        }
    }

    private static func englishStrictness(_ level: Int) -> String {
        switch level {
        case 1: return "1 (lenient) — only obvious rejects (out of focus, severely blown/crushed exposure, missing subject) score low; everything else gets 3+ stars."
        case 2: return "2 (lenient-leaning) — obvious rejects score low; minor technical flaws land at 3 stars; only overall-strong photographs reach 4-5."
        case 3: return "3 (balanced) — weigh composition, exposure, color, and subject together; a middling photograph is 3 stars, with highlights and flaws both named in the reasons."
        case 4: return "4 (strict) — default to 2-3 stars; mediocre composition or technical defects (noise, crushed blacks, fringing) drop to 2; reserve 4 for clearly excellent work."
        default: return "5 (exacting, exhibition standard) — only flawless, exhibition/portfolio-grade photographs earn 5; every improvable aspect is a reason to drop; most photographs should land at 1-2."
        }
    }

    /// The row identity: FNV-1a 64 over `rubric|protocol|model`, DECIMAL
    /// STRING (L013 — never a raw hash integer across a persistence
    /// boundary). Same inputs → same id (stable); ANY input change → new id.
    public static func promptProfileID(
        rubric: String, protocol: AIProviderProtocol, model: String
    ) -> String {
        let payload = "\(rubric)|\(`protocol`.rawValue)|\(model)"
        return String(StableHash.hash(payload))
    }

    // MARK: - Verdict parse (clamp + sentinel)

    /// Parse the model output into a verdict: rating present & 1-5 → as-is;
    /// > 5 clamps to 5; < 0 clamps to 1; exactly 0 or ABSENT → the sentinel
    /// (reasons REQUIRED — a refusal with no reasons is a malformed
    /// contract, surfaced typed, never silently swallowed).
    public static func parseVerdict(_ raw: String) throws -> AIRatingVerdict {
        struct Payload: Decodable {
            let rating: Int?
            let reasons: [String]?
        }
        guard let object = AIJSON.extractObject(raw) else {
            throw AIRatingError.malformedOutput("no JSON object in model output")
        }
        guard let data = object.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            throw AIRatingError.malformedOutput("verdict JSON did not decode")
        }
        let reasons = payload.reasons ?? []
        if let rating = payload.rating {
            if rating == 0 {
                // The explicit refusal — valid ONLY with reasons (D-4).
                guard !reasons.isEmpty else {
                    throw AIRatingError.malformedOutput(
                        "rating 0 (refusal) without reasons")
                }
                return AIRatingVerdict(stars: 0, reasons: reasons)
            }
            let clamped = min(max(rating, 1), 5)
            return AIRatingVerdict(stars: clamped, reasons: reasons)
        }
        // Rating absent = the model declined → sentinel (reasons required).
        guard !reasons.isEmpty else {
            throw AIRatingError.malformedOutput(
                "no rating and no reasons in model output")
        }
        return AIRatingVerdict(stars: 0, reasons: reasons)
    }

    // MARK: - The rate flow (append-first; confirm gate separate)

    /// One rating run: remote completion → verdict parse → `ai_rating`
    /// append (sentinel and real rows alike). Does NOT touch
    /// `images.rating` — that is `applyStars`, behind the confirm gate.
    @discardableResult
    public func rate(
        imageJPEG: Data, imageID: Int64,
        config: AIConnectionConfig, apiKey: Data, transport: AISession,
        strictness: Int, language: AIRatingLanguage,
        computedTime: Int64? = nil
    ) async throws -> AIRatingVerdict {
        let rubric = Self.rubricText(strictness: strictness, language: language)
        let profileID = Self.promptProfileID(
            rubric: rubric, protocol: config.protocol, model: config.model)
        let instruction = Self.userInstruction(language: language)
        let request = AICompletionRequest(
            systemText: rubric, userText: instruction, imageJPEG: imageJPEG)
        let completion = try await AIProviderClient.complete(
            request, config: config, apiKey: apiKey, transport: transport)
        let verdict = try Self.parseVerdict(completion.text)

        let reasonsJSON = try JSONEncoder().encode(verdict.reasons)
        let row = SemanticStore.RatingRow(
            imageID: imageID, taskID: Self.taskID,
            providerID: Self.providerID(for: config), modelID: config.model,
            promptProfileID: profileID, rating: verdict.stars,
            reasons: String(decoding: reasonsJSON, as: UTF8.self),
            computedTime: computedTime ?? Int64(Date().timeIntervalSince1970))
        try await semantic.appendRating(row)
        return verdict
    }

    /// The provider identity on result rows — the OQ-7-A single-connection
    /// key (the credential account's name; the model itself rides model_id).
    public static func providerID(for config: AIConnectionConfig) -> String {
        AICredentialStore.ratingProviderAccount
    }

    static func userInstruction(language: AIRatingLanguage) -> String {
        switch language {
        case .chinese: return "请评片。"
        case .english: return "Rate this photograph."
        }
    }

    // MARK: - The confirm gate (the ONLY images.rating write face)

    /// Write real stars to `images.rating` — the OQ-11-A gate's action leg.
    /// The caller (AIRatingController) guarantees this runs ONLY after the
    /// user's explicit 应用 (or the don't-ask preference). Sentinel values
    /// (0) are rejected — a sentinel never touches the user-facing column.
    public func applyStars(_ stars: Int, to imageID: Int64) async throws {
        guard (1...5).contains(stars) else {
            throw AIRatingError.starsOutOfRange(stars)
        }
        try await store.withWriteBatch { handle -> Bool in
            let update = try handle.prepare(
                "UPDATE images SET rating = ? WHERE id = ?")
            try update.bindInt(1, Int64(stars))
            try update.bindInt(2, imageID)
            _ = try update.step()
            return true
        }
    }
}
