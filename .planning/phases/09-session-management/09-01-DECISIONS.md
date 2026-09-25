# Plan 09-01 执行期决策（09-01-DECISIONS.md）

> 执行期决策按 plan 纪律入本文件（RESEARCH 未覆盖的实现细节，不臆造）。
> D-09-CONTEXT-1..7 全按 planner 推荐落定，不在此重复；本文件只记**实现形态**层决策。

## D-09-01-T1-1: recent 行 identifier 用 pathhash（plan 字面 `<uuid>` 的落地修正）

- **决策**：`SidebarView` recent 行 identifier = `session.row.<FNV-1a decimal pathhash>`（`StableHash.hash(url.path)`），非字面 `session.row.<uuid>`。
- **理由**：recent 列表是 `UserDefaults` 存的 `[URL]`，天然无 UUID；hash 十进制串跨重启稳定、与路径一一对应，满足 L010「稳定 id 禁索引」的全部实质（不本地化、不随数组序漂移）。
- **影响**：UITest/单测按路径即可预测 id；9-3 grid 行 `browser.cell.<pathhash>` 同构。

## D-09-01-T1-2: SessionCoordinator 的 appState 为 post-init 注入属性

- **决策**：`SessionCoordinator.appState: SessionState?` 为 var，app root 在 `.task` 经 `configure(...)` 接线（同 `AppDelegate.openHandler` 闭包后置模式）；`SessionState` 的四个写入口（setCurrentSession/setWatchStatus/setBrowseCounts/promoteRecent）是 coordinator 仅有的写面。
- **理由**：D-03b 禁止 state 对象互相持有；coordinator 构造时 state 尚未成对存在。测试注入在 init（闭包全可注入）。

## D-09-01-T1-3: 会话打开后路由首图进编辑器（同一 `EditorState.load` 路径）

- **决策**：`openSession` ④④ 完成后，若 sync 返回首图（字典序第一张可浏览图）则经注入闭包路由进 `EditorState.load`。
- **理由**：9-1 无 grid；不路由则切换会话后单窗口仍显示上一会话的图（跨会话陈旧帧，比「无 grid」更糟）。路由走既有加载路径即天然 L012 合规；9-3 grid 接管后此行为自然退化。
- **顺带钉死**：单开恰 1 次 route（`testOpenRoutesFirstImageOnce`）；L012 窗口探针 = 3 开 0 新窗 0 新 MTKView（单测形态）+ AppLaunchTests（UITest 场景级）。

## D-09-01-T1-4: ensureDirectories 失败 = 完全解绑

- **决策**：③ 目录创建失败时 `setCurrentSession(nil)` + watch 复位 `.notWatching` + toast（`toast_session_open_failed`），不落半开状态；同步/晋升步骤全部跳过。
- **理由**：半绑定的会话（URL 已设但目录集缺失）会让后续浏览/导出语义悬空；「打开失败 = 一切如初 + 明确报错」可测试且无歧义。

## D-09-01-T3-1: 扫描期扩展名过滤清单（静态集，执行期决策）

- **决策**：`SessionTreeScanner.rawExtensions` = arw/cr2/cr3/nef/nrw/raf/rw2/orf/pef/srw/dng/rwl/3fr/fff/iiq/x3f；`rasterExtensions` = jpg/jpeg/tif/tiff/heic/png/webp。匹配大小写不敏感，仅按扩展名。
- **理由**：扫描期逐文件 UTI 解析（10k 次 `CGImageSourceGetType`）代价不可接受；扩展名集镜像 `RAWDecoder.rawUTIs` 已验证的 UTI 面 + raster 路径兜底。**解码期路由仍走真 UTI 判定**（RAWDecoder 不变）——扩展名只决定「是否入浏览集」，误入的文件解码失败按既有 typed error 呈现，不污染浏览集语义。`nrw`（Nikon 别名）与 `fff`（Hasselblad 别名）为保守补充。

## D-09-01-T3-2: `*.tmp-*` 匹配 = 路径段含 `.tmp-` 子串

- **决策**：`isExcludedFile` 用 `name.contains(".tmp-")` 而非 glob 引擎。
- **理由**：Foundation 无 glob；`contains` 覆盖 SidecarStore 残留（`.DSC.ARW.lra.tmp-<uuid>`，dotfile 规则本已双保险）与无点变体。副作用：合法文件名含 `.tmp-` 会被排除（如 `vacation.tmp-backup.jpg`）——概率与代价都远低于漏排除残留物，测试向量化钉死。

## D-09-01-T4-1: SQLite 绑定形态与错误面

