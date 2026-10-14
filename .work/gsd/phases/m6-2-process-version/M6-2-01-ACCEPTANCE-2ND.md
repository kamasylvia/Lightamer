# M6-2-01 ACCEPTANCE（第二路 zcode 独立验收）

> 制度位置：config `dual_acceptance = true` 双重验收链的第二路。第一路（真独立
> subagent 批，`dec16b1f`）PASS / 0 error + 1 minor（当场修复）；omp 路维持 E3
> 配额阻塞登记（`M6-2-01-ACCEPTANCE.md` 文末，非 FAIL）。本批 = **第三独立眼**：
> 零共享上下文，不复述第一路结论，全部证据 HEAD `dec16b1f` 亲跑/亲读重取。
> 本文件 doc-only，零产线改动；不 push。

## 结论

**PASS / 0 error + 0 minor（本路新发现）+ 3 观察项（1 项修正第一路记录）**

- 对账树：六提交 `3be89a19..8c8727ba`（基线 `2363549c`）+ 第一路验收批
  `dec16b1f`，未 push。
- AC1..AC8 全 ✓（本路独立重验，逐条证据见 §3）；六面审计全过（§4）；红线机检
  族全绿（§4.7）。

## 1. 全套独立复跑（亲跑数字）

`caffeinate -dis Scripts/test-direct.sh --all`（夜间全自动授权在案；跑前删孤儿
fixture `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`——M4-1 挂账 #6 纪律）：

```
BUNDLE|IOP|686/1/0|peakRSS=7572MB|450s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=7249MB|761s|sampling=time
BUNDLE|Layers|474/4/0|peakRSS=1176MB|161s|sampling=time
BUNDLE|Library|671/4/0|peakRSS=619MB|78s|sampling=time
BUNDLE|Sessions|280/4/0|peakRSS=1624MB|70s|sampling=time
BUNDLE|Export|353/4/0|peakRSS=5539MB|204s|sampling=time
BUNDLE|App|801/4/0|peakRSS=2832MB|389s|sampling=time
TOTAL|3725/24/0|2113s        ← exit 0；OK (direct launch, no testmanagerd)
```

- **对账闭合**：3725 = 基线 3689（M6-1-VALIDATION 终验亲证值）+ 36（三新文件
  31 法 15+8+8 + additive 5 法 2+1+1+1）；**skip 段和 1+3+4+4+4+4+4 = 24 =
  TOTAL 24 机械一致**（脚本 :295 TOTAL = 段行逐值累加，无独立口径）；七段
  peakRSS 全部 <8G 门（最大 IOP 7572MB），`grep -c MEMFAIL` = 0，零 crash。
- **L055 双保险亲跑**：①七段日志末条 `Executed` 行逐段核对 = 「All tests」
  总计行且与 BUNDLE 行一致（686/460/474/671/280/353/801，skip 1/3/4/4/4/4/4）
  ②`terminated abnormally|Restarting after unexpected exit` 七段全零命中。
- 段间数字与第一路逐值一致（时间/RSS 小幅波动属采样方差）。

## 2. AC 总表逐条（本路 fresh evidence）

