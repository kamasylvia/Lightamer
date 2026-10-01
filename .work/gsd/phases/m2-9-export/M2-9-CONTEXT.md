# M2-9: 导出选项 Alcedo 化 — Context（起草稿）

**Gathered:** 2026-09-29（discuss/research 起草 subagent；输入 = ROADMAP M2-9 行 / REQUIREMENTS EXP2 族 + EXP 族 / M2-8-3-SUMMARY 交接节 / ALCEDO-FEATURE-MAP §7 / Phase 11 CONTEXT+RESEARCH / Alcedo 源码实测——`RESEARCH-NOTES.md` 正本）
**Status:** DRAFT — **C 档第 1 停**：本文 OQ 清单交用户裁决后才进 plan（不自作主张出 plan）。
直接裁决项（D-1..D-6）为低分叉/既有裁决延续，随 OQ 一并过目，可逐条推翻。

<domain>
## Phase Boundary

把现有六格式导出管线的**选项面对齐 Alcedo Studio**（格式矩阵不动，动的是选项语义/默认值/UI）：
M2EXP-01..05。核心架构事实：

1. **六格式编码面零改动红线**（ROADMAP M2-9 用户终裁）：`ExportFormatSpec`/`ImageIOEncoders`/
   `WebPEncoder` 不触碰；EXR/UltraHDR 维持 V2（ALCE-02/03）。
2. **渲染链消费面已备**（M2-8 交接，`M2-8-3-SUMMARY.md:156-162`）：`instancesOverride` 缝 +
   `effectiveDrtRecord` 载体随 active 链走——接线在 App 装配点，Core 渲染器零改动。
3. **队列不动**：`ExportQueue` actor 并发 1 + generation cancel + retry 全保留（Alcedo 队列面
   是我们的子集）；新选项走 `ExportVariant`/`Request` 载体扩容。
4. **yiyin 终步保留**（EXP-05 注入器缝）+ post-actions 保留（EXP-08 路径制）——两者是超集能力，
   Alcedo 无对应。
5. 选项面新增五块：尺寸四模式扩容（M2EXP-01）、元数据策略（M2EXP-02）、文件名模板引擎
   （M2EXP-03）、输出 ICC=DRT 联动（M2EXP-04）、检查器内队列 UI + 质量记忆（M2EXP-05）。

**Phase M2-9 不做**：EXR/UltraHDR 格式（V2）；全 recipe 导出预设持久化（挂账 PRES 交汇，
见 OQ-9）；软打样联动（13-2 SoftProofStage 结构性不进 export，不触碰）；HDR gain map 输出（V2）；
`.lalb` 版本投影列进导出 manifest（如需 = 注入 sink，v1 可不做）。

</domain>

<decisions>
## 直接裁决项（低分叉 / 既有裁决延续；随 OQ 一并过目，可逐条推翻）

### D-M2-9-CONTEXT-1: 六格式矩阵与编码器零改动
- **裁决**：格式集/位深面/质量旋钮维持 Phase 11 交付原样；Alcedo 的 EXR/UltraHDR 不进本期。
- **理由**：ROADMAP M2-9 用户终裁原文「格式保留原 6 格式矩阵」；六格式位深/质量面已覆盖
  Alcedo 四格式面（HEIC/AVIF/WebP 是超集）。
- **Reversibility**: 高（V2 ALCE-02/03 预留）。

### D-M2-9-CONTEXT-2: 队列引擎零改动（并发 1 + cancel + retry）
- **裁决**：`ExportQueue` actor 不动；四态 UI（Queued/Exporting/Done/Failed）映射现有 job 状态。
- **理由**：EXP-06 已交付超集（Alcedo 仅单 in-flight gate）；并发 1 = 内存红线推导（800MB@100MP
  全幅 float32），维持 D-11-CONTEXT-2。
- **Reversibility**: 高。

### D-M2-9-CONTEXT-3: yiyin 终步 + post-actions 保留
- **裁决**：`variant.yiyin` + `ExportYiyinInjector` 缝原样；post-actions 路径制脚本 + Finder
  reveal 原样进入新 UI（Alcedo 无此二面，属超集保留项）。
