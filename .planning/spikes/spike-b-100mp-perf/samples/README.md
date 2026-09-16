# Spike B sample files — provenance & license

Same source as Spike A (`samples/README.md` there): all files downloaded
2026-09-16 from **raw.pixls.us**, **CC0 1.0 public domain**. RAW files are NOT
committed (working copies at `.work/01-05/samples/`); golden rendered outputs in
`samples/golden/` ARE committed (2560×1440 aspect-fit RGBA8 PNG renders produced
by `perf-harness`-equivalent render path, linear Rec2020 working space → sRGB
output).

| Local file | Source URL (under https://raw.pixls.us/data/) | Role in Spike B | License |
|---|---|---|---|
| Fujifilm-GFX100S-14bits-losslescompressed-4_3.RAF | `Fujifilm/GFX100S/` | **Headline 100MP torture image** (101.8MP, 11648×8736) | CC0 |
| 7RM5-LosslessCompressedLarge.ARW | `Sony/ILCE-7RM5/` | 60MP upper-Bayer baseline (also CIRAW v9-capable) | CC0 |
| Nikon_Z8_raw_14_bit_lossless_compression.NEF | `Nikon/Z%208/` | 45MP common-pro-body baseline (plan's Canon R5 slot — R5/R5m2 CR3 not available on raw.pixls.us at execution time) | CC0 |
| B0000079.3FR | `Hasselblad/X2D%20100C/` | second 100MP data point (102.1MP) for the memory/tiling-threshold curve | CC0 |
| IQ4_150MP_L_14.iiq | `Phase%20One/IQ4%20150MP/` | 150MP candidate — **CIRAW cannot decode it** (Spike A finding); excluded from perf table | CC0 |

Plan substitutions vs 01-05-PLAN: Canon R5 CR3 (45MP) → Nikon Z8 NEF (45.4MP,
same sensor class); GFX100S RAF source is the 14-bit lossless-compressed variant
from raw.pixls.us rather than an in-house capture.
