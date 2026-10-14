# M6-4-02 DECISIONS — 执行期裁决与偏离登记（2026-10-15 夜间全自动授权批）

> 正本链：plan（修订版，HEAD `984e0256` 面）→ 七 OQ 生效值（CONTEXT，全 A）
> → 本文件（执行偏差 + 版本化条款 + KD-3 预留的两个申报槽位）。
> 晨审可推翻；推翻项回注修复批重走。执行批 commit 链 =
> `86a0b292`（T1）→ `87efa887`（T2）→ `444f4047`（T3）→ `fbbcf449`（T4）
> → `74a4709d`（KD-4 行 2 数值门测试）。

## D-01 羽化负腿公式换锚：logit gain（KD-3 的 LightCraft 原文核对槽位）

plan KD-3 草案式 `applyFeatherNegative = 1 − blur(1−x)`（形态学腐蚀的高斯近似）
**在线性高斯下代数恒等于 blur(x)**：核和为 1 ⇒ `blur(1−x) = 1 − blur(x)` ⇒
`1 − blur(1−x) = blur(x)`——与正腿完全同义，数学上不可能「收缩」，直接矛盾于
T2⑤「负值收缩」判据与 LightCraft UI 语义「below 0 a crisper border」。

**KD-3 自带的裁决条款生效**（「执行期先读本地 LightCraft checkout 核对符号
语义，有出入以 LightCraft 原文为准 + DECISIONS 申报」）。LightCraft 原文
（`crates/pipeline/src/masks.rs` MaskShape::Object 臂 + `docs/ai-masks.md`
Edge 节）实测：

- `e > 0`：Gaussian blur，sigma = `e · 0.02 · frame_px`——与我方正腿 GPU
  featherRadius 缝同式（plan 与原文一致，零偏差）。
- `e < 0`：**logit gain**，`gain = 1 − 7e`（e∈[−1,0) ⇒ gain ∈ (1,8]，至多
  8× 陡化）施加于分割 logits——「steeper transition (up to 8× the logits)」，
  **非腐蚀、非补 blur**。

**落定**：负腿 = 平面域 logit-gain 重映射 `x' = x^g/(x^g+(1−x)^g)`，g = 1 −
7·(percent/100)。性质：0→0、1→1、**0.5 轮廓逐点不动**、10-90 过渡带宽 ≈ g
倍收窄——「crisper border 而不移边界」的诚实平面等价（LightCraft 在 logits
上做增益；我方无 logits，从平面反解同族映射）。AIMaskFeatherTests ⑤ 以
朴素 Double 参照双写 + 收缩单调 + 0.5 不动点三面钉死。文件名/函数名
（`applyFeatherNegative`）与缝结构（CPU 负腿 + bake 半径恒 0 + 双羽化互斥）
照 plan 钉死形不变。

## D-02 patch 调度缝落位：commit 缝捕获与调度（host 零触兑现）

plan KD-1「App 调度：AIMaskEditing 会话内 additive——末次种子/精修交互后
1s debounce」未钉交互挂点；KD-5/S7 钉死 `SegmentEditingOverlayHost 零触`。
若在 host 的 tap/confirm 点调度则必须破零触。**落定**：调度与 livePlane
捕获全部落 `AIMaskEditing.commitRasterMask`（「the ONE seam every AI
generation path funnels through」）的 .segment 成功臂——**生成提交即交互
终点**（我方 07-3 模型：点累积 + confirm 才重推理；patch 存在于 confirm
之后，故「末次交互」= 末次提交），`patchRebake: true`（patch 自重烘）双门
跳过捕获与重调度 = 无自环。连发 confirm 经 debounce 取消-重排合并为单次
pass。host 零触兑现；点级交互（confirm 前加/减点）不触发 patch——其后必
有 confirm 重生成，对陈旧基面 patch 会被丢弃，语义上无意义。

## D-03 labelComposite 参数化类型面：CVReadOnlyPixelBuffer（E2 实现注记）

