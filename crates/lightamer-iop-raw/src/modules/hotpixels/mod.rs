// SPDX-License-Identifier: GPL-3.0-or-later
// Transcribed from darktable src/iop/hotpixels.c @ release-5.7.0
// (Copyright (C) 2011-2026 darktable developers).
// Modified for Lightamer: 2026-11-28 transcribed to Rust (bayer/mono/xtrans
// legs, commit incl. kind-gated markfixed; pixel-fix count, GUI not transcribed).
//! `hotpixels`: dampen abnormally bright pixels with their neighbors.
//!
//! Upstream anchors (`src/iop/hotpixels.c` @ `release-5.7.0`): `process`
//! `:327-356`, `commit_params` `:368-385`, `reload_defaults` `:358-366`,
//! `_process_bayer` `:105-158`, `_process_monochrome` `:161-216`,
//! `_process_xtrans` `:219-325`, `init_pipe`/`cleanup_pipe` `:387-398`.
use rayon::prelude::*;
use std::sync::Arc;

use lightamer_iop_traits::{
    CfaColor, CfaPattern, ColorRequirement, ColorSpace, CommitData, HistoryKeys, ImageInfo,
    IopModule, ModuleDesc, ModuleFlags, ModuleGroup, OrderKey, OrderKeys, ParamField, ParamType,
    ParamsDesc, PipeError, PipeKind, PipeState, Plane, PlaneMut, Roi, SharedModule, get_bool,
    get_float, par_map_rows,
};
use serde_json::{Map, Value};

/// Settings: fix strength, detection threshold, and the two switches.
/// Defaults are upstream's `$DEFAULT`s (`hotpixels.c:35-41`).
static FIELDS: &[ParamField] = &[
    ParamField {
        name: "strength",
        ty: ParamType::Float,
    },
    ParamField {
        name: "threshold",
        ty: ParamType::Float,
    },
    ParamField {
        name: "markfixed",
        ty: ParamType::Bool,
    },
    ParamField {
        name: "permissive",
        ty: ParamType::Bool,
    },
];

/// Module descriptor: id + orders from the A3 stub, everything else filled
/// from upstream (`flags()` `:85-88`, `default_group()` `:80-83`,
/// `default_colorspace()` `:90-95`, `IOP_FLAGS_ONE_INSTANCE`).
pub static DESC: ModuleDesc = ModuleDesc {
    id: "hotpixels",
    display_key: None,
    group: Some(ModuleGroup::Correction),
    order: OrderKeys {
        raw: OrderKey {
            priority: 6.0,
            tie: 6,
        },
        jpg: OrderKey {
            priority: 6.0,
            tie: 6,
        },
    },
    params: ParamsDesc {
        fields: Some(FIELDS),
    },
    flags: Some(ModuleFlags::BLEND),
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
    Arc::new(HotpixelsModule)
}

/// The hotpixels module: stateless, everything flows through commit data.
#[derive(Debug)]
pub struct HotpixelsModule;

/// Sealed commit product: detection pair, switches, mono legs, CFA snapshot,
/// applicability. Fixed-size stack data; the [`CommitData`] `Arc` is its
/// only heap.
#[derive(Debug, Clone, Copy)]
#[expect(clippy::struct_excessive_bools)]
// Five named facts mirror five upstream commit fields; a bitfield would hide them.
struct HotpixelsCommit {
    threshold: f32,
    multiplier: f32,
    permissive: bool,
    markfixed: bool,
    monochrome: bool,
    pure_monochrome: bool,
    #[cfg_attr(not(test), expect(dead_code))]
    // Upstream writes `d->filters` at commit but `process` branches on
    // `pipe->dsc.filters` instead, so the snapshot is never read there
    // either; stored for fidelity, the leg below reads process-time state.
    cfa: CfaPattern,
    applies: bool,
}

/// Upstream's parameter domain (`$MIN: 0.0 $MAX: 1.0` on both sliders).
fn check_unit(name: &str, value: f64) -> Result<f32, PipeError> {
    if !value.is_finite() || value < 0.0 || value > 1.0 {
        return Err(PipeError::InvalidParams(format!(
            "hotpixels '{name}' wants 0..=1, found {value}"
        )));
    }
    #[expect(clippy::cast_possible_truncation)]
    // Narrowing a 0..=1 finite double to float rounds once, like the C
    // params the GUI sliders produce.
    Ok(value as f32)
}

