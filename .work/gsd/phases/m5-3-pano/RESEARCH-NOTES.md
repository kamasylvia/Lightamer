# M5-3 RESEARCH NOTES — IOP-PANO-01 全景合成（球面全景拼接链读解与落地面设计）

> Phase = M5-3（ROADMAP §Milestone 5 M5-3 行；REQUIREMENTS「Photo Merging
> Extensions (v2)」IOP-PANO-01）。参考正本 = Lumen 本地仓
> `/Volumes/UNITEK/Documents/Development/lumen-raw`（**MIT**——算法/公式/模式
> 可转录；成段移植须保留 MIT 归属注记，Mertens 先例 = `MertensFusion.swift`
> 头注）。OpenCV `cv2.detail`（BSD）API 语义只读参考，代码零复制；darktable
> GPL 参考位不触。状态 = research 起草（2026-10-15 合并批 subagent），OQ
> 裁决前不进 plan（C 档第 1 停）。

## §1 参考链总览（Lumen `lumen/merge.py:192-315` + 周边模块）

Lumen 全景 = **特征匹配对齐 → 相机参数优化 → 球面投影 → 曝光增益补偿 →
分块羽化融合 → 有效域裁切** 六段。输入输出 = display-referred RGB float32
[0,1]（`merge.py:1`）。关键工程事实：

- 特征/相机估计**全部跑在 ≤1200px 预览**上（`panorama()` 第一步
  `small(im,1200)`，`merge.py:215`）；全分辨率只参与投影与融合（tile 流式）。
- 相机模型 = **单焦距 f + 每图旋转 R（3×3）**，无畸变、无每图独立焦距
  （BundleAdjuster refinement mask 只放开 f + R，`merge.py:243`）。
- 内存纪律 = `large_image.py`：单 buffer ≤256MB 进 RAM，以上转 tmp 目录
  numpy memmap 磁盘后备（`allocate`，weakref.finalize 清理）；全局面
  `validate_size` 400MP 帽；写读全走 64 行 strips。

## §2 逐段读解（行锚 = merge.py 原文）

### §2.1 输入门（`merge_images` :293-315）

- 张数门 2..32；参考帧门 0..N-1；RGB 形状校验 + 400MP 单图帽
  （`large_image.validate_size`）。
- pano 分支：`output, valid, info = panorama(images, reference, ...)`（:300）；
  堆栈族（hdr/focus）另有 align/crop 两开关，pano **恒球面 warp**（UI 面
  align 控件对 pano 隐藏，`merge_dialog.py:95`）。

### §2.2 特征与匹配（:214-238，预览域）

1. 预览 `small(im, 1200)`（≤1200px 长边，INTER_AREA）。
2. `cv2.setRNGSeed(121)`（:220）——**确定性种子显式设置**（RANSAC 类随机
   过程锚定；测试可复现的前提）。
3. SIFT `nfeatures=6000`，输入 = 0-255 uint8 预览（注释：SIFT 在低对比
   摄影地形上比 Stitcher 默认 ORB 稳，:217-218）。
4. 匹配 = `BestOf2NearestMatcher_create(False, .3, 6, 6, 3.5)`——best-of-2
   最近邻 + Lowe 比值 0.3；注释（:225-227）：默认 cutoff 3 会把「异常一致
   的匹配对」当重复图丢弃，密集良对齐纹理也会超 cutoff，故收紧参数保留
   （confidence 公式上界 10/3）。
5. 建图：`confidence > .6 && num_inliers >= 10` 为有效边（:233）。
6. **连通性门**：从参考帧 BFS 并闭包；`len(connected) != len(images)` →
   typed 报错「部分照片没有足够重叠」（:238）——几何不连通的图不被静默丢弃。

### §2.3 相机估计与优化（:239-247）

1. `cv2.detail_HomographyBasedEstimator`——由成对单应估计初始旋转与焦距
   （focal-from-homography 经典闭环）；失败 → typed 报错（视差/模糊/重复
   纹理/重叠不足，:240）。
2. `cv2.detail_BundleAdjusterRay`（射线式 BA），conf 阈 .6，refinement
   mask 3×3 只放开 **f + 全部 R 分量**（:243）——参数面最小化：N≤32 图
   = 3N + 1 个标量。
