// SPDX-License-Identifier: GPL-3.0-or-later
//! Raster decoding: synthesized PNG/TIFF round-trips are pixel-exact,
//! synthesized JPEGs decode with the right geometry (JPEG is lossy, so
//! pixels are sanity-bounded, not exact), ICC profiles come along, camera
//! RAWs are rejected, and truncated rasters report typed errors.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::{Path, PathBuf};

use lightamer_decode::{ErrorCode, RasterPixels, decode_raster};

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
    let dir = std::env::temp_dir().join(format!(
        "b2b-raster-{name}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir
}

/// Deterministic 8-bit pattern (covers 0..=255 over any 16x16+ window).
fn pattern_u8(width: u32, height: u32, components: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity((width * height * components) as usize);
    for y in 0..height {
        for x in 0..width {
            for c in 0..components {
                out.push(
                    u8::try_from(
                        x.wrapping_mul(73)
                            .wrapping_add(y.wrapping_mul(149))
                            .wrapping_add(c.wrapping_mul(31))
                            % 256,
                    )
                    .unwrap_or_default(),
                );
            }
        }
    }
    out
}

/// Deterministic 16-bit pattern (full-range over any 16x16+ window).
fn pattern_u16(width: u32, height: u32, components: u32) -> Vec<u16> {
    let mut out = Vec::with_capacity((width * height * components) as usize);
    for y in 0..height {
        for x in 0..width {
            for c in 0..components {
                out.push(
                    u16::try_from(
                        x.wrapping_mul(733)
                            .wrapping_add(y.wrapping_mul(1499))
                            .wrapping_add(c.wrapping_mul(311))
                            .wrapping_mul(257)
                            % 65_536,
                    )
                    .unwrap_or_default(),
                );
            }
        }
    }
    out
}

/// Smooth 8-bit pattern for JPEG synthesis (gentle gradient: quality 100
/// stays within a few levels, so the lossy bound below is meaningful).
fn smooth_u8(width: u32, height: u32, components: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity((width * height * components) as usize);
    for y in 0..height {
        for x in 0..width {
            for c in 0..components {
                out.push(
                    u8::try_from(
                        x.wrapping_add(y.wrapping_mul(2))
                            .wrapping_add(c.wrapping_mul(3))
                            % 251,
                    )
                    .unwrap_or_default(),
                );
            }
        }
    }
    out
}

/// Write a PNG with the `png` encoder.
fn write_png(
    path: &Path,
    width: u32,
    height: u32,
    color: png::ColorType,
    depth: png::BitDepth,
    pixels: &[u8],
) {
    let file = std::fs::File::create(path).expect("create png");
    let mut encoder = png::Encoder::new(file, width, height);
    encoder.set_color(color);
    encoder.set_depth(depth);
    let mut writer = encoder.write_header().expect("png header");
    writer.write_image_data(pixels).expect("png pixels");
}

/// Write a gray8 TIFF with the `tiff` encoder (uncompressed).
fn write_tiff_gray8(path: &Path, width: u32, height: u32, pixels: &[u8]) {
    use tiff::encoder::colortype::Gray8;
    let file = std::fs::File::create(path).expect("create tiff");
    let mut encoder = tiff::encoder::TiffEncoder::new(file).expect("tiff encoder");
    encoder
        .write_image::<Gray8>(width, height, pixels)
        .expect("tiff pixels");
}

/// Assert a pixel-exact 8-bit round-trip.
fn assert_u8_roundtrip(path: &Path, width: u32, height: u32, components: u32, written: &[u8]) {
    let image = decode_raster(path).expect("raster decode");
    assert_eq!(image.width, width);
    assert_eq!(image.height, height);
    assert_eq!(image.components, components);
    assert_eq!(image.bit_depth, 8);
    assert_eq!(image.icc_profile, None);
    assert!(
        matches!(image.pixels, RasterPixels::U8(_)),
        "want U8 pixels, got {:?}",
        image.pixels
    );
    let RasterPixels::U8(pixels) = image.pixels else {
        return;
    };
    assert_eq!(pixels, written);
}

/// Assert a pixel-exact 16-bit round-trip.
fn assert_u16_roundtrip(path: &Path, width: u32, height: u32, components: u32, written: &[u16]) {
    let image = decode_raster(path).expect("raster decode");
    assert_eq!(image.width, width);
    assert_eq!(image.height, height);
    assert_eq!(image.components, components);
    assert_eq!(image.bit_depth, 16);
    assert!(
        matches!(image.pixels, RasterPixels::U16(_)),
        "want U16 pixels, got {:?}",
        image.pixels
    );
    let RasterPixels::U16(pixels) = image.pixels else {
        return;
    };
    assert_eq!(pixels, written);
}

/// Assert JPEG geometry plus a lossy pixel bound (never pixel-exact).
fn assert_jpeg_geometry(path: &Path, width: u32, height: u32, components: u32, written: &[u8]) {
    let image = decode_raster(path).expect("raster decode");
    assert_eq!(image.width, width);
    assert_eq!(image.height, height);
    assert_eq!(image.components, components);
    assert_eq!(image.bit_depth, 8);
    assert!(
        matches!(image.pixels, RasterPixels::U8(_)),
        "want U8 pixels, got {:?}",
        image.pixels
    );
    let RasterPixels::U8(pixels) = image.pixels else {
        return;
    };
    assert_eq!(pixels.len(), written.len());
    for (got, want) in pixels.iter().zip(written.iter()) {
        assert!(got.abs_diff(*want) < 48, "JPEG drifted too far");
    }
}

/// Encode a JPEG with `jpeg-encoder` (baseline DCT, quality 100).
fn write_jpeg(path: &Path, width: u16, height: u16, color: jpeg_encoder::ColorType, pixels: &[u8]) {
    let file = std::fs::File::create(path).expect("create jpeg");
    let encoder = jpeg_encoder::Encoder::new(file, 100);
    encoder
        .encode(pixels, width, height, color)
        .expect("jpeg encode");
}

#[test]
fn png_gray8_roundtrip_is_pixel_exact() {
    let scratch = scratch_dir("png-g8");
    let path = scratch.join("gray8.png");
    let written = pattern_u8(17, 13, 1);
    write_png(
        &path,
        17,
        13,
        png::ColorType::Grayscale,
        png::BitDepth::Eight,
        &written,
    );
    assert_u8_roundtrip(&path, 17, 13, 1, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn png_rgb8_roundtrip_is_pixel_exact() {
    let scratch = scratch_dir("png-rgb8");
    let path = scratch.join("rgb8.png");
    let written = pattern_u8(19, 11, 3);
    write_png(
        &path,
        19,
        11,
        png::ColorType::Rgb,
        png::BitDepth::Eight,
        &written,
    );
    assert_u8_roundtrip(&path, 19, 11, 3, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn png_rgba8_roundtrip_keeps_alpha_exact() {
    let scratch = scratch_dir("png-rgba8");
    let path = scratch.join("rgba8.png");
    let mut written = pattern_u8(13, 9, 4);
    // Force the alpha extremes into the pattern (every 4th sample).
    for (index, sample) in written.iter_mut().enumerate() {
        if index % 4 == 3 {
            *sample = if index % 8 == 3 { 0 } else { 255 };
        }
    }
    write_png(
        &path,
        13,
        9,
        png::ColorType::Rgba,
        png::BitDepth::Eight,
        &written,
    );
    assert_u8_roundtrip(&path, 13, 9, 4, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn png_gray16_roundtrip_is_pixel_exact() {
    let scratch = scratch_dir("png-g16");
    let path = scratch.join("gray16.png");
    let written = pattern_u16(15, 12, 1);
    let bytes: Vec<u8> = written.iter().flat_map(|v| v.to_be_bytes()).collect();
    write_png(
        &path,
        15,
        12,
        png::ColorType::Grayscale,
        png::BitDepth::Sixteen,
        &bytes,
    );
    assert_u16_roundtrip(&path, 15, 12, 1, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn png_rgb16_roundtrip_is_pixel_exact() {
    let scratch = scratch_dir("png-rgb16");
    let path = scratch.join("rgb16.png");
    let written = pattern_u16(14, 10, 3);
    let bytes: Vec<u8> = written.iter().flat_map(|v| v.to_be_bytes()).collect();
    write_png(
        &path,
        14,
        10,
        png::ColorType::Rgb,
        png::BitDepth::Sixteen,
        &bytes,
    );
    assert_u16_roundtrip(&path, 14, 10, 3, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn png_with_icc_chunk_returns_the_profile_bytes() {
    use flate2::Compression;
    use flate2::write::ZlibEncoder;
    use std::io::Write;
    let scratch = scratch_dir("png-icc");
    let path = scratch.join("icc.png");
    let profile = b"fake-icc-profile-bytes-for-roundtrip";
    let written = pattern_u8(8, 8, 3);
    let file = std::fs::File::create(&path).expect("create png");
    let mut encoder = png::Encoder::new(file, 8, 8);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().expect("png header");
    // iCCP payload: profile name + NUL + deflate(0) + zlib(profile).
    let mut deflated = Vec::new();
    ZlibEncoder::new(&mut deflated, Compression::default())
        .write_all(profile)
        .expect("deflate");
    let mut chunk = b"test-profile\0".to_vec();
    chunk.push(0);
    chunk.extend_from_slice(&deflated);
    writer
        .write_chunk(png::chunk::ChunkType(*b"iCCP"), &chunk)
        .expect("iccp chunk");
    writer.write_image_data(&written).expect("png pixels");
    drop(writer);
    let image = decode_raster(&path).expect("raster decode");
    assert_eq!(image.icc_profile.as_deref(), Some(profile.as_slice()));
    assert!(
        matches!(image.pixels, RasterPixels::U8(_)),
        "want U8 pixels, got {:?}",
        image.pixels
    );
    let RasterPixels::U8(pixels) = image.pixels else {
        return;
    };
    assert_eq!(pixels, written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn tiff_gray8_roundtrip_is_pixel_exact() {
    let scratch = scratch_dir("tiff-g8");
    let path = scratch.join("gray8.tif");
    let written = pattern_u8(17, 13, 1);
    write_tiff_gray8(&path, 17, 13, &written);
    assert_u8_roundtrip(&path, 17, 13, 1, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn tiff_rgb8_roundtrip_is_pixel_exact() {
    use tiff::encoder::colortype::RGB8;
    let scratch = scratch_dir("tiff-rgb8");
    let path = scratch.join("rgb8.tif");
    let written = pattern_u8(19, 11, 3);
    let file = std::fs::File::create(&path).expect("create tiff");
    let mut encoder = tiff::encoder::TiffEncoder::new(file).expect("tiff encoder");
    encoder
        .write_image::<RGB8>(19, 11, &written)
        .expect("tiff pixels");
    assert_u8_roundtrip(&path, 19, 11, 3, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn tiff_rgba8_roundtrip_keeps_alpha_exact() {
    use tiff::encoder::colortype::RGBA8;
    let scratch = scratch_dir("tiff-rgba8");
    let path = scratch.join("rgba8.tif");
    let mut written = pattern_u8(13, 9, 4);
    for (index, sample) in written.iter_mut().enumerate() {
        if index % 4 == 3 {
            *sample = if index % 8 == 3 { 0 } else { 255 };
        }
    }
    let file = std::fs::File::create(&path).expect("create tiff");
    let mut encoder = tiff::encoder::TiffEncoder::new(file).expect("tiff encoder");
    encoder
        .write_image::<RGBA8>(13, 9, &written)
        .expect("tiff pixels");
    assert_u8_roundtrip(&path, 13, 9, 4, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn tiff_gray16_roundtrip_is_pixel_exact() {
    use tiff::encoder::colortype::Gray16;
    let scratch = scratch_dir("tiff-g16");
    let path = scratch.join("gray16.tif");
    let written = pattern_u16(15, 12, 1);
    let file = std::fs::File::create(&path).expect("create tiff");
    let mut encoder = tiff::encoder::TiffEncoder::new(file).expect("tiff encoder");
    encoder
        .write_image::<Gray16>(15, 12, &written)
        .expect("tiff pixels");
    assert_u16_roundtrip(&path, 15, 12, 1, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn tiff_rgb16_roundtrip_is_pixel_exact() {
    use tiff::encoder::colortype::RGB16;
    let scratch = scratch_dir("tiff-rgb16");
    let path = scratch.join("rgb16.tif");
    let written = pattern_u16(14, 10, 3);
    let file = std::fs::File::create(&path).expect("create tiff");
    let mut encoder = tiff::encoder::TiffEncoder::new(file).expect("tiff encoder");
    encoder
        .write_image::<RGB16>(14, 10, &written)
        .expect("tiff pixels");
    assert_u16_roundtrip(&path, 14, 10, 3, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

/// Hand-assemble a 2x2 gray8 TIFF with an ICC profile tag (the `tiff`
/// encoder's `write_tag` cannot take byte slices, so synthesis goes raw).
fn write_tiff_with_icc(path: &Path, profile: &[u8]) {
    fn entry(tag: u16, ty: u16, count: u32, value_or_offset: u32) -> Vec<u8> {
        let mut out = Vec::with_capacity(12);
        out.extend_from_slice(&tag.to_le_bytes());
        out.extend_from_slice(&ty.to_le_bytes());
        out.extend_from_slice(&count.to_le_bytes());
        out.extend_from_slice(&value_or_offset.to_le_bytes());
        out
    }
    // Layout: header(8) + IFD(count=2 + 11 entries*12 + next=4) + pixels(4) +
    // profile. IFD starts at 8; pixel data follows the IFD.
    // (StripOffsets and IccProfile entries are built inline below with the
    // computed data positions.)
    let fixed: Vec<Vec<u8>> = vec![
        entry(256, 3, 1, 2), // Width SHORT
        entry(257, 3, 1, 2), // Height SHORT
        entry(258, 3, 1, 8), // BitsPerSample SHORT
        entry(259, 3, 1, 1), // Compression none
        entry(262, 3, 1, 1), // Photometric black-is-zero
        entry(277, 3, 1, 1), // SamplesPerPixel
        entry(278, 3, 1, 2), // RowsPerStrip
        entry(279, 4, 1, 4), // StripByteCounts
        entry(284, 3, 1, 1), // PlanarConfiguration chunky
    ];
    let entry_count = fixed.len() + 2;
    let ifd_len = 2 + entry_count * 12 + 4;
    let pixels_at = 8 + ifd_len;
    let profile_at = pixels_at + 4;
    let profile_len = u32::try_from(profile.len()).unwrap_or_default();
    let mut file = Vec::new();
    file.extend_from_slice(b"II*\0");
    file.extend_from_slice(&8_u32.to_le_bytes());
    file.extend_from_slice(&u16::try_from(entry_count).unwrap_or_default().to_le_bytes());
    for bytes in &fixed[0..5] {
        file.extend_from_slice(bytes);
    }
    file.extend_from_slice(&entry(
        273,
        4,
        1,
        u32::try_from(pixels_at).unwrap_or_default(),
    ));
    for bytes in &fixed[5..] {
        file.extend_from_slice(bytes);
    }
    file.extend_from_slice(&entry(
        34675,
        7,
        profile_len,
        u32::try_from(profile_at).unwrap_or_default(),
    ));
    file.extend_from_slice(&0_u32.to_le_bytes());
    file.extend_from_slice(&[10, 20, 30, 40]);
    file.extend_from_slice(profile);
    std::fs::write(path, &file).expect("write tiff+icc");
}

#[test]
fn tiff_with_icc_tag_returns_the_profile_bytes() {
    let scratch = scratch_dir("tiff-icc");
    let path = scratch.join("icc.tif");
    let profile = b"fake-icc-profile-bytes-for-tiff";
    write_tiff_with_icc(&path, profile);
    let image = decode_raster(&path).expect("raster decode");
    assert_eq!((image.width, image.height, image.components), (2, 2, 1));
    assert_eq!(image.bit_depth, 8);
    assert_eq!(image.icc_profile.as_deref(), Some(profile.as_slice()));
    assert!(
        matches!(image.pixels, RasterPixels::U8(_)),
        "want U8 pixels, got {:?}",
        image.pixels
    );
    let RasterPixels::U8(pixels) = image.pixels else {
        return;
    };
    assert_eq!(pixels, vec![10, 20, 30, 40]);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn jpeg_gray8_synthesis_decodes_with_right_geometry() {
    let scratch = scratch_dir("jpg-g8");
    let path = scratch.join("gray8.jpg");
    let written = smooth_u8(16, 16, 1);
    write_jpeg(&path, 16, 16, jpeg_encoder::ColorType::Luma, &written);
    assert_jpeg_geometry(&path, 16, 16, 1, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn jpeg_rgb8_synthesis_decodes_with_right_geometry() {
    let scratch = scratch_dir("jpg-rgb8");
    let path = scratch.join("rgb8.jpg");
    let written = smooth_u8(17, 13, 3);
    write_jpeg(&path, 17, 13, jpeg_encoder::ColorType::Rgb, &written);
    assert_jpeg_geometry(&path, 17, 13, 3, &written);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn jpeg_with_app2_icc_returns_the_profile_bytes() {
    let scratch = scratch_dir("jpg-icc");
    let path = scratch.join("icc.jpg");
    let profile = b"fake-icc-profile-bytes-for-jpeg";
    let written = smooth_u8(16, 16, 3);
    write_jpeg(&path, 16, 16, jpeg_encoder::ColorType::Rgb, &written);
    // Splice one APP2 ICC chunk right after SOI: FF E2 len(2+12+2+N)
    // "ICC_PROFILE\0" seq(1) total(1) data.
    let bytes = std::fs::read(&path).expect("read jpeg");
    assert_eq!(&bytes[0..2], &[0xFF, 0xD8]);
    let mut spliced = vec![0xFF, 0xE2];
    let len = u16::try_from(2 + 12 + 2 + profile.len()).unwrap_or_default();
    spliced.extend_from_slice(&len.to_be_bytes());
    spliced.extend_from_slice(b"ICC_PROFILE\0");
    spliced.extend_from_slice(&[1, 1]);
    spliced.extend_from_slice(profile);
    spliced.extend_from_slice(&bytes[2..]);
    let mut out = bytes[0..2].to_vec();
    out.extend_from_slice(&spliced);
    std::fs::write(&path, &out).expect("write jpeg+icc");
    let image = decode_raster(&path).expect("raster decode");
    assert_eq!((image.width, image.height, image.components), (16, 16, 3));
    assert_eq!(image.icc_profile.as_deref(), Some(profile.as_slice()));
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn cc0_preview_jpeg_matches_sips_dimensions() {
    // `sips -g pixelWidth -g pixelHeight` (independent): 1620x1080.
    let image =
        decode_raster(&sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg"))
            .expect("preview decode");
    assert_eq!((image.width, image.height), (1620, 1080));
    assert_eq!((image.components, image.bit_depth), (3, 8));
}

#[test]
fn cc0_preview_tiff_matches_sips_dimensions() {
    // `sips` (independent): 384x256; probe: 8-bit gray, uncompressed.
    let image =
        decode_raster(&sample_dir().join("Nikon_Z8_raw_14_bit_lossless_compression-preview2.tif"))
            .expect("preview decode");
    assert_eq!((image.width, image.height), (384, 256));
    assert_eq!((image.components, image.bit_depth), (1, 8));
}

#[test]
fn truncated_raster_reports_typed_truncated() {
    let scratch = scratch_dir("trunc");
    // PNG halved.
    let png_path = scratch.join("cut.png");
    let written = pattern_u8(32, 32, 3);
    write_png(
        &png_path,
        32,
        32,
        png::ColorType::Rgb,
        png::BitDepth::Eight,
        &written,
    );
    let bytes = std::fs::read(&png_path).expect("read png");
    std::fs::write(&png_path, &bytes[..bytes.len() / 2]).expect("cut png");
    let err = decode_raster(&png_path).expect_err("cut PNG must fail");
    assert_eq!(err.code(), ErrorCode::Truncated);
    // JPEG cut inside the headers (a mid-scan cut decodes leniently in
    // zune-jpeg, so the typed error needs a headers-deep cut).
    let jpg_path = scratch.join("cut.jpg");
    write_jpeg(&jpg_path, 32, 32, jpeg_encoder::ColorType::Rgb, &written);
    let bytes = std::fs::read(&jpg_path).expect("read jpeg");
    assert!(bytes.len() > 128);
    std::fs::write(&jpg_path, &bytes[..128]).expect("cut jpeg");
    let err = decode_raster(&jpg_path).expect_err("cut JPEG must fail");
    assert_eq!(err.code(), ErrorCode::Truncated);
    // TIFF halved.
    let tif_path = scratch.join("cut.tif");
    write_tiff_gray8(&tif_path, 32, 32, &pattern_u8(32, 32, 1));
    let bytes = std::fs::read(&tif_path).expect("read tiff");
    std::fs::write(&tif_path, &bytes[..bytes.len() / 2]).expect("cut tiff");
    let err = decode_raster(&tif_path).expect_err("cut TIFF must fail");
    assert_eq!(err.code(), ErrorCode::Truncated);
    let _ = std::fs::remove_dir_all(&scratch);
}

#[test]
fn camera_raw_never_decodes_through_raster() {
    // ARW/NEF (old-JPEG TIFFs), RAF (Fuji container), DNG (DNG markers),
    // CR3 (ISO-BMFF): every one is rejected, none decoded as a raster.
    for file in [
        "7RM5-LosslessCompressedLarge.ARW",
        "Nikon_Z8_raw_14_bit_lossless_compression.NEF",
        "DSCF0021.RAF",
        "5G4A9394-compressed-lossless.DNG",
        "IMG_4276.CR3",
    ] {
        let err =
            decode_raster(&sample_dir().join(file)).expect_err(&format!("{file} must not raster"));
        assert_eq!(err.code(), ErrorCode::UnsupportedFormat, "{file}: {err}");
    }
}

#[test]
fn missing_raster_reports_not_found() {
    let err = decode_raster(&sample_dir().join("does-not-exist.png"))
        .expect_err("missing file must fail");
    assert_eq!(err.code(), ErrorCode::NotFound);
}
