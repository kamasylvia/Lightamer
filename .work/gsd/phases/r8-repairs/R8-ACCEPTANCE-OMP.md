# R8-ACCEPTANCE-OMP — omp 独立终审（实机走查 + E-1′ 修复验证 + 对账）

> 审期：2026-10-31 08:59 → 09:35。对象 = `a6b692bd` fix（`fixes #16`）+ 账本 `2502707f`/`a2349a9c`
> + zcode《R8-SUMMARY/DECISIONS》+ 内嵌 T3 AX 走查（walkthrough/ 四截图）。
> 方法：复用 Debug 二进制（零重建，磁盘红线）→ `-la_editor_probe` 探针开图 →
> 自编 AX 工具链（复用 /tmp/r8walk + 新编 `axmenu/axslide/axclick/axnth/axbtns/axrows`）
> + cliclick 坐标 + `screencapture -l` 窗口截 + sidecar verbatim 直读 + 源码亲核。
> 全程单 GUI 占用；零源码改动。

## 结论头

**CONDITIONAL PASS / 0 error + 1 major（M-1：胶片档上几何编辑渲染空洞，修复有效性边界存疑）+ 1 minor（m-1：R8 文档两处勘误）+ 3 obs**

| 终审面 | 判定 |
|---|---|
| 1. E-1′ 原崩矩阵复验（flip/crop/DRT 叠加） | **PASS**（§一；六击零崩，sidecar 逐次落盘） |
| 2. 胶片档 + 几何编辑（terminal 尾段全覆盖） | **M-1 major**（§二；存活但渲染空洞 + 重开不渲染，obs-2 并案） |
| 3. 非几何回归抽查（曝光/白平衡恒等分支） | **PASS**（§三；+1.0EV 生效、纯净链渲染正常） |
| 4. R8 诊断链复核 | **PASS**（§四；机制逐位吻合，诊断可信度高；唯日期勘误 m-1a） |
| 5. 双报告对账（zcode T3 走查证据） | **条件成立 + m-1b**（§五；承载「不崩」不承载「渲染正确」，措辞勘误） |

**签核意见**：R8 修复批本身验收通过——E-1′ 崩溃已消除（原崩矩阵六击零崩 + 全套 4438/34/0
+3 精确无人复核但回归逻辑成立）；但终审把 terminal 覆盖面补到胶片档时发现 M-1：
胶片启用档上 CW90 存活却渲染空洞（视口黑 + 胶片卡 NaN），且该档重开走 direct-load
二分叉仍 `rendered=NO`——与修复「terminal sub-run 协商错帧」的病灶面同处一域，
不能排除「roi 发布修好了 composite window 那一腿、另有一腿仍错帧」的可能性。
M-1 单独立项（major 级：阻塞胶片×几何组合实机面；纯几何/DRT 档不受影响），
不与 R8 签核挂钩。R7 T2 遗留的实机联动面（rotCW90 + 非对称 crop 转置闭式）仍待 M-1
修复后补走查。

---

## 环境与卫生

- **构建自证（复用，零重建）**：Debug 二进制（dgzsvdww 容器）mtime **10-31 07:18:00 晚于**
  `a6b692bd`（07:05:14），且 `git log a6b692bd..HEAD -- App/ LightamerCore/ LightamerIOP/
  Tests/ Scripts/` = **空**（其后仅 docs commits `5fc7150e/2502707f/a2349a9c`）→
  现成构建已含 R8 全部代码，直接复用，全程零 `xcodebuild`。
- **机器纪律**：guard 首判 **BLOCK G4**（Data 9823MB<25GB，97% 满）→ 按 M9-3 §7/§9 与
  R8 D-R8-4 先例**透明越门**（G1 heavy=0 / GUI 单实例 / 无 swap 压力 / 本轮零构建）；
  `--monitor 10800` 全程伴跑（`omp-evidence/monitor.log`），**零 RSS-KILL**；
  GUI 单实例串行（四实例均为前序干净 quit 后重起，`pgrep` 亲核同时只存活一个；
  峰值 RSS 实测 f 档 615MB，无 MEMFAIL 口径事件）。
  收工复测 guard：G4 20600MB（用户侧应用数据释放，非本轮动作）。
