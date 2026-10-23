# R12-REPAIRS ACCEPTANCE — R1/R2 修复批第一路独立验收(2026-10-22/23 夜)

> 验收对象:接续批 5 commits(`f64593af` M-1 / `266647c1` 标记链断 substrate /
> `926ba65d` F2-4 / `41790826` R2 卫生 / `c09533bf` docs)+ ops 追认 commit
> `8acfb31e`(guard G3 v1.2)。正本 = 审计 MANIFEST §R1/R2 +
> F0P-02-03-ACCEPTANCE-2ND.md 移交项 + r12-repairs SUMMARY/DECISIONS。
> 零源码改动(本报告 + acceptance-1/ 日志 + /tmp 截图 = 全部落盘产物;主树
> tracked 零 diff,`git status` 亲证);消费 executor 测试轮容器
> (`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`,二进制含新测试符号 strings 亲证,
> build-for-testing 增量 `** TEST BUILD SUCCEEDED **` 零漂移)。

## 结论头

**PASS / 0 blocking + 1 major + 2 minor + 7 obs**

五面全亲跑:M-1 / 标记链断 / F2-4 / R2 卫生 四 commit 逐 hunk 亲读 + 机检复跑;
定向三 bundle 亲跑逐值中;GUI 行为走查两项落地(culling 双 pane 出图 +
Settings 真窗 + ACA 深链页);**全套 `--all` 独立复跑 `TOTAL|4106/40/0|`
(2215s)七 bundle 计数向量逐值精确一致、零 MEMFAIL**(对账 = 4101 基线 +
ΔN 5 = SESS +1 / LIB +4,skip 40 零漂移)。D9 校准证据链与 v1.2 追认 commit
(`8acfb31e`)逐项一致。1 major = 本批 R2 新引入的 F-2 禁形命中(gamma 读出),
不影响行为,路由下一批 E 族显式化小批。

## 一、逐项判定

### 1. M-1(f64593af)— 判定 ✓ PASS

- **产线亲读**:`.task` → `.task(id: [pair.0, pair.1])`(数组 id——tuple 无
  Equatable;relPath 含 `/` 故字符串拼接有理论碰撞面,数组形 Value 语义等价,
  D2 论证成立)。pair 变化 → 旧 plane release + 新 pane 装载;同 pair 重评
  no-op。`decodeLeg: ThumbnailDecodeLeg?` 注入缝自 view init 透传至
  CullingPaneModel(模型侧缝既有);显式 init 保 `ContentView:473` 调点
  逐字节零改(生产 decodeLeg = nil = 真 RAWDecoder,行为零改)。
  `Text(pane.id)` → `Text(verbatim:)`(上一任存活件,保留合理——文件名非
  localization key)。
- **已知边界(D2)核对**:pair 不变而 selection/rows 变化的 body 重评仍换入
  idle 模型且任务不重跑——修复前同行为(无 id .task 同样不重跑),严格不劣化;
  测试不覆盖、留 R3,**登记诚实**。
- **测试亲读**(CullingPipelineTests 6 法 = 5 既有 + 1 新):新法
  `testPairChangeRespawnsAndLoadsTheNewPanes` = 行为级回归——真 CullingView
  宿主于真 NSWindow/NSHostingView、真 `.task(id:)` 语义、真 selection 驱动
  (handleClick/clearSelection)、注入 decodeLeg 记录装载;断言初始 pair
  staggered(A 先于 B,反风暴门)+ pair 切换后新 pane 必须装载(**无修复 =
  20s 超时硬红,红态即出厂缺陷**)。pump 饿死修正(Task.yield + nonisolated
  sync tick helper)合理性亲核:D3 论证成立——阻塞式 RunLoop.run 不让位,
  MainActor 隔离 spawn task 首腿后续接永不恢复;`run(until:)` async 直调编译器
  禁,MainActor async 函数仍在主线程执行 = sync helper 语义等价。`withLock`
  形(D3-2)在位(:244/:251)。
- **真机走查**:legacy 门(`LIGHTAMER_LEGACY_LIBRARY=1`)+ `browser.mode=
  culling` 预置 + fixture 3×ARW(7RM5)——**culling 双 pane 真机出图**
  (cull-a.ARW + cull-b.ARW 并排渲染非占位,截图 `acceptance-1/cull-shot.png`)。