- **理由**：ROADMAP M2-9 明写「yiyin 印框/水印终步保留适配」；EXP-05/08 交付面不动。
- **Reversibility**: 高。

### D-M2-9-CONTEXT-4: 渲染链接线 = App 装配点注入，Core 零改动
- **裁决**：入队时 App 层构造——`instancesOverride` = `EditorState.history.projection(upTo:)`
  （instances + layerSnapshot，随 active 链/版本走）；DRT 三元组 = `effectiveDrtRecord() ??
  DrtRecord()`；CGColorSpace/ICC 构建复用 13-2 资产（`DisplayProfile` resolve + exact-TRC parser
  + `LinearVariantCache`）。
- **理由**：`ExportRenderer.Request.instancesOverride` 缝即为此面预留（ExportRenderer.swift:100-104）；
  M2-8 交接明示「版本面无新增依赖」。`.drt` 尾段在 export route 的重放语义（对 11 先例
  「剔 gamma + 覆写 colorout」的替换关系）= planner 接线核心题，随 OQ-7 裁决展开。
- **Reversibility**: 中（接线形态变更是 App 层局部改动）。

### D-M2-9-CONTEXT-5: EXIF Software 写入本 app 版本号
- **裁决**：导出文件 EXIF `Software` = `Lightamer <version>`（properties 路径，
  `kCGImagePropertyExifDictionary`）；TIFF `editorSignature` 预留面保留不冲突。
- **理由**：M2EXP-02 明文；Alcedo 0.2.9 同款先例；properties 路径已验证可写（ExportEncoder.swift:18）。
- **Reversibility**: 高。

### D-M2-9-CONTEXT-6: Print 模式 DPI 必填 + maximum_edge 全模式尾段生效 + DPI 修正
- **裁决**：Print 模式（物理尺寸 + in/cm/mm + DPI）DPI 缺失/非正 = 入队校验 typed 拒绝；
  `maximumEdgePixels` 对全部尺寸模式尾段生效，触发时 **DPI 随宽度比例同步修正**（保物理打印
  尺寸一致）。
- **理由**：Alcedo 数学语义照抄（`export_recipe.cpp:63-80, 309-311`）——该两处是行为正确性
  （打印尺寸守恒）而非风格；EXP-03 既有独立 DPI 旋钮（1..2400 写入面）保留。
- **Reversibility**: 高（纯函数，golden 可钉）。

</decisions>

<open_questions>
## Open Questions（用户裁决点；每条：问题 / 选项 / 推荐 / 理由）

### OQ-1: 导出 UI 形态——检查器内嵌页 vs 现有 sheet 去留
- **问题**：ROADMAP 明写「导出队列 UI（检查器内）」，Alcedo 亦是检查器内嵌页取代旧 modal
  （`ExportInspectorPanel.qml:10-11`）；现有 `ExportPanelView` 是 sheet（ContentView.swift:337-340，
  挂在 Sessions 域 shell）。
- **选项**：(A) 新建检查器内 Export 页，旧 sheet 在 legacy gate（`LIGHTAMER_LEGACY_LIBRARY=1`）
  内保留原样，M2 面只用检查器页；(B) 检查器页 + 全局替换旧 sheet（legacy 面同换）；
  (C) 保留 sheet 不迁。
- **推荐**：(A)。
- **理由**：剥离门纪律（回切后与 M2-2 前逐字节同构）要求 legacy 面不动；(C) 违 ROADMAP 明文。

### OQ-2: 尺寸模式基座——`YiyinExportSettings` 原地扩 vs 新建 `ExportSizing` 超集
- **问题**：M2EXP-01 四模式（Original/LongEdge/Bounds/Print）+ upscale + cap；现
  `variant.sizing` 就是 `YiyinExportSettings`（OQ-11-6 正主，original/longEdge/shortEdge）。
- **选项**：(A) 原地扩 `YiyinExportSettings`（加 bounds/print 两 case + allowUpscale +
  maximumEdgePixels 字段；yiyin 面板继续只暴露三模式子集）；(B) 新建 `ExportSizing` 超集
  包裹/替换，yiyin 类型冻结。
