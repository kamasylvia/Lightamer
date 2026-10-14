import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ImportService (Plan M2-2-2 T3) — the three-transport folder import
// (M2LIB-07 ①②③⑤) over the scan→plan→per-file-executor skeleton (KD-2):
//
//   makePlan  — recursive scan + ImportFilter gate (the AC①②③ mouth) → an
//               ImportPlan carrying the accepted items + typed rejections.
//   importFolder — per-file executor loop: file placement FIRST, the images
//               row ONLY after placement success (KD-2's no-ghost-rows
//               invariant: a crash at worst loses an already-copied file's
//               row — the next import's duplicate detection skips it — and
//               never leaves a row without bytes). Batch tail = one FTS
//               rebuild; EXIF materialization rides the M2-2-1 ExifSearch
//               Indexer seam (KD-6: zero re-invented key reading).
//
// TRANSPORTS (M2LIB-07, the需求-pinned constraints):
//   ① move  — same volume: rename first; cross volume: copy → verify →
//             remove source. THE RED LINE: the source is NEVER removed
//             before verification passes (the injected-strategy test pins
//             the source file surviving a failed verify).
//   ② copy  — per-file verify (size + FNV-1a 64 content hash, StableHash);
//             duplicate detection: identical bytes already at the target →
//             skip count; same name different bytes → `<stem>-1` avoidance.
//   ③ link  — no bytes move: the row carries kind1 (volume-relative +
//             volume UUID) or kind2 (absolute) via ImageLinker.record; the
//             `.lra` stays at the origin (⑤).
//   ⑤ sidecars — move/copy migrate the sibling `.lra`/`.xmp` with the
//             photo; a sidecar failure fails the WHOLE file and rolls back
//             the already-placed bytes (move renames back; copy deletes).
//
// Progress = an immutable ImportProgress snapshot pushed through the
// CatalogRebuilder-style setProgressHandler seam; cancel = a per-file
// checkpoint (the actor processes `cancel()` between file awaits).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed import failure face (failures COUNT per file via the outcome;
/// these carry the cause into that count and into tests).
public enum ImportError: Error, Equatable, Sendable {
    /// Placement verification failed — for move legs the source is, by
    /// the red line, untouched.
    case verifyFailed(source: String, destination: String)
    /// The `.lra`/`.xmp` sidecar migration failed (the whole file failed;
    /// placed bytes were rolled back).
    case sidecarMigrationFailed(detail: String)
    /// `importFile` (Plan M2-10-06 KD-4) was handed a file that does not
    /// live under the project's `Media/` directory — the in-place adopt
    /// only registers ALREADY-PLACED bytes (the enhance-copy writer does
    /// the placement; this twin never moves bytes).
    case adoptTargetOutsideMedia(path: String)
}

/// The KD-4 progress snapshot (a plain value — the UI layer renders it,
/// tests assert its monotonicity).
public struct ImportProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case scanning
        case importing
        case completed
        case cancelled
    }

    public var phase: Phase
    public var total: Int
    public var processed: Int
    public var failed: Int
    public var skippedDuplicates: Int
    public var bytesCopied: Int64
    /// The M4-1-02 T5 category-mask account (OQ-7): candidates rejected
    /// because their FAMILY (raw/tiff) was switched off in the selector —
    /// distinct from the whitelist rejections. Additive, default 0 = the
    /// pre-M4-1 snapshot shape byte-identical.
    public var excludedType: Int

    public init(
        phase: Phase, total: Int, processed: Int = 0, failed: Int = 0,
        skippedDuplicates: Int = 0, bytesCopied: Int64 = 0,
        excludedType: Int = 0
    ) {
        self.phase = phase
        self.total = total
        self.processed = processed
        self.failed = failed
        self.skippedDuplicates = skippedDuplicates
        self.bytesCopied = bytesCopied
        self.excludedType = excludedType
    }
}

