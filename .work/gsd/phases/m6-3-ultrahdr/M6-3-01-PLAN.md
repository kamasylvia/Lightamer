---
phase: m6-3
plan: "M6-3-01"
title: "ALCE-03 UltraHDR gain map JPEG 导出（单 plan 全量批）——ExportVariant additive `gainMapHDR` 字段与 validate 四门（非 jpeg / drtOutput 缺席 / peak<203 headroom<1 / embedICC=false typed 拒——MPF 偏移雷结构性排除）+ HDR 线性面取缝（DRT 尾 EOTF-box 前线性级，PixelPipe 窄缝解封申报 + owned-copy 纹理 + headroom=peak/203 单源）+ 渲染→编码 queue 级 box 交接（ExportQueueContract 零 diff）+ ExportGainMapEncoder（CI writeJPEGRepresentation `.hdrImage` 全服务路 + 同目录 tmp 原子晋升 L009 + CopyImageSource 元数据 rewrap〔XMP F5 形 + EXIF probe 先行降级〕）+ encodeStage 分支与后处理门（ICC strip / XMP 注入双旁路——MPF 偏移雷消解）+ M2 页 SDR 节 checkbox 三态门与 enqueue 联动 + 容器/读回/基面保真/gain 语义 golden + reimport raster 链兼容"
wave: 1
depends_on: []
autonomous: true
requirements: ["ALCE-03（REQUIREMENTS 原位注记，解冻 → M6-3）"]
estimated_tests: "+24..30"
test_bundles: [EXPORT, APP]
files_modified:
  - LightamerCore/Sources/Export/ExportRecipe.swift                # 修改：ExportVariant additive `public var gainMapHDR: Bool = false`（KD-1：decode decodeIfPresent ?? false 旧档零漂移；variant 不持久化——M2-9 既定）+ validate() 四门（gainMapHDR ∧ format != .jpeg / ∧ drtOutput == nil / ∧ peakLuminance < 203 / ∧ !embedICC → AppError typed 拒）；ExportFormatSpec 类型面零 diff（红线）
  - LightamerCore/Sources/Pipe/PixelPipe.swift                     # 修改：run-scoped `linearGainCapture: ((MTLTexture, SIMD2<Int>) -> Void)? = nil` 窄缝（缺省 nil = 全部既有路径字节零变化）+ runTerminalTails 的 EotfBox 输入点单调用位；**封存面解封申报**（M3-3 清单内窄缝 additive，M4-1「封存面解封」先例，DECISIONS 登记）
  - LightamerCore/Sources/Export/ExportRenderer.swift              # 修改：StageOutput additive `hdrGainPlane: ExportGainMapHDRPlane?`（internal 载体）+ renderStage 装配 capture（variant.gainMapHDR ∧ drtTail != nil 时置 pipe.linearGainCapture，owned-copy 纹理）+ encodeStage additive 参数 `gainMapHDR: Bool = false, hdrGainPlane: ExportGainMapHDRPlane? = nil`（缺省 = 全部既有调用点零 diff）+ 分支旁路 registry 直调 ExportGainMapEncoder + 后处理门（gain-map 臂跳过 stripICC 与 mountXMP）
  - LightamerCore/Sources/Export/ExportQueue.swift                 # 修改：makeLegs 双腿共享 `ExportGainMapPlaneBox`（final class + NSLock + [Int: plane] keyed by artifact.token；render 腿 stash / encode 腿 consume+clear / cancel-retry 清理）——ExportQueueContract 封存面零 diff（contract 载体不扩）
  - LightamerCore/Sources/Export/ExportGainMapEncoder.swift        # 新建：CI writeJPEGRepresentation 全服务编码（KD-4）+ SDR 参考白常量 `sdrReferenceWhite: Float = 203` 单源 + 同目录 tmp→原子晋升（L009）+ CopyImageSource 元数据 rewrap（XMP F5 形 + EXIF probe 先行）
  - App/Sources/Lightamer/Export/ExportInspectorView.swift         # 修改：SDR 导出节 UltraHDR checkbox（三态可用门 + 两条不可用文案）+ ExportM2PanelModel additive `var gainMapHDR = false`（会话态，同 embedICC 层）+ :350 陈旧「UltraHDR 是 M4 ALCE-02 面」注记原位更新（ALCE-03 落地）
  - App/Sources/Lightamer/State/ExportState.swift                  # 修改：RunAssembly/enqueueExportM2 联动——assembled.gainMapHDR = panel 开关（M3-1-03 makeRunAssembly 纯缝延续；drtOutput 强制联动语义不变）
  - Resources/Localizable.xcstrings                                # 修改：新键 4 枚尾块纯插入（KD-6 清单；UserDefaults 零新增）
  - Tests/LightamerTests/ExportGainMapTests.swift                  # 新建（Export bundle，21 法，KD-7）：validate 四门 + additive 零漂移 + capture 两态 + 容器字节面 + aux 读回字典 + rewrap 存活 + 后处理双旁路门 + 质量旋钮 + tmp 晋升 + 基面保真 + gain 语义带 + reimport 兼容
  - Tests/LightamerTests/ExportGainMapPanelTests.swift             # 新建（App，6 法，KD-6 机检缝）：三态可用门 + 装配携带 + enqueue 联动 + 默认关零 diff
  - Project.swift                                                  # 修改：两新测试文件登记对应 target 数组（显式清单无 glob）+ `tuist generate` 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt     # 修改：两新行登记（E2 纪律，随各自任务 commit）
  - .work/gui-acceptance/m6-3/MANIFEST.md                          # 新建（T5——跨生态目检 Manual-Only 配方：Preview/Photos HDR 渲染 + sips + Chrome/Android 如有 + LightCraft 参考产物互读可选行）
  - AGENTS.md                                                      # 修改：M6-3 架构增量节（CI 全服务路定式 + 203 单源 + 后处理门雷 + box 交接形）
  - .work/gsd/ROADMAP.md                                           # 修改：M6-3 行 ✅（T5 收口同批）
  - .work/gsd/REQUIREMENTS.md                                      # 修改：ALCE-03 兑现终态注记（T5）
  - .work/gsd/phases/m6-3-ultrahdr/M6-3-01-SUMMARY.md              # 新建（T5）
  - .work/gsd/phases/m6-3-ultrahdr/M6-3-01-DECISIONS.md            # 新建（T5——含 EXIF probe 结论双态登记 + PixelPipe 解封申报 + CI 黑盒漂移 band 断言注记 + headroom<203 默认禁用 UX 注记）
  - .work/gsd/phases/m6-3-ultrahdr/M6-3-01-ACCEPTANCE.md           # 新建（m1 双重验收记录——zcode PASS 后串行 omp 二次验收，严禁并发）
  - .work/GOAL-STATE.md                                            # 修改：续接点
  - .work/TODO.md                                                  # 修改：M6-3 条目
  - .work/LESSONS.md                                               # 如踩坑
