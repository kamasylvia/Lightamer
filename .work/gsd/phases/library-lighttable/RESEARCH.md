# 图库三栏布局(dt lighttable 同构)调研报告

> lane: zcode 只读侦察 / 2026-11-02 / HEAD 字节
> 用户令:「首次打开软件,就应该进入图库,呈现三栏布局。仿照 dt,左侧是文件树和图片信息,右侧是可应用的操作,例如批量复制、批量应用、删除、批量标签等。」
> 首启进图库已由 `5bb31915` 落地(LibraryFirstLaunch 默认库直开)——本案 = 图库面三栏重设计。

## 1. dt lighttable 解剖(HEAD = release-5.7.0-1304-g37d514c78c)

### 1.1 布局骨架

dt lighttable 视图的面板分布(经 lib 模块的 `container()` 声明):

- **左栏**(`DT_UI_CONTAINER_PANEL_LEFT_CENTER`):collect(集合规则堆叠)、tagging(标签树)、recentcollect、geotagging、histogram 等。
- **右栏中段**(`DT_UI_CONTAINER_PANEL_RIGHT_CENTER`):**metadata_view(模块名 "image information")→ image(模块名 "actions on selection", position 700)→ select(模块名 "selection", position 800)→ copy_history("copy history")→ styles("styles")→ export** 自上而下排列。
- 模块在面板中的归属可由用户拖拽重排,但默认形态 = 上表。

### 1.2 左栏之一:collections(collect.c,4601 行)

- **数据模型 = 规则堆叠,不是纯文件树**:`dt_lib_collect_t.rule[MAX_RULES]`(collect.c:56,86),每条规则 `dt_lib_collect_rule_t` = 属性枚举 + 模式 + 字符串(collect.c:69-82)。最多 10 条规则 AND 叠加过滤全局 collection 查询。
- **属性全集**:`dt_collection_properties_t`(common/collection.h:74-138)——filmroll / folders / filename / camera / lens / aperture / exposure / focal_length / iso / day / time / 各时间戳 / geotagging / aspect_ratio / **tag / colorlabel / metadata** / local_copy / history / module / order / rating_range / textsearch / rating / whitebalance / flash / exposure_program / metering_mode / group_id / exposure_bias / duplicates / month / dimensions,30+ 维。
- **树视图**:当前规则的值域按层级展开到 `GtkTreeStore`,8 列(collect.c:124-135):TEXT / ID / TOOLTIP / PATH / VISIBLE / UNREACHABLE / **COUNT**(每节点计数)/ INDEX。folders 属性 → 文件系统目录树;tag → 标签层级树;day → 日期层级树。树/列表双视图切换(collect.c:1540 `_tree_view` / 2063 `_list_view`)。
- **交互**:双击树节点 = 把该节点的值写回当前规则(collection 查询重算);规则条可增删、启停。
- **与本项目同构认知**:我方 `ExifSearchFilter` + `LibraryInspectorModel.FilterArm`(点击 fold 一条 typed arm + breadcrumb 退栈,LibraryInspectorModel.swift:45-56)正是 dt 规则堆叠的 SwiftUI 翻译,已有先例可续。

### 1.3 左栏之二:image information(metadata_view.c,1881 行)

- 模块名 `_("image information")`,元数据**行集**约 40 行,按组排布(metadata_view.c:137-179):
  - 身份组:filmroll / image id / group id / filename / version / full path / local copy / 各时间戳 / flags
  - EXIF 组:maker / model / lens / aperture / exposure / exposure bias / exposure program / white balance / flash / metering mode / focal length / 35mm equiv / crop factor / focus distance / ISO / datetime / width / height / export width / export height
  - 地理组:latitude / longitude / elevation
  - 内容组:tags / categories
- 展示对象 = **单张图**(悬停图优先,否则当前图);纯只读面板,零操作按钮。

### 1.4 右栏:actions on selection(image.c,896 行)

**这就是 dt 右栏批量操作面板的正本**(任务书问的 "actions on selection 实现" = `src/libs/image.c`,5.x HEAD 在位、未移除):

- `name()` 返回 `_("actions on selection")`(image.c:72-75),容器 `DT_UI_CONTAINER_PANEL_RIGHT_CENTER`(image.c:82-85),position 700。
- **两个 tab**(image.c:503-504):
  - **tab "images"**(批量图片操作,image.c:514-599):remove(从库移除)/ delete(物理删除,trash 偏好切文案)/ move... / copy... / create HDR / duplicate(⌘D)/ duplicate virgin(⌘⇧D)/ rotate CCW·CW·reset / copy locally / resync local copy / **group**(⌘G)/ **ungroup**(⌘⇧G)。
  - **tab "metadata"**(批量元数据,image.c:602-660):**copy / paste / clear metadata** 三按钮 + 五个成分开关(ratings / colors / tags / geo tags / metadata,`dt_lib_metadata_id` 位掩码 image.c:62-70)+ pastemode(merge / overwrite 二选,image.c:646-653)+ refresh EXIF + monochrome / color。
