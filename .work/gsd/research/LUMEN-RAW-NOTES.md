# Lumen RAW 调研速记（2026-10-01）

> 来源：github.com/hety0211/lumen-raw（MIT，Windows 独占，Python 3.12 + PySide6 + NumPy/OpenCV/rawpy/LibRaw + ONNX Runtime，DirectML/TensorRT/CPU 三级，v1.3.1，193 回归测试）。面向风光/旅修的本地 RAW 工作台，中文界面。

## 与 Lightamer 的重叠面（不借鉴——我方已超集）
LibRaw 解码（我=CIRAW 9）/ Qt UI（SwiftUI）/ CPU spatial 算子（我=Metal 全 GPU）/ 分级 stage 缓存（我=per-module per-ROI + GAC 更细）/ 修图与快照 / 编辑同步 / 水印边框（yiyin 超集）/ 蒙版（我=M2-7 超集：brush/gradient/luminance/color-range/AI subject/Follow Edges）/ DRT（我=M2-6 OpenDRT+ACES 2.0，Lumen 无 DRT）/ 版本历史（M2-8）/ SQLite 库（M2-2）。

## 可借鉴候选（按价值排序，待用户裁决后入 REQUIREMENTS）
1. **单目深度 → IOP-MASK-07 数据面解锁**：Lumen 用 MiDaS 出 relative-depth 前景选择。我方 Depth 蒙版当时因「桌面 RAW 深度源稀缺」挂账——MiDaS 级单目深度（ONNX→CoreML）是现成解法，AI Background/Depth 蒙版可解锁。
2. **Mertens 曝光融合**：无 CRF 快速 HDR（三档 deghosting）——Phase 8 是 Robertson02 辐射图法，Mertens 可作第二合并模式（快/免 CRF 估计）。
3. **全景合成**：SIFT + 相机优化 + 球面投影 + 分块羽化（200MP 上限）——我方合成族（Phase 8：景深/堆栈）无全景，V2 候选。
4. **线性 RGB DNG 导出**：我方导出矩阵（JPG/PNG/TIFF/HEIF/WebP/AVIF）无 DNG 导出；Lumen/暗房类均支持 16-bit linear DNG（互操作/回传其他软件）。
5. **AI 增强的「可编辑 DNG 副本」UX**：Real-ESRGAN 超分 + DRUNet/NAFNet 降噪在独立预览对话框出片，结果作为新条目插入胶片条可继续编辑——M2-10 AI 图库之外的「AI 出片入工作流」模式。
6. **Crash-safe AI worker 进程隔离**：神经模型跑独立 worker 进程，GPU 驱动/EP 崩溃编辑器不死、tile 换设备重试、记住 GPU+driver 组合——M2-10 在 app 内跑 CLIP/推理时的健壮性范式。
7. **统一冲突表 + 单作业调度器**（加载/导出/AI/合并/蒙版推理/预览/缩略共用）——概念上近我方 BackgroundTaskHosting + L031 路由，已覆盖，仅记录。

## 明确不借鉴
AI 作用域 = developed RGB 非 mosaic（我方 RAW 9 在解码层融合降噪更强）；TensorRT EP 目录（Windows 专属）；运行时生成 GPU 图（Python 特定）；CuPy 实验分支。

## 裁决（2026-10-01 用户）

候选 1/2/3/5/6 **全部采纳**（登记：IOP-MASK-07 MiDaS 解锁注记 + 新「Photo Merging Extensions (v2)」节 IOP-HDR-06/IOP-PANO-01 + M2AI-09/M2AI-10 + ROADMAP M2-10 行扩充）；**候选 4（16-bit linear DNG 导出）不采纳**。

---

## 增量调研：v1.5.0 → v1.6.2（2026-10-13 夜间维护批）

