import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Ridge extraction (Plan M4-2-01 T1, KD-1; OQ-1-A) — the V2 PRE-EXTRACTOR:
// the edge-map magnitude field → a topology-connected set of subpixel ridge
// polylines (`RidgeGraph`). This is the classic Canny back half the V1 walker
// lacked (RESEARCH §1.2 ②③): light Gaussian → central-difference gradient →
// NMS along the gradient (asymmetric tie-break) → hysteresis (high = the
// user's `edgeThreshold`, low = r·high) → row-major 8-connected linking with
// ≤3px gap bridging + junction recording → per-vertex subpixel centroid.
//
// PURE-FUNCTION CONTRACT (checker E1 prescription A): extraction consumes
// (field, high) ONLY — no user strength parameter ever reaches this file.
// Same field + same threshold → byte-identical graph (determinism: row-major
// scans, argmax first-hit, explicit tie-breaks, no RNG, no time input).
//
// All CPU, O(N) over the ≤512 working field — zero Metal (the `mask_edge_map`
// kernel is the untouched upstream data source; zero new kernels/PSOs, OQ-2-A).
// Steger-style reference math deliberately LIVES OUT (test-file-only A/B leg).
// ─────────────────────────────────────────────────────────────────────────────

/// One extracted ridge polyline: subpixel vertices on the EdgeMapField's own
/// pixel grid (field-domain px coordinates — no normalization conversion).
public struct RidgeChain: Sendable, Equatable {
    public var vertices: [SIMD2<Double>]

    public init(vertices: [SIMD2<Double>]) {
        self.vertices = vertices
    }
}

/// A degree-≥3 link node: the chains meeting here (chain index + which end —
/// 0 = `vertices.first` side, 1 = `vertices.last` side).
public struct RidgeJunction: Sendable, Equatable {
    public struct Attachment: Sendable, Equatable {
        public var chain: Int
        public var end: Int

        public init(chain: Int, end: Int) {
            self.chain = chain
            self.end = end
        }
    }

    /// Field-domain position (refined — the junction pixel's centroid).
    public var position: SIMD2<Double>
    public var attachments: [Attachment]

    public init(position: SIMD2<Double>, attachments: [Attachment]) {
        self.position = position
        self.attachments = attachments
    }
}

/// A recorded ≤3px gap bridge between two free chain ends (the extraction-time
/// alignment gate already passed — the walker crosses without re-gating).
public struct RidgeBridge: Sendable, Equatable {
    public var chainA: Int
    public var endA: Int
    public var chainB: Int
    public var endB: Int

    public init(chainA: Int, endA: Int, chainB: Int, endB: Int) {
        self.chainA = chainA
        self.endA = endA
        self.chainB = chainB
        self.endB = endB
    }
}

/// A hashable (chain, end) key — end 0 = `vertices.first` side, 1 = `.last`.
struct ChainEndKey: Hashable, Sendable {
    var chain: Int
    var end: Int
}

/// The extracted ridge network (KD-1 type face). `high` stamps the hysteresis
/// threshold the graph was extracted at — the walker refuses injected graphs
/// whose stamp mismatches its own threshold (stale-carrier guard).
public struct RidgeGraph: Sendable, Equatable {
    public var chains: [RidgeChain]
    public var junctions: [RidgeJunction]
    public var bridges: [RidgeBridge]
    public var high: Float

    /// (chain, end) → junction index (internal walker lookup).
    var junctionByEnd: [ChainEndKey: Int] = [:]
    /// (chain, end) → bridged (chain, end) (internal walker lookup).
    var bridgeByEnd: [ChainEndKey: ChainEndKey] = [:]

    public init(
        chains: [RidgeChain] = [], junctions: [RidgeJunction] = [],
        bridges: [RidgeBridge] = [], high: Float = 0
    ) {
        self.chains = chains
        self.junctions = junctions
        self.bridges = bridges
        self.high = high
    }

    var isEmpty: Bool { chains.isEmpty }
}

public enum RidgeExtract {

