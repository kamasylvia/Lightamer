// SPDX-License-Identifier: GPL-3.0-or-later
//! Safe wrapper over the rawspeed C shim: typed errors, owned handles,
//! metadata and mosaic copies.
//!
//! [`RawImage::open`] parses a file and selects a decoder; [`RawImage::decode`]
//! produces pixels. [`decode_file`] does both. Handles are `Send` (each owns
//! an independent decoder; the camera database is read-only after load) but
//! deliberately not `Sync`.

use core::ffi::c_char;
use std::cell::Cell;
use std::ffi::{CStr, CString};
use std::marker::PhantomData;
use std::path::Path;
use std::ptr::NonNull;

use crate::error::{DecodeError, ErrorCode};
use crate::ffi;

/// Largest sane plane dimension (defense-in-depth against corrupt headers).
const MAX_DIM: i32 = 1 << 20;
/// Largest sane components-per-pixel.
const MAX_CPP: i32 = 4;

/// Mosaic sample type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MosaicKind {
    /// 16-bit unsigned integers.
    U16,
    /// 32-bit floats.
    F32,
}

impl MosaicKind {
    /// Bytes per sample.
    #[must_use]
    pub const fn sample_bytes(self) -> usize {
        match self {
            Self::U16 => 2,
            Self::F32 => 4,
        }
    }
}

/// CFA cell color (rawspeed `CFAColor` values).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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
    /// Anything else (including `UNKNOWN`).
    Unknown,
}

impl CfaColor {
    /// Map a rawspeed `CFAColor` discriminant; unknown values stay unknown.
    #[must_use]
    pub const fn from_i32(value: i32) -> Self {
        match value {
            0 => Self::Red,
            1 => Self::Green,
            2 => Self::Blue,
            3 => Self::Cyan,
            4 => Self::Magenta,
            5 => Self::Yellow,
            6 => Self::White,
            7 => Self::FujiGreen,
            _ => Self::Unknown,
        }
    }
}

/// Crop rectangle: trims on each side, in pixels.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CropBox {
    /// Trimmed pixels on the left.
    pub left: u32,
    /// Trimmed pixels on the top.
    pub top: u32,
    /// Trimmed pixels on the right.
    pub right: u32,
    /// Trimmed pixels on the bottom.
    pub bottom: u32,
}
/// Decoded RAW metadata. Fields rawspeed does not expose are `None`, with
/// the provenance noted on each field.
#[derive(Debug, Clone, PartialEq)]
pub struct RawMetadata {
    /// Demangled decoder class, e.g. `ArwDecoder`.
    pub decoder: String,
    /// Camera make (`SONY`).
    pub make: String,
    /// Camera model (`ILCE-7RM5`).
    pub model: String,
    /// Canonical make (`Sony`).
    pub canonical_make: String,
    /// Canonical model.
    pub canonical_model: String,
    /// Camera mode string (usually empty).
    pub mode: String,
    /// Cropped (active) width.
    pub width: u32,
    /// Cropped (active) height.
    pub height: u32,
    /// Uncropped width.
    pub uncropped_width: u32,
    /// Uncropped height.
    pub uncropped_height: u32,
    /// Crop trims.
    pub crop: CropBox,
    /// Mosaic sample type.
    pub mosaic_kind: MosaicKind,
    /// Cropped-plane row pitch in samples (uncropped pitch kept).
    pub pitch_elems: usize,
    /// Components per pixel.
    pub cpp: u32,
    /// Bytes per component.
    pub bpp: u32,
    /// Whether the mosaic is a CFA.
    pub is_cfa: bool,
    /// Whether the CFA is 6x6 (X-Trans).
    pub is_xtrans: bool,
    /// CFA width.
    pub cfa_w: u32,
    /// CFA height.
    pub cfa_h: u32,
    /// Row-major CFA colors.
    pub cfa_pattern: Vec<CfaColor>,
    /// Dcraw CFA filter word.
    pub cfa_dcraw_filter: u32,
    /// Black level.
    pub black_level: i32,
    /// Row-major 2x2 per-channel black levels, when reported.
    pub black_separate: Option<[i32; 4]>,
    /// White level, when reported.
    pub white_level: Option<i32>,
    /// As-shot white-balance multipliers R/G1/B/G2, when reported.
    pub white_balance: Option<[f32; 4]>,
    /// In-camera color temperature in kelvin. Always `None`: rawspeed does
    /// not expose it (B3 derives CCT from the multipliers if needed).
    pub white_balance_kelvin: Option<f32>,
    /// In-camera tint. Always `None`: rawspeed does not expose it.
    pub white_balance_tint: Option<f32>,
    /// XYZ-to-camera matrix under D65, verbatim from rawspeed.
    pub color_matrix_xyz_to_cam: Option<[f32; 9]>,
    /// Camera-to-XYZ matrix, inverted from the above in `f64`.
    /// `None` when the verbatim matrix is absent or singular.
    pub color_matrix_cam_to_xyz: Option<[f32; 9]>,
    /// ISO speed, when reported.
    pub iso: Option<u32>,
    /// Exposure time in seconds. Always `None`: rawspeed's metadata carries
    /// no exposure fields.
    pub exposure_time: Option<f64>,
    /// Aperture f-number. Always `None`: rawspeed exposes no EXIF optics.
    pub aperture: Option<f32>,
    /// Focal length in mm. Always `None`: rawspeed exposes no EXIF optics.
    pub focal_length: Option<f32>,
    /// Lens model. Always `None`: rawspeed exposes no EXIF optics.
    pub lens_model: Option<String>,
    /// Pixel subsampling.
    pub subsampling: (u32, u32),
    /// Pixel aspect ratio.
    pub pixel_aspect_ratio: f64,
    /// Cropped plane byte count.
    pub mosaic_bytes: u64,
}

