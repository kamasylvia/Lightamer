# Phase 8 Research: yiyin Border/Watermark Panel（印框/水印面板移植）

**Researched:** 2026-09-25
**Confidence 汇总：** yiyin 功能面拆解 = High（Electron/Svelte/sharp 正本源码逐文件核过，合成管线七步、EXIF 格式化、模板引擎、字体管理全部 file:line 实证）；管线落位（borders 76/watermark 77 终端段）= High（V50Order 现表槽位在、colorout→gamma 窗口语义与 dt 同 seam、LayerCompositeDriver 终端段识别为唯一改动点）；布局数学参考轨 = High（yiyin 布局全为整数/浮点确定性运算，float64 镜像可行）；文字位图 parity = Med（yiyin 文字走 Chromium canvas2D，与 CoreText 位图不可逐像素对齐——按 L017 纪律分流：几何/字符串/版式精确钉，位图自建 CoreText 基线）；性能数字 = Med（估算，plan 期 benchmark 落账）。

> **编号口径注记**：本 Phase 在 `phases/` 执行序编号为 08，对应 `.planning/ROADMAP.md` §Phase 10（:165-179，YIYIN-01..08）。ROADMAP 编号 §Phase 8（HDR/Stacking）尚未执行（`.work/GOAL-STATE.md:69` 曾记「下一程 = Phase 8 HDR」）；以编排指令（phases/ 执行序）为准，两套编号在本文档中分开引用。

---

## Summary

Phase 8 = 8 个需求（YIYIN-01..08），把独立 Electron 应用 yiyin（壹印）的印框/水印能力移植为 Lightamer 原生一等公民面板。核心结论：

1. **功能面拆解（§1）**：yiyin 的「印框」= 七步合成管线（exif 读取 → 背景尺寸计算 → 文字行位图 → 主图 webp → 内容高度 → 背景（纯色/模糊）→ 圆角阴影遮罩 → composite）——背景画布扩展 + 主图占宽比 + 圆角 + 投影 + 模糊/纯色背景 + 底部居中文字行堆叠，全部参数以**背景高度百分比**表达（分辨率无关）。无内阴影/描边；「阴影」= 圆角矩形 alpha 的高斯模糊投影。
2. **管线落位（§2）**：两个终端 iop 模块——`borders`（76.0，画布扩展+背景+圆角/投影）与 `watermark`（77.0，模板文字行+品牌 Logo）——槽位已在 V50Order 现表（`V50Order.swift:171-172`），插在 colorout 70.0 之后 gamma 78.0 之前 = **display-referred 域**（dt 同 seam；yiyin 本就是 sRGB 输出）。唯一管线改动 = LayerCompositeDriver 的终端段识别从 `opName ∈ {colorout, gamma}` 扩为 `iopOrder ≥ 70.0` 尾窗。渲染分工：布局/几何 = float64 Swift + Metal blit；文字排版 = CoreText；Logo 矢量 = CG PDF 渲染。纯原生零 Web 依赖。
3. **数据模型（§3）**：两个模块的 `Params: Codable & Hashable` 直进既有 `ModuleInstance.paramsData` 通道——**sidecar schemaVersion 2 零升级**（07 移交「AI 参数不落盘」同构的反例：yiyin 参数必须落盘，走的是 Phase 2 既有 params 通道）。预设 = Phase 12 `.lightamer-preset` 的天然消费者（instances 子集捕获）；用户字体/Logo 资产走 Application Support + 名称+StableHash 引用（RasterMaskStore 旁挂模式）。
4. **EXIF 层（§3.3）**：`CaptureMetadata`（`CaptureMetadata.swift:8-93`）缺 yiyin 所需 6 字段（等效焦距/曝光档位/曝光补偿/测光/白平衡/镜头厂）——additive optional 扩展 + RAWDecoder ImageIO walk 扩列（`RAWDecoder.swift:310-331`）；**exiftool 二进制不移植**（ImageIO 已覆盖，Phase 1 SC#5）。字段格式化（快门分数/日期/测光中文化）与 model-map（Sony α/Nikon ℤ/罗马数字）全量 Swift 直译 + 表驱动单测。
5. **批量导出联动（§4）**：EXP-05（Phase 11）= 导出管线在 colorout（导出色彩空间）后、编码前跑同两个模块实例——参数同源（同一 ModuleInstance）**结构上保证**预览/导出一致；本 Phase 只交付模块与面板 + 预设接口，导出接线归 Phase 11（YIYIN-08 的 DPI/长短边配置模型在本 Phase 建好，应用在 Phase 11 EXP-03）。
6. **性能（§5）**：PREVIEW 拖 yiyin 参数 = 上游全 cache hit + 重跑 colorout→gamma 尾窗 3 模块（borders 平面 ~1.23× 面积 + 文字行位图 ~56px 高 + gamma），拖动预算内；模糊背景腿输入是主图（内容哈希寻址，参数无关不失效）+ 降采样 proxy blur（复用 Common/GaussianBlur）；文字排版缓存 key = (模板串, 字体属性, 行高)。
7. **验证（§6）**：轨 A 参考 = yiyin 正本模块可经 node harness 直接跑出 PNG（sharp 管线无 GUI 依赖）——但按 L017 分流：**布局几何（画布尺寸/主图位置/文字行位置，全整数运算）= float64 Swift 镜像逐值断言 + yiyin 参考抽查对照**；文字位图 = CoreText 自基线 golden；EXIF 字符串/品牌归一化 = 表驱动单测；轨 B 恒等（无 yiyin 实例零增量逐字节）+ sidecar round-trip + GUI 验收轮（PLAYBOOK）。
8. **UI（§7）**：Inspector 单面板「印框/水印」双节（编辑 borders+watermark 两实例），主视口即预览（管道现成）；字体管理子视图（系统字体 + 用户导入 .ttf/.otf，CTFontManager 本地注册）；Logo 明暗双变体自动选（yiyin `Make` 字段语义）。L025 zh 标签纪律。
9. **风险（§8）**：最高优先 = **77.0 槽位所有权**（ROADMAP §Phase 8 SC#4 的「watermark iop (order 77)」与本 Phase yiyin watermark 77.0 相撞）与 **YIYIN-03/04 的「位置/旋转」措辞超出 yiyin parity 面**（yiyin 的 Logo/文字是模板行内元素，固定底部堆叠，`IPosition` 字段预留未实现）——均需用户裁决（Open Questions 1/3/2）。字体授权零风险（系统 + 用户上传，不内嵌第三方字体）。
10. **plan 拆分建议 3 个（§9）**：8-1 印框模块+终端段扩展 → 8-2 水印模块+文字/字体/品牌系统 → 8-3 面板集成+签核。总量 ~14-18 T。

