# M2-9-04 SUMMARY — 检查器 Export 页 + App 装配点（wave 3）

**Status:** COMPLETE（2026-10-03 夜间；执行 = ZCode subagent worker，
`[gsd]` `paused=false / auto=true` 全程未动——每任务边界复查）
**提交链:** `ec69483`(T1 页挂载+Destination/Naming) → `572df73`(T2
Metadata&Color/SDR+质量四键) → `c97924e`(T3 Queue+装配+exifSoftware 载体)
→ 本 docs commit(T4)。**不 push。**
**对账底稿:** 同目录 `M2-9-04-DECISIONS.md`（越界申报 §1 / per-image
override 载体 §2 / 层语义边界 §3 / 页开关非持久 §4 / 目标集语义 §5 /
质量记忆 §6 / 命名编辑器 §7 / 四态塌缩 §8 / exifSoftware §9 / 增量对账
§10 / 晨审清单 §12）。

## 数字对账表

| 项 | 基线（M2-9-03 终态） | 本波终态 | Δ |
|---|---|---|---|
| App bundle | 481/0/0 | **512/0/0**（195s，peakRSS 1347MB） | +31（9+11+11） |
| Export bundle（红线门） | 338/1/0 | **338/1/0**（200s，6641MB） | 0（零漂移） |
| 全套 | 2662/16/0 | **`TOTAL|2693/16/0|916s EXIT=0`**（七 bundle = 467/362/298/437/279/338/512，五未触 bundle 零漂移，skip 16 保全） | +31 |

- **测试增量 31 vs front-matter 预估 18**（+13，偏差入 DECISIONS §10）：
  真链捕获装配测试逐字段展开 + AC 逐条独立方法（01-03 波组织口径同族）。
- peakRSS 全 bundle < 8G 门（最大 IOP 7452MB），零 MEMFAIL。
- 每任务边界 `[gsd]` 开关复查 = 全程 `paused=false / auto=true` 无变更。

## 任务逐条（commit × 验收）

| 任务 | commit | 交付 | AC 覆盖 |
|---|---|---|---|
| T1 | `ec69483` | `exportPageActive` 会话开关（InspectorState additive，非持久）+ InspectorView 顶部分支（inactive 现体逐字节）+ ContentView M2 分支（`.inspector` 列挂载 + `\.exportPanelRequest` focused 复用路由 + 项目打开 rebuild 挂点；legacy 臂零 diff）+ ExportInspectorView 骨架（Destination 节：记忆写回/首用回落/子文件夹 OQ-11/ effectiveOutDir）+ ExportNamingEditor（预设下拉 3 内置+用户+Custom / 11 token 尾追 / typed parse 反馈 / live 预览 / 存改名删）+ ExportState 注入式 defaults 面（lastDirectory 读写+回落）+ M2 目标推导（provider+fallback）+ `rebuildQueueForProject` + 15 zh/en 键 + 9 测试 | AC1/3/6(部分) |
| T2 | `572df73` | Metadata&Color 节（单开关 OQ-6 / ICC EMBED-OMIT + HEIC/AVIF/WebP OMIT 不可达说明 / DRT 三元组只读行）+ SDR 节（六格式 Picker / 四质量滑杆 / PNG·TIFF·HEIC·AVIF 位深 / TIFF 压缩 / WebP 无损 / 尺寸四模式字段 / 模型域越界红字禁入 / 高级折叠区 allowUpscale=false+maxEdge=0 OQ-12）+ 质量四键（登记拼写/typed 读/生命周期 = mount+切格式载入、run+离页写回）+ 面板模型装配输入面（makeSizing/makeFormat/makeMetadataPolicy/makeVariant）+ 21 zh/en 键 + 11 测试 | AC2/4/8(部分) |
| T3 | `c97924e` | ExportQueueFaceView（四态映射/36 帽+汇总/进度/错误摘要/retry/add/clear）+ `enqueueExportM2`（per-image overrides / drtOutput=record / drtTails=record+catalog postOps / 模板批序 / policy / exifSoftware / relPath=展示名）+ **Core 载体（越界申报）**：`$jobExifSoftware` TaskLocal + enqueue `exifSoftware`/`instancesOverrides` per-image 参（Job 载体 + withValue 包装 + encodeLeg 消费；引擎体零 hunk）+ WorkspaceHostView（topbar 导出按钮 + 选择 provider 臂；越界申报）+ ToastFaceTests 环境随动（越界申报）+ run 装配动作（flush→targets→overrides→enqueue→双写回）+ 10 zh/en 键 + 11 测试 | AC5/7/1 |
| T4 | 本文 + DECISIONS + GOAL-STATE | 全套终跑 + legacy 冻结机检 + zh-audit PASS + 收口 | AC8/9 |

