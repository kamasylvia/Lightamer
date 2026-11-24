你是 Alcedo GUI 计时 lane 的**第三轮（最终）**自审。只读/只写结论文件。工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。
第二轮结论 = 1 error（称 evidence 下无 alcedo CSV/_harness）+ 5 minor；实际文件均在（`ls evidence/gui/alcedo-*` 6 个 CSV + `_harness/`），第二轮可能误用了 `git ls-files`（文件尚未提交）。请用文件系统核，不要用 git。
核 6 件事即可：
1. `ls -l evidence/gui/alcedo-*.csv evidence/gui/_harness/{alcedo.py,measure_zoom.py,measure1b.py,measure3.py,cap_shot.py}` —— 必须存在，且 CSV 头/行数与报告引用名一致。
2. 报告 §1.4/§8 的截帧带已改「编辑 2.76–3.53、冷开 4.76–7.38、热黑屏 7.75、zoom 3.91 Hz」。
3. 报告 §0 首见 Z8 = 2.97（不是 2.95）；§1.4 已区分 std≥40（首见）与 std≥8（就绪）。
4. §0 21× 已写分母 `65.6/(3.996−0.80−0.08)=21.1`；100 档导入 = 0.137 s。
5. 复核 cold/hot/edit 三个 median（3.846/3.996/3.616；3.775/57.914/34.079；0.163/1.548）与 `alcedo-m1m2.csv`+`alcedo-hot-zoom.csv` 一致。
6. 抽 `cold-1-2-ready.png`、`hot-2-10-ready.png`、`zoomx-2-after.png` 三帧仍可读、内容正确。
输出：覆盖写 `evidence/gui/alcedo-SELFREVIEW.md`，第一行 `PASS` 或 `N error + N minor`，下面 5–10 行依据。2 分钟内完成；不改其它文件。