---

## Implementation Approaches

### 1. yiyin 功能面拆解（正本源码，全部 file:line 核过）

#### 1.1 合成管线总览（`electron/src/modules/image-tool/index.ts:138-173` genWatermark 七步）

```
init(:92-136)            sharp(path).rotate()  ← EXIF 方向已直正；metadata；bg_rate 重置宽高比(:110-120)；
                         landscape 竖转横 = resetW/resetH 互换(:123-131)；exiftool 读取(:134-135)
clacBgImgSize(:472-506)  画布尺寸：内容高驱动；主图宽/画布宽 > main_img_w_rate(默认90%) 时等比扩画布(:494-497)
genTextImg(:231-286)     → 渲染进程 TextTool（见 1.3）产出文字行 PNG（base64 回传）
genMainImg(:213-229)     主图 lossless webp 中间件
calcContentHeight(:508-546) contentH = 主图高 + mainImgOffset(上下边距×2，有文字时 ×3/4 + textButtomOffset=bgH×0.027)
genBgImg(:197-211)       纯色(genSolidImg :392-403)或模糊(genBlurImg :356-390：3025² proxy → ffmpeg boxblur → resize)
genMainImgShadow(:416-467) → 渲染进程 ImageTool（见 1.2）产出圆角+阴影 mask PNG
composite(:288-348)      白底画布(bg.w×bg.h, 3ch) → 主图居中 → mask 居中叠加 → 文字行自底向上堆叠（水平居中，
                         首行 top = bg.h − text.h，逐行上叠 :300-319）→ JPEG/WebP 编码（保留 density）
```

- **边距模型**：无独立 margin 参数——上下边距 = max(mini_top_bottom_margin, 阴影高度)（`calcContentHeight:515-523`），左右边距由 `main_img_w_rate`（主图占背景宽度百分比）间接表达。
- **圆角/阴影公式**（`web/modules/image-tool/index.ts:50,63`）：`blur = 主图高×(shadow/100)`（默认 6）、`cornerRadius = 主图高×(radius/100)`（默认 2.1，上限 50）。
- **暗背景自适应蒙层**（`web/modules/image-tool/index.ts:28-46`）：模糊背景模式下按平均亮度（`calcAverageBrightness :96-108`，RGB 均值）分四档叠半透明灰罩，突出主体。
- **输出**：JPEG quality 1-100 或 WebP；`origin_wh_output` 在 OutputOption 中声明（`interface.ts:44-48`）但**渲染路径未消费**（yiyin 自身未实现）——YIYIN-08 的输出尺寸配置在 Lightamer 侧为真实现（§4）。

#### 1.2 圆角+阴影遮罩（`web/modules/image-tool/index.ts:18-93` genMainImgShadow）

渲染进程 canvas2D：底 = 背景图 + 亮度蒙层 → 圆角矩形路径（arcTo :65-75）填充黑色（阴影源）→ 同路径 clip 后 clearRect（挖空主图区）→ 产物 = 「带高斯模糊阴影的圆角挖空 mask」PNG，合成时叠在主图上（`composite:297` gravity center）。**Lightamer 等价物**：Metal 侧 rounded-rect SDF alpha + 复用 Common/GaussianBlur 得投影平面，一次 dispatch 合成——无 PNG 中间文件（那是 yiyin 的进程边界产物）。

#### 1.3 文字系统（`web/modules/text-tool/index.ts` + `web/modules/temp-field/index.ts`）

