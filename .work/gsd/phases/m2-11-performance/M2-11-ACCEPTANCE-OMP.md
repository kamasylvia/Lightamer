# M2-11 二次验收（omp 回溯，零共享上下文）

> 验收员 = omp 独立二次验收；基线 HEAD = `bade569`；终验日志（`/tmp/la-direct-tests-*.log`，2026-10-07）已轮转不可复核——凡涉净轮逐值的项，独立复核面 = 首验亲读记录 + 现盘可机检锚（测试文件/断言/证据文件/git 等价链），程序合规（禁全套 `--all`，本验收无授权）。
> 历史压缩注记：正本内 plan 级 SHA（`6031e1e`/`f9284ca`/`2129311`/`b5fa68a`/`3f91221`/`9586c1b` 等）全部悬空——公开仓压缩政策（AGENTS.md §2.2）合规动作，非证据缺失。本验收改走压缩后等价链（`9ad3bc4`/thumbnail 单文件/`4b589cc`/`d6b8d9c`/`33540d1`/`fa4b175`），逐项对表成立。

**PASS / 0 error + 1 minor**

## 逐 plan 判定

### M2-11-01 flaky 清算 — PASS

- selftest 亲跑：`Scripts/test-direct-selftest.sh` 12/12 ok，EXIT=0（与 01-ACCEPTANCE §1.1 逐行一致）；fixtures 三件在盘（`Scripts/test-direct-fixtures/{crash,singular,normal}.log`）。
- `parse_bundle_log` 在 `Scripts/test-direct.sh:75`；verdict 六集头注释 `:32-38` + 判定 `:130-146` 与 01-SUMMARY KD-1/KD-2 申报对表；ANE-DEGRADED 注记 `:148-149`、`:284`、`:288` + KD-3 注记 `:28-30` ✓。
- commit 等价链：`9ad3bc4`（同 subject）stat = 3 fixtures + selftest + test-direct.sh 共 5 文件 = 01-ACCEPTANCE §三申报集 ✓；thumbnail 硬化 = 单文件 `LibraryThumbnailBridgeTests.swift`（52+/5-）✓。
- D7 修复在位：`test-direct.sh:282` `peak_mb="${peak_mb%MB}"` ✓。

### M2-11-02 PERF 计量 — PASS

- revert 审计：squash `d72acfa` stat 14 文件无 `NLMeansModule`/`PixelPipe` ✓；minor-1 stale-label 注记在 `perf.md:63-68` ✓。
- 测试名在盘：`M2DefaultChainPerfTests.swift:138` `testM2DefaultChainPreviewWarm`、`:227` `testM2DragGateTwoChains`；`grep -c "func test"` = 2 ✓。
- 数字：perf.md §PERF-01（`:22-25` ARW 13.4/13.2、拖动 `:38-41` color 8.6-8.9 / nlmeans ~65/~57.5）与 VALIDATION Test Infrastructure 表逐值一致 ✓；§PERF-05 `:74-75` 0.172/0.194 ✓。

### M2-11-03 SpektraLab 两硬门 — PASS

- 门断言在码：`FullRenderBenchmarkTests.swift:273-275` Release 臂 `XCTAssertLessThan(warmMedian, 1000)`；`DrtTailTests.swift:470`、`:517` `XCTAssertLessThanOrEqual(median, 10)` + 前置命中语义断言 `:461-462`（hits>0/misses==0）、`:508-509`（misses==2/hits==1）✓。
- 测试名在盘：`testFullRenderWarmGate`（:153）、`testSameRecordSecondRunTimingAllHits`（:444）、`testEOTFTickTailReplayTiming`（:481）✓；func test = 1 / 14 ✓。
- commit 等价链：`4b589cc`（BUNDLE-MAP + Project.swift + FullRenderBenchmarkTests 3 文件）/ `d6b8d9c`（DrtTailTests 单文件）= 03-ACCEPTANCE §三申报集 ✓。

### M2-11-04 内存三分法 — PASS

- footprint 正本亲读：R1 T60 2427 / R2 T60 **1975** / R3 T60 1856 / R4 T60 1856 MB（`profile/r{1,2,3,4}-footprint-t60.txt`），中位 1975 ✓；minor-1/2 勘误在位（R1 T0 2392 ✓、`rss_kb` 1681312/1137152 ✓）。
- 口径③：`Scripts/test-direct.sh:70` `RSS_LIMIT_MB=8192`（:59→:70 漂移 04-ACCEPTANCE 已登记）✓。
- `testPreviewWorkingSetBoundedByInjectedBudget` 在 `MemoryBudgetTests.swift:552` ✓；func test = 14 ✓。

### M2-11-05 closeout — PASS

