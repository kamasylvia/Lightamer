# LENS-01 Research — Lensfun 镜头校正落地

> status: research-in-review | date: 2026-10-20 | charter: `.work/gsd/research/UPSTREAM-QUEUE.md:44`（UQ-R4 拉正，commit `8bd94370`）
> 前置: Phase 04-04（IOP-GEO-03，plan 正本 `.work/gsd/phases/04-geometry-lens-detail-iops/04-04-PLAN.md`）
> 验收锚: FEAT-DEV-07 = Alcedo 同款 **enable + scale + projection + profile database + auto-detection**（UPSTREAM-QUEUE.md:44）
> 方法: 纯只读文本侦察（机器级单重活制度——二路验收在飞，未起构建/测试/GUI）

## Summary

**核心发现：Lensfun「数据只读路线」（路线 A）的主体已在 Phase 04-04 建成并在产线运行**——XML 解析（`LensfunDB`）、EXIF 匹配 + lensfun 插值语义全移植（`LensfunMatch`：crop gate 0.96 / Hermite 焦距样条 / IDW p=3.5 渐晕 / d-factor + hugin 重标 / NS·HW 归一折算）、统一 Metal warp kernel（`lens_manual_warp`）、下载服务、面板、注册/路由、parity 测试全部在位。**LENS-01 不是从零集成，是「收口落地」**：把 (c) 层从「手动 Apply + 面板按钮下载」推进到 Alcedo 验收锚的完整形态。

缺口清单（对验收锚逐项）：

| 验收锚 | 现状 | 缺口 |
|---|---|---|
| profile database | 下载式（master.zip 不钉版）、面板按钮触发 | 数据分发硬化（钉版快照 + 归属）|
| auto-detection | **无自动**——默认 `.off`，用户手点 Apply；面板匹配状态是 stub（回显 EXIF 串非真匹配）| 真自动匹配 + 匹配预览 + miss 台账 |
| enable | 无独立开关（source 三态兼职）| enable 语义 + per-correction 分开关 |
| scale | 无 | auto/user scale（Alcedo `resolved_scale` 形）|
| projection | 无（rectilinear-only，非 rectilinear 条目直接拒绝）| 投影变换（Alcedo 8 型）|
| 双重校正互斥 | 静态文案警告 + 默认 off | 探测 + 状态机 + 显式覆盖语义 |

**路线推荐：A（数据只读，现路线收口）**，定向吸收 GPL 上游件（Alcedo 投影 GPU 参数结构 / RawLab auto-crop 二分与状态机）。理由与矩阵见下。

## Baseline — 04-04 遗产盘点（全部在产线）

- `LightamerIOP/Sources/Lens/LensModule.swift` — IOP 模块：v50 槽 13.0（`:151`）、flags `[.allowTiling, .oneInstance, .allowFastPipe]`（`:155`）、默认 `.off` 中性（`:172-178`，anti-double-correction 已固化为默认）、ROI 前向边框 AABB + 2px（`modifyROIIn :261-291`，dt `_modify_roi_in_lf` 同构无 Newton 反解）、中性/解析失败 → blit 恒等（`:357-369`）。已登记 v1 偏离（`:57-74`）：**无 projection/scale/reverse/ACM/fisheye**、real-focal 退化为标称焦距。
- `LightamerIOP/Sources/Lens/LensKernels.metal` — 单 pass 融合 kernel：统一 dc1..dc4 畸变多项式 + 全 6 项 TCA（逐通道独立采样 = 真 per-channel warp）+ devignette 除法（D1 纠偏：lensfun correct 语义 `1/(1+k1r²+k2r⁴+k3r⁶)`）；半径约定与求值序头注释钉死（`:20-50`）。
- `LightamerIOP/Sources/Lens/LensfunDB.swift` — Foundation XMLParser 全 schema 解析（lens/camera/mount、poly3/poly5/ptlens、tca linear/poly3、vignetting pa、real-focal、center、aspect-ratio；`:112-305`）。
- `LightamerIOP/Sources/Lens/LensfunMatch.swift` — lensfun C 语义自移植（头注释 `:13-47` 逐条列公式出处）：匹配打分 100/60/40 + maker +5（`:107-118`）、crop gate `imageCrop/entryCrop ≥ 0.96`（`:133`）、`_lf_interpolate` Hermite（`:160-186`）、渐晕 IDW p=3.5 三维归一距离（`:332-371`）、d-factor + hugin rescale + NS·HW 折算（`:211-263`）。
- `LensfunStore`（同文件 `:380-446`）— 进程级 NSLock 单例快照；`resolveCommitted` 是现役解析入口。
- `App/Sources/Lightamer/Session/LensfunDownloadService.swift` — master.zip 下载（`:35-36`，**不钉版**）+ `lensfun.customPath` 覆盖（`:39`）+ `resolveAndInstall()` 启动时装（`LightamerShell.swift:924`，无网络）。
- 面板 `LensPanelView.swift` 三段（内嵌状态 / 手动滑杆 / Lensfun 匹配）；注册 `Registry.swift:238-239`；**lens 不在 `defaultFaceDisabledOpNames`**（`Registry.swift:39-50`），编辑器 Geometry 行可达（`EditorTabRoute.swift:266-275`：crop/flip/lens 一行，ashift/liquify 等 advanced）。
- 测试：`Tests/LightamerTests/LensParityTests.swift`（合成 float64 参考 gate 1e-5 + uniform 探针；`:14-27` 头注明 **dt-cli 无 lens 腿**——本机 dt build 未链 liblens，L017 路线①合成参考是既定 golden 形态）+ `LensfunDBTests`（内联 XML hermetic）+ 固定 4 文件子集 fixtures（`input/golden/fixtures/lensfun/`，gitignore 例外 `.gitignore:28-35`，数据不入 git 纪律 = 04-04 DECISIONS D-04-04-T0-1）。
- 蒙版几何缝已通：`pointMapSegment`（`LensModule.swift:318-329`）向 `GeometryPointMapper` 供给径向段——蒙版点跟随 lens warp 已有。

