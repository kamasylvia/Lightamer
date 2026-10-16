# M7-3 RESEARCH — MCP O2 反馈回路 + O3 项目与版本（MCP2-04..07）

```
phase:        M7-3
title:        MCP O2 反馈回路 + O3 项目与版本 research（render_preview compare+region /
              list_luts / project_open+create / list_versions）+ M7-2 挂账顺路件六项
status:       research-draft — C 档第 1 停（OQ-M7-3-1..10 待裁决，裁决前不进 plan）
baseline:     3877/35/0（M7-2 三路全套同值，ΔN=0 本批 doc-only）
date:         2026-10-17
input:        ROADMAP §M7-3 行 + REQUIREMENTS MCP2-04..07（:434-437）+ M7-2 VALIDATION §挂账
              （①-⑥ 单一清单）+ research/ALCEDO-CLI-AI-SURVEY.md 块一 O2/O3 面（:89/:106/:111/
              :250/:263-264）+ Alcedo 本地源对照（render_commands.cpp / project_commands.cpp /
              version_commands.cpp，GPL 只读对表）+ M7-2-CONTEXT D-M7-2-5/D-M7-2-7 + M2-8 版本面
              （SidecarVersionRecord/version_ref 投影）+ M6-1 单写者锁面 + FIX2 挂账③
red_lines:    ①MCP 快照族显式改——本波持 union 改动权（McpFinalSnapshotTests.swift 23→27 显式改；
              render_preview schema 变更连带 editing 域层 McpRegistrySnapshotTests 同批显式改）；
              M7-3..M7-5 串行禁并行 ②零新 SPM ③Alcedo GPL 代码/文案零复制零翻译（只对表命令语义）
              ④不改码（本批 doc-only）⑤--all 全套轮仍须 orchestrator 批准（research 零产线）
estimate:     1 plan（四工具 additive + render_preview 两参数 + 无头运行时开项目缝 + 快照族显式改
              + 顺路件六项 + parity/仲裁 golden）
```

## §0 结论摘要

1. **四件全部可 additive 落地，单源齐备，零新依赖、零新错误码**：
   - **O2 `render_preview` compare:root + region**：现工具已是完整的「渲染→sRGB JPEG 内联」腿
     （`QuickLookRenderer.renderedPlane` verbatim 消费，D7 预算帽 2048/q90 在位）。compare:root =
     同一渲染腿跑两遍（edited + pristine）；唯一新缝 = `renderedPlane` 加 additive 默认参
     `pristineOnly: Bool = false`（跳过 :236 `readDocument`，records=[] = 原图观感，与 pristine
     文档今日渲染逐位同）——既有三消费方（QL pane/parity 测试/MCP）默认参零 diff。region =
     渲染后 `CGImage.cropping` 归一化 0..1 裁剪（Alcedo 对照形；`get_detail_crop` 的绝对像素形
     是「源细节检视」用途，两工具语义分界写进 description）。**零新 render 代码**（红线维持）。
   - **O2 `list_luts` 小件**：`LutLibraryStore.shared` 公开读面三件齐备（`installedNames` :381 /
     `entry(named:)` :395 / `libraryGroups()` :443）——工具壳薄，只读投影，lut3d `lutName` 寻址键
     一句话写进 description（M2-5-3 KD-1 键纪律）。
   - **O3 `project_open`/`project_create`**：Core 面 `ProjectFileStore.create/open(role:)/
     openReadOnly` 三入口在位（LibraryProjectController 是其 GUI 形）；无头载体
     `headlessProjectStore` + 库 seam 每调用读载体（M7-2 T4 已铺）——运行时开项目 = 同载体
     park + 锁仲裁 typed 面（`projectHeldByOther` → `projectReadOnly(holder)` 既有映射）。
     **锁交互（OQ-1）**：v1 推荐双宿主形态——无头臂真开/真建（agent 全流程第一步的承载面），
     GUI 内嵌臂经 `LibraryProjectController` MainActor hop 同源路由（Alcedo 同构：automation
     寄宿 GUI host；conflict 对话框即仲裁 UI，conflict 发布 = typed `projectReadOnly` 应答）。
   - **O3 `list_versions`**：sidecar 单源（`readDocument` → `versions:[SidecarVersionRecord]` +
     `activeVersionID` + `chainStack`）——**不读 `.lalb` version_ref 投影**（投影 ≠ 真相，M2-8
     KD-3；双真相禁令）。与 `get_history` 分界 = D-M7-2-5 兑现：get_history 带 ACTIVE 链 items，
     list_versions 带版本树 meta + 每版本链计数 + `includeItems` 拉非活跃链。
2. **顺路件六项全部定位完毕，合计 ≈ 十行代码 + 一测试**（§4 逐项 file:line + 修法草案）；
   F-AC-4（union 注释「11 read」过时）随 union 显式改同批一行。FIX2 挂账③（import coalescer
   窄边界两枚）**本波不承载**——修法落点在 `LibraryProjectController` 尾部，而 O3 无头设计
   刻意不触该文件（Core `ProjectFileStore` 直用）；仅当 OQ-1 裁决 GUI 内嵌臂走 controller
   路由且该批触碰文件尾部时才顺手，否则留给 M7-4。
3. **快照族显式改范围（本波持改动权）**：union `McpFinalSnapshotTests` 23→27（冻结表 +3 行 +
   render_preview schema 行同批更新 + 计数断言 ×4 + `descriptionKeys` +4 + F-AC-4 注释一行）+
   editing 域层 `McpRegistrySnapshotTests` render_preview schema 行显式改（schema 字节变了，
   两层「consciously change together」）+ 新域层文件 `McpProjectToolsetTests`（project 族
   3 工具快照）+ union registry 装配点加 project context 参数。xcstrings：三/四新键尾块纯插入
   + `mcp_tool_desc_render_preview` **原位值改**（描述文本扩 compare/region 语义——非尾块插入，
   zh-audit 同批验证）。
