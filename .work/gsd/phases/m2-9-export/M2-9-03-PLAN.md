---
phase: m2-9
plan: "M2-9-03"
title: "命名/元数据/ICC 消费接线（wave 2b）——文件名模板求值进 renderer（逐 job 上下文 + sequence）+ 冲突三档/子文件夹 E2E + EXIF Software 写入（Lightamer <version>）+ 元数据剥离消费（location/serials/editing-history 三剥 + XMP packet gate）+ ICC embed/omit 编码消费 + 入队闸门（resolved output color，Alcedo RequireResolvedExportOutputColor 同构）"
wave: 2
depends_on: ["M2-9-01", "M2-9-02"]
autonomous: true
requirements: [M2EXP-02, M2EXP-03, M2EXP-04]
estimated_new_tests: 21
bundles: [Export]
files_modified:
  - LightamerCore/Sources/Export/ExportRenderer.swift             # 修改：Request 增 naming/collisionPolicy/subfolder 载体 + step 9 模板求值分支（legacy stem 面零 diff）+ sizing 腿切 resolveExportResolution（修正后 DPI 消费，checker 回注 E6）
  - LightamerCore/Sources/Export/ExportQueue.swift                # 修改：Job/enqueue additive naming 载体（sequence per-batch 透传）
  - LightamerCore/Sources/Export/ExportEncoder.swift              # 修改：ExportEncodeRequest additive（exifSoftware/metadataPolicy/embedICC）+ EXIF 字典加工腿 + OMIT post-encode ICC 剥离步（checker 回注 E1 案 A）
  - LightamerCore/Sources/Export/ExportChainBuilder.swift         # 修改：mountXMP 增 policy 参数（默认 = .standard 逐字节现行为）
  - LightamerCore/Sources/Export/ExportRecipe.swift               # 修改：仅 ExportVariant.validate 扩展 additive（drtOutput peak 闸门）；ExportFormatSpec/ExportColorSpace 枚举体零 diff 延续 01 封存口径（checker 回注 E3）
  - LightamerCore/Sources/Export/ImageIOEncoders.swift            # 修改：仅元数据装配腿 additive（ImageIOEncodeCore 单点新增 processedProperties 入口 + 五 encoder 换调用点）；编码核心面零 diff——makeCGImage 签名/CGImageDestination 参数/质量映射/量化消费 hunk 级机检（checker 回注 E1 案 A 封存面收窄）
  - Tests/LightamerTests/ExportNamingE2ETests.swift               # 新建【Export】
  - Tests/LightamerTests/ExportEncoderMetadataTests.swift         # 新建【Export】
  - Tests/LightamerTests/ExportIccEmbedTests.swift                # 新建【Export】
  - Tests/LightamerTests/ExportRendererE2ETests.swift             # 修改：仅追加（既有测试零修改）
  - Tests/LightamerTests/XMPExportMatrixTests.swift              # 修改：显式传参改造白名单（checker 回注 E2——既有 case 补 editingHistory=true 显式参锚定原 packet 行为 + 新增默认档断言；改造前后 case 清单入 DECISIONS；已移出零修改封存清单，非 legacy 面）
  - Project.swift                                                 # 修改：双登记
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt    # 修改：双登记
---

# Plan M2-9-03 — 命名/元数据/ICC 消费接线（wave 2b）

> **性质**：M2-9-01 交付的模型/引擎与 M2-9-02 交付的 DRT 链在本 plan 于渲染/编码
> 消费面合流——renderer 的命名腿（模板 + 冲突 + 子文件夹）、encoder 的元数据腿
> （EXIF Software + 剥离 + XMP gate + ICC embed/omit）。红线（checker 回注
> E1/E2 后口径）：六格式**编码核心**零 diff——`ImageIOEncoders.swift` 封存面收窄
> 为编码核心面（元数据装配腿 additive，案 A）、`WebPEncoder.swift` 整文件零 diff；
> legacy 面 = **代码路径/UI 面**（naming==nil 分支、encoder 调用形状）字节冻结；
> 元数据政策默认档 = OQ-6 用户裁决的**有意行为变更**（非冻结面，波及全部导出
> 路径）。规格锚点 = RESEARCH §1.1（policy/ICC 面）+ §1.6
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
  扩展（Core 可测）；不满足 = typed 拒绝。`embedICC=false`（OMIT）=
  **post-encode ICC 剥离步**（JPEG/PNG/TIFF 产物 untagged；HEIC/AVIF/WebP 容器
  不可剥 = OMIT 不可达档 typed 记录——checker 回注 E1：nil-colorspace 路径技术
  不可行）。

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

