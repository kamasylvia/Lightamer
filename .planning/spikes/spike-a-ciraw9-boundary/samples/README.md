# Spike A sample files — provenance & license

All RAW samples were downloaded 2026-09-16 from **raw.pixls.us** (the RAW-editing
community sample repository used by darktable/RawTherapee/rawspeed for CI and
profiling). Every file on raw.pixls.us is published under
**CC0 1.0 (public domain dedication)** — see https://raw.pixls.us ("All raw
samples are licensed CC0 unless stated otherwise"; the site indexes only CC0
material and links the license at creativecommons.org/share-your-work/public-domain/cc0/).

Files are NOT committed to this repo (0.5–200 MB each; `.work/01-05/samples/`
holds the working copies on this machine). Re-fetch with the URLs below.

Golden crops in `samples/golden/` ARE committed: 320×240 100% center crops
rendered by `ciraw-probe.swift` (RGBA8 sRGB) — `-8` = CIRAW decoder v8,
`-9` = decoder v9. They are the reproducibility baseline for the CIRAW-2
pitfall (Apple changing decode internals across macOS versions — re-render and
diff after every macOS upgrade).

| Local file | Source URL (under https://raw.pixls.us/data/) | Camera | Size | License |
|---|---|---|---|---|
| IMG_1361.DNG | `Apple/iPhone%2012%20Pro/IMG_1361.DNG` | iPhone 12 Pro (ProRAW DNG) | 28 MB | CC0 |
| 5G4A9394-compressed-lossless.DNG | `Adobe%20DNG%20Converter/Canon%20EOS%205D%20Mark%20III/` | Canon 5D III → Adobe DNG | 22 MB | CC0 |
| DSC00001.ARW | `Sony/ILCE-6700/DSC00001.ARW` | Sony a6700 (ILCE-6700) | 42 MB | CC0 |
| IMG_4276.CR3 | `Canon/EOS%20R10/IMG_4276.CR3` | Canon EOS R10 | 30 MB | CC0 |
| DSCF0074.RAF | `Fujifilm/X100VI/DSCF0074.RAF` | Fujifilm X100VI (X-Trans 5) | 84 MB | CC0 |
| IMG-20221005-0665.raf | `Fujifilm/X-H2S/IMG-20221005-0665.raf` | Fujifilm X-H2S (X-Trans 5 stacked) | 29 MB | CC0 |
| DSCF0021.RAF | `Fujifilm/X-T5/DSCF0021.RAF` | Fujifilm X-T5 (X-Trans 5 HR) | 41 MB | CC0 |
| 80mp-12bit-tripod.orf | `OM%20System/OM-1%20Mark%20II/80mp-12bit-tripod.orf` | OM System OM-1 Mark II (Quad-Bayer high-res 80MP tripod) | 69 MB | CC0 |
| Nikon_Z8_raw_14_bit_lossless_compression.NEF | `Nikon/Z%208/` | Nikon Z8 (45.4MP) | 58 MB | CC0 |
| 7RM5-LosslessCompressedLarge.ARW | `Sony/ILCE-7RM5/7RM5-LosslessCompressedLarge.ARW` | Sony A7R V (60.2MP) | 82 MB | CC0 |
| Fujifilm-GFX100S-14bits-losslescompressed-4_3.RAF | `Fujifilm/GFX100S/Fujifilm-GFX100S-14bits-losslescompressed-4_3.RAF` | Fujifilm GFX100S (101.8MP X-Trans) | 105 MB | CC0 |
| B0000079.3FR | `Hasselblad/X2D%20100C/B0000079.3FR` | Hasselblad X2D 100C (102.1MP) | 203 MB | CC0 |
| IQ4_150MP_L_14.iiq | `Phase%20One/IQ4%20150MP/IQ4_150MP_L_14.iiq` | Phase One IQ4 150MP | 161 MB | CC0 |

Plan substitutions vs 01-05-PLAN sample list (all documented in the report):
Canon R5 CR3 → Nikon Z8 NEF (45MP pro slot); Canon R50 → Canon R10; Adobe
converted DNG available as 5D III conversion; OM-1 II high-res ORF covers the
Quad-Bayer slot.
