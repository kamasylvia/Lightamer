// SPDX-License-Identifier: GPL-3.0-or-later
//! hotpixels against the verbatim upstream oracle: a two-module chain over
//! true ARW tiles plus synthetic tiles run both sides and compare pixels
//! plus chain state.
//!
//! One decode per binary: the true-tile test holds a single `RawSample`
//! and slices regions out of it; synthetic tests allocate kilobytes.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use lightamer_iop_traits::{
    CfaColor, CfaPattern, ColorSpace, ImageInfo, PipeKind, PipeState, Plane, PlaneMut, RawFacts,
    Roi, SharedModule,
};
use lightamer_oracle as oracle;
use lightamer_raster::FrameExtent;
use lightamer_testkit::{IN_TOLERANCE_GATE, MEAN_ABS_GATE, RawSample, compare_planes, skip};
use serde_json::{Map, Value, json};

const SAMPLE: &str = "7RM5-LosslessCompressedLarge.ARW";
const TILE: u32 = 256;

/// Test-side params: strength, threshold, and the two switches.
struct CaseParams {
    strength: f32,
    threshold: f32,
    markfixed: bool,
    permissive: bool,
}

impl CaseParams {
    fn defaults() -> Self {
        Self {
            strength: 0.25,
            threshold: 0.05,
            markfixed: false,
            permissive: false,
        }
    }

    fn json(&self) -> Map<String, Value> {
        json!({
            "strength": {"type": "float", "value": self.strength},
            "threshold": {"type": "float", "value": self.threshold},
            "markfixed": {"type": "bool", "value": self.markfixed},
            "permissive": {"type": "bool", "value": self.permissive},
        })
        .as_object()
        .cloned()
        .expect("object literal")
    }

    fn oracle(&self) -> oracle::HotParams {
        oracle::HotParams {
            strength: self.strength,
            threshold: self.threshold,
            markfixed: self.markfixed,
            permissive: self.permissive,
        }
    }
}

/// Dcraw color number of one Bayer cell (R=0, G=1, B=2); [`None`] for
/// non-RGB cells (never in these tests).
fn bayer_number(cell: CfaColor) -> Option<u32> {
    match cell {
        CfaColor::Red => Some(0),
        CfaColor::Green => Some(1),
        CfaColor::Blue => Some(2),
        CfaColor::Cyan
        | CfaColor::Magenta
        | CfaColor::Yellow
        | CfaColor::White
        | CfaColor::FujiGreen
        | CfaColor::Unknown => None,
    }
}

/// Encodes four Bayer cells as a dcraw filter word (2x2 block repeated).
fn bayer_filters(cells: [CfaColor; 4]) -> u32 {
    let number = |index: usize| bayer_number(cells[index]).expect("RGB Bayer cell");
    let low = number(0) | number(1) << 2 | number(2) << 4 | number(3) << 6;
    low | low << 8 | low << 16 | low << 24
}

/// X-Trans byte (rawspeed `CFAColor` discriminant) back to a cell color.
fn xtrans_cell(byte: u8) -> CfaColor {
    match byte {
        0 => CfaColor::Red,
        1 => CfaColor::Green,
        2 => CfaColor::Blue,
        3 => CfaColor::Cyan,
        4 => CfaColor::Magenta,
        5 => CfaColor::Yellow,
        6 => CfaColor::White,
        7 => CfaColor::FujiGreen,
        _ => CfaColor::Unknown,
    }
}

/// Decodes post-run oracle state into our pattern: Bayer from the filter
/// word's low block (dcraw G2 collapses to green — `CfaColor` has no G2,
/// and RGGB never yields 3), X-Trans bytewise, zero filters to none.
fn pattern_from_oracle(filters: u32, xtrans: &[u8; 36]) -> CfaPattern {
    if filters == 9 {
        let mut cells = [CfaColor::Unknown; 36];
        for (cell, byte) in cells.iter_mut().zip(xtrans.iter()) {
            *cell = xtrans_cell(*byte);
        }
        CfaPattern::XTrans(cells)
    } else if filters == 0 {
        CfaPattern::None
    } else {
        // Dcraw G2 (3) collapses to green: `CfaColor` has no G2, and RGGB
        // never yields 3.
        const MAP: [CfaColor; 4] = [
            CfaColor::Red,
            CfaColor::Green,
            CfaColor::Blue,
            CfaColor::Green,
        ];
        let cell = |shift: u32| MAP[((filters >> shift) & 3) as usize];
        CfaPattern::Bayer([cell(0), cell(2), cell(4), cell(6)])
    }
}

