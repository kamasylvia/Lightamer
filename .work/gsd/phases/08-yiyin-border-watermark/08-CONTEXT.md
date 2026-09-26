# Phase 8: yiyin Border/Watermark Panel（印框/水印面板移植） - Context

**Status:** Ready for planning — 8 项 Open Questions 全部经用户裁决（2026-09-24/25 编排确认，D-08-CONTEXT-1..8）；plans（08-01..03）随本文件同批落盘；Phase 7 移交清单六面已逐条对位（07-DISCUSSION-LOG 终节 ↔ 本文件 Existing Code Insights）。

> **编号口径**：本 Phase 在 `phases/` 执行序编号 08，对应 `.planning/ROADMAP.md` §Phase 10（YIYIN-01..08）。ROADMAP §Phase 8（HDR/Effects）是另一个未来阶段，两套编号在本文档分开引用。

## Phase Boundary

**In scope（YIYIN-01..08 全 8 reqs）：**

- 两个终端 iop 模块：`borders`（76.0，画布扩展+背景+圆角/投影）+ `watermark`（77.0，模板文字行+品牌 Logo）——display-referred 域（colorout 70.0 后、gamma 78.0 前）
- 唯一管线改动：LayerCompositeDriver 终端段识别从 `opName ∈ {colorout, gamma}` 扩为 `iopOrder ≥ 70.0` 尾窗
- `YiyinLayout` float64 布局器（yiyin 七步合成管线直译，纯函数）
- EXIF 层：`CaptureMetadata` 六 optional 字段 + RAWDecoder ImageIO walk 增读 + `YiyinExifFormat` 格式化/品牌归一化纯函数层
- 资产系统：字体管理（系统枚举 + 用户 .ttf/.otf 导入）+ 品牌 Logo 双通道（内嵌 PDF 集 + 用户上传）
- `YiyinPanelView`（Inspector 单面板「印框/水印」双节）+ 面板四件套
- YIYIN-08 导出配置**模型** + 版式分辨率无关验证（像素域）
- 预设接口面验证（params 完整 Codable——Phase 12 `.lightamer-preset` 的天然消费者）

**Out of scope / Deferred：**

- **导出接线与物理应用**（EXP-05 导出管线消费点、EXP-03 resize/DPI 写入）——Phase 11（D-08-CONTEXT-7）
- **批量导出队列**（EXP-06）——Phase 11
- **预设管理器**（PRES-02 创建/编辑/导入/导出 UI）——Phase 12；本 Phase 只保证接口面
- **HDR 创意文字水印**——不占 77.0，届时另定新 opName/新槽位（D-08-CONTEXT-1）
- **完整旋转/自由拖拽**（YIYIN-03/04 的 rotation/自由 position）——v2（D-08-CONTEXT-2）
- **视频水印**（yiyin ffmpeg 腿，FEATURES.md:415 out-of-scope）、**exiftool 二进制**（ImageIO 已覆盖）、`IPosition/height` 预留未消费字段（yiyin 自身未实现，不背负）、`origin_wh_output` 渲染路径（yiyin 未消费；Lightamer 以 YiyinExportSettings 真实现）

## Implementation Decisions

### D-08-CONTEXT-1: 77.0 槽位 = yiyin 终局水印；HDR 文字水印另定槽位

`watermark` 77.0（与 `borders` 76.0 同为终端段）判给 yiyin 终局水印（本 Phase）。ROADMAP §Phase 8（HDR/Effects）SC#4「watermark iop (order 77) is distinct from the yiyin final-output watermark」的措辞**改道**：HDR 创意文字叠加届时（用户口径 Phase 12，执行序后续阶段规划时）另定新 opName/新槽位，沿用 add-only 纪律，不动 77.0。opName+order 进 sidecar history——本裁决已动工前落定（用户 2026-09-24 确认），执行期不得重开。

### D-08-CONTEXT-2: YIYIN-03/04 v1 交付深度 = 行内偏移 + 九宫格锚点 + Logo 透明度

