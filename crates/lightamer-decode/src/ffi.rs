// SPDX-License-Identifier: GPL-3.0-or-later
//! Raw FFI declarations for `csrc/rawspeed_shim.{h,cpp}`.
//!
//! This module is the only `unsafe` in the crate (see the module-level
//! `allow` in `lib.rs`). It declares the extern boundary; all calls happen
//! through the safe wrappers in [`crate::image`], one documented `unsafe`
//! block per call.

use core::ffi::{c_char, c_float, c_int};

/// Opaque decode handle (`rs_image`).
pub enum RsImage {}

/// C error out-param (`rs_error`).
#[repr(C)]
pub struct RsError {
    /// `RS_OK` (0) on success, else an `RS_ERR_*` code.
    pub code: c_int,
    /// NUL-terminated detail line.
    pub message: [c_char; 512],
}

impl RsError {
    /// A zeroed error slot to hand to the C layer.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            code: 0,
            message: [0; 512],
        }
    }
}

impl Default for RsError {
    fn default() -> Self {
        Self::new()
    }
}

/// C mosaic sample type: `RS_MOSAIC_U16`.
pub const RS_MOSAIC_U16: c_int = 0;
/// C mosaic sample type: `RS_MOSAIC_F32`.
pub const RS_MOSAIC_F32: c_int = 1;
/// C `RS_CFA_PATTERN_MAX`.
pub const RS_CFA_PATTERN_MAX: usize = 36;

/// C metadata mirror (`rs_image_info`). Field order and types must match
/// `csrc/rawspeed_shim.h` exactly; `info_size_matches_c` pins it.
#[repr(C)]
pub struct RsImageInfo {
    /// `RS_MOSAIC_U16` (0) or `RS_MOSAIC_F32` (1).
    pub data_type: c_int,
    /// Cropped (active) width.
    pub width: c_int,
    /// Cropped (active) height.
    pub height: c_int,
    /// Uncropped width.
    pub uncropped_width: c_int,
    /// Uncropped height.
    pub uncropped_height: c_int,
    /// Crop offsets and right/bottom trims.
    pub crop_left: c_int,
    /// Crop offsets and right/bottom trims.
    pub crop_top: c_int,
    /// Crop offsets and right/bottom trims.
    pub crop_right: c_int,
    /// Crop offsets and right/bottom trims.
    pub crop_bottom: c_int,
    /// Row pitch of the cropped plane in samples of the sample type.
    pub pitch_elems: c_int,
    /// Components per pixel.
    pub cpp: c_int,
    /// Bytes per component.
    pub bpp: c_int,
    /// Nonzero when the mosaic is a CFA.
    pub is_cfa: c_int,
    /// Nonzero for a 6x6 (X-Trans) CFA.
    pub is_xtrans: c_int,
    /// CFA width.
    pub cfa_w: c_int,
    /// CFA height.
    pub cfa_h: c_int,
    /// Row-major CFA colors, `cfa_valid` entries.
    pub cfa_pattern: [c_int; RS_CFA_PATTERN_MAX],
    /// Valid entries in `cfa_pattern`.
    pub cfa_valid: c_int,
    /// Dcraw CFA filter word.
    pub cfa_dcraw_filter: u32,
    /// Black level.
    pub black_level: c_int,
    /// Row-major 2x2 per-channel black, valid if `has_black_sep`.
    pub black_level_separate: [c_int; 4],
    /// Nonzero when `black_level_separate` is valid.
    pub has_black_sep: c_int,
    /// White level, valid if `has_white`.
    pub white_level: c_int,
    /// Nonzero when `white_level` is valid.
    pub has_white: c_int,
    /// As-shot R/G1/B/G2, valid if `has_wb`.
    pub wb_coeffs: [c_float; 4],
    /// Nonzero when `wb_coeffs` is valid.
    pub has_wb: c_int,
    /// XYZ-to-camera matrix (D65), valid if `has_color_matrix`.
    pub color_matrix: [c_float; 9],
    /// Nonzero when `color_matrix` is valid.
    pub has_color_matrix: c_int,
    /// ISO speed, 0 when unknown.
    pub iso_speed: c_int,
    /// Pixel subsampling.
    pub subsampling_x: c_int,
    /// Pixel subsampling.
    pub subsampling_y: c_int,
    /// Pixel aspect ratio.
    pub pixel_aspect_ratio: f64,
    /// Camera make.
    pub make: [c_char; 64],
    /// Camera model.
    pub model: [c_char; 64],
    /// Canonical make.
    pub canonical_make: [c_char; 64],
    /// Canonical model.
    pub canonical_model: [c_char; 64],
    /// Camera mode string.
    pub mode: [c_char; 32],
    /// Demangled decoder class name.
    pub decoder: [c_char; 64],
    /// Cropped plane byte count.
    pub mosaic_bytes: u64,
}

