// SPDX-License-Identifier: GPL-3.0-or-later
//! Pixel formats: one working format, two display names.

/// Pixel format of a frame buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PixelFormat {
    /// 32-bit float RGBA, premultiplied alpha: the pipeline working format.
    RgbaF32Premul,
    /// 8-bit integer RGBA for display. Named only; B1 cannot allocate it.
    RgbaU8,
    /// 16-bit integer RGBA for display. Named only; B1 cannot allocate it.
    RgbaU16,
}

impl PixelFormat {
    /// Bytes per pixel.
    #[must_use]
    pub const fn bytes_per_pixel(self) -> u64 {
        match self {
            PixelFormat::RgbaF32Premul => 16,
            PixelFormat::RgbaU8 => 4,
            PixelFormat::RgbaU16 => 8,
        }
    }

    /// Whether frames of this format can be allocated in B1.
    #[must_use]
    pub const fn is_allocatable(self) -> bool {
        matches!(self, PixelFormat::RgbaF32Premul)
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::PixelFormat;

    #[test]
    fn working_format_is_16_bytes_and_others_are_names_only() {
        assert_eq!(PixelFormat::RgbaF32Premul.bytes_per_pixel(), 16);
        assert!(PixelFormat::RgbaF32Premul.is_allocatable());
        assert_eq!(PixelFormat::RgbaU8.bytes_per_pixel(), 4);
        assert_eq!(PixelFormat::RgbaU16.bytes_per_pixel(), 8);
        assert!(!PixelFormat::RgbaU8.is_allocatable());
        assert!(!PixelFormat::RgbaU16.is_allocatable());
    }
}
