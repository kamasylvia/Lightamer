// SPDX-License-Identifier: GPL-3.0-or-later
//! Pixel views modules process through.

use super::PipeError;

/// Read-only float plane: borrowed pixels plus their shape.
///
/// The pipeline builds these from owned frames; modules never allocate.
/// `stride` is floats per row and may exceed `width × channels` (sub-buffer rows).
#[derive(Debug)]
pub struct Plane<'a> {
    data: &'a [f32],
    width: u32,
    height: u32,
    stride: usize,
    channels: u32,
}

/// Writable float plane.
#[derive(Debug)]
pub struct PlaneMut<'a> {
    data: &'a mut [f32],
    width: u32,
    height: u32,
    stride: usize,
    channels: u32,
}

impl<'a> Plane<'a> {
    /// Borrows `data` as an RGBA plane: `width` by `height` with `stride`
    /// floats per row.
    ///
    /// This entry is RGBA-only. A single-channel buffer fails here — its
    /// stride is narrower than an RGBA row — so RGBA readers never silently
    /// misread mono data; mono planes go through
    /// [`Plane::from_slice_channels`].
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
        Self::from_slice_channels(data, width, height, stride, 4)
    }

    /// Borrows `data` as a plane with `channels` lanes per pixel (1 for
    /// mono, 4 for RGBA).
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] when `channels` is neither 1 nor 4, the
    /// stride is narrower than a row, or the slice is shorter than the shape
    /// needs.
    pub fn from_slice_channels(
        data: &'a [f32],
        width: u32,
        height: u32,
        stride: usize,
        channels: u32,
    ) -> Result<Self, PipeError> {
        check_channels(channels)?;
        check_shape(data.len(), width, height, stride, channels)?;
        Ok(Self {
            data,
            width,
            height,
            stride,
            channels,
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

    /// Lanes per pixel (1 for mono, 4 for RGBA).
    #[must_use]
    pub const fn channels(&self) -> u32 {
        self.channels
    }

    /// Whole borrowed buffer (all rows, gaps included).
    #[must_use]
    pub const fn as_slice(&self) -> &[f32] {
        self.data
    }

    /// Row `y`, exactly `width × channels` floats.
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
        let len = usize::try_from(u64::from(self.width) * u64::from(self.channels))
            .map_err(|_| row_out_of_bounds(y, self.height))?;
        let end = start.saturating_add(len);
        self.data
            .get(start..end)
            .ok_or_else(|| row_out_of_bounds(y, self.height))
    }
}

impl<'a> PlaneMut<'a> {
    /// Borrows `data` mutably as an RGBA plane; same contract as
    /// [`Plane::from_slice`], mono buffers included (they fail typed).
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
        Self::from_slice_channels(data, width, height, stride, 4)
    }

    /// Borrows `data` mutably with `channels` lanes per pixel; same
    /// contract as [`Plane::from_slice_channels`].
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] when `channels` is neither 1 nor 4 or
    /// the shape does not fit the slice.
    pub fn from_slice_channels(
        data: &'a mut [f32],
        width: u32,
        height: u32,
        stride: usize,
        channels: u32,
    ) -> Result<Self, PipeError> {
        check_channels(channels)?;
        check_shape(data.len(), width, height, stride, channels)?;
        Ok(Self {
            data,
            width,
            height,
            stride,
            channels,
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

    /// Lanes per pixel (1 for mono, 4 for RGBA).
    #[must_use]
    pub const fn channels(&self) -> u32 {
        self.channels
    }

    /// Whole borrowed buffer, writable (all rows, gaps included).
    pub fn as_mut_slice(&mut self) -> &mut [f32] {
        self.data
    }

    /// Row `y`, writable, exactly `width × channels` floats.
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
        let len = usize::try_from(u64::from(self.width) * u64::from(self.channels))
            .map_err(|_| row_out_of_bounds(y, self.height))?;
        let end = start.saturating_add(len);
        self.data
            .get_mut(start..end)
            .ok_or_else(|| row_out_of_bounds(y, self.height))
    }
}

fn check_channels(channels: u32) -> Result<(), PipeError> {
    if channels == 1 || channels == 4 {
        Ok(())
    } else {
        Err(PipeError::RoiMismatch(format!(
            "plane needs 1 or 4 channels, got {channels}"
        )))
    }
}

fn check_shape(
    len: usize,
    width: u32,
    height: u32,
    stride: usize,
    channels: u32,
) -> Result<(), PipeError> {
    let row_need = u64::from(width) * u64::from(channels);
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
    #[test]
    fn mono_planes_read_and_write_single_rows() {
        let backing = vec![1.0f32; 4 * 3];
        let plane = Plane::from_slice_channels(&backing, 4, 3, 4, 1).unwrap();
        assert_eq!(plane.channels(), 1);
        assert_eq!(plane.row(2).unwrap().len(), 4);
        assert!(plane.row(3).is_err());
        let mut backing = vec![0.0f32; 4 * 3];
        {
            let mut plane = PlaneMut::from_slice_channels(&mut backing, 4, 3, 4, 1).unwrap();
            assert_eq!(plane.channels(), 1);
            plane.row_mut(1).unwrap().fill(5.0);
        }
        assert_eq!(backing[4], 5.0);
        assert_eq!(backing[3], 0.0);
        assert_eq!(backing[8], 0.0);
    }

    #[test]
    fn rgba_entry_refuses_mono_buffers_typed() {
        let backing = vec![1.0f32; 4 * 3];
        let err = Plane::from_slice(&backing, 4, 3, 4).unwrap_err();
        assert!(err.to_string().starts_with("roi mismatch:"));
        let mut backing = vec![0.0f32; 4 * 3];
        assert!(PlaneMut::from_slice(&mut backing, 4, 3, 4).is_err());
    }

    #[test]
    fn other_channel_counts_are_rejected() {
        let backing = vec![0.0f32; 4 * 3 * 4];
        assert!(Plane::from_slice_channels(&backing, 4, 3, 16, 3).is_err());
        let mut backing = vec![0.0f32; 4 * 3 * 4];
        assert!(PlaneMut::from_slice_channels(&mut backing, 4, 3, 16, 0).is_err());
    }
}
