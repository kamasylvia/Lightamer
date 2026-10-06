# M2-10-07 SUMMARY — UI 收口 + zh + 翻账（wave 6，M2-10 末波）

> 执行 worker（2026-10-04 夜间批，全自动授权在案）。正本输入 = PLAN（含
> checker 回注 M4/M9/M11）+ 六波 SUMMARY/ACCEPTANCE + CONTEXT 裁决。
> 提交批 = `9daf709`（T1）/ `47e46c4`（T2）/ `9586c1b`（T3）/ T4 收口本件，
> 全部未 push。**M-1 内存修复批已于本波前置（`c573087`，验收基线 2929/16/0）**。
>
> **续班注记（2026-10-07）**：前任 worker 于 2026-10-04 04:08 写完收口三稿
> （SUMMARY/DECISIONS/VALIDATION-INPUT）后死亡——T4 提交未落库、
> `--all` 补跑第三跑结果未及记录。续班 worker 收尾：在制品甄别收留
> （O-2 断言/REQUIREMENTS 翻账/LESSONS L066-067 均属本 plan 申报面）+
> **全套 `--all` 终轮重跑单轮干净绿 `TOTAL|2955/16/0|1019s`**（SidecarV5
> ANE flake 持续窗口结束复绿，第五波记账收口，见专节）+ T4 提交落库。
> 执行批历史轮记录（下文 2955/16/1 等）按「历史状态行不改写」纪律原样保留。
> 归属：REQUIREMENTS 翻账由并行 orchestrator 批 `de68703` 承载（hunk 零
> 篡改，DECISIONS §D16 对账登记）；其余收口件 = 本收口批（`docs(m2-10)` closeout）；O-2 断言 =
> `70d782a`。

## 提交账

| 提交 | 任务 | 内容 |
|---|---|---|
| `9daf709` | T1 | `feat(app): aca settings page with connection store`——LibraryConnectionStore（拆分持久化：defaults 非秘密面 + Keychain key 面，account 注入）+ ACASettingsModel（准入前置/严格度/语言/不再询问/连接测试）+ SettingsACAPage（SettingsPages 换真页）+ ACASettingsTests 10 |
| `47e46c4` | T2 | `feat(app): lcr settings page with model tiers`——LCRSettingsModel（五态映射/待发布禁点/下载移除/换激活入队/兼容重置/就绪探针/labeling 三态）+ SettingsLCRPage + SettingsView 换真页 + Settings scene 注入 projectController + LCRSettingsTests 10 |
| `9586c1b` | T3 | `feat(app): ai entry points and zh strings`——图库右键两命令 + Image 菜单两命令 + WorkspaceModel 请求面 + AIEntryPointCoordinator（顺序批量/生产缝/评片确认门/描述直写/任务栏 handle/key 缺席引导）+ 两 sheet + AIEntryPointsTests 6 + zh 批 126 键入目录/6 孤元移除 |
| T4（本件） | 收口 | MCP 零 diff 核验 + OQ-12-A defer 记录 + REQUIREMENTS M2AI 翻账 + 04 波 O-2 显式断言随批 + SUMMARY/DECISIONS/VALIDATION-INPUT + GOAL-STATE |

共享文件（SettingsPages/SettingsView/LightamerApp/Project/BUNDLE-MAP）按
**可构建前缀**分批进提交（每态 tuist generate + build-for-testing 0 error
逐态验证）——DECISIONS §D12。

## 交付面（对 AC 总表）

1. **LCR 页**（AC#1）：五档位清单 = profile/维/许可/体积（digest byteCount，
   未发布显「—」）/distribution 徽标/六态直映；**待发布禁点**（digestUnpublished
   → 「待发布」无下载按钮，fail-closed UI 面）；下载/移除（真 ModelAssetStore +
   temp-dir 测试真链）；**换激活** = 确认对话框 → `registry.recomputeAll`
   入队断言（真 registry drain，taskDidFinish 捕获 kind）；页内「重算中」态
   （进度在 BackgroundTask 栏——不入页）；**兼容性记录重置** = 确认后
   `CompatRecord.resetAll()` → 文件删除终态；数据政策脚注（本地不上云）；
   就绪探针三态（probing/ready/unavailable——bundled 资产 + 真 worker ping）；
   labeling 三态 + 重置（03 交接）。
