// SPDX-License-Identifier: GPL-3.0-or-later
//! Decoded-image facts a module's commit may read.

use super::ColorSpace;

/// What `commit` knows about the image: decoded full-frame size plus the
/// camera input colorspace.
///
/// Lives here (not in the geometry crate) because the module trait's
/// signature needs it and L0 crates take no workspace dependencies.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ImageInfo {
    /// Decoded full-frame width in pixels.
    pub width: u32,
    /// Decoded full-frame height in pixels.
    pub height: u32,
    /// Colorspace of the camera input feeding the pipe.
    pub input_space: ColorSpace,
}

impl ImageInfo {
    /// Builds image facts.
    #[must_use]
    pub const fn new(width: u32, height: u32, input_space: ColorSpace) -> Self {
        Self {
            width,
            height,
            input_space,
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{ColorSpace, ImageInfo};

    #[test]
    fn carries_decoded_size_and_input_space() {
        let info = ImageInfo::new(9568, 6376, ColorSpace::Raw);
        assert_eq!((info.width, info.height), (9568, 6376));
        assert_eq!(info.input_space, ColorSpace::Raw);
    }
}
