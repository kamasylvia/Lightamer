# GUI timing — darktable 5.6.2 (reference baseline)

Issue #26 · lane: darktable (first object, owns the shared harness). Machine: Mac16,10 / Apple M4 / 16 GB / macOS 27.3 / Xcode 27.0. HEAD at start: `88f6f250b7ce7861f03e02c74dfa8aa84d46a0d8`.

## §0 结论头

**M1 / M2（n=5 冷 / n=10 编辑，单位 s，median [min / p90]）**

| 指标 | A7R5 85 MB | GFX100S 210 MB | Z8 61 MB |
|---|---|---|---|
| M1 冷 · 进程启动 → 视口稳定 | **6.236** [6.138 / 7.149] | **6.508** [5.811 / 7.754] | **6.365** [5.910 / 6.406] |
| 其中：主窗出现 | 4.450 [4.356 / 5.129] | 4.456 [4.446 / 5.238] | 4.659 [4.558 / 4.680] |
| 主窗出现 → 视口稳定 | 1.79 | 2.05 | 1.71 |
| M1 热（暗房内 `→` 切图） | **未测**（见 §8） | 未测 | 未测 |
| M2 编辑（曝光 0↔+0.5 EV，Lua action 实测读回 0/0.5） | **0.680** [0.661 / 0.825]（n=10 合并） | 同左（同进程同图） | — |

**M3 批量粘贴（100 / 1,000 / 10,000）：未测得数字**（导入 + 批处理驱动在时间盒内未收敛，见 §8）。可给的是代码级证据：粘贴本身是**后台 DB 任务**（不逐张解码/渲染），缩略图刷新走 **mipmap 缓存按需 + 空闲 crawler**，不是前台同步。就「懒渲染」这一点，代码路径与用户参照（「一万张几秒」）同构；但没有本机墙钟数字，不作为合格判定。

**判定句（仅就可测部分）**：darktable 的**打开等待 = 应用启动成本主导**（约 4.5 s 窗口出现 + 约 1.7–2.1 s 首图），与 CLI 位图口径（SPIKE §4 P0 894 ms）不可直接比；**编辑等待 0.68 s**，不是「100% ROI 11 ms」那种已解码平面复用型体验，仍在同一数量级内可用。批量粘贴**架构上符合懒渲染**（DB-only job + 按需缩略图），但本轮**没有数字**，不能据此宣布「懒渲染合格」。

## §1 方法

### 1.1 二进制来源

| 项 | 值 |
|---|---|
| 项目 | `darktable-org/darktable`（官方，非 darktamer 分叉） |
| 版本 | 5.6.2（release `release-5.6.2`, 2026-10-04） |
| 资产 | `darktable-5.6.2-arm64.dmg`，88,884,896 B |
| URL | `https://github.com/darktable-org/darktable/releases/download/release-5.6.2/darktable-5.6.2-arm64.dmg` |
| SHA256 | `6ff88e58a2a59cb07b0a1502fea7205e68cd783380a33a3ce7bda68ec29def0c`（与 launch-check 记录一致） |
| codesign | `Identifier=org.darktable`, `Signature=adhoc`, `TeamIdentifier=not set` |
| spctl | `rejected`（`source=no usable signature`，adhoc 预期） |
| Gatekeeper | 下载物无 `com.apple.quarantine` 属性（app 根与可执行文件实测 `No such xattr`）；`xattr -dr` 已执行，对 444 只读库文件报 EPERM 但无可去属性 |
| 安装位置 | `/Users/Shared/lightamer-gui-test/darktable/apps/darktable.app`（不进 `/Applications`，不改 brew） |
| 启动 | `HOME=$G/darktable/home CFFIXED_USER_HOME=... <app>/Contents/MacOS/darktable --configdir $G/darktable/home/dt-config --library <db> --luacmd 'dofile(".../dt_probe.lua")' <file-or-folder>` |

### 1.2 隔离与样张

- `$G=/Users/Shared/lightamer-gui-test`（内置盘，非 TCC 保护目录）；全部产物体在 `$G/darktable/`。
- 隔离 HOME：`$G/darktable/home`（`HOME` + `CFFIXED_USER_HOME`）；darktable 配置目录 `home/dt-config`，库文件按场景分 `libcold-{A,F,N}.db` / `libhot.db` / `libbatch-N.db`。
- 样张 = CC0 原件硬链接：`$G/darktable/samples/{7RM5-LosslessCompressedLarge.ARW, Fujifilm-GFX100S-14bits-uncompress-4_3.RAF, Nikon_Z8_raw_14_bit_lossless_compression.NEF}`（源 `~/Library/Application Support/Lightamer/TestRAW/`，同盘零拷贝）。未碰用户实拍库。
- 内嵌预览：`exiv2 -ep2/-ep4` 提取 `*-preview{1,2,4}.jpg` 用于相关性自证。
- 批量样张：同一组硬链接平铺重命名 `p00001…`（三样张轮转），三档目录 `batch/n100` / `n1000` / `n10000` 各 100 / 1,000 / 10,000 个文件；库分别为 `libbatch-N.db`。

