# 自审任务书 · RawLab GUI 计时（Lightamer #26）

你是独立自审 lane。只读，不改任何产品/报告文件，只在指定路径写一份自审结论。

工作区：`/Volumes/UNITEK/Documents/Development/Lightamer`
被测报告：`.work/gsd/phases/rawspeed-backend/GUI-rawlab.md`
数据：`evidence/gui/rawlab-cold.csv`、`rawlab-hot.csv`、`rawlab-m2.csv`、`rawlab-m3.csv`
存证帧：`/Users/Shared/lightamer-gui-test/rawlab/frames/`（仓外；若目录已被删除，注明「帧已按收尾纪律删除」并跳过帧复核）
源码对照（只读）：`/Users/Shared/lightamer-gui-test/rawlab/src/RawLab-0.12.0/`（若已删，跳过源码复核并注明）

## 你要做的事

1. **统计复核**：用 CSV 重算中位/极值，与报告 §0/§2 的数字逐项比对（冷 3 样张 × n=5、热 NEF n=6 + RAF 6 次超时 + 1 次 86 s 探针、M2 n=10）。任何不一致 = error。
2. **抽 3 次运行复看存证帧**（若帧仍在）：`c2-*-ready.png` 是否为「有图」而非转圈；`probe-ready.png` 是否转圈（用于验证报告里「首版判据误判」的叙述）；相关度自证是否可复算（报告的数字 0.924/0.922/0.856 与帧是否自洽，可用任意合理裁切复算，允许 ±0.05 的解释差）。
3. **归因数字自洽**：报告 §4 的「26–30 ms/张」「2.82 s/100」「>120 s/1100」是否由 §3 数字推得；「解码器占比小」是否有源码依据（`probeRAW` 只读头）或明确标注为推断。
4. **纪律核对**：报告是否如实写了「首版就绪判据错误并重测」；M3b/M3c 的未测/不存在是否有依据；NEF 相关度 <0.9 是否如实标注。
5. **判定句是否带数字**，是否区分「解码器原因」与「架构/代码原因」。

## 输出

写 `/Volumes/UNITEK/Documents/Development/Lightamer/evidence/gui/rawlab-SELFREVIEW.md`：
- 第一行结论头：`PASS / N error + N minor`
- 逐项列：检查项、结论、证据（数字/帧名/源码行）
- error 必须给出可回修的具体句子/数字；minor 列不改也可交付的瑕疵。

不改报告、不改 CSV、不删文件、不跑被测 App。零 push。