/// Reads an optional tagged float: strict shape when present, [`None`] when
/// the key is absent (the caller falls back to upstream's default).
fn get_opt_float(params: &Map<String, Value>, name: &str) -> Result<Option<f64>, PipeError> {
    if params.get(name).is_none() {
        return Ok(None);
    }
    get_float(params, name).map(Some)
}

/// Reads an optional tagged switch: strict shape when present.
fn get_opt_bool(params: &Map<String, Value>, name: &str) -> Result<Option<bool>, PipeError> {
    if params.get(name).is_none() {
        return Ok(None);
    }
    get_bool(params, name).map(Some)
}

/// Neighbors that must agree: 3 permissive, 4 strict (`min_neighbours`).
fn min_neighbours(commit: &HotpixelsCommit) -> u32 {
    if commit.permissive { 3 } else { 4 }
}

fn resolve_commit(
    params: &Map<String, Value>,
    image: &ImageInfo,
    state: &PipeState,
    kind: PipeKind,
) -> Result<HotpixelsCommit, PipeError> {
    let strength = check_unit(
        "strength",
        get_opt_float(params, "strength")?.unwrap_or(0.25),
    )?;
    let threshold = check_unit(
        "threshold",
        get_opt_float(params, "threshold")?.unwrap_or(0.05),
    )?;
    let markfixed_param = get_opt_bool(params, "markfixed")?.unwrap_or(false);
    let permissive = get_opt_bool(params, "permissive")?.unwrap_or(false);
    let raw = image.raw;
    let monochrome = raw.is_some_and(|raw| raw.monochrome_bayer);
    let pure_monochrome = raw.is_some_and(|raw| raw.s_raw && raw.monochrome);
    // `commit_params` `:368-385`, in order: the multiplier halves the
    // strength (halving a 0..=1 float is exact, like the C double quotient
    // it lands from); `markfixed` drops on thumbnail and export pipes.
    Ok(HotpixelsCommit {
        threshold,
        multiplier: strength / 2.0,
        permissive,
        markfixed: markfixed_param && !matches!(kind, PipeKind::Thumbnail | PipeKind::Export),
        monochrome,
        pure_monochrome,
        cfa: state.cfa,
        applies: (image.is_raw() || pure_monochrome) && strength != 0.0,
    })
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
            "hotpixels passthrough needs equal shapes, got {}x{} in and {}x{} out",
            rin.width, rin.height, rout.width, rout.height
        )));
    }
    if input.width() != output.width() || input.height() != output.height() {
        return Err(PipeError::RoiMismatch(format!(
            "hotpixels planes differ: {}x{} vs {}x{}",
            input.width(),
            input.height(),
            output.width(),
            output.height()
        )));
    }
    if input.channels() != output.channels() {
        return Err(PipeError::RoiMismatch(format!(
            "hotpixels channels differ: {} vs {}",
            input.channels(),
            output.channels()
        )));
    }
    let rows = usize::try_from(rout.height.max(0))
        .map_err(|_| PipeError::RoiMismatch(format!("hotpixels height {} overflows", rout.height)))?;
    let row_len = u64::from(input.width())
        .checked_mul(u64::from(input.channels()))
        .and_then(|len| usize::try_from(len).ok())
        .ok_or_else(|| {
            PipeError::RoiMismatch(format!("hotpixels width {} overflows", input.width()))
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
    )
}

/// One float at tile `(r, c)`: [`None`] when the address leaves the buffer.
/// Callers pre-check every in-range bound; neighbor addresses that wrap
/// (unreachable in the transcribed loops) refuse here instead of trapping.
fn sample(input: &[f32], stride: usize, r: usize, c: usize) -> Option<f32> {
    let at = r.checked_mul(stride)?.checked_add(c)?;
    input.get(at).copied()
}

/// Counts how many of the four neighbors sit below `mid`, tracking their
/// maximum — the `TESTONE` sequence (`:131-141`), same order (the maximum
/// is order-free, but the transcription keeps it anyway).
fn detect(mid: f32, neighbors: [f32; 4]) -> (u32, f32) {
    let mut count = 0;
    let mut maxin = 0.0;
    for other in neighbors {
        if mid > other {
            count += 1;
            if other > maxin {
                maxin = other;
            }
        }
    }
    (count, maxin)
}

