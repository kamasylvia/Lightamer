import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The raster mask reference (Plan 06-04 T4; IOP-MASK-03) — a mask baked
// from any current effective mask plane into a sidecar 16-bit grayscale
// PNG, referenced from the sidecar WITHOUT pixels in JSON (06-RESEARCH §6
// red line: JSON-embedded base64 is rejected — size blowup + double
// encoding).
//
// Spelling (frozen at 06-04 ship):
//   RasterMaskRef { fileName, maskHash, invert }
//   file     = <original full name>.lra.masks/<maskID>.png
//   maskHash = StableHash over the PNG FILE BYTES — the decimal-String
//              lock (#2) applies; the ONLY legal generator is StableHash
//              (L013 explicit fold)
//   invert   = the dt raster_mask_invert leg (blend.c:567-572)
// ─────────────────────────────────────────────────────────────────────────────

/// The persisted reference to one baked raster mask PNG.
public struct RasterMaskRef: Codable, Sendable, Equatable, Hashable {

    /// Decimal-String on disk (the UInt64 lock); StableHash over the PNG
    /// file bytes — verified on every load.
    @UInt64String public var maskHash: UInt64

    /// File name INSIDE the masks directory (`<maskID>.png`).
    public var fileName: String

    /// Load-time inversion (dt raster_mask_invert).
    public var invert: Bool

    public init(fileName: String, maskHash: UInt64, invert: Bool = false) {
        self.fileName = fileName
        self._maskHash = UInt64String(wrappedValue: maskHash)
        self.invert = invert
    }
}
