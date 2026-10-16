# M7-4 CHECKER — 修订批独立反向核（fixer+checker 合批 worker，2026-10-13/17）

```
phase:      m7-4-mcp-o4
object:     M7-4-01-PLAN.md 修订批（commit 16011688）+ M7-4-CONTEXT.md D 条联动
input:      M7-4-01-PLAN-REVIEW.md（F1-F14）+ orchestrator 已裁（F1 = bump v11）
method:     放行门逐条复核（修订后 plan 亲验）+ Goal-backward + 修订自洽
            （v11 先例链对齐 / F2 四处联动 / F3 算术亲验 / F4 错误路径全走查）
            + 独立猎残（机检亲跑：全仓 removeItem 走查 / == 10 硬断言扫描 /
            V10 tolerance 法体亲读 / editing 冻结表亲数 / spawn env 缝亲核）
verdict:    **放行**（修订批 F1-F14 全部落位；checker 独立发现 C1 一项已
            回注修订——SidecarV11Tests 第五法；两项观察项登记非缺陷）
```

## 结论头

**PASS / 0 error + 2 minor（观察项，非缺陷）** —— 修订后 plan 可进入执行。
F1-F14 修订全部落位且自洽；F4 错误路径全走查确认 Export 链 destination 触点
恰一处（已改道）；F3 算术亲验 23；独立猎残抓获 C1（v11 bump 令 V10
future-tolerance 法语义退化——已回注 V11 第五法重正守卫）。

---

## 一、放行门逐条复核（F1-F14 → 修订落位核）

| # | 修订落位 | 核验方式 | 判定 |
|---|---|---|---|
| F1 | T3 action 2 三件（HistoryItem / 镜像四件全链 / schemaVersion 10→11）+ red_lines③ carve-out 形 + files_modified 四新行（LightamerSidecar / SidecarV11Tests / Project.swift / BUNDLE-MAP）+ T6 golden 改挂 V11 + T7 红线族机检补 carve-out 面核 + Checker 关注点 6 扩 | 修订后 plan 逐处亲验 | ✓ 落位 |
| F2 | T1 action 1 三点改形重写（②机理勘正 + ③纯 POLLIN 臂 sleep 250ms）+ action 4 校订注记真机理 + SC 四判据（Task.sleep 在位）+ red_lines ⑩「第③点分支体内含 sleep 非第四语义点」+ T7 DECISIONS 真机理表述 + CONTEXT D-M7-4-7 重写 + 晨审索引行更新 | plan/CONTEXT 四处联动亲读 | ✓ 落位且四处一致 |
| F3 | 五钉 21→22 全改 21→23（SC ×2 / files_modified ×4 / 正文 action 2/3 / red_lines①〔经 CONTEXT 摘要①〕/ 风险节 / Checker 关注点 3）+ 算术钉注记（editing 9 + culling 14 = 23） | 正文 grep `21→23` 七处、旧值 `21→22` 零残留 | ✓ 落位 |
| F4 | T4 action 1 追加清理腿改道（:724 exclusive 臂不触 destination / defer 兜底）+ action 4 第五腿 + SC hunk 判据 + files_modified ExportRenderer 注释 + T7 DECISIONS 申报 + 风险节 | 修订后 plan + 本文 §三 F4 全走查 | ✓ 落位 |
| F5 | T2 action 1 四装配点（+startReadOnlyHTTPHost :652-708）+ SC 恰 4 + CONTEXT D-M7-4-8 四点 + 晨审索引 | `startReadOnlyHTTPHost :652-708` 代码亲验（makeRegistry editing :658-664 在册） | ✓ 落位 |
| F6 | T2 两锚勘正（:714 / :952）+ 头注申报勘误段（「原 :524/:754 为漂移坐标，『fresh 坐标已亲核』申报在此勘误」） | 代码 `grep -n "func start"` 亲验：stdio :714 / http :952 / readonly :652 | ✓ 落位 |
| F7 | T3 action 4 reason 固定 token 集（notSessionMember / imageLiveInEditor / unreadableSidecar / internalError）+ SC grep `unreadableSidecar` + T6 action 5 reason 断言腿 + T7 DECISIONS 钉形 | 修订后 plan 亲验；token = 应答 JSON 字符串非 16 档封闭表错误码（红线④不触） | ✓ 落位 |
| F8 | T3 action 6 实现式钉死（`stack.position >= 0 ? stack.items[stack.position].author : null`）+ SC 真位式 + T6 golden 截断态构造腿 + CONTEXT D-M7-4-5 括注改写 | 修订后 plan/CONTEXT 亲验 | ✓ 落位 |
| F9 | T3 action 7 两工具 description 加 item-level note 区分句（distinct from append_note document-level） | 修订后 plan 亲验 | ✓ 落位 |
| F10 | T3 action 4 targets 重复项 invalidParams 一行 guard + T6 action 5 拒绝腿 + T7 DECISIONS 申报 | invalidParams = 封闭表既有码，零新增面 | ✓ 落位 |
| F11 | T3 action 4 末段 live source ≤2s 滞后申报（GUI dialog 同姿势非缺陷面）+ T7 DECISIONS 申报 | 修订后 plan 亲验 | ✓ 落位 |
| F12 | T3 action 2a 透传链签名（commitPaste + composeSegment 默认参）+ SC 两 diff 判据 + files_modified HistoryStack/SessionBatchApplier 注释 | 链 = apply → composeSegment → paste → commitPaste → HistoryItem.init 亲读 | ✓ 落位 |
| F13 | T4 action 1 其它 errno 说明补 EOPNOTSUPP/ENOSYS + 风险节论据修正（「皆本地卷」有隙 → 外置卷行为变化申报）+ T7 DECISIONS 申报 + UPSTREAM-QUEUE 降级可选项挂账 | 修订后 plan 亲验 | ✓ 落位 |
| F14 | warmLutLibrary helper 内 LIGHTAMER_SKIP_LUT_PREHEAT env 门 + 仲裁 fixture spawn 注入（:70-72 env 缝一行）+ SC 两判据 + 风险节 App bundle @main 零预热面判定 + T7 DECISIONS 申报 | spawn env 缝代码亲验；XCTest 宿主不跑 @main 判定自洽 | ✓ 落位 |

