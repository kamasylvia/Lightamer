# darktable spektrafilm 引入进度调研（omp 执行；纯文本零 commit 零构建）

你是 darktable spektrafilm 引入进度调研员。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**纯文本调研**。

## 背景

我方 M8 已落地光谱核（process v2，tc 表自拟合 clean-room，CC BY-SA 28 profile verbatim 消费）。darktable master 近期持续高频提交 spektrafilm 族（宽模糊抽稀/分叉修/翻译/GCC 兼容等），你调查**他们到哪一步了 + 有没有落地 + 可不可以学习**。

## 调研面

1. **dt spektrafilm 当前态**：`/Volumes/UNITEK/Documents/Development/darktable`（git show origin/main: 读法；本地树可能 stale）——src/common/spektra_{sim,core,fetch}.c + src/iop/ 相关 + OpenCL kernels + data/ 谱面资产。核心功能清单（已落地的用户可见功能面/操作流/参数面），**哪些是我们 M8 已有的**、**哪些是新的**。
2. **近期演进时间线**：`git log --oneline --all -- src/common/spektra_* src/iop/spektrafilm* data/kernels/spektra*` 最近 3 个月关键节点（引入/首版发布/后续修正/性能优化/OpenCL），逐 commit 一行摘要。
3. **可学习点逐条评估**：对每项新功能——我方光谱核是否有等价能力/是否值得引入/实现路径（Metal kernel 移植还是纯参数/数据层）。特别关注：宽模糊抽稀（diffusion/halation 性能配方——已登记）、分叉修（halation 修正）、OpenCL 清理（kernel 精简参考）、GCC 兼容（编译器对齐参考）。
4. **数据/资产面**：dt data/ 下 spektrafilm 谱面（CSV/JSON）有无新增 stock/更新（对照我方 Resources/FilmProfiles/ 28 卷）——新 stock 可走 SPEC-02 verbatim 通道。
5. **结论**：**引入建议**（逐项：立即可学 / M8-3+ 顺路 / 挂账观察 / 不适用）+ 时间线表 + 差距表。

## 产出契约

`.work/gsd/phases/m3-2-fsim-research/DT-SPEKTRAFILM-IMPORT-RESEARCH.md`（一个文件）：时间线表 + 功能清单表（我方已有/新/差距列）+ 可学习点逐条评估 + 数据面对照 + 引入建议结论。