- **copy/paste 元数据语义**(image.c:326-406 `_execute_metadata`):copy = 把当前单选记为源(`d->imageid`,image.c:408-416);paste = 对每个成分按源图取值,`dt_ratings_apply_on_list` / `dt_colorlabels_set_labels` / `dt_metadata_set_list_id` / `dt_image_set_locations` / `dt_tag_set_tags` 批量落到 act-on 集;clear = 五成分清零。paste 的 enabled 条件 = 已 copy + (多选 或 单选≠源图)(image.c:201-203)。
- **对 selection 的生效机制**(全 dt 统一):`dt_act_on_get_images(only_visible, force, ordered)`(common/act_on.c:380-401)——统一"作用集合"解析器,带双缓存(act_on_cache_visible / _all);两种算法(common/act_on.c:369-377):
  - **selection 算法**:`dt_selection_get_list(darktable.selection, ...)` = SQLite 表 `main.selected_images` 的有序读出;
  - **hover 算法**(culling 双栏布局用):悬停图 → 鼠标在表内 → 选区 三级优先(common/act_on.c:424-449 的表)。
- **按钮置灰逻辑**(image.c:192-276 `gui_update`):每个按钮按 `dt_act_on_get_images_nb()`(0 / 1 / >1)与 `dt_collection_get_selected_count()` 动态 sensitive——"N 张选中才 enabled"的机检语义由集中 refresh 保证,信号源 = DT_SIGNAL_SELECTION_CHANGED / COLLECTION_CHANGED / MOUSE_OVER(image.c:671-674)。
- **undo / 落盘**:`dt_undo_start_group / dt_undo_end_group`(undo_type 位掩码,image.c:343-350)+ `dt_image_synch_xmps(imgs)` XMP 批同步(image.c:393)+ `dt_collection_update_query(..., RELOAD, ...)` 触发网格重载(image.c:394-397)。

### 1.5 右栏:selection(select.c,385 行)

- 五按钮(select.c:142-160):select all(⌘A)/ select none(⌘⇧A)/ invert selection(⌘I)/ select film roll / select untouched;gui_update 按 selected_cnt vs collection_cnt 置灰(select.c:68-84)。

### 1.6 selection 模型(selection.c,580 行)

- **选区 = SQLite 表 `main.selected_images`**(单列 imgid),非内存集合——所有批量操作直接 `SELECT imgid FROM main.selected_images`(image.c:98-100 的 group helper 即此形态),跨面板/跨视图共享、天然有序。
- API(selection.c):select / deselect / select_single / toggle(:264)/ select_all(:297)/ clear(:191)/ invert(:161,`INSERT OR IGNORE ... SELECT imgid FROM collection查询 WHERE imgid NOT IN selected` + 清表,同事务两条 SQL)/ select_filmroll / select_unaltered / select_list / get_last_single_id(:210)。
- **select all 的语义 = 整个 collection 查询入库**,不是"已加载页全选"——与分页网格的常见偏差点(dt 网格也分页渲染,但选区独立于视口)。
- 视图联动(views/lighttable.c):单击 = `dt_selection_select_single`(:1155)/ ⌘单击 = `dt_selection_toggle`(:1149)/ 空白单击 = select_single(:106)。

### 1.7 右栏其余批量模块

- **copy_history.c(358 行,"copy history")**:copy(整链复制,`dt_history_copy`,:205)/ paste 到多选(`dt_control_paste_history`,:247)/ **selective copy...**(部分模块勾选复制,`dt_history_copy_parts`,:211-215)/ paste parts(:254)/ 从 XMP sidecar 文件加载应用(`dt_history_load_and_apply_on_list`,:159)。paste enabled = 已 copy + (多选 或 ≠源图)(copy_history.c:82-86)——与 image.c 元数据 paste 同款守卫。
- **tagging.c(4134 行,"tagging")**:左栏标签树 + attached 列表双区;**attach** = 选中 tag → `dt_act_on_get_images(FALSE, FALSE, FALSE)` 逐图 `dt_tag_set_tags(tags, imgs, ...)`(tagging.c:1182-1183);**detach** = `_detach_selected_tag` 对 act-on 集合 `dt_tag_detach_images`(tagging.c:1258-1285);attached 计数列实时刷新(`_update_attached_count`,:1104)。
- **styles.c(1063 行,"styles")**:样式列表 + **apply** = 对 `dt_act_on_get_images(TRUE, TRUE, FALSE)` 逐图 `dt_styles_apply_to_dev(name, id)`(styles.c:284-311);另有 create/edit/duplicate/delete 管理。

