---
phase: 11
slug: export-pipeline
status: validated
nyquist_compliant: true
created: 2026-09-26
validated: 2026-09-26
---

# Phase 11 — Validation（签核：SC#1-5 三列证据 + Per-Task Map + Manual-Only 汇总）

> 体例对齐 09-VALIDATION（frontmatter/Checklist）+ 07/08 同族。
> **翻账只认证据**：SC 表逐条「一手证据 + 测试锚 + GUI 实证」三列；无证据 ✅ = 违规。
> **checker M3 口径**：SC#2 行的「lower priority」证据**显式引用 API 事实修正**
> （`MTLCommandQueue` 无公开 priority API，SDK 头实证 RESEARCH §4.4）→ 落地 =
> 独立队列 + 并发 1 + Utility QoS + `yieldsToEditor` 接口位。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden round-trip / 直启宿主 / 内存 footprint 采样 / Release 直启计时） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启，零弹窗；11-05 起判据 = 结果行而非宿主退出态） |
| **Full suite（终轮）** | touch Tests + `build-for-testing` 重编复跑 = **1258 tests / 6 skip / 0 fail**（449.8s，2026-09-26 10:0x） |
| **基线演变** | Phase 10（=08 执行序）末 **1133** → 11-01 +54（1187）→ 11-02 +33（1220）→ 11-03 +15（1235）→ 11-04 +13（1248）→ 11-05 +10（**1258**；其中 ExportPhaseE2ETests 3 + ExportTargetsTests 4 + ExportPerfProbeTests 2 + ExportEncoderGoldenTests parity +1） |
| **11-04 收尾轮 1 fail 处置** | `testYiyinFourStateMatrixAndBorderedRoundTrip` byte-exact 断言过敏（GPU 非确定，11-04 法证）→ 11-05 T0 稳定化为像素容差 1/255 + sanity 错位红断言（`9439b59`），稳定后三轮全绿 + 终轮 0 fail |

---

## SC#1-5 对照表（ROADMAP §Phase 11 契约，三列证据）

