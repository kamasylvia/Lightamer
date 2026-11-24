FAIL / 4 error + 12 minor

自审对象：`.work/gsd/phases/rawspeed-backend/GUI-rawlab.md`（2026-11-25 05:15 版）
复核材料：`evidence/gui/rawlab-{cold,hot,m2,m3}.csv`；`/Users/Shared/lightamer-gui-test/rawlab/{frames,logs,batch,home}`（帧 81 个、源码树均在位，未按收尾纪律删除）；只读源码 `RawLab-0.12.0`。未跑被测 App，未改报告/CSV。

## 复核口径（可复跑）

- CSV 中位/极值：n=5、n=10 取偶数位两值平均（M2 ready = (1.117+1.121)/2 = 1.119）；n=6 取第 3/4 值平均。
- 帧统计：窗口灰度缩到 320 px；画布区按报告口径 x 22–82% / y 14–94%；bright_frac = 灰度>85 占比。
- 相关度：就绪帧取照片矩形（内缩 0–5%）→ 灰度 240×180；参考图 `ref-*.png` → 240×180；Pearson。
- 源码行号以 `RawLab-0.12.0` 只读树为准。

## Error（4）

### E1 §2 M2 onset 区间下限错（统计不一致）

- 检查项：§0/§2 的 M2 极值 vs `rawlab-m2.csv`（= `logs/m2c.json`）。
- 结论：ready 1.119（1.107/1.137）✓、onset 中位 0.620 ✓；但 §2 写 **"onset 0.617–0.643 s"**，CSV 最小值为 **rep1 = 0.613**（0.6130459），不是 0.617。
- 回修：第 85 行 `onset 0.617–0.643 s` → `onset 0.613–0.643 s`（0.617 在 10 个值里不存在；0.6178 是 rep8，不是最小值）。

### E2 §3 复测 prepare 2.82 s 与唯一 n=100 原始日志矛盾

- 检查项：§3「100 张（复测同值）：prepare 2.82 s」/ §4「预检 100 张 2.82 s」/ §9 同值 vs `logs/m3-100b.json`。
- 结论：`m3-100b.json` = `{"n":100,"prepare":2.65,"done":2.6544389724731445}`。唯一 n=100 的复测日志记录的 prepare 是 **2.65 s**（与报告的 apply 2.65 s 同值），没有任何日志产生 2.82；另一条 `m3-100.json` 只有 `{"closed":null,"n":31}`。CSV `prepare_s=2.82` 与报告一致，但与原始日志冲突，属同批数据缺口。
- 回修（二选一）：
  1. 补 2.82 s 那一轮的日志（哪一轮、起止时刻），并把 `logs/m3-100b.json` 标注为「prepare 2.65」的另一轮；或
  2. 把 §0/§3/§4/§9 的 2.82 s 改为 2.65 s，并把「≈28 ms/张」改为「≈26.5 ms/张」（`26–30 ms/张` 区间同步收为 26.5–30），CSV `prepare_s` 同批订正。

### E3 CPU/RSS/swap 数值无存证（§0/§2/§3/§4/§8/§9）

- 检查项：「96% CPU、RSS 4.0 GB→1.4 GB、swap 6.98 GB/8 GB」（§0 line 20、§2 line 83、§4 line 43/115、§8 line 135、§9 line 144）与「当时 App 81% CPU」（§3 line 91）。
- 结论：`$G/rawlab/logs/` 只有测量 JSON/文本（m1cold2、m1hot2、m2c、hot-raf-probe2 等），全目录 grep 无 `ps`/`vm_stat`/`sysctl vm.swapusage`/`%CPU` 记录；`omp-gui-rawlab.log` 仅 "Working..."。这些数字目前是终端口述，不可复核；而 §8 的「环境因素」辩护与 §6 的「内存膨胀」归因都依赖它们。
- 回修：在 §1 或 §6 附一条采样的原文（`ps -o pid,rss,%cpu -p <pid>` 与 `sysctl vm.swapusage` 的时间戳 + 输出），落 `$G/rawlab/logs/` 并在报告引用；否则删除具体数值，改为「进程持续高 CPU、RSS 与交换占用显著上升（未计数）」。