## Upstream Facts — Lensfun 数据模型 / 许可 / 体积 / 更新通道

- **Schema**（04-RESEARCH.md:174-181 实测核过）：`<lensdatabase version="1">` → `<mount>(name,compat)` / `<camera>(maker,model,mount,cropfactor)` / `<lens>(maker,model,mount*,cropfactor,center?,aspect-ratio?,type?,calibration?)`；calibration = `<distortion model="poly3|poly5|ptlens">` / `<tca model="linear|poly3">` / `<vignetting model="pa" focal aperture distance k1 k2 k3>` / `<real-focal-length>`。全属性驱动、两层、无命名空间——`XMLParser` 足够（已验证）。
- **实测计数**（04-RESEARCH.md:15，Homebrew lensfun 0.3.4）：distortion poly3(875)/ptlens(4697)/poly5(5)；tca poly3(3265)/linear(6)；vignetting pa(23759)。**无 ACM 行**（`__parameter_scales` 恒等成立）。体积 **55-56 xml ≈ 4.2-5.1MB**（本机 `/opt/homebrew/share/lensfun/version_1/` 现测 56 xml / 4.2MB；RawLab 快照 56 xml / 5.1MB）——「子集内置」无必要，整库量级即 5MB。
- **许可双轨**：库 **LGPL-3.0**；校准数据 **CC-BY-SA-3.0**（RawLab 随包文件实证：`RawLab/lutools/third_party/lensfun/{lgpl-3.0.txt, cc-by-sa-3.0.txt, database-CC-BY-SA-3.0.txt}`）。数据 share-alike 归属须**独立于代码许可**处理：随包分发必须保留数据许可文本 + 来源声明（RawLab 形态 = `Resources/Licenses/Lensfun/` 全套文本 + README 声明 unmodified snapshot + SHA-256，`RawLab/RawLabMac/build.sh:63-65`）。**我方 NOTICE 现无 lensfun/CC-BY-SA 条目**（`NOTICE` 第三方 provenance 节仅 OpenDRT/aces-core 等）——落地批必须补。
- **更新通道**：官方快照 `https://lensfun.github.io/db/version_1.tar.bz2`（RawLab 2026-10-12 钉版 SHA-256 `97c9f805…`，`third_party/lensfun/README.md`）或 GitHub `lensfun/lensfun-data` master.zip（我方现用，**不钉版 = 不可复现**，`LensfunDownloadService.swift:35-36`）。DB max version = 1（两家一致）。

## Reference Implementations — 三方读解

### RawLab 0.7.0（GPL-3.0，链库路线实证）

