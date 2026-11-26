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

## A-9 框架学 LightCraft，兼容 darktable（2026-11-26，用户裁决）

- 用户原话：「我要求框架上要学 LightCraft，兼容 dt。」
- **框架**按 LightCraft 的做法来：引擎优先的分层工作区，依赖方向由检查强制；「一切皆命令」，界面、命令行、MCP 共用同一个命令分发口，下层不知道界面的存在；图库带每张照片的处理版本号；CPU 参考管线，GPU 孪生在后面。LightCraft 的源码在本机 `/Volumes/UNITEK/Documents/Development/lightcraft`，许可证是 MIT 或 Apache-2.0，设计和代码都可以取用，取用代码要在 `NOTICE` 里署名。
- **兼容 darktable**是搭在这个框架上的要求：模块、模块顺序、参数格式、历史的读法都照 darktable，验收对照是 darktable 官方版。两条要求拉不到一起的地方，逐处写明怎样调和。
- 对计划的影响：
  - A3（模块描述与自动发现注册）照跑。它的产物与 crate 怎么摆无关，描述、顺序、夹具都留得住。
  - A3 之后插一波重排：按框架调研的结论重排 crate 和分层，加上强制依赖方向的检查。A2 建的包都还是空壳，现在重排最便宜。
  - A7a 的「核心对界面接口」按「一切皆命令」的命令分发口来做。A4a 不变。A4b、A5、A6、A7b 和阶段 B 的各波，按框架调研给出的对照表重新指到新的 crate。
  - 解码仍用 rawspeed，不学 LightCraft 自研解码器；界面仍用 gpui 族，不用 egui；Apple 能力仍独占一个模块，只在 macOS 构建里存在。模块仍自动发现和注册。
- 框架调研的产物：`.work/gsd/phases/rust-core/FRAMEWORK.md`。重排那一波以它为输入。

## A-10 性能目标取 LightCraft 的实测数（2026-11-26）

- 第 0 期以 LightCraft 的实测数为门：热切换一张图不超过 0.72 秒；一万张批量粘贴在 1 秒内；改过的图的可见缩略图在约 0.5 秒内刷新。在 B15、B16、B20 各量一次，量的口径沿用 #26。

## A-11 每张照片带处理版本号（2026-11-26）

- 学 LightCraft：凡改观感的变更开新的处理版本号，旧版本冻结，老照片的渲染不漂移，直到用户手动升级。我们自己的历史写进 XMP 的自有命名空间时带上版本号。读 darktable 的历史时，以 darktable 自己的迁移行为为准。
- 落在 B13（历史写与图库数据库）。

## A-12 darktable 历史兼容不再是强制需求（2026-11-26，用户裁决）

- 用户原话：「兼容 dt 历史不作为强制需求」。它不卡第 0 期，也不排期（#34）。
- 因为验收对照仍是 darktable 官方版，保留两样：默认模块顺序与 darktable 相同；给对照工具单向写 darktable 格式的 XMP 夹具（只写不读，不做版本迁移链）。
- 对计划的影响：A4a 的「读一份 darktable 真实的 XMP」不再是必过项；A4b 从「darktable 的参数布局、迁移链、历史读」改成我们自己的历史模型；B12（读历史）移出第 0 期；B14（蒙版与混合）退回基础范围。
- `FRAMEWORK.md` 里凡是按「读 darktable 历史」写出来的部分（C1 的「以整块参数为真相」、C7 的「迁移链管参数」、A4b 的 lane 数）都按这条重新理解，由架构定稿调研给出修订。

## A-13 暂停执行（2026-11-26，用户裁决）

- 用户原话：「暂停派遣的 lane，先调研清楚架构。」
- A3 在运行中被停下，没有提交。它的半成品（13 个改动过的文件和 113 个新文件）在 `git stash` 里，说明文字是 `A3 partial work …`。工作区是干净的。
- `.work/config.toml` 的 `paused` 已置为 `true`，保活巡检不再推进。
- 架构定稿之前不派任何执行 lane。恢复要等用户过目架构结论后发话。

## A-14 照 Capture One 的方式管理照片（2026-11-26，用户裁决）

- 用户原话：「学习 capture one 的管理，每一组照片是一个 session，有一个数据库，默认创建 Capture/Output/Selects/Trash 四个子文件夹。」出处是 Capture One 官方的 Sessions 指南。
- 用户同时提了一个问题，要由架构调研回答：「修改历史记录在 db 中吗？xmp 不需要了？如果放弃兼容 dt 是不是可以这么做？」
- 落实到哪几波、会话包在磁盘上长什么样、历史存在哪，由架构定稿调研给出方案，用户过目后写进这里。

## A-15 架构定稿（2026-11-26，用户裁决「全部采纳推荐」）

依据是 `.work/gsd/phases/rust-core/ARCHITECTURE.md`。逐件如下。

1. **修改历史只存会话数据库**（三个选项里的甲）。没有 XMP，也没有每张图的设置文件。`ARCHITECTURE.md` 推荐的是乙，§2、§3、§6、§7 都按乙写的；以下各条按甲理解，与那几节不同的地方以这里为准：
   - 会话包里没有 `Lightamer/` 子文件夹。历史栈、元数据、每张照片的处理版本号都在 `<Name>.lmsessiondb` 里。
   - 写历史只有一处，就是 SQLite 的一次事务。没有「先写库、后台再刷文件」的队列，也没有文件和库对不上的风险（`ARCHITECTURE.md` 列的 R1 不存在了）。B13 因此比文档估的少做一块。
   - 移进 Selects、移进 Trash、从 Trash 拖回：先动文件，再在同一条命令里改库里的路径。打开会话时核对，文件和库对不上就报告，并给出修法。
   - 备份就是拷会话文件夹，库加图，`Cache/` 可以不拷。升级库的版本之前自动留一份 `.backup`。`session.verify` 做完整性检查。
   - 单张图单独拷出会话不带修改。第 0 期不做导出调整的命令，排到第 1 期，可选。
2. **会话库用 SQLite，开 WAL**。一个会话一个库文件 `<Name>.lmsessiondb`。建表、版本迁移、数据访问在 B12′ 做。一次事务写一万行要多久，到时实测。
3. **导入默认复制进 `Capture/`**。「原地引用」是导入对话框里的显式选项，第 0 期就有。
4. **目录模式先不做**，只有会话。
5. **其余按 `ARCHITECTURE.md` §2**：四个子文件夹的行为、把已有的文件夹当会话打开、最近的会话和模板与偏好存在应用层、多个会话各开一个窗口、同一个会话只许一个写入者。
6. **分层按 `FRAMEWORK.md` 的 T-F9**：会话库和检索在 L3 的 `dt-catalog`，历史栈和处理版本号在 L2 的 `dt-history`，会话命令在 L4 的 `dt-engine`，会话浏览器在 L5 的 `dt-gpui`。
7. **计划按 `ARCHITECTURE.md` §7 改**：A4a 取消；A4b 改成我们自己的历史模型；B12 换成会话包与库；B14 退回基础范围；B15 和 B19 加上会话的行为和会话浏览器。另有 `FRAMEWORK.md` 的 A3R（重排）和 A7a（命令分发口）。
8. **执行恢复**，阶段 A 继续连跑。A3 的半成品从 `git stash` 取回，续做。
