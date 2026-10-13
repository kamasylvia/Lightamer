---
phase: M6-1
slug: interop-single-writer-lock
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-14
---

# Phase M6-1 — Validation（MCP-09-A 项目级单写者锁 + `--connect` 活实例转发）

> 体例对齐 `phases/m4-1-tiff-raster/M4-1-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收（config
> `dual_acceptance = true`）落终态后成文**：第一路 zcode 独立验收 PASS（发现并
> 当场修复 E1 session-lock ride-along 自撞，`5d814958`）→ omp 二次验收**实际执行
> 但未及正式落账**（GUI 走查 8 截图在 `.work/gui-acceptance/m6-1/omp/`；error
> 发现 M-OMP-4 = create/move 生产路径缺 role 的无锁双写窗）→ **最终独立验收
> （零共享上下文 subagent）吸收三段全史收口**——终态正本 =
> `M6-1-01-ACCEPTANCE-FINAL.md`，结论头 **PASS / 0 error + 0 minor**。
> **翻账只认证据**：SC 六项生效值对账正本 = 两路 ACCEPTANCE + FINAL 三份亲跑
> 记录；charter 验收形态四件（ROADMAP §M6-1 行）= 真实双进程仲裁 fixture ✓ +
> 无头 connect 指引输出 ✓ + GUI 只读面走查 ✓ + 既有 MCP 面（20 工具封闭集 /
> G4 parity）零回归 ✓。
> **SC 数字对账基线 = 全套 `--all` 终验 `TOTAL|3689/24/0|2157s` 亲证值**
> （2026-10-14 00:25-01:01 终验批，exit 0 零 MEMFAIL；对账链 **3631 + 53 + 4 + 1
> = 3689**：3631（M5-3 终值基线）+ 53（worker 十提交六新文件）+ 4（omp 复审批
> golden 四法，`f8e0671c`）+ 1（M-OMP-4 新法，`908526fe`）= 3689 精确算术闭合；
> skip 恒 24 零新增）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / **真实双进程仲裁轨**〔spawn 宿主二进制 + poll 门控管道〕/ GUI 实机走查轨 / LightCraft `catalog.lock` 范式对表） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠，L055 双保险） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3689 tests / 24 skip / 0 fail**（2157s，2026-10-14 终验批亲跑 exit 0；日志正本 = `acceptance-logs/full-all-final.log`；七 bundle 逐行：IOP **684/1/0**〔6797MB〕/ IOPParity **460/3/0**〔6822MB〕/ Layers **466/4/0** / Library **654/4/0** / Sessions **279/4/0**〔E1 seat 修复规模化在证〕/ Export **353/4/0**〔5979MB〕/ App **793/4/0**〔2832MB〕；峰值全 <8G 运行门，零 MEMFAIL 零 crash） |
| **基线演变** | 3631（M5 终值）→ worker 批 +53（SingleWriterLock 8 + ProjectLock 10 + FaceTests 14 + Arbitration 9 + McpReadOnly 8 + Colormatch 4）→ omp 批 +4（FaceTests 14→18）→ M-OMP-4 +1（18→19）= **3689 精确**；三段对账两式互证（终验 §一对账式 + 双重验收第一轮算术闭合 3688−4=3684 已提交面零失败） |
| **SC 数字面** | 定向对表全程精确：LIB **654/4/0**（= AC8 分账）/ APP **788→792→793**（三段递进逐位命中）/ IOP **684/1/0** 零漂移 / IOPParity **456→460/3/0**（D-1 归属勘误）；双进程确定性 = 序 A/序 B 各双跑 decode 级逐键一致（D-5 口径）；FaceTests **19/0/0** 终验亲跑 |
| **在案 flake（本 phase 事件）** | **E1（验收第一轮抓到，当场修复）**：legacy `session.lock` ride-along 同进程二次 `openAndSync` 自撞 flock per-fd → `failed:true`（Sessions 两既有测试红；修复 `5d814958` = 进程内 seat registry，Sessions 279/4/0 双轮回基线）；**M-OMP-4（omp 二次验收发现，终验批清偿 `908526fe`）**：create/move 三条生产打开路径缺 role → 新建/移动后项目无锁常驻 = 双写窗（修复 + 新 golden + 测试稿空洞断言修正）；全套轮孤儿 fixture 再生成（M4-1 挂账 #6，非本 phase 引入，如实登记） |
| **GUI 证据** | omp 实机走查一轮（`.work/gui-acceptance/m6-1/omp/` 8 截图 2026-10-13 15:33-15:39 + `MANIFEST.md` 配方）：A1 = `open -n` 双实例冲突对话框三选 sheet（真 pid 92632 插值）/ A2 = 只读打开后常驻 banner 同 pid + 图库可浏览 / B = 编辑面只读态（banner 在位 + 编辑入点禁用）；终验批对三张关键截图逐项目检与 MANIFEST 预期相符；Manual C 行（无头 connect 指引终端目测）未人驱——机检 `McpProjectArbitrationTests` decode 级全覆盖（见挂账 #1） |
| **zh 对账** | 新增 10 键全入册（KD-7 九键 + `session_lock_held` 申报，D-2）；zh-audit `--check` **PASS**（source 1661 / catalog 1900）；xcstrings diff 自 `26fd6bf0` = **纯插入**（删 0 行 / 增 170 行，终验机检亲核）；omp 复审批零新键（KD-7 十键不动，D-11） |

---

## SC 六项生效值对照（`M6-1-CONTEXT.md` 裁决记录 2026-10-14 用户回批全 A → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **锁五态 + 项目粒度**（OQ-1）：`<stem>.lalb.lock` sibling + legacy `session.lock` ride-along；flock 唯一仲裁、pid 永不作 liveness 判据；`.lalb` 零 schema 触碰 | T1 `4d345a6f` + T2 `61f5d5d0` | **Delivered**：Core `SingleWriterLock` 泛化件五态语义与 `McpEndpointFile` 正本逐条一致（flock EX\|NB 唯一仲裁 / `EWOULDBLOCK\|\|EAGAIN`→heldByOther / 无 O_EXCL+pid 清扫 / payload 骑锁 fd 仅诊断面 / probe=try-flock 即释）+ payload v1 冻结拼写 round-trip 负测 + 缺字段拒解码 + pid 缺席「pid 未知」回落（`SingleWriterLockTests` 8 法）；`ProjectFileStore` role-nil 零触碰 + 锁 nil 幂等 + **heldByOther 在 pre-migrate 快照轮换之前 typed 抛**（`testAcquirePrecedesMigrationSnapshotLeg` 钉死）+ openReadOnly E2 三岔 + close = checkpoint→handle close→unlock WAL 尾安全序 + backup 只读可用产物零锁文件（`ProjectLockTests` 10 法）；`LibrarySchema`/`project_meta`/备份/移动零触碰（红线机检 diff = 0）；flock per-open-file-description 同进程二 fd 语义 checker o1 编译探针实证 + LightCraft `lock.rs` 头注同语义对照成立 |
| 2 | **对称单写者 + 只读回退**（OQ-2）：GUI 撞锁 = 三选对话框；无头撞锁 = 只读 + 指引；无 GUI 特权非对称 | T4 `f255e8a8` + T6 `1f981f9b` | **Delivered**：`McpProjectArbitrationTests` 9 法**真实双进程**亲绿——序 A（父持项目锁 → 子 HTTP 臂 stdout 首行指引 + 800ms 存活负测）/ 序 A'（stdio：JSON+人类行全 stderr、**stdout 零字节**）/ 序 B（子 fixture 持锁 → 父 typed `projectHeldByOther` 携 holder 摘要）/ **序 A/序 B 各双跑 decode 级一致**（D-5）/ 五态③窗口（持有者退出 → 子重跑获 writer 臂）/ 旗标校验两腿 exit 1 / 无 `--project` 冒烟零回归；GUI 侧对称 = `ProjectConflictDialog` 三选 zh verbatim（sheet 面，无 @Environment 跨界——M2-8-3 FINDING-A 规则遵守，FaceTests 前 6 法含实机走查 A1） |
| 3 | **connect 指引**（OQ-3）：只读 server 常驻 + 启动 emit 机读指引（否决立即退出 / 内嵌转发代理） | T6 `1f981f9b` | **Delivered**：指引 JSON decode 级逐键断言（event=connect-guidance / endpoint{transport,host,port,auth} / holderPid）+ 降级变体（无端点文件 → `endpoint:null`）+ 通道分叉（HTTP=stdout / STDIO=stderr 零污染负测）；**只读常驻** = `startReadOnlyHTTPHost`（D-4 执行期设计修正：不取 endpoint writer 锁、不写 discovery json、`writerCheck { false }`——与 OQ-3「只读常驻」相容，GUI 持 endpoint 锁时子进程不 exit(4)）；stdio EOF = `poll(2)` 零事件掩码盯 HUP（D-10，仅 `--project` 臂挂）；无立即退出臂、无转发代理（存活负测钉死） |
| 4 | **GUI 最小只读面**（OQ-4）：浏览/检索/查看/备份可用 + 编辑入点禁用 + banner 常驻 + toast 一次性 | T5 `4326e3c4` + omp 复审批 `f42dc13c`/`ed6ca3e7`/`cf36190a` | **Delivered**：**三 seam**（EditorState gate / ExportState 两 enqueue typed 拒 / LibraryStore withWriteBatch 断路）+ banner AX 实窗断言（真 NSWindow AX 树含 `shell.readonly.banner`，可写态零 chrome）+ 重试臂 + moveProject typed backstop + backup 可用 + 顶栏 export/yiyin `.disabled(isReadOnly)` 同源布尔 + `runModal` 零命中常驻钉死；**omp 复审批 guard 家族 7→13 扩面**（plan 复审 FAIL 1E+5M 回注后落地）：performUndo/performRedo 拒 false + performJump no-op + **`PipeCoordinator.jumpToHistory` 门读**（堵 blocked-jump 的 sidecar touchActive 尾写——plan 处方外一行，D-11 申报）+ install 三函数 no-op + **VersionCoordinator coordinator 级 gate 六写命令全集**（createFromScratch/branchFromCurrent/pasteChain/switchTo/rename/remove，typed no-op + logger 静默）+ pasteToSelection batch 入口门 + toast 拒 + Edit 菜单四处 `.disabled \|\| isReadOnly` + VersionsPanelView 八处 `.disabled`；D-9 禁用清单机检表逐项在册 |
| 5 | **probe 时机 + 错误面**（OQ-5）：启动 + 每写类调用前 probe（非持有式、自持豁免）；`projectReadOnly` additive 一枚；`imageLiveInEditor` 先判 | T7 `1ee26c40` | **Delivered**：`McpProjectReadOnlyErrorTests` 8 法亲绿——probe held → typed `projectReadOnly`（code + 文案携 `role=gui pid=…` + connect 指引语）/ **live 先判序负测**（live 图 + 锁 held → `imageLiveInEditor`）/ probe nil 零行为（legacy 写落盘）/ serverReadOnly 先序（endpoint 门 → probe 正交）/ **自持豁免放行**（flock per-ofd 自拒缺陷闭死，D-3/L079 单点获锁纪律）/ export 头部 probe（先于参数校验）/ culling write-five frame 内 probe + 读类 `list_presets` 照常 / match_color attach 门；五调用点 HEAD 读码核对在位（export_image :314 / apply_params :557 / culling :355+:576 / match_color :416）；**20 工具封闭集快照族零 diff**（D-8 申报义务兑现——`McpToolError.projectReadOnly` additive 无快照面） |
| 6 | **o-2 搭车清偿**（OQ-6）：`ColormatchResolverBox` NSLock holder 收紧（否决转 M6-5） | T8 `5ff6ff48` | **Delivered**：NSLock holder = `LutLibraryStore` 体例镜像（sharedLock + sharedInstance nonisolated(unsafe) + 锁内 getter + `replaceShared` 原子换）；三写点改 replaceShared（ColorMatchService :138/:309 + MatchColorToolset :454）+ 读点局部化；**裸 `shared =` 残留全仓 0**（终验机检）；`ColormatchResolverBoxTests` 4 法全绿（IOPParity 460 轮含内；D-1 归属勘误 = 真实邻居 IOPP 非 IOP）；M-OMP-1 键登记义务兑现 |
| — | **AC7 零回归门** | T3 `397574bd` + T9 `81fdb0fc` | **Delivered**：`McpEndpointLock` 薄封装 delegate Core 后 **McpHostTests 18/0/0 原样全绿**（行为零 diff 门亲跑）；快照族/G4 parity 全套轮含内零 diff；`Project.swift` diff = 纯测试数组增行、dependencies 块零触零新 SPM；QuickLook/Spotlight appex 零触碰；无 `--project` 无头路径冒烟零回归；封存面（HistoryStack/HistoryHash/V50Order/DrtRecord/Registry[Core+IOP]/PipelineDocument/NodeGraphCommand/AIWorkerProtocol/六格式矩阵/YiyinExportSettings）+ 全部 `*.metal` + `LibrarySchema.swift`+`Sidecar/` diff 全零（终验九域机检亲跑全绿） |
| — | **AC8 SC 数字门** | T10 + 终验批 | **Delivered**：定向 LIB 654/4/0 + APP 788→792→793 递进精确 + IOP 684/1/0 零漂移 + IOPP 460/3/0（勘误后）；全套终验 **3689/24/0** = 对账式 3631+53+4+1 精确闭合，exit 0 零 MEMFAIL 零 crash 零 no-total-line |

## 双重验收记录（dual_acceptance 三段链，终态正本 = ACCEPTANCE-FINAL）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **第一路 zcode 独立验收**（2026-10-13 夜，验收树 `0f6bdcd7`） | **PASS**（E1 发现并当场修复 `5d814958`） | 全套 `--all` 两轮亲跑（二轮 3688/24/1——唯一失败属并行线 in-flight 测试自身，已提交面 3684 算术闭合全绿 + HEAD FaceTests 18/0/0 双证）；锁机制/对称性/GUI 面/MCP typed/红线七域审计全过；亲跑不轻信报告 | **E1（error）**：session.lock ride-along 同进程自撞——worker 定向轮 `test_bundles [LIB,APP,IOP]` 未覆盖 Sessions 面漏出，全套第一轮 fail-fast 抓到；修复 = seat registry（同 root 共享活锁、末座起立才 unlock、跨进程仲裁不变）；Sessions 279/4/0 双轮闭合；教训具文本提交内 |
| **第二路 omp 二次验收**（串行执行 2026-10-13，未及正式落账） | **已执行，由终验吸收收口** | GUI 走查 8 截图（A1/A2/B 关键三张与 MANIFEST 逐项相符，终验目检）；**M-OMP-4 error 发现**（create/move 缺 role 无锁双写窗）随附工作树未提交修复 | 发现不流失：终验批亲验修复、补真断言（原稿 probe 的是 harness Widget 锁且 `\|\| fileExists` 恒真 → 改新包真实锁 probe 的 `XCTAssertFalse`）、亲跑 FaceTests 19/0/0 后以 `908526fe` 落库 |
| **最终独立验收**（零共享上下文 subagent，2026-10-14 00:25-01:01，验收树 `908526fe`） | **PASS / 0 error + 0 minor** | 全套 `--all` 亲跑 **3689/24/0** exit 0 + FaceTests 19/0/0 定向 + 两段合并审计（原始段 T1-T9 逐项 HEAD 复核 + omp 段 guard 13/jumpToHistory :1860/VersionCoordinator 六门/batch 门/Edit 菜单四处逐项亲数 + **omp 批纯 additive**〔f42dc13c 仅 +6 guard 行，机制文件集与 omp 零交叠〕）+ 红线九域机检全绿 + M-OMP-4 清偿 + 走查截图目检 | 残留两处如实登记不阻签核：Manual C 行终端目测未人驱（机检 decode 级全覆盖）+ 孤儿 fixture 全套轮再生成（M4-1 挂账 #6 仍活） |

三段链终态：**零未清偿 error、零 minor**；E1 与 M-OMP-4 两处 error 级发现均在批内修复并回归；M1（BUNDLE-MAP 计数）由 omp 批 6→18、终验批 18→19 尾差闭合，BUNDLE-MAP 六文件 58 法与实库一致。

## Per-Plan Map（M6-1-01 单 plan 全量批）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M6-1-01 | T1 Core SingleWriterLock 五态泛化件 + T2 `.lalb.lock` 项目锁（role 面/openReadOnly E2/withWriteBatch 断路/close 释放序）+ legacy ride-along + T3 McpEndpointLock 薄封装（行为零 diff 门）+ T4 冲突对话框三选 + T5 只读态三 seam/banner/禁用投影 + T6 无头仲裁两臂 + connect 指引（HTTP=stdout/STDIO=stderr/降级/DEBUG fixture/EOF poll）+ T7 写面 probe + typed `projectReadOnly`（live 先判/自持豁免/五调用点）+ T8 o-2 NSLock 收窄 + T9 红线机检/zh-audit/走查 MANIFEST + T10 收口 | worker 十提交 `4d345a6f..a18cfb82`（含 T10 docs）+ omp 复审批 `e2a493c0`（plan 回注）/`f42dc13c`/`ed6ca3e7`/`cf36190a`/`f8e0671c` + 验收修复 `5d814958`（E1 seat）+ 终验清偿 `908526fe`（M-OMP-4）+ docs `0f6bdcd7`/`1c96e639`/`27483070` | 三段链 PASS / 0 error + 0 minor（终态） |

零红线域终态（终验 §四亲跑，`26fd6bf0..HEAD`）：`grep -rn "\.runModal(" App/Sources` = **0**；`LibrarySchema.swift`+`Sidecar/` = **0 行**；`Project.swift` dependencies 块 = **0 触**（零新 SPM）；封存面十一件 + 全部 `*.metal`（含 Aces2Kernels）= **0 diff**；六格式导出矩阵 + YiyinExportSettings = **0 diff**；随机源门生产码 = **0 命中**；appex = **0 触碰**；zh-audit = **PASS**（纯插入）。LightCraft 范式对照成立：flock 唯一仲裁 + payload 仅 hint + typed 冲突携 holder 描述——M6-1 目标「LightCraft `catalog.lock` + connect 范式项目级兑现」达成（payload 骑锁 fd vs 独立 owner 文件为合理简化；锁外降级臂不采纳 = 本地卷边界，plan 风险条在册）；LightCraft MIT OR Apache-2.0 全程思想/命名级转录，零成段代码复制，零 NOTICE 义务触发。

---

## 挂账总汇编（M6-1 单一移交清单，四项全带锚点）

1. **Manual-Only C 行终端目测未人驱**（ACCEPTANCE-FINAL §五.2，非阻塞）：无头 connect 指引终端目测行缺人工执行；语义面由 `McpProjectArbitrationTests` decode 级全覆盖（序 A/A'/B + writer 臂 + 降级），仓库根 `c1_stderr.txt` 探针残迹已清——低风险挂账，M6-5 清算批顺路补目测或晨审裁销。
2. **孤儿 fixture 再生成**（ACCEPTANCE-FINAL §五.3）：全套轮复活 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`——**M4-1 挂账 #6（测试 sidecar 泄漏）仍活**，本 phase 跑后再删；清偿归属 M4-1 侧（建议 M6-5 批或 M4-2 派前修复批，晨审裁）。
3. **legacy 只读回退面缺席**（KD-2 显式边界，DECISIONS D-7）：legacy Session 根 ride-along 只提供 typed 冲突 toast（`session_lock_held`），无 GUI 只读回退面——范围裁定在案（M6-5 挂账清算批候选，用户诉求出现时再裁）。
4. **move 窗口锁短暂释放 + probe TOCTOU**（plan 风险条照登，DECISIONS D-10）：move 序 close→move→reopen 窗口五态③第二实例可乘入 → typed 冲突面（M-OMP-4 修复后 create/move 均持 `.gui` role，窗口收窄为可接受残留）；写前 probe 的 TOCTOU = OQ-5 probe 语义既接受风险（probe 后新实例乘入，flock 写腿仍精确仲裁）——观察项，无动作。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。六项生效值 + AC7/AC8 每条均有 ≥1 机器锚
  （SingleWriterLockTests 8 / ProjectLockTests 10 / McpProjectArbitrationTests 9
  真实双进程 / ProjectReadOnlyFaceTests 19〔含 banner AX 实窗 + omp golden 四法 +
  M-OMP-4 真锁 probe〕/ McpProjectReadOnlyErrorTests 8 / ColormatchResolverBoxTests 4 /
  McpHostTests 18 零 diff 门 + 快照族/G4 parity 全套轮含内）+ ≥1 数字/实证背书
  （终验 3689/24/0 亲跑 + 定向轮逐位命中 + omp 实机走查 8 截图 + 红线九域机检 +
  LightCraft 正本对表）。
