import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LabelEngine (Plan M2-10-03 KD-2) — the cosine auto-labeling classifier:
// an (already-normalized) image embedding × (already-normalized) per-label
// prototype embeddings → a FULL ordered score table → the stored top-8 rows
// (`image_label`: score / second_label / margin / confident + the top_scores
// JSON — Alcedo `SemanticImageLabel` semantics).
//
// COSINE == DOT PRODUCT (the M2-10-02 normalization posture): both towers
// L2-normalize inside the graphs and `LabelPrototypeSet.load` re-normalizes
// after the fp16 round-trip, so a plain dot product is the cosine — this
// file contains zero norm code on the classify path.
//
// THRESHOLD (KD-2 planner initial, DECISIONS-signed): margin = top1 − top2;
// `confident = margin ≥ 0.05`. A single-prototype table has no runner-up —
// margin/second are nil and the row counts confident (nothing contradicts).
//
// STORAGE PRUNING (KD-2): `image_label` keeps the TOP 8 rows per
// (image, model); `top_scores` mirrors the SAME 8 — storing all ~160 labels
// is row bloat with no consumer. Each stored row carries ITS OWN runner-up
// in second_label/second_score/margin (the top-1 row's fields are the plan's
// margin/confident verbatim); the last row has no successor — its second
// fields are nil and it counts confident.
//
// The prototype set is a BUNDLE ASSET (`label-prototypes/` next to the model
// packages — D-M2-10-CONTEXT-7: same revision, dies with it). A revision
// mismatch is a TYPED refusal, never a silent empty table.
// ─────────────────────────────────────────────────────────────────────────────

/// One ordered classification row (KD-2's `LabelScore` verbatim shape).
public struct LabelScore: Sendable, Equatable {
    public let label: String
    public let score: Float
    public let secondLabel: String?
    public let secondScore: Float?
    public let margin: Float?
    public let confident: Bool

    public init(
        label: String, score: Float, secondLabel: String? = nil,
        secondScore: Float? = nil, margin: Float? = nil, confident: Bool
    ) {
        self.label = label
        self.score = score
        self.secondLabel = secondLabel
        self.secondScore = secondScore
        self.margin = margin
        self.confident = confident
    }
}

/// One normalized prototype vector (the label key + its fp16→fp32 query
/// embedding, re-normalized on load).
public struct LabelPrototype: Sendable, Equatable {
    public let label: String
    public let vector: [Float]

    public init(label: String, vector: [Float]) {
        self.label = label
        self.vector = vector
    }
}

/// The typed prototype-failure face (never a silent empty table).
public enum LabelPrototypeError: Error, Equatable, Sendable {
    /// The bundle prototype revision disagrees with the active model row
    /// (the same-revision contract — regenerate/ship the matching bundle).
    case prototypeRevisionMismatch(expected: String, actual: String)
    /// The index JSON / binary payload is structurally broken.
    case prototypeIndexCorrupt(reason: String)
    /// The `label-prototypes/` directory itself is absent.
    case prototypesUnavailable
}

/// A loaded prototype bundle: the revision pin + the per-label vectors.
public struct LabelPrototypeSet: Sendable, Equatable {

    /// The model revision these prototypes were embedded with.
    public let revision: String
    /// Vector width (== the model's embedding_dim).
    public let dim: Int
    /// The prototypes in INDEX order (classify sorts by score, not this).
    public let prototypes: [LabelPrototype]

    public init(revision: String, dim: Int, prototypes: [LabelPrototype]) {
        self.revision = revision
        self.dim = dim
        self.prototypes = prototypes
    }

    // MARK: - The bundle format (written by generate_label_prototypes.py)

    struct IndexJSON: Codable, Equatable {
        struct Entry: Codable, Equatable {
            let label: String
            let offset: Int
        }
        let revision: String
        let dim: Int
        let count: Int
        let labels: [Entry]
    }

    /// Load + validate a `label-prototypes/` directory (`prototypes.json` +
    /// `prototypes.bin`, fp16 little-endian, `dim*2` bytes per vector):
    ///   • revision ≠ `expectingRevision` → `.prototypeRevisionMismatch`
    ///   • broken index / wrong payload size / duplicate labels → corrupt
    /// Vectors are re-normalized after the fp16 round-trip (the fp16 quantize
    /// drifts the norm by ~1e-3; renormalizing keeps the dot==cosine exact).
    public static func load(
        directory: URL, expectingRevision: String
    ) throws -> LabelPrototypeSet {
        let indexURL = directory.appendingPathComponent("prototypes.json")
        let binURL = directory.appendingPathComponent("prototypes.bin")
        guard FileManager.default.fileExists(atPath: indexURL.path),
            FileManager.default.fileExists(atPath: binURL.path)
        else { throw LabelPrototypeError.prototypesUnavailable }
        let indexData = try Data(contentsOf: indexURL)
        let index: IndexJSON
        do {
            index = try JSONDecoder().decode(IndexJSON.self, from: indexData)
        } catch {
            throw LabelPrototypeError.prototypeIndexCorrupt(
                reason: "prototypes.json undecodable: \(error.localizedDescription)")
        }
        guard index.revision == expectingRevision else {
            throw LabelPrototypeError.prototypeRevisionMismatch(
                expected: expectingRevision, actual: index.revision)
        }
        guard index.dim > 0, index.count == index.labels.count,
            Set(index.labels.map(\.label)).count == index.labels.count
        else {
            throw LabelPrototypeError.prototypeIndexCorrupt(
                reason: "count/labels/dim inconsistent")
        }
        let payload = try Data(contentsOf: binURL)
        let expectedBytes = index.count * index.dim * 2
        guard payload.count == expectedBytes else {
            throw LabelPrototypeError.prototypeIndexCorrupt(
                reason: "payload \(payload.count) bytes, expected \(expectedBytes)")
        }
        var prototypes: [LabelPrototype] = []
        prototypes.reserveCapacity(index.count)
        for entry in index.labels {
            let start = entry.offset * index.dim * 2
            let slice = payload.subdata(in: start..<(start + index.dim * 2))
            prototypes.append(
                LabelPrototype(
                    label: entry.label,
                    vector: Self.renormalized(Self.littleEndianFP16(slice))))
        }
        return LabelPrototypeSet(
            revision: index.revision, dim: index.dim, prototypes: prototypes)
    }