- **链库**：pkg-config `lensfun >= 0.3.4`（`RawLabMac/build.sh:47,86`），未修改上游库、SHA-256 钉源。
- **数据打包**：unmodified offline snapshot 随包进 App Resources（`build.sh:63`：`version_1/ → Resources/Lensfun/`）+ 全套许可文本（`:64-65`）；「DB 更新 = 显式源变更，非渲染期下载」（third_party README）。
- **auto-detect**（`lutools/src/core/lens_correction.cpp`）：相机 `FindCameras(make,model)` **唯一命中才用**（`:19-25`，多命中弃）；镜头 `FindLenses(camera, lensMake, lensModel)`，**多候选 = `Ambiguous` 状态拒绝而非猜**（`:74-77`）；显式 `profileID` 覆盖（id = `maker\nmodel\nmount\ncropfactor(6dp)`，`:27-34`）。
- **auto-crop 语义**（`:230-247`）：**scale 补偿式**——对输出帧四边（含全部 RGB 通道 footprint，`:196-215`）做 inside 测试；zoom 从 1 起 ×1.25 粗探至 8，再 18 轮二分求最小 `cropScale`（×1.00001 余量）；超 8 判 `UnsupportedInput`。**是 zoom-in 隐藏无效边，不是几何裁切矩形**。
- **双重校正互斥**（解码器级，最干净先例）：`metadata.embeddedGeometry` ← LibRaw `LIBRAW_WARN_DNG_STAGE3_APPLIED` 警告位（`raw_processor.cpp:47-48`；设计正本 `docs/archive/integration/v0.7/lens-dng.md`——DNG OpcodeList3 经 SDK Stage3 应用的实机回归）；置位 → `EmbeddedGeometry` 状态、拒绝叠加（`lens_correction.cpp:161-163`）。crop factor 无库时由 EXIF 推导：`FocalLengthIn35mm / focal`（`raw_processor.cpp:45-46`）。
- **状态机 report**：`Off/NoCamera/Ambiguous/NoLens/NoCalibration/MissingFocalLength/NoDatabase/EmbeddedGeometry/UnsupportedInput/Matched`（`lens_correction.h` + `:155-183`）——UI readout 与批处理元数据共源。
- **默认态**：per-photo `distortion=false, tca=false, autoCrop=true, mode=.automatic|manual`（`RawLabMac/Sources/Adjustments/AdjustmentTypes.swift`）——**默认关，用户开**；渐晕 **未实现**（flags 只有 distortion+tca，`lens_correction.cpp:222-224`）。
- 缓存教训（`reviews/self-lens-correction-20261013-1018.md`）：lens 配置必须进 RAW 缓存键与曝光锚键（file-identity-only 键在 lens on/off 间串值）——对我方 `PipeCacheKey`/paramsHash 折叠面同构适用（现 paramsHash 已含 lens params，天然覆盖）。

### Alcedo Studio v0.3.3+（GPL-3.0，验收锚本体）

- **链库 + 随包 XML**：`<lensfun/lensfun.h>`（`src/edit/runtime/lens/lens_calibration_resolver.cpp:9`）+ 数据库 XML 随包 `src/config/lens_calib/*.xml`；三 GPU 后端 cuda/metal/opencl（`runtime/lens/{cuda,metal,opencl}/`，Metal = `metal/shader/lens_calib.metal`）。
- **设置面**（`src/include/edit/runtime/lens/lens_calibration_resolver.hpp:36-51` `LensCorrectionSettings`）：`apply_vignetting_/apply_distortion_/apply_tca_/apply_crop_` 四分开关 + `auto_scale_/use_user_scale_/user_scale_` + `projection_enabled_/target_projection_` + `low_precision_preview_` + `database_path_`。**这就是 FEAT-DEV-07 验收锚的逐字段展开**。
- **GPU 参数全型**（`lens_calib_runtime.hpp:53-119` `LensCalibGpuParams`）：source/target projection 8 型（`:35-45` rectilinear/fisheye/panoramic/equirectangular/orthographic/stereographic/equisolid/thoby）、crop mode RECTANGLE/CIRCLE + `crop_bounds[4]`（`:29-33,:91-92`）、插值档 bilinear/bicubic/lanczos（`:47-51`）、`resolved_scale`（CPU 侧定，`:107`）、perspective **stub 位**（`:109-111`——上游也还没做透视，与 UQ-R2 同起点）、fast-path hints（`:113-115`）。
- **auto-scale 用库函数**：`lf_modifier_get_auto_scale(modifier, false)`（`lens_calibration_resolver.cpp:499`）——链库路线的白送件；数据路线需自实现（见 OQ-LENS-5）。
- **状态机**：`Resolved / NoCorrectionApplies / MissingLensIdentity / DatabaseUnavailable / LensNotInDatabase`（`:56-62`）。
- **无嵌入校正守卫**：resolver 层无 stage3/opcode 探测（rg 零命中）——Alcedo 解码器（自养 demosaic 路线）不做 CIRAW 式 opcode 应用，故无双重校正问题；**我方 CIRAW 路线必须自建此守卫**（见下节）。

### darktable（GPL-3.0，数学正本）

