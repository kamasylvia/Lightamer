---
phase: M7-4（MCP O4 跨图批量 + note 归属 + UQ-A2——MCP2-08..09）
slug: m7-4-mcp-o4
status: validated
nyquist_compliant: true
created: 2026-10-17
validated: 2026-10-17
batch_form: dual-acceptance closeout（执行批 ΔN +20 已入库；本签核批 doc-only）
---

# Phase M7-4（MCP O4 跨图批量 + note 归属 + UQ-A2）— Validation（双路独立验收 PASS 签核——copy/paste 双工具 + sidecar v11 + UQ-A2 终写原子 + S1/S2/S3 清算）

> 体例对齐 `phases/m7-3-mcp-o2o3/M7-3-VALIDATION.md`（正本链上溯
> `phases/m7-2-mcp-o1/M7-2-VALIDATION.md` → `phases/m7-1-shell/M7-1-VALIDATION.md` →
> `phases/fix2-defects/FIX2-VALIDATION.md`）。
> 执行链 `49fab645..df0928f4`（7 commits = T1 S1 修复批首项 → T2 S2 预热四点+env 门+S3
> 正臂腿 → T3 O4 双工具+note/author+v11 → T4 UQ-A2 终写原子 → T5 match_color 目录锚 →
> T6 union 27→29+goldens → T7 收口翻账）；双路独立验收 = 第一路
> `M7-4-01-ACCEPTANCE.md`（全套独立复跑〔全新 build-for-testing 自证新鲜度〕+ S1/UQ-A2
> 深审 + e2e/kill 对照亲跑 + union 全点位亲核 + 偏差十条逐条裁决）+ 第二路
> `M7-4-01-ACCEPTANCE-2ND.md`（切入刻意错开 = 五面审计：paste 批量写三段事务语义 /
> V11 五法非永真性+升级链 / MPF 偏移容器交互+卷实测 / e2e 实质+kill 对照〔自建探针〕
> / 偏差十条独立复核）——**PASS / 0 error + 3 minor 零实质分歧**（第一路 2 open：
> minor-1 五处过时计数注释 + minor-2 strerror clobber；第二路新 1 open：minor-3 paste
> 段3 drain 写失败不进应答——既有段3 语义新暴露非本批引入；观察项 A/B + 行号勘正为
> 第二路增量非矛盾）；**三方全套同值 `TOTAL|3925/35/0|`**（执行批 + 双路独立复跑，
> exit 0 零 MEMFAIL 七 bundle 全 8G 门内；= 3905 基线 + ΔN 20 精确；预估带 +22..29
> 未达，**带差 −2 如实记账**——可选锁窗腿时间盒未行使 + golden 实质面收敛，无静默
> 吸收）。M7-3 挂账①②③⑤⑥ 全收口（双路亲证：S1 poll POLLIN+revents 分流修死 +
> e2e 0.87s/wal==0 + kill 形 387312 字节对照判别力双证；S2 = A+C 落地 warmLutLibrary
> 四装配点 + `LIGHTAMER_SKIP_LUT_PREHEAT` 门 + 文案；S3 正臂腿三 clause；
> ⑤ match_color kind0 锚腿；⑥ 三处措辞校订正本 DECISIONS §2.10 且 M7-3 签核文档零
> 回改）；FIX2③ controller 零 diff 第三波维持；union 改动权行使合规、用讫移交
> M7-5（串行禁并行延续）。omp 制度路由双 zcode 独立眼替代（M6-2..M6-5 先例，晨审
> 可裁）；夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻）。裁定正本 =
> `M7-4-CONTEXT.md`（D-M7-4-1..10 零重开）+ `M7-4-01-DECISIONS.md`（§1 union 取权
> 申报 + §2 偏差清单 + §3 上游分歧与行为变化 + §4 S3/O1 漂移注记 + §5 红线族）+
> 双 ACCEPTANCE；数字正本 = 本文件。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Batch form** | 执行批 T1→T7（`49fab645` T1 S1 poll POLLIN+250ms bounded re-poll+revents 分流+e2e 真断连新法+探针分仓 → `d3f487a6` T2 S2 预热四点+env 门+list_luts 描述原位值改+S3 正臂腿 → `a78ea631` T3 O4 双工具+AdjustmentTransferCatalog+HistoryItem note/author+v11 镜像 → `2af9b17d` T4 UQ-A2 exclusiveFinalWrite+link() 晋升 → `a9b8f06e` T5 match_color 目录锚+kind0 锚腿 → `503f1ffc` T6 union 29+六组 goldens+GUI 面 → `df0928f4` T7 收口翻账 docs）→ 双路验收 → 本签核批（doc-only） |
| **Full suite（三路同值）** | 执行批（T7 全套）/ 第一路（2026-10-17，2076s——先做全新 `xcodebuild build-for-testing` 重构自证产物新鲜度：执行方产物 mtime 08:44 早于 T6 commit 08:51，mtime 面不可自证）/ 第二路（2058s——符号亲证产物新鲜度：主机含 `paste_adjustments` ×9 + Library xctest 含 `SidecarV11Tests` ×4，全套轮即跑在该产物上；两路互不相倚同判）三路独立跑 `caffeinate -dis Scripts/test-direct.sh --all` 均 **`TOTAL\|3925/35/0\|`** exit 0 **零 MEMFAIL 七 bundle 全 8G 门内**。逐 bundle：IOP 687/5/0（peakRSS 7770/7610MB）/ IOPParity 460/3/0（7256/7009MB——已知贴线 bundle，双路全 8G 门内）/ Layers 494/5/0（808MB）/ Library 736/4/0（623/621MB）/ Sessions 284/9/0（1629/1262MB）/ Export 385/5/0（6107/6170MB）/ App 879/4/0（2832MB）；skip 35 构成 = 5+3+5+4+9+5+4，全部既有 env/perf-probe 门零漂移零静默吸收；App 轮 370-379s 无 50s 预热停滞 = runner 中央 env 门生效面佐证 |
| **ΔN 记账** | **ΔN = +20**（T1 App+1〔e2e 真断连〕/ T2 App+1〔S3 正臂腿〕/ T4 Export+4〔TOCTOU 负测+正向恒等+.replace 守卫+encoder 失败第五腿〕/ T5 App+1〔kind0 锚腿〕/ T6 App+8〔editing 6 + Catalog 恒等 1 + get_history 红尾 1〕+ Library+5〔SidecarV11Tests 五法〕；双路亲数对账）；对账链 3905 基线 + 20 = 3925 **精确闭合**；**带差 −2 如实记账**：预估带 +22..29（research §0.5/plan）未达——构成 = S1 可选锁窗腿未行使（plan 时间盒条款；e2e 主腿已以同测试内第二 open typed `projectHeldByOther` 承载锁语义侧写，确定性形强于 12s 竞速形，偏差⑨双路裁成立）+ T6 golden 按实质面收敛（O4 六法 + V11 五法 + 红尾一腿，未拆更细粒度）；带下如实申报，无凑数测试无静默吸收 |
| **红线族机检** | 双路独立电池全 PASS：零新 SPM（Project.swift 恰一行 SidecarV11Tests 登记 + dependencies 块零 diff）／`.metal` 全域零 diff／HistoryHash.swift 零 diff（item 元数据不入折机制证）／McpToolRegistry.swift 含 McpTimeouts 零 diff（错误码 16 档封闭表 + 超时档零新增）／ExportNamer+ExportQueueContract+ExportFormatSpec+ImageIOEncoders+WebPEncoder+ExportInspectorView+LibraryProjectController 零 diff（**FIX2③ 第三波维持**）／Pipe/Graph/IOP 域仅申报内三文件（HistoryStack/PasteSemantics/LightamerSidecar carve-out 逐 hunk 亲核 = 恰申报面）／`isAdjustmentTransferable` 全仓恰 1 定义／`runModal` App/Sources 零命中／LocalizationValue 插值禁形唯一命中 = LightamerApp :2307 既有文档注释／xcstrings 恰 2 hunks（1 原位值改 + 1 尾块三键插入）／UserDefaults 零新键／SidecarV10Tests 零 diff（:327 法语义退化申报-补偿闭环亲证）／M7-3 签核文档零回改（`git diff` 0 行双路亲跑）／改动文件清单 = T1-T7 逐 commit --stat 并集（+Scripts/test-direct.sh = 偏差③申报面） |
| **端到端证据** | S1 graceful 断连 e2e（真产线二进制 spawn → initialize → project_create → 关 stdin 真 EOF → **0.87s exit(0)** + `.lalb-wal` size==0）+ **kill 形对照双路独立同值**（自建探针 SIGKILL → exit=-9 + wal **387312 字节非 0**，两路逐字节同值——wal==0 断言判别力双证非空洞恒真）；探针分仓 = lightamer-evidence 仓 `70774ad`（7 文件 326 行双路亲验——政策 B 第三实例）；M7-3 挂账收口面双路各自独立亲证 |
| **zh 对账** | xcstrings 三新键尾块纯插入（`mcp_tool_desc_copy_adjustments`/`_paste_adjustments`/`editor_history_author_badge`〔zh =「作者 %@」亲验〕）+ `mcp_tool_desc_list_luts` 原位值改（en+zh 同批——en defaultValue 住源码，M7-3 `3ef68910` 先例形）；zh-audit `--check` PASS（1698 source keys / 1946 catalog keys）+ `--self-test` PASS 双路亲跑；UserDefaults 零新键 |
| **验收形态偏差申报** | plan 预设 `dual_acceptance = true`；**omp 制度路由双 zcode 独立眼替代**（M6-2..M6-5 先例——配额阻塞替代形态，晨审可裁）；偏差十条双路逐条独立裁决全认（§SC/AC 表 + DECISIONS §2/§3），最重项 runner 中央 env 门 = **合理扩展非越权**（测试基建一行 additive + in-process 直调 startHTTPHost 面〔McpHostTests 7+/McpRenderParity/McpFinalSnapshot 共 9+ 调用点〕确实漏盖 plan F14 spawn 面 + DECISIONS 申报在案；后续再触碰该文件建议每次 DECISIONS 单独申报）；夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻） |

