---
phase: M7-3（MCP O2 反馈回路 + O3 项目与版本——MCP2-04..07）
slug: m7-3-mcp-o2o3
status: validated
nyquist_compliant: true
created: 2026-10-17
validated: 2026-10-17
batch_form: dual-acceptance closeout（执行批 ΔN +28 已入库；本签核批 doc-only）
---

# Phase M7-3（MCP O2 反馈回路 + O3 项目与版本）— Validation（双路独立验收 PASS 签核——render_preview 反馈闭环 + 第四域 project 工具交付）

> 体例对齐 `phases/m7-2-mcp-o1/M7-2-VALIDATION.md`（正本链上溯
> `phases/m7-1-shell/M7-1-VALIDATION.md` → `phases/fix2-defects/FIX2-VALIDATION.md`）。
> 执行链 `c6019122..7694e7b1`（6 commits = T1 顺路件六项 → T2 pristineOnly+region
> → T3 compare 双臂+list_luts → T4 ProjectToolset+运行时缝 → T5 union 23→27 →
> T6 收口翻账）；双路独立验收 = 第一路 `M7-3-01-ACCEPTANCE.md`（切入 = pristineOnly
> 深审 + 仲裁 fixture 对账 + 真 stdio 端到端）+ 第二路 `M7-3-01-ACCEPTANCE-2ND.md`
> （切入刻意错开 = 五面审计 + 真产线二进制 E2E 三轮 + S1 三层独立复现 + S2 冷延迟
> 量化 + 正臂覆盖审计）——**PASS / 0 error 零实质分歧**（S1 = M6-1 `1f981f9b`
> 潜伏缺陷双路独立确认，三层复现同判；S2/S3 = 第二路增量发现非矛盾；O1/O2 双路
> 确认属实）；**三路全套同值 `TOTAL|3905/35/0|`**（执行批 + 双路独立复跑，exit 0
> 零 MEMFAIL，七 bundle 全 8G 门内；= 3877 基线 + ΔN 28 精确闭合；ΔN 预估带
> +12..20，**超带 +8 如实申报正当**——构成逐条可追溯评审处方/SC 强制腿）。omp
> 制度路由双 zcode 独立眼替代（M6-2..M6-5 先例，晨审可裁）；夜间全自动授权在案
> （先例 D-07-3-T5-1，晨审可推翻）。端到端证据面 = 真 MCP stdio 27 工具 +
> project_create 四键无 photo_count + A→B 自持切换锚随盒进程级亲证 + S1 产线
> 二进制断连复现（sample 卡 poll :398）。裁定正本 = `M7-3-CONTEXT.md`
> （D-M7-3-1..10 零重开）+ `M7-3-01-DECISIONS.md`（§1 union 显式改申报 + §2 偏离
> 族 + §3 执行期裁定 + §4 顺路件收口）+ 双 ACCEPTANCE；数字正本 = 本文件。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Batch form** | 执行批 T1→T6（`c6019122` T1 M7-2 顺路件六项〔F-AC-1 两法/F-AC-2 透传/N2-1 十三键/N2-3 typed 抛/N2-4 四案/⑥ 句〕→ `cf49c046` T2 pristineOnly+region〔Core 唯一新触点恰两处〕→ `3ef68910` T3 compare 双臂+list_luts+xcstrings → `bb6026f1` T4 ProjectToolset+盒+锚+EOF 双保险 → `286530d2` T5 测试批 union 23→27+四域 golden → `7694e7b1` T6 收口翻账 docs-only）→ 双路验收 → 本签核批（doc-only） |
| **Full suite（三路同值）** | 执行批（峰 IOPParity 7786MB）/ 第一路（2026-10-17 04:25 起，2044s）/ 第二路（第二轮，2129s——首轮 IOPParity 中段被验收方自身误杀〔§挂账④〕，留证后干净重跑闭合同值）三路独立跑 `caffeinate -dis Scripts/test-direct.sh --all` 均 **`TOTAL\|3905/35/0\|` exit 0 零 MEMFAIL**；七 bundle 逐值稳定：IOP 687/5/0（RSS 7594/7642MB ±3% 带内）/ IOPParity 460/3/0（6986/7008/7786MB——已知贴线 bundle，三路全 8G 门内）/ Layers 494/5/0 / Library 731/4/0 / Sessions 284/9/0 / Export 381/5/0 / App 868/4/0；skip 35 构成 = 5+3+5+4+9+5+4，全部既有 env/perf-probe 门，零静默吸收；L055 机检双路亲跑零命中 |
| **ΔN 记账** | **ΔN = +28**（T1 = Library +2〔FilterSQL 两法〕+ App +2〔F-AC-2 真值断言 + N2-3 负测〕/ T2 = Export +2〔pristineOnly 恒等负测两法〕/ T5 = App +22〔McpProjectToolsetTests 17 法 + McpEditingToolsetTests additive 5 法〕；双路亲数对账）；对账链 3877 基线 + 28 = 3905 **精确闭合**；**超带 +8 正当性**：预估带 +12..20 为 research §0.5 预估、plan 明文「越带如实申报」——超带构成 = 评审修订批显式增腿（H2 锚腿/H4③ 两腿/M1 门控腿，CHECKER 门 5 亲核在 plan 文）+ SC 强制腿（域快照 verbatim/注解 executable/白名单负测/盒空负测/仲裁 fixture 每腿一法），无凑数测试，第一路逐条亲核裁决正当 |
| **红线族机检** | 双路独立电池全 PASS：零新 SPM（Project.swift 恰一行测试登记）／`.metal` 全域零 diff／**封存面零触**（Core+IOP 链内 diff = 恰 `QuickLookRenderer.swift` 一文件——第二路 `git diff 2e530f8e..7694e7b1 --name-only` 亲证）／McpToolRegistry.swift 零 diff（错误码 16 档封闭表零新增）／McpTimeouts 零 diff（零新档）／controller + LibraryProjectController + SingleWriterLock 零 diff／xcstrings = 4 新键尾块纯插入 + render_preview 恰 1 行原位值改／UserDefaults 零新键／`runModal` 零命中 + LocalizationValue 插值禁形零新增／Project.swift + BUNDLE-MAP 各恰一行 + tuist generate 恒末位／V50Order/GradeCatalog 零触 |
| **端到端证据** | 真 MCP 宿主协议级抽测双路独立：第一路独立脚本 stdio 全链亲调（tools/list 27 + project_create 实调四键 + pristine 投影 + A→B 锚随盒进程级实证）+ 第二路真产线二进制 E2E 三轮（tools/list 27 + 四键 + get_state 即时反映 + M1 in-process 亲跑）+ S1 断连真复现（§端到端证据面 3）；/tmp 探针即弃（关键数值内联双 ACCEPTANCE） |
| **zh 对账** | xcstrings 四新键（`mcp_tool_desc_list_luts`/`_project_open`/`_project_create`/`_list_versions`）尾块纯插入 zh-only 形 + `mcp_tool_desc_render_preview` 原位值改（恰 1 删除行）；zh-audit `--check` PASS（1695 source keys）+ `--self-test` PASS 双路亲跑；UserDefaults 零新键 |
| **验收形态偏差申报** | plan 预设 `dual_acceptance = true`；**omp 制度路由双 zcode 独立眼替代**（M6-2..M6-5 先例——配额阻塞替代形态，晨审可裁）；偏差 1-8 + 执行期新增 3.1-3.7 双路逐项独立裁决全认（§SC/AC 表 + DECISIONS §2/§3），均为 additive 一致延伸非重开；夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻） |

