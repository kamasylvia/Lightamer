# 光谱核 module 化调研（spektra-module RESEARCH，2026-11-02）

> 结论头：**PASS / 0 error + 1 minor**（minor 见文末「验收自查」）。
> 任务书正本 = `sm-research-prompt.md`（同目录）。全程只读侦察：零 commit / 零构建 / 零测试；产物 = 本文件（chunked 追加写）。
> **在制注记**：主仓有执行 lane 在飞，`LightamerCore/Sources/Film/{FilmMaterialStore,FilmProfile,PaperGradeTable,SpectralBuildEngine}.swift` 与 `Tests/LightamerTests/{BWProfileAssets,CameraFilter,FilmProfile,SpectralBuildGolden,SpectralConservationFallback,SpectralDualArmGolden,SpectralExposureSemantics,SpectralGrainGolden,SpectralNeutralSolve,SpectralProfileDecode}Tests.swift` 有未提交 diff（`git diff --stat` Film/ 四件 +112/−28）。本文对这四个 Film/ 文件**不引行号**（只引符号名）；其余引用均为 HEAD 已提交字节。dt 仓只读（`/Volumes/UNITEK/Documents/Development/darktable`，本地检出）。

## §0 结论先行

1. **dt 事实**：spektrafilm 是一个**标准 iop module**——iop order **46.7**（五张 order 表全同值，紧随 filmicrgb 46.0、先于 colisa 47.0，legacy 回落 `_insert_before_after(…, "colisa", "spektrafilm", TRUE)`）；flags = `SUPPORTS_BLENDING | INCLUDE_IN_STYLES | ALLOW_TILING`（**无** ONE_INSTANCE → 多实例合法；**可蒙版/可混合**）；默认 **off**（无 `default_enabled`）；params v3 共 **76 字段**（`DT_MODULE_INTROSPECTION(3, …)`）；OpenCL 腿 **38 个 kernel**（program 43）；`modify_roi_in` + `tiling_callback` 以 4σ halo 支持 ROI/tiling；sim（材料+求解）**纯参数决定**（`_ensure_sim` 键 = ~50 参数 ⊕ 工作空间矩阵 ⊕ pack 代数，**不含任何图像统计**）；"auto print exposure" = 固定参考中灰密度 f_mid 归一（`normalize_print_exposure`），**非场景直方图求解**。
2. **我方事实**：film **不是** module——它是 document 级 `FilmRecord` 单例 + 终端段（≥70.0 地板）内的 **固定点 sub-run**（`runTerminalTails`：film → DRT tail → display replay），`FilmMethodBox` 虽实现 `IOPModule` 协议，但 `iopOrder 74.0` 为尾段内部约定槽、**永不注册、永不入 sidecar、无 add face**；蒙版不可达；ROI 恒等（`modifyROIIn` 直通）；求解依赖**全图 256-bin 直方图**（`FilmSolveCache` 键 = materialPairHash ⊕ **statsHash** ⊕ modeTag）→ 这是"全图 sub-run / per-ROI 红线"的结构根因。
3. **历史裁决**：M3-2 `D-M3-2-1` 三案对比中**明确否决了"方案二：grade ops 化"**（理由：阶段语义藏在 op 序 / 材料对拆成多 op 参数 / "蒙版化胶片 = 物理上不存在，与 enlarger 全图物理不符"）。**本次用户令 = 翻转该裁决**，设计案须正面回答这三条否决理由（§4.0）。
4. **设计案判定（三问）**：① sidecar schema → **键面不动（零新键）、版本号不 bump**（module params 走既有 `ModuleInstance.paramsData` 通道；`filmRecord` 键保留只读兼容；旧档判别 = 内容判定「filmRecord 键在场 && 无 spektraFilm 实例」，OQ-4 推荐 (b)；bump v14 仅作备选）；② process version → **不 bump**（挂载位置与参数载体变化、视觉语义不变 = 不触发 M6-2「改观感 = 新 process 号」判据；但若同批改求解模型（统计→参数决定）则 **必须 bump v4**——两者分批）；③ filmPlacement 20.8 占位 → **保留原槽不动**（它是置位 op、非胶片本体，D-M3-2-1 "固定搭档"语义不变；module 化的是 FilmMethodBox 这一段，不是 filmPlacement）。
5. **最硬的两块骨头**：(a) 直方图求解 vs module 的 ROI/tile 语义互斥——要么保留"全帧统计预走"（dt 无此物），要么切到 dt 的参数决定归一（改观感 → bump v4）；(b) `pixelUm = 36000 / plane.width` 在 tile 下取到 tile 宽而非帧宽 → 所有空间效应 σ 失真，module 化必须改锚到 `piece.dscIn`（toneequal 先例）。
6. **推荐路线**：**两阶段**——P1「module 化不改核」（参数载体迁移 + 46.7 槽 + 蒙版/启停/历史标准化；求解仍全帧预走、`tileHalo` 返 0 + `allowTiling` 不设，视觉逐位恒等，process 不 bump）→ P2「核对齐 dt」（参数决定归一 + ROI halo + tiling；bump v4）。P1 即兑现用户令的 module 语义；P2 是性能/物理同构的后续。

---

## §1 dt module 解剖（spektrafilm 作为 iop 的完整接线）

### 1.1 注册链

| 项 | 事实 | file:line |
|---|---|---|
| 模块声明 | `DT_MODULE_INTROSPECTION(3, dt_iop_spektrafilm_params_t)` | `src/iop/spektrafilm.c:98` |
| iop order 槽位 | **46.7**，五张表全同（legacy/v30/v30_jpg/v50/v50_jpg） | `src/common/iop_order.c:150,268,391,515,641` |
| v50 邻居 | filmicrgb 46.0 → **spektrafilm 46.7** → lut3d 36.0（列表序）→ colisa 47.0 | `iop_order.c:638-642` |
| legacy 回落插入 | `_insert_before_after(iop_order_list, "colisa", "spektrafilm", TRUE)` | `iop_order.c:765` |
| flags | `IOP_FLAGS_SUPPORTS_BLENDING \| IOP_FLAGS_INCLUDE_IN_STYLES \| IOP_FLAGS_ALLOW_TILING` | `spektrafilm.c:790-793` |
| 多实例 | **允许**（未设 `IOP_FLAGS_ONE_INSTANCE`）；文档劝诫"enable INSTEAD of sigmoid/filmic/agx" | `spektrafilm.c:54-55` |
| 默认启用 | **off**（文件无 `default_enabled` / `reload_defaults`） | grep 零命中 |
| default_group | `IOP_GROUP_TONE \| IOP_GROUP_TECHNICAL`（与 filmic/sigmoid/agx 同组） | `spektrafilm.c:781-788` |
| default_colorspace | `IOP_CS_RGB` | `spektrafilm.c:925-930` |
| description 三元组 | 输入 "linear, RGB, scene-referred" → 输出 "non-linear, RGB, display-referred" | `spektrafilm.c:771-779` |
| CMake | `add_iop(spektrafilm "spektrafilm.c")` + `SPEKTRA_FP_CONTRACT_FLAGS` | `src/iop/CMakeLists.txt:101,105` |
| OpenCL program | `spektrafilm.cl 43` | `data/kernels/programs.conf:46` |

**语义位置**：46.7 落在 dt 的 **display-transform 层级**（basecurve 44 / filmic 45 / sigmoid 45.3 / agx 45.5 / filmicrgb 46.0 之后、display-referred 创意模块 colisa 47 … vignette 68 之前、colorout 70 / gamma 78 远前）。即 dt 把胶片当作**"scene→display 视图变换的一种"**，与 sigmoid/filmic/agx 互斥使用；其后的 47–69 段（tonecurve/levels/grain/vignette…）在 **display-referred** 域操作胶片输出。

