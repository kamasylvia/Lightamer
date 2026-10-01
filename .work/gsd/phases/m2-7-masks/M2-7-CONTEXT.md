# Phase M2-7: 蒙版体系（Alcedo + Nitro） — Context

> discuss/research 起草稿（2026-09-29）。规格锚点 = `research/ALCEDO-FEATURE-MAP.md` **§4 蒙版体系**（Radial/LinearGradient 参数全表 / mask 级属性 / 应用次序 / 编辑交互 / Mask Groups 面板 / MaskContentRevision 乐观并发）+ §1.3（蒙版编辑 / Default Behavior 设置）+ §1.4（设置页）；需求 = REQUIREMENTS **M2MASK-01..07**。衔接面 = **M2-4 刚交付的蒙版数据面**（`MaskGroupItem.enabled/displayName` + `MaskSpec.deletionProtected` v5 additive、`maskItems`/`setItemEnabled`/`setItemDisplayName` 访问面、`PipelineDocument.maskGroups` 组序=grade 序投影、deletionProtected clear+fill 拦截、`PipelineLinkageTests` 5 例）+ **M1（Phase 6/7/13-3）蒙版存量**（drawn 四形态 + rasterizer stamping 0.744ms/千枚 + combine 五式 + parametric luma/JzCzhz + raster + 手柄 overlay + MaskCommand 五命令 + Vision 主体/点选蒙版）。**本 CONTEXT 面向夜间授权裁决**（文末「夜间授权预案」节：按推荐自主生效、晨审可推翻）。

## Phase Boundary

**范围**（ROADMAP M2-7 行 + M2MASK-01..07）：

1. **Radial / LinearGradient 参数对齐**（M2MASK-01/02）——Alcedo 参数表（center 0.5/0.5、major/minor 0.5、rotation、inner/outer feather；origin/normal/transition 0.2/start 1→end 0）与既有 ellipse/gradient 形态的映射或 additive。
2. **Brush 对齐**（M2MASK-03）——Phase 6 stamping brush 与 Alcedo 笔划/revision/乐观并发模型对齐。
3. **mask 级属性与语义**（M2MASK-04）——display_name/enabled/opacity/invert/feather/deletion_protected + **应用序 = feather→invert→opacity→clamp**（`mask_model.hpp:188-199`）；sidecar `deletionProtected` 文件载体补缺（D-M2-4-1-3 挂账）。
4. **蒙版编辑 UI**（M2MASK-06）——图上绘制 + 手柄 overlay 对齐 Alcedo、Mask Groups 面板（组序=grade 序拖动、蒙版缩略图 GPU 管线、锁删提示、Locate unfinished node 提示）、Default Behavior 三选。
5. **Nitro 扩展**（M2MASK-05）——Follow Edges 边缘感知笔刷（IOP-MASK-06 提级 V1）+ Luminance/Color Range（内核复用、UI 按 Nitro）+ AI Subject 入口（subject+invert sugar）。
6. **蒙版内容单调 revision + 乐观并发**（M2MASK-07）——含 D-M2-4-2-5 stroke 腿 sibling payload 缺口修复（DECISIONS 钦定同批复核）。

**非目标（本 phase 明确不做）**：

- **Grade 参数本体 / 色轮 / DRT**——M2-5/M2-6 各自的地盘；本 phase 蒙版只挂 grade 所有权投影。
- **IOP-MASK-07 Depth 深度蒙版**——V2 节（ROADMAP :352），数据面依赖（AVDepthData），不入本 phase。
- **蒙版与 Darktable 互通**——sidecar/预设不互通已终裁；本 phase 一切对齐只面向 Alcedo/Nitro 的**语义与交互**，不面向其文件格式。
- **节点图结构**——M2-4 已交付（PipelineDocument/图命令/Reconnect），本 phase 只消费投影面。
- **retouch/liquify overlay**——各自 Editing 腿独立（`LayerEditingState` 四路由 mutex 既有），零触碰。