## SC/AC 三列证据（ROADMAP §M7-4 三验收形态 ↔ 双路对表）

| # | 验收形态 | 第一路证据 | 第二路证据 | 判定 |
|---|---|---|---|---|
| 1 | **跨图批量 parity golden ✓**（对齐 GUI 排除面单源 `isAdjustmentTransferable`） | §三：Catalog 恒等单源亲核（`AdjustmentTransferCatalog` 纯 helper verbatim 抽取，GUI model 委托零 diff，`isAdjustmentTransferable` 恰 1 定义，mask contentRevision 重置单处）+ 恒等 golden 四层断言亲读（nodes/items/layerSnapshots/payload + 两 face mask 纪元重置）；paste ledger 全臂（targets ≤1000 + 重复项 invalidParams〔F10〕+ membership/live per-target 硬拒非 skip + probe 全调拒 + 无状态源重读 + `.overwrite` + label "MCP paste_adjustments" + `flushForTeardown` 写达后方返 + 固定 reason token 集〔F7〕+ 全拒批 appliedCount=0 诚实应答 + 空源 invalidParams〔偏差⑥〕） | 面 1：三段批事务语义全文走查（段1 compose per-target 分账正确 / 段2 index claim **ONE transaction for ALL targets**——claim 失败回滚零写段3 永不跑 / 段3 per-target 原子晋升 + dirty 行 heal leg 最终一致〔crash contract M6-09-04 既有〕）+ O4 golden 实质亲读非永真（磁盘真身 label/note/author 四落盘断言 + live 硬拒磁盘零触断言）+ **minor-3 新发现**（段3 drain 写失败不进应答——既有语义新暴露非本批引入，§挂账②） | **✓ 双路零分歧** |
| 2 | **note/author 面板显示走查 ✓** | §三：sidecar v11 镜像全链五件亲读（Keys 两 case + 存储两属性 + init 镜像携带 + decodeIfPresent/encodeIfPresent + `item` 重建两实参 + schemaVersionCurrent 10→11；除 carve-out 外 LightamerSidecar.swift 零触）+ SidecarV11Tests 五法 + get_history 真位翻转（position 真位式 + 越界守卫〔比 plan 字面多一层 bounds check 语义等价更稳〕+ 红尾腿 + pristine .null）+ author="mcp" 盖章 + GUI historyRow note 副标题（caption2 + lineLimit(1)）+ author 徽章（nil 无徽章 + AX label 键） | 面 2：V11 五法**非永真性独立判定**（①v10-form byte-exact = 真漂移守卫〔encode 注入 null/bump version 即红〕/ ③stamped round-trip 镜像四件缺一即死 / ④HistoryHash 隔离负测 ±note/author 真实造两档 / ⑤future-12 = CHECKER C1 守卫重正实质；②nil-face 键缺席面成立、字节差面弱于注释措辞——观察级注记非缺陷）+ 旧 v10 档升级链亲核（decode 不升级、app save 升 v11 = v8/v9/v10 先例链同构，:444 亲读）+ GUI 读面结构亲核（HistoryRowData.item 携全量）+ zh 亲验 | **✓ 双路零分歧** |
| 3 | **TOCTOU 负测（并发建文件不被覆盖）✓** | §四：产线缝亲核（encodeStage 恰尾追 `exclusiveFinalWrite` additive 缺省零 diff / 同目录隐藏 tmp `.<name>.<uuid>.tmp` / link() EEXIST → `BaseNameOccupiedError` 复用〔错误表零新增〕/ encoder-error 清理腿改道〔F4 exclusive 臂不触 destination〕/ gain-map 臂同 wrap / `$jobNamingCarrier` encode 腿 wrapper〔ExportQueueContract 零 diff〕/ render 步快照门 :620-645 零触亲验）+ 五腿全在位（①TOCTOU 负测 typed 错+植入字节不变+glob 零残留 ②正向恒等 byte-equal ③.replace 负面守卫 ④.increment 既有 E2E face ⑤encoder 失败腿）Export 385/5/0 亲证绿 | 面 3：**MPF 偏移容器交互结构亲证安全**（gain-map 编码器 rewrap 在 encoder 内部 promotion **之前**完成 :165-168 亲读 / promoteExclusive 内容中性 promotion 链零字节修改 / ICC strip+XMP mount 对 gain-map 结构性不可达 :95-97 / MPF 面测试四法亲证绿）+ exFAT EOPNOTSUPP 行为面亲读正确（非 EEXIST → encodeFailed 兜底）+ **观察项 A** 卷归类勘误（/Volumes/UNITEK 实测 Case-sensitive APFS + link() 探针 exit 0——本工作区 .fail 档实际可用，利好非缺陷）+ 可选腿未行使注记（观察项 B） | **✓ 双路零分歧** |

