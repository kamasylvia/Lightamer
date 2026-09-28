---
phase: m2-2
plan: "M2-2-2"
title: "导入管线——文件夹批量导入三方式（移动/复制/软链接，M2LIB-07①②③⑤）+ RAW-only 过滤加固三 AC（M2LIB-03：白名单精确后缀/黑名单附属文件/合成 C1 Session fixture 断言 RAW 数）+ 进度反馈 + 项目包开关 App 面（OQ-1 A：NSOpenPanel/NSSavePanel + Recent + backup/move 命令）+ 导入询问对话框与进度最小功能 UI"
wave: 2
depends_on: ["M2-2-1"]
autonomous: true
requirements: [M2LIB-03, M2LIB-07, M2LIB-01]
files_modified:
  - LightamerCore/Sources/Library/ImportFilter.swift            # 新建：白名单最后一后缀精确匹配（case-insensitive；默认面 = LibrarySchema 14 项；UserDefaults 可配宿主）+ 硬编码排除表 + 点开隐藏文件
  - LightamerCore/Sources/Library/ImageLinker.swift             # 新建：path_kind resolve（项目相对/卷相对+UUID/绝对）+ stale 检测（路径不存在或 UUID 不符）+ relink 数据面
  - LightamerCore/Sources/Library/ImportService.swift           # 新建：actor——递归扫描→计划→逐文件执行（move rename-first 跨卷 copy+校验+删源 / copy 校验+重复跳过 / link 经 ImageLinker）+ `.lra` 随迁语义⑤ + 进度快照 + 取消
  - App/Sources/Lightamer/Library/LibraryProjectController.swift # 新建：create/open/recent（UserDefaults `library.recentProjects`）/backupProject/moveProject 命令面（backupProject 走 ProjectFileStore.backup；moveProject = 整项目目录搬移，不经 backup API——KD-5）
  - App/Sources/Lightamer/Library/ImportModeDialog.swift        # 新建：三选对话框（默认复制 + 「记住我的选择」UserDefaults `library.import.mode`/`library.import.rememberMode`）
  - App/Sources/Lightamer/Library/ImportProgressView.swift      # 新建：最小进度覆盖层（计数/失败/跳过 + 取消）
  - App/Sources/Lightamer/UI/LightamerApp.swift                 # 修改：无项目时新建/打开入口（OQ-1 A Welcome 语义最小面）+ 导入流程接线（选文件夹→对话框→ImportService→Store/Indexer）
  - Tests/LightamerTests/ImportFilterTests.swift                # 新建（→ tuist generate）：AC①白名单精确后缀（`.ARW.xmp` 拒）+ AC②排除表/隐藏文件 + 可配宿主读写
  - Tests/LightamerTests/ImageLinkerTests.swift                 # 新建：三类 path_kind resolve / stale 两形态 / relink 重建
  - Tests/LightamerTests/ImportServiceTests.swift               # 新建：AC③合成 C1 Session fixture（导入数==RAW 数）+ 三方式逐条（校验前永不删源红钉/逐文件校验/重复跳过）+ sidecar 随迁⑤ + 进度/取消
  - Tests/LightamerTests/LibraryProjectControllerTests.swift    # 新建：recent 去重/上限 + backup 调用透传 + moveProject 整目录搬移后 kind0 resolve 命中 + 默认复制/记住选择读写
  - .work/gsd/phases/m2-2-library-project/M2-2-2-SUMMARY.md     # 新建（收口任务）
  - .work/gsd/phases/m2-2-library-project/M2-2-2-DECISIONS.md   # 新建（收口任务）
  - .work/GOAL-STATE.md                                         # 续接点追加（收口任务）
  - .work/LESSONS.md                                                  # 如踩坑
---

# Plan M2-2-2 — 导入管线（三方式 + 过滤加固 + 最小功能 UI + 项目开关面）

