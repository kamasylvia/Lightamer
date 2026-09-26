# Plan 08-2 Summary — 水印模块与文字系统

**Status:** Complete（T1-T7 全部执行；全套 959/6skip/0fail）
**Executed:** 2026-09-25（ZCode subagent executor）
**Commits:** T1+T2 `a02e20c` feat(core): yiyin exif format layer + brand normalization → T3 `47595d2` feat(iop): watermark 77.0 skeleton + template engine + rows leg → T4 `9ee9ea0` feat(iop): CoreText row renderer + cache + composite + self-baseline golden → T5 `b2d10da` feat(iop): logo double channel + font management + SVG-to-PDF tooling + trademark attribution → T6 `a1066b6` feat(app): watermark panel section + catalog keys → T7（本提交：drag 初测探针 + 收口文档）。T1/T2 合并提交（同一源文件对，全局规则 2.1）。未 push（用户指令：本地 commit 即完成态）。

## 交付内容（对照 plan 验收标准）

- [x] **CaptureMetadata 六 optional 字段**（focalLength35mm/exposureProgram/exposureCompensation/meteringMode/whiteBalance/lensMake——additive Codable 旧档兼容测试）+ **YiyinExifFormat 15 字段表驱动全绿**（快门分数 `1/{round(1/v)}`、JS number 面、档位字母 M/P/A/S、测光中文数值契约 + exiftool 字符串表 verbatim、白平衡、formatDate 引擎 y/M/d/h/m/s/q/S 逐规则）
- [x] **品牌归一化全绿**（CORPORATION 剥离 + 首字母大写；Sony `ILCE-→α `；Nikon `Z→ℤ` + 下划线拆段 + 罗马数字；`charToNumberChar` 0x1D63C 逐码点保留——D-08-CONTEXT-8，系统依赖头注落 golden 与 manifest）
- [x] **WatermarkModule 77.0 注册**（V50 现表槽位零插行 + oneInstance + tiling 永不 + ParamsCoding/StableHash）+ **模板引擎**（matchFields 首现去重 / show·use·forceUse 三门 / Make logo 明暗 auto 分派（blur→白、solid→黑、无资产降级文字）/ slot trim / `{---}` 交错 segment-先于-slot / 跳行规则）+ **空模板/全字段关直通逐字节**（真实管线 byte-exact）+ **轨 B 零增量**（中性插链 == 无实例 + 恰一额外平面）
- [x] **联合布局 rows 态激活**（firstPassCanvasSize 两遍字号基座 + stackRows 抽取（:543-545 末行膨胀 quirk 保留）+ applyAnchor 九宫格（bottomCenter 恒等）；横/竖图行高进 contentH 手算逐值断言；**watermark-only 面**（borders 缺席/中性 → 画布即原图直接叠行，公式 ceil-quirk 不触恒等）+ 行堆叠序 yiyin 同款（列表末行最靠底））
- [x] **CoreText 行渲染**（字号 %/行高/行宽公式同式——独立 CoreText 量测交叉断言 + getMaxFontParam 驱动画布高 + 'QSOPNYuiyl90'/'QOSyYtl709' 双伪串 verbatim + baseline/center 两位二舍五入公式）+ **golden 自基线冻结**（2 件 PNG 目检后 sha256 入 manifest；系统依赖头注；`LA_REGEN_YIYIN_GOLDEN=1` 重冻结名令）+ **排版缓存 MISS/HIT 记账**（同参 HIT、slot/bgHeight 变更 MISS、预算驱逐、clearCache）
- [x] **Logo 双通道**（26 件品牌 PDF 入库——`Scripts/yiyin-logo-convert` 有界 SVG 子集解析器，26/26 全转 + SONY/Nikon 目检像素正确；YiyinLogoStore 内嵌面 + 用户上传面（name+StableHash 注册表 + 跨实例持久 + 损坏 typed 降级））+ **字体管理**（系统族枚举 + .ttf/.otf 导入（CGFont 校验 + 会话注册 + 启动重扫自愈）+ 删除 + unsupported/corrupt/duplicate/notFound typed error）+ **授权调研落账**（README 商标归属表 + GPL-3.0 上游更正 + 零第三方字体内嵌声明——D-08-CONTEXT-5）
- [x] **水印面板节四件套**（`yiyin.panel` + `yiyin.template.row.<key>` 稳定 id 全量 / 37 键 zh+en catalog + L025 结构 smoke / 280pt 单列 / D-H1 三件套——opacity·lineSpacing·字号拖动恰 1 commit + 文本框 submit 提交）+ PanelWiring 扩展绿（dispatch/恰 1 commit/undo 还原/离散 toggle·delete）+ 锚点九宫格 Picker + Logo 透明度滑杆（D-08-CONTEXT-2）
- [x] **全量 suite 0 fail + manifest 节 + SUMMARY/DECISIONS 落盘**

