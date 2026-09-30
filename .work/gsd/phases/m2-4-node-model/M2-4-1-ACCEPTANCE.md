# M2-4-1-ACCEPTANCE — 模型核独立验收（plan M2-4-1，P1 六任务）

> 验收批：2026-09-30 独立验收 subagent。plan 正本 = 同目录 `M2-4-1-PLAN.md`
> （checker 修正版 `c94aa3c`）；执行方 6 commits = `22e3b32`/`02a2835`/`52cf75e`
> /`b7d7acd`/`48e2b7d`/`1aaa563`（T1..T6）。裁决依据 = plan AC 总表 11 条 +
> 派发指令六重点核查项。**未 push**。

## 结论

**PASS / 0 error + 0 minor**（另 2 条不计数 observation）。

六重点核查全部通过；11 条 AC 独立复验全绿；四 bundle 定向独立复跑与执行方
声明逐值一致；八条执行期裁定（D-M2-4-1-1..8）逐条复核均合理且已在 DECISIONS
备案；无缺陷，无需修复提交。

## 六重点核查结论

### ① 红线（独立 git diff 亲验）

- `git diff 60c97a3..1aaa563 -- LightamerCore/Sources/Pipe/` = **空**——
  LayerCompositeDriver / PixelPipe / PipeCacheKey 及整个 `Pipe/` 目录零 diff；
  `RawDecodePanelView.swift` 同样零 diff（AC7 附带红线）。
- Core 不 import IOP：`grep -rn "import LightamerIOP" LightamerCore/Sources/`
  仅命中 `Mat3D.swift:6` 注释行（既有方向约束注记本身）；`Graph/` 三文件
  import 面均仅 Foundation。
- `.lalb`/`LibrarySchema.swift` 零触；执行方 6-commit diff 边界 = 22 文件，
  与 front-matter 申报集 + 两处备案随动（SidecarMetadataV3Tests = D-M2-4-1-4、
  BUNDLE-MAP = 纪律 6）恰合，**零越界**。`Scripts/test-direct.sh` 变更属
  `60c97a3`（执行方范围外的独立修复 commit，M2-4-0 遗留 M3，body 备案）。

### ② E1 恢复腿真链（AC7 禁名义覆盖）

读码证实三测试走**真实装配**：`makeAssembly()` = 真 `EditorState` +
`PipeCoordinator` + `WorkspaceModel` 三方弱引用交叉 attach（生产同款组合根，
`SidecarV5Tests.swift:301-319`）+ 真 `MetalContext` + 真 registry；fixture =
仓库真 RAW `input/RAW/DSC00012.ARW`（74MB，在盘核实），缺失即 XCTSkip
（非假绿）。三条腿齐：

- **写腿**（:341）：面板 commit 同形调用 → 会话 carrier → 透传钩 → throttle
  → `flushSidecar()` → **解码落盘文件**断言 `rawOverrides` 在；再以全新装配
  reload，读回同值 + carrier 已回注。
- **恢复腿**（:384）：预写含 overrides 的档 → `EditorState.load` 真链 →
  **最终 decoded readback `boost == 0.6`**（decode #2 替换 identity 首帧的
  完成标记 = `waitForBoostReadback` 轮询真 readback，非内部状态位）+ switch-back
  等价门（缓存就位二次 load 读回不变）。
- **pristine 腿**（:415）：nil 档 → readback 恒 nil（600ms re-decode 窗后
  仍 nil = 零 re-decode）+ 会话 dict 恒空（零回注）。断言在，非名义。

### ③ v5 nil 零漂移 + hash-isolation 双向机检

- **零漂移为真**：`testNilNewMaskFieldsKeepCanonicalBytesAndStableHash`
  逐字节钉——canonical bytes 无 `deletionProtected/enabled/displayName` 新键 +
  encode→decode→encode stableHash parity + **set-fields-move 反向证明**
  （置 `deletionProtected = true` 则 hash 必动——字段非死重）。
- **hash-isolation 双向**：`testRawOverridesAreHashIsolated`——同一 spec 实例
  有/无 overrides 两文档 `historyHash` 相等 + `driftDetected` 同值且为 false
  （overrides 不进 hash）；对照面蒙版字段 set-fields-move（进 mask 域）。一进
  一出双向钉死，与 D-M2-4-1-2 的判定理由一致。

### ④ 所有权完备性 + IOP 常量表零字面量

- `grep -n '"' LightamerIOP/Sources/NodeOwnershipCatalog.swift` = **0 命中**
  （连注释都无引号）——表全由 `<Module>.opName` 常量构建，模块改名必编译红。
- 完备性测试（`NodeOwnershipCatalogTests:71`）= registry 默认 face 全集
  （`makeDefaultInstances` + `editingDefaultInstances(defaultFace: true)`）
  非 grade 分类恰等于钉死 13（9 develop + 4 drtPost）；`owner(of:)` 总函数
  （默认臂 .grade）使「面∖表=∅」结构性成立，误分类由 13-pin 捕捉——完备性
  口径成立。四件 DRT/Post 逐名断言 + 3×3 validate 矩阵 + App 缝拦截
  （refuse + toast + 零 history 移动 + grade 算子照常落链）全在。

