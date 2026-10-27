# M9-1 SUMMARY — AI Mask 工具 parity 执行摘要（T1..T5 终账）

> 执行批 2026-10-27，HEAD `371a3d95` 起（plan v2 基线核后 CC-ARW 终态）。
> GitHub issue = **#11**（kamasylvia/Lightamer，M9AIM 族合并单，四产品
> commit 全带 `refs #11`）。裁定正本 = `M9-1-DECISIONS.md`（D1..D15）；
> 走查配方 = `.work/gui-acceptance/m9-1/MANIFEST.md`。

## 逐任务战果

| T | 战果一句话 | 定向回归 | commit |
|---|---|---|---|
| T1 | 任务面板四 icon 落地（Subject/Background 共腿 + invert 位、People = person 族子集确认、Sky = 恒 disabled 槽 + tooltip）；AIMaskTask enum 单源；AIMaskEditing 零 diff | App 1024/6/0 | `feat(m9aim): add ai mask task panel…` |
| T2 | Feather px 域对齐（σ_px 换算单源 + 反向折算）+ Expand = vImage 3×3 交替形态学（CPU 合法偏离申报；vImage bias 核方向雷 D8 攻克——ε 参与位量化域精确 + 方向性 ±1e30 排除位）；bake 序 expand→feather→quantize golden 钉死 | Layers 516/5/0 | `feat(m9aim): add expand morphology…` |
| T3 | 逐点即解（300ms debounce 全量重解 + 候选 plane session 态 + 保留旧候选）+ Path 等弧长 24px 采样（Core 纯函数件）+ 候选 coverage 专用合成臂（`MaskOverlayStyle.candidate` + picker 白名单 + Commit/Cancel 双清除）+ 点删/绿红 disc 视觉 + `.scribble` seam 全撤（m-5） | PathSampling 6/0 + Iterative 8/0 | `feat(m9aim): add iterative tap-to-segment…` |
| T4 | 会话三命令收口（open 三源显式 re-entry〔m-4 意图改写〕/ commit 恰一条维持 / cancel = Done·Escape 收敛丢弃）+ paste 排除 AI bake 件（语义反转申报 + 跳过名单 toast + 手绘不排保守臂） | SessionCommands 5/0；App 1037/6/0 | `feat(m9aim): add mask session commands…` |
| T5 | BUNDLE-MAP 六行 + zh-audit 双 PASS（三死键配平删除后 PASS）+ 全套对账（下行）+ 走查配方落盘 | 见下行全套 | `test(m9aim): register…` |

## ΔN 对账（实数 vs 带）

| 域 | 新测试文件 | 法数 |
|---|---|---|
| LAYERS | AIMaskMorphologyTests | 5 |
| LAYERS | AIMaskFeatherPxTests | 4 |
| LAYERS | AIMaskPathSamplingTests | 6 |
| APP | AIMaskTaskPanelTests | 5 |
| APP | AIMaskIterativeSessionTests | 8 |
| APP | AIMaskSessionCommandsTests | 5 |
| **合计** | 六文件（三 LAYERS + 三 APP） | **+33** |

- **带 = +20..29（plan m-2 上限 29；charter +20..28）——实数 33 越带上
  限 4**。越带全部落在 T3（14 vs 6..9）：Iterative 八法与 AI-06/交互
  断言面一一对应（并法则掩盖独立红线），PathSampling 六法 = 数学面
  独立（格点/归一化/跨段/短笔触/折叠/截断）。申报正本 = DECISIONS
  D15。
- 存量改写（非增量）：`AIMaskSemanticTests` scribble 拒绝 → Path 激活
  正测（1 法原位）；`AIMaskPatchFlowTests` person 路由断言随三源扩源
  翻转（1 法原位）；`LayerUIWiringTests` scribble 段删除（法数不变）。

## 全套终值对账

- **基线（CC-ARW 解禁后）= 4295 executed / 33 skip / 0 fail**（开工基
  线核：IOPParity GoldenColorTests 6/0/0 亲测 PASS）。
- **预期终值 = 4295 + 33 = 4328 executed / 33 skip / 0 fail**（skip 面
  不变：真模型门/性能探针门既知形态）。
- **实跑终值 = 4328/33/0**（2026-10-27 全套 `--all` 夜间授权轮亲跑，
  4040s：IOP 788/1/0 · IOPParity 529/9/0 · Layers 522/5/0 · Library
  782/4/0 · Sessions 285/4/0 · Export 385/4/0 · App 1037/6/0；MEMFAIL
  机检 0 触发，峰值 = IOP 6227MB（< 8G 门），monitor 21600 伴跑零
  kill 事件）——**预期逐值命中**。
- 定向收口轮：Layers 522/5/0（+6 PathSampling）、App 1037/6/0（+18 =
  T1 5 + T3 8 + T4 5）。

## zh-audit

- `--check` **PASS**（1732 source keys / 2048 catalog keys / 10 interp
  keys variant-PRESENT + spec-matched；zh 全量；locale = {en, zh}）。
- `--self-test` **PASS**（V17 golden 八例）。
- 本批键族：`ai_task_*` 五键 + `ai_mask_expand_label/reset` 两键 +
  `ai_candidate_solving/ready` 两键 + `transfer_ai_masks_excluded
  %lld` 一键；显式**不加** `mask_overlay_style_candidate`（M-1 死键防
  御）与 `ai_path_tool`（D11 零消费面）；删除 T1 迁移死键三枚
  （ai_mask_subject 族）。

## 封存面与红线声明

- **封存面 17 件零 diff**（含 Core PixelPipe——本批候选通道全走 App 侧
  PipeCoordinator 专用臂，零 Core 触碰）。
- 零新 SPM / 零新模型 / 零新 `.metal`；sidecar schema v11 零 bump；
  UserDefaults 零新键；V50Order 零触碰；GPL 零复制（形态学/σ 式/采样
  常量/色值 = 公开数学与数值参数，出处引 RESEARCH 附录表）。
- 机器纪律：每重活轮 guard 前置（G1-G4）；GUI 实例测试起跑前 ps 清零
  核；全套伴跑 `machine-guard --monitor 21600`；commit-per-task × 5。

## 走查与验收指针

- 走查配方 = `.work/gui-acceptance/m9-1/MANIFEST.md`（六项：任务面板
  Sky disabled 态 / 逐点即解候选消长 / Path 采样计数 / Feather·Expand
  slider px 域 / paste 排除 toast / cancel 丢弃；AXPress 纪律 + M9AIM-02
  承载映射三层链登记）。
- **C 档停**：本批闭环，等用户过目（走查样例清单见 MANIFEST）后再谈
  M9-2。omp 二次验收（computer-use 串行）由 orchestrator 排程。
