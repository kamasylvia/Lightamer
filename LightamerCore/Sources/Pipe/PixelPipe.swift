import Metal
import os

/// The image-processing pipeline (FOUND-03/04) — Phase 1 skeleton.
///
/// **Phase 1 shape (this file):** a no-op, single-piece pipe. It is
/// layer-aware from day one (D-03a — holds the `LayerStack`) but traverses
/// NOTHING yet: `process` renders the decoded `CIImage` into the pipeline
/// pixel format (float32 linear Rec2020, FOUND-02) via the internal
/// `CIContextPool` bridge and returns it unchanged. This is the
/// "no-op pixelpipe" of Phase 1 success criterion #3 — the decoded image
/// flows RAWDecoder → PixelPipe → EditorMTKView with the layer stack in
/// place, so later phases fill the traversal without an architectural
/// rewrite (L005).
///
/// **Phase 2 fills** (RESEARCH §pixelpipe / CONTEXT Phase boundary):
/// - the real iop-chain traversal: the base layer's modules in `V50Order`
///   sequence, with per-module per-ROI state (`IOPiece`) and the
///   per-module output cache keyed on `(input hash, paramsHash, roi)`;
/// - multi-resolution pipes (preview / full / export at different
///   `ROI.scale`);
/// - the terminal trio (`colorin` → `colorout` → `gamma`) bracketing the
///   raw↔RGB boundary.
///
/// **Phase 6 fills:** the multi-layer composite — per-adjustment-layer
/// chain processing, mask rasterization, and the blend loop
/// (`blendop` kernel) compositing each layer onto the accumulator with
/// `layer.blendMode × layer.mask × layer.opacity`.
///
/// `internal` to Core (RESEARCH §9): the app never touches the pipe
/// directly — it goes through the `RenderPipeline` public bridge below.
internal final class PixelPipe {

    /// The layer stack being processed (D-03a: layer-aware from line one).
    /// Phase 1 only ever reads `baseLayer`; Phase 2 traversal and Phase 6
    /// composite attach here without changing this shape.
    internal var layerStack: LayerStack?

    internal init() {}

    internal init(layerStack: LayerStack) {
        self.layerStack = layerStack
    }

    /// Run the pipe over a decoded image; returns the display texture.
    ///
    /// Phase 1: guarantees a base layer exists (default `BackgroundLayer`
    /// when the stack was not injected), renders `image.ciImage` to a fresh
    /// float32 linear-Rec2020 texture, and returns it unchanged.
    internal func process(
        image: DecodedImage,
        metal: MetalContext
    ) async throws -> sending any MTLTexture {
        // 1. Base layer invariant (D-03a): a pipe always has one.
        if layerStack == nil {
            layerStack = LayerStack(baseLayer: BackgroundLayer())
        }

        // 2. Phase 1 traversal: NONE (no-op). The CIContextPool bridge
        // produces the pipeline-format texture; the pass-through KERNEL
        // contract is proven separately by `PassthroughModule.process`
        // (LightamerIOP) and the Plan 06 tests.
        // Phase 2: iterate baseLayer's chain in V50Order with per-piece
        // caches; Phase 6: the full layer composite.
        return try await metal.renderToTexture(image.ciImage)
    }
}

/// The app ↔ Core render bridge (Plan 04): `PixelPipe` itself is internal
/// to Core, so the app calls THIS entry point to run the no-op pixelpipe
/// and obtain the display texture. Documented as the render contract in
/// `LightamerCore/API.md` (Plan 06).
///
/// Phase 1 builds an ephemeral pipe per call (the no-op has no state worth
/// keeping); Phase 2 introduces a persistent pipe instance with caches.
public enum RenderPipeline {

    /// Signpost category for the pipe leg of the vertebra (D-31, visible in
    /// Instruments next to "decode" and "render").
    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer", category: "pixelpipe"
    )

    /// Run the Phase 1 no-op pixelpipe over `image` with `layerStack` and
    /// return the display texture (float32 linear Rec2020, FOUND-02).
    /// `layerStack` may be nil — the pipe installs a default
    /// `BackgroundLayer` stack (D-03a invariant).
    public static func render(
        image: DecodedImage,
        layerStack: LayerStack?,
        metal: MetalContext
    ) async throws -> sending any MTLTexture {
        let interval = signposter.beginInterval("pixelpipe", id: signposter.makeSignpostID())
        defer { signposter.endInterval("pixelpipe", interval) }
        let pipe = PixelPipe()
        pipe.layerStack = layerStack
        return try await pipe.process(image: image, metal: metal)
    }
}
