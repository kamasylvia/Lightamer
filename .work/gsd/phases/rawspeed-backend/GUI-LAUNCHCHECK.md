# GUI Launch Self-Check (pre-timing, Lightamer #26)

- 仓库 HEAD：`2bdc40228afacb1b8176107600546b3eb9a87b9d`（含未跟踪的 `.work/` 规划文件若干个，均非本批产物）
- 环境：macOS 27.3（26C5035r）/ arm64 / 主屏 3008×1632（2×）/ 内置盘余量 42GB
- 权限自检：`screencapture -x` 正常（非黑帧）；System Events AX 读取正常（`count processes` = 155）；合成鼠标移动/点击生效（`CGEventPost(kCGHIDEventTap)`）
- 本批**不量任何性能数字**，只回答「能否无人值守启动并显示一张图」
- 工作区：`/Users/Shared/lightamer-gui-test/_launchcheck/`（`$G`），帧留 `$G/frames/<app>/`（长边 1280）

## §0 结论表

| App | 版本 | 能取到包 | 能无人值守启动 | 样张能直接出图 | 挡路弹窗 | 需用户事先授的权限 | M2 可用驱动 | 能正常退出 |
|---|---|---|---|---|---|---|---|---|
| darktable 官方 | 5.6.2 arm64 | 是（89MB，adhoc） | 是（直接执行二进制 + `--configdir`/`--library`） | 是（NEF 进 darkroom 完整显示） | 首启模态「Welcome to darktable!」6 页向导，须点 `close` | 无 | 合成鼠标（GTK 的 AX 树为空） | 是（AppleScript 报 -128 但进程已退，pgrep 0） |
| Alcedo Studio 官方 | 0.3.6 arm64 | 是（176MB，adhoc） | 是（出「项目启动器」） | **否**（忽略文件参数；必须先建/开 `.alced` 项目再导入） | 项目启动器对话框（非阻塞向导，是唯一入口） | 无（但隔离 HOME 失效，见 §1.2） | AX 可读（窗口下 144 个元素） | 是（需 `kill -TERM`；AppleScript quit 无效） |
| LUMEN RAW 官方 | 2.3.0 macOS arm64 | 是（663MB，adhoc） | 是 | **是（唯一一个命令行传文件直接出图的）** | 无 | 无 | AX 可读（窗口下 34 个元素） | 是（`kill -TERM`，pgrep 0） |
| RawLab 官方 | 0.12.0 arm64 | 是（723MB zip，官方 sha 已核） | **半**：直接执行二进制 = 45s 零窗口；`open -a` + 文件 = 有窗口 | 是（`open -a` 传 NEF 直接进编辑器全图） | 无 | 无 | 合成鼠标；AX 浅层 6 子元素 | 是（`osascript quit`，pgrep 0） |
| LightCraft 官方 | 0.21.1 universal | 是（127MB，Developer ID 已公证） | 是（传文件即自动导入） | 是（库视图出缩略图，双击进编辑器全图） | 首启 Welcome 6 页（Skip）+「Download lens profiles?」（Not Now） | 无 | 合成鼠标（AX 浅层只 4 个子元素）；**双击缩略图进编辑器** | 是（`osascript quit`，pgrep 0） |
| Lightamer 现有构建 | 0.1.0 (1)，2026-10-15 | 本地 `build/`（adhoc） | **半**：直接执行二进制 = 60s 零窗口；`open -a` = 有窗口 | **否**（只显示「尚未打开项目」无按钮文案） | 无弹窗，但主窗口是死路提示 | 无 | 未测（浅层 AX：1 窗口 5 子元素） | 是（AppleScript quit，pgrep 0） |

一句话：**正式计时能直接开跑的是 darktable、LUMEN RAW、LightCraft**；**Alcedo 和 Lightamer 都需要先解决「项目」前置**，否则 M1「打开文件→出图」根本不存在。

## §1 逐 App 细节

### 1.1 darktable 5.6.2（参考基准）

- 资产：`darktable-5.6.2-arm64.dmg`，88,884,896 B，`sha256 6ff88e58a2a59cb07b0a1502fea7205e68cd783380a33a3ce7bda68ec29def0c`
  （`https://github.com/darktable-org/darktable/releases/download/release-5.6.2/darktable-5.6.2-arm64.dmg`）