/// The scan output: accepted items (each with its `Media/`-relative
/// destination path) + the typed rejections for the progress face.
public struct ImportPlan: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        /// The accepted source file (outside the project).
        public let source: URL
        /// Destination path under `Media/` INCLUDING the source-folder
        /// name segment (KD-3: `"<folderName>/<source-relative subtree>"`).
        public let mediaRelativePath: String

        public init(source: URL, mediaRelativePath: String) {
            self.source = source
            self.mediaRelativePath = mediaRelativePath
        }
    }

    public let sourceFolder: URL
    public let projectDirectory: URL
    public let mode: ImportMode
    public let items: [Item]
    public let rejected: [ImportRejection]

    /// The M4-1-02 T5 category-mask account: the `.excludedType` share of
    /// the rejections (the progress panel's typed 分账 vs the whitelist
    /// count — the upstream excluded_type/unsupported twin).
    public var excludedTypeCount: Int {
        rejected.filter { $0.reason == .excludedType }.count
    }

    public init(
        sourceFolder: URL, projectDirectory: URL, mode: ImportMode,
        items: [Item], rejected: [ImportRejection]
    ) {
        self.sourceFolder = sourceFolder
        self.projectDirectory = projectDirectory
        self.mode = mode
        self.items = items
        self.rejected = rejected
    }
}

/// The run summary (KD-2's outcome face). The M6-4-01 KD-6 tail counts are
/// additive with explicit defaults — every pre-stacks construction site
/// compiles and compares byte-identical (the M4 zero-drift guarantee; the
/// counts are TEST-consumed in v1, zero UI face).
public struct ImportOutcome: Sendable, Equatable {
    public var imported: Int
    public var failed: Int
    public var skippedDuplicates: Int
    public var cancelled: Bool
    /// Merge products whose source set fully resolved → stacks landed
    /// (stackWith, collapsed, product = cover).
    public var mergeStacksCreated: Int
    /// Merge-kind products whose source resolution failed or stayed
    /// ambiguous → the WHOLE group skipped, zero half-stacks (KD-6).
    public var mergeStacksSkipped: Int

    public init(
        imported: Int = 0, failed: Int = 0, skippedDuplicates: Int = 0,
        cancelled: Bool = false,
        mergeStacksCreated: Int = 0, mergeStacksSkipped: Int = 0
    ) {
        self.imported = imported
        self.failed = failed
        self.skippedDuplicates = skippedDuplicates
        self.cancelled = cancelled
        self.mergeStacksCreated = mergeStacksCreated
        self.mergeStacksSkipped = mergeStacksSkipped
    }
}

