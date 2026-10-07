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
// EXECUTION ORDER (the KD-2 memory pin, the M-1 fix): the fp32 input is
// QUANTIZED OUTSIDE the run — `prepareInput` converts it to the uint16
// working buffer in a frame of its own, and the CALLER drops their fp32
// reference before `run(prepared:)` starts (the production runFullCopy
// scopes both, so no frame in the chain holds the fp32 across the tile
// loop — the old `run(input:)` parameter pin was inert: the callee frame
// held the input array until return, M2-10-06 ACCEPTANCE M-1 #1). The
// loop holds only the uint16 input (6 B/px), the current tile's frames,
// and ONE fp32 RGBA accumulator (16 B/output px) — the M-1 #2 endgame
// double buffer (RGB accumulate + RGBA normalize coexisting, 28 B/px) is
// GONE: blend accumulates into the RGBA layout and normalization divides
// IN PLACE. The writer's uint16 encode buffer adds 8 B/output px at the
// fill transient (the provider owns it — no full-frame Data copy), so
// the honest worst case is ~24 B/output px.
//
// MEMORY GATE (the M-1 #3 defense): before any output-sized allocation,
// the engine estimates the peak footprint from the planned geometry and
// typed-rejects jobs over the budget — never an OOM button. The 400 MP
// output cap (TilePlanner) stays the absolute planner bound; this gate
// sits below it. The row-band streaming unlock (E3) is what eventually
// raises the gate — until then, honest rejection over silent OOM.
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
    /// The estimated peak footprint exceeded the memory budget (the typed
    /// defense — rejected BEFORE any allocation, never an OOM).
    case memoryBudgetExceeded(estimatedBytes: Int, limit: Int)
    /// Tile `index` failed with the executor's detail (the worker's typed
    /// error rides through).
    case tileFailed(index: Int, detail: String)
    /// The model facts were unusable (empty supported edges).
    case modelFactsInvalid(String)
}

/// The quantized input (the fp32 release pin's payload): the uint16 RGB
/// working buffer + its shape. `EnhanceEngine.prepareInput` builds it in
/// a frame of its own — when that frame returns the ENGINE side holds no
/// fp32, and the caller drops their own reference before `run(prepared:)`
/// (the production runFullCopy scopes both; nothing in the chain holds
/// the fp32 across the tile loop).
public struct EnhancePreparedInput: Sendable {
    /// Interleaved RGB uint16, clamped to [0,1] (the output container is
    /// uint16 anyway — the input leg quantizes once).
    public let working: [UInt16]
    public let width: Int
    public let height: Int

    public init(working: [UInt16], width: Int, height: Int) {
        self.working = working
        self.width = width
        self.height = height
    }
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
    /// The peak-footprint budget (bytes) — the typed gate's limit. The
    /// default is 6 GiB: the 8192 MB run gate (the test harness MEMFAIL
    /// line) minus ~2 GB of app + framework + allocator headroom.
    public let memoryBudgetBytes: Int

    public init(
        supportedEdges: [Int], scale: Int, amount: Double?,
        memoryBudgetBytes: Int = EnhanceEngine.memoryBudgetBytes
    ) {
        self.supportedEdges = supportedEdges
        self.scale = scale
        self.amount = amount
        self.memoryBudgetBytes = memoryBudgetBytes
    }

    // MARK: - Memory posture (the honest gate arithmetic, M-1 #3)

    /// The estimated peak footprint for one job, BEFORE any allocation:
    /// 16 B/output px (the fp32 RGBA accumulator — the ONLY output
    /// buffer; the M-1 #2 double buffer is gone) + 8 B/output px (the
    /// writer's uint16 encode buffer, held with the accumulator during
    /// the fill transient) + 6 B/input px (the uint16 working input).
    /// The row-band streaming unlock (E3) is what eventually lowers it.
    public static func estimatedPeakBytes(
        outputPixels: Int, inputPixels: Int
    ) -> Int {
        outputPixels * 24 + inputPixels * 6
    }

    /// The default peak-footprint budget (6 GiB).
    public static let memoryBudgetBytes = 6 * 1024 * 1024 * 1024

