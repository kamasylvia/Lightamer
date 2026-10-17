# M7-4-01 SUMMARY — MCP O4 跨图批量 + note 归属 + UQ-A2 原子终写（修订版 plan 全闭环）

```
phase:      m7-4-mcp-o4
plan:       M7-4-01（修订版，HEAD 16011688+7d595abc 起执行；CHECKER 放行批）
status:     executed — T1..T7 全闭环；全套终值见 §全套
baseline:   3905/35/0（HEAD 7d595abc）
executed:   2026-10-17（夜间全自动批，先例 D-07-3-T5-1；晨审可推翻）
chain:      49fab645(T1) → d3f487a6(T2) → a78ea631(T3) → 2af9b17d(T4)
            → a9b8f06e(T5) → 503f1ffc(T6) → docs(T7)
evidence:   m73-probe 分仓 commit（lightamer-evidence 仓 `70774ad`）+
            App/Library/Layers/Export 四域定向轮 + 全套 --all 轮
```

## §1 逐任务记账（ΔN 如实）

| 任务 | 内容 | commit | ΔN | 定向轮 |
|---|---|---|---|---|
| T1 | S1 修复批首项（poll POLLIN + 250ms bounded re-poll + revents 分流 + 纯 POLLIN 臂 250ms sleep〔修订批 F2 忙旋消解本体〕）+ 探针迁 evidence + e2e 真断连新法 + fixture env 注入（F14） | `49fab645` | +1（e2e） | App 869/4/0（e2e 0.87s：真 EOF → POLLHUP → close+exit(0)；`.lalb-wal` size==0） |
| T2 | S2 A+C：`warmLutLibrary()` 恰 1 定义 + 4 装配点（stdio/http/只读 http/GUI）+ `LIGHTAMER_SKIP_LUT_PREHEAT` env 门 + list_luts 描述原位值改（en+zh 同批）+ S3 正臂腿 | `d3f487a6` | +1（S3） | App 870/4/0（373s——runner 中央 env 门后零 50s 停滞） |
| T3 | O4 双工具（copy 只读枚举 / paste 批量写）+ AdjustmentTransferCatalog 抽取消二份 + HistoryItem additive note/author + SidecarHistoryItemRecord 镜像全链 + schemaVersion 10→11 + get_history 真位翻转 + apply_params note 参 + author="mcp" 盖章 | `a78ea631` | 0（golden 归 T6） | 构建绿（App 快照红窗自本任务起，申报形） |
| T4 | UQ-A2：encodeStage additive `exclusiveFinalWrite` + 同目录隐藏 tmp + link() EEXIST → BaseNameOccupiedError + encoder-error 清理腿改道（F4）+ gain-map 同 wrap + `$jobNamingCarrier` encode 腿 wrapper + 五腿测试 | `2af9b17d` | +4（TOCTOU 负测/正向恒等/.replace 守卫/第五腿） | Export 385/5/0（381+4 对账精确） |
| T5 | match_color provider 目录锚勘正（20997721 先例第三实例）+ 两测试 provider 同形 + kind0 锚腿新法 | `a9b8f06e` | +1（kind0 腿） | App 过滤轮 McpMatchColorToolsetTests 22/0/0 |
| T6 | union 27→29 全点位显式改 + editing 层 note 行 + 两新行 + union 外五钉 21→23 + O4 golden 六法 + Catalog 恒等 golden + SidecarV11Tests 新文件五法 + get_history golden（真位翻转 + 红尾腿 + pristine .null）+ GUI 面（note 副标题 + author 徽章）+ xcstrings 第三键 | `503f1ffc` | +8 App（editing 6 + Catalog 1 + 红尾 1）+5 Library（V11 五法） | App 879/4/0（红窗闭合）+ Layers 494/5/0 + Library 736/4/0 + zh-audit 双 PASS |
| T7 | Export 定向 + 全套 --all + 红线族 + 收口翻账 | 本 commit | 0 | 见 §2/§3 |

