# F0P-LENS-B2-VERIFY — B-2 接线修复聚焦补验（第二路补验注记，2026-10-21 夜）

> 对象 = `7d3c2274`（fix(lens-01): wire reloadDefaults into production
> seams — B-2）。要害源 = 第二路 blocking 正本
> `lens-01-lensfun/LENS-01-ACCEPTANCE-2ND.md` §1（B-2 写入路径端到端
> 不可达：reloadDefaults 零生产调用点 → auto-apply/EXIF 输入/快照
> bake/detected 确认门全死路）。零源码改动；本注记落盘即产物（不
> commit）。证据 = `lens-01-lensfun/fix-batch/acc2nd-{legA,all}.log`。

## 结论头

**PASS / 0 blocking + 0 major + 1 minor + 4 obs**

三缝接线逐缝亲核过（语义对 LENS-02 T2/T4 设计一致）；反死路双腿
本环境复现（腿 A = LensDefaultsWiringTests **8/0/0** 绿；腿 B = 恰
2+2 调用点）；缝②附修（rematch/clearSnapshot）**语义判定正确、零新
引入面**（一处理论序问题 obs 级）；m-5 raws 修复对齐亲核；范围让渡
四面各有正当理由；**全套独立复跑 `TOTAL|4101/40/0|`（2084s）逐值中**
（= 4093 基线 + 8 精确，skip 40 零漂移，零 MEMFAIL，峰 7082MB 门内）。

## 一、三缝接线逐缝亲核（①②③）

### 缝① EXIF parse + opt-in auto-apply（PipeCoordinator:1243）

- 落点亲核：`load` 的 **pristine（无 `.lra`）else 分支内**——`makeDefaultInstances()
  + editingDefaultInstances(defaultFace:)` 之后、`resetHistoryForNewImage`
  之前调 `LensDefaultsWiring.injectedLensSeed(into:image:)`（:1243）。
  restore 分支（:1180-1210 restore legs）零触碰 = 持久化 params 逐字
  保留（per-image params 规则）✓——影响域恰「新图」与申报一致。
- 语义对 **LENS-02 T2** 一致：auto-apply 生效域硬守卫在 `reloadDefaults`
  内部单源（`lensfun.autoApply` 键默认 false + `embeddedGeometry ==
  .notApplicable` only + lensKey 非空——LensModule.swift :346-351 亲读）；
  detected/unknown 恒不触发（D-LENS-1 禁扩域红线未破）；miss = 保留携
  EXIF 的 `.off` params（live memo 路径 identity 现状）✓。
- **D6（EXIF 快照无条件随行）兑现**：autoApply off 臂仍折
  focal/aperture/lensKey/maker/model/imageCrop/embeddedGeometry——缝②
  由此在任意新档可匹配 ✓。
- 装配等价性核：`injectedLensSeed` 经 `LensModule()`（fresh 实例 =
  生产 reader）调 `reloadDefaults`——seed 侧 lens instance 本就是
  `LensModule.Params()` 静态默认（Registry.swift :652 亲核），fresh
  实例语义等价，无 defaultFace 分歧面；`setParams` = 重编码 + 重哈希，
  id/multiPriority/iopOrder 不动（ModuleInstance.swift :157-165 亲读，
  NDE-1 身份保留 ✓，测试 `testLoadSeamWithoutLensRecordIsVerbatim` +
  id 断言钉）。
- **D-L4-1 option A（同步 bake）到达产线**：reloadDefaults 内
  `source == .lensfun → LensfunStore.bakeCommitted`（:354-357）——经缝①
  （auto-apply on）与缝②（browser 选型）两条产线路径可达 = 缝③成立，
  零新代码申报属实。

### 缝② browser 选型 commit（LensPanelView:588-594）

- 落点亲核：`commitSelection` 全体重写为 `Task { committedSelection(...)
  → applyDiscrete }`；EXIF 折入（`exifRefreshed` 六字段白名单：
  focal/aperture/maker/model/imageCrop/embeddedGeometry）→
  `selectedParams`（source=.lensfun + lensKey=选型）→ **rematch 面**。
  source/snapshot/滑杆/enable/scale/projections 不折 = 选型拥有 provenance
  ✓（对 LENS-02 T4「选型 = commit + snapshot-ready」语义一致；快照
  持久化归 LENS-04 不变）。
- detected 确认门（D-LENS-2）语义未触：`requestSelection` 的确认路由
  在 commitSelection 之前（:565-568 注释 + needsConfirmation
  embedded==.detected 单谓词），B-2 零触碰 ✓；EXIF 折入后
  embeddedGeometry 实携 → 确认门在真 RAW 档**首次可触发**（B-2 死路
  清单第 4 条闭合）。
- `edit.detectionSourceImage()` = coordinator.decoded 透传
  （PipeCoordinator:1988 + IOPPanelProvider:161 亲核）；nil（会话内无
  decode）= 跳过折入、选型照落——typed 降级面合理。

### 缝③ snapshot bake——见缝①尾；补一句：bake 的「同一 commit」
纪律由装配函数单 params 返回承载（rematch/bakeCommitted 均单拷贝
返回，调用方一次 applyDiscrete）✓。

