---
phase: m4-3
plan: "M4-3-01"
title: "IOP-MASK-07 Depth 蒙版单 plan——DA V2 Small Apple 官方 F16 件资产链（GitHub Release 登记脚本 + SHA-256 digest + LICENSE/NOTICE 随行 + manifest additive inputShortEdge/family 派生）+ M2AI-10 worker 第三推理腿（DepthSession + family 分派 + crash-safe 降档链）+ 深度→近景蒙版四段 Core 纯函数管线（Lumen selection.py:71-74 同参 0.48/0.22 窗 + 10/95 分位 + smoothstep + typed 平坦深度守卫）+ App 编排面（preview PATH 通道 + float 读回 + 既有 commitRasterMask 通道 + zip 解包 resolver）+ 蒙版工具栏单「深度」入口（下载态门）+ golden 三件套（abs-rel ≤0.01 精度门 + 同设备逐字节确定性门 + 合成靶语义门）+ 三档延迟 perf 探针"
wave: 1
depends_on: []
autonomous: true
requirements: ["IOP-MASK-07", "M2AI-10（底座复用——零协议破坏）", "M2AI-01（分发链复用——additive）", "IOP-MASK-03/04/05（消费面零新机制）"]
estimated_tests: "+26..32"
test_bundles: [LAYERS, LIB, APP]
files_modified:
  - LightamerCore/Sources/AI/ModelAssetCatalog.swift            # 修改：additive `inputShortEdge: Int?`（nil = 既有正方形语义，五 profile 零漂移）+ 派生 `family`（clip/enhancement/depth 单源判别式，零新存储字段）+ 第六 profile `depthAnythingV2SmallF16`（tier .gitHubRelease / releaseTag ai-models-v1 / licenseName Apache-2.0 / inputSize 518 + inputShortEdge 396）
  - LightamerCore/Sources/AI/ModelAssetDigests.generated.swift  # 修改：REWRITABLE ENTRIES 尾块增 depth 条目（build 脚本 sentinel 机制重写真 digest；发布前 nil = fail-closed 既有面）
  - LightamerCore/Sources/AI/AIMaskTypes.swift                  # 修改：AIMaskError additive case `noDepthStructure(String)`（平坦深度/近空覆盖两触发一门；生成失败腿严格语义照抄）
  - LightamerCore/Sources/AI/DepthMaskPipeline.swift            # 新建：四段纯函数（percentile 10/95 线性插值归一 → 近景窗 (r−0.48)/0.22 → smoothstep → α 平面）+ 守卫常量 + 有效性守卫（退化域 + 近空覆盖）
  - App/Sources/Lightamer/AI/AIWorkerDepth.swift                # 新建：worker 侧 DepthSession（HEADLESS：Foundation/CoreML/ImageIO only；包解析→编译缓存→前向 518×396 静态形状；inPath 解码→缩放归一→run→outPath 写 F32 LE + w/h 头）
  - App/Sources/Lightamer/AI/AIWorkerMain.swift                 # 修改：open/run 按 `manifest.family` 三腿分派（clip 腿/enhancement 腿原样保留 + depth 腿新 depthSessions 字典；profile 资产缺席 = 无 culprit typed 错误帧）
  - App/Sources/Lightamer/AI/AIWorkerClient.swift               # 修改：additive `runDepth(profile:inPath:outPath:)`（enhanceTile 同构——withFallbackChain 降档 + run 级错误不耗链）
  - App/Sources/Lightamer/AI/DepthMaskService.swift             # 新建：App 编排面（@MainActor @Observable：DepthEntryGate 纯函数四态 + DepthPackageResolver zip 解包（/usr/bin/ditto，Lensfun 先例）+ preview JPEG 写盘（长边 1040 帽）+ float 读回 → Core 管线 → commitRasterMask + 切图竞态守卫 + 下载触发/进度）
  - App/Sources/Lightamer/State/AIMaskEditing.swift             # 修改：AIMaskSource additive case `depth = "ai-depth"`（fileName 前缀/source(ofFileName:) 循环 additive）
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift      # 修改：单「深度」入口组（ready 生成 / needsDownload 引导下载 / downloading 进度 / failed 重试；AI Subject 同款入口形态；零参数面）
  - Resources/Localizable.xcstrings                             # 修改：depth 键族尾块纯插入（预期 +7：ai_mask_depth / ai_mask_depth_download / ai_mask_depth_download_help / ai_toast_depth_no_structure / ai_toast_depth_download_done / ai_toast_depth_download_failed / history_depth_mask）
  - Scripts/ai-models/build-depth-release-asset.sh              # 新建：构建期资产管线（HF 直采官方 F16 件→SHA-256→zip 内随行 LICENSE/NOTICE→digest sentinel 重写；模型字节不入仓，产物落 ~/Library/Caches/LightamerModels/depth/；uv 惯例）
  - Scripts/ai-models/gen-depth-golden.py                       # 新建：构建期 golden 生成器（uv run + coremltools predict：F32 参考件跑固定输入集 → Tests/Fixtures/DepthPrecision/ref-f32.bin + README 实测分布）
  - Tests/Fixtures/DepthPrecision/                              # 新建：固定输入样张（真实 RAW 降采样 + 合成渐变）+ ref-f32.bin 参考输出 + README 来源/门值注记（生成器可再生）
  - Tests/LightamerTests/DepthMaskPipelineTests.swift           # 新建（LAYERS/Core 级）：percentile 对 numpy 参考值锚/窗带/smoothstep 端点/合成靶三断言/斜坡单调/纯函数性扫描/平坦与近空 typed 负测/byteIdentity 确定性
  - Tests/LightamerTests/DepthMaskEditingTests.swift            # 新建（LAYERS，AIMaskEditPathsTests 先例）：AIMaskSource.depth 命名往返/DepthEntryGate 四态映射/float 文件头往返/preview 长边帽几何/coordinator 直驱 commit 一次 item
  - Tests/LightamerTests/DepthGoldenTests.swift                 # 新建（APP，模型在场 env 门控 XCTSkipUnless）：精度门 abs-rel ≤0.01 + max-abs 上限/同设备双跑逐字节/WorkerLoop depth 腿端到端
  - Tests/LightamerTests/DepthWorkerLegTests.swift              # 新建（APP，无资产可跑）：open 资产缺席无 culprit/family 三腿分派路由/run-before-open/崩溃注入链 respawn/depth 帧 envelope 往返
  - Tests/LightamerTests/ModelAssetCatalogTests.swift           # 修改（LIB）：depth profile 不变量 + inputShortEdge 对 + family 判别式穷举 + 五 profile shortEdge nil 零漂移负测
  - Tests/LightamerTests/ModelAssetStoreTests.swift             # 修改（LIB）：depth 形 manifest 下载晋升（URLProtocol mock 既有 harness）+ checksum mismatch typed + digest 缺席 fail-closed
  - Project.swift                                               # 修改：新测试文件/fixture 登记对应数组（显式清单无 glob）+ tuist generate 恒为该批最后一个动作（L041）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：新测试文件增行登记（E2 纪律，随各自任务 commit）
  - .work/gsd/phases/m4-3-depth/perf.md                         # 新建（T7）：ANE/GPU/CPU 三档延迟 + 端到端蒙版生成耗时（LIGHTAMER_PERF_PROBE 门控探针产出）
  - .work/gsd/phases/m4-3-depth/M4-3-01-SUMMARY.md              # 新建（T8）
  - .work/gsd/phases/m4-3-depth/M4-3-01-DECISIONS.md            # 新建（T8；T1 spike 事实先行落盘）
  - .work/gsd/phases/m4-3-depth/M4-3-01-ACCEPTANCE.md           # 新建（T8 编排注记——zcode PASS 后串行 omp 二次验收，本 plan 执行方不产内容只建骨架）
  - .work/GOAL-STATE.md                                         # 修改：续接点
  - .work/TODO.md                                               # 修改：M4-3 条目
  - .work/LESSONS.md                                            # 如踩坑