- 签名：`Identifier=org.darktable`，`Signature=adhoc`，`TeamIdentifier=not set`；`spctl -a -vv` = **rejected**（`source=no usable signature`）
- 去隔离：**是**（`xattr -dr com.apple.quarantine`；残留 `com.apple.provenance` 不影响启动）
- 启动命令（实测可用）：

  ```
  HOME=$G/darktable/home CFFIXED_USER_HOME=$G/darktable/home \
  $G/darktable/apps/darktable.app/Contents/MacOS/darktable \
    --configdir $G/darktable/home/dt-config --library $G/darktable/library.db \
    $G/darktable/samples/Nikon_Z8_raw_14_bit_lossless_compression.NEF
  ```

- 时间线（截图见 `$G/frames/darktable/`）：
  - t=2s：启动 splash（窗口名 `org.darktable.darktable`，700×365）
  - t≈8-12s：主窗 1504×816 + 模态对话框「Welcome to darktable!」500×477（6 页向导，按钮 `prev` / `next` / `close`）
  - 模态出现在主窗之上，但主窗底部 filmstrip 已经出现样张 → **图在弹窗底下已经解好**
- 关弹窗：`Return` 只翻页（不关）；**必须点 `close`**，弹出后 6 页都可跳过。实测坐标 screen (970, 656)。
  - 教训：`screencapture -l <wid>` 出的是**窗口局部坐标**，合成点击要加窗口原点（窗口 y=30 → 我第一次按 (970,626) 点了但无效，修正后才关上）。
- 出图：关弹窗后 darkroom 完整显示 NEF（`darktable-image-shown.png`）
- AX：`windows=1 | w1_children=4`，`entire contents` = **0** → GTK 不向 AX 暴露控件，**M2 只能合成鼠标拖滑杆**
- 退出：`osascript quit` 返回 `-128 用户已取消`，但进程随即退出，`pgrep` = 0

### 1.2 Alcedo Studio 0.3.6（UX 对标）

- 资产：`AlcedoStudio-0.3.6-Darwin-arm64.dmg`，176,082,021 B，`sha256 549b2b0a72036f0f1b78e555eafde0d686797f88759c20ae664f6d63b31b76b7`（项目未发布校验和，此为本地复算值）
- 签名：`Identifier=studio.alcedo.Studio`，`Signature=adhoc`，`TeamIdentifier=not set`；`spctl` = **rejected**（`source=no usable signature`）
- 去隔离：**是**
- 启动命令：`$G/alcedo/apps/AlcedoStudio.app/Contents/MacOS/AlcedoStudio <NEF>` → t=2 无窗口，t=6 出现 1504×816「Alcedo Studio」**项目启动器**
- **样张不能直接出图**：命令行文件参数被忽略。启动器只有：
  - 左：「打开项目…」「新建项目…」
  - 右：「继续上次的项目」卡片 = 用户真实环境里的一个既有项目（名称、路径、张数已抹去：属用户隐私）+「继续编辑」
  - 底部：「跟随系统」「退出」
- **隔离 HOME 失效（须登记）**：本次运行在真实 `~/Library/Preferences/` **新建** `com.alcedo-app.Alcedo.plist`（birth 2026-11-24 19:44:49，693 B），并且读到了用户真实的最近项目路径。Qt/CFPreferences 不吃 `CFFIXED_USER_HOME`（cfprefsd 是每用户守护进程，永远写真实 HOME）。该文件本批已删除。`~/Library/Application Support/Alcedo` 未被本批新建（birth 2026-09-28，属用户既有）。
- AX：`windows=1 | w1_children=144`（Qt 可读，比 darktable 强）；进程名在 System Events 里是 **`AlcedoStudio`**（带空格会 `NO_PROCESS`）
- 退出：`osascript quit` 无响应；`kill -TERM` 干净退出，`pgrep` = 0
- 帧：`$G/frames/alcedo/alcedo-t6..t60-w58445.png`（5 张）

### 1.3 LUMEN RAW 2.3.0（Python + PyInstaller）

