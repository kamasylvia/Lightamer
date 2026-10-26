# M8「FSIM 光谱升维」批 omp 终审（execute 道二次验收，computer-use 实机形态）

## 角色

你是 omp 独立终审眼（第三眼）。zcode 双路验收已 PASS（路 1 `45f88435`、路 2 `f5bbe17c`），你做 computer-use 实机终审：实机走查核心用户可见面 + 独立复核双路报告关键断言 + 三眼对账。工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文。

## 必读正本（按序）

1. `.work/gsd/phases/m8-fsim-spectral/M8-VALIDATION.md` —— phase 签核输入汇编（四 plan 终账/golden 哨兵/probe 真值）
2. `.work/gsd/phases/m8-fsim-spectral/M8-ACCEPTANCE.md`（路 1）+ `M8-ACCEPTANCE-2ND.md`（路 2）—— 对账对象
3. 四 plan 的 `-SUMMARY.md` / `-DECISIONS.md`（同目录）
4. `.work/gui-acceptance/m8/MANIFEST.md` —— executor 走查配方（迁移 UX 四面等的 fixture 路径与操作步骤，复用其配方独立复现）

## 机器与卫生纪律（硬约束）

- 你是当前唯一重活/GUI 占用者。起跑前：`Scripts/machine-guard.sh --wait` 过门；同命令链内 `ps aux | grep -iE "Lightamer|xctest"` 验证清零。
- 全套伴跑看门狗：`Scripts/machine-guard.sh --monitor 14400 > /tmp/guard-mon-omp.log 2>&1 &`（收工 kill）。
- **复用现成构建，不重建**：`~/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app`（binary mtime 10-26 07:29，已含全部产品面 commit；其后的 af84ddc1/903d23fe = test/docs only）。启动该 app 走查。
- 禁改任何源码/测试/构建文件；收工时 `git status --short` 须仅含你的报告与截图新增（tracked 零 diff）。
- GUI 实例用后 quit；测试期间写入的 UserDefaults（观察用键）收工清理；临时文件放 /tmp 即弃。

## 走查职责（实机）

1. **迁移 UX 四面实机复现**（按 gui-acceptance/m8/MANIFEST.md 配方，fixture 用其登记路径）：
   - ①旧档（process v1 密度域 film sidecar）打开 → pristine 语义不弹迁移（如配方如此）
   - ②非 pristine 旧档 → 迁移入口可见（按钮/入口按 MANIFEST 配方）
   - ③确认 sheet → 确认后迁移完成
   - ④渲染翻面：迁移后 readout/渲染走光谱臂（对照配方登记的观感/readout 变化）
   - 每面截图存证。
2. **Film 面板 v2 档走查**：面板 readout（solve 值）可见、Solve 按钮在位、曝光语义观感正常；**面板零新增控件** = AX 树实机对照 FilmPanelSpectralUITests 源清单快照（快照路径见该测试文件）。
3. **静置卫生**：编辑面静置 40s，Activity Monitor 或 ps 采样 CPU/RSS——CPU 应 ≈0%（壳交接后基线 0.0%；绝对门 <10% 名义）。
4. **回归抽查**：迁移后的图打开 → 编辑器 → 视口渲染 + 直方图/读出链活；undo 边界（迁移操作可撤销与否按 SUMMARY 申报语义核）。

## 文本复核职责（双路对账）

- 从两路报告各抽 **≥3 条核心断言**独立亲证（读码/机检，如 golden 哨兵值在测试文件在位、RenderProcess v2 五件套、NOTICE 措辞）。
- 两路 obs 清单逐条过：重叠面、矛盾面（如有）单独列「三眼对账」节。

## 产出契约（两件，缺一不可）

1. **落盘正本**：`.work/gsd/phases/m8-fsim-spectral/ACCEPTANCE-OMP.md` —— 结论头第一行 `PASS / N B + N M + N m + N obs`；逐走查面对账表（面/配方预期/实机观察/判定）；三眼对账节；证据索引。截图存 `.work/gui-acceptance/m8/omp/`。
2. **stdout 最终消息**：全部结论**合并为最后一条消息一次性完整输出**（不拆多条）。

## 边界

- 不跑全套测试（双路已各跑一轮 4286/46/0 同值）；如需定向单测佐证（如 SpectralDualArmGoldenTests），可跑单类 `Scripts/test-direct.sh --bundle <域> '<类名>'`，跑前 guard。
- blocking 判据：用户可见功能坏 / 走查面与申报矛盾 / 数据破坏风险。观感偏好与配方外形态 = minor/obs。
