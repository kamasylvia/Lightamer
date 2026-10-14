# M6-4-02 ACCEPTANCE — AI 分割蒙版原生集成 spike（面 B 全量批）双重验收记录

> **PASS / 0 error + 0 minor open + 4 观察项**（第一路 zcode 独立验收，
> 2026-10-15 夜；不 push。4 观察项全部为登记级，无一阻断；见 §六。
> omp 二次验收按 `dual_acceptance=true` **串行**补位（严禁并发），其结论
> 追加于本文件 §七。

## 结论头（第一路 zcode 独立验收）

- **判定：PASS**。执行链 `86a0b292..cc1cb04f`（T1-T4 + T6 数值门 + T7 docs
  六 commit）逐 commit 范围核对与申报一致；全套 `--all` 独立复跑
  **`TOTAL|3841/24/0|2096s`，exit 0，零 MEMFAIL，零 crash**——与 SUMMARY
  申报预期中心（3841/24/0，带 3838..3842）**逐位一致**；AC1-8 全项
  Delivered；**D-01 换锚深审 ACCEPT**（论证见 §三）；D-02..D-12 偏差逐项
  裁决全准（§五）；T5 Manual-Only 降级合规（§六.1）。
- **验收方式**：不轻信执行方报告——五正本（PLAN/CONTEXT/CHECKER/SUMMARY/
  DECISIONS）全文亲读 + 六 commit 逐 hunk diff 亲核 + 四新测试文件 24 法
  逐条对表 + LightCraft `masks.rs`/`ai-masks.md` 原文亲读（D-01 独立复核）
  + 07-1 D-07-1-T2-4 双损坏正本亲读 + 红线机检电池十项亲跑 + zh-audit
  独立复跑 + 全套 7 bundle 独立 build+run（增量 build-for-testing 后
  `caffeinate -dis Scripts/test-direct.sh --all`；运行中 RSS 监视，峰值
  IOP 7294MB / IOPParity 6829MB / Export 5554MB，8G 门内零 MEMFAIL）。

## 一、全套独立复跑对账（本路亲跑，非转引）

| bundle | 本路实测 | 申报/预期 | 基线（01 收口后） | 漂移 |
|---|---|---|---|---|
| IOP | 686/1/0（peak 7294MB，437s） | — | 686/1/0 | 0 |
| IOPParity | 460/3/0（peak 6829MB，769s） | — | 460/3/0 | 0 |
| **Layers** | **494/4/0**（peak 1174MB，158s） | 494/4/0 | 474/4/0 | **+20 恰合**（9+6+5） |
| Library | 729/4/0（peak 621MB，77s） | — | 729/4/0 | 0（01 修复批后值） |
| Sessions | 280/4/0（peak 1249MB，70s） | — | 280/4/0 | 0 |
| Export | 378/4/0（peak 5554MB，206s） | — | 378/4/0 | 0 |
| **App** | **814/4/0**（peak 2832MB，379s） | 814/4/0 | 810/4/0 | **+4 恰合** |
| **TOTAL** | **3841/24/0 / 2096s** | 3841/24/0 | 3817/24/0 | **+24/0/0 精确** |

- 基线复算闭合：686+460+474+729+280+378+810 = 3817（七段亲加，= 01 修复批
  后 S8 重算基线）；本批 +24（LAYERS 三新文件 9+6+5 + APP 一新文件 4，
  `func test` 计数亲点）∈ 计划带 21..25；**3841 = 预期带 3838..3842 中心**。
- skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL skip 机械一致。
- 退出码 0；零 MEMFAIL；零 crash 签名；全程 caffeinate 包裹；测试宿主
  parentage = 本路脚本树（M2-7-3 纪律，无外来进程清理）。
- IOP 7294MB / IOPParity 6829MB = 8G 门的 89%/83%（在案贴线族，±3% 方差
  注记口径内，MEMFAIL 机检未触发）。

## 二、AC 逐条核验表

