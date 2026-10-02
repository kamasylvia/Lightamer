import CoreGraphics
import Foundation
import Metal
import os

// ─────────────────────────────────────────────────────────────────────────────
// ExportRenderer — the HEADLESS full-frame export render (Plan 11-03 T4;
// EXP-03 + EXP-05). Assembled after the YiyinE2ETests headless precedent —
// NO PipeCoordinator dependency:
//
//   disk sidecar → instances + layer record   (the SessionBatchApplier
//                                              composeSegment reading method:
//                                              the DISK document is the truth)
//   → ExportChainBuilder                      (gamma stripped + colorout
//                                              target override, OQ-11-2)
//   → registry.materializeBoxes               (identity-preserving records
//                                              → boxes; unknown ops degrade)
//   → yiyin per-run injection                 (injectYiyinRunContext semantic
//                                              mirror — see the injector seam
//                                              below; mainImageSize STRICTLY
//                                              mirrors the entry scale)
//   → $routesToExportQueue render             (.export resolution — the whole
//                                              task tree lands on
//                                              exportCommandQueue, T1)
//   → exit leg                                (fresh CIContextPool on
//                                              exportCommandQueue — R8 fence —
//                                              renderToEncodedBitmap with
//                                              sourceColorSpace == target:
//                                              the IDENTITY pass, checker E3)
//   → quantize + encode + atomic promote      (the 11-02 registry; tmp same-
//                                              directory atomic rename, L009)
//
// decode leg seam: tests inject a synthetic `DecodedImage`; the default leg
// is `RAWDecoder.decode` — an export ALWAYS decodes the FULL FRAME once
// (a frozen PREVIEW input plane is a different SIZE — RESEARCH §4.3).
// ─────────────────────────────────────────────────────────────────────────────

/// The per-run yiyin injection seam. LightamerCore cannot name the yiyin
/// modules (D-03: Core has no IOP dependency), so the injection is handed in
/// by the caller — App wiring in 11-04 supplies `injectYiyinRunContext`'s
/// semantic mirror (captureExif / logo faces / JointContext /
/// jointLayoutOverride); tests supply the YiyinE2ETests.wireYiyinContext
/// shape. The renderer guarantees the injector runs AFTER box materialization
/// and BEFORE the render, with `mainImageSize` = the ENTRY plane (the strict
/// entry-scale mirror the borders `sourceImageSize` guard checks).
public struct ExportYiyinInjector: @unchecked Sendable {

    public let apply: @Sendable (
        _ boxes: [any ModuleBoxing],
        _ records: [ModuleInstance],
        _ mainImageSize: SIMD2<Int>,
        _ capture: CaptureMetadata
    ) -> Void

    public init(
        apply: @escaping @Sendable (
            _ boxes: [any ModuleBoxing],
            _ records: [ModuleInstance],
            _ mainImageSize: SIMD2<Int>,
            _ capture: CaptureMetadata
        ) -> Void
    ) {
        self.apply = apply
    }
}

/// One job's file-name template request (M2-9-03 KD-1, OQ-4). The pattern
/// evaluates INSIDE `renderStage` (the Alcedo RunExportRenderTask seat —
/// the context material is the DECODED capture facts + the disk sidecar's
/// rating + the batch sequence; App never pre-renders). `sequence` = the
/// batch ordinal, 1-based, SHARED by every variant of one image (OQ-4).
public struct ExportNamingRequest: Sendable {

    /// The `{token:arg}` pattern (the panel parses it to gate startExport;
    /// the renderer re-parses per job — parse is cheap and pure).
    public let pattern: String

    /// The batch ordinal (1-based; same for all variants of one image).
    public let sequence: Int

    /// The all-empty-render fallback stem (Alcedo hpp:93 default "image").
    public let fallbackStem: String

    public init(
        pattern: String, sequence: Int = 1,
        fallbackStem: String = ExportFileNameTemplate.fallbackStem
    ) {
        self.pattern = pattern
        self.sequence = sequence
        self.fallbackStem = fallbackStem
    }
}

