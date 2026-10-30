# R7-ACCEPTANCE-OMP — omp 独立终审（实机走查 + 修复验证 + 对账）

> 审期：2026-10-31 05:06 → 06:10。对象 = 五 commits `838314b2`/`8211b86f`/`edd66755`/`082178f2`/`236cd50b`
> （refs #15）+ 验收 `53dfac7e`（路 PASS/0B+0M+1m+3obs，全套 4435/34/0 复跑同值）。
> 方法：Debug 实机构建自证 → 自编 AX 工具链（`axdump`/`axpos`/`axbtn`/`axradio`/`axslider`/`axpopup`/`axmenu`/`axframe`）
> + cliclick 真实坐标拖拽 + screencapture + sidecar verbatim 直读 + 基线 worktree 对照构建。
> 全程单 GUI 占用；零源码改动。

## 结论头

**CONDITIONAL PASS / 1 error（E-1：几何编辑即崩，R7 外既有缺陷）+ 0 major + 1 minor（m-1 对账确认）+ 4 obs**

| 终审面 | 判定 |
|---|---|
| 1. T1 端点拖拽提交（含 quit 加严腿） | **PASS**（§一） |
| 2. T2 flip+crop+角度联动 | **BLOCKED by E-1**（§二；回归逻辑未被证伪，转源码级条件通过） |
| 3. T3 DRT 两裁决 | **PASS**（§三；peak 100 + 方法联动 + HDR seed 1000 三重实证） |
| 4. T4 抽验（cap toast / paste 活引用 / paper 清键） | **PASS（1 实机 + 2 源码复核）**（§四） |
| 5. 对账（m-1 + observer 三件） | 逐条评（§五） |

**签核意见**：R7 修复批本身验收通过——T1 实机闭环；T2 的转置语义经数学复核 + 回归可证伪双承载，
实机阻塞是基线既有的几何链崩溃（E-1），非 R7 回归；T3/T4 裁决复核成立。E-1 建议单独立项（error 级，
阻塞一切几何编辑实机面），不与 R7 签核挂钩。

---

## 环境与卫生

- **构建自证**：`xcodebuild build`（workspace/scheme Lightamer，Debug，
  `-disableAutomaticPackageResolution` 离线）**BUILD SUCCEEDED**（`omp-evidence/build.log`）；
  binary mtime **05:11:25 晚于** `236cd50b`（03:27:08）与验收 `53dfac7e`（05:02:43）。
  基线对照：worktree `f783f1c3` + `tuist generate` + 同参数 → **BUILD SUCCEEDED**
  （容器 `Lightamer-r7baseline`，05:29:01；worktree 已拆除）。
- **机器纪律**：`machine-guard.sh` 首判 **BLOCK G4**（Data 15233MB<25GB，清可再生面无大项可清：
  唯一 DerivedData 1.7G 系全套/构建前提）→ 按 §9 先例**透明越门**（G1 heavy=0 / G2 free 78% /
  无 swap 压力）；`--monitor 10800` 全程伴跑（`omp-evidence/monitor.log`），**零 RSS-KILL**；
  GUI 单实例串行走查（多实例交替出现均为前序 crash 后的干净重起，`ps` 亲核同时只存活一个）。
- **收工**：GUI 已 quit（末实例 crash 后无残留，`pgrep` 零命中）；`defaults` 读检查（探针污染
  `library.recentProjects` 若存则清）；tracked **零 diff**；证据全在 `omp-evidence/`；
  走查文件全在 `/tmp/r7walk/`（不入库；用户实拍仅作只读拷贝源）。
- **供件**：扫街 Capture `DSC09981/ Thi9994.ARW`（只读拷贝为 r7-a/r7-b）+ stock TIFF
  （`srgb-matrix-8`/`pq-cicp-16`）。未触个人肖像目录。

## 一、T1 端点拖拽提交 — PASS

**判据**：Guided 画线 → 拖端点 → 松手 → sidecar/history **立即**落盘 → quit 加严 → 重开位移存活。

| 步 | 实测 |
|---|---|
| 画线 | 多 tick 拖拽（`dd/dm×4/du`，单 tick 合成在 minimumDistance=1 下不可靠，见 §六.1）→ 面板「导线：1」+ 落 `Upright 导线` item，guides=`[{ax:0.2953, ay:0.3116, bx:0.2953, by:0.6306}]` |
| 拖端点 | b 端 (560,540)→(720,540) 多 tick 拖 → **items 3→4**，新 `Upright 导线` item `bx=0.5080`（位移 +0.2126），ax/ay/by 逐值不动（`t1-after-drag.lra.json`） |
| 加严 quit | 拖完**零后续操作**直接 quit → sidecar items 4/position 3 原样在盘 |
| 重开 | 新实例开同图 → 面板「导线：1」，末 item guides 与拖后逐值相同（`t1-relaunch-survived.png`） |

