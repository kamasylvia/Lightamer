// SPDX-License-Identifier: GPL-3.0-or-later
//! `decode --dump` end to end through the built binary: fields, timings,
//! the `--thumb` placeholder, corrupt input, and flag validation.

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
fn decode_thumb_flag_prints_placeholder() {
    let sample = sample_dir().join("DSCF0021.RAF");
    let output = run_decode(&["--dump", &sample.to_string_lossy(), "--thumb"]);
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(output.status.success(), "dump --thumb failed: {stdout}");
    assert!(
        stdout.contains("thumbnail: unavailable (B2-b fills this)"),
        "missing thumb placeholder in:\n{stdout}"
    );
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