---

# Plan M6-3-01 — ALCE-03 UltraHDR gain map JPEG 导出（单 plan 全量批）

> **性质**：M6-3 单 plan 承载 phase 全部交付面（RESEARCH §3 集成面测绘全量 +
> §7 OQ 六项生效值 + §8.4 ExportICCStrip 雷消解）。规格正本 = `RESEARCH.md`
> （spike 实测 D/E/F 臂亲证值；源码锚点为 2026-10-13 HEAD `55eb8f3c` 亲核）；
> 裁决正本 = `M6-3-CONTEXT.md`（**OQ-M6-3-1..6 全按推荐，夜间全自动授权批
> 2026-10-13，先例 D-07-3-T5-1，晨审可推翻**）。机制底座 = M2-9 导出链
> （`drtTails` per-image 载体 + `$jobDrtTail` TaskLocal 递缝范式 + peak 闸）+
> M2-6 DRT 尾（EOTF-box 尾段 + EOTF 前尾平面恒 working float32）+ M4-1 raster
> 链（重导入兼容臂）。
>
> **基线**：**3725/24/0**（M6-2-VALIDATION 2026-10-14 终验亲证值，ROADMAP 头部
> 亲核「M6-2 closed 2026-10-14 terminal 3725/24/0, dual independent acceptance
> PASS」）。本批预期全套 **3749..3755/24/0**（+24..30；两新文件 27 法预估），
> 对账留 T5 验收；bundle 分账 = Export +21 / App +6（基线分账以 M6-2 VALIDATION
> 终验表为准，验收轮对表）。

## 已定裁决（生效值，硬约束，不得重开）

M6-3 OQ-1..6 **全部按推荐裁**（CONTEXT 裁决记录 2026-10-13 夜间授权批）。本单 plan 承载全部六项：

1. **OQ-1 = A（HDR 面取平面点）**：HDR 线性面 = **同一 DRT 尾在 EOTF-box 之前
   的线性级取平面**（display-referred linear float32）；**禁独立 EDR 渲染链**
   （第二真相源）。spike E4 反证钉死前提：`.hdrImage` 恒喂线性光，绝不喂
   PQ/HLG 编码码值。
2. **OQ-2 = A（EXIF）**：metadata 路 **probe 先行**（T2 执行期，F5 同缝一次
   验证）；probe 失败 → **v1 接受 gain map 档无 EXIF**（DECISIONS 登记 +
   降级注记）；**自建 APP1 EXIF 注入器不入首批**（段级注入移 MPF 绝对偏移）。
3. **OQ-3 = A（hdrgm XMP 档位）**：primary XMP 经 rewrap 补 **`hdrgm:Version`**
   接受（目标生态 = Apple 全量 + 现代 Android 13+/Chrome 读 ISO 容器）；老
   Android 非硬需求；**LightCraft Rust 移植臂（C 路）降兜底封存**——仅本条被
   推翻时激活，当前零代码移植、零 NOTICE 义务。
4. **OQ-4 = A（通道数）**：**单通道亮度 'L008'**（CI 默认；`hdrGainMapAsRGB`
   不开——D2 实证 RGB 档读回侧 Data 键被 reader 扣留）。
