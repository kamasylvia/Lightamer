# 05-04 dt-cli 采纳证据（验收复验补跑，2026-09-22）

重建版 dt-cli（`darktable 5.5.0+1862~gdc58cf0ba1-dirty`）对 9 case XMP 的采纳实证
（`--apply-custom-presets 0` + fresh library DB + `--core -d params`）：

- vib/vel 5/5：loader ✓ + `params v.2 version ok params ok` ✓ + library DB
  `hex(op_params)` 与 XMP blob **byte-identical**（大小写归一后；dt 写大写 hex）
- cz 4/4：**本机 dt 构建 OpenCL 桩坏**（libcolorzones.so dlopen 失败，
  `_dt_opencl_copy_host_to_device` 符号缺失——同批 filmic/colormapping/
  rawoverexposed/hazeremoval 同因），插件不可加载，DB 无记录。此为 host 构建
  环境问题（D-05-04-T3-4 既有记录），非 blob 版式问题；cz blob 版式以
  `struct.calcsize`=520B 与 dt sizeof 对照为准。dt 重建后补跑。

原始日志：本目录 `adoption/adopt_<case>.log`（9 份）+ `<case>.db`；汇总 `adopt_hex.txt`。

| case | op | loader | version ok | DB hex vs XMP |
|---|---|---|---|---|
| vib_default | vibrance | 1 | ok | byte-identical |
| vib_strong | vibrance | 1 | ok | byte-identical |
| vel_default | velvia | 1 | ok | byte-identical |
| vel_strong | velvia | 1 | ok | byte-identical |
| vel_clamp | velvia | 1 | ok | byte-identical |
| cz_default | colorzones | 0（插件坏） | — | host 环境约束 |
| cz_hue | colorzones | 0（插件坏） | — | host 环境约束 |
| cz_chroma | colorzones | 0（插件坏） | — | host 环境约束 |
| cz_lightness | colorzones | 0（插件坏） | — | host 环境约束 |
