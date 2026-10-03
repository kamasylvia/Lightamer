import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIDescriptionService (Plan M2-10-04 KD-4, M2AI-05) — the description flow
// (caption + tags + scene + confidence) and the FULLTEXT read face over
// `ai_understanding` / `ai_understanding_fts`.
//
// WRITE SIDE: the contract parse reconciles into `ai_understanding` via
// SemanticStore.replaceUnderstanding (the explicit DELETE + INSERT — L059's
// INSERT-OR-REPLACE FTS trap is owned there). `rendition_kind` records WHICH
// rendition was described: "edited" (default — the current edit-state render,
// the MCP render_preview semantic boundary) or "original" (explicit).
//
// READ SIDE (the M2-10-04-owned E5 join): `ai_understanding_fts` indexes
// EVERY row with NO active concept — re-runs leave active=0 history rows in
// the index. The MATCH consumer MUST `JOIN ai_understanding … active = 1`
// or stale captions keep matching after the user re-describes an image.
// This file owns that join (02's store deliberately never fabricates one).
// The user text is sanitized into per-token quoted phrases (FTS5 syntax
// characters in user input must query, never explode).
// ─────────────────────────────────────────────────────────────────────────────

/// The parsed description contract.
public struct AIDescription: Sendable, Equatable {
    public let caption: String
    public let tags: [String]
    public let scene: String?
    public let confidence: Double?

    public init(
        caption: String, tags: [String], scene: String?, confidence: Double?
    ) {
        self.caption = caption
        self.tags = tags
        self.scene = scene
        self.confidence = confidence
    }
}

public struct AIDescriptionService: Sendable {

    /// The stable task key (the reconcile UNIQUE(image_id, task_id) half —
    /// a re-run REPLACES this task's row; sibling tasks demote).
    public static let taskID = "description"

    /// The cataloger role prompt (also the description prompt-profile's
    /// identity input — same guardrail as the rating rubric).
    static let rolePrompt = """
        You are a precise photo library cataloger. You describe photographs
        factually: one concise caption, domain tags, the scene type, and your
        confidence.
        """

    private let store: ProjectFileStore
    private let semantic: SemanticStore

    public init(store: ProjectFileStore) {
        self.store = store
        self.semantic = SemanticStore(store: store)
    }

    // MARK: - Contract parse

    /// Parse the model output. `caption` is REQUIRED (a description without
    /// one is a malformed contract); tags default empty; confidence clamps
    /// to 0...1.
    public static func parse(_ raw: String) throws -> AIDescription {
        struct Payload: Decodable {
            let caption: String?
            let tags: [String]?
            let scene: String?
            let confidence: Double?
        }
        guard let object = AIJSON.extractObject(raw) else {
            throw AIRatingError.malformedOutput(
                "no JSON object in model output")
        }
        guard let data = object.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let caption = payload.caption, !caption.isEmpty
        else {
            throw AIRatingError.malformedOutput(
                "description JSON has no caption")
        }
        return AIDescription(
            caption: caption,
            tags: payload.tags ?? [],
            scene: payload.scene,
            confidence: payload.confidence.map { min(max($0, 0), 1) })
    }

    /// The description prompt-profile id: hash over `role|protocol|model`
    /// (the description face of the M2AI-06 guardrail).
    public static func promptProfileID(
        protocol: AIProviderProtocol, model: String
    ) -> String {
        let payload = "\(rolePrompt)|\(`protocol`.rawValue)|\(model)"
        return String(StableHash.hash(payload))
    }

    // MARK: - The describe flow

    /// One description run: remote completion → contract parse →
    /// `ai_understanding` reconcile (FTS triggers mirror the row).
    @discardableResult
    public func describe(
        imageJPEG: Data, imageID: Int64,
        config: AIConnectionConfig, apiKey: Data, transport: AISession,
        renditionKind: String = "edited", computedTime: Int64? = nil
    ) async throws -> AIDescription {
        let profileID = Self.promptProfileID(
            protocol: config.protocol, model: config.model)
        let request = AICompletionRequest(
            systemText: Self.rolePrompt,
            userText: Self.userInstruction,
            imageJPEG: imageJPEG)
        let completion = try await AIProviderClient.complete(
            request, config: config, apiKey: apiKey, transport: transport)
        let description = try Self.parse(completion.text)

        let tagsJSON = try JSONEncoder().encode(description.tags)
        let row = SemanticStore.UnderstandingRow(
            imageID: imageID, taskID: Self.taskID,
            providerID: AICredentialStore.ratingProviderAccount,
            modelID: config.model, promptProfileID: profileID,
            renditionKind: renditionKind, caption: description.caption,
            tags: String(decoding: tagsJSON, as: UTF8.self),
            scene: description.scene, confidence: description.confidence,
            computedTime: computedTime ?? Int64(Date().timeIntervalSince1970))
        try await semantic.replaceUnderstanding(row)
        return description
    }

    static let userInstruction = """
        Describe this photograph for a photo library. Reply with ONLY one
        JSON object: {"caption": "...", "tags": ["...", "..."], "scene": "...",
        "confidence": 0.0-1.0}.
        """

    // MARK: - The fulltext read face (the E5 join lives HERE)

    /// MATCH → JOIN `ai_understanding` (active = 1) → ordered image ids.
    /// Multi-row images collapse to one id (DISTINCT, defensively — the
    /// reconcile keeps exactly one active row per image); ordering = FTS
    /// rank (bm25), the honest relevance order.
    public static func imageIDs(
        matching rawQuery: String, store: ProjectFileStore, limit: Int = 500
    ) async throws -> [Int64] {
        let match = ftsMatchQuery(rawQuery)
        guard !match.isEmpty else { return [] }
        return try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT DISTINCT u.image_id
                FROM ai_understanding_fts f
                JOIN ai_understanding u ON u.id = f.rowid
                WHERE ai_understanding_fts MATCH ? AND u.active = 1
                ORDER BY rank
                LIMIT ?
                """)
            try statement.bindText(1, match)
            try statement.bindInt(2, Int64(limit))
            var ids: [Int64] = []
            while try statement.step() {
                if let id = statement.columnInt(0) { ids.append(id) }
            }
            return ids
        }
    }

    /// Sanitize user text into an FTS5 MATCH expression: each
    /// whitespace-separated token becomes a quoted phrase (internal quotes
    /// doubled per FTS5 escaping), joined by implicit AND. Syntax characters
    /// in user input (parens, stars, colons, dashes) lose their operator
    /// meaning — they match literally or not at all, but never throw.
    static func ftsMatchQuery(_ raw: String) -> String {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { token -> String in
                let escaped = token
                    .replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
        return tokens.joined(separator: " ")
    }
}