## SC/AC 三列证据（ROADMAP §M7-3 三验收形态 ↔ 双路对表）

| # | 验收形态 | 第一路证据 | 第二路证据 | 判定 |
|---|---|---|---|---|
| 1 | **compare/region golden ✓**（T5 四法 + T2 两负测） | §二 pristineOnly 深审：Core 触点恰两 hunks（签名尾部默认参 + :243 条件化，`grep -c pristineOnly` = 2）；9 调用点/5 文件零 diff 亲核；两 byte-equal 负测实质亲核（sidecar fixture 真参与，非链真恒等）；region 校验链亲测——x+w==1.0 精确臂 800×600 全帧不缩 / 亚像素 0.0005 臂 → invalidParams 携归一化值 / 越界两臂 typed 拒 / schema 恰 +region | 面 1：`git diff --name-only -- LightamerCore/Sources LightamerIOP/Sources` = **恰此一文件**（封存面最强形态）；两负测实质亲核 + golden 手算帧亲跑；compare 双臂同一 boundedWait 闭包两遍各自 decode（「不共享 decode」红线亲证）；进程级 E2E 无头臂 typed `notSessionMember`（session 域工具诚实臂）+ 真渲染面由全套轮 Metal golden 承载 | **✓ 双路零分歧** |
| 2 | **project 工具与单写者锁仲裁 fixture ✓** | §三/§四：in-process 双 store 真 flock held 形（携真 pid）17 法亲跑全绿——held→typed projectReadOnly/释放恢复/自持切换/H2 锚随盒 executable/M1 http 不 arm eofArmDone 恒 false/create 三拒/writer gate/盒空 null 面；**进程级实证**：A 持 seeded row → open B → `list_versions(1)` = "id 1 is not a row of the open library"——锚确随盒；controller/registry/LibraryProjectController 零 diff 亲核 + 生产调用点五处全传 provider（裸 context 零命中） | 面 2/面 3：锁仲裁 fixture 实质亲核（真 flock + 真 pid + 17 法全有可机检断言）+ **真产线二进制 E2E 三轮**（tools/list 27 / project_create 四键 photo_count 缺席 / get_state 即时反映盒真值 / M1 臂 http 不 arm in-process 亲跑）；零 diff 面独立亲证 + EmbeddedState 第五缝（off→on toggle 不静默缺席）；list_versions golden 族（byte-equal + 500 帽 + 双地址臂）亲核 | **✓ 双路零分歧**——仲裁面三层覆盖（in-process golden + 进程级锚随盒 + 真二进制 E2E） |
| 3 | **快照族零意外 diff ✓**（union 27 全点位显式改） | §五：27 全点位亲核（schema 行/list_luts 行/projectTools 三行/all27 定义+引用/计数 ×4/组合代数/disjoint +3/descriptionKeys +4/makeUnionRegistry+SC7 传 fixture）+ 五计数钉 20→21 亲点 + 残漏 grep 亲跑零命中（`count, 20` 仅 SentinelTests 2000-buffer 清白旁证）+ 红窗纪律亲核（cf49c046/3ef68910/bb6026f1 零快照触碰）+ 测试序前复位纪律亲核 | 面 3：27 全点位独立亲核 + 残漏 grep 独立跑零命中 + 五钉亲点 + **`McpFinalSnapshotTests` 二进制内嵌串亲证**（`strings` 命中 "the final count is 27"/"no 28th tool"，23 面串零命中——build-for-testing 新鲜度免间接证明，第二路自建产物 05:29 晚于 T6 04:23） | **✓ 双路零分歧**——union 27 全点位兑现，串行波序注记保持 |

