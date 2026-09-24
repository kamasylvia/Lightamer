import CoreImage
import CoreML
import CoreVideo
import Metal
import Vision

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskService (Plan 07-1 T2/T3) — the layer A/B subject-masking service
// (Core level, UI-free, unit-testable; AI-01 does NOT occupy an iop slot —
// it is a mask GENERATOR whose product is a raster asset).
//
// LAYER A = `GenerateForegroundInstanceMaskRequest` (macOS 15 struct API;
// OS-built-in model, offline, class-agnostic, multi-instance). Two-stage
// API per plan 07-1: stage 1 returns the instance catalog, stage 2 bakes
// the selected subset at SOURCE resolution via `generateScaledMask` (the
// plan-preferred full-resolution leg — no upsample needed).
//
// LAYER B = `GenerateIterativeSegmentationRequest` (macOS 27, WWDC26/237
// tap-to-segment; DownloadableAssetsRequest — one-time model download,
// gated by AIAssetStore; NOT downloaded inside generate — the caller gets
// `AIMaskError.modelNotReady` and disables the entry; layer A is never
// affected. D-07-CONTEXT-1).
//
// CONCURRENCY: every method is a nonisolated async static — inference runs
// on the cooperative pool (the "background Task" of the plan; the App
// layer launches it from a Task, the Metal render loop never awaits it).
//
// L014 RED LINE: `AIMaskInput(texture:)` FENCES the producing queue
// (commit empty command buffer + waitUntilCompleted) BEFORE the texture
// crosses into CoreImage/Vision's internal queues — the same
// `CIContextPool.convertTexture` discipline.
//
// FAILURE LEGS (strict): inference error / no subject / model not ready →
// typed `AIMaskError`, NO mask, NEVER an all-ones plane (that is the
// RasterMaskStore.load degrade semantic — the two are kept strictly
// apart, D-07-CONTEXT 継承定案).
// ─────────────────────────────────────────────────────────────────────────────

/// The compute-device policy for one inference call.
///
/// RUNTIME REALITY (07-1 benchmark finding, macOS 27.0b 26A428 — recorded
/// in 07-1-DECISIONS D-07-1-T1-2): `supportedComputeStageDevices` lists
/// layer A main = [ane, gpu], layer B main = [gpu] — the CPU is NOT a
/// supported stage device, and pinning an unsupported device does NOT
/// throw: the process SIGTRAPs inside perform. The service therefore
/// VALIDATES every pin against the request's own supported map and
/// converts an impossible pin into a typed `AIMaskError.deviceUnavailable`
/// — never a trap.
public enum AIDevicePolicy: Sendable, Equatable {
    /// No pin — Vision/CoreML picks (ANE preferred). The runtime default.
    case anePreferred
    /// Pin every stage to the GPU — the TEST determinism policy (the only
    /// device BOTH layers support on this OS; same device → byte-identical
    /// output, no cross-device promise).
    case gpuPinned
    /// Pin every stage to the CPU — VALIDATED against the supported map;
    /// on macOS 27 beta this throws `AIMaskError.deviceUnavailable` (the
    /// OS traps otherwise). Retained because the supported set is
    /// OS-version-dependent and CPU may appear later.
    case cpuPinned
}

/// The inference output: a single-channel float mask plane in [0,1] at
/// the SOURCE image resolution (layer A `generateScaledMask`) or the
/// quality-level resolution (layer B — the caller upsamples at bake time,
/// see AIMaskResample). Row 0 = image TOP (buffer-aligned with the input
/// pixels — no flip; 07-CONTEXT 継承定案).
public struct AIMaskPlane: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major, `width * height` floats, [0,1].
    public let floats: [Float]

    public init(width: Int, height: Int, floats: [Float]) {
        precondition(floats.count == width * height, "AIMaskPlane count mismatch")
        self.width = width
        self.height = height
        self.floats = floats
    }

    public static func == (lhs: AIMaskPlane, rhs: AIMaskPlane) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.floats == rhs.floats
    }

    /// Bit-exact identity hash over the payload (the determinism gate's
    /// comparison primitive — dimensions folded little-endian + every
    /// float's bit pattern through FNV-1a; the L013 discipline: explicit
    /// fold, never JSON bytes).
    public var byteIdentity: UInt64 {
        func fold(_ seed: UInt64, _ value: UInt64) -> UInt64 {
            var v = value
            return withUnsafeBytes(of: &v) { StableHash.combine(seed, $0) }
        }
        var h = fold(StableHash.fnvOffsetBasis, UInt64(width))
        h = fold(h, UInt64(height))
        var bits = [UInt32](repeating: 0, count: floats.count)
        for i in 0..<floats.count { bits[i] = floats[i].bitPattern }
        return bits.withUnsafeBytes { bytes in StableHash.combine(h, bytes) }
    }
}