- **收工**：GUI 已 quit（`pgrep -x Lightamer` 零命中）；探针临时项目（5 个
  `editor-probe-*.lalb` + `.lock`）已删；`library.recentProjects` 探针污染已清
  （删前亲核 5 条探针路径，删后 `defaults read` 缺席）；tracked **零 diff**
  （本报告 + omp-evidence 落盘前）；证据 18MB（<100MB 磁盘增量线）；
  走查文件全在 `/tmp/r8omp/`（不入库；用户实拍仅作只读拷贝源，未触肖像目录）。
- **供件**：扫街 `DSC09981.ARW`（只读拷贝为 r8o-a/r8o-c/r8o-f 三份，md5 一致
  `3070225b92e30052acf6aa219d199167`）。

## 一、E-1′ 原崩矩阵复验 — PASS（六击零崩）

R7 §二矩阵逐项复验（同机 + 同供件 + 同操作语义；崩溃签名对照 = R7 六份 `.ips`）：

| # | R7 原崩动作 | 本轮复验 | 结果 |
|---|---|---|---|
| 1 | pristine RAW 上 CW90（tool strip） | r8o-a pristine 上「顺时针旋转 90°」AXpress | **存活**：items 2（旋转/flip orientation=5），视口竖构图转置（`02b`） |
| 2 | CCW90 | CW90×2 后「逆时针旋转 90°」 | **存活**：items 4（orientation 5→3→5 链），视口回竖构图（`04`） |
| 3 | rotCW90（flip 面板 popup，基线同崩） | CW90 第二击（= rot180，orientation=3） | **存活**：横构图复位 + 倒置语义（`03` 视口裁片：画面挤向底部） |
| 4 | rot180 + crop.left=0.1 | flip=5 档上 crop.left 滑杆 → 0.1 | **存活**：items 5（裁切/crop left=0.1 verbatim），视口收缩语义（`06`） |
| 5/6 | crop-only left=0.1/0.05 | 由 #4 覆盖（crop 收缩腿已激活；纯 crop-only 未单测——见 §六.2） | **存活**（组合形） |
| 7（新） | — | ACES 2.0 方法切换叠加几何档（flip+crop 在前） | **存活**：items 6，DRT 尾 + 几何链共存（`08b`）；切回 OpenDRT items 7 存活（`11b`） |
| 8（新） | — | 曝光 +1.0EV 叠加几何+DRT 档 | **存活**：items 8（exposure=1 生效，`13` 提亮可见） |

- **零崩溃判据**：四实例全程 `pgrep ALIVE` + `~/Library/Logs/DiagnosticReports/Lightamer*`
  **零新增**（R7 同矩阵 = 六份 `PixelPipe.swift:1676` precondition `.ips`）。
- **落盘判据**：sidecar items 2→8 单调递增，label/op/params 逐项 verbatim
  （`r8o-a-final.lra.json`；flip orientation 5→3→5 链与 CW90×2+CCW90 操作序一致）。
- **渲染判据**：转置语义以视口裁片亲核——`02b-vp`（竖条在右）vs `03-vp`
  （横条在底）= CW90 vs rot180 的转置/倒置正交证据；`04-vp` 与 `02b-vp` 像素级同分布
  （white 7.4%/black 17.2% 逐值相同）= CCW90 精确回到 CW90 构图。
  全屏通道分离花屏系**截屏管线伪影**（R7 §六 + 本轮 §六.1 双注记），不入判据。

→ E-1′（`negotiated ROI violated at pos 0` 几何编辑即崩）在 flip/crop/DRT 覆盖面上**已消除**。

## 二、M-1（major）：胶片档上几何编辑渲染空洞 — 修复有效性边界存疑

**实测**（r8o-f，`-la_film_probe` 实例，pid 11443）：

