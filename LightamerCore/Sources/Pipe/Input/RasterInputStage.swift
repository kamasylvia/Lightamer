import Foundation
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────────
// RasterInputStage — the TIFF input leg's assembly + develop-output cache
// (Plan M4-1-01 T7, KD-7). Self-contained: the PixelPipe position-0 dispatch
// wiring is M4-1-02; this plan drives the Stage directly from tests.
//
// CACHE (KD-7): the develop-output slot keyed
// `fnv(description fingerprint ⊕ geometry ⊕ bucket)` — Color Grade / DRT /
// post slider moves never re-run the leg (the upstream §5.4 semantics); the
// slot lives INSIDE the Stage (the PixelPipe-side decodeParamsHash-style
// explicit fold is 02's T2). LRU of 4 (a library load walks a handful of
// descriptions; the full-res planes dominate memory so the count is small).
//
// BUCKET-UNIFORM (KD-7): full / preview / thumbnail share ONE kernel box —
// the resolution flows in through the uploaded payload (the negotiation
// downsampled plane), never through a function constant.
//
// TYPED FAILURES (KD-6): peak ≤ 0, a singular branch matrix, a missing
// kernel/PSO, or an upload mismatch → `AppError` (never a fatalError).
//
// CORE↔IOP BOUNDARY: the TRC formulas the kernel evaluates are self-held in
// MSL; the host twins live in RasterTRC/DrtEotfMath (Core) — no LightamerIOP
// import anywhere on this leg.
// ─────────────────────────────────────────────────────────────────────────────

public final class RasterInputStage: @unchecked Sendable {

    /// The bucket-uniform resolution tags (KD-7).
    public enum Bucket: String, Sendable, CaseIterable {
        case full
        case preview
        case thumbnail
    }

    private struct CacheEntry {
        let texture: any MTLTexture
        var lastUse: UInt64
    }

    private let metal: MetalContext
    private let lock = NSLock()
    private var cache: [UInt64: CacheEntry] = [:]
    private var useClock: UInt64 = 0
    private static let cacheLimit = 4
    nonisolated(unsafe) private static var displayPSO: (any MTLComputePipelineState)?
    nonisolated(unsafe) private static var scenePSO: (any MTLComputePipelineState)?
    private static let psoLock = NSLock()

    public init(metal: MetalContext) {
        self.metal = metal
    }

    // MARK: - Entry

    /// Run the input leg for one description+payload, returning the cached
    /// develop-output plane (float32 RGBA, linear Rec2020 working space).
    /// - The branch selector (KD-6/m4①): `referral == .sceneLinear` → the
    ///   matrix kernel (the ② no-ICC and ①′ linear-ICC float32 halves);
    ///   EVERYTHING display-referred — including `origin == .iccLutConverted`
    ///   (TRC=linear → the linearize identity) → `raster_input_display`.
    public func run(
        description: RasterColorDescription,
        native: RasterNativePixels,
        bucket: Bucket
    ) async throws -> any MTLTexture {
        let key = Self.cacheKey(
            description: description, native: native, bucket: bucket)
        if let hit = cachedTexture(key) { return hit }
        let texture = try await execute(description: description, native: native)
        storeTexture(key, texture)
        return texture
    }

    /// The iccLutConverted sub-form's entry (M4-1-02 T2, KD-3 sub-form ②):
    /// the CI-converted plane — float32, linear, the LUT profile already
    /// TRC-linearized through full color management — rides the display
    /// inverse leg with the TRC identity (01 KD-5/KD-6 m4①). Same cache /
    /// typed-failure contract as `run`; the plane must be a
    /// `.rgba32Float`-family shader-readable texture (the CI pool legs
    /// deliver exactly that).
    public func runDisplayInverse(
        description: RasterColorDescription,
        plane: any MTLTexture,
        bucket: Bucket
    ) async throws -> any MTLTexture {
        let key = Self.cacheKey(
            description: description, width: plane.width, height: plane.height,
            bucket: bucket)
        if let hit = cachedTexture(key) { return hit }
        let texture = try await executeDisplayInverse(
            description: description, plane: plane)
        storeTexture(key, texture)
        return texture
    }