/// Owned cropped mosaic plane, pitch already removed.
#[derive(Debug, Clone, PartialEq)]
pub enum Mosaic {
    /// 16-bit mosaic, cropped, row-major.
    U16(Vec<u16>),
    /// 32-bit float mosaic, cropped, row-major.
    F32(Vec<f32>),
}

impl Mosaic {
    /// The sample type.
    #[must_use]
    pub const fn kind(&self) -> MosaicKind {
        match self {
            Self::U16(_) => MosaicKind::U16,
            Self::F32(_) => MosaicKind::F32,
        }
    }

    /// Sample count (`width * height * cpp`).
    #[must_use]
    pub fn len(&self) -> usize {
        match self {
            Self::U16(v) => v.len(),
            Self::F32(v) => v.len(),
        }
    }

    /// Whether the plane holds no samples.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

/// A fully decoded file: metadata plus the owned cropped mosaic.
#[derive(Debug, Clone, PartialEq)]
pub struct DecodedImage {
    /// Metadata.
    pub meta: RawMetadata,
    /// Cropped mosaic plane.
    pub mosaic: Mosaic,
}

/// An open RAW file. Parse with [`RawImage::open`], decode with
/// [`RawImage::decode`], then read [`RawMetadata`] and [`Mosaic`].
#[derive(Debug)]
pub struct RawImage {
    /// Handle from `rs_open`; freed exactly once by `Drop`.
    handle: NonNull<ffi::RsImage>,
    /// Whether `rs_decode` has succeeded.
    decoded: bool,
    /// Handles are `Send` (independent decoders) but not `Sync`.
    _not_sync: PhantomData<Cell<()>>,
}

// SAFETY (Send): a handle owns its file bytes, parser, decoder, and pixels.
// rawspeed decoders are independent across handles; the shared camera
// database is read-only after construction. Moving ownership across threads
// is therefore sound. `Sync` is withheld: concurrent `&self` use of one C++
// object is not part of rawspeed's documented contract.
unsafe impl Send for RawImage {}

impl Drop for RawImage {
    fn drop(&mut self) {
        // SAFETY: the handle came from a successful `rs_open`, is never
        // copied out (private field), and `Drop` runs exactly once, so this
        // is the unique `rs_free` for it. `rs_free` is NULL-safe and total.
        unsafe {
            ffi::rs_free(self.handle.as_ptr());
        }
    }
}

/// Read a C error slot into a typed error.
fn take_error(slot: &ffi::RsError) -> DecodeError {
    // SAFETY: the C layer always NUL-terminates `message` (`setErr` writes
    // the terminator; slots start zeroed), and no other thread touches this
    // stack slot, so borrowing it as `CStr` is sound.
    let detail = unsafe { CStr::from_ptr(slot.message.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    DecodeError::new(ErrorCode::from_i32(slot.code), detail)
}

/// Read a NUL-terminated C string field.
fn take_str(field: &[c_char]) -> String {
    // SAFETY: the C layer zero-fills `rs_image_info` then writes each string
    // with an explicit terminator, so the first element starts a valid C
    // string wholly inside the field.
    unsafe { CStr::from_ptr(field.as_ptr()) }
        .to_string_lossy()
        .into_owned()
}

/// Convert a path to a `CString` for the C layer.
///
/// # Errors
///
/// Returns [`ErrorCode::Internal`] when the path holds a NUL byte.
fn path_cstring(path: &Path) -> Result<CString, DecodeError> {
    CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_| DecodeError::new(ErrorCode::Internal, "path holds a NUL byte"))
}

/// Positive `i32` to `u32`.
///
/// # Errors
///
/// Returns [`ErrorCode::Internal`] on negative input.
fn to_u32(value: i32, what: &str) -> Result<u32, DecodeError> {
    u32::try_from(value)
        .map_err(|_| DecodeError::new(ErrorCode::Internal, format!("negative {what}")))
}

/// Positive `i32` to `usize`.
///
/// # Errors
///
/// Returns [`ErrorCode::Internal`] on negative input.
fn to_usize(value: i32, what: &str) -> Result<usize, DecodeError> {
    usize::try_from(value)
        .map_err(|_| DecodeError::new(ErrorCode::Internal, format!("negative {what}")))
}

/// Invert a row-major 3x3 matrix in `f64`; `None` when near-singular.
#[must_use]
#[allow(clippy::many_single_char_names)] // Matrix entries read best as a..i.
pub fn invert_3x3(m: [f32; 9]) -> Option<[f32; 9]> {
    let a = f64::from(m[0]);
    let b = f64::from(m[1]);
    let c = f64::from(m[2]);
    let d = f64::from(m[3]);
    let e = f64::from(m[4]);
    let f = f64::from(m[5]);
    let g = f64::from(m[6]);
    let h = f64::from(m[7]);
    let i = f64::from(m[8]);
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if !det.is_finite() || det.abs() < 1e-12 {
        return None;
    }
    let inv = [
        (e * i - f * h) / det,
        (c * h - b * i) / det,
        (b * f - c * e) / det,
        (f * g - d * i) / det,
        (a * i - c * g) / det,
        (c * d - a * f) / det,
        (d * h - e * g) / det,
        (b * g - a * h) / det,
        (a * e - b * d) / det,
    ];
    if inv.iter().any(|v| !v.is_finite()) {
        return None;
    }
    let mut out = [0.0_f32; 9];
    for (slot, value) in out.iter_mut().zip(inv.iter()) {
        // f64 -> f32: values are finite (checked above); precision loss is
        // inherent to the f32 matrix format, not a truncation bug.
        #[allow(clippy::cast_possible_truncation)]
        let narrowed = *value as f32;
        *slot = narrowed;
    }
    Some(out)
}

/// Copy the cropped plane out of the C++ object, dropping pitch padding.
fn copy_plane<T: Copy>(
    base: *const T,
    pitch: usize,
    width: usize,
    height: usize,
    cpp: usize,
) -> Result<Vec<T>, DecodeError> {
    let row = width
        .checked_mul(cpp)
        .ok_or_else(|| DecodeError::new(ErrorCode::Internal, "mosaic row size overflows"))?;
    if pitch < row || pitch == 0 {
        return Err(DecodeError::new(
            ErrorCode::Internal,
            "mosaic pitch smaller than row",
        ));
    }
    let total = row
        .checked_mul(height)
        .ok_or_else(|| DecodeError::new(ErrorCode::Internal, "mosaic size overflows"))?;
    let mut out = Vec::with_capacity(total);
    for y in 0..height {
        let offset = y
            .checked_mul(pitch)
            .ok_or_else(|| DecodeError::new(ErrorCode::Internal, "mosaic offset overflows"))?;
        // SAFETY: `base` is the cropped-plane base borrowed from the live
        // handle (kept alive by `&self`); dims passed the sane-bounds check
        // at the call site (<= 2^20, cpp <= 4), so `offset + row` cannot wrap
        // on 64-bit and every row lies inside the C++ plane, which outlives
        // this call. Rows are disjoint; the C++ side never mutates pixels.
        let row_slice = unsafe {
            let row_ptr = base.add(offset);
            core::slice::from_raw_parts(row_ptr, row)
        };
        out.extend_from_slice(row_slice);
    }
    Ok(out)
}

/// Fill `rs_image_info` for a live decoded handle.
///
/// # Errors
///
/// Returns the C layer's typed error when the fill fails.
fn fill_info(handle: NonNull<ffi::RsImage>) -> Result<ffi::RsImageInfo, DecodeError> {
    let mut info = ffi::RsImageInfo::new();
    let mut err = ffi::RsError::new();
    // SAFETY: `handle` is a live decoded image; `info`/`err` are valid
    // exclusive stack slots. `rs_fill_info` only reads the image.
    let rc = unsafe { ffi::rs_fill_info(handle.as_ptr(), &raw mut info, &raw mut err) };
    if rc == 0 {
        Ok(info)
    } else {
        Err(take_error(&err))
    }
}

/// Sane-bounds check shared by the mosaic readers.
///
/// # Errors
///
/// Returns [`ErrorCode::Internal`] when a dimension is out of range.
fn check_dims(width: i32, height: i32, pitch: i32, cpp: i32) -> Result<(), DecodeError> {
    for (value, what) in [(width, "width"), (height, "height"), (pitch, "pitch")] {
        if value <= 0 || value > MAX_DIM {
            return Err(DecodeError::new(
                ErrorCode::Internal,
                format!("mosaic {what} out of range"),
            ));
        }
    }
    if cpp <= 0 || cpp > MAX_CPP {
        return Err(DecodeError::new(
            ErrorCode::Internal,
            "mosaic cpp out of range",
        ));
    }
    Ok(())
}

impl RawImage {
    /// Parse `path`, select a decoder, run `checkSupport` (no pixels yet).
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::NotFound`] for missing files,
    /// [`ErrorCode::NotRaw`] for files no decoder accepts,
    /// [`ErrorCode::UnknownCamera`] for unsupported cameras,
    /// [`ErrorCode::Truncated`] for short reads, and
    /// [`ErrorCode::Internal`] for camera-database failures.
    pub fn open(path: &Path) -> Result<Self, DecodeError> {
        Self::open_with_cameras_xml(path, None)
    }

    /// [`RawImage::open`] with an explicit camera database (tests/QA only).
    /// `None` uses the process singleton (parsed once).
    ///
    /// # Errors
    ///
    /// Same as [`RawImage::open`]; a broken explicit database reports
    /// [`ErrorCode::Internal`].
    pub fn open_with_cameras_xml(
        path: &Path,
        cameras_xml: Option<&Path>,
    ) -> Result<Self, DecodeError> {
        let c_path = path_cstring(path)?;
        let c_xml = cameras_xml
            .map(path_cstring)
            .transpose()?
            .unwrap_or_default();
        // Empty CString (None case) would pass "" — use NULL instead.
        let xml_ptr = if cameras_xml.is_none() {
            core::ptr::null()
        } else {
            c_xml.as_ptr()
        };
        let mut err = ffi::RsError::new();
        // SAFETY: both pointers are NULL or valid NUL-terminated strings
        // alive for the call; `err` is an exclusive stack slot. `rs_open`
        // either returns NULL with `err` set or a unique owned handle.
        let raw = unsafe { ffi::rs_open(c_path.as_ptr(), xml_ptr, &raw mut err) };
        NonNull::new(raw).map_or_else(
            || Err(take_error(&err)),
            |handle| {
                Ok(Self {
                    handle,
                    decoded: false,
                    _not_sync: PhantomData,
                })
            },
        )
    }

    /// Run `decodeRaw` + `decodeMetaData`. Idempotent.
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::Truncated`] for cut-short files,
    /// [`ErrorCode::DecompressFailed`] for decoder failures,
    /// [`ErrorCode::UnsupportedCompression`] for unknown compressions, and
    /// [`ErrorCode::OutOfMemory`] when allocation fails.
    pub fn decode(&mut self) -> Result<(), DecodeError> {
        let mut err = ffi::RsError::new();
        // SAFETY: `handle` is live and exclusively borrowed (`&mut self`);
        // `err` is an exclusive stack slot.
        let rc = unsafe { ffi::rs_decode(self.handle.as_ptr(), &raw mut err) };
        if rc == 0 {
            self.decoded = true;
            Ok(())
        } else {
            Err(take_error(&err))
        }
    }

    /// Whether [`RawImage::decode`] has succeeded.
    #[must_use]
    pub const fn is_decoded(&self) -> bool {
        self.decoded
    }

    /// Read the decoded metadata.
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::Internal`] when the image is not decoded yet.
    pub fn metadata(&self) -> Result<RawMetadata, DecodeError> {
        if !self.decoded {
            return Err(DecodeError::new(ErrorCode::Internal, "image not decoded"));
        }
        let info = fill_info(self.handle)?;
        let mosaic_kind = if info.data_type == ffi::RS_MOSAIC_U16 {
            MosaicKind::U16
        } else if info.data_type == ffi::RS_MOSAIC_F32 {
            MosaicKind::F32
        } else {
            return Err(DecodeError::new(
                ErrorCode::Internal,
                "unknown mosaic sample type",
            ));
        };
        let valid = to_usize(info.cfa_valid, "cfa count")?
            .min(ffi::RS_CFA_PATTERN_MAX)
            .min(info.cfa_pattern.len());
        let mut pattern = Vec::with_capacity(valid);
        for cell in info.cfa_pattern.iter().take(valid) {
            pattern.push(CfaColor::from_i32(*cell));
        }
        let cam_to_xyz = if info.has_color_matrix != 0 {
            invert_3x3(info.color_matrix)
        } else {
            None
        };
        Ok(RawMetadata {
            decoder: take_str(&info.decoder),
            make: take_str(&info.make),
            model: take_str(&info.model),
            canonical_make: take_str(&info.canonical_make),
            canonical_model: take_str(&info.canonical_model),
            mode: take_str(&info.mode),
            width: to_u32(info.width, "width")?,
            height: to_u32(info.height, "height")?,
            uncropped_width: to_u32(info.uncropped_width, "uncropped width")?,
            uncropped_height: to_u32(info.uncropped_height, "uncropped height")?,
            crop: CropBox {
                left: to_u32(info.crop_left, "crop")?,
                top: to_u32(info.crop_top, "crop")?,
                right: to_u32(info.crop_right, "crop")?,
                bottom: to_u32(info.crop_bottom, "crop")?,
            },
            mosaic_kind,
            pitch_elems: to_usize(info.pitch_elems, "pitch")?,
            cpp: to_u32(info.cpp, "cpp")?,
            bpp: to_u32(info.bpp, "bpp")?,
            is_cfa: info.is_cfa != 0,
            is_xtrans: info.is_xtrans != 0,
            cfa_w: to_u32(info.cfa_w, "cfa width")?,
            cfa_h: to_u32(info.cfa_h, "cfa height")?,
            cfa_pattern: pattern,
            cfa_dcraw_filter: info.cfa_dcraw_filter,
            black_level: info.black_level,
            black_separate: (info.has_black_sep != 0).then_some(info.black_level_separate),
            white_level: (info.has_white != 0).then_some(info.white_level),
            white_balance: (info.has_wb != 0).then_some(info.wb_coeffs),
            white_balance_kelvin: None,
            white_balance_tint: None,
            color_matrix_xyz_to_cam: (info.has_color_matrix != 0).then_some(info.color_matrix),
            color_matrix_cam_to_xyz: cam_to_xyz,
            iso: u32::try_from(info.iso_speed).ok().filter(|v| *v != 0),
            exposure_time: None,
            aperture: None,
            focal_length: None,
            lens_model: None,
            subsampling: (
                to_u32(info.subsampling_x, "subsampling")?,
                to_u32(info.subsampling_y, "subsampling")?,
            ),
            pixel_aspect_ratio: info.pixel_aspect_ratio,
            mosaic_bytes: info.mosaic_bytes,
        })
    }

    /// Copy the cropped mosaic plane (pitch padding removed).
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::Internal`] when the image is not decoded yet or
    /// the C layer reports inconsistent geometry.
    pub fn mosaic(&self) -> Result<Mosaic, DecodeError> {
        if !self.decoded {
            return Err(DecodeError::new(ErrorCode::Internal, "image not decoded"));
        }
        let info = fill_info(self.handle)?;
        check_dims(info.width, info.height, info.pitch_elems, info.cpp)?;
        let width = to_usize(info.width, "width")?;
        let height = to_usize(info.height, "height")?;
        let pitch = to_usize(info.pitch_elems, "pitch")?;
        let cpp = to_usize(info.cpp, "cpp")?;
        if info.data_type == ffi::RS_MOSAIC_U16 {
            // SAFETY: live decoded u16 image; `rs_mosaic_u16` returns the
            // cropped base or NULL on type mismatch (checked below).
            let base = unsafe { ffi::rs_mosaic_u16(self.handle.as_ptr()) };
            if base.is_null() {
                return Err(DecodeError::new(
                    ErrorCode::Internal,
                    "u16 mosaic unavailable",
                ));
            }
            copy_plane(base, pitch, width, height, cpp).map(Mosaic::U16)
        } else if info.data_type == ffi::RS_MOSAIC_F32 {
            // SAFETY: live decoded f32 image; NULL-checked below.
            let base = unsafe { ffi::rs_mosaic_f32(self.handle.as_ptr()) };
            if base.is_null() {
                return Err(DecodeError::new(
                    ErrorCode::Internal,
                    "f32 mosaic unavailable",
                ));
            }
            copy_plane(base, pitch, width, height, cpp).map(Mosaic::F32)
        } else {
            Err(DecodeError::new(
                ErrorCode::Internal,
                "unknown mosaic sample type",
            ))
        }
    }

