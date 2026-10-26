# LUMEN-A-ACCEPTANCE — plan A(分析地基 LU2+LU1)第一路独立验收

> 验收轮:2026-10-23 深夜,验收人 = zcode 独立验收 lane。
> 对象 = `75678937`(checker 放行)..`e853cacf`(T8 收口)八 commit 执行链。
> 零源码改动;主树 HEAD `e853cacf` 全程只读(git status 亲证)。

## PASS / 0 blocking + 1 major + 4 minor + 7 obs

**判定:PASS(带 1 major 修复项回注)**。schema v6 迁移安全面(最高优先)全绿;八任务
SC 机检逐条通过;越带 +31 全清单甄别无虚胖灌水(30 法实断言 + 1 法哨兵性复读);
封存面/FIX2③/近亲零 diff 全数亲证;双 bundle 定向测试独立复现执行批终账
(Library 774/4/0、App 974/6/0)。**唯一 major = T7 徽章的动态刷新事件链在真实
装配下断裂**(代码层 + GUI 实测双重坐实,详见 §八)——不 blocking 的理由:
默认中性红线未破(零注记/零产物时网格逐字节现状)、SQL 四案与徽章映射的
Core/模型面测试全绿、无数据损失面;但 T7「徽章刷新挂接点(m-2)」的集成语义
在真机未达成,须修复轮回注。

---

## 一、schema v6 迁移安全(验收方法第 1 项,最高优先)——全过

| 判据 | 实测 |
|---|---|
| 七列 additive DDL 亲读 | ✅ `LibrarySchema.swift:327-337`(createImagesTableSQL 尾段,`default_look_pending` 同位追加;无 DEFAULT/NOT NULL,零回填) |
| imagesColumns 双登记各恰一处 | ✅ 数组尾段 `:201-207` + DDL `:331-337`;第三处出现 = `addCullingAnalysisColumns` 幂等探针函数 `:955-961`(`:899` 先例同形,DECISIONS §1 已申报,非双登记违例) |
| frozen 列零触碰 | ✅ `:170-198` 29 列原样;`git diff` 逐行核仅尾段追加 |
| frozen 测试 29→36 亲读 | ✅ `LibrarySchemaTests` 更名 `testImagesThirtySixColumnsVerbatim`(`:114`)+ 头注 36;`LibrarySchemaV5Tests` frozen 面 `:307` 断言走同一 `imagesColumns` 数组(自动 36);V6Tests 另加显式 `count == 36` 钉 |
| v5 库打开回归(真 fixture) | ✅ V6Tests `makeV5Package` = 手写 v1 DDL + **真实 migrate(1→5) slots**(非手写 v5——与 V5Tests fixture precedent 同形,byte-equivalent 构造路径)→ `ProjectFileStore.open` dispatch → v6;行值零漂移断言(image_path/camera_make/capture_date/rating 四列逐值)+ 七列 NULL 语义断言 |
| pre-migrate 快照缝触发亲证 | ✅ V6Tests ④:`pre-migrate.5-6.bak` 存在断言;ProjectFileStore 本体零 diff(计划红线「禁触迁移 dispatch 本体」遵守) |
| 幂等探针 | ✅ `migrate(5→6)` 双跑零错 + 每列 PRAGMA count==1 断言;半程手写 ALTER(replay 模拟)补齐余下六列(presence+type 契约;ORDER pin 收窄到 fresh-create 面——T8 §10 申报) |
| 腿拼写 | ✅ `from <= 5 && to >= 6` 全仓恰一处(`:894`) |

V6Tests 三法(fresh 36-pin / v5 迁移+快照+零漂移 / 幂等+半程)全部单断言面实在,
动态面待 §七测试轮数字背书(全绿)。

## 二、逐任务机检(T2..T8)

**T2 EXIF(3 法)**——`kCGImagePropertyExifBodySerialNumber` 读点 = ExifSearchIndexer
双 dict 臂(Exif 主 `:200` + TIFF 兜底 `:203`,同一读点两臂 = RESEARCH §风险 4 裁定
本体;ImageIOEncoders `:105` 命中为既有导出面,本批零触)。SubSec 链 = 三键数组
一次循环(Original 主 + SubsecTime/SubsecTimeDigitized 回落恰 2 臂,SC「回落臂
≤2 处」等价满足)。**SDK 键名亲证**:`CGImageProperties.h:568/572/576` 小写
`SubsecTime`、`:704` BodySerialNumber、`:739` 废弃拼写 `SubsecTimeOrginal`——
DECISIONS §2 申报与头文件逐字吻合。写腿 = fillMetadata UPDATE(camera_serial
bindText(9),nil→NULL);insertImage 确实零 EXIF 列(DECISIONS「唯一消费点」
核实成立)。测试:正例(JPEG writer 往返 + `+0.250s` 折算精度 1e-6)/ 缺失 nil /
回落链 + 空 serial 防分组。

