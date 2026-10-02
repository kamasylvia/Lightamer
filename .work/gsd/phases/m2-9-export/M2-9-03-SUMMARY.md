# M2-9-03 SUMMARY — 命名/元数据/ICC 消费接线（wave 2b）

**Status:** COMPLETE（2026-10-03 夜间；执行 = ZCode subagent worker，
`[gsd]` `paused=false / auto=true` 全程未动——每任务边界复查）
**提交链:** `cfbe385`(T1 命名腿) → `6a7515a`(T2 元数据腿) → `fe338d7`(T3
ICC+闸门) → `d2e80d2`(越界 fix：MCP export 显式 opt-in XMP packet，申报见
偏差 §7 + DECISIONS §13)。**不 push。**
**对账底稿:** 同目录 `M2-9-03-DECISIONS.md`（Software 座位探针链 / 剥离键
实测 / skippedByPolicy 穷举面 / iptc 边界 / Alcedo 差异注记 / queue 递缝 /
E6 零漂移论证 / ICC OMIT host facts / matrix 白名单 case 清单）。

## 数字对账表

| 项 | 基线（M2-9-02 终态） | 本波终态 | Δ |
|---|---|---|---|
| Export bundle | 311/1/0 | **338/1/0**（199s，peakRSS 6988MB < 8G 门） | +27（11+8+8） |
| Library bundle（matrix 类所在） | 436/4/0 | **437/4/0**（+1 = XMPExportMatrixTests 默认档新断言；bundle 全量绿） | +1 |
| 全套 | 2634/16/0 | **`TOTAL|2662/16/0|900s EXIT=0`**（全套 --all 终跑单轮干净绿；七 bundle 逐行 = 467/362/298/437/279/338/481，六未触 bundle 零漂移） | +28 |

- **测试增量 28 vs front-matter 预估 21**（+7，偏差入 DECISIONS §10）：
  E1 案 A 座位/探针面要求逐容器钉 + AC 展开为独立方法（复合方法组织口径
  同 01/02 波）。
- 每任务边界 `[gsd]` 开关复查 = 全程 `paused=false / auto=true` 无变更。
- 定向轮逐次：T1 `ExportNamingE2ETests 11/0/0`；T2
  `ExportEncoderMetadataTests 8/0/0` + `XMPExportMatrixTests 6/0/0`
  （Library bundle，白名单改造后）；T3 `ExportIccEmbedTests 8/0/0`；
  收尾 `McpEditingToolsetTests 20/0/0`（越界 fix 后）。

## 任务逐条（commit × 验收）

| 任务 | commit | 交付 | AC 覆盖 |
|---|---|---|---|
| T1 | `cfbe385` | `ExportNamingRequest` + Request 三载体（naming/collisionPolicy/subfolder，默认 = legacy 字节冻结）+ step 9 分派（模板逐 job 求值：decoded.capture 8 字段 + 盘上 rating（override 模式同读）+ sequence；空渲染 fallback；tag 拼接面不变）+ `landingDirectory` 单源 join（子目录渲染前 typed 创建）+ queue 批载体（sequence 入队盖章 = 批内序，`$jobNamingCarrier` TaskLocal 递缝）+ **E6**：sizing 腿直切 `resolveExportResolution`，`StageOutput.dpi = result.dpi` + 11 测试 | AC1/2 |
| T2 | `6a7515a` | `ExportEncodeRequest` 三载体 + `ImageIOEncodeCore.mountMetadata` 单点装配腿（五 encoder 换调用点；**编码核心面零 hunk**——E1 案 A）+ OQ-6 剥离（BodySerialNumber + Exif-dict GPS 前缀 + `{GPS}` 构造性缺席；NONE 短路）+ EXIF Software（**{TIFF} dict 座位**——唯一可序列化座位，editorSignature 预留面优先）+ `mountXMP` policy gate（`.skippedByPolicy` 新臂 + 三 bool 合取）+ encodeStage policy 载体 + XMPExportMatrixTests 白名单改造（显式 `editingHistory:true` 锚定原 packet 面 + 新默认档断言）+ 8+1 测试 | AC3/4 |
| T3 | `fe338d7` | `ExportICCStrip`（post-encode 剥离：JPEG APP2 / PNG iCCP / TIFF tag 34675 原位压缩 + payload 清零；HEIC/AVIF/WebP typed 不可达档）+ encodeStage/render/queue `embedICC` 消费 + `ExportVariant.validate` drtOutput peak 闸门（finite 正数 typed 拒绝；nil 不触发——E3 validate-additive）+ 8 测试 | AC5/6 |
| — | `d2e80d2` | 越界 fix（App/MCP/EditingToolset.swift 单文件）：MCP export_image 显式 opt-in XMP packet（工具互操作契约钉 packet——OQ-6 默认收窄波及后唯一红灯，全套跑 1 抓出） | 行为变更波及面收口 |
| T4 | 本文 + DECISIONS + GOAL-STATE | 全套终跑 + 对账 + 机检记录 | AC7/8 |

