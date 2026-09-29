# M2-2-2 SUMMARY — 导入管线（三方式 + 过滤加固 + 最小功能 UI + 项目开关面）

> Plan M2-2-2 收口（2026-09-29）。执行 = ZCode subagent worker；4 任务提交 + 本收口提交，未 push。
> 裁决正本 = `M2-2-CONTEXT.md`（D-M2-2-CONTEXT-1..12；OQ-4/5/12 与 fixture 合成口径未重开）；
> P1 交付缝消费 = `M2-2-1-SUMMARY.md` 常量钉死清单（LibrarySchema 白名单/排除表/Media 常量、
> ProjectFileStore withWriteBatch 缝、ExifSearchIndexer fillMetadata/rebuildFTS 缝、StableHash）。

## 提交账

| 任务 | Commit | 内容 |
|---|---|---|
| T1 | `b77c677` | ImportFilter（select 纯函数 + ImportRejection typed 三因 + ImportMode/ImportModeChoice/ImportDefaults 三键注入宿主）+ ImportFilterTests 13 |
| T2 | `b2da780` | ImageLinker（kind0/1/2 resolve + pathMissing/volumeAbsent 两形态 stale + relinkRecord + volumeUUID/volumeRoot/relativePath）+ ImageLinkerTests 15 |
| T3 | `c6eee61` | ImportService（scan→plan→per-file executor；move rename-first/cross-volume verify-then-remove 红线；copy verify+skip+-1 避让；link kind 行；sidecar ⑤ 随迁+回滚；StepResult 计数；进度/取消）+ ImportServiceTests 10 |
| T4 | `b30d8e5` | LibraryProjectController（create/open/recent/backup/moveProject + containment 守卫 + import 编排）+ ImportModeDialog + ImportProgressView + LightamerApp 接线 + LibraryProjectControllerTests 6 |
| T5 | 本提交 | SUMMARY / DECISIONS / GOAL-STATE 续接点 / LESSONS L039（docs-only，零代码） |

## 测试终值

**全套 1995 / 11 skip / 0 fail**（终跑 Debug，`Scripts/test-direct.sh`）。

- 基线 1951（M2-2-1 验收后终态）+ 新增 44 = 1995：ImportFilterTests 13 + ImageLinkerTests 15
  + ImportServiceTests 10 + LibraryProjectControllerTests 6。
- 11 skip = 既有基线 skip 原样（无新增 skip）。
- 每任务全套独立跑全绿：T1 轮 1964（697.1s）→ T2 轮 1979（708.6s，经 2 轮 flake 归因）→
  T3+T4 轮 1994（753.3s，当轮 ImportServiceTests 9 条，回滚测试后终跑 1995）。
- **flake 归因（T2 闸门轮，在案域）**：`LayerE2ERoundTripTests.testRealRAWRoundTrip` ——
  第 1 轮启动即 SIGTRAP（host exit 133）、第 2 轮 3 断言 fail（undo/reorder 序）、隔离复跑 ×2
  全绿、第 3 轮全套 0 fail——GOAL-STATE 在案「相邻域负载型 flaky 留观 Phase 15」同域新形态
  （crash 形态首次记录），非本 plan 改动面（该测试不经 Library 域）。

## AC 总表（11/11 全绿）

