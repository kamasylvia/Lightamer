// SPDX-License-Identifier: GPL-3.0-or-later
//! Raster decoding (B2-b): JPEG via `zune-jpeg`, PNG via `png`, TIFF via
//! `tiff` — all pure Rust, all already locked. Every raster lands in one
//! [`RasterImage`] (width, height, components, bit depth, pixels, ICC).
//!
//! Container routing is by magic bytes, never by extension. Camera RAWs
//! never decode here: TIFFs carrying DNG/CFA markers or old-JPEG
//! compression are rejected with [`ErrorCode::UnsupportedFormat`] before
//! any pixel read (they belong to the rawspeed path). Only the first TIFF
//! IFD is read.

use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::error::{DecodeError, ErrorCode};

/// Decoded raster pixels: 8-bit bytes or native 16-bit samples.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RasterPixels {
    /// 8-bit samples, row-major chunky.
    U8(Vec<u8>),
    /// 16-bit samples, row-major chunky.
    U16(Vec<u16>),
}

/// One decoded raster image (JPEG/PNG/TIFF).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RasterImage {
    /// Pixel width.
    pub width: u32,
    /// Pixel height.
    pub height: u32,
    /// Components per pixel (1 gray, 2 gray+alpha, 3 RGB, 4 RGBA).
    pub components: u32,
    /// Bits per component (8 or 16).
    pub bit_depth: u8,
    /// Row-major chunky pixels.
    pub pixels: RasterPixels,
    /// Embedded ICC profile bytes, when the file carries one.
    pub icc_profile: Option<Vec<u8>>,
}

impl RasterImage {
    /// Total sample count (`width * height * components`), saturating.
    #[must_use]
    pub fn sample_count(&self) -> u64 {
        u64::from(self.width)
            .saturating_mul(u64::from(self.height))
            .saturating_mul(u64::from(self.components))
    }
}

/// Container magic.
const MAGIC_JPEG: [u8; 2] = [0xFF, 0xD8];
const MAGIC_PNG: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const MAGIC_TIFF_LE: [u8; 4] = [0x49, 0x49, 0x2A, 0x00];
const MAGIC_TIFF_BE: [u8; 4] = [0x4D, 0x4D, 0x00, 0x2A];

/// TIFF tags that mark a camera-RAW file (DNG-private tags a plain raster
/// never carries): `DNGVersion`, `CFAPlaneColor`, `ColorMatrix1`.
const DNG_MARKER_TAGS: [u16; 3] = [50706, 50708, 50721];
/// TIFF old-JPEG compression (camera-preview style; the `tiff` crate cannot
/// decode it either).
const TIFF_COMPRESSION_OLD_JPEG: u16 = 6;
/// TIFF CFA photometric interpretation.
const TIFF_PHOTOMETRIC_CFA: u16 = 32803;

/// Which raster container the magic selects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Container {
    Jpeg,
    Png,
    Tiff,
}

/// Sniff the container from the first 8 bytes.
///
/// Returns [`ErrorCode::Truncated`] for short files,
/// [`ErrorCode::UnsupportedFormat`] for anything else.
fn sniff(path: &Path) -> Result<Container, DecodeError> {
    let mut file =
        File::open(path).map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let mut magic = [0_u8; 8];
    file.read_exact(&mut magic).map_err(|_| {
        DecodeError::new(ErrorCode::Truncated, "file shorter than any raster magic")
    })?;
    if magic.starts_with(&MAGIC_JPEG) {
        Ok(Container::Jpeg)
    } else if magic == MAGIC_PNG {
        Ok(Container::Png)
    } else if magic.starts_with(&MAGIC_TIFF_LE) || magic.starts_with(&MAGIC_TIFF_BE) {
        Ok(Container::Tiff)
    } else {
        Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            "not a JPEG, PNG, or TIFF file",
        ))
    }
}

/// Open `path` for a decoder run.
fn open_file(path: &Path) -> Result<File, DecodeError> {
    File::open(path).map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))
}

