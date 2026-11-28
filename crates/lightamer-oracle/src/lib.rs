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
    temp_enabled: i32,
    temp_coeffs: [f32; 4],
    temp_late: i32,
}

// Mirrors `oracle_temp_facts`: base facts plus white-balance facts.
#[repr(C)]
struct CTempFacts {
    base: CFacts,
    wb: [f32; 4],
    xyz_to_cam: [f32; 9],
    has_xyz: i32,
}

// The C side asserts the same four sizes (chain.c `_Static_assert`).
const _: () = assert!(size_of::<CFacts>() == 100);
const _: () = assert!(size_of::<CRoi>() == 20);
const _: () = assert!(size_of::<CStateOut>() == 92);
const _: () = assert!(size_of::<CTempFacts>() == 156);

// The chain entry points plus the params fill/read pairs. Argument
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
        pipe_type: c_int,
        planes: c_int,
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
    fn oracle_hotpixels_fill(
        out: *mut c_void,
        strength: f32,
        threshold: f32,
        markfixed: c_int,
        permissive: c_int,
    );
    fn oracle_run_temp(
        names: *const *const c_char,
        params_list: *const *const c_void,
        count: c_int,
        facts: *const CTempFacts,
        input: *const c_void,
        input_is_u16: c_int,
        rin: *const CRoi,
        output: *mut c_void,
        rout: *const CRoi,
        state: *mut CStateOut,
        pipe_type: c_int,
        planes: c_int,
    ) -> c_int;
    fn oracle_temperature_fill(
        out: *mut c_void,
        red: f32,
        green: f32,
        blue: f32,
        various: f32,
        preset: c_int,
    );
    fn oracle_temperature_find_coeffs(facts: *const CTempFacts, coeffs_out: *mut f64) -> c_int;
    fn oracle_temperature_bogus(facts: *const CTempFacts, bwb_out: *mut f64) -> c_int;
    fn oracle_temperature_temp2mul(
        facts: *const CTempFacts,
        temp: f64,
        tint: f64,
        mul_out: *mut f64,
    ) -> c_int;
    fn oracle_temperature_mul2temp(
        facts: *const CTempFacts,
        red: f32,
        green: f32,
        blue: f32,
        various: f32,
        temp_out: *mut f32,
        tint_out: *mut f32,
    ) -> c_int;
    fn oracle_temperature_tint_xyz(temp: f64, tint: f64, xyz_out: *mut f64) -> c_int;
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

/// Which render a chain run serves: the oracle-side pipe type. Values are
/// the `dt_dev_pixelpipe_type_t` bits (`src/develop/pixelpipe.h:41-57`),
/// so commit-time kind checks (`dt_pipe_is_thumb`, `dt_pipe_is_export`)
/// read what upstream reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PipeType {
    /// Full-resolution interactive pipe.
    Full,
    /// Export pipe.
    Export,
    /// Preview pipe.
    Preview,
    /// Thumbnail pipe.
    Thumbnail,
}

impl PipeType {
    fn bits(self) -> c_int {
        match self {
            PipeType::Full => 1 << 1,
            PipeType::Export => 1 << 0,
            PipeType::Preview => 1 << 2,
            PipeType::Thumbnail => 1 << 3,
        }
    }
}

/// hotpixels parameters: fix strength, detection threshold, and the two
/// switches (`hotpixels.c:35-41`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HotParams {
    /// Fix strength, 0..=1 (halved into the neighbor multiplier).
    pub strength: f32,
    /// Detection threshold: pixels at or below it are never hot.
    pub threshold: f32,
    /// Paint fixed pixels (forced off on thumbnail/export pipes).
    pub markfixed: bool,
    /// Detect by 3 neighbors instead of 4.
    pub permissive: bool,
}

/// temperature parameters: four channel multipliers plus the preset tag
/// (`temperature.c:68-75`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TempParams {
    /// Red multiplier, 0..=8.
    pub red: f32,
    /// Green multiplier, 0..=8.
    pub green: f32,
    /// Blue multiplier, 0..=8.
    pub blue: f32,
    /// Fourth-channel multiplier (G2 on four-color Bayer), 0..=8.
    pub various: f32,
    /// Preset tag: -1 unknown, 0 as-shot, 1 spot, 2 user, 3 D65, 4 D65 late.
    pub preset: i32,
}

