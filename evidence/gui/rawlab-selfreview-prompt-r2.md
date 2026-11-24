# 复审（窄口径）· RawLab GUI 计时 E1–E4 回修核验

只核验四条 error 的回修是否落地，不做全面重审。只读，不改任何文件。
工作区 `/Volumes/UNITEK/Documents/Development/Lightamer`。
报告 `.work/gsd/phases/rawspeed-backend/GUI-rawlab.md`；原自审 `evidence/gui/rawlab-SELFREVIEW.md`；资源采样 `/Users/Shared/lightamer-gui-test/rawlab/logs/resource-sample.txt`；重测日志 `logs/m1hot.json`、`logs/hot-raf-probe2.log`。

逐条核：
1. **E1**：§2 M2 onset 区间是否已改为 0.613–0.643，且与 `rawlab-m2.csv` 最小/最大值一致。
2. **E2**：§0/§3/§4/§9 的 2.82 s 是否注明了来源（stdout 实测）并解释了 `m3-100b.json` 的 prepare=2.65 是脚本起点 bug；数值是否仍自洽。
3. **E3**：报告中引用的 `logs/resource-sample.txt` 是否存在、内容是否含 96% CPU/RSS 4.0→1.4 GB/swap 6.98/8 GB 的时刻与命令；报告引用是否与文件一致。
4. **E4**：是否已加入「首轮低负载 1 次 7.27 s 完成」并核到 `m1hot.json` rep1 与 `frames/hot-1-ready.png` 是完整 RAF 图；「≥86 s」是否已限定为负载态上界。

写 `evidence/gui/rawlab-SELFREVIEW-r2.md`，第一行 `PASS / N error + N minor`，每条 error 给行号与可回修句子。不改报告、不跑 App、零 push。
