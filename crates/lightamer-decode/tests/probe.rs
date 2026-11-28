// SPDX-License-Identifier: GPL-3.0-or-later
//! Metadata-only probe: fast-path equality with full decode on both Sony
//! ARW samples, the no-pixels guarantee, the probe-then-decode guard, the
//! non-ARW fallback, and the pipe-input entry's values.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::path::PathBuf;

use lightamer_decode::{
    CfaColor, CropBox, DecodedImage, Mosaic, MosaicKind, RawImage, RawMetadata, decode_file,
};
use lightamer_raster::FrameExtent;

/// CC0 sample directory (read-only).
fn sample_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME unset");
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Lightamer")
        .join("TestRAW")
}

fn probe(path: &std::path::Path) -> lightamer_decode::RawMetadata {
    let mut image = RawImage::open(path).expect("open");
    assert!(image.probe_supported(), "ARW must take the fast path");
    image.probe_metadata().expect("probe")
}

#[test]
fn probe_matches_decode_field_for_field_on_both_arw() {
    for file in ["7RM5-LosslessCompressedLarge.ARW", "ColorChecker.ARW"] {
        let path = sample_dir().join(file);
        let probed = probe(&path);
        let decoded = decode_file(&path).expect("decode");
        assert_eq!(
            probed, decoded.meta,
            "probe disagrees with decode on {file}"
        );
        println!(
            "{file}: probe == decode ({}x{}, black {:?}, white {:?})",
            probed.width, probed.height, probed.black_separate, probed.white_level
        );
    }
}

#[test]
fn fast_probe_allocates_no_pixels() {
    let path = sample_dir().join("7RM5-LosslessCompressedLarge.ARW");
    let mut image = RawImage::open(&path).expect("open");
    image.probe_metadata().expect("probe");
    assert!(!image.is_decoded(), "probe must not decode");
    assert!(image.mosaic().is_err(), "no mosaic without a decode");
    assert!(
        image.metadata().is_err(),
        "no decode-gated metadata without a decode"
    );
}

#[test]
fn probe_then_decode_is_refused() {
    let path = sample_dir().join("7RM5-LosslessCompressedLarge.ARW");
    let mut image = RawImage::open(&path).expect("open");
    image.probe_metadata().expect("probe");
    let err = image.decode().expect_err("decode after probe must fail");
    assert!(
        err.to_string().contains("already probed"),
        "unexpected refusal: {err}"
    );
}

#[test]
fn second_probe_is_refused() {
    let path = sample_dir().join("7RM5-LosslessCompressedLarge.ARW");
    let mut image = RawImage::open(&path).expect("open");
    image.probe_metadata().expect("first probe");
    let err = image.probe_metadata().expect_err("second probe must fail");
    assert!(
        err.to_string().contains("already probed"),
        "unexpected refusal: {err}"
    );
}

#[test]
fn probe_after_decode_is_refused() {
    let path = sample_dir().join("7RM5-LosslessCompressedLarge.ARW");
    let mut image = RawImage::open(&path).expect("open");
    image.decode().expect("decode");
    let err = image
        .probe_metadata()
        .expect_err("probe after decode must fail");
    assert!(
        err.to_string().contains("already decoded"),
        "unexpected refusal: {err}"
    );
}

#[test]
fn non_arw_probe_falls_back_to_decode() {
    // RAF is not an ARW shape: the predicate says no, the probe decodes.
    let path = sample_dir().join("DSCF0021.RAF");
    let mut image = RawImage::open(&path).expect("open");
    assert!(!image.probe_supported(), "RAF must miss the fast path");
    let probed = image.probe_metadata().expect("fallback probe");
    assert!(image.is_decoded(), "fallback decodes pixels");
    let decoded = decode_file(&path).expect("decode");
    assert_eq!(probed, decoded.meta, "fallback disagrees with decode");
}

#[test]
fn supported_cameras_report_no_missing_sample() {
    for file in ["7RM5-LosslessCompressedLarge.ARW", "ColorChecker.ARW"] {
        let meta = probe(&sample_dir().join(file));
        assert!(
            !meta.camera_missing_sample,
            "{file}: supported camera must not flag a missing sample"
        );
    }
}

fn whole_extent(decoded: &DecodedImage) -> FrameExtent {
    FrameExtent::new(0, 0, decoded.meta.width, decoded.meta.height)
}

