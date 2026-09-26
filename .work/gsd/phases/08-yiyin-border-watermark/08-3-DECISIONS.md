# Plan 08-3 Decisions（执行期决策记录）

> 依据 plan 纪律：RESEARCH/CONTEXT 未覆盖的实现细节一律标注**执行期决策**落本文件，不臆造。
> 每条含：决策 + 依据 + 影响。编号 D-08-3-N（代码注释引用同名）。

## D-08-3-T0-1: yiyin_watermark_row alpha 因子修正（08-2 验收必修，随本 plan 首个 fix）

**决策**：`yiyin_watermark_row` kernel 改为编码域 un-premultiply + 线性 alpha 因子：
`out = a · M·srgbDecode(row.rgb / a) + (1 − a) · plane.rgb`（除法结果 clamp [0,1]）。
**依据**：08-2 验收员 CG 探针实证——8-bit sRGB `premultipliedLast` 位图 = **编码域预乘**
（白字 glyph 边缘 r == a 精确；alpha 0.5 白块 r=128/a=128），即存储 rgb = a×encode(color)、
a = 线性 coverage。08-2 首版 kernel 对预乘 rgb 过 EOTF 后又以 `1 − srgbDecode(a)` 作背景
因子——coverage 被二次 EOTF（0.5→0.214），AA 边缘有效覆盖率减半，文字偏瘦。
**影响**：部分覆盖像素合成结果变宽变实（修正方向）；已冻 golden 不受影响（golden 冻
**行位图**——渲染器产物未动）；合成腿测试内容级（上带恒等/下带有差异）照旧成立；
`testRowBitmapInk` 的 r≥a 注释更正（白墨 r==a）；08-2-DECISIONS D-08-2-7 末条同步更正。
T0 全套回归 0 fail 实证。

## D-08-3-T1-1: 双实例联动 = session sibling lookup（面板单视图双节，各自提交各自实例）

**决策**：`YiyinPanelView` 单视图承载双节；`PipeCoordinator.instanceRecord(opName:)` +
`InspectorEditSession.siblingInstance(opName:)` 提供兄弟实例记录查找；同一 provider 对
（YiyinPanelProvider/YiyinBordersPanelProvider）对两个 opName 注册同一视图。
**依据**：D-08-CONTEXT-3（per-image 模块实例）+ D-H1 语义（liveEdited 按 instance UUID
分键——交错编辑天然各自 1 commit、⌘Z 逐级独立还原）；不改 IOPPanelProvider 协议
（24 面板零改动契约）。
**影响**：面板重渲依赖父视图（InspectorView）在 instances 变化时重建 session——实测
实时性足够；双实例交错测试钉（PanelWiringTests.testYiyinDualInstanceInterleavedCommitsAndUndo）。

## D-08-3-T1-2: 手动挂入口形态 = 「应用默认印框」一键按钮 + 缺记录时铸造

**决策**：D-08-CONTEXT-4 的手动入口 = 印框节「应用默认印框」按钮（yiyin 默认值 rate 90 /
radius 2.1 / shadow 6 / solid #fff，一次离散 commit，commit 时 auto-enable）；链上无记录
（旧 sidecar 恢复）时按钮改「添加印框」（铸造 neutralSeed 记录）。
**依据**：seed 恒含 neutral 载体（Registry.editingDefaultInstances 注记），正常路径永不触
铸造分支；yiyin config 默认值（`web/store/config.ts:10-42`）为预设正本。
**影响**：无自动挂载；面板永不静默 no-op（applyWatermark/applyBorders 的 nil-铸兜底）。

## D-08-3-T2-1: LensMake 读取字典更正 = 主 EXIF 字典（SDK 无 Aux LensMake 常量）

**决策**：`lensMake` 读主 EXIF 字典 `kCGImagePropertyExifLensMake`（10.7+，EXIF tag
0xA434）；plan/struct 注记的「ExifAuxDictionary LensMake」表述失实——SDK Aux 字典只有
LensInfo/LensModel/SerialNumber 等，**无 LensMake 常量**；aux 同名键留防御性回落。
**依据**：macOS 27 SDK `CGImageProperties.h` 逐行核对（编译错误实证）。
**影响**：语义不变（LensMake 字符串到位）；CaptureMetadata 注记同步更正。

