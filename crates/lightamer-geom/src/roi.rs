// SPDX-License-Identifier: GPL-3.0-or-later
//! Region of interest: integer rect plus pipeline scale.

use std::fmt;

/// Region of interest, mirroring `dt_iop_roi_t`
/// (`src/develop/pixelpipe.h:36-39` in `refs/dt-master`).
///
/// `x`/`y`/`width`/`height` are full pipeline pixels at [`Roi::scale`]: a roi
/// covering the whole decoded frame at scale `s` has
/// `width = full_width * s` (subject to the rounding rules below).
/// `scale == 1.0` is full resolution. Width or height zero means "no pixels"
/// (a module reporting it needs no input); negative sizes are rejected by
/// [`Roi::new`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Roi {
    /// Left edge, may be negative for overhanging requests.
    pub x: i32,
    /// Top edge, may be negative for overhanging requests.
    pub y: i32,
    /// Width in pixels, zero means empty.
    pub width: i32,
    /// Height in pixels, zero means empty.
    pub height: i32,
    /// Resolution relative to the decoded frame; always finite and positive.
    pub scale: f32,
}

/// Why a [`Roi`] operation failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RoiError {
    /// Scale was zero, negative, or non-finite.
    BadScale,
    /// Width or height was negative.
    NegativeSize,
    /// Integer arithmetic overflowed.
    Overflow,
    /// The two operands live at different scales.
    ScaleMismatch,
    /// The requested sub-region is not inside its parent.
    OutOfBounds,
}

impl fmt::Display for RoiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RoiError::BadScale => write!(f, "roi scale must be finite and positive"),
            RoiError::NegativeSize => write!(f, "roi width and height must not be negative"),
            RoiError::Overflow => write!(f, "roi coordinate arithmetic overflowed"),
            RoiError::ScaleMismatch => write!(f, "roi operands live at different scales"),
            RoiError::OutOfBounds => write!(f, "sub-region is not inside its parent roi"),
        }
    }
}

impl std::error::Error for RoiError {}

impl Roi {
    /// Builds a roi, validating size and scale.
    ///
    /// # Errors
    ///
    /// [`RoiError::NegativeSize`] for negative `width`/`height` (zero is a
    /// valid empty roi); [`RoiError::BadScale`] for a zero, negative, or
    /// non-finite `scale`.
    pub fn new(x: i32, y: i32, width: i32, height: i32, scale: f32) -> Result<Self, RoiError> {
        if width < 0 || height < 0 {
            return Err(RoiError::NegativeSize);
        }
        if !scale.is_finite() || scale <= 0.0 {
            return Err(RoiError::BadScale);
        }
        Ok(Self {
            x,
            y,
            width,
            height,
            scale,
        })
    }

    /// Whether this roi covers no pixels.
    #[must_use]
    pub fn is_empty(self) -> bool {
        self.width <= 0 || self.height <= 0
    }

    /// Exclusive right edge, `x + width`.
    ///
    /// # Errors
    ///
    /// [`RoiError::Overflow`] when the sum leaves `i32`.
    pub fn x_end(self) -> Result<i32, RoiError> {
        self.x.checked_add(self.width).ok_or(RoiError::Overflow)
    }

    /// Exclusive bottom edge, `y + height`.
    ///
    /// # Errors
    ///
    /// [`RoiError::Overflow`] when the sum leaves `i32`.
    pub fn y_end(self) -> Result<i32, RoiError> {
        self.y.checked_add(self.height).ok_or(RoiError::Overflow)
    }

    /// Pixel count as `u64`; empty rois report 0.
    #[must_use]
    pub fn area_u64(self) -> u64 {
        if self.is_empty() {
            return 0;
        }
        // Non-negative by construction (`new` rejects negatives); the
        // fallback only guards the impossible.
        u64::try_from(self.width).unwrap_or(0) * u64::try_from(self.height).unwrap_or(0)
    }
    /// Intersection of two rois at the same scale.
    ///
    /// # Errors
    ///
    /// [`RoiError::ScaleMismatch`] when the scales differ;
    /// [`RoiError::Overflow`] when an edge sum leaves `i32`.
    pub fn intersect(self, other: Self) -> Result<Self, RoiError> {
        if self.scale.to_bits() != other.scale.to_bits() {
            return Err(RoiError::ScaleMismatch);
        }
        let x = self.x.max(other.x);
        let y = self.y.max(other.y);
        let x_end = self.x_end()?.min(other.x_end()?);
        let y_end = self.y_end()?.min(other.y_end()?);
        // i64: corner differences can exceed i32 at extreme coordinates.
        let width = (i64::from(x_end) - i64::from(x)).clamp(0, i64::from(i32::MAX));
        let height = (i64::from(y_end) - i64::from(y)).clamp(0, i64::from(i32::MAX));
        Ok(Self {
            x,
            y,
            width: i32::try_from(width).map_err(|_| RoiError::Overflow)?,
            height: i32::try_from(height).map_err(|_| RoiError::Overflow)?,
            scale: self.scale,
        })
    }

