# M5-2 RESEARCH NOTES — IOP-HDR-06 Mertens 曝光融合（discuss/research 起草批，2026-10-09）

> 读解正本 = Lumen 本地仓 `lumen/merge.py`（**MIT**，315 行全链亲读；本仓
> `/Volumes/UNITEK/Documents/Development/lumen-raw`）。我方基座 = Phase 8
> `LightamerCore/Sources/Stack/`（StackMergeService / HDRMergeMath / MTBAlign /
> FocusStackMerge / BandStreamer / ProvenanceReplay）。OQ 载体 = 同目录
> `M5-2-CONTEXT.md`。许可纪律见 §0。

## 0. 许可与借鉴纪律

- Lumen = **MIT**（`lumen-raw` 仓 LICENSE；与 darktable GPL-3.0 / Alcedo GPL-3.0
  的「只读参考思路、零代码复制」不同——**MIT 允许移植，成段移植须保留 MIT 归属
  注记**（CONVENTIONS 参考项目节原语义）。实践口径：Swift 重写为主，凡直译
  Lumen 常数表/算法段（如 deghost 三档表）在文件头注记 `Portions derived from
  Lumen RAW (lumen-raw, MIT)`；常数与公式本身不受著作权保护，注记从宽不从严。
- **OpenCV 不可入仓**：Lumen 的融合本体 = `cv2.createMergeMertens`
  （merge.py:167）——OpenCV 是 Apache-2.0 但体量大、违背零新 SPM 红线（M5 全站
  红线，M5-1-CONTEXT §验收形态复申）。**Mertens 数学自实现**（纯 Swift，论文
  Mertens-Kaus-Mey-Seidel 2007 公开算法 + OpenCV 行为锚），预测式与 Lumen 逐位
  不同属预期（见 §6 golden 设计）。

## 1. Mertens 2007 算法本体

**输入域**：display-referred 图像（归一化 [0,1]，gamma 域）。Lumen 文件头
即声明「Inputs/outputs are display-referred RGB」（merge.py:1）。

**逐像素权重（W = 三因子几何加权积）**：

```
W_i(x) = C_i(x)^wc · S_i(x)^ws · E_i(x)^we
  C = |Laplacian(gray(I))|          — 对比度（局部梯度幅度）
  S = std(R,G,B)  per pixel         — 饱和度
  E = ∏_c exp(−(I_c − 0.5)²/(2σ²))  — 曝光拟合（well-exposedness），σ=0.2
  wc = ws = we = 1.0（OpenCV/Lumen 缺省；merge.py:167 `createMergeMertens(1.,1.,1.)`）
```

归一化 `Ŵ_i = W_i / (ε + Σ_j W_j)` 后，朴素加权平均 `Σ Ŵ_i·I_i` 在权重突变处
产生 halo → **多频段融合（multiband blending）**：结果拉普拉斯金字塔逐层
`B^l = Σ_i G(Ŵ_i)^l · L(I_i)^l`（权重的**高斯**金字塔 × 图像的**拉普拉斯**
金字塔），塔顶加权平均、向下 collapse 还原。层数 = 分辨率自适应（OpenCV 内部
约到最小边 ≥ 小常数止）。

**本质**：无 CRF、无 EV 元数据、无辐射图——输出是**动态范围已压缩的
display-referred 融合片**（[0,1] 凸包内）。与 Robertson02 的根本分野：

| 维度 | Robertson02（我方 HDRMergeMath） | Mertens 2007 |
|---|---|---|
| 输出语义 | 场景参照**辐射图** L̂（可 >1.0，真 HDR） | display-referred [0,1]（融合即压缩） |
| EV/CRF 依赖 | 需 EXIF 快门差（ExifPrecheck 拒绝同曝光） | **零依赖**（无 EXIF 的 JPEG 包也能合） |
| 权重驱动 | 仅曝光域 w(p)=双门高斯（内容无关） | 内容驱动（对比度/饱和度/曝光拟合） |
| 鬼影模型 | 共识残差 rᵢ>k·σ̂ 置零（需辐射图共识） | 参考帧置换（无共识面，见 §2） |
| 下游关系 | 产物天然喂 scene-referred 管线 + DRT | 产物 = 成片观感；DRT 仅作再塑 |
| 速度 | ×2 decode pass（phase1+deghost） | 单遍金字塔（快一档，省 EV 预检） |

**互补结论**（ROADMAP M5-2 行「互为合并选项」的算法根据）：极端 bracket
（≥±2EV，高光要真 HDR 输出后调）走 Robertson02；轻 bracket（±1..2EV）、无
EXIF/非 RAW 素材、要「即合即用」观感走 Mertens。两者共存不互斥，共享
对齐/落地/队列骨架。

## 2. Lumen `merge.py` 全链读解（file:line）

