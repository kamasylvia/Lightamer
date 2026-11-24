# GUI timing — Alcedo Studio 0.3.6 (official, UX reference)

Issue #26 · lane: Alcedo Studio · machine Mac16,10 / Apple M4 / 16 GB / macOS 27.3 · HEAD at start `4349dee034e16f2f3ae9e1f187919feb57738080`
Workspace `/Users/Shared/lightamer-gui-test/alcedo/` (repo-external, deleted after the run) · isolated `HOME` · only this report + CSV/scripts in the repo.

## §0 结论头

### M1 打开等待（n=5/样张，单位 s，median [min / max]；launch = 新进程起）

| 样张 | 窗口出现 | 项目打开 | `editor.open` 返回 | 视口稳定（**M1 冷**） |
|---|---|---|---|---|
| Sony 7RM5（85 MB ARW，85 MP） | 0.82 | 0.08 | 1.31 | **3.846** [3.826 / 4.400] |
| Fujifilm GFX100S（210 MB RAF，102 MP） | 0.80 | 0.08 | 1.62 | **3.996** [3.961 / 4.117] |
| Nikon Z8（61 MB NEF，45 MP） | 0.89 | 0.08 | 1.04 | **3.616** [3.545 / 3.677] |

- 冷口径 = 进程启动 → 项目 → 首图上屏且连续 3 帧稳定（含 0.8 s 启动、0.08 s 项目、1.0–1.7 s `editor.open`、约 1.5–1.6 s 的首帧渲染/质量档稳定）。图像**首次可见**在 2.97–3.36 s（中位；判据 = 视口 std≥40 且非黑）：7RM5/GFX/Z8 分别 3.16/3.36/2.97 s；稳定值比首见晚 0.6–0.7 s（3 帧判据地板）。
- 隔离 `HOME` 生效（单次目检）：启动器只显示本 lane 的项目，未出现用户真实最近项目；启动器不截图。

### M1 热（编辑器内切换；n=10，按 2→3→1 循环；单位 s）

| 样张 | n | median | min | max | 序列 |
|---|---|---|---|---|---|
| 7RM5 | 3 | **3.775** | 3.686 | 4.645 | 3.69 / 4.64 / 3.78 |
| GFX100S | 4 | **57.914** | 12.044 | 65.626 | 12.04 / 61.53 / 54.29 / 65.63 |
| Z8 | 3 | **34.079** | 23.429 | 40.776 | 23.43 / 40.78 / 34.08 |

- 热切全程视口**黑屏**：图像在 `editor.open` 返回前后才出现。GFX 第 2 次（rep4）：图片 60.88 s、稳定 61.53 s；第 4 次（rep10）：黑屏 1.20→64.92 s、图片 64.92 s、稳定 65.63 s。7RM5 不受影响（3.7–4.6 s），102 MP/45 MP 逐次恶化（GFX 12→61→54→66 s）。
- 同一 GFX 文件**冷开 4.0 s**，热切 66 s（按全程 ≥16×；按 open 相位 ≈21×）——瓶颈不是文件解码本身，是「关闭上一张 + 重新全量解码 + 多档渲染 + 缓存/内存压力」的组合。

### M2 编辑等待（曝光，每次 +0.5 EV 新值，n=10）

| 指标 | median | min | max |
|---|---|---|---|
| `editor.set` 返回（提交 + 渲染帧） | **0.163 s** | 0.114 | 0.204 |
| 视口稳定（含 3 帧判据地板 ≈1.0 s） | **1.548 s** | 1.395 | 1.956 |
| 首个可见变化（帧差） | 0.929 s | 0.829 | 1.256 |

- 命令返回 0.12–0.20 s；画面首变 0.83–1.26 s；连续 3 帧稳定 1.40–1.96 s。截帧在编辑期为 2.9–3.2 Hz（Δt 0.315–0.349 s），判据本身贡献约 0.9–1.0 s；**用户感知的「松手后出新图」≈0.2–1.0 s**。

### 100% 放大等待（加量项，双击视口切换；n=5）

| 事件 | median | min | max |
|---|---|---|---|
| 双击 → 放大开始（onset） | 1.0 s | 0.97 | 1.10 |
| 双击 → 最后一个细节变化 | **1.40 s** | 1.38 | 1.53 |
| 双击 → 8 帧稳定（判据地板 ≈2.4 s） | 3.42 s | 3.36 | 3.55 |

