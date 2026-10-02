# M2-10 Plan 集 checker 报告（执行前质量门，goal-backward 从严）

> checker subagent，2026-09-29/10-02 批。七 plan（M2-10-01..07）+ CONTEXT + RESEARCH-NOTES
> 全文审；源码亲核锚：LibrarySchema（v3 迁移链/dispatchSchema 快照轮换/FTS 触发器/
> reservedTableNames）、Project.swift（folderReference/测试显式清单）、LightamerApp
> EntryPoint 臂序、GlobalSearchDialog 双 marker、SettingsPage 两 case 预埋、
> BackgroundTaskHosting AI leg、runImport/ImportService per-file executor、
> LightamerSidecar v7、StableHash、ImportDefaults 键族、.gitignore、仓根 Resources/ 实态。

## 结论：FAIL / 5 error + 11 minor

5 error 修复后可复审转 PASS（均为 plan 文本级修订，无结构返工）。

---

## Error（必修）

### E1 — M2-10-01（T4/KD-4/front-matter）：`App/Resources/AIModels` 路径与 Tuist 资源根不一致，打包与体积红线机检双双断裂

- **事实亲核**：仓内**不存在 `App/Resources/`**（`App/` 下只有 `Extensions/`+`Sources/`）；
  App target 资源根 = **仓根 `Resources/`**（`Resources/Assets.xcassets`、
  `Localizable.xcstrings`、`LUTs`、`TestFixtures`，Project.swift :176-180）。
  Tuist `.folderReference(path:)` 相对 **Project.swift 所在目录（仓根）**解析——
  LUTs 先例 `.folderReference(path: "Resources/LUTs")` → `<root>/Resources/LUTs`。
- **矛盾点**：plan 01 front-matter/纪律 5 写 `App/Resources/AIModels/.keep` +
  gitignore `App/Resources/AIModels/**`；KD-4 又写 `.folderReference(path:
  "Resources/AIModels")`（标注「相对 App/」——**该标注对 Tuist 语义不实**）。
  按字面执行：folder reference 指向 `<root>/Resources/AIModels`（不存在），
  模型文件落在 `App/Resources/AIModels` 不被打包；gitignore 路径与 folder
  reference 脱节 → AC#5（git check-ignore）与 T4 AC#1（build 产物探针）失真。
  对照组：plan 07 的 `Resources/Localizable.xcstrings` 写法（仓根）才是对的。
- **checker-hint**：统一为仓根惯例——目录 = `Resources/AIModels/`，front-matter、
  `.gitignore` 增行（`Resources/AIModels/**` + `!.keep`）、`.folderReference(path:
  "Resources/AIModels")` 三处同改；`ModelLocator` 的 Bundle 子目录名仍是
  `AIModels` 不受影响。（若坚持 App/ 下，则 folderReference 必须带 `App/` 前缀
  ——两案取一，禁止混写。）

### E2 — M2-10-02（T1 action 4 / front-matter）：漏申报 2 个任务产出文件，diff 边界必违约

- T1 action 4 产出 `Scripts/ai-models/tokenizer_ref.py` + `Tests/Fixtures/
  tokenizer_golden.json`（KD-3 golden fixture 防手抄机制的承重文件），两者均
  **不在 files_modified**。纪律 8 + AC#10 要求收口 `git diff --stat` == 申报集
  → T5 收口必自判违约（checker 四条④ 自伤）。
- **checker-hint**：front-matter 补两行（脚本入 `Scripts/ai-models/`、fixture 入
  `Tests/Fixtures/` ≤10KB、头注记词表 revision 锁定——KD-3 语义照抄）。

### E3 — M2-10-03（T1 action 1 / front-matter）：跨 plan 修改 `build_default_bundle.sh` 未申报

- T1 action 1 明写「`Scripts/ai-models/build_default_bundle.sh` 追加原型生成阶段
  （`--with-label-prototypes` 开关）」，纪律 2 也承认该改动，但 front-matter
  files_modified **无此文件** → T3 diff 边界对表必违约；且这是 01 交付文件的
  跨 plan 修改，恰恰最需要显式申报（3a/3b 并行波 file-conflict 判定依据）。
- **checker-hint**：front-matter 补 `Scripts/ai-models/build_default_bundle.sh
  # 修改：--with-label-prototypes 原型生成阶段追加（01 契约只读追加）`。

