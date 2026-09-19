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
/// Phase 2 = near-static blit (D-13: no zoom/pan): `isPaused` +
/// `enableSetNeedsDisplay` redraw only on demand — texture change (pushed
/// from `updateNSView`, UI-1 pitfall: ONLY on identity change, never
/// per-frame) or drawable resize. The blit render pipeline state is built
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

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.delegate = context.coordinator
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
        guard !context.coordinator.hasSameSourceTexture(as: sourceTexture) else { return }
        context.coordinator.sourceTexture = sourceTexture
        view.setNeedsDisplay(view.bounds)
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
                    var uniforms = Self.aspectFitUniforms(
                        textureSize: SIMD2(Float(texture.width), Float(texture.height)),
                        drawableSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
                    )
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<BlitUniforms>.stride, index: 0)
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                }
            } // else: no image yet — solid canvas mat (UI-SPEC "no image" viewport state)

            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// Aspect-fit the texture inside the drawable (NDC scale; the
        /// letterbox shows the canvas-mat clear color). Phase 1 keeps the
        /// image centered — fit/100% controls arrive with zoom/pan (Phase 2+).
        private static func aspectFitUniforms(
            textureSize: SIMD2<Float>, drawableSize: SIMD2<Float>
        ) -> BlitUniforms {
            guard drawableSize.x >= 1, drawableSize.y >= 1, textureSize.x >= 1, textureSize.y >= 1 else {
                return BlitUniforms(scale: SIMD2(1, 1), offset: SIMD2(0, 0))
            }
            let fit = min(drawableSize.x / textureSize.x, drawableSize.y / textureSize.y)
            return BlitUniforms(
                scale: SIMD2(fit * textureSize.x / drawableSize.x, fit * textureSize.y / drawableSize.y),
                offset: SIMD2(0, 0)
            )
        }
    }
}

/// Layout mirror of `BlitUniforms` in `EditorBlitShader.metal`
/// (float2 scale; float2 offset — 16 bytes, set via `setVertexBytes`).
private struct BlitUniforms {
    var scale: SIMD2<Float>
    var offset: SIMD2<Float>
}