/// Maps decoded facts to oracle facts. Loader right/bottom have no source
/// (`RawFacts` carries only the applied box's origin), so they read 0. A
/// pure mono small-RAW carries no `DT_IMAGE_RAW` bit, like upstream.
fn facts_for_oracle(image: &ImageInfo, stored_is_u16: bool) -> oracle::Facts {
    let raw = image.raw.expect("mosaic facts");
    let black = [
        u16::try_from(raw.black[0]).expect("black fits u16"),
        u16::try_from(raw.black[1]).expect("black fits u16"),
        u16::try_from(raw.black[2]).expect("black fits u16"),
        u16::try_from(raw.black[3]).expect("black fits u16"),
    ];
    let (filters, xtrans) = match raw.cfa {
        CfaPattern::Bayer(cells) => (bayer_filters(cells), [0; 36]),
        CfaPattern::XTrans(cells) => {
            let mut table = [0u8; 36];
            for (slot, cell) in table.iter_mut().zip(cells.iter()) {
                *slot = match cell {
                    CfaColor::Red => 0,
                    CfaColor::Green => 1,
                    CfaColor::Blue => 2,
                    CfaColor::Cyan => 3,
                    CfaColor::Magenta => 4,
                    CfaColor::Yellow => 5,
                    CfaColor::White => 6,
                    CfaColor::FujiGreen => 7,
                    CfaColor::Unknown => 255,
                };
            }
            (9, table)
        }
        CfaPattern::None => (0, [0; 36]),
    };
    let pure_mono = raw.s_raw && raw.monochrome;
    let mut flags = 0;
    if !pure_mono {
        flags |= oracle::DT_IMAGE_RAW;
    }
    if raw.hdr {
        flags |= oracle::DT_IMAGE_HDR;
    }
    if raw.s_raw {
        flags |= oracle::DT_IMAGE_S_RAW;
    }
    if raw.monochrome {
        flags |= oracle::DT_IMAGE_MONOCHROME;
    }
    if raw.monochrome_bayer {
        flags |= oracle::DT_IMAGE_MONOCHROME_BAYER;
    }
    oracle::Facts {
        width: i32::try_from(image.width).expect("width fits"),
        height: i32::try_from(image.height).expect("height fits"),
        p_width: raw.p_width,
        p_height: raw.p_height,
        crop: [raw.crop_x, raw.crop_y, 0, 0],
        black,
        white: raw.white,
        filters,
        xtrans,
        flags,
        buf_channels: if pure_mono { 4 } else { 1 },
        buf_datatype: if stored_is_u16 {
            oracle::BufferType::Uint16
        } else {
            oracle::BufferType::Float
        },
        id: 1,
    }
}

/// Runs our module over one tile: commit, roi, process.
fn run_ours(
    module: &SharedModule,
    params: &Map<String, Value>,
    image: &ImageInfo,
    input: &[f32],
    rin: Roi,
    kind: PipeKind,
    channels: u32,
) -> (Vec<f32>, PipeState, Roi) {
    let mut commit_state = PipeState::from_image(image);
    let data = module
        .commit(params, image, &mut commit_state, kind)
        .expect("commit");
    let rout = module.roi_out(&data, rin);
    let pixels = usize::try_from(
        u64::from(u32::try_from(rout.width).expect("rout width"))
            * u64::from(u32::try_from(rout.height).expect("rout height")),
    )
    .expect("rout area");
    let area = pixels * usize::try_from(channels).expect("channels");
    let mut output = vec![0.0; area];
    let stride =
        usize::try_from(rin.width).expect("rin stride") * usize::try_from(channels).expect("ch");
    let input_plane = Plane::from_slice_channels(
        input,
        u32::try_from(rin.width).expect("rin width"),
        u32::try_from(rin.height).expect("rin height"),
        stride,
        channels,
    )
    .expect("input plane");
    let out_stride =
        usize::try_from(rout.width).expect("rout stride") * usize::try_from(channels).expect("ch");
    let mut output_plane = PlaneMut::from_slice_channels(
        &mut output,
        u32::try_from(rout.width).expect("rout width"),
        u32::try_from(rout.height).expect("rout height"),
        out_stride,
        channels,
    )
    .expect("output plane");
    let mut state = PipeState::from_image(image);
    module
        .process(
            &data,
            &input_plane,
            &mut output_plane,
            rin,
            rout,
            &mut state,
        )
        .expect("process");
    (output, state, rout)
}