### 1.3 偏好保护

- 运行前快照 `$G/darktable/snap-before.txt`（`~/Library` 七个子目录条目名）+ `domains-before.txt`（`defaults domains` 排序快照，47,442 条）。
- 既有 `org.darktable` 域名运行前 `defaults export` 到 `prefs-backup-org.darktable.plist`（1,726 B）。
- 收尾：`defaults import org.darktable` 还原；只删除运行前不存在的、名称归属 darktable 的条目；未 `killall cfprefsd`。

### 1.4 计时与就绪判据

- 壁钟 `time.time()`；单机事件间隔。
- 10 Hz 窗口截帧（`cap.py`）：`CGWindowListCreateImage` 抓目标窗口 → 320 px 灰度降采样 → 相邻帧平均绝对差连续 3 帧 < 0.35/255，且与首帧差 > 1/255 或帧内标准差 > 8（非空窗）。窗口尺寸变化按「已变化」处理（`darktable` 主窗在启动 0.2 s 内会从 630 长到 652，首版因此广播异常，已修）。
- M1 冷：每测量独立进程；`t0` = `Popen` 前；含进程启动、GTK 初始化、库打开、RAW 解码、暗房首屏。首个配置向导只在首次首启出现（本 lane 在布置运行中按 launch-check 配方关闭，后续冷启无向导）。
- M1 热：同进程暗房内 `→` 切图；本轮未收敛（§8）。
- M2：Lua 快捷键 `F7` → `dt.gui.action("iop/exposure/exposure", 0, "", "set", v)`，`v` 在 0.0 / 0.5 间切换；读回值见 `dt.LUA` 日志（`ret=0.5 / 2.98e-08`）。`t0` = 按键前；M2 = 就绪时刻 − 按键时刻。
- M3a/b/c：`Ctrl+V` / Lua `F8` → 粘贴；`history` 表计数；`history_hash.mipmap_hash == current_hash` 为缩略图真值；积压期 `d` 打开一张。**本轮未形成数字**。

### 1.5 共享脚手架（本 lane 建，后续对象复用）

- `$G/_harness/`：`cap.py`、`input.py`（含 `activate()` 激活前台、合成键鼠/滚轮）、`verify.py`（就绪帧 ↔ 内嵌 JPEG 相关性）、`dt.py`（darktable 编排）、`probe_open.py`、`prefs_restore.sh`、`stats.py`，以及 venv（pyobjc-framework-Quartz + numpy + pillow）。
- 仓内副本：`evidence/gui/_harness/`。
- 权限：屏幕录制 = `screencapture -x` 得 3008×1692 非纯黑图；辅助功能 = 合成鼠标/键盘生效。
- 关键坑（供后续对象复用）：直接执行 `Contents/MacOS/darktable` 后窗口 **不在前台**，合成键必须先用 `NSRunningApplication.activate`；lighttable 无选中图时按 `d` 会提示「no image to open!」，要先 `Home` 选中；`screencapture -l` 输出是窗口局部坐标（本窗 3008×1632 px，点击要加窗口原点）。

## §2 打开 / 编辑等待数字

见 §0。补充：

- 冷启动三段（A7R5）：进程起 → 主窗 4.45 s；主窗 → 视口稳定 1.79 s；合计 6.24 s。GFX100S 与 Z8 同构（4.46/4.66 s + 2.05/1.71 s）。
- 三个样张的 M1 冷差异（6.24/6.51/6.37 s）在 0.3 s 内，**文件大小（61–210 MB）不是主因**；主导是应用启动 + GTK/窗口映射（约 4.5 s，占 72%）。
- M2：10 次合并 median 0.680 s，min 0.661 / p90 0.825；两个方向（+0.5 / −0.5）中位 0.673 / 0.687，无系统性方向差。Lua 读回值证明每次真的改了参数（0 ↔ 0.5），不是缓存位图。
- 本轮未测热打开（§8），所以「第二张起是否更快」没有数字；以 M2 的 0.68 s 看，解码结果在暗房内被复用，切图成本预计低于冷开，但**未验**。

## §3 批量粘贴数字

**未测得**。100 张档的导入/批处理驱动在 22:09–22:12 卡住（darktable 进程存活、日志只有 GTK 警告，`batch-results.csv` 未生成），时间盒耗尽后停止。没有 M3a/M3b/M3c 的墙钟数字，不编造。