| AC | 生效值 | 本路独立复核证据 | 判 |
|---|---|---|---|
| 1 键面 | `process` 拼写冻结 + v10 bump + 三则语义 + 「入册 ≠ 升级」 | `LightamerSidecar.swift` :247 `schemaVersionCurrent = 10` + :208-246 v10 注记段逐行读码；:552-566 decode lenient 表 + :641-642 `encodeIfPresent` canonical 形亲读；三 byte-face + stored-0 归一 + FUTURE-version 全绿（全套亲跑） | ✓ |
| 2 hash/缓存纪律 | hash isolation + 零 history item + 传输零携带 + 契约三处登记 + 键面零变化 | §4.2；`AdjustmentTransferPayload` :109-115 结构性三座位（records/snapshot/drtRecord）亲读；契约三处 = RenderProcess.swift 头注 :37-44 + AGENTS M6-2 节 + DECISIONS §6 亲读；seam ⑥ 第二 run `misses == 0` | ✓ |
| 3 lenient 读腿 | 边界表 + 损坏集全 nil 不毁档 + 存回 ABSENT + 前向大号保留 + 渲染钳 + pipe 面原值 | decode 表逐臂读码（Int 门 `1...0xFFFF_FFFF` → Double 整值臂 `raw == raw.rounded()` 同域 → else nil；全 `try?` 永不 throw）；`testLenientLegalDomainBoundariesAreRetained`（1/2/0xFFFFFFFF + 重存不降级）+ corrupt 集 6 值 + `testForwardLargeNumberStampsVerbatim`（piece = 7 原值）+ `testResolvingClampTable` | ✓ |
| 4 零行为基线 | 0/1 逐位恒等 + 枚举账本 + bump 三层在册 + 零演示性 bump | `testRealChainRendersProcessZeroAndOneBitIdentical`（真 terminal trio 逐字节比，亲跑绿）；`RenderProcess` case doc-comment 与 AGENTS 账本行双源逐行比对一致；`git diff 2363549c..HEAD -- LightamerIOP/` 零命中亲跑 | ✓ |
| 5 迁移 UX 挂账 | 零迁移 UI/命令/MCP 面 + 挂账双登记 | `*.xcstrings` + App/Sources/Lightamer/MCP/ 零 diff 亲跑；App 源码 diff = 恰两 plan 文件（numstat 亲核）；DECISIONS §6 + GOAL-STATE 续接点挂账在案 | ✓ |
| 6 golden 四门 | G1..G4 | §4.5 逐门 | ✓ |
| 7 零回归门 | 红线族零 diff + 既有族原样绿 | §4.7 机检族亲跑全绿；IOPParity 460/3/0 + Export 353/4/0 = 基线逐值一致（零触碰面双保险）；Tests/ numstat 七文件全纯增行（0 删行）亲核 | ✓ |
| 8 SC 数字门 | LIB +17 / LAYERS +8 / APP +8 / IOP +2 / SESS +1；全套 ∈ 3721..3727 | 全套亲跑：654→**671** / 466→**474** / 793→**801** / 684→**686** / 279→**280** / Export 353 / IOPParity 460 逐值精确；合计 **3725/24/0** = 3689+36 | ✓ |

## 3. 第一路 minor-1 复核（BUNDLE-MAP 四行修复）

`git diff 2363549c..HEAD -- M2-4-0-BUNDLE-MAP.txt` 亲读 + 四文件
`grep -c "func test"` 实测对表：

| 行 | 申报 | 实测 grep | BUNDLE-MAP 现值 | 判 |
|---|---|---|---|---|
| StackMergeServiceTests | 11→13 | 13 | `IOP 13` | ✓ |
| ImportServiceTests | 10→11 | 11 | `LIB 11` | ✓ |
| MetadataServiceTests | 11→12 | 12 | `LIB 12` | ✓ |
| SessionBatchApplierTests | 12→13 | 13 | `SESS 13` | ✓ |

三新行（`LIB 15 SidecarV10Tests` / `LAYERS 8 RenderProcessSeamTests` /
`APP 8 ProcessVersionCarrierTests`）同批实测 15/8/8 一致。**修复到位，闭环。**

## 4. 六面审计（独立视角）

### 4.1 schema v10 additive 零漂移

- 三 byte-face 测试读码亲证力学：①`testV9FormDocument...` digit-rewound
  decode→re-encode 逐字节断言（`XCTAssertEqual(reEncoded, v9String)`）②
  nil-face writer = v9 shape 仅差 schemaVersion 数字（`JSONSerialization` 键集
  断言 `process` ABSENT + 双向 digit-swap 恒等式）③process=1 档 round-trip
  byte-faithful。既有 byte-face 族零编辑亲证（Tests/ numstat 0 删行）。
- **tolerant decode 逐臂读码**（:552-566）：`contains(.process)` 门 → Int 臂
  （域门 1 起）→ Double 臂（`raw == raw.rounded()` 整值性 + 同域）→ else nil；
  显式 null 走 contains-true 路径落 nil 臂（JSON null 两 decode 皆败）——
  损坏集 6 值负测覆盖（-1/2.5/"x"/NSNull/[1,2]/2^32）。