## Existing Code Insights

### 关键语义发现（本 phase 方向裁决的地基，2026-09-29 Grep 实测）

1. **蒙版底座存量远超 ROADMAP 行文暗示——M2-7 主体是参数对齐 + UI 面，内核新增仅 Follow Edges 一项**。Phase 6 已交付：drawn 四形态 frozen（`MaskSpec.swift:164-167` brush/path/ellipse/gradient）、rasterizer（r32Float window 平面、render-pipeline additive stamping **0.744ms/1000 stamps @2560×1707**，D-06-03-T1-1）、combine 五式（union/intersect/difference/exclusion/sum，`MaskCombiner` ping-pong L018）、parametric 单内核 luma+JzCzhz（`ParametricMask`，dt blendif 4 点梯形 + boost + post 链 blur→feather→tone curve `blend.c:305-355`）、raster ref。13-3 已交付 MaskCommand 五命令（duplicate/duplicateAndInvert/fill/clear/resetEdits）。Phase 7 已交付 Vision 主体蒙版（`AIMaskSource.subject/segment/skin`，per-layer PNG raster）。
2. **图上手柄 overlay 大半是存量**——`MaskOverlayHost.swift` 已有 gradient 拉出 + tip 手柄（`gradientTip(UUID)`）、ellipse 手柄、brush/path 编辑、**screen-space 16px 命中测试**（13-3 T3）+ 纯 handle tap 不产 history item 语义（:67,217）。M2MASK-06 的「手柄 overlay」是**对齐 Alcedo 交互细节**（导引线 token 化、radial 双羽化手柄），非从零。
3. **Alcedo 出货版根本没有 brush 与 parametric——Lightamer 两侧都是超集**。Alcedo `mask_model.hpp:28-34`：Brush 挂 `ALCEDO_ENABLE_BRUSH_MASK` 编译开关（CMake 注明「not part of the shipped product」）；`ColorRangeModel`/`LuminanceRangeModel` 只允许 `enabled=false` 占位（:100-120，无亮度/参数化蒙版）。⇒ M2MASK-03 的对齐对象是 Alcedo **已就绪但未出货**的笔划/revision 数据模型语义；M2MASK-05 的 Luminance/Color Range 的「内核」只能来自 Lightamer 既有 parametric（Nitro 侧无源码，手册描述级）。
4. **参数缺口逐字段清点（映射 vs additive 的裁决基础）**：
   - Radial ↔ `EllipseForm{center, radiusX, radiusY, rotationDegrees, border}`——唯一真缺口 = Alcedo **inner/outer feather 双值** vs 既有单 `border`（羽化分数）；center/major/minor/rotation 全覆盖（半径 width 单位归一化 vs Alcedo 归一化参考空间，语义同族）。
   - LinearGradient ↔ `GradientForm{anchor, rotationDegrees, compression, curvature, state(linear/sigmoidal)}`——origin↔anchor、normal(0,1)↔rotation 角度、transition_distance 0.2↔compression（倒数关系族）；`start 1→end 0` 是 dt 渐变固定方向（既有语义内含）；curvature/sigmoidal 是 Lightamer 超集（Alcedo 无对应）。
