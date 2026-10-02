# M2-9-03 ACCEPTANCE — 命名/元数据/ICC 消费接线（wave 2b）

**验收:** M2-9-03 独立验收 subagent（零共享上下文，实测核验不轻信）
**Date:** 2026-10-03 深夜（夜间全自动授权在案；`[gsd]` auto=true/paused=false 全程未动）
**输入:** PLAN（checker E1/E2/E3/E6 回注版）× SUMMARY × DECISIONS × LESSONS L054/L055 × M2-9-02-ACCEPTANCE（基线 2634/16/0）× GOAL-STATE 续接点 × 全仓源码/测试实读 + 机检亲跑
**对象提交链:** `cfbe385`(T1 命名腿) → `6a7515a`(T2 元数据腿) → `fe338d7`(T3 ICC+闸门) → `d2e80d2`(越界 fix) → `262f98e`(收口)

## 结论

# PASS / 0 error + 1 minor + 2 observation

Plan 八条 AC 全部独立复核通过；全套独立复跑**单轮干净绿 `TOTAL|2662/16/0|909s EXIT=0`**（2634+28 精确对账，skip 16 保全）。执行波跑 1 两事件（App host 瞬态 crash + McpEditingToolsetTests 红）本轮零复现——App 481/0/0 含 McpEditingToolsetTests 20/0（packet 契约测试亲点 passed）。L055 对策按方亲跑：崩溃签名全 log 扫描零命中 + 七 bundle 末条 `Executed` 行均 = All tests 总计且与 BUNDLE 行逐值一致。1 minor = BUNDLE-MAP 三行 method 数全错（02 波 M-1 同族，验收批勘误）。

## 一、全套独立复跑（单轮全记录）

`caffeinate -dis xcodebuild build-for-testing`（-workspace，产物七 .xctest 齐）→ `caffeinate -dis Scripts/test-direct.sh --all`：

| Bundle | M2-9-02 终态 | 本轮 | Δ | 判定 |
|---|---|---|---|---|
| IOP | 467/1/0 | 467/1/0（peak 6898MB） | 0 | 零漂移 ✓ |
| IOPParity | 362/3/0 | 362/3/0（5983MB） | 0 | ✓ |
| Layers | 298/3/0 | 298/3/0（1053MB） | 0 | ✓ |
| Library | 436/4/0 | **437/4/0**（312MB） | +1 | = XMPExportMatrixTests 默认档新断言 ✓ |
| Sessions | 279/4/0 | 279/4/0（1645MB） | 0 | ✓ |
| Export | 311/1/0 | **338/1/0**（5922MB） | +27 | = 11(Naming)+8(Metadata)+8(IccEmbed) ✓ |
| App | 481/0/0 | 481/0/0（1342MB） | 0 | ✓（MCP 契约测试绿） |
| **TOTAL** | **2634/16/0** | **2662/16/0** | **+28** | **与推算精确对账** ✓ |

- peakRSS 全 bundle < 8192MB 门（最大 IOP 6898），零 MEMFAIL；909s。
- 新测试类逐类点名（本轮 /tmp 亲核）：ExportNamingE2ETests **11 passed**、ExportEncoderMetadataTests **8 passed**、ExportIccEmbedTests **8 passed**、XMPExportMatrixTests **6 passed**（Library）——与申报逐值一致。
- 执行波偏差 +7（21→28，DECISIONS §10）经方法清单逐一清点认可（E1 案 A 座位面逐容器钉 + AC 展开独立方法）。

## 二、逐 commit 边界审计

| commit | 申报 | 实测 `--stat` | 判定 |
|---|---|---|---|
| `cfbe385` T1 | Queue/Renderer + NamingE2ETests + Project.swift + BUNDLE-MAP | 恰五文件（+795/−20） | ✓ |
| `6a7515a` T2 | ChainBuilder/Encoder/Queue/Renderer/ImageIOEncoders + MetadataTests + MatrixTests + Project.swift + BUNDLE-MAP | 恰九文件（+554/−44） | ✓ |
| `fe338d7` T3 | Encoder(+240=ICCStrip)/Queue/Recipe/Renderer + IccEmbedTests + Project.swift + BUNDLE-MAP | 恰七文件（+637/−8） | ✓ |
| `d2e80d2` 越界 | App/MCP/EditingToolset.swift 单文件 | 恰一文件（+10/−2） | ✓（申报在案） |
| `262f98e` 收口 | SUMMARY/DECISIONS/LESSONS/GOAL-STATE | 恰四文档 | ✓ |

