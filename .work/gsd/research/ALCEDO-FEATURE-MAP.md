# Alcedo Studio 功能/规格测绘（Feature Map）

> **生成日期**: 2026-09-27
> **来源仓库**: `/Volumes/UNITEK/Documents/Development/AlcedoStudio`，HEAD commit `34241d0bd3f3183da78d39d5c1bd6c9e7a53cbeb`（2026-09-27，"Merge pull request #210 … adjustment-transfer-audit"）
> **目的**: Lightamer 重定义为「macOS 独占 + Core Image RAW 9 解码 + UI 完全模仿 Alcedo Studio」的产品对标研究。只做功能/交互层面测绘，不复制 GPL 代码。
> **技术底座（背景）**: C++20 + Qt6/QML（QuickQanava 节点图），GPU 管线 Windows = CUDA/OpenCL、macOS = Metal；RAW 解码 = 自维护 LibRaw fork；图库 = DuckDB；AI 侧车 = Rust gRPC 服务 `rust/puerh_mind`（tonic + ort/CoreML）。GPL-3.0-only。支持 Win10/11 x64 与 macOS 13.3+ Apple Silicon（`README.md:19,114-115`）。

---

## 1. UI 结构总览（UI Structure）

### 1.1 顶层骨架
- 双工作区路由：`LibraryWorkspace.qml`（图库）/ `EditorWorkspace.qml`（编辑器），宿主 `WorkspaceHost.qml` + `Main.qml`，顶栏 `TopToolbar.qml`，自绘无边框窗口（`macos_frameless_window.mm` / `windows_frameless_window.cpp`，0.2.9 起用系统原生窗口框）。
- 主题 tokens：`app_theme.cpp` + `DESIGN.md`（暗色玻璃卡片家族，colCardSurface/colCardBorder 等）。

### 1.2 图库（Library）
源：`LibraryWorkspace.qml`、`ThumbnailGridView.qml`、`CollectionsPanel.qml`、`AlbumInspectorPanel.qml`。
- **网格**：`ThumbnailGridView.qml`（缩略图与编辑器共用同一 GPU 渲染引擎，0.3.0 changelog「Performance」节）。
- **Album Inspector（右侧检查器）**：`AlbumInspectorPanel.qml`
  - `LIBRARY OVERVIEW`（Total Photos 总数卡）
  - 分组：`By Capture Date` / `By Camera Model` / `By Labels` / `By Lens`；0.3.0 新增 **Activity view**（按拍摄日期的照片数量图，点某天过滤相册）
  - `SEARCH FILTER` 区显示当前搜索过滤态；点击分组即筛选（README「Library and search」节）。
- **搜索**：`GlobalSearchDialog.qml`——三种搜索合一：EXIF 检索（相机/镜头/日期/ISO/焦距/光圈，支持 `iso800`、`f/2.8`、`35mm`、日期多格式、文件类型词，AND 组合）、CLIP 自然语言、AI 描述/标签全文（README:85-89；`search_query_classifier.hpp`）。
- **导入**：`FolderImportConfirmDialog.qml` + `ImportProgressOverlay.qml`/`ImportProgressRing.qml`；0.3.0 起只收相机 RAW（拒绝 JPEG/TIFF/PNG/HEIC）。用户先把照片拷到本地盘再导入文件夹（README:17），库内记录原路径 `Image.image_path`——引用式而非库内托管拷贝。
- **项目**：`WelcomeDialog.qml`（Load/Create Project，`.alcd` 文件）；`ProjectLaunchController.qml`、`ProjectLoadingOverlay.qml`。

### 1.3 编辑器（Editor）
源：`EditorWorkspace.qml`（布局注释「Desktop order (non-negotiable): tool rail left, viewport center, scopes + adjustment stack right」，`EditorWorkspace.qml:89`）。
- **左：工具轨** `EditorWorkspaceRail.qml`——图标列（History / Versions / Nodes 三个 `EditorRailButton`，0.3.0 起图标下带文字标签），点击展开对应面板（`EditorHistoryTransactionsPanel` / `EditorVersionsPanel` / `EditorNodesPanel`），面板展开推挤中央视口（共享折叠动画）。
- **中：视口 + 胶片条**
  - `EditorViewportItem`（QQuickRhiItem 直渲面）+ `EditorOverlayItem`（蒙版/裁剪 overlay）+ `EditorInteractionController`（缩放/平移/裁剪态）；
  - 状态件：`FIT`/百分比缩放读出（`EditorWorkspace.qml:331-347`）、裁剪角度徽标、两级 BusyIndicator（准备中/调整渲染中）；
  - 交互：左键=蒙版绘制或单击缩放切换、中键/拖拽=平移、滚轮=缩放、双击切换 FIT、PinchHandler 触控板缩放；**2.5K@60fps 预览拖动、松手升 4K、放大只渲可见区**（README:48）；
  - 底部 `EditorFilmstrip.qml`（与图库同集合/过滤结果，`EditorFilmstripThumbnailCard.qml`）。
- **右：示波器 + 调整栈**
  - `EditorScopePanel.qml`：直方图 / 波形二选一（「Show histogram」「Show waveform」）；
  - `EditorAdjustmentStack.qml`：右侧面板导航，7 个页签——**Tone / Look / LUT / Display Transform / Geometry / RAW Decode / Mask**（`EditorAdjustmentStack.qml:10-16`），选中节点后面板编辑该节点，头部 `EditorAdjustmentHeader.qml` 显示节点名+焦距/光圈/快门/ISO（0.3.0）。
