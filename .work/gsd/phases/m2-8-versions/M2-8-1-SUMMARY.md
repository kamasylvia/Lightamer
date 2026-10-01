# M2-8-1 SUMMARY — 版本模型核（sidecar v7 + 链 swap + version_ref 投影激活）

> Plan 正本 = 同目录 `M2-8-1-PLAN.md`（checker 修正版 `527d4ba`）。执行 = ZCode
> subagent worker（2026-10-01）。四任务四提交 + 收口提交，**未 push**。

## 交付总览

| 任务 | 提交 | 内容 |
|---|---|---|
| T1 | `2afeb3a` | sidecar v7 additive（`schemaVersionCurrent` 6→7 + `versions`/`activeVersionID` 双可选键 + `SidecarVersionRecord` public init/`chainStack` 访问器 + `SidecarHistoryItemRecord`/`SidecarHistoryRecord` private→internal + `HistoryStack.copyingPrefixOf(_:upTo:)` public extension 落 LightamerSidecar.swift）+ SidecarV7Tests（9 法）+ DrtSidecarTests:71 pin |
| T2 | `788e1a7` | VersionCoordinator（三命令 + rename/remove + materialize-on-first-create + dangling typed degrade + KD-5 sink 壳）+ EditorState.installVersionChain（rebuild 单路径复用）+ PipeCoordinator 写腿两键/restore hydrate（E4 nil 臂清空）/versionActionDidChange 通知面 + LightamerApp 装配三角（边界增补，见偏差 §）+ VersionSwapTests（10 法） |
| T3 | `69a30ec` | LibrarySchema v2→v3（reduced DDL version_ref + 幂等 migrate slot + apply 追加 + reservedTableNames 收窄三名）+ ProjectFileStore pre-migrate 快照轮换（E2）+ `backup(from:to:)` 死参收窄 + LibraryStore.replaceVersionRefs/versionRefRow/versionRefs 读面 + VersionCoordinator.syncProjection 真调用面 + EditorWorkspaceShellView sink 装配（KD-5）+ LIB 测试群 + 版本 pin 触点穷举 |
| T4 | 本提交 | 收口（本文件 + DECISIONS + GOAL-STATE 续接点） |

## 回归实测

- **定向轮**（每任务边界）：T1 App 437/0/0（428+9）→ T2 App 447/0/0（+10）→
  T3 App **448/0/0**（+1 投影面）、Library **436/4skip/0**（+6）、Layers **298/3skip/0**（零改动域复归）。
- **全套终跑（coordinator 批准报备）**：`Scripts/test-direct.sh --all` =
  `TOTAL|2550/16/0|897s EXIT=0`。七 bundle 逐行：
  `IOP 467/1/0|6979MB · IOPParity 362/3/0|5974MB · Layers 298/3/0|1043MB ·
  Library 436/4/0|304MB · Sessions 279/4/0|1642MB · Export 260/1/0|6375MB ·
  App 448/0/0|1331MB`（sampling=time；MEMFAIL 零触发，峰值 IOP 6979MB < 8G 门）。
- **基线对账**：2525/16skip/0fail → 本 plan **+25**（APP +19 = SidecarV7Tests 9 +
  VersionSwapTests 10；LIB +6 = version_ref 翻面/迁移/链式/Store 四面拆分），
  与 BUNDLE-MAP 行（9+10+6）逐行一致；skip 数不变（16）。
- 在案 flake：无（三轮定向 + 终跑零复现失败）。

## v7 键形 JSON 样例（形状誊写；字节面由 SidecarV7Tests 三断言机检）

```jsonc
{
  "schemaVersion" : 7,                    // 原 6 位
  "appVersion" : "0.1.0",
  "imageID" : "…", "decoderVersionUsed" : "v8",
  "decodeParamsHash" : "…", "historyHash" : "…",   // UInt64-as-String 不变
  "instances" : […], "layerStack" : {…} | 缺席,
  "rating" : null, "flag" : null, "colorLabel" : null,
  "keywords" : null, "note" : null,       // v3 五键恒写
  "history" : { "items" : […], "position" : 3 },   // = ACTIVE 版本链（语义升级，拼写冻结不变）
  "versions" : [                          // 仅存在版本结构时出现（encodeIfPresent）
    { "id" : "…", "name" : "Version 1", "createdAt" : 1000.0, "updatedAt" : 1100.0,
      "chain" : { "items" : […], "position" : 1 } },          // 非活跃槽带链
    { "id" : "…", "name" : "Version 2", "createdAt" : 2000.0, "updatedAt" : 2200.0 }
    // ACTIVE 槽无 "chain" 键——items 不双写（SidecarV7Tests 全文档 "items" 计数 =1 钉死）
  ],
  "activeVersionID" : "…"                 // 与 versions[] 同批出现/缺席
}
```