→ R7 T1 的「对称臂 + dragMoved 门」在真交互下成立：端点拖拽 release 即提交，拖完即关图不再丢失，
且 undo 有该步（items+1）。M9-3 N-1 关闭。

注：首轮单 tick 合成拖拽曾落「面板 1 / sidecar 空 guides」的 live-only 幻影（`Upright 导线` 空 item），
系合成输入伪影（press 即 release，pending 零长度门按设计拒收）+ live 读数污染，非产品缺陷——多 tick
真拖拽下画线/端点两臂均正常提交（§六.1）。

## 二、T2 flip+crop+角度联动 — BLOCKED（E-1 既有崩溃）

### E-1（error）：几何编辑即崩 — `negotiated ROI violated at pos 0`

**实测矩阵**（全部 `PixelPipe.swift:1676` precondition，HEAD + 基线双测）：

| # | 二进制 | 动作 | 结果 |
|---|---|---|---|
| 1 | HEAD | pristine RAW 上 CW90（tool strip） | **崩**：roiOut=1840x1227 neg=1840x1227 upstream=**1227x1840**（转置整面，未 clamp） |
| 2 | HEAD | CCW90 | **崩**：同签名 |
| 3 | 基线 `f783f1c3` | rotCW90（flip 面板 popup） | **崩**：同签名 → **R7 外既有缺陷**，非 R7 回归 |
| 4 | HEAD | rot180（存活，orientation=3 落盘）+ crop.left=0.1 | **崩**：upstream=**1656x1227**=1840×0.9（crop 窗被当整面渲染） |
| 5 | HEAD | crop-only left=0.1（flip=none） | **崩**：同 #4 签名 → 连纯 crop 都崩 |
| 6 | HEAD | crop-only left=0.05 | **崩**：upstream=**1748x1227**=1840×0.95（线性跟随，判别充分） |
| 对照 | HEAD | tint 滑杆点值提交 | **存活**（pointwise 面正常） |
| 对照 | HEAD/基线 | flipV / rot180 提交 | **存活**（sidecar 落盘，渲染不崩） |

证据：`t2-crash-*.ips` 六份（HEAD CW/CCW/rot180-crop/croponly/crop5pct + 基线 rot90）。

**根因（源码亲核，未改码）**：崩溃点是 pos 0（temperature，恒等 ROI）的 miss 闭包——上游 base case
返回的平面 ≠ 协商 ROI。两条崩溃腿语义不同：

1. **SWAP_XY 腿**（#1-3）：flip `modifyROIIn` 用 `swapped(dscIn)` 作输出 dims 反算角点——测试面
   （`FlipParityTests`）喂的是**翻转后 dims**的 roi（32×64 对 64×32 输入），恒自洽；但实机 preview
   链在某处把**未翻转 dims**（1840×1227）当作 flip 的输出 roi 传进来，反算角点越界（独立复算：
   (1839,0)→(0,−613)），clamp 后仍与 base case 的转置整面（1227×1840）对不上 → precondition。
   即：**forward walk 与 backward 协商对 flip 输出帧的 dims 理解不一致**（或某一恒等模块截断了
   转置传播），与 R7 T2 的 crop 记录域转置无关（R7 只动 `CropToolRotation.linkedSnapshots` 的
   参数面，不动 pipe ROI 协商）。
2. **crop 腿**（#4-6）：base case 按协商 roiIn（crop 窗，如 1748×1227）渲染了输入子域，但 pos 0
   的 miss 闭包断言的是**整面**（negotiatedIn=1840×1227）——协商链上 crop 的收缩在到达 pos 0
   之前被某恒等环节丢弃（negotiatedIn 回到整面），而 base case 却收到了收缩后的 roi。
   upstream 随 crop 分数线性跟随（0.9→1656，0.95→1748）证明收缩确实发生了，只是协商两端对不上。

共同点：**恒等 ROI 模块链（temperature/denoise 等 pos 0 附近）在几何收缩/转置下的协商传递断裂**，
与 R7 T2 的改动面（`CropToolRotation.swift` + 三处 `flip:` 传参）零交集——基线同崩是决定性证据。

**对 T2 验收的影响**：R7 T2 的修复语义（桥 I/O 按 swapsXY 转置 + 镜像抵消）经 zcode 验收数学独立
复核成立 + 反自取消探针真红（掏空转置 → 4 法红，漂移 4-5%），**逻辑面不被 E-1 触及**——E-1 杀的是
渲染提交后的 preview 重算，不是漏斗的参数计算。本终审给 T2 **条件通过**：转置语义成立，
实机联动面待 E-1 修复后补走查。E-1 单独立项（error 级：阻塞一切几何编辑实机面——flip90/crop/角度
联动全不可用；tint 等 pointwise 编辑不受影响）。