**REQUIREMENTS 对账**：MCP2-08..09 + UQ-A2 Delivered——双路 §SC 表亲核 ✓；**M7-3 挂账单一清单①②③⑤⑥ 全收口**（双路亲证）：①S1 = poll 体三点改形亲核（`events: Int16(POLLIN)` / `poll(&fds, 1, 250)` / revents 分流 HUP→break 四语义零改〔once guard / M1 自守卫 / close+exit(0) 体 / 两调用点 mode 传参〕）+ e2e 0.87s/wal==0；②S2 = A+C 落地（`warmLutLibrary` 恰 1 定义 + env 门 + 四装配点〔只读 http/stdio/http/GUI〕+ `Task.detached(.utility)` + list_luts 描述文案）+ 测试语境双缝禁用（fixture 注入 + runner 中央 export）；③S3 = 正臂腿三 clause 断言亲核（before==nil :532 / after!=nil :543 / store 未变 :546-548 + heldTargets 非空传参）；⑤match_color = provider 目录锚第三实例（`deletingLastPathComponent()` 一行 + 两测试 provider 同形 + kind0 锚腿新法）；⑥三处措辞校订完备性（M7-3 签核文档零回改 + 校订正本 DECISIONS §2.10 + AGENTS 修后终形 + 全源无活性残留）；挂账④ 无动作维持。FIX2③ controller 零 diff 第三波维持（双路亲验）。

