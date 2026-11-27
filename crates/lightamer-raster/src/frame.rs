// SPDX-License-Identifier: GPL-3.0-or-later
//! Frames: owned float buffers plus their extent and format.

use std::fmt;

use super::PixelFormat;

/// Integer rect locating a frame in pipeline coordinates.
///
/// Unlike `lightamer_geom::Roi` this carries no scale: a buffer's location
/// never needs one. Same-layer rules keep the two types separate; the
/// pipeline converts field by field.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FrameExtent {
    /// Left edge.
    pub x: i32,
    /// Top edge.
    pub y: i32,
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
}

impl FrameExtent {
    /// Builds an extent; zero width or height is a valid empty extent.
    #[must_use]
    pub const fn new(x: i32, y: i32, width: u32, height: u32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// Whether this extent covers no pixels.
    #[must_use]
    pub const fn is_empty(self) -> bool {
        self.width == 0 || self.height == 0
    }

    /// Pixel count as `u64`; cannot overflow.
    #[must_use]
    pub const fn area_u64(self) -> u64 {
        self.width as u64 * self.height as u64
    }

    /// Whether `other` lies fully inside `self`, edges included.
    #[must_use]
    pub fn contains(self, other: Self) -> bool {
        // i64: corner sums can exceed i32 at extreme coordinates.
        let self_right = i64::from(self.x) + i64::from(self.width);
        let self_bottom = i64::from(self.y) + i64::from(self.height);
        let other_right = i64::from(other.x) + i64::from(other.width);
        let other_bottom = i64::from(other.y) + i64::from(other.height);
        other.x >= self.x
            && other.y >= self.y
            && other_right <= self_right
            && other_bottom <= self_bottom
    }
}

/// Why a frame operation failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RasterError {
    /// The frame would exceed addressable memory.
    TooLarge {
        /// Requested element count.
        elems: u64,
    },
    /// Buffer length does not match the extent.
    ShapeMismatch {
        /// Human-readable detail.
        detail: String,
    },
    /// A row, range, or view left the frame.
    OutOfBounds {
        /// Human-readable detail.
        detail: String,
    },
    /// Only [`PixelFormat::RgbaF32Premul`] is allocatable in B1.
    UnsupportedFormat {
        /// Human-readable detail.
        detail: String,
    },
}

impl fmt::Display for RasterError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RasterError::TooLarge { elems } => {
                write!(f, "frame of {elems} floats exceeds addressable memory")
            }
            RasterError::ShapeMismatch { detail } => write!(f, "frame shape mismatch: {detail}"),
            RasterError::OutOfBounds { detail } => {
                write!(f, "frame access out of bounds: {detail}")
            }
            RasterError::UnsupportedFormat { detail } => {
                write!(f, "unsupported pixel format: {detail}")
            }
        }
    }
}

impl std::error::Error for RasterError {}

/// Largest element count a `Vec<f32>` may hold without a capacity panic.
const MAX_ELEMS: u64 = isize::MAX as u64;

/// Floats per pixel in the working format.
const WORKING_CHANNELS: u64 = 4;

/// An owned working-format frame: buffer plus extent plus format.
#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    buf: Vec<f32>,
    extent: FrameExtent,
    format: PixelFormat,
    /// Floats per row (`width * 4`); fixed at allocation so accessors divide
    /// without re-checking.
    stride: usize,
}

impl Frame {
    /// Allocates a zeroed frame.
    ///
    /// # Errors
    ///
    /// [`RasterError::UnsupportedFormat`] for anything but
    /// [`PixelFormat::RgbaF32Premul`]; [`RasterError::TooLarge`] when
    /// `width * height * 4` overflows `u64` or exceeds addressable memory.
    pub fn alloc(extent: FrameExtent, format: PixelFormat) -> Result<Self, RasterError> {
        if !format.is_allocatable() {
            return Err(RasterError::UnsupportedFormat {
                detail: format!("{format:?} is named only; B1 allocates RgbaF32Premul"),
            });
        }
        let elems = extent
            .area_u64()
            .checked_mul(WORKING_CHANNELS)
            .filter(|elems| *elems <= MAX_ELEMS)
            .ok_or(RasterError::TooLarge { elems: u64::MAX })?;
        let stride = usize::try_from(u64::from(extent.width) * WORKING_CHANNELS)
            .map_err(|_| RasterError::TooLarge { elems })?;
        let len = usize::try_from(elems).map_err(|_| RasterError::TooLarge { elems })?;
        Ok(Self {
            buf: vec![0.0; len],
            extent,
            format,
            stride,
        })
    }