| 步 | 实测 |
|---|---|
| 启用胶片模拟 | 存活；面板翻出胶片卡（材料对/强度/曝光 3 控件，`31`）；但 sidecar **2 分钟未落盘**（`ls srcF/` 无 `.lra`，对比旋转/crop/曝光均秒级落盘） |
| 重开编辑器 | film page 未复挂（默认调色面），胶片卡仍在（`AXPopUpButton desc='胶片'` 在位） |
| CW90（flip=none→5） | **存活**（pos 0 precondition 未触发）；sidecar 落盘 items 3（默认观感/启用胶片模拟/旋转，filmRecord 在场，`r8o-f-final.lra.json`）；但**视口全黑**（`32b`，35s+ 不恢复）+ **胶片卡三值 NaN**（`34b`：相纸对焦/强度/曝光全 `nan`） |
| ⌘Z 撤销旋转 | pos 3→2 存活；但视口仍黑（`36b`，20s+ 不恢复），胶片卡仍 NaN——**undo 不恢复渲染** |
| quit 重开（`-la_editor_probe`，pid 12749） | 探针 `rendered=NO` → 走 **direct-load 二分叉**（`direct pipeCoordinator.load call…`）→ 3 分钟+ 仍 `isDecoding=true`，视口黑（`37c`）；最终 direct 返回 `texture=present` 后探针自 `terminate`（plain probe 无 stay 语义），**正常开图路径下该档渲染失败** |

**判别**：同机同供件的对照——r8o-a（flip+crop+DRT+曝光八步链）渲染正常 + r8o-c
（纯净 exposure+rotate+ACES 四步链）渲染正常 + r8o-f **启用胶片前** pristine 渲染正常
（`30`）。空洞仅出现在「film record 在场 × 几何编辑提交」的交集上。

**为什么定 major 而非 obs**：

1. **病灶面同域**：R8 修的是「composite window entry 形 vs walked 形错帧 →
   terminal sub-run 协商错帧 → pos 0 崩」。胶片档的 film sub-run 正是 terminal 段的
   另一 leg（`runTerminalTails` film → DRT 序）；CW90 后 film leg 的输入帧同样经历
   转置——本轮黑屏 + NaN 证明**该 leg 在转置下的行为仍错**（不断言具体断裂点，
   见 §六.3），不能排除「修复只蓋住了 composite window 一腿」的可能性。
2. **undo 不恢复 + 重开不渲染** = 非瞬态伪影：一次 CW90 把胶片档打进**持久坏态**
   （sidecar items 3 在盘，pos 回退无用，重开 direct-load 仍失败），用户数据面可达。
3. 与 zcode T3 的覆盖关系：zcode 走查止于 flip（未启用胶片），其「修复实证」不覆盖
   此面；本终审把 terminal 覆盖补到胶片档——这是**新发现**，非复述。

**路由**：单独立项（major 级：阻塞胶片×几何组合实机面；纯几何/DRT/曝光档不受影响，
R8 签核不挂钩）。修法方向：film leg 在 walked 帧下的输入协商/seed 链
（`assembleFilmLeg` / `runFilmLeg` 的 roi 传点 + `FilmSolveCache` 键控），
以及胶片启用落盘延迟（2 分钟未落盘 vs 几何秒级）的写腿差异。
R7 T2 遗留的实机联动（rotCW90 + 非对称 crop 转置闭式）并入该项后补走查。

## 三、非几何回归抽查 — PASS

| 件 | 实测 | 判定 |
|---|---|---|
| 曝光 +1.0EV（几何+DRT 档上） | items 8（exposure=1 verbatim），视口整体提亮（`13` vs `11b`），存活 | PASS：pointwise 面在 walked 链上正常生效 |
| 纯净链曝光 +0.5EV（r8o-c，无几何） | items 2（exposure=0.5 verbatim，`21`），存活 | PASS：恒等分支（roiWalk==entry）行为正常 |
| 纯净链 rotate + ACES（r8o-c） | items 4（旋转 orientation=5 + 切换显示变换方法），存活；ACES 白屏 = §六.1 截屏伪影（对照 `13` 同机提亮正常 + R7 T3 HDR seed 实机先例） | PASS |
| 无激活几何的档零漂移 | r8o-c 纯净渲染（`20d`）与 R7 基线观感一致；process=3 两档同值；white/black/sat 分布恒等分支无异常 | PASS（观感级；像素级由全套 4435 基线零漂移承载） |