### KD-3 encoder 元数据腿（`ExportEncoder.swift` additive + `ImageIOEncoders` 装配腿 additive）

> checker 回注（2026-10-02）[E1 案 A]：原案「`ImageIOEncoders` 零 diff + 加工发生
> 在字典进 destination 前」自相矛盾——EXIF 字典装配发生在该文件**内部**
> （`sourceEXIF` 与各 encoder 的 properties 组装，JPEG/PNG 等五 encoder 同文件）；
> 且 OMIT 的「CGImage 构造 colorspace nil 路径」技术不可行：CGImage 位图构造传
> nil colorspace 仅对 image mask 合法，常规位图返回 nil → 现有 guard 直接 throw
> `encodeFailed`，untagged 产物无法经 nil-space 达成。**封存面收窄（案 A）**：
> 编码核心面零 diff，元数据装配腿 additive；OMIT 改 post-encode ICC 剥离。
> **弃案 B**（解除 encoder 文件级封存、改「行为封存」= golden 全量零漂移 + 文件
> diff 逐 hunk 审限元数据/ICC 面）理由：11-02 golden 将从「机检锚」降级为唯一
> 行为保障，逐 hunk 审主观面扩大、复审成本高；案 A 以「编码核心面 hunk 级零
> diff + 11-02 golden 双保险」达成同等保障且封存面更窄。两案禁混用，本 plan 取 A。

- `ExportEncodeRequest` 增：`exifSoftware: String? = nil` + `metadataPolicy:
  ExportMetadataPolicy = .standard` + `embedICC: Bool = true`（默认实参 = 全部既有
  调用点零改动）。
- EXIF 字典加工链 = `ImageIOEncodeCore` 单点新增入口（如 `processedProperties(
  for:request:)`，additive）——五 encoder（JPEG/PNG/TIFF/HEIC/AVIF）只换调用点；
  NONE → 跳过整个 round-trip；STANDARD → round-trip 后剥 GPS 族（`{GPS}`
  dictionary 整体 + EXIF GPS 子键）+ serial 族键（BodySerialNumber 0xa431 等——
  执行时以源 RAW 实测键集定清单，入 DECISIONS）+ 写 `Software`。剥离清单 =
  常量表单源（测试逐键钉）。**编码核心面零 diff 边界**：`makeCGImage` 签名与
  CGImageDestination 参数/质量映射/量化消费 hunk 级机检（AC6）。
- XMP gate：`mountXMP(destination:format:sourceURL:policy:)`——`policy.mode ==
  .none || !policy.includeEditingHistory` → `.skippedNoFields` 同型新 outcome
  （`.skippedByPolicy` additive 枚举臂——穷举面全列补全，L 系纪律）。
- OMIT（embedICC=false）= **post-encode ICC 剥离步**：`ExportEncoder.swift` 内、
  mountXMP 同位次的新 outcome 面（renderer 挂载点同族）——JPEG 去 APP2
  ICC_PROFILE marker / PNG 去 iCCP chunk / TIFF 去 34675 tag（XMPContainerInjector
  同族纯 Data 平面操作）；HEIC/AVIF/WebP = OMIT 不可达档 typed 记录（容器级 ICC
  剥离不做，产物仍 EMBED；UI 禁用/说明归 04）。测试 = JPEG/PNG/TIFF OMIT 产物
  metadata 无 ICC profile 键 + 不可达档 typed 断言。

### KD-4 EXIF Software 版本源

- App 层（04 装配）传 `Bundle.main` 短版本串（`Lightamer <CFBundleShortVersionString>`）；
  Core 侧不读 Bundle（Core 纯度纪律）——本 plan 的 encoder 只承 String 载体，测试
  用固定串钉写入位。

## read_first

1. `M2-9-CONTEXT.md` 裁决记录 + OQ-3/5/6/11 + D-5 正文；`RESEARCH-NOTES.md`
   §1.1（policy 默认）/§1.6（服务链 face）/§2.1（ExportNamer/Encoder/XMP 锚点）。
2. `LightamerCore/Sources/Export/ExportRenderer.swift` step 9（:356-373）+
   `ExportQueue.swift` Job/enqueue/occupiedNamesProvider + `ExportEncoder.swift`
   全文（properties 路径 + ExportEncodeRequest）+ `ExportChainBuilder.mountXMP` +
   `ExportRecipe.swift` validate（peak 闸门落点，checker 回注 E3）+
   `ImageIOEncoders.swift`（元数据装配面与编码核心面的分界——E1 案 A）。