## nyquist 判定

**`nyquist_compliant: true`**——采样密度充分性四依据：①**双路切入路径刻意错开**（第一路重全套独立复跑〔全新 build-for-testing 自证新鲜度〕+ S1 poll 体逐行深审 + UQ-A2 产线缝逐 hunk + 偏差十条裁决 + union 全点位；第二路重五面审计〔paste 三段事务语义 / V11 非永真性+升级链 / MPF 偏移容器交互+卷实测 / e2e 实质+自建 kill 探针 / 偏差独立复核+行号勘正〕+ 符号亲证产物新鲜度）→ 盲区结构性不重叠，第二路 minor-3/观察项 A/B 为增量非推翻；②**三方全套同值**（执行批 + 双路独立复跑跨三时窗，3925/35/0 逐 bundle 稳定、skip 35 零漂移）→ 基线无漂移；③**端到端双通道独立**（两路各自独立 spawn 真产线二进制跑真断连 + kill 对照两路**自建探针**逐字节同值 387312 字节）→ S1 修复判别力不在单通道假绿、kill 形对照非转抄；④**登记发现全部非阻断且带处置路由**（§挂账单一清单五项），偏差十条双路独立同判（含最重项 runner env 门「合理扩展非越权」双路各自独立论证），无未申报实质偏差。

