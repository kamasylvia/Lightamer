# A2-REPORT — Rust Workspace Skeleton (lane A2)

结论头：
- 工作区 19 包（T2 清单 19 − `dt-gpui` + `xtask`）+ 5 脚本 + lint/profile 起点落盘；除许可证检查外验收全绿。
- `Scripts/check-licenses.sh` exit 1：自有包的 `GPL-3.0-or-later` 不在 A1 允许清单（36 条全是宽松许可）里，19 包全 FAIL、4 条例外全 UNUSED——A1 脚本未覆盖"自有包许可"情形，需 orchestrator 在允许清单加一行，本波无权改 A1 文件。
- Swift 零改动；`rust-ci-lite.sh` 止于许可证步（同根因），其余各步已单独跑绿。

## 1. 基线

- 本仓库 HEAD（执行前亲核）：`8736251021b26e6c17624c5d0cef01246679d302`
  （`git rev-parse HEAD`；计划落盘基线 `1f9c1adb` 已是多提交之前）。
- 构建前守卫：`Scripts/machine-guard.sh` → `GUARD PASS (heavy=0 free=74% swap=?M disk=?GB)`，exit=0。
- 工具链：`rustc 1.100.0 (0ef1bc386 2026-11-09)`；`rustup component list --toolchain 1.100.0`
  亲核 `clippy`/`rustfmt` 均为 installed；`rust-toolchain.toml` 钉 `1.100.0`。
- 并行度：`.cargo/config.toml` `[build] jobs = 6` + 脚本显式 `-j6`；全程一次一个重活，
  未用 `caffeinate`，未下载安装任何软件。

## 2. 交付

- 根：`Cargo.toml`（`members = ["crates/*"]`，workspace.package 五字段）、`Cargo.lock`（19 包）、
  `rust-toolchain.toml`、`.cargo/config.toml`、`.gitignore`（追加 `/target/` + `**/*.rs.bk`）。
- `crates/`：17 个 lib（`src/lib.rs` = SPDX 头 + 一行 `//!` 用途 + `package_metadata_resolves` 测试）、
  `dt-cli`（`src/main.rs` 打印名与版本）、`xtask`（`check-i18n` 骨架）、`crates/README.md`（19 行地图）。
  无 `dt-gpui`（A7b 建）；零外部依赖，crate 间零互相依赖（锁表无 `source =` 行可证）。
- `Scripts/rust-{guard,build,test,budget,ci-lite}.sh`，全部可执行；`machine-guard.sh` 复用零改动。
- 执行中机修两记（非手工改）：① `cargo fmt --all` 修 xtask 一行超长；②
  `cargo clippy --fix --workspace --all-targets` 修 pedantic 的 `doc_markdown`（用途行加反引号）
  与 `assert_is_empty`（`assert!(!is_empty)` → `assert_ne!(x, "")`，19 文件）。

## 3. lint 与 profile 起点及理由

- `[workspace.lints.rust]`：`unsafe_code = "deny"`（B2 的 rawspeed FFI 在 `dt-decode` 里加局部
  `allow` 并写理由，deny 可被局部覆盖而 forbid 不行，故不用 forbid）；`missing_docs = "warn"`
  （pub 项必须写文档，与 `-D warnings` 配合即强制执行）。
- `[workspace.lints.clippy]`：`pedantic = "warn"`（nursery/cargo/restriction 不开；本波已实证能抓到
  真问题——doc 反引号与 assert 形态——且机修成本低；后续波若某条 pedantic 与移植代码冲突，
  在模块内局部 allow 并注明）。
- `[profile.release]`：`opt-level = 3` + `lto = "thin"` + `strip = "symbols"`（UI 二进制 80MB 门的
  起点配置；`codegen-units = 1` 不开，省构建时间；perf 波再调）。`[profile.dev]` 不写，用默认增量。
- `[alias]`：`xtask`（`cargo xtask check-i18n` 的入口）、`c`/`t`/`l`（check/test/clippy-D-warnings
  快捷）、`tree-deps`（A6 的 `cargo tree -e normal` 机检用）。

## 4. 验收命令与输出（任务书 §5 逐条）

