#!/bin/bash
# Lightamer golden reference regeneration (Phase 3, Plan 03-01-T2).
#
# Four-section structure (RESEARCH §6.3):
#   ① gen_fixtures   — synthetic scene-linear EXRs + pinned XMP cases
#   ② roundtrip      — each fixture through dt-cli → Rec2020 canonical form
#                      (values converted + chromaticities marked, §6.1)
#   ③ cases loop     — dt-cli per (fixture × case) golden output
#   ④ manifest       — dt commit + per-case params blob hash + output sha256
#
# Determinism contract (ALL four steps must be hermetic):
#   - `--configdir` pins the EXR writer conf (float32 + NO_COMPRESSION) —
#     otherwise dt falls back to PIZ and byte hashes drift per machine.
#   - `--apply-custom-presets 0` everywhere (RESEARCH Risk #10: keeps the
#     local user preset library out of the golden chain).
#   - Fresh library DB per run; everything transient lives under `.conf/`.
#
# Usage: bash input/golden/regenerate.sh
set -euo pipefail

GOLDEN="$(cd "$(dirname "$0")" && pwd)"
DT="${DT:-/Volumes/UNITEK/Documents/Development/darktable/build/bin/darktable-cli}"
CONF="$GOLDEN/.conf"
RAW="$GOLDEN/.conf/raw"
OUT="$GOLDEN/output"
FIX="$GOLDEN/fixtures"
PYTHON="${PYTHON:-python3}"
COLISA_REF_FIXTURES="ramp_8ev gray_staircase flat_0ev flat_-4ev saturated deep_shadow"

echo "== ① gen_fixtures =="
rm -rf "$CONF"
mkdir -p "$CONF" "$RAW" "$OUT"
# Hermetic writer conf: float32 (bpp encodes pixel_type << 4 → 32 = FLOAT)
# + no compression. Without these, dt defaults to PIZ-compressed half-prec
# output and the manifest hashes stop being reproducible. The work profile
# is PINNED to linear Rec2020 (Plan 03-03: the Lab-domain modules convert
# through the pipe's work RGB — the probe evidence assumes the Lightamer
# working space).
printf 'plugins/imageio/format/exr/bpp=32\nplugins/imageio/format/exr/compression=0\nplugins/darkroom/workicc=LIN_REC2020\n' \
    > "$CONF/darktablerc"
"$PYTHON" "$FIX/gen_fixtures.py" raw "$RAW"
"$PYTHON" "$FIX/gen_fixtures.py" cases "$GOLDEN"

echo "== ② roundtrip → Rec2020 canonical fixtures =="
FIXTURES="ramp_8ev flat_0ev flat_-4ev flat_-8ev saturated deep_shadow gray_staircase stair_1d"
for f in $FIXTURES; do
    "$DT" "$RAW/$f.exr" "$FIX/$f" --out-ext exr --icc-type LIN_REC2020 \
        --apply-custom-presets 0 --library "$CONF/golden.db" \
        --core --configdir "$CONF" 2>&1 | grep export_job || true
done

echo "== ③ golden outputs (fixture × case) =="
# stale outputs from previous runs must not survive (the temperature case
# outputs switched from dt-cli EXR to synthesized references in 03-02)
rm -rf "$OUT"
mkdir -p "$OUT"
# Exposure cases: dt-cli EXR outputs are exact (verified by plan 03-01) —
# these ARE the track-A references for exposure.
for xmp in "$GOLDEN"/cases/exposure_*.xmp; do
    case_name="$(basename "$xmp" .xmp)"
    for f in $FIXTURES; do
        "$DT" "$FIX/$f.exr" "$xmp" "$OUT/${case_name}__${f}" \
            --out-ext exr --icc-type LIN_REC2020 \
            --apply-custom-presets 0 --library "$CONF/golden.db" \
            --core --configdir "$CONF" 2>&1 | grep export_job || true
    done
done

