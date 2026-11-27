// SPDX-License-Identifier: GPL-3.0-or-later
//! Oracle parity: three CC0 fixtures (ARW/RAF/NEF) decoded through the safe
//! wrapper must match the independent C++ oracle (`rs-oracle`, direct
//! rawspeed API, same static lib) on width, height, black, white, white
//! balance, and the cropped-mosaic FNV hash.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::collections::HashMap;
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

/// Run the oracle on one file; fail the test unless it exits 0.
fn oracle_output(file: &str) -> HashMap<String, String> {
    let path = sample_dir().join(file);
    assert!(path.is_file(), "missing CC0 sample: {}", path.display());
    let output = Command::new(env!("RS_ORACLE_BIN"))
        .arg(env!("RAWSPEED_CAMERAS_XML"))
        .arg(&path)
        .output()
        .expect("oracle failed to spawn");
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(output.status.success(), "oracle failed on {file}: {stdout}");
    let mut map = HashMap::new();
    for line in stdout.lines() {
        let (key, value) = line.split_once('=').expect("oracle line without '='");
        map.insert(key.to_owned(), value.to_owned());
    }
    map
}

/// Parse one oracle value or fail.
fn get(map: &HashMap<String, String>, key: &str) -> String {
    assert!(map.contains_key(key), "oracle lacks {key}");
    map.get(key).cloned().unwrap_or_default()
}

fn check_parity(file: &str) {
    let oracle = oracle_output(file);
    let path = sample_dir().join(file);
    let decoded = decode_file(&path).expect("safe wrapper failed where oracle passed");
    let meta = &decoded.meta;

    assert_eq!(
        meta.width.to_string(),
        get(&oracle, "width"),
        "{file} width"
    );
    assert_eq!(
        meta.height.to_string(),
        get(&oracle, "height"),
        "{file} height"
    );
    assert_eq!(
        meta.black_level.to_string(),
        get(&oracle, "black"),
        "{file} black"
    );
    let sep = meta.black_separate.map_or_else(
        || "none".to_owned(),
        |s| format!("{},{},{},{}", s[0], s[1], s[2], s[3]),
    );
    assert_eq!(sep, get(&oracle, "black_sep"), "{file} black_sep");
    let white = meta
        .white_level
        .map_or_else(|| "none".to_owned(), |w| w.to_string());
    assert_eq!(white, get(&oracle, "white"), "{file} white");
    let wb = meta.white_balance.map_or_else(
        || "none".to_owned(),
        |w| {
            let rounded: Vec<f32> = w
                .iter()
                .map(|v| {
                    // Oracle prints %.9g; f32 round-trips through 9 digits.
                    v.to_string().parse::<f32>().expect("f32 round-trip")
                })
                .collect();
            format!(
                "{},{},{},{}",
                rounded[0], rounded[1], rounded[2], rounded[3]
            )
        },
    );
    // Compare through f32: parse oracle's decimals back to f32 bits.
    let oracle_wb = get(&oracle, "wb");
    if oracle_wb == "none" {
        assert_eq!(wb, "none", "{file} wb");
    } else {
        let ours: Vec<f32> = wb
            .split(',')
            .map(|n| n.parse::<f32>().expect("wb f32"))
            .collect();
        let theirs: Vec<f32> = oracle_wb
            .split(',')
            .map(|n| n.parse::<f32>().expect("oracle wb f32"))
            .collect();
        assert_eq!(ours, theirs, "{file} wb bits");
    }

    let mut image = RawImage::open(&path).expect("reopen for hash");
    image.decode().expect("re-decode for hash");
    let hash = image.mosaic_hash().expect("mosaic hash");
    assert_eq!(
        format!("{hash:016x}"),
        get(&oracle, "mosaic_hash"),
        "{file} mosaic hash"
    );

    // Decoder name: the oracle prints the mangled typeid, the wrapper the
    // demangled class; the latter must appear in the former.
    let mangled = get(&oracle, "decoder");
    assert!(
        mangled.contains(&meta.decoder),
        "{file} decoder: {} not in {mangled}",
        meta.decoder
    );

    println!(
        "{file}: {}x{} black={} white={white} wb={wb} hash={:016x}",
        meta.width, meta.height, meta.black_level, hash
    );
}

#[test]
fn arw_matches_oracle() {
    check_parity("7RM5-LosslessCompressedLarge.ARW");
}

#[test]
fn raf_matches_oracle() {
    check_parity("DSCF0021.RAF");
}

#[test]
fn nef_matches_oracle() {
    check_parity("Nikon_Z8_raw_14_bit_lossless_compression.NEF");
}
