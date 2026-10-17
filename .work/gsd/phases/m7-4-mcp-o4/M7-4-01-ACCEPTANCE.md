# M7-4-01 ACCEPTANCE — 第一路独立验收（zcode subagent，2026-10-17）

```
phase:      m7-4-mcp-o4
object:     M7-4-01 执行链 49fab645..df0928f4（7 commits，T1-T7）
method:     不轻信执行方报告——全套独立复跑 + S1/UQ-A2 深审 + e2e/kill 对照亲跑 +
            union 全点位亲核 + 偏差十条逐条裁决 + 红线族亲跑；产物逐 diff hunk 亲读
verdict:    **PASS / 0 error + 2 minor（open，均非阻断）**
dual_acc:   本文件 = 第一路；omp 二次验收按 dual_acceptance 制度串行跟进
```

## 结论头

**PASS / 0 error + 2 minor** —— 执行链与修订版 plan 逐面吻合；全套独立复跑
`TOTAL|3925/35/0|` 逐位精确对账闭合；S1 修复机理亲证成立（e2e 真断连独立复跑绿
+ kill 形对照 WAL 387KB 非 0 判别力实证）；偏差十条全部裁定成立（含最重项
runner 中央 env 门=合理扩展非越权）。无阻断发现。

## §1 亲跑数字（独立复跑，非转抄）

- **全套 `caffeinate -dis Scripts/test-direct.sh --all`（本验收先做全新
  `xcodebuild build-for-testing` 再跑——执行方产物 mtime 08:44 早于 T6 commit
  08:51，mtime 面不可自证含终码，验收轮重构自证新鲜度）**：
  `TOTAL|3925/35/0|` 2076s，exit 0，**零 MEMFAIL，七 bundle 全 8G 门内**。
  逐 bundle：IOP 687/5/0（peakRSS 7770MB）/ IOPParity 460/3/0（7256MB）/
  Layers 494/5/0（808MB）/ Library 736/4/0（623MB）/ Sessions 284/9/0
  （1629MB）/ Export 385/5/0（6107MB）/ App 879/4/0（2832MB）。
  **对账**：基线 3905（868+731+381+494+687+460+284）+ ΔN 20（App+11 /
  Library+5 / Export+4）= 3925 精确；skip 5+3+5+4+9+5+4 = 35 构成与申报
  一致零漂移。
- **S1 e2e 单测独立复跑**：`--bundle App
  'McpProjectArbitrationTests/testStdioDisconnectReleasesProjectGracefullyE2E'`
  = 1/0/0 绿（真产线二进制 spawn → initialize → project_create → 关 stdin →
  exit(0) ≤12s + `.lalb-wal` size==0）。
- **kill 形对照（修复判别力亲证）**：spawn 同一二进制 → project_create →
  SIGKILL → 进程 exit=-9，`.lalb-wal` = **387312 字节（非 0）**——graceful
  形 wal==0 / kill 形 387KB，wal==0 断言确为 graceful 正面证据（与执行方
  e2e2 遗物 387KB 申报同量级）。
- **zh-audit**：`--check` PASS（1698 source keys / 1946 catalog keys）+
  `--self-test` PASS——与 DECISIONS §5 申报一致。
- 运行中资源监视：全程无 GUI 实例混杂（进程清理前 parentage 口径核对；测试
  宿主 parent = 脚本进程树）。

## §2 S1 修复深审（最重项）

- **poll 体三点改形亲核**（`49fab645` diff + HEAD 函数全文逐行）：
  ① `events: Int16(POLLIN)` 请求位在位（清位只清 revents 绝不清 events）；
  ② `poll(&fds, 1, 250)` 超时形在位；③ revents 分流 = HUP/ERR → break
  （close+exit(0) 体原样）+ 纯 POLLIN 臂清 revents + `Task.sleep(250ms)` 续
  poll + count==0 超时臂零 sleep。SC grep 族全过（events/poll250/分流/
  Task.sleep 各恰一处；`exit(0)` 在 watcher 体恰原位一处）。