/// The inference input — a linear working-space `CIImage` (the DECODE
/// FRAME: demosaiced, pre-edit — mask semantics anchor to the photo's
/// content, D-07-CONTEXT 継承定案). `@unchecked Sendable`: CIImage is
/// immutable; the wrapper only silences the non-Sendable CoreImage tag.
public struct AIMaskInput: @unchecked Sendable {
    public let ciImage: CIImage

    public init(ciImage: CIImage) {
        self.ciImage = ciImage
    }

    /// Direct pixel-buffer leg (tests + any buffer-producing pipeline).
    public init(pixelBuffer: CVPixelBuffer) {
        self.ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    }

    /// The decode-frame leg (L014): fence the producing queue, then wrap
    /// the texture zero-copy. `CIImage(mtlTexture:)` keeps the GPU bytes
    /// in place (CoreImage samples on its own queue at perform time — the
    /// fence above is what makes that read safe). The texture must carry
    /// `.shaderRead` usage (every pipeline plane does).
    public init(texture: any MTLTexture, metal: MetalContext) throws {
        let extent = texture.width * texture.height
        guard extent > 0 else {
            throw AIMaskError.invalidInput("zero-extent inference texture")
        }
        // L014: drain OUR queue's pending writes before the texture
        // crosses into CoreImage/Vision.
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        guard let image = CIImage(mtlTexture: texture, options: [
            .colorSpace: WorkingSpace.colorSpace,
        ]) else {
            throw AIMaskError.invalidInput(
                "CIImage(mtlTexture:) rejected the plane (usage must include shaderRead)")
        }
        self.ciImage = image
    }
}

public enum AIMaskService {

    // MARK: - Layer A (foreground instance mask — offline, built-in)

    /// Stage 1: run layer A, return the instance catalog (the 07-3
    /// checkbox overlay consumes `instances`; the catalog carries the
    /// observation for stage 2).
    public static func detectInstances(
        input: AIMaskInput,
        device: AIDevicePolicy = .anePreferred
    ) async throws -> AIInstanceCatalog {
        var request = GenerateForegroundInstanceMaskRequest()
        try apply(device, to: &request)
        let handler = ImageRequestHandler(input.ciImage)
        do {
            guard let observation = try await handler.perform(request) else {
                throw AIMaskError.noSubject
            }
            return AIInstanceCatalog(
                instances: observation.allInstances.sorted(),
                observation: observation, handler: handler)
        } catch let error as AIMaskError {
            throw error
        } catch {
            throw AIMaskError.inferenceFailed(String(describing: error))
        }
    }

    /// Stage 2: the selected instances' mask — `allInstancesMask` LABEL
    /// compositing (our code: label ∈ selection → 1, else 0) at the label
    /// map's resolution; the caller upsamples at bake time
    /// (`AIMaskResample`), the same reshape contract as layer B.
    ///
    /// WHY NOT `generateScaledMask` (the plan's preferred full-res leg):
    /// macOS 27.0b breaks BOTH of its behaviors (07-1 probe evidence,
    /// D-07-1-T2-4): (a) SUBSET semantics — any subset renders as
    /// all-instances or empty; (b) GEOMETRY — the all-set mask is offset
    /// +3/16 in both axes vs the subject (a centered 0.25..0.75 box
    /// lands at 0.44..0.94). The label map is correct on both counts
    /// (probe-verified twice). UPGRADE SEAM: when Apple fixes the scaled
    /// mask, switch `.all` back for the full-resolution soft edges.
    public static func subjectMask(
        from catalog: AIInstanceCatalog,
        selection: AIInstanceSelection = .all
    ) throws -> AIMaskPlane {
        let indexSet = try resolve(selection: selection, catalog: catalog)
        return try labelCompositeMask(from: catalog, instances: indexSet)
    }