### 1.2 params 结构与持久化

- `dt_iop_spektrafilm_params_t`（`spektrafilm.c:189-410`）共 76 字段：材料身份三元（`film_hash`/`lut_hash`/`paper_hash`，**内容哈希寻址**，非文件名——跨机器/跨目录可解析）+ 曝光族 + 印相族（`print_exposure_ev`/`print_auto_exposure`/`print_contrast`/`print_gamma_r|g|b`）+ 滤色（`filter_m`/`filter_y`）+ DIR coupler 六参 + preflash 三参 + scan 族 + halation/scatter 四参 + boost 三参 + diffusion 双臂八参 + grain 十参 + 格式（`film_format_mm` 长边毫米）+ 输出压缩/增益 + 显影 chemistry（gamma fast/slow/exhaustion/push-pull/development_min）+ 扫描锐化/glare + 适应两开关 + 黑白点四参 + 表/包身份（`upsampling_hash`/`pack_hash`）。
- 版本迁移：`legacy_params()`（`:877-922`）v1→v2→v3 前缀拷贝 + 值改写（如 v1 的 `grain_density_min` 0.03 → 1.0、`grain_blur_base` 固定 0.8、旧版 lut_hash 回填 `SF_FIRST_PUBLISHED_LUT_HASH`）——dt 的 params 版本迁移范本。
- 持久化：params 经 dt db（history/preset/style 全部存这份 struct 的字节）——`INCLUDE_IN_STYLES` 使其入 style；GUI 面板 5 tab / 163 控件（`gui_init` `:5641`，presets `init_presets` `:4649`）。

### 1.3 commit→process 数据流（CPU/GPU 分工）

- `init_pipe/cleanup_pipe`（`:1399-1428`）：per-piece data = params 快照 + 互斥锁 + `sf_sim_t*`（CPU 表）+ `sf_sim_gpu_t*`（GPU 常量表）+ grain cl_mem 组。
- `commit_params`（`:1430-1442`）：拷 params 入 piece；仅 preview pipe 记 `d->self`（状态回传 GUI 的单写者）；**sim 不在此建**——留到 process 内懒建（work profile 只有在 process 才可靠）。
- `_ensure_sim`（`:1502-…`）：缓存键 = FNV-1a 64 折 ~50 个参数字段 + 工作空间 RGB↔XYZ 矩阵（`:1571-1572`）+ `sf_fetch_generation()`（数据包安装代数，`:1578-1579`）。**键里没有任何图像像素/直方图项**。miss 时 `sf_sim_build`（材料曲线/ISO 适应/tc LUT 33³/相纸 morph 全烘焙）。
- CPU `process`（`:2158-…`）：`_ensure_sim` → `pixel_um = film_format_mm·1000/full_long_edge`（`:2185-2187`，**用 `piece->buf_in` 全帧尺寸 × roi scale**，非 tile 尺寸）→ 阶段序 expose → boost → diffusion → halation → lograw → coupler corr(高斯+三高斯尾混合) → develop → grain（多层粒子采样→差值回加→clump blur→乘法 USM）→ print_expose（dichroic 滤色 × 相纸感光 × **auto print exposure = 固定 f_mid 归一**，`:1794-1799`）→ print_develop → scan（黑白点/锐化/glare/gamut 压缩）。OpenMP 并行；`preview_scale = fminf(roi->scale, 1)` 缩放固定像素半径防预览过锐（`:2192`）。
- GPU `process_cl`（`:2655-…`）：38 kernel 分段流水（expose/lograw/develop_corr/develop → grain 五件 → print_expose/print_develop → scan/crop_out/scan_usm → glare 件 → halation/scatter 件 → boost/diffusion 件 → pow10/log10 + 通用 blur 族）。**grain cl_mem 按 (gpu 指针, devid) 双键缓存跨 tile 存活**（`:590-611` 注记：devid 属于 key——设备池每次 run 重派，跨设备 cl_mem 会段错误）。无 sim 时 `kernel_passthrough` 直通；无 GPU 表回落 CPU。
- 数据包：`static sf_pack_t *_pack` 进程级单例（`:629-647`），目录 `<userdata>/spektrafilm/` 或 `packs/<hash>/`，`init_global`/`cleanup_global` 生命周期管理（`:649-759`）——**与 dt 的"我方 SpectralPrintBake per-pair LRU"同题异解**：dt 是进程一份 + 编辑记录哈希身份；我方是 pair-hash 键控 LRU 16。

### 1.4 ROI/tiling

- `modify_roi_in`（`:2035-2064`）：`roi_in = roi_out` 外扩 `halo = ceil(4σ × _max_halo_sigma(params, pixel_um))`（halation first σ 65µm 封顶 + scatter 27µm 上界 clamp，`:103-114` 常量）——空间效应需要的全部读邻域。
- `tiling_callback`（`:2066-2121`）：`factor 6.5（CPU）/ 9.75（CL）`，`overlap` = 同一 halo，`overhead` = 常量表字节数（tc LUT 4×33³×3 + 2×32³×3，`scan_film` 减半）。注释明言：**低估会让 tiler 分出分配失败的 tile，CPU 路对失败 tile 回落 passthrough（画面里出现未处理矩形）——估计必须取上界**。
- process/process_cl 一律**先处理整个 roi_in 再裁 roi_out**（`:2166-2169`、`crop_out` kernel 同理）。

### 1.5 GUI 参数族与 auto-solve 钩子

- GUI：5 collapsible tab（材料/曝光/印相/效果/扫描），14 个 format 预设 combo（half-frame…IMAX）+ custom 毫米滑杆联动（`:505-570`）；pack 下载/更新行（fetch 状态轮询 `data_poll`，`:469-503`）；trouble 消息经 `_publish_status` → `dt_iop_set_module_trouble_message`（`:4556-4575`）——**sim 构建失败的错误/警告横幅走 dt 标准 trouble 通道**，仅 preview pipe 单写者。
- auto-solve（GUI 一次性，非每帧）：`color_picker_apply`（`:5410-…`）对 `output_boost`/`output_scale` 两控件做取色求解——临时 sim + 几何二分（boost，20 步 ~2e-6）或闭式（scale = (target/L1)³），**结果写入 params 即一次普通 history item**；目标亮度 0.97/0.995。真正的印相曝光归一是**引擎内固定 f_mid**（`sf_sim_params.print_exposure_compensation` 组合 `normalize_print_exposure`，`:1794-1799`）。

---

## §2 我方现状解剖（film sub-run 全链精确映射）

### 2.1 参数载体：document 级 FilmRecord

