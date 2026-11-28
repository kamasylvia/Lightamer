// SPDX-License-Identifier: GPL-3.0-or-later
// Transcribed from darktable src/iop/temperature.c @ release-5.7.0
// (Copyright (C) 2009-2026 darktable developers).
// Modified for Lightamer: 2026-11-28 transcribed to Rust (process three
// legs, commit, _publish_chroma, _find_coeffs incl. bogus daylight, the
// temp/tint <-> coeffs conversions with their spectrum; GUI, spot preset,
// `OpenCL` not transcribed).
//! `temperature`: scale raw channels to balance white.
//!
//! Upstream anchors (`src/iop/temperature.c` @ `release-5.7.0`): `process`
//! `:532-639`, `commit_params` `:687-728`, `_publish_chroma` `:515-530`,
//! `_find_coeffs` `:1448-1511`, `_calculate_bogus_daylight_wb`
//! `:1382-1410`, `_prepare_matrices` `:1412-1446`, the conversions
//! `:281-502`, `init_pipe`/`cleanup_pipe` `:730-743`. Matrix legs come from
//! `src/common/colorspaces.c:2311-2456`, the spectrum tables from
//! `src/external/cie_colorimetric_tables.c` (see `cie_tables`).
mod cie_tables;

use rayon::prelude::*;
use std::sync::Arc;

use lightamer_iop_traits::{
    CfaColor, CfaPattern, ColorRequirement, ColorSpace, CommitData, HistoryKeys, ImageInfo,
    IopModule, ModuleDesc, ModuleFlags, ModuleGroup, OrderKey, OrderKeys, ParamField, ParamType,
    ParamsDesc, PipeError, PipeKind, PipeState, Plane, PlaneMut, RawFacts, Roi, SharedModule,
    get_float, get_int, par_map_rows,
};
use serde_json::{Map, Value};

use cie_tables::{CIE_1931, CIE_DAYLIGHT};

/// Coldest temperature the conversions admit (`DT_IOP_LOWEST_TEMPERATURE`).
const LOWEST_TEMP: f64 = 1901.0;
/// Hottest temperature the conversions admit (`DT_IOP_HIGHEST_TEMPERATURE`).
const HIGHEST_TEMP: f64 = 25000.0;
/// Smallest tint the conversions admit (`DT_IOP_LOWEST_TINT`).
const LOWEST_TINT: f64 = 0.135;
/// Largest tint the conversions admit (`DT_IOP_HIGHEST_TINT`).
const HIGHEST_TINT: f64 = 2.326;
/// Blackbody/daylight spectrum switch (`INITIALBLACKBODYTEMPERATURE`).
const BLACKBODY_SWITCH: f64 = 4000.0;

/// D65 white point, fallback when lcms2 refuses a temperature: upstream
/// initializes its `WhitePoint` to `D65xyY` and ignores the call's return,
/// so a refusal silently keeps D65 (`temperature.c:323-329`).
const D65_X: f64 = 0.31271;
/// D65 white point y (see [`D65_X`]).
const D65_Y: f64 = 0.32902;

/// Preset tag: unknown (`DT_IOP_TEMP_UNKNOWN`).
pub const PRESET_UNKNOWN: i32 = -1;
/// Preset tag: as-shot (`DT_IOP_TEMP_AS_SHOT`).
pub const PRESET_AS_SHOT: i32 = 0;
/// Preset tag: from an image area (`DT_IOP_TEMP_SPOT`).
pub const PRESET_SPOT: i32 = 1;
/// Preset tag: user modified (`DT_IOP_TEMP_USER`).
pub const PRESET_USER: i32 = 2;
/// Preset tag: camera reference D65 (`DT_IOP_TEMP_D65`).
pub const PRESET_D65: i32 = 3;
/// Preset tag: as-shot to reference, adaptation deferred (`DT_IOP_TEMP_D65_LATE`).
pub const PRESET_D65_LATE: i32 = 4;

/// Settings: four channel multipliers plus the preset tag. Defaults are
/// upstream's: as-shot multipliers (green-normalized) with the as-shot tag
/// (`reload_defaults`, `temperature.c:1608-1621`).
static FIELDS: &[ParamField] = &[
    ParamField {
        name: "red",
        ty: ParamType::Float,
    },
    ParamField {
        name: "green",
        ty: ParamType::Float,
    },
    ParamField {
        name: "blue",
        ty: ParamType::Float,
    },
    ParamField {
        name: "various",
        ty: ParamType::Float,
    },
    ParamField {
        name: "preset",
        ty: ParamType::Int,
    },
];

/// Module descriptor: id + orders from the A3 stub, everything else filled
/// from upstream (`default_group()` `:259-262` BASIC first, `flags()`
/// `:264-267`, `IOP_FLAGS_ONE_INSTANCE`, RAW on both sides).
pub static DESC: ModuleDesc = ModuleDesc {
    id: "temperature",
    display_key: None,
    group: Some(ModuleGroup::Base),
    order: OrderKeys {
        raw: OrderKey {
            priority: 3.0,
            tie: 2,
        },
        jpg: OrderKey {
            priority: 3.0,
            tie: 2,
        },
    },
    params: ParamsDesc {
        fields: Some(FIELDS),
    },
    flags: Some(ModuleFlags::TILING),
    colorspaces: Some(ColorRequirement {
        default_space: ColorSpace::Raw,
        input: ColorSpace::Raw,
        output: ColorSpace::Raw,
    }),
    panel: None,
    history: Some(HistoryKeys {
        aliases: &[],
        multi_instance: false,
        doc_level: false,
    }),
};

/// Builds the module behind a shared pointer (auto-discovery entry).
#[must_use]
pub fn create() -> SharedModule {
    Arc::new(TemperatureModule)
}

/// The temperature module: stateless, everything flows through commit data.
#[derive(Debug)]
pub struct TemperatureModule;

/// Sealed commit product: four multipliers, the preset tag, applicability.
/// Fixed-size stack data; the [`CommitData`] `Arc` is its only heap.
#[derive(Debug, Clone, Copy)]
struct TemperatureCommit {
    coeffs: [f32; 4],
    preset: i32,
    applies: bool,
}

/// Upstream's multiplier domain (`$MIN: 0.0 $MAX: 8.0` on all four sliders).
fn check_coeff(name: &str, value: f64) -> Result<f32, PipeError> {
    if !(0.0..=8.0).contains(&value) {
        return Err(PipeError::InvalidParams(format!(
            "temperature '{name}' wants 0..=8, found {value}"
        )));
    }
    #[expect(clippy::cast_possible_truncation)]
    // Narrowing a 0..=8 finite double to float rounds once, like the C
    // params the GUI sliders produce.
    Ok(value as f32)
}

