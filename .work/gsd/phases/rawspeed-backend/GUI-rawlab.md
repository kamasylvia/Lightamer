# GUI 计时 · RawLab 官方 0.12.0 (macOS arm64)

> 对象：RawLab 官方发行版 0.12.0（SwiftUI + 共享 C++17 核 / LibRaw 解码）。测量日期 2026-11-25，机器 Apple M4 / 16 GB / macOS 27.3，HEAD `2372a1f853014b6bf733e6c8d7080886ee4f7144`。

## §0 结论头

**M1 冷打开（`open` 调用 → 视口稳定完整；n=5，中位（min / max））**

| 样张 | 冷打开 | 其中：窗口出现 | 其中：窗口→图稳定 |
|---|---|---|---|
| 7RM5 ARW 85 MB | **7.55 s**（7.49 / 7.61） | 2.34 s | 5.21 s |
| GFX100S RAF 210 MB | **8.21 s**（8.14 / 8.47） | 2.31 s | 5.90 s |
| Z8 NEF 61 MB | **6.75 s**（6.69 / 6.85） | 2.35 s | 4.40 s |

**M1 热切换（已开 → 换另一张；n=12，两种样张轮转）**

| 目标 | 热切换 → 视口稳定 | 备注 |
|---|---|---|
| Z8 NEF 61 MB | **4.03 s**（3.92 / 4.14，n=6） | 稳定可测 |
| GFX100S RAF 210 MB | **≥ 86 s（负载态；重测轮 6/6 >25 s，探针 86 s 帧差 0.00）** | 首轮低负载另观测 1 次 7.27 s；负载态进程 96% CPU、RSS 4.0→1.4 GB、swap 6.98/8 GB（点位采样，`logs/resource-sample.txt`） |

**M2 编辑（曝光 ±0.6 EV 交替，n=10）**

| 指标 | 值 |
|---|---|
| 改动 → 视口稳定 | **1.119 s**（1.107 / 1.137） |
| 其中：画布首次变化（onset） | 0.62 s |

**M3 批量粘贴（源图 +0.5 EV → 批量集合）**

| 规模 | 导入（前置） | 选中 | 准备（查看目标→可应用） | 应用→结果文本 (M3a) | 结果 |
|---|---|---|---|---|---|
| 100 | 1.38 s | 默认全选 100 | **2.82 s**（复测轮；stdout 转录见 `logs/m3-100-stdout.txt`） | **2.65 s**（复测轮；`m3-100b.json` 的 prepare=2.65 系计时起点误置） | 真改首轮：UI 报「已保存 100 张」（计时未打点）；复测同值：报「未变化 100 张」 |
| 1100 | **8.83 s** | 全选 1100 | **> 120 s（超时，apply 从未变可用）** | — | 未完成 |
| 10000 | 未测 | — | — | — | 见 §8：硬链接被 inode 去重；10000 个 APFS clone 未在时窗内执行 |

- **M3b（缩略图刷新）**：**不存在刷新**。批量行缩略图由 `BatchThumbnail` 实现，`.task(id: url)` 只按 URL 加载一次 `PhotoThumbnails.shared` 缓存，粘贴链路（`applyAdjustmentPaste`）不触碰该缓存，也不发失效通知（源码 `RawLabMac/Sources/Export/BatchExportView.swift:312-324`、`EditorModel+AdjustmentTransfer.swift:244`）。用户在批量列表里看不到哪些照片被改。
- **M3c（刷新期间可交互）**：**未测**（apply 期间主线程同步写 100 张状态，没有独立的「后台刷新」阶段可对照）。

**判定句**：