- **推荐**：(A)。
- **理由**：单一 sizing 数学（fit-inside + 永不放大钳一处实现）；Codable 新 case 对旧数据
  解码无破坏（旧 rawValue 仍解）；yiyin 面板 UI 不动即子集消费；(B) 引入双类型折算层，
  违「复用 verbatim、无平行 shim」原判（ExportRecipe.swift:14-18 头注）。

### OQ-3: 默认导出落点——Sessions 常量退役后的 M2 默认
- **问题**：现默认 = `SessionLayout.outputDirectory(for:)`（Sessions 域）；M2 项目工作区下
  Session 概念被隐藏。
- **选项**：(A) 默认 = 源图所在目录（含子文件夹机制分担整理）；(B) 默认 = 最近使用目录
  （跨会话记忆，首用回落源图所在目录）；(C) 每次强制用户选目录（NSOpenPanel）。
- **推荐**：(B)。
- **理由**：Alcedo 同款心智（`defaultExportFolder` 后端提供 + outDir 记忆）；批量连续导出
  免重选；(A) 有污染源目录风险（RAW 同目录混入成片）。配合 OQ-5 的子文件夹默认档定稿。

### OQ-4: 文件名模板语法选型
- **问题**：M2EXP-03 的 12 字段 + 补零序号 + literal 需要一套模板语法。
- **选项**：(A) Alcedo `{token:arg}` 语法全量移植（`{source}`/`{date:yyyy MM dd}`/
  `{cameramake}`/`{cameramodel}`/`{lens}`/`{iso}`/`{aperture}`/`{shutter}`/`{focal}`/`{rating}`/
  `{sequence:0000}` + `{{`/`}}` 转义 + typed 解析错误 + 200 字符 sanitize + fallback "image"）；
  (B) Lightroom 式 `<filename>`/`<date>` 风格自定义语法；(C) 无模板，仅前/后缀输入框。
- **推荐**：(A)，一处修正——**shutter 渲染保持 `1-500` 形态**（Alcedo 同款；`/` 是 macOS
  文件名非法字符，`-` 是正确选择，非缺陷）。
- **理由**：功能对标正本即 Alcedo；语法语义全部实测在案（RESEARCH-NOTES §1.4）；实现自写
  （GPL 只对标行为）。(C) 违 M2EXP-03 AC。

### OQ-5: 冲突策略档位与默认（FAIL / REPLACE / 现行递增）
- **问题**：M2EXP-03 写「冲突 FAIL/REPLACE」（Alcedo 默认 FAIL）；现行 = 恒 `-1/-2` 递增
  （D-11-CONTEXT-4，含大小写不敏感占用比对 + E2E 钉）。批量导出 N 张同模板图（如无
  `{sequence}`）在 FAIL 下第 2 张起全失败。
- **选项**：(A) 三档并存：Increment（现行为）/ FAIL / REPLACE，默认 **Increment**；
  (B) 两档 FAIL/REPLACE（照 M2EXP-03 字面 + Alcedo），默认 **FAIL**，现行递增退役；
  (C) 两档 FAIL/REPLACE，默认 **REPLACE**。
- **推荐**：(A)——Increment 为默认档，FAIL/REPLACE 为显式档。
- **理由**：批量导出是 Lightamer 一等场景（EXP-06/07），无序号模板 + FAIL 默认 = 批量地雷；
  递增已有 E2E 金面（同目录二导 `-1` 递增、原文件不动），保留为默认是行为延续；
  FAIL/REPLACE 两档满足 M2EXP-03 字面与 Alcedo 对标。裁决后需同步改写 D-11-CONTEXT-4 状态
  （历史裁决注记沿用，非推翻——扩档非换档）。

### OQ-6: 元数据剥离档位——模型粒度 vs UI 粒度
- **问题**：M2EXP-02「默认剥离 location/设备序列号/编辑历史」；Alcedo 模型 7 bool 全量
  （`ExportMetadataPolicy`）但 UI 单开关 + 固定剥离文案（QML:609-626）。**注意**：现 Lightamer
  导出嵌 XMP 编辑摘要 packet（D-11-CONTEXT-5）——该 packet 语义上属「编辑历史」，默认剥离档
  下应默认不嵌。