> 本地仓已 ff（v1.5.0..v1.6.2 = 9 个 release commit，200 files / +86.7k 行；HEAD = `6a2b631`
> = v1.6.2（`e322aeb`）后再 1 个 logo SVG 资源 commit）。四版主题：1.5.0 自然语言编辑+语音输入 →
> 1.5.1 镜头校正+九语言 →
> 1.5.2 Nikon Z50II/Z5II NEF 修复 → 1.6.0 **scene-referred 处理版本 2 + 图库评级 + 统一命令层 +
> MCP** → 1.6.1 AI 蒙版边缘清理+导出元数据 → 1.6.2 广色域导出+JPEG 体积上限+水印品牌标志。
> 正本 = 仓内 `CHANGELOG.md`（逐条带实测数字，质量极高）。MIT 照旧。

### 1. scene-referred 转向实现面（1.6.0 处理版本 2，对我方 M6INT-01 的独立印证）

- **per-photo process version**：工程格式 v6 加 `process` 字段；新照片 = v2（scene-referred），
  旧工程/选片集/快照保持 v1 且导出与 1.5.2 一致（<1/1000 差）；「光影」面板显影起点下方显示
  版本 + 「升级」按钮（数值不变画面会变可撤销）；「将当前调色套用到选中照片」同时同步版本。
  → **与已交付的 M6INT-01/M6-2（sidecar v10 `process` 键）概念完全同构**——Lumen 独立收敛到
  同一纪律，是 M6-2 设计的第三方印证。可取细节 = **「升级」迁移 UX**（面板显版本号 + 一键升级 +
  可撤销），直接对应 M6-2 VALIDATION 挂账「迁移 UX 至首个真实 bump 批」——兑现该挂账时的 UX 参照。
- **scene-referred 技术面**（`lumen/develop*.py` 族，v2 腿）：RAW 解码不再截断色域（相机→sRGB
  矩阵移入浮点，域外色保留负值/>1，样片 0.2–3.5% 像素）；曝光/WB/亮暗部/白黑在线性光、显影曲线
  之前计算；显影曲线按**亮度**作色调映射（非逐通道截断），相机参考显影在 92% 亮度处接 filmic 式
  肩部（数值+斜率连续、指数逼近白、余量 2 档）→ 与我方 linear Rec2020 scene-referred + DRT 尾段
  同方向（我方已超集：完整 DRT 双 method vs 其单一肩部）。无新借鉴。
- **局部色调映射**：512px 对数亮度导向滤波出基底亮度决定增益（ε 0.2 档²，1.6.1 收紧到 0.05 档²
  光晕减半）；放大分块/分条导出用整幅同一组系数保逐像素一致 → 方法论注记（我方 shadhi 若走
  edge-aware 升级时参考；非当前需求）。
- **OkLCh 调色**（v2）：饱和度/自然饱和度/八色混合器/黑白/三段分级全移 OkLCh（Björn Ottosson
  OkLab）；皮肤保护 vibrance、明度调整随色度淡出 → **印证 LIGHTCRAFT-NOTES 面 5④ 候选**
  （「我方 GradeCatalog hls/colorWheels 色彩空间审计」）——两个独立项目（LightCraft/Lumen）先后
  收敛到 OkLCh 承载 hue/sat 算子，该审计项的证据面加强，判定维持「候选，低-中」不升级。
- **色域映射**（v2）：域外色保 OkLab 色相沿直线移向明度相近灰（Ottosson 自适应 L0，α=0.4），
  二分求位 + 区间内插一次保输入连续 → 同为 LIGHTCRAFT 面 5②「导出 gamut mapping 候选（中）」
  的第二实现参照（Ottosson 法有两个独立工程验证：映射不裁剪 + 逐块一致性）。
- **GPU 面警示**：Metal 的 v2 内核（develop2）**上游自认未在 Mac 上编译和实测**（「本次没有在
  Mac 上编译和测试」）——若参考其 Metal 腿须以 CPU NumPy 参考为真相源，不可信其 Metal 实现。

### 2. 统一命令层 + MCP（1.6.0，对我方 Phase 14 的同构印证）

