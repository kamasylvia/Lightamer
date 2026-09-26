# Plan 12-2 — Summary

**Date:** 2026-09-26
**Status:** Complete（执行 worker 申报，待验收）
**Wave:** 2（与 12-3 并行，零交集；依赖 12-1 字段面）
**Requirements:** META-05（过滤/排序）、META-06（智能相册）

## 交付面

| 任务 | 交付 | Commit | 证据 |
|---|---|---|---|
| T1 | 谓词模型：FilterPredicateGroup/Rule/Field/Op/Value（tagged-union Codable，schema v1，typed decode 降级 + 合法性矩阵） | `999a9fb` | FilterPredicateTests 10（round-trip/sortedKeys golden/独立期望矩阵/typed 拒绝向量） |
| T2 | FilterSQL 单一翻译层：四联式祖先谓词（F3 正本）+ bind-only + LIKE 转义 + 排序白名单 + baseline 恒附加 + translateConjoining 组合器 | `128991d`（+组合器随 `7336c3d` 提交） | FilterSQLTests 27（快照/注入向量/NatureHolics 对照组/fixture 精确行集 L020） |
| T3 | SessionIndexStore.query 消费面（groups 数组 + 排序 + bound LIMIT；34 列行模型复用；withHandleForTesting 缝） | `7336c3d` | query 段 4 测试（互证行集/排序 NULLs-last/limit 分页/写并发 smoke 20×5×5） |
| T4 | 过滤栏 UI：chips + Quick Filter（/聚焦·Esc 清除·防抖 200ms）+ 排序菜单持久化 + 空结果态 + zh catalog 37 键 | `fc188a9` | GUI 走查 7 证据 `12-2-01..07` |
| T5 | SmartAlbums：app 级存储（UUID 文件/sortedKeys/同目录 tmp 晋升/自愈跳过）+ 侧栏第四区 + 激活互斥 + 求值组合 | `baaa19a` | SmartAlbumStoreTests 7 + GUI 走查 3 证据 `12-2-08..10` |
| T6 | 全量回归终轮 + SUMMARY/DECISIONS/TODO/PROGRESS 收尾 | `183da56` | 1334/6skip/0fail（449.0s） |
| fix | T4 Core 半边补入库：组合器 appendsBaseline/translateConjoining + query(groups:) 签名 + 组合器/limit 测试（fc188a9 漏 stage，HEAD 单独不可构建——工作区与 HEAD 自 T4 起同码，行为零变化） | `e4ab88b` | FilterSQLTests 27 全绿（同码） |

## 测试演变

1290/6skip/0fail（12-1 收尾基线）→ **1334/6skip/0fail**（+44：FilterPredicateTests 10 + FilterSQLTests 27 + SmartAlbumStoreTests 7）；终轮 449.0s，0 fail。

## AC 逐条自检

