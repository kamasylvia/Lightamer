# M2-11-02 ACCEPTANCE — PERF 计量批验收（2026-10-07 验收 subagent，零共享上下文实测核验）

## 结论

**PASS / 0 error + 2 minor**（M2-11-02 执行+验收闭环；七提交边界干净，revert 审计通过，
计量数字亲跑复现，越界三修前提亲证成立。2 minor 均为证据注记级，不判缺、不阻塞。）

---

## 一、revert 审计（T3 / OQ-7-A，本波核心）

1. **零 diff 三向亲证**：`NLMeansModule.swift` 与 `PixelPipe.swift` 对 `3c26336`
  （checker 回注基线）..HEAD 及工作树三向零 diff（`git diff` 亲跑，0 行）；
   条件项 `PreviewChainPerfTests.swift` / `NLMeansParityTests.swift` 同样零 diff
   ——parity pin 未重钉，与「committed 档 pin 原样绿」申报一致。
2. **三档数据链数学亲核**：`offsets(K:3, decimate:true)` = 14（28 候选隔一取一）
   → 14×4+1 = **57**；step 3 → 9 → **37**；step 4 → 7 → **29**。perf.md §OQ-7-A
   档位表趟数列全部自洽。引擎级 33.1/26.5 与趟数近似线性（49.7→33.1→26.5 vs
   57→37→29，比值 1.50/1.25 vs 1.54/1.28），拖动② 46-51/40-41 全不达 16.6ms。
3. **parity 亲跑**：IOPParity 全量 = **362/3/0**（peak 5485MB，无 MEMFAIL，
   292s）——与申报逐值一致，revert 后零回归亲证。
4. **语义判定**：DECISIONS §1「revert 是默认成功路径，强改硬凑是失败」与
   OQ-7-A 裁决文本逐字一致；V2 备选语义移交 M2-11-04 在 SUMMARY/GOAL-STATE
   均有登记。「引擎单腿 26.5ms@29 趟独自超门 → decimate 数学不可达」论证成立
   （归档正确性判别见 minor-1）。

### minor-1（证据注记，已随验收批补注 perf.md §OQ-7-A）

现存 `/tmp/la-direct-tests-IOP.log`（03:55，T3 尝试期轮）引擎行打印
`downgraded(57 passes) 26.5 ms`——该标签用 `offsets(K:3, decimate:true)` 默认
step 计算，尝试期 runtime 档加深（previewDecimateStep）后标签不随之变
（stale label 伪影）。归档正确性经**满血腿机器态判别**亲证：
full 481 趟腿与降载档无关且 kernel（`NLMeansKernels.metal`，自 a61f746
2026-09-22 单提交）与 05 锚完全同码——05 锚 430.9ms → 该轮 370.6ms =
仅 **-14% 机器态漂移**；若 26.5 属 57 趟档需同 kernel **-54%**，不可能；
26.5 ≈ 49.7（57.8×0.86，预期当日 57 趟值）× 29/57，与 perf.md
「26.5 = 29 趟档」归档吻合。判定链不受影响。

## 二、计量学抽查（L014）

- **fence 亲证（读码）**：T1 `frame()` = start→process→`drain(metal)`→读钟；
  T2 `measure()` = 4 warm-up→drain→10 计时帧（tick→start→process→drain→读钟）
  ——drain 均在读钟前（计时窗含 drain，保守正确）。T4 `probeRender` 经 export
  queue await 全链完成，同一形态。
- **median 取法**：T1 `sorted()[1]`（3 轮）；T2 `sorted()[count/2]`（10 轮）；
  与既有 bench 形态一致。
- **Debug/Release 分栏**：`isReleaseBuild` 编译期判定打印进 PERF 行；Release
  列（/tmp/la-release-*.log 13 行 PERF）与 Debug 列逐值在档。
- **T1/T2 bench 验收轮亲跑对表**：2/0/0、peak 1118MB——ARW warm **12.6ms**
  （在案 13.4 同档）；RAF **14.0ms**（恰落在案带 14-42 下沿，O-1 快态复现）；
  拖动 color 9.1/8.4（在案带内）；nlmeans **64.5/57.3**（在案 ~65/~57.5 逐点
  吻合）。

## 三、越界审计（`bff022e`，DECISIONS §2 申报面）

三修前提逐一亲证 + 最小性判定：

1. `EditorProbeIfRequested` 声明于 `WorkspaceHostView.swift:1336` `#if DEBUG`
   块内（:1339）——未 guarded 调用点 Release 必编译失败；postfix `#if DEBUG`
   = 最小正当修复（Debug 臂 = 预处理器原码，逐字节不变）。
