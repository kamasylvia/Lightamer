// SPDX-License-Identifier: GPL-3.0-or-later
//! Whole-chain streaming: strips and margin blocks.
//!
//! [`Pipe::render_stream`] renders chains whose frames exceed the single-frame
//! budget: memory holds one band or one block at a time, every band or block
//! runs the whole chain, and the pieces handed to the sink join back into the
//! same bytes the whole-frame entry would have produced. The two modes follow
//! Lumen RAW (`lumen/large_image.py`, `lumen/engine.py`; MIT, see `NOTICE`):
//!
//! - **Strips**: chains whose every module declares zero overlap stream in
//!   full-width bands of [`STRIP_ROWS`] rows (`large_image.py:10,38-39`).
//! - **Blocks**: chains with any spatial reach render in square blocks whose
//!   side is `sqrt(available * 0.25 / bytes_per_pixel) - 2 * margin`, clamped
//!   to [`BLOCK_MIN_SIDE`]..=[`BLOCK_MAX_SIDE`] (`block_size`,
//!   `large_image.py:143-148`). `margin` sums the chain's `overlap`
//!   declarations; each block's input grows by it on all four sides, runs the
//!   whole chain, and contributes its inner part (`process_region`,
//!   `engine.py:1342`), so blocks match the whole-frame render.
//!
//! Streaming never touches the plane cache (neither peek nor insert): a
//! streaming-size frame's planes exceed the cache byte cap anyway, and peeking
//! would let stream-vs-whole-frame bitwise tests pass without running the
//! streaming path. Refusals (geometry-changing, whole-image, or proxy-stats
//! modules; contradictory overlap claims) precede any allocation, like the
//! whole-frame footprint check.

use lightamer_geom::Roi as GeomRoi;
use lightamer_iop_traits::{
    ImageInfo, PipeState, Plane, PlaneMut, Roi as WireRoi, StatsNeeds, check_overlap_covers,
};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use std::fmt;
use std::time::Instant;

use super::budgeted::SharedFrame;
use super::chain::{
    ChainError, CommittedNode, ModuleLookup, NodeGeometry, PipeNode, backward_check, build_chain,
    format_from_wire, forward, from_wire, to_wire,
};
use super::negotiate::negotiate as negotiate_plan;
use super::render::{NodeReport, Pipe, RenderError, RenderRequest};

/// Strip height in rows for point-only chains (Lumen `STRIP_ROWS`,
/// `lumen/large_image.py:10`); the last strip takes the remainder.
pub const STRIP_ROWS: i64 = 64;

/// Block side clamp, low end (Lumen `block_size`, `lumen/large_image.py:148`).
pub const BLOCK_MIN_SIDE: u64 = 512;

/// Block side clamp, high end (Lumen `block_size`, `lumen/large_image.py:148`).
pub const BLOCK_MAX_SIDE: u64 = 8192;

/// Nominal bytes per pixel the block formula sizes against.
///
/// Lumen's `FRAME_BYTES` is 100 (measured 55-76 on a 61 MP frame,
/// `lumen/large_image.py:134-136`). Ours started at the same 100 and the
/// B1d-b calibration moved it to 150: three block-mode probings on a
/// synthetic blur-plus-gain chain (grown 1024/2048/4096, same 120 MP
/// frame, dropping sink) measured marginal high-water 145/144/158 bytes
/// per grown pixel, linear through the origin — the two working planes
/// plus the sink plane plus the blur's separable scratch plus allocator
/// retention. Real modules carry their own scratch, so their waves
/// re-measure on arrival.
///
/// Single-channel chains reuse this figure: it overestimates their working
/// set, which only cuts blocks smaller — safe, and re-measured when the
/// first spatial RAW module lands.
pub const STREAM_BYTES_PER_PIXEL: u64 = 150;

/// Which streaming shape a plan uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamMode {
    /// Every module's overlap is zero: full-width strips of [`STRIP_ROWS`].
    Strip,
    /// Some module reaches past its pixel: margin blocks (`block_side` below).
    Block,
}

/// Why a chain refuses streaming.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StreamRefusal {
    /// The module needs whole-image statistics.
    WholeImageStats,
    /// The module wants proxy statistics; the proxy leg is a later wave.
    ProxyStats {
        /// The long edge its declaration asked for.
        max_long_edge: u32,
    },
    /// The module changes geometry (not 1:1 at the same scale).
    GeometryChange {
        /// Which probe failed.
        detail: String,
    },
    /// The module's `overlap` does not cover its `roi_in` growth.
    OverlapMismatch {
        /// The claimed overlap against the measured growth.
        detail: String,
    },
    /// The module changes pixel format mid-chain.
    FormatChange {
        /// The declared input vs output formats.
        detail: String,
    },
}

impl fmt::Display for StreamRefusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StreamRefusal::WholeImageStats => write!(
                f,
                "needs whole-image statistics; streaming cannot serve it until the whole-frame fallback wave"
            ),
            StreamRefusal::ProxyStats { max_long_edge } => write!(
                f,
                "wants proxy statistics (long edge {max_long_edge}); the proxy leg lands with the first module that needs it"
            ),
            StreamRefusal::GeometryChange { detail } => write!(
                f,
                "changes geometry ({detail}); streaming needs 1:1 same-scale modules"
            ),
            StreamRefusal::OverlapMismatch { detail } => {
                write!(f, "claims an overlap its roi_in contradicts ({detail})")
            }
            StreamRefusal::FormatChange { detail } => write!(
                f,
                "changes pixel format ({detail}); streaming runs every node through one scratch pair"
            ),
        }
    }
}

/// One planned piece: the output it contributes and the input it reads.
#[derive(Debug, Clone, PartialEq)]
pub struct StreamPiecePlan {
    /// Output region this piece contributes, in final coordinates.
    pub output: GeomRoi,
    /// Input region this piece reads: the chain's back-projection of
    /// `output`, grown by the plan margin, clamped to the frame.
    pub input: GeomRoi,
    /// Horizontal grid position (strips always report 0).
    pub tx: u32,
    /// Vertical grid position.
    pub ty: u32,
}

/// How a plan lays out its pieces.
#[derive(Debug, Clone, Copy)]
enum PlanLayout {
    /// Full-width strips of [`STRIP_ROWS`] rows.
    Strip,
    /// Square blocks of `side`, `nx` across.
    Block {
        /// Block side in pixels.
        side: i64,
        /// Blocks across one row.
        nx: u64,
    },
}

/// A whole-chain streaming plan: a pure function of the chain, its
/// full-frame geometry, the budget, the frame, and the bytes-per-pixel
/// figure. Pieces iterate lazily ([`StreamPlan::pieces`]), so planning a huge
/// frame allocates no piece list.
#[derive(Debug)]
pub struct StreamPlan<'a> {
    /// Strip or block mode.
    pub mode: StreamMode,
    /// Summed chain overlap in pixels (the per-piece growth).
    pub margin: u64,
    /// The committed chain (for per-piece back-projection).
    chain: &'a [CommittedNode],
    /// The final output region.
    frame: GeomRoi,
    /// What grown inputs clamp to: the full head input, or the frame when the
    /// head needs no input (or the chain is empty).
    clamp_box: GeomRoi,
    /// Strip or block layout.
    layout: PlanLayout,
    /// Piece count.
    count: u64,
}

impl StreamPlan<'_> {
    /// How many pieces this plan holds.
    #[must_use]
    pub fn piece_count(&self) -> u64 {
        self.count
    }

    /// The plan's pieces in row-major order (Lumen's `for y … for x` order,
    /// `lumen/large_image.py:215-216`). Each item back-projects its output
    /// through the chain, so items can fail typed when a module answers a
    /// sub-region with a malformed region.
    #[must_use]
    pub fn pieces(&self) -> StreamPieceIter<'_> {
        StreamPieceIter {
            plan: self,
            index: 0,
        }
    }

    /// Computes piece `index` (row-major): output rect, back-projected head
    /// input, grown by the margin, clamped to the frame.
    fn piece_at(&self, index: u64) -> Result<StreamPiecePlan, RenderError> {
        let frame_fail = |detail: String| RenderError::Frame { detail };
        let fx = i64::from(self.frame.x);
        let fy = i64::from(self.frame.y);
        let fw = i64::from(self.frame.width);
        let fh = i64::from(self.frame.height);
        let (x, y, width, height, tx, ty) = match self.layout {
            PlanLayout::Strip => {
                let row = i64::try_from(index)
                    .map_err(|_| frame_fail(format!("strip index {index} overflows")))?;
                let y = fy.saturating_add(row.saturating_mul(STRIP_ROWS));
                let height = STRIP_ROWS.min(fy.saturating_add(fh).saturating_sub(y));
                let ty = u32::try_from(row)
                    .map_err(|_| frame_fail(format!("strip index {index} overflows")))?;
                (fx, y, fw, height, 0, ty)
            }
            PlanLayout::Block { side, nx } => {
                if nx == 0 {
                    return Err(frame_fail("block grid has no columns".to_owned()));
                }
                let col = i64::try_from(index % nx)
                    .map_err(|_| frame_fail(format!("block index {index} overflows")))?;
                let row = i64::try_from(index / nx)
                    .map_err(|_| frame_fail(format!("block index {index} overflows")))?;
                let x = fx.saturating_add(col.saturating_mul(side));
                let y = fy.saturating_add(row.saturating_mul(side));
                let width = side.min(fx.saturating_add(fw).saturating_sub(x));
                let height = side.min(fy.saturating_add(fh).saturating_sub(y));
                let tx = u32::try_from(col)
                    .map_err(|_| frame_fail(format!("block index {index} overflows")))?;
                let ty = u32::try_from(row)
                    .map_err(|_| frame_fail(format!("block index {index} overflows")))?;
                (x, y, width, height, tx, ty)
            }
        };
        let (Ok(x), Ok(y), Ok(width), Ok(height)) = (
            i32::try_from(x),
            i32::try_from(y),
            i32::try_from(width),
            i32::try_from(height),
        ) else {
            return Err(frame_fail(format!("stream piece {index} leaves its frame")));
        };
        let output = GeomRoi::new(x, y, width, height, self.frame.scale)
            .map_err(|err| frame_fail(format!("stream piece {index} rejected: {err}")))?;
        let head = if self.chain.is_empty() {
            output
        } else {
            let geos = forward(self.chain, &output).map_err(RenderError::Chain)?;
            let Some(first) = geos.first() else {
                return Err(RenderError::Chain(ChainError::LengthMismatch {
                    chain: self.chain.len(),
                    geos: 0,
                }));
            };
            first.input
        };
        // The back-projection covers the piece for admitted modules; the union
        // keeps that true even for a module whose regions wander by position.
        let base = if head.is_empty() {
            output
        } else {
            head.union(output)
                .map_err(|err| frame_fail(format!("stream piece {index} input: {err}")))?
        };
        // Huge margins saturate into the i32 range and then clamp to the
        // frame: no margin, however large, refuses the plan.
        let step = i64::try_from(self.margin).unwrap_or(i64::MAX);
        let gx = i64::from(base.x)
            .saturating_sub(step)
            .clamp(i64::from(i32::MIN), i64::from(i32::MAX));
        let gy = i64::from(base.y)
            .saturating_sub(step)
            .clamp(i64::from(i32::MIN), i64::from(i32::MAX));
        let gw = i64::from(base.width)
            .saturating_add(step.saturating_mul(2))
            .clamp(0, i64::from(i32::MAX));
        let gh = i64::from(base.height)
            .saturating_add(step.saturating_mul(2))
            .clamp(0, i64::from(i32::MAX));
        let (Ok(gx), Ok(gy), Ok(gw), Ok(gh)) = (
            i32::try_from(gx),
            i32::try_from(gy),
            i32::try_from(gw),
            i32::try_from(gh),
        ) else {
            return Err(frame_fail(format!("stream piece {index} input overflows")));
        };
        let grown = GeomRoi::new(gx, gy, gw, gh, base.scale)
            .map_err(|err| frame_fail(format!("stream piece {index} input rejected: {err}")))?;
        let input = grown
            .intersect(self.clamp_box)
            .map_err(|err| frame_fail(format!("stream piece {index} input: {err}")))?;
        if input.is_empty() {
            return Err(frame_fail(format!(
                "internal: stream piece {index} reads an empty input"
            )));
        }
        Ok(StreamPiecePlan {
            output,
            input,
            tx,
            ty,
        })
    }
}

