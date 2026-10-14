# M6-4-02 ACCEPTANCE-2ND — AI 分割蒙版原生集成 spike 第二路独立验收记录

> **PASS / 0 error + 0 minor open + 5 独立观察 + 1 升格建议**
> （第二路 zcode 独立验收，零共享上下文，替代 omp 制度位，2026-10-15 夜；
> 不 push。与第一路结论一致，无实质分歧；一处内存生命周期缺口升格建议
> 见 §五 N-1，其余全登记级。）

## 结论头（第二路 zcode 独立验收）

- **判定：PASS**。执行链 `86a0b292..cc1cb04f`（T1-T4 + T6 数值门 + T7 docs，
  六 commit）逐 commit 范围独立亲核与申报一致；全套 `--all` **本路独立
  build + 亲跑**（L080 `env -u` 死代理旁路自历同坑）：
  **`TOTAL|3841/24/0|2097s`，exit 0，`OK (direct launch)`，零 MEMFAIL，
  零 crash 签名**——与第一路亲跑（3841/24/0 / 2096s）及 SUMMARY 申报预期
  中心**逐位一致**；对账基线 3817 + 24 = 3841 机械闭合，带 3838..3842 中心。
- **验收方式**：五正本（PLAN/CONTEXT/CHECKER/SUMMARY/DECISIONS）+ 第一路
  ACCEPTANCE 全文独立亲读；六 commit 逐 hunk diff 亲核；四新测试文件 24 法
  逐条对表；**D-01 独立数学亲推**（不接受转述）+ LightCraft `masks.rs`
  :246-255 / `ai-masks.md` Edge 节原文亲读；**D-03/D-04 探针级亲证**
  （swiftinterface 亲 grep + FourCC 常量 swift 探针实跑）；Describe 不可达
  以 swiftinterface 独立 grep 复核（非转引 RESEARCH）；红线机检电池八项
  亲跑；zh-audit 独立复跑 PASS。

## 一、全套独立复跑对账（本路亲跑，非转引）

| bundle | 本路实测 | 第一路 | 基线（01 修批后） | 漂移 |
|---|---|---|---|---|
| IOP | 686/1/0（peak 7121MB，433s） | 686/1/0（7294MB） | 686/1/0 | 0 |
| IOPParity | 460/3/0（peak 7009MB，761s） | 460/3/0（6829MB） | 460/3/0 | 0 |
| **Layers** | **494/4/0**（peak 1164MB，164s） | 494/4/0 | 474/4/0 | **+20 恰合**（9+6+5 亲点） |
| Library | 729/4/0（peak 622MB，78s） | 729/4/0 | 729/4/0 | 0 |
| Sessions | 280/4/0（peak 1627MB，70s） | 280/4/0 | 280/4/0 | 0 |
| Export | 378/4/0（peak 6213MB，206s） | 378/4/0 | 378/4/0 | 0 |
| **App** | **814/4/0**（peak 2832MB，385s） | 814/4/0 | 810/4/0 | **+4 恰合** |
| **TOTAL** | **3841/24/0 / 2097s** | 3841/24/0 / 2096s | 3817/24/0 | **+24/0/0 精确** |

- 对账亲算：686+460+494+729+280+378+814 = **3841**；skip 段和
  1+3+4+4+4+4+4 = **24** 机械一致；24 新法逐文件亲点
  （AIPatch 9 / Feather 6 / Person 5 / PatchFlow 4）。
- 两路独立跑 TOTAL 同值（2097s vs 2096s）；peakRSS 峰值族 IOP 7121 vs
  7294 / IOPParity 7009 vs 6829——离散 ≤2.6%，±3% 方差注记口径内；8G 门
  全过（最高 7121MB = 87%），MEMFAIL 机检零触发。
- 全程 `caffeinate -dis` 包裹；测试宿主 parentage = 本路脚本树，无外来
  进程清理；构建走 `env -u` 五键旁路（本路 shell 亲历 L080 死代理 env，
  旁路有效）。

## 二、五面独立审计（自选切入，非第一路路径复述）

