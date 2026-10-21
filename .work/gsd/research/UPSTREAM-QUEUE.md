# UPSTREAM-QUEUE — 新特性立项阶段的 upstream 候选

> 用途：参考上游增量同步批判定「值得入队」但**不立新 REQUIREMENTS ID** 的小件候选，集中在此。
> 消费时机 = **下一修复批收口后、新特性立项前**，由 orchestrator 逐项裁决（立项 / 续挂 / 撤销）。
> 已落地的项移文末「已兑现」节留痕。既有 EXPORT-PRESET-01 已落
> `ALCEDO-PARITY-2026-10.md` §二 REQUIREMENTS V2 候选节，不在此重复。
> 建档：2026-10-16（Alcedo +19 / lightcraft +43 同步批）。
> **2026-10-16 M7 charter 批：四候选全部入队**（用户裁决③「按推荐」生效）——立 REQUIREMENTS ID：UQ-A1 → M7-6 / UQ-A2 → M7-4 / UQ-L1 → M7-6 / UQ-L2 挂面不入波；本文件为来源正本，兑现后按惯例移文末「已兑现」节。

## 候选区（Alcedo，正本 = ALCEDO-PARITY-2026-10.md §五）

| # | 候选 | 上游锚 | 我方缺口 | 规模 | 入队理由 |
|---|---|---|---|---|---|
| UQ-A1 | DRT-SDR 预览层 colorspace 改挂导出同款 ICC v4 字节（`CGColorSpace(iccProfileData:)`）+ ColorSync 解码等值测试 | `36db9a8`（#391） | 预览层挂 calibrated-RGB 近似空间（srgbPiecewise 以 2.2 幂近似分段），导出文件携 ICC v4——preview/文件双曲线解码失配，上游实测同病同修 | 小件 | M4-1 色彩收尾批顺路；消除 SDR 幂编码观感差；L053 自建字节直接复用 —— **已入队 2026-10-16 = REQUIREMENTS UQ-A1 → M7-6** |
| UQ-A2 | 导出 FAIL 档终写原子不覆盖（tmp 编码 + `link()` EEXIST 拒晋升 + unlink tmp） | `6203791` | `.fail` = occupiedNames 快照检查 + 编码器直写——快照与落盘之间他进程建文件即被覆盖（TOCTOU） | 小件 | ExportCollisionPolicy 语义补全；上游以 renameatx_np/renameat2 落地同纪律，Swift 走 `link()` 排他即达 —— **✅ 已兑现 2026-10-17（M7-4-01，见文末已兑现节）** |

### 未来面纪律（对应面立项时吸收，不单独立项）

- 自动化/MCP 输出面**排他创建 + 失败清理自建物**（`1f12551`）——MCP thumbnail/preview 类生成命令扩面时。
- CLI 壳 `--version` 旗标惯例（`ace755e`）——若建随包 CLI。
- session-prune「只删自家记录」（`c1a66b4`）——若建 prune 面；sidecar 隔离设计已天然满足，届时核对即可。

## 候选区（LightCraft，正本 = LIGHTCRAFT-NOTES.md §七）

| # | 候选 | 上游锚 | 说明 | 规模 |
|---|---|---|---|---|
| UQ-L1 | 滑杆双击重置 + 值横扫 scrub（KEY-SLIDER-RESET/SCRUB） | `cb8b797c` `ab64e9a5` | SwiftUI Slider 无原生支持需自实现；yiyin 面板与我方 iop 面板通用 UX，两件合一个滑杆 UX 小件 | 小件 —— **已入队 2026-10-16 = REQUIREMENTS UQ-L1 → M7-6** |
| UQ-L2 | 软打样 1:1 zoom window + 「1:1 像素 == 导出」等值测试验收形态（LR-VIEW-ZOOM） | `c78b457c` | 软打样未立项；立项时验收形态直接取用（挂软打样面，不独立排期） | 挂面 —— **已入队 2026-10-16 = REQUIREMENTS UQ-L2（挂面维持，无 phase 指针）** |

### 方法论一次参考（不排队）

- Faces 网络整体 GPU 化的「GPU 批处理 + CPU-only 回退开关 + 限速使用」模式（`0242a75b`/`f625c74c`）——M2AI 推理 worker 设计前翻一次实现即弃。
- 蒙版笔刷 Shift-click 直线笔画（`e5c6e17b`）——我方笔刷若建，Lightroom 惯例对齐。

## 候选区（RawLab，正本 = `research/RAWLAB-NOTES.md`，2026-10-20 用户裁「六缺口按推荐优先级入队」）

