PASS / 0 error + 1 minor

复核对象：`.work/gsd/phases/rawspeed-backend/GUI-rawlab.md`（144 行，mtime 2026-11-25 05:27:07）。
对照：`evidence/gui/rawlab-SELFREVIEW.md`（r1）、`evidence/gui/rawlab-{cold,hot,m2,m3}.csv`、`/Users/Shared/lightamer-gui-test/rawlab/logs/{resource-sample.txt,m1hot.json,hot-raf-probe2.log,m2c.json,m3-100b.json}`、`frames/hot-1-ready.png`。
约束：只读；未改报告/CSV；未跑 App；零 push。帧 OCR 走 §9 回退链（vision_analyze_image 报 provider 400、pi 报月配额 429 → GLM-Image-MCP）。

## 逐条结论

| 条 | 结论 | 一句话 |
|---|---|---|
| E1 | PASS | §2 line 85 = 0.613–0.643，与 `rawlab-m2.csv` 最小/最大值一致 |
| E2 | FAIL | 来源注记只在 §3；§0/§4/§9 未注；2.82 s 的 stdout 未落盘 |
| E3 | PASS | `logs/resource-sample.txt` 存在，96% / RSS 4.0→1.4 GB / swap 6.98/8 GB 与命令、时刻一致 |
| E4 | PASS | 7.27 s 已加入并核到 `m1hot.json` rep1 + 完整 RAF 帧；≥86 s 已限定负载态 |

## Error 1（E2）2.82 s 仅在 §3 注明来源，§0/§4/§9 仍是无来源数字；stdout 未落盘

**已落地部分**

- line 89–90（§3）已写「该轮 stdout 实测」「prepare 2.82 s（stdout 实测）」，并解释 `m3-100b.json` 的 `prepare=2.65` 为「脚本把起点设在 apply 按下之后」。
- 算术自洽：2.82/100=28.2 ms、2.65/100=26.5 ms、120/1100=109.1 ms、109.1/28.2=3.87≈3.9×，§4/§9 的派生数字不冲突。

**未落地部分**

- line 33（§0 表）、line 45（§0 判定句）、line 99（§4 表）、line 144（§9 外发稿）仍直接写 2.82，无来源、无脚本-bug 说明。尤其 line 144 是要贴到 issue 的稿子，读者无法从外发文本回溯到 §3 的注记。
- `$G/rawlab/logs/` 全目录 `grep -rn "2\.82"` = 0 命中；唯一 n=100 原始 JSON `m3-100b.json` = `{"n": 100, "prepare": 2.65, "done": 2.6544389724731445}`。`evidence/gui/rawlab-m3.csv`（mtime 05:15:33）是事后汇总，不是独立 stdout。
- 「脚本起点 bug」与 `prepare≈done`（Δ=4.4 ms）相容，但脚本与 stdout 均未保存，无法判定是起点还是终点边界错；r1 回修选项 1 要求的「哪一轮、起止时刻」仍未提供。line 90 把 2.82 同时标为「复测 stdout」，而复测的原始 JSON 只有 2.65，这一点最容易被读者抓住。

**可回修（二选一）**

- A（保留 2.82）：在 line 33 单元格、line 45 句、line 99 行、line 144 句各补「（2.82 s 为脚本外 stdout 实测；`m3-100b.json` 的 prepare=2.65 系计时边界误置，见 §3）」，并把该轮 stdout 原文（轮次 + 起止时刻 + 输出）落 `$G/rawlab/logs/m3-100-stdout.txt`，line 89 改为引用该文件。
- B（改数）：全文 2.82→2.65、28→26.5 ms/张；`26–30 ms/张` 收为 26.5（或注明 26.5–30 的来源）；`>109 ms/张 每张成本 ≥3.9×` 按 109.1/26.5=4.1× 重算；`rawlab-m3.csv` 的 `prepare_s` 同批改 2.65；删除 line 89 的「脚本起点 bug」句。

## E1 PASS

