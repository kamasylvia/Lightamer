# M6-2-CHECKER — M6-2-01 plan 从严检查报告（2026-10-16）

> Checker = zcode subagent（从严）。审查对象 = `M6-2-01-PLAN.md`（HEAD
> `c4ff891e`）+ `M6-2-CONTEXT.md` 裁决记录（2026-10-14 用户回批）+
> `RESEARCH-NOTES.md`。全部 file:line 为 2026-10-16 HEAD `c4ff891e` 亲核；
> 工作区源码树干净（仅 .work 面未跟踪文件）。
> config 对账：`auto=true / paused=false / dual_acceptance=true /
> plan_review_by_omp=true`——plan m1 串行 omp 二次验收落点正确；本报告与 omp
> 计划复审合并回注。

## 结论

**FAIL / 1 error + 4 minor**

E1 = SessionBatchApplier 既有档臂「decode round-trip 原值自动保全（零改）」前提
与源码事实相反（该臂是字段挑选重建，非全档 round-trip）——KD-7 / front-matter
files_modified / T4 验收三处同源错误；按 plan 原文执行必然红灯或未登记偏差。
修复处方明确（一处 plan 修订 + 一行实现面处方），不伤六项裁决生效值与其余交付
面。**E1 修订回注后本 plan 可进执行；六项 OQ 生效值无需重开。**

---

## E1（error）：SessionBatchApplier 既有档臂非 round-trip——「零改自动保全」claim 错误

**源码事实**（`LightamerCore/Sources/Session/SessionBatchApplier.swift`）：

- 既有档臂 ：100-106 只从 decode 出的 document 提取 **5 个字段**（`history` /
  `instances` / `decodeParamsHash` / `imageID` / `decoderVersionUsed`）落入局部
  常量；
- 随后 pristine 臂与既有档臂**共汇同一构造点** ：136-144，以
  `LightamerSidecar(imageID:decoderVersionUsed:decodeParamsHash:instances:
  history:historyHash:appVersion:layerStack:)` 重建**全新档**——文档级 additive
  字段 `provenance / rawOverrides / displayTransform / versions /
  activeVersionID / aiProvenance / filmRecord` 在既有档 batch apply 时**今日已
  被静默丢弃**（pre-M6-2 数据保真缺口，非本批引入）；新增的 `process` 键若不
  显式携带同样会被丢弃。

**plan 三处同源错误 claim**：KD-7「既有档 read-modify-write 臂零改（decode→encode
round-trip 经 KD-2 canonical 形自动原值保全）」+ front-matter
SessionBatchApplier.swift 行「既有档臂经 decode round-trip 原值自动保全（零改）」+
T4 验收「既有档臂原值保全」（在零改前提下不可实现）。planner 显然从
MetadataService 正确形态（`mutate(&document)` :186-189 = 真 inout round-trip，
既有字段全保——该文件 claim 无误）错误外推到 SessionBatchApplier。

**四条后果**（任一即 error 级）：

1. T4 计划测试「pristine 臂 =1 + 既有档臂原值保全」在零改前提下**必红**——执行
   要么未登记偏差、要么糊弄测试。
2. 「pristine 臂盖章 current」若被实现为无分支统一参数 → 既有 legacy 档被被动
   升级为 process=1，**违反 OQ-1「永不被动升级」**。
3. 若被实现为跨臂共享的 `document.process ?? .current` 形 → 同样给 legacy 既有
   档 mint（nil 撞上 `?? .current`），同违反 OQ-1。
4. 不加显式携带 → 既有档上的前向大号（process=7）batch apply 后降级为 ABSENT，
   **违反 OQ-3「存回不降级」**在本路径的承诺。

**处方**（三步，均为 plan 文本修订 + 实现面一行，不动六项裁决值）：

1. **修订 KD-7 + files_modified SessionBatchApplier 行**：既有档臂显式一行携带
   ——在 ：100-106 臂内把 `document.process` 提升为局部（如
   `existingProcess: RenderProcessVersion?`）；构造点盖章形 =
   **分支条件式**：pristine 臂 → `.current`，既有档臂 → `existingProcess`（nil
   = legacy = ABSENT，原值含前向大号照搬）。**禁用跨臂共享 `?? .current` 形**
   （后患 = 处方后果 3）。声明：SessionBatchApplier 因此**不是零改**（+2 行
   additive：一局部一参数），front-matter 行同步改写。
2. **T4 测试意图不变**（pristine =1 / 既有档 legacy 保 ABSENT / 既有档
   process=1 保全 / 既有档前向 7 保全）——修订后可测；建议既有档臂负测三态
   （legacy/1/7）一法覆盖。