### 1.8 dt 解剖小结(我方对位的可移植面)

| dt 面板 | 机制要点 | 我方对位 |
|---|---|---|
| collect | 规则堆叠(10 条 AND)+ 值域层级树 + COUNT | FilterArm fold 先例 + 本案左栏树 |
| image information | 单图 40 行只读 | LibraryImageRow 28 列投影 |
| actions on selection | 两 tab 按钮网格 + act_on 统一作用集 + 置灰语义 + undo + XMP 同步 | 本案右栏(正本) |
| selection | DB 表选区 + all/none/invert/filmroll/untouched | selectedIDs 扩展 |
| copy history | copy/paste/parts/XMP-load | M2-8 Copy Adjustments 先例 |
| tagging | 树 + attach/detach 批量 + 计数 | keywords 列 + 本案标签操作 |
| styles | apply 逐图 | 挂账(headless 重放腿缺失) |

## 2. 我方现状解剖(主仓 HEAD 字节)

### 2.1 图库面布局(两栏,非三栏)

- 挂载点:`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift:592-705` `libraryFace` = **`HStack(spacing: 0)` 两栏**:`LibraryGridView`(flex) + `LibraryInspectorView`(固定 280pt,KD-2 注释「左网格 + 右 Inspector 槽位」WorkspaceHostView.swift:482-483)。
- phase 路由:WorkspaceHostView.swift:149-167,`workspace.phase` = `.library / .editor / .cull` 三态;libraryFace 在 `.library` 臂。
- 顶栏:WorkspaceTopBar(WorkspaceHostView.swift:140-147)含 yiyin sheet 入口(`onYiyin`)。
- 现有 Inspector(Alcedo AlbumInspectorPanel 同构)= **库统计/过滤面**,不是 dt image information:LIBRARY OVERVIEW 总数卡 / 四分组(日期/相机/标签/镜头,点击 fold 成 FilterArm)/ ACTIVITY 柱 / SEARCH FILTER 面包屑 / ACTIONS(Relink Missing)/ AI ANALYSIS / SMART ALBUMS(LibraryInspectorView.swift:43-69)。

### 2.2 数据模型(.lalb schema v6)

- `LightamerCore/Sources/Library/LibrarySchema.swift:132` `schemaVersion = 6`;五条迁移腿先例(v1→v2 default_look_pending / v2→v3 version_ref / v3→v4 AI 七表 / v4→v5 stacks / v5→v6 culling 七列),全部 idempotent + pre-migration `sqlite3_backup` 快照 + 单事务(`migrate(from:to:)` LibrarySchema.swift:877-904)。
- **`images` 表已有本 Case 全部所需列**(LibrarySchema.swift:171-208):
  - 八 EXIF 轻列:camera_make / camera_model / lens_model / iso / focal_length / aperture / exposure / capture_date
  - **保留列族(D-09-CONTEXT-7)**:`rating INTEGER` / `color_label INTEGER` / `keywords TEXT`(|-joined)/ `filename TEXT` / **`dir TEXT`** / `flag INTEGER`(0 none / 1 pick / 2 reject)/ `note TEXT`
  - 投影列:has_edits / params_hash / ref_count / added_time / modified_time
  - v6 分析七列:analysis_version / sharpness / faces / eyes_closed / signature / face_boxes / camera_serial
- **`albums` 表已有树形结构**(LibrarySchema.swift:215-223):`type TEXT('album'|'folder'|'filter')` + `name` + **`parent_id`(NULL=根,FK→albums.id CASCADE)**——相册/文件夹/智能相册三态一表。
- `dir`/`filename` 列导入时填充(ImportService.swift:647-648:`dir: file.deletingLastPathComponent().path`);**rating/color_label/keywords 导入不填**(NULL)——它们由 mark 写入投影。
- FTS5(images_fts external-content)+ 三触发器;`idx_images_capture(capture_date, id)` keyset 索引。

### 2.3 查询面(LibraryQueries.swift,932 行)

- `searchPage`(:224)/ `searchNullTail`(:244)双段 keyset 分页;`rows(byIDs:)`(:359);`stackMemberships`(:326)/ `stackMembers`(:382);`overviewCount`(:433);`groupCounts(by:)`(:449,四分组);`activitySeries`(:545);`currentFilterDescription`(:608);`memberIDs`(:626);`pendingAnalysisRows`(:841);`burstRows`(:888)。
- `LibraryImageRow`(LibraryQueries.swift:95-124)= 28 列冻结投影——**图片信息面板的数据源已齐**(maker/model/lens/iso/focal/aperture/exposure/captureDate/fileStem/fileExt/filename/dir/rating/colorLabel/flag/hasEdits/addedTime/modifiedTime/imagePath/pathKind/volumeUUID)。
- 排序白名单五键(FilterSortKey:captureDate/rating/filename/iso/focalLength/scanEpoch)。

