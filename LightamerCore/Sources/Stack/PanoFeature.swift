import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PanoFeature (Plan M5-3-01 T1; KD-1) — the panorama feature segment: preview
// gray preparation, the DoG multi-scale keypoint detector, and the 128-dim
// oriented-gradient descriptor (SIFT semantics, zero-dependency
// self-implementation). Pure CPU, sequential, deterministic (G1's anchor).
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the FEATURE-SEGMENT PARAMETERS: the ≤1200px preview cap
// (merge.py:215 `small(im, 1200)`), the 6000-feature budget (merge.py:219
// `SIFT_create(nfeatures=6000)`), the seed-121 determinism anchor (merge.py
// :220, consumed by `PanoMatch.PanoRNG`), the <10-feature typed failure
// (merge.py:223-224), and the low-contrast-terrain rationale for a
// SIFT-class detector over ORB (merge.py:217-218). Swift rewrite; the
// constants are Lumen's values transplanted verbatim. OpenCV itself NEVER
// enters this repository (the zero-new-SPM red line).
//
// DOMAIN (KD-1 / OQ-3): the feature chain runs on the sRGB piecewise
// DISPLAY-ENCODED Rec709 luma of float32 [0,1] planes (the Mertens-leg
// convention; `DrtEotfMath.srgbPiecewiseEncode` + the
// `MertensFusion.grayCoefficients` luma weights). The two `preparePreviewGray`
// seams are the checker-minor-2 ruling: the M5-3-02 leg stages
// ALREADY-ENCODED planes, so its seam must skip the encode step — a second
// encode would systematically brighten the frame and drift every threshold.
//
// SCALE BOOKKEEPING (self-consistent, pinned here): Gaussian layer s of
// octave o has sigma σ0·2^(s/S) in OCTAVE-o pixel units; the keypoint's
// reported `sigma` is σ0·2^(o+s/S) — OCTAVE-0 units. Keypoint x/y are
// always OCTAVE-0 (preview) pixel coordinates: x_preview = x_octave·2^o.
// DoG layer d = G[d+1] − G[d]; candidates d ∈ 1...S read their gradients
// from G[d+1] (the finer of the pair) and report σ = σ0·2^(o+(d+1)/S).
//
// CUTS (planner rulings, DECISIONS): sub-pixel refinement is CUT (preview
// domain + the 3px RANSAC threshold — marginal gain); the orientation
// histogram is single-peak (no secondary orientations); histogram
// accumulation is nearest-bin for ORIENTATION and nearest-cell for the
// descriptor's spatial split (the ANGLE splits linearly into its two
// adjacent bins) — no trilinear interpolation anywhere.
// ─────────────────────────────────────────────────────────────────────────────

/// One display-encoded Rec709 luma plane (row-major Float, [0,1]).
public struct PanoGrayPlane: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height, "gray plane size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    subscript(x: Int, y: Int) -> Float {
        pixels[y * width + x]
    }
}

/// One DoG keypoint. `x`/`y` are preview-domain pixel coordinates (the
/// integer grid of the octave, scaled up by 2^octave); `sigma` is absolute
/// (octave-0 units); `orientation` is radians in [0, 2π).
public struct PanoKeypoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let octave: Int
    public let sigma: Double
    public let response: Double
    public let orientation: Double

    public init(
        x: Double, y: Double, octave: Int, sigma: Double,
        response: Double, orientation: Double
    ) {
        self.x = x
        self.y = y
        self.octave = octave
        self.sigma = sigma
        self.response = response
        self.orientation = orientation
    }
}

/// One 128-dim root-normalized descriptor (its `keypointIndex` points into
/// the parallel keypoint array of the same detection run).
public struct PanoDescriptor: Sendable, Equatable {
    public let keypointIndex: Int
    public let vector: [Float]

    public init(keypointIndex: Int, vector: [Float]) {
        precondition(vector.count == Self.dimensions, "descriptor dim mismatch")
        self.keypointIndex = keypointIndex
        self.vector = vector
    }

