// SPDX-License-Identifier: GPL-3.0-or-later
//! Color management: the lcms2 leg plus matrix math.
//!
//! [`white_point_from_temp`] is the only lcms2 call in the workspace: the
//! temperature module's daylight spectrum needs it, and the later `colorin`
//! / `colorout` modules will build on this crate. Everything else here is
//! plain math over stack arrays.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

/// CIE xy white point of a daylight source at `temp_kelvin`: thin wrapper
/// over lcms2's `cmsWhitePointFromTemp` (what upstream's `_spd_daylight`
/// calls at `src/iop/temperature.c:329`).
///
/// [`None`] when lcms2 refuses the temperature (outside its valid range).
/// Links the system lcms2 via `lcms2-sys`' default dynamic feature, the
/// same library the oracle's C side links, so both sides compute this
/// identically.
#[must_use]
pub fn white_point_from_temp(temp_kelvin: f64) -> Option<(f64, f64)> {
    lcms2::white_point_from_temp(temp_kelvin).map(|white| (white.x, white.y))
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
    fn white_point_known_value() {
        // D65 neighborhood at 6504 K (lcms2 computes it, so this only pins
        // the wiring, not the algorithm: observed 0.3127/0.32912).
        let (x, y) = super::white_point_from_temp(6504.0).expect("valid temp");
        assert!((x - 0.3127).abs() < 5e-4, "x = {x}");
        assert!((y - 0.3290).abs() < 5e-4, "y = {y}");
    }
}
