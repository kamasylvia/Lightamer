---
phase: M2-10
slug: ai-library
status: validated
nyquist_compliant: true
created: 2026-10-02
validated: 2026-10-07
---

# Phase M2-10 — Validation（AI 图库：M2AI-01..10 三列证据 + Per-Plan Map + 晨审裁决项汇总 + 授权记录）

> 体例对齐 `phases/m2-9-export/M2-9-VALIDATION.md`（frontmatter / Checklist）。
> **翻账只认证据**：SC 表逐条「SC 原文 + 证据指针（测试名 + 数字 + commit SHA +
> ACCEPTANCE 节）+ 判定」；无证据 ✅ = 违规。**SC 数字对账基线 = M2-10-07 续班
> 终轮全套 `TOTAL|2955/16/0|1019s` 亲证值**（2026-10-07 build-for-testing 重建
> BUILD_EXIT=0 后 `--all` 单轮干净绿；`M2-10-07-SUMMARY.md` §交付面 8 + 续班
> 注记；六 bundle 基线零漂移 + App 630/0/0，SidecarV5 ANE flake 复绿 13.338s，
> peakRSS 最大 5737MB < 8192 门零 MEMFAIL，skip 16 零新增，L055 七日志
> abnormal 全零）。对账链：**2693（M2-9 终）→ 2718 → 2759 → 2797 → 2863 →
> 2890 → 2926 → 2929（`c573087` M-1 修复批 +3）→ 2955**，逐 plan 有独立验收
> 复跑背书。本 phase **零 error 级 FINDING**（七轮验收：01..06 全 PASS /
> 0 error，minor 三件均验收批闭环；07 执行批 ANE flake 环境型记账收口）——
> 签核 = 带挂账清单 + 晨审裁决项照常放行。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 真链装配 / 直启宿主 / 真子进程探针 / 真模型激活态） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启；`--bundle`/`--all`） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **2955 tests / 16 skip / 0 fail**（1019s，2026-10-07 续班终轮，BUILD_EXIT=0；`M2-10-07-SUMMARY.md` 续班注记；零 MEMFAIL 峰值 IOP 5737MB） |
| **基线演变** | M2-9 末 2693 → M2-10-01 +25（**2718**：Catalog 13 + Store 12）→ M2-10-02 +41（**2759**：Schema +4 / WordPiece 9 / SemanticStore 10 / Scanner 8 / SemanticSearch 10）→ M2-10-03 +38（**2797**：LabelEngine 12 + AnalysisRegistry 13 + LabelingDefaults 13）→ M2-10-04 +66（**2863**：EndpointPolicy 9 + CredentialStore 7 + ProviderClient 22 + RatingDescription 15 + FulltextSearch 13）→ M2-10-05 +27（**2890**：WorkerProtocol 10 + CompatRecord 8 + WorkerClient 9）→ M2-10-06 +36（**2926**：TileInference 13 + SidecarV8 5 + EnhanceCopy 8 + EnhanceDialog 10）→ `c573087` M-1 修复批 +3（**2929**，EnhanceDialog 回归）→ M2-10-07 +26（**2955**：ACASettings 10 + LCRSettings 10 + AIEntryPoints 6）；skip 恒 16 |
| **在案 flake** | SidecarV5Tests ANE 环境型 flake——**五波台账两红三绿终态**（01 执行 / 06 验收 / 07 首轮红；07 补跑 / 07 续班终轮绿 13.338s）：宿主 ANE 编译态劣化窗口（`ANECCompile() FAILED`），隔 ~68h 重启复绿支持环境型归因；域零接触机检四波在案；Phase 15 flaky 清算批立案输入（GOAL-STATE 阻塞节）。Library 缩略图队列 flake（05 验收 O-1，06/07 未复现）——沿用既有台账。L055 test-direct.sh 崩溃假绿解析器（03 起挂，脚本修复另案） |
| **真模型激活态** | 多波非 skip 亲点：02 sanity zh/en 2.373s + 03 真原型 2.586s + 05 worker 真链 2.409s + 06 金样 64²→256² ≤1/255 3.352s + 04 真宿主 keychain 7/0/0——终轮 `--all` 资源门在场环境全激活 |
| **GUI 证据** | 本 phase headless 交付——设置页/对话框视觉走查 = marker/AX 机检（AIEntryPointsTests marker 冻结集 7 枚）+ 模型级测试为门；Alcedo 对照截图走查移交 M2-11（`M2-10-VALIDATION-INPUT.md` 观察项 5） |
| **zh 对账** | `zh-audit --check` **PASS**（1505 source keys / 1753 catalog keys / zh complete / locale {en, zh}；07 续班亲跑复现，本签核批第三次复现） |

