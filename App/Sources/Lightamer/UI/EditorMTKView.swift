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
/// `pixelFormat = .bgra8Unorm` per UI-SPEC — and the Phase 8 reservation on
/// the next two lines is now HONORED (Plan 08-4 T1, IOP-HDR-05): the
/// Coordinator builds a SECOND blit PSO with a `.rgba16Float` color
/// attachment (both PSOs coexist; the EDR toggle picks — the SDR path is
/// byte-identical). EDR ON flips the whole display surface at once
/// (`applyEDRDisplaySurface`): 16F drawable + `wantsExtendedDynamicRange
/// Content` + `extendedLinearSRGB` (linear interpretation — the pipe feeds
/// the linear colorout plane, 08-4 T2) + a LINEAR clear color.
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

    /// 08-4 T1 (IOP-HDR-05): the viewport-level HDR preview toggle — a
    /// DISPLAY-leg runtime override (never a document parameter, the soft
    /// proof same-position contract). Default `false` = the exact Phase-1
    /// SDR surface (zero path difference). M2-6-3 KD-4: BYPASSED while a
    /// DRT tail owns the display surface (`drtTail != nil` — the mutual
    /// convergence; the coordinator's setEDRDisplay guard is the state
    /// backstop and this prop simply reads false there).
    var edrActive: Bool = false

    /// M2-6-3 T4 (KD-4): the DRT tail's viewport surface spec. nil = no DRT
    /// tail (the legacy/EDR faces above, byte-for-byte unchanged). Non-nil:
    /// the DRT tail owns the display surface — the drawable format and the
    /// CAMetalLayer colorspace follow the record's encoding (the four-state
    /// surface, see `applyEDRDisplaySurface`).
    var drtTail: DrtSurfaceSpec?

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
        // 08-4 T1: the EDR surface flip — property writes ONLY on change
        // (an untouched default never touches the layer, so the SDR leg
        // stays byte-identical down to property traffic).
        if context.coordinator.edrActive != edrActive {
            context.coordinator.edrActive = edrActive
            context.coordinator.applyEDRDisplaySurface(to: view)
            needsDisplay = true
        }
        // M2-6-3 T4 (KD-4): the DRT surface flip — the same push-once shape.
        if context.coordinator.drtTailSurface != drtTail {
            context.coordinator.drtTailSurface = drtTail
            context.coordinator.applyEDRDisplaySurface(to: view)
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

        /// The same mat in LINEAR terms (08-4 T1): the EDR drawable is
        /// tagged `extendedLinearSRGB`, which the compositor interprets as
        /// LINEAR values — the visual #161619 mat therefore needs the
        /// sRGB-decoded components there (the SDR drawable holds the
        /// ENCODED bytes raw; the pair keeps the mat identical across the
        /// toggle).
        static let canvasClearColorLinear = MTLClearColor(
            red: srgbDecode(0x16 / 255.0),
            green: srgbDecode(0x16 / 255.0),
            blue: srgbDecode(0x19 / 255.0), alpha: 1.0
        )

        /// The exact sRGB EOTF decode (the inverse of gamma's encode form,
        /// D-COL4).
        private static func srgbDecode(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        private let commandQueue: any MTLCommandQueue
        private let device: any MTLDevice
        /// Phase 1 PSO — legacy inline Rec2020→sRGB conversion (float32
        /// linear source). nil only if the app-bundle metallib/PSO failed
        /// (draw then just clears to canvas and the failure is logged).
        private var blitPipelineState: (any MTLRenderPipelineState)?
        /// 02-04 PSO — display-ready passthrough (gamma-tail `.bgra8Unorm`
        /// source; gamut+TRC applied in the pipe, SC#1). Built lazily.
        private var blitDisplayReadyPipelineState: (any MTLRenderPipelineState)?
        /// 08-4 T1 PSO — the EDR variant: SAME blit shaders, `.rgba16Float`
        /// color attachment (the :20-21 reservation honored). Coexists with
        /// the two SDR PSOs; the EDR toggle picks it. Built lazily. The
        /// EDR leg always blits the pipe's float32 linear colorout plane
        /// (T2 strips the gamma clamp), so only the `displayReady: false`
        /// specialization exists.
        private var blitEDRPipelineState: (any MTLRenderPipelineState)?
        var sourceTexture: (any MTLTexture)?

        /// 08-4 T1: the pushed EDR toggle (change = one surface flip + one
        /// armed redraw — the same push-once discipline as the texture).
        var edrActive = false

        /// M2-6-3 T4 (KD-4): the pushed DRT tail surface (nil = absent).
        /// This is the viewport-side `drtTailActive` mirror the E3 follow
        /// gate and the blit regime read.
        var drtTailSurface: DrtSurfaceSpec?

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

        // MARK: 08-4 T1 — the EDR display surface (IOP-HDR-05)

        /// Flip the whole viewport display surface for the EDR toggle.
        ///
        /// ON: `.rgba16Float` drawable + `wantsExtendedDynamicRangeContent`
        /// + `extendedLinearSRGB` (the P4-verified trio, research §0 P4) +
        /// the LINEAR clear color. The compositor then interprets frame-
        /// buffer values as linear — the pipe feeds the linear colorout
        /// plane (T2's `edrDisplayLeg`) and >1.0 values render as EDR
        /// headroom (SC#3: headroom is NOT a different color space).
        ///
        /// OFF: the exact Phase-1 SDR surface — every property restored to
        /// the `makeNSView` literals. The layer colorspace re-attach rides
        /// the per-frame D-COL2 follow in `draw` (the SDR path remains the
        /// only writer of that property; the tracker is nil-ed so the next
        /// off draw re-attaches). @MainActor: the NSView/layer property
        /// writes (called from `updateNSView`).
        ///
        /// M2-6-3 T4 (KD-4) — the FOUR-STATE surface: while a DRT tail owns
        /// the display (`drtTailSurface != nil`) the record's encoding
        /// decides, EDGING OUT both legacy faces:
        ///   • DRT-SDR (power/BT.1886): `.bgra8Unorm` drawable + the
        ///     encoding space's CGColorSpace (the gamma-tail precedent —
        ///     software encode + layer tag match);
        ///   • DRT-HDR (st2084/hlg): `.rgba16Float` + EDR content + the
        ///     PQ/HLG terminal colorspace form;
        ///   • DRT-linear (persistable, UI-unreachable): the float32 plane
        ///     rides the EDR-linear face (16F + extendedLinearSRGB — the
        ///     headroom-surviving handoff the tail format already chose).
        /// The manual EDR toggle is MUTUALLY EXCLUSIVE here by construction
        /// (the coordinator refuses the toggle while the tail is active).
        @MainActor
        func applyEDRDisplaySurface(to view: MTKView) {
            if let drt = drtTailSurface {
                view.colorPixelFormat = drt.hdrDrawable ? .rgba16Float : .bgra8Unorm
                view.clearColor =
                    drt.hdrDrawable ? Self.canvasClearColorLinear : Self.canvasClearColor
                guard let metalLayer = view.layer as? CAMetalLayer else { return }
                metalLayer.wantsExtendedDynamicRangeContent = drt.hdrDrawable
                metalLayer.colorspace = drt.layerColorSpace
                attachedLayerColorSpace = nil
                return
            }
            view.colorPixelFormat = edrActive ? .rgba16Float : .bgra8Unorm
            view.clearColor = edrActive ? Self.canvasClearColorLinear : Self.canvasClearColor
            guard let metalLayer = view.layer as? CAMetalLayer else { return }
            metalLayer.wantsExtendedDynamicRangeContent = edrActive
            if edrActive {
                // Research §7.1 择优定案: extendedLinearSRGB directly (no
                // stable public API queries the display's native EDR space;
                // the WWDC convention path). COLOR-4: headroom is expressed
                // in THIS space, never as a second colorspace.
                metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
                attachedLayerColorSpace = nil
            }
        }

        /// The blit regime pick (08-4 T1; the testable single source —
        /// `EDRViewportTests` pins all three legacy arms, `DrtViewportTests`
        /// the two DRT arms). DRT wins outright while the tail owns the
        /// surface: the tail's final plane IS the display-ready encoded
        /// plane (bgra8 → the passthrough SDR regime; 16F/float32 → the
        /// EDR 16F blit path reuse, KD-4), so the source-format probe below
        /// picks the DRT arm's format face.
        enum BlitRegime: Equatable {
            case legacyFloat
            case displayReadySDR
            case edr16F
            /// The DRT tail's software-encoded bgra8 plane — the same
            /// passthrough blit as displayReadySDR; the arm exists so the
            /// regime is explicit about WHO owns the surface (tests).
            case drtSDR
            /// The DRT tail's 16F (HDR) / float32 (linear) plane — the EDR
            /// leg's direct-write blit path reused (KD-4).
            case drtFloat16
        }

        static func blitRegime(
            edrActive: Bool, drtTailActive: Bool = false,
            sourceIsDisplayReady: Bool
        ) -> BlitRegime {
            if drtTailActive {
                return sourceIsDisplayReady ? .drtSDR : .drtFloat16
            }
            if edrActive { return .edr16F }
            return sourceIsDisplayReady ? .displayReadySDR : .legacyFloat
        }

        /// The D-COL2 follow gate (M2-6-3 E3, checker 回注): the per-frame
        /// screen-colorspace attach must run ONLY on the legacy SDR face —
        /// an EDR pin (08-4) or a DRT encoding-space pin (this plan) would
        /// otherwise be overwritten EVERY frame (the DRT-SDR原色匹配 would
        /// silently die). `drtTailActive` is the viewport-side mirror
        /// (`drtTailSurface != nil`).
        static func followGateActive(edrActive: Bool, drtTailActive: Bool) -> Bool {
            !edrActive && !drtTailActive
        }

        /// internal for `EDRViewportTests` (the dual-variant existence pin);
        /// app callers are the Coordinator itself.
        static func makeBlitPipelineState(
            device: any MTLDevice, displayReady: Bool,
            colorPixelFormat: MTLPixelFormat = .bgra8Unorm
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
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
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
            // 08-4 acceptance fix: the clear color must follow the active
            // regime — the 16F EDR drawable is tagged extendedLinearSRGB
            // (linear interpretation), so clearing it with the SDR-ENCODED
            // mat bytes read them as linear (a ~10x brighter mat). The
            // OFF arm carries the exact Phase-1 literal (zero path
            // difference); the ON arm is D-T1-3's linear decode — the same
            // value `applyEDRDisplaySurface` parks in `view.clearColor`
            // (this per-frame assignment is the authoritative one because
            // the render pass descriptor is rebuilt by MTKView).
            // M2-6-3 KD-4: the DRT faces follow the same rule (the HDR
            // drawable gets the linear mat — the PQ-interpretation shade
            // is a registered walkthrough observation, not a gate).
            let drtActive = drtTailSurface != nil
            renderPass.colorAttachments[0].clearColor =
                (edrActive || (drtActive && drtTailSurface!.hdrDrawable))
                    ? Self.canvasClearColorLinear : Self.canvasClearColor

            // D-COL2 (Plan 02-04-05): attach the resolved display colorspace
            // to the CAMetalLayer so the gamma-encoded bytes (fast path:
            // P3/sRGB gamut; fallback: sRGB workalike) are interpreted
            // as-emitted — the compositor performs NO further matching.
            // Window's screen wins (multi-display follows the window).
            // 08-4 T1: EDR ON skips this attach entirely — the layer is
            // pinned to extendedLinearSRGB (see `applyEDRDisplaySurface`);
            // the compositor no longer matches, the values ARE the display
            // intent (research §7.1).
            // M2-6-3 E3 (checker 回注): the DRT encoding-space pin rides the
            // same skip — the follow gate extended to
            // `!edrActive && !drtTailActive` (the pure gate above; the
            // per-frame override would otherwise kill the DRT-SDR原色匹配).
            if Self.followGateActive(
                edrActive: edrActive, drtTailActive: drtActive),
                let metalLayer = view.layer as? CAMetalLayer {
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
                // 08-4 T1: the EDR toggle wins the pick outright (the EDR
                // leg's source is always the float32 colorout plane, T2).
                // M2-6-3 T4: the DRT tail wins over BOTH legacy faces — its
                // final plane is the display-ready encoded plane (bgra8 →
                // drtSDR; 16F/float32 → the 16F direct-write path).
                let displayReady = texture.pixelFormat == .bgra8Unorm
                let state: any MTLRenderPipelineState?
                switch Self.blitRegime(
                    edrActive: edrActive, drtTailActive: drtActive,
                    sourceIsDisplayReady: displayReady) {
                case .edr16F, .drtFloat16:
                    if blitEDRPipelineState == nil {
                        blitEDRPipelineState = Self.makeBlitPipelineState(
                            device: device, displayReady: false,
                            colorPixelFormat: .rgba16Float
                        )
                    }
                    state = blitEDRPipelineState
                case .displayReadySDR, .drtSDR:
                    if blitDisplayReadyPipelineState == nil {
                        blitDisplayReadyPipelineState = Self.makeBlitPipelineState(
                            device: device, displayReady: true
                        )
                    }
                    state = blitDisplayReadyPipelineState
                case .legacyFloat:
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

/// The DRT viewport surface spec (Plan M2-6-3 T4, KD-4) — the pushed state
/// that flips the whole display surface when a DRT tail owns the terminal
/// segment. `hdrDrawable`: the 16F drawable + EDR content face (st2084/hlg;
/// the persistable-but-UI-unreachable linear rides it too — the tail format
/// already chose the float plane there); `layerColorSpace`: the encoding's
/// terminal CGColorSpace form (`drtLayerColorSpace`).
struct DrtSurfaceSpec: Equatable {
    var hdrDrawable: Bool
    var layerColorSpace: CGColorSpace
}

extension EditorMTKView.Coordinator {

    /// The encoding's terminal colorspace form (KD-4 终式, DECISIONS-signed):
    ///   • st2084/hlg — the macOS native PQ/HLG name constants. PLAN-LETTER
    ///     CORRECTION: the SDK has NO `extendedITUR_2100*` variant — the
    ///     terminal forms are `itur_2100_PQ` / `itur_2100_HLG` (macOS 11+;
    ///     PQ/HLG are absolute [0,1]→nits encodings, no extension needed).
    ///     The P3-encoding variants take the displayP3_PQ/HLG containers so
    ///     the primaries match the encoded gamut. A nil fallback = the E3
    ///     note (never observed on macOS 27).
    ///   • linear — extendedLinearSRGB (the EDR-linear handoff).
    ///   • SDR powers/BT.1886 — a calibrated-RGB space built from the
    ///     encoding space's primaries + white point + the EOTF's gamma (the
    ///     gamma-tail precedent: software encode + matching layer tag).
    ///     XYZ has no RGB derivation — the calibrated Rec709-gamut
    ///     approximation carries a DECISIONS note (degenerate display
    ///     target, walkthrough observation).
    static func drtLayerColorSpace(_ record: DrtRecord) -> CGColorSpace? {
        switch record.encodingEotf {
        case .st2084, .hlg:
            let pq = record.encodingEotf == .st2084
            switch record.encodingSpace {
            case .rec2020:
                return CGColorSpace(
                    name: pq ? CGColorSpace.itur_2100_PQ : CGColorSpace.itur_2100_HLG)
            case .p3d65:
                return CGColorSpace(
                    name: pq ? CGColorSpace.displayP3_PQ : CGColorSpace.displayP3_HLG)
            case .rec709, .p3d60, .p3dci, .xyz:
                return CGColorSpace(
                    name: pq ? CGColorSpace.itur_2100_PQ : CGColorSpace.itur_2100_HLG)
            }
        case .linear:
            return CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        case .gamma26, .bt1886, .gamma22, .gamma18:
            let gamma: [CGFloat] = {
                switch record.encodingEotf {
                case .bt1886: return [2.4, 2.4, 2.4]
                case .gamma26: return [2.6, 2.6, 2.6]
                case .gamma18: return [1.8, 1.8, 1.8]
                default: return [2.2, 2.2, 2.2]
                }
            }()
            let black: [CGFloat] = [0, 0, 0]
            let white: [CGFloat]
            let gamut: [[CGFloat]]
            switch record.encodingSpace {
            case .rec709, .xyz:
                // Rec709 gamut, D65 (the XYZ degenerate target's
                // approximation — DECISIONS note).
                white = [0.3127, 0.329, 0.0]
                gamut = [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]]
            case .p3d65:
                white = [0.3127, 0.329, 0.0]
                gamut = [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]]
            case .p3d60:
                white = [0.32168, 0.33767, 0.0]
                gamut = [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]]
            case .p3dci:
                white = [0.314, 0.351, 0.0]
                gamut = [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]]
            case .rec2020:
                // Not legal for SDR powers (the linkage table), but the
                // record is persistable — build the honest gamut anyway.
                white = [0.3127, 0.329, 0.0]
                gamut = [[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]]
            }
            // The SDK's Swift replacement of the obsoleted C constructor —
            // the matrix rides the FLAT 6-component face.
            var whitePoint = white
            var blackPoint = black
            var gamutFlat = gamut.flatMap { $0 }
            var gammaValues = gamma
            return CGColorSpace(
                calibratedRGBWhitePoint: &whitePoint,
                blackPoint: &blackPoint,
                gamma: &gammaValues,
                matrix: &gamutFlat)
        }
    }

    /// The surface spec for a record (nil = the Core layer refused the
    /// colorspace form — the caller stays on the legacy face + E3).
    static func drtSurfaceSpec(for record: DrtRecord) -> DrtSurfaceSpec? {
        guard let colorspace = drtLayerColorSpace(record) else { return nil }
        return DrtSurfaceSpec(
            hdrDrawable: record.encodingEotf != .gamma26 && record.encodingEotf != .bt1886
                && record.encodingEotf != .gamma22 && record.encodingEotf != .gamma18,
            layerColorSpace: colorspace)
    }
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
