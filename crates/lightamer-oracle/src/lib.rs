// SPDX-License-Identifier: GPL-3.0-or-later
//! Upstream oracle: verbatim darktable module code behind a safe runner.
//!
//! The C in `csrc/` + `upstream/` compiles upstream logic (extracted
//! byte-for-byte by `tools/extract.sh`) with stub interfaces (`stubs/`).
//! This file is the only `unsafe` boundary: it mirrors the three ABI structs
//! with `#[repr(C)]`, checks every length before the call, and hands back
//! owned results. Test-only: `cargo xtask layers` refuses it as a normal
//! dependency, so it links into test binaries alone.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

use std::ffi::{CStr, c_char, c_int, c_void};
use std::fmt;

// Mirrors `oracle_facts` (csrc/oracle_abi.h), field for field.
#[repr(C)]
struct CFacts {
    width: i32,
    height: i32,
    p_width: i32,
    p_height: i32,
    crop_x: i32,
    crop_y: i32,
    crop_right: i32,
    crop_bottom: i32,
    black_separate: [u16; 4],
    white_point: u32,
    filters: u32,
    xtrans: [u8; 36],
    flags: i32,
    buf_channels: u32,
    buf_datatype: i32,
    id: i32,
}

// Mirrors `oracle_roi`.
#[repr(C)]
struct CRoi {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: f32,
}

// Mirrors `oracle_state_out`.
#[repr(C)]
struct CStateOut {
    enabled: i32,
    filters: u32,
    xtrans: [u8; 36],
    processed_maximum: [f32; 4],
    p_width: i32,
    p_height: i32,
}

// The C side asserts the same three sizes (chain.c `_Static_assert`).
const _: () = assert!(size_of::<CFacts>() == 100);
const _: () = assert!(size_of::<CRoi>() == 20);
const _: () = assert!(size_of::<CStateOut>() == 68);

// The chain entry points plus rawprepare's params fill/read pair. Argument
// shapes are fixed here so no caller can pass a mismatched pointer.
#[expect(unsafe_code)]
// This crate owns the oracle FFI boundary: the extern block below plus one
// documented `unsafe` block per call; every block carries a SAFETY comment
// naming the contract it upholds.
unsafe extern "C" {
    fn oracle_run(
        names: *const *const c_char,
        params_list: *const *const c_void,
        count: c_int,
        facts: *const CFacts,
        input: *const c_void,
        input_is_u16: c_int,
        rin: *const CRoi,
        output: *mut c_void,
        rout: *const CRoi,
        state: *mut CStateOut,
    ) -> c_int;
    fn oracle_roi_map(
        want_out: c_int,
        name: *const c_char,
        facts: *const CFacts,
        params: *const c_void,
        input: *const CRoi,
        output: *mut CRoi,
    ) -> c_int;
    fn oracle_defaults(name: *const c_char, facts: *const CFacts, params_out: *mut c_void)
    -> c_int;
    fn oracle_params_size(name: *const c_char) -> c_int;
    fn oracle_rawprepare_fill(
        out: *mut c_void,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
        black: *const u16,
        white: u16,
        flat_field: c_int,
    );
    fn oracle_rawprepare_read(
        params: *const c_void,
        crop: *mut i32,
        black: *mut u16,
        white: *mut u16,
        flat_field: *mut c_int,
    );
}

/// Buffer scalar type, mirroring `TYPE_FLOAT`/`TYPE_UINT16`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BufferType {
    /// 32-bit float lanes (`TYPE_FLOAT`).
    Float,
    /// 16-bit integer lanes (`TYPE_UINT16`).
    Uint16,
}

impl BufferType {
    fn abi(self) -> i32 {
        match self {
            BufferType::Float => 1,
            BufferType::Uint16 => 2,
        }
    }
}

