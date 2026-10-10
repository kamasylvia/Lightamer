# M4-3: IOP-MASK-07 Depth 蒙版 — Context（起草稿）

> 起草：discuss/research subagent（2026-10-09）。**C 档第 1 停**：本文为草案，
> Open Questions 交用户裁决后才进 plan。Lumen RAW（MIT）只读参考，代码不复制入库。
> 源码实测 / 变体对比 / 许可审计细节见同目录 `RESEARCH-NOTES.md`（下称 NOTES）。

## Phase Boundary

**做**（ROADMAP M4-3 行 + REQUIREMENTS :367 IOP-MASK-07）：

1. **Depth 蒙版生成器**——MiDaS 级单目深度模型（research 推荐兑现 = Depth Anything
   V2 Small，Apple 官方 CoreML F16 转换件直采，NOTES §2/§3）进蒙版面；
   relative inverse depth → 近景/远景蒙版（NOTES §5.1 四段纯函数管线）。
2. **蒙版集成**——产物走 IOP-MASK-03 raster 通道（16-bit PNG + StableHash +
   invert 位），组合/羽化/应用于任意调整层 = 既有 IOP-MASK-04/05 面；近/远 =
   `RasterMaskRef.invert` 糖（AI Subject「主体以外」入口同款先例）。
3. **资产分发链**——ModelAssetCatalog additive 新 profile + ModelAssetStore
   下载校验既有链（SHA-256 锁定，D-M2-10-CONTEXT-7 纪律）；模型**不入仓**，
   走本仓 GitHub Release 分发（ROADMAP 字面；OQ-2 留内置翻转口）。
4. **golden 三件套**——转换精度门（abs-rel ≤ 0.01，NOTES §6）+ 确定性门 +
   蒙版语义 golden（合成深度靶 + typed error 负测）。

**不做**（本 phase 边界外）：

- 蒙版消费面新机制（组合五式/羽化/调整层挂载全部既有，零 iop 槽位占用——
  AI mask「mask GENERATOR, not an iop slot」同构裁决，D-1）。
- guided filter 边缘对齐 kernel（v1 用双线性上采样 + 既有羽化；guided filter
  挂 V2，OQ-5）。
- IOP-MASK-06 Follow Edges 任何复活动作（parked，M4-2 终裁；重启入口 =
  REQUIREMENTS parked 行，与本 phase 无涉）。
- 绝对深度/距离测量（relative depth only——Lumen `MODEL.md:54` 同款边界注记）。
- 深度其他消费面（景深虚化渲染、重对焦、深度导出）——不在 IOP-MASK-07 字面。

**既有裁决延续（不重开）**：

- M2AI-10 worker 底座（同 binary 子进程 `--ai-worker` + AIWorkerOp open/run +
  ai-compat.json 崩溃记录）——V2-PROPOSAL :91 明示「直接底座」；落位见 OQ-3。
- 模型资产纪律五件套（编译期 manifest + SHA-256 + Release 版本锁死 URL +
  hf fallback + 许可字段；D-M2-10-CONTEXT-7）。
- macOS 27 地板（CoreML/ANE API 无版本分叉负担）；依赖最小化（推理走 CoreML
  原生 MLModel，零新 SPM 依赖；转换脚本 = 构建期 Python 工具链）。
- M2-7 蒙版修订 revision/乐观并发纪律（ROADMAP M4-3 边界行）。

## 资产盘点（Phase 承接面）

