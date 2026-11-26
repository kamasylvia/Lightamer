# A8 Rename Report: `dt-*` → `lightamer-*`

结论头：改名完成，192/192 测试逐项一致，四项 xtask 检查与四脚本全绿；`--workspace` Linux 目标检查因缺交叉 gcc 失败（与 A7b 同因、同范围，改名前即如此，非改名引入）。

- 起始 HEAD：`bd6c36e8d6b5a2eae77438fe9d6802ffabcd1c57`（亲核，`git rev-parse HEAD`）。
- 提交：见末节「提交」（正文哈希格为提交时值，amend 填本行后最终值见末尾注记）。

## 1. Name Mapping（29 行）

| # | 改名前（包名 = 目录名） | 改名后 | 层 |
|---|---|---|---|
| 1 | `dt-geom` | `lightamer-geom` | L0 |
| 2 | `dt-raster` | `lightamer-raster` | L0 |
| 3 | `dt-color-math` | `lightamer-color-math` | L0 |
| 4 | `dt-iop-traits` | `lightamer-iop-traits` | L0 |
| 5 | `dt-sysmem` | `lightamer-sysmem` | L0 |
| 6 | `dt-iop-raw` | `lightamer-iop-raw` | L1 |
| 7 | `dt-iop-geom` | `lightamer-iop-geom` | L1 |
| 8 | `dt-iop-color` | `lightamer-iop-color` | L1 |
| 9 | `dt-iop-display` | `lightamer-iop-display` | L1 |
| 10 | `dt-meta` | `lightamer-meta` | L1 |
| 11 | `dt-color` | `lightamer-color` | L1 |
| 12 | `dt-blend` | `lightamer-blend` | L1 |
| 13 | `dt-decode` | `lightamer-decode` | L1 |
| 14 | `dt-scenes` | `lightamer-scenes` | L1 |
| 15 | `dt-registry` | `lightamer-registry` | L2 |
| 16 | `dt-history` | `lightamer-history` | L2 |
| 17 | `dt-pipeline` | `lightamer-pipeline` | L2 |
| 18 | `dt-catalog` | `lightamer-catalog` | L3 |
| 19 | `dt-preview` | `lightamer-preview` | L3 |
| 20 | `dt-apple` | `lightamer-apple` | L3 |
| 21 | `dt-gpu` | `lightamer-gpu` | L3 |
| 22 | `dt-merge` | `lightamer-merge` | L3 |
| 23 | `dt-lightamer` | `lightamer-ai`（唯一例外，见 §5） | L3 |
| 24 | `dt-engine` | `lightamer-engine` | L4 |
| 25 | `dt-gpui` | `lightamer-gpui` | L5 |
| 26 | `dt-mcp` | `lightamer-mcp` | L5 |
| 27 | `dt-testkit` | `lightamer-testkit` | testkit |
| 28 | `dt-cli`（`apps/dt-cli`） | `lightamer-cli`（`apps/lightamer-cli`，二进制同名） | exempt |
| 29 | `xtask` | `xtask`（不动） | exempt |

目录改名 28 次 `git mv`（27 个 `crates/dt-*` + `apps/dt-cli`），状态里 185 条 R/RM 记录。

## 2. Inventory（改名前，HEAD 侧亲测）

包名扫描（验收口径，`git grep -P -o`）：

```
$ P='\bdt-(apple|blend|catalog|cli|color|color-math|decode|engine|geom|gpu|gpui|history|iop-[a-z]+|lightamer|mcp|merge|meta|pipeline|preview|raster|registry|scenes|sysmem|testkit)\b'
$ git grep -P -o "$P" HEAD -- crates apps Scripts docs NOTICE fixtures Cargo.toml Cargo.lock | wc -l
421
```

分区域（文件数 / 出现数，命令同上加 `-- <区>`）：