### E4 「RAF 热切换 ≥86 s」绝对化，与首轮有效观测冲突

- 检查项：§0 line 20 / §2 line 43 / §5 line 115 / §9 line 144 的「100 MP RAF 热切换 ≥86 s / 6 次全部超时 / 窗口整幅冻结」。
- 结论：首轮（04:43，低负载）存在一次 **真实的 7.27 s RAF 热切换完成**：
  - `logs/m1hot.json` rep1：onset 6.4439 / ready 7.2705；
  - `frames/hot-1-ready.png`（04:43:47）= 完整 RAF 图（标题 `Fujifilm-GFX100S…RAF`，状态栏 `预览 1536 × 1152 · sRGB`），`hot-1-onset.png` 与 `hot-1-ready.png` md5 同为 `d83287d90090f29692044e5d930a6fe3`——不是「转圈被误判」（对比同轮 `hot-0-ready.png`/`hot-2-ready.png` 才是转圈，mean 31.6 / bf 0.008）。
  - 重测轮确为 6/6 在 25 s 超时、探针 86 s 冻结（CSV 与 `hot-raf-probe2.log` 支持）；两轮差异正是报告 §8 承认的 swap 负载。
- 回修：§0 表中该行改为「**≥86 s（重测轮 6/6 >25 s；探针 86 s 冻结；测量时 swap 6.98/8 GB）**；首轮低负载另观测到 1 次 7.27 s 完成（hot-1-ready 帧为完整 RAF 图）」，§5/§9 同步加这一句；把「≥86 s」限定为「负载状态下上界」而非稳定值。

## Minor（12，不改也可交付）

1. §0 line 7 表头写「n=5，min / max」，单元格主值是中位（7.55/8.21/6.75），括号才是 min/max；建议改「中位（min / max）」。
2. §0「窗口→图稳定」列 = 两位小数中位相减（6.75−2.35=4.40、7.55−2.34=5.21、8.21−2.31=5.90）；逐轮差的中位为 4.42/5.24/5.88（偏差 ≤0.03 s）。建议注明口径。
3. §4「粘贴本身 2.6–3 s」的首次运行「未逐帧打点」（§3 已承认），§4 表未带该限定；建议标「估计」。
4. §4「>120 s（>109 ms/张）…线性劣化」措辞：100 档 ≈28 ms/张 → 1100 档 >109 ms/张（≥3.9×），总时长是超线性，不是线性；建议改「每张成本升至 ≥3.9×」。
5. §0/§2「帧逐字节不变」：实际证据是 320 px 灰度 mean abs diff = 0.00（`hot-raf-probe2.log` dp=0.00），没有保存两帧做哈希；建议写「帧差 0.00」。
6. §3「不是全图解码」只引了 Swift 调用点（`EditorModel+AdjustmentTransfer.swift:171-190`）；原生证据在 `lutools/src/ffi/sony2fuji_hdr.cpp:500-511` → `lutools/src/core/hdr_pipeline.cpp:447-457` → `lutools/src/core/raw_processor.cpp:222-249`（`loadFile(..., inspectOnly=true)`，line 185-198：`metadataOnly→openAndUnpack(true,false,false)`；line 217 注释 "without decoding mosaic pixels"）。建议补引。
7. §5 两处「区间对区间」：含启动 +8%…+31%，同张对比实为 +6.1%/+21.1%/+26.2%（6.75/6.365、7.55/6.236、8.21/6.508）；窗口段 ×2.6–3.5，同张为 ×2.6/2.9/2.9（4.40/1.71、5.21/1.79、5.90/2.05）。数字不冲突，但口径建议写清。
8. 自证参考图 `ref-RAF.png` 为 480×320（3:2），RAF 样张是 4:3（ImageIO 缩略图 1024×768）——参考被非等比压缩。复算仍过门（见下），建议存 4:3 版参考或注明缩放。
9. 最终就绪判据实现未入 `_harness/`：`rl.py` 是首版「帧差 >1.0 + 稳定」、`rl2.py` 是第二版「canvas mean>20 且 std>8」，均无 bright_frac 逻辑。且文字口径「x 22–82%」含检查器左缘（画布右缘 ≈76%）；按该区域复算就绪帧 bf = 0.28（NEF）/0.23（RAF）/0.51（ARW），不是 0.55；加载帧 0.007 ≈ 0.011。建议把最终脚本入 `_harness/` 并写清区域与取样样张。
10. 帧目录版本错位：`cold-*-ready` / `hot-*-ready`（04:42–43）是首轮作废帧（多为转圈），`c2-*`（05:05–07）才是重测帧，报告未标注；`probe-{first,onset,ready}.png`（05:05:13–14）与 86 s 日志（`hot-raf-probe2.log` 05:13:32）不同轮、不同状态（帧整窗 mean 31.6/bf 0.007 是「上一张 ARW + 正在显影」；日志 mean 69.9/bf 0.242 是有图态），帧只能证明「加载态转圈」，不证明探针目标是 RAF。建议在 §1 标帧批次与对应关系。
11. §2「`value.exposure` 依次 +0.61/−0.61 交替」：CSV rep0 起始 **+0.49**、rep2 终点 **+0.55**（其余 ±0.61）；建议写「≈±0.6，两次拖拽落在 0.49/0.55」。
12. M3 首轮「已保存 100 张」、导入 1.38 s、1100 的 8.83 s 无日志（`logs/` 只有 `m3-100.json` n=31 与 `m3-100b.json` n=100）；`batch/n1000`、`batch/n10000` 已在 05:19 清理（`n100` 仍在，100 个 C0xxx.CR3）。建议把这三项标为「人工秒表/无机器日志」，或补日志。

