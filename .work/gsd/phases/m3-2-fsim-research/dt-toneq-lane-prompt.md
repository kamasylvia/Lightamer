# darktable tone equalizer 曝光方式调研（omp 执行；纯文本零 commit 零构建）

你是 darktable tone equalizer 曝光方式调研员。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**纯文本调研**。

## 背景

用户指出：**darktable 的 tone equalizer 调整曝光的方式，是我们需要引入的**。你调研 tone equalizer（toneeq）的曝光调整机制与我方现行曝光链（exposure / toneequal iop）的差距，产出可学习点。

## 调研面

1. **dt toneeq 曝光机制深读**：`/Volumes/UNITEK/Documents/Development/darktable`（`git show origin/main:` 读法）——`src/iop/toneequal.c` + `src/common/` 相关 + OpenCL `toneequal.cl`。重点：**曝光调整方式**——toneeq 如何处理曝光（曲线控制点/自动目标检测/阈值面/局部拉深），与我方 exposure iop（线性 EV 偏移）+ toneequal iop（M3-4 落地的宽容度面板）的差异。
2. **我方现状精确测绘**：我方 toneequal（M3-4 落地）——宽容度面板（descriptor 曝光不变/拉深/恢复）、曝光 iop（EV 偏移 + 黑场/白场）；我方 toneeq 的曝光调整能力 = 哪些已有、哪些缺。
3. **差距逐条**：dt toneeq 做了而我方没做的曝光相关能力——逐条评估（我方是否需要/实现路径/价值）。特别关注：**阈值面自动计算**（dt toneeq 的 auto 模式——直方图分析自动设置控制点）、**局部曝光补偿**（区域感知的曝光调整——不是全局 EV）、**高光/阴影保护曲线**（保护曲线在拖曝光时的形态变化）。
4. **可学习点结论**：逐条（立即可学 / 需要设计 / 不适用）+ 实现路径草案。

## 产出契约

`.work/gsd/phases/m3-2-fsim-research/DT-TONEEQ-EXPOSURE-RESEARCH.md`（一个文件）：dt 机制深读 + 我方现状 + 差距逐条 + 可学习点结论 + OQ 清单。