- **模板引擎**：模板串 `{Field}` 占位（`common/utils/temp.ts:1-22` matchFields，正则 `\{([A-Z0-9]+)\}`）；每模板 = `ITemp {key,name,temp,use,type:'system'|'custom',verticalAlign:'baseline'|'center',font,position?}`（`common/const/def-temps.ts:3-13`）。系统预置 3 模板：`{Make} {Model}`（size 3）/ 等效焦距参数行（size 2.2）/ 原始焦距参数行（`def-temps.ts:15-64`）。
- **字号语义**：`size` 是**背景高度的百分比**——`fieldTemp.font.size = Math.round(bgHeight × (size/100))`（`temp-field/index.ts:26`）、模板字号同式（`:47`）。这是分辨率无关的关键，Lightamer 原样继承。
- **字段填充**（`temp-field/index.ts:58-107` fillTempFieldInfo）：按 EXIF 值填充；`Make`/`LensMake` 字段自动尝试品牌 Logo SVG（`{make}-w.svg` 白 / `{make}-b.svg` 黑，:80-93；模糊背景用白 Logo、纯色背景用黑 Logo——`text-tool/index.ts:62-69`）；字段可 `forceUse` 自定义值/类型（text|img）覆盖（:97-103）。
- **行位图合成**（`text-tool/index.ts:126-267` createTextImg）：逐 slot measureText（文字）或按 `'QSOPNYuiyl90'` 伪串 ascent 估算 Logo 高（:199-202）；canvas 高 = max(行 ascent+descent+2×text_margin, 最大字号)（:170-175）；行宽 = slot 宽度和 + 两侧 30px pad（:176-249）；基线/居中两种 verticalAlign（:204-241）；字号取 slot 字体与模板字体的最大值（getMaxFontParam :302-320）。
- **字体级联**（`text-tool/index.ts:269-300` getFont）：`bold italic size family, PingFang SC`——用户字体名优先，PingFang SC 兜底。
- **`IPosition`（top/bottom/left/right）与 `height` 字段在 ITemp 上预留但渲染路径未消费**（`def-temps.ts:9-12`；composite 恒为底部居中堆叠）——YIYIN-03/04 的「位置/旋转」需 Lightamer 新实现（Open Question 2）。
- **文字行顺序**：模板列表顺序 = 堆叠顺序，列表末行最靠底（`composite:302-317` 逆序上叠）。

#### 1.4 EXIF 字段与格式化

- **15 个字段**（`common/const/def-fields.ts:1-17`）：个性签名（自由文本）/Logo（Make）/型号/镜头 Logo/镜头型号/快门/光圈/ISO/焦距/等效焦距/档位/拍摄日期/曝光补偿/测光模式/白平衡。
- **读取**：exiftool 二进制优先、exif-parser 回落（`electron/src/modules/exiftool/index.ts:37-62`）；Lightamer 直接用 ImageIO（Phase 1 已验 RAW EXIF 全可读）。
- **格式化**（`:82-168`）：ExposureTime <1s → `1/{round(1/v)}`（`base.ts:32-41`）；DateTimeOriginal → `yyyy/MM/dd hh:mm:ss`（剔次秒/时区 `:115-129`；formatDate 引擎 `electron/src/utils/date.ts:8-44`，规则 y/M/d/h/m/s/q/S）；ExposureProgram → 单字母缩写 M/P/A/S 或 Auto（`:106-113`）；WhiteBalance Auto/手动（`:131-138`）；MeteringMode 六种中文（评价/点/局部/平均/中央重点/斑马 `:140-165`）。
- **品牌归一化**（`common/modules/exif-format/`）：Make 剥 `CORPORATION` + 首字母大写（`index.ts:34`、`base.ts:11-13`）；Sony `Model.replace('ILCE-','α').toLowerCase()`（`sony.ts:4-6`）；Nikon `Z→ℤ` + `Z_6_II` 型下划线拆段 + 数字段转罗马数字（`nikon.ts:6-20` + `web/util/util.ts:3-30` toRoman）；通用 filter 做数学字母 Unicode 转换（`charToNumberChar`，起始码点 0x1D63C，`web/util/util.ts:32-54`）。`web/util/model-map.ts:11-43` 是同逻辑的 filter 表（渲染端副本）。

#### 1.5 字体管理与资源

- **用户字体**：addFont 把 .ttf/.otf 拷入 `font.dir`（文件名 = md5(源路径)）、`font.map[name] = fileName` 持久化（`electron/src/router/query.ts:36-62`）；渲染端 FontFace 加载（`web/util/util.ts:96-121`）。仅本地不联网（YIYIN-05 语义即此）。
- **Logo 库**：`web/public/logo/` 26 个 SVG = 13 品牌（canon/dji/fujifilm/hasselblad/leica/nikon/olympus/panasonic/pentax/ricoh/sigma/songdian/sony）× 明暗两变体；上传自定义字段图片走 `uploadExifImg` 存 staticDir（`query.ts:64-`）。
- **持久化**：全局单配置 JSON（`IConfig`，`electron/src/interface.ts:5-61`；默认值 `web/store/config.ts:10-42`：main_img_w_rate 90 / text_margin 0.4 / radius 2.1 / shadow 6 / bg_blur 100 / solid #fff / origin_wh_output true）。

#### 1.6 预览与队列

- **预览**：`genPreview` 全管线跑一遍出 base64 JPEG（quality 70，`image.ts:46-64`；`image-tool/index.ts:175-195`）；新预览请求 cancel 旧任务（单飞）；配置变更 300ms debounce 刷新（`actions/index.svelte:31-41`）。Lightamer 对应物 = 管道 PREVIEW 桶（视口即预览，无需独立预览图）。
- **批量**：Queue（concurrency 1，`electron/src/modules/queue/index.ts`）+ 每任务 progress 事件/cancel/失败上报（`image.ts:22-40`）。Lightamer 对应 = Phase 11 EXP-06 队列，本 Phase 不建队列。

### 2. 渲染架构选型

#### 2.1 落位：终端段两个模块（display-referred seam，dt 同构）