/// Reads an optional tagged float: strict shape when present, [`None`] when
/// the key is absent (the caller falls back to the as-shot default).
fn get_opt_float(params: &Map<String, Value>, name: &str) -> Result<Option<f64>, PipeError> {
    if params.get(name).is_none() {
        return Ok(None);
    }
    get_float(params, name).map(Some)
}

/// Reads the optional preset tag: strict shape when present.
fn get_opt_preset(params: &Map<String, Value>) -> Result<Option<i32>, PipeError> {
    if params.get("preset").is_none() {
        return Ok(None);
    }
    let tag = get_int(params, "preset")?;
    if !(i64::from(PRESET_UNKNOWN)..=i64::from(PRESET_D65_LATE)).contains(&tag) {
        return Err(PipeError::InvalidParams(format!(
            "temperature 'preset' wants -1..=4, found {tag}"
        )));
    }
    i32::try_from(tag).map(Some).map_err(|_| {
        PipeError::InvalidParams(format!("temperature 'preset' out of range: {tag}"))
    })
}

/// Whether the capture supports matrix correction: RAW-ish and not
/// monochrome (`dt_image_is_matrix_correction_supported`, `image.c:253-257`).
/// Presence of [`RawFacts`] is this pipe's RAW bit; mono small-RAWs and
/// monochrome RAWs read false, like upstream.
fn matrix_supported(raw: &RawFacts) -> bool {
    !raw.monochrome
}

/// As-shot white balance to multipliers: the first leg of `_find_coeffs`
/// (`temperature.c:1452-1465`). [`None`] when any checked multiplier is
/// missing (zero), non-normal, or non-finite — then the caller moves on to
/// the matrix leg. Only the first three count unless `four_bayer` (the
/// fourth is usually NaN for RGB).
#[must_use]
pub fn wb_to_coeffs(wb: [f32; 4], four_bayer: bool) -> Option<[f64; 4]> {
    let [r, g, b, v] = wb;
    let count = if four_bayer { 4 } else { 3 };
    for value in [r, g, b, v].iter().take(count) {
        // `f32::is_normal` matches C `isnormal` (rejects zero, subnormal,
        // infinite, NaN); the explicit zero check transcribes the `== 0.0f`
        // disjunct anyway.
        if !value.is_normal() || *value == 0.0 {
            return None;
        }
    }
    Some([f64::from(r), f64::from(g), f64::from(b), f64::from(v)])
}

/// Dcraw's pseudoinverse (`dt_colorspaces_pseudoinverse`,
/// `colorspaces.c:2311-2341`), verbatim order, hardcoded to the 4-row shape
/// both callers use.
#[allow(clippy::indexing_slicing)]
// Fixed 4x3/3x6 shapes with constant loop bounds; every index is in range
// by construction, and `get` chains would bury the transcribed arithmetic.
fn pseudoinverse(input: &[[f64; 3]; 4]) -> [[f64; 3]; 4] {
    let mut work = [[0.0; 6]; 3];
    for i in 0..3 {
        for (j, slot) in work[i].iter_mut().enumerate() {
            *slot = if j == i + 3 { 1.0 } else { 0.0 };
        }
        for j in 0..3 {
            for row in input {
                work[i][j] += row[i] * row[j];
            }
        }
    }
    for i in 0..3 {
        let num = work[i][i];
        for slot in &mut work[i] {
            *slot /= num;
        }
        for k in 0..3 {
            if k == i {
                continue;
            }
            let num = work[k][i];
            for j in 0..6 {
                work[k][j] -= work[i][j] * num;
            }
        }
    }
    let mut out = [[0.0; 3]; 4];
    for i in 0..4 {
        for j in 0..3 {
            out[i][j] = 0.0;
            for k in 0..3 {
                out[i][j] += work[j][k + 3] * input[i][k];
            }
        }
    }
    out
}

/// Camera matrix pair (`_prepare_matrices`, `temperature.c:1412-1446`, with
/// `dt_colorspaces_conversion_matrices_xyz`, `colorspaces.c:2344-2375`).
/// Non-RAW captures read the sRGB D65 pair; RAW captures read the rawspeed
/// matrix with a zero fourth row (upstream's short-matrix pad,
/// `imageio_rawspeed.cc:266-276`) plus its pseudoinverse. A RAW capture
/// without a matrix reads zeros: upstream's conversion fails there and the
/// calloc'd GUI matrices stay zero.
#[allow(clippy::unreadable_literal)]
// Verbatim upstream decimals: separators would obscure the text they must
// match digit for digit.
fn prepare_matrices(
    xyz_to_cam: Option<[f32; 9]>,
    is_raw: bool,
) -> ([[f64; 3]; 4], [[f64; 4]; 3]) {
    // sRGB D65, verbatim decimals (`temperature.c:1436-1444`).
    const RGB_TO_XYZ: [[f64; 4]; 3] = [
        [0.4124564, 0.3575761, 0.1804375, 0.0],
        [0.2126729, 0.7151522, 0.0721750, 0.0],
        [0.0193339, 0.1191920, 0.9503041, 0.0],
    ];
    const XYZ_TO_RGB: [[f64; 3]; 4] = [
        [3.2404542, -1.5371385, -0.4985314],
        [-0.9692660, 1.8760108, 0.0415560],
        [0.0556434, -0.2040259, 1.0572252],
        [0.0, 0.0, 0.0],
    ];
    if !is_raw {
        return (XYZ_TO_RGB, RGB_TO_XYZ);
    }
    let Some(matrix) = xyz_to_cam else {
        return ([[0.0; 3]; 4], [[0.0; 4]; 3]);
    };
    // The DNG-embedded leg cannot run here (decode carries no embedded
    // matrix, and ARW files hold none), so this is the adobe branch only.
    let mut xyz_to_cam_4 = [[0.0; 3]; 4];
    for k in 0..3 {
        for i in 0..3 {
            if let Some((slot, value)) = xyz_to_cam_4
                .get_mut(k)
                .and_then(|row| row.get_mut(i))
                .zip(matrix.get(k * 3 + i))
            {
                *slot = f64::from(*value);
            }
        }
    }
    let inverse = pseudoinverse(&xyz_to_cam_4);
    let mut cam_to_xyz = [[0.0; 4]; 3];
    for i in 0..3 {
        for j in 0..4 {
            if let (Some(slot), Some(value)) = (
                cam_to_xyz.get_mut(i).and_then(|row| row.get_mut(j)),
                inverse.get(j).and_then(|row| row.get(i)),
            ) {
                *slot = *value;
            }
        }
    }
    (xyz_to_cam_4, cam_to_xyz)
}