/// Runs the oracle over one tile; returns pixels and state (hotpixels is
/// roi-identity, so the caller passes `rin` as its own `rout`).
fn run_oracle(
    facts: &oracle::Facts,
    params: &oracle::HotParams,
    input: &[f32],
    rin: oracle::Roi,
    kind: oracle::PipeType,
) -> (Vec<f32>, oracle::StateOut) {
    oracle::run_hotpixels(facts, params, kind, input, rin, rin).expect("oracle run")
}

/// Runs our two-module chain (rawprepare into hotpixels) over one tile:
/// both commits in order, then both processes with the state evolving.
#[allow(clippy::too_many_arguments)]
fn run_ours_chain(
    rawprepare: &SharedModule,
    hotpixels: &SharedModule,
    rp_params: &Map<String, Value>,
    hp_params: &Map<String, Value>,
    image: &ImageInfo,
    input: &[f32],
    rin: Roi,
    kind: PipeKind,
) -> (Vec<f32>, PipeState, Roi) {
    let mut commit_state = PipeState::from_image(image);
    let rp_data = rawprepare
        .commit(rp_params, image, &mut commit_state, kind)
        .expect("rawprepare commit");
    let mid = rawprepare.roi_out(&rp_data, rin);
    let hp_data = hotpixels
        .commit(hp_params, image, &mut commit_state, kind)
        .expect("hotpixels commit");
    let rout = hotpixels.roi_out(&hp_data, mid);
    let tile = |roi: Roi| {
        let w = u32::try_from(roi.width).expect("tile width");
        let h = u32::try_from(roi.height).expect("tile height");
        (w, h, usize::try_from(roi.width).expect("tile stride"))
    };
    let (in_w, in_h, in_stride) = tile(rin);
    let (mid_w, mid_h, mid_stride) = tile(mid);
    let (out_w, out_h, out_stride) = tile(rout);
    let mut middle = vec![0.0; mid_stride * usize::try_from(mid_h).expect("mid rows")];
    let mut output = vec![0.0; out_stride * usize::try_from(out_h).expect("out rows")];
    let mut state = PipeState::from_image(image);
    {
        let input_plane =
            Plane::from_slice_channels(input, in_w, in_h, in_stride, 1).expect("chain input");
        let mut middle_plane =
            PlaneMut::from_slice_channels(&mut middle, mid_w, mid_h, mid_stride, 1)
                .expect("chain middle");
        rawprepare
            .process(
                &rp_data,
                &input_plane,
                &mut middle_plane,
                rin,
                mid,
                &mut state,
            )
            .expect("rawprepare process");
    }
    {
        let middle_plane =
            Plane::from_slice_channels(&middle, mid_w, mid_h, mid_stride, 1).expect("chain mid");
        let mut output_plane =
            PlaneMut::from_slice_channels(&mut output, out_w, out_h, out_stride, 1)
                .expect("chain output");
        hotpixels
            .process(
                &hp_data,
                &middle_plane,
                &mut output_plane,
                mid,
                rout,
                &mut state,
            )
            .expect("hotpixels process");
    }
    (output, state, rout)
}

/// Asserts the gate triple and prints the numbers for the report. This
/// module only compares, copies, and takes maxima, so the oracle and the
/// transcription must agree bitwise: `max_abs` is asserted, not just read.
fn assert_gate(label: &str, ours: &[f32], theirs: &[f32]) {
    let diff = compare_planes(ours, theirs);
    eprintln!(
        "{label}: mean_abs={:.3e} max_abs={:.3e} in_tol={:.6}",
        diff.mean_abs, diff.max_abs, diff.in_tolerance
    );
    assert!(
        diff.mean_abs < f64::from(MEAN_ABS_GATE),
        "{label}: mean_abs {} over gate",
        diff.mean_abs
    );
    assert!(
        diff.in_tolerance > IN_TOLERANCE_GATE,
        "{label}: in_tol {} under gate",
        diff.in_tolerance
    );
    assert_eq!(diff.max_abs, 0.0, "{label}: not bitwise");
}

