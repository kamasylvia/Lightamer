# M2-10-04 DECISIONS — 执行期裁决与偏离签注

> 状态：执行波 worker 落盘（2026-10-03/04 夜），晨审可推翻。正本 plan = 同目录
> `M2-10-04-PLAN.md`；基线 = 2797/16/0（M2-10-03 验收后）。

## 1. 无自动重试收窄签注（D-9 字面裁决，plan 风险节预告）

「超时/重试/取消走 URLSession 原生」的执行收窄 = **本层零重试自动机**：一次请求
一次发送；429/5xx/超时全部 typed 上抛（`.providerError(status,message)` /
`.transportFailed`），由用户手动重跑。理由：评片/描述按张计费，指数 backoff 循环
在配额类错误（429）上是费用风暴放大器；URLSession 自身的传输级重试（连接复用/
HTTP2 重试）不受影响——收窄的只是**应用层业务重试**。`AIProviderClient.complete`
单发语义由 golden 钉死（每次调用恰一条 wire 请求）。

## 2. loopback 例外无开关签注（D-5 两选项取「输入即放行」）

`AIEndpointPolicy` 的 http://localhost|127.0.0.1|::1 例外**无任何设置面/环境
变量/UserDefaults 开关**——host 白名单硬编码在 policy 内。理由：暗开关 = 状态
分裂面（设置页 http 允许位 × URL 输入的组合空间），且「用户亲手输入 http://
loopback URL」本身就是知情 dev 行为；非 loopback http 在配置面与传输面**两道门**
（存 key 前 + 发请求前）都被 typed 拒绝，无绕行路径。矩阵逐格测试在案
（AIEndpointPolicyTests 9 例）。

## 3. rubric 模板文本定稿（KD-3 快照正本）

`AIRatingService.rubricText(strictness:language:)` 五档中文校准：
1（宽松）仅明显废片低分，其余 3 星以上 / 2（偏宽松）轻微缺陷 3 星 / 3（平衡）
综合评定 / 4（严格）默认 2-3 星，瑕疵压 2 / 5（严苛展出标准）多数照片 1-2 星；
英文逐档镜像（lenient / lenient-leaning / balanced / strict / exacting,
exhibition standard）。**每份 rubric 内嵌**：①JSON 输出契约
`{"rating": <1-5>, "reasons": [...]}`；②拒评哨兵指令（差到无法评级 →
`{"rating": 0, "reasons": [...]}`）；③输出语言指令（理由用中文/English）。
**文本即身份**：rubric 文本任何改动 = 全量 prompt_profile_id 翻新（护栏按设计
工作）；后续改文案须 DECISIONS 记录新旧 id 分界。

## 4. `Data.resetBytes` 默认空 range 陷阱（E4 零化面的关键实现细节）

Foundation 的 `Data.resetBytes()` **默认 range = `0..<0`——什么都不清**（本 SDK
中该参数无默认实参，裸调用直接编译错 `missing argument for parameter 'in'`，算
编译期救了一命；但文档语义上默认确实是不清零）。全项目零化契约统一
`resetBytes(in: 0..<count)`；测试钉在 AICredentialStoreTests（字节级 all-zero
断言 + 注释警示）。**建议入 LESSONS**（执行批已加 L062）。

## 5. 零化所有权与 Data CoW（KD-1「调用方 zeroize」的语义精确化）

`complete(apiKey:)` 的 defer 清的是**客户端内部副本**；Data 是 CoW 值类型——
调用方传入的缓冲不被该 defer 触及，**调用方在自己 readout 上 resetBytes 才是
契约主体**（与 AICredentialStore「返回即忘」配对：store 每次读出交新鲜副本，
caller 用后自清）。测试两面都钉：client 侧（key 只进 auth header、body/错误
文案零泄漏）+ store 侧（E4 字节断言 + 清后重读仍完整）。

## 6. URLProtocol mock 的 bodyStream 排水（URLSession→URLProtocol 缝的实证）

URLSession 把 `httpBody` 转成 `httpBodyStream` 交给 URLProtocol——golden 断言
请求体前必须排水 bodyStream（`read` 循环），否则 body 恒 nil、请求体断言假红。
实现钉在 StubURLProtocol.bodyData(of:)；这是 URLProtocol 测试的标准坑，测试
文件头注释备案。

## 7. openAI content part 嵌套键自指 bug（首轮测试当场抓出）

`OpenAIContentPart.imageDataURL` 首版嵌套容器复用外层 CodingKeys——
`{"type":"image_url","image_url":{"image_url":"data:…"}}`（内层键该是
`"url"`）。testOpenAIRequestGoldenFieldByField 的逐字段解体断言当场红；修 =
嵌套键枚举独立（`ImageURLKeys.url`）。教训：手写 Codable 的**嵌套对象键集
必须显式独立**，复用外层键枚举 = 静默拼错 wire 形状（golden 逐字段断言是唯一
可靠的防线）。

## 8. URLSession 超时用 config golden，不做 wall-clock 等待

