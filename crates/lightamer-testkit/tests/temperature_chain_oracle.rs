// SPDX-License-Identifier: GPL-3.0-or-later
//! The three-module RAW-head chain (`rawprepare` -> `temperature` ->
//! `hotpixels`, upstream order) against the verbatim upstream oracle: four
//! true ARW tiles times four temperature param sets run both sides and
//! compare pixels plus chain state.
//!
//! Lives here (not in either module crate) because both module crates sit
//! on layer L1 and same-layer edges are forbidden: testkit sits at L5 and
//! may depend on both. One decode for the binary.
//!
//! Temperature defaults reach the oracle explicitly (both sides run the
//! same multipliers); defaults-vs-oracle is proven in
//! `lightamer-iop-color`'s `defaults_match_oracle_find_coeffs`.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
// Test-side narrowing only (tile origins): values are small and exact.
#![allow(clippy::cast_possible_truncation)]

use lightamer_iop_traits::{
    CfaColor, CfaPattern, ImageInfo, PipeKind, PipeState, Plane, PlaneMut, Roi, SharedModule,
};
use lightamer_oracle as oracle;
use lightamer_raster::FrameExtent;
use lightamer_testkit::{IN_TOLERANCE_GATE, MEAN_ABS_GATE, RawSample, compare_planes, skip};
use serde_json::{Map, Value, json};

const SAMPLE: &str = "7RM5-LosslessCompressedLarge.ARW";
const TILE: u32 = 256;

/// hotpixels params (defaults both sides).
fn hotpixels_json() -> Map<String, Value> {
    json!({
        "strength": {"type": "float", "value": 0.25},
        "threshold": {"type": "float", "value": 0.05},
        "markfixed": {"type": "bool", "value": false},
        "permissive": {"type": "bool", "value": false},
    })
    .as_object()
    .cloned()
    .expect("object literal")
}