## D-08-3-T3-1: YiyinExportSettings 校验边界值（正数/上限）

**决策**：目标像素 1...100_000（超任何合理编码器面、远低于纹理维度悬崖）；DPI 1...2400
（覆盖fine-art制版；0/负无意义、>2400 视为输入错误）；`targetSize` 永不放大（fit 大于源
钳回源尺寸）；`AppError` 增 additive `.invalidParameter(String)` case。
**依据**：yiyin 无 cap（InputOption 未消费面），Lightamer 侧自定护栏；EXP-03 编码腿在
Phase 11 调 validate()。
**影响**：边界值测试钉（YiyinExportSettingsTests.testValidationBoundaries）；AppError
switch 无穷举消费方（errorDescription 内聚）。

## D-08-3-T3-2: 生产联合上下文接线 = renderCurrentChain 注入（per-run DATA，尺寸卫兵降级）

**决策**：`PipeCoordinator.renderCurrentChain` 在每次渲染前执行 `injectYiyinRunContext`：
watermark box 注入 captureExif/logo faces/jointContext（mainImageSize 镜像
`PixelPipe.run` 的入口缩放数学），经 `WatermarkModule.makeJointLayoutRecord`（新公共面）
计算联合记录并注入 `BordersModule.jointLayoutOverride`。mainImageSize 不匹配（ROI 窗口
化 zoom run）时 borders 尺寸卫兵拒收 override → 本地空 rows 布局降级。
**依据**：D-08-2-10（「8-3 由 coordinator 在 box 物化后注入」的移交义务——08-2 只交付
注入缝）；per-run DATA 不触 paramsData/paramsHash（L013——注入不是配置）。
**影响**：生产管线 borders 现在为水印行预留 band（此前仅测试路径直注）；zoom 预览的
band 预留缺失为已登记降级（导出恒全帧不受影响）；THUMBNAIL/PREVIEW/FULL 各 bucket
按各自 longEdge 注入（框内尺寸正确）。

## D-08-3-T5-1: knownRegions 处置 = 08-2 备注证伪（zh.lproj 全量编译，零修复）

**决策**：不修改 tuist manifest/knownRegions。
**依据**：构建产物 `Lightamer.app/Contents/Resources/zh.lproj/Localizable.strings` 含全部
699 键（plutil 验证，含 08-3 新增 28 键）——catalog 用 "zh" 语言代码 → 编译进 zh.lproj
（空的 `zh-Hans.lproj` 是陈旧噪音目录）；08-2 备注「zh 值不编译进 bundle」为误报。
**影响**：zh 首屏真机全量渲染实证（FINDINGS 08-3 节截图）；knownRegions=(Base,en) 声明
不阻断 String Catalog 编译；残留 = zh-Hans 空目录（无害，不清理——避免目录级 diff 噪音）。

## 执行期实测备注（非决策）

- **GoldenColor flake 归因纪律**：T0 修复轮全套首跑/复跑各 1 次失败 → stash 对照
  （pre-change 基线绿、post-change 复跑绿）→ 判定既有负载态 flake（L018 族，0-2 失败浮动、
  单跑绿），非 kernel 修正引入；单类绿 + 全套复跑绿双证。
- **GUI 模板行 toggle 的 AX 缺口**：`yiyin.template.toggle.<key>`（DisclosureGroup label
  内 Toggle）不暴露 identifier 给 AX 树（rows/triangles 可见）——GUI 轮用坐标点击兜底；
  不阻塞 AX 面板四件套验收（L010 断言在 params/结构层），AX 可驱动性留 UI 打磨轮观察。
- **双实例 ⌘Z 真机**：菜单「撤销」×2 逐级还原量化（水印行退 → borders-only ΔR 1.70% →
  pristine ΔR 1.65%，残差 = 面板滚动态）。
