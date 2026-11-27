// SPDX-License-Identifier: GPL-3.0-or-later
//! Pipeline: chains, geometry, tiling, negotiation, execution, pipe kinds.
//!
//! The caller passes committed-ready nodes in execution order (registry
//! order); this crate commits them ([`chain`]), walks regions forward and
//! back ([`chain::forward`], [`chain::backward_check`]), decides whole-frame
//! vs tiled ([`tiling`]), plans colorspace conversions ([`negotiate::negotiate`]),
//! and pairs frames with budget grants ([`budgeted`]).
//! Execution (rendering, caching, tiling runs) lives in [`render`].
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

pub mod budgeted;
pub mod cache;
pub mod chain;
pub mod kinds;
pub mod negotiate;
pub mod render;
pub mod spill;
pub mod stream;
pub mod tiling;

#[cfg(test)]
mod fakes;

pub use budgeted::{BudgetedError, BudgetedFrame, SharedFrame, alloc_frame, alloc_shared};
pub use chain::{
    ChainError, CommittedNode, ModuleLookup, NodeGeometry, PipeNode, SharedModule, backward_check,
    build_chain, forward,
};
pub use kinds::{
    PipeKind, PipeQuota, quota, quota_for, singlebuffer_floor, system_physical_memory,
};
pub use negotiate::{ColorPlan, ColorStep, negotiate};
pub use render::{NodeReport, OutputFrame, Pipe, RenderError, RenderRequest};
pub use spill::{MappedFrame, StreamSink, StreamedOutput};
pub use stream::{
    BLOCK_MAX_SIDE, BLOCK_MIN_SIDE, STREAM_BYTES_PER_PIXEL, STRIP_ROWS, StreamMode, StreamPiece,
    StreamPiecePlan, StreamPlan, StreamRefusal, StreamSummary, plan_stream,
};
pub use tiling::{MAX_TILES, Tile, TileGrid, TilingDecision, decide};
