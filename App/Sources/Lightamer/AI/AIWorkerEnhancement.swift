import CoreML
import Foundation
import ImageIO
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EnhancementSession (Plan M2-10-06 T3a, KD-1/KD-2) — the worker-side
// enhancement model session: ONE compiled package per (profile, units),
// the static-shape facts read from the model description (the
// ShapedSessions discipline — Lumen MODEL.md:8: dynamic-shape CoreML
// cannot build plans, so the FEED shape is fixed per run and its key
// rides the (profile, units, shape) session dimension), and the tile
// run leg over the PATH channel (16-bit RGB TIFF in/out).
//
// HEADLESS DISCIPLINE: Foundation/CoreML/ImageIO only — no SwiftUI, no
// AppKit (the M2-10-05 worker-body rule).
//
// FEED VALIDATION: a run whose feed (h, w) is not among the model's
// supported edges is a typed run failure — the ENGINE maps spans to
// supported edges (TilePlanner.feedEdge; sub-tile spans pad-to-fit, the
// DRUNet pad-and-crop precedent and the ONLY padding in the system).
//
// DENOISE STRENGTH: the converted models carry no strength input — the
// worker blends output with input by amount/100 (strength 0 = identity,
// 100 = full model output; the industry-standard linear interpolation,
// DECISIONS 签注). Upscale runs carry no amount and skip the blend.
// ─────────────────────────────────────────────────────────────────────────────

final class EnhancementSession: @unchecked Sendable {

    /// The model's supported input edges (ascending; a static-converted
    /// asset reports exactly its baked edge — manifest.inputSize).
    let supportedEdges: [Int]
    /// The super-resolution factor (output edge / input edge; 1 = denoise).
    let scale: Int

    private let model: MLModel
    /// The model's IO names (the conversion names the input `input_tile`;
    /// the output name comes from the traced graph — discovered, never
    /// assumed).
    let inputName: String
    let outputName: String

    // MARK: - Package resolution

