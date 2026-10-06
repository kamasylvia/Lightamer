# M2-11-03 ACCEPTANCE — SpektraLab 对标两硬门验收（2026-10-07 验收 subagent，零共享上下文实测核验）

## 结论

**PASS / 0 error + 1 minor**（两硬门双构建亲跑复现；执行期修正裁定 = 采纳（锚定桶
澄清），非门槛放宽；minor-1 = DECISIONS §1 机制表述失准，已随验收批补注记）。

---

## 一、两门亲跑证据（本验收机直跑，非转述）

构建链亲证：Debug = `build-for-testing -derivedDataPath build`（本批重建，TEST BUILD
SUCCEEDED）+ `Scripts/test-direct.sh` 直启；Release = 执行 worker 05:50 clean 构建
产物（源 mtime 05:37-39 < 构建 05:41/05:50 < 提交 05:51+，与 HEAD 字节同源亲证：
Tests/ 工作树零改动）+ 注入闭包/`Lightamer Dev` 重签（codesign 05:50:12 +
entitlements 两键亲读）直启。两样张在场亲证：`input/RAW/DSC00012.ARW`（74.6MB）+
`~/Library/Application Support/Lightamer/TestRAW/Fujifilm-GFX100S-…RAF`（210MB）。

### 门① FULL 桶全链渲染 warm <1s（OQ-2-A①）——PASS 双构建双列

| 构建 | 60.2MP ARW warm 中位 | 100MP RAF warm 中位 | 计数 |
|---|---|---|---|
| Debug（亲跑） | **168.3 ms** | **282.7 ms** | 1/0/0（65s，peak 4186MB） |
| Release（亲跑直启） | **168.1 ms** | **280.5 ms** | 1/0/0（59.3s，peak 5344MB） |
| 执行 worker 申报（对表） | 168.2 / 稳定性 164.2 | 300.6 / 稳定性 273.8 | 1/0/0 ×2 |

- 断言硬编码读码亲证：`FullRenderBenchmarkTests.testFullRenderWarmGate` Release 臂
  `XCTAssertLessThan(warmMedian, 1000, …)` / Debug 臂 10000ms 病态界——门本体在测试
  内，非 perf.md 转述。
- 分解探针同轮复现：decode warm 0.104/0.073s；.sdrGamma 主链对照 179.1/244.5ms vs
  .drt 全链 168.1/280.5ms——同量级（±15% 内），**DRT 尾增重非主导**差分归因成立；
  KD-4 杠杆分解分支未触发亲证（无降门/挂账/阈值调整）。

### 门② 尾平面缓存命中重渲 ≤10ms（OQ-2-A②）——PASS 双构建双腿

| 腿 | Debug（亲跑） | Release（亲跑直启） | 计数 |
|---|---|---|---|
| ① 同参二次全命中 | **0.036 ms** | **0.018 ms** | 14/0/0 |
| ② 单参数 tick 尾段重放 | **4.377 ms** | **5.059 ms** | 14/0/0 |
| 执行 worker 申报（对表） | 0.034 / 4.637 | 0.021 / 5.009 | 14/0/0 双构建 |

- 断言形态读码亲证：两腿 Release 臂 `XCTAssertLessThanOrEqual(median, 10)` 硬编码；
  Debug 25ms 松界；**前置命中语义断言在计时断言之先且逐帧**（腿①
  `hits>0 && misses==0`；腿② `misses==2 && hits==1`）——「命中语义回归先红」纪律
  在码亲证；计时窗读数先于断言求值（clock append 先于 XCTAssert）；L014 drain 在
  `render` helper 内部于 return 前执行 = 计时窗内 fence 亲证。
- preview-2560 桶亲证：`makeBenchImage() = makeImage(width: 2560, height: 1920)`。

## 二、执行期修正裁定（D-M2-11-03-1：`misses==0` 断言降观测列）

**裁定：采纳——属「锚定桶澄清 + 设计内对齐」，非门槛放宽。** 依据三条亲证：

1. **plan 层面从未要求 FULL 桶 `misses==0` 断言**：KD-1 探针定义 =「分段计时落账
   ——带宽归因输入」（KD-4 同义）；T1 验收标准只有「Release 直启轮出 warm 门判定」。
   命中硬门在 plan KD-2 自身就锚定 preview-2560 桶（DrtTailTests），plan 风险节自带
   桶语义分工。降级方向 = 收敛到 plan 原文，无任何 plan 级门被触碰。