### 2.1 面 1 — D-01 独立数学复核：**ACCEPT（独立推导，结论同第一路）**

- **草案式退化亲推**：设 blur 为核和 1 的线性算子 L（L(1)=1）。则
  `L(1−x) = L·1 − L·x = 1 − L(x)`（线性）⇒ `1 − L(1−x) = L(x)` 逐点恒等。
  即 plan 草案 `1 − blur(1−x)` 与正腿 `blur(x)` **恒同**——高斯模糊保 0.5
  等值线不动、只对称展宽，数学上不可能「收缩」，直接矛盾 T2⑤ 判据与
  LightCraft「below 0 a crisper border」。**不需要非线性原语论证，线性恒等
  已判死**——D-01 换锚的程序依据（plan KD-3 自带「以 LightCraft 原文为准 +
  DECISIONS 申报」条款）与数学依据双双成立。
- **LightCraft 原文亲读**（本路亲开文件，非转引）：`crates/pipeline/src/
  masks.rs` :249-254 `let e = (*edge / 100.0).clamp(-1.0, 1.0)`；
  `gain = if e < 0.0 { 1.0 - 7.0 * e } else { 1.0 }`（施加于 logits，经
  sample_seg）；`if e > 0.0 { smooth_plane(&mut out, e * 0.02 * frame_px) }`。
  `docs/ai-masks.md` Edge/Detail 节语义同。与落定式 `g = 1 − 7·(percent/100)`
  **逐式同构**（e = percent/100 clamp 后同值；percent −100 ⇒ g=8 = 原文
  8× 上限）。
- **落定式性质亲核**：`x' = x^g/(x^g+(1−x)^g) = σ(g·logit x)`（精确恒等，
  非近似）；0.5 不动点任意 g 成立（测试另加显式短路）；g>1 时 0.5 处斜率
  恰乘 g（logit 斜率 ×g ⇒ logistic 型 10-90 宽 ≈ g 倍收窄）——「crisper
  border 而不移边界」语义诚实。
- **g<0 域行为（派单指定问句）**：**wire 面不可能送负 g**。`applyFeatherNegative`
  首行 `guard percent < 0 else { return plane }`——percent≥0（含 NaN：
  `NaN < 0` 为 false）一律短路恒等；只有 percent<0 才计算
  `e = clamp/100 ∈ [−1,0) ⇒ g ∈ (1,8]`。负 g 需 e > 1/7 即 percent > +14.3，
  而正 percent 在 guard 处已返回。**typed 防护 = 结构性 guard，负域不可达**；
  即便假设可达，`powf` 对 x∈(0,1) 任意实 g 仍有定义（a,b>0），无 NaN 面。
  另查平面值域：composer/bilinear/resample 全为凸组合，值域恒 [0,1]，
  `sharpen` 的 x≤0/x≥1 端点短路覆盖浮点边缘。

### 2.2 面 2 — livePlane 内存/生命周期三场景审计

- **会话拆**：`setSegmentActive(false)` → 整体换新 `SegmentSession`
  （LayerEditingState :262-263）⇒ 旧 livePlane 随旧对象释放；`armSegmentSession`
  同形；`recordSeed` 显式清 `livePlane/patches/patchState` 并 cancel+nil
  debounce task（:768-772）；新生成覆写（AIMaskEditing :234）。四释放点
  三点实wired。
- **崩溃恢复**：livePlane/patches/featherPercent 全 @MainActor 内存 UI 态，
  sidecar/params 零触（本批 `LightamerSidecar.swift` diff=0 亲证）——崩溃
  即随进程消亡，无恢复面、无残留。合规。
- **图切换**：**未 wired（独立发现，见 §五 N-1）**——`EditorState.load`
  与 app-root `layerEditingState` 均不触会话；声明释放点「切层/切图」
  （plan 风险节 + SUMMARY §livePlane + SegmentSession 头注）与实现存在
  缺口：100MP ≈400MB 平面跨图驻留直至模式退出/重进，且 debounce 1s 窗
  内切图可产出「旧平面 × 新图输入」的混合 patch 烘焙。窗口窄（1s）、
  无 sidecar 腐蚀、可 undo，故登记不阻断，但**建议升格为修复项**（V2
  或下批小修）。