### E4 — M2-10-01/02/03：CLIP 图塔输入 256² 契约未经研究证实（Chinese-CLIP ViT-B/16 实为 224²），跨 plan 硬编码

- **事实**：RESEARCH §1.1 的 256×256 是 **MobileCLIP2** 的输入尺寸；§1.2
  Chinese-CLIP 条目未给输入尺寸。Chinese-CLIP ViT-B/16 官方 ONNX 导出与 HF
  卡片为 **224×224**（patch16 → 14×14 grid；ViT 位置嵌入与输入尺寸绑定——
  强行 256² 导出要么转换期失败，要么走 pos-emb 插值**静默降质**）。
  但 plan 01 KD-1（manifest 初值「256²」+ 注释「CLIP 256」）、KD-2（转换脚本
  契约「image 输入固定 256×256」）、plan 02 KD-5（图像嵌入链）、plan 03 KD-3
  （「256² 预缩图」）全链继承此数——研究未对**本模型**建立该契约。
- **checker-hint**：①M2-10-01 T2 spike 首步先从 HF 卡片/官方 ONNX 实证输入尺寸
  （预期 224²），KD-2 契约改写为「image 输入固定 `<manifest.inputSize>`」；
  ②`ModelAssetManifest.inputSize` 定为**唯一常量源**：02 预缩图与 03 的预缩图
  改为「按 manifest.inputSize resize+center-crop（CLIP 标准预处理）」语义并各加
  一句 manifest 消费引用；清除字面 256 散落（03 尤其——它在 01/02 之后的波次，
  常量应从 01 产物读而非复制）。

### E5 — M2-10-02/04：`ai_understanding` 多行历史 × FTS 全行索引 = fulltext 检索会命中 active=0 的陈旧描述

- **推导**：02 KD-1/KD-2 设计 = 每图多行 understanding 历史（重跑新增 task_id 行、
  旧行 active=0 留痕）+ `ai_understanding_fts` external-content 三触发器（逐行
  同步，**无 active 概念**——images_fts 先例本就单行单图）。04 KD-4 消费 =
  「fts MATCH → 命中 rowid → image_id 集」，**未过滤 active=1** → 用户改描述后
  全文搜索仍会经陈旧行命中并可能展示旧 caption。AC#6/#7 按「MATCH 命中」断言
  不会抓住此缺陷 → 按 AC 执行会带 bug 交付。
- **checker-hint**：04 KD-4 检索腿补「MATCH 命中 rowid → JOIN ai_understanding
  过滤 `active=1`（同图多行取活跃行集）」；04 T3 测试补负测钉「旧 active=0 行
  不参与 MATCH 命中」（02 侧 schema 零改，纯查询腿语义）。

---

## Minor（建议修，不阻断）

- **M1 — 02（T3/AC#4）**：p50/p95 口径打架——T3 action 写「20 万行 p50 ≤ 50ms」，
  KD-4/AC#4/D-1 均为 **p95**（后手触发线）。统一 p95。
- **M2 — 02（T1）**：「链式 v1→v4 **两代**迁移」表述不准——dispatchSchema 一次
  `migrate(from: stored, to: schemaVersion)` 实为三腿（v1→v2→v3→v4）。
  测试名/注释按「全链 v1→v4」写，防执行者只测两腿。
- **M3 — 04（风险节）**：「与 M2-10-03 **零共享文件**」不实——两 plan 都改
  Project.swift + BUNDLE-MAP（测试登记）。改为「除 Project.swift/BUNDLE-MAP
  登记外零共享文件，冲突处置同 03」（03 风险节已自认，04 应同句对齐）。
- **M4 — 06（AC#4）**：「副本不入版本链」歧义——副本 = 新 images 行 + 自己的
  .lra，经**正常** sidecar→library 同步它自己会有单版本 version_ref 行。AC 改为
  「**原图** version_ref 零增量 + 无新版本语义机制（VersionCoordinator 面
  diff=0）」，防执行者断言「副本零 version_ref 行」与同步机制打架。
- **M5 — 02（T4）**：中文查询硬约束缺 AC 级落点——现只有 01 spike ③（人读
  sanity）+ 02 tokenizer golden（中文分词）。T4 的真模型端到端 sanity 明写
  「中文 query + 英文 query 各一条命中 sanity（资源门 skip）」，让 M2AI-01
  「中文文本塔可用」在检索面有可审计用例。
