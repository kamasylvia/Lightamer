# Plan 08-2 Decisions（执行期决策记录）

> 依据 plan 纪律：RESEARCH/CONTEXT 未覆盖的实现细节一律标注**执行期决策**落本文件，不臆造。
> 每条含：决策 + 依据 + 影响。编号 D-08-2-N（代码注释引用同名）。

## D-08-2-1: YiyinExifFormat 落 Decode/（与 CaptureMetadata 同目录）

**决策**：`YiyinExifFormat.swift` 放 `LightamerCore/Sources/Decode/`，不放 Foundation/。
**依据**：编译依赖方向是 CaptureMetadata → 格式化层；与元数据模型共址 = 单一查询点。
Foundation 留给无 Decode 依赖的横切件。
**影响**：无运行时影响（同 target）；后续 EXIF 相关展示层继续落 Decode。

## D-08-2-2: model-map.ts filter 表 = parity 保留面，不接入显示链

**决策**：`charToNumberChar` 与 model-map filter 表按 yiyin 原样移植 + 表驱动测试
（逐码点断言），但**不**接入水印显示值链路。
**依据**：实测 yiyin v1.7.1 中 `web/util/model-map.ts` 无任何 importer（死代码）；
活跃路径 = `common/modules/exif-format/`（ExifFormat 类），其 Make/Model 均**不**做
数学字母替换。忠实移植 = 移植 yiyin 的实际行为。
**影响**：D-08-CONTEXT-8「filter 保留」兑现为保留的公共 API + 测试；自定义 forceUse
文本若含数学字母仍走 CoreText 级联（零开发）。

## D-08-2-3: 品牌分派 = 剥 CORPORATION 后 uppercased 查表（yiyin 精确查表的稳健超集）

**决策**：Nikon/Sony 分派键 = 剥 CORPORATION + trim 后的 make **uppercased**。
**依据**：yiyin 用剥壳后的原始 make 精确匹配 "NIKON"/"SONY"；真实 EXIF Make 恒为大写
（NIKON CORPORATION/SONY），uppercased 查表覆盖同一现实输入且容忍大小写漂移。
**影响**：make 为 "Nikon"（非标准）时 yiyin 走 base（纯小写）、本仓走 Nikon 分派——
显示差异仅在非标准输入，方向为更正确。

## D-08-2-4: Sony α 替换采用带空格的 `α `（plan 测试向量优先）

**决策**：`ILCE-7M4 → α 7m4`（α 后带空格）。
**依据**：sony.ts 原文替换为裸 `α`（输出 "α7m4"），但 plan 验收表测试向量明写
`ILCE-7M4→α 7m4`；yiyin 的 model-map.ts（死代码面）恰为 `α ` 带空格形——plan 向量与
带空格面一致，排版观感也更正确。
**影响**：与 sony.ts 逐字面差一格空格；与 plan 验收一致；记录在案。

## D-08-2-5: 模板引用未配置字段 = 按隐藏处理（yiyin 原文在此崩溃）

**决策**：`{FIELD}` 无对应 field config 时占位符删除、无 slot 产出。
**依据**：yiyin `fieldTemps[field].show` 在 undefined 上直接抛错（依赖 15 字段恒全配
置的前提）；Swift 侧用隐藏降级等价覆盖该未定义行为。
**影响**：模块 clamp/解析永不崩溃；语义与「字段隐藏」一致。

## D-08-2-6: 九宫格锚点 = bottom-center 摆放后整体平移，margin = textBottomOffset

**决策**：锚点实现为先按 yiyin 公式 bottom-center 摆放（parity 路径），再按锚点把
文字块（行 bbox）平移到目标格位；锚定边距统一用 textBottomOffsetPx（水平边同理）。
**依据**：D-08-CONTEXT-2 定义九宫格为 Lightamer 扩展（bottom-center 恒等）；margin
取 yiyin 唯一存在的边距语义（slot 分数）避免发明第二常数。
**影响**：bottomCenter 数学零接触（yiyin parity 不破）；其余八向的行相对几何保持。

## D-08-2-7: 行渲染执行期口径（一处集中记录）

- **字体度量**：slot ascent/descent/width 用 CTLineGetTypographicBounds（字体度量）；
  yiyin 用 canvas INK bounds（actualBoundingBox*）——无 CT 等价面，行高/行宽亚像素级
  差异由自基线 golden 吸收（L017）。
- **slot 宽度** = ceil(advance width)（yiyin max(ink, advance) 的 advance 半边）。
- **确定性灰度 AA**：关 subpixel positioning/quantization（子像素定位产生逐通道彩色
  边缘，破坏白字 r=g=b 面与 golden 确定性）。
- **文字颜色走属性**：CTLineDraw 不消费 CGContext fill color（探针实测 context-only
  白 fill 输出黑字）——前景色必须挂 kCTForegroundColorAttributeName。
- **Logo opacity** 在位图烘焙（CGContext global alpha 画 logo slot）；Metal 合成面
  保持纯 premultiplied-over。
