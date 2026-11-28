// SPDX-License-Identifier: GPL-3.0-or-later
//! Decoded-RAW to pipe input: a cropped mosaic plus its facts becomes the
//! single-channel float frame and [`ImageInfo`] the pipe renders from.
//!
//! The field mapping mirrors `dt_imageio_open_rawspeed`
//! (`src/imageio/imageio_rawspeed.cc @ release-5.7.0`); each fill cites its
//! upstream line. Anything upstream derives at use time (temperature's WB
//! normalization, the colorspace module's matrix pick) stays at use time:
//! this entry only transcribes load-time facts.

use lightamer_iop_traits::CfaColor as FactsColor;
use lightamer_iop_traits::{
    CfaPattern, ColorSpace, ImageInfo, PixelFormat as WireFormat, RawFacts,
};
use lightamer_raster::{Frame, FrameExtent, PixelFormat as RasterFormat};

use crate::error::{DecodeError, ErrorCode};
use crate::image::{CfaColor, DecodedImage, Mosaic, MosaicKind, RawMetadata};

// Dcraw filter words darktable treats as four-color Bayer
// (`FILTERS_ARE_4BAYER`, `src/imageio/imageio_common.h:32-40`).
const FOUR_BAYER_FILTERS: [u32; 8] = [
    0xb4b4_b4b4,
    0x4b4b_4b4b,
    0x1e1e_1e1e,
    0xe1e1_e1e1,
    0x6363_6363,
    0x3636_3636,
    0x9c9c_9c9c,
    0xc9c9_c9c9,
];

// Upstream's default white when rawspeed reports none
// (`imageio_rawspeed.cc:220`, `value_or((1U << 16) - 1)`).
const DEFAULT_WHITE: i32 = 65535;

// Float-bits magic upstream rewrites to a unit white on the HDR path
// (`imageio_rawspeed.cc:287`: `whitePoint == 0x3F800000`).
const UNIT_WHITE_BITS: u32 = 0x3F80_0000;

// Upstream's default linearity ceiling (`dt_image_init`,
// `src/common/image.c:2238`). The EXIF override (`exif.cc:925`,
// `LinearResponseLimit`) is unread: no consumer in this wave, and Sony ARW
// carries no such tag.
const DEFAULT_LINEAR_RESPONSE_LIMIT: f32 = 1.0;

// Per-channel black: the reported 2x2 when present, else the scalar on all
// four (upstream `imageio_rawspeed.cc:219-245` always has the 2x2 — it
// forces `calculateBlackAreas()` — while this crate passes rawspeed's
// answer through verbatim, so the scalar fallback covers files without
// separate levels). Negative inputs are rawspeed's unset sentinel and
// clamp to zero; upstream never stores them (it forces the areas first).
fn fill_black(black_level: i32, separate: Option<[i32; 4]>) -> [u32; 4] {
    separate.map_or_else(
        || {
            let level = u32::try_from(black_level).unwrap_or(0);
            [level; 4]
        },
        |levels| levels.map(|level| u32::try_from(level).unwrap_or(0)),
    )
}

// White level, stored verbatim (`imageio_rawspeed.cc:220`): for HDR
// captures the bits are float bits, and the legacy unit-white magic
// rewrites to 1 (`imageio_rawspeed.cc:287-288`).
fn fill_white(is_hdr: bool, white: Option<i32>) -> u32 {
    let level = white.unwrap_or(DEFAULT_WHITE).cast_unsigned();
    if is_hdr && level == UNIT_WHITE_BITS {
        1
    } else {
        level
    }
}

// Whether the dcraw filter word marks a four-color Bayer sensor
// (`FILTERS_ARE_4BAYER`, `src/imageio/imageio_common.h:32-40`).
fn is_four_bayer(filter: u32) -> bool {
    FOUR_BAYER_FILTERS.contains(&filter)
}

// One CFA cell across the crate boundary (the two enums match one to one).
fn convert_cell(cell: CfaColor) -> FactsColor {
    match cell {
        CfaColor::Red => FactsColor::Red,
        CfaColor::Green => FactsColor::Green,
        CfaColor::Blue => FactsColor::Blue,
        CfaColor::Cyan => FactsColor::Cyan,
        CfaColor::Magenta => FactsColor::Magenta,
        CfaColor::Yellow => FactsColor::Yellow,
        CfaColor::White => FactsColor::White,
        CfaColor::FujiGreen => FactsColor::FujiGreen,
        CfaColor::Unknown => FactsColor::Unknown,
    }
}

