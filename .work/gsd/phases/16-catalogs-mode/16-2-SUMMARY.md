# Plan 16-2 SUMMARY — 双模式 UI + 跨会话浏览（W2）

**执行**: 2026-09-27, executor subagent worker
**输入**: `16-2-PLAN.md` + 16-RESEARCH（§1.5 查询集 / §5 RQ-16-9..11 / §7 RQ-16-12..16）+ 16-CONTEXT（D-5/6/7 + 验证红线）
**基线**: 1482/9skip/0fail（16-1 收尾轮）→ **终轮 1504/9skip/0fail（435.3s）**，净增 22，0 fail

## 任务表

| 任务 | 内容 | commit | 测试 |
|---|---|---|---|
| T1 | CatalogPreferencesModel（开关走 Core 单键 + 位置重指向不迁移 + suite 注入缝）+ SettingsView（替换 Phase 13 占位）+ 共享运行时（sharedCatalogStore 单例 / repointSharedCatalog / countsInvalidator 装配 = 16-1 移交位兑现 / 空库 touch）+ CatalogProjector.setCountsInvalidator + CatalogIndexStore.fetchSessions + 组织模式常量/五节序常量 | `dcc97ca` | CatalogModeIsolationTests 4 |
| T2 | 组织模式轴（正交 browser-mode）+ 冷启动恒 Sessions 首帧覆盖 + 侧栏 segmented（仅启用时出现）+ Catalogs 五节（All Photographs / Categories·Collections 骨架空态 / Smart Albums 角标 + catalog 激活 / Sessions 从属节 display_name+角标+offline 灰显+锚点过滤）+ 会话管理（removeSession / relinkSession Core 写面）+ CatalogBrowserModel + CatalogBrowserView + ContentView 挂载 | `8c3a41f` | +1（五节序 + 会话锚点过滤）|
| T3 | CatalogFilterBarView（chips/Quick Filter/排序菜单的 catalog 绑定 + 3 键白名单 + startsWith 大小写敏感可见 hint）+ NULL 尾段边界播种修复（D8） | `cfa5e0a` | CatalogBrowserModelTests 7（10k fixture 六形状 drain==one-shot 逐 identity + chips 相等 + 大小写敏感 + 排序切换重置 + end sticky + 页序）|
| T4 | SmartAlbumStore.evaluate domain 分派（.session = 12-2 面逐字回归锁 / .catalog = keyset filename 全库走查 + EXISTS keywords）+ offline 行完整性决策钉 + 规则文件零迁移断言 | `e7f61ad` | CatalogSmartAlbumDomainTests 4 |
| T5 | CatalogThumbnailRouter（惰性 provider 池 + 真开卷流程 + 内存键 session 命名空间化[D2] + offline 零请求 + teardown 生命周期）+ provider additive memoryKeyPrefix + cell 路由取图 + 离线灰显（0.35 透明 + wifi.slash） | `53926ec` | CatalogThumbnailRouterTests 3 |
| T6 | 编辑回环（catalogEditReturnRoot + 返回网格投影钩子 + refreshAfterProjection 水位追平）+ 跨会话批量评分/flag/色标（按 session 分组走 MetadataService 三段零改 + flush 先于关柄 + 逐会话投影追平）+ 进 Catalogs 后台 sweep + batch context menu + router.shared/invalidateRoots + decodeLeg 测试缝 | `13da53e` | +1（lindex 变更→project→refresh 链；累计 8）|
| T7 | 双模式隔离终段（Sessions 全流程零句柄经模型开关重驱动）+ L025（16-2 键族 en+zh translated 非空全量断言，键数 972）+ 全套回归 + 本文档 + DECISIONS + TODO/PROGRESS | 本提交 | CatalogModeIsolationTests 累计 7 |

（每任务边界查 `.work/config.toml [gsd]` auto=true/paused=false ×7；**不 push ✓**；新文件后 `tuist generate` ×3；构建 `caffeinate -dis` 包裹，测试全部走 `Scripts/test-direct.sh` 判据 = Executed 行）

## 回归终轮口径

- `caffeinate -dis ./Scripts/test-direct.sh` 全套：**Executed 1504 tests, with 9 tests skipped and 0 failures (435.284s)**，EXIT=0（真实输出 /tmp/la-full-suite-162.log）。
- 1482 基线 + 22 新增 = 1504；9 skip 不变（harness 三测门控 + 既有 6）；**零失败、零 flake 单列项**（本轮未现 ToneEqualPerf/GUI22/TilingOverlap 负载敏感失败）。
- 新增分布：CatalogModeIsolationTests +7 / CatalogBrowserModelTests +8 / CatalogSmartAlbumDomainTests +4 / CatalogThumbnailRouterTests +3。

## AC 自检（逐条）

