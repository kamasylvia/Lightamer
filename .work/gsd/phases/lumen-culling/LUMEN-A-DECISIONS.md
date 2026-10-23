# LUMEN-A DECISIONS — 裁定与偏差记录（执行批 2026-10-23）

> 正本计划 = 同目录 LUMEN-A-PLAN.md；OQ 裁决正本 = CONTEXT.md（D-LU-1..10）。
> 本文件只记执行期偏差与新钉；计划内已定值不重抄。

## §1 T1 迁移测试字面量族的代际随走（机械后果，M-1 范围延伸申报）

review M-1 只列了 frozen 断言（29→36 更名）；实际 v5→v6 bump 的机械后果
还覆盖五文件的版本/快照代字面量——全部随代际走，零行为改动：

- LibrarySchemaTests：fresh-create/重开/全链终版 5→6；future 6→7；快照代
  `pre-migrate.3-5 → 3-6`、`1-5 → 1-6`、`2-5 → 2-6`；`testImagesTwentyNine…`
  更名 `…ThirtySix…` + 头注 29→36。
- LibrarySchemaV5Tests：fresh create 5→6；v4 dispatch 快照代 `4-5 → 4-6`；
  全链终版 5→6；future 测试更名 `…Seven…` + stamp 6→7 + 文件留守值 6→7。
- LibraryDocumentTests：fresh/zero-byte 5→6；future 6→7。
- DefaultLookTests：快照代 `1-5 → 1-6` + 终版 5→6。
- ProjectLockTests：三处快照代 `3-5 → 3-6`（两处 no-snapshot 负断言 +
  一处存在断言）。
- 判据口径：`schemaVersion = 6` 恰一处；`from <= 5 && to >= 6` 恰一处；
  七列在**两登记面**（DDL + imagesColumns）各恰一处（M-1 判据），另在
  schemaVersion 注记/迁移函数各一次（:899 先例同形，注释不计入面）。

## §2 T2 两项

- **ImageIO 键名样张核对结论（风险 4 消解）**：`kCGImagePropertyExifBodySerialNumber`
  在 SDK 头文件实存（CGImageProperties.h :704）；SubSecTime 族常量拼写 =
  **"SubsecTime"**（小写 s，:568/:572/:576；:739 为废弃拼写 `SubsecTimeOrginal`）
  ——计划文本的 "SubSecTime" 非 ImageIO 符号，已按 SDK 拼写修正。
- **折算公式偏离**：计划文字 "subsec/1e6" 为转录滑误。EXIF SubSecTime =
  毫秒数字串（"250" = 0.250s），折算 = /1000 ——与 Lumen
  `SubSecDateTimeOriginal` 的 `float(".25")` 分数语义一致。/1e6 会把 250ms
  折成 250µs，破坏 ±1e-3s 副本排除与同秒帧排序。
- **写腿落点**：计划预期两文件（ExifSearchIndexer + LibraryStore:382）；
  核实 `insertImage` 不写任何 EXIF 列（camera_make 族全靠索引趟
  fillMetadata UPDATE）→ 唯一消费点 = fillMetadata，LibraryStore 零触。

## §3 T3 三项

- **cv2 auto-ksize 规则（参考实现对拍定位）**：现代 opencv 的
  `GaussianBlur(img,(0,0),σ)` 自动核 = radius `round(4σ)`（实测 σ1.2→ksize
  11、σ2.0→17、σ0.5→5；对照 `cvRound(σ*8+1)|1`）。参考脚本与锚测试镜像此
  规则；管线内部 σ0.5 两规则同值（ksize 5），产线不受扰。
- **锚点带内达成路径**：标定值 55/30 来自 Lumen 自然图；合成内容按
  内容配方调（LCG 噪声梯 + 32px checker bars 0.15 + 梯度 0.1 → 归一 →
  σ0.65 预模糊），锚实测 **55.57 / 27.38**（带 ±5 内）——公式常量零触碰
  （D-LU-10），内容配方 = fixture 资产非公式参数。