可复核的代码路径（darktable 5.6.2，本地源码 `/Volumes/UNITEK/Documents/Development/darktamer/src`）：

- `dt_control_paste_history()`（`control/jobs/control_jobs.c:2595`）只把选中图 id 列表包装成后台任务；按钮动作 `lib/copy_history/paste` 返回即回 UI。
- `_control_paste_history_job_run()`（同文件 `:1787`）逐张调用 `dt_history_paste()`（`common/history.c:2234`），**不解码、不渲染**；任务开始时 `dt_stop_backthumbs_crawler(FALSE)`（`:1789`），结束后 `dt_collection_update_query(..., DT_COLLECTION_CHANGE_RELOAD, ...)`（`:1833`）只做集合失效。
- 缩略图：`history_hash.mipmap_hash` 与 `current_hash` 不等即「缩略图过期」；`control/crawler.c:1699` 的 `dt_update_thumbs_thread` 只在 **lighttable 且用户空闲** 时批量生成（每轮 12×250 ms 静默检查），即按需/后台，不是粘贴时同步。

→ 架构判定：**粘贴路径是 DB-only + 懒缩略图**，属于「换解码器也救不了」的反面（不逐张解码）。但缺数字，不能据此给「几秒」结论。

## §4 归因拆解

- **粘贴操作本身**：代码级 = 只写 history（SQLite）+ 集合失效；不触发解码/渲染。UI 线程返回时间未测（`PASTE ret=nan`，Lua action 存在但未形成计时）。
- **缩略图单张成本**：未测。以 SPIKE §4.6 的同机同文件拆解作参照：rawspeed 文件→马赛克 37 ms，LibRaw 全幅 demosaic 445 ms（线性）/857 ms（AMaZE），CPU 单张缩略图大致落在「解码 + CPU demosaic + 编码」的数百 ms 级；darktable 走 rawspeed + CPU pipeline，量级应相近。**这是推算，不是本轮实测**。
- **排队与阻塞**：粘贴是 `DT_JOB_QUEUE_SYSTEM_BG` 后台任务，UI 不阻塞（代码路径）；缩略图由空闲 crawler 分批生成，期间 lighttable 可交互（代码路径）；未做行为级 M3c 实测。
- **判定**：未测得数字，**不判「解码器原因 / 架构原因」**。可确定的是粘贴不做逐张解码；若后续实测出长等待，优先查缩略图 crawler 的 CPU demosaic 成本与调度，而不是解码器。

## §5 与 SPIKE.md §4 的 CLI 数字对账

| 项 | SPIKE §4（CLI 位图） | 本 lane（GUI） | 差异解释 |
|---|---|---|---|
| A7R5 冷开（预览档） | P0 CIRAW 894 ms；P1 rawspeed→DNG 427 ms | **6.236 s**（进程起 → 视口稳定） | 口径不同：GUI 含进程启动 + GTK 初始化 + 窗口映射（4.45 s，占 72%）；扣除后 1.79 s，仍是 CLI 的 2–4 倍（darktable 走 rawspeed + CPU demosaic + 完整 pixelpipe，且首屏按窗口尺寸渲染）。 |
| A7R5 编辑 | P0 371 ms；P1 11 ms | **0.680 s** | 口径不同：darktable 每次提交走 history + 全预览重渲染（CPU），不是 CIRAW 已解码平面复用；0.68 s 与 P0 的 371 ms 同量级，远慢于 P1 的 11 ms。 |
| 大图（GFX100S 210 MB） | P1 冷开 427 ms（同文件） | **6.508 s**（扣窗口 2.05 s） | 同上；文件大小对 darktable 冷开的增量 <0.3 s，说明其瓶颈不在文件读取/解码，而在固定启动与首屏渲染。 |

> 结论：**GUI 数字不能与 SPIKE 的位图数字直接比**；同口径可比的是「扣掉窗口出现后的首图时间」（1.7–2.1 s）与「编辑时间」（0.68 s），二者都显著慢于 CIRAW/rawspeed 的 CLI 位图路径，但 darktable 的优势在**批量不逐张解码**（代码路径），不在单张延迟。

## §6 这个 App 做对了什么（懒在哪一层）

1. **粘贴不逐张解码/渲染**：`dt_control_paste_history` 只排后台 job，job 内 `dt_history_paste` 写 history 行，不碰像素；这是「一万张几秒」的结构基础（数字未测）。
2. **缩略图按需 + 空闲 crawler**：mipmap 缓存以 `history_hash.mipmap_hash` 判新旧，lighttable 空闲才批量补；不阻塞用户当前操作。
3. **首屏与编辑分离**：暗房只渲染当前图；lighttable 只生成可见缩略图；没有「导入即全量解码」的同步路径（launch-check 也观察到导入后缩略图逐张出现）。
4. **代价**：单张打开仍要付 4.5 s 的进程/GTK 启动 + 1.7–2.1 s 首屏；编辑 0.68 s 是 CPU pipeline 重渲染，不是已解码平面复用。也就是说，darktable 懒在**批量**，不懒在**单张启动**。

