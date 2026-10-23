---
phase: lumen-culling
plan: "LUMEN-A"
title: "plan A — 分析地基（LU2+LU1）：T1 schema v6 七列 additive 迁移 + imagesColumns 双登记 + 快照缝回归 / T2 EXIF serial+SubSecTime 读腿 / T3 SharpnessAnalyzer+Signature16 纯函数 golden / T4 EyeClosureAnalyzer 眼睑比 + 标定集机制 / T5 LibraryAnalysisService 分析趟（暂停语义 + App 装配缝） / T6 BurstAnnotator 连拍注记 golden / T7 智能相册四案 + FilterSQL 直比 + 网格徽章 + Settings 行 / T8 收口"
wave: 1
depends_on: []
autonomous: true
requirements: ["research 正本 = phases/lumen-culling/RESEARCH.md（ee73da34）§UQ-LU2/§UQ-LU1", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LU-1..10 全按推荐 + X1..X5 设计承接 + hazards 三条 + 红线 17 条 + 转写勘误四条〔① FilterField 16 案〕+ 修复轮修订节〔LENS-CULLING-PLAN-REVIEW 回注已落位〕）", "基线 4112/40/0（r12-repairs R3 终态——CONTEXT §Phase Goal）；本 plan 分账 +12..15", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 LUMEN-B 起跑", "执行排 F0'-prod + LENS-01 验收链收口之后（CONTEXT 红线 6）"]
success_criteria: "SC 全可机检——T1：schemaVersion=6 单点 + images additive 七列（analysis_version/sharpness/faces/eyes_closed/signature BLOB/face_boxes/camera_serial，frozen 列零触碰）+ imagesColumns frozen 数组（:156-186）尾段同批追加（七列双登记点——review M-1）+ 两 frozen 测试断言 29→36 更新（LibrarySchemaTests:114 / LibrarySchemaV5Tests:307——review M-1）+ migrate `from<=5&&to>=6` 腿幂等探针 ALTER（:899-909 先例）+ v5 包迁移/半程快照重跑/旧数据零漂移测试族 + ProjectFileStore 快照 hook 存在断言（零新机制）；T2：readProperties 补 BodySerialNumber（Exif dict 主 + TIFF 最佳努力）+ SubSecTimeOriginal（回落 SubSecTime/SubSecTimeDigitized）折 captureDate（亚秒 REAL）+ ExifRead additive 两字段 + 索引趟写腿 + 合成 EXIF fixture 正例/缺失 nil 测试；T3：SharpnessAnalyzer（1600px 灰度 + σ0.5 + 32px 块四方向一阶/二阶导数能量比 + P75&>2e-5 结构块筛选 + 每方向 log2(P90 比值) → 四方向 min → (min+4)/5.5*100 钳 0-100〔Lumen culling.py:84-87 实式——review B-1〕+ strong 空→0.0 / min(shape)<64→nil 两分支）+ Signature16（16×16/256B）——公式参数逐字直译（D-LU-10 禁重标定）+ MIT 归属头 + Lumen 同输入 golden（清晰度标定锚 1.2px≈55/2px≈30 带内 + NumPy 参考双写）；T4：EyeClosureAnalyzer（VNDetectFaceRectanglesRequest + VNDetectFaceLandmarksRequest 76 点 → 眼睑比 = 上下点对纵向跨度均值/眼角横向跨度，max(右,左) 语义）+ 注入式 request 工厂 + 合成 landmarks 表驱动（睁/闭/侧脸漏检）+ 阈值注入（默认 0.16 语义）+ 标定集机制落 evidence（不入 CI 门）；T5：LibraryAnalysisService actor（扫 analysis_version<CURRENT 行序 → 内嵌预览 1600px → sharpness/signature → faces>0 才 Vision → setAnalysis 批写 + additive 通知缝〔review m-2〕）+ QoS .utility + 并发 cap 2 + 导出/AI 活跃挂起/空闲恢复 + BackgroundTaskRegistry 进度/取消（App 侧 @MainActor 适配 handle——review M-2）+ 不可读写空分析防重试风暴 + UserDefaults library.analysis.enabled（typed 读 + 注入式）+ App 装配面（项目打开启动 + enabled 门 + 导出/AI 活跃探针注入——KD-5 sink 装配先例形，review M-2）；T6：BurstAnnotator 查询期纯函数直译（(make,model,serial)+ts+文件名排序键 / 副本排除 ±1e-3s stem 前缀互含 / ≤2.0s + 签名 MAD≤0.6（σ+4）/ best = 睁眼优先→sharpness 降序→组内序 / 组≥2 才成组 / blurry <22 或组差 >14 注记）+ 组 id = StableHash decimal string（L013——输入内容 DECISIONS 钉，review m-5）+ MIT 归属头 + Lumen 同输入 golden（上游向量缺失已核——自织 + 对拍正路径，review m-3）+ StackClustering/list_bursts 零 diff 断言；T7：FilterField += sharpness/faces/eyesClosed/hasBurst（16→20 案）+ FilterSQL .library 域直比翻译腿 + hasBurst typed 不支持臂 + .session 域四案 typed unsupported 负测（review m-11）+ createAlbum(filterGroup:) 四案集成测试 + LibraryGridView 徽章（模糊/闭眼/连拍序号/best）+ 转为堆栈一键（review m-6）+ Settings 开关行（review M-3）+ xcstrings 尾块纯插入 + zh-audit 双 PASS"
estimated_tests: "+12..15（T1 +2..3 / T2 +1..2 / T3 +2..3 / T4 +2 / T5 +2〔含 APP 装配/门控面——review M-2〕/ T6 +2 / T7 +1..2 / T8 0；越带申报理由）"
test_bundles: [LIB, APP]
baseline: "4112/40/0（r12-repairs R3-ACCEPTANCE:8,:93——CONTEXT §Phase Goal；HEAD ee73da34 = research docs-only 产线零漂移）"
expected_all: "4112 + ΔN（本 plan 终态带 4124..4127；--all 归 orchestrator 批准制——本 plan 验收 = 构建 + `--bundle Library` 定向，全套归 Plan C 收口轮统一对账）"
red_lines:
  - "共用红线正本 = CONTEXT §三 plan 红线 front-matter 17 条（FIX2③ 零例外〔本 plan McpServerController 零 diff——CONTEXT 红线 1 M-4 修订正本〕/ 封存面〔LightamerSidecar v11 不 bump——分析产物全在 .lalb〕/ xcstrings 尾块 / LocalizationValue 禁形 / L041 tuist 末位 / 机器级单重活 + F0'-prod·LENS-01 链后 / MIT 归属不可延后 / L013 StableHash / 默认中性零行为 / UserDefaults 恰一键 library.analysis.enabled / --all 批准制 / C 档门控 / probe fence / L057 缝 / 测试落域 LIB+APP / commit 纪律 lumena 前缀）。"
  - "StackClustering（:20-64）与 MCP list_bursts（CullingToolset.swift:1174+）零 diff——近亲不收编（D-LU-2）；CullingToolset 本体零触（session 域）。"
  - "schema 迁移纯 additive：frozen 列位置/拼写零触碰 + 零回填（分析趟懒填）+ 零改列；futureSchema 回退枚举不受扰。"
  - "公式参数逐字直译禁重标定：SHARPNESS_EDGE=1600 / σ0.5 / 32px 块 / 四方向核 / P90 / min-of-4 / 各方向 log2(P90 比值)→四方向 min→(min+4)/5.5*100 映射〔review B-1 实式——log2 逐方向先施〕/ strong 空→0 / min(shape)<64→nil 两分支 / CLOSED=0.16 语义初值 / BURST_GAP=2.0 / BURST_DIFFERENCE=0.6（D-LU-10；标定一致性 = golden 前提）。"
  - "分析趟默认中性：零分析产物行时网格/查询/渲染逐字节现状（红线 10）——行更新 = DB 写 + additive 通知缝（无既有行变更通道可复用——review m-2），图库滚动路径零接触。"
