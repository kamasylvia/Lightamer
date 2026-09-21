# 05-02-DECISIONS.md — colorbalancergb 决策记录（D1–D8）

> T1–T3 决策由 omp 执行轮落账；T4–T5 + HOLD（D8）由续跑轮补记。

## D1: seed DISABLED——默认参数非像素恒等（2026-09-21，T2）

- 论证：默认参数下 gamut legs（`gamut_check_Yrg` + UCS/JzAzBz soft-clip）对
  宽色域输入（saturated/hue_sweep/delta fixtures）产生位移——不存在零参数恒等式；
  恒等只经 disabled piece 成立（highpass/soften D11 同处置，04-05-T3）。
- in-gamut 内容（flat_0ev/flat_-4ev/ramp_8ev/gray_staircase，Rec2020-contained
  构造）默认输出 == 输入（cb_default refs 与输入字节相等——生成时验证），
  恒等门只钉此四 fixture（注释写依据，防 vacuous 门）。

## D2: D65-native 矩阵——CAT16/Bradford 往返恒等相消（2026-09-21，T1）

- dt 工作 profile 是 D50-ICC 基（matrix_in = RGB→XYZ D50，再 CAT16 到 D65）；
  Lightamer working space 是 linear Rec2020 D65-native，故 CAT/Bradford 往返
  恒等相消——模块必须用 D65-native 矩阵（`ColorBalanceRGBMatrices`），不得复用
  `YrgGamut.matrixIn/Out`（filmic V5 的 CAT 链；复用注入 ~2x 中性偏移——
  C-harness cb_verify 实证：D65-native 下 out==in 至 1e-7，CAT 链下 ~2x 偏移）。
- 中腿在 Filmlight GRADING RGB（dt :719-726，无管线矩阵）——三腿结构
  （pipeline-forward / grading-middle / pipeline-out）是承重结构。
- 共享常量仍取 YrgGamut（CAT16/LMS2006/Kirk grading/Yrg 白点——同源数，不同链）。

## D3: hue 圆盘交互参数（2026-09-21，T4）

- 圆盘显示常规色轮（红 0°，dt GUI 约定——ANGLE_SHIFT −30° 在 commit 折叠，
  故盘 0° == params H 0°；`conventionalDegToYrgRad` 钉此换算）。
  半径 0..1 映射 C 0..1（Y=1 grading 的 dt Ych chroma）。
- 拖动 = D-H1 trio（live ticks → 松手恰 ONE commit）；Y 滑块走 LightamerSlider
  同 trio；离散控件（Picker/重置/双击圆盘）= applyDiscrete 一 commit。
- "折叠" deferred：4 区用 ToneEqual house 素 Section（全展开）；
  DisclosureGroup 需每区 @State——验收只要求 4 区 + 圆盘 + Picker（本决策备案）。
- 120pt 圆盘 + 全宽滑块；280pt Inspector 约束内（GUI 走查无溢出实证）。

## D4: saturation 公式双轨门（2026-09-21，T3）

- 默认 DTUCS 路径-carry 质量门（严格 1e-5/2.5e-5@99% + 包络 1e-4/5e-4）；
  JzAzBz 遗留 1 case 宽门（1e-3/2.5e-5@99% + 包络 1e-2/5e-4）——
  PQ 逆 ^6.277 陡幂把 float32 噪声放大到 LMS 上 ~5e-5 abs（实测 ~4e-5），
  加 neutrals 上 AzBz 相消；结构断裂预修实测 0.01+，门留 20–1000x 裕度。

## D5: dt 证据三件套 + probe BROKEN 诚实记录（2026-09-21，T3）

- L017 路由：本机构建 dt-cli float 导出对变化内容空间损坏，且 colorbalancergb
  CPU 腿对 EXR 输入 misbehave（flat_0ev 默认参数导出 garbage：首像素 ~1e20，
  中心 ~1e-9；同输入 exposure 对照精确）——故轨 A 参考为合成（gen_fixtures
  float64 评估 dt 文档化 process :579-944）。
- dt 侧证据 = XMP 采纳（6/6 `params v. 5: version ok params ok` + 库 DB
  op_params hex MATCH）；数值参考三向交叉锁定（Python float64 vs Swift
  Commit.derive vs C-harness dt 真实 CPU 代码独立编译——neutrals 上 out==in
  至 1e-7）。均匀平场 PFM probe 记 BROKEN（colisa-probe-unavailable 先例）。

## D6: mask_display 不移植（2026-09-21，T1/T2）

- `mask_display` 棋盘分支是 Phase 6 蒙版域调试可视化——不移植；
  模块头 + kernel 头双处注记（RGB.w 从输入恢复）。

## D7: 轨 B / PERF 零增量论证（2026-09-22，T5）

- colorbalancergb 以 disabled seed 进默认链；`PixelPipe.processRec:666`
  对 disabled piece 直通（不读 uniforms），`levelHash` 只 fold enabled hash——
  故既有轨 B 双判据 + PERF 双门已把本模块计入（分母侧），终轮全绿即回归证据。
- 显式插入 cb 的轨 B 腿 == 不插入（同一 guard）——加了是恒真测试，防空转纪律禁加。
- 启用态单件 1-2ms@2560 计时留待 05-08（disabled 件零 dispatch，单测无意义）。

## D8: 代理链路故障全程记录 + L022（2026-09-21 23:25 → 2026-09-22 01:24）

- HOLD 起因：JMS 机场链路全面劣化（google via proxy 83s，6 探测/1h 全超时），
  omp 模型 API 不可靠（直连 403 RegionError）。已穷尽：节点轮换×3、订阅刷新
  （直连抓取成功但节点集不变）、omp 重启×4。05-02 挂起（T5 在制品 617 行完好），
  过夜自动监测每 20 分钟探测、恢复即自动续跑（`eebb407` 落 PROGRESS HOLD 行）。
- 恢复：续跑 prompt 称"代理链路已恢复"；本轮单发探测实证——
  proxy 经 127.0.0.1:10809 谷歌 3.29s，直连 2.35s/200（2026-09-22 02:04）。
  恢复路径 = 保活巡检既有 20 分钟探测 + 本轮指令直调（双保险成立）。
- T5 附带修（HOLD 后首跑全套红 2 项）：
  1. `testMatricesInvert` 前提错（L022 立账）：mo·mi≈I 恒假——L2X 腿在 MSL 内
     （`cb_lms_to_xyz` = YrgGamut.lms2006toXYZD65），uniforms 只 carry 半边；
     mo·mi = xyzD65toLMS2006 ≠ I（首值 0.643 vs 1.0 九连红）。修复为真往返
     mo·L2X·mi≈I（max dev 3.7e-9，门 1e-6）。教训：uniforms 对是"半边契约"时，
     测试必须钉全往返，禁止钉半边——此为 L022（已入 LESSONS）。
  2. `ToneEqualPerfTests.testPreviewFullChainFrameTime` 暖中位 203ms > 120ms
     病态 bound——全链条目数从 8（03-05 立门时）涨到 20 seed（含本模块注册，
     虽 disabled 仍参与 box 物化 + 全套并行负载噪声）；单跑隔离复验
     PASS（本轮 `-only-testing` 双测全绿），终轮全套回归 PASS（负载回落）。
     bound 本身未动（05-08 签核复核 PERF-5 时重估）。
  3. 面板 API 误用两处（首轮全套构建红 3 项）：`Section(isExpanded:)` 无此签名、
     `Shading.style(.displayP3)` 无此成员——均按 ToneEqual house 模式修正。
