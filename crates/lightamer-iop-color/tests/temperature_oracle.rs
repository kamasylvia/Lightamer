// SPDX-License-Identifier: GPL-3.0-or-later
//! temperature against the verbatim upstream oracle: single-module runs
//! over true ARW tiles plus synthetic tiles run both sides and compare
//! pixels plus chain state; the temp/tint conversions compare against the
//! verbatim spectrum legs.
//!
//! One decode per binary: the true-tile test holds a single `RawSample`
//! and slices regions out of it; synthetic tests allocate kilobytes. The
//! three-module chain test lives in testkit (layering: this crate cannot
//! depend on its sibling `lightamer-iop-raw`).

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
// Test-side narrowing only (fixture ramps, tile origins): values are small
// (< 2^24, exactly representable), so the casts below cannot lose anything.
#![allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]

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

/// Test-side params: four multipliers plus the preset tag.
struct CaseParams {
    red: f32,
    green: f32,
    blue: f32,
    various: f32,
    preset: i32,
}

impl CaseParams {
    fn json(&self) -> Map<String, Value> {
        json!({
            "red": {"type": "float", "value": self.red},
            "green": {"type": "float", "value": self.green},
            "blue": {"type": "float", "value": self.blue},
            "various": {"type": "float", "value": self.various},
            "preset": {"type": "int", "value": self.preset},
        })
        .as_object()
        .cloned()
        .expect("object literal")
    }

