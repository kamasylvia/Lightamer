// SPDX-License-Identifier: GPL-3.0-or-later
//! Geometry primitives for the pixel pipeline: regions of interest.
//!
//! [`Roi`] mirrors `dt_iop_roi_t` (`src/develop/pixelpipe.h:36-39` in
//! `refs/dt-master`): integer `x`/`y`/`width`/`height` plus a float `scale`.
//! All scale conversions round exactly the way darktable does; each rule cites
//! the upstream line in its rustdoc. Integer arithmetic is checked: overflow
//! is [`RoiError`], never a wrap or a panic.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

mod roi;

pub use roi::{Roi, RoiError};
