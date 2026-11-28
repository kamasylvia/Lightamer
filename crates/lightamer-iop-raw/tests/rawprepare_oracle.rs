// SPDX-License-Identifier: GPL-3.0-or-later
//! rawprepare against the verbatim upstream oracle: true ARW tiles and
//! synthetic tiles run both sides and compare pixels plus chain state.
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

/// Test-side params: crop sides, four black levels, white point.
struct CaseParams {
    crop: [i32; 4],
    black: [u16; 4],
    white: u16,
}

impl CaseParams {
    fn json(&self) -> Map<String, Value> {
        json!({
            "left": {"type": "int", "value": self.crop[0]},
            "top": {"type": "int", "value": self.crop[1]},
            "right": {"type": "int", "value": self.crop[2]},
            "bottom": {"type": "int", "value": self.crop[3]},
            "black_0": {"type": "int", "value": self.black[0]},
            "black_1": {"type": "int", "value": self.black[1]},
            "black_2": {"type": "int", "value": self.black[2]},
            "black_3": {"type": "int", "value": self.black[3]},
            "white": {"type": "int", "value": self.white},
            "flat_field": {"type": "bool", "value": false},
        })
        .as_object()
        .cloned()
        .expect("object literal")
    }

    fn oracle(&self) -> oracle::Params {
        oracle::Params {
            crop: self.crop,
            black: self.black,
            white: self.white,
            flat_field: false,
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
/// (`RawFacts` carries only the applied box's origin), so they read 0.
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
        flags: oracle::DT_IMAGE_RAW | (u32::from(raw.hdr) * oracle::DT_IMAGE_HDR),
        buf_channels: 1,
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
) -> (Vec<f32>, PipeState, Roi) {
    let mut commit_state = PipeState::from_image(image);
    let data = module
        .commit(params, image, &mut commit_state, PipeKind::Full)
        .expect("commit");
    let rout = module.roi_out(&data, rin);
    let area = usize::try_from(
        u64::from(u32::try_from(rout.width).expect("rout width"))
            * u64::from(u32::try_from(rout.height).expect("rout height")),
    )
    .expect("rout area");
    let mut output = vec![0.0; area];
    let input_plane = Plane::from_slice_channels(
        input,
        u32::try_from(rin.width).expect("rin width"),
        u32::try_from(rin.height).expect("rin height"),
        usize::try_from(rin.width).expect("rin stride"),
        1,
    )
    .expect("input plane");
    let mut output_plane = PlaneMut::from_slice_channels(
        &mut output,
        u32::try_from(rout.width).expect("rout width"),
        u32::try_from(rout.height).expect("rout height"),
        usize::try_from(rout.width).expect("rout stride"),
        1,
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

/// Runs the oracle over one tile; returns pixels, state, and roi.
fn run_oracle(
    facts: &oracle::Facts,
    params: &oracle::Params,
    input: &[f32],
    rin: oracle::Roi,
) -> (Vec<f32>, oracle::StateOut, oracle::Roi) {
    let rout = oracle::rawprepare_roi_out(facts, params, rin).expect("oracle roi");
    let (output, state) =
        oracle::run_rawprepare(facts, params, oracle::TileInput::F32(input), rin, rout)
            .expect("oracle run");
    (output, state, rout)
}

/// Asserts the gate pair and prints the numbers for the report.
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
        "{label}: share {} under gate",
        diff.in_tolerance
    );
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

fn rggb() -> CfaPattern {
    CfaPattern::Bayer([
        CfaColor::Red,
        CfaColor::Green,
        CfaColor::Green,
        CfaColor::Blue,
    ])
}

#[test]
fn lookup_and_tables_cover_rawprepare() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    assert_eq!(module.id(), "rawprepare");
    assert!(
        lightamer_iop_raw::MODULES
            .iter()
            .any(|desc| desc.id == "rawprepare"),
        "descriptor table holds rawprepare"
    );
    assert!(
        lightamer_iop_raw::IMPLEMENTED
            .iter()
            .any(|(id, _)| *id == "rawprepare"),
        "implemented table holds rawprepare"
    );
    assert_eq!(module.desc().params.fields.expect("fields").len(), 10);
}

#[test]
fn true_tiles_match_oracle_on_four_regions() {
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
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    // Defaults on both sides: empty map here, `reload_defaults` there.
    let ours_params = Map::new();
    let oracle_params = oracle::rawprepare_defaults(&facts).expect("oracle defaults");
    let (width, height) = sample.size();
    assert!(width > TILE && height > TILE, "sample holds 256px tiles");
    // Brightest/darkest full 256-blocks from the stored mosaic scan.
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
        let tile = i32::try_from(TILE).expect("tile fits");
        let rin = Roi::new(extent.x, extent.y, tile, tile, 1.0);
        let (ours, our_state, our_rout) =
            run_ours(&module, &ours_params, &image, frame.as_slice(), rin);
        let (theirs, their_state, their_rout) =
            run_oracle(&facts, &oracle_params, frame.as_slice(), to_oracle_roi(rin));
        assert_eq!(
            (our_rout.width, our_rout.height),
            (their_rout.width, their_rout.height),
            "{label}: roi widths agree"
        );
        assert_gate(&format!("true tile {label}"), &ours, &theirs);
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
fn black_point_yields_zero_white_yields_one() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, true);
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    for (label, level, want) in [("black", 512.0f32, 0.0f32), ("white", 15360.0, 1.0)] {
        let params = CaseParams {
            crop: [0, 0, 0, 0],
            black: [512, 512, 512, 512],
            white: 15360,
        };
        let input = vec![level; 64];
        let (ours, _, _) = run_ours(&module, &params.json(), &image, &input, rin);
        let (theirs, _, _) = run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
        assert_gate(&format!("synthetic {label}"), &ours, &theirs);
        assert!(
            ours.iter().all(|p| p.to_bits() == want.to_bits()),
            "{label} reads {want}"
        );
    }
}

#[test]
fn beyond_white_extrapolates_linearly() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, true);
    let params = CaseParams {
        crop: [0, 0, 0, 0],
        black: [512, 512, 512, 512],
        white: 15360,
    };
    let input = vec![30000.0; 64];
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let (ours, _, _) = run_ours(&module, &params.json(), &image, &input, rin);
    let (theirs, _, _) = run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
    assert_gate("synthetic beyond-white", &ours, &theirs);
    assert!(ours.iter().all(|p| *p > 1.0), "beyond white reads over 1.0");
}