**T3 SharpnessAnalyzer(4 法)**——对 Lumen `culling.py:68-94` 逐步对照全一致:
四方向核 8 个(`_FIRST`/`_SECOND` 逐元素核对,含 /√2、/2 权重)、correlation 非
卷积翻转、reflect-101 边界、`_tiles` 32px 均值、`strong = first≥P75 && >2e-5`、
strong 空→0.0(`:161`)、`min(shape)<64→nil`(`:80`,resize 后)、**每方向
log2(P90) 先施 → 四方向 min → `(min+4)/5.5*100` 钳**(review B-1 实式,顺序
`:163-171` 正确);percentile = numpy linear 插值同法;σ0.5 5-tap 高斯与
OpenCV getGaussianKernel 同式(k0=0.7866 验算吻合);INTER_AREA = 精确 area
average 分离两 pass。常量面 grep:1600/2e-5/0.75/0.90/4/5.5 全在册单源;旧式
`log2((min+4)/5.5)` 记法零残留;`import OpenCV`/Metal 零命中。
golden 链:`gen-culling-golden.py`(NumPy Float64 参考,Lumen 公式 verbatim)→
`culling_golden.json` → 测试端 LCG 镜像重生成内容对拍(base 0.05 / resize 0.5
容差分层申报)+ **锚 55.57/27.38 带 ±5 内**(σ1.2 对参考容差 0.2、σ2.0 容差
3.0 + 各自独立 ±5 带断言)+ 两分支 golden(flat→0.0 / tiny→nil)+
min-of-4 方向性(横 smear 塌分、加宽不回升)。

**T4 EyeClosureAnalyzer(3 法)**——注入工厂 `FaceLandmarkProviding`(测试零
`import Vision` 机检过);Vision 在 Library 域恰一文件;阈值 `defaultClosedThreshold
= 0.16` 单源声明恰一处 + analyze 全参注入;`max(右,左)` 语义 + nil→NOT closed
(`(widerOpen ?? 1) < threshold`);MIN_FACE 3% 门与 Lumen `analyse()` 同形;眼睑比
数学 = Lumen `opening()` 形状(欧氏 corner width + max(1e-6) + 均值对距)over
Vision 76 点(x-序配对替代固定 mesh 索引——语义参照非移植体,X3 边界内);
底左→顶左翻转恰一次(provider 边界)。表驱动 3 行(0.4/0.16/0.08)+ 退化 nil 三例 +
strict 阈值臂 + throwing provider 降级。标定集机制 = evidence 模板 + README 在库。

**T5 LibraryAnalysisService(4+4 法)**——三防:QoS `.utility` 恰一处
(`Task(priority:)`)、cap 2 单源 + TaskGroup 滑动窗、activityProbe 注入 +
2s poll 暂停-恢复;防风暴 = resolve/preview 失败 → 空 record(version stamp,
恰一次);懒回填 = serial NULL 才读 EXIF + COALESCE 写腿(camera_serial 与
capture_date 均保已有值);enabled 门 = typed 读(unset=true)+ run 头 + 每批
双查;进度 AsyncStream 多 consumer;Core 零 App import(机检过)。
装配面(review M-2):`LibraryAnalysisWiring` @MainActor + enabled 门 + 探针
合成(exportBusy/aiBusy 闭包)+ `LibraryAnalysisHandle`(BackgroundTaskHandle
第四腿)+ projectChanged 状态机(同 URL 幂等/切换重建/关闭 teardown——WiringTests
四法实断言)。装配点 = WorkspaceHostView(registry @State 所在;LightamerShell
零 diff——DECISIONS §5 申报,判等价且更优:最小触点 + 封存面红利)。
`library.analysis.enabled` 拼写全仓恰一处单源(service.enabledKey;AppPreferences
别名引用同一常量,零第二字面量)。