> **性质**：M1 资产高复用 plan——消费 M2-2-1 定死的全部缝（`ProjectFileStore`/
> `LibraryStore`/`ExifSearchIndexer`/`LibrarySchema` 白名单常量），新增导入三方式
> 服务与过滤加固，附功能闭环所需的最小 App UI（OQ-11 切分线：对话框 + 进度 = M2-2；
> 图库网格/Inspector 壳 = M2-3）。上游缺陷反向教训（Alcedo 0.3.0 导入链零过滤）是
> 本 plan 的验收核心：**三条加固 AC 全部机检**。

## 已定裁决（不得重开）

- **OQ-4**：对话框默认 = **复制**；「记住我的选择」存 UserDefaults，设置页可改可重置
  （设置页 UI 族归 M2-3/M2UIW-05，本 plan 落 UserDefaults 键与读写缝）；单次对话框可改。
- **OQ-5**：软链接导入默认**相对链接**（同卷 = 卷相对路径 + volume UUID，免疫挂载点
  改名——`/Volumes/UNITEK` L009 场景）；跨卷降级**绝对 + volume UUID**；stale = 路径
  不存在或 UUID 不符；relink 数据面本 plan 落（Inspector 批量 relink UI 归 M2-3）。
- **OQ-12**：白名单默认面 = LibrarySchema 常量（Alcedo 十种 ∪ `.pef/.orf/.rwl/.iiq`）；
  可配宿主 = **全局 Settings（UserDefaults `library.import.rawExtensions`，跨项目
  一致）**；附属排除表硬编码不可配（M2LIB-03 AC①②字面）。
- **M2LIB-07 实现约束（需求钉死）**：①移动 = 同卷 rename 优先、跨卷自动回退
  copy+校验+删源（**校验通过前永不删源**）；②复制 = 进度反馈 + 逐文件校验（字节/哈希）
  + 重复检测跳过；③软链接 = 相对/绝对随卷型；⑤三模式 `.lra`/附属 sidecar 随迁语义
  一致（移动/复制随行、软链接指向原位）。
- **OQ-1**：`.lalb` 由 NSSavePanel/NSOpenPanel 自选位置 + Recent Projects（UserDefaults）+
  启动无 recent/无项目时展示新建/打开入口；v1 单窗口单项目（完整 Welcome/双工作区壳
  归 M2-3，本 plan 落命令面 + 最小入口）。
- **fixture 口径（用户裁决，覆盖 AC③「真实目录」字面）**：验收 fixture = **合成
  C1 Session 形态**——真实目录结构（`Capture/RAW/` 子树）+ ARW 命名 + `.ARW`+`.ARW.xmp`
  对 + 噪声文件（`.tif`/隐藏文件/子目录），**字节为合成数据，勿拷真片**（样张版权）；
  结构保真足以复现「文件数翻倍」缺陷形态，断言语义（导入数 == RAW 数）不变。真实
  C1 Session 目录复跑 = Manual-Only 观察项（SUMMARY 登记）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 过滤 = 单一纯函数面，三处消费共享

`ImportFilter.select(_ urls: [URL]) -> (accepted: [URL], rejected: [ImportRejection])`
纯函数（无 IO 依赖，除 `isHidden`），判定序：①点开隐藏文件拒（`.` 前缀 + macOS
hidden flag）；②硬编码排除表（最后后缀 ∈ {xmp, lra, lightamer-preset, pp3, opc}
精确匹配）拒；③白名单（最后后缀精确匹配、case-insensitive——`photo.ARW.xmp` 的
最后后缀是 `xmp`，天然被 ② 拒；`photo.arw` 命中；`photo.ARw` 命中；无后缀拒）。
`ImportRejection` 带 typed 原因（`hidden`/`sidecar`/`extensionNotWhitelisted`）供
进度面板与测试断言。可配宿主只替换白名单集（UserDefaults 读 → 归一化小写 → Set），
排除表永不读配置（OQ-12 裁决：配了就会有人把 `.xmp` 配回来）。