- 采样密度：单 plan 全 AC 逐条机检（53+4+1 = 58 新测 + 既有面零回归）+ **三段独立
  验收**（zcode 全套两轮 + omp 实机走查 + 终验全套独立复跑）+ checker FAIL 先审后放
  （plan 复审 FAIL 1E+5M 回注 → omp 复审批全项落地后终验复核）；「无证据 ✅」零项。
- 数字对账：三段互证（第一轮 3688 中 3684 已提交面算术闭合 + 终验 3689 对账式
  3631+53+4+1 精确 + 定向轮 LIB/APP/IOP/IOPP 逐位命中）。

## 特殊事项入册（phase 级事件台账）

1. **omp 计划复审批（双重验收制度先审后放实例）**：plan checker FAIL / 1E+5M
   （`M6-1-01-PLAN-REVIEW-OMP.md`）→ 回注 `e2a493c0` → 执行批四 commits 落地
   guard 7→13 / coordinator 级 gate / batch 门 / golden 四法——证伪两处 plan 原宣称
   （「版本三命令靠 commit 族 guard 断路」「undo/redo/jump 直翻栈被断」均不成立，
   D-9 表划线更正），omp 批落地后由终验逐项亲数复核。
2. **两处 error 级发现均为「跨面回归/缺口」型**：E1 = ride-along 撞既有 Sessions 面
   （worker 定向轮 bundle 盲区——触碰 SessionCoordinator 却未跑 Sessions bundle，
   教训具文本提交内）；M-OMP-4 = plan-review 点名的 create/move role 缺口在计划
   回注后才在生产路径清偿——两处均为验收网兜住而非产线自暴露，验收网有效性在证。
