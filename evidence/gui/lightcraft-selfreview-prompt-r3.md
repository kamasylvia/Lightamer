# LightCraft GUI 计时自审 R3（只复核 R2 的 1 error + 3 minor）

只读。R2 = 1 error + 3 minor，见 `evidence/gui/lightcraft-SELFREVIEW-r2.md`。报告已修订。

## 输入（只准读这些）

- 报告：`.work/gsd/phases/rawspeed-backend/GUI-lightcraft.md`
- CSV：`evidence/gui/lightcraft-m1m2.csv`、`evidence/gui/lightcraft-m3.csv`
- R2：`evidence/gui/lightcraft-SELFREVIEW-r2.md`

**禁止**：读其它 lane 产物、运行 App、改任何文件（除结论文件）、截图、读 `$G`（已被删除）。

## 逐项核对（只这四项）

1. **R2-E1（PARTIAL）**：冷表启动列是否改为 CSV 中位 2.31 / 2.30 / 2.31；脚注是否说明「窗口→稳定 = 逐次差值的中位，故不与两列中位之和严格相等」；§2 是否同步 2.31/2.30/2.31。
2. **R2-E3（error）**：冷首帧计数是否改为 **12/15（0.08–0.27）+ 3/15（0.51–0.54，均 ARW）**（用 CSV `onset_s` 复算：≥0.5 的正是 25 的 0.506/0.514/0.535）。
3. **R2 新 minor-1**：报告中「1.12–1.80」是否全部改为 1.12–1.78（grep 计数应为 0）。
4. **R2 新 minor-2/3**：缩略图每格成本是否按档位列（4.35 @10 000 / 5.70 @1 000 / 18.9 @100），摘要不再单写 ~4.3；热主渲染摘要是否带「9/12 行」限定。

## 输出

写 `evidence/gui/lightcraft-SELFREVIEW-r3.md`：

- 第一行结论头：`PASS` 或 `N error + N minor`
- 四行表：项 → FIXED / NOT FIXED → 证据（行号 + CSV 复算）
- 若发现新问题另列
