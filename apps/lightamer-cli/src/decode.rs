// SPDX-License-Identifier: GPL-3.0-or-later
//! `decode --dump`: developer probe over `lightamer-decode` (B2-b).
//!
//! Prints one `key: value` line per decoded field plus timings. Camera RAWs
//! decode through rawspeed, JPEG/PNG/TIFF rasters through the pure-Rust
//! raster path, `--thumb OUT` writes the embedded thumbnail bytes. This is a
//! developer tool, not an import command: it never touches the engine.

use std::path::PathBuf;
use std::time::Instant;

use lightamer_decode::{CfaColor, RawImage, decode_file};

use crate::util::{Error, io_error};

/// A `decode --dump` request from the CLI entry.
pub struct DumpRequest {
    /// File to decode.
    pub file: PathBuf,
    /// Write the embedded thumbnail bytes to this path (plus a format report).
    pub thumb: Option<PathBuf>,
    /// Decode repetitions: run 1 is cold (meta pre-loaded), later runs hot.
    pub repeat: usize,
}

/// Short CFA color letter.
fn cfa_letter(color: CfaColor) -> &'static str {
    match color {
        CfaColor::Red => "R",
        CfaColor::Green => "G",
        CfaColor::Blue => "B",
        CfaColor::Cyan => "C",
        CfaColor::Magenta => "M",
        CfaColor::Yellow => "Y",
        CfaColor::White => "W",
        CfaColor::FujiGreen => "FG",
        CfaColor::Unknown => "?",
    }
}

/// Comma-joined CFA pattern.
fn fmt_pattern(pattern: &[CfaColor]) -> String {
    pattern
        .iter()
        .map(|c| cfa_letter(*c))
        .collect::<Vec<_>>()
        .join(",")
}

/// Print the EXIF optics block (shared by the RAW and raster paths).
fn print_optics(
    exposure: Option<f64>,
    aperture: Option<f32>,
    focal: Option<f32>,
    lens: Option<&str>,
    capture: Option<&str>,
    orientation: Option<u16>,
) {
    match exposure {
        Some(value) => println!("exposure_time: {value}"),
        None => println!("exposure_time: none"),
    }
    match aperture {
        Some(value) => println!("aperture: {value}"),
        None => println!("aperture: none"),
    }
    match focal {
        Some(value) => println!("focal_length: {value}"),
        None => println!("focal_length: none"),
    }
    match lens {
        Some(value) => println!("lens_model: {value}"),
        None => println!("lens_model: none"),
    }
    match capture {
        Some(value) => println!("capture_time: {value}"),
        None => println!("capture_time: none"),
    }
    match orientation {
        Some(value) => println!("orientation: {value}"),
        None => println!("orientation: none"),
    }
}

/// Print the decoded RAW metadata fields, one `key: value` line each.
fn print_fields(meta: &lightamer_decode::RawMetadata) {
    println!("decoder: {}", meta.decoder);
    println!("make: {}", meta.make);
    println!("model: {}", meta.model);
    println!("canonical_make: {}", meta.canonical_make);
    println!("canonical_model: {}", meta.canonical_model);
    println!("mode: {}", meta.mode);
    println!("width: {}", meta.width);
    println!("height: {}", meta.height);
    println!(
        "uncropped: {}x{}",
        meta.uncropped_width, meta.uncropped_height
    );
    println!(
        "crop: left={} top={} right={} bottom={}",
        meta.crop.left, meta.crop.top, meta.crop.right, meta.crop.bottom
    );
    println!(
        "mosaic: {} pitch={} cpp={} bpp={}",
        match meta.mosaic_kind {
            lightamer_decode::MosaicKind::U16 => "u16",
            lightamer_decode::MosaicKind::F32 => "f32",
        },
        meta.pitch_elems,
        meta.cpp,
        meta.bpp
    );
    println!("is_cfa: {}", meta.is_cfa);
    println!("is_xtrans: {}", meta.is_xtrans);
    println!(
        "cfa: {}x{} [{}] filter=0x{:08X}",
        meta.cfa_w,
        meta.cfa_h,
        fmt_pattern(&meta.cfa_pattern),
        meta.cfa_dcraw_filter
    );
    println!("black: {}", meta.black_level);
    match meta.black_separate {
        Some(sep) => println!("black_sep: {},{},{},{}", sep[0], sep[1], sep[2], sep[3]),
        None => println!("black_sep: none"),
    }
    match meta.white_level {
        Some(white) => println!("white: {white}"),
        None => println!("white: none"),
    }
    match meta.white_balance {
        Some(wb) => println!("wb: {},{},{},{}", wb[0], wb[1], wb[2], wb[3]),
        None => println!("wb: none"),
    }
    println!("wb_kelvin: none (no standard EXIF tag carries it)");
    match meta.color_matrix_xyz_to_cam {
        Some(m) => println!(
            "matrix_xyz_to_cam: {},{},{},{},{},{},{},{},{}",
            m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]
        ),
        None => println!("matrix_xyz_to_cam: none"),
    }
    match meta.color_matrix_cam_to_xyz {
        Some(m) => println!(
            "matrix_cam_to_xyz: {},{},{},{},{},{},{},{},{}",
            m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]
        ),
        None => println!("matrix_cam_to_xyz: none"),
    }
    match meta.iso {
        Some(iso) => println!("iso: {iso}"),
        None => println!("iso: none"),
    }
    print_optics(
        meta.exposure_time,
        meta.aperture,
        meta.focal_length,
        meta.lens_model.as_deref(),
        meta.capture_time.as_deref(),
        meta.orientation,
    );
    println!("subsampling: {}x{}", meta.subsampling.0, meta.subsampling.1);
    println!("pixel_aspect: {}", meta.pixel_aspect_ratio);
    println!("mosaic_bytes: {}", meta.mosaic_bytes);
}

