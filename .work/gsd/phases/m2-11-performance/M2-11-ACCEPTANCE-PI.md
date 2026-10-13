# M2-11 二次验收（PI 路，双路并发批，零共享上下文）

> 验收员 = PI 路独立二次验收；报告日期 2026-10-10（批次口径）；HEAD = `60a7ed88`。
> 方法 = 亲读 5 份 ACCEPTANCE 正本 + M2-11-ACCEPTANCE-OMP.md + 仓库面独立机检（读码/git show·log/grep·wc/正本数值复算 + XML 独立重解析），不照抄上一轮结论；测试默认不跑（净轮值引用首验在案记录；10-07 轮 /tmp 日志已轮转不可独立复核项标 △）。
> 历史再压缩注记（本验收新查明）：上一轮报告所引「压缩后等价链」SHA（`9ad3bc4`/`4b589cc`/`d6b8d9c`/`33540d1`/`fa4b175`/`9bc5076`/`e50b291`）在现 HEAD/release 两 refs **全部悬空**——release 分支其后再重写（现 M2-11 squash = `d72acfa4`）。属 phase 后演进，不记账；本验收独立换锚验证（见分歧项 D1）。

**PASS / 0 error + 2 minor**

## 逐抽查点证据（上一轮抽查点清单独立重验，8 项超 ≥4）

1. **门断言读码（03 两硬门在码）**：`Tests/LightamerTests/FullRenderBenchmarkTests.swift:273-277` Release 臂 `XCTAssertLessThan(warmMedian, 1000, …)` + Debug `10000` 病态界；`DrtTailTests.swift:471/:518` Release 双腿 `XCTAssertLessThanOrEqual(median, 10)` + Debug 25 松界；前置命中语义断言在计时断言之先逐帧（腿① `:462-463` hits>0∧misses==0；腿② `:516-517` misses==2∧hits==1）✓。行号较上一轮（:470/:517）漂移 = 后演进，不记账。func test 计数亲数：FullRender 1 / DrtTail 14 / M2DefaultChainPerf 2 ✓（BUNDLE-MAP :160/:161/:334 行值逐一相符，Project.swift :404/:416/:511 登记在位）。
2. **perf.md 预算值对账（与 VALIDATION 表逐值）**：ARW warm 13.4/13.2（perf.md:23,25）、拖动 color 8.6-8.9/denoise ~65/~57.5（:39-41）、PERF-05 0.172/0.194（:74-75）、门① 168.2/300.6（:124-125）、门② 0.021/5.009（:140-141）、内存中位 1975（:233-235）——与 05-ACCEPTANCE §1.1 SC 表逐值一致 ✓。唯 PERF-07 0.543s：/tmp Sessions 日志为 10-13 后演进轮覆写件，10-07 原轮不可独立复核，依赖首验亲读记录 △（非本批新缺口）。
3. **footprint 正本亲读（04 口径①）**：`profile/r{1,2,3,4}-footprint-t60.txt` phys_footprint = 2427/**1975**/1856/1856 MB（中位 1975 ✓）；`r1-footprint-t0.txt` = 2392（minor-1 勘误后正本值 ✓）；rss_kb 1681312/1137152（minor-2 勘误口径 ✓）；`o2-footprint-z100.txt` peak **8557 MB** + 稳态 2982 ✓。四轮 T60 带 1.8-2.4GB、≤3GB 稳态门（OQ-1-A 裁决锚稳态不锚瞬态）判定成立。
4. **性能探针惯例 + L014（范围注记指定项）**：`LIGHTAMER_PERF_PROBE=1` + `XCTSkipUnless` 门在 `GradeEnvelopePerfProbeTests.swift:108-110`、`ColorMatchBakeGoldenTests.swift:266-268`（后演进文件，惯例延续在位）；M2-11 本批件 `M2DefaultChainPerfTests.swift` 头注 :28「L014 drain before every clock stop」+ `drain()` :53-56（fence commit/waitUntilCompleted）+ 读钟前 drain 用例 :122/:270/:278 + 样张缺席 `XCTSkip` :145/:234（栅门式 = 样张 XCTSkip，与 02 增行记录「fixture 在场即跑非 env 门控」口径一致）✓。
5. **test-direct.sh 机检（01 flaky 清算）**：`parse_bundle_log` 在 :75；`RSS_LIMIT_MB=8192` 在 :70；MEMFAIL 判定 :139-141（含 SPIKE ±3% 方差注记）；verdict 六集 + crash/no-total-line 计数置零（L055）在 :128-148；selftest `Scripts/test-direct-selftest.sh`（SELFTEST OK 行 :69）+ fixtures 三件在盘 ✓。
6. **.ips 双件 + hitch XML 独立重解析（05 closeout）**：0812 件 `"type":"EXC_BREAKPOINT","signal":"SIGTRAP"` + `swift_unknownObjectRetain` + `ToneEqualModule.dispatchPack(...)` 符号亲证；0937 件 EXC_BAD_ACCESS/SIGSEGV +「Could not determine thread index for stack guard region」逐字 + `_swift_release_dealloc`/`doDecrementSlow` 链 + `LutPanelView.importLut()`/`NSSavePanel runModal` 帧 ✓。XML 重解析（regex on fmt 格）：framewait n=804 max **14.36ms** >50ms=**0**；hangs n=350 max **65.49ms** >250ms=**0**——obs-1 口径差（350 格 vs 申报 351 行）独立复现，判定不受影响 ✓。
7. **缓存预算（04，PipeCache.enforceBudget）**：`LightamerCore/Sources/Pipe/PipeCache.swift:210` `enforceBudget`、:214 `floor = min(Self.evictTarget, byteBudget * 2 / 3)`、:269 `guard trackedBytes > floor else { break }` —— hysteresis 产线语义在码（04-ACCEPTANCE §四读码复确认）；`MemoryBudgetTests.swift:552` `testPreviewWorkingSetBoundedByInjectedBudget` 精确台账语义（700 稳态 no-op / floor 666 / 600 止扫）在 :554-590 带 ✓。
8. **closeout 完整性 + 修复批闭环**：VALIDATION frontmatter `status: validated` + `milestone_closeout: M2` + nyquist_compliant（:4-8）；`grep -c "^- \[ \] \*\*M2" .work/gsd/REQUIREMENTS.md` 亲跑 = **0** ✓；M2-10 十项落位（#5/#9/#10 本轮关闭）在挂账总汇编节 ✓；§4.5 ② 修复批两 commit `2ac80b53`（ToneEqual M4）/`a902f065`（LUT 面板 M5）均 `merge-base --is-ancestor HEAD` 亲证 ✓。
9. **8G 运行门口径注记（范围注记指定，不记 M2-11 账）**：`RSS_LIMIT_MB=8192` 现盘在位（test-direct.sh:70）；MEMFAIL 行内自带 SPIKE 证伪注记（「贴线 bundle 连续破线先查重测顺序漂移，±3% 方差见 SPIKE 70e09e5」）——<3G 旧门证伪口径在案引用，现状一致，无回归。

