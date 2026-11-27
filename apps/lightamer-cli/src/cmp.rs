// SPDX-License-Identifier: GPL-3.0-or-later
//! 16-bit PNG comparison: mean/max diff (LSB), in-tolerance fraction, channel means.
//!
//! Same statistics as the spike's `cmp16.py` (f64 math, tolerance default
//! 1/255), plus gate checks so later waves can call this a pass/fail door.

use crate::util::{self, Error};
use png::{BitDepth, ColorType};
use std::fs;
use std::io::BufReader;
use std::path::Path;

/// Default tolerance in normalized units (1/255 ≈ 257 LSB16).
pub const DEFAULT_TOL: f64 = 1.0 / 255.0;

/// Decoded image: native samples widened to `u16`, row-major.
#[derive(Debug)]
pub struct Image {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Native bit depth (8 or 16).
    pub bit_depth: u8,
    /// Samples per pixel (1 gray, 2 gray+alpha, 3 RGB, 4 RGBA).
    pub channels: u8,
    /// All samples, row-major, `width*height*channels` long.
    pub samples: Vec<u16>,
}

/// Comparison knobs.
#[derive(Debug, Clone)]
pub struct Options {
    /// Tolerance in normalized units; samples at or under it count as in-tol.
    pub tol: f64,
    /// Gate: mean diff ceiling in LSB units (`None` = no gate).
    pub max_mean_lsb: Option<f64>,
    /// Gate: in-tolerance fraction floor (`None` = no gate).
    pub min_in_tol: Option<f64>,
    /// Mirror B horizontally before comparing (flip-module check).
    pub mirror_x_b: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            tol: DEFAULT_TOL,
            max_mean_lsb: None,
            min_in_tol: None,
            mirror_x_b: false,
        }
    }
}

/// Comparison statistics.
#[derive(Debug, Clone)]
pub struct Stats {
    /// Image width both inputs share.
    pub width: u32,
    /// Image height both inputs share.
    pub height: u32,
    /// Native bit depth both inputs share.
    pub bit_depth: u8,
    /// Channels both inputs share.
    pub channels: u8,
    /// Total samples compared (`width*height*channels`).
    pub samples: u64,
    /// Mean abs diff, normalized.
    pub mean_norm: f64,
    /// Max abs diff, normalized.
    pub max_norm: f64,
    /// Mean abs diff in native LSB units.
    pub mean_lsb: f64,
    /// Max abs diff in native LSB units.
    pub max_lsb: f64,
    /// Tolerance in normalized units.
    pub tol_norm: f64,
    /// Tolerance in native LSB units.
    pub tol_lsb: f64,
    /// Fraction of samples at or under tolerance.
    pub in_tol_frac: f64,
    /// Samples strictly beyond tolerance.
    pub beyond_tol_samples: u64,
    /// Pixels with any channel beyond tolerance.
    pub beyond_tol_pixels: u64,
    /// Per-channel means of A, normalized.
    pub mean_ch_a: Vec<f64>,
    /// Per-channel means of B, normalized.
    pub mean_ch_b: Vec<f64>,
}

/// Decode a PNG into widened samples (8/16-bit gray/RGB, with or without alpha).
///
/// # Errors
///
/// Returns [`Error`] on I/O failure, unsupported color type/depth, or corrupt data.
pub fn read_png(path: &Path) -> Result<Image, Error> {
    let file = fs::File::open(path).map_err(|e| util::io_error(path, e))?;
    let decoder = png::Decoder::new(BufReader::new(file));
    let mut reader = decoder
        .read_info()
        .map_err(|e| Error::new(format!("{}: png header: {e}", path.display())))?;
    let (width, height) = (reader.info().width, reader.info().height);
    let bit_depth = reader.info().bit_depth;
    let color = reader.info().color_type;
    let channels: u8 = match color {
        ColorType::Grayscale => 1,
        ColorType::GrayscaleAlpha => 2,
        ColorType::Rgb => 3,
        ColorType::Rgba => 4,
        other @ ColorType::Indexed => {
            return Err(Error::new(format!(
                "{}: unsupported color type {other:?}",
                path.display()
            )));
        }
    };
    let depth: u8 = match bit_depth {
        BitDepth::Eight => 8,
        BitDepth::Sixteen => 16,
        other => {
            return Err(Error::new(format!(
                "{}: unsupported bit depth {other:?}",
                path.display()
            )));
        }
    };
    let frame_len = reader
        .output_buffer_size()
        .ok_or_else(|| Error::new(format!("{}: png frame size unknown", path.display())))?;
    let mut raw = vec![0; frame_len];
    reader
        .next_frame(&mut raw)
        .map_err(|e| Error::new(format!("{}: png data: {e}", path.display())))?;
    let samples: Vec<u16> = if depth == 16 {
        raw.as_chunks::<2>()
            .0
            .iter()
            .map(|pair| u16::from_be_bytes(*pair))
            .collect()
    } else {
        raw.iter().map(|&byte| u16::from(byte)).collect()
    };
    Ok(Image {
        width,
        height,
        bit_depth: depth,
        channels,
        samples,
    })
}