### 2.1 入口与约束（merge.py:293-315 `merge_images`）

- 源数 **2..32**（:294）；reference 默认 0（:295）；RGB 三通道校验（:296-298）。
- 内存预检 `check_memory`（:39-43）：`pixels × (120 + count×80)` 字节 vs 可用
  内存 80%——OpenCV Mertens 的全帧原生临时面预算式（**我方不复用此式**，见
  §5：我方走 band-outer 流式，常驻与 N 解耦）。
- 对齐可选（`align` 开关，:303-306）；HDR 走 `aligned_stack` = SIFT+ECC 仿射
  （:46-97）——**我方不借鉴**：bracket 场景 MTBAlign（平移 ±128px）已交付且
  与 Robertson02 路径一致（见 §4.2）。
- 融合后 `inner_crop`（:100-117 最大全有效矩形）+ finite 校验（:313）。

### 2.2 deghosting 三档（merge.py:120-138 `ghost_mask`）

- 档位表：`{'low':(.20,2), 'medium':(.12,5), 'high':(.065,9)}` =（阈值，膨胀
  半径基数）（:121-122）。**三档 + REQUIREMENTS IOP-HDR-06「多档 deghosting」
  的正源**；阈值语义 = 亮度映射残差门（越小越敏感）。
- 机制：各帧与参考帧灰度 → 各自 33 点分位（2..98%）亮度映射到参考的灰阶
  （:123-131，抽样 `ceil(max/1000)` 省算）→ 高斯模糊 σ1.2 后取绝对差。
- **可用门**（:134）：两帧灰度均须在 (0.015, 0.985) 开区间内才计入运动证据
  ——「裁切帧缺比较细节，不是运动证据」（注释原文）。我方 Robertson02 的
  双门权重（clipGate/floorGate）同哲学，可直接互文。
- 膨胀半径随分辨率缩放 `radius × max(dim)/1800`（:136），再 Gaussian 羽化
  （:138）→ [0,1] 软运动掩码。

### 2.3 融合前参考置换（merge.py:141-169 `fuse_hdr`）

- 静止像素采样（motion<.01 的降采样格，:144-146）上估各帧→参考的**逐通道
  129 点分位映射**（:147-150, :159）。
- 置换式（:157-165）：`prepared = original·(1−α) + mapped_ref·α`（α = 运动
  掩码）——**融合前**把参考内容（调到各帧色调域）贴进运动区；注释明言「融合
  后再贴参考会在移动物周围留亮矩形」。这是对经典「选最佳帧贴补」的实质改进，
  **建议原样移植语义**（Swift 重写，MIT 注记）。
- 域注记（:151-152 注释）：MergeMertens 内部把 float 输入除以 255——保持
  [0,1] float 可避免 16-bit 数据先量化到 8-bit。**我方无 255 惯例，但「避免
  位深量化」的域纪律直接适用**（§4.4）。
- 融合调用 `createMergeMertens(1.,1.,1.).process(inputs)`（:167）→ clip
  [0,1] float32（:169）。

### 2.4 与我方对齐面的对照

Lumen HDR 对齐 = 通用多帧仿射（SIFT 特征 + ECC 回落，:46-81，为 pano/HDR
共用）；我方 bracket = 同机位平移假设，MTBAlign 已覆盖且带降级标签词汇
（`full`/`degraded`/`skipped-low-texture`）。**不换锚**——M5-3 PANO 才是
SIFT 面的主场（M5-3 项范围）。

## 3. 我方落地面设计（复用清单 + 扩展点）

### 3.1 扩展点总表（Core `LightamerCore/Sources/Stack/` 域）

| 触点 | 变更 | 语义 |
|---|---|---|
| `StackMergeService.MergeKind` | +`case hdrMertens = "hdr-merge-mertens"` | Codable raw value additive；CaseIterable +1（快照/白名单类测试随批 +1 行，BUNDLE-MAP/RegistrySnapshot 惯例） |
| `MergeParams` | additive optionals：`mertensDeghost: String?`（off/low/medium/high）+ `mertensWeights: (w?)`〔若裁参数化，见 OQ-3〕 | `encodeIfPresent` 惯例；旧 sidecar 逐字节零漂移专测 |
| `ProvenanceReplay.Kind` | +同名 case | provenance 词汇表 verbatim 镜像（两枚举 raw 值恒等） |
| 新文件 `MertensFusion.swift` | 纯函数族：权重图 / 拉普拉斯+高斯金字塔 / 条带融合 / deghost 掩码与置换 | golden 正本位（HDRMergeMath 同位）；文件头 MIT 归属注记 |
| `runProductionMerge` dispatch | `.hdrMertens → runMertensLeg(work)` | D-08-CONTEXT-3「kinds 只换尾段」原结构 |
| `defaultTag(for:)` | `.hdrMertens → "mertens"` | 产物 `<base>_mertens.tif`（与 `_hdr` 分账） |
| 队列/取消/进度/落地尾 | **零改** | actor 骨架 + ExportNamer + provenance sidecar 全复用 |

