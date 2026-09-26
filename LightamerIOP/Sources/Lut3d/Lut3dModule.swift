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

        public init(
            lutName: String? = nil, colorspace: LutColorspace = .sRGB,
            interpolation: LutInterpolation = .tetrahedral
        ) {
            self.lutName = lutName
            self.colorspace = colorspace
            self.interpolation = interpolation
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
        resolvedDevice = resolved

        if uniformBuffer == nil {
            uniformBuffer = resolved.makeBuffer(
                length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
        }
        guard uniformBuffer != nil else {
            piece.data = nil
            return
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
            uniforms.domainMinX = Float(lut.domainMin.x)
            uniforms.domainMinY = Float(lut.domainMin.y)
            uniforms.domainMinZ = Float(lut.domainMin.z)
            uniforms.domainMaxX = Float(lut.domainMax.x)
            uniforms.domainMaxY = Float(lut.domainMax.y)
            uniforms.domainMaxZ = Float(lut.domainMax.z)
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
            ensureClutTexture(lut: lut, size: size, device: resolved)
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

    /// Upload/refresh the 3D table texture (rgba32Float, RESEARCH §6.4 upgrade leg).
    /// Re-writes the region on every commit — cheap (33³ ≈ 287KB) and it
    /// keeps the texture correct when the name is re-pointed at another
    /// table of the same size.
    private func ensureClutTexture(lut: CubeLut, size: Int, device: any MTLDevice) {
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
        floats.reserveCapacity(lut.data.count * 4)
        for v in lut.data {
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
        guard piece.data != nil, let table = committedIs1D ? rampTexture : clutTexture else {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let functionName: String
        if committedIs1D {
            functionName = Kernel.ramp1D
        } else {
            functionName = committed?.interpolation == .trilinear
                ? Kernel.trilinear : Kernel.tetrahedral
        }
        // Stamp the RUN geometry into the shared uniforms (commit-time
        // carries level/domain/matrices; width/height/level are per-run —
        // the kernel's gid guard reads them, so zeroes would silently
        // no-op every thread; caught by T2's module-path test).
        let uniforms = piece.data!.contents().assumingMemoryBound(to: Uniforms.self)
        uniforms.pointee.width = UInt32(output.width)
        uniforms.pointee.height = UInt32(output.height)
        uniforms.pointee.level = UInt32(table.width)
        let session = try await metal.makeEncoder(functionName: functionName)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setTexture(table, index: 2)
        session.encoder.setBuffer(piece.data!, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()  // L008: encode close precedes commit
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