5. **revision/乐观并发无现成载体**——全仓 grep 无 `MaskContentRevision`/revision 计数（`PipeCacheKey.maskVersionHash` 是缓存键 hash 非 revision）；Lightamer 是 `@MainActor` 单写者 + history 栈，Alcedo 的 revision 服务跨线程/跨客户端笔划追加校验，映射到单写者模型后需要重新定义**它防的是什么**（见 OQ-9）。
6. **两处挂账缺口实名在案**：① D-M2-4-1-3——`SidecarMaskSpec` 缺 `deletionProtected` capture/restore（runtime-only，重启即丢；SidecarV5Tests 断言注释显式钉住）；② D-M2-4-2-5——`MaskOverlayHost.appendForm/mutateForm`（:387/:403）以 `MaskSpec(drawn:)` 重建 spec **丢 parametric/raster/deletionProtected 三个 sibling 字段**（修法候选已留：`var spec = layer.mask ?? MaskSpec(); spec.drawn = drawn`）。DECISIONS 钦定两者 M2MASK-04 同批复核。
7. **缩略图零 GPU 存量**——`MaskChipView`（LayersPanelView.swift:452）是 CPU Canvas **示意画**（黄线描形状 + parametric/raster 图标），非像素真实；Alcedo 对应物 = `mask_thumbnail_coordinator.cpp` GPU 缩略图管线。蒙版平面本就 window-sized（rasterizer 按窗口出 r32Float），缩略尺寸平面渲染的增量成本极小。
8. **组序投影与拖动已被 M2-4 钉死**——`PipelineDocument.maskGroups`（组序=grade 序=层序）+ M2-4 OQ-9 裁决「拖组排序复用 Reconnect 命令（同一 mutation 两个 UI 面）」；蒙版级操作面 `maskItems`/`setItemEnabled`/`setItemDisplayName` 已落（top-level only，嵌套 child 寻址明文归 M2-7 = 本 phase）。

### Reusable Assets

| 资产 | 位置 | M2-7 复用判定 |
|---|---|---|
| drawn 四形态 + rasterizer（stamping 0.744ms 基线 + golden） | `LightamerCore/Sources/Layers/Masks/DrawnMaskRasterizer.swift` | **Radial/Gradient/Brush 数据正本**——参数对齐走映射 + additive decodeIfPresent（06-03 one-way 锁允许） |
| `ParametricMask`（luma+JzCzhz 单内核 + post 链） | `LightamerCore/Sources/Layers/Masks/ParametricMask.swift` | **Luminance/Color Range 内核**——UI 预设化快捷皮，零内核新增 |
| `MaskCombiner`（五式 + enabled 过滤 + Deriche blur/feather） | `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift` | 应用序 feather→invert→opacity→clamp 的执行体——现状核查 + 缺口补齐点 |
| `MaskGroupItem{enabled?, displayName?}` + `maskItems` 访问面 | `LightamerCore/Sources/Layers/Masks/MaskSpec.swift:205-377` | Mask Groups 面板读写门——扩展 `setItemInverted`/`setItemOpacity`/增删 item 同款 facade |
| `PipelineDocument.maskGroups`（组序=grade 序投影） | M2-4-2 交付（`PipelineLinkageTests` 钉） | Mask Groups 面板唯一数据源；拖组 = Reconnect |
| `MaskOverlayHost`（四工具 + 手柄命中 + history 语义） | `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift` | 图上绘制/手柄 overlay 的存量底座——radial 双羽化手柄 + Alcedo 交互对齐在此扩 |
| `MaskCommand` 五命令 + deletionProtected 拦截 | `App/Sources/Lightamer/State/LayerEditingState.swift:80-89,267-323` | 面板蒙版级操作的命令面——新增 add/remove item 命令沿同款「一命令一 history item」 |
| `AIMaskSource.subject` + SegmentSession + 入口门 | `App/Sources/Lightamer/State/AIMaskEditing.swift` | AI Subject 入口——生成面零改动，只加 invert sugar 装配 |
| `MaskChipView`（CPU 示意） + `maskVersionHash` 缓存键 | `LayersPanelView.swift:452` / `PipeCacheKey.swift:98-101` | 缩略图 OQ 的对照物与失效键设计参照 |
| sidecar v5 additive 惯例（decodeIfPresent + hash-isolation + 读者容忍） | `LightamerCore/Sources/Sidecar/`（SidecarV5Tests 钉） | 新增字段（双羽化/revision/deletionProtected 载体）全部沿此 |

## Open Questions（每条含推荐；夜间授权按推荐生效）

