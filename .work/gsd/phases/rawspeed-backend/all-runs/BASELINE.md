# Full-Suite Regression Baseline

**结论头：FAIL / 1 failure**（零失败门未过；失败为确定性快照断言，另有一次 rerun 偶发宿主崩溃）

- 工作树 HEAD：`572b6753`（2026-11-25，`main`）；亲核无偏差。
- 运行窗口：2026-11-25 08:19:07 → 09:33:20（墙钟 4453s ≈ 74m13s；脚本 `TOTAL` 累计 4458s）。
- 命令：`Scripts/test-direct.sh --all`（nohup 后台，一次跑完，未中途重启）。
- 开关：`.work/config.toml [gsd] paused = false`、`auto = true`。
- 前置：`Scripts/machine-guard.sh` PASS（G1 heavy=0 / G2 free 65%）；`ps` 无 Lightamer 宿主；构建产物 = `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`（11-04 10:47–11:07），源码零文件新于产物，免重建。
- 全程 `caffeinate -dis` + `machine-guard.sh --monitor 21600` 伴跑；本 lane 自起进程收尾已停（保留用户原有两条 caffeinate）。

## Per-Bundle

| bundle | executed/skipped/failed | peak RSS | 秒 | 参照（2026-11-03） |
|---|---|---|---|---|
| IOP | 841/1/0 | 7068MB | 1013 | 840/1/0 · 6874MB · 987s |
| IOPParity | 584/10/0 | 4828MB | 1743 | 584/10/0 · 4916MB · 1733s |
| Layers | 576/6/0 | 1217MB | 488 | 540/5/0 · 1168MB · 448s |
| Library | 802/4/0 | 742MB | 177 | 797/4/0 · 750MB · 172s |
| Sessions | 289/4/0 | 1204MB | 69 | 285/4/0 · 1266MB · 65s |
| Export | 391/4/0 | 5059MB | 211 | 385/4/0 · 6047MB · 205s |
| App | 1135/6/1 | 2831MB | 757 | 1102/6/0 · 2832MB · 667s |
| **TOTAL** | **4618/35/1** | **7068MB** | **4458** | **4533/34/0 · 6874MB · 4277s** |

- 峰值内存取 `time -l` 的 `ru_maxrss`；最大 7068MB = 8G 运行门的 86.3%，无 MEMFAIL。
- 无 ANE-DEGRADED、无 `terminated abnormally`/`Restarting after unexpected exit`（全套首轮）、无 watchdog/RSS-KILL（monitor 日志 0 条）。
- `memory_pressure` 最低观测 33%（App 段），未触 15% 停跑线；测试宿主单实例 RSS 最大 7.1GB，未触 9GB 线。

## 与参照的差异

参照 = `.work/gsd/phases/m9-2-bwspectral/all-runs/m92-bwpack-all2.log`（2026-11-03，TOTAL `4533/34/0`，7 bundle；`M9-2-SUMMARY.md` 记其 HEAD 为 `5bb31915`，该 SHA 不在当前历史——历史重写/剪枝，故以日志 + SUMMARY 记载为参照）。

执行数 **+85**、跳过 **+1**、失败 **+1**，逐域归因（`git diff 593e5158..HEAD` + `Project.swift` 目标归属亲核）：

| 域 | Δ executed | 归因 |
|---|---|---|
| IOP | +1 | `V50OrderTests` +1（SM `b5db6738` v50 46.7 席位钉） |
| IOPParity | 0 | `SpectralDualArmGoldenTests` +1−1（`323ffeb8`，净 0） |
| Layers | +36（另 +1 skip） | `SpektraFilmTests` 15（含 1 RSS 探针默认 skip）+ `SpektraBridgeTests` 12 + `SpektraTilePolicyTests` 4 + `FilmHistoryTests` 2 + `FilmLegTests` 2 + `LayerCoreTests` 1 |
| Library | +5 | `FilmSidecarTests` +3 + `PresetsStoreTests` +2 |
| Sessions | +4 | `ThumbnailStripTests` 4（新文件） |
| Export | +6 | `ExportFilmChainTests` +4 + `QuickLookFilmTests` 2（新文件） |
| App | +33 | `WorkspaceLegacyTests` 9 + `PipeCoordinatorLegacyTests` 8 + `RegistryFilmModuleTests` +7 + `McpFilmTests` 3 + `ProcessMigrationGateTests` 2 + `FilmPanelTests` 5 + `FilmCoordinatorTests` 2 + `GradeCatalogTests` 1 − `FilmCardTests` 4（退役） |