#[test]
fn pipe_input_matches_metadata_on_both_arw() {
    use lightamer_iop_traits::{CfaColor as FactsColor, CfaPattern};

    for (file, wb) in [
        (
            "7RM5-LosslessCompressedLarge.ARW",
            [2536.0, 1024.0, 1778.0, 0.0],
        ),
        ("ColorChecker.ARW", [2528.0, 1024.0, 1736.0, 0.0]),
    ] {
        let decoded = decode_file(&sample_dir().join(file)).expect("decode");
        let (frame, image) = decoded
            .pipe_input(whole_extent(&decoded))
            .expect("pipe input");
        assert_eq!((image.width, image.height), (9568, 6376));
        assert!(image.is_raw(), "{file}: must read as RAW");
        assert_eq!(image.format, lightamer_iop_traits::PixelFormat::MonoF32);
        assert_eq!(image.input_space, lightamer_iop_traits::ColorSpace::Raw);
        assert_eq!(frame.format(), lightamer_raster::PixelFormat::MonoF32);
        assert_eq!(frame.extent(), whole_extent(&decoded));
        let raw = image.raw.expect("facts present");
        assert_eq!(raw.black, [512; 4], "{file}: black");
        assert_eq!(raw.white, 15360, "{file}: white");
        assert_eq!(raw.wb, wb, "{file}: wb");
        assert_eq!(raw.xyz_to_cam_d65, decoded.meta.color_matrix_xyz_to_cam);
        assert_eq!(raw.cam_to_xyz_d65, decoded.meta.color_matrix_cam_to_xyz);
        assert_eq!(
            raw.cfa,
            CfaPattern::Bayer([
                FactsColor::Red,
                FactsColor::Green,
                FactsColor::Green,
                FactsColor::Blue
            ]),
            "{file}: CFA"
        );
        assert_eq!((raw.crop_x, raw.crop_y), (0, 0), "{file}: crop");
        assert_eq!((raw.p_width, raw.p_height), (9568, 6376), "{file}: p dims");
        assert_eq!(raw.linear_response_limit, 1.0);
        assert!(!raw.hdr && !raw.four_bayer && !raw.s_raw && !raw.monochrome);
        assert!(!raw.monochrome_bayer && !raw.camera_missing_sample);
        assert!(raw.load_ok);
        // Pixels: the f32 frame is the u16 mosaic cast exactly.
        assert!(
            matches!(decoded.mosaic, Mosaic::U16(_)),
            "{file}: A7R5-family mosaics are u16"
        );
        if let Mosaic::U16(samples) = &decoded.mosaic {
            assert_eq!(frame.as_slice().len(), samples.len());
            for (got, want) in frame.as_slice().iter().zip(samples.iter()) {
                assert_eq!(*got, f32::from(*want));
            }
            println!(
                "{file}: pipe input matches metadata, {} lanes exact",
                samples.len()
            );
        }
    }
}

#[test]
fn pipe_input_region_matches_the_whole_crop() {
    let decoded =
        decode_file(&sample_dir().join("7RM5-LosslessCompressedLarge.ARW")).expect("decode");
    let (whole, _) = decoded.pipe_input(whole_extent(&decoded)).expect("whole");
    let region = FrameExtent::new(100, 200, 300, 40);
    let (piece, facts) = decoded.pipe_input(region).expect("region");
    assert_eq!(piece.extent(), region);
    assert_eq!((facts.width, facts.height), (9568, 6376));
    let view = whole.view(region).expect("crop");
    for row in 0..region.height {
        assert_eq!(
            piece.row(row).expect("piece row"),
            view.row(row).expect("whole row"),
            "row {row} disagrees"
        );
    }
    let outside = FrameExtent::new(9500, 6300, 100, 100);
    assert!(
        decoded.pipe_input(outside).is_err(),
        "overhang must fail typed"
    );
}

/// Minimal synthetic metadata: a 2x2-Bayer float capture, no fixture needed.
fn fake_meta(width: u32, height: u32) -> RawMetadata {
    RawMetadata {
        decoder: String::new(),
        make: String::new(),
        model: String::new(),
        canonical_make: String::new(),
        canonical_model: String::new(),
        mode: String::new(),
        width,
        height,
        uncropped_width: width,
        uncropped_height: height,
        crop: CropBox {
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
        },
        mosaic_kind: MosaicKind::F32,
        pitch_elems: 0,
        cpp: 1,
        bpp: 4,
        is_cfa: true,
        is_xtrans: false,
        cfa_w: 2,
        cfa_h: 2,
        cfa_pattern: vec![
            CfaColor::Red,
            CfaColor::Green,
            CfaColor::Green,
            CfaColor::Blue,
        ],
        cfa_dcraw_filter: 0x9494_9494,
        black_level: 0,
        black_separate: None,
        white_level: None,
        white_balance: None,
        white_balance_kelvin: None,
        white_balance_tint: None,
        color_matrix_xyz_to_cam: None,
        color_matrix_cam_to_xyz: None,
        iso: None,
        exposure_time: None,
        aperture: None,
        focal_length: None,
        lens_model: None,
        capture_time: None,
        orientation: None,
        subsampling: (1, 1),
        pixel_aspect_ratio: 1.0,
        mosaic_bytes: 0,
        camera_missing_sample: false,
    }
}

#[test]
fn pipe_input_copies_f32_mosaics_verbatim() {
    let samples: Vec<f32> = (0..12u16).map(|i| f32::from(i) + 0.5).collect();
    let decoded = DecodedImage {
        meta: fake_meta(4, 3),
        mosaic: Mosaic::F32(samples.clone()),
    };
    let (frame, image) = decoded
        .pipe_input(FrameExtent::new(0, 0, 4, 3))
        .expect("f32 converts");
    assert_eq!(frame.as_slice(), samples.as_slice());
    assert!(image.raw.expect("facts").hdr);
    let (piece, _) = decoded
        .pipe_input(FrameExtent::new(1, 1, 2, 2))
        .expect("f32 region");
    assert_eq!(piece.as_slice(), &[5.5f32, 6.5, 9.5, 10.5]);
}

#[test]
fn pipe_image_refuses_non_cfa_and_multi_component() {
    let mut meta = fake_meta(4, 4);
    meta.is_cfa = false;
    assert_eq!(
        lightamer_decode::pipe::pipe_image(&meta)
            .expect_err("non-CFA must fail")
            .code(),
        lightamer_decode::ErrorCode::UnsupportedFormat
    );
    let mut meta = fake_meta(4, 4);
    meta.cpp = 2;
    assert_eq!(
        lightamer_decode::pipe::pipe_image(&meta)
            .expect_err("cpp=2 must fail")
            .code(),
        lightamer_decode::ErrorCode::UnsupportedFormat
    );
}
