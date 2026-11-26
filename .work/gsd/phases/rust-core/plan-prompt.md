# 开发计划 lane（omp，只读）：为「全 Rust、功能对齐 darktable、界面用 gpui」出一份分波开发计划

## 你的任务

把已经做完的调研和用户的全部裁决，变成一份可以照着派活的分波计划。你不写产品代码，不构建，不开图形程序，不 commit。你只读资料、做设计取舍、写计划。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文，文件里的英文标题和标识符保持原文。HEAD 先亲核并记录。

## 用户的裁决（全部已定，照做，不要再列成选项）

产品与范围：
- 功能 = darktable 的功能，加 darktamer 的自定义功能；UI 交互复刻 darktable。
- Lightamer 有而 darktable 没有的功能保留（全景拼接、焦点合成、HDR 合成、节点式显示变换、版本分支、AI 标签与评分、软打样），排在第 1 期。
- 胶片模拟用 darktable 自己的 `spektrafilm` 模块，不用 SpektraLab 的资产。
- darktamer 的人像三件在那边没做完，只是占位（#35、#36、#37），不排期。

架构：
- 全部用 Rust：核心加界面。界面用 gpui 族（gpui-fast、gpui-kit、gpui）。
- Apple 能力（Core Image 解码、ColorSync、Vision、ImageIO、Metal）独占一个模块，只在 macOS 构建里存在。其余代码不依赖 Apple 框架。
- 模块自动被发现和注册：核心里不写模块名单，也不写槽号。每个模块自带一份描述。darktable 模块的描述里带着 darktable 的名字、顺序优先级、参数格式，这是模块自己的数据。
- 解码主路径是 rawspeed。
- 核心对界面只暴露一个稳定接口：命令、查询、事件流。界面的面板从模块描述生成。
- 许可证保持 GPL-3.0，可以移植 darktable 的代码，保留版权声明并标注修改。

历史：
- 第 0 期要能把 darktable 或 darktamer 修过的图打开成一样的观感（相同的模块下）。把历史写回成 darktable 能读的格式，无限延后。
- 历史只从原图旁的 XMP 文件读。只存在 darktable 自己数据库里的历史，不支持。
- 我们自己的修改两处都存，和 darktable 一样：我们自己的图库数据库，加原图那份 XMP 里我们自己的命名空间。写 XMP 时要保留 darktable 写在那里的全部内容。

其它：
- 旧的 Swift 版已冻结，它的输出不需要匹配，它自己的图库和 sidecar 不需要兼容。验收对照是 darktable 官方版。
- 第 0 期之内，每一波做完都停下来给用户看；之后连跑，只汇报。
- 用户拒绝重启 `fontd`。本机只接了一台 SDR 显示器，HDR 的验收要等有 EDR 屏。

## 先读的资料（按顺序）

