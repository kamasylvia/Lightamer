# Phase 12 计量记录（.work/12/perf.md）

> 记录约定继承 `.work/09/perf.md`：门数字在内置 SSD 上测得（fixture 位于
> `FileManager.temporaryDirectory`，L009——UNITEK USB 卷禁跑门）；执行环境 macOS 27.0 /
> M4（LaniakeadeMac-mini）、**Debug 构建**（`Scripts/test-direct.sh` 直启宿主）。
> 口径照 Phase 11：**只记不设门**——plan 12-1 的 ≤5s 语义为 RELEASE/SSD 门，Debug
> harness 数字为记录值（Debug 付未优化 JSON decode），防退化用宽松 sanity ceiling。

## 12-1 万张元数据写计量门（T4）

| 项 | 口径 | 数字 | 判定 |
|---|---|---|---|
| `setRating` 万张 段1+段2（内存 compose + 单事务 claim，writer=nil 门形态） | SSD 临时目录 fixture（Perf07 同款：10k 原 8-byte 占位 + 真 `.lra` JSON）、Debug、`testTenThousandSetRatingSegmentsOneAndTwoGate` | **0.457s** | **≤5s 门达成**（Debug 已余量 ~11×；Release 只会更快） |
| 同轮 D-8 红线断言 | 10k 行 `thumb_state`/`thumb_params_hash`/`params_hash`/`has_edits` 逐行 before/after 相等 + 逐行 rating==3 + dirty==1（writer nil 诚实挂起） | 全绿 | 评分零缩略图再生、零参数身份翻转（万张打分 ≠ 万次重渲） |

- 打印锚：`META12-GATE setRating segments1+2 10k: <s>s (gate ≤ 5.000s)` +
  `META12-GATE-CONFIG: Debug|Release`（`Tests/LightamerTests/MetadataServiceTests.swift`）。
- 与 PERF-07（9-4 参数批量 0.419–0.490s Release）同量级：元数据段1 少一次
  `PasteSemantics.paste` 合成、段2 列集更窄（五列 + mtime + dirty vs params/has_edits/
  layer/thumb 五处），形态同（PK-seek 逐行 + 单事务）。
- crash 注入一致性（F6）与 heal 回填为正确性测试（`testCrashBetweenClaimAndWriteHealsToOldValues`），
  不涉计量；段3 落盘吞吐不重复计量（复用 9-4 `BatchSidecarWriter`，PERF07-SEGMENT3 账在
  `.work/09/perf.md` ⑥）。