/// Image dimensions without a full decode (header only).
///
/// # Errors
///
/// Returns [`Error`] on I/O failure or undecodable header.
pub fn png_info(path: &Path) -> Result<(u32, u32, u8, u8), Error> {
    let image = read_png(path)?;
    Ok((image.width, image.height, image.bit_depth, image.channels))
}

/// Single-pass accumulators.
struct Accum {
    sum: u64,
    max: u16,
    in_tol: u64,
    beyond_pixels: u64,
    sum_ch_a: Vec<u64>,
    sum_ch_b: Vec<u64>,
}

#[expect(clippy::cast_precision_loss)] // counts here are far below 2^53
fn finalize(width: u32, height: u32, bit_depth: u8, channels: u8, tol: f64, acc: &Accum) -> Stats {
    let pixels = u64::from(width) * u64::from(height);
    let samples = pixels * u64::from(channels);
    let scale: f64 = if bit_depth == 16 {
        f64::from(u16::MAX)
    } else {
        f64::from(u8::MAX)
    };
    let mean_lsb = acc.sum as f64 / samples as f64;
    Stats {
        width,
        height,
        bit_depth,
        channels,
        samples,
        mean_norm: mean_lsb / scale,
        max_norm: f64::from(acc.max) / scale,
        mean_lsb,
        max_lsb: f64::from(acc.max),
        tol_norm: tol,
        tol_lsb: tol * scale,
        in_tol_frac: acc.in_tol as f64 / samples as f64,
        beyond_tol_samples: samples - acc.in_tol,
        beyond_tol_pixels: acc.beyond_pixels,
        mean_ch_a: acc
            .sum_ch_a
            .iter()
            .map(|&s| s as f64 / pixels as f64 / scale)
            .collect(),
        mean_ch_b: acc
            .sum_ch_b
            .iter()
            .map(|&s| s as f64 / pixels as f64 / scale)
            .collect(),
    }
}

/// Error for a channel accumulator shorter than its channel count.
fn short_accumulator(channel: usize) -> Error {
    Error::new(format!("short accumulator: channel {channel} missing"))
}

/// Error for an image whose samples end before `index`.
fn short_image(index: usize, len: usize) -> Error {
    Error::new(format!(
        "short image: sample {index} missing ({len} samples)"
    ))
}

/// Compare two decoded images sample by sample.
///
/// # Errors
///
/// Returns [`Error`] when geometry, depth, or channel count differ.
pub fn compare_images(a: &Image, b: &Image, opts: &Options) -> Result<Stats, Error> {
    if (a.width, a.height, a.bit_depth, a.channels) != (b.width, b.height, b.bit_depth, b.channels)
    {
        return Err(Error::new(format!(
            "geometry mismatch: {}x{} d{} c{} vs {}x{} d{} c{}",
            a.width, a.height, a.bit_depth, a.channels, b.width, b.height, b.bit_depth, b.channels
        )));
    }
    let (width, height, channels) = (a.width as usize, a.height as usize, usize::from(a.channels));
    let scale: f64 = if a.bit_depth == 16 {
        f64::from(u16::MAX)
    } else {
        f64::from(u8::MAX)
    };
    let mut acc = Accum {
        sum: 0,
        max: 0,
        in_tol: 0,
        beyond_pixels: 0,
        sum_ch_a: vec![0_u64; channels],
        sum_ch_b: vec![0_u64; channels],
    };
    for y in 0..height {
        for x in 0..width {
            let bx = if opts.mirror_x_b { width - 1 - x } else { x };
            let mut pixel_beyond = false;
            for c in 0..channels {
                let ia = (y * width + x) * channels + c;
                let ib = (y * width + bx) * channels + c;
                let va = *a
                    .samples
                    .get(ia)
                    .ok_or_else(|| short_image(ia, a.samples.len()))?;
                let vb = *b
                    .samples
                    .get(ib)
                    .ok_or_else(|| short_image(ib, b.samples.len()))?;
                *acc.sum_ch_a
                    .get_mut(c)
                    .ok_or_else(|| short_accumulator(c))? += u64::from(va);
                *acc.sum_ch_b
                    .get_mut(c)
                    .ok_or_else(|| short_accumulator(c))? += u64::from(vb);
                let diff = va.abs_diff(vb);
                acc.sum += u64::from(diff);
                acc.max = acc.max.max(diff);
                if f64::from(diff) / scale <= opts.tol {
                    acc.in_tol += 1;
                } else {
                    pixel_beyond = true;
                }
            }
            if pixel_beyond {
                acc.beyond_pixels += 1;
            }
        }
    }
    Ok(finalize(
        a.width,
        a.height,
        a.bit_depth,
        a.channels,
        opts.tol,
        &acc,
    ))
}

