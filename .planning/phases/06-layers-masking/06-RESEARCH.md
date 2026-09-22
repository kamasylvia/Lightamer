# Phase 6 Research: Layers & Masking System

**Researched:** 2026-09-21
**Confidence 汇总：** 架构裁决（混合模型）= High（dt blend/masks 源码逐段核过 + 既有 Layer 骨架与 PixelPipe 现码对照，两侧行号全部实证）；合成管线/缓存/ROI 方案 = High（全部落在现码已验证的 seam 上：PipeCacheKey、roiHint 子域渲染、TilingPlan、per-layer hash 链）；mask 光栅化 GPU 方案 = Med（stamping 走 render-pipeline additive blending 的选型需 plan 期原型验证——L018 RMW 红线约束下的备选路径已列出）；blend 公式 parity = High（blendop.cl 全 kernel 核过，L017 分流下的平场 probe 路线可行）；liquify/retouch 工作量 = Med（dt 3774+4891 行中 UI/交互占大头，计算核心 ~800 行已定位，但 Metal 移植量级靠类比 03-05 toneequal 估的）；Phase 1 BlendMode 骨架的 raw 值错位 = High（dt blend.h:47/70 逐值核对，normal=0x01 实为 NORMAL_OBSOLETE，本文件正式记录）。

---

## Summary

Phase 6 = 14 个需求（LAYER-01..07 + IOP-MASK-01..05 + IOP-GEO-05/06），全项目最大架构阶段。核心结论：

1. **架构裁决（§1）：推荐混合模型 (c)——C1 层栈为用户/数据模型，dt blendop 数学为合成引擎。** 每个调整图层 = 一条独立 iop 子链（复用现有 `IOPModule`/`ModuleBox`/`PixelPipe` 全套机制，子链本身就是一个 pixel run），层的合成 = dt `blendop` 的 mask × blend × opacity 三元组直译（`blend.c:458` 的 `a=下层合成/b=本层输出` 公式与 C1 层语义逐点同构）。纯 dt 式 (b)（单 pipe + 每模块 per-instance mask）无法表达 LAYER-01/02/04（层容器/层内 iop 组/重排合并编组），且要给全部 ~25 个已交付模块逐个加 blend 腿——双重否决；纯 C1 式 (a) 没有现成合成引擎，blend 公式全要自研。混合模型下 Phase 2-5 的 pipe walk **一行不改**——层维度活在 walk 之上（`LayerCompositeDriver` 编排 N 个子 run + 合成），不是 walk 之内。
2. **挂接点（§2）：合成 seam = base 链末端（colorout 显示尾之前）的工作空间平面。** run 结构 = base 链子 run → 逐层（自下而上）「本层子 run → blendop 合成」→ 终端段（colorout→gamma）子 run。几何模块（lens 13/ashift 15/flip 16/clipping 17）只许在 base 层（v1 禁层内几何，C1 同口径）；蒙版坐标系钉内容锚定（dt 归一化坐标模型，经几何映射器双向换算）。
3. **缓存与 ROI（§2）：`PipeCacheKey` 加 `layerID: UUID` 维度**（现 key 五字段 `PipeCacheKey.swift:15-38` 加一），每层子 run 自带独立 hash 链（`levelHash` 语义逐层复用）——编辑层 K 只失效 K 链下游 + K..N 合成前缀，<K 层与 >K 层链输出全 cache hit，增量 = N−K 个廉价 blend pass。跨层 ROI：合成窗口一次性协商（base 链 forward walk 产出最终 ROI = 各层子 run 的 entry roiHint，04-01-T4 子域渲染现成），每层 dscIn/iscale 由各自子 run stamp——**L021 红线逐层适用，禁止再 ×scale**。
4. **mask 体系（§3）：drawn（brush/path/ellipse/gradient）+ parametric（luma/JzCzhz 范围 + feather/invert/blur/contrast）+ raster（烘焙）+ combine（union/intersect/difference/exclusion/sum）。** dt 侧证据完整：form 模型（`masks.h:35-49,358-371`）、combine 公式（`group.c:487-630` 逐式可直译）、parametric mask kernel（`blendop.cl:426-512` 四域）、mask 后处理链（`blend.c:32-39` POST_BLUR/FEATHER/TONE_CURVE）。渲染推荐 GPU：analytic kernel + render-pipeline additive blending stamping（L018 RMW 红线下禁 read_write 纹理累积）；蒙版平面 = 单通道 float，按 (layerID, maskVersion, roi) 缓存。
5. **blend modes（§4）：13 个已冻结 enum 值的公式全部按 dt MODERN 版直译**（RGB scene 域算术模式 + JzCzhz 往返感知模式，`blendop.cl:513-1309`）；**Phase 1 骨架的 `normal = 0x01` 是个值错位**（`BlendMode.swift:17` 注释声称 NORMAL2，实为 dt `NORMAL_OBSOLETE`，`blend.h:47` vs `:70`）——值已冻结不可重编，处置 = 该值实现现代 normal2 公式、头注记录与 dt raw 值的分叉（Open Question 2）。PS color dodge/burn 在 dt 无对应模式，用**新 raw 值**增补（W3C compositing 公式）。mask × blend × opacity 三元组在单 kernel 内一次完成（dt 同构：mask 先与 gopacity 合成、blend 公式收 opacity 参数）。
6. **liquify/retouch（§5）：liquify = base 链既有槽位 18.0 的 warp 模块**（bezier 路径 + 扭曲场 + lanczos 重采样 kernel，计算核心 ~500 行）；**retouch = 独立图层 kind（retouch 层）**，四种算法 clone/heal/blur/fill（`retouch.c:66-71`），heal = 迭代 Laplacian（`heal.c:354` dt_heal，max_iter 2000）。两者都依赖蒙版/变形框架就位后才有意义——依赖序上排 Phase 6 尾部；retouch 的 heal 质量迭代可拆 6.5（Open Question 1）。
7. **sidecar（§6）：`layerStack: String?` 预留位（`LightamerSidecar.swift:138`）升级为类型化记录 + schemaVersion → 2**；每层记录 = 冻结的 `ModuleInstance` 拼写直接复用（层内 iop 链）+ mask form 记录（点列 + 版本号，NDE-1/3 口径）；**raster mask 像素不进 JSON**——旁挂 `<原名>.lra.masks/<maskid>.png`（16-bit 灰度）+ 文件名 + decimal String 哈希引用；历史项 `HistoryItem.layerScope`（`HistoryStack.swift:66` Phase 6 预留）直接启用，层结构操作（增删/重排/mask 编辑）以**层栈快照型** history item 扩展（新增 optional 字段，decodeIfPresent 容错）。
8. **性能（§7）：PREVIEW 交互 = 编辑层 K 的子链重渲 + N−K 个 blend pass**（≈ 各 1-3ms @2560），D-C3 梯子照常；100MP FULL = **窗口化 O(视窗) 而非 O(全图)**——roiHint 子域渲染（`PixelPipe.swift:610-663`）对每层子 run 生效，层内重模块（denoise 族）TilingPlan 逐层照旧。内存新增面 = 每层链输出 + 合成前缀平面（PREVIEW ~70MB/平面 × 2N），`PipeCache.enforceBudget` 分层驱逐语义需 plan 期扩「层平面」档。
9. **golden 主轨 = float64 逐式复刻 + 恒等不变量**（L017 约束下 blend/mask 全是点态或解析算子，合成参考天然可行）：blend 每模式 × 域一例（<1e-5）+ dt-cli 平场 probe（blendop_params 进 XMP，L015 hex 配方，`DEVELOP_BLEND_VERSION=14` blend.h:31）；mask 光栅化解析断言（stamp 径向/gradient 直线与 sigmoidal/combine 公式逐式）；序列化 round-trip（N 层栈 → write/read → 渲染逐字节恒等，L014 fence 纪律）；合成恒等三元组（全 mask normal == 下层 / opacity 0 == 下层 / 空层 == no-op）。
10. **plan 拆分建议 7 个**（§10）：6-1 层核与 sidecar v2 → 6-2 blendop 引擎 → 6-3 drawn mask → 6-4 parametric/raster/combine → 6-5 图层 UI 与 round-trip 签核 → 6-6 liquify → 6-7 retouch。总量 ~38-48 T，为全项目最大单阶段（符合 ROADMAP「the largest architectural phase」定级）。8 个 Open Questions 见文末，其中 BlendMode 值错位处置（OQ2）与 retouch 拆分（OQ1）需用户/planner 拍板。

