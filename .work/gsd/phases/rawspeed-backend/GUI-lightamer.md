# GUI timing — Lightamer (CIRAW path, product HEAD build)

执行日期 2026-11-25 · lane = omp GUI timing（issue #26）· 构建 commit `beaac01a947246ad674b0e5118c345b147e30ea8`（Release）
工作区 `/Users/Shared/lightamer-gui-test/lightamer/`（仓外，已删除）· 隔离 HOME · 本仓只留本报告 + CSV（`evidence/` 按 .gitignore 政策不入仓）

## §0 结论头

### M1 打开等待（默认项目面；启动 → 首图 preview 完成；n=5/样张；括号 = min / max）

| 样张 | launch→窗口 | launch→grid 可点（含窗口） | 点击→preview 推屏（中位） | **launch→首图（中位）** |
|---|---|---|---|---|
| Sony 7RM5（86MB ARW，85MP） | 0.36 s | 0.55 s（窗口→grid 增量 0.19） | **1.57 s**（1.53 / 1.59） | **2.13 s** |
| Fujifilm GFX100S（210MB RAF，102MP） | 0.37 s | 0.54 s（窗口→grid 增量 0.17） | **1.71 s**（1.66 / 2.12） | **2.40 s** |
| Nikon Z8（61MB NEF，45MP） | 0.37 s | 0.52 s（窗口→grid 增量 0.15） | **1.33 s**（1.29 / 1.40） | **1.82 s** |

- 冷 = 每 rep 独立进程（含进程启动）。样张全部可解；A7R5（ILCE-7RM5）可解（CIRAW v8）。组件口径：**launch→首图 = launch→grid（t_grid）+ 点击→preview**（相加吻合，见下）；launch→窗口是 t_grid 的子集，不参与相加。
- **M1 热：本 lane 未取得有效数字（作废）。** 首版脚本在编辑器内重复点击「当前已打开的那一张」，27/30 无新 PREVIEW（点击未换图）。CSV 里的两个非空值（7RM5 2.975 s、GFX 3.095 s）是**下一段 pre-click 的真实换图渲染**被「最近前一条 click」无上界归属错记到上一段 rep9（推断相对时刻约 0.49/0.61–0.72 s，即 GFX/Z8 的单次热开），不是无效点击的产物；因单 rep、状态不受控，**弃用不采信**。CSV 为原始输出，未加作废标注（本报告标注）。

### M2 编辑等待（曝光滑杆；改值 → 视口稳定）

| rep | 驱动 | 输入→首次 live 推屏 | 输入→最终（commit）推屏 | 备注 |
|---|---|---|---|---|
| 1 | 慢拖（合成轨迹 ~0.9 s） | 0.23 s | **1.39 s** | 按报告口径「拖拽 0.72 s」则松手后 ≈0.67 s；帧差 ≈6 Hz 原点比 input 晚 0.218 s（`trial.json` 的 onset 1.61 / ready 2.12 = input 1.39 / 1.90，同一事件） |
| 2 | 快拖 0.16 s（3 步） | 0.11 s | **0.41 s**（松手后 ≈0.25 s） | 每次 30 平面全 miss |

**n=2（两 rep 范围，不是中位）**。两次均走「输入平面物化 + 参数链重跑」：PREVIEW 在 1840 入口把 `decoded.ciImage` 渲成输入平面（pipe cache 按 `contentDedupeID ⊕ decodeParamsHash` 复用），编辑只重跑下游 IOP 平面。**快拖 rep：live 0.11 s / commit 0.41 s（对 SPIKE 738 ms = −44%）；慢拖 rep：总 1.39 s（+88%），松手后 ≈0.67 s（约 −9%）。** 不能概括为「远低于 738 ms」。SPIKE 738 ms 的机制见 §5 更正（不是 CIRAWFilter 写入曝光）。

### M3 批量粘贴

