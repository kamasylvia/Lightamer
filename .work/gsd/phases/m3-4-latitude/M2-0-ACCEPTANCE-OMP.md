# M2-0「测绘与规格」回溯二次验收（omp 独立）

> 对象：M2-0 charter/feature map，无代码交付。验收形态 = 五正本落账一致。
> 方法：零共享上下文亲测；Alcedo 侧一律 `git show 34241d0:<path>` 只读核实（pinned commit 存在、工作树干净）；GPL 仓零复制（本报告仅含符号名/行号/参数值等事实引用）。
> 日期：2026-10-09。STATE 登记：M2-0 complete (2026-09-27; D1-D6 signed)。

结论头：**PASS / 0 error + 6 minor**

---

## 一、抽查点 1：引用真实性（亲核 20+ 处，覆盖 UI/QML、operators、解码、AI 四面）

pinned 基线：`34241d0` = `[no ci] Merge pull request #210 …adjustment-transfer-audit`，与 feature map 头注记逐字一致。

### UI/QML 面

| # | feature map 引用 | 亲核结果 |
|---|---|---|
| 1-1 | `EditorWorkspace.qml:89` Desktop order 注释 | ✅ 命中（注释块实际 :88-90，digital order/tool rail/viewport/scopes+stack 逐词） |
| 1-2 | `EditorWorkspace.qml:331-347` FIT/百分比读出 | ⚠️ 语义命中、行号轻微漂移（FIT 文本实际 ~:328-331；见 minor m6） |
| 1-3 | `EditorAdjustmentStack.qml:10-16` 七页签 | ⚠️ 页签名 7/7 全对（Tone/Look/LUT/Display Transform/Geometry/RAW Decode/Mask，实际 `navItems` 在 :46-65），但引用行号 :10-16 为文件头注释（见 minor m1） |
| 1-4 | `EditorTonePanel.qml:126-139` exposure slider −10…+10 step 0.01 | ✅ 逐值命中（minimum/maximum/step/defaultValue 0 + reset 注释"user-created grades and reset both use 0"） |
| 1-5 | `EditorDisplayTransformPanel.qml` defaultIndex 1 + Look/Tonescale/CreativeWhite 列表 | ✅ 命中（method defaultIndex 1=open_drt；Look 7+custom；Tonescale `grep -c value:` = 15；Creative White entries 7 个值——计数见 minor m4） |
| 1-6 | EOTF 随空间联动（Rec709→BT.1886/G2.2；P3-D65→G2.2/PQ；P3-D60/DCI/XYZ→G2.6；Rec2020→PQ/HLG） | ✅ 与 `eotfOptionsForSpace` switch 逐支一致 |
| 1-7 | Limiting Space 七选 | ✅ 逐值命中（rec709/rec2020/p3_d65/p3_d60/p3_dci/prophoto/adobe_rgb） |
| 1-8 | SettingDialog 9 页 + 蒙版三选 verbatim | ✅ 页名 9/9；`Ask every time`/`Create a new layer, then draw`/`Draw on the current node` 逐字（:226-228） |
| 1-9 | 工具轨 History/Versions/Nodes + 0.3.0 图标下标签 | ✅ RailButton 三键全在；changelog 0.3.0 "shows a label below each icon" |
| 1-10 | AdjustmentTransferDialog 三层 pane | ✅ `AdjustmentTransferVersionPane/NodePane/ItemPane` 组件名全在 |
| 1-11 | Geometry「applies to the whole image」+ 范围 | ✅ 文案逐字（:654）；crop 0…1/0.0001…1、rotation ±180 全命中 |
| 1-12 | ScopePanel「Show histogram」「Show waveform」 | ✅ 逐字（:84-87） |
| 1-13 | 主题 tokens colCardSurface/colCardBorder | ✅ QML 消费点逐名（:31-32） |
| 1-14 | 视口三件 EditorViewportItem/Overlay/InteractionController | ✅ 头文件三名全在（`ui/editor_rhi/`） |
| 1-15 | mask_thumbnail_coordinator.cpp | ✅ .hpp/.cpp 双文件在册 |

### operators/模型面