- **资源监控条款衔接**：SUMMARY §livePlane 申报 ≈400MB 量级 + AGENTS GUI
  app >3G 触发线同域注记在案；patches ≤4 份 ROI 小平面 + compose 中间面
  一次性——申报量级与代码实况相符（本路核）。全套跑时无 GUI 实例并存，
  运行门 8G 由脚本机检兜底。

### 2.3 面 3 — 异步竞态走查（debounce / runPatchRefine / 自环门）

- **自环双门亲证**：`commitRasterMask` 尾部 `if source == .segment,
  !patchRebake`（:233）——patch pass 自烘走 `patchRebake: true`，捕获与
  重调度同门跳过，**零自环**（代码亲读）。
- **debounce 合并**：每 schedule cancel 前任务（schedulePatchRefine :278），
  末者胜；PatchFlow ① 5 连发（60ms 注入钟）→ 恰 1 run 且 tag=5 亲核。
- **teardown 后残留 task**：task 闭包捕 `editingState`（非 session 对象），
  fire 时读**当前** session——会话已拆 ⇒ hasSeed=false 早退（:300）安全
  （与第一路 D-02 附注一致，本路独立复核成立）。
- **在飞 + 再 confirm（O-1 复核）**：patch pass 只置 `patchState`，不置
  `isGenerating` ⇒ confirm 按钮在飞期仍可用，O-1 场景**可达**。新 confirm
  的 schedule cancel 掉 `patchDebounceTask`（此刻正承载在飞 pass 的 Task），
  但 Swift 取消是协作式——路径中无 `Task.isCancelled` 检查、Vision perform
  非协作点 ⇒ 旧 pass 大概率完整跑完（旧 base 重烘一次，O-1 描述准确），
  新 schedule 随后再跑一轮；同主体域内收敛，无状态腐蚀。**定级恰当
  （登记级）**。
- **补充独立分析**：brush 绘制与 patch 窗互斥——切画笔工具即
  `setTool` ⇒ `segmentActive=false` ⇒ 会话整体换新 ⇒ 残留 task 被新会话
  hasSeed=false 惰化；patch 覆写用户笔迹的场景不可达。confirm 后追加精修
  点（不再 confirm）会被下一轮 patch pass 消费——与 plan「末次交互」语义
  相容，非缺陷。

### 2.4 面 4 — 羽化双腿全量程 + 一致性容差

- **sigma 映射亲核**（golden 表手算复核）：|1|/100×0.02×1000=0.2、
  50→10、100→20、4000→0.8/40/80——测试表 10 行全对；端点 clamp（±150/−250）
  亲核；0 = CPU 短路恒等 + bake 缺省 0 字节恒等（AIMaskGeometryTests
  :170-193 回归在册亲读）= **双保险成立**；单调性 + 长边归一（竖横同物理
  半径）亲核。±100 端点行为：+100 ⇒ σ=2% 长边（GPU Deriche）、−100 ⇒
  g=8（logit 收窄）、0 ⇒ 两面全零。
- **两腿一致性容差申报（派单问句）**：**两腿语义相反（正=展宽/负=收窄），
  同 σ 输出本就互异——PatchFlow ② 显式断言 `negativeBytes !=
  manualPositiveBytes`（互异原语）**。故不存在「同 σ 两腿一致」的申报
  义务；真正的容差面分属：正腿 GPU Deriche = 07-1 存量原语零改（本批
  `MaskCombiner.swift`/`RasterMaskStore.swift` diff=0 亲证，其近似容差
  归 07-1 在册）；负腿 CPU logit-gain = 逐像素朴素 Double 参照双写
  1e-5（点态映射，无核近似）。wire 字节级：正腿文件 == bake(σ) 手工对照、
  负腿 == bake(CPU 面, 0) 手工对照——双写钉死亲核。
- **resolveFeather 三臂**（:256-267）：正 → (plane, σ)；负 → (CPU 面, 0)；
  0 → (plane, fallback=0)。fallback 仅 percent==0 穿透且四既有调用点全
  缺省 0——非零源唯一性（:197 bakeRadius + MaskCombiner:628 parametric
  存量）grep 亲跑与 D-09 申报一致。