- **四语义零改亲核**：once guard（eofArmLock + eofArmDone）/ M1
  `guard mode == .stdio` 自守卫 / close+exit(0) 体 / http 臂不 arm（恰两调用
  点 :321/:571 全走 mode 传参 + 臂内自守卫双保险）——函数其余行 diff 零触。
- **忙旋消解机理亲验（F2 真机理）**：确认超时形只封阻塞相（恒可读 fd 上
  poll 就绪即返），速率限制本体 = 纯 POLLIN 臂 sleep（4Hz .utility 帽）；
  真管道 HUP 到达走 HUP 分支不经 sleep 臂（12s 活性窗无扰——e2e 0.87s/
  独立复跑 4s 墙钟内含宿主启动）。实现与注释、DECISIONS §2.10、AGENTS
  :542 三处表述一致。
- **e2e 断言实质**：两断言（≤12s 活性 + wal==0 checkpoint）+ 锁语义侧写
  （退出前第二 open = typed projectHeldByOther，确定性形——偏差⑨裁定成立）
  + fixture `LIGHTAMER_SKIP_LUT_PREHEAT=1` 注入在位（:74）。
- **探针迁 evidence**：盘上 `evidence/m73-probe/` 7 件在位（probe.c/harness
  .c+sh/e2edrv*.c/e2e.sh）；`/tmp/m73_probe` 原件留存；git 面随
  lightamer-evidence 仓 `70774ad`（亲验 7 文件 326 行）——偏差①政策 B
  裁定成立。
- **挂账⑥/H3③/特殊事项 5 措辞校订完备性**：M7-3 签核文档零回改
  （`git diff 7d595abc..df0928f4 -- .work/gsd/phases/m7-3-mcp-o2o3/` = 0 行）
  + 校订正本 = DECISIONS §2.10（F2 真机理表述）+ AGENTS :542 修后终形；
  grep 全源无活性文档残留「双臂皆惰性」过时表述（M7-3 时代句子在修后
  语境反而成真，历史节按不回改纪律保留）。

## §3 T3 O4 深审

- **Catalog 恒等单源**：`AdjustmentTransferCatalog` 纯 helper（无
  @MainActor）= enumerate/buildPayload verbatim 抽取；GUI model 委托改形
  行为零 diff；`isAdjustmentTransferable` 全仓恰单一函数定义（grep 亲跑 =
  1）；mask contentRevision 置 nil 恰一处（buildPayload 内）；golden
  `testCatalogEnumerationAndPayloadMatchTheGuiModelValueForValue` 逐值恒等
  实质亲读（nodes/items/layerSnapshots/payload 四层断言 + 两 face mask
  纪元重置 + include/includeDrt 过滤腿）。
- **paste ledger 全臂**：targets ≤1000 + 重复项 invalidParams（F10）+
  membership/live 硬拒 per-target（非 skip）+ probe 全调拒 + 无状态源重读
  + `.overwrite` + label "MCP paste_adjustments" + `flushForTeardown` 写达
  后方返 + 固定 reason token 集（F7 四 token）+ 全拒批 appliedCount=0
  诚实应答 + 空源 invalidParams（偏差⑥裁定成立——封闭表既有码）。
- **author="mcp" 盖章**：`mcpAuthorToken` 常量双写工具消费；apply_params
  note 参（schema + body + minLength 1）；透传链四签名 additive 默认参
  （apply→composeSegment→paste→commitPaste→HistoryItem.init）逐 diff hunk
  亲核；GUI 写腿零触（author nil）。
- **sidecar v11 镜像全链五件亲读**（`LightamerSidecar.swift` diff）：Keys
  两 case + 存储两属性 + init 镜像携带 + decodeIfPresent/encodeIfPresent +
  `item` 重建两实参 + schemaVersionCurrent 10→11（先例链注释）——除
  carve-out 外该文件零触（红线③机检过）。
