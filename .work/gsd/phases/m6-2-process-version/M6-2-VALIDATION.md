---
phase: M6-2
slug: process-version
status: validated
nyquist_compliant: true
created: 2026-10-14
validated: 2026-10-14
---

# Phase M6-2 — Validation（per-photo process version：`.lra` additive `process` 键 + 旧号冻结纪律）

> 体例对齐 `phases/m6-1-interop/M6-1-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收（config
> `dual_acceptance = true`）落终态后成文**：第一路 zcode 真独立 subagent 验收
> PASS / 0 error + 1 minor（BUNDLE-MAP 四行对账当场修复，`dec16b1f`）→ 第二路
> omp 因 **E3 配额硬顶**（429 retry-after ≈4.9 天）阻塞登记（非 FAIL）→
> **第二路意图由第二支零共享上下文 zcode 独立验收批兑现（第三独立眼）**——
> PASS / 0 error + 0 minor 新发现 + 3 观察项（含**修正第一路 skip 误计**），
> 正本 = `M6-2-01-ACCEPTANCE-2ND.md`（doc commit `f75c52fa`）。制度字面（omp
> 串行）与执行事实（zcode 第三眼替代）的偏离在「特殊事项 §2」登记，晨审可裁。
> **翻账只认证据**：SC 六项生效值对账正本 = 两路 ACCEPTANCE + SUMMARY + DECISIONS
> 四份亲跑/亲读记录；charter 验收形态三件（ROADMAP M6-2 行）= sidecar additive
> 零漂移负测（v9 档键面字节零改）✓ + 冻结语义 golden（同档跨模拟语义变更渲染
> 逐位不变）✓ + 管线 process 读缝零行为门（0/1 逐位恒等）✓——OQ-6 四门在其上
> 补 mint/传输门，四门全绿。
> **SC 数字对账基线 = 全套 `--all` 终验 `TOTAL|3725/24/0|2113s` 亲证值**
> （2026-10-14 第二路终验批，exit 0 零 MEMFAIL；对账链 **3689 + 36 = 3725**
> 精确闭合：3689（M6-1 终值基线）+ 36（三新文件 31 法 = SidecarV10Tests 15 +
> RenderProcessSeamTests 8 + ProcessVersionCarrierTests 8，加既有四文件
> additive 5 法 = StackMerge 2 + Import 1 + SessionBatch 1 + Metadata 1）；
> **skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL 24 机械一致**——脚本 :295 TOTAL 本就
> 是段行逐值累加，第一路「段和 21 vs 24 口径 quirk」系误计，第二路证伪后销账，
> 见特殊事项 §3）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（byte-face 三档〔digit-rewound v9 档 decode→re-encode 逐字节〕/ lenient decode 全表 / hash isolation 负测 / **真 load 链**〔SidecarV5Tests 同位，真盘写读〕/ pipe harness fence 轨〔DrtTailTests 同源，L014〕/ fork double 测试替身〔test-local ProcessProbeModule，独立 registry 不触生产〕/ LightCraft `ProcessVersion` 范式对表） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠，L055 双保险） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3725 tests / 24 skip / 0 fail**（2113s，2026-10-14 第二路终验批亲跑 exit 0；两路双证——第一路 2115s 逐值一致仅时间/RSS 采样方差；七 bundle 逐行：IOP **686/1/0**〔7572MB〕/ IOPParity **460/3/0**〔7249MB〕/ Layers **474/4/0** / Library **671/4/0** / Sessions **280/4/0** / Export **353/4/0** / App **801/4/0**〔2832MB〕；峰值全 <8G 运行门，零 MEMFAIL 零 crash） |
| **基线演变** | 3689（M6-1 终值）→ worker 批 +36（三新文件 31 法 15+8+8 + additive 5 法 2+1+1+1）= **3725 精确**；对账两式互证（第二路段级 skip 和 24 = TOTAL 24 机械一致 + 两路七 bundle 数字逐值一致） |
| **SC 数字面** | 定向对表全程精确：Library **654→671**（+17）/ Layers **466→474**（+8）/ App **793→801**（+8）/ IOP **684→686**（+2）/ Sessions **279→280**（+1）/ Export 353 / IOPParity 460 逐值零漂移；BUNDLE-MAP 四既有行 + 三新行经第一路 minor-1 修复 + 第二路 `grep -c "func test"` 实测复核闭环（13/11/12/13 + 15/8/8） |
| **在案发现（本 phase 事件）** | **minor-1（第一路发现，当场修复 `dec16b1f`）**：front-matter 申报「BUNDLE-MAP 四既有行 method 数更新」未兑现（四行 stale）——验收批实测四文件 grep 后原位修复，第二路复核四行全对表；**skip 21 vs 24「口径 quirk」误计（第一路观察项①，第二路证伪）**：段和实为 1+3+4+4+4+4+4 = 24 = TOTAL，无脚本 quirk——第一路 M6-5 候选条目不立（本批销账落账）；**执行期测试面三微修**（resolving 负数改单式 / CarrierTests flushUntil 内容谓词轮询 / SeamTests 7→8 拆分）——零产线改动，DECISIONS §7 在册 |
| **GUI 证据** | **零 GUI 面**（OQ-6 范围边界：零 UI/命令/MCP 面——红线自证 `*.xcstrings` + MCP 面 + App diff = 恰两 plan 文件亲跑）；行为面由真 load 链 + pipe harness 测试承载，无 gui-acceptance MANIFEST 义务 |
| **zh 对账** | 零新键——`*.xcstrings` 零 diff + 触碰面 UserDefaults 零直读（两路亲跑双证；OQ-6 范围边界兑现） |

---

## SC 六项生效值对照（`M6-2-CONTEXT.md` 裁决记录 2026-10-14 用户回批全 A → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **键面与 schema 承载**（OQ-1）：文档级 additive `process: Int?` + schemaVersion 9→10；缺键 = legacy = 0 = 恒 ABSENT 永不被动升级；新档 mint = current(1)；拼写 `process` 冻结；「入册 ≠ 升级」注记 | T1 `3be89a19` + T3 `a33a6afd` + T4 `14c349c1` | **Delivered**：`LightamerSidecar.swift` `schemaVersionCurrent = 10` + v10 注记段（入册≠升级段逐行在册）；`process: RenderProcessVersion?` + CodingKeys + `encodeIfPresent` canonical 形（nil ⇔ ABSENT ⇔ legacy）；三 byte-face 全绿——①v9 档 digit-rewound decode→re-encode **逐字节**（键 ABSENT）②v10 nil-face writer = v9 shape 仅差 schemaVersion 数字 ③process=1 档 round-trip byte-faithful；mint 门真盘钉死（CarrierTests ①：pristine load → 首编辑落盘 `"process": 1`）；既有测试族零编辑亲证（Tests/ numstat 0 删行，符号化 `schemaVersionCurrent` 自动传播） |
| 2 | **hash 与缓存纪律**（OQ-2）：hash isolation（不折 HistoryHash/driftDetected、零 history item、undo/swap 零触）+ 缓存键仅在分叉路径折值（「非 legacy 才折」三处登记）+ Copy Adjustments/预设不携带 | T1 `3be89a19` + T2 `72e6d22d` + T3 `a33a6afd` | **Delivered**：`driftDetected` 五元折叠结构性无 process 槽（亲读）+ `HistoryHash.swift`/`PipeCacheKey.swift`/`HistoryStack.swift` 本批零 diff（机检亲跑）；`testProcessIsHashIsolated`（± process → historyHash 逐字节同 + drift 三 false）+ CarrierTests ⑤（undo 到顶 + branch + swap 后仍 1，items 无 process 键）；契约三处逐处亲读（RenderProcess.swift 头注 KD-6 段 / AGENTS M6-2 节 / DECISIONS §6③）；seam ⑥ 行为级双证（同链同参仅 process 异 → 键恒等 + 第二 run misses==0 ALL-HIT）；传输零携带三负测（payload 结构性三座位 + `testPasteTransportNeverCarriesTheProcess` 真盘 + `testLightamerPresetCarriesNoProcessKey`） |
| 3 | **lenient 读腿与前瞻值**（OQ-3）：合法域整数 0..2^32−1（`2.0`→2）、域外/损坏 → legacy 不保留不毁档、更大号保留 + 渲染钳已知最新 | T1 `3be89a19` + T2 + T3 | **Delivered**：decode 三臂全 `try?` 永不 throw（Int 门 `1...0xFFFF_FFFF` → Double 整值臂 `raw == raw.rounded()` 同域 → else nil）；`testLenientLegalDomainBoundariesAreRetained`（1/2/0xFFFFFFFF 重存不降级）+ corrupt 集 6 值负测 + `testCorruptValueIsNotRetainedOnRewrite` + CarrierTests ④ 真盘 corrupt `"x"` 重存无键；stored-0 归一化 ABSENT（M1 存储门 1 起，`testStoredZeroNormalizesToAbsentKey` 钉死；值类型域门 `init?(rawValue:)` = `0...0xFFFF_FFFF` 含 0 哨兵——**双门分离**各自测试钉死）；前向大号 = `testForwardLargeNumberStampsVerbatim`（piece = 7 原值，钳制在 resolving 消费点）+ `testResolvingClampTable` |
| 4 | **零行为基线与枚举账本**（OQ-4）：机制 armed + 渲染零行为（process 0/1 逐位恒等）；`RenderProcess` compiler-exhaustive + case doc-comment 即账本；bump 纪律三层登记；否决演示性 bump | T2 `72e6d22d` + T5 `1dbd4217` | **Delivered**：`testRealChainRendersProcessZeroAndOneBitIdentical`（真 terminal trio 逐字节比，两路亲跑绿）+ 缓存键面零变化（ALL-HIT）；枚举 case doc-comment 与 AGENTS M6-2 账本行**双源逐行比对一致**（两路亲核）；bump 三层在册（AGENTS 架构增量节 + case 注释 + M6 iop 调参 AC 模板行）；**零演示性 bump = `git diff 2363549c..HEAD -- LightamerIOP/` 零命中亲跑**（iop 模块文件零触碰）；G2① 冻结门（fork double 同 build 已带 v1 臂，legacy 值跨模拟语义变更渲染逐位不变 = 未来 bump 冻结承诺的可执行证明形） |
| 5 | **迁移 UX 挂账**（OQ-5）：v1 无显式迁移动作（老档恒冻结）；「Update to Current Process」挂账至首个真实 iop 语义 bump 场景再裁交互形态 | T5 + T6 | **Delivered（挂账兑现）**：零迁移 UI/命令/MCP 面亲证（xcstrings/MCP 零 diff + App diff 恰两 plan 文件）；挂账双登记在案（DECISIONS §6 接线件四件套同批触发 + GOAL-STATE 续接点）；undo 到顶后写腿仍写 carrier 值（与 M2-8 pristine 判定面正交，第二路排查排除项在册） |
| 6 | **golden 四门**（OQ-6）：G1 additive 零漂移负测 / G2 冻结语义 golden 三式 / G3 管线读缝零行为门 / G4 mint+传输门——ROADMAP 三件最小面之上补 mint 门；范围边界零 UI/零 MCP/零格式矩阵/零新 SPM/零 `.metal`/零新键 | T1..T4 全批 | **Delivered**：G1 = 三 byte-face + hash isolation + App 级真盘 legacy 门（`testLegacyDocumentReSavesWithTheKeyAbsentAndKeysPreserved`：v9-era 手写档 → load → 编辑 → 重存键 ABSENT + 既有键逐字节 + 无 drift）✓；G2 = 冻结门/分叉可见门（renderProcess 1 → gain 2.0 ≠ 基线，缝非摆设）/缺键 = legacy 臂（sidecar→pipe 值流贯通）三式 ✓；G3 = 真链 0/1 逐位恒等 + ALL-HIT + IOPParity 460/3/0 零触碰 ✓；G4 = mint 门 + **出生点全仓亲数恰 6 处**（coordinator 写腿 :1523 / ImportService :681 / StackMergeService :2220+:2679 / MetadataService :202 / SessionBatchApplier :149——无第七处漏报）+ 传输零携带 + corrupt 存回无键 ✓；范围边界六域红线机检族全绿（见下节） |
| — | **AC7 零回归门** | T5 `1dbd4217` + 两路机检 | **Delivered**：`Pipe/History/` + `PipeCacheKey.swift` 零 diff；MCP 面（20 工具封闭集快照族）零 diff；`.metal` 全仓零 diff；`LightamerIOP/` 零 diff；`*.xcstrings` 零 diff；Export Core+App 零 diff；LibrarySchema/LightamerPreset/FilterPredicate 零 diff；QuickLook/Spotlight appex 零触碰；`Project.swift` diff = 恰 3 行测试登记（dependencies 块零 diff，零新 SPM）；`\.runModal(` App/Sources 零命中；IOPParity/Export = 基线逐值一致（零触碰面双保险） |
| — | **AC8 SC 数字门** | T6 + 两路终验批 | **Delivered**：LIB +17 / LAYERS +8 / APP +8 / IOP +2 / SESS +1 定向逐值精确；全套终验 **3725/24/0** = 3689+36 精确闭合（两路独立亲跑同值 2115s/2113s），exit 0 零 MEMFAIL 零 crash 零 no-total-line；L055 双保险两路亲跑（七段末行 = All tests 总计行逐段一致 + 崩溃签名七段零命中） |

## 双重验收记录（dual_acceptance 链，第二路正本 = ACCEPTANCE-2ND）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **第一路 zcode 独立验收**（2026-10-14，真独立 subagent 零共享上下文，`dec16b1f`） | **PASS / 0 error + 1 minor（当场修复）** | 全套 `--all` 亲跑 **3725/24/0**（2115s）exit 0 + AC1..8 逐条 fresh evidence + 三审计节（schema bump / hash isolation / mint 面六构造点亲数 + 管线缝八点逐证）+ 六提交边界逐一对表 + 红线机检族亲跑全绿；亲跑不轻信报告 | **minor-1**：BUNDLE-MAP 四既有行 method 数 stale（front-matter 申报未兑现）——验收批实测 grep 后原位修复（本批 commit 随带）；**观察项①（skip 21 vs 24）后被第二路证伪**（误计），观察项②（翻账挂验收闭环批）本批清偿 |
| **第二路 omp 二次验收（原制度路）** | **E3 配额阻塞登记（非 FAIL），未执行** | 三次串行派发逐次诊断（直连死代理 env → 证书校验错 → xray 起后 429 `Go usage limit exceeded` retry-after ≈4.9 天——配额硬顶非瞬时）；任务书存 `/tmp/m6-2-omp-lane2-prompt.txt` 保留 | 不重试（lane_retry 语义）；第二路意图改由第三独立眼兑现——偏离登记见特殊事项 §2，晨审可裁 |
| **第二路（实际执行）：zcode 第三独立眼**（2026-10-14，零共享上下文，`f75c52fa`） | **PASS / 0 error + 0 minor 新发现 + 3 观察项** | 全套 `--all` 亲跑 **3725/24/0**（2113s）与第一路逐值一致 + AC1..8 独立重验 + 六面审计独立重取（schema/哈希/mint 六点/缝八点/四门/红线族）+ minor-1 修复复核（四行 grep 全对表闭环）+ **独立发现零新问题**（排查过而排除的面九项在册：JSON null 臂序 / 2^32 双臂拒 / 切回路径不 re-prime 幂等 / key 约定 / undo 到顶写腿 / tile 零重写 / 缩略图恒 legacy 结构性保证等） | **修正第一路观察项①**：段级 skip 和 = 1+3+4+4+4+4+4 = **24 = TOTAL**，脚本 :295 本就是段行机械累加——「口径 quirk」不成立，系第一路误计（其七段 BUNDLE 行 skip 值本身与本跑一致）；对账结论无影响，M6-5 候选条目不立。观察项②（ROADMAP/TODO 记 0e+0m vs 正本 0E+1minor）= 本批订正；观察项③（孤儿 fixture 复活）= M4-1 挂账 #6 既有行为，归 M6-5 |

两路终态：**零未清偿 error、零 open minor**；minor-1 当场修复闭环（第二路复核）；
两路独立全套复跑同值互证（3725/24/0 逐值一致）——零实质分歧，dual_acceptance
意图（≥2 路零共享上下文独立验收 PASS）满足。

## Per-Plan Map（M6-2-01 单 plan 全量批）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M6-2-01 | T1 Core 账本件 `Pipe/RenderProcess.swift`（RenderProcessVersion 值载体 legacy=0 哨兵 + RenderProcess 枚举账本 + resolving 钳制表 + KD-6 契约头注）+ sidecar v10（9→10 + `process` additive + lenient decode + encode canonical + hash isolation 注记 + 入册≠升级）+ T2 管线读缝 armed（run-scoped 属性 + 双入口 additive 参数 + IOPiece stamp 不入 paramsHash + 派生 pipe 六处继承 + 静态入口豁免注记）+ T3 App 载体/写腿（`processVersions` map 三面 + load 腿双分支 prime pristine mint + `makeSidecarDocument` 唯一写缝）+ T4 出生点盖章五面（Import AI 副本 / StackMerge 两 writer / SessionBatchApplier **E1 分支条件盖章**禁 `?? .current` / Metadata pristine 臂）+ T5 红线自证 + AGENTS bump 纪律三层 + T6 收口 | worker 六提交 `3be89a19..8c8727ba`（基线 `2363549c`；T5 `1dbd4217` / T6 `8c8727ba`）+ 验收批 `dec16b1f`（第一路 + minor-1 修复）+ `f75c52fa`（第二路 doc）；未 push | 双路 PASS / 0 error + 0 minor open（第一路 1 minor 已修） |

零红线域终态（两路亲跑，`2363549c..HEAD`）：`Pipe/History/` + `PipeCacheKey.swift` =
**0 diff**（hash 折叠面红线本体）；MCP 面 = **0 diff**（快照族无扰）；全部 `*.metal` =
**0 diff**；`LightamerIOP/` = **0 diff**（零演示性 bump 的 diff 面佐证）；`*.xcstrings` =
**0 diff**（零新键）；Export Core+App = **0 diff**（六格式矩阵零触）；LibrarySchema/
LightamerPreset/FilterPredicate = **0 diff**；appex = **0 触碰**；`Project.swift` = 恰
3 行测试登记（dependencies 块零 diff，零新 SPM）；`\.runModal(` App/Sources = **0**；
触碰面 UserDefaults 直读 = **0**（零新键）；App 源码改动 = **恰两 plan 文件**
（PipeCoordinator +26 / WorkspaceModel +38）。LightCraft 范式对照成立：`process` 同名
键 + `skip_serializing_if` 缺键不序列化（stored-0 归一同构）+ lenient decode + 前向
大号钳渲染（`ProcessVersion::process()` 同构）+ copy/paste 不携带 process；两处有意
偏离登记在案（DECISIONS §8：版本槽不承载 process——文档级键跨 versions 恒定；
legacy 记 0 非 V1=1）。LightCraft MIT OR Apache-2.0 全程思想/命名级转录，零成段
代码复制，零 NOTICE 义务触发。

---

## 挂账总汇编（M6-2 单一移交清单，三项带锚点 + 一项销账留痕）

1. **coordinator 传值接线件 + 分叉消费件 + 迁移 UX 同批裁形**（DECISIONS §6 +
   OQ-5，by-design 挂账非缺陷）：M6-2 交付面 = 缝 armed 零行为——生产零传值
   亲证（`grep renderProcess:` 命中仅声明/缺省参/一处转发；`resolving(` 生产
   消费点 0）。**首个真实 iop 语义分叉/bump 批触发时四件同批**：①各 render
   调用点读载体传 `renderProcess:` ②分叉 iop 消费 `RenderProcess.resolving`
   + 穷举 switch ③该 stage 缓存键按「非 legacy 才折」折值 ④「Update to
   Current Process」交互形态裁决（LightCraft `develop.updateProcess` 一步 undo
   为参考底稿）。
2. **pre-M6-2 SessionBatchApplier 既有档臂文档级字段丢弃缺口**（DECISIONS §1①，
   明确不修出范围）：该臂非 round-trip——从 decode document 仅提升 5 字段 +
   processStamp 后共汇全新档构造，`provenance`/`rawOverrides`/`displayTransform`/
   `versions`/`activeVersionID`/`aiProvenance`/`filmRecord` 在既有档 batch apply
   时被静默丢弃——**pre-M6-2 数据保真缺陷非本批引入**，process 的显式携带 =
   M6-2 新增面（E1 双登记第二半）；修复归属 M6-5 挂账清算批候选或独立 fix
   batch（晨审裁）。
3. **孤儿 fixture 全套轮复活**（两路双证）：`Tests/Fixtures/TiffRaster/
   srgb-matrix-8.tif.lra` 跑前删跑后复活——**M4-1 挂账 #6（测试 sidecar 泄漏）
   仍活**（M6-1 挂账清单同款延续）；清偿归属 M6-5 清算批或 M4-1 侧修复批（晨审裁）。
4. **〔销账留痕〕skip 21 vs 24「脚本口径 quirk」M6-5 候选条目不立**：第一路
   观察项①提请挂 M6-5（与 L055 脚本级修复同族）——第二路实测证伪（段和
   1+3+4+4+4+4+4 = 24 = TOTAL 24，脚本 :295 段行逐值机械累加无独立口径），
   系第一路误计；候选条目从未入 TODO/ROADMAP/STATE 的 M6-5 区（本批 grep
   亲证零命中），即日销账、不流传。

另有三项**批内已清偿**不占挂账：第一路 minor-1（BUNDLE-MAP 四行，`dec16b1f`
当场修 + 第二路复核闭环）；账面口径漂移（ROADMAP/TODO 记第一路 0e+0m——本批
订正为 0E+1minor 已修 + 第二路 PASS 0E+0minor）；第一路观察项②（行级翻账挂
验收闭环批——即本批）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。六项生效值 + AC7/AC8 每条均有 ≥1 机器锚
  （SidecarV10Tests 15 / RenderProcessSeamTests 8〔fork double 分叉可见 + 真链
  逐位 + fence 轨〕/ ProcessVersionCarrierTests 8〔真 load 链真盘写读〕/
  additive 5 法〔真实 HDR/Mertens 生产腿 + AI 副本 + Session 三态 + Metadata〕）
  + ≥1 数字/实证背书（两路独立全套复跑 3725/24/0 同值 + 对账链 3689+36 精确 +
  BUNDLE-MAP grep 实测 + 红线机检族亲跑 + mint 面全仓构造点亲数恰 6 处 +
  LightCraft 正本对表）。
- 采样密度：单 plan 全 AC 逐条机检（36 新测 + 既有面零回归双保险：IOPParity/
  Export 基线逐值 + Tests/ numstat 0 删行）+ **两路零共享上下文独立验收**
  （各自全套 `--all` 亲跑 + 各自六面审计重取，第二路证据 HEAD `dec16b1f`
  亲跑/亲读重取不复述第一路）+ checker FAIL 先审后放（E1+4M 回注
  `2363549c`，E1 修复批 front-matter 三行同批修订在案）；「无证据 ✅」零项。
- 数字对账：两路互证（3725/24/0 两轮独立亲跑逐值一致 + 段级 skip 和 = TOTAL
  机械一致〔第二路亲证，纠正第一路误读〕+ 对账式 3689+36 = 3725 精确）。

## 特殊事项入册（phase 级事件台账）

1. **omp E3 配额阻塞 → 第三独立眼替代**：原制度第二路（omp 串行）三次派发
   诊断后确认 429 配额硬顶（≈4.9 天，非瞬时，lane_retry 不适用）；第二路
   意图由第二支零共享上下文 zcode 独立验收批兑现（PASS 0E+0minor）——
   **dual_acceptance 意图满足、制度字面偏离**（omp 未参与本 phase 验收），
   登记晨审可裁；任务书 `/tmp/m6-2-omp-lane2-prompt.txt` 保留，配额恢复后
   如需可按原任务书补派 omp 复核路。
2. **第一路 skip 误计的证伪链**：第一路观察项①称「段级 skip 和 21 vs TOTAL
   24 = 脚本既有口径 quirk（基线同款）」；第二路实测段和 = 24 且亲读脚本
   :295 证 TOTAL = 段行逐值累加——第一路七段 BUNDLE 行 skip 值本身（1/3/4/4/
   4/4/4）与第二路一致，**误在段和算术而非数据**；M6-5 候选条目不立（挂账
   §4 销账留痕）。教训：段级求和应机检不应心算（L055 双保险已含末行核对，
   本例为合计侧人工算术误差，非脚本缺陷）。
3. **账面口径漂移**（第二路观察项②）：第一路结果在 ROADMAP M6-2 行/TODO
   M6-2 行记「PASS / 0 error + 0 minor」，与 ACCEPTANCE 正本（0E+1minor 当场
   修复）不一致——验收闭环批（本批）同批订正；「minor 已修 ≠ 未发生」，
   账面记发生数。
4. **E1 双登记**（checker error 回注的落地，DECISIONS §1）：SessionBatchApplier
   既有档臂非 round-trip 的事实修正（plan 原文「零改自动保全」与源码相反）
   → 分支条件盖章处方（禁跨臂 `?? .current`）+ 三态一法测试逐字对应 checker
   处方；pre-M6-2 字段丢弃缺口出范围登记（挂账 §2）。
5. **钳制形式正确性诚实申报**（DECISIONS §5）：M6-2 时点 resolving 钳制目标
   == legacy 行为（无语义分叉），钳制测试证形式非观感；首个真实分叉落地时
   由新 golden 取代。M1 双门分离（值门含 0 / 存储门 1 起）三处代码注记在位。

## 授权记录（C 档第 3 停 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 +
  M3/M4/M5/M6-1 全系 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（worker 执行 + 双重
  验收编排 + 终验 + 本 VALIDATION 同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`.work/config.toml
  [gsd] paused=false / auto=true` 全程未动，dual_acceptance=true 在册）；用户晨审
  可推翻本签核（推翻 = M6-2 签核作废回退，已交付面与两路执行/验收证据不受
  影响；翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-14 午批）；**doc-only——
  零源码 diff**（`git status` 对表 = 本批全 docs；工作树既有 untracked 四件
  属兄弟批/孤儿 fixture〔M4-1 #6〕，本批零触碰）。
- **呈报裁决点（禁静默）**：①接线件 + 迁移 UX 触发时机（首个真实 iop 语义
  bump 批即触发，无需另裁——如晨审要求提前演示 bump 则须用户显式令）；
  ②pre-M6-2 字段丢弃缺口修复归属（M6-5 清算批 or 独立 fix batch）；
  ③孤儿 fixture 清偿归属（M6-5 or M4-1 侧）；④omp 补派复核路是否需要
  （配额恢复后按原任务书，默认不需要——双路意图已满足）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：M6INT-01 兑现注记翻 **Delivered（validated）**——验收状态
  更新为双路独立验收 PASS（omp E3 登记 + 第三眼替代）+ 终态 3725/24/0。
- ROADMAP：M6-2 行 ✅ 闭环（终态 3725/24skip/0fail；双路结论 + 勘误后口径）；
  头部 Milestone 6 行追加 M6-2 closed。
- STATE：M6-2 complete + current_phase 翻新 = next M6-3；m6_phases_complete 3；
  M6 Ledger 3/7。
- TODO：M6-2 条目落账（[x]）+ M6 头部翻新（M6-2 ✅ 闭环，下一步 = M6-3）。
- GOAL-STATE：续接点翻新 = **M6-2 closed → M6-3 ALCE-03 UltraHDR**。
- 销账：skip-quirk M6-5 候选条目不立（挂账 §4 留痕）；未 push；测试宿主/GUI
  进程零残留（两路验收批毕已清，第二路 `ps` 亲查 = 0）。

## 签核

- 六项生效值 + AC7 + AC8 全项 **Delivered**（三列证据齐；数字对账 = 两路独立
  亲证基线 3725/24/0，对账链 3689+36 精确闭合；双重验收零实质分歧）。
- `status: validated` + `nyquist_compliant: true`。
- **M6-2（per-photo process version）closed**：单 plan 全量批双路独立验收
  PASS / 0 error + 0 minor open（第一路 1 minor 批内修复），终验
  `TOTAL|3725/24/0|2113s`；挂账单一清单三项带锚点（接线件 + 迁移 UX 至首个
  真实 bump 批 / pre-M6-2 字段丢弃缺口 → M6-5 或 fix batch / 孤儿 fixture
  M4-1 #6 延续 → M6-5 或 M4-1 侧）+ 一项销账留痕（skip-quirk 误计证伪），
  移交 M6-5 清算批与晨审。
- 晨审裁决项：四项呈报裁决点（见授权记录）+ 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