- **节点编辑器视图**：`EditorNodesPanel.qml` + QuickQanava 画布（`EditorNodeDelegate` / `EditorEndpointNodeDelegate`（Develop/DRT 端点）/ `EditorNodeEdgeDelegate` / `EditorNodePortDock` / `EditorNodePortDelegate`）。操作：Add / Rename / Delete / Connect Color Grade、Fit 视图、连接态提示；节点在图上可视化串接 Develop→Grades→DRT。
- **蒙版编辑**：图上直接绘制（radial/gradient 手柄 overlay），`EditorMaskGroupsPanel.qml`——每个 Color Grade 显示为一个「Mask Group」（组内蒙版缩略图，`mask_thumbnail_coordinator.cpp`），可增删组、拖组排序、锁删除（首个 grade 默认锁）；`EditorMasksContextPanel.qml` 上下文面板；`LockedNodeMaskPromptDialog.qml` 锁定提示。Settings「Default Behavior」页可选画蒙版行为：`Ask every time` / `Create a new layer, then draw` / `Draw on the current node`（`SettingDialog.qml`）。
- **历史/版本**：`EditorHistoryTransactionsPanel`（undo/redo 按钮，每行=一次真实编辑事务：操作名+参数 delta+时间，`docs/editor_versioning_ui_handoff.md` 交互规则）；`EditorVersionsPanel`（命名版本列表、Branch from current commit、Fork new version from root、Paste adjustments as a new Version、Rename/Remove）；`EditorHistoryCommitGraphNode` + `DateCommitGraph`（commit 图可视化）；`EditorSaveRecoveryBar.qml`（崩溃恢复条）。
- **Look 复制**：`AdjustmentTransferDialog.qml` 三层面板（Node/Item/Version pane）——选源 Version，按节点/条目勾选要复制的调整，Paste 生成新 Version（0.3.0「Copy Adjustments」）。
- **其它**：`BackgroundTasksDialog`/`BackgroundTaskBar`（AI 任务后台）、`SemanticGenerationDialog`（导入后「Use AI to analyze image content?」+ Remember My Choice + 后台/跳过）、`SettingDialog.qml` 设置、`AiProviderSettingsPanel.qml`、`CacheSettingsPanel.qml`、`UpdatesSettingsPanel.qml`、`KeyboardSettingsPanel.qml`（快捷键逐项自定义+冲突显示+恢复默认，0.3.0）、`AboutPage.qml`、`NikonHeRecoveryDialog.qml`（Nikon HE NEF 恢复）、`AcceleratorPreparationOverlay.qml`。

### 1.4 设置页（SettingDialog.qml）
`Language / Theme`、`Default Behavior`（含蒙版绘制行为）、`Cache`、`Local Content Recognition`（本地 CLIP/SigLIP 模型选择，页内说明文案列出 4 个模型及定位，见 §8）、`Advanced Content Analysis`（AI provider，说明灵感来自 ccswitch）、`Acceleration`、`Updates`（0.2.9 起签名自动更新+专用页）、`Keyboard`、`About`。

---

## 2. 调整控件清单（Adjustment Controls）

### 2.1 Adjustment 目录（内置 18 种）
注册表：`alcedo_studio/src/edit/operators/models/adjustment_catalog.cpp:33-52`；类型 id：`src/include/edit/operators/models/builtin_type_ids.hpp:11-82`。归属：13 种 Color Grade 拥有，4 种 DRT/Post 拥有（Clarity/Sharpen/Halation/FilmGrain），`Tint` 为目录内标量。所有权校验见 `color_grade_node_model.hpp:29-34`（Grade 内插入 DRT 拥有项会抛异常）。

| 目录名（display_name） | type_id 尾段 | 载体 | 参数 / 默认 / 范围（JSON key） |
|---|---|---|---|
| CAT02 White Balance | cat02_white_balance | Grade | temperature 默认 5999.9934 K（=AP1 白点 identity），2000–15000 K；tint 默认 9.7112783，±150（`cat02_white_balance_model.hpp:18-23`） |
| Exposure | exposure | Grade | `exposure_ev` 0 EV，±16 EV（模型）；UI slider −10…+10 step 0.01（`EditorTonePanel.qml:126-139`） |
| Contrast | contrast | Grade | `contrast` 0，±100；0.3.0 起语义=中灰邻域 lightness（保色相、不动中灰），新图默认 +15 |
| White | white | Grade | `white` 0，±100 |
| Black | black | Grade | `black` 0，±100 |
| Shadows | shadows | Grade | `shadows` 0，±100（局部色调映射实现，README:77） |
| Highlights | highlights | Grade | `highlights` 0，±100（同上） |
| Curve | curve | Grade | 单位方形控制点，identity (0,0)-(1,1)（`curve_model.hpp:24-26`）；UI 300px 曲线编辑器，左键拖/右键删点/双击重置 |
| HLS | hls | Grade | 8 色相 bin（0°…315°）、`hls_adj_table`[H,L,S]、`h_range_table` 默认 45°、target_hls {0,0.5,1}、h/l/s_range=45/0.1/0.1（`hls_model.hpp:16-39`） |
| Saturation | saturation | Grade | 默认 1.0，0…4 |
| Vibrance | vibrance | Grade | 0，±100 |
| Color Wheel | color_wheel | Grade | Lift/Gamma/Gain 三轮（见 2.2） |
| LMT | lmt | Grade | `cube_path`（CUBE LUT 文件路径，空=identity，`lmt_model.hpp`） |
| Tint | tint | Grade | 0，±100 |
| Clarity | clarity | **DRT/Post** | 0，±100 |
| Sharpen | sharpen | **DRT/Post** | amount 0 / radius 默认 3 / threshold 0（`sharpen_model.hpp:15-19`） |
| Halation | halation | **DRT/Post** | strength 0…1（UI 0…100） |
| Film Grain | film_grain | **DRT/Post** | strength 0…1（IPOL 2017 物理模型） |

**产品默认 look**（非 identity）：+1.5 EV、contrast +15、saturation 1.3，由 `CreateDefaultPipelineDocument` 施加（`color_grade_node_model.hpp:56-65`）；用户新建 grade 与 reset 均为 identity（`EditorTonePanel.qml:133-135`）。

### 2.2 Color Wheel（Lift/Gamma/Gain 色轮）
`color_wheel_model.hpp:34-50`：每轮 `ColorWheelControl { disc: Vec2, strength: float, color_offset: Vec3, luminance_offset: float }`；lift identity=全零，gamma/gain identity=色偏 (1,1,1)。UI 在 **Look 面板**「Color Wheels」组：Lift/Gamma/Gain 三个 trackball（`editor_cdl_trackball_item.cpp`），带「Reset wheels」。调色工作空间 = ACEScc（README:58-63 管线图「Grading in ACEScc」）。

### 2.3 Look 面板分组（EditorLookPanel.qml）
`Master`（Saturation/Vibrance）→ `Look`（Clarity/Sharpen/Film Grain/Halation 联动 DRT 项）→ `Color`：`White Balance`（=CAT02，页内提示说明它是 AP1 假设下的创意色温，相机 WB 在 RAW Decode 页）、`Selective Color`（Target Hue %1°、Hue Shift / Lightness / Chroma / Hue Smoothness = HLS 模型的 UI 面）、`Color Wheels`（LGG）→ `Detail` / `Texture`（Clarity/Sharpen 等）。

