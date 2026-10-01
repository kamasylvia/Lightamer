import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// Follow Edges (Plan M2-7-1 T6, KD-6; M2MASK-05, D-M2-7-CONTEXT-4 A) — the
// edge-aware brush: a precomputed edge map (MaskEdgeKernels.metal, cached at
// `PipeCacheKey.edgeMapPosition`) + a CPU streamline WALKER that turns one
// seed into a MaskPoint chain riding the local edge tangent.
//
// The output is an ORDINARY brush form's point chain — the caller packs it
// into a BrushStroke (radius/hardness/density/opacity = the current brush
// parameters) and appends through the overlay's existing legs. The
// rasterizer/combine pipeline sees nothing new: ALL the edge-awareness
// lives in the input chain's GENERATION (the Phase-6 stamping brush stays
// the data正本, D-M2-7-CONTEXT-2).
//
// Complexity fuse (OQ-4-C, pre-wired): `FollowEdgesMode` carries BOTH cases
// from day one — `.streamline` (the full tangent walker) and `.snap` (seed
// snaps to the nearest strong edge, straight-line stamps). The P3实测
// ruling flips the UI DEFAULT, not the code: the walker is never deleted.
//
// Failure degradation: an unavailable edge map (nil field / empty values /
// no edge above threshold within reach) yields an EMPTY chain — the caller
// performs NO append and surfaces the state (never a silent no-op stroke).
// ─────────────────────────────────────────────────────────────────────────────

/// The two wired modes (the complexity-fuse switch — see the header).
public enum FollowEdgesMode: String, Codable, Sendable, Equatable, Hashable {
    /// The full tangent-streamline walker.
    case streamline
    /// The degrade: snap the seed to the nearest strong edge, straight
    /// stamps from there (the OQ-4-C fallback shape).
    case snap
}

/// The Follow Edges parameter face (KD-6③) — the P2 UI consumes these.
/// The brush WIDTH is not here: it passes through as the packed
/// BrushStroke's radius (the caller's current brush parameter).
public struct FollowEdgesParams: Sendable, Equatable {

    /// The contrast gate on the NORMALIZED edge map [0,1]: below it the
    /// walker stops (and the seed snaps).
    public var edgeThreshold: Float

    /// Tangent momentum 0..1: 0 = pure local tangent every step (turns
    /// sharply around corners), 1 = straight line after the first heading.
    public var followStrength: Float

    /// The tangent side: +1 or −1 (the gradient rotated ±90°).
    public var direction: Float

    /// The walker step in edge-map pixels.
    public var stepPixels: Float

    /// The chain-length bound (the runaway fuse).
    public var maxPoints: Int

    public var mode: FollowEdgesMode

    public init(
        edgeThreshold: Float = 0.25,
        followStrength: Float = 0.5,
        direction: Float = 1,
        stepPixels: Float = 1.5,
        maxPoints: Int = 256,
        mode: FollowEdgesMode = .streamline
    ) {
        self.edgeThreshold = edgeThreshold
        self.followStrength = followStrength
        self.direction = direction
        self.stepPixels = stepPixels
        self.maxPoints = maxPoints
        self.mode = mode
    }
}

/// The CPU readback of an edge map (the walker's input domain). Coordinates
/// are the map's own pixel grid; the P2 caller hands the STROKE-LOCAL
/// window (seed bounding box + margin, working long edge ≤512 — the
/// resolution guard) after `readEdgeMap`'s fenced readback (L014).
public struct EdgeMapField: Sendable {

    public var width: Int
    public var height: Int

    /// Normalized edge strength [0,1], row-major (width × height).
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
    }

    public func value(atX x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return values[y * width + x]
    }
}

public enum FollowEdges {

    /// The mode dispatcher (exhaustive — no default; 纪律 7).
    public static func chain(
        seed: MaskPoint, field: EdgeMapField?, params: FollowEdgesParams
    ) -> [MaskPoint] {
        switch params.mode {
        case .streamline: return streamline(seed: seed, field: field, params: params)
        case .snap: return snap(seed: seed, field: field, params: params)
        }
    }

    // MARK: - The walker (pure Swift, deterministic — no RNG anywhere)