#[test]
fn distinct_black_levels_follow_bayer_ids() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let image = synth_image(rggb(), [100, 200, 300, 400], 10000);
    let facts = facts_for_oracle(&image, true);
    let params = CaseParams {
        crop: [0, 0, 0, 0],
        black: [100, 200, 300, 400],
        white: 10000,
    };
    let input: Vec<f32> = (0..64i16).map(|i| 500.0 + f32::from(i) * 137.0).collect();
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let (ours, _, _) = run_ours(&module, &params.json(), &image, &input, rin);
    let (theirs, _, _) = run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
    assert_gate("synthetic distinct-blacks", &ours, &theirs);
    // The u16 leg computes the same formula: oracle words vs our floats.
    let words: Vec<u16> = (0..64)
        .map(|i| u16::try_from(500 + i * 137).expect("word fits"))
        .collect();
    let words_f32: Vec<f32> = words.iter().map(|w| f32::from(*w)).collect();
    let (ours_words, _, _) = run_ours(&module, &params.json(), &image, &words_f32, rin);
    let (theirs_u16, _) = oracle::run_rawprepare(
        &facts,
        &params.oracle(),
        oracle::TileInput::U16(&words),
        to_oracle_roi(rin),
        to_oracle_roi(rin),
    )
    .expect("oracle u16 leg");
    assert_gate("synthetic u16 leg", &ours_words, &theirs_u16);
}