来源 = `github.com/dancancer/RawLab`（GPL-3.0，跨四平台共享 C++17 核，0.5→0.8.2 十天五版；已加为第七参考项目，正式克隆 `/Volumes/UNITEK/Documents/Development/RawLab`）。推荐优先级即下表序：

| # | 候选 | 上游版本 | 我方缺口 | 规模 | 备注 |
|---|---|---|---|---|---|
| UQ-R1 | **渲染 float32 DNG 导出**（单图+批量，baked 调整，保留捕获元数据，尺寸/方向更新） | 0.7.0 | 导出矿阵六格式无 DNG | M | 路线 = TIFF/EP 标签自写或 Adobe DNG SDK（许可链须查——SDK 许可与 GPL 参考纪律分离评估）；用户价值 = 下游 LR/C1 可续编 |
| UQ-R2 | **透视校正（keystone）**：裁切/旋转/摆正族邻接扩展，Metal warp | 0.8.0 | parity 零条目（有 crop/rotate/straighten/flip 无透视） | S-M | dt `ashift` 算法参考；与 crop 面几何管线同缝 |
| UQ-R3 | **一键自动曝光 + 新片打开默认嵌入预览曝光匹配** | 0.6.0 | parity 零条目 | S | UX 感知件（新片打开即近相机 JPEG 观感）；saved-baseline 兼容语义照抄 |
| UQ-R4 | **Lensfun 数据只读镜头校正落地**（profile 数据 + Metal warp + 手动选型 + 自动裁切） | 0.7.0 | FEAT-DEV-07 Partial（仅嵌入 opcodes） | M | 既定 v1 立场兑现（FEAT-DEV-07 验收目标 = Alcedo 同款 profile database + auto-detection）；RawLab 生产实证数据路线可行 —— **⬆ 2026-10-20 用户令「要 Lensfun 落地」→ 拉正立项 LENS-01，research 在飞**（GPL 切换后 dt lens.cc/RawLab 实现可同许可移植；Lensfun = 库 LGPL-3 + 数据 CC-BY-SA-3.0，数据归属独立处理） |
| UQ-R5 | **可续传批量导出**（冻结设置 + 跨重启恢复 + 取消 + 失败重试） | README/0.8.x | 我们有 retry 无跨重启续传 | S-M | 导出队列持久化面（M2-9 队列的 disk-backed 扩展） |
| UQ-R6 | **主配方系统**（多调整 + 24 HSL 打包预设 + 0-200% 强度同缩 LUT + 风格图） | 0.6.0 | 预设面 = LUT/导出/复制粘贴，缺「调整包+强度缩放」形态（Alcedo 亦无） | M | 14 配方+29 创意 look 的打包形态参照；强度缩放语义（当前值同缩）注意与既有 preset 语义对齐 |

### 架构不可达注记（不计缺口，永续备查）
DCP 外部 profile 导入（CIRAW 不接受外部 DCP，FEAT-DEV-04 既定 out-of-scope）/ Nikon HE/ARW6、X3F、JXL-DNG 解码（Apple 解码覆盖决定）/ 跨平台四端 / RUM 使用统计（不采）。

### 顺路消解注记
R5 随 F0'-prod 顺路 14 项中 2 项（N-D7/N-L30）将随 P3 退役自然消解——与 RawLab 六候选无交集。

## 候选区（Lumen RAW，正本 = `.work/gsd/research/LUMEN-RAW-NOTES.md` 2026-10-21 增量节，2026-10-21 用户裁「高价值和中价值落地；两件特殊（延时视频/Lightroom 预设导入）不选」）

来源 = `github.com/kamasylvia-sync Lumen RAW` v1.7.0/2.0.0/2.0.1（10-17~10-21 三版；本地克隆 `/Volumes/UNITEK/Documents/Development/lumen-raw`，**MIT**——可复制带归属）：