### ⑤ 测试登记纪律（拆 bundle 后首战，从严核）

- `Project.swift`：PipelineDocumentTests.swift @ :437 ∈ **LightamerTestsLayers**
  （target 声明 :410-459）；NodeGraphCommandTests :659 / NodeOwnershipCatalogTests
  :660 / SidecarV5Tests :663 ∈ **LightamerTestsApp**（:634 起）——归属与
  front-matter 判定逐文件一致（App 级 = 实例化 EditorState；Core 级 = 纯投影）。
- `M2-4-0-BUNDLE-MAP.txt`：LAYERS 5 / APP 17 / APP 6 / APP 10 四行在册，
  method-count 与各文件 `func test` 实数逐一相符（5/17/6/10，合计 38 =
  2203 − 2165 基线，精确）。登记与源文件同 commit（逐 commit stat 核实）。

### ⑥ 八条偏差合理性

| # | 裁定 | 验收意见 |
|---|---|---|
| D-1 | Clarity 位 = equalizer 维持 | feature-map §2.1 映射行支持；localContrast 留 .grade 有据；plan「风险与边界」预授权条款对齐。合理 |
| D-2 | rawOverrides hash-isolation 理由 | decode 域由 decodeParamsHash 代表，二次折叠 = 双记账；drift 以文件自身 decode stamp 传播。与机检互证。合理 |
| D-3 | deletionProtected 载体缺口挂 M2MASK-04 | **口径成立**：`SidecarLayerStack.swift`（SidecarMaskSpec 拼写正本）不在 plan files_modified 申报集，动它 = 违 AC10 边界纪律；runtime/snapshot/stableHash 拼写按 plan 落地，文件载体挂账 + SidecarV5Tests :200 断言注释显式钉缺口形态（防静默误判）。plan 内部张力（KD-4 表 vs 申报集）的正确解法 |
| D-4 | SidecarMetadataV3Tests 三处 pin 4→5 | 版本 bump 的机械伴随，读者容忍语义零改（diff 逐 hunk 核实：仅版本行 + 注记）。合理 |
| D-5 | testgain/passthrough 改列 .grade | 实测矛盾驱动（.develop 归属使既有层链用例经 addModuleToLayer 全红，与 plan 自身 AC5 冲突）；「面板缺席是呈现面事实非阶段归属事实」语义勘误成立；AC5 优先于 KD-3 清单。合理 |
| D-6 | apply 非 throwing + 内联 toast | plan 草图 throws 与「toast 面序」不可兼得（throws 推责给每个调用点，漏 catch 即崩）；内部 do/catch + 穷举 switch 无 default 保住穷举纪律。合理 |
| D-7 | AddClean base = Core 常量 | 命令无 base 载荷，M4 注入面由 `nextLayerName(base:)` 签名承载；P3 扩展点明示。合理 |
| D-8 | updateRawOverrides 仅调度 | `makeSidecarDocument` 直读会话 carrier = 单一真相无第二镜像（L 系列教训对齐）；回注走 `restoreSessionOverrides` 防 identity 首帧 stamp 的冗余写。比 plan 字面更稳。合理 |

两条执行期观察（同图 re-decode 层栈投影丢失 = pre-existing M2-3-3 语义；
isDecoding 灯交叠窗）登记在 DECISIONS，不属本 plan diff 面——不计数。

## AC 逐条核验（11/11 绿）