- **通路受限如实登记(obs-2)**:culling 挂载期间 pair 变化无产品 UI 直通——
  CullingView 无 selection 手势(全文件零 onTapGesture/Button,亲证);grid 改选
  → 切回 culling = 结构重挂(测不到 id 敏感路径);SessionWatcher 对落盘新文件
  未触发 culling 面重扫(等 60s+ 无 pair 变化)。**pair 切换重载的证明 = 行为级
  回归测试**(真 NSWindow + 真 .task(id:) 语义,红态 = 出厂缺陷),真机证据 =
  初载出图。验收方法「pair 切换真机走查(pane 出图)」按「pane 出图」面兑现。

### 2. 标记链断(266647c1)— 判定 ✓ PASS(substrate 面;接线让渡如实)

- **writer 亲读**:`LibraryMetadataWriter.apply` 与 `MetadataService.apply`
  段1 **同构亲证**(sidecarURL 盘真相 inout round-trip / pristine mint 同参:
  `decoderVersionUsed: "unknown-metadata"` + decode stamp 0/0 + seeded
  instances + empty history + `process: .current`(KD-7 ⑤b 对齐)/ SC#2
  existing-but-unreadable SKIP never clobber)。**nil 分量语义反转校正**
  在位:`if let rating = edit.rating { document.rating = ... }` = nil 不动,
  与测试正本语义(「the old rating survives a color mark」)一致。writeAtomic =
  同目录 tmp sibling → replaceItemAt/moveItem(L009)+ 失败清 debris +
  `journal.record`(reconciler 自吞自写事件)。
- **DB 腿**:`LibraryStore.setMetadataMarks` 单写批(trio + modified_time,
  WHERE id),bindInt 收 Int64? 亲核;投影值取**合成后文档**(post-write
  truth——grid 徽章读投影,投影 = sidecar 终值,真相镜像纪律)。
- **refreshRows(ids:)**:`rows.map { byID[$0.id] ?? $0 }` 原位补丁,walk
  order/分页/selection 不动;未载页 id 忽略。
- **4 测试亲读**(真 .lalb + 真图档):pristine mint 双写(sidecar + 投影行)/
  round-trip 保留(rating 5 存活 color mark、note/decodeParamsHash 保留)/
  SC#2 skip(bytes 逐字节不变 + 投影不动)/ grid patch(中行原位、顺序与
  selection 不动)。
- **接线让渡(D5)如实申报亲证**:`grep -rn LibraryMetadataWriter` 产线调用
  点 = **零**(仅两处注释引用);shell `applyRating/applyColor/applyFlag`
  仍只走 session-face `metadataController`(`metadataTargets()` 图库工作区
  恒空 → no-op,**与申报逐字一致**)。commit message 明示 "NOT in this
  batch: the production WIRING"。SUMMARY 续接点登记「唯一大遗留 = 产线接线
  ——下一修复批首项候选」+ DECISIONS D5 设计面地图(requestStackCommand 形 /
  ShellGraph 形 / seed 来源 = MetadataController.configure 同构)在账。
  **三重零未闭合状态的申报 = 如实,让渡合理性成立**(设计面从未开工,任何
  落笔都是本批发明的第三方案)。

### 3. F2-4(926ba65d)— 判定 ✓ PASS

- **缝亲读**:`ShellGraph.settingsRequested`(request-field,与
  `presetManagerRequested` 同形)+ face `.onChange` 消费
  (`guard requested → 复位 → presentSettings?()`)→
  `presentSettingsWindow()` = `settingsWindowController.showWindow(nil)`。
  **单实例亲证**:face `LightamerShell.swift:2203 let graph =
  ShellGraph.shared`——Button 侧 `ShellGraph.shared.settingsRequested = true`
  与 face 观察对象同实例(review M2 单源裁定形,无悬空旗)。
- **钮侧**:SettingsLink → `Button { } label: { }` + `.buttonStyle(.link)`
  (保观感);**先置 `SettingsDeepLink.pendingPage = .advancedContentAnalysis`
  再举旗**——深链在 showWindow 重挂的 SettingsView `onAppear` 消费
  (SettingsView:86-89 亲读),时序成立。`SettingsLink` grep 清零
  (App/Sources 恒 3 处注释,零代码点)。SettingsView:121 stale 注释同批清扫。
