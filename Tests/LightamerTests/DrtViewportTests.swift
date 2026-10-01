import AppKit
import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import MetalKit
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DrtViewportTests (Plan M2-6-3 T4, AC#4 — APP bundle,
// EditorMetalLegRegressionTests 同位 per the checker m2 correction; the 08-4
// EDRViewportTests live in the IOP bundle and keep pinning the three LEGACY
// arms — this file pins the DRT additions):
//
//   1. THE FOUR-STATE SURFACE MATRIX: isHdrEncoding × drt activation → the
//      drawable format / EDR flag / layer colorspace per arm (SDR-gamma,
//      EDR-linear legacy; DRT-SDR, DRT-HDR).
//   2. THE NON-DRT ZERO-DIFF FACE: a nil drtTail keeps EVERY legacy
//      property byte-identical (the bgra8 leg params, the EDR trio).
//   3. THE D-COL2 FOLLOW GATE (E3, checker 回注): the gate is OFF while a
//      DRT tail owns the surface — the encoding-space pin survives frames.
//   4. THE MUTUAL EXCLUSION: the manual EDR toggle is refused while the DRT
//      tail owns the display (the state-drift defense).
//   5. THE COLORSPECE TERMINAL FORMS: PQ/HLG/P3-PQ/HLG non-nil name
//      constants; the calibrated SDR forms; the linear face.
//   6. THE BLIT REGIME: the two new DRT arms + the legacy three untouched.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class DrtViewportTests: XCTestCase {

    private var device: (any MTLDevice)!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        device = MTLCreateSystemDefaultDevice()
        coordinator = PipeCoordinator()
        workspace = WorkspaceModel()
        coordinator.attach(workspace: workspace)
    }

    override func tearDown() async throws {
        coordinator = nil
        workspace = nil
        device = nil
        try await super.tearDown()
    }

    /// A record with the given encoding family.
    private func record(space: DrtEncodingSpace, eotf: DrtEotf) -> DrtRecord {
        var record = DrtRecord()
        record.encodingSpace = space
        record.encodingEotf = eotf
        return record
    }

    // MARK: - 1: the four-state surface matrix

    /// applyEDRDisplaySurface under a DRT tail: the SDR powers stay on the
    /// bgra8 drawable with the encoding-space tag (no EDR flag); the HDR
    /// encodings flip the 16F drawable + the EDR flag + the PQ/HLG tag.
    func testDrtSurfaceFlipFollowsTheEncoding() throws {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        let vc = EditorMTKView.Coordinator(
            device: device, commandQueue: device.makeCommandQueue()!, sourceTexture: nil)

        // DRT-SDR (rec709 / gamma 2.2): bgra8 + the calibrated space, NO
        // EDR content flag.
        let sdr = record(space: .rec709, eotf: .gamma22)
        vc.drtTailSurface = EditorMTKView.Coordinator.drtSurfaceSpec(for: sdr)
        vc.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm, "DRT-SDR stays on bgra8")
        let layer = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertFalse(layer.wantsExtendedDynamicRangeContent)
        XCTAssertNotNil(layer.colorspace)

        // DRT-HDR (rec2020 / PQ): 16F + EDR + the PQ terminal form.
        let hdr = record(space: .rec2020, eotf: .st2084)
        vc.drtTailSurface = EditorMTKView.Coordinator.drtSurfaceSpec(for: hdr)
        vc.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .rgba16Float, "DRT-HDR flips to 16F")
        XCTAssertTrue(layer.wantsExtendedDynamicRangeContent)
        XCTAssertEqual(
            layer.colorspace,
            CGColorSpace(name: CGColorSpace.itur_2100_PQ))

        // DRT-HLG: the HLG terminal form.
        vc.drtTailSurface = EditorMTKView.Coordinator.drtSurfaceSpec(
            for: record(space: .rec2020, eotf: .hlg))
        vc.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(
            layer.colorspace,
            CGColorSpace(name: CGColorSpace.itur_2100_HLG))

        // Legacy faces untouched: nil drtTail → the exact 08-4 behavior.
        vc.drtTailSurface = nil
        vc.edrActive = true
        vc.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .rgba16Float)
        XCTAssertEqual(
            layer.colorspace, CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        vc.edrActive = false
        vc.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        XCTAssertFalse(layer.wantsExtendedDynamicRangeContent)
    }

    // MARK: - 2: the non-DRT zero-diff face

    /// With NO drtTail, the view's update-shaped pushes produce the exact
    /// Phase-1/08-4 property values (the zero-path red line, property face).
    func testNonDrtPathKeepsTheLegacySurfaceByteForByte() throws {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        let vc = EditorMTKView.Coordinator(
            device: device, commandQueue: device.makeCommandQueue()!, sourceTexture: nil)
        let layer = try XCTUnwrap(view.layer as? CAMetalLayer)

        // makeNSView's literals.
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        XCTAssertFalse(layer.wantsExtendedDynamicRangeContent)

        // The coordinator accessor agrees with a bare workspace (no DRT).
        XCTAssertFalse(coordinator.drtTailActive)
        XCTAssertNil(coordinator.drtViewportSurface)

        // The blit regime's legacy arms read identically under the default
        // drtTailActive (the EDRViewportTests assertions, re-run through
        // the extended signature).
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: true, drtTailActive: false, sourceIsDisplayReady: true),
            .edr16F)
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: false, drtTailActive: false, sourceIsDisplayReady: true),
            .displayReadySDR)
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: false, drtTailActive: false, sourceIsDisplayReady: false),
            .legacyFloat)
    }

    // MARK: - 3: the D-COL2 follow gate (E3)

    /// The gate is active ONLY on the legacy SDR face. While a DRT tail owns
    /// the surface the gate stays OFF across frames — the encoding-space pin
    /// applied by `applyEDRDisplaySurface` is never overwritten.
    func testFollowGateStaysOffWhileDrtOwnsTheSurface() throws {
        // The gate truth table (the pure gate — the draw's only writer of
        // the screen-colorspace attach is gated by exactly this function).
        XCTAssertTrue(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: false, drtTailActive: false),
            "the legacy SDR face keeps the multi-display follow")
        XCTAssertFalse(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: true, drtTailActive: false),
            "the EDR pin already skipped the gate (08-4)")
        XCTAssertFalse(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: false, drtTailActive: true),
            "E3: the DRT encoding-space pin must survive frames")
        XCTAssertFalse(
            EditorMTKView.Coordinator.followGateActive(
                edrActive: true, drtTailActive: true),
            "the (unreachable) both-active face keeps the skip")

        // The frame-survival simulation: two consecutive frames under an
        // active gate would re-attach the SCREEN space (the pre-E3 defect);
        // under the DRT face neither frame touches the layer tag.
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        let vc = EditorMTKView.Coordinator(
            device: device, commandQueue: device.makeCommandQueue()!, sourceTexture: nil)
        let layer = try XCTUnwrap(view.layer as? CAMetalLayer)
        let sdr = record(space: .p3d65, eotf: .gamma22)
        vc.drtTailSurface = EditorMTKView.Coordinator.drtSurfaceSpec(for: sdr)
        vc.applyEDRDisplaySurface(to: view)
        let pinned = try XCTUnwrap(layer.colorspace)
        for _ in 0..<2 {
            // The draw's gate branch — off for the DRT face, so this body
            // (the screen attach) never runs.
            if EditorMTKView.Coordinator.followGateActive(
                edrActive: vc.edrActive, drtTailActive: vc.drtTailSurface != nil) {
                layer.colorspace = NSScreen.main?.colorSpace?.cgColorSpace
            }
        }
        XCTAssertTrue(
            layer.colorspace === pinned,
            "the DRT encoding-space pin must survive consecutive frames (E3)")
    }

    // MARK: - 4: the mutual exclusion

    /// The manual EDR toggle is REFUSED while a non-pristine DRT record is
    /// in effect (the state-machine backstop; the UI face disables it).
    func testManualEDRToggleIsBypassedWhileDrtOwnsTheTail() async throws {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let editorState = EditorState()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drt-viewport-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: LightamerSidecar.sidecarURL(for: url)) }
        try await coordinator.load(
            url: url,
            decoded: Self.decodedGradient(), instances: [], metal: metal)

        // Pristine: the toggle is legal (the exact 08-4 behavior).
        XCTAssertFalse(coordinator.drtTailActive)
        XCTAssertNil(coordinator.drtViewportSurface)
        coordinator.setEDRDisplay(true)
        XCTAssertTrue(coordinator.edrDisplayEnabled, "pristine: the toggle is legal")
        coordinator.setEDRDisplay(false)

        // A non-pristine record flips the gate; the toggle refuses.
        workspace.setSessionDrtRecord(
            record(space: .rec2020, eotf: .st2084), for: url)
        XCTAssertTrue(coordinator.drtTailActive)
        XCTAssertNotNil(coordinator.drtViewportSurface)
        coordinator.setEDRDisplay(true)
        XCTAssertFalse(
            coordinator.edrDisplayEnabled,
            "the DRT tail owns the display tail — the manual toggle is bypassed")
    }

    /// Synthetic gradient plane (EditorMetalLegRegressionTests' shape).
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

    // MARK: - 5: the colorspace terminal forms

    func testLayerColorSpaceTerminalForms() throws {
        // PQ/HLG: the plan's pinned native name constants (non-nil, exact).
        XCTAssertEqual(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .rec2020, eotf: .st2084)),
            CGColorSpace(name: CGColorSpace.itur_2100_PQ))
        XCTAssertEqual(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .rec2020, eotf: .hlg)),
            CGColorSpace(name: CGColorSpace.itur_2100_HLG))
        // The P3-encoding HDR variants take the P3 containers.
        XCTAssertEqual(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .p3d65, eotf: .st2084)),
            CGColorSpace(name: CGColorSpace.displayP3_PQ))
        XCTAssertEqual(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .p3d65, eotf: .hlg)),
            CGColorSpace(name: CGColorSpace.displayP3_HLG))

        // linear: the EDR-linear handoff face.
        XCTAssertEqual(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .rec709, eotf: .linear)),
            CGColorSpace(name: CGColorSpace.extendedLinearSRGB))

        // The calibrated SDR forms: built (non-nil) with the EOTF gamma.
        XCTAssertNotNil(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .rec709, eotf: .bt1886)))
        XCTAssertNotNil(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .p3d60, eotf: .gamma26)))
        XCTAssertNotNil(
            EditorMTKView.Coordinator.drtLayerColorSpace(
                record(space: .p3dci, eotf: .gamma26)))
        // Every (space, eotf) pair answers non-nil (the total face — a nil
        // would strand the viewport on the legacy surface).
        for space in DrtEncodingSpace.allCases {
            for eotf in DrtEotf.allCases {
                XCTAssertNotNil(
                    EditorMTKView.Coordinator.drtLayerColorSpace(
                        record(space: space, eotf: eotf)),
                    "\(space)/\(eotf) must resolve a colorspace")
                XCTAssertNotNil(
                    EditorMTKView.Coordinator.drtSurfaceSpec(
                        for: record(space: space, eotf: eotf)))
            }
        }
    }

    // MARK: - 6: the blit regime DRT arms

    func testBlitRegimeDrtArmsWinOverTheLegacyFaces() {
        // DRT wins outright; the format probe picks the arm's format face.
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: false, drtTailActive: true, sourceIsDisplayReady: true),
            .drtSDR, "the tail's bgra8 encoded plane takes the SDR passthrough")
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: false, drtTailActive: true, sourceIsDisplayReady: false),
            .drtFloat16, "the tail's 16F/float32 plane reuses the EDR blit path")
        // Even a manual EDR flag cannot out-rank the DRT tail (mutual).
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: true, drtTailActive: true, sourceIsDisplayReady: true),
            .drtSDR)
    }
}