/// Verify `samples` is exactly what the geometry promises.
fn check_len(width: u32, height: u32, components: u32, samples: u64) -> Result<(), DecodeError> {
    let expected = u64::from(width)
        .checked_mul(u64::from(height))
        .and_then(|v| v.checked_mul(u64::from(components)));
    if expected.is_some_and(|v| v == samples) {
        Ok(())
    } else {
        Err(DecodeError::new(
            ErrorCode::Internal,
            "decoder returned a short pixel buffer",
        ))
    }
}

/// Map a `zune-jpeg` failure: unsupported variants keep their own code, every
/// other failure (short reads, bad markers, Huffman faults) is truncation.
fn jpeg_error(stage: &str, err: &zune_jpeg::errors::DecodeErrors) -> DecodeError {
    match err {
        zune_jpeg::errors::DecodeErrors::Unsupported(_) => {
            DecodeError::new(ErrorCode::UnsupportedFormat, format!("JPEG {stage}: {err}"))
        }
        _ => DecodeError::new(ErrorCode::Truncated, format!("JPEG {stage}: {err}")),
    }
}

/// Decode JPEG (`zune-jpeg`, 8-bit, gray/RGB; CMYK and friends rejected).
///
/// Note: `output_colorspace` reports the decoder's *requested* output space
/// (default RGB), not the file's — gray detection reads `input_colorspace`
/// and re-decodes with a Luma output option when the file is gray.
fn decode_jpeg(path: &Path) -> Result<RasterImage, DecodeError> {
    use zune_jpeg::zune_core::colorspace::ColorSpace;
    use zune_jpeg::zune_core::options::DecoderOptions;
    let file = open_file(path)?;
    let mut probe = zune_jpeg::JpegDecoder::new(std::io::BufReader::new(file));
    probe
        .decode_headers()
        .map_err(|err| jpeg_error("headers", &err))?;
    let Some((width, height)) = probe.dimensions() else {
        return Err(DecodeError::new(
            ErrorCode::Truncated,
            "JPEG headers report no dimensions",
        ));
    };
    let (Ok(width), Ok(height)) = (u32::try_from(width), u32::try_from(height)) else {
        return Err(DecodeError::new(
            ErrorCode::Truncated,
            "JPEG dimensions overflow u32",
        ));
    };
    let icc_profile = probe.icc_profile();
    match probe.input_colorspace() {
        Some(ColorSpace::Luma) => {
            let file = open_file(path)?;
            let options = DecoderOptions::default().jpeg_set_out_colorspace(ColorSpace::Luma);
            let mut decoder =
                zune_jpeg::JpegDecoder::new_with_options(std::io::BufReader::new(file), options);
            decoder
                .decode_headers()
                .map_err(|err| jpeg_error("headers", &err))?;
            let pixels = decoder.decode().map_err(|err| jpeg_error("decode", &err))?;
            let len = u64::try_from(pixels.len()).unwrap_or(u64::MAX);
            check_len(width, height, 1, len)?;
            Ok(RasterImage {
                width,
                height,
                components: 1,
                bit_depth: 8,
                pixels: RasterPixels::U8(pixels),
                icc_profile,
            })
        }
        Some(ColorSpace::RGB | ColorSpace::YCbCr) => {
            let pixels = probe.decode().map_err(|err| jpeg_error("decode", &err))?;
            let len = u64::try_from(pixels.len()).unwrap_or(u64::MAX);
            check_len(width, height, 3, len)?;
            Ok(RasterImage {
                width,
                height,
                components: 3,
                bit_depth: 8,
                pixels: RasterPixels::U8(pixels),
                icc_profile,
            })
        }
        other => Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            format!("JPEG colorspace not supported: {other:?}"),
        )),
    }
}

/// PNG color type to component count; [`None`] for palette.
fn png_components(color: png::ColorType) -> Option<u32> {
    match color {
        png::ColorType::Grayscale => Some(1),
        png::ColorType::GrayscaleAlpha => Some(2),
        png::ColorType::Rgb => Some(3),
        png::ColorType::Rgba => Some(4),
        png::ColorType::Indexed => None,
    }
}

