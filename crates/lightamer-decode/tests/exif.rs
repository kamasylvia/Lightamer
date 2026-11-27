// SPDX-License-Identifier: GPL-3.0-or-later
//! EXIF optics: shutter/aperture/focal/lens/capture-time/orientation against
//! the independent `mdls` values, absence without error, and corrupt inputs.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;

use lightamer_decode::{ErrorCode, decode_file, read_exif};

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
fn scratch_dir(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "b2b-exif-{name}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos()
    ))
}

#[test]
fn arw_optics_match_mdls_independent_values() {
    // `mdls` (Spotlight, independent of this crate): 0.0005 s, f/1.2, 50 mm,
    // "Sony FE 50mm F1.2", 2022-12-17 08:03:36 UTC (= 16:03:36 +08:00).
    let optics = read_exif(&sample_dir().join("7RM5-LosslessCompressedLarge.ARW")).expect("EXIF");
    assert!((optics.exposure_time.expect("shutter") - 0.0005).abs() < 1e-12);
    assert!((optics.aperture.expect("aperture") - 1.2).abs() < 1e-6);
    assert!((optics.focal_length.expect("focal") - 50.0).abs() < 1e-6);
    assert_eq!(optics.lens_model.as_deref(), Some("FE 50mm F1.2 GM"));
    assert_eq!(optics.capture_time.as_deref(), Some("2022:12:17 16:03:36"));
    assert_eq!(optics.orientation, Some(1));
    assert_eq!(optics.white_balance_kelvin, None);
    assert_eq!(optics.white_balance_tint, None);
}

#[test]
fn nef_optics_match_mdls_independent_values() {
    // `mdls`: 0.0125 s, f/8, 24 mm, "NIKKOR Z 14-24mm f/2.8 S",
    // 2023-06-02 10:52:32 UTC (= naive 18:52:32 in the system +08:00 zone;
    // the file's own OffsetTime says +02:00, which mdls does not use here).
    let optics = read_exif(&sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression.NEF"))
        .expect("EXIF");
    assert!((optics.exposure_time.expect("shutter") - 0.0125).abs() < 1e-12);
    assert!((optics.aperture.expect("aperture") - 8.0).abs() < 1e-6);
    assert!((optics.focal_length.expect("focal") - 24.0).abs() < 1e-6);
    assert_eq!(
        optics.lens_model.as_deref(),
        Some("NIKKOR Z 14-24mm f/2.8 S")
    );
    assert_eq!(optics.capture_time.as_deref(), Some("2023:06:02 18:52:32"));
    assert_eq!(optics.orientation, Some(1));
}

#[test]
fn raf_optics_come_from_embedded_preview_and_match_mdls() {
    // `mdls`: 0.00625 s, f/4, 18 mm, "XF18mmF2 R",
    // 2022-11-20 07:38:30 UTC (= 15:38:30 +08:00). Neither EXIF crate reads
    // RAF containers, so this goes through the embedded preview's APP1.
    let optics = read_exif(&sample_dir().join("DSCF0021.RAF")).expect("EXIF");
    assert!((optics.exposure_time.expect("shutter") - 0.00625).abs() < 1e-12);
    assert!((optics.aperture.expect("aperture") - 4.0).abs() < 1e-6);
    assert!((optics.focal_length.expect("focal") - 18.0).abs() < 1e-6);
    assert_eq!(optics.lens_model.as_deref(), Some("XF18mmF2 R"));
    assert_eq!(optics.capture_time.as_deref(), Some("2022:11:20 15:38:30"));
    assert_eq!(optics.orientation, Some(1));
}

#[test]
fn file_without_exif_yields_empty_optics_without_error() {
    let scratch = scratch_dir("absent");
    std::fs::create_dir_all(&scratch).expect("scratch dir");
    let plain = scratch.join("plain.png");
    let file = std::fs::File::create(&plain).expect("create png");
    let mut encoder = png::Encoder::new(file, 4, 4);
    encoder.set_color(png::ColorType::Grayscale);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().expect("png header");
    writer.write_image_data(&[128_u8; 16]).expect("png pixels");
    let optics = read_exif(&plain).expect("EXIF-less file must not error");
    assert_eq!(optics.exposure_time, None);
    assert_eq!(optics.aperture, None);
    assert_eq!(optics.focal_length, None);
    assert_eq!(optics.lens_model, None);
    assert_eq!(optics.capture_time, None);
    assert_eq!(optics.orientation, None);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn missing_file_exif_reports_not_found() {
    let err =
        read_exif(&sample_dir().join("does-not-exist.ARW")).expect_err("missing file must fail");
    assert_eq!(err.code(), ErrorCode::NotFound);
}

#[test]
fn corrupt_exif_requests_never_abort() {
    let scratch = scratch_dir("corrupt");
    std::fs::create_dir_all(&scratch).expect("scratch dir");
    let sample = sample_dir();
    let arw =
        std::fs::read(sample.join("7RM5-LosslessCompressedLarge.ARW")).expect("read ARW sample");

    let empty = scratch.join("empty.ARW");
    std::fs::write(&empty, []).expect("write empty");
    let random = scratch.join("random.ARW");
    let mut state: u64 = 0x243F_6A88_85A3_0B8D;
    let mut bytes = Vec::with_capacity(1 << 20);
    for _ in 0..(1 << 20) {
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        bytes.push((state.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 56) as u8);
    }
    std::fs::write(&random, &bytes).expect("write random");
    let truncated = scratch.join("truncated.ARW");
    std::fs::write(&truncated, &arw[..arw.len() / 2]).expect("write truncated");
    let header = scratch.join("headeronly.ARW");
    std::fs::write(&header, &arw[..65536]).expect("write header");
    let jpg = std::fs::read(sample.join("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg"))
        .expect("read JPG sample");
    let renamed = scratch.join("renamed.ARW");
    std::fs::write(&renamed, &jpg).expect("write renamed");

    // EXIF is auxiliary: corrupt metadata yields empty-or-partial optics,
    // never an abort. Every call below must return (Ok or typed Err).
    for path in [&empty, &random, &truncated, &header, &renamed] {
        let _ = read_exif(path);
    }
    // The empty file deterministically yields empty optics.
    let optics = read_exif(&empty).expect("empty EXIF must not error");
    assert_eq!(optics.exposure_time, None);

    // The process is alive: a valid read works after all five.
    let valid = read_exif(&sample.join("DSCF0021.RAF")).expect("valid EXIF after corrupt");
    assert!(valid.exposure_time.is_some());

    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn decode_file_fills_the_b2a_empty_optics_fields() {
    let decoded = decode_file(&sample_dir().join("7RM5-LosslessCompressedLarge.ARW"))
        .expect("decode with optics");
    assert!((decoded.meta.exposure_time.expect("shutter") - 0.0005).abs() < 1e-12);
    assert!((decoded.meta.aperture.expect("aperture") - 1.2).abs() < 1e-6);
    assert!((decoded.meta.focal_length.expect("focal") - 50.0).abs() < 1e-6);
    assert_eq!(decoded.meta.lens_model.as_deref(), Some("FE 50mm F1.2 GM"));
    assert_eq!(
        decoded.meta.capture_time.as_deref(),
        Some("2022:12:17 16:03:36")
    );
    assert_eq!(decoded.meta.orientation, Some(1));
}
