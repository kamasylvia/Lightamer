# M3-1 RESEARCH-NOTES — 上游对表实测 + 底座锚点

> 研究正本配套 = 同目录 `M3-1-CONTEXT.md`。两参考仓只读（Alcedo GPL-3.0 / yiyin fork MIT——零复制纪律）；file:line 为实测当日行号。

---

## 一、Alcedo `c740f7b` — LUT input/output encoding 建模形态（本地仓 HEAD `f1fae5d`）

提交：`c740f7be` "feat(color-encoding): Add one catalog for transfer curves and color gamuts"（2026-10-05）——新建 `color/` 目录（`color_encoding_catalog.cpp` 354 行 + `color_encoding_math.h` 四后端传递曲线），并把 DRT/raster input/DNG profile/local tone/UltraHDR 各处的 ACEScc/sRGB/PQ/HLG/gamma/primaries 副本**收敛到目录单源**（stat：删 `cuda_acescc.cuh` 等 33 行副本、改 20+ 文件）。

### 1.1 编码目录（`alcedo_studio/src/color/color_encoding_catalog.cpp`）

- **gamuts**：`kGamuts` 22 条（:35-57），`{id, name, primaries_xy[8], ChromaticAdaptation}`；AP0/AP1 用 Cat02，其余 Bradford/含 D65 与 ACES 白点常量（:24-26）。`static_assert(GamutsAreInIdOrder)`（:61-70）= id 即索引。
- **encodings**：`kEncodings` **26 条**（:139-172），每条 `{id, gamut, transfer, referral(scene|display), peak_luminance_nits, display_name}`：
  - scene-referred 17 条 = log 家族：acescc/acescct（AP1）、arri_logc3_awg3/logc4_awg4、sony slog3×2、fuji flog/flog2、pana vlog、canon clog2/clog3、red log3g10、bmd film gen5、davinci intermediate、apple log、nikon nlog、dji dlog——全部 peak=0.0（scene 无 peak 语义）。
  - display-referred 9 条：rec709_bt1886 / rec709_srgb / rec709_gamma22 / displayp3_srgb / p3d65_gamma26（peak 48）/ p3dci_gamma26（48）/ rec2020_bt1886 / rec2100_pq1000 / rec2100_hlg1000（后两条 peak 1000）。
  - 注记：F-Gamut/N-Log gamut 行复用 BT.2020 原色（注释 :135-137 引厂规格）；**无独立 "gamma 2.4" 行——BT.1886 即 2.4 族**（我方 M2-6 EOTF 实现同语义：BT.1886 = Lb0 纯 2.4）。
- **查找/校验**：`FindColorEncoding(id)` 线性扫（:205-215）未知返 nullptr；`lut_bake.cpp` `RequireEncoding`（:293-300）未知 id typed throw。

### 1.2 LMT 节点模型（`alcedo_studio/src/edit/operators/models/lmt_model.cpp` + `lmt_model.hpp`）

- 默认 id：`kDefaultLutEncodingId = "acescc"`（`lmt_model.hpp:23`）+ static_assert（`lmt_model.cpp:15-16`）**钉死 LUT 默认编码 = 目录默认 = working space**。
- `LmtUpdate` 携 `input_encoding/output_encoding` 可选更新，`ValidateLutEncodingId` 目录内校验（:48-51 调用、:80-84 实现）。
- JSON 读：`ReadEncoding`（:36-44）**缺键 = 默认 id**（旧档宽容）；`input_encoding`/`output_encoding` 字段落 params（`lmt_model.hpp:32/:49-50` 面板投影同默认值）。

### 1.3 烘焙生效点（`alcedo_studio/src/edit/runtime/lut_bake.cpp`）——**核心机制**

- **不是 kernel 前后双 pass**：`ResolveLmtSampledTable(source, input_encoding_id, output_encoding_id)`（:317-352）把编码对烘进表本体：
  - **快路径**（:321-323）：`IsWorkingSpace(input) && IsWorkingSpace(output) && HasUnitDomain(source)` → 源表原样返回零烘焙（`IsWorkingSpace` :33-35 = id == kDefaultColorEncodingId；`HasUnitDomain` :195-203 = 域 [0,1]）。
  - 复合键 `CompositeKey = {source_hash, domain[6], input_id, output_id}`（:88-101）+ 进程级 `CompositeCache` LRU 16 张（:117-158），竞态双烘焙同内容取先到（:348-351）。
  - 复合表 = 65³ RGBA32F ≈4.4MiB；逐 voxel `inputDecode → SampleLutTable → outputEncode`，宿主线程池切片（:300-313）+ **Float64 矩阵乘**（`Multiply` :46-56——「float 积会丢多 stop 小通道」签注）；烘焙后重算 ContentHash（:338-341）+ `g_bake_count` 可观测（:354-356）。