### OQ-1 Radial/LinearGradient 参数对齐：映射复用 vs additive vs 新建平行类型（M2MASK-01/02，必裁）
- **A（推荐）**：**映射复用 + 真缺口 additive**——Radial：`EllipseForm` 全字段映射（center/radiusX↔major/radiusY↔minor/rotationDegrees），唯一真缺口 inner/outer feather 双羽化走 **additive decodeIfPresent**（`EllipseForm` 增 `innerFeather: Float?`/`outerFeather: Float?`，nil = 回落既有单 `border` 语义——one-way 锁合法形态，v4 档字节零漂移）；LinearGradient：anchor↔origin、rotationDegrees↔normal 角度、compression↔transition_distance（换算关系 plan 期钉换算式与默认值对齐——Alcedo 默认 0.2 对应 compression 数值）、start 1→end 0 = dt 渐变固定方向内含；curvature/sigmoidal 保留为超集收进「高级」折叠（UI 默认面 = Alcedo 参数表）。依据 = 发现 4（逐字段清点）。
- B：全量参数适配、零新字段（UI 层把 border 同时呈现为 inner/outer）——双羽化是真语义缺口（内侧/外侧独立过渡），假对齐留漂移。
- C：新建 `RadialForm`/`LinearGradientForm` 平行 Alcedo 型——第二真相源 + 双形态迁移负担，违「Phase 6 资产复用」。
**推荐 A**；feather 双值与 `border` 的回落次序（nil→border；双值在 → 覆盖）由 plan 以 golden 测试钉。

### OQ-2 Brush 对齐：Phase 6 stamping 为正本 vs 引入 Alcedo SDF 笔划模型（M2MASK-03）
- **A（推荐）**：**复用既有 stamping brush 为数据正本**（bézier 链 + per-stroke radius/hardness/density/opacity，`BrushStroke` frozen）——0.744ms/千枚基线 + Phase 6 golden 全保留；Alcedo brush 的 `brush_stroke.cpp`/`brush_signed_distance.cpp` 9 文件仅作**交互参考**（笔划采样密度/SDF 羽化手感），不引入其字段编码。依据 = 发现 3（Alcedo 出货版 brush 编译关——其 brush 数据模型本身就无持久化承诺）；两侧文件格式本就不互通（已终裁），「格式相似」零收益。
- B：引入 Alcedo SDF stroke 编码重写 rasterizer 腿——丢基线与 golden，重写零功能收益。
- C：brush 参数面照抄 Nitro（size/flow/strength 命名）——Nitro 无源码，描述级臆测；现有 radius/hardness/density/opacity 已覆盖同语义。
**推荐 A**；M2MASK-03 的对齐落点收敛到 revision/乐观并发（OQ-9）+ mask 级属性（OQ-7/OQ-10），非 brush 内部表示。

### OQ-3 蒙版缩略图 GPU 管线：GPU 小平面 pass vs MaskChipView 增强（M2MASK-06）
- **A（推荐）**：**GPU 缩略尺寸平面渲染 pass**——Mask Groups 面板每蒙版一格：以缩略 window（plan 定，~96-128px 级）跑既有 `DrawnMaskRasterizer`+`MaskCombiner` 出小 r32Float 平面 → 既有显示腿（convertTexture/CG 桥）→ 位图缓存，键 = `MaskSpec.stableHash()`（编辑即失效自动重渲，沿 `maskPosition` 缓存键族既有失效设计）；蒙版平面本就 window-sized（发现 7），增量成本 = O(缩略像素)，参数拖动时只重渲对应格。
- B：`MaskChipView` CPU 示意增强（形状+羽化近似）——零 GPU 依赖但非像素真实；Alcedo 是 GPU 像素级缩略图，M2MASK-06 明文「蒙版缩略图 GPU 管线」。
- C：主 pipe 全尺寸渲染再 downscale——浪费一个数量级。
**推荐 A**；AI raster/parametric 蒙版缩略 = 同 pass 消费既有平面（raster ref 解码 + parametric kernel 均现成）。

