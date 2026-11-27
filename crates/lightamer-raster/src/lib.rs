// SPDX-License-Identifier: GPL-3.0-or-later
//! Float pixel buffers shared by the pipeline.
//!
//! A [`Frame`] is a pixel buffer plus the [`FrameExtent`] it covers plus its
//! [`PixelFormat`]. The working format is 32-bit float RGBA, premultiplied
//! alpha. Buffers are plain `Vec<f32>`; the pipeline pairs each allocation
//! with a memory-budget grant from the `lightamer-sysmem` crate — this crate
//! only does checked size math, it never sees the budget (L0 crates take no
//! workspace dependencies).
//!
//! Access is bounds-checked everywhere: row ranges for parallel disjoint
//! writes, sub-region views for reads and writes, whole-frame copy. Sizes
//! are computed in `u64`; overflow is [`RasterError`], never a wrap.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

mod format;
mod frame;

pub use format::PixelFormat;
pub use frame::{Frame, FrameExtent, FrameView, FrameViewMut, RasterError};
