import CoreML
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// SemanticEngine (Plan M2-10-02 KD-5) — the semantic query orchestration:
// tokenize (52 static shape) → text-tower embed → the D-1 vDSP full sweep →
// ordered hits, plus the image-embedding chain the M2-10-03 import pipeline
// consumes (manifest.inputSize pre-scale → image tower → upsert).
//
// THE PROTOCOL SEAM (KD-5 / M2AI-10): `AIInferencing` is the inference
// capability缝. This plan ships `InProcessMLModelRunner` (CoreML in-process,
// the M2-10-02..03 transition face); M2-10-05 adds the worker-process
// conformer and the App assembly point switches conformers in ONE place —
// the engine/store/scan faces stay untouched.
//
// E4 (checker): the ONLY image-size constant source is
// `ModelAssetManifest.inputSize` (224 for the bundled Chinese-CLIP) — the
// pre-scale leg reads it from the catalog, never a literal.
//
// NORMALIZATION (D-8 / M2-10-01 DECISIONS §8): both towers L2-normalize
// INSIDE the exported graphs — this file contains zero normalization code;
// cosine == dot product all the way to the scanner.
// ─────────────────────────────────────────────────────────────────────────────

/// The inference capability seam (KD-5): one conformer per execution world
/// (in-process now, worker process in M2-10-05).
public protocol AIInferencing: Sendable {
    /// Text-tower forward. `tokens`/`mask` are the tokenizer's static-shape
    /// rows (52); the mask is the 1-D padding mask (the conformer expands
    /// per the model contract).
    func embedText(_ profileID: String, tokens: [Int64], mask: [Int64]) async throws -> [Float]
    /// Image-tower forward over the PRE-SCALED JPEG bytes (edge =
    /// manifest.inputSize; E4 — the caller owns the resize/crop).
    func embedImage(_ profileID: String, jpeg: Data) async throws -> [Float]
}

/// The typed engine failure face (the dialog maps these to honest states —
/// never a silent empty result).
public enum SemanticSearchError: Error, Equatable, Sendable {
    /// No active semantic model in the package (never converted / assets
    /// absent) — the「语义模型未就绪」face.
    case modelUnavailable
    /// The runner's vector width disagrees with the active model row.
    case dimensionMismatch(expected: Int, actual: Int)
}

/// One ordered search hit (score = cosine, both sides pre-normalized).
public struct SemanticSearchHit: Sendable, Equatable {
    public let imageID: Int64
    public let score: Float

    public init(imageID: Int64, score: Float) {
        self.imageID = imageID
        self.score = score
    }
}

/// The search face the search model consumes (the mock seam for the CI
/// tests — no model assets needed).
public protocol SemanticSearching: Sendable {
    func search(
        _ queryText: String, limit: Int, in store: SemanticStore
    ) async throws -> [SemanticSearchHit]
}

