import CoreGraphics
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// EnhanceEngine (Plan M2-10-06 T3b, KD-2) — the enhancement ORCHESTRATION
// pure face (Core-level, model-free, worker-free): tile planning, per-tile
// path-channel frames, blend assembly, cancel checkpoints, and progress.
// The App-side dialog wires the tile-executor seam to the worker client;
// tests wire a stub inferencer (the resource-gate discipline).
//
// EXECUTION ORDER (the KD-2 memory pin, Lumen ai_dialog.py:103-104
// semantics): the fp32 input render buffer is CONVERTED once to a uint16
// RGB working buffer and the PROVIDER IS RELEASED (onInputConsumed)
// BEFORE the tile loop starts allocating toward the 4× output — the loop
// holds only the uint16 input (~1/2 the fp32 size), the current tile's
// frames, and the fp32 output. The 100MP×4 output peak (6.4 GB fp32) is
// the plan's documented risk; the row-band streaming mitigation stays the
// E3 fallback (DECISIONS).
//
// TILE FRAMES travel the PATH channel (the M2-10-05 red line): the engine
// crops each tile (+pad-to-fit for sub-tile spans) into a 16-bit RGB TIFF
// tmp file, the executor runs it (the worker decodes/infers/writes), the
// engine reads the 16-bit output tile back and blends. Denoise strength
// blending is WORKER-side (the models carry no strength input); the
// engine's blend is the TILE WEIGHTS only.
//
// CANCEL (KD-2): checked before every tile — a cancel deletes the in-flight
// tmp files and surfaces `.cancelled`; the dialog maps it to close-after
// (never a hard kill — the worker's current tile finishes first).
// ─────────────────────────────────────────────────────────────────────────────

/// The engine's frame currency: interleaved RGBA float32, [0,1] display
/// domain (the render provider's contract; values clamp on encode).
public struct EnhanceFrame: Sendable, Equatable {
    public var rgba: [Float]
    public let width: Int
    public let height: Int

    public init(rgba: [Float], width: Int, height: Int) {
        self.rgba = rgba
        self.width = width
        self.height = height
    }
}

/// The typed engine failures (the dialog maps these to honest copy text).
public enum EnhanceEngineError: Error, Equatable {
    /// The user cancelled (or the dialog's close-after arm did).
    case cancelled
    /// The output budget was exceeded (the planner's typed rejection).
    case pixelBudgetExceeded(outputPixels: Int, limit: Int)
    /// Tile `index` failed with the executor's detail (the worker's typed
    /// error rides through).
    case tileFailed(index: Int, detail: String)
    /// The model facts were unusable (empty supported edges).
    case modelFactsInvalid(String)
}

/// One tile-run request through the executor seam (the worker client's
/// `enhanceTile` shape; a stub reproduces it trivially in tests).
public struct EnhanceTileRequest: Sendable {
    public let tileIndex: Int
    public let inputTile: URL
    public let outputTile: URL
    public let feedHeight: Int
    public let feedWidth: Int
    /// The denoise strength 0...100 (nil for upscale).
    public let amount: Double?

    public init(
        tileIndex: Int, inputTile: URL, outputTile: URL,
        feedHeight: Int, feedWidth: Int, amount: Double?
    ) {
        self.tileIndex = tileIndex
        self.inputTile = inputTile
        self.outputTile = outputTile
        self.feedHeight = feedHeight
        self.feedWidth = feedWidth
        self.amount = amount
    }
}

public struct EnhanceEngine {

    /// The model facts (the worker open's response — never guessed here).
    public let supportedEdges: [Int]
    public let scale: Int
    /// The denoise strength 0...100 (nil for upscale).
    public let amount: Double?

    public init(supportedEdges: [Int], scale: Int, amount: Double?) {
        self.supportedEdges = supportedEdges
        self.scale = scale
        self.amount = amount
    }