- **精度容差申报**：产线 Float32 vs 参考 Float64 在 P75 tile 选择边界发散
  ——golden 容差分层：base 0.05 / resize 0.5 / σ1.2 锚 0.2 / σ2.0 锚 3.0
  （重模糊后能量近 2e-5 地板，选择敏感性放大）；**带内断言（真正的 SC 面）
  两锚各自独立成立**。Reference-vs-cv2 逐件验证：filter2D/tiles/percentile
  位级一致、高斯 ≤1.4e-7。

## §4 T4 两项

- **类型重名**：`VisionFaceLandmarkProvider` 与 AI 域既有同名类型冲突
  （AIMaskService）→ 产线名 `VisionEyeLandmarkProvider`（域前缀消歧）。
- **threshold 语义**：`defaultClosedThreshold = 0.16` 单源声明一次；
  analyze 全参注入；无脸/无 landmark（widerOpen nil）→ NOT closed（提示
  臂不在无数据面误报）。标定集机制 = evidence 模板 + 流程 README（样张
  不入仓，LENS-04 T4 同款）；.work evidence 目录按仓策略 gitignored——
  模板正本在工作树，提交面只含 README 所指的产线常量。

## §5 T5 三项

- **装配点偏离（review M-2 触点修正）**：装配落 **WorkspaceHostView**
  （registry 的 @State 所在，M2UIW-06 单聚合纪律），非计划所列
  LightamerShell.swift——registry 上提至 controller 是更大 diff。**LightamerShell
  全程零 diff**。
- **notify 缝定形（review m-2）**：`LibraryStore.analysisEvents()`
  AsyncStream（多 consumer、unbounded 缓冲）+ `setAnalysis` 写后 yield；
  消费方 = WorkspaceHostView 的徽章 stale-until-refresh。Lumen 无对应通道
  可抄（其 Qt signal 直接系 UI），我方以缝注入保持 Core 无 UI 依赖。
- **Core-App 边界**：Registry 适配 = App 侧 `LibraryAnalysisHandle`
  （@MainActor BackgroundTaskHandle 第四腿）；Core 只暴露
  `progressEvents()`；cancel 走 handle.onCancel → `service.cancel()`。
  service init 为 async（projectDirectory 从 actor 化 store 读出后固化）。

## §6 T6 三钉（review m-5）+ 一修正

- **① best 比较器**：双眼维 = **相对开度 ratio**（`maxRatio ?? 1.0`——nil
  视为全开，Lumen `not None == True` 的直译对应），sharpness 降序
  （nil = -1），组内序升序（稳定）。参考脚本按此钉实现对拍（非 Lumen 布尔
  桶——D-LU-4 主路径语义换算申报）。
- **② nil 签名**：`similar` nil/长度不齐 = True（Lumen 原样——未分析行
  可纯时间归组）。
- **③ 组 id 输入 canonical 串**：`"<成员 id 按组序 ',' join>|<make>|<model>|
  <serial>|<%.3f 首 ts>"` → StableHash FNV-1a 64 → decimal string。排序键
  （相机三元组+ts+文件名）固定组序 ⇒ 同数据集任意输入序同 id（测试钉死）。
- **修正（golden 对拍捕获）**：blurry 的组基线 = **组内 max sharpness**
  （Lumen annotate_hints 的 `best[burst] = max(...)`），非 best 帧自身
  sharpness——首版参考与产线同错，对拍 id3 用例暴露后双端同修。

## §7 T7 四项

- **FilterValue 无 bool kind**：hasBurst 值 = int（1 = true）；合法 kind
  `["int"]`，op 支配 `[.eq]`。bool kind 属 FilterValue 联合扩展（additive
  case + Codable），v1 不扩（decode 面最小化）。
- **typed 臂错误面**：两个新 FilterPredicateError case
  （`cullingFieldUnsupportedInDomain(field:domain:)` /
  `cullingFieldNotSQLQueryable(field:)`）；PhotoProjection.describe 穷举
  switch 同批补臂（MCP filter 工具的同一翻译层）。
- **hasBurst 文案的真消费点**：审计 no-orphan 强制真实 usage——落
  LibraryInspectorModel.applyArms 的 typed catch（`filterApplyError` 面板
  渲染，LibraryInspectorView 条件行）。智能相册 builder 置灰 UI 仍属
  Plan B 选片面（文案已可达）。