- **选项**：(A) 模型全量 7 bool 对齐 Alcedo + UI v1 单开关（STANDARD=嵌 EXIF+XMP+IPTC、
  固定剥离三项 + 编辑摘要 XMP packet 默认不嵌；NONE=全剥）+ 说明文案，细粒度 UI 后置；
  (B) UI 直接给 6-7 个细粒度开关；(C) 单开关 + 不做模型（硬编码策略）。
- **推荐**：(A)。
- **理由**：模型一次到位（后续加 UI 零迁移）；UI 对齐 Alcedo 单开关心智；(C) 把策略焊死，
  META 面后续（评级/关键字同步导出）无挂点。XMP packet 默认不嵌是对 D-11-CONTEXT-5 的
  语义收窄（剥离默认档优先），需在 plan 中注记。

### OQ-7: 输出 ICC 联动——五空间菜单退役 vs 高级覆盖保留
- **问题**：M2EXP-04「输出 ICC 与本图 DRT 编码强制联动（space/EOTF/peak 入队前已解析）」；
  现 `variant.colorSpace` 五选菜单与 DRT 无关。recipe 未持久化（D-11-CONTEXT-3）→ 字段替换
  无迁移负担。真分叉在：**导出链上 DRT 尾段与 11 先例（剔 gamma + 覆写 colorout）的关系**——
  DRT 联动后输出编码 = DRT 编码，chain assembly 可能从「gamma+colorout 对」切换为「`.drt`
  尾段重放」（PixelPipe.swift:701-706）。
- **选项**：(A) 强制联动，五菜单退役，chain 走 `.drt` 尾段重放、输出编码即 DRT 编码，
  EMBED/OMIT checkbox 对齐 Alcedo；(B) DRT 派生为默认 + 高级折叠区保留五空间手动覆盖；
  (C) 保留五菜单，DRT 仅作 ICC 标注（不真联动——违 AC，列出仅完备）。
- **推荐**：(A)。
- **理由**：AC 明文「强制联动」；Alcedo 渲染与 ICC 共用同一编码三元组（service cpp:177-178）
  是行为正本——显示与导出所见即所得；(B) 双色彩出口破坏「转换恰一次」不变量且 UI 心智分裂；
  planner 需对 `.drt` 尾段导出重放做 golden（对 11-02 六格式矩阵回归 + E3 双态守卫延伸）。

### OQ-8: PQ/HLG 编码图的 SDR 输出钳位口径
- **问题**：DRT EOTF ∈ {st2084, hlg} 时（Alcedo 判 HDR 输出编码），六格式 v1 无 UltraHDR；
  现量化域 [0,1] 钳位（D-11-CONTEXT-7）。PQ/HLG 文件直出（EMBEDDED_PROFILE_ONLY 同构）还是
  维持钳位？
- **选项**：(A) v1 维持钳位（HDR 亮度压 SDR 白），ICC 如实标 EOTF（像素已被钳，标注与像素
  一致）；(B) PQ/HLG 不钳位直出（HDR 容器文件，部分查看器支持）；(C) PQ/HLG 图导出时
  typed 拒绝（强制用户切 EOTF）。
- **推荐**：(A)，v1 最小面；真 HDR 容器 = V2 UltraHDR（ALCE-02）一并交付。
- **理由**：(B) 需量化分档触碰 quantizer + 六格式 golden 重冻结（红线成本），且 HDR 静态
  文件生态（非 UltraHDR）兼容性差；(C) 把 V2 缺口变成 v1 死路。若裁 (B)，plan 必须给
  quantizer 分档 + golden 重冻结预算。

### OQ-9: 导出预设范围与存储——命名模板预设 v1、recipe 预设挂账？
- **问题**：Alcedo 有命名模板预设（3 内置 + 自存，QSettings）；全 recipe 预设 Alcedo 没有、
  Lightamer D-11-CONTEXT-3 挂给 Phase 12 PRES（Codable 已零成本预留）。
- **选项**：(A) v1 只做命名模板预设（内置 3 条对齐 Alcedo + 自存/改名/删除；存储 =
  UserDefaults JSON 数组，键 `export.namingTemplates`）；全 recipe 预设挂账 PRES 交汇；
  (B) v1 直接上全 recipe 预设（复用 PresetsStore 目录惯例新 Kind）；(C) 预设全不做。