## 四、R8 诊断链复核 — PASS（诊断可信度高）

源码亲核（零改码）逐项核对 `R8-DECISIONS.md §D-R8-1`：

| 诊断断言 | 亲核 | 结论 |
|---|---|---|
| forwardWalk 种 `roi = entry` 后不再写（修前） | `PixelPipe.swift:989` seed；修前该函数内无第二写入（`git show a6b692bd^:...` 亲核）；修复 hunk `1045 roi = roiWalk` 为修后唯一新增写入 | **成立** |
| `window = basePipe.roi` 取 entry 帧 | `LayerCompositeDriver.swift:261` verbatim 在位；`basePipe.roi` 的 `private(set)` 写点仅 `run` 系 + forwardWalk 尾（全仓 grep：外部消费唯一 = :261，内部 4 处 = film/display replay 腿恒等链，App/IOP 零消费） | **成立** |
| 崩溃点 pos 0 precondition 双值不匹配 | `:1691-1694` verbatim（`upstreamW/H == negotiatedIn` 精确断言，04-01-T4 「MUST match pixel-exact」注记）；R7 六份 `.ips` 签名（roiOut=neg=1840×1227 vs upstream 转置/收缩）与「window entry 形起步 + base case walked 形直返」的推演**逐位吻合**（CW90 1227×1840 转置整面；crop 1656=1840×0.9 / 1748=1840×0.95 线性跟随） | **成立** |
| 潜伏引入 = `9d1f4fa9` T4 composite 骨架 | 该 commit diff 亲核：`+let window = basePipe.roi`（LayerCompositeDriver :231）+ `+roi = entry`（forwardWalk :144）**同批引入**；当时链上无激活几何模块故不可达，用户可达化 = M9-3 crop tool strip——M9-3/M9-4 嫌疑线排除成立（前者 UI 入口，后者 prepareChain 折键与 ROI 协商正交） | **成立**，唯日期勘误 → m-1a |
| 恒等链零漂移 | `roiWalk == entry` 时 `roi = roiWalk` 与旧值逐位相同（纯赋值语义）；T4 全套除 +3 外零漂移为实证 | **成立** |

**诊断可信度：高**。机制链（seed 缺失 → 双形错配 → sub-run 错帧协商 → pos 0 精确断言）
的每一环都有源码行号 + R7 黑盒数值双向锁定；两条崩溃腿的数值签名（转置整面 /
线性跟随）与机制推演的吻合是**判别性**的（非事后拟合——修前探针红 `48×32-vs-32×48`
方向与推演一致，修后三绿）。

m-1a 勘误：`R8-SUMMARY.md:9` 写潜伏引入 `9d1f4fa9` 日期为「06-01」——
`git show -s` 实测该 commit 日期 = **09-23**（`feat(pipe): T4 LayerCompositeDriver`）。
「06-01」系 plan 号（Plan 06-01 T4）误作日期。路由：下批账本勘正一行，零代码影响。

## 五、对账 — 条件成立 + m-1b

