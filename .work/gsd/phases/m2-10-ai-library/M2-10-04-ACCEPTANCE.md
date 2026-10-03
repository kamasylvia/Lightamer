# M2-10-04 ACCEPTANCE — 评片/描述远程腿 + 凭据安全 + 全文检索真腿

> 验收 subagent（零共享上下文，实测核验不轻信）。验收对象 = 五提交
> `2e2a1ff` / `53f7dc1` / `ccecf68` / `67ae496` / `9114c48`（HEAD `9114c48`，
> 未 push）。正本输入 = PLAN（含 checker 回注 M3/E5/M11）+ SUMMARY +
> DECISIONS（§1..16）。验收日期 2026-10-04。基线 = M2-10-03 验收终态
> 2797/16/0（HEAD `a986089`）。

## 结论

**PASS / 0 error + 0 minor + 2 observation** —— AC 9/9 全过；越界两件
**全部追认采纳（零驳回）**；全套独立复跑**单轮干净绿**
`TOTAL|2863/16/0|930s EXIT=0`（执行批三跑三崩环境事件本轮**零复现**）；
L055 对策机检亲跑：七 bundle `terminated abnormally` 计数**全零** + 各
bundle 末行 Executed 与 BUNDLE 行逐值一致；keychain 激活态真跑非 skip
（AICredentialStoreTests 7/0/0）；M2AI-04 / M2AI-05 / M2AI-06 翻勾。

## 全套独立复跑（对账 2863/16/0）

