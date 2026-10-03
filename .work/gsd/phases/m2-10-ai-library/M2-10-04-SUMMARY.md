# M2-10-04 SUMMARY — 评片/描述远程腿 + 凭据安全 + 全文检索真腿

> 执行 worker 收口（2026-10-03/04 夜）。四个功能提交 + 本收口提交；
> 裁决与偏离正本 = `M2-10-04-DECISIONS.md`（§1..15）。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `2e2a1ff` | AICredentialStore（Keychain kSecClassGenericPassword，service=bundle id，account=`rating-provider`，读出即忘 + 调用方 zeroize 契约）+ AIEndpointPolicy（https 强制 + loopback 三 host 例外**无开关** + 双道门）+ AIEndpointPolicyTests 9 + AICredentialStoreTests 7（真宿主 keychain，E4 字节级 zeroize） |
| T2 | `53f7dc1` | AIProviderClient 双协议手写 Codable（openAI chat completions / anthropic messages，URLSession 原生，零 SDK 零流式零重试自动机）+ vision 载荷（base64 JPEG）+ AISession transport 缝 + AIJSON.extractObject（围栏四形）+ AIProviderClientTests 22（URLProtocol golden，零真网） |
| T3 | `ccecf68` | AIRatingService（rubric×严格度×语言 + prompt_profile_id FNV-1a decimal + 哨兵/clamp 解析 + ai_rating append + applyStars 确认门写面）+ AIDescriptionService（契约解析 + understanding reconcile + **AIUnderstandingSearch 全文读面：MATCH→JOIN active=1**【E5】）+ AIRatingDescriptionTests 15（真 .lalb） |
| T4 | `67ae496` | AIRatingController（确认门编排：present 不落列/confirm 族/哨兵不提案/批 200 硬顶/`library.ai.ratingConfirm` 不再询问偏好）+ LibrarySearchModel fulltext 腿 + GlobalSearchDialog fulltext 分支真腿 + WorkspaceHostView 装配 +6 行（**申报越界**，DECISIONS §9）+ FulltextSearchTests 13（APP） |
| T5 | 本提交 | AC 机检 + 全套终跑对账 + SUMMARY/DECISIONS/GOAL-STATE + BUNDLE-MAP 五行 + LESSONS L062 |

## 测试数字（基线 2797/16/0）

- **终账：`TOTAL|2863/16/0`**（= 2797 + **66 精确对账**：AIEndpointPolicyTests 9
  + AICredentialStoreTests 7 + AIProviderClientTests 22 + AIRatingDescriptionTests 15
  全落 Library；FulltextSearchTests 13 落 App）。**对账链**：全套 run3 六 bundle
  干净绿（IOP 467/1/0、IOPParity 362/3/0、Layers 298/3/0、Library 568/4/0、
  Sessions 279/4/0、Export 338/1/0）+ App bundle **隔离复跑 551/0/0 EXIT=0**
  （`Executed 551 tests, 0 failures` 全量行在案，FulltextSearchTests 13 全绿其
  中）→ 2863/16/0。peakRSS 最大 IOP 6931MB < 8192 门；skip 16 = 基线**零新增**
  （keychain 激活态，AICredentialStoreTests 真跑非 skip）。
- **环境 flake 记账（诚实口径，非代码回归）**：全套三跑，宿主异常终止三次、
  崩点漂移（run1 Layers 3/298 abnormal + Library 1 fail=本波勘正的陈旧 pin；
  run2 App 5 tests ENOENT on tmp .lalb；run3 App 75/551 处 DrtPersistenceTests
  abnormal——BUNDLE|9/0/0 为 L055 解析器假绿形态，末类 suite 行被当 bundle 计
  数）。三次受害者**隔离复跑全绿**（LayerE2ERoundTripTests 精确到方法名 1/0/0、
  SemanticSearchTests 10/0/0、App 全量 551/0/0）；本波改动与 Layers/DRT 域零
  接触。处置 = L049 清盘（弃用 DerivedData 容器 ×2 共 4.7G + tmp fixture 残留
  115 目录）+ 隔离复跑对账；**L055 脚本级修复挂账另案**（宿主 crash 的
  BUNDLE 假绿行仍会骗 EXIT=0，读数必须 `terminated abnormally` 机检 + 各
  bundle 末行核对 All tests 总计行）。