- **冷打开 6.75–8.21 s：解码/显影原因，不是懒渲染缺陷。** 2.3 s 是进程+窗口，之后 4.4–5.9 s 全部花在「打开 RAW → 预览 1536 px 显影」这一段（状态栏自报 `预览 1536 × 1024 · sRGB`，期间画布只有转圈）。100 MP RAF 只比 61 MB NEF 慢 1.46 s，说明瓶颈在固定管线而非纯字节量；换 rawspeed 可压缩这一段，但 6.7 s 里仍有 2.3 s 是应用启动，收益上限约 3–4 s。
- **热切换是这个 App 的硬伤，且属架构/代码原因：100 MP RAF 在负载态 ≥86 s 整窗冻结。** 同一进程先开后 NEF 只用 4.03 s；重测轮切到 210 MB RAF 时窗口 86 s 帧差 0.00（`logs/hot-raf-probe2.log`），同期点位采样 96% CPU、RSS 4.0 GB→1.4 GB、swap 6.98/8 GB（`logs/resource-sample.txt`）。**首轮低负载另观测到 1 次 7.27 s 完成**（`m1hot.json` rep1，`frames/hot-1-ready.png` 为完整 RAF 图），故 86 s 是负载态上界而非稳定值。这是主线程阻塞 + 内存膨胀（上一张的缓存/编辑态未释放，重开又整段 develop），**换解码器只能缩短其中解码部分，救不了「窗口冻结」这一形态**。
- **编辑 1.119 s：架构原因。** 输入平面已驻留，每次滑杆提交仍整条 develop 重跑（onset 0.62 s 后还要 0.5 s 才稳定），没有 ROI/分块/增量；darktable 同口径 0.68 s，本机基准的 1.65×。
- **批量粘贴：架构原因占主导，解码器原因占比很小。** 100 张复测的 apply 2.65 s、准备 2.82 s；1100 张准备 >120 s——每目标一次 `probeRAW`（读 RAW 头/元数据）+ 校验，**不是全图解码**，但 O(N) 且无并发/无进度；apply 在主线程同步写状态。缩略图不刷新使「批量粘贴」在 RawLab 里没有可见回执。

## §1 方法

**二进制来源**

| 项 | 值 |
|---|---|
| Release | `v0.12.0`（2026-11-23 的 `v0.12.1` 只有 Android/iOS/Windows 资产，无 macOS 包；故取最新 macOS 发行版 0.12.0） |
| 资产 | `RawLab-Mac-0.12.0-arm64.zip`，723,061,601 B |
| SHA256 | `6f2cca0bdd40aa0094459116aaed80d476454bcdbd16ea6515dc336779c9d48b`（与官方 `SHA256SUMS.txt` 一致） |
| 版本 / bundle | `0.12.0` / `com.rawtools.rawlab.mac` |
| codesign | adhoc（`flags=0x0`，`TeamIdentifier=not set`，`origin=RawLab Release Signing`） |
| spctl | `rejected`（未公证，预期） |
| Gatekeeper | **已执行** `xattr -dr com.apple.quarantine`（用户授权，仅本包；残留 `com.apple.provenance` 不影响启动） |
| 安装位置 | `$G/rawlab/apps/RawLab Mac.app`，未进 `/Applications`，未改 brew |
| 启动方式 | `open --env HOME=$G/rawlab/home --env CFFIXED_USER_HOME=$G/rawlab/home -a "RawLab Mac.app" <file>`；直接执行二进制 45 s 零窗口（启动自检已确认） |

`G=/Users/Shared/lightamer-gui-test/`。样张 = `~/Library/Application Support/Lightamer/TestRAW/` 的硬链接（零拷贝）。源码对照 = 官方 `RawLab-0.12.0-source.tar.gz`（48,728,963 B，解到 `$G/rawlab/src/`，只读引用）。

**偏好保护**：启动前快照真实 `~/Library` 六个目录条目（48,769 行）写入 `$G/rawlab/snap-before.txt`；`defaults domains` 在运行前**无** `com.rawtools.rawlab.mac`。运行期该域被 App 新建（`~/Library/Preferences/com.rawtools.rawlab.mac.plist`），并按「运行前不存在 → 测后删除」处理，详见 §7。

**权限**：`AXIsProcessTrusted() = True`；`screencapture -l <窗口ID>` 与 `CGWindowListCreateImage` 均正常；合成鼠标（点击/拖拽）与合成键盘（⌘⇧G、⌘⇧C 等）均被投递（滑杆拖拽与快捷键面板均实测生效）。