- **M6 — 05（T2 action 1）**：路径笔误 `App/Sources/Lightamer/AIWorkerClient.swift`
  漏 `AI/` 子目录；以 front-matter（`App/Sources/Lightamer/AI/AIWorkerClient.swift`）为准。
- **M7 — 02（KD-6）**：引用名漂移——「LibraryGridModel.applyFilter」实为
  `apply(filter:)`（:82）；GlobalSearchDialog marker 实际 :127-137（plan 引
  :129-137）。执行以实态为准。
- **M8 — CONTEXT（资产盘点表）**：「sidecar v7 零改动」行与 06 v8 additive 表面
  张力（D-3 已裁决 provenance 入 sidecar → 必然 bump）。建议该行加注「v7 读取
  字节兼容零漂移；写入面 v8 additive 归 06」，防后人引 CONTEXT 判 06 越界。
- **M9 — phase 对账口径**：七 plan estimated_tests 合计 **+202..254**（非任务书
  口径 +198..230）；基线 2577/16skip/0fail 已核（GOAL-STATE M2-8-VALIDATION
  `TOTAL|2577/16/0|896s`）。phase 终对账以 07 AC#8 BUNDLE-MAP 汇总为准。
- **M10 — 02（KD-1/T1）**：「四索引」只拼出三个（active 唯一 + understanding
  image + rating image）——第四个应为 `idx_image_embedding_model ON
  image_embedding(model_key)`（`loadScanRows(modelKey:)` 全扫前缀，PK(image_id,
  model_key) 不覆盖）。DDL 明示补齐。
- **M11 — 07（KD-2）**：`LibraryConnectionStore` 落 `App/Sources/Lightamer/
  Library/` 但语义是 AI 连接面——非阻断；若 App/Sources/Lightamer/AI/ 已由
  02 建目录，落 `AI/` 更贴切（二选一，登记为准）。

---

## 七维审查通过项（亲核记录）

1. **编译/迁移完整性**：`schemaVersion = 3`（LibrarySchema.swift:90）✓；migrate
   slot 形/:487、`createVersionRefTable` 幂等、user_version :394-407、FTS 三触发器
   先例 :307-341 均与 plan 引用吻合 ✓；**dispatchSchema 零改断言成立**——快照
   轮换按 `<stem>.pre-migrate.<stored>-<to>.bak` 世代化（M2-8 E2 教训已固化在
   通道内），v4 = 该通道自然延伸，v1-born 包全程覆盖 ✓；`triggerNames` 追加三名
   落点存在（:380）✓；`reservedTableNames` 断言准确（= edit_commit/image_edit_state/
   pipeline_root，语义七表从未入名单，「无预留翻面负测」判断正确）✓；版本 pin
   触点穷举与实态吻合（LibrarySchemaTests:316 `.futureSchema(version: 4)`、
   LibraryDocumentTests:180、DefaultLookTests:293）✓；新 Core 缝 AIInferencing
   Core↔App 分层（Core 协议+InProcess、App 装配）合规 ✓；05 worker 禁 SwiftUI
   import、`--ai-worker` 臂插 `--mcp` 后与 EntryPoint 实态臂序吻合（:72-81 实证）
   ✓；无模型环境 0 fail 语义全 plan 一致（探针+XCTSkip、mock/玩具向量、禁
   test-time 下载）✓。
2. **AC 与裁决一致性**：12 生效值逐条对——OQ-1-B（ViT-B/16 bundled）✓ 已同步
   REQUIREMENTS（commit `3791aed` 实证）✓、OQ-2-A（Jina 首发）✓、OQ-3-B
   （general-x4v3 内置 + x4plus/DRUNet Release）✓、OQ-5-A（同 binary 无 in-process
   兜底）✓、OQ-6-A ✓、OQ-7-A ✓、OQ-8-A ✓、OQ-9-A（partial unique index DB 级
   单激活）✓、OQ-10-C（8MB 分界）✓、OQ-11-A（前置确认门）✓、OQ-12-A（defer）
   ✓；D-1..9 全落 ✓；**无重开裁决** ✓；「16-bit 容器规则收窄」与 M2AI-09「随原
   格式」字面：8-bit JPEG/RAW 容器物理上不可承载 16-bit → 收窄是唯一自洽读法，
   plan 已诚实签注「有意偏离 + 晨审可翻」= 合规处置（非偷改裁决）✓；M2AI-08
   零 diff 在 04 AC#8 + 07 AC#5 **双锁**、07「互补核验」= 核验零新增 + defer
   记录，与 OQ-12-A 自洽 ✓。