- 槽位已在表：`colorout` 70.0 → **`borders` 76.0** → **`watermark` 77.0** → `gamma` 78.0（`LightamerCore/Sources/Foundation/V50Order.swift:166,171-173`，dt `iop_order.c` verbatim 移植）。dt 参考实现 `src/iop/borders.c:429-470`（modify_roi_out 画布扩展：aspect/size 基准边选择）、`src/iop/watermark.c`（仅作 ROI 语义参考；**功能正本是 yiyin**，dt watermark 的 SVG/position 面不移植）。
- **为什么在 colorout 之后**：yiyin 是「出图前的最后一步」，语义作用在成片域（sRGB 观感域）；dt 把 borders/watermark 放 colorout 与 gamma 之间是同一判断。LayerCompositeDriver 现架构（1+N+1：base 链子 run → 逐层合成 → 终端段子 run，`LayerCompositeDriver.swift`）里 colorout/gamma 本就是摘出的终端段——**borders/watermark 插入该段即可，层合成仍在 working space 不受污染**。
- **唯一管线改动**：终端段识别从 `opName ∈ {colorout, gamma}`（06-RESEARCH §2.1 的临时口径）扩为「`iopOrder ≥ 70.0` 的尾窗（colorout..gamma 全段）」，段内保持 v50 排序。`tailPixelFormat` 政策（`PixelPipe.swift:218-227`，top==gamma 时尾平面 .bgra8Unorm）不受影响——gamma 仍是 top；borders/watermark 平面保持 float32（对导出 16-bit 路径友好）。
- **域与色彩（COLOR-2 关注点）**：模块 `defaultColorspace = .RGB`（display 域）。白色文字/白底 = display white (1,1,1)（中性色与 primaries 无关，直接可用）；用户彩色文字/纯色背景色（sRGB hex）需一次 linearize + （P3 等场景） primaries 换算——ColorOutModule 已持 display profile（`ColorOutModule.swift:61-128`），换算函数放 Common。导出时 colorout 输出的是 EXP-04 选定色彩空间，同一换算按导出 profile 走——模块对「colorout 产出什么 profile」无感。
- **与 Phase 6 红线的关系**：borders 是几何扩展模块（modify_roi_out 扩画布），**仅允许在终端段/base 层**——层内禁几何纪律（LAYER-06 层内几何拒绝器，`06-VERIFICATION` LAYER-06 行）天然覆盖：终端段不属于任何层。ROI 扩窗（视窗+边距）与 liquify/retouch 的 hint 扩窗同族（协议内 seam）。

#### 2.2 渲染分工（纯原生，分辨率无关）

| 子功能 | 层 | 说明 |
|---|---|---|
| 画布尺寸/主图位置/文字行位置 | **float64 Swift 布局器**（新 `YiyinLayout`） | 1:1 直译 yiyin 整数/浮点公式（§1.1），输出归一化布局记录——它同时是渲染输入与 golden 参考正本（§6） |
| 背景纯色 | Metal clear/常数 kernel | 颜色经 §2.1 换算 |
| 背景模糊 | 降采样 proxy（长边 ~2048）+ Common/GaussianBlur（Deriche）+ GPU 上采样 | 复用 Phase 3 既有腿（L018 双缓冲纪律已固化在工程）；yiyin 用 ffmpeg boxblur——观感差异在容差带（L017 分流），模糊量映射 = plan 期定标 |
| 亮度统计（自适应蒙层） | Metal reduce 或 CPU 下采样均值 | yiyin 四档阈值直译 |
| 主图圆角+投影 | rounded-rect SDF alpha（Metal）+ GaussianBlur 投影平面 + 单次合成 dispatch | 替代 yiyin 的 mask PNG 两进程方案 |
| 文字行 | **CoreText**（CTFramesSetter 逐行；bold/italic 用 CTFont SymbolicTraits；caseType 转大/小写在字符串层做——yiyin 同款 `text-tool/index.ts:87-91,143-152`） | 字号 = bgHeight×size% → PREVIEW(2560)/EXPORT(全幅) 版式比例恒等 |
| 品牌/自定义 Logo | CG PDF 渲染（矢量无损缩放） | yiyin 26 个 SVG 构建期转 PDF 资产入库（一次性脚本，产物进 repo；不引 librsvg） |
| 竖转横/宽高比 | 布局器内画布重置 + 主图居中缩放 | yiyin `init:110-131` 直译 |

### 3. 数据模型

#### 3.1 模块 Params（Codable & Hashable，直进既有通道）

```
// LightamerIOP/Sources/Yiyin/（新目录，Registry.swift 增注册行）
BordersModule.Params {           // opName "borders", iopOrder 76.0
  enabled 衍生于实例存在; mode: .solid(color) | .blur(amount)
  mainImageWidthRate: Double     // % 背景宽（yiyin main_img_w_rate, 默认 90）
  miniTopBottomMargin: Double    // % 背景高（默认 0）
  aspectRatio: (w: Int, h: Int)? // 画布宽高比重置（bg_rate；nil=随主图）
  landscapeOutput: Bool          // 竖转横（bg_rate 生效时失效——yiyin actions 互斥 :157-164,406）
  cornerRadius: Double?          // % 主图高（radius_show 语义 = nil 即直角）
  shadow: Double?                // % 主图高
  textBottomOffset: Double       // 0.027 常数参数化（calcContentHeight:512）
  adaptiveBackdrop: Bool         // 模糊模式的亮度蒙层开关
}
WatermarkModule.Params {         // opName "watermark", iopOrder 77.0
  templates: [YiyinTemplate]     // key/name/pattern/use/align(baseline|center)/rotation?
  font: YiyinFont                // 默认字体：name/bold/italic/size%/color/caseType
  fields: [YiyinField]           // key/use/forceUse/customValue/type(text|logo)/logoVariant(.auto|.black|.white)
  dateFormat: String             // 默认 "yyyy/MM/dd hh:mm:ss"
  lineSpacing: Double            // text_margin %
}
YiyinFont { name: String; bold: Bool; italic: Bool; sizePercent: Double; color: String; caseType: .default|.lowcase|.upcase }
```