3. **DECISIONS 登记两条**：①上述 pre-M6-2 字段丢弃缺口
   （displayTransform/filmRecord/versions/aiProvenance/rawOverrides/provenance
   在 batch apply 既有档臂被丢弃）= 数据保真缺陷，**明确 M6-2 不修**（范围纪
   律），挂观察项待未来 fix batch；②process 在本臂的携带 = M6-2 显式新增面，
   非「自动保全」。

---

## minor 4 条

**M1（KD-2 双域门口径）**：`RenderProcessVersion.init?(rawValue:)` 值类型域门 =
`0...0xFFFF_FFFF`（KD-1），sidecar 存储值 decode 域门 = `1...0xFFFF_FFFF`（KD-2
stored-0 归一化）——两者语义一致但 plan 文本在 OQ-3/RESEARCH §3.4 表（「合法域 =
整数 0..2^32−1」）与 KD-2（「域门 1...」）间切换，执行期照 OQ-3 表写字 decode
表可能把 stored-0 保留为 0 而非归一 ABSENT。处方：DECISIONS 加一行「双门分离」
注记（值类型门含 0=legacy 哨兵；sidecar 存储门 1 起，0/null/损坏 → nil），
KD-2 已有三处 stored-0 钉死面不受影响。

**M2（T6 bundle 拼写）**：plan 定向轮写 `--bundle LIB/LAYERS/APP/IOP/SESS`；
`Scripts/test-direct.sh` 注册表实拼 = `BUNDLES=(IOP IOPParity Layers Library
Sessions Export App)`（:165）。缩写是 BUNDLE-MAP/m6-1 既定散文词汇，但执行命令
须用注册表拼写（Library/Layers/App/Sessions）。处方：T6 执行命令照注册表拼写，
plan 文本可不改（散文词汇惯例）。

**M3（派生 pipe 继承审计清单）**：plan KD-5「逐 `PixelPipe(` 内部构造点审计」
未列清单。亲核全仓生产构造点 = **8 处**：LayerCompositeDriver :236（basePipe）/
:393（layerPipe）/:539（terminalPipe）；PixelPipe :1069（DRT tailPipe）/:1190
（filmPipe）/:1340（replayPipe）/:2017（no-op throwaway 路径）/:2051（process
主 pipe）。处方：T2 执行按此 8 点逐一勾选（:2017 无状态 throwaway 可豁免继承
但注记一行）——全部落在 plan 已列两文件内，工作量与 plan 预估一致。

**M4（ProcessProbeModule 可行性确认，无行动）**：`IOPModule.process(...
piece: inout IOPiece ...)`（`LightamerCore/Sources/Pipe/IOPModule.swift` :125-130）
+ `IOPiece` public struct（`IOPiece.swift` :30）——T2 测试替身读
`piece.renderProcess` 可行，TestGainModule test-local 先例在案
（FilmSidecarTests :48 等多文件共用）；`RenderProcessVersion` 落
`LightamerCore/Sources/Pipe/` 与 IOPiece 同模块，可见性无碍。此条仅备执行期
免疑，无需 plan 改动。

---

## 通过项（逐维度，附亲核证据）

### 1. 裁决一致性（六项生效值 → AC 映射）

- OQ-1→AC1 / OQ-2→AC2 / OQ-3→AC3 / OQ-4→AC4 / OQ-5→AC5 / OQ-6 四门→AC6 全部落
  位；CONTEXT 裁决记录（2026-10-14 全 A）与 plan「已定裁决」节逐条同文。
- 「入册 ≠ 升级」（KD-2）、否决演示性 bump（OQ-4）、迁移 UX 挂账（OQ-5）、
  ROADMAP 三件之上补 mint 门（OQ-6）均显式在 AC/风险节。
- M6INT-01 锚亲证：`REQUIREMENTS.md` M6 Interop 节 M6INT-01 行「→ M6-2」；
  ROADMAP M6-2 行验收形态三件 = plan 四门之 G1/G2/G3，G4 mint 门为 plan 补强，
  与 CONTEXT D-M6-2-6 一致。M6-3 = UltraHDR（ROADMAP :74），与 M6-2 无门控耦合，
  衔接面 = GOAL-STATE 续接点（T6 覆盖）。

### 2. schema bump 审计

- v9 现状亲核：`LightamerSidecar.swift` :207 `schemaVersionCurrent = 9`；v9
  filmRecord additive 注记/decode `decodeIfPresent`（:488-489）/encode
  `encodeIfPresent`（:557）惯例与 plan KD-2 canonical 形同构；init 默认参族
  （:361-404）= `process: RenderProcessVersion? = nil` additive 落位合法。