---

# Plan M4-3-01 — IOP-MASK-07 Depth 蒙版（DA V2 Small × M2AI-10 worker × Lumen 四段管线）

> **性质**：M4-3 单 plan（M 规模）。交付面五块：①资产链（官方 F16 件 Release 登记，
> 模型字节不入 git）②worker 第三推理腿（M2AI-10 底座，crash-safe 降档链复用）
> ③深度→近景蒙版四段 Core 纯函数管线（Lumen 生产参数直采）④App 编排与单入口 UI
> ⑤golden 三件套 + perf 探针。**蒙版消费面零新机制**：产物 = raster asset 经
> IOP-MASK-03 通道（16-bit PNG + StableHash + invert 位），组合/羽化/调整层挂载
> 全走既有 IOP-MASK-04/05 + M2-7 修订纪律（D-M4-3-CONTEXT-1「mask GENERATOR,
> not an iop slot」同构）。
>
> 规格正本 = `RESEARCH-NOTES.md`（Lumen file:line 锚 2026-10-09 亲核，本 plan 转写
> 前 re-verified：`selection.py:71-74` 四段管线 / `v11-models.json:3-6` sha256 锁 /
> `auto_masks.py:77-79` 0.03% 空守卫全部亲证）；裁决正本 = `M4-3-CONTEXT.md` 裁决
> 记录（2026-10-10：OQ-1..7 全按推荐 + 5 条低分叉直接裁决项同批生效）。
>
> **基线**：**3335/16/0**（M4-1-VALIDATION 2026-10-10 终验 `TOTAL|3335/16/0|1604s`；
> bundle 分账 IOP 562 / IOPParity 427 / Layers 394 / Library 619 / Sessions 279 /
> Export 350 / App 704，求和自洽亲核；M4-2 删除批 `5a19fae` 后 Layers 394/App 704
> 逐位回落 = 本 plan 起点亲证）。贴线纪律：本批全部新测试小 fixture，零 100MP
> 单测；worker/模型在场门控测试用注入路径，CI 无模型环境 XCTSkip（skip 计数不进
> 0-fail 门——验收机经 build 脚本装模型后真跑，DECISIONS 记安装命令）。

## 已定裁决（生效值，硬约束，不得重开）

CONTEXT 裁决记录（2026-10-10）：**OQ-1..7 全部按推荐（全 A）+ 5 条低分叉直接裁决项（D-1..D-5）同批生效**。

1. **OQ-1 = A**：模型主档 = Depth Anything V2 Small，Apple 官方 CoreML F16 转换件
   直采（`apple/coreml-depth-anything-v2-small`，49.8MB，ANE 25-33ms，abs-rel 0.0089
   官方数）；零转换成本（官方 mlpackage 即发布单元）；MiDaS v2 自转换 = 后手不入 v1。
2. **OQ-2 = A**：分发 = GitHub Release（`tier: .gitHubRelease`，沿 `ai-models-v1`
   tag 追加资产）；**模型不入仓**；不内置（bundled 翻转口 = 追加档无损演进，不预付）。
3. **OQ-3 = B**：推理走 **M2AI-10 worker 进程隔离**（`--ai-worker` 同 binary fork，
   open/run 协议 + CompatRecord + 三档降级链全复用）；**编辑器进程零自有模型推理**
   （Vision 蒙版 in-process 例外不适用于自有权重）。
