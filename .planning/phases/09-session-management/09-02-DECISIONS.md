# Plan 09-02 — Execution Decisions

> 执行期决策记录（RESEARCH §4 未覆盖细节）。凡标「执行期钉死」者均已实现并有测试钉住。

## D-09-02-1: watcher latency = 0.3s（coalescing 窗取 RESEARCH 区间 0.3–0.5s 的响应端）

- **决策**：`SessionWatcher.defaultLatency = 0.3`。burst 仍合并（coalescing 对策本来就信不过逐事件），单次外部编辑 0.3s 内提示、+0.3s debounce 内收敛，端到端 ~0.6s。
- **代价**：重负载下合并更激进——hint-only 设计下无正确性风险。

## D-09-02-2: 吞事件形态 = 写侧 journal（二选一中的「写入方显式记录 + reconcile 侧按 path 过滤」混合形态）

- **决策**：`SidecarWriteJournal`（Core，`@unchecked Sendable` + NSLock，注入式，默认 `.shared`）。`SidecarStore.writeAtomic` 晋升成功后 `record(path:)`；`SessionReconciler` 对事件 path 查 `containsRecent`（TTL 30s），命中则吞（`journalSwallowCount` 计数），**全批皆吞则整个 batch 不调度 reconcile**。实现位置上 journal 是「写入方记录、消费方过滤」的混合——plan 给的两个选项（写后过滤 pending 计划 / 写入方显式吞）分别对应 journal 的记录与查询两半。
- **理由**：reconciler 侧只拿得到目录级 batch，path 级吞必须发生在事件侧；journal 是唯一能把「谁写的」带给「谁听见」的通道。TTL 30s 远大于 latency+debounce（~0.6s），漏吞降级为一次无害空 reconcile（幂等 diff），永不成风暴。
- **测试钉住**：`testOneHundredSelfWrittenSidecarsTriggerZeroReconciles`（常驻断言，真实 writeAtomic 路径 100 连写 + watcher 在跑，reconcile 增量 == 0 且 swallow > 0）。

## D-09-02-3: 子树 diff 细化 = 纯函数留 `subtreeFilter` 参数缝，9-2 一律全量 diff

- **决策**：`ReconcileDiff.diff(subtreeFilter:)` 只过滤**报告桶**（优化缝，默认 nil = 全量）；apply 腿恒为全量 sync（单事务、幂等）。事件批的三、四时点不做子树裁剪。
- **理由**：扫描是 readdir+stat（暖 SSD 万张 ms 级），裁剪省的 I/O 远小于双 diff 路径的正确性风险；RESEARCH §4.3 明示「仅受影响子树——执行期决策细化」，此处细化 = 「先正确后优化，缝已留」。计量在 9-3/9-4（PERF-06/07）如有需要再启用缝。
- **代价**：万张树上每次事件批全量 stat——debounce 300ms 已把风暴摊成单次。

## D-09-02-4: rename 配对规则 = (mtime,size) 双精确匹配，字典序先到先得，一对一

- **决策**：removed × added 候选按 `StatFingerprint(mtime,size)` 精确相等配对（APFS rename 双双保真）；同指纹多候选时 destination 取字典序最小（确定性）；一 removed 只配一 added。mtime 是 Double 位级相等——fixture 用 `setAttributes` 钉 mtime 保证测试确定性。
- **边界语义**：cp 保留时间戳的拷贝会误判为 rename——无正确性影响（行集合相同，仅桶标签差异），接受并记录。

## D-09-02-5: apply 腿与纯函数分离的形态 = Core 纯函数 + Store.sync 的 rename 前置腿（同文件分层复用 09-01 事务）

- **决策**：`ReconcileDiff` 纯函数在 Core 产 plan；apply = `SessionIndexStore.sync` 增加 `renames` 参数——每个 rename 裁决变成**同一事务内**的 path UPDATE（保行保回填列），随后 added/removed/changed 孤儿腿在调整后的内存视图上照常运行。公开入口 `SessionIndexStore.reconcile(root:scan:renames:)`（关库后幂等重开 + NULL 类回填 + counts）。
- **理由**：单事务纪律零分叉（09-01 注入测试原样覆盖 rename 路径的原子性）；「保行」语义（rating/has_edits/params_hash 随路径更新存活）有逐列断言。
- **已知限制（记录，非缺陷修复）**：rename 行的 `thumb_path` 保留旧 pathhash（缩略图内容未变，9-3 磁盘缓存按自身 path-key miss 再生）；rename 行 `sidecar_present` 按新路径现场 stat。

## D-09-02-6: externalEdits 判定 = 原片漂移 ∧ sidecar mtime 未动；sidecar mtime 只对漂移候选 stat

