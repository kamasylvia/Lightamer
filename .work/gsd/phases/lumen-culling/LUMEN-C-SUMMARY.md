# LUMEN-C SUMMARY — 蒙版精细化(LU5)执行摘要

> 执行批 = LUMEN-C-PLAN.md(checker `75678937` + fixer `a0e43b44` 后 HEAD;批起点
> = LUMEN-B 终态 `8896a46e`)。执行窗 = 2026-10-24。逐任务 commit-per-task,
> 全英文 Conventional Commits(`lumenc` 前缀),零 issue ref(内部规划口径——
> A/B 批同款备案:仓内 issues 未启用)。裁定正本 = 同目录 `LUMEN-C-DECISIONS.md`。

## 逐任务记账

| 任务 | commit | 内容 | 测试 |
|---|---|---|---|
| T1 | `66730d55` | MaskRefine 五步直译(Lumen v2.0.1 `selection.py fine()` 族;MIT 归属头 + NOTICE 条目 Q 补行;Accelerate/vDSP 全 CPU 零新 Metal kernel;fineSize 4096 钳) + golden(cv2/NumPy 参考对拍,fixture 双写入库) + 场景参照(twigs/broad-ramps/置信门控/grow-shrink 钳/畸形容错/钳数学/探针) | MaskRefineTests +8(LAYERS,1 探针默认 skip) |
| T2 | `c374889d` | MaskRefineCoordinator(refine_masks_later 直译:单飞 + 等待队列 + 失败保快速蒙版 + toast;一步 history commit 走既有 commitRasterMask 缝;`loadPlane` additive 只读腿;guide = headless 显影显示域 ≤4096;fineAuto debounce 1.2s 自愈形)+ AIMaskEditing additive hook/refineCommit + EditorState.maskRefine + 工具栏手动入口 | MaskRefineCoordinatorTests +6(APP) |
| T3 | `e5790c59` | EditingToolset.Seams additive refineMasks(默认 nil)+ refine_masks 工具(nil = typed 不可用脸;live-image 要求;McpRenderGate 串行;requiresWriter+Control)+ LightamerShell post-assignment 供给(McpServerController 零 diff——FIX2③ 兑现)+ 快照 conscious 批(32→33 / 23→24 六文件)+ tools.md 重渲染 | McpRefineMasksToolTests +5(APP) |
| T4 | `23664aba` | Settings「蒙版精细化」节(mask.fineAuto,AppPreferences alias,键字面量全仓恰一处)+ Project.swift 三行正式注册 + BUNDLE-MAP 三行 + tuist generate 批末位 + xcstrings +3 | —(收敛) |
| 收口 | (本 commit) | 本 SUMMARY + DECISIONS + `.work/gui-acceptance/lumen-c/MANIFEST.md` + 全套 --all 三轮对账 + AGENTS 键族登记 | — |

## ΔN 终账(定向机检值)

- 计划带 **+6..7**;实账 **+19**(LAYERS 494→502 = +8;App 996→1007 = +11)
  ——**越带 +12..13**,申报:每条 SC 子句一测纪律(A/B 批同款先例)+ T1 的
  golden/场景/门控/钳/容错/钳数学七面 + T2 的单飞/队列/置换/自愈环/失败
  保底/门控/MCP typed 七面 + T3 的快照/不可用脸/live 要求/typed unknown/
  gate 串行五面(详见 DECISIONS §3)。
- **T4 末轮定向(正式注册后全量)**:`--bundle Layers` **502/6/0**、
  `--bundle App` **1007/6/0**——全绿零回归(skip = 既有家族 + 本批恰一
  新增族:LU5 时长探针,DECISIONS §3.6)。

## 全套 `--all` 对账(批末位职责;三 plan 合计)

- 运行形:`Scripts/machine-guard.sh` PASS 后 `caffeinate -dis` + nohup 三轮
  连跑(证据 = `evidence/lumenc/all-3rounds.log`;PID 记录同目录 .pid)。