    /// FNV-1a 64 over the cropped plane (cross-implementation anchor).
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::Internal`] when the image is not decoded yet.
    pub fn mosaic_hash(&self) -> Result<u64, DecodeError> {
        if !self.decoded {
            return Err(DecodeError::new(ErrorCode::Internal, "image not decoded"));
        }
        let mut err = ffi::RsError::new();
        // SAFETY: live decoded handle; `err` is an exclusive stack slot.
        // A zero hash with `err` set is a failure; a zero hash with `RS_OK`
        // would be a (never observed) genuine hash — treat code as truth.
        let hash = unsafe { ffi::rs_mosaic_hash(self.handle.as_ptr(), &raw mut err) };
        if err.code == 0 {
            Ok(hash)
        } else {
            Err(take_error(&err))
        }
    }

    /// Parse the singleton camera database now (no-op once parsed).
    ///
    /// # Errors
    ///
    /// Returns [`ErrorCode::Internal`] when the bundled database is broken.
    pub fn ensure_metadata() -> Result<(), DecodeError> {
        let mut err = ffi::RsError::new();
        // SAFETY: no handle involved; `err` is an exclusive stack slot.
        // `rs_ensure_meta` is idempotent and thread-safe (call_once).
        let rc = unsafe { ffi::rs_ensure_meta(&raw mut err) };
        if rc == 0 {
            Ok(())
        } else {
            Err(take_error(&err))
        }
    }

    /// Process-wide `cameras.xml` parse count (singleton probe).
    #[must_use]
    pub fn meta_parse_count() -> u64 {
        // SAFETY: pure atomic counter read, no pointers, no state change.
        unsafe { ffi::rs_meta_parse_count() }
    }
}

/// Open, decode, and read one file.
///
/// # Errors
///
/// Returns the same typed errors as [`RawImage::open`] and
/// [`RawImage::decode`].
pub fn decode_file(path: &Path) -> Result<DecodedImage, DecodeError> {
    let mut image = RawImage::open(path)?;
    image.decode()?;
    let meta = image.metadata()?;
    let mosaic = image.mosaic()?;
    Ok(DecodedImage { meta, mosaic })
}

/// Path of the bundled `cameras.xml` copy (baked at build time).
#[must_use]
pub fn cameras_xml_bundled_path() -> &'static str {
    env!("RAWSPEED_CAMERAS_XML")
}

/// Classify a message as open (`false`) or decode (`true`) would.
/// Test seam over `rs_classify_for_test`.
#[must_use]
pub fn classify_for_test(decode_stage: bool, msg: &str) -> ErrorCode {
    let Ok(c_msg) = CString::new(msg) else {
        return ErrorCode::Internal;
    };
    let stage = i32::from(decode_stage);
    // SAFETY: `c_msg` is a valid NUL-terminated string alive for the call;
    // `rs_classify_for_test` only reads it.
    let code = unsafe { ffi::rs_classify_for_test(stage, c_msg.as_ptr()) };
    ErrorCode::from_i32(code)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn bundled_cameras_xml_exists() {
        assert!(Path::new(cameras_xml_bundled_path()).is_file());
    }

    #[test]
    fn image_is_send() {
        fn is_send<T: Send>() {}
        is_send::<RawImage>();
    }

    #[test]
    fn missing_file_reports_not_found() {
        let err = RawImage::open(&PathBuf::from("definitely-not-here-12345.ARW"))
            .expect_err("missing file must fail");
        assert_eq!(err.code(), ErrorCode::NotFound);
    }

    #[test]
    fn error_mapping_covers_observed_messages() {
        // (stage_is_decode, message, expected) — messages captured from
        // rawspeed 0c16fee77; see B2a-REPORT §5.
        let cases = [
            (false, "No decoder found. Sorry.", ErrorCode::NotRaw),
            (false, "File is 0 bytes.", ErrorCode::Truncated),
            (
                true,
                "Buffer overflow: image file may be truncated",
                ErrorCode::Truncated,
            ),
            (
                true,
                "Out of bounds access in ByteStream",
                ErrorCode::Truncated,
            ),
            (true, "Truncated file", ErrorCode::Truncated),
            (
                false,
                "Camera 'X' 'Y', mode 'Z' not supported, and not allowed to guess",
                ErrorCode::UnknownCamera,
            ),
            (false, "Couldn't find camera X Y", ErrorCode::UnknownCamera),
            (
                false,
                "Camera not supported (explicit). Sorry.",
                ErrorCode::UnknownCamera,
            ),
            (
                true,
                "Unsupported compression 7",
                ErrorCode::UnsupportedCompression,
            ),
            (true, "Error decompressing", ErrorCode::DecompressFailed),
            (
                true,
                "JPEG Error while decompressing image.",
                ErrorCode::DecompressFailed,
            ),
            (false, "something entirely new", ErrorCode::NotRaw),
            (true, "something entirely new", ErrorCode::DecompressFailed),
        ];
        for (decode_stage, msg, expected) in cases {
            assert_eq!(classify_for_test(decode_stage, msg), expected, "{msg}");
        }
    }

    #[test]
    fn classify_rejects_bad_input() {
        assert_eq!(classify_for_test(false, "has\0nul"), ErrorCode::Internal);
    }

    #[test]
    fn invert_identity_stays_identity() {
        let id = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
        let inv = invert_3x3(id).expect("identity inverts");
        for (got, want) in inv.iter().zip(id.iter()) {
            assert!((got - want).abs() < 1e-6, "{got} vs {want}");
        }
    }

    #[test]
    fn invert_round_trip_on_sony_matrix() {
        // A7R5 verbatim matrix from the oracle run.
        let m = [
            0.82, -0.2976, -0.0719, -0.4296, 1.2053, 0.2532, -0.0429, 0.1282, 0.5774,
        ];
        let inv = invert_3x3(m).expect("sony matrix inverts");
        let back = invert_3x3(inv).expect("inverse inverts");
        for (got, want) in back.iter().zip(m.iter()) {
            assert!((got - want).abs() < 1e-4, "{got} vs {want}");
        }
    }

    #[test]
    fn invert_singular_is_none() {
        assert!(invert_3x3([0.0; 9]).is_none());
        assert!(invert_3x3([1.0; 9]).is_none());
    }
}
