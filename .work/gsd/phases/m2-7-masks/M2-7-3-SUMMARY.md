# M2-7-3 SUMMARY — 收口批（质量走查 + 性能观察 + zh 对账 + 翻账移交）

> 执行 worker（2026-10-01，夜间授权连跑）。plan 正本 =
> `M2-7-3-PLAN.md`（checker 修正版 7b88bbb）。**全套回归终跑（报备制已履行，
> coordinator queued）= 见 §测试数字**（熔断触发产生一行源码增量 → 恢复
> AC8 全套门；基线 = P2 终数 2525/16skip/0fail）。

## 交付面（四任务四提交）

| 任务 | commit | 内容 |
|---|---|---|
| T1a | `853172e` | Follow Edges 三景 × 两模式走查证据入 `evidence/m2-7-3/`（ev_A/B/B2/C 真样张叠加图 + field_vis + GUI 两张 + probe/ 源码与日志）——走查形态与熔断判据实测记录（本文件 §走查裁决） |
| T1b | `60582c3` | **熔断行使（OQ-4-C）**：`LayerEditingState.followEdgesParams` 默认值翻 `.snap`（功能一行 + 站点挂账注记四行）；walker/`.streamline` 分支零删除，模式选择器仍可选 |
| T2 | （docs） | `perf.md` phase 级账本：三表（stamp 基线复测 / 缩略 pass / edge map 首算+缓存命中）+ 环境行 + OQ-11 预算项逐条对照 |
| T3 | `78b4f0f` | zh/en 对账：52 键（en+zh）入 `Resources/Localizable.xcstrings`，纯插入 884 行旧键零触碰；`zh-audit --check` 复跑 **PASS exit 0**（1321 source / 1547 catalog） |
| T4 | 本批 | REQUIREMENTS M2MASK-05 熔断注记 + ACCEPTANCE-INPUT 移交清单 + GOAL-STATE 续接点 + TODO + AGENTS.md M2-7 增量节 |

## 走查裁决（KD-1；证据 = `evidence/m2-7-3/`，数字可复核）

**裁决 = 熔断触发（判据②），默认 `.snap` 交付；streamline 挂 V2。**

- **走查形态披露**：GUI pointer 通道环境受限（synthetic CGEvent 点击不达目标
  窗口、System Events `click at` 无效、AX 仅元素级可达——P2 E3 同根因实锤），
  三景 × 两模式走查以**进程内真链探针**完成：`CIRAWFilter` 真解码
  DSC00012.ARW（60.2MP）→ 真 `mask_edge_map` kernel（MaskEdgeKernels.metal
  原文运行时编译）→ 真 L014 fence 读回链 → 仓库 `FollowEdges.swift` 原文
  编译（脚手架 shim 仅复制 `makeEncoder`/`maskLikeShape` 机械；walker 零改动）。
  探针正本 = `evidence/m2-7-3/probe/`（main/shim/extract + probe.log）。
  **禁造假纪律：本节数字全部来自 probe.log，无引用冒充实测。**
- **判据①（交互延迟 200ms）**：冷（edgeMap GPU + fence 读回 + ≤512 降采样）
  ×10 中位 **6.1ms**（min 5.7/max 7.3；首调 PSO 编译噪声 74.8ms 一次性）；
  热（缓存命中 walker-only）×100 中位 **~0.001ms**——**远内**，非触发项。
- **判据②（弯曲轮廓断链 >2 且 snap 显著更稳）**：**成立**——
  - 8 个景盒（直边 ×3 / 灯笼圆轮廓 ×3 / 低对比 ×2）× 2 阈值（0.25 默认 /
    0.15）：streamline 链长全部 ≤3 点（功能性笔划需 ≥10 点量级）；
  - 100-seed 全场网格：82/100 空链，非空链均为 1 点孤子；
  - 控制组：场分辨率 1024/2560（无降采样）× 步长 1.5/0.75 扫频 =
    **0/3 功能链**——排除「≤512 读回降采样碎脊」假说，失败在 walker 对
    真实照片脊型（细脊 + 幅值快速衰减 + 分叉）的假设本身；
  - snap：12px 触达内**确定性** 2 点贴边线（ev_B_snap 灯笼上缘亲证）。