| 资产 | 位置 | 复用方式 |
|---|---|---|
| AI 蒙版双腿服务面（layer A/B、typed error、L014 fence、device pin） | `LightamerCore/Sources/AI/AIMaskService.swift` + `AIMaskTypes.swift:131-152` | Depth 腿同构第三入口：typed error additive 一 case；失败腿严格语义照抄 |
| 蒙版上采样对齐通道 | `LightamerCore/Sources/AI/AIMaskResample.swift` | 518×396 → 源分辨率上采样直接复用 |
| raster 蒙版存储 | `LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift`（16-bit PNG + StableHash + invert） | Depth 蒙版烤盘目标通道（零改动） |
| 模型资产目录 + 下载校验 | `LightamerCore/Sources/AI/ModelAssetCatalog.swift`（五 profile 目录 additive）+ `ModelAssetStore.swift` + `ModelLocator.swift:94-106` | 新 profile `depth-anything-v2-small-f16`；Release tier 全链现成 |
| 推理 worker 底座 | `LightamerCore/Sources/AI/AIWorkerProtocol.swift:44-65`（computeUnits 三档 / open/run）+ `CompatRecord.swift` | 落位随 OQ-3；协议零改动 |
| Lumen 深度→蒙版语义参数 | `lumen/selection.py:69-74`（percentile 10/95 + 窗 0.48/0.22 + smoothstep） | 四段纯函数管线默认常量起点（NOTES §1.3/§5.1） |
| Apple 官方 CoreML 转换件 | `apple/coreml-depth-anything-v2-small`（F16 49.8MB，apache-2.0，ANE 25-33ms 实测） | 直采主档候选（OQ-1）；Release 资产来源 |

## 直接裁决项（低分叉 / 既有裁决延续；随 OQ 一并过目，可逐条推翻）

### D-M4-3-CONTEXT-1: Depth 蒙版 = 蒙版生成器，不占 iop 槽位

- **裁决**：与 AI mask 同构——Depth 推理是一次性后台生成任务，产物 = raster asset
  经 IOP-MASK-03 通道消费；V50Order/pixelpipe 零触碰。蒙版编辑/组合/羽化/应用
  全走既有面（IOP-MASK-04/05 + M2-7 修订纪律）。
- **理由**：AIMaskService 头注既有裁决（「AI-01 does NOT occupy an iop slot」）；
  深度蒙版与 Subject 蒙版在数据面完全同型（都是生成器→raster→组合）。

### D-M4-3-CONTEXT-2: 失败腿严格语义——typed error，永不 all-ones

- **裁决**：模型未安装（入口置灰，`modelNotReady` 同型）/ 推理失败
  （`inferenceFailed` 同型）/ 平坦深度无有效分层（新 case，语义 =
  AIMaskError.noSubject「无明确深度分层」提示）→ 全部 typed error、不落蒙版；
  与 RasterMaskStore.load 的三失败腿降级语义严格分离（既有红线照抄）。
- **理由**：AIMaskTypes.swift:131-152 错误面既有纪律；Lumen 空结果守卫同型
  （`auto_masks.py:77-79`，0.03% 门）。

### D-M4-3-CONTEXT-3: 深度→蒙版四段管线 = Core 级纯函数，Lumen 参数为默认起点

- **裁决**：percentile [10,95] 归一化 → 近景窗 (r−0.48)/0.22 → smoothstep
  → α 平面，全纯函数落 Core（可单测 + golden）；参数作 v1 默认常量
  （NOTES §5.1）；背景 = `RasterMaskRef.invert`（零新代码）。
- **理由**：Lumen 生产参数直接复用（`selection.py:71-74`）；纯函数性 =
  golden 友好 + OQ-4 可调档的后手空间。

### D-M4-3-CONTEXT-4: 输入静态形状 + ImageNet 归一化对齐模型要求

- **裁决**：前向固定 518×396（Apple 官方件形状）；预处理按 mlpackage feature
  描述接线（plan spike 亲核，不凭文档转抄）；flexible shapes 全程规避
  （M2-10 RESEARCH §1.5 ANE 纪律 + Lumen DRUNet/NAFNet 动态形状教训双证）。
- **理由**：静态形状 = ANE 单组 specialization 最优；蒙版用途下纵横比拉伸
  无可见伪影（Lumen 256² 拉伸同型，NOTES §3.1）。

### D-M4-3-CONTEXT-5: 转换脚本 = 构建期工具链，运行时零新依赖

- **裁决**：官方件直采时**零转换**（下载→SHA-256→Release 发布三步）；
  若 OQ-1 裁自转换，coremltools 转换脚本进 `Scripts/`（Python + uv，构建期），
  产物 .mlpackage 进 Release——app 内推理恒 CoreML 原生 MLModel，零新 SPM 依赖。
