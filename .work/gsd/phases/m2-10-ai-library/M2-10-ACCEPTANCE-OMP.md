# M2-10「AI 图库」回溯二次验收（omp 独立二次验收）

> 验收员：omp（零共享上下文回溯验收，不轻信首验结论，证据亲测）。
> 对象：M2-10 phase 粒度，7 plans（M2-10-01..07）。
> 正本：`.work/gsd/phases/m2-10-ai-library/` 下 M2-10-01..06-ACCEPTANCE（全读）、M2-10-07-SUMMARY（全读）、M2-10-VALIDATION（全读）、M2-10-VALIDATION-INPUT（全读）；DECISIONS/SUMMARY 抽读对表。
> 验收日期：2026-10-09。HEAD：`bade569`（M2-10 历史已压缩归档，见抽查点 6）。

## 结论头

**PASS / 0 error + 1 minor**

- 7 plans 逐项 PASS；抽查点 6 项全做 + 自加 2 项（InProcess 构造残留面、key 泄漏开关面）。
- 定向测试 4 类全绿：AIWorkerProtocolTests 10/0/0、AIWorkerClientTests 9/0/0、WordPieceTokenizerTests 9/0/0、SemanticSearchTests 10/0/0。
- minor M-1：AGENTS UserDefaults 键登记缺 `library.ai.*` 五键（文档缺口，零行为面）。
- 实质分歧：零（无测试红、无凭证明文落盘、无隔离面缺失）。

## 逐 plan 判定

### M2-10-01 模型资产管线 — PASS

- 首验结论（2718/16/0、digest 三方互验、E4=224² 双证）读毕；本轮未重跑其专属测试（超出 1-2 类定向额度，抽查点 4 指定 worker/语义族），但其交付物（Catalog/Store/转换脚本）为后续三波真模型激活态的前置依赖——本轮 SemanticSearchTests 10/0/0 零 skip 即其资产链在场存活旁证。
- 源码抽核：`LightamerCore/Sources/AI/ModelAssetCatalog.swift:173-184` drunet KAIR MIT 注记在位；体积红线沿用（`Resources/AIModels/` 零跟踪字节由首验亲跑，本轮未复跑 git 机检——属首验已钉死项，非本轮抽查点）。

### M2-10-02 嵌入存储与检索 — PASS

- 定向复跑：WordPieceTokenizerTests 9/0/0（peakRSS 193MB）、SemanticSearchTests 10/0/0（peakRSS 199MB，skip=0——M5 真模型 sanity 在本机仍激活态跑绿，非 skip）。
- 方法计数：`grep -c 'func test'` = 9/10，与 BUNDLE-MAP 行值（LIB 9/10）逐位一致。
- E5 契约消费面（04 波 `AIDescriptionService.imageIDs` JOIN active=1）源码在位，02 波 `replaceUnderstanding` DELETE+INSERT 同事务修复未被后继改动（后继 phase 零触碰语义四域，M2-11 机检红线延续）。

### M2-10-03 打标与后台任务 — PASS

- 首验结论（2797/16/0、exactly-once 回归、真原型 2.586s）读毕；本轮定向额度内未重跑其类，证据链经源码抽核成立：`LabelingPreferences.modeKey = "library.ai.labelingMode"`（`App/Sources/Lightamer/Library/LibraryPreferences.swift:63`）仍为 LCR 页唯一消费键（`LCRSettingsModel.swift:133,156`）；`AIAnalysisRegistry` 三任务型 + 取消增量终态为 07 波换激活入队断言的前置（07-SUMMARY §交付面 1）。
- 越界三件追认逻辑（03-ACCEPTANCE §越界三件判定）逐条读毕，无授权缺口。

### M2-10-04 远程评片/描述/凭据 — PASS

- 凭证面（抽查点 3）：`AICredentialStore.swift:30-40` 零状态 enum + 错误族仅载 OSStatus（`unhandledStatus(OSStatus)`/`unavailable(OSStatus)`，无 key 载荷）；`save/read/delete`（:55-121）纯 SecItem 面，service = bundle id（:44）、account = `rating-provider`（:49）。源码零日志面（全文件无 print/log 调用）。
- EndpointPolicy：`AIEndpointPolicy.swift:38-51` https 直放 + http 仅三 loopback（双 IPv6 拼写折叠 :61-67）；全仓 grep `allowHTTP|allowInsecure|httpEnabled|insecureAllow` 零命中——「无暗开关」成立；双道门消费点 = store 侧 `LibraryConnectionStore.swift:114-115` + 传输侧 `AIProviderClient.swift:140-142`。
- 确认门唯一写面：`AIRatingService.applyStars`（`AIRatingService.swift:227-236`，`UPDATE images SET rating` + 1...5 guard）为 M2-10 时代唯一写面。HEAD 另有一处 `SessionIndexStore.swift:1190 claimMetadataApplySQL` 含 rating 列——经 `git log -S` 溯源为 Phase 12（`b9c9f3b`/`93f25d4` 系）后加元数据认领面，非 M2-10 回归；首验当时「全仓单处」成立。记观察项 O-3，不判分歧。
- O-2 挂账（429 单请求断言）已由 `6fb7546`（`70d782a` 存续等价）消费，见 07-SUMMARY AC#7。