### 2.5 面 5 — KD-4 五行判据逐行独立核

| # | 判据 | 本路独立核 | 判定 |
|---|---|---|---|
| 1 | 点击精修回归绿 | 既有 AIMask 六套件零编辑（diff 文件全集 = 16 文件、Tests/ 仅 4 新文件亲核）+ Layers/App 全绿亲跑 | 达标 |
| 2 | 0.6× / ≤1px / ≤4 帽 / skip 门 + debounce | 双数值门**断言字面**在 T1⑤（`74a4709d`：`<= 0.6 * fullRise.width` + `x05 == center.x−radius accuracy: 1.0`）——fixture = 双分辨率解析圆（全帧 softness 2px vs patch 腿 2× 分辨率 1px 输出域），非「目测合理」；帽 FIFO（⑧）+ 三 skip 门（②③④）+ debounce（PatchFlow ①）全钉；GUI 轨 = M-1 Manual-Only 待复验 | 机检轨达标 |
| 3 | 羽化 golden + 0 恒等 + 单调 + 负参照 + wire 穿线 | §2.4 全项亲核；wire 双写字节级对照在 PatchFlow ② | 达标 |
| 4 | 人物实例单测 + GUI 轮 | 5 法亲读：typed 组装（revision1 钉 + validated pin）+ 四 label-buffer fixture（单/多/未知域/零覆盖 → invalidMask）+ 并集核心（空选中 = noSubject、未知 = invalidInput）+ **真模型 black 场 noSubject**（直启宿主实跑）+ 平面格式面；GUI 轨 M-2/M-3 待复验 | 单测轨达标 |
| 5 | Describe 收口 | **本路 swiftinterface 独立 grep**（arm64e-apple-macos.swiftinterface）：`Generate*` 请求族 = saliency×2 + ForegroundInstanceMask + PersonInstanceMask + ImageFeaturePrint + IterativeSegmentation(class)——**零文本提示分割面**（textprompt/prompt-mask 0 命中）；StatefulRequest 协议仅 Track* 跟踪请求 conform——RESEARCH B2 结论独立复核成立；SUMMARY §spike 五行表 + V2 挂账在案 | 收口成立 |

- **spike 结案语复核**：「达标即收」逻辑 = 机检判据全绿 + 不可达件按裁决⑦
  收口——与 OQ 生效值一致；GUI 轨四行挂待复验（SUMMARY §待复验 + DECISIONS
  待供件清单），**不静默**——结案语措辞（「机检判据全绿」）与实际相符。

## 三、红线机检电池（本路亲跑）

1. `.metal` 全域 diff（984e0256..HEAD）= **0** ✓
2. diff 文件全集 16 文件 ⊆ plan files_modified（LESSONS = L080 如踩坑位）；
   冻结/封存面（RasterMaskStore / MaskCombiner / LightamerSidecar /
   V50Order / NodeOwnershipCatalog / SegmentEditingOverlayHost）diff = 0 ✓
3. MCP 快照族（PhotoProjection/McpServerController）diff = 0 ✓
4. runModal / UserDefaults / `String.LocalizationValue("` 插值键 / scribble
   ——新增全 0 ✓
5. `generateScaledMask` 新增调用点 = 0（4 处 `+` 命中皆注释/文档文字，
   :197 为 07-1 存量升级缝未动）✓
6. Project.swift diff = 恰 4 行测试登记（LAYERS 3 + APP 1，显式清单）+
   dependencies 块零 diff ✓
7. xcstrings：`-` 行仅 diff 头、`+` 86 行、恰 5 键全 `ai_mask_*` 族 ✓；
   **zh-audit 独立复跑 PASS**（1682/1923/zh complete/{en,zh}）✓
8. BUNDLE-MAP 四新行亲核（:291/:293/:295 LAYERS 9/6/5 + :324 APP 4）✓

## 四、D-01..D-12 独立复核（找 REJECT——零 REJECT）

