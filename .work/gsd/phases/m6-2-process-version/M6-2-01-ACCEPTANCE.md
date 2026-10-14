# M6-2-01 ACCEPTANCE — 双重验收记录（config `dual_acceptance = true`）

> 制度：zcode 独立验收 PASS 后 → **串行** omp 二次验收（严禁并发——
> computer-use 单实例）。FAIL 回注修复批后重走验收。本 plan 零 GUI 面
> （OQ-6 范围边界）——omp 路以读码/机检/定向测试抽样为主，无实机走查面。
>
> **本文件第一路 = 真独立 subagent 验收批（2026-10-14，零共享上下文，实测
> 核验不轻信）**，取代此前执行 worker 自验披露节（该节已披露「非独立第三眼，
> 可按本清单重派」——orchestrator 据此重派本批；其证据指针凡仍有效者已并入
> 本表，原文字由本节取代）。第二路 omp 维持 E3 配额阻塞登记（文末）。

## 第一路：zcode 独立验收（AC 逐条 + 三审计节 + 数字门）

**结论：PASS / 0 error + 1 minor（当场修复）**
**对账树**：六提交 `3be89a19..8c8727ba`（基线 `2363549c`），未 push。

### 1. 全套独立复跑（亲跑数字，exec 后台任务 `caffeinate -dis Scripts/test-direct.sh --all`）

```
BUNDLE|IOP|686/1/0|peakRSS=7167MB|443s
BUNDLE|IOPParity|460/3/0|peakRSS=7741MB|770s
BUNDLE|Layers|474/4/0|peakRSS=1175MB|162s
BUNDLE|Library|671/4/0|peakRSS=618MB|78s
BUNDLE|Sessions|280/4/0|peakRSS=1625MB|72s
BUNDLE|Export|353/4/0|peakRSS=6406MB|202s
BUNDLE|App|801/4/0|peakRSS=2832MB|388s
TOTAL|3725/24/0|2115s        ← exit 0；OK (direct launch, no testmanagerd)
```

- **对账闭合**：3725 = 基线 3689（M6-1-VALIDATION 终验亲证值）+ 36（三新文件
  31 法 15+8+8 + additive 5 法 2+1+1+1）；**skip 恒 24 零新增**；七段
  peakRSS 全部 <8G 门（最大 IOPParity 7741MB），零 MEMFAIL 零 crash。
- **L055 双保险亲跑**：①七段日志末条 `Executed` 行逐段核对 = 「All tests」
  总计行且与 BUNDLE 行一致（686/460/474/671/280/353/801）②
  `terminated abnormally|Restarting after unexpected exit` 七段全零命中。
- 段级 skip 和（21）vs TOTAL skip（24）= 脚本既有口径 quirk——基线同款
  （M6-1 终验 3689/24/0 段和同为 21），本批零引入、非本批面；挂观察项（
  M6-5 清算批候选，与 L055 脚本级修复同族）。

### 2. AC 总表逐条（fresh evidence）