5. **OQ-5 = A（UI 位）**：M2 检查器 **SDR 导出节 checkbox**；可用门 =
   `drtOutput != nil` ∧ format == `.jpeg` ∧ `peakLuminance ≥ 203`（headroom =
   peak/203 ≥ 1.0）；不可用态给 ExportICCStrip 文案形说明。
6. **OQ-6 = A（tag）**：**不加新 tag/formatName**（仍 "jpeg" 同池冲突递增）。

**架构红线（本 plan 全程 + checker 机检面）**：
- **六格式矩阵既有路径零 diff**：`ImageIOEncoders.swift` 与 `WebPEncoder.swift`
  **文件级零 diff**（比「既有路径零改」更强姿态——本批零触碰）；`ExportFormatSpec`
  类型零改动（`ExportRecipe.swift` 内该面零 diff，本批对该文件改动 =
  ExportVariant 字段 + validate 四门）；`ExportEncoderRegistry`（expectedLayout /
  encoder dispatch）与 quantizer 阶梯零改。
- **`ExportICCStrip` 本体零 diff**（`ExportEncoder.swift` 文件级零 diff）——
  gain map 档经 encodeStage 门旁路，strip 代码不动。
- **`ExportQueueContract.swift` 零 diff**（M3-3 封存面）——HDR 面交接走
  ExportQueue 级 box，contract 载体不扩。
- **`PixelPipe.swift` 窄缝解封申报制**：M3-3 封存清单内文件，本批仅 additive
  run-scoped capture 属性 + 单调用位（M4-1「封存面解封②兑现」先例），
  DECISIONS 申报 diff 范围；**`.metal` 零 diff**（零新 kernel——gain 计算全在
  CI 黑盒内）。
- 零新 SPM；V50Order/GradeCatalog/Registry/HistoryStack/HistoryHash/sidecar
  schema/MCP 20 工具封闭集/QuickLook+Spotlight appex 零触碰。
- **L057/L058 禁令**（无面板呈现新面——checkbox 为内联 SwiftUI Toggle；新键
  恒静态字面量，禁 `String.LocalizationValue("prefix_\(x)")` 插值形）；
  xcstrings 尾块纯插入；UserDefaults 零新增（gain map 开关 = 会话内 recipe 面，
  同 collisionPolicy 裁定）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 ExportVariant additive 字段与 validate 四门（T1）

- `public var gainMapHDR: Bool = false`（`ExportRecipe.swift` :23 结构体内
  additive；decode `decodeIfPresent ?? false`——无键旧 variant 零漂移；encode
  走既有合成面即可，variant 不持久化 = M2-9 既定，零迁移面）。
- `validate()`（:119）追加**四门**，全 typed `AppError.invalidParameter`：
  ①`gainMapHDR && format != .jpeg` → 拒（六格式其余五格式 = typed 不可达，
  文案形同 ExportICCStrip 不可达说明）；②`gainMapHDR && drtOutput == nil` →
  拒（HDR 面来源 = DRT record——OQ-7 强制联动语义的镜像）；③
  `gainMapHDR && !peakLuminance.isFinite || peakLuminance < 203` → 拒
  （headroom = peak/203 < 1.0 = 无 HDR 余量；文案说明 SDR 参考白）；④
  `gainMapHDR && !embedICC` → 拒（**§8.4 雷结构性排除**——stripJPEGICC 删
  APP2 会使 MPF 副图绝对偏移失效，gain map 档强制 embedICC 形态）。
  既有 finite-positive 闸（:130）不触，四门为 additive 追加。
- **SDR 参考白常量单源**：`ExportGainMapEncoder.sdrReferenceWhite: Float = 203`
  （Core 单源）；validate 与 UI 门读同一常量（禁双源漂移）。

### KD-2 HDR 线性面取缝（T1，OQ-1 生效值）

- **capture 点** = `PixelPipe.runTerminalTails`（:1126）尾段 sub-run 的
  **EotfBox 输入平面**（M2-6 增量正本：「EOTF 之前的尾平面恒 working
  float32（display-referred 线性）」——该平面即线性光 HDR 面）。缝形 =
  run-scoped `linearGainCapture: ((MTLTexture, SIMD2<Int>) -> Void)? = nil`
  （缺省 nil = 既有路径字节零变化），尾段回放在 EotfBox 消费前单点回调。
- **owned-copy 纪律**：回调内将平面 blit 到 capture 专属纹理（防 pipe 池
  复用/下一 run 覆写）；载体 `ExportGainMapHDRPlane`（`ExportGainMapEncoder.swift`
  内值类型：texture + width/height + headroom）。GPU→GPU 交接（同设备
  CIContext），无 CPU 读回无 L014 fence 需求；测试侧 GPU 读回仍走既有
  fence 形。
- **装配点** = `ExportRenderer.renderStage` 的 pipe 装配窗（:499-518
  `tailFormatFloatOverride` 同位）：`variant.gainMapHDR && drtTail != nil` 时
  置 capture，回调产出 `StageOutput.hdrGainPlane`（additive internal 字段，
  :263 结构体）。headroom = `drtOutput.peakLuminance / 203`（KD-1 常量单源）。