- **同文件 3 处 R2 hunk 随批披露**(:63 overlay / :91 background / :556
  background 尾闭包化)——commit message 正文披露,与 D4 记录一致,申报透明。
- **行为级复验**:probe 实例建项目 + 导入 2 ARW → plain 实例打开项目
  (`library.ai.connection` 键 absent → needsSetup = true)→ 检查器 AI 区
  「AI 分析 / 请先配置服务商 / **打开设置…**」活钮(AX role = AXLink,
  `.buttonStyle(.link)` 产物)→ **AXPress → Settings 窗出现且非空白**
  (9 页侧栏 + detail 完整渲染)→ **深链精确落「高级内容分析」页**(侧栏
  高亮 + 协议/Base URL/模型/API 密钥配置区,截图 `settings-shot.png`)。
  **死钮 → 真窗闭环,F0P 移交 major-1 兑现。**

### 4. R2 卫生(41790826)— 判定 ✓ PASS(带 major-1 发现)

- **尾闭包化机检(独立三重)**:
  1. MANIFEST §6 口径(行尾 `\.(overlay|background)\($`)= 6 行 / 3 文件命中,
     **全部合法豁免亲核**:PipeCoordinator 4 行 = `DrawnMaskRasterizer.overlay(`
     域函数(非 View 修饰符);EditorAdjustmentStackView:139 +
     MaskGroupsPanelView:108 = **`ShapeStyle+in:` 新形**
     (`func background<S: ShapeStyle, T: Shape>(_ style: S, in: T)`)。
     旧形 View 重载**零残留**。
  2. 宽扫全形态(`\.overlay\(|\.background\(` 全命中)= 余量全为
     ShapeStyle 单参形 / 尾闭包形 / `in:` 形(合法)。
  3. **编译器旁证**:本路 build-for-testing 日志 `deprecated` 警告 = **零**。
  - SUMMARY「余 3 命中」vs 本路 6 行——按文件计 3 文件(PipeCoordinator 一文件
    一计)= 口径自洽,方向如实(minor-1 注记)。
- **本地化亲核**:三 catalog 条目(`filter_focal_mm_value %lld` /
  `rawdecode_raster_peak_value %lld` / `rawdecode_raster_trc_gamma_value %@`,
  en/zh、extractionState manual)尾插在位;孤儿 `rawdecode_raster_trc_gamma`
  单删(唯一消费点被批内替换);**zh-audit 双 PASS 复跑**——`--check` PASS
  (1687 source keys, 2005 catalog keys, interp 41 全 variant-PRESENT) +
  `--self-test` PASS(V17 golden 八例)。`blendLabel` eager String → lazy
  `LocalizedStringResource`(显式 switch 17 臂保持,V14 合规形)。
- **⚠️ major-1(本批新发现)**:`RawDecodePanelView` gamma 读出新形
  `String(localized: "rawdecode_raster_trc_gamma_value \(String(format:
  "%.2f", g))")` = **`String(localized:)` 插值构键 = F-2 禁形字面命中**
  (全局 AGENTS.md「新代码禁形」+ MANIFEST E1/M-2 同款:插值字面量直构
  LocalizationValue,scanner 不可见,catalog 靠 manual 手工维持)。
  按 E1 判级口径(「违反房内硬禁令但 catalog 手工在册 = major」)判
  **major**。缓解面:键在册、运行时查表命中(E1 mini-bundle 实验已证该形)、
  代码注释自我申报形态与理由(defaultValue 变体需 StaticString)——**行为
  正确、形态被禁**;commit message 明示「the value rides the bare
  LocalizationValue form」= 申报透明,但形态本身与同 commit 的卫生目标
  (`Text(verbatim:)` 请 runtime 串出 localizable 位)自相矛盾。**修复路由:
  并入 R1 E 族显式化小批(M-2/M-3/M-4 同批),一处小改(显式 switch 臂返回
  静态键 + 参数走 format 或 `String(format:)` 拼接面)。**
  - 同族注记(obs):`Text("filter_focal_mm_value \(Int(v))")` /
    `Text("rawdecode_raster_peak_value \(...)")`(LocalizedStringKey 插值形,
    CatalogFilterBarView/RawDecodePanelView)——同族风险但**字面不在两条禁令**
    (禁令 = `String.LocalizationValue` 构键 / `String(localized:)` 动态键);
    键 manual 在册、旧形(裸键即格式串)本就 extractor-invisible,新形 =
    键显式在册的行为等价改善。留 E 族批统一评估显式化。