| 项 | 结果 |
|---|---|
| 默认项目面 GUI 批量粘贴 | **不存在**：⌘⇧V 只作用于当前编辑图（`pasteToSelection` 读 `browserModel.selectedOrderedPaths` = 会话模型；项目格子的 `selectedIDs` 未接）；`LibraryGridView`/`WorkspaceHostView` 不引用 `AdjustmentsPasteboard` |
| Core / MCP 批量能力 | 存在：`SessionBatchApplier`（懒三段：内存 compose → 单事务 index → 后台串行 sidecar）+ MCP `paste_adjustments`（≤1000/次，源侧无状态重读） |
| M3a 实测 | **未取得**。legacy 会话（`LIGHTAMER_LEGACY_LIBRARY=1` + 目录 odoc 10,000 张硬链接）的行为：①首轮 10 min 后 MCP 仍把 `img_00002…` 当非成员（后续查明是会话索引**异步、渐进**）；②第二轮实测：会话打开后 **20.9 s** `img_00002.NEF` 成为成员，但同一时刻 `img_00004.NEF` 仍 `notSessionMember`，再等 ~20 s 仍不是成员 → **10,000 张的会话索引在 40 s 内未完成**，MCP 批量寻址不可用；③MCP 客户端会话数触顶（`maxSessions=4`）后新连接 503。被拒路径耗时 0.006–0.103 s（校验，不是 M3a）。 |
| M3a 代码外推 | 段1 = 每张读 `.lra`（KB 级 JSON）+ 内存 compose；段2 = 单事务批量 claim；段3 = 后台串行写（enqueue 即返回，flush 由 writer 继续）。**没有任何解码/渲染调用**（`SessionBatchApplier` 的签名集里没有 Metal/pipe/decoder）。按单张 compose 估 0.1–1 ms 级（**模型，未实测**）→ 1,000 张的返回 ≈ 0.1–1 s 量级 + 后台写盘；**不是解码器成本**。 |
| M3b 缩略图刷新 | **惰性**：粘贴只把 row 标 `thumb_state=stale`（claim txn），由 `SessionThumbnailProvider` 队列按需重建（并发 2；可见格优先；非可见 idle 1.5 s）。tier B = **完整 `RAWDecoder.decode(url)` + PixelPipe@360 + 写盘**，即每张一次完整 CIRAW 解码（≈ 本 lane 打开成本的解码段）。1,000 张强制全刷 = 1000 × ~1–1.7 s ÷ 2 ≈ **8–14 分钟**（**线性外推模型**，并发 2 的线性缩放未验证），但设计上只有可见格会被重建（滚动到才付费）。项目面更弱：桥的失效判据是源文件 mtime，渲染腿是 **pristine** smart preview（代码注释自述 P2 缺口）→ 编辑/粘贴**不会**让项目面缩略图失效或刷新。 |
| M3c 刷新期可交互 | 未测（M3b 未触发）。结构上：粘贴调用非 MainActor 且不碰渲染；缩略图队列独立于编辑器 pipe；编辑器打开走自己的 decode。风险点 = 强制全刷时 CPU/GPU 与打开抢资源。 |

### 判定句（带数字）

**CIRAW 路径在批量修图上不需要长时间挂起等待（排除条件不成立）：** ①粘贴本身是 sidecar/index 活，逐张不解码、不渲染（代码面）；②单张编辑走「输入平面复用 + 30 平面链」（无重解码）：快拖 live 0.11 s / commit 0.41 s（−44% vs 738 ms），慢拖总 1.39 s（+88%）；③首图上屏 1.8–2.4 s/张（45–102MP，n=5/样张），其中 **57–73% 是 CIRAW decode+CI render（解码器）**，其余是 30 平面链与装配（架构/代码）——两者不可合并。**若用户强制刷新全部 10,000 张缩略图**，成本 = 10,000 × ~1–1.7 s ÷ 2 并发 ≈ 1.4–2.4 小时——**这一条是解码器原因**（对 360 px 缩略图也做全尺寸 decode），可用「解码时降采样」（rawspeed/ds 或 CIRAW 前的马赛克降档）消除；批量粘贴的架构（懒渲染 + 按需 + 队列）本身合格。
**但**产品面有两条架构/代码缺陷须记：项目面**无批量粘贴路由**、项目面**编辑不失效缩略图**（观感不刷新）；另有每次编辑 30 平面全 miss 的过度重渲。

## §1 方法

### 1.1 二进制与隔离