### 2.4 Develop 节点（RAW Decode 面板）
`develop_node_model.hpp`（DevelopPayload）：
- `demosaic_method`：`default`（Bayer=RCD，X-Trans=Neural Engine）/ `legacy` / `neural_engine`（`EditorRawDecodePanel.qml` entries；README:44）；
- `highlights_reconstruct` 默认 **true**（inpaint-opposed 改良版，源自 darktable/RawTherapee）；
- 相机白平衡：`custom_cct` 默认 6500 / `custom_tint` 默认 0 / `as_shot_cct` / `as_shot_tint` / `user_wb`；
- `camera_profile`（cam_mul 相机矩阵，含 rawtoaces-data 来源）；
- Lens Calibration：`lens_enabled` 默认 false / `user_scale` / `projection_enabled`（Lensfun；镜头目录搜索 + 自动识别，0.3.0 移入 RAW Decode 面板）。
- DNG 内嵌色彩 profile（HueSatMap/LookTable）0.3.0 起正确使用。

### 2.5 Geometry 面板（EditorGeometryPanel.qml）
Crop X / Crop Y（0…1）、Crop Width / Crop Height（0.0001…1，默认 1）、Rotation（±180°，图上 rotate 手柄+角度徽标）、Aspect Ratio W/H（+预设长宽比）。注明「Geometry applies to the whole image」（不参与节点/蒙版）。

### 2.6 Detail 面板（EditorDetailPanel.qml，即 DRT/Post 四件套 UI）
Clarity ±100、Sharpen 0…100、Film Grain 0…100、Halation 0…100；0.3.0 起此四项**在 display transform 之后对全图应用一次**（预览与成品一致）。

---

## 3. 节点图模型（Node Graph Model）

- **语义**：`PipelineDocument` = Develop → Color Grade×N → DRT（Display Transform）。Develop 把 RAW 变成 scene-referred 线性图；任意多个 Grade 串联；DRT 是显示参考终点（单 scene 输入端口，显示输出不是 scene 图端口，`drt_node_model.hpp:182-187`）。
- **NodeId 约定**：默认文档 `grade.primary`（首个 Grade，display_name "Color Grade"）与 `drt`；DRT 内四调整 instance id 为 `drt.clarity` / `drt.sharpen` / `drt.halation` / `drt.film_grain`（`drt_node_model.hpp:203-207`）。
- **串接规则**（`pipeline_graph_commands.hpp`）：`AddCleanColorGrade(before_node_id)` 在指定位置插入 identity grade（13 种目录项）；`RemoveColorGradeAndBridge` 删除并桥接前后边；`ReconnectColorGrade` 改挂接点；`RenameColorGrade`；`SetColorGradeEnabled`；`SetColorGradeMix(mix)`；`InsertColorGradeFromJson`（undo/redo 复原用，保 NodeId）。图校验 `graph_validation.hpp` 拒绝旧式 AnalyticMaskNode/RasterMaskNode 文档（`builtin_type_ids.hpp:96-105`）。
- **节点内**：有序 adjustment 列表（顺序=用户数据，GraphCompiler 不得重排，`color_grade_node_model.hpp:30-33`）+ `enabled` + `mix`(0…1，节点整体强度) + `deletion_protected`（首个 grade 默认锁删）+ masks 列表。
- **蒙版绑定**：蒙版属于 Grade 节点（Grade-owned），不是独立节点；每 mask 独立 enabled/opacity/invert，显示序≠像素序（`color_grade_node_model.hpp:130-137`）。
- **与 Capture One adjustment layers 的概念映射**：

| Capture One 概念 | Alcedo 对应物 | 承载 UI |
|---|---|---|
| adjustment layer | 一个 Color Grade 节点 | Nodes 图节点 + Mask Groups 组 |
| layers 列表（叠序） | Mask Groups 面板的组序（拖动改 grade 顺序） | `EditorMaskGroupsPanel.qml` |
| layer mask | 该 Grade 的 masks（radial/gradient/brush） | 图上绘制 + `EditorNodeMaskDrawer` |
| layer opacity | Grade `mix`（节点整体 0…1）；mask 级另有 `opacity` | 节点/mask 属性 |
| Base 层（锁定） | `grade.primary` 默认 deletion-protected | Mask Groups 首组 |
| 「新建空层再画」 | Default Behavior 设置 newLayer/currentNode/ask | Settings |

---

## 4. 蒙版体系（Mask System）

- **类型**（`mask_model.hpp:28-34`）：`Radial`、`LinearGradient`、`Brush`（`ALCEDO_ENABLE_BRUSH_MASK` 编译开关，CMake 注明「not part of the shipped product」——**出货版只有径向+线性渐变**；画笔的完整数据模型/笔划/编码已就绪：`brush_stroke.cpp`、`brush_signed_distance.cpp` 等 9 个文件）。**无亮度/参数化蒙版**——`ColorRangeModel` / `LuminanceRangeModel` 当前只允许 `enabled=false` 占位（`mask_model.hpp:100-120`）。
- **参数**：
  - Radial：center 0.5/0.5、major/minor_radius 0.5、rotation 0、inner/outer_feather 0（归一化参考空间）；
  - Linear Gradient：origin 0.5/0.5、normal (0,1)、transition_distance 0.2、start_value 1 → end_value 0；
  - Mask 级：`display_name` / `enabled` / `opacity` 1.0 / `invert` false / `deletion_protected`；应用次序 = 源 feather → invert → opacity → clamp（`mask_model.hpp:188-199`）。
- **编辑交互**（0.3.0）：图上直接画、手柄拖调（overlay 手柄/导引线 token 化）；Mask Groups 面板按 Grade 分组、蒙版缩略图（GPU 缩略图管线）、可加删蒙版、锁删除；未完成节点会提示「Locate unfinished node %1 in Nodes」。
- **与节点关系**：每 Grade 多蒙版、互相独立；蒙版内容修订走单调 revision（`MaskContentRevision`），画笔笔划追加按乐观并发校验 revision。

---

## 5. 显示渲染变换 DRT（Display Rendering Transform）