v1 交付：①yiyin 行内语义（模板行堆叠 + `textBottomOffset` 行内偏移，列表末行最靠底）；②**九宫格锚点**——文字块/Logo 整体锚定（bottom-center 默认 = yiyin 语义特例，其余八向为 Lightamer 扩展）；③**Logo 透明度**参数（超出 yiyin parity 的低成本高价值项）。完整自由旋转/自由拖拽留 v2。REQUIREMENTS YIYIN-03「位置/旋转」/ YIYIN-04「位置/大小/透明度」注记 v1 口径（编排指令要求同批注记）。

### D-08-CONTEXT-3: 持久化 = per-image 模块实例 + 默认预设（非 yiyin 全局单配置）

borders/watermark 各为 per-image `ModuleInstance`，参数走 Phase 2 既有 `paramsData` 通道（base64，`LightamerSidecar.swift:130`）——**sidecar schemaVersion 零升级**。参数哈希 `commitParams` 内 `ParamsCoding.encode` + StableHash（L013）。「yiyin 全局默认」语义 = 存一条默认预设承载（非全局单配置覆盖式应用）。

### D-08-CONTEXT-4: 新图不自动挂默认印框

dt 语义：用户显式添加（手动挂 borders/watermark 实例或一键应用默认预设）。yiyin 的「iot 启动即生效」语义不移植。

### D-08-CONTEXT-5: 品牌 Logo 双通道（用户修正，非 research 推荐原案）

**内嵌第三方品牌模板集**（yiyin `web/public/logo/` 13 品牌 × 明暗 26 SVG，构建期转 PDF 入库）+ **用户上传自定义 Logo** 并存。内嵌集的**授权/来源在 8-2 调研落账**（各厂商商标归属 → README/关于页标注；yiyin 仓库 MIT 但 SVG 属各商标持有人）；系统字体级联的来源/授权同理调研注记。REQUIREMENTS YIYIN-04 注记双通道。

### D-08-CONTEXT-6: 模糊背景模糊量定标（线性换算式）

σ = yiyin 百分比 × bgHeight / 100 × 0.5（线性换算；观感 benchmark 微调允许，golden 冻结后不改式）。yiyin 正本 = ffmpeg boxblur（`image-tool/index.ts:376`）与 Deriche 无解析等价，此式为本 Phase 定标正本，落 8-1 DECISIONS。

### D-08-CONTEXT-7: YIYIN-08 物理应用等 Phase 11（本 Phase 只做像素域）

本 Phase 交付：配置模型（`YiyinExportSettings`：保留原尺寸/长边/短边 + DPI，独立值类型）+ 版式分辨率无关验证（PREVIEW 2560 与全幅归一化布局记录相等）。物理 resize 与 `kCGImagePropertyDPIWidth/Height` 写入 = Phase 11 EXP-03；导出管线消费点（EXPORT pipe 终端段 → borders → watermark → 编码器，gamma 不在导出链）= Phase 11 EXP-05。

### D-08-CONTEXT-8: 数学字母 Unicode 字体回退 = 系统字体级联（零开发）

`charToNumberChar`（0x1D63C 段）filter **保留**（yiyin parity）。回退 = CoreText 系统字体级联（`CTFontCreateForString`，天然支持，零开发）。文字行 golden 以当前系统基线冻结 + golden 头注记录系统依赖（OS 升级可能漂移——预期内的可重冻结节）。

### 继承定案（非 OQ，RESEARCH 已论证、下游不得重开）

