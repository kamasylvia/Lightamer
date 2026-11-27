// SPDX-License-Identifier: GPL-3.0-or-later
//! Tiling requests: how much memory a module needs per tile.

use super::Roi;

/// Memory/overlap/alignment needs of one module, mirroring
/// `dt_develop_tiling_t` (`src/develop/tiling.h:25-41`).
///
/// The `_cl` fields are the GPU side; the CPU path fills them equal to their
/// host twins (as `default_tiling_callback` does) and never reads them.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TilingReq {
    /// Memory as a multiple of the image buffer (host).
    pub factor: f32,
    /// Memory as a multiple of the image buffer (GPU; filled, unread).
    pub factor_cl: f32,
    /// Largest temp buffer as a multiple of the image buffer (host).
    pub maxbuf: f32,
    /// Largest temp buffer as a multiple of the image buffer (GPU; unread).
    pub maxbuf_cl: f32,
    /// Flat on-top requirement in bytes, independent of input size.
    pub overhead: u64,
    /// Pixels of overlap needed between neighbor tiles.
    pub overlap: u32,
    /// Tile origins align to multiples of this.
    pub align: u32,
}

impl TilingReq {
    /// darktable's default callback (`src/develop/tiling.c:1903-1921`):
    /// factor `1 + out_area / in_area`, `maxbuf` 1, no overhead, no overlap,
    /// align 1.
    ///
    /// Two documented deviations: an empty input area yields factor 2
    /// (upstream divides by zero into `inf`); the `TILING_FULL_ROI` overlap-4
    /// branch has no counterpart yet (our flags vocabulary has no such bit).
    #[must_use]
    pub fn default_for(roi_in: &Roi, roi_out: &Roi) -> Self {
        let in_area = f64::from(roi_in.width.max(0)) * f64::from(roi_in.height.max(0));
        let out_area = f64::from(roi_out.width.max(0)) * f64::from(roi_out.height.max(0));
        let factor = if in_area > 0.0 {
            1.0 + out_area / in_area
        } else {
            2.0
        };
        // Areas stay below 2^62, so the ratio stays far below `f32::MAX`;
        // the downcast keeps ~7 digits, plenty for a memory multiple.
        #[allow(clippy::cast_possible_truncation)]
        let factor = factor as f32;
        Self {
            factor,
            factor_cl: factor,
            maxbuf: 1.0,
            maxbuf_cl: 1.0,
            overhead: 0,
            overlap: 0,
            align: 1,
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{Roi, TilingReq};

    #[test]
    fn default_factor_is_one_plus_area_ratio() {
        let rin = Roi::new(0, 0, 100, 100, 1.0);
        let rout = Roi::new(0, 0, 50, 50, 1.0);
        let req = TilingReq::default_for(&rin, &rout);
        assert_eq!(req.factor, 1.25);
        assert_eq!(req.factor_cl, 1.25);
        assert_eq!((req.maxbuf, req.maxbuf_cl), (1.0, 1.0));
        assert_eq!((req.overhead, req.overlap, req.align), (0, 0, 1));
    }

    #[test]
    fn default_factor_for_identity_is_two() {
        let roi = Roi::new(0, 0, 64, 64, 1.0);
        assert_eq!(TilingReq::default_for(&roi, &roi).factor, 2.0);
    }

    #[test]
    fn empty_input_yields_factor_two_not_inf() {
        let empty = Roi::new(0, 0, 0, 0, 1.0);
        let out = Roi::new(0, 0, 64, 64, 1.0);
        let req = TilingReq::default_for(&empty, &out);
        assert_eq!(req.factor, 2.0);
        assert!(req.factor.is_finite());
    }
}