| # | AC | 机检证据 | 状态 |
|---|---|---|---|
| 1 | AC①：白名单最后后缀精确匹配、case-insensitive（`photo.ARW.xmp` 拒 / `photo.arw` 收 / 无后缀拒 / 非白名单拒） | ImportFilterTests.testWhitelistAcceptsRawAcrossCaseMatrix / testDoubleExtensionSidecarRejectedByLastExtension / testNoExtensionAndNonWhitelistedFormatsRejected / testLastExtensionSemanticsDocumented（`raw.xmp.arw` 收的语义钉） | ✅ |
| 2 | AC②：五类 sidecar + 隐藏文件全拒；配置无法放行 sidecar | testAllFiveSidecarExtensionsRejected / testDotPrefixHiddenRejected / testFinderHiddenFlagRejected（真实隐藏 flag 临时文件）/ testConfigurationCannotRe_admitSidecar（白名单含 xmp 仍拒） | ✅ |
| 3 | AC③：合成 C1 Session fixture 导入数 == RAW 数（7） | testC1SessionFixtureImportsExactlyTheRawCount：盘面 16 文件（6 ARW+6 ARW.xmp+2 tif+1 hidden+1 子树 ARW）→ items 7、rows 7、rejected 分类 6 sidecar / 2 whitelist / 1 hidden、Media 树 13 文件（7 ARW + 6 xmp 随迁） | ✅ |
| 4 | move：同卷 rename；跨卷 copy→verify→删源；**verify 失败源文件仍在 + 无行**（红钉） | testMoveSameVolumeRenamesAndSidecarsRideAlong / testMoveCrossVolumeVerifyFailureNeverRemovesSource（注入腿：源字节原样、行 0、failed 1、Media 空）/ testMoveCrossVolumeSuccessRemovesSourceOnlyAfterVerify | ✅ |
| 5 | copy：逐文件校验（尺寸+FNV-1a）+ 重复跳过 + 同名异内容 `-1` 避让 | testCopyDuplicatesSkipAndNameClashAvoids（二次导入 skippedDuplicates 1 且零新行零拷贝；异内容 → `DSC00001-1.ARW`） | ✅ |
| 6 | link：源不动、kind/uuid 正确、`.lra` 留原位；stale 两形态 + relink 重建 | testLinkLeavesSourceAndSidecarInPlaceWithKindRow（kind1+uuid+fileIdentifier 同文件 resolve）+ ImageLinkerTests 15（三形态 resolve、两 stale、relink、拼写钉） | ✅ |
| 7 | sidecar 随迁⑤：move/copy 随行 `.lra`（失败回滚）；link 指向原位 | move 测试（随行 + 失败回滚 home 腿）/ testCopySidecarFailureRollsBackPlacedBytes（sidecar 目的地被占 → failed 1、已拷字节回滚、零行、源原样）/ link 测试（原位） | ✅ |
| 8 | 进度快照单调 + per-file 取消无幽灵行；EXIF 物化列填充 | testCopyProgressIsMonotonicAndCompletes（processed ≤ total 全序列 + completed 7/7）/ testCancelAtPerFileCheckpointLeavesNoGhostRows（cancelled、rows==placed==2）/ testImportFillsExifMaterializedColumns（合成 JPEG+EXIF 名为 .ARW：camera_make/model、iso、focal、aperture、capture_date、折叠词 iso400/testcam） | ✅ |
| 9 | recent 去重/上限/清扫；默认复制 + remember 语义；backup 透传；moveProject 整目录搬移后 kind0 resolve 命中（verify 失败源目录原样在） | LibraryProjectControllerTests 6：testRecentDeduplicatesMovesFrontAndCapsAtTen / testPruneMissingRecentsDropsDeadPaths / testBackupProjectPassthroughProducesOpenableCopy / testMoveProjectSameVolumeRenamesAndKind0Resolves（新位 kind0 命中 + recent 翻新）/ testMoveProjectVerifyFailureLeavesSourceProjectIntact（typed verifyFailed + 源目录原样 + 原位 reopen）/ testDialogDefaultFaceDefaultCopyRememberGateAndSingleShot | ✅ |
| 10 | 全套回归 0 fail（基线 + 本 plan ≈ +25..35） | 1995/11skip/0fail（+44，见上；预估 25..35 实际 44 = 粒度细分，判据 0 fail 满足） | ✅ |
| 11 | diff 边界 == 申报文件集；`Session/` 域零改动 | `git diff --name-only 74c6915..HEAD` = 恰 11 文件（6 新建源 + LightamerApp.swift 修改 + 5 新建测试）；Session 域 diff 空 | ✅ |

## Manual-Only 观察项（不入自动验收）

1. **真实 C1 Session 目录复跑**（用户盘 `Capture/RAW` 样张——版权，自动验收用合成 fixture
   替代；结构保真已覆盖「文件数翻倍」缺陷形态）。建议 M2-3 GUI 验收轮顺带真目录导入一次。
2. **导入吞吐软指标 ≥100 张/min**（P3 基准复测口径）。v1 verify 哈希为全量 `Data(contentsOf:)`
   内存读——大文件（100MP+）流式哈希是已知优化点，量测后若不达标立优化项。
3. **kind1 volumeIdentifier 真实外置卷稳定性**（插拔周期/跨 mount 是否恒定——temp 环境仅逻辑测；
   若实测不稳，「volumeAbsent」误报面需换 APFS volume UUID 读取通道）。

## 偏差与说明（详版见 DECISIONS）

1. **测试数 44 > 预估 25..35**——粒度细分（AC①大小写矩阵逐条 / stale 两形态分测 /
   recent 三面分测），plan 点名的每个测试面都在；0 fail 判据满足。
2. **扫描器拼写免疫重构**（firmlink 发现）—— enumerator/contentsOfDirectory 解析
   `/var`→`/private/var` 而 URL 保留原拼写，前缀裁剪不可靠；改为 lastPathComponent
   逐层积累的相对分量扫描。教训落 L039。
3. **`setUUIDProbe` 测试缝新增**（plan 只列 verifyStrategy 缝）——单卷测试机不可达跨卷腿，
   注入 volume 探针强制；Controller 侧镜像同缝。
4. **moveProject containment 守卫**（生产加固）——目的地在源内/源在目的地内 typed 拒绝
   （moveItem 自嵌套 hazard，测试暴露后加固）。
5. **App 侧 `ImportService` 撞名**——`Session/ImportService.swift`（M1 面 enum）已存在，
   控制器以 `LightamerCore.ImportService` 模块限定消歧。
6. **字符串 verbatim**——新增 UI 面全部 `Text(verbatim:)`，String Catalog 零 churn
   （diff 边界洁净）；zh 文案随 M2-3 UI 壳批落地。