2. **ACA 页**（AC#2）：协议二选一 / baseURL（**变更即过 AIEndpointPolicy，
   拒绝 = 行内红字 typed 文案 + 零存储**；store 侧背照双保险）/ model /
   key SecureField→Keychain（save/delete + 「未配置」横幅）+ **key 零 defaults
   负测**（整 suite dump 无 key 子串）/ 严格度 1-5（clamp）/ 输出语言三选
   （system 按 preferredLanguages 解析）/ 不再询问开关 / 连接测试（URLProtocol
   mock 四形态：ok/failed/missingKey/missingConnection + refusedEndpoint 零
   流量）。
3. **双入口 + Inspector AI 区**（AC#3）：图库右键两命令（ acted-on 集 =
   含点击行的选区，否则单行）+ **Image 菜单**两命令（编辑器当前图，
   `CommandMenu` 落 LightamerApp——D3 申报）→ WorkspaceModel 请求面 → 宿主
   AIEntryPointCoordinator：**顺序单张批量**（done 自动推进非末张/用户关闭
   放弃余量/空集拒绝/关闭停 worker）+ 生产缝（frameProvider = 原文件解码
   D-3 新源像素语义；modelFacts/tileExecutor = worker 通道经打开档位盒）；
   Inspector「AI 评片…」= 顺序扫描（任务栏进度可取消）→ OQ-11-A 确认门
   sheet（逐行应用/全部应用/放弃；不再询问直通 confirmAll）→ applyStars
   唯一写面；「AI 描述」= 直写零确认（D8）+ rendition_kind 按行分叉；
   **key 缺席** = Inspector 命令区换引导行（SettingsLink 深链 ACA 页，
   D11）。marker 冻结集 7 枚机检（AIEntryPointsTests）。
4. **AC#4 枚举零改**：`SettingsPage` 枚举/IA 顺序零 diff（两 case 仅换渲染
   分支；`git diff` hunk 对表在 T3/T4 提交边界亲验）。