- **理由**：ROADMAP M4-3「运行时零新依赖」原文；M2-10 转换 spike 先例同型。

## Open Questions（用户裁决点；每条：问题 / 选项 / 推荐 / 理由）

### OQ-1: 模型主档选型——Apple 官方 DA V2 Small 直采 vs Lumen 同款 MiDaS v2 small

- **问题**：ROADMAP 字面「MiDaS ONNX→CoreML 转换」的兑现档位。
- **选项**：
  - **(A) Depth Anything V2 Small，Apple 官方 F16 转换件直采（49.8MB）**——
    2024 质量世代（DINOv2 骨干，62M 图训练）；ANE 实测 25-33ms（Apple 自报
    M1 Max/M3 Max）；许可全链 Apache-2.0；**零转换成本**（官方 mlpackage 即
    发布单元）；HF onnx-community 导出在册 = 自转换后手起点。
  - **(B) MiDaS v2.1 small 自转换（Lumen 同款，F16 ≈40MB）**——2020 质量档；
    ONNX 官方件 65MB → coremltools 自转换 + ANE 落格 spike（EfficientNet-Lite
    激活函数风险）；体积略小但质量代差明显。
  - **(C) DA V2 Base/Large 自转换**——97.5M/335M 参数（≈195MB/670MB F16），
    无官方 CoreML 件；蒙版场景质量收益边际，体积/转换成本全升。
- **推荐**：**(A)**。DA V2 是 MiDaS 直系后继（V1 即在 MiDaS 框架训练），
  REQUIREMENTS :367「MiDaS 级单目深度模型」语义内；Apple 官方背书 = ANE 兼容
  与转换质量双免检（abs-rel 0.0089 官方数，NOTES §2）。
- **理由**：转换工艺从「风险项」变「零工时」；质量、许可、性能三轴全面占优；
  (B) 仅当用户要求与 Lumen 严格同款时取。

### OQ-2: 分发 tier——GitHub Release（ROADMAP 字面）vs 内置 49.8MB

- **问题**：ROADMAP M4-3 已写「模型资产走 GitHub Release 分发（不入仓）」；
  F16 件仅 49.8MB（小于内置先例 chinese-clip 190MB），是否维持字面。
- **选项**：
  - **(A) Release 下载（维持 ROADMAP 字面）**——`tier: .gitHubRelease`，
    沿 `ai-models-v1` tag 追加资产；首次使用引导下载（ModelAssetStore 既有
    下载态/置灰面）。
  - **(B) 改内置**——`Resources/AIModels/depth-anything-v2-small-f16/` bundled
    folder reference，开箱即用；DMG/zip +49.8MB。
  - **(C) v1 Release + v1.x 追加内置档**——先走 (A)，真实使用数据出来后再定
    是否内置（bundled 档追加 = 无损演进）。
- **推荐**：**(A)**——ROADMAP 字面是 M4-0 charter 批产物，无新证据不推翻；
    49.8MB 贴内置边缘但「零下载」当初只为默认必用模型设（CLIP 检索是图库
    主路径，Depth 是蒙版可选工具），按需下载体验可接受。
- **理由**：Release 通道/下载/校验链全部现成（M2-10 交付），(A) 实现面最小；
    (C) 留演进口不预付体积。

### OQ-3: 推理落位——M2AI-10 worker 进程隔离 vs in-process async

- **问题**：V2-PROPOSAL :91 写「复用 M2AI-10 worker 隔离」；但 Vision layer A/B
  蒙版现状是 in-process async static（OS 框架推理）。Depth 腿（自有 CoreML
  模型）落哪？
