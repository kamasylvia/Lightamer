// SPDX-License-Identifier: GPL-3.0-or-later
//! Roi wire shape for module calls.

/// Region of interest as modules see it: plain data, same five fields as
/// `dt_iop_roi_t` (`src/develop/pixelpipe.h:36-39`).
///
/// This is deliberately not the op-rich `lightamer_geom::Roi`: same-layer
/// rules forbid this crate from depending on it, so the trait carries its
/// own wire shape and the pipeline converts field by field (validating at
/// the `lightamer_geom` boundary). Modules must echo back well-formed rois;
/// garbage is rejected there with the module blamed.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Roi {
    /// Left edge.
    pub x: i32,
    /// Top edge.
    pub y: i32,
    /// Width in pixels.
    pub width: i32,
    /// Height in pixels.
    pub height: i32,
    /// Resolution relative to the decoded frame.
    pub scale: f32,
}

impl Roi {
    /// Builds a wire roi; no validation (the geometry crate owns that).
    #[must_use]
    pub const fn new(x: i32, y: i32, width: i32, height: i32, scale: f32) -> Self {
        Self {
            x,
            y,
            width,
            height,
            scale,
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::Roi;

    #[test]
    fn wire_shape_round_trips_its_five_fields() {
        let roi = Roi::new(-3, 7, 100, 60, 0.5);
        assert_eq!((roi.x, roi.y, roi.width, roi.height), (-3, 7, 100, 60));
        assert_eq!(roi.scale.to_bits(), 0.5f32.to_bits());
        assert_eq!(roi, roi);
    }
}