- `src/iop/lens.cc` 锚点已在 LensModule 头逐行引用（flags :80-95 / TCA 手动 :140-144 / vignette-first :1194-1206 / ROI `_modify_roi_in_lf` :1697-1790）。OpenCL 腿 `_process_cl_lf`（`:1304`）：CPU 生成坐标缓冲上传 + `lens_distort_{bilinear,bicubic,lanczos2,lanczos3}` 四采样 kernel（`data/kernels/basic.cl:2057-2456`）——**无独立 lens.cl**；坐标生成仍在 CPU（链库 lfModifier 产物）。我方 GPU 侧多项式直算（LensfunMatch 预折算 + kernel 求值）比 dt 的 CPU 坐标上传路线更省——维持。
- dt 防双补 = lensfun `mods_done` 检测；GPL 后此数学可移植，但 CIRAW 无等价查询 API（见互斥节）。

## Route Decision Matrix — A/B/C

| 维 | **A 数据只读（现路线）** | B 链 LGPL lensfun 库 | C 移植 GPL 实现 |
|---|---|---|---|
| 工程量 | **剩余 = 收口缺口**（本研 §Baseline 表）；匹配/插值/归一数学已移植并带测试 | FFI 桥（C API）+ SPM system-library target + 构建链（vcpkg/brew 依赖分发）+ 现有 Swift 解析层废弃或并存 | 主体与 A 重合（dt 数学已移植）；增量仅投影数学与 auto-crop 算法 |
| 依赖 | 零新依赖（Foundation + Metal）| **破坏「依赖最小化」红线**（PROJECT Constraints）+ LGPL 动链合规义务（unsigned DMG 可行但增 NOTICE/构建面）| 零新依赖 |
| 性能（100MP）| 系数 GPU 端求值，逐像素 O(多项式)——零 CPU 坐标缓冲 | lfModifier CPU 坐标生成（dt `_process_cl_lf` 同款：100MP float2×3 通道 ≈ 2.4GB 坐标缓冲上传/帧）| 同 A |
| 与 CIRAW 互斥可控性 | **全自持**：探测逻辑/状态机/覆盖语义自己写（RawLab 语义可移植）| 仍须自建（CIRAW 侧无查询 API，链库不解决互斥）| 同 A |
| 维护 | lensfun 语义变更需跟（实为冻结快照 + 显式更新，RawLab 同款纪律）| 库升级自动跟进，但 API 稳定（0.3.x 十年）| 同 A |
| 许可 | 代码 GPL-3.0 自持；数据 CC-BY-SA-3.0 独立归属 | LGPL-3 库 + CC-BY-SA 数据双轨 | GPL-3.0 同源（保留原版权 + 标注修改）|

**推荐：A + 定向吸收 C**。C 不独立成路线——具体吸收件（GPL 合规，移植时保留版权头 + 标注修改 + NOTICE 登记）：
1. Alcedo `LensCalibGpuParams` 参数结构 + `lens_calib.metal` 投影数学（projection 特性直接对标移植基）。
2. RawLab auto-crop 二分语义（`:230-247`）+ 状态机枚举（含 `EmbeddedGeometry` 槽位）。
3. RawLab 曝光锚/缓存键教训 → 我方 paramsHash 已覆盖，验收时补一条 lens on/off 缓存隔离回归即可。

B 全面劣于 A：唯一红利 `lf_modifier_get_auto_scale` 用 ~50 行自实现替代（见 OQ-LENS-5）。

## Double-Correction Mutex — 双重校正互斥设计（关键设计点）

**事实基座**：
- CIRAW 对支持的镜头自动应用 DNG OpcodeList/厂商 opcode 校正（Phase 1 实证；`RAWDecoder.swift:218-220`：`kCIInputEnableVendorLensCorrectionKey` 等价键**保持默认 true**，注释明示）。CIRAW **无「是否已应用」查询 API**——RawLab 的 LibRaw 警告位路线在我方解码器上不可复制。
- 我方可控杠杆：`RAWTechnicalOverrides` 已是 per-image 解码参数面（`RAWDecoder.swift:196-217` 各 override 先写后读）——**加一枚 `vendorLensCorrection: Bool`（默认 true）即可让用户显式关掉嵌入校正后全权交给 Lensfun**（重解码语义，与现有 NR/decoder override 同缝）。

**探测缝（无 API 下的分层判定）**：
1. **DNG**：自行探测 OpcodeList1/2/3 TIFF tag（51008/51009/51010）存在性（文件头解析字节探针，纯读；ImageIO 不暴露私有 tag）→ `embeddedDetected`。
2. **厂商 RAW**：无可靠查询面 → `unknown`。已知启发（makernotes 校正标志位）脆弱，不建议 v1 依赖。
3. **raster/TIFF 链（M4-1）**：无嵌入几何概念 → `notApplicable`（Lensfun 可用，无互斥问题）。