## 三、T3 DRT 两裁决 — PASS（三重实证）

| 裁决 | 实测 | 判定 |
|---|---|---|
| **obs-4：峰值初值 = record 语义值（按设计）** | pristine RAW（r7-a.ARW）DRT 页首显 = **100 nits**（`t3-pristine-peak100.png`）；SDR raster 首显 100（= `sdrPeakNits`）；**HDR raster**（pq-cicp-16）首显 = **1000 nits** + 方法 aces_2_0 + 限色空间（`t3-hdr-seed1000.png`，= PQ peak ladder `mDCv→MaxCLL→1000` 默认档） | PASS：400/100/1000 都是 seed 说话，读链无面板局部默认 |
| **m-1b：方法切换联动（真交互）** | OpenDRT→ACES 2.0：sections Look/Tonescale/Creative White → **限色空间**（`t3-aces-sections.png`）；切回：sections 复原；sidecar 落 2×「切换显示变换方法」（method aces_2_0→open_drt，逐值在盘） | PASS：真 press 下 binding→commit→@Observable→重读全链正常，m-1b 的 AX 合成伪影定性成立 |

注：HDR seed 实测 1000 而非 R6-R1 的 400——两者都是「文件 mastering 峰」语义的不同取值
（本轮 stock 件无 mDCv/MaxCLL → 落 1000 默认档），恰证明「初值 = record 语义值」的裁决与具体数字无关。

## 四、T4 抽验 — PASS（1 实机 + 2 源码复核）

| 件 | 实测 | 判定 |
|---|---|---|
| **第 5 条导线拒 + toast** | 导线：4 后再画 → 仍 4 + `status_toast` = **「已达导线上限——最多四条。」**（`t4-cap-toast.png`） | PASS（实机） |
| **paste AI 蒙版活引用** | transfer dialog 实机开启（`t4-transfer-dialog.png`）；AI bake 三次零落盘（选择门 + 多实例 picker 未现 + 无 toast/无 `.masks`，§六.3）→ 同源再 paste 未能实机闭环。**源码复核成立**：`pasteChain` 先 `captureActiveChain`（`VersionCoordinator.swift:289→:410-415`，live history 值拷贝进 slot）再装新链；清扫 chains = `[history]+slots`（`AdjustmentTransferView.swift:308-309`）含捕获链 → 同图 paste 时 `removeAssetIfUnreferenced` 恒 no-op，文件保留；真死引用（mask 移除/版本删除后的后续 paste）由引用门自然放行 | PASS（源码复核 + dialog 实机 + 全套 `AdjustmentTransferTests` 10/0/0） |
| **setPaperStock 回 None/默认 → grade 键清** | 两次 nodes 面板导航期 NSGenericException 崩（`NSSplitViewItem _setCollapsed` 路径，`t4-crash-layout-*.ips`，§六.4）→ 面板点击未达。**源码复核成立**：`setPaperStock` 同一 commit 内 `gradedBW` 不成立 → `record.paperGrade = nil`（`FilmPanelModel.swift:336-348`）；回归 `testPaperSwitchClearsGradeOnlyOnNonGradedPaper`（graded BW 保留 / 色纸清除 / items+1 / landed nil）全套绿 | PASS（源码复核 + 回归绿） |

## 五、对账

| 项 | 复核 | 路由 |
|---|---|---|
| **m-1（minor）BUNDLE-MAP 两行滞后** | **成立**：MAP:238 `DrtPanelModelTests`=11 vs 文件实测 **13 法**；MAP:327 `AdjustmentTransferTests`=9 vs 文件 **10 法**；git 基线 `f783f1c3` 两行 = 9/8；R7 增行注记（939-942）写「9→11/8→9」= 在旧账上 +Δ 继承滞后。验收 §九的计数（基线 11/9、HEAD 13/10）逐值吻合 | 下批把两行勘正为 13/10 并行尾注记勘误；ΔN 总账 +7 与 4435 不受影响 |
| obs-1（转置「逐字节」措辞） | 成立，零动作（几何恒等声明，1e-6 闭式钉死） | 无 |
| obs-2（MCP/外部源不扫） | 成立，零动作（归 M11/M12 reachability collector） | 无 |
| obs-3（AX 合成伪影族） | 成立，零动作（走查配方课题；本轮 T3 方法切换走真 press 通道，恰避开该伪影） | 无 |
| observer 三件 | 维持纯观察，本批零动作（与 DECISIONS §3 尾一致；本轮未触达其面） | 无 |

