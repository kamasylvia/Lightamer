// SPDX-License-Identifier: GPL-3.0-or-later
//! Tiling decision: whole frame or a tile grid.
//!
//! Pure port of darktable's pixel-to-pixel tiling path
//! (`_default_process_tiling_ptp`, `src/develop/tiling.c:571-822`): the same
//! fit check, the same shrink/align/count formulas, the same give-up. Byte
//! math is `u64`/checked; the shrink ratios run in `f64` where upstream uses
//! `float` (same formulas, wider floats — the hand-computed tests use
//! exact-binary values on which both agree).
//!
//! Scope: like-for-like regions only. darktable dispatches ptp-vs-roi by
//! bitwise roi equality (`tiling.c:1176`); a shape mismatch here answers
//! [`TilingDecision::NoTiling`] — the roi-variant path (iterative fit
//! `tiling.c:527-567` plus simplex `tiling.c:496-525`) needs module callbacks
//! in the loop and lands with execution in B1-b.

use lightamer_geom::Roi as GeomRoi;
use lightamer_iop_traits::TilingReq;

/// darktable's give-up: past this many tiles it processes untiled
/// (`src/develop/tiling.c:81-84`; the `unrestricted` resource level, which
/// raises this to `2^30`, has no counterpart here).
pub const MAX_TILES: u64 = 10_000;

/// Below this factor tiling buys nothing (`src/develop/tiling.c:599-610`).
const NO_GAIN_FACTOR: f64 = 2.2;

/// Shrink-branch threshold: upstream's `0.333f` literal bit for bit
/// (`tiling.c:634,638`), widened to `f64` like the ratios it compares.
const SHRINK_BRANCH: f64 = 0.333f32 as f64;

/// A tile: its grid position, the good part it contributes, and the input it
/// reads (good part plus overlap margins).
#[derive(Debug, Clone, PartialEq)]
pub struct Tile {
    /// Horizontal grid index.
    pub tx: u32,
    /// Vertical grid index.
    pub ty: u32,
    /// Good part in output coordinates (leading overlap trimmed).
    pub output: GeomRoi,
    /// Full tile in input coordinates, overlap included, frame-clamped.
    pub input: GeomRoi,
}

/// A tile grid: darktable's tile counts plus the executable tiles.
#[derive(Debug, Clone, PartialEq)]
pub struct TileGrid {
    /// Horizontal tile count (positions, skipped end-tiles included).
    pub tiles_x: u32,
    /// Vertical tile count.
    pub tiles_y: u32,
    /// Tiles to process; end-tiles narrower than the overlap on both sides
    /// are left out, as upstream `continue`s past them (`tiling.c:733`).
    pub tiles: Vec<Tile>,
}

/// Tiling verdict for one module at one region pair.
#[derive(Debug, Clone, PartialEq)]
pub enum TilingDecision {
    /// Process the whole frame: it fits, tiling buys nothing, regions
    /// differ, or the grid gave up (upstream falls back to untiled
    /// processing in all these cases).
    NoTiling,
    /// Process per tile.
    Tiled(TileGrid),
}

