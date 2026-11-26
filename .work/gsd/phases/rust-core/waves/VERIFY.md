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

## §8 追加：架构定稿调研（2026-11-26 上午，`ARCHITECTURE.md`）

**lane 的自审没有跑出来。** `architecture-review.log` 里只有一行 `Working...`，文档末尾的复审记录是空的。所以这一份只有我一个人的核验。

- **Capture One 的官方引文，我取原文核了五处**，全部对得上：
  - Session Trash 指南（`360002546518`）：Trash 里的图只读、不能编辑；清空会永久删除原图，不能撤回；清空之前可以把图拖回原来的文件夹。
  - Selects 指南（`360002524157`）：点「Move to Selects」后文件的位置会变成 Selects 文件夹；这个文件夹在新会话时自动创建。
  - 目录指南（`360003108698`）：每个目录是一个数据库，存原图的引用、调整、元数据和用户建的集合。
  - 导入指南（`360002520417`、`360002521938`）：Capture 文件夹是用会话时导入的标准目的地，保持 Capture、Selects、Output、Trash 的结构。
  - 另外两份官方文章对这些问题的回答都是「没有说明」：同一会话能否同时打开两次；把图拖到别的文件夹时调整跟不跟着走。文档把这两条标成「官方未说明」是对的。
- **九月的笔记确实有错**，文档的勘误可信：文件夹叫 `Capture` 不是 `Captures`；没有 `Crop` 这个官方文件夹；调整不是「在 Capture 子文件夹」，而是每张图所在文件夹下的设置子文件夹。
- **LightCraft 的代码位置核了三处**，都对：同名的 RAW 和 JPG 怎样共用一个设置文件（`engine/src/sidecar.rs`）；单写者锁把持有人写在单独的文件里（`catalog/src/lock.rs`）；图库是快照加日志两个文件（`catalog/src/journal.rs`）。
- **lane 加总核过**：阶段 A 九波是 18 条 lane、45.5 小时；阶段 B 二十波是 79 条 lane；合计 97 条、262.5 小时。
- **没有核的**：SQLite 一次事务写一万行要多久，文档自己标的是推断；十万张图时智能相册的查询性能，也是推断；LightCraft 是否把每张图的全部历史都放进图库快照，我没有找到对应代码。

**我改了文档的两处**：一行里混进了一个无关的词，删掉了；末尾空的复审记录换成了一条说明。

**我和 lane 的意见不同的一件：修改历史存哪。** lane 推荐乙，每张图一份设置文件，数据库只存索引和缓存，这是 Capture One 会话本来的做法。我倾向甲，只存进会话数据库。理由：只有一处真相，不存在数据库和文件对不上的风险（文档自己把它列成头号风险）；批量粘贴就是一次事务；LightCraft 的「图库为真相」和 Capture One 目录模式（调整在库里）都是这个做法。甲放弃的是单张图连同修改直接搬走，这一点可以以后用一个导出命令补上。两种都成立，由用户定。

补记（同日上午稍后）：lane 的复审实例在主进程退出之后写完了，`architecture-review.log` 的结论是 `PASS / 0 error + 5 minor`。它抽查了 39 条 Capture One 的引文（8 条逐字核）、LightCraft 的代码位置、代价矩阵、lane 加总和有没有把旧前提带进来，都通过。五条 minor 是引文出处和行号的精度问题：重复的一行我删了，其余四条没改。所以 §8 开头说的「只有我一个人的核验」已经不准确，现在有两份互相独立的核验。

## A3 模块描述与自动发现注册（2026-11-26，commit `aeb52d78`，续做后 14 分钟）

这一波中途被用户暂停过一次，半成品收进 stash，恢复后续做完成。

