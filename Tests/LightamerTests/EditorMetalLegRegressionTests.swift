import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// EditorMetalLegRegressionTests — defect B (M2-3 walkthrough 真缺陷 B): the
// editor's first image load succeeded at DECODE but the viewport stayed
// empty forever (3/3 GUI repro incl. cold start; node header EXIF read from
// the row while the render leg never ran; scopes/stack empty as satellites).
//
// ROOT CAUSE: the editor GUI chain (EditorWorkspaceShellView.loadCurrentImage)
// feeds `pipeCoordinator.detectionMetal()` into `EditorState.load`'s metal
// parameter, but `PipeCoordinator.metal` was assigned ONLY inside
// `pipeCoordinator.load()` — a chicken-and-egg deadlock. The FIRST editor
// load always read nil and the whole render leg was skipped behind
// `if let metal` in `EditorState.load` (decode-only leg, no error, no log —
// the "no decode on screen" walkthrough signature). The direct-load probe
// (`-la_sidecar_probe`, which passes the app-root context) always rendered —
// which is why the defect hid until the GUI chain was exercised.
//
// FIX: the composition root attaches its ONE MetalContext at launch
// (`pipeCoordinator.attach(metal:)`) — `detectionMetal()` is non-nil before
// any load; the command-queue discipline (one context, D-L031) is kept.
//
// The pinned regression face mirrors the GUI chain's EXACT value flow:
// metal for the load comes from `detectionMetal()` (not from a test-held
// reference) — before the fix this read nil and the render leg died.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class EditorMetalLegRegressionTests: XCTestCase {

    private var metal: MetalContext!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        editorState = EditorState()
        coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
    }

    override func tearDown() async throws {
        coordinator = nil
        editorState = nil
        metal = nil
        try await super.tearDown()
    }

    /// The defect shape, pinned as documentation: a bare coordinator has no
    /// metal context — the OLD order (context assigned only inside load())
    /// made this nil read the FIRST editor load's render-leg key.
    func testDetectionMetalIsNilBeforeAttachment() {
        XCTAssertNil(
            coordinator.detectionMetal(),
            "pre-attach nil is the documented defect shape (defect B)")
    }

    /// The fix face: the composition root's attach makes `detectionMetal()`
    /// return the injected context — the SAME instance (one context, one
    /// command queue, D-L031), non-nil BEFORE any load.
    func testAttachMetalMakesDetectionFaceNonNil() {
        coordinator.attach(metal: metal)
        XCTAssertTrue(
            coordinator.detectionMetal() === metal,
            "detectionMetal() must surface the attached app-owned context")
    }

    /// The GUI chain's exact value flow: the load's metal comes from
    /// `detectionMetal()` (as `loadCurrentImage` reads it). With the fix,
    /// the render leg runs and the display texture lands. Before the fix,
    /// `detectionMetal()` was nil at the first load → `EditorState.load`
    /// skipped the pipe leg → the viewport stayed empty (the pinned red).
    func testEditorChainRenderLegRunsThroughDetectionFace() async throws {
        coordinator.attach(metal: metal)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-metal-leg-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }

        // The GUI-shaped load: metal resolved through the detection face.
        let guiMetal = coordinator.detectionMetal()
        let context = try XCTUnwrap(
            guiMetal, "the attached coordinator must hand the chain a context")
        await coordinator.load(
            url: url,
            decoded: Self.decodedGradient(),
            instances: [],
            metal: context)

        // The render leg must reach the display sink (the viewport's feed).
        for _ in 0..<100 where editorState.displayTexture == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(
            editorState.displayTexture,
            "the editor chain's render leg must push the display texture "
                + "when the metal context arrives through detectionMetal()")
    }

    // MARK: - Fixture

    /// Synthetic gradient plane (BeforeAfterTests' shape — no real RAW
    /// dependency; the render leg under test is transport-agnostic).
    nonisolated private static func decodedGradient(size: Int = 240) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }
}
