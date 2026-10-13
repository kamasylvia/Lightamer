# M5-3-03 二次验收报告（omp 路，独立第二遍）

> 验收员 = omp（无头 CLI 二次验收）；工作目录 = `/Volumes/UNITEK/Documents/Development/Lightamer`。
> 首验 = zcode（`M5-3-03-ACCEPTANCE.md` §一..§十）：**PASS / 0 error + 1 minor（已更正）+ 3 观察**。
> 本报告五步全部独立执行（亲读 + 亲跑 + 实机 + 读码 + 机检），不复述首验结论；分歧点见 §6。

# PASS / 0 error + 1 minor + 3 obs（omp 路；与首验零实质分歧）

minor-1 = 实机 typed FAIL toast 未能屏上取证（4s auto-clear 窗 + 12 分钟轮询 AX 零命中 + 两 instance 均只见 `就绪`；映射语义由测试三臂 + AX 文案锚 + log 原文三方闭合——机制置信高，屏上像素置信缺，记 minor 不阻断）。
obs o-omp1/o-omp2/o-omp3 = 批外观察（下详），零动作。

---

## §1 首读验收正本（任务指令文档六件）

| 文档 | 结论 |
|---|---|
| `M5-3-03-ACCEPTANCE.md`（§一..§十） | 首验 PASS / 0E+1minor（m-1 SC 锚 88/93→85/90 已更正）+ 3 观察；全套亲跑 3631/24/0 exit 0 逐位；十一项 G5 全绿；commit 边界四提交干净 |
| `M5-3-03-DECISIONS.md` | checker 五项分账（①本批 / ②④⑤前批已落 / ③转写残迹）+ 政策 B 磁盘产物 + typed 双层拆分 + G4 5.0 绑定收缩改活体形 + G5 十一项 + 桩腿 2N+5 |
| `M5-3-VALIDATION.md`（drafted） | 七门：G1/G2/G3/G4/G5/预算 ✅，G6 ⏳（Manual-Only 待排）；对账链 3539→3582→3626→3631；m-1 更正已落盘（`cb3915e6` diff 亲见） |
| `M5-3-03-PLAN.md` | checker 回注 ①-⑤：①ContentView 补登记（front-matter :13 亲见）②双缝 ③+32 ④6 行 ⑤02 口径——分账见 §5 |
| `.work/gui-acceptance/m5-3/MANIFEST.md` | G6 五行配方 + fixture 注记 + Manual-Only 依据；M3-4 先例措辞同构 |
| `g5-redline-checks.txt` + SUMMARY | transcript 十一项 + 收口轮数字源 |

首验 m-1 更正复核：十文件集 `grep -c 'func test'` 亲算 = 9+9+7+8+13+10+5+12+5+7 = **85** ✅（Gain 13/Leg 12 与 02-ACCEPTANCE m-a 同值）；VALIDATION 现盘锚「85 法 + MergeUI 5 = 90 法」✅。

## §2 定向复跑对表（`Scripts/test-direct.sh --bundle App`）

亲跑命令：`caffeinate -dis Scripts/test-direct.sh --bundle App`（直启宿主）。

| bundle | omp 亲跑 | 申报/首验 | 对表 |
|---|---|---|---|
| App | **757/4/0**（428s，peakRSS 2832MB） | 757/4/0（366s/2832MB） | ✅ 逐位（含 peakRSS 逐位） |

- 尾行 `OK (direct launch, no testmanagerd)` 亲见；零 MEMFAIL / 零 crash / exit 0。
- `PanoMergeUITests` 5 法 log 逐条亲读 **5/5 passed**（seam nil 门 / 参数映射+defaultTag / 三前缀正反+透传 / 消费面替换+不漏英文 / sibling 共存）。
- skip 4 身份亲读 = DepthGoldenTests ×3 + DepthPerfProbeTests ×1（资产/探针门，与首验 §一分类一致——App 束内 M5-1 在册 4 法）。
- 耗时差 428s vs 366s = 机器负载方差（测试宿主与 GUI/巡检同机），非回归。

## §3 实机验证（DerivedData Debug 构建，Session 面端到端）

