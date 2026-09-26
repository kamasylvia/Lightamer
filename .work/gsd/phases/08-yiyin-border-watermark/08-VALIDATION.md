# Phase 8 Validation — yiyin Border/Watermark Panel（执行序 08 = ROADMAP §Phase 10）

**Status:** validated（材料齐备；终验走 verify-work——签核纪律：VALIDATION 需用户过目）
**Date:** 2026-09-25
**Plans:** 08-1（印框模块与终端段）✅ / 08-2（水印模块与文字系统）✅ / 08-3（集成、导出配置与签核）✅
**终轮全 suite:** **973 tests / 6 skipped / 0 failed**（基线 864 → 973，Phase 8 净增 109）
**Golden 冻结:** yiyin 文字行 CoreText 自基线 2 件（manifest §yiyin watermark text-row golden；
系统依赖头注在案，`LA_REGEN_YIYIN_GOLDEN=1` 重冻结名令）

## SC 对照（ROADMAP §Phase 10 SC#1-5）

| SC | 内容 | 证据指针 | 状态 |
|---|---|---|---|
| **SC#1** | 印框 parity（边距/比例/颜色/比例扩展/竖转横）输出对齐 yiyin | **布局链**：`YiyinLayout` float64 镜像 13 case 逐值断言 + yiyin node harness（`Scripts/yiyin-ref-harness.mjs`）量测对照（08-1 T2）+ sharp 合成量测探针 bbox 精确命中；**渲染腿**：`YiyinBordersTests` 31 测试（solid 平场门/圆角 SDF 剖面/投影单调/模糊 DC 增益=1/蒙层四档/ROI 画布扩展内容级/orientation=6）；**COLOR-2** 显示域换算已知点全管线取样钉；**联合布局** rows 态横竖手算逐值（08-2）；**GUI 真机**：DSC00012.ARW 白 band + 圆角 + 竖转横参数面板（08-3 FINDINGS ΔR 31.15%） | ✅ |
| **SC#2** | EXIF 叠加（相机/镜头/焦距/光圈/快门/ISO/时间，可配置字段与格式） | `YiyinExifFormatTests` 15 字段表驱动全绿（快门分数/档位字母/测光中文/exiftool 字符串表 verbatim/formatDate 引擎）+ **decoder walk 接通**（08-3 T2 `YiyinMetadataWalkTests`：CR3/NEF/ARW 真实样张六字段与独立 ImageIO 读逐一对照）+ 模板引擎 matchFields/show·use·forceUse 三门/交错 segment（08-2 T3）+ 真机 EXIF 行渲染（SONY α 7rm5） | ✅ |
| **SC#3** | 自定义字体管理（.ttf/.otf 本地、不联网）+ 文字模板系统（预设+自定义） | `YiyinFontStoreTests`（系统族枚举 + 导入 CGFont 校验 + 会话注册 + 启动重扫自愈 + unsupported/corrupt/duplicate/notFound typed 四错）+ 面板字体 Picker（系统+用户双源）+ 模板 CRUD（stable key 行 identity，L010）+ 3 系统模板 + 自定义模板添加/删除/模式串编辑/{Field} 插入器（08-2 T5/T6 + 08-3 T1 PanelWiring 71/0） | ✅ |
| **SC#4** | Make/Model 品牌归一化（Sony ILCE→α、Nikon Z→ℤ 等） | `YiyinExifFormatTests` 品牌分派/α 带空格/ℤ+下划线拆段+罗马数字/charToNumberChar 52 码点逐点 + **真机实证**：DSC00012.ARW（ILCE-7RM5）→「SONY α 7rm5」（logo PDF + 归一化文本，08-3 GUI 轮截图）；model-map.ts 死代码面定性（D-08-2-2） | ✅ |
| **SC#5** | 输出尺寸/分辨率配置（DPI、长/短边、保留原尺寸）驱动预览与导出 | **`YiyinExportSettings`**（08-3 T3）：独立值类型（mode 三态 + DPI + validate 边界 + 纯 `targetSize` 数学，永不放大）+ **与水印参数正交**（EXP-07 多规格组合面，paramsHash 不动测试）+ **版式分辨率无关**：`YiyinLayout.layout` PREVIEW(2560-derived) vs 2× 全幅归一化记录相等（真比较 20+ 字段）+ `testResolutionIndependentNormalizedRowBox`（08-2）；**物理应用（resize/DPI 写入）= Phase 11 EXP-03、导出消费点 = EXP-05**（D-08-CONTEXT-7——本 SC 的「驱动导出」半边按裁决 deferred，接口面已就位） | ✅（本 Phase 范围；物理应用 Phase 11） |

**判定：5/5 达成**（SC#5 按范围裁剪注记：配置模型 + 版式分辨率无关 + 预设/正交接口面 =
本 Phase 交付；EXP-03 物理应用与 EXP-05 消费点归 Phase 11——D-08-CONTEXT-7 用户裁决，
非缺口）。

## Per-Task Map（08-1/2/3 全任务）