```
$ for s in rust-guard rust-build rust-test rust-budget rust-ci-lite; do bash -n Scripts/$s.sh && echo "$s: BASH-N-OK"; done
rust-guard: BASH-N-OK / rust-build: BASH-N-OK / rust-test: BASH-N-OK / rust-budget: BASH-N-OK / rust-ci-lite: BASH-N-OK
$ command -v shellcheck || echo CONFIRMED-NO-SHELLCHECK
CONFIRMED-NO-SHELLCHECK（shellcheck 未跑）

$ time Scripts/rust-build.sh --cold
rust-build: done in 9s (cold=1, jobs=6)；real 0m9.946s ≤ 360s ✓ exit=0

$ Scripts/rust-test.sh
rust-test: fmt OK / rust-test: clippy OK / rust-test: tests total passed=19；exit=0 ✓
（`cargo fmt --all --check` 与 `cargo clippy --workspace --all-targets -- -D warnings` 含在内，全绿）

$ time cargo check -p dt-iop-color --locked -j6
real 0m0.078s ≤ 40s ✓ exit=0

$ Scripts/rust-budget.sh --cold
rust-budget: cold-build = 10s (gate <=360s) PASS
rust-budget: check dt-iop-color = 0s (gate <=40s) PASS
rust-budget: release dt-gpui = N/A (no UI binary at A2) PASS
rust-budget: target/ = 2MB (3052KB, gate <=20GB)
rust-budget: overall PASS；exit=0 ✓
注：首次跑读到 cold-build 1s，曾疑计时异常；自审后深查结论（见 §8）：计时诚实，
暖机真值约 0.25s（cargo 内置 Finished 计时 + 19 Compiling 行 + 删除验证三方互证），
全程观测 0.25s–15s 均为负载波动，门 360s 下全 PASS。上表 10s 为当轮复核实测值，保留。

$ Scripts/rust-guard.sh
GUARD PASS (heavy=0 free=74% swap=?M disk=?GB)；exit=0 ✓

$ Scripts/check-licenses.sh
allow=0 exception=0 fail=19 total=19；4 条例外全 UNUSED；exit=1 ✗（见结论头根因分析）
样例行：FAIL dt-api 0.1.0: license 'GPL-3.0-or-later' not in allow list and no exception
提案：往 Scripts/licenses-allow.txt 加一行 `GPL-3.0-or-later`（自有包许可；A1 文件，本波无权改，
交 orchestrator；A1 报告 §1.3 的 W 例外退役语至此才真正闭环）。

$ cargo xtask check-i18n
xtask check-i18n: no key-table dir 'i18n' (i18n starts at B17); nothing to compare.；exit=0 ✓

$ cargo metadata --locked --no-deps --format-version 1 | python3 …（包数与名表）
packages: 19（= T2 的 19 − dt-gpui + xtask ✓；名表见 §2）
$ grep -c '^\[\[package\]\]' Cargo.lock → 19；`grep -E 'dt-gpui|source = ' Cargo.lock` 零命中 ✓

$ ./target/debug/dt-cli → `dt-cli 0.1.0`；exit=0 ✓（任务书未点名，顺手验证）

$ git status --porcelain | grep -vE '^\?\? .work/'
 M .gitignore / ?? .cargo/ Cargo.lock Cargo.toml rust-toolchain.toml crates/ Scripts/rust-*.sh（5 个）
（另有一行 `?? evidence/gui/paste-tiers.csv`，非本波产物，不碰；逐路径 add 已避开）
$ git diff --stat -- Scripts/machine-guard.sh Scripts/test-direct.sh → 空 ✓
$ git status --porcelain | grep -E 'App/|LightamerCore/|LightamerIOP/|Tests/|Project.swift|Tuist.swift|xcworkspace|xcodeproj' → 零命中 ✓
```

`rust-ci-lite.sh` 全串：守卫 PASS 后止于许可证步（同根因），exit=1；构建/测试/预算三步已在上文单独跑绿。

## 5. commit

