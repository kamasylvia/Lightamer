# M2-8-3 DECISIONS — 收口（zh 对账 + 观察项三查 + 翻账）

> Plan 正本 = 同目录 `M2-8-3-PLAN.md`（checker 修正版）。执行 = ZCode subagent
> worker（2026-10-01/02 夜间，`[gsd] paused=false / auto=true`）。本文签注
> plan 期预埋的裁决点 + 执行期新增裁决 + checker M5 勘误对账。

## 1. zh-audit 对账（KD-1：工具 PASS 为门，对账表）

### 1.1 工具判定（本波亲跑）

```
uv run python3 Scripts/zh-audit.py --check
→ zh-audit --check PASS (1362 source keys, 1588 catalog keys, zh complete, locale codes = {en, zh})
EXIT=0
```

**`Resources/Localizable.xcstrings` 零补行**——M2-8-2 批的「zh 键随手落」载体
已把 42 新键 + 孤儿键删除全部落盘，本波对账为纯核验（无 xcstrings diff）。

### 1.2 对账表：预估 40–60（OQ-12-A）vs 实数 42

| 分族 | 键数 | 键清单 |
|---|---|---|
| T1 Versions 面板（`c5e1ea7`） | 15 | `versions_default_name`、`versions_panel_default/new/branch/empty/empty_implicit/active/rename/rename_field/remove/remove_title/remove_title_slot/remove_confirm/remove_button/cancel` |
| T2 历史行（`161a773`） | 4 | `history_row_kind_global/structure/paste/drt` |
| T3 Copy Adjustments（`56360ee`） | 22 | `menu_copy_adjustments_dialog`、`history_drt_paste`、`transfer_title/source_label/source_current/source_external/source_active/node_title/node_count/node_empty/item_title/item_empty/item_excluded/version_title/version_note/summary_none/summary/paste/cancel/pasted_version_name/error_unreadable/error_empty` |
| T4 崩溃哨兵（`81f361b`） | 1 | `toast_unclean_terminate` |
| **合计** | **42** | （预估带 40–60 内；**非 43**） |

### 1.3 43→42 勘误对账（承 M2-8-2 验收 observation①）

M2-8-2-SUMMARY 行文「合计 43 键 / T3（23）」与实况差 1：代码中
`history_paste_adjustments` 系 **09-04 既有键复用**（粘贴菜单项标签），非
M2-8-2 新增目录键——逐 commit xcstrings diff 机检（验收批）+ 本波键级复核：
T1 15 + T2 4 + **T3 22** + T4 1 = **42 新键**；孤儿键
`editor_versions_placeholder` 同批删 → 目录净 +41 = 1588 − 1547 精确。
SUMMARY 行文按先例不改写，对账以本表为准。

### 1.4 键级核验（本波亲测，非引用验收数字）

- 42 键逐键在场且 **en/zh 双语非空**（脚本比对 `strings[k].localizations`）；
- 孤儿键 `editor_versions_placeholder` 不在场 ✓；`history_paste_adjustments`
  在场（既有键）✓；
- 源码引用面：`git grep` 全部 42 键名在 `App/Sources` 有字面命中（含
  EditorToolRailView / AdjustmentTransfer 面板族 / CleanTerminateSentinel），
  无目录孤键、无源码缺键（`--check` 双向断言同判）。
- zh 译文质量归人工审（plan 风险节口径）：机检只判键在册与 locale 纪律，
  **译文待人工润色**不视为缺口。