- **xcstrings 插入格式**：文件尾键块 = 2sp 键缩进代（与
  rawdecode_raster_* 同代）；插入脚本内置三重断言（历史键 byte 相等 /
  总数 = 2016 / 新键在册）。

## §8 键登记（红线 11）

- `library.analysis.enabled`（Bool，缺省 true）——本批唯一新 UserDefaults
  键；单源 = `LibraryAnalysisService.enabledKey`（Core），App 侧
  `AppPreferences.analysisEnabledKey` 为别名，Settings 页经注入实例读写
  （KD-4：body 零直读）。
- xcstrings 新键 11（tasks_analysis_* 3 + library_hint_* 4 +
  library_filter_hasburst_unsupported 1 + settings_analysis_* 3）——登记
  于 xcstrings 尾块，zh 双语齐。

## §9 其他执行注记

- **G4 磁阻**：T7 前机器门 G4 短缺 217MB——清理两个陈旧 Lightamer-*
  DerivedData 容器（非 BUILD-HANDOFF 正本）+ 自愈 ModuleCache 家族
  （~1.5GB）后放行；主容器 -dgzsvdww 未触。
- **禁触面零 diff 复核**：McpServerController / LightamerShell /
  CullingToolset / StackClustering / SessionThumbnailProvider / sidecar
  schema（v11 不 bump）/ HistoryStack / PixelPipe / Lut3dKernels.metal
  ——逐 commit diff 可核，本批零触碰。
- **--all 未跑**（orchestrator 批准制）；本批验收 = Library + App 双 bundle
  定向全绿。

## §10 T8 首注册轮捕获（T2 测试车淘汰 + V6 断言面修正）

- **ExifSerialSubsecTests 载具淘汰**：手织 TIFF（含最小图结构族 12 条）被
  ImageIO TIFF reader 读取后 **SubSecTime 族 tag 完全不上浮**
  （CGImageSourceCopyPropertiesAtIndex 的 {Exif} dict 只出
  BodySerialNumber + DateTimeOriginal——探针 dump 留档 /tmp，行为记录
  在案）；JPEG writer/reader 往返则 BodySerialNumber 与
  SubsecTimeOriginal 双双保真 → 三个用例整体换 JPEG writer fixture
  （ExifFoldTests 先例形）。读腿产线代码零改（read face 面向的正是
  JPEG/RAW 内嵌 EXIF 族）。**执行面教训**：T2/T3 落盘的测试文件在 T8
  注册前从未编译——T8 首注册轮 = 唯一真编译轮（L041 的镜像面：临时注册
  验证（T3..T7 采用）是de-risk 正道，T2 时代未采用即欠此账）。
- **LibrarySchemaV6Tests 半程重跑断言面收窄**：手写 ALTER 在批序之外时
  列物理序不必等于数组尾序——probe 契约 = 存在性+类型（fresh-create 面
  独占 ORDER pin）；半程 fixture 改手写首列（analysis_version）保序。
- **T8 末轮机检**：Library 774/4/0 + App 974/6/0（测试宿主均正常退出，
  零 MEMFAIL）。

## §11 修复轮：§八 major-1 徽章事件链（issue #1，HEAD e853cacf 基线）

- **根因注记**：`LibraryAnalysisService.persistAndTick` 每行新建
  `LibraryStore(store:)` 实例调 `setAnalysis`——`analysisContinuations`
  是 actor 实例字段，事件全部 yield 进一次性实例的**空表**；消费侧
  （WorkspaceHostView 徽章循环）订阅的是自己 ad-hoc 建的另一实例——
  两个实例永不相交，T5 SC 通知缝动态语义失效。DB 腿经共享
  ProjectFileStore 照常落盘 =「数据在、徽章不出」表型的结构性来源。