- **改动边界**：提交只含允许的路径。`dt-core` 和 `dt-api` 一个字没动。没有新增外部依赖，锁文件里仍然没有外部来源。
- **夹具我对着 darktable 源码全量比过**，不是抽查：基线是上游 `master` 的 `679d594f5d`，`v50_order` 和 `v50_jpg_order` 两张表各 97 个具名模块。我把两张表解析出来，和夹具逐条比行号、优先级、名字，两张表都是零差异。
- **顺序链**：我用一个临时测试打印了注册表算出的两条链，raw 和 jpg 各 97 条，首尾都是 `rawprepare, invert, temperature, rasterfile, highlights, cacorrect … dither, borders, watermark, gamma`。第 0 期要用的几个模块的位置对得上表：jpg 链里 `colorin` 排在 `denoiseprofile`、`lens` 前面，raw 链里排在它们后面，这正是两张表不一样的地方。临时测试跑完已删，工作区干净。
- **行内序的规则我又向源码确认了一遍**：darktable 先按表的行序建链表，再用 `g_list_sort` 按优先级排序，比较函数只比优先级，相等时返回 0。`g_list_sort` 是稳定排序，所以优先级相同的模块保持表里的行序。行内序取表里的行号是对的。jpg 表里优先级 28.0 的有 24 个模块，这条规则在那里很重要。
- **续做的 lane 纠正了我两处**：我说 `xtask` 的三个子命令没做，其实半成品里已经有了；我接手前数的 103 个模块目录里有 6 个是上一条 lane 重复生成的，真正的数是 97。
- **我自己重跑的**：`cargo test -p dt-registry` 9 个测试通过；`cargo xtask check-no-iop-names` 通过，查了 97 个名字、3 个目录；`cargo xtask check-order-sync` 通过；`rg` 在 `dt-core`、`dt-api` 里找不到任何模块名；探针脚本两个方向都通过，工作区复原；`Scripts/rust-ci-lite.sh` 退出 0，共 33 个测试；`cargo metadata` 仍是 19 个包。
- **参数描述已按 A-15 改**：只有一个字段列表，类型是「我们的设置模型」的字段，没有 C 结构体的字节布局。
- **lane 的自审**：`PASS`。

## A3R 分层重排、分层检查、测试套件（2026-11-26，commit `6bfed45d`，20 分钟）

- **改动边界**：提交只含允许的路径。Swift 的产品代码和工程文件没有出现。
- **重排**：现在是 28 个包，`crates/` 下 27 个加 `apps/dt-cli`。`cargo xtask layers` 打印每一层有哪些 crate，结论是没有违规。改名是 `git mv`：`git log --follow` 能从 `dt-pipeline` 追到它还叫 `dt-core` 时的那个提交。源码和脚本里没有留下旧名字。
- **A3 的产物没被碰**：从重排前的提交到重排后的提交，模块桩目录和顺序夹具的 `git diff --stat` 是空的。
- **分层检查我自己做了九次活体试验**，每次临时加一条依赖，跑检查，再撤掉：
  - 该报的都报了，退出 1：L0 的 `dt-color-math` 依赖 L1 的 `dt-meta`（向上）；`dt-pipeline` 把测试套件当普通依赖；`dt-geom` 依赖同层的 `dt-raster`（方向反了）。
  - 该放的都放了，退出 0：`dt-color-math` 依赖 `dt-geom`、`dt-raster` 依赖 `dt-geom`、`dt-decode` 依赖 `dt-meta`、`dt-history` 依赖 `dt-registry`。同层链的方向是排在后面的可以依赖排在前面的。
  - 我第一次挑的例子不好：让 `dt-iop-traits` 依赖 `dt-registry` 会形成循环依赖，cargo 自己先报错了，检查没跑到。换成一个不成环的例子之后才验到。
  - 一条措辞小问题：同层方向反了的时候，报错文字说的是「只能依赖严格更低的层」，没有说清是同层链的方向反了。判得对，话没说准，留给后面顺手改。
- **其余我自己重跑的**：全工作区 62 个测试通过，其中 `xtask` 22 个；`check-order-sync` 和 `check-no-iop-names` 通过；`Scripts/rust-ci-lite.sh` 退出 0，日志里能看到分层检查那一步。
- **署名**：取自 LightCraft 的两个文件（`crates/xtask/src/layers.rs` 和 `crates/dt-testkit/src/lib.rs`）文件头有来源行，`NOTICE` 里有 LightCraft 的条目。
- **分层检查查不到的**：传递依赖。它只看直接依赖，经过中间 crate 绕到高层是查不出的。这一条和 LightCraft 自己的检查一样，写在检查文件的头部说明里。
- **lane 的自审**：`PASS / 0 error + 0 minor`。