/// White-balance facts for temperature runs: base facts plus as-shot
/// multipliers and the optional rawspeed XYZ-to-camera matrix. Separate
/// from [`Facts`] so the base struct (and its tests) stays frozen.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TempFacts {
    /// Base image facts.
    pub base: Facts,
    /// As-shot white-balance multipliers, R/G/B/G2.
    pub wb: [f32; 4],
    /// XYZ(D65)-to-camera matrix, row-major 3x3; [`None`] marks the slot
    /// invalid (no matrix leg runs).
    pub xyz_to_cam: Option<[f32; 9]>,
}

impl TempFacts {
    /// Packs the ABI mirror: base facts plus white-balance facts.
    fn abi(self) -> CTempFacts {
        CTempFacts {
            base: self.base.abi(),
            wb: self.wb,
            xyz_to_cam: self.xyz_to_cam.unwrap_or([0.0; 9]),
            has_xyz: c_int::from(self.xyz_to_cam.is_some()),
        }
    }
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
    /// Whether a temperature stage published white balance.
    pub temp_enabled: bool,
    /// Published white-balance coeffs (zeros when unpublished).
    pub temp_coeffs: [f32; 4],
    /// Late-correction flag (`dev->chroma`, written by commit and process).
    pub temp_late: bool,
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

/// Module table name of the second transcribed module.
pub const HOTPPIXELS: &CStr = c"hotpixels";

/// Module table name of the third transcribed module.
pub const TEMPERATURE: &CStr = c"temperature";

/// `DT_IMAGE_RAW` (`src/common/image.h`): the capture needs demosaicing.
pub const DT_IMAGE_RAW: u32 = 64;

/// `DT_IMAGE_HDR` (`src/common/image.h`): float-bits levels.
pub const DT_IMAGE_HDR: u32 = 128;

/// `DT_IMAGE_S_RAW` (`src/common/image.h`): small-RAW container.
pub const DT_IMAGE_S_RAW: u32 = 1 << 17;

/// `DT_IMAGE_MONOCHROME` (`src/common/image.h`): detected monochrome.
pub const DT_IMAGE_MONOCHROME: u32 = 32768;

/// `DT_IMAGE_MONOCHROME_BAYER` (`src/common/image.h`): mono via demosaic.
pub const DT_IMAGE_MONOCHROME_BAYER: u32 = 1 << 19;

/// `DT_IMAGE_4BAYER` (`src/common/image.h`): four-color Bayer.
pub const DT_IMAGE_4BAYER: u32 = 16384;

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

/// Fills one hotpixels params blob through the C helper.
#[expect(unsafe_code)]
// The blob is exactly `oracle_params_size` bytes; the fill helper writes
// that struct and nothing else.
fn fill_hotparams(params: &HotParams) -> Result<Vec<u8>, OracleError> {
    let size = unsafe { oracle_params_size(HOTPPIXELS.as_ptr()) };
    let size = usize::try_from(size).map_err(|_| OracleError::Chain(1))?;
    if size == 0 {
        return Err(OracleError::Chain(1));
    }
    let mut blob = vec![0u8; size];
    unsafe {
        oracle_hotpixels_fill(
            blob.as_mut_ptr().cast::<c_void>(),
            params.strength,
            params.threshold,
            c_int::from(params.markfixed),
            c_int::from(params.permissive),
        );
    }
    Ok(blob)
}

/// Fills one temperature params blob through the C helper.
#[expect(unsafe_code)]
// The blob is exactly `oracle_params_size` bytes; the fill helper writes
// that struct and nothing else.
fn fill_tempparams(params: &TempParams) -> Result<Vec<u8>, OracleError> {
    let size = unsafe { oracle_params_size(TEMPERATURE.as_ptr()) };
    let size = usize::try_from(size).map_err(|_| OracleError::Chain(1))?;
    if size == 0 {
        return Err(OracleError::Chain(1));
    }
    let mut blob = vec![0u8; size];
    unsafe {
        oracle_temperature_fill(
            blob.as_mut_ptr().cast::<c_void>(),
            params.red,
            params.green,
            params.blue,
            params.various,
            c_int::from(params.preset),
        );
    }
    Ok(blob)
}

/// Floats per pixel hotpixels reads and writes: 4 for a monochrome
/// small-RAW (`pure_monochrome`), 1 otherwise — the same flag read
/// `commit_params` makes (`hotpixels.c:379-380`).
fn hotpixels_planes(flags: u32) -> usize {
    if flags & (DT_IMAGE_S_RAW | DT_IMAGE_MONOCHROME) == DT_IMAGE_S_RAW | DT_IMAGE_MONOCHROME {
        4
    } else {
        1
    }
}

/// Checks the tile buffers for a chain run: the input holds its region
/// times its stride, the output is reserved for its own. The returned
/// pointer borrows `input` and stays valid while it lives.
fn prepare_buffers(
    input: TileInput<'_>,
    in_planes: usize,
    rin: Roi,
    rout: Roi,
    out_planes: usize,
) -> Result<(*const c_void, c_int, Vec<f32>), OracleError> {
    let in_area = area_of(rin.width, rin.height)?
        .checked_mul(in_planes)
        .ok_or(OracleError::BadInput("input area overflows"))?;
    let out_area = area_of(rout.width, rout.height)?
        .checked_mul(out_planes)
        .ok_or(OracleError::BadInput("output area overflows"))?;
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
    Ok((in_ptr, input_is_u16, output))
}

/// Reads the post-run C state into the owned report.
fn read_state(state: &CStateOut) -> StateOut {
    StateOut {
        enabled: state.enabled != 0,
        filters: state.filters,
        xtrans: state.xtrans,
        processed_maximum: state.processed_maximum,
        p_width: state.p_width,
        p_height: state.p_height,
        temp_enabled: state.temp_enabled != 0,
        temp_coeffs: state.temp_coeffs,
        temp_late: state.temp_late != 0,
    }
}

/// Runs one chain over one tile: every entry point funnels here. `in_planes`
/// and `out_planes` are scalars per pixel on each side (hotpixels reads and
/// writes 4-wide on a monochrome small-RAW, 1-wide otherwise); `out_planes`
/// also reaches the C side, which sizes middle buffers and disabled-stage
/// copies by it.
#[expect(unsafe_code)]
// All lengths are checked below: the input holds its region times its
// stride, the output holds its own, every pointer stays inside its live
// allocation for the call, and the chain touches nothing else.
#[allow(clippy::too_many_arguments)]
fn run_chain(
    names: &[*const c_char],
    blobs: &[*const c_void],
    facts: &Facts,
    input: TileInput<'_>,
    in_planes: usize,
    rin: Roi,
    rout: Roi,
    kind: PipeType,
    out_planes: usize,
) -> Result<(Vec<f32>, StateOut), OracleError> {
    let c_facts = facts.abi();
    let c_rin = rin.abi();
    let c_rout = rout.abi();
    let (in_ptr, input_is_u16, mut output) =
        prepare_buffers(input, in_planes, rin, rout, out_planes)?;
    let mut state = CStateOut {
        enabled: 0,
        filters: 0,
        xtrans: [0; 36],
        processed_maximum: [0.0; 4],
        p_width: 0,
        p_height: 0,
        temp_enabled: 0,
        temp_coeffs: [0.0; 4],
        temp_late: 0,
    };
    let count = c_int::try_from(names.len()).map_err(|_| OracleError::Chain(1))?;
    let rc = unsafe {
        oracle_run(
            names.as_ptr(),
            blobs.as_ptr(),
            count,
            &raw const c_facts,
            in_ptr,
            input_is_u16,
            &raw const c_rin,
            output.as_mut_ptr().cast::<c_void>(),
            &raw const c_rout,
            &raw mut state,
            kind.bits(),
            c_int::try_from(out_planes).map_err(|_| OracleError::BadInput("planes overflow"))?,
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok((output, read_state(&state)))
}

/// Runs one temperature-bearing chain over one tile: [`run_chain`] with
/// white-balance facts (`oracle_run_temp` on the C side).
#[expect(unsafe_code)]
// Same contract as [`run_chain`]: checked buffers, live pointers, the
// chain touches nothing else.
#[allow(clippy::too_many_arguments)]
fn run_temp_chain(
    names: &[*const c_char],
    blobs: &[*const c_void],
    facts: &TempFacts,
    input: TileInput<'_>,
    in_planes: usize,
    rin: Roi,
    rout: Roi,
    kind: PipeType,
    out_planes: usize,
) -> Result<(Vec<f32>, StateOut), OracleError> {
    let c_facts = facts.abi();
    let c_rin = rin.abi();
    let c_rout = rout.abi();
    let (in_ptr, input_is_u16, mut output) =
        prepare_buffers(input, in_planes, rin, rout, out_planes)?;
    let mut state = CStateOut {
        enabled: 0,
        filters: 0,
        xtrans: [0; 36],
        processed_maximum: [0.0; 4],
        p_width: 0,
        p_height: 0,
        temp_enabled: 0,
        temp_coeffs: [0.0; 4],
        temp_late: 0,
    };
    let count = c_int::try_from(names.len()).map_err(|_| OracleError::Chain(1))?;
    let rc = unsafe {
        oracle_run_temp(
            names.as_ptr(),
            blobs.as_ptr(),
            count,
            &raw const c_facts,
            in_ptr,
            input_is_u16,
            &raw const c_rin,
            output.as_mut_ptr().cast::<c_void>(),
            &raw const c_rout,
            &raw mut state,
            kind.bits(),
            c_int::try_from(out_planes).map_err(|_| OracleError::BadInput("planes overflow"))?,
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok((output, read_state(&state)))
}

/// Runs verbatim `rawprepare` over one tile: commit against the image
/// snapshot, then process; the evolved state comes back beside the pixels.
/// The pipe kind is [`PipeType::Full`] (rawprepare never reads it).
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed or a buffer is
/// short; [`OracleError::Chain`] when the C chain refuses the run.
#[must_use = "the oracle ran for its output"]
pub fn run_rawprepare(
    facts: &Facts,
    params: &Params,
    input: TileInput<'_>,
    rin: Roi,
    rout: Roi,
) -> Result<(Vec<f32>, StateOut), OracleError> {
    let blob = fill_params(params)?;
    let names = [RAWPREPARE.as_ptr()];
    let blobs = [blob.as_ptr().cast::<c_void>()];
    run_chain(
        &names,
        &blobs,
        facts,
        input,
        1,
        rin,
        rout,
        PipeType::Full,
        1,
    )
}

/// Runs verbatim `hotpixels` over one tile: commit against the image
/// snapshot (the kind decides `markfixed`), then process; the evolved
/// state comes back beside the pixels. Float input only: upstream reads
/// the `TYPE_FLOAT` buffer unconditionally.
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed or a buffer is
/// short; [`OracleError::Chain`] when the C chain refuses the run.
#[must_use = "the oracle ran for its output"]
pub fn run_hotpixels(
    facts: &Facts,
    params: &HotParams,
    kind: PipeType,
    input: &[f32],
    rin: Roi,
    rout: Roi,
) -> Result<(Vec<f32>, StateOut), OracleError> {
    let blob = fill_hotparams(params)?;
    let names = [HOTPPIXELS.as_ptr()];
    let blobs = [blob.as_ptr().cast::<c_void>()];
    let planes = hotpixels_planes(facts.flags);
    run_chain(
        &names,
        &blobs,
        facts,
        TileInput::F32(input),
        planes,
        rin,
        rout,
        kind,
        planes,
    )
}

/// Runs verbatim `rawprepare` into verbatim `hotpixels` over one tile:
/// the two-module chain entry. Geometry threads through rawprepare's roi
/// (hotpixels is identity); the caller passes `rin` only. Mosaic runs
/// only: a mono small-RAW would enter hotpixels 4-wide behind rawprepare's
/// 1-wide middle, which no caller needs, so it refuses loudly instead.
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed, a buffer is
/// short, or the facts are a mono small-RAW; [`OracleError::Chain`] when
/// the C chain refuses the run.
#[must_use = "the oracle ran for its output"]
pub fn run_rawprepare_hotpixels(
    facts: &Facts,
    rawprepare: &Params,
    hotpixels: &HotParams,
    kind: PipeType,
    input: TileInput<'_>,
    rin: Roi,
) -> Result<(Vec<f32>, StateOut, Roi), OracleError> {
    if hotpixels_planes(facts.flags) != 1 {
        return Err(OracleError::BadInput("two-module chain is mosaic-only"));
    }
    let rp_blob = fill_params(rawprepare)?;
    let hp_blob = fill_hotparams(hotpixels)?;
    let rout = rawprepare_roi_out(facts, rawprepare, rin)?;
    let names = [RAWPREPARE.as_ptr(), HOTPPIXELS.as_ptr()];
    let blobs = [
        rp_blob.as_ptr().cast::<c_void>(),
        hp_blob.as_ptr().cast::<c_void>(),
    ];
    let (output, state) = run_chain(&names, &blobs, facts, input, 1, rin, rout, kind, 1)?;
    Ok((output, state, rout))
}

/// Runs verbatim `temperature` over one tile: commit against the image
/// snapshot, then process; the evolved state comes back beside the pixels.
/// Float input only: upstream reads the `TYPE_FLOAT` buffer unconditionally.
/// `planes` is scalars per pixel (1 mosaic, 4 non-mosaiced RGBA).
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed, a buffer is
/// short, or `planes` is neither 1 nor 4; [`OracleError::Chain`] when the
/// C chain refuses the run.
#[must_use = "the oracle ran for its output"]
pub fn run_temperature(
    facts: &TempFacts,
    params: &TempParams,
    kind: PipeType,
    input: &[f32],
    rin: Roi,
    rout: Roi,
    planes: usize,
) -> Result<(Vec<f32>, StateOut), OracleError> {
    if planes != 1 && planes != 4 {
        return Err(OracleError::BadInput("temperature planes must be 1 or 4"));
    }
    let blob = fill_tempparams(params)?;
    let names = [TEMPERATURE.as_ptr()];
    let blobs = [blob.as_ptr().cast::<c_void>()];
    run_temp_chain(
        &names,
        &blobs,
        facts,
        TileInput::F32(input),
        planes,
        rin,
        rout,
        kind,
        planes,
    )
}

/// Runs verbatim `rawprepare` into verbatim `temperature` over one tile:
/// the RAW-head chain prefix (upstream runs temperature before hotpixels).
/// Geometry threads through rawprepare's roi (temperature is identity);
/// the caller passes `rin` only. Mosaic runs only.
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed or a buffer is
/// short; [`OracleError::Chain`] when the C chain refuses the run.
#[must_use = "the oracle ran for its output"]
pub fn run_rawprepare_temperature(
    facts: &TempFacts,
    rawprepare: &Params,
    temperature: &TempParams,
    kind: PipeType,
    input: TileInput<'_>,
    rin: Roi,
) -> Result<(Vec<f32>, StateOut, Roi), OracleError> {
    let rp_blob = fill_params(rawprepare)?;
    let tp_blob = fill_tempparams(temperature)?;
    let rout = rawprepare_roi_out(&facts.base, rawprepare, rin)?;
    let names = [RAWPREPARE.as_ptr(), TEMPERATURE.as_ptr()];
    let blobs = [
        rp_blob.as_ptr().cast::<c_void>(),
        tp_blob.as_ptr().cast::<c_void>(),
    ];
    let (output, state) = run_temp_chain(&names, &blobs, facts, input, 1, rin, rout, kind, 1)?;
    Ok((output, state, rout))
}

/// Runs verbatim `rawprepare` into `temperature` into `hotpixels` over one
/// tile: the three-module RAW-head chain in upstream order. Geometry
/// threads through rawprepare's roi (both followers are identity); the
/// caller passes `rin` only. Mosaic runs only: a mono small-RAW would
/// enter hotpixels 4-wide behind 1-wide middles, which no caller needs.
///
/// # Errors
///
/// [`OracleError::BadInput`] when a region is malformed, a buffer is
/// short, or the facts are a mono small-RAW; [`OracleError::Chain`] when
/// the C chain refuses the run.
#[must_use = "the oracle ran for its output"]
#[allow(clippy::too_many_arguments)]
pub fn run_rawprepare_temperature_hotpixels(
    facts: &TempFacts,
    rawprepare: &Params,
    temperature: &TempParams,
    hotpixels: &HotParams,
    kind: PipeType,
    input: TileInput<'_>,
    rin: Roi,
) -> Result<(Vec<f32>, StateOut, Roi), OracleError> {
    if hotpixels_planes(facts.base.flags) != 1 {
        return Err(OracleError::BadInput("three-module chain is mosaic-only"));
    }
    let rp_blob = fill_params(rawprepare)?;
    let tp_blob = fill_tempparams(temperature)?;
    let hp_blob = fill_hotparams(hotpixels)?;
    let rout = rawprepare_roi_out(&facts.base, rawprepare, rin)?;
    let names = [
        RAWPREPARE.as_ptr(),
        TEMPERATURE.as_ptr(),
        HOTPPIXELS.as_ptr(),
    ];
    let blobs = [
        rp_blob.as_ptr().cast::<c_void>(),
        tp_blob.as_ptr().cast::<c_void>(),
        hp_blob.as_ptr().cast::<c_void>(),
    ];
    let (output, state) = run_temp_chain(&names, &blobs, facts, input, 1, rin, rout, kind, 1)?;
    Ok((output, state, rout))
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

/// Runs verbatim `_find_coeffs` for `facts`: as-shot multipliers when the
/// capture carries sane ones, else the bogus-daylight matrix leg, else the
/// hardcoded fallback (the preset-table leg is empty here — see the
/// `dt_wb_presets_count` stub row — so preset-less cameras fall through to
/// the fallback exactly as upstream does without a table hit).
///
/// # Errors
///
/// [`OracleError::Chain`] when the C side refuses the query.
#[must_use = "the oracle ran for its coeffs"]
#[expect(unsafe_code)]
// Fixed shapes: facts in, four doubles out, all live.
pub fn temperature_find_coeffs(facts: &TempFacts) -> Result<[f64; 4], OracleError> {
    let c_facts = facts.abi();
    let mut coeffs = [0.0f64; 4];
    let rc = unsafe { oracle_temperature_find_coeffs(&raw const c_facts, coeffs.as_mut_ptr()) };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok(coeffs)
}

/// Runs verbatim `_calculate_bogus_daylight_wb` for `facts`: green-
/// normalized daylight multipliers from the camera matrix. Returns the
/// multipliers plus whether the matrix leg ran ([`None`] = unsupported
/// capture or no valid matrix, all-ones multipliers).
///
/// # Errors
///
/// [`OracleError::Chain`] when the C side refuses the query.
#[must_use = "the oracle ran for its multipliers"]
#[expect(unsafe_code)]
// Fixed shapes: facts in, four doubles out, all live.
pub fn temperature_bogus(facts: &TempFacts) -> Result<Option<[f64; 4]>, OracleError> {
    let c_facts = facts.abi();
    let mut bwb = [0.0f64; 4];
    let rc = unsafe { oracle_temperature_bogus(&raw const c_facts, bwb.as_mut_ptr()) };
    // Upstream polarity: 0 = matrix found and used, 1 = unsupported.
    match rc {
        0 => Ok(Some(bwb)),
        1 => Ok(None),
        other => Err(OracleError::Chain(other)),
    }
}

/// Runs verbatim `_temp2mul` for `facts`: temperature + tint to channel
/// multipliers through the prepared camera matrices.
///
/// # Errors
///
/// [`OracleError::Chain`] when the C side refuses the query.
#[must_use = "the oracle ran for its multipliers"]
#[expect(unsafe_code)]
// Fixed shapes: facts in, four doubles out, all live.
pub fn temperature_temp_to_mul(
    facts: &TempFacts,
    temp_kelvin: f64,
    tint: f64,
) -> Result<[f64; 4], OracleError> {
    let c_facts = facts.abi();
    let mut mul = [0.0f64; 4];
    let rc = unsafe {
        oracle_temperature_temp2mul(&raw const c_facts, temp_kelvin, tint, mul.as_mut_ptr())
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok(mul)
}

/// Runs verbatim `_mul2temp` for `facts`: channel multipliers back to
/// temperature + tint through the prepared camera matrices.
///
/// # Errors
///
/// [`OracleError::Chain`] when the C side refuses the query.
#[must_use = "the oracle ran for its temperature"]
#[expect(unsafe_code)]
// Fixed shapes: facts in, two floats out, all live.
pub fn temperature_mul_to_temp(
    facts: &TempFacts,
    coeffs: [f32; 4],
) -> Result<(f32, f32), OracleError> {
    let c_facts = facts.abi();
    let mut temp = 0.0f32;
    let mut tint = 0.0f32;
    let rc = unsafe {
        oracle_temperature_mul2temp(
            &raw const c_facts,
            coeffs[0],
            coeffs[1],
            coeffs[2],
            coeffs[3],
            &raw mut temp,
            &raw mut tint,
        )
    };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok((temp, tint))
}

/// Runs verbatim `_temperature_tint_to_XYZ`: temperature + tint to CIE XYZ
/// through the blackbody/daylight spectrum (lcms2 white point included).
///
/// # Errors
///
/// [`OracleError::Chain`] when the C side refuses the query.
#[must_use = "the oracle ran for its white"]
#[expect(unsafe_code)]
// Fixed shapes: two doubles in, three doubles out, all live.
pub fn temperature_tint_xyz(temp_kelvin: f64, tint: f64) -> Result<[f64; 3], OracleError> {
    let mut xyz = [0.0f64; 3];
    let rc = unsafe { oracle_temperature_tint_xyz(temp_kelvin, tint, xyz.as_mut_ptr()) };
    if rc != 0 {
        return Err(OracleError::Chain(rc));
    }
    Ok(xyz)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{
        BufferType, DT_IMAGE_MONOCHROME, DT_IMAGE_S_RAW, Facts, HotParams, OracleError, Params,
        PipeType, Roi, TempFacts, TempParams, TileInput, rawprepare_defaults, run_hotpixels,
        run_rawprepare, run_rawprepare_hotpixels, run_temperature, temperature_bogus,
        temperature_find_coeffs, temperature_tint_xyz,
    };

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

    #[test]
    fn hotpixels_fixes_an_isolated_hot_pixel() {
        let facts = argb_facts();
        let params = HotParams {
            strength: 0.25,
            threshold: 0.05,
            markfixed: false,
            permissive: false,
        };
        let mut input = vec![0.5f32; 64];
        input[3 * 8 + 3] = 5.0;
        let rin = Roi {
            x: 0,
            y: 0,
            width: 8,
            height: 8,
            scale: 1.0,
        };
        let (output, state) =
            run_hotpixels(&facts, &params, PipeType::Full, &input, rin, rin).expect("oracle runs");
        assert!(state.enabled);
        // The hot pixel drops to the brightest same-color neighbor; the
        // flat field around it is untouched.
        assert_eq!(output[3 * 8 + 3], 0.5);
        for (i, pixel) in output.iter().enumerate() {
            if i != 3 * 8 + 3 {
                assert_eq!(*pixel, input[i], "pixel {i}");
            }
        }
    }

    #[test]
    fn markfixed_paints_on_full_and_drops_on_export() {
        let facts = argb_facts();
        let marked = HotParams {
            strength: 0.25,
            threshold: 0.05,
            markfixed: true,
            permissive: false,
        };
        let plain = HotParams {
            markfixed: false,
            ..marked
        };
        let mut input = vec![0.5f32; 64];
        input[3 * 8 + 3] = 5.0;
        let rin = Roi {
            x: 0,
            y: 0,
            width: 8,
            height: 8,
            scale: 1.0,
        };
        let (full_out, _) =
            run_hotpixels(&facts, &marked, PipeType::Full, &input, rin, rin).expect("full runs");
        let (export_out, _) = run_hotpixels(&facts, &marked, PipeType::Export, &input, rin, rin)
            .expect("export runs");
        let (plain_out, _) =
            run_hotpixels(&facts, &plain, PipeType::Export, &input, rin, rin).expect("plain runs");
        // Same-color cross around (3,3): (3,1), (3,5), (3,7) at stride 2.
        assert_eq!(full_out[3 * 8 + 1], 5.0);
        assert_eq!(full_out[3 * 8 + 5], 5.0);
        assert_eq!(full_out[3 * 8 + 7], 5.0);
        assert_ne!(full_out, export_out);
        assert_eq!(export_out, plain_out);
    }

    // Mono small-RAW facts: no RAW bit, 4-wide float buffer.
    fn mono_facts() -> Facts {
        let mut facts = argb_facts();
        facts.filters = 0;
        facts.flags = DT_IMAGE_S_RAW | DT_IMAGE_MONOCHROME;
        facts.buf_channels = 4;
        facts.buf_datatype = BufferType::Float;
        facts
    }

    #[test]
    fn two_module_chain_refuses_mono() {
        let facts = mono_facts();
        let rin = Roi {
            x: 0,
            y: 0,
            width: 8,
            height: 8,
            scale: 1.0,
        };
        let input = vec![0.5f32; 8 * 8 * 4];
        let params = HotParams {
            strength: 0.25,
            threshold: 0.05,
            markfixed: false,
            permissive: false,
        };
        let err = run_rawprepare_hotpixels(
            &facts,
            &unit_params(),
            &params,
            PipeType::Full,
            TileInput::F32(&input),
            rin,
        )
        .expect_err("mono chain refuses");
        assert!(
            matches!(err, OracleError::BadInput(_)),
            "loud refusal: {err}"
        );
    }

    #[test]
    fn disabled_four_wide_stage_passes_everything_through() {
        let facts = mono_facts();
        let params = HotParams {
            strength: 0.0,
            threshold: 0.05,
            markfixed: false,
            permissive: false,
        };
        let input: Vec<f32> = (0..256i16).map(|i| f32::from(i % 251) * 0.01).collect();
        let rin = Roi {
            x: 0,
            y: 0,
            width: 8,
            height: 8,
            scale: 1.0,
        };
        let (output, state) =
            run_hotpixels(&facts, &params, PipeType::Full, &input, rin, rin).expect("oracle runs");
        assert!(!state.enabled, "strength zero disables the piece");
        assert_eq!(output, input, "all four lanes pass through");
    }

    fn temp_facts() -> TempFacts {
        TempFacts {
            base: argb_facts(),
            wb: [2.5273, 1.0, 1.7344, 0.0],
            xyz_to_cam: None,
        }
    }

    #[test]
    fn temperature_smoke_multiplies_and_publishes() {
        let facts = temp_facts();
        let params = TempParams {
            red: 2.0,
            green: 1.0,
            blue: 1.5,
            various: 1.0,
            preset: 0,
        };
        // 4x4 ones on RGGB: R cells double, B cells gain 1.5, G stays.
        let input = vec![1.0f32; 16];
        let rin = Roi {
            x: 0,
            y: 0,
            width: 4,
            height: 4,
            scale: 1.0,
        };
        let (output, state) = run_temperature(&facts, &params, PipeType::Full, &input, rin, rin, 1)
            .expect("oracle runs");
        // RGGB rows: R G R G / G B G B, repeated.
        let want: [f32; 16] = [
            2.0, 1.0, 2.0, 1.0, //
            1.0, 1.5, 1.0, 1.5, //
            2.0, 1.0, 2.0, 1.0, //
            1.0, 1.5, 1.0, 1.5, //
        ];
        assert_eq!(output, want);
        assert!(state.temp_enabled);
        assert_eq!(state.temp_coeffs, [2.0, 1.0, 1.5, 1.0]);
        assert_eq!(state.processed_maximum, [2.0, 1.0, 1.5, 1.0]);
    }

    #[test]
    fn temperature_find_coeffs_prefers_sane_as_shot() {
        let coeffs = temperature_find_coeffs(&temp_facts()).expect("oracle runs");
        // Widened f32s, like the C `double` copy of `wb_coeffs`.
        let want = [f64::from(2.5273f32), 1.0, f64::from(1.7344f32), 0.0];
        assert_eq!(coeffs, want);
    }

    #[test]
    fn temperature_find_coeffs_falls_back_without_wb_or_matrix() {
        let mut facts = temp_facts();
        facts.wb = [0.0; 4];
        let coeffs = temperature_find_coeffs(&facts).expect("oracle runs");
        assert_eq!(coeffs, [2.0, 1.0, 1.5, 1.0]);
    }

    #[test]
    fn temperature_bogus_needs_a_matrix() {
        assert!(
            temperature_bogus(&temp_facts())
                .expect("oracle runs")
                .is_none(),
            "no matrix, no bogus daylight"
        );
    }

    #[test]
    fn temperature_tint_xyz_runs_finite() {
        let xyz = temperature_tint_xyz(5000.0, 1.0).expect("oracle runs");
        assert!(
            xyz.iter().all(|v| v.is_finite() && *v > 0.0),
            "positive finite XYZ: {xyz:?}"
        );
    }
}
