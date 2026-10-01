# M2-6-3 ACCEPTANCE — 面板 + EOTF 联动 + HDR 视口 + Post 四件迁移 + 收口（wave 3）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 7 commits（`ca7ded1`..`45e692d`，
> 正本 = checker 修正版 `905e979`：E3 follow gate 扩展 + E5 键折叠 post-params + m2 同位
> 订正 + m5 分支措辞，全部落地）。方式 = AC 10 条逐条核对 + 六重点定向抽查（实现亲验 +
> 测试真伪判读 + grep/git 机检）+ 三域独立复跑 + zh-audit 复跑。**结论头：PASS /
> 0 error + 0 minor。**

## 一、复跑 vs 声明

build-for-testing @ `45e692d` exit 0，三域定向独立复跑（`Scripts/test-direct.sh` 直启）：

| 域 | 声明 | 本轮独立复跑 | 判定 |
|---|---|---|---|
| App | 398/0/0 | **398/0/0**（163s，peakRSS 1363MB） | ✅ 逐值一致 |
| Layers | 268/3/0 | **268/3/0**（29s，1057MB） | ✅ 逐值一致 |
| IOPParity | 362/3/0 | **362/3/0**（376s，5983MB < 8G 门） | ✅ 逐值一致 |
| 全套 | 2464/16skip/0fail（基线 2435+29 = 7+9+6+7） | 三域实测 + 其余四域声明（IOP 467/1、Library 430/4、Sessions 279/4、Export 260/1）求和 = **2464/16** | ✅ 对账精确 |
| zh-audit | PASS（1282 源键/1495 目录键） | 亲跑 `Scripts/zh-audit.py --check` → **PASS**（同数） | ✅ |

## 二、六重点核查结论

### ① T3 真缺陷两枚（修复 diff 复核 + 回归测试真伪）

**判定：两枚均为真缺陷，修复在交付态，回归覆盖真实有效。**

- **缺陷①（模型读 carrier 滞后）**：修复前 `DrtPanelModel.record` 直读 session carrier——
  carrier 由滞后一拍的 Task 同步，快速连续编辑各自基于**陈旧记录**提交。修复 = 读面改三级
  `liveRecord（拖动中）→ history.effectiveDrtRecord()（提交真相，指针忠实）→ carrier（外来
  档兜底）`（DECISIONS D7）。回归真伪：吸附矩阵测试**同步读 history 投影**并做顺序状态机
  walk（(space, legal EOTF)×六 target，~60 组合；注释明言「carrier 的 Task hop trails」）——
  旧代码在 walk 中第二步起基于陈旧 carrier 提交即断言失败，**矩阵确实能揭穿该缺陷**，非
  事后补的摆设测试。
- **缺陷②（滞后通知覆写 carrier）**：修复前 `drtRecordDidChange(_ record:)` 用捕获参数写
  carrier——快速编辑序列或 undo 后到达的排队通知会用**旧值踩脏新状态**。修复 = 通知腿改
  `syncDrtCarrierWithHistory()`（从 history 真相同步，幂等；DECISIONS D10「carrier 是
  history 的会话缓存而非第二真相」）。回归真伪：`testSnapIsAtomicWithTheSpaceSwitch` 在
  undo 后 `waitForCarrier(url, equals: expected)`——旧代码的滞后通知恰在此窗口把 carrier
  踩回旧值，等待必然超时/失配。**两处测试对两处缺陷均为真回归。**
- 修复半径合规：缺陷① = DrtPanelModel 读面 + liveRecord 槽；缺陷② = PipeCoordinator 单
  函数体。无越界。

### ② E3 follow gate（checker 回注实现亲验）

**判定：按正本字面落地。** `EditorMTKView.swift` 每帧 draw 的 screen-colorspace 挂载收拢为
纯函数 `followGateActive(edrActive:drtTailActive:) = !edrActive && !drtTailActive`（:431，
与 checker E3 的扩展式逐字一致）；draw 内唯一调用点收口（:529），DRT 激活时 encoding-space
挂载不再被每帧覆盖回 screen colorspace。`drtTailActive` = `drtTailSurface != nil`（视口侧
镜像，coordinator 经 `drtViewportSurface` 注入）。测试双断言：真值表四格全覆盖 + **连续两帧
帧存活模拟**（p3d65/g22 编码空间挂载 → 两帧循环内 pin 指针不变——旧代码该模拟必翻）。
另有 42/42 (space,eotf) 组合 colorSpace 非 nil 总面 + BlitRegime 两新臂（drtSDR/drtFloat16，
DRT 恒压过 legacy 双面）+ legacy 三臂默认参零差（`EDRViewportTests` 不动、经扩展签名复跑）。