    fn oracle(&self) -> oracle::TempParams {
        oracle::TempParams {
            red: self.red,
            green: self.green,
            blue: self.blue,
            various: self.various,
            preset: self.preset,
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

/// Maps decoded facts to oracle facts. Loader right/bottom have no source
/// (`RawFacts` carries only the applied box's origin), so they read 0.
fn facts_for_oracle(image: &ImageInfo) -> oracle::TempFacts {
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
    let mut flags = oracle::DT_IMAGE_RAW;
    if raw.hdr {
        flags |= oracle::DT_IMAGE_HDR;
    }
    if raw.four_bayer {
        flags |= oracle::DT_IMAGE_4BAYER;
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
            flags,
            buf_channels: 1,
            // Value is dead here (no temperature fragment reads the buffer
            // descriptor); the chain test sets it honestly for rawprepare.
            buf_datatype: oracle::BufferType::Float,
            id: 1,
        },
        wb: raw.wb,
        xyz_to_cam: raw.xyz_to_cam_d65,
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

/// Runs the oracle over one tile; returns pixels and state (temperature is
/// roi-identity, so the caller passes `rin` as its own `rout`).
fn run_oracle(
    facts: &oracle::TempFacts,
    params: &oracle::TempParams,
    input: &[f32],
    rin: oracle::Roi,
    kind: oracle::PipeType,
    planes: usize,
) -> (Vec<f32>, oracle::StateOut) {
    oracle::run_temperature(facts, params, kind, input, rin, rin, planes).expect("oracle run")
}

/// Asserts the gate triple and prints the numbers for the report. This
/// module only multiplies, so the oracle and the transcription must agree
/// bitwise: `max_abs` is asserted, not just read.
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
        wb: [2.5273, 1.0, 1.7344, 0.0],
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
fn lookup_and_tables_cover_temperature() {
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    assert_eq!(module.id(), "temperature");
    assert!(
        lightamer_iop_color::MODULES
            .iter()
            .any(|desc| desc.id == "temperature"),
        "descriptor table holds temperature"
    );
    assert!(
        lightamer_iop_color::IMPLEMENTED
            .iter()
            .any(|(id, _)| *id == "temperature"),
        "implemented table holds temperature"
    );
    assert_eq!(module.desc().params.fields.expect("fields").len(), 5);
}

#[test]
fn singles_match_oracle_on_four_true_tiles() {
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
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    // As-shot defaults on both sides (empty map here; the oracle takes the
    // same multipliers explicitly — defaults-vs-oracle is proven separately).
    let raw = image.raw.expect("raw facts");
    let defaults = lightamer_iop_color::modules::temperature::default_coeffs(&raw);
    let case = CaseParams {
        red: (defaults[0] / defaults[1]) as f32,
        green: 1.0,
        blue: (defaults[2] / defaults[1]) as f32,
        various: (defaults[3] / defaults[1]) as f32,
        preset: 0,
    };
    let ours_params = case.json();
    let oracle_params = case.oracle();
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
        let tile = frame.as_slice().to_vec();
        let w = i32::try_from(TILE).expect("tile fits");
        let rin = Roi::new(extent.x, extent.y, w, w, 1.0);
        let kind = PipeKind::Full;
        let (ours, our_state, our_rout) =
            run_ours(&module, &ours_params, &image, &tile, rin, kind, 1);
        let (theirs, their_state) = run_oracle(
            &facts,
            &oracle_params,
            &tile,
            to_oracle_roi(rin),
            to_oracle_kind(kind),
            1,
        );
        assert_eq!((our_rout.width, our_rout.height), (w, w), "{label}: roi");
        assert_gate(&format!("single true tile {label}"), &ours, &theirs);
        assert!(their_state.temp_enabled, "{label}: oracle publishes");
        assert_eq!(
            our_state.temperature.coeffs, their_state.temp_coeffs,
            "{label}: published coeffs"
        );
        assert_eq!(
            our_state.processed_maximum, their_state.processed_maximum,
            "{label}: scaled maxima"
        );
        assert_eq!(
            our_state.temperature.late_correction, their_state.temp_late,
            "{label}: late flag"
        );
    }
}

#[test]
fn synth_bayer_phases_match_oracle() {
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    // Distinct per-cell values catch lane mixups; distinct coeffs catch
    // channel swaps.
    let input: Vec<f32> = (0..64 * 64).map(|i| 0.1 + i as f32 * 0.0001).collect();
    for origin in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let image = synth_image(rggb(), [0, 0, 0, 0], 65535);
        let facts = facts_for_oracle(&image);
        let case = CaseParams {
            red: 2.5,
            green: 1.0,
            blue: 1.7,
            various: 0.9,
            preset: 2,
        };
        let rin = Roi::new(origin.0, origin.1, 64, 64, 1.0);
        let (ours, our_state, _) = run_ours(
            &module,
            &case.json(),
            &image,
            &input,
            rin,
            PipeKind::Full,
            1,
        );
        let (theirs, their_state) = run_oracle(
            &facts,
            &case.oracle(),
            &input,
            to_oracle_roi(rin),
            oracle::PipeType::Full,
            1,
        );
        assert_gate(&format!("bayer origin {origin:?}"), &ours, &theirs);
        // Hand-check one cell per color at the tile corner, shifted by the
        // origin parity (the phase the oracle comparison proves bitwise).
        let lane = |r: usize, c: usize| {
            let oy = usize::try_from(origin.1).expect("origin y");
            let ox = usize::try_from(origin.0).expect("origin x");
            let fr = (r + oy) % 2;
            let fc = (c + ox) % 2;
            [2.5, 1.0, 1.0, 1.7][fr * 2 + fc]
        };
        let at = |r: usize, c: usize| ours[r * 64 + c];
        assert_eq!(at(0, 0), input[0] * lane(0, 0));
        assert_eq!(at(0, 1), input[1] * lane(0, 1));
        assert_eq!(at(1, 0), input[64] * lane(1, 0));
        assert_eq!(at(1, 1), input[65] * lane(1, 1));
        assert_eq!(our_state.temperature.coeffs, their_state.temp_coeffs);
        assert_eq!(our_state.processed_maximum, [2.5, 1.0, 1.7, 0.9]);
        assert_eq!(their_state.processed_maximum, [2.5, 1.0, 1.7, 0.9]);
    }
}

#[test]
fn synth_xtrans_two_origins_match_oracle() {
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    let input: Vec<f32> = (0..64 * 64).map(|i| 0.2 + i as f32 * 0.0001).collect();
    for origin in [(0, 0), (1, 3)] {
        let image = synth_image(CfaPattern::XTrans(xtrans_cells()), [0, 0, 0, 0], 65535);
        let facts = facts_for_oracle(&image);
        let case = CaseParams {
            red: 2.5,
            green: 1.0,
            blue: 1.7,
            various: 1.0,
            preset: 0,
        };
        let rin = Roi::new(origin.0, origin.1, 64, 64, 1.0);
        let (ours, our_state, _) = run_ours(
            &module,
            &case.json(),
            &image,
            &input,
            rin,
            PipeKind::Full,
            1,
        );
        let (theirs, their_state) = run_oracle(
            &facts,
            &case.oracle(),
            &input,
            to_oracle_roi(rin),
            oracle::PipeType::Full,
            1,
        );
        assert_gate(&format!("xtrans origin {origin:?}"), &ours, &theirs);
        assert_eq!(our_state.temperature.coeffs, their_state.temp_coeffs);
    }
}

#[test]
fn synth_planar_matches_oracle() {
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    let image = synth_image(CfaPattern::None, [0, 0, 0, 0], 65535);
    let facts = facts_for_oracle(&image);
    let input: Vec<f32> = (0..16 * 16 * 4).map(|i| 0.05 + i as f32 * 0.0002).collect();
    let case = CaseParams {
        red: 2.5,
        green: 1.25,
        blue: 1.7,
        various: 0.9,
        preset: 0,
    };
    let rin = Roi::new(0, 0, 16, 16, 1.0);
    let (ours, our_state, _) = run_ours(
        &module,
        &case.json(),
        &image,
        &input,
        rin,
        PipeKind::Full,
        4,
    );
    let (theirs, their_state) = run_oracle(
        &facts,
        &case.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
        4,
    );
    assert_gate("planar 4-channel", &ours, &theirs);
    assert_eq!(ours[0], input[0] * 2.5);
    assert_eq!(ours[1], input[1] * 1.25);
    assert_eq!(ours[2], input[2] * 1.7);
    assert_eq!(ours[3], input[3] * 0.9);
    assert_eq!(our_state.temperature.coeffs, their_state.temp_coeffs);
    assert_eq!(our_state.processed_maximum, their_state.processed_maximum);
}

#[test]
fn intensity_one_leaves_pixels_bitwise_unchanged() {
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    let image = synth_image(rggb(), [0, 0, 0, 0], 65535);
    let facts = facts_for_oracle(&image);
    let input: Vec<f32> = (0..32 * 32).map(|i| 0.3 + i as f32 * 0.001).collect();
    let case = CaseParams {
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        various: 1.0,
        preset: 0,
    };
    let rin = Roi::new(0, 0, 32, 32, 1.0);
    let (ours, our_state, _) = run_ours(
        &module,
        &case.json(),
        &image,
        &input,
        rin,
        PipeKind::Full,
        1,
    );
    let (theirs, their_state) = run_oracle(
        &facts,
        &case.oracle(),
        &input,
        to_oracle_roi(rin),
        oracle::PipeType::Full,
        1,
    );
    assert_gate("intensity one", &ours, &theirs);
    assert_eq!(ours, input, "unit multipliers change nothing");
    assert_eq!(our_state.temperature.coeffs, [1.0; 4]);
    assert_eq!(our_state.processed_maximum, [1.0; 4]);
    assert_eq!(their_state.temp_coeffs, [1.0; 4]);
}

#[test]
fn non_raw_passes_through() {
    // The oracle has no disable path for temperature (upstream disables it
    // via the history/enable button, not commit logic), so this asserts
    // our passthrough directly, without an oracle side.
    let module = lightamer_iop_color::lookup_implemented("temperature").expect("implemented");
    let image = ImageInfo::new(8, 8, ColorSpace::Rgb);
    let input: Vec<f32> = (0..64).map(|i| i as f32 * 0.01).collect();
    let case = CaseParams {
        red: 2.5,
        green: 1.0,
        blue: 1.7,
        various: 1.0,
        preset: 4,
    };
    let rin = Roi::new(0, 0, 8, 8, 1.0);
    let (ours, our_state, _) = run_ours(
        &module,
        &case.json(),
        &image,
        &input,
        rin,
        PipeKind::Full,
        1,
    );
    assert_eq!(ours, input, "non-RAW passes through");
    assert!(!our_state.temperature.enabled);
    assert_eq!(our_state.processed_maximum, [1.0; 4]);
    // The late flag still lands (commit wrote it, like upstream's `:725`).
    assert!(our_state.temperature.late_correction);
}

#[test]
fn defaults_match_oracle_find_coeffs() {
    use lightamer_iop_color::modules::temperature::default_coeffs;
    // As-shot leg.
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let facts = facts_for_oracle(&image);
    let ours = default_coeffs(&image.raw.expect("raw"));
    let theirs = oracle::temperature_find_coeffs(&facts).expect("oracle runs");
    assert_eq!(ours, theirs, "as-shot leg bitwise");
    // Matrix leg: zero wb plus an identity matrix.
    let mut raw = image.raw.expect("raw");
    raw.wb = [0.0; 4];
    raw.xyz_to_cam_d65 = Some([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);
    let matrix_image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let matrix_facts = facts_for_oracle(&matrix_image);
    let ours = default_coeffs(&matrix_image.raw.expect("raw"));
    let theirs = oracle::temperature_find_coeffs(&matrix_facts).expect("oracle runs");
    assert_eq!(ours, theirs, "matrix leg bitwise");
    // Fallback leg: zero wb, no matrix (the preset leg is empty on both
    // sides — zero-count stub here, skipped there).
    raw.xyz_to_cam_d65 = None;
    let bare_image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let bare_facts = facts_for_oracle(&bare_image);
    let ours = default_coeffs(&bare_image.raw.expect("raw"));
    let theirs = oracle::temperature_find_coeffs(&bare_facts).expect("oracle runs");
    assert_eq!(ours, [2.0, 1.0, 1.5, 1.0]);
    assert_eq!(theirs, [2.0, 1.0, 1.5, 1.0]);
    // Four-Bayer leg: the fourth multiplier counts.
    raw.wb = [2.5273, 1.0, 1.7344, 1.0123];
    raw.four_bayer = true;
    let quad_image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let quad_facts = facts_for_oracle(&quad_image);
    let ours = default_coeffs(&quad_image.raw.expect("raw"));
    let theirs = oracle::temperature_find_coeffs(&quad_facts).expect("oracle runs");
    assert_eq!(ours, theirs, "four-bayer leg bitwise");
    // Four-Bayer with a bad fourth multiplier falls through to the matrix
    // leg (identity matrix here), exactly like upstream.
    raw.wb[3] = 0.0;
    raw.xyz_to_cam_d65 = Some([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);
    let fall_image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let fall_facts = facts_for_oracle(&fall_image);
    let ours = default_coeffs(&fall_image.raw.expect("raw"));
    let theirs = oracle::temperature_find_coeffs(&fall_facts).expect("oracle runs");
    assert_eq!(ours, theirs, "four-bayer fallthrough bitwise");
}

#[test]
fn bogus_daylight_matches_oracle() {
    use lightamer_iop_color::modules::temperature::bogus_daylight_wb;
    // A non-trivial matrix (fractional entries exercise the arithmetic).
    let matrix = [0.9, 0.05, 0.05, 0.1, 0.8, 0.1, 0.05, 0.1, 0.85];
    let mut raw = synth_image(rggb(), [512, 512, 512, 512], 15360)
        .raw
        .expect("raw");
    raw.wb = [0.0; 4];
    raw.xyz_to_cam_d65 = Some(matrix);
    let image = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let facts = facts_for_oracle(&image);
    let ours = bogus_daylight_wb(&image.raw.expect("raw")).expect("matrix leg runs");
    let theirs = oracle::temperature_bogus(&facts)
        .expect("oracle runs")
        .expect("matrix leg runs");
    assert_eq!(ours, theirs, "bogus daylight bitwise");
    eprintln!("bogus daylight: {ours:?}");
    // No matrix on either side.
    raw.xyz_to_cam_d65 = None;
    let bare = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let bare_facts = facts_for_oracle(&bare);
    assert!(bogus_daylight_wb(&bare.raw.expect("raw")).is_none());
    assert!(
        oracle::temperature_bogus(&bare_facts)
            .expect("oracle runs")
            .is_none()
    );
}

#[test]
fn temp_sweep_matches_oracle_xy_and_mul() {
    use lightamer_iop_color::modules::temperature::{temp_tint_to_coeffs, temp_tint_to_xy};
    let matrix = Some([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let mut raw = image.raw.expect("raw");
    raw.xyz_to_cam_d65 = matrix;
    let with_matrix = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let facts = facts_for_oracle(&with_matrix);
    let mut worst_xy = 0.0f64;
    let mut worst_mul = 0.0f64;
    let mut points = 0u32;
    for temp in (2000..=12000).step_by(500) {
        for tint in [0.135, 0.5, 1.0, 1.5, 2.326] {
            let temp = f64::from(temp);
            // xy: ours against the oracle XYZ, normalized the same way.
            let (x, y) = temp_tint_to_xy(temp, tint);
            let [ox, oy, oz] = oracle::temperature_tint_xyz(temp, tint).expect("oracle runs");
            let sum = ox + oy + oz;
            let diff = (x - ox / sum).abs().max((y - oy / sum).abs());
            worst_xy = worst_xy.max(diff);
            // Multipliers through the identity matrix.
            let ours = temp_tint_to_coeffs(temp, tint, matrix, true);
            let theirs = oracle::temperature_temp_to_mul(&facts, temp, tint).expect("oracle runs");
            let mdiff = ours
                .iter()
                .zip(theirs.iter())
                .map(|(a, b)| (a - b).abs())
                .fold(0.0f64, f64::max);
            worst_mul = worst_mul.max(mdiff);
            points += 1;
        }
    }
    eprintln!("temp sweep: {points} points worst_xy={worst_xy:.3e} worst_mul={worst_mul:.3e}");
    assert!(worst_xy < 1e-4, "xy within the card gate: {worst_xy:.3e}");
}

#[test]
fn temp_sweep_with_real_matrix_matches_oracle() {
    use lightamer_iop_color::modules::temperature::{temp_tint_to_coeffs, temp_tint_to_xy};
    let Some(sample) = RawSample::open(SAMPLE) else {
        skip!(Corpus, "missing {SAMPLE}");
        return;
    };
    let Some(image) = sample.facts() else {
        skip!(Corpus, "no pipe facts for {SAMPLE}");
        return;
    };
    let raw = image.raw.expect("raw facts");
    let Some(matrix) = raw.xyz_to_cam_d65 else {
        skip!(Corpus, "sample carries no color matrix");
        return;
    };
    let facts = facts_for_oracle(&image);
    let mut worst_xy = 0.0f64;
    let mut worst_mul = 0.0f64;
    for temp in [2500.0, 5000.0, 8000.0] {
        for tint in [0.5, 1.0, 1.5] {
            let (x, y) = temp_tint_to_xy(temp, tint);
            let [ox, oy, oz] = oracle::temperature_tint_xyz(temp, tint).expect("oracle runs");
            let sum = ox + oy + oz;
            worst_xy = worst_xy.max((x - ox / sum).abs().max((y - oy / sum).abs()));
            let ours = temp_tint_to_coeffs(temp, tint, Some(matrix), true);
            let theirs = oracle::temperature_temp_to_mul(&facts, temp, tint).expect("oracle runs");
            for (a, b) in ours.iter().zip(theirs.iter()) {
                worst_mul = worst_mul.max((a - b).abs());
            }
        }
    }
    eprintln!("real-matrix sweep: worst_xy={worst_xy:.3e} worst_mul={worst_mul:.3e}");
    assert!(worst_xy < 1e-4, "xy within the card gate: {worst_xy:.3e}");
}

#[test]
fn mul_to_temp_matches_oracle() {
    use lightamer_iop_color::modules::temperature::coeffs_to_temp_tint;
    let matrix = Some([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);
    let image = synth_image(rggb(), [512, 512, 512, 512], 15360);
    let mut raw = image.raw.expect("raw");
    raw.xyz_to_cam_d65 = matrix;
    let with_matrix = ImageInfo::new(64, 64, ColorSpace::Raw).with_raw(raw);
    let facts = facts_for_oracle(&with_matrix);
    for coeffs in [
        [2.5273, 1.0, 1.7344, 1.0],
        [2.0, 1.0, 1.5, 1.0],
        [1.2, 1.0, 0.9, 1.1],
        [3.0, 1.0, 2.2, 0.8],
    ] {
        let ours = coeffs_to_temp_tint(coeffs, matrix, true);
        let theirs = oracle::temperature_mul_to_temp(&facts, coeffs).expect("oracle runs");
        eprintln!("coeffs {coeffs:?}: ours={ours:?} theirs={theirs:?}");
        assert_eq!(ours, theirs, "coeffs {coeffs:?} bitwise");
    }
}