**REQUIREMENTS 对账**：MCP2-04..07 四行 ✅ Delivered（T6 批翻账，commit 指针在案）——双路 §SC 表亲核 ✓；M7-2 顺路件六项全清偿（§挂账⑤）。

## nyquist 判定

**`nyquist_compliant: true`**——采样密度充分性四依据：①**双路切入路径刻意错开**（第一路重 pristineOnly 触点深审 + 仲裁 fixture 逐法 + union 对账 + stdio 端到端；第二路重五面审计 + 真产线二进制 E2E 三轮 + S1 三层独立复现〔自写 C probe 非转抄〕+ S2 冷延迟量化 + GUI 谓词正臂覆盖审计）→ 盲区结构性不重叠，第二路 S2/S3 为增量非推翻；②**三路全套同值**（执行批 + 双路独立复跑，跨三个时窗，3905/35/0 逐 bundle 稳定 ±3% RSS 带）→ 基线无漂移；③**端到端双通道**（两路各自独立驱动真 stdio server + 第二路真产线二进制三轮 + S1 断连面产线级复现）→ project 工具面不在单通道假绿；④**S1 双路独立复现 + 归因三方一致**（各自最小 C 探针 + 产线二进制 + sample 栈 + `git log -S` 引入 commit 同指 `1f981f9b`）→ 显著发现可信且先前性钉死。登记发现（S1/S2 显著 + S3/O1/O2 minor）全部非阻断且带处置路由（§挂账单一清单），无未申报实质偏差。

## 双眼记录

