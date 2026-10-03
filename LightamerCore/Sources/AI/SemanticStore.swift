import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SemanticStore (Plan M2-10-02 KD-2) — the AI-library four-domain read/write
// face over the OPEN `.lalb` package: the semantic MODEL registry (the OQ-9-A
// single active model), the fp16 EMBEDDINGS, the LABELS (+ the factory
// label_query rows), the AI UNDERSTANDING rows (+ their FTS mirror), and the
// append-only AI RATINGS. One actor over the ProjectFileStore's
// single-writer seam (`LibraryStore` same shape) — every write rides
// `withWriteBatch`, every read `withHandle` (the WAL one-writer discipline).
//
// FP16 BLOB (KD-1): embeddings store as native-endian fp16, `dim*2` bytes —
// `FP16Coding` is the single pack/decode face (the scanner consumes the same
// rows). Single-machine app: NO cross-endian exchange semantics (DECISIONS
// pins the posture).
//
// RECONCILE DISCIPLINE: labels replace WHOLE-GROUP (the M2-8
// replaceVersionRefs shape — re-runs are idempotent); understanding upserts
// by UNIQUE(image_id, task_id) with the sibling rows' active flag flipped to
// 0 in the SAME transaction (旧行留痕 = other tasks' rows, not the replaced
// one); ratings append (history, latest-per-image via the id order).
//
// CHECKER E5 CONTRACT (pinned at `replaceUnderstanding`): the
// `ai_understanding_fts` index is ROW-SYNCHRONOUS with NO active concept —
// active=0 history rows REMAIN in the index. Every MATCH consumer (the
// M2-10-04 fulltext leg) MUST JOIN `ai_understanding` and filter
// `active = 1`.
// ─────────────────────────────────────────────────────────────────────────────

/// One `loadScanRows` output row: the image rowid + the raw fp16 BLOB (the
/// scanner converts to fp32 in its own loop — the store never materializes
/// the fp32 copy for the whole table).
public struct EmbeddingScanRow: Sendable {
    public let imageID: Int64
    public let fp16: Data

    public init(imageID: Int64, fp16: Data) {
        self.imageID = imageID
        self.fp16 = fp16
    }
}