4. **主域判定**：`project_open/create/list_versions` 落**新第四域 ProjectToolset**（Alcedo
   project/version 命令族同构；与 editing/culling/searchstate 四域并列——union 分层命名归位）；
   `list_luts` 归 **editing 域**（6→7；lut3d 模块参数的库读面，与 lut3d 参数寻址一体）。
5. **工作量 = 1 plan**；验收形态 = ROADMAP §M7-3 行三条（compare/region golden ✓ + project
   工具与单写者锁仲裁 fixture ✓ + 快照族零意外 diff ✓）。ΔN 预期 +12..+20。

## §1 输入正本（复述）

- **ROADMAP §M7-3 行**：`render_preview` 加 `compare:"root"`（原图对比出图）+ `region`（ROI）
  参数——agent 自评调色的 before/after 反馈闭环（Alcedo `render.preview` 语义对表）+ `list_luts`
  小件 + `project_open`/`project_create`（agent 全流程第一步；与 M6-1 项目单写者锁面交互
  plan 期定）+ `list_versions`（只读优先；变更类命令视单写者余量二期）。验收 = compare/region
  golden ✓ + project 工具与单写者锁仲裁 fixture ✓ + 快照族零意外 diff ✓。
- **REQUIREMENTS MCP2-04..07**（:434-437）：MCP2-04 = render_preview 反馈回路扩展（survey gap
  #18 高价值）；MCP2-05 = list_luts（Alcedo `lut.list` 对表，库面 M2-5 已有、工具壳薄）；
  MCP2-06 = project_open/project_create（Alcedo `project.open/create` 对表，锁交互 plan 期定）；
  MCP2-07 = list_versions（M2-8 版本面只读投影；变更类二期）。
- **Alcedo 同构锚**（survey + 本地源只读对表）：
  - `render.preview`（survey :111 + `render_commands.cpp`）：`out_dir`/`long_edge`（默认 2048、
    min 16）/`region`/**`compare`（none|root，默认 root——原图对比出图）**/`file_stem` → PNG
    文件（`<stem>_current.png`，compare:root 加 `<stem>_root.png`）+ 像素尺寸；region =
    **归一化 0..1 edit-space 矩形**（`ReadRegion` :68-84：x/y/w/h double，w/h 正，x+w≤1、
    y+h≤1，违反 = `/region` 参数错误），经 `view.visible_rect_in_edit_space` 作用于整组渲染
    （current 与 root 同一 rect）；两文件先建后写、一败双删（:226-244）。
  - `project.create(folder,name)` / `project.open(path)`（`project_commands.cpp` :126-185）：
    create 前置 folder 存在 + name 非空检查；open 前置 path 存在检查（**先检后关**——错路径
    保持当前项目不动）；两者都「已加载项目先关闭（persist=true）再进入新项目」，结果 =
    ProjectSummary `{path, name, entered, photo_count}`；`changes_state = true`。
  - `versions.list`（`version_commands.cpp` :40-48）：每版本 `{version_id, name, head_commit,
    active, created_at, updated_at}`（我方无 mini-git head_commit，对应物 = 链 `position/
    itemCount` 链态面）。
  - `lut.list`（survey :114）：LUT 库清单。
- **M7-2 挂账单一清单六项**（VALIDATION §挂账）→ §4 逐项承载；**快照改动权移交本波**
  （M7-2 VALIDATION 特殊事项 5：M7-3..M7-5 串行禁并行）。

## §2 现状测绘

### 2.1 O2 渲染面（render_preview 现体）

- **工具体**（`App/Sources/Lightamer/MCP/Tools/EditingToolset.swift`）：注册 + descriptor
  :774-819（schema 只有 `relPath`/`longEdge` 1..2048 默认 1024/`quality` 1..90 默认 85）；
  body :824-859 = `boundedWait(renderAndCrop 30s)` → `renderedPlane` → `image(from:)` →
  `encodeJPEG` → 单 `imageBase64` 内容。预算常量 :39-45（D7：2048 帽 = token 效率红线，
  更大走 export_image 落盘）。
- **渲染单源**（`LightamerCore/Sources/Export/QuickLookRenderer.swift` :220-316
  `renderedPlane`）：decode（:227-233）→ **`readDocument`（:236）** → sRGB 显示端链
  （:243-260）→ layer 重建（:263-272）→ 路由渲染 `longEdge` 目标（:276-295）→ exit leg →
  packedRGBA8（:307-315）。**pristine 语义在位**：document nil → `records=[]` → 空链 =
  原图观感——compare:root 的 root 臂 = 跳过 :236 读（§3.1）。
- **裁剪先例**（`CullingToolset.swift` :1060-1123 `detailCrop`）：绝对像素 ROI +
  `bounds.contains` → `roiOutOfBounds`（:1091-1095）→ `CGImage.cropping`（:1096）→ JPEG。
  预算常量族 `McpImageBudget`（:146-149）。
- **输出载体**：`McpToolOutput.content` 是**数组**（`McpToolRegistry.swift` :179-200）——
  compare:root 的双图内联无需改载体面。
- **超时面**：`McpTimeouts.renderAndCrop` 30s（:211-213，QL renderTimeout 同族）。

### 2.2 O3 项目面

- **Core 三入口**（`LightamerCore/Sources/Library/ProjectFileStore.swift`）：`create(name:
  role:)` :103（**新建即锁**——M6-1 M-OMP-4：fresh 项目进同款锁定态，防首实例无锁写）；
  `open(role:)` :158（heldByOther → typed `LibraryError.projectHeldByOther(holder summary)`
  :249）；`openReadOnly()` :199-238（锁免 + schema `stored == current` 守卫 + 写断路器）。