- **display 臂中介语义**（:60-108）：display light（1.0 = 100 nits）为中介——
  - `DisplayDecode`：codes<0 无光；PQ/HLG codes>1 clamp；HLG 施加参考显示器 luminance OOTF（`CeHlgOotfGain`）；SDR 按 `peak_luminance_nits/100` 换算。
  - `DisplayEncode`：PQ 通道 `×100`；SDR/HLG code 1.0 = 该编码 peak（`100/peak` 换算 + HLG display gain）。
  - scene log 臂 = `CeDecode/CeDisplayEncodeChannel(tf, …)` 传递曲线正逆（`color_encoding_math.h` 四后端单源）。

### 1.4 库内逐 LUT 记忆（`alcedo_studio/src/app/lut_library_inventory.cpp` + 控制器）

- 库用户态 JSON：`remembered_encodings: {entry_id: {input, output}}`——读 :98-118（坏条目进 dropped 清单不崩）；**写 :172-179 仅在非空时写字段**（无记忆档字节零漂移——与我方 sidecar decodeIfPresent/encodeIfPresent 惯例同构）。
- 控制器（`lut_library_controller.cpp`）：载入序 `RememberedEncodings(entry_id).value_or(默认对)`（:320-324 注释明文「A LUT without remembered encodings applies the default pair」）；「记住编码」= 开关 `setRememberEncodings`（:333-339），**仅库内 LUT 可记**（:334-336 错误文案）；关联变更信号 `associationChanged` → 面板模型 `loadFromTarget`（`editor_lut_encoding_model.cpp:60-66`）。
- 面板枚举模型（`editor_lut_encoding_model.cpp:23-40`）：条目 = 目录全量，`group = scene|display` + groupLabel Tr("Scene")/Tr("Display")；默认 index = acescc。
- 测试锚（行为清单）：`tests/ui/lut_remembered_encodings_controller_test.cpp` / `tests/app/lut_encoding_render_paths_test.cpp` / `lut_library_remembered_encodings_test.cpp`。

## 二、yiyin fork `a7ab9f8`（PR #126 preview-adjust，MIT）— 拖拽分割线语义

本地仓 HEAD = `f8de57a`（上游 PR #126 已同步 merge）。改动 5 文件 +367/−18。

### 2.1 交互语义（`web/main/components/actions/index.svelte` diff）

- 常量块（diff +16..25）：`PREVIEW_MIN_WIDTH 120 / MAX_WIDTH 720 / MIN_RATIO 0.15 / MAX_RATIO 0.75 / MIN_HEIGHT 160 / MAX_HEIGHT 560 / MIN_HEIGHT_RATIO 0.35 / MAX_HEIGHT_RATIO 0.92 / SPLITTER_SIZE 6 / IMG_LIST_MIN_WIDTH 180`。
- 双轴：`resizeAxis: 'width' | 'height'`；`startResize` = pointer capture + body class（`preview-resizing-x/y` 光标态）+ window 级 move/up 监听。
- **双重钳制**：`clampPreviewWidth/Height` = px 界与「可用域 × 比例界」取交再 clamp（`getLayoutMetrics` 扣 `SPLITTER_SIZE + gap 15×2 + IMG_LIST_MIN 180`）。
- **比例持久化只在 pointerup**：`persistPreviewRatio()` 按 axis 写 `preview_pane_width_ratio` / `preview_pane_height_ratio`，`Math.round(ratio*1000)/1000` 三位小数；**拖动中不落盘**。
- **拖动禁内容重算**：`isDragging` 早退 `applyPreviewSize`（+24）；`getPreviewUpdateKey` **剔除两布局字段**（`delete options.preview_pane_width_ratio/height_ratio`，+44-56 注释「仅包含会影响预览图内容的配置」）——拖分割线不触发 300ms debounce 预览重渲染。
- 容器 `ResizeObserver`（onMount/onDestroy + `$:` 块）= 窗口缩放按 ratio 重排；实时读数 `$: resizeHint = \`${Math.round(previewWidth)} × ${Math.round(previewHeight)}\``。
- 布局：`preview-panel`（width px, flex 0 0）内含 `preview-wrap`（height px）+ 下方 horizontal splitter（height 轴）+ 侧 vertical splitter（width 轴）；图像列表占余量。