三字节面实测：①v6 形文档 decode→re-encode **逐字节相等**；②v7 writer 全 nil 版本面
输出与 v6 形**只差 schemaVersion 一位**（两新键缺席）；③带版本文档 round-trip
字节忠实 + `driftDetected == false`。hash 负测：篡改 `versions[].name` →
`driftDetected == false`（版本结构结构性进不了折叠公式，行为面钉死）。

## 迁移实测（LibrarySchemaTests）

- v2→v3：手造 v2 包 → 真开（`ProjectFileStore.open`）→ `user_version==3` +
  `pre-migrate.2-3.bak` 诞生 + 旧行完好 + `version_ref` 列序对照 reduced DDL 逐列相等。
- **链式两代（E2 死锁钉死）**：v1 fixture → 首开迁 1→3（快照 1-3）→ 回拨
  user_version=2 → 重开迁 2→3（快照 2-3 轮换路径生效，两代快照共存）→ 终态 v3。
- fresh create v3 直落（version_ref 存在性 + 列序 + 索引 + CASCADE DDL +
  无 `head_commit_hash`）。

## 偏差与越界增补（3 文件，均在对应提交 body 申报）

1. **`App/Sources/Lightamer/UI/LightamerApp.swift`（T2）**：front-matter 漏列的装配点
   ——VersionCoordinator 需 root `@State` + attach 三角 + `.environment` 注入，
   否则生产路径写腿永远读 nil coordinator（版本键永不落盘）、T3 的 sink 无注入目标。
   最小半径：3 处插入（@State / attach 块 / environment 行），零既有行为改动。
2. **`Tests/LightamerTests/DrtPersistenceTests.swift`（T1）**：E3 版本 pin 第五触点
   （`:325` 字面 `== 6` → `schemaVersionCurrent`）——checker 穷举（四处）漏计的同
   类机械修复，不修则 AC「全套 0 fail」不可达。
3. **`Tests/LightamerTests/SidecarMetadataV3Tests.swift`（T3）**：E3 漏穷举的 LIB
   bundle 字节 golden 家族（`:178` 当前版本位 + `:250/:261/:265/:268` v2→v3 diff
   面字面 `"schemaVersion" : 6`）——同款改引 `schemaVersionCurrent`。

另两处行为面测试断言修正（VersionSwapTests 自身，非边界）：源版本 branch 后保留
jump 点 position（KD-2 时点语义的正确断言）；instances 投影断言改 dedup 元组计数
（recordChange 离散提交的 append 语义与 rebuild dedup 的既有差异，非本 plan 引入）。

## 执行事故（如实登记）

- **迁移测试 WAL checkpoint busy**（T3 两轮失败）：测试在 store open 期间持第二
  读连接 + statement 停在 SQLITE_ROW，`store.close()` 的强制 TRUNCATE 必 busy。
  改为 DefaultLookTests 同款「先 close 后 detached 读」形态（LibrarySchemaTests
  内注释钉明 reader rule）。非产品代码问题。

## 红线核（机检 `git diff 527d4ba..HEAD --name-only`）

- `HistoryStack.swift` / `HistoryHash.swift` **零 diff**（前缀拷贝 extension 外挂
  LightamerSidecar.swift）✓
- EditorState 的 `rebuildInstances()`/`rebuildLayerStack()` 本体零 diff（单路径
  复用证明）✓；PixelPipe/PipeCacheKey/LayerCompositeDriver 零触 ✓
- ProjectFileStore 触碰 = pre-migrate 轮换单点 + backup 签名收窄（E2 申报面）
  + 头注释同步；dispatchSchema 三路 dispatch 形状零改 ✓
- `.xmp` 零读写删；GPL 参考零接触 ✓

## 下一步

- M2-8-2（Versions 面板 UI + 历史行升级 + Copy Adjustments）——消费本 plan 的
  `VersionCoordinator`（environment 已注入）+ v7 文档面。
- 观察项（M2-8-3）：「.lra 存在∧has_edits=0」新组合的 `sidecar_present`/backfill
  下游消费面；`updateProjection` 之外的投影通道若立项应复用注入 sink 形态。