// CFA layout from the decoded pattern (Bayer 2x2 / X-Trans 6x6; upstream
// reads `r->cfa` plus the `filters == 9u` X-Trans arm,
// `imageio_rawspeed.cc:354-380`). Exotic CFA sizes are `UnsupportedFormat`
// (unrepresentable here); short patterns are `Internal` (incoherent input).
fn fill_cfa(
    is_xtrans: bool,
    width: u32,
    height: u32,
    pattern: &[CfaColor],
) -> Result<CfaPattern, DecodeError> {
    if is_xtrans {
        if width != 6 || height != 6 || pattern.len() < 36 {
            return Err(DecodeError::new(
                ErrorCode::Internal,
                "x-trans pattern is short",
            ));
        }
        let mut cells = [FactsColor::Unknown; 36];
        for (slot, cell) in cells.iter_mut().zip(pattern.iter()) {
            *slot = convert_cell(*cell);
        }
        Ok(CfaPattern::XTrans(cells))
    } else if width == 2 && height == 2 && pattern.len() >= 4 {
        let mut cells = [FactsColor::Unknown; 4];
        for (slot, cell) in cells.iter_mut().zip(pattern.iter()) {
            *slot = convert_cell(*cell);
        }
        Ok(CfaPattern::Bayer(cells))
    } else {
        Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            format!("unsupported CFA size {width}x{height}"),
        ))
    }
}

// Sensor facts for one decoded capture, transcribed per the upstream loader.
// See the module docs for what stays at use time.
fn fill_facts(meta: &RawMetadata, is_hdr: bool) -> Result<RawFacts, DecodeError> {
    Ok(RawFacts {
        black: fill_black(meta.black_level, meta.black_separate),
        white: fill_white(is_hdr, meta.white_level),
        // Verbatim, or all zero when absent (`imageio_rawspeed.cc:256-264`).
        // The values are NOT normalized here (A7R5 reads 2536/1024/1778/0):
        // upstream normalizes green at use in temperature, never at load.
        wb: meta.white_balance.unwrap_or([0.0; 4]),
        xyz_to_cam_d65: meta.color_matrix_xyz_to_cam,
        cam_to_xyz_d65: meta.color_matrix_cam_to_xyz,
        cfa: fill_cfa(meta.is_xtrans, meta.cfa_w, meta.cfa_h, &meta.cfa_pattern)?,
        crop_x: i32::try_from(meta.crop.left)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "crop offset exceeds i32"))?,
        crop_y: i32::try_from(meta.crop.top)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "crop offset exceeds i32"))?,
        p_width: i32::try_from(meta.width)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "width exceeds i32"))?,
        p_height: i32::try_from(meta.height)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "height exceeds i32"))?,
        linear_response_limit: DEFAULT_LINEAR_RESPONSE_LIMIT,
        hdr: is_hdr,
        four_bayer: is_four_bayer(meta.cfa_dcraw_filter),
        // Non-CFA captures never reach here (refused below): upstream
        // expands them to RGB floats (`_sraw`, `imageio_rawspeed.cc:495`),
        // which a mono entry cannot represent.
        s_raw: false,
        monochrome: false,
        // Set only by demosaic at runtime (`demosaic.c:1588`), never by any
        // loader: always false at fill time.
        monochrome_bayer: false,
        // The decode succeeded; upstream treats OK and CACHE_FULL alike as
        // "loaded" (`temperature.c:209` fails only on other statuses), and
        // the cache-full half has no analog here.
        load_ok: true,
        camera_missing_sample: meta.camera_missing_sample,
    })
}

/// Pipe facts for decoded metadata: size, RAW input space, mono format,
/// and the transcribed sensor facts. Needs no pixels, so probes answer
/// from it without decoding.
///
/// # Errors
///
/// Returns [`ErrorCode::UnsupportedFormat`] for captures this mono entry
/// cannot represent (non-CFA, multi-component, exotic CFA).
pub fn pipe_image(meta: &RawMetadata) -> Result<ImageInfo, DecodeError> {
    if !meta.is_cfa {
        return Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            "non-CFA captures expand to RGB upstream; no mono form",
        ));
    }
    if meta.cpp != 1 {
        return Err(DecodeError::new(
            ErrorCode::UnsupportedFormat,
            format!("{} components per pixel; want 1", meta.cpp),
        ));
    }
    let is_hdr = meta.mosaic_kind == MosaicKind::F32;
    let facts = fill_facts(meta, is_hdr)?;
    Ok(ImageInfo::new(meta.width, meta.height, ColorSpace::Raw)
        .with_format(WireFormat::MonoF32)
        .with_raw(facts))
}

