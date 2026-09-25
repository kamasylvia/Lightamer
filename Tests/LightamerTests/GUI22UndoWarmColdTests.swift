@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// GUI-22 (2026-09-24 GUI-19/21 修复轮复验发现, 同日修复): under a layer
// stack, the UNDO (warm) render of the reverted state stably diverged from
// the COLD restore render of the same state (7.808% px / meanAbsDiff 1.7423
// / max>128 on the real-app round; zero-mean, concentrated in mid-tone
// texture). Three iron facts: cold restart == first-frame baseline (0.0),
// warm self-consistent across mask on/off cycles (0.0), each path
// byte-for-byte reproducible — non-freeze, non-GUI-21.
//
// Root cause (the fix round's bisection): CIRAW-backed input-plane renders
// RE-EXECUTE on every render call (`cacheIntermediates: false`) and are NOT
// byte-stable on this host — speckle-level variance (~0.06% of float bytes,
// byte-max 255) that local-contrast iops amplify (18% plane divergence
// through `shadhi`). The session cache's budget eviction (a 2560px PREVIEW
// family is ~1.9 GB — families evict each other mid-session) forced
// input-plane MISSES whose re-renders froze a DIFFERENT speckle variant per
// path — exactly the three iron facts. Fixed in `CIContextPool`: the
// input-plane render memo (keyed on imageID ⊕ decodeParamsHash — the pipe
// cache's own §1.3 key domain) executes the CI chain at most once per
// (file, request) and hands every later render the identical texture.
//
// THE RESIDENT BYTE GATE: one coordinator drives layer-stack edits + undo
// (warm); a second coordinator + editor state cold-loads the SAME sidecar
// state with a FRESH decode; the display bytes must be byte-identical.
@MainActor
final class GUI22UndoWarmColdTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gui22-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

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
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - helpers (the PanelWiring harness shapes)

    /// L014-fenced display read-back (bgra8, 4 bytes/px).
    nonisolated private static func readDisplayBytes(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [UInt8] {
        let fenceBuffer = metal.commandQueue.makeCommandBuffer()
        fenceBuffer?.commit()
        fenceBuffer?.waitUntilCompleted()
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: w * 4,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return bytes
    }

    /// (differing-byte %, meanAbsDiff, maxAbsDiff) — the GUI round's metric
    /// triple, printed for diagnostics even when the gate passes.
    nonisolated private static func diffMetrics(
        _ a: [UInt8], _ b: [UInt8]
    ) -> (pct: Double, mean: Double, max: Int) {
        precondition(a.count == b.count && !a.isEmpty)
        var differing = 0
        var total = 0.0
        var maxAbs = 0
        for i in 0..<a.count {
            let d = abs(Int(a[i]) - Int(b[i]))
            if d > 0 { differing += 1 }
            total += Double(d)
            maxAbs = max(maxAbs, d)
        }
        return (100 * Double(differing) / Double(a.count), total / Double(a.count), maxAbs)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(200))
        for _ in 0..<20 { await Task.yield() }
    }

    private func displayBytes(_ label: String) throws -> [UInt8] {
        let texture = try XCTUnwrap(editorState.displayTexture, "display missing at \(label)")
        return Self.readDisplayBytes(texture, metal: metal)
    }

    private func instance(_ opName: String) throws -> ModuleInstance {
        try XCTUnwrap(editorState.instances.first { $0.opName == opName })
    }

    /// Build the shared scenario state on THIS coordinator's editorState:
    /// layer「L」 with a layer-chain exposure (0.6) + a brush mask — the
    /// composite branch with every cache tier populated.
    private func buildLayerScenario() async throws -> UUID {
        // S0: the empty-chain layer (composite branch engaged).
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        await coordinator.layerStackDidChange(persist: false)

        // S1: a layer-chain module with visible params.
        let template = try instance("exposure")
        var record = template.clonedWithFreshIdentity()
        var params = try record.params(of: ExposureModule.self)
        params.exposure = 0.6
        try record.setParams(params, as: ExposureModule.self)
        record.enabled = true
        _ = editorState.addModuleToLayer(layerID: layer.id, template: record)
        await coordinator.layerStackDidChange(persist: false)

        // S1m: a brush mask on the layer (live + one commit).
        let stroke = BrushStroke(
            points: [
                BrushPoint(corner: MaskPoint(x: 0.2, y: 0.2), ctrl1: MaskPoint(x: 0.2, y: 0.2), ctrl2: MaskPoint(x: 0.2, y: 0.2)),
                BrushPoint(corner: MaskPoint(x: 0.5, y: 0.55), ctrl1: MaskPoint(x: 0.5, y: 0.55), ctrl2: MaskPoint(x: 0.5, y: 0.55)),
            ],
            radius: 0.06, hardness: 0.7, density: 1.0, opacity: 1.0)
        var live = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        live.mask = MaskSpec(drawn: DrawnMaskSpec(forms: [MaskForm(kind: .brush(stroke))]))
        editorState.applyLiveLayer(live)
        let committed = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        editorState.commitLayerEdit(committed, label: "mask brush")
        await coordinator.layerStackDidChange(persist: false)
        return layer.id
    }

    /// GUI 复验缝探针: the flat first frame vs the EMPTY-CHAIN composite
    /// render (mathematically identity) — the GUI round's 8.9% in-session
    /// flat-vs-composite divergence probe.
    func testFlatFirstFrameEqualsEmptyLayerComposite() async throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("GUI-22 real-sample fixture missing: \(sampleURL.path)")
        }
        let url = tempDirectory.appendingPathComponent("gui22-flat.ARW")
        try FileManager.default.copyItem(at: sampleURL, to: url)
        let decoded = try await RAWDecoder().decode(url)
        try await coordinator.load(url: url, decoded: decoded, instances: [], metal: metal)
        try await settle()
        let flat = try displayBytes("flat first frame")

        _ = editorState.addAdjustmentLayer() // EMPTY chain — identity composite
        await coordinator.layerStackDidChange(persist: false)
        try await settle()
        let composite = try displayBytes("empty-layer composite")

        let m = Self.diffMetrics(flat, composite)
        print("GUI22 flat-vs-emptyLayerComposite: pct=\(m.pct) mean=\(m.mean) max=\(m.max)")
    }

    // MARK: - the GUI-22 byte gate

    /// THE byte gate: warm-undo render of state S must equal the cold
    /// sidecar-restore render of S (and both equal S's first warm render),
    /// byte-for-byte on the real GUI-round sample (CIRAWFilter decode + the
    /// CI scaled-render leg — the synthetic float32 path is identity-managed
    /// and cannot exercise the seam). Skips when the sample is absent.
    func testUndoWarmRenderEqualsColdRestore() async throws {
        let sampleURL = URL(fileURLWithPath: #filePath) // .../Tests/LightamerTests/GUI22UndoWarmColdTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("GUI-22 real-sample fixture missing: \(sampleURL.path)")
        }
        let url = tempDirectory.appendingPathComponent("gui22.ARW")
        try FileManager.default.copyItem(at: sampleURL, to: url)
        // Both legs decode the SAME copied URL (a GUI cold restart re-opens
        // the same file at the same path — the contentDedupeID memo keys on
        // path ⊕ size ⊕ mtime).
        let decoded = try await RAWDecoder().decode(url)
        try await coordinator.load(url: url, decoded: decoded, instances: [], metal: metal)
        let layerID = try await buildLayerScenario()
        try await settle()

        // S1m first warm render — the baseline this state must always render to.
        let first = try displayBytes("S1m first")

        // The edit (S2): layer blend 正常 → 正片叠底 (the GUI round's edit),
        // then UNDO back to S1m — the warm re-render of the reverted state.
        var edited = try XCTUnwrap(editorState.adjustmentLayer(id: layerID))
        edited.blendMode = .multiply
        editorState.applyLiveLayer(edited)
        let commitMe = try XCTUnwrap(editorState.adjustmentLayer(id: layerID))
        editorState.commitLayerEdit(commitMe, label: "blend multiply")
        await coordinator.layerStackDidChange(persist: false)
        try await settle()
        let s2 = try displayBytes("S2 multiply")
        XCTAssertNotEqual(first, s2, "sanity: the blend edit must change the render")

        await coordinator.undo()
        try await settle()
        let warmUndo = try displayBytes("warm undo")
        let m1 = Self.diffMetrics(warmUndo, first)
        print("GUI22 warm-undo vs first-same-state: pct=\(m1.pct) mean=\(m1.mean) max=\(m1.max)")

        // COLD leg: a brand-new coordinator + editor state restores the SAME
        // sidecar (flushed at the undoed position) and renders S1m cold —
        // with a FRESH decode (the GUI cold restart re-decodes the file).
        await coordinator.flushSidecar()
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path),
                      "the sidecar must exist for the cold leg")

        let coldEditor = EditorState()
        let coldCoordinator = PipeCoordinator()
        coldEditor.attach(pipeCoordinator: coldCoordinator)
        coldCoordinator.attach(editorState: coldEditor)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coldCoordinator.attach(registry: registry)
        // Decode the SAME copied URL (a GUI cold restart re-opens the same
        // file at the same path — the contentDedupeID memo keys on it).
        let coldDecoded = try await RAWDecoder().decode(url)
        await coldCoordinator.load(
            url: url, decoded: coldDecoded, instances: [], metal: metal
        )
        try await settle()

        let coldTexture = try XCTUnwrap(coldEditor.displayTexture, "cold render missing")
        let cold = Self.readDisplayBytes(coldTexture, metal: metal)
        XCTAssertEqual(cold.count, first.count, "same plane geometry")

        let m2 = Self.diffMetrics(cold, first)
        print("GUI22 cold-restore vs first-same-state: pct=\(m2.pct) mean=\(m2.mean) max=\(m2.max)")
        let m3 = Self.diffMetrics(warmUndo, cold)
        print("GUI22 warm-undo vs cold-restore: pct=\(m3.pct) mean=\(m3.mean) max=\(m3.max)")

        // Iron fact #1: the cold restore renders the same bytes as the state's
        // first (uncontaminated) render.
        XCTAssertEqual(cold, first,
                       "GUI-22 iron fact #1: cold restore must equal the first-frame baseline")

        // THE GATE (GUI-22): the warm undo render must equal the cold render.
        XCTAssertEqual(warmUndo, cold,
                       "GUI-22: undo warm-path render must equal the cold-load render byte-for-byte")
    }
}