- **GUI 形**（`App/Sources/Lightamer/Library/LibraryProjectController.swift`，@MainActor
  @Observable）：`createProject(at:name:)` :132-143 / `openProject(at:)` :150-166
  （heldByOther → `pendingConflict` 对话框 **不 throw**）/ `openProjectReadOnly` :172-180 /
  `closeProject` :227-234（checkpoint 内置）。
- **无头臂**（`App/Sources/Lightamer/MCP/McpServerController.swift`）：启动期唯一开项目点 =
  `runHeadlessArbitrated` :303-415（`--project` 旗标；writer 臂 `open(role: .headless)` :310
  → `headlessProjectStore` park :169；heldByOther → guidance + `openReadOnly()` :327 同载体）；
  库 seam 每调用读载体（`makeHeadlessSearchState` :183-225）；EOF 优雅释放腿 :353-367
  （**仅 `--project` 启动路径 armed**）；锁 probe `makeProjectWriteProbe` :146-160；锁 URL
  推导 :305-306（`<stem>.lalb.lock`）。
- **typed 错误映射先例**：`EditingToolset.rejectIfProjectReadOnly`（EditingToolset.swift
  :175-183）——`McpProjectLockVerdict.held` → `McpToolError.projectReadOnly(verdict
  .errorMessage)`。**零新错误码**即可覆盖 project 族（§3.3）。

### 2.3 O3 版本面（M2-8）

- **sidecar 真相**（`LightamerCore/Sources/Sidecar/LightamerSidecar.swift`）：
  `versions:[SidecarVersionRecord]?` + `activeVersionID:String?`（v7 双键 :342/:348）；
  record = `{id, name, createdAt, updatedAt, chain?}`（:919-）；`chain == nil` = ACTIVE
  （items 住文档 `history` 键）；非活跃链 = `chainStack: HistoryStack?` 公开读面（FROZEN
  `{items, position}` 拼写）。
- **`.lalb` version_ref 投影**（`LibrarySchema.swift` :379-405 + `LibraryStore.swift`
  :491-560）：五列 reduced DDL + `replaceVersionRefs` 整表 reconcile + `versionRefs
  (elementID:)` 读缝——**注释自证「投影 ≠ 真相」（版本真相恒在 `.lra`）**。
- **get_history versions meta**（`SearchStateToolset.swift` :869-880）：`{id, name, createdAt,
  updatedAt, active}` 五键——D-M7-2-5 裁决「完整链投影归 M7-3」。
- **只读判域先例**：`historyKind` 五臂纯函数（:796-804）+ `historyItemCap` 500 截断保新端
  （:810）——list_versions 链 items 复用同两件。
- **GUI 消费面**（读缝零改声明）：VersionCoordinator / VersionsPanel 走 `chainStack` swap
  单路径——list_versions 只读投影不触任何写腿。

### 2.4 list_luts 面（M2-5-3）

- `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift`：`shared` 单例（锁内读，:115-123）；
  `installedNames: [String]` :381（root 相对 POSIX 路径键，排序）；`entry(named:)` :395
  （`InstalledLut{name, hash, is1D, size, title?, relativePath?, subdirectory?,
  rememberedEncodings?}`）；`libraryGroups()` :443（BuiltIn 领衔分组）。**零新读法**。
- 寻址纪律（KD-1）：`lut3d` params `lutName` 新写入恒存 key（根相对路径）；旧档裸文件名走
  唯一尾段 fallback——工具 description 一句话（「传 key 给 lutName」）即可防 agent 踩旧形。

## §3 四件语义测绘

### 3.1 `render_preview` 扩展（MCP2-04，O2 主件）

**入参新增两个（additive，schema 显式改）：**

- `region`：object `{x, y, w, h}`，全 double，**归一化 0..1**（Alcedo 对照；推荐 OQ-2）。
  语义 = 在**渲染后平面**上裁剪（`CGImage.cropping(to:)`，rect 乘以实际渲染宽高取整）——
  与 longEdge 解耦（缩放不变，agent 无需换算像素）；`get_detail_crop` 的绝对像素形是
  「源细节检视」用途（原生分辨率），两工具分界写进 description。校验：w/h ≤ 0 →
  `invalidParams`；越界（x+w>1 / y+h>1 / 负坐标）→ `roiOutOfBounds`（既有码，message 携
  归一化域）。region 同时作用于 current 与 root 两臂（同 rect，Alcedo 同构）。
- `compare`：enum `"none" | "root"`，**默认 `root`**（Alcedo 同默认——agent 每次渲染自动拿
  before/after，反零成本；OQ-3 备选默认 none 省载荷）。`root` 臂 = pristine 渲染。

**compare:root 渲染缝（唯一 Core 触点，additive 默认参）：**

- `QuickLookRenderer.renderedPlane` 加 `pristineOnly: Bool = false`（:220 签名尾部）；
  true 时跳过 :236 `readDocument`（`document = nil`、`records = []`、layerStack nil）——
  与「无 sidecar 文档的 pristine 图今日渲染」**逐位同路径**（同一空链分支），零新 render
  代码、零 kernel 触碰。既有消费方（QL pane :119-135 / parity 测试 / MCP body）默认参零 diff。
- MCP body 改形：compare:root 时同一 `boundedWait` 窗内跑两遍 `renderedPlane`（edited +
  pristine，共享 decode 候——pristine 臂传同 `decodeLeg` 即各解一次；共享 decode 属优化不属
  本波正确性面，OQ-5 附带）；输出 `McpToolOutput([.imageBase64(current), .imageBase64(root),
  .text(summary)])`，summary = `{"current":{width,height},"root":{width,height},"compare":
  "root"}`（内容序 = current 先、root 后，description 写明）。root 平面尺寸与 current 恒同
  （同 longEdge 同源）。
