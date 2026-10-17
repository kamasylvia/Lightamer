# AR-01 验收报告 — 第二路独立验收(plan A / 执行链 1765f0ca..8e3bd59d)

> 验收路:第二路(零共享上下文,对抗性切入);验收窗 2026-10-18 00:20..03:40。
> 对象:执行链六 commits `1765f0ca`(T1 M1)/ `36322b5f`(T2 M4)/ `17b95f2b`(T3 M5)
> / `e7a51667`(T4 M3)/ `5c072a23`(T5 fixup)/ `8e3bd59d`(docs)。
> 申报正本 = `AR-01-SUMMARY.md` + `AR-01-DECISIONS.md` + `gui-acceptance/audit-repair-a/MANIFEST.md`。

## 结论头

**PASS / 0 blocking + 0 major + 3 minor + 5 obs**

五面判定:①行为级走查 **PASS**(真 GUI spawn,HEAD 新构建)②回归网 **PASS**(四类定向亲跑全绿,cmd+click REPLACE 亲证)③对抗 grep/diff **PASS**(legacyBody 段零 diff 独立亲证、封存域零触、xcstrings 纯插入恰 +1)④数字复跑 **PASS**(`TOTAL|3967/35/0|2100s` 与申报逐位一致;D-6 基线臂受环境约束降级,见 minor-2)⑤台账一致性 **PASS**(ΔN 表/偏差①-⑪/D-AR1-10 两案/MANIFEST 逐项对上;一处电池行措辞精度问题 = minor-1)。

---

## 一、行为级走查(真 GUI spawn,杀净还原)

**构建新鲜度事故与自我纠错(登记)**:首轮走查误用 DerivedData 容器 `glcjhggtbffoiugu`(Oct 16 20:19 批前旧码——`ls -td` 按 bundle 目录 mtime 排序的陷阱;本路 00:27 的 HEAD 构建实际落在 `dgzsvdwwznxhozhdtijsbcwmglbi` 容器)。旧容器上完成的走查轮**全部作废**,以下判据全部来自 00:30 HEAD 构建的复核轮。定向测试轮经日志宿主路径核验 = dgz 新容器,**结果有效**。

| 走查项 | 判据 | 结果 |
|---|---|---|
| 哨兵 toast 出现(T1-W1) | kill -9 → 重开 → 开项目 → ⌘E → filmstrip 首次换图(loadedImageURL false→true 沿)→ 底缘「上次会话异常退出——编辑已自动保存(至多丢失最后数秒)。」呈现 | **PASS**(n4-toast-live.png) |
| toast 自动清除(T1-W1) | 4.5s 后同位置文案消失、零高度 | **PASS**(n4-toast-late.png) |
| 只读横幅(T1-W2) | 双实例同项目 → 冲突对话框(「项目已被另一实例打开 pid 84096」+ 只读打开/重试/取消)→ 只读打开 → 顶缘「只读——项目已由另一实例(pid 84096)打开」呈现 | **PASS**(n2-readonly-banner.png) |
| filmstrip 点击换图(T4-W1,铁条②) | 点击 acc2/acc3 → 选中环 + current dot + 视口渲染 + 直方图跟随 | **PASS**(M3 id 记账改造后行为正常) |
| cmd+click 多选旗标 | cmd+click acc3 → REPLACE(独占选中,acc2 选中清除)——selectSingle 单选语义在案保持,选中面零触 | **PASS**(代码核 + 真面双证) |
| 项目切换四信号(T1-W4) | Open Recent → 网格重建 + Inspector 聚合(6 照片总数) + 标题更新 | **PASS** |
| Export 页挂载(T2-W1/W2) | File▸导出… 菜单命令(focusedSceneValue 发布下沉 Mount 后)→ Export 页全节渲染(预设/命名模板/冲突解决/元数据 ICC/SDR 导出);× 关闭 → 回调整栈 | **PASS** |
| Film 页挂载与 dismiss(T2-W3) | View▸显示胶片面板 → 胶片模拟页挂载;启用 → 三节渲染(材料 picker/CC 滑杆/强度/求解 readout「M 18.3 · Y 16.7 · ×1.00」/宽容度直方图 +「低于 0% · 容纳 100% · 高于 0%」);× close → inspector 收起视口回宽 | **PASS** |
| Film 面板-历史联动(T3-W6) | ⌘Z 两次:撤「调整胶片滤色」面板回 0 CC(同步)→ 撤「启用胶片模拟」面板回未启用态(启用按钮复现、滑杆/求解 readout 收起、宽容度锚直方图消失) | **PASS**(KD-3 三级读 undo 同步真面亲证;历史面板两项与栈位对应) |
| 拆节失效边界(T3) | 宽容度直方图节随胶片渲染动态出现/随 undo 消失 = LatitudeSectionView 随 model 状态正确刷新;solve readout 节启用后实时出现 | **PASS**(节级响应真面证据) |
| Drt 页挂载 | 显示变换 tab 切换 → 面板节渲染(vignette/暗角四滑杆) | **PASS**(tab 面) |
| 编辑器静置 CPU(HEAD 臂) | 30s 窗 6 采样中位 ~101.5%(长 settle 尾态;执行批「195→90 衰减」尾态 90% 同域) | 与既有 functional-with-churn 持续态一致(见 obs-1) |
| 崩溃面 | 双实例并存、kill 往返、资源 diag 一条(cpu_resource,既有 churn 域)——**零 .ips 崩溃报告** | PASS |