3. `waveCorrect(WAVE_CORRECT_HORIZ)`（:246）——水平波校正：对全部 R 的
   首行（相机 x 轴）堆叠矩阵求最小特征向量，将「上方向」全局摆正到地平线。

### §2.4 尺度回投与画布帽（:249-254, :192-202）

- `matrices = inv(preview_scale) @ camera.K()`——把预览域标定 K 缩回全
  分辨率；全局投影尺度 = 各图焦距**中位数**（:251，抗单图离群）。
- `bounded_rois`（:192-202）：≤8 次迭代——`PyRotationWarper('spherical',
  scale).warpRoi` 求每图 ROI → 并集 bounds；若 `w*h > PANORAMA_MAX_PIXELS`
  （**200MP**，:12）→ `scale *= sqrt(max/(w*h)) * .998` 等比收缩重投；
  8 轮不达 → typed 报错。**输出分辨率上限由此机制而非固定缩放决定**。

### §2.5 球面投影核（`spherical_map` :205-211）

纯函数、无 OpenCV 依赖（numpy 广播），可直接转录（MIT）：

```
画布像素 (x,y) → u=(x+x0)/scale, v=(y+y0)/scale（球面经纬角）
ray_sph = (sin v · sin u, −cos v, sin v · cos u)
camera  = ray_sph @ R
project = camera @ Kᵀ；z>1e-6 为有效，否则坐标 = −1（无效标记）
```

全分辨率融合时**逐 tile 调用**（512px tile，:274），即投影映射按需计算、
从不物化整画布映射面。

### §2.6 曝光增益求解（:258-273）

- 低分辨率（≤900px 长边）把每图球面采样进画布坐标 → 重叠域 pairwise：
  两图重叠 ≥80px 且双值 ∈ (.04,.9)（排除黑场/高光裁剪）→ 方程
  `g_i − g_j = median(log(J_j/J_i))`。
- 参考帧锚定方程（权重 10，值 0）+ **最小二乘联解**（`np.linalg.lstsq`）；
  `gains = exp(clip(x, −.5, .5))`——增益上限 e^.5 ≈ **1.65×**，防单对
  噪声炸增益。
- 注释（:257-258）：几何不连通的照片不会因无重叠方程而静默丢失（锚定 +
  lstsq 的最小范数性质）。

### §2.7 分块羽化融合（:274-289）

- 512px tile 扫画布；每 tile 对 ROI 相交的每图：`spherical_map` 取源坐标
  → `inside` 门（坐标在图内）→ **边缘羽化 α = clip(到源图边缘最近距离 /
  (min(ih,iw)×.12), .001, 1) × inside**——即每图各自 12% 短边宽的渐出带，
  非 mask 羽化而是**逐图几何边缘带**（全景拼接的常用形，重叠区多图权叠加）。
- `accum += warped × (α·gain)`；`weight += α`；输出 = `accum/max(weight,
  1e-8)`，clip [0,1]；`valid = weight>0`（有效掩码逐 tile 落）。
- remap INTER_LINEAR + BORDER_REPLICATE（贴边复制防 seam 假黑）。

### §2.8 有效域裁切（`inner_crop` :100-117）

- valid 掩码 → ≤1024-cell min-pool 网格（保守：一格任一像素无效即无效格）
  → **最大全有效矩形** = 直方图栈算法（逐行高度 + 单调栈，O(cells)）。
- 恒等式：找不到非空矩形 → typed 报错（:115）。crop 由 `merge_images`
  统一执行（`crop=True` 默认，:311-312），info 记录 `[x0,y0,x1,y1]`。

### §2.9 收尾与产物（:310-315 + merge_dialog）

- `finite` 全图逐 strip 校验；NaN → typed 报错。
- UI（`merge_dialog.py`）：预览合成（1400px）/ 正式合成两键；参考帧自动 =
  像素最多（同尺寸取中间帧，:16-20）或手选；`use_edits` 开关（用各图当前
  显影 or 统一参考帧显影基准，:42-48）；命名 = `<参考帧 stem>-全景合成.dng`
  （O_EXCL 递增防撞，:23-31）；产物 = **16-bit linear DNG**（:127-128），
  provenance = `{operation, sources[], reference, details{canvas, projection,
  pixel_limit, gains[]}}`；入图集并打开。