- 右上角读数在放大后显示 **95%**（1:1 档；Qt 的 trueZoom 口径，非 100% 字样），图像细节在 1.4 s 内完成；这是 Alcedo 的 `DETAIL_ROI_PREVIEW`（全解码 ROI）在起作用。

### M3 批量粘贴（源图 +0.5 EV，复制 24 个 adjustment item，粘贴到 N-1 张）

| 档 | 导入（前置，不计 M3） | M3a 粘贴命令返回 | M3a 完成（后台任务） | 吞吐 | M3b 强制刷新缩略图（实测/外推） | M3c 刷新期打开一张 |
|---|---|---|---|---|---|---|
| 100 | 100 张，0.137 s | **0.215 s** | **1.516 s**（99 张） | 65 张/s | 99 张 **38.1 s**（2.6/s） | **16.9 s** 稳定 / **14.7 s** 命令（空载 5.10 s 命令 → 2.9×） |
| 1,000 | 1,000 张，0.93 s | **0.095 s** | **12.703 s**（999 张） | 79 张/s | 40 张 17.2 s → 外推 **≈7.2 min** | **34.1 s** 稳定 / **33.1 s** 命令（空载 5.43 s → 6.1×） |
| 10,000 | 10,000 张，8.99 s | **0.228 s** | **118.895 s**（9,999 张） | 84 张/s | 40 张 18.5 s → 外推 **≈76.9 min** | **24.8 s** 稳定 / **23.7 s** 命令（空载 4.84 s → 4.9×） |

- M3a 的「返回」只花 0.1–0.23 s；真正的版本写入在后台任务里，84 张/s。99/999/9,999 全部 `applied_count` 无失败。
- M3b 的 100 档是**全量实测**（99 个 PNG）；1k/10k 为 40 张采样外推（库函数 `library.thumbnails` 4 路在飞，约 2.2–2.6 张/s 墙钟）。正常 GUI 不会全量刷新：粘贴只让**可见/固定**的缩略图失效并重渲（`RefreshCurrentThumbnail` 只处理 pinned tier），其余滚动到才付费。
- M3c 的目标是每档最后一张（均为 210 MB GFX RAF）。同口径（`editor.open` 命令往返）：刷新期 14.74/33.15/23.68 s vs 空载 5.10/5.43/4.84 s = **2.9× / 6.1× / 4.9×**；stable 值 16.90/34.13/24.76 s 只作参考（截帧地板）。

### 判定句（带数字）

**批量粘贴合格（懒在版本/DB 层）**：命令返回 0.23 s、后台 84 张/s、9,999 张 118.9 s；粘贴只写 version/history + 仅刷新可见缩略图，不逐张解码（代码路径 + 实测）。
**单图打开/切换不合格（不懒在预览层）**：每次 `editor.open` 都 `DecodeRes::FULL` 解码再渲 2560 快速预览 / 4096 质量档（`pipeline_scheduler.cpp:151/163`；Quality Base 4096 见 `pipeline_apply_request.hpp:50`；源码行号 = v0.3.3 clone，行为在 0.3.6 实测），视口在渲染期间保持全黑；冷开 3.6–4.0 s 可用，但重复热切 102 MP 从 12 s 恶化到 54–66 s（同文件冷开 4.0 s，按全程 **≥16×**，按 open 相位 **≈21×**（65.6 / (3.996−0.80−0.08) = 21.1）。这是**架构/调度原因**（无上一张复用、无低分辨率先上屏、重复全量解码、缓存/内存压力下反复重渲），不是单纯解码器成本；解码器只解释了冷开的约 1–2 s 下限。
按用户口径：Alcedo 不走 CIRAW，CIRAW 排除条件不适用；但它的「项目内热切」在 100 MP 上需要分钟级挂起，**作为 UX 对标不能照抄这一层**。

## §1 方法

### 1.1 二进制来源