哈希纪律：`commitParams` 内 `StableHash.hash(ParamsCoding.encode(params))`（`IOPModule.swift` 契约 + L013 显式折叠）。**sidecar 零 schema 升级**——参数走 `ModuleInstance.paramsData`（base64，`LightamerSidecar.swift:130`）。

#### 3.2 资产引用与持久化

- **用户字体**：`~/Library/Application Support/Lightamer/Yiyin/Fonts/<name>.<ext>` + 注册表 JSON（name→文件名+StableHash），仿 yiyin font.map（`query.ts:36-62`）；运行时 `CTFontManagerRegisterGraphicsFont`（会话级）或 `CTFontManagerRegisterFontsForURL`（持久）——plan 期定（推荐会话级注册+启动重扫，卸载语义干净）。
- **用户 Logo**：同目录 `Logos/`；Params 引用 `(name, hash)`，加载校验失败 → 该 slot 降级为空（RasterMaskStore 三失败腿降级同构，`06-VERIFICATION` IOP-MASK-03 行）。
- **品牌 Logo（内建）**：构建期 SVG→PDF，13 品牌 × 明暗，Bundle 资源；YIYIN-05 的「不联网」天然满足。
- **预设**：yiyin 两实例的 params 是 `.lightamer-preset`（Phase 12 PRES-01，instances 子集 JSON）的普通成员——本 Phase 只需保证 params 完整 Codable，无需新接口；「yiyin 全局默认」语义 = 存一条预设做默认（Open Question 4）。

#### 3.3 CaptureMetadata 扩展（additive，非破坏）

`CaptureMetadata`（`CaptureMetadata.swift:8-93`）现缺：`focalLength35mm`（等效焦距）、`exposureProgram`、`exposureCompensation`、`meteringMode`、`whiteBalance`、`lensMake`。全部 `Optional` 追加（Codable 兼容旧档），`RAWDecoder.swift:310-331` 的 ImageIO walk 增读 `kCGImagePropertyExifDictionary` 对应键 + `ExifAuxDictionary` LensMake。归一化/格式化（快门分数、日期、测光中文、品牌 α/ℤ）放 **Core 侧纯函数层**（`YiyinExifFormat`），App 与单测共用（02-05 目录惯例：sidecar/读写器在 Core）。

### 4. 批量导出联动（Phase 11 接口预埋）

- **EXP-05 消费点**：EXPORT pipe 变体 = 全幅 + colorout（EXP-04 导出 profile）→ borders → watermark → **编码器**（gamma 不在导出链——8-bit bgra8 会截断 16-bit 路径；float32 display-domain 平面直构 CGImage）。borders/watermark 实例与编辑器**同一份 params**（同 ModuleInstance 记录），预览/导出一致由结构保证——这正是 ROADMAP §Phase 10 Notes「the same config is shared between editor preview and export」的兑现方式。
- **YIYIN-08 输出尺寸/DPI**：配置模型（长边/短边像素、DPI、保留原尺寸）归本 Phase 建模（挂 Watermark 或独立 exportSettings 记录，plan 期定）；**应用**（resize、`kCGImagePropertyDPIWidth/Height` 写入）在 Phase 11 EXP-03 编码腿。本 Phase 的可交付验证 = 版式归一化坐标在任意目标尺寸恒等（§6）。
- **EXP-06/07（队列/多规格配方）**：Phase 11 范围；本 Phase 不建队列。多规格 = 同一模块 params × 不同 exportSettings 组合，接口面已由「params 与 exportSettings 分离」预留。

### 5. 性能

- **PREVIEW 交互**（2560 长边，`PipeResolution.swift:16-24`）：拖 yiyin 滑杆 → paramsHash 翻转 → 命中面 = borders(76)/watermark(77)/gamma(78) 三个模块 + 终端段子 run；上游（含层合成）全 cache hit。文字排版缓存 key = (模板串 ⊕ 字体属性 ⊕ 行高)——参数微调（如仅改 blur）时文字行位图全命中。
- **模糊背景腿**：输入 = borders 的输入平面（主图，几何后内容）→ 降采样 proxy（~2048）blur → 上采样。proxy 尺寸/模糊量折进 borders piece 的辅助平面记账（D-C1 `tileWorkingSetBytesPerPixel` 先例，`PixelPipe.swift:150-155`）；内容哈希寻址 = 主图不变时跨参数失效面最小。
- **100MP FULL**：画布扩展 ~1.23× 面积（90% 占宽时）；窗口化照旧（视窗 ROI + 边距扩窗）；yiyin 遮罩超 10240px 降采样再放的护轨（`image-tool/index.ts:423-444`）在我们恒窗口化渲染下不需要。
- **批量吞吐**（Phase 11 预算输入）：每图 yiyin 增量 ≈ 模糊腿（降采样+blur+上采）+ 文字排版（冷排 ~ms 级/行）+ 2 个合成 dispatch——估 <200ms/图 @24MP；plan 期 benchmark 落 `.work/08/perf.md`（只记录不设门，SC 门沿 PREVIEW 拖动实测）。

### 6. 验证策略