| 环节 | 事实 | file:line |
|---|---|---|
| 记录结构 | `FilmRecord` 14 字段：`filmStock/paperStock`（开放字符串 id，非哈希）/ `yFilterShift/mFilterShift` / `contentAdaptiveShift` / `strength` / `exposureEv` / `cameraFilter?` / `paperGrade?` / `reversalPrintMode?` / `grainAmount?` / `halationAmount?` / `diffusionFamily?` / `diffusionAmount?` | `LightamerCore/Sources/Graph/FilmRecord.swift:47-134` |
| 宽容解码 + 稳定哈希 | 逐字段 `decodeIfPresent`；`stableHash()` = FNV-1a over sortedKeys JSON（L013） | `FilmRecord.swift:172-209` |
| pristine 门 | `isFilmRecordDefault(_:)` = `r == FilmRecord()`（默认记录永不入 sidecar/载体） | `FilmRecord.swift:218-220` |
| 文档级设计根据 | "one enlarger × one negative × one paper per document — the document-level singleton judgment, M3-2 D-M3-2-1" | `FilmRecord.swift:9-13,30-34` |
| App 载体 | `WorkspaceModel.filmRecords: [String: FilmRecord]`（per-url；缺键 = pristine） | `App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift:328-345` |
| 写腿 | `EditorState.recordFilmChange(_:label:)` → `HistoryStack.commitFilm` 单 discrete item | `App/.../State/EditorState.swift:339`；`LightamerCore/Sources/Pipe/History/HistoryStack.swift:323-336` |
| history 形态 | `HistoryItem.filmRecord: FilmRecord?` + `layerScope = HistoryStack.filmDocumentScope ("__filmDocument__")`——**文档级 item，snapshot 槽为占位**，被 `effectiveInstances()` 等层面忽略 | `HistoryStack.swift:124,316-336,394` |
| 有效记录投影 | `HistoryStack.effectiveFilmRecord()` = 指针以下最后一个携 filmRecord 的 item | `HistoryStack.swift:557-559` |
| historyHash 折叠 | 末位 `filmRecord.stableHash()` 折入（drt 后） | `HistoryStack.swift:590-602` |
| sidecar | v9 起 `filmRecord: FilmRecord?` 文档键 + per-item 镜像；`schemaVersionCurrent = 13` | `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:193-207,252-269,387,565-566,656` |
| 载体↔history 同步 | `PipeCoordinator.syncFilmCarrierWithHistory()`（undo/redo/jump 后从 history 真相回写） | `App/.../State/PipeCoordinator.swift:1116` |

### 2.2 管线缝：终端段内的固定点 sub-run

| 环节 | 事实 | file:line |
|---|---|---|
| 层模型 | A 基链（iopOrder < 70）→ B 层子 run × N（含 blend/mask）→ C 终端段（≥70，`terminalTailFloor`） | `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift:70-78,110,115-123` |
| pipe 开关 | `PixelPipe.filmTail: FilmTailPolicy?`（nil = OFF 零路径，逐位 = pre-M3-3） | `LightamerCore/Sources/Pipe/PixelPipe.swift:179` |
| 降出谓词 | `isTerminalTailSkipped`：3×2 矩阵——`.sdrGamma`+film 降出 colorout/gamma/borders/watermark 四件；`.edrLinear`+film 降出 gamma+colorout；`.drt` 零改 | `PixelPipe.swift:326-370` |
| 共享序 | `runTerminalTails`：① film 腿 → ② DRT tail（upstream = film 输出 hash）→ ③ display replay（降出四件重放） | `PixelPipe.swift:1168-1215` |
| 调用点 | `run()` 与 `runSub()` 末尾各一处 | `PixelPipe.swift:926-931,1087` |
| film 腿 | `runFilmLeg`：① **全帧直方图**（`FilmStatsSeam.histogram(input, metal)`，材料已解析才跑）→ ② `assembleFilmLeg` → ③ 新建 `filmPipe`（`isFilmTailLeg = true`，继承 `renderProcess`）→ `runSub([FilmMethodBox])` → outputHash = chain(seed, methodParamsHash) | `PixelPipe.swift:1230-1280` |
| 工厂分叉 | `assembleFilmLeg` exhaustive switch：`.v1` → `assembleDensityFilmLeg`（冻结密度臂）；`.v2/.v3` → `assembleSpectralFilmLeg`（光谱臂；v3 复用 v2 film 臂） | `PixelPipe.swift:1301-1323,1328-1354,1373-…` |
| seed | `FilmTailAssembly.seed(upstream:params:solvedPackHash:renderProcess:)` = fnv(recordHash ⊕ policyTag(arm) ⊕ solvedPackHash ⊕ upstream)；tag `lightamer.film.subrun.v1` / `…v2-spectral`（「非 legacy 才折」） | `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift:89-164` |
| display replay 残留集 | `displayReplayResidents`：sdrGamma→[colorout,borders,watermark,gamma]；edrLinear→[colorout]；drt→[] | `FilmTailPolicy.swift:226-246` |
| processForkHash | 协议默认 nil；仅 ColorWheels v3 折——film 腿**不经此缝**（它不在主链 pieces 内） | `LightamerCore/Sources/Pipe/ModuleBox.swift:109-118`；`PixelPipe.swift:977-979` |

### 2.3 FilmMethodBox：实现了 IOPModule 却不是 module

| 项 | 事实 | file:line |
|---|---|---|
| 协议实现 | `public final class FilmMethodBox: IOPModule` | `FilmTailPolicy.swift:295` |
| opName / 槽 | `"filmMethod"` / `iopOrder = 74.0`（"tail-internal slot — the sole box of its own sub-run — the value is conventional"）/ `flags = []` / `.RGB` | `FilmTailPolicy.swift:321-328` |
| 注册 | **never registered, never in sidecars, no add face**（driver-constructed） | `FilmTailPolicy.swift:279-281` 注释；`LightamerIOP/Sources/Registry.swift` 无注册行 |
| V50Order | **无 filmMethod 行**；74.0 在表里是 dt 的 `rawoverexposed`——纯约定重合，不冲突（因 film 从不进主链排序） | `LightamerCore/Sources/Foundation/V50Order.swift:241` |
| Params | `{record: FilmRecord, magentaCC, yellowCC, exposureGain}`——**求解结果入 Params**，整体 ParamsCoding 编码进 paramsHash | `FilmTailPolicy.swift:301-319,371-374` |
| ROI | `modifyROIOut/In` 恒等直通；**无 `tileHalo` 覆盖**（协议默认 0 = 永不 tile） | `FilmTailPolicy.swift:376-382`；`LightamerCore/Sources/Pipe/IOPModule.swift:145-159` |
| 载体 | 运行期 payload 走**实例字段** `runPayloads` / `runSpectralPayloads` / `runScratch`（任务书所称 `runContext` 静态槽已在 fix(film-leg) 批**删除**——跨 run 共享态导致 over-release 崩溃，M5-1-03 ACCEPTANCE §7） | `FilmTailPolicy.swift:330-365,445-461` |
| process 分派 | 光谱 payload 在 → `dispatchFilmChain`；否则密度 payload → fused `film_subrun`；都无 → `blitIdentity` | `FilmTailPolicy.swift:384-423` |

### 2.4 FilmSolveCache 与「全图」根因

| 项 | 事实 | file:line |
|---|---|---|
| 统计缝 | `FilmStatsSeam.histogram`：256-bin × R/G/B/luma 全平面计数直方图；`statsHash` = FNV over counts；IOP 侧安装 `ScopeReduce.histogram` 并顺手留 `FilmStatsSnapshot.last` 给宽容度面板 | `FilmTailPolicy.swift:542-570`；`Registry.swift:88-93` |
| 缓存键 | `fnv(materialPairHash ⊕ statsHash ⊕ modeTag)`；modeTag 四值（密度/光谱 × 是否 contentAdaptive）；**"NO ROI/context term: one solve per run over the FULL top plane — the per-ROI red line is structural here"** | `FilmTailPolicy.swift:659-707` |
| 值 | `AutoSolution{neutralM/Y, autoGain, contentDeltaM/Y}`；记录项（手动 Y/M、exposureEv）消费期叠加**不入键** | `FilmTailPolicy.swift:594-604` |
| 曝光锚 | `percentileBin` 整数秩 P50（通道 3）= 曝光归一锚 | `FilmTailPolicy.swift:709-…` |
| LRU | NSLock + 插入序 LRU 8；`invalidateAll()` 供面板 Solve 按钮 | `FilmTailPolicy.swift:606-650` |
| 空间效应像素尺度 | `pixelUm(frameWidth:) = 36000 / width`——**以收到的 plane 宽度为帧宽**（全帧 sub-run 不变式下成立） | `LightamerCore/Sources/Pipe/Film/SpectralPayloads.swift:1280-1287,1337-1338` |
| corr 网格 | `SpectralGPUPayloads(frameWidth:frameHeight:decimation:4)` 由全帧尺寸推 corr 网格 | `SpectralPayloads.swift:327-438` |
| 不入 tile 不变式（文档） | "film box 不入 tile 不变式下 = 全帧一次 dispatch，padding 恒 0；若未来 film 腿入 tile，padding 纪律按上游 4σ（注记，不立项）" | `.work/gsd/phases/m8-3plus-spectral/RESEARCH.md:327-328` |