4. **OQ-4 = A**：UI = **单「深度」蒙版入口** + 固定 Lumen 参数（0.48/0.22 窗 +
   10/95 分位 = v1 常量，零参数暴露）；远景 = `RasterMaskRef.invert` 既有位承载
   （生成近景，不预付「深度以外」第二按钮——零成本后补糖，DECISIONS 注记）。
5. **OQ-5 = A**：边缘对齐 = **AIMaskResample 双线性 + 既有蒙版羽化**；v1 零新
   Metal kernel，guided filter 挂 V2（实证驱动后补）。
6. **OQ-6 = A**：golden 三件套 = 转换精度门 **abs-rel ≤ 0.01**（官方 F16 自报
   0.0089 + 余量；max-abs 上限 T6 实测钉值入 DECISIONS）+ 确定性门 **同设备同
   computeUnits 双跑逐字节**（跨设备只验 abs-rel 不验字节）+ 蒙版语义 golden
   （合成深度靶三断言 + typed error 负测 + 参数扫描纯函数性）。
7. **OQ-7 = A**：`ModelAssetManifest.inputSize` 保持 Int（depth 记长边 518）+
   **additive optional `inputShortEdge: Int?`**（nil = 既有正方形语义，五 profile
   零漂移）；depth 腿消费 (518, 396) 二元组。

**低分叉直接裁决项（同批生效）**：

- **D-1**：Depth = 蒙版生成器，**不占 iop 槽位**——V50Order/Registry/pixelpipe 零触碰；
  产物走 IOP-MASK-03 raster 通道消费。
- **D-2**：失败腿严格语义——模型未安装（`modelNotReady` 同型，入口置灰）/ 推理失败
  （`inferenceFailed` 同型）/ 平坦深度无有效分层（**新 case `noDepthStructure`**，
  语义 = noSubject「无明确深度分层」提示）→ 全部 typed error、**永不 all-ones**；
  与 RasterMaskStore.load 三失败腿降级语义严格分离。
- **D-3**：四段管线 = **Core 级纯函数**（percentile 归一 → 近景窗 → smoothstep → α），
  Lumen 参数 = v1 默认常量；可单测 + golden + 后手参数化空间。
- **D-4**：输入**静态形状 518×396** + 预处理按 mlpackage feature 元数据接线
  （**T1 spike 亲核钉死，不凭文档转抄**）；flexible shapes 全程规避。
- **D-5**：转换脚本 = 构建期工具链（官方件直采 = 零转换，脚本只做下载→校验→打包）；
  运行时零新依赖（app 内推理恒 CoreML 原生 MLModel，**零新 SPM**）。

**架构红线（本 plan 全程 + checker 机检面）**：

- **模型字节不入 git**（走 Release + `~/Library/Caches/LightamerModels/depth/` 构建位；
  `.gitignore` 红线沿用——仓内零 `.mlpackage`/zip 字节）。
- **零新 SPM 依赖**；Python 只出现在 `Scripts/`（uv run，构建期）。
- **零 diff 红线面**：`LightamerCore/Sources/Sidecar/`（sidecar schema 零变更——
  AI 生成参数从不持久化，07 族继承定案）/ `Aces2Kernels.metal` / 六格式导出矩阵
  （ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ `V50Order` / `Registry` /
  `DrtRecord` / `HistoryStack` / `HistoryHash` / `LayerEditingState` /
  `MaskEdgeKernels.metal` / `NodeGraphCommand`——全部零触碰（T8 `git diff` 自证）。
- **AIWorkerProtocol wire 零破坏性改动**：depth 腿复用既有 `inPath`/`outPath`
  PATH 通道字段 + `AIWorkerPayload` 既有形态（enhanceTile 先例）；零新 op、零新
  envelope 字段、零帧版本移动。
- IOP/IOPParity 逐位基线零漂移（本批零渲染管线触碰，天然成立；T8 亲证）。
- 失败腿纪律：生成失败 typed error **永不 all-ones 蒙版**（RasterMaskStore.load
  降级语义严格分离，D-2）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 资产链与 manifest 面（T1，OQ-1/2/7 + D-5）

- **第六 profile** `depthAnythingV2SmallF16`：`profileID: "depth-anything-v2-small-f16"` /
  `modelID: "apple/coreml-depth-anything-v2-small"`（HF 转换件仓）/
  `revision:` HF commit SHA（T1 亲核钉值）+ 权重上游
  `depth-anything/Depth-Anything-V2-Small-hf` 记 hfFallback /
  `embeddingDim: nil` / `inputSize: 518` + `inputShortEdge: 396` /
  `textLanguages: []` / `licenseName: "Apache-2.0"` / `tier: .gitHubRelease` /
  `releaseTag: "ai-models-v1"` / `assetFileName: "depth-anything-v2-small-f16.mlpackage.zip"` /
  `hfFallback: (repo: "apple/coreml-depth-anything-v2-small", file: <F16 件名 T1 亲核>)`。
- **additive 字段**：`inputShortEdge: Int?`（OQ-7 裁定）；`==` 增一行比较；五既有
  profile 构造补 `nil`（编译期破面单文件 + 测试构造点，同批修——additive 先例 =
  InstalledLut.relativePath）。**零新存储字段做 family 判别**——派生计算属性
  `var family: ModelAssetFamily`（`.clip` = embeddingDim 非 nil / `.depth` =
  inputShortEdge 非 nil / `.enhancement` = 其余；穷举互斥单源，编译器背书），
  worker 分派与测试消费同一判别式（防第二真相源）。