## 双眼记录

| 眼 | 载体 | 范围 | 结论 |
|---|---|---|---|
| **眼一：第一路独立验收** | `M7-4-01-ACCEPTANCE.md` | 全套独立复跑（2076s，全新 build-for-testing 自证新鲜度）+ S1 修复深审（poll 体三点改形 + 四语义零改 + F2 真机理亲验 + 探针分仓亲验）+ T3 O4 深审（Catalog 单源/paste ledger 全臂/v11 五件/get_history 真位）+ T4 UQ-A2 五腿 + T5/T6 对账 + 偏差十条逐条裁决 + 红线族亲跑 + commit 清单核对 | **PASS / 0 error + 2 minor（minor-1 五处过时计数注释〔hygiene，M7-3 H1 家族注释误导面〕+ minor-2 strerror clobber〔robustness 观察，macOS 当前未触发〕，均 open 非阻断）** |
| **眼二：第二路独立验收** | `M7-4-01-ACCEPTANCE-2ND.md` | 全套独立复跑（2058s，符号亲证产物新鲜度）+ 五面审计（切入刻意错开）+ kill 对照自建探针 + 卷实测（diskutil = Case-sensitive APFS）+ 偏差十条独立复核 + 第一路 2 minor 独立复核（成立维持 + 行号勘正） | **PASS / 0 error + 3 minor（第一路 2 open 复核成立 + 本路新 minor-3 paste 段3 drain 应答面〔open〕）+ 观察项 A/B；与第一路无分歧** |
| **裁断** | 双路 **零实质分歧**（全套数字 / S1 修复机理 / kill 对照同值 / v11 面 / UQ-A2 五腿 / 偏差十条 / 第一路 2 minor 均独立到达同一结论；minor-3/观察项 A/B = 第二路独有角度的增量发现非矛盾） | —— | 本 VALIDATION 即裁断落账载体；omp 制度路由双 zcode 独立眼替代（先例沿用），晨审可裁 |

## 端到端证据面（协议级，非套件转述）

1. **S1 graceful 断连（双路独立）**：真产线二进制 `--mcp-stdio` spawn → initialize → `project_create`（arm watcher）→ 关 stdin（真 EOF 面）→ **0.87s exit(0)**（门 ≤12s；修复前此形 ≥12s 不退持锁——M7-3 双路三层复现在案）+ `.lalb-wal` 存在且 **size==0**（close 强制 TRUNCATE checkpoint 兑现）；锁语义侧写 = 退出前第二 `project_open` typed `projectHeldByOther`（同测试内确定性形——偏差⑨裁定成立）。
2. **kill 形对照判别力（双路独立同值）**：同一产线宿主 spawn → project_create → SIGKILL → exit=-9，`.lalb-wal` = **387312 字节（非 0）**——第一路与第二路各自自建探针实测逐字节同值；graceful 形 wal==0 / kill 形 387KB，**wal==0 断言确为 graceful 正面证据非空洞恒真**。
3. **S2 预热机制面**：`warmLutLibrary` 恰 1 定义 + `LIGHTAMER_SKIP_LUT_PREHEAT` env 门 + 四装配点（startReadOnlyHTTPHost / startHeadlessStdioHost / startHTTPHost / LightamerApp GUI 装配段）+ `Task.detached(priority: .utility)`；测试语境禁用双缝（仲裁 fixture spawn env 注入 + test-direct.sh 中央 export——in-process startHTTPHost 直调面补盖）；App 轮 370-379s 无 50s 停滞 = 预热旁路生效面佐证；**冷窗数字维持 M7-3 正本 50.2s 本波未重测**（偏差⑦如实申报——env 门使然非静默；预热后改善实测待补，§挂账④）。
4. **union 29 工具面**：T6 全点位显式改（冻结表 +2 行 verbatim + apply_params note 行两层同批 + 计数 ×4 全 29 + destructive 集 10 元素 + descriptionKeys +2 + all29 + 测试名 Union29Verbatim + 头注 + message）+ **union 外五钉 21→23**（算术钉 = editing 9 + culling 14 = 23——M7-3 H1 家族防复发形）+ 残漏 grep 双路独立零命中（`count, 21` / `count == 21` / `all27` / `Union27` 测试面零命中）。