- **零漂移负测完备性亲证**：全仓（Tests+App+Core）grep 字面量 `"schemaVersion"
  : 9` / `schemaVersion, 9` / `= 9` **零命中**——既有测试字面量全部为 rewind-form
  （上一版本 8/6/5/4 的 byte-face 重建）或 FUTURE（99/999），符号化
  `schemaVersionCurrent` 引用 11 文件在案；「既有 byte-face 测试族零编辑预期」
  成立，9→10 bump 自动传播。
- tolerant decode 读码设计：KD-2 lenient 表（缺键 nil / Int 域门 / 整值浮点
  `2.0`→2 / 损坏集全 nil 不毁档 / 存回 ABSENT / 前向大号保留）与 RESEARCH §3.4
  LightCraft 原形一致；「Int 失败→Double 重试」两种读法对损坏集结局等价（域门
  双杀），无歧义性风险。FUTURE-version 分支照读（T1 覆盖）。
- 字节面：`.sortedKeys` 下新键落 `provenance` 与 `rating` 之间，legacy 档键恒
  ABSENT → 既有键逐字节不变承诺可测（G1①②③ + T3②）。

### 3. hash isolation 审计

- `HistoryHash.swift` 零 diff 红线 + `driftDetected`（`LightamerSidecar.swift`
  :1002-1009）五元折叠亲证：`stack / decodeParamsHash / layerSnapshot /
  drtRecord / filmRecord`——film 排 drt 后，无 process 项；写缝唯一汇入
  `makeSidecarDocument`（`PipeCoordinator.swift` :1445，historyHash 实参
  ：1500-1506 同五元）亲证。
- 零 history item：`SidecarHistoryItemRecord` Keys（:715-719）=
  id/snapshot/label/timestamp/layerScope/stackSnapshot/pasteSet/drtRecord/
  filmRecord——无 process 槽；undo/swap 零触由 T3⑤ 钉。
- 分叉点折键先例亲证：`PipeCacheKey.swift` :92-127 `edgeMapAlgorithmVersion`
  折入 `edgeMapKey`（`StableHash.combine(upstreamHash, bytes)`）——「只在真分
  叉路径折键」先例成立；M6-2 `PipeCacheKey` 零改红线 + 「非 legacy 才折」契约
  三处登记（头注/AGENTS/DECISIONS）+ KD-6 可测面（seam ⑥ 键恒等 + 第二 run 命
  中）落位。modversion 正交（`ModuleInstance.swift` :64-66 version 折
  HistoryHash——process 禁折的机理澄清）亲证。

### 4. mint 面 5 处出生点普查（有无第六处）

全仓生产代码 `LightamerSidecar(` 构造点亲核 = **恰 6 处 = plan 5 面**（coordinator
写腿计一处）：

| # | 面 | 锚点 | plan 定位 |
|---|---|---|---|
| ① | coordinator 写腿（pristine 载体在 load 腿双分支 ：1153-1215 prime） | `PipeCoordinator.swift` :1500 | ✓ |
| ② | AI 副本出生档 | `ImportService.swift` :681（store :690 + flushNow :693） | ✓ |
| ③ | HDR 产物档 | `StackMergeService.swift` :2220（直写 JSONEncoder :2231-2233） | ✓ |
| ④ | Mertens+Pano 共用产物档 | `StackMergeService.swift` :2676 | ✓ |
| ⑤a | Session batch pristine 臂 | `SessionBatchApplier.swift` :136（**两臂共汇，见 E1**） | 前提错 |
| ⑤b | Metadata pristine 臂（既有档 `mutate(&document)` 真 round-trip） | `MetadataService.swift` :202（mutate :186-189） | ✓ |

旁证普查：`SidecarStore(` 生产构造仅 ImportService :690 + PipeCoordinator :1161
两处；无其它建档路径（move/backup 不产新档、ImportFilter 族掩码跳 sidecar、
LightamerPreset 独立类型不嵌文档）。**无第六处漏报**。既有档保全臂：⑤b 自动保
全成立；⑤a 不成立（E1）。

### 5. 管线缝 armed

- run-scoped 属性同位先例亲证：`PixelPipe.swift` :142 `terminalTail` /
  :155 `tailFormatFloatOverride` / :165 `filmTail`——`renderProcess` 落位合法。
- 双入口锚点精确：`process` :2036 / `processComposite` :2090（additive 缺省参 =
  既有调用点零变化，三先例同形）。
- IOPiece stamp 先例亲证：iscale/pipeType run 一次性 stamp 在
  `PixelPipe.run` :962/:967；`renderProcess` 不入 paramsHash（piece 级 run 常
  量惯例）与 `IOPiece.swift` :57/:65 契约注记一致；IOPiece 无合成
  Equatable/Hashable（plan 风险节预判属实）。