5. **AC#5 MCP 零 diff**：`git diff --name-only App/Sources/Lightamer/MCP/
   LightamerCore/Sources/MCP/` over `c573087..9586c1b` = 零命中（Export/
   Version 红线域同检零命中）+ MCP 既有测试全绿 + **`semantic_search` defer
   签认**（DECISIONS §D14，OQ-12-A）。
6. **AC#6 zh**：`zh-audit --check` **PASS**（1505 源键/1753 目录键/zh 完整/
   locale ⊆ {en,zh}）；批 = 挂账 24 键（03 的 16 + 04 的 4 + **02 波遗留 4**
   ——审计实测超出挂账口径的部分，一并清账）+ 本波新键 102 − 孤元 6
   （占位退休死键；DECISIONS §D13）。
7. **AC#7 翻账**：REQUIREMENTS **M2AI-01/08 翻勾** + 03/04/05/09/10 四注记
   追加（diff 7 行全落 M2AI 族，纪律 5 亲验）；04 波 O-2 随批消费
   （`recorded.count == 1` 显式断言，AIProviderClientTests 22/0/0）。
8. **AC#8 phase 终轮**：执行批首轮 `--all`（2026-10-04，`9586c1b` + T4 账本
   批构建）= **`TOTAL|2955/16/1|1129s`**，唯一 fail = **在案 ANE 环境型
   flake** `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile`
   （第四波记账，详见下节）；七 bundle 逐值 IOP 467/1/0、IOPParity 362/3/0、
   Layers 298/3/0、Library 581/4/0、Sessions 279/4/0、Export 338/1/0（六
   bundle 与基线零漂移）+ App **630/0/1**（601 基线 + c573087 +3 + 本波
   +26 = 630 精确；本波 26 全绿；peakRSS 最大 IOP 6245MB 零 MEMFAIL；skip
   16 = 基线零新增；L055 机检 = 七日志 `terminated abnormally` 全零 +
   Executed 行逐值一致——非假绿形态）。
   **续班终轮（2026-10-07，本 plan 终态判据）**：全套 `--all` 重跑（同一
   源态重建 build-for-testing，BUILD_EXIT=0）= **`TOTAL|2955/16/0|1019s`
   单轮干净绿**——六 bundle 逐值零漂移（IOP 467/1/0 peak 5737MB /
   IOPParity 362/3/0 peak 5992MB / Layers 298/3/0 / Library 581/4/0 /
   Sessions 279/4/0 / Export 338/1/0 peak 5483MB）+ **App 630/0/0**（
   SidecarV5 同用例 13.338s passed 复绿）+ skip 16 零新增 + L055 七日志
   abnormal 全零 + peakRSS 最大 5737MB 零 MEMFAIL。**2929 基线 + 26 =
   2955 精确对账，phase 终轮 0 fail 达成**。

### ANE flake 第四波记账（执行批处置）→ 第五波收口（续班终轮）

- 形态：`SidecarV5Tests.testWriteLeg…`「decode readback never reached
  boost=0.6」（首轮 105.8s 超时；同宿主日志 ANE 编译器持续报
  `ANECCompile() FAILED`——**宿主 ANE 编译态劣化**，非确定性可复现窗口）。
- 处置链（按 01/05/06 恢复协议）：隔离 **11/0/0 绿**（33s）→ App 全量补跑
  **两连红同用例**（第三跑进行时执行 worker 死亡，结果未及记录）。
- 域零接触机检：`git diff c573087..HEAD --name-only` 无 Sidecar/ANE 域文件
  （零 SidecarV5/RAWDecoder/CI 触碰）。
- 06 验收 O-1 的「另案挂账硬化」建议升级为 **四连记账**（01 执行 / 06 验收
  / 07 --all / 07 补跑），Phase 15 flaky 清算批立案输入（GOAL-STATE 阻塞节
  同步登记）。本波 +26 与六 bundle 对账不受影响。
- **第五波收口（2026-10-07 续班终轮）**：全套 `--all` 重跑同用例
  **13.338s passed**，本轮 0 fail——持续窗口自然结束（隔 ~68h 重启宿主后
  ANE 编译态恢复，支持「宿主态劣化」归因）。**五波台账终态 = 两红三绿，
  环境型归因维持**；Phase 15 清算批立案输入更新为本节全文。
9. **AC#9 登记闭环**：Project.swift 三命中 = BUNDLE-MAP 三行 = `grep -c
   "func test"` 10/10/6 逐位；diff 边界 = front-matter 申报集 + D3 申报增量
   表（5 文件）——front-matter 外未申报源码零（`git diff --stat` 对表亲验）。

## 偏差与执行期发现

- **D3 申报增量五件**（front-matter 起草缺口，授权原文 + additive，03/04
  WorkspaceHostView 先例同族）：SettingsView（case switch 所在）/ LightamerApp
  （CommandMenu 唯一落点 + Settings env）/ WorkspaceModel（请求面）/
  WorkspaceHostView（coordinator + sheet 宿主）/ AIProviderClientTests（O-2
  断言）。**EditorWorkspaceShellView 零触碰**（front-matter 列名但其职责由
  LightamerApp 承载——反向起草缺口，登记即闭）。
- **挂账口径修正**：zh 缺键实测 24（挂账 20）——02 波 CLIP tab 4 键为第三波
  O-1 同族，审计全集清账；`search_fulltext_placeholder` 在审计提取器形状外
  （continuation 形态），一并补录。
- 插值键形态：`String(localized:)` 带 defaultValue 时 key 为 StaticString
  ——插值键一律 catalog-only 形态（本波 11 处）；`Locale.preferredLocalizations`
  不存在 → `Locale.preferredLanguages`；`CIImage.extent` 为 CGRect（Int 转换
  显式化）。
- `ImportService` 构造歧义：`LightamerCore.ImportService(store:)` 显式限定
  （模块限定后一次通过）。

## 测试对账

| bundle | 基线（c573087） | 本波终轮 | 增量 |
|---|---|---|---|
| IOP | 467/1/0 | 467/1/0 | 0 |
| IOPParity | 362/3/0 | 362/3/0 | 0 |
| Layers | 298/3/0 | 298/3/0 | 0 |
| Library | 581/4/0 | 581/4/0 | 0 |
| Sessions | 279/4/0 | 279/4/0 | 0 |
| Export | 338/1/0 | 338/1/0 | 0（红线门零漂移） |
| App | 604/0/0 | **630/0/0**（续班终轮；执行批首轮 630/0/1 = ANE flake，已复绿记账） | +26 |
| **TOTAL** | **2929/16/0** | **2955/16/0**（2026-10-07 续班终轮 `1019s`） | **+26 精确** |

- **App 基线口径**：06 验收 601 + `c573087`（M-1 修复批）+3（EnhanceDialog
  回归）= 604；+26 = ACASettingsTests 10 + LCRSettingsTests 10 +
  AIEntryPointsTests 6（BUNDLE-MAP 三新行逐位一致）。AIProviderClientTests
  的 O-2 断言为用例体内加断言（`func test` 计数不变 22，Library 581 零漂移
  ——BUNDLE-MAP 行 22 不变）。
- 定向回归亲点：EnhanceDialogTests 13/0/0、EnhanceCopyTests 8/0/0、
  SettingsPagesTests 10/0/0、WorkspaceRoutingTests 11/0/0、LabelingDefaults
  13/0/0、AnalysisRegistryTests 13/0/0（共面零涟漪）。
- skip 16 = 基线零新增（keychain 激活态真跑：ACA key 面 / LCR 探针在案）。

## M2-10 phase 小结（七波收口）

- **交付**：M2AI-01..10 全族 Delivered（REQUIREMENTS 翻账终态）——本地 CLIP
  嵌入（五档位资产/混合获取/fail-closed）+ 嵌入存储与 vDSP 检索 + CLIP/全文
  双真腿搜索 + 出厂 173 标签自动打标（ask/always/never）+ 双协议远程评片
  （确认门/严格度/语言/不再询问）+ AI 描述（FTS 可检索）+ Keychain/HTTPS
  凭据面 + 后台任务栏（取消/增量终态）+ `--ai-worker` 进程隔离 crash-safe
  （降级链/CompatRecord）+ AI 出片（sidecar v8 provenance/分块推理/可编辑
  副本/增强对话框双入口）+ 设置两页收口。
- **测试**：2577（M2-8 基线）→ **2955/16/0**（+378 = 七 plan +375 + `c573087`
  M-1 修复 +3）；逐波验收 01..06 全 PASS（0 error 主基调，minor 均闭环或
  挂账在册）；真模型 golden 链多波激活态亲点。
- **质量事件**：真缺陷四件（02 L059 FTS 双文档、03 drain 双 fire、06 blend
  行距 + 输出名假设、L065 join）全部修复 + 揭穿面测试在册；06 验收 M-1 内存
  口径差由 `c573087` 前置闭环（两阶段 engine + typed 门）。
- **许可纪律**：Lumen/Alcedo/darktable 全程只读（GPL/MIT 参考，零代码复制
  ——RAWmakase 登记为 MIT reference 后撤销）。
- **挂账**：`M2-10-VALIDATION-INPUT.md` 十项（Release 上架清单/命中质量走查/
  真批量队列/衍生徽标/视觉走查/深链限制/100MP 内存 E3/性能表/flake 台账/
  worker 冷启动）——全部观察项，无交付缺口。

## M2-11 交接（下一 phase）

1. **60fps@100MP 复验**（M2PERF-01）：bench 基线 preview-2560 cold 117ms/
   warm 85ms（M2-6-3 在案）+ M2-10 全链加载后复测；denoise 链 85.7ms 未达标
   的正杠杆 = 更深预览降载（Phase 5 SC#4 遗留）。
2. **MCP 面零改动交接**：Phase 14 launcher + 外部 client 双入口照旧；
   `semantic_search` defer 至外部需求立项（OQ-12-A 签认在 DECISIONS §D14）。
3. **AI 面 GUI 走查**：VALIDATION-INPUT 观察清单 5（视觉对照）随 M2-11
   GUI 验收轮一并执行（Alcedo 对照截图方法学）。
4. **flaky 清算**（Phase 15 预约在案）：SidecarV5 ANE flake + LayerE2E
   RoundTrip 负载型 + Library 缩略图队列——三案台账在 GOAL-STATE/LESSONS。

## 环境注记

- 执行批 `--all` 首轮记录 ANE flake 1 fail（已记账）；**续班终轮（
  2026-10-07）单轮干净绿，无 flake 复现、无宿主异常**——phase 终态以此轮
  为准。执行批构建链 = `tuist generate` ×3（每提交态）+ build-for-testing
  逐态 0 error；续班终轮 build-for-testing 增量重建 BUILD_EXIT=0。
- zh-audit 提取器缺口（`search_fulltext_placeholder` continuation 形态漏提）
  观察在案——非本波门（PASS 主体达成），硬化建议随 Phase 15 清算批。
- **续班机检复核（2026-10-07）**：MCP/Export/Version 红线域
  `git diff --name-only c573087..9586c1b` 零命中亲跑复现；`zh-audit
  --check` PASS 复现（1505/1753/{en,zh}）；BUNDLE-MAP 三新行 10/10/6 ×
  `grep -c "func test"` 逐位一致；`SettingsPage` 枚举本体零 diff（diff
  触碰仅新页 view modifier）；双入口/Inspector marker 七枚读码在位。