## 通过项（逐项）

**M1 冷（CSV 重算 vs §0）**

| 样张 | CSV 中位（min/max） | 报告 | 结论 |
|---|---|---|---|
| NEF | 6.752（6.687/6.845） | 6.75（6.69/6.85） | ✓ |
| ARW | 7.552（7.486/7.611） | 7.55（7.49/7.61） | ✓ |
| RAF | 8.214（8.138/8.466） | 8.21（8.14/8.47） | ✓ |
| 窗口出现中位 | 2.346 / 2.342 / 2.306 | 2.35 / 2.34 / 2.31 | ✓ |

**M1 热**：NEF n=6 → 中位 4.027（3.923/4.140），报告 4.03（3.92/4.14）✓；RAF 6 行全 `timeout25`（rep 1/3/5/7/9/11）✓；probe 行 `>=86` + `logs/hot-raf-probe2.log` 86 s 逐行 dp=0.00 ✓（"逐字节"措辞见 minor 5）。

**M2**：n=10，ready 中位 1.119（1.107/1.137）✓；onset 中位 0.620，报告 §0 0.62 ✓；ready−onset ≈0.499 ≈「约 0.5 s」✓（onset 下限见 E1）。

**M3**：`rawlab-m3.csv` = 100 档 1.38/2.82/2.65、1100 档 8.83/>120 ✓ 与报告一致；`home/…/Edits/edits.json` 实测 **103 条**（100 目标 + 源图 + 早前 2 条），与 §3 的 103 一致 ✓。

**帧抽检（3 次运行 + 2 个对照）**