/// Lazy row-major iterator over a [`StreamPlan`]'s pieces; see
/// [`StreamPlan::pieces`].
#[derive(Debug)]
pub struct StreamPieceIter<'a> {
    /// The plan being read.
    plan: &'a StreamPlan<'a>,
    /// Next piece index.
    index: u64,
}

impl Iterator for StreamPieceIter<'_> {
    type Item = Result<StreamPiecePlan, RenderError>;

    fn next(&mut self) -> Option<Result<StreamPiecePlan, RenderError>> {
        if self.index >= self.plan.count {
            return None;
        }
        let piece = self.plan.piece_at(self.index);
        self.index = self.index.saturating_add(1);
        Some(piece)
    }
}

/// One finished piece handed to the streaming sink.
#[derive(Debug)]
pub struct StreamPiece {
    /// Output extent this piece contributes.
    pub extent: FrameExtent,
    /// Budget-paired plane holding exactly `extent`, contiguously. Lent for
    /// the sink call: the sink copies out what it keeps.
    pub plane: SharedFrame,
}

/// What one streaming run did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StreamSummary {
    /// The mode the run planned.
    pub mode: StreamMode,
    /// Pieces handed to the sink (saturates at `u32::MAX`).
    pub pieces: u32,
}
/// Where streaming piece inputs come from: hand it an absolute input region,
/// get that region's pixels back as a compact frame.
///
/// [`Pipe::render_stream_from`] calls this once per planned piece input and
/// never holds a whole frame; sources that cannot serve a region fail typed,
/// which fails the run like any other piece error.
pub trait StreamInput {
    /// Fetches `region` (absolute frame coordinates) as a compact frame
    /// whose extent covers `region`.
    ///
    /// # Errors
    ///
    /// [`RenderError`] when the region is unservable.
    fn fetch_region(&self, region: FrameExtent) -> Result<Frame, RenderError>;
}

/// What one region-source streaming render needs: [`RenderRequest`] without
/// the whole input frame. Piece pixels arrive per planned input region from
/// a [`StreamInput`] instead, so the run never holds a whole frame.
pub struct StreamRequest<'a, L: ModuleLookup + ?Sized> {
    /// Nodes in execution order.
    pub nodes: &'a [PipeNode],
    /// Where committed modules come from, by id.
    pub lookup: &'a L,
    /// Decoded-image facts for `commit`.
    pub image: &'a ImageInfo,
    /// Wanted final output region.
    pub final_out: GeomRoi,
    /// Cancellation probe, consulted between pieces.
    pub cancel: &'a dyn Fn() -> bool,
}

impl<L: ModuleLookup + ?Sized> fmt::Debug for StreamRequest<'_, L> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("StreamRequest")
            .field("nodes", &self.nodes)
            .field("image", &self.image)
            .field("final_out", &self.final_out)
            .finish_non_exhaustive()
    }
}

/// Plans whole-chain streaming for `chain` at `frame`.
///
/// Admission first (stats declarations, geometry probes, overlap consistency),
/// then the mode (zero total margin: strips; anything else: blocks), then the
/// lazy piece list. Pure: touches neither the budget nor the cache, so every
/// refusal returns with both exactly as found.
///
/// # Errors
///
/// [`RenderError::StreamRefused`] for a module that cannot stream;
/// [`RenderError::Chain`] for a misaligned geometry slice;
/// [`RenderError::Frame`] for a zero bytes-per-pixel figure.
pub fn plan_stream<'a>(
    chain: &'a [CommittedNode],
    geos: &[NodeGeometry],
    budget_bytes: u64,
    frame: &GeomRoi,
    bytes_per_pixel: u64,
) -> Result<StreamPlan<'a>, RenderError> {
    if chain.len() != geos.len() {
        return Err(RenderError::Chain(ChainError::LengthMismatch {
            chain: chain.len(),
            geos: geos.len(),
        }));
    }
    if bytes_per_pixel == 0 {
        return Err(RenderError::Frame {
            detail: "streaming needs a positive bytes-per-pixel figure".to_owned(),
        });
    }
    let overlaps = admit(chain, geos, frame)?;
    let mut margin: u64 = 0;
    for overlap in overlaps {
        margin = margin.saturating_add(u64::from(overlap));
    }
    let fw = i64::from(frame.width);
    let fh = i64::from(frame.height);
    let (mode, layout, count) = if margin == 0 {
        (
            StreamMode::Strip,
            PlanLayout::Strip,
            ceil_div_u64(fh, STRIP_ROWS),
        )
    } else {
        let side = block_side(budget_bytes, margin, bytes_per_pixel);
        let side_i64 = i64::try_from(side).unwrap_or(i64::MAX);
        let nx = ceil_div_u64(fw, side_i64);
        let ny = ceil_div_u64(fh, side_i64);
        (
            StreamMode::Block,
            PlanLayout::Block { side: side_i64, nx },
            nx.saturating_mul(ny),
        )
    };
    let clamp_box = match geos.first() {
        Some(head) if !head.input.is_empty() => head.input,
        _ => *frame,
    };
    Ok(StreamPlan {
        mode,
        margin,
        chain,
        frame: *frame,
        clamp_box,
        layout,
        count,
    })
}

/// Ceiling division for non-negative dividends; zero or negative yields zero.
fn ceil_div_u64(num: i64, den: i64) -> u64 {
    if num <= 0 || den <= 0 {
        return 0;
    }
    let num = u64::try_from(num).unwrap_or(0);
    let den = u64::try_from(den).unwrap_or(1);
    num.saturating_add(den.saturating_sub(1)) / den
}

/// Block side for `margin` at `budget_bytes`: `sqrt(budget * 0.25 / bpp)`
/// minus twice the margin, clamped to
/// [`BLOCK_MIN_SIDE`]..=[`BLOCK_MAX_SIDE`]. Lumen `block_size`
/// (`lumen/large_image.py:143-148`); "available memory" here is the pipe's
/// budget, so plans are deterministic. Integer square root, floored like
/// Lumen's `int(sqrt(..))`.
fn block_side(budget_bytes: u64, margin: u64, bytes_per_pixel: u64) -> u64 {
    let quarter = budget_bytes / 4;
    let per = quarter / bytes_per_pixel.max(1);
    per.isqrt()
        .saturating_sub(margin.saturating_mul(2))
        .clamp(BLOCK_MIN_SIDE, BLOCK_MAX_SIDE)
}

/// Admits every node for streaming and collects its `overlap`.
///
/// Order per node: stats declaration, geometry probes (two interior regions
/// plus the full-frame geometry), overlap consistency. Nodes that need no
/// input skip the probes (there is no support region to check); empty frames
/// skip them too (nothing renders, but stats declarations still refuse).
fn admit(
    chain: &[CommittedNode],
    geos: &[NodeGeometry],
    frame: &GeomRoi,
) -> Result<Vec<u32>, RenderError> {
    let mut overlaps = Vec::with_capacity(chain.len());
    for (node, geo) in chain.iter().zip(geos.iter()) {
        match node.module.stats() {
            StatsNeeds::Local => {}
            StatsNeeds::WholeImage => {
                return refused(node, StreamRefusal::WholeImageStats);
            }
            StatsNeeds::Proxy { max_long_edge } => {
                return refused(node, StreamRefusal::ProxyStats { max_long_edge });
            }
        }
        let overlap = node
            .module
            .tiling(&node.data, &to_wire(&geo.input), &to_wire(&geo.output))
            .overlap;
        if geo.input.is_empty() || frame.is_empty() {
            overlaps.push(overlap);
            continue;
        }
        let small = probe_roi(frame, 16)?;
        let big = probe_roi(frame, 32)?;
        let growth_small = probe_growth(node, &small)?;
        let growth_big = probe_growth(node, &big)?;
        // Halo growth is region-independent; scaling grows with the region.
        if growth_small != growth_big {
            return refused(
                node,
                StreamRefusal::GeometryChange {
                    detail: format!(
                        "input growth changes with region size ({growth_small:?} vs {growth_big:?})"
                    ),
                },
            );
        }
        if !geo.input.contains(geo.output) {
            return refused(
                node,
                StreamRefusal::GeometryChange {
                    detail: format!(
                        "full-frame input {:?} does not cover its output {:?}",
                        geo.input, geo.output
                    ),
                },
            );
        }
        if growth_of(&geo.input, &geo.output) != growth_small {
            return refused(
                node,
                StreamRefusal::GeometryChange {
                    detail: "full-frame growth differs from probe growth".to_owned(),
                },
            );
        }
        if let Err(err) = check_overlap_covers(node.module.as_ref(), &node.data, &to_wire(&small)) {
            return refused(
                node,
                StreamRefusal::OverlapMismatch {
                    detail: err.to_string(),
                },
            );
        }
        overlaps.push(overlap);
    }
    Ok(overlaps)
}

/// Refuses `node` for streaming.
fn refused<T>(node: &CommittedNode, reason: StreamRefusal) -> Result<T, RenderError> {
    Err(RenderError::StreamRefused {
        id: node.id.clone(),
        reason,
    })
}