## 挂账单一清单（五项，正本 = 本节；STATE/GOAL-STATE/TODO/ROADMAP/AGENTS 同批翻账）

| # | 项 | 形态 | 触发/动作 |
|---|---|---|---|
| ① | **minor-1 五处过时计数注释 + minor-2 strerror clobber**（minor-1 = `McpFinalSnapshotTests.swift` :263/:268〔"exactly these 27 descriptors"/"27 is"，两行号以第二路勘正为准〕+ `McpHostTests.swift` :466/:668〔"21-tool face"〕+ `McpSearchStateToolsetTests.swift` :16/:265〔"count rides 21"〕——可执行断言全正确、union 29/五钉 23 亲跑绿，注释矛盾面 = M7-3 H1 家族注释误导面；minor-2 = `ExportRenderer.promoteExclusive` 中 `strerror(errno)` 求值先于 `errno == EEXIST` 判读——POSIX 不保证 strerror 保全 errno，理论上 typed EEXIST 面可被 clobber 降级 encodeFailed〔防覆盖语义不损，macOS 当前实现未触发〕） | minor ×2（open，hygiene/robustness 观察，非阻断） | **M7-5 顺路清**（M7-5 持 union 快照改动权波——过时注释正骑 21/27 计数面，显式改同批顺手清零成本）；minor-2 一行重整（errno 先存 local 再 strerror）随下一 Export 波顺路；均勿在本波范围外自行展开 |
| ② | **minor-3 paste 段3 drain 写失败不进应答**（`outcome.appliedRelPaths` 在 ENQUEUE 后即全量填充〔文档注释自认语义 = "composed + claimed"〕，`flushForTeardown` 的 drain 写失败仅 log——MCP paste 应答在 drain 失败路径仍报 `applied`，「写达后方返」契约对 agent 单步视角失真〔heal leg 下次 open 最终一致，但单步不可见〕；**非本批引入**——apply_params M7-3 同姿势、段3 语义 = M6-09-04 writer 既有设计；MCP per-target ledger 把语义缝隙新暴露到 agent 可见面） | minor（open，honesty/robustness 观察，非阻断） | **UPSTREAM-QUEUE 挂账 OBS-M7-4-5**（本批已入队，随 OBS-M7-4-1..4 同节）——MCP 后续波诚实化（applied 语义诚实化〔改名/注记 composed+claimed〕或 drain 失败回传 failedRelPaths），勿顺手修；触发 = MCP 后续波 touching paste/apply 写应答面 |
| ③ | **观察项 A exFAT 申报卷归类勘误**（DECISIONS §3 exFAT 行为变化申报中「含本工作区所在 /Volumes/UNITEK 类外置卷」对本卷不实——`diskutil` 实测 **Case-sensitive APFS** + 同目录 `link()` 探针 exit 0（link count 2）→ 本工作区 `.fail` 档终写原子面**实际可用**（利好非缺陷）；EOPNOTSUPP → encodeFailed 兜底行为申报本身正确） | 申报文字勘误（非行为缺陷） | **下次文档触碰随批勘正卷归类例子**（DECISIONS §3 该句 + 同源申报面）；UPSTREAM-QUEUE EOPNOTSUPP 降级 plain rename 可选项维持挂账勿静默 |
| ④ | **S2 首调延迟改善实测数据待补**（预热机制 A+C 已落地且旁路生效面有佐证〔App 轮 370-379s 无停滞〕，但预热后 stdio 臂 `list_luts` 首调实测值本波未采——env 门使冷窗未重测，偏差⑦如实申报；冷窗正本维持 M7-3 50.2s） | 数据缺口（非缺陷） | **M7-5 走查顺路补实测值**（预热环境 stdio 首调 `list_luts` 计时——与 M7-3 50.2s 正本同法可对照） |
| ⑤ | **FIX2③ 第三波维持注记**（`LibraryProjectController` 零 diff 连续第三波双路亲验——M7-4 不承载；OQ-1 GUI 臂行使且触文件才顺手的裁定维持） | 维持注记 | 注记延续至 M7-5；行使须显式申报（修法落点 = controller 尾部，无头设计不触） |

