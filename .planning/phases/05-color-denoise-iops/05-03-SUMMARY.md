# 05-03-SUMMARY.md — channelmixerrgb + channelmixer legacy + colorcontrast 执行总结

> 决策见 `05-03-DECISIONS.md`（D1–D10）。修复轮（F1–F6，见末节）后收工。

## 任务表（6 项；每任务独立提交）

| 任务 | 内容 | commit |
|---|---|---|
| read_first | RESEARCH §5.1/5.6/§1.1 + CONTEXT D1/D5 + dt 源码（channelmixerrgb.c/commit/_loop_switch/illuminants.h/chromatic_adaptation.h/channelmixer.c/colorcontrast.c + channelmixer.cl/extended.cl）+ 05-02 CB 范本 + V50/Registry/面板模式 | —（无代码） |
| T1 | illuminants/CAT 泛化：ChannelMixerCommon（xy↔XYZ/CCT 双模型/全 illuminant 族/广义 Bradford-CAT16-XYZ adapt/gamut/luma_chroma；camera 反解未移植见 F4）+ 5 CPU 单测 | `2773bcc` feat(channelmixerrgb) |
| T2 | channelmixerrgb 模块（params v3 160B verbatim + commit derive + MSL 单 kernel 5 路）+ 注册/prewarm/seed-DISABLED + V50 28.5 + commit pins（5 路非单位门/illuminant hash 链/grey/gamut） | `e3dd050` feat(channelmixerrgb) |
| T3 | legacy channelmixer（params v2 88B + 4 模式 derive + MSL kernel + rgb2hsl CPU 镜）+ colorcontrast（Lab a/b slope+offset + unbound 双档，LabMath fuse）+ 注册/prewarm/seed-ENABLED-neutral ×2 + V50 39.0/56.0 + CPU 测试 | `00bf530` feat(mixer-contrast) |
| T4 | gen_fixtures（cm_derive/cm_apply 5 路 + legacy 4 模式 + contrast Lab 链 + 12 XMP + 48 EXR refs generator）+ parity（cmr 6×4 + legacy 3×4 + contrast 3×4，<1e-5）+ 矩阵交叉（float32-fair）+ illuminant 缓存链 + tie-break 回归 + manifest 05-03 节 | `1346b88` test(mixer-contrast) |
| T5 | 面板 ×3（D-H1 trio + discrete + a11y + 色卡隐藏注记/弃用注记）+ providers + 86 catalog 键 + PanelWiring +4 + 轨 B/PERF + GUI 走查 + SUMMARY/DECISIONS | `cf915a9` feat(panels-05-03) + 本轮 |

## 证据指针

- T1：D65/D50/BB6500/D5500 手算向量（Python 独立值入注释）；Bradford/CAT16
  恒等往返 1e-9（源=目标白）；XYZ⇄LMS 往返 5e-4（dt 4 位小数常量界，T4 交叉补钉）；
  既有 LabRoundTrip/YrgGamut 零回归（全套绿）。camera 反解未移植（F4-b，运行时 behaviour）。
- T2：params v3 160B 逐字段对齐（6×4 + 6 bool + 5 enum + x/y/temp/gamut/clip/version）；
  `derive`（commit :3047-3150 + _loop_switch :777-810逐路径矩阵对，D65-native）；
  MSL 单 kernel 5 运行时路径（channelmixer.cl unswitch 同构）；路径覆盖门
  （每 adaptation 非单位矩阵对）；V50 28.5（colorin 28.0 < cmr < nlmeans 29.0）。
- T3：legacy commit（:499-560 verbatim，gray fold + 模式选择）+ 模式相关钳制
  （v1 clipf vs v2 fmax；首积 vs 全点 HSL 钳制）；contrast Lab 双档；
  默认 RGB-identity / contrast-identity（CPU 测试钉）。
- T4：轨 A parity——cmr 6 case（CAT16-D/linear-A/full-BB/XYZ-F/RGB-LED+grey/
  CAT16-custom，v1/v2/v3 全覆盖）× 4 fixture；legacy 3（RGB 置换/gray/HSL-v1）
  × 4；contrast 3（含 bound ±128 钳制腿）× 4——全 <1e-5（strict 1e-5/2.5e-5@99%
  + envelope 1e-4/5e-4）；矩阵交叉（cmr_default CAT16：rgbToLMS 5e-7/mix 1e-6/
  illum 1e-6/p 1e-6，float32-fair）；illuminant/temp/xy→paramsHash 链；
  28.5 tie-break（latest-wins + multiPriority + 槽位序）。
  dt 三证据 ×3：12 XMP blob（160B/88B/20B）+ DB hex（逐字节一致）+ params ok
  （`.work/plans/05-03/ADOPTION.md` 实跑 12/12 落账；此前 52B 口径为假声明，F1–F3 修后为真）。
  color-checker 零移植：grep 仅两处头注（NOT PORTED 声明）。
