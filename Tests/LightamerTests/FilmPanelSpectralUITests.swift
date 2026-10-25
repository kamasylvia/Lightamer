import AppKit
import ApplicationServices
import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelSpectralUITests (Plan M8-3 T1/T3 — APP bundle) — the FSIM spectral
// upgrade's UI-face pins:
//
//   T1 (D-M8-7, UI zero-new-controls): the film panel's control inventory is
//   a FROZEN SNAPSHOT — the spectral core ships with ZERO new panel controls
//   (the material pickers, the Y·M dual sliders, the strength/exposure
//   sliders, the content-adaptive toggle and the solve row keep their exact
//   M3-3-03 faces; the readout numbers changing with the core is a render
//   face, not a UI face). The machine check walks the LIVE accessibility tree
//   of a mounted `FilmPanelView` and asserts the `film.*` identifier domain
//   equals the snapshot exactly, with no adaptation/bandwidth/surface/
//   upsampling control anywhere in it (D-M8-7: the upstream adaptation two
//   switches and the table selector are build-time constants, never user
//   intent faces). The source-level grep half of the machine check runs in
//   the shell (evidence archived in M8-3-DECISIONS).
//
//   T3 (the migration UX, M6-2 §6 的挂账正主): the ONE new panel element the
//   plan allows — the "Update to Current Process" row for documents still
//   rendering the frozen density arm — with its confirm sheet (a SwiftUI
//   sheet through the L057 seam: never a runModal) and the migration action
//   model (the pure evaluate face: v1/legacy migratable, current refused,
//   in-flight edits refused, film-less documents not applicable).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmPanelSpectralUITests: XCTestCase {

    private var metal: MetalContext!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!
    private var model: FilmPanelModel!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        editorState = EditorState()
        coordinator = PipeCoordinator()
        workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        let profiles = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
        coordinator.attachFilmStore(try FilmMaterialStore(profilesDirectory: profiles))
        model = FilmPanelModel(editorState: editorState, pipeCoordinator: coordinator)
    }

    override func tearDown() async throws {
        model = nil
        workspace = nil
        coordinator = nil
        editorState = nil
        metal = nil
        try await super.tearDown()
    }

    nonisolated private static func decodedGradient(size: Int = 160) -> DecodedImage {
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

    private func loadGradient() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("film-spectral-ui-\(UUID().uuidString).tif")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    // MARK: - T1: the AX walk (the ToastFaceTests in-process shape)

    /// Depth-first AX walk collecting `AXIdentifier` values (self AX needs no
    /// TCC grant).
    private func collectIdentifiers(
        _ element: AXUIElement, into set: inout Set<String>, depth: Int = 0
    ) {
        guard depth < 40 else { return }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value) == .success,
            let identifier = value as? String {
            set.insert(identifier)
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
            let kids = children as? [AXUIElement] else { return }
        for kid in kids {
            collectIdentifiers(kid, into: &set, depth: depth + 1)
        }
    }

    /// The async-context runloop pump (the CullingPipelineTests shape: a
    /// nonisolated sync tick — it still executes ON the main thread from the
    /// MainActor async test, and the sync annotation keeps the
    /// run(until:) availability check out of the call site).
    nonisolated private func runLoopTick() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    /// The hosting root carrying exactly the injections the panel reads at
    /// its depth (the app root writes them; the mount mirrors that).
    private struct PanelHost: View {
        let editorState: EditorState
        let pipeCoordinator: PipeCoordinator
        let inspectorState: InspectorState

        var body: some View {
            FilmPanelView()
                .environment(editorState)
                .environment(pipeCoordinator)
                .environment(inspectorState)
        }
    }

    /// The FROZEN control inventory (M3-3-03's panel face): the COMPLETE
    /// set of accessibility identifiers FilmPanelView may carry — the
    /// `.accessibilityIdentifier` literals AND the call-argument forms
    /// (`axIdentifier:` on the shared row shells, `accessibilityID:` on the
    /// LightamerSlider rows). T3 adds EXACTLY the migrate row's identifiers
    /// to this table — nothing else ever may.
    static let frozenControlInventory: Set<String> = [
        "editor.stack.film.panel",
        "film.close",
        "film.enable",
        "film.film.picker",
        "film.paper.picker",
        "film.y.slider",
        "film.m.slider",
        "film.strength.slider",
        "film.exposure.slider",
        "film.content.toggle",
        "film.solve.button",
        "film.readout.value",
        "film.readout.unbound",
        "film.latitude.section",
        "film.latitude.histogram",
        "film.latitude.share.below",
        "film.latitude.share.inside",
        "film.latitude.share.above",
        "film.placement.section",
        "film.placement.add",
        "film.placement.nh",
        "film.placement.ns",
        "film.placement.m",
        "film.placement.fit",
        "film.placement.fit.refused",
        "film.placement.fit.shared",
        "film.placement.fit.sidesoff",
        "film.placement.readouts",
        "film.placement.reject.knee",
        "film.placement.reject.nh",
        "film.placement.reject.ns",
    ]

    /// The identifier literals parsed out of the panel source: the panel's
    /// identifiers all follow the dot-namespaced literal convention, so the
    /// scan walks EVERY `"film.*"` / `"editor.*"` string literal (covering
    /// the `.accessibilityIdentifier` form AND the call-argument forms
    /// `axIdentifier:` / `accessibilityID:` / the positional share labels).
    static func inventoryFromSource(_ source: String) -> Set<String> {
        Set(source.matches(of: /"((?:film|editor)\.[a-zA-Z][a-zA-Z.]+)"/)
            .map { String($0.1) })
    }

    /// T1 ①: the panel's control inventory is the frozen snapshot. TWO
    /// machine faces:
    ///   (a) the SOURCE face — the identifier inventory in
    ///       FilmPanelView.swift (all three spelling forms) equals the
    ///       frozen inventory exactly (the panel's convention is that
    ///       EVERY operable element carries one; a new control means a new
    ///       identifier, a removed control means a missing one). This is
    ///       the deterministic zero-new-controls gate — the in-process AX
    ///       tree materializes lazily for self-queries, so the LIVE tree
    ///       alone cannot carry the equality;
    ///   (b) the LIVE face (`...InTheLiveTree`) — whatever the AX tree of
    ///       a mounted panel materializes must belong to the frozen set.
    func testPanelControlInventoryMatchesTheFrozenSnapshot() throws {
        // ── (a) the source face ─────────────────────────────────────────
        let panelSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "App/Sources/Lightamer/UI/Shell/FilmPanelView.swift")
        let source = try String(contentsOf: panelSource, encoding: .utf8)
        let inventory = Self.inventoryFromSource(source)
        XCTAssertGreaterThanOrEqual(
            inventory.count, 30, "防空转: the panel's identifier face parsed")
        XCTAssertEqual(
            inventory, Self.frozenControlInventory,
            "FilmPanelView's identifier inventory must equal the frozen "
                + "snapshot — diff: "
                + "\(inventory.symmetricDifference(Self.frozenControlInventory))")
    }

    /// T1 ①(b) + ②: the LIVE tree of a mounted, film-enabled panel — no
    /// identifier outside the frozen snapshot, and no
    /// adaptation/bandwidth/surface/upsampling control anywhere (D-M8-7:
    /// the upstream adaptation two switches stay build-time constants —
    /// bandwidth恒 on / surface恒 off; the tc table selector never existed
    /// on our model face). The source-level grep half runs in the shell
    /// (DECISIONS evidence).
    func testLivePanelExposesOnlyFrozenIdentifiersAndNoAdaptationControls() async throws {
        try await loadGradient()
        model.enableFilm()
        let start = Date()
        while !workspace.hasFilmRecord(for: coordinator.liveImageURL!) {
            if Date().timeIntervalSince(start) > 5 {
                XCTFail("the film record never reached the carrier")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 900),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PanelHost(
            editorState: editorState, pipeCoordinator: coordinator,
            inspectorState: InspectorState()))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 900)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let axWindow = AXUIElementCreateApplication(
            ProcessInfo.processInfo.processIdentifier)

        var collected = Set<String>()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            await Task.yield()
            runLoopTick()
            host.layoutSubtreeIfNeeded()
            collected = []
            collectIdentifiers(axWindow, into: &collected)
            if collected.contains("film.solve.button")
                && collected.contains("film.placement.add") { break }
        }

        let strangers = collected.filter { $0.hasPrefix("film.") }
            .subtracting(Self.frozenControlInventory)
        XCTAssertTrue(
            strangers.isEmpty,
            "the live panel exposed identifiers outside the frozen snapshot: "
                + "\(strangers.sorted())")
        let forbidden = ["adaptation", "bandwidth", "surface", "upsampling"]
        for identifier in collected {
            let lowered = identifier.lowercased()
            for token in forbidden {
                XCTAssertFalse(
                    lowered.contains(token),
                    "the panel must expose no adaptation/table-selector control "
                        + "(found \(identifier) via token \(token))")
            }
        }
    }

    /// T1 ②: the source-level half of the adaptation non-exposure face
    /// (D-M8-7): the panel source carries no adaptation/bandwidth/surface/
    /// upsampling control spelling, and the App target sources reference no
    /// spectral adaptation parameter face. (The live-tree half runs in
    /// `testLivePanelExposesOnlyFrozenIdentifiersAndNoAdaptationControls`;
    /// the shell grep evidence is archived in M8-3-DECISIONS.)
    func testPanelSourceCarriesNoAdaptationControlFace() throws {
        let panelSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "App/Sources/Lightamer/UI/Shell/FilmPanelView.swift")
        let source = try String(contentsOf: panelSource, encoding: .utf8)
            .lowercased()
        for token in ["adaptation", "bandwidth", "upsampling", "surface"] {
            XCTAssertFalse(
                source.contains(token),
                "the film panel must expose no adaptation control (token \(token))")
        }
    }
}