- **双臂同链纪律**（OQ-1 硬约束）：SDR base = 既有链逐字节不变；HDR 面与
  base 共用同一 record 同一尾段回放，只差 capture 点在 EOTF-box 前——禁任何
  独立第二渲染链。禁 PQ/HLG 码值直喂（E4 反证；capture 点结构性排除）。

### KD-3 渲染→编码 HDR 面交接（T1，contract 零 diff 裁定）

- `ExportRenderStage`/`ExportRenderArtifact` 在 `ExportQueueContract.swift`
  （:207/:247）= M3-3 封存面，**零 diff**——HDR 面不走 contract 载体。
- 交接 = `ExportQueue.makeLegs` 内双腿闭包共享的 **`ExportGainMapPlaneBox`**
  （final class + NSLock + `[Int: ExportGainMapHDRPlane]`，key =
  `artifact.token`（snapshot.seq）；render 腿闭包（:590-617）从 StageOutput
  stash；encode 腿闭包（:618-636）按 `variant.gainMapHDR` consume + clear）。
- **生命周期**：consume 即 clear；cancel/generation 换代/finish 路径清残余
  （retry 重跑 render 腿覆盖写同 key——token 复用语义 = 覆盖，DECISIONS 注记）；
  非 gain-map job 恒不触 box（零行为）。

### KD-4 ExportGainMapEncoder（T2，CI 全服务路正本）

- 新文件 `LightamerCore/Sources/Export/ExportGainMapEncoder.swift`，编码形 =
  spike D1 实证调用（RESEARCH §1.4 verbatim 语义）：
  `CIContext.writeJPEGRepresentation(of: sdrBaseCIImage, to: tmpURL,
  colorSpace: targetCGColorSpace, options: [.hdrImage: hdrCIImage,
  .quality: q])`——SDR base CIImage 由量化平面 CGImage 构造（既有
  targetColorSpace）；HDR CIImage = capture 纹理 + linear Rec2020 + 
  `imageBySettingContentHeadroom(peak/203)`（macOS 26+，27 底线内，零
  `#available`）。
- **L009**：CI 直写 URL——写**同目录 tmp 名**再 `FileManager` 同卷 rename
  原子晋升（`writeAtomically` :159 的半成品语义镜像；测试钉「无残渣」）。
- **元数据 rewrap**（F5 实证形）：`CGImageDestinationCopyImageSource`（JPEG→
  JPEG 同 UTI）+ `kCGImageDestinationMetadata`——挂 primary XMP：Software
  签名（`$jobExifSoftware` 既有载体）+ `hdrgm:Version`（OQ-3）+
  policy-gated sidecar 五元数据（经既有 XMPWriter 载体，**禁第二 XMP 真相
  源**）；`metadataPolicy.mode == .none` → 不挂（容器仍 UltraHDR，负测钉）。
  **rewrap 后容器必须全存活**（MPF/ISO APP2/aux 读回——F5 门）。
- **EXIF probe 先行**（OQ-2）：T2 执行期在同一 rewrap 缝 probe
  metadata-namespace EXIF 标签落盘；结论（成功/失败）入 DECISIONS 双态登记。
  失败 = v1 无 EXIF（EXIF Software 签名随之缺席——与 ImageIO 腿 {TIFF} 座位
  的 L054 事实分账登记），不算缺口。
- **质量旋钮**：`kCGImageDestinationLossyCompressionQuality` 直通（E3 实证），
  值 = `spec.quality ?? 0.9`（与 JPEGEncoder :188 同语义）。

### KD-5 encodeStage 分支与后处理门（T2，§8.4 雷消解）

- `encodeStage`（`ExportRenderer.swift` :621）additive 参数
  `gainMapHDR: Bool = false, hdrGainPlane: ExportGainMapHDRPlane? = nil`
  （缺省 = 既有调用点零 diff；queue encodeLeg :628-635 传
  `variant.gainMapHDR` + box 取面）。分支：`gainMapHDR` 真时**旁路
  `ExportEncoderRegistry.encoder`** 直调 `ExportGainMapEncoder`（registry 与
  JPEGEncoder 零触——布局门对 gain map 双平面结构不适用）；假时既有路径
  逐字节。
- **后处理门**（MPF 偏移雷——RESEARCH §8.4 正本）：gain-map 臂
  `!embedICC` 的 `stripICC` 调用（:663-672）与 `mountXMP` 调用（:681-689）
  **双双跳过**——APP2 删除/APP1 注入都会移动文件内绝对偏移使 MPF 副图失效；
  XMP 已在 encoder rewrap 内挂载（KD-4），无二次注入。ICC 嵌入与 MPF 共存 =
  gain map 档强制形态，`embedICC=false` 组合在 validate 门④ typed 拒
  （KD-1）——UI 禁用 + validate typed 拒双防线无矛盾态。
- 非 gain-map 路径（其余五格式 + 普通 JPEG）行为零 diff：后处理门只看
  `gainMapHDR` 旗标，负测一条钉死。