/// Decode PNG (8/16-bit gray/gray-alpha/RGB/RGBA; palette and sub-8-bit
/// rejected).
fn decode_png(path: &Path) -> Result<RasterImage, DecodeError> {
    let file = open_file(path)?;
    let decoder = png::Decoder::new(std::io::BufReader::new(file));
    let mut reader = decoder
        .read_info()
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("PNG headers: {err}")))?;
    let width = reader.info().width;
    let height = reader.info().height;
    let bit_depth = match reader.info().bit_depth {
        png::BitDepth::Eight => 8,
        png::BitDepth::Sixteen => 16,
        depth => {
            return Err(DecodeError::new(
                ErrorCode::UnsupportedFormat,
                format!("PNG bit depth not supported: {depth:?}"),
            ));
        }
    };
    let Some(components) = png_components(reader.info().color_type) else {
        return Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            "PNG palette images are not supported",
        ));
    };
    let icc_profile = reader
        .info()
        .icc_profile
        .as_ref()
        .map(|profile| profile.to_vec());
    let Some(buffer_size) = reader.output_buffer_size() else {
        return Err(DecodeError::new(
            ErrorCode::Internal,
            "PNG reader reports no output size",
        ));
    };
    let mut buf = vec![0_u8; buffer_size];
    reader
        .next_frame(&mut buf)
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("PNG decode: {err}")))?;
    if bit_depth == 8 {
        let len = u64::try_from(buf.len()).unwrap_or(u64::MAX);
        check_len(width, height, components, len)?;
        Ok(RasterImage {
            width,
            height,
            components,
            bit_depth,
            pixels: RasterPixels::U8(buf),
            icc_profile,
        })
    } else {
        // PNG stores 16-bit samples big-endian.
        let samples: Vec<u16> = buf
            .as_chunks::<2>()
            .0
            .iter()
            .map(|octets| u16::from_be_bytes(*octets))
            .collect();
        let len = u64::try_from(samples.len()).unwrap_or(u64::MAX);
        check_len(width, height, components, len)?;
        Ok(RasterImage {
            width,
            height,
            components,
            bit_depth,
            pixels: RasterPixels::U16(samples),
            icc_profile,
        })
    }
}

/// The camera-RAW rejection detail (one sentence, shared by all arms).
fn camera_raw_rejection() -> DecodeError {
    DecodeError::new(
        ErrorCode::UnsupportedFormat,
        "camera RAW files decode through rawspeed, not the raster path",
    )
}

/// Reject camera-RAW TIFFs before any pixel read (DNG/CFA markers, old-JPEG
/// compression, CFA photometric). Runs on the EXIF parse, ahead of the
/// `tiff` decoder: camera IFDs (ARW/NEF IFD0 has no width/height tags) fail
/// `tiff::Decoder::new` outright, so the check cannot live behind it. Plain
/// rasters pass through untouched.
fn reject_camera_raw(parsed: &exif::Exif) -> Result<(), DecodeError> {
    // Presence is the signal (DNGVersion is a BYTE field, CFAPlaneColor can
    // be ASCII): any DNG-private tag in IFD0 marks a camera file.
    for marker in DNG_MARKER_TAGS {
        let tag = exif::Tag(exif::Context::Tiff, marker);
        if parsed.get_field(tag, exif::In::PRIMARY).is_some() {
            return Err(camera_raw_rejection());
        }
    }
    if crate::exif::ifd_tag_u32(parsed, 0, 259)
        .is_some_and(|v| v == u32::from(TIFF_COMPRESSION_OLD_JPEG))
    {
        return Err(camera_raw_rejection());
    }
    if crate::exif::ifd_tag_u32(parsed, 0, 262)
        .is_some_and(|v| v == u32::from(TIFF_PHOTOMETRIC_CFA))
    {
        return Err(camera_raw_rejection());
    }
    Ok(())
}