- 调度：job 队列 priority 10 + cancel event + 分段 progress（读图 0-10 /
  相机 22 / 画布 35 / 融合 35-90 / 保存 94-96）。
- 诊断 harness（`merge_diagnostics.py`）：**从单张照片合成受控变体**
  （投影生成 pano 输入而非实拍序列）跑三族合成断言——「合成输入走查通道」
  先例，与我方 Mertens G3 合成靶同构，golden 策略直接借鉴。

## §3 我方落地面设计（Lightamer）

### §3.1 MergeKind additive 第七 case（推荐，最终裁定 = OQ-M5-3-7 关联）

`MergeKind.pano = "pano-merge"` additive（现有六 case 零触碰，`StackMerge
Service.swift:249-256` 体例）+ `runPanoLeg` 腿函数 + provenance kind
`panoMerge` 镜像 + `stepTotal(.pano)` 独立恒式（decode N / align 相机 / 
blend 分块 / write+settle 尾段——plan 期定）。复用面 = enqueue 族 /
MergeParams additive optional / `landStackProduct` additive（canvas 尺寸、
gains 记录面）/ Session legacy face merge 菜单 / zh 键族尾块纯插入。
**被否形态**：独立 PanoService（绕开合成族骨架 = 双份 enqueue/provenance/
进度账，Mertens 已证 additive 路径零回归可达）。

### §3.2 特征/对齐实现路线（核心研究问题；推荐 = 自实现，裁定 = OQ-M5-3-1）

macOS 无公开 SIFT/ORB 特征 API（Vision 无关键点检测公开面；Core Image 无
匹配器）；OpenCV `cv2.detail` 不可引入（依赖最小化红线 + SPM binary 巨包
违反零新 SPM）。三选项：

- **A（推荐）自实现特征与匹配**：多尺度 KeyPoint 检测（DoG 或
  Harris-Laplace，二选一 plan 期 spike 定）+ 定向 patch 描述子（灰度
  归一 + 主方向 + 8×8/16 维梯度统计，rootSIFT 式 L2 归一）+ BF knn 比值
  检验 + RANSAC 4-point 单应（DLT）——**全部纯函数 + 种子化 RNG（LCG，
  FilmPrintBake 测试先例）**，确定性/可 golden 完全自握。工作量 = 本 phase
  最大单件（故建议 3 plans，见 §6）。N≤32 图全 pairwise 匹配 O(N²) 在
  预览域（≤1200px、6000 特征帽）可接受（Lumen 同形）。
- **B（备选）Vision pairwise**：`VNHomographicImageRegistrationRequest`
  出成对单应——省特征面，但 ①确定性无承诺（golden 只能容差门）②置信度/
  inliers 语义不透明（连通性门需自建评分）③多图 focal 估计仍需自实现
  （focal-from-homography）。作 A 的低纹理回落 spike 候选（对比轮可选）。
- **C（被否）OpenCV SPM binary / 私有框架搬运**：违反零新 SPM 红线
  （M5 全站）+ 依赖最小化约束（AGENTS Constraints）。

匹配失败语义 = **typed 报错**（对齐失败/不连通/画布无效三态，Lumen 文案
语义同形），绝不静默丢图。

### §3.3 相机估计 + BA + 波校正（自实现数值面；裁定 = OQ-M5-3-2）

- 模型 = **单焦 f + N×R(3×3)**（§2.3 同形）：初始 = focal-from-homography
  经典式（两单应合成 H=K₂R K₁⁻¹ 分解出 f 初值）；BA = 自实现
  Levenberg-Marquardt/Gauss-Newton（残差 = 射线夹角重投影，参数 3N+1；
  N≤32 规模 Jacobian 稠密数值差分即可，`Accelerate` 线性解）——**M5-1
  S1 固定 Jacobi 零依赖先例**证明自写数值面可行且可钉 golden。