fn hotpixels_oracle() -> oracle::HotParams {
    oracle::HotParams {
        strength: 0.25,
        threshold: 0.05,
        markfixed: false,
        permissive: false,
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

/// Maps decoded facts to oracle temperature facts.
fn facts_for_oracle(image: &ImageInfo) -> oracle::TempFacts {
    let raw = image.raw.expect("mosaic facts");
    let black = [
        u16::try_from(raw.black[0]).expect("black fits u16"),
        u16::try_from(raw.black[1]).expect("black fits u16"),
        u16::try_from(raw.black[2]).expect("black fits u16"),
        u16::try_from(raw.black[3]).expect("black fits u16"),
    ];
    let cells = match raw.cfa {
        CfaPattern::Bayer(cells) => Some(cells),
        CfaPattern::XTrans(_) | CfaPattern::None => None,
    }
    .expect("chain test runs Bayer only");
    let (filters, xtrans) = (bayer_filters(cells), [0; 36]);
    oracle::TempFacts {
        base: oracle::Facts {
            width: i32::try_from(image.width).expect("width fits"),
            height: i32::try_from(image.height).expect("height fits"),
            p_width: raw.p_width,
            p_height: raw.p_height,
            crop: [raw.crop_x, raw.crop_y, 0, 0],
            black,
            white: raw.white,
            filters,
            xtrans,
            flags: oracle::DT_IMAGE_RAW,
            buf_channels: 1,
            // Stored u16 words (asserted at the test top), like B3-1c's
            // chain: rawprepare's commit legs read this.
            buf_datatype: oracle::BufferType::Uint16,
            id: 1,
        },
        wb: raw.wb,
        xyz_to_cam: raw.xyz_to_cam_d65,
    }
}

/// Runs our three-module chain over one tile: three commits in order, then
/// three processes with the state evolving. Returns the temperature-stage
/// output too (the intensity-one case asserts it equals rawprepare's).
#[allow(clippy::too_many_arguments)]
fn run_ours_chain(
    rawprepare: &SharedModule,
    temperature: &SharedModule,
    hotpixels: &SharedModule,
    rp_params: &Map<String, Value>,
    tp_params: &Map<String, Value>,
    hp_params: &Map<String, Value>,
    image: &ImageInfo,
    input: &[f32],
    rin: Roi,
    kind: PipeKind,
) -> (Vec<f32>, Vec<f32>, PipeState, Roi) {
    let mut commit_state = PipeState::from_image(image);
    let rp_data = rawprepare
        .commit(rp_params, image, &mut commit_state, kind)
        .expect("rawprepare commit");
    let mid0 = rawprepare.roi_out(&rp_data, rin);
    let tp_data = temperature
        .commit(tp_params, image, &mut commit_state, kind)
        .expect("temperature commit");
    let mid1 = temperature.roi_out(&tp_data, mid0);
    let hp_data = hotpixels
        .commit(hp_params, image, &mut commit_state, kind)
        .expect("hotpixels commit");
    let rout = hotpixels.roi_out(&hp_data, mid1);
    let tile = |roi: Roi| {
        let w = u32::try_from(roi.width).expect("tile width");
        let h = u32::try_from(roi.height).expect("tile height");
        (w, h, usize::try_from(roi.width).expect("tile stride"))
    };
    let (in_w, in_h, in_stride) = tile(rin);
    let (m0_w, m0_h, m0_stride) = tile(mid0);
    let (m1_w, m1_h, m1_stride) = tile(mid1);
    let (out_w, out_h, out_stride) = tile(rout);
    let mut middle0 = vec![0.0; m0_stride * usize::try_from(m0_h).expect("m0 rows")];
    let mut middle1 = vec![0.0; m1_stride * usize::try_from(m1_h).expect("m1 rows")];
    let mut output = vec![0.0; out_stride * usize::try_from(out_h).expect("out rows")];
    let mut state = PipeState::from_image(image);
    {
        let input_plane =
            Plane::from_slice_channels(input, in_w, in_h, in_stride, 1).expect("chain input");
        let mut middle_plane =
            PlaneMut::from_slice_channels(&mut middle0, m0_w, m0_h, m0_stride, 1)
                .expect("chain middle0");
        rawprepare
            .process(
                &rp_data,
                &input_plane,
                &mut middle_plane,
                rin,
                mid0,
                &mut state,
            )
            .expect("rawprepare process");
    }
    {
        let middle_plane =
            Plane::from_slice_channels(&middle0, m0_w, m0_h, m0_stride, 1).expect("chain m0");
        let mut out_plane = PlaneMut::from_slice_channels(&mut middle1, m1_w, m1_h, m1_stride, 1)
            .expect("chain middle1");
        temperature
            .process(
                &tp_data,
                &middle_plane,
                &mut out_plane,
                mid0,
                mid1,
                &mut state,
            )
            .expect("temperature process");
    }
    {
        let middle_plane =
            Plane::from_slice_channels(&middle1, m1_w, m1_h, m1_stride, 1).expect("chain m1");
        let mut output_plane =
            PlaneMut::from_slice_channels(&mut output, out_w, out_h, out_stride, 1)
                .expect("chain output");
        hotpixels
            .process(
                &hp_data,
                &middle_plane,
                &mut output_plane,
                mid1,
                rout,
                &mut state,
            )
            .expect("hotpixels process");
    }
    (middle1, output, state, rout)
}

/// Asserts the gate triple and prints the numbers for the report. All
/// three stages only compare, copy, take maxima, and multiply, so the
/// oracle and the transcription must agree bitwise.
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

/// Four tile regions: top-left, center, brightest, darkest 256px blocks.
fn tile_regions(sample: &RawSample) -> [(&'static str, u32, u32); 4] {
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
    [
        ("top-left", 0, 0),
        ("center", (width - TILE) / 2, (height - TILE) / 2),
        ("brightest", best.0 * TILE, best.1 * TILE),
        ("darkest", worst.0 * TILE, worst.1 * TILE),
    ]
}

/// One temperature param set the way both sides take it: ours as JSON,
/// the oracle as scalars. As-shot and D65 sets arrive green-normalized
/// from the find/bogus legs; the user/ones sets are literal. An infinite
/// fourth lane (the D65 leg) reads 1.0 on both sides: JSON cannot carry
/// inf, no Bayer sensel reads it, and the bogus test proves it bitwise.
fn temp_case(set: &str, coeffs: [f64; 4], preset: i32) -> (Map<String, Value>, oracle::TempParams) {
    let mut normed = if set == "user" || set == "ones" {
        coeffs
    } else {
        [
            coeffs[0] / coeffs[1],
            1.0,
            coeffs[2] / coeffs[1],
            coeffs[3] / coeffs[1],
        ]
    };
    if !normed[3].is_finite() {
        normed[3] = 1.0;
    }
    let json = json!({
        "red": {"type": "float", "value": normed[0]},
        "green": {"type": "float", "value": normed[1]},
        "blue": {"type": "float", "value": normed[2]},
        "various": {"type": "float", "value": normed[3]},
        "preset": {"type": "int", "value": preset},
    });
    let params = json.as_object().cloned().expect("object");
    let scalars = oracle::TempParams {
        red: normed[0] as f32,
        green: normed[1] as f32,
        blue: normed[2] as f32,
        various: normed[3] as f32,
        preset,
    };
    (params, scalars)
}

/// Runs rawprepare alone over one tile: the intensity-one reference (the
/// temperature stage must pass it through bitwise unchanged).
fn reference_rawprepare(
    rawprepare: &SharedModule,
    rp_params: &Map<String, Value>,
    image: &ImageInfo,
    tile: &[f32],
    rin: Roi,
    kind: PipeKind,
) -> Vec<f32> {
    let mut commit_state = PipeState::from_image(image);
    let rp_data = rawprepare
        .commit(rp_params, image, &mut commit_state, kind)
        .expect("rawprepare commit");
    let mid = rawprepare.roi_out(&rp_data, rin);
    let area = usize::try_from(mid.width).expect("w") * usize::try_from(mid.height).expect("h");
    let mut reference = vec![0.0; area];
    let in_plane = Plane::from_slice_channels(
        tile,
        u32::try_from(rin.width).expect("w"),
        u32::try_from(rin.height).expect("h"),
        usize::try_from(rin.width).expect("w"),
        1,
    )
    .expect("ref input");
    let mut ref_plane = PlaneMut::from_slice_channels(
        &mut reference,
        u32::try_from(mid.width).expect("w"),
        u32::try_from(mid.height).expect("h"),
        usize::try_from(mid.width).expect("w"),
        1,
    )
    .expect("ref output");
    let mut ref_state = PipeState::from_image(image);
    rawprepare
        .process(
            &rp_data,
            &in_plane,
            &mut ref_plane,
            rin,
            mid,
            &mut ref_state,
        )
        .expect("rawprepare process");
    reference
}

#[test]
fn chain_matches_oracle_on_four_tiles_times_four_param_sets() {
    use lightamer_iop_color::modules::temperature::{bogus_daylight_wb, default_coeffs};
    let Some(sample) = RawSample::open(SAMPLE) else {
        skip!(Corpus, "missing {SAMPLE}");
        return;
    };
    let Some(image) = sample.facts() else {
        skip!(Corpus, "no pipe facts for {SAMPLE}");
        return;
    };
    assert!(sample.stored_is_u16(), "ARW mosaic is u16 words");
    let facts = facts_for_oracle(&image);
    let rawprepare = lightamer_iop_raw::lookup_implemented("rawprepare").expect("implemented");
    let temperature = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    let hotpixels = lightamer_iop_raw::lookup_implemented("hotpixels").expect("implemented");
    let raw = image.raw.expect("raw facts");
    // Four temperature param sets: as-shot defaults, distinct user
    // multipliers, bogus-daylight D65, and intensity-one.
    let as_shot = default_coeffs(&raw);
    let bogus = bogus_daylight_wb(&raw).expect("sample carries a matrix");
    let sets: [(&str, [f64; 4], i32); 4] = [
        ("as-shot", as_shot, 0),
        ("user", [2.5, 1.0, 1.7, 0.9], 2),
        ("d65", bogus, 3),
        ("ones", [1.0, 1.0, 1.0, 1.0], 0),
    ];
    let rp_params = Map::new();
    let rp_oracle = oracle::rawprepare_defaults(&facts.base).expect("oracle defaults");
    let hp_params = hotpixels_json();
    let hp_oracle = hotpixels_oracle();
    let regions = tile_regions(&sample);
    for (set, coeffs, preset) in sets {
        let (tp_params, tp_oracle) = temp_case(set, coeffs, preset);
        for (label, x, y) in regions {
            let extent = FrameExtent::new(
                i32::try_from(x).expect("tile x"),
                i32::try_from(y).expect("tile y"),
                TILE,
                TILE,
            );
            let (frame, _) = sample.region(extent).expect("region converts");
            let tile = frame.as_slice().to_vec();
            let w = i32::try_from(TILE).expect("tile fits");
            let rin = Roi::new(extent.x, extent.y, w, w, 1.0);
            let kind = PipeKind::Full;
            let (temp_out, ours, our_state, our_rout) = run_ours_chain(
                &rawprepare,
                &temperature,
                &hotpixels,
                &rp_params,
                &tp_params,
                &hp_params,
                &image,
                &tile,
                rin,
                kind,
            );
            let (theirs, their_state, their_rout) = oracle::run_rawprepare_temperature_hotpixels(
                &facts,
                &rp_oracle,
                &tp_oracle,
                &hp_oracle,
                oracle::PipeType::Full,
                oracle::TileInput::F32(&tile),
                to_oracle_roi(rin),
            )
            .expect("oracle chain runs");
            let tag = format!("chain {set} {label}");
            assert_eq!(
                (our_rout.width, our_rout.height),
                (their_rout.width, their_rout.height),
                "{tag}: roi widths agree"
            );
            assert_gate(&tag, &ours, &theirs);
            assert!(their_state.enabled, "{tag}: oracle stays enabled");
            assert!(their_state.temp_enabled, "{tag}: oracle publishes wb");
            assert_eq!(
                our_state.temperature.coeffs, their_state.temp_coeffs,
                "{tag}: published coeffs"
            );
            assert_eq!(
                our_state.processed_maximum, their_state.processed_maximum,
                "{tag}: scaled maxima"
            );
            assert_eq!(
                our_state.temperature.late_correction, their_state.temp_late,
                "{tag}: late flag"
            );
            if set == "ones" {
                let reference =
                    reference_rawprepare(&rawprepare, &rp_params, &image, &tile, rin, kind);
                assert_eq!(temp_out, reference, "{tag}: temperature stage identity");
            }
        }
    }
}
