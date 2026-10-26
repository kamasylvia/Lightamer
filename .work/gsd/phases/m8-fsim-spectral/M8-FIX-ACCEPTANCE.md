# M8-FIX-ACCEPTANCE — 修正批综合验收 + R5 波报告（2026-10-26）

> 验收对象 = M8-FIX 修正批三 commits（`7422401a` 修复 / `73421ef9` 账本 /
> `3f24584c` 收口）；基线 `c0f1e5a1`；验收 HEAD = `92fb6bcc`。
> 验收员独立实测（不轻信 executor 申报）；证据正本 = 本目录
> `fix-acceptance/`。R5 三件 = 随波验收（D-6 复验 / 导入零行间歇 /
> Vision 漂移复验），每件给结论 + 路由。

## 结论头

**PASS / 0 B + 0 M + 0 m + 3 obs**（M8-FIX 修正批验收通过；R5 三件 =
绿/复现成功/维持登记，各自路由见 §五..§七）

---

## 一、逐 AC 对账（静态，file:line 实证）

| # | AC（DECISIONS/SUMMARY 申报） | 验收实测 | 判 |
|---|---|---|---|
| T2-1 | `closeEditor` 不再 drop process 载体（调用行 + 函数本体删除） | `git diff c0f1e5a1..92fb6bcc -- App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift`：`dropSessionProcessVersions()` 函数（原 :388-390）与 `closeEditor` 内调用行（原 :523）双双删除 | ✅ |
| T2-2 | doc 注释登记偏离（processVersions + closeEditor 双注释） | 同 diff：`processVersions` 注释追加 M8-FIX-1 段（close-保留 + 双守卫零载入腿 + per-path Int 惰性论证）；`closeEditor` 注释登记「The process carrier does NOT drop (M8-FIX-1)」 | ✅ |
| T2-3 | 姐妹三载体（film/DRT/rawOverrides）drop 仍在位 = 移交 M8-3+ 边界 | `closeEditor` 体内 `dropSessionOverrides()` / `dropSessionDrtRecords()` / `dropSessionFilmRecords()` 三行原样在位 | ✅ |
| T3-1 | #7 改写 `testCloseKeepsTheCarrierAndReopensStayIdempotent`（close 保留 + 新装配重开幂等 + legacy 判别腿） | ProcessVersionCarrierTests.swift:442-491（改写体）：close 后 `processVersion(for:) == .current` 断言 + 新装配重开从文件恢复 + legacy 档跨 close 恒 `.legacy`（OQ-1 不被动升级延伸腿） | ✅ |
| T3-2 | #9 新增 `testEnableAfterCloseWithoutReloadKeepsTheMintedGeneration`（生产缝端到端四面断言） | ProcessVersionCarrierTests.swift:521-594：透过 `FilmPanelModel.enableFilm` 生产缝（attachFilmStore 真材料库）断言 ①`documentProcess == .current` ②`migrationAction == .alreadyCurrent` ③flush 后 sidecar 同含 `filmRecord` 与 `process: 2` ④v1 孪生仍 `.migrate`（判别力腿）；ΔN=+1 与申报一致 | ✅ |
| 契约 | AGENTS process 不变量行 + ARCHIVE M6-2 勘误 | AGENTS.md 架构索引 process version 行追加 M8-FIX-1 豁免注记（含姐妹缺口 M8-3+ 指针）；ARCHITECTURE-ARCHIVE.md M6-2 App 面行后追加勘误行（原行不改写，append-only 惯例） | ✅ |
| 申报 | 备选三条否决有据、ΔN=+1 越带下缘申报、姐妹缺口移交 | DECISIONS §二/§四在案；越带申报（单法承载四面断言 + #7 零增量语义移动）与 diff 面吻合 | ✅ |

## 二、diff 审与封存面机检

