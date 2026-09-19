import Foundation
import os

/// The per-image sidecar writer/reader (Plan 02-06-03; D-S3). ONE store per
/// loaded image, owned by the app's `PipeCoordinator`; tests use temp-dir
/// destinations.
///
/// **Throttle (D-S3):** `scheduleWrite` merges write bursts — a slider
/// storm never touches disk more than once per 2-second window. Re-scheduling
/// CANCELS the sleeping writer task and restarts the window with the newest
/// document (LAST-write-wins merge). `flushNow()` forces the pending write
/// immediately (image switch + application termination); idempotent when
/// nothing is pending.
///
/// **Atomicity (L009):** the tmp file is created in the DESTINATION'S OWN
/// directory (`.tmp-<uuid>` sibling) so the final rename is same-VOLUME —
/// a cross-volume rename (e.g. against `/tmp`) would degrade to a copy and
/// lose atomicity. Promotion is `FileManager.replaceItemAt` when the
/// destination already exists, plain `rename` (moveItem) for the first
/// write. A crash mid-write can only ever leave the tmp sibling behind,
/// never a half-written `.lra`.
///
/// **Load:** absent file → nil (pristine upgrade path); corrupt JSON →
/// logged + nil — `load` NEVER throws into the UI (the caller treats nil
/// as "start pristine", checkpoint 02-06-01 lock #4/#5 semantics live on
/// the document itself).
///
/// **Testability:** the debounce clock is injected (`some Clock<Duration>`,
/// default `ContinuousClock`); tests park/advance a fake clock instead of
/// sleeping real seconds (research Open Question #7 resolution — the timer
/// is only a caller of the pure write path).
public actor SidecarStore {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "sidecar"
    )

    /// The `.lra` destination (`LightamerSidecar.sidecarURL(for:)`).
    private let destination: URL

    /// The debounce window (production 2s, D-S3; tests shrink or fake it).
    private let debounce: Duration

    /// The injected debounce clock.
    private let clock: any Clock<Duration>

    /// The newest scheduled-but-unwritten document (nil = nothing pending).
    private var pending: LightamerSidecar?

    /// The in-flight debounce sleeper; a newer `scheduleWrite` cancels it.
    private var sleeper: Task<Void, Never>?

    /// Test seam: true while a document is scheduled but not yet flushed.
    public private(set) var hasPendingWrite: Bool = false

    public init(
        destination: URL,
        debounce: Duration = .seconds(2),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.destination = destination
        self.debounce = debounce
        self.clock = clock
    }

    // MARK: - Scheduling (D-S3)

    /// Schedule a throttled write. Re-scheduling inside the window cancels
    /// the pending sleep and restarts it with THIS document — the merged
    /// outcome is exactly one write carrying the newest state.
    public func scheduleWrite(_ document: LightamerSidecar) {
        pending = document
        hasPendingWrite = true
        sleeper?.cancel()
        sleeper = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.clock.sleep(for: self.debounce)
            } catch {
                return // cancelled by a newer schedule or flushNow — it owns the merge
            }
            guard !Task.isCancelled else { return }
            await self.writePending()
        }
    }

    /// Force the pending write NOW (image switch / termination). Idempotent
    /// when nothing is pending; cancels the sleeper (it must not write the
    /// consumed document again).
    public func flushNow() async throws {
        sleeper?.cancel()
        sleeper = nil
        guard let document = pending else { return }
        pending = nil
        hasPendingWrite = false
        try writeAtomic(document)
    }

    /// Read the sidecar. nil = absent (pristine) or corrupt (logged —
    /// never thrown; the UI upgrades to pristine instead of failing).
    public func load() -> LightamerSidecar? {
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: destination)
            return try JSONDecoder().decode(LightamerSidecar.self, from: data)
        } catch {
            Self.logger.error(
                "sidecar unreadable (\(self.destination.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public) — treating as pristine"
            )
            return nil
        }
    }

    // MARK: - Atomic write (L009)

    /// The debounced write leg: consume + write. Runs inside the sleeper
    /// task; errors land in the typed error + log (D-26 background toast
    /// at the app layer).
    private func writePending() async {
        guard let document = pending else { return }
        pending = nil
        hasPendingWrite = false
        do {
            try writeAtomic(document)
        } catch {
            Self.logger.error(
                "sidecar write failed (\(self.destination.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Encode (pretty + sortedKeys — the D-S1 readable format) → same-dir
    /// tmp → `replaceItemAt` (existing destination) or `rename` (first
    /// write). The tmp is removed on the failure path so no debris is ever
    /// left behind.
    private func writeAtomic(_ document: LightamerSidecar) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw AppError.sidecarWriteFailed(destination.path)
        }

        let directory = destination.deletingLastPathComponent()
        let tmp = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)"
        )
        do {
            // Plain write to the SAME-DIRECTORY tmp — the tmp→destination
            // promotion below is the atomic step (L009: never a /tmp
            // cross-volume rename, which would degrade to a copy).
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
        Self.logger.debug(
            "sidecar written: \(self.destination.lastPathComponent, privacy: .public) (\(data.count, privacy: .public) bytes)"
        )
    }
}