## 红线机检（AC1，git diff 逐 hunk）

- `ExportPanelView.swift`：840eecf..HEAD **零 diff**（连编译性补臂都不需要
  ——sizing 补臂 01 波已交付）。
- `ContentView.swift`：恰 **1 hunk** 全落 gate=false M2 分支；全文件
  **0 minus 行**（legacyBody + legacy sheet 臂字节冻结）；`LightamerApp.swift`
  （菜单命令 + gate）**零 diff**。
- Core 本波（262f98e..c97924e）= 恰 2 文件纯载体：`ExportQueue.swift` 5 hunk
  全载体（Job 字段/enqueue 双增参/precondition/Job init 折叠/encode 腿
  wrapper + encodeLeg 消费）；`ExportRenderer.swift` 恰 1 additive hunk
  （TaskLocal 声明）。pump/cancel/retry/generation/markState/markTerminal/
  finish/finishCancelled **零 hunk**；`ExportQueueContract.swift`/
  `WebPEncoder.swift`/`ExportQuantizer.swift`/`ExportNamer.swift`/
  legacy 三测试族/`ExportQueueTests`/`ExportNamingTemplateStoreTests`/
  `LibraryLegacyGateTests` **全部零 diff**。
- `LibraryLegacyGateTests` 全绿（gate 双向标记面未动——`visibleContentFaceMarkers`
  纯函数未触碰）。

## 双登记闭环（AC9）

- `Project.swift`：`ExportInspectorFaceTests` / `ExportMemoryKeysTests` /
  `ExportAssemblyTests` → `LightamerTestsApp`（3 行，字母序）。
- `M2-4-0-BUNDLE-MAP.txt`：同批三行（9/11/11）+ M2-9-04 增行记录注（运行期
  总数基线上移至 2662；行值 = 文件 `func test` 终态，M-1 教训执行——Assembly
  行初登 10 执行轮实测 11 即改 11）。
- 新测试文件落盘后 `tuist generate`（L041，每 T 一轮）。

## 偏差与发现（全部入 DECISIONS，逐条有据）

1. **越界三处（§1，晨审裁决点）**：Core 载体两面（03 交接钦定缺口）/ 
   WorkspaceHostView（E5 族 front-matter 遗漏）/ ToastFaceTests 环境随动
   （真因修复——不修则 App bundle 全量必崩，trap 实测在案）。
2. **per-image instancesOverrides 载体（§2）**：queue 批级单值装不下 KD-4
   逐图语义 → drtTails 同款索引载体（默认 nil = legacy 字节稳定，Export
   bundle 零漂移实证）。
3. **层语义边界（§3，晨审重点）**：M2 面带层图 override 腿 = base 链像素
   （renderer step-3 现行语义，11-04 起如此、非本波引入）；批量其余图恒盘上
   真相含层。走查批 M2-9-05 KD-1 #4 会暴露。
4. **projection 落点（§3）**：`projection(upTo:)` 字面 API 不存在 →
   M2-8 交接原文 `EditorState.instances`（base ∪ history.effectiveInstances()）。
5. **typed 质量读（§6）**：首版 presence-check 被自家测试抓出「异型值→0.0
   假记忆」→ `object as? Double` typed 读（L054 家族教训：defaults 面同样
   写读不对称）。
6. **App host crash ×2（T3 轮）**：① DrtPersistenceTests 中途
   abnormally（L055 签名瞬态，03 波同款，隔离复跑干净）；② ToastFaceTests
   trap = 真因（§1.3）修复闭环。终跑单轮干净。

## 交接（M2-9-05 消费缝）

- 走查入口：M2 工作区（editor phase）topBar `shell.topbar.export` 或
  File > Export → 检查器 Export 页（五节）；legacy 回切（env=1）页不可达、
  sheet 原样（走查 #10 双向）。
- 键登记：`export.lastDirectory` + 质量四键 + `export.namingTemplates`
  （01 已落）——M2-9-05 KD-3 AGENTS.md 键册补六键（含 namingTemplates）。
- exifSoftware 走查：出片 byte-scan {TIFF} Software = `Lightamer <ver>`
  （JPEG readback 不回显——L054，dump 走字节）。
- 尾追 token / add-start 塌缩 / 层语义 = 走查观感核对点（§12 晨审清单并行）。

## LESSONS

- **L056 候选**：SwiftUI `@Environment(Observable.self)` 在「测试最小宿主
  少注入一面」时 = **挂载即 trap**（非静默 nil）——给既有视图加新 env 依赖
  必须全仓 grep 测试挂载点随动（ToastFaceTests 先例）；反向纪律 = 最小宿主
  注入清单注释随视图依赖更新。