#[test]
fn odd_and_even_crop_offsets_match() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let image = synth_image(rggb(), [512, 520, 508, 516], 15360);
    let facts = facts_for_oracle(&image, true);
    let input: Vec<f32> = (0..256i16).map(|i| 400.0 + f32::from(i) * 61.0).collect();
    for (left, top) in [(1, 0), (0, 1), (1, 1), (2, 3), (3, 2), (4, 4)] {
        let params = CaseParams {
            crop: [left, top, 0, 0],
            black: [512, 520, 508, 516],
            white: 15360,
        };
        let rin = Roi::new(0, 0, 16, 16, 1.0);
        let (ours, our_state, our_rout) = run_ours(&module, &params.json(), &image, &input, rin);
        let (theirs, their_state, their_rout) =
            run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
        let label = format!("synthetic crop {left}x{top}");
        assert_eq!(
            (our_rout.width, our_rout.height),
            (their_rout.width, their_rout.height),
            "{label}: roi agrees"
        );
        assert_gate(&label, &ours, &theirs);
        assert_eq!(
            our_state.cfa,
            pattern_from_oracle(their_state.filters, &their_state.xtrans),
            "{label}: CFA agrees"
        );
    }
}

#[test]
fn user_crop_shrinks_roi_both_sides() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, true);
    let params = CaseParams {
        crop: [2, 4, 6, 8],
        black: [512, 512, 512, 512],
        white: 15360,
    };
    let input: Vec<f32> = (0..1024i16).map(|i| 400.0 + f32::from(i) * 17.0).collect();
    let rin = Roi::new(0, 0, 32, 32, 1.0);
    let (ours, _, our_rout) = run_ours(&module, &params.json(), &image, &input, rin);
    let (theirs, _, their_rout) = run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
    assert_eq!((our_rout.width, our_rout.height), (24, 20));
    assert_eq!((their_rout.width, their_rout.height), (24, 20));
    assert_gate("synthetic user crop", &ours, &theirs);
    // roi_in restores both sides too.
    let data = module
        .commit(
            &params.json(),
            &image,
            &mut PipeState::from_image(&image),
            PipeKind::Full,
        )
        .expect("commit");
    let back = module.roi_in(&data, our_rout);
    let oracle_back =
        oracle::rawprepare_roi_in(&facts, &params.oracle(), their_rout).expect("oracle roi_in");
    assert_eq!((back.width, back.height), (32, 32));
    assert_eq!((oracle_back.width, oracle_back.height), (32, 32));
}

#[test]
fn xtrans_pattern_matches_oracle() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    // Deterministic 6x6 in R/G/B (validity as a true X-Trans table is
    // irrelevant: both sides shift the same table).
    let cells = std::array::from_fn(|k| match (k / 6 + 2 * (k % 6)) % 3 {
        0 => CfaColor::Red,
        1 => CfaColor::Green,
        _ => CfaColor::Blue,
    });
    let image = synth_image(CfaPattern::XTrans(cells), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, true);
    let params = CaseParams {
        crop: [1, 2, 0, 0],
        black: [512, 512, 512, 512],
        white: 15360,
    };
    let input: Vec<f32> = (0..256i16).map(|i| 400.0 + f32::from(i) * 61.0).collect();
    let rin = Roi::new(0, 0, 16, 16, 1.0);
    let (ours, our_state, _) = run_ours(&module, &params.json(), &image, &input, rin);
    let (theirs, their_state, _) = run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
    assert_gate("synthetic xtrans", &ours, &theirs);
    assert_eq!(their_state.filters, 9, "X-Trans keeps filter word 9");
    assert_eq!(
        our_state.cfa,
        pattern_from_oracle(their_state.filters, &their_state.xtrans),
        "X-Trans table agrees"
    );
}

#[test]
fn explicit_black_and_white_match_oracle() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image, true);
    let input: Vec<f32> = (0..64i16).map(|i| 300.0 + f32::from(i) * 211.0).collect();
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    for (label, black, white) in [
        ("modified black", [64, 128, 192, 256], 15360),
        ("modified white", [512, 512, 512, 512], 12000),
    ] {
        let params = CaseParams {
            crop: [0, 0, 0, 0],
            black,
            white,
        };
        let (ours, _, _) = run_ours(&module, &params.json(), &image, &input, rin);
        let (theirs, _, _) = run_oracle(&facts, &params.oracle(), &input, to_oracle_roi(rin));
        assert_gate(&format!("synthetic {label}"), &ours, &theirs);
    }
}

