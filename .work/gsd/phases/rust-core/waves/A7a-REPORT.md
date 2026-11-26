# A7a Report: Command Dispatch — Everything Is a Command

结论头：13 条命令登记，`execute` 原子可重入守卫，作业池+事件+快照在位，`dt-cli commands/run` 走通；全工作区 180 测试绿，`rust-ci-lite` 全绿。
起始 HEAD `1fcbbeab` 已亲核（`git rev-parse HEAD` = `1fcbbeab5a70e735ac428717307b2e51d60e454a`）。

## 1. 命令声明与登记表

每条命令是一条静态 `CommandSpec`（`crates/dt-engine/src/command.rs`，取自 LightCraft `cmd/mod.rs` 改造）：

```rust
pub struct CommandSpec {
    pub id: &'static str,        // 如 develop.set；同时是历史步标签
    pub summary: &'static str,   // 一句话说明
    pub params: &'static [ParamSpec], // 机器可读参数清单（LightCraft 缺，我方加）
    pub needs_session: bool,     // 会话门（拒为 NoSession）
    pub enabled: Enabled,        // 动态判断（拒为带原因的 Disabled）
    pub run: Run,                // fn(&mut Engine, &Map, &mut RunCtx) -> Outcome
}
```

`ParamSpec = { name, kind, required, doc }`，`ParamKind` 七种：`flag`/`integer`/`float`/`text`/`enum`/`photo-ids`/`patch`（`float`/`enum` 本波无用命令，留作后波词汇）。
登记表按类三静态数组（`develop::SPECS` 8 条、`history::SPECS` 4 条、`jobs::SPECS` 1 条），`command_specs()` 用 `LazyLock` 汇总，`find_command(id)` 线性查。
不进声明：菜单、快捷键、日志回放（本波无用，以后加字段）。
登记完整性三测试：标识无重复、单命令参数名无重复、每命令与每参数都有说明（`command.rs` tests）。

## 2. `execute` 的契约

`Engine::execute(&mut self, id, params) -> Result<Outcome, CommandError>`（`engine.rs`）：

- **原子**：调用前克隆同步态（全照片栈+剪贴板），任何环节出错整体恢复；失败调用零事件。`state_digest()`（FNV-1a over 全部照片规范字节+游标+剪贴板+作业表）供测试与 CLI 比对。
- **分类型错误**（`CommandError` 11 变体，各有一行人话）：`UnknownCommand`/`UnknownParam`/`MissingParam`/`BadParam`/`Disabled`/`NoSession`/`NoPhoto`/`NoInteraction`/`EmptyClipboard`/`JobNotFound`/`Reentrant`。
- **有界**：本波命令只改内存；crate 文档写的是定稿口径（B13′ 起至多一次有界落盘，无界活走作业），不是“永不碰磁盘”。
- **一步一标签**：改历史的命令每张照片恰记一步，标签=命令标识；`ids` 去重，重复 id 不记两步。
- **门控**：`needs_session` 先判（`NoSession`），再调 `enabled`（`Disabled`+原因）。`job.cancel` 的 `enabled` 在空作业表时拒（覆盖“声明判断拒”的测试路径）。
- **重入**：`executing` 标志；分发在调用内完成，监听者里调 `execute` 得 `Reentrant`，外层照常成功。

## 3. 登记命令与记步

| 命令 | 参数 | 记步 |
|---|---|---|
| `develop.set` | `ids!` `module!` `patch!` `multi?` `enabled?` | 每张一步（合并补丁） |
| `develop.reset` | `ids!` | 每张一步（回默认+最新 process） |
| `develop.copy` | `id!` | 不记（填剪贴板，`ClipboardChanged`） |
| `develop.paste` | `ids!` | 每张一步（整份替换，目标 process 不变；空剪贴板错） |
| `develop.beginInteraction` | `id!` | 不记 |
| `develop.updateInteraction` | `id!` `module!` `patch!` `multi?` `enabled?` | 不记（live 值；无交互错；发 `PhotoChanged`） |
| `develop.endInteraction` | `id!` | 变了记一步（标签 `develop.endInteraction`），无交互静默成功 |
| `develop.cancelInteraction` | `id!` | 不记（恢复拖前；无交互静默成功） |
| `history.undo` / `history.redo` | `id!` | 不记（游标动；无处可去为 `Disabled`） |
| `history.goto` | `id!` `index!` | 不记（越界为 `BadParam`） |
| `process.update` | `ids!` | 过时才记一步（最新照片零步） |
| `job.cancel` | `job!` | 不记（置取消旗；空表 `Disabled`，无此作业 `JobNotFound`） |