### KD-6 M2 页 UI（T3，OQ-5 生效值）

- `ExportM2PanelModel`（ExportInspectorView.swift :609）additive
  `var gainMapHDR = false`（会话态，同 `embedICC` :652 层；跨会话不记忆 =
  collisionPolicy 同裁定，UserDefaults 零新增）。
- **checkbox**（SDR 导出节 :382，format picker 之后）：可用门三态谓词 =
  `formatKind == .jpeg` ∧ 当前图 drt readout 在册（:354 同判据）∧
  `effectiveDrtRecord().peakLuminance ≥ 203`（KD-1 常量）。禁用态两条说明
  （ExportICCStrip 不可达文案形 ：332-339 镜像）：非 JPEG /
  peak < 203（「提升 DRT Peak 至 203 nits 以上以启用」语义）。
- **联动**：RunAssembly/enqueueExportM2（`ExportState.swift` :484-545）——
  `assembled.gainMapHDR = model.gainMapHDR`（drtOutput 强制联动 ：527 不变；
  variant 携带旗标入队，drivetTails 载体零新增——旗标随 variant 过双腿）。
  默认 false = 装配面零 diff。
- 陈旧注记原位更新：:350 「the true HDR container (UltraHDR) is the M4
  ALCE-02 face」→ ALCE-03 已落地（本文档级注释，零行为）。
- **新键 4 枚**（尾块纯插入）：`export_gainmap_label` / `export_gainmap_hint`
  （启用态说明：ISO 21496-1 gain map 随 JPEG 嵌入）/ 
  `export_gainmap_unavailable_format` / `export_gainmap_unavailable_peak`。
  zh-audit `--check` 全入册。

### KD-7 测试设计与 golden 门（T1..T4，RESEARCH §1.5/§8.2 钉法）

- **钉法裁定**（CI 黑盒漂移防假红）：golden 钉「容器字节结构 + 读回字典 +
  band 断言」，**禁字节级全量比对**（RESEARCH §8.2——字节级钉不住第三方
  黑盒，OS 升级假红）。测试面全部小尺寸合成平面（≤256px），Export bundle
  宿主既有 GPU 先例。
- **ExportGainMapTests（Export bundle，21 法）**：
  - validate 四门 + additive 零漂移（4 法，T1）：非 jpeg 拒（同法并档
    additive decode 零漂移双断言：无键旧 variant == false 且既有 validate
    面零 diff）/ drtOutput nil 拒 / peak<203 拒 / embedICC=false 拒。
  - capture 两态（2 法，T1）：flag∧tail 才捕获（面尺寸/headroom 载体断言）；
    非 flag job 的 StageOutput.hdrGainPlane == nil（零行为门）。
  - 容器字节面（4 法，T2）：MPF APP2 段在位（`FF E2 "MPF\0"` 字节扫）/
    ISO 21496 URN APP2 在位 / 主图 EOI 后有尾图（副图在位判定）/
    同目录无 tmp 残渣（L009 晋升）。
  - aux 读回字典（2 法，T2）：`CGImageSourceCopyAuxiliaryDataInfoAtIndex(0,
    kCGImageAuxiliaryDataTypeISOGainMap)` 返 dict 且 PixelFormat == 'L008'
    （单通道证明——OQ-4）+ W/H/BytesPerRow（== width）匹配。
  - rewrap 存活（1 法，T2）：primary XMP 含 `hdrgm:Version`（字节扫）∧
    rewrap 后 aux 读回仍 PRESENT（F5 门）∧ metadataPolicy .none 臂无 XMP
    但容器仍 UltraHDR（并入本法双断言）。
  - 后处理双旁路门（3 法，T2）：gain-map 臂产物 MPF 在位（strip 未跑——
    embedICC true 强制形态）/ gain-map 臂无双 XMP（mountXMP 未跑——APP1
    xap 头单实例）/ 非 gain-map job 后处理照旧（零 diff 负测）。
  - 质量旋钮 + tmp 晋升（2 法，T2）：q 显式传递 finalize 成功（E3 形）/
    晋升后目标文件在位。
  - 基面保真 + gain 语义带 + reimport（3 法，T4）：①基面解码采样点 ==
    纯 JPEGEncoder 编码同平面解码值（E2 方法；L048——比较前 decode 回
    linear，f32 产线常数升维）②合成平面 SDR 常量 + HDR = SDR×2^k → aux
    metadata GainMapMax 落 k 的 band（线性光喂入证明——E4 反证；CI 黑盒
    band 容差 DECISIONS 登记）③导出产物重导入走 M4-1 raster 链
    `decodeRaster` 成功、尺寸匹配、SDR base 解出（gain 忽略 = 正确降级）。
- **ExportGainMapPanelTests（App，6 法，T3）**：三态门（非 jpeg 禁 / 
  peak<203 禁 + hint 面 / jpeg+peak≥203 启用）+ 装配携带（RunAssembly
  gainMapHDR 进 variant）+ enqueueExportM2 联动（assembled 旗标在位）+
  默认关装配零 diff。

