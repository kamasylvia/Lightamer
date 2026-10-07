# M2-11 VALIDATION INPUT — M2 closeout 签核输入汇总（2026-10-07 执行批 T1/T2 落盘）

> C 档门控第 3 停输入 = 本文件（兼 **M2 milestone 收口签核**——OQ-8-A 单文档
> 收口，`M2-11-VALIDATION.md` 为正本）。结构先例 = `M2-10-VALIDATION-INPUT.md`。
> 状态：**T1 机检 + T2 全 `--all` 终验已落账（本批）；T3 GUI 一轮四义 + T4 SC
> 对账表/挂账总汇编/签核路径随后续批补齐。**

## 一、机检两件（T1，2026-10-07 亲跑）

### 1.1 红线域零 diff（D-M2-11-CONTEXT-6，窗口 = `9586c1b..HEAD`）

checker m6 回注采纳：窗口从 9586c1b 起算（M2-11 归因纯净窗；`c573087..9586c1b`
段 M2-10-07 已核零命中，SUMMARY :64）。窗口锚 = `9586c1b`（feat(app): ai entry
points and zh strings）；窗内 commit 数 = **32**。

| 域 | 命令 | 命中数 |
|---|---|---|
| MCP | `git diff --name-only 9586c1b..HEAD -- App/Sources/Lightamer/MCP/ LightamerCore/Sources/MCP/` | **0**（M2AI-08 零改动终验成立） |
| Export | `… -- App/Sources/Lightamer/Export/ LightamerCore/Sources/Export/` | **0** |
| Version | `… -- LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Library/`（M2-8 版本面 = sidecar v7 + .lalb version_ref） | **0** |

