import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// RasterMaskStore (Plan 06-04 T4) — the sidecar PNG store for baked raster
// masks (06-RESEARCH §6): bake any current effective mask plane into a
// 16-bit grayscale PNG under `<original full name>.lra.masks/<maskID>.png`,
// reference it from the sidecar (`RasterMaskRef`, decimal-String hash),
// and load it back with FULL verification.
//
// BAKE RESOLUTION POLICY (D-06-04-T4-1): the mask bakes at the CURRENT
// composite window resolution — the plane being consumed is
// window-defined (content-anchored), windows stay bounded (D-06-CONTEXT-8),
// and a 16-bit gray PNG of a bounded window is tens of MB at worst. A
// full-decode-frame rebake is a future explicit operation, not the store's
// default.
//
// DEGRADE SEMANTICS (D-06-04-T4-2, Phase 9 reconcile alignment): a
// missing/corrupt/hash-mismatched PNG is NOT silently swallowed — the
// mask degrades to the ALL-ONES plane (the layer's chain still applies
// through its own opacity) and the result carries `degraded` + the reason
// so the UI can flag it and reconcile can prompt (the same口径 as a
// missing original).
//
// PIXEL CONTRACT: bake quantizes the float plane (clamp 0..1, round
// v·65535) to uint16; load returns v/65535. The quantization step
// (1/65535 ≈ 1.53e-5) is the bake's documented error bound — the loaded
// plane is NOT bit-identical to the source float plane, but the PNG
// round-trip itself (bake → file → load) is EXACTLY identity over the
// uint16 values.
// ─────────────────────────────────────────────────────────────────────────────

public enum RasterMaskStore {

    /// The load outcome (the degrade leg is a VALUE, not a silent default).
    public enum LoadResult {
        case plane(any MTLTexture)
        case degraded(any MTLTexture, reason: String)
    }

    /// `<original full name>.lra.masks/` beside the original — the
    /// sidecar's mask directory (the `.lra` stem + `.masks`).
    public static func masksDirectory(forImageURL imageURL: URL) -> URL {
        imageURL.deletingLastPathComponent().appendingPathComponent(
            imageURL.lastPathComponent + ".lra.masks", isDirectory: true)
    }

    // MARK: - Bake

    /// L014: fence + float read-back (a SYNC helper — `waitUntilCompleted`
    /// is unavailable from async contexts; the Phase6SidecarTests pattern).
    nonisolated private static func readPlane(
        _ plane: any MTLTexture, metal: MetalContext
    ) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        let w = plane.width, h = plane.height
        var floats = [Float](repeating: 0, count: w * h)
        floats.withUnsafeMutableBytes {
            plane.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4,
                from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return floats
    }

    /// Bake `plane` (r32Float, the premultiplied effective-opacity
    /// contract) into a 16-bit grayscale PNG. Returns the reference with
    /// the StableHash over the WRITTEN FILE BYTES.
    public static func bake(
        plane: any MTLTexture,
        directory: URL,
        fileName: String,
        invert: Bool,
        metal: MetalContext
    ) async throws -> RasterMaskRef {
        precondition(plane.pixelFormat == .r32Float, "bake needs an r32Float mask plane")
        let floats = readPlane(plane, metal: metal)
        let w = plane.width, h = plane.height
        // Quantize: clamp 0..1 → uint16 (round-half-up on v·65535).
        var pixels = [UInt16](repeating: 0, count: w * h)
        for i in 0..<floats.count {
            let clamped = min(max(floats[i], 0), 1)
            pixels[i] = UInt16((Double(clamped) * 65535.0).rounded())
        }
        let pngData = try encodeGray16PNG(pixels: &pixels, width: w, height: h)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try pngData.write(to: fileURL, options: .atomic)
        let hash = StableHash.hash(try Data(contentsOf: fileURL))
        return RasterMaskRef(fileName: fileName, maskHash: hash, invert: invert)
    }

    // MARK: - Load

