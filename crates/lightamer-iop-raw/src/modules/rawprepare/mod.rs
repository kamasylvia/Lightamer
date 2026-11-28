// SPDX-License-Identifier: GPL-3.0-or-later
// Transcribed from darktable src/iop/rawprepare.c @ release-5.7.0
// (Copyright (C) 2015-2025 darktable developers; based on code by johannes hanika).
// Modified for Lightamer: 2026-11-28 transcribed to Rust (mosaic legs, roi pair,
// commit incl. defaults-from-facts; multichannel leg, gain maps, OpenCL, detail
// mask, GUI not transcribed).
//! `rawprepare`: sensor black/white levels and the legacy crop.
//!
//! Upstream anchors (`src/iop/rawprepare.c` @ `release-5.7.0`): `process`
//! `:322-448`, `commit_params` `:680-740`, `reload_defaults` `:753-777`,
//! `modify_roi_out`/`modify_roi_in` `:253-286`, `_compute_proper_crop`
//! `:195-201`, `_BL` `:314-320`, `_adjust_xtrans_filters` `:301-312`,
//! `_image_is_normalized` `:569-580`.
use rayon::prelude::*;
use std::sync::Arc;

use lightamer_iop_traits::{
    CfaColor, CfaPattern, ColorRequirement, ColorSpace, CommitData, HistoryKeys, ImageInfo,
    IopModule, ModuleDesc, ModuleFlags, ModuleGroup, OrderKey, OrderKeys, ParamField, ParamType,
    ParamsDesc, PipeError, PipeKind, PipeState, Plane, PlaneMut, RawFacts, Roi, SharedModule,
    get_bool, get_int, par_map_rows,
};
use serde_json::{Map, Value};

/// Settings: four crop sides, four black levels, white point, flat-field
/// switch. Fixed arrays surface as named scalars (`black_0`..`black_3`):
/// [`ParamType`] has no list kind (the `Floats`↔`Curve` mapping is
/// curve-payload-only), and `lightamer-iop-traits` is frozen this wave.
static FIELDS: &[ParamField] = &[
    ParamField {
        name: "left",
        ty: ParamType::Int,
    },
    ParamField {
        name: "top",
        ty: ParamType::Int,
    },
    ParamField {
        name: "right",
        ty: ParamType::Int,
    },
    ParamField {
        name: "bottom",
        ty: ParamType::Int,
    },
    ParamField {
        name: "black_0",
        ty: ParamType::Int,
    },
    ParamField {
        name: "black_1",
        ty: ParamType::Int,
    },
    ParamField {
        name: "black_2",
        ty: ParamType::Int,
    },
    ParamField {
        name: "black_3",
        ty: ParamType::Int,
    },
    ParamField {
        name: "white",
        ty: ParamType::Int,
    },
    ParamField {
        name: "flat_field",
        ty: ParamType::Bool,
    },
];

/// Module descriptor: id + orders from the A3 stub, everything else filled
/// from upstream (`flags()` `:104-108`, `default_group()` `:110-113`,
/// `default_colorspace()` `:115-120`, `IOP_FLAGS_ONE_INSTANCE`).
pub static DESC: ModuleDesc = ModuleDesc {
    id: "rawprepare",
    display_key: None,
    group: Some(ModuleGroup::Base),
    order: OrderKeys {
        raw: OrderKey {
            priority: 1.0,
            tie: 0,
        },
        jpg: OrderKey {
            priority: 1.0,
            tie: 0,
        },
    },
    params: ParamsDesc {
        fields: Some(FIELDS),
    },
    flags: Some(ModuleFlags::TILING.union(ModuleFlags::DISTORT)),
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
    Arc::new(RawprepareModule)
}

/// The rawprepare module: stateless, everything flows through commit data.
#[derive(Debug)]
pub struct RawprepareModule;