/// Paints the same-color cross around a fixed pixel: offsets 2..=10 step 2
/// while inside the row — the bayer `markfixed` loops (`:149-150`) with the
/// signed counter rewritten unsigned (same sequence, same bounds).
fn mark_bayer(row: &mut [f32], c: usize, width: usize, center: f32) {
    for k in (2..=10).step_by(2) {
        if k > c {
            break;
        }
        if let Some(slot) = row.get_mut(c - k) {
            *slot = center;
        }
    }
    for k in (2..=10).step_by(2) {
        if c + k >= width {
            break;
        }
        if let Some(slot) = row.get_mut(c + k) {
            *slot = center;
        }
    }
}

/// Paints the mono cross: offsets 1..=10 step 1 while inside the row, on
/// all `planes` floats — the mono `markfixed` loops (`:206-209`) with the
/// signed counter rewritten unsigned and the stride read from `planes`.
fn mark_mono(row: &mut [f32], c: usize, width: usize, planes: usize, center: f32) {
    for k in 1..=10 {
        if k > c {
            break;
        }
        for ch in 0..planes {
            if let Some(slot) = row.get_mut((c - k) * planes + ch) {
                *slot = center;
            }
        }
    }
    for k in 1..=10 {
        if c + k >= width {
            break;
        }
        for ch in 0..planes {
            if let Some(slot) = row.get_mut((c + k) * planes + ch) {
                *slot = center;
            }
        }
    }
}

/// X-Trans neighbor search order (`_process_xtrans` `:229-248`), verbatim.
const XTRANS_SEARCH: [[i32; 2]; 20] = [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
    [-1, -1],
    [-1, 1],
    [1, -1],
    [1, 1],
    [-2, 0],
    [2, 0],
    [0, -2],
    [0, 2],
    [-2, -1],
    [-2, 1],
    [2, -1],
    [2, 1],
    [-1, -2],
    [1, -2],
    [-1, 2],
    [1, 2],
];

/// Paints the X-Trans cross: offsets 2..=10 step 1 while inside the row,
/// same-color cells only — the xtrans `markfixed` loops (`:304-317`) with
/// the signed counter rewritten unsigned (same sequence, same bounds).
fn mark_xtrans(
    row: &mut [f32],
    shifted: &[[CfaColor; 6]; 6],
    r: usize,
    c: usize,
    width: usize,
    center: f32,
) {
    let middle = shifted
        .get(r % 6)
        .and_then(|table_row| table_row.get(c % 6))
        .copied();
    let Some(middle) = middle else {
        return;
    };
    for k in 2..=10 {
        if k > c {
            break;
        }
        let same = shifted
            .get(r % 6)
            .and_then(|table_row| table_row.get((c - k) % 6))
            .is_some_and(|color| *color == middle);
        if same && let Some(slot) = row.get_mut(c - k) {
            *slot = center;
        }
    }
    for k in 2..=10 {
        if c + k >= width {
            break;
        }
        let same = shifted
            .get(r % 6)
            .and_then(|table_row| table_row.get((c + k) % 6))
            .is_some_and(|color| *color == middle);
        if same && let Some(slot) = row.get_mut(c + k) {
            *slot = center;
        }
    }
}