    // ── KD-1 pinned constants (the single registry = AGENTS.md M2-7 note) ──

    /// Light Gaussian σ (stabilizes the centroid + curvature on the ≤512
    /// downsampled field — mechanism ④).
    static let gaussianSigma = 0.9
    /// Kernel radius = ceil(3σ) → 7 taps.
    static let gaussianRadius = 3
    /// Hysteresis ratio: low = r × high.
    static let hysteresisRatio = 0.4
    /// Bridge gap bound B (px).
    static let bridgeMaxGap = 3.0
    /// Bridge direction-alignment gate (cosine) — an EXTRACTION-PHASE INTERNAL
    /// constant (checker E1 prescription A; same value as followStrength's
    /// default is an alignment choice, NOT a shared consumption).
    static let bridgeAlignmentGate = 0.5
    /// Centroid profile half-window (±2 taps along the normal).
    static let centroidHalfWindow = 2
    /// Centroid Σw < ε → zero shift.
    static let centroidEpsilon = 1e-6
    /// Centroid shift clamp (px).
    static let centroidMaxShift = 1.5
    /// Structure-tensor window radius for the NMS/centroid ORIENTATION field.
    /// The magnitude ridge's own per-pixel gradient VANISHES at crest pixels
    /// (symmetric local max) — the across-ridge direction comes from the
    /// dominant gradient orientation of the ±radius neighborhood (outer-product
    /// smoothed central differences; still "central difference, smoothed field"
    /// per KD-1② — the orientation is its tensor-dominant reading).
    static let orientationRadius = 2

    /// The pipeline entry: field + hysteresis high → the ridge graph.
    /// Degenerate fields yield the empty graph (never traps).
    ///
    /// Threshold continuity (M4-2-01 DECISIONS): the hysteresis low/high
    /// gates read the RAW field values — the same quantity the V1 walk
    /// thresholded — because the σ0.9 smoothing costs ~33% amplitude on
    /// 1-2px ridges (a 0.354 Sobel step ridge would drop below the default
    /// 0.25 high and vanish). The NMS geometry and the centroid profile
    /// stay on the smoothed field (position quality).
    public static func graph(from field: EdgeMapField, high: Float) -> RidgeGraph {
        let w = field.width, h = field.height
        guard w > 1, h > 1, field.values.count == w * h else {
            return RidgeGraph(high: high)
        }
        let smoothed = gaussianSmooth(field)
        let gradient = gradients(of: smoothed, width: w, height: h)
        let orientation = orientations(of: gradient, width: w, height: h)
        let candidates = nmsCandidates(
            smoothed: smoothed, raw: field.values, orientation: orientation,
            width: w, height: h, low: Double(high) * hysteresisRatio)
        let domain = hysteresis(
            candidates: candidates, raw: field.values, width: w, height: h,
            high: Double(high))
        var graph = link(domain: domain, width: w, height: h, high: high)
        // Junction pixels keep their integer positions: the ±2 centroid
        // window at a crossing mixes several branches' mass, so the 1D
        // profile there is not a ridge — refining it would shift the
        // topology nodes and smear the walk's branch tangents.
        var junctionPixels = Set<Int>()
        for junction in graph.junctions {
            let x = Int(junction.position.x.rounded()), y = Int(junction.position.y.rounded())
            junctionPixels.insert(y * w + x)
        }
        refineCentroids(
            &graph, smoothed: smoothed, orientation: orientation, width: w, height: h,
            low: Double(high) * hysteresisRatio, skipPixels: junctionPixels)
        buildLookups(&graph)
        return graph
    }

    // MARK: - Stage ①: light Gaussian (separable 7-tap, clamp border, rows first)

