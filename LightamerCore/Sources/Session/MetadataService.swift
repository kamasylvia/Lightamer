import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// MetadataService (Plan 12-1 T4; D-12-CONTEXT-8) — the SINGLE write entry
// for the metadata face (rating / flag / colorLabel / keywords / note).
// GUI shortcuts, menus, the inspector rows and the Phase 14 MCP-06 tools
// all call THESE methods — one implementation, no drift.
//
// The write path is the Phase 9 three-segment batch pipeline (9-4 同构),
// with the F6 metadata-specific semantics:
//
//   段1  MEMORY: read each target's DISK SIDECAR (真身恒 sidecar), mutate
//        the metadata fields IN PLACE — never a history item, never a
//        params change (D-8: a rating must not produce a history entry,
//        must not flip paramsHash, must not stale thumbnails).
//   段2  INDEX: `claimMetadataApply` — ONE transaction (PK-seek per row,
//        10k shape) setting the five columns + predicted sidecar_mtime +
//        dirty=1. The dirty flag opens the F6 consistency window: a crash
//        before segment 3 heals the row BACK to the disk sidecar's values
//        (旧值回填 — the score honestly did not land).
//   段3  SIDECAR: `BatchSidecarWriter`'s serial queue (atomic promotion,
//        journal, dirty=0 write-back) — the shared 9-4 queue, untouched.
//
// D-8 red lines, enforced by construction AND by MetadataServiceTests:
// no history commit, no HistoryHash input change, `claimMetadataApplySQL`
// does not list thumb_state/params_hash — 万张打分零缩略图再生.
// ─────────────────────────────────────────────────────────────────────────────

/// The edit bookkeeping (the test + UI assertion face; BatchApplyOutcome
/// shape twin).
public struct MetadataEditOutcome: Sendable, Equatable {
    /// relPaths whose documents were composed + claimed + queued.
    public var appliedRelPaths: [String]
    /// relPaths skipped BEFORE any write: an existing-but-unreadable
    /// sidecar is NEVER clobbered by a metadata edit (SC#2 posture —
    /// stronger than the 9-4 param batch, which may overwrite a corrupt
    /// file; a metadata write must never destroy edits).
    public var skippedRelPaths: [String]

    public init(appliedRelPaths: [String] = [], skippedRelPaths: [String] = []) {
        self.appliedRelPaths = appliedRelPaths
        self.skippedRelPaths = skippedRelPaths
    }
}

public struct MetadataService: Sendable {

    /// The typed keyword-entry rejection (RESEARCH §3.1: `|` is the
    /// hierarchical path separator — an entry containing it would corrupt
    /// the path semantics).
    public enum MetadataError: Error, Equatable, Sendable {
        case keywordContainsSeparator(String)
    }

    private let root: URL
    private let store: SessionIndexStore
    /// The segment-3 serial queue (shared with the 9-4 batch face). nil =
    /// segments 1+2 only (the 万张 gate measures this shape).
    private let writer: BatchSidecarWriter?
    /// The identity-default seed for PRISTINE targets (no sidecar yet) —
    /// the batch-apply posture: a metadata-only document seeds the default
    /// instance set so a later editor load resolves the default chain.
    private let seed: [ModuleInstance]

    public init(
        root: URL,
        store: SessionIndexStore,
        writer: BatchSidecarWriter?,
        seed: [ModuleInstance] = []
    ) {
        self.root = root
        self.store = store
        self.writer = writer
        self.seed = seed
    }

    // MARK: - The API face (GUI / MCP-06 同源)

    /// Star rating (nil = clear). The 0-key UI semantic maps to nil.
    public func setRating(_ value: Int?, relPaths: [String]) async throws
        -> MetadataEditOutcome
    {
        try await apply(relPaths: relPaths) { document in
            document.rating = value
        }
    }

    /// Culling flag (0 none / 1 pick / 2 reject; nil = clear). The X/P
    /// TOGGLE semantics live in the caller (it reads the current value).
    public func setFlag(_ value: Int?, relPaths: [String]) async throws
        -> MetadataEditOutcome
    {
        try await apply(relPaths: relPaths) { document in
            document.flag = value
        }
    }

    /// Color label (0...6; nil = clear).
    public func setColorLabel(_ value: Int?, relPaths: [String]) async throws
        -> MetadataEditOutcome
    {
        try await apply(relPaths: relPaths) { document in
            document.colorLabel = value
        }
    }

