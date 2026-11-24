# LightCraft GUI 计时域内自审（只读）

你是 Lightamer #26 的执行域内自审 lane。**只读**，不修改任何文件，除了写出结论文件。

## 输入（只准读这些）

- 报告：`/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/rawspeed-backend/GUI-lightcraft.md`
- CSV：`/Volumes/UNITEK/Documents/Development/Lightamer/evidence/gui/lightcraft-m1m2.csv`、`.../lightcraft-m3.csv`
- 存证帧：`/Users/Shared/lightamer-gui-test/lightcraft/frames/`（`cold-<id>-<epoch>.png` 冷开就绪帧、`thumb-before.png`/`thumb-after.png`/`thumb-diff.png` 单格刷新证明、若干 debug 图）
- 源码（只读）：`/Users/Shared/lightamer-gui-test/lightcraft/src/lightcraft-0.21.1/`（官方 v0.21.1 源码，用于核对报告里的代码路径引用）

**禁止**读其它 lane 的报告或历史归档；禁止运行 App、禁止改动产物、禁止截图。

## 要核的

1. **统计自洽**：用 CSV 重算报告 §0/§2 的中位、min/max（冷 n=5×3、热 n=12、编辑 n=12、M3 三档），逐个对照报告表里的数字；发现不一致即为 error。
2. **抽 3 次运行复看存证帧**：`cold-25-*`、`cold-26-*`、`cold-27-*` 各取一张，确认是完整图像（不是加载态/黑帧），并用画面内容核对报告声称的样张（ARW 绿地/池塘、RAF 树林、NEF 田野）。若有明显不符即 error。
3. **归因数字自洽**：粘贴 10 000 张 0.347 s ⇒ 34.7 µs/张；可见缩略图 92 次 / 0.40 s ⇒ ~4.3 ms/张；1 000 张 50 ms、100 张 18 ms 的线性/固定开销说法是否成立；引用代码路径 `crates/engine/src/cmd/develop.rs` 的 `develop.paste` 与 `crates/ui-egui/src/panels/grid.rs` 的虚拟化注释是否真实存在且语义相符（用 grep 核对行号/内容）。
4. **口径诚实性**：报告是否明确交代 10 Hz + 3 帧 + 0.5 s 轮询造成的 ~0.65 s 墙钟下限、M3 目标为生成 JPEG（非 RAW）、RAF 自证 0.788 未过 0.9、仪器事故轮次已排除。缺任一项记 minor。
5. **结论头与判定句**：是否与数据一致（懒渲染合格；批量与解码器无关）。

## 输出

写到 `/Volumes/UNITEK/Documents/Development/Lightamer/evidence/gui/lightcraft-SELFREVIEW.md`：

- 第一行结论头：`PASS` 或 `N error + N minor`
- 逐项：核对项、方法（命令/文件）、结果、若有问题给 `file:line` 或数字证据
- 不写客套话，不重复报告正文