## read_first

1. `.work/gsd/phases/m6-3-ultrahdr/M6-3-CONTEXT.md`（裁决正本）+
   `RESEARCH.md`（§1.4 D 臂调用形 / §3 集成测绘 / §8.4 ICC 雷 / §7 OQ）
2. `LightamerCore/Sources/Export/ExportRecipe.swift`（ExportVariant :23-140
   字段/init/decode/validate :119-140 + ExportFormatSpec 面零 diff 红线）+
   `LightamerCore/Sources/Graph/DrtRecord.swift`（peakLuminance :352-355 /
   默认 100 :378）
3. `LightamerCore/Sources/Export/ImageIOEncoders.swift`（JPEGEncoder
   :178-197 / writeAtomically :159 / mountMetadata :143——零 diff 红线正本）+
   `LightamerCore/Sources/Export/ExportEncoder.swift`（registry :421-462 /
   ExportICCStrip stripICC :212 stripJPEGICC :246——零 diff 红线正本）
4. `LightamerCore/Sources/Export/ExportRenderer.swift`（TaskLocal 递缝范式
   :103-135 / StageOutput :263 / drtTail 消费 :430 / tailFormatFloatOverride
   :499-518 / encodeStage :621-694 后处理两段）
5. `LightamerCore/Sources/Export/ExportQueue.swift`（enqueue :196-260 / pump
   双腿 :415-473 / makeLegs :590-636）+ `ExportQueueContract.swift`
   （:207/:247 封存面零 diff 正本）
6. `LightamerCore/Sources/Pipe/PixelPipe.swift`（runTerminalTails :1126 /
   DrtTailAssembly :1707 / tailFormatFloatOverride :155/:381——capture 窄缝
   落点；M2-6 增量节「EOTF 之前的尾平面恒 working float32」正本 = AGENTS.md）
7. `LightamerCore/Sources/Export/XMPContainerInjector.swift`（APP1 注入形
   ——为何 gain map 臂必须旁路 mountXMP 的机制正本）+ `XMPWriter.swift` +
   `ExportChainBuilder.mountXMP`（XMP 载体单源——encoder rewrap 复用面）
8. `App/Sources/Lightamer/State/ExportState.swift`（enqueueExportM2
   :484-545 / m2DrtTail :466）+ `App/Sources/Lightamer/Export/
   ExportInspectorView.swift`（metadataColorSection :309 / drtReadout
   :352-378 / sdrSection :382+ / panel model :609+ / embedICC :652 /
   装配 :819）
9. AGENTS.md「M2-9 架构增量」（ExportVariant/drtOutput 强制联动/peak 闸）+
   「M2-6 架构增量」（DrtRecord/EOTF-box 尾段/尾平面格式）+「M4-1 架构增量」
   （raster 链/封存面解封先例）+「M3-3」（封存面清单）+ L057/L058/L009/L014/
   L041/L048 家族
10. `Scripts/test-direct.sh` + `.work/gsd/phases/m2-4-0-test-bundles/
    M2-4-0-BUNDLE-MAP.txt`（域模式与登记纪律；bundle 名 = `Export`）+
    `Tests/LightamerTests/ExportIccEmbedTests.swift`（ICC 面测试力学先例）+
    `Tests/LightamerTests/DrtTailTests.swift`（pipe harness + fence 形）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；
  front-matter `files_modified` 为界）；新测试文件随各自任务 commit 登记进
  BUNDLE-MAP（E2）+ `Project.swift` 对应数组（L041：`tuist generate` 恒为该批
  最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 =
  `Scripts/test-direct.sh --bundle Export` / `--bundle App`（直启宿主）；
  **全套 `--all` 需 orchestrator 批准，本 plan 收口轮才申请**；App bundle 轮前
  删孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1 挂账 #6
  先例，跑前删跑后不复活即净）。
- **资源监控**（AGENTS）：测试宿主与 GUI 实例同名 Lightamer——清理进程前核
  parentage（M2-7-3 事故教训）。
- **L009**：一切落盘走同目录 tmp→原子晋升（CI 直写 URL 的 tmp 化 = KD-4 钉死
  面）；**L014**：测试侧 GPU 读回走既有 fence 形（产线 GPU→GPU 交接免
  fence——KD-2 注记）；**L048**：像素比较 decode 回 linear + `Double(Float(x))`
  产线常数升维。
- **L070**：不 push（推送收敛主会话）；零历史手术。
- 零 diff 红线自证（T4）：`git diff <基线>..HEAD -- LightamerCore/Sources/
  Export/ImageIOEncoders.swift LightamerCore/Sources/Export/WebPEncoder.swift
  LightamerCore/Sources/Export/ExportEncoder.swift
  LightamerCore/Sources/Export/ExportQueueContract.swift` 文件级零命中 +
  `git diff` ExportRecipe.swift 内 ExportFormatSpec 面 + PixelPipe diff 范围
  申报（仅 capture 窄缝）+ xcstrings/UserDefaults 零新增 + dependencies 块
  零 diff。