    /// The input PREPARE (the fp32 release pin, M-1 #1): quantize the
    /// fp32 frame to the uint16 working buffer in a frame of its own —
    /// when it returns this frame's fp32 reference is gone and
    /// `onInputConsumed` has fired. The CALLER must also drop their own
    /// reference (the production runFullCopy scopes the frame so BOTH
    /// sides die before the tile loop allocates toward the output).
    public static func prepareInput(
        _ input: EnhanceFrame,
        onInputConsumed: (@Sendable () -> Void)? = nil
    ) -> EnhancePreparedInput {
        var working = [UInt16](
            repeating: 0, count: input.width * input.height * 3)
        for index in 0..<(input.width * input.height) {
            for channel in 0..<3 {
                let value = min(max(input.rgba[index * 4 + channel], 0), 1)
                working[index * 3 + channel] = UInt16(
                    Int((value * 65535.0).rounded()))
            }
        }
        onInputConsumed?()
        return EnhancePreparedInput(
            working: working, width: input.width, height: input.height)
    }

    /// The full orchestration (KD-2, the two-phase form): `prepared`
    /// comes from `prepareInput` — the fp32 input is already out of the
    /// picture, so the loop holds only the uint16 input (6 B/px), the
    /// current tile's frames, and the single fp32 RGBA accumulator
    /// (16 B/output px).
    public func run(
        prepared: EnhancePreparedInput,
        tmpDirectory: URL,
        tileExecutor: @escaping @Sendable (EnhanceTileRequest) async throws -> Void,
        onProgress: (@Sendable (Int) -> Void)? = nil,
        cancellation: @escaping @Sendable () -> Bool = { false }
    ) async throws -> EnhanceFrame {
        guard !supportedEdges.isEmpty, scale >= 1 else {
            throw EnhanceEngineError.modelFactsInvalid(
                "supportedEdges/scale unusable")
        }
        let grid = try TilePlanner.plan(
            inputWidth: prepared.width, inputHeight: prepared.height,
            scale: scale, supportedEdges: supportedEdges)

        // THE MEMORY GATE (typed, BEFORE any output-sized allocation —
        // the estimate never hands a budget breach to an allocation). The
        // planner's 400 MP output cap stays the absolute bound above it.
        let estimated = Self.estimatedPeakBytes(
            outputPixels: grid.outputWidth * grid.outputHeight,
            inputPixels: grid.width * grid.height)
        guard estimated <= memoryBudgetBytes else {
            throw EnhanceEngineError.memoryBudgetExceeded(
                estimatedBytes: estimated, limit: memoryBudgetBytes)
        }

        // The fp32 RGBA accumulator — THE single output buffer (16 B per
        // output pixel). Blend accumulates channels 0..<3 at stride 4;
        // the final normalization divides IN PLACE (the M-1 #2 fix: no
        // second RGBA frame — the old RGB + RGBA pair peaked at 28 B/px).
        let outputWidth = grid.outputWidth
        let outputHeight = grid.outputHeight
        var rgba = [Float](repeating: 0, count: outputWidth * outputHeight * 4)
        let rowSums = TilePlanner.axisWeightSums(
            spans: rowSpans(grid), length: prepared.height)
        let columnSums = TilePlanner.axisWeightSums(
            spans: columnSpans(grid), length: prepared.width)

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
                    prepared.working, width: prepared.width,
                    height: prepared.height,
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
                    into: &rgba, outputWidth: outputWidth)
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

        // In-place normalize by the accumulated weights (strictly
        // positive — the planner's coverage anchor) and re-attach opaque
        // alpha — ONE buffer end to end.
        for y in 0..<outputHeight {
            let wy = rowSums[min(y / scale, prepared.height - 1)]
            for x in 0..<outputWidth {
                let wx = columnSums[min(x / scale, prepared.width - 1)]
                let target = (y * outputWidth + x) * 4
                for channel in 0..<3 {
                    rgba[target + channel] /= (wx * wy)
                }
                rgba[target + 3] = 1
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
    /// weights; the normalization divides at the end). The target is the
    /// RGBA accumulator (stride 4 — channels 0..<3 only; alpha is set at
    /// the in-place normalize).
    static func blend(
        tile: TileGrid.Tile, grid: TileGrid, tilePixels: [Float],
        tileWidth: Int, into rgba: inout [Float], outputWidth: Int
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
                let target = ((rect.y + y) * outputWidth + rect.x + x) * 4
                rgba[target] += tilePixels[source] * weight
                rgba[target + 1] += tilePixels[source + 1] * weight
                rgba[target + 2] += tilePixels[source + 2] * weight
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