impl IopModule for HotpixelsModule {
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
        let Some(commit) = data.downcast_ref::<HotpixelsCommit>() else {
            return Err(PipeError::Backend(
                "hotpixels opened a foreign commit".to_owned(),
            ));
        };
        if !commit.applies {
            return passthrough(input, output, rin, rout);
        }
        // Identity geometry (hotpixels implements no roi pair upstream):
        // shapes match or the caller miswired. Origins match too: the
        // X-Trans leg maps the tile origin onto the CFA table, so a split
        // origin would silently read the wrong phase.
        if rin.width != rout.width || rin.height != rout.height {
            return Err(PipeError::RoiMismatch(format!(
                "hotpixels needs equal shapes, got {}x{} in and {}x{} out",
                rin.width, rin.height, rout.width, rout.height
            )));
        }
        if rin.x != rout.x || rin.y != rout.y {
            return Err(PipeError::RoiMismatch(format!(
                "hotpixels needs equal origins, got ({},{}) in and ({},{}) out",
                rin.x, rin.y, rout.x, rout.y
            )));
        }
        // `process` `:334`: the mono small-RAW leg interleaves four floats
        // per pixel, every other leg one.
        let planes: usize = if commit.pure_monochrome { 4 } else { 1 };
        let planes32: u32 = if commit.pure_monochrome { 4 } else { 1 };
        if input.channels() != output.channels() {
            return Err(PipeError::RoiMismatch(format!(
                "hotpixels channels differ: {} vs {}",
                input.channels(),
                output.channels()
            )));
        }
        if input.channels() != planes32 {
            return Err(PipeError::UnsupportedFormat(format!(
                "hotpixels needs {planes} channel(s), got {}",
                input.channels()
            )));
        }
        let rows = usize::try_from(rout.height.max(0))
            .map_err(|_| PipeError::RoiMismatch(format!("hotpixels height {} overflows", rout.height)))?;
        let width = usize::try_from(rout.width.max(0))
            .map_err(|_| PipeError::RoiMismatch(format!("hotpixels width {} overflows", rout.width)))?;
        let row_len = width
            .checked_mul(planes)
            .ok_or_else(|| PipeError::RoiMismatch("hotpixels row overflows".to_owned()))?;
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
                "hotpixels tile overruns its planes".to_owned(),
            ));
        }
        // The loop below only fixes a few pixels, so everything copies
        // first (`process` `:335`).
        par_map_rows(
            input.as_slice(),
            output.as_mut_slice(),
            rows,
            src_stride,
            dst_stride,
            row_len,
            |src, dst| dst.copy_from_slice(src),
        )?;
        if commit.monochrome || commit.pure_monochrome {
            run_mono(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                rows,
                width,
                src_stride,
                dst_stride,
                planes,
            );
        } else if matches!(state.cfa, CfaPattern::XTrans(_)) {
            run_xtrans(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                rows,
                width,
                src_stride,
                dst_stride,
                state.cfa,
                rout,
            );
        } else {
            run_bayer(
                commit,
                input.as_slice(),
                output.as_mut_slice(),
                rows,
                width,
                src_stride,
                dst_stride,
            );
        }
        // Upstream writes no `dsc` here; state passes through untouched.
        Ok(())
    }
}

/// Renders the Bayer leg row-parallel (rayon), one float at a time, in
/// upstream evaluation order — no fused or reordered arithmetic. Rows are
/// independent: detection reads the input, marks land on their own row.
/// Callers pre-check every bound; the `get`s below only restate them.
#[allow(clippy::too_many_arguments)]
fn run_bayer(
    commit: &HotpixelsCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
) {
    if rows < 5 || width < 5 {
        return; // `row < height - 2` from 2 is empty, like upstream
    }
    let min = min_neighbours(commit);
    dst.par_chunks_exact_mut(dst_stride)
        .take(rows)
        .enumerate()
        .for_each(|(r, d_row)| {
            if r < 2 || r >= rows - 2 {
                return;
            }
            for c in 2..width - 2 {
                let Some(center) = sample(src, src_stride, r, c) else {
                    continue;
                };
                let mid = center * commit.multiplier;
                if center > commit.threshold {
                    let n0 = sample(src, src_stride, r, c - 2);
                    let n1 = sample(src, src_stride, r - 2, c);
                    let n2 = sample(src, src_stride, r, c + 2);
                    let n3 = sample(src, src_stride, r + 2, c);
                    let (Some(n0), Some(n1), Some(n2), Some(n3)) = (n0, n1, n2, n3) else {
                        continue;
                    };
                    let (count, maxin) = detect(mid, [n0, n1, n2, n3]);
                    if count >= min {
                        if let Some(slot) = d_row.get_mut(c) {
                            *slot = maxin;
                        }
                        if commit.markfixed {
                            mark_bayer(d_row, c, width, center);
                        }
                    }
                }
            }
        });
}

