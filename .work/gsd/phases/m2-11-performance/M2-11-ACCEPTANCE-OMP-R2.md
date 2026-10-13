# M2-11 回溯二次验收 R2（OMP 双路并发批）

> 验收员 = OMP 独立二次验收；日期 = 2026-10-10；HEAD = `60a7ed88`。
> 方法 = 五正本亲读 + 上一轮报告抽查点提炼后独立重验机检项（file:line/命令/计数），结论独立取证。
> 口径注记：HEAD 远超 M2-11 收官；后演进差异逐处标「后演进，不记账」。根 AGENTS.md 无 M2-11 架构增量节（grep `M2-11|m2-11` 零命中）——方法第 1 条该子项无物可读，非缺口。

**PASS / 0 error + 1 minor**

## 独立重验（上一轮抽查点提炼，≥4 机检项实抽 9 组）

1. **selftest 亲跑**：`./Scripts/test-direct-selftest.sh` 尾行 `SELFTEST OK (…3 fixtures + 2 constructed)`，12 ok 全绿。fixtures 三件在盘。与 01-ACCEPTANCE §1.1 逐行一致 ✓
2. **判定脚本锚**：`Scripts/test-direct.sh:75` `parse_bundle_log()`；verdict 六集注释 `:128` + 分支 `:131-146`；ANE 注记 `:28`、`:149`；D7 剥单位 `:282` `peak_mb="${peak_mb%MB}"`。minor 沿用：`:128` 注释序（…> executed-0 > fail）与代码序（fail `:142` 先于 executed-0 `:144`）文字不一致——两分支互斥（failed>0 vs failed==0），语义零影响，纯注释措辞 ✓（minor-1，本验收认定 1 minor 即此）
3. **探针惯例（对象卡指定）**：`Tests/LightamerTests/GradeEnvelopePerfProbeTests.swift:108-109` `XCTSkipUnless(ProcessInfo…["LIGHTAMER_PERF_PROBE"]=="1")`；`M2DefaultChainPerfTests.swift:53` `drain(_:)` + `:122` frame 内 `drain(metal)` 在读钟前；T2 `measure()` `:270/:278` drain 在读钟前；DrtTailTests `render` helper 内 fence。L014 纪律在码 ✓
4. **预算/实测对账（对象卡指定）**：perf.md `:23` ARW 13.4ms、`:74-75` 0.172/0.194s ✓门、`:124-125` 168.2/300.6ms <1s ✓、`:140-141` 0.021/5.009ms ≤10ms ✓、`:233-235` 中位 1975MB ≤3GB ✓；profile 正本 R1/R2/R3/R4 T60 = 2427/1975/1856/1856 MB 亲读一致 ✓
5. **硬门断言在码**：`FullRenderBenchmarkTests.swift:274` Release `warmMedian, 1000`（:277 Debug 10000 病态界）；`DrtTailTests.swift:470/:517` Release `median, 10` + 前置逐帧断言 `:461-462` hits>0/misses==0、`:508-509` misses==2/hits==1 ✓；func test = 1 / 14 ✓
6. **缓存预算（对象卡指定）**：`LightamerCore/Sources/Pipe/PipeCache.swift:210` `enforceBudget` + `:214` floor hysteresis + `:276-278` 越界日志；`MemoryBudgetTests.swift:552` `testPreviewWorkingSetBoundedByInjectedBudget`，func test = 14 ✓
7. **framewait XML 亲解析**：`profile/framewait-zoompan.xml` duration 格 n=804（811 行含 7 空）、max=14.36ms、>50ms=0 ✓；O-2 `o2-footprint-z100.txt:7` peak 8557MB ✓；双 .ips 亲读：0812 EXC_BREAKPOINT/SIGTRAP、0937 SIGSEGV + `Could not determine thread index for stack guard region` 逐字 ✓
8. **closeout 机检**：`grep -c "^- \[ \] \*\*M2" REQUIREMENTS.md` = 0 ✓；`M2-11-VALIDATION.md:8` `milestone_closeout: M2` ✓；PERF-07 0.543s 在 perf.md `:296` ✓
9. **git 等价链（后演进重建）**：上一轮等价链 SHA（9ad3bc4/4b589cc/d6b8d9c/33540d1/fa4b175/9bc5076/e50b291 + 基线 bade569）现全部悬空——压缩政策再压缩所致，后演进不记账。现盘后继链：squash `d72acfa4`（stat 含 7 测试文件 +1079/-55：M2DefaultChainPerfTests 338 行/DrtTailTests +120/FullRenderBenchmarkTests 281 行/MemoryBudgetTests +85 等）✓；M4/M5 修复批 `2ac80b53`（ToneEqual guard）+ `a902f065`（LUT panel hop）均在 HEAD 祖先链 ✓；用户回批 `c91cb314`（closeout rulings）在位 ✓

## 运行门 8G 口径注记（对象卡指定，不记账）

`Scripts/test-direct.sh:70` `RSS_LIMIT_MB=8192` 现状在位；`:141` MEMFAIL 判据引用 SPIKE `70e09e5` ✓。<3G 旧门证伪链归 M2-4-0 账，本验收仅确认接口现状无漂移。

## 分歧项

1. **等价链 SHA 悬空**：上一轮 §逐 plan 判定/抽查点 6 所列 7 个 SHA 现全悬空（`git cat-file -t` 逐个 fatal）。非上一轮误判——HEAD 演进后再压缩所致；本验收以后继链（d72acfa4 + 2ac80b53/a902f065 + c91cb314）重建等价，结论方向一致。后演进，不记账。
2. **其余零分歧**：上一轮 minor-1（注释措辞）本验收复现确认仍在位，转为本报告 minor-1；obs-1 口径差（framewait 空格 7 格 vs 申报口径）亲解析复现，判定不受影响；门⑦ 0.543s 本轮在 perf.md :296 亲见（上一轮△依赖首验处本轮已补亲证）。

## 会话卫生

只读验收：唯一写入 = 本报告；未跑测试套件（selftest 脚本 + XML 解析除外）；未 push；零实机走查（双路并发纪律）。

OMP-VERDICT: PASS