- **三轮实测——逐轮同值,全绿零失败**:

| 轮 | executed/skipped/failed | 用时 | 备注 |
|---|---|---|---|
| R1 | **4204/41/0** | 2246s | IOP 771/5/0 · IOPParity 478/6/0 · Layers 502/6/0 · Library 776/4/0 · Sessions 285/9/0 · Export 385/5/0 · App 1007/6/0 |
| R2 | **4204/41/0** | 2281s | 逐 bundle 同值(峰值 RSS IOP 5269 / Export 4134-4137 / IOPParity 4206-4444MB,全在 8G 门内,零 MEMFAIL) |
| R3 | **4204/41/0** | 2297s | 同值复证通过 |

- 对账算术:基线 4112/40/0(r12) + A 实账 +31 + B 实账 +41 + C 实账 +19
  = 4203 ± 1;**实测 4204**——±1 落在 r12 基线快照与 A/B 时代逐 bundle
  快照之间的组成漂移(C 自身增量按 bundle 链完全对账:Layers 494→502 =
  +8、App 996→1007 = +11,其余五 bundle 与 B 收口值逐位一致,零无解释
  增长)。skip 40→41 = 恰一本批新增探针族(DECISIONS §3.6)。
- 计划带 4144..4152 的越带差额 = A +16..19 与 B +23 的历史越带
  (B-DECISIONS §9 正本)+ 本批 +12..13(DECISIONS §3)——全套诚实重算
  如上,死数不做对账依据。

## 验收判定(机检汇总)

- 构建:全任务 TEST BUILD SUCCEEDED;`tuist generate` = T4 注册批末位一次
  (+ 收口 docs 批零再生成)。
- 定向:T4 末轮 Layers 502/6/0 + App 1007/6/0 全绿(t4-*.log)。
- golden:MaskRefine vs cv2/NumPy 参考 **mean |Δ| 2.8e-3 / max 6.4e-2**
  (带 0.02/0.15;fixture = `Resources/TestFixtures/maskrefine/
  maskrefine_golden.bin`,生成器 = `evidence/lumenc/maskrefine_reference.py`;
  偏差源 = DECISIONS §3.4 的 chamfer/解析 Gaussian 形差)。
- 红线核:`McpServerController.swift` **零 diff**(`git diff 8896a46e..HEAD` 空
  ——FIX2③ 零例外,review M-4);`AIMaskFeather.swift` 零 diff(X8 正交);
  封存面(HistoryStack/HistoryHash/LightamerSidecar/PixelPipe/
  Lut3dKernels.metal/DrtRecord/V50Order/GradeCatalog)零 diff;零新 Metal
  kernel(`import Metal|MTLCompute` 文件域零命中);`4096` 钳常量文件域恰
  一处;`mask.fineAuto` 字面量全仓恰一处;refineMasks 供给恰两处(Seams
  声明 + Shell 装配);xcstrings 三次尾插(48/48/48 行纯插入,zh-audit 双
  PASS 1719/2038);L009 零触碰面;L041 tuist 末位;L057 零新面板;
  LocalizationValue 禁形零命中。
- MCP 注册面:33 工具闭集(编辑域 9→10;culling 14 零触);typed 不可用
  脸/live 要求/unknown typed/gate 串行五面测试在册。
- 探针:LU5 时长探针在册(240×160 直译路径 34ms `-O` 参考值;1024×768
  探针 skip 族)——实机样张走查挂 validate 道(`.work/gui-acceptance/
  lumen-c/MANIFEST.md`,与 B 批 C1/C2 遗留同轮)。

## C 档停位

本 plan 执行 + 验收闭环 = **停汇报**。lumen-culling 批(A+B+C)收口;
全套 `--all` 三轮对账表回填于上节;GUI 走查(A1-A6/B1-B4/C1-C2)待
validate 道。