## 二、反死路双腿复跑（本环境）

- **腿 A（运行时）**：`Scripts/test-direct.sh --bundle App
  'LensDefaultsWiringTests'` = **`BUNDLE|App|8/0/0|peakRSS=222MB|5s`**
  ——8/8 绿零 skip（含 E2E 真 `PipeCoordinator.load` 链法
  `testCoordinatorLoadSeedsLensThroughRealLoadChain`，Metal 在位实跑）。
  一路红腿证据亲核：`fix-batch/b2-red-green/red-run-prefix-tree.log`
  = stash 修复笔后同 E2E 法**三断言全红**（`off ≠ lensfun` / `nil ≠
  16` / resolve nil，带 RED-LEG 断言文案）+ `green-run-newclass.log`
  8/8——红绿闭环成立。
- **腿 B（源级）**：`grep -rn 'LensDefaultsWiring\.' App/Sources` = 恰
  **2 产线调用点**（PipeCoordinator:1243 + LensPanelView:591；:583 为
  注释行）+ 装配模块内 `reloadDefaults` 生产调用恰 **2**（:55 缝①/
  :88 缝②）；全仓 `.reloadDefaults(image` 非 Tests 命中恰此 2 处——
  与「17 测试调用者 + 零生产调用」的 B-2 考古对照，接线后产线首次
  落点 ✓。

## 三、缝②附修审查（bake 换 rematch 面——miss 清陈旧快照）

- **语义判定：正确**。旧行（`bakeCommitted(selected) ?? selected`）：
  `selectedParams(base:)` 按 `var p = base` 携带 base 快照前传
  （LensProfileBrowser.swift :68-72 亲读）——re-select miss 时**旧镜头
  的系数快照存活、lensKey 已换新选型** = 行/键错位静默渲染（B-1 同族
  no-op 面；该面在 B-2 接线前不可达——miss 恒因为 missingFocal，接线
  后 EXIF 在场、miss 才可能来自 DB 缺行，故「只在接线活后处理」的
  时序申报成立）。新行（`rematch ?? clearSnapshot`）：每次选型 = 全新
  bake，miss = 快照清空 → 渲染诚实回落 live memo（identity）且
  readout 如实报 miss——「快照 ≠ 键」错位面消除 ✓。
- **新引入面排查（三通道）**：
  1. miss 后残留 `params.sourceProjection`（bakeCommitted 命中时盖
     entry type，miss-clear 不清）：消费面排查 = live 路径
     `resolveCommitted` 投影选择读 **entry 自身 type + params.targetProjection**
     （LensfunMatch.swift :899-911 亲读），params.sourceProjection 仅
     进 KernelParams decode（:92-93，snapshot 臂）；snapshot nil 时该
     字段惰性，下次命中 bake 重盖——**惰性残留，非活面** ✓。
  2. 低置信（40 档）显式选型：bake 门槛 = `matchOutcome`（hardened
     60 底）pre/post 同一函数——显式低分选型 pre-wiring 亦不 bake
     （B-2 前后阈值语义零变），「40 档标注不自动入选」维持 ✓。
  3. **异步化（`Task { }` 包裹 commit）序问题**：commitSelection 由同步
     改 Task——但 commit 终点 `applyDiscrete` 本就是 fire-and-forget
     Task（IOPPanelProvider :118-127 亲读，setLiveParams+commit 连发），
     外层 Task 仅加一跳；reloadDefaults 无真挂起点 → 两快速选型的
     commit 在 coordinator actor 上按派发序落地。**理论倒序风险存在
     （Swift Task 序无硬保证）但后果 = 二选一胜出（每次 commit 全量
     params 自含），无状态撕裂**——obs 级登记，不构成缺陷。
- 测试钉：`testBrowserSelectionMissClearsStaleSnapshot`（陈旧快照 +
  miss 选型 → snapshot nil 断言）在 8 法内 ✓。

## 四、m-5 手动臂 raws 修复核

- 修复体 = `resolveUniforms` 手动臂补 `k.targetProjectionRaw =
  committed.targetProjection` / `k.sourceProjectionRaw =
  committed.sourceProjection`（LensModule.swift :702-710）——与面板
  `resolvedScalePreview` 手动臂（:482-485）**逐字段对齐**亲核 ✓；消
  「同文档 readout 折叠 / 渲染不折」分叉（B-1 同族静默 no-op）。
- 字节恒等承诺核：`LensKernelParams` raws 可选默认 nil（LensfunMatch.swift
  :57-58）→ `decodeLenient(nil) = .rectilinear`（LensProjection.swift
  :84-87 亲读）——无投影选型的历史档渲染字节零漂移 ✓。
- golden = `testManualArmFoldsProjectionRaws`（rectilinear 恒等 +
  target/source 折叠三 slot 断言）在 8 法内 ✓。

## 五、范围让渡面复核（四面各有正当理由，判定 = 合理）