/// Print the decoded raster fields, one `key: value` line each.
fn print_raster(image: &lightamer_decode::RasterImage) {
    println!("kind: raster");
    println!("width: {}", image.width);
    println!("height: {}", image.height);
    println!("bit_depth: {}", image.bit_depth);
    println!("components: {}", image.components);
    match &image.icc_profile {
        Some(profile) => println!("icc: present ({} bytes)", profile.len()),
        None => println!("icc: none"),
    }
}

/// Which decode path the magic selects. TIFF magic routes RAW-first (camera
/// RAWs are TIFF-based); JPEG/PNG magic routes raster-only; anything else
/// routes RAW-only.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Route {
    RawFirst,
    RasterOnly,
    RawOnly,
}

/// Peek the first bytes for routing (content only, never the extension).
fn route_for(file: &std::path::Path) -> Route {
    use std::io::Read;
    let mut magic = [0_u8; 8];
    let Ok(mut handle) = std::fs::File::open(file) else {
        return Route::RawOnly;
    };
    let Ok(()) = handle.read_exact(&mut magic) else {
        return Route::RawOnly;
    };
    if magic.starts_with(&[0xFF, 0xD8]) || magic == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    {
        Route::RasterOnly
    } else if magic.starts_with(&[0x49, 0x49, 0x2A, 0x00])
        || magic.starts_with(&[0x4D, 0x4D, 0x00, 0x2A])
    {
        Route::RawFirst
    } else {
        Route::RawOnly
    }
}

/// Handle `--thumb OUT`: write the embedded thumbnail bytes and report
/// format, byte count, decodability, and dimensions. Absence prints a typed
/// line and still exits 0: the dump itself succeeded.
fn write_thumb(file: &std::path::Path, out: &std::path::Path) -> Result<(), Error> {
    match lightamer_decode::read_thumbnail(file) {
        Ok(thumb) => {
            let (format, bytes, dims) = match &thumb {
                lightamer_decode::Thumbnail::Jpeg { bytes } => {
                    let dims = lightamer_decode::jpeg_dimensions(bytes)
                        .map_err(|err| Error::new(format!("thumbnail: {err}")))?;
                    ("jpeg", bytes.as_slice(), dims)
                }
                lightamer_decode::Thumbnail::Raw {
                    width,
                    height,
                    pixels,
                    ..
                } => ("raw", pixels.as_slice(), (*width, *height)),
            };
            std::fs::write(out, bytes).map_err(|err| io_error(out, err))?;
            println!("thumbnail_format: {format}");
            println!("thumbnail_bytes: {}", bytes.len());
            println!("thumbnail_decodable: true");
            println!("thumbnail_dims: {}x{}", dims.0, dims.1);
            println!("thumbnail_written: {}", out.display());
            Ok(())
        }
        Err(err) => {
            println!("thumbnail: unavailable ({err})");
            Ok(())
        }
    }
}