    /// 4×4 spatial cells × 8 gradient bins.
    public static let dimensions = 128
}

/// The Gaussian/DoG scale space (the detection intermediate, re-runnable).
public struct PanoPyramid: Sendable {
    /// [octave][s] — s ∈ 0..<(S+3) Gaussian layers per octave.
    public let octaves: [[PanoGrayPlane]]
    /// [octave][d] — d ∈ 0..<(S+2) DoG layers per octave.
    public let dogs: [[PanoGrayPlane]]
}

public enum PanoFeature {

    // MARK: - Constants (KD-4: file constants, NOT parameters)

    /// The preview long-edge cap (merge.py:215 anchor).
    public static let previewMaxEdge = 1200
    /// The per-image feature budget (merge.py:219 anchor).
    public static let featureCap = 6000
    /// Below this an image is typed-failed (merge.py:223-224 semantics;
    /// the gate itself lives at the leg/match layer).
    public static let minFeaturesPerImage = 10
    /// DoG intervals per octave (S = 3 → 6 Gaussian layers, 5 DoG layers).
    public static let intervals = 3
    /// The base scale σ0 (the SIFT convention).
    public static let sigma0 = 1.6
    /// The prepared preview's assumed input blur (the box downsample of an
    /// aliased-render source ≈ 0.5px — the SIFT INI_SIGMA convention).
    public static let assumedInputSigma = 0.5
    /// The DoG contrast gate (SIFT's 0.04; scaled by (S+2)/S at use — the
    /// OpenCV threshold semantics in the [0,1] domain).
    public static let contrastThreshold = 0.04
    /// The principal-curvature edge gate r (the SIFT default 10: reject
    /// when tr²/det > (r+1)²/r).
    public static let edgeRatio = 10.0
    /// The descriptor's post-L2 clamp (the SIFT 0.2 convention).
    public static let descriptorClamp = 0.2

    // MARK: - Preview gray preparation (KD-1 tail + checker minor-2 seams)

    /// The LINEAR-input seam: sRGB encode → Rec709 luma → ≤1200px box
    /// downsample (the KD-1 order, verbatim). Feed a linear Rec2020 RGBA
    /// float32 plane here.
    public static func preparePreviewGray(
        rgbaLinear pixels: [Float], width: Int, height: Int
    ) -> PanoGrayPlane {
        prepare(pixels, width: width, height: height, encode: true)
    }

    /// The ALREADY-ENCODED seam (checker minor-2): the M5-3-02 leg stages
    /// display-encoded planes — deriving the preview gray from them MUST
    /// skip the encode step (srgbEncode∘srgbEncode brightens the frame and
    /// drifts the detector thresholds while breaking nothing structurally —
    /// the silent quality defect this split exists to prevent).
    public static func preparePreviewGray(
        rgbaEncoded pixels: [Float], width: Int, height: Int
    ) -> PanoGrayPlane {
        prepare(pixels, width: width, height: height, encode: false)
    }

    private static func prepare(
        _ pixels: [Float], width: Int, height: Int, encode: Bool
    ) -> PanoGrayPlane {
        precondition(pixels.count == width * height * 4, "rgba plane size mismatch")
        let cr = Double(MertensFusion.grayCoefficients.r)
        let cg = Double(MertensFusion.grayCoefficients.g)
        let cb = Double(MertensFusion.grayCoefficients.b)
        var luma = [Float](repeating: 0, count: width * height)
        let count = width * height
        if encode {
            for index in 0..<count {
                let base = index * 4
                let r = DrtEotfMath.srgbPiecewiseEncode(Double(pixels[base]))
                let g = DrtEotfMath.srgbPiecewiseEncode(Double(pixels[base + 1]))
                let b = DrtEotfMath.srgbPiecewiseEncode(Double(pixels[base + 2]))
                luma[index] = Float(cr * r + cg * g + cb * b)
            }
        } else {
            for index in 0..<count {
                let base = index * 4
                luma[index] = Float(
                    cr * Double(pixels[base]) + cg * Double(pixels[base + 1])
                        + cb * Double(pixels[base + 2]))
            }
        }
        return downsample(PanoGrayPlane(width: width, height: height, pixels: luma))
    }

