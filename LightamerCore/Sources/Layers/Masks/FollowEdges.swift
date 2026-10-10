import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// Follow Edges (Plan M2-7-1 T6, KD-6; M2MASK-05, D-M2-7-CONTEXT-4 A; V2
// re-anchor Plan M4-2-01 KD-2) — the edge-aware brush: a precomputed edge map
// (MaskEdgeKernels.metal, cached at `PipeCacheKey.edgeMapPosition`) + a CPU
// walk over the EXTRACTED RIDGE GRAPH (RidgeExtract) that turns one seed into
// a MaskPoint chain riding the ridge.
//
// The output is an ORDINARY brush form's point chain — the caller packs it
// into a BrushStroke (radius/hardness/density/opacity = the current brush
// parameters) and appends through the overlay's existing legs. The
// rasterizer/combine pipeline sees nothing new: ALL the edge-awareness
// lives in the input chain's GENERATION (the Phase-6 stamping brush stays
// the data正本, D-M2-7-CONTEXT-2).
//
// V2 (M4-2-01): the `.streamline` arm consumes the pre-extracted RidgeGraph
// (seed attach → bidirectional traversal → greedy junction continuation →
// curvature-modulated resampling). The V1 per-point tangent walker
// (lookahead flanking samples, momentum blend λ, ring-gradient fallback) is
// RETIRED in the same batch (OQ-7 — the golden landed with the deletion).
//
// Complexity fuse (OQ-4-C, pre-wired): `FollowEdgesMode` carries BOTH cases
// from day one — `.streamline` (the ridge-graph walk) and `.snap` (seed
// snaps to the nearest strong edge, straight-line stamps). The P3实测
// ruling flips the UI DEFAULT, not the code.
//
// Failure degradation: an unavailable edge map (nil field / empty values /
// no ridge vertex within reach) yields an EMPTY chain — the caller
// performs NO append and surfaces the state (never a silent no-op stroke).
// ─────────────────────────────────────────────────────────────────────────────

/// The two wired modes (the complexity-fuse switch — see the header).
public enum FollowEdgesMode: String, Codable, Sendable, Equatable, Hashable {
    /// The ridge-graph walker (V2).
    case streamline
    /// The degrade: snap the seed to the nearest strong edge, straight
    /// stamps from there (the OQ-4-C fallback shape).
    case snap
}

/// The Follow Edges parameter face (KD-6③) — the P2 UI consumes these.
/// The brush WIDTH is not here: it passes through as the packed
/// BrushStroke's radius (the caller's current brush parameter).
/// Session-state only (never persisted) — field evolution carries no
/// migration (M4-2-01 OQ-4-A: the fixed-step and chain-cap fields are
/// withdrawn; the adaptive resampling made a fixed step meaningless and the
/// chain fuse became the walker-internal constant below).
public struct FollowEdgesParams: Sendable, Equatable {

    /// The contrast gate on the NORMALIZED edge map [0,1]: the hysteresis
    /// HIGH of the V2 ridge extraction (low = 0.4·high is internal) — the
    /// same "how strong counts as an edge" meaning the V1 walk gated on.
    public var edgeThreshold: Float

    /// The WALK-phase junction-continuation bias (V2 redefinition — V1's
    /// tangent-momentum blend is retired): the minimum alignment cosine
    /// (0..1) for taking a branch through a degree-≥3 junction; the
    /// default 0.5 ≈ a 60° aperture; no branch passes → the walk stops.
    /// EXTRACTION never consumes this (checker E1 prescription A: the ≤3px
    /// gap-bridge alignment gate is an extraction-internal 0.5 constant).
    public var followStrength: Float

    /// The output/traversal side: +1 emits the forward (index-ascending)
    /// side of the attached chain first and spends the point budget there
    /// first; −1 the backward side.
    public var direction: Float

    public var mode: FollowEdgesMode

