import AppKit
import CoreGraphics
import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryAnalysisWiring (Plan LUMEN-A T5, review M-2) — the App-side assembly
// for the culling analysis pass: the project-open START point, the
// `library.analysis.enabled` gate, the export/AI activity probe injection and
// the BackgroundTaskRegistry adapter handle.
//
// WHY THIS FACE EXISTS (review M-2): BackgroundTaskRegistry is an App-side
// @MainActor class — Core cannot import it. The Core actor exposes
// `progressEvents()`; THIS wiring owns the @MainActor adapter handle that
// forwards the snapshots into the registry (the import/export/AI legs'
// same bar/dialog face). The shell hands in its faces ONCE (the KD-5 sink
// assembly shape — the assembly point reads, views inject) and the wiring
// tracks `LibraryProjectController.projectURL` as the start/stop event.
//
// ISOLATION: the wiring is @MainActor by nature (it touches the controller,
// the registry and the shell's @Observable faces); the Core actor calls stay
// inside Tasks.
// ─────────────────────────────────────────────────────────────────────────────

/// The export/AI activity probe payload the shell composes (both faces are
/// MainActor @Observable state — the closure reads them on the main actor).
@MainActor
struct LibraryAnalysisActivityProbes: Sendable {
    /// True while the export queue holds jobs (any job row = busy).
    var exportBusy: @Sendable () -> Bool
    /// True while an AI analysis task is queued or executing.
    var aiBusy: @Sendable () -> Bool

    func anyBusy() -> Bool { exportBusy() || aiBusy() }
}

/// The registry adapter handle (the FOURTH background-task leg — the
/// import/export/AI precedent shape, review M-2).
@MainActor
final class LibraryAnalysisHandle: BackgroundTaskHandle, @unchecked Sendable {

    let id = UUID()
    let title: String
    var snapshot = BackgroundTaskSnapshot.indeterminate(
        String(localized: "tasks_analysis_waiting",
               defaultValue: "Analyzing library…"))

    private let onCancelRoute: @Sendable () async -> Void

    init(onCancel: @escaping @Sendable () async -> Void) {
        self.title = String(
            localized: "tasks_analysis_title",
            defaultValue: "Photo analysis")
        self.onCancelRoute = onCancel
    }

    func apply(_ progress: LibraryAnalysisProgress) {
        guard progress.total > 0 else {
            snapshot = .indeterminate(snapshot.detail)
            return
        }
        snapshot = .fraction(
            Double(progress.done) / Double(progress.total),
            String(localized: "tasks_analysis_detail \(progress.done) \(progress.total)"))
    }

    func cancel() async {
        await onCancelRoute()
    }
}

@MainActor
@Observable
final class LibraryAnalysisWiring {

    /// The live service for the open project (nil = no project / disabled).
    private(set) var service: LibraryAnalysisService?

    private let libraryProjects: LibraryProjectController
    private let registry: BackgroundTaskRegistry
    private let probes: LibraryAnalysisActivityProbes
    private let defaultsSuiteName: String?

    private var handle: LibraryAnalysisHandle?
    private var progressTask: Task<Void, Never>?
    private var observedURL: URL?

    init(
        libraryProjects: LibraryProjectController,
        registry: BackgroundTaskRegistry,
        probes: LibraryAnalysisActivityProbes,
        defaultsSuiteName: String? = nil
    ) {
        self.libraryProjects = libraryProjects
        self.registry = registry
        self.probes = probes
        self.defaultsSuiteName = defaultsSuiteName
    }

    // MARK: - The project-open event (the shell's `.task(id:)` hook)

    /// Call whenever the open project MAY have changed (the shell body's
    /// `.task(id: libraryProjects.projectURL)` — fires on open/close/switch;
    /// nil = the no-project state). The enabled gate (D-LU-5 默认开) wraps
    /// everything: disabled = tear down and stay inert.
    func projectChanged(to url: URL?) async {
        guard url != observedURL else { return }
        observedURL = url
        teardown()
        guard let url, let store = projectStore(for: url) else { return }
        guard LibraryAnalysisService.isEnabled(defaults: defaults) else { return }

        let service = await LibraryAnalysisService(
            store: store,
            queries: LibraryQueries(store: store),
            faceProvider: VisionEyeLandmarkProvider(),
            defaultsSuiteName: defaultsSuiteName)
        self.service = service

        // H-LU1: the export/AI activity probe (pause while either is live).
        await service.setActivityProbe { [probes] in
            await MainActor.run { probes.anyBusy() }
        }

        // The registry adapter (review M-2): the @MainActor handle forwards
        // the Core progress stream into the shared bar/dialog face.
        let handle = LibraryAnalysisHandle(onCancel: { [weak service] in
            await service?.cancel()
        })
        self.handle = handle
        registry.register(handle)
        progressTask = Task { [weak self, handle] in
            let events = await service.progressEvents()
            for await progress in events {
                handle.apply(progress)
            }
        }
        await service.start()
    }

    private func projectStore(for url: URL) -> ProjectFileStore? {
        guard libraryProjects.projectURL == url else { return nil }
        return libraryProjects.projectStore
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private func teardown() {
        progressTask?.cancel()
        progressTask = nil
        if let handle {
            registry.finish(id: handle.id)
        }
        handle = nil
        if let service {
            Task { await service.cancel() }
        }
        service = nil
    }
}
