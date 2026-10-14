# M6-4 Research — 图库 stacks + auto-stack + AI 分割蒙版原生 spike

> 起草：research worker（2026-10-14 傍晚批）。范围正本 = ROADMAP §Milestone 6 M6-4 行
> + REQUIREMENTS M6INT-02/03 + charter 六裁决点④⑤（`research/LIGHTCRAFT-NOTES.md` §六，
> 用户回批 2026-10-11：④AI 蒙版先零成本 spike Vision 达标即收 ⑤stacks + auto-stack 优先）。
> 方法：LightCraft/Alcedo 本地 checkout 源码实测（GPL 零复制；LightCraft MIT OR Apache-2.0
> 仅记录 NOTICE 义务）；Vision SDK compile-probe /tmp 即弃（未入仓）。**C 档第 1 停**：
> OQ-M6-4-1..7 交用户裁决后才进 plan。

---

## 面 A — stacks + auto-stack

### A1 LightCraft 实现语义（`crates/catalog/src/stacks.rs` + `engine/src/cmd/organize.rs`，以本地 checkout 为准）

- **数据模型**：`Stack { id, photos: 有序数组（index 0 = 顶 = 封面）, collapsed: bool }`；
  变更 = 三种 catalog op（`AddStack` / `RemoveStack` / `SetStack`），可撤销、随 journal 持久。
  封面不是独立字段——**封面 = 成员序位 0**（`set_top` = 把该图挪到数组头部），免 cover/成员两处真相。
- **校验三规则**（`validate_stack`）：成员 ≥2、无重复、**一图至多一栈**（全 catalog 级不变量）。
- **手势 op 族**：
  - `group_ops(top, members)`：并组——成员若已属他栈，整栈并入（其他成员按序跟入）；
    成员 <2 返回 None 不动。
  - `stack_with_ops(result, sources)`：**HDR/pano 合并产物与其源图自动成栈（collapsed）**——
    对我方 M5 合并域是现成先例（见 OQ-M6-4-4）。
  - `move_in_stack_ops(photo, ±delta)` / `split_stack_ops(photo)`（从该图起切新栈，余 <2 解散）/
    `ungroup_ops` / `remove_from_stacks_ops`（余 <2 自动解散）/ `set_top_ops` /
    `set_collapsed_ops`（单栈或全部）。
- **显示序**（`arrange_stacks`）：查询结果内栈成员聚拢到首成员出现的位置、按栈内序排列；
  collapsed 栈只显示顶图，**顶图被当前过滤隐藏时由首个可见成员顶替**。
- **auto-stack**（`auto_stack_groups(ids, gap_secs)`）：按拍摄时间升序，相邻间隔 ≤ gap_secs
  归同簇，**runs ≥2 才成栈**；跳过已堆叠 / 已删除 / 无 capture 时间的图；结果以
  `group_ops(collapsed: true)` 一次性成栈（一个 undo 批）。**burst/bracket 无专门检测——
  纯时间阈值**（Lightroom 同型）。UI 默认 **gap = 60 秒**（可调，支持 `preview` 只报组数不动库）。
- **命令面**：`stack.toggle`（S 键翻转收起）/ `stack.expandAll` / `stack.collapseAll`
  （View ▸ Stacks）/ `stack.auto {gap?, ids?, preview?}`（池 = 多选时选区，否则当前视图）。
- 存储机制（op-log + 快照）不借鉴——我方 SQLite 事务是代差优势（LIGHTCRAFT-NOTES 面 1 已裁）。

### A2 Alcedo 核查（stacks 的 UI 对标落空）

- 全仓核查（`sleeve/` / `storage/` / `ui/` qml / `docs/`）：**Alcedo 无照片堆叠特性**。
  "stack" 命中均为 C++ `std::stack` 容器或 `EditorAdjustmentStack`（调整层 UI）；
  `AlbumInspectorPanel.qml` 的 "Group checkbox" = 图库查询**按字段分组显示**（group-by），
  与 stacks 无关。
- **结论**：stacks 的 UI 交互采 **Lightroom / LightCraft 惯例**（网格封面 cell 叠加
  徽章 + 成员计数 + 展开/收起箭头；右键 stack/ungroup/set cover/move；View 菜单
  expand/collapse all）——ROADMAP M6-4 行「封面/展开/收起 + 网格堆叠徽章 UI」即此惯例转写。