/// Daylight multipliers from the camera matrix: the
/// `dt_colorspaces_conversion_matrices_rgb` leg
/// (`colorspaces.c:2377-2456`) with no embedded matrix (see
/// [`prepare_matrices`]), returning only the `mul` row
/// `_calculate_bogus_daylight_wb` reads.
#[allow(clippy::indexing_slicing)]
// Fixed 4x3/3x3 shapes with constant loop bounds; see `pseudoinverse`.
#[allow(clippy::unreadable_literal)]
// Verbatim upstream decimals (see `prepare_matrices`).
fn bogus_mul(xyz_to_cam: &[f32; 9]) -> [f64; 4] {
    // sRGB D65, verbatim decimals — note these differ in the last places
    // from the `_prepare_matrices` pair (`colorspaces.c:2404-2408`).
    const RGB_TO_XYZ: [[f64; 3]; 3] = [
        [0.412453, 0.357580, 0.180423],
        [0.212671, 0.715160, 0.072169],
        [0.019334, 0.119193, 0.950227],
    ];
    let mut xyz_4 = [[0.0; 3]; 4];
    for k in 0..3 {
        for i in 0..3 {
            xyz_4[k][i] = f64::from(xyz_to_cam[k * 3 + i]);
        }
    }
    let mut rgb_to_cam = [[0.0; 3]; 4];
    for i in 0..4 {
        for j in 0..3 {
            rgb_to_cam[i][j] = 0.0;
            for k in 0..3 {
                rgb_to_cam[i][j] += xyz_4[i][k] * RGB_TO_XYZ[k][j];
            }
        }
    }
    let mut mul = [0.0; 4];
    for i in 0..4 {
        let mut num = 0.0;
        for lane in &rgb_to_cam[i] {
            num += lane;
        }
        for slot in &mut rgb_to_cam[i] {
            *slot /= num;
        }
        mul[i] = 1.0 / num;
    }
    mul
}

/// Bogus daylight white balance (`_calculate_bogus_daylight_wb`,
/// `temperature.c:1382-1410`): green-normalized daylight multipliers from
/// the camera matrix. Unsupported captures read ones (upstream returns
/// "used" with ones there, and `_find_coeffs` takes them); [`None`] means
/// the matrix leg failed on a supported capture (no valid matrix).
#[must_use]
pub fn bogus_daylight_wb(raw: &RawFacts) -> Option<[f64; 4]> {
    if !matrix_supported(raw) {
        return Some([1.0; 4]);
    }
    let matrix = raw.xyz_to_cam_d65?;
    let mul = bogus_mul(&matrix);
    Some([mul[0] / mul[1], 1.0, mul[2] / mul[1], mul[3] / mul[1]])
}

/// Default multipliers (`_find_coeffs`, `temperature.c:1448-1511`): as-shot
/// when sane, else the bogus-daylight matrix leg, else the hardcoded
/// fallback. The camera-preset leg is skipped (no preset table and no body
/// strings in scope), which matches the oracle's zero-count preset stub, so
/// both sides fall through to the fallback together.
#[must_use]
pub fn default_coeffs(raw: &RawFacts) -> [f64; 4] {
    if let Some(coeffs) = wb_to_coeffs(raw.wb, raw.four_bayer) {
        return coeffs;
    }
    if let Some(bwb) = bogus_daylight_wb(raw) {
        return bwb;
    }
    [2.0, 1.0, 1.5, 1.0]
}

/// Blackbody spectral power distribution (`_spd_blackbody`,
/// `temperature.c:287-314`).
///
/// Upstream computes in `long double`, which on ARM64 macOS is the same
/// 64-bit double this uses (Apple's ARM ABI); the transcription shares the
/// width, and `powl`/`expl` versus `powi`/`exp` can differ by ≤1ulp
/// (pinned by the 1e-4 oracle gate). Decimal constants are verbatim.
#[allow(clippy::excessive_precision, clippy::unreadable_literal)]
// Verbatim `long double` decimals: the parser rounds correctly into `f64`,
// and trimming them by hand could only introduce error; separators would
// obscure the upstream text they must match digit for digit.
fn spd_blackbody(wavelength: u32, temp_kelvin: f64) -> f64 {
    const C1: f64 = 3.7417715246641281639549488324352159753e-16;
    const C2: f64 = 0.014387769599838156481252937624049081933;
    let lambda = f64::from(wavelength) * 1e-9;
    C1 / (lambda.powi(5) * ((C2 / (lambda * temp_kelvin)).exp() - 1.0))
}

/// Daylight spectral power distribution (`_spd_daylight`,
/// `temperature.c:321-342`): lcms2 white point through the daylight
/// principal components. The only lcms2 call in the module, via
/// [`lightamer_color::white_point_from_temp`].
fn spd_daylight(wavelength: u32, temp_kelvin: f64) -> f64 {
    let (x, y) =
        lightamer_color::white_point_from_temp(temp_kelvin).unwrap_or((D65_X, D65_Y));
    let m_denom = 0.0241 + 0.2562 * x - 0.7341 * y;
    let m1 = (-1.3515 - 1.7703 * x + 5.9114 * y) / m_denom;
    let m2 = (0.0300 - 31.4424 * x + 30.0717 * y) / m_denom;
    // Table-relative index, the unsigned shape upstream divides
    // (`temperature.c:335-339`); wavelengths 380..=780 land on rows
    // 16..=96 of the 300-based 107-row table.
    let first = CIE_DAYLIGHT.first().map_or(300, |(w, _)| *w);
    let step = CIE_DAYLIGHT.get(1).map_or(5, |(w, _)| *w - first);
    let index = wavelength.saturating_sub(first) / step;
    let [s0, s1, s2] = CIE_DAYLIGHT
        .get(usize::try_from(index).unwrap_or(usize::MAX))
        .map_or([0.0, 0.0, 0.0], |(_, sides)| *sides);
    s0 + m1 * s1 + m2 * s2
}

/// Spectrum to XYZ (`_spectrum_to_XYZ`, `temperature.c:348-376`): the
/// observer-weighted sum, normalized so the largest component is 1.
///
/// Upstream addresses the observer table by computed wavelength
/// (380 + 5*i); this iterates the entries and reads their wavelengths,
/// which are that same sequence (locked by `cie_tables_stay_uniform`).
#[allow(clippy::indexing_slicing)]
// Three fixed lanes addressed by constant subscripts; see `pseudoinverse`.
fn spectrum_to_xyz(temp_kelvin: f64, daylight: bool) -> [f64; 3] {
    let mut xyz = [0.0; 3];
    for (wavelength, observer) in CIE_1931 {
        let power = if daylight {
            spd_daylight(wavelength, temp_kelvin)
        } else {
            spd_blackbody(wavelength, temp_kelvin)
        };
        xyz[0] += power * observer[0];
        xyz[1] += power * observer[1];
        xyz[2] += power * observer[2];
    }
    // `f64::max` matches C `fmax` (either NaN yields the other side).
    let max = xyz[0].max(xyz[1]).max(xyz[2]);
    [xyz[0] / max, xyz[1] / max, xyz[2] / max]
}