fn to_oracle_roi(roi: Roi) -> oracle::Roi {
    oracle::Roi {
        x: roi.x,
        y: roi.y,
        width: roi.width,
        height: roi.height,
        scale: roi.scale,
    }
}

fn to_oracle_kind(kind: PipeKind) -> oracle::PipeType {
    match kind {
        PipeKind::Full => oracle::PipeType::Full,
        PipeKind::Export => oracle::PipeType::Export,
        PipeKind::Preview => oracle::PipeType::Preview,
        PipeKind::Thumbnail => oracle::PipeType::Thumbnail,
    }
}

/// Synthetic mosaic facts: 64x64, given pattern/levels/crop.
fn synth_image(cfa: CfaPattern, black: [u32; 4], white: u32) -> ImageInfo {
    ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(RawFacts {
        black,
        white,
        wb: [1.0; 4],
        xyz_to_cam_d65: None,
        cam_to_xyz_d65: None,
        cfa,
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
    })
}

/// Synthetic mono facts: Bayer-patterned mono (`monochrome_bayer`) or a
/// patternless pure mono small-RAW (`pure`).
fn synth_mono(monochrome_bayer: bool, pure: bool) -> ImageInfo {
    let cfa = if pure { CfaPattern::None } else { rggb() };
    ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(RawFacts {
        black: [512, 512, 512, 512],
        white: 15360,
        wb: [1.0; 4],
        xyz_to_cam_d65: None,
        cam_to_xyz_d65: None,
        cfa,
        crop_x: 0,
        crop_y: 0,
        p_width: 64,
        p_height: 64,
        linear_response_limit: 1.0,
        hdr: false,
        four_bayer: false,
        s_raw: pure,
        monochrome: pure,
        monochrome_bayer,
        load_ok: true,
        camera_missing_sample: false,
    })
}

fn rggb() -> CfaPattern {
    CfaPattern::Bayer([
        CfaColor::Red,
        CfaColor::Green,
        CfaColor::Green,
        CfaColor::Blue,
    ])
}

fn xtrans_cells() -> [CfaColor; 36] {
    // Deterministic 6x6 in R/G/B (validity as a true X-Trans table is
    // irrelevant: both sides derive from the same table).
    std::array::from_fn(|k| match (k / 6 + 2 * (k % 6)) % 3 {
        0 => CfaColor::Red,
        1 => CfaColor::Green,
        _ => CfaColor::Blue,
    })
}

#[test]
fn lookup_and_tables_cover_hotpixels() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    assert_eq!(module.id(), "hotpixels");
    assert!(
        lightamer_iop_raw::MODULES
            .iter()
            .any(|desc| desc.id == "hotpixels"),
        "descriptor table holds hotpixels"
    );
    assert!(
        lightamer_iop_raw::IMPLEMENTED
            .iter()
            .any(|(id, _)| *id == "hotpixels"),
        "implemented table holds hotpixels"
    );
    assert_eq!(module.desc().params.fields.expect("fields").len(), 4);
}

