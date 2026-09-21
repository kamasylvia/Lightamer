# 05-03 dt-cli 采纳证据（F3，2026-09-22 修复轮实跑）

重建版 dt-cli（`darktable 5.5.0+1862~gdc58cf0ba1-dirty`）对修后 88B legacy blob
的采纳实证：每 case 跑 `darktable-cli flat_0ev.exr <case>.xmp`（`--apply-custom-presets 0`
+ fresh library DB + `-d params`），三证据逐 case 齐全：

- ① XMP blob：`input/golden/cases/<case>.xmp`（legacy 88B hex，176 hex chars）
- ② history loader：`successfully loaded module <op> from history` + `params v. N: version ok params ok`
  （channelmixer v2 / colorcontrast v2 / channelmixerrgb v3；`blendop v.1 WRONG` 为既有 blend 头版本杂音，非本模块——12/12 一致出现）
- ③ library DB：`SELECT hex(op_params) FROM main.history` 与 XMP blob 逐字节一致（12/12；legacy 176 hex / contrast 40 hex / cmr 320 hex）

原始日志：本目录 `adopt_<case>.log`（12 份）；DB hex 汇总：`adopt_hex.txt`。

| case | op | loader 行 | DB hex vs XMP |
|---|---|---|---|
| cm_rgb_swap | channelmixer | params v. 2 ok | byte-identical (176 hex) |
| cm_gray_luma | channelmixer | params v. 2 ok | byte-identical (176 hex) |
| cm_hsl_v1_sat | channelmixer | params v. 2 ok | byte-identical (176 hex) |
| cc_default | colorcontrast | params v. 2 ok | byte-identical (40 hex) |
| cc_steep | colorcontrast | params v. 2 ok | byte-identical (40 hex) |
| cc_bound | colorcontrast | params v. 2 ok | byte-identical (40 hex) |
| cmr_default | channelmixerrgb | params v. 3 ok | byte-identical (320 hex) |
| cmr_tungsten_linear | channelmixerrgb | params v. 3 ok | byte-identical (320 hex) |
| cmr_bb_full_satv1 | channelmixerrgb | params v. 3 ok | byte-identical (320 hex) |
| cmr_fluor_xyz | channelmixerrgb | params v. 3 ok | byte-identical (320 hex) |
| cmr_led_rgb_grey | channelmixerrgb | params v. 3 ok | byte-identical (320 hex) |
| cmr_custom_satv2 | channelmixerrgb | params v. 3 ok | byte-identical (320 hex) |

注：此前 SUMMARY「dt 三证据 ×3」为假声明（52B blob 不可能被 dt 采纳）——本轮以 88B blob 实跑替换为真证据。