| AC | 生效值 | 独立复核证据 | 判 |
|---|---|---|---|
| 1 键面 | `process` 拼写冻结 + v10 bump + 三则语义 + 「入册 ≠ 升级」 | `LightamerSidecar.swift` `schemaVersionCurrent = 10` + v10 注记段逐行读码（含入册≠升级段）；decode lenient 表 + `encodeIfPresent` canonical 形亲读；SidecarV10Tests 三 byte-face + stored-0 归一 + FUTURE-version 全绿（全套亲跑） | ✓ |
| 2 hash/缓存纪律 | hash isolation + 零 history item + 传输零携带双负测 + 「非 legacy 才折」三处登记 + 键面零变化 | §4 hash isolation 审计节（下）；`testUndoToTopAndVersionSwapLeaveTheValueUntouched` + `testPasteTransportNeverCarriesTheProcess` + `testLightamerPresetCarriesNoProcessKey` 读码亲证；契约三处 = RenderProcess.swift 头注 + AGENTS M6-2 节 + DECISIONS §6 逐处亲读；seam ⑥ 第二 run `misses == 0`（ALL-HIT） | ✓ |
| 3 lenient 读腿 | 边界表（含 2.0→2）+ 损坏集全 nil 不毁档 + 存回 ABSENT + 前向大号保留 + 渲染钳 + pipe 面原值 | decode 表逐臂读码（Int 域门 1...0xFFFF_FFFF → Double 整值臂 → else nil，全 `try?` 永不 throw）；`testLenientLegalDomainBoundariesAreRetained`（1/2/0xFFFFFFFF + 重存不降级）+ corrupt 集 6 值 + `testForwardLargeNumberStampsVerbatim`（piece = 7 原值）+ `testResolvingClampTable` | ✓ |
| 4 零行为基线 | 0/1 逐位恒等 + 枚举账本 + bump 三层在册 + 零演示性 bump | `testRealChainRendersProcessZeroAndOneBitIdentical`（真 terminal trio 逐字节比）；枚举 case doc-comment 与 AGENTS 账本行双源比对一致；`git diff 2363549c..HEAD -- LightamerIOP/` 零命中亲跑 = 零 iop 观感改动 | ✓ |
| 5 迁移 UX 挂账 | 零迁移 UI/命令/MCP 面 + 挂账双登记 | `*.xcstrings` + MCP 面零 diff 亲跑；App diff = 恰两 plan 文件；DECISIONS §6 + GOAL-STATE 续接点挂账在案 | ✓ |
| 6 golden 四门 | G1..G4 | G1 = SidecarV10Tests 三 byte-face + hash isolation + CarrierTests ②；G2 = SeamTests ③④⑤ 三式（冻结门跨模拟分叉逐位 / 分叉可见 / 缺键=legacy sidecar→pipe 贯通）；G3 = SeamTests ② + ⑥ + IOPParity 460/3/0 零触碰；G4 = CarrierTests ①③④⑥ + additive 5 法——四门逐门读码 + 全套亲跑全绿 | ✓ |
| 7 零回归门 | 红线族零 diff + 既有族原样绿 | §8 红线机检族亲跑全绿；IOPParity 460/3/0 + Export 353/4/0 = 基线逐值一致（零触碰面双保险） | ✓ |
| 8 SC 数字门 | LIB +17 / LAYERS +8 / APP +8 / IOP +2 / SESS +1；全套 ∈ 3721..3727 | 全套亲跑：Library 654→**671**（+17）/ Layers 466→**474**（+8）/ App 793→**801**（+8）/ IOP 684→**686**（+2）/ Sessions 279→**280**（+1）/ Export 353 / IOPParity 460 逐值精确；合计 **3725/24/0** = 3689+36 精确闭合 | ✓ |

### 3. schema bump 审计（灵魂）

- **9→10 additive 零漂移负测完备性**：三 byte-face 全过——①v9 档
  digit-rewound decode→re-encode **逐字节**（`testV9FormDocumentDecodesAndReencodesByteExact`，
  断言 re-encoded == 原 v9 字符串）②v10 nil-face writer 与 v9 shape 唯一
  diff = schemaVersion 数字（`testNilProcessFace...`，且 `process` 键断言
  ABSENT）③process=1 档 round-trip byte-faithful。**既有测试族零编辑亲证**：
  六提交对 Tests/ 的 numstat = 七文件全为纯增行（0 删行），既有 byte-face 族
  零触碰、符号化 `schemaVersionCurrent` 引用自动传播。
- **tolerant decode 读码**：`init(from:)` 内 v10 段全 `try?` 永不 throw——
  键缺席 → nil；Int 命中 `1...0xFFFF_FFFF` → 原值（**前向大号保留**）；Int
  失败/域外 → Double 臂（整值 + 同域才收，`2.0`→2、`2.5` 拒）；其余一切
  （stored-0/负/字符串/null/数组/2^32）→ nil **不毁档其余字段**。损坏 →
  legacy 不保留（`testCorruptValueIsNotRetainedOnRewrite` + CarrierTests ④
  真盘 corrupt `"x"` 重存无键）。
- **stored-0/corrupt 归一化 ABSENT**：decode 即 nil（M1 存储门 1 起）→
  re-encode `if let process` 恒 ABSENT（`testStoredZeroNormalizesToAbsentKey`
  钉死；0 ≡ 缺键 ≡ legacy 同一语义，LightCraft `skip_serializing_if` 同构）。
- **旧档 re-encode 键恒 ABSENT 字节零漂移可测性**：App 级真盘链钉死——
  CarrierTests `testLegacyDocumentReSavesWithTheKeyAbsentAndKeysPreserved`
  （v9-era 手写档 → load → 编辑 → 重存 `process` ABSENT + schemaVersion 10
  （writer 面）+ 既有键/首 item 逐字节保全 + 无 drift）。