- line 85：`onset 0.613–0.643 s，ready 1.107–1.137 s`。
- `rawlab-m2.csv`（= `logs/m2c.json`）：onset 最小 rep1 `0.6130459`→0.613，最大 rep4 `0.6427290`→0.643；ready 最小 `1.107385`→1.107、最大 `1.137301`→1.137。
- line 27 的 `0.62 s` 是 10 个 onset 的中位（(0.619488+0.620516)/2=0.6200），不是区间，保持即可。

## E3 PASS

- 文件存在：`/Users/Shared/lightamer-gui-test/rawlab/logs/resource-sample.txt`（555 B）。
- 时刻、命令、输出逐条在案：
  - `05:10:24` `ps -o pid,%cpu,rss,state -p 13067` → `95.9 / 4003408 KB / R`（报告 96% CPU、RSS 4.0 GB）。
  - `05:12:56` `ps -o pid,%cpu,rss -p 13067` → `70.2 / 1410048 KB`（报告 RSS 1.4 GB；文件注释 1.38 GB）。
  - `05:12:56` `sysctl vm.swapusage` → `total 8192.00M / used 6978.50M / free 1213.50M`（报告 swap 6.98/8 GB）。
- 引用一致：line 43、135 显式引 `logs/resource-sample.txt`；line 20/83/144 同数。相对路径按 §1 的 `G` 解析为 `$G/rawlab/logs/`，存在。
- 注：文件 mtime 05:27:15（r1 后落盘的事后转录），内部时刻与 `hot-raf-probe2.log`（05:13:32）吻合；作为点位存证可接受，但不是原始 shell 捕获。

## E4 PASS

- 首轮 7.27 s 已加入：line 20 / 43 / 83 / 115 / 144；line 43 明引 `m1hot.json` rep1 与 `frames/hot-1-ready.png`。
- `logs/m1hot.json` rep1：`sample=Fujifilm-GFX100S-14bits-uncompress-4_3.RAF`，`onset=6.4439`，`ready=7.2705`。
- 帧核验（只读）：
  - `frames/hot-1-ready.png` 2640×1632；画布区（x 22–82%、y 14–94%）mean=76.9、`bright_frac=0.254`；同轮 spinner 帧 `hot-0-ready.png`/`hot-2-ready.png` mean=29.5、bf=0.010。
  - `hot-1-onset.png` 与 `hot-1-ready.png` md5 同为 `d83287d90090f29692044e5d930a6fe3`（onset 时已是同一完整帧）。
  - 与重测轮完整 RAF 帧 `c2-Fujif-0-ready.png` 的整窗灰度相关 r=0.983（vs `c2-Nikon-0-ready.png` 0.633、`c2-7RM5--0-ready.png` 0.182），不是错配到 NEF/ARW。
  - GLM OCR 状态栏：`Fujifilm-GFX100S-14bits-uncompress-4_3.RAF` / `1536 × 1152 · sRGB`（4:3，与 RAF 样张一致）。
- 「≥86 s」限定：line 20/43/115/144 均带「负载态」，line 135 写「负载态上界」；line 119 是唯一漏限定处（见 minor 5）。

## Minor（6，不改变四条结论）

1. line 91「当时 App 81% CPU」无存证：`resource-sample.txt` 只有 95.9% 与 70.2%，没有 81%。可回修：改为「采样 70–96% CPU（`logs/resource-sample.txt`）」或删该括号。
2. line 20/83 的「点位采样」未给文件路径，只有 line 43/135 给了。可回修：line 20 首次出现处补「（`logs/resource-sample.txt`）」。
3. line 135「本 lane 之前的历史负载」超出采样内容：文件只记「当时无其它重活」+ swap 用量，未记何时累积。可回修：改为「采样时 swap 已用 6.98/8 GB；何时累积未测」。
4. line 69/140「本文所有数字来自重测轮」与新增的首轮 7.27 s 矛盾。可回修：两处各加「（唯一例外 = 首轮 7.27 s；端点帧已核为完整 RAF 图，见 §0/§8）」。
5. line 119「86 s 热切换冻结」未带负载态。可回修：改「负载态 86 s 热切换冻结」。
6. `m1hot.json` 同轮 RAF rep3/5/7/9/11 的 ready≈0.97–1.12 s 是旧判据把转圈误判（同轮 hot-0/hot-2 帧 bf=0.010 已证）；报告只取 rep1 7.27 s，未说明其余 5 条。可回修：§8 加一句「同轮其余 RAF ~1 s 均为旧判据假阳性（转圈帧），不计入；仅 rep1 端点帧经人工核验」。