| 区域 | 文件 | 出现 | 备注 |
|---|---|---|---|
| `crates/` | 40 | 252 | 清单 27 + 源码/文档注释 |
| `apps/` | 8 | 21 | 清单 1 + 7 个源文件 |
| `Scripts/` | 6 | 59 | oracle.sh/lock、apple-boundary、budget、discovery-probe、gui-viewport-probe |
| `docs/` | 2 | 34 | APPLE-BOUNDARY 22、LICENSE-AUDIT 12（按波次登记的采用记录，改名后重述） |
| `fixtures/` | 1 | 2 | fixtures/oracle/README.md |
| `NOTICE` | 1 | 6 | 三条 LightCraft 记录的路径 |
| 根 `Cargo.toml` | 1 | 1 | 注释里一句 `dt-decode` |
| `Cargo.lock` | 1 | 46 | 由 cargo 重算，非手改 |
| 根 `README.md` / `AGENTS.md` | 0 | 0 | 无 crate 名句子，零改动（`AGENTS.md` 仅一处 `dt-verbatim`，指 darktable 逐字节，保留） |
| 合计 | 60 | 421 | |

分包名（`rg -o`，不含锁文件，合计 375；扫描正则的 `color` 分支先于 `color-math`，故 `dt-color-math` 被计入 `dt-color` 行，实际拆分 `dt-color-math` 8、`dt-color` 3）：dt-apple 64、dt-gpui 46、dt-cli 38、dt-iop-traits 23、dt-engine 23、dt-registry 22、dt-testkit 18、dt-history 17、dt-geom 13、dt-pipeline 12、dt-color（含 math）11、dt-iop-raw 10、dt-iop-color 9、dt-decode 9、dt-raster 8、dt-meta 8、dt-iop-display 8、dt-iop-geom 5、dt-preview/dt-mcp/dt-gpu/dt-catalog 各 4、dt-sysmem/dt-scenes/dt-merge/dt-lightamer/dt-blend 各 3。

标识符 `dt_*::`（`git grep -o '\bdt_[a-z_]*::'`，`crates apps`）：541 处，116 文件（crates 113 + apps 3）。分项：dt_iop_traits 502、dt_apple 13、dt_history 9、dt_registry 6、dt_engine 3、dt_testkit 2、dt_cli/dt_gpui/dt_iop_color/dt_iop_display/dt_iop_geom/dt_iop_raw 各 1。

环境变量（`rg -n '\bDT_[A-Z_]+' crates apps Scripts`）：5 处，2 文件，全部是 `DT_DISCOVERY_PROBE`（`crates/dt-registry/tests/discovery_probe.rs` 3 处 + `Scripts/rust-discovery-probe.sh` 2 处）→ `LIGHTAMER_DISCOVERY_PROBE`。

扫描正则之外的同族（逐项确认后一并改）：`dt-iop-{domain}`/`{other}` 格式串 5 处（gen_stubs.rs 4、sync.rs 1）；临时目录/进程标签 `dt-cli-*`（9 处）、`dt-oracle-run[-*]`/`dt-oracle-selftest`（6 处，残留扫描不覆盖但同属我方前缀）、`dt-testkit-*`（2 处）、`dt-engine-job-`（1 处）、`dt-gpui-probe`/`fullshots`（2 处）；测试名 `live_values_come_from_dt_apple`、`binary_name("dt_engine-…")` 各 1 处。