/// Renders the monochrome leg row-parallel (rayon): neighbors at stride
/// `planes`, the fix lands on all `planes` floats. The `markfixed` stride
/// reads `planes` where upstream hardcodes 4 (`:207`, `:209`): identical
/// for the 4-wide leg; on the 1-wide leg the hardcoded 4 mis-writes across
/// rows, escapes the buffer on narrow tiles, and races across OpenMP rows,
/// so no production build can match it there (see the wave report).
#[allow(clippy::too_many_arguments)]
fn run_mono(
    commit: &HotpixelsCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
    planes: usize,
) {
    if rows < 3 || width < 3 || planes == 0 {
        return; // `row < height - 1` from 1 is empty, like upstream
    }
    let min = min_neighbours(commit);
    dst.par_chunks_exact_mut(dst_stride)
        .take(rows)
        .enumerate()
        .for_each(|(r, d_row)| {
            if r < 1 || r >= rows - 1 {
                return;
            }
            for c in 1..width - 1 {
                // `c * planes` stays under the checked `row_len`.
                let Some(center) = sample(src, src_stride, r, c * planes) else {
                    continue;
                };
                let mid = center * commit.multiplier;
                if center > commit.threshold {
                    let n0 = sample(src, src_stride, r, (c - 1) * planes);
                    let n1 = sample(src, src_stride, r - 1, c * planes);
                    let n2 = sample(src, src_stride, r, (c + 1) * planes);
                    let n3 = sample(src, src_stride, r + 1, c * planes);
                    let (Some(n0), Some(n1), Some(n2), Some(n3)) = (n0, n1, n2, n3) else {
                        continue;
                    };
                    let (count, maxin) = detect(mid, [n0, n1, n2, n3]);
                    if count >= min {
                        for ch in 0..planes {
                            if let Some(slot) = d_row.get_mut(c * planes + ch) {
                                *slot = maxin;
                            }
                        }
                        if commit.markfixed {
                            mark_mono(d_row, c, width, planes, center);
                        }
                    }
                }
            }
        });
}

/// Renders the X-Trans leg row-parallel (rayon). The 6x6 table below is the
/// region-shifted `piece->xtrans` (`dt_dev_prepare_piece_cfa`): cell
/// `(j, i)` reads the state table at `((j + oy) % 6, (i + ox) % 6)` with the
/// tile origin `(ox, oy)`, so tile pixel `(r, c)` sees
/// `state[((r + oy) % 6, (c + ox) % 6)]` — exactly what the pre-derived
/// piece table shows upstream's tile-local `(r % 6, c % 6)` read.
#[allow(clippy::too_many_arguments)]
fn run_xtrans(
    commit: &HotpixelsCommit,
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    width: usize,
    src_stride: usize,
    dst_stride: usize,
    cfa: CfaPattern,
    rout: Roi,
) {
    if rows < 5 || width < 5 {
        return;
    }
    let CfaPattern::XTrans(cells) = cfa else {
        return; // unreachable: the caller branches on this pattern
    };
    // `rem_euclid(6)` lands 0..6, so both conversions below hold.
    let ox = usize::try_from(rout.x.rem_euclid(6)).unwrap_or(0);
    let oy = usize::try_from(rout.y.rem_euclid(6)).unwrap_or(0);
    let shifted: [[CfaColor; 6]; 6] = std::array::from_fn(|j| {
        std::array::from_fn(|i| {
            cells
                .get(((j + oy) % 6) * 6 + (i + ox) % 6)
                .copied()
                .unwrap_or(CfaColor::Unknown)
        })
    });
    let offsets = xtrans_offsets(&shifted);
    let min = min_neighbours(commit);
    dst.par_chunks_exact_mut(dst_stride)
        .take(rows)
        .enumerate()
        .for_each(|(r, d_row)| {
            if r < 2 || r >= rows - 2 {
                return;
            }
            for c in 2..width - 2 {
                let Some(center) = sample(src, src_stride, r, c) else {
                    continue;
                };
                let mid = center * commit.multiplier;
                if center <= commit.threshold {
                    continue;
                }
                let Some(cell) = offsets
                    .get(r % 6)
                    .and_then(|table_row| table_row.get(c % 6))
                else {
                    continue;
                };
                let mut count = 0;
                let mut maxin = 0.0;
                for pair in cell {
                    let [dx, dy] = *pair;
                    let nr = r.wrapping_add_signed(isize::try_from(dy).unwrap_or(0));
                    let nc = c.wrapping_add_signed(isize::try_from(dx).unwrap_or(0));
                    let Some(other) = nr
                        .checked_mul(src_stride)
                        .and_then(|base| base.checked_add(nc))
                        .and_then(|at| src.get(at).copied())
                    else {
                        continue;
                    };
                    if mid > other {
                        count += 1;
                        if other > maxin {
                            maxin = other;
                        }
                    }
                }
                if count >= min {
                    if let Some(slot) = d_row.get_mut(c) {
                        *slot = maxin;
                    }
                    if commit.markfixed {
                        mark_xtrans(d_row, &shifted, r, c, width, center);
                    }
                }
            }
        });
}