- **选项**：
  - **(A) in-process async（与 Vision 蒙版同待遇）**——`MLModel` 原生推理 +
    App 层 Task；CoreML/ANE native crash 风险由 Apple 官方件质量背书压低。
  - **(B) 走 M2AI-10 worker（V2-PROPOSAL 字面）**——`AIWorkerOp` open/run
    现成；ANE native crash 编辑器不死 + CompatRecord 记组合 + 降档重试。
  - **(C) v1 in-process + 崩溃遥测触发再隔离**——先 A，若 ai-compat 记录
    机制出现真实崩溃案例再迁 B（协议已就绪，迁移 = 推理侧改调用方）。
- **推荐**：**(B)**——字面是 charter 采纳时的既定表述；worker 底座零改动
    （open/run 协议通用，Enhance 同款），崩溃隔离对本项无额外成本；
    且 Depth 与 Enhance 同为「自有 CoreML 权重推理」，同底座心智一致
    （Vision 蒙版例外的原因是 OS 框架包办，不适用于自有模型）。
- **理由**：M2AI-10 立项本意 = 「推理崩溃编辑器不死」（自有模型推理通用，
    不限超分）；(A) 省的只是单次 IPC，(B) 的 crash-safe 是已付费资产。

### OQ-4: 蒙版语义 UI 面——入口形态与近景窗参数档位

- **问题**：Depth 蒙版的用户入口与 D-M4-3-CONTEXT-3 四段管线参数的暴露度。
- **选项**：
  - **(A) 单一「深度」蒙版入口 + 固定默认参数**（推荐）——蒙版工具栏加
    Depth 工具（AI Subject 同款入口形态），生成「近景」蒙版；远/背景 =
    「反转」既有位；参数 0.48/0.22 窗 + 10/95 分位 = v1 常量。
  - **(B) (A) + 阈值可调**——生成后暴露「近/远分界」滑杆（重跑 smoothstep
    段，纯 CPU 纯函数，无二次推理），存蒙版参数。
  - **(C) Lumen 式双按钮（「近景」「远景」两入口）**——UI 噪声，invert 糖
    已覆盖，不取。
- **推荐**：**(A)**——字面最小面；M2-7「自动蒙版可用画笔修整」心智下，
    用户修整比二次参数化更贴合既有工作流；(B) 的滑杆是纯函数重放、后补
    零返工，等真实使用反馈再加。
- **理由**：Lumen 也是单按钮「近景」+ 画笔修整（`auto_masks.py:20-22,34-36`），
    无参数暴露先例；蒙版语义 golden（§6）钉死默认参数行为。

### OQ-5: 边缘对齐裁度——v1 双线性 + 既有羽化 vs guided filter kernel

- **问题**：Lumen 用 guided filter 把粗深度边界对齐全分辨率亮度
  （NOTES §1.4）；我方 v1 是否跟。
- **选项**：
  - **(A) v1 不做 guided filter**——AIMaskResample 双线性上采样 + 既有蒙版
    羽化收尾；深度是低频信号 + 518 级输入（比 Lumen 256² 细一倍），
    边界糊可见度低；零新 kernel。
  - **(B) v1 上 Metal guided filter**——新 .metal 文件对 + golden；蒙版族
    首个对齐 kernel，plan 面显著加重。
  - **(C) (A) + 走查样张若边界糊可见 → v1 内补**——留条件升级口。
- **推荐**：**(A)**——v1 交付口径干净；guided filter 挂 V2 注记（真样张
    走查证据驱动，同 Follow Edges 熔断先例的实证纪律）。
- **理由**：OQ-4 (A) 的画笔修整工作流天然覆盖边界精修；(B) 的收益须
    先有「糊可见」证据；(C) 把裁决权留给 gui-acceptance 走查，不预付。

### OQ-6: golden 门取值与确定性策略签核

- **问题**：NOTES §6 三件套的门值需要签核（精度门 abs-rel ≤ 0.01 是否过宽/过严）。
- **选项**：
  - **(A) 三件套照 NOTES §6**：转换精度门 abs-rel ≤ 0.01（Apple F16 自报
    0.0089 + 余量）+ max-abs 上限 plan 钉值；确定性门 = 同 computeUnits
    双跑逐字节（gpuPinned 先例）；蒙版语义 golden = 合成靶三断言 + 负测。
  - **(B) 精度门收紧 0.009**——贴官方自报值，余量薄，CI 抖动风险。
  - **(C) 精度门放宽 0.02**——蒙版用途冗余大，弱化回归灵敏度。