不许改的名字（改后复核数，与 HEAD 一致）：`dt-order-` 12（含文件名 `dt-order-679d594f5d.json`）、`refs/dt-master` 6、`dt_iop_order_entry_t` 2、`dt_iop_exposure_params_t`/`dt_iop_flip_params_t`/`dt_iop_colorspace_type_t`/`dt_image_orientation_t`/`dt_bauhaus_toggle_set_default` 各 1、`dt_group_and_tags` 2（解析 darktable 分组，dt 指 darktable）、`DtParamsEncoder` 9、`darktable-cli` 12、`dt-core`/`dt-library`/`dt-api`/`dt-app`/`dt-export` 各 1（`crates/README.md` 里 A3R 历史）、`dt-derived` 2/`dt-era` 3/`dt-only` 1（parity-checklist 的 darktable 时代措辞）、`dt-verbatim`（根 AGENTS.md）1、`DT=`（ORACLE-BASELINE 指向 darktable 树的变量）1、`docs/ORACLE-BASELINE.md` 零 crate 名命中故全文不动、layers.rs 测试夹具虚构名 `dt-mystery`/`dt-lone`/`dt-ghost`（非 crate 名，不动）。

## 3. Method

1. `git mv` 28 个目录（§1）。
2. 定序 perl 替换（273 文件，`crates apps Scripts docs fixtures NOTICE Cargo.toml`，`*.rs/toml/md/sh/txt/lock/swift`，排除顺序夹具 JSON）：`dt-lightamer→lightamer-ai` → `dt-lightamer→lightamer_ai` → 裸 `dt-iop-` → 包名正交（`color-math` 先于 `color`、`gpui` 先于 `gpu`，`\b` 收尾）→ 标识符白名单（仅 28 个自有 crate 的 `dt_*`，X 域仅 traits/raw/geom/color/display 五项，darktable 的 `dt_iop_*_t` 不在表内）→ `dt-oracle-` → `DT_DISCOVERY_PROBE`。`Cargo.lock` 由 cargo 重算。
3. 事故与恢复：第一遍 perl 把 `do file or die` 写错（`do` 返回末行替换数，零匹配即 die），配合 `-i` 把每批第一个文件截空，共 7 个（NOTICE、根 Cargo.toml、LICENSE-AUDIT、fixtures/oracle/README、rust-budget.sh、merge 与 cli 的清单）。发现后从 HEAD 逐个恢复并重跑替换；随后全仓 203 个改动文件逐个验行数与 HEAD 一致（`bad=0`），并做逆映射证明：新内容经逆替换后与 HEAD 逐字节相等的文件 201 个，另 2 个（gen_stubs.rs、sync.rs）仅因 `{domain}` 格式参数使证明正则失效，人工逐行核对 11 组 diff 全是纯改名。
4. `cargo fmt --all` 一次（改名拉长行宽与 `use` 排序，7 文件机械重排：selftest、gpui lib/main、testkit lib、apple_boundary、gen_stubs、layers）。
5. build.rs 豁免、lightamer-ai 文档注、NOTICE 三句（§5）。

## 4. The Small Fix（A7a 缺口，build.rs 豁免）

四文件（`crates/lightamer-iop-{raw,geom,color,display}/build.rs`）顶部 SPDX 行之后各加一行，逻辑零改：

```rust
#![allow(clippy::expect_used, clippy::panic)] // Build scripts report failure via panic/expect; that is cargo's normal build-error path.
```

只豁免六条里命中的两条（`rg -n 'panic!|expect' crates/lightamer-iop-*/build.rs` = 4 文件 ×4 处 = 16 处，与 A7a 报数一致；`unwrap`/`indexing_slicing`/`todo`/`unimplemented` 零命中）。

A7a 口径命令（`-p lightamer-engine`，其依赖链把四份 build.rs 编进来）：

```
$ cargo clippy -p lightamer-engine --locked -j6 -- -D clippy::indexing_slicing -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic -D clippy::todo -D clippy::unimplemented
    Checking lightamer-engine v0.1.0 (.../crates/lightamer-engine)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 2.24s
ENGINE_SIX_EXIT=0
$ cargo clippy -p lightamer-iop-color -p lightamer-iop-raw -p lightamer-iop-geom -p lightamer-iop-display --locked -j6 -- <同上六开关>
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.06s
IOP_SIX_EXIT=0
$ touch crates/lightamer-iop-color/build.rs && cargo clippy -p lightamer-iop-color --locked -j6 -- <同上六开关>
   Compiling lightamer-iop-color v0.1.0 (...)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.30s
FORCED_EXIT=0
```

