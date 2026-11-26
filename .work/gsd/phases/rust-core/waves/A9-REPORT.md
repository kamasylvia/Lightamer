# A9 Lint and Doc Closure

结论头：六条不崩溃 lint 对整个工作区变绿并进总检查，7 条文档警告清零；192 测试全绿，cli 十余项输出逐字节不变，ci-lite 全绿。

起始 HEAD（亲核，2026-11-26）：`285d792327838a07f2222ebc792c0c69bdbac4af`
（`docs(rust-core): record the A8 verification`；A8 本体 `957d9110`）。

构建前守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=53% swap=?M disk=?GB)`。
并行度：`CARGO_BUILD_JOBS=6`；一次只跑一个重活；未用 `caffeinate`。

## 1. 动手前的底数（逐条重测）

- 六条 lint 全工作区（`cargo clippy --workspace --all-targets --locked -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented`）：exit=101，`^error` 51 行＝48 处命中＋3 行 could-not-compile 汇总。其中注册表 24 处（`src/lib.rs` 122–251 行 23 处，全在 `#[cfg(test)]` 模块内；`tests/discovery_probe.rs:27` 1 处 `panic!`），`xtask` 24 处（`iop_order.rs` 10、`layers.rs` 5、`main.rs` 4、`no_names.rs` 2、`gen_stubs.rs` 2、`sync.rs` 1）。按 lint：indexing 23、slicing 8、expect(Option) 9、expect(Result) 7、panic 1；unwrap/todo/unimplemented 零命中。
- 关键口径：第一遍只查了 22 个 crate（`grep -c Checking`），cargo 遇失败即不再起新单元——`lightamer-cli`、`lightamer-gpui`、四个 `lightamer-iop-*`、`lightamer-merge` 根本没被查到（与 A7a 的构建脚本遮挡同机制）。所以塔台的「xtask 约 80 处」「cli 库旧存量」在第一遍里看不见：cli 的 4 处生产命中（下 §3）是声明补齐后第二遍（28 个全查）才露出来的；xtask 的 24 是 `--all-targets` 下的实测数。
- 注册表生产代码（`src/lib.rs:1–70`）：零命中，干净，与塔台一致。
- 空壳 crate 根部：除历史/引擎/Apple/界面四家已有六条声明外，其余 22 个产品 crate（含注册表）根部均无声明；`testkit` 持有其中五条（缺 `indexing_slicing`）。
- `cargo doc --workspace --no-deps --locked`：exit=0，7 条警告（`^warning` 9 行含 2 行汇总）：历史 2 条（`history.rs:10,36` 冗余显式链接目标）、引擎 5 条（`lib.rs:48` 未解开的 `RunCtx`、`command.rs:11` 指向私有项 `crate::develop`/`crate::history` 各 1、`error.rs:4`、`jobs.rs:15` 冗余显式链接目标各 1）。与塔台一致。
- `lightamer-cli` 改前快照（`cargo build -p lightamer-cli --locked`，1m45s；命令文件按 A7a 报告 §5 五/六行节重建为 `/tmp/A9-five.jsonl`）：

| 用法 | exit | stdout md5 |
|---|---|---|
| `help` | 0 | `946bec582e85c041864056826582d610` |
| `capabilities` | 0 | `6df1f547af5126cb690a3bb0c6dad13a` |
| `commands` | 0 | `2cdd2665d5df312e9852a5b4a8f79947` |
| `commands develop.set` | 0 | `6feee898e9f975f80ceb539faab865d1` |
| `run --file /tmp/A9-five.jsonl --photos p1` | 1 | `52434d6579faa286416c24f0aaaac78b` |
| `cmp NeutralTarget.png NeutralTarget.png` | 0 | `b21dccec83e4803c3f187e4624deacf4` |
| `cmp NeutralTarget.png sample-gradient.png` | 2 | （空，geometry mismatch 走 stderr） |
| `cmp … --tol 0.01 --max-mean 1 --min-in-tol 0.5` | 2 | （同上） |
| `cmp /tmp/A9-nope.png NeutralTarget.png` | 2 | （空，missing file 走 stderr） |
| `cmp NeutralTarget.png NeutralTarget.png --mirror-x` | 0 | `14e9b0e43554e7c45d6b49b12f797f1d` |
| `frobnicate`（未知子命令） | 2 | （空） |