**推荐三态行为**（对齐 04-04 已固化默认 + RawLab/Alcedo 语义）：
- 状态机 `embedded: detected / unknown / notApplicable` 进面板 §1（替换现静态文案——`LensPanelView.swift:44-47` 的 `panel_lens_embedded_note` 升级为带判定结果的 readout）。
- **auto 层默认行为**：`detected` → Lensfun auto 关（防双补，硬守卫）；`unknown` → Lensfun auto 关（保守默认，双重校正不可检测时宁缺）；`notApplicable` → auto 可默认开（raster 链无冲突）。
- **用户显式覆盖**：面板「强制启用」（对 detected 态出确认文案）+ 进阶「解码参数关嵌入校正」（`vendorLensCorrection=false` 重解码）= 二选一，两者并存会让用户叠加困惑——推荐只做后者？**推荐：强制启用（Lensfun 侧覆盖）为 v1 面；解码侧关嵌入校正为 v1.x**（涉及重解码缓存失效链，改动面大）。见 OQ-LENS-2。

## Auto-Detection Design

- **EXIF 侧缺口**：`CaptureMetadata`（`CaptureMetadata.swift:10-37`）有 cameraMake/Model、lensModel、focalLength、aperture——**无 `FocalLengthIn35mm`**（相机 crop 推导的正源，RawLab `raw_processor.cpp:45-46` 用法）与 lensMake。补两字段（ImageIO `kCGImagePropertyExifFocalLenIn35mmFilm` / `ExifAuxLensMake`），tolerant additive。
- **匹配硬化**（现役 `resolveCommitted` 的弱点，`LensfunMatch.swift:409-428`）：maker/model **传 nil**、`imageCrop` **硬编码 1.0**、distance 恒 nil——相机 crop gate（0.96）实际未生效，全画幅偏差镜头可能误匹配 APS-C 校正集。修复 = 走 `LensfunMatch.match(maker:model:lens:imageCrop:)` 全参路径（函数本体 `:126-155` 已实现，纯接线）+ camera 条目匹配（`db.cameras` 已解析）。
- **匹配预览 stub 修复**：面板 `refreshMatchState` 现在只回显 EXIF 串（`LensPanelView.swift:226-237` `matchName = key`）——落地 = 真跑 `LensfunMatch.match` 显示命中条目 maker+model+score 档位；miss 台账（04-04 PLAN Must-haves「miss 率在测试里落账」→ 运行态也应可见：RawLab `NoLens/Ambiguous` 状态 readout 形态）。
- **匹配阈值**：现 `fallbackEntry ≥ 40`（word-overlap 档，`LensfunMatch.swift:443`）偏松——40 分 = 仅词集包含，误匹配风险；推荐 auto 通道收紧到 ≥60（contains 档），40 档仅作手动浏览的排序提示。见 OQ-LENS-4。

## Geometry Pipeline Seam — 几何管线接缝

- **v50 位**：lens 13.0（畸变/CA/渐晕）< ashift 15.0 < flip 16.0 < crop 24.5（04-RESEARCH.md:18）。lens 在 crop 上游故恒见全幅、光心精确（`LensModule.swift:46-51` 已固化）；**与 UQ-R2 透视（keystone）共缝**：透视属 ashift 族（15.0），在 lens 之后——Lensfun 校正先「拍直」再透视/裁切是正确的算子序，两特性互不挤位。
- **scale 折算**：auto/user scale 不需要新模块——折进 `LensWarpUniforms` 加一标量（采样坐标 ×1/scale + ROI 边框点同步缩），kernel 单 pass 不变；ROI 协商已支持外扩/收缩（`modifyROIIn/Out`）。Alcedo 的 `crop_bounds[4]` + CIRCLE 模式不采纳（我方 crop 是独立 iop 24.5，几何裁切已有家）——**auto-crop = scale 补偿 + 可选「接力 crop 面板」**（把算出的最小 scale 换算成建议裁切框一键填入 CropPanel，避免两套裁切真相）。见 OQ-LENS-5。
- **TCA**：kernel 已逐通道独立采样（6 项 poly3），无需结构改动；ROI 的 per-channel union 边距 v1 用 G 通道 + 2px 近似（`LensModule.swift:251-259`），落地批按 D7 注记把 resolved-XML 路径放宽为真三通道 union（纯 CPU 边框映射改动）。
- **tile/内存**：主 pipe 无模块级 tiling（全平面 dispatch；`.allowTiling` 声明未被 pipe 消费）——100MP float32 平面 1.6GB×2（in/out）量级与既有 warp 族（ashift/flip）同阶，无新增内存风险；perf probe 走 `LIGHTAMER_PERF_PROBE=1` + queue fence 惯例（AGENTS.md M2-5 节红线：无 fence 计时 = 假数）。
- **per-render 解析开销（现役隐患）**：`process` 每次 run 都全库线性匹配（`LensModule.swift:338-342` → `LensfunStore.resolveCommitted` → `LensFunMatch.match` 扫全 lenses × 打分）——拖滑杆每次预览渲染都重复 ~数千条目字符串打分。落地批随系数快照（下节）一并消解：匹配在 commit 期做一次，process 期只读快照系数。