`caffeinate -dis xcodebuild build-for-testing`（workspace/scheme 标准命令，
HEAD `9114c48`）→ `caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 467/1/0（peak 6566MB） | 467/1/0 | 零漂移 |
| IOPParity | 362/3/0（6000MB） | 362/3/0 | 零漂移 |
| Layers | 298/3/0（1049MB） | 298/3/0 | 零漂移（执行批 run1 崩点本轮未复现） |
| Library | **568/4/0**（921MB） | 568/4/0（+53 全落此） | 零漂移 |
| Sessions | 279/4/0（1648MB） | 279/4/0 | 零漂移 |
| Export | 338/1/0（5379MB） | 338/1/0 | 零漂移（红线门） |
| App | **551/0/0**（1341MB） | 551/0/0（+13 全落此；执行批 run2/run3 崩点本轮未复现） | 零漂移，**一轮过** |
| **TOTAL** | **2863/16/0，930s，EXIT=0** | 2863/16/0（806-1012s 水位） | **精确对账** |

- 对账：2797（03 验收基线）+ **66 精确** = AIEndpointPolicyTests 9 +
  AICredentialStoreTests 7 + AIProviderClientTests 22 +
  AIRatingDescriptionTests 15（全落 Library 515→568）+
  FulltextSearchTests 13（App 538→551）；五新 suite passed 行亲点；
  `grep -c 'func test'` = 9/7/22/15/13 与 BUNDLE-MAP 五行逐位一致。
- skip 16 = 基线**零新增**；`keychain unavailable` 零命中——
  AICredentialStoreTests 真宿主 keychain **激活态 7/0/0 非 skip**
  （`Executed 7 tests` 行亲点）。
- 零 MEMFAIL：peakRSS 最大 IOP 6566MB < 8192 门。
- **L055 对策机检（强制项）亲跑**：`grep -c "terminated abnormally"`
  七日志全 0；`Fatal error|EXC_BAD|Segmentation|crashed` 信号零命中；
  七 bundle 末行 Executed 总计与 BUNDLE 行逐值一致——本轮无假绿形态，
  执行批的三崩（Layers 3/298 abnormal / App ENOENT / App DrtPersistence
  75/551 abnormal）**单轮零复现**，与 L049/L018 家族环境型归因一致
  （执行批已清盘 4.7G + 本轮新容器重建）。

## 逐 commit 边界（纪律 8）

| commit | 文件集 | 判定 |
|---|---|---|
| T1 `2e2a1ff` | AICredentialStore + AIEndpointPolicy + AICredentialStoreTests + AIEndpointPolicyTests + Project.swift | == 申报 |
| T2 `53f7dc1` | AIProviderClient + AIProviderClientTests + Project.swift | == 申报 |
| T3 `ccecf68` | AIRatingService + AIDescriptionService + AIRatingDescriptionTests + Project.swift | == 申报 |
| T4 `67ae496` | AIRatingController + LibrarySearchModel + GlobalSearchDialog + WorkspaceHostView（越界①申报）+ FulltextSearchTests + Project.swift | == 申报 |
| T5 `9114c48` | SUMMARY/DECISIONS/GOAL-STATE/LESSONS + BUNDLE-MAP 五行 + SemanticSearchTests（越界②申报） | == 申报 |

五提交合计 diff = 21 文件 = **front-matter 18 + 越界申报 2 + BUNDLE-MAP
账本 1**，零未申报文件（`git diff --stat a986089..9114c48` 逐行核对；
24 项次 - Project.swift 三次重复 = 21 精确）。

## 越界两件判定（申报待追认 → 逐件裁定）

| # | 文件 | 判定 | 依据 |
|---|---|---|---|
| ① | `WorkspaceHostView.swift`（7+/1-，净 +6） | **采纳** | 单 hunk = LibrarySearchModel 组装点 `fulltext:` 闭包参数（读 diff 亲证，零夹带）；`LibrarySearchModel.init` 的 fulltext 缺省 nil——无此缝则每次真实启动 submit fullText 落 `.fulltextUnavailable`，「真腿」只存在于测试 = 假腿；03 波 §9 同文件同款先例（两波无 hunk 交集）；commit body + DECISIONS §9 双申报 |
| ② | `SemanticSearchTests.swift`（4+/2-） | **采纳** | 02 波占位 pin `.unrecognizedToken("anything")` 钉的是 placeholder 解析错误行为，本 plan AC#7 字面 =「placeholder 换真腿」——两语义正面冲突，全套首跑当场暴露属预期；新 pin `.failed(.fulltextUnavailable)` = 无注入缝时 typed 诚实拒绝（「拒而不造假」语义保持），且污染断言（semanticHits nil / rows 不变）原样未动——**新族比旧 pin 更强**（typed 家族系本波新增），正当演化非削弱；commit body + DECISIONS §16 双申报 |

## 机检亲跑记录

1. **红线零网络面**：`git diff --name-only a986089..9114c48 --` 对
   Library/ + SemanticStore + Foundation + `App/Sources/Lightamer/MCP/`
   = **零文件**；`git grep URLSession LightamerCore/Sources/AI/` 两文件
   7 处（AIProviderClient，本波）+ 2 处（ModelAssetStore，01 波既有
   下载面，`git diff` 零触碰亲证）——DECISIONS §10 澄清与实况一致。
2. **登记闭环**：Project.swift LIB 段四行 + APP 段一行；BUNDLE-MAP 五行
   （LIB 9/7/22/15 + APP 13）与 `func test` 计数逐位一致；66 = 2863−2797
   精确。
3. **diff 半径（GlobalSearchDialog）**：全部 hunks = 头注 + fullText
   分支 + placeholderState 删除（grep 残留零命中）+ `.disabled` 移除 +
   apply() 空态 mode 分叉；CLIP/EXIF 输入分支零触碰；CLIP 空态文案
   `search_semantic_empty` defaultValue 基线 vs 现行**逐字节一致**
   （`git show a986089:` 对表亲跑）——DECISIONS §13 兑现。
4. **key 三面零泄漏（读码 + 测试双证）**：client 源码 key 只进
   Authorization/x-api-key 头（body 组装与 key 无交集；文件零日志面）；
   `testKeyRidesOnlyTheAuthHeaderAndNeverTheBodyOrErrors` 双协议断言
   header 恰 1 命中 + body 零子串 + typed error 文案零子串；store 错误
   族只载 OSStatus（CredentialError 枚举亲读）。
5. **E4 zeroize 字节级**：store 读出副本 `resetBytes(in: 0..<count)` +
   `allSatisfy == 0` 断言 + 清后重读仍完整 + 清后 ≠ 原值
   （`testReadoutZeroizeScrubOnlyTheCallerCopy` 亲读）；client 侧
   `defer` 全 range 清内部副本（Data CoW 所有权模型 DECISIONS §5 与
   实现一致——`String(decoding:)` 头串为 HTTP 必需衍生形态，注释在码）。
6. **https 双道门**：配置面（save 前）+ 传输面（send 前，wire 组装前
   guard，`testInsecureBaseURLRefusedBeforeAnyWireTraffic` 钉
   `recorded.isEmpty` 零流量）；loopback 例外硬编码 policy 内
   （grep 无 settings/env/UserDefaults 开关面亲跑）——DECISIONS §2
   「无暗开关」成立；矩阵含敌意格（`localhost.attacker.dev` 后缀游戏
   拒绝、`ws://loopback` 非 http 拒、scheme-less 拒）。
7. **无重试**：`AIProviderClient.complete` 源码单发（单 `try await
   send`，零循环零 backoff）；429/5xx typed `.providerError` 上抛。
