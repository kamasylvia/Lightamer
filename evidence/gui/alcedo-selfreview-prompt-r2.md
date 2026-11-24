你是 Alcedo GUI 计时 lane 的**第二轮**域内自审。第一轮结论 = 3 error + 7 minor（已存 `evidence/gui/alcedo-SELFREVIEW-r1.md`）。只读，不改报告/CSV/帧。
输入：`.work/gsd/phases/rawspeed-backend/GUI-alcedo.md`、`evidence/gui/alcedo-*.csv`、`/Users/Shared/lightamer-gui-test/alcedo/frames/`。
只核以下回修项是否真的修好，并快速扫有无新 error：
- E1 §5 GFX 行已改为「无 file-matched CLI 数字」，不再用 SPIKE 556 ms 比 GFX；ARW 行保留。
- E2 M3c 已改为同口径命令往返：14.74/33.15/23.68 vs 5.10/5.43/4.84 = 2.9×/6.1×/4.9×；stable 值只作参考。
- E3 截帧率已按相分列（编辑 2.9–3.2 Hz、黑屏 6.8–7.8 Hz、zoom 3.9 Hz；3 帧地板 ≈1.0 s/≈0.4 s，8 帧 ≈2.4 s）。
- M1 热切示例已拆 rep4/rep10；M2 已注明 hot 首轮作废、`measure1b.py` 重跑、zoom 用 `measure_zoom.py` 双击；M3 舍入 0.82/0.80/0.89、1.62/1.04、3.42、2.95–3.36、4,615 s；M5 已注源码 clone = v0.3.3；M6 已写 ≥16× / ≈21×；M7 已注启动器单次目检。
- M4（尚未删除）：§7 是待执行清单，不是完成声明；最终删除在自审后做，不要判 error。
输出：覆盖写 `evidence/gui/alcedo-SELFREVIEW.md`，第一行 `PASS` 或 `N error + N minor`；每条 finding 给依据。3 分钟内完成，不要改其它文件。
