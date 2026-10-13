# M6-2 CONTEXT — per-photo process version（discuss/research 起草批，2026-10-13）

> Phase = M6-2（ROADMAP §Milestone 6 M6-2 行 + REQUIREMENTS M6INT-01：`.lra` additive
> 可选 `process` 键 + 旧号冻结纪律 + legacy 缺键不序列化语义〔HistoryHash/缓存键
> 逐字节不变〕——LightCraft 裁决③，用户回批 2026-10-11 按推荐立项）。本文 = 研究
> 定稿载体 + **C 档第 1 停裁决面**（OQ-M6-2-1..6 交用户；全带推荐，用户可随时推翻）。
> 读解正本 = 同目录 `RESEARCH-NOTES.md`（§ 引用见各条）。
> 设计底稿 = `phases/m6-1-interop/RESEARCH-NOTES.md` §6（前瞻 B）。
> 状态：research 起草完成 → **C 档第 1 停**：OQ 裁决前不进 plan。

## Phase Goal（ROADMAP 原文锚定）

引入 per-photo 渲染过程版本纪律（Lightroom process version / LightCraft
`DevelopSettings::process` 同构）：**改观感的 iop 语义变更必须开新 process 号，
老照片渲染零漂移直至显式迁移**。落点 = `.lra` 文档级 additive 可选 `process` 键
（缺键 = legacy = 冻结语义；写腿缺键不序列化 → legacy 档 re-encode 字节零漂移，
LightCraft `hash64` 技巧同构）+ Core 级 process 常量与枚举账本 + 管线读缝
（run-scoped，`terminalTail`/`filmTail` 装配点先例）+ 冻结 golden。

背景缺口（RESEARCH §1）：我方 iop 调观感（nlmeans 重调、tone model 变更、
M5 TRACK/Mertens 落地后调参概率升高）会让全部老 `.lra` 渲染漂移——现有兜底
只有 schemaVersion 整体迁移语义与 `ModuleInstance.version`（modversion 类比，
且其折入 `HistoryHash` → bump 即老档假阳 drift，不是语义变更的可用载体，
RESEARCH §3.6）。process version = 该缺口的根治纪律，越早越省。

验收形态（ROADMAP M6-2 行）= sidecar additive 零漂移负测（v9 档字节零改）✓
+ 冻结语义 golden（同档跨 process 语义变更渲染逐位不变）✓ + 管线 process 读缝
零行为门 ✓。

## 决议（D-M6-2-N，均带推荐；最终裁定 = 对应 OQ）

### D-M6-2-1 键面与 schema 承载（RESEARCH §3.1/§3.2）

- 推荐**文档级 additive 可选键 `process: Int?`** + `schemaVersionCurrent`
  9→10（v6/v7/v8/v9 每 bump 各承载其键族的惯例延续）。三则语义：
  - **缺键 = legacy = process 0 = 冻结语义**（写腿 `encodeIfPresent`——legacy
    档 re-encode 键保持 ABSENT，v9 时代字节面零漂移；LightCraft
    `skip_serializing_if = "ProcessVersion::is_legacy"` 同构）；
  - **新档 mint = `RenderProcessVersion.current`**（Core 常量，起步 = 1）——
    仅「首次建档」（盘上无 sidecar）时盖章；既有档 re-save 恒保留原值
    （legacy 档永不被动升级，零漂移承诺本体）；
  - 语义冻结纪律：改观感的 iop 语义变更必须 bump `current` 并为旧号保留冻结
    分支；不改观感的重构（性能/内部结构）不 bump。
- 键拼写 `process`（LightCraft 同名；单词无 camelCase 歧义），plan 期冻结。
- 被否形态：additive-in-v9 不 bump（破「一键族一 bump」惯例，v9 语义膨胀）；
  独立字段/独立文件（无先例，读写面成本）；挂在 `instances[]` 或 history item
  内（粒度错位——process 是文档级渲染语义非模块/编辑属性）。**最终裁定 =
  OQ-M6-2-1。**