| AC | 内容 | 判定 | 本路证据（亲核，非转引） |
|---|---|---|---|
| AC1 | patch 三件（Planner/segmentPatch/Composer）+ 判据 2 可机检项 + debounce 单调度 | **Delivered** | `AIPatchAssembly.swift` 亲读：Planner 三 skip 门（空掩码/ bbox>60% 全帧〔Float64 精度比较〕/ min 侧 <32px）+ pad 25% 短边 + 图界 clamp；Composer 界内 patch 精确值 + 界外逐字节恒等 + 接缝线性 ramp（带宽 5% 短边 clamp 2..16）+ ≤4 FIFO；`segmentPatch` = **恰一个委托表达式**（恒走 segmentSubject，`regionOfInterest` 传 patch 归一 rect，quality 钉 `.accurate`，零第二条装配——AIMaskFeatherTests ① 的 S6' 结构面断言 request.regionOfInterest 逐分量 1e-9）；KD-4 行 2 双数值门（0.6× 过渡宽 + 0.5 轮廓 ≤1px）以断言字面落 T1⑤（`74a4709d`，双分辨率解析圆 fixture）；AIMaskPatchFlowTests ① 五连发 → 恰 1 run 且末者胜 |
| AC2 | 羽化 ±100 全量程（正腿 GPU 缝复用 + 负腿 CPU + 双羽化钉死）+ 0 恒等双保险 + golden 表 + 零新 kernel | **Delivered** | `AIMaskFeather.swift` 亲读：sigma 映射 = \|p\|/100×0.02×longEdge（LightCraft 同式）；负腿 logit-gain 重映射（§三）；正腿 CPU 零代码（文件结构自证）；`resolveFeather` 三臂（正 → (plane, σ) / 负 → (CPU 面, 0) / 0 → (plane, fallback)）落 `commitRasterMask` .segment 臂；wire 字节级双写钉（AIMaskPatchFlowTests ②：正腿文件 == bake(σ) 手工对照、负腿文件 == bake(CPU 面, 0) 手工对照、0 == plain path 字节恒等）；golden 表手算值亲复核（0.2/10/20/0.8/40/80 全对）；`.metal` 全域 diff 0（§四） |
| AC3 | 人物实例入口（ai_mask_* 键族 + 主进程直调 + 提取恒标签合成 + 并集 + typed noSubject + 合成 fixture） | **Delivered** | `AIMaskSource.person`（"ai-person-" 前缀族，与 segment 重入门判别 disjoint——③ 路由负测钉死）；`detectPersonInstances`/`personInstanceMasks` 主进程直调 + 零观察 → typed noSubject；提取腿 = `labelComposite`（CVReadOnlyPixelBuffer 参数化，07-1 体逐字保留）；`generateScaledMask` 新增 diff 恰 2 处注释命中、:197 为 07-1 存量升级缝（grep 亲跑）；`unionSelection` 纯缝（all/subset/空 → noSubject/未知 → invalidInput）+ maxPlane 并集；四合成 label-buffer fixture（单/多/未知标签域/零覆盖）零 Vision 执行零 entitlement；真模型 black 场 → noSubject（④，直启宿主实跑绿） |
| AC4 | scribble 不激活（typed 拒负测原样绿 + 零代码面） | **Delivered** | 本批 `.swift` 新增 diff scribble 命中 = **0**（SUMMARY 文档文字除外）；`recordSeed` 的 `.scribble` typed 拒缝原样（diff 只增 patch 重置四行）；既有负测随 Layers 494/4/0 全绿 |
| AC5 | Describe 收口（SUMMARY §spike 五行表 + 原生不可达 + V2 挂账 + REQUIREMENTS 注记） | **Delivered**（注记项随闭环批） | SUMMARY §spike 五行判定表 + 「达标即收」结案语 + V2 挂账五项在案；RESEARCH B2 实测引用亲读（Vision 零文本分割 API + CLIP 图像级无像素掩码）；REQUIREMENTS 终态注记 = **D-12 申报的翻账推迟**（闭环批统一，01 批 D-15 同款先例）——VALIDATION 落签前必须随翻账补齐（登记为待复验项，非本批缺陷） |
| AC6 | spike 结论落档（GUI MANIFEST + VALIDATION 落签） | **Delivered**（VALIDATION 待签） | MANIFEST 亲读：Manual-Only 降级 + 现场记录（人物模型 7s 四场实跑：black/noise → 0、white/gray128 → 幻觉 1）+ M-1..M-4 配方（步骤 + accessibilityIdentifier + 判定标准逐行）——plan 风险节授权条款行使合规（§六.1）；VALIDATION = C 档第 3 停面，待双重验收后落签（程序位，非缺陷） |
| AC7 | 零回归门（.metal/sidecar/MCP/V50Order/封存面/既有族零编辑/typed 纪律/UserDefaults/dependencies） | **Delivered** | 机检电池十项亲跑全绿（§四）；diff 文件全集 = 16 文件 ⊆ plan files_modified（无清单外文件）；既有测试文件零编辑（diff 仅 4 新文件）；新增路径 typed 扫描零 all-ones 兜底（命中全为注释与测试 fixture） |
| AC8 | SC 数字门（LAYERS +20 / APP +4 / 全套带） | **Delivered** | 本路实测 +20/+4/3841/24/0 逐位闭合（§一）；D-08 方法计数不胀机制亲核（双数值门并入 T1⑤，恒 9+6+5+4） |