public actor ImportService {

    /// Placement verification: `(source, destination) -> verified`. The
    /// red-pin tests inject a permanently-failing strategy; the default is
    /// size equality + FNV-1a 64 content-hash equality (StableHash).
    public typealias VerifyStrategy = @Sendable (URL, URL) async throws -> Bool
    /// Volume identity seam: forces cross-volume legs in tests without a
    /// second physical disk; the default is `ImageLinker.volumeUUID`.
    public typealias UUIDProbe = @Sendable (URL) -> String?

    /// The sidecar extensions migrated with each accepted photo (⑤).
    static let sidecarExtensions = ["lra", "xmp"]

    private let projectStore: ProjectFileStore
    private let libraryStore: LibraryStore
    private let indexer: ExifSearchIndexer

    private var progressHandler: (@Sendable (ImportProgress) async -> Void)?
    private var verifyStrategy: VerifyStrategy?
    private var uuidProbe: UUIDProbe?
    private var cancelRequested = false
    /// The batch's landed rows `(rowid, imagePath)` in landing order — the
    /// import-seam auto-stack's first-choice match source (KD-6: the batch
    /// map wins, the full-library query is the fallback).
    private var batchImportedRows: [(id: Int64, imagePath: String)] = []

    public init(store: ProjectFileStore) {
        self.projectStore = store
        self.libraryStore = LibraryStore(store: store)
        self.indexer = ExifSearchIndexer(store: store)
    }

    // MARK: - Seams (the CatalogRebuilder setProgressHandler pattern)

    public func setProgressHandler(
        _ handler: (@Sendable (ImportProgress) async -> Void)?
    ) {
        progressHandler = handler
    }

    public func setVerifyStrategy(_ strategy: VerifyStrategy?) {
        verifyStrategy = strategy
    }

    public func setUUIDProbe(_ probe: UUIDProbe?) {
        uuidProbe = probe
    }

    /// Cancel at the NEXT per-file checkpoint (the actor interleaves this
    /// between file awaits — no file is ever torn mid-copy).
    public func cancel() {
        cancelRequested = true
    }

    // MARK: - Scan → plan

    /// Recursively scan `sourceFolder`, gate through ImportFilter, and
    /// shape the plan (KD-2 step 1). Hidden/dot directories are NOT
    /// skipped by the scanner — the FILTER is the single gate (the Alcedo
    /// lesson: filter everything, reject typed).
    public func makePlan(
        sourceFolder: URL, projectDirectory: URL, mode: ImportMode,
        whitelist: Set<String> = LibrarySchema.defaultRawExtensions,
        categories: ImportCategory = .all
    ) async throws -> ImportPlan {
        cancelRequested = false
        await emit(ImportProgress(phase: .scanning, total: 0))
        // The scan pairs each file with its RELATIVE components directly
        // (spelling-immune — see recursiveFiles: the manager resolves the
        // root's firmlink to /private/var while the caller's URL keeps the
        // /var spelling, so prefix-cutting the enumerator's absolute paths
        // is unsound by construction).
        let scanned = Self.recursiveFiles(in: sourceFolder)
        let selection = ImportFilter.select(
            scanned.map(\.url), whitelist: whitelist, categories: categories)
        let folderName = sourceFolder.lastPathComponent
        let relatives = Dictionary(
            uniqueKeysWithValues: scanned.map { ($0.url.path, $0.relative) })
        let items = selection.accepted.compactMap { accepted in
            relatives[accepted.path].map { relative in
                ImportPlan.Item(
                    source: accepted,
                    mediaRelativePath: folderName + "/" + relative)
            }
        }
        let plan = ImportPlan(
            sourceFolder: sourceFolder, projectDirectory: projectDirectory,
            mode: mode, items: items, rejected: selection.rejected)
        await emit(ImportProgress(
            phase: .scanning, total: items.count,
            processed: 0, failed: 0,
            skippedDuplicates: 0, bytesCopied: 0,
            excludedType: plan.excludedTypeCount))
        return plan
    }

    /// Recursively collect `(url, root-relative path)` pairs, stable order
    /// (relative-path sorted). The relative path accumulates from
    /// lastPathComponents during the descent — NEVER by prefix-cutting the
    /// manager's absolute spellings (which resolve the root's firmlink to
    /// /private/var while the caller's URL may keep /var). Dot-hidden
    /// entries ride in — the filter rejects them typed (AC②'s hidden leg
    /// needs the counts). M4-1-02 T5: public so the import selector's
    /// count fold reuses THE scan (the dialog grows no second walker).
    public nonisolated static func recursiveFiles(
        in root: URL
    ) -> [(url: URL, relative: String)] {
        var results: [(url: URL, relative: String)] = []
        let fm = FileManager.default
        func walk(_ directory: URL, relative: String) {
            let children = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [])) ?? []
            for child in children
            where child.lastPathComponent != "." && child.lastPathComponent != ".." {
                let childRelative = relative.isEmpty
                    ? child.lastPathComponent
                    : relative + "/" + child.lastPathComponent
                let isDirectory = (try? child.resourceValues(
                    forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    walk(child, relative: childRelative)
                } else {
                    results.append((child, childRelative))
                }
            }
        }
        walk(root, relative: "")
        return results.sorted { $0.relative < $1.relative }
    }

    // MARK: - Execute (KD-2 steps 2-3)

    /// Run the plan: per-file executor with a cancel checkpoint per file,
    /// one FTS rebuild at the batch tail (only when rows were written).
    public func importFolder(_ plan: ImportPlan) async throws -> ImportOutcome {
        cancelRequested = false
        batchImportedRows = []
        var progress = ImportProgress(
            phase: .importing, total: plan.items.count,
            excludedType: plan.excludedTypeCount)
        await emit(progress)
        var outcome = ImportOutcome()
        var wroteAnyRow = false

        for item in plan.items {
            // The per-file cancel checkpoint: everything committed so far
            // stays (rows == placed files — no ghost rows by construction).
            if cancelRequested {
                outcome.cancelled = true
                progress.phase = .cancelled
                await emit(progress)
                break
            }
            do {
                let result: StepResult
                switch plan.mode {
                case .move:
                    result = try await executeMove(
                        item, projectDirectory: plan.projectDirectory)
                case .copy:
                    result = try await executeCopy(
                        item, projectDirectory: plan.projectDirectory)
                case .link:
                    result = try await executeLink(
                        item, projectDirectory: plan.projectDirectory)
                }
                switch result {
                case .imported:
                    outcome.imported += 1
                    wroteAnyRow = true
                case .duplicateSkipped:
                    outcome.skippedDuplicates += 1
                    progress.skippedDuplicates = outcome.skippedDuplicates
                }
            } catch {
                outcome.failed += 1
                progress.failed += 1
            }
            progress.processed += 1
            await emit(progress)
        }

        if wroteAnyRow {
            try await indexer.rebuildFTS()
            // M6-4-01 (KD-6, OQ-4): the import-batch completion seam —
            // merge products whose `.lra` provenance carries a merge-kind
            // kind AND whose sources all resolve stack up right here
            // (product = cover, collapsed). Link-mode imports never join:
            // their `.lra` stayed at the origin (S1), so the sidecar probe
            // below never fires for them.
            let account = try await autoStackMergeProducts(
                batchRows: batchImportedRows,
                folderName: plan.sourceFolder.lastPathComponent)
            outcome.mergeStacksCreated = account.created
            outcome.mergeStacksSkipped = account.skipped
        }
        if !outcome.cancelled {
            progress.phase = .completed
            await emit(progress)
        }
        return outcome
    }

    private enum StepResult { case imported, duplicateSkipped }

    /// The per-file executor outcome (imported vs duplicate-skipped).
    private func executeCopy(
        _ item: ImportPlan.Item, projectDirectory: URL
    ) async throws -> StepResult {
        let destination = mediaDestination(of: item, projectDirectory: projectDirectory)
        let finalDestination: URL
        if FileManager.default.fileExists(atPath: destination.path) {
            if try await Self.filesEquivalent(
                source: item.source, destination: destination,
                strategy: effectiveVerify) {
                return .duplicateSkipped // identical bytes already placed
            }
            finalDestination = try Self.avoidingDestination(for: destination)
        } else {
            finalDestination = destination
        }
        try FileManager.default.createDirectory(
            at: finalDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: item.source, to: finalDestination)
        do {
            try await verifyPlacement(source: item.source, destination: finalDestination)
            try migrateSidecars(
                of: item.source, to: finalDestination,
                transport: .copy, rollbackRoot: finalDestination)
        } catch {
            // Rollback: the placed bytes leave; the row is never written.
            rollbackPlaced(destination: finalDestination, sidecarsOf: item.source)
            throw error
        }
        try await writeRow(destination: finalDestination, item: item)
        return .imported
    }

    /// The RED LINE lives in the cross-volume leg: `removeItem` on the
    /// source runs ONLY after `verifyPlacement` passed.
    private func executeMove(
        _ item: ImportPlan.Item, projectDirectory: URL
    ) async throws -> StepResult {
        let destination = mediaDestination(of: item, projectDirectory: projectDirectory)
        let finalDestination: URL
        if FileManager.default.fileExists(atPath: destination.path) {
            if try await Self.filesEquivalent(
                source: item.source, destination: destination,
                strategy: effectiveVerify) {
                return .duplicateSkipped // identical bytes placed; source stays
            }
            finalDestination = try Self.avoidingDestination(for: destination)
        } else {
            finalDestination = destination
        }
        try FileManager.default.createDirectory(
            at: finalDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        if await sameVolume(item.source, projectDirectory) {
            // Same volume: rename first (bytes never duplicated).
            try FileManager.default.moveItem(at: item.source, to: finalDestination)
            do {
                try migrateSidecars(
                    of: item.source, to: finalDestination,
                    transport: .rename, rollbackRoot: finalDestination)
            } catch {
                // Rollback the rename: the photo goes home, sidecars too.
                try? FileManager.default.moveItem(
                    at: finalDestination, to: item.source)
                rollbackRenamedSidecars(of: item.source, destination: finalDestination)
                throw error
            }
        } else {
            // Cross volume: copy → verify → remove. Any failure before
            // verify leaves the source UNTOUCHED (M2LIB-07① red line).
            try FileManager.default.copyItem(at: item.source, to: finalDestination)
            do {
                try await verifyPlacement(source: item.source, destination: finalDestination)
                try migrateSidecars(
                    of: item.source, to: finalDestination,
                    transport: .copy, rollbackRoot: finalDestination)
            } catch {
                rollbackPlaced(destination: finalDestination, sidecarsOf: item.source)
                throw error
            }
            // Verified — NOW the source (and its sidecars) may leave.
            try? FileManager.default.removeItem(at: item.source)
            for ext in Self.sidecarExtensions {
                try? FileManager.default.removeItem(
                    at: Self.sidecarURL(for: item.source, ext: ext))
            }
        }
        try await writeRow(destination: finalDestination, item: item)
        return .imported
    }

    /// Link: no bytes move — the row carries the ImageLinker record; the
    /// `.lra` stays at the origin (⑤). Always writes a row (there is no
    /// placement to duplicate). The row joins the batch map (harmless — the
    /// auto-stack seam's sidecar probe can never fire for a link row, S1).
    private func executeLink(
        _ item: ImportPlan.Item, projectDirectory: URL
    ) async throws -> StepResult {
        let record = ImageLinker.record(
            for: item.source, projectDirectory: projectDirectory,
            uuidProbe: uuidProbe)
        let rowID = try await insertRow(
            imagePath: record.imagePath, pathKind: record.pathKind,
            volumeUUID: record.volumeUUID, file: item.source)
        batchImportedRows.append(
            (id: rowID, imagePath: record.imagePath))
        return .imported
    }

    // MARK: - Steps (placement / sidecars / rows)

    private var effectiveVerify: VerifyStrategy {
        verifyStrategy ?? { source, destination in
            Self.defaultVerify(source: source, destination: destination)
        }
    }

    private func verifyPlacement(source: URL, destination: URL) async throws {
        let verified = try await effectiveVerify(source, destination)
        guard verified else {
            throw ImportError.verifyFailed(
                source: source.path, destination: destination.path)
        }
    }

    /// The default verify: size equality + FNV-1a 64 content-hash equality
    /// (StableHash — the same face the App-side project mover reuses).
    public nonisolated static func defaultVerify(source: URL, destination: URL) -> Bool {
        guard let sourceSize = fileSize(source), let destinationSize = fileSize(destination),
              sourceSize == destinationSize else { return false }
        guard let sourceData = try? Data(contentsOf: source),
              let destinationData = try? Data(contentsOf: destination) else { return false }
        return StableHash.hash(sourceData) == StableHash.hash(destinationData)
    }

    private nonisolated static func fileSize(_ url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64
    }

    /// Duplicate detection equivalence (same hash face as verify).
    private static func filesEquivalent(
        source: URL, destination: URL, strategy: VerifyStrategy
    ) async throws -> Bool {
        try await strategy(source, destination)
    }

    /// `<stem>-1`递增避让 for a taken destination (Phase 11 namer先例).
    nonisolated private static func avoidingDestination(for taken: URL) throws -> URL {
        let stem = taken.deletingPathExtension().lastPathComponent
        let ext = taken.pathExtension
        let directory = taken.deletingLastPathComponent()
        var index = 1
        while true {
            let candidate = directory.appendingPathComponent(
                "\(stem)-\(index).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    /// `<project>/Media/<item.mediaRelativePath>` (KD-3's落位形态).
    nonisolated private func mediaDestination(
        of item: ImportPlan.Item, projectDirectory: URL
    ) -> URL {
        projectDirectory
            .appendingPathComponent(LibrarySchema.mediaDirectoryName, isDirectory: true)
            .appendingPathComponent(item.mediaRelativePath)
    }

    /// The sibling sidecar URL (`<original full name>.<ext>` — the Phase 2
    /// `.lra` convention; `.xmp` rides the same shape).
    nonisolated private static func sidecarURL(for file: URL, ext: String) -> URL {
        URL(fileURLWithPath: file.path + "." + ext)
    }

    private enum SidecarTransport { case copy, rename }

    /// Migrate the existing sidecars with the photo (⑤). A failure throws
    /// (the caller rolls the whole file back); `rollbackRoot` names the
    /// placed photo destination for the rollback sweep.
    private func migrateSidecars(
        of source: URL, to destination: URL,
        transport: SidecarTransport, rollbackRoot: URL
    ) throws {
        var migrated: [URL] = []
        do {
            for ext in Self.sidecarExtensions {
                let sourceSidecar = Self.sidecarURL(for: source, ext: ext)
                guard FileManager.default.fileExists(atPath: sourceSidecar.path) else {
                    continue
                }
                let destinationSidecar = Self.sidecarURL(for: destination, ext: ext)
                switch transport {
                case .copy:
                    try FileManager.default.copyItem(
                        at: sourceSidecar, to: destinationSidecar)
                case .rename:
                    try FileManager.default.moveItem(
                        at: sourceSidecar, to: destinationSidecar)
                }
                migrated.append(destinationSidecar)
            }
        } catch {
            for placed in migrated {
                try? FileManager.default.removeItem(at: placed)
            }
            throw ImportError.sidecarMigrationFailed(
                detail: "sidecar migration failed for \(source.lastPathComponent): \(error)")
        }
    }

    /// Rollback for copy legs: the placed photo + any landed sidecars leave
    /// (the source is untouched by construction — copy never removes it).
    private func rollbackPlaced(destination: URL, sidecarsOf source: URL) {
        try? FileManager.default.removeItem(at: destination)
        for ext in Self.sidecarExtensions {
            try? FileManager.default.removeItem(
                at: Self.sidecarURL(for: destination, ext: ext))
        }
    }

    /// Rollback for the rename leg's sidecar failure: any RENAMED sidecar
    /// goes home (the photo itself is renamed back by the caller).
    private func rollbackRenamedSidecars(of source: URL, destination: URL) {
        for ext in Self.sidecarExtensions {
            let destinationSidecar = Self.sidecarURL(for: destination, ext: ext)
            if FileManager.default.fileExists(atPath: destinationSidecar.path) {
                try? FileManager.default.moveItem(
                    at: destinationSidecar,
                    to: Self.sidecarURL(for: source, ext: ext))
            }
        }
    }

    /// The images row — KD-2's invariant: only after placement success.
    /// kind0 + the project-relative `Media/...` path (move/copy); the
    /// EXIF materialization rides the M2-2-1 indexer seam (KD-6). The row
    /// joins the batch map (the auto-stack seam's first-choice source).
    private func writeRow(destination: URL, item: ImportPlan.Item) async throws {
        let rowID = try await insertRow(
            imagePath: LibrarySchema.mediaDirectoryName + "/" + item.mediaRelativePath,
            pathKind: .projectRelative, volumeUUID: nil, file: destination)
        batchImportedRows.append(
            (id: rowID,
             imagePath: LibrarySchema.mediaDirectoryName + "/"
                 + item.mediaRelativePath))
    }

    @discardableResult
    private func insertRow(
        imagePath: String, pathKind: LibrarySchema.PathKind,
        volumeUUID: String?, file: URL
    ) async throws -> Int64 {
        let rowID = try await libraryStore.insertImage(record: LibraryImageRecord(
            imagePath: imagePath,
            pathKind: pathKind,
            volumeUUID: volumeUUID,
            fileStem: file.deletingPathExtension().lastPathComponent,
            fileExt: file.pathExtension.lowercased(),
            filename: file.lastPathComponent,
            dir: file.deletingLastPathComponent().path))
        _ = try await indexer.fillMetadata(imageID: rowID, from: file)
        return rowID
    }

    private func sameVolume(_ a: URL, _ b: URL) async -> Bool {
        let probe = uuidProbe ?? ImageLinker.volumeUUID
        // Unknown identity on either side → conservative copy leg (the
        // safe direction for the red line: verify-then-delete).
        guard let aUUID = probe(a), let bUUID = probe(b) else { return false }
        return aUUID == bUUID
    }

    // MARK: - Single-file twin (Plan M2-10-06 KD-4)

    /// Register ONE file that is ALREADY placed under the project's
    /// `Media/` directory (the AI-enhance copy writer reserves + writes
    /// the bytes; this twin does the registration half of the per-file
    /// executor — the SAME `insertRow` internal the folder transports
    /// call, zero copy-paste):
    ///
    ///   1. the images row (kind0 project-relative) + EXIF backfill
    ///      (the indexer seam);
    ///   2. the optional album placement;
    ///   3. the optional `.lra` mint carrying the AI provenance — a
    ///      pristine document (empty history, own UUID imageID) written
    ///      ATOMICALLY through the SidecarStore flushNow path (the copy's
    ///      birth is a synchronous user action — it never waits for a
    ///      debounce). D-M2-10-CONTEXT-3: the copy is a NEW image — the
    ///      ORIGINAL's sidecar/version face is never touched.
    ///
    /// - Returns: the new images row id.
    @discardableResult
    public func importFile(
        at fileURL: URL,
        projectDirectory: URL,
        albumID: Int64? = nil,
        aiProvenance: SidecarAIProvenanceRecord? = nil
    ) async throws -> Int64 {
        let mediaRoot = projectDirectory
            .appendingPathComponent(LibrarySchema.mediaDirectoryName, isDirectory: true)
        let relative: String
        do {
            relative = try Self.mediaRelativePath(of: fileURL, under: mediaRoot)
        } catch {
            throw ImportError.adoptTargetOutsideMedia(path: fileURL.path)
        }
        let rowID = try await insertRow(
            imagePath: LibrarySchema.mediaDirectoryName + "/" + relative,
            pathKind: .projectRelative, volumeUUID: nil, file: fileURL)
        if let albumID {
            try await libraryStore.addImage(rowID, to: albumID)
        }
        if let aiProvenance {
            try await Self.mintProvenanceSidecar(
                for: fileURL, provenance: aiProvenance)
        }
        return rowID
    }

    /// The `Media/`-relative path of a placed file (its last path
    /// components below the media root). Throws when the file is not
    /// under the root (the typed adopt rejection).
    nonisolated private static func mediaRelativePath(
        of file: URL, under mediaRoot: URL
    ) throws -> String {
        let filePath = file.standardizedFileURL.path
        let rootPath = mediaRoot.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            throw ImportError.adoptTargetOutsideMedia(path: filePath)
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    /// The provenance `.lra` mint (KD-4): pristine document + the v8
    /// record, written atomically (SidecarStore flushNow semantics). The
    /// decode-hash seed is the neutral 0 — the document has no decode
    /// parameters of its own; the coordinator re-stamps the hash on the
    /// first real edit, and the drift anchor is self-consistent either
    /// way (it recomputes with the FILE's own seed).
    nonisolated private static func mintProvenanceSidecar(
        for fileURL: URL, provenance: SidecarAIProvenanceRecord
    ) async throws {
        let decodeHash = UInt64(0)
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: HistoryStack(),
            historyHash: HistoryHash.hash(
                stack: HistoryStack(), decodeParamsHash: decodeHash),
            aiProvenance: provenance,
            // M6-2-01 T4 (KD-7 ②): the AI copy is a NEW image — its birth
            // document stamps the current process generation (this build's
            // product never reads "born legacy").
            process: .current)
        let store = SidecarStore(
            destination: LightamerSidecar.sidecarURL(for: fileURL))
        await store.scheduleWrite(document)
        try await store.flushNow()
    }

    private func emit(_ progress: ImportProgress) async {
        await progressHandler?(progress)
    }

    // MARK: - Import-seam auto-stack (M6-4-01 KD-6; OQ-4; E1 matching)

    /// The merge-kind whitelist (EXACTLY the three HDR/pano merge kinds of
    /// `SidecarProvenance.Kind` — focus-stack / stack-average / stack-median
    /// / stack-sigma stay OUT; LightCraft's stack_with semantics only bind
    /// the HDR/pano domains). rawValues mirror the Kind enum's coding.
    static let mergeStackKinds: Set<String> = [
        "hdr-merge", "hdr-merge-mertens", "pano-merge",
    ]

    /// The batch-tail seam: for every landed destination, probe the sibling
    /// `.lra`, tolerant-decode the provenance, and stack the merge products
    /// whose sources all resolve (KD-6). Any unresolved/ambiguous source →
    /// the WHOLE group skipped (zero half-stacks). Products (or sources)
    /// already in a stack skip too — the import seam never merges existing
    /// stacks (the group-union semantics belong to the manual `group` face).
    private func autoStackMergeProducts(
        batchRows: [(id: Int64, imagePath: String)],
        folderName: String
    ) async throws -> (created: Int, skipped: Int) {
        var created = 0
        var skipped = 0
        let projectDirectory = await projectStore.fileURL.deletingLastPathComponent()
        for row in batchRows {
            // Only Media/-carrying (move/copy) rows can carry a migrated
            // sidecar; link rows' `.lra` stayed at the origin (S1).
            guard row.imagePath.hasPrefix(
                LibrarySchema.mediaDirectoryName + "/") else { continue }
            let destination = projectDirectory
                .appendingPathComponent(row.imagePath)
            let sidecarURL = URL(fileURLWithPath: destination.path + ".lra")
            guard FileManager.default.fileExists(atPath: sidecarURL.path),
                let data = try? Data(contentsOf: sidecarURL),
                let document = try? JSONDecoder().decode(
                    LightamerSidecar.self, from: data),
                let provenance = document.provenance,
                Self.mergeStackKinds.contains(provenance.kind.rawValue)
            else { continue }
            // The source resolution (E1's versioned matching rules).
            var sourceIDs: [Int64] = []
            var resolved = true
            for source in provenance.sources {
                if let id = try await resolveSourcePath(
                    relPath: source.relPath, folderName: folderName,
                    batchRows: batchRows) {
                    sourceIDs.append(id)
                } else {
                    resolved = false
                    break
                }
            }
            guard resolved, !sourceIDs.isEmpty else {
                skipped += 1
                continue
            }
            // The seam never merges existing stacks: product or any source
            // already stacked → skip (safe side, zero writes).
            let involved = [row.id] + sourceIDs
            var alreadyStacked = false
            for id in involved {
                if try await libraryStore.stackContaining(imageID: id) != nil {
                    alreadyStacked = true
                    break
                }
            }
            guard !alreadyStacked else {
                skipped += 1
                continue
            }
            if try await libraryStore.stackWith(
                productID: row.id, sourceIDs: sourceIDs) != nil {
                created += 1
            } else {
                // Below-2 union (a product with zero resolvable sources
                // cannot reach here — the guard above) — defensive skip.
                skipped += 1
            }
        }
        return (created, skipped)
    }

    /// E1's versioned matching rules (the DECISIONS clause carrier):
    ///   1. SUFFIX match (primary) — `image_path` ends with "/" + relPath;
    ///      the batch map wins, the full-library parameterized
    ///      `LIKE '%' || ? ESCAPE '\'` query is the fallback. relPath's
    ///      structural segments survive the import tree verbatim, so this
    ///      covers any folderName prefix and out-of-root source names.
    ///   2. MULTIPLE suffix hits (same-name subtree re-import) → the
    ///      batch's folderName candidate disambiguates:
    ///      exact `Media/<folderName>/<relPath>` — a unique hit wins,
    ///      still ambiguous = fail.
    ///   3. ZERO suffix hits → the folderName exact candidate (batch map,
    ///      then the library) → the last-segment FILE-STEM unique hit.
    ///   4. Any failure / unresolved ambiguity → nil (the caller skips the
    ///      whole group — mergeStacksSkipped).
    private func resolveSourcePath(
        relPath: String, folderName: String,
        batchRows: [(id: Int64, imagePath: String)]
    ) async throws -> Int64? {
        let suffix = "/" + relPath
        // 1. Suffix match, batch map first.
        var candidates = batchRows.filter { $0.imagePath.hasSuffix(suffix) }
        if candidates.isEmpty {
            candidates = try await libraryRows(
                "SELECT id, image_path FROM images"
                    + " WHERE image_path LIKE '%' || ? ESCAPE '\\'",
                    binds: [.text(Self.likeEscaped(suffix))])
        }
        if candidates.count == 1 { return candidates[0].id }
        if candidates.count > 1 {
            // 2. folderName candidate disambiguation.
            let exact = Self.folderNameCandidate(
                folderName: folderName, relPath: relPath)
            let exactHits = candidates.filter { $0.imagePath == exact }
            return exactHits.count == 1 ? exactHits[0].id : nil
        }
        // 3. Zero suffix hits: the folderName exact candidate (batch, then
        // the library), then the unique file-stem fallback.
        let exact = Self.folderNameCandidate(
            folderName: folderName, relPath: relPath)
        let batchExact = batchRows.filter { $0.imagePath == exact }
        if batchExact.count == 1 { return batchExact[0].id }
        if batchExact.isEmpty {
            let libraryExact = try await libraryRows(
                "SELECT id, image_path FROM images WHERE image_path = ?",
                binds: [.text(exact)])
            if libraryExact.count == 1 { return libraryExact[0].id }
        }
        let stem = relPath.split(separator: "/").last.map(String.init) ?? relPath
        let stemNoExt = stem.contains("/")
            ? stem
            : (stem as NSString).deletingPathExtension
        guard !stemNoExt.isEmpty else { return nil }
        let stemHits = try await libraryRows(
            "SELECT id, image_path FROM images WHERE file_stem = ?",
            binds: [.text(stemNoExt)])
        return stemHits.count == 1 ? stemHits[0].id : nil
    }

    /// `Media/<folderName>/<relPath>` — the batch's unconditional landing
    /// shape (makePlan folderName prefix + writeRow's Media/ prefix).
    nonisolated private static func folderNameCandidate(
        folderName: String, relPath: String
    ) -> String {
        LibrarySchema.mediaDirectoryName + "/" + folderName + "/" + relPath
    }

    /// LIKE-pattern escaping (the DECISIONS versioned clause): the escape
    /// character is `\`; it escapes ITSELF plus the two pattern metachars
    /// (`%`/`_`) — a relPath carrying wildcards matches literally.
    nonisolated private static func likeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func libraryRows(
        _ sql: String, binds: [FilterSQLBind]
    ) async throws -> [(id: Int64, imagePath: String)] {
        try await projectStore.withHandle { handle in
            let statement = try handle.prepare(sql)
            try FilterSQL.apply(binds, to: statement)
            var rows: [(id: Int64, imagePath: String)] = []
            while try statement.step() {
                if let id = statement.columnInt(0),
                    let path = statement.columnText(1) {
                    rows.append((id: id, imagePath: path))
                }
            }
            return rows
        }
    }
}