- **载荷预算**（OQ-3 附带）：compare:root 双倍 base64（1024/q85 每 ≈1.5MB → 双臂 ≈3MB/调）。
  D7 帽不变（2048/q90 上限双臂 ≈11MB——极端但 typed 可拒）；推荐**不做自动降档**（agent 显式
  要对比就给对比；预算边界 description 写明）。
- **超时**：双臂在既有 `renderAndCrop` 30s 单窗内（两遍 1024/2048 预览级渲染远低于单遍
  100MP 全流程耗时实测谱；不新加档——CONTEXT D-M7-2-3 档位红线延续）。
- **与 GUI 的显式偏离申报**：Alcedo 落 PNG 文件（out_dir/file_stem），我方内联 JPEG（D5/D7
  内联优先纪律不变）；Alcedo `long_edge` 默认 2048，我方默认 1024（D7 token 效率线，不动）。

**golden 面**：region golden = 合成图 fixture 上归一化 rect × 渲染尺寸取整 ≡ 手算像素框
（`CGImage.cropping` 输出尺寸断言）；compare:root golden = 同图 edited（sidecar 预置参数）
vs pristine 两平面 JPEG 尺寸恒同 + pristine 臂 ≡ 无 sidecar 图直接调 render_preview 的输出
（byte-equal 或像素容差随 parity 先例）；越界负测两臂（invalidParams / roiOutOfBounds）。

### 3.2 `list_luts`（MCP2-05，O2 小件）

- 入参：零（或 `group` 可选过滤——不推荐，v1 全量清单即可；库量级 = 内置 40 + 用户导入，
  响应小）。
- 出参：`{libraryRoot, total, luts: [{key, name, hash, is1D, size, title?, subdirectory?,
  rememberedEncodings?}]}`（key = `resolvedRelativePath` 即 registry 键；`entry(named:)`
  逐键投影）。`libraryGroups()` 不入 v1（分组是 GUI picker 面板形态，agent 面扁平清单够用；
  OQ-4 附带）。
- description 一句话：**「key 即 `lut3d` 模块 params `lutName` 的新写入寻址键」**（KD-1 纪律
  传达；旧档裸名 fallback 不在工具面叙述）。
- 只读 + `McpTimeouts.list`（10s；rescan 不触发——`shared` 单例已有扫描态，工具只投影内存
  registry）。
- 域归属 = **editing**（6→7）：lut3d 模块参数的库读面，`list_iops`（参数目录）同族。

### 3.3 `project_open` / `project_create`（MCP2-06，O3 主件）

**形态对表 Alcedo（folder/name / path 双入口）：**

- `project_open`：入参 `path`（string，必填——`.lalb` 包绝对路径）。前置校验：文件存在
  （不存在 → `invalidParams` 携路径，**先检后开**——Alcedo 同构：错路径不动当前项目）。
- `project_create`：入参 `folder`（string，必填，须为已存在目录）+ `name`（string，必填
  非空；包名 sanitize 复用导出命名 sanitize 先例或最小黑名单）。包 URL = `folder/<name>.lalb`；
  已存在 → `invalidParams`（不覆盖——Alcedo create 语义 + AutomationNewOutputFile 同纪律）。
- 两工具出参 = ProjectSummary 同构：`{path, name, readOnly, heldByOther}`（我方无
  photo_count 即时面——`LibraryQueries` count 可查但 open 应答要快；OQ-6 附带：v1 不带计数，
  agent 需要时 `search_photos`/`list_photos` 自取）。

**宿主形态（OQ-1 核心）：**

- **无头臂（承载面）**：writer 立在场内（endpoint writerCheck 过了才到 body）→
  `ProjectFileStore(at: url)` + `open(role: .headless)` / `create(name:role: .headless)` →
  park `headlessProjectStore`。**库 seam 立即活**（closure 每调用读载体——零额外接线）。
  heldByOther → `LibraryError.projectHeldByOther` → **typed `projectReadOnly(holderSummary)`
  应答**（既有映射形；holder summary 从锁 payload 读，`SingleWriterLock.readPayload` 面）。
- **项目切换**：已持有项目时 open/create 先关后开（Alcedo 同构 persist 语义 = 我方
  `store.close()` checkpoint 内置）。只读臂现 store（openReadOnly 载体）同理释放。**失败
  中间态纪律**：close 成功 open 失败 → `headlessProjectStore = nil`（诚实空态，agent 重试
  open；禁半开态）。
- **EOF 释放腿**：运行时开项目路径**未 armed**（:353 watcher 只在 `--project` 启动路径）——
  推荐 plan 期补一形：首次运行时 open 成功后 arm 同款 stdin HUP watcher（幂等 guard 一行）；
  不补 = 进程退出兜底（kernel 释放地板，M6-1 语义允许但丢 checkpoint 优雅面）。OQ-7。
- **`get_state` 联动**：`makeHeadlessSearchState` 的 liveState 快照 :210-223 是**启动期
  捕获值**（projectURL/isWriter 闭包捕获）——运行时开项目后 project/server 面会 stale。
  修形 = liveState closure 改读「当前项目盒」（carrier + 可变 currentURL 小盒，per-call
  重取），plan 期落；顺带把 OQ-F-AC-2 的 probe 透传同缝带上（§4②）。
