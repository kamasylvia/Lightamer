import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// LibraryMetadataWriter (R1 mark-chain repair, 2026-10-20) — the LIBRARY-face
// metadata write (rating / color label / flag) for the mark commands.
//
// ROOT CAUSE it closes: the mark commands (menu + keyboard, NSMenuBridge →
// LightamerShell.applyRating/applyColor/applyFlag) routed ONLY through the
// SESSION-face MetadataController — configured solely on the legacy session
// open path and fed by the session browser's selection. In the default
// library workspace both inputs are permanently empty, so every mark was a
// silent no-op (UI / sidecar / DB triple-zero; pre-flip same = pre-existing
// defect, P1 acceptance 挂账 #1).
//
// Write order mirrors the session truth discipline (OQ-3: the `.lra` is the
// truth, the DB row is the projection):
//   1. compose each target's sidecar from the DISK truth (existing document
//      = an inout round-trip that preserves every edit field; pristine target
//      = the MetadataService self-consistent mint — decoder stamp 0/0, seeded
//      defaults, empty history, current process generation) and write it
//      atomically (the BatchSidecarWriter.writeAtomic shape: pretty +
//      sortedKeys JSON → same-directory tmp sibling → replaceItemAt/moveItem,
//      journaled so any reconciler swallows the self-write event);
//   2. ONE write batch updating the library projection columns for the
//      applied group (LibraryStore.setMetadataMarks).
// An existing-but-unreadable sidecar is SKIPPED, never clobbered (SC#2 —
// the same posture as MetadataService 段1).
// ─────────────────────────────────────────────────────────────────────────────

public struct LibraryMetadataEdit: Sendable {
    public let imageID: Int64
    /// The image's RESOLVED source URL (the ImageLinker face — the sidecar
    /// rides beside it, `LightamerSidecar.sidecarURL(for:)`).
    public let imageURL: URL
    public let rating: Int64?
    public let colorLabel: Int64?
    public let flag: Int64?

    public init(
        imageID: Int64, imageURL: URL,
        rating: Int64?, colorLabel: Int64?, flag: Int64?
    ) {
        self.imageID = imageID
        self.imageURL = imageURL
        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
    }
}

public struct LibraryMetadataOutcome: Sendable, Equatable {
    public var appliedImageIDs: [Int64]
    public var skippedImageIDs: [Int64]
}

/// One image's mark row for the projection batch — the POST-WRITE TRUTH
/// trio (derived from the composed document, not the raw edit: a color
/// mark with a nil rating must project the SURVIVING rating, mirroring the
/// sidecar the grid badge reads).
public struct LibraryMetadataMark: Sendable {
    public let imageID: Int64
    public let rating: Int64?
    public let colorLabel: Int64?
    public let flag: Int64?

    public init(
        imageID: Int64, rating: Int64?, colorLabel: Int64?, flag: Int64?
    ) {
        self.imageID = imageID
        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
    }

    init(imageID: Int64, document: LightamerSidecar) {
        self.init(
            imageID: imageID,
            rating: document.rating.map(Int64.init),
            colorLabel: document.colorLabel.map(Int64.init),
            flag: document.flag.map(Int64.init))
    }
}

