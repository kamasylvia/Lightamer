import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The merge provenance record + its replay face (Plan 08-1 T6; RESEARCH
// §3.4/§12) — the sidecar v4 additive field that makes a merged product
// traceable and re-derivable.
//
// FORMAT DISCIPLINE (the inherited locks, all load-bearing here):
//   • ONE-WAY additive — `provenance` is optional; nil = a plain document,
//     old readers ignore the key, new readers of old docs see nil.
//   • UInt64String — every persisted hash serializes as a decimal String
//     (L013; FNV-1a values exceed 2^53).
//   • relPath — the sources are stored relative to the SESSION ROOT
//     (cross-machine / cross-volume migratable; the product's sidecar is
//     co-located with the product in the same root).
//   • one-way versioning — `schemaVersionCurrent` bumps 3→4; the v3 zero-
//     harm read is pinned by the tests.
//
// REPLAY SEMANTICS (research §3.4):
//   • Source drift: on load, every `sources[].stableHash` is recomputed
//     over the source file BYTES (streaming FNV-1a) and compared — a
//     mismatch marks the document dirty (「源已变更」) and offers the
//     re-merge entry (the service replays the SAME params).
//   • Idempotence: re-running the same sources+params lands a NEW file
//     (the ExportNamer increment never overwrites); equivalence is
//     detected at the provenance layer — `provenanceHash` (the FNV-1a
//     over the canonical algorithm+sources identity, EXCLUDING createdAt/
//     appVersion) matches an existing product → the UI may offer reuse.
// ─────────────────────────────────────────────────────────────────────────────

/// The persisted provenance of one merged document (the sidecar v4
/// `provenance` field's exact spelling).
public struct SidecarProvenance: Codable, Sendable, Equatable {

    /// The merge backend that produced the document (the service's kind
    /// vocabulary, verbatim). `hdrMertens` mirrors the service kind's raw
    /// value (Plan M5-2-01 KD-5 — the two enums' raw values stay aligned
    /// one-to-one).
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case hdrMerge = "hdr-merge"
        case focusStack = "focus-stack"
        case stackAverage = "stack-average"
        case stackMedian = "stack-median"
        case stackSigma = "stack-sigma"
        case hdrMertens = "hdr-merge-mertens"
        /// The spherical-feature panorama merge (Plan M5-3-01 KD-8 — the
        /// raw-value mirror of the service kind, the two enums' raw values
        /// stay aligned one-to-one).
        case panoMerge = "pano-merge"
    }

    /// The algorithm identity + its parameter snapshot (the replay's
    /// parameter source).
    public struct Algorithm: Codable, Sendable, Equatable {

        /// The algorithm family name (`"robertson02-mtb"` for v1 HDR).
        public var name: String

        /// The implementation version (a re-merge across a MATH change can
        /// be detected by comparing this — the replay warns, never silently
        /// mixes).
        public var implementationVersion: String

        /// The exact user-facing parameters the merge ran with.
        public var params: StackMergeService.MergeParams

        public init(
            name: String, implementationVersion: String,
            params: StackMergeService.MergeParams
        ) {
            self.name = name
            self.implementationVersion = implementationVersion
            self.params = params
        }
    }

    /// One source document of the merge.
    public struct Source: Codable, Sendable, Equatable {

        /// The source's path RELATIVE to the session root.
        public var relPath: String

        /// FNV-1a over the source FILE BYTES (drift detection's anchor;
        /// decimal String on disk — the L013 lock).
        @UInt64String public var stableHash: UInt64

        /// The source's exposure EV relative to the reference (the merge
        /// weight's t = 2^EV).
        public var exposureEV: Double

        public init(relPath: String, stableHash: UInt64, exposureEV: Double) {
            self.relPath = relPath
            self._stableHash = UInt64String(wrappedValue: stableHash)
            self.exposureEV = exposureEV
        }
    }

    /// The merge kind.
    public var kind: Kind

    /// The algorithm identity + parameters.
    public var algorithm: Algorithm

    /// The source set (reference first — the merge order).
    public var sources: [Source]

    /// The alignment outcome label (the `MTBShift.label` vocabulary:
    /// `"full"` / `"degraded"` / `"skipped-low-texture"` /
    /// `"skipped-user-override"`, per source, reference first).
    public var alignment: [String]

    /// The §1.2 runtime exposure-ratio self-check results (per source,
    /// reference first; the reference itself is always true).
    public var exposureRatioVerified: [Bool]

    /// The Σw==0 pixel fraction (the coverage/HOLE toast number).
    public var holeFraction: Float

    /// When the merge ran.
    public var createdAt: Date

    /// The producing app version (diagnostics only — never hashed).
    public var appVersion: String

    public init(
        kind: Kind,
        algorithm: Algorithm,
        sources: [Source],
        alignment: [String],
        exposureRatioVerified: [Bool],
        holeFraction: Float,
        createdAt: Date,
        appVersion: String
    ) {
        self.kind = kind
        self.algorithm = algorithm
        self.sources = sources
        self.alignment = alignment
        self.exposureRatioVerified = exposureRatioVerified
        self.holeFraction = holeFraction
        self.createdAt = createdAt
        self.appVersion = appVersion
    }
}