/// A centered `edge`-sided square probe inside `frame` (capped to the frame).
fn probe_roi(frame: &GeomRoi, edge: i32) -> Result<GeomRoi, RenderError> {
    let fail = |detail: String| RenderError::Frame { detail };
    let side = edge.min(frame.width).min(frame.height);
    if side <= 0 {
        return Err(fail(format!(
            "stream probe needs a non-empty frame, got {frame:?}"
        )));
    }
    let x = i64::from(frame.x) + i64::from(frame.width - side) / 2;
    let y = i64::from(frame.y) + i64::from(frame.height - side) / 2;
    let (Ok(x), Ok(y)) = (i32::try_from(x), i32::try_from(y)) else {
        return Err(fail(format!("stream probe origin ({x},{y}) overflows")));
    };
    GeomRoi::new(x, y, side, side, frame.scale)
        .map_err(|err| fail(format!("stream probe rejected: {err}")))
}

/// Probes one node at `probe`: validates its regions, requires equal scales
/// and 1:1-plus-halo containment, and returns the per-side growth.
fn probe_growth(node: &CommittedNode, probe: &GeomRoi) -> Result<[i64; 4], RenderError> {
    let wire = to_wire(probe);
    let rin = from_wire(&node.module.roi_in(&node.data, wire)).map_err(|detail| {
        RenderError::Chain(ChainError::BadRoi {
            id: node.id.clone(),
            detail,
        })
    })?;
    let rout = from_wire(&node.module.roi_out(&node.data, wire)).map_err(|detail| {
        RenderError::Chain(ChainError::BadRoi {
            id: node.id.clone(),
            detail,
        })
    })?;
    let scale = probe.scale.to_bits();
    if rin.scale.to_bits() != scale || rout.scale.to_bits() != scale {
        return refused(
            node,
            StreamRefusal::GeometryChange {
                detail: "regions change scale".to_owned(),
            },
        );
    }
    if !rin.contains(*probe) {
        return refused(
            node,
            StreamRefusal::GeometryChange {
                detail: format!("roi_in {rin:?} does not cover its output {probe:?}"),
            },
        );
    }
    if !probe.contains(rout) {
        return refused(
            node,
            StreamRefusal::GeometryChange {
                detail: format!("roi_out {rout:?} escapes its input {probe:?}"),
            },
        );
    }
    Ok(growth_of(&rin, probe))
}

/// Per-side growth of `outer` past `inner`: left, top, right, bottom.
fn growth_of(outer: &GeomRoi, inner: &GeomRoi) -> [i64; 4] {
    [
        i64::from(inner.x) - i64::from(outer.x),
        i64::from(inner.y) - i64::from(outer.y),
        i64::from(outer.x) + i64::from(outer.width) - i64::from(inner.x) - i64::from(inner.width),
        i64::from(outer.y) + i64::from(outer.height) - i64::from(inner.y) - i64::from(inner.height),
    ]
}

/// Scratch state one streaming run reuses across its pieces: two compact
/// working planes plus the pixel room they currently hold.
struct StreamScratch {
    /// First working plane.
    a: SharedFrame,
    /// Second working plane.
    b: SharedFrame,
    /// Pixel room both planes hold: width, height.
    room: (u32, u32),
}

/// Grows the run's scratch pair to `gw` by `gh` when it does not fit already.
/// Drops the old pair first, so its budget returns before the new pair
/// charges. Evicts unhit cache entries like any other allocation; streaming
/// protects none, since it never peeks the cache.
fn ensure_stream_room(
    pipe: &mut Pipe,
    scratch: &mut Option<StreamScratch>,
    gw: u32,
    gh: u32,
    format: PixelFormat,
) -> Result<(), RenderError> {
    let fits = scratch.as_ref().is_some_and(|pair| {
        pair.a.frame.format() == format && pair.room.0 >= gw && pair.room.1 >= gh
    });
    if fits {
        return Ok(());
    }
    *scratch = None;
    let extent = FrameExtent::new(0, 0, gw, gh);
    let a = pipe.stream_alloc(extent, format, "stream scratch")?;
    let b = pipe.stream_alloc(extent, format, "stream scratch")?;
    *scratch = Some(StreamScratch {
        a,
        b,
        room: (gw, gh),
    });
    Ok(())
}

/// Stages the grown input `g` from the caller's frame into the scratch head,
/// packed compactly (`gw` by `gh`).
fn stage_piece_input(
    input: &Frame,
    g: &FrameExtent,
    scratch: &mut SharedFrame,
    gw: u32,
    gh: u32,
) -> Result<(), RenderError> {
    let fail = |detail: String| RenderError::Frame { detail };
    let view = input
        .view(*g)
        .map_err(|err| fail(format!("stream input view unreadable: {err}")))?;
    let channels = scratch.frame.format().channel_count();
    let lane_mul = usize::try_from(channels)
        .ok()
        .ok_or_else(|| fail("stream piece width overflows".to_owned()))?;
    let gw_lanes = usize::try_from(gw)
        .ok()
        .and_then(|width| width.checked_mul(lane_mul))
        .ok_or_else(|| fail("stream piece width overflows".to_owned()))?;
    let rows = usize::try_from(gh)
        .ok()
        .ok_or_else(|| fail("stream piece".to_owned()))?;
    let need = gw_lanes
        .checked_mul(rows)
        .ok_or_else(|| fail("stream piece rows overflow".to_owned()))?;
    let sub = scratch
        .frame
        .as_mut_slice()
        .get_mut(0..need)
        .ok_or_else(|| fail("stream scratch smaller than its piece".to_owned()))?;
    let mut staging = PlaneMut::from_slice_channels(sub, gw, gh, gw_lanes, channels)
        .map_err(|err| fail(format!("{err}")))?;
    for row in 0..gh {
        let src = view
            .row(row)
            .map_err(|err| fail(format!("stream input row {row} unreadable: {err}")))?;
        let dst = staging
            .row_mut(row)
            .map_err(|err| fail(format!("stream staging row {row} unwritable: {err}")))?;
        if dst.len() != src.len() {
            return Err(fail(format!("stream staging row {row} lengths disagree")));
        }
        dst.copy_from_slice(src);
    }
    Ok(())
}

/// Crops the piece `p` out of the grown result `result` (compact `grown`
/// pixels) into the sink plane `out`.
fn crop_piece_output(
    result: &Frame,
    grown: &GeomRoi,
    piece: &GeomRoi,
    out: &mut Frame,
) -> Result<(), RenderError> {
    let fail = |detail: String| RenderError::Frame { detail };
    let ox = i64::from(piece.x) - i64::from(grown.x);
    let oy = i64::from(piece.y) - i64::from(grown.y);
    let (Ok(ox), Ok(oy)) = (u32::try_from(ox), u32::try_from(oy)) else {
        return Err(fail(
            "stream piece starts before its grown input".to_owned(),
        ));
    };
    let gw =
        u32::try_from(grown.width).map_err(|_| fail("stream grown width overflows".to_owned()))?;
    let pw =
        u32::try_from(piece.width).map_err(|_| fail("stream piece width overflows".to_owned()))?;
    let ph = u32::try_from(piece.height)
        .map_err(|_| fail("stream piece height overflows".to_owned()))?;
    let channels = usize::try_from(result.format().channel_count())
        .ok()
        .ok_or_else(|| fail("stream piece".to_owned()))?;
    let gw_lanes = usize::try_from(gw)
        .ok()
        .and_then(|width| width.checked_mul(channels))
        .ok_or_else(|| fail("stream grown width overflows".to_owned()))?;
    let ox_lanes = usize::try_from(ox)
        .ok()
        .and_then(|off| off.checked_mul(channels))
        .ok_or_else(|| fail("stream piece offset overflows".to_owned()))?;
    let pw_lanes = usize::try_from(pw)
        .ok()
        .and_then(|width| width.checked_mul(channels))
        .ok_or_else(|| fail("stream piece width overflows".to_owned()))?;
    let oy_n = usize::try_from(oy)
        .ok()
        .ok_or_else(|| fail("stream piece".to_owned()))?;
    let pixels = result.as_slice();
    for row in 0..ph {
        let src_row = oy_n
            .checked_add(usize::try_from(row).unwrap_or(usize::MAX))
            .ok_or_else(|| fail("stream piece rows overflow".to_owned()))?;
        let start = src_row
            .checked_mul(gw_lanes)
            .and_then(|base| base.checked_add(ox_lanes))
            .ok_or_else(|| fail("stream piece rows overflow".to_owned()))?;
        let end = start
            .checked_add(pw_lanes)
            .ok_or_else(|| fail("stream piece rows overflow".to_owned()))?;
        let seg = pixels
            .get(start..end)
            .ok_or_else(|| fail("stream piece leaves its grown result".to_owned()))?;
        let dst = out
            .row_mut(row)
            .map_err(|err| fail(format!("stream piece row {row} unwritable: {err}")))?;
        if dst.len() != seg.len() {
            return Err(fail(format!("stream piece row {row} lengths disagree")));
        }
        dst.copy_from_slice(seg);
    }
    Ok(())
}

/// Per-node totals for [`Pipe::last_trace`]: misses across the run's pieces.
fn trace_totals(chain: &[CommittedNode], calls: &[u32], millis: &[f64]) -> Vec<NodeReport> {
    chain
        .iter()
        .enumerate()
        .map(|(index, node)| NodeReport {
            id: node.id.clone(),
            multi: node.multi,
            hit: false,
            process_calls: calls.get(index).copied().unwrap_or(0),
            millis: millis.get(index).copied().unwrap_or(0.0),
        })
        .collect()
}

/// One piece's run inputs, bundled so the piece runner takes two arguments.
struct PieceJob<'a, F>
where
    F: FnMut(StreamPiece) -> Result<(), RenderError>,
{
    /// Where this piece's grown input comes from.
    source: &'a dyn StreamInput,
    /// The committed chain.
    chain: &'a [CommittedNode],
    /// The piece to run.
    piece: &'a StreamPiecePlan,
    /// Whether the chain head needs no input.
    head_empty: bool,
    /// Pixel format of the scratch pair and sink planes: the input format
    /// (streaming refuses chains that change it, so one format serves all).
    format: PixelFormat,
    /// This piece's working chain state, seeded from the commit phase.
    state: &'a mut PipeState,
    /// The run's reused scratch pair.
    scratch: &'a mut Option<StreamScratch>,
    /// Per-node `process` call totals to bump.
    calls: &'a mut [u32],
    /// Per-node millisecond totals to bump.
    millis: &'a mut [f64],
    /// The run's sink.
    sink: &'a mut F,
}

