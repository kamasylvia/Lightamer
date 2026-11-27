// SPDX-License-Identifier: GPL-3.0-or-later
//! Embedded thumbnails (B2-b).
//!
//! rawspeed at the pinned commit exposes NO thumbnail API (verified: no
//! `thumbnail`, `ThumbDataType`, or `decodeThumbnail` anywhere under
//! `external/rawspeed/src/`), so thumbnails come from each file's own
//! metadata instead of the decoder:
//!
//! - TIFF-based files (ARW/NEF/DNG/TIFF): group the `kamadak-exif` fields by
//!   IFD. JPEG candidates (`JPEGInterchangeFormat` 513 + length 514, SOI
//!   verified) win, smallest first; otherwise the first small uncompressed
//!   RGB/gray image (strips concatenated) wins.
//! - Fuji RAF: the fixed-offset embedded JPEG preview (see [`crate::exif`]).
//! - Anything else (JPEG APP1 thumbs need TIFF-base adjustment the crate does
//!   not expose, PNG carries none): [`ErrorCode::ThumbnailUnavailable`].
//!
//! The B2-a `rs_thumb` placeholder is removed (C ABI, shim, and FFI
//! declarations); this module is its replacement.

use std::collections::BTreeSet;
use std::fs::File;
use std::io::{BufReader, Read, Seek, SeekFrom};
use std::path::Path;

use crate::error::{DecodeError, ErrorCode};
use crate::exif::read_raf_preview_bytes;

/// Embedded thumbnail payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Thumbnail {
    /// JPEG bytes verbatim (SOI verified, length from IFD or RAF header).
    Jpeg {
        /// The JPEG byte range.
        bytes: Vec<u8>,
    },
    /// Uncompressed chunky pixels (strips concatenated in order).
    Raw {
        /// Thumbnail width.
        width: u32,
        /// Thumbnail height.
        height: u32,
        /// Components per pixel (1 gray, 3 RGB).
        components: u32,
        /// Bits per component (8 or 16).
        bits_per_sample: u8,
        /// Row-major pixels, `width * height * components` samples.
        pixels: Vec<u8>,
    },
}

/// Thumbnail payload kind (for the CLI probe line).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThumbnailFormat {
    /// JPEG bytes.
    Jpeg,
    /// Uncompressed pixels.
    Raw,
}

impl Thumbnail {
    /// The payload kind.
    #[must_use]
    pub const fn format(&self) -> ThumbnailFormat {
        match self {
            Self::Jpeg { .. } => ThumbnailFormat::Jpeg,
            Self::Raw { .. } => ThumbnailFormat::Raw,
        }
    }

    /// Payload byte count (JPEG length, or raw pixel bytes).
    #[must_use]
    pub fn byte_len(&self) -> usize {
        match self {
            Self::Jpeg { bytes } => bytes.len(),
            Self::Raw { pixels, .. } => pixels.len(),
        }
    }

    /// Whether the payload carries no bytes.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.byte_len() == 0
    }
}

/// TIFF magic (little/big-endian).
const TIFF_MAGIC_LE: [u8; 4] = [0x49, 0x49, 0x2A, 0x00];
const TIFF_MAGIC_BE: [u8; 4] = [0x4D, 0x4D, 0x00, 0x2A];
/// Fuji RAF magic (16 bytes; layout shared with [`crate::exif`]).
const RAF_MAGIC: &[u8; 16] = b"FUJIFILMCCD-RAW ";
/// JPEG SOI marker.
const JPEG_SOI: [u8; 2] = [0xFF, 0xD8];
/// TIFF tags read per IFD.
const TAG_IMAGE_WIDTH: u16 = 256;
const TAG_IMAGE_HEIGHT: u16 = 257;
const TAG_BITS_PER_SAMPLE: u16 = 258;
const TAG_COMPRESSION: u16 = 259;
const TAG_PHOTOMETRIC: u16 = 262;
const TAG_STRIP_OFFSETS: u16 = 273;
const TAG_SAMPLES_PER_PIXEL: u16 = 277;
const TAG_STRIP_BYTE_COUNTS: u16 = 279;
const TAG_JPEG_OFFSET: u16 = 513;
const TAG_JPEG_LENGTH: u16 = 514;
/// Uncompressed TIFF.
const COMPRESSION_NONE: u16 = 1;
/// Largest thumbnail side accepted (defense against corrupt headers).
const MAX_THUMB_SIDE: u32 = 4096;
/// Largest thumbnail payload accepted (256 MiB).
const MAX_THUMB_BYTES: u64 = 1 << 28;
/// TIFF tags read per IFD.
const TAG_SUBFILE_TYPE: u16 = 254;
/// Read exactly `len` bytes at `offset`; [`None`] on any failure.
fn read_at(file: &mut File, offset: u64, len: usize) -> Option<Vec<u8>> {
    file.seek(SeekFrom::Start(offset)).ok()?;
    let mut buf = vec![0_u8; len];
    file.read_exact(&mut buf).ok()?;
    Some(buf)
}