### OQ-4 Follow Edges（IOP-MASK-06 提级 V1）：算法来源与落地面
- **A（推荐）**：**自研 Metal edge-aware kernel**——per-image 边缘图（Sobel/梯度幅值，一次预计算入缓存，沿蒙版缓存键族挂失效）+ 笔刷 stamp 沿边缘切向流线追踪（streamline 单侧跟随）；参数面 = 宽度/边缘对比阈值/跟随强度/单侧方向。Nitro 无源码可得（手册描述级），描述只约束交互手感不约束实现——自研是唯一路径；IOP-MASK-06 提级 V1 已是 ROADMAP 明文，无回避空间。
- B：等 Nitro 逆向/参考实现——不可得，阻塞 V1 交付。
- C：降级「边缘吸附」（现有 brush + snap-to-edge）——不算 contour-following，不满足 IOP-MASK-06 描述；仅作 plan 期 fallback：若流线追踪实测复杂度超预算，先落吸附版 + 挂账完整流线（验收走查裁决，如实标注）。
**推荐 A**；plan 拆独立任务 + golden 门（边缘图复现性 + 跟随走查），复杂度熔断条款 = C 的挂账路径。

### OQ-5 AI Subject 入口：subject+invert sugar 装配形态（M2MASK-05）
- **A（推荐）**：**零新内核 sugar**——Mask Groups 面板/蒙版工具栏加「AI 主体」入口：复用 07-1 主体蒙版生成（`AIMaskSource.subject` 现档复用/重烤语义不变）+ invert 位装配（raster ref `invert` 或 group item `inverted`）一步成「主体以外」= AI Background 对标（REQUIREMENTS :244 已裁 sugar 定位）；生成参数不持久红线不触碰。
- B：新 AI Background 独立分割管线——模型冗余 + 违 AI 参数不持久红线。
- C：不做——违 M2MASK-05 明文。
**推荐 A**。

### OQ-6 Luminance/Color Range：parametric 预设化 UI 皮 vs 新蒙版型（M2MASK-05，D5）
- **A（推荐）**：**UI 按 Nitro 语义呈现、数据落既有 `ParametricMask`**——Luminance Range = luma domain 单通道快捷面板（吸管/直方图取亮部暗部 → 写 4 点梯形）；Color Range = JzCzhz domain 吸管取色 + 范围/羽化滑杆 → 换算写 Cz/hz 通道曲线；内核/数据零新增，「UI 按 Nitro 呈现」的边界 = **不暴露 dt 14 通道全量 blendif 面**（发现 3：Nitro 无源码，呈现语义以手册描述 + parametric 既有能力为界）。
- B：全量 dt blendif 通道面板——UI 复杂度爆炸，违「UI 按 Nitro」明文。
- C：新独立 `luminance`/`colorRange` MaskType 数据型——第二真相源，parametric 已全覆盖。
**推荐 A**；吸管采样 = 显示平面像素 → domain 值换算（单 seam，plan 钉换算）。

### OQ-7 Mask Groups 面板：数据源与蒙版级操作面（M2MASK-06）
- **A（推荐）**：**投影 + 既有命令面全复用**——数据源 = `PipelineDocument.maskGroups`（组序=grade 序，M2-4-2 已钉）；拖组排序 = Reconnect 命令（M2-4 OQ-9 同款「一 mutation 两 UI 面」）；蒙版级操作：增删 item = `MaskCommand` 扩 add/remove（一命令一 history item 惯例）、invert/opacity = `maskItems` facade 扩 `setItemInverted`/`setItemOpacity`（top-level + 嵌套 child 寻址本 phase 补——M2-4-2 明文归此处）、锁删 = deletionProtected toast 既有 + 锁形标记 modifier（M2-4 Specific Ideas 预制）、「Locate unfinished node」提示 = 选中蒙版定位其 grade（EditorState 层选中 + 七页签联动既有）。
- B：面板自持组序/蒙版状态副本——违单一事实源，Reconnect 与面板拖动漂移。
**推荐 A**。