    public init(
        edgeThreshold: Float = 0.25,
        followStrength: Float = 0.5,
        direction: Float = 1,
        mode: FollowEdgesMode = .streamline
    ) {
        self.edgeThreshold = edgeThreshold
        self.followStrength = followStrength
        self.direction = direction
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

    /// V2 additive (M4-2-01 KD-2): the extracted ridge graph. nil = not yet
    /// extracted — the `.streamline` arm then extracts lazily in-chain (same
    /// pure function, same output). The App carrier injects it per
    /// prefixHash ⊕ threshold so a press walks instead of extracting.
    public var ridges: RidgeGraph?

    public init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
        self.ridges = nil
    }

    /// Value copy with the ridge graph attached (the carrier's return shape;
    /// the field cache itself stays threshold-free — OQ-3/KD-4).
    public func withRidges(_ ridges: RidgeGraph?) -> EdgeMapField {
        var copy = self
        copy.ridges = ridges
        return copy
    }

    public func value(atX x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return values[y * width + x]
    }
}

public enum FollowEdges {

    /// The chain-length fuse (M4-2-01 checker M1: the withdrawn params
    /// field, now an internal constant — the whole-repo grep for the
    /// identifier ends at this file).
    private static let maxPoints = 256

    // KD-2④ pinned resampling constants (AGENTS.md M2-7 note is the registry).
    private static let resampleMinStep = 0.75
    private static let resampleMaxStep = 4.0
    private static let resampleMaxTurn = Double.pi / 4 // 45°

    /// The mode dispatcher (exhaustive — no default; 纪律 7).
    public static func chain(
        seed: MaskPoint, field: EdgeMapField?, params: FollowEdgesParams
    ) -> [MaskPoint] {
        switch params.mode {
        case .streamline: return streamline(seed: seed, field: field, params: params)
        case .snap: return snap(seed: seed, field: field, params: params)
        }
    }

    // MARK: - The V2 walker (pure Swift, deterministic — no RNG anywhere)

    /// Seed (normalized [0,1] over the map's own frame) → the MaskPoint
    /// chain riding the extracted ridge. Empty output = the documented
    /// degrade (no map / no ridge vertex within reach).
    ///
    /// Mechanics (KD-2): attach the seed to the nearest ridge vertex within
    /// 8 px, then walk the graph bidirectionally — along the attached chain,
    /// through junctions (greedy strongest continuation gated by
    /// `followStrength`, ties broken by the branch's first-past-the-junction
    /// vertex in row-major order, first hit wins) and across recorded ≤3px
    /// bridges — emitting curvature-modulated resampled points
    /// (s = 0.75 + (4 − 0.75)·(1 − θ/45°), arc accumulator reset at chain
    /// crossings), capped at `maxPoints`.
    public static func streamline(
        seed: MaskPoint, field: EdgeMapField?, params: FollowEdgesParams
    ) -> [MaskPoint] {
        guard let field, field.width > 1, field.height > 1,
            field.values.count == field.width * field.height
        else { return [] }
        let w = Double(field.width - 1), h = Double(field.height - 1)
        let seedPixel = SIMD2(Double(seed.x), Double(seed.y)) * SIMD2(w, h)
        let threshold = Double(params.edgeThreshold)

        // The ridge graph: a threshold-matched injected carrier, else lazy
        // in-chain extraction (E1 prescription A: extraction consumes
        // (field, edgeThreshold) only — same field, same threshold, same
        // graph, byte for byte).
        let graph: RidgeGraph
        if let ridges = field.ridges, ridges.high == params.edgeThreshold {
            graph = ridges
        } else {
            graph = RidgeExtract.graph(from: field, high: params.edgeThreshold)
        }

        // Seed attach (KD-2①): the nearest ridge vertex within 8 px
        // (snapTarget-family geometry; tie-break = distance² → row-major).
        // No hit → the V1-verbatim degrade: strongest neighbor via
        // snapTarget (8 px, threshold gate), then a RE-ATTACH within the
        // same 8 px of the snapped point (checker M2); both paths empty →
        // the empty-chain degrade.
        var attach = nearestVertex(graph, around: seedPixel, radius: 8)
        if attach == nil,
            let snapped = snapTarget(field, around: seedPixel, radius: 8, threshold: threshold) {
            attach = nearestVertex(graph, around: snapped, radius: 8)
        }
        guard let (startChain, startVertex) = attach else { return [] }

        let attachPos = graph.chains[startChain].vertices[startVertex]
        var forward: [SIMD2<Double>] = []
        var backward: [SIMD2<Double>] = []
        var budget = maxPoints - 1
        // The first-output side spends the budget first (KD-2② direction).
        if params.direction >= 0 {
            walk(graph, from: (startChain, startVertex), sense: 1,
                 gate: gateValue(params), into: &forward, budget: &budget)
            walk(graph, from: (startChain, startVertex), sense: -1,
                 gate: gateValue(params), into: &backward, budget: &budget)
        } else {
            walk(graph, from: (startChain, startVertex), sense: -1,
                 gate: gateValue(params), into: &backward, budget: &budget)
            walk(graph, from: (startChain, startVertex), sense: 1,
                 gate: gateValue(params), into: &forward, budget: &budget)
        }
        var out = [attachPos]
        out.append(contentsOf: params.direction >= 0 ? forward : backward)
        out.append(contentsOf: params.direction >= 0 ? backward : forward)
        return out.map { MaskPoint(x: Float($0.x / w), y: Float($0.y / h)) }
    }