**T6 BurstAnnotator(4 法)**——五点直译逐点对照 Lumen `library_db.py:822-900`:
①排序键 (make,model,serial)+ts+filename(nil→'' 同 `or ''`);②副本排除
`current.suffix(3)` + ±1e-3 + stem 前缀互含(stem 取末点前 + lower,同
`Path.stem`);③归组 sameCamera + `0<=delta<=2.0` + nil 签名 True(长度不齐
True);④best 比较器 = m-5① 换算 `(ratio ?? 1.0, sharpness ?? -1, -index)`
(nil sharpness -1 与 Lumen `or 0` 在 0-100 值域内决胜等价);⑤blurry = <22 或
组内 max−自身 >14(**组基线 = compactMap.max,与 Lumen `annotate_hints`
`best[burst]=max(...)` 逐字一致**——DECISIONS §6 修正正确性亲核)。签名差 =
zero-mean/(σ+4) 两侧各自 + population std(无 Bessel,同 numpy)→ MAD。
L013:组 id = StableHash FNV-1a decimal string,canonical 串钉死
(成员 id 组序 join|make|model|serial|%.3f 首 ts);`Hasher()` 文件域零命中;
输入序扰动确定性断言。golden = NumPy 参考(m-5① 钉注释在参考脚本)+ 10 行
数据集(gap 边界 2.0/2.0001、副本对、nil 签名、无 ts 永不组)。
`testConstantsMatchLumen` 四常量复读 = 防重标定哨兵(见 §四甄别表)。
StackClustering/CullingToolset 零 diff(git 链级亲证)。

**T7 智能相册四案(6 法)**——FilterField 16→20(四案尾段 additive);op 支配
sharpness [eq,gt,gte,lt,lte] / faces·eyesClosed [eq,gt,gte] / hasBurst [eq]
与 SC 逐条吻合;值 kind faces/eyesClosed/hasBurst=["int"]、sharpness=["double"]
(DECISIONS §7:hasBurst int 1=true,v1 值联合不扩 bool——最小化裁定合理)。
FilterSQL:hasBurst 三域 typed `cullingFieldNotSQLQueryable` guard 先决;
非 .library typed `cullingFieldUnsupportedInDomain`(m-11 两个负测在册);
直比列拼写 == DDL 名(`+i.sharpness = ?` 等三断言);NULL 行不命中语义直比断言。
FilterSortKey.allCases==6 不变断言(ORDER BY 白名单零扩红线)。
徽章:CullingBadgeMapper 纯函数表驱动(best/blurry/closed/成员列表/零注记空 map);
转栈一键 = contextMenu 条件显隐 + `LibraryStore.createStack(memberIDs:)` 断言 +
重复创建 typed 拒(one-image-one-stack)。
Settings 行(review M-3):`settings_analysis_*` 三键,消费 AppPreferences 别名
→ Core 单源常量,零新键字面量。
xcstrings:11 键尾块**纯插入**(`git diff` 零删除行机检 + 总数 2016 + 三重断言
申报吻合);`library_hint_burst_index %lld %lld` = 合法 format 插值键(非
LocalizationValue 禁形)。

**T8 收口**——Project.swift 恰八行数组插入(七 LIB + 一 APP);BUNDLE-MAP 八行
登记;tuist generate 批末位(evidence `t8-generate.log`);SUMMARY/DECISIONS 在库。

## 三、越带 +31 审查专节(重点)

**总账**:计划带 +12..15 → 实账 **+31**(Library 747→774 = +27,App 970→974 = +4),
越带 +16。构成(实测法数)= T1:3 / T2:3 / T3:4 / T4:3 / T5:4+4(APP)/
T6:4 / T7:6 = **31**。SUMMARY 记账行「构成 3+3+4+3+8+4+5」= 30 且 T7 写 +5,
与实际(31 / T7=6)差一——**账面笔误**(obs-1:BUNDLE-MAP 行内法数同源 stale,
`FilterCullingFieldsTests 5` 实为 6;数字修正不改判定)。

**31 法全清单 + 深读 31/31**(超出 ≥30 深读要求)。虚胖甄别表:

