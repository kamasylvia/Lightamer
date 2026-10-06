# M2-11-03 SUMMARY — SpektraLab 对标两硬门 bench（wave 3，2026-10-07 夜间执行）

> 执行 = subagent worker（夜间全自动授权在案：「开跑，不要停」）。
> 数字正本 = `perf.md` §SpektraLab 对标两硬门 节（每数字可回溯 /tmp 日志行）。
> 裁决签注 = `M2-11-03-DECISIONS.md`。

## 结论头

**两硬门双 PASS（无降门/无挂账）**：①FULL 桶全链渲染 warm <1s——Release
60.2MP **168.2ms**（余量 ~5.9×）/ 100MP **300.6ms**（余量 ~3.3×），KD-4 杠杆
分解**未触发**；②尾平面缓存命中重渲 ≤10ms——同参二次全命中腿 **0.021ms**（余量
~476×）/ 单参数 tick 尾段重放腿 **5.009ms**（余量 ~2×），前置命中语义断言在。
基线对账 **2957 + 3 = 2960 预期**（IOP 全量实测 470/1/0 = 469+1 精确；全套
`--all` 留 M2-11-05 终验）。**零产线 diff**（`git diff --name-only` 亲证：
App/ LightamerCore/ 零命中）。

## 任务逐条

| 任务 | 状态 | commit | 要点 |
|---|---|---|---|
| T1 FULL 全渲染 bench（IOP） | ✅ | `fdc9ea0` | `FullRenderBenchmarkTests.swift` 新建（1 法）：M2-11-02 T1 链构造复用（terminal trio displayP3 + defaultLook grade + DRT SDR 尾）+ 60.2MP 主列（>45MP 更严口径）+ 100MP 加列 + cold×1/warm×3 中位（per-frame exposure tick 全链 miss 帧型）+ 分解探针三段（decode warm / .sdrGamma control / 同参 FULL 重渲观测）+ Release 硬门断言 <1000ms / Debug 10000ms 病态界；Project.swift IOP 数组 + BUNDLE-MAP 同 commit 登记（L041 generate 恒批末） |
| T2 尾命中重渲计时（LAYERS） | ✅ | `37eb603` | DrtTailTests 扩 2 法（12→14）：腿①同参二次全命中（前置 hits>0 && misses==0）+ 腿②单参数 tick 尾段重放（EOTF 基座 + record 单字段 tick，前置 misses==2/hits==1）；preview-2560（2560×1920 合成 native scale 1）；Release ≤10ms 双腿断言 + Debug 25ms 松界；首轮不计入（warm = 数据热平面）；L014 drain 在计时窗内 |
| T3 记录档 + 不对标注记 | ✅ | 本批 | perf.md §SpektraLab 节四要素齐：对标①②数字行（带判定列）、preview 全链 warm 记录档行 + 语义差异注记（RESEARCH §B.2 原文语义）、32MB 不对标行（≈193MB AI 模型锚）；每行带测试名/在案值出处 |
| T4 收口 | ✅ | 本批 | AC 机检（下表）；GOAL-STATE 续接点；`git diff --stat` 对表 |

## 两门判定（Release 断言轮，测试内断言非 perf.md 转述）

| 门 | 断言位置 | 60.2MP ARW | 100MP RAF | 判定 |
|---|---|---|---|---|
| ① FULL warm <1s | `FullRenderBenchmarkTests.testFullRenderWarmGate`（`XCTAssertLessThan(warmMedian, 1000)`，Release 臂） | **168.2 ms** | **300.6 ms** | **PASS**（Executed 1 test 0 failures ×2 轮；稳定性轮 164.2/273.8ms，跨轮 -2.4/-8.9% 带内） |
| ② 尾命中 ≤10ms | `DrtTailTests.testSameRecordSecondRunTimingAllHits` / `testEOTFTickTailReplayTiming`（`XCTAssertLessThanOrEqual(median, 10)`，Release 臂） | 腿① **0.021 ms** / 腿② **5.009 ms** | 同左（preview-2560 桶，无样张分列语义） | **PASS 双腿**（Executed 14 tests 0 failures；Debug 0.034/4.637ms 同绿） |

## 分解探针（KD-4 输入，恒采；KD-4 分支未触发）

- decode warm：ARW 0.108s / RAF 0.073s。
- 全链 .drt 帧 vs .sdrGamma 主链对照：168.2 vs 184.7/149.9（ARW）、300.6 vs
  259.3/246.9（RAF）ms——同量级，**DRT 尾增重非主导**。