**「film 当前不是 module」的结构性原因（归纳）**：
1. **求解依赖全图统计**（P50 曝光锚 + content-adaptive 投影）→ 必须在"看得到整幅顶面"的位置运行 → 落在层合成之后的终端段，而非可被 tile/ROI 切割的主链槽；
2. **document 级单例语义**（D-M3-2-1：一台放大机一副底片一张相纸）→ 参数不走 `ModuleInstance`，而走 `filmRecord` 文档键 + `__filmDocument__` scope item；
3. **DRT 交接**：film 输出 hash 直接作 DRT tail 的 upstream seed（`DrtTailAssembly.seed` 签名零改）——它被设计成 DRT 的"前置尾段"，与 DRT 同属终端编排层；
4. **M2-4 节点图零改红线**：`NodeKind` 仍三 case（`PipelineDocument.swift:44-47`），Film 卡 = App 侧投影（`NodeCanvasGeometry.filmCardID` 编译期常量，`App/.../Nodes/NodeCanvasGeometry.swift:27-29,108-148`）。

---

## §3 差距映射表（dt module 形态 vs 我方 sub-run 形态，15 维度）

| # | 维度 | dt spektrafilm（module） | 我方 film（sub-run） | 差距性质 |
|---|---|---|---|---|
| D1 | 参数载体 | `dt_iop_spektrafilm_params_t` 76 字段，走标准 iop params（history/db/preset/style 同一字节） | `FilmRecord` 14 字段，document 级 `filmRecord` 键 + `__filmDocument__` scope item；求解结果另存 `FilmMethodBox.Params` | **结构**：非 ModuleInstance，与其它 op 不同轨 |
| D2 | 材料身份 | `film_hash/paper_hash/lut_hash/pack_hash` 内容哈希（uint32） | `filmStock/paperStock` 开放字符串 id + `materialPairHash`（FNV64，运行期） | 语义同构，编码不同；我方字符串 id 更可读、dt 哈希更抗重命名 |
| D3 | 启停语义 | 标准 module enable 开关（默认 off）；`enabled` 入 history | "启用 = 首次 commit 默认材料对"（`FilmPanelModel` enable entry，`App/.../FilmPanelModel.swift:382-409`）；禁用 = 回到 pristine 记录（无显式 enabled 位） | **结构**：缺独立 enabled 位——不能"保留参数但关掉" |
| D4 | 排序/槽位 | iop order 46.7，display-transform 层级；可与 47–69 段 display-referred 模块交错 | 终端段固定点（主链顶面之后、DRT 之前）；不可重排 | **结构**：我方位置 ≈ dt 的 ~69.95（acesccOut 之后、colorout 之前），**比 dt 晚一整段**（dt 的 colisa…vignette 在胶片之后作用于 display-referred 输出；我方同类 grade ops 在胶片之前作用于 scene-linear） |
| D5 | 多实例 | 允许（无 ONE_INSTANCE），但文档劝诫单用 | 单例（document 级） | 语义差；我方若 module 化应设 `.oneInstance` |
| D6 | 蒙版/混合 | `SUPPORTS_BLENDING` → dt blendop（drawn/parametric/raster mask + 混合模式 + opacity）per-module | **不可达**（终端段无层蒙版；`FilmMethodBox.flags = []`）；仅 `filmPlacement` 20.8 可蒙版 | **结构**：dt 形态的核心收益；我方层模型的蒙版在**层**（`AdjustmentLayer` opacity/blendMode/mask），非 per-module——module 化后 film 若入 grade 层即继承层蒙版 |
| D7 | ROI/tiling | `modify_roi_in` 4σ halo + `tiling_callback` factor 6.5/9.75 + overlap；`pixel_um` 由 `buf_in` 全帧尺寸推 | ROI 恒等直通；`tileHalo` 默认 0；**不入 tile 不变式**；`pixelUm = 36000/plane.width` | **结构+性能**：我方 100MP 全帧一次 dispatch（峰值内存由 `SpectralScratchAllocator` 串行复用压住）；dt 可分块 |
| D8 | 自动求解 | 参数决定（固定 f_mid 归一，`normalize_print_exposure`）；GUI 取色一次性求 boost/scale 写 params | **全帧直方图** P50 锚 + content-adaptive 投影，每 run 消费 `FilmSolveCache`（键含 statsHash） | **语义**：我方"曝光随画面自适应"是 dt 没有的能力，也是 tile 不可达的根因 |
| D9 | 缓存键 | per-piece `sim_key`（参数 ⊕ 工作空间矩阵 ⊕ pack 代数）；pipe cache 走 dt 标准 piece hash | film sub-run seed = recordHash ⊕ policyTag ⊕ **solvedPackHash** ⊕ upstream；box paramsHash 含求解值 | 同构于"参数全在 hash 里"，但我方多一个统计派生项 |
| D10 | 预设/样式 | `INCLUDE_IN_STYLES` + `init_presets`（`:4649`）db 预设 | `FilmRecord.PresetNames` **空枚举**（悬置，`FilmRecord.swift:112-117`）；无预设面 | 功能缺口（非结构） |
| D11 | 导出 | 普通 iop，导出 pipe 自然包含 | `ExportQueue.filmTail` per-job 载体 + `ExportRenderer.$jobFilmTail` TaskLocal 递缝（Contract 零 diff 约束下的三件套范式） | **结构**：module 化后此递缝**可退役**（params 随 history 自然进导出链） |
| D12 | 缩略图 | 普通 iop（dt 缩略图走 full pipe） | **恒 legacy**（`filmTailPolicy(for:)` 对 `.thumbnail` 恒 nil，`PipeCoordinator.swift:851-854`） | 政策差；module 化后需显式保留"缩略图跳过"（否则 grid 渲染成本暴涨） |
| D13 | MCP | dt 无 MCP；但 params 可经 lua/style 寻址 | MCP 工具集**无 film 面**（`App/.../MCP/Tools/` grep 零命中） | module 化后自动进入 `apply_params` 的 opName 寻址 |
| D14 | 错误回传 | `dt_iop_set_module_trouble_message` 标准 trouble 横幅（preview pipe 单写者） | 材料未解析 → `logger.error` + film 腿禁用 + 一次性 toast（`PipeCoordinator.swift:857-867`） | 同构（我方走 toast 通道） |
| D15 | 节点图 | dt 无节点图；module 在模块列表 | App 侧只读投影 Film 卡（`filmCardID`，非 `NodeKind`） | module 化后 Film 卡可转正为 grade 层内 op 行或保留为投影 |

**结论**：15 维中 **D1/D3/D4/D6/D7/D11 六项为结构差**（必须改架构）、D8 为**语义差**（是否保留直方图自适应是独立裁决）、其余为功能/政策差（module 化顺路或独立立项）。

---

## §4 module 化设计案

### 4.0 前提：本案翻转 D-M3-2-1，须正面回答三条否决理由

M3-2 `RESEARCH-NOTES.md:188-197`（方案二「grade ops 化」）+ `M3-2-CONTEXT.md:16-26`（被否形态）给出三条理由，逐条对应：