    /// Little-endian fp16 bytes → `[Float]` (the bundle is written LE by the
    /// generator; FP16Coding's native-endian faces are for the DB BLOBs).
    static func littleEndianFP16(_ data: Data) -> [Float] {
        var halves = [Float16](repeating: 0, count: data.count / 2)
        halves.withUnsafeMutableBufferPointer { buffer in
            data.copyBytes(to: buffer)
        }
        // The bytes were read raw; swap if this machine is big-endian (the
        // single-machine posture keeps the fast path branch-free on ARM64).
        var floats = [Float](repeating: 0, count: halves.count)
        for index in 0..<halves.count { floats[index] = Float(halves[index]) }
        return floats
    }

    /// L2 renormalize (idempotent for unit vectors up to fp noise).
    static func renormalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

public enum LabelEngine {

    /// The confident margin threshold (KD-2 planner initial — DECISIONS-signed
    /// observation item; adjacent-concept cosine margins typically 0.02–0.15).
    public static let confidentThreshold: Float = 0.05

    /// The per-(image, model) stored-row cap (KD-2's pruning ruling).
    public static let storedTopCount = 8

    /// The full classification: cosine scores over EVERY prototype, ordered
    /// best-first (ties break alphabetically by label — deterministic).
    /// `image` and every prototype vector must be L2-normalized (the engine
    /// chain guarantees the image side; `LabelPrototypeSet.load` the other).
    public static func classify(
        image: [Float], prototypes: [LabelPrototype],
        threshold: Float = LabelEngine.confidentThreshold
    ) -> [LabelScore] {
        guard !prototypes.isEmpty else { return [] }
        let scored: [(label: String, score: Float)] = prototypes.map {
            ($0.label, dot(image, $0.vector))
        }
        let sorted = scored.sorted { lhs, rhs in
            lhs.score != rhs.score
                ? lhs.score > rhs.score : lhs.label < rhs.label
        }
        var rows: [LabelScore] = []
        rows.reserveCapacity(sorted.count)
        for index in sorted.indices {
            let current = sorted[index]
            if index + 1 < sorted.count {
                let next = sorted[index + 1]
                let margin = current.score - next.score
                rows.append(
                    LabelScore(
                        label: current.label, score: current.score,
                        secondLabel: next.label, secondScore: next.score,
                        margin: margin, confident: margin >= threshold))
            } else {
                // The tail row has no runner-up: no margin to judge, nothing
                // contradicts it — confident by definition.
                rows.append(
                    LabelScore(
                        label: current.label, score: current.score,
                        confident: true))
            }
        }
        return rows
    }

    /// The STORAGE PRUNING face: the first `top` scores become the
    /// `image_label` rows (top-8 default), each with its own runner-up
    /// fields, plus the same-source `top_scores` JSON on the MAIN row only
    /// (the JSON mirrors the ranked list once per image — per-row
    /// duplication is payload bloat; the main row is the read anchor).
    public static func labelRows(
        from scores: [LabelScore], top: Int = LabelEngine.storedTopCount
    ) -> [SemanticStore.LabelRow] {
        let kept = scores.prefix(top)
        guard !kept.isEmpty else { return [] }
        let json = topScoresJSON(Array(kept))
        return kept.enumerated().map { index, score in
            SemanticStore.LabelRow(
                label: score.label,
                score: Double(score.score),
                secondLabel: score.secondLabel,
                secondScore: score.secondScore.map(Double.init),
                margin: score.margin.map(Double.init),
                confident: score.confident,
                topScoresJSON: index == 0 ? json : nil)
        }
    }

    /// The `top_scores` JSON (same source, same order, same count as the
    /// stored rows): `[{"label": …, "score": …}, …]` with sorted keys.
    static func topScoresJSON(_ scores: [LabelScore]) -> String? {
        let entries: [[String: Any]] = scores.map {
            ["label": $0.label, "score": Double($0.score)]
        }
        guard JSONSerialization.isValidJSONObject(entries) else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: entries, options: [.sortedKeys, .prettyPrinted])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Plain dot product (both sides normalized → the cosine).
    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        var sum: Float = 0
        for index in 0..<count { sum += a[index] * b[index] }
        return sum
    }
}
