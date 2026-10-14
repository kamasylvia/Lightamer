# M6-4-01 ACCEPTANCE — 图库 stacks + auto-stack（面 A 全量批）双重验收记录

> **PASS / 0 error + 0 minor open + 5 登记 minor + 6 观察项**（第一路 zcode 独立验收，
> 2026-10-14 夜；不 push。5 minor 均为登记级（实现面正确、缺的是断言/登记/清单
> 精度），不阻断 plan 02；清偿归属见各条。omp 二次验收按 `dual_acceptance=true`
> **串行**补位（严禁并发），其结论追加于本文件 §六。

## 结论头（第一路 zcode 独立验收）

- **判定：PASS**。执行链 `f30e83a3..6fa1f536`（T1-T8 八 commit）逐 commit 范围核对
  与申报一致；全套 `--all` 独立复跑 **`TOTAL|3815/24/0|2134s`，exit 0，零 MEMFAIL，
  零 crash**——与 SUMMARY 申报推算值逐位一致；AC1-8 全项 Delivered；
  D-01..D-12 偏差逐项裁决全准（三处登记缺口与本路发现见 §四/§五）。
- **验收方式**：不轻信执行方报告——五正本（PLAN/CONTEXT/CHECKER/SUMMARY/
  DECISIONS）全文亲读 + 八 commit 逐 hunk diff 亲核 + 六新测试文件 56 法逐条
  对表 + 红线机检电池九项亲跑 + zh-audit 独立复跑 + sqlite3 ESCAPE 语义独立
  探针 + 全套 7 bundle 独立 build+run（运行中 RSS 监视，峰值 IOP 7546MB /
  IOPParity 6988MB / Export 5356MB，8G 门内零 MEMFAIL）。

## 一、全套独立复跑对账（本路亲跑，非转引）

| bundle | 本路实测 | 申报 | 基线（M6-3 终验） | 漂移 |
|---|---|---|---|---|
| IOP | 686/1/0（peak 7546MB） | — | 686/1/0 | 0 |
| IOPParity | 460/3/0（peak 6988MB） | — | 460/3/0 | 0 |
| Layers | 474/4/0（peak 1173MB） | — | 474/4/0 | 0 |
| **Library** | **727/4/0**（peak 621MB） | 727/4/0 | 671/4/0 | **+56 恰合** |
| Sessions | 280/4/0（peak 1462MB） | — | 280/4/0 | 0 |
| Export | 378/4/0（peak 5356MB） | — | 378/4/0 | 0 |
| App | 810/4/0（peak 2832MB） | 810/4/0 | 810/4/0 | 0 |
| **TOTAL** | **3815/24/0 / 2134s** | 3815/24/0 | 3759/24/0 | **+56/0/0 精确** |

- 基线复算闭合：686+460+474+671+280+378+810 = 3759（七段亲加）；本批 LIB +56
  （六新文件 8+16+8+9+5+10 = 56，`func test` 计数亲点）∈ 计划带 52..58 顶沿。
- skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL skip 机械一致。
- 脚本尾行 `OK (direct launch, no testmanagerd)`；全程 caffeinate 包裹；测试宿主
  parentage = 脚本树（M2-7-3 教训纪律遵守，未误杀）。
- IOP peakRSS 7546MB = 8G 门的 92%（AGENTS 在案贴线族，MEMFAIL 机检未触发）——
  运行门语义内，无动作。

## 二、AC 逐条核验表

