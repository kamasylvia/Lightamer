// SPDX-License-Identifier: GPL-3.0-or-later
//! EXIF optics over `kamadak-exif` (B2-b).
//!
//! rawspeed exposes no EXIF optics (shutter, aperture, focal length, lens),
//! so this module reads them from the original file: TIFF-based RAWs
//! (ARW/NEF/DNG) and JPEGs go through the crate's container sniffing, Fuji
//! RAF goes through its embedded JPEG preview (fixed offsets, big-endian),
//! everything else yields empty fields.
//!
//! [`read_exif`] only fails when the file cannot be opened
//! ([`ErrorCode::NotFound`]). Absent or corrupt EXIF yields empty fields,
//! never an error: optics are auxiliary — pixels stay the product, and a
//! broken metadata block must not fail a decode.

use std::fs::File;
use std::io::{BufReader, Read, Seek, SeekFrom};
use std::path::Path;

use crate::error::{DecodeError, ErrorCode};

/// Shutter/aperture/focal/lens/capture-time/orientation from EXIF.
///
/// The white-balance slots are always [`None`]: no standard EXIF tag carries
/// kelvin/tint (vendor makernotes do, and parsing those is out of scope).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ExifOptics {
    /// Exposure time in seconds (`ExposureTime`).
    pub exposure_time: Option<f64>,
    /// Aperture f-number (`FNumber`).
    pub aperture: Option<f32>,
    /// Focal length in mm (`FocalLength`).
    pub focal_length: Option<f32>,
    /// Lens model (`LensModel`).
    pub lens_model: Option<String>,
    /// Capture time (`DateTimeOriginal`), verbatim `YYYY:MM:DD HH:MM:SS`.
    pub capture_time: Option<String>,
    /// Orientation (`Orientation`), raw 1-8 value.
    pub orientation: Option<u16>,
    /// In-camera white-balance kelvin. Always [`None`] (see above).
    pub white_balance_kelvin: Option<f32>,
    /// In-camera white-balance tint. Always [`None`] (see above).
    pub white_balance_tint: Option<f32>,
}

/// Fuji RAF magic (16 bytes).
const RAF_MAGIC: &[u8; 16] = b"FUJIFILMCCD-RAW ";
/// RAF embedded-preview offset/length fields (big-endian `u32`).
const RAF_PREVIEW_OFFSET_AT: u64 = 84;
const RAF_PREVIEW_LENGTH_AT: u64 = 88;
/// JPEG SOI marker (preview sanity check).
const JPEG_SOI: [u8; 2] = [0xFF, 0xD8];

/// First rational of a primary-IFD tag, denominator non-zero.
fn first_rational(parsed: &exif::Exif, tag: exif::Tag) -> Option<(u32, u32)> {
    let field = parsed.get_field(tag, exif::In::PRIMARY)?;
    if let exif::Value::Rational(values) = &field.value {
        let first = values.first()?;
        if first.denom != 0 {
            return Some((first.num, first.denom));
        }
    }
    None
}

/// One IFD's tag value as a `u32` list (Short and Long forms both).
pub(crate) fn ifd_tag_u32s(parsed: &exif::Exif, ifd: u16, tag: u16) -> Option<Vec<u32>> {
    let field = parsed.get_field(exif::Tag(exif::Context::Tiff, tag), exif::In(ifd))?;
    match &field.value {
        exif::Value::Short(values) => Some(values.iter().map(|v| u32::from(*v)).collect()),
        exif::Value::Long(values) => Some(values.clone()),
        _ => None,
    }
}

/// One IFD's tag value as a single `u32`.
pub(crate) fn ifd_tag_u32(parsed: &exif::Exif, ifd: u16, tag: u16) -> Option<u32> {
    ifd_tag_u32s(parsed, ifd, tag)?.first().copied()
}

/// First non-empty ASCII string of a primary-IFD tag, trimmed.
fn first_ascii(parsed: &exif::Exif, tag: exif::Tag) -> Option<String> {
    let field = parsed.get_field(tag, exif::In::PRIMARY)?;
    if let exif::Value::Ascii(values) = &field.value {
        for raw in values {
            let text = String::from_utf8_lossy(raw);
            let trimmed = text.trim_matches(['\0', ' ']);
            if !trimmed.is_empty() {
                return Some(trimmed.to_owned());
            }
        }
    }
    None
}

/// Rational to `f32` (via `f64`: `u32` is exact in `f64`, and optical values
/// are small enough that the final narrowing is lossless in practice).
#[allow(clippy::cast_possible_truncation)] // See above; f/1.2-class values.
fn ratio_f32(num: u32, denom: u32) -> f32 {
    (f64::from(num) / f64::from(denom)) as f32
}

/// Extract the optics from one parsed EXIF block (primary IFD).
fn optics_from_parsed(parsed: &exif::Exif) -> ExifOptics {
    let exposure_time = first_rational(parsed, exif::Tag::ExposureTime)
        .map(|(num, denom)| f64::from(num) / f64::from(denom));
    let aperture =
        first_rational(parsed, exif::Tag::FNumber).map(|(num, denom)| ratio_f32(num, denom));
    let focal_length =
        first_rational(parsed, exif::Tag::FocalLength).map(|(num, denom)| ratio_f32(num, denom));
    ExifOptics {
        exposure_time,
        aperture,
        focal_length,
        lens_model: first_ascii(parsed, exif::Tag::LensModel),
        capture_time: first_ascii(parsed, exif::Tag::DateTimeOriginal),
        orientation: parsed
            .get_field(exif::Tag::Orientation, exif::In::PRIMARY)
            .and_then(|field| {
                if let exif::Value::Short(values) = &field.value {
                    values.first().copied()
                } else {
                    None
                }
            }),
        white_balance_kelvin: None,
        white_balance_tint: None,
    }
}

