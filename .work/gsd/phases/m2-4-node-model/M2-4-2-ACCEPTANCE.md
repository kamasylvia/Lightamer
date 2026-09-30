# M2-4-2-ACCEPTANCE — 蒙版语义面 + 页签联动独立验收（plan M2-4-2，P2 三任务）

> 验收批：2026-09-30 独立验收 subagent。plan 正本 = 同目录 `M2-4-2-PLAN.md`
> （checker 修正版 `c94aa3c`，E3 双腿 + E2 登记纪律版）；执行方 3 commits =
> `42e2f95`（T1）/ `9a3e906`（T2）/ `cda10e7`（T3 收口）。裁决依据 = plan AC
> 总表 9 条 + 派发指令五重点核查项 + DECISIONS 六裁定复核。**未 push**。

## 结论

**PASS / 0 error + 0 minor**（另 4 条不计数 observation）。

五重点核查全部通过；9 条 AC 独立复验全绿；定向独立复跑与执行方声明逐值一致；
六条执行期裁定（D-M2-4-2-1..6）逐条复核均合理且已在 DECISIONS 备案；无缺陷，
无需修复提交。

## 复跑 vs 声明

| 轮次 | 执行方声明 | 本批独立复跑 | 判定 |
|---|---|---|---|
| Layers bundle | 174/2/0（942MB） | `BUNDLE|Layers|174/2/0|944MB|22s EXIT=0` | 一致 |
| App bundle | 309/0/0（1470MB） | `BUNDLE|App|309/0/0|1468MB|79s EXIT=0` | 一致 |
| SidecarV5 族定向 | （App 309 内含） | `--bundle App 'SidecarV5Tests'` = 10/0/0 EXIT=0 | v5 零漂移防护在位 |
| 全套 --all | TOTAL\|2217/14/0\|723s EXIT=0 | 不自行启动（纪律：全套须 orchestrator 批准；执行方为批准后实跑） | 计数对账：2203 基线 + 14 新增（App 9 + Layers 5）= 2217 精确，定向两轮合计增量逐值吻合 |

MEMFAIL（8G 口径）：本批四轮（Layers/App×2/SidecarV5 定向）零触发；峰值
1468MB。

## 五重点核查结论

### ① E3 双腿（deletionProtected clear+fill 拦截）+ 全仓写入点审计独立复核

- **双腿拦截实现亲验**（`App/Sources/Lightamer/State/LayerEditingState.swift`）：
  `.fill` 腿（`copy.mask = MaskSpec()` 前，现 ：299 写入点）与 `.clear` 腿
  （`copy.mask = nil` 前，现 ：311）各自前置 `isDeletionProtected` 判定 →
  `presentToast` + `return`（零 history item）；`isDeletionProtected` =
  `layer.mask?.deletionProtected == true`（nil 安全，单点判定）。
- **测试钉真伪**：`MaskItemSemanticsTests` 三例——
  `testDeletionProtectedRejectsClear` / `testDeletionProtectedRejectsFill`
  （各断言 mask 保持 Equatable 逐值 + history 计数不动 + toast 非空）+
  `testUnprotectedClearAndFillBehaviorUnchanged`（fill 恰 +1 item 且
  `hasAnyPayload == false`、undo 后 clear 恰 +1 item 且 mask 变 nil、无
  toast）。双腿同权拒绝 + 非 protected 行为不变，断言全实。
- **全仓 mask 写入点独立 grep**（`grep -rn "\.mask = \|mask = nil\|mask = MaskSpec" App/Sources LightamerCore/Sources`）= **8 触点**，与 DECISIONS
  审计表逐个吻合：2 清空腿（拦截）+ 6 合法（`LayerEditingState.swift:282`
  duplicateAndInvert 内容变换 / `AIMaskEditing.swift:164` segment bake 保
  payload / `MaskOverlayHost.swift:387/:403` stroke 生产 / `AdjustmentLayer
  .swift:73` 构造 / `LayerStackSnapshot.swift:61` undo 恢复载体 /
  `SidecarLayerStack.swift:131` load 缺省）。**无漏网**；命令面清空入口
  恰两个，拦截面闭合。

### ② 恒等元过滤（KD-1）——零 diff 独立核 + passthrough 路径名 + 0.7 断言真伪

- **五式公式零语义改动独立 git diff 亲验**：T1 对 `MaskCombiner.swift` 的
  全部 diff = `drawnGroupPlane` item 循环顶部一行 `if item.enabled ==
  false { continue }` + 注释块；union/intersect/difference/sum/exclusion
  五式及 feather→invert→opacity→clamp 应用序逐行未触。全 plan 三 commit
  `git diff --name-only d103b9e..cda10e7` = **零 `.metal` 文件**（kernel
  红线独立核，非转述）。
- **空 enabled 集 passthrough 路径名核实**：`drawnGroupPlane` 全项被滤后
  `inputs` 空 → 返 nil → caller 既有段落（`MaskCombiner.swift:541`）
  `// nil group plane (no resolvable item) → dt's no-form fill 1`，dt 源
  引注 `blend.c:612-616`（:393-394）——「dt no-form fill-1 leg」路径名
  实录无误，非恒 0 语义（D-M2-4-CONTEXT-6 分工）在注记与测试双重钉死。
