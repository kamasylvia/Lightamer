import CoreGraphics
import CoreImage
import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// ExportGainMapEncoder (M6-3-01, ALCE-03) — the ISO 21496-1 gain map JPEG
// encode leg (RESEARCH §1.4 D/E/F arms, spike-verified CI full-service path):
//
//   CIContext.writeJPEGRepresentation(of: sdrBaseCIImage, to:, colorSpace:,
//   options: [.hdrImage: hdrLinearCIImage, .quality: q])
//
// CI computes the gain map (HDR/SDR ratio) and writes the complete ISO
// 21496-1 container (MPF APP2 index + ISO APP2 URN + trailing gain map
// subimage + Apple HDRToneMap metadata). The HDR plane MUST be LINEAR LIGHT
// (E4 counter-proof: PQ/HLG code values produce a legal container with
// non-physical gain semantics) — the capture seam pins the plane at the DRT
// tail's pre-EOTF linear stage (OQ-1/D-M6-3-1), structurally excluding the
// forbidden shape; validate gate ⑤ (D-M6-3-7) refuses the HDR-encoding base.
//
// This file carries TWO T1 faces before the T2 encode leg:
//   • `ExportGainMapHDRPlane` — the owned-copy carrier crossing the
//     render→encode boundary OUTSIDE the contract-frozen `ExportRenderStage`
//     (ExportQueueContract zero-diff red line; the ExportQueue-level box
//     stashes/consumes it keyed by `artifact.token`).
//   • `sdrReferenceWhite` — the SDR reference white constant (203 nits), the
//     KD-1 single source consumed by the variant gates AND the UI gate AND
//     the headroom computation (three consumers, one spelling).
// ─────────────────────────────────────────────────────────────────────────────

/// The captured HDR linear plane (M6-3-01 KD-2): an OWNED copy of the DRT
/// tail's pre-EOTF working-float32 plane (display-referred linear), blit out
/// of the pipe at capture time so the pipe's scratch/pool reuse can never
/// overwrite it (`linearGainCapture` seam discipline). GPU→GPU handoff on the
/// SAME device and command queue the blit ran on — the encode leg's
/// `CIContext` is built on the carried queue so the CI write orders after the
/// blit by same-queue FIFO (no CPU readback, hence no L014 fence).
public struct ExportGainMapHDRPlane: @unchecked Sendable {

    /// The owned float32 plane (linear Rec2020 samples, WorkingSpace format).
    public let texture: any MTLTexture

    /// The queue the capture blit was committed on (the routed queue at
    /// capture time) — the encode leg builds its CIContext on it.
    let commandQueue: any MTLCommandQueue

    public let width: Int
    public let height: Int

    /// `drtOutput.peakLuminance / sdrReferenceWhite` (the content headroom
    /// handed to `imageBySettingContentHeadroom`).
    public let headroom: Float

    init(
        texture: any MTLTexture, commandQueue: any MTLCommandQueue,
        width: Int, height: Int, headroom: Float
    ) {
        self.texture = texture
        self.commandQueue = commandQueue
        self.width = width
        self.height = height
        self.headroom = headroom
    }
}

public enum ExportGainMapEncoder {

    /// The SDR reference white in nits (KD-1 single source): headroom =
    /// `peakLuminance / 203`; a peak below it means NO HDR headroom over the
    /// SDR reference white → the gain map tier is meaningless (validate gate
    /// ③ + the M2 page's peak-unavailable copy all read THIS constant).
    public static let sdrReferenceWhite: Float = 203

    /// The headroom for a record's peak (the one fold every consumer shares).
    public static func headroom(peakLuminance: Float) -> Float {
        peakLuminance / sdrReferenceWhite
    }
}

/// The render-side capture sink (M6-3-01 KD-2): the closure handed to the
/// pipe's `linearGainCapture` seam funnels through this sink, which blits the
/// plane into an OWNED texture (the pipe's scratch/pool planes are never safe
/// to hold — the next run would overwrite them) and keeps it for the
/// render→encode handoff. One capture per run (the EotfBox appears once in
/// the tail chain); a failed allocation degrades to "no plane", which the
/// encode leg's fail-loud guard turns into a typed refusal (never a silently
/// plain JPEG — KD-5/M4).
final class ExportGainMapCapture: @unchecked Sendable {

    private let lock = NSLock()
    private var plane: ExportGainMapHDRPlane?
    private let headroom: Float
    private let metal: MetalContext

    init(headroom: Float, metal: MetalContext) {
        self.headroom = headroom
        self.metal = metal
    }

    /// The captured plane, if the blit landed. Read AFTER the pipe run.
    var capturedPlane: ExportGainMapHDRPlane? {
        lock.lock()
        defer { lock.unlock() }
        return plane
    }

    /// The pipe-seam callback body: blit `texture` into an owned copy and
    /// commit it on the ROUTED queue (the same queue the pipe run writes on,
    /// so the copy orders after the producing passes by same-queue FIFO).
    func capture(texture: any MTLTexture, size: SIMD2<Int>) {
        lock.lock()
        let alreadyCaptured = plane != nil
        lock.unlock()
        guard !alreadyCaptured else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: max(size.x, 1), height: max(size.y, 1), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let owned = texture.device.makeTexture(descriptor: descriptor),
              let buffer = try? metal.makeRoutedCommandBuffer(),
              let encoder = buffer.makeBlitCommandEncoder()
        else { return }
        encoder.copy(
            from: texture,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: descriptor.width, height: descriptor.height, depth: 1),
            to: owned,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        encoder.endEncoding()
        buffer.commit()
        let queue: any MTLCommandQueue =
            MetalContext.routesToExportQueue
            ? metal.exportCommandQueue : metal.commandQueue
        let captured = ExportGainMapHDRPlane(
            texture: owned, commandQueue: queue,
            width: descriptor.width, height: descriptor.height, headroom: headroom)
        lock.lock()
        plane = captured
        lock.unlock()
    }
}