> **勘误注记（M2-6-3 T6，2026-10-01）**：本节「45 个 detailed 参数」系少计——
> `OpenDrtDetailedParams` 实数 **53**（tn×9 + cwp_lm + rs×3 + pt_lml×4 + pt_lmh×3 +
> ptl×3 + ptm×6 + brl×6 + brlp×4 + hc×2 + hs×12；`drt_node_model.hpp:45-99` 逐字段
> 清点，M2-6-CONTEXT 事实基线②）。schema 按实际枚举落（`DrtRecord.swift`），本注记
> 为文档勘误——**REQUIREMENTS 原文不改**。

面板 `EditorDisplayTransformPanel.qml`；模型 `drt_node_model.hpp`。默认 **OpenDRT**（`drt_node_model.hpp:102`，面板 defaultIndex 1）。

- **Method**：`ACES 2.0` / `OpenDRT`（分段卡切换，Method 恒展开）。
- **Color & Encoding**（折叠组默认展开）：
  - `Encoding Space`：Rec.709 / P3-D65 / P3-D60 / P3-DCI / XYZ / Rec.2020；
  - `Encoding EOTF`（随空间联动）：Rec.709→BT.1886/Gamma 2.2；P3-D65→Gamma 2.2/ST 2084(PQ)；P3-D60/DCI/XYZ→Gamma 2.6；Rec.2020→ST 2084/HLG（模型层还有 Linear/Gamma 1.8，`drt_node_model.hpp:35-43`）；
  - `Peak Luminance`：100…1000 nits，默认 100（slider）。
- **ACES 2.0 专属**：`Limiting Space`：Rec.709 / Rec.2020 / P3-D65 / P3-D60 / P3-DCI / ProPhoto RGB / Adobe RGB。
- **OpenDRT 专属（预设三件套）**：
  - `Look`：standard / arriba / sylvan / colorful / aery / dystopic / umbra / custom；
  - `Tonescale`：use_look_preset + low/medium/high_contrast + 各 look 的 *_tonescale + aces_1_x / aces_2_0 + marvelous_tonscape / dagrinchi_tonegroan + custom（共 15 项）；
  - `Creative White`：use_look_preset / D93 / D75 / D65 / D60 / D55 / D50。
  - 模型层另有 **45 个 detailed 参数**（`OpenDrtDetailedParams`，`drt_node_model.hpp:45-99`：tn_con 1.66 / tn_sh 0.5 / tn_toe 0.003 / tn_off 0.005 / tn_hcon* / tn_lcon* / cwp_lm 0.25 / rs_sa 0.35 / rs_rw 0.25 / rs_bw 0.55 / pt_lml* / pt_lmh* / ptl_cmy / ptm_low* / ptm_high* / brl* / brlp* / hc_r / hs_*…）作为「editor-owned 参数组」整体序列化——预设是这组参数的具名快照，UI 面板只暴露预设三件套。
  - 其它载荷字段：`creative_white_limit` 0.25、`display_grey_luminance` 10、`hdr_grey_boost` 0.13、`hdr_purity` 0.5（`drt_node_model.hpp:107-113`）。
- **HDR**：EOTF ∈ {ST2084, HLG} 即判定 HDR 输出编码（`IsHdrExportEncoding`，驱动图库 HDR 标志与导出）；macOS HDR 显示屏直接在编辑器预览 HDR（README:63）。ACES 2.0 的 HDR 峰值亮度路径在 v0.2.3 时段是已知损坏项（`KNOWN_ISSUES.md` v0.2.3 节）。
- **实现来源**：OpenDRT 移植自 jedypod/open-display-transform（参考 dctl 存 `src/config/DRTs/OpenDRT.dctl`）；ACES 2.0 ODT 按 aces-aswf/aces-core 实现（README:131-132）。DRT 前有 ACES reference gamut compression（`aces_reference_gamut_compression.h`）。

---

## 6. 图库 / 项目模型（Library & Project Model）

### 6.1 项目文件
- `.alcd` 项目；工作区 = `<stem>.db`（DuckDB）+ `<stem>.json`（`project_package_backend.cpp:269-382`）。相册结构与每张照片完整编辑历史都在这一个项目文件里，可当普通文件移动/备份（README:17）。项目 schema 版本记录于 `ImageEditState.project_schema_version`；**0.3.0 不能打开 0.2.9 及更早项目**（changelog 升级须知）。

### 6.2 DuckDB 表（`src/include/storage/store/database.hpp` DDL）
- **相册骨架**：`Sleeve(id)`、`SleeveRoot(id)`、`Element(id, type, element_name, added_time, modified_time, ref_count)`、`FolderContent(folder_id, element_id)`、`FileImage(file_id, image_id)`、`ComboFolder`、`Filter(combo_id, type, data JSON)`（智能/过滤相册）。
- **照片**：`Image(id, image_path, file_name, type, metadata JSON, …)` + **物化搜索列**（`image_search_columns.hpp`）：`file_stem`、`file_ext`、`capture_at`、`capture_date`、`camera_make`、`camera_model`、`lens`、`iso`、`focal_mm`、`aperture`、`rating`、`exif_search_text`、`exif_search_words`（词边界折叠检索，~20ms@2 万张）。
- **编辑管线**：`PipelineParam(file_id PK, param_json JSON)`（活动参数表）、`PipelineRoot(root_id, element_id UNIQUE, serialized_pipeline_state JSON)`。
- **Mini-Git 历史**：`EditCommit(commit_hash PK, root_id, first_parent_hash, second_parent_hash, created_at_ns, kind, edit_payload JSON)`（不可变 commit 图，双亲=分支/合并）；`VersionRef(version_id PK, element_id, display_name, head_commit_hash, created_at_unix, updated_at_unix)`；`ImageEditState(element_id PK, root_id, active_version_id, materialized_head_commit_hash, materialized_transaction_chain_hash, serialized_pipeline_state JSON, project_schema_version)`（材质化缓存，仅加速恢复、非用户概念）。
- **语义检索**：`SemanticModel`（model_key/model_id/revision/embedding_dim/image_size/engine_id/profile_id/supported_text_languages_json/prompt_config_hash/asset_manifest_json/active）、`SemanticImageEmbedding(embedding FLOAT[512])` 与 `…768`、`SemanticImageLabel(file_id, model_key, label, score, second_label, second_score, margin, confident, top_scores JSON)`、`SemanticLabelQuery(prompt_config_hash, label, query_text)`（出厂预置中英文标签 query，`DefaultSemanticPhotographyLabelQueries`）、`SemanticLabelPrototype(…embedding FLOAT[512])`（标签原型嵌入，余弦自动打标）。
- **AI 注记**：`AiImageUnderstanding(file_id, task_id, provider_id, model_id, prompt_profile_id, rendition_kind, caption, tags_json, scene, confidence, active, caption_search_text, tags_search_text, …)`、`AiImageFtsDocument(file_id PK, body)`（全文）、`AiImageSearchText`、`AiImageRating(file_id, task_id, provider_id, model_id, prompt_profile_id, rendition_kind, …)`。