/// Sealed commit product: levels, crop, cached raw levels, applicability.
/// Fixed-size stack data; the [`CommitData`] `Arc` is its only heap.
#[derive(Debug, Clone, Copy)]
struct RawprepareCommit {
    sub: [f32; 4],
    div: [f32; 4],
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    #[cfg_attr(not(test), expect(dead_code))]
    // Sealed for the future `dsc.rawprepare` publication (no reader in the
    // RAW head outside tests; see the commit comment).
    raw_black_level: u16,
    #[cfg_attr(not(test), expect(dead_code))]
    // Same as above: the commit product stays complete.
    raw_white_point: u16,
    applies: bool,
}

/// Legacy float-bits white meaning "already unit-normalized"
/// (`rawprepare.c:575`, `0x3F800000` = 1.0f bits).
const UNIT_WHITE_BITS: u32 = 0x3F80_0000;

/// Upstream's parameter domain (`$MIN: 0 $MAX: UINT16_MAX` on every level
/// and crop side).
const PARAM_MAX: i64 = 65535;

/// Mirrors `_image_is_normalized` (`:569-580`) for the HDR half: a
/// float-bits capture whose white is 1 (or its legacy magic bits) needs no
/// scaling. The non-HDR half (stored mono float, e.g. sRAW) is unreadable
/// here — commit sees facts, not the stored buffer — and out of scope
/// (A7R5 ARW only); such inputs take the mosaic branch like upstream's
/// `dsc.filters` arm would have.
fn is_normalized(raw: RawFacts) -> bool {
    raw.hdr && (raw.white == 1 || raw.white == UNIT_WHITE_BITS)
}

/// Reads an optional tagged int: strict shape when present, [`None`] when
/// the key is absent (the caller falls back to facts, then neutral).
fn get_opt_int(params: &Map<String, Value>, name: &str) -> Result<Option<i64>, PipeError> {
    if params.contains_key(name) {
        get_int(params, name).map(Some)
    } else {
        Ok(None)
    }
}

fn check_level(name: &str, value: i64) -> Result<u16, PipeError> {
    u16::try_from(value).map_err(|_| {
        PipeError::InvalidParams(format!("rawprepare '{name}' needs 0..=65535, got {value}"))
    })
}

fn check_crop(name: &str, value: i64) -> Result<i32, PipeError> {
    if !(0..=PARAM_MAX).contains(&value) {
        return Err(PipeError::InvalidParams(format!(
            "rawprepare '{name}' needs 0..=65535, got {value}"
        )));
    }
    i32::try_from(value).map_err(|_| PipeError::InvalidParams(format!("rawprepare '{name}' exceeds i32")))
}

/// Matches C `(int)roundf((float)crop * scale)` (`_compute_proper_crop`,
/// `modify_roi_out/in` with `iscale` ≡ 1: this pipe holds full-resolution
/// buffers). Rust `as` saturates garbage scales where C would go undefined;
/// valid inputs compute identically (`f32::round` rounds half away from
/// zero, like `roundf`).
#[expect(clippy::cast_precision_loss, clippy::cast_possible_truncation)]
// Same two conversions upstream applies; `as` only differs on garbage input.
fn scaled_round(crop: i32, scale: f32) -> i32 {
    ((crop as f32) * scale).round() as i32
}

/// Resolves one crop side: explicit key, else the loader crop for left/top
/// (`reload_defaults` `:761-764`), else 0. Right/bottom have no loader fact
/// (`RawFacts` carries only the applied box's origin; the mosaic arrives
/// pre-cropped), so their default is 0 = no further crop.
fn resolve_crop(
    params: &Map<String, Value>,
    name: &str,
    raw: Option<RawFacts>,
    raw_side: fn(RawFacts) -> i32,
) -> Result<i32, PipeError> {
    let fallback = raw.map_or(0, raw_side);
    let value = get_opt_int(params, name)?.unwrap_or(i64::from(fallback));
    check_crop(name, value)
}