### 2.2 持久化默认（`electron/src/config.ts` + `web/store/config.ts` diff）

- `preview_pane_width_ratio: 0.5` / `preview_pane_height_ratio: 0.85` 两键进默认配置块（两侧各 +2 行）。

## 三、我方底座锚点（复用面实测）

### 3.1 LUT 栈（`LightamerIOP/Sources/Lut3d/`）

- `Lut3dModule.swift`：`LutColorspace`（:39-44，sRGB/displayP3/rec2020/proPhotoLinear = **色域矩阵维**）/ `LutInterpolation`（:46-49）/ `Params {lutName?, colorspace, interpolation}`（:53-72）/ opName "lut3d" :76 / iopOrder 36.0 :79 / flags `[.supportsBlending, .allowTiling]` :81 / `commitParams` paramsHash（D-H4，:139-143）/ resolver 注入 `LutResolving` 协议 :93 / colorspace 矩阵消费 :194。
- `LutColorspaceMatrices.swift`：:49 enum 容器 + :57 `matrices(for:)` 正逆对 + :82-105 Rec2020↔sRGB/P3/ProPhoto 常量阵——**既有色域维，与传递曲线维正交**（CONTEXT §二 D-1）。
- `LutLibraryStore.swift`：`InstalledLut {name, hash, is1D, size, title?, relativePath?, subdirectory?}`（:52-80，additive optional 先例 :61/:64 = M2-5 key 升级批）/ `SharedForwardingResolver`（:112-118）+ `sharedResolver` :118 / `libraryRootKey` :125 / `supportedExtensions ["cube"]` :148 / `entry(named:)/entry(withHash:)/lut(named:)/isMissing` :333-362 / `importLut` :407 / `removeLut` :451——**逐 LUT 记忆对挂 InstalledLut additive 字段 + 库 JSON**。
- 测试族：`Tests/LightamerTests/`（CubeLutParserTests / Lut3dKernelTests / Lut3dGoldenImageTests / LutLibraryStoreTests / LutLibraryRecursionTests / BuiltInLutSetTests）——快路径零 diff 回归面。

### 3.2 LUT 面板（`App/Sources/Lightamer/UI/Inspector/LutPanelView.swift`）

- 结构：Section 导入按钮（:47-51，AX `inspector.button.lut.import`——**FINDING-F 崩点位 ：159 importLut**）+ colorspace Picker（:66-71）+ interpolation Picker（:74）+ `importLut()`（:163-183）。
- **M3-1 增量位**：encoding 双 Picker 插 colorspace Picker 邻位；`LutPanelView.swift` 与在飞修复批文件级交叉（CONTEXT §五隔离前提——修复批落地形态未知，plan 以增量 hunk 为准）。

### 3.3 yiyin sheet（YIYIN-09 落点）

- `WorkspaceHostView.swift`：`isYiyinSheetPresented` :107 / sheet 挂载 :202-204 / **`YiyinTopBarSheet` :1216-1285**——标题栏 + 关闭钮（AX `yiyin.sheet.close`）+ 空态 ContentUnavailableView + `ScrollView { YiyinPanelView + TextOverlayPanelView }`；**固定 `.frame(width: 420, height: 560)`（:1273）；AX `yiyin.sheet`；无预览区**。
- `YiyinPanelView.swift:28-29`：「The main viewport IS the preview (no panel canvas — the pipe renders live)」——in-sheet 预览冗余论据（CONTEXT §三方案 A）。

### 3.4 导出小件（冲突档 + peak-ICC）