### D-M6-2-2 hash 与缓存纪律（RESEARCH §3.3）

- 推荐 **hash isolation**（v3 五元数据/v4 provenance/v5 rawOverrides/v7
  versions/v8 aiProvenance 先例族）：`process` 不折入 `HistoryHash.hash` /
  `driftDetected`（它是渲染语义标签，非用户像素编辑；折入会让未来语义升级
  误报 external-edit drift——set-fields-move 被否理由），不产生 history item
  （commit 面零触），undo/redo/版本 swap 零触（文档级常量跨编辑历史恒定）。
- 缓存键（`PipeCacheKey.upstreamHash` 链）：**只在 process 分支真分叉的代码
  路径折 process 值**（`edgeMapAlgorithmVersion` 折键先例；M6-2 无分叉 =
  键面零变化；缺键 = 0 恒，legacy 档键面零变化）。
- Copy Adjustments（M2-8 `isAdjustmentTransferable`）**不携带 process**——
  目标照片按自己的 process 解释粘来的参数（LightCraft「copy/paste/sync/presets
  never carry the process」同构；文档级键天然不在传输集，负测钉死）。
- 被否形态：set-fields-move（`drtRecord`/`filmRecord` 先例形——process 非
  「用户改了它」的编辑面）。**最终裁定 = OQ-M6-2-2。**

### D-M6-2-3 读腿宽容性与前瞻值（RESEARCH §3.4）

- 推荐 **LightCraft lenient 原形**：
  - 合法域 = 整数 0..2^32−1（`2.0` 记 2）；域外/损坏值（负数/小数/字符串/
    null/数组）→ **legacy（0）**，不毁档其余字段（tolerant decode 纪律），
    且损坏值不保留（存回 = 键 ABSENT）；
  - **比本 build 更大的 process 号** = 读入保留（存回不降级用户数据）+
    渲染钳到已知最新（`RenderProcess.current`）——新版本 app 写的档在旧
    build 上可读可渲染（前向兼容，LightCraft `ProcessVersion::process()`
    钳制同构）。
- 被否形态：损坏值 decode error 整档拒读（违反 tolerant decode 纪律）；
  未知大号直接重写为本 build 值（降级用户数据）。**最终裁定 = OQ-M6-2-3。**

### D-M6-2-4 M6-2 零行为基线与枚举账本（RESEARCH §3.5/§3.6）

- 推荐 **M6-2 交付面 = 机制 armed + 渲染零行为**：Core 级
  `RenderProcessVersion`（Int 值类型，0 = legacy 哨兵）+ `RenderProcess` 枚举
  （compiler-exhaustive，case doc-comment 即账本——LightCraft `Process` 枚举
  `ALL`/`LATEST` 先例）+ 管线 run-scoped 读缝（`PixelPipe` 装配点属性，缺省 =
  legacy，`terminalTail`/`filmTail` 同位先例）。**M6-2 时点 process 0 与
  process 1 渲染逐位恒等**（尚无语义分叉）——首个真实分叉由未来 iop 语义
  变更引入。
- **bump 纪律的程序面**：M6 批内任何 iop 调参/语义变更（含 M5 TRACK/Mertens
  后续调优）落地时必须同时 bump `current` + 旧号冻结分支 + 冻结 golden 更新；
  登记处 = AGENTS.md 架构增量节 + 枚举 case 注释（无 CI 可机检语义变更，
  纪律 = 流程序 + golden 可见性）。
- 顺带澄清（RESEARCH §3.6）：`ModuleInstance.version`（modversion 类比）是
  **params 形状迁移**（decode 域）且折入 `HistoryHash`——bump 即全量老档
  假阳 drift，**不得**用作语义变更载体；process 与 modversion 正交并存。
- 被否形态：M6-2 顺带做一个演示性真实 bump（无真实调参场景，为演示而改观感
  = 人为制造漂移面）。**最终裁定 = OQ-M6-2-4。**

### D-M6-2-5 迁移 UX（RESEARCH §6）