/// Image facts the caller fills: the `dt_image_t` fields the chain reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Facts {
    /// Decoded width and height.
    pub width: i32,
    /// Decoded height.
    pub height: i32,
    /// Post-crop width (`p_width`, rewritten by commit's rawcrops leg).
    pub p_width: i32,
    /// Post-crop height.
    pub p_height: i32,
    /// Loader crop: left, top, right, bottom.
    pub crop: [i32; 4],
    /// Per-channel black levels.
    pub black: [u16; 4],
    /// White level.
    pub white: u32,
    /// Dcraw filter word (0 when patternless).
    pub filters: u32,
    /// X-Trans table, row-major (read only when `filters == 9`).
    pub xtrans: [u8; 36],
    /// `DT_IMAGE_*` bits.
    pub flags: u32,
    /// Stored buffer channels (1 = mono).
    pub buf_channels: u32,
    /// Stored buffer scalar type (feeds the normalized check).
    pub buf_datatype: BufferType,
    /// Image id (opaque here).
    pub id: i32,
}

impl Facts {
    fn abi(self) -> CFacts {
        CFacts {
            width: self.width,
            height: self.height,
            p_width: self.p_width,
            p_height: self.p_height,
            crop_x: self.crop[0],
            crop_y: self.crop[1],
            crop_right: self.crop[2],
            crop_bottom: self.crop[3],
            black_separate: self.black,
            white_point: self.white,
            filters: self.filters,
            xtrans: self.xtrans,
            flags: i32::from_ne_bytes(self.flags.to_ne_bytes()),
            buf_channels: self.buf_channels,
            buf_datatype: self.buf_datatype.abi(),
            id: self.id,
        }
    }
}

/// Region of interest, same five fields as `dt_iop_roi_t`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Roi {
    /// Left edge.
    pub x: i32,
    /// Top edge.
    pub y: i32,
    /// Width in pixels.
    pub width: i32,
    /// Height in pixels.
    pub height: i32,
    /// Resolution relative to the decoded frame.
    pub scale: f32,
}

impl Roi {
    fn abi(self) -> CRoi {
        CRoi {
            x: self.x,
            y: self.y,
            width: self.width,
            height: self.height,
            scale: self.scale,
        }
    }

    fn from_abi(roi: &CRoi) -> Self {
        Self {
            x: roi.x,
            y: roi.y,
            width: roi.width,
            height: roi.height,
            scale: roi.scale,
        }
    }
}

/// rawprepare parameters: crop sides, four black levels, white point, and
/// the flat-field switch (always off here: DNG gain maps untranscribed).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Params {
    /// Crop sides: left, top, right, bottom.
    pub crop: [i32; 4],
    /// Per-channel black levels.
    pub black: [u16; 4],
    /// White point.
    pub white: u16,
    /// Embedded-gainmap correction (off in every oracle run).
    pub flat_field: bool,
}

/// One input tile: raw sensor words or unnormalized floats.
#[derive(Debug, Clone, Copy)]
pub enum TileInput<'a> {
    /// 16-bit mosaic words (the `TYPE_UINT16` leg).
    U16(&'a [u16]),
    /// Unnormalized float mosaic (the `TYPE_FLOAT` leg).
    F32(&'a [f32]),
}

/// Post-run state: what the Rust transcription must reproduce, except
/// `p_width`/`p_height` (commit's rawcrops rewrite has no channel into the
/// Rust pipe yet — `ImageInfo` is immutable at commit and `PipeState`
/// carries no such field — so comparisons skip them for now).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StateOut {
    /// Whether the piece stayed enabled (commit may disable it).
    pub enabled: bool,
    /// CFA word after the run's crop shift.
    pub filters: u32,
    /// X-Trans table after the run, row-major.
    pub xtrans: [u8; 36],
    /// Per-channel maxima after the run.
    pub processed_maximum: [f32; 4],
    /// Post-crop width (commit's rawcrops leg may rewrite it).
    pub p_width: i32,
    /// Post-crop height.
    pub p_height: i32,
}