| 否决理由（M3-2） | dt 的回答（事实） | 本案的回答 |
|---|---|---|
| ① 阶段语义藏在 op 序里（用户可在胶片 op 之间插 grade 件） | dt 就是这样：46.7 固定槽，47–69 段模块在胶片**之后**作用于 display-referred 域，dt 视为正常创作自由 | 单 op（非三 op 拆分）→ 无"之间"可插；槽位固定 46.7 不可拖动（我方 V50Order 本就不允许重排）；47–69 段在我方默认面几乎为空（colisa/tonecurve/levels/shadhi 注册但属 .grade 默认 face；dt 的 grain/vignette/bloom 在我方走 `.drtPost`）→ 实际交错面很小 |
| ② 材料对拆成多 op 参数，sidecar 无单一 record | dt 是**一个** struct 含 film_hash+paper_hash | 一个 `SpektraFilmModule.Params` 含 FilmRecord 全部 14 字段（+ enabled 位由 ModuleInstance 承载）→ 单一 record 保持 |
| ③ 蒙版化胶片 = 物理不存在，与 enlarger 全图物理不符 | dt `SUPPORTS_BLENDING`——蒙版胶片是 dt 的**正常功能**（局部胶片感/双曝叠加/渐变过渡） | 接受为创作工具（用户令即此意）；物理忠实性由"默认无蒙版 = 全图"保证；文档措辞「局部应用为创作扩展，非物理模拟」 |

### 4.1 槽位提案：V50Order 新增 `("spektraFilm", 46.7)`

- **与 dt 同值 46.7**（verbatim-port 纪律：dt 已有此行，我方表是 dt 表的 verbatim 移植 + add-only 原生行——加 dt 行比造原生槽更合规）。插在 `filmicrgb 46.0` 之后、`lut3d 36.0`（列表序）之前，与 `V50Order.swift:171-174` 的列表序一致。
- **filmPlacement 20.8 处置 = 保留原槽、零改动**。理由：它是 RFC-023 **场景置位**曲线（scene-referred 曝光域 op，D-M3-2-1 的"固定搭档"），不是胶片本体；dt 没有对应物（dt 用 `exposure_ev` 一个标量代替置位）。"真挂载 vs 恒等占位"的关系：20.8 当前是"可加不可编"的恒等占位（`NodeOwnershipCatalog.swift:256-266`，panelExposures 指向 M3-4 FSIM-02 面板）——它的转正（面板激活）与本案正交，不随 module 化合并。**勿把 filmMethod 塞进 20.8**：20.8 在 ACEScc 包夹域内（acesccIn 20.5 … acesccOut 69.9），胶片核要求 scene-linear 输入。
- **域问题（关键）**：46.7 同样落在 ACEScc 包夹区间 [20.5, 69.9]。若 spektraFilm 入 `GradeCatalog`（owner .grade）则层子 run 被 `ACESccEnvelope.wrap` 包夹（`LightamerIOP/Sources/ACEScc/ACESccInModule.swift:126-133`：含 ≥1 目录 op 即包夹）→ 胶片收到 **ACEScc log** 而非 linear。三选一：
  - (a) **op 自带域转换**：process 内 ACEScc→linear→胶片→linear→ACEScc（两次 1D 变换，成本可忽略；dt `default_colorspace` 精神的我方变体）；
  - (b) **不入 GradeCatalog**（owner 新档 `.filmSim` 或 .develop）→ 不触发包夹，但也**不能加进 grade 层** → 失去层蒙版 → 违背用户令核心收益；
  - (c) 包夹谓词排除法：`needsEnvelope` 仅看"目录 op"，spektraFilm 入目录但标 `skipsEnvelope`——envelope 仍会对**同层其它 grade op** 包夹，spektraFilm 夹在中间仍收 log。**不可行**。
  - **推荐 (a)**：唯一既保蒙版又保域正确的形态；实现 = 在 `SpektraFilmModule.process` 前后各调一次 ACEScc 正/逆变换 kernel（`ACESccInModule`/`OutModule` 的 kernel 可复用，零新 kernel 红线下走既有 PSO）。注：若层内**只有** spektraFilm 一个目录 op，包夹仍发生（谓词是 ≥1）——(a) 对此情形同样正确，只是多两次无用变换；可加谓词"层内目录 op 全为 skipsEnvelope 则不包夹"作优化（额外改 `needsEnvelope`，属 GradeCatalog 封存面例外）。

### 4.2 参数迁移：FilmRecord → module instance params

- 新 `SpektraFilmModule: IOPModule`（`LightamerIOP/Sources/SpektraFilm/`），`Params` = `FilmRecord` **原样嵌入**（`public var record: FilmRecord`）+ 零新字段（求解值 M/Y/gain **不入 Params**——它们是运行期派生，走 piece.data/seed 折叠，见 4.4）。`opName = "spektraFilm"`，`iopOrder = 46.7`，`flags = [.supportsBlending, .oneInstance]`（P1 **不设** `.allowTiling`），`defaultColorspace = .RGB`。
- history：标准 `ModuleInstance(module: SpektraFilmModule.self, params:)` + `HistoryItem.snapshot`，`layerScope = 所在 grade 层 UUID`（或 nil = 基链）。**`HistoryItem.filmRecord` / `filmDocumentScope` 保留只读**（旧档解码）；新写入不再产生 `__filmDocument__` item。
- `FilmRecord` 类型**保留**（Core Graph），仅去掉"document 级"职责注释；`WorkspaceModel.filmRecords` 载体退役（由 `effectiveInstances()` 的 spektraFilm 实例替代）；`PipeCoordinator.filmTailPolicy(for:)` 退役（film 不再是 tail policy）。
- Alcedo 节点图：spektraFilm 作为 grade 层内 op 出现在该层的 op 行；`NodeCanvasGeometry.filmCardID` 投影卡**退役**（或保留为"跳到含 spektraFilm 的层"导航糖——OQ-5）。`NodeKind` 三 case **零新增**（M2-4 红线守住：module 化恰好不需要新 NodeKind）。

### 4.3 蒙版能力解锁面

- 入 grade 层 → 自动继承 `AdjustmentLayer` 的 opacity / blendMode / mask（`LayerCompositeDriver` B 段 degenerate blend，`:74-76`）——**零新 mask 代码**。这正是 dt 形态的核心收益（D6）。
- 限制：我方蒙版粒度 = **层**，非 per-module；同层内 spektraFilm 与其它 grade op 共享一张蒙版。若用户要"只蒙版胶片"→ 单独开一层只放 spektraFilm（Alcedo 工作流本就如此）。
- `supportsBlending` 在我方 IOPFlags 已存在（`LightamerCore/Sources/Pipe/IOPFlags.swift:18`）；层级 blend 不读该 flag（层对所有 op 生效），flag 仅作语义标注。

### 4.4 FilmSolveCache 键控：P1 不变

- P1 保留直方图求解：module 的 `process` 内，对**收到的 input 平面**跑 `FilmStatsSeam.histogram` → `FilmRuntimeSolve.solve/solveSpectral`（键 = materialPairHash ⊕ statsHash ⊕ modeTag，**零改**）。差别：统计对象从"主链顶面"变为"该层子 run 在 46.7 位置的输入"——层内 46.7 之前的 grade ops（exposure/contrast/…）输出。**观感差异**：原先胶片看到的是所有层合成后的顶面；现在看到的是本层 46.7 处的平面——对"单层、胶片在最上层"的典型档**逐位等价**（层只有一个且 op 全在 46.7 前）；多层档会漂移（§6 R3）。
- piece.data 承载求解值 + payloads（dt `piece->data` 同构，`commitParams` 写 paramsHash；`process` 首次懒建 payload——dt `_ensure_sim` 在 process 内懒建的同款理由：统计只有在 process 才可得）。
- seed/缓存：box paramsHash = `hash(Params)`（不含求解值）→ 平面 key 不含 statsHash → **同参数不同上游统计会命中陈旧平面**。解法：`processForkHash` 式**额外折叠项**——`ModuleBoxing.processForkHash` 是 per-box 可选折叠缝（`ModuleBox.swift:109-118`），但它按 renderProcess 折而非按统计；需新增一个 `runtimeFoldHash(piece:)` 可选缝或把 solvedPackHash 写进 piece 后由 `prepareChain` 折入 levelHash（`PixelPipe.swift:974-979` 旁加一行）。**这是 PixelPipe 封存面的一处例外，须逐 hunk 申报**。