/// Temperature to XYZ (`_temperature_to_XYZ`, `temperature.c:379-394`):
/// blackbody below 4000 K (no daylight reference there), daylight above.
fn temperature_to_xyz(temp_kelvin: f64) -> [f64; 3] {
    // Upstream clamps with two `if`s; `clamp` is the same shape (NaN passes
    // through both, then poisons the spectrum identically).
    let temp = temp_kelvin.clamp(LOWEST_TEMP, HIGHEST_TEMP);
    spectrum_to_xyz(temp, temp >= BLACKBODY_SWITCH)
}

/// Temperature + tint to XYZ (`_temperature_tint_to_XYZ`,
/// `temperature.c:396-403`): tint scales Y only (upstream's own TODO calls
/// this out as a hack; transcribed as-is).
fn temperature_tint_to_xyz(temp_kelvin: f64, tint: f64) -> [f64; 3] {
    let [x, y, z] = temperature_to_xyz(temp_kelvin);
    [x, y / tint, z]
}

/// Temperature + tint to the CIE xy white point: the spectrum XYZ,
/// normalized. The XYZ leg is upstream's; the xy normalization is this
/// pipe's panel helper (upstream only ever needs XYZ downstream).
#[must_use]
pub fn temp_tint_to_xy(temp_kelvin: f64, tint: f64) -> (f64, f64) {
    let [x, y, z] = temperature_tint_to_xyz(temp_kelvin, tint);
    let sum = x + y + z;
    (x / sum, y / sum)
}

/// One rounding into `f32`: the C `float` out-param stores round once.
#[expect(clippy::cast_possible_truncation)]
fn narrow(value: f64) -> f32 {
    value as f32
}

/// Promotion-compare, rounded-constant assign: upstream clamps its `float`
/// out-params against `double` bounds, which promotes the value and rounds
/// the assigned bound once.
fn clamp_out(value: f32, lo: f64, hi: f64) -> f32 {
    let wide = f64::from(value);
    if wide < lo {
        narrow(lo)
    } else if wide > hi {
        narrow(hi)
    } else {
        value
    }
}
/// XYZ to temperature + tint (`_XYZ_to_temperature`, `temperature.c:406-430`):
/// binary search on the blue/red ratio, then the tint ratio. The search
/// runs in `f32` (upstream iterates a `float` out-param), the ratios in
/// `f64`. `hi`/`lo` are upstream's `maxtemp`/`mintemp`.
#[allow(clippy::manual_midpoint)]
// The search midpoint keeps upstream's `(hi + lo) / 2.0` order (1901..25000
// cannot overflow); `midpoint` rounds differently and would diverge bitwise.
fn xyz_to_temperature(xyz: [f64; 3]) -> (f32, f32) {
    let [xx, xy, xz] = xyz;
    let mut hi = HIGHEST_TEMP;
    let mut lo = LOWEST_TEMP;
    let mut temp = narrow((hi + lo) / 2.0);
    let mut probe = [0.0; 3];
    while hi - lo > 1.0 {
        probe = temperature_to_xyz(f64::from(temp));
        let [px, _, pz] = probe;
        if pz / px > xz / xx {
            hi = f64::from(temp);
        } else {
            lo = f64::from(temp);
        }
        temp = narrow((hi + lo) / 2.0);
    }
    let [px, py, _] = probe;
    let tint = narrow((py / px) / (xy / xx));
    (
        clamp_out(temp, LOWEST_TEMP, HIGHEST_TEMP),
        clamp_out(tint, LOWEST_TINT, HIGHEST_TINT),
    )
}

/// XYZ to multipliers (`_xyz2mul`, `temperature.c:432-451`): through the
/// prepared camera matrix, then reciprocals.
fn xyz_to_mul(xyz: [f64; 3], xyz_to_cam: &[[f64; 3]; 4]) -> [f64; 4] {
    let mut cam = [0.0; 4];
    for (lane, slot) in cam.iter_mut().enumerate() {
        let mut sum = 0.0;
        for (i, value) in xyz.iter().enumerate() {
            if let Some(factor) = xyz_to_cam
                .get(lane)
                .and_then(|row| row.get(i))
            {
                sum += factor * value;
            }
        }
        *slot = sum;
    }
    for slot in &mut cam {
        *slot = 1.0 / *slot;
    }
    cam
}

/// Temperature + tint to multipliers (`_temp2mul`, `temperature.c:453-470`):
/// the spectrum XYZ (tint on Y) through the prepared camera matrix.
#[must_use]
pub fn temp_tint_to_coeffs(
    temp_kelvin: f64,
    tint: f64,
    xyz_to_cam: Option<[f32; 9]>,
    is_raw: bool,
) -> [f64; 4] {
    let xyz = temperature_tint_to_xyz(temp_kelvin, tint);
    let (matrix, _) = prepare_matrices(xyz_to_cam, is_raw);
    xyz_to_mul(xyz, &matrix)
}

/// Multipliers to XYZ (`_mul2xyz`, `temperature.c:472-494`): reciprocals
/// (non-positive lanes read zero) back through the inverse matrix.
fn mul_to_xyz(coeffs: [f32; 4], cam_to_xyz: &[[f64; 4]; 3]) -> [f64; 3] {
    let mut cam = [0.0; 4];
    for (lane, slot) in cam.iter_mut().enumerate() {
        let value = coeffs.get(lane).map_or(0.0, |v| f64::from(*v));
        *slot = if value > 0.0 { 1.0 / value } else { 0.0 };
    }
    let mut xyz = [0.0; 3];
    for (k, slot) in xyz.iter_mut().enumerate() {
        let mut sum = 0.0;
        for (i, value) in cam.iter().enumerate() {
            if let Some(factor) = cam_to_xyz.get(k).and_then(|row| row.get(i)) {
                sum += factor * value;
            }
        }
        *slot = sum;
    }
    xyz
}

/// Multipliers to temperature + tint (`_mul2temp`, `temperature.c:496-502`):
/// back through the inverse matrix, then the binary search.
#[must_use]
pub fn coeffs_to_temp_tint(
    coeffs: [f32; 4],
    xyz_to_cam: Option<[f32; 9]>,
    is_raw: bool,
) -> (f32, f32) {
    let (_, inverse) = prepare_matrices(xyz_to_cam, is_raw);
    xyz_to_temperature(mul_to_xyz(coeffs, &inverse))
}