- **判据③（100MP FULL 边缘图读回 >1 帧）**：**n/a（路径不存在，非豁免）**——
  P2 seam 只跑 preview 桶（`followEdgesSurface` = `.preview` + bucket cap）；
  FULL 9504×6336 单发 80.3ms 作为语境数字记录于 perf.md 表三。
- **行使动作**：`60582c3`（UI 默认值一行；walker 代码保留——V2 复活零重写）。
  M2MASK-05 REQUIREMENTS 注记措辞按 KD-1 预制：「Delivered（snap 态，
  streamline 挂 V2）」。

## 性能观察项终值（OQ-11 清账；详 perf.md）

| 观察项 | 终值 | 处置 |
|---|---|---|
| 边缘图首算 / 缓存命中 | 冷 6.1ms 中位 / 热 ~0.001ms（同层连笔恒命中——mask append 不在 prefixHash 折叠集） | 达标 |
| 缩略 pass 单格 + 20 格滚动 | **未测得**（探针不可达 Core framework 闭包 + GUI 无蒙版内容可渲） | Manual-Only 挂账（不虚报） |
| 双羽化手柄拖动实时性 | GUI 实操未取得（E3 五点之一） | fallback 未启用；Manual-Only 挂账 |
| stamping 基线 | 0.744ms/千枚 bench 引证（rasterizer 零 diff）+ Layers 298/3/0 golden 族新鲜复归 | 有效 |

## zh/en 对账（KD-3）

首跑 `--check` = **39 缺口**（FAIL exit 1）；与 P2 DECISIONS §五 52 键清单
对账：差额 13 键为动态族（Core 映射 range 标签 / tool+command labelKey stem /
commit label switch / Picker 字面量——scanner 不可见），**52 键全族照补**
（预估 40-70 内，无膨胀）。diff = 纯插入 884 行（52 × 17 行），旧键零触碰
（零 `-` 行）。复跑 **PASS exit 0**（1321 source / 1547 catalog / locale =
{en, zh}）。

## 测试数字 vs 基线

| 轮 | 结果 |
|---|---|
| 基线（P2 终数） | 2525/16skip/0fail（882s） |
| 熔断行后定向复归 | App **429/0/0**（167s）+ Layers **298/3/0**（25s）——逐值 = P2 域终值 |
| **全套 `--all` 终跑（报备制，coordinator 批准；净轮）** | **`TOTAL|2525/16/0|877s EXIT=0`**——IOP 467/1（峰值 7850MB）、IOPParity 362/3、Layers 298/3、Library 430/4、Sessions 279/4、Export 260/1（6785MB）、App 429/0（1330MB）；skip 16 持平；P3 零新增测试 = 与 P2 终数逐值持平；MEMFAIL 零触发（峰值 IOP 7850MB < 8G 门，±3% 方差注记内） |
| 全套首轮（事故轮，如实登记） | `TOTAL|2179/16/0|764s`——IOPParity 16/3/0 **被截断**（见下 §执行事故），其余六 bundle 逐值平基线零 fail；证据 `evidence/m2-7-3/all_run_incident.log` |

## AC 总表机检（8/8）

