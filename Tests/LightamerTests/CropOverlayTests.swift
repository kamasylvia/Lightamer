@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import CoreGraphics
import Metal
import XCTest

// CropOverlayTests (Plan 04-02-T4) — the overlay math + D-H1 routing,
// exercised PROGRAMMATICALLY (no UI): hit-test vectors, rect geometry,
// aspect-lock math, ViewportFit single-source parity, and the
// live-disabled drag trio (exactly ONE history item; live ticks carry
// enabled=false; commit carries enabled=true).
//
// The plan names this file `CropOverlayUITests` (XCUITest); the XCUITest
// leg is Manual-Only on this host (L011: automation-mode grant needs an
// unlocked console — AppLaunchTests documents the same standing
// decision). This file is the AUTOMATED leg: every assertion the plan
// lists that is computable without a running app lives here
// (trio count, enabled flags, record params); the Manual-Only table in
// 04-VALIDATION.md keeps the viewport-texture-size + visual rows.
@MainActor
final class CropOverlayTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cropoverlay-\(UUID().uuidString)", isDirectory: true)
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

    private func makeSyntheticImage() throws -> DecodedImage {
        let width = 32, height = 32
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

    private func loadSynthetic() async throws {
        let url = tempDirectory.appendingPathComponent("image.exr")
        try await coordinator.load(
            url: url, decoded: makeSyntheticImage(), instances: [], metal: metal
        )
    }

    private func crop() throws -> ModuleInstance {
        try XCTUnwrap(editorState.instances.first { $0.opName == CropModule.opName })
    }

    private func withCrop(
        _ instance: ModuleInstance, _ mutate: (inout CropModule.Params) -> Void, enabled: Bool? = nil
    ) throws -> ModuleInstance {
        var params = try instance.params(of: CropModule.self)
        mutate(&params)
        var record = instance
        if let enabled { record.enabled = enabled }
        try record.setParams(params, as: CropModule.self)
        return record
    }

    private func historyCount() -> Int { editorState.history.items.count }

    // MARK: - Hit-test vectors (dt _grab_region_t)

    /// Corners/edges/center/outside map to the bit field (dt
    /// `_gui_get_grab` order — corners emerge as the OR combos).
    func testHitTestMapsHandlesToGrabRegions() {
        let box = CGRect(x: 100, y: 100, width: 200, height: 120)
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 105, y: 105), rectBox: box), [.top, .left])
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 295, y: 105), rectBox: box), [.top, .right])
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 295, y: 215), rectBox: box), [.bottom, .right])
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 105, y: 215), rectBox: box), [.bottom, .left])
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 200, y: 105), rectBox: box), .top)
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 200, y: 215), rectBox: box), .bottom)
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 105, y: 160), rectBox: box), .left)
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 295, y: 160), rectBox: box), .right)
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 200, y: 160), rectBox: box), .center)
        XCTAssertEqual(cropHitTest(point: CGPoint(x: 50, y: 50), rectBox: box), .none)
    }

    // MARK: - Overlay rect math

    /// Fractions ⇄ viewport box round-trip through the fitted rect.
    func testOverlayRectRoundTripsThroughFittedRect() {
        let fitted = CGRect(x: 50, y: 20, width: 400, height: 300)
        let view = CropOverlayView(
            fittedRect: fitted,
            cropRect: CropOverlayRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75, lockedAspect: nil),
            isDimmed: false, showsPhiGrid: false)
        let box = view.rectBox(for: CropOverlayRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75, lockedAspect: nil))
        XCTAssertEqual(box, CGRect(x: 150, y: 95, width: 200, height: 150))
        let back = view.overlayRect(for: box)
        XCTAssertEqual(back.left, 0.25, accuracy: 1e-9)
        XCTAssertEqual(back.top, 0.25, accuracy: 1e-9)
        XCTAssertEqual(back.right, 0.75, accuracy: 1e-9)
        XCTAssertEqual(back.bottom, 0.75, accuracy: 1e-9)
    }

    /// Aspect lock: short side sticks, long side follows (16:9 drag
    /// widening a square shrinks the height... precisely: keeps w/h).
    func testAspectLockKeepsShortSide() {
        let rect = CropOverlayRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.6, lockedAspect: 16.0 / 9.0)
        let locked = rect.withAspectLocked(anchor: CGPoint(x: 0, y: 0))
        XCTAssertEqual(locked.width / locked.height, 16.0 / 9.0, accuracy: 1e-9)
        // Freehand passes through the clamp only.
        let free = CropOverlayRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.6, lockedAspect: nil)
        XCTAssertEqual(free.withAspectLocked(anchor: CGPoint(x: 0, y: 0)).clamped(), free.clamped())
    }

    // MARK: - ViewportFit single-source parity

    /// The extracted math reproduces both call sites: blit scale matches
    /// the `aspectFitUniforms` formula; uv matches the `viewportUV`
    /// letterbox semantics (EyedropperTests vectors).
    func testViewportFitMatchesBothCallSites() {
        // Blit scale: 64×64 texture in a 200×100 viewport → fit = 100/64.
        let scale = ViewportFit.blitScale(
            viewportSize: CGSize(width: 200, height: 100),
            textureSize: CGSize(width: 64, height: 64))
        XCTAssertEqual(scale.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(scale.y, 1.0, accuracy: 1e-9)
        // Eyedropper vector: tall image in a wide viewport — letterbox
        // click rejected, center click maps.
        XCTAssertNil(ViewportFit.uv(
            at: CGPoint(x: 50, y: 50), viewportSize: CGSize(width: 200, height: 100),
            textureSize: CGSize(width: 64, height: 128)))
        let inside = ViewportFit.uv(
            at: CGPoint(x: 100, y: 50), viewportSize: CGSize(width: 200, height: 100),
            textureSize: CGSize(width: 64, height: 128))
        XCTAssertNotNil(inside)
        // Coordinator delegates (same values through the public seam).
        XCTAssertNil(PipeCoordinator.viewportUV(
            at: CGPoint(x: 50, y: 50), viewportSize: CGSize(width: 200, height: 100),
            textureSize: SIMD2(64, 128)))
    }

    /// 04-06 GUI-2+3: `fitQuad` emits the fitted rect as NDC corners —
    /// wide texture in a square viewport ⇒ full-width band; tall texture
    /// ⇒ full-height band; degenerate ⇒ fullscreen. NDC corners must match
    /// `ViewportFit.fittedRect` point-for-point (blit == overlay geometry).
    func testFitQuadMatchesFittedRect() {
        func ndc(_ p: CGPoint, _ size: CGSize) -> SIMD2<Float> {
            SIMD2(Float(2 * p.x / size.width - 1), Float(1 - 2 * p.y / size.height))
        }
        // 3:2 landscape (300×200) in a 200×200 viewport → 200×133 band.
        let wide = EditorMTKView.Coordinator.fitQuad(
            textureSize: SIMD2(300, 200), drawableSize: CGSize(width: 200, height: 200))
        let wideRect = ViewportFit.fittedRect(
            viewportSize: CGSize(width: 200, height: 200),
            textureSize: CGSize(width: 300, height: 200))
        XCTAssertEqual(wide.p0.x, ndc(CGPoint(x: wideRect.minX, y: wideRect.maxY), CGSize(width: 200, height: 200)).x, accuracy: 1e-5)
        XCTAssertEqual(wide.p0.y, ndc(CGPoint(x: wideRect.minX, y: wideRect.maxY), CGSize(width: 200, height: 200)).y, accuracy: 1e-5)
        XCTAssertEqual(wide.p3.x, ndc(CGPoint(x: wideRect.maxX, y: wideRect.minY), CGSize(width: 200, height: 200)).x, accuracy: 1e-5)
        XCTAssertEqual(wide.p3.y, ndc(CGPoint(x: wideRect.maxX, y: wideRect.minY), CGSize(width: 200, height: 200)).y, accuracy: 1e-5)
        // No overhang: band edges strictly inside NDC on the letterboxed axis.
        XCTAssertGreaterThan(wide.p0.y, -1)
        XCTAssertLessThan(wide.p2.y, 1)
        XCTAssertEqual(wide.p0.x, -1, accuracy: 1e-5)
        XCTAssertEqual(wide.p1.x, 1, accuracy: 1e-5)
        // 2:3 portrait (200×300) in a 200×200 viewport → 133×200 band.
        let tall = EditorMTKView.Coordinator.fitQuad(
            textureSize: SIMD2(200, 300), drawableSize: CGSize(width: 200, height: 200))
        XCTAssertEqual(tall.p0.y, -1, accuracy: 1e-5)
        XCTAssertEqual(tall.p2.y, 1, accuracy: 1e-5)
        XCTAssertGreaterThan(tall.p0.x, -1)
        XCTAssertLessThan(tall.p1.x, 1)
        // Degenerate ⇒ fullscreen quad (never a collapsed draw).
        let deg = EditorMTKView.Coordinator.fitQuad(
            textureSize: SIMD2(0, 0), drawableSize: CGSize(width: 200, height: 200))
        XCTAssertEqual(deg.p0.x, -1, accuracy: 1e-5)
        XCTAssertEqual(deg.p3.x, 1, accuracy: 1e-5)
    }

    // MARK: - D-H1 live-disabled drag (T0 (a))

    /// Overlay drag shape: begin → N live ticks (enabled=false, zero
    /// history) → commit (enabled=true, exactly ONE item). The host's
    /// `liveSnapshot` helper builds both snapshots from the record.
    func testOverlayDragCommitsOnceWithLiveDisabled() async throws {
        try await loadSynthetic()
        let record = try crop()
        let host = CropOverlayHost(
            viewportSize: CGSize(width: 200, height: 200),
            displaySize: CGSize(width: 32, height: 32),
            cropRecord: record, isDragging: false)

        coordinator.beginContinuousEdit()
        for tick in 1...8 {
            let rect = CropOverlayRect(
                left: 0.1 + Double(tick) * 0.01, top: 0.1,
                right: 0.9, bottom: 0.9, lockedAspect: nil)
            let live = try XCTUnwrap(host.liveSnapshot(from: record, rect: rect, enabled: false))
            XCTAssertFalse(live.enabled, "live ticks render full-frame (T0 (a))")
            await coordinator.setLiveParams(live)
            XCTAssertEqual(historyCount(), 0, "tick \(tick): zero history")
        }
        let final = CropOverlayRect(left: 0.18, top: 0.1, right: 0.9, bottom: 0.9, lockedAspect: nil)
        let commit = try XCTUnwrap(host.liveSnapshot(from: record, rect: final, enabled: true))
        await coordinator.setLiveParams(commit)
        await coordinator.commitContinuousEdit(label: String(localized: "history_crop"))

        XCTAssertEqual(historyCount(), 1, "overlay drag = exactly ONE item")
        let committed = try crop()
        XCTAssertTrue(committed.enabled, "commit re-enables the crop")
        let params = try committed.params(of: CropModule.self)
        XCTAssertEqual(Double(params.left), 0.18, accuracy: 1e-6)
        XCTAssertEqual(committed.id, record.id, "same instance UUID end-to-end")
    }

    /// The pristine seed carries the crop instance (T5 panel + overlay
    /// share it) at full-frame neutral.
    func testPristineSeedCarriesNeutralCrop() async throws {
        try await loadSynthetic()
        let record = try crop()
        let params = try record.params(of: CropModule.self)
        XCTAssertEqual(params.left, 0)
        XCTAssertEqual(params.top, 0)
        XCTAssertEqual(params.right, 1)
        XCTAssertEqual(params.bottom, 1)
        XCTAssertTrue(record.enabled)
    }
}