### KD-2 三方式统一执行骨架 = plan → per-file executor → commit

`ImportService.importFolder(_ plan: ImportPlan) async throws -> ImportOutcome`：
扫描（`ImportFilter`）→ `ImportPlan`（每文件：源 URL + 目标策略 + mode）→ 逐文件
executor（进度快照 + 取消检查点 per-file）→ 单事务入 `LibraryStore`（images 行 +
`ExifSearchIndexer.fillMetadata` 批尾 + FTS rebuild）。**DB 行只在文件落位成功后写**
——崩溃最坏丢「已拷文件未建行」（下次导入重复检测跳过），不产生幽灵行。

- **move**：同卷（`FileManager.contentsEqual` 卷判定 = `volumeUUID` 相等，落
  `renameItem` 优先；失败/跨卷回退 copy→verify→`removeItem` 源；verify = 尺寸相等 +
  FNV-1a 64 内容哈希相等（`StableHash` 既有实现），**verify 通过前 remove 永不调用**
  ——测试红钉：stub verify 失败断言源文件仍在）。
- **copy**：逐文件 copy + 同款 verify + 重复检测（目标 `Media/<folderName>/<rel>`
  已存在且哈希相等 → skip 计数；存在但哈希不等 → `<stem>-1` 递增避让，Phase 11
  namer 先例）。
- **link**：不搬文件——images 行 `path_kind=1/2` + `volume_uuid` + 原路径（KD-3）；
  `.lra` 留原位（⑤）。
- **sidecar 随迁（⑤）**：move/copy 对每个 accepted 文件同名单 `.lra`（及 `.xmp`）
  随行 rename/copy（存在才随，随行失败 = 该文件整体失败回滚已拷字节）。

### KD-3 落位形态：Media/<sourceFolderName>/<源相对子树>

copy/move 目标 = `<项目目录>/Media/<sourceFolderName>/<源子树相对路径>`（KD-1 P1
常量）；images 行 `path_kind=0` + 项目相对 path（整目录移动免疫挂载点改名）。link
行 resolve 规则（`ImageLinker.resolve`）：kind1 = 项目所在卷 volumeUUID 匹配 →
卷根 + rel path；不匹配 → 遍历已挂载卷按 UUID 匹配；kind2 = 绝对路径 stat；均失败
= stale（`pathMissing` / `volumeAbsent` 两形态，typed 枚举）。`relink(to: URL)`
= 重选文件夹重建 kind/uuid/path（批量面，P4 后 M2-3 挂 UI）。

### KD-4 对话框/进度 = 无副作用 SwiftUI 薄壳，状态面 Core 可测

`ImportModeDialog` = 纯绑定视图（三选 segment + 记住 checkbox + 目录摘要行），选择
结果回落 `ImportModeChoice`（Codable struct，Core 定义，测试直构）；UserDefaults 读写
集中在 `ImportDefaults`（Core 级小类型：`mode`/`remember`/`rawExtensions` 三键 + 测试
注入 `UserDefaults` suite——M2-1 D-EXEC-1 face 注入教训：**禁 view body 直读静态
env/defaults**）。`ImportProgressView` 消费 `ImportProgress` 快照 struct（total/
processed/failed/skippedDuplicates/bytes + phase 枚举 + cancelled），由
`ImportService.progressHandler` 缝推送（CatalogRebuilder `setProgressHandler` 同型）。
取消 = generation 计数（ExportQueue cancel 先例）。

### KD-5 项目开关面 = Controller 命令族，welcome 入口最小化

