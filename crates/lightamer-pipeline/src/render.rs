// SPDX-License-Identifier: GPL-3.0-or-later
//! Execution: running a committed chain into an output plane.
//!
//! [`Pipe`] is one pipe instance (see [`PipeKind`]):
//! it holds the memory budget and the plane cache across renders.
//! [`Pipe::render`] runs the darktable main-flow shape
//! (`_dev_pixelpipe_process_rec`, `src/develop/pixelpipe_hb.c:2323-2480` for
//! the cache-first recursion plus `:2575-2600` for the
//! `modify_roi_in`/recurse/process order), minus what B1-b does not have yet
//! (no decode leg — the caller hands in the input plane; no colorspace
//! transforms — a non-empty [`ColorPlan`](super::negotiate::ColorPlan) is a typed
//! error; no `OpenCL`, blending, masks, or histograms):
//!
//! build the chain and commit → push geometry forward (check it backward) →
//! refuse oversized frames before allocating anything → negotiate formats
//! (plan only) → per node: peek the cache (hit: reuse the plane, no `process`
//! call, no realloc); miss: decide whole-frame vs tiled, make room by
//! evicting unhit entries oldest-first, allocate the output plane, run
//! `process` once (or once per tile), insert the finished plane at once. A
//! cancelled or failed run keeps every completed plane (content-determined
//! keys stay valid); only a node that never finished leaves nothing behind.
//!
//! Tiles run serially in B1-b (tile-level parallelism is future work); rows
//! inside one `process` call parallelize through
//! [`par_map_rows`](lightamer_iop_traits::par_map_rows). Tiled execution
//! follows `_default_process_tiling_ptp` (`src/develop/tiling.c:690-806`):
//! one reusable input/output scratch pair, per-tile input copied out of the
//! full upstream plane (overlap included, frame-clamped), `process` per tile,
//! then only the good part (leading overlap trimmed) copied back.

use std::collections::HashSet;
use std::fmt;
use std::sync::Arc;
use std::time::Instant;

use lightamer_geom::Roi as GeomRoi;
use lightamer_iop_traits::{ColorSpace, ImageInfo, PipeError, Plane, PlaneMut, Roi as WireRoi};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use lightamer_sysmem::Budget;

use super::budgeted::{BudgetedError, SharedFrame, alloc_shared};
use super::cache::{PlaneCache, chain_keys};
use super::chain::{
    ChainError, CommittedNode, ModuleLookup, NodeGeometry, PipeNode, backward_check, build_chain,
    forward, to_wire,
};
use super::kinds::{PipeKind, quota, quota_for, singlebuffer_floor, system_physical_memory};
use super::negotiate::negotiate as negotiate_plan;
use super::stream::StreamRefusal;
use super::tiling::{Tile, TileGrid, TilingDecision, decide};

/// What one node did in the latest render: cache hit or recompute, how many
/// `process` calls it took, and how long they took. The engine copies these
/// into its per-render record for demos and tests; `millis` is wall time on
/// the calling thread (0.0 for hits, which call nothing).
#[derive(Debug, Clone)]
pub struct NodeReport {
    /// Module id.
    pub id: String,
    /// Multi-instance index.
    pub multi: u32,
    /// Whether the output plane came from the cache (`process` not called).
    pub hit: bool,
    /// `process` calls for this node (0 on a hit, 1 untiled, tile count tiled).
    pub process_calls: u32,
    /// Milliseconds spent running this node (0.0 on a hit).
    pub millis: f64,
}

impl NodeReport {
    fn for_node(node: &CommittedNode, hit: bool, process_calls: u32, millis: f64) -> Self {
        Self {
            id: node.id.clone(),
            multi: node.multi,
            hit,
            process_calls,
            millis,
        }
    }
}
/// One pipe instance: a budget and a plane cache shared across renders.
///
/// The budget cap, cache slots, and single-tile floor come from the kind's
/// quota ([`quota_for`]); the constructor reads live
/// physical memory, the test constructor takes explicit numbers.
#[derive(Debug)]
pub struct Pipe {
    kind: PipeKind,
    budget: Arc<Budget>,
    floor: u64,
    cache: PlaneCache,
    last_trace: Vec<NodeReport>,
}

/// What one render needs. The caller defines `input_id` (any change to the
/// decoded input changes it, e.g. image id mixed with a decode generation)
/// and passes the process version as a plain integer, so the pipeline never
/// depends on the history model's types.
pub struct RenderRequest<'a, L: ModuleLookup + ?Sized> {
    /// Nodes in execution order.
    pub nodes: &'a [PipeNode],
    /// Where committed modules come from, by id.
    pub lookup: &'a L,
    /// Decoded-image facts for `commit`.
    pub image: &'a ImageInfo,
    /// Caller-built input plane (decoding is B2; B1-b renders from this).
    pub input: &'a Frame,
    /// Caller-defined input identity (image id mixed with decode generation).
    pub input_id: u64,
    /// Process version, as a plain integer (mirrors history's `u32`).
    pub process: u32,
    /// Wanted final output region.
    pub final_out: GeomRoi,
    /// Cancellation probe, consulted between nodes and between tiles.
    pub cancel: &'a dyn Fn() -> bool,
}

impl<L: ModuleLookup + ?Sized> fmt::Debug for RenderRequest<'_, L> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RenderRequest")
            .field("nodes", &self.nodes)
            .field("image", &self.image)
            .field("input", &self.input)
            .field("input_id", &self.input_id)
            .field("process", &self.process)
            .field("final_out", &self.final_out)
            .finish_non_exhaustive()
    }
}

/// A rendered output plane: an [`Arc`] over a budget-paired frame.
///
/// Cloning shares the plane (no copy, no realloc); the budget bytes return
/// when the last holder — cache entry or output — drops.
#[derive(Debug, Clone)]
pub struct OutputFrame {
    inner: Arc<SharedFrame>,
}

impl OutputFrame {
    /// The output pixels.
    #[must_use]
    pub fn frame(&self) -> &Frame {
        &self.inner.frame
    }

    /// Budget bytes this output holds.
    #[must_use]
    pub fn bytes(&self) -> u64 {
        self.inner.bytes()
    }
}

/// Why a render failed. Every path is typed and human-readable; no path
/// panics. A failure returns every transient byte and caches no partial
/// plane; planes of nodes that already finished stay cached under their
/// content-determined keys.
#[derive(Debug)]
pub enum RenderError {
    /// Chain building or geometry failed (unknown module, refused commit,
    /// bad region, round-trip mismatch).
    Chain(ChainError),
    /// The format plan needs a conversion this wave cannot run (B5).
    ColorGap {
        /// Index of the node whose output would convert.
        after: usize,
        /// That node's output space.
        from: ColorSpace,
        /// The next node's input space.
        to: ColorSpace,
    },
    /// A module's `process` failed, whole-frame (`tile` none) or tiled.
    Node {
        /// Module id.
        id: String,
        /// Tile position for tiled runs.
        tile: Option<(u32, u32)>,
        /// What the module reported.
        source: PipeError,
    },
    /// The budget refused a plane this run needs.
    OutOfBudget {
        /// Which plane, and the budget numbers.
        detail: String,
    },
    /// One node's footprint (its charged planes plus the tiling scratch
    /// reserve) exceeds this pipe's budget. The run refuses before
    /// allocating anything, so the budget and the cache sit exactly as found.
    FrameTooLarge {
        /// Index of the first node that does not fit.
        node: usize,
        /// That node's footprint in bytes.
        need_bytes: u64,
        /// This pipe's budget in bytes.
        budget_bytes: u64,
    },
    /// A frame or plane would not build (shapes the geometry made
    /// unbuildable, or bytes that overflow `u64`).
    Frame {
        /// What would not build.
        detail: String,
    },
    /// The caller's input plane does not cover the chain's first input.
    InputMismatch {
        /// Expected vs handed-in extents.
        detail: String,
    },
    /// The cancel probe fired between nodes or between tiles.
    Cancelled,
    /// Streaming refused before allocating anything: one module cannot
    /// stream. The budget and the cache sit exactly as found.
    StreamRefused {
        /// Module id.
        id: String,
        /// Why it cannot stream.
        reason: StreamRefusal,
    },
    /// Streaming output assembly failed (spill file, byte limit, piece shape).
    Spill {
        /// What failed.
        detail: String,
    },
}

impl fmt::Display for RenderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RenderError::Chain(source) => write!(f, "render chain: {source}"),
            RenderError::ColorGap { after, from, to } => write!(
                f,
                "render needs a colorspace conversion after node {after} ({from:?} to {to:?}); conversions land in B5"
            ),
            RenderError::Node { id, tile, source } => match tile {
                Some((tx, ty)) => write!(f, "render node '{id}' tile ({tx},{ty}): {source}"),
                None => write!(f, "render node '{id}': {source}"),
            },
            RenderError::OutOfBudget { detail } => write!(f, "render out of budget: {detail}"),
            RenderError::FrameTooLarge {
                node,
                need_bytes,
                budget_bytes,
            } => write!(
                f,
                "render frame too large: node {node} needs {need_bytes} bytes (its planes plus the tiling scratch reserve) over the {budget_bytes}-byte budget; shrink the frame or grow the budget"
            ),
            RenderError::Frame { detail } => write!(f, "render frame: {detail}"),
            RenderError::InputMismatch { detail } => write!(f, "render input: {detail}"),
            RenderError::Cancelled => write!(f, "render cancelled"),
            RenderError::StreamRefused { id, reason } => {
                write!(f, "streaming refused module '{id}': {reason}")
            }
            RenderError::Spill { detail } => write!(f, "streaming spill: {detail}"),
        }
    }
}

impl std::error::Error for RenderError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            RenderError::Chain(source) => Some(source),
            RenderError::Node { source, .. } => Some(source),
            _ => None,
        }
    }
}

impl Pipe {
    /// Builds one pipe instance of `kind`, deriving its budget, cache slots,
    /// and single-tile floor from live physical memory.
    ///
    /// # Errors
    ///
    /// [`std::io::Error`] when physical memory is unreadable; the caller
    /// falls back to [`Pipe::with_budget_and_floor`] with a conservative
    /// constant then.
    pub fn new(kind: PipeKind) -> Result<Self, std::io::Error> {
        let total = system_physical_memory()?;
        let quota = quota_for(kind, total);
        Ok(Self::with_budget_and_floor(
            kind,
            quota.memory_budget,
            singlebuffer_floor(kind, total),
        ))
    }

    /// Builds one pipe instance with an explicit budget and single-tile
    /// floor (tests and callers that manage memory themselves). Cache slots
    /// still come from the kind's quota. The cache keeps at most half the
    /// budget in bytes, so a re-render's working set always has room beside
    /// a full cache; a plane bigger than that half is never cached (the
    /// render that made it still succeeds).
    #[must_use]
    pub fn with_budget_and_floor(kind: PipeKind, memory_budget: u64, floor: u64) -> Self {
        Self {
            kind,
            budget: Arc::new(Budget::new(memory_budget)),
            floor,
            cache: PlaneCache::new(quota(kind).cache_slots, memory_budget / 2),
            last_trace: Vec::new(),
        }
    }

    /// This pipe's kind.
    #[must_use]
    pub fn kind(&self) -> PipeKind {
        self.kind
    }

    /// This pipe's budget (live bytes are observable for tests).
    #[must_use]
    pub fn budget(&self) -> &Arc<Budget> {
        &self.budget
    }

    /// Cached planes currently held.
    #[must_use]
    pub fn cache_len(&self) -> usize {
        self.cache.len()
    }

    /// Drops every cached plane.
    pub fn clear_cache(&mut self) {
        self.cache.clear();
    }