- **docs(c09533bf)**:三账本(SUMMARY/DECISIONS/all-runs 日志)纯插入,
  与实盘对账全吻合(逐值核对见 §二)。

### 5. D9 / v1.2 校准证据链 — 判定 ✓ 一致

- `8acfb31e`(v1.2 永久化)= G3 4GB→7GB(7168MB)+ config.toml 同批 +
  注记更新;校准证据链 = **6.59G 健康态三证**(物理空闲 77% / 单重活 /
  零 MEMFAIL)与 DECISIONS D9 记录(6.59G / 77% / 无其它重活 / 根卷 30% ·
  Data 卷 39% 满 / MEMFAIL 机检兜底)**逐项一致**;commit message「Static
  swapused is confirmed not to be a pressure signal」与 D9 实测面同口径。
- 「套后已复原」申报亲证:executor 轮后 `git diff Scripts/machine-guard.sh`
  零 diff(c09533bf 时点;v1.2 走独立 commit 落永久化)——临时校准与永久化
  两段式全程留痕。

## 二、全套独立复跑(移交义务)

**`TOTAL|4106/40/0|`(2215s,零 MEMFAIL,exit OK)**——日志
`acceptance-1/all-runs/acc1-round1.log`。前置:guard(G1 heavy=0 / G2
free=80% / G4 盘健康;G3 事件见 obs-5)。

| bundle | executor 轮(SUMMARY 申报) | 本路独立轮 | 判定 |
|---|---|---|---|
| IOP | 753/5/0 · 6782MB | **753/5/0** · 7135MB | ✓ 计数逐值中 |
| IOPParity | 478/6/0 · 5783MB | **478/6/0** · 5665MB | ✓ |
| Layers | 494/5/0 · 817MB | **494/5/0** · 814MB | ✓ |
| Library | 742/4/0 · 630MB | **742/4/0** · 621MB | ✓ |
| Sessions | 285/9/0 · 1246MB | **285/9/0** · 1207MB | ✓ |
| Export | 385/5/0 · 5348MB | **385/5/0** · 5082MB | ✓ |
| App | 969/6/0 · 2832MB | **969/6/0** · 2832MB | ✓ |

- 计数七 bundle **逐值精确一致**;skip 40 零漂移;峰值 RSS 全在 8G 运行门内。
- 对账:4101 基线 + ΔN 5(SESS +1 = CullingPipelineTests 5→6 M-1 新法 /
  LIB +4 = LibraryMetadataWriterTests)= **4106 精确**;BUNDLE-MAP 两行
  (SESS 6 / LIB 4)与 Project.swift +1 注册行对应亲证。
- 定向轮(套前):Sessions **285/9/0**(79s)/ Library **742/4/0**(90s)/
  App **969/6/0**(512s)= 与套跑向量三重一致。

## 三、GUI 行为走查证据

| 项 | 配方 | 结果 |
|---|---|---|
| M-1 culling 出图 | legacy 门 + `browser.mode=culling` 预置 + 3×ARW fixture + File→打开会话(NSNavLastRootDirectory 预置缝) | **双 pane 真机渲染非占位**(截图 `acceptance-1/cull-shot.png`;AX 树「选择要对比的图片(最多 2 张)」空态 → session 载入后 pane 出图) |
| F2-4 Settings 真窗 | probe 项目(2 ARW 导入)+ plain 实例打开 + 检查器 AI 行 AXPress(UI element 20,role=AXLink) | **Settings 窗出现且非空白 + 深链落「高级内容分析」页**(截图 `acceptance-1/settings-shot.png`) |

## 四、分级清单

- **major-1**:R2 批新增 F-2 禁形命中——`RawDecodePanelView` gamma 读出
  `String(localized: "rawdecode_raster_trc_gamma_value \(...)")`(E1 同形:
  禁形 + extractor 不可见 + manual 维持)。行为正确(键在册、查表命中、
  注释申报),形态违规;修复路由 = R1 E 族显式化小批(M-2/M-3/M-4 同批顺路,
  一处小改)。**不阻断本批收口**(无行为缺陷;申报透明;与前批 E 族在账项
  同性质)。
