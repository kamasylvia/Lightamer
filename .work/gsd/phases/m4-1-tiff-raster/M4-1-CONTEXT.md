# M4-1-CONTEXT — TIFF 栅格开发链（RASTER-IN-01 收窄版）

> Phase M4-1 discuss/research 定稿（2026-10-10）。技术正本 = 同目录 `RESEARCH-NOTES.md`。
> charter 正本 = ROADMAP §Milestone 4 M4-1 行；需求正本 = REQUIREMENTS RASTER-IN-01
> （2026-10-08 收窄注记：TIFF only，EXR/JPEG/PNG 移出）+ ALCE-02（推迟注记）。
> **C 档第 1 停**：本文 OQ 节 = 用户裁决点；裁决后再进 plan。

## Scope

**入**：TIFF 导入即开发（ImageIO 原生 8/16/32F + 内嵌 ICC 解析 → display-referred 输入经
ACES 2.0 逆变换进编辑管线）；HDR TIFF（旗标 → EDR 面）；导入类型选择器（上游 #264 形态
收窄 = RAW + TIFF 两类）。

**不出**（红线）：JPEG/PNG 图库可浏览现状零回退、不进开发链；EXR/ALCE-02 推迟；导出矩阵
六格式零改动；OpenDRT 逆链不做（上游同界）。**defer 候选**：Input profile 手动覆盖
（Alcedo D5）——首波 Auto（文件即真相）+ 面板只读 readout。

## 现状一句话

TIFF 今天已在 `RAWDecoder.decodeRaster`（CGImageSource，位深保真 02-06 宿主已证）→
CIContext working-space（linear Rec2020）渲染 → 管线把 display-referred 数值当 scene-linear
消费、尾段 gamma 直出——「栅格经 DRT 逆链进开发管线」从未形式化，此即 M4-1 本体。
逆变换所依赖的 forward（aces-core v2.0 移植）与表族 M2-6 已交付，`outputTransform_inv`
是 M2-6-2 明注预留的移植对象。

## 设计推荐形（详见 RESEARCH-NOTES §3）

新 TIFF 开发分支：描述解析（ICC/cicp/float-无ICC/sRGB 默认 + usable 三检查）→ 原生字节
解码（保源 primaries，绕开 CI 色彩管理渲染）→ Metal 输入腿（linearize TRC → ACES 2.0
inverse [limiting=源 primaries/peak]，Float64 authority + kernel mirror，M2-6-2 范式）→
develop-output 级缓存（滑动不重跑）→ 既有 v50 链/DRT 尾原样消费；float 无 ICC = scene-linear
矩阵分支。LUT-based ICC 单独走 CI 腿转换（零第三方，ColorSync 等价 lcms2 形）。持久化 =
零 schema 变更（描述 decode-time 重解析，文件即真相）。导入面 = 类别掩码（raw/tiff）+
checkbox 计数 UI + UserDefaults 记忆；三模式 move/copy/link 零特例。

## Open Questions（C 档第 1 停裁决点）

### OQ-1：raster 文档的默认 DRT 形态（含 `DrtEotf` 是否加 `srgbPiecewise`）

- **A（推荐）= Alcedo D2 同形**：TIFF 文档默认挂 DRT record（method=aces20 + limiting/
  peak/EOTF 随源描述；raster 默认跳过 defaultLook mint）；配套给 `DrtEotf` 增
  `srgbPiecewise` additive case（M2DRT-06 注册语义的编译期破 switch 扩展路径；M3-3 封存
  面解封注记随 plan 申报）。语义收益：开图所见 ≈ 源（inverse→forward 闭环），编辑语义
  全形式化。
- **B = 维持我方 pristine 语义**：raster 无 DRT 尾（`.sdrGamma` 直通，linearized 值经
  gamma 2.2 出屏）——开图观感近似源但非闭环，HDR TIFF 无默认 EDR 臂可走。
- **推荐 A**：charter「经 DRT 逆链进编辑管线」的形式化语义只有在 A 下闭合；显示变换资产
  （M2-6）齐备，增量 = 一个枚举 case + 默认 record 装配点。代价 = 与「pristine = 无 DRT」
  的既有语义多一条 raster 例外（需在 AGENTS 增量节写清）。

### OQ-2：管线分支——新 TIFF 开发分支 vs 扩展现有 CI 通路

- **A（推荐）= 新分支**：原生解码保源 primaries（逆变换 limiting gamut 必须源域；CI
  working-space 渲染已做 primaries 映射，数值不可逆回收——RESEARCH §3.1 论证），u8/u16/
  32F 原生深度上传 + 自持 linearize/inverse kernel。JPEG/PNG 既有通路零回退。
- **B = CI 通路扩展**：留 CI 渲染再补逆盒——实现省，但 limiting 语义错位（B 下逆变换
  只能按 Rec2020 limiting，源为 sRGB/P3 时 gamut/色调偏移），且 8-bit 源提前膨胀成 float32
  CI 平面。
- **推荐 A**（B 的语义缺陷是结构性的，不是调参可救）。

### OQ-3：逆变换实现来源——aces-core `outputTransform_inv` vs OCIO 2.5.1 inverse

