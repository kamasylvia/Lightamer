import CoreGraphics
import CoreImage
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// RasterDecoder — the NATIVE TIFF decode leg (Plan M4-1-01 T6, KD-5):
// pixels leave CGImageSource as raw bytes with ZERO color-managed
// conversion, preserving the source primaries for the inverse DRT (the OQ-2
// effective ruling — the CI working-space render bakes a primaries mapping
// the inverse cannot undo).
//
// ROUTING RED LINE (this plan): `RAWDecoder.decode()` is NOT switched —
// TIFF still flows through the existing `decodeRaster` CI path in
// production; `decodeTIFF` is test-driven only until M4-1-02 flips the
// route. A golden test pins the routing (the production decode of a TIFF
// carries nil raster fields).
//
// Pixel extraction shape: draw into a bitmap context whose colorspace
// OBJECT, bit depth and alpha face all MATCH the source — a numeric copy
// (no matching, no un-premultiplication — D6: alpha discarded, color
// rendered as stored) — then strip alpha / expand gray on the CPU:
//   • RGB 8/16/32F → RGB triplets (u8 / u16 native / f32 native);
//   • gray → the gray plane expands to channel-equal RGB;
//   • CMYK → typed `AppError.decodeFailed` (the D4 reject);
//   • multi-page → page 0.
//
// The LUT-based RGB ICC form (A2B0 with no matrix-shaper tags) is the ONLY
// TIFF form that stays on the CI leg (`CIImage(cgImage:)` full color
// management — the ColorSync equivalent of the upstream's lcms2 host
// conversion): `rasterNative` is nil there and the description records
// `iccLutConverted` (Rec.2020, linear, display-referred). The input leg
// walks `raster_input_display` for it with TRC=linear (the linearize
// identity).
//
// The content probe (KD-9): a deterministic ≤4096-cell subsampled channel
// max rides `RasterNativePixels.contentProbeMax` — the HDR flag's
// scene-linear float input (T10 consumes it as a parameter; the flag
// itself is a pure function there).
// ─────────────────────────────────────────────────────────────────────────────

/// The native pixel payload of the raster input leg (KD-5): raw source
/// bytes at native bit depth, RGB-packed (gray expanded, alpha stripped).
public struct RasterNativePixels: Sendable {

    public enum ChannelLayout: String, Sendable {
        case rgb8
        case rgb16
        case rgb32Float
    }

    /// RGB triplets, row-major, top row first (the CGImage orientation).
    public let data: [UInt8]
    public let width: Int
    public let height: Int
    public let channelLayout: ChannelLayout

    /// The deterministic content probe (≤4096-cell subsampled channel max,
    /// normalized to the [0, ∞) linear domain: u8/255, u16/65535, f32 raw).
    /// The scene-linear HDR flag's input (KD-9).
    public let contentProbeMax: Float

    public var bitsPerComponent: Int {
        switch channelLayout {
        case .rgb8: return 8
        case .rgb16: return 16
        case .rgb32Float: return 32
        }
    }

    public var bytesPerPixel: Int { bitsPerComponent / 8 * 3 }
    public var bytesPerRow: Int { bytesPerPixel * width }

    public init(
        data: [UInt8], width: Int, height: Int,
        channelLayout: ChannelLayout, contentProbeMax: Float
    ) {
        self.data = data
        self.width = width
        self.height = height
        self.channelLayout = channelLayout
        self.contentProbeMax = contentProbeMax
    }
}

public enum RasterDecoder {