波内 `840eecf..262f98e` = 17 文件 = **front-matter 12 文件 + 越界 1（申报）+ docs 4**；模型面 `ExportMetadataPolicy.swift` 来自 01 波（`3b90709`），本波零触碰——front-matter 无破。

## 三、红线零 diff 机检（亲跑）

| 红线 | 机检 | 判定 |
|---|---|---|
| `WebPEncoder.swift` / `ExportQuantizer.swift` / `ExportQueueContract.swift` | `git diff 840eecf..HEAD` 各 = 0 行 | ✓ |
| legacy 三测试族（RendererE2E/PhaseE2E/NamerTests） | 各 = 0 行 | ✓ |
| `ImageIOEncoders.swift` 编码核心面 | **恰 6 hunk**：hunk1 = ImageIOEncodeCore 纯 additive 装配腿（`processedEXIF`/`mountMetadata`/剥离常量，+77）；hunk2-6 = 五 encoder 各 3 行 `sourceEXIF` 块 → 1 行 `mountMetadata` 调用点；**makeCGImage 签名 / writeAtomically / 质量-DPI 映射行仅作上下文，零改动**（E1 案 A 属实） | ✓ |
| `ExportQueue.swift` 引擎体 | **恰 7 hunk 全载体**（Job 三字段 / enqueue 三默认参 / sequence 入队盖章 / Job init 透传 / 占用枚举 landingDirectory join / `$jobNamingCarrier` 嵌套 wrapper / encodeLeg 变体政策透传）；pump/cancel/retry/generation/markState/finish **零 hunk**（AC7） | ✓ |

注（observation O-1）：SUMMARY/DECISIONS §11 的机检叙述有失实——「ExportChainBuilder minus 2 行均为注释行替换」实测 **minus 1 行且为 `mountXMP` 签名行**（default 参 `policy: = .standard` 增改）；「ExportRecipe minus 1 行 = validate 注释行」属实。gate 纯 additive 的实质主张成立（默认参零调用点破坏、gate 臂纯新增，逐行亲核），仅 hunk 记账文字错位——以本报告为勘误正本，不改执行波文档。

## 四、越界审计 `d2e80d2`（MCP export_image opt-in XMP）

**判定：成立且必要，改动面最小，接受并登记晨审项。**

1. **波及真实性**：`mountXMP` 默认档 gate = `mode == .standard && includeXMP && includeEditingHistory`（ChainBuilder diff 亲核）——OQ-6 收窄后默认 `.standard` 必返 `.skippedByPolicy`，packet 不嵌。
2. **契约钉死**：`McpEditingToolsetTests.testExportImageLandsInOutputWithXMPAndPathNote`（**零修改**）字节断言产物含 `ns.adobe.com/xap/1.0/`（XMP packet 在盘）——不 opt-in 该工具契约必红（执行波跑 1 实证）。工具行为规格「export lands WITH XMP」= 互操作契约非 legacy 面。
3. **最小性**：单调用点 `variant.metadataPolicy = ExportMetadataPolicy(editingHistory: true)`，测试零改动（契约保真），GUI 导出面不 opt-in（收窄照旧，装配归 04）。晨审可推翻（3a1ecb8 先例族），GOAL-STATE 登记在案。

## 五、重点抽查（读码 + 断言体亲读）