### 2.4 写面(LibraryStore.swift,1306 行)

- 相册树 CRUD 全在:`createAlbum`(:116)/ `renameAlbum`(:171)/ **`moveAlbum(id:toParent:)`**(:193)/ `removeAlbum`(:227)/ `albums()`(:293)/ `members(of:)`(:355)/ `addImage(_:to:)`(:313)/ `removeImage(_:from:)`(:335)。
- `removeImage(id:)`(:409)= 从库删除单图;`insertImage(record:)`(:378);`updateProjection`(:434);**`setMetadataMarks([LibraryMetadataMark])`**(:455)= rating/colorLabel/flag 投影批写。
- stacks 族(:601-1128,group/setTop/moveInStack/splitStack/ungroup/autoStack 等)。

### 2.5 批量 mark 全链路(R1 先例,已通)

- 菜单/键盘 → `NSMenuBridge`(UI/Shell/NSMenuBridge.swift:518-544)→ `LightamerShell.applyRating/applyColor/applyFlag/toggleFlag`(LightamerShell.swift:1630-1715)→ `routeLibraryMark`(LightamerShell.swift:1643-1648,`workspace.phase == .library` 门)→ `WorkspaceModel.requestMark(MarkCommand)`(WorkspaceModel.swift:496-505)→ `MarkCommandModifier.onChange`(WorkspaceHostView.swift:978-1002)→ **`LibraryMarkApplier.apply`**(WorkspaceHostView.swift:1011-1098):
  - 作用集 = `grid.rows.filter { grid.selectedIDs.contains($0.id) }`(**walk 序多选**,WorkspaceHostView.swift:1023)——dt act_on ordered 的同构;
  - 三态命令翻译(rating/colorLabel/flag/toggleFlag 全选即清,WorkspaceHostView.swift:1061-1071);
  - 落盘 = **`LibraryMetadataWriter.apply(edits:store:seed:)`**(LightamerCore/Sources/Library/LibraryMetadataWriter.swift:108-151):逐图 sidecar 组合写(inout round-trip 保真 + pristine mint)→ `store.setMetadataMarks` 单批投影 → `grid.refreshRows(ids:)` 局部刷新(:1090)+ `inspectorModel.refresh()`(:1091)。
- **结论:右栏「评级/色标/旗标」批量操作的数据面完全现成,零新 SQL、零新写面,只缺 UI 面板。**

### 2.6 选择模型现状(LibraryGridModel.swift)

- `selectedIDs: Set<Int64>`(:115)/ `selectSingle`(:393)/ `toggleSelection`(⌘单击,:399)/ `setSelection`(:409,**零视图调用方**)/ `clearSelection`(:415)/ `openCurrent`(:421)。
- **缺口**:无 shift-range、无 select-all、无 invert、无键盘导航(网格仅 ⌘⇧I 一个快捷键,LibraryGridView.swift:367);selection 无持久化(会话态,dt 是 DB 表)。
- 选择存活语义:filter/sort 重载后 selection **存活**(KD-3 注记 LibraryGridModel.swift:16-20);stack 操作后收缩(`reloadShrinkingSelection`,:541-546)。

### 2.7 其余相关件

- **Copy Adjustments(M2-8 先例)**:`App/Sources/Lightamer/State/AdjustmentTransfer.swift:36` `isAdjustmentTransferable(_:)` 单谓词(owner==.grade + terminal trio 排除集);复制/粘贴走 editor 域 OVERWRITE-paste epoch(`VersionCoordinator` / `EditorState`)。**图库级批量粘贴调整 = 无现成写面**(LibraryMetadataWriter 只管 rating/colorLabel/flag 三元组;instances/paste epoch 批量写需要新写面)。
- **yiyin**:图库域零挂载(grep 零命中);入口在顶栏 WorkspaceTopBar 的 `onYiyin` → editor sheet。图库级批量印框 = 全新挂载点(观察项)。
- **搜索**:`LibrarySearchModel`(WorkspaceHostView.swift:112)+ `GlobalSearchDialog`(Library/Views/GlobalSearchDialog.swift)全局搜索对话框;`semanticHits` 语义搜索叠层(LibraryGridModel.swift:104)。
- **选片面(CullFace)**:第三 face(LUMEN-B T4),openCullFace(WorkspaceHostView.swift:502-529)。
- **首启**:`LibraryFirstLaunch`(App/Sources/Lightamer/Library/LibraryFirstLaunch.swift:22-62)= 默认库 `~/Library/Application Support/Lightamer/Library.lalb` 直开;走查证据 `.work/gui-acceptance/library-first-launch/`(MANIFEST 三项:冷启空态+导入门 / ⌘⇧I 面板 / 二启直进,右 Inspector 0 照片卡在位)。
- **FIX2③ 红线**:`LibraryProjectController.swift` 零 diff(连续六波亲证,AGENTS 架构速查)——本案 UI 改造不动该文件。
- **L057 红线**:面板呈现禁 `runModal`,唯一缝 `PanelPresentation.present`(LibraryPanels 已合规,LibraryProjectController.swift:586-630)。