- **GUI 内嵌臂（OQ-1 裁决点）**：推荐 **同源路由**——MainActor hop 经
  `LibraryProjectController.openProject/createProject`（Alcedo 同构：automation 寄宿 GUI；
  单源复用零新路径；heldByOther 时 controller 走 `pendingConflict` 对话框**不 throw**，
  工具应答判别 = 调用后 `projectStore == nil ∧ pendingConflict != nil` → typed
  `projectReadOnly(holder)`——「对话框已发布、等用户裁决」的诚实应答）。备选 = v1 无头 only、
  内嵌臂 typed 拒（降级可后补）。**requiresWriter: true**（双宿主一致：状态变更面走 endpoint
  writer gate；只读臂天然 serverReadOnly 拒——held 臂不能换项目，语义正确）。
- **错误码零新增**：`invalidParams`（路径/目录/name 校验）+ `projectReadOnly`（held/
  conflict/只读 stance）+ `internalError`（open/create I/O 失败兜底，携 LibraryError
  detail）+ `serverReadOnly`（registry writer gate 自动）。超时 = `McpTimeouts.apply`
  （10s：close-on-switch 含强制 checkpoint，5s metadataWrite 贴线）。

**锁仲裁 fixture（ROADMAP 验收形态②）**：`McpProjectArbitrationTests` 序列 A/B fixture
先例——进程 A 持锁 → project_open → typed `projectReadOnly` + holder summary；A 退出 →
重试成功（自然恢复）；自持切换腿（open B while holding A = close A checkpoint → open B）；
create 已存在拒 / create folder 缺失拒。

### 3.4 `list_versions`（MCP2-07，O3 只读件）

- **寻址**：`get_history` 双地址制 verbatim 复用（digits 库 id 经 `LibraryStore.image` +
  ImageLinker / open-session relPath；`resolveImageURL` :951-998 直调——零新寻址面）。
- **入参**：`image`（必填）+ `includeItems`（bool 默认 false——true 时每版本附链 items，
  复用 `historyKind` 五臂 + `historyItemCap` 500 保新端截断 + `position/itemCount` 真值，
  get_history F-5 同语义逐版本套用）。
- **出参**：`{image, activeVersionID, versions: [{id, name, createdAt, updatedAt, active,
  position, itemCount, [items?] }]}`。**ACTIVE 版本**（`chain == nil`）：meta 同构 +
  `position/itemCount` 读文档 `history`；`includeItems` 时 items 同样来自文档 `history`
  （与 get_history 主面同源——**分界**：get_history 只有一条 ACTIVE 链且带 note/keywords/
  rating 元数据面；list_versions 是版本树 + 非活跃链通道，两者 items 面对同一 ACTIVE 链
  重复属可接受冗余（同源同投影，无双真相），description 一句话写明分工）。
- **单源声明**：sidecar `readDocument` 唯一真相；**不读 `version_ref`**（`.lalb` 投影 =
  GUI 库域检索面，可滞后；读了 = 双真相违 M2-8 KD-3）。version_ref 在本工具零角色。
- **只读**：`requiresWriter` 缺省 + `readOnlyHint: true`；无 create/branch/checkout/rename/
  remove（变更类 = ROADMAP「视单写者余量二期」，checkout 即 M2-8 swap 写腿——不在本波）。
- 超时 `McpTimeouts.list`（10s；sidecar 读 + 链解码，500 帽内远低于贴线）。

### 3.5 域归属与命名（OQ-4）

- **ProjectToolset 新第四域**：`project_open` / `project_create` / `list_versions` 三工具
  （Alcedo project/version 命令族同构；与 M7-2 search/state 分域同理——锁仲裁语义自成一族，
  快照第 5 层命名归位）。`list_luts` 入 **editing 域**（6→7）。
- union 分层变为 editing(7) + culling(14) + searchstate(3) + project(3) = **27**。

## §4 顺路件六项落点测绘（每项 file:line + 修法草案）