- **推荐**：(A)。
- **理由**：Alcedo 功能面就是命名预设（对标边界）；recipe 预设涉及 PresetsStore schema 扩展
  （调整栈预设与导出预设同库或分库），是独立设计题，塞进本期会拖 M2EXP 面；Codable 预留
  使后挂成本趋零。(C) 违对标。

### OQ-10: 质量跨会话记忆键面——四格式全记 vs 单键
- **问题**：M2EXP-05「质量跨会话记忆」；Alcedo 记两键（SDR quality + UltraHDR quality，
  `import_export.cpp:43,491-499`）。Lightamer 有质量旋钮的格式 = JPEG/HEIC/AVIF/WebP 四个。
- **选项**：(A) 四格式各一键（`export.jpegQuality` / `export.heicQuality` / `export.avifQuality`
  / `export.webpQuality`，0...1 Double，AGENTS.md UserDefaults 键登记段入册）；(B) 单键全局
  quality 共享；(C) 不记忆。
- **推荐**：(A)。
- **理由**：四格式质量语义独立（AVIF 95 ≠ WebP 95 观感），单键共享会在切格式时串值；
  Alcedo 两键是因为它只有两个质量旋钮——语义同构（每个旋钮一键），非键数教条。

### OQ-11: 子文件夹默认档与命名——文案跟随 Alcedo "Processed"？
- **问题**：M2EXP-03 子文件夹；Alcedo 开关默认关 + 默认文案 `"Processed"`。
- **选项**：(A) 完全对齐（默认关 + 文案 Processed）；(B) 默认关 + 文案本地化（zh「导出」
  / en "Processed"——String Catalog 双语）；(C) 默认开。
- **推荐**：(B)（默认关同 (A)，仅文案走本地化）。
- **理由**：Lightamer 是 zh/en 双语应用（String Catalog 惯例），默认文案属于 UI 文案面，
  走 L25 zh 键纪律；开关默认关与 Alcedo 一致（不强制用户整理目录）。(C) 改变落盘行为
  预期，且与 OQ-3 (B) 的「源图同目录首用」组合会把首用导出静默收进子目录。

### OQ-12: upscale/cap 的 UI 归置与默认值确认
- **问题**：`allowUpscale`（默认 false）与 `maximumEdgePixels`（默认 0=关）两旋钮的 UI 暴露
  程度；Alcedo 把两参数埋在模型里（QML 未暴露 upscale/cap 控件——`StartExportWithRecipeOptions…`
  实参 8192 硬 cap）。
- **选项**：(A) 高级折叠区（DisclosureGroup）暴露两控件，默认 false/0（不放大、无上限）；
  (B) 完全跟 Alcedo——模型有、UI 不暴露（cap 固定 100000 或格式上限）；(C) 主面板直排。
- **推荐**：(A)。
- **理由**：M2EXP-01 把 `allow_upscale + maximum_edge_pixels` 列为 AC 面（需用户可达才能算
  交付）；折叠区保主面板 Alcedo 同构简洁。(B) 使 AC 不可验收。
</open_questions>

<impacts>
## 裁决后影响面速览（给 plan 阶段的输入）

- **Codable 面变更**：`ExportVariant`（colorSpace → drtDerived 载体；sizing 扩容）——recipe
  未持久化，零迁移；`YiyinExportSettings` 扩 case（旧 payload 兼容解）。
- **新纯函数面（golden 钉）**：尺寸解析（fit-inside + upscale 钳 + cap + DPI 修正——Alcedo
  cpp:31-80,287-325 同构自写）、模板解析/渲染/sanitize、冲突策略三档。
- **回归红线**：六格式 golden 矩阵（11-02）零漂移；E2E 尺寸向量（EXP-03）；`-1` 递增 E2E
  （EXP-07，若 OQ-5 裁 (A) 保留为默认档）；yiyin round-trip（11-03/11-05）。
- **UI 面**：检查器新 Export 页（zh/en String Catalog；L25 zh 键纪律）；legacy sheet 冻结。
- **UserDefaults 新键**（AGENTS.md 登记段）：`export.jpegQuality` 等 4 键（OQ-10）+
  `export.namingTemplates`（OQ-9）+ 落点记忆键（OQ-3 裁 (B) 时）。
</impacts>