### A3 我方现状与落点

- **LibrarySchema v4 冻结面**（`LightamerCore/Sources/Library/LibrarySchema.swift`）：
  `images` 29 列（`capture_date` 有现成 keyset 索引 `(capture_date, id)`）；`albums`
  （type = album|folder|filter 一表三分）；`album_content` WITHOUT ROWID join 表 +
  `ref_count` 物化计数；`version_ref` 投影表；AI 七表族。**迁移缝现成**：ProjectFileStore
  打开时自动 `sqlite3_backup` 快照（轮换）→ 单 `BEGIN IMMEDIATE` → 幂等 `CREATE IF NOT EXISTS`
  走全腿（v1→…→N）→ futureSchema typed 拒绝。
- **查询/UI 挂点**：`LibraryQueries.searchPage` keyset 分页（anchor = capture_date,id）+
  `groupCounts` / `memberIDs`；App 侧 `LibraryGridModel`（分页/选区/打开）+
  `LibraryGridView`（cell 渲染 = 徽章 overlay 落点）；View/右键菜单走既有菜单面。
- **MCP 面**：M6-1 PhotoProjection 消费图库查询——堆叠显示序是否透出 MCP = 对账项（风险节 R3）。

### A4 推荐形态（schema v4 → v5，PURE ADDITIVE）

**新两表**（album_content / version_ref 先例形态）：

```sql
CREATE TABLE IF NOT EXISTS stacks (
  id INTEGER PRIMARY KEY,
  collapsed INTEGER NOT NULL DEFAULT 0,
  added_time REAL,
  modified_time REAL
);
CREATE TABLE IF NOT EXISTS stack_content (
  stack_id INTEGER REFERENCES stacks(id) ON DELETE CASCADE,
  image_id INTEGER REFERENCES images(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,               -- 0 = 封面（LightCraft photos[0] 同构）
  PRIMARY KEY (stack_id, image_id)
) WITHOUT ROWID;
CREATE UNIQUE INDEX IF NOT EXISTS idx_stack_content_image
  ON stack_content(image_id);              -- 一图一栈 = DB 级不变量 + stack_of 反查
```

- **不设 cover 列**：封面 = position 0 成员（LightCraft 同构，单真相）。
- **一图一栈**由 UNIQUE 索引 DB 级强制（LightCraft validate 规则 3 的 SQL 化）；
  「成员 ≥2」由 store 层校验（LightCraft 规则 1）；image 删除 → CASCADE 掉成员行，
  余 <2 的栈由 store 在同事务解散（LightCraft remove_from_stacks 语义）。
- **auto-stack = 查询期计算 + 落普通栈**：池取 `images.capture_date`（现有列 + 现有索引，
  零新增数据依赖）→ LightCraft 阈值聚类语义（排序 / 相邻 ≤ gap 归簇 / runs ≥2 /
  跳过已堆叠）→ 一次事务批量成栈。**不存 auto 出处**（LightCraft 同——撤销走既有 history 面）。
- **迁移代价 = 低**：v3→v4 槽同款幂等 additive（两表一索引，无列变更、无回填，栈初始为空）；
  快照/单事务/全腿走查链全部现成；`schemaVersion` 4→5，futureSchema 拒绝面自动生效。
- **分页 × 堆叠**（keyset 分页不受扰的关键）：
  - 收起态 = 页查询纯谓词排除非封面成员
    （`WHERE id NOT IN (SELECT image_id FROM stack_content WHERE position > 0)` 形）——
    collapsed 栈天然只剩封面，keyset 分页零改动；
  - 展开态 = 页内 adjacency fixup（成员聚拢 + 跨页边界有界补拉）——plan 期定案（OQ-M6-4-3）。
- **许可注记**：阈值聚类 / arrange 语义 = 思想移植，无需 NOTICE；若逐字移植
  `stacks.rs` 算法段则 NOTICE 归属（MIT OR Apache-2.0）。

---

## 面 B — AI 分割蒙版原生 spike

### B1 我方 AI-01 已交付面（盘点基线，`LightamerCore/Sources/AI/`）

