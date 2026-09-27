import LightamerCore
import MetalKit
import SwiftUI

/// SwiftUI ↔ MetalKit bridge for the editor viewport (FOUND-05, D-13).
///
/// `internal` to the app target (RESEARCH §9: the app target has no public
/// surface). Consumes Core's `MetalContext.device`/`.commandQueue` (public)
/// and the display texture `EditorState` produces via
/// `MetalContext.renderToTexture`.
///
/// Plan 13-3 T1 (D-13-CONTEXT-6) — the Phase 2 near-static reservation is
/// FLIPPED: the blit consumes the `ViewportState` zoom/pan/rotation through
/// `ViewportFit` (the single math source) — `fitQuad` forward-maps the
/// texture-corner uvs through the transform. Still `isPaused` +
/// `enableSetNeedsDisplay` redraw only on demand — texture change, zoom
/// state change, or drawable resize (UI-1 pitfall: ONLY on identity
/// change, never per-frame). The blit render pipeline state is built
/// ONCE in the Coordinator and reused every frame (RESEARCH §4).
/// `pixelFormat = .bgra8Unorm` per UI-SPEC (`.rgba16Float` reserved for the
/// Phase 8 EDR viewport).
///
/// UAT issue #1 root cause (Plan 02-01, fixed in `LightamerApp`): SwiftUI's
/// `WindowGroup` opened a NEW WINDOW per odoc Apple Event, stacking fresh
/// viewports that raced the shared `displayTexture`. The single-`Window`
/// scene is the fix; this view stayed a pure paused-mode blit throughout.
internal struct EditorMTKView: NSViewRepresentable {

    /// The shared GPU (injected `MetalContext.device`, D-14).
    let device: any MTLDevice

    /// The shared queue (injected `MetalContext.commandQueue`, D-15).
    let commandQueue: any MTLCommandQueue

    /// The rendered decoded image, owned by `EditorState`.
    @Binding var sourceTexture: (any MTLTexture)?

    /// 09-04 T7 (HIST-06) split blit variant: the BEFORE plane. nil = the
    /// legacy single-plane blit (byte-identical draw path — the default).
    var secondaryTexture: (any MTLTexture)?

    /// The split line as a fraction of the DRAWABLE width: everything LEFT
    /// of the line shows the secondary (before) plane, the rest shows the
    /// source (after). nil = no split. 0 = the whole viewport is the
    /// before plane (the hold-to-view-original form — a constant blit,
    /// zero renders).
    var splitFraction: Double?

    /// 13-3 T1: the zoom/pan/rotation state machine (environment-injected
    /// from the app root). The blit and the gesture face (T2) read it; the
    /// state itself lives in `ViewportState` (D-03b isolated).
    @Environment(ViewportState.self) private var viewportState