/// What can go wrong across the oracle boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OracleError {
    /// Caller-side shape problem; the C side was never reached.
    BadInput(&'static str),
    /// The C chain refused: 1 unknown module, 2 disabled-stage mismatch,
    /// 3 rout mismatch, 4 allocation failure.
    Chain(i32),
}

impl fmt::Display for OracleError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OracleError::BadInput(what) => write!(f, "oracle input rejected: {what}"),
            OracleError::Chain(code) => write!(f, "oracle chain refused (code {code})"),
        }
    }
}

impl std::error::Error for OracleError {}

/// Module table name of the first transcribed module.
pub const RAWPREPARE: &CStr = c"rawprepare";

/// `DT_IMAGE_RAW` (`src/common/image.h`): the capture needs demosaicing.
pub const DT_IMAGE_RAW: u32 = 64;

/// `DT_IMAGE_HDR` (`src/common/image.h`): float-bits levels.
pub const DT_IMAGE_HDR: u32 = 128;

fn area_of(width: i32, height: i32) -> Result<usize, OracleError> {
    let width = u64::try_from(width).map_err(|_| OracleError::BadInput("negative width"))?;
    let height = u64::try_from(height).map_err(|_| OracleError::BadInput("negative height"))?;
    let area = width
        .checked_mul(height)
        .ok_or(OracleError::BadInput("area overflows u64"))?;
    usize::try_from(area).map_err(|_| OracleError::BadInput("area overflows usize"))
}

/// Fills one params blob through the C helper, so Rust never mirrors the
/// C struct layout.
#[expect(unsafe_code)]
// The blob is exactly `oracle_params_size` bytes; the fill helper writes
// that struct and nothing else, and `black` points at four live u16s.
fn fill_params(params: &Params) -> Result<Vec<u8>, OracleError> {
    let size = unsafe { oracle_params_size(RAWPREPARE.as_ptr()) };
    let size = usize::try_from(size).map_err(|_| OracleError::Chain(1))?;
    if size == 0 {
        return Err(OracleError::Chain(1));
    }
    let mut blob = vec![0u8; size];
    unsafe {
        oracle_rawprepare_fill(
            blob.as_mut_ptr().cast::<c_void>(),
            params.crop[0],
            params.crop[1],
            params.crop[2],
            params.crop[3],
            params.black.as_ptr(),
            params.white,
            c_int::from(params.flat_field),
        );
    }
    Ok(blob)
}