- **layer A** `GenerateForegroundInstanceMaskRequest`（macOS 15+ 结构 API，内置离线，
  类不可知多实例，两段式：catalog → 全实例 label 合成 mask）。⚠️ `generateScaledMask`
  在 macOS 27.0b 双损坏（subset 语义错 + 几何 +3/16 偏移，07-1 D-07-1-T2-4 探针实证）→
  已统一走 `allInstancesMask` 标签合成；Apple 修复后升级缝在案。
- **layer B** `GenerateIterativeSegmentationRequest`（macOS 27，WWDC26/237；
  `DownloadableAssetsRequest` 一次性模型下载 + `AIAssetStore` 三态门；point/box 种子 +
  included/excluded 精修点（预算 13/11，typed 超限）；quality 三档——fast 256² 需上采样、
  **balanced/accurate 全分辨率直出**（07-1 D-07-1-T4-2）；IoU ≥0.9 语义门在册；
  ⚠️ 测试宿主 entitlement 阻断资产下载 → GUI 真机复验先例（07-3）；
  ⚠️ 任何 device pin 都会 abort（27.0b Vision beta bug，layer B 只许不 pin）。
- **person 双件**：`GeneratePersonSegmentationRequest`（内置）+
  `GeneratePersonInstanceMaskRequest`（macOS 15+ 多人实例）。
- **scribble 升级缝**：`AISubjectSeed.scribble` case 保留（v1 构造即 typed 拒绝）——
  SDK `init(seedScribbleBuffer:)` 本轮 probe 实测在位（B2），激活缝现成。
- **worker 底座（M4-3 先例）**：`AIWorkerProtocol` 同 binary 子进程 `--ai-worker`（open/run
  + ai-compat.json 崩溃记录）+ `ModelAssetCatalog` 五 profile + `ModelAssetStore`
  （SHA-256 锁定 + Release 版本锁 URL + hf fallback + 许可字段）。**LightCraft 安装器纪律
  （SHA256 + 自检 + 断点续传 + 条款确认）与我方 ModelAssetStore 面语义同构**——SAM 类模型
  若引入，安装/隔离两件套代价低；贵的是模型本体（B3）。

### B2 Vision macOS 27 SDK 实测（compile-probe，/tmp 即弃）

本机 macOS 27.0b 26A428 / Apple M4，swiftc 全绿 + 只读运行（不触发下载）：

| API | 实测 |
|---|---|
| layer A `GenerateForegroundInstanceMaskRequest` | 编译通过；supportedComputeStageDevices main = **[ane, gpu]**（与 07-1 一致） |
| layer B `GenerateIterativeSegmentationRequest` | 编译通过；`supportedRevisions = [revision1]`；quality 三档；**assetStatus = notReady**（本机未下载，与 entitlement 先例一致）；`init(seedScribbleBuffer:)` 编译通过 |
| `GeneratePersonInstanceMaskRequest`（macOS 15+） | revision1；main = **[ane, gpu, cpu]** |
| `GeneratePersonSegmentationRequest` | revision1；quality 三档 |

- **API 面全扫**（`Vision.swiftmodule/arm64e-apple-macos.swiftinterface` 全文 grep +
  Headers 逐文件）：**Vision 无任何文本提示分割 API**（无 grounding / text-prompt
  segmentation；文本侧仅 RecognizeTextRequest OCR）。`VNStatefulRequest` = macOS 11
  视频跟踪基类，与分割无关——ROADMAP 行内「SAM 类新 API 若 macOS 27 有」的答案是：
  **没有**，macOS 27 新分割面就是 layer B（已交付）。

### B3 LightCraft SAM 3 路盘点（`docs/ai-masks.md` + `crates/segment/`）

- **能力集**：Object 点击精修（绿/红点，≤64 击，每击 ~35ms）+ Describe 文本选择
  （`sky` / `the red car`，逗号分隔多目标合并，score>0.5，每次 ~0.6s）+
  **Edge 羽化**（±100，≤2% 长边）+ **延迟 hi-res detail patch**（末击 ~1s 后放大重析，
  ~5s/次 M4 Pro，≤4 patch/selection，边缘细 5–10×）+ 组件加减交组合。