**走查覆盖缺口(通道限制,非缺陷证据)**:滑杆 knob 级精细拖拽(cliclick 三式未达 knob)、Drt Method 切换深滚动、filmstrip 滚动窗(6 行无滚动空间)、T3-W7 七 tab 逐页——机检面(D-H1 绑定面/memo 回归/FilmstripModelTests stale-window 两回归)与同款模式真面证据覆盖,登记 minor-3。

证据:/tmp/ar01-acc2/(即弃域,截图 16 张 + cpu-editor-head.txt);GUI 实例全部 kill 自己 spawn 的 PID(parentage 先核),defaults 写入(library.ai.labelingMode=never 抑制 AI ask)已 delete 还原,工作树 tracked 零改动。

## 二、回归网对抗

| 项 | 结果 |
|---|---|
| FilmstripModelTests(LIB bundle) | **8/0/0** 亲跑 = 申报(6 改写 + 2 新回归;新回归为真 SQLite 驱动 10k 行 fixup 插行/删行 stale-window 面,质量过关) |
| ToastFaceTests(APP) | **3/0/0** 亲跑(零 diff 面) |
| DrtPanelModelTests(APP) | **11/0/0** 亲跑 = 申报(9 原 + m2 memo 两新) |
| AgentControlCoordinatorTests(APP) | **13/0/0** 亲跑 = 申报(T5 fixup 后复测值) |
| AX 树语义 | 子 View struct 拆分不改变 AX 语义——ToastFaceTests 3/0/0(含 AX wiring 断言)亲跑绿 + 走查面元素全部可达;深度 AX 对比基线面因基线臂降级未做(见 minor-2),以机检面 + 真面判据代偿 |

## 三、对抗 grep/diff(全部独立亲证,非复跑申报命令)

| 项 | 判据与结果 |
|---|---|
| legacyBody byte-frozen | **段内容零 diff 独立亲证**:`diff <(git show c5570b05:ContentView.swift \| sed -n '248,418p') <(sed -n '210,380p' HEAD 版)` 零输出;偏移 -38 行(248→210)与 D-AR1-2 申报一致;段起止边界干净(前后为 docstring/browserContent 注释)。offset 适配申报成立,无掩盖 |
| T2 hunk 归属 | -U0 四 hunk = :186 / :191+6 / :195-46+2(臂区)/ :769+97(文件尾)——全部落 gate-false 臂区+文件尾,legacyBody 零 hunk |
| Mount 求值内容 | InspectorPageMount 的 .inspector binding / focusedSceneValue get-set / onChange(projectURL) 与旧臂**逐行语义恒等**亲证;clamped()→inline `CGFloat(min(max(w,200),460))` 数学恒等 |
| 封存域零触 | LightamerIOP/ LightamerCore/ *.metal UI/Inspector/ Project.swift BUNDLE-MAP 全链 `git diff --stat` 零输出亲证 |
| xcstrings | 纯插入(deleted=0)恰 +1 键 `latitude_share_value` 尾块(append 序惯例);D-AR1-7 终账 +1 亲证 |
| T1 四 modifier 平移 | 四 onChange 消费体逐行平移亲证;ToastBarMount/ReadOnlyBannerMount 内容形与旧 safeAreaInset 段逐字一致;七 struct 各恰一定义亲证 |
| T5 fixup 正当性 | WorkspaceTopBar :661/:675 `.disabled(isReadOnly || holdsControl)` 合并语义与改前 `.disabled(projectController?.isReadOnly ?? false \|\| agentControl.holdsControl)` 等价亲证——token 同步随重构,非改测试放水 |
| m2②③ 缓存失效 | isCustomLook 值键 memo(record==miss 即重算,无写点钩子需求);placementTarget 写点刷新五处 + 读时活真相校验(found == memo.instance 含 paramsData 全值比较——undo/参数替换必失效)逐行核过 |
| o9 会话缓存 | InspectorEditSession = stateless(weak coordinator + scope 纯转发)——缓存复用与新建语义恒等亲证 |
| M3 记账面 | firstIndex 双文件消灭(仅注释提及);visibleIDs 恰一声明;refreshWindow 单次建 map + formIntersection 剪枝;:169 `.disabled(agentControl.holdsControl)` 逐字节保留 |
| 禁形电池 | `.runModal(` App/Sources 零命中;`String.LocalizationValue("prefix_` 插值禁形零命中 |
| D-6 禁区分账 | WorkspaceHostView 挂点(.focusedSceneValue :183 / menus / 双 safeAreaInset)零 diff 亲证;ContentView 的 focusedSceneValue = T2 申报范围内的 gate-false 臂下沉(求值内容零改)——见 minor-1 措辞分歧 |