- Hash（基线，amend 补 Cargo.lock 后）：`9e4d74b17b1488c02c6fc8d0bc80710f1abbe93f`
- `git show --stat`（基线 50 文件；终版 hash 见 stdout，入库报告不可预写）：
```
9e4d74b1 feat(rust-core): add workspace skeleton with 19 crates and scripts
 .cargo/config.toml                            |  11 +++
 .gitignore                                    |   4 +
 .work/gsd/phases/rust-core/waves/A2-REPORT.md | 120 ++++++++++++++++++++++++++
 Cargo.lock                                    |  79 +++++++++++++++++
 Cargo.toml                                    |  26 ++++++
 Scripts/rust-budget.sh                        |  76 ++++++++++++++++
 Scripts/rust-build.sh                         |  23 +++++
 Scripts/rust-ci-lite.sh                       |  19 ++++
 Scripts/rust-guard.sh                         |  53 ++++++++++++
 Scripts/rust-test.sh                          |  24 ++++++
 crates/README.md                              |  30 +++++++
 crates/dt-api/Cargo.toml                      |  10 +++
 crates/dt-api/src/lib.rs                      |  11 +++
 crates/dt-app/Cargo.toml                      |  10 +++
 crates/dt-app/src/lib.rs                      |  11 +++
 crates/dt-apple/Cargo.toml                    |  10 +++
 crates/dt-apple/src/lib.rs                    |  11 +++
 crates/dt-blend/Cargo.toml                    |  10 +++
 crates/dt-blend/src/lib.rs                    |  11 +++
 crates/dt-cli/Cargo.toml                      |  10 +++
 crates/dt-cli/src/main.rs                     |  15 ++++
 crates/dt-color/Cargo.toml                    |  10 +++
 crates/dt-color/src/lib.rs                    |  11 +++
 crates/dt-core/Cargo.toml                     |  10 +++
 crates/dt-core/src/lib.rs                     |  11 +++
 crates/dt-decode/Cargo.toml                   |  10 +++
 crates/dt-decode/src/lib.rs                   |  11 +++
 crates/dt-export/Cargo.toml                   |  10 +++
 crates/dt-export/src/lib.rs                   |  11 +++
 crates/dt-history/Cargo.toml                  |  10 +++
 crates/dt-history/src/lib.rs                  |  11 +++
 crates/dt-iop-color/Cargo.toml                |  10 +++
 crates/dt-iop-color/src/lib.rs                |  11 +++
 crates/dt-iop-display/Cargo.toml              |  10 +++
 crates/dt-iop-display/src/lib.rs              |  11 +++
 crates/dt-iop-geom/Cargo.toml                 |  10 +++
 crates/dt-iop-geom/src/lib.rs                 |  11 +++
 crates/dt-iop-raw/Cargo.toml                  |  10 +++
 crates/dt-iop-raw/src/lib.rs                  |  11 +++
 crates/dt-iop-traits/Cargo.toml               |  10 +++
 crates/dt-iop-traits/src/lib.rs               |  11 +++
 crates/dt-library/Cargo.toml                  |  10 +++
 crates/dt-library/src/lib.rs                  |  11 +++
 crates/dt-lightamer/Cargo.toml                |  10 +++
 crates/dt-lightamer/src/lib.rs                |  11 +++
 crates/dt-registry/Cargo.toml                 |  10 +++
 crates/dt-registry/src/lib.rs                 |  11 +++
 crates/xtask/Cargo.toml                       |  10 +++
 crates/xtask/src/main.rs                      |  57 ++++++++++++
 rust-toolchain.toml                           |   4 +
 50 files changed, 918 insertions(+)
```

## 6. 构建目录

- `du -sk target/` = 3052KB（≈2MB，远低于 20GB 清理线）；`git check-ignore target` 命中，
  `git status` 无 `target/`，绝未入库。

## 7. 未做 / 未验

**未做**：① 许可证检查红灯（根因与一行提案见 §4，需 orchestrator 改 A1 数据文件）；
② `rust-ci-lite.sh` 全绿未演示（止于许可证步，exit=1）；③ `dt-gpui`（A7b 建，按计划不做）；
④ 任何业务逻辑（按计划不做）；⑤ `evidence/gui/paste-tiers.csv` 非本波文件，未动。

**未验**：① shellcheck（本机无）；② `rust-guard.sh --wait` 长轮询与超时分支（只验了无参数即时返回；
BLOCK/超时路径未触发）；③ 非 macOS 空壳行为（A6 的事）；④ `rust-test.sh` 的测试计数解析在
"有失败测试"分支的表现（当前 19/19 全过，无失败样本）；⑤ 域内自审结论见 `A2-review.log`
（若 error 则修订记录附 §8）。

## 8. 终审修订记录

自审结论：`PASS`（0 error + 0 minor），见 `A2-review.log`（125s 独立重跑，§4 逐条复现，
含许可证红灯同签名；`git show --stat` 50 文件核对无误；三 crate 继承抽查通过）。
基线之后三处收尾改动（amend 并入同一 commit，不另起提交）：
  ① `Scripts/rust-budget.sh` 计时硬化：`SECONDS` 改 `date +%s` 起止戳 + `rm` 后验
     `target/` 确已消失（`TARGET-NOT-REMOVED` 判 FAIL）；改后 `bash -n` 过，
     `rust-budget.sh --cold` 连跑三轮皆 `overall PASS`（cold 0s/0s/0s，cargo 内置
     Finished 0.25s/0.02s，Compiling ×19，target 3052KB 不变）。附带正本结论：
     所谓"0–1s 异常值"是暖机真值，计时器从未说谎（取证：RUSTC_WRAPPER/sccache 未设、
     无全局 cargo config、cargo 内置 Finished 0.25s + Compiling ×19 + 删除验证）。
  ② `A2-REPORT.md` 本文件：回填 §5（基线 hash + stat）、§8 本段、§4 注的更正。
  ③ `A2-review.log` 落盘（39 行）。
另：复审发现 index 有一行他方 staged 的 `.gitignore` 重复块（A2 注释块又 append 一遍），
worktree 与 HEAD 干净一致——非本波写入，未碰（见 `git diff --cached -- .gitignore`）。
终版 hash = 最终 amend 后 `git rev-parse HEAD`（提交后亲核，stdout 末尾给出）。