| # | AC | 验收 verdict | 证据 |
|---|---|---|---|
| 1 | 投影 parity + retouch 排除 + 纯函数性 | ✅ | PipelineDocumentTests 5/5 读码（序/id/name/enabled/mix 逐项 zip 断言 + retouch narrowing 排除 + 空栈三段 + 同栈两次 init 相等 + 异栈不等） |
| 2 | 7 命令 + 锁/钳/载荷 + E4 像素级 + undo/redo 保 UUID + 字节复原 | ✅ | NodeGraphCommandTests 17/17 读码（E4 = setGradeMix(0) vs enabled=false 经 LayerCompositeDriver 复合 **rawBytes 逐字节相等** + mix=1 可见性防空转 :505-548；undo/redo canonical JSON 逐字节 :362-414；InsertFromJson re-encode 相等 :219-241） |
| 3 | 新枚举 switch 穷举零 default | ✅ | `grep -n "default:" NodeGraphCommand.swift PipelineDocument.swift` 零命中（亲跑 exit=1）；EditorState.apply/graphCommandFace 两消费者编译穷举 |
| 4 | 完备性 + 四件 + 矩阵 + 表零字面量 | ✅ | 测试读码 + grep `'"'` 零命中（亲跑） |
| 5 | addModuleToLayer 拦截；加载/undo/复原零校验 | ✅ | 拦截测试读码（refused/toast/零 history/链零动）；校验缝只在 `addModuleToLayer` 单点（EditorState diff 核实）；既有 suite 全绿（四 bundle 复跑零回归） |
| 6 | v5 nil 零漂移 + v1..v5 矩阵 + 容忍 >5 + 写者恒发 5 | ✅ | SidecarV5Tests 读码（零漂移字节钉 + isolation pair + `>current+1` 解码 + schemaVersion 5 writer pin）；旧档容忍由既有 Sidecar 族零改动覆盖（v2/v3 fixtures 在 SidecarMetadataV3Tests/Phase6SidecarTests，本轮全绿）；pre-v5 全 nil 由 decodeIfPresent 结构性保证 |
| 7 | RAW overrides 真 load 链 + pristine 零 re-decode + nil 档不带键 + 面板零 diff | ✅ | ②节详证；`testNilRawOverridesOmitsTheKey` 钉缺键；RawDecodePanelView git 零 diff（亲验） |
| 8 | 渲染红线零 diff | ✅ | `git diff 60c97a3..1aaa563 -- Pipe/` 空（亲验） |
| 9 | 全套 0 fail，计数 ≈2165+20..28 | ✅（+38 超带已归因） | 执行方 `--all` TOTAL|2203/14/0|723s EXIT=0；七 bundle 和 = 2203 精确（457+308+169+430+279+260+300，亲算）、skip 14 精确；+38 = 5+17+6+10（SidecarV5Tests 终值 10 > 预估 7，T5 真链 3 例并入同文件——SUMMARY AC9 行在册归因） |
| 10 | diff 边界 == 申报集 | ✅ | 执行方 range 22 文件 = 申报 + D-4 随动 + BUNDLE-MAP（纪律 6）；零越界 |
| 11 | 测试登记闭环 | ✅ | ⑤节详证 |

## 验证数字（独立复跑 vs 声明）

`Scripts/test-direct.sh --bundle` 定向域轮（验收批亲跑，2026-09-30；产物
DerivedData `Lightamer-dgzsvdww…` mtime 2026-09-30 09:44 晚于执行方 commits；
全程 caffeinate 包裹）：

| bundle | 执行方声明 | 验收独立复跑 | 对账 |
|---|---|---|---|
| Layers | 169/2/0（945MB） | **169/2/0** peakRSS=944MB 21s sampling=time EXIT=0 | 逐值一致 |
| Library | 430/4/0（295MB） | **430/4/0** peakRSS=296MB 17s EXIT=0 | 逐值一致 |
| IOPParity | 308/2/0（5984MB） | **308/2/0** peakRSS=5983MB 234s EXIT=0 | 逐值一致（RSS −0.02%） |
| App | 300/0/0（1468MB） | **300/0/0** peakRSS=1469MB 72s EXIT=0 | 逐值一致 |

- 四 bundle 覆盖全部 38 个新增测试的归属域（LAYERS 5 + APP 33）；在案
  LayerE2E flaky 未触发（Layers 21s 一遍过）。
- 其余三 bundle（IOP/Sessions/Export）无新增测试登记（BUNDLE-MAP 仅 LAYERS/
  APP 增行），以执行方 `--all` BUNDLE 行 + TOTAL 和亲算（=2203/14 精确）交叉
  对账覆盖；全套 `--all` 复跑按纪律不自行启动（须 orchestrator 批准）。
- MEMFAIL 8G 门：四轮零触发；IOPParity 5983MB 与执行方 5984/5966（M2-4-0
  两轮）同带，±3% 方差注记带内。

## 翻账清单（本批）

- REQUIREMENTS：M2NODE-01 ✅ Delivered / M2NODE-02 ✅ Delivered /
  M2NODE-05 ✅ Delivered（sidecar 腿；项目文件腿归 M2-8，口径注记随行）；
  M2DIS-04 终注（持久化挂账销账确认，锚 `48e2b7d`）。M2NODE-03/04/06 留
  后续波次（M2-5 目录收窄 / M2-7 蒙版面板 / P2-P3 面板 plan）——M2NODE-03
  本 plan 交付的是所有权框架 + 宽限执行（D-M2-4-CONTEXT-8），严格面激活
  归 M2-5，不勾。
- 本报告落盘 `phases/m2-4-node-model/M2-4-1-ACCEPTANCE.md`。
- 无修复 commit（零缺陷）。

## Observation（不计数，登记备查）

1. **AC6「v1..v5 decode 矩阵」的字面实现为组合覆盖**：SidecarV5Tests 显式钉
   v4 + v5 + `>5`；v1..v3 旧档容忍由既有 Sidecar 族（SidecarMetadataV3Tests
   v2/v3 fixtures 等，本 plan 零改动）承载；pre-v5 新字段全 nil 由
   decodeIfPresent 路径结构性保证。容忍矩阵语义完整，无行为缺口——记录
   字面 vs 实现的对应关系供后续查阅。
2. **`SidecarV5Tests` 真链用例对 `coordinator` 具名绑定强依赖**（`_ = coordinator`
   保活 + L046）：weak 互指网的测试写法契约已在 LESSONS L046 沉淀，后续
   装配型测试（NodesPanelModel 族）按 L046 对策执行即可，无行动项。
