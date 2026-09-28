# M2-2 Research Notes — 探针实测（2026-09-27）

> discuss 阶段探针，只记录必要结论；脚本未入仓（/tmp 临时件）。CONTEXT 引用处标注 P1/P2/P3。

## P1: 系统 libsqlite3 版本与 FTS5 能力

**问题**：D3 选 SQLite 后，项目库能否用 FTS5 且零新依赖？CLI 与 app 内链接的是否同一引擎？

**方法**：`sqlite3 --version`；Swift 脚本 `import SQLite3`（= Xcode SDK 自动链接系统 libsqlite3，与 Phase 9 `SQLiteHandle` 同链路面）在 `:memory:` 上建 FTS5 虚表并查 `sqlite_compileoption_used`。

**结果**：

| 项 | 值 |
|---|---|
| CLI `/usr/bin/sqlite3` | 3.54.0（2026-04-09） |
| Swift `SQLite3` module 链接的 lib | 3.54.0（`sqlite3_libversion()`，与 CLI 同源） |
| FTS5 建表 | OK |
| `ENABLE_FTS5` | true |
| `FTS3_PARENTHESIS` | true（无关但顺记） |

**结论**：FTS5 + external-content 全部可用，零新 SPM 依赖成立。`SQLiteHandle` 现有面（prepare/bind/step/finalize）够用，无需 C 扩展（自定义 tokenizer 不可行也无必要——见 P2 风险注）。

## P2: EXIF 词法检索 — folded-LIKE vs FTS5 @ 20k 行

**问题**：M2LIB-04「物化搜索列 + 词边界折叠检索，~20ms@2 万张」。折叠物化与索引层的分工各占多少收益？

**方法**（Swift + 系统 libsqlite3，/tmp 单文件库，WAL+NORMAL）：

- 合成语料 20,000 行：stem/日期/5 相机/5 镜头/7 档 ISO/6 档光圈/7 档焦距随机组合。
- **折叠物化**（正确性承重面）：`exif_search_text` 与 `exif_search_words` 存折叠变体串，例如原文 `f/2.8` 折叠出 `f2.8`、`f 2 8`；`ISO 800` 折叠出 `iso800`、`iso 800`；`35mm` 折叠出 `35 mm`。查询词与折叠词精确对齐。
- 方案 A：折叠文本列上 `LIKE '%' || ? || '%'` AND 组合（3-5 词）。
- 方案 B：同文本上 FTS5 external-content 表（`tokenize=unicode61` 默认），`"w1" AND "w2" AND ...` MATCH（4 词）。
- 300 次随机查询取 p50/p95；另测导入吞吐与库体积。

**结果**：

| 指标 | folded-LIKE | FTS5 MATCH |
|---|---|---|
| 组合检索 p50 | 3.80 ms | 0.17 ms |
| 组合检索 p95 | **3.89 ms** | **0.23 ms** |
| 导入 20k + FTS rebuild | 同一批事务 | 共 125 ms |
| 库体积（含两方案并存） | 5.3 MB / 20k 行 | — |

正确性抽核：`f2.8` 双方案计数一致（6665）；`iso800` 精确命中不含 `iso8000` 类前缀串。

**解读**：

1. **折叠物化是正确性承重面**——不折叠则 `iso800` 查不到 `ISO 800`（unicode61 把 `iso800` 与 `iso`,`800` 分成不同 token）；折叠词表必须进 plan 固化（词表 + 双向测试）。
2. **20k 规模两方案都大幅低于 20ms 门**（LIKE 全表扫 3.9ms ≈ 门值 1/5）。FTS5 ~17× headroom 的价值在 10 万张级（LIKE 线性外推 ≈ 20ms 触顶，FTS5 走索引基本持平）。
3. **tokenizer 风险注**：unicode61 若注册 `tokenchars '.-/'`，`f/2.8` 会变成单 token，`f2.8` 查询反而失配——**用默认 unicode61 不定制**，一切归一化交给折叠物化。自定义 C tokenizer（如 alnum-run 折叠 tokenizer）能力上可行（系统 lib 允许注册），但属于自养复杂度，不推荐。

**备注**：跑探针时 LIKE 侧多带一个折叠词（5 项 vs FTS 4 项），部分 trial 计数差异是查询集不同所致，非正确性缺陷；性能结论不受影响（LIKE 侧更慢的方向保守）。

## P3: 单文件包形态 — WAL 伴生文件行为

**问题**：`.lalb` 要「拷走 = 完整项目」。WAL 模式下伴生 `-wal`/`-shm` 的生命周期如何？严格零伴生是否可能？

**方法**：Swift 脚本建库 → `journal_mode=WAL` → 写入 → 观察目录；`sqlite3_close`（rc=0）后再观察；再开 → 写 → `PRAGMA wal_checkpoint(TRUNCATE)` → close；另测 `sqlite3_backup_*` 在打开态拷贝。

**结果**（系统 libsqlite3 3.54.0，macOS 27）：

| 时点 | 目录状态 |
|---|---|
| open + 首写后 | `-wal`（非零）+ `-shm` 出现 |
| clean close（rc=0）后 | **伴生文件仍留存**（3.54.0 不再 unlink） |
| checkpoint(TRUNCATE) 后 | `-wal` = **0 字节**，`-shm` 32KB（纯映射无数据） |
| `sqlite3_backup` 打开态拷贝 | OK，得一致性单文件 |

**结论**：

1. **严格零伴生不可得**——连 clean close 都留 0 字节 `-wal`。CONTEXT OQ-2 的「单文件」语义只能定义为「一个数据文件 + checkpoint 纪律下的空伴生」，不是字面唯一文件。
2. 真正的数据丢失窗口 = **未 checkpoint 时只拷主文件**。纪律对策（进 plan）：写批后节流 `wal_checkpoint(TRUNCATE)` + 关闭强制 checkpoint + 「备份/移动」功能一律走 backup API，不给用户裸拷路径的依赖。
3. 若 plan 要更硬的单文件观感，fallback = `journal_mode=DELETE`（永不伴生，代价：每写事务整库 journal 重写、读写并发弱化）——批量导入吞吐会明显劣于 WAL，不推荐，仅备选登记。
4. SC#3 结论（SQLite 1M 行 p95 12.28ms）在此 3.54.0 引擎上延续成立；Phase 9 的 WAL+NORMAL PRAGMA 基线与本项目库兼容同栈。
