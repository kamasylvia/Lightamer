---
phase: m2-9
plan: "M2-9-03"
title: "命名/元数据/ICC 消费接线（wave 2b）——文件名模板求值进 renderer（逐 job 上下文 + sequence）+ 冲突三档/子文件夹 E2E + EXIF Software 写入（Lightamer <version>）+ 元数据剥离消费（location/serials/editing-history 三剥 + XMP packet gate）+ ICC embed/omit 编码消费 + 入队闸门（resolved output color，Alcedo RequireResolvedExportOutputColor 同构）"
wave: 2
depends_on: ["M2-9-01", "M2-9-02"]
autonomous: true
requirements: [M2EXP-02, M2EXP-03, M2EXP-04]
estimated_new_tests: 20
bundles: [Export]
files_modified:
  - LightamerCore/Sources/Export/ExportRenderer.swift             # 修改：Request 增 naming/collisionPolicy/subfolder 载体 + step 9 模板求值分支（legacy stem 面零 diff）
  - LightamerCore/Sources/Export/ExportQueue.swift                # 修改：Job/enqueue additive naming 载体（sequence per-batch 透传）
  - LightamerCore/Sources/Export/ExportEncoder.swift              # 修改：ExportEncodeRequest additive（exifSoftware/metadataPolicy/embedICC）+ EXIF 字典加工腿
  - LightamerCore/Sources/Export/ExportChainBuilder.swift         # 修改：mountXMP 增 policy 参数（默认 = .standard 逐字节现行为）
  - Tests/LightamerTests/ExportNamingE2ETests.swift               # 新建【Export】
  - Tests/LightamerTests/ExportEncoderMetadataTests.swift         # 新建【Export】
  - Tests/LightamerTests/ExportIccEmbedTests.swift                # 新建【Export】
  - Tests/LightamerTests/ExportRendererE2ETests.swift             # 修改：仅追加（既有测试零修改）
  - Project.swift                                                 # 修改：双登记
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # 修改：双登记
---

# Plan M2-9-03 — 命名/元数据/ICC 消费接线（wave 2b）

> **性质**：M2-9-01 交付的模型/引擎与 M2-9-02 交付的 DRT 链在本 plan 于渲染/编码
> 消费面合流——renderer 的命名腿（模板 + 冲突 + 子文件夹）、encoder 的元数据腿
> （EXIF Software + 剥离 + XMP gate + ICC embed/omit）。红线不变：六格式编码器
> （`ExportFormatSpec`/`ImageIOEncoders`/`WebPEncoder`）零 diff；legacy 面（模板
> nil + 政策默认）逐字节冻结。规格锚点 = RESEARCH §1.1（policy/ICC 面）+ §1.6
> （Alcedo 服务链：name 解析在 render task 内、`metadata_written_` 仅 STANDARD、
> `icc_embedded_` 仅 EMBED）+ D-M2-9-CONTEXT-5（EXIF Software）。

## 已定裁决（硬约束，不得重开）

- **OQ-4/模板求值点**：模板在 renderer 内逐 job 求值（Alcedo RunExportRenderTask
  cpp:131-143 同位）——上下文素材 = 解码后 `CaptureMetadata`（相机/镜头/EXIF 族）
  + sidecar rating（`readDocument` 面）+ 批内 sequence + 源 stem。**sequence = 批内
  图像序（1 起，同图多 variant 共享同序号）**。
- **OQ-5/冲突三档消费**：renderer step 9 走 policy；FAIL 档占用 = typed 抛错
  （job failed，不静默改名）；REPLACE = 既有名覆盖；Increment = 现行为逐字节。
  占用快照仍由 queue `occupiedNamesProvider` 在 dequeue 时枚举（子文件夹拼接目录）。
- **OQ-11/子文件夹**：`subfolder: String?` 载体；非 nil = 目标目录拼接 sanitized
  子目录（模板 sanitize 同函数）；目录不存在 = 渲染前创建（typed 失败不落半成品，
  L009 同族——编码仍 tmp 原子晋升）。默认 nil = 不启用。**UI 默认文案（zh「导出」/
  en "Processed"）与开关默认关 = M2-9-04 UI 面**，本 plan 只落行为。
