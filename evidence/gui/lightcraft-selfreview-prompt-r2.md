# LightCraft GUI 计时自审 R2（只复核 R1 的 5 error + 7 minor）

只读。R1 结论 = 5 error + 7 minor，见 `evidence/gui/lightcraft-SELFREVIEW.md`。报告已修订。

## 输入（只准读这些）

- 报告：`.work/gsd/phases/rawspeed-backend/GUI-lightcraft.md`
- CSV：`evidence/gui/lightcraft-m1m2.csv`（现含 `step_*` 列与 `spawn_to_window_s`）、`evidence/gui/lightcraft-m3.csv`
- 源码（只读）：`/Users/Shared/lightamer-gui-test/lightcraft/src/lightcraft-0.21.1/`（若已不存在则跳过源码项，按报告引用与实际文件对比仅限仍在的路径）
- R1 报告：`evidence/gui/lightcraft-SELFREVIEW.md`

**禁止**：读其它 lane 产物、运行 App、改任何文件（除结论文件）、截图。

## 逐项核对

1. **E1 启动→窗口**：报告 §0/§2 是否改为与 CSV `spawn_to_window_s` 一致（2.26–2.34），且表内「窗口→稳定」= `total − spawn_to_window` 自洽（容差 0.01 s）；§5/§9 是否同步。
2. **E2** ARW `lastRenderMs` 上限是否改为 630。
3. **E3** 首帧计数是否改为 13/15（0.08–0.27）+ 2/15（0.51–0.54）。
4. **E4** 热表是否不再声称「0.572–0.603 首次访问」；是否写明 `step.fullSource` 12/12 cached、`sharpMs` 0–34.5、`lastRenderMs` 9 行 114–148 / 3 行 20.7–24.8、`loupe.source` 11/12 render；CSV `step_*` 列能否复核。
5. **E5** 是否分表交代仪器相位（3 帧 0.15 s + 0–0.5 s 轮询；编辑首轮询立即命中），并保留编辑 vs darktable 同仪器说明。
6. **Minors**：§8 相关性顺序、`develop.rs:1188/1191`、`grid.rs` 预取表述、M3b 每格成本（100 档 18.9 ms / 10 000 档 4.35 ms，总时长与 N 无关）、「最大一段解码相关」措辞、§5 ×0.53–0.67、导入/队列数字的来源路径是否补上。
7. **自证数字**：报告 §1 是否写 0.996/0.996/0.991 并说明第一版固定 rect 的 0.788 原因（无法复算，可只查报告内部自洽）。

## 输出

写 `evidence/gui/lightcraft-SELFREVIEW-r2.md`：

- 第一行结论头：`PASS` 或 `N error + N minor`
- 表：R1 项 → 现状（FIXED / NOT FIXED / PARTIAL）→ 证据（文件:行 或 CSV 复算值）
- 新发现另列（若引入新错误）