- **成本面**：图像编码每图 ~3s + 一次性 kernel 编译 ~6s；模型 **~3.4GB** 内存驻留
  （闲置 10 分钟卸载）；权重 = **Meta SAM License（非 OSI，不可入仓不可随发行版捆绑）**，
  HF `facebook/sam3` gated（需逐用户 token），三文件（model.safetensors / vocab.json /
  merges.txt）SHA256 + 精确尺寸锁定 + `.part` 原子晋升 + 断点续传 + 镜像列表 +
  条款确认对话框（`acknowledged: true` 命令门）。
- **推理面**：candle 纯 Rust 移植（32 层 ViT 2D RoPE + SAM2 prompt encoder + mask decoder
  + CLIP text encoder + DETR）——我方走 SAM 必是 CoreML 转换路线，**无官方转换件，
  ViT+DETR+CLIP 全族自转换 = 大件**；推理宿主复用 AIWorkerProtocol 第四腿（代价低）。
- **值得抄的设计**（若 SAM 路激活）：掩码存 **288×288 logits 量化压缩 ~10–30KB**，
  渲染/导出按分辨率采样**永不回模型**——库搬机/无模型机 mask 全功能。

### B4 能力对照 + 缺口判定

| LightCraft SAM 3 能力 | 我方 AI-01 现状 | 判定 |
|---|---|---|
| Object 点击精修 | layer B point 种子 + included/excluded 精修点 + layer A 实例勾选（07-3 已交付） | **已覆盖** |
| Describe 文本选择 | 无——Vision 零文本分割 API（B2 实测）；M2-10 CLIP 为图像级 embedding，无像素掩码 | **真缺口，原生无路** |
| 延迟 hi-res patch 精修 | layer B `regionOfInterest` + quality 三档可组合同构能力（未组装） | **可原生组装**（纯应用层） |
| Edge 羽化 | `MaskCombiner.blur` 羽化在册（07-1 D-07-1-T4-1） | **已覆盖**（±100 语义参数化为小件） |
| 掩码分辨率无关存储 | raster 16-bit PNG bake（分辨率绑定） | 观察：logits 快照先例（SAM 路激活再评） |

### B5 推荐

- **原生达标即收**（裁决④字面）：点击精修 / hi-res patch / 羽化三件 native 可达——
  M6-4 范围内做能力组装（scribble 激活与 patch 组装是否入本 phase = OQ-M6-4-5/6）。
- **Describe 文本选择 = 唯一不可达件** → 不达标部分挂账；SAM CoreML 大件**不**在本 phase
  启动（3.4GB 许可捆绑禁令 + 全族自转换工程 + 分发成本三重，V2 另裁，OQ-M6-4-7 留口）。

---

## Open Questions（OQ-M6-4-1..7，均带推荐；C 档第 1 停待裁）

- **OQ-M6-4-1（schema v5 落点）**：`stacks` + `stack_content` 两新表（join 表形态，
  UNIQUE(image_id) 一图一栈 DB 级不变量）vs `images` 侧加 `stack_id/stack_position` 列。
  **推荐前者**——album_content/version_ref 先例、images 冻结列清单零触碰、CASCADE 自动跟随
  图删；images 侧列方案省一次 join 但侵入冻结面且 ref_count 型计数无必要。
- **OQ-M6-4-2（auto-stack 语义）**：按 LightCraft 全套语义（gap 默认 60s 用户可调 +
  preview 只报数 + 时间排序相邻归簇 + runs ≥2 + 跳过已堆叠/无 capture + 结果落普通栈、
  不存 auto 出处）。**推荐 = 是**（bracket/burst 无专门检测，纯时间阈值与 Lightroom 同型）。
- **OQ-M6-4-3（分页 × 堆叠显示序）**：收起态 = SQL 谓词排除非封面成员（keyset 零扰动）；
  展开态 = 页内 adjacency fixup。**推荐 = 是**；替代方案（SQL 端 ORDER BY 栈键重排）伤
  keyset seek，不推荐。plan 期定 fixup 细节。