- **修复形态（三缝一线）**：
  1. `LibraryAnalysisService` 新增 `public private(set) var
     libraryStore: LibraryStore`——init 注入（`libraryStore:` 参数，nil
     = 自建一份兜底），`persistAndTick` 改走 `libraryStore.setAnalysis`，
     每行新建形态根除；
  2. `LibraryAnalysisWiring` 装配点建一份 `LibraryStore(store:)` 注入
     service，并暴露 `analysisEvents() -> AsyncStream<[Int64]>?`（转经
     `service.libraryStore` 取流；nil = 分析面 inert）——消费方订阅
     THE SAME actor 实例（验收 §八处方①「service 持单一 facade + 经
     wiring 暴露」臂）；
  3. WorkspaceHostView `.task(id:)` 徽章循环改订阅 `wiring.
     analysisEvents()`（原 ad-hoc `LibraryStore(store:)` 删除）。
  编排时序不变：projectChanged（起趟）→ 首刷 reloadCullingBadges →
  订阅事件循环；起趟与订阅窗内的写由首刷覆盖。
- **测试（红→绿）**：新 `testAnalysisEventReachesSubscriberThroughWalkPersist`
  （LibraryAnalysisServiceTests §⑤）——订阅者实例注入 service + 身份
  钉（`===`，per-row 新建形态先死在这行）+ 走完整趟后断言事件到达订阅
  者流 + sharpness 非 nil。**修复前红**：同测试（无注入形态）RUN RED——
  行已 stamp（前置过）、事件未达（断言 250 行失败），红轮日志 =
  `evidence/lumena/lumen-a-fix/fix-red-run.log`；修复后绿 5/0/0
  （fix-green-run.log）。
- **回归**：`--bundle Library` 775/4/0（774 带 +1 新测试，4 skip 不变，
  零 fail，峰值 667MB 零 MEMFAIL；fix-lib-bundle.log）。App bundle 未跑
  （改动面 WorkspaceHostView/LibraryAnalysisWiring 编译由 build-for-
  testing 全量验证通过；App 面行为 = 本节 GUI 复验）。
- **GUI 复验（行为级，真机；证据 = `evidence/lumena/lumen-a-fix/`）**：
  自建 BADGECHK 工程（Core 三文件直编 createproj 工具建 .lalb——M2-7
  探针先例形，ProjectFileStore+LibrarySchema+SQLiteHandle+SingleWriter
  Lock+LibraryError 自洽闭包）+ 6 行未分析行（3 连拍相邻 ts + 3 独立，
  棋盘/纯色 fixture）→ 打开项目 → **同一会话内**徽章渲染：
  `fix-badge-zoom.png`（原生分辨率裁切）= 「连拍 1/3 ★」「连拍 2/3」
  「连拍 3/3」+ 两张「可能模糊」+ 独立清晰行零徽章；「照片分析」任务
  条在屏（fix-badge-grid-live.png）。SQL 核（fix-sql-verify.txt）：
  6 行 analysis_version=1，sharpness 95.1（棋盘）/0.0（纯色，strong-empty
  谱系），signature 256B，COALESCE 保 serial——与验收轮 §七数值逐位同。
- **§八断点二归因**：初始 reload 恒早于分析趟产物 + 事件链断后无补救
  刷新 = 徽章不出；跨重启仍不出 = 重开触发的新趟事件同样进空表（同
  断点一覆盖，非独立第二缺陷）。事件链接通后 live 路与 reopen 路同用
  一条 reload 缝，无需独立改动。
- **执行注记**：①用户正机 Ghostty 会话活跃——GUI 驱动全部改 AX 菜单/
  面板路径（File→Open Project… + Go-to-Folder AX setValue 绕拼音 IM），
  坐标点击一次误触 Ghostty 后即改道；②`library.recentProjects` 曾被
  临时指向 BADGECHK，已还原（原列表的 /tmp editor-probe 死路径项已被
  控制器死路径清扫语义覆盖，只还原活路径 ACCPROJ×3）；③机器门 G4 本轮
  贴线（24.88GB vs 25GB 门，purge 波动放行）——未清任何容器。
- **ACP 0 字节旁证**：`QSync/ACCPROJ.lalb` 现为 0 字节文件（验收轮
  §十还原后的残壳，mtime 非本批）——用户点开必报错，本批未动（挂给
  orchestrator 知会）。