- **SidecarV11Tests 五法亲读**（新文件，LIB 域=V10 同位）：v10-form
  byte-exact / nil face = v10 shape 仅 digit 异 / stamped roundtrip
  byte-faithful（含 `item` 重建镜像面）/ HistoryHash 隔离负测 / future
  tolerance schemaVersion 12（CHECKER C1 守卫重正）；SidecarV10Tests 全链
  零 diff（0 行）。
- **get_history 真位翻转**：per-item 恰 +2 键（缺省 .null）+ 顶层 author =
  `stack.position >= 0 && position < count ? items[position].author : .null`
  （真位式 + 越界守卫——比 plan 字面多一层 bounds check，语义等价更稳）；
  红尾腿 golden（position 3 + 最新 kept ≠ position item）+ pristine .null
  负测在位。

## §4 T4 UQ-A2 深审（五腿全在位 + 全套轮亲证绿）

- **产线缝**：encodeStage 恰尾追 `exclusiveFinalWrite: Bool = false`；
  exclusive 臂 = 同目录隐藏 tmp `.<name>.<uuid>.tmp` + post-encode 两腿
  （ICC strip / XMP mount）原位跑 tmp + `promoteExclusive`（link 成功
  unlink / EEXIST → `BaseNameOccupiedError` 复用 / 其它 errno →
  encodeFailed 兜底）+ defer 清 tmp；**encoder-error catch 清理腿改道**
  （F4：`if !exclusiveFinalWrite` 才触 destination——exclusive 臂不触他进程
  可能的同名物）；gain-map 臂同 wrap；`.replace`/缺省路径 plain rename
  原样。ExportNamer/ExportQueueContract 零 diff；render 步快照门
  （:620-645）零触亲验（上游分歧申报成立——成本门保留）。
- **递缝纪律**：encode 腿 `$jobNamingCarrier.withValue` wrapper（render 腿
  同形装配）+ encodeLeg 内读 `collisionPolicy == .fail` 传参——leg 闭包
  签名零 diff（ExportQueueContract 零触机检过）。
- **五腿**：①TOCTOU 负测（typed 错 + 植入字节不变 + glob 零残留）②正向
  恒等（byte-equal）③.replace 负面守卫 ④.increment = 既有 E2E face
  （零新增，申报形）⑤encoder 失败腿（float32 plane 强制 throw + 预植
  destination 字节不变 + 零残留）——Export 385/5/0 全套轮亲证绿。

## §5 T5/T6 对账

- **T5**：LightamerApp provider return 恰一行 `deletingLastPathComponent()`
  （20997721 先例第三实例）+ 三测试 provider 同形 + kind0 锚腿新法
  （pathKind 0 行 → resolve == `<projectDir>/Media/x.tif`）。
- **T6 union 全点位亲核**：冻结表 +2 行（copy/paste 完整 schema verbatim）
  + apply_params note 行两层同批 + 计数 ×4（:275/:328/:356/:510 全 29）+
  destructive 集 10 元素（+paste_adjustments）+ descriptionKeys +2 +
  all29（:245）+ 测试名 Union29Verbatim + 头注 :20-25 + message 同批。
  **union 外五钉**：:223（RegistrySnapshot）/ :274（SearchState）/
  :243/:697（Host）/ :200（Launcher）全 23 + message 同批；残漏 grep
  （`count, 21` / `count == 21` / `all27` / `Union27`）全仓测试面零命中。
- **editing 层**：apply_params note 行 + copy/paste 两行（7→9）+ 算术钉
  9+14=23（F3 防复发形兑现）。
- **GUI 面**：historyRow note 副标题（caption2 + lineLimit(1)）+ author
  徽章（nil 无徽章 + AX label 键）diff 亲读；xcstrings 第三键尾块插入。