- 中文标注（待核/待定/待补）一律显式；无源待核项入 DECISIONS 待供件清单。

## Tasks

### T1 渲染面：variant 字段 + validate 门 + capture 窄缝 + box 交接（KD-1/KD-2/KD-3）

- read_first 2/4/5/6 → `ExportVariant.gainMapHDR` + validate 四门（含
  embedICC 组合门）→ `PixelPipe.linearGainCapture` 窄缝（解封申报面）→
  `ExportRenderer.renderStage` capture 装配 + `StageOutput.hdrGainPlane` →
  `ExportQueue.makeLegs` box stash/consume/cleanup。
- 验收：`ExportGainMapTests` 前 6 法（validate 4 + capture 2）全绿；构建零
  警告新增；既有 Export 套件原样绿（零回归初证）；PixelPipe diff 范围 =
  capture 属性 + 单调用位（git diff 自证入任务报告）。

### T2 CI 编码腿：ExportGainMapEncoder + encodeStage 分支 + 后处理门（KD-4/KD-5）

- read_first 3/4/7 → `ExportGainMapEncoder.swift` 新建（CI 写路 + tmp 晋升 +
  rewrap + EXIF probe + 203 常量）→ `encodeStage` additive 参数与分支 +
  strip/XMP 双旁路门 → queue encodeLeg 接线。
- 验收：`ExportGainMapTests` 中 12 法（容器 4 + 读回 2 + rewrap 1 + 后处理门
  3 + 质量/晋升 2）全绿；**EXIF probe 结论落 DECISIONS 双态登记**（OQ-2）；
  ImageIOEncoders/WebPEncoder/ExportEncoder/ExportQueueContract 四文件
  `git diff` 零命中（红线初证）。

### T3 M2 页 UI：checkbox 三态门 + 装配联动（KD-6）

- read_first 8 → panel model 字段 + checkbox 与两文案 + RunAssembly/
  enqueueExportM2 联动 + :350 陈旧注记更新 + 4 键 xcstrings 尾块纯插入。
- 验收：`ExportGainMapPanelTests` 6 法全绿；zh-audit `--check` 4 新键全入册
  PASS；UserDefaults 零新增（grep 自证）；非 jpeg 格式选中态 UI 面零 diff
  （门谓词负测）。

### T4 集成 golden + 读回兼容 + 红线自证（KD-7 尾）

- read_first 10 → `ExportGainMapTests` 尾 3 法（基面保真 E2 形 / gain 语义
  band / reimport raster 链）+ 零 diff 机检族（四文件 + ExportFormatSpec 面 +
  PixelPipe 范围申报 + xcstrings/UserDefaults/dependencies）。
- 验收：27 法全绿（Export bundle 21 + App 6）；机检行全绿截屏入任务报告；
  分账 Export 353+21 / App +6 对表。

### T5 收口

- SUMMARY（任务序/bundle 分账/对账链）+ DECISIONS（EXIF probe 双态结论 /
  PixelPipe 解封申报 / band 容差与 CI 黑盒漂移注记 / headroom<203 默认禁用
  UX 注记 / box token 覆盖写语义）+ `gui-acceptance/m6-3/MANIFEST.md`
  （Manual-Only：Preview/Photos HDR 目检 + sips + Chrome/Android 如有 +
  LightCraft 产物互读可选行）+ AGENTS.md M6-3 架构增量节 + ROADMAP M6-3 行
  ✅ + REQUIREMENTS ALCE-03 兑现注记 + GOAL-STATE 续接点 + TODO 同批 +
  `M6-3-01-ACCEPTANCE.md`（双重验收：zcode subagent 独立验收 PASS 后 →
  **串行** omp 二次验收，严禁并发——computer-use 单实例；FAIL 回注修复批后
  重走验收）。
- 验收：定向轮 `--bundle Export` / `--bundle App` 全绿（exit 0 + 零 MEMFAIL，
  SC 分账对表；拼写 = test-direct.sh 注册表 `BUNDLES=(IOP IOPParity Layers
  Library Sessions Export App)`）；**申请全套 `--all` 批准轮**（预期
  3749..3755/24/0，基线 3725/24/0 亲核在 plan 头）。

## 验收标准（AC 总表）

1. **OQ 生效值①（HDR 面取平面点）**：capture 点 = DRT 尾 EOTF-box 前线性级
   （gain 语义 band 测试间接证明线性光喂入；PQ 码值面结构性不可达——capture
   点单源）；独立 EDR 链零存在（无第二渲染链文件/装配面）。【T1/T4】
2. **OQ 生效值②（EXIF probe 先行）**：probe 结论入 DECISIONS 双态登记；
   probe 失败形态下产物容器/aux/XMP 全存活且无 EXIF（降级负测，若 probe 成功
   则改为 EXIF 在位正测）。【T2】
3. **OQ 生效值③（hdrgm 档位）**：primary XMP 含 `hdrgm:Version` + rewrap 后
   MPF/ISO APP2/aux 读回全 PRESENT（F5 门）；LightCraft C 路零代码零 NOTICE
   （`git log`/grep 无移植面佐证）。【T2】