- **digest 登记**：`ModelAssetDigests.generated.swift` REWRITABLE ENTRIES 尾块增
  `depthAnythingV2SmallF16` sentinel 行；`Scripts/ai-models/build-depth-release-asset.sh`
  （独立于 build_default_bundle.sh——资产来源是 HF 直采非转换）复用其内嵌 python
  重写正则模式（sentinel 名唯一匹配），产物 zip 落
  `~/Library/Caches/LightamerModels/depth/`。digest 发布（=nil→真值）与 Release
  资产上传同批生效；上传前 digest 也可先行入库（fail-closed 面只是「可下载」，
  404 → allSourcesFailed typed，无半态风险——顺序不敏感，T8 端到端走查兜底）。
- **zip 内随行**：`DepthAnythingV2SmallF16.mlpackage/` + `LICENSE`（Apache-2.0
  全文）+ `NOTICE`（署名 Depth Anything 团队 HKU/TikTok + Apple ML research/
  huggingface 转换件；RESEARCH §4 许可审计三行全 Apache-2.0 零灰色）；zip 外
  `MANIFEST.sha256`（资产内容清单，M3-3 五件套先例形态）随 NOTICE 同打包。
- **许可审计入 AC**：manifest `licenseName == "Apache-2.0"` 断言 + zip 内容清单
  断言（LICENSE/NOTICE 在场）+ NOTICE 署名行断言（读 zip 目录清单）。

### KD-2 worker family 三腿分派（T3，OQ-3）

- `AIWorkerMain.open`：现行二分（`embeddingDim != nil` → CLIP 腿，else →
  enhancement 腿）改 **`switch manifest.family`** 三臂：`.clip` 臂逐字节保留现
  CLIP 腿体 / `.enhancement` 臂逐字节保留 `openEnhancementLeg` / `.depth` 臂新
  `openDepthLeg`（DepthSession 构造：`resolvePackage` → `loadCompiled` 同款编译
  缓存模式 → 挂 `depthSessions[key]`）。资产缺席 = 无 culprit 错误帧（profile 级，
  KD-2 既有语义）；units 级加载失败 = 带 culprit（降档记账输入）。
- `run` 分派同步三腿（`forwardDepthRun`）；crash 注入 hook（`LIGHTAMER_TEST_AI_WORKER_CRASH
  =<profileID>`）对 depth profile 免费生效（hook 在资产解析前，零改动）。
- `AIWorkerClient.runDepth`：enhanceTile 逐字段同构（`withFallbackChain` 包裹——
  ANE native crash → CompatRecord 记账 + respawn + 下一档重试；run 级错误帧 =
  worker 健康，typed requestFailed 不耗链）；open 响应不携带 depth facts（静态
  形状 manifest 单源，editor 侧已知，零 AIWorkerResult 改动）。
- **协议零破坏自证**：`AIWorkerProtocol.swift` 零 diff；depth 帧 = 既有
  `inPath/outPath` 字段（T3 envelope round-trip 测试钉）。

### KD-3 DepthSession 前向工艺（T3，D-4 spike 驱动）

- **输入腿**：inPath = editor 写的 sRGB JPEG（q 0.92，长边 1040 帽——2× 模型输入，
  IPC 小且信息余量足）。worker 侧：`CGImageSource` 解码 → CGContext 缩放拉伸到
  **518×396**（静态形状，纵横比失真换 ANE 单组 specialization——Lumen 256² 拉伸
  同型，蒙版用途无可见伪影；`CGInterpolationQuality.medium` 确定性）→ 归一化
  **按 T1 spike 钉死的 feature 元数据接线**：
  - 臂 a（模型收 image input，预处理已烘焙）：直接喂 CVPixelBuffer；
  - 臂 b（模型收 multiArray float）：ImageNet mean/std
    `[.485,.456,.406]/[.229,.224,.225]` CPU 侧归一（Lumen `selection.py:65` 同参）。
  两臂分叉只在 DepthSession 内，T1 spike 结论落 DECISIONS 后 T3 按钉值实现，
  另一臂代码不落。
- **输出腿**：relative inverse depth F32 平面 → outPath = **8 字节头
  （UInt32 LE width + UInt32 LE height）+ row-major F32 LE bytes**（显式无歧义，
  零 ImageIO 32F 灰度 TIFF 写入变数；L048 比较纪律天然兼容——读回即 F32 原值）。
- **HEADLESS 纪律**：AIWorkerDepth.swift imports Foundation/CoreML/ImageIO only
  （AIWorkerEnhancement.swift 同款头注）；编译缓存走 worker 自己的
  `compiled-models-worker/<profile>` 树（既有函数复用）。

### KD-4 四段管线纯函数核（T2，D-3）

- `DepthMaskPipeline.nearMask(depth: AIMaskPlane, ...) throws -> AIMaskPlane`：
  ①**percentile 归一**——`low = percentile(depth, 10)`、`high = percentile(depth, 95)`
  （**线性插值语义** = numpy 默认 'linear'：rank = q/100·(n−1)，排序副本 + 显式
  插值公式，测试对 numpy 预计算参考值硬编码锚定）→
  `relative = clamp((d−low)/max(high−low, 1e-6), 0, 1)`（Lumen :72 同式含 1e-6 地板）；
  ②**近景窗** `clamp((relative−0.48)/0.22, 0, 1)`（:73 同参——≥0.48 起算前景，
  ≥0.70 全前景）；③**smoothstep** `p·p·(3−2p)`（:74 同式）；④α 平面输出。
- **有效性守卫（先于输出，D-2）**：(a) 退化域——`high − low ≤ max(1e-6, 1e-4 ·
  max(|low|, |high|))` → throw `.noDepthStructure("degenerate depth range")`；
  (b) 近空覆盖——smoothstep 后 `mean(α > 0.5) < 3e-4` → throw
  `.noDepthStructure("near mask covers < 0.03%")`（Lumen `auto_masks.py:77`
  0.0003 同值）。两触发一门一 case（消息区分），**不落蒙版**。