- 全窗产线 diff 亲核：`git diff --stat 9586c1b..HEAD -- LightamerIOP/ LightamerCore/ App/`
  = **唯一 `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（+9/-2）**（M2-11-02
  T5 越界申报面 `bff022e`，Release 断代三修之 DEBUG probe guard）——红线域字面零命中。
- **`semantic_search` defer 维持**（OQ-12-A 签认延续；M2-11 零新增动作、零新验收面）。

### 1.2 M2 族机械扫（KD-1.3，E2 四行实况基线）

`grep -n "^- \[ \]" .work/gsd/REQUIREMENTS.md` M2 段 uncheck = **恰四行**（checker
E2 回注实况确认）：

| 行 | 项 | 关闭路径 |
|---|---|---|
| :41 | M2NODE-03（行内注记已载「严格面激活归 M2-5」+ `TODO.md` M2-5 批指针） | 翻账批补勾 + Delivered 终态注记（**执行批不越权预勾**；若 orchestrator 另有裁决则在签核面显式呈报） |
| :61 | M2DRT-06（行内注记已载 M2-6-3 终验 Delivered + 验收 PASS 指针） | 翻账批补勾（记账件） |
| :99 | M2PERF-01 | 本 VALIDATION 签核后翻账批勾 |
| :100 | M2PERF-02 | 同上 |

其余各族（M2LIB/M2GRADE/M2MASK/M2VER/M2EXP/M2AI）已翻账 Delivered 只做存在性核；
原 PERF 族 :613-620 历史行零触碰（M2-11-04 重述批纪律延续）。

## 二、全 `--all` 终验轮（T2，批准在案：plan 批 + 夜巡授权）

### 2.1 终验净轮（第 3 试，恢复协议后干净轮——终值以此为准）

**`TOTAL|2961/16/0|1081s` 单轮干净绿**（2026-10-07 09:04-09:22，build = R4 验收批
07:40 增量产物，895a352..HEAD 源码零 diff；skip 恒 16 零新增）。

| bundle | executed/skipped/failed | peakRSS | secs | L055 核读 |
|---|---|---|---|---|
| IOP | 471/1/0 | 7709 MB | 188 | 末条 Executed = All tests 总计 ✓ abnormal=0 ANE=0 |
| IOPParity | 362/3/0 | 5980 MB | 353 | ✓（贴线 bundle 5980 vs SPIKE 5788 = +3.3% 方差带内） |
| Layers | 300/3/0 | 1158 MB | 23 | ✓ |
| Library | 581/4/0 | 592 MB | 28 | ✓ |
| Sessions | 279/4/0 | 1649 MB | 75 | ✓ |
| Export | 338/1/0 | 6970 MB | 194 | ✓ |
| App | 630/0/0 | 2831 MB | 220 | ✓ |
| **TOTAL** | **2961/16/0** | max 7709 < 8192 | 1081 | 七日志 `terminated abnormally` 全零 + `ANECCompile` 全零 + 零 MEMFAIL |

- 对账三方（KD-1.4）：2955（M2-10 终值）+ **+6**（02 波 M2DefaultChainPerfTests 2 +
  03 波 FullRenderBenchmarkTests 1 + DrtTailTests 计时 2 + 04 波 MemoryBudgetTests 1）
  = **2961 精确**；bundle 位 = IOP 467+4=471 ✓ / Layers 298+2=300 ✓ / 其余五 bundle
  逐值零漂移 ✓；skip 16 按 test func 计零新增（E3 判定式 `16+Δs` 保形，Δs=0）。
  BUNDLE-MAP 历史行滞后注记：txt 合计 2942 系 M2-9/M2-10 波增行未回写 txt 所致
  （各波验收轮已各自对表），M2-11 增量四文件 `grep -c "func test"` 逐位亲核在案。
- SidecarV5 canary 本轮 **20.190s passed**（慢速绿非超时非崩；vs 晨绿 13.338s）。

### 2.2 PERF-07 终验带内复核（KD-1.2）

净轮 Sessions bundle 内：`PERF07-GATE segments1+2 10k: **0.543s** (gate ≤ 5.000s)`
（Debug harness record；composeSegment 0.524s / claimBatchApply 0.020s / fixture-build
1.655s）——vs 在案 0.490s = +10.8% 机器态漂移**带内即过**（余量 ~9.2×），万张 apply
Delivered 维持。正本 = perf.md §PERF-07 终验带内复核节。

### 2.3 恢复协议实录（checker E1 真链纪律；flake 台账已同步追加行）

终验轮经历三次全套（前两次 App 段崩，第三次干净绿）+ App 独立轮五次（四红一绿）：

1. **崩溃家族**：App bundle 宿主 EXC_BREAKPOINT（SIGTRAP）at `swift_unknownObjectRetain`
   ← `ToneEqualModule.dispatchPack / dispatchLuma` ← PixelPipe.processRec ←
   PipeCache.plane——**ToneEqual encode 路径悬垂 retain = 潜伏缺陷家族**（2 份 .ips
   同栈亲证，证据正本 `profile/appbundle-crash-2026-10-07-0812.ips`）；崩点漂移
   （GUI22 undo 渲染 / DrtPersistence restore 腿 / SidecarV5 writeLeg）= 堆态依赖。
   崩点类隔离全绿（2/0/0、7/0/0、11/0/0）+ App 全量独立轮复绿（630/0/0，210s）。
2. **环境协同因子**：Data 卷 98% 满（4.3GB free）+ Metal shader cache
   `MDB_MAP_FULL` 风暴 + 当日全量重编译风暴；处置 = 盘/缓存卫生（清 Instruments
   ktrace 残留 3.7GB + 测试残留 + 陈旧 DerivedData 容器 1.7GB + Metal cache 重建；
   Data 卷 → 11GB free）+ 缓存回填 → 第 3 试干净轮落地。
3. **产线零 diff 亲证**：9586c1b..HEAD IOP/Core 零命中（唯一 App diff = WorkspaceHostView
   DEBUG probe guard）——崩溃家族为**潜伏旧账非 M2-11 新回归**；**FINDING 登记**
   （error 级，零当场修），归属（验收批 fix 或 V2）= orchestrator 裁决点，随签核面
   呈报。GOAL-STATE Flaky 清算台账已追加两行（家族 + SidecarV5 第 6/7 波）。

## 三、GUI 验收轮一轮四义（T3，2026-10-07 真机走查；证据 = `.work/gui-acceptance/m2-11/` t7-* + MANIFEST 行 15-26）

### 义① AI 面视觉走查（M2-10 交接件 3）

| 项 | 形态 | 证据 |
|---|---|---|
| LCR 设置页（模型五档位/AI 就绪横幅/待发布禁点） | **live ✓** | `t7-lcr-settings.png` |
| ACA 设置页（协议双 radio/Base URL/API 密钥 fail-closed 横幅） | **live ✓** | `t7-aca-settings.png` |
| EnhanceDialog（算法 picker 内置档 + 4×/16× 诚实文案 + 关闭取消腿 Escape→ALIVE） | **live ✓** | `t7-enhance-dialog.png` |
| Image 菜单双入口之编辑器腿 | **live ✓**（AI 超分辨率… 真开 dialog） | 同上 |
| 图库右键双入口腿 | **Manual-Only**（合成右键不开 SwiftUI context menu + LazyVGrid cell 零 AX 暴露——T6 先例同；机器门 = `AIEntryPointTests` marker 冻结集 7 枚） | 通道注记 |
| 评片确认门 sheet（OQ-11-A） | **Manual-Only**（provider-gated——零真实凭据约束不可达；机器门 = AIRatingDescriptionTests 确认门唯一写面断言族）；Inspector AI 区本体 live（请先配置服务商 + 打开设置… = aiSetup 面） | `t7-library-grid-inspector-ai.png` |
| Alcedo 对照截图 | **部分 ✓**（welcome/项目卡对照面；项目内 AI 面深对照 = 1,338 张装载成本 + 无设置页同构面 → Manual-Only） | `t7-alcedo-welcome.png` |

### 义② PERF-04/06 hitch 遗存（T6 Manual-Only 三场景补测）

| 场景 | 形态 | 证据 |
|---|---|---|
| 拖动（T6 在案） | 引用 ✓（hitch >50ms = 0，498 hitch 全单帧 16.7ms；trace ② 归档） | `profile/hitches-export-edit-session.xml` |
| **缩放/平移（本轮补测）** | **live ✓ 双表亲证**：xctrace Animation Hitches 20s attach + Z→scroll-pan→F→pan 驱动——framewait max **14.36ms（>50ms = 0，>100ms = 0）** + potential-hangs 351 行 max 65.5ms（**>250ms = 0**）；frame-lifetime max 74.6ms = 离散 Z/F 全链重渲 by-design 非交互卡顿 | `profile/{framewait,hangs,hitches-frames}-zoompan.xml` |
| 万张滚动 | **Manual-Only**（NSOpenPanel 路径表单遭 IME 截键 + 合成指针不可达——本轮理由充实化；机器数 = 档 A Release 9.7ms/张 ✓ + LRU 预算在案；fixture `scrollsession` 10,000 张在库未消费） | 本行 |

### 义③ L057 面板取消腿真机走查（grep 现扫 16 调用点）

**Live 取消腿 ×9 全 ALIVE**：打开…（FileOpenHelper:77）／New Project…（save, LPC:380）／Open Project…（LPC:392）／**Import Folder… ×2**（grid + editor 语境, LPC:404——**M2-9 F-1 HEAD 不复现亲证**）／Backup Project…（save, LPC:416）／LUT 根选取…（SettingsPages:315, BuiltIn/ 活体在册）／ICC 选择描述文件…（:1200, Profiles 面板）／预设导入文件（PresetManagerWindow:405）／导出…目的地面板（Export 族）。截图 = t7-lutroot-panel / t7-icc-panel / t7-preset-import-panel。

**FINDING-F（error 级，零当场修）**：LUT 面板「导入 .cube…」（LutPanelView:159）取消 → **SIGSEGV `swift release_dealloc` 链**（`Could not determine thread index for stack guard region` = **L057 签名消息逐字**；`.ips` 正本 = `profile/guiwalk-crash-2026-10-07-0937-lut-import-panel.ips`）——L057 家族复活于新点位；归属（验收批 fix 或 V2）= orchestrator 裁决，随签核面呈报。

**Manual-Only 三行**：预设导出 save-panel（hover 门控合成不可达；同族 NSSavePanel 已由 Backup Project 腿 live 覆盖）／relink 两处（SidebarView:979 + RelinkSheetView:184，需 offline/missing 状态构设）／Copy Adjustments 外部 .lra 腿（grid face 菜单 disabled）；Catalogs chooseLocation = 剥离门隐藏 by design。

**走查新 FINDING-G（minor/zh 面）**：标记 菜单裸键直出——`metadata_rating_1..5` / `metadata_color_0..5` 未本地化（F-2 插值键陷阱同族，动态查表键 scanner 不可见）；登记随 Phase 15 zh 清算批。

### 义④ DRT 走查观察项遗存（M2-6-3 五项）

| 项 | 形态 | 证据 |
|---|---|---|
| 4. EOTF 切换时延（FULL 大图） | **live ✓**（Gamma 2.2→BT.1886 实切，100MP 预画布即时重渲无卡顿观感） | `t7-drt-eotf-bt1886.png` |
| 5. 预设三件套手感（单 commit 语义） | **live ✓**（单步 Cmd+Z 回退 BT.1886→Gamma 2.2；Look Standard/Tonescale/Creative White picker 结构在案） | `t7-drt-eotf-undo-revert.png` + `t7-drt-panel.png` |
| 联动吸附活证 | Rec.709 空间 EOTF 菜单仅出 BT.1886/Gamma 2.2（legalEOTFs 单源 live） | 走查注记 |
| 1. HDR 屏实机 + 降容显示 | **维持挂账**（本机 BenQ PD2705U = SDR 屏；HDR 编码态菜单滚动合成不可达） | 本行 |
| 2. PQ canvas mat 深浅 | **维持挂账**（同上 HDR 编码态不可达） | 本行 |
| 3. Post 四件 display 域强度 | bloom/grain 已停用态在案（`t7-lut-pane-builtin40.png` 外观页）；实开观感 = Manual-Only | 本行 |

### O-1/O-2 观察行（M2-11-04 移交）

- **O-2 瞬态峰走查 ✓**：Z(100%) 腿 `phys_footprint_peak: 8557 MB`（`profile/o2-footprint-z100.txt`）——vs R4 登记值 8556MB **±1MB 稳定复现**；稳态 2982-2984MB（<3GB 口径①带内）。
- O-1（RAF warm 双峰）— bench 层数字在案未变；本轮 GUI 编辑会话未观测到上屏态双峰（非计量结论，注记）。

## 四、M2PERF-01 SC 对账表 + M2PERF-02 终验 + 挂账总汇编 + 签核路径（T4）

### 4.1 M2PERF-01 逐门三列对账（重述口径 = REQUIREMENTS :99 六要素；三态判据 KD-5，禁硬签）

| 门 | 门值 | 证据（数字正本 = perf.md） | 判定 |
|---|---|---|---|
| ① PERF-01 链面（OQ-5-A M2 默认面） | 静态 warm + 拖动两档 vs 16.6ms | ARW 13.4/13.2ms（Debug/Release）达标；RAF 14-42 带/37.2ms（O-1 双峰噪声）；拖动 color ARW 8.6-8.9 双构建达标（RAF best-round 9.7-11.9 达标）；denoise ~65/~57.5ms 未达 + OQ-7-A bounded 降载三档全不达 revert | **达标（ARW 全门 + 拖动 color）+ 观察项（RAF O-1）+ 挂账（denoise → V2 语义「拖动降档预览」）** |
| ② PERF-05（OQ-6-A 缩略桶 512 门） | open→512 首帧 warm ≤500ms | 0.172s(RAF)/0.194s(ARW)，余量 2.6-2.9× | **达标**（fit(2560) = 记录档观察项 2.08-2.8s；RAW9 编译冷 2.62s 首编译态单列不入门；渐进显示 = 观察项） |
| ③ PERF-02（OQ-1-A 三分法） | ①GUI 稳态 ≤3GB ②FULL 窗口断言 ③宿主 8G 运行门 | ①三轮中位 1975MB PASS（R4 1856 复测带内）②MemoryBudgetTests bilateral FULL 门 + testFullToneEqualMemoryBudget 零触碰在册绿 ③RSS_LIMIT_MB=8192 零触碰；净轮 max peak 7709MB 零 MEMFAIL | **三口径全达标**（O-2 瞬态峰 8.6GB = 观察项不入门） |
| ④ PERF-03（Instruments 落账） | trace 系统级归档 + 杠杆记录 | trace ×2 盘上归档（编辑 33MB + hitch 432MB）+ TRACE-NOTES | **达标** |
| ⑤ PERF-04（交互零卡顿） | hitch >50ms = 0 + MainActor ≥250ms = 0 | 拖动（T6）= 0/0 ✓；**缩放/平移（本轮补测）framewait max 14.36ms = 0 + hangs >250ms = 0 ✓**；万张滚动 Manual-Only | **达标（两场景本轮补齐）+ Manual-Only 一行（万张滚动）** |
| ⑥ PERF-06（懒加载万张） | 档 A 60fps 桶 / 档 B 记录 | 档 A Release 9.7ms/张 ✓；档 B 2.70s/张（预算上沿外 ~35%，吞吐由档 A 承担） | **达标（档 A）+ 记录档（档 B）** |
| ⑦ PERF-07（批量 apply ≤5s） | 万张 apply 门 | 净轮带内复核 **0.543s**（≤5s 余量 ~9.2×；vs 在案 0.490s +10.8% 机器态漂移带内） | **达标（Delivered 维持）** |
| ⑧ SpektraLab ①（OQ-2-A 硬门） | FULL 桶全链 warm <1s | Release 168.2ms(60.2MP)/300.6ms(100MP)，余量 5.9×/3.3×；KD-4 杠杆未触发（DRT 尾非主导） | **PASS** |
| ⑨ SpektraLab ②（OQ-2-A 硬门） | 尾平面命中重渲 ≤10ms | 同参全命中 0.021ms / 单参 tick 重放 5.009ms | **PASS** |

### 4.2 M2PERF-02 终验（REQUIREMENTS :100）

- 终验净轮 **`TOTAL|2961/16/0|1081s`** 单轮干净绿（§2.1 七 bundle 表 + L055 核读 + 三方对账 2955+6 逐位 ✓）。
- 机检四件：红线域零 diff ✓（§1.1）／M2 族 uncheck 四行 → 翻账批清零（§1.2）／L055 七日志 abnormal=0 ✓／零 MEMFAIL ✓。

### 4.3 五 plan 交付索引（M2-11-01..05）

| plan | 交付 | SUMMARY / DECISIONS | 验收 |
|---|---|---|---|
| M2-11-01 | flaky 清算批（脚本两修 `6031e1e` + 缩略图硬化 `f9284ca` + 台账立表） | 01-SUMMARY / 01-DECISIONS | PASS |
| M2-11-02 | PERF 计量批（PERF-01/05/03/04/06 数字落账 + OQ-7-A revert + 档 B 复核 + `bff022e` Release 三修越界申报） | 02-SUMMARY / 02-DECISIONS §1..7 | PASS |
| M2-11-03 | SpektraLab 两硬门（`fdc9ea0`+`37eb603` 双 PASS 无降门） | 03-SUMMARY / 03-DECISIONS | PASS |
| M2-11-04 | 内存三分法（GUI 稳态 1975MB 三轮 + 断言面 +1 + M2PERF 重述 `88ffba8`） | 04-SUMMARY / 04-DECISIONS §1..5 | PASS |
| M2-11-05 | closeout 本批（机检 + 终轮 + GUI 轮 + VALIDATION-INPUT/VALIDATION + 翻账） | 05-SUMMARY / 05-DECISIONS | 本 VALIDATION 即验收面 |

### 4.4 M2 挂账总汇编（KD-3 单一移交清单；各 phase 原文不改写）

**Maintenance 栏（引擎级后手，触发条件在案）**

| # | 项 | 来源锚点 |
|---|---|---|
| M1 | 100MP 级增强内存行带流式（E3）；`c573087` 两阶段 engine 已闭 12MP 档 | M2-10-VALIDATION 挂账#3 + OQ-4-A |
| M2 | denoise 拖动本征成本（~65/57.5ms 未达；decimate 三档试尽 revert；剩余杠杆 = kernel 重写/时域复用 = C 案；V2 语义「拖动降档预览」） | M2-11-02 §OQ-7-A + perf.md |
| M3 | Follow Edges V2（脊线预提取/亚像素质心/自适应步长；snap 熔断态） | M2-7-3 SUMMARY + AGENTS M2-7 |
| M4 | **ToneEqual encode 路径悬垂 retain（潜伏崩溃家族；.ips ×2 同栈；当日 5 红 2 绿 + 盘/缓存卫生后干净轮；产线零 diff = 旧账非回归）**——**归属 orchestrator 裁（验收批 fix 或 Maintenance）** | M2-11-05 §2.3 + GOAL-STATE Flaky 台账追加行 |
| M5 | **L057 面板取消腿家族（LUT 导入 .cube 取消 SIGSEGV，签名消息逐字；F-1 Import Folder HEAD 不复现）**——归属同上 | 本文件 §三义③ FINDING-F |
| M6 | 100% 缩放腿瞬态峰 O-2（6.3-8.6GB；TilingPlan 显示腿杠杆评估；16GB 机 swap 压力时触发处置） | M2-11-04 perf.md §O-2 + 本轮 §O-2 复现 |
| M7 | RAF 100MP warm 双峰噪声 O-1（14↔42ms 两态跳变未定位；spike 候选） | M2-11-02 perf.md §O-1 |

**V2/观察项 栏（M2-10 十项逐项落位 + M2-11 新增）**

| # | 项 | 落位 |
|---|---|---|
| V1 | M2-10 #1 Release digest 上架回填 | 维持（上架后零 UI 改动解锁） |
| V2 | M2-10 #2 命中质量实图走查 | 维持（headless 盲区；LCR 页视觉半边本轮关闭） |
| V3 | M2-10 #3 真批量增强队列 | 维持（需求出现再立项） |
| V4 | M2-10 #4 「衍生自」徽标 UI | 维持（join 键已定案 D7） |
| V5 | M2-10 #5 设置页/对话框视觉走查 | **本轮关闭**（义① LCR/ACA/Dialog live 证据） |
| V6 | M2-10 #6 SettingsDeepLink 已开窗口限制 | 维持（v1 已知） |
| V7 | M2-10 #7 worker 编译缓存冷启动观感 | 维持 |
| V8 | M2-10 #8 100MP 级增强内存 | = M1 同源落位 |
| V9 | M2-10 #9 性能实测表 → M2PERF-01 | **本轮关闭**（本 VALIDATION §4.1 兑现） |
| V10 | M2-10 #10 flake 台账 | **本轮关闭**（M2-11-01 清算 + 台账观测收口；崩溃家族新行追加见 §2.3/M4） |
| V11 | M2-11 新增：渐进显示观察项（不强制） | PERF-05 重述注记 |
| V12 | M2-11 新增：fit(2560) 首帧观察项（2.08-2.8s，checker m2 归类） | §4.1 门② |
| V13 | M2-11 新增：RAW9 编译冷 2.62s 首编译态单列 | PERF-05 注记（缓存态不可复现） |
| V14 | M2-11 新增：标记菜单裸键（metadata_rating_N/color_N 直出，F-2 同族） | FINDING-G → Phase 15 zh 清算批 |
| V15 | M2-11 新增：zh-audit 提取器硬化（continuation 漏提） | Phase 15 清算批 |
| V16 | M2-11 新增：万张滚动 Manual-Only（通道理由） | §义② |
| V17 | 既有：冲突档选择器 UI 缺口 / yiyin M2 页节 / peak-ICC / UltraHDR / EXR / 全 recipe 预设 / YIYIN-09 | M2-9 VALIDATION 挂账（原文不改写） |

### 4.5 签核路径（C 档第 3 停）

- **verify-work 输入** = 本 INPUT + `M2-11-VALIDATION.md`（正本）+ 五 plan SUMMARY/DECISIONS + `perf.md`（数字正本）+ `MANIFEST.md`（GUI 证据）+ REQUIREMENTS M2PERF/M2DRT-06/M2NODE-03 终态。
- **呈报裁决点（禁静默）**：①M2NODE-03 翻勾——行内注记「严格面激活归 M2-5」+ `TODO.md` M2-5 批「add 面严格化」指针在案，checker E2 判「翻勾逾期带指针件」→ 翻账批拟补勾 + Delivered 注记（指针 = `TODO.md` M2-5 批 + `M2-5-3-ACCEPTANCE.md`）；**若 orchestrator 另有裁决（严格面语义未满）则该行保持 uncheck 收口**。②error 级 FINDING 两枚（M4 ToneEqual / M5 L057 家族）——「零 error 级 FINDING」判据 = 无未登记 error，两枚均已登记带证据 → 照签核纪律可放行，归属裁决随晨审。
- **夜间授权在案**（D-07-3-T5-1 先例 + 用户「开跑，不要停」）→ INPUT 落盘即同批落签 VALIDATION（status validated）+ 翻账批；晨审可推翻。