4. **OQ 生效值④（单通道）**：aux 读回 PixelFormat == 'L008' 且
   BytesPerRow == width；`hdrGainMapAsRGB` 全仓零出现（grep 机检）。【T2】
5. **OQ 生效值⑤（UI 位）**：SDR 节 checkbox 三态门机检（6 法）+ 不可用文案
   两态 + enqueue 联动 + 203 阈值与 Core 常量同源。【T3】
6. **OQ 生效值⑥（无新 tag）**：formatName 恒 "jpeg"（无新 tag 常量/分支——
   grep 机检）+ 同池冲突递增行为不变（既有 Namer 测试原样绿）。【T3/T4】
7. **零回归门**：ImageIOEncoders/WebPEncoder/ExportEncoder/ExportQueueContract
   四文件级零 diff + ExportFormatSpec 类型面零 diff + ExportICCStrip 本体零
   diff + 非 gain-map 路径零 diff 负测 + 既有 Export 套件原样绿 + 既有
   reimport/图库路径零触。【T2/T4】
8. **SC 数字门**：Export 353+21 / App +6 定向对表；全套预期
   3749..3755/24/0（批准轮对账，基线 3725/24/0 亲核记录在 plan 头）。【T5】

## 风险与边界

- **CI 黑盒行为漂移**：gain 计算/元数据由 CI 内部决定（D1 亲验值在案；OS
  大版本可能微调）——golden 钉容器结构 + 读回字典 + band，禁字节级全量
  （KD-7 钉法；假红 = band 容差 DECISIONS 调整点）。
- **headroom<203 默认禁用**：默认 record peak=100 → checkbox 默认灰 + hint
  （诚实语义：SDR 参考白下无 HDR 余量）；UX 预期管理注记入 DECISIONS。
- **ExportQueueContract 封存约束**：box 交接 = 封存面下的最小 additive 形；
  若 checker 裁 box 形不可接受 → 备选 = encode 腿内二次尾段回放（缓存命中，
  成本低）——切换属 KD-3 偏差，须 checker 会审裁定非 executor 自行切换。
- **EXIF probe 不可达**：v1 无 EXIF = 已裁降级（OQ-2）非缺口；挂账登记。
- **外部校验缺口**：exiftool 本机不可用、Android/Chrome 设备环境不保证 →
  Manual-Only 走查批（MANIFEST 可选行显式标注，不可达不阻断收口）。
- **纹理跨腿交接**：owned-copy 防 pool 复用；cancel/retry 清理覆盖（KD-3）；
  同设备 CI 上下文 + Metal 默认 hazard tracking。
- **APP bundle 贴线**：IOP/IOPParity 本批零触碰（预期零漂移）；Export bundle
  新法全小尺寸合成面（内存增量 ≪ 8G 门）。

## Checker 关注点（plan review 用）

1. **MPF 偏移脆弱面**：任何对产物文件的段级后处理都会破坏 MPF 绝对偏移——
   机检 encodeStage gain-map 臂 strip/XMP 双旁路 + `XMPContainerInjector`
   不得被 gain map 臂复用（APP1 注入同样移偏移）；非 gain-map 臂零 diff。
2. **contract 零 diff 交接形**：ExportQueueContract 封存面下的 box 载体是否
   成立（备选 = encode 腿二次尾段回放）；box 的 retry/generation/cancel
   生命周期覆盖是否完备（token 覆盖写语义已登记）。
3. **PixelPipe 解封申报范围**：diff 是否严格限于 capture 属性 + 单调用位；
   有无借道扩面（M3-3 清单纪律）。
4. **203 双源风险**：validate 门 / UI 门 / encoder headroom 三消费点是否全走
   `sdrReferenceWhite` 单源；默认 peak=100 → checkbox 默认灰的 UX 是否与
   OQ-5 生效值文案一致。
5. **E4 红线的测试可证性**：gain 语义 band 法是否足以反证「PQ 码值直喂」未
   发生（capture 点结构性排除 + band 断言双层）。
6. **CI 黑盒钉法**：有无字节级全量断言混入（假红源）；band 容差是否登记
   DECISIONS。
7. **validate 门与 UI 门的语义一致**：非 jpeg / drtOutput nil / peak<203 /
   embedICC=false 四门在 UI 端的可用门是否同集（UI 禁用 + validate typed 拒
   双防线，无「UI 可用但 validate 拒」的矛盾态；embedICC 门在 UI 端由
   「embedICC toggle 默认开 + gain map 档文档形」承载，检查有无裸露矛盾面）。
8. **SC 对账**：两新文件法数（21+6）与 front-matter `estimated_tests`
   "+24..30"、全套预期 3749..3755 三处一致。

## 提交约定

- T1 `feat(core): gain map export variant gates and drt linear plane capture`
- T2 `feat(core): iso 21496-1 gain map jpeg encoder on the ci write path`
- T3 `feat(app): ultra gain map toggle on the m2 export page`
- T4 `test(export): gain map container golden and reimport compatibility`
- T5 `docs(m6-3): close the ultrahdr batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。