/// [`StreamInput`] over one in-RAM frame: [`Pipe::render_stream`]'s view of
/// its whole input. Regions outside the frame refuse typed, like the piece
/// runner's own coverage check did before the region-source entry landed.
struct WholeFrameInput<'a> {
    /// The caller's whole input frame.
    frame: &'a Frame,
}

impl StreamInput for WholeFrameInput<'_> {
    fn fetch_region(&self, region: FrameExtent) -> Result<Frame, RenderError> {
        let fail = |detail: String| RenderError::Frame { detail };
        let have = self.frame.extent();
        if !have.contains(region) {
            return Err(RenderError::InputMismatch {
                detail: format!("stream piece needs input at {region:?}, caller gave {have:?}"),
            });
        }
        let view = self
            .frame
            .view(region)
            .map_err(|err| fail(format!("stream input view unreadable: {err}")))?;
        let mut cropped = Frame::alloc(region, self.frame.format())
            .map_err(|err| fail(format!("stream input crop would not build: {err}")))?;
        for row in 0..region.height {
            let src = view
                .row(row)
                .map_err(|err| fail(format!("stream input row {row} unreadable: {err}")))?;
            let dst = cropped
                .row_mut(row)
                .map_err(|err| fail(format!("stream crop row {row} unwritable: {err}")))?;
            if dst.len() != src.len() {
                return Err(fail(format!("stream crop row {row} lengths disagree")));
            }
            dst.copy_from_slice(src);
        }
        Ok(cropped)
    }
}

impl Pipe {
    /// Runs one piece: fetches the grown input from the source, runs the
    /// whole chain through the reused scratch pair, crops the piece into
    /// a sink plane, and calls the sink.
    fn run_stream_piece<F>(&mut self, job: PieceJob<'_, F>) -> Result<(), RenderError>
    where
        F: FnMut(StreamPiece) -> Result<(), RenderError>,
    {
        let PieceJob {
            source,
            chain,
            piece,
            head_empty,
            format,
            state,
            scratch,
            calls,
            millis,
            sink,
        } = job;
        let frame_fail = |detail: String| RenderError::Frame { detail };
        let gw = u32::try_from(piece.input.width)
            .map_err(|_| frame_fail("stream grown width overflows".to_owned()))?;
        let gh = u32::try_from(piece.input.height)
            .map_err(|_| frame_fail("stream grown height overflows".to_owned()))?;
        let grown = FrameExtent::new(piece.input.x, piece.input.y, gw, gh);
        ensure_stream_room(self, scratch, gw, gh, format)?;
        let Some(pair) = scratch.as_mut() else {
            return Err(frame_fail("internal: stream scratch missing".to_owned()));
        };
        if !head_empty {
            let got = source.fetch_region(grown)?;
            stage_piece_input(&got, &grown, &mut pair.a, gw, gh)?;
        }
        let grown_wire = to_wire(&piece.input);
        let empty_wire = WireRoi::new(0, 0, 0, 0, piece.input.scale);
        let channels = format.channel_count();
        let lane_mul = usize::try_from(channels)
            .ok()
            .ok_or_else(|| frame_fail("stream grown width overflows".to_owned()))?;
        let stride = usize::try_from(gw)
            .ok()
            .and_then(|width| width.checked_mul(lane_mul))
            .ok_or_else(|| frame_fail("stream grown width overflows".to_owned()))?;
        let rows = usize::try_from(gh)
            .ok()
            .ok_or_else(|| frame_fail("stream grown height overflows".to_owned()))?;
        let row_len = stride
            .checked_mul(rows)
            .ok_or_else(|| frame_fail("stream grown rows overflow".to_owned()))?;
        let no_pixels: &[f32] = &[];
        for (index, node) in chain.iter().enumerate() {
            let started = Instant::now();
            let first_without_input = index == 0 && head_empty;
            let rin = if first_without_input {
                empty_wire
            } else {
                grown_wire
            };
            let in_plane = if first_without_input {
                Plane::from_slice_channels(no_pixels, 0, 0, 0, channels)
                    .map_err(|err| frame_fail(format!("{err}")))?
            } else {
                let sub = pair.a.frame.as_slice().get(0..row_len).ok_or_else(|| {
                    frame_fail("stream scratch smaller than its piece".to_owned())
                })?;
                Plane::from_slice_channels(sub, gw, gh, stride, channels)
                    .map_err(|err| frame_fail(format!("{err}")))?
            };
            let out_sub = pair
                .b
                .frame
                .as_mut_slice()
                .get_mut(0..row_len)
                .ok_or_else(|| frame_fail("stream scratch smaller than its piece".to_owned()))?;
            let mut out_plane = PlaneMut::from_slice_channels(out_sub, gw, gh, stride, channels)
                .map_err(|err| frame_fail(format!("{err}")))?;
            node.module
                .process(
                    &node.data,
                    &in_plane,
                    &mut out_plane,
                    rin,
                    grown_wire,
                    state,
                )
                .map_err(|source| RenderError::Node {
                    id: node.id.clone(),
                    tile: Some((piece.tx, piece.ty)),
                    source,
                })?;
            if let Some(slot) = calls.get_mut(index) {
                *slot = slot.saturating_add(1);
            }
            if let Some(slot) = millis.get_mut(index) {
                *slot += started.elapsed().as_secs_f64() * 1000.0;
            }
            std::mem::swap(&mut pair.a, &mut pair.b);
        }
        // Every node reads head `a` and writes head `b`, then the pair swaps:
        // the finished grown piece always sits in `a`.
        self.emit_stream_piece(piece, &pair.a.frame, sink)
    }

    /// Crops the finished grown result into a sink plane and calls the sink.
    fn emit_stream_piece<F>(
        &mut self,
        piece: &StreamPiecePlan,
        grown: &Frame,
        sink: &mut F,
    ) -> Result<(), RenderError>
    where
        F: FnMut(StreamPiece) -> Result<(), RenderError>,
    {
        let frame_fail = |detail: String| RenderError::Frame { detail };
        let pw = u32::try_from(piece.output.width)
            .map_err(|_| frame_fail("stream piece width overflows".to_owned()))?;
        let ph = u32::try_from(piece.output.height)
            .map_err(|_| frame_fail("stream piece height overflows".to_owned()))?;
        let out_extent = FrameExtent::new(piece.output.x, piece.output.y, pw, ph);
        let mut sink_plane = self.stream_alloc(out_extent, grown.format(), "stream piece")?;
        crop_piece_output(grown, &piece.input, &piece.output, &mut sink_plane.frame)?;
        sink(StreamPiece {
            extent: out_extent,
            plane: sink_plane,
        })?;
        Ok(())
    }

    /// Renders `req` piece by piece, handing each finished piece to `sink`.
    ///
    /// The request is the whole-frame one ([`RenderRequest`]); `sink` runs
    /// once per strip or block, in row-major order, and reports its own
    /// failures (a spill sink's disk errors) through [`RenderError`]. The
    /// sink plane is lent for the call: the sink copies out what it keeps.
    ///
    /// Order: commit → forward geometry → backward check → format plan (any
    /// conversion step is [`RenderError::ColorGap`]) → admission and planning
    /// ([`plan_stream`], refusals before anything allocates) → per piece:
    /// cancel check, fetch the grown input, run the whole chain through two
    /// reused scratch planes, crop the piece into a sink plane, call the sink.
    /// There is no footprint pre-check: oversized frames are why streaming
    /// exists. Every allocation still charges the budget, and a piece that
    /// does not fit fails typed ([`RenderError::OutOfBudget`]).
    ///
    /// The cache sits untouched (no peeks, no inserts): streaming-size planes
    /// exceed its byte cap, and peeking would let bitwise tests pass without
    /// exercising this path. Cancel or any error drops the run's scratch
    /// (budget back) and leaves per-node partial counts in `last_trace`; an
    /// empty chain copies its input piece by piece; a chain whose head needs
    /// no input feeds its first node empty planes, like the whole-frame run.
    ///
    /// # Errors
    ///
    /// [`RenderError`] for every failure above; see its variants.
    pub fn render_stream<L, F>(
        &mut self,
        req: &RenderRequest<'_, L>,
        sink: F,
    ) -> Result<StreamSummary, RenderError>
    where
        L: ModuleLookup,
        F: FnMut(StreamPiece) -> Result<(), RenderError>,
    {
        let whole = WholeFrameInput { frame: req.input };
        let from = StreamRequest {
            nodes: req.nodes,
            lookup: req.lookup,
            image: req.image,
            final_out: req.final_out,
            cancel: req.cancel,
        };
        self.render_stream_from(&from, &whole, sink)
    }

    /// Renders `req` piece by piece, fetching each grown input from `source`
    /// and handing each finished piece to `sink`.
    ///
    /// The request carries no pixels ([`StreamRequest`]); `source` runs once
    /// per planned piece input, in row-major piece order, and `sink` runs
    /// once per strip or block, reporting its own failures (a spill sink's
    /// disk errors) through [`RenderError`]. The sink plane is lent for the
    /// call: the sink copies out what it keeps.
    ///
    /// Order: commit → forward geometry → backward check → format plan (any
    /// conversion step is [`RenderError::ColorGap`]) → admission and planning
    /// ([`plan_stream`], refusals before anything allocates) → per piece:
    /// cancel check, fetch the grown input from `source`, run the whole
    /// chain through two reused scratch planes, crop the piece into a sink
    /// plane, call the sink. There is no footprint pre-check: oversized
    /// frames are why streaming exists. Every allocation still charges the
    /// budget, and a piece that does not fit fails typed
    /// ([`RenderError::OutOfBudget`]).
    ///
    /// The cache sits untouched (no peeks, no inserts): streaming-size planes
    /// exceed its byte cap, and peeking would let bitwise tests pass without
    /// exercising this path. Cancel or any error drops the run's scratch
    /// (budget back) and leaves per-node partial counts in `last_trace`; an
    /// empty chain copies its input piece by piece; a chain whose head needs
    /// no input never calls `source` and feeds its first node empty planes,
    /// like the whole-frame run.
    ///
    /// # Errors
    ///
    /// [`RenderError`] for every failure above, including the source's own
    /// region refusals; see its variants.
    pub fn render_stream_from<L, F>(
        &mut self,
        req: &StreamRequest<'_, L>,
        source: &dyn StreamInput,
        mut sink: F,
    ) -> Result<StreamSummary, RenderError>
    where
        L: ModuleLookup,
        F: FnMut(StreamPiece) -> Result<(), RenderError>,
    {
        if (req.cancel)() {
            return Err(RenderError::Cancelled);
        }
        self.set_last_trace(Vec::new());
        let mut commit_state = PipeState::from_image(req.image);
        let chain = build_chain(req.lookup, req.nodes, req.image, &mut commit_state)
            .map_err(RenderError::Chain)?;
        let full_geos = if chain.is_empty() {
            Vec::new()
        } else {
            let geos = forward(&chain, &req.final_out).map_err(RenderError::Chain)?;
            let first = geos
                .first()
                .ok_or(RenderError::Chain(ChainError::LengthMismatch {
                    chain: chain.len(),
                    geos: 0,
                }))?;
            backward_check(&chain, &geos, &first.input).map_err(RenderError::Chain)?;
            if let Some(step) = negotiate_plan(&chain).steps.first() {
                return Err(RenderError::ColorGap {
                    after: step.after,
                    from: step.from,
                    to: step.to,
                });
            }
            geos
        };
        // One scratch pair serves the whole chain, so every node must keep
        // the input format; a node that changes it refuses here, before
        // anything allocates.
        let mut running = req.image.format;
        for node in &chain {
            let out = node.module.output_format(running);
            if out != running {
                return refused(
                    node,
                    StreamRefusal::FormatChange {
                        detail: format!("{running:?} in, {out:?} out"),
                    },
                );
            }
            running = out;
        }
        let format = format_from_wire(req.image.format);
        let plan = plan_stream(
            &chain,
            &full_geos,
            self.budget().cap(),
            &req.final_out,
            STREAM_BYTES_PER_PIXEL,
        )?;
        let head_empty = matches!(full_geos.first(), Some(head) if head.input.is_empty());
        let mut calls = vec![0u32; chain.len()];
        let mut millis = vec![0.0f64; chain.len()];
        let mut scratch: Option<StreamScratch> = None;
        let mut done: u64 = 0;
        let mut outcome: Result<(), RenderError> = Ok(());
        for piece_result in plan.pieces() {
            let piece = match piece_result {
                Ok(piece) => piece,
                Err(err) => {
                    outcome = Err(err);
                    break;
                }
            };
            if (req.cancel)() {
                outcome = Err(RenderError::Cancelled);
                break;
            }
            // Every piece runs the whole chain from the commit phase's value:
            // pieces never see each other's processing.
            let mut piece_state = commit_state;
            piece_state.set_input(req.image.format);
            let step = self.run_stream_piece(PieceJob {
                source,
                chain: &chain,
                piece: &piece,
                head_empty,
                format,
                state: &mut piece_state,
                scratch: &mut scratch,
                calls: &mut calls,
                millis: &mut millis,
                sink: &mut sink,
            });
            match step {
                Ok(()) => {
                    done = done.saturating_add(1);
                }
                Err(err) => {
                    outcome = Err(err);
                    break;
                }
            }
        }
        self.set_last_trace(trace_totals(&chain, &calls, &millis));
        outcome?;
        Ok(StreamSummary {
            mode: plan.mode,
            pieces: u32::try_from(done).unwrap_or(u32::MAX),
        })
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::sync::Arc;
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use lightamer_geom::Roi as GeomRoi;
    use lightamer_iop_traits::{ColorSpace, ImageInfo, PipeState};
    use lightamer_raster::{Frame, FrameExtent, PixelFormat};
    use serde_json::json;

    use super::{
        STREAM_BYTES_PER_PIXEL, StreamInput, StreamMode, StreamPiece, StreamRefusal, StreamRequest,
        plan_stream,
    };
    use crate::chain::{CommittedNode, NodeGeometry, PipeNode, build_chain, forward};
    use crate::fakes::{
        FakeBackendFail, FakeBlur, FakeCopy, FakeGain, FakeGrow, FakePosition, FakeProxy,
        FakeScale, FakeSource, FakeSpin, FakeStateReader, FakeStateWriter, FakeWhole, Probe,
        no_params, table,
    };
    use crate::kinds::PipeKind;
    use crate::render::{Pipe, RenderError, RenderRequest};

    const GIB: u64 = 1024 * 1024 * 1024;

    fn image() -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Rgb)
    }