3. **并发批交错**（ACCEPTANCE §发现 3）：第一路验收执行期间并行线落 5 commits
   （编排层知情裁决「二轮优先 + 串行」）；双线各用 -workspace/-project 容器零
   DerivedData 竞争；omp 批与原始段机制文件集零交叠、diff 纯 additive（终验 §三
   交叉影响判定亲核）。
4. **L078/L079 双教训沉淀**（T9/D-3）：表格式崩溃（键入册后 Int32 过 %@ 崩进程，
   仲裁 fixture 当场抓到）+ 单点获锁纪律（flock per-ofd 同进程自锁——外部 acquire +
   store.open 双 fd 缺陷，store 即唯一获锁点）。
5. **D-4 执行期设计修正**：只读 HTTP serve 走 `startReadOnlyHTTPHost` 新面（不走
   `startHTTPHost`——其 endpoint writer 锁契约与 OQ-3 只读常驻冲突），KD-4 补充
   形状在案。

## 授权记录（C 档第 3 停 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 + M3/M4
  全系 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（worker 执行 + 双重验收
  编排 + 终验 + 本 VALIDATION 同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`.work/config.toml
  [gsd] paused=false / auto=true` 全程未动，dual_acceptance=true 在册）；用户晨审
  可推翻本签核（推翻 = M6-1 签核作废回退，已交付面与三段执行/验收证据不受影响；
  翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-14 夜批）；**doc-only——零源码
  diff**（`git status` 对表 = 本批全 docs；工作树既有 untracked 三件属兄弟 retro 批，
  本批零触碰）。