#[test]
fn disabled_inputs_pass_through() {
    let module = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let input: Vec<f32> = (0..64i16).map(|i| 0.25 + f32::from(i) * 0.01).collect();
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    // Non-RAW capture: no sensor facts, patternless, RGBA-ish float tile.
    let plain = ImageInfo::new(8, 8, ColorSpace::Rgb);
    let (ours, our_state, _) = run_ours(&module, &Map::new(), &plain, &input, rin);
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
    let oracle_params = oracle::Params {
        crop: [0, 0, 0, 0],
        black: [0, 0, 0, 0],
        white: 0,
        flat_field: false,
    };
    let (theirs, their_state) = oracle::run_rawprepare(
        &oracle_facts,
        &oracle_params,
        oracle::TileInput::F32(&input),
        to_oracle_roi(rin),
        to_oracle_roi(rin),
    )
    .expect("oracle run");
    assert!(!their_state.enabled, "oracle disables non-RAW");
    assert_eq!(theirs, input, "oracle passes non-RAW through");
    // HDR-normalized capture: float-bits unit white disables both sides.
    let mut raw = synth_image(rggb(), [512, 512, 512, 512], 15360)
        .raw
        .expect("raw");
    raw.hdr = true;
    raw.white = 0x3F80_0000;
    let hdr = ImageInfo::new(8, 8, ColorSpace::Raw).with_raw(raw);
    let (ours_hdr, _, _) = run_ours(&module, &Map::new(), &hdr, &input, rin);
    assert_eq!(ours_hdr, input, "normalized HDR passes through");
    let mut oracle_hdr = facts_for_oracle(&hdr, false);
    oracle_hdr.white = 0x3F80_0000;
    let (theirs_hdr, their_hdr_state) = oracle::run_rawprepare(
        &oracle_hdr,
        &oracle_params,
        oracle::TileInput::F32(&input),
        to_oracle_roi(rin),
        to_oracle_roi(rin),
    )
    .expect("oracle run");
    assert!(!their_hdr_state.enabled, "oracle disables normalized HDR");
    assert_eq!(theirs_hdr, input, "oracle passes normalized HDR through");
    // Disabled pieces leave geometry alone on both sides, even cropped.
    let crop_params = CaseParams {
        crop: [2, 4, 6, 8],
        black: [0, 0, 0, 0],
        white: 0,
    };
    let (ours_crop, _, our_rout) = run_ours(&module, &crop_params.json(), &plain, &input, rin);
    assert_eq!(ours_crop, input, "cropped disabled passes through");
    assert_eq!(
        (our_rout.width, our_rout.height),
        (8, 8),
        "disabled roi identity"
    );
    let (theirs_crop, their_crop_state) = oracle::run_rawprepare(
        &oracle_facts,
        &crop_params.oracle(),
        oracle::TileInput::F32(&input),
        to_oracle_roi(rin),
        to_oracle_roi(rin),
    )
    .expect("oracle run");
    assert!(!their_crop_state.enabled, "oracle disables cropped non-RAW");
    assert_eq!(theirs_crop, input, "oracle passes cropped non-RAW through");
    // Disabled u16 input errors loudly: the f32-only ABI cannot express a
    // u16 passthrough, and silent conversion would diverge from upstream.
    let words = vec![0u16; 64];
    let refused = oracle::run_rawprepare(
        &oracle_facts,
        &oracle_params,
        oracle::TileInput::U16(&words),
        to_oracle_roi(rin),
        to_oracle_roi(rin),
    );
    assert!(
        matches!(refused, Err(oracle::OracleError::Chain(2))),
        "disabled u16 refuses with code 2, got {refused:?}"
    );
}
