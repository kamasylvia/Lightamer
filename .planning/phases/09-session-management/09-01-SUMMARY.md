# Plan 09-01 SUMMARY — 会话模型 + 索引 DB 基建

**执行**：ZCode subagent worker（夜间阵容），2026-09-25
**基线**：975/6skip/0fail（Phase 8 终轮 973 + verify-work 尾批 memo-key 回归 2）
**终轮**：**1017/6skip/0fail**（净增 +42；touch 重编复跑见 T8 节）

## 任务完成表

| T | 内容 | commit | 验证数字 |
|---|---|---|---|
| T1 | SessionState 状态机（recent 持久化去重/上限/剔除 + watch 枚举 + 浏览计数快照）+ SessionCoordinator 五步编排（闭包注入 D-03b + stepLog）+ `PipeCoordinator.prepareForSessionSwitch`（Phase 9 hook 落地）+ UI 三段侧栏/菜单/odoc 路由 + 12 键 catalog（zh 标签） | `e461fff` | SessionSwitchTests 11 例；全套 986/6/0 |
| T2 | SessionLayout 三级目录幂等（Trash/Selects 不建）+ `outputDirectory(for:)` Phase 11 消费点常量 + reservedRootDirectoryNames 单一真源 | `ee3c39c` | 幂等零 diff（双跑+三跑 mtime 快照相等）+ 纯函数向量；全套 992/6/0 |
| T3 | SessionTreeScanner：递归 walk + exclude 表单一真源（9-2 watcher 复用）+ stat 三元组分页流（256/页）+ 孤儿分类永不硬失败 | `c077a06` | golden 五类逐路径精确（pristine 4/edited 1/orphan 1/excluded 7）+ 渐进多页结构证明；全套 998/6/0 |
| T4 | SQLiteHandle（libsqlite3 薄封装零 SPM 依赖）+ SessionIndexSchema v1 冻结（25 列 + L013 TEXT + Phase 12 预留 + dirty + orphan_sidecar + WAL/synchronous=NORMAL）+ SessionIndexStore actor 增量同步单事务 + App 接线（SessionIndexController） | `0f26e0a` | schema 逐列断言 + 三向量精确 diff + 注入回滚 + v99 拒开；全套 1005/6/0 |
| T5 | sidecar 摘要回填（imageID/has_edits/params_hash decimal TEXT/layer_count/layer_summary/sidecar_mtime）+ sidecar mtime 漂移重读 + EXIF 轻量列（ImageIO properties） | `de8a34c` | 真 .lra 逐列 round-trip（params_hash 逐字节 == historyHash）+ yiyin 实例翻转 + 降级不硬失败 + 真 JPEG EXIF 向量；全套 1011/6/0 |
| T6 | 删库重建 parity（SESS-07 门）+ WAL 崩溃恢复 + 10k 单事务 UPDATE 计时 | `abf99a8` | parity 13 列 × 50 行逐列相等（compared > 400）；integrity_check ok；**10k 单事务 12.9ms**；全套 1014/6/0 |
| T7 | 会话切换泄漏四步断言（真 PipeCoordinator + 真渲染填缓存）+ L012 单测探针（3 开 0 新窗 0 新 MTKView）+ 开卷 10k 暖/冷基线 + `.work/09/perf.md` | `64c0532` | 泄漏四步全绿 + 暖开卷 0.43–0.44s（≤2s 门余量 ~4.6×）/冷 0.47–0.54s 记录；全套 1017/6/0 |
| T8 | 全量回归终轮（touch 重编复跑）+ SUMMARY/DECISIONS/TODO/GOAL-STATE/LESSONS 账目 | 本提交 | 见下 |

* T1–T7 每任务边界均全套回归 0 fail。T1–T7 每任务边界均全套回归 0 fail。

## T8 终轮（重编复跑）

- `touch Tests/LightamerTests/SessionSwitchTests.swift` + `caffeinate -dis xcodebuild build-for-testing` + `Scripts/test-direct.sh`
- 结果：**1017 tests, 6 skipped, 0 failures**（与 T7 边界数字一致，重编复跑绿）。

## 验收标准逐条对照

