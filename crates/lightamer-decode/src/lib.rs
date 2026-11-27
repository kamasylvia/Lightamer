// SPDX-License-Identifier: GPL-3.0-or-later
//! `lightamer-decode`: RAW decoding over rawspeed (L1).
//!
//! The crate builds rawspeed from the pinned submodule (`external/rawspeed`)
//! in `build.rs`, talks to it through a thin exception-proof C ABI
//! (`csrc/rawspeed_shim.{h,cpp}`), and exposes a safe wrapper: typed
//! [`error::DecodeError`], the process-once camera database, decoded
//! [`image::RawMetadata`], and owned cropped [`image::Mosaic`] planes.
//!
//! Raster decoding (JPEG/TIFF/PNG) and embedded thumbnails arrived in B2-b
//! (pure Rust; the camera-RAW path stays on rawspeed).
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

pub mod error;
pub mod exif;
// B2-a: this crate owns the rawspeed FFI boundary. `unsafe` is confined to
// `ffi` (declarations) plus one documented block per extern call in `image`;
// every block carries a `SAFETY` comment naming the contract it upholds.
#[allow(unsafe_code)]
pub mod ffi;
#[allow(unsafe_code)]
pub mod image;
pub mod raster;
pub mod thumbnail;

pub use error::{DecodeError, ErrorCode};
pub use exif::{ExifOptics, read_exif};
pub use image::{
    CfaColor, CropBox, DecodedImage, Mosaic, MosaicKind, RawImage, RawMetadata,
    cameras_xml_bundled_path, classify_for_test, decode_file, invert_3x3,
};
pub use raster::{RasterImage, RasterPixels, decode_raster};
pub use thumbnail::{Thumbnail, ThumbnailFormat, jpeg_dimensions, read_thumbnail};

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