/// Resolves commit data: explicit multipliers win per key, absent keys read
/// the green-normalized as-shot defaults (`reload_defaults`,
/// `temperature.c:1633-1636`); the tag defaults to as-shot. Commit reads no
/// chain state and no render kind, but writes the late-correction flag:
/// upstream's `commit_params` sets `chr->late_correction` (`:725`) for every
/// piece but the true-monochrome hide early-return (the oracle's hide is
/// always false, so it always writes there, like here). Non-RAW captures
/// and monochrome RAWs stay disabled (see [`matrix_supported`]).
fn resolve_commit(
    params: &Map<String, Value>,
    image: &ImageInfo,
    state: &mut PipeState,
    _kind: PipeKind,
) -> Result<TemperatureCommit, PipeError> {
    let raw = image.raw.filter(matrix_supported);
    let defaults = raw.map(|facts| {
        let [r, g, b, v] = default_coeffs(&facts);
        [r / g, 1.0, b / g, v / g]
    });
    let mut coeffs = [1.0f32; 4];
    for (lane, name) in ["red", "green", "blue", "various"].iter().enumerate() {
        let fallback = defaults
            .as_ref()
            .and_then(|d| d.get(lane))
            .copied()
            .unwrap_or(1.0);
        let value = check_coeff(name, get_opt_float(params, name)?.unwrap_or(fallback))?;
        if let Some(slot) = coeffs.get_mut(lane) {
            *slot = value;
        }
    }
    let preset = get_opt_preset(params)?.unwrap_or(PRESET_AS_SHOT);
    state.temperature.late_correction = preset == PRESET_D65_LATE;
    Ok(TemperatureCommit {
        coeffs,
        preset,
        applies: raw.is_some(),
    })
}

/// Copies input to output unchanged: the disabled piece upstream skips.
/// Only the late flag lands (upstream's commit wrote it even though the
/// piece never publishes); everything else stays untouched, like the
/// skipped piece. (Sibling copy of hotpixels' helper plus the flag:
/// same-layer crates cannot share code.)
fn passthrough(
    input: &Plane<'_>,
    output: &mut PlaneMut<'_>,
    rin: Roi,
    rout: Roi,
    state: &mut PipeState,
    late_correction: bool,
) -> Result<(), PipeError> {
    if rin.width != rout.width || rin.height != rout.height {
        return Err(PipeError::RoiMismatch(format!(
            "temperature passthrough needs equal shapes, got {}x{} in and {}x{} out",
            rin.width, rin.height, rout.width, rout.height
        )));
    }
    if input.width() != output.width() || input.height() != output.height() {
        return Err(PipeError::RoiMismatch(format!(
            "temperature planes differ: {}x{} vs {}x{}",
            input.width(),
            input.height(),
            output.width(),
            output.height()
        )));
    }
    if input.channels() != output.channels() {
        return Err(PipeError::RoiMismatch(format!(
            "temperature channels differ: {} vs {}",
            input.channels(),
            output.channels()
        )));
    }
    let rows = usize::try_from(rout.height.max(0)).map_err(|_| {
        PipeError::RoiMismatch(format!("temperature height {} overflows", rout.height))
    })?;
    let row_len = u64::from(input.width())
        .checked_mul(u64::from(input.channels()))
        .and_then(|len| usize::try_from(len).ok())
        .ok_or_else(|| {
            PipeError::RoiMismatch(format!("temperature width {} overflows", input.width()))
        })?;
    let src_stride = input.stride();
    let dst_stride = output.stride();
    par_map_rows(
        input.as_slice(),
        output.as_mut_slice(),
        rows,
        src_stride,
        dst_stride,
        row_len,
        |src, dst| dst.copy_from_slice(src),
    )?;
    state.temperature.late_correction = late_correction;
    Ok(())
}

/// Bayer color number of one cell (R=0, G=1, B=2, G2=3); non-RGB cells
/// read green (upstream tables hold Bayer colors only).
fn bayer_number(cell: CfaColor) -> u32 {
    match cell {
        CfaColor::Red => 0,
        CfaColor::Blue => 2,
        CfaColor::Green
        | CfaColor::Cyan
        | CfaColor::Magenta
        | CfaColor::Yellow
        | CfaColor::White
        | CfaColor::FujiGreen
        | CfaColor::Unknown => 1,
    }
}

/// Encodes four Bayer cells as a dcraw filter word (2x2 block repeated),
/// the `filters` word upstream's `FC` reads.
fn bayer_filters(cells: [CfaColor; 4]) -> u32 {
    let [a, b, c, d] = cells;
    let low =
        bayer_number(a) | bayer_number(b) << 2 | bayer_number(c) << 4 | bayer_number(d) << 6;
    low | low << 8 | low << 16 | low << 24
}

/// Shifts a Bayer pattern by the tile origin: upstream derives
/// `piece->filters` per tile (`dt_dev_prepare_piece_cfa` shifts the word
/// by `roi.x`/`roi.y`), so tile-local `FC` reads the shifted pattern.
/// Sibling copy of rawprepare's `shift_bayer` (same-layer crates cannot
/// share code): parity match, exact for the uniform words `bayer_filters`
/// encodes.
fn shift_bayer_cells(cells: [CfaColor; 4], ox: usize, oy: usize) -> [CfaColor; 4] {
    let [a, b, c, d] = cells;
    match (ox & 1, oy & 1) {
        (0, 0) => cells,
        (1, 0) => [b, a, d, c],
        (0, 1) => [c, d, a, b],
        _ => [d, c, b, a],
    }
}

/// Bayer color at tile `(row, col)`: upstream `FC`
/// (`imageop_math.h:154-157`), same shift shape.
fn bayer_color(row: usize, col: usize, filters: u32) -> usize {
    // `0xE` is upstream's decimal `14`, same value (`FC` masks row parity).
    let shift = (((row << 1) & 0xE) + (col & 1)) << 1;
    usize::try_from((filters >> shift) & 3).unwrap_or(0)
}

/// Multiplier lane for one X-Trans cell: R/G/B to 0/1/2 (upstream tables
/// hold those only; anything else reads green).
fn xtrans_lane(cell: CfaColor) -> usize {
    match cell {
        CfaColor::Red => 0,
        CfaColor::Blue => 2,
        CfaColor::Green
        | CfaColor::Cyan
        | CfaColor::Magenta
        | CfaColor::Yellow
        | CfaColor::White
        | CfaColor::FujiGreen
        | CfaColor::Unknown => 1,
    }
}

impl IopModule for TemperatureModule {
    fn desc(&self) -> &ModuleDesc {
        &DESC
    }

