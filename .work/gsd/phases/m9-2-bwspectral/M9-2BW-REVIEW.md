# M9-2 改签批「v0.3.3 BW pack 解码修复」独立审核报告(zcode review lane)

> 审核对象:产品 commit `339adb33`(fix(m92),18 文件,fixes #22)+ 账本 `e63ebb3f`。
> 审核日期:2026-11-03。纪律:只读 + 定向测试复跑(禁 `--all`),零产品修改、零 commit、零 push。
> 任务书正本:`m92bw-review-prompt.md`。

## 结论头

**PASS / 0 error + 3 minor**(另 8 obs)

产线语义正确(null→0 与上游 hanatos `nan_to_num` 对齐、中位显影列确定性、存量 28 卷
pass-through 零漂移)、封存面全集零 diff、计数钉逐处与数据实况吻合、定向复跑双绿、ΔN
链逐段可加、zh-audit 双 PASS。三项 minor 均为测试门/死代码/契约注释层面,零运行时影响,
建议回注 omp 修复循环一并收口。

---

## 一、审查清单逐项核验

### 1. 边界 — PASS

- HEAD = `e63ebb3f` ✓(`git rev-parse --short HEAD` 亲核)。
- `git show --stat 339adb33`:18 文件 = BUNDLE-MAP 1 + `LightamerCore/Sources/Film/`
  4(FilmMaterialStore / FilmProfile / PaperGradeTable / SpectralBuildEngine)+ Project.swift
  1 + `Tests/LightamerTests/` 12(含新建 BWPackDecodeTests)——**任务域外零文件** ✓。
- `git show --stat e63ebb3f`:4 文件全 docs(GOAL-STATE / TODO / M9-2-DECISIONS /
  M9-2-SUMMARY)✓。
- `git status --short`:51 条未跟踪,**全部位于 `.work/`**(lane prompt / omp 日志 /
  all-runs 日志),产品面零残留 ✓。

### 2. 封存面独立机检 — PASS

- 17 件封存面按**类型名**在 18 个变更文件中 grep(`class|struct|enum|protocol|actor <Name>`):
  TerminalTailPolicy / DrtTailAssembly / ExportFormatSpec / ImageIOEncoders / WebPEncoder /
  NodeGraphCommand / HistoryStack / HistoryHash / PipelineDocument / V50Order / GradeCatalog /
  Registry / ModuleInstance / LightamerSidecar / DrtRecord / DrtEotf / DrtPanelModel /
  DrtPanelView ——**全部零命中**(变更文件均不定义上述类型)✓。
- `RenderProcess.swift:92` `public static let current = RenderProcessVersion(rawValue: 3)!`
  ——**恒 3** ✓。
- 变更文件名 grep `GrainModule|\.metal$|LibraryProjectController|McpServerController` 零命中 ✓。
- `Resources/FilmProfiles/` 不在变更列表;`shasum -a 256 -c MANIFEST.sha256` → **33/33 OK**
  (31 profile + LICENSE + neutral_print_filters)✓。

### 3. BloomTests 行恢复实证 — PASS

- `Project.swift:450` `BloomTests.swift` 在位;`:454` `BWPackDecodeTests.swift` 新增;
  diff 形态 = **纯 `+` 行,零 `-` 行**(纯插入)✓。
- `grep -c "func test"`:BloomTests = **6**、BWPackDecodeTests = **4** ✓。
- BUNDLE-MAP `:126 IOP 6 BloomTests.swift` + `:978 IOP 4 BWPackDecodeTests.swift` ✓。
- **叙述自洽性补核**:父 commit `0c72ae3e` 的 Project.swift 本就含 BloomTests 行且无
  BWPackDecodeTests 文件——「前任 lane 把注册写成替换」只存在于被 SIGTERM 中断的 lane
  工作区,从未入 git;最终提交为纯插入,与叙述一致(obs-a)。

### 4. 计数钉逐处核 — PASS(附 1 minor)

| 钉点 | 变更 | 核验 |
|---|---|---|
| FilmProfileTests 卷数 | 28→31 | `testProfileCountIs31…` ✓ |
| FilmProfileTests version | 0.3.2 ∥ (0.3.3 ∧ ∈ bwPackStocks) | 限三卷 ✓ |
| FilmProfileTests film | 22→25,paper 6 不变 | ✓ |
| FilmProfileTests manifest | 30→33 | ✓ |
| FilmProfileTests densitometer | `channelModel == "bw"` → `diffuse_visual` 分支先行 `continue` | ✓(三卷实测 diffuse_visual) |
| SpectralBuildGolden / GrainGolden / DualArmGolden | 三 set-wide 28→31,方法名 All28→All31 | ✓ |
| ExposureSemantics manifest | 30→33 | ✓ |
| FilmPanelBWTests BW 分节 | 4→7(四自采 + 三 CC 包) | ✓ |
| NeutralSolve anchored | filmStocks 22→25;排除 2383/2393/**2302**/**trix**/**doublex** → 20 | 算术 25−2−1−2=20 ✓ |

- anchored 排除理由实证:`neutral_print_filters.json` 中 trix/doublex/2302 出现次数 **0/0/0**
  (2383/2393 各 1)——「无锚行」成立;2302 `info.name = Kodak Print Film 2302` 印片成立 ✓。
- **minor-3**:`SpectralDualArmGoldenTests.swift:618` `XCTAssertGreaterThan(differingPairs, 25)`
  门槛未随 28→31 同比上调(原 ≥26/28 ≈ 93%,现 ≥26/31 ≈ 84%);实测 31/31 有余量。

### 5. nullable 语义抽查 — PASS(附 1 minor)

- **decode 逐字保留**:`logSensitivity: [[Float]]?` → `[[Float?]]?`,经
  `normalizedSpectralNullableMatrix`(形状门 81×3,点级 null 不降级)✓。
- **消费端 null→0**:`SpectralBuildEngine.swift` 两处 `guard let value else { return 0.0 }`;
  `PaperGradeTable.swift` 两处 `guard let sample else { continue }`(积分求和内 skip ≡ +0)
  ——与上游 hanatos.cpp:164 `np.nan_to_num` 语义一致 ✓。
- **中位显影列**:`normalizedDensityCurves`(width≠3 → 按 `rows[mid]` 排序取 `order[width/2]`
  三重复制;width==3 直通)+ `normalizedBaseDensityFamily`(双 `try?` 形分派,皆败抛
  typed `schemaMismatch` fail-closed)。Swift 5+ `sorted` 稳定性有保证 → 并列值确定。
- **存量零漂移**:width==3 / 标量 81 向量皆走 verbatim 分支;定向复跑 FilmProfileTests
  21/0/0(含 set-wide pair-hash 镜像 + 结构断言跨 31 卷)✓。
- **minor-2(契约矛盾 + 死 API)**:`FilmProfile.swift` 新增 `public func logSensitivityProjected()`
  **全仓零调用点**(Sources + Tests);而字段文档注释(`logSensitivity` 声明处)写明
  「consumption goes ONLY through `logSensitivityProjected()`」——**与实际消费端相悖**
  (四处消费均直读 `logSensitivity` 做 null→0)。更要紧的是 `projectedSpectralSeries` 语义 =
  线性插值 + 端点常量延展:若日后按注释接入,BW 包 30–56 整行 null 的未测波段会被赋予
  邻近非零灵敏度,**与上游 nan_to_num→0 物理相悖**。属上膛 footgun,现为零运行时影响。

### 6. materialPairHash — PASS

- 改动 = `log_sensitivity` 折入 nil-vs-value 标签(`.some` → chain(1)+bitPattern;`.none` → chain(0))。
- 消费点全集(grep 全仓):FilmSolveCache(注释明文「runtime solve cache … NSLock + LRU 8」)/
  FilmPrintBake LRU / FilmDescriptorCache.cacheKey / FilmTailParams Equatable / 面板 live 读。
- **Sidecar / Graph(FilmRecord·HistoryHash)目录零命中**;测试中无 materialPairHash 字面钉值。
  → 仅运行时缓存键,不改输出面、不入持久化哈希;存量 28 卷键值改变 = 一次冷 miss 窗(commit
  已申报)✓。

### 7. 定向复跑 — PASS

- `Scripts/machine-guard.sh` → **GUARD PASS**(heavy=0 free=79%);跑前 `ps` 零 Lightamer 实例。
- `test-direct.sh --bundle IOP 'BWPackDecodeTests'` → **BUNDLE|IOP|4/0/0|peakRSS=210MB|4s**。
- `test-direct.sh --bundle Layers 'FilmProfileTests'` → **BUNDLE|Layers|21/0/0|peakRSS=202MB**。
- 跑后 `ps` 零残留 ✓。
- **构建产物新鲜度亲核**(消除「xctest mtime 22:37 早于 commit 01:15」疑虑):
  `nm` IOP xctest 含 `BWPackDecodeTests` 5 符号 **且** `BloomTests` 5 符号;`strings` Layers
  含 `testProfileCountIs31…`(1)不含 `…Is28…`(0);App 含「the seven BW films ride the section」
  (1)。18 变更源 mtime 全部早于各自 bundle 构建时刻(最紧 22:34 → 22:37;FilmPanelBW 23:28 →
  App 23:47;Film 产线 20:38–20:58 → LightamerCore.framework 21:43)。xctest 早于 commit =
  正常「编辑→构建→测试→提交」序。executor 全套 4533 确跑在含修复二进制上(obs-d)。

### 8. ΔN 对账 — PASS

- 本批净增:`git diff` 中 `func test` **+9 / −5**(4 新法 + 5 重命名对 Is28→Is31 / All28→All31)
  = **+4** ✓。
- 链锚(commit message 提取):`3e3955fc` r9 **4443** → `ef3e4aff` MCP-UQ 4462(+19)→ `ac0157b1`
  m83p lane 4514(+52)→ `b8bbe9e5` 4516(+2)→ `2c57f1b5`/`bb1d1665`/`e1010e3a` **4520**(+4)
  → `55ad476d` vendoring **+0**(test diff 零 func)→ `7aa4c140` gallery-first **+9**(9 法逐一
  列出)→ 4529 → 本批 +4 → **4533** ✓。中间带 19+52+2+4+9 = **86** ✓。
- obs-b:账本写法 `4529 − 4443 = +86` 为同义反复,建议改列上述分段链以便审计。

### 9. zh-audit — PASS

- `--check` → **PASS**(1798 source keys / 2131 catalog keys,与账本逐字一致)。
- `--self-test` → **PASS**(V17 golden eight cases hold)。

### 10. 反自取消探针 — 3 项(超要求 2 项)

| executor 声明 | executor 方法 | 本审核方法 | 结果 |
|---|---|---|---|
| CC 包 MANIFEST 33/33 | 计数/对账 | `shasum -a 256 -c` 逐文件校验 | 33/33 OK ✓ |
| null 行 56/33/30、零部分行、2302 双键 col 2、doublex 曲线 col 2 / Dmin col 0、钉值 1.9514/0.0057/1.0957/0.2196 | Swift 测试钉 | `uv run python3 -I` 直读原始 JSON 复算(镜像排序规则) | **全部精确吻合** ✓ |
| BloomTests 已恢复 + 全套跑在修复后二进制 | 读文件 / 日志 | `nm`/`strings` 探 xctest 二进制符号 + mtime 序 | ✓(见 §7) |

### 11. 环境事件复核(.ips) — 结论成立

`Lightamer-2026-11-02-235749.ips`(bug_type 309,macOS 27.0.1 26A434):
- exception = **EXC_BREAKPOINT / SIGTRAP**,code 0x1。
- ASI = `BUG IN LIBMALLOC: malloc assertion "err == VM_RECLAIM_SUCCESS" failed
  (libmalloc/src/xzone_malloc/xzone_segment.c:342)`——**libmalloc 自宣的 xzone 分配器 VM 回收断言**。
- 故障线程 #0 栈:`_xzm_reclaim_force_sync` ← `xzm_reclaim_mark_free_locked` ←
  `_xzm_xzone_madvise_batch` ← `swift_release_dealloc` ← `destroy for LensEntry` ←
  `swift_arrayDestroy` ← `outlined consume of LensfunDB?` ← `LensfunStore.uninstall()`
  (LensfunMatch.swift:701)← `LensAutoApplyTests.tearDown()`(LensAutoApplyTests.swift:17)。
- 应用帧 = `[LensEntry]` 大数组的**常规 ARC 释放路径**;**无** `swift_fatalError` /
  `_assertionFailure` / runtime failure 帧;Lensfun 面与本批 18 文件零交集。
- 复发面:Lightamer 全部历史 .ips 含该签名 **仅 1 例**;本机其它进程零同签名;clean 重跑通过。
- **判定:「环境型 / 无 Swift fatal」成立**(obs-c)。建议:登记该 teardown 站点,若复发可考虑
  测试宿主 env 关 xzone(`MallocNanoZone`)或不在 per-test tearDown 释放整库。

---

## 二、Findings 清单(不自行修复,回注 omp 修复循环)

### error — 0

### minor — 3

**minor-1 · 测试门静默放空(存量 28 卷失去不变量守卫)**
- 位置:`Tests/LightamerTests/SpectralProfileDecodeTests.swift:261`
  `XCTAssertGreaterThanOrEqual(nulls, 0, name)`(原 `nulls, 15`)。
- 事实:对 count 而言 `≥ 0` 恒真 = 空断言;且**对全部 31 卷生效**。原钉 `≥15` 对存量 28 卷
  **恰好紧致成立**(Python 直读实测 channel_density null 范围 15–78,vision3 三卷恰为 15),
  BW 三卷实测为 0(midscale 缺席)。同一函数对 midscale 用了正确的 BW 分支形(`:300`
  `let isBWPack`),此处却全局放松;commit message 称「re-pin」,未披露此处为 de-pin。
- 影响:零产品影响;存量 28 卷 channel_density null 分布的回归守卫丢失(日后 decoder 丢 null
  或数据回填将漏检)。
- 修复建议:把 `:300` 的 `isBWPack` 提升到 `:261` 之前,改为
  `XCTAssertGreaterThanOrEqual(nulls, isBWPack ? 0 : 15, name)`;更优形 = BW 分支改
  `XCTAssertEqual(nulls, 0, name)` 同时钉死三卷形态。

**minor-2 · 死公开 API + 字段契约注释与实际消费相悖(物理方向错误的 footgun)**
- 位置:`LightamerCore/Sources/Film/FilmProfile.swift:225`(注释「consumption goes ONLY
  through `logSensitivityProjected()`」)+ `:640` `public func logSensitivityProjected()`。
- 事实:`logSensitivityProjected` **全仓零调用点**(Sources + Tests grep);实际四处消费
  (SpectralBuildEngine ×2、PaperGradeTable ×2)直读 `logSensitivity` 做 null→0 / skip。
  `projectedSpectralSeries`(`:586`)语义 = 邻近非 null 线性插值 + 端点常量延展——若按注释
  接入,BW 包 30–56 整行 null 的未测波段将获得非零灵敏度,**与上游 hanatos.cpp:164
  `np.nan_to_num`(→0)相悖**,且与引擎现行为分叉。
- 影响:现为零运行时影响;但注释主动误导维护者走错误路径。
- 修复建议:删除 `logSensitivityProjected()`;`:222-228` 注释改为「consumers read a null
  sample as ZERO sensitivity (upstream hanatos.cpp:164 np.nan_to_num); never interpolate /
  project across unmeasured wavelengths」。若保留方法,须改名并在文档中显式声明「非引擎消费面」。

**minor-3 · set-wide 门槛未随卷数同比上调**
- 位置:`Tests/LightamerTests/SpectralDualArmGoldenTests.swift:618`
  `XCTAssertGreaterThan(differingPairs, 25, …)`。
- 事实:28→31 后门槛仍 25(严格度 ≥26/28 ≈ 93% → ≥26/31 ≈ 84%);实测 31/31 全分叉有余量。
- 修复建议:上调为 `> 28`(≥29/31 ≈ 94%)以保持原严格度。

### obs — 8(非缺陷,供账本/后续参考)

- **obs-a** BloomTests「替换」从未入 git(父 `0c72ae3e` 本含该行);最终 diff 纯插入,叙述自洽。
- **obs-b** 账本 ΔN 写法 `4529 − 4443 = +86` 同义反复;分段链(4443→4462→4514→4516→4520→
  4529→4533,gallery-first `7aa4c140` +9、vendoring `55ad476d` +0)已由本审核独立核实可加,
  建议账本改列分段链。
- **obs-c** .ips 环境型结论成立(libmalloc xzone `VM_RECLAIM_SUCCESS` 断言;应用帧仅为
  LensfunDB ARC 释放;Lightamer 历史唯一 1 例;与本批零交集)。建议登记 `LensAutoApplyTests.tearDown`
  站点观察复发。
- **obs-d** 构建产物新鲜度:`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi` 容器二进制含全部新符号,
  源 mtime 序自洽;本审核复用该产物未重建(符合交接不重建纪律)。
- **obs-e** `BWPackDecodeTests.testPairHashFoldsTheNormalizedFace` 为 smoke 级(异卷不等 +
  双载确定);方法名「folds the normalized face」略超其断言——未断言中位列选择影响哈希。可接受。
- **obs-f** `FilmProfile.swift:404-406` 新引入三连空行(格式)。
- **obs-g** 上游数据事实核实(非缺陷):`kodak_trix` = **Kodak Tri-X Reversal Film 7266**
  → `type=positive` 正确;`FilmPanelModel.isReversalFilm`(`:452-457`)将对其显示反转片印相模式节
  = 正确行为。`kodak_2302` = Kodak Print Film 2302,`type=negative` 沿 2383/2393 数据集惯例。
- **obs-h** 任务书举例 `cinestill_800t` 不在 vendored 集(28 存量无此卷);存量零漂移改由
  FilmProfileTests set-wide 覆盖。

---

## 三、红线纪律自证

- 零产品代码修改(`git status` 产品面无变更;本报告为唯一新文件,落 `.work/`)。
- 零 commit / 零 push。
- 定向测试仅两类(IOP 4 法 / Layers 21 法),未跑 `--all`;guard 先行,跑前跑后 `ps` 零实例。
- 临时脚本 `/tmp/ips_parse.py`(即弃)。

> 结论:**PASS / 0 error + 3 minor** —— 可进入 omp 修复循环收口三项 minor 后终审。