2. **lock #4 by-design 亲证成立**：`PixelPipe.swift` processRec 缓存判据（:1075-1079
   一带）原文「PER-PIPETYPE POLICY (lock #4): PREVIEW/THUMBNAIL cache every plane;
   FULL caches input + final only (intermediates ping-pong); EXPORT caches nothing」
   逐字在码；`runOnce` 注记同源（lock #4 引用）。
3. **两门本体硬编码完好**：warm <1s（Release 臂）与 ≤10ms 双腿（Release 臂）均在本
   验收双构建亲跑断言通过——降观测列的是探针腿，不是任何门。

**minor-1（机制表述失准，已随验收批在 DECISIONS §1 补验收注记）**：§1 原文「尾段
method box 每次重渲，`misses==0` 断言必然假红」两点不成立：(a) 尾段 sub-run stats
在 `runDrtTailLeg` 的 `let (output, _) = try await tailPipe.runSub(…)` 丢弃点不进主
run 统计——尾段即使 miss 也到不了该断言；(b) 亲跑实测同参 FULL 重渲 = hits=2
misses=0（主链 input+final 双命中、尾段终面 seed 键自顶向下探测先命中即返回不递归
method box），`misses==0` 若保留**会绿不会红**。降观测列的真依据 = 主 run stats 对
「尾平面全命中」语义是空证（尾段 stats 不可见），0.0-0.1ms 时间值才是全命中证据。
裁定结论不受影响（降级方向保守、两门完好），仅表述修正。

## 三、零产线 diff 与登记闭环亲证

- `git diff --name-only 09d7e31..HEAD`（基线=02 波终批）= **8 文件**：Tests×2 +
  Project.swift + BUNDLE-MAP + perf.md + SUMMARY + DECISIONS + GOAL-STATE——与申报
  集精确一致；`git diff -- App/ LightamerCore/` = **0 行**（红线域零命中亲证）。
- 登记闭环：`Project.swift` LightamerTestsIOP 显式清单 +1 行（新文件在 array 内亲
  读）；BUNDLE-MAP IOP +1 行（FullRenderBenchmarkTests 1 法）+ LAYERS DrtTailTests
  12→14 行——均随 `fdc9ea0` 同 commit。
- L041：Project.swift mtime 05:38:58 → `project.pbxproj`（tuist generate）05:39:40
  → 测试构建 05:41 → 提交 05:51+；generate 恒批末亲证（pbxproj gitignored，mtime
  链为唯一在案证据，含 FullRenderBenchmarkTests 4 处引用）。
- 提交三件与 plan 提交约定一致：`fdc9ea0` test(iop) / `37eb603` test(layers) /
  `5b9823f` docs(m2-11)；`origin/main..HEAD` = 835（未 push 亲证）。

## 四、数字对账（2960 预期 + IOP 全量亲跑）

- **IOP 全量亲跑：470/1/0，peak RSS 7838MB < 8192 门，零 MEMFAIL**（210s，
  `BUNDLE|IOP|470/1/0|peakRSS=7838MB`）——与执行 worker 申报 470/1/0@7840MB 逐值
  吻合（peak 差 2MB = 噪声）。BUNDLE-MAP IOP 列合计 = **470**（awk 亲算精确），
  469+1 成立。
- 唯一 skip = `SkinRegionGeometryTests.testVisionProviderOnSynthesizedFaceDrawing`
  （host Vision 环境件，既有项）——**skip 零新增**亲证；两样张在场（本机口径）。
- Layers 定向 14/0/0 双构建（12+2 精确）；2957 + 3 = **2960/16/0 预期**算术成立；
  全套 `--all` 留 M2-11-05 终验（批准制未申请，符合纪律）。
- 峰值观察（checker m5 处置序）：本验收 Release FULL 轮 peak 5344MB / Debug 4186MB
  / IOP 全量 7838MB——贴线观察登记与 perf.md 峰值表互证，「连续 MEMFAIL 先查本
  bench 顺序位」指针在 perf.md 在案。

## 五、语义注记与 OQ-4-A 复核

- 85ms 记录档行 + 32MB 不对标行齐备且带锚（RESEARCH §B.2/B.3 原文语义逐点对上：
  SpektraLab 0.01s = LUT 重贴级 → 对标行在尾命中腿；二进制 32MB 无对应单一体，
  ≈193MB AI 模型 by-design 锚 M2-10-01-SUMMARY:42）——不对标语义未被悄悄翻案。
- OQ-4-A 未触发判定合理：两门达标面下（余量 3.3-5.9× / 2-476×），.drt ≈ .sdrGamma
  同量级 = 无引擎级杠杆指向（TilingPlan/链趟合并无立项必要），与本验收亲跑差分
  （168.1 vs 179.1；280.5 vs 244.5，±15% 内）互证。
- 观察项（不判缺）：`testFullRenderWarmGate` 多样张循环内 fixture 缺席 `throw
  XCTSkip` = 全测试 skip（all-or-nothing 采列）——仅 RAF 缺席机器上 ARW 列也不
  断言；门语义以样张在场机器为准（DECISIONS §2 机器口径已注记），现状可接受。

## 六、AC 总表（plan 6 条逐条）

| # | AC | 结果 |
|---|---|---|
| 1 | FULL warm 硬门终态在案（Release 断言 <1s PASS，无第三态） | ✅ 断言在码 + 亲跑 1/0/0 双构建（168.1/280.5ms）；KD-4 未触发 |
| 2 | 尾命中 ≤10ms 两腿 PASS + 前置命中语义断言在 | ✅ 亲跑 14/0/0 双构建（0.018/5.059ms Release）；前置断言在码 |
| 3 | 分解探针三段数字在案 | ✅ decode/主链对照/同参观测 + 差分归因（perf.md 分解表 + 本验收同轮复现） |
| 4 | 记录档行 + 语义差异注记 + 32MB 不对标行齐 | ✅ perf.md §KD-3 三行带锚 grep 亲证 |
| 5 | 登记闭环 + L041 顺序 | ✅ 三处登记同 commit；mtime 链亲证 |
| 6 | 零产线 diff；红线域零命中 | ✅ 8 文件申报集精确一致；App/LightamerCore 0 行 |

**验收批动作**：DECISIONS §1 补验收注记（minor-1）+ 本 ACCEPTANCE 入库 + GOAL-STATE
增量——零代码改动，无新 commit 争议面。