- T5：`ChannelMixerRGBPanelView`（3×3 mix + normalize×6 + sat/light/grey 组 +
  illuminant 区全族 Picker + adaptation/gamut/clip/version + camera 回落注记 +
  noprofile 注记）；`ChannelMixerPanelView`（输出 Picker + 3 滑块 + 算法 Picker +
  弃用注记）；`ColorContrastPanelView`（4 滑块 + unbound）。
  `PanelWiringTests` +4：三面板拖动=恰 1 commit + dispatch 三非 nil；seed 断言
  （cmr DISABLED 在 seed；legacy/contrast ENABLED-neutral）。
  catalog 86 键（panel_cmr_×62/panel_cm_×15/panel_cc_×6/history_×3，zh/en）。
  a11y：panel identifier ×3 + slider/toggle/picker/notes 全量。
- 轨 B / PERF：见下节。

## 防空转自检声明

| 套件 | compared |
|---|---|
| ChannelMixerCommonTests（5） | 手算向量逐值 + 全族分支 + 往返 + 三版 luma 有限性（camera 反解未移植，F4-b） |
| ChannelMixerRGBCommitTests（5） | 5 路非单位矩阵对（每路实算）；hash 链双腿 |
| ChannelMixerColorContrastTests（9） | 4 模式 derive 选择 + 全模式有限性（3 探针）+ HSL 往返 + contrast 恒等/钳制 |
| ChannelMixerRGBParityTests（3：parity + 交叉 + 缓存链） | parity 全像素双循环（6×4×RGB；compared>0）；交叉全矩阵有限 + 4 钉点 |
| ChannelMixerColorContrastParityTests（2） | 全像素双循环（3×4 + 3×4；compared>0）+ ramp≠flat 非空转门（RGB/gray 腿） |
| SidecarTieBreakTests（3） | 真实 HistoryStack commit → effectiveInstances |
| PanelWiringTests（40：既有 36 + 本轮 4） | drag 6 ticks → history==1 ×3；dispatch 非 nil ×3 |
| V50Order（+1 方法：8 个中仅 cmr 槽位方法为本轮新增；legacy+contrast 槽位断言在既有 CPU 测试内） | cmr 28.5 order 数值 + 两侧序关系 |
| GUI 走查 | 视口量化 + history 条数 + 布局红线（FINDINGS 登记，见下） |

## 验收标准核对（plan §验收标准 8 条）

- [x] channelmixerrgb：轨 A 6×4 <1e-5 + 5 矩阵路径覆盖（非常规 illuminant：A/F4/BB/LED/custom 全在内）+ 矩阵 float64 交叉（float32-fair 门）+ illuminant 变更缓存失效断言
- [x] channelmixer legacy：3 case parity + 弃用头注；colorcontrast：3 case + unbound 双档
- [x] 28.5/39.0/56.0 三槽位 V50 断言；28.5 共槽 tie-break 回归测试绿
- [x] color-checker 子树零移植（grep 证：仅头注）+ params 位保留（camera/detect enum + resolver nil + 面板注记）+ 面板注记
- [x] dt 三证据 ×3（12 XMP blob + DB hex逐字节 + params ok；`.work/plans/05-03/ADOPTION.md` 实跑 12/12；manifest 落账）
- [x] 面板 ×3 + PanelWiring +4 + catalog 86 + a11y + GUI 走查登记
- [x] 轨 B 双判据不回归；PERF 记录落 `.work/plans/05-03/perf.md`
- [x] 全 suite 绿（0 fail）；ROI 头注钉死 ×3（恒等 + tileHalo=0 + 禁 dscIn×scale）

## T5 证据（面板/GUI/轨 B/PERF）

- T5 面板/GUI：
  - 右列 23→26 行（删 sidecar 冷载实证：色彩校准/通道混合/色彩对比中文行；
    `fix(inspector)` 前裸 opName 回落已修）。
  - 色彩对比面板展开 + a 陡度 1→3 视口块 meanAbsDiff **3.575**/frac>8 **0.1435**；
    撤销逐位一致 **0.0000**；布局红线不破（FINDINGS.md `05-03 mixer trio` 节 +
    4 证据截图）。
  - AX set 只走 live 预览分支（05-02 同口径）；commit 通路由 PanelWiring +4 证明；
    CGEvent 真拖拽仍 BLOCKED（L011）。