- **推荐**：**(A)**；确定性门作为「跨设备不验字节、同设备必须逐字节」的
    既有口径（AIMaskService gpuPinned 注记）原样延续。
- **理由**：0.01 对蒙版用途（阈值化后分段常数）有约一个量级冗余，
    对真回归（F16 精度劣化/预处理错线）仍高灵敏；Lumen 先例 2.3e-3 是
    未归一化域数字，域不同不直接可比（NOTES §6 注记）。

### OQ-7: `inputSize` 清单语义放宽——非正方形输入的 typed 承载

- **问题**：`ModelAssetManifest.inputSize` 语义 = 「canonical square edge」
  （ModelAssetCatalog.swift:34 注记）；DA V2 件是 518×396 非正方形。
- **选项**：
  - **(A) additive 放宽**：`inputSize` 保持 Int（记长边 518）+ 新 optional
    `inputShortEdge: Int?`（nil = 既有正方形语义，五 profile 零漂移）；
    depth 腿消费 (518, 396) 二元组。
  - **(B) `inputSize: (Int, Int)?` 破坏性改型**——五 profile 调用点全动，
    违 additive 纪律。
  - **(C) depth profile 不进 ModelAssetCatalog，独立常量**——开第二真相源，
    违 D-M2-10-CONTEXT-7「single constant source」。
- **推荐**：**(A)**——additive optional（synthesized decode 宽容 + 既有
    InstalledLut.relativePath additive 先例同型）；typed 且零漂移。
- **理由**：清单是编译期常量面，字段演进 = additive optional 唯一正解；
    (C) 的第二真相源是 M2-10 明令禁止形态。

## 裁决后影响面速览（给 plan 阶段的输入）

- **Core**：`LightamerCore/Sources/AI/` additive——`DepthMaskService.swift`
  （生成器，AIMaskService 孪生形态）+ 深度→蒙版四段纯函数（含 golden 目标）
  + `AIMaskError` additive case；`ModelAssetCatalog.swift` additive profile
  （OQ-7 字段放宽）。
- **App**：蒙版工具栏 Depth 入口（AI Subject 同款置灰/下载态门）+ 生成
  Task 接线（OQ-3 落位）+ 无深度分层 toast。
- **资产**：Release tag 追加 `depth-anything-v2-small-f16.mlpackage.zip`
  （SHA-256 进 manifest；zip 内随行 LICENSE/NOTICE，五件套先例）。
- **测试**：域归置按 BUNDLE-MAP（AI/蒙版族现有 target）；golden fixture =
  合成深度靶 + 真实 RAW 降采样样张（转换精度门）。
- **plan 期 spike 清单**：①F16 件 feature 元数据亲核（预处理归一化接线，
  D-4）；②Release 资产上传 + ModelAssetStore 下载端到端走查；③OQ-3 落位
  定稿后推理延迟实测（ANE/GPU/CPU 三档入 perf 记录）。
- **依赖登记**：零新 SPM 依赖；构建期 Python 工具链仅 OQ-1 裁自转换时需要。

## 裁决记录（用户回批）

- （待填：OQ-1..7 与 D-1..5 裁决后在此登记，同 M2-10-CONTEXT 惯例。）

## 裁决记录（用户回批 2026-10-10）

**OQ-1..7 全部按推荐采纳（全 A）**：①DA V2 Small Apple 官方 CoreML F16 直采 ②GitHub Release 分发（不内置）③M2AI-10 worker 推理 ④单「深度」入口 + Lumen 固定参数（0.48/0.22 窗 + 10/95 分位）⑤v1 双线性 + 既有羽化（guided filter 挂 V2）⑥golden 三件套（abs-rel ≤0.01 + 逐字节确定性 + 合成靶语义）⑦additive optional `inputShortEdge`。另有 5 条低分叉直接裁决项同批按推荐生效。