`LibraryProjectController`（`@Observable`）持有当前 `ProjectFileStore` 句柄 +
`recentProjects`（UserDefaults 数组，去重 + 上限 10 + 失效路径启动清扫——Phase 9
recent 去重/上限先例同型）。命令面：`createProject(savePanel:)`/`openProject(
openPanel:)`/`openRecent(url:)`/`backupProject(to:)`/`moveProject(to:)`。**move =
整项目目录搬移**（KD-1 包目录口径：先 `ProjectFileStore.close()` → 目录级
`renameItem`；跨卷 = copy+verify+删源——**M2LIB-07① 同纪律复用，verify 通过前
永不删源**；`.<stem>.lathumbs/` 为派生物可丢弃不搬，新位首访重建）→ 打开新位。
**backup API（`sqlite3_backup`）只留 `backupProject` 一个消费者**，move 不经它
（单文件拷贝搬不走 `Media/` 物理照片，旧「close → backup API 拷 → 打开新位」措辞
作废）。`LightamerApp`
接线：无项目态显示「新建项目 / 打开项目 / 最近」最小入口（对齐 OQ-1 Welcome 语义；
完整壳 M2-3）。**本 plan 不动 Sidebar/ContentView 的 Session 面**（剥离归 P4）——
当前默认仍是 M1 Session 面，项目入口为并列新增路径，二者并存的整理在 M2-2-4
统一收口。

### KD-6 EXIF 键位零重发明

`ImportService` 落位成功即调 `ExifSearchIndexer.fillMetadata`（M2-2-1 T3 缝，ImageIO
键位 == SessionIndexSchema v2 同集）；本 plan 不新增任何 EXIF 键读取代码。RAW 抽样
交叉 = 测试内用 `input/RAW/` 既有样张（gitignore，存在才跑，否则 skip——与
`SessionThumbnailProvider` 测试供件模式同型）。

## read_first

1. `.work/gsd/phases/m2-2-library-project/M2-2-1-PLAN.md`——缝正本（KD-1 包目录/
   白名单常量/ExifSearchIndexer/LibraryStore API 形态）。
2. `.work/gsd/phases/m2-2-library-project/M2-2-CONTEXT.md`——OQ-1/4/5/12 裁决文本 +
   M2LIB-03 加固 AC 三条原文。
3. `.work/gsd/REQUIREMENTS.md` M2LIB-03/07——实现约束①②③⑤逐条。
4. `LightamerCore/Sources/Library/LibrarySchema.swift`——白名单/排除表/Media 常量
   （消费点）。
5. `LightamerCore/Sources/Library/ProjectFileStore.swift` + `LibraryStore.swift` +
   `ExifSearchIndexer.swift`——actor 缝（withHandle/progressHandler 形态）。
6. `LightamerCore/Sources/Foundation/` 下 `StableHash`（FNV-1a 64——verify 哈希复用）。
7. `LightamerCore/Sources/Catalog/CatalogRebuilder.swift:104`（setProgressHandler 缝）
   + `App/Sources/Lightamer/Catalog/CatalogPreferences.swift`（UserDefaults 键宿主
   先例）。
8. `App/Sources/Lightamer/UI/LightamerApp.swift`——窗口/场景结构（接线落点；
   M2-1 populate/seed 组装点 :867/:1481 附近为既有参考锚）。
9. `.work/LESSONS.md` L009（USB 卷/原子写）、`.work/09/` recent 先例（去重/上限）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使句、
   body 写 what+why）；只 add 本任务申报文件；**不 push**；`.work/gsd/...` 真路径。
2. **构建纪律**：`caffeinate -dis` 包裹构建；不加 `-derivedDataPath`；新建 .swift 后
   同 commit `tuist generate`。
3. **测试纪律**：`Scripts/test-direct.sh '<Class>'`，Executed + failures 双读（L028）；
   **基线 = 1889 + M2-2-1 新增（读 `.work/GOAL-STATE.md` 续接点取最新）**；全套 0 fail；
   在案 flake ×3 归因。
4. **边界纪律**：每任务边界查 `.work/config.toml [gsd]`。
5. **架构红线**：禁触 `LightamerCore/Sources/{Pipe,Sidecar,Metal,Decode}/`；
   `Session/` 域零改动（EXIF 走 M2-2-1 Indexer 缝）；**测试临时文件一律 `/tmp` 或
   temp dir，禁外置卷落库**（L009）；文件操作用 `FileManager` 且 copy/rename 后
   verify（红钉测试随 T3 落）。