| 项 | 值 |
|---|---|
| 来源 | 本仓 HEAD 重建（无官方二进制） |
| 构建 | `xcodebuild build -workspace Lightamer.xcworkspace -scheme Lightamer -configuration Release -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO -jobs 4` + `Scripts/make-release-direct-launchable.sh --skip-build`（BUILD_EXIT=0，571 s） |
| commit | `beaac01a947246ad674b0e5118c345b147e30ea8` |
| 二进制 SHA256 | `c3293ec7b0c464da8d539829f751f70060108ec0bbe93747f45ebfd2a3e84f21` |
| 签名 | adhoc（Release 配方） |
| 隔离 | `open -n -a Lightamer.app --env HOME=$G/home --env CFFIXED_USER_HOME=$G/home`；已实证 `Library.lalb` 建于 `$G/home/Library/Application Support/Lightamer/`，真实 `~/Library/Application Support/Lightamer/Library.lalb` mtime 始终 1793619957（未变） |
| 样张 | `~/Library/Application Support/Lightamer/TestRAW/` 硬链接（零拷贝）：7RM5 86MB / GFX100S 210MB / Z8 61MB |
| 项目 | 默认库（首启自动建）+ GUI 导入 3 张（链接模式；NSOpenPanel 经 `defaults write com.kamasylvia.lightamer NSNavLastRootDirectory <dir>` 定向 + 打开按钮） |
| 屏幕 | 1440×846 窗口于 (32,0)：`screencapture -l` + Quartz CGWindowList 截图；合成鼠标/键盘经 `CGEventPost`（前一 lane 已建 harness，本 lane 复用未改 cap.py/input.py） |

### 1.2 就绪判据与计时

- 视口就绪 = 统一日志 `pixelpipe output ready: PREVIEW bucket 1840px`（subsystem `com.kamasylvia.lightamer`，category `coordinator`）在点击后的**第一条**。该行在 `editorState.displayTexture` 推送同点打印，故 = 位图可上屏。
- 帧差（`cap.py`）用于首次可见变化/稳定与前后帧存证。实际采样 ≈5–7 Hz（每次 `screencapture` 的抓帧成本叠加，帧间隔 0.138–0.206 s），时间分辨率 ≈1 帧 = 0.15–0.2 s。判据：**onset = 跳过头 3 帧预热后 `diff_base > 1.5`**（`change_thresh`）；**ready = `diff_prev < 0.35` 连续 3 帧**（`stable_n`）。M1 冷另加「编辑器视口非黑 + 顶栏出现」的像素判据（帧差单独会把「编辑器 chrome 已定、视口还黑」误判为就绪，已实测踩到）。
- `log stream` 全程一条，按「每次点击的最近前一条时间戳」归属 rep（修掉了跨 rep 串线）。
- M1 冷：quit → 新进程 → 窗口 → grid 可点 → 双击 cell（独立 rep，5/样张）；launch→窗口中位 0.36/0.37/0.37 s，窗口→grid 增量 0.15–0.19 s。M1 热：未取得（见 §0）。M2：编辑器内曝光滑杆合成拖拽（D-H1 三段），每次新值，记录首个/最后一个 PREVIEW 日志时间。
- M3：MCP（Streamable HTTP `127.0.0.1:<port>/mcp`，`control_acquire` → `apply_params`/`paste_adjustments`），legacy 会话面（`LIGHTAMER_LEGACY_LIBRARY=1`），目标 10/100/1000 + 目录硬链接 10,000。失败原因见 §3/§8。

### 1.3 数量核对

- 导入后 SQLite `select count(*) from images` = 3（样张 3/3）。
- 冷 M1 每 rep 截图存证（含就绪帧）；打开的是预期样张（EXIF 读数：7RM5 50mm f/1.2 / GFX 45mm f/4 / Z8 等）。
- 批量目录 `find … -type f | wc -l` = 10,000（三源循环、文件名互异）。

## §2 打开/编辑等待数字

（同 §0；逐 rep 明细 = `evidence/gui/lightamer-m1-cold.csv`，字段 `preview_first` = 点击→PREVIEW 秒，`t_grid` = launch→grid 可点秒。）