- **stored-0 归一化**：decode 即 nil（M1 存储门 1 起）→ re-encode
  `if let process` 恒 ABSENT（`testStoredZeroNormalizesToAbsentKey` 钉死）。
- **M1 双门分离**：值门 `init?(rawValue:)` = `0...0xFFFF_FFFF`（含 0 哨兵，
  RenderProcess.swift :74-77）/ 存储门 = `1...`（sidecar decode）——两门各自
  测试钉死（`testVersionTypeDomainGateAndConstants` 断言 -1 与 2^32 均 nil +
  0 合法；`testStoredZero...` 断言 0 → ABSENT），三处代码注记亲读在位
  （RenderProcess.swift 头注 / LightamerSidecar.swift decode 段 / AGENTS M6-2 节）。

### 4.2 hash isolation

- **机制本体**：`driftDetected`（LightamerSidecar.swift :1088-1095）五元折叠
  `stack / decodeParamsHash / layerSnapshot / drtRecord / filmRecord`——
  process 结构性不在折叠公式可见域；`HistoryHash.swift` / `PipeCacheKey.swift`
  / `HistoryStack.swift` 本批零 diff（`git diff 2363549c..HEAD -- Pipe/History/
  PipeCacheKey.swift` 零输出亲跑）。
- **测试钉死**：`testProcessIsHashIsolated`（同 stack ± process(nil/1/7) →
  historyHash 逐字节同 + driftDetected 三 false + layerStack 不变）+
  CarrierTests ⑤（undo 到顶 position -1 + branch + swap 后重存仍 1；items
  逐条断言无 `process` 键 = 零 history item 面）。
- **分叉点折键契约三处登记**逐处亲读：RenderProcess.swift :37-44 头注（KD-6
  段，「FOLD ONLY WHEN NON-LEGACY」）+ AGENTS M6-2 节 + DECISIONS §6③；
  M6-2 零分叉 = `PipeCacheKey` 零改 + seam ⑥ 行为级双证（同链同参仅 process
  异 → 键恒等 + 第二 run `misses == 0` ALL-HIT）。
- **与 modversion 正交**：头注 :46-51 显式禁令（禁折 `ModuleInstance.version`
  / HistoryHash）+ 零 diff 机检兜底。

### 4.3 mint 面（出生点全仓亲数）

`grep -rn "LightamerSidecar("` 生产面（App + LightamerCore 非 Tests 非
SidecarStore 自身）**亲数 = 恰 6 处**，逐点读码：

| # | 点 | 盖章形 | 判 |
|---|---|---|---|
| 1 | PipeCoordinator :1523（写腿） | `processCarrier.rawValue == 0 ? nil : processCarrier`（carrier 驱动，:1500-1502 读面） | ✓ |
| 2 | ImportService :681（AI 副本） | `process: .current` | ✓ |
| 3 | StackMergeService :2220（HDR） | `process: .current` | ✓ |
| 4 | StackMergeService :2679（Mertens+Pano 共用 landStackProduct 腿） | `process: .current` | ✓ |
| 5 | MetadataService :202（pristine 臂） | `process: .current`；既有档臂 `mutate(&document)` 真 inout round-trip 零改自动保全 | ✓ |
| 6 | SessionBatchApplier :149（E1 分支条件） | `process: processStamp` per-arm 提升（既有档臂 = `document.process` 原值 verbatim；pristine 臂 = `.current`）；`?? .current` 禁令注记在提升点与构造点两处亲读在位 | ✓ |

无第七处漏报（Tests 35 文件构造点为测试面不入生产普查）。**E1 合规**：
三态一法测试 `testBatchApplyStampsProcessBranchConditionally`（pristine = 1 +
legacy 保 ABSENT / 1 保全 / 前向 7 保全）与 checker 处方逐字对应；E1 双登记
（pre-M6-2 字段丢弃缺口不修出范围 + process 显式携带面）DECISIONS §1 在案——
构造点亲读证实该臂确只提升 5 字段 + stamp（provenance/rawOverrides/
displayTransform/versions/activeVersionID/aiProvenance/filmRecord 确不在构造
实参中，登记诚实）。

