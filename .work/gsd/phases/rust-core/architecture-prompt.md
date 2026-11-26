# 架构定稿调研 lane（omp，只读）：会话式的照片管理、修改历史存放在哪、分层框架，怎样合成一个完整的架构

## 背景

用户暂停了全部执行 lane，要求先把架构调研清楚。原话：「暂停派遣的 lane，先调研清楚架构。」你的产物是给用户过目的那份架构方案，要能据此定案、据此恢复执行。

用户最近的三条裁决：

1. **「我要求框架上要学 LightCraft，兼容 dt。」** 框架调研已经做完，结论在 `.work/gsd/phases/rust-core/FRAMEWORK.md`。
2. **「兼容 dt 历史不作为强制需求。」** 它不卡第 0 期，也不排期。
3. **「学习 capture one 的管理，每一组照片是一个 session，有一个数据库，默认创建 Capture/Output/Selects/Trash 四个子文件夹。」** 出处是 Capture One 官方的 Sessions 指南：<https://support.captureone.com/hc/en-us/articles/360003115137-The-Complete-Guide-to-Sessions-in-Capture-One>。用户同时问：「修改历史记录在 db 中吗？xmp 不需要了？如果放弃兼容 dt 是不是可以这么做？」

**先读的资料：**

- `.work/gsd/phases/rust-core/PLAN-AMENDMENTS.md`，全部十四条。A-1 到 A-11 是此前的裁决，A-12 到 A-14 是上面三条。
- `.work/gsd/phases/rust-core/FRAMEWORK.md` 与 `FRAMEWORK-TABLES.md`：LightCraft 的分层、命令分发口、处理版本号、图库与预览缓存，以及新布局 T-F9。**它是按「要读 darktable 历史」写的**，其中 C1（以整块参数为真相）、C7（迁移链）和 A4b 的部分内容要按 A-12 重新理解。
- `.work/gsd/phases/rust-core/PLAN.md` 的 §0 到 §2 和各波的标题。
- `.work/gsd/research/FEATURES.md` 里「Capture One Session Mode Features」一节，`.work/gsd/research/ARCHITECTURE.md` 的第 5 节，`.work/gsd/research/SUMMARY.md` 的资料清单：这是 2026 年 9 月为旧的 Swift 版做的调研，来源标的是 Capture One 的官方博客和支持文档。拿来定位，逐条对官方文档核实。
- `.work/gsd/phases/rust-core/HISTORY-COMPAT.md`：darktable 怎样存历史，只作对照。
- LightCraft 源码：`/Volumes/UNITEK/Documents/Development/lightcraft`，只读，许可证是 MIT 或 Apache-2.0。图库在 `crates/catalog/`，编辑设置在 `crates/develop/`，引擎在 `crates/engine/`，预览缓存在 `crates/preview/`。

**塔台已经从那份官方指南取到的事实**，你核对并补充，不用重新推导：

- Session 是「一个自包含的项目文档」，RAW 文件、调整、预览和元数据都放在同一个文件夹结构里。它「没有 Catalog 那样庞大的数据库」。
- 默认的子文件夹是 **Capture、Selects、Output、Trash**。指南只解释了 Output：可以把它排除在浏览之外。九月的笔记写成 `Captures`，以官方为准。
- 会话数据库是 **`.cosessiondb`** 文件。里面至少有 Session Favorites 和 Albums。
- **调整不在那个数据库里**：原文是「image edits are stored separately in the Session's Capture One subfolder」「Settings are stored locally in a CaptureOne subfolder, enabling easy transport and reuse」。也就是每张图一份调整文件，放在图片旁边的 `CaptureOne` 子文件夹里，不是 XMP。
- 模板只存文件夹和相册的结构，不存图片。指南没有讲 Trash 的行为。