| # | 项 | 落点 | 修法草案 |
|---|---|---|---|
| ① | **F-AC-1 FilterSQL `.library` 域快照补申报** | `Tests/LightamerTests/FilterSQLTests.swift`（Library bundle，Project.swift :586 已登记——零 Project.swift 改）；单源 = `LightamerCore/Sources/Session/FilterSQL.swift` :115-124（`orderBySQL(domain:)` library 臂）+ `LightamerCore/Sources/Library/LibraryQueries.swift` :633-634/:673-674（`.library` 调用点） | 新法 `testLibraryDomainSnapshots()`（同型 `testNumericSnapshots` :30-91）：`FilterSQL.translate(group:domain: .library)` 对 rating gte / flag eq / iso lt / captureDate gte / focalLength between / keywords contains 断 WHERE+bind 串（钉住现字节 = 快照法，非新写 SQL）；如 keywords 四子句在 library 域为物化列形则同法补第二法。**申报注记随 DECISIONS**（F-AC-1 二选一收口的两路同时兑现：快照补 + DECISIONS 一段） |
| ② | **F-AC-2 headless searchState 透传 projectWriteProbe** | `App/Sources/Lightamer/MCP/McpServerController.swift` :183-225 `makeHeadlessSearchState`（现不收 probe，context 无 projectWriteProbe）；调用点 :374-375 | `makeHeadlessSearchState` 加参 `projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil`，context init 带入；:374 调用点传既有 `probe`（:370 已建）。默认参 = 既有测试构造零 diff。效果：headless `get_state.control.lock` = verdict 真值（writer 臂 self-held writable / 只读臂真 probe）。**与 §3.3 get_state 联动改同缝落** |
| ③ | **N2-1 pristine 面补 `truncated` 键** | `App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift` :833-847（pristine payload 十三键无 truncated；正常面 :886 恒有） | payload 字典加一行 `"truncated": .bool(false),`——形状一致化，零 schema 语义变；`McpSearchStateToolsetTests` pristine golden 同批字节更新 |
| ④ | **N2-3 fulltext 闭包窄竞态 typed 抛** | `App/Sources/Lightamer/MCP/McpServerController.swift` :204-209（`guard let store else { return [] }` 静默空——与「never a silent empty result」头注纪律表层相悖） | 改 `guard let store else { throw McpToolError.notSessionMember(McpSearchStateToolset.noOpenProjectMessage) }`（闭包签名已 `async throws`；消费点 SearchStateToolset :697 `try await` 已接）。typed 面与 library seam 缺席同文案（noOpenProjectMessage 单源） |
| ⑤ | **N2-4 `requestFailed` 显式测试** | `Tests/LightamerTests/McpSearchStateToolsetTests.swift` :566-615（F-3 家族映射法已覆盖 workerUnavailable/workerCrashed/workerExhausted 三案，缺 `.requestFailed`） | 既有法内补一臂（两行）：`registryFor(AIWorkerClientError.requestFailed("boom"))` → 断 `code == "modelUnavailable"`——F-3 族表四案闭合；或独立小法。**先核实** `AIWorkerClientError.requestFailed` 关联值形态（`AIWorkerClientTests.swift` :135 显示 `requestFailed(let message)`）后照抄 |
| ⑥ | **cursor 跨调用稳定性边界注记** | 无码面——VALIDATION ⑥「登记维持（DECISIONS §4）」 | 本波 DECISIONS 承接一句（边界口径不变：库重排后旧 cursor 可能跳行/漏行，不引入版本戳）；list_versions/project 族无 cursor 面，零新增边界 |
| 附 | **F-AC-4 union 注释「11 read」过时** | `Tests/LightamerTests/McpFinalSnapshotTests.swift` :210（「exactly 9 destructive tools, 11 read」——现 14 read，union 后再变） | 随 union 显式改同批：改写为非易碎形（「the 9 destructive tools are the §A write face + match_color; the remainder are read-only or non-destructive state-changing（project_open/project_create）」），消除未来计数漂移 |

**FIX2 挂账③（import coalescer 窄边界两枚：throw-path stale-interim + flushTerminal-vs-tail
竞态，同根修法 = tail 处 `cancelAndClear()`）——本波默认不承载**：修法落点
`LibraryProjectController.swift` 尾部（ImportProgressCoalescer 消费段），而 O3 无头设计
Core `ProjectFileStore` 直用不触该文件；仅当 OQ-1 裁决 GUI 内嵌臂 controller 路由且批内
触碰该文件尾部时顺手同批（DECISIONS 申报），否则留 M7-4。

## §5 集成缝测绘

### 5.1 注册缝（additive，装配点唯一）

- 新 toolset 文件 `App/Sources/Lightamer/MCP/Tools/ProjectToolset.swift`：
  `McpProjectContext`（seam 结构体，provider closure 全注入）+ `McpProjectToolset
  .registerAll(on:context:)` 注册三工具。context faces：
  - `openProject: @Sendable (URL) async throws -> ProjectOpenOutcome`（宿主形态注入——
    无头臂 = Core 直开形；GUI 臂 = controller MainActor hop 形；**工具体不直接 import
    controller 类型**，F-6 源隔离纪律延续）
  - `createProject: @Sendable (URL, String) async throws -> ProjectOpenOutcome`
  - `currentProject: @Sendable () async -> (url: URL, readOnly: Bool)?`（list_versions
    前置面？——**不需要**：list_versions 走 image 寻址，与 get_history 同域，挂
    SearchState context 或自携 seam；推荐**挂 searchState context** 复用
    `library/sessionPair/resolveImageURL`——但跨 toolset 消费 context 违背单域自持……
    备选：ProjectToolset 自携同形 `library/sessionPair` 两 seam（复制 provider 装配而非
    复制逻辑——装配点共享同一闭包变量，零双真相）。OQ-8 裁决）
  - `listVersions` 的读缝 = `readDocument`（Core 静态，无注入需求）
- `list_luts` 入 EditingToolset：`register(into:seams:)` 追加一注册（+ descriptor + body）；
  LutLibraryStore.shared 直读（IOP 层公开单例，editing seams 无需新 face）。
- `makeRegistry` 追加第四参 `project:`（默认 nil = 既有构造零 diff）；三宿主装配点
  （GUI :1383 段 / stdio :378 / http :390/:410）传 context。

### 5.2 快照族（本波显式改范围——改动权已移交）

| 层 | 文件 | 本波动作 |
|---|---|---|
| editing 域 | `McpRegistrySnapshotTests.swift` | render_preview schema 行显式改（region+compare）；list_luts 行加入（6→7 + 计数断言） |
| culling 域 | `McpCullingToolsetTests.swift` | 零触 |
| search/state 域 | `McpSearchStateToolsetTests.swift` | pristine golden `truncated` 字节同批（N2-1）；+`requestFailed` 一臂（N2-4）；工具面零变 |
| **project 域（新）** | `McpProjectToolsetTests.swift`（新文件） | 三工具 name/description/schema 快照 + 白名单负测 + domain 层计数 |
| **union** | `McpFinalSnapshotTests.swift` | all23→**all27**：render_preview schema 行同批更新 + searchState 不变 + project 三行新入；计数断言 ×4（:209/:246/:274/:421）23→27；`descriptionKeys` +4 行（`mcp_tool_desc_project_open/_project_create/_list_versions/_list_luts`）；`makeUnionRegistry` :190-200 加 project context（all-nil fixture 同形）；F-AC-4 注释一行（:210） |

- **两层 consciously change together**：render_preview schema 字节变 = editing 域层 +
  union 层同批显式改（M5-1-03 match_color 先例形）。