## §7 删除清单

- 已删：`/Users/Shared/lightamer-gui-test/darktable/`（1.1 GB），含 `apps/darktable.app`、隔离 `home/`（dt-config / data.db / 缓存）、`samples/` 与 `batch/` 硬链接、`frames/` 存证帧、`logs/`、`dl/`。
- 进程：`pgrep -fl "lightamer-gui-test/darktable"` 清零（含最后一次 batch 卡住的 app pid 17335，已 `kill -9`）。
- 偏好：`org.darktable` 已 `defaults import` 还原；运行前后 `defaults domains` 比对无新增域名；`~/Library` 七个子目录无运行前不存在的 darktable 条目（`prefs_restore.sh` 输出为空）。
- 磁盘：删除前 41 GB 可用 → 删除后 41 GB（1.1 GB 回收，取整）；`df -h /` = 41 GB avail。
- 未动：`$G/_harness/`（共享脚手架，后续对象复用）、`$G/_launchcheck/`（前一 lane 的存证）。

## §8 风险与未验项

- **M1 热未测**：暗房内连续 `→` 切图时 darktable 进程退出（两次独立运行均在切图阶段消失，日志只有 GTK IM 警告，无 crash 报告），hot 循环未产出 CSV。未定位是合成按键、内存还是上游崩溃。**下一对象不要复用 hot 驱动，先做单次切图布置验证。**
- **自审未完成**：域内自审 `omp -p` 实例在 170 s 时间盒内未产出 `evidence/gui/darktable-SELFREVIEW.md`（进程被 SIGTERM，无结论头）。因此本报告**没有独立自审背书**；统计数字由 `stats.py` 直接复算，存证帧抽检未做。下一对象/复跑时应先跑自审再删帧。
- **M3 未测**：batch 100 档在导入/粘贴前卡住（进程存活、无输出），时间盒耗尽。没有 100/1,000/10,000 任何数字；批次结论只能引用代码路径，不能引用墙钟。
- **向导**：首次配置的「Welcome」6 页在本 lane 的布置运行中出现并被 Escape 关闭；后续冷启无向导（配置已初始化），因此**向导对 M1 冷的影响没有独立数字**。
- **合成输入**：darktable 直接执行二进制后窗口不在前台，已用 `NSRunningApplication.activate` 修正；若后续对象不激活，所有键盘驱动都会静默失败（本 lane 首轮即此坑）。
- **口径偏差**：M1 冷 = 进程启动 → 视口稳定，包含 4.5 s 启动成本；不要与 SPIKE 的位图口径直接平均。
- **并行污染申报**：本 lane 启动 GUI 时，spike lane 的 omp 进程（pid 53383）仍在（其最终 commit `26c6446f` 于 21:40 落盘，最后一次 bench 产物 `evidence/bench.csv` mtime 21:37；`pgrep` 无 cmake/ninja/bench 进程）。本 lane 的 `Scripts/machine-guard.sh` 在起跑前 PASS。判定：spike 的计时已完成，仅剩报告文字工作；但严格按「等 pid 退出」的约束，本 lane **提前启动**，记录为偏差。

## §9 issue #26 评论草稿

> darktable 5.6.2（官方 arm64，SHA `6ff88e5…`）真机 GUI 计时（M4/16 GB/macOS 27.3）：
> - M1 冷（进程起 → 视口稳定，n=5/样张）：A7R5 **6.24 s**、GFX100S **6.51 s**、Z8 **6.37 s**；其中主窗出现约 **4.45–4.66 s**，即 **72% 是应用启动/GTK**，不是解码。
> - M2 编辑（曝光 0↔0.5 EV，Lua 读回证实，n=10）：**0.68 s**（0.661 / 0.825）。
> - M3（100/1,000/10,000）本轮**未测得数字**：批处理驱动在导入阶段卡住，时间盒耗尽。
> - 代码级：粘贴 = 后台 DB job（`control_jobs.c:2595/1787`，不逐张解码）；缩略图 = mipmap 按需 + lighttable 空闲 crawler（`crawler.c:1699`）。架构是懒的，但**没有本机墙钟数字**，不能据此宣称「一万张几秒」。
> - 与 SPIKE §4 对账：GUI 6.24 s ≠ CLI 894 ms，差在 4.5 s 启动；扣启动后首图 1.7–2.1 s、编辑 0.68 s，仍慢于 P1 的 427 ms / 11 ms。**单张延迟不是 darktable 的优势，批量懒渲染才是。**