- **终端段落位**：borders 76.0 / watermark 77.0 在 colorout 70.0 后 gamma 78.0 前 = display-referred 域（dt 同 seam；yiyin 本就是 sRGB 出图前最后一步）。tailPixelFormat 政策不回归（gamma 仍是 top；borders/watermark 平面保持 float32，对 16-bit 导出友好）。borders 是几何扩展模块——仅允许在终端段/base 层（LAYER-06 层内几何拒绝器天然覆盖：终端段不属任何层）。
- **联合布局记录（joint layout，RESEARCH 未显式定案、本文件补钉）**：yiyin 的 `calcContentHeight` 依赖文字行高度（有/无文字两态）；拆两模块后 borders（76.0）扩画布必须**预留** watermark（77.0）文字块空间。定案 = 纯函数 `YiyinLayout.layout(imageSize:bordersParams:watermarkRows:) → YiyinLayoutRecord`，终端段子 run 组装时按段内 yiyin 实例对计算一次（缓存键含 imageDims ⊕ 两实例 paramsHash——ParamsCoding 规范化），borders/watermark 各自消费同一记录的己方字段。8-1 先交付空 rows 态（watermark 缺席/无行）；8-2 激活 rows 态。模块协议缝（driver 注入 aux vs 段内协调器查询）= **执行期决策**入 08-1-DECISIONS。
- **渲染分工**：布局/几何 = float64 Swift 布局器；背景纯色/画布合成/圆角 SDF/投影 = Metal（投影模糊复用 `Common/GaussianBlur`，L018 双缓冲纪律）；文字排版 = CoreText；Logo 矢量 = CG PDF 渲染。不引 librsvg/WebView；ffmpeg/exiftool 不移植；yiyin 的 mask PNG 两进程方案不做（Metal 一次 dispatch 等价替代）。
- **display 域色彩换算（COLOR-2）**：白色文字/白底 = display white (1,1,1) 直接可用；用户彩色文字/纯色背景色（sRGB hex）需 linearize + primaries 换算，走 ColorOutModule 同源 display profile（`ColorOutModule.swift:61-128`）；导出时按 colorout 产出 profile 同式换算——模块对 colorout 产出什么 profile 无感。
- **CaptureMetadata 扩展形态**：六字段（focalLength35mm/exposureProgram/exposureCompensation/meteringMode/whiteBalance/lensMake）全部 additive `Optional`（Codable 兼容旧档）。**拆两半落地**：struct 声明随 8-2（YiyinExifFormat 格式化层的编译依赖），RAWDecoder ImageIO walk 增读随 8-3（集成 + 真实样张验证）。
- **性能形态**：PREVIEW 拖 yiyin 参数命中面 = borders(76)/watermark(77)/gamma(78) 三模块 + 终端段子 run，上游全 cache hit；模糊背景腿输入 = 主图（内容哈希寻址，参数无关不失效）+ 降采样 proxy（长边 ~2048）；文字排版缓存 key = (模板串 ⊕ 字体属性 ⊕ 行高)；批量吞吐估 <200ms/图 @24MP——benchmark 落 `.work/08/perf.md`（**只记录不设门**，ROADMAP §Phase 10 无性能 SC）。
- **验证分流（L017 纪律）**：布局几何 = float64 Swift 镜像逐值断言 + yiyin node harness 抽查对照（sharp 管线无 GUI 依赖，可在正本仓直跑）；文字位图 = **不做位图 parity**（Chromium canvas 与 CoreText 光栅管线不同），CoreText 自基线 golden（首次人工签核后冻结）；EXIF 格式化/品牌归一化 = 表驱动单测（yiyin 源码为规格正本）；轨 B 恒等 + sidecar round-trip + GUI 验收轮常驻。
- **yiyin 公式直译钉**：`blur = 主图高×(shadow/100)`（默认 6）、`cornerRadius = min(主图高×(radius/100), 上限 50)`（默认 2.1）、字号 = `round(bgHeight × size/100)`、行高 = `max(行 ascent+descent+2×text_margin, 最大字号)`、行宽 = slot 宽度和 + 两侧 pad、暗背景蒙层 = 平均亮度（RGB 均值）四档半透明灰罩、文字行首行 top = bg.h − text.h 逆序上叠。

### 验证与 GUI 红线（全 plan 写死，执行期不得放宽）