    /// Wraps an existing buffer, checking its length against the extent.
    ///
    /// # Errors
    ///
    /// [`RasterError::UnsupportedFormat`] for non-working formats;
    /// [`RasterError::ShapeMismatch`] when the length is wrong.
    pub fn from_parts(
        buf: Vec<f32>,
        extent: FrameExtent,
        format: PixelFormat,
    ) -> Result<Self, RasterError> {
        if !format.is_allocatable() {
            return Err(RasterError::UnsupportedFormat {
                detail: format!("{format:?} is named only; B1 allocates RgbaF32Premul"),
            });
        }
        let want = extent.area_u64().saturating_mul(WORKING_CHANNELS);
        if u64::try_from(buf.len()).is_ok_and(|len| len == want) {
            let stride =
                usize::try_from(u64::from(extent.width) * WORKING_CHANNELS).map_err(|_| {
                    RasterError::ShapeMismatch {
                        detail: format!("width {} overflows row stride", extent.width),
                    }
                })?;
            Ok(Self {
                buf,
                extent,
                format,
                stride,
            })
        } else {
            Err(RasterError::ShapeMismatch {
                detail: format!("buffer holds {} floats, {extent:?} needs {want}", buf.len()),
            })
        }
    }

    /// This frame's extent.
    #[must_use]
    pub const fn extent(&self) -> FrameExtent {
        self.extent
    }

    /// This frame's format.
    #[must_use]
    pub const fn format(&self) -> PixelFormat {
        self.format
    }

    /// Floats per row.
    #[must_use]
    pub const fn row_stride(&self) -> usize {
        self.stride
    }

    /// Whole buffer, read-only.
    #[must_use]
    pub fn as_slice(&self) -> &[f32] {
        &self.buf
    }

    /// Whole buffer, writable.
    pub fn as_mut_slice(&mut self) -> &mut [f32] {
        &mut self.buf
    }

    /// Row `y`, read-only.
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when `y` leaves the frame.
    pub fn row(&self, y: u32) -> Result<&[f32], RasterError> {
        self.rows(y, y.saturating_add(1))
    }

    /// Row `y`, writable.
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when `y` leaves the frame.
    pub fn row_mut(&mut self, y: u32) -> Result<&mut [f32], RasterError> {
        self.rows_mut(y, y.saturating_add(1))
    }

    /// Contiguous rows `[y0, y1)` for parallel disjoint writes: split the
    /// returned slice with `split_at_mut` and each writer owns its part with
    /// no aliasing.
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when the range leaves the frame or is
    /// inverted.
    pub fn rows(&self, y0: u32, y1: u32) -> Result<&[f32], RasterError> {
        let (start, end) = self.row_byte_range(y0, y1)?;
        self.buf
            .get(start..end)
            .ok_or_else(|| out_of_bounds(y0, y1, self.extent.height))
    }

    /// Writable version of [`Frame::rows`].
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when the range leaves the frame or is
    /// inverted.
    pub fn rows_mut(&mut self, y0: u32, y1: u32) -> Result<&mut [f32], RasterError> {
        let (start, end) = self.row_byte_range(y0, y1)?;
        let height = self.extent.height;
        self.buf
            .get_mut(start..end)
            .ok_or_else(|| out_of_bounds(y0, y1, height))
    }