/// The fp16 BLOB coding (native endian, `dim*2` bytes) — the ONE pack /
/// decode face shared by the store (pack) and the scanner (decode).
public enum FP16Coding {
    /// `[Float]` → native-endian fp16 bytes.
    public static func pack(_ vector: [Float]) -> Data {
        var halves = [Float16](repeating: 0, count: vector.count)
        for (index, value) in vector.enumerated() { halves[index] = Float16(value) }
        return halves.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Native-endian fp16 bytes → `[Float]` (exact inverse of `pack` up to
    /// the fp16 representation error, |Δ| ≤ ~5e-4 for unit-scale values).
    public static func unpack(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float16>.size
        var halves = [Float16](repeating: 0, count: count)
        halves.withUnsafeMutableBufferPointer { buffer in
            data.copyBytes(to: buffer)
        }
        var floats = [Float](repeating: 0, count: count)
        for index in 0..<count { floats[index] = Float(halves[index]) }
        return floats
    }
}

public actor SemanticStore {

    private let store: ProjectFileStore

    public init(store: ProjectFileStore) {
        self.store = store
    }

    // MARK: - semantic_model (the OQ-9-A single-activation registry)

    public struct ModelRecord: Sendable, Equatable {
        public let modelKey: String
        public let modelID: String
        public let revision: String
        public let embeddingDim: Int
        public let imageSize: Int
        /// CLIP-family profiles carry no rubric — nil (the reserved D-2
        /// column position).
        public let promptConfigHash: String?
        public let active: Bool

        public init(
            modelKey: String, modelID: String, revision: String,
            embeddingDim: Int, imageSize: Int,
            promptConfigHash: String? = nil, active: Bool
        ) {
            self.modelKey = modelKey
            self.modelID = modelID
            self.revision = revision
            self.embeddingDim = embeddingDim
            self.imageSize = imageSize
            self.promptConfigHash = promptConfigHash
            self.active = active
        }
    }

    /// Upsert one model profile. `active = true` demotes the previous
    /// active row in the SAME batch (the DB's partial unique index is the
    /// backstop — two active rows can never commit).
    public func upsertModel(_ record: ModelRecord) async throws {
        try await store.withWriteBatch { handle -> Bool in
            if record.active {
                try handle.exec(
                    "UPDATE semantic_model SET active = 0 WHERE active = 1")
            }
            let upsert = try handle.prepare("""
                INSERT OR REPLACE INTO semantic_model (model_key, model_id,
                    revision, embedding_dim, image_size, prompt_config_hash,
                    active)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """)
            try upsert.bindText(1, record.modelKey)
            try upsert.bindText(2, record.modelID)
            try upsert.bindText(3, record.revision)
            try upsert.bindInt(4, Int64(record.embeddingDim))
            try upsert.bindInt(5, Int64(record.imageSize))
            try upsert.bindText(6, record.promptConfigHash)
            try upsert.bindInt(7, record.active ? 1 : 0)
            _ = try upsert.step()
            return true
        }
    }

    /// The single active model, or nil when none (the engine's typed
    /// `.modelUnavailable` source).
    public func activeModel() async throws -> ModelRecord? {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT model_key, model_id, revision, embedding_dim, image_size,
                    prompt_config_hash, active
                FROM semantic_model WHERE active = 1
                """)
            guard try statement.step() else { return nil }
            return Self.modelRecord(from: statement)
        }
    }

    private static func modelRecord(
        from statement: SQLiteStatement
    ) -> ModelRecord {
        ModelRecord(
            modelKey: statement.columnText(0) ?? "",
            modelID: statement.columnText(1) ?? "",
            revision: statement.columnText(2) ?? "",
            embeddingDim: Int(statement.columnInt(3) ?? 0),
            imageSize: Int(statement.columnInt(4) ?? 0),
            promptConfigHash: statement.columnText(5),
            active: (statement.columnInt(6) ?? 0) == 1)
    }

    // MARK: - image_embedding (fp16 BLOB domain)

    /// Insert-or-replace one image's embedding (fp16-packed here; the
    /// dimension rides its own column so a scan can validate cheaply).
    public func upsertEmbedding(
        imageID: Int64, modelKey: String, vector: [Float],
        computedTime: Int64
    ) async throws {
        let blob = FP16Coding.pack(vector)
        try await store.withWriteBatch { handle -> Bool in
            let upsert = try handle.prepare("""
                INSERT OR REPLACE INTO image_embedding (image_id, model_key,
                    dim, embedding, computed_time)
                VALUES (?, ?, ?, ?, ?)
                """)
            try upsert.bindInt(1, imageID)
            try upsert.bindText(2, modelKey)
            try upsert.bindInt(3, Int64(vector.count))
            try upsert.bindBlob(4, blob)
            try upsert.bindInt(5, computedTime)
            _ = try upsert.step()
            return true
        }
    }

    /// Delete embeddings for one image; `modelKey = nil` sweeps every
    /// model's rows (the换档重算 consumer).
    public func deleteEmbeddings(imageID: Int64, modelKey: String? = nil) async throws {
        try await store.withWriteBatch { handle -> Bool in
            let delete: SQLiteStatement
            if let modelKey {
                delete = try handle.prepare(
                    "DELETE FROM image_embedding WHERE image_id = ? AND model_key = ?")
                try delete.bindInt(1, imageID)
                try delete.bindText(2, modelKey)
            } else {
                delete = try handle.prepare(
                    "DELETE FROM image_embedding WHERE image_id = ?")
                try delete.bindInt(1, imageID)
            }
            _ = try delete.step()
            return true
        }
    }

    /// The scanner's input: every (image_id, fp16) row for the model key,
    /// built by incremental statement steps (NO intermediate copies — the
    /// one array of rows is the whole materialization).
    public func loadScanRows(modelKey: String) async throws -> [EmbeddingScanRow] {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT image_id, embedding FROM image_embedding
                WHERE model_key = ?
                """)
            try statement.bindText(1, modelKey)
            var rows: [EmbeddingScanRow] = []
            while try statement.step() {
                if let imageID = statement.columnInt(0),
                   let blob = statement.columnBlob(1) {
                    rows.append(EmbeddingScanRow(imageID: imageID, fp16: blob))
                }
            }
            return rows
        }
    }