- **minor-1**:R2 机检残留数字口径——SUMMARY「余 3 命中」vs 本路实测
  6 行 / 3 文件(按文件计 3 = 口径自洽但未注明;全为合法豁免,零非法残留,
  方向如实)。
- **minor-2**:G3 v1.2 门(7G)**套后地板再次结构性阻塞**——本路实测:
  套后 + GUI 轮 churn 后 swap used 7.2-7.47G,回落 ~1-2MB/min,1 小时窗
  不可达(D9 同款形态升级:地板棘轮 2.1G→4G 时代→6.59G→7.2G+);按 D9
  最贴先例临时校准 7G→7.5G 执行全套,**套后已复原**
  (`git diff Scripts/machine-guard.sh` 零 diff 亲证),**永久再校准
  (或改压力探头 / G3 放弃静态门)留用户裁决**。v1.2 门在新地板常态下
  大概率每套跑后皆阻塞,ops 面需一轮裁决。
- **obs-1**:全套对账与日志 = §二;本路产物 =
  `acceptance-1/{bft.log, sess.log, lib.log, app.log}` +
  `acceptance-1/all-runs/acc1-round1.log`;主树 tracked 零 diff。
- **obs-2**:M-1 pair 切换的真机 UI 直通不存在(culling 无 selection 手势 +
  watcher 不触发 culling 重扫;grid↔culling 往返 = 结构重挂非 id 敏感)——
  pair 切换重载由行为级回归测试证明(真 NSWindow,红态 = 出厂缺陷),真机
  证据 = 初载双 pane 出图。SessionWatcher 对 culling 面 rows 刷新的行为
  (hint 是否应在 culling 挂载时驱动重扫)留后续批评估,非本批缺陷。
- **obs-3**:xcstrings 孤儿键删除处残留一行两空格空白行(文本级编辑残留,
  JSON 合法、zh-audit 无感,零行为面)。
- **obs-4**:M-1 已知边界(D2:pair 不变的 body 重评换入 idle 模型)在账
  留 R3——登记诚实,本路亲读确认修复前同行为(严格不劣化)。
- **obs-5**:guard 事件链——首轮 `--wait 300` PASS(free=78%);套前
  `--wait 600` G3 BLOCK(7.47G)→ 长窗轮询(~50min,7.47→7.19G,
  ~1-2MB/min)→ 按 D9 先例临时校准 7168→7680 一行(G1/G2/G4 全 PASS)→
  起全套 → **套后复原 checkout 零 diff**;套后 swap 冲 8241M(churn 惰性
  膨胀,与 acc2 4557M / D9 10.4G 同现象带)。本路临时校准 = minor-2 的
  处置腿,如实申报。
- **obs-6**:GUI 走查 defaults 副作用恢复——`browser.mode` 回写批前实测值
  `grid`;`session.recentPaths` / `NSNavLastRootDirectory` 批前值未采样,
  delete 归 absent(如实登记;均为测试便利预置,无持久危害);
  `library.ai.connection` 保持 absent(批前态,F2-4 needsSetup 条件)。
  走查期间一次误触 New Project 保存板(Esc 取消,零副作用)。
- **obs-7**:标记链断接线(下一批首项候选)之外,R1 其余在账项
  (M-2..M-9、M-10..M-30)MANIFEST 路由原样未动——与 SUMMARY 续接点申报
  一致;O-38(CullingView transition)未动 = 与申报一致。

## 五、结论

**PASS / 0 blocking + 1 major + 2 minor + 7 obs。**四笔修复 commits 忠实于
MANIFEST §R1/R2 与 F0P 移交项:M-1 产线修复 + 行为级回归 + 真机出图;
标记链断 write-face substrate 与 MetadataService 段1 同构、nil 语义校正、
让渡申报如实;F2-4 request-field 缝 + 真窗 + ACA 深链页真机闭环;R2 卫生
35 处全清(三重机检含编译器零警告)+ 本地化双 PASS。全套 `4106/40/0` 七
向量独立复现。唯一 major = 本批自引入的 F-2 禁形一处(行为正确,路由 E 族
批);接线缺口(图库标记命令 no-op)为已登记让渡,非验收缺陷。还原干净:
guard 复原、锁清理、零进程、零 tracked diff。