    func makeNSView(context: Context) -> MTKView {
        // 13-3 T2 (D-13-CONTEXT-6①): the AppKit GESTURE face — the
        // trackpad's native event stream is NSView's magnify/rotate/
        // scrollWheel overrides (SwiftUI gestures cannot express the
        // anchor/end-state/scroll-pan details on macOS). The subclass
        // forwards into the Coordinator, which mutates the shared
        // `ViewportState` (no second math) and arms one redraw.
        let view = ViewportMTKView(frame: .zero, device: device)
        view.delegate = context.coordinator
        view.gestureTarget = context.coordinator
        view.colorPixelFormat = .bgra8Unorm // UI-SPEC: Phase 1 display format
        view.isPaused = true // D-13: redraw on demand, not a 60fps loop
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.clearColor = Coordinator.canvasClearColor
        // UI-SPEC "MTKView Viewport Color": layer mat = neutral-1 canvas
        // (the Metal clear color handles the viewport; the layer background
        // covers the frame between Metal draws).
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.backgroundColor = NSColor(LightamerColors.canvas).cgColor
        }
        // UI-SPEC Accessibility: the viewport is a named region for
        // VoiceOver/XCUITest (MTKView is not exposed to the AX tree by
        // default — the shell's "editor viewport" region query relies on
        // this label). AppKit NSAccessibility setter methods, not UIKit
        // properties.
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(String(localized: "editor_viewport_label"))
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        // UI-1 pitfall prevention: the Coordinator owns per-frame state;
        // SwiftUI only pushes the SOURCE OF TRUTH, and only when it changes
        // (`===` identity — every pixelpipe pass produces a new texture).
        // Paused mode: arm exactly one redraw per texture change.
        var needsDisplay = false
        if !context.coordinator.hasSameSourceTexture(as: sourceTexture) {
            context.coordinator.sourceTexture = sourceTexture
            needsDisplay = true
        }
        // 09-04 T7: the compare-plane inputs ride the same push-once shape.
        if context.coordinator.secondaryTexture !== secondaryTexture {
            context.coordinator.secondaryTexture = secondaryTexture
            needsDisplay = true
        }
        if context.coordinator.splitFraction != splitFraction {
            context.coordinator.splitFraction = splitFraction
            needsDisplay = true
        }
        // 13-3 T1: the zoom/pan/rotation state push (same push-once shape
        // as the texture — a changed signature arms exactly one redraw).
        // The view's live geometry also feeds the state's remembered
        // sizes (the App-scene menu seam).
        let signature = Coordinator.ZoomSignature(
            zoom: viewportState.zoom,
            pan: viewportState.pan,
            rotationDegrees: viewportState.rotationDegrees)
        if context.coordinator.zoomSignature != signature {
            context.coordinator.zoomSignature = signature
            needsDisplay = true
        }
        if let texture = sourceTexture {
            viewportState.noteGeometry(
                viewportSize: view.bounds.size,
                textureSize: CGSize(width: texture.width, height: texture.height))
        }
        context.coordinator.viewportState = viewportState
        if needsDisplay {
            view.setNeedsDisplay(view.bounds)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(device: device, commandQueue: commandQueue, sourceTexture: sourceTexture)
    }

    // MARK: - Coordinator (per-frame render loop owner)

    final class Coordinator: NSObject, MTKViewDelegate {

        /// neutral-1 #161619 (UI-SPEC canvas mat) as the Metal clear color —
        /// sRGB-encoded values written raw into the `.bgra8Unorm` drawable.
        static let canvasClearColor = MTLClearColor(
            red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x19 / 255.0, alpha: 1.0
        )

        private let commandQueue: any MTLCommandQueue
        private let device: any MTLDevice
        /// Phase 1 PSO — legacy inline Rec2020→sRGB conversion (float32
        /// linear source). nil only if the app-bundle metallib/PSO failed
        /// (draw then just clears to canvas and the failure is logged).
        private var blitPipelineState: (any MTLRenderPipelineState)?
        /// 02-04 PSO — display-ready passthrough (gamma-tail `.bgra8Unorm`
        /// source; gamut+TRC applied in the pipe, SC#1). Built lazily.
        private var blitDisplayReadyPipelineState: (any MTLRenderPipelineState)?
        var sourceTexture: (any MTLTexture)?

        /// 09-04 T7: the before/after split inputs (nil texture = the
        /// legacy single-plane draw; nil fraction = no split line).
        var secondaryTexture: (any MTLTexture)?
        var splitFraction: Double?

        /// 13-3 T1: the pushed zoom/pan/rotation signature (change = one
        /// armed redraw — the same discipline as the texture push).
        struct ZoomSignature: Equatable {
            var zoom: Double
            var panX: CGFloat
            var panY: CGFloat
            var rotationDegrees: Double

            init(zoom: Double, pan: CGPoint, rotationDegrees: Double) {
                self.zoom = zoom
                self.panX = pan.x
                self.panY = pan.y
                self.rotationDegrees = rotationDegrees
            }
        }
        var zoomSignature = ZoomSignature(zoom: 1, pan: .zero, rotationDegrees: 0)