- 冷 M1 离散度小：7RM5 1.525–1.587，GFX 1.661–2.121（第 1 rep 2.12 为 PSO/首解冷），Z8 1.287–1.397。
- 第 1 rep 的 CIRAW/Metal 冷启成分只在首 rep 可见（GFX 2.12 vs 1.66–1.92），其余稳定。
- 曝光编辑：未见任何「数十毫秒级」的推屏；最快 0.11 s（live），最终 0.41 s。每次编辑的 PREVIEW 日志都是 `0 hits / 30 misses, 30 planes`（= 从曝光模块往下的全部 30 个平面重跑；输入平面/更上游的平面不在统计内，未见 CIRAW 重解码）。

## §3 批量粘贴数字

- `paste_adjustments` 拒付路径（源非会话成员）返回 **0.006 s** —— 只证明校验是即时拒绝，不是 M3a。
- 代码外推：段 1 每张 = 读 sidecar + `PasteSemantics.paste` + 构造 1 个 document；段 2 = 1 个 SQLite 事务（10k 行一次）；段 3 = 后台串行 `BatchSidecarWriter`（enqueue 即返回）。**M3a（用户等待）= 段1+段2 的时间**，量级毫秒/张；M3a 之外还有后台写盘（不可见等待，但关窗/退出有 flush）。
- 初始化成本（不计入 M3）：10,000 张的会话/库导入未在本 lane 跑通（见 §8），无法给首扫时间。

## §4 归因拆解

以同文件 7RM5（86MB ARW，85MP）为例；其它样张单列，不做跨文件减法：

| 段 | 值 | 来源 |
|---|---|---|
| SPIKE 裸腿：decode + CI render（2560，无 IOP 链，不物化 1840 输入平面） | 968 ms 冷 / 759 ms 热 | SPIKE.md §4.1/4.2 |
| SPIKE M2：retained decoded image → CIColorMatrix → render 2560（无 IOP 链、无输入平面物化） | 738 ms（min 378 / p90 748） | `spike-src/bench.swift:218-232`、`benchrun.py:6-7` |
| **产品**打开：点击→preview（1840 入口平面 + 30 IOP 平面） | **1.57 s**（1.53–1.59） | 本 lane n=5 |
| 其中「打开 − SPIKE 裸腿」 | **+0.61 s**（同文件） | 30 IOP 平面 commit 实测 0.41 s（单点，非固定常量）+ 编辑器/overlay/scope/项目面装配 |
| **产品**编辑（快拖）：输入平面复用，30 平面全 miss | live 0.11 s / commit **0.41 s** | 本 lane |
| **产品**编辑（慢拖）：同上 | 总 1.39 s；松手后 ≈0.67 s | 本 lane |
| 单张缩略图 tier B（legacy 面） | = decode + pipe@360 + encode；未单测 | 代码 + 下表代理 |

**解码占比（同文件 7RM5，可算的两个分母）**：
- 点击→preview 1.574 s 中，SPIKE 裸腿 968 ms 占 **61.5%**（其余 = 30 平面链 + 装配）；
- launch→首图 2.129 s 中占 **45.5%**（分母含 launch 0.36 s 与 grid 0.19 s）。
- 三样张点击→preview 的裸腿占比 = **57–73%**（968/1713 GFX、968/1325 Z8）；若把 30 平面链按 0.3–0.4 s 全算进去则 74–103%，但该链是推断值（见 §4 表注），不可当实测。

**判定**：
1. **批量粘贴本身不是长等待来源**（架构懒渲染合格；`SessionBatchApplier` 无 decode/pipe/Metal）。
2. **长等待只可能来自「每张首次全尺寸解码」**：首图上屏 1.82–2.40 s/张（Z8 45MP→7RM5 85MP→GFX 102MP，n=5/样张），其中 SPIKE 裸腿（decode+CI render）占 45–62%；强制全量缩略图刷新 10k = **1.4–2.4 h（线性模型：1–1.7 s/张 ÷ 2 并发）** → **解码器原因**（对 360 px 目标仍全尺寸 `decoder.decode`）。
3. **架构/代码原因（换解码器救不了）**：
   - 每次参数编辑 30 个平面全 miss（无部分缓存命中）：快拖 commit 0.41 s；慢拖松手后 ≈0.67 s。
   - 项目面编辑不失效/不刷新缩略图（pristine smart-preview 腿 + 源 mtime 判据）。
   - 项目面无批量粘贴路由（只有 legacy 面/MCP）。