    /// Element range of rows `[y0, y1)`; `None`-free: the `get` still guards.
    fn row_byte_range(&self, y0: u32, y1: u32) -> Result<(usize, usize), RasterError> {
        if y0 > y1 || y1 > self.extent.height {
            return Err(out_of_bounds(y0, y1, self.extent.height));
        }
        let start = usize::try_from(u64::from(y0) * self.stride as u64)
            .map_err(|_| out_of_bounds(y0, y1, self.extent.height))?;
        let end = usize::try_from(u64::from(y1) * self.stride as u64)
            .map_err(|_| out_of_bounds(y0, y1, self.extent.height))?;
        Ok((start, end))
    }

    /// Read-only view of `rect` in frame coordinates.
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when `rect` is not fully inside.
    pub fn view(&self, rect: FrameExtent) -> Result<FrameView<'_>, RasterError> {
        if !self.extent.contains(rect) {
            return Err(RasterError::OutOfBounds {
                detail: format!("view {rect:?} leaves frame {:?}", self.extent),
            });
        }
        // i64: the difference of two i32s can exceed i32; containment above
        // guarantees it is non-negative, so the `u64` conversion holds.
        let ox = u64::try_from(i64::from(rect.x) - i64::from(self.extent.x)).map_err(|_| {
            RasterError::OutOfBounds {
                detail: format!("view {rect:?} offset overflows"),
            }
        })?;
        let oy = u64::try_from(i64::from(rect.y) - i64::from(self.extent.y)).map_err(|_| {
            RasterError::OutOfBounds {
                detail: format!("view {rect:?} offset overflows"),
            }
        })?;
        Ok(FrameView {
            data: &self.buf,
            rect,
            base: oy * self.stride as u64 + ox * WORKING_CHANNELS,
            stride: self.stride,
        })
    }

    /// Writable version of [`Frame::view`].
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when `rect` is not fully inside.
    pub fn view_mut(&mut self, rect: FrameExtent) -> Result<FrameViewMut<'_>, RasterError> {
        if !self.extent.contains(rect) {
            return Err(RasterError::OutOfBounds {
                detail: format!("view {rect:?} leaves frame {:?}", self.extent),
            });
        }
        let ox = u64::try_from(i64::from(rect.x) - i64::from(self.extent.x)).map_err(|_| {
            RasterError::OutOfBounds {
                detail: format!("view {rect:?} offset overflows"),
            }
        })?;
        let oy = u64::try_from(i64::from(rect.y) - i64::from(self.extent.y)).map_err(|_| {
            RasterError::OutOfBounds {
                detail: format!("view {rect:?} offset overflows"),
            }
        })?;
        Ok(FrameViewMut {
            data: &mut self.buf,
            rect,
            base: oy * self.stride as u64 + ox * WORKING_CHANNELS,
            stride: self.stride,
        })
    }
    /// Copies `src` over `self` wholesale.
    ///
    /// # Errors
    ///
    /// [`RasterError::ShapeMismatch`] when dimensions or formats differ.
    pub fn copy_from(&mut self, src: &Frame) -> Result<(), RasterError> {
        if self.format != src.format
            || self.extent.width != src.extent.width
            || self.extent.height != src.extent.height
        {
            return Err(RasterError::ShapeMismatch {
                detail: format!(
                    "copy {:?} {:?} into {:?} {:?}",
                    src.extent, src.format, self.extent, self.format
                ),
            });
        }
        if self.buf.len() != src.buf.len() {
            return Err(RasterError::ShapeMismatch {
                detail: format!("buffer lengths {} vs {}", self.buf.len(), src.buf.len()),
            });
        }
        self.buf.copy_from_slice(&src.buf);
        Ok(())
    }
}

fn out_of_bounds(y0: u32, y1: u32, height: u32) -> RasterError {
    RasterError::OutOfBounds {
        detail: format!("rows [{y0}, {y1}) of height {height}"),
    }
}

/// Read-only sub-region view; rows are borrowed per row, never as one slice.
#[derive(Debug)]
pub struct FrameView<'a> {
    data: &'a [f32],
    rect: FrameExtent,
    base: u64,
    stride: usize,
}