    /// The deterministic integer box downsample (INTER_AREA semantics):
    /// destination pixel (x, y) averages the source rect
    /// [⌊x·w/tw⌋, ⌈(x+1)·w/tw⌉) × [⌊y·h/th⌋, ⌈(y+1)·h/th⌉) — fixed walk
    /// order, Float accumulation, division by the box's pixel count.
    /// Adjacent boxes share one boundary pixel when the boundary lands on a
    /// fractional coordinate (a pinned averaging property, not a tiling).
    private static func downsample(_ gray: PanoGrayPlane) -> PanoGrayPlane {
        let longEdge = max(gray.width, gray.height)
        guard longEdge > previewMaxEdge else { return gray }
        let scale = Double(previewMaxEdge) / Double(longEdge)
        let tw = max(1, Int((Double(gray.width) * scale).rounded()))
        let th = max(1, Int((Double(gray.height) * scale).rounded()))
        var out = [Float](repeating: 0, count: tw * th)
        for y in 0..<th {
            let y0 = y * gray.height / th
            let y1 = min(gray.height, ((y + 1) * gray.height + th - 1) / th)
            for x in 0..<tw {
                let x0 = x * gray.width / tw
                let x1 = min(gray.width, ((x + 1) * gray.width + tw - 1) / tw)
                var sum = Float(0)
                for yy in y0..<y1 {
                    let row = yy * gray.width
                    for xx in x0..<x1 {
                        sum += gray.pixels[row + xx]
                    }
                }
                out[y * tw + x] = sum / Float((y1 - y0) * (x1 - x0))
            }
        }
        return PanoGrayPlane(width: tw, height: th, pixels: out)
    }

    // MARK: - Scale space (KD-1)

    /// The adaptive octave count: floor(log2(minEdge)) − 3, clamped to
    /// [1, 6] — a ≤1200px preview lands 4-6 octaves for realistic edges.
    public static func octaveCount(minEdge: Int) -> Int {
        guard minEdge > 1 else { return 1 }
        var floorLog2 = 0
        var edge = minEdge
        while edge > 1 {
            floorLog2 += 1
            edge >>= 1
        }
        return max(1, min(6, floorLog2 - 3))
    }

    /// Build the Gaussian pyramid + DoG stack. Octave o's layer 0 is the
    /// 2× decimation of octave o−1's layer S (its scale σ0·2^S/S = 2σ0 in
    /// octave-(o−1) units becomes exactly σ0 in octave-o units — no extra
    /// blur); octave 0's layer 0 is blurred from the assumed 0.5 input
    /// blur up to σ0. Layer s > 0 accumulates the incremental blur
    /// √(σ(s)² − σ(s−1)²).
    public static func buildPyramid(_ gray: PanoGrayPlane) -> PanoPyramid {
        let octaveTotal = octaveCount(minEdge: min(gray.width, gray.height))
        let layersPerOctave = intervals + 3
        // The absolute per-layer sigmas in octave units.
        let layerSigma = (0..<layersPerOctave).map {
            sigma0 * pow(2, Double($0) / Double(intervals))
        }
        var octaves: [[PanoGrayPlane]] = []
        octaves.reserveCapacity(octaveTotal)
        let initialBlur = sigma0 * sigma0 - assumedInputSigma * assumedInputSigma
        var current = [blur(gray, sigma: initialBlur > 0 ? sqrt(initialBlur) : 0)]
        for s in 1..<layersPerOctave {
            let inc = sqrt(max(0, layerSigma[s] * layerSigma[s] - layerSigma[s - 1] * layerSigma[s - 1]))
            current.append(blur(current[s - 1], sigma: inc))
        }
        octaves.append(current)
        for _ in 1..<octaveTotal {
            var layers = [decimate2(octaves[octaves.count - 1][intervals])]
            for s in 1..<layersPerOctave {
                let inc = sqrt(max(0, layerSigma[s] * layerSigma[s] - layerSigma[s - 1] * layerSigma[s - 1]))
                layers.append(blur(layers[s - 1], sigma: inc))
            }
            octaves.append(layers)
        }
        var dogs: [[PanoGrayPlane]] = []
        dogs.reserveCapacity(octaves.count)
        for octave in octaves {
            var dogLayers: [PanoGrayPlane] = []
            dogLayers.reserveCapacity(layersPerOctave - 1)
            for d in 0..<(layersPerOctave - 1) {
                let finer = octave[d + 1]
                var pixels = [Float](repeating: 0, count: finer.width * finer.height)
                for index in pixels.indices {
                    pixels[index] = finer.pixels[index] - octave[d].pixels[index]
                }
                dogLayers.append(
                    PanoGrayPlane(width: finer.width, height: finer.height, pixels: pixels))
            }
            dogs.append(dogLayers)
        }
        return PanoPyramid(octaves: octaves, dogs: dogs)
    }