    /// The synchronous cache faces (NSLock must not span an await).
    private func cachedTexture(_ key: UInt64) -> (any MTLTexture)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[key] else { return nil }
        var updated = entry
        useClock &+= 1
        updated.lastUse = useClock
        cache[key] = updated
        return entry.texture
    }

    private func storeTexture(_ key: UInt64, _ texture: any MTLTexture) {
        lock.lock()
        defer { lock.unlock() }
        useClock &+= 1
        cache[key] = CacheEntry(texture: texture, lastUse: useClock)
        while cache.count > Self.cacheLimit {
            if let oldest = cache.min(by: { $0.value.lastUse < $1.value.lastUse }) {
                cache[oldest.key] = nil
            }
        }
    }

    /// The cache key (L013 field-explicit fold: the description
    /// fingerprint ⊕ geometry ⊕ bucket tag).
    public static func cacheKey(
        description: RasterColorDescription,
        native: RasterNativePixels,
        bucket: Bucket
    ) -> UInt64 {
        cacheKey(
            description: description, width: native.width, height: native.height,
            bucket: bucket)
    }

    /// The geometry-explicit key face (the display-inverse entry's shape —
    /// the CI-converted plane carries no native payload).
    public static func cacheKey(
        description: RasterColorDescription,
        width: Int, height: Int,
        bucket: Bucket
    ) -> UInt64 {
        var h = description.stableFingerprint()
        withUnsafeBytes(of: UInt64(width)) { h = StableHash.combine(h, $0) }
        withUnsafeBytes(of: UInt64(height)) { h = StableHash.combine(h, $0) }
        h = StableHash.hash("\(h)-\(bucket.rawValue)")
        return h
    }

    /// Drop every cached plane (the memory-pressure face).
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    /// The current cache occupancy (the test face).
    public var cachedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    // MARK: - Execution

    private func execute(
        description: RasterColorDescription,
        native: RasterNativePixels
    ) async throws -> any MTLTexture {
        guard description.peakLuminanceNits > 0 else {
            throw AppError.invalidParameter(
                "raster input leg: non-positive peak \(description.peakLuminanceNits)")
        }
        let input = try Self.upload(native, metal: metal)
        return try await dispatchLeg(
            description: description, input: input,
            sceneLinear: description.referral == .sceneLinear)
    }

    private func executeDisplayInverse(
        description: RasterColorDescription,
        plane: any MTLTexture
    ) async throws -> any MTLTexture {
        guard description.peakLuminanceNits > 0 else {
            throw AppError.invalidParameter(
                "raster input leg: non-positive peak \(description.peakLuminanceNits)")
        }
        return try await dispatchLeg(
            description: description, input: plane,
            sceneLinear: false) // display branch — the TRC identity arm
    }

    /// The shared uniforms + dispatch core: builds the leg uniforms from
    /// the description, allocates the working-plane output, and dispatches
    /// `raster_input_scene_linear` (the ②/①′ matrix branch) or
    /// `raster_input_display` (every display-referred arm).
    private func dispatchLeg(
        description: RasterColorDescription,
        input: any MTLTexture,
        sceneLinear: Bool
    ) async throws -> any MTLTexture {
        let params = Aces2Reference.params(
            space: Self.limitingSpace(for: description.primariesXY),
            peak: Double(description.peakLuminanceNits),
            rgcOn: false) // the raster RGC-off policy (KD-9)
        let sceneMatrix: DrtMat3? = sceneLinear
            ? try Self.sceneToRec2020Matrix(primaries: description.primariesXY)
            : nil
        let uniforms = RasterInputUniforms(
            description: description, params: params, sceneLinearMatrix: sceneMatrix)

        guard input.width >= 1, input.height >= 1 else {
            throw AppError.decodeFailed("raster input leg: degenerate input plane")
        }
        let out = try Self.makeOutputTexture(input.width, input.height, metal: metal)

        // The uniform buffer is created BEFORE the encode and held by the
        // enclosing scope — an encoder's setBuffer does not keep a
        // deallocated buffer alive past the closure (the Aces2KernelGolden
        // pattern).
        let uniformBuffer = uniforms.floats.withUnsafeBufferPointer { rows in
            metal.device.makeBuffer(
                bytes: rows.baseAddress!, length: rows.count * 16,
                options: .storageModeShared)!
        }
        let functionName = sceneLinear ? "raster_input_scene_linear" : "raster_input_display"
        try await metal.dispatch2DTexture(
            functionName: functionName, input: input, output: out,
            configure: { encoder in
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            })
        return out
    }

    // MARK: - Textures

    /// The native payload → an RGBA texture at the native bit depth
    /// (RGB triplets expanded with a full alpha; the upload is a plain
    /// numeric copy — zero color conversion).
    static func upload(
        _ native: RasterNativePixels, metal: MetalContext
    ) throws -> any MTLTexture {
        // The UNORM faces (the kernel reads texture2d<float> — a UINT
        // format read through a float texture is a type mismatch and
        // returns zeros): u8/u16 arrive normalized (code/255, code/65535 —
        // exactly the TRC code domain), f32 passes through.
        let format: MTLPixelFormat
        switch native.channelLayout {
        case .rgb8: format = .rgba8Unorm
        case .rgb16: format = .rgba16Unorm
        case .rgb32Float: format = .rgba32Float
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: native.width, height: native.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw AppError.memoryExceeded(native.width * native.height * 16)
        }
        let srcBpp = native.bytesPerPixel
        let dstBpp = native.bitsPerComponent / 8 * 4
        var rgba = [UInt8](repeating: 0, count: native.width * native.height * dstBpp)
        let componentBytes = native.bitsPerComponent / 8
        let pixelCount = native.width * native.height
        let alphaFull: [UInt8] = {
            switch native.channelLayout {
            case .rgb8: return [UInt8](repeating: 255, count: pixelCount)
            case .rgb16:
                var a = [UInt8](repeating: 0, count: pixelCount * 2)
                for i in 0..<pixelCount {
                    a[i * 2] = 0xFF; a[i * 2 + 1] = 0xFF
                }
                return a
            case .rgb32Float:
                var a = [UInt8](repeating: 0, count: pixelCount * 4)
                let one = Float(1.0).bitPattern.littleEndian
                withUnsafeBytes(of: one) { pattern in
                    for i in 0..<pixelCount {
                        for k in 0..<4 { a[i * 4 + k] = pattern[k] }
                    }
                }
                return a
            }
        }()
        for i in 0..<pixelCount {
            let src = i * srcBpp
            let dst = i * dstBpp
            for c in 0..<3 {
                for k in 0..<componentBytes {
                    rgba[dst + c * componentBytes + k] = native.data[src + c * componentBytes + k]
                }
            }
            for k in 0..<componentBytes {
                rgba[dst + 3 * componentBytes + k] = alphaFull[i * componentBytes + k]
            }
        }
        rgba.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, native.width, native.height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: native.width * dstBpp)
        }
        return texture
    }

    static func makeOutputTexture(
        _ width: Int, _ height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: width, height: height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw AppError.memoryExceeded(width * height * WorkingSpace.bytesPerPixel)
        }
        return texture
    }

    // MARK: - Branch matrices + limiting space

    /// Map the description primaries onto the seven-space limiting set
    /// (the inverse leg's gamut key; the distance metric = the sum of the
    /// primary/white chromaticity offsets).
    static func limitingSpace(
        for primaries: SIMD8<Float>
    ) -> DrtLimitingSpace {
        let candidates: [(DrtLimitingSpace, SIMD8<Float>)] = [
            (.rec709, RasterColorResolver.sRGBPrimaries),
            (.p3d65, RasterColorResolver.displayP3Primaries),
            (.adobeRGB, RasterColorResolver.adobeRGBPrimaries),
            (.rec2020, RasterColorResolver.rec2020Primaries),
            (.proPhoto, RasterColorResolver.proPhotoPrimaries),
        ]
        var best = candidates[0]
        var bestDistance = Double.greatestFiniteMagnitude
        for candidate in candidates {
            var distance = 0.0
            for i in 0..<8 {
                distance += abs(Double(candidate.1[i] - primaries[i]))
            }
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best.0
    }

    /// The scene-linear branch matrix: source primaries+white → Rec2020,
    /// CAT02 chromatic adaptation from the source white to D65
    /// (Float64; the kernel mirror packs it f32 — the T8 parity face).
    static func sceneToRec2020Matrix(
        primaries: SIMD8<Float>
    ) throws -> DrtMat3 {
        let source = Aces2Cam.Chromaticities(
            red: SIMD2(Double(primaries[0]), Double(primaries[1])),
            green: SIMD2(Double(primaries[2]), Double(primaries[3])),
            blue: SIMD2(Double(primaries[4]), Double(primaries[5])),
            white: SIMD2(Double(primaries[6]), Double(primaries[7])))
        let sourceXYZ = Aces2Cam.rgbToXyzMat(source).multiply(SIMD3(1, 1, 1))
        let target = Aces2Cam.rec2020Primaries
        let adapted = cat02Adaptation(from: sourceXYZ, to: simdRec2020WhiteXYZ())
        let rgbToXyzSource = Aces2Cam.rgbToXyzMat(source)
        // source RGB → XYZ → CAT02 → D65 XYZ → Rec2020 RGB.
        var m = multiply(adapted, rgbToXyzSource)
        m = multiply(Aces2Cam.xyzToRgbMat(target), m)
        // Singularity guard (the typed failure face): a degenerate source
        // would invert to NaNs — reject before the GPU sees it.
        let probe = m.multiply(SIMD3(1, 1, 1))
        guard probe.x.isFinite, probe.y.isFinite, probe.z.isFinite,
              abs(probe.x) > 1e-12 else {
            throw AppError.invalidParameter(
                "raster input leg: singular scene-linear matrix (degenerate primaries)")
        }
        return m
    }

    /// The CAT02 chromatic adaptation matrix (native white → target white).
    static func cat02Adaptation(from sourceWhiteXYZ: SIMD3<Double>, to targetWhiteXYZ: SIMD3<Double>) -> DrtMat3 {
        let cat02 = DrtMat3(
            r0: SIMD3(0.7328, 0.4296, -0.1624),
            r1: SIMD3(-0.7036, 1.6975, 0.0061),
            r2: SIMD3(0.0030, 0.0136, 0.9834))
        let cat02Inverse = cat02.inverted()
        let coneSource = cat02.multiply(sourceWhiteXYZ)
        let coneTarget = cat02.multiply(targetWhiteXYZ)
        var scale = DrtMat3(r0: SIMD3(1, 0, 0), r1: SIMD3(0, 1, 0), r2: SIMD3(0, 0, 1))
        for (row, cone) in zip(0..<3, [coneSource.x, coneSource.y, coneSource.z]) where cone != 0 {
            switch row {
            case 0: scale.r0.x = coneTarget.x / cone
            case 1: scale.r1.y = coneTarget.y / cone
            default: scale.r2.z = coneTarget.z / cone
            }
        }
        return multiply(cat02Inverse, multiply(scale, cat02))
    }

    static func multiply(_ a: DrtMat3, _ b: DrtMat3) -> DrtMat3 {
        func row(_ r: SIMD3<Double>, _ m: DrtMat3) -> SIMD3<Double> {
            SIMD3(
                r.x * m.r0.x + r.y * m.r1.x + r.z * m.r2.x,
                r.x * m.r0.y + r.y * m.r1.y + r.z * m.r2.y,
                r.x * m.r0.z + r.y * m.r1.z + r.z * m.r2.z)
        }
        return DrtMat3(
            r0: row(a.r0, b), r1: row(a.r1, b), r2: row(a.r2, b))
    }

    /// The Rec2020 white in XYZ (D65 at Y=1).
    static func simdRec2020WhiteXYZ() -> SIMD3<Double> {
        Aces2Cam.rgbToXyzMat(Aces2Cam.rec2020Primaries).multiply(SIMD3(1, 1, 1))
    }
}