#[test]
fn chain_matches_oracle_on_four_true_tiles() {
    let Some(sample) = RawSample::open(SAMPLE) else {
        skip!(Corpus, "missing {SAMPLE}");
        return;
    };
    let Some(image) = sample.facts() else {
        skip!(Corpus, "no pipe facts for {SAMPLE}");
        return;
    };
    assert!(sample.stored_is_u16(), "ARW mosaic is u16 words");
    let facts = facts_for_oracle(&image, true);
    let rawprepare = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let hotpixels = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    // Defaults on both sides: empty maps here, `reload_defaults` there for
    // rawprepare; hotpixels defaults are static on both sides.
    let rp_params = Map::new();
    let oracle_rp = oracle::rawprepare_defaults(&facts).expect("oracle defaults");
    let hp = CaseParams::defaults();
    let hp_params = hp.json();
    let (width, height) = sample.size();
    assert!(width > TILE && height > TILE, "sample holds 256px tiles");
    let means = sample.block_means(TILE);
    let stride = usize::try_from(width.div_ceil(TILE)).expect("grid stride");
    let full_cols = width / TILE;
    let full_rows = height / TILE;
    let mut best = (0u32, 0u32, f32::MIN);
    let mut worst = (0u32, 0u32, f32::MAX);
    for row in 0..full_rows {
        for col in 0..full_cols {
            let mean = means
                [usize::try_from(row).expect("row") * stride + usize::try_from(col).expect("col")];
            if mean > best.2 {
                best = (col, row, mean);
            }
            if mean < worst.2 {
                worst = (col, row, mean);
            }
        }
    }
    let regions = [
        ("top-left", 0, 0),
        ("center", (width - TILE) / 2, (height - TILE) / 2),
        ("brightest", best.0 * TILE, best.1 * TILE),
        ("darkest", worst.0 * TILE, worst.1 * TILE),
    ];
    for (label, x, y) in regions {
        let extent = FrameExtent::new(
            i32::try_from(x).expect("tile x"),
            i32::try_from(y).expect("tile y"),
            TILE,
            TILE,
        );
        let (frame, _) = sample.region(extent).expect("region converts");
        // Four isolated hot pixels plus one adjacent pair, super-white so
        // the fix triggers whatever the neighbors hold (both sides see the
        // same input, so the gate proves the math, not the realism).
        let mut tile = frame.as_slice().to_vec();
        let at = |r: usize, c: usize| r * usize::try_from(TILE).expect("tile") + c;
        for (r, c) in [(10, 10), (10, 200), (200, 10), (200, 200)] {
            tile[at(r, c)] = 120_000.0;
        }
        tile[at(100, 100)] = 120_000.0;
        tile[at(100, 102)] = 120_000.0;
        let w = i32::try_from(TILE).expect("tile fits");
        let rin = Roi::new(extent.x, extent.y, w, w, 1.0);
        let kind = PipeKind::Full;
        let (ours, our_state, our_rout) = run_ours_chain(
            &rawprepare,
            &hotpixels,
            &rp_params,
            &hp_params,
            &image,
            &tile,
            rin,
            kind,
        );
        let (theirs, their_state, their_rout) = oracle::run_rawprepare_hotpixels(
            &facts,
            &oracle_rp,
            &hp.oracle(),
            to_oracle_kind(kind),
            oracle::TileInput::F32(&tile),
            to_oracle_roi(rin),
        )
        .expect("oracle chain runs");
        assert_eq!(
            (our_rout.width, our_rout.height),
            (their_rout.width, their_rout.height),
            "{label}: roi widths agree"
        );
        assert_gate(&format!("chain true tile {label}"), &ours, &theirs);
        assert!(their_state.enabled, "{label}: oracle stays enabled");
        assert_eq!(our_state.processed_maximum, [1.0; 4], "{label}: our maxima");
        assert_eq!(
            their_state.processed_maximum, [1.0; 4],
            "{label}: oracle maxima"
        );
        assert_eq!(
            our_state.cfa,
            pattern_from_oracle(their_state.filters, &their_state.xtrans),
            "{label}: CFA agrees"
        );
    }
}

#[test]
fn bayer_hot_at_each_phase_matches() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, false);
    let hp = CaseParams::defaults();
    // One hot pixel per Bayer phase, pairwise far apart.
    let mut input = vec![0.5f32; 12 * 12];
    for (r, c) in [(3, 3), (3, 6), (6, 3), (6, 6)] {
        input[r * 12 + c] = 5.0;
    }
    let rin = Roi::new(0, 0, 12, 12, 1.0);
    let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 1);
    let (theirs, _) = run_oracle(
        &facts,
        &hp.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic bayer phases", &ours, &theirs);
    for (r, c) in [(3, 3), (3, 6), (6, 3), (6, 6)] {
        assert_eq!(ours[r * 12 + c], 0.5, "hot at ({r},{c}) fixed");
    }
}

#[test]
fn adjacent_pair_strict_and_permissive_match() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, false);
    let mut input = vec![0.5f32; 10 * 10];
    input[4 * 10 + 4] = 5.0;
    input[4 * 10 + 6] = 5.0;
    let rin = Roi::new(0, 0, 10, 10, 1.0);
    for (label, permissive) in [("strict", false), ("permissive", true)] {
        let hp = CaseParams {
            permissive,
            ..CaseParams::defaults()
        };
        let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 1);
        let (theirs, _) = run_oracle(
            &facts,
            &hp.oracle(),
            &input,
            to_oracle_roi(rin),
            oracle::PipeType::Full,
        );
        assert_gate(&format!("synthetic pair {label}"), &ours, &theirs);
    }
}