| 项 | 值 |
|---|---|
| 项目 | `zidage/AlcedoStudio`（官方） |
| 版本 | 0.3.6（release `v0.3.6`, 2026-11-17） |
| 资产 | `AlcedoStudio-0.3.6-Darwin-arm64.dmg`, 176,082,021 B |
| URL | `https://github.com/zidage/AlcedoStudio/releases/download/v0.3.6/AlcedoStudio-0.3.6-Darwin-arm64.dmg` |
| SHA256 | `549b2b0a72036f0f1b78e555eafde0d686797f88759c20ae664f6d63b31b76b7`（与 launch-check 记录一致；项目未发布校验和，本地复算） |
| codesign | `Identifier=studio.alcedo.Studio`, `Signature=adhoc`, `TeamIdentifier=not set` |
| spctl | `rejected`（`source=no usable signature`，adhoc 预期） |
| Gatekeeper | 下载物无 `com.apple.quarantine`（curl 直下，实测 app/可执行文件仅 `com.apple.provenance`）；**未执行** `xattr -dr` |
| 安装 | `$G/alcedo/apps/AlcedoStudio.app`（不进 `/Applications`，不改 brew） |
| 退出 | `kill -TERM`（AppleScript quit 无响应，launch-check 已确认） |

### 1.2 隔离、项目与样张

- `$G=/Users/Shared/lightamer-gui-test`；`HOME=$G/alcedo/home CFFIXED_USER_HOME=$G/alcedo/home`。Qt 的 `QStandardPaths` 生效：自动化 session 落在 `$G/alcedo/home/Library/Application Support/Alcedo/Alcedo/automation/sessions/gui.json`，启动器只显示本 lane 的项目。
- 项目：`$G/alcedo/project/gui-test.alcd`（Alcedo 实际后缀是 `.alcd`，不是任务书写的 `.alced`；打包项目 = 单文件 6.8 MB）。3 张样张导入后 `library.list` = 3/3。
- 启动器内容：本 lane 一次目检（`frames/c1-first.png`，仓外）只显示本 lane 的 `gui-test` 与「没有其他最近项目」；未对用户真实项目截图/读图。该断言是单次目检 + 隔离 HOME 的行为，未做多轮复核（见 §8）。
- 样张：7RM5 / GFX100S 从 `~/Library/Application Support/Lightamer/TestRAW/` 硬链接；Z8 NEF 该目录缺失，从 raw.pixls.us 下载（60,842,580 B）到 `$G/alcedo/dl/` 后硬链接。未碰用户实拍库。
- 批量：`batch/n10000/` 含 9,000 个文件 + `n1000/`（含 900 + `n100/` 100）= 10,000 个唯一文件；`n1000` 合计 1,000；`n100` 合计 100。全部硬链接（`du` 341 MB 为目录元数据，数据块零拷贝）。文件名互异，三样张轮转。
- 批量项目：`batchproj100/`、`batchproj1000/`、`batchproj10000/` 三个独立 `.alcd`，分别导入对应目录；导入计数 = 100/1,000/10,000（未发生内容去重坍缩）。

### 1.3 偏好保护

- 运行前 `$G/alcedo/snap-before.txt`（`~/Library` 七个子目录条目名，48,770 行）+ `domains-before.txt`（47,442 个域名）。
- 运行前 `com.alcedo-app.Alcedo` **不存在**（`defaults domains` 无此域名，launch-check 已删过）。运行后由 cfprefsd 新建（最终 1,022 B）；收尾 `defaults delete com.alcedo-app.Alcedo`，残留空 plist（42 B）删除；未 `killall cfprefsd`。
- `~/Library/Application Support/Alcedo`（用户既有，2026-09-28）**只读**：运行后无新文件（`find -newermt` 为空），未删未改。

### 1.4 计时与就绪判据

