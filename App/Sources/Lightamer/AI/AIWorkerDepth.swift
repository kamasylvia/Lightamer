import CoreML
import Foundation
import ImageIO
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DepthSession (M4-3-01 KD-3/T3) — the worker-side depth model session: ONE
// compiled package per (profile, units), the STATIC shape (518×392) read from
// the manifest (the D-4 spike's single source — never re-typed), and the
// depth run leg over the PATH channel (sRGB JPEG in → F32 plane out).
//
// PREPROCESSING (D-4 SPIKE, DECISIONS §1 — KD-3 arm a): the Apple F16
// package takes an IMAGE input (518 wide × 392 high, BGRA) with the
// normalization BAKED into the graph — no CPU-side ImageNet statistics at
// this layer (arm b's code intentionally does not exist). The input is
// scale-STRETCHED to the static shape (aspect-ratio distortion for one ANE
// specialization — the Lumen 256² stretch paradigm; a mask needs no
// visible-fidelity guarantee) with `.medium` interpolation determinism.
//
// OUTPUT (spike): a one-component 32-bit-HALF image, larger = nearer
// (relative inverse depth, roughly [0,1]). The worker converts to F32 and
// gates non-finite values at the source (m3: NaN/Inf → typed failure HERE,
// keeping `noDepthStructure` reserved for genuinely flat depth — the two
// faces are orthogonal). outPath = 8-byte header (UInt32 LE width, UInt32
// LE height) + row-major F32 LE bytes — explicit and unambiguous, zero
// ImageIO 32F grayscale-TIFF variables.
//
// HEADLESS DISCIPLINE: Foundation/CoreML/ImageIO/LightamerCore only — no
// SwiftUI, no AppKit (the M2-10-05 worker-body rule; checker m7's whitelist
// includes LightamerCore for ModelAssetManifest/ModelLocator).
// ─────────────────────────────────────────────────────────────────────────────

final class DepthSession: @unchecked Sendable {

    enum DepthRunError: Error, CustomStringConvertible {
        case unreadableInput(String)
        case contextFailed(String)
        case predictionFailed(String)
        case nonFiniteOutput(Int)
        case outputWriteFailed(String)

        var description: String {
            switch self {
            case .unreadableInput(let detail): return "depth input unreadable: \(detail)"
            case .contextFailed(let detail): return "depth input context failed: \(detail)"
            case .predictionFailed(let detail): return "depth prediction failed: \(detail)"
            case .nonFiniteOutput(let count):
                return "depth output carries \(count) non-finite values"
            case .outputWriteFailed(let detail): return "depth output unwritable: \(detail)"
            }
        }
    }

    /// The static model shape from the manifest — (H, W) single source
    /// (checker m2): `inputSize` = long edge, `inputShortEdge` = short.
    let inputWidth: Int
    let inputHeight: Int

    private let model: MLModel
    private let inputName: String
    private let outputName: String

    // MARK: - Package resolution