### 6.3 版本与历史（`docs/editor_versioning_ui_handoff.md`）
- 两个概念分立：**编辑历史**=当前版本内线性时间线（每行=一次真实编辑事务）；**版本**=同图独立完整 look（「暖调」「黑白」…），**从导入原始态新建**（不是从当前版本分叉，但 commit 图层支持 branch from current commit 与 fork from root 两种入口，`EditorVersionsPanel.qml`）。
- 交互规则（原文档「Confirmed interaction rules」）：跳回早期编辑后 redo 尾巴保留；跳回后再编辑则丢弃未来尾巴；切版本即时；版本自动保存（无显式 save）；版本可改名；跨图版本复制刻意延后。
- 每次调整记入 Git-like 历史、**可永远 undo**；undo/redo 按钮在历史面板头部。
- **Look 复制**（0.3.0「Copy Adjustments」）：选源 Version → 对每个 Color Grade 与 Display Transform 勾选要复制的条目 → Paste 生成**新 Version**；不复制 RAW decode / lens / crop-rotation。实现：`AdjustmentTransferDialog.qml` + `adjustment_transfer_*` 控制器（Node pane → Item pane → Version pane）。

### 6.4 导入
用户自拷照片到本地盘 → 导入文件夹；库记录原路径（引用式）。删除磁盘文件后**无法 relink**，调整丢失（KNOWN_ISSUES v0.2.3「Assets Management」）。0.3.0 只接受相机 RAW 扩展名：`.3fr/.arw/.cr2/.cr3/.dng/.fff/.nef/.raf/.raw/.rw2`（`docs/supported_raw_formats.md`）。

---

## 7. 导出面（Export）

模型：`src/include/io/image/export_recipe.hpp`（0.2.9 起完整 recipe）；UI：`ExportInspectorPanel.qml`（在检查器内、含 Export Queue）。

- **格式**：JPEG / PNG / TIFF / EXR（+ **Ultra HDR JPEG** 模式）；WebP 已从导出移除（0.2.9）。`ExportFormatOptions`（`supported_file_type.hpp:34-56`）：JPEG `quality_` 默认 95；PNG `compression_level_` 默认 5（UI 0–9）；TIFF 压缩 `NONE/LZW/ZIP`；`BIT_DEPTH` 8/16/32；`HDR_EXPORT_MODE` = `ULTRA_HDR` / `EMBEDDED_PROFILE_ONLY`；`ultra_hdr_quality_` 95（gain map 质量）+ `ultra_hdr_dither_enabled_` true，Ultra HDR 自动 8192px 上限。
- **尺寸**（`ExportResizeMode`）：Original / **Long Edge** px / Bounds（W×H px）/ **Print**（W×H + 单位 in/cm/mm + DPI）；`allow_upscale_`、`maximum_edge_pixels_`。
- **元数据策略**（`ExportMetadataPolicy`，默认 STANDARD=含 EXIF+XMP+IPTC）：`include_location_=false`、`include_device_serials_=false`、`include_editing_history_=false`——**定位、设备序列号、编辑历史默认剥离**（README:93）。导出文件 EXIF 写入 Alcedo 版本号（0.2.9）。
- **ICC**：`EMBED_OUTPUT_PROFILE`（默认）/ `OMIT`；输出色彩 `ExportColorProfileConfig` 从本图 DRT 派生（encoding space/EOTF/peak nits，入队前强制已解析，`export_recipe.hpp:131-150`）——导出与显示共享同一 DRT 编码。
- **文件名模板**：模式串如 `{date:yyyy MM dd}-{sequence:0000}`（`ParseExportFileNamePattern`）；字段 `ExportFileNameField`：LITERAL / SOURCE_STEM / CAPTURE_DATE / CAMERA_MAKE / CAMERA_MODEL / LENS_MODEL / ISO / APERTURE / SHUTTER_SPEED / FOCAL_LENGTH / RATING / SEQUENCE（序号可补零位宽）；fallback stem "image"；冲突策略 `FAIL` / `REPLACE`；可选子文件夹（默认文案 "Processed"）。
- **队列**：Add selected to queue、每项状态（Queued/Exporting/Done/Failed）、SDR/HDR 质量跨会话记忆（0.2.9）。

---

## 8. AI 功能（AI Features）

### 8.1 本地语义（CLIP 搜索 + 自动标签）
- **服务**：Rust 侧车 `rust/puerh_mind`（crate 名 `alcedo_mind`，tonic gRPC，C++ ↔ Rust 经 proto）；ONNX Runtime（Windows DirectML / macOS **CoreML**，`ort` + `coreml` crate；`coreml_clip.rs` 与 `ort_clip.rs` 双引擎）。
- **模型目录**（`configs` + `model_assets.rs` + Settings 页说明文案）：SigLIP2 B/32 256 Multilingual（默认推荐）、MobileCLIP2 S2 English（HuggingFace `plhery/mobileclip2-onnx@s2`，512 维）、Jina CLIP v2 INT8 Multilingual（`jinaai/jina-clip-v2`，768 维、512px 输入）、SigLIP2 Base CoreML macOS（Apple Silicon 原生）。支持维度 {512, 768}。
- **运行**：模型从 HF 下载（asset manifest + revision pin），嵌入写 `SemanticImageEmbedding`，DuckDB **HNSW 索引**（vss 扩展，`QueryHasHnswIndex`）做近似最近邻 → 自然语言搜索=文本嵌入查询；导入后 `SemanticGenerationDialog` 询问自动打标（Remember My Choice 可记住）；自动打标 = 预置中英文 label query 原型嵌入相似度，写 `SemanticImageLabel`（score/second_label/margin/confident）。
- 页面说明强调本地运行、图片不上云（`SettingDialog.qml`「Local Content Recognition」）。

