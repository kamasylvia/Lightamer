# 独立复跑 summary — rawspeed spike（issue #24）

**PASS / 3 error + 8 minor**（error 全修；minor 全修或复核为「当前版已修」）。HEAD `144a76b9`，2026-11-25。详细证据 = `evidence/RERUN.md`。

## 对账超 ±15% 的 5 格（全部更快）

| row | kind | 归档 | 复跑 | 偏差 |
|---|---|---:|---:|---:|
| P1a live ds0 full | cold | 555.5 | 460.8 | -17.0% |
| P1b cached-DNG ds0 full | cold | 481.5 | 391.3 | -18.7% |
| P1b cached-DNG ds0 full | hot | 275.9 | 226.1 | -18.1% |
| P0 CIRAW v8 fit | hot (M2) | 738.3 | 329.3 | -55.4% |
| P1 cached-DNG ds0 fit | hot (M2) | 13.3 | 10.0 | -24.8% |

其余 21 格在 ±15% 内；M1 的 P1/P0 比值保持 ~2.0–2.2×（P0 868/939、P1a 401/461、P1b 337/391 ms）。

## 七件事各一句

1. **重跑基准**：未改一行 `bench.sh`/`benchrun.py` 副本、机器守卫 PASS（heavy=0 free=71%）、26 格全跑；5 格超 ±15% 全部更快，原始输出 `evidence/rerun-bench.csv` / `rerun-bench.log`。
2. **核口径**：M1/M2 计时窗正确、哈希窗外、冷=独立进程、热每 rep `clearCaches()`（只保证 CI 层，RawCamera 不可控，原报告已申报）；P0 的 decoder version 与产品一致，但渲染腿是 sRGB RGBA8 + `cacheIntermediates: true`，产品是 linear Rec2020/RGBAh/32F texture + `cacheIntermediates: false`——P0 是**同形近似**；**P0 M2 用 CIColorMatrix 下游乘法，不是 CIRAW 曝光参数**；738 ms 仍高估产品，因为 harness 没冻结解码平面，产品有 render-once memo。
3. **核 Q1**：编译错误支持「直接 interop 不可行」；补试 `operator*`/`.pointee` 也不导入（排除「只试一两条路径」）。shim 异常零穿出（`noexcept` 访问器 + 全捕获），内存归属闭合；**潜在契约冲突**：decoder 保活但 `FileReader` storage 已释放（open 后不再调用 decoder，实测无害；生产化须去掉 decoder 或保留 mapping）。并发：每 handle 独立，本 shim 每次 open 解析一份 meta（线程安全，非共享）。
4. **核 P1 两隐患**：ColorMatrix1 方向**独立证明为 XYZ→camera**（rawspeed 矩阵 = LibRaw `cam_xyz`，max diff 0；`cam_xyz @ rgb2xyz` ↔ `rgb_cam` 吻合 1e-7），写原值正确；RAW 9 的 3.18 s = 冷进程，首进程模型准备 ~2.1 s 一次性，稳态 ~2.8 s（render ~2.7 s = v8DNG 的 ~15×）。
5. **核隐私/边界**：无图像文件、无真实 GPS/作者/序列号；产品树 `git status`/`git diff` 零改动；历史 `bench-run.log` 的 `heavy_procs` 行含另一 lane argv（m8），已改为 `pgrep -l`，复跑日志为 `none`。
6. **SELFREVIEW-3 余项**：m1/m5/m6/m7/m8/m9 真→修；m2/m3/m4/m10 当前版已修→复核不改；m6 升级为 error（T1 引文 100.8/43.1 vs 文件 992.1/40.4）。新增 3 minor：decoder 契约、`rs_mosaic_hash` 类型门、interop 注释「template」。
7. **修与落账**：`SPIKE.md` 的 §0 Q2 / §4.3 / §4 关键读数 / §4.5 / §4.9（新增）/ §5.3 / §6.1/6.2/6.5/6.12 / §7.5/7.6 / §8 全部改写；脚本修 m7/m8；shim 注释 + 类型门；新增复跑工具 5 个。§4.1–§4.4/§4.7 表仍由 `tables.py` 从 `bench.csv` 生成（表行 diff 全等）；§4.9 表由 `rerun_tables.py` 机械生成。零 push。

## 结论变化（最重要）

- **撤回**「编辑等待差两个数量级 / 57×」。产品形态对照（冻结 2560 输入平面 + 下游曝光）：P0 **1.69 ms**、P1 **1.76 ms**（n=10）。rawspeed 的体验收益 = **首开 ~2×**（447/374 vs 968）与机型覆盖，不是编辑。
- **保留**：M1 绝对值的跨轮漂移（5/26 超 ±15%，全部更快）；RAW 9 不可进预览档；rawspeed 与 LibRaw 马赛克逐像素相同；形态 A 不可行。

## SELFREVIEW-3 余项判定

m1 真→改 `8873c77c`；m2 已修；m3 已修；m4 已修（复跑进一步拆冷/稳态）；m5 真→补双向漂移；m6 真→升级 error R4；m7 真→`BENCH_OUT` + quick 不覆盖；m8 真→`pgrep -l`；m9 真→显式 15×/9.2×；m10 已修（165 行）。

## 未验项

- 产品 GUI 真值（`QuickLookPerfProbeTests` / #26）未跑：重活 + 与基准互斥；P0 产品形态用同形 CI 探针，不是 GUI 逐字节。
- ColorChecker / 受控光源的色彩标定未做（方向已证，偏色未标）。
- V9 绿偏缺陷（G/R≈3.9×）未复核。
- XCFramework 未构建；LGPL-2.1 静态链接合规未决。
- Metal demosaic 原型未做。
- 仅 A7R5 CC0 单样张；其它机型/格式（X-Trans、CR3、float DNG）未测；`rs_mosaic_hash`/dngwriter 的 UINT16 门已补哈希侧，dngwriter 仍只覆盖 UINT16。
- 100% ROI 产品形态对照未单跑（harness 与产品都已 ~2 ms，非关键路径）。

## 提交

commit SHA：见交付消息（本文件与 `evidence/RERUN.md` 同提交；`git log -1 -- .work/gsd/phases/rawspeed-backend/omp-spike-rerun-summary.md` 可复核）。零 push。