## 3. 差距映射表(14 维)

| # | 维度 | dt 形态 | 我方现状 | 差距 |
|---|---|---|---|---|
| 1 | 布局骨架 | 左中右三栏面板(模块化可重排) | HStack 两栏(网格+统计 Inspector) | **缺左栏;右栏职责换位**(统计面→操作面,统计面可迁左栏或保留) |
| 2 | 文件树 | collect folders 属性树(GtkTreeStore 层级+COUNT) | 无(dir 列已有数据,零 UI) | **全新左栏树**(dir 层级 + albums 树) |
| 3 | 图片信息 | metadata_view 40 行单图只读 | 无独立面板(LibraryImageRow 28 列在数据面) | **全新左栏信息卡**(悬停/选中单图) |
| 4 | 右栏操作面板 | actions on selection 两 tab 按钮网格 | Inspector ACTIONS 区仅 Relink 一键 | **全新操作面板**(批量复制/应用/删除/标签/评级) |
| 5 | 多选模型 | DB 表选区 + ordered;单击/⌘/shift-range | Set<Int64> 内存;单击/⌘;无 shift-range | 补 shift-range 锚点;ordered 面(rows walk 序已同构);持久化挂账 |
| 6 | select all/invert | select.c 五按钮(collection 全量) | setSelection 无调用方;select-all/invert 无 | 补 collection 全量 walk + invert |
| 7 | 评级/色标/旗标 | ratings.c/colorlabels.c(键盘 0-5/⌘0-4) | **全通**(menu/键盘→LibraryMetadataWriter 批量) | 仅缺面板入口(键盘已在) |
| 8 | 标签 | tagging 树 attach/detach 批量 | keywords 列在(空置);零写面 | 补 LibraryStore.setKeywords 批量 + UI |
| 9 | 删除语义 | remove(库)× delete(盘,trash 偏好)双刀 | removeImage(id:) 单图;无批量 UI | 补批量 remove UI;**物理删除不做**(引用式边界);Media 孤儿挂 OQ |
| 10 | 复制调整 | copy_history(copy/paste/parts/XMP) | M2-8 编辑器域单图 copy/paste;图库级无 | **最大单项新写面**(批量 sidecar instances 写+paste epoch) |
| 11 | 预设/样式应用 | styles apply 逐图 | 编辑器域预设;图库级无 | 挂账(headless 重放腿缺失) |
| 12 | 键盘导航 | 网格 arrow/g/Home/End + 快捷键族 | 仅 ⌘⇧I | 补 arrow 导航 + ⌘A/⌘I 等选择快捷键 |
| 13 | 树点击语义 | 双击=写回规则(collection 过滤) | 无 | 左栏树点击 = fold FilterArm(dir eq/day eq)复用 FilterSQL |
| 14 | 置灰/计数语义 | act_on nb 集中 gui_update | 无集中面(逐按钮手写 disabled) | 右栏面板统一 selectedCount 驱动 |

## 4. 三栏设计案

### 4.1 容器选型

**判定:延续 `libraryFace` 的手工 `HStack(spacing: 0)` 三段式**(左 220pt + 网格 flex + 右 260pt),零框架替换。理由:

1. 现状 KD-1 缝就是 HStack 两段,加一段是纯增量(WorkspaceHostView.swift:594);NavigationSplitView 虽在 ContentView 在位(SettingsView.swift:70 / ContentView.swift:241),但 libraryFace 是其 detail 内的面——再嵌一层 NavigationSplitView 会引入列折叠/visibility 联动 churn(D-6 敏感面),收益(拖拽分隔)非 v1 必需。
2. dt 语义 = 固定宽度面板 + 可折叠;SwiftUI HStack + 固定 `.frame(width:)` 完全承载;拖拽宽度挂账(HSplitView 弱形态,或后续上 NSSplitViewController 桥)。
3. 零 ContentView / 零 LibraryProjectController 改动——FIX2③ 与剥离门风险面不触碰。

### 4.2 左栏:文件树 + 图片信息

**树数据源判定:双节树,首版以「文件夹」节为主刀。**

