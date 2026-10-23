# R12-REPAIRS ACCEPTANCE-2ND — R1/R2 修复批第二路独立验收(对抗错位,2026-10-23)

> 验收对象:接续批 5 commits(`f64593af` M-1 / `266647c1` 标记链断 write-face
> substrate / `926ba65d` F2-4 / `41790826` R2 卫生 / `c09533bf` docs)+ ops
> 追认(`8acfb31e` v1.2 / `e7852a1e` guard v1.3,本路亲历 v1.3 全程零校准)。
> 正本 = 审计 MANIFEST §R1/R2 + F0P-02-03-ACCEPTANCE-2ND.md 移交项 +
> r12-repairs SUMMARY/DECISIONS + 一路 `ACCEPTANCE.md`(PASS/0B+1M+2m+7obs)。
> 主树 HEAD = `e7852a1e` 亲证;零源码改动;主树 tracked 零 diff(commit 前
> `git status` 亲证);本报告 + `acceptance-2/` 日志/截图 = 全部落盘产物,
> 不 commit。
>
> 二进制有效性:本路独立增量 `build-for-testing` = `** TEST BUILD SUCCEEDED **`
> (`acceptance-2/bft2.log`),Sessions/.xctest 含 `testPairChangeRespawns…`
> 符号、Library/.xctest 含 LibraryMetadataWriterTests 双新法符号(strings
> 亲证)——消费默认容器 `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`。

## 结论头

**PASS / 0 blocking + 0 major + 3 minor + 8 obs**

五面全亲跑,一路结论(PASS,四笔修复忠实)**独立复现成立**;全套
`--all` 独立复跑 **`TOTAL|4106/40/0|`(2422s)七 bundle 计数向量逐值精确
一致、零 MEMFAIL、峰值 RSS 全在 8G 运行门内**;zh-audit `--check`(1687
source / 2005 catalog / 41 interp 全 variant-PRESENT)+ `--self-test`
(V17 golden 八例)**双 PASS 与一路逐值一致**。真机走查三件:culling 双
pane 出图(**本路加证 staggered 防风暴中间态**:A 已渲染 + B「解码中…」
占位帧)、Settings 真窗 + ACA 深链页、**深链重现性(关窗复点再落 ACA)+
⌘, 串扰反证(菜单开 = 默认页「语言与主题」,零陈旧深链)**。
与一路的分歧清单见 §六——**无推翻项**;新增 = F-2 直插值家族全仓
花名册缺口(minor-1)+ 标记链断接线批两个未登记设计输入(minor-2/3)。
一路 major-1(gamma F-2 禁形)维持原判与 E 族路由,本路花名册扩充后
并入同批。

## 一、面 1 — M-1(f64593af):判定 ✓ PASS

**逐 hunk 亲读 + 攻击全过:**

- **id 数组稳定性**:`.task(id: [pair.0, pair.1])`([String],Value 语义)
  — `resolvePair` 六 arm 逐一攻击:双元素恒异(relPath 来自 rows 去重面,
  picks[0]≠picks[1];单选 anchor 与 next/previous 异源;无选首二异源)…
  无重复元素形态;空组(browsable<2)→ nil → 空态分支无 task(无 id 冲突
  面);同 pair 重评 → 数组 Equatable 相等 → no-op(任务不重启,一路 D2
  边界如实);跨组切换 → id 变 → 重跑(relPath 含 `/` 的拼接碰撞面被数组
  形结构性排除——D2 论证亲核成立)。滚动回收:pane 非 scroll 容器,无回收
  id 冲突面(N/A)。
- **decodeLeg 显式 init 缝旁路排查**:全仓构造点恰二——`ContentView:473`
  (不传 decodeLeg = 默认 nil = 真 RAWDecoder,调点逐字节零改)+ 测试
  :278(注入 recorder.leg)。无第三路径绕过缝(memberwise init 不可达:
  `let` 无缺省,显式 init 唯一)。
- **pump 饿死复发面**:yield 式 pump + nonisolated sync tick helper(D3
  论证亲核:阻塞式 RunLoop.run 不让位 → MainActor spawn task 首腿后续接
  永不恢复)。高载复发面 = 20s 窗超时(非假绿:超时 = 硬红);全套套跑中
  该法随 Sessions 285/9/0 三重绿(定向/一路/本路),未见环境敏感。