    /// Load + verify: hash check over the file bytes FIRST (integrity of
    /// the exact file the reference names), then decode. Any failure
    /// degrades per D-06-04-T4-2 (a WINDOW-SIZED all-ones plane + reason).
    public static func load(
        ref: RasterMaskRef,
        directory: URL,
        windowWidth: Int,
        windowHeight: Int,
        metal: MetalContext
    ) async throws -> LoadResult {
        let fileURL = directory.appendingPathComponent(ref.fileName)
        func ones() async throws -> any MTLTexture {
            try await MaskCombiner.fill(1, width: windowWidth, height: windowHeight, metal: metal)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .degraded(
                try await ones(),
                reason: "raster mask PNG missing: \(ref.fileName)")
        }
        let bytes = try Data(contentsOf: fileURL)
        let hash = StableHash.hash(bytes)
        if hash != ref.maskHash {
            return .degraded(
                try await ones(),
                reason: "raster mask hash mismatch: \(ref.fileName) " +
                    "(file \(hash) != ref \(ref.maskHash))")
        }
        do {
            let (pixels, width, height) = try decodeGray16PNG(data: bytes)
            var plane = try textureFromPixels(pixels, width: width, height: height, metal: metal)
            // Resolution mismatch → the per-scale resample (the
            // dt_dev_get_raster_mask regeneration analog, nearest v1).
            if width != windowWidth || height != windowHeight {
                plane = try await MaskCombiner.resample(
                    plane, toWidth: windowWidth, toHeight: windowHeight, metal: metal)
            }
            if ref.invert {
                return .plane(try await MaskCombiner.invert(plane: plane, metal: metal))
            }
            return .plane(plane)
        } catch {
            return .degraded(
                try await ones(),
                reason: "raster mask PNG corrupt: \(ref.fileName) (\(error))")
        }
    }

    /// The synchronous verify-only probe (the reconcile/UI marker leg —
    /// no GPU): returns the degrade reason or nil when the reference is
    /// intact.
    public static func verify(ref: RasterMaskRef, directory: URL) -> String? {
        let fileURL = directory.appendingPathComponent(ref.fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return "raster mask PNG missing: \(ref.fileName)"
        }
        guard let bytes = try? Data(contentsOf: fileURL) else {
            return "raster mask PNG unreadable: \(ref.fileName)"
        }
        if StableHash.hash(bytes) != ref.maskHash {
            return "raster mask hash mismatch: \(ref.fileName)"
        }
        return nil
    }

    // MARK: - PNG codec (16-bit grayscale, lossless)

    /// Encode uint16 samples as a 16-bit grayscale PNG (byteOrder16Little
    /// on BOTH codec sides — the round-trip is host-consistent).
    static func encodeGray16PNG(pixels: inout [UInt16], width: Int, height: Int) throws -> Data {
        precondition(pixels.count == width * height, "pixel count mismatch")
        let bitmapInfo = CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 16,
            bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: bitmapInfo)
        guard let cg = context?.makeImage() else {
            throw AppError.unsupportedFile("gray16 CGContext creation failed")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AppError.unsupportedFile("PNG destination creation failed")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.unsupportedFile("PNG encode failed")
        }
        return data as Data
    }

    /// Decode a 16-bit grayscale PNG into uint16 samples (drawn through an
    /// explicit gray16 context so the layout is guaranteed, never the
    /// PNG's native chunk order).
    static func decodeGray16PNG(data: Data) throws -> ([UInt16], width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw AppError.unsupportedFile("PNG decode failed") }
        let width = cg.width, height = cg.height
        var pixels = [UInt16](repeating: 0, count: width * height)
        let bitmapInfo = CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 16,
            bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: bitmapInfo)
        guard let context else {
            throw AppError.unsupportedFile("gray16 CGContext creation failed")
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    // MARK: - Plane helpers

    private static func textureFromPixels(
        _ pixels: [UInt16], width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        var floats = [Float](repeating: 0, count: width * height)
        for i in 0..<floats.count { floats[i] = Float(pixels[i]) / 65535.0 }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: d) else {
            throw MetalError.bufferAllocationFailed(width * height * 4)
        }
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }
}
