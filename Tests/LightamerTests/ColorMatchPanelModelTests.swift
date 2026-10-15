@testable import LightamerCore
@testable import LightamerIOP
@testable import Lightamer
import XCTest

/// ColorMatchPanelModelTests (Plan M5-1-02 T6/T7, KD-6/KD-7; TRACK-04) —
/// the panel ViewModel:
///
/// - the THREE-LEVEL read (the live drag window's value → the instance
///   record → the pristine default);
/// - the strength D-H1 trio committing EXACTLY ONE history item per drag
///   with the last live value;
/// - the reference list actions (add dedupes by URL, remove, the weight
///   clamp — KD-7's session-state list);
/// - the solver display names (three distinct faces) + the readout
///   projection (the R1 fallback line rides `effectiveSolver`).
final class ColorMatchPanelModelTests: XCTestCase {

    @MainActor
    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator, metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, metal)
    }

    @MainActor
    private func makeModel(
        _ assembly: (editorState: EditorState, coordinator: PipeCoordinator, metal: MetalContext),
        instance: ModuleInstance?
    ) -> ColorMatchPanelModel {
        ColorMatchPanelModel(
            instance: instance, editorState: assembly.editorState,
            pipeCoordinator: assembly.coordinator,
            service: ColorMatchService(metal: assembly.metal, registry: ModuleRegistry.makeDefault()),
            editSession: InspectorEditSession(coordinator: assembly.coordinator))
    }

    // MARK: - The three-level read

    @MainActor
    func testReadProjectionThreeLevels() async throws {
        let assembly = try await makeAssembly()
        // Level 3: NO instance → the pristine default (strength 0).
        let pristine = makeModel(assembly, instance: nil)
        XCTAssertEqual(pristine.params.strength, 0)
        XCTAssertTrue(pristine.params.isUnsolved)

        // Level 2: the instance record's params.
        var params = ColormatchModule.Params()
        params.strength = 0.35
        params.sourceStatsHash = "11"
        params.referenceStatsHash = "22"
        let instance = ModuleInstance(
            module: ColormatchModule.self, multiPriority: 0, params: params)
        let withRecord = makeModel(assembly, instance: instance)
        XCTAssertEqual(withRecord.params.strength, 0.35)

        // Level 1: the live drag window's value wins while open.
        withRecord.beginStrengthDrag()
        withRecord.setStrengthLive(0.8)
        XCTAssertEqual(withRecord.params.strength, 0.8, "the live window reads back its own value")
        withRecord.commitStrengthDrag()
    }

    // MARK: - The strength D-H1 trio

    @MainActor
    func testStrengthDragCommitsExactlyOneItem() async throws {
        let assembly = try await makeAssembly()
        let instance = ModuleInstance(
            module: ColormatchModule.self, multiPriority: 0,
            params: ColormatchModule.Params())
        // The instance must LIVE in the editor state for the live leg to
        // upsert + the commit to land (the real attach shape).
        assembly.editorState.resetHistoryForNewImage(defaultInstances: [])
        assembly.editorState.recordChange(instance, label: "test_seed")
        let seeded = try XCTUnwrap(assembly.editorState.instances.first {
            $0.opName == ColormatchModule.opName
        })
        let model = makeModel(assembly, instance: seeded)
        let before = assembly.editorState.history.items.count

        model.beginStrengthDrag()
        // The session faces are fire-and-forget Tasks — yield between the
        // steps so the MainActor drains them in submission order (the
        // production slider has real time between events).
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))
        model.setStrengthLive(0.3)
        try await Task.sleep(for: .milliseconds(20))
        model.setStrengthLive(0.6)
        try await Task.sleep(for: .milliseconds(20))
        model.setStrengthLive(0.9)
        try await Task.sleep(for: .milliseconds(20))
        model.commitStrengthDrag()
        try await Task.sleep(for: .milliseconds(100))
        // Drain the in-flight tick-render continuations, then force one
        // final rematerialize (the compressed test timeline can otherwise
        // leave a pre-commit tick rebuild running AFTER the commit's
        // upsert — the production slider's real event spacing never
        // overlaps these).
        await assembly.coordinator.historyDidChange()

        XCTAssertEqual(
            assembly.editorState.history.items.count, before + 1,
            "EXACTLY ONE item per drag window; items="
                + assembly.editorState.history.items.map { "\($0.label)|\(String(data: $0.snapshot.paramsData, encoding: .utf8)?.prefix(120) ?? "?")" }.joined(separator: " ;; "))
        let record = try XCTUnwrap(assembly.editorState.instances.first {
            $0.opName == ColormatchModule.opName
        })
        let params = try record.params(of: ColormatchModule.self)
        XCTAssertEqual(params.strength, 0.9, "the last live value landed")
        // The history item itself carries the last live value (the commit
        // snapshot = the tick snapshot).
        let lastItem = assembly.editorState.history.items.last
        let lastParams = try lastItem?.snapshot.params(of: ColormatchModule.self)
        XCTAssertEqual(lastParams?.strength, 0.9, "the history snapshot carries it too")
        // The read fell back to the committed record (the window closed).
        XCTAssertEqual(model.params.strength, 0.9)
    }

    // MARK: - The committed-truth snapshot (V2M-01 T1, defect D-1)

    @MainActor
    private func makeInstance(strength: Float, id: UUID = UUID()) -> ModuleInstance {
        var params = ColormatchModule.Params()
        params.strength = strength
        return ModuleInstance(
            id: id, module: ColormatchModule.self, multiPriority: 0, params: params)
    }

    /// The snapshot refresh semantics: a committed chain-record change →
    /// the refresh hook (`updateInstance`, the view's `.onChange(of:
    /// instance)` seam) → the snapshot syncs (the getter answers the NEW
    /// value with zero coordinator reads).
    @MainActor
    func testSnapshotRefreshFollowsTheCommittedRecord() async throws {
        let assembly = try await makeAssembly()
        let identity = UUID()
        let first = makeInstance(strength: 0.2, id: identity)
        let model = makeModel(assembly, instance: first)
        XCTAssertEqual(model.params.strength, 0.2, "init seeds the snapshot")

        // A committed change (the external-write / post-commit shape): the
        // chain carries a new record and the view seam hands it over.
        let second = makeInstance(strength: 0.7, id: identity)
        assembly.editorState.resetHistoryForNewImage(defaultInstances: [])
        assembly.editorState.recordChange(second, label: "test_external_write")
        model.updateInstance(second)
        XCTAssertEqual(model.params.strength, 0.7, "the hook re-seats the snapshot")

        // The instance-switch shape: a different record id entirely.
        let switched = makeInstance(strength: 0.45)
        model.updateInstance(switched)
        XCTAssertEqual(model.params.strength, 0.45)
        XCTAssertTrue(model.hasInstance)
        XCTAssertEqual(model.instance?.id, switched.id)
    }

    /// The liveParams window priority: while the drag window is open the
    /// live value pins the read over the snapshot; after the commit the
    /// read falls back to the commit-tail-refreshed snapshot (the last
    /// live value) — continuous across the async landing gap.
    @MainActor
    func testLiveWindowOverridesTheSnapshotUntilCommit() async throws {
        let assembly = try await makeAssembly()
        let model = makeModel(assembly, instance: makeInstance(strength: 0.2))
        XCTAssertEqual(model.params.strength, 0.2)

        model.beginStrengthDrag()
        model.setStrengthLive(0.6)
        XCTAssertEqual(
            model.params.strength, 0.6, "the open window's live value wins over the snapshot")
        model.commitStrengthDrag()
        XCTAssertEqual(
            model.params.strength, 0.6,
            "the commit tail refreshes the snapshot to the last live value")
        XCTAssertEqual(model.params.strength, 0.6, "the read is stable across repeated reads")

        // The next committed change (the async landing re-seat) wins again.
        model.updateInstance(makeInstance(strength: 0.4))
        XCTAssertEqual(model.params.strength, 0.4)
    }

    // MARK: - The reference list actions (KD-7)

    @MainActor
    func testReferenceListActions() async throws {
        let assembly = try await makeAssembly()
        let model = makeModel(assembly, instance: nil)
        XCTAssertTrue(model.references.isEmpty, "the list opens empty (session state)")

        let urlA = URL(fileURLWithPath: "/tmp/ref-a.tif")
        let urlB = URL(fileURLWithPath: "/tmp/ref-b.tif")
        model.addReference(url: urlA)
        model.addReference(url: urlB)
        model.addReference(url: urlA)  // dedupe
        XCTAssertEqual(model.references.count, 2, "the same URL never duplicates a row")
        XCTAssertEqual(model.references[0].weight, 1, "the default weight is the equal split")

        let rowID = model.references[0].id
        model.setWeight(0.4, id: rowID)
        XCTAssertEqual(model.references[0].weight, 0.4)
        model.setWeight(5, id: rowID)
        XCTAssertEqual(model.references[0].weight, 1, "the weight clamps to the range")
        model.setWeight(-1, id: rowID)
        XCTAssertEqual(model.references[0].weight, 0, "the weight clamps low")

        model.removeReference(id: rowID)
        XCTAssertEqual(model.references.count, 1)
        XCTAssertEqual(model.references[0].url, urlB)
    }

    @MainActor
    func testSolveGuardWithoutReferences() async throws {
        let assembly = try await makeAssembly()
        let model = makeModel(assembly, instance: nil)
        model.solve(solver: .gaussianOT, strength: 0.5)
        XCTAssertNotNil(model.solveError, "a solve with no references is typed-rejected")
    }

    // MARK: - The readout projection

    @MainActor
    func testSolverDisplayNamesAreDistinct() {
        let names = ColorMatchSolverKind.allCases.map {
            ColorMatchPanelModel.solverDisplayName($0)
        }
        XCTAssertEqual(Set(names).count, 3, "three distinct solver labels")
    }

    @MainActor
    func testReadoutProjectsTheFallbackDiagnostic() async throws {
        let assembly = try await makeAssembly()
        var params = ColormatchModule.Params()
        params.strength = 0.5
        params.sourceStatsHash = "42"
        params.referenceStatsHash = "43"
        params.effectiveSolver = .reinhard  // the R1 fallback face
        params.solver = .gaussianOT
        let instance = ModuleInstance(
            module: ColormatchModule.self, multiPriority: 0, params: params)
        let model = makeModel(assembly, instance: instance)
        let readout = model.readout
        XCTAssertEqual(readout.solver, ColorMatchPanelModel.solverDisplayName(.gaussianOT))
        XCTAssertNotEqual(readout.effective, readout.solver, "the fallback line discloses")
        XCTAssertEqual(readout.statsHash, "42")
        XCTAssertNil(readout.supportWidth, "no extraction yet — the support line stays absent")
    }
}