- **位图编码** = 8-bit sRGB premultiplied；CG 的 premultiply 语义为
  rgb=encode(coverage)、a=coverage（故 r≥a 远离 0/1 处恒成立，非 bug）。

## D-08-2-8: Logo PDF 供给 = 512px 一次性栅格化（CGImage provider 面）

**决策**：YiyinLogoStore 把内嵌 PDF 按高 512px 栅格化一次（负缓存记录失败），以
`YiyinLogoImage(CGImage, aspect)` 供给渲染器；运行时零 SVG/Web 依赖。
**依据**：T4 已冻结的 provider 形状（CGImage）；512px 源在行内 ~30-80px 绘制为纯
降采样，观感无损；矢量化 upgrade（enum 带 CGPDFDocument）为记录在案的扩展缝。
**影响**：logo 边缘在极端放大档（大画布低行数）略软——8-3 GUI 轮 Manual-Only 目检。

## D-08-2-9: 用户字体注册 = 会话级 + 启动重扫（research 推荐案采纳）

**决策**：导入即 `CTFontManagerRegisterGraphicsFont`（会话级）；YiyinFontStore init
重扫目录 + 注册表（内容 StableHash 校验，文件缺失/损坏行自愈剔除）。
**依据**：research §3.2 推荐会话级（卸载语义干净：removeFont 即 unregister，无持久
注册残留）；yiyin font.map = 注册表持久 + 会话加载同构。
**影响**：重启 app 即重扫重注册（启动路径 O(字体数) 文件读）；持久注册路线（
CTFontManagerRegisterFontsForURL）留作扩展缝。

## D-08-2-10: EXIF/联合布局的模块级注入缝（8-3 接线面）

**决策**：`WatermarkModule.captureExif / personalSign / captureTimeZone /
jointContext / logoExists / logoProvider / displayProfileOverride` 全部为模块侧
per-run 注入属性（BordersModule.displayProfileOverride 同族先例）；8-3 由
coordinator 在 box 物化后注入。联合记录 = watermark 按注入的
（mainImageSize ⊕ bordersParams）自算 `YiyinLayout.layout`，并将同一记录注入
`BordersModule.jointLayoutOverride`（D-08-1-1 预留缝）。
**依据**：两条 08-1 决策（D-08-1-1/D-08-1-2）明示的 8-2 分工；injection 不入
paramsHash（per-image DATA ≠ per-image CONFIG），文字缓存键在渲染器层折叠
EXIF 派生 slot 值（L013）。
**影响**：borders 激活时 rows 进 contentH 的画布预留由同一纯函数保证一致
（borders/watermark 各自持记录副本）；borders 中性时**不走公式**（ceil-quirk 不得
放大恒等画布，D-08-1-2），watermark-only 面直接在图上摆行（D-08-CONTEXT Specific
Ideas「画布即原图」）。

## D-08-2-11: watermark-only 行摆放 = yiyin 同式循环 + offset 底边距（无画布预留）

**决策**：`YiyinLayout.stackRows` 复用 yiyin composite 循环（含 :543-545 末行膨胀
quirk）作用在图像自身上；底边距 = textBottomOffset 分数（注入 borders 参数时取其值，
否则 0.027 常数）× 图像高。
**依据**：CONTEXT 的 watermark-only 语义（画布即原图）+ yiyin 的可见底边距语义
（末行可见下缘距底 = offset）逐式保留。
**影响**：单一 stackRows 函数同时服务公式面与水印-only 面（行摆放逻辑单源）。

## 执行期实测备注（非决策，供 8-3 消费）

- **授权调研（D-08-CONTEXT-5）**：13 品牌（canon/dji/fujifilm/hasselblad/leica/
  nikon/olympus/panasonic/pentax/ricoh/sigma/songdian/sony）商标归属表已落 README
  「Trademarks & embedded brand logos」节（nominative use 声明 + 异议移除通道）；
  上游资产来自 **GPL-3.0** 的 kamasylvia/yiyin（research 误记 MIT，已按 LICENSE 实文
  更正）；系统字体级联 = PingFang SC 系统字体经系统 API 使用、**零第三方字体内嵌**
  （README Fonts 节）。关于页（App 层）挂 v1 后。
- **L025 既有缺口发现**：tuist 生成的 `knownRegions = (Base, en)`——String Catalog 的
  zh 值**不编译**进 bundle（zh-Hans.lproj 为空目录，592 既有键同状）。属项目级既有
  状态（非 08-2 引入）；catalog 结构 smoke（en+zh 双面断言）已入 PanelWiringTests；
  zh 实机渲染复验 + knownRegions 修复建议 → 8-3 GUI 轮处置。
- **PREVIEW 拖动初测**（Debug、1706×2560、PSO 冷干扰、只记不设门；正式 benchmark
  8-3 perf.md）：水印参数编辑热路径（两行 + SONY logo，opacity 微调全缓存命中面）
  median **800.8ms**（5 样本 773-838ms）——含终端段重跑 + 行合成上传；比 borders
  同测（~250-380ms）重，主嫌疑 = CoreText 排版冷排 + rgba8 上传/回读路径 Debug 开销。