`timeoutInterval == config.timeout` 走**录制请求断言**（URLProtocol 侧记录
timeoutInterval）；真实超时路径由**取消测试**家族覆盖（hanging mock + task
cancel → typed `.cancelled`，native URLSessionTask.cancel 语义直通）。理由：
真超时 = 强制 wall-clock 等待（秒级）+ mock 时序脆弱；取消腿已证明 abort
路径 typed 到达。计划 AC#3 的「取消超时」由该组合覆盖。

## 9. 越界文件申报（front-matter 外，1 件）

`App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（+6 行）：
LibrarySearchModel 组装点传 fulltext 闭包——plan front-matter 漏列本文件，但
「fulltext tab 真腿」若无装配点传缝则只存在于测试（= 假腿）。M2-10-03 §9
同款先例（该文件本波前一行，03 波已增 65 行——两波无 hunk 交集，后提交方
本波已含前波改动，无 rebase 面）。commit body + 本节双申报。

## 10. 红线机检的既有命中澄清（AC#8 的诚实记账）

`git grep URLSession LightamerCore/Sources/AI/` 命中两文件：本波
`AIProviderClient.swift`（预期）+ **既有** `ModelAssetStore.swift`
（M2-10-01 的资产下载面，commit 6a7e81e，本波零 diff）。plan 红线原文「仅
AIProviderClient 族命中」写作时未计 01 的下载面；架构红线的**意图**（嵌入/
打标/出片推理链零网络）成立：ModelAssetStore 是模型资产获取（用户触发的
一次性下载），不在推理链路。本波新增 URLSession 引用 = 零（grep 计数
AIProviderClient 7 处全在本波文件）。

## 11. provider_id 拼写与 max_tokens 常量

- 结果行 `provider_id` = `"rating-provider"`（AICredentialStore.ratingProviderAccount——
  OQ-7-A 单连接键；模型本体走 `model_id` 列，双 id 语义不重叠）。
- anthropic `max_tokens` = 客户端常量 4096（协议必填字段；本 plan 不做配置面，
  后续设置页若开放再入 AIConnectionConfig——纯 additive）。

## 12. 批量评片 200 行硬顶（费用护栏，plan 风险节字面）

`AIRatingController.batchLimit = 200`：present 截断 + `droppedByCap` 上报，
被截行不静默（调用方面可见）。远程调用的实际发起在调用方（本 plan 不含批量
触发 UI），cap 保护的是**预览表行数**与未来批量腿的误触发面。

## 13. 对话框空态文案 mode 分叉（共享函数的最小半径例外）

`GlobalSearchDialog.apply()` 的零命中 note 改为 `emptyNoteText(for: mode)`
二分：fulltext 专属文案 + **CLIP 文案逐字节保持原样**。apply() 是共享函数，
但 fulltext 分支拿错误语义的「semantic」文案违背「空命中诚实空态」；CLIP/EXIF
分支行为零变（diff hunk 机检：CLIP 输入分支零触碰）。同批新增 ErrorFamily
`.fulltextUnavailable`（App 侧呈现族，LibrarySearchModel 内聚 switch）。

## 14. `library.ai.ratingConfirm` 键名 polarity 签注

plan 钉的键名 literal（`ratingConfirm` bool，默认 false = 恒确认）语义读作
「用户已选不再询问」——名字与语义反极性是 plan 原文拼写，保持唯一登记键不改
（键名是持久契约）。`RatingConfirmPreferences` 的 Swift 面
（`skipConfirmation`）承载正极性，避免调用侧读反。

## 15. Swift 6 编译期签注

- URLProtocol 子类静态可变面：`nonisolated(unsafe)` + NSLock 三明治（reset/
  record/recorded 全锁内）——URLProtocol 回调在 session 队列，静态录制区
  必须显式同步。
- 测试 Task 闭包捕获：先落 Sendable 局部再进 Task（L038 纪律的 region
  isolation 变体，sending 参数报错一次即改）。
- `XCTAssert(try await …)` 自闭包禁令（L038）：本波三次编译错全该形态，
  局部变量先落再断言。

## 16. SemanticSearchTests 陈旧占位 pin 勘正（越界文件申报，2 件之一）

全套首跑 Library 红 1 项：`testExifAndSemanticLegsAreExclusive` 尾段 pin 了
fullText **占位行为**（`.failed(.unrecognizedToken("anything"))`，02 波写入）——
本 plan T4 字面就是「placeholder 换真腿」，占位 pin 与 plan AC#7 直接冲突。
勘正 = 该断言改钉新诚实族 `.failed(.fulltextUnavailable)`（该测试模型未注入
fulltext 缝 → typed 拒绝，行为语义「拒而不造假」保持）。同族检查：
LibrarySearchModelTests 的 `guard case .failed` 形态断言**兼容新族**（绿，零
改动零触碰）。**越界文件申报**：`SemanticSearchTests.swift`（M2-10-02 产
物，03 波保护面——该保护针对已完结的 03 并行波；本波改动 = 单断言 2 行 +
注释，commit body + 本节双申报）。