#[test]
fn flat_tile_is_identity() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, false);
    let hp = CaseParams::defaults();
    let input = vec![0.5f32; 16 * 16];
    let rin = Roi::new(0, 0, 16, 16, 1.0);
    let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 1);
    let (theirs, _) = run_oracle(
        &facts,
        &hp.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic flat", &ours, &theirs);
    assert_eq!(ours, input, "no hot pixels, bitwise unchanged");
}

#[test]
fn xtrans_matches_at_two_origins() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(
        CfaPattern::XTrans(xtrans_cells()),
        [512, 512, 512, 512],
        15360,
    );
    let facts = facts_for_oracle(&image, false);
    assert_eq!(facts.filters, 9, "X-Trans filter word");
    let hp = CaseParams::defaults();
    let mut input = vec![0.5f32; 16 * 16];
    input[5 * 16 + 5] = 5.0;
    input[10 * 16 + 8] = 5.0;
    // The nonzero origin is the strong case: it proves the region-shifted
    // table lines up with upstream's pre-derived piece table.
    for (label, x, y) in [("origin", 0, 0), ("offset", 1, 3)] {
        let rin = Roi::new(x, y, 16, 16, 1.0);
        let (ours, our_state, _) =
            run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 1);
        let (theirs, their_state) = run_oracle(
            &facts,
            &hp.oracle(),
            &input,
            to_oracle_roi(rin),
            oracle::PipeType::Full,
        );
        assert_gate(&format!("synthetic xtrans {label}"), &ours, &theirs);
        assert_eq!(
            our_state.cfa,
            pattern_from_oracle(their_state.filters, &their_state.xtrans),
            "{label}: X-Trans table agrees"
        );
    }
}

#[test]
fn mono_bayer_matches() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_mono(true, false);
    let facts = facts_for_oracle(&image, false);
    let hp = CaseParams::defaults();
    let mut input = vec![0.5f32; 8 * 8];
    input[4 * 8 + 4] = 5.0;
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 1);
    let (theirs, _) = run_oracle(
        &facts,
        &hp.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic mono bayer", &ours, &theirs);
    assert_eq!(ours[4 * 8 + 4], 0.5, "mono hot pixel fixed");
}

#[test]
fn mono_pure_matches_plain_and_marked() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_mono(false, true);
    let facts = facts_for_oracle(&image, false);
    let mut input = vec![0.5f32; 8 * 8 * 4];
    input[(4 * 8 + 4) * 4] = 5.0;
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    for (label, markfixed) in [("plain", false), ("marked", true)] {
        let hp = CaseParams {
            markfixed,
            ..CaseParams::defaults()
        };
        let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 4);
        let (theirs, _) = run_oracle(
            &facts,
            &hp.oracle(),
            &input,
            to_oracle_roi(rin),
            oracle::PipeType::Full,
        );
        assert_gate(&format!("synthetic mono pure {label}"), &ours, &theirs);
    }
}

#[test]
fn strength_zero_passes_through() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, false);
    let hp = CaseParams {
        strength: 0.0,
        ..CaseParams::defaults()
    };
    let mut input = vec![0.5f32; 8 * 8];
    input[3 * 8 + 3] = 5.0;
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, PipeKind::Full, 1);
    let (theirs, their_state) = run_oracle(
        &facts,
        &hp.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic strength zero", &ours, &theirs);
    assert!(!their_state.enabled, "oracle disables the piece");
    assert_eq!(ours, input, "strength zero passes through");
}

