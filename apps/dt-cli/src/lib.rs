// SPDX-License-Identifier: GPL-3.0-or-later
//! `dt-cli`: oracle对照工具——取官方包、调 `darktable-cli` 渲染、比对 16 位 PNG、写 XMP 夹具。
//!
//! Thin CLI over [`fetch`], [`render`], [`cmp`], [`xmp`] and [`selftest`];
//! `Scripts/oracle.sh` only forwards to this binary.

pub mod capabilities;
pub mod cmp;
pub mod commands;
pub mod fetch;
pub mod render;
pub mod selftest;
pub mod util;
pub mod xmp;