/// One IFD's tag value as `u32` list (Short and Long forms both).
fn tag_u32s(parsed: &exif::Exif, ifd: u16, tag: u16) -> Option<Vec<u32>> {
    crate::exif::ifd_tag_u32s(parsed, ifd, tag)
}

/// One IFD's tag value as a single `u32`.
fn tag_u32(parsed: &exif::Exif, ifd: u16, tag: u16) -> Option<u32> {
    crate::exif::ifd_tag_u32(parsed, ifd, tag)
}

/// All IFD indices present in the parse, ascending.
fn ifd_indices(parsed: &exif::Exif) -> Vec<u16> {
    let mut seen = BTreeSet::new();
    for field in parsed.fields() {
        seen.insert(field.ifd_num.index());
    }
    seen.into_iter().collect()
}

/// In-bounds check for `[offset, offset + len)` against `total`.
fn range_in_bounds(offset: u32, len: u32, total: u64) -> bool {
    len > 0
        && u64::from(offset)
            .checked_add(u64::from(len))
            .is_some_and(|end| end <= total)
}

/// Smallest SOI-verified JPEG (`513`/`514`) across the IFDs.
fn jpeg_thumbnail(
    file: &mut File,
    parsed: &exif::Exif,
    ifds: &[u16],
    total: u64,
) -> Option<Thumbnail> {
    let mut candidates: Vec<(u32, u32)> = Vec::new();
    for ifd in ifds {
        let (Some(offset), Some(len)) = (
            tag_u32(parsed, *ifd, TAG_JPEG_OFFSET),
            tag_u32(parsed, *ifd, TAG_JPEG_LENGTH),
        ) else {
            continue;
        };
        if range_in_bounds(offset, len, total) && u64::from(len) <= MAX_THUMB_BYTES {
            candidates.push((len, offset));
        }
    }
    candidates.sort_unstable();
    for (len, offset) in candidates {
        let Ok(len_usize) = usize::try_from(len) else {
            continue;
        };
        let Some(bytes) = read_at(file, u64::from(offset), len_usize) else {
            continue;
        };
        if bytes.first() == JPEG_SOI.first() && bytes.get(1) == JPEG_SOI.get(1) {
            return Some(Thumbnail::Jpeg { bytes });
        }
    }
    None
}

/// Bits-per-sample as one shared depth: every sample 8 or 16 and equal (a
/// single entry broadcasts to all components, per lenient readers).
fn shared_depth(depths: &[u32], components: u32) -> Option<u8> {
    if depths.is_empty() {
        return None;
    }
    let first = depths.first().copied()?;
    if first != 8 && first != 16 {
        return None;
    }
    if depths.len() == 1 {
        return u8::try_from(first).ok();
    }
    if u64::from(components) != depths.len() as u64 || depths.iter().any(|d| *d != first) {
        return None;
    }
    u8::try_from(first).ok()
}

/// First small uncompressed RGB/gray image marked reduced (`NewSubfileType`
/// 254 == 1) across the IFDs (ascending). The marker matters: without it a
/// plain small raster (IFD0 of an ordinary TIFF) would mispass as its own
/// thumbnail.
fn raw_thumbnail(
    file: &mut File,
    parsed: &exif::Exif,
    ifds: &[u16],
    total: u64,
) -> Option<Thumbnail> {
    for ifd in ifds {
        // Uncompressed candidates must be marked reduced images (DNG IFD0
        // carries 254 = 1; a plain raster's IFD0 omits the tag).
        if tag_u32(parsed, *ifd, TAG_SUBFILE_TYPE) != Some(1) {
            continue;
        }
        let Some(compression) = tag_u32(parsed, *ifd, TAG_COMPRESSION) else {
            continue;
        };
        if compression != u32::from(COMPRESSION_NONE) {
            continue;
        }
        let (Some(photo), Some(width), Some(height), Some(spp)) = (
            tag_u32(parsed, *ifd, TAG_PHOTOMETRIC),
            tag_u32(parsed, *ifd, TAG_IMAGE_WIDTH),
            tag_u32(parsed, *ifd, TAG_IMAGE_HEIGHT),
            tag_u32(parsed, *ifd, TAG_SAMPLES_PER_PIXEL),
        ) else {
            continue;
        };
        if photo > 2 || (spp != 1 && spp != 3) {
            continue;
        }
        if width == 0 || height == 0 || width > MAX_THUMB_SIDE || height > MAX_THUMB_SIDE {
            continue;
        }
        let Some(depths) = tag_u32s(parsed, *ifd, TAG_BITS_PER_SAMPLE) else {
            continue;
        };
        let Some(depth) = shared_depth(&depths, spp) else {
            continue;
        };
        let expected = u64::from(width)
            .checked_mul(u64::from(height))
            .and_then(|v| v.checked_mul(u64::from(spp)))
            .and_then(|v| v.checked_mul(u64::from(depth) / 8));
        let Some(expected) = expected else { continue };
        if expected == 0 || expected > MAX_THUMB_BYTES {
            continue;
        }
        let (Some(offsets), Some(counts)) = (
            tag_u32s(parsed, *ifd, TAG_STRIP_OFFSETS),
            tag_u32s(parsed, *ifd, TAG_STRIP_BYTE_COUNTS),
        ) else {
            continue;
        };
        if offsets.is_empty() || offsets.len() != counts.len() {
            continue;
        }
        let mut pixels: Vec<u8> = Vec::new();
        let mut ok = true;
        for (offset, count) in offsets.iter().zip(counts.iter()) {
            if !range_in_bounds(*offset, *count, total) {
                ok = false;
                break;
            }
            let Ok(count_usize) = usize::try_from(*count) else {
                ok = false;
                break;
            };
            let Some(chunk) = read_at(file, u64::from(*offset), count_usize) else {
                ok = false;
                break;
            };
            pixels.extend_from_slice(&chunk);
        }
        if ok && pixels.len() as u64 == expected {
            return Some(Thumbnail::Raw {
                width,
                height,
                components: spp,
                bits_per_sample: depth,
                pixels,
            });
        }
    }
    None
}