### M2-10-05 worker 进程隔离 — PASS

- 定向复跑：AIWorkerProtocolTests 10/0/0（4s）、AIWorkerClientTests 9/0/0（含真子进程 crash 注入/exit(9)/超时 kill/外杀折叠全族，peakRSS 2831MB 系真 CoreML 会话常态）。
- 进程边界亲核（对照 05-ACCEPTANCE 申报 ≥3 处）：
  1. 分叉臂：`LightamerApp.swift:85-92`（`AIWorkerMain.runIfRequested()` 位于 `--mcp` 臂后、`LightamerApp.main()` 前，worker 臂永不构造 SwiftUI App）——与首验「8 行纯插入」一致（HEAD 因 Phase 14 MCP 臂演进，行号后移但臂序不变）。
  2. crash 钩子双门：`AIWorkerMain.swift:78-95`（`#if DEBUG` 圈声明 + `crashHookShouldFire` `@units` 扩展形）+ `:245-246` open 前 `Darwin.exit(9)`；SIGTERM→exit 0（:67）、stop 清双 session 表（:193-197）。
  3. 降级链：`AIWorkerClient.swift:91-92` attemptOrder、`:307-368` withFallbackChain（预剔除 `:310-312` + 增量 `removeAll` `:349/:355`，无重算路径）、culprit 归因 `lastOpenedUnits`（:376）、SIGPIPE 忽略（:482）、SIGKILL+`waitUntilExit` 收尸（:534-544）、foldDeath exit 码附着（:559-572）。
  4. L063 对策：`AIWorkerProtocol.swift:320-324` 逐字节 `UInt32(byte)` 宽化再移位 + 注释；8MB 构造期拒（:238 `:246-249`）。
  5. CompatRecord：CPU 恒不记（:126 guard）、两模型同 units 全禁（:134 `count>=2`）、detail 截断 300（:137）、同目录 tmp 原子晋升（:169-176）。
- 无头纪律：worker 五文件 grep `Sidecar|import SwiftUI|import AppKit` 零命中（亲跑）。
- InProcess 兜底不存在：全仓 `InProcessMLModelRunner(` 生产构造仅 `AIWorkerMain.swift:277` 一处（worker 会话对象）；`AIInferenceService.swift:75-79` 换刀注释在位。OQ-5-A 成立。
- Lumen MIT 归属：`AIWorkerClient.swift:7-9`「Lumen Worker/RemoteSession paradigm, MIT read-only (structure ported, never code)」+ 行级 parity 注记（:26/:36/:59/:64/:107/:433/:518/:560）；`AIWorkerMain.swift:27-28`（`LUMEN_TEST_WORKER_CRASH` paradigm）、:63（SIGTERM parity）；`CompatRecord.swift:6-7`（`gpu-compat.json` paradigm, MIT read-only）；`EnhanceCopyWriter.swift:9-11`、`TileInference.swift` Lumen MODEL.md parity 族。结构移植 + 注记齐全，无成段代码复制面（Swift/Process/帧协议实现与 Python 原仓无逐行对应物）。合规。

### M2-10-06 可编辑副本 — PASS