## 分歧项（与上一轮 M2-11-ACCEPTANCE-OMP.md）

- **D1（等价链锚不可复核——后演进，不记账，结论不受影响）**：上一轮所引压缩后等价链 SHA（9ad3bc4/4b589cc/d6b8d9c/33540d1/fa4b175/9bc5076/e50b291）现全 refs 悬空（`git rev-parse` 全 fatal）——release 分支其后再次重写（30 commit 每 phase 一 squash，M2-11 = `d72acfa4`）。非上一轮误判（其时点在案），本验收独立换锚：release `d72acfa4` stat = **14 文件**（M2DefaultChainPerf/FullRenderBenchmark/DrtTail/MemoryBudget/QuickLookPerfProbe/LibraryThumbnailBridge/AIWorkerClient 七测试件 + test-direct.sh + selftest + 3 fixtures + Project.swift + WorkspaceHostView）与 01-05 申报面同构、无 NLMeansModule/PixelPipe（02 revert 审计口径成立）；HEAD 粒度链 `9827751d`（03 T1）/`161cac9c`（04 T2）在位。交付面等价性由新锚背书。
- **D2（上一轮漏检——本验收新发现 minor-1）**：BUNDLE-MAP `IOP	13	MemoryBudgetTests.swift`（:149）行值滞留 13，现盘 `grep -c "func test"` = **14**（第 14 法 `testPreviewWorkingSetBoundedByInjectedBudget` 由 `161cac9c` 落盘，13→14 与 04-ACCEPTANCE §五申报一致）；02/03 批的增行纪律（「DrtTailTests 行 12→14 同批」「行内 method 数终态」）未在 04 批执行——无 13→14 行值更新、无 M2-11-04 增行记录。首验与两轮 omp 均未捕获。影响面：对账台账计数列陈旧一行为（该文件自身注记「对账以运行期 Executed 为准」），零功能影响。可修性 = **小修**（单行行值 13→14 + 可选增行记录两行）。
- **D3（上一轮 minor 独立复确认，一致非分歧）**：verdict 优先级注释措辞（test-direct.sh:128「…> executed-0 > fail > ok」vs elif 实序 fail 先于 executed-0 :131-145）亲读复现——两判定互斥（failed>0 蕴含 executed>0，executed-0 要求 executed==0），语义零影响，维持 minor 定级。

## minor 汇总

- minor-1（新发现，本验收）：BUNDLE-MAP MemoryBudgetTests 行值 13 vs 现盘 14 法（D2；小修）。
- minor-2（上一轮 minor 独立复确认）：test-direct.sh:128 verdict 优先级注释措辞与代码分支序不一致（D3；小修/可仅改注释）。

## 会话卫生

- 只读验收：零仓库文件修改（唯一写入 = 本报告）；未 push；测试零复跑（引用首验在案终值）；未触发任何 Lightamer 进程（`ps` 无 GUI/宿主实例）。
- 净轮逐值项（10-07 轮 /tmp 日志已轮转）依赖首验 + 03/04 验收轮双重复核记录 + release squash/HEAD 粒度链交付面等价背书，程序合规。

PI-VERDICT: PASS