### 4.5 sidecar schema：键面不动、版本号不 bump（判定 + 理由；bump v14 为备选）

- **判定：键面不动，不 bump**。module instance params 已有持久化通道（`ModuleInstance.paramsData` 入 history/sidecar 现行 schema）——**不需要新键**，但需要 schemaVersion bump 吗?逐项看:①现有 v13 读 v14 文档（含 spektraFilm 实例）→ `ModuleInstance` 解码成功、opName 未知模块走 `degradedForUnknownOps`（enabled=false + 一次性 toast，`Registry.swift:30-38`）——**前向兼容已天然成立**；②唯一缺口是"旧版 App 打开新档"场景，schemaVersion 是唯一的升级信号。**判定细化：不加新键则 schema 不必 bump**——现行 `schemaVersionCurrent = 13` 的语义是"writer 版本"（writer 写 13 = 它认识 13 的全部键），新 writer 写 14 仅当引入了**新键或新形态**。spektraFilm 走既有 ModuleInstance 通道 → **不 bump 亦可**；但 4.4 的 paramsHash 语义变化（film 参数从 `filmRecord` 键迁到实例）曾考虑**bump v14** 以便迁移器识别"v13 = 有 filmRecord 键待转换"——但内容判定（`filmRecord` 键在场 && 无 spektraFilm 实例）已充分且可机检，版本号 bump 只会引入"旧 writer 拒读"的误伤面。**最终判定：零新键、不 bump（OQ-4 推荐 (b)）**；bump v14 作备选，仅当 orchestrator 裁定需要显式"旧 writer 拒读"信号时启用（迁移语义见 §5）。
- `filmRecord` 键保留只读兼容（v13 档原样解码；v14 writer 不再产出该键）。`FilmSidecarTests` 的 v9..v13 负测面全部保留。

### 4.6 process version：不 bump（判定+理由）

- **判定：P1 不 bump**。M6-2 判据 = "改观感 = 新 process 号"。P1 的典型档（单层胶片置顶）逐位恒等；多层档存在漂移（§4.4/§6 R3）——若接受"多层档升级即重渲"（迁移提示承担）则不 bump；若不接受则同批 bump。
- **P2（核对齐 dt：参数决定归一）= 改观感 → 必须新增 case `.v4` 并 bump**（fork 点 = `assembleFilmLeg` exhaustive switch 加臂 + film seed policyTag 加 `lightamer.film.subrun.v4-parametric` 或干脆改走主链无 sub-run——见 4.8）。
- **分批纪律**：P1 与 P2 严禁同批——两个"观感变化源"混在一个 process 代际里无法做双臂 golden 对照。

### 4.7 DRT 尾段交互：film 从共享序退出

- module 化后 `runTerminalTails` 的 ① film 腿**整段退役**：`PixelPipe.filmTail`、`runFilmLeg`、`runFilmDisplayReplayLeg`、`FilmTailAssembly.displayReplayResidents`、`isTerminalTailSkipped` 的 film 分支全部成为死路径 → 按封存面清单走**退役而非删除**（保留 `.v1` 文档的回放腿，见 §5）。
- DRT 交接面改动：`DrtTailAssembly.seed(upstream:)` 的 upstream 回到主链顶面 hash（`levelHash[top]` 原语义，`PixelPipe.swift:926` 调用点换回 `decodeParamsHash`/顶面值——注意现在顶面 = acesccOut 之后含 spektraFilm 的平面）。
- `.drt` 行为：原先 film→DRT 交接 = 数源替换；现在 film 在主链内、DRT tail 原样接主链顶面——**交接语义不变，实现变简**。
- `isTerminalTailSkipped` 的 `.sdrGamma/.edrLinear` film 分支消失（降出逻辑只剩既有 08-4/M2-6 形态）。
- **FilmSubRunKernels 的 fused kernel 与 `film_subrun` 密度臂**：P1 里 kernel/装配字节零改（只有宿主位置变）；`FilmLegAssembly`/`SpectralPrintBake.tables`/`FilmPrintBake.Cache` 原样复用——宿主从 `PixelPipe.runFilmLeg` 移到 `SpektraFilmModule.process`（或 module 调 `PixelPipe.assembleFilmLeg` static 工厂，传自己的 piece 上下文）。

### 4.8 导出腿 / 缩略图 / MCP / Film 面板 / 节点 Film 卡改动面

| 面 | 现状 | 改动 |
|---|---|---|
| 导出 | `ExportQueue.filmTail` per-job 载体 + `$jobFilmTail`/`$jobDrtTail` TaskLocal（`LightamerCore/Sources/Export/ExportQueue.swift:117,266-319,503`；`ExportRenderer.swift:125,183,447,549-561`） | filmTail 载体退役；导出 pipe 含 spektraFilm 实例 = 自然包含。`ExportFilmChainTests` 改造为"导出含 46.7 实例"断言。`ExportQueueContract` 封存面：删 `filmTails` 参数 = 例外申报 |
| 缩略图 | `filmTailPolicy(for:)` 对 `.thumbnail` 恒 nil（KD-4 门） | 保留同语义：`SessionThumbnailRenderer` 豁免面对 spektraFilm 生效（AGENTS M9-4「穿线」豁免两件先例）——**缩略图管线剥掉该实例**（thumbnail run 显式 disable opName==spektraFilm），或在 `RenderProcess` 穿线缝沿用 M8-3 guard 形态。政策面同 D12 |
| MCP | 无 film 面 | 自动获 `apply_params` opName 寻址（`spektraFilm`）；`requiresControl`/turn-taking 面 M7-5 已覆盖所有 op |
| Film 面板 | `FilmPanelModel`（三级读 live→history→carrier；D-H1 三件套走 `beginFilmEdit/setFilmLive/commitFilmEdit`，`PipeCoordinator.swift:835-842,520-556`） | 读级改为标准 module 面板形态（live 实例 params → history 投影 → carrier）；`commitFilm` → 标准 `recordChange`；Solve 按钮 `FilmSolveCache.shared.invalidateAll()` 保留（`FilmPanelModel.swift:379`）。面板 View 主体可保留，仅数据源换 |
| 节点 Film 卡 | `NodeCanvasGeometry.filmCardID` 投影（M2-4 零 NodeKind 红线） | 退役或转导航糖（OQ-5） |
| 迁移 UX | `EditorState+FilmMigration`（film ∥ colorWheels 二源 gate + `history_process_migrate` marker） | P1 若不 bump process：迁移 UX 不触发；多层档漂移提示走 §5 的 sidecar 迁移提示面。P2 bump v4：复用同款 marker 机制加 `panel_process_migrate_*` 行 |
| zh 键族 | `film_*` 面板族 15 键 + `history_film_*` 4 键在册 | 零新增（复用）；若启用 preset 面另议 |

---

## §5 迁移与兼容

### 5.1 既有 `.lra`（filmRecord 键）档的迁移策略

三条路线，推荐 **B**：