---

## Implementation Approaches

### 1. 架构裁决核心：图层模型选型（全文档最重要一节）

#### 1.1 三个候选

| 模型 | 机制 | 优势 | 劣势 |
|---|---|---|---|
| **(a) C1 纯层栈** | 每层独立 iop 子链 + mask + blend + opacity，自下而上合成 | LAYER-01..07 语义直接；用户模型即产品差异化 | 合成引擎（blend 公式 × 色域 × mask 组合）全自研 |
| **(b) dt 纯 per-module mask** | 单 pipe，每个模块实例挂 `blend_params`（mask_mode + mask_id + blend_mode + opacity），blend 在每模块 process 尾部执行（dt 现状） | 与 dt 源码 1:1；单 pipe 不变 | **无法表达 LAYER-01/02/04**：没有层容器（iop 组）、层不透明度/混合模式作用于「组」而非模块、层重排/合并/编组无落位；且要求给已交付 ~25 模块逐个加 blend 腿（每个 process 尾部插合成段）——Phase 3-5 产物全面返工 |
| **(c) 混合：C1 层栈为模型，dt blendop 为引擎** | 层栈数据模型按 (a)；每层的「子链 → 输出 → 与下层合成」一段按 dt `dt_develop_blend_process` 直译；合成段 = 独立 `LayerCompositeStage`，不在各模块 process 内 | 两头取长：语义 = C1，数学 = dt（经过 15 年打磨的公式与色域处理）；Phase 2-5 的 pipe walk / 缓存 / ROI / tiling **零改动** | 需要 `PipeCacheKey` 加维度 + 新编排层（工作量集中在 §2 的 driver） |

#### 1.2 dt 侧证据：per-module blend 的真实形态（为什么 (b) 不合需求）

- dt 的 blend 挂在每个 iop 模块的 process 尾部：`dt_develop_blend_process`（blend.c:458-530）拿 `a = 模块输入`、`b = 模块输出`，按 `blend_params` 合成。**blend 参数是每模块实例的属性**（`dt_develop_blend_params_t`，blend.h:192-233：mask_mode/blend_cst/blend_mode/opacity/mask_combine/mask_id/blendif/feathering/blur/contrast/brightness/details + raster_mask_source）——这就是「per-iop mask」。
- 该模型里「一组 iop 共享一个蒙版/一个不透明度」只能靠 dt 的 instance 分组 hack（多实例各自挂同一 mask form 的引用），**没有「层」这个一等公民**：LAYER-04 的重排序是「层」的重排（整组 iop 连带 mask 一起动），per-module 模型下要重排的是散布在 v50 序列各处的模块实例，语义与 UX 都不成立。
- dt 自己也证明 blend 数学可以脱离模块独立成段：`blendop.cl` 全部 13 个 kernel（:426-1710）是纯函数级的 mask/blend 算子，输入 `in_a/in_b/mask` 输出 `out`——**正是 (c) 方案合成引擎的现成直译源**。

#### 1.3 Lightamer 侧证据：骨架与 pipe 现状已经按 (c) 预埋

- **Layer 骨架（Phase 1 就位）**：`Layer.swift:25-52` 协议（id/name/isVisible/opacity/blendMode/enabled/kind）+ `LayerStack.swift:27-42`（baseLayer + adjustmentLayers 自下而上）+ `BackgroundLayer.swift` + `LayerKind.swift`（注释明言 Phase 6 可加 `case raster`）。`Layer.swift:19-24` 明确把 `iopChain`/`mask` 留给 Phase 6 设计——**本研究的层内 iop 链类型裁决：`AdjustmentLayer.chain: [ModuleInstance]`（记录型，与 `EditorState.instances` 同构），盒化（ModuleBox）按子 run 生命周期制造**（`any IOPModule` existential 不可形成的 gotcha 已由 ModuleBoxing 解）。
- **PixelPipe 的层意识**：`PixelPipe.swift:59` `layerStack` 字段自 Phase 1 起持有；`run()`（:429）的 pieces 排序/hash 链/ROI 协商全部对「一个实例数组」工作——**每层子链恰好就是一个这样的数组**。子 run 复用 = 零协议改动。
- **既有 seam 清单（合成 driver 的全部依赖）**：
  - `PipeCacheKey`（`PipeCacheKey.swift:15-38`）：加 `layerID` 一字段（in-memory key，合成 Hashable 现成）。
  - roiHint 子域渲染（`PixelPipe.swift:493-500,610-663`）：04-01-T4 已端到端，每层子 run 直接喂窗口 ROI。
  - `HistoryItem.layerScope`（`HistoryStack.swift:66`）：Phase 6 预留位，启用即可。
  - sidecar `layerStack: String?`（`LightamerSidecar.swift:138`）：预留位，升级为类型化记录（§6）。
  - `V50Order.swift:37-50`：几何模块槽位（lens 13→clipping 17）与 liquify 18/retouch 20 已在表内；终端段 colorout/gamma 的识别条件 = `opName ∈ {colorout, gamma}`（现 `tailPixelFormat` 已按 gamma 识别，`PixelPipe.swift:180-187`）。

#### 1.4 裁决：推荐 (c)，迁移路径三步

1. **6-1：层核落地**——`AdjustmentLayer` 具体类型（含 chain/mask/props）+ `LayerCompositeDriver`（先只支持「无 mask、normal、opacity 1.0」的退化合成 = 逐层拷贝/直通）+ `PipeCacheKey.layerID`。这一步交付后，**多层的「同 iop 不同参数」（LAYER-02）已经可用**（各层子 run 各自的实例链），只是还没有局部性。
2. **6-2：合成引擎**——blendop 移植落位（§4），三元组生效，LAYER-05 完成但仍全帧。
3. **6-3/6-4：mask 体系**——蒙版接入三元组的 mask 腿，局部性完成（LAYER-03/05/MASK-01..05）。

回退安全性：若 6-2 前发现 blendop 直译有结构性障碍（预期不会——公式是纯点态），合成引擎可先只做 normal 模式 + opacity（三条公式），层栈语义不受影响。

### 2. 合成管线设计

#### 2.1 run 结构与挂接点

```
PixelPipe.run(image, instances, layerStack)
  ├─ A. base 子 run：pieces = base 链（instances 剔除终端段 colorout/gamma）
  │      → 产出合成输入平面 S（线性 Rec2020，post-几何 post-colorin）
  ├─ B. 逐层合成（adjustmentLayers 自下而上，跳过 !enabled）：
  │      for layer in stack:
  │        L = layer 子 run（input = 上一层合成输出 C，roiHint = 合成窗口）   ← LAYER-02 独立参数
  │        C = blendop(below=C_prev, b=L, mask(layer), blendMode, opacity)   ← dt blend.c:458 同构
  ├─ C. 终端段子 run：pieces = [colorout, gamma]（若 base 链原本含之）
  │      → 显示平面
```