- **M1 双门分离**：值类型域门 `init?(rawValue:)` = `0...0xFFFF_FFFF`（含
  legacy=0 哨兵）；sidecar 存储门 = `1...`（stored-0 → nil）。两门各自测试
  钉死（`testVersionTypeDomainGateAndConstants` /
  `testStoredZeroNormalizesToAbsentKey`），三处代码注记亲读在位。

### 4. hash isolation 审计

- **机制本体亲读**：`driftDetected`（LightamerSidecar.swift :1088）五元折叠
  `stack / decodeParamsHash / layerSnapshot / drtRecord / filmRecord`——
  process **结构性不在折叠公式可见域**；`HistoryHash.swift` 本批零 diff
  （`git diff 2363549c..HEAD -- LightamerCore/Sources/Pipe/History/
  PipeCacheKey.swift` 零命中亲跑）。
- **测试钉死**：`testProcessIsHashIsolated`（同 stack ± process(nil/1/7) →
  historyHash 逐字节同 + driftDetected 三 false + layerStack 不变）+
  CarrierTests ⑤（undo 到顶 + branch + swap 重存仍 1，items 逐条断言无
  `process` 键 = 零 history item 面）。
- **分叉点折键契约**：M6-2 零分叉 = `PipeCacheKey.swift` 零改（亲跑零
  diff）；「非 legacy 才折」契约三处登记逐处亲读（RenderProcess.swift 头注
  KD-6 段 / AGENTS M6-2 节 / DECISIONS §6③）；seam ⑥ 同链同参仅 process
  异两 run → 键恒等 + 第二 run misses==0（缓存键面零变化的行为级证明）。
- **Copy Adjustments / 预设 / 版本 swap 零携带**：payload 类型
  `AdjustmentTransferPayload(records/snapshot/drtRecord)` 结构性无 process
  座位（CarrierTests ⑥ 真盘负测：源档 =1 贴入 legacy 目标重存仍 ABSENT）；
  `LightamerPreset` 容器无键负测（SidecarV10Tests 6b）；版本槽不承载
  process（versions[0] 键面断言 + 版本链并存 round-trip，SidecarV10Tests
  6a）。

### 5. mint 面 5 出生点 + 第六处普查

- **全仓生产 `LightamerSidecar(` 构造点亲数 = 恰 6 处**（grep 亲跑）：
  coordinator 写腿（PipeCoordinator :1523，carrier 驱动）/ ImportService
  :681（AI 副本，`process: .current`）/ StackMergeService :2220 + :2679
  （HDR / Mertens+Pano 两 writer，`process: .current`）/ MetadataService
  :202（pristine 臂，`.current`；既有档臂 `mutate(&document)` 真 inout
  round-trip 零改自动保全——diff 亲证零触碰）/ SessionBatchApplier :149
  （E1 分支条件盖章）。**无第六处漏报**（旁证：`SidecarStore(` 生产构造
  仅 2 处；BatchSidecarWriter 只写已构造档不产新档）。
- **E1 合规性**：`processStamp: RenderProcessVersion?` per-arm 提升（既有
  档臂 = `document.process` 原值含前向大号照搬 / pristine 臂 = `.current`），
  构造点传 `process: processStamp`；跨臂 `?? .current` 禁令注记在提升点与
  构造点两处在位（读码亲证）；三态一法测试
  （`testBatchApplyStampsProcessBranchConditionally`：pristine=1 + legacy
  保 ABSENT / 1 保全 / 前向 7 保全）与 checker 处方逐字对应。
- **既有档 read-modify-write 臂自动保全零改**：仅 MetadataService 成立
  （真 round-trip）；SessionBatchApplier 按修正后处方显式携带（E1 修复批
  front-matter 三行同批修订兑现——DECISIONS §1 双登记在案）。

### 6. 管线缝 armed（零消费即零行为）

- 八构造点亲证（checker M3 清单）：PixelPipe tailPipe/filmPipe/replayPipe
  三处继承 + LayerCompositeDriver basePipe/layerPipe/terminalPipe 三处继承
  + no-op throwaway 豁免注记在位 + 静态入口属性赋值 = 恰 8 点（读码逐点
  过）；IOPiece stamp 在 `forwardWalk` 与 pipeType 同位一次性、不入
  paramsHash（注记亲读）；`process`/`processComposite` 双入口 additive
  缺省 `.legacy`。
- **生产零传值亲证**：`grep renderProcess:` 生产面命中仅为声明/缺省参/
  processComposite→composite 一处转发；`resolving(` 生产消费点 = 0（仅
  doc 注记）——零行为结构证明 + G3 行为级双证（0/1 真链逐位恒等 + 缓存
  第二 run 全 HIT）。coordinator 传值接线挂账 DECISIONS §6 在案。