- **golden 面**：O4 七法（copy 枚举/paste ledger×4/include+DrtOptOut/
  Catalog 恒等）+ MCP2-09（V11 五法 + get_history 红尾）+ 温度归属修正
  （偏差⑤：NodeOwnershipCatalog :21 亲验「camera WB is a RAW Decode
  concern」——断言未放宽，捕获面即正确性）。
- **登记纪律**：Project.swift 恰一行 + BUNDLE-MAP 恰一行功能登记行（LIB
  域=V10 同位；附注 4 行为 additive 注记非登记行）。

## §6 偏差十条裁决（逐条）

| # | 偏差 | 裁决 | 依据 |
|---|---|---|---|
| 1 | 探针分仓（evidence 仓 `70774ad`） | **成立** | 政策 B（.gitignore :80 用户令）> plan 字面；盘上 SC 判据满足；evidence 仓 commit 亲验 |
| 2 | T2 四→五文件（+EditingToolset） | **成立** | en defaultValue 住在代码文件，「en+zh 同批」必然触它；M7-3 `3ef68910` 先例 |
| 3 | **runner 中央 env 门（test-direct.sh export）** | **成立（非越权）** | 见下详述 |
| 4 | V11 落 LIB 域 | **成立** | V10 同位先例（Project.swift :624/BUNDLE-MAP LIB 行）；CHECKER 原文「LIB〔=Layers 域〕」即此指称；plan 文误 |
| 5 | 温度归属修正 | **成立** | NodeOwnershipCatalog :21 亲验；断言收紧未放宽 |
| 6 | 空源 payload = typed invalidParams | **成立** | 封闭表既有码；全拒批语义（目标侧）不适用于源侧空态；copy 先行可避免 |
| 7 | S2 预热观察证据（冷窗未重测） | **成立（如实）** | env 门使然；50.2s 正本维持 M7-3；观察面非门值 |
| 8 | SidecarV10Tests :327 法语义退化申报 | **成立** | CHECKER C1 闭环——V11 第五法亲读在位；V10 文件零 diff 亲证 |
| 9 | e2e 可选锁窗腿未行使 | **成立** | SC「可选腿」条款内；确定性侧写强于 12s 竞速形；测试体亲读在位 |
| 10 | 三处措辞校订注记 | **成立** | §2 已核（F2 真机理 + 零回改 + UPSTREAM-QUEUE OBS-M7-4-1..4 入队亲验） |

**偏差③（runner 中央 env 门）影响面评估（本验收重点复核项）**：
- 改动体 = `Scripts/test-direct.sh` 顶部一行 `export
  LIGHTAMER_SKIP_LUT_PREHEAT=1` + 注释——测试基建，非产线码；产线 env 门
  （helper 内 nil 判）行为不变，非测试语境的 GUI 宿主零影响。
- 动机成立：McpHostTests/McpFinalSnapshotTests/McpRenderParityTests
  **in-process 直调 startHTTPHost**（亲验调用面在案）——App/Export bundle
  宿主会付 ~50s 预热 + 向真实用户 LUT 根 seeding；plan F14 只盖 spawn 面，
  in-process 面确实漏盖；中央 export 一处替代三文件 setenv 且 spawn 子进程
  env 继承全覆盖（mechanically 成立）。
- T1 fixture 显式注入行保留（F14 字面兑现，:74 亲验）——双防线非互斥。
- 实测证据：全套轮 App 379s（执行方申报 373s/385s 同量级，无 50s 停滞）。
- 越权判定：test-direct.sh 不在 files_modified 清单，但红线族未冻结该文件
  （登记纪律只钉 Project.swift/BUNDLE-MAP 行）；改动 additive、语境面单一、
  DECISIONS §偏差3 申报在案——**裁定 = 合理扩展，非越权**。留痕：该文件
  后续如再被触碰建议每次 DECISIONS 单独申报（本次已做）。

## §7 红线族亲跑（T7 电池独立复跑）

