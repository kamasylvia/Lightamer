# M2-4-0 ACCEPTANCE — test bundle 拆分 + 门修订 8G（轻量验收）

**结论：PASS / 0 error + 0 minor**（2026-09-30 独立验收 subagent；拆分落地 + 门 8G 翻账收口）

## 核查记录

1. **执行链 commits**（`git log` 亲验，六连齐 + 范围逐个 `git show --stat` 核对）：
   `eca777c`（六域拆分 + ChainBuilderHelpers/调用点改写）→ `281bda9`（D5 第 7 bundle IOPParity）→ `46bf1c7`（test-direct.sh 多 bundle 跑法）→ `ffc892b`（SUMMARY/DECISIONS/台账收口）→ `70e09e5`（SPIKE 证伪 + 证据落盘）→ `28f1db9`（门 3G→8G）。两份豁免/授权口径在案：**E1 豁免**（ChainBuilderHelpers 零测试 helper 进 SHARED，BUNDLE-MAP 头注 + `7427cd6`）、**夜间授权**（D5 拆分 + 门 8G，「夜间授权 + 派发指令授权，晨审可推翻」，BUNDLE-MAP 头注 / test-direct.sh 头注 / SUMMARY 偏差登记 #4 三处同文）。`git status`：无 M2-4-0 代码滞留（滞留物 = gui-acceptance 截图/临时物，非本 plan 面）。
2. **对账独立复核**：
   - BUNDLE-MAP 数据行 234（去注释/空行）vs `Tests/LightamerTests/` 实际 swift 文件 234，`diff` **1:1 零差、无重名**；bundle 分布 APP 22 / EXPORT 24 / IOP 53 / IOPP 44 / LAYERS 20 / LIB 43 / SESS 25 / SHARED 3。
   - 测试方法逐文件 grep 和 = **2165 精确**（map 编列与实 grep 全等）。2 处 grep 多匹配已定性为**非测试方法误匹配**：`CPUDerivationTests.swift:581` 注释行 `// func testToneEqualizerLUTConstruction`；`IOPieceIscaleTests.swift:95` helper `private func testImage(...)`——map 计数口径正确。
   - `ChainBuilderHelpers.swift` **零测试方法**（`grep -c '^\s*(@Test\s+)?func test'` = 0；仅 `makeCommittedDefaultChain` / `makeChainWithCropFlip` 两 helper）；调用点 30 文件 + helper 自身 = 31 文件吻合；抽核 3 处（TerminalTrioTests:328 / GeometryGoldenTests:271,312,385 / YiyinWatermarkTests:84）均为裸函数调用（原样搬移成立）；pbxproj 内 helper 编列 **6 target**（IOP/LAYERS/LIB/EXPORT/APP/IOPP），SESS 零调用者不编列——与豁免注记一致。
3. **脚本机检亲验**（读码 + 实跑，**未跑 `--all`**——全套轮须批准，本次验收不批）：
   - `Scripts/test-direct.sh` 读码：`RSS_LIMIT_MB=8192`；主判据 `/usr/bin/time -l` ru_maxrss（bytes→MB），ps-poll 后备；`peak_mb >= RSS_LIMIT_MB` → verdict=MEMFAIL → BUNDLE 行尾追加 ` MEMFAIL` + ANY_FAIL → 非零退出；判据 = 测试结果行非宿主退出态。
   - **`--bundle Layers` 独立复跑一轮**：`BUNDLE|Layers|164/2/0|peakRSS=930MB|20s|sampling=time`，TOTAL 164/2/0，**exit 0**。164 = BUNDLE-MAP LAYERS 合计；行格式与脚本头注释规格逐字段一致。

## 两轮验证数字复核（执行轮 vs 验收轮）

| bundle | 执行轮（SUMMARY 结案补记） | 验收轮 | 判定 |
|---|---|---|---|
| Layers | 164/2/0，peakRSS=943MB，22s，PASS | 164/2/0，peakRSS=930MB，20s，exit 0 | executed 精确一致；RSS -1.4%，±3% 方差带内 |
| IOPParity | 308/2/0，peakRSS=5966MB，235s，PASS | 未复跑（重贴线 bundle，数字作一致性复核） | 5966 vs 在案 5788 = +3.1%，SUMMARY 已注记带内；T3 矩阵在案 308 = map IOPP 合计 |

## 晨审注记（晨审可推翻项）

- **门 3G→8G 修订为夜间授权裁决**（依据 = `M2-4-0-SPIKE.md` / commit `70e09e5` 证伪链：<3G 数学不可达——by-design GB 级重测单类自峰 TilingOverlap 7865 / HDR 5913 / QuickLook 4589MB + ~1.4G 框架分页一次性地板；真实跨测残留仅 0.18-2.4MB/test 二阶）。晨审若推翻：改 `RSS_LIMIT_MB` 单点 + AGENTS.md 资源监控节口径回滚即可，拆分结构不受影响。
- 同属夜间授权：D5 第 7 bundle 拆分（`281bda9`，成员含编译闭合微调 10 文件——GoldenParityTests 静态 helper 三角耦合，引用方随被引方同 bundle，零源改动）。晨审不认可微调成员可回调，BUNDLE-MAP 为归属正本。
- 验收轮未跑 `--all`（纪律维持：全套轮仍须 orchestrator 批准 + 运行监视，MEMFAIL 机检兜底）。

## 翻账清单（本验收批）

- `.work/GOAL-STATE.md` 续接点 🌙→✅ 终态（拆分落地 / 门 8G / SPIKE 证伪链 / 验收数字）。
- `.work/TODO.md` M2-4-0 OQ 挂账行勾选 + 验收注记。
- 本报告落盘 `phases/m2-4-0-test-bundles/M2-4-0-ACCEPTANCE.md`。
- 单 commit：`docs(m2-4-0): acceptance — split landed, gate 8G ratified (overnight ruling)`（不 push）。
