# M8-3+ 最终验收（omp 执行 lane）

**PASS / 修复核验三件全绿 + 全套 4520/34/0 全绿** —— 本批可收口；挂账移交见 §五。

> 验收对象：修复轮四 commits `ef3e4aff`..`b8bbe9e5` + 复审 `c86767f4` +
> fix2 `2c57f1b5`（+ 后续纯账本 `8882976d`，1 文件 `.work` 面，零产品影响）。
> 正本 = `M8-3+-ACCEPTANCE.md`（E-acc1/m-A/o1）+ `M8-3+-FIX-REVIEW.md`
> （E-fix-1/m-fix-1）+ `M8-3+-SUMMARY.md` §八/§九。方法 = diff 逐 hunk +
> file:line 亲核 + 定向复跑实测 + 封存面机检 + 全套一轮。issue：#21。

## 一、修复核验三件（定向亲核 + 定向绿，全过）

### E-acc1（分配器接线，`8fb4291e`）✓

- `git diff ac0157b1..8fb4291e -- LightamerIOP/` 机检：**零命中**——接线面全在
  LightamerCore（`SpectralPayloads.swift` +454/-96、`FilmTailPolicy.swift`
  +12、`SpectralScratchAllocator.swift` token→资源池 +270）。任务书路径前缀
  是旧口径（T5 分配器最初登记在 IOP 侧），git 事实 = Core 侧八借点。
- 八借点 @HEAD 亲核（borrow/release/腿/池键）：B1 CMY `:747/:779`（`.stageB2`，
  唯一无 defer 尾 release = obs-1 已登记）/ grain 三 buffer `:862/:892` defer /
  clump 对 `:999/:1024` defer / r32 staging 对 `:1135/:1165` defer / diffusion
  三元 `:1348/:1377` defer / wide 五 staging `:1465/:1501` defer / halation
  四元 `:1742/:1775` defer / bounce 面 `:1857/:1878` defer。Slot mint 缝
  `dispatchFilmChain :603`（`scratch ?? Slot()`）+ 注入面
  `FilmTailPolicy.swift:349-357/404-409` 亲核。
- WiringTests 4 法本审定向复跑 **4/0/0**（251s，peakRSS 234MB）✓。

### E-fix-1（GrainGolden 加回，`2c57f1b5`）✓

- `Project.swift` diff 亲核：`+SpectralGrainGoldenTests.swift` 一行（`:345`，
  Wiring 行 `:348` 之上，替换事故反转）；BUNDLE-MAP `:962` `IOPP 4`
  登记本就未动，与加回自洽。
- `git diff ac0157b1..HEAD -- SpectralGrainGoldenTests.swift` = 空（文件内容
  零触，加回纯登记修复）。
- 本审定向复跑 **4/0/0**（296s）——ramp 哨兵 `3613671270926763817` 逐位主门恢复 ✓。

### m-fix-1（CrossArm 钉值，`2c57f1b5`）✓

- 处置形态 = review 建议选项①（补钉值）而非任务书预期的改名：类名维持
  `SpectralCrossArmGoldenTests`，理由 = 补钉后名实相符。双常量
  `:45-46`（wide `15571136022812571430` / 转置 `12304591439955305968`）+
  断言 `:232-238/:272-278` 在位；exact 孪生按设计不钉（注释 `:43` 申报
  routing monitor 非 byte monitor）。
- 本审定向复跑 **2/0/0**（244s）✓。

## 二、全套一轮（✓ 4520/34/0 精确落点）

- 起跑纪律：guard PASS（heavy=0 / free=68%）+ ps 清零亲核 +
  `machine-guard.sh --monitor 21600` 伴跑（**零触发**，日志仅 start 行）+
  `caffeinate -dis test-direct.sh --all` nohup disown（12:52 → 14:01，4143s）。
- 终值 **4520/34/0** = 预期精确落点；零 MEMFAIL；IOP 6820MB < 8G 运行门。

| bundle | 本轮实测 | 预期 | 判 |
|---|---|---|---|
| IOP | 836/1/0（6820MB/956s） | 836/1/0 | 逐位一致 |
| IOPParity | 584/10/0（6081MB/1662s） | 584/10/0 | **+4 加回实证** |
| Layers | 540/5/0（1171MB/452s） | 540/5/0 | 逐位一致 |
| Library | 788/4/0（744MB/171s） | 788/4/0 | 逐位一致 |
| Sessions | 285/4/0（1584MB/63s） | 285/4/0 | 逐位一致 |
| Export | 385/4/0（5111MB/199s） | 385/4/0 | 逐位一致 |
| App | 1102/6/0（2832MB/640s） | 1102/6/0 | 逐位一致 |
| **TOTAL** | **4520/34/0** | **4520/34/0** | 精确落点 |