        /// 13-3 T2: the shared zoom state (environment-injected through
        /// `updateNSView`; app-lifetime, so `weak` is cycle-free).
        weak var viewportState: ViewportState?

        /// The live texture size for the gesture entries (zero when the
        /// viewport is empty — the state machine ignores degenerate sizes).
        private var liveTextureSize: CGSize {
            sourceTexture.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        }

        // MARK: 13-3 T2 gesture surface (ViewportMTKView forwards here)

        /// The shared mutation tail: run the state edit, mirror the
        /// signature (the next `updateNSView` push sees it as a no-op)
        /// and arm exactly one paused-mode redraw.
        @MainActor private func editViewport(
            in view: MTKView, _ edit: (ViewportState) -> Void
        ) {
            guard let viewportState else { return }
            edit(viewportState)
            zoomSignature = ZoomSignature(
                zoom: viewportState.zoom,
                pan: viewportState.pan,
                rotationDegrees: viewportState.rotationDegrees)
            view.setNeedsDisplay(view.bounds)
        }

        @MainActor func handleMagnify(
            _ delta: Double, at point: CGPoint, in view: MTKView
        ) {
            editViewport(in: view) { state in
                state.magnify(
                    delta: delta, anchoredAt: point,
                    viewportSize: view.bounds.size, textureSize: liveTextureSize)
            }
        }

        @MainActor func handleRotate(
            _ degrees: Double, at point: CGPoint, in view: MTKView
        ) {
            editViewport(in: view) { state in
                state.rotate(
                    deltaDegrees: degrees, anchoredAt: point,
                    viewportSize: view.bounds.size, textureSize: liveTextureSize)
            }
        }

        @MainActor func handleScrollPan(
            deltaX: Double, deltaY: Double, in view: MTKView
        ) {
            editViewport(in: view) { state in
                state.scrollPan(deltaX: deltaX, deltaY: deltaY)
            }
        }

        @MainActor func handleScrollZoom(
            ticks: Double, at point: CGPoint, in view: MTKView
        ) {
            editViewport(in: view) { state in
                state.scrollZoom(
                    ticks: ticks, anchoredAt: point,
                    viewportSize: view.bounds.size, textureSize: liveTextureSize)
            }
        }

        @MainActor func handleSmartMagnify(in view: MTKView) {
            editViewport(in: view) { state in
                state.smartMagnify(
                    viewportSize: view.bounds.size, textureSize: liveTextureSize)
            }
        }

        /// The colorspace last attached to the CAMetalLayer (D-COL2 — set
        /// only on change; the compositor re-reads it per present).
        private var attachedLayerColorSpace: CGColorSpace?

        init(device: any MTLDevice, commandQueue: any MTLCommandQueue, sourceTexture: (any MTLTexture)?) {
            self.device = device
            self.commandQueue = commandQueue
            self.sourceTexture = sourceTexture
            super.init()
            self.blitPipelineState = Self.makeBlitPipelineState(device: device, displayReady: false)
        }

        func hasSameSourceTexture(as texture: (any MTLTexture)?) -> Bool {
            switch (sourceTexture, texture) {
            case (nil, nil): return true
            case let (lhs?, rhs?): return lhs === rhs
            default: return false
            }
        }