| Plan | Task | 交付 | commit | 关键测试 |
|---|---|---|---|---|
| 08-1 | T1 | borders 76.0 skeleton + 终端段尾窗（iopOrder ≥ 70） | `a709c9b` | testTailWindowExtraction / testTailWindowRoutesBorders… |
| 08-1 | T2 | YiyinLayout parity vs node harness（13 case） | `dd1bed5` | YiyinLayoutTests 逐值 |
| 08-1 | T3 | solid 腿 + display 域色彩 + ROI 画布扩展 | `d77d204` | 平场门 / ROI 内容级 |
| 08-1 | T4 | 圆角 SDF + 投影腿 | `6604ac9` | SDF 剖面 / 投影单调 |
| 08-1 | T5 | blur 背景腿 + 自适应蒙层 | `65372af` | DC 增益=1 / 四档边界 |
| 08-1 | T6 | orientation 钉 + PREVIEW 初测 + 收口 | `30661ad` | orientation=6 / 时序探针 |
| 08-2 | T1/T2 | YiyinExifFormat 15 字段 + 品牌归一化 | `a02e20c` | 表驱动全绿 |
| 08-2 | T3 | watermark 77.0 skeleton + 模板引擎 + rows 腿 | `47595d2` | 引擎矩阵 / rows 手算 |
| 08-2 | T4 | CoreText 行渲染 + 缓存 + 合成 + golden | `9ee9ea0` | golden ×2 / 缓存记账 |
| 08-2 | T5 | Logo 双通道 + 字体管理 + SVG→PDF 工具 + 商标注记 | `b2d10da` | 26/26 PDF / typed 四错 |
| 08-2 | T6 | 水印面板节 + catalog | `a1066b6` | PanelWiring 68/0 |
| 08-2 | T7 | 拖动探针 + 收口文档 | `b44b2f4` | 时序探针 |
| 08-3 | T0 | **kernel alpha 因子修正**（编码域 un-premultiply + 线性 coverage） | `49faec4` | 全套 960/6/0（D-08-3-T0-1） |
| 08-3 | T1 | 印框节整合 + 双实例联动（sibling lookup + 双 provider） | `4d2bf6f` | PanelWiring +3（交错 ⌘Z） |
| 08-3 | T2 | decoder walk 六字段 + orientation 端到端 | `630f5fe` | YiyinMetadataWalkTests 3 |
| 08-3 | T3 | YiyinExportSettings + 生产联合上下文接线 + 预设面 | `2de8645` | YiyinExportSettingsTests 5 |
| 08-3 | T4 | E2E + sidecar round-trip ×3 + 4 态矩阵 | `3b4a6be` | YiyinE2ETests 2 |
| 08-3 | T5 | GUI 验收轮 + perf.md + knownRegions 处置 | `73e29e0` | FINDINGS ΔR 表 / perf.md |
| 08-3 | T6 | 签核材料 + 移交 + 收口（本提交） | — | 终轮重编复跑 |

## Manual-Only 汇总（正本 FINDINGS「Plan 08-3 T5 GUI 验收轮」）

| 项 | 级别 | 处置 |
|---|---|---|
| 字体下拉手感 | Manual-Only | 交互手感不可量化——待人工 |
| Logo 视觉（band 内锐度/字号观感） | Manual-Only | 初观可读、位置正确；人工终审 |
| 暗背景蒙层观感（档位自然度） | Manual-Only | 渲染正确；观感定标（D-08-CONTEXT-6 容差带）待人工 |
| 超长文本溢出行为 | Manual-Only | yiyin 同款单行溢出语义（源码 TODO 头注在案）；未构造超长样张 |
| 模糊背景 Debug 首渲延迟 | Manual-Only | Debug 极值在案（perf.md）；Release 另计 |
| 撤销链/⌘Z | **已覆盖** | 菜单「撤销」×2 真机逐级还原（ΔR 1.70%/1.65%） |

## 遗留与注记（非阻塞）

1. **GoldenColor 既有 flake**（L018 类 CI 腿黑帧）：本轮全套 960 首跑出现 2 次、单跑绿、
   复跑全绿（T0 轮实证 pre/post-change 双向均绿——非本 Phase 引入）；GUI-23 归因族，既有行跟踪。
2. **kernel alpha 修正**（08-3 T0）：08-2 首版合成因子二次 EOTF——已修正并全量回归；
   golden 冻行位图不受影响（D-08-3-T0-1）。
3. **zh 编译缺口证伪**：08-2 备注的「zh 值不编译」为误报——`zh.lproj/Localizable.strings`
   含全部 699 键（08-3 T5 FINDINGS）；knownRegions 声明不阻断编译。
4. **ROI 窗口化（zoom）× 联合布局**：ROI-hinted 窗口化 run 下 borders 的 joint override
   按尺寸卫兵优雅降级（本地空 rows 布局）——zoom 预览的水印 band 预留可能缺失；普通
   PREVIEW/FULL 全帧 run 精确。已登记 DECISIONS D-08-3-T3-2，Phase 11 导出（恒全帧）不受影响。
5. **v2 旋转/自由拖拽**（YIYIN-03/04 完整深度）：D-08-CONTEXT-2 裁决 defer；`rotation?`
   参数位已预留（Codable 前向兼容）。