- **seam 选择论证**：调整图层必须作用在 working space（scene-referred 线性 Rec2020）——若合成放在 colorout 之后（显示域），层内 iop（exposure/filmic 等）的 scene-linear 语义全毁。放 colorin 之前（相机 RGB 域）则与「层做创意调整」的产品语义相反。colorout 前是唯一正解；这也是 dt `DEVELOP_BLEND_CS_RGB_SCENE`（blend.h:40）的存在理由。
- **终端段归属**：colorin 在 base 链内（28.0，V50Order.swift:61）不动；colorout/gamma 从 base 链尾摘出、在合成后执行。`GammaModule.outputPixelFormat` 的 display-tail 政策（`PixelPipe.swift:173-187`）原样适用于终端段子 run。
- **driver 形态**：`LayerCompositeDriver`（Core/Pipe 新文件）不改 `PixelPipe`——它实例化 1 + N + 1 个 `PixelPipe`（或复用一个 pipe 多次 run）。`processRec`/缓存/tiling 全部原样。

#### 2.2 per-layer 缓存语义

- `PipeCacheKey` 加 `layerID: UUID`（base/终端段 = baseLayer.id；合成前缀平面单独一类 key，见下）。position 在每个子 run 内部照旧从 0 计。
- **每层链输出平面**缓存：key = (imageID, pipeType, layerID, position=end, upstreamHash=该层 levelHash 末端, roi=窗口)。
- **合成前缀平面**（C₁..Cₙ）：key = (imageID, pipeType, layerID=<该层的>, position=COMPOSITE 保留位, upstreamHash=该层 chain hash ⊕ blend 三元组 hash ⊕ maskVersion hash, roi)。**下游层的缓存命中依赖上游前缀 key 不变**——编辑层 K 参数 → K 前缀失配 → K+1..N 的前缀连锁失配（正确，C1 语义要求），但 K+1..N 的**链输出**平面全部命中（它们的链没变），重算只有 blend pass。
- **重排/改名/可见性**：层身份 = UUID（`Layer.swift:30` NDE-1 铁律），重排只改「合成顺序」= 各前缀 key 的上游依赖序——层链输出 key 不含顺序 → **重排后链缓存全存活**，只重 blend（该设计的免费红利）。
- FULL 政策（lock #4 推广）：PREVIEW/THUMBNAIL 照旧缓存全层；FULL 只缓存「热层」（当前编辑层）链输出 + 各前缀（窗口化后每平面 ~几十 MB），冷层链输出不缓存（重渲走子 run）。预算入 `PipeCache.enforceBudget` 分层档（§7）。

#### 2.3 跨层 ROI 协商（L020/L021 红线承重）

- **一次性协商**：base 子 run 的 forward walk（`PixelPipe.swift:508-538`）产出最终 ROI（含 crop 收缩/rotate AABB 扩张）→ 该 ROI = 合成窗口 = 每层子 run 的 entry roiHint + 终端段输入 ROI。三层 ROI 一致性由 precondition 断言（照 `PixelPipe.swift:719-722` 的 negotiated-ROI violated 模式）。
- **层内 ROI**：v1 调整层只许恒等 ROI 模块（§1.4 几何禁令），故层内无几何协商；layer 子 run 的 backward negotiation（halo 类）照旧单层内闭环。**跨层的 dscIn/iscale 语义**：每层子 run 独立 stamp 自己的 `bufInROI`/`iscale`（`PixelPipe.swift:513-523` 同码），蒙版/半径计算各自读各自 piece——L021 的「dscIn 是本 run 平面像素」逐层成立，**禁止任何「拿 base 的 dscIn 给层用」的抄近路**（层与 base 的入口 ROI 因 base 链几何而不同）。
- **蒙版坐标系**（跨层几何一致性核心）：mask 点列以**全解码帧归一化坐标**存储（dt 同口径，`masks.h` form 点列均为归一化 buffer 坐标）；合成窗口在「合成平面坐标」（post-几何），光栅化时经**几何映射器**换算回图像坐标。`GeometryPointMapper` 新协议：Phase 4 五个几何模块（crop/rotate/perspective/lens/ashift + flip）各实现正向/逆向点映射（仿射精确、单应/径向用 04-03/04-04 已在 Swift 侧的矩阵/系数），映射器 = base 链几何段逆序复合——**liquify 的路径映射同机制**（dt 用 `dt_dev_distort_transform_plus` 做同一件事，liquify.c:606-612）。
  - 备选（plan 压力时的降级，需用户认可）：蒙版钉「合成平面坐标」（所见即所得），crop/rotate 变更后蒙版随帧走不随内容走——省掉映射器，但 mask 内容锚定语义降级（dt/C1 都是内容锚定），记 Open Question 7。

### 3. mask 体系

#### 3.1 形态清单与数据模型（dt form 模型直译）

| 类型 | dt 证据 | Lightamer 记录 |
|---|---|---|
| brush | `masks.h:183-191`（corner/ctrl1/ctrl2/border/density/hardness/状态 per 点）；stamps 贝塞尔串 | `BrushStroke { points: [BrushPoint]，径向 falloff 由 hardness/density 参数化 }` |
| path（多边形/贝塞尔） | `masks.h:173-181`（corner+双控制点+border）；`masks/path.c` 5562 行（含 border 内缩带） | `PathForm { nodes: [corner, ctrl1, ctrl2]，fill + feather border }` |
| ellipse | `masks.h:154-163`（center/radius[2]/rotation/border/flags） | `EllipseForm { …同构 }` |
| gradient | `masks.h:195-204`（anchor/rotation/compression/steepness/curvature + linear/sigmoidal 状态，:91-95）；光栅化公式 gradient.c:1201/:1353 | `GradientForm { anchor, rotation, compression, state: linear\|sigmoidal }` |
| group（combine） | `masks.h:206-211`（formid/parentid/state/opacity）；state 位 UNION/INTERSECTION/DIFFERENCE/EXCLUSION/SUM/INVERSE（masks.h:52-68）；combine 公式 group.c:487-630（union=MAX、intersect=MIN 夹取、difference、sum、exclusion 逐式） | `MaskGroup { items: [(formID, op, inverted, opacity)] }`——**LAYER-03/MASK-04 的多蒙版并/差/交 + 蒙版组** |
| raster | dt `DEVELOP_MASK_RASTER`（blend.h:97）+ `blend.c:552-571` 经 `dt_dev_get_raster_mask` 取上游模块导出的 mask 平面 | `RasterMaskRef { pngFile, maskHash, invert }`（烘焙自其他 mask/层，§6 存储） |
| parametric | dt blendif：`blend.h:120-190` 通道集（Lab/RGB/JzCzhz/HSL 域 × in/out 侧）+ `blendop_mask_*` kernel（blendop.cl:426-512，4 点平滑曲线 per 通道 + boost 因子）+ 后处理 blur/feather/contrast/brightness（blend.c:32-39 → :305-330 组装；contrast/brightness 走 `blendop_mask_tone_curve` blendop.cl:1310-1424；feather 走单通道 Gaussian blend.c:664-710） | `ParametricMask { domain: luma\|jzczhz，channels: [4 点曲线]，featherRadius, blurRadius, contrast, brightness, invert }` |

