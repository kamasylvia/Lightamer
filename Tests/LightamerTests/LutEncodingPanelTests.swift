import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer

// LutEncodingPanelTests (Plan M3-1-01 T4, M2GRADE-08 / KD-4) — the LUT
// panel's encoding-picker wiring, exercised PROGRAMMATICALLY (no UI — the
// PanelWiringTests discipline):
//
// - the catalog grouping counts (scene 11 / display 6 / total 17 — the
//   explicit checker-M1 contract the picker renders);
// - the visibility rule (selected 3D LUT only — 1D hides both pickers);
// - the library-selection memory ride (a remembered pair joins the SAME
//   single applyDiscrete commit; no memory keeps the fields nil);
// - the picker change = one discrete commit + the remember-toggle
//   write-back pair; entry absent = typed no-op.
@MainActor
final class LutEncodingPanelTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lut-encoding-panel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// The full assembly (Metal-gated — the render chain is real): the
    /// pristine seed + a lut3d record upserted into EditorState (the
    /// panel's applyDiscrete path is editorState-side — setLiveParams
    /// upserts records regardless of the box chain).
    private func assemble(lutParams: Lut3dModule.Params) async throws {
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

        let url = tempDirectory.appendingPathComponent("panel.exr")
        try await coordinator.load(
            url: url, decoded: makeSyntheticImage(), instances: [], metal: metal)
        editorState.applyLiveInstance(
            ModuleInstance(module: Lut3dModule.self, params: lutParams))
        _ = try lutInstance()
    }

    /// The PanelWiringTests synthetic float32 image (no ImageIO decode).
    private func makeSyntheticImage() throws -> DecodedImage {
        let width = 16, height = 16
        var rgba = [Float](repeating: 0.25, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4 + 3] = 1.0 }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private func lutInstance() throws -> ModuleInstance {
        try XCTUnwrap(editorState.instances.first { $0.opName == Lut3dModule.opName })
    }

    private var historyCount: Int { editorState.history.items.count }

    // MARK: - Grouping counts (checker M1 explicit contract)

    /// The picker renders the catalog halves — scene 11 / display 6 /
    /// total 17, exactly (an add-a-row change must update this test).
    func testEncodingGroupCounts() {
        XCTAssertEqual(LutEncodingCatalog.all.count, 17)
        XCTAssertEqual(LutEncodingCatalog.sceneEncodings.count, 11)
        XCTAssertEqual(LutEncodingCatalog.displayEncodings.count, 6)
        // The picker groups mirror the catalog halves (LutEncodingPickerGroups
        // iterates exactly these two arrays).
        XCTAssertEqual(
            Set(LutEncodingCatalog.sceneEncodings.map(\.id))
                .intersection(LutEncodingCatalog.displayEncodings.map(\.id)),
            [], "scene and display halves are disjoint")
    }

    // MARK: - Visibility rule

    /// Both pickers show only for a selected 3D LUT (KD-3 boundary: 1D
    /// tables have no authoring-encoding semantics).
    func testVisibilityRule() {
        XCTAssertFalse(
            LutEncodingPanelLogic.showsEncodingPickers(lutName: nil, is1D: false),
            "no LUT selected: hidden")
        XCTAssertTrue(
            LutEncodingPanelLogic.showsEncodingPickers(lutName: "BuiltIn/Film.cube", is1D: false))
        XCTAssertFalse(
            LutEncodingPanelLogic.showsEncodingPickers(lutName: "BuiltIn/Film.cube", is1D: true),
            "1D table: hidden")
        XCTAssertFalse(
            LutEncodingPanelLogic.showsEncodingPickers(lutName: nil, is1D: true))
    }

    // MARK: - Memory ride (KD-4 ①)

    /// A remembered pair rides the library selection: the logic returns the
    /// entry's memory; the resulting params go through ONE applyDiscrete
    /// commit and the committed record carries the pair.
    func testLibrarySelectionRidesMemorySingleCommit() async throws {
        try await assemble(lutParams: Lut3dModule.Params())
        let before = historyCount
        let key = "BuiltIn/Film.cube"
        let entry = LutLibraryStore.InstalledLut(
            name: "Film.cube", relativePath: key, subdirectory: "BuiltIn",
            hash: "0", is1D: false, size: 33, title: "Film",
            rememberedEncodings: RememberedEncodings(
                input: .arriLogC4AWG4, output: .rec709BT1886))
        // The panel's selection closure, verbatim:
        var p = try lutInstance().params(of: Lut3dModule.self)
        p.lutName = key
        if let memory = LutEncodingPanelLogic.rememberedPair(forSelection: key, entry: entry) {
            p.inputEncoding = memory.input
            p.outputEncoding = memory.output
        }
        let record = try XCTUnwrap(
            PanelEditing.updated(try lutInstance(), params: p, as: Lut3dModule.self))
        let session = InspectorEditSession(coordinator: coordinator)
        await session.applyDiscreteForTest(record, label: "history_lut")

        XCTAssertEqual(historyCount, before + 1, "selection = exactly ONE commit")
        let committed = try XCTUnwrap(
            try lutInstance().params(of: Lut3dModule.self))
        XCTAssertEqual(committed.lutName, key)
        XCTAssertEqual(committed.inputEncoding, .arriLogC4AWG4)
        XCTAssertEqual(committed.outputEncoding, .rec709BT1886)
    }

    /// No remembered pair on the entry: the selection writes ONLY the
    /// lutName — the encoding fields stay nil (the default-pair semantics,
    /// the existing-document byte contract).
    func testLibrarySelectionWithoutMemoryKeepsFieldsNil() async throws {
        try await assemble(lutParams: Lut3dModule.Params())
        let before = historyCount
        let key = "External.cube"
        let entry = LutLibraryStore.InstalledLut(
            name: "External.cube", relativePath: key, subdirectory: nil,
            hash: "0", is1D: false, size: 33, title: nil, rememberedEncodings: nil)
        XCTAssertNil(LutEncodingPanelLogic.rememberedPair(forSelection: key, entry: entry))

        var p = try lutInstance().params(of: Lut3dModule.self)
        p.lutName = key
        if let memory = LutEncodingPanelLogic.rememberedPair(forSelection: key, entry: entry) {
            p.inputEncoding = memory.input
            p.outputEncoding = memory.output
        }
        let record = try XCTUnwrap(
            PanelEditing.updated(try lutInstance(), params: p, as: Lut3dModule.self))
        let session = InspectorEditSession(coordinator: coordinator)
        await session.applyDiscreteForTest(record, label: "history_lut")

        XCTAssertEqual(historyCount, before + 1)
        let committed = try XCTUnwrap(
            try lutInstance().params(of: Lut3dModule.self))
        XCTAssertEqual(committed.lutName, key)
        XCTAssertNil(committed.inputEncoding, "no memory: fields stay nil")
        XCTAssertNil(committed.outputEncoding)
    }

    // MARK: - Picker change + remember write-back (KD-4 ②③)

    /// A picker change is ONE discrete commit carrying the explicit pair;
    /// the remember-toggle write-back stores the CURRENT params pair.
    func testPickerChangeWritesParamsAndToggleBack() async throws {
        try await assemble(
            lutParams: Lut3dModule.Params(
                lutName: "BuiltIn/Film.cube", colorspace: .rec2020))
        let before = historyCount

        // The input-encoding binding's set leg, verbatim:
        var p = try lutInstance().params(of: Lut3dModule.self)
        p.inputEncoding = .arriLogC4AWG4
        p.outputEncoding = .rec709BT1886
        let record = try XCTUnwrap(
            PanelEditing.updated(try lutInstance(), params: p, as: Lut3dModule.self))
        let session = InspectorEditSession(coordinator: coordinator)
        await session.applyDiscreteForTest(record, label: "history_lut")
        XCTAssertEqual(historyCount, before + 1, "picker change = ONE discrete commit")

        // The write-back face: ON + entry registered = the current pair.
        let committed = try XCTUnwrap(
            try lutInstance().params(of: Lut3dModule.self))
        let pair = LutEncodingPanelLogic.writeBackPair(for: committed)
        XCTAssertEqual(pair.input, .arriLogC4AWG4)
        XCTAssertEqual(pair.output, .rec709BT1886)

        // A REAL temp-dir store proves the write face (the panel calls the
        // same method on the shared store).
        let store = LutLibraryStore(directory: tempDirectory.appendingPathComponent("LUTs"))
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("LUTs"), withIntermediateDirectories: true)
        try "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
            .write(
                to: tempDirectory.appendingPathComponent("LUTs/t.cube"), atomically: true,
                encoding: .utf8)
        store.rescan()
        store.updateRememberedEncodings(named: "t.cube", to: pair)
        XCTAssertEqual(store.entry(named: "t.cube")?.rememberedEncodings, pair)
        // Entry ABSENT = typed no-op (the store face, restated at the App
        // level for the toggle's guard).
        store.updateRememberedEncodings(named: "ghost.cube", to: pair)
        XCTAssertNil(store.entry(named: "ghost.cube"))
    }
}