## Persistence & Process Version

- **params 载体**：`LensModule.Params` Codable 骑 history item（sidecar v10 现行 schema；paramsData base64 字节精确惯例）——**扩字段全走 additive optional + 默认值字节零漂移守卫**（M3-1-01 LUT 编码对先例：hash 专测钉死旧档逐字节）。
- **系数快照（强烈推荐）**：现 params 只存 `source/lensKey/focal/aperture`，系数在 process 期按**当前 DB** 实时解析——**DB 更新会静默改写全部旧档渲染**，与「非破坏 + 渲染确定性」纪律冲突（M6-2 RenderProcess.swift:29-44 的 bump 纪律管代码语义，管不住数据源漂移）。推荐：Apply/auto-match 时把**归一化系数**（dc1..dc4/vr..bb/vk1..k3/model ids/profile id/匹配分数）快照进 params——渲染与 DB 版本彻底解耦；DB 更新 = 用户显式「re-match」才生效。代价：params 变大（~30 float），可接受。见 OQ-LENS-3。
- **process version 判定**：①auto-enable 改的是 `reloadDefaults`（新档默认参数），旧档 params 不动 → **不 bump**；②resolve 数学修订（投影/hugin 折算修复）属 look change → **bump `RenderProcessVersion` + 新旧 golden 对**（RenderProcess.swift:29-37 纪律）；③系数快照使 resolve 从 process 期消失 → 同批属于 ② 的语义变更评估（快照使旧档「按当时 DB」重放 = 观感可能变 → 快照落地批自带 bump 评估）。
- **批量/预设面**：lens 属 `.develop` 族 → `isAdjustmentTransferable` 排除（`AdjustmentTransfer.swift:36-39` 只放行 `.grade`）→ Copy Adjustments/grade 预设不带 lens（正确：几何/镜头是 per-shot 属性）；批量校正走 M7-4 MCP `apply_params`（同谓词）或项目级「新片默认」设置面——v1 建议只做 per-photo + optional 项目默认开关，预设打包（UQ-R6 形态）不带 lens。

## UI / UX（面板改造面）

现三段 → 目标五段（Alcedo 设置面逐项 + RawLab 状态机 readout）：
1. **状态**（嵌入校正判定三态 + 匹配状态机 readout：Matched(name/score)/NoLens/Ambiguous/NoDatabase/MissingFocal/NotApplicable）。
2. **enable + per-correction 开关**（distortion/TCA/vignette 三 toggle，Alcedo `apply_*` 逐项；enable = 整段总开关）。
3. **scale**（auto 开关 + user 滑杆 + resolved readout；auto-crop 语义挂此处）。
4. **profile browser**（RawLab `lens.chooser` 形态：搜索 + 候选列表 + matched 置顶；替换现「Apply/Clear」两按钮——手动选型是 auto-detect 的回落 UX）。
5. **数据管理**（DB 来源/版本/条目数 readout + 手动更新按钮 + 自备路径设置项迁 Settings——现 `panel_lens_download` 按钮位）。
布局跟随现 LightamerSlider/Form 惯例（D-H1 拖拽三件 + discrete commit 键族 `panel_lens_*`/`history_lens` 已注册，新键尾块纯插入）。

## Test Strategy

- **基座已在**：`LensParityTests`（合成 float64 参考 1e-5 门 + uniform 探针——warp 是空间变化算子，dt-cli EXR parity 不可用且本机 dt 无 lens 腿，`LensParityTests.swift:14-27` 既定结论维持）+ `LensfunDBTests`（解析/匹配/插值 hermetic）。
- **新增**：①投影/crop/scale kernel 数学 golden（同一 gen_fixtures.py 合成路线扩节；投影参考公式 GPL 后可与 Alcedo `lens_calib.metal` 直接同源对表）；②匹配硬化回归（camera crop gate 生效/miss 台账/阈值分档）；③互斥状态机表驱动（detected/unknown/notApplicable × enable 组合）；④系数快照 round-trip + 旧档字节零漂移负测；⑤lens on/off 缓存隔离回归（RawLab 教训移植）；⑥DB 快照钉版测试（ fixtures 已有，补 update 通道的 SHA 校验单测）。
- **跨实现对账**：GPL 后可用 RawLab（链库真值）产参考帧做抽样对账（非 CI 门，抽查形态——RawLab CLI/配方面可无头渲染）；dt 侧维持合成参考（无 lens 腿）。
- **perf**：100MP 预算 probe（lens 全平面 dispatch 单帧耗时 + 匹配移出 process 期前后对比），`LIGHTAMER_PERF_PROBE` 惯例。