| 法 | 断言面 | 判定 |
|---|---|---|
| SchemaV6 ×3 | 36-pin/迁移零漂移/幂等半程 | 实(每法 ≥4 组断言) |
| Exif ×3 | 往返正例+折算精度/缺失 nil/回落+空串 | 实 |
| Culling ×4 | NumPy 对拍/锚带内/min-of-4/percentile+值域 | 容差分层已申报,带内断言独立成立 → 实 |
| Eye ×3 | 表驱动比值/max 判定+阈值注入/门+降级 | 实 |
| Service ×4 | 扫序+COALESCE+notify/防风暴/enabled 单源/暂停-恢复+进度 | 实 |
| Wiring ×4 | 门禁启停/开-关状态机/切换重建/探针+快照映射 | 实 |
| Burst ×3 | golden 全注记面/L013 确定性/边界+排除+nil | 实 |
| Burst `testConstantsMatchLumen` | 四常量复读 | **哨兵性复读(半虚)**——无判别力但定位 = D-LU-10 禁改断言,保留合理(obs-2) |
| FilterCulling ×6 | 四案直比+NULL/hasBurst 三域/域负测/白名单+拼写/徽章表驱动/转栈 | 实(见 obs-3 弱化注记) |

**越带归因判定**:+31 对带 +12..15 的超出 = ①「每 SC 子句一测」的执行口径
(申报理由成立——SC 子句密度本就高于 +12..15 预算的乐观折算);②review M-2
追加的 App 装配面 +4(SC 外但评审强制,正当);③T7 的 m-6/m-11 两评审项各占
一法(正当)。**超出部分全部可追溯到 SC 子句或评审强制项,无 executor 自加
测试域**。M-2 App 装配面(+4)必要性与最小性:Core 不可 import App 的
Registry 适配确需 App 侧承载(BackgroundTaskRegistry 为 App @MainActor 类),
四法分别覆盖门/状态机/切换/探针映射,最小充分。

**plan 外触点审查**(files_modified 之外):`LibraryInspectorModel.swift`(+22)/
`LibraryInspectorView.swift`(+8)= DECISIONS §7 申报的 hasBurst 文案真消费点
(no-orphan 审计强制,typed catch 渲染——合法最小);`PhotoProjection.swift`
(+4)= 两个新 FilterPredicateError case 的 describe 穷举 switch 补臂(编译强制);
`FilterPredicateTests.swift`(+6)= op 支配表与 CaseIterable 面的既有测试数据行
追加(非新方法)。四处均有申报或编译强制依据,无越界改动。

## 四、回归面(验收方法第 4 项)

- **FIX2③**:McpServerController 全程零 diff(diff 75678937..e853cacf 空)。
- **封存面**:LightamerSidecar(schemaVersionCurrent=11 不 bump)/ HistoryStack /
  PixelPipe / Lut3dKernels.metal / DrtRecord / TerminalTailPolicy /
  ExportQueueContract / 六格式导出矩阵 / NodeGraphCommand / V50Order /
  GradeCatalog / SessionThumbnailProvider / LightamerShell——全部零 diff(逐一
  pathspec diff 亲证)。
- **近亲零触**:StackClustering(`:20-64`)/ CullingToolset(MCP list_bursts 域)
  零 diff。
- **xcstrings 尾块**:纯插入(零删除行)+ zh-audit `--check` PASS(1697 source /
  2016 catalog)+ `--self-test` PASS(验收轮独立复跑)。
- **MIT 归属**:CullingAnalysis/EyeClosureAnalyzer/BurstAnnotator 三文件头归属
  注记 + NOTICE 条目 Q(覆盖 T3/T4/T6 + Plan C T1,措辞含「算法思想与常量标定
  源自…实现独立」)。
- **L041**:tuist generate 批末位(T8);L013 组 id;UserDefaults 恰一键
  (`library.analysis.enabled`,全仓 grep 单源)。

## 五、偏差十节逐条判等(验收方法第 5 项)