## 交付面形态（KD 对照）

- **凭据与准入（KD-1/D-5）**：Keychain 无状态静态面（store 永不留副本）；
  准入矩阵 https 通 / http×{localhost,127.0.0.1,::1} 通（[::1] 拼写折叠）/
  其余 typed 拒；**存 key 前与发请求前双检**（client send 门在 wire 前，
  测试钉「insecure base = 零 wire 请求」）。
- **双协议客户端（KD-2/D-9）**：请求体逐字段 golden 双协议（openAI
  `{model,messages[{role,content-parts}]}` + Bearer；anthropic
  `{model,max_tokens=4096,system,messages[image-first]}` + x-api-key +
  anthropic-version）；响应归一（choices[0].message.content / text-blocks
  拼接 + finish/stop reason）；错误体 `error.message` 双形一解码 + 非 JSON
  截断兜底；取消 typed（native cancel）；**无重试自动机**（DECISIONS §1 签注）。
- **评片流（KD-3/OQ-11-A/D-4）**：rubric 五档×双语模板定稿（DECISIONS §3，
  含 JSON 契约 + 拒评指令 + 语言指令，文本即 profile 身份）；
  `prompt_profile_id` = FNV-1a(rubric|protocol|model) **decimal String**；
  解析面 = 1-5 原样 / 越界 clamp / rating 0 或缺席+reasons → 哨兵行 /
  无理由拒评 typed malformed；**写入序 = ai_rating append 恒发 →
  images.rating 只经 applyStars 确认门**（Core 唯一写面 + 控制器编排 +
  负测钉「present 不落列」三层层层设防，rating 无 undo 基建故确认门即最后防线）。
- **描述流 + 全文检索（KD-4/M2AI-05/E5）**：契约 caption 必填/tags 默认/
  confidence clamp；reconcile 走 02 的显式 DELETE+INSERT（L059 镜像经服务
  路径回归）；`rendition_kind` edited 默认/original 显式；**全文读面 = 本 plan
  新建**（02 文件零 diff）：`ai_understanding_fts MATCH` → JOIN active=1 →
  rank 序 id 集；E5 负测双钉（demote 行仍被索引——raw MATCH 证——但不过
  JOIN；同 task 重跑旧词 unstage）；用户输入消毒 = 逐 token 引号短语（FTS5
  语法字符不可炸查询）。
- **fulltext tab（T4）**：对话框 fulltext 分支真输入（CLIP/EXIF 分支零触碰
  ——diff hunk 机检）；Search 按钮去禁用；零命中 note mode 分叉（CLIP 文案
  逐字节不变，DECISIONS §13）；grid overlay 复用（CLIP 腿同型，rank 序）；
  无装配缝 = typed `.fulltextUnavailable` 诚实族。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | 准入矩阵逐格 + 双检 | ✅ AIEndpointPolicyTests 9/0/0（https/http 三 loopback/拒绝面/归一化）+ client insecure 零 wire 钉 |