## 三、D-01 换锚深审（本验收最重项）——裁决：**ACCEPT**

### 1. 数学亲推（草案式退化证明，独立推导）

设 blur 为归一化核线性算子（核和 1 ⇒ 常数保持 L(1)=1；Deriche IIR + 边界
延拓与边界重归一化两类实现皆满足）。则逐点有：

```
L(1−x) = L(1) − L(x) = 1 − L(x)   （线性）
⇒ 1 − L(1−x) = 1 − (1 − L(x)) = L(x)
```

即草案式 `1 − blur(1−x)` 与正腿 `blur(x)` **逐点恒等**——高斯模糊保持 0.5
等值线不动、只对称展宽过渡带，数学上不可能产生「收缩」；直接矛盾于 T2⑤
「负值收缩」判据与 LightCraft「below 0 a crisper border」UI 语义。DECISIONS
D-01 的退化论证**成立**（且比我方原 plan 措辞更强：不需非线性原语论证，
线性恒等已足够判死）。

### 2. LightCraft 原文亲读（KD-3 指定权威）

`crates/pipeline/src/masks.rs` MaskShape::Object 臂（:246-255）亲读：

```rust
let e = (*edge / 100.0).clamp(-1.0, 1.0) as f32;
let gain = if e < 0.0 { 1.0 - 7.0 * e } else { 1.0 };
sample_seg(seg.as_ref(), detail, gain, frame, w, h, &mut out);
if e > 0.0 { smooth_plane(&mut out, e * 0.02 * frame_px(frame, w)); }
```

`docs/ai-masks.md` Edge 节：「below 0 a crisper border, above 0 a feathered
one (up to 2 % of the long edge, so previews and exports match)」。与 D-01
申报**逐字吻合**：e>0 = Gaussian（sigma = e·0.02·frame_px，与我方正腿 GPU
featherRadius 缝同式）；e<0 = **logit gain（1−7e，至多 8×）施加于分割
logits**——非腐蚀、非补 blur。

### 3. 落定式性质核（平面域 logit gain）

`x' = x^g/(x^g+(1−x)^g)`，g = 1 − 7·(percent/100)：

- **恒等式**：x' = σ(g·logit(x))（logit 域增益的精确平面等价，非近似）——
  与 LightCraft「对 logits 施加 gain」同族同构。
- **0.5 不动**：0.5^g/(0.5^g+0.5^g) = 0.5（任意 g）；代码另有显式短路。
  0→0、1→1 端点精确。
- **单调**：logit 严格增 + sigmoid 严格增 ⇒ 复合严格增（g>0）。
- **g>1 收窄过渡**：logit 斜率 ×g ⇒ logistic 型剖面的 10-90 宽恰缩 g 倍
  （一般剖面近似）——「crisper border 而不移边界」的诚实语义。
- **映射一致性**：percent=−100 ⇒ g=8 = LightCraft gain 上限；g = 1−7e 与
  masks.rs `gain = 1.0 − 7.0*e` 逐式同（e = percent/100 clamp 后同值）。

### 4. 测试钉面（三判据）

- **负腿真收缩**：AIMaskFeatherTests ⑤(b) 10-90 过渡宽随 \|percent\| 单调
  收窄（−25→−50→−100 三档严格递减 + 总体方向断言）；⑤(a) 朴素 Double
  pow 参照逐像素双写（1e-5）；⑤(c) 0.5 轮廓逐点不动（1e-6）。
- **0 字节恒等**：③ percent≥0 短路「同 floats 恒等 + byteIdentity 恒等」
  （防御面）；wire 层 0 == plain path 文件字节恒等（PatchFlow ②）+ 既有
  bake 缺省 0 字节恒等回归（07-1 在册，RasterMaskStore 头注）= 双保险。
- **正负互斥**：PatchFlow ② wire 字节级——正腿文件 == bake(radius=σ) 手工
  对照、负腿文件 == bake(CPU 面, radius=0) 手工对照、两腿文件互异；
  `resolveFeather` 三臂结构 + 全仓非零 `featherRadius:` 调用点 grep 申报
  亲核（仅 AIMaskEditing:197 bakeRadius 穿线 + MaskCombiner:628 parametric
  存量面）——双羽化在数据流上不可达。

**裁决：ACCEPT**——换锚依据（plan KD-3 自带「以 LightCraft 原文为准 +
DECISIONS 申报」条款）程序合法，数学论证正确，落定式与原文语义同构，
测试三判据全钉。文件名/函数名/缝结构照 plan 钉死形不变（申报与实现一致）。

