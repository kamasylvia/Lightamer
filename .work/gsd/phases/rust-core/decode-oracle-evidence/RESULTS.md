# C4 oracle results (2026-11-25 night, Apple M4 / macOS 27.3)

All 7 outputs: 9568x6376 RGB, IHDR bitdepth 16, ~311 MB each. Wall 17.6–20.8 s/run.
Full cmp16 transcripts: cmp16-full.log (6 pairs, archived rerun).
Stray file note: /tmp out/ also holds g0-full-cl.png (23:23, 310908453 B, sha 5b3518aef0f936f8,
early CPU-path run predating the bpp fix verification — superseded by g0-full-cl_01.png, NOT an oracle output).

## Backend proof lines (from full-runs.log)

- CPU leg: `[opencl_summary_statistics] device 'Apple Apple M4' id=0: NOT utilized`
- CL leg: `OpenCL:0 tiled direct bayer demosaic RCD. tiles=10 tileheight=670 overlap=10`
  + `161 out of 161 events were successful and 0 events lost`

## Noise floor: repeat + CPU-vs-OpenCL (16-bit LSB units, tol = 1/255 = 257 LSB)

| pair | mean (LSB16) | max (LSB16) | in_tol frac |
|---|---|---|---|
| G0 cpu vs cpu-r2 (repeat) | 0.0000 | 0.0000 | 1.00000000 |
| G0 cpu vs cl | 0.0132 | 842.0 | 0.99999995 |
| G1 cpu vs cl | 0.0137 | 904.0 | 0.99999994 |
| G2 cpu vs cl | 0.0137 | 904.0 | 0.99999994 |

Read: repeats are pixel-identical (PNG bytes differ => metadata only; dither is deterministic,
推断 fixed seed). CPU-vs-OpenCL mean ≈ 0.01 LSB16; max ≈ 850–900 LSB on ~10 pixels
((1-0.99999995)*183M ≈ 9 px). G1/G2 identical stats: flip commutes with backend diff.

## Cross-group (history takes effect)

| pair | mean (LSB16) | max | in_tol frac | note |
|---|---|---|---|---|
| G0 vs G1 | 2600.87 | 10562.0 | 0.0195 | exposure +1EV: ch means .218/.488/.410 -> .256/.530/.449 |
| G1 vs G2 | 7747.82 | 62724.0 | 0.0299 | flip: ch means EXACTLY equal; mirror test (G2 fliplr vs G1, fullres-mirror.log): dx=dy=0 mean/max 0.0000/0.0000 = bit-exact mirror, no 1px shift at full res |

## Probe findings (1600px, uint8)

- G0 vs minimal-XMP G1: same shape 1066x1600; mean diff 10.14 LSB8, max 44.
- G2 mirror check at 1600px: plain-vs-mirror search best at dx=+1 (mean 1.96 vs 8.84 LSB8):
  1px horizontal offset observed in the --width scaled path only. Full-res mirror search
  (3x3 shifts, fullres-mirror.log): dx=dy=0 gives 0.0000/0.0000, all 8 shifted variants
  >= 929 LSB mean — full-res flip is a bit-exact mirror; the 1px probe offset is a scaler-path
  artifact, not the flip module.
- Null-xmp (foreign history) probe rendered fine but is NOT camera-correct; do not use as oracle input.

## Verdict for oracle use

- Oracle command: CPU leg, full-res, 16-bit PNG, minimal XMPs as in this dir.
- Pixel tolerance proposal: mean < 1 LSB16 + in_tol(1/255) > 0.9999 passes; max up to ~1000 LSB
  on < 100 px is backend noise, not failure. Repeats are bit-exact, so any systematic shift is real.