    /// Seed (normalized [0,1] over the map's own frame) → the MaskPoint
    /// chain riding the local edge. Empty output = the documented degrade
    /// (no map / no edge above threshold within reach).
    ///
    /// Mechanics (KD-6②): the heading follows the edge tangent = the local
    /// gradient rotated 90°, sampled AHEAD of the walker (a magnitude
    /// ridge's crest self-sample vanishes — the flank one step ahead is
    /// the informative reading, and it is what rotates the heading around
    /// a corner); a zero reading falls back to the strongest ±1-ring
    /// gradient, then to pure momentum (the follow-strength blend).
    public static func streamline(
        seed: MaskPoint, field: EdgeMapField?, params: FollowEdgesParams
    ) -> [MaskPoint] {
        guard let field, field.width > 1, field.height > 1,
            field.values.count == field.width * field.height
        else { return [] }
        let w = Double(field.width - 1), h = Double(field.height - 1)
        var seedPixel = SIMD2(Double(seed.x), Double(seed.y)) * SIMD2(w, h)
        let dirSign: Double = params.direction >= 0 ? 1 : -1
        let λ = Double(max(0, min(1, params.followStrength)))
        let threshold = Double(params.edgeThreshold)
        let step = Double(max(0.5, params.stepPixels))

        // Seed snap: an off-edge seed walks from its nearest STRONG
        // neighbor (8 px reach — the streamline share of the snap
        // geometry); none → the empty-chain degrade.
        if sample(field, seedPixel) < threshold {
            guard let snapped = snapTarget(
                field, around: seedPixel, radius: 8, threshold: threshold)
            else { return [] }
            seedPixel = snapped
        }

        var heading = initialHeading(field, at: seedPixel, dirSign: dirSign)

        func walk(_ sign: Double) -> [SIMD2<Double>] {
            var chain: [SIMD2<Double>] = []
            var position = seedPixel
            var direction = heading * sign
            for _ in 0..<(params.maxPoints / 2) {
                // Lookahead gradient (the flank one step ahead), falling
                // back to the strongest ring reading, then to momentum.
                let look = position + direction * step
                var grad = gradient(field, at: look) ?? SIMD2(0, 0)
                if lengthOf(grad) < 1e-4 {
                    grad = strongestRingGradient(field, at: position) ?? SIMD2(0, 0)
                }
                if lengthOf(grad) >= 1e-4 {
                    let tangent = tryNormalize(SIMD2(-grad.y, grad.x) * dirSign)
                        ?? direction
                    direction = tryNormalize(direction * λ + tangent * (1 - λ))
                        ?? direction
                }
                let next = position + direction * step
                guard next.x >= 0, next.y >= 0,
                    next.x <= Double(field.width - 1),
                    next.y <= Double(field.height - 1),
                    sample(field, next) >= threshold
                else { break }
                chain.append(next)
                position = next
            }
            return chain
        }

        // Bidirectional walk from the seed (双步进): + heading and −
        // heading, gated independently.
        let forward = walk(1)
        let backward = walk(-1)
        var pixels: [SIMD2<Double>] = backward.reversed()
        pixels.append(seedPixel)
        pixels.append(contentsOf: forward)

        var seen = Set< SIMDTwoKey>() // grid-quantized dedup
        var out: [MaskPoint] = []
        out.reserveCapacity(pixels.count)
        for pixel in pixels {
            let key = SIMDTwoKey(
                x: (pixel.x * 2).rounded(), y: (pixel.y * 2).rounded())
            guard seen.insert(key).inserted else { continue }
            out.append(MaskPoint(x: Float(pixel.x / w), y: Float(pixel.y / h)))
        }
        return out
    }

    /// The `.snap` degrade: [seed, snappedTarget] — the caller stamps a
    /// STRAIGHT line between the two (KD-6's fuse shape). Empty = no edge
    /// within reach (nothing to snap to — the caller surfaces it).
    public static func snap(
        seed: MaskPoint, field: EdgeMapField?, params: FollowEdgesParams
    ) -> [MaskPoint] {
        guard let field, field.width > 1, field.height > 1,
            field.values.count == field.width * field.height
        else { return [] }
        let w = Double(field.width - 1), h = Double(field.height - 1)
        let p = SIMD2(Double(seed.x), Double(seed.y)) * SIMD2(w, h)
        guard let target = snapTarget(
            field, around: p, radius: 12,
            threshold: Double(params.edgeThreshold))
        else { return [] }
        return [
            MaskPoint(x: Float(p.x / w), y: Float(p.y / h)),
            MaskPoint(x: Float(target.x / w), y: Float(target.y / h)),
        ]
    }

    // MARK: - Field sampling primitives (pure)

    /// A hashable grid key (SIMD2<Double> is not Hashable — the dedup
    /// grid is half-pixel quantized, deterministic).
    private struct SIMDTwoKey: Hashable {
        var x: Double
        var y: Double
    }