1. 台账：GitHub #23（ledger）、#32（核心）、#33（界面）、#34（历史兼容）、#27（面板体系）、#25（逐模块蒙版）、#26（计时基线）、#24（解码）。读法 `gh issue view <N> -R kamasylvia/Lightamer`。
2. `.work/gsd/phases/rust-core/`：`FEATURE-SCOPE.md`（darktable 103 个模块与 21 个功能域、分期建议）、`HISTORY-COMPAT.md`（历史格式与 Rust 要复刻的六件事）、`CORE-DESIGN.md`（模块接口、第 0 期 21 个模块的清单、解码实测、验收对照命令、GPU 选型、仓库布局、量级估算）、`SPIKE-RUST-APPLE.md`（Rust 调四项 Apple 能力）、`VERIFY.md`（塔台核验记录，含对报告的更正）。
3. 界面：`.work/gsd/phases/gpui-spike/STATUS.md` 与 `REPORT*.md`（1,600 行原型，页面骨架、控件、12 条交互里 7 条一致）、`.work/gsd/phases/gpui-fast-scout/R2-CAPABILITIES.md` 与 `T1-BENCH.md`、`.work/gsd/phases/gpui-viewport/SPIKE-VIEWPORT.md`（自建 Metal 视口放进 gpui-fast 窗口）。
4. 界面的另一份盘点：`.work/gsd/phases/appkit-migration/RESEARCH.md` 与 `INVENTORY.md`。注意 `STATUS.md` 里标了哪些部分已过时，只有 Q1、Q2、Q4、Q5 还能用。
5. darktable 源码：只读 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`（上游 `master`，`679d594f5d`）。不要读 `/Volumes/UNITEK/Documents/Development/darktable`，那是 darktamer 的工作树。

## 已知与裁决冲突的两处，计划里必须改

- `CORE-DESIGN.md` §6 的仓库布局没有模块自动发现与注册的机制。
- `CORE-DESIGN.md` §7 第 ① 步写「参数版本为 1，不做旧版本迁移」。历史兼容的要求正相反：参数必须按 darktable 的 C 结构体布局和版本迁移来，见 `HISTORY-COMPAT.md` §0 和 §9。

## 我已定的技术取舍（带理由，计划里照用；你发现不成立就写明并给替代）

- 去马赛克起步只移植 darktable 的 RCD，另留一个直通模式供调试。它是 darktable 的默认算法。rawspeed 现在不带拜耳去马赛克，darktable 的实现在 `src/iop/demosaic.c` 和 `data/kernels/demosaic_*.cl`。
- 第 0 期管线全在 CPU 上跑，正确性优先。着色器以后用 WGSL 配 wgpu，Metal 快路径只放在 Apple 模块里。
- Apple 模块里的 Core Image 解码在第 0 期默认关闭。那条路相对 Apple 自己的解码有偏色，根因是相机数据来源不同；darktable 兼容的路径没有这个问题。
- 参数布局：每个 darktable 模块的参数结构体按 darktable 的 C 布局用 `#[repr(C)]` 复刻，用测试钉住大小和字段偏移；带最近两个版本的迁移链，迁移失败时像 darktable 一样丢掉那一条；混合参数读到版本 15 并带迁移链；只支持小端。
- 验收对照：每个移植的模块都用官方 darktable 命令行渲染的图来对，阈值是平均差小于 16 位的 1 个最低位、容差内的像素比例大于 0.9999，噪声底线的依据在 `CORE-DESIGN.md` §4。
- XMP 库不定死，放进地基阶段做选型，见下面 A4。

## 计划要有的内容

**阶段划分**（可调整，调整要写理由）：

- **阶段 A，地基**，先于任何功能。
- **阶段 B，第 0 期**：从导入一张图到导出成品的日常闭环，加暗房界面的第一版。这是第一个用户自己能拿它修图的版本。
- **阶段 C，第 1 期**：调色全量、修饰、HDR 视口与软打样、图库检索与标签、批量导出、Lightamer 独有功能。只列波次和目标，不展开。
- **阶段 D，第 2 期**：打印、联机拍摄、地图、幻灯片、Lua、长尾模块。只列清单。

**阶段 A 至少覆盖**（你可以合并或拆分，顺序要有依据）：

- A1 许可证与依赖核查：逐个依赖的许可证与链接方式，rawspeed 的 LGPL 义务怎样满足，GPL-3.0 的精确变体，README 与 NOTICE 要改什么。
- A2 仓库骨架：cargo 工作区、构建与测试脚本、机器守卫接入、构建产物的体积预算。
- A3 模块描述与自动发现注册：机制选型（编译期自行登记由链接器收集，或构建期扫描目录生成清单，各有什么坑，怎样验证新模块「加一个目录就被发现」），描述的字段，默认顺序怎样从描述算出，以及一条钉住「算出的默认顺序等于 darktable 默认顺序」的测试。
- A4 历史读写与 XMP 库选型：读 darktable 的 XMP；写我们自己的命名空间并保留其余内容；我们自己的图库数据库的表结构。选型用一条 lane 做三个测试后定：读一份 darktable 真实的 XMP；加我们的命名空间写回后 darktable 的内容一项不少；写回后让 darktable 再写一次，我们的内容还在。候选是 `xmp_toolkit`（Adobe 官方，C++ 底层）、`xmpkit`（纯 Rust，很年轻）、把 XMP 当 XML 只改我们自己那一段。
- A5 验收对照工具：把 `CORE-DESIGN.md` §4 的配方做成一条命令（下载并校验官方包、隔离配置与偏好、渲染、比对），官方包是每次重下还是留一份带校验的缓存，你定并写理由。
- A6 Apple 模块的边界：只在 macOS 编进去的门控方式，界面怎样知道某项能力在不在。
- A7 核心对界面的接口，加 gpui 窗口里的视口：视口用自建的 Metal 层放进 gpui-fast 的原生表面；视口区域的鼠标键盘事件走哪条路，要定下来并测试。