---

## M2AI-01..10 对照表（ROADMAP §M2-10 行契约 = REQUIREMENTS AI2 族，三列证据）

| SC | 判据（SC 原文） | 证据指针（测试名 + 数字 + commit SHA + ACCEPTANCE 节） | 判定 |
|---|---|---|---|
| **SC#1** | **M2AI-01 本地 CLIP 嵌入——CoreML 档模型可选，本地运行不上云；混合获取（默认内置 + Release 下载版本锁死 + HF 兜底）；OQ-1 裁决默认档 = Chinese-CLIP ViT-B/16 质量档** | **模型资产半边**：`2d897ad`/`6a7e81e` 五档位编译期清单 + digest 三方互验（shasum 手搓独立复核 img `f3edaccb…`/92,558,991B 等四组全对）+ E4 inputSize 224² 双证 + fail-closed（`testDigestUnpublishedFailClosed` + `testReleaseDigestsUnpublishedFailClosed`）+ 三源次序固定 + 流式 SHA-256 + 同目录 tmp 原子晋升（StoreTests 12 + CatalogTests 13 全绿）；`318a473` 转换脚本族 + SPIKE（int8 16.21ms/5.59ms + A/B 平级 mlprogram 裁决）；`git ls-files Resources/AIModels/` 仅 `.keep`（体积红线，验收亲跑）；全套 **2718/16/0**（01 验收 §一/§机检）。**设置 UI 半边**：`47e46c4` LCR 页五档位清单（状态六态/许可/体积/徽标/**待发布禁点** = digestUnpublished 无下载按钮 fail-closed UI 面）+ 下载/移除/换激活（确认 → `registry.recomputeAll` 入队断言，真 registry drain）+ 就绪探针三态 + 本地数据政策脚注；LCRSettingsTests 10；终轮 **2955/16/0**（07 SUMMARY §交付面 1） | ✅ |
| **SC#2** | **M2AI-02 嵌入存储+ANN 检索（SQLite 向量方案执行时定）+ 自然语言搜索入全局搜索** | `882f97a` LibrarySchema v4 additive 七表（user_version 3→4，v1/v2/v3 三出生形态单 dispatch 全链迁移测试 + OQ-9-A 单激活 partial unique DB 级强制 + fp16 BLOB + 四域 CASCADE）+ `2aa4179` WordPieceTokenizer（golden 12 句 revision 锁定 9 法）+ SemanticStore 四域 actor；`4ddb71a` vDSP 精确全扫（D-1 用户裁决闭合 ANN 条款——`testScanBudget200KRowsWithinP50Of50ms` 哨兵 + **200k×512 median 32.05ms ≤50ms 硬门 PASS**，验收轮 100k 档 15.98ms 逐位重合）；`a181890` GlobalSearchDialog CLIP tab 真腿（EXIF 腿零触碰 hunk 机检 + typed `.modelUnavailable` 诚实空态 + 真模型 zh「蓝天白云」/en sanity 2.373s 非 skip）；全套 **2759/16/0**（02 验收 §一/§检索性能独立复测/§AC 总表 1-9） | ✅ |
| **SC#3** | **M2AI-03 自动打标——出厂中英 label query 原型余弦（score/second_label/margin/confident）+ 导入后询问 Remember-my-choice** | `f15bb96` LabelQueries 173 标签 × zh/en 单源（`testFactoryCatalogCompleteness` + 真 .lalb 双 seed 幂等 173×2 行）+ prototypes.bin **177,152B = 173×512×fp16 精确** + revision pin 逐字对 + LabelEngine margin≥0.05 `nextUp` 双侧 + top8 裁度 + typed 拒绝五路（LabelEngineTests 12）；`6a756bd` AIAnalysisRegistry + 真 ImportService 链三态 ×3（ask 弹/always 跳/never 仅嵌入）+ LabelingDefaultsTests 13（remember 写回/reset/垃圾值→ask）；真原型 sanity 2.586s 非 skip；全套 **2797/16/0**（03 验收 §一/§AC 总表）。**labelingMode 三态 UI**：`47e46c4` LCR 页自动打标节（03 验收交接注记 → 07 兑现）；命中质量走查（threshold 0.05）= 观察项挂账#2 | ✅ |
| **SC#4** | **M2AI-04 AI 评片——OpenAI/Anthropic 兼容 endpoint、1-5 星+理由（clamp；rating=0 reasons-only）、星级写库、严格度+输出语言** | `2e2a1ff`/`53f7dc1` AIProviderClient 手写 Codable 双协议（URL join golden + vision base64 载荷 + typed 错误族 + **零重试**——429 后 `recorded.count == 1` 显式断言随批钉死 `70d782a`，AIProviderClientTests 22）+ `ccecf68` AIRatingService（clamp 入 [1,5] + rating=0/缺席+reasons 哨兵 + 无理由 typed malformed + rubric 五档×双语 + `promptProfileID` = StableHash FNV-1a decimal，rubric/protocol/model 变更敏感）+ `67ae496` applyStars **确认门唯一写面**（`images.rating` 写点全仓 grep 单处 + present 不落列三层负测 + 批 200 硬顶 + `library.ai.ratingConfirm` 不再询问；AIRatingDescriptionTests 15 + FulltextSearchTests 13）；全套 **2863/16/0**（04 验收 §一/§机检 4-9）。**UI 半边**：`9daf709` ACA 页严格度 1-5/输出语言三选/不再询问开关 + `9586c1b` Inspector「AI 评片…」顺序扫描 → OQ-11-A 确认门 sheet（逐行/全部/放弃）（07 SUMMARY §交付面 2-3） | ✅ |
| **SC#5** | **M2AI-05 AI 描述——caption+tags+scene+confidence + 全文检索文档（描述/标签进全局搜索）** | `ccecf68` AIDescriptionService 契约四字段（caption 必填/tags 默认/confidence clamp 0...1）→ `ai_understanding` reconcile（**L059 FTS 双文档缺陷修复**：显式 DELETE+INSERT 同事务——OR REPLACE 约束删除不触发 AFTER DELETE 触发器根因；回归揭穿面 `assertMatch("beach", 0)` 亲读）+ rendition_kind edited/original；**E5 契约双钉**：demote 行 raw MATCH 计数 >0 证索引在 + JOIN active=1 检索空集证陈旧行不命中（04 验收 §机检 8）；`67ae496` fulltext tab 真腿（CLIP/EXIF 分支零触碰 + 空态诚实 mode 分叉 + 族互斥，FulltextSearchTests 13）。**触发 UI**：`9586c1b` Inspector「AI 描述」直写零确认（KD-3 派生数据语义，D8）+ FTS 可检索零改（07 SUMMARY §交付面 3） | ✅ |
| **SC#6** | **M2AI-06 凭据与安全——Keychain 存 key（zeroize）+ 强制 HTTPS（localhost 例外）+ prompt profile 护栏** | AICredentialStore kSecClassGenericPassword 零状态面（**真宿主 keychain 激活态 7/0/0 非 skip**——`keychain unavailable` 零命中亲点）+ **zeroize 字节级契约**（`testReadoutZeroizeScrubOnlyTheCallerCopy`：全 range resetBytes + allSatisfy == 0 + 清后重读完整）；AIEndpointPolicy https 强制 + loopback 三 host（双 IPv6 拼写折叠）例外**无开关**（grep 无 settings/env 开关面亲跑）+ 配置/传输双道门（`testInsecureBaseURLRefusedBeforeAnyWireTraffic` 钉 `recorded.isEmpty` 零流量）；key 三面零泄漏（`testKeyRidesOnlyTheAuthHeaderAndNeverTheBodyOrErrors` header 恰 1 + body 净 + 错误文案净）；AIEndpointPolicyTests 9（敌意格 `localhost.attacker.dev`/`ws://`/scheme-less 全拒）（04 验收 §机检 4-6/§AC 总表 1-2）。**ACA 页面**：`9daf709` key SecureField→Keychain save/delete + 「未配置」横幅 + **key 零 defaults 负测**（整 suite dump 无 key 子串）+ baseURL 变更即过 AIEndpointPolicy 拒绝 = 行内红字零存储（07 SUMMARY §交付面 2） | ✅ |
| **SC#7** | **M2AI-07 后台执行——任务注册表+取消，分析期间可继续工作** | AIAnalysisRegistry 三任务型（embedding/labeling/recomputeAll）conformer 挂既有 BackgroundTaskRegistry 聚合面（**BackgroundTaskHosting 协议零 diff 亲证**）；取消 = per-task NSLock token + 每张检查点 + 增量终态（已完成行保留）+ **exactly-once fire**（drain 双 fire 回归测试揭穿——`testCancelMidTaskKeepsCompletedRowsOnly` 断言 `finishedIDs == [id]`，旧双 fire 实现下必得 `[id,id]`）；串行 utility QoS 单飞（mock `maxInFlight==1` + FIFO `[1,2,3,4,5]`）+ 每张 Task.yield + 解码/IO 离主线程；四缺席路径 typed + lastFailureCopy 禁假开关；recomputeAll = 单批翻 active + 旧 key 行保留（取消保 partial，测试双钉）；AnalysisRegistryTests 13/0/0；全套 **2797/16/0**（03 验收 §机检 4-5/§AC 总表 3/6） | ✅ |
| **SC#8** | **M2AI-08 MCP server 保留互补（Phase 14 资产；launcher 与外部 client 双入口照旧）** | **按字面零新增核验**（`M2-10-07-DECISIONS.md` §D14 + 本签核批复现）：`git diff --name-only c573087..9586c1b -- App/Sources/Lightamer/MCP/ LightamerCore/Sources/MCP/` = **零命中**（Export/Version 红线域同检零命中——本签核亲跑 EXIT=0 空输出）；MCP 既有测试全绿（AIProviderClientTests 同轮 Library 22/0/0；MCP 族测试 App bundle `--all` 亲点）；**`semantic_search` 工具 defer 签认** = OQ-12-A 用户裁决（2026-10-02）采纳推荐 A——语义工具等外部需求立项（工具 schema/文档/安全走查都是新增验收面） | ✅（defer 签认记录 = §D14，晨审可推翻） |
| **SC#9** | **M2AI-09 AI 出片入工作流——超分/降噪增强独立预览对话框，结果作为新可编辑副本插入项目，原图零触碰（Lumen RAW editable-copy UX）** | `dba72ce` sidecar v8 additive `aiProvenance` 六字段 snake_case 冻结（v7 三字节形 pin + tamper hash 隔离负测，SidecarV8Tests 5）+ TileInference 纯面（exact-shape 网格末 tile 对齐轴尾/线性 ramp 归一和一/400MP 输出域 typed/15+78 进度曲线，TileInferenceTests 13）；`b4d13d6` EnhanceCopyWriter（POSIX O_EXCL 命名递增/16-bit 容器规则/EXIF 继承+orientation 烘焙+GPS 保留/失败清占位）+ `ImportService.importFile` 单文件孪生（**原图字节级零触碰断言**真链 round-trip，EnhanceCopyTests 8）；`7786ff8` EnhanceEngine（blend 行距 = tile 实宽——多 tile exact-tile identity 绿掩蔽缺陷揭穿修复 + 取消 checkpoint + tmp 清扫）+ EnhanceDialog（192² 预览/下载四态/close-after 取消）；**真模型金样激活态**：64²→256² 经真 worker 子进程两轮 ≤1/255，3.352s 非 skip；全套 **2926/16/0**（06 验收 §一/§重点抽查）。**M-1 内存口径**：`c573087` 两阶段 engine + typed `memoryBudgetExceeded` 门前置闭环（12MP@×2 实测 −38%，+3 回归 = 基线 2929）。**双入口**：`9586c1b` 图库右键两命令 + Image 菜单两命令 → 顺序单张批量 v1（07 SUMMARY §交付面 3） | ✅（16-bit 容器规则收窄晨审可推翻——裁决项#5；100MP 行带流式 E3 挂账#3） |
| **SC#10** | **M2AI-10 AI 推理进程隔离 crash-safe——独立 worker 进程：推理崩溃编辑器不死、任务可重试/降级、记住失败设备组合** | `f1cc3a3` `--ai-worker` 同 binary 子进程（OQ-5-A，**无 InProcess 兜底**——全仓 `InProcessMLModelRunner(` 生产构造仅剩 worker 会话一处亲证）+ UInt32 BE 长度前缀 JSON 帧协议（8MB 构造期分界 + 坏帧容忍，AIWorkerProtocolTests 10）；`3afc5d4` CompatRecord（per 机型+OS build per 模型 per units 记账/两模型同 units 崩全禁/CPU 崩恒不记/坏 JSON 容忍，CompatRecordTests 8）；`65da2d1` AIWorkerClient 降级链 `.all→.cpuAndGPU→.cpuOnly` 增量剔除（MAX_RETRIES=4/超时 SIGKILL 收尸/管道断裂折叠 typed）→ `.workerExhausted/.workerUnavailable` 诚实呈现（AIWorkerClientTests 9）；**crash 链 E1 三重亲证**：全套 crash 三测试 + 验收独立 python 探针（坏 JSON 帧→error 帧同 pid 存活/stop→exit 0/钩子 **HOOK-EXIT: 9**）+ 真模型探针 2.409s 非 skip；装配单点换 AIWorkerClient，02/03 消费面零 diff（AnalysisRegistryTests 13/0/0 + SemanticSearchTests 10/0/0 零涟漪）；全套 **2890/16/0**（05 验收 §一/§机检亲证）。**resetAll 按钮**：`47e46c4` LCR 页诊断节（文件删除终态测试钉）（07 SUMMARY §交付面 1） | ✅ |