- **OQ-3/落点**：本 plan 不动落点决策（App 装配面归 04）；renderer 只消费
  `destinationDirectory`（已含子文件夹拼接）。
- **D-M2-9-CONTEXT-5/EXIF Software**：STANDARD 档导出文件 EXIF `Software` =
  `Lightamer <version>`（App 传值，properties 路径 `kCGImagePropertyExifDictionary`）；
  NONE 档 = 全剥（无 EXIF 字典 → 无 Software）；TIFF `editorSignature` 预留面
  保留不冲突（两字段独立）。
- **OQ-6/剥离消费**：STANDARD 档——EXIF round-trip 保留但**剥 location（GPS 族）/
  设备序列号（BodySerialNumber 等 serial 族）/编辑历史**；XMP 编辑摘要 packet 归
  editingHistory 档（默认 false）→ `mountXMP` 默认**不嵌**（D-11-CONTEXT-5 语义
  收窄，DECISIONS 注记）；NONE 档 = metadata_written=false 语义（无 EXIF round-trip、
  无 XMP、无 Software）。exif/xmp/iptc 三 bool（模型层）v1 消费面 = xmp bool gate
  packet、exif bool gate round-trip、iptc bool gate IPTC 字典直通（round-trip 内
  随 EXIF 主开关，v1 不做 IPTC 单独剥离细目——DECISIONS 记录边界）。
- **OQ-7/入队闸门**：`drtOutput != nil` 时 peak 必须 finite 正数（Alcedo
  RequireResolvedExportOutputColor hpp:141-150 同构）——校验落 `ExportVariant.validate`
  扩展（Core 可测）；不满足 = typed 拒绝。`embedICC=false`（OMIT）= 编码 CGImage
  不挂目标色彩空间（untagged 产物）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 renderer 命名腿分派（step 9 改造的形状）

- Request 增：`naming: ExportNamingRequest? = nil`（`pattern: String` +
  `sequence: Int` + `fallbackStem: String = "image"`）+ `collisionPolicy:
  ExportCollisionPolicy = .increment` + `subfolder: String? = nil`。
- 分派：`naming == nil` → 既有 stem+tag 路径**逐字节**（legacy sheet + 既有测试全绿
  的锚）；非 nil → `ExportFileNameTemplate.parse` + render（上下文 = KD-2 构造）→
  渲染空 → fallback → `ExportNamer.destinationURL(stem: 模板结果, tag: 原样, ...,
  policy)`。**tag 拼接面不变**（多 variant 批次不互覆；单 variant tag=nil 即纯模板
  名——DECISIONS 记录与 Alcedo 单 recipe 世界的差异）。
- 子目录拼接在 Request 消费前（renderStage 入口）：`destinationDirectory.appending
  (subfolder)`，occupancy 枚举天然命中拼接目录（queue provider 收拼接后 URL）。

### KD-2 模板上下文构造（Core 内聚，App 零预加工）

- renderer 在 decode 后构造 `ExportFileNameContext`：`sourceStem` = 源文件 stem；
  capture 族 = `decoded.capture`（CaptureMetadata.swift:8-35 现成 8 字段）；
  `rating` = `readDocument(imageURL)?.rating`（override 模式同样读盘——rating 非渲染
  参数，盘上 META 即真相）；`sequence` = Request 载体。App 不预渲染模板（唯一真相
  在 renderer，批量 sequence 单源）。
- shutter/aperture/focal 渲染语义 = M2-9-01 T2 已钉（Alcedo cpp:136-171 对表）——
  本 plan 不重开。

### KD-3 encoder 元数据腿（`ExportEncoder.swift` additive）

- `ExportEncodeRequest` 增：`exifSoftware: String? = nil` + `metadataPolicy:
  ExportMetadataPolicy = .standard` + `embedICC: Bool = true`（默认实参 = 全部既有
  调用点零改动）。
- EXIF 字典加工链（properties 路径，`ImageIOEncoders` 零 diff——加工发生在字典
  进 destination 前）：NONE → 跳过整个 round-trip；STANDARD → round-trip 后
  剥 GPS 族（`{GPS}` dictionary 整体 + EXIF GPS 子键）+ serial 族键
  （BodySerialNumber 0xa431 等——执行时以源 RAW 实测键集定清单，入 DECISIONS）+
  写 `Software`。剥离清单 = 常量表单源（测试逐键钉）。
