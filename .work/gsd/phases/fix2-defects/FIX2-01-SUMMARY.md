# FIX2-01 SUMMARY — 修复批 II 执行摘要

> executor: FIX2-01 执行批（2026-10-16 夜间，T1→T5）。plan = 修订版
> `FIX2-01-PLAN.md`（`dafcec88`+`029f84bc`）；基线 = 3857/35/0；裁定正本 =
> `FIX2-01-DECISIONS.md`（D-FIX2-1..5）。证据域 =
> `gui-acceptance/v2m/fix2-probe/`（local-only）。

## 0. 终值与对账

- **全套 `--all` = `TOTAL|3860/35/0|`（2070s，exit 0，七 bundle 全绿零
  MEMFAIL）**：IOP 687/5/0（7701MB）/ IOPParity 460/3/0（8112MB）/ Layers
  494/5/0（808MB）/ Library 729/4/0 / Sessions 284/9/0 / Export 379/5/0 /
  App 827/4/0。对账链 = 3857 + ΔN 3 = **3860 精确**（ΔN = T2
  ImportProgressCoalescingTests +3；T1 ΔN=0 断环缝不可纯函数化〔视图级
  seam，D-3 先例〕；T3 零码）。skip 35 = 24 基线 + 11 RAW 供件域漂移
  （口径维持）。首轮 IOP 一次窗外 crash（NLMeans 中 terminated abnormally，
  5.3GB——本机当日 GUI 轮残留内存压力面；隔离重跑 687/5/0 绿 + 全套重跑
  绿，flake 台账延续先例）。
- commit 链：T2 `da99ea2f`（fix(fix2) 合流+watchdog+测试+登记）→ T2/T3
  docs（DECISIONS 全文件，含 T1 定罪 + T2 裁定 + T3 核销）→ T4 本批
  台账。T1/T3 零产线 diff（AC 兑现：T3 `git diff --stat` 仅 docs）。

## 1. T1 — D-6（error 级候选）：探针定罪完成，主案不可落地，升级上报

- **定罪（plan action 1 五条读数，DECISIONS D-FIX2-1）**：H1-a
  （onGeometryChange 写环）/ H1-b（focusedSceneValue 写环）/
  H1-c（任意 app 写点）**全部证伪**——28k+ 次重估零属性变更（`@self` 恒
  父传值恒新）、深层七视图各仅挂载一次重估。环 = **macOS 27 SwiftUI
  菜单/焦点更新机制自持环**（`makeMainMenu ↔ updateMainMenu ↔
  invalidateProperties ↔ updatePreferences`，焦点 store 逐 pass
  `PropertyList.prependValue` 无去重；样本 =
  `fix2-probe/t1-menu-loop-sample.txt`）。**H2 坐实**。
- **持续条件（threshold 形）**：空载面摘 `.inspector` 或摘双
  safeAreaInset 任一 → 环饿死；编辑器面**三段内容任摘一段** → 饿死；
  摘 `.inspector`/insets/List→LazyVStack/phase 动画全部不饿死。
- **处置（M-8 上报分支行使）**：修法不可落地产线（无写点；H2 备案
  `.inspector` 改形经 C1 实测换不来编辑器面 spin 消失，行使收益为零）。
  **D-6 三铁条未过（CPU 48-53% + filmstrip 点击零响应复现）→ T1 如实
  BLOCKED**，三选一上报 orchestrator（①接受降级/专项立项 ②research
  复审 ③回退 macOS 27 评估）。W1 的 D-6 依赖行随之 Blocked。
- 探针代码零入库（纪律兑现）；证据九件 `t1-*` 入证据域。

## 2. T2 — D-7：合流投递 + watchdog 落地（`da99ea2f`）

- `ImportProgressCoalescer`：handler 零 await（M-1①非阻塞钉）+ 100ms
  leading/trailing 单槽 latest-wins + 终态恒穿透 supersede（双载体断言：
  服务侧 `.completed/.cancelled` bypass + controller `importProgress=nil`
  直写 tail 零触）+ main actor 单飞保序（M-1②钉，adapter 单调钳维持）。
  watchdog = os Logger 一行（诊断面零行为）。
- 测试 +3 法（`ImportProgressCoalescingTests`，App bundle 824→827；
  Project.swift + BUNDLE-MAP 同批 + tuist generate 末位）。
- **N 轮导入亲跑**：post-T2 11 轮中 **8 轮完成**（6/6 行落库 + 逐行
  loaded/rendered ≥ AC 的 N≥3）；**3 轮零行间歇**（新观察登记：
  per-file insert 静默失败、lastError=nil、completion 照常发布——pre-T2
  同型在案，非本批引入，DECISIONS D-FIX2-4）。

## 3. T3 — D-8：翻案核销（零产线 diff）

- 真腿亲证：`LIGHTAMER_LEGACY_LIBRARY=1` → Open Recent > d2-session →
  网格带图（CPU 0.1%）→ 双击进编辑器（Single 带图渲染 + 右栏调整栈
  mount + CPU 0.1%）→ 返回图库。三步截图 `t3-legacy-step{1,2,3}`。
- 配方固化 = `gui-acceptance/v2m/MANIFEST.md`「FIX2-01 批 T3 legacy
  通道正确配方」节（含 W4 复走映射表）。核销口径 = **翻案核销（走查
  错腿 + inert-by-design），非代码修复**；V2 #4 无前置。证据缺口自愈：
  probe-14（返回图库）重产 ✓；probe-16（legacy 面件清单）= File 菜单
  AX 清单文本在案（本批 transcript）；probe-8（导入完成面）= T2 的
  probe 轮 transcript 族替代在案。

## 4. T4 — 红线族机检（全 PASS）

`.metal`/LightamerIOP/sidecar/封存面（029f84bc..HEAD）零 diff；
`\.runModal(` App/Sources 零命中；LocalizationValue 插值禁形 regex 命中
仅 ：2069 doc comment（豁免锚）；UserDefaults 零新键；xcstrings 零
diff；Project.swift = 恰 T2 测试一行 + BUNDLE-MAP 一行（tuist generate
已随批执行恒末位）。

## 5. T5 — 走查复走（执行中；终态落 MANIFEST）

- W1：D-6 三铁条 = **Blocked（升级待裁，T1 未过）**；依赖编辑器通道行
  随之 Blocked。
- W2（legacy 配方 ⌘⇧O 会话腿）/ W3（D-7 复验 + F-1 现状）/ W4（legacy
  行）：按 MANIFEST 配方执行，逐行终态见 MANIFEST「FIX2-01 T5」节
  （本文件不重复记账）。

## 6. 移交与上报（orchestrator 决策项）

1. **D-6 三选一**（DECISIONS D-FIX2-1 处置节）：①接受降级（挂账框架侧
   + 专项立项 gate=false 壳减树/窗口内容拆分）②research 复审（带五条
   读数）③回退 macOS 27 目标评估。
2. **导入零行间歇**（D-FIX2-4）：11 轮 3 中，per-file insert 静默失败，
   独立待研。
3. IOP NLMeans 窗外 crash flake 1 例（隔离重跑绿，台账延续）。