    /// Per-node report of the latest render on this pipe, in execution order.
    /// A hit reports `process_calls: 0`; a completed miss reports how many
    /// `process` calls it took and how long they took. A cancelled or failed
    /// run leaves the prefix it completed (a node that never finished leaves
    /// no entry); an empty chain leaves nothing.
    #[must_use]
    pub fn last_trace(&self) -> &[NodeReport] {
        &self.last_trace
    }

    /// Allocates one streaming scratch or sink plane, evicting unhit cache
    /// entries oldest-first until it fits. The protected set stays empty:
    /// streaming never peeks the cache, so no entry is a live input.
    pub(crate) fn stream_alloc(
        &mut self,
        extent: FrameExtent,
        why: &str,
    ) -> Result<SharedFrame, RenderError> {
        alloc_room(&self.budget, &mut self.cache, &HashSet::new(), extent, why)
    }

    /// Replaces the last-trace report (streaming writes node totals on every
    /// exit, including cancel and failure).
    pub(crate) fn set_last_trace(&mut self, trace: Vec<NodeReport>) {
        self.last_trace = trace;
    }

    /// Largest uniform frame this pipe renders: `(budget − 2 × floor) / 2`,
    /// saturating at zero.
    ///
    /// One node holds its input and output together (two frames); the
    /// `2 × floor` reserve margins a tiled node's scratch pair at the
    /// smallest tile this pipe cuts. [`Pipe::render`] enforces the sharper
    /// per-node form (node 0 needs its output, later nodes input + output,
    /// each plus the reserve) and refuses the run as
    /// [`RenderError::FrameTooLarge`] before allocating anything. A tiled
    /// node whose tiles exceed the reserve can still refuse mid-run
    /// ([`RenderError::OutOfBudget`]); both errors return every transient
    /// byte and cache no partial plane.
    #[must_use]
    pub fn max_frame_bytes(&self) -> u64 {
        self.budget
            .cap()
            .saturating_sub(self.floor.saturating_mul(2))
            / 2
    }

    /// Runs `req` into an output plane.
    ///
    /// Order: commit → forward geometry → backward check → footprint check
    /// ([`RenderError::FrameTooLarge`] before anything allocates) → format
    /// plan (any conversion step is [`RenderError::ColorGap`]) → per node:
    /// cache peek (hit: reuse, no `process`, no realloc), else tiling
    /// decision, make room, and one `process` run whole-frame or per tile,
    /// inserted at once. Cancel is consulted before every node and every
    /// tile; cancel or any error drops the run's transients (budget back)
    /// and keeps every completed plane cached — never a partial one.
    ///
    /// # Errors
    ///
    /// [`RenderError`] for every failure above; see its variants.
    pub fn render<L: ModuleLookup>(
        &mut self,
        req: &RenderRequest<'_, L>,
    ) -> Result<OutputFrame, RenderError> {
        if (req.cancel)() {
            return Err(RenderError::Cancelled);
        }
        self.last_trace.clear();
        let chain = build_chain(req.lookup, req.nodes, req.image).map_err(RenderError::Chain)?;
        if chain.is_empty() {
            return self.render_empty(req);
        }
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
        let keys = chain_keys(self.kind, req.input_id, req.process, req.nodes, &geos);

        // Footprints before work: a frame no budget this size can host
        // refuses here, typed, with nothing allocated and nothing cached.
        check_footprints(self.budget.cap(), self.floor, &geos)?;

        let mut prev: Option<Arc<SharedFrame>> = None;
        let mut protected: HashSet<u64> = HashSet::new();
        for ((node, geo), key) in chain.iter().zip(geos.iter()).zip(keys.iter()) {
            if (req.cancel)() {
                return Err(RenderError::Cancelled);
            }
            let want = geo_extent(&geo.output)?;
            if let Some(hit) = self.cache.peek(*key) {
                // A key collision with different geometry recomputes (never a
                // wrong plane): upstream invalidates size-mismatched cachelines
                // the same way (`pixelpipe_cache.c`, `_get_by_hash`).
                if hit.frame.extent() == want {
                    self.cache.touch(*key);
                    protected.insert(*key);
                    self.last_trace
                        .push(NodeReport::for_node(node, true, 0, 0.0));
                    prev = Some(hit);
                    continue;
                }
            }
            let input: &Frame = match prev.as_ref() {
                Some(upstream) => &upstream.frame,
                None => req.input,
            };
            let treq = node
                .module
                .tiling(&node.data, &to_wire(&geo.input), &to_wire(&geo.output));
            let frame_bytes = plane_bytes(&geo.output)?;
            let decision = decide(
                &treq,
                &geo.input,
                &geo.output,
                frame_bytes,
                self.budget.cap(),
                self.floor,
            );
            let started = Instant::now();
            let (plane, process_calls) = match decision {
                TilingDecision::NoTiling => {
                    let plane =
                        run_untiled(&self.budget, &mut self.cache, &protected, node, geo, input)?;
                    (plane, 1)
                }
                TilingDecision::Tiled(grid) => run_tiled(
                    &self.budget,
                    &mut self.cache,
                    &protected,
                    node,
                    geo,
                    &grid,
                    input,
                    req.cancel,
                )?,
            };
            self.last_trace.push(NodeReport::for_node(
                node,
                false,
                process_calls,
                started.elapsed().as_secs_f64() * 1000.0,
            ));
            let plane = Arc::new(plane);
            // The plane is complete, so it lands in the cache at once: the
            // next node (or the next render) reuses it, and a later cancel or
            // failure keeps it. `false` = no room: the render still succeeds,
            // uncached.
            let _ = self.cache.insert(*key, Arc::clone(&plane));
            prev = Some(plane);
        }
        // Upstream entries land most-recently-used (B1-b rule): a downstream
        // edit reuses them while the reverse never holds. Keys refused or
        // evicted mid-run are simply unknown here and ignored.
        for key in keys.iter().rev() {
            self.cache.touch(*key);
        }
        let Some(last) = prev else {
            return Err(RenderError::Frame {
                detail: "internal: a non-empty chain rendered no plane".to_owned(),
            });
        };
        Ok(OutputFrame { inner: last })
    }

    /// An empty chain copies the input plane (which must already sit at the
    /// wanted region: no module can reshape it). Uncached by design.
    fn render_empty<L: ModuleLookup>(
        &mut self,
        req: &RenderRequest<'_, L>,
    ) -> Result<OutputFrame, RenderError> {
        let want = geo_extent(&req.final_out)?;
        if req.input.extent() != want {
            return Err(RenderError::InputMismatch {
                detail: format!(
                    "empty chain needs input at {want:?}, caller gave {:?}",
                    req.input.extent()
                ),
            });
        }
        let protected = HashSet::new();
        let mut out = alloc_room(
            &self.budget,
            &mut self.cache,
            &protected,
            want,
            "empty chain",
        )?;
        out.frame
            .copy_from(req.input)
            .map_err(|err| RenderError::Frame {
                detail: format!("empty chain cannot copy its input: {err}"),
            })?;
        Ok(OutputFrame {
            inner: Arc::new(out),
        })
    }
}

/// Geometry rect to frame extent (rois are validated non-negative, so the
/// conversion only guards the impossible).
pub(crate) fn geo_extent(roi: &GeomRoi) -> Result<FrameExtent, RenderError> {
    let width = u32::try_from(roi.width).map_err(|_| RenderError::Frame {
        detail: format!("region width {} is not a frame width", roi.width),
    })?;
    let height = u32::try_from(roi.height).map_err(|_| RenderError::Frame {
        detail: format!("region height {} is not a frame height", roi.height),
    })?;
    Ok(FrameExtent::new(roi.x, roi.y, width, height))
}

/// Bytes of one full plane at `roi` (working format, 16 bytes per pixel).
fn plane_bytes(roi: &GeomRoi) -> Result<u64, RenderError> {
    let width = u64::try_from(roi.width).map_err(|_| RenderError::Frame {
        detail: format!("region width {} overflows its byte count", roi.width),
    })?;
    let height = u64::try_from(roi.height).map_err(|_| RenderError::Frame {
        detail: format!("region height {} overflows its byte count", roi.height),
    })?;
    width
        .checked_mul(height)
        .and_then(|area| area.checked_mul(PixelFormat::RgbaF32Premul.bytes_per_pixel()))
        .ok_or_else(|| RenderError::Frame {
            detail: format!("region {roi:?} overflows its byte count"),
        })
}

/// Maps a budgeted-allocation failure onto the render error for node `id`.
fn map_budgeted(id: &str, err: BudgetedError) -> RenderError {
    match err {
        BudgetedError::Budget(source) => RenderError::OutOfBudget {
            detail: format!("node '{id}' needs a plane: {source}"),
        },
        BudgetedError::Raster(source) => RenderError::Frame {
            detail: format!("node '{id}' plane would not build: {source}"),
        },
    }
}

/// Refuses runs whose frames no budget this size can host: node 0 charges
/// its output (its input is the caller's uncharged plane), later nodes
/// charge input + output, and every node margins `2 × floor` for a tiled
/// scratch pair. Runs before any allocation, so a refusal leaves the budget
/// and the cache exactly as found.
fn check_footprints(cap: u64, floor: u64, geos: &[NodeGeometry]) -> Result<(), RenderError> {
    let reserve = floor.saturating_mul(2);
    for (index, geo) in geos.iter().enumerate() {
        let out = plane_bytes(&geo.output)?;
        let input = if index == 0 {
            0
        } else {
            plane_bytes(&geo.input)?
        };
        let need = input.saturating_add(out).saturating_add(reserve);
        if need > cap {
            return Err(RenderError::FrameTooLarge {
                node: index,
                need_bytes: need,
                budget_bytes: cap,
            });
        }
    }
    Ok(())
}

/// Allocates one plane, evicting cache entries this run has not hit (oldest
/// first) until it fits. Hit entries are the run's live inputs and never
/// yield; when nothing evictable remains and the plane still does not fit,
/// the budget refusal surfaces typed.
pub(crate) fn alloc_room(
    budget: &Arc<Budget>,
    cache: &mut PlaneCache,
    protected: &HashSet<u64>,
    extent: FrameExtent,
    node_id: &str,
) -> Result<SharedFrame, RenderError> {
    match alloc_shared(budget, extent, PixelFormat::RgbaF32Premul) {
        Ok(frame) => Ok(frame),
        Err(BudgetedError::Budget(_)) => {
            let need = extent_bytes(&extent)?;
            while budget.remaining() < need {
                if cache.evict_oldest_except(protected).is_none() {
                    break;
                }
            }
            alloc_shared(budget, extent, PixelFormat::RgbaF32Premul)
                .map_err(|err| map_budgeted(node_id, err))
        }
        Err(err) => Err(map_budgeted(node_id, err)),
    }
}

/// Bytes of one working-format plane at `extent` (16 bytes per pixel).
fn extent_bytes(extent: &FrameExtent) -> Result<u64, RenderError> {
    extent
        .area_u64()
        .checked_mul(PixelFormat::RgbaF32Premul.bytes_per_pixel())
        .ok_or_else(|| RenderError::Frame {
            detail: format!("extent {extent:?} overflows its byte count"),
        })
}

/// Checks the upstream plane covers exactly the node's input region.
fn check_input(id: &str, input: &Frame, geo: &NodeGeometry) -> Result<(), RenderError> {
    let want = geo_extent(&geo.input)?;
    if input.extent() != want {
        return Err(RenderError::InputMismatch {
            detail: format!(
                "node '{id}' needs input at {want:?}, upstream gave {:?}",
                input.extent()
            ),
        });
    }
    Ok(())
}