### 4.4 管线缝 armed 零行为

- **八继承/stamp 点逐点亲证**（grep `\.renderProcess = ` 全命中清单）：
  LCDriver basePipe :243 / layerPipe :400 / terminalPipe :570（3）+
  PixelPipe forwardWalk stamp :988（pipeType 同位、freeze 之前）/
  tailPipe :1104 / filmPipe :1223 / replayPipe :1376（3）+ 静态入口
  `pipe.renderProcess = renderProcess` :2103（1）= 8 点；no-op throwaway
  豁免注记（:2050-2052）在位。
- **IOPiece**：additive 字段 + memberwise 默认参 `.legacy`（:100）= 既有构造
  点零 diff；**不入 paramsHash**（commitParams 唯一写 paramsHash，stamp 是
  独立字段）——run 常量惯例亲证。
- **生产零传值**：`grep "renderProcess:"` 生产面命中仅声明/缺省参/
  processComposite→composite 一处转发（PixelPipe :2157）；`resolving(` 生产
  消费点 = 0（仅 doc 注记 + 测试）——零行为结构证明 + G3 行为级双证。
- coordinator 传值接线挂账（DECISIONS §6）+ 派生 pipe 覆盖（尾段 DRT tail /
  film / display replay / LCDriver 三 pipe）亲读与 AGENTS 节一致。

### 4.5 golden 四门逐门

- **G1**：三 byte-face（§4.1）+ hash isolation（§4.2）+ App 级真盘 legacy 门
  `testLegacyDocumentReSavesWithTheKeyAbsentAndKeysPreserved`（v9-era 手写档 →
  load → 编辑 → 重存 `process` ABSENT + schemaVersion 10 + 既有键/item 逐字节
  保全 + 无 drift）。✓
- **G2**：三式读码亲证——①冻结门：fork double **同 build 已带 v1 臂**
  （`piece.renderProcess.rawValue > 0` 分支在编译产物内）legacy 值渲染 =
  直通基线逐位（结构性不可达 + 行为级断言）②分叉可见门：renderProcess 1 →
  gain 2.0 ≠ 基线（`XCTAssertNotEqual` + recorder raw==1）③缺键 = legacy 臂：
  v10 无键档 decode nil → `?? .legacy` → pipe → legacy 臂逐位（sidecar→pipe
  值流贯通）。✓
- **G3**：`testRealChainRendersProcessZeroAndOneBitIdentical`（真 terminal
  trio，防空转断言 + 逐字节相等，亲跑绿）+ 缓存键面（seam ⑥ ALL-HIT）+
  IOPParity 460/3/0 零触碰（源码 diff + 全套亲跑双证）。✓
- **G4**：mint 门（CarrierTests ① pristine load → carrier = .current 且零盘
  写 → 首编辑落盘 `"process": 1`）+ 五出生点（§4.3）+ 传输零携带
  （payload 三座位结构性 + CarrierTests ⑥ 真盘负测 + Preset 容器 6b 负测）+
  corrupt 存回无键（SidecarV10Tests 3e + CarrierTests ④ 真盘）。✓

### 4.6 六提交边界逐一对表

| commit | 交付 | 本路边界核验 |
|---|---|---|
| `3be89a19` T1 | RenderProcess.swift（新 150 行）+ LightamerSidecar +90 + SidecarV10Tests（新 15 法）+ Project.swift +1 + BUNDLE-MAP +7（注记块 6 行 + 1 行） | stat 亲核恰合 front-matter；无越界 |
| `72e6d22d` T2 | IOPiece +16 / PixelPipe +49 / LCDriver +13 + SeamTests（新 8 法）+ Project.swift +1 + BUNDLE-MAP +1 | 恰合；八继承点全落三 plan 文件 |
| `a33a6afd` T3 | WorkspaceModel +38 / PipeCoordinator +26 + CarrierTests（新 8 法）+ Project.swift +1 + BUNDLE-MAP +1 | 恰合；load 双分支 + 唯一写缝 |
| `14c349c1` T4 | 四源文件（Import +6 / Metadata +9 / SessionBatch +21 / StackMerge +10）+ additive 5 法（四测试文件纯增行 33/39/60/113） | 恰合；E1 分支条件盖章合规（§4.3） |
| `1dbd4217` T5 | AGENTS.md +13（M6-2 节）+ GOAL-STATE +1 + TODO +2 | 纯 docs |
| `8c8727ba` T6 | SUMMARY + DECISIONS + ACCEPTANCE + ROADMAP/REQUIREMENTS/STATE/TODO | 纯 docs |