| 项 | 复核 | 路由 |
|---|---|---|
| zcode T3「CW90×2+CCW90 存活、转置正确、items 4」 | **存活/items 两项成立**：本轮独立复验六击零崩 + sidecar items 逐次落盘（2→8），与其 items 4（CW90+CCW90 两击）同构。但「转置渲染正确」的承载存疑 → m-1b | 见 m-1b |
| zcode walkthrough/ 四截图 | `02-rot90.png`（欢迎 sheet 未关 + 通道分离花屏）/`06-cw90-again.png`（竖构图花屏）亲看：两者视口均为**通道分离状**——与本轮 `02b/03/04` 同源截屏伪影。截图能证明「进程存活 + 视口有转置形输出」，**不能证明「渲染正确」**（花屏下无法判读转置语义） | m-1b 勘误后可保留为存活证据 |
| zcode「crop overlay 手柄框自适应转置后 frame」 | 本轮 `03-vp` 视口裁片亲核：crop overlay 手柄（白点 + 三分线）确在转置/倒置后重拟——该观察**成立**，且与 R7 T2「重拟窗转置」联动面一致 | 无，成立 |
| zcode 降级项（crop 拖拽/滑杆挂账 omp） | 本轮 crop.left 系 AX slider 设值（0.1）**已覆盖语义面**（收缩 + 落盘 + 存活）；overlay 拖拽手势面仍挂账（与 zcode 同因：无 AX 面 + 前台互斥） | 维持挂账，并入 M-1 项后补 |
| 全套 4438/34/0（+3 精确） | 未独立复跑（磁盘红线禁重建 + 全套 4043s 超终审窗）；`a6b692bd --stat` 亲核改动面 = PixelPipe 2 hunk + LayerCompositeTests +122 行（3 法），与「Layers 528→531 唯增」自洽；两轮环境型事故（metallib 半成品 / App 截断重跑净轮）处置链完整 | 采信，记 obs-3 |
| issue #16 CLOSED（fixes #16） | E-1′ 在 flip/crop/DRT 面上确已消除 → 关闭成立；但 M-1 胶片面建议**新 issue**（非重开 #16：崩溃已修，新件是渲染空洞） | 新 issue 路由 |

**m-1b（minor）：R8-SUMMARY §逐 T 战果 T3 行「转置渲染正确」的措辞超证据承载**。
walkthrough 四截图在通道分离花屏下只能承载「存活 + 有转置形输出」，不能承载
「渲染正确」——本轮以视口裁片（`02b-vp/03-vp/04-vp` 三图正交：竖条在右/横条在底/
CCW90 回竖 + 像素分布逐值）补足了转置语义的**独立证据**，「转置正确」的结论本身成立，
唯 zcode 侧的证据链需勘误措辞为「转置形输出（存活），语义正确性由 omp 终审视口裁片补证」。
路由：下批账本勘正一行（或接受本报告为补证，SUMMARY 加一句指针）。

## 六、局限与透明度（不冒充产品结论）

1. **截屏管线通道分离伪影**：本轮 `screencapture -l` 全屏图中视口区呈品红/青/黄
   通道分离状（`02b/03/04/06/08b/13` 全系），但**缩略图/直方图/面板读数正常** +
   同机 pristine（`01`）正常 + 同操作视口裁片转置语义自洽 → 判为截屏抓取 EDR/浮点
   视口纹理的呈现伪影，非产品渲染缺陷（R7 §六已有同类注记；zcode `02/06` 同状佐证
   环境性）。一切渲染结论以**视口裁片几何语义 + sidecar verbatim + 存活**为准，
   不采信花屏像素。
2. **crop-only 纯形未单测**：本轮 crop 腿在 flip=5 档上激活（= R7 #4 形），未补
   flip=none 纯 crop（R7 #5/#6 形）。理由：机制上纯 crop 与组合 crop 走同一协商腿
   （crop.modifyROIOut 收缩 walked），且修前探针两腿双红、修后三绿已覆盖纯形语义；
   实机纯形待 M-1 项后补走查时顺路补。
3. **M-1 的根因定位是黑盒判别 + 源码域锁定**，未单步调试 film leg——
   「film leg 转置下错帧」的精确断裂点（输入协商 vs seed 键 vs solve 缓存）需立项后
   以 Debug 断点/日志确认。本报告只断言：黑屏 + NaN + undo 不恢复 + 重开 direct-load
   失败四事实 + 对照组判别（纯几何/DRT/曝光档全正常）。
4. **全套未独立复跑**（obs-3）：磁盘红线（禁重建）+ 4043s 超窗 → 采信 zcode T4
   终值（改动面亲核自洽 + 两轮事故处置链完整）。终审的独立增量在实机面，
   不在全套面。
5. **中文输入法劫持键入**：开图面板 `keystroke` 法被拼音 IME 吞掉两次，改剪贴板粘贴
   路径 + 键盘导航解决；后全程改走 `-la_editor_probe`（与 zcode 同路），开图面结论不受影响。
