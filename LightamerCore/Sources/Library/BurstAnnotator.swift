import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// BurstAnnotator (Plan LUMEN-A T6, X4/D-LU-2) — the QUERY-TIME burst
// grouping + best-of-burst annotation (zero DB writes, zero entities — the
// grid folds/badges render from the returned groups).
//
// ATTRIBUTION (NOTICE entry Q, Lumen RAW): the algorithm is a literal
// transliteration of LUMEN RAW (https://github.com/LeisureLinux/lumen, MIT
// License, Copyright (c) 2026 LUMEN RAW contributors,
// `lumen/library_db.py` annotate_bursts/_copy/_similar/signature_difference
// + BURST_GAP/BURST_DIFFERENCE constants). The implementation is independent
// Swift — no upstream code copied.
//
// The five algorithm points (CONTEXT X4):
//   1. sort key = (make, model, serial) triple + captured_ts + filename
//      tiebreak; rows without a timestamp NEVER group.
//   2. copy exclusion (`_copy` literal): same moment (±1e-3 s) + filename
//      stem prefix-containment (an export like `name-Lumen.jpg` or the JPEG
//      of a RAW+JPEG pair is not another frame) — checked against the last
//      THREE accepted rows of the current group.
//   3. grouping = same camera triple + adjacent gap ≤ 2.0 s + signature
//      similarity (each 16×16 signature zero-mean/unit-deviation normalized
//      with the +4 stddev damper, then per-pixel MAD ≤ 0.6). nil/absent
//      signatures are "similar" (Lumen `_similar` — unanalyzed rows still
//      group on time alone).
//   4. best = the frame to keep: eyes-open first (the D-LU-4 THRESHOLD-FREE
//      arm — the wider-open eye's ratio, higher wins; a row with no ratio
//      ranks as fully open, Lumen's `not None == True` analog), then
//      sharpness descending, then the group's index order (stable).
//   5. hints (Lumen annotate_hints): blurry = sharpness < 22 outright, or
//      in-burst and more than 14 below the group's best sharpness.
//
// Group identity = StableHash (FNV-1a 64) DECIMAL STRING over the canonical
// member/camera/time tuple (L013 — Swift Hasher never crosses a persistence
// boundary; the MCP list_bursts:1243 precedent). Group ≥ 2 frames only.
// ─────────────────────────────────────────────────────────────────────────────

/// One row as the annotator consumes it (the LibraryQueries projection).
public struct BurstRow: Sendable, Equatable {
    public let imageID: Int64
    public let make: String?
    public let model: String?
    public let serial: String?
    /// Epoch seconds (nil = the row never groups — Lumen's ts filter).
    public let capturedTS: Double?
    /// The 16×16 Signature16 bytes.
    public let signature: Data?
    /// The wider-open eye's ratio (T4's `Face.maxRatio`; nil = no landmark).
    public let eyesRatio: Double?
    /// The stored eyes_closed column (the T7 badge's absolute-hint face;
    /// nil = un-analysed).
    public let eyesClosed: Bool?
    public let sharpness: Double?
    /// The stored filename (the copy-exclusion stem source).
    public let filename: String?

    public init(
        imageID: Int64, make: String?, model: String?, serial: String?,
        capturedTS: Double?, signature: Data?, eyesRatio: Double?,
        eyesClosed: Bool? = nil, sharpness: Double?, filename: String?
    ) {
        self.imageID = imageID
        self.make = make
        self.model = model
        self.serial = serial
        self.capturedTS = capturedTS
        self.signature = signature
        self.eyesRatio = eyesRatio
        self.eyesClosed = eyesClosed
        self.sharpness = sharpness
        self.filename = filename
    }
}

/// One formed group (≥2 frames). `id` = the L013 StableHash decimal string;
/// `imageIDs` = the group's member order (index 1-based positions map onto
/// this array).
public struct BurstGroup: Sendable, Equatable {
    public let id: String
    public let imageIDs: [Int64]
}