files_modified:
  - LightamerCore/Sources/Library/LibrarySchema.swift        # T1：schemaVersion 5→6 + images 七列 DDL + migrate v5→v6 腿 + addCullingAnalysisColumns 幂等探针
  - LightamerCore/Sources/Library/ExifSearchIndexer.swift    # T2：ExifRead additive（cameraSerial/subsec）+ readProperties 补读 + 索引趟写腿
  - LightamerCore/Sources/Library/LibraryStore.swift         # T2/T5：import INSERT serial 写腿（:382 核实）+ setAnalysis 批写 additive 方法
  - LightamerCore/Sources/Library/CullingAnalysis.swift      # T3：新建——SharpnessAnalyzer + Signature16（MIT 归属头）
  - LightamerCore/Sources/Library/EyeClosureAnalyzer.swift   # T4：新建——Vision landmarks 眼睑比 + 注入式工厂
  - LightamerCore/Sources/Library/LibraryAnalysisService.swift # T5：新建——actor 分析趟（暂停/进度/取消）
  - App/Sources/Lightamer/Library/LibraryAnalysisWiring.swift  # T5（review M-2）：新建——App 装配缝（项目打开启动 + enabled 门 + 导出/AI 活跃探针注入 + BackgroundTaskRegistry @MainActor 适配 handle）
  - App/Sources/Lightamer/UI/Shell/LightamerShell.swift        # T5（review M-2）：装配挂接最小触点（KD-5 sink 装配先例同形）
  - LightamerCore/Sources/Library/BurstAnnotator.swift       # T6：新建——查询期连拍注记纯函数（MIT 归属头）
  - LightamerCore/Sources/Library/LibraryQueries.swift       # T6/T7：注记行集读缝（signature/serial 列读取）+ 分析扫描查询
  - LightamerCore/Sources/Session/FilterPredicate.swift      # T7：FilterField += 4 案（:54-84，16→20）
  - LightamerCore/Sources/Session/FilterSQL.swift            # T7：.library 域直比翻译腿（白名单纪律同形）
  - App/Sources/Lightamer/Library/Views/LibraryGridView.swift # T7：行角标徽章（模糊/闭眼/连拍序号/best）+ 转为堆栈一键（review m-6）
  - App/Sources/Lightamer/Settings/SettingsPages.swift        # T7（review M-3）：library.analysis.enabled 开关行（消费 T5 键单源常量，零新键字面量）
  - Resources/Localizable.xcstrings                          # T7：library_hint_* 键族尾块纯插入
  - NOTICE                                                   # T3：Lumen RAW（MIT）条目首落地（覆盖 T6/T4 引用）
  - Tests/LightamerTests/LibrarySchemaV6Tests.swift          # T1：新建（LIB）
  - Tests/LightamerTests/ExifSerialSubsecTests.swift         # T2：新建（LIB）
  - Tests/LightamerTests/CullingAnalysisGoldenTests.swift    # T3：新建（LIB）
  - Tests/LightamerTests/EyeClosureAnalyzerTests.swift       # T4：新建（LIB）
  - Tests/LightamerTests/LibraryAnalysisServiceTests.swift   # T5：新建（LIB）
  - Tests/LightamerTests/LibraryAnalysisWiringTests.swift    # T5（review M-2）：新建（APP——装配/门控面）
  - Tests/LightamerTests/BurstAnnotatorTests.swift           # T6：新建（LIB）
  - Tests/LightamerTests/FilterCullingFieldsTests.swift      # T7：新建（LIB）
  - Project.swift                                            # T8：八个新测试文件入对应 bundle 显式数组（七 LIB + 一 APP——review M-2）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T8：八行落域登记行（七 LIB + 一 APP）
  - .work/gsd/phases/lumen-culling/LUMEN-A-SUMMARY.md        # T8：执行摘要（逐任务记账 + ΔN 终账）
  - .work/gsd/phases/lumen-culling/LUMEN-A-DECISIONS.md      # T8：裁定记录（ImageIO 键名样张核对结论 + m-5 比较器/nil 签名/组 id 三钉 + m-2 通知缝定形 + 各偏差 + 标定记录指针）