    fn geom(x: i32, y: i32, w: i32, h: i32) -> GeomRoi {
        GeomRoi::new(x, y, w, h, 1.0).unwrap()
    }

    fn node(id: &str) -> PipeNode {
        PipeNode {
            id: id.to_owned(),
            multi: 0,
            params: no_params(),
        }
    }

    fn gain_node(id: &str, gain: f64) -> PipeNode {
        let mut params = no_params();
        params.insert("gain".to_owned(), json!({"type": "float", "value": gain}));
        PipeNode {
            id: id.to_owned(),
            multi: 0,
            params,
        }
    }

    #[expect(clippy::cast_precision_loss)] // test frames are small; the conversion is exact
    fn pattern_frame(w: u32, h: u32) -> Frame {
        let len = w as usize * h as usize * 4;
        let buf: Vec<f32> = (0..len).map(|i| i as f32 * 0.125 - 3.0).collect();
        Frame::from_parts(
            buf,
            FrameExtent::new(0, 0, w, h),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap()
    }

    /// Commits `nodes` and walks the full-frame geometry to `final_out`.
    fn committed(
        lookup: &impl crate::chain::ModuleLookup,
        nodes: &[PipeNode],
        final_out: &GeomRoi,
    ) -> (Vec<CommittedNode>, Vec<NodeGeometry>) {
        let chain = build_chain(
            lookup,
            nodes,
            &image(),
            &mut PipeState::from_image(&image()),
        )
        .unwrap();
        let geos = forward(&chain, final_out).unwrap();
        (chain, geos)
    }

    /// Streams `req` on `pipe`, assembling pieces into one frame.
    fn stream_assembled(
        pipe: &mut Pipe,
        req: &RenderRequest<'_, impl crate::chain::ModuleLookup>,
    ) -> (super::StreamSummary, Frame) {
        let extent = FrameExtent::new(
            req.final_out.x,
            req.final_out.y,
            u32::try_from(req.final_out.width).unwrap(),
            u32::try_from(req.final_out.height).unwrap(),
        );
        let mut out = Frame::alloc(extent, PixelFormat::RgbaF32Premul).unwrap();
        let summary = pipe
            .render_stream(req, |piece: StreamPiece| {
                let src = piece.plane.frame.as_slice();
                let ox = usize::try_from(piece.extent.x - extent.x).unwrap();
                let oy = usize::try_from(piece.extent.y - extent.y).unwrap();
                for row in 0..piece.extent.height as usize {
                    let seg = &src[row * piece.extent.width as usize * 4
                        ..(row + 1) * piece.extent.width as usize * 4];
                    let dst_row = u32::try_from(oy + row).unwrap();
                    let dst = out.row_mut(dst_row).unwrap();
                    dst[ox * 4..ox * 4 + seg.len()].copy_from_slice(seg);
                }
                Ok(())
            })
            .unwrap();
        (summary, out)
    }
    /// Streams `req` from `source` on `pipe`, assembling pieces into one frame.
    fn stream_from_assembled(
        pipe: &mut Pipe,
        req: &StreamRequest<'_, impl crate::chain::ModuleLookup>,
        source: &dyn StreamInput,
    ) -> (super::StreamSummary, Frame) {
        let extent = FrameExtent::new(
            req.final_out.x,
            req.final_out.y,
            u32::try_from(req.final_out.width).unwrap(),
            u32::try_from(req.final_out.height).unwrap(),
        );
        let mut out = Frame::alloc(extent, PixelFormat::RgbaF32Premul).unwrap();
        let summary = pipe
            .render_stream_from(req, source, |piece: StreamPiece| {
                let src = piece.plane.frame.as_slice();
                let ox = usize::try_from(piece.extent.x - extent.x).unwrap();
                let oy = usize::try_from(piece.extent.y - extent.y).unwrap();
                for row in 0..piece.extent.height as usize {
                    let seg = &src[row * piece.extent.width as usize * 4
                        ..(row + 1) * piece.extent.width as usize * 4];
                    let dst_row = u32::try_from(oy + row).unwrap();
                    let dst = out.row_mut(dst_row).unwrap();
                    dst[ox * 4..ox * 4 + seg.len()].copy_from_slice(seg);
                }
                Ok(())
            })
            .unwrap();
        (summary, out)
    }

    /// [`StreamInput`] over one in-RAM frame, recording every region served.
    struct RecordedRegions<'a> {
        frame: &'a Frame,
        regions: std::sync::Mutex<Vec<FrameExtent>>,
    }