- **呈报裁决点（禁静默）**：①Manual C 行目测补执行归属（M6-5 顺路 or 裁销）；
  ②孤儿 fixture 清偿归属（M6-5 or M4-1 侧修复批）；③legacy 只读回退面立项与否
  （挂账 #3，用户诉求驱动）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：MCP-09 行「研究项 A 重开 → M6-1」注记追加 **Delivered 兑现终态**
  （项目级单写者锁 + connect 指引 + GUI 只读回退 + typed 拒绝面四件全落账）。
- ROADMAP：M6-1 行 ✅ 闭环（终态 3689/24skip/0fail）。
- STATE：M6-1 complete + current_phase 翻新 = next M6-2；M6 Ledger 2/7。
- TODO：M6-1 条目落账（[x]）。
- GOAL-STATE：续接点翻新 = **M6-1 closed → M6-2 per-photo process version**。
- 未 push；GUI app / 测试宿主进程零残留（终验批毕已清）。

## 签核

- 六项生效值 + AC7 + AC8 全项 **Delivered**（三列证据齐；数字对账 = 终验亲证基线
  3689/24/0，对账链 3631+53+4+1 精确闭合）。
- `status: validated` + `nyquist_compliant: true`。
- **M6-1（MCP-09-A 项目级单写者锁 + `--connect` 活实例转发）closed**：单 plan 全量批
  三段验收链 PASS / 0 error + 0 minor，终验 `TOTAL|3689/24/0|2157s`；挂账单一清单
  四项（Manual C 行目测 / 孤儿 fixture〔M4-1 挂账 #6 延续〕/ legacy 只读回退面 /
  move 窗口 + TOCTOU 观察项）移交 M6-5 清算批与晨审。
- 晨审裁决项：三项呈报裁决点（见授权记录）+ 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