4. 比例判断（用户裁定所需）：**打开成本里约一半是 SPIKE 裸腿（decode+CI render），另一半是产品自身的 30 平面链与装配；批量粘贴本身 ≈ 0 解码。** 结论不变但措辞按数据收窄：**「CIRAW 批量修图要长挂」不成立；成立的是「CIRAW 单张首次解码慢（打开 1.8–2.4 s/张）且缩略图腿也吃全尺寸解码」；产品另有一半打开成本可优化（30 平面链/装配），与解码器无关。**

## §5 与 SPIKE.md §4 对账（同文件、同口径）

| 指标 | SPIKE 裸腿 | 产品实测 | 差异 | 解释 |
|---|---|---|---|---|
| 冷开（85MP） | 968 ms（decode+CI render 2560，进程内一次，不物化 1840 输入平面） | 点击→preview 1.57 s；launch→首图 2.13 s | +62% / +120% | 产品多 30 平面 IOP（commit 实测 0.41 s）+ 编辑器装配 + overlay/scope；launch 另含 0.36 s 进程+窗口、0.55 s 到 grid |
| 热开 | 759 ms（同进程重开 + clearCaches） | 未取得 | — | 见 §0/§8 |
| 编辑（P0 CIRAW） | 738 ms（min 378 / p90 748；**retained decoded image → CIColorMatrix → render 2560**，无 IOP 链、无 1840 输入平面物化——`bench.swift:218-232` 实证，**不是** CIRAWFilter 写入曝光） | 快拖 live 0.11 / commit **0.41 s**；慢拖总 1.39 s，松手后 ≈0.67 s | 快拖 −44%；慢拖总 +88% | 差异来自**scale-at-entry + 输入平面缓存**（产品在 1840 物化一次并按 decode 哈希复用，下游 30 平面在 1840 跑；spike 没做这一层）。任务书对 P0 M2 的怀疑（CIRAWFilter 曝光伪值）**不成立**，但产品编辑确实更快（快拖） |
| 编辑（P1 已缓存 DNG） | 13 ms | 未取得（P1 非本 lane 对象） | — | 13 ms 是「CI 缓存平面 + 无 IOP 链」的专用腿；产品 30 平面链是 0.11–0.41 s，量级差 10–30×，不能互比 |

> 口径差异声明：SPIKE 的 M1 是「decode + 一次 CI render」的裸腿，不含 IOP 链、编辑器/项目面；本 lane 的 M1 是用户动作（双击照片）→ 视口可用。两者同文件同机，但包含物不同，表中给出包含物分解。

## §6 这个 App 做对了什么（懒在哪一层）+ 代码预判 vs 实测

### 6.1 预判（动手前读码结论）

1. **改一个参数是否重解码？不重解。** `PipeCoordinator.decoded: DecodedImage?` 在加载后常驻；`renderCurrentChainInner` 每次渲染都从同一个 `decoded.ciImage` 起链；`PixelPipe` 的输入平面（position 0）按 `decodeParamsHash`（`contentDedupeID ⊕ decodeParamsHash`）做键，参数编辑不改变 decode 哈希（`PixelPipe.swift:270-283, 707-730`；`LightamerCore/Sources/Pipe/PipeCache.swift` 的键语义）。→ **实测一致**：编辑日志无 decode，0.11–0.41 s；打开 1.3–1.7 s 含解码。
2. **批量粘贴是否逐张解码/渲染？没有。** `SessionBatchApplier` 头注 = 明确红线（无 decode leg、无 pipe 引用、无 Metal 类型）；段 1 读 `.lra` + compose，段 2 单事务 claim（`dirty=1`、`thumb stale`），段 3 后台串行写。GUI 的 `pasteToSelection` 与 MCP `paste_adjustments` 都走它。→ **实测一致**（拒付路径 6 ms；无渲染）。**但路由缺口**：默认项目面没有把格子选择接到批量粘贴，只有 legacy 会话面/MCP 能批量。
3. **粘贴后缩略图怎么失效/重建？** legacy 面：claim txn 标 stale，**只失效不重渲**；重建 = `SessionThumbnailProvider` 队列（2 并发、可见优先、非可见 1.5 s idle），tier B = 完整 `RAWDecoder.decode` + PixelPipe@360 + 写盘（`SessionThumbnailProvider.swift` 头注 + `buildRenderRequest`）。项目面：`LibraryThumbnailBridge` 的新鲜度 = **源文件 mtime**，渲染腿 = `SmartPreviewStore` 的 **pristine** decode（源码注释自述「sidecar-develop materialize 是 P2」）→ 编辑/粘贴**不会**触发缩略图失效。→ **代码预判与实测一致**（项目面看不到批量结果；legacy 面按需重建）。
4. 额外发现：编辑提交后 PREVIEW 日志统计恒为 `0 hits / 30 misses`（从曝光模块往下 30 平面全部重算）——说明链上缓存对参数编辑的作用仅限于「输入平面/未受影响前缀」，实际每次编辑都付全链。