**就绪判据（含一次修订，如实记录）**：10 Hz 截窗口 → 灰度降采样 320 px → 只统计画布区（窗口内 x 22–82%、y 14–94%），以 `(灰度>85) 像素占比 > 0.05` 判「有图」，再加连续 3 帧帧差 <0.5 判「稳定」。**首版判据只看帧差，把「转圈 + 文件名」的加载态误判成已就绪**（黑底 mean≈31、白字/转圈使 std≈13），导致冷启动被低估到 3.2 s；发现后全部冷/热/编辑数据按新判据重测，本文所有数字来自重测轮（唯一例外 = 首轮低负载 7.27 s RAF 热切换，端点帧已核为完整 RAF 图）。加载态与就绪态对照：加载态 bright_frac≈0.011、就绪态 0.55。

**自证（相关度）**：将就绪帧按画布内亮区自动取包围盒（同一算法用于三样张），与文件内嵌 JPEG 预览（ImageIO thumbnail，1024 px）双线性缩放到 240×180 后算 Pearson：**7RM5 ARW r=0.924、GFX100S RAF r=0.922、Z8 NEF r=0.856**（NEF 略低是预览调色/裁切差异；ARW/RAF 过 0.9 门槛，NEF 记录在案）。

**导入与粘贴驱动**：RawLab 无脚本接口（其 `tools/mcp` 的 `sony2fuji` CLI 不在桌面应用包内），全部经 GUI/AX：
- 冷/热：`open` 传文件；热切换 = 对已运行实例再 `open` 另一文件。
- 编辑：`slider.exposure` 的 AX 坐标 + 合成拖拽（±15 px ≈ ±0.6 EV），AX 读回 `value.exposure` 核对每次生效。
- 批量：`open -a <app> <N 个文件>` 触发 `handleSystemOpen`（`RawLabMacApp.swift:155-170`）→ 全部加入批量集合并开「批量编辑」窗；「全选」→「应用调整并保存到所选照片…」→「查看目标」→「应用」。
- 数量核对：批量窗自报「已选 N 张」；100 → 100；1100 → 1100（100 残留 + 1000 新入）。

## §2 打开 / 编辑等待数字

冷启动阶段拆分（n=5 中位）：`open` 返回 <0.05 s；进程 + 窗口出现 2.31–2.35 s；窗口出现到图稳定 4.40 s（NEF）/ 5.21 s（ARW）/ 5.90 s（RAF）。恢复上次编辑的样张会在状态栏显示「已恢复上次调整 · 正在显影…」，该项计入冷启动（真实用户路径）。

热切换：NEF 6/6 成功，ready 3.92–4.14 s（onset≈3.6 s）；RAF 6/6 在 25 s 门槛超时。追加单次探针：切 RAF 后 86 s 内窗口帧差 0.00（mean=69.9、bright=0.242），同期点位采样 96% CPU、RSS 4.0 GB、swap 6.98 GB/8 GB（`logs/resource-sample.txt`）；**但首轮低负载有 1 次 7.27 s 完成**（见 §8）；期间 AX 层仍可读（窗口未崩），但画面与状态栏全部冻结。

M2：10/10 生效，`value.exposure` 依次 +0.61/−0.61 交替；onset 0.613–0.643 s，ready 1.107–1.137 s；首帧变化到稳定还有约 0.5 s。

## §3 批量粘贴数字

- **100 张（真改首轮）**：`open` 100 文件 → 批量窗 1.38 s；默认全选 100；点「应用」后 UI 报「已保存 100 张 · 未变化 0 · 跳过 0 · 未完成 0」。该轮未打印 prepare/apply 计时，只确认了结果文本。
- **100 张（复测同值，唯一带计时的 n=100 轮）**：prepare 2.82 s、应用→「未变化 100 张」2.65 s（逐 0.1 s 轮询结果文本）。终端转录见 `$G/rawlab/logs/m3-100-stdout.txt`；`m3-100b.json` 的 `prepare=2.65` 是该轮脚本把计时起点误设在 apply 按下之后，非真实预检时长。
- **1100 张**：导入 8.83 s；「查看目标」后 prepare 跑满 120 s 仍未使 apply 可用（当时采样 App 70–96% CPU，`logs/resource-sample.txt`），按超时终止。每目标一次 `probeRAW`（`EditorModel+AdjustmentTransfer.swift:171-190`），线性无并发。
- **持久化证据**：粘贴完成后 `$HOME/Library/Application Support/RawLab/Edits/edits.json` 出现 103 条 records（100 目标 + 源图 + 早前 2 条），即写入的是编辑状态 JSON，不是像素。