| 眼 | 载体 | 范围 | 结论 |
|---|---|---|---|
| **眼一：第一路独立验收** | `M7-3-01-ACCEPTANCE.md` | 全套独立复跑（2044s）+ pristineOnly 深审（触点/调用点/负测/region 边界亲测）+ 四域深审（盒/锚/EOF 双保险/GUI 臂/零 diff 亲核）+ 真 stdio 端到端抽测 ①-⑥ + union 对账 + 偏差 1-8 + 3.1-3.7 逐项裁决 + ΔN +28 超带构成亲核 + 红线族亲跑 + commit 清单核对 | **PASS / 0 error + 3 minor（S1〔显著，M6-1 潜伏非本波违例〕/O1/O2）+ O3 info；独立发现含 S1 三判据亲测（events:0 ≥12s 不醒 / POLLIN 0.38s 醒 / revents 0x11）** |
| **眼二：第二路独立验收** | `M7-3-01-ACCEPTANCE-2ND.md` | 自建 build-for-testing 全套独立复跑（第二轮 2129s）+ 五面审计（错开切入：render_preview/四域/快照面/偏差族/S1 表态）+ 真产线二进制 E2E 三轮 + S1 三层独立复现（最小探针 20s 不醒 / POLLIN 2.001s 醒 0x11 / 产线 12s+ 不退 sample :398 + `git log -S` 归因 `1f981f9b`）+ S2 冷延迟量化（50.2s vs 10s 声明窗）+ S3 正臂覆盖审计 + 红线族独立电池 | **PASS / 0 error + 0 new-error；S1 成立三层复现无分歧 + S2/S3 新显著/minor 发现 + O1/O2 确认属实；事故自我申报 = 首轮误杀宿主后留证干净重跑闭合同值（§挂账④）** |
| **裁断** | 双路 **零实质分歧**（全套数字 / pristineOnly 触点 / 仲裁 fixture / 快照族 / 偏差族 / S1 归因与复现 / O1/O2 均独立到达同一结论；S2/S3 = 第二路独有角度的增量发现非矛盾） | —— | 本 VALIDATION 即裁断落账载体；omp 制度路由双 zcode 独立眼替代（先例沿用），晨审可裁 |

## 端到端证据面（协议级，非套件转述）

1. **stdio 27 工具（双路独立）**：真 server（第一路独立脚本 / 第二路真产线二进制 `--mcp-stdio`）→ initialize → `tools/list` = **27**（六关键工具在位）；`project_create` 实调 → 四键 summary `{path, name, readOnly, heldByOther}`，**photo_count 缺席**（D-M7-3-6 schema 自描述诚实面）；`get_state` 即时反映盒真值（path/readOnly/hostMode）；sqlite 种行 + Media 文件 → `list_versions(1)` = pristine 诚实面 `{image, activeVersionID: null, versions: []}` 非错误臂；`render_preview` 无头臂 = typed `notSessionMember`（session 域工具在无 session 宿主的诚实臂，真实渲染体由进程内真 Metal golden 覆盖）。
2. **A→B 自持切换锚随盒（进程级）**：A 持 seeded row → `project_open` B → `list_versions(1)` = "id 1 is not a row of the open library"——library projectDirectory 解析锚确随 current-project 盒（H2，fix `20997721` 同族第二实例关闭）；in-process executable 腿 `testSelfSwitchClosesThenOpensWithAnchorFollowing` 同批亲跑。
3. **S1 断连面真复现（双路三层）**：最小 C 探针（两路各自编写）——产线形 `poll(events: 0)` 唯一写者关闭后 ≥12s/20s 不醒（强杀收场）；同形改 `events: POLLIN` 0.38s/2.001s 醒，`revents = 0x11`（POLLIN\|POLLHUP）；真产线二进制复现——`--mcp-stdio` + runtime `project_create`（arm watcher）→ 关闭 stdin → 12s+ 进程不退出，`sample` 亲证卡 `McpServerController.swift:398` poll；归因三方一致 = 基线 `217999a5` :355 原体同形 + `git log -S "events: 0"` 引入 commit = `1f981f9b`（M6-1）——M7-3 抽取忠实保留字节非本波引入（§挂账①）。
4. **S2 冷延迟量化（第二路）**：真 stdio server 冷进程首调 `list_luts` → 应答 50.2s 后落盘（`McpTimeouts.list` 声明窗 10s）；sample 栈亲证线程在 `LutLibraryStore.shared` 首次 dispatch_once → `rescan()` → `CubeLutParser.parse` 内置 40 LUTs 纯 CPU 解析（非死锁，长解析；`withTimeout` v1 stuck-body 形无法救援）——agent 客户端短超时会误杀此调用（§挂账②）。

