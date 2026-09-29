# M2-4-0 DECISIONS — 执行期裁决（2026-09-30，夜间授权 + 派发指令授权，晨审可推翻）

## D-EXEC-1：D5 预案实拆触发与授权链

MEMFAIL 证据（IOP 765 tests 单宿主 ru_maxrss 6975MB/8141MB 两轮）满足 plan D5 触发条件。
D5 原文「停，OQ 上报，需 orchestrator 批准后执行」与派发指令「任一 ≥3G = MEMFAIL 触发
IOP 拆第 7 bundle 预案并停机上报」+ GOAL-STATE 2026-09-29 夜间自动授权（OQ 按推荐自主
裁决，晨审可推翻）合并解读为：**按预声明线执行拆分 + 如实上报晨审**。若晨审不认可，
回退 = revert `281bda9`（回到六 bundle；IOP 8.1G 破门事实不变）。

## D-EXEC-2：D5 拆分线的编译闭合微调（成员 v2）

预声明线 `*Parity*|Golden*|ToneEqual*|Lut3d*`（35 文件）首批构建暴露跨文件静态 helper
耦合（plan 风险 §1 剧本，但方向相反——是**留守文件引用被搬文件的 helper**）：

- `GoldenParityTests.decodeFixtureEXR` + `GoldenParityTests.UncompressedEXR`（静态、非
  测试方法）被 8 个留守文件以代码引用：AgX/FilmicRGB/GeometryGolden/HDRPipelineMatrix/
  HighpassSoften/LocalContrast/NoiseFixtureStatistics/Sigmoid；
- `DenoiseProfileDerivationTests.decodedImage`（静态）被 DenoiseProfileParityTests 引用，
  而 DenoiseProfileParityTests 同时引用 GoldenParityTests 上述 helper → **三角耦合**。

计划内 remedies 均不可用：把宿主文件列入多 target = 测试方法重复执行破对账（明令禁止）；
抽 helper 进共享文件 = 新的 E1 型豁免（「不得即席扩豁免」）。**采用第三条零源改动路**：
把引用方文件整体归入被引方所在 bundle（成员归属本是本 plan 的处置自由度；每个测试文件
仍唯一归属、测试方法零增量 grep=2165 自证）。终态成员：

- IOPParity = 44 文件/308 tests（35 线内 + 8 helper 使用者 + DenoiseProfileDerivationTests）；
- IOP = 53 文件/457 tests。

BUNDLE-MAP.txt 头部 D5 实拆记录 + IOPP bucket 为归属正本。剩余 53 留守文件对 10 个搬移
文件的类名引用经逐一 grep 核实**全部为注释**（FilmicRGB→CPUDerivation /
LocalContrast→TilingOverlap / Sigmoid→CPUDerivation / MonochromeGrid→LocalContrast 等），
v2 构建一次通过（TEST BUILD SUCCEEDED）。

## D-EXEC-3：bundle 选择旋钮修正（L019b 配方更新）

旧直启配方的 config plist（TestBundlePath）实测被无视——宿主扫 PlugIns 取首个 .xctest
（App，字母序）。单 bundle 时代 scan 与 config 巧合等价，L019b 等价性验证（480/3skip）
无法区分两者。实验矩阵（2026-09-30）：

| 实验 | 结果 |
|---|---|
| config=Library + 过滤 StableHashTests | 加载 **App**.xctest，executed 0 |
| config=IOP 无过滤 | 加载 **App**.xctest（跑满 267） |
| `XCTestBundlePath`=<IOP.xctest> + 过滤 | **正确加载 IOP**，6/6 |
| 无任何 env | 加载 App（scan 语义确认） |

结论：直启路径 bundle 选择 = `XCTestBundlePath` env 唯一有效；config plist 整体弃用
（脚本不再生成）。已记 LESSONS L044。

## D-EXEC-4：`(( ))` 算术状态码与 set -e

zsh `(( expr ))` 在求值为 0 时返回状态 1，`set -euo pipefail` 下直接杀脚本（首版
`(( t1 = SECONDS - t0 ))` 在 <1s 的快轮上触发）。修复 = `$(( ))` 赋值形态。同类风险
面（`&&` 链中的 `(( ))`）符合 set -e 豁免规则，保留。

## D-EXEC-5：提交结构偏离 plan 的三commit 划分

plan 设 T1/T2/T3/T4 各一 commit。实际：T1（eca777c）→ D5 修正（281bda9，Project.swift
+ BUNDLE-MAP）→ T2（46bf1c7）→ 收口 docs（本提交，含 T3 证据 = SUMMARY）。T3 因
MEMFAIL 停机无独立代码产出，证据并入收口 docs commit；不设空提交（§2.1）。

## D-EXEC-6：AC-2 破门后的停止纪律

Export 独立破门（6659MB）出现在 D5 预案验证轮——**不追加任何 bundle**（D5 明令）、
**不放宽门**（D5 明令）、**不触碰产品源**（plan 性质 = 测试基建）。线性积累事实
（~17-26MB/test）+ 三选一决策点如实上报（SUMMARY「内存事实」节，推荐先产品侧 spike
定性积累可释性）。