## 四、数字独立复跑

### 全套 --all(锁 `/tmp/la-audit-repair-all.lock` 串行,orchestrator 预批;nohup+disown 脱离形态)

**净轮 = `TOTAL|3967/35/0|2100s`——与申报 `TOTAL|3967/35/0|2142s` 计数逐位一致**(时长 -2% 噪声)。

| bundle | 申报 | 本轮复跑 | RSS 对比 |
|---|---|---|---|
| IOP | 687/5/0(7948) | **687/5/0** | 7661(执行批 +294 漂移;M2-4-0 记录 7654 → 本轮 +0.1% 贴记录值,obs-2) |
| IOPParity | 460/3/0(7741) | **460/3/0** | 7735(-0.08%) |
| Layers | 494/5/0(809) | **494/5/0** | 809(逐字节同) |
| Library | 738/4/0(622) | **738/4/0** | 622(逐字节同) |
| Sessions | 284/9/0(1431) | **284/9/0** | 1629(+13.8%,非贴线面,obs-3) |
| Export | 385/5/0(6011) | **385/5/0** | 6476(+7.7%,obs-3) |
| App | 919/4/0(2832) | **919/4/0** | 2832(逐字节同) |

skip 分账 5+3+5+4+9+5+4 = 35 ✓(24 基线 + 11 RAW 供件漂移,零第三种来源);零 MEMFAIL;零 fail。首轮一次过,无需净轮重跑。

### D-6 探针双构建差分

- **HEAD 臂**:独立复测编辑器静置 ~101.5%(30s×6 中位;与执行批 60s settle 形尾态 ~90% 同域,+11% 窗口差)——functional-with-churn 既有持续态,无新越阈。
- **基线臂:未能复测(minor-2)**——worktree 隔离(铁律①合规形态)冷构建三次同败(`xcodebuild: Could not resolve package dependencies: Couldn't update repository submodules`,含 `-disableAutomaticPackageResolution` 离线形;Tuist 生成工程的 SPM 集成对 worktree 冷解析结构性失败)。执行批双构建差分数据(193.7→194.4 / 31.4→31.9,Δ≤噪声带)**采信**,基线臂独立复现留待。

## 五、台账一致性

| 项 | 核对结果 |
|---|---|
| 六 commits | `git log 1765f0ca^..8e3bd59d` 六条与逐任务表一一对应 |
| ΔN 合计 +4 | T3 +2(DrtPanelModelTests 9→11)/ T4 +2(FilmstripModelTests 6→8)定向轮亲证;基线 3963+4=3967 全套亲证 |
| 全套终值 | `3967/35/0` 逐位一致(第四节) |
| 偏差①-⑪ | D-AR1-2(offset 适配——独立亲证零 diff)/ D-AR1-3(窄值字面形——:138/:626/:661/:675 亲核)/ D-AR1-4(同键复用——:167/:757 亲核)/ D-AR1-5/6(memo 形——失效正确性亲核)/ D-AR1-7(+1 豁免——纯插入亲证)/ D-AR1-8(LIB 归属——BUNDLE-MAP :384 亲核)/ D-AR1-9(token 同步——语义等价亲核)/ D-AR1-10(两案论证——HEAD 臂复测支持「相对门 PASS、绝对门基线永假」论证)/ D-AR1-11(微偏差七项——task 合并形 :341 / enumerated Array 包裹 / row 壳复制 / 剪枝 / o9 回落窗逐项亲核) |
| D-AR1-10 两案论证自洽性 | 自洽:(a) 相对门 = 双构建同协议差分 ≤ 噪声带(实测 +0.7%/+0.5%)PASS;(b) 绝对门 <10% 在 FIX2 裁定①持续态下永假(本路 HEAD 臂 ~101% 独立佐证基线固有 churn)。论证链无内部矛盾 |
| MANIFEST 配方 vs 实况 | AR-01-01..06 配方齐;探针五避坑(seam 自终止/stderr/LUT 预热/AI ask 抑制还原/AX+cliclick)亲历有效(AI ask 抑制与还原本路照做);执行批机检证据 /tmp/ar01-d6-probe/ 在案(即弃域) |

