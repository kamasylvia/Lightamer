// SPDX-License-Identifier: GPL-3.0-or-later
//! Repeatability: double-run bit identity, singleton parse-once, and a
//! no-leak RSS check over repeated decodes.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;
use std::process::Command;

use lightamer_decode::{RawImage, decode_file};

/// CC0 sample directory (read-only).
fn sample_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME unset");
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Lightamer")
        .join("TestRAW")
}

/// Own resident set in KiB, via `ps` (macOS reports KiB).
fn own_rss_kb() -> u64 {
    let pid = std::process::id().to_string();
    let output = Command::new("ps")
        .args(["-o", "rss=", "-p", &pid])
        .output()
        .expect("ps failed");
    assert!(output.status.success(), "ps exited nonzero");
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u64>()
        .expect("ps rss parses")
}

#[test]
fn same_file_decoded_twice_is_bit_identical() {
    let path = sample_dir().join("DSCF0021.RAF");
    let first = decode_file(&path).expect("first decode");
    let second = decode_file(&path).expect("second decode");
    assert_eq!(first.meta, second.meta, "metadata differs across runs");
    assert_eq!(first.mosaic, second.mosaic, "mosaic differs across runs");
    println!("RAF double-run identical: {} samples", first.mosaic.len());
}

#[test]
fn camera_database_parses_once() {
    RawImage::ensure_metadata().expect("ensure meta");
    let before = RawImage::meta_parse_count();
    assert!(before >= 1, "meta never parsed");
    for file in [
        "7RM5-LosslessCompressedLarge.ARW",
        "DSCF0021.RAF",
        "Nikon_Z8_raw_14_bit_lossless_compression.NEF",
    ] {
        decode_file(&sample_dir().join(file)).expect("decode");
    }
    let after = RawImage::meta_parse_count();
    assert_eq!(before, after, "cameras.xml parsed more than once");
    println!("parse count stable at {after} across three decodes");
}

#[test]
fn repeated_decodes_do_not_grow_rss() {
    let path = sample_dir().join("DSCF0021.RAF");
    // Warm up (meta + allocator arenas), then sample the baseline.
    for _ in 0..3 {
        decode_file(&path).expect("warmup decode");
    }
    let baseline = own_rss_kb();
    for _ in 0..20 {
        let decoded = decode_file(&path).expect("decode");
        assert!(!decoded.mosaic.is_empty());
        drop(decoded);
    }
    let end = own_rss_kb();
    println!("rss baseline={baseline}KiB end={end}KiB");
    let growth = end.saturating_sub(baseline);
    assert!(
        growth < 32 * 1024,
        "RSS grew {growth}KiB over 20 decodes (baseline {baseline}KiB)"
    );
}
