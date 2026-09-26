# Plan 09-02 — SUMMARY：FSEvents + reconcile（SESS-05）

> 执行：ZCode subagent worker（夜间 GSD 流水线，omp 分诊模型下的 subagent 执行档）
> 日期：2026-09-25（单会话五任务连续执行）
> 基线：1017 / 6 skip / 0 fail（09-01 终轮）→ **终轮：1054 / 6 skip / 0 fail**（净增 37）

## 任务表

| 任务 | 内容 | commit | 测试证据 |
|---|---|---|---|
| T1 | `ReconcileDiff` 纯函数五桶 golden + rename 幸存 apply 腿（Core） | `5ab2868` | ReconcileDiffTests 16/0fail；09-01 三套回归绿 |
| T2 | `SessionWatcher` FSEventStreamCreate 封装（四 flags + WatchRoot + 私有队列 + AsyncStream）+ 四缺陷对策落位 + 单一真源 exclude 谓词重构 | `fe51f41` | SessionWatcherTests 8/0fail（真 FSEventStream 合成事件）；Scanner 回归 13/0fail |
| T3 | `SessionReconciler` 四时点调度 + 自反馈环双防 + 100 sidecar 零自触发常驻断言 + 行级 stale 标记 | `d847948` | SessionReconcileScheduleTests 8/0fail；session 族六套回归绿 |
| T4 | 孤儿 sidecar 移除/忽略两动作（meta KV 持久化，schema 零迁移）+ rootLost 五态接线 + 侧栏动作面 + 外部变更 E2E | `46ef09e`（amend 修正 message 反引号截断） | SessionReconcileE2ETests 5/0fail；session 族回归绿 |
| T5 | 全量回归 + touch 重编复跑 + SUMMARY/DECISIONS/TODO/LESSONS/GOAL-STATE 账目闭合 | 本提交 | 全套 1054/6skip/0fail |

执行决策 12 条入 `09-02-DECISIONS.md`（latency/debounce、吞事件形态、子树 diff 细化、rename 配对规则、apply 分层、externalEdits 判定、孤儿 ignore 持久化、五态命名、生命周期挂点、batch 双字段、L027 应用、残留事件基线差值）。

## 验收标准逐条对照

- [x] **reconcile 纯函数**：五桶 golden 逐集合精确（added/removed/changed/renamedSurvived/orphanSidecars + externalEdits 第六桶）+ rename 幸存配对裁决（`(mtime,size)` 精确指纹、一对一、原行不丢——`testApplyRenameSurvivalKeepsBackfilledColumns` 逐列断言 params_hash/has_edits/imageID 存活）+ externalEdits 单独桶；apply 单事务纪律（复用 09-01 sync 事务，rename 前置腿同事务）。
- [x] **FSEvents watcher**：`FileEvents | UseCFTypes | NoDefer | WatchRoot` 四 flags + latency 0.3s + 私有串行队列 + AsyncStream；四缺陷对策逐一落位（coalescing→hint-only 只触发 reconcile【T3 消费】；4096→目录级分类 + truncated 升全量【`testBatchCapSemantics` + T3 forced 腿】；rename 丢失→stale 不删行 + stat 裁决【T1 配对 + T4 E2E 钉死】；丢事件→获焦强制兜底【`testFocusGainForcesReconcile`】）。
- [x] **四时点 reconcile 全接线**：①开卷（coordinator sync，watcher 后臂）②获焦（didBecomeActive 强制）③事件批后 debounce 300ms ④WatchRoot/MustScanSubDirs/截断强制全量；`folderWatchStatus` 五态真源（rootLost 新增 + recent 失效提示，路径不静默改写）。
- [x] **自反馈环双防**：exclude 单一真源（watcher 消费 scanner 谓词，值级测试钉死）+ 写侧 journal 吞事件；**100 sidecar 零自触发常驻断言绿**（真实 writeAtomic 路径 + watcher 在跑，基线差值增量 == 0 且 swallow > 0）。
- [x] **孤儿 sidecar**：索引标记（09-01 已有行）+「移除/忽略」两 reconcile 动作（移除带确认弹窗）+ 永不硬失败（store 腿返回 Bool 不 throw、closed store / 非 .lra 拒绝路径有测）。
- [x] **外部变更 E2E**：Finder 模拟四类变更（增/删/会话内移/改写）收敛 index==disk 精确 + move-out rename 幸存自愈钉死（不丢单不重复）+ 孤儿两动作各一 case。
- [x] **全套 0 fail + 每任务独立提交 + 边界查开关 + SUMMARY/DECISIONS 落盘**。

## 防空转自检

- 五桶 golden 全部**成员精确断言**（非计数非存在性）；混合场景六桶逐路径比对。
- 自反馈零计数：`reconcileLog` 增量 == 0 且 `journalSwallowCount` 增量 > 0（双断言防「没听到事件」假绿——后者证明事件链路活着）。
- 合成事件测试限时 await（10s 超时 = fail，实测 create/rename/move-out/delete/sidecar/WatchRoot 全部 <2s 到达）。
- E2E 收敛断言含**二次 reconcile 空 diff**（防重复计数/残留行假绿）。
- 单测直启（L019b test-direct.sh）全程零密码弹窗。

## 亮点与踩坑

1. **L027 在 FSEvents 的活体复现**：watcher 初版所有文件事件被前缀过滤静默丢弃（FSEvents 上报 `/private/var` 物理拼写而 `URL.path` 保留 `/var`），WatchRoot flag-only 事件正常到达一度造成误判——realpath 双前缀 + journal 查询变体对修复。已增补 L027 场景注记。
2. **SinceNow 残留事件**：watcher arm 前的文件创建事件会在 arm 后立即投递（FSEvents 合并窗）——常驻断言因此采用基线差值；生产语义无害（hint-only 幂等）。
3. **runReconcile 状态机修正**：`.scanning` 无条件覆写会吞掉 rootLost——改为 `currentSessionRootLost` 旗标决定终态。
4. **xcstrings 外科手术**：两次尝试整文件 JSON 重写导致 2100 行 churn 后回滚，改为锚点插入（+34/+85 行净增，Xcode 格式保持）。

## 账目

- TODO.md Phase 9 节 09-02 勾选（本批同更）。
- LESSONS.md L027 增补 FSEvents 适用面注记（无新 L0xx——纪律同源，应用面扩展）。
- GOAL-STATE.md Phase 9 续接点更新（9-2 完成 → 9-3 待执行）。
- 下步：Plan 09-03（浏览模式三态 + 双档缩略图管线，9T）。
