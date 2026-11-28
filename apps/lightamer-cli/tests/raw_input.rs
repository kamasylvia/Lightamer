// SPDX-License-Identifier: GPL-3.0-or-later
//! `RawFileSource`: probe/fetch/region behavior on the two Sony ARW
//! samples, the decode-once counters, and typed non-RAW refusal.
//!
//! The decode/probe counters are process-global, so every test here holds
//! the file-local serial lock for its whole body: counter deltas would
//! otherwise race with other tests' decodes in this binary.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;
use std::sync::Mutex;

use lightamer_decode::{RawImage, decode_file};
use lightamer_engine::{InputSource, RenderFacts};
use lightamer_raster::FrameExtent;

use lightamer_cli::raw_input::RawFileSource;

static SERIAL: Mutex<()> = Mutex::new(());

/// CC0 sample directory (read-only).
fn sample_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME unset");
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Lightamer")
        .join("TestRAW")
}

fn arw(name: &str) -> String {
    sample_dir()
        .join(name)
        .to_str()
        .expect("sample path is UTF-8")
        .to_owned()
}

#[test]
fn probe_facts_match_fetch_on_both_arw() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    for file in ["7RM5-LosslessCompressedLarge.ARW", "ColorChecker.ARW"] {
        let source = RawFileSource::new();
        let photo = arw(file);
        let RenderFacts { image, extent } = source.probe(&photo).expect("probe");
        assert!(image.is_raw(), "{file}: probe must read RAW");
        assert_eq!(image.format, lightamer_iop_traits::PixelFormat::MonoF32);
        assert_eq!((extent.width, extent.height), (9568, 6376));
        let fetched = source.fetch(&photo).expect("fetch");
        assert_eq!(fetched.image, image, "{file}: fetch facts drift from probe");
        assert_eq!(fetched.frame.extent(), extent);
        assert_eq!(
            fetched.frame.format(),
            lightamer_raster::PixelFormat::MonoF32
        );
        println!("{file}: probe == fetch, input_id {}", fetched.input_id);
    }
}

#[test]
fn whole_path_counts_probe_once_decode_once() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let source = RawFileSource::new();
    let photo = arw("7RM5-LosslessCompressedLarge.ARW");
    let probes = RawImage::probe_count();
    let decodes = RawImage::decode_count();
    let parses = RawImage::meta_parse_count();
    source.probe(&photo).expect("probe");
    assert_eq!(RawImage::probe_count() - probes, 1, "probe must run once");
    assert_eq!(
        RawImage::decode_count() - decodes,
        0,
        "probe decodes no pixels"
    );
    source.fetch(&photo).expect("fetch");
    assert_eq!(RawImage::probe_count() - probes, 1, "fetch probes nothing");
    assert_eq!(RawImage::decode_count() - decodes, 1, "fetch decodes once");
    assert_eq!(
        RawImage::meta_parse_count() - parses,
        0,
        "no cameras.xml re-parse per request (singleton)"
    );
}

#[test]
fn stream_pieces_share_one_decode_and_match_whole_crops() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let source = RawFileSource::new();
    let photo = arw("7RM5-LosslessCompressedLarge.ARW");
    let regions = [
        FrameExtent::new(0, 0, 2000, 1000),
        FrameExtent::new(2000, 1000, 3000, 2000),
        FrameExtent::new(5000, 3000, 4568, 3376),
        FrameExtent::new(0, 6000, 9568, 376),
    ];
    let probes = RawImage::probe_count();
    let decodes = RawImage::decode_count();
    let mut pieces = Vec::with_capacity(regions.len());
    for region in regions {
        pieces.push(source.fetch_region(&photo, region).expect("region"));
    }
    assert_eq!(
        RawImage::decode_count() - decodes,
        1,
        "pieces share one decode"
    );
    assert_eq!(RawImage::probe_count() - probes, 0, "regions probe nothing");
    // Reference pixels come from the same cached decode: no second decode.
    let whole = source.fetch(&photo).expect("whole");
    assert_eq!(
        RawImage::decode_count() - decodes,
        1,
        "fetch reuses the cache"
    );
    for (piece, region) in pieces.iter().zip(regions.iter()) {
        assert_eq!(piece.frame.extent(), *region);
        assert_eq!(piece.image, whole.image, "piece facts match the whole");
        let view = whole.frame.view(*region).expect("crop");
        for row in 0..region.height {
            assert_eq!(
                piece.frame.row(row).expect("piece row"),
                view.row(row).expect("whole row"),
                "row {row} of {region:?} disagrees"
            );
        }
    }
    println!("4 pieces, 1 decode, all bytes match the whole frame");
}