    /// Separable Gaussian blur (edge-replicate, Float accumulation in the
    /// fixed −r...r walk order; kernel = exp(−i²/2σ²) normalized to sum 1).
    private static func blur(_ plane: PanoGrayPlane, sigma: Double) -> PanoGrayPlane {
        guard sigma > 1e-6 else { return plane }
        let radius = max(1, Int((3.0 * sigma).rounded(.up)))
        var kernel = [Double](repeating: 0, count: radius + 1)
        var total = 0.0
        for i in 0...radius {
            let value = exp(-Double(i * i) / (2.0 * sigma * sigma))
            kernel[i] = value
            total += i == 0 ? value : 2 * value
        }
        for i in kernel.indices {
            kernel[i] /= total
        }
        let width = plane.width
        let height = plane.height
        var horizontal = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum = Float(0)
                for i in -radius...radius {
                    let xx = min(max(x + i, 0), width - 1)
                    sum += Float(kernel[Int(abs(i))]) * plane.pixels[row + xx]
                }
                horizontal[row + x] = sum
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum = Float(0)
                for i in -radius...radius {
                    let yy = min(max(y + i, 0), height - 1)
                    sum += Float(kernel[Int(abs(i))]) * horizontal[yy * width + x]
                }
                out[y * width + x] = sum
            }
        }
        return PanoGrayPlane(width: width, height: height, pixels: out)
    }

    /// 2× decimation: out[y][x] = in[2y][2x] (the scale-space downsample).
    private static func decimate2(_ plane: PanoGrayPlane) -> PanoGrayPlane {
        let width = max(1, plane.width / 2)
        let height = max(1, plane.height / 2)
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                out[y * width + x] = plane.pixels[min(2 * y, plane.height - 1) * plane.width
                    + min(2 * x, plane.width - 1)]
            }
        }
        return PanoGrayPlane(width: width, height: height, pixels: out)
    }

    // MARK: - Detection (KD-1)

    /// The DoG detector: 3×3×3 strict-extrema candidates on DoG layers
    /// 1...S, the contrast gate (|DoG| ≥ 0.04·(S+2)/S), the 2×2-Hessian
    /// edge gate (reject when det ≤ 0 or tr² > (r+1)²/r·det), a single-peak
    /// 36-bin orientation, the 6000-response cap. Deterministic end to end.
    public static func detect(_ gray: PanoGrayPlane) -> [PanoKeypoint] {
        detectAndDescribe(gray).keypoints
    }

    /// Detection + description over ONE pyramid build (the matching chain's
    /// entry; the descriptors' `keypointIndex` matches the returned array).
    public static func detectAndDescribe(
        _ gray: PanoGrayPlane
    ) -> (keypoints: [PanoKeypoint], descriptors: [PanoDescriptor]) {
        let pyramid = buildPyramid(gray)
        let contrastGate = contrastThreshold * Double(intervals + 2) / Double(intervals)
        let edgeGate = (edgeRatio + 1) * (edgeRatio + 1) / edgeRatio
        var keypoints: [PanoKeypoint] = []
        for (o, dogOctave) in pyramid.dogs.enumerated() {
            for d in 1...intervals {
                let center = dogOctave[d]
                let below = dogOctave[d - 1]
                let above = dogOctave[d + 1]
                let width = center.width
                let height = center.height
                guard width >= 3, height >= 3 else { continue }
                let relativeScale = Double(d + 1) / Double(intervals)
                let sigmaLocal = sigma0 * pow(2, relativeScale)
                for y in 1..<(height - 1) {
                    for x in 1..<(width - 1) {
                        let value = Double(center.pixels[y * width + x])
                        if abs(value) < contrastGate { continue }
                        // Strict 26-neighborhood extremum (plateaus yield
                        // nothing — the deterministic tie posture).
                        var isMax = true
                        var isMin = true
                        let neighborhood = [below, center, above]
                        for (offset, layer) in neighborhood.enumerated() {
                            for dy in -1...1 {
                                for dx in -1...1 {
                                    if offset == 1, dy == 0, dx == 0 { continue }
                                    let neighbor = Double(
                                        layer.pixels[(y + dy) * width + (x + dx)])
                                    if neighbor >= value { isMax = false }
                                    if neighbor <= value { isMin = false }
                                }
                            }
                        }
                        guard isMax || isMin else { continue }
                        // The 2×2 Hessian edge gate (low principal curvature).
                        let dxx = Double(center.pixels[y * width + x + 1]
                            + center.pixels[y * width + x - 1]
                            - 2 * center.pixels[y * width + x])
                        let dyy = Double(center.pixels[(y + 1) * width + x]
                            + center.pixels[(y - 1) * width + x]
                            - 2 * center.pixels[y * width + x])
                        let dxy = Double(
                            (center.pixels[(y + 1) * width + x + 1]
                                - center.pixels[(y + 1) * width + x - 1]
                                - center.pixels[(y - 1) * width + x + 1]
                                + center.pixels[(y - 1) * width + x - 1]) / 4)
                        let trace = dxx + dyy
                        let det = dxx * dyy - dxy * dxy
                        guard det > 0, trace * trace <= edgeGate * det else { continue }
                        let orientation = dominantOrientation(
                            pyramid.octaves[o][d + 1], x: x, y: y, sigmaLocal: sigmaLocal)
                        let upsample = pow(2, Double(o))
                        keypoints.append(PanoKeypoint(
                            x: Double(x) * upsample,
                            y: Double(y) * upsample,
                            octave: o,
                            sigma: sigma0 * pow(2, Double(o) + relativeScale),
                            response: abs(value),
                            orientation: orientation))
                    }
                }
            }
        }
        let capped = applyFeatureCap(keypoints, limit: featureCap)
        let descriptors = describe(pyramid, keypoints: capped)
        return (capped, descriptors)
    }

    /// The response-ordered feature cap (merge.py:219's nfeatures=6000
    /// semantics): sort by response DESC with the index tie-break (a total
    /// order — Swift's sort is not stable, this is), keep the first `limit`.
    public static func applyFeatureCap(
        _ keypoints: [PanoKeypoint], limit: Int
    ) -> [PanoKeypoint] {
        guard keypoints.count > limit else { return keypoints }
        let indexed = keypoints.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.1.response != rhs.1.response {
                return lhs.1.response > rhs.1.response
            }
            return lhs.0 < rhs.0
        }
        return sorted.prefix(limit).map(\.1)
    }

    /// The single-peak 36-bin orientation histogram (window radius
    /// ⌈1.5σ⌉, Gaussian weight σ_w = σ, nearest-bin accumulation — the
    /// pinned simplification; ties keep the lowest bin index).
    private static func dominantOrientation(
        _ layer: PanoGrayPlane, x: Int, y: Int, sigmaLocal: Double
    ) -> Double {
        let binCount = 36
        var histogram = [Double](repeating: 0, count: binCount)
        let radius = max(2, Int((1.5 * sigmaLocal).rounded(.up)))
        let weightDenom = 2.0 * sigmaLocal * sigmaLocal
        let width = layer.width
        let height = layer.height
        for dy in -radius...radius {
            let yy = y + dy
            guard yy >= 1, yy < height - 1 else { continue }
            for dx in -radius...radius {
                let xx = x + dx
                guard xx >= 1, xx < width - 1 else { continue }
                let gx = Double(layer.pixels[yy * width + xx + 1]
                    - layer.pixels[yy * width + xx - 1])
                let gy = Double(layer.pixels[(yy + 1) * width + xx]
                    - layer.pixels[(yy - 1) * width + xx])
                let magnitude = sqrt(gx * gx + gy * gy)
                if magnitude == 0 { continue }
                var angle = atan2(gy, gx)
                if angle < 0 { angle += 2 * Double.pi }
                let weight = exp(-Double(dx * dx + dy * dy) / weightDenom)
                let bin = min(binCount - 1, Int(angle / (2 * Double.pi) * Double(binCount)))
                histogram[bin] += magnitude * weight
            }
        }
        var best = 0
        for index in 1..<binCount where histogram[index] > histogram[best] {
            best = index
        }
        // Parabolic peak interpolation (the SIFT refinement): sub-bin offset
        // from the neighbors, clipped to ±½ bin; a non-peak concavity keeps
        // the bin center.
        let previous = histogram[(best + binCount - 1) % binCount]
        let next = histogram[(best + 1) % binCount]
        let peak = histogram[best]
        let denominator = previous - 2 * peak + next
        var offset = 0.0
        if denominator < 0 {
            offset = 0.5 * (previous - next) / denominator
            offset = min(max(offset, -0.5), 0.5)
        }
        return (Double(best) + 0.5 + offset) * 2 * Double.pi / Double(binCount)
    }

    // MARK: - Description (KD-2)

    /// The 128-dim oriented-gradient descriptor per keypoint: 4×4 cells of
    /// 4σ_local (window half-width 8σ_local), gradients rotated into the
    /// keypoint's frame, 8 relative-angle bins with the linear angle split,
    /// Gaussian sample weight σ_w = half/2; then L2 → clamp 0.2 → renorm →
    /// sqrt → final L2 (the root contract — see descriptorVector). Degenerate
    /// (flat-window) keypoints are DROPPED — the returned array may be
    /// shorter, `keypointIndex` preserves the original indices.
    public static func describe(
        _ pyramid: PanoPyramid, keypoints: [PanoKeypoint]
    ) -> [PanoDescriptor] {
        var descriptors: [PanoDescriptor] = []
        descriptors.reserveCapacity(keypoints.count)
        for (index, keypoint) in keypoints.enumerated() {
            let octave = keypoint.octave
            guard octave >= 0, octave < pyramid.octaves.count else { continue }
            let downsample = pow(2, Double(octave))
            let localX = keypoint.x / downsample
            let localY = keypoint.y / downsample
            let sigmaLocal = keypoint.sigma / downsample
            // The gradient layer the detection used for this keypoint:
            // σ_local = σ0·2^((d+1)/S) ⇒ layer index = S·log2(σ_local/σ0).
            let layerIndex = Int(
                (Double(intervals) * log2(sigmaLocal / sigma0)).rounded())
            guard layerIndex >= 0, layerIndex < pyramid.octaves[octave].count
            else { continue }
            guard let vector = descriptorVector(
                pyramid.octaves[octave][layerIndex],
                x: localX, y: localY, sigma: sigmaLocal,
                orientation: keypoint.orientation)
            else { continue }
            descriptors.append(PanoDescriptor(keypointIndex: index, vector: vector))
        }
        return descriptors
    }

    private static func descriptorVector(
        _ layer: PanoGrayPlane, x: Double, y: Double, sigma: Double,
        orientation: Double
    ) -> [Float]? {
        let cellSize = 4.0 * sigma
        let half = 2.0 * cellSize // 8σ — the 4×4 window half-width
        let radius = Int(half.rounded(.up))
        let weightDenom = 2.0 * (half * 0.5) * (half * 0.5)
        let cosTheta = cos(orientation)
        let sinTheta = sin(orientation)
        let binWidth = Double.pi / 4
        var histogram = [Double](repeating: 0, count: PanoDescriptor.dimensions)
        let width = layer.width
        let height = layer.height
        let baseX = Int(x.rounded())
        let baseY = Int(y.rounded())
        for dy in -radius...radius {
            let py = baseY + dy
            guard py >= 1, py < height - 1 else { continue }
            for dx in -radius...radius {
                let px = baseX + dx
                guard px >= 1, px < width - 1 else { continue }
                // The rotated sample frame (the orientation invariance).
                let rx = cosTheta * Double(dx) + sinTheta * Double(dy)
                let ry = -sinTheta * Double(dx) + cosTheta * Double(dy)
                // Bilinear cell assignment (the SIFT standard): each sample
                // spreads over its (up to) two neighboring cells per axis in
                // the rotated frame — the nearest-cell form loses matches
                // under a few degrees of orientation-quantization residual
                // (the probe-pinned rotation distances: 0.25 → 0.75 mean).
                // Cell c covers rx/cellSize ∈ [c−2, c−1); the outer neighbor
                // of an edge sample is guarded out below.
                let cellU = rx / cellSize
                let cellV = ry / cellSize
                let cellX0 = Int(floor(cellU))
                let cellY0 = Int(floor(cellV))
                let fracX = cellU - Double(cellX0)
                let fracY = cellV - Double(cellY0)
                guard cellX0 >= -2, cellX0 < 2, cellY0 >= -2, cellY0 < 2 else {
                    continue
                }
                let gx = Double(layer.pixels[py * width + px + 1]
                    - layer.pixels[py * width + px - 1])
                let gy = Double(layer.pixels[(py + 1) * width + px]
                    - layer.pixels[(py - 1) * width + px])
                let magnitude = sqrt(gx * gx + gy * gy)
                if magnitude == 0 { continue }
                // Floor-mod into [0, 2π): the raw difference spans (−3π, π]
                // and a single conditional wrap leaves negatives (a negative
                // position through Swift's sign-keeping `%` indexes out of
                // range — the probe-pinned crash).
                var angle = (atan2(gy, gx) - orientation)
                    .truncatingRemainder(dividingBy: 2 * Double.pi)
                if angle < 0 { angle += 2 * Double.pi }
                if angle >= 2 * Double.pi { angle = 0 }
                let position = angle / binWidth
                let bin = Int(position) % 8
                let fraction = position - floor(position)
                let weight = exp(-Double(dx * dx + dy * dy) / weightDenom) * magnitude
                // The (up to) four neighboring cells with bilinear weights.
                for (offsetY, weightY) in [(0, 1 - fracY), (1, fracY)] {
                    let cy = cellY0 + offsetY
                    guard cy >= -2, cy < 2 else { continue }
                    for (offsetX, weightX) in [(0, 1 - fracX), (1, fracX)] {
                        let cx = cellX0 + offsetX
                        guard cx >= -2, cx < 2 else { continue }
                        let base = (cy + 2) * 32 + (cx + 2) * 8
                        histogram[base + bin] += weight * weightY * weightX * (1 - fraction)
                        histogram[base + (bin + 1) % 8] += weight * weightY * weightX * fraction
                    }
                }
            }
        }
        // L2 normalize → clamp → renormalize → sqrt → final L2 (the root
        // contract: sqrt of a unit vector has norm √‖u‖₁ ≠ 1 — the pinned
        // unit-norm clause needs the closing renormalize; the positive
        // scalar leaves the Hellinger ranking intact).
        var vector = histogram
        var norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-12 else { return nil }
        for index in vector.indices {
            vector[index] /= norm
            vector[index] = min(vector[index], descriptorClamp)
        }
        norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-12 else { return nil }
        var rooted = vector.map { sqrt($0 / norm) }
        let rootedNorm = sqrt(rooted.reduce(0) { $0 + $1 * $1 })
        guard rootedNorm > 1e-12 else { return nil }
        return rooted.map { Float($0 / rootedNorm) }
    }
}