| 对象 | 轨 A（yiyin 证据） | 合成参考（L017 分流） | 钉参 case |
|---|---|---|---|
| 布局几何（画布尺寸/主图位置/文字行位置） | node harness 直跑 yiyin 正本模块（sharp 管线无 GUI 依赖）出 PNG，量测其整数布局 | **float64 Swift 镜像布局器逐值断言**（<1e-6；全部 ceil/round 整数运算可精确复刻）；yiyin 参考抽样对照（尺寸/位置量测） | 横/竖/方图 × aspect 重置 × landscape ≥8 |
| EXIF 字段格式化 | yiyin 格式化表（exiftool/index.ts:82-168）为规格正本 | 表驱动单测：快门分数/日期剔时区/档位缩写/测光中文/白平衡 逐 case | 15 字段 × 边界值 |
| 品牌归一化 | nikon.ts/sony.ts/base.ts/model-map.ts 为规格正本 | 表驱动单测：`ILCE-7M4→α 7m4`、`Z_6_II→ℤ 6 II`、`Z 30→ℤ 30`、CORPORATION 剥离、罗马数字、数学字母 Unicode | 每品牌 ≥3 |
| 文字行位图 | Chromium canvas 位图不可逐像素对齐（**不做位图 parity**） | CoreText 自基线 golden（首次人工签核后冻结）；行宽/行高/ascent 与 yiyin 公式同式断言 | 3 模板 × 明暗 |
| 圆角/阴影/模糊 | yiyin 参考图（`static/最终效果*.jpeg` + node harness）形状区域对照 | alpha 剖面解析断言（SDF 圆角半径/投影 σ 映射）；模糊 DC 增益=1 平场门 | 各 3 |
| 合成恒等/轨 B | — | 无 yiyin 实例 = 全链逐字节零增量；纯色模式白底中姓（D-COL1 沿用）；禁用实例试 == 无实例 | 常驻回归 |
| 持久化 | — | 两实例 params sidecar round-trip 逐字节（L014 fence 纪律）；预设捕获/应用等价 | 3 |
| 版式分辨率无关 | — | PREVIEW(2560) 与全幅渲染的归一化布局记录相等断言 | 2 |
| GUI 验收轮 | PLAYBOOK §0-§6 真机走查（真实 RAW + yiyin 启用前后截图量化）+ Manual-Only 表（字体下拉手感/Logo 视觉/暗背景蒙层观感） |

### 7. UI 面（GUI 红线）

- **YiyinPanelView**（Inspector 新席，`InspectorState.swift:33-62` provider 注册模式 + `InspectorView.swift` 路由）：单面板双节——「印框」（borders 参数：背景模式/颜色、主图占比、圆角、投影、最小边距、宽高比、竖转横）+「水印」（模板列表 CRUD、字段开关与自定义值、字体设置、日期格式）。两节分别提交对应模块实例（D-H1：拖动结束 1 commit）。面板内不放独立预览画布——**主视口即预览**（管道现成，比 yiyin 的 300ms debounce base64 预览更强）。
- **模板编辑**（对齐 yiyin temp-setting/dialog.svelte 语义）：模板串输入 + 字段插入器（FieldSelect）+ 字体设置（FontSetting：字体/字号%/粗斜体/大小写/颜色）+ 对齐；模板列表行 = use 开关 + 编辑/删除。
- **字体管理子视图**：系统字体列表（CTFontManagerCopyAvailablePostScriptNames/家族名）+ 用户导入（.ttf/.otf 文件导入 → 注册 → 列表）+ 删除；导入失败（损坏字体）typed error 提示不静默。
- **Logo 选择**：Make 字段的明暗变体自动 + 手动覆盖 Picker；自定义 Logo 导入入口。
- **i18n**：全部新键走 String Catalog，语言标签 **zh**（L025 红线：禁 zh-Hans 部分表）。
- **accessibility**：L010 纪律 identifier 全量（`yiyin.panel`、`yiyin.template.row.<uuid>` 稳定 id）。

### 8. Risks & Gotchas

1. **77.0 槽位所有权冲突（需先裁决）**：ROADMAP §Phase 8（HDR/Effects，:145）SC#4 写「watermark iop (order 77)」而 §Phase 10 yiyin watermark 同占 77.0（`V50Order.swift:172` 槽位唯一）。倾向：dt `watermark` 槽 = yiyin 终局水印（本 Phase），HDR 的创意文字叠加用新 opName/新槽位（ROADMAP Phase 8 执行时尚未规划，届时沿用 add-only 纪律）——**Open Question 1，动工前定案**。
2. **YIYIN-03/04 措辞超出 parity 面**：需求文字含「位置/旋转」（YIYIN-03）与「位置/大小/透明度」（YIYIN-04），但 yiyin 的文字/Logo 是模板行内元素、固定底部堆叠（`IPosition` 预留未实现）。方案 a：按需求做锚点+旋转+透明度（新能力，工作量 +）；方案 b：v1 交付 yiyin 同款行内语义 + 锚点九宫格（bottom 默认），旋转/自由拖拽 defer（Open Question 2）。
3. **文字位图 parity 不可达**：yiyin 文字 = Chromium canvas2D（Electron/macOS 侧同 CoreText 光栅但排版管线不同）——几何级 parity + 自基线 golden（§6），不做逐像素；预期验收以版式/内容一致为准。
4. **display 域色彩换算（COLOR-2）**：彩色文字/纯色背景在 P3 显示 profile 与导出 profile 下的 linearize+primaries 换算必须走 ColorOutModule 同源 profile——错用 sRGB 字面值 = 色偏；测试钉（平场纯色模式下取样值断言）。
5. **EXIF 方向 × 印框**：CIRAW/orientation 在解码层已直正（yiyin `sharp().rotate()` 同语义，`image-tool/index.ts:97`）→ borders 看到的恒为 upright 像素，无交互风险；回归用 orientation=6 样张钉一条。
6. **数学字母 Unicode 的字体回退**（`charToNumberChar` 0x1D63C 段）：PingFang SC 无这些字形，CoreText 级联回退（CTFontCreateForString）结果依系统字体而定——golden 以当前系统基线冻结 + 头注记录系统依赖（Open Question 8 可选裁剪该 filter）。
7. **yiyin 自身未实现项不背负**：`origin_wh_output`（渲染未消费）、`IPosition/height`（预留未消费）、视频水印（ffmpeg，FEATURES.md:415 明示 out-of-scope）——Lightamer 侧 `origin_wh_output` 为真实现（YIYIN-08），其余不移植并在 plan 注记。
8. **超长文本**：yiyin 直排溢出（源码 TODO 自认 `text-tool/index.ts:171-174`）；v1 沿用单行语义 + 头注，不引入自动缩排（无需求支撑）。
9. **SVG 依赖红线**：不引 librsvg/WebView——构建期 SVG→PDF 转换脚本为一次性工具（转换产物入库，运行时零 Web 依赖）。
10. **L013/L014/L022/L019b 常规适用**：params 哈希走 ParamsCoding；读回前 fence；omp 执行期零工作区写入；单测走 `Scripts/test-direct.sh`。

