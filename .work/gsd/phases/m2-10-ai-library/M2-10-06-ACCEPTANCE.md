# M2-10-06 ACCEPTANCE — AI 出片可编辑副本（分块推理 + sidecar v8 + 副本落盘 + 对话框）

> 验收 subagent（零共享上下文，实测核验不轻信）。验收对象 = 四提交
> `dba72ce`（T1）/ `b4d13d6`（T2）/ `7786ff8`（T3）/ `5183343`（T4 收口，
> 验收起点 HEAD，未 push）。正本输入 = PLAN（含 checker 回注 M4）+ SUMMARY +
> DECISIONS（§1..13）+ LESSONS L065。验收日期 2026-10-04。
> 基线 = M2-10-05 验收终态 2890/16/0（HEAD `1491f8f`）。

## 结论

**PASS / 0 error + 1 minor(挂账) + 3 observation** —— AC 8/8 全过；全套独立
复跑经在案 flake 恢复协议后**对账精确成立** `2926/16/0`（App 首轮
601/0/**1** = `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`
在案 ANE
环境型 flake〔M2-10-01 同用例同形态，本波零接触域〕→ 隔离 11/0/0 + App
全量补跑 601/0/0，恢复路径与 01/05 两波先例同构）；**越界四件追认采纳**
（授权原文三处逐字在案，改动半径全 additive，05 的 27 worker 测试零 diff
全绿）；真模型 golden **激活态亲点**（`testRealModelGolden64SquaredTo
256SquaredThroughWorker` passed 3.352s 非 skip——真 worker 子进程
64²→256²，tileEdges `[256]`/scale 4 发现断言）；**M2AI-09 翻勾**。
验收批小修一例（cosmetic 重复赋值行，`b766cf5` + App 回归双绿）。

## 全套独立复跑（对账 2926/16/0）

`caffeinate -dis xcodebuild -workspace Lightamer.xcworkspace -scheme
Lightamer -configuration Debug build-for-testing`（TEST BUILD SUCCEEDED，
退出码 0 亲验）→ `caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 467/1/0（peak 5317MB） | 467/1/0（7090MB） | 零漂移 |
| IOPParity | 362/3/0（5140MB） | 362/3/0（5985MB） | 零漂移 |
| Layers | 298/3/0（1049MB） | 298/3/0（1058MB） | 零漂移 |
| Library | 581/4/0（599MB） | 581/4/0（599MB） | 零漂移 |
| Sessions | 279/4/0（1246MB） | 279/4/0（1607MB） | 零漂移 |
| Export | 338/1/0（5109MB） | 338/1/0（5377MB） | 零漂移（红线门） |
| App | 首轮 601/0/**1** → 隔离 SidecarV5Tests **11/0/0** → 全量补跑 **601/0/0**（2831MB；修复后回归再跑 601/0/0，2508MB） | 601/0/0（2831MB） | 零漂移（flake 恢复，见 O-1） |
| **TOTAL** | **2926/16/0** | 2926/16/0 | **精确对账** |

- 对账：2890（05 验收基线）+ **36 精确** = TileInferenceTests 13〔LIB〕+
  SidecarV8Tests 5 + EnhanceCopyTests 8 + EnhanceDialogTests 10〔APP〕；
  `grep -c "func test"` = 13/5/8/10 与 BUNDLE-MAP 四行逐位一致；App
  578→601、Library 568→581。
- skip 16 = 1+3+3+4+4+1+0 亲点 = 基线**零新增**（金样在场环境激活态非
  skip）；peakRSS 最大 IOP 5317MB < 8192 门，零 MEMFAIL。
- **L055 对策机检亲跑**：七日志 `terminated abnormally` 计数**全零**；
  `Fatal error|EXC_BAD|Segmentation|crashed` 信号零命中；七 Executed 行
  （467/362/298/581/279/338/601 + skip 1/3/3/4/4/1/0）与 BUNDLE 行逐值
  一致——无假绿形态。
- **金样激活态亲点**：`testRealModelGolden64SquaredTo256SquaredThrough
  Worker` **passed 3.352s 非 skip**（真 worker 子进程 + capability
  discovery）；`testRealModelEmbedImageThroughWorkerProcess` 2.373s 非
  skip（05 链路无回归）。
- 修复批回归：`b766cf5` 重建后 EnhanceDialogTests 隔离 **10/0/0** +
  App 全量 **601/0/0**——小修零涟漪。

## 逐 commit 边界（diff 全域 18 文件对表）

| commit | 文件集 | 判定 |
|---|---|---|
| T1 `dba72ce` | LightamerSidecar.swift（+96）+ TileInference.swift（266 新）+ SidecarV8Tests（233 新）+ TileInferenceTests（256 新）+ Project.swift（+2）+ BUNDLE-MAP（+6） | == 申报（BUNDLE-MAP 两行随测试文件先行登记） |
| T2 `b4d13d6` | EnhanceCopyWriter.swift（242 新）+ ImportService.swift（+95/-1）+ EnhanceCopyTests（371 新）+ Project.swift（+1）+ BUNDLE-MAP（+1） | == 申报 |
| T3 `7786ff8` | EnhanceEngine.swift（390 新）+ EnhanceDialogModel.swift（346 新）+ EnhanceDialog.swift（270 新）+ EnhanceDialogTests（380 新）+ Project.swift（+1）+ **越界四件**（protocol +44/-、client +69、main +131/-23、enhancement 355 新）+ BUNDLE-MAP（+1） | == 申报 + §9 四件（见越界判定节） |
| T4 `5183343` | SUMMARY + DECISIONS + GOAL-STATE（+1）+ LESSONS（+16 = L065） | == 申报 |

- `git diff --name-only dba72ce^..HEAD` = **18 文件** = front-matter 12
  （源码 8 + 测试 4）+ 账本 5（GOAL-STATE/LESSONS/DECISIONS/SUMMARY/
  BUNDLE-MAP）+ **越界四件（申报内）**——**front-matter 外未申报源码
  零**；`git diff -- Tests/` = 仅四新建文件，既有测试零改动（AC#7；
  SidecarV7Tests 本就引用 `schemaVersionCurrent`，T1 免机械同步属实）。
- SUMMARY 提交账 T4 行「BUNDLE-MAP 三行」为表述滑差：实际 BUNDLE-MAP
  触碰落在 T1(+6)/T2(+1)/T3(+1)（行随各自测试提交走，登记闭环本身
  双命中逐位一致）——见 O-2。
- **域外零 diff 亲跑**：`git diff --name-only -- App/…/Export App/…/MCP
  LightamerCore/Sources/MCP LightamerCore/Sources/Version App/…/Version
  App/…/Sessions` = **零文件**（AC#4/#7 机检）；Project.swift App 源
  glob（`App/Sources/**`）使 AIWorkerEnhancement 免登记，T3 Project.swift
  +1 = EnhanceDialogTests 一行，核验一致。

## 越界四件判定（DECISIONS §9 申报，逐件核验）

**判定：三处授权原文逐字在案，四件改动半径全 additive，追认采纳。**

1. **授权链亲证（逐字引用）**：
   - PLAN KD-1 :72「…M2-10-05 会话缓存语义扩展 `shape` 维，**帧协议
     `tile:{h,w}` 字段承载**」——protocol 填字段授权；
   - PLAN T3 AC :214「**worker 协议若需 `tile` 形状字段 = additive 且 05
     测试零 diff（越界线）**」——additive 边界授权；
   - M2-10-05-SUMMARY 交接节 :133-135「…增强族（embeddingDim==nil）回
     typed『opens via the M2-10-06 leg』error 帧——**06 落地 = AIWorkerMain
     增强腿 + InProcessMLModelRunner 单资产形态扩展**」——worker 侧两文件
     授权。
   front-matter 清单漏列四者 = 起草缺口（DECISIONS §9 自认），非授权缺口。
2. **AIWorkerProtocol.swift**：`AITileParameters` 三字段 + `AIWorkerResult`
   双字段**全 optional**，帧 envelope 零动（05 的 AIWorkerProtocolTests 10 +
   AIWorkerClientTests 9 + CompatRecordTests 8 = 27 零 diff 全绿亲点）——
   越界线（帧级形状改动）未触。
3. **AIWorkerClient.swift**：`openEnhancement`/`enhanceTile` 两 additive
   方法 + open 响应 facts 记账（CLIP open 清位防 stale）+ teardown 清位
   ——tile 通道消费面，无既有方法签名改动。
4. **AIWorkerMain.swift**：增强 open leg（05 占位 error 分支退役 = 交接
   明文）+ run 分发（先 embed runner 后 enhancement session，run-before-open
   typed 面保持）+ stop 双 session 表清空——交接授权正主。
5. **AIWorkerEnhancement.swift（新建 355 行）**：`EnhancementSession`——
   IO 名动态发现（input 优先 `input_tile` 否则首个 / output 取首个）+
   supported edges 三级发现（enumerated → min==max range → manifest）+
   scale = out/in edge 比 + 编译缓存单模型形态 + tile run（pad-to-fit
   CHW / denoise 强度 worker 侧线性插值 / fp16 dataType dispatch L060）。
   **无头纪律亲验**：worker 五文件 grep `Sidecar|import SwiftUI|import
   AppKit` = **零命中**（零 sidecar 直写）。

## 重点抽查（读码 + 测试揭穿力 + 实测）

### 1. TileInference 数学（KD-1）

- `axisSpans`：`start = min(i*stride, remainder)`（stride = edge−overlap）
  ——末 tile start = remainder，恰对齐轴尾（`remainder + edge = length`），
  长轴全 exact-shape 零截断余数；短轴单 exact span。测试钉 7 种长度
  （257..4097）+ 覆盖连续 + 邻 tile 重叠 ≥ ramp 宽。
- **ramp 权重本征和 = 17/16（重叠区恒定）**，非 1——设计自洽点：引擎以
  `axisWeightSums`（严格正）作 blend 分母归一，归一后恰 1（测试锚
  `testWeightsArePositiveAndNormalizeToExactlyOne` + 可分离性 2D 积锚）。
  「权重和恒 1」口径 = 归一后语义，测试与实现互证。
- `feedEdge` = 最小 supported ≥ span（exact / pad-to-fit 双腿）；400MP
  预算**输出像素域**（`w·scale·h·scale`，§5 修正在码）——tests 钉
  10001²@×2 拒（typed + limit 断言）/ 10000²@×2 过（1764 tile）。
- 进度 `15 + 78·done/total`（15..93 钉死端点 + 单调 + total=0 钳制）。

### 2. blend 行距修复揭穿力（首轮抓红回归）

- **exact-tile 掩蔽面**：`testEngineMultiTileIdentityReproducesInputExactly`
  （300² 2×2 网格，feed == span 宽 → 行距 == rect 宽，旧 bug 不触发）——
  与 SUMMARY「绿掩蔽」申报一致。
- **pad 路径揭穿面**：`testPreviewWithIdentityStubMakesBeforeEqualAfter`
  （192² 中央 crop → feed 256 pad-to-fit；旧代码以 rect 宽 192 作 tile
  缓冲行距，读 256 宽缓冲 = 行错位乱值 → identity 断言必红）——揭穿力
  亲验成立。修复在码：`blend(... tileWidth:)` 行距 = tile 实宽
  （EnhanceEngine :363-365）。
- 身份桩经真 writer→TIFF→reader 全 I/O 路径（非内存桩），量化容差
  2/65535 钉 uint16 域。

### 3. sidecar v8 additive（AC#1）

- 三字节面：v7 形 round-trip 逐字节 / nil 面 = v7 形仅版本位差（整串
  replace 断言「无其他字节移动」）/ 带 provenance round-trip 逐字节。
- **hash 隔离**：JSON 层 tamper provenance → `driftDetected` 恒 false
  （v3/v4/v7 metadata judgment 延续，fold 公式零 diff——sidecar diff 全
  additive 亲读）。
- **L013 命名纪律**：六字段 snake_case 冻结（`source_file`/`source_image_id`
  CodingKeys + `Set(record.keys)` 六键 total 断言）；记录零 hash 字段
  （UInt64 decimal-String 锁零新增面）；unknown operation raw = 整文档
  decode 失败（冻结值空间，DECISIONS §3 钉死）。

### 4. EnhanceCopyWriter + 导入孪生（AC#2/#3/#4）

- **O_EXCL**：POSIX `open(O_CREAT|O_EXCL)` + errno==EEXIST 续爬 + 非
  EEXIST typed + 9999 上限；**8 并发去重**（`Set(results).count == 8`）
  + Lumen 命名形（首份无序号 / `-N` N≥2）逐名断言。
- **容器规则矩阵 6 腿**：PNG16→PNG / TIFF16→TIFF / TIFF8→TIFF / JPEG8→
  TIFF / PNG8→TIFF / 合成字节（RAW 等价腿）→TIFF——盘上 `Depth == 16`
  断言 + 渐变 round-trip；失败清占位终态断言。
- **EXIF/orientation/GPS**：make/model 继承 + orientation 强制 1（烘焙
  契约）+ GPS 纬度 35.6812 保真——三腿键值级断言。
- **孪生零漂移**：`insertRow` 三调用点共享亲证（executeLink :424 /
  writeRow :562 / twin :626——folder 三 transport 均经前两者）+
  `@discardableResult` 行为零改；既有 ImportServiceTests 10 +
  ImportCompletionRegression 2 + ImportDropTests 7 全绿（suite 内亲点）。
- **真链 round-trip**：真 .lalb + 真 ImportService.importFile → images
  行（kind0 project-relative `Media/…`）+ 相册落位 + `.lra` decode
  round-trip provenance 逐字段 + pristine（空 history + driftDetected
  false）+ **原图字节级零触碰**（Data equality）+ 原 .lra 不产生 + 二跑
  落 `-2` 阶梯；Media/ 外 typed `adoptTargetOutsideMedia` 拒绝。
- **version_ref 零触碰（M4 消歧口径）**：原图链零增量（上两项断言）+
  VersionCoordinator/version 域文件零 diff（机检零命中）——双半边全过；
  副本自有单版本行 = sidecar→library 同步自然发生（§11，未触机制）。

### 5. worker 增强腿 + L065（AC#5/#6）

- **capability discovery**：`EnhancementSession` init 从模型描述发现
  （input_tile 优先 / output 首个 / edges 三级 / scale 比值）——「输出名
  假设不存在」修复亲读（金样测试为其揭穿面）；§4 静态资产消解（plan
  「LRU 4 形状」假设 → 实测静态 256 不可重整形 → supported 集内 plan +
  run 时 feed 验证 typed 拒绝）成立。
- **denoise 强度**：worker 侧 output/input 线性插值（0=identity/100=全
  输出，`AITileParameters.amount` 承载，upscale 恒 nil）——§6 在码。
- **L065 join 修复**：`_ = await runTask.value`（EnhanceDialogTests :139）
  + LESSONS L065 正本在案；取消链 = closeRequested(busy) → CancelFlag
  （NSLock Sendable box）→ engine checkpoint（每 tile 前）→ `.cancelled`
  → shouldClose → dismiss——`testCancelMidRunLandsCancelledAndClosesAfter`
  + `testEngineCancelSweepsInFlightTileFiles`（tmp 目录终态空断言）双绿。

### 6. EnhanceDialog UX 面（KD-5）

- before/after 中央 192² 双窗格 + 操作/模型 Picker + 强度滑杆 0-100 +
  下载行四态（notInstalled 下载按钮 / downloading 进度 / corrupt 重下载 /
  digestUnpublished「待发布」诚实面——`testReleaseModelWithoutDigest…`
  钉 x4plus+drunet 双 digestUnpublished）+ 进度条 + 取消/关闭一钮双语义
  （busy→取消运算 / idle→关闭）+ `.done` 网格文案。
- 预览 = 同引擎同模型单 tile（确定性一致，§10）——`testPreviewWith
  IdentityStub…` + `testCentralCropTakesTheClampedCenter` 钉死。
- **内存 pin = M-1（见下）**：机制 seam 在 engine（onInputConsumed 于
  output 分配前触发，顺序正确），但生产接线传 nil 且 engine callee 持有
  `input` 参数——释放面未闭合。

## minor M-1（挂账，不动码）——内存姿态两处口径差

1. **fp32 输入释放 pin 实际 inert**：engine 头注释与 §12 申报「onInput
   Consumed 后 provider 释放、循环只持 uint16（fp32 的 ~1/2）」——实际
   `EnhanceDialogModel.runFullCopy` 传 `onInputConsumed: nil`（:239），
   且 `run(input:)` 的 `input` 参数（struct 持数组引用）在函数帧内存活
   至返回，caller 置 nil 也无法释放——fp32 输入全程驻留（Debug 语义确
   定；Release 由编译器 last-use 决定，无语言级保证）。
2. **终段双缓冲共存**：归一段 `output`（RGB fp32）与 `rgba`（RGBA fp32）
   同时存活 → 真实峰值 ≈ 28 B/输出像素；§5 修正后的最大准入工况（400M
   输出，如 100MP@×2）≈ **11.2GB+**，为 §12 申报口径（6.4GB）的 ~1.75×
   ——MEMFAIL/风控触发线远早于申报值（粗算 >285M 输出即越 8G，约
   17MP@×4 / 71MP@×2）。

**不判 error 的依据**：零 AC 涉内存；测试域全小图（设计如此），MEMFAIL
门未触发；流水线化直写 TIFF 已是 §12/plan 风险节申报的 E3 后手（Maintenance
挂账在案）；对话框未接生产入口（M2-10-07 前 UI 不可达）。**处置建议**：
M2-10-07 双入口接线**之前**完成 ①§12/SUMMARY 峰值口径修正（同一编辑批次
纪律）②tile 直写流水线化或至少终段 in-place 归一（消除 RGB+RGBA 共存），
否则 100MP 级大图在 ×2 档即可能 OOM——与本项目「100MP 零延迟」Core Value
直接相关。本验收不动码（改 engine 生命周期属设计级变更，超小修半径）。

## observation 三件

- **O-1（flake 记账，第三轮形态）**：App 首轮 `--all` 红
  `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`
  （.lra 文件缺席，12.2s）= **在案 ANE 环境型 flake**（M2-10-01 执行批
  同用例同形态 + GOAL-STATE 备案；01 验收轮未复现）。隔离 11/0/0 + App
  全量 601/0/0 复绿（两轮：补跑 + 修复回归），本波 diff 零 SidecarV5/
  ANE 域。三波累计两红一绿，维持「环境型」归因；若 M2-10-07 波再现，
  建议另案挂账该用例的 decode-超时-紧邻写盘断言硬化。
- **O-2（账面滑差，登记即闭）**：SUMMARY 提交账 T4 行「BUNDLE-MAP 三行」
  与实际不符——BUNDLE-MAP +8 行落在 T1(+6)/T2(+1)/T3(+1)（行随测试提交
  走）。登记闭环本身无缺（Project.swift 4 命中 + BUNDLE-MAP 4 行 + grep
  13/5/8/10 逐位），纯账面归属表述滑差。
- **O-3（消账注记）**：M2-10-05 申报的 Library 缩略图时序 flake
  （O-1 两连击挂账）**本轮 --all 未复现**（Library 581/4/0 一轮过）——
  05 验收 O-1 的挂账建议维持（另案硬化），本波无新增。

## 判定汇总（AC 8/8）

| # | AC | 结果 |
|---|---|---|
| 1 | v8 三字节形断言 + provenance 不进 historyHash | ✅ SidecarV8Tests 5/0/0（round-trip 逐字节/位差/tamper 负测/冻结枚举 decode-fail） |
| 2 | reserve_copy 并发唯一 + N 递增 + 容器矩阵 + orientation 烘焙 + EXIF 键值 | ✅ EnhanceCopyTests（8 并发去重 + 矩阵 6 腿 + 盘上 16-bit + 清占位 + 三继承腿） |
| 3 | 导入链 round-trip（Media/ + 新 images 行 + `.lra` provenance 回读 + 相册落位） | ✅ 真链亲证（真 .lalb + 孪生 + 原图字节级零触碰 + `-2` 阶梯） |
| 4 | version_ref 零触碰（M4 消歧口径） | ✅ 原图链零增量断言 + version/VersionCoordinator 域零 diff 机检 |
| 5 | 分块：切分/权重和一/余数族内/进度单调 + 取消删半成品 + close-after | ✅ TileInferenceTests 13 + EnhanceDialogTests（engine sweep + close-after 终态 + L065 join） |
| 6 | 真模型 golden：64²→256² + tile 一致性 1/255（资源门 skip） | ✅ 激活态 3.352s 非 skip 亲点（真 worker + discovery 断言 + 两轮 ≤1/255） |
| 7 | 导出管线/MCP 零 diff；既有 importFolder/sidecar 测试零改动 | ✅ 双机检零命中 + Tests/ 仅四新建 + 05 的 27 worker 测试零 diff 全绿 |
| 8 | 资源门 + 登记闭环 + diff 边界 == 申报集 | ✅ 2926/16/0 对账 + 登记双命中逐位 + 18 文件对表零未申报源码 |

## 翻账

- REQUIREMENTS **M2AI-09 翻勾**（Delivered 注记：四块交付 + 真模型 golden
  激活态 + 2926/16/0 对账；注记三项如实登记——容器规则收窄 §1、双入口
  接线归 M2-10-07、内存流水线化挂 Maintenance）。
- **M2AI-01 残留半边追记**：AI 出片增强半边已 Delivered（M2AI-09 翻勾，
  M2-10-06 验收）；剩余 = 设置 UI 面（M2-10-07），本条维持未勾。
- M2AI-02..08/10 无本波触发的回退/追记（嵌入/检索/打标/描述/凭据/MCP/
  worker 隔离面零 diff 亲证；05 的 27 测试零 diff）。

## 交接确认

- SUMMARY 交接节四项核对：①`EnhanceDialogModel` seams（frameProvider/
  modelFacts/tileExecutor/EnhanceContext）全注入形态亲读——M2-10-07 接线
  即换生产闭包；②`CompatRecord.resetAll()` 按钮 API 在位（05 交接延续）；
  ③下载行四态已接 `ModelAssetStore`（`.notInstalled/.downloading/.corrupt/
  .digestUnpublished`）——release 上架后零 UI 改动；④「衍生自」徽标
  join 键 = `source_image_id`（provenance 在码，OQ-4-C 后手挂 07 走查）。
- **M-1 随交接**：M2-10-07 接线前先清内存口径 + 流水线化（见 M-1 处置
  建议）。

**验收批改动 = 小修一例 `b766cf5`（cosmetic 重复赋值行删除，回归
EnhanceDialogTests 10/0/0 + App 601/0/0）；本文件 + 翻账（REQUIREMENTS）+
GOAL-STATE 增量 = 单 docs 提交。未 push。**
