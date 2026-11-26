// SPDX-License-Identifier: GPL-3.0-or-later
//! Apple platform capabilities, probed once and read as plain data.
//!
//! This is the only workspace crate allowed to touch Apple frameworks (see
//! `docs/APPLE-BOUNDARY.md`). Everything outside this crate reads
//! [`capabilities()`] and never writes `cfg(target_os)`.
//!
//! The public surface carries no framework types: only [`Backend`],
//! [`Capabilities`], and standard-library types cross the boundary.
//!
//! ```rust
//! let caps = dt_apple::capabilities();
//! assert!(matches!(
//!     caps.backend,
//!     dt_apple::Backend::Empty | dt_apple::Backend::MacOs
//! ));
//! ```
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

mod capabilities;
mod empty;
#[cfg(target_os = "macos")]
mod macos;

pub use capabilities::{
    Backend, Capabilities, ImageFormat, StandardSpaces, VisionRequests, capabilities,
};