- **「文件夹」节** = `images.dir` 列层级展开(dt collect folders 同构):查询面新增 `folderTree()`——`SELECT DISTINCT dir FROM images` 后路径段拆分聚合成树(Swift 内存聚合,万级库微秒级;不必 SQLite 递归 CTE)。每节点计数 = `dir LIKE prefix%`(或内存计数,树构建时顺带)。**点击语义** = fold 成一条 `.dir` eq rule 的 FilterArm(FilterField 若无 dir 字段则补枚举——FilterSQL 已有列映射面),collection 过滤,FilterArm/breadcrumb 先例直续。
- **「相册」节** = `albums` 表 folder 树(`LibraryStore.albums()` + `parent_id`,面板已全 CRUD):展示用户自建相册层级;点击 = `memberIDs(albumID:)` 语义(dt 的 album 语义),点击后 collection 切相册成员集。**判定:相册成员集过滤走 `ref_count`/`album_content` JOIN,查询面补 `memberIDs` 进 searchPage 的 filter 形(或临时 filter 注入成员 id 集——万级成员 IN 列表不可靠,建议走 JOIN 臂,挂 plan 细化)。**
- **智能相册节**(SmartAlbumStore.evaluate 已在)挂第三节点,可选启用,不设新表。
- 树 UI:**d6-relevant 敏感面**——SwiftUI 大纲控件(Note: OutlineGroup / List 树形)在本仓无先例;首版用 DisclosureGroup/缩进 HStack 自绘(禁 OutlineGroup 大树 churn 面;标注 D-6 观察,验收走 GUI 走查)。

**图片信息面板 = 左栏下半区**(dt metadata_view 同构收窄版):

- 数据源 = `LibraryImageRow`(28 列已投影);展示对象 = **悬停单图优先,否则 selection 首图**(dt mouse_over 语义;我方网格可挂 hover 状态——`onHover` 面板态,d6-relevant 留意重渲染半径,建议仅记录 id)。
- 行集(v1 约 12 行):filename / 文件夹(dir)/ 拍摄时间(captureDate)/ 相机(maker+model)/ 镜头 / ISO / 光圈 / 快门 / 焦距 / 评级★ / 色标 / 旗标 / has_edits。分组小标题仿 dt(EXIF / FILE)。
- 纯只读;零新查询(`rows(byIDs:)` 已有);显示格式化建议复用 Inspector 的 DateFormatter 单例惯例(LibraryInspectorView.swift:522-527)。

### 4.3 中栏:网格(既有 LibraryGridView 为基)

- 零结构改动(adaptive LazyVGrid + keyset 分页 + stack/culling 徽章全保留)。
- 增量:①shift-range select(cell onTapGesture 带 shift → `grid.selectRange(to: row.id)`——锚点 = 上次单击行,walk 序区间);②键盘 arrow 导航(焦点面挂网格,`.onKeyPress` / hidden focusable,选中行滚动可见——LazyVGrid 滚动定位挂账,无 ScrollViewReader 到 cell 的现成缝,标注风险);③hover 上报(信息面板数据源)。
- select-all(⌘A)语义 = **collection 全量**非已加载页(dt 同款):`LibraryGridModel.collectAllIDs()`(:550-574 private)提 internal + `setSelection(Set(allIDs))`;注意 setSelection 现有实现会**过滤掉未加载行**(:410-413 `filter { rows.contains }`)——**select-all 路径需绕开该过滤**(加 `setSelectionIncludingUnloaded` 或放宽该谓词,plan 细化)。

### 4.4 右栏:操作面板(dt actions on selection 同构)

**面板骨架**(新 `LibraryActionsPanelView` + `LibraryActionsPanelModel`,固定 260pt 右栏,与左栏对称):

- 头部:选中计数卡(N 张选中;0 张 = 全面板 disabled——dt gui_update 的 nbimgs 语义,机检 AX 断言缝)。
- **操作清单(逐项数据依赖与可复用件)**:

