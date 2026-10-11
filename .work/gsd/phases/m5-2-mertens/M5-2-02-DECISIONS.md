# M5-2-02 DECISIONS — Mertens 生产腿与 UI 收口批（wave 2 执行批，2026-10-14）

> 执行 subagent worker 落账。基线 = `7d9708f` 后 HEAD；执行 commits：T1
> `826fa5b` / T2 `5afa952` / T3 `45bcfe4` / T4 `e52bd6f` / T5（本批 docs）。
> checker 回注三项（M1 兜底/M2 双帧恒等 = 01 已落，02 继承；M5 test_bundles
> 口径 = 本节 §1 处置）。

## §1 checker minor-5（02 front-matter test_bundles 含 Library）处置

按处方第二选（注记形）：02 的四新测试文件落域 = **IOP×2 / APP / EXPORT**，
无 LIB 落域文件；front-matter 的 `Library` = **G5 复验定向轮口径**（01 的
`MertensProvenanceTests` LIB 行支撑复验面，02 批照跑 `--bundle Library`
作共存零回归见证——T5 拼表含之）。plan 文件不回改（执行批不改 planner
正文惯例）。

## §2 KD-1 落地形的五项执行裁决（流式腿语义面）

1. **掩码 = 共享单通道（非 per-source）**：KD-1 草图「pixels UInt8 掩码
   双通道（每源掩码落盘）」按 merge.py 语义修正——`ghost_mask` 是**全帧
   并集单平面**（union 跨源 max 累积），置换 α 对所有帧同一。dilate 对 max
   可分配，但羽化（Gaussian）不可——per-source dilate+feather 再并集 =
   近似而非移植正本。落地 = 阶段末全帧 union → **一次** dilate + 一次
   feather → 单个共享 `mask.u8`（UInt8 量化）落盘；磁盘账 N×16+1 B/px ≤
   OQ-6 的 N×(16+1) B/px。`readShiftedMask` 命名相应落为
   `readMaskBand`（掩码在参考/输出帧坐标系，不随 MTB shift）。
2. **置换 LUT 估计 = staged 网格行读回**（非全帧回读）：LUT 的 static 格
   定义在**最终**软掩码上（merge.py:145），只能在掩码定稿后估计；脚手架
   等价测试钉死「网格行读回 LUT == 整帧 `substituteLUTs` LUT」逐字段相等
   （`MertensLegTests.testGridRowSubstituteLUTsMatchWholeFrameFace`）。
   百分位多重集与采样序无关——等价成立。
3. **分离式 dilate**：生产 100MP 半径 32-58（tier 缩放）下 01 golden 的
   O(r²) naive 形为分钟级——`mertensSeparableDilate`（水平+垂直两次
   max 过轴）输出**逐位相同**（max filter 轴可分解），O(r)/轴；golden 面
   `MertensFusion.dilate` 零触碰，恒等由测试钉死。
4. **NaN 消毒 → 0**：shift 读出的 out-of-overlap NaN 在 provider 内消毒为
   0——黑码在 Mertens 权重族下 E³≈8.5e-5 自然近零权（01 G3③ 常数），
   免显式权重门。与 MertensFusion 头注的调用方契约一致。
5. **带网格对齐（01 DECISIONS §6 继承约束兑现）**：`mertensAlignedBands`
   band 起点整除 2^(L−1)、band 高取整到同倍数（≈256 行）；halo 恒为
   2^(L−1) 倍数（halo = max(32,2^L)），stripFirst = band.y − halo 保持
   对齐——带内行与整帧参考**逐位相等**经驱动级测试钉死
   （`testBandOuterFuseMatchesWholeFrameGolden`，多 band 600 行 fixture）。

## §3 plan 偏差与申报（三处）

1. **files_modified 之外两文件**：①`ContentView.swift`——seam 穿线
   （`onHDRMertens` 闭包 `Task { await coordinator.mertensMergeHandler? }`，
   与既有四 merge seam 完全同形的机械传递，零自有逻辑）；②
   `MertensMergeKindTests.swift`——01 的 stub 形测试
   `testProductionStubFailsTypedNamingM5_2_02` 被 T1 落地作废，改写为
   `testProductionLegLandsAfterM5_2_02`（真实腿落地产物断言；stub 所钉的
   「未落地态」被它点名的落地 plan 终结——plan KD-4 预宣告的结构）。
2. **landStackProduct 加参面超 KD-4 点名两项**：`implementationVersion` 与
   `productColorSpace`（T2/KD-2 消费）同族 default-nil additive——语义
   必要（mertens 版本常量独立于 hdr；单一路径落地的 tag 承载），nil 路径
   字节零漂移负测钉死（既有 kind 断言原值）。
3. **evidence 目录不入 git**（`.gitignore` 证据域惯例 / L073）：plan
   files_modified 列了 `evidence/lumen-structural-compare/`——文件已落盘
   （脚本 + 报告 + bench 源存证），随证据域政策出主仓；SUMMARY 注记路径。

## §4 探针与预算证据（正本 = perf.md；此处执行批侧记）

- **环境链**：首轮 Debug 全路径探针被系统杀死（staged 脏页 phys_footprint
  16.28 GB / ru_maxrss 本身 6248 MB 达标）→ sync 回写修复；被杀进程
  `defer` 不跑 → staged 残留两度吃满系统盘（ENOSPC 卡 harness，L049 同族
  变体）→ 手工清扫 + runbook 化；Release 直启链因工具链级链接不对称
  （Release 动态引用 WebP 包 framework 且未 embed；Debug 静态）不可达
  （D-09-04-D9 重签+entitlements 配方用尽，framework 根本未产出）——
  登记环境债，CPU 数值面走 `swiftc -O` 脚手架。
- **终值**：融合核 172.24s（100MP×5，含置换）= 预算内、零 GPU 化触发；
  ru_maxrss 6248MB < 8G 门（AC#4）；流式驻留恒 ~2.9GB。三起事故全环境/
  探针侧，产线零缺陷（LESSONS 承接）。

## §5 待供件 / 挂账移交

1. **G6 Manual-Only 走查行**——配方 = `.work/gui-acceptance/m5-2/MANIFEST.md`
   （双算法各合一张 + deghost 三档对比 + `_mertens` 分账核 + 重导入观感）；
   执行 = 用户/orchestrator 安排，证据回填 ACCEPTANCE。
2. **双重验收**：`M5-2-02-ACCEPTANCE.md` 由验收波落盘（zcode PASS → 串行
   omp，严禁并发）；本批不预写。
3. **Release 直启注入链环境债**（perf.md §事故 4）——工具链级，另案。
4. **M5-4 收口交接**：M5-4 = VALIDATION + **瘦身手术第二次触发**
   （SPEC 正本：strip 集按 SPEC 重算非空才动手；M5 立项时已从「M4 后
   立即」改挂 M5-4）。M5-2 phase 全部三 plan（01/02）+ G4/G6 证据在本批
   收口后移交 M5-4 汇总。