    fn commit(
        &self,
        params: &Map<String, Value>,
        image: &ImageInfo,
        state: &mut PipeState,
        kind: PipeKind,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(resolve_commit(params, image, state, kind)?))
    }

    fn process(
        &self,
        data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
        state: &mut PipeState,
    ) -> Result<(), PipeError> {
        let Some(commit) = data.downcast_ref::<TemperatureCommit>() else {
            return Err(PipeError::Backend(
                "temperature opened a foreign commit".to_owned(),
            ));
        };
        if !commit.applies {
            let late = commit.preset == PRESET_D65_LATE;
            return passthrough(input, output, rin, rout, state, late);
        }
        let dims = process_dims(input, output, rin, rout, state.cfa)?;
        match state.cfa {
            CfaPattern::XTrans(cells) => run_xtrans(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                dims.rows,
                dims.width,
                dims.src_stride,
                dims.dst_stride,
                cells,
                rout,
            ),
            CfaPattern::Bayer(cells) => run_bayer(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                dims.rows,
                dims.width,
                dims.src_stride,
                dims.dst_stride,
                cells,
                rout,
            ),
            CfaPattern::None => run_planar(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                dims.rows,
                dims.width,
                dims.src_stride,
                dims.dst_stride,
            ),
        }
        // `_publish_chroma` (`:515-530`): enabled, per-channel coeffs, and
        // the maxima scaled by the coeffs (upstream multiplies coeffs-first;
        // `f32` multiplication commutes bitwise), plus the late-correction
        // flag the commit wrote to `dev->chroma` beside it (`:725`).
        state.temperature.enabled = true;
        state.temperature.coeffs = commit.coeffs;
        state.temperature.late_correction = commit.preset == PRESET_D65_LATE;
        for (lane, slot) in state.processed_maximum.iter_mut().enumerate() {
            if let Some(coeff) = commit.coeffs.get(lane) {
                *slot *= coeff;
            }
        }
        Ok(())
    }
}

/// Checked process geometry: identity roi, lane count, and whole-row bounds.
struct ProcessDims {
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
}

/// Checks the process call: identity geometry (temperature implements no
/// roi pair upstream), the lane count for the process-time pattern
/// (`process` `:544/:587/623`: one lane per sensel on mosaic input, four
/// on non-mosaiced — the branch reads process-time state, like upstream's
/// `piece->filters` read), and whole-row bounds before a lane spawns.
fn process_dims(
    input: &Plane<'_>,
    output: &mut PlaneMut<'_>,
    rin: Roi,
    rout: Roi,
    cfa: CfaPattern,
) -> Result<ProcessDims, PipeError> {
    // Shapes match or the caller miswired. Origins match too: the X-Trans
    // leg maps the tile origin onto the CFA table, so a split origin
    // would silently read the wrong phase.
    if rin.width != rout.width || rin.height != rout.height {
        return Err(PipeError::RoiMismatch(format!(
            "temperature needs equal shapes, got {}x{} in and {}x{} out",
            rin.width, rin.height, rout.width, rout.height
        )));
    }
    if rin.x != rout.x || rin.y != rout.y {
        return Err(PipeError::RoiMismatch(format!(
            "temperature needs equal origins, got ({},{}) in and ({},{}) out",
            rin.x, rin.y, rout.x, rout.y
        )));
    }
    let (planes, planes32): (usize, u32) = if matches!(cfa, CfaPattern::None) {
        (4, 4)
    } else {
        (1, 1)
    };
    if input.channels() != output.channels() {
        return Err(PipeError::RoiMismatch(format!(
            "temperature channels differ: {} vs {}",
            input.channels(),
            output.channels()
        )));
    }
    if input.channels() != planes32 {
        return Err(PipeError::UnsupportedFormat(format!(
            "temperature needs {planes} channel(s), got {}",
            input.channels()
        )));
    }
    let rows = usize::try_from(rout.height.max(0)).map_err(|_| {
        PipeError::RoiMismatch(format!("temperature height {} overflows", rout.height))
    })?;
    let width = usize::try_from(rout.width.max(0)).map_err(|_| {
        PipeError::RoiMismatch(format!("temperature width {} overflows", rout.width))
    })?;
    let row_len = width
        .checked_mul(planes)
        .ok_or_else(|| PipeError::RoiMismatch("temperature row overflows".to_owned()))?;
    let src_stride = input.stride();
    let dst_stride = output.stride();
    // Bounds before a single lane spawns: every addressed row must exist
    // whole (same whole-row discipline as rawprepare: strided planes
    // with a short tail refuse instead of leaving zeros there).
    let fits = |stride: usize, len: usize| -> bool {
        row_len <= stride && rows.checked_mul(stride).is_some_and(|need| need <= len)
    };
    if !fits(src_stride, input.as_slice().len())
        || !fits(dst_stride, output.as_mut_slice().len())
    {
        return Err(PipeError::RoiMismatch(
            "temperature tile overruns its planes".to_owned(),
        ));
    }
    Ok(ProcessDims {
        rows,
        width,
        src_stride,
        dst_stride,
    })
}

/// Renders the Bayer leg row-parallel (rayon): one multiply per sensel.
/// Upstream's 4-wide alignment dance (`:587-621`) computes these same
/// per-sensel products; the transcription multiplies directly. Rows are
/// independent.
#[allow(clippy::too_many_arguments)]
fn run_bayer(
    commit: &TemperatureCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
    cells: [CfaColor; 4],
    rout: Roi,
) {
    if rows == 0 || width == 0 {
        return; // empty loops upstream, plus a zero stride would panic below
    }
    // Origin-shifted word, like `dt_dev_prepare_piece_cfa` derives it.
    let ox = usize::try_from(rout.x.rem_euclid(2)).unwrap_or(0);
    let oy = usize::try_from(rout.y.rem_euclid(2)).unwrap_or(0);
    let filters = bayer_filters(shift_bayer_cells(cells, ox, oy));
    let coeffs = commit.coeffs;
    dst.par_chunks_exact_mut(dst_stride)
        .take(rows)
        .enumerate()
        .for_each(|(r, d_row)| {
            let s_row = src.get(r * src_stride..(r + 1) * src_stride).unwrap_or(&[]);
            for (c, slot) in d_row.iter_mut().take(width).enumerate() {
                let input = s_row.get(c).copied().unwrap_or(0.0);
                let lane = bayer_color(r, c, filters);
                *slot = input * coeffs.get(lane).copied().unwrap_or(1.0);
            }
        });
}

/// Renders the X-Trans leg row-parallel (rayon): one multiply per sensel
/// through the region-shifted table (see hotpixels' leg for the mapping:
/// tile pixel `(r, c)` sees `cells[((r + oy) % 6, (c + ox) % 6)]`). Rows
/// are independent.
#[allow(clippy::too_many_arguments)]
fn run_xtrans(
    commit: &TemperatureCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
    cells: [CfaColor; 36],
    rout: Roi,
) {
    if rows == 0 || width == 0 {
        return; // empty loops upstream, plus a zero stride would panic below
    }
    // `rem_euclid(6)` lands 0..6, so both conversions below hold.
    let ox = usize::try_from(rout.x.rem_euclid(6)).unwrap_or(0);
    let oy = usize::try_from(rout.y.rem_euclid(6)).unwrap_or(0);
    let shifted: [[usize; 6]; 6] = std::array::from_fn(|j| {
        std::array::from_fn(|i| {
            cells
                .get(((j + oy) % 6) * 6 + (i + ox) % 6)
                .map_or(1, |cell| xtrans_lane(*cell))
        })
    });
    let coeffs = commit.coeffs;
    dst.par_chunks_exact_mut(dst_stride)
        .take(rows)
        .enumerate()
        .for_each(|(r, d_row)| {
            let s_row = src.get(r * src_stride..(r + 1) * src_stride).unwrap_or(&[]);
            for (c, slot) in d_row.iter_mut().take(width).enumerate() {
                let input = s_row.get(c).copied().unwrap_or(0.0);
                let lane = shifted
                    .get(r % 6)
                    .and_then(|table_row| table_row.get(c % 6))
                    .copied()
                    .unwrap_or(1);
                *slot = input * coeffs.get(lane).copied().unwrap_or(1.0);
            }
        });
}