- **`Text(verbatim: pane.id)`**:文件名非 localization key,保留合理。
- **真机走查**:legacy 门 + `browser.mode=culling` 预置 + 真会话目录 —
  **双 pane 真机渲染**(`acceptance-2/cull-shot.png` = A.ARW 已渲染 +
  A_mertens.tif「解码中…」占位 = **staggered 防风暴门中间态实拍**;
  `cull-shot-both.png` = B 落地后双图并排)。本路加证:中间态帧为一行为
  语义(A 先于 B)的运行时直接证据,一路仅有终态。
- **pair 切换真机直通仍不存在**(复证一路 obs-2):CullingView 全文件零
  手势/按钮(静态亲证);grid↔culling 往返 = 结构重挂非 id 敏感。pair
  切换重载的行为级证明 = 套内回归测试(真 NSWindow + 真 `.task(id:)`,
  红态 = 出厂缺陷),本路三重绿。

**新登记 obs-4**:pair → nil 原位迁移(rows 收缩 <2 且视图挂载)不释放
planes(release 仅在 task 闭包与视图级 onDisappear;Group 内层分支切换
不触 onDisappear)—— bounded ~2 planes、修复前后同形(严格不劣化)、
视图显示空态正确;留 R3 同 D2 边界顺路。

## 二、面 2 — 标记链断(266647c1):判定 ✓ PASS(substrate 面;接线让渡如实)

- **writer 极端序列攻击**:
  - mark→unmark→mark 交替:writer v1 **无 clear 通道**(nil = 不动)——
    「unmark」不可表达,与 D5 让渡登记逐字一致(接线层决定 clear 语义);
    交替序列在 writer 层退化为连续 mark,语义单调、无丢失。
  - 跨照片连发:`apply` 循环逐张 compose+write + **单投影批**收口;并发
    `apply`(未来接线)经 LibraryStore actor 串行,`withWriteBatch` 互斥。
  - 评级色标并发:同上 actor 串行;DB 腿单写批原子(四列 WHERE id)。
- **nil 分量语义**:`if let rating = edit.rating { document.rating = … }`
  三分量同形(nil 不动)——与测试正本「the old rating survives a color
  mark」一致(测试 :179 亲读)。
- **DB 腿落盘亲核**:测试 4 法(真 .lalb + 真图档)已钉 sidecar 字节 +
  投影行双读;`bindInt(_:_:)` 签名 = `Int64?`(SQLiteHandle:69,三 nil
  臂同签名);投影值 = 合成后文档(post-write truth,round-trip 测试
  rating 5 存活断言在位)。modified_time = 批级 `now`(bindDouble)。
- **SC#2**:existing-but-unreadable → `sidecarWriteFailed` throw → SKIP,
  bytes 逐字节不变断言在位;与 MetadataService.apply 段1 同构亲证
  (pristine mint 六参逐一比对:decoderVersionUsed "unknown-metadata" /
  decodeParamsHash 0 / seed instances / empty history + HistoryHash(stack:,
  0) / currentAppVersion / layerStack nil / process: .current)。
- **refreshRows(ids:)**:`rows.map { byID[$0.id] ?? $0 }` 原位补丁;
  walk order/分页态/selection 不动(测试 :223-238 钉死);未载页 id 忽略。
- **接线让渡如实复证**:`grep -rn LibraryMetadataWriter` 产线调用点零
  (仅注释);shell apply\* 仍只走 session-face(图库工作区 no-op = 申报
  状态)。**接线批两个未登记设计输入 = 本路 minor-2/3**(§六)。

## 三、面 3 — F2-4(926ba65d):判定 ✓ PASS(本路加证三项)

- **缝亲读**:request-field(ShellGraph.settingsRequested)+ face
  `.onChange` 消费(guard → 复位 → presentSettings?())+
  `SettingsWindowController.showWindow`。单实例亲证:controller 持
  `ShellGraph.shared`(:2204),face `graph` 由 controller 注入
  (:2308)——Button 侧 `ShellGraph.shared.settingsRequested = true` 与
  face 观察同实例。
- **深链时序**:先置 `SettingsDeepLink.pendingPage` 再举旗;
  `SettingsView.onAppear` 消费(SettingsView:86-89)。
