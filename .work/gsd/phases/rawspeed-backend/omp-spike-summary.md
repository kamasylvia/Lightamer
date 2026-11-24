# rawspeed spike — 交付摘要（issue #24）

问题：#24 是否接 rawspeed 后端、以什么形态、收益多少。

## Q1 形态

- **Swift 6 直接 C++ interop = 不可行**（驱动可以，读取全封死，错误即崩）。`RawImage::get()` 被 interop 的 interior-pointer 规则禁用；`operator->` 不导入；像素访问器只能经那个被封死的指针到达；`RawImageData::data` protected。且 rawspeed 函数被导入为**非 throwing**：坏输入实测 `SIGABRT (EXIT=134)`。
- **C ABI 薄封装 = 可行**（darktable 同款）：shim 165 行 + 头 68 行，异常零穿出（坏输入 → `code=2` + 消息，进程存活），Swift 6 严格并发编译通过，字段与像素哈希三路一致（`0xbd81df79e1a15f93`）。
- 置信：高（编译错误原文 + 运行时对照实验）。

## Q2 体验速度（用户动作 → 位图就绪；冷启动每测量独立进程；10 次中位）

| 指标（冷启动，每测量独立进程，10 次中位） | P0 CIRAW v8（现状） | P1 首开（rawspeed→内存 DNG→CIRAW） | P1 缓存 DNG（盘上 122 MB） |
|---|---|---|---|
| M1 · 适配屏 2560 | 968 ms | **447 ms** | **374 ms**（ds1 239 / ds2 202） |
| M1 · 全分辨率 | 1048 ms | **556 ms** | **482 ms** |
| M2 编辑 · 适配屏（每次新曝光值） | 738 ms | — | **13 ms** |
| M2 编辑 · 100% ROI | 1.8 ms | — | 1.5 ms |
| RAW 9（v9DNG） | — | 3177 ms | — |

热（同进程重开 + clearCaches）：P0 759 / 835 ms；P1b 244 / 276 ms（ds1 57 ms）。

关键事实：CIRAW 对输出尺寸不敏感（2560/1280/640 = 968/993/1001 ms）→ **降采样必须在解码前**；rawspeed 解码段 34–57 ms（同文件 LibRaw unpack 618–638 ms，解码段口径）；RAW 9 经 DNG 对 rawspeed 马赛克可用，但每次 3.18 s，只适合导出档；**编辑等待差近两个数量级（13 vs 738 ms）来自「已解码平面能否被复用」**。

## Q3 取舍

- 最快且体验最好 = **rawspeed 解码 + 小档解码 + 目标尺寸直渲 + 100% 只渲可见 ROI + 分块/小预览缓存**（lumen-raw / Alcedo / darktable 三方同构，file:line 见 SPIKE.md §5）。
- **自写解码器不值**：rawspeed 已覆盖格式且比 LibRaw 快 16×；缺口只剩 C++ 边界（形态 B 已证）与 demosaic 归属（DNG→CIRAW 或自有 Metal）。

## 自审

第一轮：`evidence/SELFREVIEW.md` = **4 error + 13 minor**；第二轮：`SELFREVIEW-2.md` = **3 error + 11 minor**；第三轮：`SELFREVIEW-3.md` = **1 error + 10 minor**（仅 §5.3/§7.5 两处旧数字残留，已修；N1/N2/N3 判 FIXED、`tables.py` ↔ §4 逐行全等）。三轮 error 已逐条修：P1 首开单列、`benchlive` 补 `hash_ms`、§8 按 §4 重写、§4 表由 `evidence/tables.py` 从 `bench.csv` 机械生成（报告与数据同源）、`bench.sh` 的机器守卫路径修正。修订表见 `SPIKE.md` §6.11。

## 偏差申报

1. v2 遗留 T1 的 `mosaic_fnv1a64_cropped` 值（`0xbcc1…`）来自 FNV 偏移基笔误（少一位）；本次修正后三路（rsprobe / shim / DNG 字节 Python 复算）一致为 `0xbd81…`，旧值作废。
2. P1 的 `ColorMatrix1` 用 rawspeed 原值（与其文档方向相符）才渲染正常；按 DNG 规范字面写逆矩阵会过曝 2.5–3 档。需在 #24 用色卡复核。DNG 降档 binning 必须 GPU/紧密循环化（初版 CPU 双精度 855 ms，改后 68 ms）。
3. P2 用 LibRaw 端到端作 CPU demosaic 替身（未建 Metal 原型）。
4. 「产品现状真值」探针（`QuickLookPerfProbeTests`，`LA_QL_PERF=1`）未跑：需产品测试构建且口径走导出链，决定影响为零；归 #26。
5. 轮间漂移：P0 基线四轮 894–992 ms（±5%），P1a fit 427–468 ms；另一 lane 的 `ApplicationsStorageExtension`（~30% CPU）在场时整轮慢 8–12%，个别行 +21%。表内数字 = 最终 `bench.csv` 那一轮。
6. 计时口径按第一轮自审修订（P1 首开单列、校验哈希移出计时窗、M2 每次换新曝光值）；修订明细见 `SPIKE.md` §6.11 与 `evidence/SELFREVIEW.md`。

## 证据

`evidence/`：`bench.csv` / `bench-run.log` / `bench.sh` / `benchrun.py` / `t1-a7r5-meta.txt` / `t2-form-a.log` / `t3-shim.log` / `xcheck.txt` / `dng-props.txt` / `SELFREVIEW.md`。
`spike-src/`：shim、Swift 探针、两个 `Package.swift`、DNG 写入器、rsprobe、xcheck、lrbench、bench。
报告正本：`SPIKE.md`。

## 未验项

RAW 9 的 CoreML 资源是否需联网首次下载（`downloadResources` API 存在，未触发验证）；v9 的既有绿偏缺陷未在本 DNG 路径复测；XCFramework 未实际构建；LGPL-2.1 静态链接合规处置待决策；Metal demosaic 无本机数字。