- `LightamerCore/Sources/Export/ExportNamer.swift:21`：`ExportCollisionPolicy: String, Codable, Hashable, Sendable` 三档（increment 默认 = 既有 `-1/-2` 行为逐字节 / fail typed / replace 永不落 -N）——引擎钉死面（`3b90709`，M2-9-01 验收 §三.5/.6；E2E `testFailPolicyFailsQueueJobWithoutWriting`）。
- 挂账正本：`M2-9-VALIDATION.md:59`（晨审判「选择器必须暴露」）+ `:124`（挂账#4 `enqueueExportM2` 固定 `.increment`）。
- peak-ICC 边界正本：`M2-9-02-DECISIONS.md:41-45`（peak 不入 ICC 有意缺席；validate peak 闸门 = `ExportVariant.validate` finite 正数 / nil 不触发；真容器 = UltraHDR ALCE-02 M4）。

### 3.5 denoise 拖动降档在案事实

- `phases/m2-11-performance/perf.md:43-64`：OQ-7-A bounded 降载三档（decimate step 57→37→29 趟）全不达 16.6ms revert（除线外推达线需 ≤8 趟 = 观感崩坏禁入）；`:60` 「V2 备选语义（拖动降档预览）移交 M2-11-04 重述批注记」；`:64` 引擎级 `downgraded(57 passes) 26.5 ms` 独自超门。
- `M2-11-VALIDATION-INPUT.md:151` 行：denoise 腿「挂账（denoise → V2 语义拖动降档预览）」。
- NLMeans 现状：`LightamerIOP/Sources/NLMeans/NLMeansModule.swift`（K = ceil(7·scale) → 120 offsets = 481 passes 全质量态，:16-17 注）——降档语义只动 App 层拖动态旁路，kernel/参数面零触碰。

### 3.6 zh 清算输入清单

- FINDING-G 正本：`M2-11-VALIDATION-INPUT.md:127`（`metadata_rating_1..5` / `metadata_color_0..5` 裸键直出，F-2 插值键陷阱同族）。
- V14/V15 行：同文件 :207-208（→ Phase 15 清算批——V2 站裁决提前执行，OQ-V2-9 同批）。
- M2-6-3 F1：ProjectWorkspaceFace 4 处 zh 缺口（GOAL-STATE 挂账延续）。
- 方法论先例：AGENTS「M2-7 架构增量」xcstrings 节（静态 MISSING + 动态族双清单并集对账；新键块 append 尾部 diff = 纯插入）。

### 3.7 内置 LUT 集作者编码对（M2GRADE-08 补标依据）

- `phases/m2-5-color-grade/evidence/spectral-film-lut-license.md:150-152`：生成参数 = **input ARRI Wide Gamut 4 / WB 6500K / output Rec.709 + Gamma 2.4**（SpektraLab 应用默认）；40/40 全 65³，vendored 来源 JanLohse/spectral_film_lut v0.18.2（MIT）零 Alcedo 字节。
- 推论：内置集直套 working space = log 域表 × 线性输入 = M2GRADE-08 所修系统性偏差的**在库实例**；正确管线 = LogC4/AWG4 进 → LUT → Rec709 BT.1886 族出（复合烘焙两臂各有事做）。补标决策 = OQ-M3-1-4。

## 四、纪律与流程锚

- 立项裁决链：`phases/v2-station/OQ.md:75-77`（OQ-V2-1..10 全按推荐，用户预裁 2026-10-08）→ 本批 OQ-M3-1-1..7 为**实现语义层**新分叉，预裁不覆盖。
- 在飞修复批：`M2-11-VALIDATION-INPUT.md:123/:186/:221` + `V2-PROPOSAL.md:171`（waves 派发前复核 git log / GOAL-STATE；FINDING-F owned = LUT 导入面板取消腿、ToneEqual = IOP 面）。
- 单测跑法：`Scripts/test-direct.sh --bundle <域>`；全套 `--all` 须 orchestrator 批准 + MEMFAIL 8G 机检（AGENTS 资源监控节）。LUT/编码新测试按 BUNDLE-MAP 域模式归 target（IOP 算法域 / IOPParity 对照域），`tuist generate` 恒批尾（L041）。
- 许可：Alcedo GPL-3.0 零复制（只对表形态与行集）；传递曲线数学源 = ITU-R BT.709-6/BT.2100、SMPTE RP 431-2、ARRI LogC 白皮书、厂规格（Alcedo 目录注释 :29-33 的来源清单可作**文献指针**，非代码）；yiyin MIT（模式借鉴；成段移植须 MIT 归属注记——SwiftUI 重写预期零成段移植）。

---

*实测：2026-10-08（discuss/research 起草 subagent）；两参考仓只读零写入。*