### 3.2 对齐与预检（与 Robertson02 的分叉点）

- **对齐：MTBAlign 原样复用**（同 runStackPrecheckAndAlignment 前半，含
  `full`/`degraded`/`skipped-low-texture` 标签与 NCC 可选自检豁免——Mertens
  用 NCC 无意义面弱，v1 `withNCC: false`）。
- **预检语义分叉（OQ-6）**：Mertens **免 EXIF EV**——`ExifPrecheck.precheck`
  的快门差严格预检**不适用**（其 `rejected` 分支会拒绝同曝光包，而 Mertens
  对同曝光包只是无收益并非非法）。推荐：Mertens 腿 = extent 一致性 + N≥2 +
  aperture/ISO 差异**降 warning 不拒绝**；EV 有则记 provenance（无则 0 占位
  ——`Source.exposureEV` 字段语义 = 「仅记录，权重不消费」，与 08-3 stack 族
  的 flat-zero 先例同形）。
- **曝光比运行时自检豁免**：`exposureRatioCheck` 依赖 EV 期望值，Mertens 无
  此输入——`exposureRatioVerified` 全 true 占位（landStackProduct 现形）。

### 3.3 融合腿流水（`runMertensLeg` 草形）

```
①decode N 帧（逐帧 renderFullFloatRGBA，线性 Rec2020 float32——与 08-1 同）
②每帧 display 编码 → [0,1]（OQ-2：sRGB piecewise 推荐；M3-1 LutEncodingCatalog
  曲线族现成，无新数学）
③deghost（档位 off/low/medium/high）：灰度 + 分位亮度映射 + 残差掩码 + 膨胀
  羽化 → 参考置换（§2.3 语义移植；off = 跳过整段）
④对齐：MTB shifts（③②可交换——置换在对齐坐标系做，移位采样同 StagedSet
  readShiftedPixels 惯例）
⑤staged 落盘（StagedSet：N×16B/px 暂存；~1.6GB/帧@100MP 磁盘价，focus-stack
  同价先例）
⑥band-outer 金字塔融合：每 band + halo 条带（FocusStackMerge.defaultHaloRows=32
  先例；**halo 须随层数缩放**——层数 L 的高斯支撑 ≈ 常数×2^(L−1)，32 行@5 层
  的既有常数起步，层数可配时按比例放大）逐源建金字塔、逐层加权、collapse；
  权重金字塔与图像金字塔同条带产出（Laplacian down/up 均为行带可算核）
⑦落地：float32 RGBA → ExportNamer（tag "mertens"）+ provenance sidecar
  （kind hdr-merge-mertens + algorithm name "mertens-exposure-fusion" +
  implementationVersion "1"）+ ghost 掩码落盘（GhostMaskWriter 复用，置换掩码
  即掩码语义——Robertson02 的 ghostUnion 同位）
```

进度步数：`stepTotal` 对 `.hdrMertens` = N(align) + N(encode/stage) + N(融合
按源计) + 3（write/sidecar/settle）——照 08-3 `sources*3+3` 形，`done ≤ total`
恒式不破。

### 3.4 输出域与 IOP-HDR-04 管线衔接（OQ-1 核心）

**推荐形态 A：产物 = display-referred [0,1] 的 32f TIFF（无内嵌 ICC）**。
下游衔接走 **M4-1 已交付的 raster ingest 链**（AGENTS「M4-1 Delivered」注记）：
无 ICC float32 → checker → sRGB 判定 → 逆变换（`outputTransform_inv`）→
sceneLinear → 常规编辑管线——**零新机制**，与 Robertson02 产物（scene-referred
辐射值直读）恰成两域两门。产物 provenance 的 kind 即域判别器（文档级事实：
`hdr-merge-mertens` = display 域产物）。

- 备选 B（伪辐射重映射：融合片 × 参考曝光 / 逆 OETF 后伪装 scene-referred）
  **不推荐**——Mertens 融合已完成动态范围压缩，逆映射只放大数值不复原被压缩
  的 range，产生「半假 HDR」文档（DRT 再拉伸会双重压缩伪影）；诚实域声明
  （A）让 DRT 对 Mertens 产物按普通 display 输入工作，语义干净。
- 备选 C（双产物：融合片 + 伪辐射片各落一份）——磁盘/UI 双倍负担，无场景，
  v1 不做。
- **plan-01 校验任务**：实测 Mertens 产物（[0,1] float TIFF）经 decodeRaster
  → rasterColor 链的端到端观感 + Robertson02 产物 >1.0 值路径的既有行为对照
  （Phase 8 VALIDATION 已覆盖编辑链零改，本项只补两域判别的回归钉）。

