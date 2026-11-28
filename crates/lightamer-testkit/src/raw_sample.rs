// SPDX-License-Identifier: GPL-3.0-or-later
//! RAW sample loader for module tests: sample file name in, mono frame
//! plus pipe facts out. A thin wrapper over the decode crate's pipe-input
//! entry with sample lookup and skip-on-absent.

use std::path::PathBuf;

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