| # | 偏差 | 判定 |
|---|---|---|
| 1 | T1 代际字面随走(五测试文件 5→6/future 6→7/快照代 N-5→N-6) | **等价**——bump 机械后果,逐文件列举完备 |
| 2 | T2 SubsecTime 小写 s | **等价(必需)**——SDK 头 `:568/:572/:576` 亲证;plan 拼写非 ImageIO 符号,照抄不编译 |
| 3 | T2 ÷1000(非 /1e6) | **等价且更正确**——"250"=0.250s,/1e6 会破副本排除 ±1e-3 判定;与 Lumen `float(".25")` 分数语义一致。规范边角:严格 EXIF 语义 SubSecTime 是任意位小数串(2 位 "25"=0.25s 时 /1000 硬编码错),Lumen 拼小数法天然处理——实践相机恒 3 位,低风险 → **minor-1**(建议按位数缩放或注释登记假设) |
| 4 | T3 cv2 auto-ksize(σ1.2→11/σ2.0→17/σ0.5→5) | **等价**——锚模糊属 fixture 合成面;产线内部 σ0.5 两规则同值不受扰 |
| 5 | T4 VisionEyeLandmarkProvider 改名 | **等价(编译必需)**——AI 域同名冲突,域前缀消歧 |
| 6 | T5 装配点 WorkspaceHostView(非 LightamerShell) | **等价且更优**——registry @State 所在(M2UIW-06 单聚合),上提 = 更大 diff;LightamerShell 零 diff 为封存面红利 |
| 7 | T5 AsyncStream 通知缝定形 | **合规定形**(plan 明示 execute 期 DECISIONS 定形)——但定形实例存在缺陷,见 §八 major |
| 8 | T6 best 比较器双字段 | **等价**——m-5① 预设换算申报路径(D-LU-4 免阈值主路径);nil sharpness -1 与 Lumen `or 0` 决胜等价 |
| 9 | T6 blurry 基线修正(组 max 非 best 自身) | **正确**——与 Lumen `annotate_hints` 实式逐字核对吻合;golden 对拍暴露、双端同修的过程记录诚实 |
| 10 | T8 ImageIO 丢 SubSec 族换 JPEG fixture | **等价**——TIFF reader 丢 0xA421 探针记录在案(测试头注 + DECISIONS §10);读腿面向 JPEG/RAW 内嵌 EXIF = 产线真面;证据链弱点 = 探针 dump 在 /tmp 即弃 → **obs-4**(建议后续将 TIFF 丢弃行为记入 evidence 常驻文件) |
| 附 | T7 hasBurst int + typed 双 case | **等价**——v1 值联合最小化;两 error case 编译穷举强制(PhotoProjection 补臂) |

## 六、定向测试数字(验收方法第 6 项配套)

独立复现轮(验收 lane 自跑,caffeinate 包裹 + machine-guard PASS 后串行):

- `--bundle Library`:**774/4/0**,peakRSS 737MB,182s —— 与执行批 T8 终账逐值一致
- `--bundle App`:**974/6/0**,peakRSS 1276MB,485s —— 与执行批 T8 终账逐值一致
- ΔN:Library +27、App +4 = **+31**(基线 747/970 亲核自执行批 t1 前 log 与
  SUMMARY;全套 `--all` 按 orchestrator 批准制不在本验收,归 Plan C 收口对账)
- 日志:`.work/gsd/phases/lumen-culling/evidence/lumena/acceptance/acc1-{library,app}.log`

## 七、GUI 行为抽验(验收方法第 6 项;AX 驱动 + 截屏,证据 =
`evidence/lumena/acceptance/acc-*.png`)

- ✅ **分析趟端到端真机跑通**:自建 ACCPROJ(Open Project 面板)→ SQL 灌 6 行
  (3 连拍相邻 ts + 3 独立)→ 重开项目触发分析趟 → 6 行全部 stamp
  (`analysis_version=1`;burst 行 sharpness 95.1,scene 行 **0.0 = strong-empty
  分支在真实数据上可观察**;signature 256B;faces=0 合成图无脸合理)。
- ✅ **「照片分析」任务条**(LibraryAnalysisHandle → BackgroundTaskRegistry 第四腿)
  在项目打开后真实渲染(左下角,两轮独立可见)。
- ✅ **Settings 行(review M-3)**:Settings → 默认行为 →「照片分析」节 +
  「后台分析照片」toggle(默认 ON)+ 说明文案,AX 可达、渲染正常
  (`acc-settings-analysis-toggle.png`)。
- ✅ 默认中性红线(反向面):零注记时代网格逐字节现状(打开即查无产物行时
  网格无任何角标渲染路径进入)。
- ❌ **徽章显示未达成**(major,§八)。
- 未走:四案智能相册的 GUI 建相册全流程(交互链深;SQL 直比语义已由
  FilterCullingFieldsTests 集成面覆盖,徽章 mapper 表驱动覆盖注记映射——
  缺口收窄为「GUI 显示」,与 major 合并跟踪)。

## 八、major-1:徽章刷新事件链断裂(T7 集成语义未达成)

**现象**(真机双轮复现):分析产物已落库(6 行 stamp 亲证),网格缩略图正常,
但 burst 行无「n/m + best」徽章、scene 行无「可能模糊」徽章;放大原图逐格核验
(`acc-badge-zoom-absent.png`)。