    private static func gateValue(_ params: FollowEdgesParams) -> Double {
        Double(max(0, min(1, params.followStrength)))
    }

    /// One direction of the graph walk: consumes the vertex stream from
    /// `(chain, vertex)` toward `sense`, crossing junctions/bridges, and
    /// emits adaptively spaced points (never the start vertex itself).
    private static func walk(
        _ graph: RidgeGraph, from start: (chain: Int, vertex: Int), sense initialSense: Int,
        gate: Double, into out: inout [SIMD2<Double>], budget: inout Int
    ) {
        var chain = start.chain
        var index = start.vertex
        var sense = initialSense
        var lastPos = graph.chains[chain].vertices[index]
        var arrival: SIMD2<Double>? = nil // the direction INTO lastPos
        // The arc accumulator: distance until the next emission. At the
        // attach vertex θ is unknown → the straight-run spacing.
        var deficit = resampleStep(turnAngle: 0)
        var spacing = resampleStep(turnAngle: 0)
        var steps = 0
        let stepGuard = maxPoints * 8 // traversal safety fuse
        while budget > 0 {
            guard steps < stepGuard else { return }
            steps += 1

            // Advance the cursor one vertex along the traversal.
            let vertices = graph.chains[chain].vertices
            let nextIndex = index + sense
            let crossed: Bool
            var nextPos: SIMD2<Double>
            if nextIndex >= 0, nextIndex < vertices.count {
                index = nextIndex
                nextPos = vertices[index]
                crossed = false
            } else {
                // Chain end: bridge / junction continuation / free end.
                let end = sense > 0 ? 1 : 0
                guard let continuation = continuationFrom(graph, chain: chain, end: end, gate: gate)
                else { return }
                chain = continuation.chain
                let nextVertices = graph.chains[chain].vertices
                index = continuation.end == 1 ? nextVertices.count - 1 : 0
                sense = continuation.end == 1 ? -1 : 1
                // 弧长累计清零 (KD-2④): the accumulator resets at crossings.
                spacing = resampleStep(turnAngle: 0)
                deficit = spacing
                crossed = true
                continue
            }

            let seg = nextPos - lastPos
            let segLen = (seg.x * seg.x + seg.y * seg.y).squareRoot()
            if segLen > 1e-9 {
                let dir = seg / segLen
                // The spacing is set by the turn at the segment's start
                // vertex (θ = 0 until a direction change is observed).
                if !crossed, let a = arrival {
                    let cosTurn = max(-1.0, min(1.0, a.x * dir.x + a.y * dir.y))
                    spacing = resampleStep(turnAngle: acos(cosTurn))
                }
                var t = 0.0
                while deficit <= segLen - t, budget > 0 {
                    t += deficit
                    out.append(lastPos + dir * t)
                    budget -= 1
                    deficit = spacing
                }
                deficit -= segLen - t
                arrival = dir
            }
            lastPos = nextPos
        }
    }