- XMP gate：`mountXMP(destination:format:sourceURL:policy:)`——`policy.mode ==
  .none || !policy.includeEditingHistory` → `.skippedNoFields` 同型新 outcome
  （`.skippedByPolicy` additive 枚举臂——穷举面全列补全，L 系纪律）。
- OMIT：CGImage 构造 colorspace nil 路径（encodeRequest.embedICC=false）——产物
  untagged；测试 = metadata 扫描无 ICC profile 键。

### KD-4 EXIF Software 版本源

- App 层（04 装配）传 `Bundle.main` 短版本串（`Lightamer <CFBundleShortVersionString>`）；
  Core 侧不读 Bundle（Core 纯度纪律）——本 plan 的 encoder 只承 String 载体，测试
  用固定串钉写入位。

## read_first

1. `M2-9-CONTEXT.md` 裁决记录 + OQ-3/5/6/11 + D-5 正文；`RESEARCH-NOTES.md`
   §1.1（policy 默认）/§1.6（服务链 face）/§2.1（ExportNamer/Encoder/XMP 锚点）。
2. `LightamerCore/Sources/Export/ExportRenderer.swift` step 9（:356-373）+
   `ExportQueue.swift` Job/enqueue/occupiedNamesProvider + `ExportEncoder.swift`
   全文（properties 路径 + ExportEncodeRequest）+ `ExportChainBuilder.mountXMP`。
3. M2-9-01/02 两 PLAN + 对应 DECISIONS 底稿（模板语义/冲突三档/DRT 载体——本 plan
   消费不重开）。
4. `LightamerCore/Sources/Decode/CaptureMetadata.swift`（模板 8 字段可达性）。
5. Alcedo 只读：`export_service.cpp`（:69-93 commit / :131-143 name 解析 /
   :217-221 三 tally 位）；`export_recipe.cpp`（:376-422 解析错误——fallback 时机）。

## 纪律（强制）

1. 提交/边界/收口纪律同 M2-9-01。
2. **红线**：`ImageIOEncoders.swift`/`WebPEncoder.swift`/`ExportQuantizer.swift`/
   `ExportQueueContract.swift` 零 diff；既有 ExportRendererE2ETests/
   ExportPhaseE2ETests/ExportNamerTests/XMPExportMatrixTests 零修改全绿（legacy 面
   冻结的机检锚——mountXMP 默认参数路径 outcome 与现行为逐值同）。
3. 测试全部【Export】；双登记；全套基线 2577/16/0。
4. E2E 磁盘纪律：临时目录 scratch（`FT`/`/tmp` 即弃），禁入仓 fixture 残留。

## Tasks

### T1 renderer 命名腿（KD-1/KD-2）

- **action**：Request 载体 + step 9 分派 + 子目录拼接 + queue additive 透传；测试：
  模板渲染名落盘（12 字段抽锚 + sequence 递增跨图）+ fallback 触发（空渲染）+
  tag 并存（多 variant 同模板不互覆）+ 三档冲突 E2E（fail=typed failed job 产物
  零写盘/replace=覆盖/increment=现状）+ 子目录创建 + 子目录内 occupancy 枚举。
- **验收标准**
  - [ ] naming==nil 既有 E2E 全族零修改全绿；模板路径全族测试绿。
  - [ ] FAIL 档占用 = job failed（typed AppError）且目标目录零新文件。

### T2 encoder 元数据腿（KD-3/KD-4）

- **action**：ExportEncodeRequest additive 三字段 + NONE 短路 + STANDARD 剥离常量表
  + Software 写入 + mountXMP policy gate（`.skippedByPolicy` 臂 + 穷举消费面补全）+
  测试：三档产物 EXIF/XMP 字节面（NONE 无 EXIF 字典/STANDARD 有 Software 无 GPS 无
  serials/编辑摘要 packet 默认缺席、editingHistory=true 时回归现 packet 行为）+
  XMPExportMatrixTests 既有矩阵零漂移（policy=.standard 显式传参的既有调用点——
  renderer 消费点改传 variant 政策，**默认参数保持现 packet 行为吗？否**——见风险）。