## Tasks

### T1 ImportFilter——AC①② 机检

- **read_first**：上列 1/2/4。
- **action**
  1. 新建 `LightamerCore/Sources/Library/ImportFilter.swift`（KD-1：select 纯函数 +
     `ImportRejection` typed 原因 + `ImportDefaults`（UserDefaults 三键注入式宿主，
     KD-4））。
  2. 新建 `Tests/LightamerTests/ImportFilterTests.swift`（→ `tuist generate`）：
     - **AC①**：`photo.ARW`/`photo.arw`/`photo.ARw` 收；`photo.ARW.xmp` 拒
       （最后后缀 `xmp`）；`photo`（无后缀）拒；`photo.jpeg`/`photo.tif` 拒（默认白
       名单无）；大小写不敏感矩阵逐条。
     - **AC②**：`.xmp/.lra/.lightamer-preset/.pp3/.opc` 五类全拒（即使伪造
       `raw.xmp.arw` 形态？——否：该形态最后后缀 arw 会收；断言文档钉「过滤按最后
       后缀」，双后缀伪装由 ③ 命中白名单语义裁决，与需求字面一致）；`.` 前缀隐藏
       拒；macOS hidden flag 拒（`Foundation` `isHidden` stub 或临时文件实测）。
     - **可配宿主**：注入 suite 写 `library.import.rawExtensions`（增 `mos`）→ 收
       `.mos`；重置 → 默认 14 项；排除表不受配置影响（写配置试图放行 `.xmp` → 仍拒）。
  3. 全套回归 0 fail。
- **验收标准**
  - [ ] AC① 白名单精确最后后缀（大小写不敏感）断言全绿。
  - [ ] AC② 排除表五类 + 隐藏文件拒，且配置不可放行 sidecar——全绿。
  - [ ] `ImportDefaults` 注入式读写 + 重置全绿；全套回归 `0 fail`。

### T2 ImageLinker——resolve/stale/relink 数据面

- **read_first**：上列 1（P1 KD-1 path_kind 冻结列）/5。
- **action**
  1. 新建 `LightamerCore/Sources/Library/ImageLinker.swift`（KD-3：resolve 三形态 +
     `StaleReason` 枚举 + `relink(to:)` + `volumeUUID(of: URL)` helper
     （`urlResourceValues.volumeUUID`？——实际用 `URLResourceKey.volumeIdentifierKey`，
     不可得时 typed 降级 kind2））。
  2. 新建 `Tests/LightamerTests/ImageLinkerTests.swift`：
     - kind0 项目相对：项目目录整体改名后 resolve 仍命中（挂载点免疫语义复钉）。
     - kind1 卷相对：同卷命中；UUID 不匹配 → `volumeAbsent` stale。
     - kind2 绝对：命中 / 文件删除 → `pathMissing` stale。
     - relink：stale 行重指新目录后 resolve 命中 + kind/uuid 重算正确。
- **验收标准**
  - [ ] 三形态 resolve + 两 stale 原因 + relink 全绿；项目目录改名免疫断言在册。
  - [ ] 全套回归 `0 fail`。

### T3 ImportService——三方式 + AC③ fixture + 进度/取消

- **read_first**：上列 1/3/5/6 + `Tests/LightamerTests/` 内既有 fixture 供件模式
  （grep `input/RAW` 用法）。