- **OQ-M6-4-4（merge 产物自动成栈）**：LightCraft `stack_with_ops` 先例（HDR/pano 产物与
  源图自动 collapsed 成栈）。**推荐 = 顺带做**（便宜高值），但我方 merge 产物现落 Session 域
  不经 `.lalb`——仅当 merge 产物入项目图库时成立，plan 期核落点后定。
- **OQ-M6-4-5（原生能力组装范围）**：本 phase 是否包含 hi-res patch 组装（layer B
  ROI+quality 延迟重析）与 Edge 羽化 ±100 参数化对齐。**推荐 = patch 组装入 M6-4 spike
  达标判据、羽化参数化顺带**（均为应用层小件）；spike 判据 plan 期定（ROADMAP 授权）。
- **OQ-M6-4-6（scribble 种子激活）**：`init(seedScribbleBuffer:)` SDK 在位、服务面 case
  已留。**推荐 = 本 phase 不激活**（UI 输入形态工程量不小，单列后续小件；缝保持）。
- **OQ-M6-4-7（Describe 缺口处置）**：SAM CoreML 大件挂 V2（ModelAssetStore 安装链 +
  AIWorkerProtocol 第四腿已备，贵在 3.4GB 许可捆绑禁令 + ViT/DETR/CLIP 全族自转换）。
  **推荐 = 挂账 V2，M6-4 内以「Describe 原生不可达」结论收口**；若用户裁定 SAM 立项，
  另开独立 phase（charter「大件另裁」）。

## 风险边界

- **R1 分页一致性**：展开态成员跨页拆分会破「成员聚拢」不变量——fixup 必须有界且幂等
  （plan 期负测钉）；收起态谓词方案无此风险。
- **R2 macOS 27.0b Vision 双 bug 尾巴**：`generateScaledMask` 双损坏（标签合成绕行在位）
  与 layer B pin abort（只许不 pin）——Apple 修复前不可依赖被绕行面；升级缝已在 AI-01 登记。
- **R3 MCP 投影对账**：M6-1 PhotoProjection 若按堆叠显示序透出，与网格面排序须同源
  （arrange 单源），否则 agent 看到的序与 UI 不一致。
- **R4 layer B 资产每机首下**：Apple 服务器下载 + 测试宿主 entitlement 阻断（GUI 真机
  复验先例）——spike 达标判据若涉 layer B，验收须走 GUI 轮或宿主外探针。
- **R5 UNIQUE 竞态**：拖拽组栈 UX 与「一图一栈」约束的竞态在 store 层单事务内消解
  （group 语义 = 整栈并入，LightCraft 同）。
- **R6 许可**：SAM 权重永不入仓/不随发行版（Meta SAM License）；LightCraft 代码逐字移植
  须 NOTICE（MIT OR Apache-2.0）；darktable GPL 零复制照旧。

## Sources

- LightCraft 本地 checkout：`/Volumes/UNITEK/Documents/Development/lightcraft`
  （`crates/catalog/src/stacks.rs` 全文、`crates/engine/src/cmd/organize.rs` stack 命令、
  `docs/ai-masks.md` 全文、`crates/segment/` 目录面）
- Alcedo 本地 HEAD：`/Volumes/UNITEK/Documents/Development/AlcedoStudio`
  （`alcedo_studio/src/ui/alcedo_main/qml/`、`sleeve/`、`docs/`——stacks 缺席核查）
- 本仓：`LightamerCore/Sources/Library/LibrarySchema.swift`（v4 冻结面 + 迁移缝）、
  `LibraryQueries.swift`、`App/Sources/Lightamer/Library/LibraryGridModel.swift`、
  `LightamerCore/Sources/AI/{AIMaskService,AIMaskTypes,AIAssetStatus}.swift`、
  `.work/gsd/phases/07-ai-modules/07-1-{SUMMARY,DECISIONS}.md`、
  `.work/gsd/phases/m4-3-depth/M4-3-CONTEXT.md`
- macOS 27 SDK：`Vision.framework/Headers/*` + `Vision.swiftmodule/arm64e-apple-macos.swiftinterface`
  （compile-probe 源与产物留在 /tmp，未入仓）
- 账面：ROADMAP §M6 M6-4 行 / REQUIREMENTS M6INT-02/03 / LIGHTCRAFT-NOTES §二面1·面8·§六