echo "== ③b temperature dt-cli semantic probes (PFM) =="
# HOST FINDING (plan 03-02, see manifest): this dt build emits spatially
# corrupted float output for SPATIALLY-VARYING images (EXR/PFM/TIFF all
# affected; uniform images exact). The temperature case loop therefore
# exports dt-cli PFM PROBES (kept under output/pfm_probe/ — trustworthy on
# the UNIFORM flats, where dt's per-pixel semantic in×gains is verified),
# while the track-A per-pixel REFERENCES for temperature are SYNTHESIZED
# from the shared semantic in step ③c.
PROBE="$OUT/pfm_probe"
rm -rf "$PROBE"
mkdir -p "$PROBE"
# temperature (03-02) + colisa (03-03-T2): same probe route — the PFM
# writer is exact on UNIFORM images, so the flats pin dt's per-pixel
# semantic while the synthesized references carry the per-pixel track-A
# role (host finding: spatially-varying float export is corrupt).
# sigmoid (03-04-T4): the rgb_ratio flat probes MATCH the reference math
# exactly (three flats, ≤1e-5) — the dt-side semantic evidence for the
# shared derivation+curve. The per_channel leg SIGSEGVs dt-cli in this
# build (3/3 runs, manifest note) — its files simply never appear.
# shadhi (03-04-T2): the probes pin the BROKEN route (the pipe runs the
# Lab module on unconverted domain — manifest finding), NOT the module
# semantic; kept as the mechanism's evidence record.
for xmp in "$GOLDEN"/cases/temperature_*.xmp "$GOLDEN"/cases/colisa_*.xmp \
           "$GOLDEN"/cases/sigmoid_*.xmp "$GOLDEN"/cases/shadhi_*.xmp; do
    case_name="$(basename "$xmp" .xmp)"
    for f in $FIXTURES; do
        "$DT" "$FIX/$f.exr" "$xmp" "$PROBE/${case_name}__${f}" \
            --out-ext pfm --icc-type LIN_REC2020 \
            --apply-custom-presets 0 --library "$CONF/golden.db" \
            --core --configdir "$CONF" 2>&1 | grep export_job || true
    done
done

echo "== ③c temperature reference synthesis (shared semantic) =="
"$PYTHON" "$FIX/gen_fixtures.py" refs "$FIX"