/// Read two PNGs and compare them.
///
/// # Errors
///
/// Returns [`Error`] on read failure or geometry mismatch.
pub fn compare(a_path: &Path, b_path: &Path, opts: &Options) -> Result<Stats, Error> {
    let a = read_png(a_path)?;
    let b = read_png(b_path)?;
    compare_images(&a, &b, opts)
}

/// Gate violations (`max_mean_lsb`, `min_in_tol`); empty means pass.
#[must_use]
pub fn check_gates(stats: &Stats, opts: &Options) -> Vec<String> {
    let mut violations = Vec::new();
    if let Some(ceiling) = opts.max_mean_lsb
        && stats.mean_lsb > ceiling
    {
        violations.push(format!("mean_lsb {} > max {ceiling}", stats.mean_lsb));
    }
    if let Some(floor) = opts.min_in_tol
        && stats.in_tol_frac < floor
    {
        violations.push(format!("in_tol {} < min {floor}", stats.in_tol_frac));
    }
    violations
}

/// Human-readable stats block (same fields as `cmp16.py` plus beyond-tol counts).
#[must_use]
pub fn format_stats(stats: &Stats, a_name: &str, b_name: &str) -> String {
    let dtype = if stats.bit_depth == 16 {
        "uint16"
    } else {
        "uint8"
    };
    format!(
        "A={a_name} shape={}x{}x{} dtype={dtype}\n\
         B={b_name} shape={}x{}x{} dtype={dtype}\n\
         tol={:.6} (= {:.3} LSB)\n\
         mean_abs_diff={:.8} (= {:.4} LSB)\n\
         max_abs_diff={:.8} (= {:.4} LSB)\n\
         in_tol_fraction={:.8}\n\
         beyond_tol_samples={}\n\
         beyond_tol_pixels={}\n\
         mean_ch_A={:?}\n\
         mean_ch_B={:?}",
        stats.height,
        stats.width,
        stats.channels,
        stats.height,
        stats.width,
        stats.channels,
        stats.tol_norm,
        stats.tol_lsb,
        stats.mean_norm,
        stats.mean_lsb,
        stats.max_norm,
        stats.max_lsb,
        stats.in_tol_frac,
        stats.beyond_tol_samples,
        stats.beyond_tol_pixels,
        stats.mean_ch_a,
        stats.mean_ch_b,
    )
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;
    use png::Encoder;
    use std::path::PathBuf;

    /// Write a tiny 16-bit RGB PNG; pixels row-major, 3 samples each.
    fn write_rgb16(path: &Path, width: u32, height: u32, pixels: &[u16]) {
        let file = fs::File::create(path).unwrap();
        let mut enc = Encoder::new(file, width, height);
        enc.set_color(ColorType::Rgb);
        enc.set_depth(BitDepth::Sixteen);
        let mut writer = enc.write_header().unwrap();
        let mut raw = Vec::with_capacity(pixels.len() * 2);
        for &sample in pixels {
            raw.extend_from_slice(&sample.to_be_bytes());
        }
        writer.write_image_data(&raw).unwrap();
    }

    /// Float equality for integer-valued stats (clippy forbids `==` on `f64`).
    fn approx(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-9
    }

    fn temp_pair() -> (PathBuf, PathBuf, PathBuf) {
        let dir = util::make_temp_dir("lightamer-cli-cmp-test").unwrap();
        let a = dir.join("a.png");
        let b = dir.join("b.png");
        (a, b, dir)
    }

    #[test]
    fn identical_images_are_all_zero() {
        let (a_path, b_path, dir) = temp_pair();
        let pixels = vec![0_u16, 100, 65535, 7, 8, 9];
        write_rgb16(&a_path, 2, 1, &pixels);
        write_rgb16(&b_path, 2, 1, &pixels);
        let stats = compare(&a_path, &b_path, &Options::default()).unwrap();
        assert!(approx(stats.mean_lsb, 0.0));
        assert!(approx(stats.max_lsb, 0.0));
        assert!(approx(stats.in_tol_frac, 1.0));
        assert_eq!(stats.beyond_tol_samples, 0);
        assert_eq!(stats.beyond_tol_pixels, 0);
        assert_eq!(check_gates(&stats, &Options::default()).len(), 0);
        util::remove_dir_quiet(&dir);
    }

    #[test]
    fn known_diffs_match_hand_math() {
        // 2x1 RGB: diffs [0,0,0, 257,258,1000] over 6 samples.
        let (a_path, b_path, dir) = temp_pair();
        write_rgb16(&a_path, 2, 1, &[1000, 1000, 1000, 1000, 1000, 1000]);
        write_rgb16(&b_path, 2, 1, &[1000, 1000, 1000, 1257, 1258, 2000]);
        let stats = compare(&a_path, &b_path, &Options::default()).unwrap();
        // mean = 1515/6 = 252.5 LSB; max = 1000 LSB.
        assert!((stats.mean_lsb - 252.5).abs() < 1e-9);
        assert!(approx(stats.max_lsb, 1000.0));
        // tol = 257 LSB: 257 == 1/255 in f64 (bit-identical), so in-tol are
        // [0,0,0,257] (4 of 6); beyond are [258,1000] in one pixel.
        assert_eq!(stats.beyond_tol_samples, 2);
        assert_eq!(stats.beyond_tol_pixels, 1);
        assert!((stats.in_tol_frac - 4.0 / 6.0).abs() < 1e-12);
        // Channel means: A all 1000/65535; B[0] = 1257 avg over pixels.
        assert!((stats.mean_ch_a[0] - 1000.0 / 65535.0).abs() < 1e-12);
        let expected_b0 = f64::from(1000 + 1257) / 2.0 / 65535.0;
        assert!((stats.mean_ch_b[0] - expected_b0).abs() < 1e-12);
        util::remove_dir_quiet(&dir);
    }

    #[test]
    fn gates_fire_on_breach() {
        let (a_path, b_path, dir) = temp_pair();
        write_rgb16(&a_path, 1, 1, &[0, 0, 0]);
        write_rgb16(&b_path, 1, 1, &[1000, 0, 0]);
        let stats = compare(&a_path, &b_path, &Options::default()).unwrap();
        let breach = Options {
            max_mean_lsb: Some(1.0),
            min_in_tol: Some(0.9999),
            ..Options::default()
        };
        assert_eq!(check_gates(&stats, &breach).len(), 2);
        let pass = Options {
            max_mean_lsb: Some(1000.0),
            min_in_tol: Some(0.5),
            ..Options::default()
        };
        assert_eq!(check_gates(&stats, &pass).len(), 0);
        util::remove_dir_quiet(&dir);
    }

    #[test]
    fn mirror_x_compares_flipped() {
        let (a_path, b_path, dir) = temp_pair();
        write_rgb16(&a_path, 2, 1, &[1, 2, 3, 4, 5, 6]);
        write_rgb16(&b_path, 2, 1, &[4, 5, 6, 1, 2, 3]);
        let plain = compare(&a_path, &b_path, &Options::default()).unwrap();
        assert!(plain.max_lsb > 0.0);
        let mirror = Options {
            mirror_x_b: true,
            ..Options::default()
        };
        let flipped = compare(&a_path, &b_path, &mirror).unwrap();
        assert!(approx(flipped.max_lsb, 0.0));
        assert!(approx(flipped.mean_lsb, 0.0));
        util::remove_dir_quiet(&dir);
    }

    #[test]
    fn geometry_mismatch_is_an_error() {
        let (a_path, b_path, dir) = temp_pair();
        write_rgb16(&a_path, 1, 1, &[0, 0, 0]);
        write_rgb16(&b_path, 2, 1, &[0, 0, 0, 0, 0, 0]);
        assert!(compare(&a_path, &b_path, &Options::default()).is_err());
        util::remove_dir_quiet(&dir);
    }
}