    // MARK: - image_label (the M2-10-03 write face; frozen here)

    public struct LabelRow: Sendable, Equatable {
        public let label: String
        public let score: Double
        public let secondLabel: String?
        public let secondScore: Double?
        public let margin: Double?
        public let confident: Bool
        public let topScoresJSON: String?

        public init(
            label: String, score: Double, secondLabel: String? = nil,
            secondScore: Double? = nil, margin: Double? = nil,
            confident: Bool, topScoresJSON: String? = nil
        ) {
            self.label = label
            self.score = score
            self.secondLabel = secondLabel
            self.secondScore = secondScore
            self.margin = margin
            self.confident = confident
            self.topScoresJSON = topScoresJSON
        }
    }

    /// Whole-group reconcile: the (image, model) group is deleted and the
    /// given rows inserted in ONE transaction — re-runs are idempotent.
    public func replaceLabels(
        imageID: Int64, modelKey: String, rows: [LabelRow]
    ) async throws {
        try await store.withWriteBatch { handle -> Bool in
            let delete = try handle.prepare(
                "DELETE FROM image_label WHERE image_id = ? AND model_key = ?")
            try delete.bindInt(1, imageID)
            try delete.bindText(2, modelKey)
            _ = try delete.step()
            let insert = try handle.prepare("""
                INSERT INTO image_label (image_id, model_key, label, score,
                    second_label, second_score, margin, confident, top_scores)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for row in rows {
                try insert.reset()
                try insert.bindInt(1, imageID)
                try insert.bindText(2, modelKey)
                try insert.bindText(3, row.label)
                try insert.bindDouble(4, row.score)
                try insert.bindText(5, row.secondLabel)
                try insert.bindDouble(6, row.secondScore)
                try insert.bindDouble(7, row.margin)
                try insert.bindInt(8, row.confident ? 1 : 0)
                try insert.bindText(9, row.topScoresJSON)
                _ = try insert.step()
            }
            return true
        }
    }

    /// Every label row of one image (any model key; the display face).
    public func labels(for imageID: Int64) async throws -> [LabelRow] {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT label, score, second_label, second_score, margin,
                    confident, top_scores
                FROM image_label WHERE image_id = ?
                ORDER BY model_key, score DESC
                """)
            try statement.bindInt(1, imageID)
            var rows: [LabelRow] = []
            while try statement.step() {
                rows.append(
                    LabelRow(
                        label: statement.columnText(0) ?? "",
                        score: statement.columnDouble(1) ?? 0,
                        secondLabel: statement.columnText(2),
                        secondScore: statement.columnDouble(3),
                        margin: statement.columnDouble(4),
                        confident: (statement.columnInt(5) ?? 0) == 1,
                        topScoresJSON: statement.columnText(6)))
            }
            return rows
        }
    }

    // MARK: - label_query (the factory query text)

    public struct LabelQueryRow: Sendable, Equatable {
        public let modelKey: String
        public let label: String
        public let queryText: String
        public let lang: String

        public init(modelKey: String, label: String, queryText: String, lang: String) {
            self.modelKey = modelKey
            self.label = label
            self.queryText = queryText
            self.lang = lang
        }
    }