## 红线机检（AC6/7，git diff 840eecf..fe338d7 逐 hunk）

- `WebPEncoder.swift` / `ExportQuantizer.swift` / `ExportQueueContract.swift`
  **零 diff**；legacy 冻结测试族（ExportRendererE2ETests /
  ExportPhaseE2ETests / ExportNamerTests）**零修改全绿**（AC2）。
- `ImageIOEncoders.swift` 恰 6 hunk：1 additive 装配腿（mountMetadata/
  processedEXIF，+77 行）+ 5 调用点换写（3 行 sourceEXIF 块 → 1 行
  mountMetadata）；**makeCGImage 签名 / writeAtomically / 质量-DPI 映射零
  hunk**（编码核心面冻结，E1 案 A）。
- `ExportQueue.swift` 7 hunk 全载体（Job 字段/enqueue 增参+盖章/execute
  landing+carrier 嵌套/encodeLeg 变体面）；pump/cancel/retry/generation/
  markState/markTerminal/finish/finishCancelled **零 hunk**（AC7）。
- `ExportChainBuilder.swift` minus 2 行均为注释行替换（gate 纯 additive）；
  `ExportRecipe.swift` minus 1 行 = validate 注释行（ExportFormatSpec/
  ExportColorSpace 枚举体零 diff——E3）。
- 波内 diff 恰 12 文件 == front-matter files_modified（AC8 边界 == 登记）。

## 双登记闭环（AC8）

- `Project.swift`：`ExportNamingE2ETests` / `ExportEncoderMetadataTests` /
  `ExportIccEmbedTests` → `LightamerTestsExport`（3 行）。
- `M2-4-0-BUNDLE-MAP.txt`：同批三行（EXPORT 11/9/7）+ M2-9-03 增行记录注
  （运行期总数基线上移至 2662；对账以各行 method 数为准）。
- 新测试文件落盘后 `tuist generate`（L041 顺序纪律，每 T 一轮）。

## 偏差与发现（全部入 DECISIONS，逐条有据）

1. **Software 座位**（DECISIONS §1）：D-5 的 `kCGImagePropertyExifDictionary`
   座位全容器被 ImageIO 丢弃——唯一可序列化座位 = `{TIFF}` dict Software
   tag（JPEG APP1 字节 / TIFF tag / HEIC·AVIF 元数据 / PNG XMP CreatorTool
   bridge）；JPEG readback 不回显 `{TIFF}`（reader 面局限）→ 断言走
   byte-scan。裸 Software dict 还会被 JPEG writer 整体丢弃（round-trip
   dict 在场才序列化，探针钉）。
2. **剥离键实测**（§2）：Sony ARW 的 round-trip `{Exif}` 38 键无
   serial/GPS/MakerNote——剥离清单 = EXIF 标准位防御集（BodySerialNumber
   精确 + GPS 前缀 + `{GPS}` 构造性缺席）。