## 六、局限与透明度（合成输入；不冒充产品结论）

1. **单 tick 合成拖拽在导线 overlay 上不可靠**：`cliclick dd/du` 一步拖在 `DragGesture(minimumDistance: 1)`
   下常只产生 press 即 release（pending 零长度门按设计拒收），面板 live 读数可短暂显示幻影值。
   本轮一切拖拽结论（T1 画线/端点、T4 cap）均以**多 tick 慢拖**（`dd/dm×3-4/du`）+ sidecar 落盘为准，
   不采信纯面板读数。
2. **E-1 的根因定位是源码亲核 + 黑盒判别**，未单步调试 pipe 协商链——forward/backward 不一致的
   精确断裂点（恒等模块截断 vs entry 缩放帧混淆）需立项后以 Debug 断点/日志确认。本报告只断言：
   基线同崩 + 改动面零交集 + 两条崩溃腿的数值判别（转置整面 / 线性跟随）。
3. **AI 蒙版 bake 三次零落盘**：Subject/人物按钮 AX-press 与真实点击均无 toast、无 `.masks`、
   无 history——hasSelection 门（`selectedLayerID != nil`）在首轮确未满足；补建图层并点选行后
   仍无 bake（多实例 picker 未现）。可能为合成事件未送达 `Task {}` 按钮动作，或该街景确无
   前景实例（`noSubject` toast 应现而未现，倾向前者）。paste 活引用因此走源码复核 + dialog 实机。
4. **两次 NSGenericException 崩**（`t4-crash-layout-*.ips`）：均发生在 nodes/rail 面板导航期，
   栈顶 `NSSplitViewItem _setCollapsed` + SwiftUI Transaction 动画监听，reason 被 redact。
   与 R7 改动面零交集（R7 无 UI 改动），判为既有布局崩溃观察项（obs-4），film 卡导航面待其修复后补走查。
5. **探针末行 `displayTexture = nil` 既有行为**：每实例首开后走查从当前面继续，不影响判据
   （sidecar/渲染均为真实产线面）。探针污染 `library.recentProjects` 已随收工清 defaults 处理。

## 七、证据清单（`omp-evidence/`）

| 文件 | 内容 |
|---|---|
| `build.log` / `monitor.log` | BUILD SUCCEEDED（05:11:25）/ RSS monitor 零 kill |
| `omp-verification.txt` | 全部原始观测 + 逐值 |
| `t1-endpoint-dragged.png` / `t1-after-drag.lra.json` / `t1-relaunch-survived.png` | T1 三段：拖后 items 4（bx 0.5080）/ 落盘 verbatim / 重开存活 |
| `t2-crash-head-cw90.ips` / `-ccw90` / `-rot180-crop` / `-croponly` / `-crop5pct` / `t2-crash-baseline-rot90.ips` | E-1 六份崩溃报告（HEAD 五 + 基线一） |
| `t3-pristine-peak100.png` / `t3-aces-sections.png` / `t3-hdr-seed1000.png` | T3 三段：pristine 100 / ACES 限色联动 / HDR seed 1000 |
| `t4-cap-toast.png` / `t4-transfer-dialog.png` / `t4-nodes-filmcard.png` | 第 5 条拒 toast / transfer dialog / nodes 胶片卡 |
| `t4-crash-layout-splitview.ips` / `…2.ips` | obs-4 两份布局崩溃报告 |

## 八、建议（给 orchestrator）

1. **R7 可签核**（CONDITIONAL PASS）：T1 实机闭环；T2 转置语义经数学复核 + 可证伪回归双承载，
   实机面待 E-1 修复后补走查；T3/T4 裁决复核成立；m-1 路由明确。
2. **E-1 单独立项**（error 级）：几何编辑即崩——flip90/crop/角度联动实机全不可用；基线既有，
   非 R7 回归。修法方向：pipe 恒等链在几何收缩/转置下的协商传递（pos 0 miss 闭包两端对不上）。
   立项后补 T2 实机联动（rotCW90 + 非对称 crop + 10° → 转置闭式）与 T4 paper 面板点击。
3. obs-4（NSSplitView 布局崩）可并入 E-1 同批排查（都是几何/布局面实机崩溃），或另立小项。
4. 走查配方增补：导线 overlay 拖拽一律多 tick 慢拖（§六.1）；AI bake 走查需先点选图层行
   （hasSelection 门），无实例街景换人像样张。

—— 终审：omp（独立于 zcode 验收；全部结论以本轮实测 + 源码亲核为准，实机未达面已如实标注）。