/// Resolves one level: explicit key, else the sensor fact.
fn resolve_level(params: &Map<String, Value>, name: &str, raw_value: u32) -> Result<u16, PipeError> {
    let value = get_opt_int(params, name)?.unwrap_or(i64::from(raw_value));
    check_level(name, value)
}

fn resolve_commit(
    params: &Map<String, Value>,
    image: &ImageInfo,
    state: &PipeState,
) -> Result<RawprepareCommit, PipeError> {
    let raw = image.raw;
    let applies = raw.is_some_and(|r| !is_normalized(r));
    let left = resolve_crop(params, "left", raw, |r| r.crop_x)?;
    let top = resolve_crop(params, "top", raw, |r| r.crop_y)?;
    let right = resolve_crop(params, "right", raw, |_| 0)?;
    let bottom = resolve_crop(params, "bottom", raw, |_| 0)?;
    if !applies {
        // Upstream computes levels and then discards them with the disabled
        // piece; same observable behavior with benign constants, and level
        // keys (even garbage shapes) stay unread.
        return Ok(RawprepareCommit {
            sub: [0.0; 4],
            div: [1.0; 4],
            left,
            top,
            right,
            bottom,
            raw_black_level: 0,
            raw_white_point: 0,
            applies: false,
        });
    }
    let Some(facts) = raw else {
        return Err(PipeError::InvalidParams(
            "rawprepare applies without sensor facts".to_owned(),
        ));
    };
    let [f0, f1, f2, f3] = facts.black;
    let black = [
        resolve_level(params, "black_0", f0)?,
        resolve_level(params, "black_1", f1)?,
        resolve_level(params, "black_2", f2)?,
        resolve_level(params, "black_3", f3)?,
    ];
    let white = resolve_level(params, "white", facts.white)?;
    if get_opt_bool(params, "flat_field")? == Some(true) {
        return Err(PipeError::InvalidParams(
            "rawprepare flat_field needs DNG gain maps (untranscribed)".to_owned(),
        ));
    }
    // Upstream branches on `dsc.filters` (`commit_params` `:693-716`); the
    // mosaic test here is the same bit in enum form.
    let mosaic = matches!(state.cfa, CfaPattern::Bayer(_) | CfaPattern::XTrans(_));
    let (sub, div) = if mosaic {
        let white = f32::from(white);
        let [b0, b1, b2, b3] = black;
        let sub = [f32::from(b0), f32::from(b1), f32::from(b2), f32::from(b3)];
        let [s0, s1, s2, s3] = sub;
        (sub, [white - s0, white - s1, white - s2, white - s3])
    } else {
        let normalizer = if facts.hdr { 1.0 } else { 65535.0 };
        let white = f32::from(white) / normalizer;
        let [b0, b1, b2, b3] = black;
        let sub = [
            f32::from(b0) / normalizer,
            f32::from(b1) / normalizer,
            f32::from(b2) / normalizer,
            f32::from(b3) / normalizer,
        ];
        let [s0, s1, s2, s3] = sub;
        (sub, [white - s0, white - s1, white - s2, white - s3])
    };
    // Cached raw levels (`:718-724`): f32 accumulation in channel order.
    // No reader in this wave (the `dsc.rawprepare` publication has none in
    // the RAW head); kept so the commit product stays complete.
    let mut total = 0.0;
    for level in black {
        total += f32::from(level);
    }
    #[expect(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    // Mean of four u16s is in range and non-negative; `as` only differs on
    // garbage input.
    let raw_black_level = (total / 4.0).round() as u16;
    Ok(RawprepareCommit {
        sub,
        div,
        left,
        top,
        right,
        bottom,
        raw_black_level,
        raw_white_point: white,
        applies: true,
    })
}

/// Reads an optional tagged switch: strict shape when present.
fn get_opt_bool(params: &Map<String, Value>, name: &str) -> Result<Option<bool>, PipeError> {
    if params.contains_key(name) {
        get_bool(params, name).map(Some)
    } else {
        Ok(None)
    }
}