- **决策**：controller 侧只为 **mtime/size 漂移候选** stat sidecar（数量小），喂 `ReconcileScanSnapshot.sidecarMtimes`；纯函数判「prev.sidecarMtime != nil ∧ curr == prev」入桶。全树 sidecar stat 被明确否决（USB 卷上每 reconcile 10k stat 违背 hint-only 的成本模型）。
- **下游缝**：externalEdits 桶随 `SessionReconcileOutcome.plan` 暴露（9-3/9-4 消费：解码缓存失效 + thumb 再生优先级）；行级腿已由 sync 的 changed UPDATE 落实（thumb stale + sidecar 列清空 → 回填重读）。

## D-09-02-7: 孤儿「忽略」标记持久化 = meta 表 KV（schema 零迁移）

- **决策**：`orphanIgnore/<relPath>` 键入 `meta` 表（`SessionIndexStore.orphanIgnoreKeyPrefix`）。counts.orphans 仍含 ignored 行（分类记录稳定），`actionableOrphanRelPaths()` 过滤后供 UI。
- **理由**：09-01 schema 冻结契约「后续 plan 只消费不迁移」；meta 是索引自带的 KV 面，列迁移成本为负。

## D-09-02-8: FolderWatchStatus 五态命名 = notWatching/scanning/synced/stale/rootLost

- **决策**：plan 文中「watching」态沿用 09-01 的 `notWatching` 拼写（存量测试/目录页已引用），新增 `rootLost` 成第五态。rootLost 语义：状态行红色 + 提示文案；recent 列表**不静默改写**（L012：打开会话永远是显式动作），由 `SessionState.currentSessionRootLost` 旗标驱动提示。

## D-09-02-9: watcher 生命周期挂点 = app root 组合进 coordinator 闭包缝（不改 Step 枚举）

- **决策**：`closeIndexHandler` 组合 `reconciler.stopSession()`（teardown ②-d 之前停 watcher，事件不进已关库）；`syncIndexHandler` 在 sync 成功后组合 `reconciler.startSession(root:)`。SessionCoordinator 本体零改动。
- **理由**：09-01 SessionSwitchTests 逐字断言 stepLog 序列，新增 Step 会破冻结测试；闭包缝本就是 D-03b 的正道。
- **获焦接线偏离说明**：plan files_modified 列了 ContentView（获焦通知接线）——实际接线在 `SessionReconciler.startSession` 内订阅 `NSApplication.didBecomeActiveNotification`（订阅生命周期与 watcher 严格同生共死，且可单测直发通知），ContentView 无需改动。属落位优化，非行为偏离。

## D-09-02-10: WatchEventBatch = 目录摘要 + 文件路径集双字段；路径集 cap = 4096

- **决策**：`affectedDirectories`（相对目录集，日志/摘要缝）与 `affectedFilePaths`（绝对路径集，journal 吞事件与行 stale 标记的输入）并存；路径集达 4096 停止收录（batch 已 `truncated` 升级全量）。AsyncStream `bufferingNewest(64)`（hint 丢了有获焦兜底，不积压）。
- **must-rescan flag**：FSEvents 常量实际拼写为 `kFSEventStreamEventFlagMustScanSubDirs`（RESEARCH 行文中 "MustRescanSubtree" 的正式名）。

## D-09-02-11: FSEvents 路径拼写 = L027 应用（realpath 双前缀匹配 + journal 查询变体对）

- **决策**：watcher init 时 realpath(3) 求物理根，`rootPrefixes` 同时匹配 `/var` 与 `/private/var` 两拼写；reconciler 侧 journal 查询与 rowKey 映射都用**双拼写变体对**（`pathVariants`）。实测抓到过真实失败：无此处理时文件事件全被前缀过滤丢弃（WatchRoot flag-only 事件反而正常，曾造成误判假象）。
- **教训归档**：L027 增补 FSEvents 场景注记（LESSONS 同批更新）。

## D-09-02-12: 测试基线与残留事件处理

- **决策**：自反馈常驻断言采用**基线差值**——watcher 启动后先排水 1.2s（`kFSEventStreamEventIdSinceNow` 已知会投递启动瞬间前后的合并残留事件——本测试里是 arm 之前 100 个原片创建的合法外部变更提示），再落基线，风暴窗内 reconcile 增量必须为 0。生产语义不受影响（残留事件触发一次幂等 reconcile 是 hint-only 的正确行为）。

## 残留/移交（9-3/9-4 消费）

- sidecar 被外部删除且原片无变化的行：`sidecar_present` 不在本 plan 的 diff 桶内（原片未漂移不触发），下轮开卷 sync 收敛；如 9-3 需要即时语义，走 externalEdits 缝扩展（已记录，未实现）。
- grid cell 孤儿徽章视觉 = 9-3（本 plan 交付数据缝 `SessionState.orphanSidecarRelPaths` + 侧栏动作面）。
- externalEdits 的解码缓存失效实际执行 = 9-3/9-4（桶已产出）。
