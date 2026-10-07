import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MTB alignment (Plan 08-1 T2; RESEARCH §2) — Ward's median-threshold-bitmap
// pyramid, the hdrmerge/Luminance mainstream for bracket alignment.
//
// Parameter table (research §2.1 — P1-probed configuration, pinned):
//   • 8 pyramid levels (100 MP → ≈91×68 bottom level)
//   • luma = Rec2020 coefficients (0.2126/0.7152/0.0722) taken on the LINEAR
//     decode domain directly (the MTB threshold is monotonic-gain invariant —
//     no gamma pre-correction)
//   • threshold = the 256-bin histogram MEDIAN per level (8-bit quantization
//     only feeds the threshold decision; the bitmap is 1 bit/pixel)
//   • search: coarse-to-fine, ±1 px per level; the bottom level searches ±1
//     independently, every step up doubles the inherited shift first then
//     searches ±1 again → ±128 px full-res coverage
//   • bitmap compare: packed UInt64 XOR + popcount over the INTERSECTION
//     window — the window SHRINKS by (dx,dy) (the P1 first-cut out-of-bounds
//     lesson, pinned into the implementation)
//   • rotation: v1 = translation ONLY; a ±1° rotation search stays an
//     ADDITIVE KNOB SLOT (research §17.2 — not probed, not in the default
//     path)
//
// Failure handling (research §2.3): a merge is NEVER hard-failed by
// alignment — "no alignment + merge anyway + warn", with the provenance
// label recording why (`degraded` = hit the search boundary;
// `skipped-low-texture` = a near-constant luma histogram).
//
// SHIFT CONVENTION (load-bearing for the merge pass): `cmp(x, y) ==
// ref(x - dx, y - dy)` — the comparison frame's content is the reference's
// content carried by (+dx, +dy); the merge pass therefore SAMPLES the
// comparison source at (X - dx, Y - dy) for the output pixel (X, Y).
// ─────────────────────────────────────────────────────────────────────────────

/// One alignment frame's luma planes. The full-resolution NORMALIZED uint8
/// surface feeds the MTB pyramid (ordering-only — normalization cancels the
/// inter-frame gain); the small UNNORMALIZED float surface (a decimated
/// copy) feeds the runtime exposure-ratio self-check, which must see the
/// raw physical values.
public struct AlignmentFrame: Sendable {

    /// Full-resolution normalized uint8 luma (row-major, 1 byte/px).
    public let luma: LumaSurface

    /// The UNNORMALIZED float luma, decimated to ≈1024 px long edge
    /// (row-major) — the exposure-ratio self-check's median source.
    public let ratioLuma: RatioLuma

    public struct LumaSurface: Sendable {
        public let width: Int
        public let height: Int
        public let pixels: [UInt8]

        public init(width: Int, height: Int, pixels: [UInt8]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }

        @inline(__always)
        public func pixel(_ x: Int, _ y: Int) -> UInt8 {
            pixels[y * width + x]
        }
    }

    /// The decimated float luma (physical domain, unnormalized).
    public struct RatioLuma: Sendable {
        public let width: Int
        public let height: Int
        public let pixels: [Float]

        public init(width: Int, height: Int, pixels: [Float]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }
    }

    /// Build the frame from a full-resolution float RGBA linear-Rec2020
    /// buffer (row-major, `bytesPerRow` bytes per row): luma = 0.2126R +
    /// 0.7152G + 0.0722B, normalized by the surface MAX (monotonic — the
    /// MTB bit order is preserved), quantized to uint8. The ratio surface
    /// is the same luma box-decimated to ≈1024 px long edge, UNNORMALIZED.
    public init(
        rgbaFloat: UnsafeRawBufferPointer, width: Int, height: Int,
        bytesPerRow: Int
    ) {
        // Pass 1: float luma + max (one sweep, no full-width allocation kept).
        var floatLuma = [Float](repeating: 0, count: width * height)
        var maxValue: Float = 0
        for y in 0..<height {
            let row = rgbaFloat.baseAddress!.advanced(by: y * bytesPerRow)
                .bindMemory(to: Float.self, capacity: width * 4)
            for x in 0..<width {
                let base = x * 4
                let value = 0.2126 * row[base] + 0.7152 * row[base + 1]
                    + 0.0722 * row[base + 2]
                floatLuma[y * width + x] = value
                if value > maxValue { maxValue = value }
            }
        }
        // Normalized uint8 (max 0 → an all-black frame; quantize to zeros).
        let scale: Float = maxValue > 0 ? 255 / maxValue : 0
        var u8 = [UInt8](repeating: 0, count: width * height)
        for index in u8.indices {
            let scaled = floatLuma[index] * scale
            u8[index] = UInt8(max(0, min(255, Int(scaled.rounded()))))
        }
        self.luma = LumaSurface(width: width, height: height, pixels: u8)

        // Decimated float ratio surface (2×2 box mean to ≈1024 long edge).
        let longEdge = max(width, height)
        let step = max(1, (longEdge + 1023) / 1024)
        let smallWidth = width / step
        let smallHeight = height / step
        var small = [Float](repeating: 0, count: smallWidth * smallHeight)
        if step == 1 {
            small = floatLuma
        } else {
            for sy in 0..<smallHeight {
                for sx in 0..<smallWidth {
                    var accumulator: Float = 0
                    for dy in 0..<step {
                        let rowBase = (sy * step + dy) * width + sx * step
                        for dx in 0..<step {
                            accumulator += floatLuma[rowBase + dx]
                        }
                    }
                    small[sy * smallWidth + sx] = accumulator / Float(step * step)
                }
            }
        }
        self.ratioLuma = RatioLuma(
            width: smallWidth, height: smallHeight, pixels: small)
    }
}