    /// The `.all` leg — full-resolution soft mask (half-float 'L00f').
    /// UNUSED in v1 (the offset bug above) — retained as the documented
    /// upgrade seam for the Apple-fixed path.
    private static func scaledMask(from catalog: AIInstanceCatalog) throws -> AIMaskPlane {
        do {
            let buffer = try catalog.observation.generateScaledMask(
                for: catalog.observation.allInstances, scaledToImageFrom: catalog.handler)
            return try maskPlane(from: buffer)
        } catch let error as AIMaskError {
            throw error
        } catch {
            throw AIMaskError.inferenceFailed(String(describing: error))
        }
    }

    /// The `.subset` leg — `allInstancesMask` label compositing (label 0
    /// = background, always excluded; the probe-verified correct label
    /// map). Output at the label map's resolution (bake-time upsample is
    /// the caller's, via AIMaskResample).
    private static func labelCompositeMask(
        from catalog: AIInstanceCatalog, instances: IndexSet
    ) throws -> AIMaskPlane {
        return try catalog.observation.allInstancesMask.pixelBuffer.withUnsafeBuffer { buffer -> AIMaskPlane in
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            guard width > 0, height > 0,
                  let base = CVPixelBufferGetBaseAddress(buffer)
            else {
                throw AIMaskError.invalidMask("unreadable allInstancesMask")
            }
            let labels = base.assumingMemoryBound(to: UInt8.self)
            var floats = [Float](repeating: 0, count: width * height)
            var covered = 0
            for y in 0..<height {
                for x in 0..<width {
                    let label = Int(labels[y * bytesPerRow + x])
                    if label != 0 && instances.contains(label) {
                        floats[y * width + x] = 1
                        covered += 1
                    }
                }
            }
            guard covered > 0 else {
                throw AIMaskError.invalidMask(
                    "subset \(instances.sorted()) covers no pixels in the label map")
            }
            return AIMaskPlane(width: width, height: height, floats: floats)
        }
    }

    /// One-shot layer A (detect + full-subset scaled mask).
    public static func subjectMask(
        input: AIMaskInput,
        selection: AIInstanceSelection = .all,
        device: AIDevicePolicy = .anePreferred
    ) async throws -> AIMaskPlane {
        let catalog = try await detectInstances(input: input, device: device)
        return try subjectMask(from: catalog, selection: selection)
    }

    // MARK: - Layer B (iterative segmentation — tap/box, model download gated)

    /// Layer B: tap/box-seeded iterative segmentation. The mask comes out
    /// at the QUALITY-level resolution (upsample at bake time —
    /// AIMaskResample). Refine points are view-normalized; the Y-flip is
    /// applied here (through AIMaskTypes' seam).
    public static func segmentSubject(
        input: AIMaskInput,
        seed: AISubjectSeed,
        refine: [AIRefinePoint] = [],
        quality: AIMaskQuality = .accurate,
        regionOfInterest: AIMaskRect? = nil,
        device: AIDevicePolicy = .anePreferred,
        assets: AIAssetStore = .shared
    ) async throws -> AIMaskPlane {
        // The model gate: layer B refuses (typed) when assets are not
        // ready — no silent download, no silent fallback (D-07-CONTEXT-1).
        // An unqueried store is queried inline (the first call after
        // launch may race the first-launch prompt).
        let phase = await assets.currentPhase(queried: true)
        switch phase {
        case .notReady:
            throw AIMaskError.modelNotReady("layer B model not downloaded (assetStatus notReady)")
        case .downloading:
            throw AIMaskError.modelNotReady("layer B model still downloading")
        case .failed(let reason):
            throw AIMaskError.modelNotReady("layer B model download failed: \(reason)")
        case .ready, .unknown:
            break // unknown only survives when the probe itself failed —
                  // perform() then surfaces the real error through the
                  // typed inferenceFailed face below.
        }

        let request = try buildLayerBRequest(
            seed: seed, refine: refine, quality: quality,
            regionOfInterest: regionOfInterest, device: device)
        let handler = ImageRequestHandler(input.ciImage)
        do {
            guard let observation = try await handler.perform(request) else {
                throw AIMaskError.noSubject
            }
            let plane = try observation.pixelBuffer.withUnsafeBuffer { buffer in
                try maskPlane(from: buffer)
            }
            return plane
        } catch let error as AIMaskError {
            throw error
        } catch {
            throw AIMaskError.inferenceFailed(String(describing: error))
        }
    }