    /// Keywords — WHOLE-GROUP replacement (the MCP-09 set_keywords
    /// upstream semantics). Full path strings, `|`-separated. nil clears
    /// to never-tagged; `[]` records the cleared state.
    ///
    /// `allowHierarchical` opens the separator gate for the XMP-IMPORT
    /// face only (Plan 12-3 T5): third-party `lr:hierarchicalSubject`
    /// paths legitimately carry `|` — the default-strict validation
    /// exists to stop MANUAL ENTRY from typing the separator (RESEARCH
    /// §3.1), not to reject well-formed hierarchical paths.
    public func setKeywords(
        _ keywords: [String]?, relPaths: [String], allowHierarchical: Bool = false
    ) async throws -> MetadataEditOutcome {
        try Self.validate(keywords: keywords ?? [], allowHierarchical: allowHierarchical)
        return try await apply(relPaths: relPaths) { document in
            document.keywords = keywords
        }
    }

    /// Keywords — deduplicated append (META-03 batch editing). Ancestors
    /// are NOT materialized (the query face expands them).
    public func appendKeywords(_ keywords: [String], relPaths: [String]) async throws
        -> MetadataEditOutcome
    {
        try Self.validate(keywords: keywords)
        return try await apply(relPaths: relPaths) { document in
            let existing = document.keywords ?? []
            document.keywords = existing
                + keywords.filter { !existing.contains($0) }
        }
    }

    /// Note — appends one line (the MCP-06 append_note upstream semantics;
    /// a non-empty note gains a `\n` before the addition).
    public func appendNote(_ addition: String, relPaths: [String]) async throws
        -> MetadataEditOutcome
    {
        try await apply(relPaths: relPaths) { document in
            if let existing = document.note, !existing.isEmpty {
                document.note = existing + "\n" + addition
            } else {
                document.note = addition
            }
        }
    }

    // MARK: - Validation

    private static func validate(
        keywords: [String], allowHierarchical: Bool = false
    ) throws {
        guard !allowHierarchical else { return }
        for keyword in keywords where keyword.contains("|") {
            throw MetadataError.keywordContainsSeparator(keyword)
        }
    }

    // MARK: - The three segments

    /// 段1 (disk sidecar → in-memory metadata mutation) + 段2 (single-
    /// transaction claim) + 段3 (serial write queue).
    private func apply(
        relPaths: [String],
        mutate: (inout LightamerSidecar) -> Void
    ) async throws -> MetadataEditOutcome {
        guard !relPaths.isEmpty else { return MetadataEditOutcome() }

        // ── 段1: compose the new documents from the DISK truth.
        var composed: [(relPath: String, document: LightamerSidecar)] = []
        var skipped: [String] = []
        composed.reserveCapacity(relPaths.count)
        let decoder = JSONDecoder()

        for relPath in relPaths {
            let imageURL = root.appendingPathComponent(relPath)
            let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                guard let data = try? Data(contentsOf: sidecarURL),
                      var document = try? decoder.decode(
                        LightamerSidecar.self, from: data)
                else {
                    // Existing-but-unreadable: NEVER clobber it with a
                    // metadata-only document (the skip keeps the user's
                    // bytes honest; SC#2).
                    skipped.append(relPath)
                    continue
                }
                mutate(&document)
                composed.append((relPath, document))
            } else {
                // PRISTINE target: mint self-consistently (the batch-apply
                // posture — decode stamp 0/0, seeded defaults, empty
                // history). driftDetected recomputes from the file's OWN
                // fields, so a later load never false-positives.
                let history = HistoryStack()
                var document = LightamerSidecar(
                    imageID: UUID(),
                    decoderVersionUsed: "unknown-metadata",
                    decodeParamsHash: 0,
                    instances: seed,
                    history: history,
                    historyHash: HistoryHash.hash(
                        stack: history, decodeParamsHash: 0),
                    appVersion: LightamerSidecar.currentAppVersion,
                    layerStack: nil)
                mutate(&document)
                composed.append((relPath, document))
            }
        }
        guard !composed.isEmpty else {
            return MetadataEditOutcome(appliedRelPaths: [], skippedRelPaths: skipped)
        }

        // ── 段2: ONE transaction for all targets (the F6 claim — dirty=1
        // opens the crash window; the five columns mirror the composed
        // documents).
        let claimedMtime = Date().timeIntervalSince1970
        let claims: [SessionIndexStore.MetadataClaim] = composed.map { relPath, document in
            SessionIndexStore.MetadataClaim(
                relPath: relPath,
                rating: document.rating.map(Int64.init),
                colorLabel: document.colorLabel.map(Int64.init),
                keywords: SessionIndexStore.materializeKeywords(document.keywords),
                flag: document.flag.map(Int64.init),
                note: document.note,
                sidecarMtime: claimedMtime)
        }
        try await store.claimMetadataApply(claims: claims)

        // ── 段3: the serial write queue (enqueue awaits the drain; each
        // promotion clears its row's dirty flag). nil writer = the gate
        // shape (segments 1+2 only — rows stay honestly dirty).
        if let writer {
            await writer.enqueue(composed)
        }
        return MetadataEditOutcome(
            appliedRelPaths: composed.map(\.relPath),
            skippedRelPaths: skipped)
    }
}
