// SPDX-License-Identifier: GPL-3.0-or-later
//! `decode --dump` end to end through the built binary: fields, timings,
//! `--thumb OUT` extraction, raster files, corrupt input, and flag validation.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;
use std::process::Command;

/// CC0 sample directory (read-only).
fn sample_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME unset");
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Lightamer")
        .join("TestRAW")
}

fn run_decode(args: &[&str]) -> std::process::Output {
    let binary = PathBuf::from(env!("CARGO_BIN_EXE_lightamer-cli"));
    Command::new(binary)
        .arg("decode")
        .args(args)
        .output()
        .expect("decode failed to spawn")
}

#[test]
fn decode_dump_prints_fields_and_timings() {
    let sample = sample_dir().join("DSCF0021.RAF");
    let output = run_decode(&["--dump", &sample.to_string_lossy()]);
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(output.status.success(), "dump failed: {stdout}");
    for key in [
        "decoder: RafDecoder",
        "width: 7728",
        "height: 5152",
        "black: 1020",
        "white: 16383",
        "wb: ",
        "iso: 125",
        "meta_ms: ",
        "decode_ms_cold: ",
        "meta_parse_count: 1",
    ] {
        assert!(stdout.contains(key), "missing `{key}` in:\n{stdout}");
    }
    assert!(
        !stdout.contains("thumbnail:"),
        "no thumb line without --thumb:\n{stdout}"
    );
}

#[test]
fn decode_thumb_flag_writes_bytes_and_reports_format() {
    let dir =
        std::env::temp_dir().join(format!("lightamer-cli-decode-{}-thumb", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    let out = dir.join("raf-thumb.jpg");
    let sample = sample_dir().join("DSCF0021.RAF");
    let output = run_decode(&[
        "--dump",
        &sample.to_string_lossy(),
        "--thumb",
        &out.to_string_lossy(),
    ]);
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(output.status.success(), "dump --thumb failed: {stdout}");
    for key in [
        "thumbnail_format: jpeg",
        "thumbnail_bytes: 4016595",
        "thumbnail_decodable: true",
        "thumbnail_dims: 4416x2944",
        "thumbnail_written: ",
    ] {
        assert!(stdout.contains(key), "missing `{key}` in:\n{stdout}");
    }
    let written = std::fs::read(&out).expect("thumb output");
    assert_eq!(written.len(), 4_016_595);
    assert_eq!(&written[0..2], &[0xFF, 0xD8]);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn decode_repeat_two_reports_cold_and_hot() {
    let sample = sample_dir().join("DSCF0021.RAF");
    let output = run_decode(&["--dump", &sample.to_string_lossy(), "--repeat", "2"]);
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(output.status.success(), "dump --repeat 2 failed: {stdout}");
    assert!(
        stdout.contains("decode_ms_cold: "),
        "no cold line:\n{stdout}"
    );
    assert!(stdout.contains("decode_ms_hot: "), "no hot line:\n{stdout}");
}

#[test]
fn decode_dump_reports_corrupt_file() {
    let dir =
        std::env::temp_dir().join(format!("lightamer-cli-decode-{}-empty", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    let empty = dir.join("empty.ARW");
    std::fs::write(&empty, []).expect("write empty");
    let output = run_decode(&["--dump", &empty.to_string_lossy()]);
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    assert_eq!(output.status.code(), Some(2), "want exit 2, got {stderr}");
    assert!(
        stderr.contains("file is truncated or empty"),
        "missing typed message in: {stderr}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn decode_rejects_missing_dump_flag() {
    let output = run_decode(&[]);
    assert_eq!(output.status.code(), Some(2));
    let output = run_decode(&["--dump", "x.ARW", "--repeat", "0"]);
    assert_eq!(output.status.code(), Some(2));
    let output = run_decode(&["--dump", "x.ARW", "--repeat", "17"]);
    assert_eq!(output.status.code(), Some(2));
}

#[test]
fn decode_rejects_bare_thumb_flag() {
    // B2-b breaking change: `--thumb` takes the output path (B2-a's bare
    // flag is gone).
    let sample = sample_dir().join("DSCF0021.RAF");
    let output = run_decode(&["--dump", &sample.to_string_lossy(), "--thumb"]);
    assert_eq!(output.status.code(), Some(2));
}

#[test]
fn decode_dump_handles_raster_file() {
    let sample = sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg");
    let output = run_decode(&["--dump", &sample.to_string_lossy()]);
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(output.status.success(), "raster dump failed: {stdout}");
    for key in [
        "kind: raster",
        "width: 1620",
        "height: 1080",
        "bit_depth: 8",
        "components: 3",
        "icc: ",
        "exposure_time: ",
        "decode_ms_cold: ",
    ] {
        assert!(stdout.contains(key), "missing `{key}` in:\n{stdout}");
    }
}

#[test]
fn decode_thumb_on_raster_without_thumbnail_reports_typed_unavailable() {
    let dir = std::env::temp_dir().join(format!(
        "lightamer-cli-decode-{}-rasthumb",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    let out = dir.join("thumb.jpg");
    let sample = sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg");
    let output = run_decode(&[
        "--dump",
        &sample.to_string_lossy(),
        "--thumb",
        &out.to_string_lossy(),
    ]);
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(
        output.status.success(),
        "raster dump --thumb failed: {stdout}"
    );
    assert!(
        stdout.contains("thumbnail: unavailable (embedded thumbnail not available"),
        "missing typed thumb line in:\n{stdout}"
    );
    assert!(!out.exists(), "no output file on absence");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn decode_dump_reports_cr3_as_not_raw() {
    // This rawspeed pin ships no CR3 decoder: clean typed error, exit 2.
    let sample = sample_dir().join("IMG_4276.CR3");
    let output = run_decode(&["--dump", &sample.to_string_lossy()]);
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    assert_eq!(output.status.code(), Some(2), "want exit 2, got {stderr}");
    assert!(
        stderr.contains("not a supported RAW file"),
        "missing typed message in: {stderr}"
    );
}