/// One row's annotation (the grid badge payload).
public struct BurstAnnotation: Sendable, Equatable {
    /// Group number 1..n (0 = not in a burst).
    public let burst: Int
    /// 1-based position inside the group (0 when alone).
    public let burstIndex: Int
    /// The group's frame count (1 when alone).
    public let burstSize: Int
    /// The frame to keep (eyes-open first, then sharpest).
    public let best: Bool
    /// Lumen annotate_hints: low sharpness or far below the group best.
    public let blurry: Bool
}

public enum BurstAnnotator {

    /// At most this many seconds between frames of the same camera.
    public static let burstGap = 2.0
    /// The signature MAD ceiling (zero-mean/unit-deviation normalized).
    public static let burstDifference = 0.6
    /// Sharpness below this (0-100) is blurry outright (Lumen BLURRY).
    public static let blurryFloor = 22.0
    /// … and so is a frame this far below its burst's sharpest (Lumen
    /// BURST_BLURRY).
    public static let burstBlurryDelta = 14.0

    // MARK: - The signature face (Lumen signature_difference)

    /// How different two 16×16 signatures look, brightness and contrast
    /// aside: zero-mean / (stddev + 4) normalization (the damper keeps flat
    /// signatures from exploding), then the mean absolute difference.
    public static func signatureDifference(_ a: Data, _ b: Data) -> Double {
        let x = a.map { Double($0) }
        let y = b.map { Double($0) }
        guard x.count == y.count, !x.isEmpty else { return 0 }
        let xm = x.reduce(0, +) / Double(x.count)
        let ym = y.reduce(0, +) / Double(y.count)
        let xs = sqrt(x.reduce(0) { $0 + ($1 - xm) * ($1 - xm) } / Double(x.count))
        let ys = sqrt(y.reduce(0) { $0 + ($1 - ym) * ($1 - ym) } / Double(y.count))
        let xDamper = xs + 4
        let yDamper = ys + 4
        var sum = 0.0
        for index in 0..<x.count {
            sum += abs((x[index] - xm) / xDamper - (y[index] - ym) / yDamper)
        }
        return sum / Double(x.count)
    }

    /// Lumen `_similar`: an absent/length-mismatched signature is ALWAYS
    /// "similar" (unanalyzed rows still group on time alone).
    static func similar(_ a: Data?, _ b: Data?) -> Bool {
        guard let a, let b, a.count == b.count else { return true }
        return signatureDifference(a, b) <= burstDifference
    }

    // MARK: - The copy exclusion (Lumen _copy)

    static func stem(of row: BurstRow) -> String {
        let name = row.filename ?? ""
        guard let dot = name.lastIndex(of: "."), name.startIndex < dot else {
            return name.lowercased()
        }
        return String(name[name.startIndex..<dot]).lowercased()
    }