/// Dump one file's decode result plus timings.
///
/// # Errors
///
/// Returns [`Error`] when the repeat count is 0, the camera database fails
/// to load, the file fails every decode path (the message carries the typed
/// decode error), or the thumbnail output cannot be written.
pub fn dump(req: &DumpRequest) -> Result<(), Error> {
    if req.repeat == 0 {
        return Err(Error::new("repeat must be >= 1".to_owned()));
    }
    match route_for(&req.file) {
        Route::RasterOnly => dump_raster(req),
        Route::RawOnly => dump_raw(req),
        Route::RawFirst => match dump_raw(req) {
            Ok(()) => Ok(()),
            Err(raw_err) => dump_raster_fallback(req, raw_err),
        },
    }
}

/// RAW path: rawspeed decode plus EXIF-merged fields and timings.
fn dump_raw(req: &DumpRequest) -> Result<(), Error> {
    let meta_start = Instant::now();
    RawImage::ensure_metadata().map_err(|err| Error::new(format!("camera database: {err}")))?;
    let meta_ms = meta_start.elapsed().as_secs_f64() * 1000.0;

    let mut cold_ms = 0.0;
    let mut hot_ms = 0.0;
    let mut decoded = None;
    for run in 0..req.repeat {
        let start = Instant::now();
        let one = decode_file(&req.file).map_err(|err| Error::new(format!("decode: {err}")))?;
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        if run == 0 {
            cold_ms = ms;
        }
        hot_ms = ms;
        decoded = Some(one);
    }
    let Some(final_image) = decoded else {
        return Err(Error::new("repeat must be >= 1".to_owned()));
    };
    let meta = &final_image.meta;

    println!("file: {}", req.file.display());
    print_fields(meta);
    println!("meta_ms: {meta_ms:.3}");
    println!("decode_ms_cold: {cold_ms:.3}");
    println!("decode_ms_hot: {hot_ms:.3}");
    println!("meta_parse_count: {}", RawImage::meta_parse_count());
    if let Some(out) = &req.thumb {
        write_thumb(&req.file, out)?;
    }
    Ok(())
}

/// Raster path: pure-Rust JPEG/PNG/TIFF decode plus timings.
fn dump_raster(req: &DumpRequest) -> Result<(), Error> {
    let mut cold_ms = 0.0;
    let mut hot_ms = 0.0;
    let mut decoded = None;
    for run in 0..req.repeat {
        let start = Instant::now();
        let one = lightamer_decode::decode_raster(&req.file)
            .map_err(|err| Error::new(format!("raster: {err}")))?;
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        if run == 0 {
            cold_ms = ms;
        }
        hot_ms = ms;
        decoded = Some(one);
    }
    let Some(image) = decoded else {
        return Err(Error::new("repeat must be >= 1".to_owned()));
    };
    println!("file: {}", req.file.display());
    print_raster(&image);
    // EXIF optics ride along when the raster carries any (usually none).
    let optics = lightamer_decode::read_exif(&req.file).unwrap_or_default();
    print_optics(
        optics.exposure_time,
        optics.aperture,
        optics.focal_length,
        optics.lens_model.as_deref(),
        optics.capture_time.as_deref(),
        optics.orientation,
    );
    println!("decode_ms_cold: {cold_ms:.3}");
    println!("decode_ms_hot: {hot_ms:.3}");
    if let Some(out) = &req.thumb {
        write_thumb(&req.file, out)?;
    }
    Ok(())
}

/// TIFF-magic fallback: the RAW path failed, so probe the raster path once;
/// when that succeeds, run the full raster dump (timings included), else
/// report the original RAW error (primary for TIFF magic).
fn dump_raster_fallback(req: &DumpRequest, raw_err: Error) -> Result<(), Error> {
    match lightamer_decode::decode_raster(&req.file) {
        Ok(_) => dump_raster(req),
        Err(_) => Err(raw_err),
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    #[test]
    fn cfa_letters_cover_all_colors() {
        let colors = [
            CfaColor::Red,
            CfaColor::Green,
            CfaColor::Blue,
            CfaColor::Cyan,
            CfaColor::Magenta,
            CfaColor::Yellow,
            CfaColor::White,
            CfaColor::FujiGreen,
            CfaColor::Unknown,
        ];
        assert_eq!(fmt_pattern(&colors), "R,G,B,C,M,Y,W,FG,?");
    }

    #[test]
    fn dump_rejects_zero_repeat() {
        let req = DumpRequest {
            file: PathBuf::from("x.ARW"),
            thumb: None,
            repeat: 0,
        };
        assert!(dump(&req).is_err());
    }
}