| AC | 内容 | 判定 | 本路证据（亲核，非转引） |
|---|---|---|---|
| AC1 | schema v5 两新表 + UNIQUE additive 迁移 + 冻结面零变 + 封面 = position 0 | **Delivered** | LibrarySchema.swift diff 逐节核对：DDL 与 KD-1 原式逐字节（WITHOUT ROWID + 双 CASCADE + PK (stack_id,image_id)）；`schemaVersion = 5`；迁移槽 `from <= 4 && to >= 5` 三条 `CREATE IF NOT EXISTS`（幂等四代）；`apply()` fresh-create 追加（出生面）；`indexNames` 恰一行追加、`triggerNames`/`reservedTableNames`/`imagesColumns` 等冻结数组 diff 零命中（仅文档文字）；`stacksColumns`/`stackContentColumns` 冻结面新立；V5Tests ①..⑧ 全过（v4 fixture 经**真迁移槽 1→4** 构建 = 诚实 fixture；快照轮换 `pre-migrate.4-5.bak` 亲证；幂等双跑零重复；全腿 1→5；futureSchema 6 typed 拒 + 文件零写；UNIQUE 负测；CASCADE） |
| AC2 | CRUD op 族全量 + 一图一栈 DB 级 + CASCADE 余 <2 同事务解散 + modified_time | **Delivered** | LibraryStore diff 亲读：createStack/group/stackWith/setTop/moveInStack/splitStack/ungroup/removeFromStacks/setCollapsed/setAllCollapsed/stacks()/stackContaining/members 全单事务（withWriteBatch）；group/stackWith 整栈并组（unionMembers 序保全）+ <2 typed no-op（先 guard 后删除 = 零半写）；removeImage sweep 与删除同事务；StackStoreTests 16 法全过（S6 封面切点 no-op 保 id、越界 clamp、真钟 20ms stamp 抽查、rowid 复用下以成员集断言身份） |
| AC3 | 聚类 golden + gap 边界 + runs≥2 + 双 skip + preview 零写 + commit collapsed + 60s 缺省 | **Delivered** | StackClustering 纯函数亲读（stable 排序 capture ASC + tie id ASC；≤gap 归簇；runs≥2；nil-capture 双重防御）；`defaultGapSeconds = 60`；ClusteringTests 8 法全过——preview 零写用**整包 clean-close 前后字节恒等**钉死（强形态）；边界（==60 归簇 / +0.001 断开 / 链式合并）+ 乱序/同 capture 排列不变确定性 + 已堆叠/无 capture 双 skip（store 腿 + 纯函数腿各一） |
| AC4 | collapsed 谓词双腿 + `.flat` 字节恒等双证据 + fixup 三件套 + union golden + 两偏离登记 | **Delivered** | 谓词插点 = runPage 装配处恰一行 conjunct（appendFilterLeg 后、nullTail/anchor 腿前）；`stackMode` 缺省参 `.flat` = 七个生产调用点全部缺省（grep 清单见 §四 M-d 勘误）；行级恒等测试（无参 vs 显式 .flat 跨双段逐行恒等）+ nullTail 腿谓词 + 混合收起/展开面；fixup 三件套：无重复（displayed 集合 + 两测）/**无丢失**（union golden 双测——T4⑨ 与 T6③，fixture 封面与成员**分处不同页**〔cover r09 首页 / 成员 r01+r05 后页〕满足 checker 关注点 3）/**幂等有界**（displayed-set 结构性 + 纯函数层 forward-only 守卫测；模型级显式重复 load 断言缺 = O-iv 观察）；D-05 forward-only + D-06 无顶替/口径分裂登记亲核在案 |
| AC5 | merge 三 kind 检测 + stackWith collapsed 成栈（真导入流）+ 源缺 skip 计数 + Outcome 零漂移 | **Delivered** | ImportService diff 亲读：白名单恰三值（`hdr-merge`/`hdr-merge-mertens`/`pano-merge`，ProvenanceReplay :40-49 rawValue 逐拼写核对；focus-stack 排除）；匹配四步序（后缀主式 → folderName 消歧 → folderName/stem 兜底 → 整组 skip）与 D-07 逐条一致；`mergeStacksCreated/Skipped` additive 双计数显式默认值（既有构造点零 diff，负测断言在册）；ImportMergeStackTests 5 法全走**真 importFolder**（真盘 session 树 + 真 .lra 落盘，禁手拼 image_path 遵守）：规范流（product = cover + collapsed + `Media/Burst/HDR/DSC00001-hdr.tif` 形状 spot-pin）/ 细则表四臂（后缀歧义 folderName 消歧 / 前批全库回落 / stem 唯一兜底 / stem 撞名整组 skip 零半栈）/ Mertens+pano / 源缺 skip / 零触 + 零漂移 |
| AC6 | UI 面 + 13 键尾块纯插入 + zh-audit 零 MISSING | **Delivered** | 徽章 overlay（计数 + chevron + `%lld` AX label）/ contextMenu 五项条件可见性（成组 ≥2 门 + 封面项 position≠0 门）/ AutoStackDialog（gap stepper 2..600 步 2 初值 60 + preview 随 gap 重查**零写** + Start 禁用门 + `.sheet` 缝）/ View 菜单「堆叠」节（静态项零 MenuCommandID 零快捷键 + pendingStackCommand 载体 no-op 守卫）；xcstrings diff 221 行纯插入（唯一 `-` 行 = diff 头，历史键字节/顺序零触碰）+ **13 键逐名在册**（两格式键 `%lld` 后缀 = focus_stack 先例同形，zh/en 双语值齐）；`zh-audit --check` 本路独立复跑 **PASS（1677/1918/zh complete）**；`grep -rn "\.runModal(" App/Sources` = 0 |
| AC7 | 零回归门（冻结面/MCP/sidecar/V50Order/.metal/UserDefaults/dependencies/既有族除指名外原样绿） | **Delivered** | 机检电池亲跑九项全绿（§三）；七 bundle 中六 bundle 逐位零漂移（仅 LIB +56）；既有 SchemaTests/DefaultLookTests/ProjectLockTests/LibraryDocumentTests 全绿（D-09 九处全为机械代际前滚，§四逐处核）；MCP 快照族/`LightamerSidecar.swift`/V50Order/`.metal` diff 零命中 |
| AC8 | SC 数字门 LIB +56 / APP +0 / 全套 3811..3817 | **Delivered** | 本路实测 56/0 + TOTAL 3815/24/0（带内中心，与 SUMMARY 申报推算值逐位一致）；02 plan 的 S8 重算基线 = 3815 申报成立 |

## 三、红线机检电池（本路亲跑）

1. 冻结面数组（imagesColumns/albumsColumns/albumContentColumns/versionRefColumns/
   reservedTableNames/triggerNames）diff 零命中（命中全为 PLAN/CHECKER/SUMMARY/
   DECISIONS 文档文字）✓
2. `indexNames` 恰一行追加（`"idx_stack_content_image",`）✓
3. `.metal` 全域 diff 零命中 ✓
4. `Project.swift` diff = 恰六行测试文件登记（LIB 数组显式清单，无 glob）+
   dependencies 块零 diff ✓
5. MCP 快照族（PhotoProjection/McpServerController）diff 零命中 ✓
6. V50Order diff 零命中 ✓
7. `LightamerSidecar.swift` diff 零命中（`.lra` sidecar 格式零字节变更）✓
8. `grep -rn "\.runModal(" App/Sources` = 0 ✓
9. 本批新增 diff `String.LocalizationValue("` 插值键形态 = 0（命中为 SUMMARY 文档
   文字）；UserDefaults 零新键（代码零命中）✓

附加独立验证：
- `zh-audit --check` 独立复跑 PASS（1677 source / 1918 catalog / zh complete）。
- **sqlite3 独立探针**（ESCPE 语义，`/tmp/escape-probe.db` 即弃）：`LIKE '%' || ?
  ESCAPE '\'` 配 `\`-转义后缀对含 `%`/`_` 文件名恰 1 命中（未转义对照臂 2 命中
  证伪 wildcard 泄漏）——`likeEscaped`（先转 `\` 再 `%`/`_`）实现语义亲证正确。
- BUNDLE-MAP 六新行（:738-743 全 LIB）+ Project.swift 六行一一对应，法数逐文件
  相符（8/8/16/9/5/10）。

## 四、D-01..D-12 偏差逐项裁决

| # | 项 | 裁决 | 依据（本路亲核） |
|---|---|---|---|
| D-01 | 谓词拼写 flag-aware JOIN（KD-5 字面式 ↔ T4①/④ 收敛） | **准——合理修正** | KD-5 字面式（无 JOIN 的 NOT IN）会隐藏**展开栈**的非封面成员，与 T4①「收起栈只余封面」+ T4④「混合面」测试规格直接矛盾（字面式下混合面不可测）；D-M6-4-3 裁决本体（纯 WHERE 谓词 / keyset 零改动 / 无滤片复制 / runPage 唯一合法 diff 位）逐项保持——JOIN 在 NOT-IN 子查询内，非滤片手术。D-01 属 plan 字面 bug 的语义侧收敛，**非越权重开**。测试亲证：展开栈成员在 collapsed 模式全可见（StackPaginationTests ④） |
| D-02 | 单栈展开 = 成员现 keyset 位（v1） | 准（已登记） | toggleCollapse 不切模式，成员在 collapsed 谓词下于各自 keyset 位现身——GridStackTests ⑤ 钉死；Lightroom 聚拢语义 V2 候选登记在案 |
| D-03 | 手动 group 生 collapsed；split 尾栈继承 flag | 准（已登记） | KD-2 未钉值；保守默认（不打散当前视图）合理；实现与登记一致（group `collapsed: true`；splitStack 读原 flag 传尾栈）；测试钉死 |
| D-04 | 无 undo 偏离 | 准（plan KD-3 预授权） | 图库域今日即无 undo 基建；ungroup = 唯一逆向动作一致 |
| D-05 | fixup forward-only 偏离 | 准（plan KD-7 预授权） | displayed-set 守卫实现亲核 + T4⑦ 第二段（早前页成员 15 不回拉）+ union golden 双测钉无丢失面 |
| D-06 | 收起态无顶替 + overviewCount/groupCounts 口径分裂 | 准（已登记，KD-7 登记义务已落账） | DECISIONS §D-06 双项在案 + V2 候选（语义腿 App 侧可行）登记；`overviewCount`/`groupCounts` 零 diff 亲证（KD-5 零实现申报属实） |
| D-07 | 导入缝匹配细则版本化条款 + link 模式 + 计数器零 UI | 准（一处缺口见 M-a） | 四步序逐行亲核与条款一致；ESCAPE 实现 + SQL 语义独立探针双过；`Media/` 前缀门使 link 行不进探测（S1）；计数器仅测试消费亲证 |
| D-08 | fixup 纯函数宿主提前至 T4 commit | 准（已登记） | 每 commit 构建自洽约束下合理；`stackAdjacencyFixup` 为 LibraryGridModel 静态函数（App 侧，零 Core fixup 文件——O-3 additive 纪律遵守）；T4 commit a33a24c1 载体亲证 |
| D-09 | schema 测试定向更新九处（M3 两法 + 机械前滚七处） | **准——全为机械代际前滚，零越权** | 四文件 diff 逐处亲核：4→5 / 5→6 / 快照代际名 1-4→1-5、2-4→2-5、3-4→3-5、4-5 / 方法名 testFreshCreateStampsUserVersionFour→Five / allowlist 增 stacks/stack_content 两名（FTS shadow 谓词不动）/ 注释勘误——无一语义变更、无一断言放松 |
| D-10 | T5 fixture 批内隔离 | 准（已登记） | testMatchingRulesTable 单方法内五独立导入批（S→Burst→Solo→Lone/Odd→Amb）全走真 importFolder 亲证 |
| D-11 | auto-stack 池全集走查性能注记 | 准（已登记） | collectAllIDs 500/页 id-only 双段亲读；走查不落 rows（分页恢复不受扰）亲证 |
| D-12 | `.flat` 字节恒等双证据 | 准（清单精度勘误见 M-d） | 调用点 grep 亲跑：**7 处全在 LibraryGridModel**（语义走查双段 + loadNextPage 三臂 + collectAllIDs 双段）；MCP = Session 域零 `.lalb` 接触（零 diff 亲证）；filmstrip 消费 model.rows 零 SQL；行级恒等测试在册 |

## 五、本路独立发现（登记级 minor ×5 + 观察 ×6；零 error）

**Minor（登记级——实现面正确，缺断言/登记/清单精度；清偿归属闭环批或 omp 路
复核裁量）：**

- **M-a（O-1 兑现缺口）**：checker O-1 明示「执行期落条款时**补一条转义单测断言**
  即可」——ImportMergeStackTests 无 `%`/`_` 文件名用例，D-07「T5② 细则表覆盖命中
  面」的表述对该分支不成立。缓解：likeEscaped 实现亲核正确 + 本路 sqlite3 独立
  探针语义双过（§三）→ 实现风险已消，欠的是**回归钉**。清偿建议 = 闭环批补一法
  （或 omp 二次验收路补跑）。
- **M-b（files_modified 范围外两文件）**：T7 `923f3a85` 触碰
  `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（+13 行 onChange 消费）
  与 `WorkspaceModel.swift`（+27 行 pendingStackCommand 载体）——不在 plan
  front-matter `files_modified`，DECISIONS 未登记。亲核：additive 命令路由载体
  （pendingAIEnhance 既有模式复用），KD-8「View 菜单 + 非图库面 no-op 守卫」的
  必要机制，零既有行为面变更（App 810 零漂移佐证）。定性 = 未申报的合理机械
  依赖，补登记即可。
- **M-c（两处代码注记引用悬空 DECISIONS 条目）**：①`LibraryQueries.stackMembers(
  ofStacks:)` 头注自称「DECISIONS-registered」；②`LibraryGridModel.
  reloadShrinkingSelection` 头注自称「DECISIONS-registered」（plan KD-7 明文要求
  「不保滚动位——v1 简形；DECISIONS 登记」）——两处均为**事实正确但登记缺失**
  （DECISIONS D-01..D-12 无对应条目）。清偿 = DECISIONS 补两行（或闭环批翻账
  AGENTS.md 时并入 M6-4 节）。
- **M-d（D-12 调用点清单漏数）**：D-12 写「5 处（:180/:191/:236/:247/:254）」；
  实际生产调用点 **7 处**（collectAllIDs 双段两处为 T6 后增）。漏数两处行为正确
  （缺省 .flat，池走查不受收起谓词影响 = D-11 语义），结论面不受扰，清单需勘误。
- **M-e（翻账推迟未编号）**：plan `files_modified` 含 AGENTS/ROADMAP/REQUIREMENTS/
  GOAL-STATE/TODO 五文档（T7/T8 兑现）；实际全批零翻账（五文档 M6-4 面现状亲核
  未动），SUMMARY「翻账建议（闭环批统一做）」开放式申报但未入 DECISIONS 编号
  偏差。定性 = 申报透明的程序偏差，闭环批翻账时顺带闭。

**观察项（零动作或 V2 候选）：**

- **O-i**：`LibraryStore.autoStack` 空 `ids` 数组将拼出 `IN ()` 非法 SQL 抛错——
  App 侧不可达（contextMenu 挂在 cell 上 = 池 ≥1；`stackedIDs(in:)` 有空守卫，
  读腿无）。防御性守卫 V2 候选。
- **O-ii**：fixup 纯函数两栈共享同一 anchor 时插入序 = 排序稳定性决定（无重复/
  无丢失风险，仅相邻序细节）。
- **O-iii**：fixup 前拉成员不在原页 → 徽章 membership map 无其条目（下次 reload
  自愈）——观感级。
- **O-iv**：fixup「幂等有界」的模型级显式重复 loadNextPage 零增量断言缺（结构性
  保证 + 纯函数层守卫测 + 走查计数钉已覆盖主体；补一条显式断言 = 完整形态）。
- **O-v**：展开（.flat）模式下点成员 cell 徽章 chevron 翻转栈 flag 而网格无可见
  变化（模式不切换）——D-02 v1 语义的观感后果，Lightroom 对齐 V2。
- **O-vi**：工作区 untracked 残留 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`
  ——M4-1 挂账 #6 / M6-2 挂账延续项，非本批产物，本批不处置。

## 六、GUI Manual-Only 清单（移交 omp 二次验收 / GUI 走查批）

单测面已闭环；以下观感项待走查（SUMMARY §GUI 缺口与本路合并）：

1. 徽章/chevron 点击态（收起/展开翻转 + 计数显示）。
2. AutoStackDialog sheet 呈现 + preview 组数随 gap 变化 + Start 禁用门。
3. View 菜单两命令在图库面生效 / 编辑器面 no-op（无异常）。
4. contextMenu 五项条件可见性（无选区 / ≥2 选区 / 栈成员 / 栈封面）。
5. D-02 单栈展开的 keyset 位观感（v1 语义确认）。

（accessibilityIdentifier 已预埋：`library.grid.cell.stackBadge.*` /
`chevron.*` / `library.autostack.*` / `menu.view.stacks.*`。）

## 七、验收链状态

| 路 | 状态 | 结论 |
|---|---|---|
| 第一路 zcode 独立验收（本文件） | **完成** | **PASS / 0 error + 0 minor open + 5 登记 minor + 6 obs** |
| 第二路 omp 二次验收 | 待串行执行（`dual_acceptance=true`；严禁并发） | 结论追加于本节 |

执行链 `f30e83a3..6fa1f536` 八 commit 与 plan 提交约定逐条对表一致
（T1 `f30e83a3` / T2 `8c613f4f` / T3 `80b7c5fd` / T4 `a33a24c1` / T5 `c4ce7847` /
T6 `07d5fcdd` / T7 `923f3a85` / T8 `6fa1f536`）；本验收零 push、零历史手术；
独立探针产物（/tmp）即弃未入仓。