### 8.2 AI 评片/描述（远程 LLM）
- **接口**：OpenAI 兼容或 Anthropic 兼容 endpoint；provider profile 模板见 `rust/puerh_mind/configs/providers/`（openrouter、volcengine_ark、opencode_go_*、ccswitch_*、**openai_codex_oauth**=ChatGPT/Codex OAuth 登录导入）。强制 HTTPS（仅 localhost dev 例外，`Cargo.toml` Phase 5c 注释 + reqwest rustls）。
- **输出**：描述 caption + tags(JSON) + scene + confidence（`ai_description.hpp`）；评分 **1–5 星 + 简短理由**（`ai_rating.hpp`: `kMinRating=1/kMaxRating=5`，clamp；星级写图库/EXIF `Rating` 列，理由文本存 `AiImageRating.reasons_`，rating=0 为 reasons-only 哨兵）。
- **配置项**：评片严格程度（SeveritySegmentedSlider）、输出语言（Follow app / English / 中文，`AiProviderSettingsPanel.qml`）、prompt profile（rubric 变更护栏 `prompt_profile_id`）。
- **密钥**：Windows Credential Manager / macOS 钥匙串（`credential_vault.rs`，zeroize 清内存）；UI 内 Paste API key → Save/Delete Key。
- **执行**：后台任务（`BackgroundTasksDialog`/`BackgroundTaskBar`、cancellation registry），分析期间可继续工作；设置页「Advanced Content Analysis」声明数据政策由所选 AI provider 决定、Alcedo 不留存。

---

## 9. dt 独有功能对照（darktable iop Coverage Gap）

**判断依据**：Alcedo 的调整全集 = `builtin_type_ids.hpp`（18 项）+ Develop 节点字段 + DRT 节点四项，注册表 `adjustment_catalog.cpp` 封闭；changelog/文档未列任何以下功能。对照 darktable `/Volumes/UNITEK/Documents/Development/darktable/src/iop/` 96 模块：

| darktable iop | Alcedo 状态 | 说明 |
|---|---|---|
| filmicrgb / sigmoid | **无（架构性替代）** | tone mapping 由终端 DRT（ACES 2.0/OpenDRT tonescale）承担，用户不可编辑场景→显示 tone spline；这是「DRT 而非 iop」的哲学差异 |
| toneequal | **无** | 无 local Laplacian；shadows/highlights 用局部色调映射近似 |
| denoiseprofile / rawdenoise / nlmeans 类 | **无** | 全目录无任何降噪项（LibRaw 解码层也不暴露 NR 滑块） |
| bilat / equalizer | **无**（Clarity 是最近对应） | Clarity=单一中间调反差标量 |
| velvia | **无**（Vibrance 近似） | 无按饱和度加权的 velvia |
| monochrome | **无专用** | 仅 saturation→0 + curve 可凑 |
| channelmixer / channelmixerrgb / colorbalancergb / colorzones | **无**（最接近 = HLS 8-bin + LGG 色轮） | 无按通道混合、无 3D 色相-亮度球 |
| cacorrect / cacorrectrgb | **无** | 无手动 CA 校正（KNOWN_ISSUES 提到解码色边只能裁掉） |
| hazeremoval | **无** | — |
| retouch / liquify | **无** | 无任何修图/变形工具 |
| lens（用户可调畸变/晕影/CA 数据库三滑块） | **部分** | Lensfun 几何校正启用+scale（`lens_enabled/user_scale/projection_enabled`），无 CA/晕影子滑块 UI |
| ashift | **无**（有 crop+rotation+aspect） | 无自动透视 |
| hlreconstruct | **有** | inpaint-opposed 改良版默认开启（`highlights_reconstruct=true`） |
| demosaic 算法菜单（PPG/RCD/AMaZE/VNG/Markesteijn…） | **部分** | 仅 default(RCD/Neural)/legacy/neural_engine 三选 |
| hotpixels / rawprepare / expose / basecurve | **无** | 场景参考管线无 basecurve/expose 对 |
| flip / borders / watermark / overlay | **无** | 导出无水印/边框 |
| 分割色调 splittoning / colisa 类 | **部分** | LGG 色轮覆盖 split-tone 大部分能力 |
| film grain（dt 无原生） | **反向独有** | Alcedo 有（IPOL 物理模型）+ Halation |

**Alcedo 独有而 dt 无**：节点式 Grade 图+Grade 蒙版、ACEScc 调色空间、ACES 2.0/OpenDRT 双 DRT 与 HDR 监看、DuckDB 库、CLIP 语义搜索/自动标签、AI 评片、mini-git 无限撤销+命名版本、Ultra HDR/OpenEXR 导出。

---

## 10. 对 Lightamer 的映射建议（Mapping to Lightamer）

Lightamer 现状基线：39 个 iop（exposure/temperature/tonecurve/levels/gamma/colisa/shadhi/sharpen/highpass/bilateral/nlmeans/denoiseprofile/colorbalancergb/colorzones/channelmixer/channelmixerrgb/colorcontrast/velvia/monochrome/equalizer/filmicrgb/sigmoid/agx/grain/bloom/hazeremoval/crop/flip/ashift/lens/liquify/borders/watermark/lut 等）+ Sessions/Catalogs 管理 + C1 adjustment layers + Phase 14 MCP server；working space = linear Rec2020 scene-referred float32；CIRAW 解码。