- **决策**：`SQLiteHandle`（final class，非 actor，由 Store actor 独占）+ `SQLiteStatement`（prepare/bind/step/finalize；1-based bind、0-based column；deinit finalize）。错误面 `SessionIndexError` 三分：`openFailed`/`schemaFailed`/`execFailed`（各带 code+message；execFailed 带 offending SQL）。`SQLITE_TRANSIENT` 绑定（Swift 侧字符串可先行释放）。每连接 `sqlite3_busy_timeout(5000)`。
- **理由**：薄封装 ~200 行换零依赖（D-09-CONTEXT-1）；busy_timeout 是多连接 WAL（切换 close→reopen 竞态、崩溃恢复腿）的防瞬发 SQLITE_BUSY 底线。

## D-09-01-T4-2: schema v1 冻结拼写（25 列，顺序即契约）

- **决策**：`images` 列序 = `path(TEXT PK), dir, filename, file_size, file_mtime, scan_epoch, imageID, sidecar_present, sidecar_mtime, has_edits, params_hash(TEXT), layer_count, layer_summary, orientation, width, height, capture_date, thumb_state, thumb_path, thumb_params_hash(TEXT), rating, color_label, keywords, orphan_sidecar, dirty(INTEGER DEFAULT 0)` + `meta(key,value)` + `idx_images_dir(dir)`。`meta.schemaVersion` 无则直建 v1，>1 拒开（v1 二进制不猜未来 schema），<1 不存在（无历史版本）。
- **冻结证据**：`testSchemaV1FrozenColumnSpelling` 逐列 name+type 对照 `SessionIndexSchema.imagesColumns` + L013 双哈希列 TEXT 断言 + PK + 索引 + WAL/synchronous(NORMAL) pragma。

## D-09-01-T4-3: 孤儿 sidecar 行 = 以 `.lra` relPath 为键的同表行（orphan_sidecar=1）

- **决策**：孤儿不进旁表也不弃录——`images` 表插一行 `path = <lra relPath>`、`orphan_sidecar=1`、图像列 NULL。scan 的孤儿集与 DB 孤儿行同事务 diff（resolved → 删行）。
- **理由**：9-2 reconcile 需要 DB 侧可查询的孤儿清单；同表单查询面（counts 的 total 排除孤儿）最简。**永不硬失败**：`.lra` 存在原片缺失只分类不动作。

## D-09-01-T5-1: 回填两腿在 openSession 内同步执行

- **决策**：sidecar 摘要回填 + EXIF 轻量列在 `openSession` 内、sync 事务后同步跑（非 fire-and-forget 后台）。
- **理由**：侧栏 counts 的 `edited` 需要回填后的 `has_edits`；同步执行让「开卷完成 = 数据完整」可测试。10k 实测冷开卷 0.47–0.54s（含回填），远在预算内；9-3 若需要首屏更快再解耦为后台（缝已在：两方法独立 public）。

## D-09-01-T5-2: sidecar 漂移检测 = sidecar_mtime 比对（回填第二 pending 类）

- **决策**：回填 pending 集 = ①摘要列 NULL 的行（新增/漂移清除/降级重试）∪ ②sidecar_present=1 且磁盘 `.lra` 当前 mtime ≠ 行 `sidecar_mtime` 的行。解码失败 = 降级：行留 NULL 类（下次开卷自动重试），仅 log 不硬失败。
- **理由**：sync 的 diff 是**原片 stat** 驱动——原片不动而 sidecar 被外部改写（真身！）时必须重读，否则索引陈旧违反「真身恒 sidecar」。
- **补充**：degraded 行无独立列（schema 冻结不加）——NULL 类即降级标记 + 重试队列，一列两用。

## D-09-01-T5-3: layer_summary JSON 拼写冻结

- **决策**：`[{"blend":Int,"name":String,"visible":Bool}]`，`JSONEncoder` + `.sortedKeys`（无 pretty）。
- **理由**：plan 要求「名/混合/可见性」三要素；sortedKeys 保证同栈同串（parity 重建一致性的前提，`testDeleteAndRebuildParityColumnByColumn` 逐列钉住）。

## D-09-01-T7-1: EXIF capture_date 解析 = `yyyy:MM:dd HH:mm:ss` 严格 UTC 钉

- **决策**：`DateFormatter`（en_US_POSIX + UTC）严格解析 EXIF DateTimeOriginal；TIFF DateTime 兜底；解析失败 capture_date = NULL。
- **理由**：EXIF 无时区语义，钉 UTC 保证同一文件跨机器/跨时区解析值一致（parity 与确定性优先于本地时区直觉）。

## D-09-01-T7-2: L012 单测探针形态

- **决策**：单测断言 3 次开卷 NSApp.windows 计数 delta == 0 且 MTKView 实例数 delta == 0 + route 闭包 3 次触发（非空转锚）；场景级单窗证明仍由 AppLaunchTests（UITest）承担。
- **理由**：单测进程内 SwiftUI scene 的窗口由宿主管理，创建 MTKView 需真实加载腿——单测形态只可能断言「会话编排零窗口副作用」，两个层级合起来才是完整 L012 回归。