- 每任务独立提交（Conventional Commits，只 add 相关文件）；构建 `caffeinate -dis` 包裹；单测一律 `Scripts/test-direct.sh`（L019b）；`xcodebuild test` 保留给 UITests 需求。
- **每任务边界检查 `.work/config.toml [gsd]` 开关**（`paused=true` → 全链路干净停：在制品已 commit、报告断点；`auto=false` → 当前波完成后停等用户；检查点 = 任务收尾 commit 后、下一任务开工前。2026-09-24 暂停机制，2026-09-25 起布尔开关替代 PAUSE 文件）。
- **防空转定式**：布局逐值断言真比较循环 + `compared > 0`；恒等/直通逐字节（seed 恒等 / 空模板直通 / 禁用实例试 == 无实例）；平场门（纯色白底中姓沿 D-COL1、模糊 DC 增益=1）；alpha 剖面带方向断言（SDF 内=1/外=0/模糊带单调）。
- **ROI 红线（L020/L021）**：照搬 dt `borders.c` ROI 公式前核对 walk 坐标系前提；几何扩展模块必须有**内容级**断言（记账绿≠内容对）；窗口化渲染 = 视窗 ROI + 边距扩窗（liquify/retouch hint 扩窗同族）；`dscIn` 恒为本 run 平面像素。
- **面板四件套**（8-2/8-3 硬性项）：L010 accessibilityIdentifier（`yiyin.panel` / `yiyin.template.row.<uuid>` 稳定 id 非索引）+ zh/en String Catalog（**zh 标签**，L025——`ls *.lproj` smoke + 首屏截图必查中文渲染）+ 280pt Inspector 约束 + D-H1 三件套（滑块/拖动实时 → 松手恰 1 commit）。
- **GUI 复验（8-3）**：PLAYBOOK §0-§6 真机走查 + 截图量化（ΔR 口径数字进 FINDINGS，L021 ⑤）+ Manual-Only 表登记（L011）。
- **L022 纪律**：omp 执行期 orchestrator 零工作区写入。
- RESEARCH/CONTEXT 未覆盖的实现细节（协议缝形制/pad 缩放语义/字体注册会话级 vs 持久等）一律标注**执行期决策**入对应 `08-X-DECISIONS.md`，不臆造。

## Canonical References

- `.planning/phases/08-yiyin-border-watermark/08-RESEARCH.md`（正本：yiyin 七步管线拆解 file:line / V50 槽位 / 渲染选型 / 数据模型 / 性能 / §6 验证策略 / §8 风险 / §9 plan 拆分）
- `.planning/ROADMAP.md` §Phase 10（:165-179，SC#1-5 + Notes「same config shared between editor preview and export」）/ §Phase 11（:181-193，EXP-05 依赖序）/ §Phase 8（:135-147，77 槽位冲突原文——D-08-CONTEXT-1 已裁决）
- `.planning/REQUIREMENTS.md` YIYIN-01..08（:167-178 正本）+ EXP-03..07（:200-206，Phase 11 消费面）+ PRES-01..04（:191-194）
- yiyin 正本：`/Volumes/UNITEK/Documents/Development/yiyin`（v1.7.1，全部 file:line 见 RESEARCH §Sources——**只读参考，独立维护**）
- Darktable：`src/iop/borders.c:429-470`（modify_roi_out 语义参考）、`src/common/iop_order.c`（槽位正本）；dt `watermark.c` 仅 ROI 语义参考（SVG/position 面不移植）
- `.planning/phases/07-ai-modules/07-DISCUSSION-LOG.md` 终节（Phase 8 移交清单六面）+ `07-3-SUMMARY.md`（体例与收口范本）
- `.work/gui-acceptance/PLAYBOOK.md`（GUI 验收口径）；`LESSONS.md` L010/L013/L014/L017/L018/L019b/L020/L021/L022/L025

## Existing Code Insights

### Reusable Assets（08-RESEARCH §Sources 现码 file:line 核过）

