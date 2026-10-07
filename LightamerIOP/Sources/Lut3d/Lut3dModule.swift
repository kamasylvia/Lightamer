import Foundation
import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// Lut3dModule (Plan 12-5 T2, IOP-COLOR-08 = PRES-03) — the .cube 3D LUT
// application iop, v50 slot 36.0 (V50Order verbatim; dt iop_order.c:261).
//
// Darktable reference: src/iop/lut3d.c
//   - interpolation enum  :1020  tetrahedral | trilinear | pyramid
//                         (pyramid is NOT ported — dt docs mark it
//                         experimental; RESEARCH §6.5 two-state ruling)
//   - colorspace map      :1029-1031  six dt states → we ship FOUR
//                         (sRGB / displayP3 / rec2020 / proPhotoLinear,
//                         default sRGB — the INTEROP-2/3 防呆 narrowing;
//                         T4 wires the matrices)
//   - process             : working → LUT-domain matrix → table sample →
//                         matrix back (fused into ONE kernel pass here;
//                         dt does separate colorspace passes — port
//                         delta 3 on the kernel header).
//
// NEUTRAL / DEGRADED IDENTITY (L031 red line): `lutName == nil` (the
// freshly-seeded state) or a MISSING library entry (a preset carried from
// another machine — D-12-CONTEXT-5/D-6 documented exception, 12-4 D10)
// both take the blit-identity fast path through
// `metal.makeRoutedCommandBuffer()` — the ONE routed acquisition point
// (PixelPipe.swift:466; LESSONS L031: a hardwired queue blit races the
// export chain's compute cross-queue). Cache-neutral, exposure-0EV style.
//
// Table texture: rgba32Float (RESEARCH §6.4 upgrade leg — the DEFAULT was
// rgba16Float, but the T2 golden gate BREACHED it on HDR random tables
// (values up to ±2.8: half table representation error ≈1.4e-3 > 1/1024),
// triggering the pre-planned upgrade — zero kernel rewrite under access::read; DECISIONS D7).
// ─────────────────────────────────────────────────────────────────────────

/// The application color space of the LUT (RESEARCH §6.6): the four-state
/// INTEROP-2/3 防呆 narrowing of dt's six (lut3d.c:1029-1031), default sRGB.
public enum LutColorspace: String, Codable, Sendable, CaseIterable {
    case sRGB
    case displayP3
    case rec2020
    case proPhotoLinear
}

public enum LutInterpolation: String, Codable, Sendable, CaseIterable {
    case tetrahedral
    case trilinear
}