plan E2 写「输入 = 标签图 `CVPixelBuffer` + IndexSet」；swiftinterface 实测
`InstanceMaskObservation.allInstancesMask.pixelBuffer` 的类型是
`CVReadOnlyPixelBuffer`（macOS 26+ 新只读缓冲面，非裸 `CVPixelBuffer`）。
helper 形参按真实类型钉 `CVReadOnlyPixelBuffer`，`withUnsafeBuffer` 内锁读
（原 07-1 体逐字保留）；测试侧经 `CVReadOnlyPixelBuffer(unsafeBuffer:)`
桥合成 fixture（注意该 init 是 `sending`——桥前必须 unlock，region-isolation
编译门实测）。E2 的「零 Observation 依赖零 entitlement」语义完整兑现。

## D-04 `kCVPixelFormatType_OneComponent32Float` == 'L00f' 别名（存量事实申报）

探针实测（/tmp 即弃，2026-10-15）：`kCVPixelFormatType_OneComponent32Float`
== `0x4C303066`（'L00f'）——与 `maskPlane(from:)` 的 half-float 臂（07-1 探针
定标的 generateScaledMask 输出读法）**同值**，Swift switch 首匹配胜出 ⇒
32F 整读臂为**不可达死码**（存量面，本批零改）。测试 ⑤ 弃 32F fixture 改
走 OneComponent8 臂（v/255）。半浮点读法对 Vision 真实输出正确性的既有
证据（07-1 探针）不受扰。

## D-05 person 检测复用 AIInstanceCatalog 载体（零新类型）

两请求族 observe 同一 `InstanceMaskObservation`，提取腿又经 E2 参数化后
observation-type-agnostic ⇒ `detectPersonInstances` 直返既有
`AIInstanceCatalog`（instances/observation/handler 三元），**不新增
AIPersonInstanceCatalog**。收益：`InstancePickerOverlay`（含 live 预览的
`subjectMask(from:selection:)` 读腿，同为 observation 无关）零改复用，
toolbar 只加第二 popover 宿主（S7 @State 形）与 `.person` 提交源。files_modified
无新类型文件的自洽兑现。

## D-06 无人物场分类腿的 fixture 选型：black（探针申报）

真模型腿探针（/tmp 即弃直编进程，四场实跑）：**black → nil observation**、
**white → 1 实例、gray128 → 1 实例（幻觉）**、noise → nil。测试 ④ 用 black
场钉「零观察 → typed noSubject」；灰/白场的幻觉实例为本 OS 构建模型行为
实况，登记供 GUI 轮（M-3 的「无人像」判定须用真无人像照片而非素场）。

**person 标签编号域**：合成 label-buffer 侧已钉「复合键只认 buffer 自带
标签、不对编号起点/背景语义做假设」（foreign-domain fixture）；**真 person
观察的编号域实测**（起点/背景语义 vs layer A 有无出入）需真多人照片 ⇒
随 GUI 轮 M-2 申报（KD-2 预留的探针申报项，未关）。默认腿恒标签合成，
不因探针出入换 API（plan 钉死）。

## D-07 layer B ROI 产物分辨率：未实测（申报义务挂 GUI 轮）

`segmentPatch` 的 ROI 产物分辨率保持运行时事实（assets notReady，本批无
真推理）。组装面**分辨率无关**已由测试钉死：composer 对任意分辨率 patch
平面 bilinear 到 rect 像素尺寸（T1⑤ 显式喂 2× 分辨率 fixture）。实测申报
随 GUI 轮 M-1 补录（KD-1 申报义务 → 待供件清单）。

## D-08 KD-4 行 2 数值判据落断言（方法计数保持带内）

「0.6× 过渡宽」+「≤1px 缝错位」两判据按 checker 关注点 6 落为测试断言
字面：**并入 T1⑤**（composer 质量法的双分辨率解析圆 fixture——全帧腿
softness 2px vs 2× patch 腿 1px 输出域），**不加新方法**——SC 分账恒
9+6+5+4 = 24 ∈ 21..25，对账链机械闭合（`74a4709d`）。

## D-09 羽化 wire 契约：percent≠0 时会话值权威（参数面申报）