    /// Assemble the layer-B request (seed inits, point budget, quality,
    /// ROI, device pin — the point-count gate throws BEFORE Vision can).
    static func buildLayerBRequest(
        seed: AISubjectSeed,
        refine: [AIRefinePoint],
        quality: AIMaskQuality,
        regionOfInterest: AIMaskRect?,
        device: AIDevicePolicy
    ) throws -> GenerateIterativeSegmentationRequest {
        let request: GenerateIterativeSegmentationRequest
        let seedPoints: Int
        let limit: Int
        switch seed {
        case let .point(p):
            request = GenerateIterativeSegmentationRequest(seedPoint: p.visionPoint)
            seedPoints = 1
            limit = AIPointBudget.pointSeeded
        case let .box(r):
            request = GenerateIterativeSegmentationRequest(seedBox: r.visionRect)
            seedPoints = 0
            limit = AIPointBudget.boxSeeded
        case .scribble:
            throw AIMaskError.scribbleNotSupported
        }
        request.qualityLevel = quality.visionLevel
        if let roi = regionOfInterest {
            request.regionOfInterest = roi.visionRect
        }
        switch device {
        case .anePreferred: break
        case .gpuPinned, .cpuPinned:
            try pin(device, to: request) // typed refusal on this OS (bug guard)
        }
        // Our deterministic budget gate (seed counts for point seeds).
        guard seedPoints + refine.count <= limit else {
            throw AIMaskError.pointLimitExceeded(limit: limit)
        }
        do {
            for point in refine {
                switch point.role {
                case .included:
                    try request.addIncludedPoint(point.point.visionPoint)
                case .excluded:
                    try request.addExcludedPoint(point.point.visionPoint)
                }
            }
        } catch let error as AIMaskError {
            throw error
        } catch {
            // Vision's own limit threw first (budget semantics differ) —
            // surface it through the same typed face.
            throw AIMaskError.pointLimitExceeded(limit: limit)
        }
        return request
    }

    // MARK: - Person segmentation (Plan 07-2 skinSmooth's matte leg)

    /// The person matte (`GeneratePersonSegmentationRequest`, OS-built-in,
    /// offline) — the skin chain's background exclusion (background
    /// skin-toned wood/sandstone must not enter the skin mask,
    /// 07-RESEARCH §2.2). Output at the model's resolution — the caller
    /// resamples to the target plane (AIMaskResample.bilinear via
    /// SkinRegionLocator).
    public static func personSegmentationMask(
        input: AIMaskInput,
        quality: GeneratePersonSegmentationRequest.QualityLevel = .accurate,
        device: AIDevicePolicy = .anePreferred
    ) async throws -> AIMaskPlane {
        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        try refusePin(device, legacy: "personSeg")
        let handler = ImageRequestHandler(input.ciImage)
        do {
            let observation = try await handler.perform(request)
            return try observation.pixelBuffer.withUnsafeBuffer { buffer in
                try maskPlane(from: buffer)
            }
        } catch let error as AIMaskError {
            throw error
        } catch {
            throw AIMaskError.inferenceFailed(String(describing: error))
        }
    }

    /// Apply the policy to the face-landmarks request (Plan 07-2's
    /// `VisionFaceLandmarkProvider` seam).
    ///
    /// PIN REALITY (07-2, D-07-2-T3-4): `GeneratePersonSegmentationRequest`
    /// and `DetectFaceLandmarksRequest` predate the compute-device API —
    /// neither exposes `supportedComputeStageDevices`/`setComputeDevice`.
    /// A pin request is therefore REFUSED with a typed error (the layer
    /// A/B guard semantics — an impossible pin must never trap); the
    /// default `.anePreferred` (no pin) is the only supported policy and
    /// Vision routes both OS-built-in models itself (deterministic
    /// run-to-run, 07-1 D-07-1-T1-2's unpinned-layer-B precedent).
    static func refusePin(_ policy: AIDevicePolicy, legacy name: String) throws {
        guard case .anePreferred = policy else {
            throw AIMaskError.deviceUnavailable(
                "pin refused: \(name) exposes no compute-device API (legacy Vision request)")
        }
    }

