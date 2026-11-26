# PLAN-B Review (read-only lane)

PASS / 1 error + 12 minor

> 被评对象：`.work/gsd/phases/rust-core/PLAN-B.md`（537 行）+ `PLAN-B-TABLES.md`（231 行）。
> 结论：命令覆盖、依赖顺序（除 E1）、性能门分配、SQL、T1–T3 落地均成立；1 处前向依赖必须改卡面，12 处措辞/引用/数字小修。

---

## 1. Command coverage (T-A8 → T-B2)

**结论：通过。T-A8 的 31 条恰好各分一波，无重无漏；`adjustments.*` 归 C 期；`job.cancel` + 交互四件归 A7a。**

证据：亲数 `ARCHITECTURE-TABLES.md:217-236` 共 20 行：单命令行 13 行（`session.*` 6 + `template.save` + `library.import/sync` 2 + `photo.moveToSelects/delete/restore` 3 + `trash.empty`）+ `photo.rate/label/flag` 3 + `album.create/smart.create/favorite.add/remove` 4 + `develop.set/merge/reset/copy/paste/sync` 6 + `process.update` + `export.process` + `adjustments.export/import` 2 + `history.goto` = 31。与 `PLAN-B-TABLES.md:106` 的“31 条 / 20 行”一致。

逐条对 `PLAN-B-TABLES.md:110-148`：B12′ 7 条（110-116）、B15 14 行（117-130，含补入的 `library.relink`）、A7a 的 `develop.set/reset/copy/paste`（131-134）+ `history.goto`（143）+ `process.update`（144）、B13′ 的 `develop.merge/sync`（135-136）、B16 的 `export.process`（146）、C 期的 `adjustments.export/import`（147-148，`PLAN-B.md:132` 同口径）。`job.cancel`（145）与交互四件（137-140）在 A7a，与 `waves/A7a-prompt.md:51-59,69-78` 一致。T-A8 之外的条目只有 `library.relink`（补入有注记）、`history.undo/redo`、`develop.*Interaction` ×4、`job.cancel`，均为 A7a prompt 已登记项，无野命令。

小瑕见 m1（B15 卡面写 13 条，表里 14 行）、m2（表头对 undo/redo 的归类语不全）。

## 2. Wave dependencies

**结论：1 处倒挂（E1），其余成立。**

依赖图（→ = 依赖）：B1→A7a（作业/事件）✓；B2 独立 ✓；B3–B11→A4b（校验/`Floats`）✓；B5→A4b 缺口（Text/Path 扩展，B5 内做）✓；B9→B1（roi）✓；B14→B1（S12）✓；B12′→A7a（注册表）✓；B13′→B12′（DAO）✓；B15→B12′（DAO/会话）+B2（`--thumb`）+B1–B11（渲染回落）✓；B16→B1–B11（渲染）✓；B17→A7a+B13′（硬依赖，`PLAN-B.md:386,442` 明示）✓；B18→A7b+B1/B2/B5 ✓；B19→B12′/B15/B16、零新命令 ✓；B20→全部 ✓。

“不做”面无偷渡：B14 退回项归 C-6（`PLAN-B.md:346`）、B15 不做项（层级标签/IPTC/AI/mip）无后波依赖、B16 不做格式 B20 不用、B18 不做项（scopes/DRT）B20 不验。

E1：B6 产出（`PLAN-B.md:244`）要求 overexposed 阈值存会话级 `_meta.display_aux`，但 `_meta` 表与 `dt-catalog` 到 B12′（`PLAN-B-TABLES.md:13-16`）才建，B6 在 B12′ 之前。B6 按卡面做不完。

## 3. Reportable units

**结论：通过。20/20 卡均有“向用户汇报”段，可独立演示；B15 的 7 lane 有内切分（`PLAN-B.md:365`：导入 2 / 缩略图 3 / 浏览行为 2）。**

证据：抽查 B12′（`PLAN-B.md:323` 建/开/验/备/恢复 + 双开被拒 + kill-9 重开）、B13′（`:336` 万张粘贴计时 + 强退重开）、B15（`:362` 导入计时 + 十万行滚动 + Selects/Trash，并诚实注记 GUI 在 B19）、B20（`:427` e2e + 门数总表 + 未达标清单）。无一波塞两件不相干的事；B12′/B13′/B15 范围虽宽但各自内聚（会话地基 / 历史落库 / 会话浏览）。