- **产线面边界**：`git diff c0f1e5a1..92fb6bcc` 全量 9 文件；排除账本
  （.work/**、AGENTS.md）与测试（Tests/**）后**产线改动恰 =
  `WorkspaceModel.swift` 单文件**。范围内另有五件非本批 commit
  （`0a21136c` fixture 供件恢复 / `26cd0705` 样张登记 / `b325d8e8` +
  `92fb6bcc` ColorChecker 批 / `4ddc1439` 排队账）——均已核对无产线面
  交集（`92fb6bcc` 的 Fixtures.swift 改动为注释级，patch 表保持空）。
- **封存面 15 项零 diff**（逐项机检）：DrtRecord.swift / TerminalTailPolicy
  + DrtTailAssembly（内嵌于 PixelPipe.swift）/ PixelPipe.swift / LUT
  kernel（FilmSubRunKernels.metal，含 lut 采样）/ 全部 10 个 .metal /
  DrtEotf.swift / ExportQueueContract.swift / 六格式矩阵（ExportFormatSpec
  于 ExportRecipe.swift · ImageIOEncoders.swift · WebPEncoder.swift）/
  NodeGraphCommand.swift / LightamerSidecar.swift / HistoryStack.swift /
  HistoryHash.swift / PipelineDocument.swift / V50Order.swift /
  GradeCatalog（NodeOwnership.swift）——**全零**。
- **FIX2③**：`LibraryProjectController.swift` 零 diff。

## 三、全套复跑

`Scripts/machine-guard.sh --wait`（G1-G4 过）+ 起跑 ps 清零（Lightamer/
xctest = 0，同链验证）+ `--monitor 21600` 伴跑（全程零 RSS-KILL，收工
kill）+ `nohup disown Scripts/test-direct.sh --all`（build-for-testing 产
物 = orchestrator 预建 20:26 同 DerivedData，未重建）：

**TOTAL `4287/35/0`（3964s，零 MEMFAIL 零 crash）**

| bundle | M8-3 基线 | executor T4 | 本轮 | 判 |
|---|---|---|---|---|
| IOP | 788/5/0 | 788/5/0 | **788/1/0** | 见 obs-1 |
| IOPParity | 529/11/0 | 529/11/0 | 529/11/0 | 逐值同（golden 三件套 + filmRampPlaneHash 哨兵承载） |
| Layers | 507/6/0 | 507/5/0 | 507/5/0 | 逐值同 T4 |
| Library | 778/4/0 | 778/4/0 | 778/4/0 | 逐值同 |
| Sessions | 285/9/0 | 285/4/0 | 285/4/0 | 逐值同 T4 |
| Export | 385/5/0 | 385/4/0 | 385/4/0 | 逐值同 T4 |
| App | 1014/6/0 | **1015/6/0** | **1015/6/0** | 逐值同 T4（含 #9 新法） |

- **executed 4287 与 fail 0 逐值达预期**；skip 35 vs 预期 39 = **−4 全在
  IOP**（5→1），零失败非红，归 obs-1。
- executor T4 五 bundle 残留日志已在覆盖前抢救至
  `/tmp/m8fix-acc-legacy-logs/execT4-*.log`（skips 逐值吻合 DECISIONS 表，
  佐证申报真实性）；其 IOP 日志已被本轮覆盖，skip 差分不可逐法枚举。

## 四、M-1 表型复走（GUI 探针，omp 配方）

探针 = DerivedData Debug 直启 `-la_film_probe <folder>`（stderr 取证）+
pyobjc AX 驱动（AXPress 生产缝 / CGEvent / System Events 菜单）。

| 腿 | 会话 | 链 | 实测 | 判 |
|---|---|---|---|---|
| **疾病链**（原病灶） | pid 86080、88174 两轮独立 | 开图（pristine mint，sidecar=no）→ 生产菜单「返回图库」（closeEditor）→ 面板跨关图存活（omp S1 布局）→ 图库态点「启用胶片模拟」 | 两轮均：commit 落地（启用按钮消失 = 控制面浮现）+ **「更新到当前渲染代」迁移行缺席**（AX 断言窗 6s） | ✅ 表型反转 |
| **干净路**（对照） | pid 84630 | 编辑器态直接启用 | 迁移行缺席 | ✅ |
| **v1 对照腿** | pid 90837 | 真 v1 老档（omp 时代 `/tmp/m8-3-walk/float32-gradient.tif.lra`：`process:1` + filmRecord + schemaVersion 11）导入 | 启用按钮缺席（老档恢复非 pristine）+ **迁移行可见（蓝色「更新到当前渲染代」按钮）** | ✅ 判别力未盲化 |

截图（本目录 `fix-acceptance/`，已逐张识图核验）：
- `m1-a1-editor-film-pristine.png`（编辑器 + Film 页 pristine）
- `m1-a2-library-film-after-close.png`（关图后图库面 + Film 面板共存 = omp S1 布局复现）
- `m1-a-clean-editor-enable.png` / `m1-b1` / `m1-b2-library-enable-after-close-c.png`
  （**关键证据**：关图后启用态——控制面 + readout「M 18.3 · Y 16.7 · ×1.00」
  与 M8-3 登记面逐字同值、**无迁移行、无启用按钮**）
- `m1-ctl-v1-archive-migrate-row-visible.png`（**关键证据**：v1 老档蓝色迁移按钮在位）
- `probe4-spectral-bake-quit-stall.sample.txt` / `probe-gridrows-fail-spin.sample.txt`
  （obs-2/R5-2 采栈证据）

**sidecar 磁盘写入腿**：GUI 面三条路均被仪器/环境面阻断（idle 探针去抖
不自发落盘〔M8-3 MANIFEST 已登记面〕；quit-flush 落在光谱烘焙窗口期
〔`SpectralTcFit.fitCoefficientTable` 分钟级 LM 拟合，sample 在案〕；
「保存 Sidecar」菜单需 Film 页先开而左轨项无 AX 可寻址面）——该断言由
**App bundle #9 测试 in-process 承载**（1015/6/0 在册绿：flush 后 sidecar
同含 `filmRecord` + `process: 2`）。判：核心表型（迁移行可见性 + 载体语义）
直接实证反转，写面经测试承载，**不计缺陷**；仪器面入 obs-2。

## 五、R5-1：D-6 重开项目态复验 — **绿（翻账建议）**

配方照 TODO 407 行：GUI 打开既有项目（recents 重开）→ quit → 重开项目 →
文件>进入编辑器 → 三面 + 40s CPU 采样（`top -l 40 -s 1 -stats cpu`）。

- **视口**：渐变图渲染在位（非黑/非空态；截图 `d6-reopen-editor-state.png`
  识图核验：对角渐变 + 底部缩放条）✅
- **右栏**：完整调整模块列表，「未选择图像」空态缺席（AX 断言）✅
- **filmstrip**：行在位（`filmstrip.row.1`）+ 青色选中框（截图核验）✅
- **CPU 40s**：40 采样 `min=0.0 p50=0.0 max=0.0 mean=0.0`——D-6 病灶
  （AttributeGraph 99.9% spin）**未复现** ✅

**路由：翻账建议**——TODO 407 行核销 + LESSONS 注记「F0'-prod 壳交接
（SwiftUI App lifecycle → NSApplicationDelegate）消解 D-6 H2 载体：
macOS 27.0.1 26A434 上重开项目态零 spin、三面健康」。（核销动作留
orchestrator 执行；README Known Issues 的 D-6 workaround 行是否随撤请
orchestrator 一并裁量。）

## 六、R5-2：导入零行间歇 — **诊断性复现成功（只诊断不修）**

- **复现**：本轮 9 次探针 fresh-project 导入中 **4 次 grid 行 >10s 未到**
  （probe 自身 10s 等窗超时自灭：pid 87874/88063/89544/89697）；4 次全部
  落在机器 load 10-20 窗口（本轮全套 + 光谱烘焙 + WindowServer 高载期），
  低载期 0/5 失败——**负载敏感的刷新迟到**。
- **DB 法证**（`sqlite3 <project>.lalb "SELECT COUNT(*) FROM images"`）：
  5 个 acc-c 项目（含上述 4 个失败会话）**全部 n=1**——DB 行恒落库、
  grid 页未刷新 = FIX2 勘误后登记的真实失效面（「grid 页刷新迟到
  >10s 自愈」）**签名确证**。
- **GUI 面板腿**：NSOpenPanel ⌘⇧G 键盘通道在 AX/CGEvent 通道下不达
  （与 FIX2-01-ACCEPTANCE W3「Blocked-Channel」同判，两波独立复现）——
  GUI 导入走查继续需人工或换通道，入 obs-3。
- 失败实例采栈（`probe-gridrows-fail-spin.sample.txt`）：全线程 idle/
  mach_msg——非 CPU 挂死型，与「刷新事件未达」形态一致。

**路由：真修归后续批**（刷新链归因）——候选面 = ImportProgressCoalescer
终态 bypass 投递在高载下的时序 × grid model 重建触发；本轮按 mandate
只诊断不修。DB 侧无需动作（行恒落库已再证）。

## 七、R5-3：Vision 漂移复验 — **维持登记（红侧，不翻账）**

- **定向测试类**（按域单 bundle 类过滤）：`VisionDetectTests`（IOP）
  **4/0/0**；`AIMaskDeterminismTests`（Layers）**6/1/0**；
  `AIMaskSemanticTests`（Layers）**10/1/0**（skip = 层 B 资产 entitlement
  门，07-1 既有登记面非漂移）；`PersonInstanceMaskTests`（Layers）
  **5/0/0**——规避腿（allInstancesMask 合成 + gpuPinned 确定性）全部健康。
- **设备直查探针**（swift, macOS 27.0.1 26A434, `/tmp/r53-drift-probe.swift`）：
  - layerA `GenerateForegroundInstanceMaskRequest`：main = `[MLNeuralEngineComputeDevice, MLGPUComputeDevice]`——**CPU 仍不在 supported 集**
  - layerB `GenerateIterativeSegmentationRequest`：main = `[MLGPUComputeDevice]`——CPU 仍不在
  - （`GeneratePersonSegmentationRequest`：main 含 CPU——非 07-1 漂移登记对象）
- **判定**：07-1 漂移①（CPU 不在 supportedComputeStageDevices + 非法 pin
  SIGTRAP）在正式版 **27.0.1 仍存活**；②与①结构耦合维持；③
  （generateScaledMask 双重损坏）本轮未直测（需 person fixture 真推理，
  超出测试类复验载具）——**三漂移登记整体维持，升级缝继续 dormant，
  AIDevicePolicy 的 validate-then-typed-throw 防线不可撤**。测试类绿 ≠
  翻账依据（类走的是规避腿），设备直查红 = 翻账否决证据。

## 八、观察项（obs，0 阻塞）

1. **obs-1（全套 skip 对账）**：IOP skip 5→1（executed/fail 逐值不变，
   零失败）。供件面已排除——两轮间唯一 TestRAW 增量 ColorChecker.ARW 的
   唯一消费者 GoldenColorTests 属 IOPParity 域且被空 patch 表门控（本轮
   IOPParity 529/11/0 逐值同）；executor T4 的 IOP 日志已被本轮覆盖、差分
   不可逐法枚举。本轮 IOP 幸存唯一 skip = SkinRegionGeometryTests 宿主
   Vision 态条件 skip（`no face detected in the cartoon drawing`），消失的
   4 个 skip 最可能同属宿主态族。趋势 = 更多法通过、无 executed 损失。
2. **obs-2（探针实例生命周期仪器面）**：probe 实例 terminate 挂死 ×3
   （两例 SN 态 + 一例光谱烘焙期 quit 不落——`SpectralTcFit.fitCoefficientTable`
   首烘分钟级，sample 存证）；idle 实例去抖写不自发落盘（M8-3 既有登记
   复现）；AI 分析 sheet 于未勾选「记住我的选择」时每新会话必现（CGEvent
   点击偶发不达，AXPress 稳定）。均不影响产线判定；建议后续走查工具面
   统一改 AXPress。
3. **obs-3（GUI 面板通道）**：NSOpenPanel ⌘⇧G 在 AX/CGEvent 通道死路
   （FIX2 W3 + 本轮双判）——Import Folder/New Project 的 GUI 自动化腿
   不可达 /tmp 供件，导入面 GUI 走查需人工或替代通道。

## 九、卫生与提交

- GUI 实例全部 quit/kill 清零（起跑前 ps 验证、收工复核）；defaults 清
  （`library.recentProjects` 10 条 throwaway 探针项目已删，其余用户键
  未触）；/tmp fixture（m8fix-acc* / m8fix-import / r53 探针）按指示留存
  下轮复用；$TMPDIR throwaway 项目 = R5-2 证据留存。全程未 checkout
  主树、未触 0a21136c 恢复的 TestRAW 供件。
- 本报告单 commit（`docs(m8)`，内部账本无 issue ref，不 push）。