| # | 引用 | 亲核结果 |
|---|---|---|
| 1-16 | `adjustment_catalog.cpp:33-52` 18 注册 | ✅ 18 个 `Register` 逐名与 §2.1 表一致（见抽查点 2） |
| 1-17 | `builtin_type_ids.hpp:11-82` | ✅ 15 调整 type_id + Develop/Grade/Drt 三节点 id 全在范围内 |
| 1-18 | `color_grade_node_model.hpp:29-34` 所有权注释 | ✅ 逐句（ordered list/GraphCompiler must not reorder/display order/DRT-owned rejected/scene-image input only） |
| 1-19 | `:56-65` MakeDefault 默认 look 注释 | ✅ + 常量亲证 `kDefaultPipelineExposureEv=1.5/Contrast=15.0/Saturation=1.3`（pipeline_document.hpp:112-116） |
| 1-20 | cat02/hls/curve/sharpen/wheel 默认值域 | ✅ 逐值：5999.9934/9.7112783/2000-15000/±150；HLS 8 bin+45°+target{0,0.5,1}+45/0.1/0.1；curve identity；sharpen 0/3/0；wheel lift 零/gamma·gain (1,1,1) |
| 1-21 | scalar range（exposure ±16 / saturation 0-4 / halation·grain 0-1 strength） | ✅ Traits 常量逐项；JSON key exposure_ev/contrast/…/strength 全对 |
| 1-22 | 图命令 7 名 + grade.primary/drt.* | ✅ AddClean/Remove+Bridge/Reconnect/Rename/SetEnabled/SetMix/InsertFromJson 逐名；`grade.primary`+develop/drt 连边亲证 |
| 1-23 | 旧式 MaskNode 拒绝 | ✅ pipeline_document.cpp 两处 AnalyticMaskNode/RasterMaskNode 比对拒绝 |
| 1-24 | `mask_model.hpp:28-34` 类型枚举 | ✅ Radial=1/LinearGradient=2（Brush 在开关内） |
| 1-25 | `:100-120` Color/LuminanceRange 占位 | ✅ 双 struct 均为 `enabled=false` + 注释"Only the disabled placeholder" |
| 1-26 | `:188-199` 应用序 feather→invert→opacity→clamp | ⚠️ 部分成立：hpp 注释实证 invert→opacity→clamp（RadialMaskParams doc ~:187-190）；feather 为源内参数无 mask 级序文本证据，行号亦对位 struct 体（见 minor m2） |
| 1-27 | `drt_node_model.hpp` 段（EOTF 枚举 :35-43 / 53 参数 :45-99 / 默认 OpenDrt :102 / 载荷 :107-113 / 端点 :182-187 / drt.* :203-207） | ✅ 六段全命中（DrtEotf 7 值；DrtPayload 默认逐字段；"display output is not a scene graph port"；instance id 注释逐字） |
| 1-28 | 45→53 勘误注记 | ✅ 注记内分组求和 9+1+3+4+3+3+6+6+4+2+12=53，亲核 hpp 字段逐数一致；REQUIREMENTS「原文不改」政策在案 |

### 解码面

| # | 引用 | 亲核结果 |
|---|---|---|
| 1-29 | demosaic default/legacy/neural_engine + RCD Bayer/Neural X-Trans | ✅ QML entries 三值 + README:44 逐句；`debayer_rcd.metal`/`demosaicnet_io.metal`/`xtrans_interpolate.metal` 全在 gpu/metal_shader/ |
| 1-30 | highlights_reconstruct=true + inpaint-opposed 出处 | ✅ DevelopPayload 默认 true；README:129 darktable opposed.c + RawTherapee hilite_recon.cc |
| 1-31 | 相机 WB/lens 字段（custom_cct 6500/lens_enabled false/user_scale/projection_enabled/camera_profile） | ✅ DevelopPayload 逐字段 |
| 1-32 | 10 RAW 扩展名（supported_raw_formats.md） | ✅ .3fr/.arw/.cr2/.cr3/.dng/.fff/.nef/.raf/.raw/.rw2 逐项 |
| 1-33 | 导入缺陷链（CollectFolderFiles :131 零过滤 + image_loader 注释 + is_supported_file 孤儿） | ✅ 三环全亲证（递归枚举无过滤；loader 内 `is_supported_file` 调用被注释；函数定义在 supported_file_type.hpp——行号 :57→实际 ~:64，见 minor m6）；与 0.3.0 changelog「Import accepts camera RAW files only」(:8) 矛盾成立 |

### AI 面