### OQ-8 Default Behavior 三选：设置页接线与消费点（M2MASK-06）
- **A（推荐）**：**Settings 新「Default Behavior」节 + 注入式求值**——`UserDefaults` 键 `mask.defaultBehavior`（`ask`/`newLayer`/`currentNode`，缺省 `ask` 对齐 Alcedo）；消费点 = 蒙版工具 arm 时求值（`ask` = 一次性选择 sheet、`newLayer` = 自动建 grade 再画、`currentNode` = 当前选中 grade 上画）；求值注入式（M2-1 D-EXEC-1 同款——environment 注入，视图 body 零 `UserDefaults` 直读）。
- B：硬编码 ask 无设置页——违 M2MASK-06 三选明文。
- C：每工具独立记忆——超 Alcedo 面，YAGNI。
**推荐 A**。

### OQ-9 单调 revision + 乐观并发：载体与校验点（M2MASK-07 + D-M2-4-2-5 同批）
- **A（推荐）**：**`MaskSpec` additive `contentRevision: Int?`（nil=0）+ 异步腿乐观校验 + D-5 修复同批**——①每个内容写点（stroke append/form mutate/AI 烤贝/clear-fill）revision 单调 +1（decodeIfPresent，旧档字节零漂移；`stableHash` 随内容变已是失效正解，revision 是**并发防护计数**非缓存键）；②校验点 = 唯一异步生产者 seam（overlay live stroke 腿提交带 expectedRevision，单写者校验相等才落、不等拒收重读——把 Alcedo 跨线程乐观并发收敛为单写者下的丢更新/乱序防护）；③D-M2-4-2-5 同批修：`appendForm/mutateForm` 改 `var spec = layer.mask ?? MaskSpec(); spec.drawn = drawn` 保 sibling payload（DECISIONS 已留修法候选）。
- B：revision 仅运行时（编辑会话内计数不入 spec）——重启/undo 穿越后计数失义，M2MASK-07「单调」弱化；且 stroke 腿重建本就丢字段（发现 6），runtime-only 无法修复该缺口。
- C：全量 Alcedo 式 per-mask 事务日志——单写者模型下无消费者，过度工程。
**推荐 A**。

### OQ-10 deletionProtected 文件载体：本 phase 落地形态（M2MASK-04 挂账 D-M2-4-1-3）
- **A（推荐）**：**`SidecarMaskSpec` 补 `deletionProtected` capture/restore 各一行 + SidecarV5Tests 补双向断言**——D-M2-4-1-3 挂账正解原文；与 OQ-9 的 D-5 修复同一任务批（M2-4-2 DECISIONS 钦定「同批复核」）。理由：M2-7 面板落锁删按钮 = 锁成为用户可编辑面，runtime-only 重启即丢不可接受。
- B：维持 runtime-only——面板锁态假持久，违 M2MASK-04 deletion_protected 语义。
**推荐 A**。

### OQ-11 性能预算：stamping 基线与新交互叠加（M2MASK 全族）
- **A（推荐）**：**基线 golden 保留 + 增量预算项 + 观察项挂账**——既有 0.744ms/千枚 golden 不动；新增预算项：Follow Edges 边缘图（per-image 一次预计算，随缓存失效）、缩略图 pass（O(缩略像素)/格）、手柄 overlay display 腿（不进 pipe，60fps 与 pipe 解耦既有架构）；不引入新节流机制（`maskVersionHash`/`stableHash` 缓存失效已保增量）。观察项挂验收走查：radial 双羽化手柄拖动实时性（超标 fallback = 拖动中缩略窗口平面预览、松手全精——plan 实测裁决，沿 E4 观察先例）。
- B：新交互每帧全量重渲蒙版平面——手柄拖动场景大概率超预算且无必要。
**推荐 A**。

