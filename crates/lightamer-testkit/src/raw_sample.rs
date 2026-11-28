// SPDX-License-Identifier: GPL-3.0-or-later
//! RAW sample loader for module tests: sample file name in, mono frame
//! plus pipe facts out. A thin wrapper over the decode crate's pipe-input
//! entry with sample lookup and skip-on-absent.
//!
//! [`RawSample`] holds one decode for region-granular tests: tiles come
//! out through [`RawSample::region`] (no whole-frame float conversion),
//! and [`RawSample::block_means`] scans the stored mosaic for
//! brightest/darkest-block picks without materializing pixels.

use std::path::PathBuf;

use lightamer_decode::{DecodedImage, Mosaic, decode_file};
use lightamer_iop_traits::ImageInfo;
use lightamer_raster::{Frame, FrameExtent};

use crate::{Need, record};

// CC0 sample directory under `$HOME` (same layout the decode tests use).
fn sample_dir() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let dir = PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Lightamer")
        .join("TestRAW");
    dir.is_dir().then_some(dir)
}

/// Resolve `file` (e.g. `7RM5-LosslessCompressedLarge.ARW`) to its sample
/// path, recording a skip and returning [`None`] when the corpus is absent.
#[must_use]
pub fn sample_path(file: &str) -> Option<PathBuf> {
    let path = sample_dir().map(|dir| dir.join(file));
    if let Some(path) = path.filter(|path| path.is_file()) {
        Some(path)
    } else {
        record(
            Need::Corpus,
            &format!("no such sample: {file}"),
            file!(),
            line!(),
        );
        None
    }
}

/// Load `file` as pipe input: the whole mosaic as a mono frame plus its
/// facts. Returns [`None`] (after recording a skip) when the sample is
/// absent or fails to decode — decode-correctness itself is guarded loudly
/// by the decode crate's own tests, so module tests just stand down here.
#[must_use]
pub fn load_raw_sample(file: &str) -> Option<(Frame, ImageInfo)> {
    let path = sample_path(file)?;
    let decoded = match lightamer_decode::decode_file(&path) {
        Ok(decoded) => decoded,
        Err(err) => {
            record(
                Need::Corpus,
                &format!("cannot decode {file}: {err}"),
                file!(),
                line!(),
            );
            return None;
        }
    };
    let extent = FrameExtent::new(0, 0, decoded.meta.width, decoded.meta.height);
    match decoded.pipe_input(extent) {
        Ok(pair) => Some(pair),
        Err(err) => {
            record(
                Need::Corpus,
                &format!("no pipe input for {file}: {err}"),
                file!(),
                line!(),
            );
            None
        }
    }
}

/// One decoded sample held for region-granular tests: tiles and block
/// statistics come out of this single decode, so a test binary never
/// loads the same file twice concurrently.
pub struct RawSample {
    file: String,
    decoded: DecodedImage,
}

/// Mean of a block scan; empty scans read 0.
#[expect(clippy::cast_possible_truncation)]
// Block means order blocks; f32 keeps every ordering f64 would give here.
fn mean_of(total: f64, count: f64) -> f32 {
    if count == 0.0 {
        0.0
    } else {
        (total / count) as f32
    }
}

/// Mean of every `block` square over `samples` (row-major, `width` pitch):
/// partial edge blocks shrink to the frame. Pure indexing-free scan.
fn grid_means<T>(
    samples: &[T],
    width: usize,
    height: usize,
    block: usize,
    mut value: impl FnMut(&T) -> f64,
) -> Vec<f32> {
    let block = block.max(1);
    if width == 0 || height == 0 {
        return Vec::new();
    }
    let cols = width.div_ceil(block);
    let rows = height.div_ceil(block);
    let mut means = Vec::with_capacity(cols.saturating_mul(rows));
    for block_row in 0..rows {
        for block_col in 0..cols {
            let y0 = block_row.saturating_mul(block);
            let x0 = block_col.saturating_mul(block);
            let y1 = (y0.saturating_add(block)).min(height);
            let x1 = (x0.saturating_add(block)).min(width);
            let mut total = 0.0;
            let mut count = 0.0;
            for row in samples
                .chunks_exact(width)
                .skip(y0)
                .take(y1.saturating_sub(y0))
            {
                for sample in row.iter().skip(x0).take(x1.saturating_sub(x0)) {
                    total += value(sample);
                    count += 1.0;
                }
            }
            means.push(mean_of(total, count));
        }
    }
    means
}

impl RawSample {
    /// Decodes `file` once; [`None`] (after recording a skip) when the
    /// sample is absent or fails to decode.
    #[must_use]
    pub fn open(file: &str) -> Option<Self> {
        let path = sample_path(file)?;
        match decode_file(&path) {
            Ok(decoded) => Some(Self {
                file: file.to_owned(),
                decoded,
            }),
            Err(err) => {
                record(
                    Need::Corpus,
                    &format!("cannot decode {file}: {err}"),
                    file!(),
                    line!(),
                );
                None
            }
        }
    }

    /// Pipe facts for the whole capture (no pixels); [`None`] when the
    /// capture is not a mono-mosaic input (recorded as a skip).
    #[must_use]
    pub fn facts(&self) -> Option<ImageInfo> {
        match lightamer_decode::pipe::pipe_image(&self.decoded.meta) {
            Ok(image) => Some(image),
            Err(err) => {
                record(
                    Need::Corpus,
                    &format!("no pipe facts for {}: {err}", self.file),
                    file!(),
                    line!(),
                );
                None
            }
        }
    }

    /// Cropped-frame width and height.
    #[must_use]
    pub fn size(&self) -> (u32, u32) {
        (self.decoded.meta.width, self.decoded.meta.height)
    }

    /// Whether the stored mosaic holds `u16` words (else `f32` samples).
    #[must_use]
    pub fn stored_is_u16(&self) -> bool {
        matches!(self.decoded.mosaic, Mosaic::U16(_))
    }

    /// One tile as pipe input: the region as a mono frame plus the
    /// capture's full facts. [`None`] (after recording a skip) when the
    /// region leaves the frame — callers pass computed regions, so this
    /// only fires on test bugs.
    #[must_use]
    pub fn region(&self, extent: FrameExtent) -> Option<(Frame, ImageInfo)> {
        match self.decoded.pipe_input(extent) {
            Ok(pair) => Some(pair),
            Err(err) => {
                record(
                    Need::Corpus,
                    &format!("no pipe input for {}: {err}", self.file),
                    file!(),
                    line!(),
                );
                None
            }
        }
    }

    /// Mean stored sample of every `block` square, row-major over the
    /// cropped frame: block `(r, c)` sits at `r * width.div_ceil(block) + c`.
    #[must_use]
    pub fn block_means(&self, block: u32) -> Vec<f32> {
        let width = self.decoded.meta.width as usize;
        let height = self.decoded.meta.height as usize;
        let block = block.max(1) as usize;
        match &self.decoded.mosaic {
            Mosaic::U16(words) => grid_means(words, width, height, block, |s| f64::from(*s)),
            Mosaic::F32(samples) => grid_means(samples, width, height, block, |s| f64::from(*s)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::load_raw_sample;

    #[test]
    fn loads_the_a7r5_sample_as_mono_raw() {
        let Some((frame, image)) = load_raw_sample("7RM5-LosslessCompressedLarge.ARW") else {
            return;
        };
        assert_eq!((image.width, image.height), (9568, 6376));
        assert!(image.is_raw());
        assert_eq!(frame.extent().width, 9568);
    }

    #[test]
    fn missing_samples_skip_to_none() {
        assert!(load_raw_sample("no-such-sample.ARW").is_none());
    }
}