3. M2-9-01/02 两 PLAN + 对应 DECISIONS 底稿（模板语义/冲突三档/DRT 载体——本 plan
   消费不重开）。
4. `LightamerCore/Sources/Decode/CaptureMetadata.swift`（模板 8 字段可达性）。
5. Alcedo 只读：`export_service.cpp`（:69-93 commit / :131-143 name 解析 /
   :217-221 三 tally 位）；`export_recipe.cpp`（:376-422 解析错误——fallback 时机）。
6. 行号锚以**符号检索为准**——源码演进致行号漂移（checker 回注 m2 实测：
   ExportRenderer.Request instancesOverride 实际 :93/:106），执行期以符号名定位，
   行号偏差不作违例。

## 纪律（强制）

1. 提交/边界/收口纪律同 M2-9-01。
2. **红线（checker 回注 E1/E2 后口径）**：`WebPEncoder.swift`/`ExportQuantizer.swift`/
   `ExportQueueContract.swift` 整文件零 diff；`ImageIOEncoders.swift` **编码核心面**
   零 diff（makeCGImage 签名与 CGImageDestination 参数/质量映射/量化消费——元数据
   装配腿 additive，hunk 级机检，E1 案 A）；legacy 冻结 = **代码路径/UI 面**
   （naming==nil 分支、encoder 调用形状），既有 ExportRendererE2ETests/
   ExportPhaseE2ETests/ExportNamerTests 零修改全绿；元数据政策默认档 = OQ-6
   用户裁决的有意行为变更（波及全部导出路径，含 legacy sheet 产物：packet 不嵌、
   GPS/serials 剥离）；**XMPExportMatrixTests 移出零修改封存清单**，列为显式传参
   改造白名单（见风险节，E2）。
3. 测试全部【Export】；双登记；全套基线 2577/16/0。
4. E2E 磁盘纪律：临时目录 scratch（`FT`/`/tmp` 即弃），禁入仓 fixture 残留。

## Tasks

### T1 renderer 命名腿（KD-1/KD-2）

- **action**：Request 载体 + step 9 分派 + 子目录拼接 + queue additive 透传 +
  **修正后 DPI 消费接线（显式第 3 步——checker 回注 E6，01 KD-1 交接的正主落点；
  本 plan 本就改 ExportRenderer，files_modified 无需扩）**：renderStage sizing 腿
  切 `resolveExportResolution`（拿 cap 修正后 dpi）+ `StageOutput.dpi =
  result.dpi`。测试：模板渲染名落盘（12 字段抽锚 + sequence 递增跨图）+ fallback
  触发（空渲染）+ tag 并存（多 variant 同模板不互覆）+ 三档冲突 E2E（fail=typed
  failed job 产物零写盘/replace=覆盖/increment=现状）+ 子目录创建 + 子目录内
  occupancy 枚举 + **DPI 元数据 golden 一条**：physical（如 3000×2000@300dpi）+
  cap 2000 → 产物 `kCGImagePropertyDPIWidth/Height` = 200。
- **验收标准**
  - [ ] naming==nil 既有 E2E 全族零修改全绿；模板路径全族测试绿。
  - [ ] FAIL 档占用 = job failed（typed AppError）且目标目录零新文件。
  - [ ] 修正后 DPI golden 绿（physical+cap → 产物 DPI 元数据 = 修正值 200 锚）；
        legacy 三模式 `StageOutput.dpi` 与现行为逐值同（DECISIONS 论证：legacy 面
        构造不出 physical/cap，resolve 对其输出与 targetSize 逐值同——字节零漂移）。

> checker 回注（2026-10-02）[E6]：原 plan 集该消费交接悬空——01 KD-1 写「M2-9-02
> 的 renderer 切换到 resolve」而 02 任务集/AC 无任何 sizing/DPI 条目，physical+cap
> 时 `StageOutput.dpi`（ExportRenderer.swift:367 现取 `effectiveSizing.dpi`）永远
> 拿未修正 DPI，D-6 物理打印尺寸守恒在产物元数据上失效（M2EXP-01 缺一角）。消费
> 落点定为 03 T1 显式第 3 步。

### T2 encoder 元数据腿（KD-3/KD-4）