6. **探针末行既有限制**：plain `-la_editor_probe` 末行 `NSApp.terminate`（`37c` 后自退出）、
   首开后 `displayTexture = nil`（每实例首开走查从当前面继续）——均为既有行为，
   不影响判据（sidecar/渲染均为真实产线面）。

## 七、证据清单（`omp-evidence/`，18MB）

| 文件 | 内容 |
|---|---|
| `01-pristine.png` | r8o-a 纯净基线（横构图街景，缩放 100%） |
| `02-cw90.png` / `02b-cw90-settled.png` / `02b-cw90-settled-vp.png` | CW90 第一击：存活 + 竖构图转置 + 视口裁片（竖条在右） |
| `03-cw90x2.png` / `03-cw90x2-vp.png` | CW90 第二击 rot180：横构图复位 + 倒置（横条在底）+ overlay 手柄重拟 |
| `04-ccw90.png` / `04-ccw90-vp.png` | CCW90：回竖构图（与 02b 像素分布逐值同） |
| `05-croppanel.png` / `06-crop-left01.png` | crop 面板 + left=0.1 收缩语义（items 5） |
| `07-drtpanel.png` / `08-drt-aces-geom.png` / `08b-drt-settled.png` | DRT 面板 + ACES 叠加几何档存活（items 6） |
| `11b-opendrt-settled.png` | 切回 OpenDRT 存活（items 7） |
| `13-exposure-after.png` | 曝光 +1.0EV 叠加档生效（items 8） |
| `20d-fit.png` / `21-clean-exp05.png` | r8o-c 纯净链：适配渲染 + 曝光 0.5（items 2） |
| `22-clean-cw90-exp.png` | 纯净链 CW90 叠曝光存活（items 3） |
| `23-clean-aces.png` | 纯净链 ACES 存活（items 4） |
| `30-film-face.png` / `31-film-enabled.png` | r8o-f 胶片页 + 启用后面（M-1 前序） |
| `32-film-cw90.png` / `32b-film-cw90-settled.png` | **M-1**：胶片档 CW90 存活但视口黑 |
| `34b-history-settled.png` | **M-1**：胶片卡三值 NaN + 视口黑 |
| `36b-undone-settled.png` | **M-1**：undo 后仍黑（持久坏态） |
| `37c-relaunch-late.png` | **M-1**：重开 direct-load 失败（rendered=NO） |
| `r8o-{a,c,f}-final.lra.json` | 三档 sidecar 终态 verbatim（items 8/4/3） |
| `monitor.log` / `probe-stderr.log` / `probeF-stderr.log` / `probeF2-stderr.log` | RSS 零 kill + 三实例探针日志 |

## 八、建议（给 orchestrator）

1. **R8 可签核**（CONDITIONAL PASS）：E-1′ 崩溃消除（六击零崩 + sidecar 逐次落盘 +
   转置语义视口裁片补证）；诊断链高可信；zcode T3 对账条件成立。
   issue #16 维持 CLOSED。
2. **M-1 单独立项**（major 级）：胶片档 × 几何编辑渲染空洞（黑屏 + NaN + undo/重开不恢复）。
   立项后补：film leg 转置断裂点定位 + R7 T2 实机联动（rotCW90 + 非对称 crop 转置闭式）+
   crop-only 纯形 + overlay 拖拽手势面。
3. m-1a（`9d1f4fa9` 日期 06-01→09-23）+ m-1b（T3「转置渲染正确」措辞超载）下批账本各勘正一行；
   或接受本报告为补证、SUMMARY 加指针。
4. 走查配方增补：实机几何走查必须带胶片启用档（terminal 全覆盖；纯 flip 面不够）；
   截屏结论一律以视口裁片几何语义为准（全屏花屏伪影环境性）；中文输入法下键入改剪贴板粘贴。

—— 终审：omp（独立于 zcode 验收；全部结论以本轮实测 + 源码亲核为准，实机未达面已如实标注）。
