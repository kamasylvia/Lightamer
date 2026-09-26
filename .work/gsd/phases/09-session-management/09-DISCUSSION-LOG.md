# Phase 9 — Discussion Log（执行决策与移交记录）

> 执行期讨论按 plan 分批记录于各 `09-0X-DECISIONS.md`（09-01: 12 条 / 09-02: 12 条 /
> 09-03: 11 条 / 09-04: 12 条）+ 阶段裁决 `09-CONTEXT.md`（D-09-CONTEXT-1..7 用户
> 「全按推荐」）。本文件为**签核终节**：SC#1-6 证据指针 + Phase 11 移交清单 + 遗留对表。
> 体例对齐 07/08-DISCUSSION-LOG 终节。

## SC#1-6 证据指针终节（正本 = 09-VALIDATION.md 对照表）

| SC | 判据 | 证据指针 |
|---|---|---|
| SC#1 文件夹即会话 + 三级目录 | SessionLayout 幂等 + Coordinator 五步 | `SessionTreeScannerTests`（exactlyThreeTiers/IdempotentZeroDiff/OutputDirectoryConstantVectors）+ FINDINGS 09-3 目录落位走查 |
| SC#2 FSEvents + 孤儿 reconcile | watcher 四 flags + 四时点 + journal 双防 + 孤儿两动作 | `SessionWatcherTests`/`ReconcileDiffTests`/`SessionReconcileScheduleTests`/`SessionReconcileE2ETests` 37 例 + FINDINGS 09-3 监视状态链 |
| SC#3 多会话切换零泄漏 | 五步 teardown + recent 持久化 | `SessionSwitchTests` 13（泄漏四步 + L012 窗口探针）+ FINDINGS 09-3 recent 点击走查 |
| SC#4 浏览三态 | 双档管线 + 三态 UI + culling 子管线 | `SessionBrowserModelTests`/`SessionThumbnailProviderTests`/`ThumbnailMemoryCacheTests`/`CullingPipelineTests` 39 例 + FINDINGS 09-3 三态/双档/culling 走查 + 截图 3 张 |
| SC#5 复制粘贴 + before/after | PastePayload/pasteSet 单提交 + 三段批量管线 + 三形态对比 | `PasteSemanticsTests` 16 + `SessionBatchApplierTests` 12 + `BeforeAfterTests` 5 + FINDINGS 09-4 真会话粘贴链与 split/hold 截图 3 张 |
| SC#6 索引 DB 可重建 + 批量懒渲染基座 | schema v1 冻结 + 单事务 + 真身恒 sidecar | `SessionIndexStoreTests` 16（parity/WAL/12.9ms）+ `Perf07MassApplyTests` 3 + FINDINGS 09-4 DB 三列实证 |

## Phase 11（Export Pipeline，执行序 11 = ROADMAP §Phase 11）移交清单

1. **EXP-08 `Output/` 落点常量**：`SessionLayout.outputDirectory(for:)` 已就位
   （09-01 T2，`testOutputDirectoryConstantVectors` 钉向量）——导出编码器落盘路径
   直接消费；reservedRootDirectoryNames 单一真源保证导出目录不回流浏览集。
2. **批量管线队列复用面**：`SessionBatchApplier`（段1 compose + 段2 claim）、
   `BatchSidecarWriter`（段3 串行写队列 + 崩溃自愈 healDirtyRows）、
   `SessionIndexStore.claimBatchApply/clearBatchDirty`——EXP 批量导出清单与 Phase 14
   MCP-06 写回面（ROADMAP 2026-09-26 扩充）按同三段语义复用；sidecar 真身 +
   journal 吞自事件语义原样生效。
3. **collection 过滤缝**：schema v1 已预留 `rating/color_label/keywords` 列
   （D-09-CONTEXT-7）+ `SessionBrowserModel` 投影/有序多选向量——Phase 12 评分/标签
   列落地后，导出「按评分筛选导出」走 collection 过滤即可，无需 schema 迁移。
4. **`thumb_state` stale 再生缝供 EXP 缩略图**：导出后（或任何外部写）对行置
   stale + `thumb_params_hash` 翻转 → 9-3 后台队列自动再生（memory stale 感知 +
   execute 时重读行，9-4 已全链实证）——导出徽章/缩略图刷新零新接线。
   另：Phase 8 移交的 EXP-05 联合上下文注入缝（`injectYiyinRunContext` 导出尺寸重跑
   + `YiyinExportSettings.targetSize` 规格正本）继续有效（08-DISCUSSION-LOG 终节①）。

## 遗留对表（09-01..09-04 各 SUMMARY 遗留节合并）