/// Per-cell four nearest same-color offsets over the shifted table, in
/// `XTRANS_SEARCH` order — the precomputation atop `_process_xtrans`.
/// Cells hitting fewer than four keep zero offsets (a self-read that never
/// counts); upstream leaves those entries uninitialized (read only where
/// fewer than four same-color cells exist, unreachable on true or these
/// synthetic tables).
fn xtrans_offsets(shifted: &[[CfaColor; 6]; 6]) -> [[[[i32; 2]; 4]; 6]; 6] {
    let mut offsets = [[[[0i32, 0i32]; 4]; 6]; 6];
    for (j, plane) in offsets.iter_mut().enumerate() {
        for (i, slot) in plane.iter_mut().enumerate() {
            let center = shifted
                .get(j)
                .and_then(|table_row| table_row.get(i))
                .copied()
                .unwrap_or(CfaColor::Unknown);
            let jj = i32::try_from(j).unwrap_or(0);
            let ii = i32::try_from(i).unwrap_or(0);
            let mut found = 0;
            for [dx, dy] in XTRANS_SEARCH {
                if found >= 4 {
                    break;
                }
                let r = (jj + dy).rem_euclid(6);
                let c = (ii + dx).rem_euclid(6);
                let (Some(r), Some(c)) =
                    (usize::try_from(r).ok(), usize::try_from(c).ok())
                else {
                    continue;
                };
                let same = shifted
                    .get(r)
                    .and_then(|table_row| table_row.get(c))
                    .is_some_and(|color| *color == center);
                if same {
                    if let Some(entry) = slot.get_mut(found) {
                        *entry = [dx, dy];
                    }
                    found += 1;
                }
            }
        }
    }
    offsets
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{HotpixelsCommit, HotpixelsModule, create};
    use lightamer_iop_traits::{
        CfaColor, CfaPattern, ColorSpace, ImageInfo, IopModule, PipeKind, PipeState, Plane,
        PlaneMut, RawFacts, Roi,
    };
    use serde_json::{Map, Value, json};

    fn facts() -> RawFacts {
        RawFacts {
            black: [512, 512, 512, 512],
            white: 15360,
            wb: [1.0; 4],
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

    fn image() -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(facts())
    }

    fn state() -> PipeState {
        PipeState::from_image(&image())
    }

    fn float_cell(value: f64) -> Value {
        json!({"type": "float", "value": value})
    }

    fn bool_cell(value: bool) -> Value {
        json!({"type": "bool", "value": value})
    }

    fn open(
        module: &HotpixelsModule,
        params: &Map<String, Value>,
        kind: PipeKind,
    ) -> HotpixelsCommit {
        let mut state = state();
        let data = module
            .commit(params, &image(), &mut state, kind)
            .expect("commit");
        data.downcast_ref::<HotpixelsCommit>()
            .copied()
            .expect("our commit")
    }

    #[allow(clippy::too_many_arguments)]
    fn run_process(
        module: &HotpixelsModule,
        params: &Map<String, Value>,
        kind: PipeKind,
        image: &ImageInfo,
        input: &[f32],
        channels: u32,
        w: i32,
        h: i32,
    ) -> Vec<f32> {
        let mut commit_state = PipeState::from_image(image);
        let data = module
            .commit(params, image, &mut commit_state, kind)
            .expect("commit");
        let area = usize::try_from(w * h).expect("area") * usize::try_from(channels).expect("ch");
        let mut output = vec![0.0; area];
        let uw = u32::try_from(w).expect("w");
        let uh = u32::try_from(h).expect("h");
        let stride = usize::try_from(w).expect("stride") * usize::try_from(channels).expect("ch");
        let input_plane =
            Plane::from_slice_channels(input, uw, uh, stride, channels).expect("input plane");
        let mut output_plane =
            PlaneMut::from_slice_channels(&mut output, uw, uh, stride, channels)
                .expect("output plane");
        let roi = Roi::new(0, 0, w, h, 1.0);
        let mut state = PipeState::from_image(image);
        module
            .process(&data, &input_plane, &mut output_plane, roi, roi, &mut state)
            .expect("process");
        output
    }

    #[test]
    fn missing_keys_resolve_to_upstream_defaults() {
        let module = HotpixelsModule;
        let commit = open(&module, &Map::new(), PipeKind::Full);
        assert!(commit.applies);
        assert_eq!(commit.threshold, 0.05);
        assert_eq!(commit.multiplier, 0.125);
        assert!(!commit.markfixed);
        assert!(!commit.permissive);
        assert!(!commit.monochrome);
        assert!(!commit.pure_monochrome);
    }

    #[test]
    fn explicit_keys_win_and_validate() {
        let module = HotpixelsModule;
        let params: Map<String, Value> = [
            ("strength".to_owned(), float_cell(0.5)),
            ("threshold".to_owned(), float_cell(0.2)),
            ("markfixed".to_owned(), bool_cell(true)),
            ("permissive".to_owned(), bool_cell(true)),
        ]
        .into_iter()
        .collect();
        let commit = open(&module, &params, PipeKind::Preview);
        assert_eq!(commit.multiplier, 0.25);
        assert_eq!(commit.threshold, 0.2);
        assert!(commit.markfixed);
        assert!(commit.permissive);

        for (name, value) in [("strength", 2.0), ("threshold", -0.1)] {
            let bad: Map<String, Value> =
                [(name.to_owned(), float_cell(value))].into_iter().collect();
            assert!(module.commit(&bad, &image(), &mut state(), PipeKind::Full).is_err());
        }
        let nan: Map<String, Value> = [("strength".to_owned(), float_cell(f64::NAN))]
            .into_iter()
            .collect();
        assert!(module.commit(&nan, &image(), &mut state(), PipeKind::Full).is_err());
        let mistyped: Map<String, Value> = [("markfixed".to_owned(), float_cell(1.0))]
            .into_iter()
            .collect();
        assert!(module.commit(&mistyped, &image(), &mut state(), PipeKind::Full).is_err());
    }

    #[test]
    fn kind_gates_markfixed() {
        let module = HotpixelsModule;
        let params: Map<String, Value> = [("markfixed".to_owned(), bool_cell(true))]
            .into_iter()
            .collect();
        assert!(open(&module, &params, PipeKind::Full).markfixed);
        assert!(open(&module, &params, PipeKind::Preview).markfixed);
        assert!(!open(&module, &params, PipeKind::Export).markfixed);
        assert!(!open(&module, &params, PipeKind::Thumbnail).markfixed);
    }

    #[test]
    fn strength_zero_and_non_raw_disable() {
        let module = HotpixelsModule;
        let zero: Map<String, Value> = [("strength".to_owned(), float_cell(0.0))]
            .into_iter()
            .collect();
        assert!(!open(&module, &zero, PipeKind::Full).applies);
        let plain = ImageInfo::new(8, 8, ColorSpace::Rgb);
        let mut state = PipeState::from_image(&plain);
        let data = module
            .commit(&Map::new(), &plain, &mut state, PipeKind::Full)
            .expect("commit");
        assert!(!data.downcast_ref::<HotpixelsCommit>().expect("commit").applies);

        // Disabled means the tile passes through untouched.
        let input: Vec<f32> = (0..64i16).map(|i| f32::from(i) * 100.0).collect();
        let output = run_process(&module, &zero, PipeKind::Full, &image(), &input, 1, 8, 8);
        assert_eq!(output, input);
    }

    #[test]
    fn commit_snapshots_the_build_time_cfa() {
        let module = HotpixelsModule;
        let commit = open(&module, &Map::new(), PipeKind::Full);
        assert_eq!(commit.cfa, state().cfa);
    }

    #[test]
    fn bayer_fix_matches_hand_computation() {
        let module = HotpixelsModule;
        let mut input = vec![0.5f32; 64];
        input[3 * 8 + 3] = 5.0;
        let output = run_process(&module, &Map::new(), PipeKind::Full, &image(), &input, 1, 8, 8);
        assert_eq!(output[3 * 8 + 3], 0.5);
        for (i, pixel) in output.iter().enumerate() {
            if i != 3 * 8 + 3 {
                assert_eq!(*pixel, input[i], "pixel {i}");
            }
        }
    }

    #[test]
    fn permissive_fixes_an_adjacent_pair_strict_does_not() {
        let module = HotpixelsModule;
        // Same-color neighbors at distance 2: (4,4) sees the hot (4,6).
        let mut input = vec![0.5f32; 100];
        input[4 * 10 + 4] = 5.0;
        input[4 * 10 + 6] = 5.0;
        let strict = run_process(&module, &Map::new(), PipeKind::Full, &image(), &input, 1, 10, 10);
        assert_eq!(strict[4 * 10 + 4], 5.0);
        assert_eq!(strict[4 * 10 + 6], 5.0);
        let params: Map<String, Value> = [("permissive".to_owned(), bool_cell(true))]
            .into_iter()
            .collect();
        let loose = run_process(&module, &params, PipeKind::Full, &image(), &input, 1, 10, 10);
        assert_eq!(loose[4 * 10 + 4], 0.5);
        assert_eq!(loose[4 * 10 + 6], 0.5);
    }

    #[test]
    fn mono_four_wide_fix_lands_on_all_planes() {
        let module = HotpixelsModule;
        let mut mono = facts();
        mono.s_raw = true;
        mono.monochrome = true;
        mono.cfa = CfaPattern::None;
        let image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(mono);
        let mut input = vec![0.5f32; 8 * 8 * 4];
        input[(3 * 8 + 3) * 4] = 5.0;
        let output = run_process(&module, &Map::new(), PipeKind::Full, &image, &input, 4, 8, 8);
        assert_eq!(&output[(3 * 8 + 3) * 4..(3 * 8 + 4) * 4], &[0.5; 4]);
        for (i, pixel) in output.iter().enumerate() {
            let px = i / 4;
            if px != 3 * 8 + 3 {
                assert_eq!(*pixel, input[i], "sample {i}");
            }
        }
    }

    #[test]
    fn mono_planes_one_markfixed_stays_in_row() {
        let module = HotpixelsModule;
        let mut mono = facts();
        mono.monochrome_bayer = true;
        let image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(mono);
        let mut input = vec![0.5f32; 12 * 12];
        input[5 * 12 + 5] = 5.0;
        let params: Map<String, Value> = [("markfixed".to_owned(), bool_cell(true))]
            .into_iter()
            .collect();
        let output = run_process(&module, &params, PipeKind::Full, &image, &input, 1, 12, 12);
        assert_eq!(output[5 * 12 + 5], 0.5);
        // Marks stride one pixel here (the planes-stride reading of the
        // mono loops), on row 5 only.
        assert_eq!(output[5 * 12 + 4], 5.0);
        assert_eq!(output[5 * 12 + 6], 5.0);
        for (i, pixel) in output.iter().enumerate() {
            let (r, c) = (i / 12, i % 12);
            if r != 5 {
                assert_eq!(*pixel, 0.5, "row {r} col {c}");
            }
        }
    }

    #[test]
    fn descriptor_matches_upstream_metadata() {
        use lightamer_iop_traits::{ColorSpace as Cs, ModuleFlags, ModuleGroup};
        let module = create();
        assert_eq!(module.id(), "hotpixels");
        let desc = module.desc();
        assert_eq!(desc.group, Some(ModuleGroup::Correction));
        assert_eq!(desc.flags, Some(ModuleFlags::BLEND));
        let colors = desc.colorspaces.expect("colorspaces");
        assert_eq!((colors.input, colors.output), (Cs::Raw, Cs::Raw));
        let history = desc.history.expect("history");
        assert!(!history.multi_instance);
        let fields = desc.params.fields.expect("fields");
        assert_eq!(fields.len(), 4);
        assert_eq!(fields[0].name, "strength");
        assert_eq!(fields[3].name, "permissive");
    }
}