- **真机走查**(probe 项目 + `library.ai.connection` absent → needsSetup):
  1. AXLink(role=AXLink)AXPress → **Settings 窗出现 + 侧栏「高级内容
     分析」高亮 + detail = 协议/Base URL/模型/API 密钥区**
     (`settings-shot.png`)——死钮 → 真窗闭环复现。
  2. **重现性**(本路加测):关窗(AXCloseButton 亲点,窗列表回落单窗)
     → 复点同链 → **Settings 重开仍精确落 ACA**(`settings-reopen.png`,
     ACA 行蓝色新选中 = fresh mount 选择)——pendingPage 每次开窗消费
     且链条自再武装。
  3. **⌘, 串扰反证**(本路加测):关窗 → AppKit 菜单 Settings…(⌘, 同缝)
     → **落默认页「语言与主题」**(`settings-cmdcomma.png`)——零陈旧
     深链、零跨页串扰;pendingPage 唯一 setter = LibraryInspectorView:348
     (grep 亲证)。
- **已开窗重挂语义(本路攻击,静态封死)**:初始攻击假说「窗已开时
  showWindow 不重挂 → onAppear 不跑 → 陈旧 pendingPage 毒化下次 ⌘,」
  被**代码事实封死**——`showWindow` **无条件重建 contentView**
  (NSHostingView(SettingsView(…)) 每调必新,ShellWindowControllers.swift
  "Same unconditional mount" 注)→ 每次 showWindow 必触发 onAppear 必
  消费。运行时半证:已开窗态复点后窗前移且 ACA 保持(页面未离开无法
  区分「重挂落 ACA」与「停留 ACA」——AX 驱动 List 选择受限,该项
  time-box;结构性证据充分,非缺陷)。
- **竞态攻击**:连点(双击)→ flag 两举两消 + showWindow 两调(重挂幂等,
  单窗实例);双窗不可能(controller 单实例持有单 NSWindow)。clean。

## 四、面 4 — R2 卫生(41790826):判定 ✓ PASS(带 minor-1 花名册缺口)

- **尾闭包化等价性抽查(≥8 达成)**:43 处转换(23 文件)逐 hunk 亲读;
  **alignment 参数迁移 8 处全对核等价**(.top×2 / .trailing×2 /
  .leading×3 / .bottom×1,`git show` 行对 :99/:103、:628/:632、
  :648/:652、:680/:684、:696/:700、:724/:730、:882/:886、:897/:901);
  非 alignment 形(View 实参 → 尾闭包)机械等价。overlay/background
  语义差异点(alignment 缺省 center、z 序)无一受扰。