- **验收标准**
  - [ ] EXIF Software = 载体串逐字节（测试固定串）；NONE 全剥断言。
  - [ ] 剥离族逐键断言（GPS/serials 清单 = 常量表）；exif round-trip 其余键保留。
  - [ ] `metadataPolicy` 默认值下 XMP packet 缺席（OQ-6 收窄生效）；
        `includeEditingHistory=true` → packet 回归在案行为（对照测试）。

### T3 ICC embed/omit + 入队闸门

- **action**：encodeRequest.embedICC 消费（CGImage colorspace nil 路径）+
  `ExportVariant.validate` 扩展（drtOutput peak 闸门）+ 测试：EMBED 产物 ICC 在
  （对照 11-02 golden 面）/ OMIT 产物无 ICC profile 键 / peak 非有限正数 typed
  拒绝 / drtOutput=nil 不触发闸门（legacy 变体合法）。
- **验收标准**
  - [ ] EMBED/OMIT 两态产物 metadata 断言绿；闸门 typed 拒绝绿。

### T4 波次收尾核对

- **action**：Export bundle 终跑 + 全套 `--all`（前报备）+ 计数对账 + `git diff
  --stat` 对表 + DECISIONS 底稿（剥离键清单实测/`.skippedByPolicy` 穷举面/iptc
  v1 边界/命名与 Alcedo 差异注记）。
- **验收标准**
  - [ ] 全套 0 fail（2577 + 01/02/03 增量精确对账）；diff 边界 == front-matter。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 模板命名 E2E 全族绿（渲染名/sequence/fallback/tag 并存/三档冲突/子目录） | 测试名 |
| 2 | legacy 命名面（naming==nil）既有测试族零修改全绿 | 测试目录 diff + bundle 行 |
| 3 | EXIF Software/NONE 全剥/GPS+serials 剥离逐键断言绿 | 测试名 |
| 4 | XMP packet 默认缺席 + editingHistory=true 回归 + 既有 XMP 矩阵零漂移 | 测试名 |
| 5 | EMBED/OMIT 两态 + peak 闸门 typed 拒绝 | 测试名 |
| 6 | ImageIOEncoders/WebPEncoder/ExportQuantizer/ExportQueueContract 零 diff | `git diff` |
| 7 | ExportQueue 引擎体零 diff（仅 additive 载体） | `git diff` 逐 hunk |
| 8 | 全套回归 0 fail；双登记闭环 | bundle 行 + grep |

## 风险与边界

- **mountXMP 默认参数语义变更风险**：OQ-6 裁决 = 「默认剥离档优先」——`policy`
  参数**默认值 = `.standard`（剥 editingHistory）**，这意味着既有默认调用点行为
  变化（packet 从嵌变不嵌）。处置：XMPExportMatrixTests 矩阵以**显式传参
  `editingHistory=true`** 改造锚定现 packet 行为（该测试文件允许修改——它是行为
  规格不是 legacy 面），renderer 消费点传 variant 政策；改动范围与逐条对照入
  DECISIONS，全套零 fail 为门。若判该矩阵改造面超预算 → 回退方案 = 默认参数保持
  现 packet 行为、剥离只在显式 policy 下生效，并在 DECISIONS 记录偏差待裁——
  **两案不得混用**（单一默认语义）。
- **serial 族键集**：各厂商 RAW 的 serial 落点（EXIF 0xa431 / MakerNote 内嵌）不
  一——v1 剥离清单限 EXIF 标准位（MakerNote 整体本就不在 round-trip 白名单，
  实测确认后入 DECISIONS）。
- **FAIL 档批量地雷**：无 sequence 模板 + FAIL = 第 2 张起全失败——预期行为
  （Alcedo 同款语义；OQ-5 已以 Increment 默认消解默认档风险），UI 文案警示归 04。

## 提交约定

- T1 `feat(m2-9): template-driven naming with collision tiers in export renderer`
- T2 `feat(m2-9): metadata policy consumption with exif software tagging`
- T3 `feat(m2-9): icc embed-omit face and resolved output color gate`
- T4 `test(m2-9): wave-2b reconciliation`
- 全英文；body 写 what+why；不 push。
