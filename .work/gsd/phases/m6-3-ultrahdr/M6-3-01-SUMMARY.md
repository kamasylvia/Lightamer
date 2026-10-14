# M6-3-01 SUMMARY — ALCE-03 UltraHDR gain map JPEG 导出（单 plan 全量批）

> 执行 = executor 夜间全自动批（授权先例 D-07-3-T5-1；2026-10-13/14）。
> plan 正本 = `M6-3-01-PLAN.md`（修订版 HEAD `56ea8461`+`01dc6e52`，checker 放行
> C-1..C-5）；裁决正本 = `M6-3-CONTEXT.md`（OQ-1..6 全 A + 增补 D-M6-3-7）。
> **ACCEPTANCE 不在本文**——验收方独立写（`M6-3-01-ACCEPTANCE.md`，双重验收
> 串行制）。

## 任务序与 commit 链

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `53a74582` | ExportVariant additive `gainMapHDR` + validate 六门 + `PixelPipe.linearGainCapture` 窄缝（KD-2 9 hunk）+ `ExportRenderer` capture 装配（owned-copy blit）+ `ExportQueue.ExportGainMapPlaneBox` 交接（stash/clear 生命周期） |
| T2 | `caa4113b` | `ExportGainMapEncoder.encode`（CI `.hdrImage` 全服务写 + 同目录 tmp 晋升 L009 + CopyImageSource XMP rewrap + 203 单源）+ `encodeStage` gain-map 臂（registry 旁路 + M4 fail-loud guard + strip/XMP 双旁路）+ queue encodeLeg consume |
| T3 | `e1ef7396` | M2 页 checkbox（五维可用门 + 三条不可用文案 + embedICC 复用 hint）+ 联动复位（页内 setter + run-face 复核兜底 C-2）+ `makeVariant` S4 落点 + 5 键 xcstrings 尾块纯插入 |
| T4 | `c077784a` | 尾 3 golden（基面保真 S1 漂移伞 / gain 语义 band / reimport raster 链）+ 零 diff 机检族全绿 + 9 hunk 逐 hunk 对照 |
| T5 | 本批 | SUMMARY + DECISIONS + MANIFEST（本文档批） |

## 定向轮终值（对账链）

| bundle | 终值 | 新法 | peak RSS | 判定 |
|---|---|---|---|---|
| Export | **378/4/0**（基线 353/4/0） | **+25**（ExportGainMapTests） | 5708MB | OK，零 MEMFAIL |
| App | **810/4/0**（基线 801/4/0） | **+9**（ExportGainMapPanelTests） | 2832MB | OK，零 MEMFAIL |
| IOP | 686/1/0（与 M6-2 基线一致） | 0 | 7975MB | 零漂移；贴线（<8192 门）无 MEMFAIL |
| Layers | 474/4/0（与 M6-2 基线一致） | 0 | 1163MB | 零漂移 |

- 新法合计 **34** ∈ plan `estimated_tests "+28..34"`；全套预期 = 3725 + 34 =
  **3759/24/0** ∈ plan 预期带 **3753..3759/24/0**（基线 3725/24/0 =
  M6-2-VALIDATION 终验亲证值）。
- **全套 `--all` 未跑**（orchestrator 批准制）——**批准申请**随本 SUMMARY 上报：
  预期 3759/24/0；贴线 bundle = IOP（本批定向轮 7975MB，重测顺序漂移 ±3%
  方差在案，MEMFAIL 机检兜底在位）。

## AC 对账（八条）

1. **OQ-1① capture 点** = DRT 尾 EOTF-box 前线性级（processRec 单处，EotfBox
   仅存在于尾段 assembly）；独立 EDR 链零存在（零新渲染文件/装配面）；门⑤
   （st2084/hlg 拒）+ 门⑥（yiyin 拒）validate 负测各一 ✓。
2. **OQ-2② EXIF probe** = **失败态**（`{TIFF}/Software` 路径被
   `CGImageMetadataSetValueWithPath` 拒，返 false）→ v1 无 EXIF（OQ-2 裁决②
   降级落位）；容器/aux/XMP 全存活负测 = `testGainMapArmSkipsTheICCStrip` +
   rewrap 双断言法 ✓（双态登记 = DECISIONS §1）。
3. **OQ-3③ hdrgm:Version** 在册（字节扫）+ rewrap 后 MPF/ISO APP2/aux 读回
   全 PRESENT（F5 门，`testRewrapSurvivesAndPolicyNoneStaysUltraHDR`）；C 路
   零代码零 NOTICE ✓。
4. **OQ-4④ 单通道** = aux 读回 PixelFormat 'L008' + BytesPerRow == width ✓；
   `hdrGainMapAsRGB` 全仓零代码命中（唯一 grep 命中 = 测试 doc comment 引用
   该键名陈述其未启用——语义即「不开」）。
5. **OQ-5⑤ UI 位** = SDR 节 checkbox 五维门 9 法 + 三态不可用文案 + 联动复位
   负测（embedICC off → 旗标复位）+ run-face 复核兜底（C-2，Assembly 携带
   blocked 维度 + toast）+ enqueue 联动（makeVariant 落点 + OQ-7 双写）+
   203 阈值 = `ExportGainMapEncoder.sdrReferenceWhite` Core 单源 + encoding
   维 = `isHdrEncoding` Core 单源 ✓。
6. **OQ-6⑥ 无新 tag** = formatName 恒 "jpeg"（ExportFormatSpec 类型面零
   diff；grep 无新 tag 常量/分支）；Namer 既有测试原样绿（Export bundle 全绿
   含之）✓。
7. **零回归门** = 四文件 + S3 五文件 + ExportICCStrip 本体（ExportEncoder.swift
   文件级）+ ExportQueueContract + ExportFormatSpec 面 + ExportState 零 diff
   全部机检零命中；PixelPipe/LayerCompositeDriver diff 恰 = KD-2 9 hunk
   （7+2，hunk-header 逐一对照在 DECISIONS §2）；`.metal`/dependencies/
   UserDefaults 零 diff；runModal/LocalizationValue 插值禁形零命中；非
   gain-map 负测 + 既有套件原样绿（Export 378 全绿含全部既有面）✓。
8. **SC 数字门** = Export +25 / App +9（34 ∈ +28..34）；全套预期 3759 ∈
   3753..3759；plan「App +8」为 planner 近似（实落 9 法，维度恰覆盖五维门
   5+复位+装配+enqueue+默认关），SC 带内 ✓（DECISIONS §6 勘误注记）。

## 挂账申报（建议验收后闭环批统一翻账）

- **AGENTS.md 增量节（建议 M6-3 架构增量）**：CI 全服务路定式（`.hdrImage` +
  CopyImageSource rewrap——AddImageFromSource 丢 MPF 的雷）+ 203 单源三消费点
  + encodeStage 后处理门双旁路（MPF 绝对偏移雷）+ box 交接形（contract 外
  queue 级载体 + fresh-seq 清理）+ capture queue 同队 FIFO（CIContext
  mtlCommandQueue 缝）。
- ROADMAP M6-3 行 ✅；REQUIREMENTS ALCE-03 兑现终态注记；TODO M6-3 条目；
  GOAL-STATE 续接点（= 验收轮 + `--all` 批准轮）。
- 遗留观察（不阻断）：①跨生态目检 = Manual-Only（MANIFEST 配方在位，不可达
  行不阻断收口）；②`v1 无 EXIF` 六格式矩阵唯一 additive 档偏离已裁（OQ-2）；
  ③IOP 贴线 7975MB 重测漂移观察（±3% 方差，M2-4-0 SPIKE 注记口径）。