| Lightamer 已有 | Alcedo 对应物 | 差异 / 移植 / 禁用建议 |
|---|---|---|
| exposure | Exposure（`exposure_ev` ±16） | 移植默认值/范围对齐；Alcedo 默认 look +1.5 EV |
| temperature | CAT02 White Balance（Grade 级，场景参考色适应）+ Develop 相机 WB | **语义差异关键**：CIRAW 解码承担相机 WB；若引入 Alcedo 式「Grade WB」，需实现 AP1 白点假设下的 CAT02 色适应（默认 ≈6000K=identity） |
| tonecurve | Curve（单位方形点列） | 直接对齐；交互抄：左拖/右删/双击复位 |
| levels / gamma / colisa / shadhi | White / Black / Contrast / Highlights / Shadows 五标量 | Alcedo 更简；0.3.0 Contrast=中灰邻域 lightness 保色相——建议采纳该语义；shadhi 对应其「局部色调映射」实现 |
| sharpen | Sharpen（amount/radius/threshold，DRT/Post 拥有） | 移植所有权模型：细节工具不进 Grade、全图一次应用 |
| highpass / equalizer | Clarity（±100 标量，DRT/Post） | Lightamer 实现更精细，可保留但 UI 呈现按 Alcedo 单滑块 |
| bilateral / nlmeans / denoiseprofile | **无对应** | **保留为 Lightamer 独有优势**（Alcedo 无降噪）；UI 上归入 Alcedo 式 Detail/Texture 组避免破坏 IA |
| colorbalancergb | Color Wheel LGG（CDL 三轮+strength+luma offset，ACEScc 域） | **Lightamer 完全缺失 LGG 色轮**——高优移植项；colorbalancergb 可与 DRT tonescale 共存但 UI 主推三轮 |
| colorzones | HLS 8-bin（target hue + H/L/S adj + h/l/s range） | 可作 colorzones 的简化 UI 面 |
| channelmixer / channelmixerrgb | **无** | Lightamer 独有，收进「高级」分组 |
| colorcontrast / velvia / monochrome | Vibrance（±100）/ 无 / 无 | velvia/monochrome 保留为独有；vibrance 补齐 |
| filmicrgb / sigmoid / agx | **DRT 节点**（ACES 2.0 / OpenDRT 预设化） | **架构决定点**：模仿 Alcedo 则把 tone mapping 从 iop 链移到末端 DRT 节点，UI 只露预设（look/tonescale/creative white）+空间/EOTF/峰值亮度；自家 filmic/sigmoid/agx 可作为 DRT method 的扩展项而非滑块堆 |
| grain | Film Grain（strength 0…1，DRT/Post，display transform 后一次） | 移植「Post 拥有、全图一次」模型 |
| bloom | Halation（strength 0…1，DRT/Post） | 同上 |
| lut | LMT（CUBE path，Grade 内） | 直接对应；补「LUT 面板」（搜索/排序/收藏/打开目录，`LUTPanel.qml`）与内置 spectral film LUT 库 |
| hazeremoval / liquify / retouch(无) / borders / watermark | **无** | Lightamer 独有（尤其 yiyin 印框/水印是一等公民定位），不得删 |
| crop / flip / ashift / lens | Geometry（crop xywh/rotation/aspect）+ RAW Decode Lens Calibration（Lensfun 启用+scale+自动识别） | flip/ashift 保留为独有；Lensfun 目录搜索+元数据自动选镜头值得抄 |
| Sessions/Catalogs | `.alcd` 单项目文件 = DuckDB（+json） | **模型差异**：C1 Session 文件夹制 vs Alcedo 单文件库；若走「UI 完全模仿」仍可保留 Session 目录制，但建议吸收其 DuckDB 物化搜索列 + Filter/ComboFolder 相册模型 |
| C1 adjustment layers | Color Grade 节点 + Mask Groups 面板 + mix + 删除锁 | 概念几乎一一对应（见 §3 映射表）；Mask Groups 面板/节点图 UI 是**完全缺失、需新建**的两屏 |
| —（无蒙版） | Radial + LinearGradient 蒙版（brush 编译开关未出货） | 高优移植：参数化蒙版源 + invert/opacity/feather + overlay 手柄交互；亮度/参数化蒙版 Alcedo 也只有占位——Lightamer 可后发先至 |
| —（无版本） | Named Versions + mini-git EditCommit 图 + Branch/Fork + 自动保存 | **完全缺失**：命名版本、branch from current/fork from root、永久 undo、Copy Adjustments 细粒度勾选（按节点/条目→Paste 成新版本） |
| —（无 DRT 面板） | Display Transform 面板（Method/Space/EOTF/Peak nits/Limiting Space/OpenDRT 三预设） | **完全缺失**：含 macOS HDR 显示直出预览（EDR 管线已在 Lightamer STACK 规划内，落地为此面板） |
| —（无导出扩展） | OpenEXR 8/16/32bit、Ultra HDR JPEG（gain map+dither）、导出文件名模板 `{date}{sequence}`、元数据剥离策略 | **完全缺失**：Ultra HDR 与 EXR 导出、文件名模板、碰撞策略；ICC 嵌入 Lightamer 已规划，建议加「输出编码=本图 DRT」联动 |
| —（无语义搜索） | MobileCLIP2/SigLIP2/Jina CLIP 本地嵌入 + HNSW + 自动标签（中英 label query） | **完全缺失**；macOS 上可走 CoreML/BNNS 路线（对齐 Alcedo 的 coreml 引擎档） |
| —（无 AI 评片） | OpenAI/Anthropic 兼容 provider + 1–5 星+理由 + 钥匙串存 key + 后台任务 + 严格度/语言设置 | **完全缺失**；Keychain 对 macOS 原生是加分项 |
| Phase 14 MCP server | **无** | Lightamer 独有，保留 |
| 39 iop 中的其余（levels/gamma/colisa/highpass/hazeremoval…） | 无对应或近似 | 全部保留，UI 分组向 Alcedo 靠拢（Tone/Look/LUT/Display Transform/Geometry/RAW Decode/Mask 七页签） |

### Lightamer 完全缺失清单（模仿 Alcedo 需新建）
1. **节点编辑器 UI**（Develop→Grades→DRT 图、增删改名重连、QuickQanava 对应物需换 SwiftUI/Metal 自绘）。
2. **LGG 色轮**（CDL trackball + strength + luma offset）。
3. **DRT 节点与面板**（ACES 2.0/OpenDRT、空间/EOTF/峰值亮度、HDR 监看）。
4. **命名版本 + mini-git 历史 + Copy Adjustments**。
5. **蒙版体系**（radial/gradient 编辑器 + Mask Groups 面板 + 蒙版缩略图）。
6. **CLIP 语义搜索/自动标签**、**AI 评片/描述**（provider+Keychain+后台）。
7. **导出扩展**：OpenEXR、Ultra HDR JPEG、文件名模板、元数据剥离策略、导出队列。
8. **图库检查器**（Album Inspector 分组/Activity view）与全局搜索（EXIF 词法 + 自然语言 + 全文三合一）。
9. **设置面**：Local Content Recognition、Advanced Content Analysis、Keyboard 自定义、Cache、Updates。
10. **示波器面板**（直方图/波形切换）与胶片条联动。