- [x] **谓词模型**：16 字段 × 12 操作符全对齐 v2 34 列面（Field→列名静态白名单）；tagged-union Value（8 kind，intList/doubleList 为 additive 扩展）；合法性校验 typed 错误（illegalFieldOperator/illegalValueKind/invalidInterval）；sortedKeys 字节 golden（智能相册文件体与过滤栏 state 同型序列化——同一类型同字节拼写）。
- [x] **翻译层单实现**：四联式祖先谓词 = `(keywords = ? OR LIKE ?||'|%' OR LIKE '%|'||?||'|%' OR LIKE '%|'||?)` ESCAPE 形态（RESEARCH §3.2 修正 CONTEXT D-3；**NatureHolics 对照组测试钉死**——裸 LIKE 在同一 fixture 命中 natureholics.arw 而四联式不命中）；bind-only 零拼接（注入向量 `'`/`%`/`_`/`\` 全测）；排序白名单直译列名 + LIMIT bind；`orphan_sidecar = 0` 恒附加（含空组/多组合并恰一次）；每字段×操作符快照断言。
- [x] **query 消费面**：fixture 精确行集（query ↔ 翻译层互证）+ 与 claimMetadataApply/markRowsStale 并发共存 smoke（TaskGroup 交错 30 腿全成功）。
- [x] **过滤栏 chips + Quick Filter + 排序持久化 + zh**：chips 叠加 AND 即时生效；Quick Filter 粘贴输入 + 防抖重查 + Esc 清除；排序 asc/desc + **重启跨程持久化**（Picker 恢复 + `installQueryState` 修复后首绘即按排序渲染——walk-16）；空结果态 zh 展示；catalog 37 键 zh/en 双语（L025 zh 标签）。
- [x] **SmartAlbums**：app 级存储（`~/Library/Application Support/Lightamer/SmartAlbums/*.json`，sortedKeys + 同目录 tmp 原子晋升 L009 + 无残留断言）；启动重扫自愈（损坏/未来 schema 文件 typed 跳过永不删除）；求值域 = 当前会话（规则随 app/结果随会话——切会话空结果/切回复现双证 + 测试组合面 L020）。
- [x] **收尾**：全 suite 0 fail（1334/6/0）；每任务独立提交（5 commits，`git show --stat` 边界干净）+ 边界查 config 开关 ×5；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘。

## GUI 走查记录（控制台解锁，2026-09-26 15:38-16:01；真实 app + /tmp/la12-session + AX/键盘驱动）

1. **12-2-01-filterbar-zh**：过滤栏 zh 首屏（快速过滤框/★3·留用·排除·已编辑 chips/+菜单/排序「文件名」↑ 全渲染）
2. **12-2-02-grid-3rows**：会话打开，网格 3 行，过滤栏就位
3. **12-2-03-chip-rating3**：★3 chip 激活（高亮）→ 网格只剩 img0(4★) + 激活 chips 行「评分 ≥ 3 ⓧ」投影 + 清除按钮出现
4. **12-2-04-quickfilter-img1**：Quick Filter 粘贴 "img1" → 防抖后只剩 img1（chip 取消同时验证）
5. **12-2-05-empty-result**：chips + Quick Filter AND 叠加（img1 且 ≥3 星 = 空集）→ 空结果 face（zh）
6. **12-2-06-sort-asc-firstpaint**：重启后**首绘**即按持久化「评分 ↑」渲染（img2(2★)→img0(4★)→img1 NULL 尾）——排序跨重启持久化 + installQueryState 修复实证
7. **12-2-07-sort-desc**：方向切换 ↓ → img0→img2→img1（NULL 仍尾）
8. **12-2-08-smartalbum-created**：「从当前过滤新建」→ 侧栏「高分组」+ 激活勾；磁盘文件 `SmartAlbums/759CB924-….json` 内容 = 谓词组 + 名称（sortedKeys）；chips 行被替换（互斥）
9. **12-2-09-smartalbum-other-session**：切 la093-session → 同一激活规则求值 = 空结果 face（**结果随会话**）
10. **12-2-10-smartalbum-back-to-la12**：切回 → img0 复原（规则随 app）

### Manual-Only 登记（合成驱动限制，人工确认项）

| # | 项 | 说明 | 覆盖状态 |
|---|---|---|---|
| F-12-2-1 | `/` 键聚焦 Quick Filter | 裸 `/` 合成走 IME 不可靠；聚焦语义以 AX 直点搜索框验证（输入可达），keyboardShortcut("/") 代码面在位 | 代码面 ✅ / 按键合成待人工 |
| F-12-2-2 | chips 长按删除交互 | 长按手势不可合成；同语义 ⓧ 删除按钮已走查（激活 chips 行移除即时生效） | ⓧ 路径 ✅ / 长按观感待人工 |
| F-12-2-3 | 日期区间 sheet 双 DatePicker | sheet 交互合成复杂；between SQL 形态 + fixture 行集已由单测钉死（captureDate between 快照 + iso400 行集） | SQL 面 ✅ / sheet 观感待人工 |
| F-12-2-4 | 智能相册重命名/删除确认 alert 流 | SwiftUI alert 对 AX 合成不稳定（12-1 F-12-1-2 同款）；CRUD 服务面由 SmartAlbumStoreTests rename/remove 全覆盖 | 服务面 ✅ / alert 观感待人工 |

## 偏离与注记

1. **基线口径**：plan Verification 表写 1260（12-1 前快照），执行协议基线 1290（12-1 后实况）——按 1290 起算，终轮 1334。
2. **plan 申报文件两处落位修正**（D1/D2 详录）：ContentView.swift 未改（过滤栏实落 SessionBrowserView 内部 inset）；智能相册侧栏入口实落 SidebarView.swift（plan 笔误申报 InspectorView.swift——三段结构在 SidebarView，InspectorView 在 grid 模式不渲染）。新增未申报文件：`FilterBarView.swift`（过滤栏 UI 独立成文件）、`SmartAlbumStore.swift`/`SmartAlbumStoreTests.swift`（plan 已列）。
3. **T2 双提交**：四联式/快照/行集主体在 `128991d`；多组合并器（D6，T4 叠加语义的前置）随 T3 的 `7336c3d` 进库——组合器是消费面扩展非翻译层重写，commit 归属按 diff 实际。
4. **走查数据辅助**（D14）：合成键盘 IME 限制下，排序/相册走查用 sqlite3 直改 fixture DB + sidecar 直写辅助——生产语义（GUI 写链路）已由 12-1 MetadataServiceTests 钉死，本 plan 验收面（过滤/排序/求值）不受影响。
5. **域外缺陷登记**：`sidecar_present` 永不刷新（12-1 域）——「先图后 sidecar」的行增量打开永不回读（详 12-2-DECISIONS 域外节）；已登记 GOAL-STATE 待人工立案，本 plan 范围纪律未修。
6. **T4 提交边界遗漏（已补）**：fc188a9 只 stage 了 UI 文件，其消费的组合器 Core 半边（FilterSQL translateConjoining/appendsBaseline + store query(groups:) 签名 + 测试更新）滞留工作区——`e4ab88b` 补入库（同码入库非行为修复；此后 HEAD 单独可构建）。流程注记：每 commit 后须复查 `git status` 而非只核 add 清单。
7. **执行环境注记**：`Scripts/test-direct.sh` 为 zsh 脚本，bash 直接调用会挂（`${0:A}` 语法）——以 `./Scripts/test-direct.sh`（shebang zsh）调用正常；脚本既有面未改。
