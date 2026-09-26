# Plan 12-1 SUMMARY — 元数据依赖根（W1）

> **终轮全 suite：1290 tests / 6 skip / 0 fail**（touch 重编复跑，426.4s；基线 1260 → 1290，净增 30）。
> 六任务六提交（`8f1a96a` / `db105ee` / `4b906b6` / `e0ce1ed` / `0ad5c96` / `a7f44b7` + T7 收尾本提交），未 push。
> 每任务边界查 `.work/config.toml [gsd]`（auto=true / paused=false 全程）。

## 任务表

| 任务 | 内容 | commit | 证据 |
|---|---|---|---|
| T1 | sidecar v3 五字段（rating/flag/colorLabel/keywords/note；decodeIfPresent + encode 恒写 null；哈希隔离） | `8f1a96a` | SidecarMetadataV3Tests 9 绿（v2 降级读/显式 null 混合/v4 容忍/恒写 golden/哈希逐字节不变 ×2/加键 diff/0-vs-nil round-trip）+ Phase6 2 处版本钉随 current 常量 |
| T2 | DB v2 首迁移 25→34 列（migrate 表驱动逐列幂等 + apply dispatch + v99/unparsable 拒开） | `db105ee` | SessionIndexMigrationTests 8 绿（旧行逐列字节不变/新列 NULL/幂等/重置 stamp 重迁/中迁失败 ROLLBACK 回 25 列/只读拒开字节不动/v99 数据级保全/删库重建 parity 34 列）+ SessionIndexStoreTests 冻结断言 34 列 16 绿 |
| T3 | Store additive：claimMetadataApply 新缝（F6 SQL verbatim）+ heal/summary UPDATE 扩五列（F7）+ changed-leg 清五列 + Row 扩九列（fetch 单拼写收敛） | `4b906b6` | 回归 16+8+3 绿；claim/heal/summary 值级断言落 MetadataServiceTests 前置段（T4 提交） |
| T4 | MetadataService 三段写面（六 API + `|` typed 拒绝 + pristine mint + 不可读 skip）+ 万张门 + crash 注入 | `e0ce1ed` | MetadataServiceTests 10 绿；**META12-GATE 10k 段1+段2 = 0.457s（Debug/SSD；≤5s Release 门余量 ~11×）** → `.work/12/perf.md`；crash 注入：written 行保新值、unwritten 行 heal 回旧值、全行 dirty=0 且 index==磁盘真身（三态漂移零发生） |
| T5 | EXIF 七列回填（单锚谓词 `camera_make IS NULL` + 文本 '' 哨兵/数值 NULL + 七列同批） | `0ad5c96` | 迁移测试 +3 → 11 绿（真 JPEG 七列精确值 L020 + 直调二扫 0 行恰扫一次 + v1 形态行单轮收编 orientation 存活） |
| T6 | UI 接线：overlay 实星/色点/flag 徽章 + 全域快捷键（0-5/X/P/⌘0-6）+ Inspector keywords/note 行 + 多选追加菜单 + zh catalog 29 键 | `a7f44b7` | GUI 走查 6 证据 `.work/gui-acceptance/12-1-*.png`（详见下）；lproj smoke zh/en 829/829 |
| T7 | 全量回归 1290/6/0 + SUMMARY + DECISIONS + TODO 开账 + PROGRESS.log | 本提交 | 本文件 + DECISIONS + TODO Phase 12 节 |

## AC 自检（plan 验收标准逐条）

- [x] **sidecar v3**：五字段 additive（decodeIfPresent + encode 恒写含 null，golden 锁定五键行 + 顶层键集 + 双 encode 字节稳定）；init 默认参数零调用点改动；五字段写后 historyHash/paramsHash 逐字节不变（`testMetadataWriteKeepsHashesByteIdentical` + 投影重算 `testHistoryHashProjectionIgnoresMetadata`）；v2 降级读 + `>3` 容忍（v4 文档 decode）
- [x] **DB v2**：34 列冻结（列序钉死 = imagesColumns）+ 幂等迁移（逐列 skip + 重置 stamp 重迁零害）+ v99 拒开保留 + 迁移失败不破坏原库（中迁失败 ROLLBACK 回 25 列 + 只读拒开字节不动）+ 删库重建 parity 扩 v2 全列（34 列 compared >90 断言）+ PRAGMA VERBATIM 断言更新；不建新索引（DECISIONS D4）
- [x] **claimMetadataApply 新缝**：不复用 claimBatchApply（SQL 常量文本断言 SET 列集 = 五列+sidecar_mtime+dirty，无 thumb_state/params_hash/has_edits/layer 系；功能断言 rendered-thumb 行 claim 后 thumb_state/params_hash 不变）；healDirtyRows/backfillSidecarSummaries additive 扩五列（签名不变）；crash 窗口三态漂移零发生（注入测试：index==磁盘真身逐行断言）
- [x] **MetadataService 唯一写入口**：六 API（GUI/未来 MCP 同源，GUI 侧经 MetadataController 全路由）；`|` 录入 typed 拒绝（setKeywords/appendKeywords 双入口 + 拒绝后字节不变断言）；万张 setRating 段1+段2 = **0.457s** 入 perf.md + thumb_state/params_hash 逐行不变断言
- [x] **EXIF 七列回填**：单锚谓词（plan 定死形态）+ 无 EXIF 单次哨兵（直调二扫返回 0）+ 值精确断言（真 JPEG 七列 L020）
- [x] **GUI**：overlay 实星/色点/flag badge + 三态快捷键（0-5/X/P/⌘0-6）+ note 录入位 + keywords 编辑行 + zh catalog；Manual-Only 3 行登记（下表）
- [x] **全 suite 0 fail**（1290/6/0）；每任务独立提交 + 边界查 config 开关 ×6；不 push；无 /tmp 产物入工作区（fixture 全部临时目录 + 探针即弃）；SUMMARY + DECISIONS 落盘

