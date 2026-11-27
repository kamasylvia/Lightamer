// SPDX-License-Identifier: GPL-3.0-or-later
//! Pipeline foundation: chains, geometry, tiling, negotiation, pipe kinds.
//!
//! The caller passes committed-ready nodes in execution order (registry
//! order); this crate commits them ([`chain`]), walks regions forward and
//! back ([`chain::forward`], [`chain::backward_check`]), decides whole-frame
//! vs tiled ([`tiling`]), plans colorspace conversions ([`negotiate::negotiate`]),
//! and pairs frames with budget grants ([`budgeted`]).
//! Execution (caching, row parallelism, tile runs, render jobs) is B1-b.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

pub mod budgeted;
pub mod chain;
pub mod kinds;
pub mod negotiate;
pub mod tiling;

#[cfg(test)]
mod fakes;

pub use budgeted::{BudgetedError, BudgetedFrame, alloc_frame};
pub use chain::{
    ChainError, CommittedNode, ModuleLookup, NodeGeometry, PipeNode, SharedModule, backward_check,
    build_chain, forward,
};
pub use kinds::{PipeKind, PipeQuota, quota};
pub use negotiate::{ColorPlan, ColorStep, negotiate};
pub use tiling::{MAX_TILES, Tile, TileGrid, TilingDecision, decide};