- SidecarV8 additive（抽查点 2）：`LightamerSidecar.swift:482-483` decodeIfPresent + `:552` encodeIfPresent（M2-8 同构惯例）；六字段 snake_case 冻结（:927-931 CodingKeys）；操作枚举冻结二值（:895-900）；hash 隔离——`driftDetected`（:1002-1008）折叠式无 provenance 项，注释 `:188-191` 明示延续 v3/v4/v7 判定。v9 film 面（:484/:553）沿用同惯例，反证 v8 形态为先例。
- 测试法面：`SidecarV8Tests.swift` 5 法（v7 逐字节/nil 位差/provenance round-trip/tamper 负测/枚举冻结）+ `EnhanceCopyTests.swift` 8 法（O_EXCL 并发/命名形/容器矩阵/16-bit/清占位/EXIF-GPS/真链 round-trip/Media 外拒绝）——`grep -c` = 5/8 与 BUNDLE-MAP 逐位一致；`importFile` 孪生缝（`ImportService.swift:612-671`，`aiProvenance` 参数 + Media 内断言）。
- EnhanceCopy 语义：O_EXCL 独占预约（`EnhanceCopyWriter.swift:127`）+ 9999 上限（:123-136）+ 失败清占位；EXIF 继承/orientation 烘焙/GPS 保留（头注 :31-35）。副本独立 sidecar（pristine `.lra` + provenance）/原片字节零触碰由真链测试钉死（首验亲读，本轮读码复核测试名与缝在位）。
- M-1 内存修复批 `fd43ceb`（`c573087` 存续等价）在位：`PixelBufferContext` 零拷贝 encode 缓冲（:49-66 头注点名 M-1）。

### M2-10-07 设置页与入口收口 — PASS（VALIDATION 即验收面，无独立验收轮）

- ACASettings/LCRSettings 键族消费：ACA 经 `LibraryConnectionStore`（`connection/strictness/outputLanguage` 三键，`LibraryConnectionStore.swift:57-59`）+ `RatingConfirmPreferences`（`AIRatingController.swift:35`）+ Keychain key 面（`ACASettingsModel.swift:33-34,166-184` save/delete + 未配置横幅）；LCR 经 `LabelingPreferences`（`LCRSettingsModel.swift:133,156`）+ `CompatRecord.resetAll`。键常量单源拼写，注入式 suite，无 body 直读。
- zh：07-SUMMARY 申报 `zh-audit --check` PASS（1505/1753）在 DECISIONS §D13 + SUMMARY §交付面 6 + 续班注记三处互证；M2-11 未推翻（V15 仅立案提取器硬化，主体 PASS 延续）；本轮 HEAD 实跑复现 PASS（1584/1822，增长来自 M3 film 等后继键，方向一致）。
- 双入口/marker 冻结集：AIEntryPointsTests 6 法在册；图库右键腿 Manual-Only 通道注记经 M2-11 义①复核维持（见抽查点 5）。

## 逐抽查点证据

1. **worker 进程隔离读码**：见 M2-10-05 节。亲核 file:line 12 处（分叉臂/钩子/链/收尸/协议/记账各 ≥2）。Lumen MIT 注记三文件头注齐全，结构移植无代码复制。结论：隔离面完整，崩溃恢复路径（crash→记账→respawn→降级→exhausted/unavailable 诚实面）与首验申报一致。
2. **SidecarV8 + EnhanceCopy 读码**：见 M2-10-06 节。decodeIfPresent/encodeIfPresent 双缝 + hash 隔离 + 冻结枚举 + O_EXCL/真链测试法名亲核。结论：v7 零漂移门结构成立（nil 面 key 缺席 + fold 公式零 diff），副本语义成立。
3. **凭证面 + 键族对表**：见 M2-10-04/07 节。keychain 零状态面 + 错误零载荷 + https 双道门 + 无暗开关（grep 零命中）亲证；key 零入 defaults 由 `StoredConnection` 四字段（protocolRaw/baseURL/model/timeout，无 key 槽，`LibraryConnectionStore.swift:66-71`）结构保证 + 07 波 dump 负测钉死。键族对表：代码五键（`library.ai.connection/strictness/outputLanguage/ratingConfirm/labelingMode`）vs AGENTS 登记零收录 → **minor M-1**（文档缺口：AGENTS.md:299 UserDefaults 键登记行未追加 M2-10 键族；行为面零影响——单源常量 + 注入式 suite 纪律本身完好）。
4. **定向测试**：App `AIWorkerProtocolTests` 10/0/0 + `AIWorkerClientTests` 9/0/0；Library `WordPieceTokenizerTests` 9/0/0 + `SemanticSearchTests` 10/0/0。合计 38/0/0，零 skip、零 flake（SidecarV5 ANE 家族未触发，无需换类）。BUNDLE-MAP 登记（APP 10/9、LIB 9/10）与 `func test` 计数逐位一致。禁全套纪律遵守（未跑 --all）。
5. **VALIDATION 数字对表（抽 3 处）+ GUI 移交**：
   - ① 02 sanity 2.373s：02-ACCEPTANCE:39 ↔ VALIDATION:36（`02 sanity zh/en 2.373s`）逐字一致。
   - ② 05 worker 真链 2.409s：05-ACCEPTANCE:60,215,252（三处内一致）↔ VALIDATION:36（`05 worker 真链 2.409s`）一致。
   - ③ 06 金样 3.352s：06-ACCEPTANCE:19,51,253（三处内一致）↔ VALIDATION:36（`06 金样 64²→256² ≤1/255 3.352s`）一致；另 03 真原型 2.586s（03-ACCEPTANCE:39,161 ↔ VALIDATION:36）附带一致。
   - 观察项 O-2：06-ACCEPTANCE:52 称 `testRealModelEmbedImageThroughWorkerProcess` 2.373s——数字与 02 波另一测试（`testRealModelEndToEndZhAndEnQueries`）逐位相同。两测试不同名而耗时同值至毫秒，疑转录巧合；毫秒级计时不可回溯复算，且任一取值均不改变「激活态非 skip」结论。记观察项，不判分歧。
   - GUI 移交：VALIDATION-INPUT 观察项 5（设置页/对话框视觉走查）→ M2-11-VALIDATION-INPUT §义① live 证据（t7-lcr/aca/enhance 三截图 + Image 菜单编辑器腿 live）+ V5 本轮关闭；V2（命中质量）维持 headless 盲区。移交闭环可考，无悬空。
