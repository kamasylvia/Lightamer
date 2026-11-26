# 功能范围盘点 lane（omp，只读）：darktable 的功能面 + darktamer 的自定义功能，对照 Lightamer 现状

## 背景（用户刚定的方向）

用户 2026-11-25 晚定的产品定义：**功能 = darktable 的功能，加上 darktamer 的自定义功能；UI 交互复刻 darktable。** 架构：非 UI 部分全部用 Rust，UI 用 AppKit。开发计划要按这个范围来排，所以先把范围盘清楚。

你这条 lane 只做盘点，不做设计，不改任何代码。

事实线索（先核实再用）：
- 官方 darktable 源码在本机 `/Volumes/UNITEK/Documents/Development/darktable`（master，无 remote）。**功能基线以它为准**，不要拿别的分支。
- darktamer 是用户的 darktable 分叉：GitHub `kamasylvia/darktamer`（2026-11-20 有推送），本机没有副本。
- Lightamer 现有功能：`LightamerIOP/Sources/`（iop 模块与 `.metal` 着色器）、`LightamerCore/Sources/`、`App/Sources/Lightamer/`；项目约定见仓库 `AGENTS.md`；已有的对标笔记在 `.work/gsd/research/` 与 `research/` 下。

## 要回答的问题

**Q1 darktable 的功能面。** 按功能域列表，每个域列出它的组成。至少覆盖：iop 模块全量（`src/iop/` 下每一个，名字、用途一句话、源码行数、是否依赖外部库）、lighttable 与选片、导入、导出格式与流程、标签与颜色标签与评分、样式（styles）与预设、蒙版、混合、色彩管理与显示变换、暗房之外的模式（打印、联机拍摄、地图、幻灯片）、HDR 与全景、修饰类（retouch、liquify）、LUT、脚本（Lua）、主题与快捷键、首选项。每个域给出源码位置和大致行数，作为工作量的粗略量级。

**Q2 darktamer 的自定义功能。** darktamer 相对官方 darktable 多了什么、改了什么。做法：优先用 GitHub API（先查它的 fork 来源，再用 compare 接口列出相对上游的提交和改动文件）。API 拿不到足够信息时，可以做一次**部分浅克隆**：`git clone --filter=blob:none --depth 300 git@github.com:kamasylvia/darktamer.git`，放在 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/darktamer`。不运行其中任何东西。结束时报告这个目录的大小；超过 300 MB 就删掉并在报告里说明。输出一张表：每个自定义功能一条，写它改了哪些文件、是新增模块还是改动现有模块、是否有 UI 部分、是否依赖平台能力。

**Q3 Lightamer 现状对照。** 对 Q1 的每个 iop 模块和每个功能域，标明 Lightamer 今天有没有：有、部分、没有。给出对应文件。「部分」要写清差什么。

**Q4 分期建议。** 按「一个用户拿它处理自己照片的日常流程」给出分期：第 0 期（不做成就不能日常用）、第 1 期、第 2 期（以后再做）。每期列功能域，并说明归到这一期的理由。这一节是建议，标明是建议。

## 读法与诚实要求

- 数字不编。行数写得出出它的命令。没查到就写没查到。
- darktamer 的自定义功能如果没盘全（API 限流、克隆失败等），写明盘到了哪些、漏了哪类。
- 结论和证据分开写。没有证据的判断标「推断」。

## omp 域内自审（项目既定模型）

产物落盘后，另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审。复审实例逐条抽查你的数字和对照结论（自己重跑命令），结论头 `PASS / N error + N minor`，发现回注修订，修订记录附在产物末尾。复审输出落 `scope-review.log`。

## 纪律

- 仓内只写 `.work/gsd/phases/rust-core/` 下的文件：`FEATURE-SCOPE.md`、`FEATURE-SCOPE-TABLES.md`（大表）、`scope-review.log`、`omp-scope-summary.md`。
- 只读官方 darktable 源码目录，不改它。产品树零改动。零 commit，零 push。
- 不构建、不跑测试、不开图形程序。
- 不碰用户照片库 `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`：不读、不列目录。
- 总墙钟不超过 100 分钟，含自审。到点交已有结果，标明没完成的部分。

## 交付

`FEATURE-SCOPE.md`（中文正文，英文标题）：

1. §0 一页纸：darktable 功能域数量、iop 模块总数、darktamer 自定义功能条数、Lightamer 现状的三档计数（有、部分、没有）。**不超过 40 行。**
2. §1 到 §4 对应上面四个问题，正文里只放汇总，长表放 `FEATURE-SCOPE-TABLES.md`。
3. §5 没查到的。

stdout 最后一条消息一次性完整输出，并落盘 `omp-scope-summary.md`。