| 验收面（plan Verification 表） | 判定 | 证据 |
|---|---|---|
| fixture golden：五类分类计数 + 逐路径精确 + exclude 逐规则 + 三级目录幂等零 diff | ✅ | `SessionTreeScannerTests` 13 例（golden 精确集合 + 双跑/三跑 mtime 快照相等 + 逐规则谓词向量） |
| 索引 DB：schema 逐列冻结 + 增量三向量 + 删库重建逐列 parity + WAL 崩溃 + 事务原子性 | ✅ | `SessionIndexStoreTests` 16 例（25 列 name+type 顺序对照 + L013 TEXT + PK + idx + meta；added/removed/changed 精确；parity compared>400；afterAdded/beforeCommit 注入回滚 verbatim；v99 拒开） |
| 会话编排：切换五步按序 spy + recent 去重/上限 + L012 三会话单窗 | ✅ | `SessionSwitchTests` 13 例（stepLog 顺序 + recent 4 向量 + 泄漏四步 + 窗口/MTKView delta 0 + route×3） |
| sidecar 摘要：.lra 逐列回填 + yiyin 实例翻转 + EXIF 轻量列 | ✅ | params_hash == historyHash 逐字节；has_edits 随 borders 参数翻转移位；orientation 6/64×32/DateTimeOriginal±1s |
| 计量基线：perf.md 开卷节 + 渐进 ingest 时序断言 | ✅ | `.work/09/perf.md`「开卷计量」节（暖 0.43–0.44s ≤2s 门；冷 0.47–0.54s 记录；L009 注记）+ `testScanIsProgressiveMultiPage` |
| 回归：全 suite 0 fail（基线 975 → 1017） | ✅ | 每任务边界全套绿（986/992/998/1005/1011/1014/1017 各点 0 fail；GoldenColor 已知负载 flake 三次双向归因：隔离绿 + 冷却全跑绿，02-04 台账在案非引入） |

## 防空转自检

- golden 分类：**精确集合断言**（非计数相等即过），excluded 噪声逐条断言未泄漏。
- parity：**逐列 13 × 50 行**断言 + `compared > 400` 下限（禁「行数相等即过」）。
- 10k UPDATE：置位后**回读验证** 10k 行全部 stale+dirty（计时非空转）。
- 渐进 ingest：首页恰 256 行 + 总页数 ≥3（非「能出结果即过」）。
- 泄漏断言：切换前 `totalBytes > 0` 非空转门 + 切换后 `== 0`。

## 交付物

- 代码：`App/Sources/Lightamer/Session/{SessionCoordinator,SessionLayout,SessionTreeScanner}.swift`、`LightamerCore/Sources/Session/{SQLiteHandle,SessionIndexSchema,SessionIndexStore}.swift`、`SessionState/PipeCoordinator/SidebarView/LightamerApp/FileOpenHelper` 增量、catalog +12 键
- 测试：`SessionSwitchTests`（13）+ `SessionTreeScannerTests`（13）+ `SessionIndexStoreTests`（16）= 42 新例
- 账目：本文件 + `09-01-DECISIONS.md`（12 条执行期决策）+ `.work/09/perf.md` + TODO.md Phase 9 勾选 + GOAL-STATE 增量 + LESSONS L027

## 遗留 / 风险（供 9-2/9-3/9-4 消费）

1. **GoldenColor 负载态 flake**（`testCrossConsistencySyntheticTarget`/`testNeutralPatchesSyntheticTarget`）：全量跑高负载时偶发（ColorSync 转换返回全零），隔离恒绿；02-04 台账在案，本轮三次双向归因非引入。建议后续 plan 独立归类为环境门。
2. **缩略图 LRU 缝**：9-1 以 spy 计数钉住 teardown 调用面；真 LRU + 磁盘缓存 9-3 落地后泄漏断言自动覆盖（`thumb_path` 清理缝已在 removed DELETE 路径实现）。
3. **回填同步执行**：10k 冷开卷 0.54s 含回填，9-3 若需首屏更快可将两腿解耦后台（public 独立方法已备）。
4. **watch 状态机**：`.scanning/.synced` 由 9-1 编排驱动，`.stale` 与真源接线 = 9-2（枚举与 UI 已就位）。
5. **孤儿 reconcile 动作**：9-1 只分类入表；「移除 sidecar / 忽略」两选项 = 9-2。