说明：`--workspace` 口径（含 `--all-targets` 与否）在改名前后都不是绿的——xtask 主程序 24 处、lightamer-cli 库 7 处生产代码 `unwrap` 等均为历史存量（A7a 只要求 `-p dt-engine` 口径），任务书「只许动这一处」禁止顺手修，故不碰，数字如实记录。

## 5. Naming Notes

- `dt-lightamer` → `lightamer-ai`：`crates/lightamer-ai/src/lib.rs` 文档注释加一行 `Named lightamer-ai, not lightamer-lightamer: this crate holds Lightamer's own AI features, and the mechanical rename would stutter.`。引用点仅三处（自身清单、layers.rs TABLE、crates/README.md 表行）。
- `NOTICE` 三条 LightCraft 记录路径已更新，各加一句「文件于 2026-11-26 由 `dt-` 前缀改名为 `lightamer-` 前缀」。
- 二进制 banner 与 `argv` 风格前缀随二进制改名（`lightamer-cli: …`、`usage: lightamer-gpui …`），描述语里的 `darktable`（对照对象）保留。

## 6. Acceptance

- 守卫（构建前）：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=72% …)`，后一批重跑 `GUARD PASS (heavy=0 free=75% …)`。并行度 `-j6`。
- 测试：改名前 `cargo test --workspace --locked -j6` = 192 通过（60 个 `test result: ok`；单测/集成 188 + doctest 4：apple/history/registry 各 1、testkit compile 1）。改名后同命令 `EXIT=0`，60 行 ok，`passed-sum=192`；逐 target 对照程序（名归一后 diff）仅 `lightamer-ai` 一项因包名字母序提前一位，其余行全同，计数逐个相同。
- `cargo fmt --all --check` 干净；`cargo clippy --workspace --all-targets --locked -j6 -- -D warnings` 退出 0。
- Linux 目标：`cargo check --workspace --all-targets --target x86_64-unknown-linux-gnu --locked` **失败**，唯一原因 `failed to run custom build command for wayland-backend v0.3.17` / `failed to find tool "x86_64-linux-gnu-gcc"`——与 A7b 核验记录逐字同因（gpui 的 Linux 后端要 C 交叉编译器，本机无，纪律禁装）。改名前即如此，非改名引入。A7b 修订口径 `cargo check --workspace --exclude lightamer-gpui --all-targets --target x86_64-unknown-linux-gnu --locked` 退出 0，`grep -ci warning` = 0。
- xtask 四项：`layers` → `OK: 29 crates, no layering violations.`（表内新名可见）；`check-order-sync` → `OK (97 modules, fixture …/crates/lightamer-registry/fixtures/dt-order-679d594f5d.json)`；`check-no-iop-names` → `OK (97 names, 4 roots clean)`（输出本无 crate 名，新旧一致）；`check-apple-boundary` → `OK: 29 crates, 155 rust files, no Apple-boundary violations.`。
- 脚本：`rust-apple-boundary.sh` 7 步 ALL GREEN（含第 7 步真编 lightamer-apple）；`rust-discovery-probe.sh` present/absent 双 PASS、工作区复原（`zz_probe` 零残留）；`rust-ci-lite.sh` ALL GREEN（内含 tests total passed=192）；`rust-budget.sh` overall PASS（ui rebuild 63s≤180s、check 0s≤40s、target 9225MB≤20GB；release/cold 两项 N/A-SKIP，与 A7b 同口径）。
- 二进制：`target/debug/lightamer-cli help` 8 子命令（fetch/render/cmp/emit-xmp/selftest/capabilities/commands/run，与改名前 `dt-cli` 一一对应）；`capabilities` 输出 backend=macos、Metal Apple M4、ImageIO 五值、CIRAW/Vision/色彩空间行照常。
- 六 lint：见 §4（A7a 口径绿；workspace 口径历史存量红，非本波范围）。
- rustdoc：`cargo doc --workspace --no-deps --locked` 7 警告（engine 5 + history 2：`RunCtx` 未解链、私有项链接、冗余显式目标）；HEAD worktree 对照跑出**完全相同**的 7 条（仅 crate 名 dt→lightamer 不同），改名零新增断链。
- `git mv`：提交后 `git log --follow --oneline -- crates/lightamer-history/Cargo.toml` 可追到 `crates/dt-history` 时期；另抽 `apps/lightamer-cli` 与一模块桩各验一次（输出见 §7；registry 小清单阈值注记亦在 §7）。
- 桩与夹具内容：顺序夹具 JSON 新旧路径逐字节相同（8789 字节）；97 个模块桩逐文件证明 `HEAD内容经dt_iop_traits→lightamer_iop_traits替换 == 新内容`（`checked=97 bad=0`），语义载荷（模块名、prio、tie）零差。
- 路径审计：`git show --stat HEAD` 仅含纪律允许路径（crates、apps、根 Cargo.toml/lock、6 脚本、docs 2 文件、NOTICE、fixtures/oracle/README、本报告）。

## 7. Commit

- message：`refactor(rust): rename dt-* crates to lightamer-*` + body（含 `refs #32`），逐路径 `git add`，零 push。
- 哈希（提交时 `c569c782c75a5b16abdc1b8692fb71245ba66588`；回填本行后 amend 一次，最终以 `git log` 为准，见 §10）。
- `git show --stat` 汇总：216 文件（185 重命名 + 原地修改 + 本报告新增），`+1316 -1055`，路径审计见 §6（仅纪律允许路径）。
- `git log --follow` 三抽查输出（提交时亲核）：
  - `crates/lightamer-history/Cargo.toml`：`c569c782 refactor(rust)` → `52a24bd7 feat(history)` → `097890cb feat(rust-core)`（追到 `dt-history` 时期 ✓）。
  - `apps/lightamer-cli/Cargo.toml`：`c569c782` → `93374d61` → `bbd08a76` → `ccc60b9f` → `6bfed45d` → `097890cb`（追到 `dt-cli` 时期 ✓）。
  - `crates/lightamer-iop-raw/src/modules/invert/mod.rs`：`c569c782` → `aeb52d78`（追到桩生成时 ✓）。
  - 注：`lightamer-registry/Cargo.toml` 等小清单因 7/20 行含包名、相似度低于默认阈值，`--follow` 需 `--find-renames=30%` 才连通（`c569c782` + 旧径 3 提交）；改名本身为 `git mv`，旧径历史见 `git log c569c782^ -- crates/dt-registry/Cargo.toml`。此为 git 启发式行为，非断链。

## 8. Self Review

结论头：REVIEW_HEADER_TBD（详见 `A8-review.log`）。

## 9. 未做 / 未验

未做：`--workspace` 含 gpui 的 Linux 目标检查仍红（缺 `x86_64-linux-gnu-gcc`，与 A7b 同因；需 Linux 机或交叉工具链，不在本波）；workspace 口径六 lint 的历史存量（xtask 24、cli 库 7 等）未修（任务书禁动）；`docs/ORACLE-BASELINE.md`、根 `README.md`/`AGENTS.md` 零 crate 名命中故零改动；`.work/` 下除本报告与复审日志外未碰（阶段 B 计划另有专人）。

未验：Linux 真机行为；HDR 屏 EDR 效果（A7b 遗留）；冷构建耗时（ci-lite/budget 均为 SKIP/N/A 口径，与 A7b 一致）。

## 10. 修订记录

- 报告哈希格与 `git log --follow` 输出回填（amend 一次）。
- 复审回注：见 `A8-review.log` 与本节追记。