| # | 候选 | 上游版本 | 我方缺口 | 规模 | 备注 |
|---|---|---|---|---|---|
| UQ-LU1 | **连拍分组 + best-of-burst**（同机身+序列号 ≤2s + 16×16 灰度相似归组；睁眼优先再取最清晰；折叠连拍） | 2.0.0 | culling 域无分组概念 | M | 选片工作流核心；与 LU2 配套（闭眼/清晰度喂 best 选择） |
| UQ-LU2 | **清晰度 + 闭眼批量提示**（图库后台低优先级分析入库；清晰度 = 结构加权块导数能量比；闭眼 = 人脸眼睑比——**Apple Vision 原生可替代 YuNet/MediaPipe**，M6-4 先例）+ 智能相册条件扩展（`eyes/sharp/burst` 族） | 2.0.0 | 无 | M | 与 LU1 配套；智能相册条件语言对照扩展（`date:2026-10` 语法可学） |
| UQ-LU3 | **快速选片视图**（全屏 = 相机内嵌预览直接解码零 RAW 解码 + ±3 预读 + 100% 优先内嵌 JPEG + C 并排对比缩放同步） | 2.0.0 | culling 域为 MCP 工具，无 GUI 选片视图 | M | M2-3 档A 内嵌预览缝现成；Lightroom 惯例选片键位（0-5/P/X/U） |
| UQ-LU4 | **智能预览缓存**（1600px 线性 float16 字节平面重排压缩持久 LRU 4GB；重开 50ms；缓存键含 mtime+版本；**GUI/CLI/MCP 三前门共享**） | 2.0.0 | 编辑级持久解码缓存无（M2-3 档A 会话内 + .lathumbs 仅缩略图） | S-M | perf 模式；`float16 相对误差 <0.05%` 结论可直接引用 |
| UQ-LU5 | **AI 蒙版精细边缘**（快速蒙版 → 原图 ≤4096px 精细化；采样式抠图零新模型：边缘带像素颜色 = 近邻前景/背景混合；天空 ≥30% 置信扩、暗细节可切出；MCP `refine_masks`） | 1.7.0 | M6-4 分割蒙版无边缘精细化（羽化路线已走 logit-gain） | M | 技术优雅（采样式 alpha）；与 M6-4 羽化共存形态待 research |

### 未入队登记
- 直方图分区拖动（1.7.0）→ 归入 UQ-L1 滑杆 UX 族一并落地。
- 调色吸管（1.7.0，取色设分级区域色相）→ 小候选登记不排队（分级面板顺路时可带）。
- 延时摄影视频（2.0.0，关键帧调整插值 + 去闪烁）→ **用户裁不选**（跨 RAW 编辑器 scope）。
- Lightroom 预设导入（1.7.0）→ **用户裁不选**（撞既定「预设不互通」决策）；方法论登记：换算系数测试照片拟合 + 未映射设置如实报告。
- XMP 单写队列模式（2.0.1）→ 我方不写 XMP（N/A）；模式优秀登记备查。

## 已兑现

- **UQ-A2**（2026-10-17，M7-4-01 `2af9b17d`）：encodeStage additive `exclusiveFinalWrite` + 同目录隐藏 tmp + link() EEXIST → `BaseNameOccupiedError` 复用 + encoder-error 清理腿改道（exclusive 臂 destination 不可触）+ `$jobNamingCarrier` encode 腿递缝；**我方分歧申报 = 保留 render 步快照检查**（成本门非正确性门——与上游 6203791 删 exists() 检查不同构，DECISIONS §3）；exFAT 类卷 EOPNOTSUPP → encodeFailed 兜底（行为变化申报；**EOPNOTSUPP 降级回 plain rename 的可选项在此挂账**——外置卷实测需要时立项，勿静默）。

## 观察项（M7-4-01 挂账兑现，2026-10-17 入队）

| # | 来源 | 内容 | 触发条件 |
|---|---|---|---|
| OBS-M7-4-1 | D-M7-4-3 | `list_tasks`/`wait_task` 通用任务 tracker 面（两新工具 + tracker 基建；union 29→31） | 万级目标批实测超 applyBatch 60s 窗才立项 |
| OBS-M7-4-2 | D-M7-4-6 | paste per-target 版本化（Alcedo `e75cf2a` 同构——预贴态隔离） | 预贴态隔离需求实测出现才立项 |
| OBS-M7-4-3 | D-M7-4-1 | 库域批量写（`.lalb` claim 面 + sidecar 直写 + 投影刷新缺口设计） | 万级库域批量需求实测出现才立项 |
| OBS-M7-4-4 | D-M7-4-8 | withTimeout v2 abandon 形语义族专项（~20 工具共用，per-call-site 纪律） | M7-5+ 评估；B 线独立专项 |
| OBS-M7-4-5 | M7-4-01-ACCEPTANCE-2ND minor-3（VALIDATION §挂账②） | paste 段3 drain 写失败不进应答——`appliedRelPaths` ENQUEUE 后即全量填充〔语义 = composed+claimed〕，`flushForTeardown` drain 失败仅 log；MCP paste 应答在 drain 失败路径仍报 `applied`，「写达后方返」契约对 agent 单步视角失真（heal leg 最终一致但单步不可见；非本批引入——apply_params M7-3 同姿势 + 段3 语义 M6-09-04 writer 既有设计） | MCP 后续波 touching paste/apply_params 写应答面时诚实化（applied 语义诚实化〔改名/注记 composed+claimed〕或 drain 失败回传 failedRelPaths），勿顺手修 |