## 验证数字

| 面 | 数字 |
|---|---|
| 全套（终轮） | **959 tests / 6 skipped / 0 failed**（基线 888 → 959 +71：T1/T2 23 + T3 24 + T4 10 + T5 9 + T6 PanelWiring 4 + T7 计时探针 1；每任务提交时全套分别 911/0、935/0、945/0、955/0、959/0） |
| EXIF/品牌 | 23 测试（15 字段边界值 + 品牌 α/ℤ/罗马 + charToNumberChar 52 码点逐点 + formatDate 规则） |
| 模板引擎/布局 | 35 测试（matchFields/交错/forceUse/明暗矩阵/隐藏降级 + rows 态手算逐值（横 680×453、竖 445×668）+ watermark-only + 锚点平移） |
| 渲染 | 行盒公式交叉 + 缓存记账（1MISS→1HIT→3MISS）+ 分辨率无关（4× 高度比、pad 稀释宽度比钉注释）+ 管线底带墨迹内容级（上半零差异） |
| Logo/字体 | 26/26 PDF 转换 + 13 品牌双变体解析 + 用户通道 typed 四错 + 注册表持久/自愈 |
| 面板 | PanelWiring 68/0（全文件）；catalog 37 键 en+zh 双面 |
| PREVIEW 初测 | 拖动热路径（opacity 微调，全缓存命中面）median **800.8ms**（Debug、PSO 冷，只记不设门——正式 benchmark 8-3 perf.md） |

## 遗留 / 风险（对表）

1. **PREVIEW 拖动 Debug 初测偏重**（~800ms vs borders ~250-380ms）：主嫌疑 = CoreText 冷排 + rgba8 上传路径 Debug 开销；8-3 正式 benchmark（perf.md，只记不设门）+ SC 门 = 真机拖动。
2. **zh 编译缺口（既有，非本 plan 引入）**：tuist `knownRegions=(Base,en)` → catalog zh 值不编译（zh-Hans.lproj 空目录，592 既有键同状）。catalog 结构 smoke 已入测；**knownRegions 修复建议 + zh 实机渲染复验 → 8-3 GUI 轮处置**（DECISIONS 备注节）。
3. **Golden 系统依赖**（D-08-CONTEXT-8）：CoreText 自基线随 OS/字体更新合法漂移——重冻结名令 `LA_REGEN_YIYIN_GOLDEN=1` 已写入 manifest 与测试 skip 信息；首签核 = 执行期目检 + 结构断言，人工终审随 8-3 GUI 轮。
4. **yiyin verbatim quirks 钉住**（非缺陷）：Nikon 前缀剥离在 Model 重复 make 字符串时留下前导空格（引擎 slot trim 兜住）；宽度比被绝对 30px pad 稀释；sony α 空格采用 plan 向量形——全部测试注释在案（D-08-2-2/4/7）。
5. **8-3 接线面**：`captureExif/jointContext/logoExists/logoProvider` 注入缝已就位（含 box.module 直注测试实证），coordinator 双实例联动 = 8-3 交付；borders 节整合 + GUI 验收轮 + perf.md + 预设捕获面同批。

## 关键文件

- `LightamerIOP/Sources/Yiyin/{YiyinTemplate,WatermarkModule,YiyinTextRenderer,YiyinLogoStore,YiyinFontStore}.swift` + `YiyinLayout.swift`（rows 态扩展）+ `YiyinColor.swift`（行色矩阵）+ `YiyinKernels.metal`（yiyin_watermark_row）
- `LightamerCore/Sources/Decode/{CaptureMetadata,YiyinExifFormat}.swift`
- `LightamerIOP/Resources/Logos/*.pdf`（26 件）+ `Scripts/yiyin-logo-convert/main.swift`
- `App/Sources/Lightamer/Yiyin/YiyinPanelView.swift` + `State/InspectorState.swift`（注册）
- `input/golden/yiyin-watermark/`（2 golden + manifest 节）；`README.md`（商标节）
- 决策正本：`08-2-DECISIONS.md`（D-08-2-1..11 + 实测备注）