| 遗留项 | 终态 | 下游 |
|---|---|---|
| Manual-Only 10 行（滚动 hitch/滚动手感/culling 布局/占位观感/多选手感/D10 混排/拖线手感/hold 观感/peek 等待/部分对话框） | VALIDATION 汇总表 pending-manual | 人工终验（verify-work）；#1 与 PERF-06 60fps 门挂 Phase 15；#6 挂 P3+ 色彩校准 |
| 跨图 undo 组（批量粘贴批级撤销） | plan 显式 defer；per-image commit 可退 | v2（批级 journal） |
| 层结构 merge（粘贴合并层栈结构） | D-09-04-D4：merge 只并全局实例 | v2 |
| skip 集 flag 制升级（DEPRECATED/UNSAFE_COPY/HIDDEN） | D-09-04-D1：现边界 `<15.0` 常量随 v50 表 | IOPFlags 引入三 flag 后平移 |
| culling 4 图扩展位 | v1 = 2 图 cap（D-09-CONTEXT-6） | 后续 plan（常驻账本复核口径已备 D-09-03-D11） |
| Trash/Selects 目录 + 会话内删除工作流 | 不建（D-09-CONTEXT-3，REQUIREMENTS 字面三级即契约） | v1 后 |
| Crop/ 工作副本语义 | v1 仅空目录维护 | 大功能另立 plan |
| GUI-20（09 轮：侧栏已编辑计数不即时刷新，轻） | grid 行/徽章即时刷新；侧栏计数挂 reconcile/重开时点 | Phase 12 顺手在 apply 收尾回填 counts |
| GUI-21（09 轮：mode segmented CGEvent 点击不可靠） | AX radio 语义点击可靠；人工使用不受影响 | 自动化按 AX 口径（PLAYBOOK §3 复证） |
| PERF-06 万张滚动 60fps 门 + Release 分栏 + 10k hitch signpost | 工作基线已落 perf.md | Phase 15 门清算 |
| PERF-07 段3 SSD 吞吐（万张 ~6-9s）与 USB 卷分钟级预期 | 只记录不设门；后台队列 + 进度 + dirty 徽章为 UI 对策（dt 同构） | Phase 11 导出/Phase 14 MCP 写回复用队列时复核 |
| 双档观感抽检（D10「可辨」残差） | 常驻抽检测试随管线演进出真值 | P3+ 色彩 iop 校准后收敛 |
| zh-Hans.lproj 空目录（dgzsvdww 增量产物噪音） | 源头无 zh-Hans（xcstrings 仅 zh 标签）；clean 产物仅 en+zh；zh 回退正常（GUI 轮实证） | 无需处理；DerivedData 增量残留，clean 构建自消 |
| paste/flag 菜单 stub（9-3 占位） | 9-4 已交付真身 | rating overlay 菜单 = Phase 12 |
| externalEdits 解码缓存失效执行 | 9-2 数据缝（externalEdits 桶）+ 9-3/9-4 消费 | 按需在 Phase 12 打磨 |

## GUI 验收轮汇总（9-3 + 9-4 两轮，正本 FINDINGS.md）

- **09-3 轮**（2026-09-25，浏览全链）：真会话 4/2/0 计数精确、三级目录 + `.lightamer`
  落位、三态切换 + 重启保持、双档真机确认、磁盘缓存秒开、双击链、culling 双格含
  100MP、zh 首屏全量；**09 轮 GUI-19（浏览模式 Inspector 未隐藏）当场修**（`10cf39d`）；
  量化 = 视口亮度域 <16=1.42% 无断裂。
- **09-4 轮**（2026-09-26 凌晨，批量 apply + before/after）：真会话粘贴链 15s 内
  DB claim/段3 落盘/清 dirty/E 徽章/缩略图再生全实证；split HUD + hold \ 切换截图
  3 张；缺陷 GUI-20/21 均「轻，记录不阻塞」。
- **lproj smoke 终验（09-05）**：构建产物 `ls *.lproj` = en + zh（含 Localizable.strings）；
  zh-Hans 空目录仅存于 dgzsvdww 增量产物（源头 xcstrings 无 zh-Hans 键，clean 构建
  无此目录），zh 渲染正常（两轮 GUI 走查佐证），不构成 L025 回退断链。

## 签核判定

**Phase 9 签核：PASS（SC#1-6 ✅；status: validated + nyquist_compliant: true；
终轮 1133/6skip/0fail；PERF-07 门终值 0.490s Release/SSD）。** 终验走 verify-work；
Manual-Only 10 行挂人工不阻塞（自动化腿均已钉数值与语义）。