public actor SemanticEngine: SemanticSearching {

    /// The static export shape (M2-10-01 contract).
    public static let maxTokens = 52

    private let runner: any AIInferencing
    private let tokenizer: WordPieceTokenizer

    public init(runner: any AIInferencing, tokenizer: WordPieceTokenizer) {
        self.runner = runner
        self.tokenizer = tokenizer
    }

    // MARK: - The query chain (KD-5)

    public func search(
        _ queryText: String, limit: Int, in store: SemanticStore
    ) async throws -> [SemanticSearchHit] {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let model = try await store.activeModel() else {
            throw SemanticSearchError.modelUnavailable
        }
        let encoded = tokenizer.encode(trimmed, maxTokens: Self.maxTokens)
        let query = try await runner.embedText(
            model.modelKey, tokens: encoded.tokenIDs, mask: encoded.attentionMask)
        guard query.count == model.embeddingDim else {
            throw SemanticSearchError.dimensionMismatch(
                expected: model.embeddingDim, actual: query.count)
        }
        // The D-1 sweep over the flat table payload (OQ-9-A: the ACTIVE
        // model's rows only; a换档 recompute rides its own model_key).
        let table = try await store.loadScanTable(modelKey: model.modelKey)
        return try EmbeddingScanner.topK(
            rowIDs: table.rowIDs, contiguousFP16: table.fp16,
            dim: model.embeddingDim, query: query, k: limit
        ).map { SemanticSearchHit(imageID: $0.id, score: $0.score) }
    }

    // MARK: - The image-embedding chain (M2-10-03 consumes)

    /// One image → pre-scale (manifest.inputSize resize + center crop, the
    /// CLIP preprocessing; a DEDICATED resample — never the thumbnail
    /// cache) → image tower → upsert. `imageData` is any ImageIO-decodable
    /// source (RAW via the caller's decode face or a raster file).
    public func embedAndStore(
        imageData: Data, imageID: Int64, in store: SemanticStore,
        computedTime: Int64
    ) async throws {
        guard let model = try await store.activeModel() else {
            throw SemanticSearchError.modelUnavailable
        }
        guard let manifest = ModelAssetCatalog.manifest(for: model.modelKey) else {
            throw SemanticSearchError.modelUnavailable
        }
        let jpeg = try Self.preScaledJPEG(from: imageData, edge: manifest.inputSize)
        let vector = try await runner.embedImage(model.modelKey, jpeg: jpeg)
        guard vector.count == model.embeddingDim else {
            throw SemanticSearchError.dimensionMismatch(
                expected: model.embeddingDim, actual: vector.count)
        }
        try await store.upsertEmbedding(
            imageID: imageID, modelKey: model.modelKey, vector: vector,
            computedTime: computedTime)
    }

    /// The KD-5 pre-scale: decode → resize the SHORTER edge to `edge`
    /// (high interpolation) → center-crop `edge`² → JPEG bytes (quality
    /// 0.9 — the embedding-dedicated resample, RESEARCH 锚点表 semantics).
    /// Pure ImageIO/CG — directly testable without any model.
    public static func preScaledJPEG(from data: Data, edge: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw SemanticSearchError.modelUnavailable
        }
        guard let image = CGImageSourceCreateImageAtIndex(
            source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw SemanticSearchError.modelUnavailable }
        return try preScaledJPEG(from: image, edge: edge)
    }

    public static func preScaledJPEG(from image: CGImage, edge: Int) throws -> Data {
        let scale = Double(edge) / Double(min(image.width, image.height))
        let scaledWidth = max(edge, Int((Double(image.width) * scale).rounded()))
        let scaledHeight = max(edge, Int((Double(image.height) * scale).rounded()))
        let cropX = (scaledWidth - edge) / 2
        let cropY = (scaledHeight - edge) / 2
        // Resize + center crop in ONE bitmap draw — `CGImage.cropping(to:)`
        // returns nil for context-backed images (probed 2026-10-03); the
        // draw path is universally reliable (RAW-decoded frames included).
        guard let bitmap = CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8,
            bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw SemanticSearchError.modelUnavailable }
        bitmap.interpolationQuality = .high
        bitmap.draw(
            image, in: CGRect(
                x: -CGFloat(cropX), y: -CGFloat(cropY),
                width: CGFloat(scaledWidth), height: CGFloat(scaledHeight)))
        guard let cropped = bitmap.makeImage()
        else { throw SemanticSearchError.modelUnavailable }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, "public.jpeg" as CFString, 1, nil)
        else { throw SemanticSearchError.modelUnavailable }
        CGImageDestinationAddImage(
            destination, cropped,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw SemanticSearchError.modelUnavailable
        }
        return mutable as Data
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// InProcessMLModelRunner — the M2-10-02..03 transition conformer (KD-5):
// the two bundled Chinese-CLIP towers. The bundle ships UNCOMPILED
// .mlpackage trees — `MLModel(contentsOf:)` refuses them (probed 2026-10-03:
// "Compile the model with Xcode or MLModel.compileModel(at:)"), so the
// runner compiles ONCE and caches the .mlmodelc under the injected cache
// directory (a rebuildable Caches-class derivative, keyed by cache name —
// subsequent launches load the compiled form directly).
//
// The model IO contract is the M2-10-01 conversion's: text = input_ids
// int32 [1,52] + attention_mask float32 [1,1,52,52] (the 1-D padding mask
// tiled on the kv axis, `> 0.5` in-graph); image = pixel_values float32
// [1,3,S,S] with the CLIP mean/std normalization applied by the caller side
// (folded out of the graph); both outputs = one L2-normalized vector.
// ─────────────────────────────────────────────────────────────────────────────

public final class InProcessMLModelRunner: AIInferencing, @unchecked Sendable {

    /// CLIP preprocessing constants (M2-10-01 DECISIONS §8; RGB, [0,1] domain).
    private static let mean: [Float] = [0.481_454_66, 0.457_827_5, 0.408_210_73]
    private static let std: [Float] = [0.268_629_54, 0.261_302_58, 0.275_777_11]

    private let imageModel: MLModel
    private let textModel: MLModel