- **27 条命令**（`app.status`/`library.rate`/`photo.open`/`edit.apply`/`render.preview`/
  `photo.export` 等）稳定 id + JSON Schema 参数逐项校验；**UI/命令面板（Ctrl+K）/CLI/本地控制
  通道/MCP 五前端同一入口**；调整类命令复用自然语言修图参数与校验；每命令 = 一步可撤销操作。
  → 印证 LIGHTCRAFT「命令注册表单源」范式（我方 LIGHTCRAFT 面 6② 观察项）。
- **MCP 面**：`lumen-cli mcp` stdio MCP（纯 Python 标准库），25 工具（列表/导入/选择/打开/信息/
  读应用调整/撤销/重做/重置/自动色调/预设/复制调色/process 版本/星级/旗标/色标/渲染预览〔返回
  JPEG + 亮度统计〕/导出/批量导出/存工程 + 按 id 执行任意命令）；协议双版支持（2026-07-28 无握手
  + 2024-11-05..2025-11-25 握手）；**窗口控制通道**（Windows 命名管道限当前用户）：助手操作直接
  显在窗口 + Ctrl+Z 可撤 + 状态栏「AI 助手：…」；app 未跑时后台独立处理。
  → 与 Alcedo agent GUI turn-taking 同主题；我方 MCP 编排皮判定不变（不立项 GUI 控制）。
  可取细节 = **render_preview 返回 JPEG 图像内容 + 亮度统计**（agent 自检出片质量的低成本面）——
  我方 render_preview 已返图，亮度统计属可选增强，注记。
- **图库评级/筛选/XMP**：星级/旗标/色标 UI + 快捷键（Lightroom 同款）+ `catalog.jsonl` append-only
  评级日志（即写即 fsync、崩溃丢半行、自动压缩）+ 字段筛选语法（`rating>=3 -flag:reject label:red`）
  + **XMP sidecar 评级读写与 `.lrcat` 评级导入** → XMP 读写被 `.xmp` 永不读写删红线挡死（不借鉴，
  维持前判）；评级 UI/筛选语法/append-only 日志 = 图库面参考（我方 M6-4 已交付 stacks；评级 UI 现状
  需核——set_rating/set_flag MCP 已有，in-app 评级 UI 若缺属 UI parity 项，列 V2 图库打磨观察）。

### 3. AI 蒙版边缘清理（1.6.1，算法面最有可借鉴性的一件）

- **问题**：识别网络只在 320×320（人物 384×384）跑，放大到 1600px 预览后边缘有 ~10px 渐变带；
  9×9 灰度导向滤波修不动（渐变多留背景侧）→ 压暗背景时主体外一圈亮边（贴纸感）。
- **解法两步**：①先把渐变**收窄到 0.5 附近**；②用**窗口覆盖整段渐变（两个网络像素宽）的彩色
  导向滤波**把边缘贴到照片颜色边界；深度「近景」的有意过渡不收窄；新蒙版默认羽化 10→3
  （实测：24MP 人像压暗背景 −1EV，肩外 ~80px 亮带消失，紧贴边缘 16px 内墙面 17/255→8/255）。
- **判定**：**候选（小，质量参考）**——我方 AI 蒙版（M2-7 AI subject + M6INT-03
  VNGenerateForegroundInstanceMask + hi-res patch 组装）分辨率路径不同（Vision 全辨析率请求 +
  patch ramp），无同款 320² 上采样渐变问题；但「彩色导向滤波贴边 + 渐变先收窄」对我方任何
  AI 蒙版边缘质量轮是现成小算法（OpenCV/CoreImage 均可承载）。**不立项**——列 M6INT-03 蒙版
  质量轮（若开）的算法参考；同批的「镜头校正后画面上识别 NL 蒙版」（1.6.1）对齐我方 lens iop
  默认禁用现状，无需动作。

### 4. 导出与水印（1.6.1/1.6.2）