`run` 输出与 A7a 手算逐行一致（含 `digest=9734988588720734966` / `6191755046607852097` 与第 5 行剪贴板空 FAIL）。

## 2. 规则原文（`crates/README.md` 新增节）

（见文件 `## 不崩溃的 lint 规则（A9 收口）`：产品 crate＝层表 L0–L5 共 26 个，库根六条拒绝，测试模块放开前三条，`panic!/todo!/unimplemented!` 测试同样禁止；`testkit` 辅助代码按测试代码对待（现持有全部六条）；新 crate 建出来就带；`xtask` 整 crate、`lightamer-cli` 二进制入口、四域 `build.rs` 豁免且根部写理由；`lightamer-cli` 库按产品对待；检查口径即六条 lint 命令行。）

## 3. `lightamer-cli` 库逐条改写

生产代码 4 处（cli 库此前无根部声明，全靠第二遍 lint 扫出；测试模块 7 个文件补标准放开行，`commands.rs` 已有）：

1. `cmp.rs:139` `u16::from_be_bytes([pair[0], pair[1]])` → `u16::from_be_bytes(*pair)`。输出逐字节相同（`as_chunks::<2>` 的项本就是 `[u8; 2]`）。
2. `cmp.rs:243–246` 四处下标 → `.get()/.get_mut()`＋`Error`（新增 `short_image`/`short_accumulator` 两个构造器，`format!` 经 `cargo fmt` 排版）。正常路径（`read_png` 构造的满样本图）输出逐字节相同；**出错路径变化**：`compare_images` 被直接传入样本不足的 `Image` 时，以前下标越界崩溃，现在返回 `Error("short image: sample {i} missing ({len} samples)")`，经 `main` 的 `From<util::Error>` 映射为 `lightamer-cli: error: …`＋退出码 2。`short_accumulator` 分支按构造不可达（两 vec 建出来就是 `channels` 长），属防御性错误。
3. `util.rs:83` `&bytes[start..]` → `bytes.get(start..).unwrap_or_default()`。输出相同（`start = len.saturating_sub(max) ≤ len` 恒成立，`None` 分支不可达）。
4. `xmp.rs:123–124` `DIGITS[…]` → 新增 `hex_nibble`（`match` 算术：`0..=9 → b'0'+n`，`_ → b'a'+(n-10)`）。输出相同（输入恒为 4 位半字节）；`emit-xmp` 字节稳定性由既有 golden 测试覆盖。

测试代码 2 处（`panic!` 在测试里不放开，改写法不加豁免）：

5. `selftest.rs:386` `_ => panic!("bad group")` → `unknown` 计数＋`assert_eq!(unknown, 0, "bad group")`。
6. `xmp.rs:198` `.unwrap_or_else(|_| panic!("missing {name}"))` → `assert!(text.is_ok(), "missing {name}")`＋`text.unwrap_or_default()`，失败信息不变。

二进制入口 `main.rs`：只加根部豁免及理由，一行逻辑未动。
出错路径崩→错的变化共 1 条（第 2 条的 `short_image`；`short_accumulator` 不可达）：以前是进程崩溃（exit 101），现在是一句 stderr＋退出码 2。

## 4. 注册表 crate 与探针

- `src/lib.rs`：生产代码经第一遍 lint 确认零命中，未动；根部加六条声明，测试模块加标准放开行。
- `tests/discovery_probe.rs:27` `panic!("bad LIGHTAMER_DISCOVERY_PROBE={other}")` → `assert!(["present", "absent"].contains(&other), "bad LIGHTAMER_DISCOVERY_PROBE={other}")`。测试语义不变（坏值仍失败，信息相同），消掉全工作区唯一的 `panic` 命中。该文件属第 3 节「注册表 crate 按第 3 节」的测试放开范围。

## 5. 文档 7 条各改了什么（只动文档注释）

