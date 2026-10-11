# M5-3 CONTEXT — IOP-PANO-01 全景合成 research（discuss/research 起草批，2026-10-15）

> Phase = M5-3（ROADMAP §Milestone 5 M5-3 行：SIFT 特征匹配对齐 + 相机参数
> 优化 + 球面投影 + 分块羽化融合，输出 100MP+ 大图入正常编辑管线；M5 最大
> phase 估 2-3 plans）。本文 = 研究定稿载体 + **C 档第 1 停裁决面**
> （OQ-M5-3-1..7 交用户；全带推荐，用户可随时推翻）。读解正本 = 同目录
> `RESEARCH-NOTES.md`（§ 引用见各条）。Lumen 参考锚 = 本地仓
> `lumen/merge.py:192-315`（MIT，模式借鉴；成段移植带 MIT 归属注记）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。

## Phase Goal（ROADMAP/REQUIREMENTS 原文锚定）

IOP-PANO-01：全景合成——特征匹配对齐 + 相机参数优化 + 球面投影 + 分块羽化
融合，输出 100MP+ 大图入正常编辑管线；v1 合成族（HDR/焦点堆栈/降噪堆栈）
之外的新合成模式。验收形态 = 对齐/投影/羽化分段 golden + 大图内存预算
（8G 运行门）+ 走查。

## 决议（D-M5-3-N，均带推荐；最终裁定 = 对应 OQ）

### D-M5-3-1 算法链形态（RESEARCH §1-§2）

- 推荐**六段链全盘采纳 Lumen 形**（特征匹配 → 相机估计/BA → 波校正 →
  球面投影 → 曝光增益 → 分块羽化融合 → 有效域裁切）；特征/相机段跑
  ≤1200px 预览域，全分辨率只参与投影与 tile 融合——内存与工时双赢。
- 相机模型 = **单焦 f + 每图旋转 R**（BA 参数 3N+1）；refinement 范围与
  Lumen 同形（f + R，无畸变/tilt）。几何不连通/对齐失败 = typed 报错
  三态，绝不静默丢图。**最终裁定 = OQ-M5-3-2。**

### D-M5-3-2 特征/对齐实现路线（RESEARCH §3.2）

- 推荐 **A 自实现**：多尺度关键点（DoG 或 Harris-Laplace，plan 期 spike
  定）+ 定向 patch 描述子 + knn 比值检验 + RANSAC 单应——纯函数 +
  种子化 RNG（LCG 先例），确定性/G1 bit-identity 完全自握。
- 备选 B：Vision `VNHomographicImageRegistrationRequest` pairwise（省
  特征面；确定性无承诺、置信语义不透明）作低纹理回落 spike 候选。
- 被否：OpenCV SPM binary / 任何新 SPM（M5 全站零新 SPM 红线；AGENTS
  依赖最小化）。**最终裁定 = OQ-M5-3-1。**

### D-M5-3-3 数值面零依赖（RESEARCH §3.3）

- 推荐 focal-from-homography 初值 + 自实现 LM/Gauss-Newton BA（稠密
  数值差分 + Accelerate 线性解；M5-1 固定 Jacobi 零依赖先例）+ 横向
  wave correct（R 首行堆叠最小特征向量，标准式纯函数）。
- 被否：per-image 独立焦距/畸变/tilt、multiband 融合（v1 收益边际，
  V2 另议）。**最终裁定 = OQ-M5-3-2。**

### D-M5-3-4 融合色彩域与产物（RESEARCH §3.4/§3.7）

- 推荐**全链 sRGB 编码 float32 [0,1]**（Mertens 腿同域）+ 产物 =
  sRGB-tagged 32f TIFF（`writeFloatTIFF` additive 先例）→ M4-1 raster
  ingest 重导入——合成族域一致性 + 落盘/重导入链零新面。
- 被否：scene-linear Rec2020 域融合（与合成族断层 + 新增色彩转换落盘面）。
  **最终裁定 = OQ-M5-3-3。**

### D-M5-3-5 画布/张数/裁切门（RESEARCH §3.5/§3.7）

- 推荐 **200MP 输出帽**（Lumen `PANORAMA_MAX_PIXELS` 同值）+ bounded_rois
  等比收缩循环（×0.998 ≤8 轮）；张数门 **2..32**；**inner_crop 最大有效
  矩形恒 on**（v1 无开关；直方图栈纯函数 + naive 参考对照）；alpha 不写。
