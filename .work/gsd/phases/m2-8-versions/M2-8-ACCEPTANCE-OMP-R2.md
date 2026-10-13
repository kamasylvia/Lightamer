# M2-8-ACCEPTANCE-OMP-R2 —「版本与历史」双路并发终验（OMP 路）

> 验收员：OMP 独立回溯二次验收员（零共享上下文）；日期 2026-10-10；HEAD `efef1462`。
> 方法：亲读三 ACCEPTANCE + M2-8-3-DECISIONS + AGENTS.md M2-8 节，对上一轮 OMP 报告抽查点①-⑤独立重验（现树读码 + git 机检 + 计数），测试引用已记录终值未复跑。
> 口径：上一轮引用的时代树 `a26b005` 及实 SHA `66f0cb7`/`9d9ed87` 现树均已 `unknown revision`（历史再次重写），同 subject 实 commits 现为 `5ca8c546`/`d6271a9c`；本轮全部按现树 + fix commit diff 取证。

**结论头：PASS / 0 error + 0 minor**

## 抽查点 1：sidecar v7 双键 + 不双写 + v6 零漂移 + hash 隔离 — PASS

- 双键在位：`LightamerCore/Sources/Sidecar/LightamerSidecar.swift:302,308`（`versions`/`activeVersionID`，后演进 v8/v9 additive 未动此二键，不记账）。
- `SidecarVersionRecord`（同文件 :833-888）：active 槽 `encodeIfPresent(chain)` 键缺席（:884-886）= items 不双写编码面；单点铸造 `init(...chain: HistoryStack?)`（:853-862）+ `chainStack` 读回（:866）。
- v6 零漂移：`decodeIfPresent`（:475-477）+ `encodeIfPresent`（:546-547）；`schemaVersionCurrent = 9`（:207，后演进 v8/v9 加法，不记账）。
- `SidecarV7Tests` 8 法：不双写 = active 无 `chain` 键 + 全文档 `"items"` 计数 == 1（:183-211 机检亲核）；hash 负测 = 篡改版本元数据 `driftDetected == false`（:215-240）；`HistoryHash.hash` 签名仅 instances/decodeParamsHash（`HistoryHash.swift:37-40` 后演进迁入 `Pipe/History/`，不记账）= 版本结构无入口结构性隔离。
- 测试终值引用：上一轮定向 `SidecarV7Tests` 8/0/0 + 首验全套 `TOTAL|2577/16/0`（M2-8-3-ACCEPTANCE §四），本轮未复跑（任务书默认不跑）。

## 抽查点 2：version_ref 激活 + 迁移轮换 + sink 注入 + swap 单路径 + pristine 收窄 — PASS

- reduced DDL：`LibrarySchema.swift:375-382` `version_ref` 恰 5 列（version_id/element_id/display_name/created_at_unix/updated_at_unix，CASCADE 在列定义）；`versionRefColumns` 顺序冻结（:390-396）与 DDL 逐列一致；`head_commit_hash` 不激活（:87 注释钉明）。
- 快照轮换：`ProjectFileStore.swift:285-288` 代际命名 `pre-migrate.<stored>-<to>.bak` + 同名先删后照；死参收窄注释（:377-381）。
- sink 注入：`VersionProjectionSink`（`VersionCoordinator.swift:50`）+ 装配 `EditorWorkspaceShellView.swift:192-196`（有 store 装配 / Sessions 模式 nil，装配后调 `load`；相对 M2-8-1 时代装配点前移，KD-5 非 body 单源语义保持，后演进不记账）。
- swap 单路径：`switchTo`（:300-315）= capture 原链 → install 目标链 → 目标槽清 nil → `finishVersionAction`；`installVersionChain`（`EditorState.swift:132-142`）= `history + rebuildInstances() + rebuildLayerStack()`，半径无 decode 面，同图零重解码结构性成立。两函数各含 M6-1 只读门 early-return（后演进，不记账）。
- pristine 收窄：`history.position >= 0 ? 1 : 0` 三处同式（`SessionIndexStore.swift:792,1274`、`SessionBatchApplier.swift:191`）；`SessionIndexSchema.swift:76` 注释钉明。

## 抽查点 3：两 FINDING 修复闭环现状在位 — PASS

- 实 SHA（现树）：FINDING-A → `5ca8c546`（--stat 5 文件：LightamerApp + AdjustmentTransferView + Project.swift + BUNDLE-MAP + SheetEnvironmentInjectionTests）；FINDING-B → `d6271a9c`（--stat 4 文件：WorkspaceHostView + Project.swift + BUNDLE-MAP + ToastFaceTests）；父链 `d6271a9c→5ca8c546→bc4d89e7` 连续，subject/body 与首验申报逐项一致。
- A 修复现树在位：`AdjustmentTransferSheetContent`（`AdjustmentTransferView.swift:330-340`，init 双参 + 内容内双 `.environment` 重注入）；app-root sheet 闭包挂该面（`LightamerApp.swift:1461-1462`）。
- B 修复现树在位：`WorkspaceHostView` 底部 `safeAreaInset` 挂 `ToastBarView`（:158-169，注释钉明 FINDING-B 缝）；`ToastBarView`（:1474-1500）：nil = 空分支零 chrome，有 toast = 22pt + surfaceRaised + monospaced + hairline + `status_toast` 标识；legacyBody 零触（ContentView StatusBar 仍仅 legacy 面）。
- 回归测试文件 8/8 在位（ls 亲核）；终值引用上一轮定向 1/0/0 + 3/0/0，本轮未复跑。

## 抽查点 4：单谓词排除面单源 — PASS

- `isAdjustmentTransferable`（`AdjustmentTransfer.swift:35-38`）= terminal trio 排除 + `owner(of:) == .grade`，唯一定义点；消费点仅枚举/重建两处（:249,256）经谓词，无第二份排除逻辑。
- `AdjustmentTransferTerminalTrio.opNames`（:42-46）= ColorIn/ColorOut/Gamma 三模块 `opName` 常量，零字符串字面量。

## 抽查点 5：登记对账（BUNDLE-MAP + 计数）— PASS

- `grep -c "func test"` 实况：SidecarV7 8、VersionSwap 11、VersionsPanel 5、HistoryRowJump 7、AdjustmentTransfer 8、CleanTerminateSentinel 3、SheetEnvironmentInjection 1、ToastFace 3。
- BUNDLE-MAP（`M2-4-0-BUNDLE-MAP.txt:311-318`）登记 8/11/5/7/8/3/1/3——**八行逐值一致**，首验三批勘误终值稳定。

## 分歧项

1. **SHA 口径再漂移（注记，不入计数）**：上一轮「实 SHA」`66f0cb7`/`9d9ed87` 现树已 `unknown revision`；同 subject 同内容 commits 实为 `5ca8c546`/`d6271a9c`（--stat 文件集与上一轮申报一致）。上一轮 minor（e9c03af/4e7fc58 口径差）口径已过期，本报告以现树实 SHA 引用。内容一致，非实质分歧。
2. **时代树不可用（注记，不入计数）**：`a26b005` 现树不存在，无法按时代树取证；本轮以现树读码 + fix commit diff（内容与 DECISIONS §3/首验 §三逐项一致）替代，覆盖等价。
3. 实质判定分歧：**无**。上一轮五抽查点结论（①-⑤ PASS）本轮独立取证全部复现成立；首验三 PASS 结论无推翻项。

## 会话卫生

只读验收：除本报告文件外零写入；测试未跑（引用终值）；未发起网络动作；未 push。

OMP-VERDICT: PASS
