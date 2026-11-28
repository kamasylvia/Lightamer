// SPDX-License-Identifier: GPL-3.0-or-later
//! Decoded-image facts a module's commit may read.

use std::hash::{Hash, Hasher};

use super::{ColorSpace, PixelFormat};

/// What `commit` knows about the image: decoded full-frame size, the camera
/// input colorspace, the buffer format the pipe actually holds, and — for
/// RAW captures — the sensor facts RAW modules transcribe from `dt_image_t`
/// (`src/common/image.h` in `refs/dt-master`).
///
/// Stays [`Copy`]: string facts (camera make/model, file name) are deferred
/// to a later wave, when the fill path from decode lands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ImageInfo {
    /// Decoded full-frame width in pixels.
    pub width: u32,
    /// Decoded full-frame height in pixels.
    pub height: u32,
    /// Colorspace of the camera input feeding the pipe.
    pub input_space: ColorSpace,
    /// Buffer format of the frames this render holds. The probe reports it
    /// alongside the extent so sizing never assumes RGBA.
    pub format: PixelFormat,
    /// Sensor facts for RAW captures; [`None`] for anything else.
    pub raw: Option<RawFacts>,
}

impl ImageInfo {
    /// Builds image facts for a non-RAW RGBA render.
    #[must_use]
    pub const fn new(width: u32, height: u32, input_space: ColorSpace) -> Self {
        Self {
            width,
            height,
            input_space,
            format: PixelFormat::RgbaF32Premul,
            raw: None,
        }
    }

    /// Sets the buffer format these facts describe.
    #[must_use]
    pub const fn with_format(self, format: PixelFormat) -> Self {
        Self {
            width: self.width,
            height: self.height,
            input_space: self.input_space,
            format,
            raw: self.raw,
        }
    }

    /// Attaches RAW sensor facts, marking this a RAW capture.
    #[must_use]
    pub const fn with_raw(self, raw: RawFacts) -> Self {
        Self {
            width: self.width,
            height: self.height,
            input_space: self.input_space,
            format: self.format,
            raw: Some(raw),
        }
    }

    /// Whether this is a RAW (mosaic) capture: exactly when sensor facts
    /// are present. The engine sorts on this.
    #[must_use]
    pub const fn is_raw(self) -> bool {
        self.raw.is_some()
    }
}

/// One CFA cell color, mirroring `lightamer_decode::CfaColor` one to one so
/// the fill loses nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CfaColor {
    /// Red.
    Red,
    /// Green.
    Green,
    /// Blue.
    Blue,
    /// Cyan.
    Cyan,
    /// Magenta.
    Magenta,
    /// Yellow.
    Yellow,
    /// White.
    White,
    /// Fuji green.
    FujiGreen,
    /// Anything else.
    Unknown,
}

/// CFA layout: none, 2x2 Bayer, or 6x6 X-Trans. Cells are row-major.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CfaPattern {
    /// No CFA (monochrome or already demosaiced).
    None,
    /// 2x2 Bayer, row-major.
    Bayer([CfaColor; 4]),
    /// 6x6 X-Trans, row-major.
    XTrans([CfaColor; 36]),
}