---

## 晨审裁决项汇总（执行/验收批已判，用户晨审可逐条推翻）

| # | 项 | 内容与执行/验收判定 | 推翻路径（如晨审不认） |
|---|---|---|---|
| 1 | **07 续班事实链**（`M2-10-07-DECISIONS.md` §D16） | 前任执行 worker 2026-10-04 04:08 写完收口三稿后死亡——T4 提交未落库、`--all` 补跑第三跑未及记录。续班 worker（2026-10-07）在制品甄别收留三件（04 波 O-2 断言 `70d782a` / REQUIREMENTS 翻账 7 行 / LESSONS L066-067）+ 两张 `09-3-tiers-*.jpg` 判与本 plan 无关勿动 + 全套终轮重跑单轮干净绿 + T4 `5c2ad27` 落库。逐 diff 读毕甄别、机检复核全过 | 晨审不认收留判定 → revert `70d782a`/`5c2ad27`（注意 70d782a 是 04 验收 O-2 挂账的钦定消费面，revert 则该挂账重开） |
| 2 | **de68703 并行滑差归属** | 续班期间并行 orchestrator 批 `de68703`（Alcedo 上游 V2 裁决）将工作树中前任 M2AI 翻账 7 行一并扫入——本签核批 `git show de68703` 亲验：hunk 与本 plan 申报内容逐行一致（M2AI-01/08 [ ]→[x] + 03/04/05 注记扩写），零篡改，body 自注 provenance。最终归属：REQUIREMENTS 翻账 = `de68703`；LESSONS/GOAL-STATE/三收口件 = `5c2ad27`；O-2 断言 = `70d782a` | 翻账内容可独立复核（SC 表逐条证据）；如晨审判归属需改写 → doc-only 重排，无代码影响 |
| 3 | **c573087 内存修复批前置** | 06 验收 M-1 minor（fp32 释放 pin inert + 终段双缓冲 ≈28B/像素，400M 输出 ≈11.2GB 越 8G）在 07 双入口接线前前置闭环——两阶段 engine（输出 tile 写后释放 rgba 面）+ typed `memoryBudgetExceeded` 门 + 诚实文案 + 12MP@×2 实测 −38% + 3 回归测试；六 bundle 零漂移 | 晨审判修法不认 → 另立 plan 重设计（两阶段序列化为「推理→落盘→blend」面，回退则 100MP@×2 工况回贴 8G 门） |
| 4 | **SidecarV5 ANE flake 五波台账收口** | 五波两红三绿终态（01 执行 / 06 验收 / 07 首轮红；07 补跑 / 07 续班终轮绿 13.338s）——宿主 ANE 编译态劣化窗口归因维持（`ANECCompile() FAILED` 宿主日志 + 隔离复绿 + 域零接触机检 + ~68h 重启复绿）；**不改判定、不修码**，Phase 15 flaky 清算批立案输入更新 | 晨审判环境归因不成立 → Phase 15 清算批提级先行（硬化方向：超时阈值/重试协议/宿主态自检） |
| 5 | **16-bit 容器规则收窄**（06 DECISIONS §1） | 「副本格式随原格式」D-3 有意收窄为：16-bit PNG 同格式、其余一律 TIFF 16——晨审可推翻（原话在案） | 晨审判「随原格式」字面执行 → EnhanceCopyWriter 容器矩阵扩腿（纯 App 面小修） |
| 6 | **描述无确认门 + rendition_kind 分叉**（D8） | KD-3 明文（`ai_understanding` = 派生数据非用户手评语义）：描述扫描直写零确认；rendition_kind 按行 `has_edits` 分叉 edited/original（04 波编辑器语境默认 edited 的显式偏离，图库语境按行状态） | 晨审判描述也走确认门 → App 层加门（服务面契约不动） |
| 7 | **增强副本 albumID = nil**（D6） | D-3「落当前相册（可选）」的可选半边 v1 不实现——副本入项目网格不入相册（相册选择态未进 coordinator 面），挂观察项 | 晨审判必须落相册 → coordinator 加相册 picker（App 面增量） |
| 8 | **批量 = 顺序单张循环 v1**（D5，KD-3 明文） | 一图一对话框 done 自动推进非末张/用户关闭放弃余量/空集拒绝；真批量队列（并发/断点）= 需求出现再立项（挂账#2 内） | 晨审判需并发队列 → 另立 plan（worker 通道已支持并发面） |
| 9 | **Image 菜单落 LightamerApp**（D3 申报增量） | SwiftUI 菜单栏命令只能声明在 Scene commands 块——`CommandMenu("Image")` 唯一落点 = LightamerApp（front-matter 漏列 = 起草缺口，additive 五件 D3 表全追认；`EditorWorkspaceShellView` 零触碰） | 晨审不认申报形态 → revert 对应 hunk 后 Image 菜单不可达（功能回退，非缺陷） |