`commitRasterMask` 的 `featherRadius` 显式参数仅在会话 `featherPercent ==
0` 时穿透（今日全部调用点缺省 0，零实炸）；`percent > 0` ⇒ bake 半径 =
sigma（显式参数被忽略）；`percent < 0` ⇒ CPU 负腿 + bake 半径强制 0
（显式参数被忽略）。双羽化在数据流上不可能：两臂互斥 + 0 门 + 唯一非零
源（toolbar 滑杆 → 会话值）。全仓 `featherRadius:` 非零调用点 grep 申报 =
`AIMaskEditing.swift:197`（bakeRadius 穿线，正腿唯一）+
`MaskCombiner.swift:628`（parametric post-chain 存量面，非 AI 路径）。

## D-10 T5 Manual-Only 降级行使 + MANIFEST gitignored（commit 空转申报）

执行会话无 GUI 自动化工具面 + R4 两前置不可达（layer B 资产需引导下载、
人物判据需真实多人照片——D-06 探针证合成场不可用）⇒ 行使 plan 风险节
降级条款：MANIFEST（`.work/gui-acceptance/m6-4/MANIFEST.md`）落现场记录
（含人物模型真推理 7s 实跑证据）+ 四 Manual-Only 行配方，交验收批/人工。
**该目录被 .gitignore:79 忽略（历史各批 MANIFEST 同为本地证据不入仓）**
⇒ plan T5 的 commit（`docs(m6-4): record the ai mask gui acceptance
manifest`）空转——文件在盘，无 git 面。非静默放行：M-1..M-4 入待复验。

## D-11 环境事件两笔（非产物缺陷）

①AIWorkerClientTests 首轮全量跑挂起于 `testTimeoutKillFoldsToWorkerCrashedAndRespawns`
（worker respawn 时序，30 分钟零推进）——杀自跑进程后单类复跑 9/0/0（7s）
+ 全套复跑 814/4/0 通过：一次性挂起，非稳定缺陷；挂起日志 =
`/tmp/la-direct-tests-App.log` 首轮尾部（即弃）。②会话 shell 死代理 env
撞 SPM re-resolve → build 以 `env -u …` 旁路——runbook 入 LESSONS L080。

## D-12 翻账推迟申报编号（01 批 D-15 同款程序项）

本批零翻账：plan files_modified 所列 AGENTS.md（M6-4 架构增量节面 B 段）/
ROADMAP（M6-4 行 ✅）/ REQUIREMENTS（M6INT-03 终态注记）/ GOAL-STATE
（续接点）/ TODO（M6-4 条目）五文档未动——闭环批统一翻账，素材 =
本文件 D-01..D-12 + SUMMARY §spike 判定表 + 「实际收口 TOTAL」节。

## 待供件清单

| # | 项 | 供件方 | 验证方法 |
|---|---|---|---|
| 1 | GUI 轮 M-1..M-4（patch 真图/多人实例/无人像/羽化三档） | 验收批（omp computer-use）或人工 | MANIFEST 逐行判定 |
| 2 | layer B ROI 产物分辨率实测值 | M-1 走查时 | bundle 探针/log 分辨率读数 → 补录本文件 D-07 |
| 3 | person 标签编号域实测（起点/背景语义） | M-2 走查时 | 多人照 label map 读数 → 补录 D-06 |
| 4 | 全套 `--all` 终验（预期 3841/24/0 中心，带 3838..3842） | orchestrator 批准轮 | test-direct.sh --all + VALIDATION 对表 |

## 建议翻账点（闭环批统一做，本批未动——推迟申报编号 = D-12）

- AGENTS.md：M6-4 架构增量节（面 B 段：patch 组装/羽化分腿缝/spike 判据表/
  Vision pin 纪律/livePlane 姿态）——本文件为素材正本。
- ROADMAP：M6-4 行 ✅（两 plan 收口）。
- REQUIREMENTS：M6INT-03 兑现终态注记（含 Describe 不可达收口 + V2 挂账）。
- GOAL-STATE：续接点（phase 收口态 + 全套终验待办）。
- TODO：M6-4 条目 + LESSONS 已入 L080。