8. **E5 join**：`AIDescriptionService.imageIDs` SQL = `MATCH ? AND
   u.active = 1`（`JOIN ai_understanding u ON u.id = f.rowid`，rank 序
   LIMIT 500）；负测双钉亲读——demote 行 raw MATCH 计数 >0 证「索引
   无 active 概念」+ 经 join 检索空集证「陈旧行不命中」；同 task 重跑
   旧词 unstage（L059 服务路径镜像）。demote 机制 = 02
   `replaceUnderstanding` 的 `UPDATE … SET active=0 WHERE task_id <> ?`
   （亲读，本波零 diff）。
9. **确认门唯一写面**：`images.rating` 写点全仓 grep 仅 `applyStars`
   UPDATE 一处（1...5 guard 拒 0/6/-1）；`rate()` 只 append ai_rating；
   controller `present()` 只建 proposals（sentinel 过滤 + 200 硬顶 +
   droppedByCap）——负测钉三层（Core `rate … NeverTouchesImagesRating`
   / App `testPresentAloneNeverWritesImagesRating` / 失败写保提案）。

## 重点读码抽查

- **AIProviderClient**：嵌套键修复在码（`OpenAIContentPart.ImageURLKeys`
  独立枚举 → wire `image_url.url`，golden :218 断言钉死回归）；端点拼接
  golden（openAI base 含版本段 + 尾斜杠不双写；anthropic 裸 host 拼
  `v1/messages`）；错误体双形一解码 + 非 JSON 截断 300 兜底；取消
  typed（URLError.cancelled / CancellationError 双臂）；AIJSON 字符串
  感知括号计数（转义引号/串内括号不计数，五形 golden 在案）。
- **AIRatingService**：rubric 五档×双语模板定稿与 DECISIONS §3 文本逐条
  对上（内嵌 JSON 契约 + 拒评哨兵指令 + 输出语言指令）；strictness 入
  参 clamp 1-5；`promptProfileID` = `StableHash.hash`（FNV-1a 64，
  DisplayProfile.swift 唯一生成器先例）`String(UInt64)` = decimal
  （L013）；解析面四支（1-5 原样 / 越界 clamp / 0 或缺席+reasons →
  哨兵 / 无理由 typed malformed）。
- **AIRatingController**：`RatingConfirmPreferences` 与 ImportDefaults
  同构（常量键 `library.ai.ratingConfirm` + 注入 suite + reset；
  `skipConfirmation` 正极性避免调用侧读反——§14 签注成立）；
  `confirmAll` 逐条成功才移除（首败抛出余量 intact）。
- **AIDescriptionService**：caption 必填 / tags 默认 / confidence clamp
  0...1；`rendition_kind` edited 默认 / original 显式；用户输入消毒 =
  逐 token 引号短语 + 内部引号双写（FTS5 语法字符不可炸查询）。
- **WorkspaceHostView fulltext 闭包**：装配点传 `AIDescriptionService
  .imageIDs(matching:store:)`——Core 面 E5 join 唯一消费入口，与 02 波
  semantic 闭包同型。

## FINDING

- **observation O-1**：本波 4 个新 UI 键（`search_fulltext_placeholder`
  / `search_fulltext_hint` / `search_fulltext_empty` /
  `search_error_fulltext_unavailable`）未入 `Localizable.xcstrings`
  （本波零 xcstrings diff），以 `defaultValue:` 英文渲染。判定 =
  **非违约**：03 波 O-1 同族（M2-10-07 PLAN 明文承载「zh String Catalog
  全量」阶段收口批）。登记挂 M2-10-07：届时 `zh-audit --check` 须覆盖
  03 的 16 键 + 本波 4 键 = **20 键**。
- **observation O-2**：DECISIONS §1「单发语义由 golden 钉死（每次调用
  恰一条 wire 请求）」表述偏强——在案测试钉了 insecure 零请求与 200
  路径 golden，但无「429/5xx 后 `recorded.count == 1`」显式断言；
  no-retry 属性本体验收由**源码读证**成立（complete 单发零循环），
  非缺口。建议后续如触 client 改造，补一条 429 → 单请求负测（observation
  级，不阻塞）。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | 准入矩阵逐格 + 双检 | ✅ AIEndpointPolicyTests 9/0/0（https 任意 host/http 三 loopback 双拼写/远程拒/非 http 拒/scheme-less 拒/归一化/端口路径无关）+ client 传输面零流量钉 |