---

## Per-Plan Map（M2-10-01..07 + 验收批）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M2-10-01 模型资产管线 | 五档位 Catalog + digest fail-closed + ModelAssetStore（三源/流式 SHA-256/原子晋升）+ 转换脚本族 + SPIKE + bundled 打包 | `2d897ad`/`6a7e81e`/`318a473`/`ec7d9dc` + `6f768c0`（验收批 M-1 fix）/`b7b918d`（验收报告） | PASS / 0E + 1m 已修 + 1o（2718/16/0；`M2-10-01-ACCEPTANCE.md`） |
| M2-10-02 嵌入存储与检索 | LibrarySchema v4 七表 + WordPiece + SemanticStore + vDSP Scanner + SemanticEngine + CLIP tab 真腿 | `882f97a`/`2aa4179`/`4ddb71a`/`a181890`/`ed1880d` + `ede45f8`（验收批 M-1 fix）/`321383b`（验收报告） | PASS / 0E + 1m 已修 + 2o（2759/16/0；越界四件追认；`M2-10-02-ACCEPTANCE.md`） |
| M2-10-03 打标与后台任务 | LabelQueries 173×zh/en + LabelEngine + AIAnalysisRegistry + 导入接线三态 | `f15bb96`/`6a756bd`/`4c07dc6` + `a986089`（验收报告） | PASS / 0E + 0m + 3o（2797/16/0；越界三件追认；`M2-10-03-ACCEPTANCE.md`） |
| M2-10-04 远程评片/描述/凭据 | AIProviderClient 双协议 + CredentialStore/EndpointPolicy + Rating/Description 服务 + 确认门 + fulltext tab | `2e2a1ff`/`53f7dc1`/`ccecf68`/`67ae496`/`9114c48` + `81ae393`（验收报告） | PASS / 0E + 0m + 2o（2863/16/0；越界两件追认；`M2-10-04-ACCEPTANCE.md`） |
| M2-10-05 worker 进程隔离 | `--ai-worker` 帧协议 + CompatRecord + AIWorkerClient 降级链 + 装配单点切换 | `f1cc3a3`/`3afc5d4`/`65da2d1`/`1491f8f` + `54e5e39`（验收报告） | PASS / 0E + 0m + 3o（2890/16/0；E1 python 探针三重亲证；`M2-10-05-ACCEPTANCE.md`） |
| M2-10-06 AI 出片可编辑副本 | sidecar v8 + TileInference/EnhanceEngine + EnhanceCopyWriter + import 孪生 + EnhanceDialog | `dba72ce`/`b4d13d6`/`7786ff8`/`5183343` + `b766cf5`（验收批 cosmetic fix）+ `c573087`（M-1 内存修复批）+ `bbb22d1`（验收报告） | PASS / 0E + 1m（`c573087` 闭环）+ 3o（2926/16/0；越界四件追认；`M2-10-06-ACCEPTANCE.md`） |
| M2-10-07 UI 收口 + zh + 翻账 | LCR/ACA 设置页 + 双入口 + Inspector AI 区 + zh 全量 126 键 + M2AI-08 核验 + 翻账 | `9daf709`/`47e46c4`/`9586c1b` + `70d782a`（O-2 断言）+ `5c2ad27`（T4 收口；并行 `de68703` 载翻账——裁决项#2） | 执行批闭环（续班终轮 2955/16/0 亲证）；**07 无单独验收轮——本 VALIDATION 即其验收面**（七 plan 唯一执行闭环待验收项，输入 = `M2-10-VALIDATION-INPUT.md`） |