1. `history.rs:10` `[`Arc`](std::sync::Arc)` → `[`Arc`]`（`use` 在作用域，显式目标冗余）。
2. `history.rs:36` 同上。
3. `engine/lib.rs:48` `[`RunCtx`]`（作用域内无此名）→ `[`command::RunCtx`]`（公开路径）。
4. `engine/command.rs:11` `[`develop`][crate::develop]` → `` `develop` ``（私有项改代码字体，不公开）。
5. 同行 `[`history`][crate::history]` → `` `history` ``（同上）。
6. `engine/error.rs:4` `[`Display`][std::fmt::Display]` → `[`Display`]`（已 `use`，冗余）。
7. `engine/jobs.rs:15` `[`Event`][crate::Event]` → `[`Event`]`（冗余）。

无任何类型因文档由私转公。

## 6. 第 8 节验收（命令与输出）

- 底数重测：见 §1（clippy 第一遍 exit=101，48 处命中，22/29 查到；doc 7 警告；快照 11 项）。
- `cargo clippy --workspace --all-targets --locked -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented`：exit=0，`^error` 0 行（第三遍；第二遍查到全部 28 个 crate 并扫出 cli 库最后 2 处，修后本遍绿）。
- `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --locked`：exit=0，`warning` 0 行。
- `cargo test --workspace --locked`：exit=0，`passed=192 failed=0`（`grep ^test result` 加总；≥192 ✓，与 A8 持平）。
- cli 快照比对：重建后 11 项（help、capabilities、commands、commands develop.set、run、cmp 同文件/cmp 跨文件/cmp 缺文件/cmp 带阈值/cmp mirror-x、未知子命令）的 stdout、stderr、退出码与改前逐字节比对，全同（`SNAP-IDENTICAL-11`）。
- 26 产品 crate 库根声明：`for c in <L0–L5 共 26 名>; do grep -q indexing_slicing && grep -q unimplemented && echo $c; done | wc -l` → `26`。
- `cargo xtask layers` → `OK: 29 crates, no layering violations.`；`check-order-sync` → `OK (97 modules, …)`；`check-no-iop-names` → `OK (97 names, 4 roots clean)`；`check-apple-boundary` → `OK: 29 crates, 155 rust files, no Apple-boundary violations.`；`Scripts/rust-apple-boundary.sh` → exit=0（`STEP 7/7 PASS … ALL GREEN`）。
- `cargo check --workspace --exclude lightamer-gpui --all-targets --target x86_64-unknown-linux-gnu --locked`：exit=0，`^warning` 0 行。
- `Scripts/rust-ci-lite.sh`：exit=0，`rust-ci-lite: ALL GREEN`；新两步在日志中按序可见（902 行 layers OK → 903 行起 clippy-six `Checking…`/`Finished 41.72s` → doc `Generated …/target/doc/…` → 936 行 apple-boundary）。
- 保护路径：`git diff --stat 285d7923 HEAD -- 'crates/lightamer-iop-*/src/modules' crates/lightamer-registry/fixtures` → 空；引擎＋历史 diff 新增行全为 `//` 注释（`grep -vc '^\+//'` → 0）。
- `git show --name-only HEAD`：见 §7（仅允许路径）。
- 通用纪律：`cargo fmt --all --check` 绿；`cargo clippy --workspace --all-targets --locked -- -D warnings` exit=0。

## 7. 提交

（提交后填哈希。）

## 8. 复审结论头

（自审实例结论落盘后填。）

## 9. 未做 / 未验

未做：本波 7 项无未做。两处经实测无需动手：一是四个域 `build.rs`，第二遍 lint 证实除 A8 已豁免的 `expect_used`/`panic` 外零命中，不在允许路径内也无需进；二是 `testkit` 的测试模块不加放开行，该模块测试本就避开 unwrap/expect/indexing（文件头有述），加放开反而放宽其既有标准——`testkit` 现以产品条（六条拒绝、无放开）持有。

未验：`render/selftest/fetch` 需官方 DMG 挂载与 `darktable-cli` 的端到端路径未跑（与历波一致；cli 快照覆盖 help/capabilities/commands/run/cmp，单测覆盖其余）；Linux 真机运行未验（只做到 `--target x86_64-unknown-linux-gnu` 检查零警告，与 A6/A7b 口径一致）；`compare_images` 新 `short_image` 错误分支无单测（属防御性分支，正常构造不可达；行为变化见 §3 第 2 条）。