### 建议禁用/不做（Alcedo 有但与 Lightamer 定位冲突）
- 无。Alcedo 的功能面是 Lightamer 的**子集+IA 模板**；Lightamer 的 39 iop 超集全部保留，仅 UI 呈现按 Alcedo 七页签收敛。唯一「反向决策」是把 filmicrgb/sigmoid/agx 从滑块面板降级/迁移为 DRT method（若采纳 Alcedo 管线语义）。

---

## 附：关键源码索引

| 主题 | 路径 |
|---|---|
| 总览/管线/平台 | `README.md`、`README.zh-CN.md`、`docs/build_from_source.md` |
| 版本日志 | `docs/changelog/0.2.9.en.txt`、`docs/changelog/0.3.0.en.txt` |
| 调整目录 | `alcedo_studio/src/edit/operators/models/adjustment_catalog.cpp:33-52`、`builtin_type_ids.hpp`、`scalar_operator_model.hpp:74-216`、`color_wheel_model.hpp`、`curve_model.hpp`、`hls_model.hpp`、`lmt_model.hpp`、`sharpen_model.hpp`、`cat02_white_balance_model.hpp` |
| 节点图 | `src/include/edit/graph/color_grade_node_model.hpp`、`drt_node_model.hpp`、`develop_node_model.hpp`、`pipeline_graph_commands.hpp`、`pipeline_document.hpp` |
| 蒙版 | `src/include/edit/mask/mask_model.hpp`（MaskSource/MaskModel/range 占位）、`brush_*.cpp`（未出货） |
| DRT | `src/ui/alcedo_main/qml/EditorDisplayTransformPanel.qml`、`src/config/DRTs/OpenDRT.dctl` |
| 库/历史 schema | `src/include/storage/store/database.hpp`（全部 DDL）、`docs/editor_versioning_ui_handoff.md` |
| 项目包 | `src/app/project_package_backend.cpp:269-382`（.alcd/.db/.json/HNSW） |
| 导出 | `src/include/io/image/export_recipe.hpp`、`src/include/type/supported_file_type.hpp:15-56`、`ultra_hdr_writer.hpp`、`ExportInspectorPanel.qml` |
| AI | `src/ai/ai_rating.cpp`、`src/include/ai/ai_description.hpp`、`rust/puerh_mind/`（`src/service/model_assets.rs`、`credential_vault.rs`、`configs/providers/`）、`AiProviderSettingsPanel.qml`、`SettingDialog.qml` |
| 已知问题 | `KNOWN_ISSUES.md`（v0.2.3：ACES2.0 HDR 峰值损坏、无法 relink 已删文件等） |

---

## 附：已知缺陷观察（实机/源码核实，供上游 issue 与反向教训）

- **文件夹导入不过滤附属文件（0.3.0 实机复现，2026-09-27 用户报告 + 源码定位）**：导入含 `.ARW` + `.ARW.xmp` 对的 C1 Session 目录时 `.xmp` 被当图片导入、数量翻倍。源码链：`CollectFolderFiles`（`import_export.cpp:131`）递归枚举**零扩展名过滤** → `StartImportPaths` 仅全路径去重 → `is_supported_file`（`supported_file_type.hpp:57`）仅 test host 调用、`image_loader.cpp:66` 处调用被注释；与 0.3.0 changelog「Import accepts camera RAW files only」不符。修复位 = `CollectFolderFiles`/`StartImportResolvedPaths` 套 `is_supported_file`。Lightamer 反向教训已钉入 REQUIREMENTS M2LIB-03 过滤加固 AC。
- **AI 离线包应用内下载全报错（0.3.0 实机，2026-09-27 用户报告）**：默认端点已设 `https://hf-mirror.com`（`ai_sidecar_runtime_service.hpp:65`）但仍失败；疑点 = `rust/puerh_mind/src/service/model_assets.rs:496` 的 `_hf_endpoint` 参数带下划线前缀（未使用惯例）——端点可能未接线到实际下载路径。未深查（非我方 scope）。Lightamer 对策 = M2AI-01 混合策略：默认模型内置包 + 大档走本仓 Release 资产。

---

## 上游增量测绘（2026-10-07，34241d0 → f1fae5d = 188 commits，v0.3.1 + 未发布主干）

> 本地仓已 ff 合并。我们提的 #213/#214/#215 **全部 CLOSED**（#214 → 0.3.1 导入文件类型选择器；#215 → #226 LUT library service）。以下为** parity 影响**，候选待裁决：

1. **非 RAW 栅格输入链（#265-270，大件）**——JPEG/PNG/TIFF/**OpenEXR** 导入即开发：源 color description（ICC）解析 + HDR 旗标 → **DisplayToAp1（ACES 2.0 inverse，OCIO 实现）** 进 develop 图；Metal staging 上传；缩略图取自全尺寸 decode；文件夹导入文件类型选择器（#264）。对照：我方编辑器可开非 RAW 但未形式化「栅格 = display-referred 输入经 DRT 逆链」语义。**候选 = V2 RASTER-IN 需求族**（EXR 与 ALCE-02 OpenEXR 导出对偶）。
2. **LUT 编码面（#271-274 + #226，直撞我方 LMT）**——LUT 面板 **input/output encoding 选择器** + 编码**烘焙进 LMT 表** + 库记住每 LUT 编码 + 传递曲线/色域目录（c740f7b）+ lut_catalog.cpp（413 行）退役换 **LUT library service**（递归清单/导入/根迁移 #226）。对照：我方 M2GRADE-05/06 递归+可配根已交付打平；**缺口 = LUT 作者编码建模**（胶片 LUT 常作于 log 域，我方按 working space 直套会有系统性偏差）。**候选 = M2GRADE-08 LUT IO 编码**（V2/M2 后期）。
3. **OCIO ACES 2.0 reference forward transform（8f8e712）**——我方 M2-6 aces-core 移植的**交叉验证资产**机会（parity 测试对表，非功能缺口）。
4. **图库编辑时间排序分组（57d6385/#276）+ 后台任务岛（ef12a93/#275）**——UI parity 注记；我方 BackgroundTaskHosting 语义已有，形态可对照。
5. **0.3.1 稳定性批**——导入扫描不卡窗（增量入列）/中文 Windows 崩溃修复/AMD OpenCL。方法论注记：其「扫描大文件夹持续加入文件」对 M2LIB-07 导入三模式 UX 有参考。