### 7. 逐 commit 边界（六提交 vs front-matter）

| commit | 交付 | 边界核验 |
|---|---|---|
| `3be89a19` T1 | RenderProcess.swift（新）+ LightamerSidecar v10 + SidecarV10Tests（新 15 法）+ Project.swift +1 + BUNDLE-MAP +7 | diff 面与 front-matter 恰合；sidecar 面 = schemaVersion 注记 + 字段 + init 默认参 + CodingKeys + decode/encode，无越界 |
| `72e6d22d` T2 | IOPiece + PixelPipe + LayerCompositeDriver + SeamTests（新 8 法）+ Project.swift +1 + BUNDLE-MAP +1 | 恰合；八构造点全落两 plan 文件内 |
| `a33a6afd` T3 | WorkspaceModel +38 / PipeCoordinator +26 + CarrierTests（新 8 法）+ Project.swift +1 + BUNDLE-MAP +1 | 恰合；load 腿双分支 + makeSidecarDocument 单写缝 |
| `14c349c1` T4 | ImportService/StackMergeService/SessionBatchApplier/MetadataService + additive 5 法（四测试文件纯增行） | 恰合；E1 分支条件盖章合规（§5） |
| `1dbd4217` T5 | AGENTS.md +13（M6-2 节）+ GOAL-STATE + TODO | 纯 docs；机检族在其 commit message 申报面 |
| `8c8727ba` T6 | SUMMARY + DECISIONS + ACCEPTANCE + ROADMAP/REQUIREMENTS 注记 | 纯 docs；omp 批未破坏原始交付面（本批无 omp 执行波，六提交即原始交付面，逐提交对树读码无后续覆盖） |

- 每提交 Conventional Commits 全英文 subject/body 符合约定；无 wip/空提交。
- **红线机检亲跑**（基线 `2363549c`）：History/ + PipeCacheKey 零 diff；
  MCP 面零 diff；`.metal` 全仓零 diff；LightamerIOP/ 零 diff；`*.xcstrings`
  零 diff；Export Core+App 零 diff；LibrarySchema/Presets/FilterPredicate
  零 diff；Project.swift diff = 恰 3 行测试登记（dependencies 块零 diff）；
  `\.runModal(` App/Sources 零命中；触碰面 UserDefaults 零直读——**零新键**。
  App 源码改动 = 恰两 plan 文件。

### 8. 发现与处置

1. **minor-1（当场修复）**：front-matter 申报「BUNDLE-MAP 四既有行 method
   数更新（E2 纪律，随各自任务 commit）」未兑现——四既有行 stale
   （StackMerge 11→13 / Import 10→11 / Metadata 11→12 / SessionBatch
   12→13，新块注记「行内 method 数以终态对账为准」部分披露）。处置 =
   验收批实测四文件 `grep -c "func test"` 后原位修复（本批 commit 随带）。
   除此之外执行申报三偏差（resolving 负数测试改式 / CarrierTests
   flushUntil 内容谓词轮询 / SeamTests 7→8 拆分）读码亲证与登记一致，
   零产线改动属实。
2. **观察项（非阻塞）**：①段级 skip 和 21 vs TOTAL 24 = 脚本既有口径
   quirk（基线同款，非本批引入，M6-5 清算批候选）；②ROADMAP M6-2 行 ✅
   翻账与 TODO 勾选诚实地挂在验收闭环批（dual_acceptance 门控第二路），
   非本路阻塞。

## 第二路：omp 二次验收（串行，第一路 PASS 后派）——**E3 配额阻塞，待补**

**状态：未完成（E3——omp 账户用量配额耗尽），非 FAIL。** 派发链三次尝试
逐次诊断（2026-10-16 凌晨，串行无并发）：①直连（死代理 env 残留）→
`Unable to connect`；②清 env 直连 → `unknown certificate verification
error`；③按 §6 起 xray（`px --up`）后经代理重派 → **`429 Go usage limit
exceeded` `retry-after-ms=423247000`（≈4.9 天）**——配额硬顶非瞬时；
lane_retry 语义下不重试。任务书存 `/tmp/m6-2-omp-lane2-prompt.txt`；
xray 已 `--stop`。

**处置**：第二路挂起待 orchestrator（配额恢复后按原任务书串行重派，或晨审
裁定以第一路独立验收 + 本批机检证据链签核）。第一路全套 `--all` 亲跑
3725/24/0 + 三审计节 + 红线机检族不受此阻塞影响。