## 挂账单一清单（六项，正本 = 本节；STATE/GOAL-STATE/TODO/ROADMAP/AGENTS 同批翻账）

| # | 项 | 形态 | 触发/动作 |
|---|---|---|---|
| ① | **S1 stdio EOF watcher `poll(events: 0)` macOS 管道永不因写端关闭醒来**（「agent 断连 → checkpoint 优雅释放」面 M6-1 KD-4/OQ-7/D-M7-3-7 实际惰性；真实释放 = 进程退出 kernel 地板） | **显著；M6-1 `1f981f9b` 潜伏缺陷**（基线同形亲证 + M7-3 红线「启动路径逐字节不变」忠实兑现非本波违例——验收按「行为 = 基线」判 PASS） | **M7-4 修复批首项**：poll 改 POLLIN 请求 + 醒后按 `revents & POLLHUP` 分流（HUP → close+exit；纯 POLLIN → 清位续 poll 不消费字节——保「watches HUP without stealing bytes」原意图；http 臂 M1 自守卫语义不变）；**勿顺手修需独立裁决**；回归用例 = 双路探针/harness 脚本可复用（真二进制 + 真 EOF + 活性断言 12s 窗）；O2「checkpoint 优雅面仅 stdio」措辞同批校订 |
| ② | **S2 `list_luts` 进程级首调 50.2s**（`LutLibraryStore.shared` 冷 dispatch_once 全库解析超 `McpTimeouts.list` 10s 声明窗；`withTimeout` v1 stuck-body 形救援不了 CPU 型 body；测试面盲区 = golden 用 `replaceShared` 小 store 不触默认根；GUI 臂有预热、stdio agent 臂独吃冷成本） | **显著；本波新工具面 plan 级盲区**（实现 = plan T3 字面处方照办非实现偏离） | **M7-4 裁决三选一**（勿顺手修）：宿主启动后台预热 shared store / 解析协作化挂起 / description 明示首调代价；裁决前禁改既有档值（CONTEXT D-M7-2-3 红线延续） |
| ③ | **S3 GUI 差分谓词正臂零测试覆盖**（`before==nil ∧ after!=nil ∧ store 未变 → typed projectReadOnly` 仅窄竞态窗口可达；两 stub 腿均 `heldTargets: []`——生产面该 clause 是防御网，预检已拦确定性 held，不阻断） | minor（覆盖缺口非缺陷） | **M7-4 顺路补一腿**（`heldTargets` 非空 stub 腿即可，零产线代码）；O1 同形复制漂移风险可顺路评估抽 App 内可测 helper 消二份 |
| ④ | **第二路验收事故自我申报**（首轮全套 IOPParity 中段被验收方自身 E2E 探针清理 `kill -9` 误杀测试宿主——先杀后查违反 M2-7-3 parentage 纪律；log 留证 `/tmp/m73_accept2_all.log` + `/tmp/la-direct-tests-IOPParity.log` 后干净重跑，第二轮零进程干预逐 bundle 闭合同值；产物零缺陷） | 流程纪律（非产物缺陷，验收方自我申报在案） | **登记 + 纪律再提醒**：LESSONS 候选评估 = **已有同类条目，指针化不另立**——parentage 纪律正本 = AGENTS.md「M2-7 架构增量」节「测试宿主进程清理教训」（先核 `ps -o ppid`：测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd）；本事故 = 该教训第二次活体佐证（M2-7-3 首例），AGENTS phase-closed 行附注 |
| ⑤ | **M7-2 顺路件六项清偿确认**（T1 `c6019122` 闭环） | ✅ 全清偿：F-AC-1（FilterSQLTests 两法六断言 + keywords eq 第二法 + DECISIONS §2.9 收口段——「二选一」两路兑现）/ F-AC-2（probe 默认参透传 + get_state.control.lock 双臂真值断言）/ N2-1（pristine payload 12→13 键 truncated:false + golden 同 commit）/ N2-3（fulltext 闭包 typed 抛 + nil 载体负测）/ N2-4（requestFailed 臂——F-3 四案闭合）/ ⑥ cursor 边界承接句（DECISIONS §2.8）+ F-AC-4 注释非易碎形（§1.7） | 余项路由维持：M7-2 挂账④ CLIP 10s 贴线待万级库实测（超时才申报升档）；挂账⑤ match_color provider projectDirectory → **M7-4 顺路勘正**；N2-2 → M7-6 文档句 |
| ⑥ | **EOF http-absence 偏离 + 双臂不对称如实化** | 已钉（DECISIONS §2.1/§2.3 偏离族申报）：http 运行时开项目 = 进程退出 kernel 地板（checkpoint 优雅面仅 stdio——armStdioEOFReleaseOnce `mode == .stdio` 自守卫 M1 + 启动路径既有门）；两臂先关后开差异 = headless close-then-open 盒清空诚实态 vs GUI held 预检 + before/after 差分 + promoteRecent 不对称（D-M7-3-9） | **如实化注记维持**：偏离为显式申报面非缺陷；S1 修复批落定后 DECISIONS H3③ 措辞校订时同批复核本条（S1 使 stdio 优雅面当前亦惰性——修复批校订两处措辞一并处理） |