/// TIFF color type to (components, bit depth); [`None`] for palette/CMYK and
/// anything but 8/16-bit.
fn tiff_components(color: tiff::ColorType) -> Option<(u32, u8)> {
    match color {
        tiff::ColorType::Gray(depth) if depth == 8 || depth == 16 => Some((1, depth)),
        tiff::ColorType::GrayA(depth) if depth == 8 || depth == 16 => Some((2, depth)),
        tiff::ColorType::RGB(depth) if depth == 8 || depth == 16 => Some((3, depth)),
        tiff::ColorType::RGBA(depth) if depth == 8 || depth == 16 => Some((4, depth)),
        _ => None,
    }
}

/// Collect the ICC profile tag (34675) as bytes; [`None`] when absent or in
/// an unexpected shape (ICC is auxiliary — never an error).
fn tiff_icc<R: Read + std::io::Seek>(decoder: &mut tiff::decoder::Decoder<R>) -> Option<Vec<u8>> {
    let value = decoder.find_tag(tiff::tags::Tag::IccProfile).ok()??;
    if let tiff::decoder::ifd::Value::List(items) = value {
        let mut bytes = Vec::with_capacity(items.len());
        for item in items {
            if let tiff::decoder::ifd::Value::Byte(byte) = item {
                bytes.push(byte);
            } else {
                return None;
            }
        }
        if bytes.is_empty() { None } else { Some(bytes) }
    } else {
        None
    }
}

/// Decode TIFF (first IFD; 8/16-bit gray/gray-alpha/RGB/RGBA).
fn decode_tiff(path: &Path) -> Result<RasterImage, DecodeError> {
    let file = open_file(path)?;
    let mut probe = std::io::BufReader::new(file);
    let parsed = exif::Reader::new()
        .read_from_container(&mut probe)
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("TIFF open: {err}")))?;
    reject_camera_raw(&parsed)?;
    let file = open_file(path)?;
    let mut decoder = tiff::decoder::Decoder::new(file)
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("TIFF open: {err}")))?;
    let (width, height) = decoder
        .dimensions()
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("TIFF headers: {err}")))?;
    let color = decoder
        .colortype()
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("TIFF headers: {err}")))?;
    let Some((components, bit_depth)) = tiff_components(color) else {
        return Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            format!("TIFF color type not supported: {color:?}"),
        ));
    };
    let icc_profile = tiff_icc(&mut decoder);
    let image = decoder
        .read_image()
        .map_err(|err| DecodeError::new(ErrorCode::Truncated, format!("TIFF decode: {err}")))?;
    match image {
        tiff::decoder::DecodingResult::U8(pixels) => {
            let len = u64::try_from(pixels.len()).unwrap_or(u64::MAX);
            check_len(width, height, components, len)?;
            Ok(RasterImage {
                width,
                height,
                components,
                bit_depth,
                pixels: RasterPixels::U8(pixels),
                icc_profile,
            })
        }
        tiff::decoder::DecodingResult::U16(pixels) => {
            let len = u64::try_from(pixels.len()).unwrap_or(u64::MAX);
            check_len(width, height, components, len)?;
            Ok(RasterImage {
                width,
                height,
                components,
                bit_depth,
                pixels: RasterPixels::U16(pixels),
                icc_profile,
            })
        }
        _ => Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            "TIFF sample format is not 8- or 16-bit integer",
        )),
    }
}

/// Decode a JPEG, PNG, or TIFF file into one uniform buffer.
///
/// # Errors
///
/// Returns [`ErrorCode::NotFound`] when the file cannot be opened,
/// [`ErrorCode::Truncated`] for short or corrupt files,
/// [`ErrorCode::UnsupportedFormat`] for non-raster bytes, camera-RAW TIFFs,
/// and unsupported variants (CMYK, palette, sub-8-bit, non-8/16-bit).
pub fn decode_raster(path: &Path) -> Result<RasterImage, DecodeError> {
    match sniff(path)? {
        Container::Jpeg => decode_jpeg(path),
        Container::Png => decode_png(path),
        Container::Tiff => decode_tiff(path),
    }
}