#[test]
fn markfixed_preview_and_export_match() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, false);
    let hp = CaseParams {
        markfixed: true,
        ..CaseParams::defaults()
    };
    let mut input = vec![0.5f32; 8 * 8];
    input[3 * 8 + 3] = 5.0;
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    for kind in [PipeKind::Preview, PipeKind::Export] {
        let (ours, _, _) = run_ours(&module, &hp.json(), &image, &input, rin, kind, 1);
        let (theirs, _) = run_oracle(
            &facts,
            &hp.oracle(),
            &input,
            to_oracle_roi(rin),
            to_oracle_kind(kind),
        );
        assert_gate(&format!("synthetic markfixed {kind:?}"), &ours, &theirs);
    }
    // Preview paints the cross, export matches the unmarked run.
    let (preview, _, _) = run_ours(
        &module,
        &hp.json(),
        &image,
        &input,
        rin,
        PipeKind::Preview,
        1,
    );
    assert_eq!(preview[3 * 8 + 1], 5.0, "preview paints the cross");
    let plain = CaseParams::defaults();
    let (export_marked, _, _) = run_ours(
        &module,
        &hp.json(),
        &image,
        &input,
        rin,
        PipeKind::Export,
        1,
    );
    let (export_plain, _, _) = run_ours(
        &module,
        &plain.json(),
        &image,
        &input,
        rin,
        PipeKind::Export,
        1,
    );
    assert_eq!(export_marked, export_plain, "export drops markfixed");
}

#[test]
fn non_raw_passes_through() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let input: Vec<f32> = (0..64i16).map(|i| 0.25 + f32::from(i) * 0.01).collect();
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let plain = ImageInfo::new(8, 8, ColorSpace::Rgb);
    let (ours, our_state, _) =
        run_ours(&module, &Map::new(), &plain, &input, rin, PipeKind::Full, 1);
    assert_eq!(ours, input, "non-RAW passes through");
    assert_eq!(our_state.processed_maximum, [1.0; 4]);
    let oracle_facts = oracle::Facts {
        width: 8,
        height: 8,
        p_width: 8,
        p_height: 8,
        crop: [0, 0, 0, 0],
        black: [0, 0, 0, 0],
        white: 0,
        filters: 0,
        xtrans: [0; 36],
        flags: 0,
        buf_channels: 1,
        buf_datatype: oracle::BufferType::Float,
        id: 1,
    };
    let hp = CaseParams::defaults();
    let (theirs, their_state) = run_oracle(
        &oracle_facts,
        &hp.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic non-raw", &ours, &theirs);
    assert!(!their_state.enabled, "oracle disables the piece");
}

#[test]
fn threshold_and_strength_variants_match() {
    let module = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, false);
    // A warm pixel (0.25) on a dim field (0.1) at full strength: fixed at
    // the default threshold (mid 0.125 over the 0.1 neighbors), kept at 0.3.
    let mut dim = vec![0.1f32; 8 * 8];
    dim[3 * 8 + 3] = 0.25;
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let raised = CaseParams {
        strength: 1.0,
        threshold: 0.3,
        ..CaseParams::defaults()
    };
    let (ours, _, _) = run_ours(
        &module,
        &raised.json(),
        &image,
        &dim,
        rin,
        PipeKind::Full,
        1,
    );
    let (theirs, _) = run_oracle(
        &facts,
        &raised.oracle(),
        &dim,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic threshold raised", &ours, &theirs);
    assert_eq!(
        ours[3 * 8 + 3],
        0.25,
        "raised threshold keeps the warm pixel"
    );
    let full_strength = CaseParams {
        strength: 1.0,
        ..CaseParams::defaults()
    };
    let (ours, _, _) = run_ours(
        &module,
        &full_strength.json(),
        &image,
        &dim,
        rin,
        PipeKind::Full,
        1,
    );
    assert_eq!(ours[3 * 8 + 3], 0.1, "default threshold fixes it");
    // A hot pixel on a bright field: kept at default strength (mid 0.625
    // under the 1.0 neighbors), fixed at strength 0.5 (mid 1.25).
    let mut bright = vec![1.0f32; 8 * 8];
    bright[3 * 8 + 3] = 5.0;
    let strong = CaseParams {
        strength: 0.5,
        ..CaseParams::defaults()
    };
    let (ours, _, _) = run_ours(
        &module,
        &strong.json(),
        &image,
        &bright,
        rin,
        PipeKind::Full,
        1,
    );
    let (theirs, _) = run_oracle(
        &facts,
        &strong.oracle(),
        &bright,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
    );
    assert_gate("synthetic strength raised", &ours, &theirs);
    assert_eq!(
        ours[3 * 8 + 3],
        1.0,
        "raised strength fixes on bright field"
    );
}
