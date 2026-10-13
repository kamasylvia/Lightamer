# M6-1-01 ACCEPTANCE-FINAL — 最终独立验收（2026-10-14 夜，零共享上下文 subagent）

**结论头:`PASS / 0 error + 0 minor`（open；两处 error 级在案项均已在批内清偿,见「发现与处置」）**

- 验收树 = `908526fe`（= 第一路 PASS 树 `0f6bdcd7` → 回溯 docs 批 → **本批 M-OMP-4
  修复 `908526fe`**）；全套亲跑数字、两段合并审计、交叉影响判定、红线机检全部
  独立亲证,不轻信任何在案报告。
- 双重验收链记录:第一路 zcode PASS（`M6-1-01-ACCEPTANCE.md` 第一路节）→ omp
  二次验收**实际执行但未及正式落账**（GUI 走查 8 截图 2026-10-13 15:33-15:39 在
  `.work/gui-acceptance/m6-1/omp/`,M-OMP-4 发现随附工作树未提交修复）→ 本路
  = 最终独立验收,吸收 omp 走查证据与 M-OMP-4 发现,出终态。

## 一、全套独立复跑（亲跑,2026-10-14 00:25-01:01）

`caffeinate -dis Scripts/test-direct.sh --all`,**TOTAL|3689/24/0|2157s,exit 0**:

| bundle | 实测 | 峰值 RSS | 预期 | 判定 |
|---|---|---|---|---|
| IOP | 684/1/0 | 6797MB | 684/1/0 | ✅ 精确 |
| IOPParity | 460/3/0 | 6822MB | 460/3/0 | ✅ 精确 |
| Layers | 466/4/0 | 1176MB | 466/4/0 | ✅ 精确 |
| Library | 654/4/0 | 616MB | 654/4/0 | ✅ 精确 |
| Sessions | 279/4/0 | 1628MB | 279/4/0 | ✅ 精确（E1 seat 修复规模化在证） |
| Export | 353/4/0 | 5979MB | 353/4/0 | ✅ 精确 |
| App | 793/4/0 | 2832MB | 793/4/0 | ✅ 精确（= 792 + M-OMP-4 1 法） |
| **TOTAL** | **3689/24/0** | 全 <8G 门 | 3689/24/0 | ✅ 算术闭合 |

- 对账式:**3631（基线）+ 53（worker 十提交）+ 4（omp golden 四法）+ 1（M-OMP-4
  新法）= 3689**;零 MEMFAIL、零 crash、零 no-total-line（L055 双保险全过;
  日志正本 = `acceptance-logs/full-all-final.log`）。
- 定向:FaceTests **19/0/0**（App bundle,本批提交前亲跑——14 原始 + 4 omp +
  1 M-OMP-4 全绿）。
- 孤儿 fixture `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra` 跑前已删;
  **全套轮中被 TIFF 栅格测试再生成**——M4-1 挂账 #6（测试泄漏 sidecar）仍活,
  跑后再删,挂账不闭（非本 plan 范围,如实登记）。

## 二、两段合并审计

### 原始段（10 commits `4d345a6f..a18cfb82`,worker 批）

第一路 ACCEPTANCE 的 PASS 结论**在当前 HEAD 逐项复核成立**:

- **T1 SingleWriterLock 五态**（`LightamerCore/Sources/Foundation/SingleWriterLock.swift`
  全文读码）:五态头注 verbatim 继承 McpEndpointFile、payload v1 冻结拼写、
  flock per-open-file-description 同进程二 fd 语义在册、probe=try-flock 即释、
  pid 仅诊断面;8 法在库（LIB 654 轮含内全绿）。
- **T2 项目锁**（`ProjectFileStore.swift` 读码）:`acquireProjectLockIfRoled`
  role-nil 零触 + 锁 nil 幂等;heldByOther 在 pre-migrate 快照轮换**之前** typed
  抛;close = checkpoint(TRUNCATE) → handle close → unlock（WAL 尾安全序）;
  openReadOnly E2 三岔;withWriteBatch 断路。10 法在库全绿。
- **T3 McpEndpointLock 薄封装**:McpHostTests 原样全绿（App 793 轮含内）= 行为
  零 diff 门持续成立。
- **T4/T5 GUI 面**:冲突对话框三选（FaceTests 前半 6 法）、三 seam（EditorState
  原 7 guard + ExportState 两 enqueue + withWriteBatch）、banner AX、顶栏
  export/yiyin `.disabled`（WorkspaceHostView :610/:623 原样）——14 法全绿。