## 二、Goal-backward

ROADMAP §M7-4 行四目标 ↔ 任务面映射复核：

- **copy/paste（MCP2-08）** → T3（Catalog + 双工具 + golden）+ T6（union 27→29）——无孤儿。
- **note/author（MCP2-09）** → T3（字段/镜像/盖章/读面）+ T6（GUI 面 + V11 golden）——F1 修订后持久化面闭合，无孤儿。
- **UQ-A2** → T4（exclusiveFinalWrite + link + TOCTOU 负测 + 第五腿）——F4 修订后错误路径闭合。
- **M7-3 挂账①②③⑤⑥** → T1（S1 修复 + 探针迁 + e2e + 措辞注记）/ T2（A+C + S3 腿）/ T5（目录锚）——齐备；④ 无动作维持。

REQUIREMENTS MCP2-08..09（:438-439）+ UQ-A2（:459）全覆盖；Alcedo 对表偏离
申报面（items 并入 copy 应答 / render 快照保留 / 无 per-target 版本）在
CONTEXT D-M7-4-3/6/9 三处齐备。

## 三、修订自洽核

### F1 v11 链对齐 v8/v9/v10 先例

- bump 先例链亲验：AGENTS M3-3 节原文「sidecar v9（filmRecord 字段 +
  HistoryItem.filmRecord **镜像**）」——同族添加 = 字段 + 镜像 + bump 三件套
  与修订后 T3 action 2 形逐件对齐。
- `schemaVersionCurrent = 10`（LightamerSidecar :247）亲验 → bump 落点正确。
- **SidecarV11Tests 独立文件先例链亲验**：V5/V7/V8/V10 每个 bump 一独立专测
  文件在案（Tests/LightamerTests/ ls + Project.swift :624/:864 + BUNDLE-MAP
  :731 LIB〔=Layers 域〕行）——v11 新文件 = 先例忠实形，落 Layers 域（V10
  同位）。
- 全仓 `== 10` 硬断言扫描：**零命中**（schemaVersion 断言全部走
  `schemaVersionCurrent` 常量——ProcessVersionCarrierTests :254/:479 /
  SidecarMetadataV3Tests :295 / Phase6SidecarTests :96）→ bump 全仓零涟漪，
  唯 V10 :325 字面 11 一处（→ C1，见 §四）。

### F2 真机理与 T1 SC 联动

- 机理推演亲核：`poll(2)` timeout 只封阻塞相（man 2 poll 语义）——恒可读 fd
  就绪即返，原「超时形 = 4Hz 忙旋消解」确为假命题；sleep 臂为速率限制本体
  ——修法甲（纯 POLLIN 臂 sleep 250ms）消解自旋且不损 HUP 即时性（HUP 到达
  时下一轮 poll 立即返 HUP → 分流 break 不经 sleep 臂；12s 活性窗无扰）。
- watcher 与请求读取线程独立（Task.detached 分离），sleep 无请求延迟面。
- plan T1 action ①②③ / T1 SC / red_lines ⑩ / T1 action 4 / CONTEXT
  D-M7-4-7 / T7 DECISIONS 六处一致（grep「sleep 250ms」逐处亲读）。

### F3 算术

- editing 冻结表亲读（McpRegistrySnapshotTests :150-182：apply_params /
  render_preview / list_luts〔M7-3 6→7 注记〕/ export_image / match_color +
  截断前段）+ :203 断言 message「the editing+culling closed face is exactly
  21 tools」= 双域面 7+14；plan T6 action 2「editing 7→9」→ 9+14 = **23**。
- review 的 22 系 +1 惯性套写（list_luts 单工具 6→7 肌肉记忆）亲证成立。
- 修订后 plan 七处 21→23 + 算术注记在位；旧值零残留。