- Project.swift：`McpProjectToolsetTests.swift` 入 App 测试数组显式清单（:833 段）+
  BUNDLE-MAP 恰一行 + **`tuist generate` 恒为该批最后一个动作**（L041）。

### 5.3 xcstrings / 键族

- 新键（尾块纯插入）：`mcp_tool_desc_list_luts` / `mcp_tool_desc_project_open` /
  `mcp_tool_desc_project_create` / `mcp_tool_desc_list_versions`（4 键 zh-only 形）。
- **原位值改**：`mcp_tool_desc_render_preview`（en defaultValue + zh 译文同批——描述扩
  compare/region 语义；非尾块插入，zh-audit `--check` 对账 source keys 数 +4）。
- UserDefaults：零新键（project 工具不记忆路径——agent 每调显式传；recent list 是 GUI 面，
  MCP 开的项目**不入 recent**（OQ-9 附带，防 GUI 最近列表被 agent 轮次污染））。

## §6 测试策略（验收形态兑现）

1. **compare/region golden（ROADMAP 验收①）**：合成 fixture（McpCullingImageBudgetTests
   makeGradientCGImage 先例 / 无 sidecar 的假 RAW 走 decodeLeg 注入缝）：
   - region：归一化 rect × 渲染平面尺寸 → `CGImage.cropping` 输出宽高断言 ≡ 手算取整；
     越界两臂 typed 拒；region+compare 组合臂（同 rect 双图）。
   - compare:root：edited（fixture sidecar 预置）vs pristine 两平面；pristine 臂输出 ≡
     无 sidecar 同图直调 render_preview（自证同一渲染腿）；`pristineOnly` 默认参负测
     （不传 = 既有行为字节不变——Core additive 零 diff 钉）。
   - 载体序：内容数组 [current, root, text] 序断言。
2. **project 锁仲裁 fixture（ROADMAP 验收②）**：两进程锁形（`McpProjectArbitrationTests`
   先例）：held → typed `projectReadOnly` + holder summary；释放 → 自然恢复；自持切换
   （checkpoint 释放腿）；create 存在拒/缺失拒；只读臂（writerCheck false）→
   `serverReadOnly` 前置拒；运行时 open 后 `get_state.project` 面即时性（liveState
   per-call 重取腿）。
3. **list_versions golden**：fixture sidecar（versions 三条：ACTIVE + 两非活跃带链）→
   投影 JSON byte-equal；`includeItems` 两档；链 500 帽截断保新端（F-5 同式逐版本）；
   digits/relPath 双地址臂；与 get_history 同源断言（ACTIVE 链 items 两工具恒等）。
4. **list_luts golden**：临时根 fixture（M2-5-3 LutLibraryStore 测试先例形）seeded .cube
   → 投影 ≡ `installedNames`/`entry(named:)` 直调（单源恒等式）；键形断言（根相对 POSIX）。
5. **快照族零意外 diff（ROADMAP 验收③）**：union 27 + editing 7 + project 3 全点位显式改
   亲核；既有 20+3 工具 descriptor/schema 零 diff（除 render_preview 申报内字节）；
   `McpHostTests`/`McpEditingToolsetTests` 全绿。
6. **顺路件回归**：FilterSQL `.library` 快照法绿（Library bundle 定向轮）；
   `McpSearchStateToolsetTests` pristine golden 更新 + requestFailed 臂绿；headless
   `get_state.control.lock` 真值断言（F-AC-2 兑现腿）。
7. **零回归**：收尾跑定向 APP + Library bundle（`Scripts/test-direct.sh --bundle App
   --bundle Library`）；全套 `--all` 留 phase 收口（orchestrator 批准制）。
8. **zh-audit**：`--check` PASS（4 新键 + 1 原位改）+ `--self-test` PASS。