1. **E6 兑现（checker 回注正主）**：`renderStage` sizing 腿直切 `resolveExportResolution` + `StageOutput.dpi = Double(resolution.dpi)`（diff 亲读）；golden `testCappedPhysicalExportLandsCorrectedDPI` 数学自洽（physical 10×20/3in@300dpi → 3000×2000px 框，源 3072×2048 aspect 1.5 同框，cap 2000 → 2000×1333，DPI 修正 = 300×2000/3000 = **200±0.5**，经 `kCGImagePropertyDPIWidth/Height` readback 断言）本轮亲跑 passed。legacy 零漂移论证亲核成立：`applyMaximumEdgeLimit` cap=0 直通 + `clampedDpi`（validate 保证 dpi∈1...2400 → clamp no-op）≡ `effectiveSizing.dpi`；`landingDirectory(base, nil) ≡ base` → legacy 命名路径 directory 实参恒等。
2. **E1 案 A / OMIT 剥离语义**：`ExportICCStrip` 读码——JPEG marker walk 丢 APP2 `ICC_PROFILE\0`（SOS 后熵流 verbatim）；PNG 走 chunk 流丢 iCCP（总长守恒校验）；TIFF tag 34675 IFD 原位左移（长度不变 → 表后外部 offset 全有效）+ vacated 尾槽/旧 next-IFD 位清零 + **孤儿 payload 按 entry (type,count) 定界清零**。`stripped == original` → typed `.failed("no ICC payload")`（sRGB 零嵌入 host fact 诚实降解）。测试断言 = `suffixFromSOS` 逐字节恒等（JPEG）/ IDAT 不动（PNG）/ TIFF EXIF round-trip 走查 / 不可达档 typed / 二次剥离 degraded typed——L054「剥离确定性」纪律落地。
3. **OQ-6 兑现**：`processedEXIF` guard `mode == .standard && includeExif`；剥离 = BodySerialNumber 精确 + Exif-dict `GPS` 前缀 + `{GPS}` 构造性缺席（mountMetadata 只挂 Exif dict）；NONE 短路（无 Exif dict + 无 Software）；默认档 `mountXMP` → `.skippedByPolicy`（三 bool 合取，五臂穷举在案）。matrix 白名单实测 13 处显式 `editingHistoryMounted` 锚点 + 新增 `testDefaultPolicyKeepsPacketUnmounted`（JPEG byte-scan 无 `x:xmpmeta` + PNG hostRating nil + 默认/.none 双 outcome 断言）——DECISIONS §9 case 清单逐条对上。NONE 档断言钉 round-trip 内容缺席而非 dict 缺席（host trio 诚实登记属实）。
4. **Software 座位**：`mountMetadata` 走 `{TIFF}` dict `kCGImagePropertyTIFFSoftware`，座位已占即跳（editorSignature 预留面胜）；JPEG 断言走 **byte-scan**（readback 不回显 {TIFF} 的处理 = 诚实绕行非掩盖，DECISIONS §1 探针链与实现一致）。
5. **命名腿**：step 9 逐 job 求值（decoded.capture 8 字段 + `namingDocument?.rating` 盘上真相〔override 模式同读〕+ carrier sequence）；queue 入队盖章 `imageIndex + 1`（`stampedNaming` 重建、载体自带 sequence 不消费 = 批内序单真相，同图多 variant 共享）；FAIL 档双级钉——renderer 级 typed `BaseNameOccupiedError` + 目标目录零文件，queue 级经既有 finish 映射 `.encodeFailed(String)`（message 含名，Contract 零 diff 不扩面）；子目录渲染前 typed `createDirectory` + queue 占用枚举经同一条 `landingDirectory` join（单源）。`testFailPolicyFailsQueueJobWithoutWriting` 断言 1 done + 1 failed + 单产物落盘，读码真。
6. **peak 闸门（E3 additive）**：`ExportVariant.validate` 仅 additive；测试 0/−1/nan/+inf/−inf 五值 typed 拒绝（message 含 "peak"）+ peak=100 过 + `ExportVariant(format:)`（drtOutput nil）validate no-throw——nil 不触发实证。

## 六、AC 逐条（8/8）

