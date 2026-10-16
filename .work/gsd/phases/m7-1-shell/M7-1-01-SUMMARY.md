# M7-1-01 SUMMARY — D-6 壳专项执行批（2026-10-16 夜间批；停手批）

> **一句话结论：T1 交付前提被执行批探针证伪——FIX2 C1/C2 饿死读数在今日
> HEAD 复现失败（六形态 + 编辑器面 C3 全部环活），零产线 commit，工作树
> 回落 HEAD（`fc587281`）。** 裁定正本 =
> `M7-1-01-DECISIONS.md`（D-M7-1-01-1..5）；证据正本 =
> `gui-acceptance/m7-1/t1-scratch-matrix/MATRIX.md`（含协议硬化记录）。

## 逐任务终态（对 plan T1..T7）

| 任务 | 终态 | 产出指针 |
|---|---|---|
| T1 案 A+B + flag + 判别臂 | **停手——判据不可达**。三形读数全活（case-B 28.5% / A+B 34.9% / C1 纯摘 32.7% / C2 纯摘 29.05% / HEAD 座位 31.1%；环符号同族）。代码全回滚；flag 全套撤回 | `t1-scratch-matrix/MATRIX.md` + per-arm 文件 |
| T2 C3 scratch 门 | **分支 B**：编辑器面 96.1% 环活 → 不饿死；render 链 6/6 通；回退零 diff；呈报件见下 | `t2-c3-scratch/VERDICT.md` |
| T3 燃料减频 | **不行使**（价值论证依赖已证伪理论；纯风险面）——停手待裁定 | DECISIONS D-M7-1-01-1 |
| T4 三判据终验 + 挂账⑥ | 三判据 = FAIL（如实）；挂账⑥ N=3 轮全净（6/6 行 ×3、DB=6 ×3、0 迟到——**churn 在场态零再现**，对因果假说反向旁证） | `t4-import-retest/rounds-summary.txt` |
| T5 全套 --all | 本批末跑（HEAD 基线；预期 3860/35/0 + ΔN 0）——结果见文末补记 | 本文件末节 |
| T6 走查复走 | **Deferred**（修后复走行集的前提=修法落地；未落地则复走无判读对象。波 1/2/3 行集 + 挂账④⑤ 保持原账，下一批承接） | `gui-acceptance/m7-1/MANIFEST.md` |
| T7 收口 | 本文件 + DECISIONS + FB 勘误 + 台账翻新（GOAL-STATE/TODO/AGENTS 注记） | 各台账 |

## ΔN 记账

ΔN = 0（零产线 commit；新测试文件 = 0 存活——ShellReducedTreeGateTests
随 flag 撤回删除；全套预期 = 基线 3860/35/0 逐值）。

## 呈报件清单（用户裁定项；经 orchestrator 汇报层）

1. **【主件】阈值理论证伪的处置**：按本批硬化协议（可见窗 frontmost +
   符号判读）重跑 FIX2 C1/C2 scratch——若仍不饿死，D-6 缓解脱离树形域
   （窗拆 SHELL-02 重评 / upstream-only；FB 提交价值上升）。若重跑饿死
   → 本批读数归因环境漂移，修法批重启（本批 flag/座移/列改造草案代码
   已撤，需按 plan 重落——草案经验已录 DECISIONS D-M7-1-01-2）。
2. **C1/C2 形的批注**：本批 case A 座移在测试宿主 AX 桥上不可测（行座
   位不物化——DECISIONS D-M7-1-01-2）；无论理论走向，重启批需先解 AX
   断言面适配。
3. **FB 提交**（维持「现在就提交」裁决 D-M7-1-3）：勘误两处已落稿
   （display-cycle-locked + 98-100% datapoint）；**FB 案号待回填槽 =
   此处**（用户提交后回填 REQUIREMENTS SHELL-04 + GOAL-STATE）。
4. **挂账⑥**：维持独立待研登记（D-FIX2-4 口径）；本批三轮全净 =
   churn 在场态的反向旁证，随主件裁定一并处置。
5. **T3 燃料减频**：停手待裁定（见 DECISIONS D-M7-1-01-1 后果节）。

## 环境与协议备忘（下一批必读）

- 遮挡门控：一切 CPU/探针读数前 `set frontmost` 先行（本批首批读数因
  遮挡 0.0% 作废——FIX2 一路观察 #1 复现）。
- 带参启动进程的 pgrep：`-la_editor_probe` 带参时 `MacOS/Lightamer$`
  锚尾不命中（RESEARCH §0.4 PID 陷阱姊妹条）。
- 测试宿主 AX 桥：普通 VStack 行内容不对 in-process AX 走查物化（仅
  safeAreaInset 内容物化；priming/挂载形五试均无效）——涉 AX 断言的
  座移类改造先读 DECISIONS D-M7-1-01-2。
- 代理：SPM 子模块 clone 需清 proxy env（本机 proxy daemon 未跑时
  xcodebuild 解析包失败——`env -u http_proxy ...` 配方）。

## T5 全套对账（补记，2026-10-16 19:14-19:49 轮）

```
BUNDLE|IOP|687/5/0|peakRSS=7728MB
BUNDLE|IOPParity|460/3/0|peakRSS=8108MB
BUNDLE|Layers|494/5/0|peakRSS=808MB
BUNDLE|Library|729/4/0|peakRSS=619MB
BUNDLE|Sessions|284/9/0|peakRSS=1665MB
BUNDLE|Export|379/5/0|peakRSS=6567MB
BUNDLE|App|827/4/0|peakRSS=2832MB
TOTAL|3860/35/0|2093s
OK (direct launch, no testmanagerd)
```

exit 0；对账 = 基线 3860/35/0 **逐值精确闭合（ΔN = 0）**；七 bundle 全
8G 门内（IOPParity 8108MB 贴线未触 MEMFAIL 门 ≥8192）；skip 35 构成 =
基线 24 + RAW 供件域漂移 11（口径维持，无第三来源）。

红线族机检（回滚后 HEAD 原状亲核）：tracked modified = 0；`.metal` 零
diff；封存面零触；runModal/LocalizationValue 禁形零命中；UserDefaults
新键 = 零（flag 撤回）；xcstrings 零 diff；Project.swift 零 diff。