- **全 disabled 逐字节 0.7 断言为真**：`testAllDisabledGroupIsTheConstant
  OnePassthrough`（a）combiner 面断言 `XCTAssertNil`（空 enabled 集无
  plane）；（b）全装配面 `assembleUnmasked(layerOpacity: 0.7)` 后 `getBytes`
  fence 读回逐像素 `XCTAssertEqual(value, 0.7)`——constant-1 × 0.7 逐字节，
  读 GPU 纹理非内部状态位；（c）单项 disabled 单形组同通道（恒 1 而非
  渲染 form）。恒等元矩阵主测试 = 5 op × 首/中/末 disabled 逐像素 Double
  参考折叠（真实 plane 值、边缘像素覆盖、<1e-6）+ 双圆闭式面积锚（错位
  过滤会偏差半圆、超出离散界两个量级）——断言强度高于 plan AC 最低要求。

### ③ maskGroups 投影同构（KD-3）+ stored let 偏差（D-3）合理性

- **组序 = grade 序 = 层序**：`PipelineDocument.init` 内
  `zip(gradeNodes, stack.compositeLayers).map` 同批派生（`grades` 落盘
  同源）；`testMaskGroupsProjectInGradeOrder` = 3 grades 全投影（含无蒙版
  grade 空组）+ id 序对齐 `compositeLayers` + masked 组 2 items 字段逐断。
- **reorder 跟随纯派生证明**：`testMaskGroupsFollowReorderWithoutAnySync
  Point` = `stack.reorder` 后**重新 init** 的新投影组序翻转 + 层 UUID 保持
  + items 随行，且 **reorder 前的旧投影逐值不动**——值语义下「无对象被
  变异」结构性排除双写漂移，Reconnect 复用（D-M2-4-CONTEXT-9）的证明
  方式正确（钉投影行为而非钉任何同步点）。
- **parity**：`testMaskItemSummaryParityWithTheSpecReadView` 逐字段
  （id/name/enabled/opacity/inverted）+ 序保持。
- **D-3（stored let 替代 KD-3 草图 computed var）合理**：computed 需持有
  stack（真存储，违文档门面红线）且 LayerStack 非 Equatable 破坏合成相等
  ——init 内 per-read 派生与 `grades` 自身同构（非缓存非同步点），Eq 面
  加宽 = 行为正确化；头注纪律未破。翻转代价如实备案。

### ④ 动态名 KEY 恒等勘误（D-2）——zh catalog 实测 + 断言写法

- **zh catalog 实测核对**：`Resources/Localizable.xcstrings` 的
  `editor_node_name` 条目 `localizations.zh.stringUnit.value = "调色"`
  （locale code `zh`，state translated）——D-2 声称属实：zh 宿主上现行为
  （改前 header）渲染的就是「调色」，故「未选中 = 逐字节不变」的正确
  契约表述 = **同键同解析**，非英文字面量。
- **断言写法正确**：`testDisplayTitleCoversAllBranches` 以同式
  `String(localized: "editor_node_name", defaultValue: "Color Grade")`
  对照断言（任何 locale 下与 header 渲染同解析，比字面量断言更强）。
- **新键滞后在案**：`editor_node_develop`/`editor_node_drt`/
  `editor_node_kind_grade`/`editor_node_kind_drt` + `toast_mask_deletion_
  protected` 共 5 键 catalog 尚无条目（defaultValue 英文生效）= D-M2-4-
  CONTEXT-11 明文允许的 zh 滞后，挂 P3 收口对账（非缺陷）。
- **视图零分支核验**：`EditorNodeHeaderView` 的 `nodeTitle`/`nodeKindLabel`
  均为穷举 switch（无 default）消费 `PipelineDocument`，视图自身无标题
  业务逻辑；未选中路径实参与改前逐 token 相同（m7/D-6 勘误实质成立）。

### ⑤ 六条执行期裁定（D-M2-4-2-1..6）逐条复核——均合理且备案在案

- **D-1 测试类两班拆**（Swift 6 `SendingRisksDataRace`：@MainActor 区域
  本地创建 MTLTexture 送 nonisolated async 装配）根因技术正确；文件名与
  登记行不变、BUNDLE-MAP 按文件计 9 不受影响。
- **D-2 KEY 恒等**：上述 ④ 实测吻合；勘误使 plan「Color Grade 现值」表述
  在任意 locale 成立，收窄为更强契约。
- **D-3 stored let**：上述 ③ 合理。
- **D-4 maskItems 窄门面**（空 forms = []、top-level only、setter 静默
  no-op）：plan 未言明处按最窄实现 + M2-7 再扩（YAGNI），与「不新增第二
  存储」红线一致；`testMaskItemsAccessorRoundTrip` 钉 round-trip + 未知 id
  no-op + nil name 存储面。
