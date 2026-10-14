# M6-3 CONTEXT — ALCE-03 UltraHDR gain map JPEG 导出（spike 定稿 + OQ 裁决落签批，2026-10-13 夜间）

> Phase = M6-3（ROADMAP §Milestone 6 M6-3 行：ALCE-03 解冻——LightCraft 裁决②，
> 用户回批 2026-10-11 全按推荐）。本文 = OQ 裁决正本；读解正本 = 同目录
> `RESEARCH.md`（spike 实测 + 两臂对照 + 集成面测绘 + §7 OQ 原文 + §8.4
> ExportICCStrip 雷）。
>
> **授权注记：本裁决为夜间全自动授权批落签（先例 D-07-3-T5-1），六项全按
> RESEARCH 推荐采纳；晨审/用户可随时推翻，推翻项回注 plan 修复批重走。**
>
> 状态：research 定稿（`RESEARCH.md`，2026-10-14 夜间批）→ OQ 裁决落签
> （本文）→ plan round（`M6-3-01-PLAN.md` 同批起草）。

## Phase Goal（ROADMAP M6-3 行锚定）

SDR base + HDR 增益层 JPEG 导出（ISO 21496-1 gain map）。charter 纪律 =
**原生路容器字节达标即收，不达标落移植**。验收形态 = spike 结论落档 ✓（三路
对照 + 容器字节级验证，`RESEARCH.md` 已交付）+ 导出链集成（`ImageIOEncoders`
JPEG 腿 additive，六格式矩阵零改动红线）✓ + DRT-HDR/EDR 源图端到端 ✓。

spike 主结论（RESEARCH §Summary）：ImageIO 手挂 aux（A 臂）与 destination 生成
键族（B 臂）在 macOS 27 实测均为死路；**可行原生路 = Core Image 全服务写**
（`CIContext.writeJPEGRepresentation` + `.hdrImage`，macOS 15+；容器 MPF APP2
索引 + ISO APP2 + 尾部 gain map 副图 + HDRToneMap 元数据全亲证落盘）；LightCraft
Rust 移植（C 路）降兜底（见下）。

## 裁决（D-M6-3-N，全按 RESEARCH §7 推荐；生效值 = 硬约束）

### D-M6-3-1 HDR 面取平面点 = DRT 尾 EOTF-box 前线性级（OQ-M6-3-1①）

HDR 线性面 = **同一 DRT 尾在 EOTF-box 之前的线性级取平面**（display-referred
linear float32；`DrtEotf.linear` 为 legalEOTFs 既有成员，linear 特例通道在案）。
理由：单一 record 单源，两臂（SDR base / HDR linear）逐字节同链只差终级；
独立 EDR 渲染链 = 第二真相源，弃。spike E4 反证在案——PQ/HLG 编码码值直喂
`.hdrImage` 容器合法但 gain 语义非物理，**必须喂线性光**，故取平面点钉死在
EOTF-box 之前。

### D-M6-3-2 EXIF 路径 = metadata 路 probe 先行 → 降级接受 v1 无 EXIF（OQ-M6-3-2①→②）

CI 写路 + rewrap 面当前只实证 XMP（spike F5：`CGImageDestinationCopyImageSource`
+ `kCGImageDestinationMetadata`，gain map 结构逐字节存活 + 自定义 XMP 落盘）。
裁决 = T2 执行期在同一 F5 缝**先 probe metadata-namespace EXIF**：probe 成功 →
gain map 档带 EXIF round-trip；probe 失败 → **v1 接受无 EXIF**（挂账文案 +
DECISIONS 注记，六格式矩阵仅此 additive 档偏离）。自建 APP1 EXIF 注入器
（③）不入首批——段级注入移动文件内绝对偏移，与 MPF 副图偏移互斥，风险大
收益小。

### D-M6-3-3 `hdrgm` XMP 兼容档位 = primary XMP 补 `hdrgm:Version` 接受（OQ-M6-3-3①）