每层一个 `MaskSpec`：`drawn: MaskGroup?` ⊕ `parametric: ParametricMask?` ⊕ `raster: RasterMaskRef?` 可同时启用（dt `mask_mode` 位组合 MASK|CONDITIONAL|RASTER，blend.h:92-103 同语义），合成时先各自出平面、后按 combine 规则并成**单一有效 mask 平面**再进 blend（dt 同构：blend.c:516-530 的 mask 获取 + post 链）。

#### 3.2 渲染管线（mask 纹理）

- **平面格式**：`r32Float` 单通道（合成数学与 combine 直接吃 float；100MP 窗口化后单平面 ≤ ~25MB）。
- **drawn 光栅化（GPU 首选）**：
  - gradient/ellipse/path（多边形）：**analytic compute kernel**——per-pixel 到几何原语的有向距离/参数化位置，纯函数无累积，窗口化天然精确（每窗口重算，无需全图 mask 缓存）。
  - brush stamps：逐 stamp 的径向 falloff 需要**累加**——L018 红线禁 read_write 纹理同线程 RMW。推荐 **render-pipeline additive blending**（render pass 逐 stamp 点精灵，硬件混合累加，无原子操作）；备选 compute + `atomic_fetch_add`（Metal 的 float 原子需 integer 定点缩放或 compare-exchange，复杂度高）。**Med 置信点**：stamping 路径在 6-3 plan 首任务原型化（两方案各一天 spike）后定稿。
  - path 的 border（羽化内缩带）：SDF 距离带 + smoothstep，解析式。
- **parametric 光栅化**：单 kernel 直译 `blendop_mask_rgb_jzczhz`（blendop.cl:1096-1309）——从合成平面像素现算 JzCzhz/luma → 4 点曲线平滑权重 → 与 gopacity 合成。JzCzhz 往返常量与 filmic/cb 链同源（YrgGamut/JzAzBz 既有矩阵，**L023 教训：uniforms 半边契约必须先写全往返式再钉测试**）。后处理链（blur/feather/contrast）作为 mask 平面上的独立 pass（单通道 Deriche 复用 GaussianBlur 工程纪律、双平面 buffer；contrast/brightness 直译 `blendop_mask_tone_curve`）。
- **combine**：`_combine_masks_*` 五式逐行移植（group.c:487-630，全是 MAX/MIN/线性式），单 kernel 吃 N 个输入平面按序 reduce（N 通常 ≤4）。
- **mask 缓存**：key=(imageID, pipeType, layerID, maskVersionHash, roi)，maskVersionHash = StableHash(form JSON + props)。mask 不变时跨 param 编辑全命中；蒙版编辑只失效本层 mask 平面 + 本层前缀（**层内蒙版编辑的增量面是全阶段最小的**）。
- **预览（overlay）**：`blendop_display_channel`（blendop.cl:1474+）的显示腿移植——mask 平面以黄色调/黑白 checker 叠加到显示平面（终端段后一个可选 overlay pass 或 EditorBlitShader 变体）；触发 = UI「显示蒙版」开关（dt request_mask_display 同语义，blend.c:509-515 只对焦点模块/当前 pipe 生效——我们对应「选中层」）。

### 4. blend modes

#### 4.1 模式清单与域映射

- **已冻结 13 值**（`BlendMode.swift:14-47`，值不可重编——sidecar 自 Phase 2 携带）：normal/multiply/linearBurn(=dt SUBTRACT)/screen/overlay/softLight/hardLight/luminosity(=dt LIGHTNESS)/saturation(=CHROMATICITY)/hue/color/colorDodge(=dt COLORADJUST)/difference(=DIFFERENCE2)。
- **⚠ Phase 1 骨架的值错位（本研究正式记录）**：`normal = 0x01` 的注释声称 `DEVELOP_BLEND_NORMAL2`，但 dt `blend.h:47` 的 0x01 是 `NORMAL_OBSOLETE`（带 clamp 的旧版），现代无 clamp normal 是 **0x18**（blend.h:70）。同理 `colorDodge = 0x16` 是 dt `COLORADJUST`（特殊「只混入调整色」模式），**并非** PS color dodge。处置推荐（OQ2）：**值不重编，语义按现代公式实现**——0x01 实现 normal2 公式（`o = a·(1−op) + blend(a,b)·op`，blendop.cl:646+ 的 NORMAL2 分支），0x16 实现 COLORADJUST 公式并另开新 raw 值给真 PS color dodge；`BlendMode.swift` 头注更新为「raw 值沿用 dt 枚举槽位、公式按 dt MODERN 直译、与 dt raw 值的语义映射表见此」。若用户要求与 dt raw 值逐 case 严格同义，则 0x01 弃用 + 新增 0x18——破坏「已冻结」承诺，需 sidecar 迁移（不推荐）。
- **LAYER-05 增补**：PS color dodge/burn（dt 无对应——新 raw 值，W3C Compositing-1 公式）；lighten/darken（dt 0x02/0x03 现成直译，顺手）；vivid/linear/pin light 等其余 dt 模式（blend.h:59-88 全表）按新值按需追加，枚举扩展永不重编（`BlendMode.swift:43-46` 既有纪律）。
- **域能映射**（dt 的 per-mode 色域路由，blendop.cl:513-1309 三个 kernel 家族）：
  - **算术模式**（normal/multiply/screen/overlay/soft/hard/lighten/darken/dodge/burn/difference/linearBurn）：**线性 Rec2020 域直接混合**（dt `blendop_rgb_*` 对 RGB scene 的行为，lmin/lmax = 工作域界）；每模式一个分支函数，单 kernel。
  - **感知模式**（hue/saturation/color/luminosity）：**JzCzhz 域往返**——`blendop_rgb_jzczhz`（blendop.cl:1096-1309）逐式直译（hue 分支的角度最短路径插值 :713-733 公式族；L 分量直接换）;备选域 OKLCh（更现代）放弃——parity 源唯一性优先 JzCzhz。
  - **REVERSE 位**：dt `DEVELOP_BLEND_REVERSE = 0x80000000`（blend.h:89）交换 a/b——`BlendMode.swift:11-13` 注释已预告采纳，零成本。

#### 4.2 三元组与 kernel 形态

- **单 kernel 完成合成**：`compositeLayer(inBelow, inLayer, inMask, out, blendMode, opacity, maskDisplay)`——mask 先乘 gopacity（dt blend.c:530 `opacity = CLIP(d->opacity/100)` 与 mask 合成的顺序照搬），blend 公式收 opacity 参数（blendop.cl 全部模式同构）。mask 缺省（无蒙版层）走 `blendop_set_mask`(value=1) 等价的常量路径，无专门 kernel。
- **PS 期望 vs 线性域的观感分歧**：PS 的 overlay/soft light 定义在 gamma 编码域；dt RGB scene 在线性域跑同名公式——两者观感不同（线性域 overlay 更「硬」）。**v1 钉 dt（parity 可验证）**，观感调优（编码域混合变体）留作后续选项（OQ8 不单列，并入 4.1 头注记录）。

### 5. liquify / retouch

#### 5.1 liquify（IOP-GEO-05）