- 波校正 = 横向 wave correct（R 首行堆叠最小特征向量，标准式，幂等纯函数）。
- 被否形态：per-image 独立焦距/畸变/tilt（Lumen 亦未做；摄影面收益边际）；
  multiband 融合（blend 复杂度换 seam 收益，v1 用几何羽化带先交）。

### §3.4 融合色彩域（推荐 = display-referred sRGB 编码；裁定 = OQ-M5-3-3）

- 推荐：全链在 **sRGB 编码 float32 [0,1]**（Mertens 腿同域——
  `DrtEotfMath.srgbPiecewise` 接缝现成）做特征灰度/增益/融合；产物 =
  sRGB-tagged 32f TIFF（`writeFloatTIFF` additive colorSpace 先例，M5-2
  T2）→ M4-1 raster ingest 重导入编辑。理由：①合成族域一致性（HDR/focus/
  mertens 全 display 域）②增益 median-log 求解在单调编码域有效 ③落盘/
  重导入链零新面。 
- 被否形态：scene-linear Rec2020 域融合（working-space 纯度更高，但与
  合成族域断层 + 落盘需色彩转换新面 + 32f 线性域羽化带观感无差）。

### §3.5 内存与画布预算（裁定 = OQ-M5-3-4）

- **200MP 输出帽**（Lumen 同值）+ `bounded_rois` 等比收缩循环（×0.998，
  ≤8 轮）移植；张数门 **2..32**（Lumen 同值；上限由 pair 匹配 O(N²) 预览
  域成本背书）。
- 融合内存 = **tile 流式**（512px tile：accum+weight 每 tile 常驻 O(tile²)
  + 每图 ROI 相交跳过）+ 有效掩码单通道 UInt8 全画布 + 产物经 BandStreamer
  行带写 32f TIFF（Mertens StagedSet/行带面复用）——估算 200MP：valid
  mask 200MB + 输出写缓冲行带级 + 特征预览域 <1GB，**ru_maxrss < 8G 门
  可达**（预算探针机检钉，M2-11/M5-2 惯例；实测数入 perf.md）。
- 大 buffer 磁盘后备（Lumen memmap 形）v1 **不做**——行带写已覆盖产物面；
  若探针越门再议（挂 perf.md 观察项）。

### §3.6 CPU/GPU 分工（推荐 v1 全 CPU；裁定 = OQ-M5-3-6）

- 推荐 v1 = **纯 CPU**（`Accelerate`/vImage 双线性 remap + 逐 tile 融合；
  数值面 §3.3 同域）——Mertens phase 全程纯 CPU 先例（`*.metal` 新增 0
  红线先例形态）；remap+feather 每 tile 独立、缓存友好，CPU 预算内可达
  （Lumen CPU 全链 ~分钟级 @100MP 级）。
- 预算探针（PERF_PROBE env 门）实测：200MP 画布 × 8 图 tile 融合墙钟 +
  ru_maxrss；**越门 → GPU kernel 化另立 plan**（球面 warp+羽化 accumulate
  是天然 compute kernel 形，但零新 kernel 红线是 per-phase 纪律、需立项
  才动）。
- 被否形态：v1 直接 GPU（新增 `.metal` + PSO 面，预算未证需要）。

### §3.7 落盘与裁切（推荐 = 恒裁 + 无 alpha；裁定 = OQ-M5-3-5）

- 产物 = sRGB-tagged 32f TIFF（§3.4）；**inner_crop 最大有效矩形恒 on**
  （v1 无开关；Lumen crop 默认 on 同形）——有效掩码直方图栈算法纯函数
  （naive 参考实现做 golden 对照）。
- alpha 通道**不写**（valid 掩码信息在恒裁后已表达；M4-1 raster 链 alpha
  丢弃语义不变）。
- 命名/分账 = `defaultTag(.pano) = "pano"` → `_pano` 后缀（`_mertens`
  ExportNamer 先例）；provenance = `operation: pano-merge` + sources[] +
  reference + `{canvas, pixelLimit, gains[], crop}`（Lumen details 同构）。

### §3.8 UI 走线与 v1 范围（裁定 = OQ-M5-3-7）

