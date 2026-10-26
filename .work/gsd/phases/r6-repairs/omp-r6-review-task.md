# R6 修复批 omp 复核（execute 道二次验收，computer-use 实机）

## 角色

omp 独立复核眼。R6 修复批（导入零行真修 + 三姐妹载体）已过 zcode 综合验收 PASS/0B+0M+0m+2obs——你做 computer-use 实机复核 + 对账。工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文。

## 必读

1. `.work/gsd/phases/r6-repairs/R6-SUMMARY.md` + `R6-DECISIONS.md`（四修法与根因）
2. `.work/gsd/phases/r6-repairs/R6-ACCEPTANCE.md`（zcode 验收——你的对账对象；含 GUI 5/5 复验数据与反自取消结论）
3. 你上场报告 `.work/gsd/phases/m8-fsim-spectral/M8-FIX-ACCEPTANCE-OMP.md`（obs-4 probe 自灭 2/5 = 本批 T1 病灶侧证——本批复核的正主线索）

## 机器与卫生

- 唯一重活/GUI 占用者；guard --wait；同链 ps 清零；`--monitor 7200 &` 伴跑（收工 kill）。
- 复用现成构建：`~/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app`——**注意**：该构建 mtime 早于 R6 修复 commits——**你须先重建**（`xcodebuild build -workspace Lightamer.xcworkspace -scheme Lightamer -configuration Debug -derivedDataPath <同路径>`；guard 前置；构建产物自证含 R6 面后才走查）。
- 禁改源码；收工 tracked 零 diff；GUI quit；defaults 清；/tmp fixture 即弃。

## 复核职责（实机）

1. **导入零行（T1 正主）**：zcode 配方复走 fresh 导入 ≥5 次计时 grid 行到达（对照其 0.54-0.66s 数据）+ **压力腿**：导入进行中切换界面/连开两个导入（原竞态窗口的活体再触发尝试）——核无复活/无零行。
2. **三姐妹载体（T3）**：任选一载体实机链（如 DRT：编辑器开图 → 设 DRT → ⌘W 关 → 图库重进 → readout/渲染 DRT 仍在〔修复前会静默掉〕）；film/raw 载体各一条快速核（面板启用态跨 close 存活）。
3. **回归面**：正常导入/编辑流不受 invalidate 修法影响（大导入 N≥16 完成态照常发布——FIX2-01 面不回归）。
4. **对账 zcode 报告**：obs-1（生产缝法概率性假绿申报）/obs-2（并行账本 commit）各评一句。

## 产出契约

- 正本 `.work/gsd/phases/r6-repairs/R6-ACCEPTANCE-OMP.md`：结论头 `PASS / N B + N M + N m + N obs` + 逐面判定表 + 对账节。截图 `.work/gsd/phases/r6-repairs/omp-evidence/`。
- stdout 最终消息一次性完整输出。