/// One pyramid level's median-threshold bitmap (1 bit/pixel, packed UInt64
/// rows; each row's words array carries ONE extra always-zero guard word so
/// the shifted word reads never index out of bounds).
public struct MTBBitmap: Sendable {

    public let width: Int
    public let height: Int
    public let wordsPerRow: Int
    var bits: [UInt64]

    /// The bit for pixel (x, y): 1 = luma above the level's median.
    @inline(__always)
    func bit(_ x: Int, _ y: Int) -> UInt64 {
        (bits[y * wordsPerRow + (x >> 6)] >> UInt64(x & 63)) & 1
    }

    @inline(__always)
    func word(_ row: Int, _ index: Int) -> UInt64 {
        bits[row * wordsPerRow + index]
    }
}

/// The alignment answer for one comparison frame.
public struct MTBShift: Sendable, Equatable {

    /// SHIFT CONVENTION: cmp(x, y) == ref(x - dx, y - dy).
    public let dx: Int
    public let dy: Int

    /// Best XOR distance / intersection pixels (0 = perfect bit match,
    /// ≈0.5 = random). The research §2.3 failure threshold is 0.25.
    public let quality: Double

    /// The failure classification (`nil` = a trusted alignment).
    public enum Quality: Sendable, Equatable {
        /// A trusted alignment — the provenance label is `"full"`.
        case full
        /// The best hit sat ON the search boundary — the provenance label
        /// is `"degraded"`.
        case hitSearchBoundary
        /// A near-constant luma histogram — the label is
        /// `"skipped-low-texture"`.
        case lowTexture
    }

    public let verdict: Quality

    /// The provenance label (RESEARCH §3.4 vocabulary).
    public var label: String {
        switch verdict {
        case .full: return "full"
        case .hitSearchBoundary: return "degraded"
        case .lowTexture: return "skipped-low-texture"
        }
    }
}

public enum MTBAlign {

    // MARK: - Tunables (research §2.1 table + §2.3 thresholds)

    /// Pyramid depth (100 MP → ≈91×68 bottom level).
    public static let pyramidLevels = 8

    /// The XOR-distance failure threshold (bits/pixel; random ≈ 0.5).
    public static let maxAcceptableDistance = 0.25

    /// The near-constant histogram ratio (the low-texture verdict).
    public static let lowTextureDominantBin = 0.99

    // MARK: - Pyramid build

    /// Build the 8-level pyramid: level 0 = full resolution, each next
    /// level halves (2×2 box mean, odd edges dropped) and re-thresholds on
    /// ITS OWN histogram median.
    public static func pyramid(
        _ luma: AlignmentFrame.LumaSurface, levels: Int = MTBAlign.pyramidLevels
    ) -> [MTBBitmap] {
        var width = luma.width
        var height = luma.height
        var gray = [UInt32](repeating: 0, count: width * height)
        for index in gray.indices { gray[index] = UInt32(luma.pixels[index]) }
        var result: [MTBBitmap] = []
        result.reserveCapacity(levels)
        for level in 0..<levels {
            result.append(bitmap(gray: gray, width: width, height: height))
            if width <= 2 || height <= 2 { break }
            // 2×2 box-mean downsample (odd edge dropped).
            let nextWidth = width >> 1
            let nextHeight = height >> 1
            var next = [UInt32](repeating: 0, count: nextWidth * nextHeight)
            for y in 0..<nextHeight {
                let row0 = (y * 2) * width
                let row1 = (y * 2 + 1) * width
                for x in 0..<nextWidth {
                    let x0 = x * 2
                    next[y * nextWidth + x] = (gray[row0 + x0]
                        + gray[row0 + x0 + 1]
                        + gray[row1 + x0]
                        + gray[row1 + x0 + 1]) >> 2
                }
            }
            gray = next
            width = nextWidth
            height = nextHeight
        }
        return result
    }

