# Plan 09-03 — SUMMARY(浏览模式三态 + 双档缩略图管线 + PERF-06 基线)

**执行**:ZCode subagent worker(2026-09-25 夜间);8 commits(未 push)。
**终轮全 suite:1097 tests / 6 skip / 0 fail**(基线 1054 → 1097,净增 43;
CullingPipeline 5 + ThumbnailMemoryCache 7 + SessionThumbnailProvider 16 +
SessionBrowserModel 11 + MemoryBudget 扩 1 + 渐进时序等)。每任务边界
`.work/config.toml [gsd]` 开关检查(auto=true / paused=false 全程)。

## 任务完成表

| T | 内容 | commit | 验证 |
|---|---|---|---|
| T1 | 行模型(SessionBrowserModel:投影/⌘⇧多选/渐进占位)+ ThumbnailMemoryCache LRU + ThumbnailPath | `feat(session): browser row model + thumbnail memory LRU` | LRU 7 tests(逐出序列精确到字节);model 10→11 tests;session 族回归 0 fail |
| T2 | ThumbnailDiskStore(`.lightamer/thumbs/<pathhash>.jpg`)+ 行绑定腿(updateThumbnailRecord)+ 9-1 removed 腿挂接 | `feat(session): thumbnail disk store + index row binding leg` | 4 tests(有损域 round-trip D6/stale hash 翻转/删行清 thumb);IndexStore 16 回归 |
| T3 | SessionThumbnailProvider:双档判定(has_edits 红线)+ 档 A ImageIO(10.9ms)+ 回落缝 + tier B 材料化 | `feat(session): double-tier thumbnail provider — tier A` | +4(tier 判定真值表/真 RAW 档 A/pristine 禁走 B 反向断言/无嵌入回落) |
| T4 | 档 B 真渲染(RenderPipeline @ THUMBNAIL 360)+ 后台队列(并发2/可见优先/空闲/cancelAll)+ memory stale 感知 + 隔离(严格 grep 零命中) | `feat(session): tier B real pipe render + background queue + isolation` | 14 tests(真渲染 round-trip/隔离 totalBytes 恒等/并发=2/可见插队/cancel) |
| T5 | 三态 segmented + SessionBrowserView(cell 四件/多选/菜单 stub/双击链)+ culling 形状 + wiring(渐进观察者/teardown②接真)+ catalog 10 键 | `feat(ui): three-mode browse switch + grid view` | model 11 tests(渐进时序:首屏早于全扫);PanelWiring 71 + Switch 13 回归 |
| T6 | CullingView 子管线(独立 decode+1480 rung+自持 cache、错峰、cap 2、释放账本) | `feat(ui): culling sub-pipelines` | CullingPipelineTests 5(逐字节隔离/cap 拒第 3/孤儿不配对/释放归零/预算面) |
| T7 | 一致性(A→B 升级只在编辑)+ 真样张抽检(D10) + **转换腿双域修复**(bgra8/float32) | `test(session): double-tier consistency + real-sample spot check` | 16/0;归档 09-3-tiers-{arw,nef,raf}-A-vs-B.jpg |
| T8 | PERF-06 基线(perf.md 09-3 节)+ culling 内存断言(MemoryBudgetTests 扩 case) | `test(perf): PERF-06 baseline ledger` | 档 A 10.6ms/档 B 2.87s/10k reload 26ms/culling 双100MP 2.9s;MemoryBudget 13 |
| T9 | GUI 验收轮 + 全量回归 + SUMMARY | 本 commit | FINDINGS 09-3 节 + Manual-Only 表;GUI-19 修复;全 suite 0 fail |

## 验收标准对照(PLAN 验收标准)