| 操作 | 语义 | 数据依赖 | 现有可复用件 | v1? |
|---|---|---|---|---|
| 评级 0-5 ★ | 全选集置值 | images.rating | **LibraryMarkApplier + LibraryMetadataWriter 全通**(R1) | ✅ 仅 UI |
| 色标 0-5 | 全选集置值 | images.color_label | 同上 | ✅ 仅 UI |
| 旗标 pick/reject/clear | 全选集置值 | images.flag | 同上(toggleFlag 全带即清语义在位) | ✅ 仅 UI |
| 批量标签 attach/detach | keywords 列合并/移除(|-split) | images.keywords + sidecar? | 无写面——**新 `setKeywords` 批量**(LibraryStore);sidecar 无 keywords 座位(写库即真,sidecar 只投影三 mark——见 §5) | ✅ 小写面 |
| 移出图库(remove) | 删行 + CASCADE(相册/堆栈/版本引用) | images + FK CASCADE | **`LibraryStore.removeImage(id:)`(:409)已有**,循环多选即可;物理文件不动 | ✅ 仅 UI(确认 sheet) |
| 复制调整(copy) | 记源单图 instances | .lra sidecar | M2-8 `isAdjustmentTransferable` 谓词 + 读面 | ✅ 单图 copy |
| 粘贴调整(paste) | 源 instances 批写 N 图 | .lra sidecar × N + paste epoch | **无批量写面**——新 `LibraryAdjustmentWriter`(LibraryMetadataWriter 同构:逐图 sidecar inout + instances 替换 + pasteEpochScope 重放 + params_hash 投影批写) | ⚠️ 最大单项 |
| 应用预设/样式 | 预设批写 | headless 重放腿 | 无 | ❌ 挂账 v2 |
| 全选/反选/清选 | selection 面 | collection 全量 walk | collectAllIDs + setSelection(见 4.3) | ✅ 仅 UI |
| 移入相册/堆栈 group | 已有 | album_content / stacks | LibraryStore 全套(:313/:650) | ✅ 仅 UI |

- **粘贴调整语义判定**:复用 M2-8 OVERWRITE-paste epoch(粘贴 = 新 epoch 整链替换,非 merge——M2-8 DECISIONS 单语义);源图 = copy 时记录的单图(多选 copy 禁用,dt 同款);粘贴后 per-image `refreshRows` + 网格徽章(has_edits 变化)自动活。
- **删除确认**:sheet 确认(显示 N 与不可逆语义;L057 缝——sheet 非 runModal);物理 delete 不入 v1。
- **undo**:我方图库域无 undo 栈(M2-8 KD-3 no-undo posture);右栏操作 v1 同 posture,undo 挂账。

### 4.5 selection 模型设计(增量而非重写)

- 保持 `selectedIDs: Set<Int64>` + rows walk 序(LibraryMarkApplier :1023 已按 walk 序取——ordered 面已同构 dt);**新增** `selectionAnchor: Int64?`(shift 起点)+ `selectRange(to:)`(walk 序闭区间替换语义:Lr 惯例 shift=区间重置,⌘shift=区间并集——v1 取 Lr 重置语义,plan 细化)。
- `selectAll()` = collectAllIDs 全量;`invertSelection()` = 全量 − selectedIDs。
- 选区持久化(跨会话,dt selected_images 表形态)**不做**——.lalb 无选区表,v1 会话态;若后续需要属 additive v7 议题(单表 selected_images 同构),挂 Open Question。

## 5. 数据面缺口

- **判定:.lalb schema 不 bump(v6 保持)。** 理由:①rating/color_label/flag/keywords/dir/filename 全部列已在(D-09-CONTEXT-7 保留列族,本 Case 就是它们的消费兑现);②albums 树已在;③右栏所有 v1 操作皆可落现有列;④粘贴调整走 sidecar 真身(.lra),.lalb 只刷 has_edits/params_hash 投影(现有列)。五条迁移腿先例虽齐,但零新列零新表 = 零迁移风险,最优。
- **标签存储判定:keywords 列(|-joined)承接,不建标签表。** dt 有 tags 树 + tagged_images 多对多表,但其树/计数/搜索面我方 v1 不做层级标签;keywords 拆分搜索已进 exif_search_text 折叠面(ExifFold)。层级标签树(左栏 tag 节点树)若立项再议 additive bump(单表 tags + tagged_images,无列变更)。副作用:关键词含 `|` 字符需转义/禁入(plan 细化:输入 sanitize)。
- **与 lumen-culling 批(v6 分析七列)关系**:零冲突——分析列 read-only 消费(徽章),右栏操作不写它们;批量 remove 的 FK CASCADE 会连带删除 analysis 数据(在 images 行内,无独立表)。
- **sidecar 契约**:批量标签只写 .lalb keywords 列(sidecar 无 keywords 座位,不引入新 sidecar 字段=sidecar schema v11 不动;与「.lra = 编辑态真相」边界一致——标签是组织元数据非编辑态)。批量粘贴调整写 sidecar(instances)——真身域正确。

## 6. 风险清单