public enum ProvenanceReplay {

    /// The implementation version stamped into every v1 HDR provenance.
    public static let hdrImplementationVersion = "1"
    /// The v1 HDR algorithm family name.
    public static let hdrAlgorithmName = "robertson02-mtb"
    /// The Mertens algorithm family name (Plan M5-2-01 KD-5 — INDEPENDENT
    /// of the HDR identity: the two algorithms evolve without entangling
    /// each other's replay warnings).
    public static let mertensAlgorithmName = "mertens-exposure-fusion"
    /// The Mertens implementation version (a re-merge across a Mertens math
    /// change bumps THIS, never the HDR version).
    public static let mertensImplementationVersion = "1"
    /// The panorama algorithm family name (Plan M5-3-01 KD-8 — INDEPENDENT
    /// of the HDR/Mertens identities: the three algorithms evolve without
    /// entangling each other's replay warnings).
    public static let panoAlgorithmName = "spherical-feature-panorama"
    /// The panorama implementation version (a re-merge across a pano math
    /// change bumps THIS, never the HDR or Mertens versions).
    public static let panoImplementationVersion = "1"

    // MARK: - Source hashing (the drift anchor)

    /// FNV-1a over the file BYTES, streamed in 1 MiB chunks (a 200 MB RAW
    /// never loads whole). nil = unreadable.
    public static func fileHash(_ url: URL) -> UInt64? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var hash = StableHash.fnvOffsetBasis
        let bufferSize = 1 << 20
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while true {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 { return nil } // stream error
            if read == 0 { break }
            hash = StableHash.combine(hash, UnsafeRawBufferPointer(
                start: buffer, count: read))
        }
        return hash
    }

    /// The per-source drift verdict: recompute each source's stableHash and
    /// compare — `true` entries mark CHANGED (or missing) sources.
    public static func drift(
        provenance: SidecarProvenance, sessionRoot: URL
    ) -> [Bool] {
        provenance.sources.map { source in
            guard let hash = fileHash(sessionRoot.appendingPathComponent(source.relPath))
            else { return true }
            return hash != source.stableHash
        }
    }

    /// The replay request's parameters: the recorded algorithm params
    /// verbatim (the service re-merges with EXACTLY these).
    public static func replayParams(
        _ provenance: SidecarProvenance
    ) -> StackMergeService.MergeParams {
        provenance.algorithm.params
    }

    // MARK: - Equivalence (the reuse-prompt face)

    /// The provenance identity hash — FNV-1a over the CANONICAL
    /// (sortedKeys) JSON of {kind, algorithm.name, implementationVersion,
    /// params, sources[relPath+hash+EV]}. Deliberately EXCLUDES createdAt/
    /// appVersion (the same merge re-run a day later is the SAME identity).
    public static func provenanceHash(_ provenance: SidecarProvenance) -> UInt64 {
        // Codable tuples do not exist — project into mirror structs.
        struct IdentitySource: Codable {
            var relPath: String
            var hash: UInt64
            var ev: Double
        }
        struct IdentityRoot: Codable {
            var kind: String
            var name: String
            var version: String
            var params: StackMergeService.MergeParams
            var sources: [IdentitySource]
        }
        let root = IdentityRoot(
            kind: provenance.kind.rawValue,
            name: provenance.algorithm.name,
            version: provenance.algorithm.implementationVersion,
            params: provenance.algorithm.params,
            sources: provenance.sources.map {
                IdentitySource(relPath: $0.relPath, hash: $0.stableHash, ev: $0.exposureEV)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(root) else { return 0 }
        return StableHash.hash(data)
    }

    /// Two provenances describe the SAME merge (the reuse prompt's
    /// predicate — byte-identical identity, timestamps aside).
    public static func equivalentProvenance(
        _ a: SidecarProvenance, _ b: SidecarProvenance
    ) -> Bool {
        provenanceHash(a) == provenanceHash(b)
            && a.sources.count == b.sources.count
    }
}
