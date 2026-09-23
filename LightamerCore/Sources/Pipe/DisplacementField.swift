import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DisplacementField (Plan 06-06 T1) — the liquify displacement grid, living
// in Core because the mask point mapper's `.liquify` segment consumes it
// (Core cannot import IOP, D-03). The BUILDER (path interpolation + stamps)
// lives in LightamerIOP (`LiquifyDistortionField`); this type is the inert
// product both the GPU kernel (as an MTLBuffer mirror of `vectors`) and the
// CPU point mapper (via bilinear sampling) read.
//
// SEMANTICS (L020 — coordinate premise pinned):
// A cell (i, j) of the grid holds the displacement vector F at the FRAME
// PIXEL x = origin + (i, j) — the same domain the warp kernel samples in
// (the run's plane pixels; for the mapper, the entry-frame pixels of the
// chain position). dt's map is identical: `warp_kernel` reads
// `map[pos.y * extent.width + pos.x]` for the FRAME pixel `pos + origin`
// (liquify.cl:82-86). The field is the BACKWARD SAMPLING map:
//
//     out(q) = in(q + F(q))          (the kernel's per-pixel sampling)
//
// so content physically moves by −F, and the mapper's two legs are:
//   inverse (composite q → decode p)  = q + F(q)   [exact, the sampling map]
//   forward (decode p → composite q)  = solve q + F(q) = p  [iterative, the
//     mapper's guarded solve — the lens `.radial` forward does the same]
// ─────────────────────────────────────────────────────────────────────────────

/// A per-pixel displacement field over a rectangular extent (liquify,
/// Plan 06-06; dt `_build_global_distortion_map` product).
public struct DisplacementField: Sendable, Equatable {

    /// The grid: `origin` = extent origin in frame pixels; `vectors` is
    /// row-major `width × height` (dt's `map` layout — cell (i, j) is the
    /// displacement at frame pixel `origin + (i, j)`).
    public struct Grid: Sendable, Equatable {
        public var origin: SIMD2<Int>
        public var width: Int
        public var height: Int
        public var vectors: [SIMD2<Float>]

        public init(origin: SIMD2<Int>, width: Int, height: Int, vectors: [SIMD2<Float>]) {
            precondition(vectors.count == width * height, "grid payload mismatch")
            self.origin = origin
            self.width = width
            self.height = height
            self.vectors = vectors
        }

        /// The displacement at a continuous frame point: bilinear over the
        /// four neighboring cells (cell values anchor AT integer frame
        /// coordinates — vertex interpolation). Outside the extent → zero
        /// (dt: cells beyond the stamp union are untouched zeros).
        public func sample(_ p: SIMD2<Double>) -> SIMD2<Double> {
            let fx = p.x - Double(origin.x)
            let fy = p.y - Double(origin.y)
            let i0 = Int(fx.rounded(.down))
            let j0 = Int(fy.rounded(.down))
            let tx = fx - Double(i0)
            let ty = fy - Double(j0)
            func cell(_ i: Int, _ j: Int) -> SIMD2<Double> {
                guard i >= 0, j >= 0, i < width, j < height else { return .zero }
                let v = vectors[j * width + i]
                return SIMD2(Double(v.x), Double(v.y))
            }
            let c00 = cell(i0, j0), c10 = cell(i0 + 1, j0)
            let c01 = cell(i0, j0 + 1), c11 = cell(i0 + 1, j0 + 1)
            let bottom = c00 * (1 - tx) + c10 * tx
            let top = c01 * (1 - tx) + c11 * tx
            return bottom * (1 - ty) + top * ty
        }
    }

    /// The forward (sampling) map F. `out(q) = in(q + F(q))`.
    public var forward: Grid

    public init(forward: Grid) {
        self.forward = forward
    }

    /// The kernel's sampling map at a composite pixel: p = q + F(q).
    public func sampleForward(_ q: SIMD2<Double>) -> SIMD2<Double> {
        forward.sample(q)
    }

    /// Upper bound |F| over the grid — the tile halo's displacement term.
    public var maxMagnitude: Double {
        var m = 0.0
        for v in forward.vectors {
            m = max(m, Double((v.x * v.x + v.y * v.y).squareRoot()))
        }
        return m
    }

    /// True when every cell is zero (degenerate stamps) — the module's
    /// identity fallback.
    public var isZero: Bool {
        forward.vectors.allSatisfy { $0.x == 0 && $0.y == 0 }
    }
}
