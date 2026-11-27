// SPDX-License-Identifier: GPL-3.0-or-later
//! `lightamer-cli`: oracle对照工具——取官方包、调 `darktable-cli` 渲染、比对 16 位 PNG、写 XMP 夹具。
//!
//! Thin CLI over [`fetch`], [`render`], [`cmp`], [`xmp`] and [`selftest`];
//! `Scripts/oracle.sh` only forwards to this binary.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

// EPIPE-safe `println!`: the standard macro panics when stdout is a closed
// pipe (`lightamer-cli ... | head -1`); this one exits quietly instead (see
// `util::print_stdout`). Textually scoped: shadows `std::println!` for this
// crate only, with identical formatting syntax.
macro_rules! println {
    ($($arg:tt)*) => {
        $crate::util::print_stdout_line(&format!($($arg)*))
    };
}

pub mod bench;
pub mod capabilities;
pub mod cmp;
pub mod commands;
pub mod decode;
pub mod fetch;
pub mod render;
pub mod render_demo;
pub mod selftest;
pub mod stream_demo;
pub mod util;
pub mod xmp;
