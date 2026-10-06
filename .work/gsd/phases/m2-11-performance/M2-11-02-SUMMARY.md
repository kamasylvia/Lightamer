# M2-11-02 SUMMARY — PERF 计量批（wave 2）执行收口（2026-10-07 夜间执行 worker）

> Plan = `M2-11-02-PLAN.md`（PERF-01/03/04/05/06 数字落账批 + OQ-7-A 唯一改码候选）。
> 执行正本 = 本文件 + `M2-11-02-DECISIONS.md`（§1..7）+ `perf.md`（数字正本）+
> `profile/`（trace 归档）+ `.work/gui-acceptance/m2-11/MANIFEST.md`。
> 数字逐值可回溯：`/tmp/la-direct-tests-{IOP,Export}.log` + `/tmp/la-release-*.log`
> 的 `PERF|` 行 + trace 导出 XML（perf.md 每表注明）。

## 任务对账

| 任务 | 终态 | 提交 | 关键产出 |
|---|---|---|---|
| T1 M2 默认链 warm 复测 bench | ✅ | `de424d0` | `M2DefaultChainPerfTests`（IOP）+ Project.swift/BUNDLE-MAP 登记（E2）+ generate（L041）；PERF-01 数字 + 交接件 ① 复测闭合 |
| T2 拖动两档复测（M2 面） | ✅ | `7e79a2e` | `testM2DragGateTwoChains`；vs 05 SC#4 对照表（perf.md §PERF-01）= T3 before 列 |
| T3 nlmeans bounded 降载尝试 | ✅ **revert 挂账** | 零产线 commit（§1） | 三档（57/37/29 趟）全不达 16.6ms，引擎单腿已超门 → OQ-7-A 默认退出；parity 362/3/0 零回归零重钉；挂账行 + V2 语义移交 04 |
| T4 open→首帧端到端探针 | ✅ | `7a87eaa` | E3-a 单 func 内分段（skip 零新增）；**warm 512 门双列达标（0.172/0.194s ≤ 0.5s）**；2560 记录档；编译冷缓存态注记（§5） |
| T5 档 B Release 复核 | ✅ | `bff022e`（构建修复）+ `e19a03f`（账） | Release 直启链修复 + 档 A 9.7ms / **档 B 2.70s/张**落 09 perf.md（历史行零改写）；预算判定：上沿外 ~35% 量级一致，吞吐预算由档 A 承担 |
| T6 Instruments + hitch | ✅（部分 Manual-Only） | 本批 | 两 trace 盘上归档（465MB 不入 git，§3）+ hitch 拖动场景 >50ms = 0 + potential-hangs 0；缩放/平移/滚动 Manual-Only（§4）；MANIFEST 九件 |
| T7 收口 | ✅ | 本批 | perf.md 终校（PERF 行逐值对账）+ GOAL-STATE 续接点 + 本 SUMMARY/DECISIONS |

## PERF 数字一览（详见 perf.md）

- **PERF-01 静态 warm**（preview-2560，M2 默认面 + DRT SDR 尾）：ARW 60MP = 13.4 Debug /
  13.2 Release（达标）；RAF 100MP = 14-42 Debug 带 / 37.2 Release（双峰噪声 O-1，未稳态
  达标）；vs M2-6-3 在案 85ms 同量级无回归。
- **拖动两档**：color 七件 = ARW 8.1-8.9 双构建达标 / RAF 带 9.7-21（best-round 达标）；
  nlmeans = ~65(RAF)/~57.5(ARW) Debug ≈ Release，**未达 16.6ms**。
- **OQ-7-A**：57→37→29 趟三档全不达，revert（默认成功路径）；Decimate 杠杆数学不可达，
  V2 备选语义移交。
- **PERF-05**：warm 512 首帧 0.172/0.194s **达标**（门 ≤500ms）；2560 = 2.8/5.1 首帧
  （warm 中位 2.07/1.94 记录档）。
- **PERF-06**：档 A Release 9.7ms ✓；档 B Release 2.70s/张（预算上沿外 ~35%，量级一致，
  不翻档）。
- **PERF-03/04**：trace ×2 归档；MainActor ≥250ms hang = 0；hitch >50ms（拖动场景）= 0；
  三场景 Manual-Only。

## 测试对账

- 基线 2955/16/0 + 本波 +2（M2DefaultChainPerfTests 2 法；E3-a 零 skip 增量）→ 预期
  **2957/16/0**。本波未跑全套 `--all`（批准制未申请）；实跑：IOP 定向多轮全绿、
  IOPParity 全量 **362/3/0**（peak 5995MB）、Export 定向 1/0/0、SESS Release 直启
  1/0/0（Executed 1 test / 0 failures）。skip 零新增；零 MEMFAIL。
- 峰值观测（checker m5）：本波 IOP 新 bench 轮 peak 943-1097MB ≪ 主导峰 7865MB
  （bundle 峰值不变）；贴线处置序未触发。

## 偏差与越界申报（详见 DECISIONS）

1. `bff022e` 两文件产线修复（Release 配置断代缺陷三处）——越界申报 §2。
2. .trace 465MB 盘上归档不入 git（排除 + 导出证据随批）——§3。
3. T6 通道限制（computer-use 主 agent 专属）→ AX 回退 + 三场景 Manual-Only——§4。
4. 编译冷缓存态不可复现 2.62s——§5。
5. RAF warm 双峰噪声观察项 O-1——§6。

## 遗留与移交

- O-1（RAF warm 双峰）→ M2-11-05 GUI 验收轮顺带观察。
- V2 备选语义「denoise 拖动降档预览」→ M2-11-04 重述批注记 + VALIDATION。
- hitch 缩放/平移/万张滚动三场景 → computer-use 主 agent 轮（M2-11-05 或终验 GUI 轮）。
- 编译冷首编译态硬数字 → 待显式清缓存专项（如需）。
- 全套 `--all` 终轮（2957 预期对账）→ M2-11-05 终验（批准制）。
- **未 push。下一步 = orchestrator C 档第 2 停（M2-11-02 plan 闭环汇报）→ M2-11-03。**