| SC | 判据 | 一手证据（文件/决策） | 测试锚（类/用例） | GUI 实证（FINDINGS/走查节） | 判定 |
|---|---|---|---|---|---|
| **SC#1** | 六格式全导出正确：JPEG(quality)/PNG(8/16)/TIFF(8/16/32f+压缩)/HEIC(quality,10-bit)/WebP(libwebp,有损无损)/AVIF(native 27, 8/10/12) | `LightamerCore/Sources/Export/`：`ExportEncoder.swift`（协议+注册表+色彩空间映射）+ `ImageIOEncoders.swift`（五原生）+ `WebPEncoder.swift`（libwebp 唯一 SPM 依赖，D-11-CONTEXT-1 native AVIF）+ `ExportQuantizer.swift`（三域量化 D-11-CONTEXT-7）+ `ExportRecipe.swift`（per-format 参数面，非法位深类型级不可表达） | `ExportEncoderGoldenTests` 17（逐位/已知点 ±2/255/奇数 33×17/DPI/ICC 名/UTI 写能力双向锚/32f 1-ULP）+ `WebPEncoderTests` 5（lossless 逐位 + RIFF 结构锚 OQ-11-5）+ `ExportQuantizerTests` 12 + `ExportPhaseE2ETests.testOneQueueAction…`（落盘终判：HEIC depth10/AVIF depth10/**AVIF 12→10 R1 降级锚**/PNG16 depth16/TIFF32f depth32/XMP 全缺席 R5） | 11-04 走查 #5/#6c：导出面板格式/位深/TIFF 压缩/WebP lossless/色彩空间全套内联编辑（截图 06/06c/07/08）；走查 #11 落盘 `WALKTEST.jpg` | ✅ |
| **SC#2** | 队列后台执行含进度/取消/失败重试；不阻塞编辑（独立 MTLCommandQueue、**更低优先级**、有界并发） | `ExportQueue.swift` actor（generation cancel/`cancel(jobID)` 三 gate/pump FIFO/并发 1 常量/`Task.detached(priority: .utility)`/两层进度快照/retry 显式）+ `MetalContext.exportCommandQueue`（NEW property）+ `@TaskLocal routesToExportQueue` 单点路由 + `ExportQueueContract.yieldsToEditor` 接口位。**API 事实修正（checker M3，RESEARCH §4.4 SDK 头实证）：`MTLCommandQueue.h` 无公开 priority API（`MTLIOPriority` 仅 IOCommandQueue）→「lower priority」字面不可实现；落地 = 独立队列 + 并发 1 + Utility QoS + `yieldsToEditor` 接口位（Phase 15 评估）——裁决意图（不阻塞编辑）不变** | `ExportQueueTests` 13（①FIFO ②cancel(pending) ③cancel(in-flight) 零落盘 ④cancelAll 代际闸+进度窗重置 ⑤retry 队尾+守恒 ⑥N×M 计数 ⑦**并发=1 探针** ⑧失败不毒化 ⑨新代收单 ⑩不等时长 done/total + retry 拒绝 + dequeue 占用 + default provider）+ `ExportPipeTests` 队列身份 3（`!==` 编辑队列/TaskLocal 三态/detached 不继承反向锚） | 11-04 走查 #10：「开始导出 → 0/1 渲染中 → 1/1」两层进度实时；#12 导出运行中 GUI 保持响应；#14 取消/重试按钮响应由单测 ②③⑤ 全语义覆盖（D8） | ✅ |
| **SC#3** | 多规格同导：一源 → 多尺寸/格式/水印组合，一次队列动作 | `ExportQueue.enqueue`（N images × M variants → N×M jobs 单调用）+ `ExportRecipe.resolvedOutputTags`（D-11-CONTEXT-4 tag 派生）+ `ExportNamer`（`<stem>[_<tag>].<ext>` + `-1/-2` 递增 + 大小写不敏感占用）+ `ExportState.enqueueExport`（tag 派生消费点 + F-11-04-1 拼写容差 targets） | `ExportQueueTests` ⑥（2×2=4 jobs 计数+variant 序）+ `ExportPhaseE2ETests` ①（**1 源×8 变体一次动作，落盘名集合逐文件对照** + ② 同目录二导 `-1` 递增原文件字节不动）+ `ExportNamerTests` 16 + `ExportTargetsTests` 4 | 11-04 走查 #5/#6：添加变体 → #1/#2 双 variant 内联编辑 → 一次入队；#15 多图 N×M GUI 入队由单测 ⑥ 钉（单 fixture 限制） | ✅ |
| **SC#4** | yiyin 印框/水印 = 导出管线最后一步（与 Phase 10 面板共享配置）；输出色彩空间五选 + 嵌入 ICC | `ExportRenderer` yiyin 注入缝（`ExportYiyinInjector`，Core 零 IOP 依赖 D-03）+ App `ExportState.makeYiyinInjector`（生产注入器 = coordinator 语义镜像，08-3 T3 义务闭环）+ `ColorOutModule` 五色域（ColorSync 精确路径 + display/linear 双味 D-11-03-D4）+ `ExportColorSpaceMapper` 单表 | `ExportRendererE2ETests` yiyin 段 7（双尺寸归一化布局 20+ 字段/4 态矩阵像素容差/有印框 round-trip）+ `ExportPhaseE2ETests` ③（**真队列**有印框全链 渲染→出口→编码→解码 band+白字存活）+ `ExportPipeTests` 五色域中性恒中性 + sRGB 0.5→187-188 已知点 + ICC 名逐格式 golden | 11-04 走查 #5（壹印开关与面板共享 `YiyinExportSettings` 值类型，OQ-11-6）；08-3 T5 GUI ΔR（印框 31.15%/水印行 26.29%）= 同一配置的编辑器面实证 | ✅ |
| **SC#5** | 导出后动作（运行 shell 脚本、Finder 打开文件夹）执行；文件落 Session/Output/ | `PostExportActions.swift`（脚本路径制 bookmark + `Process` 直 exec 不经 shell 解释 + `NSWorkspace.activateFileViewerSelecting`）+ Core `ExportQueue.setCompletionHook`（per-job `.done` 且当代触发，OQ-11-7）+ `SessionLayout.outputDirectory(for:)`（09-1 移交常量消费）+ `ExportFileWriter` | 队列 completion hook 语义 = `ExportQueueTests` ①③④⑤（仅 done settle）；**注入面自查**（11-04 SUMMARY 实录）：`$(){touch}` 反引号分号路径 → `$1` 逐字 110 字节 + `/tmp/INJECTED` 哨兵未创建 = 零 shell 解析面；脚本以用户权限执行的文档明示（面板权限注记全文） | 11-04 走查 #11-13：Output/ 落盘 `WALKTEST.jpg`（4.6MB）→ post-action 脚本实跑（`postaction-log.txt` 内容 = 输出文件完整路径，无执行位 `.sh` 走 `/bin/sh` fallback 实证）→ Finder 前台高亮选中（截图 13） | ✅ |