- 壁钟 `time.time()`；命令时间 = `alcedo-cli --json call` 往返（同一进程内自动化 host，无网络）。
- 自动化为「脚本接口」驱动（任务书优先项）：`project.create/open`、`library.import`、`editor.open`、`editor.set`、`adjustments.copy/paste`、`tasks.wait`、`library.thumbnails`；状态变更前 `control.acquire {holder_name:"gui-timing"}`。
- 窗口截帧：`screencapture -x -o -l <wid>`，裁到视口区（captured px `215,125,1870,1130`），320×193 灰度。实测 Δt（单轮取值带）：编辑 2.76–3.53 Hz，冷开 4.76–7.38 Hz，热切黑屏 7.75 Hz，zoom 3.91 Hz。**CGWindowListCreateImage 在该机的 Metal 视口返回全黑**，首版因此把「编辑器 chrome 已定、视口黑」误判为就绪；改用 `screencapture -l` 并加 `std≥8` 非黑门槛后修正（`cap_shot.py`）。
- 就绪 = 与基线差异 >1.5/255 后，连续 3 帧相邻差 <0.35/255，且视口 `std≥8`（非黑）；「首次可见」用更高的 `std≥40` 区分真图像与 UI 灰块。100% 放大档用 8 帧（避免把放大动画中间态当稳定）。3 帧地板 ≈1.0 s（编辑期 ~3 Hz）/≈0.4 s（冷开 ~7 Hz），8 帧 ≈2.4 s（zoom ~3.9 Hz）；报告同时给「命令返回」和「末次变化」以剥离地板。
- M1 冷：每次 `kill -TERM` → 新进程 → 等窗口/自动化就绪 → `project.open` → `editor.open(样张)`；`t0` = `Popen` 前。M1 热：同一进程内 `editor.open` 轮换 2→3→1，n=10。
- M2：`editor.set exposure` 每次新值（当前 +0.5，1.5→6.5，实际设置 2.0…6.5），共 10 次；`editor.set` 的契约是「提交 + 渲染帧后返回」。
- 证据链：hot 首轮 `measure1.py` 因 `cap.args` 类型错误作废（`alcedo-m1m2.csv` 保留 hot 10 行 error；另有首轮 zoom 5 行 `'0'` 键码错误），hot 真值由 `measure1b.py` 重跑；zoom 由 `measure_zoom.py`（双击）生成。
- 100%：双击视口中心（QML `TapHandler.onDoubleTapped → handleDoubleTap → zoomToActualPixels`；键盘 `1` 因焦点未进视口无效，已弃用），5 次，每次双击回 FIT 再测。
- 自证：就绪帧视口与文件内嵌 JPEG 的相关性——7RM5 **0.993**（preview2）、GFX100S **0.991**（preview2）、Z8 **0.935**（preview3；preview2 是坏缩略图，0.116，已排除），**15/15 冷就绪帧均 ≥0.9355**（`evidence/gui/alcedo-correlation.txt`）。

### 1.5 数量核对

- `library.list`：3 / 100 / 1,000 / 10,000，逐档 `total` 相等；粘贴结果 `applied_count` = 99/999/9,999，`failure_count`=0。
- 缩略图落盘：100 档 99 个 PNG（目标 99），1k/10k 各 40 个（采样 40）。
- 粘贴后的缩略图亮度高于原内嵌预览（例：138.5 vs 122.1、141.8 vs 110.2、112.3 vs 95.8），与 +0.5 EV 一致（方向性核对，非像素级）。

## §2 打开 / 编辑等待数字

（同 §0。逐 rep 明细：`evidence/gui/alcedo-m1m2.csv`、`alcedo-hot-zoom.csv`、`alcedo-zoom.csv`。）

- 冷开三段（中位）：进程/窗口 **0.80–0.89 s** + 项目 **0.08 s** + `editor.open` **1.04–1.62 s** + 首帧渲染/稳定至 **3.62–4.00 s**。三个样张的冷开差异 <0.4 s，**文件大小不是冷开主因**。
- 热切是另一条曲线：7RM5 稳定在 3.7–4.6 s；GFX 12.0/61.5/54.3/65.6 s；Z8 23.4/40.8/34.1 s。所有热切都有**全黑视口**期（黑屏 0.7–2.2 s 开始，持续到图片出现），没有「旧图保留到新图就绪」或「低分辨率先上屏」。
- M2：命令返回 0.163 s，首变 0.93 s，稳定 1.55 s；没有出现「数十毫秒级」的松手响应。与 Lightamer lane 的参考（快拖 live 0.11 s / commit 0.41 s）相比，首变慢 8.5×、命令返回同量级（0.16 s），但两边的判据/交互路径不同，只作方向性参照。

## §3 批量粘贴数字

- 100：导入 100 张 0.137 s（命令 0.021 + wait 0.116）；源图编辑 0.28 s；copy 0.17 s（24 items）；paste 命令 0.215 s；后台 1.516 s；强制刷新 99 张 38.1 s；刷新期打开一张 14.7 s 命令 / 16.9 s 稳定（空载 5.10 s 命令 = 2.9×）。
- 1,000：导入 0.93 s；paste 命令 0.095 s；后台 12.703 s（79/s）；40 张采样 17.2 s → 全量外推 430 s（7.2 min）；刷新期打开 33.1 s 命令 / 34.1 s 稳定（空载 5.43 s = 6.1×）。
- 10,000：导入 8.99 s（`import` 任务，无缩略图解码）；paste 命令 0.228 s；后台 118.895 s（84/s）；40 张采样 18.5 s → 全量外推 4,615 s（76.9 min）；刷新期打开 23.7 s 命令 / 24.8 s 稳定（空载 4.84 s = 4.9×）。
- 导入本身极快（1 万张 9 s）说明入库不逐张解码；缩略图是后续按需渲染。粘贴任务的 84 张/s 也不是解码吞吐，而是「读 history 快照 + paste 图 + 单事务持久化」的 DB 吞吐（`adjustment_transfer_apply_coordinator.cpp:141-170`）。