| # | 裁决 | 本路独立依据 |
|---|---|---|
| D-01 | **ACCEPT** | §2.1 独立推导 + 原文亲读，换锚程序/数学双合法 |
| D-02 | 准 | 自环双门亲证 + 残留 task 惰化亲读；「末次交互 = 末次提交」论证与我方 07-3 confirm-模型自洽 |
| D-03 | 准（探针级亲证） | swiftinterface :3429 `pixelBuffer: CoreVideo::CVReadOnlyPixelBuffer`（macOS 27+）亲 grep——plan 草案 CVPixelBuffer 确为不精确形 |
| D-04 | 准（探针级亲证） | swift 探针实跑：`OneComponent32Float == 0x4C303066（'L00f'）= true`；maskPlane switch 中 `case 0x4C303066`（:757）先于 `case kCVPixelFormatType_OneComponent32Float`（:766）⇒ 32F 臂死码（存量面零改） |
| D-05 | 准 | `detectPersonInstances` 直返 AIInstanceCatalog 亲读；InstancePickerOverlay 零改复用（两 popover 宿主形） |
| D-06 | 准 | 测试④ black 场 + MANIFEST 四场探针记录（white/gray128 幻觉）亲读；M-3「真照片」判定注记在册 |
| D-07 | 准 | assets notReady 无真推理可跑；组装面分辨率无关由 T1⑤ 2× fixture 钉死亲读；申报挂 M-1 合规 |
| D-08 | 准 | `74a4709d` 单文件 ±78 行亲核；9 法不胀；SC 24 机械闭合 |
| D-09 | 准 | resolveFeather 三臂 + 非零源 grep 亲跑（恰 2 处与申报一致） |
| D-10 | 准 | `.gitignore:79` `.work/gui-acceptance/` 亲证 + `git check-ignore` 命中；MANIFEST 现场记录完整（模型 7s 四场 + 配方 + 判定标准） |
| D-11 | 准 | L080 本路亲历同坑（死代理 env 在册）旁路有效；worker 挂起一次性有两轮全套双证 |
| D-12 | 准 | 五文档 diff = 0 亲证（diff 文件全集无 AGENTS/ROADMAP/REQUIREMENTS/GOAL-STATE/TODO）；素材指针齐备 |

## 五、第一路 4 观察项复核 + 本路独立发现

### 5.1 O-1..O-4 复核（第一路）——定级全部恰当，无一应升格 error/minor-open

- **O-1**（在飞 + 再 confirm）：场景可达性/取消语义本路独立走查成立
  （§2.3）；同域收敛无腐蚀——**登记级恰当**。
- **O-2**（sigma 负 percent 对称）：wire 上负值恒不入 GPU（三臂 + PatchFlow ②
  钉死）亲核成立；表完备性备注——**登记级恰当**。
- **O-3**（连续 Slider 中间值）：数学良定义 + clamp 兜底亲核成立；
  step 量化属 UX 打磨——**登记级恰当**。
- **O-4**（person 单实例直烘）：`count > 1` 才弹 picker 亲读；与 layer A
  单实例直烘先例同形；M-2/M-3 GUI 轮覆盖真图——**登记级恰当**。

### 5.2 本路独立发现（第一路未覆盖面）

- **N-1（升格建议，唯一非纯登记项）**：**切层/切图不拆段会话**——
  `EditorState.load` 与 app-root `layerEditingState` 均无会话 teardown，
  `armSegmentSession` 仅挂 overlay `onAppear`（图切换不触发重入）。后果
  两支：①**内存**——livePlane（100MP ≈400MB）跨图驻留至模式退出，与
  SUMMARY/plan 声明的「切层/切图」释放点不符（声明 vs 实现缺口）；②
  **正确性（窄窗）**——confirm 后 1s debounce 窗内切图，`runPatchRefine`
  守卫全过（hasSeed/livePlane/isGenerating 均旧会话态）⇒ 旧平面规划
  rect + 新图 decodeFrameInput 进 `segmentPatch` ⇒ 混合输入 patch 烘到
  新图层。窗口 1s、结果可 undo、零 sidecar 腐蚀 ⇒ 不阻断本批 PASS；
  **建议**：闭环批翻账时把「切层/切图释放点」从已兑现清单改为挂账项 +
  V2/下批补「schedule 时捕获 imageURL/layerID、fire 时身份比对」小修
  （约 10 行）。与 O-1 同族（stale-capture 类）但根因不同（O-1 = 同会话
  竞态；N-1 = 会话身份不随图/层迁移）。