| 路线 | 做法 | 优 | 劣 |
|---|---|---|---|
| A 读时静默转换 | sidecar 解码遇 `filmRecord` 非默认 → 合成一个 `ModuleInstance(spektraFilm, params: record)` 挂到"最上层 grade 层"（无层则新建）；history 末尾追加合成 item | 用户无感 | 改写历史 = 违反「带日期历史行不可改写」精神；多层档落点（挂哪一层）无唯一答案；undo 栈语义污染 |
| **B 双轨读 + 显式迁移** | 旧档继续按 **v1 回放腿**（保留 `runTerminalTails` film 分支作 legacy 臂，由 `RenderProcess`/schema 判别走旧腿）；面板出「Convert to Film module」行（复用 `ProcessMigrationRow` 泛化形态，`EditorState+FilmMigration` 二源 gate 加第三源 "has legacy filmRecord"）→ 用户点确认 = 一次 discrete commit：合成实例 + 清空 filmRecord 载体 + sidecar 升 v14 | 零静默改写；旧档逐位恒等直到用户确认；与 M8-3/M9-4 迁移 UX 同形 | 保留两套渲染腿（legacy sub-run + module）直到 deprecation 窗口结束 |
| C 强制一次性迁移 | 打开即转换 + 写回 | 代码面最小 | 违反「原文件永不改」精神（sidecar 自动重写）；回退无门 |

**B 的判别缝**：`sidecar.filmRecord != nil && !hasInstance(spektraFilm)` = legacy 档 → `PixelPipe.filmTail` 仍由 `filmTailPolicy(for:)` 供给（该函数退役推迟到 deprecation 后）；已迁移档 → filmTail 恒 nil。双条件互斥由 `WorkspaceModel` 一处判定。

### 5.2 filmPlacement 20.8 占位：零改动（既非退役也非转正）

- 20.8 是置位 op，不是胶片本体；其"可加不可编"状态由 M3-4 FSIM-02 面板激活决定，与本案正交。module 化**不碰** `FilmPlacementModule`/`FilmPlacementKernels.metal`/GradeCatalog 第 19 行。
- 若将来要"胶片一键 = 置位 + 胶片"组合，走 preset（两 op 同时写入）而非合并 op。

### 5.3 feature flag / 回退面

- **进程级开关**：`LIGHTAMER_FILM_MODULE=1`（env，KD-3 `LIGHTAMER_FULL_IOP_FACE` 同款读法：`Registry.populate` 条件注册 spektraFilm + `filmTailPolicy(for:)` 对已迁移档恒 nil）。默认 **off** 直到 GUI 走查 + 双臂 golden 全绿，然后翻默认。
- 回退 = 关 flag：未迁移档本就走 legacy 腿；已迁移档的 spektraFilm 实例在无注册时走 `degradedForUnknownOps`（enabled=false + toast）→ 画面退回无胶片——**非逐位回退**；要逐位回退需保留迁移前 sidecar 备份（`SidecarStore` 的 `pre-migrate.N-M.bak` 轮换先例，M2-8）。
- 注册面变化属 `Registry.swift` 非封存面；`defaultFaceDisabledOpNames` 不动。

---

## §6 风险清单

### 6.1 封存面 17 件：会破哪些（例外申报形态）

| 封存件 | P1 是否触碰 | 申报形态 |
|---|---|---|
| **PixelPipe** | **是** | ① `prepareChain` levelHash 加运行期折叠项（4.4）；② `runTerminalTails` film 分支改为 legacy 判别门；③ `run()`:926 调用点 upstream 语义恢复。逐 hunk 申报（M9-4 `processForkHash` 先例） |
| **V50Order** | **是（add-only）** | 新增 `("spektraFilm", 46.7)` 一行，dt 同值——add-only 纪律内，须申报"dt-verbatim 行补录"而非原生行 |
| **GradeCatalog（NodeOwnershipCatalog）** | **是** | 新增第 21 行 spektraFilm（owner .grade，identityJSON = `FilmRecord()`，panelExposures = 面板键）；E7 完备性断言随之更新；若走 4.1(a) 优化则 `needsEnvelope` 谓词加 skipsEnvelope 判定 |
| **ExportQueueContract** | **是** | `filmTails:` 参数退役（或保留为 legacy 档通道直至 deprecation）—— M2-9 Contract 零 diff 约束下走 TaskLocal 递缝的原因消失 |
| **HistoryStack** | 否（P1） | `commitFilm`/`filmDocumentScope` 保留只读；新写走既有 `recordChange` |
| **HistoryHash** | 否 | filmRecord 尾位折叠保留（legacy 档）；module 实例自然入 paramsHash 链 |
| **sidecar schema（LightamerSidecar）** | **是（版本号）** | `schemaVersionCurrent 13→14`，零新键；doc comment 加 v14 节 |
| DrtRecord / TerminalTailPolicy / DrtTailAssembly / DrtEotf | 否 | 零 diff（DRT 交接只换 upstream 值，签名不动） |
| Lut3dKernels.metal | 否 | 零 diff |
| 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder） | 否 | 零 diff |
| NodeGraphCommand / PipelineDocument | 否 | `NodeKind` 三 case 零新增 |
| Registry（非封存面） | 是 | 注册行 + flag 门 |

**计 5 件触碰**（PixelPipe / V50Order / GradeCatalog / ExportQueueContract / sidecar schema），其中 V50Order 与 schema 为 add-only/版本号级，PixelPipe 为实质改动。

### 6.2 双臂 golden 冻结面