/// Runs verbatim `rawprepare` over one tile: commit against the image
/// snapshot, then process; the evolved state comes back beside the pixels.
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed or a buffer is
/// short; [`OracleError::Chain`] when the C chain refuses the run.
#[must_use = "the oracle ran for its output"]
#[expect(unsafe_code)]
// All lengths are checked above: the input holds its region, the output
// holds its own, every pointer stays inside its live allocation for the
// call, and the chain touches nothing else.
pub fn run_rawprepare(
    facts: &Facts,
    params: &Params,
    input: TileInput<'_>,
    rin: Roi,
    rout: Roi,
) -> Result<(Vec<f32>, StateOut), OracleError> {
    let c_facts = facts.abi();
    let c_rin = rin.abi();
    let c_rout = rout.abi();
    let blob = fill_params(params)?;
    let in_area = area_of(rin.width, rin.height)?;
    let out_area = area_of(rout.width, rout.height)?;
    let (in_ptr, input_is_u16) = match input {
        TileInput::U16(words) => {
            if words.len() < in_area {
                return Err(OracleError::BadInput("u16 input shorter than rin"));
            }
            (words.as_ptr().cast::<c_void>(), 1 as c_int)
        }
        TileInput::F32(samples) => {
            if samples.len() < in_area {
                return Err(OracleError::BadInput("f32 input shorter than rin"));
            }
            (samples.as_ptr().cast::<c_void>(), 0 as c_int)
        }
    };
    let mut output = Vec::new();
    output
        .try_reserve_exact(out_area)
        .map_err(|_| OracleError::BadInput("output reservation failed"))?;
    output.resize(out_area, 0.0);
    let mut state = CStateOut {
        enabled: 0,
        filters: 0,
        xtrans: [0; 36],
        processed_maximum: [0.0; 4],
        p_width: 0,
        p_height: 0,
    };
    let names = [RAWPREPARE.as_ptr()];
    let blobs = [blob.as_ptr().cast::<c_void>()];
    let rc = unsafe {
        oracle_run(
            names.as_ptr(),
            blobs.as_ptr(),
            1,
            &raw const c_facts,
            in_ptr,
            input_is_u16,
            &raw const c_rin,
            output.as_mut_ptr().cast::<c_void>(),
            &raw const c_rout,
            &raw mut state,
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok((
        output,
        StateOut {
            enabled: state.enabled != 0,
            filters: state.filters,
            xtrans: state.xtrans,
            processed_maximum: state.processed_maximum,
            p_width: state.p_width,
            p_height: state.p_height,
        },
    ))
}

/// Runs verbatim `modify_roi_out` for committed `params` over `rin`.
///
/// # Errors
///
/// [`OracleError::Chain`] when the C chain refuses the query.
#[must_use = "the oracle ran for its roi"]
#[expect(unsafe_code)]
// Fixed shapes: committed blob in, one roi in, one roi out, all live.
pub fn rawprepare_roi_out(facts: &Facts, params: &Params, rin: Roi) -> Result<Roi, OracleError> {
    let c_facts = facts.abi();
    let c_rin = rin.abi();
    let blob = fill_params(params)?;
    let mut c_rout = CRoi {
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        scale: 1.0,
    };
    let rc = unsafe {
        oracle_roi_map(
            1,
            RAWPREPARE.as_ptr(),
            &raw const c_facts,
            blob.as_ptr().cast::<c_void>(),
            &raw const c_rin,
            &raw mut c_rout,
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok(Roi::from_abi(&c_rout))
}

/// Runs verbatim `modify_roi_in` for committed `params` over `rout`.
///
/// # Errors
///
/// [`OracleError::Chain`] when the C chain refuses the query.
#[must_use = "the oracle ran for its roi"]
#[expect(unsafe_code)]
// Same contract as [`rawprepare_roi_out`], other direction.
pub fn rawprepare_roi_in(facts: &Facts, params: &Params, rout: Roi) -> Result<Roi, OracleError> {
    let c_facts = facts.abi();
    let c_rout = rout.abi();
    let blob = fill_params(params)?;
    let mut c_rin = CRoi {
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        scale: 1.0,
    };
    let rc = unsafe {
        oracle_roi_map(
            0,
            RAWPREPARE.as_ptr(),
            &raw const c_facts,
            blob.as_ptr().cast::<c_void>(),
            &raw const c_rout,
            &raw mut c_rin,
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok(Roi::from_abi(&c_rin))
}

/// Runs verbatim `reload_defaults` for `facts`: the defaults commit falls
/// back to.
///
/// # Errors
///
/// [`OracleError::Chain`] when the C chain refuses the query.
#[must_use = "the oracle ran for its defaults"]
#[expect(unsafe_code)]
// The blob is exactly params-sized; the read helper fills four crop ints,
// four black words, one white word, and one flag, all live locals.
pub fn rawprepare_defaults(facts: &Facts) -> Result<Params, OracleError> {
    let c_facts = facts.abi();
    let size = unsafe { oracle_params_size(RAWPREPARE.as_ptr()) };
    let size = usize::try_from(size).map_err(|_| OracleError::Chain(1))?;
    if size == 0 {
        return Err(OracleError::Chain(1));
    }
    let mut blob = vec![0u8; size];
    let rc = unsafe {
        oracle_defaults(
            RAWPREPARE.as_ptr(),
            &raw const c_facts,
            blob.as_mut_ptr().cast::<c_void>(),
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    let mut crop = [0i32; 4];
    let mut black = [0u16; 4];
    let mut white = 0u16;
    let mut flat = 0 as c_int;
    unsafe {
        oracle_rawprepare_read(
            blob.as_ptr().cast::<c_void>(),
            crop.as_mut_ptr(),
            black.as_mut_ptr(),
            &raw mut white,
            &raw mut flat,
        );
    }
    Ok(Params {
        crop,
        black,
        white,
        flat_field: flat != 0,
    })
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{BufferType, Facts, Params, Roi, TileInput, rawprepare_defaults, run_rawprepare};

    // ARW-shaped facts: RGGB Bayer, black 512, white 15360, no loader crop.
    fn argb_facts() -> Facts {
        Facts {
            width: 64,
            height: 64,
            p_width: 64,
            p_height: 64,
            crop: [0, 0, 0, 0],
            black: [512, 512, 512, 512],
            white: 15360,
            filters: 0x9494_9494,
            xtrans: [0; 36],
            flags: 64,
            buf_channels: 1,
            buf_datatype: BufferType::Uint16,
            id: 1,
        }
    }

    fn unit_params() -> Params {
        Params {
            crop: [0, 0, 0, 0],
            black: [512, 512, 512, 512],
            white: 15360,
            flat_field: false,
        }
    }

    #[test]
    fn checkpoint_runs_verbatim_process_on_a_synthetic_tile() {
        let facts = argb_facts();
        let params = unit_params();
        // 8x8 ramp straddling black (512) and white (15360).
        let input: Vec<f32> = (0..64i16).map(|i| 500.0 + f32::from(i) * 250.0).collect();
        let rin = Roi {
            x: 0,
            y: 0,
            width: 8,
            height: 8,
            scale: 1.0,
        };
        let (output, state) =
            run_rawprepare(&facts, &params, TileInput::F32(&input), rin, rin).expect("oracle runs");
        assert!(state.enabled);
        assert_eq!(state.filters, 0x9494_9494);
        assert_eq!(state.processed_maximum, [1.0; 4]);
        assert_eq!((state.p_width, state.p_height), (64, 64));
        // Hand-computed: (in - 512) / (15360 - 512), Bayer-uniform levels.
        for (i, pixel) in output.iter().enumerate() {
            let want = (input[i] - 512.0) / 14848.0;
            assert_eq!(*pixel, want, "pixel {i}");
        }
    }

    #[test]
    fn u16_leg_matches_f32_leg_on_exact_casts() {
        let facts = argb_facts();
        let params = unit_params();
        let words: Vec<u16> = (0..64)
            .map(|i| u16::try_from(500 + i * 250).unwrap())
            .collect();
        let floats: Vec<f32> = words.iter().map(|w| f32::from(*w)).collect();
        let rin = Roi {
            x: 0,
            y: 0,
            width: 8,
            height: 8,
            scale: 1.0,
        };
        let (words_out, _) = run_rawprepare(&facts, &params, TileInput::U16(&words), rin, rin)
            .expect("u16 leg runs");
        let (floats_out, _) = run_rawprepare(&facts, &params, TileInput::F32(&floats), rin, rin)
            .expect("f32 leg runs");
        assert_eq!(words_out, floats_out);
    }

    #[test]
    fn defaults_come_from_the_image_facts() {
        let mut facts = argb_facts();
        facts.crop = [4, 6, 8, 10];
        let defaults = rawprepare_defaults(&facts).expect("defaults run");
        assert_eq!(defaults.crop, [4, 6, 8, 10]);
        assert_eq!(defaults.black, [512, 512, 512, 512]);
        assert_eq!(defaults.white, 15360);
        assert!(!defaults.flat_field);
    }
}