### 9. Plan 拆分建议（3 个，依赖序）

| Plan | 内容 | T 数（估） | 验收要点 |
|---|---|---|---|
| **8-1 印框模块与终端段** | CaptureMetadata 六字段扩展 + RAWDecoder walk 增读；`BordersModule`（76.0）+ `YiyinLayout` float64 布局器 + 圆角/投影/模糊背景/纯色/竖转横 全腿 + LayerCompositeDriver 终端段尾窗扩展 + 注册 + 平场/恒等/ROI 扩窗断言 + yiyin node harness 参考（布局量测） | 5-6 | 布局几何逐值断言；轨 B 零增量；窗口化 FULL 画布扩展正确（视窗+边距）；tail 政策不回归 |
| **8-2 水印模块与文字系统** | `WatermarkModule`（77.0）+ 模板引擎（matchFields/port）+ CoreText 行渲染 + 排版缓存 + YiyinExifFormat（15 字段格式化）+ 品牌归一化（α/ℤ/罗马/数学字母）+ 字体管理（CTFontManager + 用户导入）+ 品牌 Logo PDF 资产 + 面板水印节（模板 CRUD/字段/字体） | 6-8 | 表驱动单测全绿（EXIF/品牌）；文字行 golden；明暗 Logo 选择；字体导入 typed error；空模板/空字段直通 |
| **8-3 集成、导出配置与签核** | YiyinPanelView 印框节整合 + 双实例联动（面板↔history↔sidecar round-trip）+ YIYIN-08 输出尺寸/DPI 配置模型 + 预设捕获/应用验证（Phase 12 接口面）+ 版式分辨率无关断言 + GUI 验收轮 + perf 落账 + Phase 8 签核材料 | 3-4 | E2E：开图→配印框→⌘Z→sidecar round-trip 渲染逐字节；GUI 轮截图量化；zh 全量渲染（L025 smoke） |

依赖序：8-1 → 8-2（文字系统只依赖布局器产出的行高/位置）→ 8-3。总量 ~14-18 T。

### 10. Open Questions for Planning

1. **77.0 槽位所有权**（§8.1）：dt `watermark` 槽判给 yiyin 终局水印（推荐）+ HDR 创意文字叠加届时用新 opName/新槽位，还是保留 77.0 给 HDR、yiyin 用新槽位（破坏「matching Darktable」口径）？**8-1 动工前必须拍板**（opName+order 进 sidecar history，拖延成本递增）。
2. **YIYIN-03/04 的位置/旋转/透明度交付深度**（§8.2）：a) 完整做（锚点+旋转+透明度，超出 yiyin parity）vs b) v1 = 行内语义 + 九宫格锚点（bottom 默认）+ Logo 透明度（低成本高价值），自由拖拽/旋转 defer v2。推荐 b（parity 优先、需求措辞注记）。
3. **yiyin 配置的持久化形态**：per-image 模块实例（架构一致，推荐——历史/⌘Z/层共存全免费）+「默认印框」预设承载全局语义，vs 全局单配置（yiyin 原语义）覆盖式应用于导出。
4. **「默认印框」交互形态**（与 3 衔接）：启动即给新图自动挂默认 yiyin 实例（yiyin iot 语义），还是显式添加（dt 语义，推荐）。
5. **Logo 资产授权口径**：yiyin 仓库 MIT、品牌 Logo SVG 属各厂商商标——沿用（推荐，与 yiyin 同法）需在 README/关于页标注商标归属，还是首版仅用户自定义 Logo。
6. **模糊背景的模糊量映射**：yiyin = ffmpeg boxblur(`radius×bg_blur%`,2)（`image-tool/index.ts:376`）与 Deriche σ 的映射无解析等价——按观感定标（plan 期定标曲线 + golden 冻结）确认。
7. **YIYIN-08 应用边界确认**：本 Phase 交付配置模型 + 版式分辨率无关验证，物理 resize/DPI 写入等 Phase 11（推荐）——若用户要求本 Phase 内可见 DPI 效果需提前 EXP-03 部分腿。
8. **数学字母 Unicode filter 去留**：`charToNumberChar` 风格化（依赖系统字体回退）保留（yiyin parity）还是 v1 裁剪（降低字体回退不确定性）。

---

## Sources

### yiyin（本地源码 `/Volumes/UNITEK/Documents/Development/yiyin`，v1.7.1，全部 file:line 已核）