- Session legacy face（merge 菜单仅 legacy 面有，Project face 无入口——
  Mertens omp 走查在案）第三项「全景合成」+ **简形 sheet**（Mertens 先例：
  标题 + body 说明 + 取消/开始，v1 零/极少控件——文案注明「重叠 ≥30%、
  同一视点、画布上限 2 亿像素、超限等比缩小、恒自动裁边」）。
- **v1 不做**（V2 挂账）：预览合成画布（1400px preview）/ 参考帧手选 /
  use_edits（用各图当前显影）/ deghost 类档位（pano 无此面）。
- typed 报错三态进 toast（对齐失败 / 不连通 / 画布无效），文案入 zh 键族。

## §4 golden 策略（分段，ROADMAP 验收形态「对齐/投影/羽化分段 golden」）

| 段 | 门 | 形态 |
|---|---|---|
| G1 确定性 | 双跑 bit-identity | 我方核心（投影/羽化/增益/crop/BA）纯函数双跑逐位；特征段 = 种子化 RNG 双跑一致（全链闭环轮） |
| G2 合成恢复靶 | 容差门 | 已知 K/R 渲染合成网格景（受控单图变体，Lumen `merge_diagnostics.py` 先例）→ 恢复 R/focal 对照真值；连通性门正反测 |
| G3 分段 golden | 逐段精确 | `sphericalMap` vs 闭式解逐点；feather 带宽/权重归一/零权=invalid；gain lstsq 合成方程组恢复；innerCrop vs naive O(N²M²) 参考实现；boundedRois 帽循环不变式 |
| G4 OpenCV 结构对照 | 非门值 | uv 仓外 bench（M5-2 G4 先例）：cv2.detail.Stitcher 链 vs 我方链结构形态一致 + 数值报告在册，不入 CI |
| G5 共存零回归 | 红线机检 | 既有六 kind 快照/字节零漂移 + 密封面零 diff + 零新 SPM + V50Order/Registry 零触 |
| G6 走查 | Manual-Only | 三张重叠样张合一张 + crop 观感 + `_pano` 分账 + 重导入编辑链（配方落 gui-acceptance/m5-3/MANIFEST.md） |
| 预算门 | 机检 | 预算探针：200MP×8 tile 融合墙钟 + ru_maxrss < 8G；MEMFAIL 兜底（test-direct 惯例） |

## §5 风险登记

- **特征自实现质量** = 最大不确定项（低纹理/重复纹理景匹配失败率）；缓解
  = typed 失败面 + Vision pairwise spike 对比轮（OQ-M5-3-1 若裁 B/混合）
  + G2 合成靶先证数学面。
- **RANSAC/特征确定性** = 种子化 LCG + 禁系统随机源（grep 门）；VN*
  请求若引入则该段只可容差门（G1 覆盖面在 plan 期收窄申报）。
- **BA 数值稳定性** = 病态几何（近纯旋转退化为单应 / 平面场景）收敛失败
  → LM 阻尼回落 + typed 失败；容差带 plan 期实测收窄（M4-1 parity 先例）。
- **200MP 融合内存** = tile 流式可控（§3.5 估算）；探针证伪则磁盘后备
  buffer 提上（Lumen memmap 形）。
- **许可**：Lumen MIT 可转录（成段移植带归属注记）；OpenCV detail API 语义
  只读参考（BSD，代码零复制）；darktable GPL 零触碰。

## §6 plan 划分建议（3 plans，C 档第 2 停逐 plan 汇报）

- **P1 数学核心**：特征检测/描述子/匹配/RANSAC 单应 + focal-from-homography
  + LM BA + wave correct（全部纯函数 + golden G1/G2 + 单元域）。
- **P2 生产腿**：runPanoLeg 装配（bounded_rois + spherical_map + 增益 +
  tile 融合 + inner_crop + BandStreamer 32f sRGB 落盘 + landStackProduct
  additive + provenance/stepTotal）+ G3 分段 golden + 预算探针。
- **P3 UI 与收口**：菜单第三项 + 简形 sheet + zh 键族 + typed 报错面 +
  G4 OpenCV 对照 evidence + G5 红线机检 + G6 MANIFEST + 拼表对账。