## 三、封存面机检（✓ 全过）

- 修复轮段 `git diff --name-only ac0157b1..HEAD` = 14 文件，17 件封存面
  （DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/
  DrtEotf/ExportQueueContract/ExportFormatSpec/ImageIOEncoders/WebPEncoder/
  NodeGraphCommand/LightamerSidecar/HistoryStack/HistoryHash/PipelineDocument/
  V50Order/NodeOwnershipCatalog）**交集零** ✓。
- 全批段 `git diff --name-only 0b9f480d^..HEAD` 命中仅两申报例外：
  - 例外① `LightamerSidecar.swift`：1 hunk（v13 注释 + digit 12→13，`+15/-4`，
    上行 v12 注释逐字节保留）——纯净 ✓。
  - 例外② `PixelPipe.swift`：**1 hunk**（非任务书"2 hunks"：E3 RMS tag
    additive 默认参，`+6/-1`；`publishedRms: Int? = nil` 默认参 = nil tag 走旧路）。
    任务书"2 hunks"是复述偏差，git 事实 = 1 hunk，照申报核对通过。
- 路径落地注记：`TerminalTailPolicy`/`DrtTailAssembly` = `PixelPipe.swift`
  尾部 enum（:1801/:1863），`ExportFormatSpec` = `ExportRecipe.swift` 内 enum
  （:322）——封存清单 17 件是语义件名，非 17 个独立文件。
- 双臂/进程/默认 off：FilmSubRunKernels.metal / FilmDeterminismTests /
  RenderProcess（current=3）/ GrainModule 零 diff；UserDefaults 零新键；
  `runModal(` 零命中；zh-audit 双 PASS 本审复跑（`--check` 1795/2128 +
  `--self-test` V17 golden 八例）。

## 四、ΔN 对账（✓ 闭环）

任务书链含两处复述偏差，git 事实纠正：①M9-4 修复轮与 M9-3 修复轮在 M9
close（`a4545673`）之前，已含 4443 锚内，不可重复计入；②mcp-uq 基线是
`1b241de9` 时点的 4443（R9 收口态），非"4443+M9-4 修复轮"。实链：

| 段 | commits | ΔN | 累计全套 |
|---|---|---|---|
| M9 close 锚（含 M9-3/M9-4 执行+修复轮 + R7/R8/R9 站后链） | `a4545673` | — | 4443/34/0 |
| mcp-uq 增量批（McpGetSchema 7 + McpOnboarding 11） | `a98318cc..310a499a` | +18（App） | 4461 |
| mcp-uq 修复轮直测（review 轮账面漏记，o1 勘误 `ef3e4aff` 纠正） | `365bbe26` | +1（App） | **4462**（M8-3+ 真基线） |
| M8-3+ T1..T7（5/10/10/12/13/0/2） | `0b9f480d..17ce3d6a` | +52 | **4514**（验收路 1 复跑亲证） |
| fix2（GrainGolden 加回） | `2c57f1b5` | +4（IOPP） | **4520**（本轮全套亲证） |

- 分解式：4443 + 18 + 1 + 52 + (4+2−4) + 4 = 4520 ✓；skip 34 全程持平，
  fail 0 全程持平。
- 旁证：验收 `git diff` 重数 52 增/0 删（ΔN=+52 精确）；FIX-REVIEW
  账本算术 4514+6−4=4516 自洽式；本审三类定向 4+4+2 全绿。
## 五、结论（PASS，可收口）

- 修复核验三件：E-acc1 ✓ / E-fix-1 ✓ / m-fix-1 ✓（file:line 亲核 + 定向绿）。
- 全套 4520/34/0 全绿精确落点（七 bundle；IOPP +4 加回实证；零 MEMFAIL）。
- 封存面/红线：全过（两例外照申报核对，hunk 数纠正 1 处复述偏差）。
- ΔN：逐段闭环（4443+18+1+52+2+4 = 4520；任务书链 2 处复述偏差已纠正）。
- 挂账移交（非本批缺口）：D5/D6/D8/D9/D11 入 GOAL-STATE 追踪；obs-1 defer 化 +
  obs-2 措辞注明（低优先）；100MP on 档真跑 + m-6①/三戳 leg-2 + 走查 MANIFEST
  六配方归批准轮；obs-o3 RMS 覆盖面 census。