- 纯函数性：无状态、无时钟、无随机；同输入 byteIdentity 恒等（AIMaskPlane
  既有 FNV 面复用）。参数作带名常量（`percentileLow/High`、`windowStart`、
  `windowSpan`、`coverageFloor`）= v1 默认起点（OQ-4 固定；后手参数化零返工）。

### KD-5 App 编排与消费接线（T4，零消费面新机制）

- `DepthMaskService`（@MainActor @Observable，App AI 目录）：生成流程 =
  `AIMaskEditing.decodeFrameInput`（pre-edit 语义锚，07 族同款）→ preview JPEG
  写 `FileManager.default.temporaryDirectory`（EnhanceDialogModel :215 先例）→
  `client.runDepth` → float 读回（头校验 w==518/h==396，失配 = typed invalidInput）
  → `DepthMaskPipeline.nearMask` → `AIMaskEditing.commitRasterMask(plane: α,
  source: .depth, label: history_depth_mask, activateTool: .brush,
  decodeWidth/Height)`（**既有唯一 commit 缝**：上采样→bake→`MaskSpec.raster`
  → 恰一个 stackSnapshot item + 画笔落地形态，零新机制）。**expectedRevision
  不传**（nil = 与 Subject 首次生成同款——新生成语图，非 refine 重烤）。
- **切图竞态守卫**：入发起时捕获 `editorState.loadedImageURL`，commit 前比对，
  失配 = 丢弃结果（typed invalidInput，Lumen document token 比对同型
  `auto_masks.py:56,75`）。
- **DepthPackageResolver**（DepthMaskService 内嵌）：`ensurePackage(profileID:)`
  ——installed root（`ModelLocator` 注入缝）下 zip 在场且 `.mlpackage` 目录缺席
  → `/usr/bin/ditto -x -k` 解包（Lensfun `:82` Process 先例；幂等：目录在场即
  跳过；解包失败 typed `extractionFailed`）。**勘误登记（DECISIONS）**：现行
  `EnhancementSession.resolvePackage` 找解压目录而 `ModelAssetStore.download`
  只晋升 zip——release 档「zip→可用包」一跳在全链缺位（latent gap，全 digest
  nil 从未走通故未发作）；本 plan 在 App 侧 resolver 补齐 depth 腿，enhancement
  族顺延待其 digest 发布批处置（observation 登记，不在本 plan 扩面）。
- **DepthEntryGate 纯函数**（AIMaskEntryGate.layerBEntry 同构四态）：`ready` =
  status installed + 包目录在场 / `needsDownload` = notInstalled + digest 已发布
  （digestUnpublished = needsDownload + 引导文案「待发布」注记）/ `downloading(f)` /
  `failed(reason)`（corrupt → failed「重新下载可自愈」——store.download 重下
  self-heal 既有面）。下载触发 = `store.download`（进度回调 → gate 态），完成后
  resolver 解包 → **自动衔接一次生成**（单 tap 全程）。
- `AIMaskSource.depth = "ai-depth"`：fileName 前缀/source(ofFileName:) additive
  （LayerEditingState :278 的 segment 判别不受扰——depth 文件名前缀不同）。

### KD-6 UI 单入口（T5，OQ-4）

- MaskToolbarView 点选入口（layer B switch）之后加 Depth 组：**单按钮** ready 态
  （SF Symbol `square.stack.3d.up.forward` 系深度隐喻，或 `camera.metering.`
  系——执行期取最贴切一枚，accessibility `ai.mask.depth`）；四态映射 KD-5 gate
  （downloading = 迷你 ProgressView + 百分比；failed = 橙色重试，layer B 同款）。
- **零参数面**：0.48/0.22/10/95 无任何 UI 暴露；蒙版修整走既有画笔（M2-7 心智）。
- xcstrings 七键尾块纯插入（front-matter 清单）；V14 禁令：零
  `String.LocalizationValue("prefix_\(x)")` 插值形态；zh-audit `--check` 预期
  +7 全绿。

### KD-7 golden 三件套与 fixture（T6，OQ-6）

- **蒙版语义门（无模型依赖，T2 随管线落）**：合成深度靶（近景矩形 0.9 + 远景
  0.2 两级平面）→ 三断言（前景命中 α≈1 / 背景零误伤 α≈0 / 窗过渡带位置 =
  relative∈[0.48,0.70] 带）；斜坡单调；平坦与近空两负测 typed；参数扫描
  （windowStart 平移 → 过渡带平移，纯函数性）。比较域纪律 L048（F32 原值 +
  `Double(Float(x))` 升维，带容差按 smoothstep 斜率上限推导，测试头注写明）。
- **转换精度门（模型在场门控）**：`Tests/Fixtures/DepthPrecision/` 固定输入集
  （≥4 张：真实 RAW 降采样样张 2 + 合成渐变/边缘靶 2）+ `ref-f32.bin`（F32
  参考件预计算输出，`gen-depth-golden.py` uv run + coremltools predict 产出，
  生成器可再生）；测试 = F16 件（env `LIGHTAMER_TEST_DEPTH_PACKAGE` 注入路径或
  走查机已安装位）跑同输入 vs 参考输出 → **abs-rel ≤ 0.01** + max-abs ≤ T6
  实测钉值（DECISIONS 记分布与钉值依据；禁调门凑数）。XCTSkipUnless 门控——
  CI 无模型 skip，验收机装后真跑。
- **确定性门**：同 F16 包同 computeUnits 双跑（DepthSession 直驱）→ outPath
  字节逐位一致；跨设备零承诺（AIMaskService gpuPinned 注记口径延续）。
- **WorkerLoop 端到端（模型在场门控）**：真帧 open+run 一轮（合成小图 inPath →
  outPath F32 头校验 + finite 全查——Lumen `np.isfinite` 守卫同型 :67）。

