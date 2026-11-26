# omp-history-summary — 历史兼容调研 lane 交付（2026-11-25）

产物：`HISTORY-COMPAT.md`（§0-§11）+ `HISTORY-COMPAT-TABLES.md`（Table 1-7）+ `history-review.log`。基线 dt-master @ `679d594f5d`。

核心结论：

1. 历史两处存：DB（`history`/`masks_history`/`module_order`/`history_hash` + `images.history_end`）与原图旁 `<file>[ _NN].xmp`；写时机三档 pref `write_sidecar_files`（默认 `on import`）。
2. XMP 历史 = `darktable:history` 结构数组（10 属性/条）+ `history_end` + `iop_order_version/list` + `masks_history` + 3 hash + `xmp_version`=5；已知 key 共 41 个（`dt_xmp_keys`）。
3. 参数 = 整块 POD 内存镜像，DB BLOB ↔ XMP hex（>100B 可 zlib+base64 加 `gz` 前缀）；`version()`=N 判别 + `legacy_params` 链式迁移；无端序处理、无 packed；9 模块版本/size/迁移全表在案，无指针/变长反例。
4. 顺序表 5 张编译在 `iop_order.c`，默认 V50/V50_JPG；custom/多实例才存文本；运行时 int（100 起步长 100）。
5. 多实例键 = `operation+multi_priority`；blend v15 整块 + 1→15 迁移链；蒙版 shapes 走 `masks_history`，经典参数蒙版内嵌 blendop。
6. 未知 op：XMP→DB 照存，DB→内存跳过不断链，超前版本用默认保留；未知 XMP key 读忽略写保留——Lightamer 独有功能可安全存同一份历史。
7. 入口：`dt_exif_xmp_read`（exif.cc:4924）/ `dt_exif_xmp_write`（:6933）/ `dt_dev_read_history_ext`（develop.c:2437）/ `dt_dev_write_history_ext`（:2011），均为纯逻辑+DB/Exiv2。
8. 样例 `G1_bare_uniform.xmp` exposure v6 24B 逐字节解出（mode/black/5.0/50.0/-4.0/FALSE），v6→v7 迁移补 FALSE。
9. darktamer 未改历史格式（exif/database 仅品牌文案，iop_order +11 行分属 3 新模块）。
10. 裁决 8 点：exiv2 起步、复用 dt 表结构、bindgen 布局、legacy 近2版、blend 走迁移链、LE-only、默认 on import、darktamer 模块读跳过写保留。
11. 没查到：`sizeof` 未编译验证、v1 XMP 样例缺失（`memory.history` 建表与 `dt_conf` 后端经复审已找到，见 §10/§11）。
12. 复审：独立 omp 实例判 `3 error + 13 minor`（见 `history-review.log`），16 条已逐条核实回注（§11 修订记录）：E1 jpg 表各+1/E2 memory.history 建表 database.c:3722/E3 hash 枚举行号 + 13 minor 行号口径。复算无误：9 sizeof/9 版本/9 legacy/Table 6/41 key。

