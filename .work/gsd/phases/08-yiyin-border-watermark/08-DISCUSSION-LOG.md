# Phase 8 Discussion Log — yiyin Border/Watermark Panel

> 讨论与裁决记录。裁决正本：`08-CONTEXT.md` D-08-CONTEXT-1..8（2026-09-24/25 用户确认，
> 全部动工前落定）+ 各 plan `08-X-DECISIONS.md` 执行期决策。本文件只登记证据指针终节与移交。

## SC 证据指针终节（Phase 8 签核）

SC#1-5 逐条证据链正本 = `08-VALIDATION.md` SC 对照表。指针摘要：

| SC | 一手证据 | 测试锚 | GUI 实证 |
|---|---|---|---|
| SC#1 印框 parity | 08-1-DECISIONS D-08-1-1..10 + node harness JSON（`.work/plans/08-01/yiyin-layout-reference.json`） | `YiyinLayoutTests` / `YiyinBordersTests` 31 | FINDINGS 08-3 节 ΔR 31.15% |
| SC#2 EXIF | 08-2-DECISIONS D-08-2-1..11 + yiyin `exiftool/index.ts:82-168` 规格正本 | `YiyinExifFormatTests` / `YiyinMetadataWalkTests` | SONY α 7rm5 行真机截图 |
| SC#3 字体/模板 | 08-2 T5 授权调研（README 商标节 + GPL-3.0 更正） | `YiyinFontStoreTests` / `PanelWiringTests` 71/0 | 面板 zh 全量截图 |
| SC#4 品牌归一化 | D-08-2-3/4/7（分派键/α 空格/行渲染口径） | charToNumberChar 52 码点逐点 | α 7rm5 实机 |
| SC#5 输出配置 | D-08-CONTEXT-7（物理应用 Phase 11 裁决）+ D-08-3-T3-1（边界值） | `YiyinExportSettingsTests` 5 | — |

**Phase 8 签核判定：PASS（SC#1-5 ✅；SC#5 按裁决范围注记）。** 终验走 verify-work。

## Phase 9（Export Pipeline，执行序 09 = ROADMAP §Phase 11）移交清单

### ① EXP-05 导出消费点接口面（本 Phase 就位、零改动可直接消费）

- **EXPORT pipe 终端段**：`LayerCompositeDriver.terminalTailFloor`（iopOrder ≥ 70.0 尾窗）
  对 EXPORT 变体同样成立——导出链 = colorout（EXP-04 profile）→ borders 76.0 →
  watermark 77.0 → 编码器，**gamma 不在导出链**（8-bit bgra8 会截断 16-bit；float32
  display-domain 平面直构 CGImage）。tail 平面格式政策不回归（gamma 是 top 的前提消失时，
  borders/watermark 平面恒 float32，16-bit 友好）。
- **参数同源**：borders/watermark 与编辑器共享同一份 `ModuleInstance` 记录（sidecar
  paramsData 通道）——「same config shared between editor preview and export」由结构保证。
- **联合上下文注入**：EXP-05 需按导出目标尺寸重跑 `injectYiyinRunContext` 同款注入
  （`PipeCoordinator.injectYiyinRunContext` 是 App 层参考实现——mainImageSize = 导出
  全幅尺寸；joint record 随尺寸重算，行字号 = bgHeight% 自动跟随，版式分辨率无关已钉）。
- **YiyinExportSettings 应用缝**：`targetSize(canvasWidth:canvasHeight:)` 纯函数 =
  EXP-03 resize 规格正本（aspect 保持、永不放大、cap 100_000px）；DPI 写入 = 
  `kCGImagePropertyDPIWidth/Height`（EXP-03 编码腿）；validate() 在编码前调用，
  `AppError.invalidParameter` typed 上浮。

### ② YiyinLayout Record 复用面

- `YiyinLayout.layout(imageSize:bordersParams:rows:)` 纯函数对任意尺寸成立（float64）；
  归一化坐标分辨率无关（`YiyinExportSettingsTests.testJointLayoutRecordResolutionIndependent`
  20+ 字段真比较）。
- 导出多规格（EXP-07）：同一 params × 不同 `YiyinExportSettings` 组合——正交性已测
  （paramsHash 不动）；EXP-05 消费时每规格一次联合布局计算（缓存键含尺寸，天然分档）。

### ③ 遗留对表（承接 08-1/08-2/08-3 各 SUMMARY 遗留节）

| 遗留项 | Phase 8 终态 | 下游 |
|---|---|---|
| blur 腿 Debug 性能（163.9s 全链极值 / 模块腿 7.3s） | √N 多 pass 分解已做；PSO 冷 + Debug 因素主导 | Phase 11 导出腿 Release 复测；观感定标 = Manual-Only |
| watermark 拖动 800ms（Debug） | CoreText 冷排 + rgba8 上传嫌疑；缓存命中面已钉 | Release 复测；排版缓存已最小化 MISS 面 |
| GoldenColor flake | 既有（L018 族）；本轮双向实证非 yiyin 引入 | GUI-23 归因族既有行 |
| ROI 窗口化 × 联合布局（zoom band 预留缺失） | 尺寸卫兵优雅降级（D-08-3-T3-2） | Phase 11 导出恒全帧不受影响；zoom 预览 v2 候选 |
| v2 旋转/自由拖拽（YIYIN-03/04 完整深度） | `rotation?` 参数位预留 | v2（D-08-CONTEXT-2） |
| 内嵌 Logo 授权跟进 | README 商标节 + GPL-3.0 更正已落账 | 关于页（App 层）挂 v1 后 |
| zh-Hans 空目录噪音 | zh.lproj 全 699 键实证（误报证伪） | 无需处理 |
| 蒙层/模糊线性域 vs yiyin 编码域代数差 | 观感容差带（D-08-1-5/6） | Manual-Only 人工终审 |
| 超长文本溢出观感 | yiyin 同款单行语义（源码 TODO 头注） | Manual-Only |
| 字体下拉手感 / Logo 视感 | GUI 轮初观正常 | Manual-Only 人工终审 |

### ④ Phase 8 → verify-work 检查单

- [x] SC#1-5 证据落 08-VALIDATION（本文件 + VALIDATION 正本）
- [x] REQUIREMENTS YIYIN-01..08 翻账 Delivered ×8（同批提交）
- [x] manifest Phase 8 golden 总账节（CoreText 自基线 2 件 + 系统依赖头注）
- [x] perf.md 落账（.work/08/perf.md——只记录不设门）
- [x] 全 suite 0 fail（973/6skip；终轮重编复跑惯例）
- [ ] 用户过目 VALIDATION（签核纪律 C 档第 3 停——本 plan 产出材料，终验 verify-work）