## Plan Split Suggestion

| 波 | 内容 | 规模 | 备注 |
|---|---|---|---|
| **L1** | 互斥落地：嵌入探测（DNG tag 探针）+ 状态机 readout + 匹配硬化（maker/model/crop 全参 + 预览 stub 修复 + 阈值分档）+ EXIF 补字段 + 匹配移出 process 期 | S-M | 纯现基座接线，无 kernel 改动；`panel_lens_*` 键族追加 |
| **L2** | enable/per-correction/scale（auto+user）+ kernel uniforms 扩 scale + profile browser + auto-crop（scale 补偿 + 接力 crop）| M | kernel 单 pass 扩参；ROI 缩放联动；RawLab 二分移植 |
| **L3** | projection（Alcedo GPU 参数结构 + 投影数学移植，rectilinear↔fisheye 族）+ 数据分发硬化（钉版快照随包 vs 下载裁决 + NOTICE CC-BY-SA 条目 + 更新通道）| M | projection 可拆独立波（Alcedo 移植件最大单件）；NOTICE/许可件不可延后 |
| **L4** | 系数快照持久化 + process version 评估/bump + 测试面收口（golden 扩节/缓存隔离/process 对）+ perf probe | S-M | 与 L2/L3 的语义变更合并裁决 bump |

串行依赖：L1 → L2 → L3（投影依赖 scale 的 uniforms 结构）；L4 与 L3 可并行。ΔN 粗估：全套 +60..90 测试（现 IOP/目录 +App 分账按 BUNDLE-MAP 落域，`tuist generate` 恒收尾——CONVENTIONS M2-4-0 E2 红线）。

## Open Questions

- **OQ-LENS-1 auto 默认行为**：新片自动应用（matched 即 enable）还是保持显式 opt-in？**推荐：全局默认 opt-in 关 + 面板/设置「自动应用匹配」开关（默认关，raster 链可默认开）**——`unknown` 态占多数（厂商 RAW），自动开 = 高概率双补面；RawLab 默认关同判。
- **OQ-LENS-2 覆盖语义**：detected 态的「强制 Lensfun」= 仅 Lensfun 侧覆盖，还是同时提供「解码关嵌入校正」（重解码）？**推荐 v1 只做 Lensfun 侧覆盖 + 警示文案；解码侧 override 挂 v1.x**（重解码缓存链改动大，价值 = 极端双补需求的逃生门）。
- **OQ-LENS-3 系数快照 vs 实时解析**：**推荐快照**（渲染确定性 + 消 per-render 匹配开销；代价 = DB 更新需显式 re-match）。若裁决实时解析，则必须把 DB 版本折进 paramsHash + process 评估。
- **OQ-LENS-4 匹配阈值与歧义**：auto 通道 ≥60？多候选歧义 = RawLab 式拒绝还是最高分即用？**推荐 ≥60 + 歧义（同分多候选）拒绝进手动**——错误校正比无校正更伤信任。
- **OQ-LENS-5 auto-crop 形态**：scale 补偿（RawLab/Alcedo 同语义）+ 可选「接力 crop 面板」vs 真 `crop_bounds` 内嵌？**推荐前者**（裁切真相单源在 CropModule 24.5，符合 Alcedo framing 分工）；CIRCLE 模式不采纳。
- **OQ-LENS-6 数据分发**：随包钉版快照（~5MB，RawLab 形态，离线即用、复现可审计）vs 维持首跑下载？**推荐随包钉版 + NOTICE/许可全套 + 设置面手动「检查更新」（拉官方 version_1.tar.bz2 钉 SHA）**——「依赖最小化」管代码库不管数据资产；下载失败降级路径保留（customPath 优先序不变）。
- **OQ-LENS-7 vignetting 纳入**：RawLab 无渐晕、Alcedo/dt 有——**推荐有**（kernel/插值已在，只是开关 + 默认档）；渐晕系数随 EXIF aperture 缺失时 = nearest-aperture 行（现 IDW 已处理）。
- **OQ-LENS-8 projection 范围**：Alcedo 8 型全量 vs 只 rectilinear↔fisheye 主流四型（fisheye/equisolid/stereographic/orthographic）？**推荐四型起步**（panoramic/equirectangular/thoby 数据面与用例双重稀疏，枚举槽位预留 additive）。

## Risks