- **N-2（nit）**：sigma golden 表 10 行 vs plan T2① 字面「±{1,50,100}×
  {1000,4000}」12 行——缺 (−1,4000)/(−50,4000) 两行；(−50,4000) 实由
  测试⑥ 覆盖，abs 对称性使缺行与正行同码路。纯记账 nit，不修不碍判据。
- **N-3（nit）**：`AIPatchRect.from(normalized:)` 在 x 被钳到
  imageWidth−1 时 `clamped(to: 1...(imageWidth−x))` 出空域 ⇒ width=0 ⇒
  AIPatchRect precondition crash。仅测试/未来消费者可达（产线恒走
  `normalized()` 方向）；防御形建议返回 nil 或收窄 clamp，登记即可。
- **N-4（nit）**：composer seam band `Int(Float * 0.05)` 截断（2.4→2，
  测试⑥ 钉的是截断行为）——与 pad 的 `.rounded()` 不一致；行为已钉死
  且带宽 clamp 域 2..16 内无观感差，登记保确定性即可。
- **N-5（备注）**：patch pass 每轮产一条 history item（`history_ai_mask`
  label）——与 07-3 refine 同语义的延续（每次重烘 = 一条 undo 步），
  非 M6-4-02 新增语义；连发 patch 会积累 undo 步数，产品语义若需折叠
  归后续 UX 批，登记备考。

## 六、分歧与与第一路结论对照

- **结论一致：PASS**；全套数字两路逐位同值（3841/24/0）。
- **无实质分歧**。两点措辞级差异：①D-01 论证强度——本路认为线性恒等
  已足判死，无需「非线性原语」论证链（第一路已同向表述，无冲突）；
  ②第一路 O-1/D-02 附注认为会话拆后残留 task「安全」——本路确认
  **teardown 路径**安全，但指出**不 teardown 的切层/切图路径**未被
  覆盖（N-1），属覆盖面补全而非结论推翻。
- 第一路 AC1-8 全 Delivered 判定本路逐条独立复核**维持**；其「验收方式」
  声明的十项机检本路八项亲跑重证（其余两项 = parentage/监视为本路运行
  实况记录）。

## 七、待复验项（沿第一路 §七，本路无新增门）

1. GUI 轮 M-1..M-4（omp computer-use 或人工；layer B 资产引导下载前置）。
2. D-07（layer B ROI 分辨率）/ D-06（person 标签编号域）随 M-1/M-2 补录。
3. 闭环批翻账五文档（D-12 申报位）+ **N-1 处置落账**（释放点声明订正或
   小修回注）。
4. VALIDATION 落签（C 档第 3 停面）待双重验收闭环后进行。

## 八、执行链 commit 清单（本路逐 commit 范围亲核）

| commit | 内容 | 本路核对 |
|---|---|---|
| `86a0b292` | T1 AIPatchAssembly + 9 法 + BUNDLE-MAP/Project.swift | 4 文件 471+，范围合规 |
| `87efa887` | T2 segmentPatch + AIMaskFeather + 6 法 | 5 文件 324+，零第二条装配亲证 |
| `444f4047` | T3 person 实例面 + 菜单/picker + 5 键 + 5 法 | 7 文件 685+，xcstrings 纯插入 |
| `fbbcf449` | T4 debounce/羽化接线/livePlane + 4 法 | 6 文件 500+，双羽化钉死在位 |
| `74a4709d` | T6 KD-4 行 2 数值门落断言 | 单文件 ±78 行，D-08 合规 |
| `cc1cb04f` | T7 SUMMARY/DECISIONS/LESSONS（L080） | 3 文件 docs-only |

（T5 无 commit = MANIFEST gitignored，D-10 申报合规。）