## 特殊事项

1. **S1 先前性钉死与本波红线兑现**：M7-3 对 M6-1 EOF watcher 的抽取 = **忠实字节保留**（基线 `217999a5` :355 原体 `events: 0` 同形）——「启动路径行为逐字节不变」红线被兑现，缺陷先前性由双路 `git log -S` 同指 `1f981f9b` 钉死；本波验收按「行为 = 基线」判 PASS，修复另立 M7-4 首项（验收方建议形态已入挂账①，需独立裁决勿顺手修）。
2. **S2 归因 = plan 盲区非实现偏离**：实现按 plan T3 字面处方（`McpTimeouts.list` 包裹 + `LutLibraryStore.shared` 直读）；测试盲区机制 = golden 用 `replaceShared` 注入小 store 不触默认根全库解析——修法三选一属裁决面（挂账②），本波不改。
3. **omp 制度路替代申报**：plan 预设双路验收；omp 制度路由双 zcode 独立眼替代（M6-2..M6-5 同款，晨审可裁）——双路切入路径刻意错开保证独立性（§nyquist 判定①）；第二路事故自我申报（挂账④）= 验收纪律透明面，重跑闭合同值消解产物疑虑。
4. **union 快照串行波序注记保持**：本波 union 改动权 23→27 已用讫；**M7-5 接棒时继续显式改 `McpFinalSnapshotTests.swift`，串行波序，禁并行派发**（orchestrator 编排保证；M7-4 无快照面改动预期，若有 additive 工具须先取权）。
5. **测试进程 stdin dup2 安全化与 S1 交互**：`McpProjectToolsetTests` setUpWithError 将 STDIN_FILENO dup2 /dev/null——套件内 arm 真 watcher 后 poll 永不 HUP不自噬；S1 使「真实 HUP 由 McpProjectArbitrationTests 承载」的 DECISIONS 句实际不准确（仲裁测试全 `child.terminate()`=SIGTERM 从未真跑 HUP）——该网当前 moot 但属正确防御性卫生，S1 修复后仍必要（挂账①修复批同批校订措辞）。
6. **夜间全自动授权在案**（先例 D-07-3-T5-1，晨审可推翻）：执行批、双路验收、本签核批均夜间无人批窗内完成；本文件即晨审入口。

## 留痕

- 签核正本 = 本文件；验收正本 = `M7-3-01-ACCEPTANCE.md` + `M7-3-01-ACCEPTANCE-2ND.md`（双份随本批入库）；执行正本 = `M7-3-01-{SUMMARY,DECISIONS}.md` + `M7-3-CONTEXT.md`（D-M7-3-1..10）+ `M7-3-01-{PLAN,PLAN-REVIEW}.md` + `M7-3-CHECKER.md` + `M7-3-RESEARCH.md`。
- 端到端探针 = /tmp 即弃域（双路各自 fixture 已清；第二路 S1 探针 `/tmp/m73_probe/` 脚本标注意为 M7-4 挂账①回归用例改造源——修复批取用时迁入仓内 evidence 面）；关键数值全部内联双 ACCEPTANCE 与本文件 §端到端证据面。
- 执行链 = `c6019122..7694e7b1`（6 commits，未 push；前置 plan 修订批 `e7d8151e..2e530f8e` docs）；本 VALIDATION = doc-only commit；不 push。