- 资产：`LumenRAW-2.3.0-macOS-arm64.dmg`，662,538,964 B，`sha256 6e002680d7e8860929c52cebf0ae701dd5c752866e5eb511e527121ebc9b2a71` = **与官方 `SHA256SUMS-macOS.txt` 一致**（已核）
  （release tag `v2.3.0-macos`；`v2.3.1`/`v2.3.2` 无 macOS 资产，按「最新带 macOS arm64 DMG」取此版）
- 签名：`Identifier=io.github.hety0211.lumenraw`，`Signature=adhoc`，`TeamIdentifier=not set`；`spctl` = **rejected**
- 去隔离：**是**；解包后 910MB
- 启动命令：`$G/lumen/apps/LUMEN RAW.app/Contents/MacOS/LumenRAW <NEF>`（可执行名 `LumenRAW`，另有 `lumen-cli`）
- **直接出图**：t=3 主窗 1504×816，标题「LUMEN RAW 2.3.0 · 多品牌 RAW 工作室」，**样张已在编辑器里显示**（底栏 `NEF 8280×5520`，状态栏 `预览已更新 · 137 ms`、`GPU`、`编辑已保存`）
- 无首启向导、无 TCC 弹窗。stderr 仅一条 Qt 警告：`qt.accessibility.table: Cell requested for row 1 is out of bounds for table with 0 rows! Resizing table model.`
- 面板可见「曝光与动态范围」「自动加速 (Metal / Core ML)」「Metal · Apple M4」
- AX：`windows=1 | w1_children=34`
- 退出：`kill -TERM` 后 `pgrep` = 0
- 帧：`$G/frames/lumen/lumen-t3..t40-w58493.png`（5 张）

### 1.4 RawLab 0.12.0 arm64

- 资产：`RawLab-Mac-0.12.0-arm64.zip`（release tag `v0.12.0`；最新 `v0.12.1` 只发 Android/iOS，无 macOS 资产），723,061,601 B，
  `sha256 6f2cca0bdd40aa0094459116aaed80d476454bcdbd16ea6515dc336779c9d48b` = **与官方 `SHA256SUMS.txt` 一致**（已核）
- 签名：`Identifier=com.rawtools.rawlab.mac`，`TeamIdentifier=not set`，`origin=RawLab Release Signing`；`spctl` = **rejected**
- 去隔离：**是**；解包后 962MB
- 启动方式 A（直接执行 `apps/RawLab Mac.app/Contents/MacOS/RawLabMac <NEF>` + 隔离 HOME）：进程活着（68MB RSS），**45 秒零窗口**（Quartz `option All` 也 0）
- 启动方式 B（`open --env HOME=… -a "RawLab Mac.app" <NEF>`）：窗口出现（1320×816，标题 `RawLab Mac`），**样张直接在编辑器里显示**（底栏 `Nikon_Z8_raw_14_bit_lossless_compression.NEF` / `预览 1536 × 1024 · sRGB`），右侧「调整栏 / 外观 / 光线 / 颜色 / 效果 / 细节 / 几何与镜头」齐全（`rawlab-openfile.png`）
- 无首启向导、无 TCC 弹窗
- 隔离副作用：真实 `~/Library/Preferences/com.rawtools.rawlab.mac.plist` **新建**（birth 20:00:55，187 B），本批已删
- AX：`windows=1 | w1_children=6`（浅层）
- 退出：`osascript quit` 正常，`pgrep` = 0
- 帧：`$G/frames/rawlab/rawlab-openfile.png`（1 张）

### 1.5 LightCraft 0.21.1

- 资产：`lightcraft-0.21.1-macos-universal.dmg`，127,261,345 B，`sha256 b70f46cac01390154c9adfa06822e6691b95fc270c507b0ed220a00dc588bb1e` = **与官方 `SHA256SUMS.txt` 一致**（已核）
- 签名：`Identifier=ai.storyteller.lightcraft`，`Authority=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)`；`spctl` = **accepted**（`Notarized Developer ID`）
- 去隔离：**是**（虽已公证，统一处理）
- 启动命令：`$G/lightcraft/apps/LightCraft.app/Contents/MacOS/LightCraft <NEF>`
- t=2 就有主窗「LightCraft — LightCraft Library」1504×816，样张**自动导入**（`All Photos`，`Friday, 2 June 2023`，`1 photo`，缩略图可见 = 出图）
- 弹窗链（都在 App 自己窗口内，可无人值守关掉）：
  1. 「Welcome」6 页向导（`Back` / `Skip` / `Next`）→ 点 **Skip** 结束
  2. 「Download lens profiles?」（`Not Now` / `Download`）→ 点 **Not Now**
