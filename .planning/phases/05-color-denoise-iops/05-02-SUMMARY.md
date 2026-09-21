# 05-02-SUMMARY.md — colorbalancergb 执行总结（T1–T5 + T6 GUI）

> 全套绿 + 本文件落盘后收工；决策见 `05-02-DECISIONS.md`（D1–D8）。

## 任务表（6 项；每任务独立提交；HOLD 插曲见 D8）

| 任务 | 内容 | commit |
|---|---|---|
| T1 | CPU commit 推导 + MSL kernel + D65-native 矩阵 + float64 参考 + 注册/prewarm/seed-disabled + gen_fixtures cb 小节（6 XMP + Python 参考链）；YrgGamut.matMul 升 public | `a14ff2c` feat(colorbalancergb) |
| T2 | （与 T1 同提交）Registry 注册 + prewarm + seed DISABLED + V50 41.5 槽位 | `a14ff2c`（同上） |
| T3 | golden 6 case × 8 fixture + 恒等门 + 方向断言 + dt 采纳 + split parity 门 + manifest cb 节 | `e80fc17` test(colorbalancergb) |
| HOLD | 代理链路劣化挂起（23:25）→ 恢复后续跑（01:24 起） | `eebb407` docs: HOLD（PROGRESS 行） |
| T4 | 面板 4 区 + hue 圆盘 + 26 a11y + 31 locale 键 + PanelWiring +3 + seed 断言 | `1725972` feat(colorbalancergb) |
| T5 | 轨 B 回归（disabled 零增量论证）+ PERF 复用既有门 + invert 测试真值修复 + GUI 走查 | `1725972`（同 T4 提交；T5 无独立代码增量）+ 本文件 |
| T6 | GUI 交互复验（FINDINGS 登记 + 5 证据截图） | 证据随本提交（`.work/gui-acceptance/2026-09-22-cb-*.png`） |

## 证据指针

- T1：params v5 132B 版式逐字段对齐；`commitParams`（colorbalancergb.c:621-647 直译，
  input_matrix = RGB→XYZ(D50)→CAT16(D65)→LMS2006 合成——D65-native 落账 D2）；
  float64 参考链（Swift 测试 target + Python gen_fixtures 双边互证）。
- T2：Registry 注册行 + prewarm + seed disabled（D1：默认参数非像素恒等——
  gamut_check 默认 gamut=1.0 对宽色域输入裁剪；D11 同款处置）；
  `V50OrderTests.testColorBalanceRGBSlotOrderConstraint`（41.5 介于 colorbalance 41.0
  与 rgbcurve 之间）。
- T3：轨 A parity——DTUCS 5 case 严格 1e-5/2.5e-5@99% + 包络 1e-4/5e-4；
  JzAzBz 遗留 1 case 1e-3/2.5e-5@99% + 包络 1e-2/5e-4（PQ 逆 ^6.277 float32 放大）；
  in-gamut 全默认恒等门（flat_0ev/flat_-4ev/ramp_8ev/gray_staircase，依据写入注释）；
  hue/vibrance 方向探针；commit pins；kernel 隔离探针；
  dt 三证据（6/6 XMP adoption MATCH + `params v. 5: version ok params ok` +
  平场 PFM probe BROKEN 记录——colisa 先例，数值参考三向交叉锁定）；
  manifest cb 节（blob hash + 48 reference sha256）。
- T4：`ColorBalanceRGBPanelView`（421 行）——4 区（Global/Shadows/Midtones/Highlights，
  ToneEqual house Section 样式；"折叠" deferred，见 D3）各含 hue 圆盘（Canvas
  点击/拖动设 H+C，常规色轮红 0°，120pt，280pt Inspector 安全）+ Y 滑块；
  Chroma/Saturation/Brilliance 三组四滑块；Master（Vibrance/Contrast/Hue-shift/
  Fulcrums + saturation 公式 Picker）；D-H1 trio 全控件（live update → 松手恰 1
  commit），离散控件（Picker/重置）走 applyDiscrete；26 a11y identifier +
  `history_colorbalancergb` + 30 `panel_cb_*`（zh/en）。
  `PanelWiringTests` +3：`testColorBalanceRGBPanelDragCommitsOnce`（Y 拖动=恰 1
  commit + 自动启用 GUI-7 + 归零恢复 paramsHash）、
  `testColorBalanceRGBHueDiscCommitsOnce`（H+C 离散对=1 commit）、
  `testColorBalanceRGBPanelDispatch`（面板分发）；seed 含 colorbalancergb
  disabled 断言。
- T5：
  - 轨 B：零代码增量——colorbalancergb 以 disabled seed 进默认链；
    `PixelPipe.processRec:666` 对 disabled piece 直接跳过（不读 uniforms、不占
    levelHash——`levelHash` 只 fold enabled hash），故既有 GeometryGolden 轨 B
    双判据（`testTrackBNeutralityWithCropFlipInserted` +
    `testTrackBCrossConsistencyLinearWithCropFlipInserted`）已覆盖本模块：
    终轮全套中 14 trackB-ish 全绿即回归证据。显式插入 cb 的轨 B 腿未加——
    disabled 件的插入 == 不插入（同一 guard），加了也是恒真测试（防空转纪律）。
  - PERF：零代码增量——colorbalancergb 以 disabled 进 `editingDefaultInstances`，
    既有 `PreviewChainPerfTests`（Debug 病态 bound 120ms）+ `ToneEqualPerfTests`
    全链帧计时已把本模块计入分母；终轮两门全绿即增量证据。
    单件 1-2ms@2560 预期未独立测量（disabled 件零 dispatch——测了也是 0；
    启用态单件计时留待 05-08 签核的启用态 PERF 轮）。
  - invert 真值修复（T5 必修）：`testMatricesInvert` 原断言 mo·mi≈I——
    前提错误（L2X 腿在 MSL 内，不在 uniforms；mo·mi = xyzD65toLMS2006 ≠ I，
    首值 0.643 对 1.0 九连红实证）。修复为真中性往返 mo·L2X·mi≈I
    （L2X = YrgGamut.lms2006toXYZD65；实测 max dev 3.7e-9，门 1e-6）；
    `matrixOut` 注释同步更正（bisect 2.9156606 回归证据保留）。
    另修面板两处 API 误用（`Section(isExpanded:)` 无此签名 → 素 Section；
    `Shading.style` 无 `.displayP3` 成员 → `Color(.displayP3,…)` 构造）。