impl FrameView<'_> {
    /// The viewed rect in frame coordinates.
    #[must_use]
    pub const fn rect(&self) -> FrameExtent {
        self.rect
    }

    /// Row `y` relative to the view, read-only.
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when `y` leaves the view.
    pub fn row(&self, y: u32) -> Result<&[f32], RasterError> {
        if y >= self.rect.height {
            return Err(RasterError::OutOfBounds {
                detail: format!("view row {y} of height {}", self.rect.height),
            });
        }
        let start = self.base + u64::from(y) * self.stride as u64;
        let len = u64::from(self.rect.width) * WORKING_CHANNELS;
        let (start, len) = (
            usize::try_from(start).map_err(|_| RasterError::OutOfBounds {
                detail: format!("view row {y} address overflows"),
            })?,
            usize::try_from(len).map_err(|_| RasterError::OutOfBounds {
                detail: format!("view row {y} length overflows"),
            })?,
        );
        let end = start.saturating_add(len);
        self.data.get(start..end).ok_or(RasterError::OutOfBounds {
            detail: format!("view row {y} leaves its buffer"),
        })
    }
}

/// Writable sub-region view.
#[derive(Debug)]
pub struct FrameViewMut<'a> {
    data: &'a mut [f32],
    rect: FrameExtent,
    base: u64,
    stride: usize,
}