## 分级清单

**blocking(0)**:无。

**major(0)**:无。

**minor(3)**:
1. **电池表 D-6 行措辞精度**:SUMMARY 红线电池表「D-6 禁区面|menus/focus 挂点零 diff」——WorkspaceHostView 挂点零 diff 属实,但 ContentView 的 focusedSceneValue 实际被移动(gate-false 臂内下沉至 InspectorPageMount,求值内容零改)。T2 任务行与 D-AR1-2 已如实申报「整段下沉」,仅电池行汇总措辞有歧义。行为零差,机检语义以 T2 行为准。建议晨审时对电池行措辞补一句括注。
2. **基线臂 D-6 未复测**:worktree 冷构建三次同败(Tuist SPM 对 worktree 结构性失败),执行批双构建数据采信。覆盖缺口登记,非缺陷。
3. **行为走查覆盖缺口**:滑杆 knob 级拖拽/Drt Method 深滚/filmstrip 滚动窗/七 tab 逐页受探针通道限制未完成;以机检面 + 同款模式真面证据代偿。非缺陷。

**obs(5)**:
1. HEAD 静置 CPU ~101.5%(长 settle 尾态)与执行批尾态 ~90% 同域——functional-with-churn 既有持续态,D-6 专项挂账域。
2. IOP RSS 本轮 7661MB 贴 M2-4-0 记录值 7654(+0.1%);执行批申报轮的 7948(+3.8%)才是漂移轮——「贴线 RSS 漂移」观察以本轮为准更贴记录,资源监控注记域。
3. Sessions/Export RSS 漂移(1431→1629 / 6011→6476)——非贴线面正常方差,零 MEMFAIL。
4. 编辑器 shell 空态文案「选择文件夹以创建会话」在项目编辑器空态呈现(session 语义残留文案;执行批同款,窗口外既有面)。
5. m9 zh 语序渲染亲证(「低于 0% · 容纳 100% · 高于 0%」)= MANIFEST O-1 预期改进登记一致。

## 与申报的分歧清单

- **无 blocking/major 分歧**。五面申报(逐 commit 表/全套终值/偏差链/两案论证/MANIFEST)全部独立复现或亲证兑现。
- 措辞精度一处(minor-1);覆盖缺口两处(minor-2/3)如实登记。

## 操作事故登记(验收路自身,如实申报)

1. **01:01 前后裸 pkill 误杀第一路 App bundle 定向轮**(exit 143,杀前全绿,纯误杀)——违反「杀进程先核 parentage」红线;整改 = 之后一律只 kill 自己 spawn 的具体 PID(每轮记录 pid + parentage 先核),并已向 orchestrator 申报。M2-7-3 家族第二件。
2. **01:41 `git checkout c5570b05` 翻共享主工作树**并滞留——炸掉第一路一次 --all 的 App 束(源码 token manifest 测试:编译态 HEAD token 对盘上基线源码 contains=false,机理链吻合,非产线缺陷)。第一路已还原 main/8e3bd59d;本路后续基线臂改用 worktree 隔离(合规形态,受 SPM 约束降级)。M2-7-3 家族第三件:共享状态未隔离。
3. **首轮 GUI 走查误用旧容器构建**(Oct 16 批前码)——`ls -td` 容器排序陷阱,产物新鲜度未按二进制 mtime 核;自纠 = 走查全部作废重跑(HEAD 新构建),测试轮经宿主路径核验有效。教训:容器新鲜度判据 = xctest 可执行 mtime,非目录 mtime。

## 收尾状态

- 工作树:main@8e3bd59d,tracked 零改动(本路落盘文件 = 本报告,untracked)。
- 进程:零 Lightamer 残留(全部 kill 自己 spawn 的 PID);零 xcodebuild/test-direct 残留。
- defaults:`library.ai.labelingMode` 已 delete 还原;`app.cleanTerminate`=0(干净退出自然态)。
- 锁:/tmp/la-audit-repair-all.lock 已由 lane1 释放;/tmp/la-audit-repair-gui.lock 本路已删。
- 本路 --all 证据:/tmp/ar01-acc2-all.log;走查证据 /tmp/ar01-acc2/(即弃域)。