环境：`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Debug/Lightamer.app`（二进制 mtime 10-13 06:42 = T2 `2d57bc37` 代码态 build；其后 commit 纯 docs/.work——首验新鲜度链复用成立）；`LIGHTAMER_LEGACY_LIBRARY=1` 进 Session 面；素材 `/tmp/omp-pano-sess/`（A/B.ARW 同源对，M5-2 omp 素材复用）；证据 `.work/gui-acceptance/m5-3/omp-g6/`（政策 B 忽略路径，未入仓）。

- **G6 行 1 前段 ✅**：⌘A 双选 → 右键菜单 **13 项亲见**（`m5-3-g6-1-menu.png`）——复制/粘贴组 3（灰）+ 旗标组 3 + 关键词/备注组 2 + merge 组 **HDR 合并… / HDR 合并（Mertens 快速）/ 全景合成 / 焦点堆栈… / 堆栈降噪…** ✅（第三项落位与代码 :184-194 一致）。
- **简形 sheet ✅**：`m5-3-g6-1-sheet.png` + AX 树逐字锚：标题 `全景合成` + 正文 `选择同一视点、重叠约 30% 以上的照片；画布上限 2 亿像素，超限自动等比缩小；结果恒自动裁去无效边缘。`（四生效值逐字 = 键值 + plan KD-1 文案）+ 按钮 `取消`/`开始合成`；sheet AX 子树 = 2 static text + 2 button，**零档位控件** ✅。
- **enqueue 接线 ✅**：开始合成 → toast `全景合成已加入队列` 亲见（`m5-3-g6-1-queued.png`，`toast_pano_queued` zh 值逐字）✅。
- **生产腿真跑 ✅**：`sample` 亲见 `runPanoLeg → PanoFeature.detectAndDescribe → buildPyramid → blur` 热栈（StackMergeService.swift:974 / PanoFeature.swift:353/251/305——与腿体源码行号一致）✅；job 约 120s 后 FAIL（见下）。
- **typed 失败面（半亲证 → minor-1）**：同源复制对零视差 → 匹配链零有效边 → `medianFocal([])` = nil → log 原文 `stack merge job failed: Invalid setting: panorama alignment failed: no image pair carries focal information`（三 instance 逐字同，`FailurePrefix.alignment` canonical 前缀亲证 ✅）。FAIL toast 屏上取证失败：toast 4s auto-clear（`EditorState.presentToast` :67-75 源码）+ 事后轮询 AX 12 分钟零命中 + 两轮截图均只见 `就绪`。映射语义闭合链：`failureMessage` 三臂测试（空 detail/有 detail/透传）✅ + AX 键值锚（三 error 键 zh 值亲读 §4）+ log canonical 前缀 ✅ + `toast_hdr_merge_failed %@` 模板 `HDR 合并失败：%@` ✅ → 预期屏显 = `HDR 合并失败：全景对齐失败：no image pair carries focal information`，英文短语不漏出机理由测试 `XCTAssertFalse(contains(prefix))` 钉死。缺的一环仅屏上像素——记 minor-1，不阻断。
- **资源**：实机全程 RSS 1.4-2.1GB / CPU 闲时 <1% / 跑腿时满核；零崩溃（DiagnosticReports 无新 .ips）；`MDB_MAP_FULL`（Metal shader 缓存）与 CoreSpotlight/XPC 错误各一例 = 环境噪音（o-omp3）。
- **G6 行 2/3/5 未执行**：需成功产物（同视点扫幅样张缺如——MANIFEST 已登记 fixture 注记）；行 4 部分（log 面 ✅ / 屏面 minor-1）。G6 行整体仍 ⏳ 待排，与 VALIDATION 登记一致。

实机方法论副产品（供后用）：Retina 2x 下 cliclick 用逻辑点（截图物理像素 ÷2）；SwiftUI tap 手势修饰键走 `NSEvent.modifierFlags`——cliclick `kd:cmd` 压不住，必须 osascript `key down command`；单选后 ⌘-点加选有效，shift 范围选中 cliclick 修饰键丢失恒退化为单选。

## §4 读码抽查（行号锚）