    private static func lengthOf(_ v: SIMD2<Double>) -> Double {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    private static func sample(_ field: EdgeMapField, _ p: SIMD2<Double>) -> Double {
        let x = min(max(0, Int(p.x.rounded())), field.width - 1)
        let y = min(max(0, Int(p.y.rounded())), field.height - 1)
        return Double(field.values[y * field.width + x])
    }

    /// Central-difference gradient of the normalized map at a pixel.
    private static func gradient(
        _ field: EdgeMapField, at p: SIMD2<Double>
    ) -> SIMD2<Double>? {
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        guard let cx0 = field.value(atX: x - 1, y: y),
            let cx1 = field.value(atX: x + 1, y: y),
            let cy0 = field.value(atX: x, y: y - 1),
            let cy1 = field.value(atX: x, y: y + 1)
        else { return nil }
        return SIMD2(Double(cx1 - cx0), Double(cy1 - cy0))
    }

    /// The initial heading: the strongest gradient among the seed and its
    /// ±1 ring, rotated 90° (on a magnitude ridge the crest self-sample is
    /// zero — a flank neighbor carries the reading).
    private static func initialHeading(
        _ field: EdgeMapField, at p: SIMD2<Double>, dirSign: Double
    ) -> SIMD2<Double> {
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        var best = SIMD2(0.0, 0.0)
        var bestLength = 0.0
        for dy in -1...1 {
            for dx in -1...1 {
                guard let grad = gradient(
                    field, at: SIMD2(Double(x + dx), Double(y + dy)))
                else { continue }
                let length = lengthOf(grad)
                if length > bestLength {
                    bestLength = length
                    best = grad
                }
            }
        }
        guard bestLength > 1e-4 else { return SIMD2(dirSign, 0) }
        return tryNormalize(SIMD2(-best.y, best.x) * dirSign) ?? SIMD2(dirSign, 0)
    }

    /// The strongest gradient among the ±1 ring (the on-crest fallback).
    private static func strongestRingGradient(
        _ field: EdgeMapField, at p: SIMD2<Double>
    ) -> SIMD2<Double>? {
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        var best: SIMD2<Double>?
        var bestLength = 0.0
        for dy in -1...1 {
            for dx in -1...1 {
                guard let grad = gradient(
                    field, at: SIMD2(Double(x + dx), Double(y + dy)))
                else { continue }
                let length = lengthOf(grad)
                if length > bestLength {
                    bestLength = length
                    best = grad
                }
            }
        }
        return best
    }

    /// The strongest pixel within `radius` of `around` whose value clears
    /// `threshold` (the seed snap; deterministic scan order — purity). No
    /// candidate → nil (the empty-chain degrade; sub-threshold ripples
    /// NEVER count as edges).
    private static func snapTarget(
        _ field: EdgeMapField, around p: SIMD2<Double>, radius: Int,
        threshold: Double
    ) -> SIMD2<Double>? {
        let cx = Int(p.x.rounded()), cy = Int(p.y.rounded())
        var best: (point: SIMD2<Double>, value: Float)?
        for dy in -radius...radius {
            for dx in -radius...radius {
                guard let v = field.value(atX: cx + dx, y: cy + dy),
                    Double(v) >= threshold
                else { continue }
                if best == nil || v > best!.value {
                    best = (SIMD2(Double(cx + dx), Double(cy + dy)), v)
                }
            }
        }
        guard let best else { return nil }
        return best.point
    }

    private static func tryNormalize(_ v: SIMD2<Double>) -> SIMD2<Double>? {
        let length = lengthOf(v)
        guard length > 1e-9 else { return nil }
        return v / length
    }

    // MARK: - The fenced readback primitive (L014) + the ≤512 resolution guard

    /// Read an r32Float edge map back to CPU behind a command-buffer fence
    /// (L014: `getBytes` must not race in-flight encoders), then CPU
    /// box-downsample to a ≤`maxLongEdge` working resolution (the
    /// stroke-local window the P2 caller crops keeps the walker cheap).
    public static func readEdgeMap(
        _ plane: any MTLTexture, maxLongEdge: Int = 512, metal: MetalContext
    ) -> EdgeMapField? {
        guard plane.width > 0, plane.height > 0 else { return nil }
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted() // L014
        var raw = [Float](repeating: -1, count: plane.width * plane.height)
        raw.withUnsafeMutableBytes {
            plane.getBytes(
                $0.baseAddress!, bytesPerRow: plane.width * 4,
                from: MTLRegionMake2D(0, 0, plane.width, plane.height),
                mipmapLevel: 0)
        }
        let longEdge = max(plane.width, plane.height)
        guard longEdge > maxLongEdge else {
            return EdgeMapField(width: plane.width, height: plane.height, values: raw)
        }
        // Box subsample (nearest — an edge field tolerates it; determinism
        // beats interpolation cost here).
        let scale = Double(longEdge) / Double(maxLongEdge)
        let outW = max(2, Int(Double(plane.width) / scale))
        let outH = max(2, Int(Double(plane.height) / scale))
        var out = [Float](repeating: 0, count: outW * outH)
        for y in 0..<outH {
            let sy = min(plane.height - 1, Int((Double(y) + 0.5) * scale))
            for x in 0..<outW {
                let sx = min(plane.width - 1, Int((Double(x) + 0.5) * scale))
                out[y * outW + x] = raw[sy * plane.width + sx]
            }
        }
        return EdgeMapField(width: outW, height: outH, values: out)
    }

    // MARK: - The GPU pass (the single-PSO edge map)

    /// Run `mask_edge_map` over the below composite plane → a fresh
    /// r32Float plane (the caller caches it at `PipeCacheKey.edgeMapKey`).
    public static func edgeMap(
        below: any MTLTexture, metal: MetalContext
    ) async throws -> any MTLTexture {
        let output = try MaskCombiner.maskLikeShape(
            width: below.width, height: below.height, metal: metal)
        let session = try await metal.makeEncoder(functionName: "mask_edge_map")
        session.encoder.setTexture(below, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }
}