## 四、红线机检电池（本路亲跑）

1. `.metal` 全域 diff（`git diff 984e0256..HEAD -- '*.metal'`）= 0 ✓
2. `Project.swift` diff = 恰 4 行测试文件登记（LAYERS 3 + APP 1，显式清单
   无 glob）+ dependencies 块零 diff（零新 SPM）✓
3. 冻结/封存面：`RasterMaskStore.swift`（正腿复用面，Sources/Sidecar/）/
   `MaskCombiner.swift` / `LightamerSidecar.swift` / V50Order /
   NodeOwnershipCatalog / `SegmentEditingOverlayHost.swift`（host 零触）全部
   diff 0 ✓
4. MCP 快照族（PhotoProjection/McpServerController）diff 零命中 ✓
5. `grep -rn "\.runModal(" App/Sources` = 0；本批代码新增 runModal = 0
   （唯一命中 = SUMMARY 文档文字）✓
6. 本批新增 `String.LocalizationValue("` 插值键形态 = 0 ✓
7. UserDefaults 代码新增 = 0（唯一命中 = SUMMARY 文字）✓
8. xcstrings：diff `-` 行 0（纯插入）、`+` 86 行、恰 5 键
   （ai_mask_feather_label / ai_mask_feather_reset / ai_mask_patch_refining /
   ai_mask_person_instance / ai_mask_person_none，全 ai_mask_* 族）✓
9. `zh-audit --check` 独立复跑 **PASS**（1682 source / 1923 catalog /
   zh complete / {en, zh}）——与 SUMMARY 申报逐值一致 ✓
10. `generateScaledMask` 新增调用点 = 0（2 处 `+` 命中皆为 E2 禁用注记
    注释；:197 = 07-1 存量已登记升级缝，未动）✓；scribble 新增（.swift）
    = 0 ✓

## 五、D-02..D-12 偏差逐项裁决

| # | 项 | 裁决 | 依据（本路亲核） |
|---|---|---|---|
| D-02 | patch 调度缝 = commit 缝捕获 + patchRebake 双门自环 | **准** | `commitRasterMask` 尾部 `if source == .segment, !patchRebake` 双门（livePlane 捕获 + 重调度同门跳过）——patch 自重烘不重入，代码亲证零自环；host 零触兑现（diff 0）；交互终点语义（我方 07-3 confirm 才重推理模型）与 D-02 论证自洽。附带独立分析：会话拆后残留 debounce task 经 `hasSeed` 守卫惰化（读的是 editingState 当前 session，非捕获旧对象），安全 |
| D-03 | labelComposite 形参 = CVReadOnlyPixelBuffer | **准** | swiftinterface 事实申报；helper + 测试桥（`init(unsafeBuffer:)`，unlock-before-bridge 的 sending 注记）亲读一致；E2「零 Observation 依赖零 entitlement」语义完整兑现（fixture 自造 CVPixelBuffer） |
| D-04 | 32F/'L00f' 常量别名 → 32F 臂不可达 | **准** | Apple 常量 kCVPixelFormatType_OneComponent32Float = 'L00f' = 0x4C303066 亲证；maskPlane switch 中 `case 0x4C303066`（half 臂）位于 32F 臂之前，Swift 首匹配胜出 ⇒ 32F 臂死码；07-1 存量面零改，D-04 仅申报，测试 ⑤ 改走 OneComponent8 臂合理 |
| D-05 | person 检测复用 AIInstanceCatalog（零新类型） | **准** | `detectPersonInstances` 直返 AIInstanceCatalog 亲证；InstancePickerOverlay 零改复用（toolbar 只加第二 popover 宿主 + `.person` 提交源）；files_modified 无新类型文件自洽 |
| D-06 | black 场分类腿 fixture + 幻觉探针申报 | **准** | 测试 ④ 用 black 场（探针四场实跑录 MANIFEST：white/gray128 幻觉 1 实例）；M-3「无人像须真照片」判定注记在 MANIFEST——诚实申报非掩盖 |
| D-07 | layer B ROI 分辨率未实测 | **准** | assets notReady 无真推理可跑（RESEARCH B2 + MANIFEST 现场）；组装面分辨率无关已由 T1⑤ 2× 分辨率 fixture 钉死；实测申报随 GUI M-1（待供件清单在册）——申报义务挂账合规 |
| D-08 | KD-4 行 2 数值门并入 T1⑤（SC 恒 24） | **准** | `74a4709d` diff 仅 AIPatchAssemblyTests 单文件 ±78 行，双判据断言字面在 ⑤ 内；方法计数 9 不变；SC 分账机械闭合 |
| D-09 | 羽化 wire 契约 + 非零调用点 grep 申报 | **准** | resolveFeather 三臂 + `featherRadius` 显式参数仅 percent==0 穿透亲读；非零点 = AIMaskEditing:197（bakeRadius 穿线）+ MaskCombiner:628（parametric 存量）行号亲证；四既有调用点缺省 0 零漂移亲读 |
| D-10 | T5 Manual-Only 降级 + MANIFEST gitignored | **准** | plan 风险节授权条款（资产不可达 = MANIFEST 记录现场 + 不静默放行）行使合规；`.gitignore:79` 忽略亲证（commit 空转 = 非静默，D-10 显式申报）；待复验项入 SUMMARY §待复验 |
| D-11 | 环境事件两笔 | **准** | 死代理 L080 已入 LESSONS（本路 build 亦按 `env -u` 旁路亲历同坑）；worker respawn 一次性挂起有单类复跑 + 全套复跑双证，非稳定缺陷 |
| D-12 | 翻账推迟编号 | **准** | AGENTS/ROADMAP/REQUIREMENTS/GOAL-STATE/TODO 五文档本批 diff = 0 亲证；素材指针（DECISIONS + SUMMARY §spike + TOTAL 节）齐备；01 批 D-15 同款程序项 |