- 进编辑器：**双击缩略图** → 全图显示，右侧 Light 面板 `Exposure 0.00` / Contrast / Highlights / Shadows / Whites / Blacks 滑杆齐全（`lightcraft-editor2.png`）
- AX：`windows=1 | w1_children=4`（浅层）；未做深层遍历
- 退出：`osascript quit` 正常，`pgrep` = 0
- 帧：`$G/frames/lightcraft/`（7 张：t2…t60 + 编辑器两张）

### 1.6 Lightamer 现有构建（2026-10-15，v0.1.0 build 1）

- 包：`build/DerivedDataRelease/Build/Products/Release/Lightamer.app`（自 2026-10-15 15:09 未动）；`com.kamasylvia.lightamer`，adhoc；未重建（按任务书）
- 启动方式 A（直接执行二进制 + 隔离 HOME）：进程活着（`SNs`，主线程空转在 `NSApplication run` 的 `_DPSNextEvent`），**60 秒内 Quartz 与 AX 都是 `windows=0`**，physical footprint 仅 20MB → 不建窗口
- 启动方式 B（`open --env HOME=… -a Lightamer.app <NEF>`）：约 8s 后出现 1440×816 窗口，**内容是「尚未打开项目。创建或打开一个项目来整理你的图库。」**，无可见按钮
- **不出图**，命令行传样张被忽略（文件根本没进编辑器）
- AX（唯一一次浅层读取，遵守禁止深度遍历）：`windows=1 | w1_children=5`
- 隔离副作用：真实 `~/Library/Preferences/com.kamasylvia.lightamer.plist` **新建**（birth 19:37:49，1381 B），本批已删
- 退出：`osascript quit` 正常，`pgrep` = 0
- 帧：`$G/frames/lightamer/lightamer-openfile-t9-w58396.png`（1 张）
- 含义：M2-2 项目模型把「开图」锁在 `.lalb` 项目之后；旧构建没有建项目入口 → 正式计时必须先解决这一层，否则本对象 M1 无法测「打开→出图」

## §2 需要用户做的事

1. **Alcedo 的项目前置（必须）**：正式计时前需要一个 `.alced` 项目并导入三个样张。当前启动器唯一入口是「打开项目 / 新建项目 / 继续编辑」，没有任何「直接开文件」通道（§1.2）。建议：在 `$G/alcedo/` 下新建专用项目，导入样张硬链接，之后 M1/M2 都从这个项目里打开。
2. **Alcedo 的 HOME 隔离失效（需知情）**：它会写真实 `~/Library/Preferences/com.alcedo-app.Alcedo.plist`。如不接受，正式计时前请在系统设置里给它一个独立的用户账户，或事先备份该 plist。
3. **Lightamer 现有构建不可用（必须决定）**：旧构建只到「尚未打开项目」死路。两条路选一：
   - 正式计时前按 HEAD 重建 Release（走 `Scripts/make-release-direct-launchable.sh`，过机器守卫），再验证「建项目 → 导入 → 出图」路径；
   - 或者明确接受 Lightamer 本轮只能测「项目内打开」，并先在 GUI 里手工建好一个项目（隔离 HOME 里），再让脚本复用。
4. **无声明的 TCC 授权**：本轮 0 个系统权限弹窗（样张在 `/Users/Shared`，非 TCC 保护目录）。若正式计时把样张/项目放到 `~/Pictures`、`~/Documents` 或外置卷，会新弹「文件与文件夹」授权——**建议正式计时继续用 `/Users/Shared`**，避免弹窗。
5. **磁盘**：RawLab 解包后体量大（zip 723MB），加上 Lumen 的 910MB，单轮请保证 ≥10GB 余量（当前 42GB）。
6. **HOME 隔离只挡一半（需知情）**：`HOME`/`CFFIXED_USER_HOME` 只影响 App 自己的目录（`Application Support`/`Caches`），**偏好 plist 一律写真实 `~/Library/Preferences`**（cfprefsd 是每用户守护）。本批新建的三个 plist（`com.alcedo-app.Alcedo`、`com.kamasylvia.lightamer`、`com.rawtools.rawlab.mac`）已删；`org.darktable.plist` 是本机既有（birth 2026-11-07），本批被修改、无法还原——正式计时如果在意这一点，需要接受或换用户账户。