### F4 错误路径全走查（含第二处 destination 触点搜索）

全仓 `removeItem|trashItem` 扫描（产线码，Tests/.work 排除）：

- `ExportRenderer.swift :724`——唯一 destination 触点（encoder catch 清理
  腿），修订已改道（exclusive 臂不触）。
- `ExportGainMapEncoder.swift :119-120`——删的是 `ciTmp`/`rewrapTmp`（gain-map
  编码器自有 tmp），**非 destination**；T4 gain-map 臂同 wrap 后 destination
  形参换 tmp+link，此两处 tmp 触点语义不变（删自己 tmp）——无第二处触点。
- AI 域 `EnhanceCopyWriter.swift :171/:174`（destination 字样）——AI 增强
  可编辑副本写面，不走 encodeStage exclusiveFinalWrite 缝，与本特性无涉。
- 其余命中（DepthMaskService / AIWorkerDepth / EnhanceDialogModel /
  SettingsPages / LibraryProjectController / McpEndpointFile /
  LensfunDownloadService / McpBearerValidator）——各自独立面（AI 缓存 /
  设置清理 / 库搬移 / endpoint json / lensfun staging），均不在导出
  encodeStage 链上。
- **判定：Export 链 destination 触点恰一处，已改道覆盖；第二处不存在。**

### 登记纪律自洽

- SidecarV11Tests = 计划内新文件 → Project.swift 恰一行 + BUNDLE-MAP 恰一行
  （Layers 域）+ L041 tuist generate 恒末位——red_lines 登记纪律条已改写为
  确定性表述（非「若执行期必须」条件形）；预期带 +22..29 三处（front-matter
  estimated_tests / expected_all / 正文基线段）同步无残留旧带。
- T2「恰四文件」判据与 fixture env 行归属自洽（env 行归 T1 commit，T2 验收
  时为已落位面复核——plan SC 已注明）。

## 四、独立猎残

### C1（checker 独立发现，已回注修订）

**SidecarV10Tests :325 `future["schemaVersion"] = 11` 字面硬编码**——v11
bump 后 11 = `schemaVersionCurrent`，该法（testFutureVersionDocumentStillYieldsEverything
:315-336 亲读）从「future-version tolerant degrade 守卫」**语义退化为
「current 版本可读」**（断言仍绿但守卫面消失——`schemaVersion > current` 的
tolerant degrade 行为〔LightamerSidecar :98 注记面〕失去测试覆盖）。

- **修法（已回注 plan）**：SidecarV11Tests 补第五法——`future["schemaVersion"]
  = 12` 的 future-tolerant degrade 面（守卫迁移重正）；SidecarV10Tests 文件
  零触维持（其法名/MARK 注记保留，语义退化在 DECISIONS 申报）。
- review F1 未捕获此面（review 亲验止于「FUTURE-version tolerance 法自动守卫
  v11 前向可读」——只验证了 bump 后法仍绿，未推演法语义退化）；本 checker
  亲读法体 :325 捕获。

### 观察项（非缺陷，登记不修）

- **O-1**：CONTEXT 顺路件表①摘要行未提 sleep 臂（只写「POLLIN + revents 分流
  + bounded re-poll 250ms〔D-M7-4-7〕」）——D-M7-4-7 正本已重写，表行系摘要
  层级指向正本，不构成矛盾；执行批 DECISIONS 以 D 条为准。
- **O-2**：plan estimated_tests 的 T3 段「MCP2-09 ~4——sidecar 面落
  SidecarV11Tests」与 T6 段「SidecarV11Tests ~4 法入上条 MCP2-09 计」表述
  冗余但计数一致（4 法只计一次，带 +22..29 内）；C1 回注后 V11 为五法（T3
  ~14 的 MCP2-09 ~4 口径含 V11 五法 + SearchState golden 法合计口径，执行时
  逐法如实记账，越带申报条款兜底）。

## 五、结论

**放行。** 修订批（commit 16011688 + C1 回注）使 plan 达到可执行状态：

1. F1-F14 全部落位，四处联动面（plan 正文 / SC / red_lines / CONTEXT D 条）
   逐处一致。
2. F1 v11 链与 v8/v9/v10 先例三件套（字段 + 镜像 + bump）逐件对齐；全仓
   schemaVersion 断言走常量零涟漪。
3. F2 真机理六处一致，假命题已从台账源（plan/CONTEXT）清除。
4. F3 算术亲验 23（9+14），M7-3 H1 家族防复发注记在位。
5. F4 Export 链 destination 触点全走查 = 恰一处已改道；无第二处。
6. C1 独立发现已回注（V11 第五法守卫迁移）——checker 闭环。

执行面提醒（非阻塞）：T3-T6 间 Layers 域新增红窗面 = schemaVersion bump 后
SidecarV10Tests 既有法仍绿（零触维持）但 V11 新文件 T6 才落位——红窗已在
风险节申报形内（App bundle 快照红窗 + 分批纪律），无新增停等点。
