# M2-4-0 SUMMARY — test bundle 拆分（执行收口 2026-09-30）

**执行 = ZCode subagent worker（夜间连跑授权 + 派发指令授权，晨审可推翻）**
**起点 = `7427cd6`（checker 修正版 plan）**

## 结论头

**PASS / 0 error + 1 硬门未达（AC-2，停机上报 OQ）**

- 计数对账、门控归属、零源改动、一条命令、归属完备：**全过**。
- **内存硬门（AC-2）未达**：D5 预案（第 7 bundle）已按预声明线执行并验证，**仍 3 bundle
  破门**（IOP 7654MB / Export 6659MB / IOPParity 5788MB，ru_maxrss 精确口径）。按 plan
  T3「任一硬门破线 → 停 + OQ，不自行绕」停机。**全套回归的 <3G 硬门在当前 4-7 bundle
  粒度下不可达**（见「内存事实」节），需要 orchestrator/用户裁决下一档方案。

## 交付物

| commit | 内容 |
|---|---|
| `eca777c` | T1：单 LightamerTests → 六域 target + E1 豁免（ChainBuilderHelpers.swift + 30 文件调用点机械改写，2165 零增量） |
| `281bda9` | D5 预案：LightamerTestsIOPParity 第 7 bundle（MEMFAIL 触发，成员含编译闭合微调，见 DECISIONS） |
| `46bf1c7` | T2：test-direct.sh 多 bundle 跑法（--bundle/--all/BUNDLE+TOTAL 行/时间法 RSS/MEMFAIL 机检） |
| （本提交） | T4：SUMMARY/DECISIONS + AGENTS.md（资源监控过渡条款更新 + 测试落域约定）+ GOAL-STATE + TODO + LESSONS |

**未 push。**

## AC 对账表

| # | 断言 | 结果 | 证据 |
|---|---|---|---|
| 1 | 计数对账 2165/14skip + δ=0 + 测试方法零增量 | **PASS** | 七 bundle executed 和 = 2165 精确；skip 和 = 14 精确；`grep -rcE '^\s*(func test\|@Test)' Tests/LightamerTests` = 2165（E1 后复核）；逐域 BUNDLE 行 vs BUNDLE-MAP 静态计数**逐域相等**（下表） |
| 2 | 任一 bundle 单宿主峰值 RSS <3G | **FAIL（停机 OQ）** | ru_maxrss（/usr/bin/time -l，内核精确峰值）：IOP **7654MB** / Export **6659MB** / IOPParity **5788MB** 破门；其余 4 bundle 过门 |
| 3 | 总时长 ≤1135s（1.5×756.7s） | **PASS（口径注记）** | 七 bundle 单跑时长和 = 704s ≤ 1135s。注：MEMFAIL 停机故未跑最终 `--all` 整轮；单跑和为上界估计（`--all` 逐 bundle 独立进程，行为同构）。IOP 单跑时长方差大（352s/455s/115s 三轮——冷热缓存差） |
| 4 | 门控归属（9 变量全清单） | **PASS** | grep 审计逐一核对：LA_CATALOG_BENCH→SESS（CatalogBenchmarkHarness）/ LA_PERF07_VOLUME→SESS / LA_LIBRARY_BENCH→LIB / LA_THUMB_BENCH→LIB（LibraryGridModelTests）/ LA_QL_PERF→EXPORT / LA_REGEN_YIYIN_GOLDEN→EXPORT（YiyinWatermarkTests）/ LIGHTAMER_MCP→APP 三文件（门体在测试文件内，按实位）/ LIGHTAMER_FULL_IOP_FACE→APP 使用（McpHostTests；生产门体 LightamerIOP/Sources/Registry.swift 不在 diff 面）/ LIGHTAMER_RAW_SAMPLES_DIR→共享 Fixtures.swift（随宿主生效）。不设 env 跑 = skip 形态逐 bundle 确认（对账 skip=14 即证） |
| 5 | 测试源零改动（E1 豁免集单列） | **PASS** | `git diff --name-only 7427cd6..HEAD`：Tests/ 面 = ChainBuilderHelpers.swift（新）+ 30 调用点改写文件（E1 豁免集，逐文件对账 D1 E1 清单）；`LightamerCore/`、`LightamerIOP/`、`App/` 零出现；改动行均非测试方法行（AC-1 零增量兜底） |
| 6 | 全套一条命令 | **PASS** | `Scripts/test-direct.sh` 无参 = --all；BUNDLE 行×7 + TOTAL 行 + 总退出码（fail/executed=0/RSS≥3G 任一非零） |
| 7 | 归属完备无重复 | **PASS** | 数组并集 = 231 域文件唯一归属（comm 对 on-disk 双向零差）；SHARED 3 文件编列 Fixtures×7 / ParityGate×7 / ChainBuilderHelpers×7（D5 后 IOPParity 与 IOP 同构列法） |

## 七 bundle 实测矩阵（2026-09-30，全部 /usr/bin/time -l ru_maxrss 精确口径）