## §2.5 本批清理

| 项 | 结果 |
|---|---|
| `$G/<app>/`（darktable / alcedo / lumen / rawlab / lightcraft / lightamer） | 全部删除（二进制 + 隔离 HOME + 硬链接样张 + 缓存），逐个 `pgrep` 清零后删 |
| 帧 | 保留 `$G/frames/<app>/`（darktable 6 / alcedo 5 / lumen 5 / lightcraft 8 / rawlab 1 / lightamer 1 张 PNG + 各自 windlog），长边 1280，合计约 10MB |
| 真实 `~/Library` 新增 | 3 个 plist（见上「HOME 隔离只挡一半」），已删；`killall cfprefsd` 冲缓存后 `defaults read` 确认域名消失 |
| 内置盘 | 起 42GB → 收 41GB（`df -h /`） |
| 进程 | 六个对象全部 `pgrep` 清零（只杀自己起的） |

## §3 未验项

- **启动路径差异（跨 App 规律，正式计时必须写进每个任务书）**：直接执行 `Contents/MacOS/<exec>` 时，Lightamer 与 RawLab **都不建窗口**（等 LaunchServices 的 open-document 事件），Alcedo 只出启动器；darktable / Lumen / LightCraft 会正常出窗。→ 统一启动方式应为 `open --env HOME=… -a <app> <file>`，并在启动后用 `pgrep`/`CGWindowList` 确认窗口真的出现再开始计时。
- **曝光滑杆的定位方式只做到「元素计数」**：darktable（4 子元素/entire contents=0）判定为不可用 AX；Lumen（34）与 Alcedo（144）只证明 AX 有树，未证明能定位到曝光滑杆；LightCraft 浅层 4 个子元素，未深挖。正式计时开场各 App 需现场补一次「按 AXTitle/role 能否找到滑杆」的探针，失败即退合成鼠标。
- **TCC 弹窗覆盖不全**：本轮只走非保护目录，未触发「文件与文件夹 / 通知 / 本地网络」任何一类，故「需事先授的权限」一栏全部为空**不构成**「永不需要」。
- **Alcedo 0.3.6 的 DMG 无官方校验和**：本批记录的是本地复算值（`549b2b0a…`），来源只有 GitHub release CDN，无 `SHA256SUMS` 可比对。
- **Lightamer 的 RAF 样张**：未测——该构建连 NEF 都不显示，RAF 无意义。
- **`screencapture -l` 的坐标语义**：本批踩坑（窗口局部坐标），正式计时脚本化点击时必须统一加窗口原点，否则合成点击全体偏移 30pt。

## §4 塔台复核（orchestrator，2026-11-24）

- **隐私抹除**：§1.2 原文记录了用户真实环境里一个既有 Alcedo 项目的名称、路径与张数，已抹去；对应的启动器截图（`$G/frames/alcedo/`）已删除。原因是 `HOME` / `CFFIXED_USER_HOME` 隔离挡不住它读真实的最近项目列表。
- **更正 §2 第 6 条**：`org.darktable.plist` 复核时 mtime 仍为 2026-11-07 10:02，本批未改动它，原文「被修改、无法还原」不成立。
- **更正「新建 plist」的判定方法**：本批用文件 birth 时间判定「新建」不可靠。cfprefsd 每次写入都换新文件，birth 时间随之刷新。被删的三个 plist（`com.kamasylvia.lightamer`、`com.alcedo-app.Alcedo`、`com.rawtools.rawlab.mac`）**可能在本批之前就存在**，其中 Lightamer 与 Alcedo 的很可能是用户既有偏好。本机无 Time Machine 快照，无法恢复。
- **教训与修订**：正式计时的通用任务书已改为——启动任何 App 之前，先按域名检查并 `defaults export` 备份既有偏好；测完按「运行前是否存在」还原或删除；没有运行前记录的条目一律不删；禁止 `killall cfprefsd`。