## 4. Performance gates (A-10)

**结论：通过。三数各有首次波、量法、复量波、不过处置，且首量波均在 B20 之前。**

| 门 | 首量 | 量法 | 不过怎么办 | 复量 |
|---|---|---|---|---|
| 万张粘贴 <1s | B13′（`PLAN-B.md:336` 验收②，`dt-cli bench` + 事务分解） | commit 返回 + 事件送达 | `PLAN-B.md:149` 拆三段后调优或报用户放门 | B20 `perf.sh` |
| 暖切图 ≤0.72s | B18 验收⑥（`:401`，fitted 视口） | 切图→视口稳定计时 | `PLAN-B.md:405` 拆三段、只动呈现段、仍不过报用户 | B20 |
| 可见缩略图 ~0.5s | B15 验收⑤（`:362`，合成网格数据面） | `develop.set` 后可见窗作业完成计时 | `PLAN-B.md:366` 只保数据面、GUI 差值归 B19/B20 | B20 带 GUI |

T-B5（`PLAN-B-TABLES.md:202-215`）与 §0 表（`PLAN-B.md:44-50`）一致。小瑕见 m3（T-B5 表头与行数/出处）、m4（与 A-10 原定波次的偏离未注记）。

## 5. No resurrection of the old architecture

**结论：通过。旧架构零回潮；A-16 与 rawspeed 钉点对；无已退役 crate 名被当现役。**

证据：grep `lmsettings` 仅 `PLAN-B.md:13`“去掉”注记 1 处；`XMP` 仅手写 oracle 夹具（`PLAN-B.md:171` 默认对照、`B20:427`）与 §5/T-B3 差异表史述（`:481-483`，`PLAN-B-TABLES.md:173`）；“双写”仅两处——`user_version`/`_meta` 镜像（`:327`，§1.4 钦定的单函数双写）与差异表史述；“后台刷文件”仅 `PLAN-B-TABLES.md:184` 乙→甲说明句；“无 dt 历史读”在 `PLAN-B.md:427` 为否定句。B3–B11 输入栏逐波写 `release-5.7.0`（`:204,217,230,243,256,269,282,295,308`）+ §3 默认（`:171`），顺序夹具留 master（B1`:177`），合 A-16（`PLAN-AMENDMENTS.md:100-106`）。B2 钉 `0c16fee77`（`:191`）合 A-6（`:29-31`）。`dt-core` 仅两处史述（B1`:177`“A3R 改名”、§5`:479` 原计划列）；`dt-api/dt-app/dt-export/dt-library` 零命中（`crates/README.md:45` 为退役行，计划未引用）。

## 6. Consistency with phase A

**结论：通过，1 处应补写（m10）。**

- 命令经 `execute`：B12′/B13′/B15/B16 均为“向引擎登记新命令”，T-B2 机检（`PLAN-B-TABLES.md:151`）以 A7a 的 `dt-cli commands` 输出断言 id 集，与 `waves/A7a-prompt.md:65,93-97`（会话命令后加、`commands`/`run` 子命令）相容。
- 界面只用 `execute` + 快照：B17 验收⑦（`PLAN-B.md:388`）有 `rg` 机检；B18/B19 零新命令（`:443-444`，T-B2`:150`）；菜单/快捷键归 L5 自有表（`:386-387`），合 A-17（`PLAN-AMENDMENTS.md:108-115`）。
- 费时间的活走作业：B1 渲染（`:178`）、B12′ open 扫描（`:323` 验收⑨）、B16 进度/取消（`:372`）均明示；但 B15（导入复制/sync/缩略图生成）与 B12′（`backup/restore` 整包拷）未写作业边界，而 A7a 契约禁命令碰磁盘/等线程（m10）。
- Apple 边界：§3.1（`:438`）+ T-B6（`:219-230`）点名 B 期唯一增量是 B18 的 `PresentSink` 真实实现；B15 快路径走 rawspeed+纯 Rust JPEG、ImageIO 排 C 期。与 `waves/A6-prompt.md:59-66` 的四条边界检查相容（新增只在 `dt-apple` 内、目标表依赖、无外部 `cfg`）。

## 7. Reference spot-checks (≥12)