echo "== ④ manifest =="
{
    echo "# Lightamer golden manifest (generated by regenerate.sh)"
    echo
    echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "- darktable-cli: \`$DT\`"
    echo "- dt commit: \`$("$DT" --version 2>/dev/null | head -1)\`"
    echo "- Writer conf: float32 uncompressed (\`plugins/imageio/format/exr/bpp=32\`, \`.../compression=0\`)"
    echo "- ICC: \`--icc-type LIN_REC2020\`; \`--apply-custom-presets 0\` everywhere"
    echo
    echo "## dt-cli ↔ Lightamer exposure field mapping (RESEARCH Risk #5)"
    echo
    echo "dt blob \`<iffffii\` (little-endian pack of dt_iop_exposure_params_t v7,"
    echo "hex-ASCII in XMP) ↔ Lightamer \`ExposureModule.Params\` (JSON, ParamsCoding):"
    echo
    echo "| dt field (offset) | Lightamer field | note |"
    echo "|---|---|---|"
    echo "| mode (0, int) | \`mode\` | Lightamer: deflicker falls back to manual (divergence #2) |"
    echo "| black (4, f) | \`black\` | both clamp to [-1,1] |"
    echo "| exposure (8, f) | \`exposure\` | EV; white = exp2(−EV) |"
    echo "| deflicker_percentile (12, f) | \`deflickerPercentile\` | unused (divergence #2) |"
    echo "| deflicker_target_level (16, f) | \`deflickerTargetLevel\` | unused (divergence #2) |"
    echo "| compensate_exposure_bias (20, int) | \`compensateExposureBias\` | dt: bias source = RAW EXIF (0 on EXR fixtures) — reserved in Lightamer (divergence #4) |"
    echo "| compensate_hilite_pres (24, int) | \`compensateHilitePres\` | no pixel effect without highlight preservation |"
    echo
    echo "Scale math (both sides): \`white = exp2(−exposure)\`; \`out = (in − black) × 1/(white − black)\`."
    echo
    echo "## dt-cli ↔ Lightamer temperature field mapping (Plan 03-02-T2)"
    echo
    echo "dt blob \`<ffffi\` (little-endian pack of dt_iop_temperature_params_t"
    echo "v4, hex-ASCII in XMP) ↔ Lightamer \`TemperatureModule.Params\` (JSON):"
    echo
    echo "| dt field (offset) | Lightamer field | note |"
    echo "|---|---|---|"
    echo "| red (0, f) | \`red\` | gain ∈ [0,8] |"
    echo "| green (4, f) | \`green\` | gain ∈ [0,8] |"
    echo "| blue (8, f) | \`blue\` | gain ∈ [0,8] |"
    echo "| various (12, f) | — (not ported) | CYGM 4th channel; Lightamer pipe is RGB (module divergence #3); pinned 1.0 |"
    echo "| preset (16, int) | \`preset\` | dt DT_IOP_TEMP_* raw values; UI-state bit only |"
    echo
    echo "Pixel math (both sides): \`out.rgb = in.rgb × (red, green, blue)\`, alpha untouched"
    echo "(\`whitebalance_4f\` ↔ \`temperature_apply\`). The Kelvin→gains MODEL diverges by"
    echo "design (dt: sensor-domain XYZ_to_CAM; Lightamer: Rec2020-native post-CIRAW"
    echo "correction layer, RESEARCH §5) — the Kelvin math is locked by"
    echo "CPUDerivationTests against .work/03-02/wb_reference.c instead of golden."
    echo
    echo "## Cases × params blob hash + golden output sha256"
    echo
    echo "### exposure cases (dt-cli EXR = track-A reference)"
    echo
    echo "| case | params blob (hex) | sha256(blob) | outputs (sha256) |"
    echo "|---|---|---|---|"
    for xmp in "$GOLDEN"/cases/exposure_*.xmp; do
        case_name="$(basename "$xmp" .xmp)"
        blob="$(grep -o '<darktable:params>[^<]*</darktable:params>' "$xmp" | head -1 | sed -E 's|</?darktable:params>||g')"
        blob_hash="$(printf '%s' "$blob" | shasum -a 256 | cut -d' ' -f1)"
        outs=""
        for f in $FIXTURES; do
            o="$OUT/${case_name}__${f}.exr"
            if [ -f "$o" ]; then
                outs="$outs $f:$(shasum -a 256 "$o" | cut -d' ' -f1 | cut -c1-16)"
            fi
        done
        echo "| $case_name | \`$blob\` | \`$blob_hash\` |$outs |"
    done
    echo
    echo "### temperature cases (Plan 03-02)"
    echo
    echo "dt-cli EXR outputs for temperature are NOT reference-grade in this build"
    echo "environment (host finding: spatial corruption for varying content — see"
    echo "manifest notes). Track-A references = synthesized \`<case>__<fixture>.exr\`"
    echo "(canonical fixture × gains, float64); dt-cli PFM probes kept under"
    echo "output/pfm_probe/ (trustworthy on the uniform flats)."
    echo
    echo "| case | params blob (hex) | sha256(blob) | reference sha256 (synthesized) |"
    echo "|---|---|---|---|"
    for xmp in "$GOLDEN"/cases/temperature_*.xmp; do
        case_name="$(basename "$xmp" .xmp)"
        blob="$(grep -o '<darktable:params>[^<]*</darktable:params>' "$xmp" | head -1 | sed -E 's|</?darktable:params>||g')"
        blob_hash="$(printf '%s' "$blob" | shasum -a 256 | cut -d' ' -f1)"
        outs=""
        for f in ramp_8ev flat_0ev flat_-4ev flat_-8ev gray_staircase; do
            o="$OUT/${case_name}__${f}.exr"
            if [ -f "$o" ]; then
                outs="$outs $f:$(shasum -a 256 "$o" | cut -d' ' -f1 | cut -c1-16)"
            fi
        done
        echo "| $case_name | \`$blob\` | \`$blob_hash\` |$outs |"
    done
    echo
    echo "### colisa cases (Plan 03-03-T2, synthesized references + PFM probes)"
    echo
    echo "| case | params blob (hex) | sha256(blob) | reference sha256 (synthesized) |"
    echo "|---|---|---|---|"
    for xmp in "$GOLDEN"/cases/colisa_*.xmp; do
        case_name="$(basename "$xmp" .xmp)"
        blob="$(grep -o '<darktable:params>[^<]*</darktable:params>' "$xmp" | head -1 | sed -E 's|</?darktable:params>||g')"
        blob_hash="$(printf '%s' "$blob" | shasum -a 256 | cut -d' ' -f1)"
        outs=""
        for f in $COLISA_REF_FIXTURES; do
            o="$OUT/${case_name}__${f}.exr"
            if [ -f "$o" ]; then
                outs="$outs $f:$(shasum -a 256 "$o" | cut -d' ' -f1 | cut -c1-16)"
            fi
        done
        echo "| $case_name | \`$blob\` | \`$blob_hash\` |$outs |"
    done
    echo
    echo "### levels cases (Plan 03-03-T4/T5, synthesized references)"
    echo
    echo "dt blob \`<iffffff\` (28 bytes, dt_iop_levels_params_t v2, hex-ASCII) ↔"
    echo "Lightamer \`LevelsModule.Params\` (JSON):"
    echo
    echo "| dt field (offset) | Lightamer field | note |"
    echo "|---|---|---|"
    echo "| mode (0, i) | \`mode\` | 0 manual / 1 automatic |"
    echo "| black (4, f) | \`black\` | manual: unused; automatic: PERCENTILE (levels.c:514-516) |"
    echo "| gray (8, f) | \`gray\` | same dual role |"
    echo "| white (12, f) | \`white\` | same dual role |"
    echo "| levels[3] (16..28, f) | \`levels\` | manual points, normalized [0,1] (init: 0/0.5/1) |"
    echo
    echo "Pixel math (both sides): Rec2020→Lab, L_in ≤ black → 0, percentage ="
    echo "(L_in−l0)/(l2−l0), lut[nearest] below 1.0, 100·percentage^inv_gamma above,"
    echo "chroma a,b × L_out/max(L_in, 0.01) (CPU form), Lab→Rec2020."
    echo "Track-A references synthesized (L017 route)."
    echo
    echo "### levels automatic reference note (Plan 03-03-T5)"
    echo
    echo "The levels_auto case (\`mode=1\`, percentiles 2/50/98) pins dt-side"
    echo "ADOPTION only (DB op_params hex: 01000000 00000040 00004842 0000c442"
    echo "+ 'params v. 2: version ok params ok'). The Lightamer-side reference"
    echo "for the automatic chain is IN-TEST and SELF-CONSISTENT"
    echo "(testLevelsAutomaticSelfConsistentParity): the GPU histogram →"
    echo "percentile levels → LUT → apply, compared against a float64"
    echo "evaluation of the SAME levels. A pre-generated per-pixel EXR"
    echo "reference would bake in the float64 histogram binning, which"
    echo "disagrees with the GPU's float32 bin assignment at ~1e-4 of pixels;"
    echo "a single bin shift at a percentile crossing changes the GLOBAL LUT"
    echo "(a shift the <1e-4 pixel gate cannot absorb). Gates instead:"
    echo "histogram vs analytic (drift ≤8 counts, levels ±1 bin), parity"
    echo "<1e-4 relative+absolute, ΔE p99 < 1.0. 256 bins per the plan (dt:"
    echo "16384 — divergence #1); histogram recomputed per pipe run."
    echo
    echo "Stale-plugin note: the same rebuild that fixed libcolisa (03-03-T2)"
    echo "applied to libtonecurve/liblevels; librgblevels remains stale in the"
    echo "dt build (dlopen failure at startup — non-fatal noise, module unused"
    echo "by the golden chain)."
    echo
    echo "### shadhi cases (Plan 03-04-T2, synthesized references; gaussian leg pinned)"
    echo
    echo "dt blob \`<i8fIfi\` (48 bytes, dt_iop_shadhi_params_t v5, hex-ASCII) ↔"
    echo "Lightamer \`ShadhiModule.Params\` (JSON):"
    echo
    echo "| dt field (offset) | Lightamer field | note |"
    echo "|---|---|---|"
    echo "| order (0, i) | — (fixed .zero) | dt_gaussian_order_t; Lightamer v1 always ZERO |"
    echo "| radius (4, f) | \`radius\` | both clamp ≥ 0.1; sigma = radius × roi.scale / iscale |"
    echo "| shadows (8, f) | \`shadows\` | commit rescale ×2 (clamped ±1) |"
    echo "| whitepoint (12, f) | \`whitepoint\` | factor = max(1 − wp/100, 0.01) |"
    echo "| highlights (16, f) | \`highlights\` | commit rescale ×2; dt default −50 |"
    echo "| reserved2 (20, f) | — | unused |"
    echo "| compress (24, f) | \`compress\` | /100, clamp ≤ 0.99 |"
    echo "| shadows_ccorrect (28, f) | \`shadowsCCorrect\` | sign-folded vs sign(shadows) |"
    echo "| highlights_ccorrect (32, f) | \`highlightsCCorrect\` | sign-folded vs sign(−highlights) |"
    echo "| flags (36, I) | \`unbound\` | 127 = UNBOUND_DEFAULT ↔ true; 63 ↔ false |"
    echo "| low_approximation (40, f) | \`lowApproximation\` | dt default 1e-6 |"
    echo "| shadhi_algo (44, i) | \`algo\` | 0 = GAUSSIAN (pinned); dt default 1 = bilateral — Phase 5 leg |"
    echo
    echo "Pixel math (both sides): Rec2020→Lab, 4-channel Deriche-IIR gaussian"
    echo "(gaussian.c/gaussian.cl recursion — NOT a truncated FIR; plan-source"
    echo "erratum recorded), invert+desaturate the blur, whitepoint, highlights"
    echo "then shadows overlay loops (strength² chunking, chroma factor),"
    echo "Lab→Rec2020. Track-A references SYNTHESIZED (L017 route)."
    echo
    echo "PROBE ROUTE BROKEN for shadhi (extends the 03-03 Lab-chain finding"
    echo "with a concrete mechanism): libcolorin/libcolorout and ~17 other"
    echo "plugins are stale in this dt build (\`nm -u\` references the renamed-"
    echo "away OpenCL symbols → dlopen failure), and the export pipe then runs"
    echo "the IOP_CS_LAB module on UNCONVERTED domain — the flat probes match"
    echo "the unconverted model EXACTLY (flat 0.5: highlights-only c=0 →"
    echo "0.50247 = raw L/100 rescaled; shadows=+50 c=50 → 0.99005 = the"
    echo "(100−0.5)/100 mask overlay), so they pin the BROKEN route, not the"
    echo "module semantic. XMP adoption IS verified (DB op_params hex =="
    echo "pinned blob, \`params v. 5: version ok params ok\`)."
    echo
    echo "| case | params blob (hex) | sha256(blob) | reference sha256 (synthesized) |"
    echo "|---|---|---|---|"
    for xmp in "$GOLDEN"/cases/shadhi_*.xmp; do
        case_name="$(basename "$xmp" .xmp)"
        blob="$(grep -o '<darktable:params>[^<]*</darktable:params>' "$xmp" | head -1 | sed -E 's|</?darktable:params>||g')"
        blob_hash="$(printf '%s' "$blob" | shasum -a 256 | cut -d' ' -f1)"
        outs=""
        for f in $COLISA_REF_FIXTURES; do
            o="$OUT/${case_name}__${f}.exr"
            if [ -f "$o" ]; then
                outs="$outs $f:$(shasum -a 256 "$o" | cut -d' ' -f1 | cut -c1-16)"
            fi
        done
        echo "| $case_name | \`$blob\` | \`$blob_hash\` |$outs |"
    done
    echo
    echo "### sigmoid cases (Plan 03-04-T4, synthesized references + rgb_ratio flat probes)"
    echo
    echo "dt blob \`<ffffiffffffffi\` (56 bytes, dt_iop_sigmoid_params_t v3,"
    echo "hex-ASCII) ↔ Lightamer \`SigmoidModule.Params\` (JSON):"
    echo
    echo "| dt field (offset) | Lightamer field | note |"
    echo "|---|---|---|"
    echo "| middle_grey_contrast (0, f) | \`middleGreyContrast\` | [0.1,10], default 1.5 |"
    echo "| contrast_skewness (4, f) | \`contrastSkewness\` | [-1,1]; paper_power = 5^(−skew) |"
    echo "| display_white_target (8, f) | \`displayWhiteTarget\` | OUTPUT-side; ×0.01 |"
    echo "| display_black_target (12, f) | \`displayBlackTarget\` | OUTPUT-side; ×0.01 |"
    echo "| color_processing (16, i) | \`colorProcessing\` | 0 per_channel / 1 rgb_ratio |"
    echo "| hue_preservation (20, f) | \`huePreservation\` | [0,100] → [0,1] |"
    echo "| inset/rotation ×3 (24..48, f) | \`red/green/blueInset/Rotation\` | primaries path |"
    echo "| purity (48, f) | \`purity\` | [0,1] |"
    echo "| base_primaries (52, i) | \`basePrimaries\` | 0 work / 1 Rec2020 / 2 P3 / 3 Adobe / 4 sRGB |"
    echo
    echo "commit_params four-scalar derivation (sigmoid.c:318-407): verified"
    echo "END-TO-END by the rgb_ratio flat probes — dt matches the float64"
    echo "reference on flat 0 / −4 / −8 EV to ≤1e-5 (0.5→0.379984,"
    echo "0.03125→0.037023, 0.001953→0.002539). HOST FINDING: the per_channel"
    echo "leg SIGSEGVs dt-cli in this build (3/3 runs, exit 139) — per_channel"
    echo "is pinned by the CPUDerivation dual implementation + the shared"
    echo "derivation (identical scalars both paths, rgb_ratio-probe-verified)."
    echo "The primaries inset/rotation path carries a recorded deviation (dt's"
    echo "stored-matrix product order reads inverted against the applied"
    echo "chain; Lightamer implements the documented direction semantics —"
    echo "coincides exactly on the default identity path); sigmoid_smooth is"
    echo "pinned against the dual implementation, NOT dt."
    echo
    echo "| case | params blob (hex) | sha256(blob) | reference sha256 (synthesized) |"
    echo "|---|---|---|---|"
    for xmp in "$GOLDEN"/cases/sigmoid_*.xmp; do
        case_name="$(basename "$xmp" .xmp)"
        blob="$(grep -o '<darktable:params>[^<]*</darktable:params>' "$xmp" | head -1 | sed -E 's|</?darktable:params>||g')"
        blob_hash="$(printf '%s' "$blob" | shasum -a 256 | cut -d' ' -f1)"
        outs=""
        for f in $COLISA_REF_FIXTURES; do
            o="$OUT/${case_name}__${f}.exr"
            if [ -f "$o" ]; then
                outs="$outs $f:$(shasum -a 256 "$o" | cut -d' ' -f1 | cut -c1-16)"
            fi
        done
        echo "| $case_name | \`$blob\` | \`$blob_hash\` |$outs |"
    done
    echo
    echo "### dt-cli PFM probes (temperature + colisa + sigmoid + shadhi)"
    echo
    echo "Trust roles: temperature/colisa flats = per-pixel semantic evidence;"
    echo "sigmoid flats = derivation+curve evidence (rgb_ratio; per_channel"
    echo "crashes); shadhi flats = the broken-route mechanism record only."
    echo
    echo "| probe | sha256 |"
    echo "|---|---|"
    if [ -d "$OUT/pfm_probe" ]; then
        for p in "$OUT"/pfm_probe/*.pfm; do
            [ -f "$p" ] || continue
            echo "| $(basename "$p" .pfm) | \`$(shasum -a 256 "$p" | cut -d' ' -f1 | cut -c1-16)\` |"
        done
    fi
    echo
    echo "## dt-cli ↔ Lightamer colisa field mapping (Plan 03-03-T2)"
    echo
    echo "dt blob \`<fff\` (little-endian pack of dt_iop_colisa_params_t v1,"
    echo "hex-ASCII in XMP) ↔ Lightamer \`ColisaModule.Params\` (JSON):"
    echo
    echo "| dt field (offset) | Lightamer field | note |"
    echo "|---|---|---|"
    echo "| contrast (0, f) | \`contrast\` | both ∈ [-1,1]; commit rescale +1 → [0,2] |"
    echo "| brightness (4, f) | \`brightness\` | commit rescale ×2 → [-2,2]; gamma = 1/(1+b) if b≥0 else 1−b (colisa.c:220 — the plan text's 10^(−b) form does not exist in the source tree; recorded deviation) |"
    echo "| saturation (8, f) | \`saturation\` | commit rescale +1 → [0,2] (0 = unchanged, NOT b&w) |"
    echo
    echo "Pixel math (both sides): Rec2020→Lab (project LabRoundTrip constants;"
    echo "dt: pixelpipe work-profile conversion), L = ctable[L/100] →"
    echo "ltable[L/100] (NEAREST truncation lookups, power-law extrapolation"
    echo "above 1.0), a,b × (saturation+1), Lab→Rec2020. Track-A references"
    echo "are SYNTHESIZED (L017 route); dt pinned via the PFM probes above on"
    echo "the uniform flats + XMP op_params adoption."
    echo
    echo "## Canonical fixture sha256 (roundtrip outputs)"
    echo
    for f in $FIXTURES; do
        echo "- $f.exr: \`$(shasum -a 256 "$FIX/$f.exr" | cut -d' ' -f1)\`"
    done
    echo
    echo "## XMP-attach acceptance probe (Plan 03-01-T1)"
    echo
    echo "ramp_8ev column 48 = 0.25 exactly (v(x) = 2^(−8 + x/8)):"
    echo "default-pipeline export keeps 0.25 (±1e-6); \`exposure_plus1ev\` maps it to 0.5 (±1e-6)"
    echo "— i.e. the XMP-pinned history IS adopted by the export pipeline (the prebuilt"
    echo "1263552fab binary dropped it; rebuilt binary dc58cf0ba1 adopts it)."
    echo
    echo "## dt-cli host finding (Plan 03-02, 2026-09-19)"
    echo
    echo "darktable-cli (rebuilt dc58cf0ba1, Apple clang + libomp, macOS 27/arm64) emits"
    echo "SPATIALLY CORRUPTED float output for spatially-varying images in ALL float"
    echo "writers tried (EXR: per-channel-plane mislayout; PFM/TIFF: horizontal smear),"
    echo "deterministic per input; uniform images (flat_NNev) export exactly. Exposure"
    echo "on the ramp exports exactly through EXR (the 03-01 gate), temperature does"
    echo "not. A no-OpenMP rebuild was attempted (USE_OPENMP=OFF): darktable-cli then"
    echo "hangs at startup in dt_image_get_camera_id — unusable."
    echo "Consequences: temperature track-A references are SYNTHESIZED from the shared"
    echo "semantic (canonical fixture × pinned gains, float64 — gen_fixtures.py refs);"
    echo "dt-cli PFM probes on the uniform flats verify dt's per-pixel semantic"
    echo "(temperature_r120_b080 on flat_0ev: (0.6, 0.5, 0.4) exact, 4e-8); the pinned"
    echo "params adoption is verified via the library DB op_params hex + -d params log."
} > "$GOLDEN/manifest.md"

echo "manifest → $GOLDEN/manifest.md"
echo "done."