- 派生 pipe 继承 8 构造点清单见 M3。
- 零消费即零行为：生产传值不接线（KD-5）+ G2③ 显式证明 + 传值接线挂账
  DECISIONS——与 G3「0/1 逐位恒等」自洽（钳制目标 == legacy 行为的诚实申报在
  T6 DECISIONS 要求项内）。

### 6. golden 四门落位

- G1（T1）：byte-face 三档 + hash isolation + stored-0/corrupt ABSENT +
  FUTURE-version + 缓存键面零变化（T2⑥ 分账在 seam 文件）——完备。
- G2（T2①③④⑤）：冻结门（legacy 跨模拟语义变更逐位）/ 分叉可见门 / 缺键 =
  legacy 臂（sidecar→pipe 值流贯通）——LightCraft
  `settings_saved_before_process_versions_load_as_v1` 同构三式齐。
- G3（T2②）：0/1 逐位恒等 + IOP/IOPParity 本批零触碰（BUNDLE-MAP 无新行）——
  parity 族零 diff 预期成立。
- G4（T3/T4）：mint 门（pristine 编辑落 `"process": 1`）/ legacy 编辑重存
  ABSENT / 前向大号保全 / corrupt 存回无键 / Copy Adjustments 不携带（T3⑥，
  `isAdjustmentTransferable` 单谓词 + 传输面=instances+DRT 值拷，process 文档
  级键结构上不在传输集——`AdjustmentTransfer.swift` :35-44 亲证）/ LightamerPreset
  独立类型（`LightamerCore/Sources/Presets/`）不携带——除 SessionBatchApplier
  一腿受 E1 影响外落位完备。

### 7. 测试对账

- 法数：三新文件 15+8+8=31 + 既有四文件 additive 2+1+1+1=5 → **36 法 ∈
  +32..38**；基线 **3689/24/0** 亲证（`M6-1-VALIDATION.md` :24 终验
  `TOTAL|3689/24/0|2157s`）；全套预期 3689+36=**3725 ∈ 3721..3727** ✓。
- bundle 分账亲证（BUNDLE-MAP 行）：FilmSidecarTests=LIB / DrtTailTests=LAYERS /
  SidecarV5Tests=APP / StackMergeServiceTests=IOP / ImportServiceTests=LIB /
  MetadataServiceTests=LIB / SessionBatchApplierTests=SESS——新文件与 additive
  归属全部成立；AC8 LIB 17/LAYERS 8/APP 8/IOP 2/SESS 1 对表闭合。
- Project.swift 显式清单七行在案（:452/:511/:588/:604/:613/:683/:843），三新
  文件登记 + L041 tuist generate 恒末位纪律在 plan。
- 编排落点：`dual_acceptance=true` → plan T6 m1「zcode PASS 后串行 omp 二次验
  收，严禁并发」✓；`plan_review_by_omp=true` → 本报告与 omp 复审合并回注 ✓。
- 测试体例先例：FilmSidecarTests digit-rewound + canonicalEncoder 力学在案
  （:108-156）；DrtTailTests pipe harness + L014 drain/fence（:120-136）在案；
  SidecarV5Tests 真 load 链 APP 形在案——三新文件的「同位同力学」引用全部可追。
- 杂项亲证：`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 当前不存在（干净
  ，App bundle 轮前置条件天然满足）；L057 禁令无 UI 面自然满足；零 xcstrings/
  UserDefaults 新键与 OQ-6 范围边界一致。

### 8. goal-backward

- 交付定义映射：iop 调参漂移缺口（RESEARCH §1，modversion 不可用载体——折
  HistoryHash 假阳 drift 的机理亲证）→ per-photo process 纪律（旧号冻结 + 缺键
  不序列化 = legacy 档 re-encode 键面零漂移）→ M6INT-01 兑现。
- bump 纪律三层（枚举账本/冻结 golden 常青/M6 批 iop 调参 plan AC 模板行）落
  T5；「Update to Current Process」挂账双登记（DECISIONS + GOAL-STATE 续接点）
  落 T6。
- M6-3（UltraHDR）无门控耦合，衔接 = 续接点更新，无缺口。

---

## 处置摘要

1. **E1 修复批**（orchestrator 回注 plan 或 planner 修订）：按 E1 处方三步修
   KD-7 + files_modified + T4 描述；DECISIONS 双登记（pre-M6-2 字段丢弃缺口
   出范围 + process 携带为显式新增面）。修订后无需重跑本 checker 全量——定向
   复核 SessionBatchApplier 相关三处文本即可。
2. **M1**：DECISIONS 一行双门注记。**M2**：T6 执行命令用注册表拼写。
   **M3**：T2 按 8 点清单勾选。**M4**：无行动。
3. 六项 OQ 生效值、红线族、测试基建与 SC 数字面**全部维持**，不因 E1 重开。