- **T6 无头仲裁**:McpProjectArbitrationTests 9 法（序 A/A'/B + 双跑确定性 +
  五态③ writer 臂 + 旗标校验 + 无 project 冒烟）App 轮全绿。
- **T7 MCP typed**:五调用点 HEAD 读码核对在位（export_image :314 / apply_params
  :557 / culling write-five :355+:576 / match_color attach :416）+ 8 法全绿;
  20 工具封闭集快照族零 diff（McpRegistrySnapshotTests/McpFinalSnapshotTests
  App 轮含内亲证）。
- **T8 o-2 搭车**:ColormatchResolverBox NSLock holder 读码（sharedLock +
  sharedInstance nonisolated(unsafe) + 锁内 getter + replaceShared）+ 三写点
  （ColorMatchService :138/:309、MatchColorToolset :454）+ 裸 `shared =` 残留
  全仓 **0**;4 法全绿（IOPP 460 轮含内）。
- **T9 红线自证**:本路全部重跑（见第四节）,结论同第一路且范围延展至今 HEAD。

### omp 发现段（`e2a493c0` + `f42dc13c`/`ed6ca3e7`/`cf36190a`/`f8e0671c`;兄弟修复 `5d814958`）

- **guard 家族 7→13 精确命中**（EditorState grep 亲数）:原 7（recordChange :211 /
  commitMaskEdit :750 / commitLayerEdit :839 / commitLayerStructure :1117 /
  commitRetouchEdit :1238 / recordDrtChange :286 / recordFilmChange :310）+
  omp 补 6（installVersionChain :138 / installMergePaste :342 /
  installOverwritePaste :358 / performUndo :388〔拒 false〕/ performRedo :400
  〔拒 false〕/ performJump :414〔no-op〕）。
- **jumpToHistory 门读**（PipeCoordinator :1860）:blocked jump 在
  scheduleSidecarWrite 前返回——堵 touchActive 的 `.lra` updatedAt 尾写
  （plan 处方外的一行,DECISIONS D-11 申报核实）;undo/redo 由 EditorState
  false 早退承载（PipeCoordinator undo/redo guard 链读码核实）。
- **VersionCoordinator coordinator 级门**:injectable `projectReadOnlyGate`
  （nil = 可写,零 diff 缺省）+ `isReadOnly` Observable 追踪投影 + 六写命令
  全集过门（createFromScratch :194 / branchFromCurrent :219 / pasteChain :262 /
  switchTo :303 / rename :321 / remove :338）,typed no-op + logger 静默形。
- **paste batch 门**:`pasteToSelection` 入口 `batchPasteBlocked` + toast 拒
  （复用 banner 键零新键）;`batchPasteBlocked`/`readOnlyPasteToast` internal
  纯函数可测缝在位。
- **Edit 菜单四处 `.disabled || isReadOnly`**:undo :1675 / redo :1680 /
  paste_adjustments :1695 / paste_partial :1700 亲数;jump 面板无此要求
  （performJump guard 兜底,plan 钉死）一致。
- **VersionsPanelView 八处 `.disabled(versions.isReadOnly)`**（header/emptyState
  四钮 + 行 tap + rename/remove 菜单 + remove 确认）与 D-11 表一致。
- **golden 四法**（FaceTests :409-:520）读码:①undo/redo/jump no-op + canUndo/
  canRedo 不翻栈 ②版本六命令连拒 + 装链零触 ③双 paste install no-op
  ④batch 谓词 + toast face——断言锚 setup 后合法态,gate 泄漏无。
- **`5d814958` seat registry**（SessionCoordinator）读码:同 root 同进程共享活
  锁对象 + holders 计数、末座起立才 unlock、跨进程仲裁/typed 冲突/ioError
  降级不变;Sessions 279/4/0 本轮再证。

## 三、交叉影响判定（omp 批 vs 原始段）

- **omp 批触面**:EditorState / PipeCoordinator / VersionCoordinator /
  LightamerApp / VersionsPanelView / FaceTests / BUNDLE-MAP / PLAN——逐 commit
  diff 亲核为**纯 additive**:f42dc13c 仅 +6 guard 行（原 7 行零改零删）;
  ed6ca3e7 装配点为第三 gate 追加（原两 gate 闭包零 diff）。
- **原始段机制文件**（SingleWriterLock / ProjectFileStore / McpEndpointFile /
  McpServerController / McpToolRegistry / SessionIndexController）与 omp 批
  **零交叠**（`5d814958` 只触 SessionCoordinator,与 omp 文件集不相交;commit 序
  交错无冲突,DECISIONS D-11 并发注记核实）。