    /// Bundled folder reference first (parity with the enhancement leg),
    /// then the installed Application Support root. The RELEASE artifact is
    /// a zip; the usable form is the EXTRACTED `.mlpackage` directory (the
    /// assetFileName minus its `.zip` suffix — the build script renames the
    /// package to match). The extraction face lives App-side
    /// (DepthMaskService.ensurePackage); this only RESOLVES what is on disk.
    static func resolvePackage(
        profile: String, manifest: ModelAssetManifest, locator: ModelLocator
    ) -> URL? {
        if let bundled = locator.bundledProfileURL(profile) {
            let candidate = bundled.appendingPathComponent(manifest.assetFileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let installed = try? locator.installedProfileURL(profile) {
            var name = manifest.assetFileName
            if name.hasSuffix(".zip") { name = String(name.dropLast(4)) }
            let candidate = installed.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Construction

    init(
        packageURL: URL, manifest: ModelAssetManifest,
        computeUnits: MLComputeUnits,
        compileCacheDirectory: URL?
    ) throws {
        self.inputWidth = manifest.inputSize
        self.inputHeight = manifest.inputShortEdge ?? manifest.inputSize
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try Self.loadCompiled(
            from: packageURL, cacheName: "depth.mlmodelc",
            cacheDirectory: compileCacheDirectory, configuration: configuration)
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName
        self.inputName = inputs["image"] != nil
            ? "image" : (inputs.first?.key ?? "image")
        self.outputName = outputs["depth"] != nil
            ? "depth" : (outputs.first?.key ?? "depth")
    }

    /// The compile-once/cache-forever pattern (the EnhancementSession
    /// worker-side form, single package; duplicated here because that one
    /// is private to its file — the compiled cache stays in the worker's
    /// own `compiled-models-worker/<profile>` tree).
    private static func loadCompiled(
        from modelURL: URL, cacheName: String, cacheDirectory: URL?,
        configuration: MLModelConfiguration
    ) throws -> MLModel {
        var cacheFile: URL?
        if let cacheDirectory {
            cacheFile = cacheDirectory.appendingPathComponent(cacheName)
        }
        if let cacheFile,
           FileManager.default.fileExists(
               atPath: cacheFile.appendingPathComponent("coremldata.bin").path),
           let model = try? MLModel(
               contentsOf: cacheFile, configuration: configuration) {
            return model
        }
        let compiled = try MLModel.compileModel(at: modelURL)
        if let cacheFile {
            let parent = cacheFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                try? FileManager.default.removeItem(at: cacheFile)
            }
            try? FileManager.default.moveItem(at: compiled, to: cacheFile)
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                return try MLModel(
                    contentsOf: cacheFile, configuration: configuration)
            }
        }
        return try MLModel(contentsOf: compiled, configuration: configuration)
    }

    // MARK: - The depth run

    /// Decode `inPath` (the editor's sRGB preview JPEG) → scale-stretch to
    /// the static shape → forward → F32 plane (isfinite-gated, m3) →
    /// `outPath` (8-byte header + row-major F32 LE).
    func run(inPath: URL, outPath: URL) async throws {
        let pixelBuffer = try Self.stretchedPixelBuffer(
            from: inPath, width: inputWidth, height: inputHeight)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: pixelBuffer),
        ])
        let output = try await model.prediction(
            from: provider, options: MLPredictionOptions())
        guard let buffer = output.featureValue(for: outputName)?.imageBufferValue else {
            throw DepthRunError.predictionFailed(
                "no \(outputName) image (available: \(output.featureNames))")
        }
        let floats = try Self.floatPlane(from: buffer)
        try Self.writePlane(
            floats, width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer), to: outPath)
    }

    /// Decode + scale-stretch into a BGRA CVPixelBuffer of exactly
    /// `width × height` (`.medium` interpolation determinism; row 0 = top
    /// — the buffer convention the output plane keeps).
    static func stretchedPixelBuffer(
        from inputURL: URL, width: Int, height: Int
    ) throws -> CVPixelBuffer {
        guard let source = CGImageSourceCreateWithURL(
            inputURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else {
            throw DepthRunError.unreadableInput(inputURL.path)
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw DepthRunError.contextFailed("CVPixelBufferCreate \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw DepthRunError.contextFailed("no base address")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // BGRA memory = little-endian ARGB context (the kCVPixelFormatType_
        // 32BGRA layout).
        guard let context = CGContext(
            data: base, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else {
            throw DepthRunError.contextFailed("CGContext create failed")
        }
        context.interpolationQuality = .medium
        context.draw(
            image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// The output image buffer → row-major F32 plane, gated non-finite at
    /// the source (m3). Both one-component numeric formats are handled
    /// (the spike pinned Half; the Float32 reader costs nothing and keeps
    /// an F32 re-conversion of the package usable).
    static func floatPlane(from buffer: CVPixelBuffer) throws -> [Float] {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw DepthRunError.predictionFailed("output buffer unreadable")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var floats = [Float](repeating: 0, count: width * height)
        var nonFinite = 0
        // CoreVideo ships no constant for the one-component Half form the
        // spike found ('L00h' = 1278226536; OneComponent32Float is 1278226534).
        let oneComponent32Half: OSType = 0x4C3030_68
        switch format {
        case oneComponent32Half:
            let halves = base.assumingMemoryBound(to: UInt16.self)
            let stride = bytesPerRow / 2
            for y in 0..<height {
                for x in 0..<width {
                    let value = Float(Float16(bitPattern: halves[y * stride + x]))
                    if value.isFinite { floats[y * width + x] = value }
                    else { nonFinite += 1 }
                }
            }
        case kCVPixelFormatType_OneComponent32Float:
            let raw = base.assumingMemoryBound(to: Float.self)
            let stride = bytesPerRow / 4
            for y in 0..<height {
                for x in 0..<width {
                    let value = raw[y * stride + x]
                    if value.isFinite { floats[y * width + x] = value }
                    else { nonFinite += 1 }
                }
            }
        default:
            throw DepthRunError.predictionFailed(
                "unexpected depth output pixel format \(format)")
        }
        guard nonFinite == 0 else {
            throw DepthRunError.nonFiniteOutput(nonFinite)
        }
        return floats
    }

    /// 8-byte header (UInt32 LE width, UInt32 LE height) + row-major F32
    /// LE bytes — the explicit float-plane file form.
    static func writePlane(
        _ floats: [Float], width: Int, height: Int, to outPath: URL
    ) throws {
        precondition(floats.count == width * height, "plane count mismatch")
        var data = Data(count: 8 + floats.count * 4)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            raw.storeBytes(of: UInt32(width).littleEndian, toByteOffset: 0, as: UInt32.self)
            raw.storeBytes(of: UInt32(height).littleEndian, toByteOffset: 4, as: UInt32.self)
            floats.withUnsafeBytes { source in
                raw.baseAddress!.advanced(by: 8)
                    .copyMemory(from: source.baseAddress!, byteCount: floats.count * 4)
            }
        }
        do {
            try data.write(to: outPath, options: .atomic)
        } catch {
            throw DepthRunError.outputWriteFailed("\(outPath.path): \(error)")
        }
    }
}
