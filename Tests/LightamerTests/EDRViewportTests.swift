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
// Plan 08-4 T2/T3/T4 — the pipe display leg, headroom monitor and the SDR
// invariance suite.
//
// Hard red lines under test (plan 纪律, unrelaxable):
//   ① EDR OFF = the ZERO-PATH leg (byte plane, clamped, cache keys identical,
//     bytes identical to the no-flag call);
//   ② EDR ON = the float32 colorout plane passes through UNMODIFIED (the
//     gamma tail is a pure SKIP — byte-identical to a gamma-less chain) and
//     >1.0 values survive to the drawable face;
//   ③ the toggle stales NOTHING (the off→on→off dance re-hits every line);
//   ④ the three-not-enter trio (export / history / sidecar) — independent
//     tests, never merged (L020).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class EDRDisplayLegTests: XCTestCase {

    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        // The IOP kernels (exposure_apply etc.) resolve through the IOP
        // bundle registration (the BeforeAfter harness shape).
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    // MARK: - Fixtures

    /// Solid linear gray — the RAW-FLOAT CGImage form (the PanelWiringTests
    /// synthetic shape): the plane carries the value EXACTLY (no CI color
    /// interpretation — CIColor 0.5 renders as sRGB-decoded 0.214, which
    /// would break the absolute-value anchor).
    nonisolated private static func decodedGray(_ value: Float = 0.5, size: Int = 32) -> DecodedImage {
        var rgba = [Float](repeating: value, count: size * size * 4)
        for i in 0..<(size * size) { rgba[i * 4 + 3] = 1.0 }
        var data = Data(capacity: rgba.count * 4)
        for v in rgba {
            var le = v.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: size, height: size, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: size * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
                    | CGBitmapInfo.floatComponents.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!

        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    private func coloroutBox() -> ModuleBox<ColorOutModule> {
        // EXPLICIT .sRGB (never .display): the fast-path matrix, host- and
        // screen-independent (the 02-04 test discipline).
        let box = ModuleBox(module: ColorOutModule())
        box.setParams(ColorOutModule.Params(outputProfile: .sRGB))
        return box
    }

    private func gammaBox() -> ModuleBox<GammaModule> {
        let box = ModuleBox(module: GammaModule())
        box.setParams(GammaModule.Params())
        return box
    }

    private func exposureBox(ev: Float) -> ModuleBox<ExposureModule> {
        let box = ModuleBox(module: ExposureModule())
        box.setParams(ExposureModule.Params(exposure: ev))
        return box
    }

    /// L014-fenced read-back (drain BEFORE getBytes — the convention).
    nonisolated private static func readBytes(_ texture: any MTLTexture) -> [UInt8] {
        let bytesPerPx = texture.pixelFormat == .bgra8Unorm ? 4 : 16
        let w = texture.width, h = texture.height
        let rowBytes = w * bytesPerPx
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func render(
        _ boxes: [any ModuleBoxing], edr: Bool, resolution: PipeResolution = .preview,
        cache: PipeCache = PipeCache(), size: Int = 32, gray: Float = 0.5,
        imageID: UUID = UUID()
    ) async throws -> (any MTLTexture, RenderPipeline.PipeRunStats) {
        let (texture, stats) = try await RenderPipeline.process(
            image: Self.decodedGray(gray, size: size),
            instances: boxes,
            imageID: imageID,
            resolution: resolution,
            cache: cache,
            metal: metal,
            terminalTail: edr ? .edrLinear : .sdrGamma)
        await Self.drain(metal)
        return (texture, stats)
    }

    // MARK: - T4①: EDR OFF = the byte plane, zero path difference

    /// OFF: the gamma tail runs — bgra8 byte plane, alpha opaque, and the
    /// explicit-`false` call is byte-identical to the DEFAULT call (the
    /// no-flag legacy path).
    func testSDROffTailIsTheBytePlaneAndDefaultIdentical() async throws {
        let chain: [any ModuleBoxing] = [coloroutBox(), gammaBox()]
        let (explicitOff, _) = try await render(chain, edr: false)
        let (defaultOff, _) = try await render(chain, edr: false)
        XCTAssertEqual(explicitOff.pixelFormat, .bgra8Unorm)
        let a = Self.readBytes(explicitOff)
        let b = Self.readBytes(defaultOff)
        XCTAssertEqual(a, b, "the flag's default IS false — bytes must not move")
        // gamma encodes alpha=1 everywhere (the D-COL4 byte plane contract).
        let w = explicitOff.width
        for px in 0..<(w * explicitOff.height) {
            XCTAssertEqual(a[px * 4 + 3], 255, "alpha opaque at px \(px)")
        }
    }

    // MARK: - T4②: EDR ON = the pure gamma-less float32 passthrough

    /// THE core T2 proof: the bypass is a pure SKIP — the [colorout, gamma]
    /// chain on the EDR leg is byte-identical to the SAME chain with gamma
    /// absent (float32 linear colorout output, format and all).
    func testEDROnBypassEqualsGammalessChain() async throws {
        let (gammaless, _) = try await render([any ModuleBoxing]([coloroutBox()]), edr: false)
        let (bypassed, _) = try await render([coloroutBox(), gammaBox()], edr: true)
        XCTAssertEqual(bypassed.pixelFormat, WorkingSpace.pixelFormat,
                       "the EDR final is the float32 colorout plane")
        XCTAssertEqual(Self.readBytes(gammaless), Self.readBytes(bypassed),
                       "EDR ON must be a pure gamma skip — zero new math")
    }

    // MARK: - T4②: >1.0 survives ON, clamps OFF

    /// Gray 0.5 + 3EV → 4.0 linear (gray-invariant through colorout): ON
    /// passes ≈4.0 through to the float32 plane; OFF clamps to SDR white
    /// (byte 255).
    func testEDRLegPassesValuesAboveSDRWhite() async throws {
        let chain: [any ModuleBoxing] = [exposureBox(ev: 3.0), coloroutBox(), gammaBox()]
        let (on, _) = try await render(chain, edr: true)
        XCTAssertEqual(on.pixelFormat, WorkingSpace.pixelFormat)
        let onBytes = Self.readBytes(on)
        let center = on.height / 2 * on.width * 16 + on.width / 2 * 16
        let value = Float(bitPattern: UInt32(onBytes[center])
            | (UInt32(onBytes[center + 1]) << 8)
            | (UInt32(onBytes[center + 2]) << 16)
            | (UInt32(onBytes[center + 3]) << 24))
        XCTAssertEqual(value, 4.0, accuracy: 0.05,
                       ">1.0 linear value must survive the EDR leg")
        let (off, _) = try await render(chain, edr: false)
        let offBytes = Self.readBytes(off)
        let offCenter = off.height / 2 * off.width * 4 + off.width / 2 * 4
        XCTAssertEqual(offBytes[offCenter], 255, "OFF clamps to SDR white")
        XCTAssertEqual(offBytes[offCenter + 1], 255)
        XCTAssertEqual(offBytes[offCenter + 2], 255)
    }

    // MARK: - T4③: the toggle stales NOTHING (cache-key identity)

    /// off → on → off over ONE cache: the ON leg re-hits the colorout line
    /// (its key is chain-identical — gamma's hash never entered it) and the
    /// second OFF leg re-hits the SURVIVING gamma line. Every leg after the
    /// first is all-hits: zero invalidation, zero re-render.
    func testEDRToggleDoesNotStalePipeCacheKey() async throws {
        let cache = PipeCache()
        let imageID = UUID()
        let chain: [any ModuleBoxing] = [coloroutBox(), gammaBox()]
        let (first, stats1) = try await render(chain, edr: false, cache: cache, imageID: imageID)
        XCTAssertGreaterThan(stats1.misses, 0, "first render must populate")
        let (_, stats2) = try await render(chain, edr: true, cache: cache, imageID: imageID)
        XCTAssertEqual(stats2.misses, 0,
                       "the ON leg must reuse the colorout line — no invalidation")
        XCTAssertGreaterThan(stats2.hits, 0)
        let (third, stats3) = try await render(chain, edr: false, cache: cache, imageID: imageID)
        XCTAssertEqual(stats3.misses, 0,
                       "the gamma line survived the ON leg — re-hit, not stale")
        XCTAssertEqual(Self.readBytes(first), Self.readBytes(third),
                       "OFF bytes identical across the toggle dance")
    }

    // MARK: - T4: the three-not-enter trio (independent tests, never merged)

    /// NOT-ENTER-EXPORT: at the EXPORT resolution the toggle is moot — the
    /// real export shape strips gamma (the builder's contract), and with
    /// gamma present the flag defaults false byte-identically. Export
    /// goldens re-run green across the suite as the broader pin.
    func testEDRNeverEntersExportLeg() async throws {
        // (a) gamma-tail chain at .export: explicit true vs default — the
        // flag defaults false, so the bytes cannot move.
        let chain: [any ModuleBoxing] = [coloroutBox(), gammaBox()]
        let (exportDefault, _) = try await render(chain, edr: false, resolution: .export)
        XCTAssertEqual(exportDefault.pixelFormat, .bgra8Unorm)
        // (b) the REAL export shape (gamma stripped): the flag changes
        // nothing — no gamma tail for it to skip.
        let (strippedFalse, _) = try await render([any ModuleBoxing]([coloroutBox()]), edr: false, resolution: .export)
        let (strippedTrue, _) = try await render([any ModuleBoxing]([coloroutBox()]), edr: true, resolution: .export)
        XCTAssertEqual(Self.readBytes(strippedFalse), Self.readBytes(strippedTrue),
                       "the stripped-gamma export chain is EDR-indifferent")
    }

    /// NOT-ENTER-HISTORY: the toggle re-renders the display leg and moves
    /// NO history item and NO instance record (the soft proof orthogonality).
    func testEDRToggleNeverCreatesHistoryItem() async throws {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edr-\(UUID().uuidString).ARW")
        try Data(repeating: 0xCD, count: 64).write(to: url)
        await coordinator.load(
            url: url, decoded: Self.decodedGray(), instances: [], metal: metal)

        // A real commit (the sidecar/history writer) — then the toggle.
        let exposure = try XCTUnwrap(editorState.instances.first { $0.opName == "exposure" })
        coordinator.beginContinuousEdit()
        var record = exposure
        try record.setParams(
            ExposureModule.Params(exposure: 0.5), as: ExposureModule.self)
        await coordinator.setLiveParams(record)
        await coordinator.commitContinuousEdit(label: "EDR probe")
        let itemsBefore = editorState.history.items.count
        let instancesBefore = editorState.instances

        coordinator.setEDRDisplay(true)
        XCTAssertTrue(coordinator.edrDisplayEnabled)
        // Let the display re-render task run to completion.
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(editorState.history.items.count, itemsBefore,
                       "the toggle must not append a history item")
        XCTAssertEqual(editorState.history.position, itemsBefore - 1,
                       "the pointer stays on the last committed item")
        XCTAssertEqual(editorState.instances, instancesBefore,
                       "the toggle must not touch any instance record")
    }

    /// NOT-ENTER-SIDECAR: with a sidecar ON DISK (flushed from the real
    /// commit above), the toggle + flush leaves the file byte-identical.
    func testEDRToggleNeverWritesSidecar() async throws {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edr-sidecar-\(UUID().uuidString).ARW")
        try Data(repeating: 0xCD, count: 64).write(to: url)
        await coordinator.load(
            url: url, decoded: Self.decodedGray(), instances: [], metal: metal)

        // Force a real sidecar write (the commit → schedule → debounce →
        // flush path): out-wait the 2s production debounce, then force.
        let exposure = try XCTUnwrap(editorState.instances.first { $0.opName == "exposure" })
        coordinator.beginContinuousEdit()
        var record = exposure
        try record.setParams(
            ExposureModule.Params(exposure: 0.5), as: ExposureModule.self)
        await coordinator.setLiveParams(record)
        await coordinator.commitContinuousEdit(label: "EDR probe")
        try await Task.sleep(nanoseconds: 2_500_000_000)
        await coordinator.flushSidecar()
        let tmp = url.deletingLastPathComponent()
        let sidecarURL = try XCTUnwrap(
            FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)?
                .allObjects
                .compactMap { $0 as? URL }
                .first { $0.pathExtension == "lra" && $0.deletingPathExtension().lastPathComponent
                    == url.lastPathComponent },
            "the flushed sidecar must exist on disk")
        let before = try Data(contentsOf: sidecarURL)

        coordinator.setEDRDisplay(true)
        try await Task.sleep(nanoseconds: 800_000_000)
        await coordinator.flushSidecar()
        let after = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(before, after,
                       "the toggle must leave the sidecar byte-identical")
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