- 翻账等价链：`33540d1` = GOAL-STATE/TODO/REQUIREMENTS/ROADMAP/STATE/VALIDATION（136 行新建）6 文件 = 05-ACCEPTANCE §1.2 申报集 ✓；`grep -c "^- \[ \] \*\*M2" REQUIREMENTS.md` 亲跑 = **0** ✓。
- `.ips` 双栈亲读：0812 件 EXC_BREAKPOINT/SIGTRAP + `swift_unknownObjectRetain` ← `ToneEqualModule.dispatchPack` 链 ✓；0937 件 EXC_BAD_ACCESS/SIGSEGV + `Could not determine thread index for stack guard region` 逐字 + `_swift_release_dealloc` 链 ✓。
- hitch XML 亲解析：framewait n=804 max=**14.36ms** >50ms=**0**；hangs n=350 max=65.49ms >250ms=**0** ✓（obs-1 口径差复现确认：350 duration 格 vs 申报 351 行，判定不受影响）。
- MANIFEST 行 15-26 齐（12 件 t7-* + 3 XML + 3 footprint txt 全在盘）✓；O-2 `o2-footprint-z100.txt` peak **8557MB** ✓。
- §4.5 用户回批：`fa4b175` diff 亲证（①翻勾维持 ②修复批 ③签核追认推翻窗关闭 ④V2 按推荐）✓；修复批 `9bc5076`（M5）+ `e50b291`（M4）均在 HEAD 祖先链，去向闭环 ✓。

## 逐抽查点证据

1. **SC 三列抽查（7 条，超 ≥4）**：门① ARW 13.4/13.2（perf.md:23,25）✓；门② 0.172/0.194（perf.md:74-75）✓；门③ 1975MB（profile 正本）+ 8G 门（test-direct.sh:70）✓；门④ trace 双件在盘（profile/）✓；门⑤ framewait 14.36/>50=0（亲解析）✓；门⑦ 0.543s（首验 Sessions 日志亲读记录，日志已轮转，依赖首验）△；门⑧⑨ 168.2/300.6 + 0.021/5.009（perf.md:124-125,140-141 + 断言在码）✓。无证据 ✅ = 零项。
2. **脚本机检**：KD-1 parse 抽取（:75）+ KD-2 verdict 六集（:32-38/:130-146）+ KD-3 ANE 注记 + selftest 12 断言亲跑全绿，与 01-ACCEPTANCE 申报对表 ✓。唯一 minor：头注释 `:128` 优先级序（…> executed-0 > fail > ok）与代码分支序（fail `:142` 先于 executed-0 `:144`）文字不一致——两分支互斥（fail 要求 failed>0，executed-0 要求 failed==0），语义零影响，纯注释措辞。
3. **perf 账本对表（3 处）**：60fps 预算（13.4/13.2、8.6-8.9、~65/~57.5）/ 解码时延（0.172/0.194）/ 内存峰值（1975 中位）与 VALIDATION 表逐值一致 ✓。SPIKE 链：`M2-4-0-SPIKE.md:21-22`（<3G 数学不可达）+ `:59-63`（7865/5913/4589）与 test-direct.sh `:63-65` 同值引用互证 ✓。max peakRSS 7709 与首验 7710 差 ±1MB 取整（首验已注记），日志轮转不可独立复核 △。
4. **closeout 完整性**：frontmatter `milestone_closeout: M2`（VALIDATION:8）+ status validated + nyquist_compliant ✓；§4.4 M1-M7 + V1-V17 全带锚，M4/M5 经 §4.5 ② 走修复批且已落地 ✓；§4.5 四项在案 ✓。
5. **定向测试（1 类，禁全套遵守）**：`--bundle Layers GradeEnvelopePerfProbeTests`（无 env）= `BUNDLE|Layers|1/1/0|peakRSS=191MB|5s` verdict ok——skip 语义在位（日志 `Test skipped - manual probe — set LIGHTAMER_PERF_PROBE=1`），门控未把 skip 算 FAIL ✓。
6. **git 机检（2 plan 等价链，超 ≥2 实抽 4 组）**：01 波 `9ad3bc4`（5 文件）+ thumbnail 单文件 / 03 波 `4b589cc` + `d6b8d9c` / 05 波 `33540d1`（6 文件）/ `fa4b175`（+7 行），与各 ACCEPTANCE 申报集逐一对照 ✓。

## 与首验分歧点

无实质分歧。复现确认两项首验注记：obs-1（hangs 350 vs 351 口径差）亲解析复现；peakRSS 7709 vs 7710 取整差。新增 minor-1（注释优先级措辞，语义零影响）为本验收新发现。

## 会话卫生

- 只读验收：零源码/文档修改（唯一写入 = 本报告）；未 push。
- 定向测试 1 个（Layers probe，5s/191MB）；禁全套遵守；Lightamer 进程零残留（ps 仅见本验收进程自身）。

OMP-VERDICT: PASS