## §7 OQ-M7-3-1..10（每条带推荐）

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| 1 | `project_open/create` 宿主形态：GUI 内嵌臂走 controller 同源路由，还是 v1 无头 only？ | **双宿主同源**（Alcedo 同构：automation 寄宿 GUI；controller 是开项目单源；conflict 对话框 = 仲裁 UI，conflict 发布 → typed `projectReadOnly(holder)` 应答） | 无头 only（内嵌臂 typed 拒——降级可后补，DECISIONS 申报） |
| 2 | `region` 坐标契约：归一化 0..1（Alcedo 对照）还是绝对像素（get_detail_crop 同形）？ | **归一化 0..1**——与 longEdge 解耦（缩放不变，agent 免换算）；Alcedo 同构；两工具分界（detail_crop=源细节检视原生分辨率 / render_preview region=渲染观感 ROI）写进 description + M7-6 SKILLS-01 | 绝对像素（与 detail_crop 同形但需声明坐标系基准面〔渲染后 vs 原生〕，歧义更大） |
| 3 | `compare` 默认值：`root`（Alcedo 同默认，每调自动 before/after）还是 `none`（省载荷）？ | **默认 `root`**——反馈回路的语义即对比；显式 `none` 供省载荷；载荷预算（双臂 ≈3MB@1024）写进 description | 默认 `none`（agent 忘传 compare 就丢了 before/after——回路退化） |
| 4 | 域归属：project 三工具立第四域 ProjectToolset + list_luts 入 editing（6→7）？ | **是**——Alcedo 命令族同构 + union 分层命名归位；list_luts 与 lut3d 参数寻址同族 | list_luts 也入 ProjectToolset（四工具一域——但 LUT 与 project 语义无 affinity）；list_versions 入 searchstate 域（与 get_history 同面——但版本树是 project 语义面） |
| 5 | compare:root 双臂是否共享 decode（一次解码两遍管线）？ | **v1 不共享**（两臂各走 renderedPlane verbatim——零新 render 代码红线最简兑现；性能损失 = 多一次 decode，预览级可忽略）；共享 decode 属后续优化若实测慢再立项 | 共享 decode（renderedPlane 需再开缝——Core 触点扩大） |
| 6 | ProjectSummary 是否带 photo_count（Alcedo 同构字段）？ | **v1 不带**——open 应答要快（count 需额外查询）；agent 需要时 search_photos/list_photos 自取；字段缺席 = schema 自描述诚实面 | 带 count（open 同步查 COUNT——SQLite COUNT(*) images 单查询快，可接受；Alcedo 同构加分） |
| 7 | 无头运行时开项目的 EOF 释放腿：首次 open 成功后 arm stdin HUP watcher？ | **是**（幂等 guard 一行；M6-1 checkpoint 优雅面延续到运行时开项目路径） | 不 arm（进程退出 kernel 释放地板——丢优雅 checkpoint，DECISIONS 申报偏离） |
| 8 | list_versions 的库/会话 seam：ProjectToolset 自携同形两 seam（装配点共享闭包变量），还是复用 searchState context 实例？ | **自携同形两 seam、装配点共享同一闭包值**（单域自持 = F-6 纪律；provider 逻辑零复制——GUI/无头装配点把同一 closure 赋给两个 context） | ProjectToolset 直接消费 McpSearchStateContext（跨域耦合，快照白名单语义混） |
| 9 | MCP open/create 的项目是否入 `library.recentProjects`？ | **否**——recent 是 GUI 用户面；agent 批量轮次会污染最近列表；controller 的 promoteRecent 仅 GUI 臂自然触发（无头臂不经 controller，天然不入）——DECISIONS 一句话钉死 | 入 recent（Alcedo 无此概念，无从对表；污染面真实） |
| 10 | `project_open` 对 stub/旧 schema 包：writer 臂 migrate（写腿）还是拒？ | **writer 臂照常 migrate**（`open(role:)` 既有语义；agent 拿到的是完整可写项目——与 GUI open 同构）；migrate 失败 = `internalError` 携 detail | 拒旧 schema（逼用户先 GUI 打开——多一步，无收益） |

## §8 plan 拆分建议（1 plan）

- **T1 = O2**：`renderedPlane` additive 默认参（pristineOnly）+ render_preview
  region/compare（descriptor/schema/body/裁剪/双臂输出）+ `list_luts`（editing 域注册）
  + region/compare golden + editing 域层快照显式改 + `mcp_tool_desc_render_preview`
  原位改 + `mcp_tool_desc_list_luts` 新键。
- **T2 = O3**：`ProjectToolset.swift`（context + 三工具）+ 无头运行时 open/create 缝
  （载体 park + EOF watcher arm + liveState per-call 重取 + F-AC-2 probe 透传同缝）+
  GUI 臂 controller 路由（OQ-1 裁决行使）+ 锁仲裁 fixture + list_versions golden +
  project 域快照新文件。
- **T3 = 顺路件 + 快照收尾**：顺路件①-⑤+F-AC-4（§4 逐项）+ union 23→27 全点位 +
  Project.swift/BUNDLE-MAP 登记 + `tuist generate` 恒末位 + xcstrings 4 新键 + zh-audit
  + 定向 App/Library bundle 轮 + SUMMARY/DECISIONS + REQUIREMENTS MCP2-04..07 翻账
  + TODO/GOAL-STATE。
- SC 判定式：compare/region golden ✓ + 锁仲裁 fixture ✓ + 快照族零意外 diff（显式改
  全点位亲核）✓；ΔN 预期 +12..+20；全套轮留收口。

## §9 风险与边界

- **render_preview schema 变更波及面**：非纯 additive——既有 `render_preview` descriptor
  schema 字节变（+region/compare 属性）。所有引用该 schema 字符串的面同批显式改：union
  冻结表 + editing 域层。**快照串行红线维持**（M7-3..M7-5 禁并行派发）。
- **GUI 内嵌臂 controller 路由**（若 OQ-1 行使推荐臂）：`openProject` 的 conflict 发布
  不 throw——判别缝（projectStore nil ∧ pendingConflict != nil）必须与 controller 实现
  对表测试（controller 本波若被触碰，FIX2③ 顺手窗口开启，DECISIONS 申报）。
- **运行时开项目的状态面**：liveState startup 捕获 → per-call 重取改形必须同批落地，
  否则 `get_state.project` 在 open 后说谎（诚实面纪律）；headlessProjectStore 静态盒
  的第二个写者（工具 body）= `nonisolated(unsafe)` 既有形延续，单线程 writer gate 内
  写入（apply 同款串行面）。
- **region 与 EXIF orientation**：`renderedPlane` 输出已是 orientation 归一后的显示平面
  （decode 链内处理），归一化 rect 作用于显示平面——description 写明「region 相对渲染
  输出画面」即可，无第二坐标系。
- **GPL 边界**：Alcedo render_commands/project_commands/version_commands 只读对表（区域
  归一化/先检后关/版本树 JSON 形为语义参照）；我方 schema/参数名/文案全自写。
- **载荷膨胀**：compare:root 双臂 + region 大 rect（接近全图）= 极端调用 ≈11MB base64
  ——typed 帽在位（2048/q90），description 边界一句话；不做服务端降档（诚实拒绝优于
  静默缩水）。
- **零回归面申报**：不改 registry 错误码表（16 档封闭维持）、`McpTimeouts`（零新档）、
  PhotoProjection、session 域查询、sidecar 写面、`.metal`、导出矩阵；Core 新触点仅
  `renderedPlane` additive 默认参一处（parity/QL 消费方默认参零 diff 钉死）。