- **dt 形态**：bezier 路径节点网（`dt_liquify_path_data_t`：header + warp(point/strength/radius 复数对) + node 控制点，liquify.c:225-257；MAX_NODES=100 :47）；warp 类型 linear/radial grow/radial shrink（:218-223）。process（:1390-1410）= 拷贝全图 → 由路径插值构建**全局扭曲场**（per-pixel 位移矢量，`_build_global_distortion_map`）→ 对场内区域重采样应用（CPU）；CL 腿 = `warp_kernel`（liquify.cl:73+，位移卷积 + lanczos3/bicubic 核，kdesc 分辨率 100）。iop_order 18.0（V50Order.swift:48 现表已在），域 RGB（liquify.c:323-330），tags = DISTORT|GEOMETRY、过滤 CROPPING|DECORATION（:313-321）。
- **落位裁决：base 链既有槽位的普通模块**（非层）。理由：liquify 是几何变形——放合成之上会让「层 mask 坐标」与「图像内容」脱钩（mask 在合成平面、内容被 liquify 拉走）；放 base 链则蒙版映射器（§2.3）把 liquify 纳入几何段即可保持内容锚定（位移场可逆采样做点映射，dt 同法 liquify.c:606-612）。
- **分工**：扭曲场构建（路径插值 → 位移图）= CPU（Swift，仅 liquify 参数变化时重建，分辨率 = 场网格 ~百级）；场应用 = GPU（`warp_kernel` 直译：邻域位移采样 + lanczos 权重，单 pass）。交互（拖控制点）= overlay 编辑器（dt 的 layer/hit-test 机制 :97-204 不移植——那是 Cairo UI，我们用 SwiftUI/Metal overlay 重做交互层）。
- **工作量**：计算核心（场构建 + warp kernel + 点映射）~500 行直译 + 交互 overlay 全新写 = **大件**；估 1 个 plan（5-6T）。

#### 5.2 retouch（IOP-GEO-06）

- **dt 形态**：四算法 clone/heal/blur/fill（retouch.c:66-71），stroke 列表参数化（每 stroke = 形状（圆/bezier path）+ 算法 + source 位置 + 不透明度）；heal = 迭代 Laplacian 边界条件扩散（`dt_heal`，heal.c:354-422，max_heal_iter 2000 retouch.c:117，有 CL 腿 heal_cl :422）；clone = 源区拷贝 + mask 羽化；blur/fill = Gaussian/bilateral 与纯色。flags = SUPPORTS_BLENDING | **NO_MASKS**（retouch.c:221——它自带 per-stroke 形状蒙版，不吃全局 blend mask）。iop_order 20.0（V50Order.swift:50 现表已在）。
- **落位裁决：独立图层 kind `retouch`**（`LayerKind.swift:12` 注释预留的 `case raster` 扩展为 retouch/raster 两 kind 之一，plan 期定名）。理由：C1 语义（heal/clone 是独立「修复层」，可整体隐藏/删除）；其「iop 链」= stroke 列表（单一参数体），复用层容器（可见性/蒙版/混合全套免费获得）；**不在 base 链**——修复应该是可整体开关的编辑步骤，且多层修复栈是常见工作流。stroke 形状即该层自带的 mask（dt NO_MASKS 同语义），不再叠加 parametric mask v1（可后续）。
- **分工**：clone/fill/blur = 全 GPU（拷贝/纯色/单通道模糊，GaussianBlur 复用）；**heal = GPU 直译 heal.cl 迭代核**（每次迭代一个 dispatch，≤2000 iter 上界 → 实际按收敛 early-exit 需读回判断 = CPU 侧迭代循环 + GPU 单步，M 置信：迭代次数与延迟需 plan 期基准，100MP 窗口化后 patch 小、预期可交互）。stroke 源区采样跨窗口（patch 源可出视窗——dt 为此有 `inside_roi` 分支 blend.c:493-500 同类问题）→ retouch 子 run 的 modifyROIIn 需按 stroke 的源∪目标 AABB 扩窗（协议内现成 seam）。
- **工作量**：**最大单件**（dt 4891 行中 UI 占半，计算核心 clone/heal/blur/fill + stroke 模型 + retouch 层 kind ≈ 全新交互系统）；估 1-2 个 plan（6-8T）。**若排期压力：6-7a（clone/blur/fill + retouch 层框架）先行，6-7b（heal 迭代核）拆 6.5**（OQ1）。

### 6. sidecar 格式扩展

- **schemaVersion → 2**（`LightamerSidecar.swift:98` 现为 1）：`layerStack: String?`（:138 预留）升级为类型化 `SidecarLayerStackRecord`；v1 文档（layerStack=null）解码为「无调整层」兼容路径。单向格式锁延续（Phase 2 约定）：所有 UInt64 哈希 decimal String（`UInt64String` wrapper 全沿用）。
- **层记录**（新 Codable，拼写冻结）：
  ```
  SidecarLayerRecord { id: UUID, kind, name, isVisible, enabled, opacity: Float,
                       blendMode: Int（raw 值）, chain: [ModuleInstance]（冻结拼写复用）,
                       mask: SidecarMaskSpec? }
  SidecarMaskSpec   { drawn: SidecarMaskGroup?, parametric: …?, raster: …?,
                      version: Int（form 版本，NDE-3 口径——mask 点结构演进时升级） }
  ```
  mask 点记录 = 类型化 payload（brush/path/ellipse/gradient/group 逐类型，字段对齐 §3.1 表）；opacity/combine/invert 等属性随组。
- **raster mask 像素不进 JSON**：旁挂 `<原文件完整名>.lra.masks/<maskID>.png`（16-bit 灰度 PNG 无损；100MP 灰度 PNG 压缩后 ~几十 MB 级）+ 记录内 `{fileName, maskHash: UInt64-String, invert}`；加载时 hash 校验（与原片缺失同样的 reconcile 语义，Phase 9 口径）。JSON 内嵌 base64 否决（体积失控 + 双重编码）。
- **历史**：
  - 参数类编辑：`HistoryItem.layerScope`（`HistoryStack.swift:66`，String? 存层 UUID 字符串）启用；`snapshot` 仍是 `ModuleInstance`——**生效实例集 = 按 layerScope 分组的 `effectiveInstances(layer:)`**（`ModuleRegistry.effectiveInstances` 扩展，层内 dedup 元组 (opName, multiPriority) 不变）。
  - 层结构类操作（增删层/重排/复制/合并/mask 笔画/属性）：新增 optional `HistoryItem.stackSnapshot: LayerStackSnapshot?`（完整层栈轻量快照——masks 是点列、chain 是参数字节，无纹理，体积可忽略；`items[]` 1:1 落 sidecar 的既有性质保持）。CodingKeys 加字段走 decodeIfPresent（v1 文档 nil 兼容，非破坏）。
  - 合并/编组（LAYER-04 的 merge/group）：merge = 把层链按 v50 序合入下层 + mask 并入（丢失独立性的破坏性操作，history 可退）；group = v1 以「MaskGroup 内嵌套 form」承载蒙版组（§3.1），**层编组（文件夹）defer 到 v2**（OQ6 记录理由：层文件夹是纯 UX 组织，不产生新管线语义）。
- **层内模块注册/降级**：未知 op 透传降级（02-06 机制）对层链逐层生效；sidecar 漂移检测（historyHash）把层链哈希一并折叠（字段显式折叠，L013 纪律）。

### 7. 性能