### KD-8 perf 探针（T7）

- `LIGHTAMER_PERF_PROBE=1` env 门控 + XCTSkipUnless（M2-5 惯例）；探针读钟前
  queue fence（L014——无 fence 计时是假数）。量三档：`.all`/`.cpuAndGPU`/`.cpuOnly`
  各 N=5 前向中位数 + 端到端（preview 写盘→run→管线→bake）一次；落
  `phases/m4-3-depth/perf.md`（M2-11 体例）。预算参照：ANE 25-33ms（Apple 自报）；
  显著超带（>10×）先查是否落 CPU 再上报，不静默收。

## read_first

1. `.work/gsd/phases/m4-3-depth/M4-3-CONTEXT.md`（裁决记录 = 生效值正本）+
   `RESEARCH-NOTES.md` §1/§3/§5/§6（Lumen 锚与管线/golden 正本）
2. `LightamerCore/Sources/AI/AIWorkerProtocol.swift`（帧协议 + 8MB BYTE 界 + PATH
   通道语义——depth 用 PATH 通道）
3. `App/Sources/Lightamer/AI/AIWorkerMain.swift`（WorkerLoop open/run 二分现状 +
   crash hook + 编译缓存）+ `AIWorkerEnhancement.swift`（Session 范式 +
   `resolvePackage` 解压目录契约）
4. `App/Sources/Lightamer/AI/AIWorkerClient.swift`（withFallbackChain/单飞行/
   respawn；enhanceTile = runDepth 的逐字段模板）
5. `LightamerCore/Sources/AI/ModelAssetCatalog.swift` + `ModelAssetStore.swift` +
   `ModelLocator.swift`（manifest/additive 字段落点/下载晋升/安装根注入缝）
6. `LightamerCore/Sources/AI/AIMaskService.swift` + `AIMaskTypes.swift:131-152`
   （失败腿严格语义 + typed error 面）+ `AIMaskResample.swift`（双线性 + 对齐）
7. `App/Sources/Lightamer/State/AIMaskEditing.swift`（唯一 commit 缝 + EntryGate
   先例）+ `UI/Overlay/MaskToolbarView.swift:280-396`（AI Subject 入口形态）
8. `LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift`（16-bit PNG +
   StableHash + invert——烤盘目标通道零改动）
9. Lumen 参考锚（MIT 只读，零复制）：`lumen/selection.py:59-78` + `auto_masks.py:49-91`
   + `assets/models/v11-models.json:3-6`
10. `Tests/LightamerTests/AIWorkerClientTests.swift` + `ModelAssetStoreTests.swift`
    （真子进程/URLProtocol mock harness）+ `AIMaskEditPathsTests.swift`（coordinator
    直驱 harness）+ `AIMaskDeterminismTests.swift`（确定性门先例）
11. `Scripts/ai-models/build_default_bundle.sh`（digest sentinel 重写正则模式）+
    `Scripts/test-direct.sh`（跑法）+ `Session/LensfunDownloadService.swift:79-90`
    （/usr/bin/unzip Process 先例——resolver 用 ditto，形态同参）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits 全英文；只 add 相关文件；front-matter
  `files_modified` 为界）；新测试文件随各自任务 commit 登记进 BUNDLE-MAP（E2）+
  `Project.swift` 对应数组（L041：`tuist generate` 恒为该批最后一个动作）。
- **构建**：`caffeinate -dis` 包裹；单测标准命令 = `Scripts/test-direct.sh
  --bundle <域>`（全套 `--all` 需 orchestrator 批准，收口轮才申请）。
- **GPU/纹理读回 fence（L014）**：任何探针/测试读纹理或计时前先 queue fence。
- **比较域（L048）**：F32 原值 + `Double(Float(x))` 升维；禁已量化域直接比。
- **中文标注（待核/待定/待补）显式**；无源待核项入 DECISIONS 待供件清单
  （预期候选：HF 转换件 revision SHA = T1 网络亲核后回填）。
- **网络兜底**：HF 直采/Release 上传走 `px --up` 代理（AGENTS §6），任务完即
  `px --stop`。
- **模型字节红线自证**：T8 `git status`/`git ls-files` 机检仓内零模型字节
  （`.gitignore` AIModels 段既有 + 本批产物路径在仓外）。

## Tasks

### T1 资产管线 + manifest additive + spike（KD-1，含 D-4 spike）

- read_first 1/5/11 → 下载官方 F16 件（px --up 兜底）→ **spike：feature 元数据
  亲核**（`MLModel.modelDescription` input/output 类型、形状、归一化是否烘焙、
  输出语义范围）→ 结论落 `M4-3-01-DECISIONS.md` §spike（T3 的接线依据，KD-3
  两臂择一钉死）→ `ModelAssetCatalog.swift` additive（inputShortEdge + family
  派生 + 第六 profile）→ `build-depth-release-asset.sh`（下载→SHA-256→zip +
  LICENSE/NOTICE/MANIFEST.sha256→digest 重写）→ digest 条目真值入库 → Release
  上传留 T8 ops（本任务产物在 `~/Library/Caches/LightamerModels/depth/`）。
- 验收：五既有 profile digest/status 面**零漂移负测**（ModelAssetCatalogTests：
  shortEdge 全 nil、family 穷举、== 含新行）；depth profile 不变量断言
  （licenseName/tier/releaseTag/(518,396) 对）；digest fail-closed 面（若 digest
  先行入库则改测「值格式 + byteCount 与 zip 实测一致」）；`git ls-files` 机检
  零模型字节；zip 内容清单断言（LICENSE/NOTICE/MANIFEST.sha256 在场——脚本
  自检步 + 单测对 sentinel 值）。