/// Decides whole-frame vs tiled.
///
/// `frame_bytes` is one full frame (`width * height * bytes-per-pixel`);
/// `budget_bytes` is this pipe's memory budget;
/// `singlebuffer_floor` is this pipe's single-tile floor in bytes (see
/// [`crate::kinds::singlebuffer_floor`]). Both regions must be the
/// ptp shape (bitwise equal, `tiling.c:1176`); anything else answers
/// [`TilingDecision::NoTiling`] (see module docs).
#[must_use]
pub fn decide(
    req: &TilingReq,
    roi_in: &GeomRoi,
    roi_out: &GeomRoi,
    frame_bytes: u64,
    budget_bytes: u64,
    singlebuffer_floor: u64,
) -> TilingDecision {
    if roi_in.is_empty() || roi_out.is_empty() {
        return TilingDecision::NoTiling;
    }
    // Bitwise ptp dispatch (tiling.c:1176); the TILING_FULL_ROI flag leg has
    // no counterpart yet (our flags vocabulary has no such bit).
    let same_shape = roi_in.x == roi_out.x
        && roi_in.y == roi_out.y
        && roi_in.width == roi_out.width
        && roi_in.height == roi_out.height
        && roi_in.scale.to_bits() == roi_out.scale.to_bits();
    if !same_shape {
        return TilingDecision::NoTiling;
    }
    let factor = f64::from(req.factor.max(1.0));
    let maxbuf = f64::from(req.maxbuf.max(1.0));
    let frame = bytes_f64(frame_bytes);
    let budget = bytes_f64(budget_bytes);

    // Fit check (dt_tiling_piece_fits_host_memory, tiling.c:1923-1933).
    if factor * frame + bytes_f64(req.overhead) <= budget {
        return TilingDecision::NoTiling;
    }
    // No-gain gate (tiling.c:599-610).
    if factor < NO_GAIN_FACTOR && bytes_f64(req.overhead) < 0.2 * frame {
        return TilingDecision::NoTiling;
    }

    // Resident frames plus overhead come off the budget first
    // (tiling.c:613-615); the floor is zero.
    let resident = frame_bytes.saturating_mul(2).saturating_add(req.overhead);
    let available = bytes_f64(budget_bytes.saturating_sub(resident));
    // Upstream floors this at dt_get_singlebuffer_mem() (tiling.c:613-620);
    // the caller passes its kind's floor (a zero floor keeps the quotient).
    let singlebuffer = (available / factor).max(bytes_f64(singlebuffer_floor));

    let full_w = i64::from(roi_in.width);
    let full_h = i64::from(roi_in.height);
    let overlap = i64::from(req.overlap);
    let align = i64::from(req.align.max(1));
    let (width, height) =
        settle_tile_size(full_w, full_h, frame, maxbuf, singlebuffer, overlap, align);
    // Overlap rounds up to the alignment (tiling.c:674-675).
    let overlap_eff = if overlap % align == 0 {
        overlap
    } else {
        (overlap / align + 1) * align
    };

    // Good-part stride per tile, at least one pixel (tiling.c:678-679).
    let tile_wd = if width - 2 * overlap_eff > 0 {
        width - 2 * overlap_eff
    } else {
        1
    };
    let tile_ht = if height - 2 * overlap_eff > 0 {
        height - 2 * overlap_eff
    } else {
        1
    };

    // Tile counts (tiling.c:682-683).
    let tiles_x = if width < full_w {
        ceil_div(nonneg_u64(full_w), nonneg_u64(tile_wd))
    } else {
        1
    };
    let tiles_y = if height < full_h {
        ceil_div(nonneg_u64(full_h), nonneg_u64(tile_ht))
    } else {
        1
    };
    if tiles_x.saturating_mul(tiles_y) > MAX_TILES {
        return TilingDecision::NoTiling;
    }
    let plan = GridPlan {
        full_w,
        full_h,
        width,
        height,
        tile_wd,
        tile_ht,
        overlap: overlap_eff,
        tiles_x,
        tiles_y,
    };
    build_grid(roi_in, roi_out, &plan).map_or(TilingDecision::NoTiling, |tiles| {
        let (Ok(tiles_x), Ok(tiles_y)) = (u32::try_from(plan.tiles_x), u32::try_from(plan.tiles_y))
        else {
            return TilingDecision::NoTiling;
        };
        TilingDecision::Tiled(TileGrid {
            tiles_x,
            tiles_y,
            tiles,
        })
    })
}

/// Shrinks the full frame to one tile: single-buffer shrink, overlap
/// squaring, then alignment rounding (`tiling.c:629-675`).
fn settle_tile_size(
    full_w: i64,
    full_h: i64,
    frame: f64,
    maxbuf: f64,
    singlebuffer: f64,
    overlap: i64,
    align: i64,
) -> (i64, i64) {
    let mut width = full_w;
    let mut height = full_h;
    // Shrink the tile while it exceeds the single buffer (tiling.c:629-646).
    if frame * maxbuf > singlebuffer {
        let scale = singlebuffer / (frame * maxbuf);
        if width < height && scale >= SHRINK_BRANCH {
            height = floor_i64(px_f64(height) * scale);
        } else if height <= width && scale >= SHRINK_BRANCH {
            width = floor_i64(px_f64(width) * scale);
        } else {
            let root = scale.sqrt();
            width = floor_i64(px_f64(width) * root);
            height = floor_i64(px_f64(height) * root);
        }
    }
    // Overlap-dominated tiles go square (tiling.c:652-658; the ptp path
    // applies no alignment here).
    if 3 * overlap > width || 3 * overlap > height {
        let side = floor_i64(px_f64(width.max(0) * height.max(0)).sqrt());
        width = side;
        height = side;
    }
    // Tile sizes round down to the alignment, but only when actually split
    // (tiling.c:670-671).
    if width < full_w {
        width = (width / align) * align;
    }
    if height < full_h {
        height = (height / align) * align;
    }
    (width, height)
}

