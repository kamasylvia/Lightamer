// SPDX-License-Identifier: GPL-3.0-or-later
//! Wire pixel format: the format vocabulary of module contracts.
//!
//! Same names and variants as `lightamer_raster::PixelFormat` (like
//! [`super::Roi`] mirrors `lightamer_geom::Roi`): L0 crates take no workspace
//! dependencies, so [`IopModule::output_format`](super::IopModule::output_format)
//! speaks this type and the pipeline converts at the boundary.

/// Pixel format on module contracts: a wire mirror of the raster format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PixelFormat {
    /// 32-bit float RGBA, premultiplied alpha.
    RgbaF32Premul,
    /// 8-bit integer RGBA for display.
    RgbaU8,
    /// 16-bit integer RGBA for display.
    RgbaU16,
    /// Single-channel 32-bit float (RAW mosaic).
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

    /// Float lanes per pixel (1 for mono, 4 otherwise).
    #[must_use]
    pub const fn channel_count(self) -> u32 {
        match self {
            PixelFormat::MonoF32 => 1,
            PixelFormat::RgbaF32Premul | PixelFormat::RgbaU8 | PixelFormat::RgbaU16 => 4,
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::PixelFormat;

    #[test]
    fn sizes_match_the_raster_format() {
        assert_eq!(PixelFormat::RgbaF32Premul.bytes_per_pixel(), 16);
        assert_eq!(PixelFormat::RgbaU8.bytes_per_pixel(), 4);
        assert_eq!(PixelFormat::RgbaU16.bytes_per_pixel(), 8);
        assert_eq!(PixelFormat::MonoF32.bytes_per_pixel(), 4);
        assert_eq!(PixelFormat::RgbaF32Premul.channel_count(), 4);
        assert_eq!(PixelFormat::MonoF32.channel_count(), 1);
    }
}