**结论：核 22 处，对 20 处，2 处引用不准（m5、m7）。**

| # | 引用 | 核对 |
|---|---|---|
| 1 | `settings.rs:505` `hash64_decimal`（`:71`） | 对（`crates/dt-history/src/settings.rs:505`） |
| 2 | `settings.rs:492` `hash64`（`:178,334`） | 对（`:492`） |
| 3 | `history.rs:23` HISTORY_LIMIT（`:72`） | 对（200） |
| 4 | `history.rs:59` 模型（`:81`） | 对（`HistoryStack` `:59-63`） |
| 5 | `history.rs:191` 交互四件（`:81`） | 对（`begin` 191，update 206 / end 218 / cancel 228 同块） |
| 6 | `history.rs:129` commit / `:147` undo（`:334`） | 对 |
| 7 | `Scripts/rust-budget.sh:42` 360s 门（`:162`） | 对（`gate "cold-build" … 360 s`） |
| 8 | LC `lock.rs:1-34` 语义（`:101`） | 对（162 行文件，文档头 + `LOCK/OWNER` 常量 `:32-34`） |
| 9 | LC `lock.rs:13-18` drop-unlock + #680（`:103`） | 对（#680 在 `:17` 与 `:150` 两处，亲见） |
| 10 | LC `lock.rs:22-24` 无锁降级（`:106`） | 对 |
| 11 | `ModuleInstance::validate`（`:204`） | 对（`impl` 在 `settings.rs:295`，`validate` 在 `:309`） |
| 12 | `SettingValue::Floats`（`:308`） | 对（`settings.rs:136`） |
| 13 | `CORE-DESIGN.md` §1 13 步（`:178`） | 对（`:37` 管线 13 步 + `pixelpipe_hb.c`） |
| 14 | `dt-master` 的 `pixelpipe_hb.c`（`:178`） | 对（`Lightamer-rust-spike/refs/dt-master/src/develop/pixelpipe_hb.c` 存在） |
| 15 | T7 行号（B3`:204` 1/3/5/2…B11`:308` 14/15/16） | 全对（`PLAN-TABLES.md:179-199` 逐行是 rawprepare/highlights/hotpixels/temperature…rgbcurve/rgblevels/tonecurve） |
| 16 | T11 首图 1.79s / 编辑 0.68s（`:399`） | 对（`PLAN-TABLES.md:252-262`：1.79s / 0.680s） |
| 17 | LC `preview/{pool,lru,disk,lib}.rs`（`:360`） | 对（四文件在 `lightcraft/crates/preview/src/` 均在） |
| 18 | LC `media.rs build_job`（`:360`） | 对（`lightcraft/crates/engine/src/media.rs:1207`） |
| 19 | A2 冷构建 10s（`:162`） | 对（`waves/VERIFY.md:19`） |
| 20 | 本仓 Rust 1.100（`:157`） | 对（`Cargo.toml:8` `rust-version = "1.100"`） |
| 21 | “阶段 A 实际 18 lane/45.5h（`waves/VERIFY.md`）”（`:41`） | **错**，见 m5 |
| 22 | relink“ARCH §6/R2 点名”（T-B2`:106`） | **半错**，见 m7（R2 对，§6 未点名） |

另：T-A1 引文号（B12′`:321` 的 #1/#3/#5/#6/#32/#36/#38/#39、B15`:360` 的 #11/#12/#14/#17/#20–24/#25–27/#47–49）逐号存在且主题相符；`history.doc_level`（B6`:249`）在 `crates/dt-iop-traits/src/*.rs:236` 亲见；97 模块夹具（B1`:177`）与 `crates/README.md:49`、`waves/VERIFY.md:52` 一致。

## 8. Dependency facts (rusqlite)

**结论：通过。T-B4 的版本号、许可证、传递依赖与 crates.io 实测逐字一致；全部许可证表达式在允许清单内。**