        private static func makeBlitPipelineState(
            device: any MTLDevice, displayReady: Bool
        ) -> (any MTLRenderPipelineState)? {
            // The blit shaders live in the APP target → Bundle.main is the
            // correct library here (the framework-bundle gotcha applies to
            // Core/IOP kernels, not app shaders).
            guard let library = device.makeDefaultLibrary(),
                  let vertex = library.makeFunction(name: "editor_blit_vertex")
            else {
                AppError.logger.error("editor blit shader functions not found in app default.metallib")
                return nil
            }
            // D-17: the fragment's `display_ready` function constant — set
            // BOTH regimes' constants explicitly (no MSL defaults).
            let constants = MTLFunctionConstantValues()
            var ready = displayReady
            withUnsafeBytes(of: &ready) {
                constants.setConstantValue($0.baseAddress!, type: .bool, index: 0)
            }
            guard let fragment = try? library.makeFunction(
                name: "editor_blit_fragment", constantValues: constants
            ) else {
                AppError.logger.error("editor_blit_fragment specialization failed (displayReady=\(displayReady))")
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                AppError.logger.error("blit PSO creation failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        // MTKViewDelegate — MTKView invokes these on the main thread.

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Resize → re-blit at the new drawable size.
            view.setNeedsDisplay(view.bounds)
        }

        func draw(in view: MTKView) {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable
            else {
                // currentDrawable is nil transiently around window/file
                // switches; in isPaused mode nothing else re-arms the draw,
                // so a dropped frame here would stick as a black viewport.
                // Retry shortly.
                let bounds = view.bounds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak view] in
                    view?.setNeedsDisplay(bounds)
                }
                return
            }
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].storeAction = .store
            renderPass.colorAttachments[0].clearColor = Self.canvasClearColor

            // D-COL2 (Plan 02-04-05): attach the resolved display colorspace
            // to the CAMetalLayer so the gamma-encoded bytes (fast path:
            // P3/sRGB gamut; fallback: sRGB workalike) are interpreted
            // as-emitted — the compositor performs NO further matching.
            // Window's screen wins (multi-display follows the window).
            if let metalLayer = view.layer as? CAMetalLayer {
                let target = (view.window?.screen ?? NSScreen.main)?.colorSpace?.cgColorSpace
                    ?? metalLayer.colorspace
                if let target, target !== attachedLayerColorSpace {
                    metalLayer.colorspace = target
                    attachedLayerColorSpace = target
                }
            }

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }

            // endEncoding MUST precede commit — a defer here would run after
            // commit() and abort validation ("uncommitted encoder").
            if let texture = sourceTexture {
                // 02-04: pick the blit regime by SOURCE format — the pipe's
                // gamma tail produces .bgra8Unorm (display-ready);
                // everything else is the Phase 1 float32 linear plane.
                let displayReady = texture.pixelFormat == .bgra8Unorm
                let state: any MTLRenderPipelineState?
                if displayReady {
                    if blitDisplayReadyPipelineState == nil {
                        blitDisplayReadyPipelineState = Self.makeBlitPipelineState(
                            device: device, displayReady: true
                        )
                    }
                    state = blitDisplayReadyPipelineState
                } else {
                    state = blitPipelineState
                }
                if let state {
                    encoder.setRenderPipelineState(state)
                    var quad = Self.fitQuad(
                        textureSize: SIMD2(Float(texture.width), Float(texture.height)),
                        drawableSize: view.drawableSize,
                        boundsSize: view.bounds.size,
                        zoom: zoomSignature.zoom,
                        pan: CGPoint(x: zoomSignature.panX, y: zoomSignature.panY),
                        rotationDegrees: zoomSignature.rotationDegrees)
                    encoder.setVertexBytes(&quad, length: MemoryLayout<FitQuad>.stride, index: 0)

                    // 09-04 T7 (HIST-06) split blit: the SAME PSO + quad
                    // drawn twice under complementary SCISSOR rects — left
                    // of the line = the before plane, right = the after
                    // plane. Zero new GPU kernels (the split is raster
                    // clipping; both planes are resident cache lines). A
                    // fraction of 0 (the hold form) clips the after plane
                    // away entirely — the whole viewport shows before.
                    if let secondary = secondaryTexture, let fraction = splitFraction {
                        let width = Int(view.drawableSize.width)
                        let height = Int(view.drawableSize.height)
                        let splitX = min(max(Int((Double(width) * fraction).rounded()), 0), width)
                        encoder.setFragmentTexture(secondary, index: 0)
                        if splitX > 0 {
                            encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: splitX, height: height))
                            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        }
                        if splitX < width {
                            encoder.setScissorRect(MTLScissorRect(x: splitX, y: 0, width: width - splitX, height: height))
                            encoder.setFragmentTexture(texture, index: 0)
                            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        }
                        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: width, height: height))
                    } else {
                        encoder.setFragmentTexture(texture, index: 0)
                        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    }
                }
            } // else: no image yet — solid canvas mat (UI-SPEC "no image" viewport state)

            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// The viewport quad as NDC corners (04-06 GUI-2+3; 13-3 T1
        /// zoom/pan/rotation): the SINGLE source of truth is `ViewportFit`
        /// (the crop overlay's geometry) — the texture-corner uvs are
        /// forward-mapped through the `ViewportFit.transform` composition
        /// (zoom → rotation → pan about the fitted rect), then points →
        /// NDC via `2·p/size − 1` with the y axis flipped (SwiftUI
        /// top-left origin vs Metal NDC bottom-left).
        ///
        /// `boundsSize` (POINTS) drives both the transform and the NDC
        /// mapping whenever it is provided — the drawable is the bounds ×
        /// backing scale (a UNIFORM factor), so NDC is ratio-identical;
        /// the pan offsets are point-space and must not be rescaled. The
        /// identity state (defaults) reproduces the 04-02 fit quad
        /// byte-for-byte (CropOverlayTests pin the corners).
        /// Degenerate input ⇒ fullscreen quad (the ViewportFit guard's
        /// `.zero` would otherwise collapse the draw to nothing).
        static func fitQuad(
            textureSize: SIMD2<Float>, drawableSize: CGSize,
            boundsSize: CGSize? = nil,
            zoom: Double = 1, pan: CGPoint = .zero, rotationDegrees: Double = 0
        ) -> FitQuad {
            let texSize = CGSize(width: Double(textureSize.x), height: Double(textureSize.y))
            let viewport = boundsSize ?? drawableSize
            guard viewport.width >= 1, viewport.height >= 1,
                  texSize.width >= 1, texSize.height >= 1
            else {
                return FitQuad(
                    p0: SIMD2(-1, -1), p1: SIMD2(1, -1),
                    p2: SIMD2(-1, 1), p3: SIMD2(1, 1))
            }
            let transform = ViewportFit.transform(
                viewportSize: viewport, textureSize: texSize,
                zoom: zoom, pan: pan, rotationDegrees: rotationDegrees)
            func ndc(_ p: CGPoint) -> SIMD2<Float> {
                SIMD2(
                    Float(2 * p.x / viewport.width - 1),
                    Float(1 - 2 * p.y / viewport.height))
            }
            // Corner ↔ uv pairing is the SHADER's contract (the vertex
            // function pairs p0↔uv(0,1), p1↔uv(1,1), p2↔uv(0,0),
            // p3↔uv(1,0)) — identical slot-for-slot with the 04-02 code
            // (p0 was ndc(minX, maxY)); only the mapping INTO the slots
            // now routes through the transform.
            return FitQuad(
                p0: ndc(transform.point(atUV: SIMD2(0, 1))),
                p1: ndc(transform.point(atUV: SIMD2(1, 1))),
                p2: ndc(transform.point(atUV: SIMD2(0, 0))),
                p3: ndc(transform.point(atUV: SIMD2(1, 0))))
        }

        /// 13-3 T1: the Phase 2 "fit/100% controls arrive with zoom/pan"
        /// reservation is honored by `fitQuad` + `ViewportFit.transform`
        /// (the live blit leg since the 04-06 fitQuad retirement of the
        /// uniform-scale path). This doc-chain stub remains only to keep
        /// the eyedropper comment chain intact — the zoom/pan offsets are
        /// the `ViewportTransform` pan, never a second formula here.
        private static func aspectFitUniforms(
            textureSize: SIMD2<Float>, drawableSize: SIMD2<Float>
        ) -> BlitUniforms {
            // 04-02-T4: single-source math (ViewportFit); behavior
            // byte-identical (the guard + scale formula moved verbatim).
            // 04-06: RETIRED by fitQuad (kept for the eyedropper doc chain —
            // PipeCoordinator.viewportUV mirrors the fitted rect, not this).
            // 13-3: zoom/pan ride fitQuad via ViewportFit.transform.
            let scale = ViewportFit.blitScale(
                viewportSize: CGSize(width: Double(drawableSize.x), height: Double(drawableSize.y)),
                textureSize: CGSize(width: Double(textureSize.x), height: Double(textureSize.y)))
            return BlitUniforms(
                scale: SIMD2(Float(scale.x), Float(scale.y)), offset: SIMD2(0, 0)
            )
        }
    }
}
/// Layout mirror of `FitQuad` in `EditorBlitShader.metal`
/// (4× float2 NDC corners — 32 bytes, set via `setVertexBytes`).
struct FitQuad {
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
    var p2: SIMD2<Float>
    var p3: SIMD2<Float>
}

