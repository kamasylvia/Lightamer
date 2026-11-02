# 图库三栏布局（dt lighttable 同构）调研 lane（zcode 只读侦察）

你是 Lightamer 的架构调研员。**全程只读（除最终 RESEARCH.md 外零写入、零 commit、零构建）**。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。中文正文，file:line 引用保持原文。

## 用户令（本案目标）

「首次打开软件，就应该进入图库，呈现三栏布局。仿照 dt，左侧是文件树和图片信息，右侧是可应用的操作，例如批量复制、批量应用、删除、批量标签等。」

首启进图库已由 `5bb31915` 落地（默认库直开）——本案 = 图库面的**三栏重设计**：
- **左栏**：文件树（文件夹/集合层级树）+ 图片信息（选中图的 EXIF/元数据面板）
- **中栏**：图片网格（既有 LibraryGridView 为基）
- **右栏**：选中集操作面板（dt "actions on selection" 形态）：批量复制（copy/paste 调整）、批量应用（预设/样式）、删除、批量标签、评级/色标等

## 输入集合

**dt 侧**（/Volumes/UNITEK/Documents/Development/darktable，只读）：
- lighttable 左栏：`src/libs/collections.c`（集合树：文件夹/相机/日期/标签/评级层级）、`src/libs/image.c`（image information 模块）、`src/libs/metadata_view.c`（元数据展示行）
- lighttable 右栏：`src/libs/dtmask?` 不存在——找 actions on selection 实现（4.x+ 在 `src/libs/` 下，tagging.c / labels.c / copy_history.c / selects.c / styles.c / modulegroups 交互）；批量操作如何对多选生效（selection 模型：`src/common/selection.c`）
- 多选状态与视图：`src/views/lighttable.c` 的 selection/collection 联动
- **注意**：dt 5.x 已重构过 actions on selection（module hierarchy 化）——读当前 HEAD 形态，不必考古

**我方侧**（主仓，只读）：
- `App/Sources/Lightamer/Library/`（LibraryGridView / LibraryProjectController / LibraryWelcomeView / ImportModeDialog / ImportProgressView / LibraryPreferences）
- `LightamerCore/Sources/Library/`（LibrarySchema（v6 分析六列）/ LibraryStore / LibraryQueries / ImportService / ExifFold / ExifSearchIndexer / LibraryProjectController 若在）
- 壳：`App/Sources/Lightamer/Shell/`（WorkspaceHostView / ContentView）+ `LightamerFirstLaunch.swift`（gallery-first 落地面）
- 既有选择/批量语义盘点：图库网格现有多选能力？rating/flag 面？Copy Adjustments（编辑器内）与图库级批量复制的关系
- yiyin 面板挂载面（图库级批量印框可能性——观察项，不设计）
- GUI 走查证据：`.work/gui-acceptance/library-first-launch/`（现状面）

## 变换规则（产出 RESEARCH.md 章节骨架）

1. **dt lighttable 解剖**：左栏两模块（collections 树数据源/节点模型/UI 交互 + image information 行集）与右栏 actions on selection（操作清单/分组/对 selection 的生效机制/file:line）。
2. **我方现状解剖**：图库面当前布局（单栏网格？侧栏？）、数据模型（.lalb schema 有无 folder/tag/rating 列——v6 分析六列盘点）、选择模型现状、可用批量操作清单。
3. **差距映射表**：≥10 维度（左栏树/图片信息/右栏操作/多选/评级/色标/标签/删除语义/复制调整/预设应用/布局骨架/键盘导航）。
4. **三栏设计案**：三栏容器选型（NavigationSplitView 三列 vs HSplitView——参考 dt 交互与 SwiftUI macOS 27 现状）、左栏树数据源（文件夹 vs 智能集合——给判定）、图片信息面板（EXIFFold 复用面）、右栏操作面板（操作清单 + 逐操作对多选的语义：批量复制调整 = copy/paste epoch 复用 M2-8 先例、批量删除 = 引用式删除语义 OQ、批量标签 = schema 列或 sidecar?——给判定）、selection 模型设计。
5. **数据面缺口**：.lalb schema 是否需要新列/新表（标签表?）——version bump 判定（对齐 sidecar/.lalb 迁移先例）；与 lumen-culling 批（schema v6 分析列）的关系。
6. **风险清单**：剥离门（LibraryLegacyGate）回切面、FIX2③（LibraryProjectController 零 diff）约束影响、D-6 型 SwiftUI 树形框架缺陷风险（树形控件 = 敏感面，标注 d6-relevant）。
7. **Open Questions**（≤6 条带推荐）：呈裁。

## 验收清单

- [ ] dt 侧两模块 + actions on selection 全 file:line 可核（含 selection 模型）
- [ ] 我方侧含 LibraryGridView/LibraryStore/LibraryQueries 现状精确 file:line
- [ ] 设计案明确回答：.lalb schema 是否 bump（判定+理由）、批量删除语义（引用式 vs 文件删除）、树数据源选型
- [ ] 右栏操作清单逐项标注数据依赖与现有可复用件
- [ ] Open Questions ≤6 带推荐
- [ ] 全程只读零 commit；产出单文件 `.work/gsd/phases/library-lighttable/RESEARCH.md`（chunked 写：每段 ≤8KB 追加，防截断）

注：主仓 Film/ 域有执行 lane 在飞（与本域无交集）；你读 HEAD 字节即可，勿引 Film/ 在制行号。

产出 = stdout 一次性完整输出摘要 + RESEARCH.md 正本。结论头 `PASS / N error + N minor`。
