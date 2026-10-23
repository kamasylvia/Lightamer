import AppKit
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// LibraryAnalysisWiringTests (Plan LUMEN-A T5, review M-2) — the App-side
// assembly face: the enabled gate, the project-open start/teardown state
// machine and the registry adapter (the analysis handle joins the SAME
// aggregate bar/dialog registry — the M2UIW-06 single-aggregate discipline).
// Every dependency is injectable (an isolated defaults suite + a temp
// controller); no Vision, no network.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryAnalysisWiringTests: XCTestCase {

    private var tempDirectory: URL!
    private var controller: LibraryProjectController!
    private var registry: BackgroundTaskRegistry!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("analysis-wiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        controller = LibraryProjectController(defaultsSuiteName: nil)
        registry = BackgroundTaskRegistry()
        defaultsSuiteName = "analysis-wiring-tests-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func makeWiring(enabled: Bool? = nil) -> LibraryAnalysisWiring {
        if let enabled {
            let suite = UserDefaults(suiteName: defaultsSuiteName)!
            suite.set(enabled, forKey: LibraryAnalysisService.enabledKey)
        }
        return LibraryAnalysisWiring(
            libraryProjects: controller,
            registry: registry,
            probes: LibraryAnalysisActivityProbes(
                exportBusy: { false }, aiBusy: { false }),
            defaultsSuiteName: defaultsSuiteName)
    }

    private func openProject(named name: String = "WiredProj") async throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(name).lalb")
        _ = try await controller.createProject(at: url, name: name)
        return url
    }

    // MARK: - ① The enabled gate

    func testEnabledGateStaysInertWhenDisabled() async throws {
        let url = try await openProject()
        let wiring = makeWiring(enabled: false)
        await wiring.projectChanged(to: url)
        XCTAssertNil(wiring.service, "disabled = the pass never assembles")
        XCTAssertTrue(registry.handles.isEmpty, "no registry row without a run")
    }

    // MARK: - ② The project-open start/teardown state machine

    func testProjectOpenRegistersAndCloseTearsDown() async throws {
        let url = try await openProject()
        let wiring = makeWiring()
        await wiring.projectChanged(to: url)

        // The service assembled and the adapter handle joined the aggregate
        // registry (the bar/dialog see the analysis leg).
        XCTAssertNotNil(wiring.service)
        XCTAssertEqual(registry.handles.count, 1)
        XCTAssertTrue(registry.handles[0] is LibraryAnalysisHandle)

        // The same-URL re-fire is idempotent (no duplicate services/rows).
        await wiring.projectChanged(to: url)
        XCTAssertEqual(registry.handles.count, 1)

        // Project closed → teardown: the registry row leaves, the service
        // is cancelled and dropped.
        await wiring.projectChanged(to: nil)
        XCTAssertNil(wiring.service)
        XCTAssertTrue(registry.handles.isEmpty)
    }

    func testProjectSwitchRebuildsService() async throws {
        let first = try await openProject(named: "WiredA")
        let second = try await openProject(named: "WiredB")
        let wiring = makeWiring()
        await wiring.projectChanged(to: first)
        let firstService = wiring.service
        await wiring.projectChanged(to: second)
        XCTAssertNotNil(wiring.service)
        XCTAssertNotIdentical(wiring.service, firstService)
        XCTAssertEqual(registry.handles.count, 1, "one adapter row across a switch")
    }

    // MARK: - ③ The probe composition + progress forwarding

    func testProbeCompositionAndProgressForwarding() {
        let flags = ProbeFlags()
        let probes = LibraryAnalysisActivityProbes(
            exportBusy: { flags.export }, aiBusy: { flags.ai })
        XCTAssertTrue(probes.anyBusy(), "aiBusy alone holds")
        flags.ai = false
        XCTAssertFalse(probes.anyBusy())
        flags.export = true
        XCTAssertTrue(probes.anyBusy(), "exportBusy alone holds")

        // The adapter handle maps a progress event onto the snapshot face.
        let handle = LibraryAnalysisHandle(onCancel: {})
        handle.apply(LibraryAnalysisProgress(done: 3, total: 10))
        XCTAssertEqual(handle.snapshot.progress ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertFalse(handle.snapshot.isIndeterminate)
    }
}


/// The probe flags carrier (@unchecked Sendable — mutated from the main
/// actor's test body only; the closures read synchronously).
private final class ProbeFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var exportFlag = false
    private var aiFlag = true

    var export: Bool {
        get { lock.lock(); defer { lock.unlock() }; return exportFlag }
        set { lock.lock(); exportFlag = newValue; lock.unlock() }
    }
    var ai: Bool {
        get { lock.lock(); defer { lock.unlock() }; return aiFlag }
        set { lock.lock(); aiFlag = newValue; lock.unlock() }
    }
}
