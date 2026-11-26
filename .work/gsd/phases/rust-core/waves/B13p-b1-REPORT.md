# B13′-b1 Report: Persisted Edit Commands on Real Sessions

> lane B13′-b1（omp 执行）。HEAD 起始 `0b11763b`（亲核）。中文正文，英文标题与 message。

## 结论头

- 十二条编辑/历史/处理版本号命令在真实会话上按 T5 落库；草稿语义逐位不变；全工作区 344 通过 +1 忽略（283+62）。
- 按需加载 + LRU 64 缓存 + 盖库摘要；强杀崩溃语义经子进程证明；第 0 步对齐 `import` 单一出处。
- A7a 单测 44 原样通过，CLI 样例摘要逐位相同；lint/文档/xtask/边界/演示全绿；复审 `PASS / 0 error + 2 minor` 已回注。

## 真实会话里的照片

- 标识：库内 `uuid` 文本即引擎 key（`engine.rs:47` 不动）。
- 按需加载：`ensure_photo_loaded`（`engine.rs:351`）——命中触达；未命中 `find+read_history+from_steps` 重建入缓存；库无此标识报 `NoPhoto`（与草稿同变体，双边断言）。
- 缓存上限 64（`PHOTO_CACHE_LIMIT`）：栈是纯设置（数十 KB），64 覆盖浏览/选片工作集；批量命令流式穿过；有未结束拖动的不驱逐；全钉时新加载被拒（`Disabled`，M-2 回注）。驱逐后重载一致。
- `photo_ids` 走库列出并排序（`engine.rs:615`）；其余四口命中走栈（含 live），未命中直读库不入缓存（`stored_history:495`）。

## 每条命令的三步落点（`engine/src/real.rs`；分发 `engine.rs:196` + develop/history 各首行）

- 算：load（含 settle 旧拖动）→ 新栈/设置 → 序列化（可失败点），库未碰。`settle_interaction:100` 经 `pending_interaction` 预读。
- 交：`commit_ops:123`——空 ops 不碰库；单推 `push_step`/单移 `move_cursor`；多 ops 一 writer（含新增 `HistoryWriter::move_cursor`）。
- 换：`swap_in:174`，事件由 probe 步数/游标构造（不读可驱逐缓存），不可失败。
- 内存-only：copy（剪贴板）、begin/update（live）、无变化 end、cancel——触发器下照常成功，反证零写。
- 函数：set 189 / reset 241 / copy 284 / paste 307 / begin 362 / update 396 / end 432 / cancel 466 / undo 491 / redo 501 / goto 511（经 move_cursor 571）/ process 627（现行照片连 settle 都不碰）。

## 万张粘贴：没走快路径

统一逐张加载再提交：栈是 KB 级小对象，LRU 防钉住，算好的新栈在局部等提交；等价性构造自明。205 步连续落库所在文件 23 测试共 0.17 s。门级计时归 b2。

## 摘要数（`state_digest:723`）

- 草稿：原体逐字入 `digest_draft_state:731`；A7a 两数 CLI 复核逐位同。
- 真实：`digest_real_state:762` = 库全量（uuid 序×游标×逐同步标签与快照字节）+ 已加载 live 值 + 同一尾巴（`mix_clipboard_and_jobs:805`）。
- 库被背改则动；拖动则动、取消则回；加载/驱逐不动（69 轮 begin+cancel 后回初值）。读失败混 `store-unreadable`。

## 历史模型接口（只增）

1. `INITIAL_LABEL` 公开（`history.rs:29`），值 `import` 钉死。
2. `from_steps(steps, cursor)`（`:261`）+ `RebuildError::{Empty,TooMany,CursorOutOfRange}`（`:290`）：与逐步提交全等；越界/空/超 200 皆错。
3. `merge_adjustments`（`merge.rs:56`）+ `MergeSelection::{Modules,Params}`：模块级整实例替换/新增（源缺席=无操作）；参数级按名覆盖（目标缺实例则新建，只带选中参数+源开关/名）；目标版本不动。4 测试。
4. 附带（T5 所需）：`pending_interaction`（`:135`）预读拖动会不会提交。1 测试。

## 验收 §7（命令与输出）

- 守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=72% ...)` exit 0。
- history/engine/catalog：`37+1` / `44+25+26+1+13+11+0` / `60+1忽略`，全绿。
- workspace：344 通过 / 0 失败 / 1 忽略；`--list` 343→345（283+62：history 9 + catalog 1 + engine 52）。
- 测试映射：对等 10（set/reset/copy/paste/paste-empty/drag/cancel/moves/process/stuck，覆 13 契约）+ settle 2 + 懒加载 4 + reopen + paste 单事务 + trim + import + digest 3 + 坏参数 12 + 事务失败 14 + 崩溃 1 + merge 4 + from_steps 3 + label/pending 2 + catalog writer-move 1 + partial/pinned 2。
- A7a 零改：三文件 diff 中 `assert` 零增删，hunk 全在非测试区（12 分发 + 可见性 + 缓存/摘要；`_ctx`→`ctx` 系传参需要）。
- 历史只增：删除行唯一（`const INITIAL_LABEL` 改公开）；旧 28 全过。
- 字节：CLI 五行摘要 `9734988588720734966/6191755046607852097` 逐位同，exit=1 同 A7a（末行空剪贴板注定失败）。
- 六 lint + `fmt --check` + `clippy -D warnings` + `cargo doc -D warnings` 全绿。
- xtask 四项 + `rust-apple-boundary.sh`（7/7）全绿。
- `rg std::fs... engine/src` 与 `rg '"seed"' catalog/src` 皆无输出（exit 1）。
- `rust-session-demo.sh` → `demo: ALL GREEN`，exit 0。
- 残留：git status 无测试文件；/tmp 无 `lightamer-*-test-*`；无残留进程（pgrep 空）。
- 路径：`git show --name-only` 22 文件全在纪律清单（engine/history/catalog、SESSION.md、README 两行、REPORT+review.log；无 Cargo.lock、无 CLI 改动）。

## Commit

`067a1a73`（初交）→ 含 M-1/M-2 回注与 review.log 的 amend 为最终（`git log -1` 为准；B12′/B13′-a 同款 skew，内容差见修订记录）。

## 复审结论头

`PASS / 0 error + 2 minor`（`B13p-b1-review.log`，154 行，§7 逐条重跑 + real/engine/history/merge/store/测试全读）。

## 修订记录（自审回注）

- R1（M-1）：初交 REPORT 落盘截断（67 行，止于“字节没变：A7a 五”）——重写为本全文；补 §7 后半、`INITIAL_LABEL` 行号、计数口径（对等 10 覆 13）。
- R2（M-2）：64 全 pinned 时新加载当轮被驱逐（批 `continue` 静默跳步/单命令 spurious NoPhoto）——`ensure_photo_loaded` 加留存断言，落空报 `Disabled`（提交前失败，原子性成立）；加 `set_with_cache_fully_pinned_is_refused_cleanly` + 另补 `set_with_a_later_unknown_photo_commits_nothing`；计数 60→62、343→345。

## 给用户看的汇报

做成了：在真实会话里改参数、撤销、跳步、升处理版本，每一步都进了库；关掉重开一模一样；中途强杀，已提交的全在、没松手的拖动不在；一次粘贴一万张要么全成要么全不成。
还没做：合并/同步两条新命令与计时演示（B13′-b2）；照片导入（B15）。

## 未做 / 未验

- 未做：无。任务书 1–6 节交付；b2 预置的 merge 函数本波零调用者（按计划）。
- 未验：非 macOS 目标（按任务书不跑）；万张门级计时归 b2 bench。