### 6.2 这个 App 做对了什么

- **懒在粘贴层**：粘贴不碰像素（sidecar-only），批量 1,000 的返回是 index+compose，不是 1,000 次渲染——与 darktable 的 `_control_paste_history_job_run` 同构。
- **懒在缩略图层**：stale 只标记，队列按需；可见格优先、非可见 idle；并发 2（不让解码饿死编辑器）。
- **懒在编辑层**：解码结果与输入平面按 decode 哈希缓存，改参数不重解 RAW。
- **没有做的**（架构/代码原因，须另立）：
  - 缩略图 tier B 对 360 px 目标做**全尺寸解码**（解码器成本放大器）。
  - 项目面无批量粘贴路由、无编辑失效缩略图。
  - 参数编辑从曝光往下全链重跑（30 平面）。

## §7 删除清单

- `$G/lightamer/` 全删（`apps/Lightamer.app` 583 MB + 10,000 硬链接 + 隔离 HOME 的 `Library.lalb`/缓存 + frames 存证帧 + dl）。为补测 M3 曾重建一次沙箱（app + 10k 硬链接）并再次全删；最终 `$G` 只剩 `_frames/`、`_harness/`、`_launchcheck/`。
- `$G/_harness/` 保留（前一 lane 建的共享脚手架，本 lane 只新增 `lm.py`/`m1_log.py`/`m1m2.py`/`mcp.py`/`batch_mcp.py` + 修 `m1m2.py` 自身，未改 `cap.py`/`input.py`）。
- 进程：本 lane 启动的 Lightamer 全部退出（`pgrep -f lightamer/apps/Lightamer.app` = none）。
- 偏好：`com.kamasylvia.lightamer` 的键全部清除（`defaults delete` + 删 plist）。补测的 legacy 启动又写入了 `NSWindow Frame LightamerMainWindow`（HOME 隔离挡不住 cfprefsd），已再次 `defaults delete` + 删 plist；最终 `defaults read` = **Domain not found**、plist 不存在。
- 真实 `~/Library/Application Support/Lightamer/Library.lalb`：mtime 1793619957 未变（我们所有测量都在隔离 HOME；唯一触碰来自仓库 release 脚本自带的 direct-launch probe，00:05 打开过该库，`.lock`/`-shm` mtime 更新，主库未写）。
- **清理错误（如实登记）**：`$G/lightamer/snap/` 的 `~/Library` 顶层 before 快照被我在运行审计**之前**随 `$G/lightamer` 一并删除 → 无法完成「运行前不存在条目」的逐条比对。现存 `Application Support/com.kamasylvia.lightamer`、`Caches/com.kamasylvia.lightamer`、`Containers/com.kamasylvia.lightamer.{quicklook,spotlight,uitests.xctrunner}`、`HTTPStorages/com.kamasylvia.lightamer` **未动**（无运行前记录，按规则不删；多为系统对既有 App 的容器/缓存，早于本 lane 的可能性高）。
- `df -h /` 删除后：38 GB avail（84%）。