public final class Lut3dModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// The LUT library-relative file name (D-6: the raw path is dropped
        /// at import so references never rot; D-12-CONTEXT-5: presets carry
        /// this name — cross-machine portability presumes the LUT library
        /// itself is copied, the documented 12-4 D10 exception).
        /// nil = neutral (no LUT loaded — the blit identity).
        public var lutName: String?
        /// The color space the LUT's table values are expressed in.
        public var colorspace: LutColorspace
        public var interpolation: LutInterpolation
        /// The LUT's authoring encodings (M3-1-01 KD-3, OQ-1①): nil = the
        /// UNANNOTATED default pair `{linear_rec2020, linear_rec2020}` =
        /// the working-space passthrough. Additive optional — the synthesized
        /// encoder omits nil keys, so every pre-M3 params blob encodes
        /// byte-identically (the paramsHash zero-drift contract, pinned by
        /// testParamsEncodingZeroDrift). Decode is tolerant: a missing key
        /// decodes nil; an unknown rawValue degrades to nil (never a throw
        /// into the sidecar loader).
        public var inputEncoding: LutEncodingId?
        public var outputEncoding: LutEncodingId?

        public init(
            lutName: String? = nil, colorspace: LutColorspace = .sRGB,
            interpolation: LutInterpolation = .tetrahedral,
            inputEncoding: LutEncodingId? = nil, outputEncoding: LutEncodingId? = nil
        ) {
            self.lutName = lutName
            self.colorspace = colorspace
            self.interpolation = interpolation
            self.inputEncoding = inputEncoding
            self.outputEncoding = outputEncoding
        }

        private enum CodingKeys: String, CodingKey {
            case lutName, colorspace, interpolation, inputEncoding, outputEncoding
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lutName = try c.decodeIfPresent(String.self, forKey: .lutName)
            colorspace = try c.decodeIfPresent(LutColorspace.self, forKey: .colorspace) ?? .sRGB
            interpolation =
                try c.decodeIfPresent(LutInterpolation.self, forKey: .interpolation)
                ?? .tetrahedral
            inputEncoding = try? c.decodeIfPresent(LutEncodingId.self, forKey: .inputEncoding)
            outputEncoding = try? c.decodeIfPresent(LutEncodingId.self, forKey: .outputEncoding)
        }
    }

    public static let opName = "lut3d"

    /// dt v50 slot 36.0 (V50Order table verbatim; iop_order.c:261) —
    /// inside the creative band, before colisa 47.0, well below the
    /// terminal tail floor 70.0 (layer-internal legality).
    public static let iopOrder: Float = 36.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Kernel function names (default.metallib of the IOP bundle).
    public enum Kernel {
        public static let tetrahedral = "lut3d_tetrahedral"
        public static let trilinear = "lut3d_trilinear"
        public static let ramp1D = "lut3d_1d"
    }

    /// The LUT resolution seam: T5's `LutLibraryStore` conforms; tests
    /// inject in-memory tables. The module NEVER touches disk itself.
    public protocol LutResolving: Sendable {
        func lut(named: String) -> CubeLut?
    }

    /// MSL mirror of `Lut3dUniforms` (Lut3dKernels.metal) — scalar fields
    /// only (MSL float3 in constant buffers is 16-byte aligned; three
    /// scalars sidestep the padding trap). Matrices are 9-float tuples,
    /// row-major.
    struct Uniforms {
        var width: UInt32 = 0
        var height: UInt32 = 0
        var level: UInt32 = 0
        var domainMinX: Float = 0
        var domainMinY: Float = 0
        var domainMinZ: Float = 0
        var domainMaxX: Float = 1
        var domainMaxY: Float = 1
        var domainMaxZ: Float = 1
        var fwd: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (1, 0, 0, 0, 1, 0, 0, 0, 1)
        var inv: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (1, 0, 0, 0, 1, 0, 0, 0, 1)
    }

    private let resolver: LutResolving?
    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var uniformBuffer: (any MTLBuffer)?
    private var clutTexture: (any MTLTexture)?
    private var rampTexture: (any MTLTexture)?
    private var committed: Params?
    /// The committed table shape — selects the 3D lattice vs the 1D ramp
    /// kernel at process time.
    private var committedIs1D = false

    /// M4/L069 family guard (08dd061 same shape, checker M4): overlapping
    /// renderPreview tasks share the coordinator's live box set, so ONE
    /// instance can run `process`/`commitParams` concurrently. The lock
    /// guards every reference-bearing mutable window (commitParams body,
    /// the process ref extraction, and the shared uniform buffer's per-run
    /// stamp window). Every locked section is synchronous — zero awaits.
    /// The GPU-side read-ordering residual (a stamped command buffer
    /// executing after a later stamp) is the coordinator-level render
    /// serialization item, registered under M4 — same deferral as
    /// ToneEqualModule.
    private let stateLock = NSLock()

    // MARK: - Encoding composite bake (M3-1-01 KD-3, Alcedo lut_bake)

    /// One composite-cache entry identity (Alcedo `CompositeKey` :88-101
    /// shape: source content + domain + the encoding pair).
    struct CompositeKey: Hashable, Sendable {
        let sourceHash: UInt64
        let input: LutEncodingId
        let output: LutEncodingId
    }

    /// The composite LRU capacity (Alcedo `CompositeCache` :117-158).
    static let compositeCacheLimit = 16

    private var compositeCache: [CompositeKey: [SIMD3<Float>]] = [:]
    private var compositeOrder: [CompositeKey] = []  // least-recent first
    private var bakeCountStorage = 0
    private var lastCompositedStorage: [SIMD3<Float>]?

    /// Observable bake counter (Alcedo `g_bake_count` :354-356 — instance
    /// level; test face). Counts COMPOSITE bakes only: the fast path and
    /// LRU hits never increment.
    var bakeCount: Int { stateLock.withLock { bakeCountStorage } }

    /// The last baked composite table (test observability — the voxel-level
    /// golden compares this against the Float64 CPU reference).
    var lastCompositedTable: [SIMD3<Float>]? { stateLock.withLock { lastCompositedStorage } }

    /// The unannotated default pair — both ends the working space itself.
    static func isDefaultPair(_ params: Params) -> Bool {
        (params.inputEncoding ?? LutEncodingCatalog.defaultInputId)
            == LutEncodingCatalog.defaultInputId
            && (params.outputEncoding ?? LutEncodingCatalog.defaultOutputId)
                == LutEncodingCatalog.defaultOutputId
    }

    /// The composite-key source hash: table bytes + domain (the KD-3
    /// `{源表 StableHash(data+domain)}` form — FNV-1a over the float
    /// bit patterns, never Swift Hasher, L013).
    static func compositeSourceHash(_ lut: CubeLut) -> UInt64 {
        var hash = lut.data.withUnsafeBytes {
            StableHash.combine(StableHash.fnvOffsetBasis, $0)
        }
        hash = withUnsafeBytes(of: lut.domainMin) { StableHash.combine(hash, $0) }
        hash = withUnsafeBytes(of: lut.domainMax) { StableHash.combine(hash, $0) }
        return hash
    }

    /// Alcedo `Compose` (lut_bake.cpp:273 =
    /// `LutOutputToAcescc(SampleLutTable(source, AcesccToLutInput(node)))`),
    /// per composite voxel over the UNIT domain at the SOURCE table's size
    /// (checker M5 ①② — no 65³ resample, no non-unit quality loss):
    ///
    /// 1. input arm (`AcesccToLutInput` :241-255): working (linear Rec2020)
    ///    → input-gamut linear → transfer/display ENCODE into the LUT's
    ///    input encoding — the SAMPLE POSITION;
    /// 2. CPU reference sample of the source table (through the source
    ///    domain);
    /// 3. output arm (`LutOutputToAcescc` :257-271): output-encoding
    ///    DECODE back to light → output-gamut → working Rec2020 linear.
    ///
    /// Float64 channel math, `concurrentPerform` per lattice slice
    /// (Alcedo's thread pool :300-313 — deterministic index merge, no
    /// await). Zero new kernels: the composite rides the existing table
    /// upload.
    static func bakedCompositeTable(
        lut: CubeLut, input: LutEncoding, output: LutEncoding
    ) -> [SIMD3<Float>] {
        let level = lut.kind.size
        let inGamut = LutEncodingCatalog.gamut(id: input.gamutId)!
        let outGamut = LutEncodingCatalog.gamut(id: output.gamutId)!
        let d = Double(level - 1)
        var result = [SIMD3<Float>](repeating: .zero, count: lut.data.count)
        result.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: level) { z in
                for y in 0..<level {
                    let base = z * level * level + y * level
                    for x in 0..<level {
                        let voxel = SIMD3(Double(x) / d, Double(y) / d, Double(z) / d)
                        let linear = inGamut.fromRec2020 * voxel
                        let position: SIMD3<Double> =
                            input.referral == .scene
                            ? LutTransferMath.encode(input.transfer, linear)
                            : LutTransferMath.displayEncode(
                                input.transfer, linear, peakNits: input.peakNits)
                        let sampled = sampleTable(lut, position: position)
                        let light: SIMD3<Double> =
                            output.referral == .scene
                            ? LutTransferMath.decode(output.transfer, sampled)
                            : LutTransferMath.displayDecode(
                                output.transfer, sampled, peakNits: output.peakNits)
                        let value = outGamut.toRec2020 * light
                        buffer[base + x] = SIMD3(
                            Float(value.x), Float(value.y), Float(value.z))
                    }
                }
            }
        }
        return result
    }

    /// The CPU reference sampler — the kernel's sample leg double-written
    /// (Lut3dKernelTests.cpuLut3d minus the colorspace matrices): DOMAIN
    /// remap, lattice map, tetrahedral branch table (lut3d.cl:51-77
    /// verbatim), Float64.
    static func sampleTable(_ lut: CubeLut, position: SIMD3<Double>) -> SIMD3<Double> {
        let level = lut.kind.size
        let v =
            (simd_clamp(position, lut.domainMin, lut.domainMax) - lut.domainMin)
            / (lut.domainMax - lut.domainMin)
        var scaled = v * Double(level - 1)
        func clampInt(_ x: Int, _ lo: Int, _ hi: Int) -> Int { min(max(x, lo), hi) }
        let rgbi = SIMD3<Int>(
            clampInt(Int(scaled.x.rounded(.toNearestOrEven)), 0, level - 2),
            clampInt(Int(scaled.y.rounded(.toNearestOrEven)), 0, level - 2),
            clampInt(Int(scaled.z.rounded(.toNearestOrEven)), 0, level - 2))
        scaled -= SIMD3<Double>(rgbi)

        func entry(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Double> {
            SIMD3<Double>(lut.data[x + y * level + z * level * level])
        }
        let c000 = entry(rgbi.x, rgbi.y, rgbi.z)
        let c100 = entry(rgbi.x + 1, rgbi.y, rgbi.z)
        let c010 = entry(rgbi.x, rgbi.y + 1, rgbi.z)
        let c110 = entry(rgbi.x + 1, rgbi.y + 1, rgbi.z)
        let c001 = entry(rgbi.x, rgbi.y, rgbi.z + 1)
        let c101 = entry(rgbi.x + 1, rgbi.y, rgbi.z + 1)
        let c011 = entry(rgbi.x, rgbi.y + 1, rgbi.z + 1)
        let c111 = entry(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)
        let d = scaled
        // The kernel's tetrahedral branch table (the bake always samples
        // tetrahedral — the interpolation param applies to the per-pixel
        // GPU sampling of the COMPOSITE, not to its construction).
        let out: SIMD3<Double>
        if d.x > d.y {
            if d.y > d.z {
                out = (1 - d.x) * c000 + (d.x - d.y) * c100 + (d.y - d.z) * c110 + d.z * c111
            } else if d.x > d.z {
                out = (1 - d.x) * c000 + (d.x - d.z) * c100 + (d.z - d.y) * c101 + d.y * c111
            } else {
                out = (1 - d.z) * c000 + (d.z - d.x) * c001 + (d.x - d.y) * c101 + d.y * c111
            }
        } else {
            if d.z > d.y {
                out = (1 - d.z) * c000 + (d.z - d.y) * c001 + (d.y - d.x) * c011 + d.x * c111
            } else if d.z > d.x {
                out = (1 - d.y) * c000 + (d.y - d.z) * c010 + (d.z - d.x) * c011 + d.x * c111
            } else {
                out = (1 - d.y) * c000 + (d.y - d.x) * c010 + (d.x - d.z) * c110 + d.z * c111
            }
        }
        return out
    }

    /// The LRU-backed composite lookup (Alcedo `CompositeCache` :117-158;
    /// hit = zero rebake, miss = bake + insert, evict least-recent past 16).
    /// Caller holds stateLock.
    private func compositedTable(
        lut: CubeLut, input: LutEncoding, output: LutEncoding
    ) -> [SIMD3<Float>] {
        let key = CompositeKey(
            sourceHash: Self.compositeSourceHash(lut), input: input.id, output: output.id)
        if let cached = compositeCache[key] {
            compositeOrder.removeAll { $0 == key }
            compositeOrder.append(key)
            return cached
        }
        bakeCountStorage += 1
        let table = Self.bakedCompositeTable(lut: lut, input: input, output: output)
        compositeCache[key] = table
        compositeOrder.append(key)
        while compositeOrder.count > Self.compositeCacheLimit {
            let evicted = compositeOrder.removeFirst()
            compositeCache[evicted] = nil
        }
        lastCompositedStorage = table
        return table
    }

    public init(device: (any MTLDevice)? = nil, resolver: LutResolving? = nil) {
        self.device = device
        self.resolver = resolver
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// Commit: encode the uniforms + upload the rgba32Float table.
    /// `piece.data == nil` marks the neutral/missing-degraded identity.
    /// Hashes the RAW params (D-H4) — the degradation is a process-time
    /// concern, never a cache-identity one.
    ///
    /// M3-1-01 KD-3: with a non-default encoding pair (or a non-unit table
    /// domain), the pair is BAKED into the table body here (Alcedo
    /// `ResolveLmtSampledTable` :317-352) — the composite rides the normal
    /// upload with UNIT-domain uniforms (checker M5 ③). The default pair +
    /// unit domain takes the fast path (source table verbatim, zero bake —
    /// Alcedo :321-323). Encoding pairs never apply to 1D tables.
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let lutName = params.lutName, let resolver,
            let lut = resolver.lut(named: lutName)
        else {
            // Neutral (nil name) or degraded (missing entry — the D-6
            // documented cross-machine exception): the blit identity.
            piece.data = nil
            return
        }
        let is1D: Bool
        let size: Int
        switch lut.kind {
        case .lut3d(let s): is1D = false; size = s
        case .lut1d(let s): is1D = true; size = s
        }

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }

        // Table assembly (bake + LRU + all reference mutations) under the
        // state lock — synchronous, no awaits (the L069/08dd061 shape).
        stateLock.withLock {
            resolvedDevice = resolved

            if uniformBuffer == nil {
                uniformBuffer = resolved.makeBuffer(
                    length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
            }
            guard uniformBuffer != nil else {
                piece.data = nil
                return
            }

            var table = lut
            var domainMin = lut.domainMin
            var domainMax = lut.domainMax
            // The fast path is the DEFAULT PAIR ALONE (OQ-1① byte contract —
            // stronger than Alcedo's `IsWorkingSpace && HasUnitDomain`
            // :321-323: a non-unit-domain table under the default pair keeps
            // its verbatim bytes AND its native domain uniforms, which the
            // HDR-domain storage tests pin; the domain remap only happens
            // inside a real pair bake). DECISIONS records the deviation.
            if !is1D, !Self.isDefaultPair(params),
                let inputRow = LutEncodingCatalog.find(
                    id: (params.inputEncoding ?? LutEncodingCatalog.defaultInputId).rawValue),
                let outputRow = LutEncodingCatalog.find(
                    id: (params.outputEncoding ?? LutEncodingCatalog.defaultOutputId).rawValue)
            {
                let composite = compositedTable(lut: lut, input: inputRow, output: outputRow)
                table = CubeLut(
                    kind: lut.kind, domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(1, 1, 1),
                    data: composite)
                domainMin = SIMD3(0, 0, 0)
                domainMax = SIMD3(1, 1, 1)
            }

            var uniforms = Uniforms()
            if is1D {
                // The GLOBAL INPUT_RANGE governs the 1D remap (RESEARCH §6.3);
                // fall back to DOMAIN.x when the file carries only DOMAIN keys.
                // No keys at all = 0..1, the sRGB-encoded face (§6.6).
                let range = lut.inputRange ?? SIMD2(
                    Double(lut.domainMin.x), Double(lut.domainMax.x))
                uniforms.domainMinX = Float(range.x)
                uniforms.domainMinY = Float(range.x)
                uniforms.domainMinZ = Float(range.x)
                uniforms.domainMaxX = Float(range.y)
                uniforms.domainMaxY = Float(range.y)
                uniforms.domainMaxZ = Float(range.y)
            } else {
                uniforms.domainMinX = Float(domainMin.x)
                uniforms.domainMinY = Float(domainMin.y)
                uniforms.domainMinZ = Float(domainMin.z)
                uniforms.domainMaxX = Float(domainMax.x)
                uniforms.domainMaxY = Float(domainMax.y)
                uniforms.domainMaxZ = Float(domainMax.z)
            }
            let (fwd, inv) = LutColorspaceMatrices.matrices(for: params.colorspace)
            withUnsafeBytes(of: fwd) { f in
                withUnsafeBytes(of: inv) { n in
                    withUnsafeMutableBytes(of: &uniforms.fwd) { $0.copyMemory(from: f) }
                    withUnsafeMutableBytes(of: &uniforms.inv) { $0.copyMemory(from: n) }
                }
            }

            if is1D {
                ensureRampTexture(lut: lut, size: size, device: resolved)
            } else {
                ensureClutTexture(data: table.data, size: size, device: resolved)
            }
            committedIs1D = is1D

            if let buffer = uniformBuffer {
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: MemoryLayout<Uniforms>.stride)
                }
            }
            committed = params
            piece.data = uniformBuffer
        }
    }

    /// Upload/refresh the 3D table texture (rgba32Float, RESEARCH §6.4
    /// upgrade leg). Takes the (possibly baked composite) table data —
    /// the caller owns the table/domain selection. Re-writes the region on
    /// every commit — cheap (33³ ≈ 287KB) and it keeps the texture correct
    /// when the name is re-pointed at another table of the same size.
    private func ensureClutTexture(
        data: [SIMD3<Float>], size: Int, device: any MTLDevice
    ) {
        if clutTexture == nil || clutTexture!.width != size || clutTexture!.height != size
            || clutTexture!.depth != size
        {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D
            descriptor.pixelFormat = .rgba32Float
            descriptor.width = size
            descriptor.height = size
            descriptor.depth = size
            descriptor.mipmapLevelCount = 1
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            clutTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let texture = clutTexture else { return }
        // data is already in kernel index order (parser red-fastest lock) —
        // one region write, no swizzle.
        var floats = [Float]()
        floats.reserveCapacity(data.count * 4)
        for v in data {
            floats.append(v.x)
            floats.append(v.y)
            floats.append(v.z)
            floats.append(1.0)
        }
        floats.withUnsafeBytes { raw in
            let bytesPerRow = size * 16
            let bytesPerImage = bytesPerRow * size
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: size, height: size, depth: size))
            texture.replace(
                region: region, mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
        clutTexture = texture
    }

    /// Upload/refresh the 1D ramp texture (rgba32Float texture1d — the r/g/b
    /// channels ARE the three curves; the texture2d wide-strip fallback
    /// stays unused, DECISIONS D8).
    private func ensureRampTexture(lut: CubeLut, size: Int, device: any MTLDevice) {
        if rampTexture == nil || rampTexture!.width != size {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type1D
            descriptor.pixelFormat = .rgba32Float
            descriptor.width = size
            descriptor.mipmapLevelCount = 1
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            rampTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let texture = rampTexture else { return }
        var floats = [Float]()
        floats.reserveCapacity(lut.data.count * 4)
        for v in lut.data {
            floats.append(v.x)
            floats.append(v.y)
            floats.append(v.z)
            floats.append(1.0)
        }
        floats.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: size, height: 1, depth: 1)),
                mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                bytesPerRow: size * 16, bytesPerImage: size * 16)
        }
    }

    // MARK: ROI (pointwise — dt lut3d SUPPORTS_BLENDING | ALLOW_TILING with
    // zero halo; every pixel samples the table independently)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    // MARK: Process

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        // Neutral (lutName nil) / degraded (missing library entry): the
        // blit identity — routed, L031 (a hardwired queue blit races the
        // export chain's compute cross-queue).
        // Ref extraction under the state lock (M4/L069 shape): snapshot
        // the reference state into locals once; everything past this point
        // touches locals only.
        let (table, is1D, interpolation): ((any MTLTexture)?, Bool, LutInterpolation) =
            stateLock.withLock {
                (committedIs1D ? rampTexture : clutTexture, committedIs1D,
                 committed?.interpolation ?? .tetrahedral)
            }
        guard piece.data != nil, let table else {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let functionName: String
        if is1D {
            functionName = Kernel.ramp1D
        } else {
            functionName = interpolation == .trilinear
                ? Kernel.trilinear : Kernel.tetrahedral
        }
        // The encoder session is acquired OUTSIDE the lock (await); the
        // per-run stamp + submission window below is atomic per instance
        // (the shared uniform buffer's :329-332 stamp — the DECISIONS M4
        // scope; sync-only inside the lock).
        let session = try await metal.makeEncoder(functionName: functionName)
        try stateLock.withLock {
            // Stamp the RUN geometry into the shared uniforms (commit-time
            // carries level/domain/matrices; width/height/level are per-run —
            // the kernel's gid guard reads them, so zeroes would silently
            // no-op every thread; caught by T2's module-path test).
            let uniforms = piece.data!.contents().assumingMemoryBound(to: Uniforms.self)
            uniforms.pointee.width = UInt32(output.width)
            uniforms.pointee.height = UInt32(output.height)
            uniforms.pointee.level = UInt32(table.width)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(output, index: 1)
            session.encoder.setTexture(table, index: 2)
            session.encoder.setBuffer(piece.data!, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: output.width, height: output.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
            )
            session.encoder.endEncoding()  // L008: encode close precedes commit
        }
        session.commandBuffer.commit()
    }

    /// Whole-window blit (SharpenModule shape) — routed (L031).
    private func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
    }
}