### OQ-12 zh/en 键范围与预估（M2-4-3 收口先例沿用）
- **A（推荐）**：**随手键 + phase 尾 `Scripts/zh-audit.py --check` 对账补齐**——预估 **40-70 键**（Mask Groups 面板 + Default Behavior 设置节 + Follow Edges 参数 + Luminance/Color Range 面板 + AI Subject 入口 + 锁删/Locate 提示 toast 族 + 缩略图 AX）；语言 code 沿 `zh`。
- B：每任务同步 zh——面板密集期反复打断，M2-2/M2-3/M2-4 verbatim 先例三连。
**推荐 A**。

## Canonical References

- `research/ALCEDO-FEATURE-MAP.md` §4（蒙版体系正本：`mask_model.hpp:28-34,100-120,188-199`、`brush_stroke.cpp`/`brush_signed_distance.cpp`、`EditorMaskGroupsPanel.qml`/`mask_thumbnail_coordinator.cpp`/`EditorMasksContextPanel.qml`/`LockedNodeMaskPromptDialog.qml`）+ §1.3（Default Behavior 三选 `SettingDialog.qml`）
- REQUIREMENTS M2MASK-01..07 + `:244`（AI Background sugar 注记）+ V2 节 IOP-MASK-06/07；ROADMAP M2-7 行 + :352
- `LightamerCore/Sources/Layers/Masks/`（MaskSpec/DrawnMaskRasterizer/MaskCombiner/ParametricMask 全族）+ `App/Sources/Lightamer/State/LayerEditingState.swift`（工具/命令/仲裁机）+ `App/Sources/Lightamer/UI/Overlay/MaskOverlayHost.swift`（手柄 overlay）
- `phases/m2-4-node-model/M2-4-CONTEXT.md`（CONTEXT 惯例 + OQ-3/7/9 蒙版前裁）+ `M2-4-1-DECISIONS.md` D-M2-4-1-3 + `M2-4-2-DECISIONS.md` D-M2-4-2-4/5（top-level only 界线 + stroke 腿缺口）
- `phases/06-layers-masking/06-03-DECISIONS.md`（stamping 0.744ms 基线）+ `06-RESEARCH.md` §3.1（dt form 表）

## Specific Ideas（起草倾向，plan 细化）

- 蒙版参数/交互对齐面落 Core facade（`MaskSpec` extension 同款——setter 值语义、miss 静默 no-op、无第二存储），App 面板只消费投影——沿 M2-4-2 访问面纪律。
- 缩略图渲染器独立小类型（`MaskThumbnailRenderer`：入 spec + 尺寸 → 出 CGImage，缓存键 stableHash）——Core 可单测，面板 dumb。
- Follow Edges 边缘图 = pipe 级派生缓存（per imageID+roi，随 decode 失效）——不挂 layer，不进 sidecar。
- Default Behavior 选择 sheet 与锁删 toast/Locate 提示共用「蒙版提示面」样式（可复用 modifier 家族），IA 一致。

## Deferred Ideas

- 蒙版手柄的键盘微调（方向键 nudge）——Alcedo 无对应，反馈后议。
- Mask Groups 面板缩略图的 hover 放大预览——面板先落定再说。
- IOP-MASK-07 Depth——V2 节既定。
- Follow Edges 完整流线追踪若触发 OQ-4-C 熔断，完整版挂账 V2（如实登记）。

---

## 夜间授权预案（2026-09-29 起草时点）

本 CONTEXT 提交夜间授权裁决：若无人干预，D-M2-7-CONTEXT-1..12 = **OQ-1..12 全部按推荐 A 生效**。晨审可推翻：推翻任一条 = 修订对应 plan（CONTEXT OQ 原文不改、以 Ruling/勘误注记为准，沿 M2-3-CONTEXT E1 勘误先例）。plan 期需回填的悬决点（非 OQ 级）：feather 双值回落次序与 compression↔transition 换算式（OQ-1）、缩略图尺寸与缓存预算（OQ-3）、Follow Edges 流线复杂度熔断实测（OQ-4）、`contentRevision` 递增写点全表（OQ-9）。