| 2 | Keychain round-trip + 隔离 + 删除 + E4 字节零化 + 无泄漏 | ✅ AICredentialStoreTests 7/0/0（真宿主 keychain）+ ClientTests key 面断言 |
| 3 | 双协议 golden：请求体/响应归一/错误映射/取消超时 | ✅ AIProviderClientTests 22/0/0（URLProtocol mock 零真网；超时=config golden + 取消真路，DECISIONS §8） |
| 4 | 评片 clamp/哨兵/profile id 稳定敏感 | ✅ AIRatingDescriptionTests verdict 族 + profile 族 |
| 5 | 确认门三路径 + 不确认不落列 | ✅ FulltextSearchTests gate 族（present 负测钉/confirm/confirmAll/不再询问/失败保提案/哨兵不提案/cap 200） |
| 6 | 描述 reconcile + FTS JOIN active=1 + E5 负测 + rendition_kind | ✅ describe 族 + E5 双钉 + L059 镜像 |
| 7 | fulltext tab 真腿 + 空态诚实 + 族互斥 | ✅ FulltextSearchTests leg 族 + dialog diff hunk 对表（CLIP/EXIF 零触碰） |
| 8 | 红线：推理链零网络 + MCP 零 diff | ✅ URLSession 增量仅 AIProviderClient（ModelAssetStore 既有命中澄清，DECISIONS §10）；MCP 面零 diff |
| 9 | 登记闭环 + diff 边界 == 申报集 | ✅ 五测试文件 Project.swift × BUNDLE-MAP 双命中；diff 边界 = front-matter 全量 + §9 申报一件 + 账本文件 |

## 偏差与申报（全量清单）

front-matter 外源码文件共两件：①`WorkspaceHostView.swift`（+6 行，§9——
fulltext 装配缝，无它则真腿只存在于测试 = 假腿；03 波 §9 同款先例）；
②`SemanticSearchTests.swift`（单断言勘正，§16——02 波的 fullText 占位 pin
与本 plan AC#7「真腿」字面直接冲突，全套首跑当场暴露，改钉新诚实族
`.fulltextUnavailable`）。
计划文本外的执行裁决：超时=config golden + 取消真路组合（§8）、
provider_id=`rating-provider` 与 max_tokens=4096 常量（§11）、空态文案
mode 分叉（§13）、ratingConfirm 键 polarity 签注（§14）——晨审可推翻，
改动半径各一处函数。

## 首轮测试抓出的真缺陷（防线自证）

- **openAI content part 嵌套键自指**（§7）：嵌套容器复用外层 CodingKeys →
  wire 上 `image_url.image_url`（应为 `image_url.url`）——逐字段 golden
  当场红，独立键枚举修复。手写 Codable 的嵌套对象键集必须显式独立。
- **Data.resetBytes 默认空 range**（§4/L062）：无参调用 = 清零零字节
  （本 SDK 编译期拦截）；zeroize 契约统一显式全 range + 字节级断言。

## 交接（下游 plan）

- **M2-10-05（worker 进程）**：无消费面交集（本 plan 远程腿与本地推理
  worker 正交）；`AISession` transport 缝若 worker 需要远端调用可复用。
- **M2-10-06（v8 sidecar provenance）**：无交集（评片/描述行在 .lalb，
  不触 sidecar）。
- **M2-10-07（LCR/ACA 设置页）**：**主消费方**——ACA 页 =
  AIConnectionConfig 表单（protocol/baseURL/model/严格度/语言）+
  `AICredentialStore.save/delete`（key 录入/清除，policy 存前门已备）+
  `RatingConfirmPreferences` 开关 + `LabelingPreferences.reset()` 同页；
  LCR 页照 03 交接。批量评片入口（网格多选 → 评片）的触发 UI 未建
  （本 plan 交付服务+确认门编排，UI 挂 ACA/LCR 页或右键菜单）。
- **验收轮**：`M2-10-04` 关键抽查点 = E5 负测（stale 行不命中）、
  确认门负测钉（present 不落列）、key 零泄漏三面（header-only/body 净/
  错误文案净）。

## 阻塞节

无 E3 阻塞。环境注记：①系统盘 8.5Gi→13Gi（L049 清盘后）；②**App/Layers
宿主长跑稳定性挂账**——三跑三崩、崩点漂移、隔离全绿，与 L049/L018 家族
症状一致；验收轮全套复跑时若再现，先 `terminated abnormally` 机检再归因；
③CoreML 缓存热（03 波预热），全套正常水位 806-1012s。