## §4 归因拆解

| 段 | 数字 | 依据 |
|---|---|---|
| 粘贴本身（100 张，复测未变化路径） | 2.65 s（26.5 ms/张） | 点「应用」→ 结果文本；期间无全图解码，写 edits.json |
| 粘贴预检（100 张，复测） | 2.82 s（≈28 ms/张；stdout 转录 `logs/m3-100-stdout.txt`，`m3-100b.json` 的 2.65 系计时起点误置） | 「查看目标」→ apply 可用；逐目标 `probeRAW` + 兼容性校验 |
| 粘贴预检（1100 张） | >120 s（>109 ms/张，每张成本 ≥3.9×） | 同上，规模放大后总时长超线性（RAW 头读取 + 校验 + 主线程回写） |
| 单张缩略图 | 未单独计时 | `BatchThumbnail` 走 `PhotoThumbnails.shared` 缓存（内嵌预览量级）；粘贴不触发刷新 |
| 主线程阻塞 | apply 在 `Button` action 内同步执行 | `applyAdjustmentPaste` 逐目标写状态（`AdjustmentTransferSession.apply`），期间无进度/无取消 |
| 排队 | 无队列、无并发 | 预检在后台队列但串行；apply 在主线程 |

判定：**批量等待 = 架构/代码原因**（O(N) 逐张 RAW 探测 + 主线程同步写 + 无缩略图失效）；**解码器原因占比小**——探测只读 RAW 头/元数据，不做全图解码。真正与解码器相关的是 M1/M2 的整段 develop。

## §5 与 `SPIKE.md` §4 / darktable 对账

| 项 | RawLab 0.12.0 | 参照 | 差 | 解释 |
|---|---|---|---|---|
| 冷打开（窗口→图） | 4.40–5.90 s | darktable 1.7–2.1 s（主窗→首图） | **×2.6–3.5** | RawLab 每次 `open` 都整段 LibRaw 解码 + 1536 px 显影；darktable 先内嵌 JPEG 再按需 mipmap |
| 冷打开（含启动） | 6.75–8.21 s | darktable 6.2–6.5 s | +8%…+31% | 应用启动 2.3 s 比 darktable 4.5 s 快，但图后段慢 |
| 编辑 | 1.119 s | darktable 0.68 s | ×1.65 | 每次提交重跑整条 develop；darktable 只重跑受影响 iop |
| 热切换 NEF | 4.03 s | Alcedo 热切换远差于冷启动 | 同形态 | 重解码 + 重显影，无预览缓存复用 |
| 热切换 RAF 210 MB | 负载态 ≥86 s 冻结；低负载 1 次 7.27 s | — | — | 主线程阻塞 + 内存膨胀（swap 6.98 GB） |
| 批量粘贴 | 26–30 ms/张（100 张） | darktable ≈20 ms/张（50 张/s） | ×1.3–1.5 | 每张多一次 RAW 探测；darktable 只写 history |
| 缩略图刷新 | 不刷新 | darktable ≈80 ms/张、按需 | — | 无失效通知 |

与 `SPIKE.md` §4 的 CLI 数字不是同一实现，只作量级参照：P0 CIRAW 冷 968 ms（解码+渲染+读回）远快于 RawLab 的 4.4–5.9 s 图后段，说明 rawspeed/CIRAW 路线在**解码段**有 4–6× 空间；但 RawLab 的 2.3 s 启动与负载态 86 s 热切换冻结不是解码器能解释的部分。

## §6 这个 App 做对了什么（懒在哪一层）

- **启动快**：2.3 s 出窗口（darktable 4.5 s），无首启向导。
- **打开即编辑器**：`open` 传文件直达编辑视图，无导入/项目前置。
- **预览分辨率固定 1536 px**：显影在预览尺寸完成，100 MP RAF 只比 61 MB NEF 多 1.46 s，说明没有按全分辨率解码。
- **编辑状态与像素分离**：粘贴只写 `edits.json`，不触发解码（100 张 apply 2.65 s 的语义证据）。
- **没做对的**：热切换不释放上一张的缓存/编辑态（RSS 4 GB → swap 打满）；批量预检逐张 `probeRAW` 且无并发；apply 主线程同步；缩略图不失效。

