// SPDX-License-Identifier: GPL-3.0-or-later
//! Exclusive features: pano/focus/HDR merge, node DRT, versions, AI (phase C fills it).
//! Named `lightamer-ai`, not `lightamer-lightamer`: this crate holds Lightamer's own AI features, and the mechanical rename would stutter.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
