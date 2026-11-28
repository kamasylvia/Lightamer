// SPDX-License-Identifier: GPL-3.0-or-later
//! Geometry modules, auto-discovered from `src/modules/*/mod.rs`.
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

/// Re-exported implemented-module table; see `modules::IMPLEMENTED`.
pub use modules::IMPLEMENTED;

/// Looks up an implemented module by id; [`None`] for stubs and unknowns.
pub fn lookup_implemented(id: &str) -> Option<lightamer_iop_traits::SharedModule> {
    modules::IMPLEMENTED
        .iter()
        .find(|entry| entry.0 == id)
        .map(|entry| (entry.1)())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
    #[test]
    fn implemented_modules_resolve_and_stay_described() {
        for entry in super::IMPLEMENTED {
            assert!(super::lookup_implemented(entry.0).is_some());
            assert!(super::MODULES.iter().any(|desc| desc.id == entry.0));
        }
        assert!(super::lookup_implemented("__no_such_module__").is_none());
        for desc in super::MODULES {
            let listed = super::IMPLEMENTED.iter().any(|entry| entry.0 == desc.id);
            assert_eq!(super::lookup_implemented(desc.id).is_some(), listed);
        }
    }
}