## GUI 走查记录（控制台解锁，2026-09-26 14:2x-14:5x）

真实 app + 真会话（/tmp/la12-session 三 JPEG）+ AX/键盘驱动；六张证据归档 `.work/gui-acceptance/12-1-*.png`：

1. **12-1-01-open**：zh 首屏全量中文渲染（L025 smoke）+ 菜单栏新「标记」菜单出现
2. **12-1-04-rating3**：网格选中 img0 按「3」→ overlay 3 颗实星即时点亮；DB rating=3 dirty=0；sidecar `img0.jpg.lra` 落盘（v3 五键全在，history 空 = 零 history 项）
3. **12-1-05-flag-color**：X → 红色 X 徽章即时出现；⌘4 → 绿色色点即时出现（⌘4→色标3=绿 与菜单标签一致）；DB flag=2/color_label=3；sidecar rating/flag/colorLabel 三字段同值、`driftDetected` 面（history/paramsHash）未动
4. **12-1-07-single**：单图态无选区按「4」→ 当前图路由（img0 rating=4）——三态路由的 single 分支实证；Inspector 底部 keywords/note 两行可见
5. **12-1-10**：keywords 编辑行聚焦态（IME 候选弹出即输入可达证明）
6. **12-1-12-grid-reopen**：**退出重开**后网格 img0 四颗实星保持（sidecar 真身回读）；DB keywords/note 与 sidecar 全等

**服务面语义走查实证**（键盘 + 剪贴板 + AX）：keywords 整组替换两轮（逗号拆分 → sidecar 数组 → DB `|` 物化）；note 追加落 sidecar；P 双击 toggle 回未标记；0/⌘0 清除评分/色标。

### Manual-Only 登记（AX 合成驱动限制，人工确认项）

| # | 项 | 说明 | 覆盖状态 |
|---|---|---|---|
| F-12-1-1 | ⇧ 多选批量打分的 GUI 合成 | System Events 合成 click 不携 shift 修饰键进 SwiftUI tap 手势（`NSEvent.modifierFlags` 读不到）；批量语义（多 relPath 一次调用）已由 MetadataServiceTests 多目标用例钉死 | 服务面 ✅ / 手势合成待人工 |
| F-12-1-2 | 网格右键「追加关键词/备注」alert 流 | SwiftUI contextMenu 对 AXShowMenu 不可达；同源服务面（appendKeywords/appendNote）已由编辑行 + 单测实证 | 服务面 ✅ / 菜单交互待人工 |
| F-12-1-3 | 对比（culling）态快捷键 | culling 分支与 grid 共用 browserModel 选区数据面 + 同一 MetadataController 路由（代码面同路径）；合成键盘无法稳定到达 culling 双格选中态 | 代码面同路径 / 双格观感待人工 |

## 基线演变

1260（Phase 11 收口）→ **1290**（+30：SidecarMetadataV3Tests 9 + SessionIndexMigrationTests 11【含 T5 EXIF 3】+ MetadataServiceTests 10）；6 skip 不变；0 fail。终轮 426.4s（touch 重编复跑）。

## 偏离与注记

1. commit `e0ce1ed` body 中 perf 路径笔误 `.worl/12/perf.md`（实为 `.work/12/perf.md`）——cosmetic，历史不重写，DECISIONS D12 在案。
2. 万张门数字为 Debug harness 记录值（0.457s；≤5s 门语义 = Release/SSD，Perf07 同口径）；Debug 已余量 ~11×，Release 只会更快。
3. SessionIndexStore.swift 的 fetch 全行查询收敛为共享拼写（rowSelectColumns + readRow）——九列 additive 的防漂移收敛，行为等价（16/16 回归）。