impl RsImageInfo {
    /// A zeroed info block to hand to the C layer.
    #[must_use]
    pub const fn new() -> Self {
        Self {
            data_type: 0,
            width: 0,
            height: 0,
            uncropped_width: 0,
            uncropped_height: 0,
            crop_left: 0,
            crop_top: 0,
            crop_right: 0,
            crop_bottom: 0,
            pitch_elems: 0,
            cpp: 0,
            bpp: 0,
            is_cfa: 0,
            is_xtrans: 0,
            cfa_w: 0,
            cfa_h: 0,
            cfa_pattern: [0; RS_CFA_PATTERN_MAX],
            cfa_valid: 0,
            cfa_dcraw_filter: 0,
            black_level: 0,
            black_level_separate: [0; 4],
            has_black_sep: 0,
            white_level: 0,
            has_white: 0,
            wb_coeffs: [0.0; 4],
            has_wb: 0,
            color_matrix: [0.0; 9],
            has_color_matrix: 0,
            iso_speed: 0,
            subsampling_x: 0,
            subsampling_y: 0,
            pixel_aspect_ratio: 0.0,
            make: [0; 64],
            model: [0; 64],
            canonical_make: [0; 64],
            canonical_model: [0; 64],
            mode: [0; 32],
            decoder: [0; 64],
            mosaic_bytes: 0,
        }
    }
}

impl Default for RsImageInfo {
    fn default() -> Self {
        Self::new()
    }
}

unsafe extern "C" {
    /// Parse, select a decoder, run `checkSupport` (see header).
    pub fn rs_open(
        path: *const c_char,
        cameras_xml: *const c_char,
        err: *mut RsError,
    ) -> *mut RsImage;
    /// Run `decodeRaw` + `decodeMetaData` (see header).
    pub fn rs_decode(img: *mut RsImage, err: *mut RsError) -> c_int;
    /// Fill metadata + geometry (see header).
    pub fn rs_fill_info(img: *const RsImage, out: *mut RsImageInfo, err: *mut RsError) -> c_int;
    /// Cropped u16 plane base, or NULL (see header).
    pub fn rs_mosaic_u16(img: *const RsImage) -> *const u16;
    /// Cropped f32 plane base, or NULL (see header).
    pub fn rs_mosaic_f32(img: *const RsImage) -> *const f32;
    /// FNV-1a 64 over the cropped plane (see header).
    pub fn rs_mosaic_hash(img: *const RsImage, err: *mut RsError) -> u64;
    /// Release a handle (NULL-safe).
    pub fn rs_free(img: *mut RsImage);
    /// Parse the singleton camera database now (see header).
    pub fn rs_ensure_meta(err: *mut RsError) -> c_int;
    /// Process-wide `cameras.xml` parse count.
    pub fn rs_meta_parse_count() -> u64;
    /// `sizeof(rs_image_info)`.
    pub fn rs_info_size() -> usize;
    /// `sizeof(rs_error)` (M3 pin for the error slot).
    pub fn rs_error_size() -> usize;
    /// Classify a message as open (0) or decode (1) would (see header).
    pub fn rs_classify_for_test(stage: c_int, msg: *const c_char) -> c_int;
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    #[test]
    fn info_size_matches_c() {
        // SAFETY: rs_info_size takes no pointers and touches no state.
        let c_size = unsafe { rs_info_size() };
        assert_eq!(c_size, size_of::<RsImageInfo>());
    }

    #[test]
    fn error_size_matches_c() {
        // SAFETY: rs_error_size takes no pointers and touches no state.
        let c_size = unsafe { rs_error_size() };
        assert_eq!(c_size, size_of::<RsError>());
    }
}