- ✅ 三模式:grid(LazyVGrid+渐进 ingest+cell 四件+E 徽章+rating overlay 布局+多选/右键菜单 stub)/单图(既有链)/culling(独立子管线+错峰+cap 2+关闭释放)
- ✅ 双档管线:判定只看 has_edits(反向断言:pristine 禁走 B、编辑只升级该图)+ 档 A 秒开(10.6ms)+ 档 B LAZY 一次 + stale 再生 hash 翻转 + **PipeCache 隔离常驻断言**(grep 严格零命中 + totalBytes 恒等)
- ✅ 缓存:磁盘 round-trip(有损域 D4)+ LRU 逐出精确到字节 + 删行清 thumb 文件
- ✅ 后台队列:并发 2 + 可见优先 + 空闲调度 + 会话切换全 cancel(teardown ②接真,cancelAll+LRU drain)
- ✅ Phase 8 契约:档 B 走同一 driver;coordinator 的 terminalTailFloor/injectYiyinRunContext **零改动**(git diff 佐证)
- ✅ 双档观感抽检:D10「可辨」落 DECISIONS(退路否决 + 证据链);截图归档
- ✅ PERF-06 基线:perf.md 09-3 节(Debug 分栏;Release 复核挂 Phase 15 注记)
- ✅ GUI 验收轮:PLAYBOOK 走查 + 量化 + zh 首屏 + `ls *.lproj` smoke + Manual-Only 表;L010 identifier 全量(`browser.mode.*`/`browser.cell.<pathhash>`/cell 四件/culling pane);L025 zh 标签
- ✅ 全 suite 0 fail;每任务独立提交;SUMMARY/DECISIONS 落盘

## 关键实现事实(下游必读)

- **隔离红线形态**:`grep -rn PipeCache LightamerCore/Sources/Session App/Sources/Lightamer/Session` = **0 命中**——provider 用注入腿(`ThumbnailRenderLeg`/`ThumbnailDecodeLeg`/`ThumbnailRunContextInjector`),GPU 腿唯一合法持有点 = `App/Sources/Lightamer/State/SessionThumbnailRenderer.swift`(throwaway per-run cache)。
- **memory stale 感知**:memory 命中后仍做一次行级重检(stale 或 hash 漂移 → 失效重产)——编辑/批量 apply 后 grid 缩略图自动刷新(9-4 的 stale 再生直接受益)。
- **队列任务 execute 时重读行**:等待中的 job 用权威行判定档位(等待期间编辑不产陈旧图)。
- **teardown ② 已接真**:cancelThumbnailTasks 闭包 = `provider.cancelAll()`(generation 门)+ `memory.removeAll()`;SessionSwitchTests 泄漏断言面现成。
- **渐进 ingest 缝**:`SessionIndexController.scanPageObserver`(页先于事务)+ `currentStore`;grid 用 `reload(includeOrphans: true)`(孤儿 = 占位 cell + 徽章,不产缩略图)。
- **culling pane 渲染 pristine display 链**(registry 默认 trio;编辑对比 = 9-4 before/after 平面复用同形状)。

## 遗留与风险

1. **双档混排观感(D10 残差)**:edited(管线域)/pristine(相机域)缩略图在 grid 混排可辨;Phase 3+ 色彩 iop 校准后自动收敛,抽检测试常驻复核。Manual-Only 挂人工。
2. **Release 计量**:PERF-06 数字为 Debug;Release 复核随 Phase 15 门清算(test-direct.sh 为 Debug 产物锚定)。
3. **10k 大集合滚动 hitch signpost**:结构面就绪(10k reload 26ms),真机大集合滚动走查挂 Phase 15(本轮 fixture 4 图,Manual-Only 登记)。
4. **zh-Hans.lproj 空目录**(dgzsvdww 产物,历史遗留):无表不破坏回退(本轮 zh 渲染正常),建议清理防误判。
5. **GUI 内 toast 卡片(「Pasted text.txt」残留)坐标点击不响应**:输入法误输入产物,AX 层不可达——不挡功能(重启消失);D-26 toast 交互语义留观察。
6. **paste/flag 菜单为禁用 stub**(9-4 数据面);**rating overlay 布局不接数据**(Phase 12)——均为 plan 内占位。