    /// The native TIFF decode leg: `DecodedImage` with the additive raster
    /// fields populated (`rasterColor` + `rasterNative`, or `rasterColor`
    /// alone for the LUT-ICC CI-leg form). Production routing is NOT
    /// switched here (see the file header red line).
    public static func decodeTIFF(_ url: URL) throws -> DecodedImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw AppError.fileUnreadable(url.path)
        }
        // Multi-page → page 0 (KD-5; the CGImageSource default index).
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AppError.decodeFailed("No decodable image in \(url.lastPathComponent)")
        }

        // The CMYK typed reject (D4) — the colorspace model the platform
        // reports (probed: a CMYK TIFF presents .cmyk with no embedded ICC).
        if cgImage.colorSpace?.model == .cmyk {
            throw AppError.decodeFailed(
                "CMYK TIFF is not supported by the develop input leg "
                    + "(\(url.lastPathComponent))")
        }

        // The embedded ICC straight from the IFD (the synthesized-profile
        // ambiguity on the colorspace face forces the file route — the T3
        // probe record).
        let iccData = RasterIccParser.tiffEmbeddedICCData(at: url)

        // The LUT-based RGB form → the CI leg (the ONLY TIFF form on it).
        if let iccData, let profile = RasterIccParser.parse(iccData),
           profile.model == .rgb, !profile.hasMatrixShaper, profile.hasA2B0 {
            let description = RasterColorResolver.resolve(
                iccData: iccData, colorSpaceName: nil, isFloat: false)
            let capture = try RAWDecoder.readCaptureMetadata(url: url)
            return DecodedImage(
                ciImage: CIImage(cgImage: cgImage),
                rawTech: RAWTechnicalParams(),
                capture: capture,
                segmentationSkyMatte: nil,
                decoderVersionUsed: .v8,
                contentDedupeID: RAWDecoder.contentDedupeID(for: url),
                rasterColor: description,
                rasterNative: nil,
                embeddedGeometry: .notApplicable) // TIFF chain: no embedded geometry (X1)
        }

        // The native byte leg.
        let isFloat = cgImage.bitsPerComponent == 32
        let description = RasterColorResolver.resolve(
            iccData: iccData, colorSpaceName: nil, isFloat: isFloat)
        let native = try extractNativePixels(cgImage)
        let capture = try RAWDecoder.readCaptureMetadata(url: url)
        return DecodedImage(
            ciImage: CIImage(cgImage: cgImage),
            rawTech: RAWTechnicalParams(),
            capture: capture,
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: RAWDecoder.contentDedupeID(for: url),
            rasterColor: description,
            rasterNative: native,
            embeddedGeometry: .notApplicable) // TIFF chain: no embedded geometry (X1)
    }

    // MARK: - The negotiation-window payload (M4-1-02 T2, KD-3)

    /// The payload for ONE pipe run: extract `window` (source-pixel rect in
    /// the CGImage TOP-LEFT view space) at `targetWidth×targetHeight`,
    /// delivered TOP-ROW-FIRST — the pipe INPUT-plane convention (the CI
    /// bitmap+replace input render lands row 0 = image top; RAW03's
    /// passing pinned diagonal pins this face; the display-terminal leg
    /// owns the one flip to the row-0-bottom FINAL face). A 1:1 window →
    /// a straight row copy; a downscale → a deterministic box average
    /// over the covered source span (≤1 px source-edge rounding registered
    /// in DECISIONS); an upscale (never produced by the pipe — downscale-
    /// only) falls back to nearest sampling. The channel layout and the
    /// probe rule (≤4096-cell deterministic stride) carry over.
    public static func windowedPayload(
        _ native: RasterNativePixels, window: CGRect,
        targetWidth: Int, targetHeight: Int
    ) throws -> RasterNativePixels {
        let bounds = CGRect(x: 0, y: 0, width: native.width, height: native.height)
        guard targetWidth >= 1, targetHeight >= 1 else {
            throw AppError.invalidParameter(
                "windowed payload: degenerate target \(targetWidth)×\(targetHeight)")
        }
        let clipped = window.intersection(bounds)
        guard !clipped.isEmpty else {
            throw AppError.invalidParameter(
                "windowed payload: empty window \(window) in \(native.width)×\(native.height)")
        }
        let componentBytes = native.bitsPerComponent / 8
        let srcBpp = native.bytesPerPixel
        let outBytesPerPixel = 3 * componentBytes
        var out = [UInt8](repeating: 0, count: targetWidth * targetHeight * outBytesPerPixel)

        let sourceIsCopy = Int(clipped.width.rounded(.down)) == targetWidth
            && Int(clipped.height.rounded(.down)) == targetHeight

        func sourceComponent(_ x: Int, _ y: Int, _ c: Int) -> Double {
            // native.data is LITTLE-endian (the extraction pushes LE16 /
            // LE f32) — read it back little-endian.
            let base = (y * native.width + x) * srcBpp + c * componentBytes
            switch componentBytes {
            case 1: return Double(native.data[base])
            case 2:
                let v = UInt16(native.data[base + 1]) << 8 | UInt16(native.data[base])
                return Double(v)
            default:
                let bits = UInt32(native.data[base + 3]) << 24
                    | UInt32(native.data[base + 2]) << 16
                    | UInt32(native.data[base + 1]) << 8
                    | UInt32(native.data[base])
                return Double(Float(bitPattern: bits))
            }
        }

        func writeComponent(_ index: Int, _ c: Int, _ value: Double) {
            let base = index * outBytesPerPixel + c * componentBytes
            switch componentBytes {
            case 1: out[base] = UInt8(max(0, min(255, value.rounded())))
            case 2:
                let v = UInt16(max(0, min(65535, value.rounded())))
                out[base] = UInt8(v & 0xFF)
                out[base + 1] = UInt8(v >> 8)
            default:
                let f = Float(value)
                withUnsafeBytes(of: f.bitPattern.littleEndian) { pattern in
                    for k in 0..<4 { out[base + k] = pattern[k] }
                }
            }
        }

        let xScale = clipped.width / CGFloat(targetWidth)
        let yScale = clipped.height / CGFloat(targetHeight)
        var probeMax: Float = 0
        let cellCount = targetWidth * targetHeight
        let probeStride = max(1, cellCount / 4096)

        // Target rows run TOP-FIRST: `ty = 0` is the image top (the input
        // plane face RAW03 pins).
        for ty in 0..<targetHeight {
            let sy0 = clipped.minY + CGFloat(ty) * yScale
            let sy1 = sy0 + yScale
            let y0 = max(0, min(native.height - 1, Int(sy0.rounded(.down))))
            let y1 = max(y0, min(native.height - 1, Int(sy1.rounded(.down) - 1)))
            for tx in 0..<targetWidth {
                let sx0 = clipped.minX + CGFloat(tx) * xScale
                let sx1 = sx0 + xScale
                let x0 = max(0, min(native.width - 1, Int(sx0.rounded(.down))))
                let x1 = max(x0, min(native.width - 1, Int(sx1.rounded(.down) - 1)))
                let dstIndex = ty * targetWidth + tx
                for c in 0..<3 {
                    if sourceIsCopy {
                        writeComponent(dstIndex, c, sourceComponent(x0, y0, c))
                    } else {
                        if xScale < 1 || yScale < 1 {
                            // Nearest (upscale face — never pipe-produced).
                            writeComponent(dstIndex, c, sourceComponent(x0, y0, c))
                            continue
                        }
                        var sum = 0.0
                        var count = 0
                        var y = y0
                        while y <= y1 {
                            var x = x0
                            while x <= x1 {
                                sum += sourceComponent(x, y, c)
                                count += 1
                                x += 1
                            }
                            y += 1
                        }
                        writeComponent(dstIndex, c, count > 0 ? sum / Double(count) : 0)
                    }
                }
                // The probe (visited target cells only, the window's max).
                if dstIndex % probeStride == 0 {
                    for c in 0..<3 {
                        let v = Float(sourceComponent(x0, y0, c))
                        let normalized: Float
                        switch native.channelLayout {
                        case .rgb8: normalized = v / 255.0
                        case .rgb16: normalized = v / 65535.0
                        case .rgb32Float: normalized = v
                        }
                        if normalized > probeMax { probeMax = normalized }
                    }
                }
            }
        }

        return RasterNativePixels(
            data: out, width: targetWidth, height: targetHeight,
            channelLayout: native.channelLayout, contentProbeMax: probeMax)
    }

    // MARK: - Native pixel extraction (the numeric-copy face)

    /// Draw into a bitmap context that MATCHES the source (colorspace
    /// object, bit depth, alpha presence) — zero color conversion, no
    /// un-premultiplication — then CPU-normalize: alpha stripped, gray
    /// expanded to channel-equal RGB, wide components to native endianness.
    static func extractNativePixels(_ image: CGImage) throws -> RasterNativePixels {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw AppError.decodeFailed("TIFF has empty geometry")
        }
        let bpc = image.bitsPerComponent
        guard bpc == 8 || bpc == 16 || bpc == 32 else {
            throw AppError.decodeFailed(
                "TIFF bit depth \(bpc) is not native-decodable (8/16/32F)")
        }
        let isGray = image.colorSpace?.model == .monochrome
        let hasAlpha: Bool = {
            switch image.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return true
            }
        }()

        // The context format (host-probed 2026-10-10 — the SUPPORTED
        // CGBitmapContext matrix: plain `.none` is refused for RGB at every
        // depth; `noneSkipLast` carries the numeric copy with a dead X
        // byte the CPU walk skips; 8-bit gray takes `.none`):
        //   RGB 8/16/32F → noneSkipLast (X ignored — the STORED color sits
        //     in the first three slots unchanged);
        //   gray 8 → none (1 slot); gray+alpha 8 → premultipliedLast
        //     (the stored gray in slot 0);
        //   gray 16 → typed reject (no supported gray-16 context face;
        //     registered as the native leg's layout gap in DECISIONS).
        // Premultiplied alpha keeps the stored (associated) color values —
        // the alpha byte is simply dropped on the walk (D6: no
        // un-premultiplication).
        let alphaInfo: CGImageAlphaInfo
        switch (isGray, bpc, hasAlpha) {
        case (true, 8, false): alphaInfo = .none
        case (true, 8, true): alphaInfo = .premultipliedLast
        case (true, _, _):
            throw AppError.decodeFailed(
                "16-bit gray TIFF has no supported native context layout")
        default:
            alphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        }
        var bitmapInfo = alphaInfo.rawValue
        switch bpc {
        case 16: bitmapInfo |= CGImageByteOrderInfo.order16Big.rawValue
        case 32:
            bitmapInfo |= CGImageByteOrderInfo.order32Big.rawValue
            bitmapInfo |= CGBitmapInfo.floatComponents.rawValue
        default: break
        }
        let contextSlots = isGray ? (hasAlpha ? 2 : 1) : 4
        let componentBytes = bpc / 8
        let srcBytesPerPixel = contextSlots * componentBytes
        let stride = width * srcBytesPerPixel
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: bpc, bytesPerRow: stride,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo)
        else {
            throw AppError.decodeFailed(
                "bitmap context refused the TIFF layout (bpc=\(bpc) gray=\(isGray) alpha=\(hasAlpha))")
        }
        context.interpolationQuality = .none
        // The numeric copy: same extent, no geometry.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else {
            throw AppError.decodeFailed("bitmap context produced no data")
        }

        let outComponents = isGray ? 3 : 3  // gray expands; RGB keeps 3
        let outBytesPerPixel = outComponents * componentBytes
        var out = [UInt8](repeating: 0, count: width * height * outBytesPerPixel)
        var probeMax: Float = 0
        // The deterministic ≤4096-cell probe stride.
        let cellCount = width * height
        let probeStride = max(1, cellCount / 4096)

        // Big-endian readers over the context bytes (the context was
        // created with explicit big byte order for 16/32 bpc).
        func beU16(_ base: UnsafePointer<UInt8>, _ byteOffset: Int) -> UInt16 {
            UInt16(base[byteOffset]) << 8 | UInt16(base[byteOffset + 1])
        }
        func beF32(_ base: UnsafePointer<UInt8>, _ byteOffset: Int) -> Float {
            let bits = UInt32(base[byteOffset]) << 24
                | UInt32(base[byteOffset + 1]) << 16
                | UInt32(base[byteOffset + 2]) << 8
                | UInt32(base[byteOffset + 3])
            return Float(bitPattern: bits)
        }
        func pushLE16(_ dst: UnsafeMutablePointer<UInt8>, _ offset: Int, _ v: UInt16) {
            dst[offset] = UInt8(v & 0xFF)
            dst[offset + 1] = UInt8(v >> 8)
        }
        func pushLEF32(_ dst: UnsafeMutablePointer<UInt8>, _ offset: Int, _ v: Float) {
            withUnsafeBytes(of: v.bitPattern.littleEndian) {
                for k in 0..<4 { dst[offset + k] = $0[k] }
            }
        }

        let outCount = out.count
        out.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
            let dst = outPtr.baseAddress!.bindMemory(to: UInt8.self, capacity: outCount)
            let src = UnsafeRawPointer(raw).bindMemory(to: UInt8.self, capacity: stride * height)
            for y in 0..<height {
                for x in 0..<width {
                    let srcPx = y * stride + x * srcBytesPerPixel
                    let dstPx = (y * width + x) * outBytesPerPixel
                    for c in 0..<outComponents {
                        // The source channel index (gray → slot 0; RGB →
                        // slots 0..2 with the X slot skipped).
                        let srcCh = srcPx + (isGray ? 0 : c * componentBytes)
                        let dstCh = dstPx + c * componentBytes
                        switch bpc {
                        case 8:
                            dst[dstCh] = src[srcCh]
                        case 16:
                            pushLE16(dst, dstCh, beU16(src, srcCh))
                        default:
                            pushLEF32(dst, dstCh, beF32(src, srcCh))
                        }
                    }
                    // The probe (visited cells only).
                    if (y * width + x) % probeStride == 0 {
                        for c in 0..<outComponents {
                            let srcCh = srcPx + (isGray ? 0 : c * componentBytes)
                            let v: Float
                            switch bpc {
                            case 8: v = Float(src[srcCh]) / 255.0
                            case 16: v = Float(beU16(src, srcCh)) / 65535.0
                            default: v = beF32(src, srcCh)
                            }
                            if v > probeMax { probeMax = v }
                        }
                    }
                }
            }
        }

        let layout: RasterNativePixels.ChannelLayout
        switch bpc {
        case 8: layout = .rgb8
        case 16: layout = .rgb16
        default: layout = .rgb32Float
        }
        return RasterNativePixels(
            data: out, width: width, height: height,
            channelLayout: layout, contentProbeMax: probeMax)
    }
}