- **A（推荐）= aces-core 移植**：Apache-2.0（NOTICE 族内）；与我方 M2-6 forward **同源**
  ——round-trip 对自家 forward 的紧度是上游（OCIO 逆 vs 改装 forward，接受面偏差）拿不到
  的一致性优势；Float64 authority + kernel mirror 是已验证范式；`outputTransform_inv` 在
  M2-6-2 文件头明注预留。
- **B = OCIO 2.5.1 inverse 移植**（Alcedo D1 选型）：BSD-3； OCIO 是其 forward 的偏差
  （Hunt fade/RGC/362 表）的逆；对我方 forward 无同源一致性，round-trip 退化为上游接受面。
- **推荐 A**；RGC 逆不移植（上游同界，偏差登记；OQ-1 采 A 时可加「raster 默认 record 关
  RGC」消解双压缩叠加，随裁决定）。

### OQ-4：HDR TIFF 的 EDR 语义

- 旗标判定推荐：transfer ∈ {st2084, hlg} 或（scene-linear float32 且内容探针 max > 1.0）。
- 默认视口推荐：走 M2-6 DRT-HDR 既有臂（record encoding=st2084 → 16F + EDR + PQ
  colorspace；peak 贯通源描述）——**新建面趋零**，手动 EDR 互斥纪律零扰动。HDR 徽标
  （图库面）defer。
- 备选：非 DRT 直接 EDR-linear 展示（与手动 EDR 开关语义打架，不推荐）。

### OQ-5：类型选择器默认值与记忆键

- 推荐：**默认 raw+tiff 双开**（上游「五类全开」的收窄镜像）；新键
  `library.import.categories`（掩码/JSON）记忆 last selection；`library.import.rawExtensions`
  （RAW 细粒度白名单）**保持独立正本不动**——两键正交（类别开关 ≠ RAW 扩展编辑）。
- 备选：把 tiff 塞进 rawExtensions——否（语义污染：TIFF 不是 RAW，过滤面/文案/审计全歪）。

### OQ-6：开发链与既有非 RAW 图库通路的关系

- 推荐：**TIFF 编辑链路整体切新分支**（decode UTI 分流），`decodeRaster` 的 TIFF 臂退役
  但代码保留（dt 禁用纪律同款）；JPEG/PNG/HEIC/WebP 照走 CI 通路；缩略图 Tier A（未编辑
  TIFF）走 ImageIO 缩略解码、Tier B（已编辑）经 pipe 新腿（bucket-uniform）。
- 备选：TIFF 保留 CI 通路仅加读出 UI——即 OQ-2 B，不推荐。

### OQ-7：import 三模式适配面

- 推荐：**零特例**——move/copy/link 对 TIFF 是纯字节运输 + `.lra` 随行纪律照旧；link 模式
  下外部替换源文件 → 描述 decode-time 重解析跟随（缓存经 contentDedupeID 的 mtime 腿翻新），
  登记为 by-design。仅新增进度计数分账（`excludedType` vs 既有拒绝面，上游两计数对应物）。
- 无实质备选（三模式机制 M2LIB-07 已闭环，TIFF 无新增运输语义）。

## Wave 草案

W1 描述+fixture+ICC golden → W2 逆变换 Float64+golden → W3 解码腿+kernel+缓存 →
W4 HDR/EDR+默认 record → W5 导入面+编辑面门控 → W6 round-trip 收口+全套回归。
（每 wave 独立实现→自测→双验收，波内 plan 拆分归 plan 环。）

## 验收形态（charter SC 对表）

TIFF 开发链 round-trip ✓（§RESEARCH 4.4）+ ICC 语义 golden ✓（4.1/4.2）+ HDR TIFF EDR ✓
（4.4）；SC 数字门 = 期定（plan 定）。回归红线：forward `Aces2Kernels.metal` 零 diff、
IOP/IOPParity 逐位基线、JPEG/PNG 通路零回退断言。

## 参考

- Alcedo `raster_image_input_plan.md`（R1–R5 完成记录 + macOS 验证教训）——GPL 只读。
- aces-core v2.0 `Lib.Academy.OutputTransform.ctl`（Apache-2.0，M2-6 同源）。
- 我方锚：`Decode/RAWDecoder.swift`、`Metal/CIContextPool.swift:144`、`Pipe/Drt/Aces2Reference.swift`、
  `Pipe/Drt/DrtEotf.swift`、`Graph/DrtRecord.swift`、`Export/ImageIOEncoders.swift:231`、
  `Library/ImportFilter.swift`、`Library/LibrarySchema.swift:235`、`App/.../Library/ImportModeDialog.swift`。

## 裁决记录（用户回批 2026-10-10）

**OQ-1..7 全部按推荐采纳**：①raster 默认 DRT = Alcedo D2 同形（aces20 record 随源 + DrtEotf srgbPiecewise additive）②新 TIFF 开发分支 ③逆变换 = aces-core 移植（RGC 逆不移植）④HDR 旗标 = PQ/HLG TRC 或 float>1.0，图库徽标 defer ⑤选择器默认双开 + `library.import.categories` 新键 ⑥TIFF 整体切新分支、旧 CI 臂退役保留、JPEG/PNG 零回退 ⑦import 三模式零特例。