- **双重校正不可全检测**（厂商 RAW `unknown` 态恒存）——缓解：默认 opt-in + 面板诚实状态 + 覆盖逃生门；残余风险登记为产品取舍（dt 的 mods_done 等价物在 CIRAW 路线架构性不可达）。
- **匹配误命中**（EXIF lens 串质量参差/lensfun 别名多）——缓解：阈值分档 + 歧义拒绝 + profile browser 手动回落 + miss 台账。
- **许可归属遗漏**（CC-BY-SA 数据 share-alike 归属是独立义务，NOTICE 现无条目）——缓解：L3 数据分发批带许可审计件（fixtures 子集已在 git，同样须在 NOTICE 或 fixtures README 已有声明处复核——`input/golden/fixtures/lensfun/README.md` 现状待核）。
- **auto-scale 自实现精度**（无 `lf_modifier_get_auto_scale` 等价物）——缓解：RawLab 二分语义移植（GPL 可直采）+ 合成 golden 钉边界。
- **DB 大库性能**（全库线性匹配）——缓解：L1 把匹配移出 process 期（commit 期一次）；若库随包整载解析耗时超窗（对照 S2 教训：`list_luts` 冷首调 50.2s 同类盲区），启动异步装载 + `LensfunStore.isInstalled` 门已天然降级。

## Sources

### 本仓（file:line）
- `LightamerIOP/Sources/Lens/LensModule.swift:57-74,151,155,172-178,251-259,318-329,335-346` — 模块/偏离登记/槽位/默认 off/ROI/蒙版缝/解析入口
- `LightamerIOP/Sources/Lens/LensKernels.metal:20-50` — 半径约定/模型映射/求值序
- `LightamerIOP/Sources/Lens/LensfunDB.swift:112-305`；`LensfunMatch.swift:13-47,107-118,126-155,160-186,332-371,409-446` — 解析/匹配/插值/store
- `App/Sources/Lightamer/Session/LensfunDownloadService.swift:35-39,52-65`；`App/Sources/Lightamer/UI/Shell/LightamerShell.swift:924` — 分发/启动装
- `App/Sources/Lightamer/UI/Inspector/LensPanelView.swift:44-47,226-237,242-256` — 面板/stub/Apply-Clear
- `LightamerCore/Sources/Decode/RAWDecoder.swift:218-220`；`LightamerCore/Sources/Decode/CaptureMetadata.swift:10-37` — CIRAW 互斥杠杆/EXIF 面
- `LightamerCore/Sources/Pipe/RenderProcess.swift:29-44` — bump 纪律；`App/Sources/Lightamer/State/AdjustmentTransfer.swift:36-39` — 传输谓词
- `LightamerIOP/Sources/Registry.swift:39-50,238-239`；`App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift:266-275` — 注册/路由
- `Tests/LightamerTests/LensParityTests.swift:14-27`；`.gitignore:28-35`；`NOTICE`（无 lensfun 条目）
- `.work/gsd/phases/04-geometry-lens-detail-iops/04-RESEARCH.md:15,17-18,161,172-183`；`04-04-PLAN.md`；`04-04-DECISIONS.md`（D-04-04-T0-1..3, D1-D9）
- `.work/gsd/research/UPSTREAM-QUEUE.md:44`（UQ-R4/LENS-01 charter）

### RawLab（`/Volumes/UNITEK/Documents/Development/RawLab`，GPL-3.0）
- `lutools/src/core/lens_correction.cpp:19-34,60-83,155-183,196-247` — 匹配/歧义/auto-crop 二分
- `lutools/src/core/raw_processor.cpp:45-48` — crop 推导/Stage3 嵌入位；`lutools/include/sony2fuji/lens_correction.h` — 状态机/options
- `RawLabMac/build.sh:47,63-65,86`；`lutools/third_party/lensfun/README.md` — 链库/打包/钉版
- `docs/archive/integration/v0.7/lens-dng.md` — Stage3 探测设计正本；`reviews/self-lens-correction-20261013-1018.md` — 缓存键教训
- `RawLabMac/Sources/Adjustments/AdjustmentTypes.swift` — per-photo 默认态

### Alcedo Studio（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`，GPL-3.0）
- `src/include/edit/runtime/lens/lens_calibration_resolver.hpp:36-62` — 设置面/状态机
- `src/include/edit/runtime/lens/lens_calib_runtime.hpp:11-119` — GPU 参数全型（projection 8 型/crop mode/resolved_scale/perspective stub）
- `src/edit/runtime/lens/lens_calibration_resolver.cpp:218-296,499` — hugin 重标/auto-scale 库函数
- `src/edit/runtime/lens/metal/shader/lens_calib.metal` + `src/config/lens_calib/*.xml` — Metal 腿/随包数据

### darktable（`/Volumes/UNITEK/Documents/Development/darktable`，GPL-3.0）
- `src/iop/lens.cc:80-95,140-144,1194-1206,1304,1697-1790`；`data/kernels/basic.cl:2057-2456`（lens_distort_* 四采样 kernel）