6. **git 机检**：
   - 首验引用的执行期短 SHA（如 `65da2d1`/`b4d13d6`）在 HEAD 历史中不可解析——M2-10 已按公开仓压缩纪律归档（ squash `e36a589` 90 文件 22917+）。改走存续等价全 SHA 抽查 3 个（超任务要求的 2 个）：
     - `5419cd0`（05-T2 client）：5 文件 = AIWorkerClient 新建 567 + AIInferenceService 62 换刀 + AIWorkerMain +28/-19（spike 路由/L064 双修复）+ Project +1 + ClientTests 397 ——与 05-ACCEPTANCE T2 行逐项一致。
     - `dc92d71`（06-T2 writer）：5 文件 = EnhanceCopyWriter 242 + ImportService +95/-1 + BUNDLE-MAP +1 + Project +1 + EnhanceCopyTests 371 ——与 06-ACCEPTANCE T2 行逐项一致。
     - `927ae20`（06-T1 v8）：6 文件 = TileInference 266 + Sidecar +96 + SidecarV8Tests 233 + TileInferenceTests 256 + Project +2 + BUNDLE-MAP +6 ——与 06-ACCEPTANCE T1 行逐项一致。
   - zh 互证：1505/1753 PASS 在 07-SUMMARY/07-DECISIONS/VALIDATION 三处互证；M2-11-VALIDATION zh 行（本 phase 零新键批 + FINDING-G 新裸键立案）侧证 M2-10 主体 PASS 未被推翻；本轮 HEAD 实跑 `zh-audit --check` PASS（1584/1822，locale {en,zh}）。
   - 记观察项 O-1：回溯验收引用短 SHA 需经 squash 映射，建议后继回溯任务先 `git log --all --oneline --grep` 定位存续等价提交。

## 与首验分歧点

实质分歧：无。账面差异三项观察项（均不触及判定）：

- O-1：执行期短 SHA 压缩后不可解析，改存续等价提交验证通过（见抽查点 6）。
- O-2：2.373s 同值出现在两个不同测试名下，疑转录巧合，结论不受影响（见抽查点 5）。
- O-3：HEAD 新增 `images.rating` 第二写面（Phase 12 元数据认领），M2-10 时代单写面结论当时成立（见 M2-10-04 节）。
- M-1（minor）：AGENTS UserDefaults 键登记缺 `library.ai.*` 五键——文档缺口，建议 Phase 15 文档清算批或下次触 AGENTS 时补行（只读验收纪律，本轮不写）。

## 会话卫生

- 只读验收：除本报告文件外零写入；源码/既有文档零修改；未 push。
- 定向测试仅 4 类（App 2 + Library 2），未跑全套 --all。工作区 `git status` 无本会话新增修改（M3-4 队列文件 M 态 + M2-9 OMP 报告未跟踪件均为他会话产物，未触碰）。
- 过程注记：曾误以 `--help` 参数调用 test-direct.sh（该脚本无 help 面，参数被当类过滤），后台任务启动后立即 kill，经 `ps` 确认无测试宿主残留、无任何测试被实际执行；后改读脚本头注释取用法。另实跑 `zh-audit.py --check` 一次（只读机检）。
- 测试宿主进程：四轮定向跑均为短进程（0-4s），完即退出；结束时无 Lightamer 残留进程。

OMP-VERDICT: PASS