本 lane 直连 crates.io API 复测（2026-11-26，无代理）：`rusqlite 0.43.0` license `MIT`、`rust_version 1.89.0`；normal 非可选依赖恰 5 个（`bitflags ^2.6`、`fallible-iterator ^0.3`、`fallible-streaming-iterator ^0.1`、`libsqlite3-sys ^0.40.0`、`smallvec ^1.6.1`）；`default = ["cache","ffi-sqlite-wasm-rs"]`、`cache → hashlink`，故 `default-features = false` 确避开 `hashlink`；`backup = []` 无额外依赖；`bundled → libsqlite3-sys?/bundled + modern_sqlite` 不拉新 crate；`libsqlite3-sys 0.40.0` 的 `bundled` 开 build 依赖 `cc`，`cc 1.11.3` 的 normal 依赖恰 `find-msvc-tools + shlex`（`jobserver/libc` 为可选）。许可证：`bitflags`/`smallvec`/`cc`/`shlex`/`find-msvc-tools` = `MIT OR Apache-2.0`（清单 `:15`✓）、`fallible-*` = `MIT/Apache-2.0`（清单 `:19`✓）、`libsqlite3-sys` = `MIT`（清单 `:16`✓）。只查未改。

## 9. Schema (T-B1 SQL)

**结论：通过；索引有 1 处建议（m11）；不变量⑤写不成纯行为测试（m12）。**

- 外键：`history_steps.photo_id→photos`、`snapshot_hash→snapshots`、`photo_keywords→photos/keywords`、`album_photos→albums/photos`，目标表全存在（`PLAN-B-TABLES.md:12-98`）。
- PK/唯一：`photos(id + uuid UNIQUE)`、`snapshots(hash)`（T1 后缀制与 PK 相容）、`history_steps(photo_id,idx)`、`photo_keywords(photo_id,keyword_id)`、`album_photos(album_id,photo_id)`、`favorites(path UNIQUE)`，无自相矛盾。
- §1 文字 vs 列：EXIF 七检索列（`:76` vs `:27-34`）、`trash_original_path/kind`（`:75` vs `:41-42`）、`process` 镜像（`:73` vs `:38`）、游标/当前哈希/失联标记（§0`:34` vs `:39-40,43`）、`display_aux`（B6 S1 vs `:16`），全部对上。
- 索引：`path/rating/flag/process/captured`、`steps_hash`、`album_pos` 有；智能相册查询列（camera/lens/iso/焦距/光圈/快门）、`label`、`missing`、`albums.kind`、`photo_keywords.keyword_id`、`album_photos.photo_id` 无（m11）。
- 六不变量可测性：① 单事务 ✓（故障注入 + 双态比对）；② “单条 UPDATE”行为部分 ✓，字面“单条”需 sqlite trace 钩子；③ 裁剪重编 + 孤儿报告 ✓；④ 镜像核对 ✓；⑤ “写入恒显式”✗（m12：行为测试只能断言存值正确，显式与否不可观察）；⑥ 碰撞注入 ✓。

## 10. Tower amendments T1–T3

**结论：通过，无残留矛盾。**

- T1：§0`:35`、§1.2`:71`、T-B1`:52-53`、不变量⑥（`:100`）、B13′`:332`（“键命中要比对字节”）一致；其余 `hash` 用法是缓存键（B1`:179`，LC 语义的缓存非真相）与测试行比对（B12′`:323` 验收⑥），不与 T1 冲突。
- T2：“不存引用计数”在 `:35,72`、T-B1`:55`、不变量③一致；`refcount` 全文仅 §7`:530` 史述 1 处；`snapshots` 表仅 `(hash, json)` 两列。
- T3：`:118`（强退/崩溃）与 `:119`（断电）两句话分开，T-B1`:10` 同口径；“已提交的命令全在”仅出现在 `:118`（强退/崩溃限定）与 `:531` 史述；B13′ 验收③（`:336` kill-9）是强退语义，一致。

## 11. Estimates

**结论：通过。逐卡粗估，无差一倍以上者。**

| 波 | 卡面 | 本 lane 粗估 | 结论 |
|---|---|---|---|
| B1 | 9h | 9–12h | 偏紧（渲染作业/latest-wins 入波但 +0h），<2× |
| B2 | 6h | 6–8h | OK |
| B3–B11 | 12/12/15/6/10/12/6/9/12h | 同卡面 ±20% | OK（沿用原计划） |
| B12′ | 12h | 12–15h | OK |
| B13′ | 12h | 10–14h | OK |
| B14 | 6h | 5–7h | OK |
| B15 | 21h | 20–26h | OK（上沿；实为 14 命令见 m1） |
| B16 | 12h | 10–14h | OK |
| B17 | 15h | 12–18h | OK |
| B18 | 12h | 10–15h | OK |
| B19 | 15h | 12–18h | OK |
| B20 | 9h | 8–12h | OK |