    /// Same moment (±1e-3 s) + stem prefix-containment → a copy/export/the
    /// JPEG of a RAW+JPEG pair, never another burst frame.
    static func isCopy(_ a: BurstRow, _ b: BurstRow) -> Bool {
        if abs((a.capturedTS ?? 0) - (b.capturedTS ?? 0)) > 1e-3 { return false }
        let x = stem(of: a)
        let y = stem(of: b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.hasPrefix(y) || y.hasPrefix(x)
    }

    // MARK: - The annotation (Lumen annotate_bursts)

    /// Group the rows (Lumen's algorithm verbatim) and return the formed
    /// groups (≥2 frames, first-timestamp order, group numbering = the
    /// returned array order starting at 1).
    public static func groups(for rows: [BurstRow]) -> [BurstGroup] {
        rowGroups(for: rows).map { group in
            // L013: the canonical identity string — member ids (group
            // order) + the camera triple + the first frame's epoch. DECISIONS
            // pins this spelling (review m-5 ③).
            let camera = group.first!
            let canonical = group.map { String($0.imageID) }.joined(separator: ",")
                + "|\(camera.make ?? "")|\(camera.model ?? "")|\(camera.serial ?? "")"
                + "|\(String(format: "%.3f", camera.capturedTS ?? 0))"
            return BurstGroup(
                id: String(StableHash.hash(canonical)),
                imageIDs: group.map(\.imageID))
        }
    }

    /// The row-order groups (the annotate pass iterates the ROWS).
    static func rowGroups(for rows: [BurstRow]) -> [[BurstRow]] {
        // The timed subset + the sort key (nils spell '' like Lumen's
        // `or ''` tuple members).
        let timed = rows
            .filter { $0.capturedTS != nil }
            .sorted { a, b in
                let keyA = (
                    a.make ?? "", a.model ?? "", a.serial ?? "",
                    a.capturedTS ?? 0, a.filename ?? ""
                )
                let keyB = (
                    b.make ?? "", b.model ?? "", b.serial ?? "",
                    b.capturedTS ?? 0, b.filename ?? ""
                )
                return keyA < keyB
            }

        var groups: [[BurstRow]] = []
        var current: [BurstRow] = []
        for row in timed {
            if !current.isEmpty {
                // The copy exclusion looks at the last THREE accepted rows.
                if current.suffix(3).contains(where: { isCopy($0, row) }) {
                    continue
                }
                let last = current[current.count - 1]
                let sameCamera =
                    (last.make ?? "", last.model ?? "", last.serial ?? "")
                        == (row.make ?? "", row.model ?? "", row.serial ?? "")
                let delta = row.capturedTS! - last.capturedTS!
                if sameCamera, delta >= 0, delta <= burstGap,
                   similar(last.signature, row.signature) {
                    current.append(row)
                    continue
                }
                if current.count > 1 {
                    groups.append(current)
                }
            }
            current = [row]
        }
        if current.count > 1 {
            groups.append(current)
        }
        // Group numbering rides first-timestamp order (Lumen's re-sort).
        groups.sort { ($0.first?.capturedTS ?? 0) < ($1.first?.capturedTS ?? 0) }
        return groups
    }

    /// The full per-row annotation (groups + best + the blurry hints).
    /// Rows not in any group read burst=0/index=0/size=1/best=false and
    /// blurry only via the absolute floor.
    public static func annotate(rows: [BurstRow]) -> [Int64: BurstAnnotation] {
        var result: [Int64: BurstAnnotation] = [:]
        for row in rows {
            result[row.imageID] = BurstAnnotation(
                burst: 0, burstIndex: 0, burstSize: 1, best: false,
                blurry: (row.sharpness ?? 1) < blurryFloor && row.sharpness != nil)
        }

        let formed = rowGroups(for: rows)
        for (number, group) in formed.enumerated() {
            // Best: eyes-open first (ratio, higher wins; nil = fully open —
            // the Lumen `not None == True` analog, review m-5 ①), then
            // sharpness descending (nil = -1), then group index ascending.
            var bestRow = group[0]
            var currentBest = bestKey(of: group[0], index: 0)
            for (index, row) in group.enumerated() where index > 0 {
                let key = bestKey(of: row, index: index)
                if key > currentBest {
                    currentBest = key
                    bestRow = row
                }
            }
            // Lumen annotate_hints: the group's MAX SHARPNESS (any row),
            // never the best-frame's own sharpness.
            let groupBest = group.compactMap(\.sharpness).max() ?? 0
            for (index, row) in group.enumerated() {
                let blurry: Bool
                if let value = row.sharpness {
                    blurry = value < blurryFloor
                        || groupBest - value > burstBlurryDelta
                } else {
                    blurry = false
                }
                result[row.imageID] = BurstAnnotation(
                    burst: number + 1,
                    burstIndex: index + 1,
                    burstSize: group.count,
                    best: row.imageID == bestRow.imageID,
                    blurry: blurry)
            }
        }
        return result
    }

    /// The comparator tuple (review m-5 ①: the eyes dimension is the
    /// THRESHOLD-FREE relative ratio; nil = 1.0).
    static func bestKey(of row: BurstRow, index: Int) -> (
        eyes: Double, sharpness: Double, index: Int
    ) {
        (row.eyesRatio ?? 1.0, row.sharpness ?? -1, -index)
    }
}