    /// Bundled folder reference first (KD-3), then the installed
    /// Application Support root (the M2-10-01 store's layout: a release
    /// artifact downloads as `<profile>/<assetFileName>`; the unzipped
    /// `.mlpackage` directory is the usable form — the artifact's `.zip`
    /// suffix is stripped for the lookup). nil = assets absent (the
    /// profile-level typed face).
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
                atPath: candidate.path, isDirectory: &isDirectory) {
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
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try Self.loadCompiled(
            from: packageURL, cacheName: "tile.mlmodelc",
            cacheDirectory: compileCacheDirectory, configuration: configuration)
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName
        self.inputName = inputs["input_tile"] != nil
            ? "input_tile" : (inputs.first?.key ?? "input_tile")
        self.outputName = outputs.first?.key ?? "output_tile"
        let inputEdge = Self.readEdge(
            of: inputs[self.inputName], fallback: manifest.inputSize)
        self.supportedEdges = [inputEdge]
        let outputEdge = Self.readEdge(
            of: outputs[self.outputName], fallback: manifest.inputSize)
        self.scale = max(1, outputEdge / max(1, inputEdge))
    }

    /// The InProcessMLModelRunner's compile-once/cache-forever pattern,
    /// single-model form (the enhancement family has one package, not two
    /// towers).
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

    /// The supported edge from a feature description's shape constraint:
    /// enumerated square shapes, else a static size range (min == max —
    /// the coremltools static conversion), else the manifest fallback.
    static func readEdge(
        of description: MLFeatureDescription?, fallback: Int
    ) -> Int {
        guard let shapeConstraint = description?.multiArrayConstraint?.shapeConstraint else {
            return fallback
        }
        if shapeConstraint.type == .enumerated,
           !shapeConstraint.enumeratedShapes.isEmpty {
            let edges = Set(shapeConstraint.enumeratedShapes.compactMap { shape -> Int? in
                guard shape.count == 4 else { return nil }
                let height = shape[2].intValue, width = shape[3].intValue
                return height == width ? height : nil
            })
            if let edge = edges.sorted().first { return edge }
        }
        let ranges = shapeConstraint.sizeRangeForDimension
        if ranges.count == 4 {
            let height = ranges[2].rangeValue
            let width = ranges[3].rangeValue
            if height.location == width.location, height.location > 0 {
                return height.location
            }
        }
        return fallback
    }

    // MARK: - The tile run

    enum TileRunError: Error, CustomStringConvertible {
        case unsupportedFeed(height: Int, width: Int, supported: [Int])
        case unreadableInput(String)
        case shapeMismatch(String)
        case predictionFailed(String)
        case outputWriteFailed(String)

        var description: String {
            switch self {
            case .unsupportedFeed(let height, let width, let supported):
                return "feed shape \(height)×\(width) not supported "
                    + "(supported: \(supported))"
            case .unreadableInput(let detail): return "input tile unreadable: \(detail)"
            case .shapeMismatch(let detail): return "shape mismatch: \(detail)"
            case .predictionFailed(let detail): return "prediction failed: \(detail)"
            case .outputWriteFailed(let detail): return "output tile unwritable: \(detail)"
            }
        }
    }

    /// One tile: decode → (pad-to-fit) → CHW float32 → prediction →
    /// interleave → (denoise blend) → encode. The output is the FULL
    /// feed×scale frame; the engine owns the valid-span crop and the
    /// blend weights.
    func runTile(
        inPath: URL, outPath: URL, feedHeight: Int, feedWidth: Int,
        amount: Double?
    ) async throws {
        guard supportedEdges.contains(feedHeight),
              supportedEdges.contains(feedWidth) else {
            throw TileRunError.unsupportedFeed(
                height: feedHeight, width: feedWidth, supported: supportedEdges)
        }
        // Decode the 16-bit RGB tile.
        guard let source = CGImageSourceCreateWithURL(
            inPath as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else {
            throw TileRunError.unreadableInput(inPath.path)
        }
        let (rgba, width, height) = try Self.rasterize16(image)
        guard width <= feedWidth, height <= feedHeight else {
            throw TileRunError.shapeMismatch(
                "input \(width)×\(height) exceeds the feed "
                    + "\(feedWidth)×\(feedHeight)")
        }
        // CHW float32 [1,3,H,W], edge-replicate padded to the feed shape.
        var input = try MLMultiArray(
            shape: [1, 3, NSNumber(value: feedHeight), NSNumber(value: feedWidth)],
            dataType: .float32)
        input.withUnsafeMutableBytes {
            (pointer: UnsafeMutableRawBufferPointer, _: [Int]) in
            let floats = pointer.bindMemory(to: Float.self)
            for channel in 0..<3 {
                for y in 0..<feedHeight {
                    let sourceY = min(y, height - 1)
                    for x in 0..<feedWidth {
                        let sourceX = min(x, width - 1)
                        floats[channel * feedHeight * feedWidth
                            + y * feedWidth + x] =
                            rgba[(sourceY * width + sourceX) * 4 + channel]
                    }
                }
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: input),
        ])
        let output = try await model.prediction(
            from: provider, options: MLPredictionOptions())
        guard let outputArray = output.featureValue(
            for: outputName)?.multiArrayValue
        else {
            throw TileRunError.predictionFailed(
                "no \(outputName) feature (available: \(output.featureNames))")
        }
        let outputHeight = feedHeight * scale
        let outputWidth = feedWidth * scale
        guard outputArray.count == 3 * outputHeight * outputWidth else {
            throw TileRunError.shapeMismatch(
                "output count \(outputArray.count) != "
                    + "3×\(outputHeight)×\(outputWidth)")
        }
        // CHW → interleaved RGB16, with the denoise amount blended against
        // the (padded) input (strength 0 = identity).
        var pixels = [UInt16](
            repeating: 0, count: outputHeight * outputWidth * 4)
        let blend = amount.map { Float(max(0, min(100, $0)) / 100.0) }
        let rawOutput = Self.floatValues(of: outputArray)
        for y in 0..<outputHeight {
            let inputY = min(y / scale, height - 1)
            for x in 0..<outputWidth {
                let inputX = min(x / scale, width - 1)
                let inputIndex = (inputY * width + inputX) * 4
                let target = (y * outputWidth + x) * 4
                for channel in 0..<3 {
                    var value = rawOutput[
                        channel * outputHeight * outputWidth
                            + y * outputWidth + x]
                    if let blend {
                        value = rgba[inputIndex + channel] * (1 - blend)
                            + value * blend
                    }
                    let clamped = min(max(value, 0), 1)
                    pixels[target + channel] = UInt16(
                        Int((clamped * 65535.0).rounded()))
                }
                pixels[target + 3] = UInt16.max
            }
        }
        // Encode 16-bit RGBA16 TIFF (the engine crops the valid span).
        let pixelData = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: pixelData as CFData) else {
            throw TileRunError.outputWriteFailed("provider create failed")
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder16Little.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cgImage = CGImage(
            width: outputWidth, height: outputHeight,
            bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: outputWidth * 8,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent),
            let destination = CGImageDestinationCreateWithURL(
                outPath as CFURL, "public.tiff" as CFString, 1, nil)
        else {
            throw TileRunError.outputWriteFailed(outPath.path)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TileRunError.outputWriteFailed(outPath.path)
        }
    }

    // MARK: - Raster plumbing

    /// Draw any source image into a 16-bit RGBA context (the L060
    /// single-draw discipline — no cropping-through-makeImage) and return
    /// the interleaved [0,1] float buffer.
    static func rasterize16(_ image: CGImage) throws -> (
        rgba: [Float], width: Int, height: Int
    ) {
        let width = image.width, height = image.height
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes {
            (raw: UnsafeMutableRawBufferPointer) -> CGContext? in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 16, bytesPerRow: width * 8,
                space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder16Little.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context = drawn else {
            throw TileRunError.unreadableInput("context create failed")
        }
        context.draw(
            image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (
            pixels.map { Float($0) / 65535.0 }, width, height)
    }

    /// The output-array read with the L060 dataType dispatch (a fp16
    /// buffer must not be pointer-rebound as Float).
    static func floatValues(of array: MLMultiArray) -> [Float] {
        switch array.dataType {
        case .float32:
            return array.withUnsafeMutableBytes {
                (pointer: UnsafeMutableRawBufferPointer, _: [Int]) in
                Array(pointer.bindMemory(to: Float.self))
            }
        case .float16:
            let count = array.count
            var values = [Float](repeating: 0, count: count)
            return array.withUnsafeMutableBytes {
                (pointer: UnsafeMutableRawBufferPointer, _: [Int]) in
                let halves = pointer.bindMemory(to: UInt16.self)
                for index in 0..<count {
                    values[index] = Float(Float16(bitPattern: halves[index]))
                }
                return values
            }
        default:
            return (0..<array.count).map { array[$0].floatValue }
        }
    }
}