/// Read exactly `len` bytes at `offset`; [`None`] on any failure (seek error,
/// short read). Bounds come free: reads past EOF fail.
fn read_at(file: &mut File, offset: u64, len: usize) -> Option<Vec<u8>> {
    file.seek(SeekFrom::Start(offset)).ok()?;
    let mut buf = vec![0_u8; len];
    file.read_exact(&mut buf).ok()?;
    Some(buf)
}

/// Big-endian `u32` at `offset`; [`None`] on any failure.
fn read_u32_be_at(file: &mut File, offset: u64) -> Option<u32> {
    let bytes = read_at(file, offset, 4)?;
    let arr: [u8; 4] = bytes.as_slice().try_into().ok()?;
    Some(u32::from_be_bytes(arr))
}

/// Length of `file` via end-seek; [`None`] when the seek fails.
fn file_len(file: &mut File) -> Option<u64> {
    file.seek(SeekFrom::End(0)).ok()
}

/// Read the RAF embedded-preview bytes (bounds-checked, SOI-verified).
///
/// # Errors
///
/// Returns [`ErrorCode::NotFound`] when the file cannot be opened,
/// [`ErrorCode::Truncated`] when the header or the preview range is short,
/// out of range, or fails the SOI check.
pub(crate) fn read_raf_preview_bytes(path: &Path) -> Result<Vec<u8>, DecodeError> {
    let mut file =
        File::open(path).map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let magic = read_at(&mut file, 0, RAF_MAGIC.len())
        .ok_or_else(|| DecodeError::new(ErrorCode::Truncated, "file shorter than RAF magic"))?;
    if magic.as_slice() != RAF_MAGIC {
        return Err(DecodeError::new(
            ErrorCode::Truncated,
            "not a RAF file (bad magic)",
        ));
    }
    let offset = read_u32_be_at(&mut file, RAF_PREVIEW_OFFSET_AT)
        .ok_or_else(|| DecodeError::new(ErrorCode::Truncated, "RAF preview offset unreadable"))?;
    let len = read_u32_be_at(&mut file, RAF_PREVIEW_LENGTH_AT)
        .ok_or_else(|| DecodeError::new(ErrorCode::Truncated, "RAF preview length unreadable"))?;
    let total = file_len(&mut file)
        .ok_or_else(|| DecodeError::new(ErrorCode::NotFound, "cannot stat RAF file"))?;
    let end = u64::from(offset)
        .checked_add(u64::from(len))
        .ok_or_else(|| DecodeError::new(ErrorCode::Truncated, "RAF preview range overflows"))?;
    if len < 2 || end > total {
        return Err(DecodeError::new(
            ErrorCode::Truncated,
            "RAF preview range out of bounds",
        ));
    }
    let bytes = usize::try_from(len)
        .ok()
        .and_then(|n| read_at(&mut file, u64::from(offset), n))
        .ok_or_else(|| DecodeError::new(ErrorCode::Truncated, "RAF preview short read"))?;
    if bytes.first() != JPEG_SOI.first() || bytes.get(1) != JPEG_SOI.get(1) {
        return Err(DecodeError::new(
            ErrorCode::Truncated,
            "RAF preview fails the JPEG SOI check",
        ));
    }
    Ok(bytes)
}

/// Read the EXIF optics of `path`.
///
/// TIFF-based files and JPEGs parse directly; RAF parses through its embedded
/// preview's APP1 block; anything else (PNG, corrupt metadata, bare bytes)
/// yields empty fields.
///
/// # Errors
///
/// Returns [`ErrorCode::NotFound`] only when the file cannot be opened.
/// Every other failure (no EXIF, corrupt EXIF, short file) yields
/// [`ExifOptics::default`].
pub fn read_exif(path: &Path) -> Result<ExifOptics, DecodeError> {
    let mut probe =
        File::open(path).map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let Some(magic) = read_at(&mut probe, 0, RAF_MAGIC.len()) else {
        return Ok(ExifOptics::default());
    };
    drop(probe);
    if magic.as_slice() == RAF_MAGIC {
        let Ok(preview) = read_raf_preview_bytes(path) else {
            return Ok(ExifOptics::default());
        };
        let mut cursor = std::io::Cursor::new(preview);
        match exif::Reader::new().read_from_container(&mut cursor) {
            Ok(parsed) => return Ok(optics_from_parsed(&parsed)),
            Err(_) => return Ok(ExifOptics::default()),
        }
    }
    let file =
        File::open(path).map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let mut reader = BufReader::new(file);
    match exif::Reader::new().read_from_container(&mut reader) {
        Ok(parsed) => Ok(optics_from_parsed(&parsed)),
        Err(_) => Ok(ExifOptics::default()),
    }
}