- 轨 B：零代码增量——channelmixerrgb 以 disabled seed 进默认链（processRec 直通，
  05-02 D7 同构）；legacy + contrast 以 enabled-neutral 进链（identity 矩阵 ⇒
  缓存中性，exposure/colisa 同处置）。既有 GeometryGolden 轨 B 双判据终轮全绿即
  回归证据（显式插入三件的轨 B 腿 == 不插入/恒等腿，防空转纪律禁加）。
- PERF：`.work/plans/05-03/perf.md`（3 趟单 pass +6ms 量级；seed 政策；启用态计时留 05-08）。

## 全量回归

终轮全 suite：**480 passed / 0 failed / 3 skipped**（基线 445 → 本轮 +35 cases：
Common 5 + Commit 5 + CPU 9 + CMR parity 3 + CC parity 2 + tiebreak 3 +
PanelWiring 4 + V50 1 方法（8 方法中 7 既有；legacy+contrast 槽位断言在 CPU 测试内）= 32 新增 + GeometryGolden 轨 B 计入既有（+1 口径差来自
V50OrderTests 方法计数）；skip 3 既有合规：2 ColorChecker ARW + 1 GPS）。
（注：此前「V50 +3」为口径误——V50OrderTests 方法本轮只新增 1 个，legacy/contrast 槽位由 ChannelMixerColorContrastTests.testLegacyAndContrastSlots 覆盖。）
轨 B 双判据（neutrality + cross-consistency）终轮全绿；MDB_MAP_FULL 杂音复现（02-04 遗留项，同族无影响）。

## 新教训候选

- T4 cm_rgb_swap 误配 HSL 行非零 → v2 下 HSL mix 隐式启用 → 全黑输出（mode 断言
  抓出；F2 修后交换值归位 idx3-5，gray 权重归位 idx6+恒等行；旧 manifest hash 恒黑铁证——cm_rgb_swap/cm_gray_luma 旧 refs 与 canonical flat 逐字节同 hash 6fc281172bc40bcf）
- Swift Float params vs Python double：交叉门必须 float32-fair（本轮 10× 观测），
  公式相等由端到端 parity 钉（D6）。
- Tuist 重生成后 scheme testables 漂移（LightamerTests 掉出 scheme）→
  regenerate 后必查 `BlueprintName` 双 testable（本轮 T5 实测）。
- xcodebuild 卡插件扫描（UNITEK 卷 Xcode，plugin scan 读慢）→ 构建超时先看
  `sample` 调用栈定性（本轮：DVTPlugIn scan read() 阻塞；warm cache 后通过）。

## 修复轮 F1–F6（验收 FAIL 回注，2026-09-22）

> cmr 数学/kernel/面板/tie-break 已验收全过零改动（diff 自查见收尾 commit）。
> FAIL 集中在 legacy golden 证据链与文档诚实性；每项独立提交。

| 项 | 内容 | commit |
|---|---|---|
| F1 | legacy blob 52B→88B（`<12fi`→`<21fi`，CHANNEL_SIZE=7 @ channelmixer.c:55-91；v2=3×7+algorithm）：`[:4]` 截断修 + regen 3 XMP + manifest 行 + 模块头注 | `9ba7ae2` |
| F2 | case 语义：swap 值→idx3-5（RGB 输出行）/gray 改 RGB 恒等+权重（真实 luma）/删 `_gray` shim；regen refs；parity 12/12 maxRel≤1.2e-7；新增 ramp≠flat 非空转门 | `115f526` |
| F3 | dt-cli 采纳实跑 12/12（loader params v.N ok + DB hex 逐字节）：日志 + hex + `.work/plans/05-03/ADOPTION.md` | `11bf868` |
| F4 | camera 反解选 b)删死代码（`wbCoeffsToIlluminantXY`+`bradfordAdaptTM` 零调用；dt 路径需 live RAW+管线 WB 通道，纯函数接不上）；D4 修订记录 | `bc1e9bb` |
| F5/F6 | 本提交：TODO 挂账 + GOAL-STATE + SUMMARY 勘误（D1–D10/catalog 86/dt 措辞/V50 口径/防空转表） | 本轮 |

F3 方法：`darktable-cli flat_0ev.exr <case>.xmp`（fresh DB + `-d params`），
`successfully loaded module <op> from history` + `params v. 2/3 ok` + DB hex==XMP
逐字节（legacy 176 hex / contrast 40 hex / cmr 320 hex；`blendop v.1 WRONG` 为既有杂音）。
此前「dt 三证据」为假声明（52B 实跑必拒收）——修后为真证据，措辞已改写。