## §8 风险与未验项

1. **M1 热未取得**（脚本缺陷；两行非空值已按 §0 归因并弃用；CSV 是原始输出、未加标注）。
2. **M2 只有 2 rep**；形态（快拖 0.11/0.41 s、慢拖 0.23/1.39 s）足够定性，但不足以给 p90。
3. **M3 全部未实测**（M3a/M3b/M3c）：已定位为**会话索引渐进**——10,000 张目录会话在 20.9 s 时只暴露了部分成员（`img_00002` 可用），40 s 时 `img_00004` 仍不可用；随后 MCP 会话数触顶 503。**10k 会话的完整索引时间未测到**（>40 s，可能数分钟）。下一轮第一优先 = 等索引完成后重测 10/100/1000，并单测 tier-B 缩略图。
4. **项目面导入 10,000 张未试**（时间预算）；导入成本与首次缩略图成本未测。
5. **编辑器默认 armed 蒙版工具**：打开图片即出现蒙版工具条与全幅渐变手柄/网格（会话 UI 状态），对渲染成本与用户观感有影响；本 lane 未量化，也未确认是否属预期。
6. ~~慢拖 live 第一帧可能不改变可见像素~~ **撤回**：`trial.json` 的 CSV 中，早期帧 `diff_prev` 0.049–0.054 已显著高于稳定噪声 0.001–0.016，且 cap 原点比 input 晚 0.218 s——1.61/2.12 s 与日志 1.39/1.90 s 是同一事件的两个原点，不存在「live 不可见」。live 的「0 平面」是统计面（下游平面计数），不表示无像素更新。
7. 真实 HOME 被仓库脚本 probe 触碰一次（00:05）；数据未变，但隔离流里该脚本环节是漏洞。
8. 预算超时：墙钟约 2 h（含 10 分钟构建与 2 次 UI 探索）；M3 与 M1 热的欠账是超时直接后果。
9. **文本存证缺口**：`$G/lightamer/run.log`（含 M2 的 0.11/0.23/0.41/1.39 s 与 `0 hits/30 misses`）随沙箱删除；这些日志数字只能按本报告引用与代码行为复核，无法独立复算。

## §9 issue #26 评论草稿

> **GUI timing — Lightamer (CIRAW, HEAD beaac01, Release adhoc)**
> - Cold open (launch → first image ready, n=5): **7RM5 2.13 s / GFX100S 2.40 s / Z8 1.82 s**. Click → preview alone: 1.57 / 1.71 / 1.33 s. Components: launch→window 0.36–0.37 s, launch→grid 0.52–0.55 s; the decode+CI-render leg is **45–62%** of the open.
> - Edit (exposure drag): fast drag live 0.11 s / commit **0.41 s** (−44% vs spike 738 ms); slow drag total 1.39 s (+88%), ≈0.67 s after release. Every edit re-runs **30 planes (0 hits/30 misses)**. The spike's P0 738 ms is retained-decoded-image → CIColorMatrix → 2560 render (no IOP chain, no preview-sized input plane) — **not** a CIRAWFilter-exposure artifact; the product's win is scale-at-entry + input-plane cache.
> - Batch paste is **sidecar-only** (`SessionBatchApplier`: no decode, no pipe, no Metal; 1 txn + background sidecar writes). Measured `paste_adjustments` rejection path = 6–103 ms. **No M3a/M3b numbers** (session index progressive + MCP session cap 4 → 503).
> - **Verdict:** the CIRAW path does **not** require long hangs for batch paste. The long-wait risk is per-image first decode (1.3–2.1 s per 85–102 MP) and is **decoder-bound** — full-size decode even for 360 px thumbnails (forced 10k refresh ≈ 1.4–2.4 h at concurrency 2). Two architecture gaps independent of the decoder: **no batch-paste routing in the default project face**, and **edits never stale/refresh project-face thumbnails** (pristine smart-preview leg + source-mtime freshness).
> - Unverified: M1 hot (script defect), M2 n=2, **all of M3 unmeasured** (10k session index is progressive: img_00002 member at 20.9 s, img_00004 still missing at 40 s; MCP session cap 4 → 503); see `GUI-lightamer.md` §8.