算术复核：新 81 lane / 223h（B1–B11 43 lane/109h + B12′–B20 38 lane/114h）、原 76/208、差 +5/+15，与 `PLAN-B.md:41,494`、T-B3（`:159-181`）一致。

---

## Findings

| # | 位置 | 问题 | 证据 | 建议改法 |
|---|---|---|---|---|
| E1 | `PLAN-B.md:244`（B6 产出） | 阈值存 `_meta.display_aux`，但该表 B12′ 才建，前向依赖 | B6 波序 < B12′；表定义 `PLAN-B-TABLES.md:13-16` | B6 只做内存行为 + 不记步规则，持久化行移到 B12′（schema + DAO） |
| m1 | `PLAN-B.md:359,366`、T-B3`:175` | “13 条命令”与 T-B2 的 14 行（`:117-130`，含补入 `relink`）不一致 | 亲数 14 行 | 统一为 14，或注记“13 + 补入 1” |
| m2 | T-B2 表头 `:106` | “A7a 已登记的作业/交互命令”漏了 `history.undo/redo`（历史类） | `:141-142` 为 A7a 历史命令 | 改为“编辑/历史/作业/交互命令” |
| m3 | T-B5`:202-215` | 表头“T11 六门 + A-10 三门”=9 但表 10 行；T11 批量粘贴 101 张门（`PLAN-TABLES.md:252-262`）被丢无注记；导出/内存两行出处未注 | 亲数 10 行；T11 有 6 行含粘贴门 | 注记粘贴门被 A-10 门取代 + 两行出处（B16/B18 卡） |
| m4 | `PLAN-B.md:44-50` | 首量波（B13′/B15/B18）与 A-10“在 B15、B16、B20 各量一次”（`PLAN-AMENDMENTS.md:53-55`）偏离，无注记 | 对照两处 | §0 或 §5 加一句偏离理由（B13′ 即历史落库波，更早） |
| m5 | `PLAN-B.md:41,162`、T-B4`:198` | “阶段 A 实际 18 lane/45.5h（`waves/VERIFY.md`）”实为 VERIFY 引 T-A7 计划数（`VERIFY.md:38`），且 A6/A7 未完；“冷构建约 10–15s”的 15s 无出处（VERIFY A2 仅报 10s，`:19`） | 对照三处 | 改“实际”为“计划”并改引 T-A7；15s 注出处或删 |
| m6 | `PLAN-B.md:149` | “再定是调 `#13′`”疑 typo | 原文 | 改为“调优”或“调 B13′” |
| m7 | T-B2 表头 `:106` | relink“ARCH §6/R2 点名”中 §6 未点名 | `ARCHITECTURE.md:71`（§2）与 `:140`（§9 R2）有点名，§6 无 | 改为“§2/R2” |
| m8 | `PLAN-B.md:72` | commit 描述漏了 redo-tail 删除（A4b 先 `truncate(cursor+1)`） | `crates/dt-history/src/history.rs:133` | 补“同事务删游标后步” |
| m9 | `PLAN-B.md:340` | “库事务先提交，内存随后应用，失败回滚库事务”——已提交事务无法回滚 | 原文 | 改顺序（内存先算/库事务内提交 + 内存应用不可失败）或重写措辞 |
| m10 | `PLAN-B.md:320-323`（B12′）、`:358-362`（B15） | `backup/restore` 整包拷、导入复制/sync/缩略图生成未写作业边界，A7a 禁命令碰磁盘 | `waves/A7a-prompt.md:40-43` 快命令契约 | 两卡各加一句“重活走作业，命令只登记/返回” |
| m11 | T-B1`:45-49,65,90` | 智能相册查询列（camera/lens/iso/…）、`label`、`missing`、`albums.kind`、两个连接表反向列无索引 | SQL 全文 | B15 bench 定夺，或注记故意不加 |
| m12 | T-B1`:100` 不变量⑤ | “写入恒显式”写不成纯行为测试（只能断言存值 + 代码检查）；②“单条”需 trace 钩子 | 同行 | ⑤ 改为可断言形（“process≠1 的照片存值与快照一致”）+ 注记显式性走代码检查 |