    /// The level's bitmap: threshold = the 256-bin histogram median; bit = 1
    /// for luma STRICTLY above the median.
    static func bitmap(
        gray: [UInt32], width: Int, height: Int
    ) -> MTBBitmap {
        var histogram = [Int](repeating: 0, count: 256)
        for value in gray { histogram[Int(value)] += 1 }
        let median = medianThreshold(histogram: histogram, total: gray.count)

        let wordsPerRow = width / 64 + 1 // +1 = the zero guard word
        var bits = [UInt64](repeating: 0, count: wordsPerRow * height)
        for y in 0..<height {
            let rowBase = y * wordsPerRow
            for x in 0..<width {
                if gray[y * width + x] > median {
                    bits[rowBase + (x >> 6)] |= 1 << UInt64(x & 63)
                }
            }
        }
        return MTBBitmap(
            width: width, height: height, wordsPerRow: wordsPerRow, bits: bits)
    }

    /// The 256-bin median (the bin where the cumulative count crosses
    /// total/2 — the Ward MTB threshold).
    static func medianThreshold(histogram: [Int], total: Int) -> UInt32 {
        guard total > 0 else { return 0 }
        let half = total / 2
        var cumulative = 0
        for bin in 0..<256 {
            cumulative += histogram[bin]
            if cumulative > half { return UInt32(bin) }
        }
        return 255
    }

    /// The near-constant verdict: the largest bin holds ≥ 99% of the pixels.
    static func isLowTexture(_ luma: AlignmentFrame.LumaSurface) -> Bool {
        var histogram = [Int](repeating: 0, count: 256)
        for pixel in luma.pixels { histogram[Int(pixel)] += 1 }
        guard let dominant = histogram.max() else { return true }
        return Double(dominant)
            >= Double(luma.pixels.count) * lowTextureDominantBin
    }

    // MARK: - The coarse-to-fine search

    /// Find the shift of `compare` relative to `reference` (both pyramids
    /// from `MTBAlign.pyramid`, level 0 = full resolution). Coarse-to-fine:
    /// the bottom level searches ±1 independently; every step up doubles
    /// the inherited shift then searches ±1 again.
    public static func findShift(
        reference: [MTBBitmap], compare: [MTBBitmap]
    ) -> MTBShift {
        precondition(
            reference.count == compare.count && !reference.isEmpty,
            "pyramids must be built pairwise")
        // Low texture → do not even search (the merge degrades to identity
        // with the `skipped-low-texture` label).
        if isLowTextureFrame(reference: reference, compare: compare) {
            return MTBShift(dx: 0, dy: 0, quality: 0, verdict: .lowTexture)
        }

        // Adaptive effective bottom (execution decision D-08-1): the
        // coarsest searched level must keep enough pixels for a STABLE
        // median bitmap — a bottom below ~16 px wide turns the median into
        // noise and the inherited seed cascades in the wrong direction
        // (the fixture-pathology finding, pinned here). The 100 MP 8-level
        // pyramid's bottom (≈91×68) qualifies and keeps the research §2.1
        // table verbatim; small frames simply start coarser.
        var bottom = reference.count - 1
        while bottom > 0,
              reference[bottom].width < 16 || reference[bottom].height < 12 {
            bottom -= 1
        }

        var dx = 0
        var dy = 0
        var bestDistance = 0.0
        for level in stride(from: bottom, through: 0, by: -1) {
            if level != bottom {
                dx *= 2
                dy *= 2
            }
            let ref = reference[level]
            let cmp = compare[level]
            var localBest = Double.greatestFiniteMagnitude
            var localBestDx = dx
            var localBestDy = dy
            for candidateDy in (dy - 1)...(dy + 1) {
                for candidateDx in (dx - 1)...(dx + 1) {
                    let distance = Self.xorDistance(
                        reference: ref, compare: cmp,
                        dx: candidateDx, dy: candidateDy)
                    if distance < localBest {
                        localBest = distance
                        localBestDx = candidateDx
                        localBestDy = candidateDy
                    }
                }
            }
            dx = localBestDx
            dy = localBestDy
            bestDistance = localBest
        }

        // Failure verdicts (research §2.3): a boundary hit or a distance
        // beyond the noise floor both DEGRADE (never hard-fail). The search
        // bound = the coarse-to-fine reach from the EFFECTIVE bottom:
        // 2^bottom full-res px (±1 px per level, doubled on every step up).
        let searchBound = 1 << bottom
        let onBoundary = abs(dx) >= searchBound || abs(dy) >= searchBound
        let verdict: MTBShift.Quality
        if onBoundary || bestDistance > maxAcceptableDistance {
            verdict = .hitSearchBoundary
        } else {
            verdict = .full
        }
        return MTBShift(dx: dx, dy: dy, quality: bestDistance, verdict: verdict)
    }