## 未覆盖 / 范围外

- 未复跑 App；未核 §1 的二进制 SHA/Gatekeeper；未逐条复审 r1 的 12 minor。
- r1 minor 9（就绪判据实现）仍未闭环：报告 line 69 写 `bright_frac>0.05` + 帧差<0.5，但 `_harness/rl2.py` 用 `mean>20 && std>8`、`stable_thresh=0.4`；就绪帧 `bright_frac` 本机复算 0.23–0.46，不是报告写的 0.55。按窄口径不计入本轮 error，留给 minor 收口批。

## E2 复核（2026-11-25 05:37:12 版；原始正文为 05:27 版快照）

**结论：E2 未完全闭合（FAIL，仍计 1 error）。**

已闭合部分：

- `$G/rawlab/logs/m3-100-stdout.txt` 已落盘（709 B，mtime 05:37:12），第 11 行 `prepare wall 2.82 enabled True`、第 13 行 `M3a 2.65 | 已保存 0 张 · 未变化 100 张`，并在末尾注明 `m3-100b.json` 的 `prepare=2.65` 系计时起点误设在 apply 按下之后。
- §3 行 90 已引用该转录，并把 2.82/2.65 归为「复测同值，唯一带计时的 n=100 轮」；§3 行 89 已把真改首轮标为「未打印 prepare/apply 计时」。
- §0 行 33 表、§4 行 98–99、§9 行 144 已把 2.82/2.65 标为「复测轮/复测」，真改首轮标为「计时未打点」。
- 算术自洽：2.82/100=28.2 ms、2.65/100=26.5 ms、120/1100=109.1 ms、109.1/28.2≈3.9×。

残余（未闭合）：

- **§0 行 45** 仍写「100 张真改的 apply 2.65 s、准备 2.82 s」，与 §0 行 33、§3 行 89 的「真改首轮计时未打点；2.82/2.65 属复测轮」直接矛盾。复测轮结果是「未变化 100 张」，其 2.65 s 不能作为「100 张真改」的 apply 证据。应改为「100 张复测的 apply 2.65 s、准备 2.82 s」。
- **§0/§4/§9 仍未注 stdout 来源与脚本起点 bug**：三处只有「复测轮/复测」标签；E2 要求的「§0/§3/§4/§9 must state the 2.82 s prepare value's provenance (stdout) and explain ... as a script-start bug」目前只在 §3 行 90 满足。至少在这三处各补「（stdout 转录见 `logs/m3-100-stdout.txt`；`m3-100b.json` 的 prepare=2.65 系计时起点误置）」。

**Minor 状态**（原正文 6 项）：

- 已闭合：minor 1（行 91 的 81% CPU 已改为「采样 App 70–96% CPU」并引 `logs/resource-sample.txt`）、minor 2（行 20 首次出现处已补文件路径，行 83 为同数二次提及）、minor 4（行 69/140 已加首轮 7.27 s 例外）、minor 6（行 140 已说明同轮 RAF ~1 s 为旧判据假阳性）。
- 仍存：minor 3（行 135「本 lane 之前的历史负载」仍超出采样内容）、minor 5（行 119「86 s 热切换冻结」未带「负载态」）。
- 故首行按残余计：1 error + 2 minor。
## E2 终核（05:40 版，覆盖上文 05:37 版复核）
- PASS：§0 行 33（复测轮 + stdout 转录）、行 45（复测）、§4 行 99（stdout + `m3-100b` 计时起点误置）、§9 行 144（复测 + stdout 转录）；§3 行 90 明注 `m3-100b.json` 的 prepare=2.65 系计时起点误置，§9 经该转录可追溯；行 119/135 已补「负载态」/「何时累积未测」，minor 3/5 闭合；数字自洽（28.2/26.5 ms、109.1/28.2≈3.9×）。
- Minor：§9 行 144 未复述「m3-100b 计时起点误置」，仅引转录；首行按 0 error + 1 minor 计。
