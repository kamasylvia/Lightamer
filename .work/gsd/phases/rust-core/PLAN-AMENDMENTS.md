# PLAN-AMENDMENTS — 对 PLAN.md 的修订（执行 lane 必须与 PLAN.md 一起读）

## A-1 基线改为上游 master 的指定提交（2026-11-26，用户裁决）

- 用户使用的 darktable / darktamer 版本是 5.7+2314（构建时的版本号）；本机 darktamer 工作树现在是 `release-5.7.0-2316`。它的上游基座是 darktable `master` 的提交 `679d594f5d`（2026-11-22，`release-5.7.0-2234`），上面加了 darktamer 自己的 82 个提交。
- 因此：参数布局、模块版本号、默认模块顺序一律钉上游 `master` @ `679d594f5d`，不钉 `release-5.7.0` tag。计划里凡是写 `release-5.7.0` 的地方（§1.3、§2.4、A3、A4b、A5，以及 `PLAN-TABLES.md` 的 T5、T7）都按这条改。
- 读 5.7.0 或 5.6.2 发布版写的历史，走 darktable 自己的迁移链，例如 `temperature` 从版本 4 到 5、`colorin` 从 7 到 8。
- 官方对照包：有 5.7.0 的官方 macOS 包就用它，没有就降到 5.6.2。给官方包用的 XMP 夹具按该发布版的格式写，我们这一侧经迁移链读。A4b 的验收「官方包回读的 modversion 与我们的描述表相等」改为「官方包回读的 modversion 在我们的迁移链里，并且能迁移到钉住的版本」。
- A5 多一项产出：官方包的版本与 `679d594f5d` 之间，第 0 期 21 个模块的差异报告（参数版本、默认值、渲染行为）。
- 源码位置不变：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master` 就是 `679d594f5d`。

## A-2 阶段 A 连跑（2026-11-26，用户裁决）

- 阶段 A 的九波不停下等用户，逐波连跑，每波完成在 #32 记一条；只有遇到需要用户裁决的事才停。
- 阶段 B 仍然每波停下给用户看，共 20 次。阶段 C 起连跑。

## A-3 许可证变体已确认

- 用户是唯一版权人，已确认 `GPL-3.0-or-later`。A1 可以直接落到 README、NOTICE 和源文件头。

## A-4 Rust 工作区的位置已确认

- 放在仓库根目录（`Cargo.toml` 加 `crates/`），与冻结的 Swift 代码树（`App/`、`LightamerCore/`、`LightamerIOP/`、`Tests/`、`Project.swift` 等）并存。旧树在 B20 之后再决定去留。

## A-5 脚本目录

- 所有新的 shell 脚本放进已有的 `Scripts/`，与 `machine-guard.sh` 同目录，不另建小写的 `scripts/`。计划里写的 `scripts/check-licenses.sh` 即 `Scripts/check-licenses.sh`。这个卷是大小写敏感的 APFS，两个名字会成为两个目录，容易混。

## A-6 rawspeed 的版本

- darktable `679d594f5d` 钉的 rawspeed 提交是 `0c16fee77`。我们以这个提交为准，许可证文本也按它取。此前 spike 用的是 `718eae2`，只是实验用。

## A-7 推送

- 用户 2026-11-26 凌晨下令推送：`main` 已推到两个远端（`50a01c13`）。之后阶段 A 结束时推一次，阶段 B 每个检查点推一次。

## A-8 阶段 A 的脚本文件名

- 这个仓库里已有给 Swift 版用的 `Scripts/test-direct.sh` 等脚本。为了不和它们混，计划里写的 `Scripts/{guard,build,test,budget}.sh` 的实际文件名是 `Scripts/rust-{guard,build,test,budget}.sh`，另有一个总入口 `Scripts/rust-ci-lite.sh`。`oracle.sh` 和 `perf.sh` 的名字不变。