**ΔN 总账 = +20**（逐 bundle：App 868→879〔+11〕/ Library 731→736〔+5〕/ Export 381→385〔+4〕/ Layers 494→494 / IOP·IOPParity·Sessions 零漂移；全套口径 +20）。预期带 +22..29 未达（−2）：S1 可选锁窗腿未行使（时间盒条款——e2e 主腿已承载锁语义侧写经第二 open typed 拒；不入 XCTest）+ T6 golden 按实质面收敛（O4 六法 + V11 五法 + 红尾一腿，未拆更细粒度）——带下如实记账，无静默吸收。

## §2 全套终值

`TOTAL|3925/35/0|`（3905 + 20 对账精确；skip 35 = 既有 env 门构成零漂移零新 skip；exit 0 零 MEMFAIL 七 bundle 8G 门内——逐 bundle 行见全套轮日志 `/tmp/la-direct-tests-*.log`）。

## §3 S1 e2e 实测（活性窗 + wal==0）

- **活性窗**：真产线二进制 `--mcp-stdio` spawn → initialize → `project_create`（arm watcher）→ 关 stdin（真 EOF 面）→ **0.87s 退出**（门 ≤12s；修复前此形 ≥12s 不退持锁——三层复现在案）。
- **wal==0**：close 的强制 TRUNCATE checkpoint 兑现——`.lalb-wal` 文件存在且 size == 0（本机实测干净 close 后 WAL 保留 0 字节〔macOS 系统 SQLite 形〕；kill 形遗留非 0〔e2e2 遗物 387KB 对照〕）。锁语义侧写 = 退出前第二 `project_open` typed `projectHeldByOther`（同测试内）。

## §4 O4 双工具 golden 摘要

copy（六断言面：grades/nodes/chainCount/transferableCount/灰显可见/两形态寻址含库 id）+ paste（ledger applied + label/note/author 落盘 + mask 纪元重置 + 立即读回 + live 硬拒 + membership 拒 + probe 全调拒 + 重复 targets invalidParams + unreadableSource 全拒批 + include 子集 + includeDrt opt-out + UUID recast）+ Catalog 恒等（GUI model ≡ Catalog 逐值）+ SidecarV11 五法（三 byte face + hash 隔离 + future 12）+ get_history（per-item 两键 + 顶层真位翻转 + 红尾腿 + pristine .null）。

## §5 UQ-A2 五腿实测

①TOCTOU 负测：renderStage 后手工植 destination → exclusive encode → typed `BaseNameOccupiedError` + 植入字节不变 + 目录零 tmp 残留；②正向恒等：exclusive ≡ plain rename 逐字节；③.replace 负面守卫：plain rename 仍覆盖；④.increment：既有 E2E face 全绿即守卫（零新增法）；⑤encoder 失败腿：float32 plane vs png spec 强制 throw → 植入 destination 字节不变（F4 清理腿改道兑现）+ 零残留。

## §6 中间红窗申报（T3..T6）

union/editing 两层快照红自 T3（29/23 工具 vs 冻结 27/21）至 T6 显式改收口——每任务 gate = 构建绿 + 非 App 定向绿（T4 Export / T5 过滤轮）；T6 `--bundle App` 879/4/0 为红窗闭合点。App bundle 6/4/2 中间轮两败（T6 golden 首版 TemperatureModule 归属预期错误——temperature 属 RAW-decode 域非 grade）当轮修复重跑绿，未放宽断言。

## §7 偏差清单（plan vs 执行，全小偏差已申报）

见 `M7-4-01-DECISIONS.md` §偏差清单（探针分仓 / T2 五文件 / runner 中央 env 门 / V11 落 LIB 域 / 温度归属修正 / 空源 invalidParams / S2 预热观察证据 / SidecarV10Tests :327 法语义退化申报等）。
