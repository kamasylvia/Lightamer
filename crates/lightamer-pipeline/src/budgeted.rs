// SPDX-License-Identifier: GPL-3.0-or-later
//! Budget-paired frames: a frame plus the grant it was charged to.
//!
//! `lightamer_raster` cannot see `lightamer_sysmem` (same layer, no chain),
//! so the pairing lives here: [`alloc_frame`] charges the budget first, then
//! allocates. A failed allocation drops its grant, returning the bytes.
//! [`SharedFrame`] is the same pairing with an owned ([`Arc`]) grant: cache
//! entries and returned frames share planes past the call that made them, and
//! the last holder's drop returns the bytes.

use std::fmt;
use std::sync::Arc;

use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use lightamer_sysmem::{Budget, BudgetError, Grant, SharedGrant};
/// A frame plus its budget grant; dropping both frees pixels and bytes.
#[derive(Debug)]
pub struct BudgetedFrame<'a> {
    /// The pixels.
    pub frame: Frame,
    grant: Grant<'a>,
}

/// Why a budgeted allocation failed.
#[derive(Debug)]
pub enum BudgetedError {
    /// The budget refused.
    Budget(BudgetError),
    /// The frame refused.
    Raster(lightamer_raster::RasterError),
}

impl fmt::Display for BudgetedError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BudgetedError::Budget(source) => write!(f, "budgeted frame: {source}"),
            BudgetedError::Raster(source) => write!(f, "budgeted frame: {source}"),
        }
    }
}

impl std::error::Error for BudgetedError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            BudgetedError::Budget(source) => Some(source),
            BudgetedError::Raster(source) => Some(source),
        }
    }
}

impl BudgetedFrame<'_> {
    /// Bytes this frame holds against the budget.
    #[must_use]
    pub fn bytes(&self) -> u64 {
        self.grant.bytes()
    }
}

/// Allocates a frame against a budget.
///
/// # Errors
///
/// [`BudgetedError::Budget`] when the charge exceeds the cap;
/// [`BudgetedError::Raster`] when the frame itself is unbuildable (the
/// grant is already dropped, so the bytes are back).
pub fn alloc_frame(
    budget: &Budget,
    extent: FrameExtent,
    format: PixelFormat,
) -> Result<BudgetedFrame<'_>, BudgetedError> {
    let bytes = extent
        .area_u64()
        .checked_mul(format.bytes_per_pixel())
        .ok_or(BudgetedError::Raster(
            lightamer_raster::RasterError::TooLarge { elems: u64::MAX },
        ))?;
    let grant = budget.acquire(bytes).map_err(BudgetedError::Budget)?;
    let frame = Frame::alloc(extent, format).map_err(BudgetedError::Raster)?;
    debug_assert_eq!(grant.bytes(), bytes);
    Ok(BudgetedFrame { frame, grant })
}

/// A frame plus an owned budget grant: clone the [`Arc`] to share the plane,
/// drop the last holder to return the bytes. Cache entries and render outputs
/// are these behind one [`Arc`] each.
#[derive(Debug)]
pub struct SharedFrame {
    /// The pixels.
    pub frame: Frame,
    grant: SharedGrant,
}

impl SharedFrame {
    /// Bytes this frame holds against the budget.
    #[must_use]
    pub fn bytes(&self) -> u64 {
        self.grant.bytes()
    }
}

/// Allocates a frame against a shared budget.
///
/// Same contract as [`alloc_frame`]: the charge lands first, and a refused
/// frame drops its grant before the error reaches the caller.
///
/// # Errors
///
/// [`BudgetedError::Budget`] when the charge exceeds the cap;
/// [`BudgetedError::Raster`] when the frame itself is unbuildable (the
/// grant is already dropped, so the bytes are back).
pub fn alloc_shared(
    budget: &Arc<Budget>,
    extent: FrameExtent,
    format: PixelFormat,
) -> Result<SharedFrame, BudgetedError> {
    let bytes = extent
        .area_u64()
        .checked_mul(format.bytes_per_pixel())
        .ok_or(BudgetedError::Raster(
            lightamer_raster::RasterError::TooLarge { elems: u64::MAX },
        ))?;
    let grant = budget
        .acquire_shared(bytes)
        .map_err(BudgetedError::Budget)?;
    let frame = Frame::alloc(extent, format).map_err(BudgetedError::Raster)?;
    debug_assert_eq!(grant.bytes(), bytes);
    Ok(SharedFrame { frame, grant })
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use lightamer_raster::{FrameExtent, PixelFormat};
    use lightamer_sysmem::Budget;

    use super::{BudgetedError, alloc_frame, alloc_shared};

    #[test]
    fn alloc_charges_and_drop_returns() {
        let budget = Budget::new(1_000_000);
        let extent = FrameExtent::new(0, 0, 10, 10);
        {
            let mut paired = alloc_frame(&budget, extent, PixelFormat::RgbaF32Premul).unwrap();
            assert_eq!(paired.bytes(), 10 * 10 * 16);
            assert_eq!(budget.used(), 1_600);
            paired.frame.as_mut_slice().fill(1.0);
        }
        assert_eq!(budget.used(), 0);
    }

    #[test]
    fn over_budget_is_an_error_and_charges_nothing() {
        let budget = Budget::new(100);
        let err = alloc_frame(
            &budget,
            FrameExtent::new(0, 0, 10, 10),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap_err();
        assert!(matches!(err, BudgetedError::Budget(_)));
        assert!(err.to_string().contains("memory budget exceeded"));
        assert_eq!(budget.used(), 0);
    }

    #[test]
    fn failed_frame_build_returns_its_grant() {
        let budget = Budget::new(u64::MAX);
        // Display formats are named only: the frame build fails after the
        // grant was taken, and the drop returns the bytes.
        let err =
            alloc_frame(&budget, FrameExtent::new(0, 0, 10, 10), PixelFormat::RgbaU8).unwrap_err();
        assert!(matches!(err, BudgetedError::Raster(_)));
        assert_eq!(budget.used(), 0);
    }

    #[test]
    fn shared_frame_returns_bytes_when_last_holder_drops() {
        use std::sync::Arc;
        let budget = Arc::new(Budget::new(1_000_000));
        let extent = FrameExtent::new(0, 0, 10, 10);
        let shared = Arc::new(alloc_shared(&budget, extent, PixelFormat::RgbaF32Premul).unwrap());
        assert_eq!(budget.used(), 1_600);
        // A second holder keeps the bytes charged past the first drop.
        let twin = Arc::clone(&shared);
        drop(shared);
        assert_eq!(budget.used(), 1_600);
        drop(twin);
        assert_eq!(budget.used(), 0);
    }
}