    /// The full orchestration (KD-2). `onInputConsumed` fires after the
    /// input has been converted to the uint16 working buffer — the caller
    /// drops its fp32 render buffer there (the memory pin).
    public func run(
        input: EnhanceFrame,
        tmpDirectory: URL,
        tileExecutor: @escaping @Sendable (EnhanceTileRequest) async throws -> Void,
        onInputConsumed: (@Sendable () -> Void)? = nil,
        onProgress: (@Sendable (Int) -> Void)? = nil,
        cancellation: @escaping @Sendable () -> Bool = { false }
    ) async throws -> EnhanceFrame {
        guard !supportedEdges.isEmpty, scale >= 1 else {
            throw EnhanceEngineError.modelFactsInvalid(
                "supportedEdges/scale unusable")
        }
        let grid = try TilePlanner.plan(
            inputWidth: input.width, inputHeight: input.height,
            scale: scale, supportedEdges: supportedEdges)

        // The uint16 RGB working buffer (the encode clamp — the output
        // container is uint16 anyway, so the input leg quantizes once).
        var working = [UInt16](repeating: 0, count: input.width * input.height * 3)
        for index in 0..<(input.width * input.height) {
            for channel in 0..<3 {
                let value = min(max(input.rgba[index * 4 + channel], 0), 1)
                working[index * 3 + channel] = UInt16(
                    Int((value * 65535.0).rounded()))
            }
        }
        onInputConsumed?()

        // The fp32 output accumulator + the separable normalization sums
        // (×scale-repeated to output space — Lumen's `np.repeat` parity).
        let outputWidth = grid.outputWidth
        let outputHeight = grid.outputHeight
        var output = [Float](repeating: 0, count: outputWidth * outputHeight * 3)
        let rowSums = TilePlanner.axisWeightSums(
            spans: rowSpans(grid), length: input.height)
        let columnSums = TilePlanner.axisWeightSums(
            spans: columnSpans(grid), length: input.width)

        try FileManager.default.createDirectory(
            at: tmpDirectory, withIntermediateDirectories: true)
        var inFlight: [URL] = []

        do {
            for (tileIndex, tile) in grid.tiles.enumerated() {
                if cancellation() {
                    throw EnhanceEngineError.cancelled
                }
                // Crop (+pad-to-fit) the input tile → 16-bit RGB TIFF.
                let inputTile = tmpDirectory
                    .appendingPathComponent("tile-in-\(tileIndex).tif")
                let outputTile = tmpDirectory
                    .appendingPathComponent("tile-out-\(tileIndex).tif")
                inFlight.append(contentsOf: [inputTile, outputTile])
                try Self.writeTileFile(
                    working, width: input.width, height: input.height,
                    tile: tile, grid: grid, to: inputTile)
                // The path channel (the worker decodes, infers, blends the
                // denoise amount, and writes the output tile).
                try await tileExecutor(EnhanceTileRequest(
                    tileIndex: tileIndex,
                    inputTile: inputTile, outputTile: outputTile,
                    feedHeight: tile.feedHeight, feedWidth: tile.feedWidth,
                    amount: amount))
                // Read back and blend into the accumulator.
                let result = try Self.readTileFile(outputTile)
                guard result.width == tile.feedWidth * scale,
                      result.height == tile.feedHeight * scale else {
                    throw EnhanceEngineError.tileFailed(
                        index: tileIndex,
                        detail: "output tile \(result.width)×\(result.height) "
                            + "!= feed×scale")
                }
                Self.blend(
                    tile: tile, grid: grid, tilePixels: result.rgb,
                    tileWidth: result.width,
                    into: &output, outputWidth: outputWidth)
                // The tile's frames are consumed — keep the tmp set small
                // on long runs (a cancel sweep only has the current pair).
                try? FileManager.default.removeItem(at: inputTile)
                try? FileManager.default.removeItem(at: outputTile)
                inFlight.removeAll()
                onProgress?(TilePlanner.progressPercent(
                    done: tileIndex + 1, total: grid.tiles.count))
            }
        } catch {
            // The cancel/failure sweep: no half-made tile tmp survives.
            for url in inFlight {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }

        // Normalize by the accumulated weights (strictly positive — the
        // planner's coverage anchor) and re-attach opaque alpha.
        var rgba = [Float](repeating: 1, count: outputWidth * outputHeight * 4)
        for y in 0..<outputHeight {
            let wy = rowSums[min(y / scale, input.height - 1)]
            for x in 0..<outputWidth {
                let wx = columnSums[min(x / scale, input.width - 1)]
                let source = (y * outputWidth + x) * 3
                let target = (y * outputWidth + x) * 4
                for channel in 0..<3 {
                    rgba[target + channel] =
                        output[source + channel] / (wx * wy)
                }
            }
        }
        return EnhanceFrame(
            rgba: rgba, width: outputWidth, height: outputHeight)
    }

    // MARK: - Grid axis helpers

    private func rowSpans(_ grid: TileGrid) -> [TileGrid.Span] {
        // Reconstruct the per-axis spans from the tiles (the planner's own
        // derivation — y and x spans repeat deterministically).
        var seenY: Set<Int> = []
        var rows: [TileGrid.Span] = []
        var seenX: Set<Int> = []
        var columns: [TileGrid.Span] = []
        for tile in grid.tiles {
            if seenY.insert(tile.y).inserted {
                rows.append(TileGrid.Span(start: tile.y, length: tile.height))
            }
            if seenX.insert(tile.x).inserted {
                columns.append(TileGrid.Span(start: tile.x, length: tile.width))
            }
        }
        return rows
    }

    private func columnSpans(_ grid: TileGrid) -> [TileGrid.Span] {
        var seenX: Set<Int> = []
        var columns: [TileGrid.Span] = []
        for tile in grid.tiles {
            if seenX.insert(tile.x).inserted {
                columns.append(TileGrid.Span(start: tile.x, length: tile.width))
            }
        }
        return columns
    }

    // MARK: - Tile file codec (16-bit RGB TIFF)

    /// Crop (+pad-to-fit) the working buffer into the tile's 16-bit RGB
    /// TIFF feed frame.
    static func writeTileFile(
        _ working: [UInt16], width: Int, height: Int,
        tile: TileGrid.Tile, grid: TileGrid, to destination: URL
    ) throws {
        let feedWidth = tile.feedWidth, feedHeight = tile.feedHeight
        var pixels = [UInt16](repeating: 0, count: feedWidth * feedHeight * 4)
        for y in 0..<feedHeight {
            let sourceY = min(tile.y + y, height - 1)
            for x in 0..<feedWidth {
                let sourceX = min(tile.x + x, width - 1)
                let source = (sourceY * width + sourceX) * 3
                let target = (y * feedWidth + x) * 4
                pixels[target] = working[source]
                pixels[target + 1] = working[source + 1]
                pixels[target + 2] = working[source + 2]
                pixels[target + 3] = UInt16.max
            }
        }
        let image = try tileImage(
            pixels: pixels, width: feedWidth, height: feedHeight)
        try writeTIFF(image, to: destination)
    }

    /// Read a 16-bit tile file back (RGBA16 context draw — the L060
    /// single-draw discipline).
    static func readTileFile(_ url: URL) throws -> (
        rgb: [Float], width: Int, height: Int
    ) {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else {
            throw EnhanceEngineError.tileFailed(
                index: -1, detail: "tile file unreadable: \(url.path)")
        }
        let width = image.width, height = image.height
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        let context = pixels.withUnsafeMutableBytes {
            (raw: UnsafeMutableRawBufferPointer) -> CGContext? in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 16, bytesPerRow: width * 8,
                space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder16Little.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context else {
            throw EnhanceEngineError.tileFailed(
                index: -1, detail: "tile context create failed")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rgb = [Float](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            for channel in 0..<3 {
                rgb[index * 3 + channel] =
                    Float(pixels[index * 4 + channel]) / 65535.0
            }
        }
        return (rgb, width, height)
    }

    static func tileImage(
        pixels: [UInt16], width: Int, height: Int
    ) throws -> CGImage {
        let pixelData = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: pixelData as CFData) else {
            throw EnhanceEngineError.tileFailed(
                index: -1, detail: "tile provider create failed")
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder16Little.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw EnhanceEngineError.tileFailed(
                index: -1, detail: "tile CGImage create failed")
        }
        return image
    }

    private static func writeTIFF(_ image: CGImage, to destination: URL) throws {
        guard let destinationImage = CGImageDestinationCreateWithURL(
            destination as CFURL, "public.tiff" as CFString, 1, nil)
        else {
            throw EnhanceEngineError.tileFailed(
                index: -1, detail: "tile destination create failed")
        }
        CGImageDestinationAddImage(destinationImage, image, nil)
        guard CGImageDestinationFinalize(destinationImage) else {
            throw EnhanceEngineError.tileFailed(
                index: -1, detail: "tile finalize failed")
        }
    }

    // MARK: - Blend

    /// Accumulate one output tile into the frame (the separable ramp
    /// weights; the normalization divides at the end).
    static func blend(
        tile: TileGrid.Tile, grid: TileGrid, tilePixels: [Float],
        tileWidth: Int, into output: inout [Float], outputWidth: Int
    ) {
        let rect = grid.outputRect(of: tile)
        for y in 0..<rect.height {
            let inputY = tile.y + y / grid.scale
            for x in 0..<rect.width {
                let inputX = tile.x + x / grid.scale
                let weight = Self.tileWeight(
                    grid: grid, tile: tile, inputX: inputX, inputY: inputY)
                // The tile buffer's row stride is the TILE's width (the
                // feed shape) — the valid rect may be narrower (pad-to-fit).
                let source = (y * tileWidth + x) * 3
                let target = ((rect.y + y) * outputWidth + rect.x + x) * 3
                output[target] += tilePixels[source] * weight
                output[target + 1] += tilePixels[source + 1] * weight
                output[target + 2] += tilePixels[source + 2] * weight
            }
        }
    }

    /// The tile's weight at one OUTPUT pixel: the separable product of the
    /// span-local ramp weights (not the accumulated sums — those are the
    /// final denominators).
    static func tileWeight(
        grid: TileGrid, tile: TileGrid.Tile, inputX: Int, inputY: Int
    ) -> Float {
        let rowSpan = TileGrid.Span(start: tile.y, length: tile.height)
        let columnSpan = TileGrid.Span(start: tile.x, length: tile.width)
        let wy = TilePlanner.spanWeight(
            span: rowSpan, position: inputY, axisLength: grid.height,
            overlap: grid.overlap)
        let wx = TilePlanner.spanWeight(
            span: columnSpan, position: inputX, axisLength: grid.width,
            overlap: grid.overlap)
        return wx * wy
    }
}
