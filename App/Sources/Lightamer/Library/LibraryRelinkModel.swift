import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryRelinkModel (Plan M2-3-2 T4, KD-4 / M2LIB-07③) — the Inspector's
// batch-relink face over the M2-2-2 `ImageLinker` public surface (zero Core
// changes):
//
//   • CLASSIFICATION — each stale row resolves through
//     `ImageLinker.resolve` into its typed two-form stale reason:
//     `pathMissing` (a concrete path, file gone) vs `volumeAbsent` (no
//     mounted volume carries the recorded UUID). The sheet renders the two
//     groups separately — "know WHY it broke".
//   • ORCHESTRATION — the batch loop is APP-LAYER (the plan's KD-4 ruling:
//     the controller has no relink face and Core stays frozen). Per row:
//     `ImageLinker.relinkRecord` rebuilds kind/uuid/path against the picked
//     source directory (file matched by NAME), the record hands to the
//     injected persistence leg, and a post-relink resolve decides relived
//     vs stillStale — a failing row never blocks the rest.
//   • PROGRESS — one BackgroundTaskHandle registration per batch (the P1
//     protocol's second leg), monotonic clamped like the import leg;
//     cancellation stops the loop and counts the remainder `cancelled`.
//
// THE PERSISTENCE GAP (execution finding — see the persistLeg note below):
// the Core write face for the path carrier does not exist publicly; the
// leg is injected and the production run stays gated until it lands.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class LibraryRelinkModel {

    /// The batch outcome's three-way classification (KD-4's 完成分类计数).
    struct BatchResult: Equatable {
        var relived = 0
        var stillStale = 0
        var cancelled = 0

        var total: Int { relived + stillStale + cancelled }
    }

    /// The two stale sections the sheet renders (the typed two-form).
    struct Classification: Equatable {
        var pathMissing: [LibraryImageRow] = []
        var volumeAbsent: [LibraryImageRow] = []

        var staleCount: Int { pathMissing.count + volumeAbsent.count }
    }

    /// The record `ImageLinker.relinkRecord` returns (the rebuild face).
    typealias RelinkRecord = (
        imagePath: String,
        pathKind: LibrarySchema.PathKind,
        volumeUUID: String?
    )

    /// The persistence seam (the default = the real store write; tests
    /// inject a recorder). Throws = the row stays stale, the batch goes on.
    typealias PersistLeg = (Int64, RelinkRecord) async throws -> Void

    /// The test seam for the volume probe (the controller's twin).
    var uuidProbe: (@Sendable (URL) -> String?)?

    /// The persistence seam. THE CORE-FACE GAP (execution finding, D-note):
    /// the public Core surface carries the relink RECORD face
    /// (`ImageLinker.relinkRecord`) but no public WRITE face for the
    /// images row's path carrier — `ProjectFileStore.withWriteBatch` is
    /// Core-internal and `LightamerCore/` is frozen THIS plan (the AC#9
    /// red line). The leg is therefore INJECTED: the tests drive the real
    /// store write through the testable import; the production sheet keeps
    /// the run gated (the honest empty-state discipline) until the Core
    /// write face lands (the M2LIB-07③ completion note).
    var persistLeg: PersistLeg?

    /// Whether the batch can actually persist (the sheet's run gate).
    var canPersist: Bool { persistLeg != nil }

    private(set) var result: BatchResult?
    private(set) var isRunning = false
    /// The cancel flag (the handle's cancel route sets it; the loop checks
    /// between rows).
    private var cancelRequested = false

    init() {}

    // MARK: - Classification (the two stale forms)

    /// Classify rows into the sheet's two sections (plus the healthy rows
    /// the sheet notes but does not act on).
    nonisolated static func classify(
        rows: [LibraryImageRow], projectDirectory: URL
    ) -> Classification {
        var classification = Classification()
        for row in rows {
            guard let kind = LibrarySchema.PathKind(rawValue: row.pathKind) else {
                continue
            }
            if case .stale(let reason) = ImageLinker.resolve(
                imagePath: row.imagePath,
                pathKind: kind,
                volumeUUID: row.volumeUUID,
                projectDirectory: projectDirectory) {
                switch reason {
                case .pathMissing:
                    classification.pathMissing.append(row)
                case .volumeAbsent:
                    classification.volumeAbsent.append(row)
                }
            }
        }
        return classification
    }

    // MARK: - The batch (KD-4: the App-layer orchestration loop)

    /// Cancel the running batch at the next row boundary.
    func cancel() {
        cancelRequested = true
    }

    /// Relink every row against `sourceDirectory` (files matched by their
    /// stored filename). Progress rides the given handle (the
    /// BackgroundTaskHosting second leg); the result classifies every row.
    @discardableResult
    func runBatch(
        rows: [LibraryImageRow],
        sourceDirectory: URL,
        projectDirectory: URL,
        store: ProjectFileStore,
        handle: RelinkTaskHandle?
    ) async -> BatchResult {
        guard !isRunning else {
            return result ?? BatchResult()
        }
        isRunning = true
        cancelRequested = false
        defer {
            isRunning = false
            if let handle {
                Task { await handle.finish() }
            }
        }

        var outcome = BatchResult()
        let total = rows.count
        for (index, row) in rows.enumerated() {
            if cancelRequested {
                outcome.cancelled += 1
                continue
            }
            // The name-matched candidate in the picked directory.
            let filename = row.filename
                ?? (row.imagePath as NSString).lastPathComponent
            let candidate = sourceDirectory.appendingPathComponent(filename)
            // The linker rebuilds kind/uuid/path from the candidate's CURRENT
            // volume relationship (the M2-2-2 relink face, consumed as-is).
            let record = ImageLinker.relinkRecord(
                for: candidate,
                projectDirectory: projectDirectory,
                uuidProbe: uuidProbe)
            do {
                guard let persistLeg else {
                    // Unreachable through the gated sheet — the typed
                    // refusal keeps the contract honest anyway.
                    throw LibraryError.constraintViolation(
                        detail: "relink persistence leg not wired (Core write face pending)")
                }
                try await persistLeg(row.id, record)
                // Post-relink honesty: the row counts relived only when the
                // NEW record actually resolves.
                if case .resolved = ImageLinker.resolve(
                    imagePath: record.imagePath,
                    pathKind: record.pathKind,
                    volumeUUID: record.volumeUUID,
                    projectDirectory: projectDirectory) {
                    outcome.relived += 1
                } else {
                    outcome.stillStale += 1
                }
            } catch {
                // A failing row never blocks the rest (the AC's face).
                outcome.stillStale += 1
            }
            handle?.apply(processed: index + 1, total: total)
        }
        result = outcome
        return outcome
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The BackgroundTaskHosting second leg (P1 protocol consumption): one
// handle per batch, monotonic progress, cancel transit into the model.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class RelinkTaskHandle: BackgroundTaskHandle {

    let id = UUID()

    let title: String

    var snapshot = BackgroundTaskSnapshot.indeterminate(
        String(localized: "tasks_relink_waiting",
               defaultValue: "Relink pending…"))

    /// The live handle hands the finished flag to the registry host.
    private(set) var isFinished = false

    private let cancelRoute: () -> Void

    /// The monotonic floor (the import leg's clamp twin).
    private var lastFraction: Double = 0

    init(count: Int, cancelRoute: @escaping () -> Void) {
        self.title = String(
            localized: "tasks_relink_title",
            defaultValue: "Relinking \(count) photos…")
        self.cancelRoute = cancelRoute
    }

    /// Test seam: an explicit title + cancel route.
    init(title: String, cancelRoute: @escaping () -> Void) {
        self.title = title
        self.cancelRoute = cancelRoute
    }

    /// Mirror one batch step into the monotonic snapshot: an out-of-order
    /// or replayed step is dropped WHOLE (fraction AND detail — a regressed
    /// "2 of 10" after "6 of 10" is a UI lie).
    func apply(processed: Int, total: Int) {
        guard total > 0 else { return }
        let fraction = Double(processed) / Double(total)
        guard fraction >= lastFraction else { return }
        lastFraction = fraction
        snapshot = .fraction(
            fraction,
            String(
                localized: "tasks_relink_counts",
                defaultValue: "\(processed) of \(total)"))
    }

    /// The batch is done — the host finishes the registry entry.
    func finish() {
        isFinished = true
    }

    // MARK: - BackgroundTaskHandle

    func cancel() async {
        cancelRoute()
        snapshot = .fraction(
            lastFraction,
            String(localized: "tasks_relink_cancelled",
                   defaultValue: "Relink cancelled"))
    }
}