零新 SPM（Project.swift dependencies 块零 diff，恰 SidecarV11Tests 一行）/
`.metal` 全域零 diff（changed files 扫描 0 命中）/ HistoryHash.swift 零
diff（0 行）/ McpToolRegistry.swift（含 McpTimeouts）零 diff /
ExportNamer+ExportQueueContract+ExportFormatSpec+ImageIOEncoders+
WebPEncoder+ExportInspectorView+LibraryProjectController 零 diff /
Pipe/Graph/IOP 域仅申报内三文件（HistoryStack/PasteSemantics/
LightamerSidecar）/ `isAdjustmentTransferable` 恰 1 定义 / `.runModal(`
App/Sources 零命中 / LocalizationValue 插值禁形唯一命中 = LightamerApp
:2307 既有文档注释（申报面）/ xcstrings 恰 2 hunks（1 原位值改 + 1 尾块
三键插入）/ UserDefaults 零新键（diff 面 grep 无）/ 改动文件清单与
files_modified 一致（+Scripts/test-direct.sh=偏差③申报面）。

## §8 独立发现

- **minor-1（open，hygiene）**：过时计数注释残留 5 处——
  `McpFinalSnapshotTests.swift` :268（"exactly these 27 descriptors"）+
  :263（"27 is"）+ `McpHostTests.swift` :466/:668（"21-tool face"）+
  `McpSearchStateToolsetTests.swift` :16/:265（"count rides 21"）。SC 机检
  判据（可执行形态零命中）全过、断言本身全部正确——但注释与断言矛盾，
  正是 M7-3 H1 家族的注释误导面。建议 M7-5（持 union 权波）顺手清，不阻断。
- **minor-2（open，robustness 观察）**：`ExportRenderer.promoteExclusive`
  中 `strerror(errno)` 求值先于 `errno == EEXIST` 判读——POSIX 不保证
  strerror 保全 errno，理论上 EEXIST 判别可被 clobber 降级为 encodeFailed
  （防覆盖语义不损，仅 typed 面降级）。macOS 当前实现未触发（TOCTOU 负测
  两轮绿）。建议一行重整（errno 先存 local 再 strerror）随下一 Export 波
  顺路，不阻断。
- 观察项（非发现）：执行方产物 mtime（08:44）早于 T6 commit（08:51）——
  先写文件构建后 commit 的时序，本验收以全新 build-for-testing 自证消解，
  不构成缺陷。

## §9 commit 清单（49fab645..df0928f4，7 commits）

1. `49fab645` fix(m7-4): wake the stdio EOF watcher on POLLHUP with a bounded re-poll（T1）
2. `d3f487a6` fix(m7-4): preheat the LUT store and pin the gui readonly predicate leg（T2）
3. `a78ea631` feat(m7-4): add the adjustment copy/paste tools and note attribution（T3）
4. `2af9b17d` fix(m7-4): make the FAIL collision tier reject on final write via link（T4）
5. `a9b8f06e` fix(m7-4): anchor the match_color library provider at the project directory（T5）
6. `503f1ffc` test(m7-4): pin the o4 goldens and grow the union snapshot to 29（T6）
7. `df0928f4` docs(m7-4): reconcile the full suite and close the M7-4 ledgers（T7）

每任务独立 commit、Conventional Commits 全英文、只 add 相关文件——抽样
面核（T1/T3/T4/T5/T6 逐 commit --stat 与 files_modified 对应）吻合。

## §10 判定

**第一路独立验收 PASS / 0 error + 2 minor（均 open 非阻断）。**
M7-3 挂账①②③⑤⑥清算兑现；MCP2-08/09 + UQ-A2 Delivered 申报成立；
union 改动权行使合规（M7-5 串行禁并行注记延续）；全套 3925/35/0 独立
复跑逐位闭合。按 dual_acceptance 制度移交 omp 二次验收（串行）；两 minor
建议随 M7-5 波顺路消化。
