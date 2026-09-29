# M2-2-2 ACCEPTANCE — 导入管线独立验收报告

> 验收 = 独立 subagent（2026-09-29）。对照正本：`M2-2-2-PLAN.md`（checker 修正版：E5 =
> moveProject 整目录搬移）+ `M2-2-CONTEXT.md` D-M2-2-CONTEXT-1..12 + M2-2-1 交付缝。
> 执行方声明 5 commits（`b77c677`/`b2da780`/`c6eee61`/`b30d8e5`/`18a5189`），逐 commit
> 实测核对；全套测试独立复跑（执行方进程外）。

## 结论

**PASS / 0 error + 0 minor**（3 条 observation 登记不计数，见 Findings）。

- 复跑 = 声明：`caffeinate -dis Scripts/test-direct.sh` → **Executed 1995 tests,
  with 11 tests skipped and 0 failures (0 unexpected) in 716.759s**（host exit=0；
  脚本 OK 行在案）。声明终值 1995/11skip/0fail 逐值一致；本轮零 flake（在案
  LayerE2E/QuickLook 计时域本轮全绿）。
- 分类计数核对：ImportFilterTests **13** + ImageLinkerTests **15** +
  ImportServiceTests **10** + LibraryProjectControllerTests **6** = **+44**；
  1995 = 基线 1951（M2-2-1 验收终态，GOAL-STATE 在案）+ 44。✅

## 边界核查（AC #11）

- `git diff --stat 74c6915..18a5189` = **恰 15 文件 / +3129 行、零删改**：6 新建源
  （ImportFilter 208 / ImageLinker 197 / ImportService 588 / LibraryProjectController
  435 / ImportModeDialog 103 / ImportProgressView 58）+ LightamerApp.swift 修改
  （+173 纯新增）+ 5 新建测试（196/232/529/248 + FilterTests 内 ImportDefaults 面）+
  4 docs（SUMMARY/DECISIONS/GOAL-STATE +1/LESSONS +7）。
- **Session 域 diff 空**（`grep session` 零命中）；`Pipe/`、`Sidecar/`、`Metal/`、
  `Decode/` 红线域零触碰。✅
- 5 commit 各自边界：T1 2 文件 / T2 2 / T3 2 / T4 5 / T5 4（docs-only），subject 全
  英文 Conventional、body what+why 在案；与 plan 提交约定一致。
- `git status` 滞留 = `.work/gui-acceptance/`（并行会话产物）+ `.work/culling-cli/`
  等 untracked——均非本 plan 面，不属执行方泄漏。

## 逐 AC 表（11/11 全绿）