/// Copies input to output unchanged: the disabled piece upstream skips.
/// State untouched, like the skipped piece.
fn passthrough(
    input: &Plane<'_>,
    output: &mut PlaneMut<'_>,
    rin: Roi,
    rout: Roi,
) -> Result<(), PipeError> {
    if rin.width != rout.width || rin.height != rout.height {
        return Err(PipeError::RoiMismatch(format!(
            "rawprepare passthrough needs equal shapes, got {}x{} in and {}x{} out",
            rin.width, rin.height, rout.width, rout.height
        )));
    }
    if input.width() != output.width() || input.height() != output.height() {
        return Err(PipeError::RoiMismatch(format!(
            "rawprepare planes differ: {}x{} vs {}x{}",
            input.width(),
            input.height(),
            output.width(),
            output.height()
        )));
    }
    if input.channels() != output.channels() {
        return Err(PipeError::RoiMismatch(format!(
            "rawprepare channels differ: {} vs {}",
            input.channels(),
            output.channels()
        )));
    }
    let rows = usize::try_from(rout.height.max(0))
        .map_err(|_| PipeError::RoiMismatch(format!("rawprepare height {} overflows", rout.height)))?;
    let row_len = u64::from(input.width())
        .checked_mul(u64::from(input.channels()))
        .and_then(|len| usize::try_from(len).ok())
        .ok_or_else(|| PipeError::RoiMismatch(format!("rawprepare width {} overflows", input.width())))?;
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
    )
}

/// Shifts a Bayer pattern by the crop: cell `(r, c)` comes from
/// `((r + csy) % 2, (c + csx) % 2)`, the enum form of
/// `dt_rawspeed_crop_dcraw_filters` (verified against it by the oracle
/// tests, not by reading bits here).
fn shift_bayer(cells: [CfaColor; 4], csx: usize, csy: usize) -> [CfaColor; 4] {
    let [a, b, c, d] = cells;
    match (csx & 1, csy & 1) {
        (0, 0) => cells,
        (1, 0) => [b, a, d, c],
        (0, 1) => [c, d, a, b],
        _ => [d, c, b, a],
    }
}

/// Shifts an X-Trans table by the crop, verbatim
/// `_adjust_xtrans_filters` index math (`new[j][i] = old[(j + y) % 6][(i + x) % 6]`).
fn shift_xtrans(cells: [CfaColor; 36], csx: usize, csy: usize) -> [CfaColor; 36] {
    std::array::from_fn(|k| {
        let row = k / 6;
        let col = k % 6;
        let from = ((row + csy) % 6) * 6 + ((col + csx) % 6);
        cells.get(from).copied().unwrap_or(CfaColor::Unknown)
    })
}

impl IopModule for RawprepareModule {
    fn desc(&self) -> &ModuleDesc {
        &DESC
    }