/// Runs one node whole-frame: make room, allocate the output plane, call
/// `process` once.
///
/// An empty input region still calls `process` (with empty planes): the
/// module reports it needs no input, not that it does nothing.
fn run_untiled(
    budget: &Arc<Budget>,
    cache: &mut PlaneCache,
    protected: &HashSet<u64>,
    node: &CommittedNode,
    geo: &NodeGeometry,
    input: &Frame,
) -> Result<SharedFrame, RenderError> {
    check_input(&node.id, input, geo)?;
    let mut out = alloc_room(budget, cache, protected, geo_extent(&geo.output)?, &node.id)?;
    let in_extent = input.extent();
    let in_plane = if geo.input.is_empty() {
        Plane::from_slice(&[], 0, 0, 0).map_err(|err| RenderError::Frame {
            detail: format!(
                "node '{}' empty input plane would not build: {err}",
                node.id
            ),
        })?
    } else {
        Plane::from_slice(
            input.as_slice(),
            in_extent.width,
            in_extent.height,
            input.row_stride(),
        )
        .map_err(|err| RenderError::Frame {
            detail: format!("node '{}' input plane would not build: {err}", node.id),
        })?
    };
    let out_extent = out.frame.extent();
    let out_stride = out.frame.row_stride();
    let mut out_plane = PlaneMut::from_slice(
        out.frame.as_mut_slice(),
        out_extent.width,
        out_extent.height,
        out_stride,
    )
    .map_err(|err| RenderError::Frame {
        detail: format!("node '{}' output plane would not build: {err}", node.id),
    })?;
    node.module
        .process(
            &node.data,
            &in_plane,
            &mut out_plane,
            to_wire(&geo.input),
            to_wire(&geo.output),
        )
        .map_err(|source| RenderError::Node {
            id: node.id.clone(),
            tile: None,
            source,
        })?;
    Ok(out)
}

/// Runs one node per tile: copy each tile's input (overlap included) out of
/// the full upstream plane, call `process` per tile, copy each good part back.
///
/// Follows `_default_process_tiling_ptp` (`src/develop/tiling.c:690-806`):
/// one reusable input/output scratch pair sized to the largest tile; per-tile
/// absolute-coordinate rois (`iroi`/`oroi`, `:740-741`); only the good part
/// (leading overlap trimmed) copied back (`:780-790`).
#[expect(clippy::too_many_arguments)] // one tiled run with its budget, cache, geometry, and input; splitting would scatter the tiling loop
fn run_tiled(
    budget: &Arc<Budget>,
    cache: &mut PlaneCache,
    protected: &HashSet<u64>,
    node: &CommittedNode,
    geo: &NodeGeometry,
    grid: &TileGrid,
    input: &Frame,
    cancel: &dyn Fn() -> bool,
) -> Result<(SharedFrame, u32), RenderError> {
    check_input(&node.id, input, geo)?;
    let mut out = alloc_room(budget, cache, protected, geo_extent(&geo.output)?, &node.id)?;
    if grid.tiles.is_empty() {
        return Ok((out, 0));
    }
    // Scratch pair sized to the largest tile, reused across all tiles.
    let mut widest: u32 = 1;
    let mut tallest: u32 = 1;
    for tile in &grid.tiles {
        let (width, height) = tile_dims(&node.id, tile)?;
        widest = widest.max(width);
        tallest = tallest.max(height);
    }
    // Scratch planes charge the budget while the node runs (transient, like
    // upstream's `input`/`output` tile buffers at `tiling.c:694-711`); each
    // yields unhit cache entries first, and a refusal past that is a typed
    // out-of-budget, where upstream falls back to untiled processing with a
    // log line.
    let scratch_extent = FrameExtent::new(0, 0, widest, tallest);
    let mut scratch_in = alloc_room(budget, cache, protected, scratch_extent, &node.id)?;
    let mut scratch_out = alloc_room(budget, cache, protected, scratch_extent, &node.id)?;
    let mut run = TileRun {
        node,
        geo,
        input,
        scratch_in: &mut scratch_in.frame,
        scratch_out: &mut scratch_out.frame,
        out: &mut out.frame,
    };
    let mut calls: u32 = 0;
    for tile in &grid.tiles {
        if cancel() {
            return Err(RenderError::Cancelled);
        }
        run_tile(&mut run, tile)?;
        calls += 1;
    }
    Ok((out, calls))
}

/// Scratch state one tiled node reuses across its tiles.
struct TileRun<'a> {
    node: &'a CommittedNode,
    geo: &'a NodeGeometry,
    input: &'a Frame,
    scratch_in: &'a mut Frame,
    scratch_out: &'a mut Frame,
    out: &'a mut Frame,
}

/// One tile's dimensions as frame widths.
fn tile_dims(id: &str, tile: &Tile) -> Result<(u32, u32), RenderError> {
    let width = u32::try_from(tile.input.width).map_err(|_| RenderError::Frame {
        detail: format!("node '{id}' tile width overflows"),
    })?;
    let height = u32::try_from(tile.input.height).map_err(|_| RenderError::Frame {
        detail: format!("node '{id}' tile height overflows"),
    })?;
    Ok((width, height))
}

/// Runs one tile: fill its input, call `process`, copy its good part back.
fn run_tile(run: &mut TileRun<'_>, tile: &Tile) -> Result<(), RenderError> {
    let in_len = fill_tile_input(run, tile)?;
    let oroi = process_tile(run, tile, in_len)?;
    let stride = run.scratch_out.row_stride();
    // Good part back into the full output plane (leading overlap trimmed;
    // the next tile overwrites the trailing margin).
    copy_good_part(
        run.node,
        tile,
        &oroi,
        &*run.scratch_out,
        stride,
        &mut *run.out,
    )
}

/// Copies one tile's input (overlap included, frame-clamped by the grid
/// builder) out of the full upstream plane into the scratch input.
/// Returns the scratch elements the tile occupies.
fn fill_tile_input(run: &mut TileRun<'_>, tile: &Tile) -> Result<usize, RenderError> {
    let id = &run.node.id;
    let (width, height) = tile_dims(id, tile)?;
    let tile_extent = FrameExtent::new(tile.input.x, tile.input.y, width, height);
    let view = run
        .input
        .view(tile_extent)
        .map_err(|err| RenderError::Frame {
            detail: format!(
                "node '{id}' tile ({},{}) input is outside its plane: {err}",
                tile.tx, tile.ty
            ),
        })?;
    let rows = usize::try_from(height).map_err(|_| RenderError::Frame {
        detail: format!("node '{id}' tile height overflows its row count"),
    })?;
    let stride = run.scratch_in.row_stride();
    let in_len = rows.checked_mul(stride).ok_or_else(|| RenderError::Frame {
        detail: format!("node '{id}' tile input rows overflow"),
    })?;
    let in_sub = run
        .scratch_in
        .as_mut_slice()
        .get_mut(0..in_len)
        .ok_or_else(|| RenderError::Frame {
            detail: format!("node '{id}' tile input exceeds its scratch"),
        })?;
    let mut in_plane =
        PlaneMut::from_slice(in_sub, width, height, stride).map_err(|err| RenderError::Frame {
            detail: format!("node '{id}' tile input plane would not build: {err}"),
        })?;
    for row in 0..height {
        let src = view.row(row).map_err(|err| RenderError::Frame {
            detail: format!("node '{id}' tile input row {row} unreadable: {err}"),
        })?;
        let dst = in_plane.row_mut(row).map_err(|err| RenderError::Frame {
            detail: format!("node '{id}' tile input row {row} unwritable: {err}"),
        })?;
        if dst.len() != src.len() {
            return Err(RenderError::Frame {
                detail: format!("node '{id}' tile input row {row} lengths disagree"),
            });
        }
        dst.copy_from_slice(src);
    }
    Ok(in_len)
}

/// Calls the module's `process` on one filled tile; returns the tile's
/// output roi for the good-part copy.
fn process_tile(run: &mut TileRun<'_>, tile: &Tile, in_len: usize) -> Result<WireRoi, RenderError> {
    let id = run.node.id.clone();
    let (width, height) = tile_dims(&id, tile)?;
    let rows = usize::try_from(height).map_err(|_| RenderError::Frame {
        detail: format!("node '{id}' tile height overflows its row count"),
    })?;
    let stride_out = run.scratch_out.row_stride();
    let out_len = rows
        .checked_mul(stride_out)
        .ok_or_else(|| RenderError::Frame {
            detail: format!("node '{id}' tile output rows overflow"),
        })?;
    let out_sub = run
        .scratch_out
        .as_mut_slice()
        .get_mut(0..out_len)
        .ok_or_else(|| RenderError::Frame {
            detail: format!("node '{id}' tile output exceeds its scratch"),
        })?;
    let mut tile_out = PlaneMut::from_slice(out_sub, width, height, stride_out).map_err(|err| {
        RenderError::Frame {
            detail: format!("node '{id}' tile output plane would not build: {err}"),
        }
    })?;
    let stride_in = run.scratch_in.row_stride();
    let in_sub = run
        .scratch_in
        .as_slice()
        .get(0..in_len)
        .ok_or_else(|| RenderError::Frame {
            detail: format!("node '{id}' tile input exceeds its scratch"),
        })?;
    let tile_in =
        Plane::from_slice(in_sub, width, height, stride_in).map_err(|err| RenderError::Frame {
            detail: format!("node '{id}' tile input plane would not build: {err}"),
        })?;
    let oroi = tile_output_roi(run.node, run.geo, tile)?;
    run.node
        .module
        .process(
            &run.node.data,
            &tile_in,
            &mut tile_out,
            to_wire(&tile.input),
            oroi,
        )
        .map_err(|source| RenderError::Node {
            id,
            tile: Some((tile.tx, tile.ty)),
            source,
        })?;
    Ok(oroi)
}

/// Output roi for one tile: the tile's size at the output origin plus the
/// tile's offset into the input region (`tiling.c:740-741` shapes `iroi` and
/// `oroi` with the same per-tile origin math).
fn tile_output_roi(
    node: &CommittedNode,
    geo: &NodeGeometry,
    tile: &Tile,
) -> Result<WireRoi, RenderError> {
    let frame = |here: i32, base: i32| -> Result<i32, RenderError> {
        let offset = i64::from(here) - i64::from(base);
        i32::try_from(offset).map_err(|_| RenderError::Frame {
            detail: format!("node '{}' tile offset overflows", node.id),
        })
    };
    let dx = frame(tile.input.x, geo.input.x)?;
    let dy = frame(tile.input.y, geo.input.y)?;
    let ox = i64::from(geo.output.x) + i64::from(dx);
    let oy = i64::from(geo.output.y) + i64::from(dy);
    let (Ok(ox), Ok(oy)) = (i32::try_from(ox), i32::try_from(oy)) else {
        return Err(RenderError::Frame {
            detail: format!("node '{}' tile output origin overflows", node.id),
        });
    };
    Ok(WireRoi::new(
        ox,
        oy,
        tile.input.width,
        tile.input.height,
        geo.output.scale,
    ))
}