    impl StreamInput for RecordedRegions<'_> {
        fn fetch_region(&self, region: FrameExtent) -> Result<Frame, RenderError> {
            if let Ok(mut held) = self.regions.lock() {
                held.push(region);
            }
            super::WholeFrameInput { frame: self.frame }.fetch_region(region)
        }
    }

    #[test]
    fn strip_plan_counts_bands_and_takes_the_remainder() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let nodes = vec![node("mod_a")];
        let frame = geom(0, 0, 100, 150);
        let (chain, geos) = committed(&lookup, &nodes, &frame);
        let plan = plan_stream(&chain, &geos, GIB, &frame, STREAM_BYTES_PER_PIXEL).unwrap();
        assert_eq!(plan.mode, StreamMode::Strip);
        assert_eq!(plan.margin, 0);
        assert_eq!(plan.piece_count(), 3);
        let pieces: Vec<_> = plan.pieces().collect::<Result<_, _>>().unwrap();
        assert_eq!(pieces.len(), 3);
        // Heights 64, 64, and the 22-row remainder; zero margin reads back
        // exactly what each band contributes.
        for (piece, (ty, y, height)) in pieces.iter().zip([(0, 0, 64), (1, 64, 64), (2, 128, 22)]) {
            assert_eq!((piece.tx, piece.ty), (0, ty));
            assert_eq!(piece.output, geom(0, y, 100, height));
            assert_eq!(piece.input, piece.output);
        }
    }

    #[test]
    fn block_plan_grows_inputs_by_the_summed_margin() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe))),
            Arc::new(FakeBlur::new("mod_blur", Arc::clone(&probe), 8, 8)),
        ]);
        let nodes = vec![node("mod_a"), node("mod_blur")];
        let frame = geom(0, 0, 8000, 7000);
        let (chain, geos) = committed(&lookup, &nodes, &frame);
        // sqrt(5_184_000_000 / 4 / 150) = sqrt(8640000) = 2939
        // (2939^2 = 8637721); minus 2*8 = 2923, so 3x3 blocks.
        let plan =
            plan_stream(&chain, &geos, 5_184_000_000, &frame, STREAM_BYTES_PER_PIXEL).unwrap();
        assert_eq!(plan.mode, StreamMode::Block);
        assert_eq!(plan.margin, 8);
        assert_eq!(plan.piece_count(), 9);
        let pieces: Vec<_> = plan.pieces().collect::<Result<_, _>>().unwrap();
        assert_eq!(pieces.len(), 9);
        // Corner block: grown by 8, clamped to the frame origin.
        assert_eq!(pieces[0].output, geom(0, 0, 2923, 2923));
        assert_eq!(pieces[0].input, geom(0, 0, 2931, 2931));
        // Top-edge block: clamped vertically only.
        assert_eq!(pieces[1].output, geom(2923, 0, 2923, 2923));
        assert_eq!(pieces[1].input, geom(2915, 0, 2939, 2931));
        // Middle block: grown on all four sides.
        assert_eq!(pieces[4].output, geom(2923, 2923, 2923, 2923));
        assert_eq!(pieces[4].input, geom(2915, 2915, 2939, 2939));
        // Bottom-right block: partial on both axes.
        assert_eq!(pieces[8].output, geom(5846, 5846, 2154, 1154));
        assert_eq!(pieces[8].input, geom(5838, 5838, 2162, 1162));
    }

    #[test]
    fn block_side_clamps_both_ends_and_huge_margins_plan_fine() {
        let lookup = table(vec![Arc::new(FakeBlur::new(
            "mod_blur",
            Arc::new(Probe::new()),
            8,
            8,
        ))]);
        let nodes = vec![node("mod_blur")];
        let frame = geom(0, 0, 20000, 20000);
        let (chain, geos) = committed(&lookup, &nodes, &frame);
        // Bottom clamp: a huge margin drives the formula negative.
        let lookup_big = table(vec![Arc::new(FakeBlur::new(
            "mod_big",
            Arc::new(Probe::new()),
            8,
            1_000_000,
        ))]);
        let nodes_big = vec![node("mod_big")];
        let (chain_big, geos_big) = committed(&lookup_big, &nodes_big, &frame);
        let giant_margin = plan_stream(
            &chain_big,
            &geos_big,
            2_748_779_069,
            &frame,
            STREAM_BYTES_PER_PIXEL,
        )
        .unwrap();
        assert_eq!(giant_margin.mode, StreamMode::Block);
        assert_eq!(giant_margin.margin, 1_000_000);
        let first: Vec<_> = giant_margin
            .pieces()
            .take(1)
            .collect::<Result<_, _>>()
            .unwrap();
        assert_eq!(first[0].output, geom(0, 0, 512, 512));
        // No refusal for the giant margin: the grown input just saturates to
        // the whole frame.
        assert_eq!(first[0].input, frame);
        // Top clamp: an enormous budget still stops at 8192.
        let rich = plan_stream(&chain, &geos, u64::MAX, &frame, STREAM_BYTES_PER_PIXEL).unwrap();
        let first: Vec<_> = rich.pieces().take(1).collect::<Result<_, _>>().unwrap();
        assert_eq!(first[0].output, geom(0, 0, 8192, 8192));
        // A zero bytes-per-pixel figure is a typed error, not a division.
        assert!(matches!(
            plan_stream(&chain, &geos, GIB, &frame, 0),
            Err(RenderError::Frame { .. })
        ));
    }

    #[test]
    fn stream_matches_whole_frame_on_strips() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g1", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![
            node("mod_a"),
            gain_node("mod_g0", 2.0),
            gain_node("mod_g1", 0.5),
        ];
        let input = pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_eq!(summary.pieces, 3);
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
        // One `process` call per node per strip.
        assert_eq!(pipe.last_trace().len(), 3);
        for report in pipe.last_trace() {
            assert!(!report.hit);
            assert_eq!(report.process_calls, 3);
        }
    }

    #[test]
    fn stream_matches_whole_frame_on_blocks() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeBlur::new("mod_blur", Arc::new(Probe::new()), 8, 8)),
        ]);
        let nodes = vec![node("mod_a"), node("mod_blur")];
        let input = pattern_frame(640, 640);
        let final_out = geom(0, 0, 640, 640);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        // sqrt(64MiB / 4 / 150) = 334; minus 2*8 clamps the side to 512, so
        // 640x640 renders as 2x2 blocks.
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Block);
        assert_eq!(summary.pieces, 4);
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
    }

    #[test]
    fn stream_matches_whole_frame_on_a_mixed_chain() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeBlur::new("mod_blur", Arc::new(Probe::new()), 8, 8)),
            Arc::new(FakeGain::new("mod_g1", Arc::new(Probe::new()))),
            Arc::new(FakeCopy::new("mod_b", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![
            node("mod_a"),
            gain_node("mod_g0", 2.0),
            node("mod_blur"),
            gain_node("mod_g1", 0.5),
            node("mod_b"),
        ];
        let input = pattern_frame(1024, 1024);
        let final_out = geom(0, 0, 1024, 1024);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Block);
        assert_eq!(summary.pieces, 4);
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
    }

    #[test]
    fn lying_overlap_shows_seams_against_the_whole_frame() {
        // The blur really reads 8 pixels of halo but claims zero: admission
        // sees a point-only chain (strips), so every strip boundary renders
        // from clamped edges instead of true neighbors. The declarations are
        // self-consistent (identity regions), so only the bitwise comparison
        // catches this shape of lie.
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeBlur::new("mod_lie", Arc::new(Probe::new()), 8, 0)),
        ]);
        let nodes = vec![node("mod_a"), node("mod_lie")];
        let input = pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_ne!(streamed.as_slice(), whole.frame().as_slice());
    }

    #[test]
    fn contradictory_overlap_refuses_and_covering_overlap_streams() {
        let frame = geom(0, 0, 96, 64);
        let input = pattern_frame(96, 64);
        let no_cancel = || false;
        // Growth 8 with overlap 0 contradicts itself: both the planner and
        // the entry refuse, with budget, cache, and trace untouched.
        let lookup = table(vec![Arc::new(FakeGrow::new(
            "mod_grow",
            Arc::new(Probe::new()),
            8,
            0,
        ))]);
        let nodes = vec![node("mod_grow")];
        let (chain, geos) = committed(&lookup, &nodes, &frame);
        let err = plan_stream(&chain, &geos, GIB, &frame, STREAM_BYTES_PER_PIXEL).unwrap_err();
        assert!(matches!(
            err,
            RenderError::StreamRefused {
                reason: StreamRefusal::OverlapMismatch { .. },
                ..
            }
        ));
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out: frame,
            cancel: &no_cancel,
        };
        let err = pipe
            .render_stream(&req, |_: StreamPiece| Ok(()))
            .unwrap_err();
        assert!(matches!(
            err,
            RenderError::StreamRefused {
                reason: StreamRefusal::OverlapMismatch { .. },
                ..
            }
        ));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
        assert!(pipe.last_trace().is_empty());
        // Growth 8 with overlap 8 covers: the chain streams (block mode). The
        // caller feeds the grown head input (region-style halo, unclamped),
        // and the fake copies, so stream and whole-frame agree.
        let lookup = table(vec![Arc::new(FakeGrow::new(
            "mod_grow",
            Arc::new(Probe::new()),
            8,
            8,
        ))]);
        let grown = Frame::from_parts(
            pattern_frame(112, 80).as_slice().to_vec(),
            FrameExtent::new(-8, -8, 112, 80),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap();
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &grown,
            input_id: 7,
            process: 1,
            final_out: frame,
            cancel: &no_cancel,
        };
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Block);
        // The fake copies its grown input, so the piece equals the input
        // cropped to the piece (the whole-frame entry cannot run this chain:
        // region-style growth breaks its equal-shape copy check).
        let view = grown.view(FrameExtent::new(0, 0, 96, 64)).unwrap();
        let mut expected =
            Frame::alloc(FrameExtent::new(0, 0, 96, 64), PixelFormat::RgbaF32Premul).unwrap();
        for row in 0..64 {
            expected
                .row_mut(row)
                .unwrap()
                .copy_from_slice(view.row(row).unwrap());
        }
        assert_eq!(streamed.as_slice(), expected.as_slice());
    }

    #[test]
    fn geometry_changing_modules_refuse_streaming() {
        let frame = geom(0, 0, 96, 64);
        let input = pattern_frame(96, 64);
        let no_cancel = || false;
        // Non-square on purpose: the transpose maps the centered probes
        // off themselves, and the scales move positions as well as sizes.
        for (id, module) in [
            (
                "mod_spin",
                Arc::new(FakeSpin::new("mod_spin", Arc::new(Probe::new())))
                    as Arc<dyn lightamer_iop_traits::IopModule>,
            ),
            (
                "mod_up",
                Arc::new(FakeScale::new("mod_up", 2, 1))
                    as Arc<dyn lightamer_iop_traits::IopModule>,
            ),
            (
                "mod_down",
                Arc::new(FakeScale::new("mod_down", 1, 2))
                    as Arc<dyn lightamer_iop_traits::IopModule>,
            ),
        ] {
            let lookup = table(vec![module]);
            let nodes = vec![node(id)];
            let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
            let req = RenderRequest {
                nodes: &nodes,
                lookup: &lookup,
                image: &image(),
                input: &input,
                input_id: 7,
                process: 1,
                final_out: frame,
                cancel: &no_cancel,
            };
            let err = pipe
                .render_stream(&req, |_: StreamPiece| Ok(()))
                .unwrap_err();
            assert!(
                matches!(
                    err,
                    RenderError::StreamRefused {
                        reason: StreamRefusal::GeometryChange { .. },
                        ..
                    }
                ),
                "{id}: {err}"
            );
            assert_eq!(pipe.budget().used(), 0);
            assert_eq!(pipe.cache_len(), 0);
            assert!(pipe.last_trace().is_empty());
        }
    }

    #[test]
    fn whole_image_and_proxy_stats_refuse_streaming() {
        let frame = geom(0, 0, 96, 64);
        let input = pattern_frame(96, 64);
        let no_cancel = || false;
        for (id, module) in [
            (
                "mod_whole",
                Arc::new(FakeWhole::new("mod_whole", Arc::new(Probe::new())))
                    as Arc<dyn lightamer_iop_traits::IopModule>,
            ),
            (
                "mod_proxy",
                Arc::new(FakeProxy::new("mod_proxy", Arc::new(Probe::new())))
                    as Arc<dyn lightamer_iop_traits::IopModule>,
            ),
        ] {
            let lookup = table(vec![module]);
            let nodes = vec![node(id)];
            let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
            let req = RenderRequest {
                nodes: &nodes,
                lookup: &lookup,
                image: &image(),
                input: &input,
                input_id: 7,
                process: 1,
                final_out: frame,
                cancel: &no_cancel,
            };
            let err = pipe
                .render_stream(&req, |_: StreamPiece| Ok(()))
                .unwrap_err();
            if id == "mod_whole" {
                assert!(matches!(
                    err,
                    RenderError::StreamRefused {
                        reason: StreamRefusal::WholeImageStats,
                        ..
                    }
                ));
            } else {
                assert!(matches!(
                    err,
                    RenderError::StreamRefused {
                        reason: StreamRefusal::ProxyStats { .. },
                        ..
                    }
                ));
            }
            assert_eq!(pipe.budget().used(), 0);
            assert_eq!(pipe.cache_len(), 0);
            assert!(pipe.last_trace().is_empty());
        }
    }

    #[test]
    fn empty_chain_streams_as_a_copy() {
        let lookup = table(vec![]);
        let nodes: Vec<PipeNode> = Vec::new();
        let input = pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_eq!(summary.pieces, 3);
        assert_eq!(streamed.as_slice(), input.as_slice());
        assert!(pipe.last_trace().is_empty());
    }

    #[test]
    fn single_sourceless_node_streams() {
        let lookup = table(vec![Arc::new(FakeSource::new(
            "mod_src",
            Arc::new(Probe::new()),
            96,
            64,
        ))]);
        let nodes = vec![node("mod_src")];
        let empty = Frame::alloc(FrameExtent::new(0, 0, 0, 0), PixelFormat::RgbaF32Premul).unwrap();
        let final_out = geom(0, 0, 96, 64);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &empty,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
        assert!(
            streamed
                .as_slice()
                .iter()
                .all(|value| value.to_bits() == 3.0f32.to_bits())
        );
    }

    #[test]
    fn cancel_mid_run_returns_the_budget() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![node("mod_a"), gain_node("mod_g", 2.0)];
        let input = pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        // Entry check plus two pieces run; the third piece never starts.
        let calls = AtomicUsize::new(0);
        let cancel = || calls.fetch_add(1, Ordering::SeqCst) >= 3;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let err = pipe
            .render_stream(&req, |_: StreamPiece| Ok(()))
            .unwrap_err();
        assert!(matches!(err, RenderError::Cancelled));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
        assert_eq!(pipe.last_trace().len(), 2);
        for report in pipe.last_trace() {
            assert_eq!(report.process_calls, 2);
        }
    }

    #[test]
    fn failing_node_reports_its_piece_and_returns_the_budget() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeBackendFail::new("mod_fail", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![node("mod_a"), node("mod_fail")];
        let input = pattern_frame(96, 64);
        let final_out = geom(0, 0, 96, 64);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let err = pipe
            .render_stream(&req, |_: StreamPiece| Ok(()))
            .unwrap_err();
        assert!(matches!(
            err,
            RenderError::Node {
                tile: Some((0, 0)),
                ..
            }
        ));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn streaming_twice_is_bitwise_identical() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![node("mod_a"), gain_node("mod_g", 2.0)];
        let input = pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let (_, first) = stream_assembled(&mut pipe, &req);
        let (_, second) = stream_assembled(&mut pipe, &req);
        assert_eq!(first.as_slice(), second.as_slice());
    }

    #[test]
    fn position_module_proves_absolute_coordinates() {
        // The position fake ignores its pixels and writes absolute-coordinate
        // values: equal outputs prove pieces render in final coordinates,
        // not scratch coordinates.
        let lookup = table(vec![Arc::new(FakePosition::new(
            "mod_pos",
            Arc::new(Probe::new()),
        ))]);
        let nodes = vec![node("mod_pos")];
        let input = pattern_frame(700, 600);
        let final_out = geom(0, 0, 700, 600);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Block);
        assert_eq!(summary.pieces, 4);
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
    }

    #[test]
    fn tiny_budget_fails_typed_on_the_first_piece() {
        let lookup = table(vec![Arc::new(FakeCopy::new(
            "mod_a",
            Arc::new(Probe::new()),
        ))]);
        let nodes = vec![node("mod_a")];
        let input = pattern_frame(96, 64);
        let final_out = geom(0, 0, 96, 64);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        // One 96x64 strip needs 96KB of scratch; 100 bytes cannot host it.
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 100, 0);
        let err = pipe
            .render_stream(&req, |_: StreamPiece| Ok(()))
            .unwrap_err();
        assert!(matches!(err, RenderError::OutOfBudget { .. }));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    /// Quiet-machine probe mirroring the whole-frame idle tests: returns the
    /// load line when the machine is quiet, `None` when the gate must not run
    /// (guard refuses or load1 per cpu tops 1.0).
    fn quiet_line(label: &str) -> Option<String> {
        let uptime = std::process::Command::new("uptime").output().ok()?;
        let text = String::from_utf8_lossy(&uptime.stdout).into_owned();
        let load_text = text
            .split("load averages:")
            .nth(1)
            .or_else(|| text.split("load average:").nth(1))?;
        let one_minute: f64 = load_text
            .split([',', ' '])
            .find_map(|part| part.trim().parse().ok())?;
        let ncpu = std::process::Command::new("sysctl")
            .args(["-n", "hw.ncpu"])
            .output()
            .ok()
            .and_then(|out| String::from_utf8_lossy(&out.stdout).trim().parse().ok())
            .or_else(|| {
                std::process::Command::new("nproc")
                    .output()
                    .ok()
                    .and_then(|out| String::from_utf8_lossy(&out.stdout).trim().parse().ok())
            })
            .unwrap_or(4u32);
        let guard = format!(
            "{}/../../Scripts/machine-guard.sh",
            env!("CARGO_MANIFEST_DIR")
        );
        let guard_ok = std::process::Command::new(&guard)
            .output()
            .is_ok_and(|out| out.status.success());
        let line = format!("{label} load: load1={one_minute} ncpu={ncpu} guard_ok={guard_ok}");
        if !guard_ok || one_minute / f64::from(ncpu) > 1.0 {
            return None;
        }
        Some(line)
    }

    /// Peak resident set of this process in bytes (macOS `ru_maxrss`).
    #[expect(unsafe_code)] // one getrusage call; the contract is in the SAFETY comment below
    fn peak_rss_bytes() -> u64 {
        // SAFETY: `getrusage` writes a plain struct through a live pointer;
        // a failure (never observed) reports zero instead of a number.
        let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
        let ok = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) == 0 };
        if !ok {
            return 0;
        }
        let usage = unsafe { usage.assume_init() };
        u64::try_from(usage.ru_maxrss).unwrap_or(0)
    }

    /// Streams `req` on `pipe`, asserting every pixel equals `want` and
    /// dropping each piece: a 200 MP output (3.2 GB) never assembles, since
    /// assembling it would dwarf the memory gate the test measures.
    fn stream_checked(
        pipe: &mut Pipe,
        req: &RenderRequest<'_, impl crate::chain::ModuleLookup>,
        want: f32,
        pixels: u64,
    ) -> super::StreamSummary {
        let mut seen: u64 = 0;
        let summary = pipe
            .render_stream(req, |piece: StreamPiece| {
                for value in piece.plane.frame.as_slice() {
                    assert_eq!(*value, want);
                }
                seen += u64::from(piece.extent.width) * u64::from(piece.extent.height);
                Ok(())
            })
            .unwrap();
        assert_eq!(seen, pixels);
        summary
    }

    /// Streaming timing: a 200 MP synthetic frame (20000x10000 float32 RGBA)
    /// through five nodes on the Full quota a 16 GiB machine derives, strip
    /// mode then block mode in one process (serial: parallel runs stack their
    /// resident sets and distort the numbers). The input never sits in RAM: a
    /// sourceless head generates each piece on demand, and the sink checks
    /// every pixel against the constant the chain must produce, then drops
    /// the piece. Ignored by default; run it on a quiet machine in release
    /// mode:
    /// `cargo test --release -p lightamer-pipeline --locked -- --ignored stream_200mp`.
    #[test]
    #[ignore = "timing bench: needs a quiet machine and a release build"]
    fn stream_200mp_reports_strip_and_block_peaks() {
        const WIDTH: u32 = 20000;
        const HEIGHT: u32 = 10000;
        const PIXELS: u64 = 200_000_000;
        const BUDGET_16GIB_FULL: u64 = 2_748_779_069;
        const FLOOR_16GIB_FULL: u64 = 128 * 1024 * 1024;
        const GATE_STRIP_RSS_BYTES: u64 = 1024 * 1024 * 1024;
        const STOP_RSS_BYTES: u64 = 4 * 1024 * 1024 * 1024;
        let Some(line) = quiet_line("stream 200mp") else {
            println!("stream-200mp = UNRELIABLE (machine busy; see load line) SKIP-GATE");
            return;
        };
        println!("stream-200mp {line}");
        let width = i32::try_from(WIDTH).unwrap();
        let height = i32::try_from(HEIGHT).unwrap();
        let final_out = geom(0, 0, width, height);
        let empty = Frame::alloc(FrameExtent::new(0, 0, 0, 0), PixelFormat::RgbaF32Premul).unwrap();
        let no_cancel = || false;
        // Strips: every overlap is zero; 10000 rows at 64 rows a strip is 157
        // pieces. The chain multiplies the source constant back to itself
        // (3.0 * 2.0 * 0.5), exactly in float32.
        let lookup = table(vec![
            Arc::new(FakeSource::new(
                "mod_src",
                Arc::new(Probe::new()),
                width,
                height,
            )),
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeCopy::new("mod_b", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g1", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![
            node("mod_src"),
            node("mod_a"),
            gain_node("mod_g0", 2.0),
            node("mod_b"),
            gain_node("mod_g1", 0.5),
        ];
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &empty,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe =
            Pipe::with_budget_and_floor(PipeKind::Full, BUDGET_16GIB_FULL, FLOOR_16GIB_FULL);
        let summary = stream_checked(&mut pipe, &req, 3.0, PIXELS);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_eq!(summary.pieces, 157);
        let strip_peak = peak_rss_bytes();
        println!(
            "stream-200mp strip peak rss = {}MB",
            strip_peak / 1024 / 1024
        );
        // Blocks: the blur's overlap of 8 sums the margin; the side is
        // isqrt(2748779069 / 4 / 150) - 2*8 = 2124, so 10 by 5 blocks. A box
        // blur of a constant field is the constant, exactly.
        let lookup = table(vec![
            Arc::new(FakeSource::new(
                "mod_src",
                Arc::new(Probe::new()),
                width,
                height,
            )),
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeBlur::new("mod_blur", Arc::new(Probe::new()), 8, 8)),
            Arc::new(FakeGain::new("mod_g1", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![
            node("mod_src"),
            node("mod_a"),
            gain_node("mod_g0", 2.0),
            node("mod_blur"),
            gain_node("mod_g1", 0.5),
        ];
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &empty,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let summary = stream_checked(&mut pipe, &req, 3.0, PIXELS);
        assert_eq!(summary.mode, StreamMode::Block);
        assert_eq!(summary.pieces, 50);
        let peak = peak_rss_bytes();
        println!("stream-200mp block peak rss = {}MB", peak / 1024 / 1024);
        assert!(
            strip_peak < GATE_STRIP_RSS_BYTES,
            "strip peak rss {strip_peak} tops the 1 GiB gate"
        );
        assert!(
            peak < STOP_RSS_BYTES,
            "peak rss {peak} tops the 4 GiB stop line"
        );
    }

    #[test]
    fn stream_from_region_source_matches_whole_frame() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeBlur::new("mod_blur", Arc::new(Probe::new()), 8, 8)),
        ]);
        let nodes = vec![node("mod_a"), gain_node("mod_g0", 2.0), node("mod_blur")];
        let input = pattern_frame(640, 640);
        let final_out = geom(0, 0, 640, 640);
        let no_cancel = || false;
        let from = StreamRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            final_out,
            cancel: &no_cancel,
        };
        let source = RecordedRegions {
            frame: &input,
            regions: std::sync::Mutex::new(Vec::new()),
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let (summary, streamed) = stream_from_assembled(&mut pipe, &from, &source);
        assert_eq!(summary.mode, StreamMode::Block);
        assert_eq!(summary.pieces, 4);
        let whole_req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let whole = pipe.render(&whole_req).unwrap();
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
        let (_, via_whole) = stream_assembled(&mut pipe, &whole_req);
        assert_eq!(streamed.as_slice(), via_whole.as_slice());
    }

    #[test]
    fn region_source_serves_exactly_the_planned_inputs() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![node("mod_a"), gain_node("mod_g0", 2.0)];
        let input = pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let from = StreamRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            final_out,
            cancel: &no_cancel,
        };
        let source = RecordedRegions {
            frame: &input,
            regions: std::sync::Mutex::new(Vec::new()),
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let (summary, _) = stream_from_assembled(&mut pipe, &from, &source);
        assert_eq!(summary.pieces, 3);
        let (chain, geos) = committed(&lookup, &nodes, &final_out);
        let plan = plan_stream(
            &chain,
            &geos,
            64 * 1024 * 1024,
            &final_out,
            STREAM_BYTES_PER_PIXEL,
        )
        .unwrap();
        let want: Vec<FrameExtent> = plan
            .pieces()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
            .into_iter()
            .map(|piece| {
                FrameExtent::new(
                    piece.input.x,
                    piece.input.y,
                    u32::try_from(piece.input.width).unwrap(),
                    u32::try_from(piece.input.height).unwrap(),
                )
            })
            .collect();
        assert_eq!(*source.regions.lock().unwrap(), want);
    }

    #[test]
    fn sourceless_head_never_calls_its_source() {
        let lookup = table(vec![Arc::new(FakeSource::new(
            "mod_src",
            Arc::new(Probe::new()),
            96,
            64,
        ))]);
        let nodes = vec![node("mod_src")];
        let empty = Frame::alloc(FrameExtent::new(0, 0, 0, 0), PixelFormat::RgbaF32Premul).unwrap();
        let final_out = geom(0, 0, 96, 64);
        let no_cancel = || false;
        let from = StreamRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            final_out,
            cancel: &no_cancel,
        };
        let source = RecordedRegions {
            frame: &empty,
            regions: std::sync::Mutex::new(Vec::new()),
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let (summary, streamed) = stream_from_assembled(&mut pipe, &from, &source);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert!(source.regions.lock().unwrap().is_empty());
        let whole_req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &empty,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let whole = pipe.render(&whole_req).unwrap();
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
    }

    #[test]
    fn whole_frame_adapter_refuses_an_uncovered_piece() {
        let lookup = table(vec![Arc::new(FakeCopy::new(
            "mod_a",
            Arc::new(Probe::new()),
        ))]);
        let nodes = vec![node("mod_a")];
        let input = pattern_frame(32, 32);
        let final_out = geom(0, 0, 64, 64);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let err = pipe
            .render_stream(&req, |_: StreamPiece| Ok(()))
            .unwrap_err();
        assert!(matches!(err, RenderError::InputMismatch { .. }));
    }
    fn mono_image() -> ImageInfo {
        ImageInfo::new(200, 150, ColorSpace::Raw)
            .with_format(lightamer_iop_traits::PixelFormat::MonoF32)
    }

    #[expect(clippy::cast_precision_loss)] // test frames are small; the conversion is exact
    fn mono_pattern_frame(w: u32, h: u32) -> Frame {
        let len = w as usize * h as usize;
        let buf: Vec<f32> = (0..len).map(|i| i as f32 * 0.125 - 3.0).collect();
        Frame::from_parts(buf, FrameExtent::new(0, 0, w, h), PixelFormat::MonoF32).unwrap()
    }

    /// Streams `req` on `pipe`, assembling mono pieces into one mono frame.
    fn mono_stream_assembled(
        pipe: &mut Pipe,
        req: &RenderRequest<'_, impl crate::chain::ModuleLookup>,
    ) -> (super::StreamSummary, Frame) {
        let extent = FrameExtent::new(
            req.final_out.x,
            req.final_out.y,
            u32::try_from(req.final_out.width).unwrap(),
            u32::try_from(req.final_out.height).unwrap(),
        );
        let mut out = Frame::alloc(extent, PixelFormat::MonoF32).unwrap();
        let summary = pipe
            .render_stream(req, |piece: StreamPiece| {
                assert_eq!(piece.plane.frame.format(), PixelFormat::MonoF32);
                let src = piece.plane.frame.as_slice();
                let ox = usize::try_from(piece.extent.x - extent.x).unwrap();
                let oy = usize::try_from(piece.extent.y - extent.y).unwrap();
                for row in 0..piece.extent.height as usize {
                    let seg = &src[row * piece.extent.width as usize
                        ..(row + 1) * piece.extent.width as usize];
                    let dst_row = u32::try_from(oy + row).unwrap();
                    let dst = out.row_mut(dst_row).unwrap();
                    dst[ox..ox + seg.len()].copy_from_slice(seg);
                }
                Ok(())
            })
            .unwrap();
        (summary, out)
    }

    #[test]
    fn mono_stream_matches_whole_frame_bitwise() {
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g1", Arc::new(Probe::new()))),
        ]);
        let nodes = vec![
            node("mod_a"),
            gain_node("mod_g0", 2.0),
            gain_node("mod_g1", 0.5),
        ];
        let input = mono_pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &mono_image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        assert_eq!(whole.frame().format(), PixelFormat::MonoF32);
        let (summary, streamed) = mono_stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_eq!(summary.pieces, 3);
        assert_eq!(streamed.format(), PixelFormat::MonoF32);
        assert_eq!(streamed.as_slice(), whole.frame().as_slice());
    }

    /// Test module declaring mono-in/RGBA-out: streaming must refuse it.
    struct FormatChanger {
        desc: lightamer_iop_traits::ModuleDesc,
    }

    struct FormatChangerCommit;

    impl lightamer_iop_traits::IopModule for FormatChanger {
        fn desc(&self) -> &lightamer_iop_traits::ModuleDesc {
            &self.desc
        }

        fn commit(
            &self,
            _params: &serde_json::Map<String, serde_json::Value>,
            _image: &ImageInfo,
            _state: &mut PipeState,
        ) -> Result<lightamer_iop_traits::CommitData, lightamer_iop_traits::PipeError> {
            Ok(Arc::new(FormatChangerCommit))
        }

        fn output_format(
            &self,
            input: lightamer_iop_traits::PixelFormat,
        ) -> lightamer_iop_traits::PixelFormat {
            match input {
                lightamer_iop_traits::PixelFormat::MonoF32 => {
                    lightamer_iop_traits::PixelFormat::RgbaF32Premul
                }
                other => other,
            }
        }

        fn process(
            &self,
            _data: &lightamer_iop_traits::CommitData,
            input: &lightamer_iop_traits::Plane<'_>,
            output: &mut lightamer_iop_traits::PlaneMut<'_>,
            rin: lightamer_iop_traits::Roi,
            rout: lightamer_iop_traits::Roi,
            _state: &mut lightamer_iop_traits::PipeState,
        ) -> Result<(), lightamer_iop_traits::PipeError> {
            FakeCopy::copy_planes(input, output, rin, rout)
        }
    }

    #[test]
    fn format_change_refuses_before_any_allocation() {
        let key = lightamer_iop_traits::OrderKey {
            priority: 1.0,
            tie: 0,
        };
        let lookup = table(vec![Arc::new(FormatChanger {
            desc: lightamer_iop_traits::ModuleDesc::stub("mod_expand", key, key),
        })]);
        let nodes = vec![node("mod_expand")];
        let input = mono_pattern_frame(200, 150);
        let final_out = geom(0, 0, 200, 150);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &mono_image(),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let err = pipe
            .render_stream(&req, |_: StreamPiece| Ok(()))
            .unwrap_err();
        assert!(matches!(
            err,
            RenderError::StreamRefused {
                reason: StreamRefusal::FormatChange { .. },
                ..
            }
        ));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn stream_pieces_each_start_from_commit_state() {
        // Zero-overlap chain streams in 64-row strips; 130 rows make 3 pieces.
        let commits = Arc::new(Mutex::new(Vec::new()));
        let processes = Arc::new(Mutex::new(Vec::new()));
        let seen = Arc::new(Mutex::new(Vec::new()));
        let lookup = table(vec![
            Arc::new(FakeStateWriter::new(
                "mod_w",
                Arc::new(Probe::new()),
                2.0,
                4.0,
                2.0,
                Arc::clone(&seen),
            )),
            Arc::new(FakeStateReader::new(
                "mod_r",
                Arc::new(Probe::new()),
                Arc::clone(&commits),
                Arc::clone(&processes),
                false,
            )),
        ]);
        let nodes = vec![node("mod_w"), node("mod_r")];
        let input = pattern_frame(8, 130);
        let image = ImageInfo::new(8, 130, ColorSpace::Rgb);
        let final_out = geom(0, 0, 8, 130);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 1024 * 1024);
        let (summary, streamed) = stream_assembled(&mut pipe, &req);
        assert_eq!(summary.mode, StreamMode::Strip);
        assert_eq!(summary.pieces, 3);
        assert_eq!(streamed.as_slice(), input.as_slice());
        // Commits ran once; each piece ran the whole chain from the commit
        // value, never from a sibling piece's processing.
        assert_eq!(*commits.lock().unwrap(), vec![2.0]);
        assert_eq!(*seen.lock().unwrap(), vec![2.0, 2.0, 2.0]);
        assert_eq!(*processes.lock().unwrap(), vec![4.0, 4.0, 4.0]);
    }
}