- **机检门独立复现(三重)**:
  1. MANIFEST §6 窄口径(行尾) = 6 行/3 文件,全合法豁免亲核
     (PipeCoordinator ×4 = DrawnMaskRasterizer 域函数;
     EditorAdjustmentStackView:139 + MaskGroupsPanelView:108 = 合法
     `ShapeStyle+in:` 形,后者 `.background(ThemeTokens.cardBorder, in:)
     亲读);
  2. 宽扫全形态余量 = ShapeStyle 单参(Color)/`in:` 形(合法);
  3. **本路独立构建 `deprecated` 警告 = 零**(bft2.log;5 条警告全为
     既有 nonisolated(unsafe)/retroactive-conformance/appintents 噪声,
     与 R2 面无关)。
- **本地化亲核**:blendLabel eager String → lazy `LocalizedStringResource`
  (显式 switch 17 臂逐一比对,1:1 静态键,V14 合规);xcstrings diff =
  尾插三键(manual,en/zh)+ 孤儿单删(obs-3 一路所指两空格空白行本路
  diff 亲见:`+  `,JSON 合法、zh-audit 无感)。
- **F-2 禁形残留全仓 grep(一路查过 gamma 一处——本路猎洞结果 =
  一整个家族)**:
  - 模式 `String(localized: "stem \(x)")`(直插值构 LocalizationValue,
    = E1/major 同形)全仓 **27 处 / 16 文件**(§五清单)。
  - 在册性逐键机检:**27/27 运行时键全部 catalog 在册**
    (`settings_displays_overridden %@` 疑似裸键经 `$0` 类型溯源证伪——
    `overridePath` 返回 `String?` → 运行时键 = `%@` 变体 = 在册命中,
    零运行时裸键)。
  - 在账比对:仅 `EDRControlView:46` = MANIFEST M-23 在账;gamma =
    本批新引(一路 major-1);**余 ~25 处存量(9/25–10/4 引入)不在
    E 族 / M-10..M-23 花名册**(B 路 m10 只从 xcstrings 复数维度点到
    export_targets_header/export_face_more 两键,非形态点位)。
    → **minor-1**(§六)。

## 五、面 5 — 全套独立复跑 + zh-audit:判定 ✓ 一致

**`TOTAL|4106/40/0|`(2422s,零 MEMFAIL,exit OK)** — 日志
`acceptance-2/all-runs/acc2nd-round1.log`。前置:guard v1.3 两过
(套前 heavy=0 free=56%;**v1.3 撤 G3 后全程零校准零阻塞**——一路
minor-2 的 ops 面缺口已被 `e7852a1e` 关闭,本路亲历佐证);锁目录
`acceptance-2/all-runs/acc2nd.lock`(跑毕已清);nohup+disown。

| bundle | 一路独立轮 | executor 申报 | **本路独立轮** | 判定 |
|---|---|---|---|---|
| IOP | 753/5/0 · 7135MB | 753/5/0 · 6782MB | **753/5/0** · 7013MB | ✓ 计数逐值中 |
| IOPParity | 478/6/0 · 5665MB | 478/6/0 · 5783MB | **478/6/0** · 5781MB | ✓ |
| Layers | 494/5/0 · 814MB | 494/5/0 · 817MB | **494/5/0** · 813MB | ✓ |
| Library | 742/4/0 · 621MB | 742/4/0 · 630MB | **742/4/0** · 624MB | ✓ |
| Sessions | 285/9/0 · 1207MB | 285/9/0 · 1246MB | **285/9/0** · 1222MB | ✓ |
| Export | 385/5/0 · 5082MB | 385/5/0 · 5348MB | **385/5/0** · 5479MB | ✓ |
| App | 969/6/0 · 2832MB | 969/6/0 · 2832MB | **969/6/0** · 2832MB | ✓ |

- 七 bundle 计数向量三路逐值精确一致;skip 40 零漂移;峰值 RSS 全在
  8G 门内(方差带 ±3% 内,与 SPIKE 注记一致)。对账 4101 + ΔN 5
  (SESS +1 / LIB +4)= **4106 精确**;BUNDLE-MAP 两行 + 注记亲证。
- zh-audit:`--check` **PASS**(1687/2005/41,与一路同值)+ `--self-test`
  **PASS**(V17 golden 八例)——双 PASS 复现。
- 对象间顺序纪律:构建 → 全套 → GUI 走查,严格串行;套跑中 GUI 零实例
  (ps parentage 亲证唯一 Lightamer = 测试宿主)。

## 六、与一路的分歧清单 + 分级清单

**推翻项:无。**一路 PASS 维持;major-1(gamma F-2)维持原判与 E 族
路由。分歧全部为**范围/账面增量**,无一改判:

- **minor-1:F-2 直插值禁形家族花名册缺口(27 处,在账仅 1+gamma)** —
  一路只点名 gamma(本批新引,判 major);本路全仓扫出同形存量 26 处
  (9/25–10/4 引入,B/C 两路均未按点位入账;B-m10 仅 xcstrings 复数
  维度邻接)。27/27 键 catalog 在册、零运行时裸键 → 按 E1 口径全族
  「禁形 + 键在册 = major 形态违规、行为正确」,但均为存量非本批引入,
  **不阻断本批**。处置:**E 族显式化小批花名册扩至 27 处全量**(修复法
  同 E1:显式 switch/静态键 + 参数走 format;`settings_displays_overridden`
  键含 `%@` 与 String 参数匹配,无需键迁移)。清单:
  BeforeAfterState:46 · ExportQueueFaceView:109/128/168 ·
  ExportPanelView:346 · LCRSettingsModel:72/115 · ACASettingsModel:219 ·
  SettingsPages:593/1255/1521/1525 · EDRControlView:46(M-23 已账)·
  SoftProofControlView:83 · SessionBrowserView:284/309/345 ·
  FilterBarView:233/237/249/253/257/261/265 · LightamerShell:704 ·
  SegmentEditingOverlayHost:170 · SkinSmoothPanelView:183(三参)·
  RawDecodePanelView gamma(本批,一路 major-1)。
- **minor-2:标记链断接线批设计输入缺「分页一致性」条款** —
  `setMetadataMarks` 投影批改写 `rating`;六键 whitelist 排序键含
  rating(FilterSQL:59-75)→ 未来接线若在 rating 排序 + 分页未走完时
  落标,`mainAnchor`(末行键值)漂移可致已载行**重复投递**或未载行
  **跳过**(keyset 游标语义)。现状双缓冲:接线未开工(apply 零调用点)
  + library grid `apply(sort:)` 无生产调用点(今日仅 filename 默认序)
  = **双重潜在,零现行为**。处置:并入 D5 设计面地图作接线批输入
  (候选:落标后若 sort.key ∈ {rating} 则 resetCursor+reload,或投影批
  免改 sort 键)。
- **minor-3:标记链断接线批设计输入缺「崩溃窗投影时序」条款** —
  MetadataService 段2 先 claim(dirty=1 开崩溃窗)后写;writer 反序
  (sidecar 先落 → 投影批后落):进程死于两步之间 = 真相已写、投影陈旧。
  投影 = 可重建派生物(OQ-3),reconciler/journal 兜底面存在,非数据
  损坏;但接线批应显式登记该窗口与恢复路径(reconciler 对 mark 场景
  的覆盖验证)。
- **obs-1**:产物登记 = `acceptance-2/{bft2.log, bft2.pid, cull-ax.txt,
  cull-shot.png, cull-shot-both.png, settings-shot.png, settings-reopen.png,
  settings-cmdcomma.png, settings-remount.png, gui-*.zsh}` +
  `acceptance-2/all-runs/acc2nd-round1.log`;主树 tracked 零 diff。
- **obs-2**:culling 真机走查加证 staggered 中间态(A 渲染 + B 解码中
  占位,`cull-shot.png`);pair 切换真机直通不存在(复证一路 obs-2,
  静态 + 行为级测试双轨不变)。
- **obs-3**:F2-4 已开窗重挂的运行时「异页切换」变体未走通(AX 驱动
  SwiftUI List 选择受限,time-box 放弃);结构性证据(unconditional
  remount → onAppear 必消费)充分,非缺陷面。
- **obs-4**:culling pair→nil 原位迁移不释放 planes(~2 planes 有界,
  修复前后同形),留 R3 与 D2 边界同批。
- **obs-5**:guard v1.3 撤门后本路全程零校准(两轮 guard 一次过:
  build 前 free=58% / 套前 free=56%)——一路 minor-2 的 ops 裁决项
  已被 `e7852a1e` 落地关闭,本路作为 v1.3 首个全套轮实证可用。
- **obs-6**:走查 defaults 副作用恢复——`browser.mode` 回写批前值
  `grid`;`NSNavLastRootDirectory`(本路预置)已 delete(批前 absent);
  `library.ai.connection` 保持 absent。recentProjects:本会话产生的
  `/tmp/r12-acc2/Untitled.lalb` 条目随 probe 目录删除成死路径,下次
  启动由既有死路径清扫自动摘除(既有机制,不手工动 defaults);应用
  会话期间自扫了三条批前已有死路径条目(既有清扫行为,如实登记)。
  probe 项目 = "Untitled"(保存板命名步 keystroke 未落,项目文件随
  /tmp 目录删除,零持久残留)。
- **obs-7**:R1 其余在账项(M-2..M-9、M-10..M-30)MANIFEST 路由原样
  未动 = 与 SUMMARY 续接点申报一致;唯一大遗留(标记链断产线接线)
  仍开放,本路新增其两个设计输入(minor-2/3)。
- **obs-8**:IME 候选框在 settings-reopen/settings-cmdcomma 截图左下
  入镜(osascript keystroke 上下文残留,截屏态噪声,零产物影响)。

## 七、结论

**PASS / 0 blocking + 0 major + 3 minor + 8 obs。**四笔修复 commits +
docs 忠实于 MANIFEST §R1/R2 与 F0P 移交项,一路结论独立复现:M-1 产线
修复 + 行为级回归 + 真机双 pane(加证 staggered 中间态);标记链断
write-face 与 MetadataService 段1 同构、nil 语义校正、让渡如实;F2-4
request-field 缝 + 真窗 + ACA 深链 + 重现性 + ⌘, 串扰反证三件套;
R2 卫生 43 处转换 alignment 逐对等价 + 三重机检(含本路构建零
deprecated)+ zh-audit 双 PASS。全套 `4106/40/0` 七向量本路独立复现。
三个 minor 全部为**账面/路由增量**(E 族花名册扩容 + 接线批两个设计
输入),无一阻断收口、无一改判一路。还原干净:guard 无痕(零校准)、
锁已清、零进程、defaults 回写批前值、零 tracked diff。