零红线域终态：本签核亲跑 `git diff --name-only c573087..9586c1b -- MCP/Export/Version 三域` = **零命中**（07 全批；Export 红线门测试 338/1/0 七轮零漂移）。GPL/MIT 参考全程只读（Alcedo/darktable/Lumen 零代码复制——RAWmakase 登记为 MIT reference 后经 `64a120b` 撤销，零借鉴采纳）；`.xmp` 零读写删。

---

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。M2AI-01..10 每条均有 ≥1 机器锚（本 phase
  新增测试 **+378 法** = 七 plan +375 + `c573087` +3——BUNDLE-MAP 逐行登记且
  经验收 `grep -c "func test"` 逐值对表）+ ≥1 数字/实证背书（全套七轮独立
  验收复跑 2718→2955 逐波精确对账 + 真模型激活态多波非 skip 亲点 + crash 链
  独立 python 探针）。
- 覆盖密度与前序已签核 phase（M2-9-VALIDATION 同款）对齐：数学面 golden
  （tokenizer 12 句逐位 / LabelEngine margin nextUp 双侧 / TileInference ramp
  归一和一 / digest 三方互验）、语义面真链（真 ImportService 三态 / 真
  keychain 激活态 / 真 worker 子进程金样 ≤1/255）、安全面敌意输入（端点准入
  矩阵敌意格 / key 三面零泄漏 / zeroize 字节级）、行为面正反双向（fail-closed
  typed 拒绝族 / exactly-once fire 揭穿面 / E5 双钉）、性能面哨兵测试（200k
  ≤50ms 硬门 + 「禁静默调宽」文案在断言里）。
