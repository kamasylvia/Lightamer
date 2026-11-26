# 塔台核验记录：阶段 A 逐波

每波退出后，我自己重跑验收，先核证据再派下一波。数字给命令。

## A1 许可证与依赖核查（2026-11-26，commit `e19be370`，18 分钟）

- **改动边界**：`git show --stat` 是 8 个文件，全在任务书允许的清单里。Swift 产品代码、`Project.swift`、`Tests/` 零改动。
- **脚本我自己跑了五遍**：`bash -n` 通过。正例两个 spike 工作区都退出 0。负例是我自己搭的工作区，一个包写 `AGPL-3.0-only`、一个包不写许可证字段：脚本把这两个包都判为 FAIL，退出 1。把允许清单写坏一行时退出 1。仓库根目录现在还没有工作区，不带参数运行会退出 1，这是预期的，A2 建好工作区后应当变成 0。
- **README**：`## License` 一节已改成 `GPL-3.0-or-later`，写明是版权持有人 2026-11-26 确认的。
- **审计表**：`docs/LICENSE-AUDIT.md` 1037 行，八节；854 个 crate 的锁表加 T1 的十三项。我抽核了一条：lensfun 在 GitHub 上的许可证是 LGPL-3.0，与审计表一致。
- **rawspeed 的结论**：LGPL-2.1-or-later，不是调研里说的 LGPL-3.0；静态链接进 GPL-3.0-or-later 的项目即可，darktable 自己也是这样做的。这是工程核查，不是法律意见。
- **lane 的自审**：`PASS`，零 error。
- **一处小出入**：报告里写的提交哈希是 `b75404b0`，那是被修订前的版本；最终提交是 `e19be370`。报告正文我没有改，以这一条为准。

## A2 Rust 工作区骨架（2026-11-26，commit `097890cb`，约 15 分钟）

- **改动边界**：`git show --name-only` 全部在任务书允许的路径里：根目录五个文件、`crates/` 下 19 个包、五个脚本、波次报告与复审日志。Swift 的三个包目录、`Tests/`、`Project.swift`、`Tuist.swift`、两个 Xcode 工程一个都没出现。`machine-guard.sh` 和 `test-direct.sh` 与之前逐字节相同。
- **我自己重跑的**：五个脚本的 `bash -n` 全过。`Scripts/rust-ci-lite.sh` 从头到尾退出 0：守卫、许可证、构建、测试、预算。`cargo metadata` 列出 19 个包，锁文件里没有任何外部依赖。`cargo fmt --all --check` 干净。`cargo xtask check-i18n` 退出 0。
- **lane 报的数**：冷构建 10 秒（门是 360 秒），19 个测试通过，单 crate 增量检查 0.08 秒（门是 40 秒）。冷构建我没有自己重跑。
- **发现并修掉的一个缺口**：A1 的许可证检查对仓库自己的工作区是红的，19 个包全判不过。原因是 A1 的允许清单只按两个 spike 的锁表生成，全是宽松许可证，没有项目自己的 `GPL-3.0-or-later`。A2 的 lane 没有权改 A1 的文件，如实报了上来。我在允许清单里加了这一行，提交 `3f7e6106`，现在检查退出 0。这一行是我亲手加的，没有派 lane：一行数据文件的改动，派 lane 的开销比改动本身大。
- **lane 留下的一处残留**：`.gitignore` 的同一段被加了两遍，第二遍只进了暂存区、没进提交，工作区文件本身是对的。我用 `git restore --staged` 把暂存区还原，内容没变。
- **lint 起点**：`unsafe_code = "deny"`，`missing_docs` 和 clippy 的 `pedantic` 都是 warn，配合 `-D warnings` 等于强制。release profile 是 `opt-level = 3`、thin LTO、去符号。起点合理。
- **lane 的自审**：`PASS`。
- **一处小出入**：报告里写的提交哈希是修订前的 `9e4d74b1`，最终提交是 `097890cb`。