| 面 | 事实 | 让渡理由核 |
|---|---|---|
| restore 分支 | 持久化 params 逐字（缝①只在 pristine else 分支，:1211-1247 亲核） | per-image params 规则：旧档 EXIF 折入 = 改写用户已持久化编辑态；且旧档的用户动作仍经缝②折 EXIF（commitSelection 对任意文档生效）——价值主张不因让渡失活 ✓ |
| SidecarSeedTopUp（:1446 + Core :29-56） | 修复路径补缺失 seed op = 静态默认 params，无 EXIF 折 | NDE-1 恒等语义（补 absent op 不动既有身份）；top-up 对象 = legacy 档，auto-apply 对已持久化档属意外面；同受缝②覆盖 ✓ |
| seedInstances（Shell :1873-1882） | Shell 侧新文档种子 = makeDefaultInstances + editingDefaultInstances，无折 | 调用点为 shell 文档创建/MCP 种子装配——无 DecodedImage 在手（种子先于载图）；载入后缝①接管 ✓ |
| MCP editingSeed（EditingToolset :1135-1144） | 同形静态种子 | MCP set_param 的 upsert 投影（:1146- projectInstances）对 agent 显式参数写——若折 reloadDefaults 反而覆盖 agent 显式意图；MCP 编辑目标档经 GUI/coordinator 载入者已过缝① ✓ |

**边界如实申报**：纯 headless MCP 建-编辑流（不经 coordinator.load 的
假想档）不会有 EXIF 折——该形态当前不存在（MCP 编辑档必先 import+load），
不构成活缺口；登记为语义注记。

## 六、全套独立复跑（第五面）

- guard 记录（如实）：`--wait 600` 窗内 **G3 swap 4.87→4.56GB 恒 >4G 门
  + G4 Data 卷 24GB<25GB** 双 BLOCK（活用户进程冷页地板 + 磁盘四舍五入
  24.x）→ 按本批自报先例 **D-L4-4 同形偏差放行**（LENS-01-DECISIONS
  B-2 批在案：G2/G1 绿 + `/usr/bin/time` ru_maxrss MEMFAIL 机检兜底 +
  峰值 <8G）；放行时 G2 = 75% free ✓、G1 = 零其它重活 ✓、零构建需求
  （DerivedData 现存容器 = 执行批 17:48 HEAD 构建，strings 含
  LensDefaultsWiringTests 亲证）——放行正当性入档。
- **结果：`TOTAL|4101/40/0|`（2084s）exit 0 零 MEMFAIL**，与执行批申报
  逐值同；4101 = 4093 二路基线 + 8 精确；skip 40 零漂移。

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 753/5/0（7082MB） | 753/5/0 | ✓ |
| IOPParity | 478/6/0（5907MB） | 478/6/0 | ✓ |
| Layers | 494/5/0（814MB） | 494/5/0 | ✓ |
| Library | 738/4/0（625MB） | 738/4/0 | ✓ |
| Sessions | 284/9/0（1308MB） | 284/9/0 | ✓ |
| Export | 385/5/0（5395MB） | 385/5/0 | ✓ |
| App | 969/6/0（2832MB） | 969/6/0 | ✓ |

- 腿 A 定向轮与本轮同容器（`test-direct` mtime 拾取唯一 Lightamer-*
  容器亲核）；全部峰 <8G 运行门；锁目录 `acc2nd-all.lock` 跑毕已清。

## 七、分级清单

- **minor-1**：范围让渡的语义边界申报缺一注——「纯 headless MCP 建-编
  流无 EXIF 折」当前不可达但未登记（§五尾）；后续 MCP 批若引入不经
  load 的建档形态须补（一句注记成本）。
- **obs-1**：缝② commit 异步化的理论倒序风险（§三.3）——后果二选一
  胜出、无撕裂；如后续收敛，`applyDiscreteForTest` 形（内联 await）或
  选型队列化皆可，非必改。
- **obs-2**：red-run 日志行号（:80/:83/:84）与现行测试文件（:305-308）
  差 = stash 树版测试文件排布差，断言内容逐字同——证据可读性注记。
- **obs-3**：guard 双门 BLOCK（G3 冷页地板 + G4 24GB 圆整）与 D-L4-4
  偏差放行全录（§六）；G4 门与 df -g 圆整交互（24.x GB 显示 24）建议
  后续 ops 批把 G4 判据改 `awk` 小数位或 24.5 阈，免结构性误拦。
- **obs-4**：执行批 B-2 构建复用了 F0P handoff 容器同路径
  （DerivedData 仅此一个 Lightamer-* 目录）——F0P 两路均已收口，覆盖
  无追溯损失；「handoff 容器保留」以现存形态（B-2 HEAD 构建）满足。

## 八、判定汇总

- B-2 修复判定：**PASS**——三缝语义对 plan 设计一致、写入路径产线
  端到端复活（8/0/0 + 4101/40/0 双腿本环境亲证）、反死路回归防再死。
- 缝②附修（rematch/clearSnapshot）：**语义正确 + 零新引入面**（惰性
  残留/阈值不变/异步序 obs）。
- m-5：**修复成立**（双臂对齐 + 字节恒等承诺成立）。
- 范围让渡：**四面合理**（一注记 minor-1）。
- 无新 blocking。