| # | 引用 | 亲核结果 |
|---|---|---|
| 1-34 | tonic/ort/CoreML 双引擎 | ✅ Cargo.toml: tonic 0.14/ort 2.0-rc.12(+coreml feature)/coreml 0.3.5/reqwest rustls/zeroize；`coreml_clip.rs`+`ort_clip.rs` 双文件 |
| 1-35 | 模型目录 4 档 + 维度 {512,768} | ✅ SettingDialog 文案四模型 verbatim；model_assets.rs `SUPPORTED=[512,768]` + `plhery/mobileclip2-onnx:s2` |
| 1-36 | providers/ 模板族 | ⚠️ 所列 7 名全在，另有 `volcengine_ark_coding.json` 未提及（见 minor m5） |
| 1-37 | `ai_sidecar_runtime_service.hpp:65` hf-mirror 默认端点 | ✅ 逐字 `= "https://hf-mirror.com"` |
| 1-38 | `model_assets.rs:496` _hf_endpoint 未接线疑点 | ✅ 亲证：`ensure_present(_revision,_hf_endpoint,_allow_download)` + 注释明言下载由 C++ aria2 层处理——feature map「疑…未接线」与源码注释一致 |
| 1-39 | ai_rating kMin=1/kMax=5 clamp | ✅ :48-49 逐行 |
| 1-40 | DuckDB vss HNSW + DefaultSemanticPhotographyLabelQueries | ✅ semantic_vector_search.hpp HNSW 注释 + 语义表头预置函数 |

### 库/导出/DDL 面（附带深核）

- mini-git 四表 DDL（EditCommit 双亲/kind/payload、VersionRef、ImageEditState 材质化列、PipelineRoot）✅ 列名逐字；Image 物化搜索列 ✅ 逐列（含 exif_search_text/words）；SemanticImageLabel/AiImageUnderstanding/AiImageRating ✅ 全字段。
- 项目包 `project_package_backend.cpp:269-382` ✅（.alcd 去后缀 + `stem.db`/`stem.json` pair 构建在范围内）；0.3.0 不开 0.2.9 项目 ✅（changelog :5-6）。
- 导出：ExportFormatOptions（quality 95/PNG 5/TIFF 三档/BIT_DEPTH/HDR 双模/ultra_hdr 95+dither）✅；resize 四模式+物理单位+DPI ✅；collision FAIL/REPLACE ✅；12 文件名字段 ✅；fallback "image" ✅；子目录 "Processed" ✅；Ultra HDR 8192 钳制 ✅（import_export.cpp:371）；`output_color_` 入队前强制解析 ✅（:131-150）。
- 版本交互规则 ✅（跳回保 redo 尾/再编辑丢尾/即时切换/自动保存/可改名/从原始态新建/跨图延后——handoff :17-27 逐条）。
- 0.3.0：Activity view ✅ / Contrast 中灰语义+新图+15 ✅ / Copy Adjustments ✅ / Keyboard ✅ / Lens 移 RAW Decode ✅ / DNG HueSatMap ✅ / Post 四件 DRT 后全图一次 ✅（changelog :44-45）；0.2.9：WebP 移除 ✅ / EXIF 版本号 ✅ / Updates 页 ✅。
- KNOWN_ISSUES：ACES 2.0 HDR 峰值损坏 ✅ / 删盘文件无法 relink ✅。

---

## 二、抽查点 2：内置 18 目录对表

catalog 注册（`adjustment_catalog.cpp` 18 个 Register）vs feature map §2.1 表：**数量 18=18，目录名逐项一致**（CAT02 White Balance/Exposure/Contrast/White/Black/Shadows/Highlights/Curve/HLS/Saturation/Vibrance/Color Wheel/LMT/Clarity/Sharpen/Halation/Film Grain/Tint），type_id 尾段 18/18 全对（`alcedo.adjustment.<tail>`）。

归属（`adjustment_ownership.cpp` + `color_grade_node_model.hpp` 所有权语义，抽 7 项超标）：

| 抽查项 | feature map 归属 | 亲核 |
|---|---|---|
| Exposure | Grade | ✅ Grade 13 表内 |
| Saturation | Grade | ✅ Grade 13 表内 |
| Clarity / Sharpen / Halation / Film Grain | DRT/Post | ✅ DrtPost 4 表内；Grade `InsertAdjustment` doc 声明 DRT/Post-owned 抛异常 |
| Tint | 目录内标量（非两属） | ✅ `OwnerOfAdjustment` 对 Tint 落 `Unsupported`（不在任一表内）——表述成立 |

注：hpp:30-33「GraphCompiler 不得重排」与 ownership「编译序固定、文档序仅选参数身份」两处上游注释存在字面张力，属上游表述差异，feature map 忠实转述其一，不计缺陷（obs-o1）。

---

## 三、抽查点 3：ROADMAP M2 表 12 行覆盖对表