    /// The continuation at a chain end: a recorded bridge (alignment-gated
    /// at extraction — crossed ungated), else the junction's greedy
    /// strongest branch with cosine ≥ `gate` (checker M3: candidates
    /// enumerated by their first-past-the-junction vertex in row-major
    /// order, argmax first-hit wins). None → nil (the walk stops).
    private static func continuationFrom(
        _ graph: RidgeGraph, chain: Int, end: Int, gate: Double
    ) -> (chain: Int, end: Int)? {
        let key = ChainEndKey(chain: chain, end: end)
        if let bridged = graph.bridgeByEnd[key] {
            return (bridged.chain, bridged.end)
        }
        guard let ji = graph.junctionByEnd[key] else { return nil }
        let junction = graph.junctions[ji]
        guard let arrivalDir = RidgeExtract.outwardTangent(
            graph.chains[chain].vertices, end: end)
        else { return nil }
        struct Candidate {
            var chain: Int
            var end: Int
            var cos: Double
            var order: (Int, Int, Int)
        }
        var candidates: [Candidate] = []
        for att in junction.attachments where !(att.chain == chain && att.end == end) {
            let leaving = RidgeExtract.outwardTangent(graph.chains[att.chain].vertices, end: att.end)
            let leavingDir = leaving.map { SIMD2(-$0.x, -$0.y) } ?? SIMD2(0.0, 0.0)
            let cos = arrivalDir.x * leavingDir.x + arrivalDir.y * leavingDir.y
            guard cos >= gate else { continue }
            // M3 enumeration order: the branch's first vertex past the
            // junction, row-major (y, then x); single-vertex branches order
            // at the junction itself.
            let branch = graph.chains[att.chain].vertices
            let first: SIMD2<Double>
            if branch.count >= 2 {
                first = att.end == 1 ? branch[branch.count - 2] : branch[1]
            } else {
                first = junction.position
            }
            candidates.append(Candidate(
                chain: att.chain, end: att.end, cos: cos,
                order: (Int(first.y.rounded()), Int(first.x.rounded()), att.chain)))
        }
        candidates.sort { $0.order < $1.order }
        var best: Candidate?
        for candidate in candidates {
            if best == nil || candidate.cos > best!.cos { best = candidate }
        }
        guard let winner = best else { return nil }
        return (winner.chain, winner.end)
    }

    /// The nearest graph vertex within `radius` px of `around`
    /// (tie-break = distance² → row-major y/x — KD-2①).
    private static func nearestVertex(
        _ graph: RidgeGraph, around p: SIMD2<Double>, radius: Double
    ) -> (chain: Int, vertex: Int)? {
        var best: (chain: Int, vertex: Int, dist2: Double)? = nil
        for (ci, chain) in graph.chains.enumerated() {
            for (vi, v) in chain.vertices.enumerated() {
                let d = v - p
                let dist2 = d.x * d.x + d.y * d.y
                guard dist2 <= radius * radius else { continue }
                let better: Bool
                if let b = best {
                    if dist2 < b.dist2 {
                        better = true
                    } else if dist2 == b.dist2 {
                        let bv = graph.chains[b.chain].vertices[b.vertex]
                        better = (v.y, v.x) < (bv.y, bv.x)
                    } else {
                        better = false
                    }
                } else {
                    better = true
                }
                if better { best = (ci, vi, dist2) }
            }
        }
        guard let b = best else { return nil }
        return (b.chain, b.vertex)
    }

    /// s = s_min + (s_max − s_min)·(1 − min(θ, θ_max)/θ_max) — straight
    /// runs emit sparsely, bends densify (KD-2④).
    private static func resampleStep(turnAngle θ: Double) -> Double {
        let t = min(max(θ, 0), resampleMaxTurn) / resampleMaxTurn
        return resampleMinStep + (resampleMaxStep - resampleMinStep) * (1 - t)
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