| # | AC | 结果 |
|---|---|---|
| 1 | 三景 × 两模式证据 + 判据三项有数字 + 裁决明确 | ✅ evidence/m2-7-3/ + 本文件 §走查裁决（裁决 = 熔断，无含糊态） |
| 2 | perf.md 三表 + OQ-11 逐条对照；超标有处置 | ✅（缩略项「未测得 + 挂账」如实记录，无静默超标） |
| 3 | zh-audit 复跑 exit 0；M2-7 键族全覆盖；旧键零触碰 | ✅（PASS；diff 纯插入） |
| 4 | REQUIREMENTS M2MASK 措辞与实态一致 | ✅（M2MASK-05 补 P3 熔断注记，其余六行 P1/P2 验收批已翻不动） |
| 5 | ACCEPTANCE-INPUT 四节齐 | ✅（AC 指针 / 熔断记录 / 挂账 / Manual-Only） |
| 6 | GOAL-STATE 终态 + TODO 推进 + 收口 md 同批 | ✅ |
| 7 | 源码 diff = 熔断行 + zh 键，零第三类 | ✅（`git diff 7b88bbb..HEAD --stat` 逐文件核对：LayerEditingState.swift + Localizable.xcstrings + .work md/evidence，零其他） |
| 8 | 全套回归 0 fail（基线 = P2 终数） | ✅ 净轮 `TOTAL|2525/16/0|877s EXIT=0`（BUNDLE 行双读；首轮事故轮如实登记 §执行事故） |

## 偏差与挂账

- **偏差 1（熔断落点文件）**：plan 申报熔断行在 `MaskToolbarView.swift`；
  实际默认值落点 = `LayerEditingState.swift:189`（toolbar 无默认值——读
  `editingState.followEdgesParams`，Core init 缺省 `.streamline`）。为不动
  Core（FollowEdgesTests 可能钉缺省），行使行落 App 消费点，语义同 plan
  （UI 默认翻 `.snap`）。功能 diff 一行 + 站点注记四行（挂账登记同步，
  plan T1 AC 要求）。
- **偏差 2（走查形态）**：plan KD-1 预期「Debug 构建 + 真实样张 GUI 走查」；
  pointer 注入不可达（E3 同根因）→ 探针真链走查替代，GUI 截图仅存工具栏
  武装态证据。验收 subagent 有权以证据复核推翻（plan 风险节原文）。
- **挂账（移交验收批）**：GUI 交互五点（缩略格渲染/锁删 toast/Locate 联动/
  双羽化手柄拖动/ask sheet）+ 缩略 pass 运行时数字 + 100MP 真机走查 +
  streamline V2（walker 保留）——全清单在 `M2-7-3-ACCEPTANCE-INPUT.md`。

## 红线核

源码 diff 全集 = `LayerEditingState.swift`（熔断行）+
`Resources/Localizable.xcstrings`（zh 键）——`git diff 7b88bbb..HEAD --stat`
零第三类源码文件（evidence/probe/.work md 为 plan 申报面）。walker 与
`.streamline` 分支零删除（源码 grep 在案）；GPL（Alcedo/darktable）只读
零拷贝；未 push。

## 执行事故（如实登记；晨审可推翻）

首轮 `--all` 进行中，执行 worker 清理本会话启动的 GUI 进程时误判双斜杠路径
的 IOPParity **测试宿主**为 GUI 实例并 `kill`（宿主路径同构：test-direct.sh
的 `HOST_BIN` 与 `open` 启动仅一斜杠之差），截断该 bundle（16/3/0 ≠ 362/3/0；
零 fail，纯 executed 截断）。处置 = 待首轮跑完留证（`all_run_incident.log`）
后**干净重跑全套**，终值取净轮（上表）；其余六 bundle 两轮逐值一致佐证无
连带影响。教训入 AGENTS.md M2-7 增量节同批（进程清理前先核 parentage——
`ps -o ppid`，测试宿主 parent = 脚本进程树）。

---

**全套终值行（净轮）**：TOTAL|2525/16/0|877s EXIT=0（7 bundle 逐域：IOP
467/1、IOPParity 362/3、Layers 298/3、Library 430/4、Sessions 279/4、Export
260/1、App 429/0——与 P2 终数逐值持平，P3 零新增测试；MEMFAIL 零触发，峰值
IOP 7850MB < 8G 门）。