### ③ E5 尾平面键折叠（post-params 项 + 主链键面零改动）

**判定：AC#5 兑现，实现形状与 plan 字母有一处已申报的等价偏离。** `DrtTailAssembly.seed`
在 post 集**非空时**折入排序后的 op-name 集（order-insensitive）；**空集零折叠 → P1 种子
位等**（`testEmptyPostAssemblyAndSeedMatchTheP1Face` 位等断言钉死）。**偏离**：plan 字面写
「⊕ postParamsHash」；实现折的是**集身份**，四件的**参数值**经尾段 sub-run 自身的
levelHash 链（各 replayed box 的 paramsHash）进键——两路径对 AC#5 的行为面等价，且后者
让「四件参数变更 → 尾平面 MISS、method plane + 主链全 HIT」由
`testPostParamChangeReRunsOnlyTheTailDownstream` 实测钉死（sharpen 改参 → 恰 4 tail miss
= sharpen+bloom+grain+eotf）。偏离已在 T5 commit body 申报（「param VALUES ride the
sub-run's own levelHash chain」）+ SUMMARY 记载，**不计缺陷**。主链键面零改动（skip 谓词
为装配期摘除，`PipeCacheKey` 零 diff）。

### ④ E2 序锁全链（印框链 guard 在 T5 落地后复核）

**判定：序锁保持。** T5 尾段装配 = `[DrtMethodBox 74.0] → post 槽 74.1+（TailOrderedBox
只覆写 iopOrder，payload 逐成员 verbatim 转发）→ [EotfBox 75.0] → residents（borders 76 /
watermark 77）`——borders/watermark 恒在 EOTF **之后**重放，永不被 tone map 的 E2 guard
不变；P1 `DrtTailTests` 的画布带=1.0 白后画 + 图区保持 PQ 编码实测断言 + 结构序断言
（orders[2]==76.0）在空 post 集下原样成立（post 空集装配 = P1 链位等）。skip 谓词扩展只
降四件，borders/watermark 的尾驻留摘除原样保留。`testAssemblyInsertsPostSlotsBetween
MethodAndEotf` 新增序断言与 P1 面并存，两代测试同绿。

### ⑤ 持久化四件（rawOverrides 同构 + D1 零污染双断言）

**判定：同构成立，占位签注兑现。** 亲验四件：carrier per-url 隔离（缺键 = pristine，默认
record 不入 map——`testCarrierPerUrlIsolationAndDefaultAbsence`）+ 写腿 2s debounce 经
`updateDrtRecord`（rawOverrides 先例同位）+ restore 腿三态分级
（`restoreDrtRecordLeg`：nil 零动作 / 同值跳过 / 异值回注，失配记 error 日志——D10 真相源
签注）+ run 传点 pristine→`.sdrGamma`（D5 直通差异，isDrtRecordDefault 单源判定）。
**D1（HistoryItem snapshot 槽占位）零污染双断言亲读**：
`testRecordDrtChangeCommitsOnceAndCarrierSyncsOnUndoRedo` 断言
（a）`effectiveInstances()` 无 drtMethod/drtEotf 泄漏 +（b）live 实例集 count 不变——
「投影面不污染 instances」硬约束由双断言承载，另配 `drtDocumentScope` 排除面
（rebuildLayerStack 显式排除 + sidecar 层重建不涉）。historyHash 折叠 = 4 参扩展、
effective record 的 stableHash **末位**折入；无 drt item 档零折叠 → 3 参公式结果原样返回
（位等回归门在 `testHistoryHashFoldMovesWithDrtAndStaysBitIdenticalWithout`）。旧档零漂移 +
pristine 档不写 displayTransform key（v5 形态字节）两断言在册。

### ⑥ 10 条偏差合理性（SUMMARY 执行期偏差 1-6 + DECISIONS D1-D10）