    /// The IOP-side provider seam (SkinRegionLocator's
    /// VisionFaceLandmarkProvider) — the pin-refusal guard, public for the
    /// cross-module call.
    public static func apply(
        _ policy: AIDevicePolicy, toFaceLandmarks request: inout DetectFaceLandmarksRequest
    ) throws {
        // No setComputeDevice surface — see refusePin's note.
        try refusePin(policy, legacy: "faceLandmarks")
    }

    // MARK: - Device policy

    /// Apply the policy to a layer-A (struct) request. Every pin is
    /// validated against the request's supported map FIRST (the trap
    /// guard — see AIDevicePolicy).
    static func apply(
        _ policy: AIDevicePolicy, to request: inout GenerateForegroundInstanceMaskRequest
    ) throws {
        guard let device = try pinnedDevice(policy) else { return }
        let supported = request.supportedComputeStageDevices[.main] ?? []
        guard supported.contains(where: { sameDevice($0, device) }) else {
            throw AIMaskError.deviceUnavailable(
                "pin rejected: device not in layer A supportedComputeStageDevices " +
                    "(\(supported.map(\.description)))")
        }
        request.setComputeDevice(device, for: .main)
        request.setComputeDevice(device, for: .postProcessing)
    }

    /// Apply the policy to a layer-B (class) request (same trap guard,
    /// plus the layer-B pin bug guard below).
    static func pin(_ policy: AIDevicePolicy, to request: GenerateIterativeSegmentationRequest) throws {
        guard let device = try pinnedDevice(policy) else { return }
        // LAYER-B PIN BUG GUARD (07-1 probe finding, macOS 27.0b 26A428 —
        // 07-1-DECISIONS D-07-1-T1-2): although supportedComputeStageDevices
        // reports [gpu], pinning layer B to ANY device aborts the process
        // (EXC_BREAKPOINT, "recursively lock an os_unfair_lock" in
        // Foundation) — a Vision beta bug. The service REFUSES the pin with
        // a typed error instead of crashing; the default (unpinned) path is
        // the only safe layer-B execution on this OS (and IS deterministic
        // run-to-run — probe-verified byte-identical).
        if #available(macOS 27.0, *) {
            throw AIMaskError.deviceUnavailable(
                "layer B device pin refused on this OS build (Vision beta bug: any " +
                    "pin aborts the process) — use .anePreferred for layer B")
        }
        let supported = request.supportedComputeStageDevices[.main] ?? []
        guard supported.contains(where: { sameDevice($0, device) }) else {
            throw AIMaskError.deviceUnavailable(
                "pin rejected: device not in layer B supportedComputeStageDevices " +
                    "(\(supported.map(\.description)))")
        }
        request.setComputeDevice(device, for: .main)
        request.setComputeDevice(device, for: .postProcessing)
    }

    /// The concrete device for a pin policy (nil = the no-pin default).
    static func pinnedDevice(_ policy: AIDevicePolicy) throws -> MLComputeDevice? {
        switch policy {
        case .anePreferred: return nil
        case .gpuPinned:
            for d in MLComputeDevice.allComputeDevices {
                if case .gpu = d { return d }
            }
            throw AIMaskError.deviceUnavailable("no GPU device in MLComputeDevice.allComputeDevices")
        case .cpuPinned:
            for d in MLComputeDevice.allComputeDevices {
                if case .cpu = d { return d }
            }
            throw AIMaskError.deviceUnavailable("no CPU device in MLComputeDevice.allComputeDevices")
        }
    }

    /// MLComputeDevice equality (enum with associated values is Equatable;
    /// the explicit match keeps the future-case warning visible).
    static func sameDevice(_ a: MLComputeDevice, _ b: MLComputeDevice) -> Bool {
        a == b
    }

    /// The supported-stage device map for a fresh layer-A request (the
    /// tests' CPU-residency enumeration probe).
    public static func layerASupportedDevices() -> [ComputeStage: [MLComputeDevice]] {
        GenerateForegroundInstanceMaskRequest().supportedComputeStageDevices
    }

    /// The supported-stage device map for a fresh layer-B request.
    public static func layerBSupportedDevices() -> [ComputeStage: [MLComputeDevice]] {
        GenerateIterativeSegmentationRequest(
            seedPoint: NormalizedPoint(x: 0.5, y: 0.5)
        ).supportedComputeStageDevices
    }

    // MARK: - Mask buffer reading

    /// Convert a Vision mask `CVPixelBuffer` into the float plane. Row 0 =
    /// the buffer's row 0 (image top — Vision mask buffers are pixel-
    /// aligned with the input; NO flip, 07-RESEARCH §1.1).
    static func maskPlane(from buffer: CVPixelBuffer) throws -> AIMaskPlane {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else {
            throw AIMaskError.invalidMask("empty mask buffer \(width)×\(height)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw AIMaskError.invalidMask("no base address")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let count = width * height
        var floats = [Float](repeating: 0, count: count)

        switch format {
        case kCVPixelFormatType_OneComponent8:
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    floats[y * width + x] = Float(p[y * bytesPerRow + x]) / 255.0
                }
            }
        case kCVPixelFormatType_OneComponent16, 0x4C303068: // 'L00h' — layer B
            // (GenerateIterativeSegmentation) emits LE UInt16; probed 07-1
            // acceptance: bpr=2·w, background 0x1376, subject 0xFEFE (half
            // interpretation would be NaN — integer, not half).
            let p = base.assumingMemoryBound(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width {
                    floats[y * width + x] = Float(p[y * (bytesPerRow / 2) + x]) / 65535.0
                }
            }
        case 0x4C303066: // 'L00f' — one-component HALF-float (the
            // generateScaledMask output format; probe-verified 07-1 T2).
            let p = base.assumingMemoryBound(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width {
                    let h = Float16(bitPattern: p[y * (bytesPerRow / 2) + x])
                    floats[y * width + x] = max(0, min(1, Float(h)))
                }
            }
        case kCVPixelFormatType_OneComponent32Float:
            let p = base.assumingMemoryBound(to: Float.self)
            for y in 0..<height {
                for x in 0..<width {
                    floats[y * width + x] = p[y * (bytesPerRow / 4) + x]
                }
            }
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32RGBA:
            // 8-bit RGBA: any channel carries the gray mask (blue-first
            // for BGRA — read the R slot of the matching layout).
            let p = base.assumingMemoryBound(to: UInt8.self)
            let channel = format == kCVPixelFormatType_32BGRA ? 2 : 0
            for y in 0..<height {
                for x in 0..<width {
                    floats[y * width + x] =
                        Float(p[y * bytesPerRow + x * 4 + channel]) / 255.0
                }
            }
        default:
            throw AIMaskError.invalidMask(
                "unsupported mask pixel format 0x\(String(format: "%08X", format))")
        }
        return AIMaskPlane(width: width, height: height, floats: floats)
    }

    /// Resolve the selection against the catalog (indices outside the
    /// catalog are a typed error — never a silent drop).
    static func resolve(
        selection: AIInstanceSelection, catalog: AIInstanceCatalog
    ) throws -> IndexSet {
        switch selection {
        case .all:
            return IndexSet(catalog.instances)
        case .subset(let set):
            let known = Set(catalog.instances)
            for index in set where !known.contains(index) {
                throw AIMaskError.invalidInput(
                    "instance \(index) not in catalog \(catalog.instances)")
            }
            return IndexSet(set)
        }
    }
}

/// Layer-A stage-1 product: the detected instance indices + the
/// observation/handler pair stage 2 needs (`generateScaledMask` requires
/// the originating handler — both ride here). `@unchecked Sendable`: the
/// observation is an immutable product (Vision marks it
/// `@unchecked Sendable` itself); the handler is Vision-Sendable.
public struct AIInstanceCatalog: @unchecked Sendable {
    /// The detected instances, sorted (the checkbox overlay's list).
    public let instances: [Int]
    let observation: InstanceMaskObservation
    let handler: ImageRequestHandler
}