模块校验：`module` 经注册表（或测试注入的 `set_param_lookup`）取 `ParamsDesc`，有字段按字段验（错型/越界为 `BadParam`），无字段全收，未登记参数名直通保留——与 A4b 同规则。
会话类命令本波零登记（`session.*`/`library.*`/`photo.*`/`export.*` 等 B12′ 后逐条加）。

## 4. 草稿会话、作业、事件、快照

- **草稿会话**：`Engine::new()` 无会话（改命令全拒）；`Engine::open_draft(ids)` 全内存开会话，无持久化（文档注明 B12′ 后由会话命令开正式会话）。
- **作业**（`jobs.rs`，取自 LightCraft `activity.rs` 改造）：固定 4 线程 FIFO 池（`POOL_SIZE` 常量，测试钉死）；作业只拿不可变快照+`JobCtx`（取消旗+进度 sender）；进度/完成经结果队列由 `collect()`（引擎线程）收成事件；取消=置旗+下块边界自查，完成事件带 `cancelled`；作业表（id/kind/label/状态/done/total）可读，终态行保留；`Drop` 先置全部未完旗再跳过排队、join 运行中，无孤儿线程。本波无启动作业的用户命令，覆盖靠合成作业测试（求和分块报进度、门控取消、panic 变 `Failed` 且池存活、drop 即返）。
- **事件**：`PhotoChanged{photo,steps,cursor}`/`ClipboardChanged`/`JobStarted{job}`/`JobProgress{job,done,total}`/`JobFinished{job,success,cancelled}`；一调用攒序、成功后一次送、失败零送；监听者可登记/注销，各收一次。
- **快照**：`photo_settings/labels/cursor/len`、`jobs/job`、`has_session/has_clipboard/photo_ids`，均为便宜克隆。

## 5. 五/六行命令文件

`/tmp/A7a-five.jsonl` 原文（模块标识取自注册表运行时第一项 `rawprepare`，由 shell 读夹具得来，未进 Rust 源码）：

```jsonl
{"id": "develop.set", "params": {"ids": ["p1"], "module": "rawprepare", "patch": {"p_gain": {"type": "float", "value": 1.5}}}}
{"id": "history.undo", "params": {"id": "p1"}}
{"id": "history.redo", "params": {"id": "p1"}}
{"id": "history.goto", "params": {"id": "p1", "index": 0}}
{"id": "develop.paste", "params": {"ids": ["p1"]}}
```

`target/debug/dt-cli run --file /tmp/A7a-five.jsonl --photos p1` 输出（exit=1）：

```text
line 1: develop.set ok outcome={"updated":1} photos=[p1:2:1] digest=9734988588720734966
line 2: history.undo ok outcome={"cursor":0} photos=[p1:2:0] digest=6191755046607852097
line 3: history.redo ok outcome={"cursor":1} photos=[p1:2:1] digest=9734988588720734966
line 4: history.goto ok outcome={"cursor":0} photos=[p1:2:0] digest=6191755046607852097
line 5: develop.paste FAIL develop.paste: the clipboard is empty photos=[p1:2:0] digest=6191755046607852097
dt-cli: check failed: 1 of 5 lines failed
```

手算核对：L1 记一步→2:1；L2/L4 游标 0；L3 回 1 且 digest 与 L1 逐位同（同态同值）；L5 剪贴板空按 §3 失败、状态与 L4 同值。两次运行 md5 相同（`71afef7ab28ef98cf9a4578f2aeeab4f`），省略 `--photos` 靠文件扫描同样结果。
说明：第 5 条 `paste` 在此文件里**注定失败**（此前无 `copy`，剪贴板空是规定的错误），`run` 的语义是逐条全跑、失败计入、非零退出——“走通”指五条皆可执行、步数/位置/汇总值与手算一致。
坏模块复跑（首行模块换 `__no_such_module__`）：`FAIL ... unknown module`，`photos=[p1:1:0]`，exit=1。
六行成功变体（set/copy/paste/undo/redo/goto）：6 行全 ok，paste 后 `p1:3:2`，redo 后 digest 与 paste 行同值，exit=0。