- 采样率对变更面不成欠账：七 plan 全部 AC 逐条机检（8+10+8+9+9+8+9 = **61
  条**）+ 六验收 subagent 零共享上下文独立复跑；每轮全套对账基线精确（逐波
  +25/+41/+38/+66/+27/+36/+3/+26 全对上）；无「无证据 ✅」项。
- 07 波无独立验收轮的补偿：续班机检复核五项（红线零 diff/zh-audit/BUNDLE-MAP
  逐位/枚举零 diff/marker 七枚）+ 本 VALIDATION 签核批三项亲跑复现（红线域
  git diff 零命中 / `zh-audit --check` PASS / 测试文件计数 10/10/6 逐位）+
  SC 表 1-10 证据指针全部落到前六波已验收资产或终轮亲证数字——采样覆盖不因
  验收轮合并而降级。

---

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（C 档第 3 停夜间
  授权先例，M2-8/M2-9-VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（用户两条显式指令，夜间全自动批在案沿用）**：
  1. 「今晚任务不要停下，自动化持续推进」（今晚不停）
  2. 「开跑，不要停」
- 依上述授权，本 VALIDATION 由夜间全自动批落盘签核（`[gsd] paused=false /
  auto=true` 全程未动——七 plan 执行/验收逐任务边界复查在案）；用户晨审可推翻
  本签核（推翻 = M2-10 签核作废回退，已交付面与七轮执行/验收证据不受影响）。