    /// σ=0.9 separable Gaussian; horizontal pass then vertical pass (pinned
    /// order — determinism), edge-clamped.
    static func gaussianSmooth(_ field: EdgeMapField) -> [Double] {
        let w = field.width, h = field.height
        let sigma = gaussianSigma, radius = gaussianRadius
        var kernel = [Double](repeating: 0, count: 2 * radius + 1)
        var sum = 0.0
        for i in -radius...radius {
            let v = exp(-Double(i * i) / (2 * sigma * sigma))
            kernel[i + radius] = v
            sum += v
        }
        for i in kernel.indices { kernel[i] /= sum }

        var temp = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc = 0.0
                for i in -radius...radius {
                    let cx = min(max(x + i, 0), w - 1)
                    acc += Double(field.values[y * w + cx]) * kernel[i + radius]
                }
                temp[y * w + x] = acc
            }
        }
        var out = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc = 0.0
                for i in -radius...radius {
                    let cy = min(max(y + i, 0), h - 1)
                    acc += temp[cy * w + x] * kernel[i + radius]
                }
                out[y * w + x] = acc
            }
        }
        return out
    }

    // MARK: - Stage ②: central-difference gradient (clamped coordinates)

    struct Gradient {
        var gx: Double
        var gy: Double
        var magnitude: Double
    }

    static func gradients(of s: [Double], width w: Int, height h: Int) -> [Gradient] {
        var out = [Gradient](repeating: Gradient(gx: 0, gy: 0, magnitude: 0), count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let x0 = max(x - 1, 0), x1 = min(x + 1, w - 1)
                let y0 = max(y - 1, 0), y1 = min(y + 1, h - 1)
                let gx = (s[y * w + x1] - s[y * w + x0]) / 2
                let gy = (s[y1 * w + x] - s[y0 * w + x]) / 2
                out[y * w + x] = Gradient(
                    gx: gx, gy: gy, magnitude: (gx * gx + gy * gy).squareRoot())
            }
        }
        return out
    }

    /// Bilinear sample with clamped coordinates (the NMS flank reader).
    static func bilinear(_ s: [Double], width w: Int, height h: Int, _ p: SIMD2<Double>) -> Double {
        let cx = min(max(p.x, 0), Double(w - 1))
        let cy = min(max(p.y, 0), Double(h - 1))
        let x0 = Int(cx.rounded(.down)), y0 = Int(cy.rounded(.down))
        let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
        let fx = cx - Double(x0), fy = cy - Double(y0)
        let v00 = s[y0 * w + x0], v10 = s[y0 * w + x1]
        let v01 = s[y1 * w + x0], v11 = s[y1 * w + x1]
        return v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy)
            + v01 * (1 - fx) * fy + v11 * fx * fy
    }

    // MARK: - Stage ②b: the orientation field (structure-tensor dominant direction)

    /// Per pixel: the dominant gradient orientation over the ±`orientationRadius`
    /// window — θ = ½·atan2(2b, a−c) of the outer-product sums of the central
    /// differences. Sign-normalized (first non-zero component positive) so the
    /// NMS strict side is deterministic.
    static func orientations(
        of g: [Gradient], width w: Int, height h: Int
    ) -> [SIMD2<Double>] {
        let r = orientationRadius
        var out = [SIMD2<Double>](repeating: SIMD2(1, 0), count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var a = 0.0, b = 0.0, c = 0.0
                for dy in -r...r {
                    let cy = min(max(y + dy, 0), h - 1)
                    for dx in -r...r {
                        let cx = min(max(x + dx, 0), w - 1)
                        let grad = g[cy * w + cx]
                        a += grad.gx * grad.gx
                        b += grad.gx * grad.gy
                        c += grad.gy * grad.gy
                    }
                }
                let theta = 0.5 * atan2(2 * b, a - c)
                var e = SIMD2(cos(theta), sin(theta))
                if e.x < 0 || (e.x == 0 && e.y < 0) { e = -e }
                out[y * w + x] = e
            }
        }
        return out
    }

    // MARK: - Stage ③: NMS along the orientation (asymmetric tie)

    /// NMS survivor mask: keep p iff S(p) > S(p+e) && S(p) >= S(p−e) with
    /// e = the structure-tensor orientation (the pinned asymmetric tie-break —
    /// deterministic); candidates = survivors whose RAW field value clears
    /// `low` (threshold continuity — see `graph`).
    static func nmsCandidates(
        smoothed s: [Double], raw: [Float], orientation o: [SIMD2<Double>],
        width w: Int, height h: Int, low: Double
    ) -> [Bool] {
        var keep = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                guard Double(raw[idx]) >= low else { continue }
                let e = o[idx]
                let p = SIMD2(Double(x), Double(y))
                let sPlus = bilinear(s, width: w, height: h, p + e)
                let sMinus = bilinear(s, width: w, height: h, p - e)
                if s[idx] > sPlus && s[idx] >= sMinus { keep[idx] = true }
            }
        }
        return keep
    }

    // MARK: - Stage ④: hysteresis (strong seeds row-major → 8-connected growth)

    /// Strong points (raw value ≥ high, row-major seeds) grow 8-connected
    /// through the candidate set; the reached candidates form the link domain.
    static func hysteresis(
        candidates c: [Bool], raw: [Float], width w: Int, height h: Int,
        high: Double
    ) -> [Bool] {
        var domain = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for y in 0..<h { // row-major seeding
            for x in 0..<w {
                let idx = y * w + x
                if c[idx], Double(raw[idx]) >= high { stack.append(idx) }
            }
        }
        var seen = [Bool](repeating: false, count: w * h)
        while let idx = stack.popLast() {
            guard !seen[idx] else { continue }
            seen[idx] = true
            domain[idx] = true
            let x = idx % w, y = idx / w
            for dy in -1...1 {
                for dx in -1...1 {
                    guard dx != 0 || dy != 0 else { continue }
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let nIdx = ny * w + nx
                    if c[nIdx], !seen[nIdx] { stack.append(nIdx) }
                }
            }
        }
        return domain
    }

    // MARK: - Stage ⑤: linking (endpoints/junctions row-major → chains) + bridging

    /// The 8 neighbors in fixed row-major-ish scan order (determinism).
    static let neighborOrder: [(dx: Int, dy: Int)] = [
        (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1),
    ]

    private struct LinkState {
        var domain: [Bool]
        var width: Int
        var height: Int
        var visited: [Bool]
        var isJunction: [Bool]
        var degree: [Int]

        func contains(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && domain[y * width + x]
        }
    }

    /// Trace the domain into chains + junctions, then bridge ≤3px gaps.
    static func link(domain: [Bool], width w: Int, height h: Int, high: Float) -> RidgeGraph {
        var state = LinkState(
            domain: domain, width: w, height: h,
            visited: [Bool](repeating: false, count: w * h),
            isJunction: [Bool](repeating: false, count: w * h),
            degree: [Int](repeating: 0, count: w * h))
        for y in 0..<h {
            for x in 0..<w {
                guard domain[y * w + x] else { continue }
                var deg = 0
                for n in neighborOrder where state.contains(x + n.dx, y + n.dy) { deg += 1 }
                state.degree[y * w + x] = deg
                state.isJunction[y * w + x] = deg >= 3
            }
        }

        var chains: [[SIMD2<Double>]] = []
        // junction index per pixel (-1 = none); junctions accumulate attachments
        var junctionIndexAt = [Int](repeating: -1, count: w * h)
        var junctions: [(position: SIMD2<Int>, attachments: [RidgeJunction.Attachment])] = []

        func noteJunction(_ x: Int, _ y: Int, chain: Int, end: Int) {
            let idx = y * w + x
            if junctionIndexAt[idx] < 0 {
                junctionIndexAt[idx] = junctions.count
                junctions.append((SIMD2(x, y), []))
            }
            junctions[junctionIndexAt[idx]].attachments
                .append(RidgeJunction.Attachment(chain: chain, end: end))
        }

        /// Walk from `current` (already in chain) toward `next`; append until a
        /// junction (appended + recorded, even when a previous trace already
        /// claimed the junction pixel — every arriving chain must attach) /
        /// visited non-junction pixel (cycle closure, stop) / dead end (stop).
        func trace(_ chain: inout [SIMD2<Double>], prev: SIMD2<Int>, next: SIMD2<Int>) {
            var previous = prev
            var current = next
            chain.append(SIMD2(Double(current.x), Double(current.y)))
            state.visited[current.y * w + current.x] = true
            while true {
                let cIdx = current.y * w + current.x
                if state.isJunction[cIdx] {
                    noteJunction(current.x, current.y, chain: chains.count, end: 1)
                    return
                }
                var nextPixel: SIMD2<Int>?
                for n in neighborOrder {
                    let nx = current.x + n.dx, ny = current.y + n.dy
                    guard state.contains(nx, ny) else { continue }
                    let candidate = SIMD2(nx, ny)
                    guard candidate != previous else { continue }
                    nextPixel = candidate
                    break
                }
                guard let onward = nextPixel else { return }
                if state.visited[onward.y * w + onward.x] {
                    if state.isJunction[onward.y * w + onward.x] {
                        // Shared junction: append + attach this chain too.
                        chain.append(SIMD2(Double(onward.x), Double(onward.y)))
                        noteJunction(onward.x, onward.y, chain: chains.count, end: 1)
                    }
                    return
                }
                previous = current
                current = onward
                chain.append(SIMD2(Double(current.x), Double(current.y)))
                state.visited[current.y * w + current.x] = true
            }
        }

        // Pass 1: endpoints (degree ≤ 1) row-major — chains anchored at free ends.
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                guard domain[idx], !state.visited[idx], !state.isJunction[idx],
                    state.degree[idx] <= 1
                else { continue }
                state.visited[idx] = true
                var chain = [SIMD2(Double(x), Double(y))]
                if state.degree[idx] == 0 {
                    chains.append(chain) // isolated pixel: its own chain
                    continue
                }
                for n in neighborOrder {
                    let nx = x + n.dx, ny = y + n.dy
                    guard state.contains(nx, ny) else { continue }
                    if state.isJunction[ny * w + nx] {
                        chain.append(SIMD2(Double(nx), Double(ny)))
                        noteJunction(nx, ny, chain: chains.count, end: 1)
                    } else {
                        trace(&chain, prev: SIMD2(x, y), next: SIMD2(nx, ny))
                    }
                    break
                }
                chains.append(chain)
            }
        }

        // Pass 2: junction-adjacent segments (row-major junctions, fixed
        // neighbor order) + once-per-pair junction↔junction chains.
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                guard domain[idx], state.isJunction[idx] else { continue }
                for n in neighborOrder {
                    let nx = x + n.dx, ny = y + n.dy
                    guard state.contains(nx, ny) else { continue }
                    let nIdx = ny * w + nx
                    if state.isJunction[nIdx] {
                        // Emit each junction↔junction pair once (row-major order).
                        if idx < nIdx {
                            let chain = [
                                SIMD2(Double(x), Double(y)), SIMD2(Double(nx), Double(ny)),
                            ]
                            noteJunction(x, y, chain: chains.count, end: 0)
                            noteJunction(nx, ny, chain: chains.count, end: 1)
                            chains.append(chain)
                        }
                        continue
                    }
                    guard !state.visited[nIdx] else { continue }
                    var chain = [SIMD2(Double(x), Double(y))]
                    noteJunction(x, y, chain: chains.count, end: 0)
                    trace(&chain, prev: SIMD2(x, y), next: SIMD2(nx, ny))
                    chains.append(chain)
                }
            }
        }

        // Pass 3: closed loops (all remaining degree-2 cycles), row-major start.
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                guard domain[idx], !state.visited[idx], !state.isJunction[idx] else { continue }
                state.visited[idx] = true
                var chain = [SIMD2(Double(x), Double(y))]
                for n in neighborOrder {
                    let nx = x + n.dx, ny = y + n.dy
                    guard state.contains(nx, ny), !state.visited[ny * w + nx] else { continue }
                    trace(&chain, prev: SIMD2(x, y), next: SIMD2(nx, ny))
                    break
                }
                chains.append(chain)
            }
        }

        // Bridging: free ends (no junction attachment), gap ≤ B, both sides
        // aligned (cosine ≥ the extraction-internal gate) — the pure pairing
        // pass (testable directly; the σ0.9 smoothing already merges small
        // straight gaps, so real bridges fire on fragmented/curved domains).
        var junctionAttached = Set<ChainEndKey>()
        for junction in junctions {
            for att in junction.attachments {
                junctionAttached.insert(ChainEndKey(chain: att.chain, end: att.end))
            }
        }
        let bridges = pairBridges(
            chains: chains.map { RidgeChain(vertices: $0) }, junctionAttached: junctionAttached)

        var graph = RidgeGraph(high: high)
        graph.chains = chains.map { RidgeChain(vertices: $0) }
        graph.junctions = junctions.map {
            RidgeJunction(
                position: SIMD2(Double($0.position.x), Double($0.position.y)),
                attachments: $0.attachments)
        }
        graph.bridges = bridges
        return graph
    }

    /// The outward unit tangent at a chain end (nil for single-vertex chains
    /// and degenerate segments) — shared with the walker's junction cosine.
    static func outwardTangent(_ vertices: [SIMD2<Double>], end: Int) -> SIMD2<Double>? {
        guard vertices.count >= 2 else { return nil }
        let v = end == 1
            ? vertices[vertices.count - 1] - vertices[vertices.count - 2]
            : vertices[0] - vertices[1]
        let length = (v.x * v.x + v.y * v.y).squareRoot()
        guard length > 1e-9 else { return nil }
        return v / length
    }

    /// Free-end bridge pairing (pure): candidate pairs of non-junction-attached
    /// chain ends within `bridgeMaxGap` px whose outward tangents BOTH point
    /// into the gap (cosine ≥ `bridgeAlignmentGate` on each side — the pinned
    /// extraction-internal constant). Greedy nearest-first with the pinned
    /// tie-break = distance² → row-major (a row, a col, b row, b col); each
    /// end bridges at most once. Single-vertex ends have no tangent → skipped.
    static func pairBridges(
        chains: [RidgeChain], junctionAttached: Set<ChainEndKey>
    ) -> [RidgeBridge] {
        struct EndRef {
            var chain: Int
            var end: Int
            var position: SIMD2<Int>
            var tangent: SIMD2<Double>?
        }
        var freeEnds: [EndRef] = []
        for (ci, chain) in chains.enumerated() {
            for end in 0...1 {
                guard !junctionAttached.contains(ChainEndKey(chain: ci, end: end)) else {
                    continue
                }
                let pos: SIMD2<Int> = end == 1
                    ? SIMD2(Int(chain.vertices[chain.vertices.count - 1].x.rounded()),
                            Int(chain.vertices[chain.vertices.count - 1].y.rounded()))
                    : SIMD2(Int(chain.vertices[0].x.rounded()), Int(chain.vertices[0].y.rounded()))
                freeEnds.append(
                    EndRef(chain: ci, end: end, position: pos,
                           tangent: outwardTangent(chain.vertices, end: end)))            }
        }
        struct Pair {
            var a: Int
            var b: Int
            var dist2: Double
        }
        var pairs: [Pair] = []
        for i in 0..<freeEnds.count {
            for j in (i + 1)..<freeEnds.count {
                let a = freeEnds[i], b = freeEnds[j]
                let d = SIMD2(Double(b.position.x - a.position.x), Double(b.position.y - a.position.y))
                let dist2 = d.x * d.x + d.y * d.y
                guard dist2 <= bridgeMaxGap * bridgeMaxGap else { continue }
                guard let ta = a.tangent, let tb = b.tangent else { continue }
                let len = dist2.squareRoot()
                guard len > 1e-9 else { continue }
                let dir = d / len
                // Both chains must point INTO the gap (collinear continuation).
                let cosA = ta.x * dir.x + ta.y * dir.y
                let cosB = -(tb.x * dir.x + tb.y * dir.y)
                guard cosA >= bridgeAlignmentGate, cosB >= bridgeAlignmentGate else { continue }
                pairs.append(Pair(a: i, b: j, dist2: dist2))
            }
        }
        pairs.sort {
            if $0.dist2 != $1.dist2 { return $0.dist2 < $1.dist2 }
            let pa = freeEnds[$0.a].position, pb = freeEnds[$0.b].position
            let qa = freeEnds[$1.a].position, qb = freeEnds[$1.b].position
            if pa.y != qa.y { return pa.y < qa.y }
            if pa.x != qa.x { return pa.x < qa.x }
            if pb.y != qb.y { return pb.y < qb.y }
            return pb.x < qb.x
        }
        var bridged = Set<Int>()
        var bridges: [RidgeBridge] = []
        for pair in pairs {
            guard !bridged.contains(pair.a), !bridged.contains(pair.b) else { continue }
            bridged.insert(pair.a)
            bridged.insert(pair.b)
            let a = freeEnds[pair.a], b = freeEnds[pair.b]
            bridges.append(
                RidgeBridge(chainA: a.chain, endA: a.end, chainB: b.chain, endB: b.end))
        }
        return bridges
    }

    // MARK: - Stage ⑥: subpixel centroid refinement (±2 profile along the normal)

    /// Per candidate vertex: profile f_k = bilinear(smoothed, p + k·n),
    /// w_k = max(f_k − low, 0), δ = Σk·w_k / Σw_k (Σw < ε → 0; |δ| ≤ clamp);
    /// refined vertex = p + δ·n (n = the tensor orientation at the vertex).
    /// `skipPixels` (junction pixels) keep their integer positions. Junction
    /// positions follow their first attachment's vertex.
    static func refineCentroids(
        _ graph: inout RidgeGraph, smoothed s: [Double], orientation o: [SIMD2<Double>],
        width w: Int, height h: Int, low: Double, skipPixels: Set<Int> = []
    ) {
        func refineVertex(_ p: SIMD2<Double>) -> SIMD2<Double> {
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            guard x >= 0, y >= 0, x < w, y < h else { return p }
            guard !skipPixels.contains(y * w + x) else { return p }
            let n = o[y * w + x]
            var sumKW = 0.0, sumW = 0.0
            for k in -centroidHalfWindow...centroidHalfWindow {
                let f = bilinear(s, width: w, height: h, p + SIMD2(Double(k) * n.x, Double(k) * n.y))
                let weight = max(f - low, 0)
                sumKW += Double(k) * weight
                sumW += weight
            }
            guard sumW >= centroidEpsilon else { return p }
            var delta = sumKW / sumW
            if !delta.isFinite { return p }
            delta = min(max(delta, -centroidMaxShift), centroidMaxShift)
            return p + delta * n
        }
        for ci in graph.chains.indices {
            graph.chains[ci].vertices = graph.chains[ci].vertices.map(refineVertex)
        }
        for ji in graph.junctions.indices {
            if let first = graph.junctions[ji].attachments.first,
                first.chain < graph.chains.count {
                let chain = graph.chains[first.chain]
                let vertex: SIMD2<Double>? = first.end == 1
                    ? chain.vertices.last : chain.vertices.first
                if let vertex { graph.junctions[ji].position = vertex }
            }
        }
    }

    static func buildLookups(_ graph: inout RidgeGraph) {
        var junctionByEnd: [ChainEndKey: Int] = [:]
        for (ji, junction) in graph.junctions.enumerated() {
            for att in junction.attachments {
                junctionByEnd[ChainEndKey(chain: att.chain, end: att.end)] = ji
            }
        }
        var bridgeByEnd: [ChainEndKey: ChainEndKey] = [:]
        for bridge in graph.bridges {
            bridgeByEnd[ChainEndKey(chain: bridge.chainA, end: bridge.endA)] =
                ChainEndKey(chain: bridge.chainB, end: bridge.endB)
            bridgeByEnd[ChainEndKey(chain: bridge.chainB, end: bridge.endB)] =
                ChainEndKey(chain: bridge.chainA, end: bridge.endA)
        }
        graph.junctionByEnd = junctionByEnd
        graph.bridgeByEnd = bridgeByEnd
    }
}