- **action**：ExportEncodeRequest additive 三字段 + NONE 短路 + STANDARD 剥离常量表
  + Software 写入（装配腿 = `ImageIOEncodeCore.processedProperties` 单点新增入口 +
  五 encoder 换调用点——E1 案 A，编码核心面零 diff）+ mountXMP policy gate
  （`.skippedByPolicy` 臂 + 穷举消费面补全）+
  测试：三档产物 EXIF/XMP 字节面（NONE 无 EXIF 字典/STANDARD 有 Software 无 GPS 无
  serials/编辑摘要 packet 默认缺席、editingHistory=true 时回归现 packet 行为）+
  **XMPExportMatrixTests 白名单改造**（checker 回注 E2）：既有矩阵逐 case 补
  `editingHistory=true` 显式参锚定原 packet 行为 + 新增默认档断言（packet 缺席）；
  改造前后 case 清单逐条入 DECISIONS。
- **验收标准**
  - [ ] EXIF Software = 载体串逐字节（测试固定串）；NONE 全剥断言。
  - [ ] 剥离族逐键断言（GPS/serials 清单 = 常量表）；exif round-trip 其余键保留。
  - [ ] `metadataPolicy` 默认值下 XMP packet 缺席（OQ-6 收窄生效）；
        `includeEditingHistory=true` → packet 回归在案行为（对照测试）。
  - [ ] XMPExportMatrixTests 改造后全绿（既有 case 显式参 + 默认档新断言；白名单
        case 清单 diff 入 DECISIONS）。

### T3 ICC embed/omit + 入队闸门

- **action**：encodeRequest.embedICC 消费（**post-encode ICC 剥离步**——KD-3 E1
  案 A：ExportEncoder.swift 内 mountXMP 同位次 outcome 面，JPEG/PNG/TIFF 剥 +
  HEIC/AVIF/WebP typed 不可达档）+ `ExportVariant.validate` 扩展（drtOutput peak
  闸门——落点 `ExportRecipe.swift`，front-matter 已登记，checker 回注 E3；仅
  validate additive，ExportFormatSpec/ExportColorSpace 枚举体零 diff）+ 测试：
  EMBED 产物 ICC 在（对照 11-02 golden 面）/ OMIT 产物无 ICC profile 键
  （JPEG/PNG/TIFF）+ 不可达档 typed 断言 / peak 非有限正数 typed
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
| 1 | 模板命名 E2E 全族绿（渲染名/sequence/fallback/tag 并存/三档冲突/子目录）+ 修正后 DPI golden（physical+cap → 产物 DPI 元数据 = 修正值） | 测试名 |
| 2 | legacy 命名面（naming==nil）既有测试族零修改全绿 | 测试目录 diff + bundle 行 |
| 3 | EXIF Software/NONE 全剥/GPS+serials 剥离逐键断言绿 | 测试名 |
| 4 | XMP packet 默认缺席 + editingHistory=true 回归 + XMPExportMatrixTests 白名单改造全绿（既有 case 显式参锚定原行为 + 新增默认档断言，case 清单入 DECISIONS） | 测试名 + DECISIONS case 清单 |
| 5 | EMBED/OMIT 两态 + peak 闸门 typed 拒绝 | 测试名 |
| 6 | WebPEncoder/ExportQuantizer/ExportQueueContract 整文件零 diff；ImageIOEncoders **编码核心面**零 diff（makeCGImage 签名/CGImageDestination 参数/质量映射/量化消费 hunk 级审——元数据装配腿 additive，E1 案 A） | `git diff` 逐 hunk |
| 7 | ExportQueue 引擎体零 diff（仅 additive 载体） | `git diff` 逐 hunk |
| 8 | 全套回归 0 fail；双登记闭环 | bundle 行 + grep |

## 风险与边界

- **mountXMP 默认参数语义变更风险**：OQ-6 裁决 = 「默认剥离档优先」——`policy`
  参数**默认值 = `.standard`（剥 editingHistory）**，这意味着既有默认调用点行为
  变化（packet 从嵌变不嵌）。这是**有意行为变更**（checker 回注 E2：与「默认参数
  路径 outcome 逐值冻结」类承诺不可同真，后者已从纪律中移除）。处置：
  XMPExportMatrixTests 矩阵以**显式传参 `editingHistory=true`** 改造锚定现 packet
  行为（该测试文件是行为规格不是 legacy 面——从零修改封存清单移出，列为显式传参
  改造白名单），renderer 消费点传 variant 政策；改动范围与逐条对照入 DECISIONS，
  全套零 fail 为门。**回退方案（默认参数保持现 packet 行为、剥离只在显式 policy
  下生效）= 用户升级点，非执行方可自裁项**——OQ-6 是用户裁决（CONTEXT 裁决记录
  2026-10-02），plan 不得以 DECISIONS 注记自行翻转；执行中若判矩阵改造面超预算，
  登记阻塞待用户裁决。
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
