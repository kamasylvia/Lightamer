// SPDX-License-Identifier: GPL-3.0-or-later
//! Embedded thumbnails: JPEG extraction against independently probed offsets,
//! the uncompressed form, absence, and corrupt inputs (no abort).

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;

use lightamer_decode::{ErrorCode, Thumbnail, jpeg_dimensions, read_thumbnail};

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
        "b2b-thumb-{name}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos()
    ))
}

/// Deterministic pseudo-random bytes (xorshift64*, fixed seed; same recipe as
/// the B2-a robustness test).
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

/// Write a thumbnail-less 4x4 gray PNG (exercises the absence path).
fn write_plain_png(path: &std::path::Path) {
    let file = std::fs::File::create(path).expect("create png");
    let mut encoder = png::Encoder::new(file, 4, 4);
    encoder.set_color(png::ColorType::Grayscale);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().expect("png header");
    writer.write_image_data(&[128_u8; 16]).expect("png pixels");
}

/// Unwrap a JPEG thumbnail (fails the test with context otherwise).
fn expect_jpeg(thumb: Thumbnail, what: &str) -> Vec<u8> {
    assert!(
        matches!(thumb, Thumbnail::Jpeg { .. }),
        "{what} must be JPEG, got {thumb:?}"
    );
    match thumb {
        Thumbnail::Jpeg { bytes } => bytes,
        Thumbnail::Raw { .. } => Vec::new(),
    }
}

#[test]
fn arw_embedded_jpeg_thumbnail_matches_probed_offsets_and_decodes() {
    // Independent probe (`kamadak-exif` over the raw file): IFD1
    // JPEGInterchangeFormat/Length = 43994/9405, SOI+EOI verified.
    let thumb = read_thumbnail(&sample_dir().join("7RM5-LosslessCompressedLarge.ARW"))
        .expect("ARW thumbnail");
    let bytes = expect_jpeg(thumb, "ARW thumbnail");
    assert_eq!(bytes.len(), 9405);
    assert_eq!(&bytes[0..2], &[0xFF, 0xD8]);
    assert_eq!(jpeg_dimensions(&bytes).expect("decodable"), (160, 120));
}