- **D-5 stroke 腿 sibling payload 重建观察**：**登记在案非静默吞**——
  DECISIONS D-M2-4-2-5 详注（`MaskOverlayHost.appendForm/mutateForm`
  以 `MaskSpec(drawn: drawn)` 重建，parametric/raster/deletionProtected
  三 sibling 置 nil）；当前无用户可达后果（deletionProtected =
  runtime-only，sidecar 载体缺口本身 = D-M2-4-1-3 挂 M2MASK-04；raster
  腿有独立保 payload 写点 AIMaskEditing），登记义务（M2MASK-04 补载体时
  同批复核 stroke 腿，修法候选在案）+ 翻转条件 + 本 plan 纪律禁顺手修
  齐备。**本批已将该挂账显式带入 REQUIREMENTS M2NODE-04 Delivered 注记**
  （防单点依赖 DECISIONS 被遗忘）。
- **D-6 m7 域勘误**：diff 面 = 头注/环境声明/两 Text 消费点，未选中渲染
  输出逐字节不变；`EditorStackRoutingTests` 等既有族零改动全绿佐证。
  AC5 的「diff 仅消费点替换」按实质（渲染输出恒等）核验成立。

## AC 总表核验（9 条全绿）

| # | AC | 独立复核 |
|---|---|---|
| 1 | 恒等元矩阵 + 空 enabled = 恒 1 | ✅ 上述 ②；测试断言逐条读毕为真 |
| 2 | deletionProtected 双腿 + 非 protected 不变 | ✅ 上述 ① |
| 3 | 写入点审计表完整 | ✅ 上述 ①；独立 grep 8 触点闭合 |
| 4 | maskGroups 组序/reorder 跟随/parity | ✅ 上述 ③ |
| 5 | node(for:)/displayTitle 全分支 + 未选中现值 | ✅ 上述 ④；6 分支（nil/develop/grade/drt/retouch/未知）+ 四分支标题 + rename 经命令流转投影跟随 |
| 6 | kernel/Metal 零 diff；公式行零语义改动；面板族零 diff | ✅ 独立 `git diff --name-only` 无 .metal；MaskCombiner 单行过滤；七页签面板族/InspectorEditSession/EditorAdjustmentStackView 零触 |
| 7 | 全套 0 fail ≈ 基线 + 10..14 | ✅ 2217 = 2203 + 14 精确（带上沿）；定向复跑逐值一致（表见上） |
| 8 | diff 边界 == 申报集 | ✅ `d103b9e..cda10e7` = 12 文件 = front-matter 申报集 + GOAL-STATE/BUNDLE-MAP 随动（LESSONS 未触发，无新踩坑） |
| 9 | 测试登记闭环（checker E2） | ✅ 两测试文件分别在 `Project.swift` App/Layers bundle sources（各 +1 行）+ BUNDLE-MAP `APP 9` / `LAYERS 5` 行；同 commit `tuist generate`（T1/T2 各自） |

## Findings（不计数 observation，登记备查）

1. **翻账指令笔误（已按用户裁决处理）**：派发指令「M2NODE-03 勾选 + Delivered
   （蒙版绑定 Grade-owned 语义面）」的括号描述实为 M2NODE-04 正文，且与
   M2-4-1 验收在案裁决（M2NODE-03 所有权框架宽限执行、严格面激活归 M2-5、
   不勾）冲突。经确认按指令笔误处理：**M2NODE-03 维持不勾**，本批勾选
   M2NODE-04（数据/绑定面 Delivered + 挂账注记）。
2. **D-5 挂账单点风险已消**：stroke 腿 payload 复核义务原仅存于 DECISIONS
   单文件；本批翻账已将其显式写入 REQUIREMENTS M2NODE-04 挂账注记（M2-7/
   M2MASK-04 双锚）。
3. **displayTitle develop/drt 分支测试用英文字面量**（`"Develop"`/
   `"Display Transform"`）：当前 catalog 缺键（defaultValue 生效）故绿；
   P3 zh 对账若译 `editor_node_develop`/`editor_node_drt` 需同批改这两处
   断言（或改同式 KEY 对照写法）——P3 收口对账清单应含此联动点。
4. **DECISIONS 审计表行号为改动前快照**（`.fill` :292 / `.clear` :298；
   T1 插入拦截代码后实际 :299/:311）：定性正确、触点集合与独立 grep 完全
   吻合，纯行号陈旧，不需修。

## 翻账清单（本批）

- REQUIREMENTS：**M2NODE-04 ✅ Delivered（数据/绑定面）**——蒙版绑定
  Grade-owned 语义面 + 挂账注记四条（D-5 stroke payload 复核归 M2-7/
  M2MASK-04；feather/应用序归 M2MASK-04；M2-7 面板 UI 消费面归 M2-7；
  新 5 UI 键 zh 滞后挂 P3 对账），锚 `42e2f95`/`9a3e906`。
  M2NODE-03 维持 M2-4-1 验收裁决不勾（严格面激活归 M2-5）。
- 本报告落盘 `phases/m2-4-node-model/M2-4-2-ACCEPTANCE.md`。
- 无修复 commit（零缺陷）。
