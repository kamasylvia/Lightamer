// SPDX-License-Identifier: GPL-3.0-or-later
//! Pixel views modules process through.

use super::PipeError;

/// Read-only float plane: borrowed pixels plus their shape.
///
/// The pipeline builds these from owned frames; modules never allocate.
/// `stride` is floats per row and may exceed `width * 4` (sub-buffer rows).
#[derive(Debug)]
pub struct Plane<'a> {
    data: &'a [f32],
    width: u32,
    height: u32,
    stride: usize,
}

/// Writable float plane.
#[derive(Debug)]
pub struct PlaneMut<'a> {
    data: &'a mut [f32],
    width: u32,
    height: u32,
    stride: usize,
}

/// Floats per pixel.
const CHANNELS: u64 = 4;

impl<'a> Plane<'a> {
    /// Borrows `data` as a `width` by `height` plane with `stride` floats
    /// per row.
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] when the stride is narrower than a row or
    /// the slice is shorter than the shape needs.
    pub fn from_slice(
        data: &'a [f32],
        width: u32,
        height: u32,
        stride: usize,
    ) -> Result<Self, PipeError> {
        check_shape(data.len(), width, height, stride)?;
        Ok(Self {
            data,
            width,
            height,
            stride,
        })
    }

    /// Plane width in pixels.
    #[must_use]
    pub const fn width(&self) -> u32 {
        self.width
    }

    /// Plane height in pixels.
    #[must_use]
    pub const fn height(&self) -> u32 {
        self.height
    }

    /// Floats per row.
    #[must_use]
    pub const fn stride(&self) -> usize {
        self.stride
    }

    /// Row `y`, exactly `width * 4` floats.
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] when `y` leaves the plane.
    pub fn row(&self, y: u32) -> Result<&[f32], PipeError> {
        if y >= self.height {
            return Err(row_out_of_bounds(y, self.height));
        }
        let start = usize::try_from(u64::from(y) * self.stride as u64)
            .map_err(|_| row_out_of_bounds(y, self.height))?;
        let len = usize::try_from(u64::from(self.width) * CHANNELS)
            .map_err(|_| row_out_of_bounds(y, self.height))?;
        let end = start.saturating_add(len);
        self.data
            .get(start..end)
            .ok_or_else(|| row_out_of_bounds(y, self.height))
    }
}

impl<'a> PlaneMut<'a> {
    /// Borrows `data` mutably; same contract as [`Plane::from_slice`].
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] when the shape does not fit the slice.
    pub fn from_slice(
        data: &'a mut [f32],
        width: u32,
        height: u32,
        stride: usize,
    ) -> Result<Self, PipeError> {
        check_shape(data.len(), width, height, stride)?;
        Ok(Self {
            data,
            width,
            height,
            stride,
        })
    }

    /// Plane width in pixels.
    #[must_use]
    pub const fn width(&self) -> u32 {
        self.width
    }

    /// Plane height in pixels.
    #[must_use]
    pub const fn height(&self) -> u32 {
        self.height
    }

    /// Floats per row.
    #[must_use]
    pub const fn stride(&self) -> usize {
        self.stride
    }

    /// Row `y`, writable, exactly `width * 4` floats.
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] when `y` leaves the plane.
    pub fn row_mut(&mut self, y: u32) -> Result<&mut [f32], PipeError> {
        if y >= self.height {
            return Err(row_out_of_bounds(y, self.height));
        }
        let start = usize::try_from(u64::from(y) * self.stride as u64)
            .map_err(|_| row_out_of_bounds(y, self.height))?;
        let len = usize::try_from(u64::from(self.width) * CHANNELS)
            .map_err(|_| row_out_of_bounds(y, self.height))?;
        let end = start.saturating_add(len);
        self.data
            .get_mut(start..end)
            .ok_or_else(|| row_out_of_bounds(y, self.height))
    }
}

fn check_shape(len: usize, width: u32, height: u32, stride: usize) -> Result<(), PipeError> {
    let row_need = u64::from(width) * CHANNELS;
    if u64::try_from(stride).is_ok_and(|s| s < row_need) {
        return Err(PipeError::RoiMismatch(format!(
            "plane stride {stride} is narrower than a {width}-pixel row"
        )));
    }
    let need = if height == 0 {
        0
    } else {
        u64::from(height - 1) * stride as u64 + row_need
    };
    if u64::try_from(len).is_ok_and(|have| have < need) {
        return Err(PipeError::RoiMismatch(format!(
            "plane needs {need} floats for {width}x{height}, slice holds {len}"
        )));
    }
    Ok(())
}

fn row_out_of_bounds(y: u32, height: u32) -> PipeError {
    PipeError::RoiMismatch(format!("plane row {y} of height {height}"))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{Plane, PlaneMut};

    #[test]
    fn rows_read_and_write_with_strides() {
        let backing = vec![1.0f32; 4 * 3 * 4];
        let plane = Plane::from_slice(&backing, 4, 3, 16).unwrap();
        assert_eq!((plane.width(), plane.height(), plane.stride()), (4, 3, 16));
        assert_eq!(plane.row(2).unwrap().len(), 16);
        assert!(plane.row(3).is_err());
        let mut backing = vec![0.0f32; 4 * 3 * 4];
        {
            let mut plane = PlaneMut::from_slice(&mut backing, 4, 3, 16).unwrap();
            plane.row_mut(1).unwrap().fill(5.0);
            assert!(plane.row_mut(3).is_err());
        }
        assert_eq!(backing[16], 5.0);
        assert_eq!(backing[15], 0.0);
        assert_eq!(backing[32], 0.0);
    }

    #[test]
    fn short_slice_or_narrow_stride_is_rejected() {
        let backing = vec![0.0f32; 10];
        assert!(Plane::from_slice(&backing, 4, 3, 16).is_err());
        let backing = vec![0.0f32; 4 * 3 * 4];
        assert!(Plane::from_slice(&backing, 4, 3, 15).is_err());
        let err = Plane::from_slice(&backing, 4, 3, 15).unwrap_err();
        assert!(err.to_string().starts_with("roi mismatch:"));
    }
}