## §7 删除清单

- `$G/rawlab/` 全树 **5.2 GB** 已删：`apps/` 962 MB（RawLab 0.12.0）、`dl/` 737 MB（zip + 源码包）、`batch/` 2.9 GB（100 个 APFS clone）、`frames/` 154 MB、`src/` 88 MB、`samples/` 341 MB（硬链接，不占额外空间）、`home/` 1.1 MB、`logs/`。
- 偏好：真实 `~/Library/Preferences/com.rawtools.rawlab.mac.plist` 与域名 `com.rawtools.rawlab.mac` 在运行前**不存在**（`snap-before.txt` 无 rawlab 行、`defaults domains` 无该域）；测后 `defaults delete` + 删 plist，复查域名 0 命中、`~/Library/Preferences` 无 rawlab/rawtools 文件。
- 运行前已存在的其它条目一律未动（快照 48,769 行对照，无 rawlab 归属项）。
- 进程：`pgrep -f "RawLab Mac.app"` 清零；隔离 HOME 随 `$G/rawlab` 一并删除。
- `df -h /`：删前 **36 GB 可用（85%）** → 删后 **38 GB 可用（84%）**（APFS clone 共享块，实际回收小于 du 逻辑值）。
- 保留（非本 lane 私有）：`$G/_harness/`（共享脚手架）、`$G/_frames`、`$G/_launchcheck`（前序 lane 产物）。

## §8 风险与未验项

- **热切换 RAF 的 ≥86 s 是负载态上界**（首轮低负载 7.27 s 完成，两轮差异见 `logs/resource-sample.txt`）：采样时 swap 已用 6.98 GB/8 GB；何时累积未测，不能把全部 86 s 归给 App；但「负载态窗口冻结 86 s、帧差 0.00」是确定的用户可见形态，且 NEF 同进程 4.03 s 可作对照。
- **M3 10000 未测**：产品按 `device:inode` 去重（`Shared/RawLabKit/MacBatchExport.swift:149-155`），硬链接样张会坍缩成 1 张；改用 APFS clone 后 100/1100 可用，10000 个 clone 未在时窗内创建。
- **M3c 未测**：粘贴没有后台刷新阶段，无法构造「刷新期间开图」对照。
- **NEF 相关度 0.856** 低于 0.9 门槛，原因是内嵌预览与 App 显影的调色/裁切差异；ARW/RAF 过门。
- **编辑测量用滑杆拖拽**（合成事件），不是真实手指轨迹；AX 读回确认每次值变化。
- **首版就绪判据错误已修正**：所有数字来自修正后重测（唯一例外 = 首轮低负载 7.27 s RAF 热切换，端点帧人工核验）；修正前的 3.2 s 冷启动值作废，未混入本文。首轮其余 RAF ready≈1 s 均为旧判据把转圈误判（`hot-0/hot-2` 帧 bf≈0.010），不计入。

## §9 issue #26 评论草稿

> RawLab 0.12.0（macOS arm64）真机计时：冷打开 6.75 s（NEF 61 MB）/ 7.55 s（ARW 85 MB）/ 8.21 s（RAF 210 MB），其中应用启动 2.3 s、图后段 4.4–5.9 s；编辑 1.119 s；热切换 NEF 4.03 s，但 **100 MP RAF 负载态热切换 ≥86 s 整窗冻结**（点位采样 96% CPU、RSS 4.0→1.4 GB、swap 6.98/8 GB；低负载首轮曾 7.27 s 完成）。批量粘贴 100 张复测：预检 2.82 s + 应用 2.65 s（stdout 转录 `logs/m3-100-stdout.txt`；26.5 ms/张，只写 edits.json；真改首轮仅确认「已保存 100 张」，计时未打点），1100 张预检 >120 s 超时；缩略图不刷新。判定：冷打开是解码/显影成本（换 rawspeed 有 3–4 s 空间，上限受 2.3 s 启动限制）；热切换冻结、编辑 1.12 s、批量 O(N) 预检与主线程同步均属架构/代码原因。证据 = `.work/gsd/phases/rawspeed-backend/GUI-rawlab.md` + `evidence/gui/rawlab-*.csv`。