CI 产物 gain map 副图只有 ISO APP2 + Apple HDRToneMap（无副图内嵌 `hdrgm`
XMP）。裁决 = **接受**：primary XMP 经 rewrap 补 `hdrgm:Version`，目标生态 =
Apple 全量 + 现代 Android 13+/Chrome（读 ISO 21496-1 容器）；老 Android/老
Chrome（读副图 hdrgm XMP）**非硬需求**。**LightCraft 移植臂（C 路）据此降
兜底封存**——仅当本条被推翻（老 Android 裁为硬需求）时激活（RESEARCH §2：
~400+ 行容器装配 + NOTICE 义务 + 段级 golden 全套）；当前零代码移植、零
NOTICE 义务。跨生态目检走 Manual-Only 走查批留证（RESEARCH §8.1）。

### D-M6-3-4 gain map 通道数 = 单通道亮度（OQ-M6-3-4）

单通道 'L008'（CI 默认）——Apple 生态标准、文件更小；`hdrGainMapAsRGB` 不开
（spike D2：RGB 档读回侧 Data 键被 reader 扣留，JuniperPhoton 同报）。

### D-M6-3-5 M2 页 UI 位 = SDR 导出节 checkbox（OQ-M6-3-5①）

gain map 开关落 M2 检查器 **SDR 导出节 checkbox**；可用门 = `drtOutput != nil`
（M2 页 OQ-7 强制联动语义）∧ format == `.jpeg`，另加派生门 peak ≥ 203 nits
（headroom = peak/203 ≥ 1.0，低于 = 无 HDR 余量）；不可用态给
ExportICCStrip 文案形说明。理由：格式级旋钮归格式节；DRT readout 节是
readout 非旋钮面。

### D-M6-3-6 命名/输出 tag = 不加新 tag（OQ-M6-3-6①）

gain map 档不引入新 tag/formatName（仍 "jpeg"）——容器本就是超集 JPEG，同池
冲突递增语义正确；新 tag = 占位面膨胀，弃。

## 范围与红线预告（细则 = `M6-3-01-PLAN.md`）

- 六格式矩阵既有路径零 diff（`ExportFormatSpec` 类型 / 既有五编码器 /
  `ExportEncoderRegistry` / quantizer 阶梯全零改；新增面 = `ExportVariant` 一
  字段 + `encodeStage` 一分支 + 新文件 `ExportGainMapEncoder`）。
- **ExportICCStrip 雷（RESEARCH §8.4）**：`stripJPEGICC` 删 APP2 段会使 MPF
  副图绝对偏移失效——gain map 档 `embedICC=false` = typed 不可达（validate
  拒），`ExportICCStrip` 本体零 diff。
- 零新 SPM；`ExportQueueContract` 封存面零 diff（HDR 面交接走 queue 级载体，
  M2-9-02 KD-4 递缝范式同族）；`.metal` 零 diff（gain 计算全在 CI 黑盒内）；
  V50Order/HistoryHash/sidecar schema 零触。
- 风险边界（RESEARCH §8）：CI 黑盒行为漂移 → golden 钉「容器结构 + 读回字典」
  非字节级全量；跨生态目检 = Manual-Only 走查批。

## 状态

research 定稿 + OQ 全裁（本文，夜间授权批）→ plan round
（`M6-3-01-PLAN.md`，执行分工照 Phase 执行模型；plan_review_by_omp = true，
双重验收 dual_acceptance = true）。

## 裁决记录

**OQ-M6-3-1..6 全部按 RESEARCH 推荐采纳（全 A，夜间全自动授权批 2026-10-13，
先例 D-07-3-T5-1，晨审可推翻）**：①HDR 线性面 = DRT 尾 EOTF-box 前线性级取面
（禁独立 EDR 链）②EXIF = metadata 路 probe 先行、失败降级 v1 无 EXIF（禁自建
APP1 注入器）③primary XMP 补 `hdrgm:Version` 接受、LightCraft C 路降兜底封存
④单通道 'L008'（`hdrGainMapAsRGB` 不开）⑤M2 页 SDR 导出节 checkbox
（drtOutput≠nil ∧ .jpeg ∧ peak≥203 可用）⑥不加新 tag（仍 "jpeg" 同池）。