public enum ExportRenderer {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "export-render")

    /// The QUEUE-side per-image DRT carrier (M2-9-02 KD-4's delivery seam):
    /// the export leg signature `(ExportJobSnapshot, ExportJobContext)` is
    /// contract-frozen (`ExportQueueContract.swift` zero-diff red line), so
    /// the actor's `execute` scopes each render-leg call in
    /// `$jobDrtTail.withValue(queued.drtTail)` — a detached task inherits
    /// NO TaskLocals, so the wrapper sits INSIDE the leg dispatch (the
    /// `routesToExportQueue` zero-default posture; nil = the legacy path).
    /// `renderStage` consumes it when the request's own `drtTail` is nil.
    @TaskLocal public static var jobDrtTail: DrtTailParams? = nil

    /// The QUEUE-side naming bundle (M2-9-03 KD-1): the template request +
    /// collision tier + subfolder, delivered through the same contract-
    /// frozen leg signature as `jobDrtTail`. nil = the legacy face; the
    /// explicit `Request` fields win over the carrier when both are set.
    public struct ExportNamingCarrier: Sendable {

        /// The per-job template request (sequence already stamped).
        public let naming: ExportNamingRequest?

        /// The collision tier (OQ-5).
        public let collisionPolicy: ExportNamer.ExportCollisionPolicy

        /// The landing subfolder (OQ-11).
        public let subfolder: String?

        public init(
            naming: ExportNamingRequest? = nil,
            collisionPolicy: ExportNamer.ExportCollisionPolicy = .increment,
            subfolder: String? = nil
        ) {
            self.naming = naming
            self.collisionPolicy = collisionPolicy
            self.subfolder = subfolder
        }
    }

    @TaskLocal public static var jobNamingCarrier: ExportNamingCarrier? = nil

    // MARK: - Request / outcome

    public struct Request {

        /// The SOURCE image (the decode leg's input; the EXIF round-trip
        /// carrier; the output stem).
        public let imageURL: URL

        /// The output landing zone (EXP-08 default = Session/Output/ — the
        /// App layer decides; the renderer only names + writes).
        public let destinationDirectory: URL

        /// File names ALREADY occupied there (ExportNamer's collision face).
        public let occupiedNames: Set<String>

        /// The variant: sizing × format × color space × yiyin switch.
        public let variant: ExportVariant

        /// `nil` = read the DISK SIDECAR (`<imageURL>.lra` — the truth, the
        /// 09-4 batch discipline; an unreadable sidecar exports PRISTINE).
        /// Non-nil = explicit records (the 11-04 live-edit export face).
        public var instancesOverride: [ModuleInstance]?

        /// The DRT tail policy payload (M2-9-02 KD-4): non-nil = the OQ-7-A
        /// mandatory linkage — the render runs the `.drt` terminal tail and
        /// the output ICC is the record's encoding pair. The payload
        /// (record + postOpNames) is APP-ASSEMBLED (D-M2-9-CONTEXT-4 — Core
        /// cannot name the IOP catalog); `nil` = the legacy five-space
        /// path, byte-frozen. Queue jobs may also deliver it through
        /// `ExportRenderer.jobDrtTail` (the contract-frozen leg signature's
        /// TaskLocal seam); the explicit field wins.
        public var drtTail: DrtTailParams?

        // ── M2-9-03 KD-1 naming carriers (additive; defaults = the legacy
        // face byte-for-byte: the stem+tag increment path) ────────────────

        /// Non-nil = the OQ-4 template face: step 9 evaluates the pattern
        /// per job (KD-2 context) and resolves through the collision tier.
        /// `nil` = the historical stem+tag path, byte-frozen.
        public var naming: ExportNamingRequest?

        /// The collision tier (OQ-5). Consumed by the TEMPLATE face only —
        /// the legacy path keeps the historical increment (KD-1's freeze).
        public var collisionPolicy: ExportNamer.ExportCollisionPolicy

        /// The landing subfolder (OQ-11): non-nil = `destinationDirectory`
        /// gains the sanitized subdirectory (created before the render;
        /// occupancy enumerates the JOINED directory). `nil` = off.
        public var subfolder: String?

        /// The yiyin output tag (`ExportNamer`; nil = derive/absent).
        public var outputTag: String? { variant.outputTag }

        /// Reserved provenance face (TIFF Software tag; nil = omit).
        public var editorSignature: String?

        public init(
            imageURL: URL,
            destinationDirectory: URL,
            occupiedNames: Set<String>,
            variant: ExportVariant,
            instancesOverride: [ModuleInstance]? = nil,
            editorSignature: String? = nil,
            drtTail: DrtTailParams? = nil,
            naming: ExportNamingRequest? = nil,
            collisionPolicy: ExportNamer.ExportCollisionPolicy = .increment,
            subfolder: String? = nil
        ) {
            self.imageURL = imageURL
            self.destinationDirectory = destinationDirectory
            self.occupiedNames = occupiedNames
            self.variant = variant
            self.instancesOverride = instancesOverride
            self.editorSignature = editorSignature
            self.drtTail = drtTail
            self.naming = naming
            self.collisionPolicy = collisionPolicy
            self.subfolder = subfolder
        }
    }

    public struct Outcome: Sendable {
        /// The promoted (atomically renamed) output file.
        public let destination: URL
        /// The FINAL output pixel size — the borders canvas extension
        /// INCLUDED (yiyin semantics: a border adds margin, so this may
        /// exceed the main-image target size).
        public let outputWidth: Int
        public let outputHeight: Int
        /// The main-image (entry-plane) size the yiyin joint layout saw.
        public let mainImageSize: SIMD2<Int>
    }

    /// The render-STAGE product (11-04): everything through step 8
    /// (decode → … → quantize) plus the encode inputs resolved at the
    /// stage boundary (the ExportNamer destination against the request's
    /// occupancy snapshot). Crossing the queue's render→encode handoff,
    /// hence a Sendable value; `CGColorSpace` rides the thread-safe-CF
    /// `@unchecked` posture (see `ExportRenderStage`).
    public struct StageOutput: @unchecked Sendable {
        public let plane: ExportQuantizedPlane
        public let formatSpec: ExportFormatSpec
        public let targetColorSpace: CGColorSpace
        public let dpi: Double
        public let destination: URL
        public let sourceURL: URL
        public let editorSignature: String?
        public let outputWidth: Int
        public let outputHeight: Int
        public let mainImageSize: SIMD2<Int>
    }

    // MARK: - The pipeline

    /// The D-34 conversion: a cancelled task becomes the TYPED
    /// `AppError.cancelled` at the renderer's phase boundaries (Swift's
    /// `Task.checkCancellation` would surface a bare CancellationError).
    private static func cancellationCheckpoint() throws {
        if Task.isCancelled {
            throw AppError.cancelled
        }
    }

    /// The full chain, one call: `renderStage` + `encodeStage` (the 11-03
    /// shape — unchanged for its callers; the 11-04 ExportQueue splits the
    /// two across its leg boundary so a cancelled in-flight job at the
    /// boundary leaves NOTHING on disk).
    public static func render(
        request: Request,
        metal: MetalContext,
        registry: ModuleRegistry,
        decodeLeg: (@Sendable (URL) async throws -> DecodedImage)? = nil,
        yiyinInjector: ExportYiyinInjector? = nil
    ) async throws -> Outcome {
        let stage = try await renderStage(
            request: request, metal: metal, registry: registry,
            decodeLeg: decodeLeg, yiyinInjector: yiyinInjector)
        let destination = try encodeStage(
            plane: stage.plane, formatSpec: stage.formatSpec,
            targetColorSpace: stage.targetColorSpace, dpi: stage.dpi,
            sourceURL: stage.sourceURL, editorSignature: stage.editorSignature,
            destination: stage.destination)
        return Outcome(
            destination: destination,
            outputWidth: stage.outputWidth,
            outputHeight: stage.outputHeight,
            mainImageSize: stage.mainImageSize)
    }

    /// The render stage — steps 1-8 (decode, sizing, document, export
    /// chain, yiyin injection, routed render, exit leg, quantize) plus the
    /// destination NAMING (the encoder has not touched disk yet — a throw
    /// or a cancellation here leaves zero files).
    public static func renderStage(
        request: Request,
        metal: MetalContext,
        registry: ModuleRegistry,
        decodeLeg: (@Sendable (URL) async throws -> DecodedImage)? = nil,
        yiyinInjector: ExportYiyinInjector? = nil
    ) async throws -> StageOutput {
        let variant = request.variant
        try variant.validate()

        // ── 0. the naming face (M2-9-03 KD-1) + the landing zone ────────
        // The queue delivers its batch carriers through the TaskLocal seam
        // (the contract-frozen leg signature); the explicit Request fields
        // win when both are set. `naming == nil` everywhere = the legacy
        // increment face, byte-frozen.
        let carrier = Self.jobNamingCarrier
        let naming = request.naming ?? carrier?.naming
        let collisionPolicy = carrier?.collisionPolicy ?? request.collisionPolicy
        let subfolder = request.subfolder ?? carrier?.subfolder
        // OQ-11: the subfolder joins BEFORE anything runs, so the occupancy
        // snapshot (already enumerated against this joined directory by the
        // queue) and the landing face agree, and a missing directory is
        // created typed-fail-fast — the render never starts into a void
        // (L009 family: the encoder's own write stays tmp-atomic).
        let landingDirectory = Self.landingDirectory(
            base: request.destinationDirectory, subfolder: subfolder)
        if landingDirectory != request.destinationDirectory {
            do {
                try FileManager.default.createDirectory(
                    at: landingDirectory, withIntermediateDirectories: true)
            } catch {
                throw AppError.encodeFailed(
                    "export: subfolder create failed for "
                        + "\(landingDirectory.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // ── 1. decode leg (full frame, once) ─────────────────────────────
        try cancellationCheckpoint()
        let decoded: DecodedImage
        if let decodeLeg {
            decoded = try await decodeLeg(request.imageURL)
        } else {
            decoded = try await RAWDecoder().decode(request.imageURL)
        }

        // ── 2. sizing (EXP-03): percent fold → targetSize → entry plane ──
        // E6 (checker 回注): the sizing leg consumes `resolveExportResolution`
        // DIRECTLY so the cap stage's width-ratio DPI correction reaches the
        // product metadata (`StageOutput.dpi = result.dpi`). `targetSize()`
        // already delegates to the same resolution — the pixel math is
        // byte-identical; only the DPI face changes (the corrected value on
        // capped physical exports, the clamped value elsewhere).
        let fullWidth = max(Int(decoded.ciImage.extent.width), 1)
        let fullHeight = max(Int(decoded.ciImage.extent.height), 1)
        let effectiveSizing = variant.effectiveSizing(
            canvasWidth: fullWidth, canvasHeight: fullHeight)
        let resolution = effectiveSizing.resolveExportResolution(
            canvasWidth: fullWidth, canvasHeight: fullHeight)
        guard resolution.success, resolution.width >= 1, resolution.height >= 1 else {
            throw AppError.invalidParameter(
                "export sizing resolution failed: \(resolution.message ?? "unknown")")
        }
        let targetSize = (width: resolution.width, height: resolution.height)
        // The entry LONG EDGE (the pipe's scale-at-entry parameter) and the
        // ENTRY PLANE — computed with the pipe's EXACT math (coordinator
        // mirror) so the yiyin `mainImageSize` is the borders guard's
        // `sourceImageSize` to the pixel (settings floor vs pipe round can
        // disagree by 1px on the short edge — the guard would degrade).
        let entryLongEdge = max(targetSize.width, targetSize.height)
        let entryScale = min(
            CGFloat(entryLongEdge) / CGFloat(fullWidth),
            CGFloat(entryLongEdge) / CGFloat(fullHeight),
            1.0)
        let planeWidth = max(1, Int((CGFloat(fullWidth) * entryScale).rounded()))
        let planeHeight = max(1, Int((CGFloat(fullHeight) * entryScale).rounded()))

        // ── 3. the document (disk sidecar truth, 09-4 reading method) ────
        let records: [ModuleInstance]
        let layerRecord: SidecarLayerStackRecord?
        let imageID: UUID
        // KD-2: the template's `rating` face reads the DISK sidecar even in
        // the override mode (the rating is not a render parameter — the
        // on-disk META is the truth). The step-3 read is reused when it
        // already happened.
        var namingDocument: LightamerSidecar?
        if let override = request.instancesOverride {
            records = override
            layerRecord = nil
            imageID = UUID()
            if naming != nil {
                namingDocument = Self.readDocument(imageURL: request.imageURL)
            }
        } else if let document = Self.readDocument(imageURL: request.imageURL) {
            records = document.instances
            layerRecord = document.layerStack
            imageID = document.imageID
            namingDocument = document
        } else {
            records = []
            layerRecord = nil
            imageID = UUID()
            Self.logger.info(
                "export: no readable sidecar for \(request.imageURL.lastPathComponent, privacy: .public) — exporting pristine")
        }

        // ── 4. the export chain ─────────────────────────────────────────
        // M2-9-02 KD-2/KD-4: a DRT carrier switches the assembly to the
        // OQ-7-A linkage (verbatim records — the pipe demotes the terminal
        // set in-pipe under `.drt`; the output ICC is the record's encoding
        // pair). nil carrier = the legacy five-space face, byte-frozen.
        let drtTail = request.drtTail ?? Self.jobDrtTail
        let built: ExportChainBuilder.Built
        if let drtTail {
            built = try ExportChainBuilder.exportDrtChain(
                from: records,
                space: drtTail.record.encodingSpace,
                eotf: drtTail.record.encodingEotf)
        } else {
            built = try ExportChainBuilder.exportChain(
                from: records,
                target: variant.colorSpace,
                linearVariant: ExportChainBuilder.isLinearVariant(variant.format))
        }
        let (boxes, unknownOps) = await registry.materializeBoxes(for: built.instances)
        if !unknownOps.isEmpty {
            Self.logger.info(
                "export: unknown ops degraded \(unknownOps.joined(separator: ","), privacy: .public)")
        }
        // The override socket (per-run DATA): set AFTER apply, then
        // re-commit so the folded hash carries it (the tests' proven shape).
        for box in boxes {
            guard let colorout = box as? ModuleBox<ColorOutModule> else { continue }
            colorout.module.exportTargetOverride = built.exportTargetOverride
            if let coloroutRecord = built.instances.first(where: {
                $0.opName == ColorOutModule.opName && $0.id == box.instanceID
            }) {
                let params = (try? coloroutRecord.params(of: ColorOutModule.self))
                    ?? ColorOutModule.Params()
                colorout.setParams(params)
            }
        }

        // ── 5. yiyin per-run injection (EXP-05; mainImageSize = entry) ───
        if variant.yiyin {
            guard let injector = yiyinInjector else {
                throw AppError.invalidParameter(
                    "variant.yiyin requires an ExportYiyinInjector (App wiring or test seam)")
            }
            injector.apply(
                boxes, built.instances, SIMD2(planeWidth, planeHeight), decoded.capture)
        }

        // ── 6. the routed render (.export resolution) ────────────────────
        try cancellationCheckpoint()
        let layerStack: LayerStack?
        if let layerRecord, !layerRecord.layers.isEmpty {
            var rebuilt = LayerStack(baseLayer: BackgroundLayer())
            for layer in layerRecord.snapshot.makeLayers() {
                rebuilt.addAdjustment(layer)
            }
            layerStack = rebuilt.compositeLayers.isEmpty ? nil : rebuilt
        } else {
            layerStack = nil
        }

        let cache = PipeCache()
        let outputTexture: any MTLTexture
        // M2-9-02 KD-4: the DRT tail owns the terminal segment on the
        // EXPORT run (the pipe's `.drt` policy demotes colorout/gamma/
        // borders/watermark and replays the tail) — the legacy carrier
        // stays `.sdrGamma`, the zero-path default. The T3 seam rides the
        // same switch: the export tail plane is ALWAYS the working float32
        // face (the quantizer owns the [0,1] clamp + the bit tiers — an
        // 8/16-bit display tail would quantize before the quantizer).
        let terminalTailPolicy: TerminalTailPolicy =
            drtTail.map { .drt($0) } ?? .sdrGamma
        let tailFormatFloatOverride = drtTail != nil
        if let layerStack {
            let (texture, _) = try await MetalContext.$routesToExportQueue.withValue(true) {
                try await RenderPipeline.processComposite(
                    image: decoded, instances: boxes, layerStack: layerStack,
                    registry: registry, imageID: imageID, resolution: .export,
                    cache: cache, metal: metal, longEdge: entryLongEdge,
                    roiHint: nil, policy: .export,
                    terminalTail: terminalTailPolicy,
                    tailFormatFloatOverride: tailFormatFloatOverride)
            }
            outputTexture = texture
        } else {
            let (texture, _) = try await MetalContext.$routesToExportQueue.withValue(true) {
                try await RenderPipeline.process(
                    image: decoded, instances: boxes, imageID: imageID,
                    resolution: .export, cache: cache, metal: metal,
                    longEdge: entryLongEdge, terminalTail: terminalTailPolicy,
                    tailFormatFloatOverride: tailFormatFloatOverride)
            }
            outputTexture = texture
        }

        // ── 7. the exit leg (R8: export-queue fence; E3: identity) ───────
        try cancellationCheckpoint()
        // A FRESH pool per render — the export exit is single-shot (the
        // memo/GUI-22 input-plane reuse is an EDITOR economy; here the pool
        // exists to hang the fence on the right queue and die with the job).
        let exportPool = CIContextPool(
            device: metal.device, commandQueue: metal.exportCommandQueue)
        // E3 consumption face: the in-pipe colorout override already landed
        // primaries+TRC → the pass is an IDENTITY (source == target). A
        // colorout-less chain (non-standard document) does the WHOLE
        // conversion here instead (the 11-02 default face).
        let sourceColorSpace =
            built.coloroutOverridden ? built.exportTargetOverride : WorkingSpace.colorSpace
        let encoded = try await exportPool.renderToEncodedBitmap(
            TextureBox(texture: outputTexture),
            sourceColorSpace: sourceColorSpace,
            toSpace: built.exportTargetOverride)

        // ── 8. quantize (D-11-CONTEXT-7 tiers) ───────────────────────────
        try cancellationCheckpoint()
        let layout = try ExportEncoderRegistry.expectedLayout(for: variant.format)
        let samples = encoded.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        let packed: Data
        switch layout {
        case .rgba8:
            packed = try ExportQuantizer.packedRGBA8(
                rgba: samples, width: encoded.width, height: encoded.height)
        case .rgba16:
            packed = try ExportQuantizer.packedRGBA16(
                rgba: samples, width: encoded.width, height: encoded.height)
        case .float32:
            packed = try ExportQuantizer.packedFloat32(
                rgba: samples, width: encoded.width, height: encoded.height)
        }
        let plane = ExportQuantizedPlane(
            data: packed, width: encoded.width, height: encoded.height, layout: layout)

        // ── 9. name (the encode stage does encode + atomic promote) ─────
        // KD-1's dispatch: the template face evaluates INSIDE the renderer
        // (OQ-4's Alcedo seat) and resolves through the collision tier; the
        // `naming == nil` face is the historical stem+tag increment path,
        // byte-frozen (the legacy sheet and every existing E2E anchor on
        // it). The tag face is UNCHANGED on both paths — multi-variant
        // batches never overwrite each other (a single-variant batch tags
        // nil and lands the pure template name).
        let destination: URL
        if let naming {
            let context = ExportFileNameContext(
                sourceStem: request.imageURL.deletingPathExtension().lastPathComponent,
                captureDate: decoded.capture.captureTime,
                cameraMake: decoded.capture.cameraMake,
                cameraModel: decoded.capture.cameraModel,
                lensModel: decoded.capture.lensModel,
                iso: decoded.capture.iso,
                aperture: decoded.capture.aperture,
                shutterSeconds: decoded.capture.shutterSpeed,
                focalLengthMM: decoded.capture.focalLength,
                rating: namingDocument?.rating,
                sequence: naming.sequence)
            let stem = ExportFileNameTemplate.resolvedStem(
                pattern: naming.pattern, context: context,
                fallback: naming.fallbackStem)
            destination = try ExportNamer.destinationURL(
                directory: landingDirectory,
                stem: stem,
                tag: request.outputTag,
                ext: variant.format.fileExtension,
                occupiedNames: request.occupiedNames,
                collisionPolicy: collisionPolicy)
        } else {
            destination = ExportNamer.destinationURL(
                directory: landingDirectory,
                stem: request.imageURL.deletingPathExtension().lastPathComponent,
                tag: request.outputTag,
                ext: variant.format.fileExtension,
                occupiedNames: request.occupiedNames)
        }
        return StageOutput(
            plane: plane,
            formatSpec: variant.format,
            targetColorSpace: built.exportTargetOverride,
            dpi: Double(resolution.dpi),
            destination: destination,
            sourceURL: request.imageURL,
            editorSignature: request.editorSignature,
            outputWidth: encoded.width,
            outputHeight: encoded.height,
            mainImageSize: SIMD2(planeWidth, planeHeight))
    }

    /// The encode stage — step 9's write half: quantized plane → encoder →
    /// atomic promote (L009). A throw cleans any pre-rename residue; a
    /// COMPLETED export never reaches the cleanup path. (Explicit
    /// parameters — both the internal `StageOutput` and the queue-facing
    /// `ExportRenderStage` carry exactly this set.)
    public static func encodeStage(
        plane: ExportQuantizedPlane,
        formatSpec: ExportFormatSpec,
        targetColorSpace: CGColorSpace,
        dpi: Double,
        sourceURL: URL,
        editorSignature: String?,
        destination: URL
    ) throws -> URL {
        let encodeRequest = ExportEncodeRequest(
            plane: plane,
            spec: formatSpec,
            colorSpace: targetColorSpace,
            dpi: dpi,
            sourceURL: sourceURL,
            editorSignature: editorSignature,
            destination: destination)
        do {
            let encoder = try ExportEncoderRegistry.encoder(
                for: formatSpec, plane: plane)
            _ = try encoder.encode(encodeRequest)
        } catch {
            // The encoder writes atomically (in-memory encode → .atomic
            // rename, L009) — a thrown error can only leave a stray tmp
            // file, never a partial destination. The destination removal
            // here is the belt-and-suspenders cleanup for any pre-rename
            // residue; a COMPLETED export never reaches this path.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        // ── the XMP mount (Plan 12-3 T4): the sidecar's five metadata
        // fields ride the PRODUCT (the exported image has left the session
        // truth-chain). Every non-attached outcome degrades — an export
        // never hard-fails on metadata; the outcome value is the tally face.
        let xmpOutcome = ExportChainBuilder.mountXMP(
            destination: destination, format: formatSpec, sourceURL: sourceURL)
        if case .failed(let reason) = xmpOutcome {
            Self.logger.error(
                "export: XMP injection degraded for \(destination.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
        } else {
            Self.logger.info("export: XMP mount \(String(describing: xmpOutcome), privacy: .public)")
        }

        Self.logger.info(
            "export: \(destination.lastPathComponent, privacy: .public) \(plane.width, privacy: .public)×\(plane.height, privacy: .public)")
        return destination
    }

    /// The OQ-11 subfolder join — the ONE source for the renderer's landing
    /// face AND the queue's occupancy enumeration (they must agree). An
    /// absent or empty-sanitizing subfolder returns the base verbatim; a
    /// non-empty one appends the template-sanitized name (KD-1: the template
    /// sanitize is the subfolder sanitize — one policy, two jobs).
    public static func landingDirectory(base: URL, subfolder: String?) -> URL {
        guard let subfolder else { return base }
        let sanitized = ExportFileNameTemplate.sanitizedStem(subfolder)
        guard !sanitized.isEmpty else { return base }
        return base.appendingPathComponent(sanitized, isDirectory: true)
    }

    // MARK: - Disk sidecar reading (the SessionBatchApplier method)

    /// Read the DISK document for an image (`<imageURL>.lra`). The truth —
    /// the index is never consulted (D-09-CONTEXT-4). nil = no readable
    /// sidecar (pristine export).
    public static func readDocument(imageURL: URL) -> LightamerSidecar? {
        let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
        guard let data = try? Data(contentsOf: sidecarURL) else { return nil }
        return try? JSONDecoder().decode(LightamerSidecar.self, from: data)
    }
}