**断点一(代码层坐实)**:`LibraryStore.analysisEvents()` 的
`analysisContinuations` 是 **actor 实例字段**,而消费侧(WorkspaceHostView
badges 循环)监听 `LibraryStore(store:)` 的一次性实例 A,生产侧
(`LibraryAnalysisService.persistAndTick`)每行 **新建** `LibraryStore(store:)`
实例 Bᵢ 调 `setAnalysis` → 事件 yield 进 Bᵢ 的空 continuation 表 → **通知永不
到达**。T5 SC「additive 通知缝」与 T7「徽章刷新挂接点」的动态语义失效。

**断点二(GUI 层坐实)**:初始 reload(`.task(id: projectURL)` 尾部)在项目
打开瞬间执行,恒早于分析趟产物落库;事件链断后无任何补救刷新。即便跨重启
重开(行已 stamp、reload 应命中),徽章仍未渲染——显示链还有第二个未定位环节
(疑似 reload 时序或 gridModel 就绪次序,修复轮需顺带定位)。

**修复方向建议**(供 executor 修复轮,零源码改动为本验收纪律):
①通知缝去实例化——`analysisContinuations` 提为 static/shared holder(与
LutLibraryStore.shared 先例同形),或 service 持单一 LibraryStore facade 并把
`analysisEvents()` 经 wiring 暴露给消费方;②初始 reload 移到分析趟空闲回调后
再补一刷(或 badges 消费方改订阅同一事件源)。

**不判 blocking 论证**:默认中性红线未破;Core 纯函数面(mapper/annotate)与
SQL 面测试全绿;无数据损失;Settings/任务条/分析趟均真机可用。但修复轮闭环前,
LUMEN-B(选片视图消费徽章)不应起跑。

## 九、minor / obs 清单

- **minor-1**:SubSec ÷1000 假设三位数(§五 #3)。
- **minor-2**:`column(for: .hasBurst)` 返回死拼写 `"burst_annotated"`
  (guard 先抛永不可达;防御值建议改 typed throw,防未来调用点前移生成坏 SQL)。
- **minor-3**:徽章 reload 在 MainActor 全量重算(`burstRows` 全表 + annotate
  同步纯函数),大库首扫 = 每分析行一次 O(n) 主线程重算(万张库可见掉帧;
  建议 debounce/coalesce,与 major-1 修复同批)。
- **minor-4**:分析趟完成后「照片分析」任务条不消失(handle 仅 teardown 时
  finish,run 自然结束不回收)——Plan B 任务面打磨项。
- **obs-1**:SUMMARY 构成账 30 vs 实际 31(T7 5→6);BUNDLE-MAP 法数同源 stale。
- **obs-2**:`testConstantsMatchLumen` 常量复读哨兵(§三)。
- **obs-3**:四案集成测试的 `createAlbum` 只落了 sharpness 一案(其余三案由
  evaluate 直比兜底)——弱化但有判别力。
- **obs-4**:TIFF 丢 SubSec 探针 dump 在 /tmp 即弃(§五 #10)。
- **obs-5**:T1 注释拼写 `ANAYLSIS`(`LibrarySchema.swift:118`,纯注释)。
- **obs-6**:rowGroups 组序 sort 为 Swift 非稳定排序,两组首帧 ts 精确相等时
  组号分配理论上可漂移(best/成员不受影响;Lumen Python 稳定排序)。
- **obs-7**:执行批 issue ref 缺席(SUMMARY 已备案:仓内 issues 未启用,沿
  先前批口径)。

## 十、还原确认

- 主树零改动(git status 生产路径空;HEAD `e853cacf` 不动;报告本身落 .work
  不 commit)。
- 进程零残留(app 已退,caffeinate/test-direct 自出进程清零;后台 guard 轮询
  已停)。
- 产物清理:QSync 侧 ACCPROJ.lalb(+wal/shm/lock)与 src/ 删除;/tmp/lumena-acc
  截图已归档 evidence 后删除;`library.import.rawExtensions` defaults 键恢复
  原态(删除)。
- G4 门处理备案:验收轮前置 guard 首报 24307MB<25GB,清理可再生缓存
  (Homebrew 542MB + 重复更新包 zip ×2 + swiftpm + GeoServices + CoreML 编译
  缓存,合计 ~1.3GB)后 GUARD PASS(25604MiB);未触碰任何用户数据与
  BUILD-HANDOFF 正本容器。