    fn commit(
        &self,
        params: &Map<String, Value>,
        image: &ImageInfo,
        state: &mut PipeState,
        _kind: PipeKind,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(resolve_commit(params, image, state)?))
    }

    fn roi_out(&self, data: &CommitData, rin: Roi) -> Roi {
        let Some(commit) = data.downcast_ref::<RawprepareCommit>() else {
            return rin;
        };
        if !commit.applies {
            return rin; // disabled pieces leave geometry alone, like upstream
        }
        let dw = scaled_round(commit.left + commit.right, rin.scale);
        let dh = scaled_round(commit.top + commit.bottom, rin.scale);
        Roi {
            x: 0,
            y: 0,
            width: rin.width.saturating_sub(dw),
            height: rin.height.saturating_sub(dh),
            scale: rin.scale,
        }
    }

    fn roi_in(&self, data: &CommitData, rout: Roi) -> Roi {
        let Some(commit) = data.downcast_ref::<RawprepareCommit>() else {
            return rout;
        };
        if !commit.applies {
            return rout;
        }
        let dw = scaled_round(commit.left + commit.right, rout.scale);
        let dh = scaled_round(commit.top + commit.bottom, rout.scale);
        Roi {
            x: rout.x,
            y: rout.y,
            width: rout.width.saturating_add(dw),
            height: rout.height.saturating_add(dh),
            scale: rout.scale,
        }
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
        let Some(commit) = data.downcast_ref::<RawprepareCommit>() else {
            return Err(PipeError::Backend(
                "rawprepare opened a foreign commit".to_owned(),
            ));
        };
        if !commit.applies {
            return passthrough(input, output, rin, rout);
        }
        if input.channels() != output.channels() {
            return Err(PipeError::RoiMismatch(format!(
                "rawprepare channels differ: {} vs {}",
                input.channels(),
                output.channels()
            )));
        }
        if input.channels() != 1 {
            // The pre-downsampled multichannel leg (`process` `:382-402`) is
            // not transcribed: no such input exists on this pipe, and silent
            // passthrough would diverge from upstream scaling. Loud refusal.
            return Err(PipeError::UnsupportedFormat(
                "rawprepare transcribes the mono mosaic legs only".to_owned(),
            ));
        }
        if matches!(state.cfa, CfaPattern::None) {
            // Mosaic branch without a pattern: unreachable in-pipe (sensor
            // facts always carry one), and passthrough would diverge from
            // upstream's unmosaiced scaling. Loud refusal.
            return Err(PipeError::UnsupportedFormat(
                "rawprepare mosaic branch without a CFA pattern".to_owned(),
            ));
        }
        let csx = scaled_round(commit.left, rin.scale);
        let csy = scaled_round(commit.top, rin.scale);
        if csx < 0 || csy < 0 {
            return Err(PipeError::RoiMismatch(format!(
                "rawprepare negative crop offset {csx}x{csy}"
            )));
        }
        let rows = usize::try_from(rout.height)
            .map_err(|_| PipeError::RoiMismatch(format!("rawprepare height {} invalid", rout.height)))?;
        let row_len = usize::try_from(rout.width)
            .map_err(|_| PipeError::RoiMismatch(format!("rawprepare width {} invalid", rout.width)))?;
        let csx = usize::try_from(csx)
            .map_err(|_| PipeError::RoiMismatch("rawprepare crop offset overflows".to_owned()))?;
        let csy = usize::try_from(csy)
            .map_err(|_| PipeError::RoiMismatch("rawprepare crop offset overflows".to_owned()))?;
        let src_stride = input.stride();
        let dst_stride = output.stride();
        // Bounds before a single lane spawns: every addressed row must exist
        // whole. Stricter than `Plane` (which allows a short tail): the
        // chunk-addressed loop below cannot reach a partial last row, so a
        // short tail refuses loudly instead of leaving zeros there. In-pipe
        // frames are tight; only hand-built planes can trip this.
        let fits = |stride: usize, skip_rows: usize, skip_cols: usize, len: usize| -> bool {
            skip_cols
                .checked_add(row_len)
                .is_some_and(|need| need <= stride)
                && rows
                    .checked_add(skip_rows)
                    .and_then(|touched| touched.checked_mul(stride))
                    .is_some_and(|need| need <= len)
        };
        if rows == 0 || row_len == 0 {
            // Empty tile: upstream still publishes state below.
        } else if !fits(src_stride, csy, csx, input.as_slice().len())
            || !fits(dst_stride, 0, 0, output.as_mut_slice().len())
        {
            return Err(PipeError::RoiMismatch(
                "rawprepare tile overruns its planes".to_owned(),
            ));
        } else {
            run_mosaic(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                rows,
                row_len,
                src_stride,
                dst_stride,
                csx,
                csy,
                rout,
            );
        }
        state.processed_maximum = [1.0; 4];
        state.cfa = match state.cfa {
            CfaPattern::Bayer(cells) => CfaPattern::Bayer(shift_bayer(cells, csx, csy)),
            CfaPattern::XTrans(cells) => CfaPattern::XTrans(shift_xtrans(cells, csx, csy)),
            CfaPattern::None => CfaPattern::None,
        };
        Ok(())
    }
}

