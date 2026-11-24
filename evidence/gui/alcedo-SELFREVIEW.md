PASS
- 文件系统核（非 git）：`evidence/gui/alcedo-{m1m2,hot-zoom,zoom,m3-100,m3-1000,m3-10000}.csv` 6/6 在位（m1m2 41 行、hot-zoom 16 行、zoom 6 行、m3 各 12 行），`_harness/{alcedo,measure_zoom,measure1b,measure3,cap_shot}.py` 5/5 在位。第二轮「文件不存在」= 误用 `git ls-files`（全目录尚未提交），实为假 error。
- §1.4（line 104）与 §8（line 173）截帧带 = 「编辑 2.76–3.53 / 冷开 4.76–7.38 / 热 7.75 / zoom 3.91 Hz」，两处一致 ✓。
- §0（line 16）首见 Z8 = **2.97** s（7RM5/GFX/Z8 = 3.16/3.36/2.97），非 2.95 ✓；§1.4（line 105）已分「std≥40 = 首次可见」与「std≥8 = 就绪」两个门槛 ✓。
- §0（line 65）21× 分母已写 `65.6/(3.996−0.80−0.08)=21.1` ✓；§0（line 54）/§3（line 128）100 档导入 0.137 s（0.021+0.116）✓。
- median 复核（CSV 重算）：cold 3.846/3.996/3.616 ✓（7RM5 第 3 值=3.846，GFX=3.996，Z8 排序第 3=3.616）；hot 3.775/57.914/34.079 ✓（GFX 4 值中位 (54.293+61.535)/2=57.914）；M2 edit `t_editor_set` 中位 (0.16302+0.16386)/2=0.163、ready 中位 (1.5280+1.5681)/2=1.548 ✓；首变 0.929 s 对第 5/6 值也成立。
- 三帧抽检（3008×1632，视口灰度 std 69.3/69.0/70.0，min0/max255 非全黑，画面为真实照片 + 「对比」工具条 chrome）：`cold-1-2-ready.png` 草坡树林、`hot-2-10-ready.png` 森林远景、`zoomx-2-after.png` 同景放大后细节（与 zoom 前帧同场景，几何一致）✓。
- minor（不阻塞）：`alcedo-m1m2.csv` 的 `error` 列非空共 **15** 行（10 行 hot `unsupported operand … 'float' and 'list'` + 5 行 zoom `'0'`），报告 §1.4 只写「保留 10 行 error」——该句主语是 hot 首轮作废，事实无误，仅计数未含 zoom 5 行，属表述可补全。
- 无 error；报告数字与 CSV/帧三方一致，可交付。