## §4 归因拆解

源码引用说明：本地 clone = AlcedoStudio `6024386`（tag v0.3.3，2026-10-15），被测二进制 = 0.3.6（2026-11-17）；下方行号在 v0.3.3 上核对，行为在 0.3.6 上实测。

1. **粘贴操作本身**：不逐张解码/渲染。每目标 = `LoadHistorySnapshot` → `PasteAsRootRelativeVersion` → `PersistHistory`（单事务）；之后 `RefreshOneTarget` 只对 **pinned** 缩略图 `RequestThumbnail`（异步 detached），非可见项不付费（`thumbnail_manager.cpp:451` 只遍历 `thumbnail_pins_`）。实测 100/1k/10k 的粘贴任务 1.52/12.7/118.9 s，吞吐 65→84 张/s，证明不是解码器瓶颈。
2. **缩略图单张成本**：强制 `library.thumbnails`（256 px，4 路在飞）实测 2.2–2.6 张/s 墙钟 → 单张计算约 1.5–1.8 s（4 路并发）。**未拆分**「解码 vs 管线+编码」——本 lane 只有整张吞吐，没有单独解码计时；这是 §8 的未验项。10k 全量 ≈76.9 min。这一档是**解码 + 管线 + 编码**的成本，且对 256 px 也做全量解码（`RenderType::THUMBNAIL` 仍走 `DecodeRes` 路径），属于解码器+架构混合；正常 GUI 的懒刷新把这块藏掉了。
3. **单图打开/切换**：`FAST_PREVIEW` 请求 = `DecodeRes::FULL` + 2560 长边（`pipeline_scheduler.cpp:147-155`），`QUALITY_BASE_PREVIEW` = 4096（`pipeline_apply_request.hpp:50`），`FULL_RES_PREVIEW` = 8192（`:190`）；每次 `editor.open` 都重新解码，且关闭上一张要持久化。冷开 4.0 s 是这条链的下限；热切 12–66 s 是**重复全量解码 + 多档渲染 + 无缓存复用/内存压力**，架构原因为主（同文件冷开 4 s vs 热切 66 s，≥16×；7RM5 不受影响说明不是通用调度卡死，而是大图缓存/内存）。
4. **排队与阻塞**：粘贴后台任务不阻塞 UI（命令 0.2 s 返回；任务期间可继续操作）；但缩略图刷新会抢解码/GPU，与打开竞争——同口径命令往返：刷新期打开 GFX 14.74/33.15/23.68 s vs 空载 5.10/5.43/4.84 s（2.9× / 6.1× / 4.9×）。编辑器打开本身是同步黑屏（用户可见等待），不是后台。

## §5 与 SPIKE.md §4 的 CLI 数字对账

| 项 | SPIKE §4（CLI 位图） | 本 lane（GUI） | 差异解释 |
|---|---|---|---|
| 85 MP ARW 冷开 | P0 CIRAW 968 ms / P1 rawspeed 447 ms（适配屏 2560） | **3.846 s**（launch→稳定） | 口径不同：含 0.80–0.89 s 进程/窗口 + 0.08 s 项目 + 1.31 s `editor.open` + 约 1.6 s 渲染稳定；扣启动后约 3.0 s，仍是 CLI 的 3–7×（Alcedo 有自己的解码器 + 多档渲染，不走 CIRAW）。 |
| 编辑等待 | P0 产品形态 1.69 ms / P1 1.76 ms；harness 上界 738 ms | **0.163 s 返回 / 1.55 s 稳定** | Alcedo 每次提交重渲 2560/4096 档，不是「已解码平面 + 下游平面」的毫秒级复用；比 CLI 产品形态慢 ~90×（数量级差，不是同一路径）。 |
| 大图（GFX 210 MB） | **无 file-matched CLI 数字**（SPIKE 只用 7RM5 85 MB；其 556 ms 是 7RM5 全分辨率，不是 GFX/2560） | **3.996 s 冷 / 57.9 s 热中位** | 不跨文件比。GFX 热切的恶化只能与自己的冷开比：同文件 4.0 → 65.6 s（≥16×）。 |
| 批量粘贴 | 无 CLI 对应项（SPIKE 不测批量） | 84 张/s（版本写入）；强制缩略图 2.2/s | 新口径：粘贴是 DB/version 吞吐，缩略图是解码+渲染吞吐，两者不可混。 |

