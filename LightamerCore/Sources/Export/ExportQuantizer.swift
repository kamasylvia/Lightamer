import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportQuantizer — the D-11-CONTEXT-7 quantization tiers (Plan 11-02 T1).
//
// The exit conversion (`CIContextPool.renderToEncodedBitmap`) lands float32
// RGBA values already ENCODED in the target color space (primaries + white +
// TRC in the one ColorSync render). Quantization is the last lossless-or-
// saturating step before the container:
//
//   8-bit display tier  → `roundf(CLAMP(v*0xff,   0, 0xff))`   (JPEG/PNG8/HEIC8/AVIF8/WebP)
//   16-bit display tier → `roundf(CLAMP(v*0xffff, 0, 0xffff))` (PNG16/TIFF16; HEIC10/AVIF10(12)
//                         ride the 16bpc container, the encoder requantizes —
//                         the explicit ×1023/×4095 faces exist for future
//                         direct bit-packing and are golden-pinned here)
//   32f linear tier     → identity + [0,1] clamp, NO quantization (TIFF float)
//
// The rounding formula is darktable's, byte-for-byte (imageio.c:1403-1460:
// `roundf(CLAMP(inbuf[k] * 0xff, 0, 0xff))` — ROUND, never truncation, so a
// 0.5-level value rounds UP where C's float→int cast would drop it).
//
// HDR clip semantics (D-11-CONTEXT-7): the [0,1] clamp IS the SDR-white
// luminance clip. "Chroma 不裁" is an ORDERING guarantee upstream of this
// file: values arrive already converted to the TARGET primaries (wide-gamut
// targets keep their in-gamut values; nothing here re-clamps into a narrower
// sRGB gamut). NaN follows dt's CLAMPF lower-bound branch (→ 0).
//
// PURE — no GPU, no I/O, no globals. Packed `Data` faces are the encoder
// consumption plane (Plan 11-02 T3/T4).
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportQuantizer {

    /// darktable `CLAMPF(a, mn, mx)` (common/math.h:80) verbatim branch
    /// shape: a NaN fails BOTH comparisons and lands on the LOWER bound.
    @inline(__always)
    static func clamped(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        value >= lower ? (value <= upper ? value : upper) : lower
    }

    /// 8-bit display tier. `roundf` semantics = Swift
    /// `.toNearestOrAwayFromZero` (C roundf: halfway cases AWAY from zero —
    /// 127.5 → 128, where a truncating cast would yield 127).
    public static func quantize8(_ samples: [Float]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: samples.count)
        for (i, v) in samples.enumerated() {
            out[i] = UInt8(clamped(v * 255.0, 0, 255.0).rounded(.toNearestOrAwayFromZero))
        }
        return out
    }

    /// 16-bit display tier (PNG16 / TIFF16; the HEIC 10-bit / AVIF 10(12)-bit
    /// encode paths consume the 16bpc CGImage this tier feeds and requantize
    /// internally).
    public static func quantize16(_ samples: [Float]) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: samples.count)
        for (i, v) in samples.enumerated() {
            out[i] = UInt16(clamped(v * 65535.0, 0, 65535.0).rounded(.toNearestOrAwayFromZero))
        }
        return out
    }

    /// 10-bit value domain inside a 16bpc container (×1023): the value range
    /// is [0, 1023], requantized losslessly back to 10 bits by a deep-color
    /// encoder that reads the 16bpc plane.
    public static func quantize10In16(_ samples: [Float]) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: samples.count)
        for (i, v) in samples.enumerated() {
            out[i] = UInt16(clamped(v * 1023.0, 0, 1023.0).rounded(.toNearestOrAwayFromZero))
        }
        return out
    }

    /// 12-bit value domain inside a 16bpc container (×4095).
    public static func quantize12In16(_ samples: [Float]) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: samples.count)
        for (i, v) in samples.enumerated() {
            out[i] = UInt16(clamped(v * 4095.0, 0, 4095.0).rounded(.toNearestOrAwayFromZero))
        }
        return out
    }

    /// The 32f linear tier (D-11-CONTEXT-7: TIFF float keeps LINEAR, the
    /// scene-referred handoff): identity for in-range values — quantization
    /// never bends them (bit-exact pass-through) — plus the [0,1] SDR-white
    /// clamp for HDR overs and negatives.
    public static func clampLuminance01(_ samples: [Float]) -> [Float] {
        samples.map { clamped($0, 0, 1) }
    }

    // MARK: - Packed encoder faces (Plan 11-02 T3/T4 consumption plane)

    /// Packed RGBA8: 4 bytes/pixel, host byte order (arm64 = LE).
    /// `rgba` is interleaved RGBA float32 (`width * height * 4` samples).
    public static func packedRGBA8(rgba: [Float], width: Int, height: Int) throws -> Data {
        try validateCount(rgba: rgba, width: width, height: height)
        return Data(quantize8(rgba))
    }

    /// Packed RGBA16: 8 bytes/pixel, HOST-endian UInt16 samples (arm64 =
    /// little-endian). The CGImage face MUST read it with
    /// `.byteOrder16Little` (see `ExportEncoder.makeCGImage`).
    public static func packedRGBA16(rgba: [Float], width: Int, height: Int) throws -> Data {
        try validateCount(rgba: rgba, width: width, height: height)
        let samples = quantize16(rgba)
        return samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Packed float32 RGBA: 16 bytes/pixel, host-endian floats, [0,1]-clamped
    /// (the 32f tier — values arrive target-linear from the exit leg).
    public static func packedFloat32(rgba: [Float], width: Int, height: Int) throws -> Data {
        try validateCount(rgba: rgba, width: width, height: height)
        let samples = clampLuminance01(rgba)
        return samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private static func validateCount(rgba: [Float], width: Int, height: Int) throws {
        guard width >= 1, height >= 1 else {
            throw AppError.invalidParameter(
                "export plane degenerate dimensions \(width)×\(height)")
        }
        let expected = width * height * 4
        guard rgba.count == expected else {
            throw AppError.invalidParameter(
                "export plane sample count \(rgba.count) != \(width)×\(height)×4")
        }
    }
}