- ✅ **未启用零 .lcat 句柄隔离**：模型 setEnabled(false) → openAndSync 全流程（真 scanner）成功且无 `.lcat` 文件（testSessionsModeFullFlowCreatesNoCatalogFile）+ GUI 冒烟截图（无切换器/无 Catalogs 节，/tmp/la-smoke-1.png）。
- ✅ **冷启动恒 Sessions**：常量钉（testColdStartOrganizationModeIsSessions）+ onAppear 首帧覆盖 + GUI 冒烟（启用后首帧选中「会话」，/tmp/la-smoke-2.png）。
- ✅ **切换器出现 + 五节序**：`CatalogSidebarSection.allCases` 钉 + GUI 冒烟（切换器出现）。
- ✅ **keyset 滚动无重无漏**：10k fixture × 6 形状（date/rating/filename × 双向）drain == one-shot 参照逐 identity 相等 + Set 无重 + NULL 尾段 == 层集合（CatalogBrowserModelTests）。
- ✅ **filter bar 全套 + startsWith 提示**：chips 组合 == store 直查；Quick Filter 'Apple' 只中 Apple.arw；hint 行可见（catalog_filter_quick_hint）。
- ✅ **SmartAlbums 域随模式零迁移**：session 域 == 12-2 面逐字；catalog 域跨会话 + EXISTS；规则文件字节不变 + schemaVersion 1。
- ✅ **provider 池 384MB 复用断言**：两会话同池单实例（memory.count==2 两键）+ 各自生产一次 + 重复取图内存命中（D2 命名空间化语义，见 DECISIONS D2）。
- ✅ **编辑回环 + re-link/移除**：lindex 变更→project→refreshAfterProjection→行值追平（testEditProjectionRefreshChainUpdatesRows）；removeSession 单事务清行集+tags+组织归属；relinkSession root_path UPDATE+offline 清+立即重投影同 id（16-1 探针延续 + T2/T4 测试）；交互走查登记 Manual-Only。

## 缝 a grep 自证（收尾轮）

```
$ grep -rn "SELECT\|WHERE" App/Sources/Lightamer/Catalog/
（零命中，exit 1）
```

辅证：`grep -rln "CREATE TABLE|CREATE INDEX|PRAGMA" App/Sources/Lightamer/` 零命中；`grep -rln "sqlite3_[a-z_]*(" App/Sources/Lightamer/` 零命中。缝 b/缝 c 在 App 层成立（Core 侧 16-1 三缝审计口径不变，本轮 Core 增补均走 CatalogIndexStore/CatalogProjector/FilterSQL 既定缝）。

## GUI 冒烟（执行器本机，控制台已解锁）

1. 禁用态冷启动：无切换器、无 Catalogs 节、Sessions 侧栏原样（截图 /tmp/la-smoke-1.png）。
2. `catalogs.enabled=true` 后冷启动：切换器出现、选中「会话」（恒默认）；Sessions 侧栏零变化（/tmp/la-smoke-2.png）。
3. 冒烟后清理：恢复默认键 + 删除冒烟产生的空 `catalog.lcat/-shm/-wal`（无用户数据）。

## Manual-Only 台账（交互走查未竟项，验收轮承接）

| # | 项 | 原因 |
|---|---|---|
| MO-16-2-1 | 设置面板交互走查（开关开合联动切换器出现/消失；NSOpenPanel 位置更改→新路径空库） | 需人工面板操作 |
| MO-16-2-2 | 切换器点按往返（Sessions⇄Catalogs）+ 五节视觉序 + All Photographs 空态「打开会话以入册」文案 | 需人工点按走查 |
| MO-16-2-3 | 跨会话网格渲染走查（真实多会话库缩略图/点开编辑/返回网格数字已更新/stale 再生/离线灰显） | 需真实 RAW 会话库 |
| MO-16-2-4 | 会话管理全流程（移除 confirm 文案→行集消失；re-link 选新目录→行恢复） | 需人工面板操作 |
| MO-16-2-5 | 批量多选跨两会话评分/flag/色标生效 + filter bar chips/Quick Filter/排序手感 | 需人工点按走查 |

## 偏离/决策

15 条入 `16-2-DECISIONS.md`。要点：**D2** 内存键按 session 命名空间化（对 plan T5「同 hash 图内存命中复用」断言的正确性修正——同 relPath 跨会话是不同文件，盲复用会串图；共享池/预算目标以单实例 + 键空间隔离达成）；**D5** Core 面增补六处（fetchSessions/isDefault public/removeSession/relinkSession/setCountsInvalidator/SmartAlbumStore.evaluate——UI 消费面只能落 Core 既定缝，缝 a 禁 App SQL）；**D8** NULL 尾段边界播种（主段页末 NULL 键行 → 尾锚点播种防重发，10k 套件抓住）；**D11** CatalogFilterBarView 独立面（不动 12-2 交付面）。

## 遗留

- 无阻塞。Manual-Only 五行（上表）待验收轮交互走查。
- 16-3 接线位就绪：侧栏 Categories/Collections 骨架空态 + FilterScope.categoryID/collectionID 锚点参数位 + 批量归类复用批量面形状。
- 16-4 输入就绪：SC#3 终测按 16-1 harness 复跑；双模式隔离终验可复用 CatalogModeIsolationTests 语境。