1. **FIX2③(LibraryProjectController 零 diff)**:本案全部改动落在 WorkspaceHostView / Library 域视图与 Core 查询/写面,零 controller 触碰;验收批加零 diff 机检。
2. **D-6 型 SwiftUI 树形控件风险(d6-relevant)**:左栏树 + 右栏面板属「可见性门控 churn」敏感族;处置 = 自绘缩进树(OutlineGroup/NSOutlineView 桥不上 v1)、面板固定挂载不条件卸载(disable-not-unmount 纪律)、树节点折叠态会话态零持久化(零 UserDefaults 新键——M9-4 先例同款);GUI 走查列入验收。
3. **剥离门(LibraryLegacyGate)**:三栏面只在默认图库工作区(phase == .library);legacy 回切面(Sessions/Catalogs 双区)不渲染新栏——挂载点在 WorkspaceHostView.libraryFace 内部,回切路径天然不见新面;验收含 LIGHTAMER_LEGACY_LIBRARY=1 回切走查。
4. **select-all 全量 Set 内存面**:50k 库 = 50k Int64 Set ≈ 1MB 量级,可接受;但 setSelection 过滤未加载行的现状谓词(:410-413)与全量语义冲突,直改会动既有调用方语义——必须走新增方法,不改 setSelection 本体。
5. **批量粘贴调整的 sidecar 风暴**:N 图逐 sidecar 写(pretty+sortedKeys JSON + tmp+replace)+ journal;N 大时须走 BackgroundTaskRegistry 任务面(ImportProgressCoalescer 形态先例)+ 分批;LibraryMetadataWriter.apply 无进度回调——新写面照抄该形态时一并补进度缝。
6. **hover→左栏信息面板的重渲染半径**:onHover 逐 cell 触发会导致 grid body 重评估(D-6 已定罪的同型 churn);处置 = hover 状态不落 LibraryGridModel(独立 @State 承载 + 面板侧 debounce),或 v1 降级为「选中首图」无 hover(dt mouse_over 语义让位)。推荐降级(Open Question OQ-4)。
7. **键盘导航焦点与 ScrollViewReader 定位**:LazyVGrid 无 cell 级 anchor 缝,arrow 导航到视口外行的滚动定位要自定义(offset 估算),有 D-6 风险;v1 可先 arrow 导航不改滚动(可见行内导航),视口外定位挂账。
8. **keywords `|` 注入**:批量标签输入含 `|` 会破坏 |-joined 语义——输入 sanitize 硬拒绝(plan 细化)。
9. **Film/ 域在飞执行 lane**:主仓 Film/ 域有执行 lane 在飞;本案零交集,验收批跑域 bundle 时避开 Film 域。

## 7. Open Questions(≤6,带推荐)

- **OQ-1 左栏树首版范围**:仅「文件夹」节(v1)还是文件夹+相册双节同批?
  推荐:双节同批(相册树 CRUD 与成员过滤全是现成件,增量小);智能相册第三节点挂账。
- **OQ-2 批量粘贴调整是否入 v1**:右栏最大单项(新 LibraryAdjustmentWriter + 进度缝 + 任务面)。
  推荐:入 v1 但独立 plan(右栏其余操作先行交付,粘贴调整单独一波验收;dt 同位模块 copy_history 本就独立面板)。
- **OQ-3 批量 remove 后 Media/ 孤儿文件策略**:remove 只删行,Media/ 内物理文件留存(引用式边界)。
  推荐:留存 + 右栏操作面板不提供物理删除;「清理未引用文件」工具挂账(dt delete 的 trash 偏好形态留 v2 议题)。
- **OQ-4 图片信息面板展示对象**:悬停优先(dt mouse_over)还是选中首图?
  推荐:v1 选中首图(selection 变化驱动,零 hover churn);hover 升级挂 D-6 观察面。
- **OQ-5 现有右栏统计 Inspector 去向**:右栏换操作面板后,统计面(四分组/Activity/智能相册)迁左栏下部还是保留第三态切换?
  推荐:统计面迁左栏下半(信息卡之下可折叠区),右栏专职操作——dt 语义即「左浏览辅助 + 右操作」;智能相册随统计面迁左栏。
- **OQ-6 selection 是否需要 shift 之外的 rubber-band 框选**:网格空白拖拽框选(Lr/Photos 有)。
  推荐:v1 不做(LazyVGrid 无现成 overlay 框选缝,自绘成本高 + D-6 风险);⌘A/shift-range/⌘单击覆盖主场景,rubber-band 挂账。

## 8. 验收清单对照

- [x] dt 侧两模块 + actions on selection 全 file:line 可核(含 selection 模型)——§1.2-1.6
- [x] 我方侧 LibraryGridView / LibraryStore / LibraryQueries 现状精确 file:line——§2
- [x] 设计案三判定:schema 不 bump(§5)/ 批量删除 = 引用式 remove(§4.4)/ 树数据源 = dir 层级 + albums 双节(§4.2)
- [x] 右栏操作清单逐项数据依赖与可复用件——§4.4 表
- [x] Open Questions ≤6 带推荐——§7
- [x] 全程只读零 commit;本文件 chunked 追加写入(每段 ≤8KB)