3. **sRGB 零嵌入**（§8）：JPEG/PNG writer 对已知 sRGB 空间不写 profile
   payload（JFIF/sRGB-chunk 推断）——OMIT 剥离可观察面 = AdobeRGB+ 目标；
   sRGB 档 typed "no ICC payload" 降解。untagged JPEG/TIFF 的 profileName
   推断回落 sRGB（PNG 才真 nil）。
4. **像素完整性 = 剥离确定性**：跨 ICC 上下文 color-managed decode 不可比
   ——断言改 `stripped == strip(embedded)` 逐字节 + JPEG SOS 后熵流恒等。
5. **TIFF 孤儿清零**：tag 34675 删除后 payload block 按 entry (type,count)
   定界清零（不留孤儿数据在盘）；IFD 原位压缩长度稳定 → 其余 offset 全
   有效（EXIF round-trip 走查钉）。
6. **queue FAIL 包装**：`BaseNameOccupiedError` 经 queue 既有 finish 映射
   成 `.encodeFailed(String)`（Contract 零 diff 红线不扩面）；renderer 级
   typed 直抛，测试双级钉。
7. **host trio**：ImageIO 对 JPEG 产物恒发最小 `{Exif}`（ColorSpace/
   PixelX/Y）——NONE 档断言钉 round-trip 内容缺席而非 dict 缺席。
8. **全套跑 1 两事件**（收尾轮，均闭环）：① App host 于
   `HistoryRowJumpTests.testFiveHundredItemChainReloadsByteFaithfulAndUndoesToEnd`
   中途 **crash（"command terminated abnormally"）**——该 --all 轮 App 行
   误记 15/0/0（test-direct.sh 解析器取末条类 suite 行 = 假绿缺陷，脚本
   修复另案）；**隔离复跑 ×2 零复现**（481/0/1 → fix 后 481/0/0），判瞬态
   flake，非本波引入（本波零 App 源码触碰——除 §7 的 MCP stamp）。② 同轮
   抓出 `McpEditingToolsetTests.testExportImageLandsInOutputWithXMPAndPathNote`
   红 = OQ-6 有意行为变更波及 MCP 互操作面（该工具契约钉 packet）→
   `d2e80d2` 显式 opt-in（越界一文件，晨审可推翻，01 波 3a1ecb8 先例）；
   复跑干净轮全套 **2662/16/0 EXIT=0**。**test-direct.sh 解析器缺陷记
   LESSONS L055 候选**（crash 后取末条类行当 bundle 计数；本波不改脚本——
   front-matter 外，报备 orchestrator）。

## 交接（M2-9-04 消费缝）

- **装配点**：检查器 Export 页 → `ExportQueue.enqueue(naming:
  collisionPolicy: subfolder:)`（batch-wide，sequence 自动盖章）+
  `ExportVariant.drtOutput/metadataPolicy/embedICC`（02/03 已全消费）+
  `ExportRenderer.Request` 直接渲染面同权。
- **exifSoftware 载体缺口**（DECISIONS §11）：queue 路径暂无 App→encoder
  的 Software 载体（Contract 冻结 + variant 无字段——本 plan front-matter
  不许加）→ 04 需 enqueue 增参 + carrier 递缝（jobDrtTail 同款）或 variant
  新字段（彼时 front-matter 登记）接入 `Lightamer <CFBundleShortVersionString>`。
- **OMIT 不可达档 UI**：HEIC/AVIF/WebP 的 embedICC=false 禁用/说明归 04
  （`.skippedUnsupportedFormat` typed 面已备）。
- **mountXMP 默认档**：检查器若有「含编辑摘要」开关 → `includeEditingHistory`
  显式传参（默认关 = 现行为）。

## LESSONS

- **L054（新沉淀）**：ImageIO 写入面 ≠ readback 面——seat/payload 断言先
  ObjC 探针字节取证（`strings`/marker 走查），readback 断言会假阴性
  （JPEG `{TIFF}` 不回显）也会假阳性（profileName inference 回落 sRGB）；
  已知空间（sRGB）零 payload 嵌入是 inference 面的成因。