- **action**
  1. 新建 `LightamerCore/Sources/Library/ImportService.swift`（KD-2 骨架 + KD-4
     progress 快照/generation 取消 + KD-6 EXIF 接线 + sidecar 随迁⑤）。
  2. 新建 `Tests/LightamerTests/ImportServiceTests.swift`：
     - **AC③ fixture**（合成 C1 Session 形态，temp dir）：`<root>/Capture/RAW/` 下
       6 × `.ARW`（合成字节）+ 各配 `.ARW.xmp` + 2 × `.tif` + 1 × `.hidden` +
       1 × 子目录内 `.ARW`；断言 **导入数 == 7（RAW 数）而非文件数**、rejected 分类
       计数精确。
     - move：同卷 rename（源消失 + `Media/` 落位 + `.lra` 随行）；**红钉**——注入
       verify 失败（`verifyStrategy` 注入缝）断言跨卷腿源文件仍在、行未建、outcome
       failed 计数 1。
     - copy：verify（尺寸+哈希）逐文件；同内容二次导入 → skipDuplicates；同名不同
       内容 → `-1` 递增避让；进度快照序列单调（processed ≤ total）。
     - link：源不动 + 行 `path_kind`/`volume_uuid` 正确 + `.lra` 留原位（⑤）。
     - 取消：per-file 检查点 cancel → 部分结果 + 已建行数 == 已拷文件数（无幽灵行）。
     - EXIF：accepted 行 `camera_model` 等物化列已填充（小合成 JPEG-with-EXIF 或
       `input/RAW` 存在时真样张，否则该断言 skip 记录）。
  3. 全套回归 0 fail。
- **验收标准**
  - [ ] **AC③：合成 C1 Session fixture 导入数 == RAW 数（7），xmp/tif/隐藏零入库**
        ——断言在册全绿。
  - [ ] 三方式语义逐条绿；「verify 通过前永不删源」红钉绿；sidecar 随迁⑤绿。
  - [ ] 进度/取消/重复检测/无幽灵行全绿；全套回归 `0 fail`。

### T4 App 最小功能 UI + 项目开关面

- **read_first**：上列 7/8/9 + `App/Sources/Lightamer/Catalog/CatalogPreferences.swift`
  （键宿主与 @Observable model 先例）。
- **action**
  1. 新建 `App/Sources/Lightamer/Library/LibraryProjectController.swift`（KD-5）+
     `ImportModeDialog.swift` + `ImportProgressView.swift`（→ `tuist generate`）。
  2. `LightamerApp.swift` 接线：无项目入口（新建/打开/最近三按钮最小列）+ 选文件夹
     导入命令（NSOpenPanel）→ dialog → ImportService.run → 进度覆盖层；**不触
     Sidebar/ContentView**（P4 剥离另批）。
  3. 新建 `Tests/LightamerTests/LibraryProjectControllerTests.swift`：recent 去重/
     上限 10/失效清扫；默认复制 + remember 写读 + 单次覆盖不落盘（remember=false
     时下次仍默认复制）；backup 命令透传 ProjectFileStore（temp 项目实测）；
     **moveProject 整目录搬移**——temp 项目 + 若干 kind0 行 → 同卷 rename move 后
     新位 open 成功且 **kind0（项目相对路径）resolve 命中**（KD-3 ImageLinker 链，
     挂载点免疫语义实链复钉）；verify 失败注入腿（复用 T3 `verifyStrategy` 缝）断言
     源项目目录原样在（M2LIB-07① 红钉同款）。ImportModeDialog/ProgressView 无状态
     薄壳不设 UI 测试（逻辑全在 Core 可测类型，SUMMARY 声明）。
  4. 全套回归 0 fail。
- **验收标准**
  - [ ] recent 去重/上限/清扫 + 默认值语义（记住=false 不持久化单次选择）+ backup
        透传全绿。
  - [ ] moveProject 整目录搬移后 kind0 resolve 命中 + verify 失败源项目目录原样在，
        全绿。
  - [ ] App 接线编译面零 Sidebar 改动（diff 自检）；全套回归 `0 fail`。

### T5 收口