public enum LibraryMetadataWriter {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "library-metadata")

    /// Compose-and-write the metadata-only sidecar per target, then one
    /// projection batch for the applied group. Throws only when the
    /// projection batch itself fails (the sidecars already landed — a retry
    /// is idempotent); per-target compose failures are SKIPS, not throws.
    public static func apply(
        edits: [LibraryMetadataEdit],
        store: LibraryStore,
        seed: [ModuleInstance],
        journal: SidecarWriteJournal = .shared
    ) async throws -> LibraryMetadataOutcome {
        guard !edits.isEmpty else { return LibraryMetadataOutcome(appliedImageIDs: [], skippedImageIDs: []) }

        var applied: [Int64] = []
        var skipped: [Int64] = []
        var marks: [LibraryMetadataMark] = []
        applied.reserveCapacity(edits.count)

        for edit in edits {
            do {
                let document = try composeDocument(
                    for: edit, seed: seed)
                try writeAtomic(document, imageURL: edit.imageURL, journal: journal)
                applied.append(edit.imageID)
                // The projection row mirrors the POST-WRITE truth (the
                // composed document — a nil component of the edit means
                // "leave untouched", so the surviving value projects).
                marks.append(
                    LibraryMetadataMark(imageID: edit.imageID, document: document))
            } catch {
                skipped.append(edit.imageID)
                Self.logger.warning(
                    "library metadata write skipped image \(edit.imageID): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !applied.isEmpty else {
            return LibraryMetadataOutcome(
                appliedImageIDs: applied, skippedImageIDs: skipped)
        }

        // The projection batch: per-id trio values (the sidecars for this
        // exact group already landed — a failure here leaves the truth
        // right and the projection stale, logged by the store).
        try await store.setMetadataMarks(marks)

        return LibraryMetadataOutcome(
            appliedImageIDs: applied, skippedImageIDs: skipped)
    }

    // MARK: - The compose leg (the MetadataService.apply 段1 shape)

    /// Disk truth first: an existing sidecar round-trips INOUT (every edit
    /// field preserved — only the trio mutates); a pristine target mints the
    /// self-consistent metadata document. Unreadable existing bytes throw
    /// (the caller skips — never clobber).
    private static func composeDocument(
        for edit: LibraryMetadataEdit, seed: [ModuleInstance]
    ) throws -> LightamerSidecar {
        let sidecarURL = LightamerSidecar.sidecarURL(for: edit.imageURL)
        let decoder = JSONDecoder()
        var document: LightamerSidecar
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            guard let data = try? Data(contentsOf: sidecarURL),
                let decoded = try? decoder.decode(
                    LightamerSidecar.self, from: data)
            else {
                throw AppError.sidecarWriteFailed(sidecarURL.path)
            }
            document = decoded
        } else {
            let history = HistoryStack()
            document = LightamerSidecar(
                imageID: UUID(),
                decoderVersionUsed: "unknown-metadata",
                decodeParamsHash: 0,
                instances: seed,
                history: history,
                historyHash: HistoryHash.hash(
                    stack: history, decodeParamsHash: 0),
                appVersion: LightamerSidecar.currentAppVersion,
                layerStack: nil,
                // M6-2-01 T4 (KD-7 ⑤b) parity: a metadata mint stamps the
                // current process generation (the same rule the session
                // face's MetadataService mints under).
                process: .current)
        }
        // A nil component means "leave untouched" — only the NON-NIL mark
        // components mutate the document (a color mark must not clear the
        // surviving rating; the SC#2 round-trip preserves every field).
        if let rating = edit.rating { document.rating = Int(rating) }
        if let colorLabel = edit.colorLabel { document.colorLabel = Int(colorLabel) }
        if let flag = edit.flag { document.flag = Int(flag) }
        return document
    }

    // MARK: - The atomic write (the BatchSidecarWriter.writeAtomic shape)

    /// Encode → same-directory tmp sibling → `replaceItemAt`/`moveItem`.
    /// The tmp is removed on the failure path (never leave debris); the
    /// promotion is journaled so a reconciler swallows the FSEvents event
    /// it just caused.
    private static func writeAtomic(
        _ document: LightamerSidecar, imageURL: URL, journal: SidecarWriteJournal
    ) throws {
        let destination = LightamerSidecar.sidecarURL(for: imageURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw AppError.sidecarWriteFailed(destination.path)
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            // Plain write to the SAME-DIRECTORY tmp — the promotion below
            // is the atomic step (L009: never a cross-volume rename).
            try data.write(to: tmp)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp) // never leave debris
            throw AppError.sidecarWriteFailed(destination.path)
        }
        journal.record(path: destination.path)
    }
}