    /// Low texture = EITHER frame's level-0 histogram is near-constant.
    /// The check rides LEVEL 0 (the full resolution — the coarsest levels
    /// quantize a flat field into a uniform median bitmap and would
    /// false-positive; the fixture-pathology finding, pinned here).
    static func isLowTextureFrame(
        reference: [MTBBitmap], compare: [MTBBitmap]
    ) -> Bool {
        // The pyramids carry bits, not the histogram — the DOMINANT-BIT
        // ratio at level 0 is the equivalent test (a constant frame's
        // median bitmap is uniform: strictly-above-median is empty).
        for pyramid in [reference, compare] {
            let level = pyramid[0]
            var ones = 0
            let total = level.width * level.height
            for y in 0..<level.height {
                let rowBase = y * level.wordsPerRow
                for wordIndex in 0..<(level.wordsPerRow - 1) {
                    ones += level.bits[rowBase + wordIndex].nonzeroBitCount
                }
            }
            let dominant = max(ones, total - ones)
            if total > 0,
               Double(dominant) >= Double(total) * lowTextureDominantBin {
                return true
            }
        }
        return false
    }

    // MARK: - The intersection-window XOR distance

    /// XOR popcount / intersection pixels asserting the shift convention
    /// `cmp(x, y) == ref(x − dx, y − dy)` over the intersection rect — the
    /// window SHRINKS with the shift (the P1 out-of-bounds lesson).
    /// Word-aligned in the interior, bit-exact at the edges.
    static func xorDistance(
        reference: MTBBitmap, compare: MTBBitmap, dx: Int, dy: Int
    ) -> Double {
        // Intersection in COMPARE coordinates: x − dx must stay inside the
        // reference frame → x ∈ [max(0,dx), min(cmpW, refW+dx)), y likewise.
        let x0 = max(0, dx)
        let x1 = min(compare.width, reference.width + dx)
        let y0 = max(0, dy)
        let y1 = min(compare.height, reference.height + dy)
        guard x1 > x0, y1 > y0 else { return 1.0 }

        var totalBits: UInt64 = 0
        let interiorStart = (x0 + 63) & ~63
        let interiorEnd = x1 & ~63

        for y in y0..<y1 {
            let cmpRow = y * compare.wordsPerRow
            let refRow = (y - dy) * reference.wordsPerRow
            // Head/tail edges: bit-exact loop.
            var x = x0
            while x < min(x1, interiorStart) {
                totalBits += compare.bit(x, y) ^ reference.bit(x - dx, y - dy)
                x += 1
            }
            // Interior: an aligned 64-bit window of the reference starting
            // at absolute bit (x − dx) — its bit b IS ref(x − dx + b), for
            // EITHER sign of dx (the guard word keeps the +1 read safe).
            while x < interiorEnd {
                let position = x - dx
                let wordIndex = position >> 6
                let offset = position & 63
                let w0 = reference.bits[refRow + wordIndex]
                let refWord: UInt64
                if offset == 0 {
                    refWord = w0
                } else {
                    let w1 = reference.bits[refRow + wordIndex + 1]
                    refWord = w0 >> UInt64(offset) | (w1 << UInt64(64 - offset))
                }
                let cmpWord = compare.bits[cmpRow + (x >> 6)]
                totalBits &+= UInt64((cmpWord ^ refWord).nonzeroBitCount)
                x += 64
            }
            // Tail edge.
            while x < x1 {
                totalBits += compare.bit(x, y) ^ reference.bit(x - dx, y - dy)
                x += 1
            }
        }
        let pixels = (x1 - x0) * (y1 - y0)
        guard pixels > 0 else { return 1.0 }
        return Double(totalBits) / Double(pixels)
    }
}