### T2 四段管线纯函数 + typed 守卫（KD-4，D-2/D-3）

- read_first 1/6 → `DepthMaskPipeline.swift` + `AIMaskError.noDepthStructure`
  additive case → `DepthMaskPipelineTests.swift`（LAYERS）。
- 验收：percentile 对 numpy 参考值锚（≥5 点含偶数长/含重复值/含 q 落格间）；
  合成靶三断言；斜坡单调；窗带位置断言（0.48/0.70 拐点 ±半格）；两守卫负测
  typed + 不落蒙版；纯函数性（同输入 byteIdentity 恒等 + 参数扫描）；L048
  容差推导写测试头注。

### T3 worker depth 腿（KD-2/KD-3，OQ-3）

- read_first 2/3/4/10 → `AIWorkerDepth.swift`（按 T1 钉死臂实现）+
  `AIWorkerMain` family 三腿分派 + `AIWorkerClient.runDepth` →
  `DepthWorkerLegTests.swift`（APP，无资产可跑）。
- 验收：open 资产缺席 = 无 culprit 错误帧；family 三腿路由断言（depth profile
  不落 enhancement 腿——负测钉）；run-before-open typed；崩溃注入
  `@all` → CompatRecord 记账 + generation respawn + 降档重试链（既有 harness
  模式）；depth envelope round-trip（PATH 字段复用零新字段断言）；**协议零
  diff 自证**（`git diff -- AIWorkerProtocol.swift` 零命中）；HEADLESS import
  纪律（文件头注 + grep 门无 SwiftUI/AppKit）。

### T4 App 编排 + 包 resolver + 入口门（KD-5）

- read_first 5/6/7/8/11 → `DepthMaskService.swift`（gate/resolver/generate/
  下载触发）+ `AIMaskEditing.swift` additive `.depth` →
  `DepthMaskEditingTests.swift`（LAYERS）。
- 验收：gate 四态映射纯函数全断言（含 digestUnpublished→needsDownload、
  corrupt→failed 自愈文案）；resolver 幂等（目录在场跳过）+ 解包失败 typed +
  注入 root 测试（临时目录 zip fixture）；float 读回头校验负测（w/h 失配
  typed）；竞态守卫（切图后 commit 丢弃——coordinator 直驱 harness）；
  commit 一次 item + activateTool 落地（AIMaskEditPaths 同款断言）；
  `AIMaskSource.depth` 命名往返 + segment 判别不受扰负测。

### T5 蒙版工具栏 Depth 入口（KD-6，OQ-4）

- read_first 7 → MaskToolbarView Depth 组 + xcstrings 七键尾块纯插入。
- 验收：四态 UI 映射（ready 生成按钮/needsDownload 引导/downloading 进度/
  failed 重试）——视图逻辑经 DepthMaskService gate 态驱动（单测覆盖 gate 面，
  视图零直读 ProcessInfo/UserDefaults——KD-4 注入式惯例）；accessibility
  identifier `ai.mask.depth` 在册；**零参数面负测**（无新 slider/滑杆断言——
  toolbar 常量面扫描或代码评审注记）；zh-audit `--check` 预期 +7 全绿
  （尾块纯插入，diff = 键级 added 7/removed 0/modified 0）；`history_depth_mask`
  键经 commit label 消费路径在册。

### T6 golden 三件套（KD-7，OQ-6）

- read_first 10/11 → `gen-depth-golden.py`（uv run + coremltools predict）→
  `Tests/Fixtures/DepthPrecision/`（README 记来源/门值/再生命令）→
  `DepthGoldenTests.swift`（APP，env 门控 XCTSkipUnless）。
- 验收：精度门 abs-rel ≤ 0.01（固定输入集全张）+ max-abs 实测分布入 DECISIONS
  并钉上限；确定性门同 computeUnits 双跑逐字节；WorkerLoop 端到端一轮（finite
  全查 + 头校验）；**skip 纪律**：无模型环境零失败（skip 计数记录）；fixture
  生成器幂等重跑字节一致（ref-f32.bin 重生成 diff 零命中）。

### T7 perf 探针 + 登记收尾（KD-8）

- read_first 11 → 探针（env 门控，三档 + 端到端）→ `perf.md` 落账 →
  BUNDLE-MAP 全部新文件行核对补齐。
- 验收：三档中位数入 perf.md（对照 Apple 自报 ANE 25-33ms 带注记）；超带处置
  结论行；L041 `tuist generate` 尾闸亲证（最后一动作）；BUNDLE-MAP 行数 =
  新测试文件数对账。

### T8 收口 + 双重验收编排

- SUMMARY（任务序/实测带/bundle 分账/门值）+ DECISIONS（spike 事实/门值钉值/
  resolver 勘误注记/安装命令/许可审计三行）+ GOAL-STATE 续接点 + TODO 同批 +
  LESSONS 如踩坑；**红线自证清单**：`git diff <基线>..HEAD --` 零命中集
  （Sidecar/Aces2Kernels.metal/六格式矩阵/V50Order/Registry/DrtRecord/
  HistoryStack/HistoryHash/LayerEditingState/MaskEdgeKernels.metal/
  AIWorkerProtocol.swift）+ 仓内零模型字节 + IOP/IOPParity 基线零漂移。
- **Release 上传 + 端到端走查（spike ②）**：`gh release upload ai-models-v1
  <zip>`（px --up 兜底；上传字节 = digest 锁定字节）→ 真下载走查一轮
  （ModelAssetStore 真网 → 解包 → 生成一轮；失败 = 阻塞上报不静默）。
- 验收：定向轮 `--bundle LAYERS/LIB/APP` 全绿（exit 0 + 零 MEMFAIL；模型在场
  门控法全真跑）；基线对账 3335 + 本批增量逐位。
