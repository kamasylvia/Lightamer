import CoreGraphics
import CoreImage
import Foundation
import Metal
import UniformTypeIdentifiers

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

    // MARK: - The encode leg (M6-3-01 T2, KD-4 — the spike D/E/F arms)

    /// The ISO 21496-1 gain map JPEG encode (KD-4, the RESEARCH §1.4 D1 call
    /// verbatim semantics): the SDR base (the quantized rgba8 plane over the
    /// target color space) + the captured linear plane (content headroom =
    /// peak/203) → `writeJPEGRepresentation` — CI computes the gain map and
    /// writes the full container (MPF APP2 index + ISO APP2 URN + trailing
    /// gain map subimage + HDRToneMap). The write lands on a SAME-DIRECTORY
    /// tmp (L009); the primary XMP rewrap (F5 form:
    /// `CGImageDestinationCopyImageSource` + `kCGImageDestinationMetadata`)
    /// mounts `hdrgm:Version` + the Software signature + the policy-gated
    /// sidecar five fields, and the final tmp promotes atomically.
    ///
    /// CALLERS (KD-5): the encodeStage gain-map arm ONLY — it bypasses the
    /// encoder registry (the layout gate does not fit the two-plane tier)
    /// and SKIPS both post-encode passes (an APP2 delete or an APP1 inject
    /// shifts the file's absolute offsets and kills the MPF subimage — the
    /// XMP is ALREADY mounted here).
    static func encode(
        plane: ExportQuantizedPlane, hdrPlane: ExportGainMapHDRPlane,
        targetColorSpace: CGColorSpace, quality: Double?,
        destination: URL, sourceURL: URL?, exifSoftware: String?,
        metadataPolicy: ExportMetadataPolicy
    ) throws -> URL {
        guard plane.layout == .rgba8 else {
            throw AppError.invalidParameter(
                "gain map jpeg needs an rgba8 base plane, got \(plane.layout.rawValue)")
        }
        guard Int(hdrPlane.width) == plane.width, Int(hdrPlane.height) == plane.height else {
            throw AppError.invalidParameter(
                "gain map plane mismatch: HDR \(hdrPlane.width)×\(hdrPlane.height) "
                    + "vs base \(plane.width)×\(plane.height)")
        }
        let fileManager = FileManager.default
        // L009: same-directory tmp names — every artifact of this encode
        // lives beside the destination until the final promotion.
        let ciTmp = destination.appendingPathExtension("gain-ci.tmp")
        let rewrapTmp = destination.appendingPathExtension("gain-xmp.tmp")
        defer {
            try? fileManager.removeItem(at: ciTmp)
            try? fileManager.removeItem(at: rewrapTmp)
        }

        // ① the SDR base CIImage (the quantized plane's CGImage construction
        //    — the SAME builder the registry encoders use, so the tier's
        //    base face is byte-identical to a plain JPEG at equal quality).
        let baseCG = try ImageIOEncodeCore.makeCGImage(
            from: plane, colorSpace: targetColorSpace)
        let baseImage = CIImage(cgImage: baseCG)

        // ② the HDR linear CIImage: the captured owned texture, linear
        //    Rec2020 samples, BOTTOM-UP read convention undone with the
        //    exit leg's down-mirror (the rows must align the base), then
        //    the content headroom (peak/203 — macOS 26+, inside the 27
        //    deployment floor, no #available).
        guard let hdrImage = CIImage(
            mtlTexture: hdrPlane.texture, options: [.colorSpace: WorkingSpace.colorSpace]
        )?.oriented(.downMirrored) else {
            throw AppError.encodeFailed("gain map: CIImage(mtlTexture:) failed for the HDR plane")
        }
        let headedHDR = hdrImage.settingContentHeadroom(hdrPlane.headroom)

        // ③ the CI context rides the CAPTURE's queue — same-queue FIFO
        //    orders the CI read after the blit (the GPU→GPU handoff; no CPU
        //    readback, hence no L014 fence).
        let context = CIContext(
            mtlCommandQueue: hdrPlane.commandQueue,
            options: [.cacheIntermediates: false])

        // ④ the CI write (D1): quality knob straight through (E3).
        var options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:
                quality ?? 0.9,
        ]
        options[.hdrImage] = headedHDR
        do {
            try context.writeJPEGRepresentation(
                of: baseImage, to: ciTmp, colorSpace: targetColorSpace,
                options: options)
        } catch {
            throw AppError.encodeFailed(
                "gain map: CI writeJPEGRepresentation failed: \(error)")
        }

        // ⑤ the primary XMP rewrap (F5 form: CopyImageSource — the probe
        //    batch proved AddImageFromSource re-encodes the primary image
        //    and DROPS the MPF subimage; CopyImageSource preserves the
        //    container verbatim and ImageIO rewrites the moved internal
        //    offsets). `.none` policy = NO metadata — the container stays
        //    UltraHDR (the negative test pins both).
        let finalTmp: URL
        if let metadata = Self.primaryXMP(
            policy: metadataPolicy, sourceURL: sourceURL, exifSoftware: exifSoftware)
        {
            guard let source = CGImageSourceCreateWithURL(ciTmp as CFURL, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary),
                let dest = CGImageDestinationCreateWithURL(
                    rewrapTmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else {
                throw AppError.encodeFailed("gain map: rewrap destination failed")
            }
            var rewrapError: Unmanaged<CFError>?
            let copied = CGImageDestinationCopyImageSource(
                dest, source, [kCGImageDestinationMetadata: metadata] as CFDictionary,
                &rewrapError)
            guard copied else {
                throw AppError.encodeFailed(
                    "gain map: rewrap copyImageSource failed: "
                        + (rewrapError?.takeRetainedValue().localizedDescription ?? "unknown"))
            }
            finalTmp = rewrapTmp
        } else {
            finalTmp = ciTmp
        }

        // ⑥ the atomic promotion (L009: same-volume rename; the destination
        //    name was resolved by the namer against the occupancy snapshot).
        do {
            try fileManager.moveItem(at: finalTmp, to: destination)
        } catch {
            throw AppError.encodeFailed(
                "gain map: promotion failed for "
                    + "\(destination.lastPathComponent): \(error)")
        }
        return destination
    }

    // MARK: The primary XMP assembly (KD-4)

    /// The hdrgm namespace (OQ-3): primary XMP carries `hdrgm:Version` so
    /// modern readers see the gain map tier's version face.
    private static let hdrgmNamespace = "http://www.adobe.com/ns/hdrgm/1.0/"
    private static let hdrgmPrefix = "hdrgm"
    private static let hdrgmVersion = "1.0"

    /// Build the rewrap metadata: `hdrgm:Version` + the Software signature
    /// (`xmp:CreatorTool` — the seat the F5 spike proved serializes through
    /// the metadata path) + the policy-gated sidecar five fields through the
    /// `XMPWriter` projection. `.none` policy (or nothing to write) → nil —
    /// NO rewrap, the container stays UltraHDR with CI's own faces only.
    ///
    /// EXIF probe verdict (OQ-2, probed 2026-10-13 — the T2 execution-time
    /// probe, verdict recorded in M6-3-01-DECISIONS): the metadata-namespace
    /// EXIF/TIFF seat is NOT settable — `CGImageMetadataSetValueWithPath`
    /// REJECTS the `{TIFF}/Software` path (returns false), so the gain map
    /// tier ships v1 WITHOUT EXIF (the sanctioned OQ-2 ② degrade; the XMP
    /// CreatorTool above is the Software signature's surviving seat).
    ///
    /// NOTE (single-truth discipline): the sidecar stays the ONLY truth
    /// source — the five fields flow through `XMPWriter.project` (the same
    /// projection `ExportChainBuilder.mountXMP` consumes); the serialization
    /// face lives here because `kCGImageDestinationMetadata` demands a
    /// `CGImageMetadata` and `XMPWriter.write` produces packet bytes (the
    /// zero-diff red line on XMPWriter bars a shared serializer).
    static func primaryXMP(
        policy: ExportMetadataPolicy, sourceURL: URL?, exifSoftware: String?
    ) -> CGMutableImageMetadata? {
        guard policy.mode == .standard else { return nil }
        let metadata = CGImageMetadataCreateMutable()
        // ① hdrgm:Version (always — the tier's version face).
        var registrationError: Unmanaged<CFError>?
        guard CGImageMetadataRegisterNamespaceForPrefix(
            metadata, hdrgmNamespace as CFString, hdrgmPrefix as CFString,
            &registrationError)
        else { return nil }
        guard CGImageMetadataSetValueWithPath(
            metadata, nil, "\(hdrgmPrefix):Version" as CFString,
            hdrgmVersion as CFString)
        else { return nil }
        // ② the Software signature (xmp:CreatorTool — the F5-proven seat).
        if let exifSoftware, !exifSoftware.isEmpty {
            CGImageMetadataSetValueWithPath(
                metadata, nil, "xmp:CreatorTool" as CFString,
                exifSoftware as CFString)
        }
        // ④ the policy-gated sidecar five fields (the projection carrier).
        if policy.includeXMP, policy.includeEditingHistory,
            let sourceURL, let document = ExportRenderer.readDocument(imageURL: sourceURL)
        {
            let fields = XMPWriter.project(
                rating: document.rating, flag: document.flag,
                colorLabel: document.colorLabel, keywords: document.keywords)
            if let rating = fields.rating {
                CGImageMetadataSetValueWithPath(
                    metadata, nil, "xmp:Rating" as CFString, rating as CFNumber)
            }
            if let label = fields.label {
                CGImageMetadataSetValueWithPath(
                    metadata, nil, "xmp:Label" as CFString, label as CFString)
            }
            if !fields.hierarchicalSubject.isEmpty {
                if CGImageMetadataRegisterNamespaceForPrefix(
                    metadata, XMPWriter.Namespaces.lightroom as CFString,
                    XMPWriter.Namespaces.lightroomPrefix as CFString,
                    &registrationError)
                {
                    setBag(
                        metadata, path: "lr:hierarchicalSubject",
                        xmlns: XMPWriter.Namespaces.lightroom,
                        prefix: XMPWriter.Namespaces.lightroomPrefix,
                        name: "hierarchicalSubject", values: fields.hierarchicalSubject)
                }
            }
            if !fields.subject.isEmpty {
                setBag(
                    metadata, path: "dc:subject",
                    xmlns: kCGImageMetadataNamespaceDublinCore as String,
                    prefix: nil, name: "subject", values: fields.subject)
            }
        }
        return metadata
    }

    /// The Bag construction discipline (the XMPWriter.setBag shape —
    /// `.arrayUnordered` lands rdf:Bag; a raw CFArray would land rdf:Seq).
    private static func setBag(
        _ metadata: CGMutableImageMetadata, path: String, xmlns: String,
        prefix: String?, name: String, values: [String]
    ) -> Bool {
        guard let tag = CGImageMetadataTagCreate(
            xmlns as CFString, prefix as CFString?, name as CFString,
            .arrayUnordered, values as CFArray)
        else { return false }
        return CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
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