| 2 | Keychain round-trip + 隔离 + 删除 + E4 字节零化 + 无泄漏 | ✅ AICredentialStoreTests 7/0/0 真宿主 keychain 激活态（skip 零命中亲证）+ ClientTests key 面 |
| 3 | 双协议 golden：请求体/响应归一/错误映射/取消超时 | ✅ AIProviderClientTests 22/0/0（URLProtocol mock 零真网；超时=config golden + 取消真路组合，§8 签注） |
| 4 | 评片 clamp/哨兵/profile id 稳定敏感 | ✅ AIRatingDescriptionTests verdict 族 + profile 族（稳定 + rubric/protocol/model 变更敏感 + decimal 形状） |
| 5 | 确认门三路径 + 不确认不落列 | ✅ FulltextSearchTests gate 族（present 负测钉/confirm/confirmAll/哨兵不提案/cap 200+dropped/不再询问往返/失败保提案） |
| 6 | 描述 reconcile + FTS JOIN active=1 + E5 负测 + rendition_kind | ✅ describe 族 + E5 双钉（raw MATCH 证索引在 + join 空集证不命中）+ L059 镜像 + edited/original 翻换 |
| 7 | fulltext tab 真腿 + 空态诚实 + 族互斥 | ✅ FulltextSearchTests leg 族（overlay rank 序/零命中空集/空输入清腿/typed unavailable/EXIF 互斥/失败族）+ dialog diff hunk 对表（CLIP/EXIF 零触碰 + CLIP 文案逐字节不变） |
| 8 | 红线：推理链零网络 + MCP 零 diff | ✅ URLSession 增量仅 AIProviderClient（ModelAssetStore 既有命中 §10 澄清属实）；MCP 面 diff 零文件亲跑 |
| 9 | 登记闭环 + diff 边界 == 申报集 | ✅ 五测试文件 Project.swift + BUNDLE-MAP 双命中；21 文件 = front-matter 18 + 申报 2 + 账本 1，零未申报 |

## 翻账

- **REQUIREMENTS `M2AI-04`：翻勾 ✅**（本验收批追记 Delivered 注记）——
  ①OpenAI/Anthropic 兼容 endpoint = 双协议手写 Codable 客户端（URL join
  golden + vision base64 载荷 + typed 错误族 + 零重试费用护栏）；
  ②1-5 星+理由（clamp + rating=0 reasons-only 哨兵 + 无理由 typed
  malformed）；③星级写库 = `applyStars` 确认门唯一写面（OQ-11-A：
  present 不落列负测钉 + 批 200 硬顶 + `library.ai.ratingConfirm` 不再
  询问）；④严格度+输出语言 = rubric 五档×双语 service 面（profile 护栏
  随行）——持久化设置 UI 归 M2-10-07 ACA 页（KD-2 明文承载 1-5 滑杆 +
  语言 picker），批量评片触发 UI 同页（SUMMARY 交接）。
- **REQUIREMENTS `M2AI-05`：翻勾 ✅**（本验收批追记 Delivered 注记）——
  caption+tags+scene+confidence 契约（caption 必填/confidence clamp）+
  `ai_understanding` reconcile（L059 服务路径镜像 + rendition_kind
  语义）+ 全文检索真腿 = `ai_understanding_fts` MATCH → JOIN active=1
  【E5】→ GlobalSearchDialog fulltext tab（CLIP/EXIF 零触碰 + 空态诚实
  + 互斥不污染）。
- **REQUIREMENTS `M2AI-06`：翻勾 ✅**（本验收批追记 Delivered 注记）——
  Keychain kSecClassGenericPassword 零状态面（真宿主测试激活态 7/0/0）
  + zeroize 字节级契约（全 range resetBytes + allSatisfy 断言 + 调用方
  所有权模型）+ https 强制双道门（loopback 三 host 例外**无开关**）+
  prompt profile 护栏（FNV-1a decimal String，rubric/protocol/model
  变更敏感测试钉）。key 三面零泄漏（header-only/body 净/错误文案净）
  测试钉在案。
- **GOAL-STATE**：本验收续接点追加。**未 push。**

## 下游交接注记

- **M2-10-05（worker 进程）**：无消费面交集（`AISession` transport 缝
  可复用）。
- **M2-10-06（v8 sidecar provenance）**：无交集（评片/描述行在 .lalb）。
- **M2-10-07（LCR/ACA 设置页）**：主消费方——AIConnectionConfig 表单 +
  `AICredentialStore.save/delete` key 录入/清除 + `RatingConfirm
  Preferences` 开关 + **O-1 的 zh 补录（03 波 16 键 + 本波 4 键 = 20 键）**
  + 批量评片触发 UI（网格多选入口，本 plan 交付服务+确认门编排）+
  O-2 的 429 单请求负测可随批补。
