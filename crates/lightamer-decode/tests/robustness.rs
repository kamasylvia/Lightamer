// SPDX-License-Identifier: GPL-3.0-or-later
//! Robustness: five corrupt inputs in one process each report their typed
//! code and the process survives (a valid decode still works afterwards).

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;

use lightamer_decode::{ErrorCode, decode_file};

/// CC0 sample directory (read-only).
fn sample_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME unset");
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Lightamer")
        .join("TestRAW")
}

/// Unique scratch directory for this test process.
fn scratch_dir() -> PathBuf {
    std::env::temp_dir().join(format!(
        "b2a-corrupt-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos()
    ))
}

/// Deterministic pseudo-random bytes (xorshift64*, fixed seed).
fn random_bytes(len: usize) -> Vec<u8> {
    let mut state: u64 = 0x243F_6A88_85A3_0B8D;
    let mut out = Vec::with_capacity(len);
    for _ in 0..len {
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        out.push((state.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 56) as u8);
    }
    out
}

#[test]
fn corrupt_inputs_each_report_their_code_and_the_process_survives() {
    let scratch = scratch_dir();
    std::fs::create_dir_all(&scratch).expect("scratch dir");
    let sample = sample_dir();
    let arw =
        std::fs::read(sample.join("7RM5-LosslessCompressedLarge.ARW")).expect("read ARW sample");
    assert!(arw.len() > 1_000_000, "ARW sample suspiciously small");

    // 1. Empty file.
    let empty = scratch.join("empty.ARW");
    std::fs::write(&empty, []).expect("write empty");
    // 2. Random bytes.
    let random = scratch.join("random.ARW");
    std::fs::write(&random, random_bytes(1 << 20)).expect("write random");
    // 3. Truncated to half.
    let truncated = scratch.join("truncated.ARW");
    std::fs::write(&truncated, &arw[..arw.len() / 2]).expect("write truncated");
    // 4. Header only (first 64 KiB).
    let header = scratch.join("headeronly.ARW");
    std::fs::write(&header, &arw[..65536]).expect("write header");
    // 5. Non-RAW bytes under a RAW name (JPEG preview renamed).
    let jpg = std::fs::read(sample.join("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg"))
        .expect("read JPG sample");
    let renamed = scratch.join("renamed.ARW");
    std::fs::write(&renamed, &jpg).expect("write renamed");

    // The extension is never sniffed (content only), so a valid RAW under a
    // wrong name would still decode; fixture 5 is non-RAW content instead.
    let cases = [
        ("empty", &empty, ErrorCode::Truncated),
        ("random", &random, ErrorCode::NotRaw),
        ("truncated", &truncated, ErrorCode::Truncated),
        ("header-only", &header, ErrorCode::Truncated),
        ("renamed", &renamed, ErrorCode::NotRaw),
    ];
    for (name, path, expected) in cases {
        let err = decode_file(path).expect_err(&format!("{name} must fail, not decode"));
        assert_eq!(err.code(), expected, "{name}: {err}");
        println!("{name}: code={:?} detail={}", err.code(), err.detail());
    }

    // The process is alive and the decoder state is clean: a valid file
    // decodes after all five failures in this same process.
    let valid = sample.join("DSCF0021.RAF");
    let decoded = decode_file(&valid).expect("valid decode after corrupt run");
    assert_eq!(decoded.meta.width, 7728);
    assert_eq!(decoded.meta.height, 5152);

    let _ = std::fs::remove_dir_all(&scratch);
}