    /// Factory seed — idempotent (`INSERT OR IGNORE`; the PK
    /// (model_key, label, lang) is the dedup face).
    public func seedLabelQueries(_ rows: [LabelQueryRow]) async throws {
        try await store.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT OR IGNORE INTO label_query (model_key, label,
                    query_text, lang)
                VALUES (?, ?, ?, ?)
                """)
            for row in rows {
                try insert.reset()
                try insert.bindText(1, row.modelKey)
                try insert.bindText(2, row.label)
                try insert.bindText(3, row.queryText)
                try insert.bindText(4, row.lang)
                _ = try insert.step()
            }
            return true
        }
    }

    public func labelQueries(modelKey: String) async throws -> [LabelQueryRow] {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT model_key, label, query_text, lang
                FROM label_query WHERE model_key = ?
                ORDER BY label, lang
                """)
            try statement.bindText(1, modelKey)
            var rows: [LabelQueryRow] = []
            while try statement.step() {
                rows.append(
                    LabelQueryRow(
                        modelKey: statement.columnText(0) ?? "",
                        label: statement.columnText(1) ?? "",
                        queryText: statement.columnText(2) ?? "",
                        lang: statement.columnText(3) ?? ""))
            }
            return rows
        }
    }

    // MARK: - ai_understanding (+ the FTS mirror)

    public struct UnderstandingRow: Sendable, Equatable {
        public let imageID: Int64
        public let taskID: String
        public let providerID: String
        public let modelID: String
        /// FNV-1a DECIMAL String (L013 — never a raw hash integer).
        public let promptProfileID: String
        public let renditionKind: String
        public let caption: String?
        /// JSON array (the FTS document column).
        public let tags: String?
        public let scene: String?
        public let confidence: Double?
        public let computedTime: Int64

        public init(
            imageID: Int64, taskID: String, providerID: String,
            modelID: String, promptProfileID: String,
            renditionKind: String = "edited", caption: String?, tags: String?,
            scene: String? = nil, confidence: Double? = nil, computedTime: Int64
        ) {
            self.imageID = imageID
            self.taskID = taskID
            self.providerID = providerID
            self.modelID = modelID
            self.promptProfileID = promptProfileID
            self.renditionKind = renditionKind
            self.caption = caption
            self.tags = tags
            self.scene = scene
            self.confidence = confidence
            self.computedTime = computedTime
        }
    }

    /// The reconcile upsert (ONE transaction): sibling rows of the same
    /// image flip to `active = 0` (旧行留痕), the (image_id, task_id) row
    /// is explicitly DELETED and re-INSERTED at active=1 — the FTS triggers
    /// unstage the old document and stage the new one.
    ///
    /// WHY NOT `INSERT OR REPLACE`: a conflict-resolution delete fires the
    /// AFTER DELETE trigger only when `recursive_triggers` is ON (off by
    /// default) — the external-content index would keep BOTH documents
    /// staged under the rowid (silent MATCH drift). The explicit DELETE
    /// always fires the trigger (the plain-statement leg).
    ///
    /// CHECKER E5 CONTRACT: `ai_understanding_fts` indexes EVERY row with
    /// no active concept — active=0 history rows REMAIN searchable. Any
    /// MATCH consumer MUST `JOIN ai_understanding … WHERE active = 1`
    /// (the M2-10-04 fulltext leg owns that join; this store never
    /// fabricates one).
    public func replaceUnderstanding(_ row: UnderstandingRow) async throws {
        try await store.withWriteBatch { handle -> Bool in
            let demote = try handle.prepare(
                "UPDATE ai_understanding SET active = 0 WHERE image_id = ? AND task_id <> ?")
            try demote.bindInt(1, row.imageID)
            try demote.bindText(2, row.taskID)
            _ = try demote.step()
            let delete = try handle.prepare(
                "DELETE FROM ai_understanding WHERE image_id = ? AND task_id = ?")
            try delete.bindInt(1, row.imageID)
            try delete.bindText(2, row.taskID)
            _ = try delete.step()
            let insert = try handle.prepare("""
                INSERT INTO ai_understanding (image_id, task_id,
                    provider_id, model_id, prompt_profile_id, rendition_kind,
                    caption, tags, scene, confidence, active, computed_time)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                """)
            try insert.bindInt(1, row.imageID)
            try insert.bindText(2, row.taskID)
            try insert.bindText(3, row.providerID)
            try insert.bindText(4, row.modelID)
            try insert.bindText(5, row.promptProfileID)
            try insert.bindText(6, row.renditionKind)
            try insert.bindText(7, row.caption)
            try insert.bindText(8, row.tags)
            try insert.bindText(9, row.scene)
            try insert.bindDouble(10, row.confidence)
            try insert.bindInt(11, row.computedTime)
            _ = try insert.step()
            return true
        }
    }

    /// Every understanding row of one image, newest task first (the read
    /// face; active flag rides the row).
    public func understandings(imageID: Int64) async throws -> [(row: UnderstandingRow, active: Bool)] {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT task_id, provider_id, model_id, prompt_profile_id,
                    rendition_kind, caption, tags, scene, confidence,
                    computed_time, active
                FROM ai_understanding WHERE image_id = ?
                ORDER BY computed_time DESC, id DESC
                """)
            try statement.bindInt(1, imageID)
            var rows: [(row: UnderstandingRow, active: Bool)] = []
            while try statement.step() {
                let value = UnderstandingRow(
                    imageID: imageID,
                    taskID: statement.columnText(0) ?? "",
                    providerID: statement.columnText(1) ?? "",
                    modelID: statement.columnText(2) ?? "",
                    promptProfileID: statement.columnText(3) ?? "",
                    renditionKind: statement.columnText(4) ?? "edited",
                    caption: statement.columnText(5),
                    tags: statement.columnText(6),
                    scene: statement.columnText(7),
                    confidence: statement.columnDouble(8),
                    computedTime: statement.columnInt(9) ?? 0)
                rows.append((value, (statement.columnInt(10) ?? 0) == 1))
            }
            return rows
        }
    }

    // MARK: - ai_rating (append-only history)

    public struct RatingRow: Sendable, Equatable {
        public let imageID: Int64
        public let taskID: String
        public let providerID: String
        public let modelID: String
        public let promptProfileID: String
        /// 0 = the reasons-only sentinel (D-4); 1-5 = real stars.
        public let rating: Int
        public let reasons: String?
        public let computedTime: Int64

        public init(
            imageID: Int64, taskID: String, providerID: String,
            modelID: String, promptProfileID: String, rating: Int,
            reasons: String? = nil, computedTime: Int64
        ) {
            self.imageID = imageID
            self.taskID = taskID
            self.providerID = providerID
            self.modelID = modelID
            self.promptProfileID = promptProfileID
            self.rating = rating
            self.reasons = reasons
            self.computedTime = computedTime
        }
    }

    /// Append one rating row (append-only; `id INTEGER PRIMARY KEY` order
    /// is the history order).
    public func appendRating(_ row: RatingRow) async throws {
        try await store.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO ai_rating (image_id, task_id, provider_id,
                    model_id, prompt_profile_id, rating, reasons, computed_time)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            try insert.bindInt(1, row.imageID)
            try insert.bindText(2, row.taskID)
            try insert.bindText(3, row.providerID)
            try insert.bindText(4, row.modelID)
            try insert.bindText(5, row.promptProfileID)
            try insert.bindInt(6, Int64(row.rating))
            try insert.bindText(7, row.reasons)
            try insert.bindInt(8, row.computedTime)
            _ = try insert.step()
            return true
        }
    }

    /// The newest rating row of one image (id DESC), or nil.
    public func latestRating(imageID: Int64) async throws -> RatingRow? {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT task_id, provider_id, model_id, prompt_profile_id,
                    rating, reasons, computed_time
                FROM ai_rating WHERE image_id = ?
                ORDER BY id DESC LIMIT 1
                """)
            try statement.bindInt(1, imageID)
            guard try statement.step() else { return nil }
            return RatingRow(
                imageID: imageID,
                taskID: statement.columnText(0) ?? "",
                providerID: statement.columnText(1) ?? "",
                modelID: statement.columnText(2) ?? "",
                promptProfileID: statement.columnText(3) ?? "",
                rating: Int(statement.columnInt(4) ?? 0),
                reasons: statement.columnText(5),
                computedTime: statement.columnInt(6) ?? 0)
        }
    }
}
