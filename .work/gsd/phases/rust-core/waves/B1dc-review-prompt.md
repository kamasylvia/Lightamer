# 复审 lane（omp，只读）：B1d-c——流式作业不再先取整帧

## 你是什么

一条**只读**的独立复审。执行 lane 已经把代码提交了（`fix(rust-core): B1d-c probe-first streaming, region-source pipe entry`，以及其后一个文档提交），但它的自审没有做成——主进程在复审实例写完之前就退出了，`waves/B1dc-review.log` 是空的，报告是带「待填」的草稿。塔台另派你来补这次复审。**你不改仓库里任何已有的文件，不提交。** 你可以运行构建、测试、演示脚本和计时。你唯一的产物是复审日志。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文，代码引用保持原文。先亲核 HEAD 并写进日志。

**先读这两个技能文件**，复审时按它们衡量代码：`/Users/kamasylvia/.agents/skills/ponytail/SKILL.md`、`/Users/kamasylvia/.agents/skills/rust-best-practices/SKILL.md`。两个技能打架处按项目的优先级：公开的项写 `///`，其余注释只写为什么；错误类型手写；不跟「一个测试只断言一件事」和类型状态。

## 先读

- `.work/gsd/phases/rust-core/waves/B1dc-prompt.md`：执行 lane 的任务书（要做的四条、验收清单）。
- `.work/gsd/phases/rust-core/waves/B1dc-REPORT.md`：执行 lane 的报告草稿（带待填）。
- `.work/gsd/phases/rust-core/waves/VERIFY.md` 的最后两节：B1d-b 一节记着缺陷是怎么来的。
- `docs/PIPELINE.md`（仓库根下）的「行带流式」一节。
- 被复审的改动：`git diff 18499e44..HEAD`（`crates/lightamer-pipeline/src/stream.rs`、`crates/lightamer-engine/src/render.rs`、`apps/lightamer-cli/src/stream_demo.rs`、文档）。
- Lumen RAW 的源码，**只读**，在 `/Volumes/UNITEK/Documents/Development/lumen-raw`（`lumen/large_image.py`、`lumen/engine.py`），只在需要对照时看。不 pull、不构建、不运行。

## 要核的（每一条都写下你实际跑了什么、看到了什么）

1. **重跑验收清单**（`B1dc-prompt.md` 里的全部）：三个 crate 的测试、`cargo test --workspace --locked --no-fail-fast`、六条不崩溃 lint（`CARGO_INCREMENTAL=0`）、文档零警告、`cargo xtask layers` 等、许可证检查、五个演示脚本、`Scripts/rust-ci-lite.sh`。守卫不过就等，不要绕；机器上可能有别人自己的重活，不是你的，不碰。
2. **流式这条路一次都不整帧取输入**：读引擎的渲染作业，从开头跟到结束——`probe` 在哪、整帧 `fetch` 在哪、什么条件下走流式；用 grep 列出 `input.fetch(` 的全部调用点，证明它们只在非流式的那条路上。再读测试：计数的来源那一例是不是真的断言了「整帧取 0 次」。
3. **规划只在管线里做一次**：`run_stream_fallback` 里是不是只剩一次 `render_stream_from`；引擎里还有没有残留的规划或逐块调用。
4. **`render_stream` 的改写没有改意思**：它现在经 `render_stream_from` 实现——B1d-a 的测试是不是一个没改（diff 里旧测试体零改动）且照旧通过；整帧裁一块的适配器，区域盖不住时是不是分了类型的拒绝。
5. **默认的 `probe` 和原来的行为逐值相同**；自己覆写的 `probe` 报的尺寸和像素不一致时会怎样（找出来，写下来——报告里没说）。
6. **「探」和真正取到的尺寸不一致的边角**：探说放得下、于是整帧取输入，取出来的却比探的大（或者反过来）——代码怎么处理？有没有测试？没有的话列为 minor 或 error（按后果定）。
7. **整帧入口一个字没改**：`git diff 18499e44..HEAD -- crates/lightamer-pipeline/src/render.rs` 零输出。
8. **引擎的源码里没有文件操作**（grep）。
9. **内存的真相**：报告草稿的新上限表里峰值常驻仍然跟着输出的大小涨（两亿像素条带 3.03 GiB），lane 的解释是「输出拼装是内存映射文件，页是干净的、可回收的」。**用另一个量来验证这句话**：`/usr/bin/time -l` 除了「maximum resident set size」还打印「peak memory footprint」。自己跑 `stream-demo --mp N --only …`（看 `apps/lightamer-cli/src/stream_demo.rs` 和 `Scripts/rust-stream-demo.sh` 弄清参数），至少量四行（条带和方块各两档，例如两亿和五亿像素），把**峰值常驻**和**峰值占用（footprint）**两个数并排记下来。如果 footprint 不随帧的大小涨，lane 的解释成立；如果也涨，就是真问题，列 error。发行版、串行、一次一个重活；负载高时常驻的数会抖，写明当时的负载。
10. **两个技能**：抽查这次改动有没有违反的地方（没人要的抽象、该写 `///` 的公开项没写、不必要的克隆）；只报真问题。
11. **边界**：`git show --name-only` 的两个提交只含任务书允许的路径；`Cargo.lock` 没变；历史模型、注册表、会话库、模块桩、Apple 模块没变。

## 产物

`.work/gsd/phases/rust-core/waves/B1dc-review.log`（中文）：第一行是结论头 `PASS / N error + N minor`；然后逐条写上面每一项你跑了什么、看到了什么（数字和命令）；最后是发现清单——每条写明级别（error 或 minor）、位置（`文件:行号`）、问题、建议的修法。第 9 条量到的四行数字要完整地写进去（后面收尾的人要抄进报告）。

只写这一个文件。跑完之后系统的临时目录里不许留下你建的目录；没有残留的进程。总墙钟不超过 90 分钟。