### 3.5 UI 面（OQ-4/6 的落点）

现状：HDR 合并 = SessionBrowser 选中 bracket → 一键 enqueue（`hdrMergeHandler`，
LightamerApp.swift:900 一带；toast `toast_hdr_merge_queued`）。推荐 v1 最小面：

- 「HDR 合并」入口扩为两项（context menu 子菜单或并排菜单项）：
  「HDR 合并（Robertson02）」（现行为原样=默认）+「HDR 合并（Mertens 快速）」
  → 后者 enqueue `.hdrMertens` + `MergeParams(mertensDeghost: "medium")`。
- deghost 档位 v1 **不弹面板**（默认 medium；Lumen 同为对话框默认值起步）；
  档位选择器挂账 advanced 面（OQ-3）。
- zh 键族：`merge_hdr_mertens_menu` / `toast_hdr_mertens_queued` 等，xcstrings
  尾块纯插入惯例；`MergeKind` 新 case 若进任何 Picker/文案走显式 switch 静态
  键（V14 形态，禁 `String.LocalizationValue("prefix_\(x))"` 动态键）。

## 4. 内存与性能预算

- **常驻面（band-outer 后）**：输出 plane（16B/px ≈1.6GB@100MP）+ 单 band 的
  N 源条带 + 金字塔条带组（每层 ≈1/4 面积，Σ≈1.33×band 面×N）——与 N 的
  全帧解耦；staged 磁盘 = N×1.6GB（临时目录，`defer` 清理——StagedSet 现行）。
- 对照：Lumen 预检式 `pixels×(120+count×80)`（:41）= OpenCV 全帧临时面形态
  （N×80B/px 全帧常驻）；我方 band-outer 把 80B/px 项从全帧压到条带——
  **预算式不移植，走 `test-direct.sh` ru_maxrss 机检（8G 运行门）+ 定向
  bundle 轮**（AGENTS 资源监控节；合成族新 bundle 或挂 IOPParity 域按
  BUNDLE-MAP 规则定）。
- decode 次数：Mertens 腿每源 2 次 render（对齐/预检 1 + staged 落盘 1，
  deghost off 时置换在 staged 数据上做则仍 2）——比 Robertson02 的 2+1 遍
  少一档，符合「快速第二模式」定位。100MP×N=5 实测量级 plan-01 探针出数
  （perf.md 惯例）。

## 5. golden 门草案（OQ-7 详表）

- **G1 确定性 bit-identity**：同输入双跑融合逐字节相等（全 CPU 顺序归约，
  零原子零并发归约——concurrentPerform 固定索引归并先例 M3-3/5-1）；provenance
  identity hash 稳定（createdAt/appVersion 排除面既有）。
- **G2 Float64 孪生 parity**：`MertensFusion` Float32 产线 vs 同文件 Float64
  孪生（M5-1 OklabMath 形态），p99.9 实测收窄钉门（拉普拉斯差分放大小数噪声，
  预期带 1e-6..1e-5，实测后钉字面）。
- **G3 合成语义靶**：①双帧恒等（同帧×2 → 输出==输入，权重归一凸包性）②
  已知鬼影构造（帧 B 局部块位移 → medium 档掩码命中且置换正确）③权重零化
  （过曝区 E→0 且无对比度补偿的构造面）④金字塔 collapse vs 朴素加权差带
  （halo 边界不渗——halo 缩放回归钉）。
- **G4 跨实现对照（非逐位）**：小图（≤256²）对 Lumen `fuse_hdr` 输出结构
  对照（权重积 + 金字塔形态一致 → 相关性/最大偏差量级报告，**不作门值**——
  OpenCV 内部常数未公开冻结，逐位不可达；跑法 = 仓外脚本一次性，证据入
  evidence/，测试不入 CI）。
- **G5 共存不回归**：Phase 8 全套 HDR/stack 测试零 diff 全绿（`hdr-merge`
  既有路径逐字节不动——additive dispatch 旁路）；App/IOP 快照族 +1 行随批。
- **G6 走查**：gui-acceptance Manual-Only 行（真 RAW bracket 双算法各合一张
  + deghost 三档对比截图），配方落 `.work/gui-acceptance/m5-2/MANIFEST.md`。

## 6. plan 切分建议（OQ 裁决后细化）

估 2 plans：**01** = MertensFusion 纯函数族 + MergeKind/Params/provenance
additive + runMertensLeg + G1/G2/G3/G5（Core 面，test-direct 定向 bundle）；
**02** = UI 两入口 + zh 键族 + provenance 域判别回归钉（§3.4）+ G6 走查 +
perf 探针。执行分工照 Phase 执行模型（omp 执行 + subagent 验收；config
`dual_acceptance = true`）。