- 同参 FULL 重渲 0.0-0.1ms（hits=2 misses=0）——FULL 桶缓存腿（input+final）
  亚毫秒，尾平面漏缓存/格式转换冗余均未观察到，无意外缺陷形态。
- 主导项 = float32 全幅带宽 × 主链趟数本征成本；<1s 达标面下 OQ-4-A（禁开
  引擎级工作）无触发必要。详见 perf.md 分解表。

## 偏差与发现（执行期）

1. **T1 同参 FULL 重渲腿从断言改观测（设计内修正，DECISIONS §1）**：FULL 桶
   by-design 只缓存 input+final 平面（`PixelPipe.swift:1079` lock #4），初稿
   `misses==0` 断言会假红；KD-2 的命中门本就锚定 preview-2560 桶（DrtTailTests），
   FULL 桶腿降为观测列（stats 进行），分解归因用 .drt − .sdrGamma 差分。
2. **尾段 sub-run stats 丢弃口径（观察注记）**：`runDrtTailLeg` 丢弃尾段 stats
   （既有形态）→ 同参 FULL 腿 hits=2 只计主链面；0.1ms 时间值证明尾平面全命中，
   语义不受计数口径影响（perf.md 注记）。
3. **IOP 全量轮峰值贴线验证通过**：本 bench 100MP 跑完 footprint-now 高水位
   ~6.8GB 不回落（缓存/池驻留），IOP 全量 470/1/0 peak **7840MB < 8192 门**零
   MEMFAIL（vs SPIKE 7865 = -0.3% 方差带内）；连续 MEMFAIL 先查本 bench 顺序位
   的处置序照登 perf.md。
4. **Debug ≈ Release（±2-9%）**：带宽主导本征（与 02 波 nlmeans 拖动同现象），
   Debug 分栏数字有效，双栏口径注记沿用 m2-10 §A.3。
5. **Release 直启链路复用无新坑**：clean 重建 + XCTest 闭包/WebP PackageProduct
   手动嵌入 + `Lightamer Dev` 重签（/tmp/la-release-ent.plist 沿用）一次通过；
   配方正本 09 perf.md §PERF-07 执行期发现 + M2-11-02 T5。
6. **cold 列噪声大不设门**：ARW cold 189.9→655.1ms、RAF 763.5→450.0ms 跨轮
   跳变（首渲 PSO 变体 + 缓存冷 + tile 首分配）；门语义在 warm（印相稳态），
   cold 单值记录。

## AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | FULL warm 硬门终态在案：Release 断言 <1s PASS（无第三态） | ✅ perf.md §对标① 行 + 测试断言 1/0/0 ×2 Release 轮 |
| 2 | 尾命中 ≤10ms 两腿 PASS + 前置命中语义断言在 | ✅ DrtTailTests 扩展 2 法（Debug/Release 双构建 14/0/0） |
| 3 | 分解探针三段数字在案 | ✅ perf.md 分解表（decode/主链对照/同参观测 + 差分归因） |
| 4 | 记录档行 + 语义差异注记 + 32MB 不对标行齐 | ✅ perf.md §KD-3 节 |
| 5 | 登记闭环 + L041 顺序 | ✅ Project.swift/BUNDLE-MAP 随 `fdc9ea0`；generate 在全部文件落盘后 |
| 6 | 零产线 diff；红线域零命中 | ✅ `git diff --name-only 2957基线..HEAD` = Tests×2 + Project.swift + BUNDLE-MAP + 本批 docs（App/ LightamerCore/ 空） |

## 测试对账

- 基线 2957/16/0（02 波终值）+ 3（FullRenderBenchmarkTests 1 + DrtTailTests 2）
  = **2960/16/0 预期**；全套 `--all` 批准制未申请，留 M2-11-05 终验。
- 实测：Layers 定向 14/0/0（Debug）+ 14/0/0（Release 直启）；IOP 定向 1/0/0
  （Debug）+ 1/0/0 ×2（Release 直启）；**IOP 全量 470/1/0**（Debug，154s，peak
  7840MB）——IOP bundle 基数 469+1 精确，skip 零新增（本机两样张在场）。

## 提交清单

- `fdc9ea0` test(iop): full render benchmark with spektralab gate
  （FullRenderBenchmarkTests.swift + Project.swift + BUNDLE-MAP IOP 行/DrtTail 行预记）
- `37eb603` test(layers): tail hit rerender timing gate（DrtTailTests.swift）
- 本批 docs(m2-11): close out plan 3 spektralab benchmark gates
  （perf.md + SUMMARY + DECISIONS + GOAL-STATE）

未 push（纪律）。