/// Sensor facts a RAW capture carries into `commit`: the `dt_image_t` fields
/// (`src/common/image.h`) the raw-head modules read, with upstream's flag
/// bits decoded into named booleans.
///
/// Floats compare and hash by bits (see the manual impls below): facts that
/// differ re-key the pipe cache, facts that repeat hit it.
#[expect(clippy::struct_excessive_bools)]
// Seven named facts mirror seven upstream flag reads; a bitfield would hide them.
#[derive(Debug, Clone, Copy)]
pub struct RawFacts {
    /// Per-channel black levels, row-major 2x2 (`raw_black_level_separate`;
    /// `u32` holds darktable's `u16` values and the decode `i32`s).
    pub black: [u32; 4],
    /// White level (`raw_white_point`); HDR captures store float bits here.
    pub white: u32,
    /// As-shot white-balance multipliers (`wb_coeffs`): R/G/B/G2. Only the
    /// first three are valid unless [`RawFacts::four_bayer`] is set.
    pub wb: [f32; 4],
    /// XYZ(D65)-to-camera matrix, verbatim rawspeed, row-major; [`None`]
    /// when the file carries none.
    pub xyz_to_cam_d65: Option<[f32; 9]>,
    /// Camera-to-XYZ(D65) matrix, inverted in `f64`; [`None`] when absent
    /// or singular.
    pub cam_to_xyz_d65: Option<[f32; 9]>,
    /// CFA layout.
    pub cfa: CfaPattern,
    /// Left crop (`crop_x`).
    pub crop_x: i32,
    /// Top crop (`crop_y`).
    pub crop_y: i32,
    /// Full width before crop (`p_width`).
    pub p_width: i32,
    /// Full height before crop (`p_height`).
    pub p_height: i32,
    /// Sensor linearity ceiling (`linear_response_limit`).
    pub linear_response_limit: f32,
    /// Float-normalized HDR capture (`DT_IMAGE_HDR`): white holds float
    /// bits and levels normalize by it (rawprepare).
    pub hdr: bool,
    /// Four-color Bayer (`DT_IMAGE_4BAYER`): all four `wb` entries valid
    /// (temperature).
    pub four_bayer: bool,
    /// Small-RAW container (`DT_IMAGE_S_RAW`): with `monochrome` marks a
    /// supported monochrome RAW (hotpixels).
    pub s_raw: bool,
    /// Monochrome capture (`DT_IMAGE_MONOCHROME`): with `s_raw` marks a
    /// supported monochrome RAW (hotpixels).
    pub monochrome: bool,
    /// Bayer-mono sensor (`DT_IMAGE_MONOCHROME_BAYER`, hotpixels).
    pub monochrome_bayer: bool,
    /// The load succeeded (`DT_IMAGEIO_OK` or `DT_IMAGEIO_CACHE_FULL`):
    /// white-balance complaints apply (temperature).
    pub load_ok: bool,
    /// No sample for this camera yet (`camera_missing_sample`, temperature).
    pub camera_missing_sample: bool,
}

/// Bitwise equality over float arrays: equal bits compare equal (even NaN),
/// so facts round-trip through the cache key honestly.
fn floats_eq<const N: usize>(a: &[f32; N], b: &[f32; N]) -> bool {
    a.iter()
        .zip(b.iter())
        .all(|(x, y)| x.to_bits() == y.to_bits())
}

fn opt_floats_eq<const N: usize>(a: Option<&[f32; N]>, b: Option<&[f32; N]>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(x), Some(y)) => floats_eq(x, y),
        (None, Some(_)) | (Some(_), None) => false,
    }
}
fn hash_floats<H: Hasher, const N: usize>(values: &[f32; N], state: &mut H) {
    for v in values {
        state.write_u32(v.to_bits());
    }
}

fn hash_opt_floats<H: Hasher, const N: usize>(values: Option<&[f32; N]>, state: &mut H) {
    match values {
        None => state.write_u8(0),
        Some(v) => {
            state.write_u8(1);
            hash_floats(v, state);
        }
    }
}
impl PartialEq for RawFacts {
    fn eq(&self, other: &Self) -> bool {
        self.black == other.black
            && self.white == other.white
            && floats_eq(&self.wb, &other.wb)
            && opt_floats_eq(self.xyz_to_cam_d65.as_ref(), other.xyz_to_cam_d65.as_ref())
            && opt_floats_eq(self.cam_to_xyz_d65.as_ref(), other.cam_to_xyz_d65.as_ref())
            && self.cfa == other.cfa
            && self.crop_x == other.crop_x
            && self.crop_y == other.crop_y
            && self.p_width == other.p_width
            && self.p_height == other.p_height
            && self.linear_response_limit.to_bits() == other.linear_response_limit.to_bits()
            && self.hdr == other.hdr
            && self.four_bayer == other.four_bayer
            && self.s_raw == other.s_raw
            && self.monochrome == other.monochrome
            && self.monochrome_bayer == other.monochrome_bayer
            && self.load_ok == other.load_ok
            && self.camera_missing_sample == other.camera_missing_sample
    }
}

impl Eq for RawFacts {}