- **交互增量模型**（PREVIEW，2560 长边，平面 ~70MB）：
  - 拖层 K 的滑杆 → K 链子 run 增量（层内 hash 链 = SC#2 语义原样）+ 前缀 K..N 重 blend（各 1 kernel ~1-3ms）+ 终端段重跑（2 模块）。<K 全 hit；>K 链输出全 hit。**D-C3 梯子/拖动=1 commit 三件套不动**。
  - 蒙版笔画编辑 → 仅 mask 平面重光栅化 + 本层重 blend + K..N 前缀。
  - 10 层全启用链的稳态拖动预算 ≈ 层链增量（与单层链同量级，Phase 5 已验 33ms 全链基线的层化版本）+ ~10 blend pass ≈ 仍在 60fps 预算内；signpost 增 `composite` 段记账（04-07 模式，`.work/06/perf.md` 落账，只记录不设门——SC 门沿 PREVIEW 拖动实测）。
- **100MP FULL**：**窗口化**——runOnce 带 roiHint（视窗），每层子 run 只渲窗口（子域渲染 `PixelPipe.swift:610-663` 现成）；层内重模块（denoise 族）`tileNeeded`/`executeTiledNegotiated` 逐层照旧（**TilingPlan 首次多消费者跨层复用，回归网先行加固**——05-RESEARCH §3.3 同款纪律）。无窗口（fit 视图）时 FULL 全幅：每层链输出平面 1.63GB——**FULL 不缓存冷层链输出**（§2.2 政策），工作集 = 2 平面（ping-pong）× 1 + 前缀平面数，前缀平面 FULL 也走「合成即弃、仅缓存最终」除非热编辑（热编辑窗口化已覆盖交互场景）。
- **内存记账扩展**：`MemoryBudgetTests` 增层维度 case（N 层 PREVIEW Δfootprint 有界 + FULL 窗口化断言「输出平面尺寸 == 窗口而非全幅」）；`PipeCache.enforceBudget` 分档：终端/输入 > 层链输出 > 前缀 > mask 平面（驱逐序）。
- **METAL-8（拖动失效风暴）**：per-layer 缓存本身就是分层止血（单层失效不扩散到 <K）；再加「蒙版编辑不触发链重算」（maskVersion 与 chain hash 独立折叠进前缀 key）双保险。

### 8. UI 面

- **图层面板**（`LayersPanelView` 新文件，Inspector 顶部固定区，280pt 内）：层列表（自下而上）+ 每行：可见性眼、名称（inline rename）、缩略 mask chip（蒙版平面低清快照）、opacity 滑块（D-H1：拖动结束 1 commit）、blend Picker（zh/en String Catalog）。层操作条：添加（新建调整层）、复制、合并向下、删除、拖拽重排（重排 = 1 commit，`stackSnapshot` 型）。层选中态 = Inspector 模块面板切换为该层 chain（`IOPPanelProvider` 逐层实例化——面板代码全复用，24 个既有面板零改动）。L010 identifier 全量（`layer.row.<uuid>` 用稳定 id 非索引）。
- **蒙版绘制工具**（`MaskToolbarView` + `MaskOverlayHost`，Overlay/ 既有 CropOverlayHost 模式扩展）：工具集 brush/eraser/gradient/ellipse/path；brush 参数环（size/hardness/flow/opacity，cmd-drag 调 size 的 C1 手势 → Manual-Only 表登记）；gradient 三线交互（按下拖出 = anchor→falloff 线，两端手柄 + 旋转，linear/sigmoidal 切换）；形状工具命中/手柄 = CropOverlay 的 hit-test 模式。**交互手感全挂 Manual-Only register（L011/L021 红线：笔刷延迟/落点精度/光标环单测不可达）**；GUI 验收轮按 PLAYBOOK §0-§6 真实 RAW + 截图量化（mask overlay 开/关各一张，亮度域断言）。
- **蒙版显示开关**：层行「显示蒙版」→ §3.2 overlay pass（黄色调 + 强度按 mask 值）；选中层才显示（dt 焦点语义）。
- **视口主导红线**：工具条浮于视口下缘（不撑 Inspector）；蒙版绘制手势与既有 crop overlay 手势互斥路由（编辑模式状态机，同 D-H1 归口）。

### 9. Golden / 验证策略

| 对象 | 轨 A（dt 证据） | 合成参考（L017 路线①） | 钉参 case 数（初值） |
|---|---|---|---|
| blend 公式（13+ 增补模式 × 线性/JzCzhz 两域） | 平场 PFM probe：XMP 历史项携 `blendop_params`（L015 hex 配方，blob 按 `dt_develop_blend_params_t` 逐字段 pack；`--core -d params` 验 version ok/params ok；`DEVELOP_BLEND_VERSION=14` blend.h:31）——平场 + 恒定 mask = 常数输出，逐值对照 | float64 Swift 逐式复刻（每模式一函数，与 kernel 同源公式表）；<1e-5 rel 点态门（03 门档） | 每模式 ≥3（opacity 0.25/0.6/1.0）× 域 2 |
| JzCzhz 感知模式 | 同上（hue/sat/color/luminosity 平场） | 往返式先行（L023：先写全往返恒等式 mo·M·mi ≈ I 再钉测试，Jz 往返 <1e-6） | 4 模式 × hue 全环 sweep |
| mask combine | dt-cli 不可达（mask 不落盘）——不适用 | 五式逐式单测（group.c:487-630 公式直译参考，含 inverted 分支）+ 合成形状 golden（两圆并/交/差解析面积断言） | 5 式 × 2（正/反） |
| drawn 光栅化 | 同上 | 解析断言：brush stamp 径向剖面（hardness 0/0.5/1）、gradient 直线剖面（linear vs sigmoidal，gradient.c:1201/1353 公式）、ellipse/path SDF；tile 缝 = 强制分块 vs 整幅 <1e-6 | 每形态 3 |
| parametric mask | 平场 probe（平场入 → 阈值内/外二元 → 常数 mask） | blendif 4 点曲线权重 float64 参考 + JzCzhz 换算交叉（filmic 链常量同源） | 4（luma/JzC/hue 三通道 × in/out） |
| 合成恒等三元组 | — | **全 mask=1 + normal + op=1 == 下层（逐字节）**；op=0 == 下层；空层/禁用层 == no-op；REVERSE 位 == a/b 交换 | 4（常驻回归） |
| 层栈序列化 round-trip | — | 3 层（含 mask + 非常规 blend）→ write → load → 参数逐字节 + UUID 恒等 + **渲染逐字节恒等**（L014 fence 纪律）；重排后重应用 == 重排快照渲染 | 3 |
| liquify/retouch | dt-cli 不适用（交互模块） | 扭曲场解析（单径向 grow 节点的位移场公式参考）+ heal 在合成 patch 上的收敛参考（小图 Python 复刻 dt_heal） | 各 3 |

- **轨 B 照旧**：全链 ColorSync 中性度 + 交叉一致性不回归（D-COL1）；层启用/禁用态均过。
- **dt 侧采纳证据模板**：blend probe 的 XMP 生成 = gen_fixtures.py 新增 `blendop_params_blob`（注意 blend blob 是每历史项一个，与 params blob 并列）——三证据（DB hex + `--d params` + 平场 PFM）照 03-02 定式，manifest 落账。

## Validation Architecture

1. **顺序**：6-1 层核全绿（退化合成 + 缓存/ROI 断言）→ 6-2 blend 引擎（blend parity 是一切局部效果的基座）→ 6-3/6-4 mask（依赖引擎的 mask 腿）→ 6-5 UI/round-trip 签核 → 6-6/6-7 liquify/retouch（依赖 mask 框架 + 几何映射器）。
2. **双闸**：ParityGate 双闸沿用（blend 点态 <1e-5 + Jz 往返 <1e-6；mask 解析 <1e-6；tile 缝 <1e-6）。
3. **内容级断言兜底（L020 对策③）**：合成恒等三元组与「分块==整幅」必须逐字节/数值级——纯记账测试对坐标错位免疫，Phase 4 教训直接复用。
4. **GUI 验收轮**（AGENTS.md Phase 执行模型硬性项）：真实 RAW + 多层 + 蒙版绘制的端到端走查 + PLAYBOOK 量化；mask 绘制手感入 Manual-Only 表。
5. **性能**：PREVIEW 拖动门（60fps，层 K 编辑场景）+ FULL 窗口化内存断言；signpost composite 段记账。