**R1/R5 探针终判（DECISIONS ↔ VALIDATION 对账）**：R1 = HEIC 10-bit ✅ / AVIF 10-bit ✅ /
**AVIF 12-bit 请求落 10-bit**（宿主 `l12p` 封顶；文档化降级 + `AVIFEncoder` conformer 缝保留 +
`testAVIFGoldens` depth==10 锚，宿主能力变化即红）——落 11-02 DECISIONS D4 ↔ 本表 SC#1 测试锚。
R5 = XMP packet 全六格式不序列化（宿主 API 事实，11-02 D3 三途径字节级验证）→ 文档化限制 +
`{XMP}` 反向锚 + EXIF 走 properties dict 五格式全通 + WebP v1 元数据例外（OQ-11-5，RIFF
结构锚）——落 11-02 DECISIONS D3/D8 ↔ 本表 SC#1 + `ExportPhaseE2ETests` ①（六格式
`xmpPresent == false` 终判）。奇数尺寸：编码器级 33×17 逐格式 + E2E 级 257×171 精确落盘。

---

## Per-Task Map（11-01..11-05）

| Task | Plan | 交付 | commit | Status |
|---|---|---|---|---|
| 11-01 T1 | 模型 | ExportRecipe/ExportVariant 六格式参数面 + scalePercent 换算 + tag 派生（22 tests） | `c4bd371` | ✅ |
| 11-01 T2 | 命名 | ExportNamer 纯函数（16 tests，不摸 FS） | `559065c` | ✅ |
| 11-01 T3 | 契约 | ExportQueueContract 状态机/leg 缝/并发 1/yieldsToEditor 位（12 tests） | `84a91f4` | ✅ |
| 11-01 T4 | SPM | Swift-WebP 0.6.1 接线（唯一新 SPM 依赖，4 tests） | `d12311b` | ✅ |
| 11-01 T5 | 收口 | 回归 1187 + SUMMARY/DECISIONS(13) | 收尾提交 | ✅ |
| 11-01 验收 | fix | 契约 switch 显式穷尽 + package.resolved 钉版 | `db8fa32`/`de796c4` | ✅ |
| 11-02 T1 | 量化链 | ExportQuantizer 三域分层 dt 同款（12 tests） | `67eb61e` | ✅ |
| 11-02 T2 | 出口腿 | renderToEncodedBitmap sourceColorSpace 参数化 + 行序契约（7 tests） | `4fca688` | ✅ |
| 11-02 T3 | 五原生 | ImageIOEncoders + golden 矩阵 + EXIF properties 路径 + R1/R5 探针（5 tests） | `c14295c` | ✅ |
| 11-02 T4 | WebP | WebPEncoder + lossless 逐位 + mux 探测结构锚（5 tests） | `44d05d6` | ✅ |
| 11-02 T5 | 锚 | UTI 写能力常驻锚 + 注册表分派（4 tests） | `0d759d9` | ✅ |
| 11-02 T6 | 收口 | 回归 1220 + SUMMARY/DECISIONS(12)/L029 | 收尾提交 | ✅ |
| 11-03 T1 | 队列基建 | exportCommandQueue + TaskLocal 路由零 iop 改动（3 tests） | `0ec8f7e` | ✅ |
| 11-03 T2 | 导出链 | colorout additive 三色域 + override 插座 + convertToEncodedTexture（3 tests） | `afb8b3f` | ✅ |
| 11-03 T3 | .export 激活 | 双 stub 删除 + entry scale + 零缓存语义（2 tests + 契约翻转） | `5f261ef` | ✅ |
| 11-03 T4+T5 | 渲染腿 | ExportRenderer 全链 + 管线 scratch 缺陷修复（L030）+ yiyin E2E（7 tests） | `fb5b044` | ✅ |
| 11-03 T6 | 收口 | 回归 1235 + SUMMARY/DECISIONS(12)/L030 | `9e299ca` | ✅ |
| 11-03 验收 | fix | SUMMARY 测试名勘误 | `3ae5dbe` | ✅ |
| 11-04 T1 | 队列 actor | generation cancel/三 gate/并发 1/Utility QoS/TaskLocal 包裹 | `a68d888` | ✅ |
| 11-04 T2 | 队列单测 | 13 tests 毫秒级 leg 注入 | `f909dad` | ✅ |
| 11-04 T3 | State 桥 | ExportState 完整桥 + ExportFileWriter + App 接线 | `a057754` | ✅ |
| 11-04 T4 | 面板 | ExportPanelView + N×M 入队 + 56 export.* 键 | `4bbc3ec` | ✅ |
| 11-04 T5 | post-actions | PostExportActions + completion hook + 注入面自查 | `91d11f3` | ✅ |
| 11-04 T6 | 收口 | 回归 1248 + GUI 走查轮 13 PASS + DECISIONS(15) | `16825a3` | ✅ |
| 11-05 T0 | 前置修复 | flake 像素容差 `9439b59` / test-direct 判据 `80fc0bb` / F-11-04-1 `d9dfa9b` / L029 收口 `8700b61` | 四提交 | ✅ |
| 11-05 T1 | E2E 终验 | ExportPhaseE2ETests 3（8 变体单动作/不互覆/有印框队列链）+ 反模式扫描零命中 | `065f367` | ✅ |
| 11-05 T2 | perf | ExportPerfProbeTests 2 + `.work/11/perf.md`（只记不设门）+ 模糊腿 Release 复测 | perf 提交 | ✅ |
| 11-05 T3 | 签核材料 | 本文件 + DISCUSSION-LOG 终节 + Phase 12 移交清单 | 本提交批 | ✅ |
| 11-05 T4 | 翻账收口 | 全套终轮 + REQUIREMENTS EXP-01..08 Delivered + TODO/GOAL-STATE（C 档第 3 停记录） | 同批提交 | ✅ |