- 签核 executor：ZCode VALIDATION executor（2026-10-07 夜间批）；doc-only——
  全套 `--all` 未在本批重跑，SC 数字用 07 续班终轮亲证值（`TOTAL|2955/16/0|
  1019s`），机检三项（红线 diff/zh-audit/测试计数）本批亲跑复现。

---

## 特殊事项入册（phase 级事件台账）

1. **07 续班与重启事故**：执行 worker 2026-10-04 04:08 死亡（收口三稿落盘、
   T4 未提交）；续班 worker 2026-10-07 收尾（在制品甄别 + 终轮 `--all` 重跑 +
   T4 落库）——commit-per-task 纪律使三功能提交零损失，损失面 = 收口批时序
   （~68h 滞后）。SidecarV5 ANE flake 持续窗口恰跨该死亡事件，终轮复绿与
   ~68h 宿主间隔重合（环境型归因的旁证，非因果断言）。
2. **内存修复批 `c573087`**：06 验收 M-1（双缓冲峰值 ≈28B/输出像素）前置闭环
   于 07 接线前——两阶段 engine + typed 门 + 文案；基线 2929 含 +3 回归。
   100MP 级行带流式（E3）仍为正解，挂 Maintenance（挂账#3）。
3. **de68703 滑差对账**：并行 orchestrator 批扫入前任 M2AI 翻账 7 行——hunk
   逐行一致零篡改（本签核 `git show` 亲验），body 自注 provenance 点名续班
   agent 对账；最终归属三件清（裁决项#2）。
4. **SidecarV5 flake 五波台账收口**：两红三绿终态，环境型归因维持；Phase 15
   flaky 清算批立案输入（GOAL-STATE 阻塞节同步登记）——本 phase 无硬化动作
   （域零接触红线维持）。
5. **MCP 零 diff 红线核验**：`c573087..9586c1b` 三域（MCP/Export/Version）
   零命中——执行批 D14 机检 + 续班复核 + 本签核批三度亲跑复现；M2AI-08
   「零新增」字面核验成立，`semantic_search` defer 签认（OQ-12-A）。

---

## 挂账清单（Deferred + 观察项，交接 M2-11 与 Phase 15）