> 结论：Alcedo 的 GUI 单图数字**不能**与 SPIKE 的位图数字直接比（SPIKE 只有 7RM5；GFX 无 file-matched 值）。它的优势在批量粘贴的懒版本层（84/s），劣势在单图预览的重复全量渲染（冷 4 s、热 12–66 s）。

## §6 这个 App 做对了什么（懒在哪一层）

1. **粘贴懒在版本/DB 层**：`adjustments.paste` 每目标只写一棵新的 history/version（单事务），不触发解码；返回 0.2 s，后台 84 张/s。10k 粘贴 119 s，而不是 10k × 解码。
2. **缩略图懒在可见性**：`RefreshOneTarget` 只刷新 **pinned**（网格/胶片带可见）的 tier；未 pinned 的目标即使粘贴完成也不重渲（`thumbnail_manager.cpp:451-468`）。强制全量刷新是显式 API 才会付的钱（10k ≈76.9 min）。
3. **导入不解码**：1 万张入库 9 s，缩略图后置。
4. **100% 用 ROI**：`DETAIL_ROI_PREVIEW` 只解全分辨率 ROI（`pipeline_scheduler.cpp:170-180`），100% 细节 1.4 s 到位（首次），比整图重渲快。
5. **做错的一层**：编辑器视口没有「旧图保留」或「低分辨率先上屏」，`editor.open` 一到就把视口清黑；FAST_PREVIEW 仍 `DecodeRes::FULL`，每次切换重复解全图；重复切换大图会恶化到分钟级。首屏策略是「全量解码 → 2560 → 4096 → 8192（按需）」，不是 darktable 的「内嵌 JPEG 先上屏 → 后台补真预览」。

## §7 删除清单（已执行）

- 已删 `/Users/Shared/lightamer-gui-test/alcedo/`（2.1 GB）：`apps/AlcedoStudio.app`（483 MB）、`dl/` DMG+NEF（226 MB）、隔离 `home/`（12 MB）、`project/gui-test.alcd`（6.6 MB）、`batchproj100/1000/10000`（8.1/25/195 MB）、`batch/` 10,000 硬链接（341 MB 元数据）、`thumbs*`（21 MB）、`frames/`（194 张 PNG / 314 文件，797 MB）、`logs/`。
- 进程：`pgrep -x AlcedoStudio` = 0（删除前自证）。
- 偏好：`defaults delete com.alcedo-app.Alcedo`（运行前不存在）；残留空 plist（`{}`，42 B）已删；`~/Library` 与 `snap-before.txt` 对比，新条目仅 `Preferences/com.alcedo-app.Alcedo.plist`，处理后 total=0；`~/Library/Application Support/Alcedo`（用户既有）未动。
- 未动：`$G/_harness/`（共享脚手架）、`$G/_launchcheck/`。
- 磁盘：删除前 35 GB 可用 → 删除后 38 GB（`df -h /`）。

## §8 风险与未验项

