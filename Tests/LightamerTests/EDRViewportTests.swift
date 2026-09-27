import AppKit
import CoreImage
import LightamerIOP
import Metal
import MetalKit
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 08-4 — the EDR viewport suite (IOP-HDR-05).
//
// T1 (this file's first section): the P4 API re-verification on the macOS 27
// host (the research §0 P4 spike's three-acceptance pinned as a test), the
// blit PSO dual-variant existence + regime pick, and the viewport EDR
// surface flip (on → the 16F/EDR/extendedLinearSRGB trio; off → the exact
// Phase-1 SDR surface restored).
//
// Hard red line (plan 纪律①): the toggle OFF state is a ZERO-PATH leg — the
// default surface must stay byte-identical in both behavior and property
// values; these tests pin the property face (the rendering face is pinned
// by the golden matrix + the T4 snapshot section below).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class EDRViewportTests: XCTestCase {

    private var device: (any MTLDevice)!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        device = MTLCreateSystemDefaultDevice()
    }

    // MARK: - T1: the P4 spike trio (macOS 27 behavior pin)

    /// Research §0 P4: `CAMetalLayer` accepts `.rgba16Float` +
    /// `wantsExtendedDynamicRangeContent` + `CGColorSpace(name:
    /// .extendedLinearSRGB)` — the spike's runtime acceptance, re-verified
    /// per run so an OS behavior regression surfaces HERE, not in a GUI轮.
    func testP4MetalLayerAcceptsEDRTrio() {
        let layer = CAMetalLayer()
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        layer.colorspace = linear
        XCTAssertEqual(layer.pixelFormat, .rgba16Float)
        XCTAssertTrue(layer.wantsExtendedDynamicRangeContent)
        XCTAssertTrue(layer.colorspace === linear, "extendedLinearSRGB must stick (P4)")
    }

    // MARK: - T1: the blit PSO dual variants + the regime pick

    /// The 08-4 red line "共存不替换": both color attachments build from the
    /// same blit shaders — the SDR pair is untouched (the existing
    /// lazy-built displayReady variant included) and the 16F variant
    /// exists alongside.
    func testBlitPSODualVariantsExist() {
        let sdr = EditorMTKView.Coordinator.makeBlitPipelineState(
            device: device, displayReady: false)
        let sdrDisplayReady = EditorMTKView.Coordinator.makeBlitPipelineState(
            device: device, displayReady: true)
        let edr = EditorMTKView.Coordinator.makeBlitPipelineState(
            device: device, displayReady: false, colorPixelFormat: .rgba16Float)
        XCTAssertNotNil(sdr, "legacy SDR blit PSO must build")
        XCTAssertNotNil(sdrDisplayReady, "display-ready SDR blit PSO must build")
        XCTAssertNotNil(edr, "the EDR 16F blit PSO variant must build")
    }

    /// The pick is the single source of truth for `draw`: EDR wins outright;
    /// OFF falls back to the exact 02-04 source-format probe.
    func testBlitRegimePickAllArms() {
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: true, sourceIsDisplayReady: true),
            .edr16F)
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: true, sourceIsDisplayReady: false),
            .edr16F, "EDR always blits the float32 colorout plane (T2)")
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: false, sourceIsDisplayReady: true),
            .displayReadySDR, "OFF + gamma-tail source = the 02-04 display-ready leg")
        XCTAssertEqual(
            EditorMTKView.Coordinator.blitRegime(
                edrActive: false, sourceIsDisplayReady: false),
            .legacyFloat, "OFF + float source = the Phase-1 legacy leg")
    }

    /// MTLClearColor is not Equatable (the macOS 27 SDK) — field-wise assert.
    private func assertClearColor(
        _ actual: MTLClearColor, equals expected: MTLClearColor,
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.red, expected.red, accuracy: 0, message, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0, message, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0, message, file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: 0, message, file: file, line: line)
    }

    // MARK: - T1: the viewport EDR surface flip

    /// ON: the trio applies to the live MTKView (16F drawable, EDR flag,
    /// extendedLinearSRGB, linear clear color). OFF: the exact makeNSView
    /// literals are restored (the zero-path red line, property face).
    func testEDRSurfaceFlipOnAndOff() throws {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        let coordinator = EditorMTKView.Coordinator(
            device: device, commandQueue: device.makeCommandQueue()!, sourceTexture: nil)

        // Simulate makeNSView's SDR surface (a RAW MTKView defaults to a
        // black clear color — the production view sets the canvas mat there).
        view.clearColor = EditorMTKView.Coordinator.canvasClearColor

        // OFF is the makeNSView state (defaults).
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        assertClearColor(
            view.clearColor, equals: EditorMTKView.Coordinator.canvasClearColor,
            "default = the SDR canvas mat")

        // ON: the P4 trio + the linear mat.
        coordinator.edrActive = true
        coordinator.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .rgba16Float)
        assertClearColor(
            view.clearColor, equals: EditorMTKView.Coordinator.canvasClearColorLinear,
            "EDR uses the LINEAR mat (extendedLinearSRGB interprets linear)")
        let metalLayer = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertTrue(metalLayer.wantsExtendedDynamicRangeContent)
        XCTAssertTrue(
            metalLayer.colorspace === CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            "EDR pins extendedLinearSRGB (research §7.1 择优)")
        // The linear mat is the sRGB decode of the encoded mat — the same
        // visual #161619 on both sides of the toggle.
        XCTAssertLessThan(
            view.clearColor.red, EditorMTKView.Coordinator.canvasClearColor.red,
            "linear decode of an sRGB-encoded value must be darker")

        // OFF: every property back to the SDR literal (the layer colorspace
        // itself re-attaches in the next draw via the D-COL2 follow).
        coordinator.edrActive = false
        coordinator.applyEDRDisplaySurface(to: view)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        assertClearColor(
            view.clearColor, equals: EditorMTKView.Coordinator.canvasClearColor,
            "OFF restores the SDR mat literal")
        XCTAssertFalse(metalLayer.wantsExtendedDynamicRangeContent)
    }

    // MARK: - T1: the coordinator state face (runtime override, not a doc param)

    /// The toggle flips coordinator state with NO image loaded (the guard
    /// keeps it legal — the soft proof `setSoftProof` shape) and the flag
    /// round-trips. History/instance non-entanglement is T4's trio.
    func testEDRToggleStateRoundTripWithoutImage() {
        let coordinator = PipeCoordinator()
        XCTAssertFalse(coordinator.edrDisplayEnabled, "default OFF = today's behavior")
        coordinator.setEDRDisplay(true)
        XCTAssertTrue(coordinator.edrDisplayEnabled)
        coordinator.setEDRDisplay(true) // idempotent: no second generation bump
        XCTAssertTrue(coordinator.edrDisplayEnabled)
        coordinator.setEDRDisplay(false)
        XCTAssertFalse(coordinator.edrDisplayEnabled)
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// Plan 08-4 T3 — the headroom monitor legs.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class EDRHeadroomMonitorTests: XCTestCase {

    /// The query's legal domain: the documented floor is 1.0 (SDR white —
    /// the compositor's clamp); a nil screen reports exactly 1.0; the real
    /// host screen (P4: SDR-only rig) reports >= 1.0. The badge state bit
    /// follows the value: hasEDRHeadroom ⇔ value > 1.0.
    func testHeadroomQueryLegalDomainAndBadgeBit() {
        XCTAssertEqual(EDRHeadroomMonitor.headroom(of: nil), 1.0,
                       "nil screen = the SDR-safe answer")
        let real = EDRHeadroomMonitor.headroom(of: NSScreen.main)
        XCTAssertGreaterThanOrEqual(real, 1.0, "headroom floor is 1.0")
        let monitor = EDRHeadroomMonitor()
        monitor.recompute()
        XCTAssertEqual(monitor.headroom, real, accuracy: 1e-9)
        XCTAssertEqual(monitor.hasEDRHeadroom, monitor.headroom > 1.0,
                       "the badge state bit is the value comparison")
        // The P4 rig's semantics: at exactly 1.0 the badge warning state is
        // active (and the toggle stays legal — no fallback exists to test).
        XCTAssertFalse((real == 1.0) && monitor.hasEDRHeadroom)
    }

    /// The two screen notifications drive re-queries — one bump per event
    /// (the跨屏-drag invalidation face).
    func testScreenNotificationsInvalidateMonitor() async throws {
        let monitor = EDRHeadroomMonitor()
        monitor.start()
        let afterStart = monitor.invalidationCount
        XCTAssertGreaterThanOrEqual(afterStart, 1, "start performs the initial query")

        // Let the observer tasks reach their `for await` subscription before
        // posting (a post racing the subscription is dropped — production
        // events arrive long after launch).
        try await Task.sleep(nanoseconds: 300_000_000)

        let target1 = afterStart + 1
        NotificationCenter.default.post(
            name: NSWindow.didChangeScreenNotification, object: nil)
        try await Self.waitForCount(target1, on: monitor)

        let target2 = monitor.invalidationCount + 1
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Self.waitForCount(target2, on: monitor)
    }

    private static func waitForCount(
        _ target: Int, on monitor: EDRHeadroomMonitor
    ) async throws {
        for _ in 0..<150 {
            if monitor.invalidationCount >= target { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("monitor invalidation did not land (wanted \(target), got \(monitor.invalidationCount))")
    }
}