- **FaceTests 19 法构成** = 原始 14（T4 前 6 + T5 后 8）+ omp 4 + M-OMP-4 1,
  逐法名单亲数一致;**BUNDLE-MAP 一致性**:六文件合计 58 法（8+10+9+8+19+4）,
  本批同步 18→19 行 + 注记（f8e0671c 的 6→18 后 M-OMP-4 尾差已闭）。
- 快照族/G4 parity/宿主锁零回归由 App 793 全量轮含内亲证（AC7 零回归门）。

## 四、红线机检（全部亲跑,26fd6bf0〔worker 起点〕..HEAD）

| # | 检查 | 结果 |
|---|---|---|
| 1 | `grep -rn "\.runModal(" App/Sources` | **0** ✅ |
| 2 | `LibrarySchema.swift` + `Sidecar/` diff（schemaVersion 面） | **0 行** ✅ |
| 3 | `Project.swift` diff | worker 段 6 行纯测试数组增行,dependencies 块零触,零新 SPM（`.package`/`url:` 增行 = 0） ✅ |
| 4 | 封存面零 diff:HistoryStack / HistoryHash / V50Order / DrtRecord / Registry（Core+IOP） / PipelineDocument / NodeGraphCommand / AIWorkerProtocol / LayerEditingState | 全 **0 行** ✅ |
| 5 | 全部 `*.metal`（含 Aces2Kernels.metal） | **0 diff** ✅ |
| 6 | 六格式导出矩阵（ExportFormatSpec/ImageIOEncoders/WebPEncoder）+ YiyinExportSettings | **0 diff** ✅ |
| 7 | 随机源门（`SystemRandomNumberGenerator|srand\(|arc4random|\.random\(`,App+Core+IOP 生产码） | **0 命中** ✅ |
| 8 | QuickLook / Spotlight appex | **0 触碰** ✅ |
| 9 | zh-audit `--check` | **PASS**（source 1661 / catalog 1900）;M6-1 十键全入册;xcstrings diff 自 26fd6bf0 = **纯插入**（删 0 行/增 170 行） ✅ |

## 五、发现与处置

1. **M-OMP-4（error 级;omp 二次验收发现 → 本批清偿 `908526fe`）**:create/
   move 三条生产打开路径缺 role——新建/移动后项目无锁常驻,第二实例
   `open(role:)` 无感知获写 = 双写。修复 = createProject 传 `.gui` + move 两
   重开腿（失败腿旧位回开/成功腿新位重开）传 `.gui`（move 序 = close→move→
   reopen,窗口五态③注记前提自此成立）;新 golden
   `testCreateAndMoveReopensHoldTheWriterLock`（create 后异实例 typed-held +
   move 后新位 typed-held + **新位锁 probe 实判**）。终验批并修正其测试稿
   一处空洞断言（原稿 probe 的是 harness Widget 锁且 `|| fileExists` 恒真;
   改为对新包真实锁 probe 的 `XCTAssertFalse`）。验证 = FaceTests 19/0/0 +
   全套 App 793/4/0。
2. **Manual-Only C 行（无头 connect 指引终端目测）未有人驱执行**（非阻塞）:
   omp 走查批产出 A/B 节截图 8 张;C1..C4 语义面由
   McpProjectArbitrationTests decode 级全覆盖（序 A/A'/B + writer 臂 + 降级）,
   仓库根遗留 `c1_stderr.txt` 一次旗标校验探针残迹（内容 = openFailed 预期
   形,已清）。**目测行缺口如实登记,机检覆盖在案,不阻签核。**
3. **孤儿 fixture 再生成**（非阻塞）:全套轮复活
   `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`——M4-1 挂账 #6（测试
   sidecar 泄漏）仍活,本批跑后再删;建议 M4-1 侧后续清偿。
4. **A/B 走查截图目检**（本路补验）:A1（三选 sheet + 真 pid 92632）/A2（常驻
   banner 同 pid + 图库可浏览）/B（只读编辑面 banner 在位）三张与 MANIFEST
   A1/A2/B 预期逐项相符。

## 六、M6-1-01 终态意见

**可签核。** 两段执行成果合并后:AC1..AC8 逐条兑现（AC4 的 omp E-OMP-1 缺口
已由 omp 批补齐并 golden 四法钉死;AC8 数字门以 3689 终值精确闭合）;omp 二次
验收的唯一 error 发现（M-OMP-4）已修复并回归;红线九域机检全绿;全套
3689/24/0 零 MEMFAIL。M6-1 VALIDATION 可进;建议签核批同登 M4-1 挂账 #6
（fixture 泄漏）与 Manual C 行目测残留（低风险,机检已覆盖）。

—— 最终独立验收 subagent（零共享上下文）,2026-10-14 01:0x