impl DecodedImage {
    /// Pipe input for `region` (absolute cropped-frame coordinates): the
    /// region as a single-channel float frame plus the capture's full facts.
    ///
    /// `u16` samples cast exactly (`f32` holds every `u16`); `f32` mosaics
    /// copy verbatim. The facts describe the whole capture even for a
    /// sub-region, matching the engine's default region reader.
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::UnsupportedFormat`] for captures this mono
    /// entry cannot represent (non-CFA, multi-component, exotic CFA) and
    /// [`ErrorCode::Internal`] for out-of-bounds regions or incoherent
    /// planes.
    pub fn pipe_input(&self, region: FrameExtent) -> Result<(Frame, ImageInfo), DecodeError> {
        let image = pipe_image(&self.meta)?;
        let full = FrameExtent::new(0, 0, self.meta.width, self.meta.height);
        if !full.contains(region) {
            return Err(DecodeError::new(
                ErrorCode::Internal,
                format!("region {region:?} leaves the {full:?} frame"),
            ));
        }
        let stride = usize::try_from(self.meta.width)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "width exceeds usize"))?;
        let area = u64::from(self.meta.width).saturating_mul(u64::from(self.meta.height));
        let want = usize::try_from(area).unwrap_or(usize::MAX);
        if self.mosaic.len() != want {
            return Err(DecodeError::new(
                ErrorCode::Internal,
                "mosaic length disagrees with its dimensions",
            ));
        }
        // Bounds hold from here: `region` lies inside `full`, so every
        // coordinate below is non-negative and every take stays in range.
        let x = usize::try_from(region.x)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "region x exceeds usize"))?;
        let y = usize::try_from(region.y)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "region y exceeds usize"))?;
        let width = usize::try_from(region.width)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "region width exceeds usize"))?;
        let height = usize::try_from(region.height)
            .map_err(|_| DecodeError::new(ErrorCode::Internal, "region height exceeds usize"))?;
        let mut plane = Vec::with_capacity(width.saturating_mul(height));
        // A zero stride (empty frame) skips the loop: `chunks_exact(0)`
        // would panic, and the region is empty anyway by the contains check.
        if stride != 0 {
            match &self.mosaic {
                Mosaic::U16(samples) => {
                    for row in samples.chunks_exact(stride).skip(y).take(height) {
                        plane.extend(row.iter().skip(x).take(width).map(|s| f32::from(*s)));
                    }
                }
                Mosaic::F32(samples) => {
                    for row in samples.chunks_exact(stride).skip(y).take(height) {
                        plane.extend(row.iter().skip(x).take(width).copied());
                    }
                }
            }
        }
        let frame = Frame::from_parts(plane, region, RasterFormat::MonoF32).map_err(|err| {
            DecodeError::new(ErrorCode::Internal, format!("pipe frame rejected: {err}"))
        })?;
        Ok((frame, image))
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{CfaPattern, fill_black, fill_cfa, fill_white, is_four_bayer};
    use crate::image::CfaColor;

    #[test]
    fn four_bayer_words_match_upstream() {
        for word in [
            0xb4b4_b4b4,
            0x4b4b_4b4b,
            0x1e1e_1e1e,
            0xe1e1_e1e1,
            0x6363_6363,
            0x3636_3636,
            0x9c9c_9c9c,
            0xc9c9_c9c9,
        ] {
            assert!(is_four_bayer(word), "word {word:#x} should mark 4-bayer");
        }
        assert!(
            !is_four_bayer(0x9494_9494),
            "A7R5 RGGB must not mark 4-bayer"
        );
        assert!(!is_four_bayer(9), "X-Trans must not mark 4-bayer");
        assert!(!is_four_bayer(0), "empty filters must not mark 4-bayer");
    }

    #[test]
    fn black_prefers_separate_and_clamps_unset() {
        assert_eq!(fill_black(512, Some([1, 2, 3, 4])), [1, 2, 3, 4]);
        assert_eq!(fill_black(512, None), [512; 4]);
        assert_eq!(fill_black(-1, None), [0; 4]);
        assert_eq!(fill_black(-1, Some([5, -1, 7, 8])), [5, 0, 7, 8]);
    }

    #[test]
    fn white_defaults_and_rewrites_the_hdr_magic() {
        assert_eq!(fill_white(false, Some(15360)), 15360);
        assert_eq!(fill_white(false, None), 65535);
        assert_eq!(fill_white(true, Some(0x3F80_0000)), 1);
        assert_eq!(fill_white(false, Some(0x3F80_0000)), 0x3F80_0000);
    }

    #[test]
    fn cfa_maps_bayer_and_xtrans_and_refuses_exotic() {
        let bayer = fill_cfa(
            false,
            2,
            2,
            &[
                CfaColor::Red,
                CfaColor::Green,
                CfaColor::Green,
                CfaColor::Blue,
            ],
        )
        .expect("bayer maps");
        assert!(matches!(bayer, CfaPattern::Bayer(_)));
        assert!(fill_cfa(false, 4, 4, &[CfaColor::Green; 16]).is_err());
        assert!(fill_cfa(true, 6, 6, &[CfaColor::Green; 35]).is_err());
        let full = fill_cfa(true, 6, 6, &[CfaColor::Green; 36]).expect("xtrans maps");
        assert!(matches!(full, CfaPattern::XTrans(_)));
    }
}
