# Phase M2-6: DRT（ACES 2.0 + OpenDRT）— Context

> discuss/research 起草稿（2026-09-29）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` **§5 显示渲染变换 DRT**（面板结构/预设三件套/45 detailed 参数/EOTF 联动表/HDR 判定/实现来源）+ §2.6（Detail 面板 = DRT/Post 四件套）；需求 = REQUIREMENTS **M2DRT-01..06**；ROADMAP M2-6 行。衔接面 = M2-4 交付的 `PipelineDocument` 端点语义（DRT = 灰态占位终点，`displayTransformNodeID` 固定 UUID）+ M2-3 七页签 Display Transform 页占位（`displayTransformPlaceholder` 特面）+ Phase 8 EDR display leg + `NodeOwnershipCatalog` 的 `.drtPost` 四席位。**本 CONTEXT 面向夜间授权裁决**（文末「夜间授权预案」：按推荐自主生效、晨审可推翻）。

## Phase Boundary

**范围**（ROADMAP M2-6 行 + M2DRT-01..06）：

1. **DRT 节点 + 面板**（M2DRT-01）——Method 分段卡（ACES 2.0/OpenDRT）恒展开；默认 OpenDRT；面板挂 Display Transform 页（替换 `displayTransformPlaceholder` 占位特面，Vignette 行原地保留——checker E1 勘误边界不动）。
2. **OpenDRT 预设三件套**（M2DRT-02）——Look 7 + Tonescale 15 + Creative White 6；detailed 参数组 editor-owned 整体序列化（预设 = 具名快照）。
3. **ACES 2.0**（M2DRT-03）——Limiting Space 七选 + reference gamut compression 前置。
4. **Color & Encoding**（M2DRT-04）——Encoding Space 六选 + EOTF 随空间联动 + Peak Luminance 100-1000 nits；HDR 判定（EOTF∈{ST2084,HLG}）驱动 EDR 预览与导出链。
5. **DRT/Post 四件套**（M2DRT-05）——Clarity/Sharpen/Halation/FilmGrain 在 display transform 后对全图应用一次（预览 = 成品）。
6. **DRT method 扩展位**（M2DRT-06）——filmic/sigmoid/agx 按 D1 v1 禁用；架构预留 method 注册口。

**非目标（本 phase 明确不做）**：

- **导出 writer 集成**（M2-9）——本 phase 交付 EOTF 编码核 + HDR 判定 API + 视口链；导出队列/ICC 联动/尺寸模式归 M2-9（ROADMAP M2-9 行明文「输出 ICC = 本图 DRT 编码强制联动」届时接线）。
- **图库 HDR 标志位**（M2-2 库面）——判定 API 交付，`.lalb` 投影列消费归库面后续 plan。
- **filmic/sigmoid/agx 的 DRT method 实现**（M2DRT-06 明文 v1 禁用）——只落注册口形状，零 method 注册。
- **detailed 参数编辑 UI**——FEATURE-MAP §5 明文「UI 面板只暴露预设三件套」；45+ detailed 参数 = editor-owned 序列化数据面（预设快照），不开 stickshift 编辑面（Alcedo 亦默认隐藏）。
- **Alcedo v0.2.3 已知损坏项的继承**——FEATURE-MAP 记「ACES 2.0 的 HDR 峰值亮度路径在 v0.2.3 已知损坏」；本 phase 按 aces-core 规范直实现（OQ-3），不读其 metal 移植反推。

## Existing Code Insights

### 关键语义发现（本 phase 方向裁决的地基，2026-09-29 Grep 实测）

1. **jedypod/OpenDRT 上游许可 = GPLv3，不是 MIT**——本地 dctl 存档头 `OpenDRT.dctl:7` 明文 `License: GPLv3`，上游 GitHub 仓（jedypod/open-display-transform）同样 GPLv3。**简报里「MIT?」假设不成立**。GPL 红线与 M2GRADE-07 / darktable 参考先例同款：只读参考算法思路、**零代码拷贝入库**（本项目 MIT）。对比：**aces-core（ampas/aces-core）= AMPAS BSD 风格许可**（Alcedo 仓 `third_party_licenses/aces-core-LICENSE.md` 全文在案 + 上游核实）——可带署名直接移植。
2. **Alcedo DRT 参数实态 = 12 顶层字段 + 53 个 detailed 浮点**，不是 45——`drt_node_model.hpp:31-85` `OpenDrtDetailedParams` 逐字段清点：tn 系 9 + cwp_lm 1 + rs 系 3 + pt_lml 系 4 + pt_lmh 系 3 + ptl 系 3 + ptm 系 6 + brl 系 6 + brlp 系 4 + hc 系 2 + hs 系 12 = **53**。ROADMAP/REQUIREMENTS 的「45」系少计（schema 按实际枚举落，文档数字随验收勘误注记，不回改 REQUIREMENTS 原文）。顶层 `DrtPayload`：method/encoding_space/encoding_eotf/limiting_space/peak_luminance/look_preset/tonescale_preset/creative_white + creative_white_limit(0.25)/display_grey_luminance(10)/hdr_grey_boost(0.13)/hdr_purity(0.5)；默认 method = **OpenDRT**、Rec709/Gamma2.2、peak 100。
3. **Post 四件应用域两处文档冲突——以「DRT 之后」为准**：`drt_node_model.hpp:189-191` 注释称四件「run in ACEScc **before** the display transform」，但 FEATURE-MAP §2.6 实测 Alcedo 0.3.0 QML 行为 =「**在 display transform 之后**对全图应用一次（预览与成品一致）」，ROADMAP M2-6 行 + M2DRT-05 亦明文「DRT 后」。hpp 注记判过时文档；管线语义按 M2DRT-05 落。
4. **端点缝已钉死，M2-6 是「填实体」不是「开门」**——`PipelineDocument.swift:38` `displayTransformNodeID` 编译期常量 UUID（"DRT00000-..."）；`displayTransform` 节点恒 `isEnabled: true`/`mix: 1`/`isDeletionLocked: true`；`NodeGraphCommand.swift:172,190` 删除/插入边界已拦截 DRT id；`EditorTabRoute.swift:171` `displayTransformPlaceholder` 特面 + `:254` displayTransform 页当前只有 Vignette 行。M2-6 换占位文案为真面板 + 落渲染实体，图拓扑零改动。
5. **EDR display leg = DRT 终端交接的现成模式**——`PixelPipe.swift:135` `edrDisplayLeg`（`setEDRDisplay` 手动开关 + `PipeResolution != .thumbnail` 门）：EDR on 时 **gamma 尾降级禁用**（`:649,873`）、float32 colorout 平面直写 16F drawable（tag `extendedLinearSRGB`）。DRT 激活时对 colorout/gamma 的接管可复用同一「尾段降级」缝；`EDRHeadroomMonitor`（被动读出 `maximumExtendedDynamicRangeColorComponentValue`）为 HDR 监看判定输入。
6. **D1 三件套禁用缝 + `.drtPost` 席位已备**——`Registry.swift:39` `defaultFaceDisabledOpNames` = filmicrgb/sigmoid/agx（D1）+ 降噪三件（D2），`gatedRegister` 单缝收窄；`NodeOwnershipCatalog.swift:44` `drtPostOpNames` = sharpen/**grain**(=FilmGrain)/**bloom**(=Halation)/**equalizer**(=Clarity) 四席已注册 owner `.drtPost`（M2-3 面板矩阵里在 Look 页挂 `panel_note_pre_drt` 占位注）。M2-6 兑现 = 四件真渲染语义（DRT 后全图一次）+ Look 页注记摘除。
7. **sidecar 已到 v5**（`LightamerSidecar.swift:141`，M2-4 升 v4→v5 additive）——DRT 参数无家，需 **v5→v6 additive**（document 级新 record；decodeIfPresent + 读者容忍 + hash 判定惯例正本同文件）。`.lalb` 四表零触碰（`.lra` 恒编辑态真相红线）。
8. **100MP 渲染预算基线**（M2-4-0-SPIKE）——PREVIEW 桶硬帽 2560px（`PreviewBucket.cap`，float32 ≈70MB/平面）；FULL 平面 100MP float32 ≈1.6GB/张、toneequal FULL tiling 内存验证 <3GB（实测峰值 7.8GB 工作集为测试自身属性）；100MP 预算内做 per-pixel 全图单 pass 可行（无邻域扩展），邻域型（Post 四件）复用既有 tiling/bloom 资产。

### Reusable Assets

| 资产 | 位置 | M2-6 复用判定 |
|---|---|---|
| `PipelineDocument.displayTransformNodeID` + 端点三重固定语义 | `LightamerCore/Sources/Graph/PipelineDocument.swift:38` | **DRT 实体挂接点**——面板选中路由/节点卡渲染直接消费，图拓扑零改 |
| `displayTransformPlaceholder` 特面 + Display Transform 页 | `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift:171,254` | **面板落点**——占位特面替换为 DRT 面板（Method 卡恒展开） |
| `edrDisplayLeg` 尾段降级缝 + `EDRHeadroomMonitor` | `LightamerCore/Sources/Pipe/PixelPipe.swift:135,649` / `App/Sources/Lightamer/State/EDRHeadroomMonitor.swift` | **HDR 视口交接先例**——DRT 激活/HDR 判定的 colorout/gamma 语义接管同模式 |
| `gatedRegister` + `defaultFaceDisabledOpNames` | `LightamerIOP/Sources/Registry.swift:39,77` | **D1 扩展位形状参照**——method 注册口同款「单缝收窄/回切」思路 |
| `drtPostOpNames` 四席位 + Look 页 `panel_note_pre_drt` 注 | `LightamerIOP/Sources/NodeOwnershipCatalog.swift:44` + `EditorTabRoute.swift:215-236` | **Post 四件归属已定**——M2-6 摘注 + 激活 display-referred 应用语义 |
| Sidecar v5 additive 惯例（decodeIfPresent/读者容忍/hash-isolation 判定/canonical 字节稳定） | `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:86-141` | **v6 升版正本**——document 级 `displayTransform` record 照惯例落 |
| `HistoryStack` + history 键族惯例 | `App/Sources/Lightamer/State/EditorState.swift` | DRT 参数编辑 = document 作用域 history item（预设应用 = 单 discrete commit，M2-5-2 Reset wheels 先例） |
| Bloom/Sharpen/Grain/Equalizer 四 kernel + tiling | `LightamerIOP/Sources/{Bloom,Sharpen,Grain,Equalizer}` | **Post 四件内核复用**——域适配（display-referred 输入）注记进 plan |
| golden harness + Swift Float64 参考先例（M2-5-1：linear 域比较 + p99.9≤1e-5 分级容差） | `Tests/` + `phases/m2-5-color-grade/M2-5-1-ACCEPTANCE.md` | **DRT golden 方法论**——OQ-11 依据 |
| zh-audit 对账惯例（随手键 + phase 尾 `Scripts/zh-audit.py --check`） | M2-3-4/M2-4-3 先例 | OQ-12 依据 |

### Integration Points

- **管线位置**：DRT = composite 后的**文档级终端段**（C_N → DRT → Post 四件 → EOTF 编码 → 显示/导出），非 v50 iop、非 ModuleInstance（OQ-8）；colorout/gamma 终端对在 DRT 激活文档上的接管沿 EDR leg 降级先例。
- **App/Core 边界**：DRT 参数模型 + EOTF 联动表 + HDR 判定落 Core（可单测；沿「sidecar 读写器放 Core」原则）；SwiftUI 面板落 App（`UI/Shell/` Display Transform 页）。
- **M2-5 ACEScc 域衔接**：Grade 输出（ACEScc envelope 末端 = linear Rec2020）→ DRT 输入；DRT 内部自管 ACES 空间变换（in_gamut 固定 = 我们的 working space，不露 Alcedo dctl 的 15 种输入 gamut 菜单——v1 输入恒 linear Rec2020 scene-referred，OQ-3 附注）。

## Open Questions（每条含推荐；夜间授权按推荐生效）

### OQ-1 OpenDRT 实现来源与许可路径（必裁——GPLv3 实核推翻 MIT 假设）
- **A（推荐）**：**独立实现（read-only 算法参考）+ 数值预设表转录 + NOTICE 署名**——GPLv3 红线同 darktable/M2GRADE-07 先例：走读 `OpenDRT.dctl`（86KB 算法正本）与 Alcedo 移植层只取**算法思路**，Metal/Swift 全部自写；预设三件套的**参数数值表**（tn_con 1.66、look0-6 各字段组合等）按「数值事实」转录为 Swift 数据表，`NOTICE` 记 provenance（jedypod/open-display-transform v1.1.0, GPLv3——参考实现未复制代码）。
- B：严格 clean-room（只读规格文档不读代码）——dctl 即唯一算法文档，不读代码 = 无法实现，不成立。
- C：直接移植 dctl 代码段并 GPL 兼容声明——本项目 MIT，v1 不接受代码传染； licensable dual-license 无上游意愿，不可行。
**推荐 A**；预设数值转录的「事实/表达」边界风险（数值表通常不构成版权表达，但非零）在 NOTICE 显式记录；用户若不愿承担，退路 = 参考数值手工等效调校（plan 前向用户确认一次）。

### OQ-2 DRT 参数持久化 schema 与预设快照机制（M2DRT-02）
- **A（推荐）**：**sidecar v5→v6 additive，document 级 `displayTransform` record**——新 `DrtRecord`（12 顶层字段 + `OpenDrtDetailedParams` 53 浮点单 Codable 嵌套对象，全字段 Optional decodeIfPresent，nil = 默认 OpenDRT/Rec709/G2.2/peak100）；canonical 字节稳定（encodeIfPresent，旧档零漂移）；**hash 判定 = set-fields-move**（DRT 参数影响渲染 → 进 `historyHash`，沿 v5 蒙版字段先例，非 rawOverrides 式 hash-isolation）；预设 = 内置具名快照（三件套 preset → detailed 参数组的映射函数），应用预设 = 一次原子 discrete commit（undo 一步回）；「custom」判定 = 当前参数组不匹配任何内置快照时标 custom（派生展示值，不持久化额外字段）。
- B：DRT 挂成 base 链内 ModuleInstance（paramsData 复用）——语义错位：DRT 是文档级终点非层链成员；渲染序也错（base 链先于 composite，晚于它运行的 grade 会被跳过），且 ownership 校验面要开新洞。
- C：`.lalb` 列承载——违 `.lra` 恒编辑态真相红线 + 四表激活序。
**推荐 A**；`DrtRecord` 落 `LightamerCore/Sources/Graph/`（与 PipelineDocument 同目录，EditorState 单写者）。

### OQ-3 ACES 2.0 实现范围与来源（M2DRT-03）
- **A（推荐）**：**aces-core（AMPAS BSD）移植 + v1 子集 = ODT 参数化模型 + Limiting 七选**——ACES 2.0 ODT = JMh（CAM16）参数化 tonescale + limiting 编码（aces-core CTL 为 BSD 风格，可带署名直接移植：`NOTICE` 署 AMPAS）；Limiting Space 七选（Rec709/Rec2020/P3-D65/P3-D60/P3-DCI/ProPhoto RGB/Adobe RGB）= 七组 limiting primaries/矩阵数据表；**不落新 LMT 面**（LMT CUBE 已是 Grade 域既有 op，M2GRADE-01）；输入 gamut 恒 linear Rec2020（不露 dctl 的 15 种输入菜单）。HDR peak 路径按 aces-core 规范直实现（不继承 Alcedo v0.2.3 损坏项）。
- B：v1 全量移植 aces-core（RRT+全部 ODT+LMT 族）——体量失控，面板面只用其中一小块，违 YAGNI。
- C：走读 Alcedo `drt_aces.metal` 反推实现——GPL 只读参考可以，但其实现自带 v0.2.3 已知损坏 + BSD 上游可直接移植，绕路无益。
**推荐 A**；移植边界（哪些 CTL 函数进 kernel、362 项 reach 表等数据表经营收后 vendored）留给 plan。

### OQ-4 reference gamut compression 前置件归属（M2DRT-03）
- **A（推荐）**：**DRT 内置前置段，非独立 op、非用户参数面**——ACES reference gamut compression（P3/Rec709 limiting 外的广色域收敛）作为 ACES 2.0 method kernel 的固定前置 stage（可开关常量，默认 on，Alcedo 同款「DRT 前置」语义）；不进节点图、不进 18 目录、不占 ownership 面（OpenDRT method 自带 render-space purity 处理，无此前置）。
- B：独立 gamut iop（用户可单独启停）——超 Alcedo 面板面、节点图语义污染（无对应 UI 手势）。
- C：不做 gamut compression——ACES 2.0 规范行为缺块，limiting 到小色域时高饱和裁切伪像，规格不符。
**推荐 A**。

### OQ-5 Encoding Space/EOTF 联动表实现（M2DRT-04）
- **A（推荐）**：**纯函数数据表 + 切换吸附**——Core 单源 `legalEOTFs(for space:)`：Rec709→{BT.1886, G2.2}；P3-D65→{G2.2, PQ(ST2084)}；P3-D60/P3-DCI/XYZ→{G2.6}；Rec2020→{PQ, HLG}（模型层 EOTF 枚举全 7 值 = Linear/ST2084/HLG/Gamma2.6/BT.1886/Gamma2.2/Gamma1.8，UI 暴露合法子集——FEATURE-MAP §5 联动表逐行照抄）；切空间时当前 EOTF 非法 → 吸附到该空间首个合法值（单 discrete commit）；纯函数全枚举单测钉死。
- B：UI 层硬编码 if-else——联动知识散落视图层，M2-9 导出 ICC 联动（「输出 ICC = 本图 DRT 编码强制联动」）无 Core 级可消费源。
- C：开放全组合任选——违 Alcedo 联动语义（非法组合产生无意义输出）。
**推荐 A**。

### OQ-6 HDR 判定 → EDR 视口联动（M2DRT-04 前半：预览腿）
- **A（推荐）**：**判定纯函数 + 尾段接管变体**——`IsHdrEncoding(eotf) = eotf ∈ {.st2084, .hlg}`（Core 纯函数，Alcedo `IsHdrExportEncoding` 同语义）；DRT 激活文档上 colorout/gamma 终端对降级（复用 `edrDisplayLeg` 的「尾段 demote」缝，新增 `drtTailActive` 条件）：SDR = DRT EOTF 编码核产 8bit 显示平面（EOTF 编码 + encoding space 原色 → drawable colorSpace 匹配，现 colorout/gamma 语义由 DRT 尾段继承）；HDR（PQ/HLG）= EOTF 编码值直写 16F drawable + `CAMetalLayer.colorSpace` 切对应编码 space（PQ/HLG colorSpace，macOS 原生支持），EDR headroom 为被动读出（`EDRHeadroomMonitor` 现面不动，非 EDR 屏上 HDR 编码降容显示不阻塞——走查观察项）。非 DRT 文档（理论上 M2-6 后 DRT 恒在，但 env 回切/降级路径）行为逐字节不变。
- B：HDR 预览走「PQ 解码回 linear + 复用现 EDR 线性腿」——双重变换精度损失 + 与导出编码不一致（违「预览=成品」）。
- C：手动开关（沿用现 EDRControlView 语义）——HDR 判定是参数派生事实（M2DRT-04 明文「驱动」），手动开关 = 状态漂移。
**推荐 A**；colorSpace 枚举与 PQ 绝对/相对映射（peak nits → layer 语义）细节 plan 定。

### OQ-7 Peak Luminance 语义与导出联动缝（M2DRT-04 后半：导出腿）
- **A（推荐）**：**峰值 = tonescale limiting 输入 + 导出元数据缝，本 phase 只交付编码核与判定 API**——Peak 100-1000 nits 进 DRT tonescale（tn_Lp， limiting/gray boost 语义）+ HDR 导出时映射 PQ mastering 元数据（maxCLL/maxCLF 载荷形）；导出渲染腿 = EOTF 编码核复用（与视口同核），writer/ICC/队列集成归 M2-9（ROADMAP M2-9 行明文 ICC 联动）——本 phase 交付「给定 DrtRecord + 像素 → 编码后平面」的纯函数缝 + `IsHdrEncoding` API，并钉单测。
- B：本 phase 连导出 writer 一起做——M2-9 边界被吃，队列/尺寸/元数据语义连锁重排，phase 爆量。
- C：peak 只影响视口不影响导出——违「预览=成品」（M2DRT-05 语义延伸）。
**推荐 A**。

### OQ-8 DRT 管线挂接与终端三件交接（架构必裁）
- **A（推荐）**：**composite 后文档级终端段，非 v50 iop**——渲染序 = C_N（composite 末端）→ DRT 变换 → Post 四件（全图一次）→ EOTF 编码 → 显示/导出平面；DRT 状态 = document 级 `DrtRecord`（OQ-2），编辑走 document 作用域 history item（新 `history_drt_*` 键族）；colorout/gamma 终端对在 DRT 尾段激活时降级（OQ-6 缝）；v50 表零新增槽（DRT 非 iop，与 M2-1 禁用的 45.x 三件无槽位关系）。
- B：DRT 做成 v50 iop（占 46.x 槽）注册进 registry——层链归属错误（DRT 必须在全部 grade composite 之后，而任何层链都先于后续层 composite 运行，结构上放不进层链）；b 案即 OQ-2-B 的渲染面翻版。
- C：重建 pixelpipe 终端编排——现终端三件 + EDR leg 缝已支撑降级语义，重写零收益全量回归风险。
**推荐 A**；Post 四件在此终端段内单 pass 应用（邻域型复用既有 tiling/bloom 基建，OQ-9）。

### OQ-9 Post 四件套应用域与内核复用（M2DRT-05）
- **A（推荐）**：**DRT 之后 display-referred 应用一次 + 既有 kernel 域适配**——序 = DRT 输出（display-referred，EOTF 前）→ Clarity(equalizer)/Sharpen/Halation(bloom)/FilmGrain 全图一次 → EOTF 编码；四 kernel 复用既有实现（`drtPostOpNames` 四席位），输入域从 scene-referred 换 display-referred 的适配（强度标定/钳制）注记进 plan，golden 按 display-referred 参考重钉；Look 页 `panel_note_pre_drt` 注摘除，UI 家不动（仍 Look 页 Look 组——M2-3 IA 既定，不新开 Detail 页签，偏离 Alcedo 面板归属一处、已属 M2-3 裁定范围）。
- B：跟 hpp 注释做 ACEScc 域 DRT 前——与 FEATURE-MAP §2.6（0.3.0 行为 = DRT 后）和 M2DRT-05 明文双冲突，grain/halation 被 tonescale 压缩的语义也不成立。
- C：四件重写专用 kernel——既有四 kernel 已过 golden/tiling 验证，重写零收益。
**推荐 A**。

### OQ-10 100MP 性能策略（per-pixel 大算子预算）
- **A（推荐）**：**参数 buffer 化 + 单 PSO 常驻 + 既有分辨率分桶，不做分段编译**——DRT/OpenDRT/ACES 2.0 全部 per-pixel 无邻域（53 参数经 `MTLBuffer` 传入，非 function constant → **参数拖动零 PSO 重编译**，单 kernel 单 PSO 常驻 PSO 缓存）；PREVIEW 桶（2560 帽）天然限交互预算；FULL/导出 = 单次全图 pass（100MP float32 ≈1.6GB/平面 × 单读单写在 <3GB 预算内，无 toneequal 式多平面叠加以避 1.6GB×N）；Post 四件邻域腿沿既有 tiling（OQ-9）；bench 行（全图 DRT pass @24MP/100MP 计时）挂验收观察行，60fps 复验归 M2-11（既有惯例）。
- B：分段编译（function constant 折叠参数特化）——参数高频拖动场景每次重编译反成卡顿源，且 53 参数空间特化爆炸。
- C：PREVIEW 降参（简化参数集渲染预览）——违「预览=成品」明文。
**推荐 A**。

### OQ-11 golden 参考来源与测试策略（DRT 无 golden 先例）
- **A（推荐）**：**自建 Swift Float64 参考实现（M2-5-1 先例）+ dctl 走读交叉验证 + 确定性探针输入**——CPU Float64 参考实现 DRT 数学（OpenDRT tonescale/purity/brilliance 链 + ACES 2.0 JMh ODT），Metal kernel 对齐参考（linear 域比较 + p99.9 分级容差，Grade golden 同款）；dctl/上游只作代码走读对照（数值抽检），**GPL 管线渲染的参考图不入库**（ Licensing 风险 + 不可自动化）；确定性 = 固成合成探针（linear ramp/色卡网格/极饱和探针）输入，per-pixel 无邻域 → 同 PSO 位精确确定；ACES 2.0 侧加 aces-core CTL 数值抽检（BSD 源直接对数）。
- B：jedypod 上游参考渲染图作 golden——GPL 污染疑虑 + 依赖外部渲染环境（Resolve/Nuke）不可自动化。
- C：只测 round-trip/无 crash 不对数值——DRT 是视觉终态核心，无 golden = 回归裸奔。
**推荐 A**。

### OQ-12 DRT method 扩展位 + zh 键预估（M2DRT-06 + 惯例）
- **A（推荐）**：**枚举 + 映射表注册口，零 method 注册；zh 随手键 + 尾对账**——`DrtMethod` 枚举（aces20/opendrt + 预留 case 不入 UI）+ method→kernel/序列化映射 switch 穷举（无 default，机检纪律）；filmic/sigmoid/agx **v1 不注册**（M2-1 `defaultFaceDisabledOpNames` 缝不动，三个 iop 模块原地保留）；D1 兑现 = 注册口形状交付（「parity 后评估回归」的挂账面）。zh：面板组标签/方法名/提示/四件套标签 ≈ 30-50 键随手 `String(localized:)`，收口批 `zh-audit --check` 补齐；**预设名（standard/arriba/…）/空间名（Rec.709/…）/EOTF 名（BT.1886/PQ/HLG/…）为技术专名不译**（zh 值 = 英文原文）。
- B：v1 就注册 agx 作为第三 method——D1 明文禁用、无验收面，抢跑。
- C：不落注册口只留注释——M2DRT-06 明文「架构预留 DRT method 注册口」是交付物。
**推荐 A**。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §5（DRT 面板/预设/45 参数/EOTF 联动/HDR/实现来源正本）+ §2.6（Post 四件 0.3.0 行为）
- REQUIREMENTS M2DRT-01..06；ROADMAP M2-6 行 + M2-9 行（导出 ICC 联动明文）
- 上游（只读）：`/Volumes/UNITEK/Documents/Development/AlcedoStudio/alcedo_studio/src/config/DRTs/OpenDRT.dctl`（jedypod v1.1.0 存档，`License: GPLv3` 于 :7）+ `src/include/edit/graph/drt_node_model.hpp`（GPL-3.0，参数模型/联动语义参考）+ `third_party_licenses/aces-core-LICENSE.md`（AMPAS BSD 全文）
- `LightamerCore/Sources/Graph/PipelineDocument.swift:38`（端点语义）+ `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift:171,254`（占位特面）+ `LightamerIOP/Sources/Registry.swift:39`（D1 缝）+ `LightamerIOP/Sources/NodeOwnershipCatalog.swift:44`（.drtPost 席位）
- `LightamerCore/Sources/Pipe/PixelPipe.swift:135,649`（EDR leg 降级缝）+ `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:141`（v5 additive 惯例）
- `phases/m2-4-node-model/M2-4-CONTEXT.md`（CONTEXT 惯例 + 端点裁定 D-M2-4-CONTEXT-1/6/7）+ `phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md`（100MP 预算基线）

## Specific Ideas（起草倾向，plan 细化）

- `DrtRecord` + `DrtMethod`/`DrtEotf`/`DrtEncodingSpace`/`DrtLimitingSpace` 枚举 + `legalEOTFs(for:)` + `IsHdrEncoding` 单文件落 `LightamerCore/Sources/Graph/DrtRecord.swift`——「联动/HDR 判定知识单文件承载」，防散落。
- 预设三件套快照表 = Swift 数据文件（`DrtPresets.swift`：look0-6 → detailed 参数字典 + tonescale 14 值表 + creative white 白点 xy）——`NOTICE` 记两处 provenance（jedypod 数值转录 / aces-core 数据）。
- DRT 面板 ViewModel（`DrtPanelModel`）订阅 document 级 DrtRecord + 写经 EditorState（document 作用域 commit），预设应用 = 单 discrete commit——M2-5-2 ColorWheelsPanelView 的 reset/commit 模式直搬。
- 渲染尾段 = `PixelPipe` 新 `drtTail` 段（DRT + Post + EOTF 三 stage 编排），`drtTailActive` 与 `edrDisplayLeg` 互斥收敛为一个尾段策略枚举——防两套 demote 布尔打架。

## Deferred Ideas

- detailed 参数 stickshift 编辑 UI（Alcedo 亦注释态隐藏；用户诉求出现再议——DrtRecord schema 已承载，只欠面板）。
- 输入 gamut/OETF 菜单（dctl 15 种 in_gamut）——v1 输入恒 working space；外部文件挂载场景归 M2-9 后评估。
- Alcedo `DrtDirty` 三组脏标记粒度——Lightamer 走 paramsHash 全量失效已够（终端段重算 ~ms 级）。
- 图库 HDR 标志 `.lalb` 投影列（判定 API 已交付，库面消费归后续）。

---

## 夜间授权预案（2026-09-29 起草时点）

本 CONTEXT 提交夜间授权裁决：若无人干预，D-M2-6-CONTEXT-1..12 = **OQ-1..12 全部按推荐 A 生效**。晨审可推翻：推翻任一条 = 修订对应 plan（CONTEXT OQ 原文不改、以 Ruling/勘误注记为准，沿 M2-4-CONTEXT 先例）。plan 期需回填的悬决点（非 OQ 级）：①预设数值转录的许可边界最终确认（OQ-1 附注的用户确认点）；②ACES 2.0 CTL 移植函数清单与数据表经营收（OQ-3）；③PQ/HLG drawable colorSpace 枚举与 peak→layer 映射（OQ-6）；④Post 四件 display-referred 强度标定（OQ-9）；⑤`drtTail` 与 `edrDisplayLeg` 收敛后的策略枚举形状（Specific Ideas）。

---

## Ruling（夜间授权，晨审可推翻）

（待裁）