- `electron/src/modules/image-tool/index.ts`（合成管线正本：init :92-136 / clacBgImgSize :472-506 / genTextImg :231-286 / genMainImg :213-229 / calcContentHeight :508-546 / genBgImg :197-211 / genMainImgShadow :416-467 / composite :288-348 / genBlurImg :356-390 / genSolidImg :392-403）
- `web/modules/image-tool/index.ts`（渲染进程遮罩：亮度分档 :28-46、blur/radius 公式 :50,63、圆角路径 :65-90、createCanvas :123）
- `web/modules/text-tool/index.ts`（genTextImg :18-117 / createTextImg :126-267 / getFont :269-300 / getMaxFontParam :302-320）
- `web/modules/temp-field/index.ts`（字段填充 + 字号 % 换算 :17-32 + Make Logo 明暗 :80-93 + getTextTempList :40-50）
- `common/const/def-temps.ts`（ITemp 结构 :3-13 + 三系统模板 :15-64）、`common/const/def-fields.ts`（15 字段 :1-17）、`common/utils/temp.ts`（matchFields :1-22）
- `common/modules/exif-format/{index,base,nikon,sony}.ts`（品牌分派 :27-45 / 格式化 :11-122 / Nikon ℤ+罗马 :6-20 / Sony α :4-6）
- `electron/src/modules/exiftool/index.ts`（读取回退 :37-62 / 格式化表 :82-168）；`electron/src/utils/date.ts`（formatDate :8-44）
- `web/util/model-map.ts`（filter 表 :11-43）；`web/util/util.ts`（toRoman :3-30 / charToNumberChar :32-54 / FontFace :96-121）
- `electron/src/interface.ts`（IConfig :5-61 / IFont :63-70 / IFieldInfoItem :83-121）；`electron/src/modules/image-tool/interface.ts`（OutputOption :10-101）
- `web/store/config.ts`（默认值 :10-42）；`web/main/components/actions/index.svelte`（参数面板全项 :227-496）；`web/main/components/temp-setting/dialog.svelte`（模板编辑器 :109-146）；`web/components/font-dialog/index.svelte`（字体导入）
- `electron/src/router/query.ts`（addFont/delFont :36-62）；`electron/src/router/image.ts`（任务/预览 :22-64）；`electron/src/modules/queue/index.ts`（并发队列）
- `web/public/logo/`（13 品牌 × b/w SVG，26 文件）；`static/`（效果样张）

### Darktable（本地 `/Volumes/UNITEK/Documents/Development/darktable`）

- `src/iop/borders.c:429-470`（modify_roi_out 画布扩展：aspect/basis 选择）；`src/iop/watermark.c`（ROI 语义参考）；`src/common/iop_order.c`（borders 76/watermark 77 槽位正本）

### Lightamer 代码（现码，file:line 已核）

- `LightamerCore/Sources/Foundation/V50Order.swift:14-16,166,171-173`（colorout 70/borders 76/watermark 77/gamma 78 + skinSmooth 66.5 非 dt 行纪律）
- `LightamerCore/Sources/Pipe/PixelPipe.swift:150-155,195-199,218-227`（辅助平面记账/tail 平面格式/尾窗政策）；`IOPModule.swift`（Params 契约/commitParams/ROI 钩子）；`PipeResolution.swift:16-24`（PREVIEW 2560）
- `LightamerCore/Sources/Pipe/Terminal/{GammaModule,ColorOutModule}.swift`（display handoff/profile 持有）；`LayerCompositeDriver.swift`（终端段识别扩展点）；`ModuleRegistry.swift:40-77` + `LightamerIOP/Sources/Registry.swift:22-30`（注册模式）
- `LightamerCore/Sources/Decode/CaptureMetadata.swift:8-93` + `RAWDecoder.swift:294-331`（元数据模型与 ImageIO walk）
- `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:36,92-143`（schemaVersion 2/instances/UInt64String）
- `App/Sources/Lightamer/State/InspectorState.swift:33-62`（面板注册）；`App/Sources/Lightamer/UI/Inspector/`（27 面板复用面）；`App/Sources/Lightamer/{Yiyin,Export}/`（空占位目录——本 Phase 落点）
- `Common/GaussianBlur`（模糊腿复用，L018 双缓冲纪律固化件）

### 项目文档

- `.planning/ROADMAP.md`（§Phase 10 :165-179 正本 / §Phase 8 :135-147 的 77 槽位冲突原文 :145 / §Phase 11 :181-193 EXP-05 依赖序）
- `.planning/REQUIREMENTS.md`（YIYIN-01..08 :167-178 / EXP-03..07 :200-206 / PRES-01..04 :191-194）
- `.planning/research/FEATURES.md:274-359`（yiyin 功能清单正本）+ `:415`（ffmpeg out-of-scope）
- `.planning/phases/06-layers-masking/06-RESEARCH.md`（体例范本 + 终端段设计 §2.1）+ `06-VERIFICATION.md`（层内几何拒绝/降级模式先例）
- `.planning/phases/07-ai-modules/07-DISCUSSION-LOG.md:93-116`（Phase 8 移交清单六面：层栈 API/缓存面/66.5 槽位邻域）
- `LESSONS.md`（L010/L013/L014/L017/L018/L019b/L021/L022/L025）；`.work/gui-acceptance/PLAYBOOK.md`（GUI 验收口径）；`.work/GOAL-STATE.md:69`（编号口径旁证）

---

*Phase 8 Research — 2026-09-25。产物仅本文件；未提交 git。*