---

## Per-Requirement Annotations（EXP-01..08 注记行 = REQUIREMENTS 翻账口径）

| Requirement | 注记 |
|---|---|
| **EXP-01** | 六格式之 JPEG(quality)/PNG 8\|16/TIFF 8\|16\|32f×none\|lzw\|zip：golden 逐位（PNG/TIFF 8\|16 全压缩变体）+ 32f 1-ULP（float 域 bitwise 不可达，1e-6 带）；JPEG-in-TIFF 刻意缺席（有损域上线性歧义）。 |
| **EXP-02** | HEIC(quality,8\|10)/WebP(libwebp,lossy+lossless)/AVIF(native 27)。**注记：AVIF 12-bit 请求落 10-bit**（宿主封顶，文档化降级 R1；libavif conformer 缝保留）；WebP = libwebp SPM 全项目唯一新依赖；**WebP 元数据 v1 例外**（零 mux 面，OQ-11-5，Phase 12/14 复审位）。 |
| **EXP-03** | 尺寸=长边/短边/百分比/原尺寸（永不放大钳）+ DPI 1..2400 写入（72/300 实测落盘）；sizing 复用 `YiyinExportSettings`（OQ-11-6 正主），percent 经 `scalePercent` 折算向量。 |
| **EXP-04** | 五色域 sRGB/Display P3/Adobe RGB/ProPhoto/Rec2020 嵌入 ICC（ColorSync 精确路径）。**注记：32f 线性 ICC 变体宿主只供 sRGB/P3/Rec2020**——adobeRGB/proPhoto×32f typed throw（11-02 D2）；ProPhoto = 系统 ROMM 档案（D1）。 |
| **EXP-05** | yiyin = 导出管线最后一步（联合上下文注入，borders band 预留 + watermark 行，08-3 T3 义务闭环）；与 Phase 10 面板共享 `YiyinExportSettings`/模板/logo faces；导出域 yiyin 缺注入器 = typed error（静默丢印框禁止）。 |
| **EXP-06** | 后台队列：并发 1（内存红线，D-11-CONTEXT-2；**低优先级 = Utility QoS 替代——`MTLCommandQueue` 无公开 priority API**，checker M3/RESEARCH §4.4）+ 两层进度（generation 窗 done/total + phase）+ 取消（pending 即时/in-flight 边界/encode 后诚实完成）+ 重试（显式、仅 failed、队尾新 seq）；v1 无 queue journal（重启丢队列，D-11-CONTEXT-8，幂等重试替代）。 |
| **EXP-07** | 多规格同导：`enqueue` N images × M variants 单动作 + tag 派生不互覆（`<stem>_<tag>` + `-1` 递增，大小写不敏感占用）+ E2E 8 变体一次落盘终验。**注记：recipe v1 不持久化**（session 生命周期，D-11-CONTEXT-3）——`ExportRecipe`/`ExportVariant` Codable 直挂 Phase 12 PRES 预设存储即升级。 |
| **EXP-08** | post-actions：脚本路径制（普通 bookmark + 可达性重验降级）+ `Process` 直 exec（**注入面自查 PASS**：`$()`/反引号/分号路径逐字进 `$1`，哨兵未创建）+ Finder reveal + per-job completion hook（仅 `.done` 且当代）。 |