---

# Plan LUMEN-A — 分析地基（LU2 + LU1）

> **裁决正本** = `CONTEXT.md`（D-LU-1..10 + X1..X5；晨审可推翻）；规格
> 正本 = `RESEARCH.md`（§UQ-LU2 / §UQ-LU1 / §依赖与切分 A 行；planner
> 抽核吻合 + 勘误四条见 CONTEXT〔① = FilterField 16 案〕+ 修复轮修订节
> 〔review 回注已落位，改动点行内 `(review …)` 标记〕）。本 plan = 纯
> Library 域 additive + Core 纯函数新件，**零 Metal kernel 零 sidecar 面
> 零 MCP 面**（CullingToolset 本体零触）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T8 形态 = CONTEXT D-LU
> 落定值）。执行中如触「必须扩面」（sidecar 面 / MCP culling 域重挂 /
> stacks 实体化 / 封存面触碰 / ImageIO 键名样张核对失败需换读法）= 停
> 手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8。每任务独立 commit
> （Conventional Commits 全英文，只 add 相关文件，不 push，零 issue
> ref）；重活（xcodebuild）起跑前过 `Scripts/machine-guard.sh`；开工前
> 核 `.work/config.toml [gsd]` paused/auto。
>
> **C 档停**：T8 闭环后**停汇报**；确认后 LUMEN-B 起跑。
>
> **基线**：**4112/40/0**。全套预期 4112 + ΔN（本 plan 分账 +12..15 →
> 终态带 4124..4127；全套对账归 Plan C 收口轮）。

## ΔN 预算表（逐任务，本 plan 分账带 +12..15；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 schema v6 | **+2..3** | v5→v6 迁移 + 幂等重跑 + 旧数据零漂移 + imagesColumns frozen 断言 29→36（review M-1）+ 快照 hook 存在断言 | LIB（LibrarySchemaV6Tests） |
| T2 EXIF serial/SubSec | **+1..2** | 合成 EXIF 正例 + 缺失 nil + SubSec 折算 | LIB（ExifSerialSubsecTests） |
| T3 清晰度/签名纯函数 | **+2..3** | Lumen 同输入 golden + 标定锚带内 + 四方向表驱动 | LIB（CullingAnalysisGoldenTests） |
| T4 眼睑比 | **+2** | 合成 landmarks 表驱动（睁/闭/侧脸）+ 工厂注入 | LIB（EyeClosureAnalyzerTests） |
| T5 分析趟服务 | **+2** | 扫序/版本戳重算/暂停恢复/空结果防风暴 + App 装配/门控（review M-2） | LIB + APP（LibraryAnalysisServiceTests + LibraryAnalysisWiringTests） |
| T6 BurstAnnotator | **+2** | Lumen 同输入 golden + 副本排除 + best 序 + L013 id | LIB（BurstAnnotatorTests） |
| T7 相册四案+徽章 | **+1..2** | FilterSQL 直比集成 + hasBurst 不支持臂 + .session 负测（review m-11）+ 徽章/转栈模型（review m-6）+ Settings 行 | LIB（FilterCullingFieldsTests） |
| T8 收口 | **0** | docs + Project.swift 数组 + BUNDLE-MAP + tuist generate | — |
| **合计** | **+12..15** | 4112 → 本 plan 终态带 4124..4127 | 八新测试文件（七 LIB + 一 APP——review M-2） |

## 已定裁决（生效值，硬约束，不得重开）

1. **分析基准 = 1600px 内嵌预览灰度**（D-LU-10）——公式参数直译禁重标
   定；2560 档属 Plan B 显示档不混用。
2. **闭眼 = 组内排序免阈值（主）+ 校准集绝对提示（副）**（D-LU-4）——
   本 plan 落两臂：T6 best 排序消费相对开度；T4 阈值注入臂默认 0.16 语
   义初值。
3. **连拍 = 查询期虚拟注记零落库**（D-LU-2）——「转为堆栈」手动动作
   **T7 显式收编**（contextMenu → `LibraryStore.createStack :625` 一键
   ——review m-6，消灭死胡同条款）；网格折叠显示 = 徽章指示（行不隐藏
   ——D-LU-2 注记语义）。
4. **分析趟 = 默认开 + 导出/AI 期挂起 + Settings 开关**（D-LU-5）——
   `library.analysis.enabled` 本 plan 唯一新 UserDefaults 键（红线 11）。
5. **serial 缺失回落 make+model / SubSec 缺失文件名 tiebreak**（X2）——
   登记接受，不改排序键结构。