/// Copies one tile's good part from the scratch output into the full output.
fn copy_good_part(
    node: &CommittedNode,
    tile: &Tile,
    oroi: &WireRoi,
    scratch: &Frame,
    stride: usize,
    out: &mut Frame,
) -> Result<(), RenderError> {
    let fail = |what: &str| RenderError::Frame {
        detail: format!("node '{}' tile ({},{}): {what}", node.id, tile.tx, tile.ty),
    };
    let ox = i64::from(tile.output.x) - i64::from(oroi.x);
    let oy = i64::from(tile.output.y) - i64::from(oroi.y);
    let (Ok(ox), Ok(oy)) = (u32::try_from(ox), u32::try_from(oy)) else {
        return Err(fail("good part starts before its tile"));
    };
    let good_w = u32::try_from(tile.output.width).map_err(|_| fail("good width overflows"))?;
    let good_h = u32::try_from(tile.output.height).map_err(|_| fail("good height overflows"))?;
    let tile_h = u32::try_from(tile.input.height).map_err(|_| fail("tile height overflows"))?;
    let rows = usize::try_from(tile_h).map_err(|_| fail("tile height overflows its row count"))?;
    let sub_len = rows
        .checked_mul(stride)
        .ok_or_else(|| fail("tile rows overflow"))?;
    let sub = scratch
        .as_slice()
        .get(0..sub_len)
        .ok_or_else(|| fail("good part exceeds its scratch"))?;
    let tile_w = u32::try_from(tile.input.width).map_err(|_| fail("tile width overflows"))?;
    let src_plane =
        Plane::from_slice(sub, tile_w, tile_h, stride).map_err(|err| fail(&err.to_string()))?;
    let good_extent = FrameExtent::new(tile.output.x, tile.output.y, good_w, good_h);
    let mut dst = out
        .view_mut(good_extent)
        .map_err(|err| fail(&err.to_string()))?;
    let ox4 = usize::try_from(ox).map_err(|_| fail("good offset overflows"))?;
    let good4 = usize::try_from(good_w).map_err(|_| fail("good width overflows"))?;
    let (Some(ox4), Some(good4)) = (ox4.checked_mul(4), good4.checked_mul(4)) else {
        return Err(fail("good columns overflow"));
    };
    for row in 0..good_h {
        let src_row = oy
            .checked_add(row)
            .ok_or_else(|| fail("good rows overflow"))?;
        let src = src_plane
            .row(src_row)
            .map_err(|err| fail(&err.to_string()))?;
        let seg = src
            .get(ox4..ox4 + good4)
            .ok_or_else(|| fail("good columns leave their row"))?;
        let dst_row = dst.row_mut(row).map_err(|err| fail(&err.to_string()))?;
        if dst_row.len() != seg.len() {
            return Err(fail("good row lengths disagree"));
        }
        dst_row.copy_from_slice(seg);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use lightamer_geom::Roi as GeomRoi;
    use lightamer_iop_traits::{ColorSpace, ImageInfo};
    use lightamer_raster::{Frame, FrameExtent, PixelFormat};
    use lightamer_testkit::IdentityModule;
    use serde_json::json;
    use std::sync::Arc;

    use super::{Pipe, RenderError, RenderRequest};
    use crate::chain::{PipeNode, forward};
    use crate::fakes::{
        FakeBackendFail, FakeBadRoi, FakeCopy, FakeFail, FakeGain, FakeMem, FakePosition,
        FakeScale, FakeScaleCopy, FakeSource, Probe, no_params, table,
    };
    use crate::kinds::PipeKind;

    const GIB: u64 = 1024 * 1024 * 1024;

    fn image() -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Rgb)
    }

    fn extent(x: i32, y: i32, w: u32, h: u32) -> FrameExtent {
        FrameExtent::new(x, y, w, h)
    }

    fn filled_frame(x: i32, y: i32, w: u32, h: u32, value: f32) -> Frame {
        let len = w as usize * h as usize * 4;
        Frame::from_parts(
            vec![value; len],
            extent(x, y, w, h),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap()
    }

    #[expect(clippy::cast_precision_loss)] // test frames are small; the conversion is exact
    fn pattern_frame(w: u32, h: u32) -> Frame {
        let len = w as usize * h as usize * 4;
        let buf: Vec<f32> = (0..len).map(|i| i as f32 * 0.125 - 3.0).collect();
        Frame::from_parts(buf, extent(0, 0, w, h), PixelFormat::RgbaF32Premul).unwrap()
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

    /// Renders `nodes` on `pipe` with no cancellation; panics only on
    /// unexpected render errors (tests assert the error cases separately).
    fn render_ok(
        pipe: &mut Pipe,
        nodes: &[PipeNode],
        lookup: &impl crate::chain::ModuleLookup,
        image: &ImageInfo,
        input: &Frame,
        final_out: GeomRoi,
    ) -> super::OutputFrame {
        let no_cancel = || false;
        let req = RenderRequest {
            nodes,
            lookup,
            image,
            input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        pipe.render(&req).unwrap()
    }

    #[test]
    fn identity_chain_renders_bitwise() {
        let module = Arc::new(IdentityModule::new());
        let lookup = table(vec![module]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let out = render_ok(
            &mut pipe,
            &[node("test_identity")],
            &lookup,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(out.frame().extent(), input.extent());
        assert_eq!(out.frame().as_slice(), input.as_slice());
    }

    #[test]
    fn two_and_three_node_chains_match_input() {
        let probes = [
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
        ];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
            Arc::new(FakeCopy::new("mod_c", Arc::clone(&probes[2]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let nodes: Vec<PipeNode> = ["mod_a", "mod_b", "mod_c"]
            .iter()
            .map(|id| node(id))
            .collect();
        let out = render_ok(
            &mut pipe,
            &nodes[0..2],
            &lookup,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(out.frame().as_slice(), input.as_slice());
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (1, 1, 0)
        );
        pipe.clear_cache();
        let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(out.frame().as_slice(), input.as_slice());
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (2, 2, 1)
        );
    }

    #[test]
    fn empty_chain_copies_input_uncached() {
        let lookup = table(vec![]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let out = render_ok(&mut pipe, &[], &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(out.frame().as_slice(), input.as_slice());
        assert_eq!(pipe.cache_len(), 0);
        drop(out);
        assert_eq!(pipe.budget().used(), 0);
    }

    #[test]
    fn scale_chain_nodes_receive_forward_geometry() {
        // [up 2/1, down 1/2], final 64: forward gives node0 (64 -> 128) and
        // node1 (128 -> 64); both directions round-trip on even sizes.
        let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
        let lookup = table(vec![
            Arc::new(FakeScaleCopy::new("mod_up", Arc::clone(&probes[0]), 2, 1)),
            Arc::new(FakeScaleCopy::new("mod_down", Arc::clone(&probes[1]), 1, 2)),
        ]);
        let image = image();
        let input = filled_frame(0, 0, 64, 64, 0.5);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let nodes = vec![node("mod_up"), node("mod_down")];
        let out = render_ok(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input,
            geom(0, 0, 64, 64),
        );
        assert_eq!(out.frame().extent(), extent(0, 0, 64, 64));
        assert!(
            out.frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == 1.0f32.to_bits())
        );
        // Each node saw exactly the forward pass's regions.
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 64, 64)).unwrap();
        assert_eq!(geos[0].input, geom(0, 0, 64, 64));
        assert_eq!(geos[0].output, geom(0, 0, 128, 128));
        assert_eq!(geos[1].input, geom(0, 0, 128, 128));
        assert_eq!(geos[1].output, geom(0, 0, 64, 64));
        for (probe, geo) in probes.iter().zip(geos.iter()) {
            assert_eq!(probe.calls(), 1);
            let regions = probe.regions();
            assert_eq!(regions.len(), 1);
            let (rin, rout) = regions[0];
            assert_eq!(
                (rin.x, rin.y, rin.width, rin.height),
                (geo.input.x, geo.input.y, geo.input.width, geo.input.height)
            );
            assert_eq!(
                (rout.x, rout.y, rout.width, rout.height),
                (
                    geo.output.x,
                    geo.output.y,
                    geo.output.width,
                    geo.output.height
                )
            );
        }
    }

    #[test]
    fn empty_input_node_still_runs() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeSource::new(
            "mod_src",
            Arc::clone(&probe),
            8,
            8,
        ))]);
        let image = image();
        let input = filled_frame(0, 0, 0, 0, 0.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let out = render_ok(
            &mut pipe,
            &[node("mod_src")],
            &lookup,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(out.frame().extent(), extent(0, 0, 8, 8));
        assert!(
            out.frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == 3.0f32.to_bits())
        );
        assert_eq!(probe.calls(), 1);
        let (rin, rout) = probe.regions()[0];
        assert_eq!((rin.width, rin.height), (0, 0));
        assert_eq!((rout.width, rout.height), (8, 8));
    }

    #[test]
    fn second_identical_render_calls_no_process() {
        let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let nodes = vec![node("mod_a"), node("mod_b")];
        let first = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(pipe.cache_len(), 2);
        let second = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!((probes[0].calls(), probes[1].calls()), (1, 1));
        assert_eq!(second.frame().as_slice(), first.frame().as_slice());
    }

    #[test]
    fn param_change_recomputes_node_and_downstream_only() {
        let probes = [
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
        ];
        let lookup = table(vec![
            Arc::new(FakeGain::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeGain::new("mod_b", Arc::clone(&probes[1]))),
            Arc::new(FakeGain::new("mod_c", Arc::clone(&probes[2]))),
        ]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let nodes = vec![
            gain_node("mod_a", 2.0),
            gain_node("mod_b", 3.0),
            gain_node("mod_c", 4.0),
        ];
        let first = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert!(
            first
                .frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == 24.0f32.to_bits())
        );
        // Only the middle gain changes: node 0 hits, nodes 1-2 recompute.
        let nodes = vec![
            gain_node("mod_a", 2.0),
            gain_node("mod_b", 5.0),
            gain_node("mod_c", 4.0),
        ];
        let second = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (1, 2, 2)
        );
        assert!(
            second
                .frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == 40.0f32.to_bits())
        );
    }

    #[test]
    fn upstream_hit_reuses_plane_without_realloc() {
        let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeGain::new("mod_b", Arc::clone(&probes[1]))),
        ]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let nodes = vec![node("mod_a"), gain_node("mod_b", 2.0)];
        render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        let before = pipe.cache.peek(keys[0]).unwrap();
        let nodes = vec![node("mod_a"), gain_node("mod_b", 3.0)];
        render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        // Node 0's key is unchanged (its params and upstream are): the cached
        // plane is the same allocation, not a fresh copy.
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        let after = pipe.cache.peek(keys[0]).unwrap();
        assert!(Arc::ptr_eq(&before, &after));
        assert_eq!(probes[0].calls(), 1);
    }

    #[test]
    fn cache_isolated_across_pipe_kinds() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes = vec![node("mod_a")];
        let mut preview = Pipe::with_budget_and_floor(PipeKind::Preview, GIB, 0);
        render_ok(
            &mut preview,
            &nodes,
            &lookup,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(probe.calls(), 1);
        // Same settings on Full: the Preview plane must not serve it.
        let mut full = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let out = render_ok(&mut full, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(probe.calls(), 2);
        assert_eq!(out.frame().as_slice(), input.as_slice());
    }

    #[test]
    fn cache_isolated_across_process_versions() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes = vec![node("mod_a")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        for process in [1u32, 1, 2] {
            let req = RenderRequest {
                nodes: &nodes,
                lookup: &lookup,
                image: &image,
                input: &input,
                input_id: 7,
                process,
                final_out: geom(0, 0, 8, 8),
                cancel: &no_cancel,
            };
            pipe.render(&req).unwrap();
        }
        // Same version hits; the new version misses everything.
        assert_eq!(probe.calls(), 2);
    }

    #[test]
    fn input_id_change_recomputes_everything() {
        let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes = vec![node("mod_a"), node("mod_b")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        for input_id in [7u64, 7, 9] {
            let req = RenderRequest {
                nodes: &nodes,
                lookup: &lookup,
                image: &image,
                input: &input,
                input_id,
                process: 1,
                final_out: geom(0, 0, 8, 8),
                cancel: &no_cancel,
            };
            pipe.render(&req).unwrap();
        }
        assert_eq!((probes[0].calls(), probes[1].calls()), (2, 2));
    }
    #[test]
    fn tight_budget_skips_cache_renders_ok_and_returns_bytes() {
        // One 8x8 plane is 1024 bytes; a 1024-byte budget renders one node
        // but keeps nothing (the plane tops the 512-byte half-budget cap, so
        // the immediate insert refuses it).
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes = vec![node("mod_a")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 1_024, 0);
        let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(out.frame().as_slice(), input.as_slice());
        assert_eq!(pipe.cache_len(), 0);
        // The grant follows the frame: held while the caller holds the
        // output, back once the last holder drops.
        assert_eq!(pipe.budget().used(), 1_024);
        drop(out);
        assert_eq!(pipe.budget().used(), 0);
        // And the second render recomputes (nothing was kept).
        let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(probe.calls(), 2);
        drop(out);
        assert_eq!(pipe.budget().used(), 0);
    }

    #[test]
    fn render_level_cache_evicts_least_recently_used() {
        // 8x8 planes (1024 bytes), one node, 4096-byte budget: the cache keeps
        // half the budget (two planes); older gains evict in order.
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeGain::new("mod_g", Arc::clone(&probe)))]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 4_096, 0);
        for gain in [1.0, 2.0, 3.0, 4.0, 5.0] {
            render_ok(
                &mut pipe,
                &[gain_node("mod_g", gain)],
                &lookup,
                &image,
                &input,
                geom(0, 0, 8, 8),
            );
        }
        assert_eq!(probe.calls(), 5);
        assert_eq!(pipe.cache_len(), 2);
        // Gains 1-3 are gone (miss), gain 5 is cached (hit).
        render_ok(
            &mut pipe,
            &[gain_node("mod_g", 1.0)],
            &lookup,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(probe.calls(), 6);
        render_ok(
            &mut pipe,
            &[gain_node("mod_g", 5.0)],
            &lookup,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(probe.calls(), 6);
    }

    #[test]
    fn tiled_copy_matches_untiled_bitwise() {
        // 64x64 frame (65_536 bytes), factor 8: a 200_000 budget tiles 3x3
        // (see the hand computation below); a 4 GiB budget stays untiled.
        let probe_tiled = Arc::new(Probe::new());
        let tiled_lookup = table(vec![Arc::new(FakeMem::new(
            "mod_m",
            Arc::clone(&probe_tiled),
            8.0,
            0,
        ))]);
        let probe_plain = Arc::new(Probe::new());
        let plain_lookup = table(vec![Arc::new(FakeMem::new(
            "mod_m",
            Arc::clone(&probe_plain),
            8.0,
            0,
        ))]);
        let image = image();
        let input = pattern_frame(64, 64);
        let nodes = vec![node("mod_m")];
        let mut tiled = Pipe::with_budget_and_floor(PipeKind::Full, 200_000, 0);
        let tiled_out = render_ok(
            &mut tiled,
            &nodes,
            &tiled_lookup,
            &image,
            &input,
            geom(0, 0, 64, 64),
        );
        let mut plain = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let plain_out = render_ok(
            &mut plain,
            &nodes,
            &plain_lookup,
            &image,
            &input,
            geom(0, 0, 64, 64),
        );
        assert_eq!(tiled_out.frame().as_slice(), plain_out.frame().as_slice());
        assert_eq!(tiled_out.frame().as_slice(), input.as_slice());
        // available = 200_000 - 2 * 65_536 = 68_928; singlebuffer = 8_616;
        // scale = 8_616 / 65_536 = 0.131 < 0.333, so sqrt shrink: 23x23
        // tiles, ceil(64 / 23) = 3 per side, 9 tiles, one process call each.
        assert_eq!(probe_tiled.calls(), 9);
        assert_eq!(probe_plain.calls(), 1);
        let regions = probe_tiled.regions();
        assert_eq!(regions.len(), 9);
        // The last column is boundary-clamped: 2 * 23 + 23 > 64, so 18 wide.
        assert!(
            regions
                .iter()
                .any(|(rin, _)| rin.x == 46 && rin.width == 18)
        );
    }

    #[test]
    fn tiled_position_matches_untiled_and_tiles_carry_overlap() {
        // FakePosition (factor 8, overlap 4) on 100x100 (160_000 bytes):
        // budget 400_000 tiles 6x6 (25x25 tiles, stride 17); the last column
        // clamps to 15 wide. Values depend only on absolute coordinates, so
        // tiled and untiled agree bitwise iff the good parts assemble right.
        let probe_tiled = Arc::new(Probe::new());
        let tiled_lookup = table(vec![Arc::new(FakePosition::new(
            "mod_p",
            Arc::clone(&probe_tiled),
        ))]);
        let probe_plain = Arc::new(Probe::new());
        let plain_lookup = table(vec![Arc::new(FakePosition::new(
            "mod_p",
            Arc::clone(&probe_plain),
        ))]);
        let image = image();
        let input = filled_frame(0, 0, 100, 100, 0.0);
        let nodes = vec![node("mod_p")];
        let mut tiled = Pipe::with_budget_and_floor(PipeKind::Full, 400_000, 0);
        let tiled_out = render_ok(
            &mut tiled,
            &nodes,
            &tiled_lookup,
            &image,
            &input,
            geom(0, 0, 100, 100),
        );
        let mut plain = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let plain_out = render_ok(
            &mut plain,
            &nodes,
            &plain_lookup,
            &image,
            &input,
            geom(0, 0, 100, 100),
        );
        assert_eq!(tiled_out.frame().as_slice(), plain_out.frame().as_slice());
        assert_eq!(probe_tiled.calls(), 36);
        assert_eq!(probe_plain.calls(), 1);
        let regions = probe_tiled.regions();
        // Every tile ran with its full input (overlap included): full tiles
        // are 25 wide, the clamped last column is 15.
        assert!(
            regions
                .iter()
                .all(|(rin, rout)| rin.width == rout.width && rin.height == rout.height)
        );
        assert!(regions.iter().any(|(rin, _)| rin.x == 0 && rin.width == 25));
        assert!(
            regions
                .iter()
                .any(|(rin, _)| rin.x == 85 && rin.width == 15)
        );
        // Overlap reaches the module: a middle tile's input starts a full
        // stride (17) in, so its first 4 columns overlap the neighbor.
        assert!(
            regions
                .iter()
                .any(|(rin, _)| rin.x == 17 && rin.width == 25)
        );
    }

    #[test]
    fn cancel_after_first_node_keeps_completed_planes() {
        // B1-b2 meaning: node 0's plane is complete under its
        // content-determined key, so the cancelled run keeps it; nodes 1-2
        // never ran and leave nothing behind.
        let probes = [
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
        ];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
            Arc::new(FakeCopy::new("mod_c", Arc::clone(&probes[2]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes = vec![node("mod_a"), node("mod_b"), node("mod_c")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        // Checks: entry, node 0, node 1...: firing on the third check cancels
        // after the first node ran.
        let checks = std::cell::Cell::new(0);
        let cancel = || {
            checks.set(checks.get() + 1);
            checks.get() >= 3
        };
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::Cancelled));
        assert_eq!(err.to_string(), "render cancelled");
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (1, 0, 0)
        );
        // Node 0's plane is cached, complete: its key resolves and its bytes
        // equal the copied input. Nodes 1-2 have no entries.
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        assert_eq!(pipe.cache_len(), 1);
        assert_eq!(
            pipe.cache.peek(keys[0]).unwrap().frame.as_slice(),
            input.as_slice()
        );
        assert!(pipe.cache.peek(keys[1]).is_none());
        assert!(pipe.cache.peek(keys[2]).is_none());
        assert_eq!(pipe.budget().used(), 1_024);
        // A clean re-render hits node 0 and runs nodes 1-2 once each.
        let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (1, 1, 1)
        );
        assert_eq!(out.frame().as_slice(), input.as_slice());
    }

    #[test]
    fn cancel_between_tiles_aborts_cleanly() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeMem::new(
            "mod_m",
            Arc::clone(&probe),
            8.0,
            0,
        ))]);
        let image = image();
        let input = pattern_frame(64, 64);
        let nodes = vec![node("mod_m")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 200_000, 0);
        // Checks: entry, node, tile 0, tile 1...: firing on the fourth check
        // cancels after the first tile ran (9 tiles without cancel). The node
        // never finished, so its half-written plane stays out of the cache:
        // cancel keeps completed planes, never partial ones.
        let checks = std::cell::Cell::new(0);
        let cancel = || {
            checks.set(checks.get() + 1);
            checks.get() >= 4
        };
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 64, 64),
            cancel: &cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::Cancelled));
        assert_eq!(probe.calls(), 1);
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }
    #[test]
    fn error_unknown_module_is_typed_and_restores_budget() {
        let lookup = table(vec![]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("mod_missing")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(
            err,
            RenderError::Chain(crate::chain::ChainError::UnknownModule(_))
        ));
        assert!(err.to_string().contains("unknown module 'mod_missing'"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn error_invalid_params_is_typed_and_restores_budget() {
        let lookup = table(vec![Arc::new(FakeFail::new("mod_fail"))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("mod_fail")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(
            err,
            RenderError::Chain(crate::chain::ChainError::Commit { .. })
        ));
        assert!(err.to_string().contains("mod_fail"));
        assert!(err.to_string().contains("invalid parameters"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn error_bad_roi_is_typed_and_restores_budget() {
        let lookup = table(vec![Arc::new(FakeBadRoi::new("mod_bad"))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("mod_bad")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(
            err,
            RenderError::Chain(crate::chain::ChainError::BadRoi { .. })
        ));
        assert!(err.to_string().contains("bad roi"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn error_roundtrip_is_typed_and_restores_budget() {
        // 3/2 scaling loses pixels both ways: the backward check disagrees.
        let lookup = table(vec![Arc::new(FakeScale::new("mod_mid", 3, 2))]);
        let image = image();
        let input = filled_frame(0, 0, 150, 100, 0.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("mod_mid")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 100, 100),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(
            err,
            RenderError::Chain(crate::chain::ChainError::Roundtrip { .. })
        ));
        assert!(err.to_string().contains("round-trip"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn error_color_gap_names_both_spaces() {
        let lookup = table(vec![
            Arc::new(
                FakeScale::new("mod_first", 1, 1).with_colors(ColorSpace::Rgb, ColorSpace::Lab),
            ),
            Arc::new(FakeScale::new("mod_second", 1, 1)),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("mod_first"), node("mod_second")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(
            matches!(err, RenderError::ColorGap { .. }),
            "expected ColorGap, got {err:?}"
        );
        if let RenderError::ColorGap { after, from, to } = &err {
            assert_eq!(*after, 0);
            assert_eq!((*from, *to), (ColorSpace::Lab, ColorSpace::Rgb));
        }
        assert!(err.to_string().contains("Lab"));
        assert!(err.to_string().contains("Rgb"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn error_module_backend_is_typed_and_restores_budget() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeBackendFail::new(
            "mod_boom",
            Arc::clone(&probe),
        ))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("mod_boom")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(
            matches!(err, RenderError::Node { .. }),
            "expected Node, got {err:?}"
        );
        if let RenderError::Node { id, tile, source } = &err {
            assert_eq!(id, "mod_boom");
            assert_eq!(*tile, None);
            assert!(matches!(
                source,
                lightamer_iop_traits::PipeError::Backend(_)
            ));
        }
        assert!(err.to_string().contains("backend error"));
        assert_eq!(probe.calls(), 1);
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn error_out_of_budget_returns_transient_bytes_after_full_eviction() {
        // B1-b2 meaning: the footprint pre-check now refuses frames no
        // budget this size can host, so a mid-run out-of-budget only happens
        // past evictable bytes — here two caller-held outputs pin the whole
        // 2048-byte budget while the cache holds one of their planes.
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 2_048, 0);
        let no_cancel = || false;
        // Two photos, one 8x8 node each; the caller holds both outputs.
        let mut held = Vec::new();
        for input_id in [7u64, 8] {
            let req = RenderRequest {
                nodes: &[node("mod_a")],
                lookup: &lookup,
                image: &image,
                input: &input,
                input_id,
                process: 1,
                final_out: geom(0, 0, 8, 8),
                cancel: &no_cancel,
            };
            held.push(pipe.render(&req).unwrap());
        }
        assert_eq!(pipe.cache_len(), 1);
        assert_eq!(pipe.budget().used(), 2_048);
        // A third photo: its footprint fits, but make-room evicts the last
        // cache entry (freeing nothing — the caller holds that plane) and the
        // allocation still refuses, typed.
        let req = RenderRequest {
            nodes: &[node("mod_a")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 9,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::OutOfBudget { .. }));
        assert!(err.to_string().contains("out of budget"));
        assert_eq!(probe.calls(), 2);
        assert_eq!(pipe.cache_len(), 0);
        // The failed render leaves nothing: only the caller's two planes are
        // charged, and dropping them returns every byte.
        assert_eq!(pipe.budget().used(), 2_048);
        drop(held);
        assert_eq!(pipe.budget().used(), 0);
    }

    #[test]
    fn error_input_mismatch_is_typed_and_restores_budget() {
        let lookup = table(vec![Arc::new(IdentityModule::new())]);
        let image = image();
        // Identity chain wanting 16x16, handed an 8x8 plane.
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("test_identity")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 16, 16),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::InputMismatch { .. }));
        assert!(err.to_string().contains("needs input"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn repeated_renders_agree_bitwise_hit_or_miss() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeGain::new("mod_g", Arc::clone(&probe)))]);
        let image = image();
        let input = pattern_frame(16, 16);
        let nodes = vec![gain_node("mod_g", 1.5)];
        // Miss, then hit on the same pipe.
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let miss = render_ok(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input,
            geom(0, 0, 16, 16),
        );
        let hit = render_ok(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input,
            geom(0, 0, 16, 16),
        );
        assert_eq!(probe.calls(), 1);
        assert_eq!(hit.frame().as_slice(), miss.frame().as_slice());
        // A second miss on a fresh pipe agrees too.
        let mut fresh = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let again = render_ok(
            &mut fresh,
            &nodes,
            &lookup,
            &image,
            &input,
            geom(0, 0, 16, 16),
        );
        assert_eq!(again.frame().as_slice(), miss.frame().as_slice());
    }

    #[test]
    fn one_thread_and_many_threads_agree_bitwise() {
        // Identity copies rows through the rayon helper: one lane or many,
        // the bytes are the same.
        let lookup = table(vec![Arc::new(IdentityModule::new())]);
        let image = image();
        let input = pattern_frame(32, 32);
        let nodes = vec![node("test_identity")];
        let one = rayon::ThreadPoolBuilder::new()
            .num_threads(1)
            .build()
            .unwrap();
        let many = rayon::ThreadPoolBuilder::new()
            .num_threads(8)
            .build()
            .unwrap();
        let solo = one.install(|| {
            let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
            render_ok(
                &mut pipe,
                &nodes,
                &lookup,
                &image,
                &input,
                geom(0, 0, 32, 32),
            )
        });
        let parallel = many.install(|| {
            let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
            render_ok(
                &mut pipe,
                &nodes,
                &lookup,
                &image,
                &input,
                geom(0, 0, 32, 32),
            )
        });
        assert_eq!(solo.frame().as_slice(), parallel.frame().as_slice());
        assert_eq!(solo.frame().as_slice(), input.as_slice());
    }
    /// Quiet-machine probe mirroring `Scripts/rust-budget.sh:load_busy`:
    /// returns the load line when the machine is quiet, `None` when the gate
    /// must not run (guard refuses or load1 per cpu tops 1.0).
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

    fn median_ms(mut samples: Vec<std::time::Duration>) -> f64 {
        samples.sort_unstable();
        let mid = samples.len() / 2;
        samples[mid].as_secs_f64() * 1_000.0
    }

    /// The 61 MP caller-built input shared by the idle timing tests (9504x6336
    /// float32 RGBA, ≈0.9 GiB; building it stays out of the clock).
    fn mp61_input() -> Frame {
        const WIDTH: u32 = 9504;
        const HEIGHT: u32 = 6336;
        let len = WIDTH as usize * HEIGHT as usize * 4;
        let mut buf = vec![0.25f32; len];
        buf[0] = 1.0;
        buf[len - 1] = -3.0;
        Frame::from_parts(buf, extent(0, 0, WIDTH, HEIGHT), PixelFormat::RgbaF32Premul).unwrap()
    }

    /// Idle timing: one 61 MP identity render (9504x6336 float32 RGBA), miss
    /// and hit medians over five rounds each, plus peak RSS. Ignored by
    /// default; run it on a quiet machine in release mode:
    /// `cargo test --release -p lightamer-pipeline --locked -- --ignored idle_61mp`.
    #[test]
    #[ignore = "timing bench: needs a quiet machine and a release build"]
    fn idle_61mp_reports_miss_and_hit_medians() {
        const WIDTH: u32 = 9504;
        const HEIGHT: u32 = 6336;
        const GATE_MISS_MS: f64 = 200.0;
        const STOP_RSS_BYTES: u64 = 4 * 1024 * 1024 * 1024;
        let Some(line) = quiet_line("idle 61mp") else {
            println!("idle-61mp = UNRELIABLE (machine busy; see load line) SKIP-GATE");
            return;
        };
        println!("idle-61mp {line}");
        // Input and decode stay out of the clock: the frame is caller-built.
        let len = WIDTH as usize * HEIGHT as usize * 4;
        let mut buf = vec![0.25f32; len];
        buf[0] = 1.0;
        buf[len - 1] = -3.0;
        let input = Frame::from_parts(buf, extent(0, 0, WIDTH, HEIGHT), PixelFormat::RgbaF32Premul)
            .unwrap();
        let lookup = table(vec![Arc::new(IdentityModule::new())]);
        let image = image();
        let nodes = vec![node("test_identity")];
        let final_out = GeomRoi::new(0, 0, 9504, 6336, 1.0).unwrap();
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
        // Misses: a fresh pipe every round (cold cache). The floor is the
        // Full value at 16 GiB (128 MiB); the fit check keeps this untiled.
        let mut misses = Vec::with_capacity(5);
        for _ in 0..5 {
            let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 4 * GIB, 128 * 1024 * 1024);
            let start = std::time::Instant::now();
            let out = pipe.render(&req).unwrap();
            misses.push(start.elapsed());
            assert_eq!(out.frame().as_slice(), input.as_slice());
        }
        // Hits: one warm pipe, re-rendered.
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 4 * GIB, 128 * 1024 * 1024);
        let warm = pipe.render(&req).unwrap();
        assert_eq!(warm.frame().as_slice(), input.as_slice());
        let mut hits = Vec::with_capacity(5);
        for _ in 0..5 {
            let start = std::time::Instant::now();
            let out = pipe.render(&req).unwrap();
            hits.push(start.elapsed());
            assert_eq!(out.frame().as_slice(), input.as_slice());
        }
        let miss_ms = median_ms(misses);
        let hit_ms = median_ms(hits);
        let peak = peak_rss_bytes();
        println!(
            "idle-61mp miss median = {miss_ms:.1}ms over 5 rounds (gate <={GATE_MISS_MS:.0}ms)"
        );
        println!("idle-61mp hit median = {hit_ms:.3}ms over 5 rounds");
        println!("idle-61mp peak rss = {}MB", peak / 1024 / 1024);
        assert!(
            peak < STOP_RSS_BYTES,
            "peak rss {peak} tops the 4 GiB stop line"
        );
        assert!(
            miss_ms <= GATE_MISS_MS,
            "miss median {miss_ms:.1}ms tops the 200ms gate"
        );
    }
    /// Idle timing, five nodes: 61 MP through five identity nodes on the Full
    /// quota a 16 GiB machine derives (`2_748_779_069` B budget, 128 MiB floor).
    /// B1-b stages every node's plane to the end of the run, so this peaks at
    /// five frames (≈4.5 GiB) and fails out of budget; B1-b2 inserts each
    /// plane as its node completes and must render it. Ignored by default; run
    /// it on a quiet machine in release mode:
    /// `cargo test --release -p lightamer-pipeline --locked -- --ignored idle_61mp_five_nodes`.
    #[test]
    #[ignore = "timing bench: needs a quiet machine and a release build"]
    fn idle_61mp_five_nodes_reports_miss_median() {
        const BUDGET_16GIB_FULL: u64 = 2_748_779_069;
        const FLOOR_16GIB_FULL: u64 = 128 * 1024 * 1024;
        const GATE_MISS_MS: f64 = 1_000.0;
        const STOP_RSS_BYTES: u64 = 4 * 1024 * 1024 * 1024;
        let Some(line) = quiet_line("idle 61mp five nodes") else {
            println!("idle-61mp-five = UNRELIABLE (machine busy; see load line) SKIP-GATE");
            return;
        };
        println!("idle-61mp-five {line}");
        let input = mp61_input();
        let lookup = table(vec![Arc::new(IdentityModule::new())]);
        let image = image();
        let nodes = vec![node("test_identity"); 5];
        let final_out = GeomRoi::new(0, 0, 9504, 6336, 1.0).unwrap();
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
        // Misses: a fresh pipe every round (cold cache).
        let mut misses = Vec::with_capacity(5);
        for _ in 0..5 {
            let mut pipe =
                Pipe::with_budget_and_floor(PipeKind::Full, BUDGET_16GIB_FULL, FLOOR_16GIB_FULL);
            let start = std::time::Instant::now();
            let out = pipe.render(&req).unwrap();
            misses.push(start.elapsed());
            assert_eq!(out.frame().as_slice(), input.as_slice());
        }
        let miss_ms = median_ms(misses);
        let peak = peak_rss_bytes();
        println!(
            "idle-61mp-five miss median = {miss_ms:.1}ms over 5 rounds (gate <={GATE_MISS_MS:.0}ms)"
        );
        println!("idle-61mp-five peak rss = {}MB", peak / 1024 / 1024);
        assert!(
            peak < STOP_RSS_BYTES,
            "peak rss {peak} tops the 4 GiB stop line"
        );
        assert!(
            miss_ms <= GATE_MISS_MS,
            "miss median {miss_ms:.1}ms tops the 1000ms gate"
        );
    }

    #[test]
    fn error_frame_overflow_is_typed_and_restores_budget() {
        // i32::MAX squared fits u64 but not times 16 bytes: the byte count
        // overflows before any plane is allocated.
        let lookup = table(vec![Arc::new(IdentityModule::new())]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &[node("test_identity")],
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: GeomRoi::new(0, 0, i32::MAX, i32::MAX, 1.0).unwrap(),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::Frame { .. }));
        assert!(err.to_string().contains("overflows"));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn warm_cache_cancel_keeps_completed_planes() {
        // B1-b2 meaning: same assertions as B1-b, new reason — node 0 hits
        // (no process call, recency touched at once) and node 1 never runs,
        // so both completed planes stay cached, complete.
        let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes = vec![node("mod_a"), node("mod_b")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(pipe.cache_len(), 2);
        // Same request, cancelled at the second node: node 0 hits, node 1
        // never runs and adds nothing.
        let checks = std::cell::Cell::new(0);
        let cancel = || {
            checks.set(checks.get() + 1);
            checks.get() >= 3
        };
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::Cancelled));
        assert_eq!((probes[0].calls(), probes[1].calls()), (1, 1));
        assert_eq!(pipe.cache_len(), 2);
        assert_eq!(pipe.budget().used(), 2 * 1_024);
        // Both entries resolve under their keys with the copied bytes.
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        assert_eq!(
            pipe.cache.peek(keys[0]).unwrap().frame.as_slice(),
            input.as_slice()
        );
        assert_eq!(
            pipe.cache.peek(keys[1]).unwrap().frame.as_slice(),
            input.as_slice()
        );
    }
    /// Renders `nodes` on `pipe` under `input_id` with no cancellation.
    fn render_with_id(
        pipe: &mut Pipe,
        nodes: &[PipeNode],
        lookup: &impl crate::chain::ModuleLookup,
        image: &ImageInfo,
        input: &Frame,
        input_id: u64,
        final_out: GeomRoi,
    ) -> super::OutputFrame {
        let no_cancel = || false;
        let req = RenderRequest {
            nodes,
            lookup,
            image,
            input,
            input_id,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        pipe.render(&req).unwrap()
    }

    /// Six chained copy fakes (`mod_a`..`mod_f`) with one probe each.
    fn six_copies() -> (
        [Arc<Probe>; 6],
        std::collections::HashMap<String, crate::chain::SharedModule>,
        Vec<PipeNode>,
    ) {
        let probes = [
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
        ];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
            Arc::new(FakeCopy::new("mod_c", Arc::clone(&probes[2]))),
            Arc::new(FakeCopy::new("mod_d", Arc::clone(&probes[3]))),
            Arc::new(FakeCopy::new("mod_e", Arc::clone(&probes[4]))),
            Arc::new(FakeCopy::new("mod_f", Arc::clone(&probes[5]))),
        ]);
        let nodes = vec![
            node("mod_a"),
            node("mod_b"),
            node("mod_c"),
            node("mod_d"),
            node("mod_e"),
            node("mod_f"),
        ];
        (probes, lookup, nodes)
    }

    /// Six chained gain fakes with per-node gains and one probe each.
    fn six_gains(
        gains: [f64; 6],
    ) -> (
        [Arc<Probe>; 6],
        std::collections::HashMap<String, crate::chain::SharedModule>,
        Vec<PipeNode>,
    ) {
        let ids = ["mod_a", "mod_b", "mod_c", "mod_d", "mod_e", "mod_f"];
        let probes = [
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
        ];
        let lookup = table(vec![
            Arc::new(FakeGain::new(ids[0], Arc::clone(&probes[0]))),
            Arc::new(FakeGain::new(ids[1], Arc::clone(&probes[1]))),
            Arc::new(FakeGain::new(ids[2], Arc::clone(&probes[2]))),
            Arc::new(FakeGain::new(ids[3], Arc::clone(&probes[3]))),
            Arc::new(FakeGain::new(ids[4], Arc::clone(&probes[4]))),
            Arc::new(FakeGain::new(ids[5], Arc::clone(&probes[5]))),
        ]);
        let nodes = vec![
            gain_node(ids[0], gains[0]),
            gain_node(ids[1], gains[1]),
            gain_node(ids[2], gains[2]),
            gain_node(ids[3], gains[3]),
            gain_node(ids[4], gains[4]),
            gain_node(ids[5], gains[5]),
        ];
        (probes, lookup, nodes)
    }

    #[test]
    fn six_node_chain_renders_within_three_frame_budget() {
        // Six 8x8 planes (1024 bytes each) on a 3072-byte budget: B1-b staged
        // all six to the end of the run and refused; B1-b2 inserts each
        // finished plane at once, so the peak is two frames plus the
        // half-budget cache and the render succeeds.
        let (probes, lookup, nodes) = six_copies();
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 3_072, 0);
        let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        assert_eq!(out.frame().as_slice(), input.as_slice());
        for probe in &probes {
            assert_eq!(probe.calls(), 1);
        }
        // The 1536-byte half-budget cap keeps one plane: the last insert
        // evicted the rest, and the output shares it.
        assert_eq!(pipe.cache_len(), 1);
        assert_eq!(pipe.budget().used(), 1_024);
    }

    #[test]
    fn cancel_after_third_node_keeps_completed_planes() {
        // Cancelling at the fourth node keeps the first three planes — each
        // complete under its key — and nothing else.
        let (probes, lookup, nodes) = six_copies();
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        // Checks: entry, nodes 0-2, node 3...: firing on the fifth check
        // cancels before the fourth node runs.
        let checks = std::cell::Cell::new(0);
        let cancel = || {
            checks.set(checks.get() + 1);
            checks.get() >= 5
        };
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::Cancelled));
        assert_eq!(
            (
                probes[0].calls(),
                probes[1].calls(),
                probes[2].calls(),
                probes[3].calls(),
                probes[4].calls(),
                probes[5].calls()
            ),
            (1, 1, 1, 0, 0, 0)
        );
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        assert_eq!(pipe.cache_len(), 3);
        for key in keys.iter().take(3) {
            assert_eq!(
                pipe.cache.peek(*key).unwrap().frame.as_slice(),
                input.as_slice()
            );
        }
        for key in keys.iter().skip(3) {
            assert!(pipe.cache.peek(*key).is_none());
        }
        assert_eq!(pipe.budget().used(), 3_072);
        // A clean re-render hits the first three and runs the last three.
        let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
        for probe in &probes {
            assert_eq!(probe.calls(), 1);
        }
        assert_eq!(out.frame().as_slice(), input.as_slice());
    }

    #[test]
    fn error_after_completed_nodes_keeps_completed_planes() {
        // Nodes 0-1 finish, node 2 fails its process: the error is typed and
        // the two finished planes stay cached, complete; swapping in a
        // working node 2 reuses them (their keys never changed).
        let probes = [
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
            Arc::new(Probe::new()),
        ];
        let failing = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
            Arc::new(FakeBackendFail::new("mod_boom", Arc::clone(&probes[2]))),
        ]);
        let fixed = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
            Arc::new(FakeCopy::new("mod_c", Arc::clone(&probes[2]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let nodes_failing = vec![node("mod_a"), node("mod_b"), node("mod_boom")];
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes_failing,
            lookup: &failing,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(err, RenderError::Node { .. }));
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (1, 1, 1)
        );
        let chain = crate::chain::build_chain(&failing, &nodes_failing, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes_failing, &geos);
        assert_eq!(pipe.cache_len(), 2);
        assert_eq!(
            pipe.cache.peek(keys[0]).unwrap().frame.as_slice(),
            input.as_slice()
        );
        assert_eq!(
            pipe.cache.peek(keys[1]).unwrap().frame.as_slice(),
            input.as_slice()
        );
        assert!(pipe.cache.peek(keys[2]).is_none());
        assert_eq!(pipe.budget().used(), 2_048);
        // The fixed chain reuses nodes 0-1 (same keys) and runs only node 2.
        let nodes_fixed = vec![node("mod_a"), node("mod_b"), node("mod_c")];
        let chain = crate::chain::build_chain(&fixed, &nodes_fixed, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let fixed_keys = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes_fixed, &geos);
        assert_eq!(fixed_keys[0], keys[0]);
        assert_eq!(fixed_keys[1], keys[1]);
        let out = render_ok(
            &mut pipe,
            &nodes_fixed,
            &fixed,
            &image,
            &input,
            geom(0, 0, 8, 8),
        );
        assert_eq!(
            (probes[0].calls(), probes[1].calls(), probes[2].calls()),
            (1, 1, 2)
        );
        assert_eq!(out.frame().as_slice(), input.as_slice());
    }

    #[test]
    fn render_level_eviction_takes_oldest_first() {
        // 4096-byte budget: the cache keeps two 8x8 planes. Photo A fills it
        // with two nodes; photo B's single node then evicts A's oldest entry
        // while its newer one survives.
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 4_096, 0);
        let nodes_a = vec![node("mod_a"), node("mod_a")];
        render_with_id(
            &mut pipe,
            &nodes_a,
            &lookup,
            &image,
            &input,
            7,
            geom(0, 0, 8, 8),
        );
        let chain = crate::chain::build_chain(&lookup, &nodes_a, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys_a = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes_a, &geos);
        assert_eq!(pipe.cache_len(), 2);
        let nodes_b = vec![node("mod_a")];
        let out = render_with_id(
            &mut pipe,
            &nodes_b,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        assert_eq!(out.frame().as_slice(), input.as_slice());
        let chain = crate::chain::build_chain(&lookup, &nodes_b, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys_b = crate::cache::chain_keys(PipeKind::Full, 9, 1, &nodes_b, &geos);
        // Oldest first: A's node 1 entry (oldest after the success-touch
        // reversal) yields, node 0 survives beside B.
        assert!(pipe.cache.peek(keys_a[1]).is_none());
        assert_eq!(
            pipe.cache.peek(keys_a[0]).unwrap().frame.as_slice(),
            input.as_slice()
        );
        assert!(pipe.cache.peek(keys_b[0]).is_some());
        assert_eq!(pipe.cache_len(), 2);
        assert_eq!(pipe.budget().used(), 2_048);
    }

    #[test]
    fn allocation_evicts_cache_until_plane_fits() {
        // 2560-byte budget: photo A caches one 8x8 plane (1024 bytes); photo
        // B's 8x16 plane (2048 bytes) does not fit beside it, so make-room
        // evicts A's entry and the render succeeds uncached (2048 tops the
        // 1280-byte half-budget cap).
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe)))]);
        let image = image();
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 2_560, 0);
        let input_a = pattern_frame(8, 8);
        let nodes = vec![node("mod_a")];
        render_with_id(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input_a,
            7,
            geom(0, 0, 8, 8),
        );
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys_a = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        assert_eq!(pipe.cache_len(), 1);
        assert_eq!(pipe.budget().used(), 1_024);
        let input_b = pattern_frame(8, 16);
        let out = render_with_id(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input_b,
            9,
            geom(0, 0, 8, 16),
        );
        assert_eq!(out.frame().as_slice(), input_b.as_slice());
        assert_eq!(probe.calls(), 2);
        assert!(pipe.cache.peek(keys_a[0]).is_none());
        assert_eq!(pipe.cache_len(), 0);
        assert_eq!(pipe.budget().used(), 2_048);
        drop(out);
        assert_eq!(pipe.budget().used(), 0);
    }

    #[test]
    fn make_room_evicts_around_planes_hit_this_run() {
        // 10240-byte budget, half-budget cache of 5120: photo A caches two
        // 8x8 planes; the same photo scaled 3x then hits node 0 (protected)
        // and make-room evicts only the stale node 1 entry for the 24x24
        // plane (9216 bytes), which stays uncached past the cap.
        let copy_probe = Arc::new(Probe::new());
        let scale_probe = Arc::new(Probe::new());
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&copy_probe))),
            Arc::new(FakeScaleCopy::new("mod_s", Arc::clone(&scale_probe), 3, 1)),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 10_240, 0);
        let nodes_a = vec![node("mod_a"), node("mod_a")];
        render_with_id(
            &mut pipe,
            &nodes_a,
            &lookup,
            &image,
            &input,
            7,
            geom(0, 0, 8, 8),
        );
        let chain = crate::chain::build_chain(&lookup, &nodes_a, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys_a = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes_a, &geos);
        let held_a0 = pipe.cache.peek(keys_a[0]).unwrap();
        let nodes_b = vec![node("mod_a"), node("mod_s")];
        let chain = crate::chain::build_chain(&lookup, &nodes_b, &image).unwrap();
        let geos = forward(&chain, &GeomRoi::new(0, 0, 24, 24, 1.0).unwrap()).unwrap();
        let keys_b = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes_b, &geos);
        // Same photo, same node 0 prefix: the hit key never moved.
        assert_eq!(keys_b[0], keys_a[0]);
        let out = render_with_id(
            &mut pipe,
            &nodes_b,
            &lookup,
            &image,
            &input,
            7,
            GeomRoi::new(0, 0, 24, 24, 1.0).unwrap(),
        );
        assert_eq!(out.frame().as_slice().len(), 24 * 24 * 4);
        assert!(
            out.frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == 1.0f32.to_bits())
        );
        // Node 0 hit (no third copy call); the scaler ran once.
        assert_eq!(copy_probe.calls(), 2);
        assert_eq!(scale_probe.calls(), 1);
        // Make-room took the stale entry; the hit entry survived with the
        // same allocation.
        assert!(pipe.cache.peek(keys_a[1]).is_none());
        let kept = pipe.cache.peek(keys_a[0]).unwrap();
        assert!(Arc::ptr_eq(&held_a0, &kept));
        assert_eq!(pipe.cache_len(), 1);
        assert_eq!(pipe.budget().used(), 10_240);
        drop(out);
        drop(held_a0);
        drop(kept);
        assert_eq!(pipe.budget().used(), 1_024);
    }

    #[test]
    fn pipe_reports_max_frame_bytes_per_kind() {
        // (budget − 2 × floor) / 2 at the 16 GiB derivations, pinned exactly.
        const MIB: u64 = 1024 * 1024;
        let total = 16 * 1024 * MIB;
        for (kind, budget, floor, max) in [
            (PipeKind::Full, 2_748_779_069, 128 * MIB, 1_240_171_806),
            (PipeKind::Export, 2_748_779_069, 128 * MIB, 1_240_171_806),
            (PipeKind::Preview, 858_993_459, 64 * MIB, 362_387_865),
            (PipeKind::Thumbnail, 515_396_075, 32 * MIB, 224_143_605),
        ] {
            let quota = crate::kinds::quota_for(kind, total);
            assert_eq!(quota.memory_budget, budget, "{kind:?}");
            let floor_got = crate::kinds::singlebuffer_floor(kind, total);
            assert_eq!(floor_got, floor, "{kind:?}");
            let pipe = Pipe::with_budget_and_floor(kind, budget, floor);
            assert_eq!(pipe.max_frame_bytes(), max, "{kind:?}");
        }
        // Floor zero: exactly half the budget. A floor past half the budget
        // saturates the maximum at zero instead of underflowing.
        let pipe = Pipe::with_budget_and_floor(PipeKind::Full, 2_048, 0);
        assert_eq!(pipe.max_frame_bytes(), 1_024);
        let pipe = Pipe::with_budget_and_floor(PipeKind::Full, 2_048, 2_048);
        assert_eq!(pipe.max_frame_bytes(), 0);
    }

    #[test]
    fn renders_at_max_frame_boundary_succeed_per_kind() {
        // Budget 2048, floor 0: the maximum is 1024, and a two-node 8x8 chain
        // (node 1 needs exactly input + output = 2048) renders on every kind.
        for kind in [
            PipeKind::Full,
            PipeKind::Export,
            PipeKind::Preview,
            PipeKind::Thumbnail,
        ] {
            let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
            let lookup = table(vec![
                Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
                Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
            ]);
            let image = image();
            let input = pattern_frame(8, 8);
            let nodes = vec![node("mod_a"), node("mod_b")];
            let mut pipe = Pipe::with_budget_and_floor(kind, 2_048, 0);
            assert_eq!(pipe.max_frame_bytes(), 1_024, "{kind:?}");
            let out = render_ok(&mut pipe, &nodes, &lookup, &image, &input, geom(0, 0, 8, 8));
            assert_eq!(out.frame().as_slice(), input.as_slice(), "{kind:?}");
            assert_eq!((probes[0].calls(), probes[1].calls()), (1, 1), "{kind:?}");
            assert!(pipe.budget().used() <= 2_048, "{kind:?}");
        }
    }

    #[test]
    fn oversized_frame_is_typed_and_leaves_no_trace() {
        // Node 1 needs input + output = 2048 bytes; a 2047-byte budget
        // refuses before anything runs: no process call, no bytes charged,
        // nothing cached.
        let probes = [Arc::new(Probe::new()), Arc::new(Probe::new())];
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probes[0]))),
            Arc::new(FakeCopy::new("mod_b", Arc::clone(&probes[1]))),
        ]);
        let image = image();
        let input = pattern_frame(8, 8);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 2_047, 0);
        let no_cancel = || false;
        let nodes = vec![node("mod_a"), node("mod_b")];
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(
            err,
            RenderError::FrameTooLarge {
                node: 1,
                need_bytes: 2_048,
                budget_bytes: 2_047
            }
        ));
        assert!(err.to_string().contains("too large"));
        assert_eq!((probes[0].calls(), probes[1].calls()), (0, 0));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
        // A single node that alone tops the budget names node 0.
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 1_023, 0);
        let nodes = vec![node("mod_a")];
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        let err = pipe.render(&req).unwrap_err();
        assert!(matches!(
            err,
            RenderError::FrameTooLarge {
                node: 0,
                need_bytes: 1_024,
                budget_bytes: 1_023
            }
        ));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
    }

    #[test]
    fn cross_photo_eviction_then_selective_recompute() {
        // Fix 1 + fix 2 strung together on a budget that fits three 8x8
        // frames (3072 bytes): photo A fills the cache, photo B's six-node
        // chain renders through it (A's entries yield), and — on a roomy pipe
        // holding the same six-node shape — editing node 2 recomputes only
        // nodes 2-5. One pipe cannot show both: the tight pipe's half-budget
        // cache keeps a single plane, so no six-node prefix survives it; the
        // roomy leg pins the recompute shape the tight leg's keys already
        // determine.
        let (probes, lookup, nodes) = six_gains([2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut tight = Pipe::with_budget_and_floor(PipeKind::Full, 3_072, 0);
        // Photo A fills the cache (one plane: the half-budget cap binds).
        let out_a = render_with_id(
            &mut tight,
            &nodes,
            &lookup,
            &image,
            &input,
            7,
            geom(0, 0, 8, 8),
        );
        assert_eq!(tight.cache_len(), 1);
        // Photo B's six-node chain renders through A's entries.
        let out_b = render_with_id(
            &mut tight,
            &nodes,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let product = 2.0f32 * 3.0 * 4.0 * 5.0 * 6.0 * 7.0;
        assert!(
            out_b
                .frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == product.to_bits())
        );
        // A's entries are all gone; the budget never topped.
        let chain = crate::chain::build_chain(&lookup, &nodes, &image).unwrap();
        let geos = forward(&chain, &geom(0, 0, 8, 8)).unwrap();
        let keys_a = crate::cache::chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        for key in &keys_a {
            assert!(tight.cache.peek(*key).is_none());
        }
        assert_eq!(tight.cache_len(), 1);
        assert!(tight.budget().used() <= 3_072);
        for probe in &probes {
            assert_eq!(probe.calls(), 2);
        }
        drop(out_a);
        drop(out_b);
        // Roomy leg: the same six-node shape, editing node 2 hits nodes 0-1
        // and recomputes nodes 2-5.
        let (probes, lookup, nodes) = six_gains([2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
        let mut roomy = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        render_with_id(
            &mut roomy,
            &nodes,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let mut edited = nodes.clone();
        edited[2] = gain_node("mod_c", 8.0);
        let out = render_with_id(
            &mut roomy,
            &edited,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let calls: Vec<usize> = probes.iter().map(|probe| probe.calls()).collect();
        assert_eq!(calls, vec![1, 1, 2, 2, 2, 2]);
        let product = 2.0f32 * 3.0 * 8.0 * 5.0 * 6.0 * 7.0;
        assert!(
            out.frame()
                .as_slice()
                .iter()
                .all(|v| v.to_bits() == product.to_bits())
        );
    }
    #[test]
    fn trace_reports_miss_then_hit_with_matching_call_counts() {
        let (probes, lookup, nodes) = six_gains([2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        render_with_id(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let trace = pipe.last_trace();
        assert_eq!(trace.len(), 6);
        for (index, report) in trace.iter().enumerate() {
            assert!(!report.hit, "node {index} should miss cold");
            assert_eq!(report.process_calls, 1);
            assert!(report.millis >= 0.0);
            assert_eq!(report.multi, 0);
        }
        assert_eq!(trace[0].id, "mod_a");
        assert_eq!(trace[5].id, "mod_f");
        render_with_id(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let trace = pipe.last_trace();
        assert_eq!(trace.len(), 6);
        for (index, report) in trace.iter().enumerate() {
            assert!(report.hit, "node {index} should hit warm");
            assert_eq!(report.process_calls, 0);
            assert_eq!(report.millis.to_bits(), 0.0f64.to_bits());
        }
        for probe in &probes {
            assert_eq!(probe.calls(), 1);
        }
    }

    #[test]
    fn trace_reports_partial_recompute_after_param_edit() {
        let (probes, lookup, nodes) = six_gains([2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        render_with_id(
            &mut pipe,
            &nodes,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let mut edited = nodes.clone();
        edited[2] = gain_node("mod_c", 8.0);
        render_with_id(
            &mut pipe,
            &edited,
            &lookup,
            &image,
            &input,
            9,
            geom(0, 0, 8, 8),
        );
        let trace = pipe.last_trace();
        let hits: Vec<bool> = trace.iter().map(|report| report.hit).collect();
        assert_eq!(hits, vec![true, true, false, false, false, false]);
        let calls: Vec<usize> = probes.iter().map(|probe| probe.calls()).collect();
        assert_eq!(calls, vec![1, 1, 2, 2, 2, 2]);
        for report in trace.iter().filter(|report| !report.hit) {
            assert_eq!(report.process_calls, 1);
        }
    }

    #[test]
    fn trace_counts_tiles_for_tiled_nodes() {
        let probe = Arc::new(Probe::new());
        let lookup = table(vec![Arc::new(FakeMem::new(
            "mod_m",
            Arc::clone(&probe),
            8.0,
            0,
        ))]);
        let image = image();
        let input = pattern_frame(64, 64);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 200_000, 0);
        render_ok(
            &mut pipe,
            &[node("mod_m")],
            &lookup,
            &image,
            &input,
            geom(0, 0, 64, 64),
        );
        let trace = pipe.last_trace();
        assert_eq!(trace.len(), 1);
        assert!(!trace[0].hit);
        assert_eq!(trace[0].process_calls, 9);
        assert_eq!(probe.calls(), 9);
        assert!(trace[0].millis >= 0.0);
    }

    #[test]
    fn trace_keeps_completed_prefix_on_failure() {
        let probe_ok = Arc::new(Probe::new());
        let probe_boom = Arc::new(Probe::new());
        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::clone(&probe_ok))),
            Arc::new(FakeBackendFail::new("mod_boom", Arc::clone(&probe_boom))),
        ]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        let nodes = vec![node("mod_a"), node("mod_boom")];
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &image,
            input: &input,
            input_id: 7,
            process: 1,
            final_out: geom(0, 0, 8, 8),
            cancel: &no_cancel,
        };
        assert!(pipe.render(&req).is_err());
        let trace = pipe.last_trace();
        assert_eq!(trace.len(), 1);
        assert_eq!(trace[0].id, "mod_a");
        assert!(!trace[0].hit);
        assert_eq!(trace[0].process_calls, 1);
        assert_eq!(probe_ok.calls(), 1);
    }

    #[test]
    fn trace_is_empty_for_empty_chain() {
        let lookup = table(vec![]);
        let image = image();
        let input = filled_frame(0, 0, 8, 8, 1.0);
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, GIB, 0);
        render_ok(&mut pipe, &[], &lookup, &image, &input, geom(0, 0, 8, 8));
        assert!(pipe.last_trace().is_empty());
    }
}