- T6 GUI：FINDINGS.md `05-02 colorbalancergb GUI 走查` 节 + 5 证据截图。
  Debug 产物 + DSC00012.ARW：cb 行选中→面板展开（4 区 + hue 圆盘 + Master）；
  圈 toggle 关→开视口块 meanAbsDiff 0.037（阈下，D1 中性预期）；
  全局 Y 0→+0.3 视口块 meanAbsDiff 73.387 / frac>8 0.6676（强跟随），
  全窗 meanRGB [24.1,32.5,30.3]→[58.9,61.7,61.9]；
  sidecar history 恰 2 条（切换模块 + 色彩平衡 RGB）；⌘Z 撤销后 vs 启用中性
  逐位一致（0.0）；Inspector ≈31% 窗宽视口主导保持，无裁剪溢出。
  通道注记：AX set 只走 live 预览分支（不进 liveEdited），commit 通路由单测
  trio 证明；CGEvent 真拖拽仍 BLOCKED（输入监控权限，L011）。

## 防空转自检声明

| 套件 | compared |
|---|---|
| ColorBalanceRGBParityTests（9：parity 2 + 恒等门 + 方向 2 + commit pins + invert + 注册 + kernel 隔离） | parity 双循环全像素（6 case × 8 fixture × RGB；compared>0 断言）；恒等门双腿（ref 字节 + live 管）全像素；kernel 隔离 4×4×3 逐分量 |
| PanelWiringTests（36：既有 33 + cb 3） | drag 6 ticks → history==1；hue-disc 6 ticks → (H,C)==末 tick；dispatch 非 nil；paramsHash 复原逐位 |
| GeometryGolden 轨 B（14 trackB-ish 全绿） | 中性块 3×3 采样 + level 容差 + 全平面 maxDiff<0.004 |
| V50Order（cb 槽位约束） | order 数值三断言（41.5 + 两侧序关系） |
| GUI 走查 | 视口块均值差 + frac>8 + 全窗 meanRGB + history 条数 + 撤销逐位一致（全 >0 比较） |

无比较循环的"绿"恒真空转——本轮零容忍；invert 恒真（mo·mi≠I 前提错）已修复为真往返。

## 验收标准核对（plan §验收标准 7 条）

- [x] 轨 A parity：6 case × 8 fixture——DTUCS 双门 + JzAzBz 宽门全绿；compared>0；
  in-gamut 全默认恒等门绿（fixture 依据入注释）
- [x] dt 三证据齐（DB hex 采纳 + params ok + 平场 probe BROKEN 诚实记录）；
  manifest cb 节落账（blob + 48 sha256）
- [x] 模块 41.5 注册 + V50 断言；seed disabled 论证入 DECISIONS D1；
  mask_display 不移植头注（模块 + kernel 双处）
- [x] 面板：4 区 + hue 圆盘 + Picker；PanelWiring 3 用例（拖动=1 commit）；
  catalog zh/en 31 键；a11y 26 全量
- [x] GUI 走查：真实 RAW 渲染变化量化（73.387）+ 启用中性阈下（0.037）+
  撤销逐位一致 + 布局红线不破（FINDINGS 登记 + 5 截图）
- [x] 轨 B 双判据不回归（14 全绿；disabled 零增量论证——显式腿恒真故不加）；
  PERF 既有双门全绿（单件启用态计时留 05-08）
- [x] 全 suite 绿（0 fail）；ROI 头注钉死（恒等 + tileHalo=0 + 禁 dscIn×scale——
  模块:297-306，点态无分块）

## 全量回归

终轮全 suite：**445 passed / 0 failed / 3 skipped**（xcresult 计 448 cases；
T3 落盘时基线 435 → 本轮 +10 cases：PanelWiring cb 3 + Parity 9 − 方法/用例口径差 2；
skip 3 既有合规：2 ColorChecker ARW + 1 GPS）。
MDB_MAP_FULL 杂音本轮复现（既有，不影响结果）。

## 新教训候选

- L022（已立，见 DECISIONS D8 + LESSONS 追加）：uniforms 对是"半边契约"——
  L2X 类腿在 MSL 内时 parity 测试必须钉全往返 mo·L2X·mi≈I，禁止钉 mo·mi。
- 面板 `instance` 快照滞后（T6 附带发现）：AX live 预览不刷新面板 `value` 源——
  待 Phase 6 面板刷新审计复核（不入 LESSONS，本 SUMMARY 登记即可）。
- Hue 圆盘 AX role = AXUnknown（拖拽只能走 CGEvent）——与 overlay 手柄同类，
  L011 路径统一解决（不另立 lesson）。