- 融合 = 512px tile 流式 + valid 掩码单通道 + BandStreamer 行带写；
  ru_maxrss < 8G 门机检（预算探针钉，实测入 perf.md）。**最终裁定 =
  OQ-M5-3-4 / OQ-M5-3-5。**

### D-M5-3-6 计算面 CPU/GPU（RESEARCH §3.6）

- 推荐 **v1 纯 CPU**（Accelerate/vImage；零新 `.metal`——Mertens 全程
  纯 CPU 先例）；预算探针越门 → GPU kernel 化另立 plan（零新 kernel
  红线 = per-phase 纪律，立项才动）。**最终裁定 = OQ-M5-3-6。**

### D-M5-3-7 MergeKind additive 与 UI 范围（RESEARCH §3.1/§3.8）

- 推荐 `MergeKind.pano = "pano-merge"` additive 第七 case + `runPanoLeg`
  腿 + provenance/tag `_pano`/stepTotal 独立恒式（enqueue/进度/分账面
  全复用，六既有 kind 零回归红线）。
- UI = Session legacy face merge 菜单第三项「全景合成」+ 简形 sheet
  （Mertens 先例；v1 零/极少控件，文案注明 30% 重叠/同视点/2 亿像素帽/
  恒自动裁边）；**v1 不做**（V2 挂账）：预览画布 / 参考帧手选 / use_edits。
  **最终裁定 = OQ-M5-3-7。**

## Open Questions（OQ-M5-3-1..7，全带推荐；C 档第 1 停裁决面）

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| **OQ-M5-3-1** | 特征/对齐实现路线 | **A 自实现**（多尺度特征 + RANSAC 单应，确定性全握、G1 可钉） | B Vision pairwise homography（省工但确定性无承诺）；A+B 混合（B 作低纹理回落 spike） |
| **OQ-M5-3-2** | 相机模型与 BA 范围 | **单焦 f + N×R，LM BA（3N+1 参数）+ 横向 wave correct** | 扩 per-image 焦距/畸变（V2）；不做 BA 仅单应拼接（质量退） |
| **OQ-M5-3-3** | 融合色彩域 | **sRGB 编码 float32（Mertens 同域）+ sRGB 32f TIFF 落盘** | scene-linear Rec2020（working 纯度 + 新落盘转换面） |
| **OQ-M5-3-4** | 画布/张数帽 | **200MP + ×0.998 收缩循环；2..32 张；预算探针 ru_maxrss<8G 钉** | 100MP 帽（更保守）/ 8G 门实测后再定 |
| **OQ-M5-3-5** | 落盘与裁切 | **恒 inner_crop（v1 无开关）+ alpha 不写 + `_pano` 分账 + provenance details（canvas/gains/crop）** | crop 开关进 sheet / alpha 写入（valid 面语义另表达） |
| **OQ-M5-3-6** | CPU/GPU 分工 | **v1 全 CPU（Accelerate；零新 .metal）；越门 GPU 化另立 plan** | v1 直接 GPU kernel（warp+feather 天然 compute 形，预算未证需要） |
| **OQ-M5-3-7** | MergeKind 面与 UI v1 范围 | **`.pano` additive + Session legacy 简形 sheet（零/极少控件）；预览/手选参考/use_edits 挂 V2** | 独立 PanoService / v1 带预览画布（工时显著增） |

## 风险与红线

- **特征自实现质量** = 最大不确定项（低纹理/重复纹理匹配失败）——typed
  失败面 + G2 合成靶先证数学面 + Vision spike 对比轮候补。
- **红线**：零新 SPM（M5 全站）；darktable GPL 零复制；OpenCV detail
  （BSD）API 语义只读；Lumen MIT 成段移植带归属注记；既有六 kind +
  密封面零 diff（G5 机检）；`--all` 全套轮批准制 + 8G 运行门（AGENTS
  资源监控节）。
- **plan 建议 3 plans**（RESEARCH §6）：P1 数学核心（特征/BA/波校正 +
  G1/G2）→ P2 生产腿（投影/融合/落盘 + G3/预算）→ P3 UI 与收口
  （G4/G5/G6/拼表）。

## 下一步

**C 档第 1 停**：OQ-M5-3-1..7 交用户裁决（全带推荐）→ 回批后 plan round
（执行分工照 Phase 执行模型 = omp 执行 + subagent 验收）→ M5-4 VALIDATION
兼「全史瘦身手术」第二次（strip 集重算非空才动手）。
