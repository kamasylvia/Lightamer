# 只读调研 lane（omp）：Alcedo 和 Lumen RAW 的人像功能——盘点与借鉴清单

## 背景

Lightamer 在用 Rust 全量重写。用户 2026-11-27 指示：「参考项目中 Alcedo 和 Lumen RAW 都在更新人像功能。请借鉴。」我们自己的蒙版已经立了两波（B14 基础蒙版包、B14A AI 蒙版），调研在 `.work/gsd/phases/masks-research/`（`RESEARCH.md`、`RESEARCH-TABLES.md`、`SKIN-FACE-BODY.md`）。你是只读的调研 lane：把两个参考仓库拉到最新，盘点它们的人像功能，给出借鉴清单。不改我们的代码、不构建、不提交。

两个参考仓库（都是 GPL-3.0，同许可可以复制，但要逐项核清楚代码、模型权重、训练数据各自的许可）：

- `/Volumes/UNITEK/Documents/Development/AlcedoStudio`：现在在 `f4d36474`（0.3.7，2026-11-25），分支 `main`，工作区干净。
- `/Volumes/UNITEK/Documents/Development/lumen-raw`：现在在 `f520192`（2.3.2，2026-11-21），分支 `main`，工作区干净。

已有的笔记（只读，在 `.work/gsd/` 下）：`research/ALCEDO-FEATURE-MAP.md`、`research/ALCEDO-PARITY-2026-10.md`、`research/ALCEDO-CLI-AI-SURVEY.md`、`research/LUMEN-RAW-NOTES.md`；`phases/masks-research/RESEARCH.md`、`SKIN-FACE-BODY.md`；`phases/rust-core/PLAN-B.md` 里 B14 和 B14A 两张卡；`phases/rust-core/PLAN-AMENDMENTS.md` 的 A-19。

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文，代码引用保持原文。

## 要做的

**1. 拉到最新。** 两个仓库各先 `git status`——有本地改动就停下报告，不要动；干净就 `git pull --ff-only`。拉不动（不能快进）也停下报告。记下新的提交、标签，以及从上面两个提交以来各有多少个新提交。

**2. 盘点人像相关的功能。** 从最近两个月（2026-09 下旬到现在）的提交、发行说明、界面代码、管线代码、模型文件里找。至少看这些方向，有就写、没有就写没有：人像或人物的自动蒙版（人脸、皮肤、头发、眼睛、牙齿、身体部位）、点选主体、磨皮与肤色、人脸感知的曝光或美白、人像的景深虚化或背景替换、 portrait 类的预设或风格、拍照时的眼里有光和面部识别。每一项写清楚：

   - 做什么，用户怎样用（自动、点选、滑杆、笔刷）。
   - 怎样实现的：哪个文件、哪个函数（`文件:行号`）；推理后端（ONNX Runtime、CoreML、Vision、别的）；模型的名字、来源、大小。
   - 许可：代码的、模型权重的（有没有单独的许可声明）、训练数据的（有没有非商业的限制）。
   - 依赖什么平台能力（只有 Apple 平台能跑吗），权重怎样取得（随包、首次使用时下载）。

**3. 对照我们已有的。** 把第 2 步找到的每一项和我们的蒙版两波比：我们已经计划的（Lumen RAW 的四类：天空、人物、主体、背景；点选物体；边缘细化；风光组和近景深度；皮肤和面部的像素级蒙版；整人身体）、我们计划里有但它们做得不一样的、它们有而我们完全没有的。

**4. 借鉴清单。** 每个候选一项：是什么；出处；怎样实现；许可（代码、权重、训练数据各一句）；依赖；估算（几条 lane、各几小时）；落在哪一波（B14、B14A，或者要新开一波）；风险（隐私是不是都在本机、权重从哪里下载、体积）；推荐（现在就收、以后再收、不收）和理由。

**5. 待用户定的事**，不超过五件，每件给推荐。

## 纪律

- **只读**：除了两个参考仓库里的 `git pull --ff-only`，不往任何地方写东西（我们仓库里已有的文件一个不改）；产物只落在 `.work/gsd/phases/portrait-research/` 下面（新建目录）。**不提交**——产物留在工作区，由塔台收编。
- 不构建，不打开图形程序，不运行它们的程序，不下载任何模型权重或软件。
- 不读 `/Volumes/UNITEK/Documents/Development/darktable` 和 `darktamer` 两个目录。不读、不打印任何凭据文件。不碰用户照片库。
- 机器上可能有别人同时在跑的 omp 会话，不是你的，不碰。
- **每一处事实都要亲自读到源码原文**，带 `文件:行号`。「某个功能没有」这类否定性结论要有两个互相独立的证据，其中一个是你直接看到了全貌（把那个目录整个列出来搜过）。权重的许可没有单独声明就写「没有单独声明」，不要替它推断成和代码一样。
- 数字不编。到时间上限就交已有结果。
- 总墙钟不超过 150 分钟。

## 交付

1. `.work/gsd/phases/portrait-research/PORTRAIT.md`（中文正文，英文标题）：两个仓库各自的变化；功能盘点（一张总表加逐项说明）；对照；借鉴清单；估算；风险。
2. `.work/gsd/phases/portrait-research/ONE-PAGER.md`（不超过四十行）：结论；推荐现在就收的几项；待用户定的事（不超过五件，各带推荐）；估算合计。
3. **自审**：写完之后另起一个独立的 `omp -p --auto-approve --thinking max "<复审任务书>"` 实例复审这两份笔记：抽核至少十条出处的 `文件:行号`；核每一条许可说法（代码、权重、训练数据分开核）；核否定性结论的证据。结论头 `PASS / N error + N minor`，输出落同目录的 `review.log`。发现的问题回注修订。复审实例写完结论头之后你的主进程才退出。

stdout 最后一条消息一次性完整输出 `ONE-PAGER.md` 的内容。