    /// Smallest roi at the same scale enclosing both operands.
    ///
    /// The union of two empty rois is empty at their shared scale.
    ///
    /// # Errors
    ///
    /// [`RoiError::ScaleMismatch`] when the scales differ;
    /// [`RoiError::Overflow`] when an edge sum leaves `i32`, or when the
    /// true union is wider than `i32`.
    pub fn union(self, other: Self) -> Result<Self, RoiError> {
        if self.scale.to_bits() != other.scale.to_bits() {
            return Err(RoiError::ScaleMismatch);
        }
        if self.is_empty() {
            return Ok(other);
        }
        if other.is_empty() {
            return Ok(self);
        }
        let x = self.x.min(other.x);
        let y = self.y.min(other.y);
        let x_end = self.x_end()?.max(other.x_end()?);
        let y_end = self.y_end()?.max(other.y_end()?);
        // i64: a true union wider than i32 is an honest overflow, not a clamp.
        let width = i32::try_from(i64::from(x_end) - i64::from(x));
        let height = i32::try_from(i64::from(y_end) - i64::from(y));
        let (Ok(width), Ok(height)) = (width, height) else {
            return Err(RoiError::Overflow);
        };
        Ok(Self {
            x,
            y,
            width,
            height,
            scale: self.scale,
        })
    }

    /// Moves the roi by `(dx, dy)`; size and scale are unchanged.
    ///
    /// # Errors
    ///
    /// [`RoiError::Overflow`] when a corner sum leaves `i32`.
    pub fn translate(self, dx: i32, dy: i32) -> Result<Self, RoiError> {
        Ok(Self {
            x: self.x.checked_add(dx).ok_or(RoiError::Overflow)?,
            y: self.y.checked_add(dy).ok_or(RoiError::Overflow)?,
            width: self.width,
            height: self.height,
            scale: self.scale,
        })
    }

    /// Whether `other` lies fully inside `self`, edges included.
    ///
    /// Scales must match bitwise; a scale mismatch reports `false` rather
    /// than comparing across resolutions. An empty roi contains only an empty
    /// roi at its own origin-or-inside position; anything with pixels inside
    /// nothing reports `false`.
    #[must_use]
    pub fn contains(self, other: Self) -> bool {
        if self.scale.to_bits() != other.scale.to_bits() {
            return false;
        }
        if other.is_empty() {
            return other.width == 0
                && other.height == 0
                && other.x >= self.x
                && other.y >= self.y
                && other.x.saturating_add(other.width) <= self.x.saturating_add(self.width)
                && other.y.saturating_add(other.height) <= self.y.saturating_add(self.height);
        }
        if self.is_empty() {
            return false;
        }
        other.x >= self.x
            && other.y >= self.y
            && other
                .x_end()
                .is_ok_and(|end| end <= self.x.saturating_add(self.width))
            && other
                .y_end()
                .is_ok_and(|end| end <= self.y.saturating_add(self.height))
    }

    /// Whether the point `(x, y)` lies inside, right/bottom edges excluded.
    #[must_use]
    pub fn contains_point(self, x: i32, y: i32) -> bool {
        !self.is_empty()
            && x >= self.x
            && y >= self.y
            && x < self.x.saturating_add(self.width)
            && y < self.y.saturating_add(self.height)
    }

    /// Sub-region at offset `(x, y)` with size `width` by `height`, inheriting
    /// the scale. Offsets are relative to this roi's origin.
    ///
    /// # Errors
    ///
    /// [`RoiError::NegativeSize`] for negative sizes;
    /// [`RoiError::OutOfBounds`] when the sub-region is not fully inside;
    /// [`RoiError::Overflow`] when a corner sum leaves `i32`.
    pub fn sub(self, x: i32, y: i32, width: i32, height: i32) -> Result<Self, RoiError> {
        if width < 0 || height < 0 {
            return Err(RoiError::NegativeSize);
        }
        let abs_x = self.x.checked_add(x).ok_or(RoiError::Overflow)?;
        let abs_y = self.y.checked_add(y).ok_or(RoiError::Overflow)?;
        let end_x = abs_x.checked_add(width).ok_or(RoiError::Overflow)?;
        let end_y = abs_y.checked_add(height).ok_or(RoiError::Overflow)?;
        let self_end_x = self.x_end()?;
        let self_end_y = self.y_end()?;
        if x < 0 || y < 0 || end_x > self_end_x || end_y > self_end_y {
            return Err(RoiError::OutOfBounds);
        }
        Ok(Self {
            x: abs_x,
            y: abs_y,
            width,
            height,
            scale: self.scale,
        })
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{Roi, RoiError};

    fn roi(x: i32, y: i32, w: i32, h: i32) -> Roi {
        Roi::new(x, y, w, h, 1.0).unwrap()
    }

    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }

    #[test]
    fn new_rejects_negative_size_but_accepts_empty() {
        assert_eq!(Roi::new(0, 0, -1, 4, 1.0), Err(RoiError::NegativeSize));
        assert_eq!(Roi::new(0, 0, 4, -1, 1.0), Err(RoiError::NegativeSize));
        let empty = Roi::new(3, 5, 0, 0, 1.0).unwrap();
        assert!(empty.is_empty());
        assert_eq!(empty.area_u64(), 0);
    }

    #[test]
    fn new_rejects_zero_negative_and_nonfinite_scale() {
        assert_eq!(Roi::new(0, 0, 4, 4, 0.0), Err(RoiError::BadScale));
        assert_eq!(Roi::new(0, 0, 4, 4, -1.0), Err(RoiError::BadScale));
        assert_eq!(Roi::new(0, 0, 4, 4, f32::NAN), Err(RoiError::BadScale));
        assert_eq!(Roi::new(0, 0, 4, 4, f32::INFINITY), Err(RoiError::BadScale));
    }

    #[test]
    fn intersect_clips_to_overlap_and_scale_must_match() {
        let a = roi(0, 0, 10, 10);
        let b = roi(4, 6, 10, 10);
        assert_eq!(a.intersect(b).unwrap(), roi(4, 6, 6, 4));
        let disjoint = roi(20, 20, 5, 5);
        let hit = a.intersect(disjoint).unwrap();
        assert!(hit.is_empty());
        let scaled = Roi::new(0, 0, 10, 10, 0.5).unwrap();
        assert_eq!(a.intersect(scaled), Err(RoiError::ScaleMismatch));
    }

    #[test]
    fn union_encloses_both_and_empty_is_neutral() {
        let a = roi(0, 0, 10, 10);
        let b = roi(4, 6, 10, 10);
        assert_eq!(a.union(b).unwrap(), roi(0, 0, 14, 16));
        let empty = roi(99, 99, 0, 0);
        assert_eq!(a.union(empty).unwrap(), a);
        assert_eq!(empty.union(a).unwrap(), a);
    }

    #[test]
    fn translate_moves_origin_and_checks_overflow() {
        assert_eq!(
            roi(2, 3, 10, 10).translate(5, -2).unwrap(),
            roi(7, 1, 10, 10)
        );
        // 0 + MAX fits; 1 + MAX does not.
        assert!(roi(0, 0, 1, 1).translate(i32::MAX, 0).is_ok());
        assert_eq!(
            roi(1, 0, 1, 1).translate(i32::MAX, 0),
            Err(RoiError::Overflow)
        );
        assert_eq!(roi(0, 0, 1, 1).x_end(), Ok(1));
        assert_eq!(
            Roi::new(i32::MAX, 0, 1, 1, 1.0).unwrap().x_end(),
            Err(RoiError::Overflow)
        );
    }

    #[test]
    fn contains_needs_same_scale_and_full_enclosure() {
        let outer = roi(-4, -4, 20, 20);
        assert!(outer.contains(roi(0, 0, 4, 4)));
        assert!(outer.contains(outer));
        assert!(!outer.contains(roi(0, 0, 40, 4)));
        assert!(!outer.contains(Roi::new(0, 0, 4, 4, 0.5).unwrap()));
        assert!(!roi(0, 0, 0, 0).contains(roi(0, 0, 1, 1)));
        assert!(outer.contains_point(0, 0));
        assert!(!outer.contains_point(16, 16));
        assert!(!outer.contains_point(-5, 0));
    }

    #[test]
    fn sub_is_relative_and_clamped_by_parent() {
        let parent = roi(10, 20, 100, 60);
        assert_eq!(parent.sub(5, 5, 10, 10).unwrap(), roi(15, 25, 10, 10));
        assert_eq!(parent.sub(0, 0, 100, 60).unwrap(), parent);
        assert_eq!(parent.sub(-1, 0, 10, 10), Err(RoiError::OutOfBounds));
        assert_eq!(parent.sub(95, 0, 10, 10), Err(RoiError::OutOfBounds));
        assert_eq!(parent.sub(0, 0, 10, -2), Err(RoiError::NegativeSize));
    }

    #[test]
    fn area_is_u64_and_errors_read_human() {
        let r = roi(0, 0, 61_000, 1_000);
        assert_eq!(r.area_u64(), 61_000_000);
        assert_eq!(
            format!("{}", RoiError::BadScale),
            "roi scale must be finite and positive"
        );
        assert_eq!(
            format!("{}", RoiError::Overflow),
            "roi coordinate arithmetic overflowed"
        );
        let err: Box<dyn std::error::Error> = Box::new(RoiError::ScaleMismatch);
        assert!(err.to_string().contains("different scales"));
    }
}