    /// - Parameters:
    ///   - compileCacheDirectory: when given, compiled `.mlmodelc` trees are
    ///     cached there (`<name>.mlmodelc`) and reused across launches; nil
    ///     compiles into a fresh temp directory each construction (tests).
    public init(
        imageModelURL: URL, textModelURL: URL,
        computeUnits: MLComputeUnits = .all,
        compileCacheDirectory: URL? = nil
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.imageModel = try Self.loadCompiled(
            from: imageModelURL, cacheName: "img.mlmodelc",
            cacheDirectory: compileCacheDirectory, configuration: configuration)
        self.textModel = try Self.loadCompiled(
            from: textModelURL, cacheName: "txt.mlmodelc",
            cacheDirectory: compileCacheDirectory, configuration: configuration)
    }

    /// Cache-hit → load; else `MLModel.compileModel` → move into the cache
    /// (best-effort; a cache write failure still returns a working model).
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

    // MARK: AIInferencing

    public func embedText(
        _ profileID: String, tokens: [Int64], mask: [Int64]
    ) async throws -> [Float] {
        let sequence = tokens.count
        let ids = try MLMultiArray(
            shape: [1, NSNumber(value: sequence)], dataType: .int32)
        let expandedMask = try MLMultiArray(
            shape: [1, 1, NSNumber(value: sequence), NSNumber(value: sequence)],
            dataType: .float32)
        ids.withUnsafeMutableBytes {
            (pointer: UnsafeMutableRawBufferPointer, _: [Int]) in
            let int32 = pointer.bindMemory(to: Int32.self)
            for (index, token) in tokens.enumerated() {
                int32[index] = Int32(token)
            }
        }
        // The kv-axis broadcast (the conversion contract: the graph applies
        // `> 0.5`; row i of the 2-D mask == the 1-D padding mask).
        expandedMask.withUnsafeMutableBytes {
            (pointer: UnsafeMutableRawBufferPointer, _: [Int]) in
            let floats = pointer.bindMemory(to: Float.self)
            for row in 0..<sequence {
                for column in 0..<sequence {
                    floats[row * sequence + column] = Float(mask[column])
                }
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: expandedMask),
        ])
        // Synchronous prediction on this actor (the engine serializes
        // searches anyway; single-digit-ms ANE forwards per M2-10-01 spike;
        // M2-10-05 moves inference off-thread with the worker conformer).
        let output = try await textModel.prediction(
            from: provider, options: MLPredictionOptions())
        return try Self.firstVector(of: output)
    }

    public func embedImage(_ profileID: String, jpeg: Data) async throws -> [Float] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else {
            throw SemanticSearchError.modelUnavailable
        }
        guard let image = CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw SemanticSearchError.modelUnavailable }
        let edge = image.width
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, edge, edge, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let buffer = pixelBuffer else {
            throw SemanticSearchError.modelUnavailable
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: edge, height: edge,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw SemanticSearchError.modelUnavailable }
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))

        let channels = 3
        let pixels = edge * edge
        let array = try MLMultiArray(
            shape: [1, NSNumber(value: channels), NSNumber(value: edge),
                    NSNumber(value: edge)],
            dataType: .float32)
        array.withUnsafeMutableBytes {
            (pointer: UnsafeMutableRawBufferPointer, _: [Int]) in
            let floats = pointer.bindMemory(to: Float.self)
            let base = CVPixelBufferGetBaseAddress(buffer)!
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<edge {
                let row = base.advanced(by: y * bytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)
                for x in 0..<edge {
                    // BGRA little-endian layout: B,G,R,A.
                    let pixel = row + x * 4
                    let rgb = [Float(pixel[2]), Float(pixel[1]), Float(pixel[0])]
                    for channel in 0..<channels {
                        floats[
                            channel * pixels + y * edge + x
                        ] = (rgb[channel] / 255.0 - Self.mean[channel])
                            / Self.std[channel]
                    }
                }
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(multiArray: array),
        ])
        let output = try await imageModel.prediction(
            from: provider, options: MLPredictionOptions())
        return try Self.firstVector(of: output)
    }

    /// The single-output contract: the first multiArray feature, flattened.
    /// Element-wise `float32Value` reads — the int8-quantized towers keep
    /// FP16 ACTIVATIONS, so the output multiArray is a half-precision
    /// buffer (the scoped-byte Float binding traps on it — probed in the
    /// M5 sanity run 2026-10-03).
    private static func firstVector(of output: MLFeatureProvider) throws -> [Float] {
        for name in output.featureNames {
            if let array = output.featureValue(for: name)?.multiArrayValue {
                var vector = [Float](repeating: 0, count: array.count)
                for index in 0..<array.count {
                    vector[index] = Float(array[index].doubleValue)
                }
                return vector
            }
        }
        throw SemanticSearchError.modelUnavailable
    }
}