- `SpectralDualArmGoldenTests` / `SpectralCrossArmGoldenTests` / `FilmGoldenTests` / `BWSpectralGoldenTests` 等 47 个 film/spectral 测试文件（`Tests/LightamerTests/` ls 计数）——**kernel 字节零改**下 golden 本身不动；但**宿主路径变**（sub-run → module process）→ 需新增"同输入经两宿主逐位相等"的桥接测试（P1 验收主门），并把现有 `FilmLegTests`/`FilmCoordinatorTests`/`ExportFilmChainTests` 改成双形态参数化。
- `.v1` 密度臂冻结（`assembleDensityFilmLeg` "nothing may change without a new process generation"）：P1 不改该函数体，module 调同一 static 工厂 → 冻结维持。
- 在飞 lane 正在改 `SpectralBuildEngine`/`FilmProfile`/`PaperGradeTable` 与 10 个 golden 测试（@工作区在制）——本案 plan 期须以其 commit 后字节为基线，**不可与其并行动 Film/**。

### 6.3 性能面：ROI/tile 语义 vs 全图 sub-run

| 项 | 风险 | 缓解 |
|---|---|---|
| R1 pixelUm 锚 | `pixelUm = 36000/plane.width` 在 tile 下取 tile 宽 → σ 全错（预览缩放时 dt 用 `buf_in × roi->scale` 全帧值） | P1 `tileHalo` 返 0 + 不设 `.allowTiling` → 永不 tile，plane = 层子 run 全平面 → 锚仍正确；P2 改锚 `piece.dscIn`（toneequal 先例，`IOPModule.swift:150-153`） |
| R2 corr 网格/scratch 全帧 | `SpectralGPUPayloads(frameWidth:frameHeight:)` 与 `SpectralScratchAllocator` 按全帧分配 | 同上，P1 不 tile 则零变化；P2 需 per-tile 重建 corr 网格（dt 的 grain cl_mem 跨 tile 缓存先例，`spektrafilm.c:590-611`） |
| R3 多层档统计漂移 | 统计对象从全合成顶面变为本层 46.7 输入 → 含多层/胶片非置顶层的档观感变 | 迁移提示 + 默认把合成实例挂**最上层**；或 P1 保留"统计取主链顶面"的旁路（需 pipe 回传顶面 — 破 module 自洽，不推荐） |
| R4 100MP 内存峰 | 全帧 sub-run 今已 8G 门内（IOP 7.6-8.1G）；module 化后层子 run 内多一次全帧 film 链 + 层 blend 平面 | 同量级（film 链本就全帧）；若层数 >1 则每含 spektraFilm 的层各跑一次 → 建议 `.oneInstance` + 面板提示"单层" |
| R5 层内重复求解 | 每次层子 run 重跑直方图（`ScopeReduce`）+ 缓存查询 | `FilmSolveCache` 命中则零成本；直方图一次 reduce ~ms 级（M3-3-02 已有度量） |
| R6 ACEScc 往返 | 4.1(a) 两次 1D 变换 | 逐像素 2 次 log/pow，≪ 胶片链本体 |

---

## §7 Open Questions（呈 orchestrator/用户裁决，每条带推荐）

| # | 问题 | 选项 | 推荐 |
|---|---|---|---|
| OQ-1 | **多实例**：module 化后允不允许两个胶片层（两个不同胶片对）？ | (a) `.oneInstance` 单实例（dt 文档"INSTEAD of sigmoid/filmic/agx"精神 + 避免双放大机物理失真，即 M3-2 否决理由③的残留面）；(b) 多实例（dt flags 允许，创作自由最大化） | **(a)**。首版单实例：把"多层胶片"的解留给多档/合并导出；若用户真需求再撤 flag（成本低） |
| OQ-2 | **统计求解去留**（dt 同构 vs 我方独有能力）：P2 是否把 P50 直方图归一切换为 dt 的固定 f_mid 参数决定归一？ | (a) 保留直方图（module 化但求解仍全帧预走 = P1 终态；ROI/tile 永不可用）；(b) 切 dt 形态（params-determined；tile/halo 可用；**观感变化 → bump v4**；"自适应曝光"能力消失，用户档观感变） | **(a) 保留**。我方 P50 自适应是实测优于 dt 固定锚的差异化能力（M3-2 §4.2 裁决链）；tile 化的内存收益在 100MP+ 层子 run 场景尚无实证痛点。P2 挂账，不立项 |
| OQ-3 | **槽位域**：spektraFilm 入 GradeCatalog（owner .grade + ACEScc 往返 4.1(a)）还是走 owner 新档不入目录（放弃层蒙版）？ | (a) 入目录 + process 内 ACEScc 往返；(b) 不入目录（.develop 档，仅基链，无蒙版）；(c) 入目录 + envelope 谓词特化 | **(a)**。蒙版是用户令核心收益；(c) 的谓词改动同时影响所有目录 op，封存面代价更大；(b) 等于不做 module |
| OQ-4 | **sidecar v14 bump**：是否为迁移提示引入版本号（零新键）？ | (a) bump v14（迁移器识别 + 「Convert to Film module」行 gate）；(b) 不 bump，迁移判定 = `filmRecord 键在场 && 无 spektraFilm 实例`（纯内容判定） | **(b)**。内容判定已充分（双条件互斥可机检）；bump 无新键 = 只引入"旧 writer 拒读"的误伤面（schema 版本的文档语义本就是键面而非逻辑面）。若 §5.1-B 走 ProcessMigrationRow 泛化，gate 用内容判定即可 |
| OQ-5 | **节点 Film 卡**：退役还是保留为导航糖？ | (a) 退役（投影卡、`filmCardID` 常量、`includesFilmCard` 布局全撤；spektraFilm 出现在所在 grade 层的 op 行）；(b) 保留卡 = 点击跳转到含胶片的层 | **(a) P1 退役**。卡的非模块本质正是要消除的"两轨"观感；(b) 是可选后续糖。注意 `FilmCardTests` 退役面与 `editor_node_film*` 3 键处理 |
| OQ-6 | **在飞 lane 基线**：m8-3plus 执行 lane 正在改 Film/ 四件 + 10 golden 测试，本案 plan 期基线怎么定？ | (a) 等其 commit 后以 HEAD 为基线（串行）；(b) 以当前在制 diff 为基线并行 | **(a) 串行**。plan 批最早也在其收口后启动；AGENTS 机器级单重活 + 「不可与其并行动 Film/」双约束 |

---

## 验收自查

- [x] dt 侧解剖含注册链事实（槽位 46.7 / flags 三件 / kernel 数 38）与 CPU/OpenCL 分工，file:line 可核（§1.1/§1.3）
- [x] 我方侧解剖含 FilmMethodBox（`FilmTailPolicy.swift:295-462`）/ runTerminalTails（`PixelPipe.swift:1168-1215`）/ filmTailPolicy（`PipeCoordinator.swift:851-871`）/ FilmSolveCache（`FilmTailPolicy.swift:576-650`）精确 file:line（§2.2-2.4）
- [x] 差距映射表 ≥8 维度（§3，15 维，其中 6 结构差）
- [x] 设计案明确回答三问：sidecar schema = **键面不动（零新键）、版本号不 bump，旧档走内容判定**（§0.4 / §4.5 / OQ-4 三处同向，bump v14 仅作备选）；process version = P1 不 bump / P2 必 bump（§4.6）；filmPlacement 占位 = 零改动保留（§4.1 / §5.2）
- [x] Open Questions ≤6 带推荐（§7，6 条）
- [x] 全程只读零 commit；产出单文件本路径（chunked 写：7 段追加，各 4.8-8.6KB）

**minor-1**：chunk 3 实际 8.6KB 超出 8KB 段限 7.5%（写入无截断，全文复核完整；其余 7 段均 ≤8KB）。

## Sources

- dt 仓（只读）：`src/iop/spektrafilm.c`（6509 行）/ `src/common/spektra_sim.c`（5405）/ `spektra_core.c`（1189）/ `spektra_fetch.{c,h}` / `data/kernels/spektrafilm.cl`（38 kernel）/ `data/kernels/programs.conf:46` / `src/common/iop_order.c:150,268,391,515,641,765` / `src/iop/CMakeLists.txt:101`
- 我方仓（HEAD + 在制注记）：`LightamerCore/Sources/{Graph/FilmRecord.swift, Graph/DrtRecord.swift, Pipe/PixelPipe.swift, Pipe/Film/*, Pipe/History/*, Pipe/LayerCompositeDriver.swift, Pipe/IOPModule.swift, Pipe/IOPFlags.swift, Pipe/ModuleBox.swift, Pipe/RenderProcess.swift, Foundation/V50Order.swift, Sidecar/LightamerSidecar.swift}`；`LightamerIOP/Sources/{Registry.swift, NodeOwnershipCatalog.swift, FilmPlacement/*, ACEScc/ACESccInModule.swift}`；`App/Sources/Lightamer/{State/PipeCoordinator.swift, State/EditorState.swift, UI/Shell/WorkspaceModel.swift, UI/Shell/FilmPanelModel.swift, UI/Shell/Nodes/NodeCanvasGeometry.swift, Export/ExportInspectorView.swift, EditorState+FilmMigration.swift}`；`LightamerCore/Sources/Export/{ExportQueue.swift, ExportRenderer.swift}`
- 调研正本：`.work/gsd/phases/m3-2-fsim-research/{RESEARCH-NOTES.md, M3-2-CONTEXT.md, DT-SPEKTRAFILM-IMPORT-RESEARCH.md, M3-2-ACCEPTANCE-OMP*.md}`；`.work/gsd/phases/m8-fsim-spectral/M8-2-DECISIONS.md`；`.work/gsd/phases/m8-3plus-spectral/{RESEARCH.md, M8-3+-DECISIONS.md}`；AGENTS.md「M3-3/M8/M9-4 架构增量」节
