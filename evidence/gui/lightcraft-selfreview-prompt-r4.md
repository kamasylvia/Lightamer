# LightCraft GUI 计时自审 R4（只复核 R3 的 1 minor + 备注 3）

只读。R3 = 0 error + 1 minor。报告已修订。

## 输入

- 报告：`.work/gsd/phases/rawspeed-backend/GUI-lightcraft.md`
- CSV：`evidence/gui/lightcraft-m1m2.csv`、`evidence/gui/lightcraft-m3.csv`
- R3：`evidence/gui/lightcraft-SELFREVIEW-r3.md`

**禁止**：运行 App、改文件（除结论）、读 `$G`（已删）。

## 只核三点

1. §0 读法（原 `:28`）与 §6 第 2 条（原 `:133`）是否已把「114–148 ms」限定为「9/12 行」，并把 3/12 行 20.7–24.8 ms 并列；是否不再出现「缓存命中 / 未命中」的二分表述。
2. §4 每格成本与 §8 风险条是否补齐 1 000 档 5.70（三档并列）。
3. §2 首帧句是否补上 3/15（0.51–0.54，均 ARW）。

## 输出

写 `evidence/gui/lightcraft-SELFREVIEW-r4.md`：第一行结论头 `PASS` 或 `N error + N minor`，三行表 + 证据（行号）。