- 推荐 **v1 = 无显式迁移动作**：老档恒冻结（零漂移承诺本体）；
  「Update to Current Process」挂账至首个真实消费场景（首个 iop 语义 bump
  落地时裁交互形态——面板按钮 vs 菜单项 vs MCP 工具；LightCraft
  `develop.updateProcess` 一步 undo 形态为参考底稿）。
- 被否形态：M6-2 即交付迁移按钮（无消费场景的空转面，交互形态无依据）；
  自动迁移（破坏零漂移承诺）。**最终裁定 = OQ-M6-2-5。**

### D-M6-2-6 golden 门集与范围边界（RESEARCH §5）

- 推荐 **四门**（ROADMAP 验收形态三件全覆盖 + mint 面）：
  ①additive 零漂移负测（v9 档 decode→re-encode process 键 ABSENT + 既有键
  逐字节；v10 无 process 档 re-encode 字节面钉；legacy 档 historyHash 重算
  零漂移）；②冻结语义 golden（测试替身模块按 process 分叉输出——legacy 档
  跨「模拟语义变更」渲染逐位不变 + 新 process 臂真分叉可见；LightCraft
  `settings_saved_before_process_versions_load_as_v1` 同构）；③管线读缝
  零行为门（process 0/1 渲染逐位恒等 + `PipeCacheKey` legacy 键面零变化）；
  ④mint/传输面（新档首写 = process 1 入档；Copy Adjustments / 预设 apply /
  版本 swap 零携带）。
- 范围边界：**零 MCP 工具面、零 UI 面、零格式矩阵触碰、零新 SPM**；测试
  落域按 BUNDLE-MAP 登记 + `tuist generate` 恒末位（L041）。
- **最终裁定 = OQ-M6-2-6。**

## Open Questions（OQ-M6-2-1..6，全带推荐；C 档第 1 停裁决面）

- **OQ-M6-2-1（键形态与 schema 承载）**：文档级 additive 可选 `process: Int?`
  + schemaVersion 9→10 bump；缺键 = legacy = 0 = 冻结；新档 mint = current(1)；
  键拼写 `process`？**推荐 = 是**（RESEARCH §3.1/3.2）。
- **OQ-M6-2-2（hash 与缓存纪律）**：hash isolation（不折 HistoryHash/
  driftDetected、零 history item、undo/版本 swap 零触）+ 缓存键仅在分叉路径
  折 process 值 + Copy Adjustments 不携带？**推荐 = 是**（RESEARCH §3.3）。
- **OQ-M6-2-3（读腿宽容性与前瞻值）**：合法域整数 0..2^32−1（2.0 记 2）、
  域外/损坏 → legacy 且不保留、更大号保留 + 渲染钳已知最新（LightCraft
  lenient 原形）？**推荐 = 是**（RESEARCH §3.4）。
- **OQ-M6-2-4（M6-2 零行为基线）**：机制 armed + 渲染零行为（process 0/1
  逐位恒等），枚举 case 注释即账本 + AGENTS 登记 bump 纪律，否决演示性
  bump？**推荐 = 是**（RESEARCH §3.5/3.6）。
- **OQ-M6-2-5（迁移 UX）**：v1 无显式迁移动作，「Update to Current Process」
  挂账至首个真实 iop 语义 bump 场景再裁交互形态？**推荐 = 挂账**
  （RESEARCH §6）。
- **OQ-M6-2-6（golden 门集）**：四门（零漂移负测 / 冻结 golden / 读缝零行为
  门 / mint+传输面），否决 ROADMAP 三件最小面（补 mint 门）？**推荐 =
  四门**（RESEARCH §5）。

## 状态

research 起草完成（2026-10-13，M6-1 closed 后接棒批）→ **C 档第 1 停**：
OQ-M6-2-1..6 交用户裁决（全带推荐；晨审/用户可随时推翻）→ 裁决回批后进
plan round（执行分工照 Phase 执行模型 = omp 执行 + subagent 验收；
plan_review_by_omp = true）。

## 裁决记录

（待用户回批后补记。）