- **导出保留原片元数据**（1.6.1，GitHub #5）：内置 ExifTool 写源 EXIF/版权/IPTC/XMP+GPS，
  排除集 = 尺寸/方向/缩略图/色彩空间/LR 调参/MakerNotes；失败不阻断 + 提示原因 → 与我方
  ExportMetadataPolicy STANDARD 同语义（我方走 ImageIO 无 ExifTool 依赖），无新借鉴。
  与 Alcedo `7052355` 同主题——两个上游同月独立补此面，语义收敛验证我方 M2-9 设计在位。
- **导出色彩空间选择**（1.6.2）：sRGB（默认）/Display P3/Adobe RGB (1998)；v2 照片色调+色彩阶段
  直接映射所选色域（保 OkLCh 色相）；程序生成 ICC v2 矩阵 profile（LittleCMS 验证）+ DNG 色彩
  矩阵；16-bit TIFF/DNG 无损往返；广色域渲染走 CPU → **架构注记**：我方导出 ICC = 本图 DRT
  encoding space 派生（Alcedo 对齐，EXPORT 页无独立空间选择器），Lumen 的「导出空间 ≠ 编辑空间」
  是另一范式；我方如需 P3 外广色域导出已有 DrtOutputColorSpace 七值显示域可扩。**不立项**。
- **JPEG 体积上限**（1.6.2）：目标 KB 下二分质量（下限 10）+ 降质时 4:2:0 色度采样 + 返回实际
  bytes/note → 小而美的导出工具面；**候选（低）**——M7+ 导出打磨批与 EXPORT-PRESET-01 同窗裁量。
- **水印品牌标志**（1.6.2）：按 EXIF 自动显示机身/镜头品牌字标（内置 19 个，Wikimedia Commons
  公有领域文字标志，SVG→512px PNG + 来源与校验值登记 `assets/logos/README.txt`）+ 对比度不足
  （<2.2:1）的字标自动改边框文字色 + 原厂镜头不重复显示机身标 + 品牌名文字去重 →
  **候选（中）——yiyin 印框/水印面板是一等公民**，此件直接是 yiyin 面的功能借鉴：EXIF 自动选标 +
  对比度自适应 + 去重三细节都可移植；许可面干净（公有领域文字标志，仍照例登记来源）。
  落点 = yiyin 面板规划批（非 REQUIREMENTS ID，yiyin 面 backlog 参照）。

### 5. 增量判定汇总（对照既有 5 采纳裁决，无新增 REQUIREMENTS ID）

| 发现 | 判定 | 落点 |
|---|---|---|
| process version + 「升级」迁移 UX | **印证 M6INT-01 已交付** | M6-2 挂账「迁移 UX」兑现时的 UX 参照 |
| OkLCh 调色 / Ottosson gamut mapping | 印证既有候选（LightCraft 面 5②④） | 判定不升级，维持候选（低-中/中） |
| AI 蒙版边缘（收窄渐变 + 彩色导向滤波贴边） | 候选（小）→ 不立项 | M6INT-03 蒙版质量轮算法参考 |
| 水印 EXIF 自动品牌标志 + 对比度自适应 + 去重 | **候选（中）** | yiyin 面板 backlog（许可干净：公有领域字标 + 来源/校验值登记先例） |
| JPEG 体积上限（二分质量 + 4:2:0） | 候选（低） | M7+ 导出打磨批，与 EXPORT-PRESET-01 同窗 |
| render_preview 返图 + 亮度统计 | 注记 | 我方已返图；统计可选 |
| 评级 UI/append-only 评级日志/筛选语法 | 注记 | 图库打磨观察（我方 MCP 评级面已有） |
| XMP sidecar 评级读写 / `.lrcat` 导入 | **不借鉴** | `.xmp` 永不读写删红线（维持前判） |
| 导出色彩空间选择器 | 不立项 | 我方导出 ICC = DRT 派生（Alcedo 对齐范式）；域内可扩 |
| ExifTool 元数据复制 / NL 蒙版镜头校正对齐 | 不适用 | ImageIO 路线 / lens 默认禁用 |
| Metal develop2 内核 | **警示** | 上游自认未在 Mac 实测——参考须以 NumPy 参考为真相源 |