/// Settled tile geometry handed to the grid builder.
struct GridPlan {
    full_w: i64,
    full_h: i64,
    width: i64,
    height: i64,
    tile_wd: i64,
    tile_ht: i64,
    overlap: i64,
    tiles_x: u64,
    tiles_y: u64,
}

/// Integer ceiling division; `b` is always positive here.
fn ceil_div(a: u64, b: u64) -> u64 {
    a.saturating_add(b.saturating_sub(1)) / b.max(1)
}

/// Non-negative pixel value to `u64`. Callers only pass values the shrink
/// and align steps keep at zero or above; the fallback degrades a truly
/// unexpected negative to an empty span.
fn nonneg_u64(px: i64) -> u64 {
    u64::try_from(px).unwrap_or(0)
}

/// Bytes to ratio math. Counts below 2^53 convert exactly; anything larger
/// (petabytes) loses low bits, harmless for a shrink ratio.
#[expect(clippy::cast_precision_loss)]
fn bytes_f64(bytes: u64) -> f64 {
    bytes as f64
}

/// Pixel dims and areas (bounded by 2^62) to ratio math; see [`bytes_f64`].
#[expect(clippy::cast_precision_loss)]
fn px_f64(px: i64) -> f64 {
    px as f64
}

/// Floored pixel value back to `i64`. Out-of-range or non-finite input
/// degrades to 0, which the give-up below turns into
/// [`TilingDecision::NoTiling`]; in-range values convert exactly.
fn floor_i64(value: f64) -> i64 {
    const LIMIT: f64 = 4_294_967_296.0;
    if !value.is_finite() || value < 0.0 || value >= LIMIT {
        return 0;
    }
    #[expect(clippy::cast_possible_truncation)]
    {
        value.floor() as i64
    }
}