| # | AC | 独立核对证据（file:line） | 判 |
|---|---|---|---|
| 1 | AC① 白名单最后后缀精确、case-insensitive | `ImportFilter.swift:82`（`pathExtension.lowercased()` 天然取最后后缀）+ `:89` 精确匹配；`ImportFilterTests` testWhitelistAcceptsRawAcrossCaseMatrix（ARW/arw/ARw/dng 收）/ testDoubleExtensionSidecarRejectedByLastExtension（`photo.ARW.xmp` 拒）/ testNoExtensionAndNonWhitelistedFormatsRejected（无后缀+jpeg/tif/jpg/png 拒）/ testLastExtensionSemanticsDocumented（`raw.xmp.arw` 收的语义钉） | ✅ |
| 2 | AC② 五类 sidecar + 隐藏全拒；配置不可放行 | 判定序 ② 先于 ③（`ImportFilter.swift:85-90`）；排除表硬编码（`LibrarySchema.swift:216`）；testAllFiveSidecarExtensionsRejected / testDotPrefixHiddenRejected / testFinderHiddenFlagRejected（真实 isHidden flag 临时文件）/ testConfigurationCannotRe_admitSidecar（白名单 union xmp 仍 .sidecar 拒） | ✅ |
| 3 | AC③ 合成 C1 fixture 导入数 == RAW 数 | `ImportServiceTests.swift:79-105` fixture（6 ARW+6 .ARW.xmp+2 tif+1 hidden+1 子树 ARW = 16 盘面文件，全合成字节）；`:160-190` 断言 items==7、rows==7、rejected 6/2/1 精确、Media 树 13 文件（7 ARW+6 xmp 随迁）——「文件数翻倍」缺陷形态机检复现 | ✅ |
| 4 | move rename 优先；跨卷 copy→verify→删源；**verify 失败源不删+无行**（红钉） | 红线结构化（`ImportService.swift:386-405`：copy→verifyPlacement→migrateSidecars→然后才 removeItem；失败腿 `rollbackPlaced` 不触源）；红钉 testMoveCrossVolumeVerifyFailureNeverRemovesSource（uuidProbe 强制跨卷 + verify 注入 false → 源字节原样+sidecar 在、行 0、Media 空、failed 1）+ 同卷 rename 腿 + 成功腿三测全绿 | ✅ |
| 5 | copy 逐文件校验 + 重复跳过 + `-1` 避让 | `defaultVerify` = 尺寸+FNV-1a（`ImportService.swift:443-449`，`StableHash`）；testCopyDuplicatesSkipAndNameClashAvoids（二次导入 skippedDuplicates==1 零新行零拷贝；异内容 → `DSC00001-1.ARW`） | ✅ |
| 6 | link 源不动、kind/uuid 正确、`.lra` 原位；stale 两形态 + relink | testLinkLeavesSourceAndSidecarInPlaceWithKindRow（kind==1、uuid==project 卷、`fileIdentifier` 同文件 resolve、Media 空）；ImageLinkerTests 15 全绿（kind0/1/2 resolve、pathMissing/volumeAbsent 两形态、relink 重建、uuid 不可得 typed 降级 kind2、firmlink 拼写钉） | ✅ |
| 7 | sidecar 随迁⑤（失败回滚） | move 测试（rename 随行 + 失败回滚 home 腿 `ImportService.swift:376-385`）；testCopySidecarFailureRollsBackPlacedBytes（sidecar 目的地被目录占 → failed 1、已拷字节回滚、零行、源原样）；link 原位 | ✅ |
| 8 | 进度单调 + per-file 取消无幽灵行；EXIF 物化 | testCopyProgressIsMonotonicAndCompletes（全序列 processed≤total + completed 7/7）；testCancelAtPerFileCheckpointLeavesNoGhostRows（actor 重入点确定，cancelled、rows==placed==2）；testImportFillsExifMaterializedColumns（合成 JPEG+EXIF 名 .ARW：make/model/iso/focal/aperture/capture_date/折叠词 iso400+testcam） | ✅ |
| 9 | recent 三面 + 默认复制/remember + backup 透传 + moveProject 整目录搬移 kind0 命中（verify 失败源目录原样） | ControllerTests 6 全绿：testRecentDeduplicatesMovesFrontAndCapsAtTen（cap 10/去重移前/跨实例持久）/ testPruneMissingRecentsDropsDeadPaths / testBackupProjectPassthroughProducesOpenableCopy（行保真）/ **testMoveProjectSameVolumeRenamesAndKind0Resolves**（旧位消失 + 新位 `.lalb`+Media 在 + recent 翻新 + **kind0 对新项目目录 resolve 命中** + 行随迁）/ **testMoveProjectVerifyFailureLeavesSourceProjectIntact**（typed verifyFailed + 源目录字节原样 + 半拷回滚 + 原位 reopen）/ testDialogDefaultFaceDefaultCopyRememberGateAndSingleShot | ✅ |
| 10 | 全套 0 fail | 独立复跑 **1995/11skip/0fail（716.8s）**（见结论；预估 +25..35 实际 +44 = 粒度细分，SUMMARY 已声明） | ✅ |
| 11 | diff 边界 == 申报；Session 域零改动 | 见上「边界核查」 | ✅ |

## 五重点核查

1. **M2LIB-03 加固三 AC**：逐条属实——白名单最后后缀精确 case-insensitive
   （`pathExtension` 语义天然「最后后缀」，排除表先于白名单的结构序使 `photo.ARW.xmp`
   落 ②）；排除表硬编码 + 隐藏文件（`.` 前缀 + 真实 Finder flag 双腿）五测机检；
   合成 C1 fixture 断言「导入数 == RAW 数（7）」+ rejected 分类精确 + Media 树逐文件
   断言，缺陷形态（sidecar 翻倍）结构性复现。配置不可放行 sidecar 有专门红测。
2. **M2LIB-07 三方式护栏**：跨卷 verify 失败「源永不删」红钉**为真**——双缝注入
   （uuidProbe 强制跨卷 + verifyStrategy 恒 false）后断言源字节/源 sidecar/零行/
   Media 空/failed 计数五面；remove 调用在源码上位于 verify 通过腿内（结构性红线，
   非仅测试覆盖）。FNV 校验（StableHash 复用）+ 尺寸双验；重复跳过计数控
   （StepResult enum，D7 修复后 skippedDuplicates 不再恒 0）；相对链接 =
   kind1 卷相对 + volumeUUID（挂载点改名免疫语义 + firmlink 双拼写候选 resolve）；
   stale 两形态 typed + relink 数据面在册。