- `LightamerCore/Sources/Foundation/V50Order.swift:166,171-173`——colorout 70.0 / **borders 76.0 / watermark 77.0 槽位已在表（本 Phase 零插行）** / gamma 78.0；表头 verbatim 纪律 + V50OrderTests strip-to-93 零移动钉常驻
- `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift`——1+N+1 架构，终端段子 run 现成；识别扩展点 = 本 Phase 唯一管线改动
- `LightamerCore/Sources/Pipe/PixelPipe.swift:150-155,218-227`——辅助平面记账（D-C1 先例，模糊 proxy 折算用）+ tail 平面格式政策
- `LightamerIOP/Sources/Common/GaussianBlur`——模糊腿复用（Deriche IIR 双缓冲，L018 合规固化件）
- `LightamerCore/Sources/Pipe/Terminal/{ColorOutModule,GammaModule}.swift`——display profile 持有（色彩换算同源）+ gamma top 语义
- `LightamerCore/Sources/Decode/{CaptureMetadata.swift:8-93,RAWDecoder.swift:294-331}`——元数据模型 + ImageIO walk 扩列点
- `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:36,92-143`——paramsData 通道（零 schema 升级）
- `App/Sources/Lightamer/State/InspectorState.swift:33-62`——provider 注册模式（27+ 面板先例）；`App/Sources/Lightamer/{Yiyin,Export}/` 空占位目录 = 本 Phase 落点
- `LightamerCore/Sources/AI/`（Phase 7 移交）——服务层骨架/typed error/fence 模式可参照（yiyin 面板本身不消费 AI 蒙版）

### Integration Points（Phase 7 移交清单六面 vs 本 Phase）

| 移交面 | 本 Phase 对位 |
|---|---|
| RasterMaskRef / 层栈 API / mask 三 payload | 不消费（yiyin 无蒙版面）；LayerCompositeDriver 终端段是其相邻消费面 |
| 缓存面（零新缓存类） | 沿用：文字排版缓存走 paramsHash 前缀键族（同 maskPosition 先例），模糊 proxy 折进 borders piece 辅助平面记账 |
| skinSmooth 66.5 槽位 | 与 76/77 无冲突；非 dt 行纪律（只增不改）延续——本 Phase V50 零改动 |
| AIMaskService 复用面 / Vision 基建 | 不触及 |

## Specific Ideas

- **九宫格锚点语义**：`anchor: NineGridAnchor`（.bottomCenter 默认）作用于文字块/Logo 整体相对画布的定位；块内行堆叠仍按 yiyin 行内语义（自锚点边起排）——bottom-center 时与 yiyin 逐值一致（parity 不破）。
- **logoVariant auto 分派**：模糊背景用白 Logo、纯色背景用黑 Logo（`text-tool/index.ts:62-69` 语义）；`.auto` 读 borders 背景模式（同段联合布局上下文），`.black/.white` 手动覆盖；borders 缺席时 auto 按白底处理（黑 Logo）。
- **watermark-only 语义**：只挂 watermark 不挂 borders = 画布即原图尺寸，文字/Logo 直接叠主图（合法组合，轨 B 覆盖）。
- **超长文本**：沿用 yiyin 单行直排溢出语义 + 源码头注（`text-tool/index.ts:171-174` 自认 TODO）；不引入自动缩排（无需求支撑）。Manual-Only 表登记观感。
- **yiyin 参考样张**：`static/最终效果*.jpeg` + node harness PNG = 形状/版式对照素材（不做位图 parity）。

## Deferred Ideas

- **完整旋转/自由拖拽**（YIYIN-03/04 v2）——`rotation?` 参数位在 Params 预留（Codable 前向兼容），渲染 v1 不消费
- **parametric 尺寸联动**（YiyinExportSettings × EXP-07 多规格配方的 UI 编排）——Phase 11
- **内嵌 Logo 集扩充**（品牌增补/官方授权渠道）——v1 沿用 yiyin 26 件 + 授权标注；扩充随需求
- **文字排版跨平台 golden**（与 yiyin 位图对照）——永久不做法（L017 分流已定性），不再议

---

*Context gathered: 2026-09-25（planner 裁决定稿；8 项 Open Questions 用户已确认——D-08-CONTEXT-1..8 全部落定，REQUIREMENTS 注记随 plans 执行同批落地）。产物：本文件 + 08-01/02/03-PLAN.md；未提交 git。*
