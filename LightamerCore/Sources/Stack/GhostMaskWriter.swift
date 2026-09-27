import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// GhostMaskWriter (Plan 08-1 T4; RESEARCH §4) — the ghost bitmap's
// morphological cleanup + its landing as a `RasterMaskRef` sidecar PNG.
//
// Shape (research §4.2): the per-pixel deviation bitmap (the HDRMergeMath
// phase-2 ghost union) dilates by a 3×3 kernel for 2 rounds (the
// conservative halo — a one-pixel rejection is never a one-pixel object),
// then lands as a 16-bit grayscale PNG beside the product:
//   <product full name>.lra.masks/<maskID>.png
// — the frozen `RasterMaskRef` file convention (Plan 06-04): the mask rides
// the PRODUCT's sidecar directory (the product is an ordinary document, so
// its masks live exactly where every document's masks live), the hash is
// StableHash over the PNG FILE BYTES (L013 decimal-String lock via the
// `RasterMaskRef` wrapper), and the layer consumes it through the EXISTING
// Phase 6 mask face — zero new mechanisms.
//
// de-ghost OFF (`params.deGhost == false`): no residual statistics run, no
// bitmap exists, NO file is written and the product's layer stack carries
// no Ghost Suppression layer (the zero-cost档 — research §4.4).
// ─────────────────────────────────────────────────────────────────────────────

public enum GhostMaskWriter {

    /// The dilation rounds (research §4.2 — pinned 2).
    public static let dilationRounds = 2

    /// One landed ghost mask: the on-disk reference + the file URL.
    public struct LandedMask: Sendable, Equatable {
        /// The `RasterMaskRef` for the product's Ghost Suppression layer.
        public let ref: RasterMaskRef
        /// The PNG's URL (diagnostics/tests).
        public let url: URL

        public init(ref: RasterMaskRef, url: URL) {
            self.ref = ref
            self.url = url
        }
    }

    // MARK: - Morphology (3×3 dilation)

    /// Binary 3×3 dilation, `rounds` passes (a pixel survives if itself or
    /// any 8-neighbor is set). Edge treatment: out-of-frame neighbors read
    /// 0 (the dilation never grows past the frame).
    public static func dilate(
        _ bitmap: [UInt8], width: Int, height: Int, rounds: Int = dilationRounds
    ) -> [UInt8] {
        var current = bitmap
        for _ in 0..<max(0, rounds) {
            var next = current
            for y in 0..<height {
                let rowUp = max(y - 1, 0) * width
                let rowMid = y * width
                let rowDown = min(y + 1, height - 1) * width
                for x in 0..<width {
                    if current[rowMid + x] == 1 { continue }
                    let xm = max(x - 1, 0)
                    let xp = min(x + 1, width - 1)
                    let any =
                        current[rowUp + xm] == 1 || current[rowUp + x] == 1
                        || current[rowUp + xp] == 1
                        || current[rowMid + xm] == 1 || current[rowMid + xp] == 1
                        || current[rowDown + xm] == 1 || current[rowDown + x] == 1
                        || current[rowDown + xp] == 1
                    if any { next[rowMid + x] = 1 }
                }
            }
            current = next
        }
        return current
    }

    // MARK: - The RasterMaskRef landing

    /// Write the ghost bitmap as a 16-bit grayscale PNG into the PRODUCT's
    /// masks directory and return its `RasterMaskRef`.
    ///
    /// - Parameters:
    ///   - bitmap: the dilated 0/1 bytes (row-major).
    ///   - productURL: the merged product file (its `.lra.masks/` sibling
    ///     directory is created idempotently).
    ///   - maskID: the mask identity (the file stem; a fresh UUID at the
    ///     service layer).
    public static func land(
        _ bitmap: [UInt8], width: Int, height: Int,
        productURL: URL, maskID: UUID
    ) throws -> LandedMask {
        let masksDirectory = URL(fileURLWithPath: productURL.path + ".lra.masks",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: masksDirectory, withIntermediateDirectories: true)
        let fileName = maskID.uuidString + ".png"
        let fileURL = masksDirectory.appendingPathComponent(fileName)

        // 16-bit grayscale pixels (0 / 65535 — the RasterMaskRef 16-bit
        // grayscale convention; values never enter JSON).
        var pixels = [UInt16](repeating: 0, count: width * height)
        for index in pixels.indices where bitmap[index] == 1 {
            pixels[index] = 65535
        }
        let data = pixels.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw AppError.encodeFailed("ghost mask CGDataProvider failed")
        }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 16,
            bytesPerRow: width * 2,
            space: CGColorSpace(name: CGColorSpace.linearGray)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
        else {
            throw AppError.encodeFailed("ghost mask CGImage construction failed")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw AppError.encodeFailed(
                "ghost mask CGImageDestinationCreateWithURL failed")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.encodeFailed("ghost mask PNG finalize failed")
        }

        // maskHash = StableHash over the PNG FILE BYTES (the RasterMaskRef
        // contract; the decimal-String lock lives in the wrapper).
        let pngBytes = try Data(contentsOf: fileURL)
        let hash = StableHash.hash(pngBytes)
        let ref = RasterMaskRef(fileName: fileName, maskHash: hash, invert: false)
        return LandedMask(ref: ref, url: fileURL)
    }

    // MARK: - The Ghost Suppression layer (the editing closure, §4.3)

    /// The product's initial layer stack carrying the Ghost Suppression
    /// adjustment layer: an EMPTY iop chain (the user adds adjustments into
    /// the ghost regions through the Phase 6 panel) + the raster mask.
    /// nil when the product has no ghost mask (de-ghost off / no ghost
    /// pixels) — the layer stack carries no Ghost Suppression layer then.
    public static func ghostSuppressionLayerStack(
        _ mask: LandedMask?
    ) -> SidecarLayerStackRecord? {
        guard let mask else { return nil }
        let layer = AdjustmentLayer(
            id: UUID(),
            name: "Ghost Suppression",
            isVisible: true,
            opacity: 1,
            enabled: true,
            chain: [],
            mask: MaskSpec(raster: mask.ref))
        return SidecarLayerStackRecord(layers: [SidecarLayerRecord(layer)])
    }
}