6. **MIT 归属随件落地**（红线 7）——T3 NOTICE 首条目 + T3/T4/T6 文件头。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lumen-culling/CONTEXT.md`（D-LU-1..10 + X1..X5 +
  hazards + 红线 17 条 + 勘误四条〔① FilterField 16 案〕+ 修复轮修订节
  + 晨审索引）
- `.work/gsd/phases/lumen-culling/RESEARCH.md` §UQ-LU2/§UQ-LU1/§风险
  1-5/§键族与登记预案
- Lumen 直译源（只读，`git show v2.0.1:`——**禁触其工作区**）：
  `lumen/culling.py:34-94`（常量/清晰度/签名）+:97-179（Faces——语义参
  照，我方 Vision 自算）；`lumen/library_db.py:34-67`（列族）+:822-900
  （annotate_bursts/_copy/signature_difference 全式）；`
  lumen/library_tasks.py:44-58,141-200`（三防 + 空分析先例）
- `.work/config.toml [gsd]` paused/auto 开关 + `.work/LESSONS.md` L041
  （tuist 末位——八个新测试文件必触发）/ L014（本 plan 无计时面，备忘）
  / L013（组 id StableHash）
- AGENTS.md M2-4-0 E2（测试落域 + BUNDLE-MAP）+ M2-5 节（spectral-film-lut
  许可证登记流程——NOTICE 条目先例）+ M6-2（process version——本 plan
  零触，备忘）

---

## T1 — schema v6：culling 七列 additive 迁移 + 快照缝回归（X1，H-LU2 消解）

> 四代迁移先例（v1→v5 全 additive + 快照 hook + 幂等探针）齐备——本任
> 务 = 第五代同款，零新机制。

**read_first**：CONTEXT §X1 + §Hazards H-LU2；`LibrarySchema.swift:76-130`
（版本注记块——v6 段随批续写）/:278-307（images DDL）/`:836-860`
（migrate 单事务）/:899-909（addImagesDefaultLookPendingColumn 幂等先例）；
`ProjectFileStore.swift:270-290`（pre-migrate hook）/:358-420（backup
本体）；`Tests/LightamerTests/LibrarySchemaV5Tests.swift`（存量族同形参照）。

- **action**：
  1. `schemaVersion` 5→**6**（`:116` 单点）+ 版本注记块 v6 段（LU2 分析
     六列 + camera_serial，纯 additive 零回填——CONTEXT X1 语义）。
  2. images DDL additive 七列（DDL 尾段 `default_look_pending` :307 同位
     追加）：`analysis_version INTEGER` / `sharpness REAL` / `faces
     INTEGER` / `eyes_closed INTEGER` / `signature BLOB` / `face_boxes
     TEXT` / `camera_serial TEXT`——**frozen 列位置/拼写零触碰**。
  3. **imagesColumns frozen 数组尾段同批追加七项**（`LibrarySchema.swift
     :156-186`——doc 自述 frozen contract；`default_look_pending` `:184`
     同位顺延）——**七列双登记点：DDL + imagesColumns**，漏一即 frozen
     断言失败（review M-1）。
  4. `migrate(from:to:)` 加腿 `if from <= 5 && to >= 6 { try
     addCullingAnalysisColumns(on:) }`；新函数 = **幂等列探针**（PRAGMA
     table_info 逐列 probe 跳过已存在——:899-909 先例七列化）。
  5. 测试（LIB）：v5 包打开迁移（七列在位 + user_version=6 + 既有行数
     与列值零漂移）+ 幂等重跑（migrate 二次调用零错——半程快照重跑干净）
     + 快照 hook 存在断言（pre-migrate 快照文件产生于迁移前——
     ProjectFileStore 既有 hook 的回归断言，零新机制）+ 新列 NULL 缺省
     语义（零回填断言）+ **imagesColumns frozen 断言更新 29→36**
     （`LibrarySchemaTests.testImagesTwentyNineColumnsVerbatim :114`
     更名/断言 + `LibrarySchemaV5Tests :307-310` assertColumns 冻结面同
     步 + V6Tests 新冻结族钉 36 项——review M-1）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一产线文件（LibrarySchema.swift）。
  - grep：`schemaVersion = 6` 恰一处；七列拼写各恰**两**处（DDL +
    imagesColumns——review M-1）；`from <= 5 && to >= 6` 腿恰一处。
  - v5 fixture（或构造 v5 库）迁移测试族在册（迁移/幂等/零漂移/快照
    四断言）。
  - `--bundle Library` 定向零回归（LibrarySchemaV5Tests 存量族全绿）。
- **commit**: `feat(lumena): add culling analysis columns as library schema v6`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（additive 迁移，旧包
  不受扰；已迁移包被旧二进制回落打开 = `LibraryError.futureSchema` 硬
  拒〔by design——`ProjectFileStore.swift:271-273` guard `stored <=
  schemaVersion`〕，数据无损，新二进制重开即愈——review m-1 措辞勘正）；
  偏差（列
  型微调/注记措辞）= DECISIONS 申报；**禁改 frozen 列**；**禁加回填腿**；
  **禁触 ProjectFileStore 迁移 dispatch 本体**（快照 hook 回归断言即可）。

## T2 — EXIF serial + SubSecTime 读腿（X2）

**read_first**：CONTEXT §X2；`ExifSearchIndexer.swift:108-161`（ExifRead
+ readProperties 现形——无 serial 无 SubSec 亲核）；RESEARCH §风险 4-5；
`LibraryStore.swift:382`（import INSERT——serial 写腿核实点）。

- **action**：
  1. `ExifRead` additive 两字段（`cameraSerial: String?` + captureDate
     SubSec 折算）；`readProperties` 补读 `kCGImagePropertyExifBodySerialNumber`
     （Exif dict 主、TIFF dict 最佳努力）+ `kCGImagePropertyExifSubSecTimeOriginal`
     （回落 `SubSecTime`/`SubSecTimeDigitized`）——SubSec 折进 captureDate
     （timeInterval + subsec/1e6）。
  2. 索引趟写腿：ExifSearchIndexer INSERT（camera_serial 列）+ import
     INSERT（LibraryStore :382 处——实际消费点核实后恰最小接线）。
  3. **旧行零回填**——分析趟顺路懒补归 T5（本任务零回填腿）。
  4. 测试（LIB）：合成 EXIF fixture（gen-tiff-fixtures.py 家族先例——
     serial + SubSec 正例）断言取值 + 无 serial/subsec 缺失 nil + SubSec
     折算精度断言。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（ExifSearchIndexer +
    LibraryStore〔或实际消费点〕）。
  - grep：`kCGImagePropertyExifBodySerialNumber` 恰一处读点；
    `SubSecTimeOriginal` 主读点恰一处（回落臂 ≤2 处）。
  - 正例/缺失/折算测试在册；`--bundle Library` 定向零回归。
- **commit**: `feat(lumena): index camera serial and subsecond capture time`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（additive 读腿，索引
  数据面回落无 serial 态）；偏差（**ImageIO 键名与样张不符**——RESEARCH
  §风险 4 的 ExifTool≠ImageIO 读法面）= 停手取证（实拍样张
  CGImageSourceCopyPropertiesAtIndex dump 落 evidence）→ DECISIONS 申报
  换读法，禁拍脑袋猜键名；**禁动既有字段语义**（ExifRead 既有八字段零
  触）。

## T3 — SharpnessAnalyzer + Signature16 纯函数 golden（X3，MIT 归属）

**read_first**：CONTEXT §X3 + 红线 7；Lumen `culling.py:34-94`（常量 +
sharpness + signature 全式——直译正本）；RESEARCH §UQ-LU2 清晰度段；
Accelerate/vDSP 先例（`LightamerCore/Sources/AI/` SemanticEngine vDSP 面
——AGENTS M2-10 节）；AGENTS M2-5 节（许可证登记流程——NOTICE 先例）。

- **action**：
  1. 新建 `LightamerCore/Sources/Library/CullingAnalysis.swift`：
     `SharpnessAnalyzer.analyze(gray: 1600px 平面) -> Double?`（高斯 σ0.5
     → 32px 块四方向（0/45/90/135°）一阶/二阶导数能量比（固定 3×3 核
     直译）→ 结构块筛选（一阶能量 P75 且 >2e-5）→ **每方向 log2(P90
     比值) → 四方向取 min → `(min+4)/5.5*100` 钳 0-100**——Lumen
     `culling.py:84-87` 实式，min 比值=1 时 ≈72.7 分；**log2 逐方向先
     施、min 后线性映射，顺序不可写反**（review B-1）；两分支：strong
     空 → 0.0（`:83`）/ `min(gray.shape) < 64 → nil`（`:79`））+
     `Signature16.bytes(gray) -> [UInt8]`（16×16 INTER_AREA 同义缩放）
     ——实现域 Accelerate/vDSP，**零 OpenCV 零 Metal**。
  2. 文件头 MIT 归属（Lumen RAW 上游版权 + 「算法思想与常量标定源自
     LUMEN RAW（MIT），实现独立」——红线 7 措辞）。
  3. 根 `NOTICE` 新增 Lumen RAW 条目（首落地；覆盖 T4/T6 引用——条目措
     辞注明三件算法 provenance）。
  4. 测试（LIB）：Lumen 同输入 golden——合成图样 + NumPy 参考输出双写
     （M2-4 golden 惯例；`Scripts/gen-float-fixtures.py` 家族先例）+
     标定锚断言（1.2px 高斯模糊 ≈55 分、2px ≈30 分——带内 ±5）+ 四方
     向核表驱动（单向运动模糊 min-of-4 检出例）+ **两分支 golden**
     （strong 空图样 → 0.0；<64px 图样 → nil——review B-1）+
     Signature16 尺寸/值域断言。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（CullingAnalysis.swift）+
    NOTICE 一条目。
  - grep：常量直译面在册（`1600`/`2e-5`/`P75`/`P90`/`log2`/`5.5`——
    `grep -c` 对 Lumen 源常量逐项命中）；旧式 `log2((min+4)/5.5)` 记法
    零残留（review B-1 机检）；`import OpenCV`/Metal 零命中。
  - golden 测试在册（锚点带内 + NumPy 对拍双写留档 evidence）。
  - `--bundle Library` 定向零回归。
- **commit**: `feat(lumena): port lumen sharpness and signature analyzers`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯新件，零消费方）；
  偏差（vDSP 实现形态/核常量浮点序）= DECISIONS 申报——**公式参数
  （1600/σ0.5/核系数/P75/2e-5/P90/各方向 log2 序/5.5 线性映射/两分支）
  逐字直译禁改**（review B-1 实式；D-LU-10，
  标定一致性 = T5 分析产物可比性前提）；golden 失配 = 停手对拍定位（禁
  调参数凑数）。

## T4 — EyeClosureAnalyzer：眼睑比 + 注入式工厂 + 标定集机制（X3，D-LU-4）

**read_first**：CONTEXT §X3 + §D-LU-4；`CullingToolset.swift:1281-1370`
（VNDetectFaceLandmarksRequest 调用链 + 像素换算 + 底左→顶左翻转先例——
**零触，参照**）；RESEARCH §Vision 结论（VNFaceLandmarks.h:170-180
isBlinking 注记）；Lumen `culling.py:97-179`（Faces——语义参照非移植体
：YuNet/MediaPipe 478 点不移植，Vision 76 点自算）。

- **action**：
  1. 新建 `LightamerCore/Sources/Library/EyeClosureAnalyzer.swift`：
     `VNDetectFaceRectanglesRequest`（1280px 级检测图——长边 3% 门直译）
     → 逐脸 `VNDetectFaceLandmarksRequest` → 眼睑比 = 眼 region 上下点
     对纵向跨度均值 / 眼角横向跨度（左右各一）→ 输出 `(faces: Int,
     boxes: [CGRect], ratioRight: Double?, ratioLeft: Double?)` + 闭眼
     判定（`max(右,左) < threshold`，threshold 注入——默认 0.16 语义初
     值常量单源）。
  2. **注入式 request 工厂**（protocol 缝——Vision 请求不可 CI 依赖；
     生产 = 真 Vision 工厂，测试 = 合成 landmarks 工厂）。
  3. 文件头归属注记（Lumen CLOSED 语义出处——CONTEXT X3）。
  4. 标定集机制：`evidence/culling-analysis/calibration/` 目录约定 +
     定标记录模板（10-20 张实拍人工标注——样张不入仓不入 CI 门；
     LENS-04 T4 同款纪律）——本任务落机制与模板，定标值换发随 DECISIONS。
  5. 测试（LIB）：合成 landmarks 表驱动（睁眼/闭眼/单眼/侧脸漏检/无脸）
     + 工厂注入断言 + 比值数学面（上下跨度/眼角跨度）钉死。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件（EyeClosureAnalyzer.swift）。
  - grep：`VNDetectFaceRectanglesRequest`/`VNDetectFaceLandmarksRequest`
    在 LightamerCore 恰一文件；threshold 默认常量恰一处声明；测试文件
    零 `import Vision` 直跑（工厂注入断言——合成面可测性机检）。
  - 标定集机制目录 + 模板在 evidence 在库。
  - `--bundle Library` 定向零回归。
- **commit**: `feat(lumena): add eye closure ratio analyzer over vision landmarks`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯新件）；偏差（
  landmark 索引选取/比值变体）= DECISIONS 申报；**禁在 Core 落 GUI 依赖
  **（Vision request 工厂注入缝保 CI 可测）；**禁定死标定值为「最终值」
  **（0.16 = 语义初值，定标前文案恒「可能闭眼」——D-LU-4 提示性语义）。

## T5 — LibraryAnalysisService：actor 分析趟 + 暂停语义（X1 缝位 5，D-LU-5，H-LU1 消解）

**read_first**：CONTEXT §D-LU-5 + §Hazards H-LU1；`BackgroundTaskHosting
.swift:53-127`（BackgroundTaskHandle protocol :53 / Registry :80-127 亲
核）；`SessionThumbnailProvider.swift:411-424`（embeddedPreview 缝形态
——**参照**，本 plan Core 侧自建 1600px 变体，Session 域 720 常量零触）；
Lumen `library_tasks.py:44-58,141-200`（三防 + 空分析 :162 先例）；T3/T4
产物面。

- **action**：
  1. 新建 `LightamerCore/Sources/Library/LibraryAnalysisService.swift`：
     actor——扫描 `analysis_version IS NULL OR analysis_version < CURRENT`
     行序 → 内嵌预览读（ImageIO `CGImageSourceCreateThumbnailAtIndex`
     max pixel 1600——Core 侧自有函数）→ 灰度 → SharpnessAnalyzer +
     Signature16 → faces>0 才 EyeClosureAnalyzer → `LibraryStore.setAnalysis`
     批写（additive store 方法——七列 UPDATE + **additive 通知缝**：
     LibraryStore/LibraryQueries 现零通知面、网格刷新靠调用方 reload
     （`LibraryGridModel.swift:169-194` 先例）——轻量 AsyncStream/回调
     缝或显式 stale-until-refresh 语义，execute 期 DECISIONS 定形——
     review m-2）。
  2. 三防：QoS `.utility` + 并发 cap 2（TaskGroup）+ 暂停语义（导出/AI
     活跃查询挂起、空闲恢复——BackgroundTaskRegistry 状态查询缝 + 注入
     式活跃探针；Lumen paused()/kick() 直译）。
  3. 单张不可读写 = 写空分析（`analysis_version = CURRENT` + 空产物列）
     防重试风暴（Lumen :162 直译）。
  4. 进度/取消挂 `BackgroundTaskRegistry`——Registry 为 **App 侧
     `@MainActor` 类**（`BackgroundTaskHosting.swift:80-127`），Core 不
     可 import App：Core 侧经注入 handle 抽象，注册面由 App 装配件完成
     （:53 protocol/:87 register 缝——review M-2）。
  5. UserDefaults `library.analysis.enabled`（Bool 默认 true——typed 读
     + 注入式 defaults，本 plan 唯一新键，红线 11）。
  6. **App 装配面（review M-2）**：新建 `App/Sources/Lightamer/Library/
     LibraryAnalysisWiring.swift`——项目打开事件启动点（KD-5 ShellView
     sink 装配先例形，挂 `LightamerShell.swift` 最小触点）+ enabled 门
     （「默认开」判据落地——D-LU-5）+ 导出/AI 活跃探针注入 + Registry
     适配 handle（`@MainActor` 侧实现 handle 协议，桥接 Core actor）。
  7. 旧行懒补：分析趟读 EXIF 时 camera_serial/capture_date 亚秒缺 = 顺
     路 UPDATE（X2 懒回填腿）。
  8. 测试（LIB + APP）：注入式 store + 工厂全合成——扫序（版本戳优先）/
     重算（版本落后行）/暂停-恢复状态机/空分析防风暴（不可读文件恰一次）/
     enabled=false 零启动 + 进度回调计数（LIB）+ 装配/门控面（APP——
     `LibraryAnalysisWiringTests`：enabled 门启停/探针注入/适配 handle
     注册——review M-2）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四产线文件（LibraryAnalysisService 新建
    + LibraryStore setAnalysis additive + LibraryAnalysisWiring 新建 +
    LightamerShell 装配挂接最小触点——review M-2）。
  - grep：`.utility` QoS 恰一处；并发 cap 常量恰一处；
    `library.analysis.enabled` 拼写全仓恰一处（键单源——T7 Settings 行
    消费同一常量）；LightamerCore 域 App 模块 import 零命中（装配面
    App 侧机检——review M-2）。
  - 暂停/恢复/防风暴 + 装配/门控测试在册；`--bundle Library` +
    `--bundle App` 定向零回归。
- **commit**: `feat(lumena): add background culling analysis service`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（零消费方时无行为差
  ——T7 徽章/Settings 与 App 装配面是消费方，回滚序 T5 先于 T7 revert）；
  偏差（活跃探针缝形
  态/批写批大小）= DECISIONS 申报；**禁在分析趟触碰图库滚动路径**（行更
  新只走 DB + additive 通知缝（无既有行变更通道——review m-2 勘正）——
  红线 10/RESEARCH §风险 2）；**禁
  MainActor 阻塞读**（actor 隔离纪律）；**禁跳过空分析防风暴**（重试风
  暴 = 电池/IO 事故面）。

## T6 — BurstAnnotator：查询期连拍注记纯函数 golden（X4，D-LU-2）

**read_first**：CONTEXT §X4 + §D-LU-2；Lumen `library_db.py:822-900`
（signature_difference/_copy/annotate_bursts/annotate_hints 全式——直译
正本）；`StackClustering.swift:20-64` + `CullingToolset.swift:1174-1194`
（近亲——**零触参照**）；RESEARCH §UQ-LU1 全节 + §风险 4-5。

- **action**：
  1. 新建 `LightamerCore/Sources/Library/BurstAnnotator.swift`：查询期
     纯函数 `annotate(rows: [BurstRow]) -> [BurstAnnotation]`——BurstRow
     输入 = LibraryQueries 行集投影（id/make/model/serial/captureDate/
     signature/eyesRatio/sharpness）；算法五点直译（排序键/副本排除/
     归组/best/blurry 注记——CONTEXT X4 全式）；组 id = StableHash
     decimal string（L013）；组 ≥2 才成组。
  2. `LibraryQueries` additive：分析注记行集读缝（signature/serial 列
     读取——签名 BLOB decode）。
  3. 文件头 MIT 归属（红线 7——T3 NOTICE 条目覆盖）。
  4. 测试（LIB）：**Lumen 同输入 golden**（上游向量缺失已核——v2.0.1
     `tests/` 全清单 38 文件无 annotate_bursts 向量；自织向量 + 直译双
     实现对拍为正路径，execute 期取证申报——review m-3）+
     副本排除例（RAW+JPEG 对/stem 前缀互含）+ 跨机身不组/无 ts 永不组/
     2.0s 阈值边界 + best 序（睁眼优先 > sharpness 降序 > 组内序）+
     组 id decimal string 断言（L013）+ StackClustering/list_bursts 零
     diff 断言（`git diff --stat` 面核即可）。
  5. **DECISIONS 必钉三件（review m-5）**：①best 比较器形态——Lumen
     `library_db.py:876` best 元组 = `(not eyes_closed, sharpness,
     -index)` 布尔桶，我方 D-LU-4 主路径 = 相对开度 ratio 免阈值，best
     维不可字面对拍 → 双字段 `(not eyes_closed, ratio, 组内序)` 形或
     golden 语义换算申报；②`_similar` 对 nil 签名返回 True（`:825-827`
     ——无签名行仍可归组）行为转录；③组 id StableHash **输入内容**钉
     死（成员 id + 机身 + ts 的 canonical 串——确定性面）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（BurstAnnotator 新建 +
    LibraryQueries additive 缝）。
  - grep：`StableHash` 在组 id 生成点恰一处；`Hasher()` 零命中（文件
    域）；2.0/0.6/±1e-3 常量直译在册。
  - golden 测试在册（同输入对拍留档 evidence）。
  - `--bundle Library` 定向零回归；`git diff` 确认 StackClustering/
    CullingToolset 零触碰。
- **commit**: `feat(lumena): port lumen burst annotator as query-time annotation`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯查询期注记，零落
  库零消费方行为差）；偏差（行投影字段增减/golden 向量来源）= DECISIONS
  申报；**禁落库禁实体化**（stacks 零写面——D-LU-2）；**禁改近亲两件**
  （红线 2）；**禁浮点身份入组 id**（L013）。

## T7 — 智能相册四案 + FilterSQL 直比 + 网格徽章（X5）

**read_first**：CONTEXT §X5；`FilterPredicate.swift:54-84`（16 案亲核
——勘误①）；`FilterSQL.swift`（FilterSortKey 白名单 + column 拼写守卫
——注入面纪律）；`LibraryStore.swift:116-155`（createAlbum 智能相册缝）；
RESEARCH §UQ-LU2 智能相册语法段 + 缝位 6-7；`App/Sources/Lightamer/
Library/Views/LibraryGridView.swift`（行渲染面——徽章落点）。

- **action**：
  1. `FilterField` += `sharpness`/`faces`/`eyesClosed`/`hasBurst`（16→20
     案——CaseIterable 迭代面 additive）；op 支配 = sharpness gt/gte/lt/
     lte/eq；faces/eyesClosed eq/gt/gte；hasBurst eq(true)。
  2. `FilterSQL` `.library` 域翻译腿：sharpness/faces/eyes_closed 纯
     SQL 直比列（NULL 行不命中——缺省语义）；`hasBurst` = **typed 不支
     持臂**（智能相册 builder 置灰 + 说明文案——查询期注记不可纯 SQL，
     RESEARCH 缝位 6 裁定）。
  3. 网格徽章（LibraryGridView 行角标）：可能模糊（sharpness <22 或组
     相对——T6 注记）/ 可能闭眼（T4 判定）/ 连拍序号「n/m」+ best 标记
     ；零注记行 = 现状渲染逐字节（红线 10 默认中性）。**「转为堆栈」
     contextMenu 一键**（选中连拍注记行 → `LibraryStore.createStack :625`
     ——review m-6 显式收编）+ **徽章刷新挂接点**（T5 additive 通知缝
     消费——分析行更新后可见区刷新；stale-until-refresh 则滚动/切页刷
     新——review m-2）。
  4. xcstrings `library_hint_blurry`/`library_hint_eyes_closed`/
     `library_hint_burst_index`（+ best/hasBurst 不支持文案键 + Settings
     开关标签/说明两键——review M-3）尾块纯插入；`zh-audit --check` +
     `--self-test` 双 PASS。
  5. **Settings 开关行（review M-3）**：`SettingsPages.swift` additive
     一节——`library.analysis.enabled` 开关（消费 T5 键单源常量，零新
     键字面量；标签/说明两 xcstrings 键）——D-LU-5「Settings 开关」
     用户可达面闭环。
  6. 测试（LIB）：createAlbum(filterGroup:) 四案集成（建库 → 灌注记行
     → 直比命中/未命中 + NULL 缺省语义）+ hasBurst 不支持臂 + FilterSQL
     白名单回归（注入面零扩）+ **`.session` 域四新案 typed unsupported
     负测**（SessionIndexSchema 34 列 frozen 契约无 sharpness 列——
     review m-11）+ 徽章注记映射模型表驱动 + 转栈一键动作断言（合成
     store——review m-6）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰四产线文件（FilterPredicate +
    FilterSQL + LibraryGridView + SettingsPages——review M-3）+ xcstrings。
  - grep：`case sharpness`/`case faces`/`case eyesClosed`/`case hasBurst`
    各恰一处；FilterSQL 直比列拼写 = DDL 列名（`sharpness`/`faces`/
    `eyes_closed`——grep 对表）；**负向判据：`.session` 翻译臂四新案零
    SQL 生成（typed unsupported 负测在册——review m-11）**；xcstrings
    尾块 diff = 纯插入（历史键零触碰——`git diff` 核）。
  - zh-audit 双 PASS 输出留档；`--bundle Library` + `--bundle App`
    （网格面）定向零回归。
- **commit**: `feat(lumena): add smart album culling filters and grid badges`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（FilterField additive
  案零既有行为差；徽章零注记 = 现状）；偏差（op 支配集/徽章视觉形态/
  键清单）= DECISIONS 申报；**禁扩 ORDER BY 白名单**（FilterSortKey 本
  批零新增——排序面不在四案范围）；**禁让 hasBurst 走伪 SQL**（typed 不
  支持臂 = 裁定值）；**禁触智能相册既有四案外行为**。

## T8 — 收口（Project.swift 数组 + tuist generate + docs）

- **action**：
  1. `Project.swift` 八个新测试文件入对应 bundle 显式数组（七
     LightamerTestsLibrary + 一 App——review M-2）+ BUNDLE-MAP 八行登记。
  2. `tuist generate` = 本批最后一个动作（L041）。
  3. `--bundle Library` 定向全绿；ΔN 实数对账（预算 +12..15）。
  4. LUMEN-A-SUMMARY（逐任务记账 + ΔN 终账 + golden/标定证据指针）+
     LUMEN-A-DECISIONS（ImageIO 键名样张核对结论 + 标定记录指针 + m-5
     比较器/nil 签名/组 id 三钉 + m-2 通知缝定形 + 各偏差 + 键登记
     `library.analysis.enabled`）落盘。
  5. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff =
  恰八行数组插入；BUNDLE-MAP 八行在库；tuist generate 后无生成物入 git
  ；SUMMARY/DECISIONS 在库。
- **commit**: `test(lumena): register culling analysis suites and close out plan a`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY
  申报理由；禁漏 tuist generate（数组改后不生成 = 编译面漂移）。

---

## 风险与回退

- **ImageIO 键名面失配**（RESEARCH §风险 4）：BodySerialNumber 在部分机
  身走 TIFF dict、部分不落盘——T2 双 dict 最佳努力 + 样张 dump 取证；
  serial 全缺 = 回落 make+model（误组登记接受），LU1 分组价值降级但闭
  眼/清晰度面不受扰。
- **Vision 76 点眼睑比精度**（§风险 3）：绝对阈值待标定——主路径（T6
  best 排序）免阈值不受扰；提示文案恒「可能」语义；侧脸/遮挡漏检与
  Lumen 同病。
- **分析趟吞吐**：全项目首扫 = 逐张内嵌预览读 + 分析（Lumen 口径
  61MP≈0.5s/张参照）——QoS .utility 后台慢跑可接受；插队缝（±窗优先）
  归 Plan B T6 消费。
- **golden 失配定位**：清晰度/连拍 golden 与 Lumen 对拍失配 = 先核实现
  域差（vDSP 浮点序/灰度转换式/min 与 log2 施加序——review B-1），**禁
  调常量凑数**（D-LU-10）——定位记录落 DECISIONS。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §UQ-LU2 缝位 1-7 ↔ T1/T2/T3/T4/T5/T7 逐
   项闭合；§UQ-LU1 缝位 ↔ T6/T7；H-LU1 ↔ T5 三防；H-LU2 ↔ T1 迁移族。
2. **OQ 兑现核**：D-LU-4（T4 两臂 + T6 免阈值消费）/ D-LU-5（T5 开关 +
   暂停 + T7 Settings 行 + App 装配——review M-2/M-3）/ D-LU-10（T3 常
   量直译——review B-1 实式）/ D-LU-2（T6 零落库 + T7 徽章/转栈——
   review m-6）/ 勘误①（T7 16→20 案非 17→21）。
3. **红线核**：LightamerSidecar/HistoryStack/CullingToolset/
   StackClustering/SessionThumbnailProvider 零 diff；MIT 归属三处文件头
   + NOTICE 条目；xcstrings 尾块纯插入 + 双 PASS；L013 组 id；tuist
   generate 末位。
4. **SC 可机检性**：每条 SC 有命令级判据（grep / git diff --stat /
   定向 bundle）；ΔN 对账式非死数。