/// Per-tile rects; [`None`] when a coordinate leaves `i32` (defensive: only
/// pathological rois near the `i32` edge hit this, and they degrade to
/// [`TilingDecision::NoTiling`]).
fn build_grid(roi_in: &GeomRoi, roi_out: &GeomRoi, plan: &GridPlan) -> Option<Vec<Tile>> {
    // Bounded by the give-up check before the plan was built.
    let nx = i64::try_from(plan.tiles_x).unwrap_or(0);
    let ny = i64::try_from(plan.tiles_y).unwrap_or(0);
    let mut tiles = Vec::new();
    for tx in 0..nx {
        // Last-column width clamps to the frame (tiling.c:727; the row leg is :730).
        let wd = if tx * plan.tile_wd + plan.width > plan.full_w {
            plan.full_w - tx * plan.tile_wd
        } else {
            plan.width
        };
        for ty in 0..ny {
            let ht = if ty * plan.tile_ht + plan.height > plan.full_h {
                plan.full_h - ty * plan.tile_ht
            } else {
                plan.height
            };
            // End-tiles narrower than the two-sided overlap are skipped
            // (tiling.c:733).
            if (wd <= 2 * plan.overlap && tx > 0) || (ht <= 2 * plan.overlap && ty > 0) {
                continue;
            }
            // Good part trims the leading overlap only; trailing margins
            // are overwritten by the next tile (tiling.c:780-790).
            let ox = if tx > 0 { plan.overlap } else { 0 };
            let oy = if ty > 0 { plan.overlap } else { 0 };
            let in_x = i64::from(roi_in.x) + tx * plan.tile_wd;
            let in_y = i64::from(roi_in.y) + ty * plan.tile_ht;
            let out_x = i64::from(roi_out.x) + tx * plan.tile_wd + ox;
            let out_y = i64::from(roi_out.y) + ty * plan.tile_ht + oy;
            let input = GeomRoi::new(
                i32::try_from(in_x).ok()?,
                i32::try_from(in_y).ok()?,
                i32::try_from(wd).ok()?,
                i32::try_from(ht).ok()?,
                roi_in.scale,
            )
            .ok()?;
            let output = GeomRoi::new(
                i32::try_from(out_x).ok()?,
                i32::try_from(out_y).ok()?,
                i32::try_from(wd - ox).ok()?,
                i32::try_from(ht - oy).ok()?,
                roi_out.scale,
            )
            .ok()?;
            tiles.push(Tile {
                tx: u32::try_from(tx).ok()?,
                ty: u32::try_from(ty).ok()?,
                output,
                input,
            });
        }
    }
    Some(tiles)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use lightamer_geom::Roi as GeomRoi;
    use lightamer_iop_traits::{Roi as WireRoi, TilingReq};

    use super::{MAX_TILES, SHRINK_BRANCH, TilingDecision, decide};

    /// 16 bytes per float32 RGBA pixel.
    const BPP: u64 = 16;

    fn geom(x: i32, y: i32, w: i32, h: i32) -> GeomRoi {
        GeomRoi::new(x, y, w, h, 1.0).unwrap()
    }

    fn req(factor: f32, overlap: u32, align: u32) -> TilingReq {
        TilingReq {
            factor,
            maxbuf: 1.0,
            overhead: 0,
            overlap,
            align,
        }
    }

    /// Unwraps a tiled verdict for tests (owned: temporaries cannot lend).
    fn tiled(decision: TilingDecision) -> Option<super::TileGrid> {
        match decision {
            TilingDecision::Tiled(grid) => Some(grid),
            TilingDecision::NoTiling => None,
        }
    }

    #[test]
    fn shrink_branch_matches_upstream_literal() {
        // Upstream compares against the `0.333f` literal (tiling.c:634,638),
        // which is not 1/3: pin the widened value and its distance below it.
        const { assert!(SHRINK_BRANCH < 1.0 / 3.0) };
        assert_eq!(SHRINK_BRANCH, f64::from(0.333f32));
    }

    #[test]
    fn fitting_frame_and_default_request_stay_untiled() {
        let roi = geom(0, 0, 100, 100);
        let frame = 100 * 100 * BPP;
        // Default request: factor 1 + 100*100/100*100 = 2.
        let wire = WireRoi::new(0, 0, 100, 100, 1.0);
        let default = TilingReq::default_for(&wire, &wire);
        assert_eq!(default.factor, 2.0);
        // Fits: 2 * 160_000 = 320_000 <= 1_000_000.
        assert_eq!(
            decide(&default, &roi, &roi, frame, 1_000_000, 0),
            TilingDecision::NoTiling
        );
        // Even past the fit check the no-gain gate (factor 2 < 2.2) keeps
        // default requests untiled: 320_000 > 200_000 yet NoTiling.
        assert_eq!(
            decide(&default, &roi, &roi, frame, 200_000, 0),
            TilingDecision::NoTiling
        );
    }

    #[test]
    fn wide_frame_splits_into_two_x_tiles() {
        // Frame 1000x100, one frame = 1_600_000 bytes, factor 5.
        // Fits? 5 * 1_600_000 = 8_000_000 > 7_200_000: no.
        // Gate? factor 5 >= 2.2: tiling proceeds.
        // available = 7_200_000 - 2 * 1_600_000 = 4_000_000.
        // singlebuffer = 4_000_000 / 5 = 800_000.
        // scale = 800_000 / 1_600_000 = 0.5 (>= 0.333, height <= width):
        // width = floor(1000 * 0.5) = 500, height stays 100.
        // align 1: unchanged. overlap 0: tile stride 500x100.
        // tiles_x = ceil(1000 / 500) = 2, tiles_y = 1.
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        let grid = tiled(decide(&req(5.0, 0, 1), &roi, &roi, frame, 7_200_000, 0)).unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (2, 1));
        assert_eq!(grid.tiles.len(), 2);
        assert_eq!(grid.tiles[0].output, geom(0, 0, 500, 100));
        assert_eq!(grid.tiles[0].input, geom(0, 0, 500, 100));
        assert_eq!(grid.tiles[1].output, geom(500, 0, 500, 100));
        assert_eq!(grid.tiles[1].input, geom(500, 0, 500, 100));
    }

    #[test]
    fn square_frame_splits_both_ways() {
        // Frame 1000x1000, one frame = 16_000_000 bytes, factor 5.
        // Fits? 5 * 16_000_000 = 80_000_000 > 52_000_000: no.
        // available = 52_000_000 - 32_000_000 = 20_000_000.
        // singlebuffer = 20_000_000 / 5 = 4_000_000.
        // scale = 4_000_000 / 16_000_000 = 0.25 (< 0.333): both shrink by
        // sqrt(0.25) = 0.5: 500x500. tiles 2x2.
        let roi = geom(0, 0, 1000, 1000);
        let frame = 1000 * 1000 * BPP;
        let grid = tiled(decide(&req(5.0, 0, 1), &roi, &roi, frame, 52_000_000, 0)).unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (2, 2));
        assert_eq!(grid.tiles.len(), 4);
        assert_eq!(grid.tiles[0].output, geom(0, 0, 500, 500));
        assert_eq!(grid.tiles[1].output, geom(0, 500, 500, 500));
        assert_eq!(grid.tiles[2].output, geom(500, 0, 500, 500));
        assert_eq!(grid.tiles[3].output, geom(500, 500, 500, 500));
        for tile in &grid.tiles {
            assert_eq!(tile.input, tile.output);
        }
    }

    #[test]
    fn aligned_tiles_land_on_the_grid() {
        // Same budget as the two-tile case, but align 16: width 500 rounds
        // down to (500 / 16) * 16 = 496. tiles_x = ceil(1000 / 496) = 3:
        // widths min(496, 1000 - tx * 496): 496, 496, 8.
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        let grid = tiled(decide(&req(5.0, 0, 16), &roi, &roi, frame, 7_200_000, 0)).unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (3, 1));
        assert_eq!(grid.tiles.len(), 3);
        for tile in &grid.tiles {
            assert_eq!(tile.input.x % 16, 0, "tile at {}", tile.input.x);
        }
        assert_eq!(grid.tiles[0].input, geom(0, 0, 496, 100));
        assert_eq!(grid.tiles[1].input, geom(496, 0, 496, 100));
        assert_eq!(grid.tiles[2].input, geom(992, 0, 8, 100));
    }

    #[test]
    fn overlap_widens_input_and_trims_leading_good_part() {
        // Same budget, overlap 8: tile width 500, stride 500 - 16 = 484.
        // tiles_x = ceil(1000 / 484) = 3.
        // tx0: input (0, 500), good (0, 500) — no leading trim.
        // tx1: input (484, 500), good (492, 492) — leading 8 trimmed.
        // tx2: input (968, 32), good (976, 24). 32 > 2 * 8: processed.
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        let grid = tiled(decide(&req(5.0, 8, 1), &roi, &roi, frame, 7_200_000, 0)).unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (3, 1));
        assert_eq!(grid.tiles.len(), 3);
        assert_eq!(grid.tiles[0].input, geom(0, 0, 500, 100));
        assert_eq!(grid.tiles[0].output, geom(0, 0, 500, 100));
        assert_eq!(grid.tiles[1].input, geom(484, 0, 500, 100));
        assert_eq!(grid.tiles[1].output, geom(492, 0, 492, 100));
        assert_eq!(grid.tiles[2].input, geom(968, 0, 32, 100));
        assert_eq!(grid.tiles[2].output, geom(976, 0, 24, 100));
    }

    #[test]
    fn narrow_end_tiles_are_skipped() {
        // Frame 100x100, one frame = 160_000 bytes, factor 5, overlap 8.
        // Budget 370_000: fits? 800_000 > 370_000: no.
        // available = 370_000 - 320_000 = 50_000; singlebuffer = 10_000.
        // scale = 10_000 / 160_000 = 0.0625 (< 0.333): both shrink by
        // sqrt(0.0625) = 0.25: 25x25. Square check: 3 * 8 = 24 < 25: kept.
        // Stride 25 - 16 = 9; counts ceil(100 / 9) = 12 per side.
        // Columns/rows 10..12 are 10 and 1 wide (<= 16 past the first):
        // skipped. 10x10 = 100 tiles stay; row/col 9 clamps to 19 wide
        // (100 - 9 * 9), the rest are full 25.
        let roi = geom(0, 0, 100, 100);
        let frame = 100 * 100 * BPP;
        let grid = tiled(decide(&req(5.0, 8, 1), &roi, &roi, frame, 370_000, 0)).unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (12, 12));
        assert_eq!(grid.tiles.len(), 100);
        for tile in &grid.tiles {
            assert!(tile.tx < 10 && tile.ty < 10);
            let expect_wd = if tile.tx < 9 { 25 } else { 19 };
            let expect_ht = if tile.ty < 9 { 25 } else { 19 };
            assert_eq!(
                (tile.input.width, tile.input.height),
                (expect_wd, expect_ht)
            );
        }
        assert_eq!(grid.tiles[0].input, geom(0, 0, 25, 25));
        assert_eq!(grid.tiles[0].output, geom(0, 0, 25, 25));
    }

    #[test]
    fn tiny_budget_gives_up_to_untiled() {
        // available hits zero, tiles shrink to 1px, 1000x100 positions top
        // MAX_TILES: upstream falls back to untiled processing, so do we.
        const { assert!(MAX_TILES == 10_000) };
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        assert_eq!(
            decide(&req(5.0, 0, 1), &roi, &roi, frame, 1_000, 0),
            TilingDecision::NoTiling
        );
    }

    #[test]
    fn mismatched_or_empty_regions_stay_untiled() {
        let roi = geom(0, 0, 100, 100);
        let frame = 100 * 100 * BPP;
        // Shape mismatch: the roi-variant path is B1-b work.
        let other = geom(0, 0, 50, 50);
        assert_eq!(
            decide(&req(5.0, 0, 1), &roi, &other, frame, 1_000, 0),
            TilingDecision::NoTiling
        );
        // Scale mismatch counts too (bitwise dispatch, tiling.c:1176).
        let rescaled = GeomRoi::new(0, 0, 100, 100, 0.5).unwrap();
        assert_eq!(
            decide(&req(5.0, 0, 1), &roi, &rescaled, frame, 1_000, 0),
            TilingDecision::NoTiling
        );
        // Empty regions have nothing to split.
        let empty = geom(0, 0, 0, 0);
        assert_eq!(
            decide(&req(5.0, 0, 1), &empty, &empty, 0, 1_000, 0),
            TilingDecision::NoTiling
        );
    }

    #[test]
    fn floor_below_quotient_changes_nothing() {
        // Same hand-computed case as `wide_frame_splits_into_two_x_tiles`
        // (singlebuffer 800_000): a 700_000 floor loses to the quotient.
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        let grid = tiled(decide(
            &req(5.0, 0, 1),
            &roi,
            &roi,
            frame,
            7_200_000,
            700_000,
        ))
        .unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (2, 1));
        assert_eq!(grid.tiles.len(), 2);
    }

    #[test]
    fn floor_above_quotient_grows_the_tile() {
        // Same case, but the floor (1_200_000) beats the quotient (800_000):
        // scale = 1_200_000 / 1_600_000 = 0.75, width = floor(1000 * 0.75)
        // = 750, stride 750, tiles_x = ceil(1000 / 750) = 2 with the last
        // tile clamped to 250.
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        let grid = tiled(decide(
            &req(5.0, 0, 1),
            &roi,
            &roi,
            frame,
            7_200_000,
            1_200_000,
        ))
        .unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (2, 1));
        assert_eq!(grid.tiles.len(), 2);
        assert_eq!(grid.tiles[0].input, geom(0, 0, 750, 100));
        assert_eq!(grid.tiles[1].input, geom(750, 0, 250, 100));
    }

    #[test]
    fn floor_covering_the_frame_yields_one_tile() {
        // A floor at the full frame size (1_600_000): scale = 1.0, no
        // shrink, one tile covering the frame.
        let roi = geom(0, 0, 1000, 100);
        let frame = 1000 * 100 * BPP;
        let grid = tiled(decide(
            &req(5.0, 0, 1),
            &roi,
            &roi,
            frame,
            7_200_000,
            1_600_000,
        ))
        .unwrap();
        assert_eq!((grid.tiles_x, grid.tiles_y), (1, 1));
        assert_eq!(grid.tiles.len(), 1);
        assert_eq!(grid.tiles[0].input, geom(0, 0, 1000, 100));
    }
}