- **read_first**：本 plan AC 表。
- **action**：AC 逐条机检 + 全套终跑；落盘 `M2-2-2-SUMMARY.md`（测试数/Manual-Only
  观察项：真实 C1 Session 目录复跑、导入吞吐软指标）+ `M2-2-2-DECISIONS.md`；
  `.work/GOAL-STATE.md` 续接点追加；`git diff --stat` 边界核对。
- **验收标准**
  - [ ] AC 表全绿；SUMMARY/DECISIONS/GOAL-STATE 同批落盘；边界无越界。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | AC①：白名单按最后后缀精确匹配、case-insensitive（`photo.ARW.xmp` 拒 / `photo.arw` 收 / 无后缀拒 / 非白名单格式拒） | ImportFilterTests 矩阵 |
| 2 | AC②：`.xmp/.lra/.lightamer-preset/.pp3/.opc` + 隐藏文件全拒；配置无法放行 sidecar | ImportFilterTests |
| 3 | AC③：合成 C1 Session fixture（`.ARW`+`.ARW.xmp` 对 + 噪声 + 子目录）导入数 == RAW 数 | ImportServiceTests fixture 断言 |
| 4 | move：同卷 rename 优先；跨卷 copy→verify→删源；**verify 失败源文件仍在 + 无行**（红钉） | ImportServiceTests 注入腿 |
| 5 | copy：逐文件校验（尺寸+FNV-1a）+ 重复跳过 + 同名异内容 `-1` 避让 | ImportServiceTests |
| 6 | link：源不动、kind/uuid 正确、`.lra` 留原位；stale 两形态 + relink 重建 | ImportServiceTests + ImageLinkerTests |
| 7 | sidecar 随迁⑤：move/copy 随行 `.lra`（失败回滚）；link 指向原位 | ImportServiceTests |
| 8 | 进度快照单调 + per-file 取消无幽灵行；EXIF 物化列填充 | ImportServiceTests |
| 9 | recent 去重/上限/清扫；默认复制 + remember 语义；backup 透传；moveProject 整目录搬移后 kind0 resolve 命中（verify 失败源目录原样在） | LibraryProjectControllerTests |
| 10 | 全套回归 0 fail（基线 + M2-2-1 新增 + 本 plan ≈ +25..35） | test-direct.sh 双读 |
| 11 | diff 边界 == 申报文件集；`Session/` 域零改动 | `git diff --stat` |

## 风险与边界

- **fixture 版权**（用户裁决）：合成字节 + ARW 命名 + 真实目录形态；真实 C1 Session
  目录（用户盘 `Capture/RAW`）复跑 = Manual-Only 观察项入 SUMMARY，不入自动验收。
- **USB 卷软链接相对化（L009）**：kind1 卷相对路径依赖 volumeUUID 可读性；实测不可得
  时 typed 降级 kind2 + SUMMARY 登记；测试全在 temp dir 逻辑测，不依赖真实外置卷。
- **跨卷判定**：`URLResourceKey.volumeIdentifierKey` 同卷判定实现（rename 跨卷会
  `ENOENT`/部分拷贝语义，必须先判后走）；判定失败保守走 copy 腿（安全方向）。
- **大目录扫描阻塞**：扫描在 ImportService actor 内后台 Task，进度快照含 scan phase；
  v1 无分批流式（观察项：吞吐 ≥100 张/min 软指标，P3 基准复测）。
- **与 M1 Session 面并存**（KD-5）：本 plan 后 app 同时可见 Session 默认面与项目入口
  ——属过渡态，M2-2-4 剥离门统一收窄；不在此提前动 Sidebar（防 P4 前测试面漂移）。

## 提交约定

- T1 `feat(library): import filter with raw whitelist and sidecar exclusions`
- T2 `feat(library): image linker with volume-relative paths and stale faces`
- T3 `feat(library): import service with three modes and progress`
- T4 `feat(app): minimal project and import ui face`
- T5 `docs(m2-2): close out plan 2 import pipeline`
- 全英文 Conventional Commits；body 写 what+why + 同批 md 清单；不 push。