跳过数 +1 = Layers 的 SpektraFilm RSS 探针（默认 skip）；其余域跳过数与参照逐位一致。耗时 +181s（+4.2%）与执行数增量同向；IOP 峰值 +194MB 在 SPIKE 注记的 ±3% 运行方差内（6874×1.03 ≈ 7080MB）。

## 失败（确定性）

- 测试：`FilmPanelSpectralUITests.testPanelControlInventoryMatchesTheFrozenSnapshot`
- 域：App；位置 `Tests/LightamerTests/FilmPanelSpectralUITests.swift:253`
- 断言：`XCTAssertEqual(inventory, frozenControlInventory)` 失败；对称差 =
  `["film.convert.cancel", "film.convert.sheet", "film.convert.confirm", "film.convert.button"]`
- 根因：`a88eb770`（2026-11-04，SM convert row）在 `App/Sources/Lightamer/UI/Shell/FilmPanelView.swift` 新增上述 4 个标识符，冻结清单（47 id）未同步。
- 稳定性：App 域定向重跑（09:35:35 起）该测试以逐位相同的 4-id 差再失败 → **稳定复现，非偶发**。未修（本 lane 只跑不修）。

## 重跑异常（偶发）

- `Scripts/test-direct.sh --bundle App`：快照测试复跑失败后，宿主于 09:43:02 在 `FilmPanelTests.testModuleLegReadsTheInstanceRecord` 起跑期间崩溃（`time` 报 `command terminated abnormally`，exit 139），verdict = crash → BUNDLE 0/0/0（L055 计数置零），446s，peak 2831MB。
- 崩溃报告：`all-runs/Lightamer-2026-11-25-094309.ips`；`EXC_BAD_ACCESS / SIGSEGV / KERN_INVALID_ADDRESS`，faulting thread = `com.apple.root.user-initiated-qos.cooperative`，栈顶 `_swift_release_dealloc` ← `SpektraFilmModule.process` ← `ModuleBox.processErased` ← `PixelPipe.processRec` ← `LayerCompositeDriver.composite`。
- 定性：**偶发**——首轮 App 完整跑完 1135 测试（仅上述 1 失败，无崩溃）；rerun 才出现。是否与并发路径（cooperative queue 上的 refcount 竞争）相关未验证，未修。
- 依纪律未再重跑（全套一次 + 问题域一次已用尽）。

## 异常事件

- `App` 日志启动期有 `sandbox_extension_issue_file_to_process failed ... Operation not permitted` 一行；测试继续执行、无关联失败，仅登记。
- 未出现整机内存压力事件：swap 占用为既有其它进程（未干预）。

## 收尾

- 无残留测试宿主（`ps` 复查仅本 lane 的 omp 自身）；monitor 与本次 `caffeinate` 已停；用户原有两条 `caffeinate` 未动。
- 日志与证据（不提交，仅本地）：`baseline-all.log`、`app-rerun.log`、`app-rerun-detailed.log`、`monitor-baseline.log`、崩溃 `.ips`。
- 产品树零改动；未 push；issue 只读。

## 未验项

- App rerun 因崩溃未跑完：崩溃后的其余 App 测试在 rerun 中的表现未验；崩溃根因未验。
- 参照 SHA `5bb31915` 与当前历史的对应关系不可考（该对象不存在），执行数对账以日志逐 bundle 值为准。