/// Renders `(in - sub[id]) / div[id]` row-parallel (rayon), one float at a
/// time, in upstream evaluation order — no fused or reordered arithmetic.
/// `id` is `_BL`: `(((j + oy + top) & 1) << 1) | ((i + ox + left) & 1)`.
/// Callers pre-check every bound; the `get`s below only restate them.
#[allow(clippy::too_many_arguments)]
fn run_mosaic(
    commit: &RawprepareCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    row_len: usize,
    src_stride: usize,
    dst_stride: usize,
    csx: usize,
    csy: usize,
    rout: Roi,
) {
    let [s0, s1, s2, s3] = commit.sub;
    let [d0, d1, d2, d3] = commit.div;
    // Parities in i64: exact where C would overflow into UB, identical low
    // bits everywhere else (two's complement `& 1`).
    let row_base = usize::from(((i64::from(rout.y) + i64::from(commit.top)) & 1) != 0);
    let col_base = usize::from(((i64::from(rout.x) + i64::from(commit.left)) & 1) != 0);
    let src_rows = src.get(csy * src_stride..).unwrap_or(&[]);
    src_rows
        .par_chunks_exact(src_stride)
        .zip(dst.par_chunks_exact_mut(dst_stride))
        .take(rows)
        .enumerate()
        .for_each(|(j, (s_row, d_row))| {
            let row_bit = (j & 1) ^ row_base;
            let (se, de, so, odd) = if row_bit == 0 {
                (s0, d0, s1, d1)
            } else {
                (s2, d2, s3, d3)
            };
            let (Some(s), Some(d)) = (
                s_row.get(csx..csx + row_len),
                d_row.get_mut(..row_len),
            ) else {
                // Unreachable by the caller's pre-checks; skip, never trap.
                return;
            };
            for (i, (sample, pixel)) in s.iter().zip(d.iter_mut()).enumerate() {
                let col_bit = (i & 1) ^ col_base;
                let (sub, div) = if col_bit == 0 { (se, de) } else { (so, odd) };
                *pixel = (*sample - sub) / div;
            }
        });
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{RawprepareCommit, RawprepareModule, create, is_normalized, shift_bayer};
    use lightamer_iop_traits::{
        BufferDataType, CfaColor, CfaPattern, ColorSpace, ImageInfo, IopModule, PipeKind, PipeState,
        Plane, PlaneMut, RawFacts, Roi,
    };
    use serde_json::{Map, Value, json};

    fn facts() -> RawFacts {
        RawFacts {
            black: [512, 520, 508, 516],
            white: 15360,
            wb: [1.0; 4],
            xyz_to_cam_d65: None,
            cam_to_xyz_d65: None,
            cfa: CfaPattern::Bayer([CfaColor::Red, CfaColor::Green, CfaColor::Green, CfaColor::Blue]),
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

    fn image() -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(facts())
    }

    fn state() -> PipeState {
        PipeState::from_image(&image())
    }

    fn int_cell(value: i64) -> Value {
        json!({"type": "int", "value": value})
    }

    fn bool_cell(value: bool) -> Value {
        json!({"type": "bool", "value": value})
    }

    fn open(module: &RawprepareModule, params: &Map<String, Value>) -> RawprepareCommit {
        let mut state = state();
        let data = module.commit(params, &image(), &mut state, PipeKind::Full).expect("commit");
        data.downcast_ref::<RawprepareCommit>().copied().expect("our commit")
    }

    #[test]
    fn missing_keys_resolve_from_sensor_facts() {
        let module = RawprepareModule;
        let commit = open(&module, &Map::new());
        assert!(commit.applies);
        assert_eq!((commit.left, commit.top, commit.right, commit.bottom), (0, 0, 0, 0));
        assert_eq!(commit.sub, [512.0, 520.0, 508.0, 516.0]);
        assert_eq!(commit.div, [14848.0, 14840.0, 14852.0, 14844.0]);
        assert_eq!(commit.raw_black_level, 514);
        assert_eq!(commit.raw_white_point, 15360);
    }

    #[test]
    fn explicit_keys_win_and_validate() {
        let module = RawprepareModule;
        let params: Map<String, Value> = [
            ("black_0".to_owned(), int_cell(100)),
            ("white".to_owned(), int_cell(10000)),
            ("left".to_owned(), int_cell(2)),
            ("flat_field".to_owned(), bool_cell(false)),
        ]
        .into_iter()
        .collect();
        let commit = open(&module, &params);
        assert_eq!(commit.sub[0], 100.0);
        assert_eq!(commit.div[0], 9900.0);
        assert_eq!(commit.left, 2);
        let bad: Map<String, Value> =
            [("white".to_owned(), int_cell(70000))].into_iter().collect();
        assert!(module.commit(&bad, &image(), &mut state(), PipeKind::Full).is_err());
        let bad_crop: Map<String, Value> =
            [("left".to_owned(), int_cell(-1))].into_iter().collect();
        assert!(module.commit(&bad_crop, &image(), &mut state(), PipeKind::Full).is_err());
        let flat: Map<String, Value> =
            [("flat_field".to_owned(), bool_cell(true))].into_iter().collect();
        assert!(module.commit(&flat, &image(), &mut state(), PipeKind::Full).is_err());
    }

    #[test]
    fn normalized_and_non_raw_inputs_do_not_apply() {
        assert!(!is_normalized(facts()));
        let mut hdr = facts();
        hdr.hdr = true;
        hdr.white = 0x3F80_0000;
        assert!(is_normalized(hdr));
        let module = RawprepareModule;
        let mut state = state();
        let plain = ImageInfo::new(8, 8, ColorSpace::Rgb);
        let data = module.commit(&Map::new(), &plain, &mut state, PipeKind::Full).expect("commit");
        let commit = data.downcast_ref::<RawprepareCommit>().expect("our commit");
        assert!(!commit.applies);
    }

    #[test]
    fn roi_pair_crops_and_restores() {
        let module = RawprepareModule;
        let params: Map<String, Value> = [
            ("left".to_owned(), int_cell(2)),
            ("top".to_owned(), int_cell(4)),
            ("right".to_owned(), int_cell(6)),
            ("bottom".to_owned(), int_cell(8)),
        ]
        .into_iter()
        .collect();
        let mut state = state();
        let data = module.commit(&params, &image(), &mut state, PipeKind::Full).expect("commit");
        let rin = Roi::new(0, 0, 64, 64, 1.0);
        let rout = module.roi_out(&data, rin);
        assert_eq!((rout.x, rout.y, rout.width, rout.height), (0, 0, 56, 52));
        let back = module.roi_in(&data, rout);
        assert_eq!((back.width, back.height), (64, 64));
    }

    #[test]
    fn mosaic_pixels_follow_upstream_order() {
        let module = RawprepareModule;
        let data = module.commit(&Map::new(), &image(), &mut state(), PipeKind::Full).expect("commit");
        // 4x4 ramp; levels differ per channel so ids show.
        let input: Vec<f32> = (0..16i16).map(|i| 512.0 + f32::from(i) * 100.0).collect();
        let mut output = vec![0.0; 16];
        let rin = Roi::new(0, 0, 4, 4, 1.0);
        let input_plane = Plane::from_slice_channels(&input, 4, 4, 4, 1).expect("plane");
        let mut output_plane =
            PlaneMut::from_slice_channels(&mut output, 4, 4, 4, 1).expect("plane");
        let mut state = state();
        module
            .process(&data, &input_plane, &mut output_plane, rin, rin, &mut state)
            .expect("process");
        assert_eq!(state.processed_maximum, [1.0; 4]);
        assert!(matches!(state.datatype, BufferDataType::Float));
        // Hand evaluation with (j&1, i&1) ids over black [512,520,508,516].
        let sub = [512.0f32, 520.0, 508.0, 516.0];
        let div = [14848.0f32, 14840.0, 14852.0, 14844.0];
        for j in 0..4 {
            for i in 0..4 {
                let id = ((j & 1) << 1) | (i & 1);
                let want = (input[j * 4 + i] - sub[id]) / div[id];
                assert_eq!(output[j * 4 + i], want, "pixel {j},{i}");
            }
        }
    }

    #[test]
    fn bayer_shift_matches_crop_parity() {
        use CfaColor::{Blue, Green, Red};
        let rggb = [Red, Green, Green, Blue];
        assert_eq!(shift_bayer(rggb, 0, 0), rggb);
        assert_eq!(shift_bayer(rggb, 1, 0), [Green, Red, Blue, Green]);
        assert_eq!(shift_bayer(rggb, 0, 1), [Green, Blue, Red, Green]);
        assert_eq!(shift_bayer(rggb, 3, 3), [Blue, Green, Green, Red]);
    }

    #[test]
    fn descriptor_matches_upstream_metadata() {
        let module = create();
        assert_eq!(module.id(), "rawprepare");
        assert_eq!(module.desc().id, "rawprepare");
        assert_eq!(module.desc().params.fields.expect("fields").len(), 10);
        assert_eq!(module.colorspaces(), (ColorSpace::Raw, ColorSpace::Raw));
    }

    #[test]
    fn short_tail_planes_refuse_loudly() {
        let module = RawprepareModule;
        let data = module.commit(&Map::new(), &image(), &mut state(), PipeKind::Full).expect("commit");
        // Valid short-tail plane: 4x4 stride 5 needs exactly 19 floats.
        let input = vec![600.0; 19];
        let mut output = vec![0.0; 16];
        let rin = Roi::new(0, 0, 4, 4, 1.0);
        let input_plane = Plane::from_slice_channels(&input, 4, 4, 5, 1).expect("plane");
        let mut output_plane =
            PlaneMut::from_slice_channels(&mut output, 4, 4, 4, 1).expect("plane");
        let refused = module.process(&data, &input_plane, &mut output_plane, rin, rin, &mut state());
        assert!(refused.is_err(), "short tail must not render zeros");
    }

    #[test]
    fn nonzero_rout_origin_shifts_bayer_ids() {
        let module = RawprepareModule;
        let data = module.commit(&Map::new(), &image(), &mut state(), PipeKind::Full).expect("commit");
        // rout at (1,1): ids read (((j+1)&1)<<1)|((i+1)&1) over the ramp.
        let input: Vec<f32> = (0..4i16).map(|i| 512.0 + f32::from(i) * 100.0).collect();
        let mut output = vec![0.0; 4];
        let rin = Roi::new(0, 0, 2, 2, 1.0);
        let rout = Roi::new(1, 1, 2, 2, 1.0);
        let input_plane = Plane::from_slice_channels(&input, 2, 2, 2, 1).expect("plane");
        let mut output_plane =
            PlaneMut::from_slice_channels(&mut output, 2, 2, 2, 1).expect("plane");
        module
            .process(&data, &input_plane, &mut output_plane, rin, rout, &mut state())
            .expect("process");
        let sub = [512.0f32, 520.0, 508.0, 516.0];
        let div = [14848.0f32, 14840.0, 14852.0, 14844.0];
        for j in 0..2 {
            for i in 0..2 {
                let id = (((j + 1) & 1) << 1) | ((i + 1) & 1);
                let want = (input[j * 2 + i] - sub[id]) / div[id];
                assert_eq!(output[j * 2 + i], want, "pixel {j},{i}");
            }
        }
    }
}