## Risks & Gotchas

1. **BlendMode 骨架值错位（已坐实）**：`normal=0x01`/`colorDodge=0x16` 与 dt raw 值语义错位（§4.1）——值冻结承诺与「case-for-case 映射 dt」的注释矛盾，必须由 planner/用户拍板处置（OQ2），**6-1 动工前定案**（sidecar 已携带这些值，拖延成本递增）。
2. **L018 mask 累积红线**：brush stamps 的累加禁 read_write 纹理 RMW——render-pipeline additive blending 主案 + 原型验证先行（§3.2 Med 点）；combine 的多平面 reduce 也走 kernel 参数数组非原地累积。
3. **L023 往返式先行**：JzCzhz 感知模式的 uniforms（RGB↔Jz 矩阵对）是半边契约——测试先写全往返恒等式；矩阵定义变更与断言同批提交。
4. **跨层 ROI 的 dscIn 语义（L021）**：每层子 run 独立 stamp；任何「层借用 base 的 dscIn/iscale」的捷径都是 double-scale 变体——常驻断言（每层 entry dscIn == 该子 run bufInROI 首元素）+ 内容级 golden 兜底。
5. **蒙版坐标锚定的映射器成本**：`GeometryPointMapper` 要求 5 个几何模块补点映射函数（Phase 4 模块的增量 API）——若 plan 期发现 lens/ashift 的逆向点映射精度不足（迭代求逆），降级方案 = 蒙版钉合成帧坐标（OQ7），**语义降级需用户认可**。
6. **retouch 源区跨窗**：heal/clone 的 patch 源可出视窗——modifyROIIn 需按 stroke AABB 扩窗，与 blend.c:493-500 的 `inside_roi` 分支同题；漏扩窗 = 源区黑边（内容级断言覆盖）。
7. **FULL 冷层重渲的重复成本**：冷层链输出不缓存 → 每次窗口变化全层重渲——若实测 fit 视图下 N 层全幅重渲超预算，回退「FULL 也缓存层输出」并把 FULL 平面预算入 enforceBudget 分档（数据驱动决策，plan 期 benchmark）。
8. **sidecar v2 迁移**：schemaVersion 2 的降级读路径（v1 文档无层栈）与「未知 op 透传」正交——round-trip 测试集须含 v1 文档样本；`stackSnapshot` 型 history item 的体积上限监控（千级 mask 点 × 百级 history 的极端栈）。
9. **liquify 与蒙版映射的耦合**：liquify 在 base 链时，mask 点映射必须含 liquify 位移场的逆采样——场构建失败/路径为空时映射器必须恒等直通（空 liquify 层是常态路径，回归覆盖）。
10. **L014/L022 常规适用**：读回前 fence；omp 执行期间本研究外零工作区写入。

## Plan 拆分建议（7 个，依赖序）

| Plan | 内容 | T 数（估） | 验收要点 |
|---|---|---|---|
| **6-1 层核与 sidecar v2** | `AdjustmentLayer` 具体类型（chain/mask spec 占位）+ `LayerCompositeDriver`（退化合成：normal/全 mask 直通）+ `PipeCacheKey.layerID` + 终端段摘出 + sidecar v2（层记录/历史 layerScope+stackSnapshot）+ BlendMode 处置定案执行（OQ2）+ 全套缓存/ROI/重排断言 | 6-7 | 恒等三元组逐字节；层 K 编辑增量 hit/miss 记账；v1 文档兼容读；重排后链缓存存活 |
| **6-2 blendop 合成引擎** | 线性域算术模式全表 + JzCzhz 往返 + 感知模式 + REVERSE 位 + 增补模式（dodge/burn/lighten/darken）+ float64 参考 + dt-cli 平场 probe（blendop_params blob） | 4-5 | 每模式 <1e-5；Jz 往返 <1e-6（L023 式）；平场三证据 |
| **6-3 drawn mask** | `GeometryPointMapper` + 五几何模块点映射 + drawn 四形态光栅化（stamping 原型先行的定稿）+ mask 平面缓存 + mask overlay 显示 | 6-8 | 解析断言逐形态；tile 缝 <1e-6；overlay 截图量化 |
| **6-4 parametric/raster/combine** | blendif（luma/JzCzhz）+ 后处理链（blur/feather/contrast）+ combine 五式 + raster 烘焙与旁挂 PNG + mask 组 | 5-6 | blendif 参考 parity；combine 逐式；raster round-trip + hash 校验 |
| **6-5 图层 UI 与签核** | LayersPanelView + 层选 Inspector 路由 + MaskToolbar/OverlayHost + 绘制手势 + history 全粒度接线 + E2E round-trip + GUI 验收轮 + Phase 6 前半签核 | 6-8 | 拖动=1 commit；重排/合并可退；PLAYBOOK 量化；全 suite 绿 |
| **6-6 liquify** | 扭曲场构建（CPU）+ warp kernel 直译 + 路径 overlay 交互 + 点映射接入（几何映射器含 liquify）+ 面板 | 5-6 | 位移场解析参考；恒等空路径直通；交互 overlay 验收 |
| **6-7 retouch（或拆 6.5）** | retouch 层 kind + stroke 模型 + clone/blur/fill GPU 腿 + heal 迭代核 + 源区扩窗 + retouch 面板/交互 | 6-8 | patch 收敛参考；源区黑边断言；交互验收（heal 可拆 6.5 → OQ1） |

依赖序：6-1 → 6-2 → (6-3 → 6-4 → 6-5) 与 6-6 可并行（6-6 只依赖 6-1/6-3 的映射器框架，排在 6-3 后）→ 6-7。总量 ~38-48 T——Phase 4（7 plans）+ Phase 5（8 plans）之上，符合「最大架构阶段」定级。

## Open Questions for Planning

1. **liquify/retouch 是否拆 Phase 6.5**：保持 Phase 6 尾部独立 plan（推荐——mask 框架就位后两者独立可签核）vs 正式拆出 6.5 里程碑；retouch 的 heal 迭代核是否可降级（先 clone/blur/fill，heal 后置）。
2. **BlendMode 骨架值错位处置**（§4.1/OQ1 风险）：值不重编 + 语义按现代公式 + 头注映射表（推荐）vs 0x01/0x16 弃用 + 新 raw 值 + sidecar 迁移。**6-1 动工前必须拍板。**
3. **parametric mask 的域面**：v1 单域 JzCzhz + luma（推荐，kernel 一个）vs dt 双域 UI（Lab + RGB 各一套曲线面板）。
4. **retouch 落位**：独立 retouch 层 kind（推荐）vs base 链模块（dt 原样）。
5. **层内几何模块**：v1 禁用（推荐，仅 base 层；UI 对层内 crop/lens 等隐藏或只读）vs 放开（ROI 协商跨层复杂度陡增）。
6. **层编组（文件夹）**：v1 defer 到 v2（推荐——MaskGroup 已覆盖蒙版组，层文件夹是纯 UX）vs v1 交付。
7. **蒙版坐标锚定**：内容锚定（dt 模型，需 GeometryPointMapper，推荐）vs 合成帧锚定（降级，crop 后蒙版随帧）。
8. **FULL 冷层缓存政策**：窗口化 + 冷层不缓存（推荐，benchmark 后回退）vs FULL 全层缓存 + 预算扩档。