impl Hash for RawFacts {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.black.hash(state);
        self.white.hash(state);
        hash_floats(&self.wb, state);
        hash_opt_floats(self.xyz_to_cam_d65.as_ref(), state);
        hash_opt_floats(self.cam_to_xyz_d65.as_ref(), state);
        self.cfa.hash(state);
        self.crop_x.hash(state);
        self.crop_y.hash(state);
        self.p_width.hash(state);
        self.p_height.hash(state);
        state.write_u32(self.linear_response_limit.to_bits());
        self.hdr.hash(state);
        self.four_bayer.hash(state);
        self.s_raw.hash(state);
        self.monochrome.hash(state);
        self.monochrome_bayer.hash(state);
        self.load_ok.hash(state);
        self.camera_missing_sample.hash(state);
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{CfaColor, CfaPattern, ColorSpace, ImageInfo, PixelFormat, RawFacts};

    #[test]
    fn carries_decoded_size_and_input_space() {
        let info = ImageInfo::new(9568, 6376, ColorSpace::Raw);
        assert_eq!((info.width, info.height), (9568, 6376));
        assert_eq!(info.input_space, ColorSpace::Raw);
    }

    fn sample_raw() -> RawFacts {
        RawFacts {
            black: [512, 512, 512, 512],
            white: 15360,
            wb: [2.0, 1.0, 1.5, 1.0],
            xyz_to_cam_d65: None,
            cam_to_xyz_d65: None,
            cfa: CfaPattern::Bayer([
                CfaColor::Red,
                CfaColor::Green,
                CfaColor::Green,
                CfaColor::Blue,
            ]),
            crop_x: 0,
            crop_y: 0,
            p_width: 9568,
            p_height: 6376,
            linear_response_limit: 1.0,
            hdr: false,
            four_bayer: false,
            s_raw: false,
            monochrome: false,
            monochrome_bayer: false,
            load_ok: true,
            camera_missing_sample: false,
        }
    }

    #[test]
    fn new_defaults_to_rgba_and_non_raw() {
        let info = ImageInfo::new(64, 48, ColorSpace::Rgb);
        assert_eq!(info.format, PixelFormat::RgbaF32Premul);
        assert!(info.raw.is_none());
        assert!(!info.is_raw());
    }

    #[test]
    fn builders_attach_format_and_facts() {
        let info = ImageInfo::new(9568, 6376, ColorSpace::Raw)
            .with_format(PixelFormat::MonoF32)
            .with_raw(sample_raw());
        assert_eq!(info.format, PixelFormat::MonoF32);
        assert!(info.is_raw());
        assert_eq!(info.raw, Some(sample_raw()));
    }

    #[test]
    fn raw_facts_compare_floats_bitwise() {
        let base = sample_raw();
        assert_eq!(base, sample_raw());
        let mut neg_zero = sample_raw();
        neg_zero.wb[1] = -0.0;
        assert_ne!(base, neg_zero);
        let mut nan_a = sample_raw();
        let mut nan_b = sample_raw();
        nan_a.wb[0] = f32::from_bits(0x7fc0_0001);
        nan_b.wb[0] = f32::from_bits(0x7fc0_0001);
        assert_eq!(nan_a, nan_b);
        nan_b.wb[0] = f32::from_bits(0x7fc0_0002);
        assert_ne!(nan_a, nan_b);
        let mut matrix = sample_raw();
        matrix.cam_to_xyz_d65 = Some([0.0; 9]);
        assert_ne!(base, matrix);
    }

    #[test]
    fn raw_facts_hash_floats_bitwise() {
        use std::collections::hash_map::DefaultHasher;

        fn hash_of(facts: &RawFacts) -> u64 {
            let mut state = DefaultHasher::new();
            std::hash::Hash::hash(facts, &mut state);
            std::hash::Hasher::finish(&state)
        }

        let base = sample_raw();
        assert_eq!(hash_of(&base), hash_of(&sample_raw()));
        let mut neg_zero = sample_raw();
        neg_zero.wb[1] = -0.0;
        assert_ne!(hash_of(&base), hash_of(&neg_zero));
        let mut nan_a = sample_raw();
        let mut nan_b = sample_raw();
        nan_a.wb[0] = f32::from_bits(0x7fc0_0001);
        nan_b.wb[0] = f32::from_bits(0x7fc0_0001);
        assert_eq!(hash_of(&nan_a), hash_of(&nan_b));
    }
}