/// Layout mirror of `BlitUniforms` in `EditorBlitShader.metal`
/// (float2 scale; float2 offset — 16 bytes, set via `setVertexBytes`).
/// 04-06 RETIRED from the draw (fitQuad carries corners); kept for the
/// `aspectFitUniforms` doc chain until the eyedropper comment is updated.
private struct BlitUniforms {
    var scale: SIMD2<Float>
    var offset: SIMD2<Float>
}

// ─────────────────────────────────────────────────────────────────────────
// ViewportMTKView (Plan 13-3 T2, D-13-CONTEXT-6①) — the AppKit GESTURE
// surface. macOS trackpad gestures arrive as NSView event overrides with
// cursor anchors and continuous deltas; SwiftUI's gesture set cannot
// express the anchor/end-state/scroll-pan details, so the bridge
// subclasses the MTKView and forwards into the Coordinator (which owns
// the single `ViewportState` mutation + one armed redraw).
//
//   magnify       — pinch zoom, cursor-anchored (event.magnification is
//                   the cumulative factor per gesture; each callback
//                   carries the delta since the LAST call, so the state
//                   machine's multiplicative apply composes).
//   rotate        — two-finger rotation, cursor-anchored (degrees).
//   scrollWheel   — two-finger pan (continuous deltas, content follows
//                   the fingers); ⌘-scroll = wheel zoom (the mouse
//                   fallback leg).
//   smartMagnify  — the two-finger double-tap: fit ↔ 100%.
//
// The 手感 (feel) is Manual-Only registered (L032: synthetic CGEvents do
// not reach the SwiftUI/AppKit tooling in headless drivers); the SIGN and
// anchoring MATH are pinned by ViewportTransformTests.
// ─────────────────────────────────────────────────────────────────────────
internal final class ViewportMTKView: MTKView {

    weak var gestureTarget: EditorMTKView.Coordinator?

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        // event.magnification is a 1-centered per-event factor (~1.02 =
        // +2%); the state machine takes a 0-centered delta — the seam is
        // the −1 here (zoom · (1 + (mag − 1)) = zoom · mag).
        gestureTarget?.handleMagnify(
            Double(event.magnification) - 1,
            at: convert(event.locationInWindow, from: nil),
            in: self)
    }

    override func rotate(with event: NSEvent) {
        super.rotate(with: event)
        gestureTarget?.handleRotate(
            Double(event.rotation),
            at: convert(event.locationInWindow, from: nil),
            in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        if event.modifierFlags.contains(.command) {
            // ⌘-scroll zoom (the keyboard-mouse fallback; delta flips so
            // scroll-up zooms in — the universal viewer convention).
            gestureTarget?.handleScrollZoom(
                ticks: event.scrollingDeltaY,
                at: convert(event.locationInWindow, from: nil),
                in: self)
        } else {
            gestureTarget?.handleScrollPan(
                deltaX: Double(event.scrollingDeltaX),
                deltaY: Double(event.scrollingDeltaY),
                in: self)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        gestureTarget?.handleSmartMagnify(in: self)
    }
}