| bundle | executed/skipped/failed | peakRSS (MB) | 时长 (s) | vs BUNDLE-MAP |
|---|---|---:|---:|---|
| IOP | 457/1/0 | **7654** ⛔ | 115 | 457 ✓ |
| IOPParity | 308/2/0 | **5788** ⛔ | 234 | 308 ✓ |
| Layers | 164/2/0 | 944 | 18 | 164 ✓ |
| Library | 430/4/0 | 292 | 16 | 430 ✓ |
| Sessions | 279/4/0 | 1593 | 70 | 279 ✓ |
| Export | 260/1/0 | **6659** ⛔ | 196 | 260 ✓ |
| App | 267/0/0 | 1276 | 55 | 267 ✓ |
| **Σ** | **2165/14/0** | — | **704** | **2165 ✓** |

- 拆分前单宿主（765 tests 旧 IOP）：6975MB/352s、8141MB/455s 两轮复现（触发 D5 的证据）。
- 拆分前全套 2165 基线（GOAL-STATE）：756.7s、ps 口径峰值 3.73G（**严重低估**——ps 1s
  轮询漏瞬态峰，时间法精确口径约 2×；LESSONS L045）。
- 在案 flaky `LayerE2ERoundTripTests`（Layers 域）：本轮**未触发**（Layers 164/2/0 全绿
  18s），零处置。

## 内存事实（OQ 决策依据）

1. **积累近线性于测试数，跨域同病**：IOP ≈16.7MB/test、Export ≈25.6MB/test、
   IOPParity ≈18.8MB/test、Sessions ≈5.7MB/test、App ≈4.8MB/test、Layers ≈5.8MB/test、
   Library ≈0.7MB/test。渲染/kernel 密集域（IOP、Export-E2E/yiyin、IOPParity）同型。
2. **外推**：2165 tests × ~17MB ≈ 全 suite 累计 ~37G——<3G 硬门需 **~12+ bundle**；
   D5 预声明单拆 IOP（7 bundle）只把最大宿主从 8.1G 降到 7.7G（IOP），**且 Export 域
   独立在 6.7G 破门**——D5「kernel 集中于 IOP」的前提被数据证伪。
3. **D5 预案已用尽**：第 7 bundle 落地 + 编译闭合 + 双 bundle 复测仍破。按 D5「不得
   未经批准自行加 bundle」「不得为凑 6（7）放宽内存门」停止。
4. **下一步决策点（需 orchestrator/用户裁决，非本 plan 范围）**：
   - (a) 放宽硬门到机器现实档（如单宿主 <8G + 运行监视 + >8G 即杀的现行口径），以
     7 bundle 现状为常态（较拆分前 10.4G 单点已显著改善且可定向跑）；
   - (b) 继续细拆渲染密集域（IOP/IOPParity/Export 各再拆半 → ~10-12 bundle）；
   - (c) 产品代码排障积累根因（CIContextPool/Metal 堆/PipeCache 跨测试驻留？——本 plan
     零产品源红线未触碰；属独立调查 plan）。
   - 推荐：先 (c) 小 spike 定性积累是否可释（若一处 clearCaches 能塌掉 70% 即 (a)(b)
     皆可缓），再定 (a)/(b)。

## T2 跑法验证（Scripts/test-direct.sh）

- `--bundle Library 'StableHashTests'` → 7/0/0 ✓（BUNDLE-MAP LIB 7 一致）；
  `--bundle IOP` → 765/3/0 ✓（= 拆分前族计数）。
- 旧式 `Scripts/test-direct.sh 'StableHashTests'` → 扫七 bundle 合计 7/0/0 ✓ 向后兼容。
- MEMFAIL 路径：三 bundle 自然破门触发，标记/日志定位/总退出码非零全生效（较注入
  1MB 阈值测试更强的有机验证）。
- `--bundle Nope` → 明确报错列出合法名单 ✓。
- **机制修正（LESSONS L044）**：直启路径唯一被尊重的选 bundle 旋钮 =
  `XCTestBundlePath` env；旧配方 `XCTestConfigurationFilePath` 配置 plist 的
  TestBundlePath **被无视**（宿主扫 PlugIns 取首个 .xctest——单 bundle 时代两机制巧合
  等价，拆分才暴露）。脚本头注释已备案。

## 偏差登记

1. 6→7 bundle（D5 授权线）+ 成员编译闭合微调（10 文件不匹配 `*Parity*|Golden*|
   ToneEqual*|Lut3d*` 字面：8 文件 GoldenParityTests 静态 helper 使用者 + 
   DenoiseProfileDerivationTests 入 parity；无出列者）——零源改动、唯一归属、计数零增。
2. AC-3 以单跑和（704s）代替 `--all` 整轮（MEMFAIL 停机所迫，上界口径如实注记）。
3. AGENTS.md「资源监控」过渡条款**未能解除**（AC-2 未过）——改写为落地中间态事实
   （7 bundle + MEMFAIL 机检 + 3 bundle 仍破门 + OQ 挂账），门控纪律不变。
4. 夜间授权 + 派发指令授权下执行 D5 拆分（晨审可推翻点：281bda9 的成员微调是否
   认可、以及 OQ 三选一）。
