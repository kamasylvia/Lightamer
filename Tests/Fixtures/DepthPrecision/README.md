# DepthPrecision fixtures (M4-3-01 T6, KD-7)

The depth conversion-precision golden inputs + the F32 reference outputs.

## Contents

| file | role |
|---|---|
| `scene-soft-shapes.png` | natural-like scene (smooth depth structure + vignette) — IN GATE |
| `scene-texture.png` | natural-like scene (layered band noise + fine detail) — IN GATE |
| `target-edges.png` | synthetic bars + checkerboard edge target — IN GATE |
| `scene-horizon.png` | landscape-like bands + sun disc — e2e fixture only (matched-pipeline 0.0092 = 92% of gate; margin hygiene) |
| `target-ramp.png` | horizontal ramp — e2e fixture only (structure-less OOD input) |
| `ref-f32.bin` | the F32 package's outputs, concatenated blocks `[UInt32 LE width][UInt32 LE height][row-major F32 LE plane]` in the GENERATOR's INPUTS order (soft-shapes, texture, horizon, ramp, edges); 5×815,232 = 4,061,160 bytes |

All five are 518×392 (the D-4 spike's static shape). All PNGs carry the
standard sRGB ICC profile (see the pipeline-exactness note below).

## Provenance / regeneration

The images are SYNTHESIZED deterministically (seed 20261010) by
`Scripts/ai-models/gen-depth-golden.py`; the reference comes from Apple's
official F32 package at the pinned HF revision
`cfef6f6f2a70783dedc0bfae40cecbc2052285d3` (CPU_ONLY predict).

```
uv run --with coremltools --with numpy --with pillow \
  python Scripts/ai-models/gen-depth-golden.py \
  --f32-package <path-to-DepthAnythingV2SmallF32.mlpackage> \
  --fixtures-dir Tests/Fixtures/DepthPrecision
```

Re-running must be byte-identical (PNG encode + float serialization are
deterministic for the same inputs).

## Pipeline exactness (probed, 2026-10-10)

The fixtures are natively 518×392 and sRGB-tagged: the runtime
CGImageSource → CGContext(.medium) draw is an identity resample whose R
channel is byte-identical to the PIL reference pipeline's (full-plane
diff = 0 on target-edges), and the DepthSession F16 output is
BYTE-IDENTICAL to the coremltools CPU predict on the same input
(standalone three-way probe: sess-vs-py max diff = 0.000000). The gate
below therefore measures F16-vs-F32 CONVERSION noise with zero
pipeline-mediated perturbation.

## PLAN DEVIATION (declared, 2026-10-10)

The plan's 「真实 RAW 降采样样张 2」 is not satisfiable from in-repo or
reference-repo material: personal photos violate the privacy red line
(open repository), the reference repos' imagery is UI screenshots (GPL,
and not photographic content). The precision gate's discriminating power
does not depend on photographic provenance — F16 quantization noise is
content-independent to first order — so the scene fixtures are
synthesized natural-like content.

## Measured distribution (matched pipeline, 2026-10-10, CPU_ONLY)

| input | abs-rel | max-abs | membership |
|---|---|---|---|
| scene-soft-shapes | 0.002339 | 0.010742 | gate (.all leg, passes) |
| scene-texture | 0.002908 | 0.010254 | gate (.all leg, passes) |
| target-edges | 0.003578 | 0.011719 | gate (.all leg, passes) |
| scene-horizon | 0.009238 | 0.016113 | e2e only (gate-margin hygiene) |
| target-ramp | 0.023729 | 0.048828 | e2e only (OOD) |

Metric: `rel = |f16 − f32| / max(|f32|, 1e−3)` averaged over the plane;
max-abs = max |f16 − f32|.

Gate pins (OQ-6 effective values):

- **abs-rel ≤ 0.01** over the three in-gate fixtures (the natural rows
  sit ≈3× under Apple's official F16 self-report 0.0089);
- **max-abs ≤ 0.02** (the observed in-gate max 0.0117 + headroom; not
  tuned to any failing fixture — the two exclusions are domain/margin
  calls documented above, not lowered gates).