3. **E5 moveProject 整目录搬移**：`LibraryProjectController.moveProject` = close
   （checkpoint）→ 同卷 rename / 跨卷 copyTree（跳 `.lathumbs` 派生物）→逐文件
   verify→删源，红线纪律与 ImportService 同构；containment 守卫双 typed 拒绝
   （目的地在源内/源在目的地内，D6 自嵌套 hazard 加固）+ 同位/已存在守卫；「move 后
   kind0 resolve 命中」AC 实链复钉（新位 resolve + 行随迁 + recent 翻新）。
4. **M1 域零破坏**：Session 域 diff 空声明核实（范围 grep 零命中）；App 侧撞名
   `LightamerCore.ImportService` 模块限定消歧（D4），M1 `Session/ImportService.swift`
   未动。
5. **12 条偏差合理性**：D1 firmlink 三拼写 → 相对分量扫描（构造性论证 + L039 落
   LESSONS，`ImportService.recursiveFiles:227-253` lastPathComponent 逐层积累核实）；
   D2 uuidProbe 缝（单卷机不可达跨卷腿，生产零影响）；D3/D5/D8 文件内聚（plan 未
   单列，边界未越）；D4 撞名消歧；D6 containment（测试暴露后生产加固，正当）；
   D7 skippedDuplicates 计数修复（Bool 返回丢面 → enum，测试捕获后修，正当）；
   D9 快捷键 ⌘N/⌥⌘O/⇧⌘I 对既有表零冲突（本验收独立复点 `LightamerApp.swift:1100-
   1340` 快捷键全表）；D10 tuist 分任务 ×3；D11 `.lathumbs` rename 腿随行（派生物
   无数据危害）；D12 提交序列事故透明记录且终态边界干净（本验收 `--stat` 复核）。
   **全部认可。**

## Findings（observation ×3，登记不计数，不修）

- **O-1** `ImportServiceTests.swift:428-430` 私有 `fileIdentifier(_:)` helper 未被
  引用（同文件断言改内联 resourceValues 后遗留）——测试死代码，cosmetic。
- **O-2** `LibraryProjectController.runImport:263` 在 `importFolder` 返回后立即清
  `importProgress`——completed 快照的 UI 呈现窗口≈0（快照序列含 completed，AC8 不
  要求呈现窗口）；完整后台任务系统 UI 归 M2UIW-06，不属本 plan 面。
- **O-3** link 模式同文件二次导入会重复建行（无重复检测）——M2LIB-07② 重复检测
  字面只钉 copy；link 引用去重语义需求未定义，M2-3 Inspector 引用管理面处置。

## 偏差核查声明核对

- 测试数 44 > 预估 25..35：属实且合理（粒度细分，plan 点名测试面全在，0 fail 判据
  满足）。
- T2 轮 flake 归因（LayerE2E SIGTRAP/3-assert 两形态 + 隔离复跑 ×2 + 干净轮）：归因
  轨迹在 SUMMARY，非本 plan 改动面（该测试不经 Library 域）；本验收复跑全绿，维持
  「在案域留观」。
- Manual-Only 三项（真 C1 目录复跑 / 吞吐 ≥100 张/min 软指标 / volumeIdentifier
  真实热插拔稳定性）：登记于 SUMMARY §Manual-Only，本验收照录（见下表）。

## Manual-Only 观察项（移交后续轮）

| # | 项 | 触发时机 |
|---|---|---|
| 1 | 真实 C1 Session 目录（用户盘 `Capture/RAW` 样张）导入复跑，断言导入数 == RAW 数 | M2-3 GUI 验收轮顺带 |
| 2 | 导入吞吐软指标 ≥100 张/min（100MP+ 全量内存哈希 verify 是已知优化点） | P3 基准复测 |
| 3 | kind1 `volumeIdentifierKey` 真实外置卷热插拔/跨 mount 稳定性（不稳则换 APFS volume UUID 读取通道） | 真实外置卷接入时 |

## 翻账

- `REQUIREMENTS.md` M2LIB-03 `[x]` + Delivered 锚点（过滤加固三 AC 兑现 + 合成
  fixture 裁决注记）；M2LIB-07 `[x]` + Delivered 锚点（三方式护栏兑现 + ④ 对话框
  ImportDefaults 键 + 设置页/Inspector UI 归 M2-3 注记）。M2LIB-05 不属本 plan 不动
  （M2LIB-01 已于 M2-2-1 翻账）。
- 本报告落 `phases/m2-2-library-project/M2-2-2-ACCEPTANCE.md`；GOAL-STATE 续接点由
  orchestrator 收口批更新（执行方已在 :12 声明「未翻账留验收」）。