每提交 Conventional Commits 全英文 subject/body 亲读合规；无 wip/空提交。
第一路验收批 `dec16b1f`（ACCEPTANCE 重写 + minor-1 四行 + GOAL-STATE 续接点）
边界同样干净（§3）。

### 4.7 红线机检族（本路亲跑）

`git diff 2363549c..HEAD` 定向：`Pipe/History/` + `PipeCacheKey.swift` 零输出；
App/MCP/ 零输出；`*.metal` 全仓零输出；`LightamerIOP/` 零输出；`*.xcstrings`
零输出；Export Core+App 零输出；LibrarySchema/FilterPredicate/Presets 零输出；
appex 路径零输出；Project.swift diff = **恰 3 行测试登记**（dependencies 块零
diff，零新 SPM）；`grep -rn "\.runModal(" App/Sources` = 0；触碰文件 grep
UserDefaults = 零命中（零新键）。App 源码改动 = 恰两 plan 文件（numstat）。

## 5. 与第一路的分歧点与修正

1. **修正第一路观察项①（skip 段和 21 vs TOTAL 24）**：本跑段级 skip 和 =
   1+3+4+4+4+4+4 = **24 = TOTAL 24**，且脚本 :295 证 TOTAL 本就是段行逐值机械
   累加（无独立口径）——「脚本既有口径 quirk」不成立，系第一路对七段 skip 值
   的误计（其七段 BUNDLE 行本身 1/3/4/4/4/4/4 与本跑逐值一致）。对账结论无影响
   （两边 TOTAL 同为 3725/24/0）；M6-5 清算批候选中对应条目可销。
2. **观察项（账面口径，非阻塞）**：ROADMAP M6-2 行与 TODO M6-2 行记第一路
   「PASS / 0 error + 0 minor」，ACCEPTANCE 正本与 GOAL-STATE =「PASS / 0 error
   + 1 minor（当场修复）」——同一事实两处口径不一致（minor-1 已当场修复，零
   open 项，但账面应记发生数）。验收闭环批翻账时顺手订正 ROADMAP/TODO 两行。
3. **观察项（已知挂账复现，非本批引入）**：跑前删除的孤儿 fixture
   `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 全套轮后复活——M4-1 挂账
   #6 已登记行为（M6-1 挂账清单「孤儿 fixture 全套轮再生成」在案），与本批
   零关联，归 M6-5 清算批既有条目。

## 6. 独立发现（第一路未抓的新问题）

除 §5.1 的第一路误计修正外，**无新 error / minor 级发现**。排查过而排除的面：
JSON null 走 contains-true 落 nil 臂（正确）；2^32 Int decode 成功后被域门拒、
Double 臂同拒（正确）；`historyLoadedURL == url` 切回路径不 re-prime（幂等，
:1157 门亲证）；载体族四件 key 约定一致（url.path）；undo 到顶后写腿仍写
carrier 值 1（与 M2-8 pristine 判定面 items/position 正交，正确）；tile 驱动
零 renderProcess 重写（grep 全命中清单仅 8+init）；缩略图恒 legacy 由「生产
零传值」结构性保证（无需独立 policy，同零行为基线）。

## 7. 运行日志指针

本路全套日志 = `/tmp/m6-2-acc2-all.log`（TOTAL 行 + 七段 BUNDLE 行 +
`OK (direct launch, no testmanagerd)`）；七段分日志 = `/tmp/la-direct-tests-*.log`
（本跑覆盖，L055 双保险核对即取自此）。跑后孤儿 fixture 复活即证（§5.3）；
无残留 Lightamer 进程（`ps` 亲查 = 0）。