- `c2-Nikon-0-ready.png` / `c2-7RM5--2-ready.png` / `c2-Fujif-3-ready.png`：均为完整图像 + 状态栏 `预览 1536 × 1024 / 1536 × 1152 · sRGB`，非转圈 ✓。同一样张 5 帧 md5 相同（5d2a6bdd…），说明渲染确定性，不构成矛盾。
- `probe-ready.png`：转圈 + `7RM5-LosslessCompressedLarge.ARW` + `已恢复上次调整 · 正在显影…`，正是「首版判据误判」的加载态 ✓。
- **相关度复算**（照片矩形内缩 5%，240×180，灰度 Pearson）：ARW **0.928**、RAF **0.948**、NEF **0.844**，对报告 0.924/0.922/0.856 的差为 0.004/0.026/0.012，全部在 ±0.05 内 ✓（不内缩的紧框为 0.998/0.988/0.970）。参考图来源核验：与 ImageIO 内嵌预览（1024 px）相关 0.999/0.938/0.996，确为内嵌预览而非 App 自身渲染 ✓（RAF 的 3:2 失真见 minor 8）。
- 注意：按报告字面「画布内亮区自动取包围盒」直接复算，暗场景 RAF 的 >85 亮区只有天空带（bbox 高度 ≈27% 画面），r≈0.40，无法得到 0.922；必须取照片矩形才复现。属方法描述精度问题（minor 9），数字本身自洽。

**源码核对（只读）**

- `probeRAW` 只读头：`Shared/Native/HDRSource.swift:67-86` → `lutools/src/ffi/sony2fuji_hdr.cpp:500-511` → `hdr::probeCameraRaw`（`hdr_pipeline.cpp:447-457`）→ `RAWProcessor::inspectCameraHDR`（`raw_processor.cpp:222-249`）→ `loadFile(..., inspectOnly=true)`（185-198：`metadataOnly` 时不 unpack）。「解码器占比小」有源码依据 ✓（报告只缺这条引用）。
- 预检后台串行：`Shared/RawLabKit/MacAdjustmentTransferSession.swift:5-38` 单串行 `DispatchQueue(label:"rawlab.adjustment-preflight")` ✓；apply 在 Button action 内同步：`RawLabMac/Sources/Editor/View/AdjustmentTransferView.swift:156-161` ✓。
- 缩略图不刷新：`BatchExportView.swift:312-324`（`.task(id:url)` 只按 URL 取 `PhotoThumbnails.shared`）、`EditorModel+AdjustmentTransfer.swift:244`（apply 不失效）、`FileLibrary.swift:613-615`（`PhotoThumbnails.image(for:)` 用 `uneditedFileAt` 缓存键）✓。M3b「不存在刷新」成立；M3c「未测」有理由（apply 在主线程同步，无后台刷新阶段）✓。
- 批量入口：`RawLabMacApp.swift:155-170`（`handleSystemOpen`，多文件→批量选择窗）✓；`MacBatchExport.swift:144-155`（`device:inode` resourceKey，硬链接去重）✓。

**纪律**

- §1 line 69 + §8 line 137 如实写「首版判据只看帧差、把转圈误判、3.2 s 作废、全部重测」；首轮日志（`m1cold.json` 3.19–3.43、`m1hot.json` NEF ~1.0）与之一致 ✓。
- NEF r=0.856 <0.9 在 §1 与 §8 两处如实标注 ✓。
- 判定句区分了「冷打开=解码/显影（解码器可压缩）」与「热切换/编辑/批量=架构/代码」，且均带数字 ✓（RAF 的绝对化见 E4）。
- 归因算术自洽：2.65/100=26.5、2.82/100=28.2、120/1100=109.1、1.119/0.68=1.65、8.21−6.75=1.46 ✓。

## 未覆盖

- 未复跑被测 App（任务约束）；未核 §1 的二进制 SHA/Gatekeeper（与计时无关）。
- `batch/n1000`、`batch/n10000` 在复核期间被外部清理（05:19），1100/10000 档只能依据 CSV/正文。
- 报告 §7 的删除清单尚未执行（`$G/rawlab/` 全树、偏好域仍在），与「收尾后补」的写法一致，不算缺陷；若按 §7 收尾，请先保留 `frames/` 与 `logs/` 供本自审复核。