#[test]
fn fallback_probe_caches_so_fetch_decodes_nothing() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let source = RawFileSource::new();
    let photo = arw("DSCF0021.RAF");
    let decodes = RawImage::decode_count();
    source.probe(&photo).expect("fallback probe");
    assert_eq!(
        RawImage::decode_count() - decodes,
        1,
        "fallback probe decodes"
    );
    source.fetch(&photo).expect("fetch");
    assert_eq!(
        RawImage::decode_count() - decodes,
        1,
        "fetch reuses the fallback decode"
    );
}

#[test]
fn non_raw_files_are_typed_refusals() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let source = RawFileSource::new();
    let photo = arw("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg");
    assert!(
        std::path::Path::new(&photo).is_file(),
        "need the JPEG preview"
    );
    for outcome in [
        source.probe(&photo).map(|_| ()),
        source.fetch(&photo).map(|_| ()),
        source
            .fetch_region(&photo, FrameExtent::new(0, 0, 8, 8))
            .map(|_| ()),
    ] {
        let err = outcome.expect_err("JPEG must not serve as RAW input");
        assert!(
            err.reason().contains("NotRaw"),
            "refusal must name its code: {}",
            err.reason()
        );
    }
}

#[test]
fn regions_outside_the_frame_fail_typed() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let source = RawFileSource::new();
    let photo = arw("7RM5-LosslessCompressedLarge.ARW");
    let err = source
        .fetch_region(&photo, FrameExtent::new(9500, 6300, 100, 100))
        .expect_err("overhang must fail");
    assert!(
        err.reason().contains("leaves the"),
        "unexpected refusal: {}",
        err.reason()
    );
    // A failed region poisons nothing: the whole frame still serves.
    let whole = source.fetch(&photo).expect("whole after refusal");
    assert_eq!(
        (whole.frame.extent().width, whole.frame.extent().height),
        (9568, 6376)
    );
    let direct =
        decode_file(&sample_dir().join("7RM5-LosslessCompressedLarge.ARW")).expect("direct decode");
    assert_eq!(whole.image.width, direct.meta.width);
}

#[test]
fn same_source_evicts_between_files() {
    let _serial = SERIAL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let source = RawFileSource::new();
    let a = arw("7RM5-LosslessCompressedLarge.ARW");
    let b = arw("ColorChecker.ARW");
    // Independent B pixels first (outside the counted window below).
    let direct_b = decode_file(&sample_dir().join("ColorChecker.ARW")).expect("direct B");
    let extent = FrameExtent::new(0, 0, direct_b.meta.width, direct_b.meta.height);
    let (frame_b, image_b) = direct_b.pipe_input(extent).expect("convert B");
    let decodes = RawImage::decode_count();
    let first_a = source.fetch(&a).expect("fetch A");
    assert_eq!(RawImage::decode_count() - decodes, 1);
    let got_b = source.fetch(&b).expect("fetch B");
    assert_eq!(
        RawImage::decode_count() - decodes,
        2,
        "B must evict A and decode, not serve it stale"
    );
    assert_ne!(got_b.input_id, first_a.input_id);
    assert_eq!(got_b.frame.as_slice(), frame_b.as_slice());
    assert_eq!(got_b.image, image_b);
    // Back to A: evicted, so it re-decodes and matches the first fetch.
    let second_a = source.fetch(&a).expect("fetch A again");
    assert_eq!(RawImage::decode_count() - decodes, 3);
    assert_eq!(second_a.frame.as_slice(), first_a.frame.as_slice());
    assert_eq!(second_a.input_id, first_a.input_id);
}