/// Renders the non-mosaiced leg row-parallel (rayon): per-lane products
/// (`:623-635`). Rows are independent.
#[allow(clippy::too_many_arguments)]
fn run_planar(
    commit: &TemperatureCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
) {
    if rows == 0 || width == 0 {
        return; // empty loops upstream, plus a zero stride would panic below
    }
    let coeffs = commit.coeffs;
    dst.par_chunks_exact_mut(dst_stride)
        .take(rows)
        .enumerate()
        .for_each(|(r, d_row)| {
            let s_row = src.get(r * src_stride..(r + 1) * src_stride).unwrap_or(&[]);
            for c in 0..width {
                for lane in 0..4 {
                    let input = s_row.get(c * 4 + lane).copied().unwrap_or(0.0);
                    if let Some(slot) = d_row.get_mut(c * 4 + lane) {
                        *slot = input * coeffs.get(lane).copied().unwrap_or(1.0);
                    }
                }
            }
        });
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{
        PRESET_AS_SHOT, PRESET_D65_LATE, TemperatureCommit, bayer_filters, default_coeffs,
        resolve_commit, temp_tint_to_coeffs, temp_tint_to_xy,
    };
    use super::{CIE_1931, CIE_DAYLIGHT};
    use lightamer_iop_traits::{
        CfaColor, CfaPattern, ColorSpace, ImageInfo, PipeKind, PipeState, Plane, PlaneMut, RawFacts,
        Roi,
    };
    use serde_json::{Map, Value, json};

    fn raw_facts() -> RawFacts {
        RawFacts {
            black: [512, 512, 512, 512],
            white: 15360,
            wb: [2.5273, 1.0, 1.7344, 0.0],
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
            p_width: 64,
            p_height: 64,
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

    fn raw_image() -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw_facts())
    }

    fn commit_of(params: &Map<String, Value>, image: &ImageInfo) -> TemperatureCommit {
        let mut state = PipeState::from_image(image);
        resolve_commit(params, image, &mut state, PipeKind::Full).expect("commit")
    }

    #[test]
    fn absent_keys_read_normalized_as_shot() {
        let commit = commit_of(&Map::new(), &raw_image());
        assert!(commit.applies);
        assert_eq!(commit.preset, PRESET_AS_SHOT);
        // As-shot 2.5273/1.0/1.7344/0.0, green-normalized (green already 1).
        assert_eq!(commit.coeffs, [2.5273, 1.0, 1.7344, 0.0]);
    }

    #[test]
    fn defaults_fall_back_without_wb_or_matrix() {
        let mut facts = raw_facts();
        facts.wb = [0.0; 4];
        assert_eq!(default_coeffs(&facts), [2.0, 1.0, 1.5, 1.0]);
    }

    #[test]
    fn defaults_take_bogus_when_wb_missing() {
        let mut facts = raw_facts();
        facts.wb = [0.0; 4];
        // Identity matrix: bogus daylight stays near ones, green exact.
        // The fourth lane is +inf (the zero fourth matrix row sums to a
        // zero divisor, like upstream) — no Bayer sensel reads it.
        facts.xyz_to_cam_d65 = Some([
            1.0, 0.0, 0.0, //
            0.0, 1.0, 0.0, //
            0.0, 0.0, 1.0, //
        ]);
        let coeffs = default_coeffs(&facts);
        assert_eq!(coeffs[1], 1.0);
        assert!(coeffs[0].is_finite() && coeffs[0] > 0.0);
        assert!(coeffs[2].is_finite() && coeffs[2] > 0.0);
        assert_eq!(coeffs[3], f64::INFINITY);
    }

    #[test]
    fn explicit_params_parse_per_key() {
        let params = json!({
            "red": {"type": "float", "value": 2.5},
            "preset": {"type": "int", "value": 2},
        });
        let commit = commit_of(params.as_object().expect("object"), &raw_image());
        assert_eq!(commit.coeffs[0], 2.5);
        assert_eq!(commit.coeffs[1], 1.0);
        assert_eq!(commit.preset, 2);
    }

    #[test]
    fn coeff_out_of_domain_rejected() {
        for value in [f64::NAN, f64::INFINITY, -1.0, 8.5] {
            let params = json!({ "red": {"type": "float", "value": value} });
            let mut state = PipeState::from_image(&raw_image());
            assert!(
                resolve_commit(
                    params.as_object().expect("object"),
                    &raw_image(),
                    &mut state,
                    PipeKind::Full
                )
                .is_err(),
                "rejects {value}"
            );
        }
    }

    #[test]
    fn preset_out_of_domain_rejected() {
        for tag in [-2, 5, 100] {
            let params = json!({ "preset": {"type": "int", "value": tag} });
            let mut state = PipeState::from_image(&raw_image());
            assert!(
                resolve_commit(
                    params.as_object().expect("object"),
                    &raw_image(),
                    &mut state,
                    PipeKind::Full
                )
                .is_err(),
                "rejects {tag}"
            );
        }
    }

    #[test]
    fn non_raw_disables() {
        let image = ImageInfo::new(8, 8, ColorSpace::Rgb);
        let commit = commit_of(&Map::new(), &image);
        assert!(!commit.applies);
    }

    #[test]
    fn mono_raw_disables() {
        let mut facts = raw_facts();
        facts.monochrome = true;
        let image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(facts);
        let commit = commit_of(&Map::new(), &image);
        assert!(!commit.applies);
    }

    #[test]
    fn commit_ignores_kind() {
        let image = raw_image();
        let mut a = PipeState::from_image(&image);
        let mut b = PipeState::from_image(&image);
        let full = resolve_commit(&Map::new(), &image, &mut a, PipeKind::Full).expect("full");
        let thumb =
            resolve_commit(&Map::new(), &image, &mut b, PipeKind::Thumbnail).expect("thumb");
        assert_eq!(full.coeffs, thumb.coeffs);
        assert_eq!(full.preset, thumb.preset);
        assert_eq!(full.applies, thumb.applies);
    }

    #[test]
    fn bayer_filters_encode_rggb() {
        assert_eq!(
            bayer_filters([
                CfaColor::Red,
                CfaColor::Green,
                CfaColor::Green,
                CfaColor::Blue,
            ]),
            0x9494_9494
        );
    }

    fn run_process(
        commit: &TemperatureCommit,
        image: &ImageInfo,
        input: &[f32],
        width: u32,
        height: u32,
        channels: u32,
        origin: (i32, i32),
    ) -> (Vec<f32>, PipeState) {
        use super::TemperatureModule;
        use lightamer_iop_traits::IopModule;
        use std::sync::Arc;
        let module = TemperatureModule;
        let data: Arc<dyn std::any::Any + Send + Sync> = Arc::new(*commit);
        let area = usize::try_from(width).expect("w") * usize::try_from(height).expect("h");
        let mut output = vec![0.0; area * usize::try_from(channels).expect("ch")];
        let stride = usize::try_from(width).expect("w") * usize::try_from(channels).expect("ch");
        let plane = Plane::from_slice_channels(input, width, height, stride, channels).expect("in");
        let mut out_plane =
            PlaneMut::from_slice_channels(&mut output, width, height, stride, channels)
                .expect("out");
        let w = i32::try_from(width).expect("w");
        let h = i32::try_from(height).expect("h");
        let roi = Roi::new(origin.0, origin.1, w, h, 1.0);
        let mut state = PipeState::from_image(image);
        module
            .process(&data, &plane, &mut out_plane, roi, roi, &mut state)
            .expect("process");
        (output, state)
    }

    #[test]
    fn bayer_multiplies_per_cell() {
        let image = raw_image();
        let commit = commit_of(&Map::new(), &image);
        // 2x2 ones on RGGB with as-shot coeffs.
        let (output, state) = run_process(&commit, &image, &[1.0; 4], 2, 2, 1, (0, 0));
        assert_eq!(output, [2.5273, 1.0, 1.0, 1.7344]);
        assert!(state.temperature.enabled);
        assert_eq!(state.temperature.coeffs, commit.coeffs);
        assert!(!state.temperature.late_correction);
        assert_eq!(state.processed_maximum, [2.5273, 1.0, 1.7344, 0.0]);
    }

    #[test]
    fn planar_multiplies_per_lane() {
        let image = raw_image();
        let params = json!({
            "red": {"type": "float", "value": 2.0},
            "green": {"type": "float", "value": 1.0},
            "blue": {"type": "float", "value": 1.5},
            "various": {"type": "float", "value": 0.5},
        });
        let commit = commit_of(params.as_object().expect("object"), &image);
        // Patternless state takes the 4-wide leg (upstream `filters == 0`).
        let mut planar = image;
        planar.raw = planar.raw.map(|mut raw| {
            raw.cfa = CfaPattern::None;
            raw
        });
        let (output, _) = run_process(&commit, &planar, &[1.0; 4], 1, 1, 4, (0, 0));
        assert_eq!(output, [2.0, 1.0, 1.5, 0.5]);
    }

    #[test]
    fn late_preset_sets_late_correction() {
        let image = raw_image();
        let params = json!({ "preset": {"type": "int", "value": PRESET_D65_LATE} });
        let commit = commit_of(params.as_object().expect("object"), &image);
        let (_, state) = run_process(&commit, &image, &[1.0; 4], 2, 2, 1, (0, 0));
        assert!(state.temperature.late_correction);
    }

    #[test]
    fn commit_writes_late_flag_even_when_disabled() {
        // Upstream's commit sets `chr->late_correction` for every piece
        // (`:725`); a disabled piece still carries the flag.
        let image = ImageInfo::new(2, 2, ColorSpace::Rgb);
        let params = json!({ "preset": {"type": "int", "value": PRESET_D65_LATE} });
        let mut state = PipeState::from_image(&image);
        let commit = resolve_commit(
            params.as_object().expect("object"),
            &image,
            &mut state,
            PipeKind::Full,
        )
        .expect("commit");
        assert!(!commit.applies);
        assert!(state.temperature.late_correction);
    }

    #[test]
    fn disabled_passes_through_untouched() {
        let image = ImageInfo::new(2, 2, ColorSpace::Rgb);
        let commit = commit_of(&Map::new(), &image);
        let input = [0.25, 0.5, 0.75, 1.0];
        let (output, state) = run_process(&commit, &image, &input, 2, 2, 1, (0, 0));
        assert_eq!(output, input);
        assert!(!state.temperature.enabled);
        assert_eq!(state.processed_maximum, [1.0; 4]);
    }

    #[test]
    fn temp_tint_xy_clamps_and_stays_finite() {
        // Below-range temperatures clamp to 1901 K.
        assert_eq!(temp_tint_to_xy(100.0, 1.0), temp_tint_to_xy(1901.0, 1.0));
        assert_eq!(temp_tint_to_xy(99999.0, 1.0), temp_tint_to_xy(25000.0, 1.0));
        let (x, y) = temp_tint_to_xy(5000.0, 1.0);
        assert!(x.is_finite() && y.is_finite() && x > 0.0 && y > 0.0);
        assert!((x + y) < 1.0);
    }

    #[test]
    fn temp_to_coeffs_runs_on_both_matrix_legs() {
        let matrix = Some([
            1.0, 0.0, 0.0, //
            0.0, 1.0, 0.0, //
            0.0, 0.0, 1.0, //
        ]);
        // The fourth lane is +inf on both legs (the zero fourth matrix
        // row reciprocates to it, like upstream) — no Bayer sensel reads it.
        for (xyz, is_raw) in [(matrix, true), (None, false)] {
            let mul = temp_tint_to_coeffs(5000.0, 1.0, xyz, is_raw);
            assert!(mul[0].is_finite() && mul[0] > 0.0, "{mul:?}");
            assert!(mul[1].is_finite() && mul[1] > 0.0, "{mul:?}");
            assert!(mul[2].is_finite() && mul[2] > 0.0, "{mul:?}");
            assert_eq!(mul[3], f64::INFINITY, "{mul:?}");
        }
    }

    #[test]
    fn cie_tables_stay_uniform() {
        // The spectrum loop reads entry wavelengths instead of computing
        // 380+5*i / 300+5*i; this locks the equivalence.
        for (i, (wavelength, _)) in CIE_1931.iter().enumerate() {
            assert_eq!(*wavelength, 380 + 5 * u32::try_from(i).expect("i"));
        }
        for (i, (wavelength, _)) in CIE_DAYLIGHT.iter().enumerate() {
            assert_eq!(*wavelength, 300 + 5 * u32::try_from(i).expect("i"));
        }
        assert_eq!(CIE_1931.len(), 81);
        assert_eq!(CIE_DAYLIGHT.len(), 107);
    }

    #[test]
    fn descriptor_covers_temperature() {
        let desc = &super::DESC;
        assert_eq!(desc.id, "temperature");
        assert_eq!(desc.params.fields.expect("fields").len(), 5);
        assert_eq!(super::create().id(), "temperature");
    }
}