2. optional 链复合表达式提升局部量 = 语义保持拆分，两配置同效。
3. `AIWorkerMain.spikeOp` :104 于 `#if DEBUG`（:99）内、dispatch :199-200 同
   gate——「Release worker 对 spike 应答 unknown-op」属实；测试整函数
   `#if DEBUG` 门控，门控域内恰 1 个 test func + 内嵌 helper（Debug func
   计数不变亲数）。

**判定**：三修皆 Release-only 编译面正当修复、非顺手改；越界申报程序合规；
「revert bff022e = T5 义务不可达」dependency 注记成立。晨审若裁回退须连带
接受 T5 Release 数字失效。

## 四、逐 commit 边界（15cfe14..HEAD 七提交）

| commit | 任务 | 边界判定 |
|---|---|---|
| `de424d0` | T1 | 3 文件（新 bench 213 行 + Project.swift +1 + BUNDLE-MAP 增行）——恰申报集 |
| `7e79a2e` | T2 | 单文件 +125——恰申报集（BUNDLE-MAP 计数更新实际落 T7，见 minor-2） |
| `7a87eaa` | T4 | 单文件 +52；`testQLRenderLatencyGrid` func 计数 1→1 亲证 = E3-a 零 skip 增量成立 |
| `bff022e` | T5 修复 | 2 文件 +15/-2——越界申报面（§三，判定正当） |
| `e19a03f` | T5 账 | 09 perf.md 纯插入节（历史行零改写 diff 亲证） |
| `4184fd8` | T6 | 导出证据 + MANIFEST 九件；.trace 盘上归档（33M+432M du 亲证）+ `.git/info/exclude` 两行在档 |
| `98749f3` | T7 | perf.md / SUMMARY / DECISIONS / BUNDLE-MAP 计数 1→2 / GOAL-STATE |

- 红线域：MCP/Export/Version **零命中**（全范围 name-only 亲证）；产线 diff =
  WorkspaceHostView（越界申报面）+ Project.swift（登记）两文件；PixelPipe/
  NLMeansModule 零命中（AC#8 revert 分支字面成立）。

### minor-2（提交信息表述）

`7e79a2e` 提交信息称 "BUNDLE-MAP note updated in the same commit"——实际该文件
T2 未触，计数 1→2 与注记改写落 T7（`98749f3`）。登记闭环本身成立（E2/AC#7
对表：`grep -c "func test"` = 2 = 行值 2 = Project.swift 登记在位），仅提交
信息表述不准，不改史。

## 五、数字复核

- **2957 = 2955 + 2 精确**（M2DefaultChainPerfTests 2 func 亲数；
  QuickLookPerfProbeTests 1→1；BUNDLE-MAP 行值 2）。
- **PERF-05 探针验收轮亲跑**：512 门 **0.162/0.189s ≤ 0.5s 达标复现**（申报
  0.172/0.194，噪声带内）；2560 = 2.855/5.099（申报 2.806/5.061 吻合）；
  ARW decodeCold 0.144 = 磁盘缓存命中态复现（DECISIONS §5 注记一致）。
- **Release 列对表**：静态 warm 37.2/13.2、拖动 color 21.0/15.2/9.7 与
  8.7/8.2/8.1、nlmeans 63.8/64.5/64.4 与 56.9/57.3/57.4——`/tmp/la-release-*.log`
  PERF 行与 perf.md 逐值吻合。
- **hitch 证据**：`hitch-edit-session-summary.txt` = 498 帧 / >50ms = 0 /
  top10 全 16.7ms——与 perf.md §PERF-03/04 一致；XML 501 行在档；
  缩放/平移/滚动 Manual-Only 有 KD-6 兜底条款授权。
- **Executed/skip 对账**：IOPParity 362/3/0 + IOP 2/0/0 + Export 1/0/0 + SESS
  Release 1/0/0 日志亲证；skip 零新增；2957 全套预期留 M2-11-05 终验
  （批准制未申请 = 合规，与 plan 纪律 5 收口定向轮口径一致）。

## 六、观察项（不判缺）

- 工作区残留：`.work/gui-acceptance/09-3-tiers-*.jpg` 两文件 modified 未提交
  （非本批七提交触及，T6 GUI 会话工作区副产物；不属本 plan 边界，留工作区）。
- DECISIONS §1「达线需 ≤8 趟」为保守端外推（按各列线性外推实际约 10-19 趟
  不等）——方向为「更不可达」，强化 revert 判定，不影响结论。

## 验收批动作

- `perf.md` §OQ-7-A 追加证据注记（minor-1 stale-label 判别记录）。
- `GOAL-STATE.md` 续接点追加本验收行。
- 验收批零修码；未 push（纪律）。