3. **红线机检**：模型字节不入 git——gitignore「目录内容 `**` 排除 + `!.keep`
   反包含」模式语义正确（目录本体未排除，反包含生效），AC#5 git check-ignore +
   git ls-files 可机检——**但路径须先按 E1 修正**；digest fail-closed typed
   `.digestUnpublished`（01 AC#2）✓；key 不入 defaults/日志（04 纪律 3 golden
   断言 + 07 AC#2 defaults dump 负测）✓；zeroize 字节级 E4 断言 ✓；HTTPS 准入
   矩阵逐格机检 + 双检（存 key 前/发请求前）✓；本地不上云逐任务核——01/02/03/05/
   06 零网络面，04 纪律 2 `git grep URLSession` 机检仅 AIProviderClient 族命中 ✓。
4. **测试对账与资源**：基线 2577/16skip/0fail 实证（GOAL-STATE + M2-8-VALIDATION）
   ✓；估测合计 202..254（M9）；模型依赖测试 XCTSkip 资源门全 plan 一致，无模型
   环境 0 fail 可达（tokenizer/scanner/store/protocol/compat 全为无模型面）✓；
   内存面：06 100MP×4 ≈ 6.4GB 输出缓冲风险已列（tile 流水线化缓解 + MEMFAIL E3
   报备线明确）✓；02 scanner 20 万行 ≈ 数百 MB 合成数据安全 ✓；05 worker 推理
   在独立进程 = 隔离面本身 ✓。
5. **依赖链**：1→2→(3a∥3b)→4(=05)→5(=06)→6(=07) 波次成立；07 传递依赖 05 经 06
   覆盖 ✓；3a/3b 交集 = Project.swift/BUNDLE-MAP 登记面，03 已自认 rebase 处置
   （04 需按 M3 对齐表述）；每波独立提交 + 验收可行（收口任务 + SUMMARY/
   DECISIONS + GOAL-STATE 续接点齐全）✓；06 对 05 协议 `tile` 字段「05 已留位」
   断言实证（05 KD-1 envelope payload 已含 `"tile":{…}`）✓。
6. **goal-backward**：M2AI-01→01/02、02→02、03→03、04→04、05→04、06→04、
   07→03、08→07、09→06、10→05 全映射无遗漏 ✓；M2AI-10 三字面（崩溃不死/重试
   降级/记住组合）→ 05 AC#3/#4/#5 逐条落 ✓；中文查询硬约束检索面落点见 M5；
   副本「胶片条/网格可见 + 可继续调整」由新 images 行 + 自有编辑历史自然满足
   （OQ-4-A 已签）✓。
7. **网络安全面**：下载器 digest fail-closed ✓、下载源 failover（非重试）语义
   清晰 ✓、评片/描述无自动重试（04 KD-2 + DECISIONS 签注收窄）✓、HTTPS 强制 +
   loopback 三 host 显式例外（无暗开关，D-5 授权纬度内）✓。

## 其他核销

- `.work/config.toml [gsd]`：`auto = true` / `paused = false`——流水线可推进 ✓。
- `LibraryConnectionStore` 无同名冲突（全仓 find 零命中，确系新建）✓。
- Keychain service `com.kamasylvia.lightamer` 与 Project.swift bundleId 一致 ✓。
- `LibraryGridModel.apply(filter:)`/`LibraryStore.addImage`/`PipeCoordinator`/
  `SessionThumbnailProvider`/`zh-audit.py`/`test-direct.sh` 全实存 ✓。
- App 非 sandbox（`ENABLE_USER_SELECTED_FILES: read-write`，unsigned 分发路线）
  → OQ-5-A 同 binary 子进程无权限障碍 ✓。

## 处置建议

E1..E5 均为 plan 文本级修订（front-matter 补行 / 路径统一 / 常量源收敛 / 查询腿
补一句 + 一条负测），预计一次 planner 修订批可清零后复审转 PASS。error 修复前
**不派发** M2-10-01（E1/E4 其源头）；02..07 的修订随批同步（E2/E3/E5/M1..M11）。