**每一波**都要写清：

1. 编号、名称、一句话目标。
2. 范围：涉及哪些模块、文件或目录；明确不做什么。
3. 输入：依赖前面哪几波，读哪些资料。
4. 产出：代码、测试、文档各是什么。
5. 验收标准：能机检的才写，写明用什么命令或测试来判。
6. 对照方法：和 darktable 怎么比。
7. 回退方式：这一波出了问题怎样撤。
8. 估时：几条执行 lane，每条不超过 3 小时。估算要标明是估算，并说明按什么校准。
9. 风险，以及是否需要用户裁决（绝大多数波不需要）。
10. 任务书草案：输入、变换规则、验收清单三件套，各写三五句，让派活的人能直接扩写成任务书。

**另外要有**：

- 一页纸：各阶段的波数与 lane 数、总数、第一个能日常用的版本在哪一波之后、三个最大的风险。
- 质量门：每波都要过的东西（测试、对照阈值、打开与编辑与批量的等待对照 #26 的基线、内存预算、机器一次只跑一个重活）。
- 检查点：哪些波做完要停下来给用户看。阶段 A 和阶段 B 的每一波都停，阶段 C 起连跑。
- Lightamer 现有的 73 个 Metal 着色器里，哪些能直接参考、哪些用不上。

## 读法与诚实要求

- 估算就是估算，写清口径。今天实测的速度是一条 lane 一到两小时交付一千行上下、带测试的代码。
- 没有依据的判断标「推断」。查不到就写查不到。
- 调研报告之间有矛盾时，以 `VERIFY.md` 的更正和本任务书的裁决为准，并在计划里指出来。
- 计划要能被一个没有上下文的人照着执行：不写「见上文」而不给位置。

## omp 域内自审（项目既定模型）

产物落盘后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例只读产物和资料，逐项核：每一条用户裁决在计划里有没有落到位、每波的验收标准能不能机检、依赖顺序有没有环、估时加总对不对、和调研报告的数字有没有抄错。结论头 `PASS / N error + N minor`。发现的问题回注修订，修订记录附在产物末尾。复审输出落 `plan-review.log`。

## 纪律

- 仓内只写 `.work/gsd/phases/rust-core/` 下的文件：`PLAN.md`、`PLAN-TABLES.md`、`plan-review.log`、`omp-plan-summary.md`。不改任何已有文件。产品树零改动。零 commit，零 push。
- 不构建、不跑测试、不开图形程序、不下载任何东西。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 总墙钟不超过 150 分钟，含自审。到点交已有结果，标明没完成的部分。

## 交付

`PLAN.md`（中文正文，英文标题）：

1. §0 一页纸。不超过 45 行。
2. §1 裁决清单与本计划的技术取舍。
3. §2 架构基线：只写计划采纳的部分和对调研的修订，不重复调研内容。
4. §3 阶段 A 与阶段 B 的逐波计划。长表放 `PLAN-TABLES.md`。
5. §4 阶段 C 与阶段 D 的清单。
6. §5 质量门与检查点。
7. §6 风险与没查到的。

stdout 最后一条消息一次性完整输出，并落盘 `omp-plan-summary.md`。