- **内存压力**：M1 热与 M3c 期间 `memory_pressure` 报可用 22%（低于守卫 G2 的 30%），机器上有用户其它应用；热切 54–66 s 可能被 swap/压缩内存放大。冷开与粘贴数字稳定；热切应按「本机真实负载下的观测」读，不能当纯净实验室数字。
- **热切样本量**：10 次轮换得到 7RM5 n=3 / GFX n=4 / Z8 n=3，不是每样张 n=10；序列显示恶化趋势，中位只作量级。
- **自动化驱动**：M1/M2 用官方自动化接口（等价于 GUI 的打开/松手提交），不是合成鼠标拖滑杆；`editor.open` 的契约是「可编辑时返回」，与「视口稳定」相差约 0.5–2 s，已分别报告。
- **截帧频率分相**（单轮取值带）：编辑 2.76–3.53 Hz（3 帧地板 ≈1.0 s），冷开 4.76–7.38 Hz（≈0.4–0.6 s），热切黑屏 7.75 Hz，zoom 3.91 Hz（8 帧 ≈2.4 s）；M2/100% 的「稳定」被地板放大，已同时给命令返回/末次变化。
- **CGWindowListCreateImage 对 Metal 视口全黑**：这是本 lane 首版误判就绪的原因；后续对象若复用 `cap.py` 需改 `cap_shot.py` 或加非黑门槛。
- **Z8 内嵌 preview2 是坏图**（0.116 相关），自证用 preview3（0.935）；换 preview 索引前先目检。
- **偏好域**：真实写入的是 `com.alcedo-app.Alcedo`（`defaults`），而隔离 HOME 里还有 `com.alcedo.Alcedo`（Qt QSettings）；前者运行前不存在，收尾删除。
- **未验**：Alcedo 的 GPU/CPU 占用未逐 rep 采样（只有任务级 CPU 观察）；没有 Photos/GPU 计数器；没有真机 Trackpad 手势（合成双击等价于 1:1 快捷键）；缩略图的解码 vs 管线+编码未拆分；没有单独的「关图/持久化」耗时。
- **过程偏差（隐私）**：为测截屏速度做过一次 `screencapture -R` 屏幕区域试拍，画面包含用户其它窗口；未读取/记录其内容，临时文件已删。其余所有存证均为 `screencapture -l`，只含本 lane 自己的 Alcedo 窗口。
- **自审**：第一轮 3 error + 7 minor（`alcedo-SELFREVIEW-r1.md`）→ 全部回修；第二轮 1 假 error（证据文件未提交、误用 `git ls-files`）+ 5 minor → 回修；第三轮 **PASS**（`evidence/gui/alcedo-SELFREVIEW.md`）。

## §9 issue #26 评论草稿

> Alcedo Studio 0.3.6（官方 arm64，SHA `549b2b0…`，Mac16,10 / M4 / 16 GB / macOS 27.3）真机 GUI 计时：
> - **M1 冷**（launch → 项目 → 首图稳定，n=5/样张）：7RM5 **3.85 s**、GFX100S **4.00 s**、Z8 **3.62 s**；其中窗口 0.83 s、项目 0.08 s、`editor.open` 1.04–1.62 s，其余为首帧渲染到稳定。
> - **M1 热**（编辑器内切换，n=10 轮换）：7RM5 **3.78 s**（n=3）、GFX **57.9 s**（12.0–65.6，n=4）、Z8 **34.1 s**（23.4–40.8，n=3）。热切全程视口黑屏；GFX 逐次 12→61→54→66 s 恶化；同文件冷开 4.0 s，**≥16×**。
> - **M2 编辑**（曝光，每次新值，n=10）：`editor.set` 返回 **0.163 s**；视口稳定 **1.55 s**（3 帧判据地板约 0.9 s，首变 0.93 s）。
> - **100% 放大**：双击 → 细节到位 **1.4 s**（稳定 3.4 s，8 帧地板）；读数 95%（1:1 档）。
> - **M3 粘贴**：命令返回 **0.10–0.23 s**；后台 99 / 999 / 9,999 张 = **1.52 / 12.70 / 118.9 s**（65→84 张/s）。强制全量刷新缩略图 99 张 38.1 s，1k/10k 按 40 张采样外推 **≈7.2 / ≈76.9 min**；正常 GUI 只刷新可见/固定缩略图。刷新期打开 GFX 命令 **14.7 / 33.1 / 23.7 s**（空载 5.10 / 5.43 / 4.84 s = 2.9× / 6.1× / 4.9×）。
> - **代码**：粘贴 = version/DB 写入（`adjustment_transfer_apply_coordinator.cpp`），缩略图按 pinned tier 懒刷新（`thumbnail_manager.cpp:451`）；`FAST_PREVIEW` 仍 `DecodeRes::FULL` + 2560（`pipeline_scheduler.cpp:151`），Quality Base 4096、Full 8192；切换无旧图保留/低分辨率先上屏。
> - **判定**：批量粘贴懒在版本层（合格）；单图打开/切换不懒在预览层（100 MP 热切分钟级，架构原因，不是单纯解码器）。
> - 限制：热切轮次机内可用内存 22%（低于 30% 守卫线，用户其它应用在场）；热切 n=3/4/3；截帧 2.9–7.8 Hz 分相与判据地板已单列。