---

## Manual-Only Verifications（汇总：11-04 走查未走查行 + 11-05 T2 观感行）

| # | Behavior | 来源 | Why Manual | 状态 |
|---|---|---|---|---|
| 1 | GUI 取消/重试按钮中间态（长 job 可观察取消） | 11-04 #14 | 单图单 job 瞬时完成无中间态；语义由 `ExportQueueTests` ②③⑤ 全覆盖（D8） | ⏳ pending-manual（语义已单测钉死，GUI 观感随用复核） |
| 2 | 多图多 variant GUI 入队 | 11-04 #15 | 单 fixture 限制；N×M 计数/序由单测 ⑥ 钉 | ⏳ pending-manual（同上） |
| 3 | 编辑并发观感（导出 100MP 运行中拖滑块/缩放帧率） | 11-05 T2 §4 | 主观帧率判据，headless 不可测；结构面（独立队列+并发 1+Utility QoS）已锚 | ⏳ pending-manual（Phase 15 清算随行） |
| 4 | 真实 RAW 大图（100MP CR3/ARW）导出全链观感 | 11-05 | 测试 fixture 为合成平面；真机大样张手感/耗时随 Phase 15 | ⏳ pending-manual（Phase 15） |

---

## 反模式扫描（11-05 T1 终轮）

