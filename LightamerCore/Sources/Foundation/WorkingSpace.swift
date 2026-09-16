import CoreGraphics
import Metal

/// The locked working color space + pixelpipe pixel format (FOUND-02).
///
/// - Working space: **linear Rec2020, scene-referred** — every iop in the
///   pixelpipe operates in this space; conversion to a display space happens
///   only at the terminal (`gamma`, Phase 2).
/// - Pixel format: **float32 RGBA** (`.rgba32Float`, 16 bytes/pixel) —
///   pixelpipe-internal format. Half-float is banned on shadow-sensitive
///   paths (LESSONS L006 banding); display-conversion may use half later.
///
/// `public` because LightamerIOP kernels and the app's Metal/CI plumbing both
/// consume these constants.
public enum WorkingSpace {

    /// Linear Rec2020 (ITU-R BT.2020, linear transfer) — the scene-referred
    /// working space (FOUND-02). Typed member `CGColorSpace.linearITUR_2020`
    /// (renamed from the legacy `rec2020Linear` spelling in recent SDKs).
    /// Force-unwrap is safe: the name is a system-provided constant that is
    /// always present on macOS.
    public static let colorSpace: CGColorSpace =
        CGColorSpace(name: CGColorSpace.linearITUR_2020)!

    /// float32 RGBA — the pixelpipe-internal texture/buffer format (FOUND-02).
    /// NOT a display format; the Phase 2 `gamma` terminal performs the
    /// display transfer at the end of the pipe.
    public static let pixelFormat: MTLPixelFormat = .rgba32Float

    /// Bytes per pixel of `pixelFormat` (4 channels x 4 bytes, float32 RGBA).
    public static let bytesPerPixel: Int = 16
}