| # | AC | 独立核验 | 判定 |
|---|---|---|---|
| 1 | 模板命名 E2E 全族 + 修正后 DPI golden | 11 测试亲点 11 passed；golden 数学重算 + readback 断言亲读 | ✓ |
| 2 | legacy 命名面零修改全绿 | 三测试族 0 diff 亲跑 + 基线 bundle 全零漂移 + `testNilNamingIgnoresCollisionPolicy` | ✓ |
| 3 | EXIF Software/NONE/剥离逐键 | MetadataTests 8/0 亲点 + 五条测试体逐行读核 | ✓ |
| 4 | XMP 默认缺席 + editingHistory 回归 + 白名单改造 | MatrixTests 6/0 亲点 + 13 显式锚点清点 + §9 清单对账 | ✓ |
| 5 | EMBED/OMIT 两态 + peak 闸门 | IccEmbedTests 8/0 亲点 + strip 算法读码 + 五坏值拒绝测试体 | ✓ |
| 6 | WebPEncoder/Quantizer/Contract 零 diff + ImageIOEncoders 核心面零 diff | §三表机检亲跑（恰 6 hunk 逐 hunk 审） | ✓ |
| 7 | ExportQueue 引擎体零 diff | 恰 7 hunk 全载体逐 hunk 审 | ✓ |
| 8 | 全套 0 fail + 双登记闭环 | 2662/16/0 单轮干净；Project.swift 恰 3 行；BUNDLE-MAP 勘误后行值=method 终态 | ✓（M-1 勘误） |

## 七、minor 与 observation

- **M-1（minor，已修）**：BUNDLE-MAP M2-9-03 三增行 method 数**三行全错**（行 10/9/7 vs 文件 `func test` 终态 **11/8/8**；SUMMARY 双登记节又把行值误报为 11/9/7——连「申报值」与「文件值」双重失真）。行和勘误后 27+1 = 28 与全套增量精确对账。验收批直接勘误（11/8/8 + 勘误注），doc-only 零回归面。02 波 M-1 同族——执行波行值登记流程仍是缺陷源。
- **O-1（observation）**：SUMMARY/DECISIONS §11 红线机检叙述错位（ChainBuilder「minus 2 注释行」实为 minus 1 签名行）——实质主张（gate additive）成立，勘误见 §三注；验收判读以亲跑机检为准。
- **O-2（observation）**：DECISIONS §6 称「Request 显式字段 > carrier（?? 链）」，实现却分叉——naming/subfolder 为 `request ?? carrier`、collisionPolicy 为 `carrier ?? request`（carrier 优先）。实际无歧义面（queue 面从不设 Request naming 族、直接渲染面无 carrier），但 04 装配若双设需留意方向不对称，建议彼时统一。

## 八、翻账与提交

- **REQUIREMENTS**：M2EXP-01/02/03/04 各追记「消费半边 Delivered（M2-9-03，验收本报告）」——**不翻勾**（App 装配/面板 UI 归 M2-9-04，条目完整交付后随 phase 收口勾选）；ALCE-01..07 本 plan 无可支撑增量（EXR/UltraHDR = V2），不动。
- **BUNDLE-MAP**：M-1 勘误（10/9/7 → 11/8/8 + 勘误注）。
- **GOAL-STATE**：验收续接点入账（含 `d2e80d2` 越界晨审项验收判定）。
- **本验收批提交**：单 docs commit（本报告 + REQUIREMENTS 追记 ×4 + BUNDLE-MAP 勘误 + GOAL-STATE）。
- **不 push。**

## 九、下一步（交接 orchestrator）

C 档第 2 停 = M2-9-03 plan 闭环汇报（本报告为输入）→ 用户确认 → **M2-9-04**（App 装配点：检查器 Export 页 + `enqueue(naming:collisionPolicy:subfolder:)` 接线 + `exifSoftware` 载体缺口〔SUMMARY 交接：enqueue 增参 + carrier 递缝或 variant 新字段，front-matter 彼时登记〕+ OMIT 不可达档 UI 禁用/说明 + 「含编辑摘要」开关显式传参）。LESSONS L055 的 test-direct.sh 崩溃假绿脚本修复另案报备（本波不改脚本，front-matter 外）。