## Sources

### Darktable（本地源码，树 dc58cf0ba1 2026-08-02，与 Phase 2-5 同；file:line 均已核）

- `src/develop/blend.h:31`（DEVELOP_BLEND_VERSION=14）、`:35-41`（blend CS 枚举）、`:44-91`（blend mode 全表：NORMAL_OBSOLETE=0x01 :47、NORMAL2=0x18 :70、REVERSE=0x80000000 :89）、`:92-103`（mask_mode 位：MASK/CONDITIONAL/RASTER）、`:105-118`（combine：NORM/INV/EXCL/INCL）、`:120-190`（blendif 通道集四域 + SIZE=16）、`:192-233`（`dt_develop_blend_params_t` 全字段含 blendif_parameters[64] 与 raster_mask_source）
- `src/develop/blend.c:32-39`（mask 后处理枚举 BLUR/FEATHER_IN/FEATHER_OUT/TONE_CURVE）、`:305-330`（_get_post_operations 组装）、`:458-530`（`dt_develop_blend_process`：a/b 语义、inside_roi 门 :493-500、mask_display 焦点门 :509-515、opacity CLIP :530）、`:552-571`（raster mask 经 dt_dev_get_raster_mask + invert）、`:664-710`（CPU feather 单通道 dt_gaussian）、`:814`（CL fast blur feather）
- `src/develop/masks.h:35-49`（form 类型位：CIRCLE/PATH/GROUP/CLONE/GRADIENT/ELLIPSE/BRUSH/OBJECT）、`:52-68`（state 位含 UNION/INTERSECTION/DIFFERENCE/EXCLUSION/SUM/INVERSE）、`:70-83`（property 枚举）、`:91-95`（gradient linear/sigmoidal）、`:146-213`（五类点结构逐字段）、`:358-371`（`dt_masks_form_t`：points/type/source/formid/version）
- `src/develop/masks/group.c:308-480`（_group_get_mask：逐 form 取 mask + state 分派）、`:487-630`（_combine_masks_union/intersect/difference/sum/exclusion 全公式含 inverted 分支）；`src/develop/masks/gradient.c:1113-1201,1271-1353`（linear/sigmoidal 剖面公式）；`src/develop/masks/{brush,ellipse,path,circle}.c`（共 ~15k 行光栅化/UI 参考）
- `data/kernels/blendop.cl:426-512`（blendop_mask_Lab/RAW/rgb_hsl/rgb_jzczhz 参数蒙版 kernel）、`:513-800`（blendop_Lab：模式 switch + LCh hue/sat/color :695-735）、`:802-1095`（RAW4 + blendop_rgb_hsl）、`:1096-1309`（blendop_rgb_jzczhz）、`:1310-1424`（blendop_mask_tone_curve）、`:1425-1473`（blendop_set_mask）、`:1474+`（blendop_display_channel 蒙版显示）、`:1681-1710`（Y0/scharr/detail 后处理）
- `src/iop/liquify.c:47`（MAX_NODES=100）、`:97-257`（layer/hit/UI 与 warp/node/path 结构）、`:218-223`（warp 类型）、`:307-321`（flags SUPPORTS_BLENDING、tags DISTORT|GEOMETRY、filter CROPPING|DECORATION）、`:323-330`（IOP_CS_RGB）、`:606-612`（路径经 dt_dev_distort_transform_plus 映射）、`:1390-1410`（process：拷贝→场→应用）、`:1418-1439`（lanczos/bicubic）、`data/kernels/liquify.cl:34-131`（warp_kernel 位移卷积）
- `src/iop/retouch.c:66-71`（四算法枚举）、`:221`（SUPPORTS_BLENDING|NO_MASKS）、`:224-231`（IOP_CS_RGB）、`:117`（max_heal_iter 2000）、`:248-261`（stroke 参数化记录）；`src/common/heal.c:354-422`（dt_heal 迭代 + CL 腿）
- `src/common/iop_order.c:96,100,205,207`（retouch 14.0/20.0、liquify 17.0/18.0 新旧表位）

### Lightamer 代码（现码，file:line 核过）

- `LightamerCore/Sources/Layers/{Layer,LayerStack,BlendMode,LayerKind,BackgroundLayer}.swift`（Phase 1 骨架全件；BlendMode 冻结值 :14-47 + 值错位记录见 §4.1）
- `LightamerCore/Sources/Pipe/PixelPipe.swift`（layerStack 字段 :59、pieces 排序 :447-450、levelHash :462-467、roiHint :493-500、forward walk + iscale stamp :508-538、子域渲染 :610-663、缓存键 :677-683、FULL 政策 :702、tile 驱动 :262-392、display tail :173-187、ROI precondition :719-722）
- `LightamerCore/Sources/Pipe/{ModuleBox,IOPModule,IOPiece,PipeCacheKey,PipeResolution,ROI}.swift`（ModuleBoxing 面、tileHalo seam、iscale、key 五字段、ROI clamp/union/aabb）
- `LightamerCore/Sources/Pipe/History/HistoryStack.swift:53-80`（HistoryItem.layerScope Phase 6 预留 :66）+ `ModuleInstance.swift`（冻结拼写）；`LightamerCore/Sources/Pipe/ModuleRegistry.swift`（effectiveInstances 扩展点）
- `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:82,98,138`（layerStack 预留 + schemaVersion）；`LightamerCore/Sources/Foundation/V50Order.swift:37-50,61-69`（几何/liquify/retouch/colorin 槽位）
- `App/Sources/Lightamer/State/{PipeCoordinator,EditorState}.swift`（pipe 生命周期、layerStack 安装 :280-281）；`App/Sources/Lightamer/UI/Inspector/`（IOPPanelProvider + 24 面板复用面 + CurveEditorView）；`App/Sources/Lightamer/UI/Overlay/`（CropOverlayHost 交互模式）

### 项目文档

- `.planning/ROADMAP.md` §Phase 6（:103-116，SC#1-5 + NDE-1/3、METAL-8、PERF-2 风险标注）+ §Phase 7（AI mask 以 Phase 6 raster/parametric mask 为消费端 :129-130）
- `.planning/REQUIREMENTS.md`（LAYER-01..07 :105-111、IOP-MASK-01..05 :117-121、IOP-GEO-05/06 :98-99、映射表 :328-341）
- `.planning/phases/05-color-denoise-iops/05-RESEARCH.md`（体例范本 + TilingPlan 多消费者纪律 + L017 分流表定式）；`.planning/phases/04-geometry-lens-detail-iops/04-CONTEXT.md`（ROI 端到端 + liquify/retouch defer 移交）
- `LESSONS.md` L005（层先行）/L013（显式折叠）/L014（fence）/L017（dt-cli 分流）/L018（RMW 红线）/L020（ROI 坐标系）/L021（dscIn 禁 ×scale + GUI 验收红线）/L022（omp 期间零写入）/L023（半边契约全往返）
- `.planning/research/PITFALLS.md`（NDE-1/3、METAL-8、PERF-2 原文）；`.work/gui-acceptance/PLAYBOOK.md`（GUI 验收操作口径）

---

*Phase 6 Research — 2026-09-21。产物仅本文件；未提交 git。*