**正本 = `M2-10-VALIDATION-INPUT.md` 十项**（全部观察项，无交付缺口），索引：

1. **Release 上架维护者清单**（01 DECISIONS §6）：jina-clip-v2 int8 /
   real-esrgan-x4plus fp16 / drunet-color fp16 三资产 digest 回填 + GitHub
   Release `ai-models-v1` 上传——上架后 LCR 页/对话框下载行零 UI 改动解锁。
2. **命中质量走查**（03 挂账）：threshold 0.05 / 单句原型上限的实图观感——
   headless 盲区，随 M2-11 GUI 验收轮（Alcedo 对照方法学）。
3. **100MP 级增强内存行带流式（E3）**：`c573087` 两阶段 engine 已闭环 12MP
   档；>6 GiB 工况 typed 拒绝诚实文案在位；行带流式为正解，挂 Maintenance。
4. **Library 缩略图队列 flake 硬化**（05 验收 O-1）：竞争断言硬化建议，
   Phase 15 flaky 清算批（与 SidecarV5 ANE flake / LayerE2E RoundTrip 三案
   并案）。
5. **设置页/对话框视觉走查**（07 plan 风险节）：headless marker/AX 机检为门，
   Alcedo 对照截图走查随 M2-11。
6. **SettingsDeepLink 已开窗口限制**（D11）：pendingPage 滞留至下次开启消费——
   v1 已知。
7. **真批量增强队列**（并发/断点续跑）：需求出现再立项。
8. **「衍生自」徽标 UI**（06 交接④）：join 键定案 `source_image_id` = 行 id
   十进制（D7）；网格徽标后手。
9. **性能实测表**：嵌入扫描 200k×512 median 32.05ms + tile 20.55ms + IPC
   spike（ping 0.025ms / 50MP TIFF 15.5-19.4ms）在案——60fps@100MP 终验归
   M2PERF-01（M2-11）。
10. **worker 编译缓存冷启动**（~400s 首轮）：真机首启观感走查项。

**zh-audit 提取器缺口**（`search_fulltext_placeholder` continuation 形态漏提，
D13 补录消化）：硬化建议随 Phase 15 清算批——非本 phase 门（PASS 主体达成）。

**V2 面（既有挂账延续）**：无新增。

---

## 翻账与移交

- REQUIREMENTS **M2AI-01..10 全 Delivered 终态复核通过**（翻勾正本 = `de68703`
  承载 + 注记义务逐条在案：01 五档位/混合获取/设置 UI 双半边 + 02 vDSP 基线
  + ANN 后手条件 + 03 labelingMode UI + 04/05 UI 半边 + 06 双道门 + 07 exactly-once
  + 08 defer 签认 + 09 容器收窄注记 + 10 CompatRecord/resetAll）——本批零改动
  （前批翻账已终态，本签核逐条复核 SC 表）。
- STATE.md：M2-10 翻 complete（2955/16/0）+ M2-11 标 next（本批）。
- ROADMAP §M2-10 行状态同步 ✅（本批）。
- GOAL-STATE 续接点增量：M2-10 closed → **M2-11（性能专项 + closeout）= M2
  最后 phase**——交接面 = `M2-10-07-SUMMARY.md` §M2-11 交接节四件（60fps@100MP
  复验 / MCP 面零改动 + semantic_search defer / AI 面 GUI 走查随验收轮 /
  flaky 清算三案）。
- TODO.md 同批（本批）。
- 未 push；GPL/MIT 参考零接触；`.xmp` 零读写删；GUI app / 测试宿主进程零残留
  （本批 doc-only 零构建零测试运行）。

## 签核

- M2AI-01..10 全项 ✅（三列证据齐；SC 数字对账 = 07 续班终轮 2955/16/0 亲证
  基线，演进链 2693→…→2955 逐波独立验收背书）。
- `status: validated` + `nyquist_compliant: true`。
- 零 error 级 FINDING（01..06 六轮验收全 PASS / 0 error；minor 三件——01
  `6f768c0` / 02 `ede45f8` / 06 `b766cf5`——均验收批闭环，06 内存 M-1 由
  `c573087` 闭环）；07 执行批 ANE flake 环境型记账收口（五波台账）。
- 晨审裁决项九条入册（§晨审裁决项汇总），逐条带推翻路径。
- 挂账十项（全观察项）+ zh-audit 提取器硬化随 M2-11 / Phase 15 交接。
- **C 档第 3 停 = 夜间授权先例（D-07-3-T5-1 + 用户「今晚不停」「开跑，不要停」
  两条原话）落签，晨审可推翻。**