- **typed 三态**（`LightamerApp.swift:71-121`）：`failureKey` = 纯前缀表（消费 `PanoMatch.FailurePrefix` 三常量，零第二词汇源 ✅）；`failureMessage` = 显式 switch 返回静态键（三臂 + default 透传，V14 纪律 ✅）；detail 从 prefix `upperBound` 起取 → AppError 样板头自然剥除 ✅；非前缀逐字节透传（`guard let key ... else return raw`）✅。Core 侧 `PanoMatch.swift:127-130` 三常量带 `": "` 尾 ✅。
- **seam 孪生形**：`SessionCoordinator.swift:132 panoMergeHandler`（doc 注 `mertensMergeHandler twin`）vs `:138 mertensMergeHandler`——签名同形 ✅；`SessionBrowserView.swift:69 onPano` optional（nil=隐藏）✅；菜单 gate `targets.count >= 2, onPano != nil`（:186）+ Divider 链 `onHDRMerge == nil, onHDRMertens == nil`（:187）= mertens 项同构语义 ✅。
- **ContentView 穿线第四段**（`:467-471`）：`onPano: { Task { await sessionCoordinator.panoMergeHandler?(relPaths) } }`——mertens 段（:462-465）同位 ✅；checker minor-1 兑现 + plan front-matter 补登记 ✅。
- **enqueue 面**（`LightamerApp.swift:1019-1038`）：`kind: .pano` + `MergeParams(deGhost: false, tag: nil)` 显式形 + 注释言明腿不消费 + `toast_pano_queued` ✅；`defaultTag(.pano) = "pano"`（`StackMergeService.swift:637`）+ 落盘 `tag ?? defaultTag`（:2603）→ `_pano` 分账 ✅；`stepTotal .pano = 3N+6`（:618-619）与桩腿 2N+5 恒式分解一致 ✅。
- **测试面**：`PanoMergeUITests` 5 法——seam nil 门 / handler 参数映射（work.kind/deGhost/tag 三断言）/ 前缀表 10 案例正反（含空串）/ 消费面三臂（透传恒等/detail 保留+英文不漏/裸形态）/ sibling 共存（KindLog 双 kind 集断言）。mertens 桩 bump = 4N+2 vs 先例 3N+2（首验 o-2）：超步 N 步纯 cosmetic，复核同意（progress 显示面，`.done` 由腿返回决定）。
- **8 键值亲读**（xcstrings JSON 直读）：menu/title/body/start/toast 三 error 键 en+zh 双语全 translated；body 四生效值逐字；error 键 zh = 全景对齐失败 / 全景照片不连通（重叠不足）/ 全景画布无效 ✅。

## §5 红线机检（base `60aad61f`，亲跑）

| # | 项 | 亲跑结果 | 判定 |
|---|---|---|---|
| 1 | `LightamerIOP/ + LightamerCore/` 全域零 diff | 0 行 | ✅ |
| 2 | `*.metal` 新增/修改 | 0 文件 | ✅ |
| 3 | `Project.swift` dependencies/package/product | 0 diff（唯一 diff = PanoMergeUITests 登记 1 行 :832） | ✅ |
| 4 | `StackMergeService/BandStreamer/ProvenanceReplay` | ⊂ §1 全域 0 行 | ✅ |
| 5 | 禁系统随机源 hardened 门（含 `\.random\(`，pano face 五文件） | 0 命中 | ✅ |
| 6 | `runModal`（App/Sources） | 0 命中 | ✅ |
| 7 | `LocalizationValue("…")` 插值禁形 | 2 命中 = M2-9-05 既有修复形（ExportInspectorView:392，base..HEAD 0 行）+ :1921 文档注释；**零新增** | ✅（首验 o-1 复核同意） |
| 8 | sidecar schemaVersion | ⊂ §1 全域 0 行 | ✅ |
| 9 | xcstrings 纯插入 | 136/0（8 键尾块，`toast_hdr_mertens_queued` 后） | ✅ |
| 10 | SessionBrowserView 0 deletions | 49+/0-；前两项/focus/stack 字节不动 | ✅ |
| 11 | `zh-audit --check` | **PASS (1651 source keys, 1890 catalog keys, zh complete)** 亲跑复现 | ✅ |
| 12 | 全窗 diff | 1071+/3-（3 删除 = toast 改线 1 + cb3915e6 验收注记 2 行改写；产品面删除仅 T2 正当改线 1 行） | ✅ |