impl FrameViewMut<'_> {
    /// The viewed rect in frame coordinates.
    #[must_use]
    pub const fn rect(&self) -> FrameExtent {
        self.rect
    }

    /// Row `y` relative to the view, writable.
    ///
    /// # Errors
    ///
    /// [`RasterError::OutOfBounds`] when `y` leaves the view.
    pub fn row_mut(&mut self, y: u32) -> Result<&mut [f32], RasterError> {
        if y >= self.rect.height {
            return Err(RasterError::OutOfBounds {
                detail: format!("view row {y} of height {}", self.rect.height),
            });
        }
        let start = self.base + u64::from(y) * self.stride as u64;
        let len = u64::from(self.rect.width) * WORKING_CHANNELS;
        let (start, len) = (
            usize::try_from(start).map_err(|_| RasterError::OutOfBounds {
                detail: format!("view row {y} address overflows"),
            })?,
            usize::try_from(len).map_err(|_| RasterError::OutOfBounds {
                detail: format!("view row {y} length overflows"),
            })?,
        );
        let end = start.saturating_add(len);
        self.data
            .get_mut(start..end)
            .ok_or(RasterError::OutOfBounds {
                detail: format!("view row {y} leaves its buffer"),
            })
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{Frame, FrameExtent, PixelFormat, RasterError};

    fn extent(w: u32, h: u32) -> FrameExtent {
        FrameExtent::new(0, 0, w, h)
    }

    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }

    #[test]
    fn alloc_zeroes_and_reports_shape() {
        let frame = Frame::alloc(extent(3, 2), PixelFormat::RgbaF32Premul).unwrap();
        assert_eq!(frame.extent(), extent(3, 2));
        assert_eq!(frame.row_stride(), 12);
        assert!(frame.as_slice().iter().all(|v| *v == 0.0));
        assert_eq!(frame.as_slice().len(), 3 * 2 * 4);
    }

    #[test]
    fn alloc_rejects_display_formats_and_absurd_sizes() {
        let err = Frame::alloc(extent(2, 2), PixelFormat::RgbaU8).unwrap_err();
        assert!(matches!(err, RasterError::UnsupportedFormat { .. }));
        let err = Frame::alloc(
            FrameExtent::new(0, 0, u32::MAX, u32::MAX),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap_err();
        assert!(matches!(err, RasterError::TooLarge { .. }));
        assert!(err.to_string().contains("exceeds addressable memory"));
    }

    #[test]
    fn row_ranges_split_for_disjoint_parallel_writes() {
        let mut frame = Frame::alloc(extent(4, 8), PixelFormat::RgbaF32Premul).unwrap();
        // Two writers split rows 0..8 at 3; each fills its own rows only.
        let stride = frame.row_stride();
        let halves = frame.rows_mut(0, 8).unwrap();
        let (top, bottom) = halves.split_at_mut(3 * stride);
        top.fill(1.0);
        bottom.fill(2.0);
        assert!(
            frame
                .row(0)
                .unwrap()
                .iter()
                .all(|v| v.to_bits() == 1.0f32.to_bits())
        );
        assert!(
            frame
                .row(2)
                .unwrap()
                .iter()
                .all(|v| v.to_bits() == 1.0f32.to_bits())
        );
        assert!(
            frame
                .row(3)
                .unwrap()
                .iter()
                .all(|v| v.to_bits() == 2.0f32.to_bits())
        );
        assert!(
            frame
                .row(7)
                .unwrap()
                .iter()
                .all(|v| v.to_bits() == 2.0f32.to_bits())
        );
        // Inverted and overhanging ranges are errors.
        assert!(frame.rows(5, 3).is_err());
        assert!(frame.rows(0, 9).is_err());
        assert!(frame.row(8).is_err());
    }

    #[test]
    fn sub_views_read_and_write_their_own_rect() {
        let mut frame =
            Frame::alloc(FrameExtent::new(10, 20, 6, 6), PixelFormat::RgbaF32Premul).unwrap();
        let rect = FrameExtent::new(12, 22, 2, 2);
        {
            let mut view = frame.view_mut(rect).unwrap();
            assert_eq!(view.rect(), rect);
            for y in 0..2 {
                view.row_mut(y).unwrap().fill(7.0);
            }
        }
        let view = frame.view(rect).unwrap();
        assert!(
            view.row(0)
                .unwrap()
                .iter()
                .all(|v| v.to_bits() == 7.0f32.to_bits())
        );
        assert!(
            view.row(1)
                .unwrap()
                .iter()
                .all(|v| v.to_bits() == 7.0f32.to_bits())
        );
        assert!(view.row(2).is_err());
        // Outside the rect the frame is still zero.
        assert_eq!(frame.row(0).unwrap()[0], 0.0);
        assert_eq!(frame.row(5).unwrap()[23], 0.0);
        // Overhanging views are errors.
        assert!(frame.view(FrameExtent::new(15, 20, 2, 2)).is_err());
        assert!(frame.view(FrameExtent::new(9, 20, 2, 2)).is_err());
    }

    #[test]
    fn whole_copy_needs_matching_shape() {
        let mut dst = Frame::alloc(extent(2, 2), PixelFormat::RgbaF32Premul).unwrap();
        let mut src = Frame::alloc(extent(2, 2), PixelFormat::RgbaF32Premul).unwrap();
        src.as_mut_slice().fill(3.0);
        dst.copy_from(&src).unwrap();
        assert!(
            dst.as_slice()
                .iter()
                .all(|v| v.to_bits() == 3.0f32.to_bits())
        );
        let other = Frame::alloc(extent(2, 3), PixelFormat::RgbaF32Premul).unwrap();
        assert!(dst.copy_from(&other).is_err());
    }

    #[test]
    fn from_parts_checks_length() {
        let good = vec![1.0f32; 2 * 2 * 4];
        let frame = Frame::from_parts(good, extent(2, 2), PixelFormat::RgbaF32Premul).unwrap();
        assert_eq!(frame.row_stride(), 8);
        let bad = vec![1.0f32; 15];
        assert!(Frame::from_parts(bad, extent(2, 2), PixelFormat::RgbaF32Premul).is_err());
    }

    #[test]
    fn errors_read_human() {
        let err = RasterError::OutOfBounds {
            detail: "rows [0, 9) of height 8".to_owned(),
        };
        assert_eq!(
            format!("{err}"),
            "frame access out of bounds: rows [0, 9) of height 8"
        );
        let boxed: Box<dyn std::error::Error> = Box::new(RasterError::TooLarge { elems: 1 });
        assert!(boxed.to_string().contains("addressable memory"));
    }
}
