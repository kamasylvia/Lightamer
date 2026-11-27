// SPDX-License-Identifier: GPL-3.0-or-later
//! `decode --dump`: developer probe over `lightamer-decode` (B2-a).
//!
//! Prints one `key: value` line per decoded field plus timings. This is a
//! developer tool, not an import command: it never touches the engine.

use std::path::PathBuf;
use std::time::Instant;

use lightamer_decode::{CfaColor, RawImage, decode_file};

use crate::util::Error;

/// A `decode --dump` request from the CLI entry.
pub struct DumpRequest {
    /// File to decode.
    pub file: PathBuf,
    /// Print the thumbnail placeholder line (B2-b fills it).
    pub thumb: bool,
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

/// Print the decoded metadata fields, one `key: value` line each.
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
    println!("wb_kelvin: none (rawspeed does not expose it)");
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
    println!("exposure_time: none (rawspeed exposes no EXIF optics)");
    println!("aperture: none (rawspeed exposes no EXIF optics)");
    println!("focal_length: none (rawspeed exposes no EXIF optics)");
    println!("lens_model: none (rawspeed exposes no EXIF optics)");
    println!("subsampling: {}x{}", meta.subsampling.0, meta.subsampling.1);
    println!("pixel_aspect: {}", meta.pixel_aspect_ratio);
    println!("mosaic_bytes: {}", meta.mosaic_bytes);
}

/// Dump one file's decode result plus timings.
///
/// # Errors
///
/// Returns [`Error`] when the camera database fails to load or the file
/// fails to decode (the message carries the typed decode error).
pub fn dump(req: &DumpRequest) -> Result<(), Error> {
    if req.repeat == 0 {
        return Err(Error::new("repeat must be >= 1".to_owned()));
    }
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
    if req.thumb {
        println!("thumbnail: unavailable (B2-b fills this)");
    }
    Ok(())
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
            thumb: false,
            repeat: 0,
        };
        assert!(dump(&req).is_err());
    }
}