## 特殊事项

1. **S1 修复 = M7-3 挂账①首项兑现，修复形 = M7-3 验收方建议形态**：poll POLLIN 请求 + 250ms bounded re-poll + revents 分流（HUP/ERR → close+exit(0) 四语义零改；count==0 超时臂零 sleep；纯 POLLIN 臂清位 + `Task.sleep(250ms)`）——修订批 F2 真机理落笔：超时只封阻塞相，**sleep 臂才是速率限制本体**（恒可读 fd 上 4Hz .utility 帽；真管道 HUP 到达走 HUP 分支不经 sleep 臂，12s 活性窗无扰）；e2e 回归用例 = 双路探针/harness 改造源（`/tmp/m73_probe` 迁 evidence 分仓 `70774ad`，M7-3 挂账①预嘱兑现）；修后 stdio 优雅面成真（M7-3 挂账⑥/H3③/特殊事项 5 三处措辞校订正本 = DECISIONS §2.10，M7-3 签核文档零回改）。
2. **runner 中央 env 门（偏差③）双路同判「合理扩展非越权」**：`Scripts/test-direct.sh` 顶部一行 `export LIGHTAMER_SKIP_LUT_PREHEAT=1`——测试基建非产线码，产线 env 门行为不变；in-process 直调 `startHTTPHost` 九+调用点确实漏盖 plan F14 spawn 面（会触真实 LUT 根 seeding + ~50s 预热）；T1 fixture 显式注入行保留 = 双防线非互斥；该文件后续如再被触碰建议每次 DECISIONS 单独申报（第一路留痕在案）。
3. **union 改动权行使合规 + 移交维持**：本波 27→29 显式改全点位零意外 diff（双路亲核 + 残漏 grep 零命中）；**改动权用讫移交 M7-5**（`McpFinalSnapshotTests.swift` 显式改，串行禁并行注记延续——M7-5 持权 M7-6 禁并行，orchestrator 编排保证）。
4. **evidence 分仓政策 B 第三实例**：主仓 gitignore evidence 路径，`/tmp/m73_probe` 探针源随 lightamer-evidence 仓 `70774ad`（probe.c/harness.c+sh/e2edrv*.c/e2e.sh 七件 326 行，双路亲验盘上+git 面在位）；关键数值全部内联双 ACCEPTANCE 与本文件。
5. **产物新鲜度双通道自证**：第一路全新 build-for-testing 重构自证（执行方产物 mtime 08:44 早于 T6 commit 08:51 的时序疑点消解，不构成缺陷）+ 第二路二进制符号亲证（`paste_adjustments` ×9 / `SidecarV11Tests` ×4 内嵌串在位）——两路方法互不相倚同判。
6. **夜间全自动授权在案**（先例 D-07-3-T5-1，晨审可推翻）：执行批、双路验收、本签核批均夜间无人批窗内完成；本文件即晨审入口。

## 留痕

- 签核正本 = 本文件；验收正本 = `M7-4-01-ACCEPTANCE.md` + `M7-4-01-ACCEPTANCE-2ND.md`（双份随本批入库）；执行正本 = `M7-4-01-{SUMMARY,DECISIONS}.md` + `M7-4-CONTEXT.md`（D-M7-4-1..10）+ `M7-4-01-{PLAN,PLAN-REVIEW}.md` + `M7-4-CHECKER.md` + `M7-4-RESEARCH.md`。
- 端到端探针 = /tmp 即弃域 + lightamer-evidence 分仓 `70774ad`（七件在位；关键数值全部内联双 ACCEPTANCE 与本文件 §端到端证据面）。
- 执行链 = `49fab645..df0928f4`（7 commits，未 push；前置 plan 修订批 `0b34d199..7d595abc` docs）；本 VALIDATION = doc-only commit；不 push。
