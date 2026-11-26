// SPDX-License-Identifier: GPL-3.0-or-later
//! Display-referred modules, auto-discovered from `src/modules/*/mod.rs`.
//!
//! Each child directory holding a `mod.rs` file is one module. The build
//! script scans the directory at compile time and generates the `mod`
//! declarations plus the `MODULES` table, so adding a module is adding a
//! directory; no list in the core changes.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

/// Auto-discovered modules (generated; see `build.rs`).
pub mod modules {
    include!(concat!(env!("OUT_DIR"), "/modules_gen.rs"));
}

/// Re-exported descriptor table; see `modules::MODULES`.
pub use modules::MODULES;

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