/// Decode just the JPEG headers for dimensions (proves decodability).
///
/// # Errors
///
/// Returns [`ErrorCode::Truncated`] when the headers do not decode or the
/// dimensions overflow `u32`.
pub fn jpeg_dimensions(bytes: &[u8]) -> Result<(u32, u32), DecodeError> {
    let mut decoder = zune_jpeg::JpegDecoder::new(std::io::Cursor::new(bytes));
    decoder.decode_headers().map_err(|err| {
        DecodeError::new(
            ErrorCode::Truncated,
            format!("thumbnail JPEG headers do not decode: {err}"),
        )
    })?;
    decoder.dimensions().map_or_else(
        || {
            Err(DecodeError::new(
                ErrorCode::Truncated,
                "thumbnail JPEG headers report no dimensions",
            ))
        },
        |(width, height)| {
            let (Ok(width), Ok(height)) = (u32::try_from(width), u32::try_from(height)) else {
                return Err(DecodeError::new(
                    ErrorCode::Truncated,
                    "thumbnail JPEG dimensions overflow u32",
                ));
            };
            Ok((width, height))
        },
    )
}

/// Read the embedded thumbnail of `path`.
///
/// # Errors
///
/// Returns [`ErrorCode::NotFound`] when the file cannot be opened,
/// [`ErrorCode::Truncated`] when a claimed thumbnail's bytes are short or
/// out of range, [`ErrorCode::ThumbnailUnavailable`] when the file carries
/// no supported embedded thumbnail.
pub fn read_thumbnail(path: &Path) -> Result<Thumbnail, DecodeError> {
    let mut file =
        File::open(path).map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let total = file
        .seek(SeekFrom::End(0))
        .map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let Some(magic) = read_at(&mut file, 0, RAF_MAGIC.len()) else {
        return Err(DecodeError::new(
            ErrorCode::Truncated,
            "file shorter than any container magic",
        ));
    };
    if magic.as_slice() == RAF_MAGIC {
        return read_raf_preview_bytes(path).map(|bytes| Thumbnail::Jpeg { bytes });
    }
    let is_tiff = magic.starts_with(&TIFF_MAGIC_LE) || magic.starts_with(&TIFF_MAGIC_BE);
    if !is_tiff {
        return Err(DecodeError::new(
            ErrorCode::ThumbnailUnavailable,
            "only TIFF-based files and RAF carry supported embedded thumbnails",
        ));
    }
    let mut ranges = file
        .try_clone()
        .map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    // The magic peek left the cursor at 16; rewind before the parse.
    file.seek(SeekFrom::Start(0))
        .map_err(|err| DecodeError::new(ErrorCode::NotFound, err.to_string()))?;
    let mut reader = BufReader::new(file);
    let parsed = exif::Reader::new()
        .read_from_container(&mut reader)
        .map_err(|err| {
            DecodeError::new(ErrorCode::Truncated, format!("EXIF parse failed: {err}"))
        })?;
    let ifds = ifd_indices(&parsed);
    if let Some(thumb) = jpeg_thumbnail(&mut ranges, &parsed, &ifds, total) {
        return Ok(thumb);
    }
    if let Some(thumb) = raw_thumbnail(&mut ranges, &parsed, &ifds, total) {
        return Ok(thumb);
    }
    Err(DecodeError::new(
        ErrorCode::ThumbnailUnavailable,
        "no JPEG or uncompressed thumbnail in the TIFF IFDs",
    ))
}