全部成立、签注在册：①两执行期悬决（snapshot 槽占位 = D6 / specialContent 枚举保留换渲染
臂 = D1）均在 plan 授权范围内按 diff 最小面钉死，grep 审计证实 `editor.stack.drt.placeholder`
a11y id 仅存于退役事实注释；②真缺陷两枚见①；③P1 缺陷退休（D9：主链顶面 8-bit 量化）有
测试面守护（DrtTailTests 12/0 保持绿 + 格式断言翻转）；④plan 字母修正（D2：SDK 无
extendedITUR_2100 变体——终式 itur_2100_PQ/HLG + displayP3_PQ/HLG + SDR calibrated 建
面，macOS 27 SDK 核读成立，非 nil 42/42 实测）；⑤两处 E4 先例机械翻面（EditorStackRouting
D9 note pin 翻 absence / TAB-MATRIX 转录断言翻 DrtPanelView marker）各 commit body 申报；
⑥LayerCompositeDriver 零 diff 的 front-matter 偏差（postOpNames 随 TerminalTailPolicy
携带，`git show --stat c2d99bf` 亲核属实）。

## 三、AC 逐条

| # | AC | 判定 | 依据 |
|---|---|---|---|
| 1 | 持久化链（carrier 隔离/写腿一次/restore 三态/undo-redo 一步回/hash 折叠/旧档零漂移/pristine 不写 key） | ✅ | DrtPersistenceTests 7 法复跑全绿（App 398 内）；五要点逐一亲读（见⑤） |
| 2 | 面板（Method 恒展开 + FEATURE-MAP §5 逐行 + 预设单 commit + custom 派生 + peak 钳制 + Vignette 原位 + 占位不再产生） | ✅ | DrtPanelModelTests 9 法（结构随 method 切换/Vignette+槽路由/预设原子 undo/method 幂等/custom 派生/peak 三件式）；占位壳视图+文案+a11y id 删除 grep 零残留（D1 枚举处置一致） |
| 3 | EOTF 吸附（6×7 全组合 + 原子 commit + 联动单源） | ✅ | 吸附矩阵（pristine 入口 6 target + 顺序状态机 ~60 组合，UI 可达域全覆盖——非法组合 UI 构造不可达由 picker 源测试钉）+ 原子双值 undo + `legalEOTFs` 单源 pin；grep 审计 App 层零第二实现 |
| 4 | HDR 视口（四分支矩阵/非 DRT 逐字节/手动 EDR 原样/互斥/colorSpace 非 nil/E3 gate） | ✅ | DrtViewportTests 6 法（surface 矩阵/零差面/E3 真值表+帧存活/toggle bypass 端到端/终式 42/42/regime 两臂）；既有 EDRViewportTests 5/0 零差（IOP 复跑） |
| 5 | Post 四件（skip/尾段序/golden 重钉/键局部性/非 drt 零回归） | ✅ | DrtPostMigrationTests 7 法复跑全绿（Layers 268 内）：装配序/空集 P1 位等/集身份折叠/skip+重放字节/键局部性 4-miss/display 域锚/bench 观察行 |
| 6 | `panel_note_pre_drt` 零残留 + TAB-MATRIX 勘误行 + 注册面零 diff | ✅ | Swift 源 grep 零命中（残留仅 plan/历史 md 转录面）；TAB-MATRIX 四勘误行 + displayTransform 页实态行亲读；红线五文件 `git diff ca7ded1^..45e692d` = 0；Registry/NodeOwnershipCatalog M2-6 全程零触碰 |
| 7 | zh 全落账 + audit PASS + 专名不译 | ✅ | 亲跑 PASS（1282/1495/{en,zh}）；面板键专名 zh=英文原文抽验（DrtPanelView 键面） |
| 8 | 红线五文件零 diff + PixelPipe/EditorMTKView 半径 | ✅ | 五文件零 diff 机检；PixelPipe diff = skip 集/插槽+TailOrderedBox/种子折/格式面（主链键面/DRT 装配段零改动）；EditorMTKView diff = surface 四态/两臂/gate/终式（渲染数学零改） |
| 9 | 全套 0 fail，计数 2435+25..40 | ✅ | 2464 = 2435+29；三域复跑逐值一致 |
| 10 | diff 边界 == 申报集 + 测试登记闭环 + front-matter 申报 | ✅ | 24 文件 = 申报 21 + E4 先例补充 3（各 commit body 申报）；四测试文件 Project.swift + BUNDLE-MAP 双命中 |

## 四、Findings

- **0 error / 0 minor。** 执行方申报与实态无一处不符；E4 族补充申报口径核过。
- **观察项（不计缺陷）**：E5 实现形状与 plan 字母的「⊕ postParamsHash → ⊕ post 集身份 +
  参数值经尾段 levelHash 链」等价偏离——行为面由键局部性测试实测钉死，commit body +
  SUMMARY 已申报，无需回改（晨审若要求字面回流 = seed 函数一处，行为不变）。