你要再取的官方资料：同一支持站上关于 Catalogs 的指南，关于 Session 文件夹、Trash、模板、备份的文章，以及九月亮笔记里引的官方博客「Sessions 101」(<https://www.captureone.com/blog/sessions-101-discussing-the-concept>)。取网页用 `curl` 加代理（`https_proxy=http://127.0.0.1:10809`），或者你自己的联网工具。每条事实给链接和原文引用，查不到就写查不到。

**不要改本仓库的任何文件**，只在 `.work/gsd/phases/rust-core/` 下写交付文件。不构建，不跑测试，不开图形程序。

## 要回答的问题

**Q1 Capture One 的会话模型。** 逐项列出官方文档怎么说：文件夹结构、数据库里有什么、调整存在哪、四个子文件夹各自的用途、把图拖到别的文件夹时调整是否跟着走、不导入直接浏览现有文件夹、模板、会话与目录（Catalog）的区别、同时开多个会话、备份与删除会话、变体（variants）、相册与收藏。九月的笔记有说错的地方指出来。

**Q2 我们的会话包。** 设计它在磁盘上长什么样：会话文件夹、数据库文件的名字和位置、缩略图缓存放哪、单写者锁、备份和恢复的产物。四个子文件夹在我们这里各自的行为要写具体：

- 往 Capture 导入是复制、移动，还是原地引用。三种各有什么后果。
- 把一张图移进 Selects 是移动文件，还是只做标记。
- 删除一张图是不是把它移进 Trash；清空 Trash 是什么动作；撤回删除怎么做。
- Output 是不是导出的默认落点。

还要设计：怎样把一个已有的文件夹当成会话打开；最近打开的会话列表存在哪（它在所有会话之外）；模板里有什么；同时开多个会话时的规则。每一条给出理由，拿不准的列进裁决点。

**Q3 修改历史存在哪。这是用户问的问题，要正面回答。** 先用证据说清三家各怎样做：Capture One、LightCraft、darktable。然后比较在放弃兼容 darktable 之后我们的三个选项：

- 甲：只存进会话数据库。
- 乙：照 Capture One，每张图一份我们自己的调整文件，数据库只存结构和缓存。
- 丙：两处都存。

比较的维度：实现要多少东西（crate 和 lane）、批量粘贴一万张的快慢、崩溃安全、备份、单张图连同它的修改在会话之间或机器之间搬动、文件在磁盘上被挪走、损坏时波及多大、要不要依赖 XMP 库、和「图库为真相」的 LightCraft 做法合不合。给出推荐，并写清放弃了什么、怎样弥补。**XMP 还要不要**，明确回答。

**Q4 会话数据库用什么存。** 此前定的 SQLite 是为了和 darktable 的数据库互通，那个前提已经不在了，所以重新比：SQLite；LightCraft 那种快照加只追加日志的做法（读 `crates/catalog/src/journal.rs` 等）；两者结合。维度：批量提交的耗时、崩溃安全、单写者锁、备份是不是拷一个文件就行、智能相册和检索要做的查询、十万张图时的体积、实现成本和风险、测试手段、能不能整包搬走。读代码得出的就给代码位置，没有实测的标明是推断。给出推荐。

**Q5 LightCraft 的图库怎样落到「每个会话一个库」上。** LightCraft 是一个总图库。我们改成每个会话一个之后：它的缓存键、预览缓存、单写者锁、 compaction 各放在会话里还是放在应用层；哪些代码还能按会话复用；预览缓存的键里要不要带会话标识。

**Q6 合成一个完整架构。** 一张图或一张表讲清：

- 分层沿用 T-F9，写明会话、历史、预览缓存、引擎、管线、Apple 模块、gpui 界面各在哪一层。
- 每条流程怎么走，逐步写数据和命令：新建会话、导入、浏览、进暗房、编辑、批量粘贴、移进 Selects、移进 Trash、导出到 Output、备份、重新打开。命令按「一切皆命令」的口径列出来。
- 用户第一次打开应用时看到什么；没有会话时是什么。
- 应用层的状态（最近的会话、设置）存在哪。

**Q7 对计划的影响。** 逐波写哪些取消、哪些改内容、哪些新增，并给出新的估时。至少看：A4a（XMP 库选型）还要不要；A4b 改成什么；B12 移出后 B13 做什么；B15 和 B16 在会话模型下做什么；界面各波要多出一个会话浏览器。第一个能日常用的版本在这个架构下是什么样，在哪一波之后。

**Q8 要用户定的事。** 不超过五件。每件写选项、你的推荐、依据。候选：历史是不是只存数据库；数据库用什么存；导入是复制还是原地引用；要不要「目录」模式（一个大库里放很多会话）；单张图连同修改能不能搬出会话。

**Q9 没查到的与风险。**

## 读法与诚实要求

- 数字不编。没有实测的标「推断」。查不到就写查不到，并写出查过什么。
- 官方文档没写的行为不要当成事实，标「官方未说明」。
- 结论和证据分开写。
- 产物是给用户过目的：一页纸要让没读过前面文档的人看得懂。

## omp 域内自审（项目既定模型）

产物落盘后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读，重点核：Capture One 的每条说法有没有官方链接和原文；LightCraft 的代码位置是不是存在（抽查六处）；Q3 的比较有没有漏掉明显的代价；Q7 的 lane 加总对不对；有没有把 A-12 之前的前提带进来。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在产物末尾。复审输出落 `.work/gsd/phases/rust-core/architecture-review.log`。

## 纪律

- 只写 `.work/gsd/phases/rust-core/` 下的 `ARCHITECTURE.md`、`ARCHITECTURE-TABLES.md`、`architecture-review.log`、`omp-architecture-summary.md`。零 commit，零 push。
- 不构建、不跑测试、不开图形程序。不在 LightCraft 的目录里运行任何东西。
- 不读、不打印任何凭据文件。联网取文档时用给定的代理环境变量，不要把密钥写进任何输出。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 总墙钟不超过 170 分钟，含自审。到点交已有结果，标明没完成的部分。

## 交付

`ARCHITECTURE.md`（中文正文，英文标题）：

1. §0 一页纸，不超过 45 行：完整架构的一张表；用户那个问题的答案（历史存哪、XMP 还要不要）；会话包在磁盘上的样子；要用户定的事；新的估时。
2. §1 到 §9 对应上面九个问题，正文只放汇总，长表放 `ARCHITECTURE-TABLES.md`。

stdout 最后一条消息一次性完整输出，并落盘 `omp-architecture-summary.md`。