#[test]
fn nef_embedded_jpeg_thumbnail_matches_probed_offsets_and_decodes() {
    // Independent probe: IFD0 JPEGInterchangeFormat/Length = 244168/10807.
    let thumb = read_thumbnail(&sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression.NEF"))
        .expect("NEF thumbnail");
    let bytes = expect_jpeg(thumb, "NEF thumbnail");
    assert_eq!(bytes.len(), 10807);
    assert_eq!(&bytes[0..2], &[0xFF, 0xD8]);
    assert_eq!(jpeg_dimensions(&bytes).expect("decodable"), (160, 120));
}

#[test]
fn raf_embedded_preview_extracts_at_documented_offsets_and_decodes() {
    // Fuji layout: big-endian preview offset/length at bytes 84/88.
    let thumb = read_thumbnail(&sample_dir().join("DSCF0021.RAF")).expect("RAF preview");
    let bytes = expect_jpeg(thumb, "RAF preview");
    assert_eq!(bytes.len(), 4_016_595);
    assert_eq!(&bytes[0..2], &[0xFF, 0xD8]);
    assert_eq!(jpeg_dimensions(&bytes).expect("decodable"), (4416, 2944));
}

#[test]
fn colorchecker_second_body_thumbnail_decodes_with_sane_size() {
    let thumb =
        read_thumbnail(&sample_dir().join("ColorChecker.ARW")).expect("ColorChecker thumbnail");
    let bytes = expect_jpeg(thumb, "ColorChecker thumbnail");
    let (width, height) = jpeg_dimensions(&bytes).expect("decodable");
    assert!(width > 0 && width <= 1024 && height > 0 && height <= 1024);
}

#[test]
fn dng_uncompressed_thumbnail_reports_pixels_not_jpeg() {
    // Independent probe: DNG IFD0 is 256x171 uncompressed RGB chunky, strip
    // at 201416, 131328 bytes — no 513/514 anywhere.
    let thumb =
        read_thumbnail(&sample_dir().join("5G4A9394-compressed-lossless.DNG")).expect("DNG thumb");
    assert!(
        matches!(thumb, Thumbnail::Raw { .. }),
        "DNG thumbnail must be raw pixels, got {thumb:?}"
    );
    let Thumbnail::Raw {
        width,
        height,
        components,
        bits_per_sample,
        pixels,
    } = thumb
    else {
        return;
    };
    assert_eq!(
        (width, height, components, bits_per_sample),
        (256, 171, 3, 8)
    );
    assert_eq!(pixels.len(), 256 * 171 * 3);
    // The pixel bytes equal the file range at the probed strip offset.
    let file = std::fs::read(sample_dir().join("5G4A9394-compressed-lossless.DNG")).expect("DNG");
    assert_eq!(&pixels[0..64], &file[201_416..201_416 + 64]);
}

#[test]
fn plain_small_tiff_is_not_its_own_thumbnail() {
    // preview2.tif is a 384x256 uncompressed gray raster whose IFD0 omits
    // NewSubfileType: structurally readable, but not a marked thumbnail.
    let err =
        read_thumbnail(&sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression-preview2.tif"))
            .expect_err("plain TIFF has no marked thumbnail");
    assert_eq!(err.code(), ErrorCode::ThumbnailUnavailable);
}

#[test]
fn file_without_thumbnail_reports_typed_unavailable() {
    let scratch = scratch_dir("absent");
    std::fs::create_dir_all(&scratch).expect("scratch dir");
    let plain = scratch.join("plain.png");
    write_plain_png(&plain);
    let err = read_thumbnail(&plain).expect_err("plain PNG has no thumbnail");
    assert_eq!(err.code(), ErrorCode::ThumbnailUnavailable);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn missing_file_thumbnail_reports_not_found() {
    let err = read_thumbnail(&sample_dir().join("does-not-exist.ARW"))
        .expect_err("missing file must fail");
    assert_eq!(err.code(), ErrorCode::NotFound);
}

#[test]
fn corrupt_thumbnail_requests_do_not_abort() {
    let scratch = scratch_dir("corrupt");
    std::fs::create_dir_all(&scratch).expect("scratch dir");
    let sample = sample_dir();
    let arw =
        std::fs::read(sample.join("7RM5-LosslessCompressedLarge.ARW")).expect("read ARW sample");

    let empty = scratch.join("empty.ARW");
    std::fs::write(&empty, []).expect("write empty");
    let random = scratch.join("random.ARW");
    std::fs::write(&random, random_bytes(1 << 20)).expect("write random");
    let truncated = scratch.join("truncated.ARW");
    std::fs::write(&truncated, &arw[..arw.len() / 2]).expect("write truncated");
    let header = scratch.join("headeronly.ARW");
    std::fs::write(&header, &arw[..65536]).expect("write header");
    let jpg = std::fs::read(sample.join("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg"))
        .expect("read JPG sample");
    let renamed = scratch.join("renamed.ARW");
    std::fs::write(&renamed, &jpg).expect("write renamed");

    // Empty input is structurally unreadable.
    let err = read_thumbnail(&empty).expect_err("empty must fail");
    assert_eq!(err.code(), ErrorCode::Truncated);
    // Random bytes are either unreadable or thumb-less; both are typed.
    let err = read_thumbnail(&random).expect_err("random bytes must not yield a thumbnail");
    assert!(
        err.code() == ErrorCode::Truncated || err.code() == ErrorCode::ThumbnailUnavailable,
        "unexpected code: {err}"
    );
    // Truncated EXIF is unreadable, thumb-less, or (the thumbnail lives at
    // the file head, so a tail truncation can leave it intact) still
    // extractable — all three outcomes are honest and typed.
    match read_thumbnail(&truncated) {
        Ok(thumb) => {
            assert!(
                matches!(thumb, Thumbnail::Jpeg { .. }),
                "unexpected truncated payload: {thumb:?}"
            );
            if let Thumbnail::Jpeg { bytes } = thumb {
                assert_eq!(bytes.len(), 9405);
            }
        }
        Err(err) => assert!(
            err.code() == ErrorCode::Truncated || err.code() == ErrorCode::ThumbnailUnavailable,
            "unexpected code: {err}"
        ),
    }
    // The 64 KiB header physically contains the whole thumbnail range, but
    // the EXIF parser reads the IFD chain eagerly and fails it as a whole
    // on the cut tail: typed truncation, still no abort.
    let err = read_thumbnail(&header).expect_err("header-only must fail typed");
    assert_eq!(err.code(), ErrorCode::Truncated);
    // EXIF-less JPEG content carries no supported thumbnail.
    let err = read_thumbnail(&renamed).expect_err("plain JPEG has no thumbnail");
    assert_eq!(err.code(), ErrorCode::ThumbnailUnavailable);

    // The process is alive: a valid thumbnail reads after all five.
    let valid = read_thumbnail(&sample.join("DSCF0021.RAF")).expect("valid thumb after corrupt");
    assert!(!valid.is_empty());

    let _ = std::fs::remove_dir_all(&scratch);
}