| Phase 行 | feature map 锚点 | 结论 |
|---|---|---|
| M2-0 | 自身=测绘交付；闭环四要素：feature map（初版 301 行 `d0ffd80`→现 330 行）+ 本表 + REQUIREMENTS M2 族 + D1-D6 签核（`f0295fd` body 逐条 verbatim） | ✅ 齐备 |
| M2-1 | §9 gap 表 + §10 映射（D1/D2/D6 落点） | ✅ |
| M2-2 | §6 全节（DDL/导入/项目/物化列/剥离） | ✅ |
| M2-3 | §1 全节（双工作区/七页签/设置页族/后台任务） | ✅ |
| M2-4 | §3 节点图（链语义/7 命令/ordered list/Grade-owned 蒙版） | ✅ |
| M2-5 | §2.1 全表 + §2.2 ACEScc + LMT/LUT 面 | ✅ |
| M2-6 | §5 DRT（预设三件套/EOTF 联动/Peak/HDR 判定/Post 四件） | ✅（行内"45 detailed"为历史冻结字面，勘误链在 feature map 注记+M2DRT-02，不追改） |
| M2-7 | §4 蒙版 + D5 Nitro 扩展 | ✅ |
| M2-8 | §6.2 mini-git DDL + §6.3 版本交互 | ✅ |
| M2-9 | §7 导出 recipe 全项 | ✅ |
| M2-10 | §8 AI 双节 + 混合策略（§附缺陷观察反向教训） | ✅ |
| M2-11 | 间接锚：§1.3 引 README:48（2.5K@60fps/4K/可见区渲染）+ M1 Phase 15 资产延续（行内自述"原 Phase 15 重校"） | ✅ 可接受（性能专项非 Alcedo 功能面，行内锚点自洽） |

---

## 四、抽查点 4：REQUIREMENTS M2 族对表（抽 8 条超标）

| FR | 出处锚点 | 结论 |
|---|---|---|
| M2DIS-01 | §9+§10（D1/D2/D6） | ✅ 无孤链 |
| M2LIB-03 | §6.4 + §附导入缺陷链（file:line 全亲证，见 1-33） | ✅ |
| M2GRADE-01 | §2.1 全表逐值（见 1-20/1-21） | ✅ |
| M2DRT-02 | §5 预设三件套 + 45→53 勘误链 | ✅（Tonescale"15"按 QML entries 计准确；M2-6 口径 14 系排除 custom 的另一计数，勘误链在案非矛盾） |
| M2VER-01 | §6.2 DDL 逐字 | ✅ |
| M2EXP-03 | §7（12 字段/fallback/FAIL-REPLACE/Processed 全亲证） | ✅ |
| M2AI-01 | §8.1 + §附 AI 下载缺陷（见 1-38） | ✅ |
| M2NODE-02 | §3 七命令逐名（见 1-22） | ✅ |

M2 族全枚举 79 个 ID（含 M2GRADE-08/M2AI-09·10 等后立项，均有独立出处注记：上游 delta / Lumen 借鉴 / M1 延续），**零孤链**。

---

## 五、与首验/申报分歧点

M2-0 为 charter phase，无首验 ACCEPTANCE；下为本次独立验收相对申报材料的分歧清单（6 minor，均行号/计数级，无一触及功能语义与规划正确性；既有勘误链内项如 45→53、44→40 张不重复记）：

- **m1**：七页签行号 `EditorAdjustmentStack.qml:10-16` 实际为文件头注释，页签定义在 `navItems` :46-65（页签名 7/7 正确）。
- **m2**：蒙版应用序"feather→invert→opacity→clamp"（`mask_model.hpp:188-199`）——hpp 实证仅 invert→opacity→clamp，feather 为源内参数；行号对位 struct 体非序陈述。
- **m3**：画笔文件"9 个"——pinned 树 src+include brush_* 实际 14 个（6 cpp + 8 hpp；再加 tests 4 + docs 1 = 19）。
- **m4**：Creative White "6"——QML entries 实际 7 个值（use_look_preset + D93/D75/D65/D60/D55/D50）；ROADMAP M2-6 行与 REQUIREMENTS M2DRT-02 原文同源同错一处记。
- **m5**：providers 模板列举漏 `volcengine_ark_coding.json`（所列 7 名全对）。
- **m6**：行号轻微漂移三处：`is_supported_file` :57→实际 ~:64；FIT 读出 :331-347→实际 ~:328 起；README 平台 :19,114-115→实际 :19/:114。

obs-o1（非缺陷）：上游 hpp「不得重排」vs ownership「编译序固定」字面张力，feature map 忠实转述其一；M2NODE-03 已按"顺序=用户数据"交付。

---

## 六、会话卫生

- 只读验收：Alcedo 侧仅 `git show/grep/ls-tree`（pinned commit 读），工作树干净；本仓零源码/文档修改（`git status` 仅预存 untracked：dt-clone-archive/ + 2 张 gui-acceptance jpg，与本验收无关）。
- 未跑测试（纪律禁跑全套；纯文档面无测试面）。
- 未 push。唯一写入 = 本报告文件。

OMP-VERDICT: PASS
