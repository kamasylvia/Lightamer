// SPDX-License-Identifier: GPL-3.0-or-later
//! Pixel formats: two working formats, two display names.

/// Pixel format of a frame buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PixelFormat {
    /// 32-bit float RGBA, premultiplied alpha: the pipeline's RGBA working format.
    RgbaF32Premul,
    /// 8-bit integer RGBA for display. Named only; no wave allocates it yet.
    RgbaU8,
    /// 16-bit integer RGBA for display. Named only; no wave allocates it yet.
    RgbaU16,
    /// Single-channel 32-bit float: the RAW mosaic working format. Decoded
    /// mosaics (`u16` or `f32`) enter the pipe as this.
    MonoF32,
}

impl PixelFormat {
    /// Bytes per pixel.
    #[must_use]
    pub const fn bytes_per_pixel(self) -> u64 {
        match self {
            PixelFormat::RgbaF32Premul => 16,
            PixelFormat::RgbaU8 | PixelFormat::MonoF32 => 4,
            PixelFormat::RgbaU16 => 8,
        }
    }

    /// Float lanes per pixel. Only meaningful for the float formats, the
    /// only ones [`PixelFormat::is_allocatable`] admits; integer formats
    /// report their channel count anyway so callers never branch on it.
    #[must_use]
    pub const fn channel_count(self) -> u32 {
        match self {
            PixelFormat::RgbaF32Premul | PixelFormat::RgbaU8 | PixelFormat::RgbaU16 => 4,
            PixelFormat::MonoF32 => 1,
        }
    }

    /// Whether frames of this format can be allocated.
    #[must_use]
    pub const fn is_allocatable(self) -> bool {
        matches!(self, PixelFormat::RgbaF32Premul | PixelFormat::MonoF32)
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

    #[test]
    fn mono_format_is_4_bytes_and_allocatable() {
        assert_eq!(PixelFormat::MonoF32.bytes_per_pixel(), 4);
        assert!(PixelFormat::MonoF32.is_allocatable());
    }

    #[test]
    fn channel_counts_cover_all_formats() {
        assert_eq!(PixelFormat::RgbaF32Premul.channel_count(), 4);
        assert_eq!(PixelFormat::RgbaU8.channel_count(), 4);
        assert_eq!(PixelFormat::RgbaU16.channel_count(), 4);
        assert_eq!(PixelFormat::MonoF32.channel_count(), 1);
    }
}