- **Export 新面全量 grep**（`LightamerCore/Sources/Export/` 10 文件 + `App/Sources/Lightamer/Export/` 3 文件）：TBD/FIXME/XXX/HACK/PLACEHOLDER/coming soon/notImplemented/unimplemented/`// stub`/`fatalError`/TODO——**零命中**。
- **tmp 残留**：`ExportPhaseE2ETests` 三测各带 `assertNoTmpResidue`（Output/ 落点零 `.tmp-*`）全绿——L009 同目录原子晋升纪律 E2E 级实证。
- **PipeCache 隔离**（.export 变体复核）：`ExportPipeTests` 共享缓存 totalBytes 恒 0 + misses==0（walk 不 probe）+ composite `.export` policy 双 false（11-03 T3/D8 在案）。

---

## PERF 记账（摘要，正本 `.work/11/perf.md`——只记不设门，Phase 15 清算）

- **分段耗时 @2560×1707 Debug（SSD）**：renderStage 2.5-4.0s（含注入 decode ≈1.8s）/ encodeStage JPEG 8ms·HEIC 47ms·AVIF 175ms·PNG16 240ms·TIFF32f 116ms·**WebP 5719ms（全链最重单段，Phase 15 杠杆位）**。
- **内存红线对账（D-11-CONTEXT-2）**：44.7MP 实测峰值增量 3604MB → **100MP 外推 ≈8.0GB**——推导值 ≈5GB **低估**（多平面存活 + CI CPU 副本）；**并发 1 红线维持且必要**（并发 2 即触 16GB 机器顶），Phase 15 杠杆 = 平面复用率。
- **32f TIFF 落盘**：2560×1707 = 69,924,114B（W×H×16 数学吻合）；100MP 32f 未压缩 ≈1.6GB/张。
- **08-3 遗留 #5 模糊腿 Release 复测**：Release 直启 `BORDERS-PERF` 三档 median 落 perf.md §5（solid/blur+overlay/radius+shadow）——遗留关闭。
- 编辑并发观感 = Manual-Only 行（结构面证据链在 perf.md §4）。

---

## Sign-Off Checklist

- [x] 全部 5 执行 plans 完成（11-01..11-04 执行+验收，11-05 收口），SUMMARY 逐 plan 落盘；签核材料齐（本文件 + DISCUSSION-LOG 终节 + perf.md）
- [x] SC#1-5 逐条三列证据（一手证据 + 测试锚 + GUI 实证）——无证据 ✅ 零条；**SC#2 显式引用 priority API 事实修正（checker M3）**
- [x] R1/R5 探针终判落 DECISIONS↔VALIDATION 双向对账（AVIF 12→10 降级锚 / XMP 六格式缺席 / HEIC 10 / AVIF 10）
- [x] E2E 终验：1 源×8 变体一次队列动作全落盘命名不互覆 + 有印框真队列 round-trip + tmp 零残留
- [x] 全套回归终轮 touch + build-for-testing 重编复跑 **1258/6skip/0fail**；11-04 收尾轮唯一 fail 已稳定化（像素容差 + sanity，三轮绿）
- [x] 反模式扫描零静默命中 + tmp 残留零
- [x] perf.md 计量总账齐（分段/内存外推/32f 尺寸/模糊腿 Release 复测 + Phase 15 清算注记七行）
- [x] Phase 12 移交清单五条 + 遗留对表落 `11-DISCUSSION-LOG.md` 终节
- [x] REQUIREMENTS EXP-01..08 翻账 Delivered（含注记行）+ TODO/GOAL-STATE 同批收口（§3.1）
- [x] `status: validated` + `nyquist_compliant: true`
- [x] **C 档第 3 停执行记录**：夜间自动推进场景，按先例 **D-07-3-T5-1 / D-09-05-T1-1**（夜间授权 = 签核推进授权，签核结论以 VALIDATION frontmatter 为准，用户终验留 verify-work 轮）执行翻账；config.toml `auto=true / paused=false` 任务边界复核在案；晨审可推翻（推翻项回注重开受影响面），详见 `11-05-DECISIONS.md`