## 六、T5 Manual-Only 降级合规性 + 独立发现

### 6.1 T5 降级合规（plan 授权条款对照）

- plan 风险节：「资产不可达 = MANIFEST 记录现场 + VALIDATION 标注待复验项
  （不静默放行）」——MANIFEST 现场记录（模型 7s 四场实跑 + assetStatus
  notReady + entitlement 域注记）+ SUMMARY 待复验项 4 条，逐条对上。
- T5 验收标准：「MANIFEST 逐项闭环；layer B 资产未就绪 = 记录 assetStatus
  现场 + 按失败处置（不静默）——07-3 先例形」——合规。
- M-1..M-4 配方完备性：步骤含 accessibilityIdentifier（ai.mask.tap /
  ai.mask.download / ai.mask.patch.refining / ai.mask.person / ai.picker.* /
  ai.mask.feather.*，与 MaskToolbarView 源码逐一在册亲对）+ 判定标准行
  （M-1 边缘细化观察 + 同 maskID；M-2 实例数 ≥2 + 逐实例非全零 + 并集；
  M-3 typed toast 零兜底；M-4 三档 + 0 字节一致）——omp 二次验收可直接消费。

### 6.2 独立发现（4 观察项，全部登记级不阻断）

- **O-1**：`runPatchRefine` 在飞期间用户再 confirm（同 session 加精修点）
  → 新 commit 捕获新 livePlane 并调度新 pass；在飞旧 pass 完成时以其**旧
  base** 的组合面重烘一次（patch rect 系按旧基面规划）——同主体域内收敛
  （新 pass 1s 后以新基面重规划），无状态腐蚀，仅瞬态观感可能。V2 若做
  「patch pass 互斥锁」可消；登记即可。
- **O-2**：`sigma()` 对负 percent 对称映射（golden 表含负行）——wire 上负
  percent 恒不入 GPU 半径（resolveFeather 三臂 + PatchFlow ② 钉死），映射
  对称性纯为表完备；文档层面无歧义风险，备注供未来读者。
- **O-3**：羽化滑杆为连续 Slider，featherPercent 可取任意中间 float——
  sigma/g 对域内任意 float 数学良定义（clamp 兜底），无功能影响；如需
  step 量化属 UX 打磨项。
- **O-4**：person 单实例直烘无确认门（picker 仅 ≥2 实例弹）——若边缘图
  单幻觉实例将直烘；D-06 探针已证素场幻觉形态，M-2/M-3 GUI 轮覆盖真图
  判定；产品语义上与 layer A 单实例直烘先例同形，非本批缺陷。

## 七、待复验项（VALIDATION 落签前置；omp 二次验收/人工）

1. GUI 轮 M-1..M-4（MANIFEST 配方逐行判定；layer B 资产引导下载为前置）。
2. D-07（layer B ROI 产物分辨率实测）/ D-06（person 标签编号域实测）随
   M-1/M-2 补录 DECISIONS。
3. 闭环批翻账五文档（AGENTS 面 B 段 / ROADMAP ✅ / REQUIREMENTS M6INT-03
   终态注记〔AC5 挂点〕/ GOAL-STATE 续接点 / TODO）——D-12 申报位。
4. omp 二次验收结论追加于本节之后（严禁与第一路并发）。