- git status 滞留 = 既有 gui-acceptance 走查产物（前序轮遗留 untracked/modified jpg），非
  本 plan 边界，未触碰。

## 五、翻账

- REQUIREMENTS **M2DRT-01 → [x] Delivered**（面板 + 占位退休 + 默认 OpenDRT 偏离登记 D5）。
- REQUIREMENTS **M2DRT-04 → [x] Delivered**（面板/联动吸附/HDR 视口腿全交付；导出链接线 =
  M2-9，编码核/判定/复用面已备）。
- REQUIREMENTS **M2DRT-05 → [x] Delivered**（Post 迁移 + E5 键折叠 + D9 格式修正 + 注摘除）。
- REQUIREMENTS **M2DRT-06 → [x] 终验 Delivered**（面板暴露两 case + 注册面零 diff + D1 兑现
  + parity 回归挂账注记）。
- REQUIREMENTS **M2DRT-02/03 终态补注**（面板暴露面落地，M2-6-1/M2-6-2 交付不变）。
- GOAL-STATE 续接点补本验收条目；本报告与翻账同一 commit（不 push）。

## 六、M2-6 phase 小结（3 plans 全闭环）

| plan | 交付 | 终态 commit | 验收 |
|---|---|---|---|
| M2-6-1 | OpenDRT 核（DrtRecord/EOTF 七函数+kernel/Float64 参考/kernel golden/预设三件套/sidecar v6/TerminalTailPolicy+尾段装配） | `4289f12` | PASS 0E+3m（`M2-6-1-ACCEPTANCE.md`，9ff9dc3） |
| M2-6-2 | ACES 2.0（CAM16/JMh/限色七表+RGC/ODT 参考/kernel+method 分派；Apache-2.0 署名链） | `d678118` | PASS 0E+0m（`M2-6-2-ACCEPTANCE.md`，12888dc） |
| M2-6-3 | 面板 + 联动吸附 + HDR 视口 + Post 四件迁移 + 持久化链 + method/zh 收口 | `45e692d` | PASS 0E+0m（本报告） |

- **测试演进**：2327（M2-5 终态）→ 2402（M2-6-1）→ 2435（M2-6-2）→ **2464/16skip/0fail**
  （+137；skip 恒 16 既有在案）。
- **M2DRT 全族终态**：01 面板 ✅ / 02 预设三件套 ✅ / 03 ACES 2.0 ✅ / 04 Color & Encoding +
  HDR 视口 ✅ / 05 Post 四件 DRT 后一次 ✅ / 06 method 注册口 ✅（REQUIREMENTS 本批全勾）。
- **执行期真缺陷档案**：M2-6 共修 3 枚真缺陷——T3 面板陈旧读 + 通知覆写（本 plan，吸附矩阵
  揭穿）+ P1 主链顶面 8-bit 量化退休（D9）；均带回归测试在册。
- **挂账（非阻塞，交接面）**：
  1. **走查观察五项**（纪律 11，非门——待 gui 验收轮）：HDR 屏实机 DRT-HDR + 非 EDR 屏
     降容显示 / DRT-HDR canvas mat 深浅（PQ 域解释）/ Post 四件 display 域视觉强度 / EOTF
     切换 FULL 大图时延 / 预设三件套手感。
  2. **Manual-Only 清单**：上述走查项归 GUI 验收轮统一执行（`.work/gui-acceptance/` 惯例）。
  3. **F1 zh 缺口延续**：ProjectWorkspaceFace 4 处 verbatim zh 缺口（M2-3-4 F1 起挂账，经
     M2-4/M2-5 延续）仍归专项 zh sweep；本 plan 新键已全落账（audit PASS）不新增缺口。
  4. **M2-9 导出腿**：EOTF 编码核 + `isHdrEncoding` + `DrtTailParams` 复用面已备，writer/
     ICC/队列集成按 ROADMAP M2-9 行接线（输出 ICC 与 DRT 编码强制联动）；图库 HDR 标志位
     `.lalb` 投影列归库面后续 plan。
  5. **M2-11**：60fps 复验（本 phase bench 行 = 尾段全链 preview-2560 cold 117ms / warm
     85ms、FULL 1024×640 20ms，为基线输入）。
  6. **parity 后评估回归**（filmic/sigmoid/agx 是否解禁）：AGENTS.md M2-6 增量节注记挂账。
- **下一步**：C 档门控第 3 停——M2-6 phase VALIDATION 签核（verify-work 输入 = 三
  ACCEPTANCE + DECISIONS + 本小结 + 挂账清单）→ 用户确认后 M2-7。