## 6. 新增依赖与取用

- 新依赖边：`dt-engine → dt-history/dt-iop-traits/dt-registry/serde/serde_json`，`dt-cli → dt-engine/serde_json`（`cargo tree --depth 1` 实测）。外部只 `serde 1.0.229` + `serde_json 1.0.154`，均已在审计表 §4 登记且版本逐字同，锁文件只增边、无新增 crate；`licenses-allow.txt` 未动（`MIT OR Apache-2.0` 已在），作业池纯标准库。
- 取用 LightCraft（commit `0da998f2`，文件头均有 `Derived from` 行，`NOTICE` 已按 T-F10 N1 追加 A7a 条目）：`command.rs <- cmd/mod.rs`（改造）、`engine.rs <- lib.rs`（`execute`/`commit`/撤销重做/拖动合并，改造）、`jobs.rs <- activity.rs`（改造）。
- `docs/LICENSE-AUDIT.md` 追加 §11 采用记录（无新表行）；`crates/README.md` 只改 `dt-engine`/`dt-cli` 两行。

## 7. 第 10 节验收（命令与输出）

- `cargo test -p dt-engine --locked`：44 passed（契约/每命令/作业/事件各有命名测试；原子性按 13 命令×3 坏参数；全文无 dt 模块名，真实标识一处运行时取首项）。
- `cargo test -p dt-cli --locked`：34 passed（含 `commands` 列出/单查/未知、`run` 执行+失败计数+坏模块+缺文件、`scan_photo_ids`）。
- 口径 clippy（六 `-D`）：`dt-engine` 本体零命中；命令整体被 A3 的四个 `crates/dt-iop-*/build.rs:35,51`（`panic!`/`expect`）拖红——越界文件，本波无权改（见“未做”）。等价证据：crate 根 `#![deny(六条)]` 常开 + `cargo clippy --workspace --all-targets -- -D warnings` 绿。
- `rg -n 'thread::spawn|thread::Builder|spawn\(' crates/dt-engine/src`：仅 `jobs.rs:166,168` 两处（池创建）。
- `rg -n 'std::fs|File::|std::net|TcpStream' crates/dt-engine/src`：无输出（exit=1）。
- `cargo xtask layers`：`OK: 28 crates, no layering violations.`；`check-no-iop-names`：`OK (97 names, 4 roots clean)`；`check-apple-boundary`：`OK: 28 crates, 153 rust files, no Apple-boundary violations.`；`check-order-sync`：`OK (97 modules, ...)`。
- `Scripts/check-licenses.sh`（无参数）：exit=0。
- `cargo test --workspace --locked`：180 passed = 132 + 48（`dt-engine` 43 新 + `dt-cli` 5 新；`#[test]` 行数对过）。
- `Scripts/rust-ci-lite.sh`：`rust-ci-lite: ALL GREEN`。
- 保护路径：`git diff --stat 1fcbbeab -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures crates/dt-history` 无输出；`dt-history` 零改（`params_for` 只读其 API，未动它；无缺件要报）。
- CLI 回归：`help` 含 A5 五子命令 + `capabilities` + 新两项；`capabilities` 首行 `backend=macos`、`metal.device=Apple M4` 照常。
- `git show --name-only HEAD`：见 §8（仅允许路径）。

## 8. 提交

commit（一个，`refs #32`，零 push）：`<hash 见 log>`。

```text
git show --stat HEAD
（落盘后填）
```

路径：`crates/dt-engine/**`、`apps/dt-cli/{Cargo.toml,src/lib.rs,src/main.rs,src/commands.rs}`、`Cargo.lock`、`crates/README.md`、`docs/LICENSE-AUDIT.md`、`NOTICE`、本报告、`A7a-review.log`。

## 9. 未做 / 未验

- **未做**：口径 clippy 命令整体变绿——卡在 A3 四个 `build.rs` 的 `panic!`/`expect`（越界路径，不敢动）。`dt-engine` 本体在该口径下零命中（输出可 grep 验证），且 crate 根 deny 等价覆盖。
- **未做**：`session.*` 等会话类命令（计划内，B12′ 后逐条加）；启动作业的用户命令（本波无真实后台活，按计划不登记）。
- **未验**：非 macOS 目标编译（本机单目标，纪律禁装；`dt-engine` 无平台相关代码，风险低）。

## 10. 修订记录（自审回注）

（复审后填）