- checker 五项分账复核：①ContentView→T1 ✅ ②双缝→01/02（`preparePreviewGray` 双缝在 01-SUMMARY 亲见引用）✅ ③「+32」CHECKER/plan 全文零命中（首验 grep 复跑结论复用——本轮未重跑 grep，记复用项）④6 行→01-SUMMARY ✅ ⑤02 口径→BUNDLE-MAP 记录块 ✅。
- G4 独立复跑：同脚本仓外 `uv run`（opencv 5.0.0）→ 输出与 `probe-output.txt` **逐位一致**（`diff` 空）✅；G4-BITIDENTICAL。源码树 opencv 命中 = 头注/`cv2.setRNGSeed` 注记（PanoMatch.swift:17/87 亲读两例为注释），零代码 ✅。政策 B：`git check-ignore` 双路径 IGNORED-OK ✅。
- BUNDLE-MAP：`APP 5 PanoMergeUITests.swift` 增行 ✅；`tuist generate` 时间链（pbxproj < 二进制 < commit）首验已亲证，本轮复用。

## §6 与首验分歧点 + 本路 minor/obs

**零实质分歧**。首验 1 minor（m-1）复算确认已更正；首验 o-1（ExportInspectorView:392 既有形）/ o-2（4N+2 cosmetic）/ o-3（skip 归类 ±1）三观察复核全部同意。

- **minor-1（本路新记，不阻断）**：实机 FAIL toast 屏上像素未取证（§3 机理详）。去向：G6 行 4 屏面仍挂 MANIFEST 待排；映射语义三方闭合已足够签核本批（UI 接线批，非腿体批）。
- **o-omp1（观察，批外）**：同源复制对（零视差）FAIL 路径 = alignment 臂（`medianFocal` nil）先于 disconnected 臂——guard 序（:1035 先于 :1040）决定。MANIFEST 行 4 配方「两张无重叠样张 → disconnected」不受影响（真无重叠对走 RANSAC 全败 → 同 alignment 臂？或部分边存活 → disconnected 臂——取决于样张；配方断言「disconnected zh 文案」对真无重叠对成立当且仅当至少一边过门。建议 G6 执行时若落 alignment 臂亦接受（同为 typed 三态诚实面），不视为配方失败。
- **o-omp2（观察，批外）**：误触焦点堆栈 sheet 标题 `焦点堆栈 0 张源图`——双选态下源图计数 0（08-3 T4 面，疑 pendingTargets 捕获时序或计数源与 selection 脱节）。本批零触碰（08-3 面），登记供 focus-stack 批回看。
- **o-omp3（观察，环境）**：`MDB_MAP_FULL`（Metal mdb）+ CoreSpotlight/XPC 中断噪音各一例；L057-B 同族崩溃本轮零撞见。

## §7 结论

批内 plan AC 全达成（菜单第三项 + 简形 sheet 零控件 + seam 四段 + enqueue `.pano` + typed 三态 zh + zh 八键 + G4/G5/G6 + VALIDATION drafted），红线机检十二项全零/全绿，App 定向复跑 757/4/0 逐位闭合，实机端到端取证（菜单/sheet/toast/生产腿热栈/typed canonical log），与首验零实质分歧。本路 1 minor 为屏上像素置信缺（语义已三方闭合），3 obs 均为批外/环境。**omp 路结论：PASS。**

*（报告人：omp 二次验收；证据：§2 App 亲跑日志 + §3 三截图与 sample/log + §4 行号锚 + §5 机检输出 + G4 独立复跑 diff 空；工作区残留：`/tmp/omp-pano-sess/`、`/tmp/omp-pano-*.png`、`/tmp/omp-pano-sample*.txt`、`.work/gui-acceptance/m5-3/omp-g6/` 三截图——留置备查，未入仓。）*