- **双重验收（config `dual_acceptance = true`，m1）**：zcode subagent 独立验收
  PASS 后 → **串行** omp 二次验收（computer-use 走查；**严禁并发**——单实例
  硬约束）；两路结论（PASS/FAIL + 证据）落 `M4-3-01-ACCEPTANCE.md`；FAIL 回注
  修复批后重走。GUI 走查配方（Depth 入口四态 + 生成一轮 + 画笔修整衔接）先记
  `.work/gui-acceptance/m4-3/MANIFEST.md` 草案（Manual-Only 行——三电路激活
  环境级全惰先例，M3-4 在案）。

## 验收标准（AC 总表）

1. **OQ-1 生效值**：模型 = DA V2 Small Apple 官方 F16 件（profile modelID/revision
   锁定 + build 脚本来源 URL 锁定）；转换精度门 abs-rel ≤ 0.01 绿 + max-abs 钉值
   入 DECISIONS。【T1/T6】
2. **OQ-2 生效值**：`tier .gitHubRelease` + `releaseTag ai-models-v1` + digest
   SHA-256 锁定 + fail-closed 既有面保持；**仓内零模型字节机检** + Release 资产
   真下载端到端走查一轮。【T1/T8】
3. **OQ-3 生效值**：推理全走 `--ai-worker`（DepthSession worker 腿 + client
   runDepth 降档链）；崩溃注入 → CompatRecord + respawn + 降档重试断言；编辑器
   进程零自有模型推理面（grep 门：`MLModel` 构造点仅在 worker session 文件）；
   `AIWorkerProtocol.swift` 零 diff。【T3】
4. **OQ-4 生效值**：单「深度」入口 + 0.48/0.22 窗与 10/95 分位 = 带名常量零 UI
   暴露；远景 = invert 位承载（本批零第二按钮）；合成靶窗带位置断言钉死默认
   参数行为。【T2/T5】
5. **OQ-5 生效值**：零新 Metal kernel（全批零 `.metal` 新文件/零 diff 既有
   kernel 面）；上采样走 AIMaskResample 既有通道 + 羽化走 RasterMaskStore.bake
   既有 featherRadius。【全批】
6. **OQ-6 生效值**：golden 三件套在册——精度门（≤0.01）+ 确定性门（同设备双跑
   逐字节）+ 蒙版语义门（合成靶三断言 + 两 typed 负测 + 参数扫描）；模型缺席
   环境 skip 零失败。【T2/T6】
7. **OQ-7 生效值**：`inputShortEdge: Int?` additive（五 profile nil 零漂移负测 +
   depth (518,396) 消费断言 + `==` 新行）；family 派生判别式穷举单源。【T1】
8. **D-1**：V50Order/Registry/pixelpipe/DrtRecord 零 diff（蒙版生成器不占 iop
   槽位）。【T8 红证】
9. **D-2**：失败腿三门 typed（modelNotReady/inferenceFailed/noDepthStructure）
   + 永不 all-ones（负测：守卫触发即 throw，产物零落盘）。【T2/T4】
10. **D-3**：四段管线 Core 级纯函数（LAYERS bundle 单测直驱 + byteIdentity
    确定性 + Lumen 同参常量锚注 `selection.py:71-74`）。【T2】
11. **D-4**：输入静态形状 518×396（DepthSession 形状断言 + spike 事实 DECISIONS
    在册）；flexible shapes 零出现。【T1/T3】
12. **D-5 + 许可审计**：零新 SPM（Project.swift 依赖面零 diff）；许可全链
    Apache-2.0（manifest licenseName 断言 + zip LICENSE/NOTICE 清单断言 +
    DECISIONS 审计三行）。【T1/T8】
13. **基线**：LAYERS/LIB/APP 定向轮全绿零 MEMFAIL；全套对账 3335 + 本批增量
    逐位；zh-audit +7 键纯插入。【T8】

## 风险与边界

- **feature 元数据与文档不符**（D-4 核心风险）：官方件若 image input 与 multiArray
  臂选择错误 → 前向静默劣化。兜底 = T1 spike 先行钉死 + T6 精度门对 F32 参考件
  兜住（错归一化必爆 abs-rel）。
- **HF 直采/Release 上传网络失败**：px --up 兜底；仍失败 = digest 留 nil
  （fail-closed 天然安全）+ 阻塞上报，不伪造 digest。
- **worker 前向延迟异常**（>10× 自报带）：先查 computeUnits 落格（perf 探针三档
  分账）；ANE 不可用 = 降档链既有面自动接，不阻塞交付。
- **IOP 贴线 bundle**：本批零触碰其面；若 `--all` 轮 MEMFAIL 按 AGENTS 口径查
  重测漂移。
- **guided filter 缺位**（OQ-5 裁定边界）：深边界糊可见度 = T8 GUI 走查观察项，
  证据驱动挂 V2（Follow Edges 熔断先例的实证纪律）。
- **enhancement 族 latent zip 缺口**：本批只补 depth 腿 resolver；enhancement
  顺延（DECISIONS observation 登记），不扩面。

## 提交约定

- T1 `feat(ai): depth anything v2 small asset chain with additive manifest fields`
- T2 `feat(core): depth to near-mask pipeline with typed flat-depth face`
- T3 `feat(app): depth inference leg on the ai worker process`
- T4 `feat(app): depth mask service with package resolver and entry gate`
- T5 `feat(app): depth mask toolbar entry with download states`
- T6 `test(app): depth golden precision and determinism gates`
- T7 `chore(perf): depth inference probe across compute units`
- T8 `docs(m4-3): close depth mask batch with decisions and ledger`
- 全英文 Conventional Commits；不 push。
