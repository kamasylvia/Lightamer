# M2-7 ACCEPTANCE-OMP — 蒙版 phase 回溯二次验收（独立）

> 验收员：omp（零共享上下文回溯验收）。日期 2026-10-09。对象 = M2-7 三 plans（M2-7-1 数据与内核 / M2-7-2 面板与交互 / M2-7-3 收口批）。
> 方式 = 正本三 ACCEPTANCE + 三 SUMMARY + 两 DECISIONS 亲读 + AGENTS.md M2-7 增量节亲读 + 证据 dir 亲看 + 读码亲核 8 处 + 定向测试 2 类亲跑 + zh 52 键全族机检 + git 机检 + 探针 log 逐行核对。
> **结论头：`PASS / 0 error + 1 minor`**

## 一、逐 plan 判定

### M2-7-1（数据与内核）— PASS

- 首验结论（`M2-7-1-ACCEPTANCE.md`：12/12，0e+0m）经本轮抽查**成立**。双羽化分流、换算单源、sidecar 双向、revision 单源、edgeMap 段位、Follow Edges 穷举六面全部亲核吻合（见 §二 1/2/4/5）。
- 唯一口径注记：首验「生产 bump 恰 4 处」是 P1 窗口快照真值；现 HEAD 全仓 8 处新增 4 处全部隶属 P2 申报面（面板统一缝 + add/remove 命令 + overlay 重放臂），已在 §二-5 归因，无口径冲突。

### M2-7-2（面板与交互）— PASS

- 首验结论（`M2-7-2-ACCEPTANCE.md`：11/11，0e+1m 已修）经本轮抽查**成立**：E5 校验次序（先校验后 bump + append 重放/mutate 拒绝分派）实现亲验逐段吻合 `MaskOverlayHost.swift:830-862`；panelMenuCases 白名单五项与消费点 `LayersPanelView.swift:396` 亲核在位；Range 纯映射 `luminanceTrapezoid`/`colorRangeEntries` + 吸管单源注记亲核在位（见 §二 2/5）。
- T8 LazyVStack 修复：`panel-before-fix-empty-hint.png` 在 evidence/m2-7-2/ 亲看在库；修复语义（body 作用域读取）与首验描述一致，不复读 diff 行（属 P2 验收时态证据）。

### M2-7-3（收口批）— PASS

- 首验结论（`M2-7-3-ACCEPTANCE.md`：8/8，0e+3m 已修+1o）经本轮抽查**成立**：熔断落点 App 单点与 Core 缺省不动亲核吻合；probe.log 判据数字逐行复核（§二-3）；incident.log 在案且 AGENTS 教训已登记（F2 修复亲证在位，§二-3）；zh 52 键全族机检 52/52 存在且 zh 非空（§二-6）。

## 二、逐抽查点证据

### 1. Follow Edges 熔断态（读码）— ✅ 与申报逐字一致

| 申报项 | 亲核位置 | 实测 |
|---|---|---|
| App 侧单点默认 `.snap` | `App/Sources/Lightamer/State/LayerEditingState.swift:193` | `var followEdgesParams = FollowEdgesParams(mode: .snap)`，上附 OQ-4-C 熔断注记（:186-192，含 ≤3 点链判据 + V2 挂账） |
| Core 缺省仍 `.streamline` | `LightamerCore/Sources/Layers/Masks/FollowEdges.swift:66` | `mode: FollowEdgesMode = .streamline`，改默认未触 Core |
| `.streamline` 分支保留 | `FollowEdges.swift:108-109` | `case .streamline: return streamline(...)` 与 `case .snap` 双臂在位 |
| 模式选择器保留 | `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift:210-214` | Picker 双 tag（streamline/snap）全绑 `editingState.followEdgesParams.mode`，无字面默认值 |
| 穷举零 default | `FollowEdges.swift` 全文件 `default:` grep | **零命中** |

### 2. 双羽化内核 / 换算钉 / revision 乐观并发（读码 ≥4 处，实际亲核 8 处）— ✅

1. **kernel 腿分流** `LightamerCore/Sources/Metal/MaskRasterKernels.metal:171-176`：`if (u.form2.z != 0.0)` → Alcedo 线性带腿（rho/inner/outer/clamp 四式）；旧二次腿 `:177-185`（border ≤1e-6 guard、`f*f`）逐 token 保留。分流按 mode 旗标非按值——与首验 §二①逐字吻合。
2. **facade 单源谓词** `LightamerCore/Sources/Layers/Masks/MaskSpec.swift:148-150,161-162`：`hasDualFeather = innerFeather != nil || outerFeather != nil`（头注 THE single predicate）；`resolvedOuterFeather = outerFeather ?? (innerFeather != nil ? 0 : border)` 逐字亲验。
3. **form2 打包** `DrawnMaskRasterizer.swift:101-102`：`innerFeather ?? 0, outerFeather ?? 0, hasDualFeather ? 1 : 0`——腿内补缺 + modeFlag 纯函数，与首验一致。
4. **换算钉单源** `MaskGradientDefaults.swift:32,46`：`compression = τ/(2·√2)`（τ=0.2 → `0.2/(2√2)`）+ `rotation = atan2(nx, ny)`（:26）。首验「compression=τ/(2√2)」是公式通式，代码落笔为 τ=0.2 默认档实例——同一事实两面，无分歧（文件头 13-37 行双公式推导逐行引证在案）。
5. **Range 纯映射** `ParametricMask.swift:231,251`：`luminanceTrapezoid`/`colorRangeEntries` 纯函数在位；吸管走 IOP `JzCzhz.fromRGB` 单源（文件头 :207-211 注记 Core 不自实现）。
6. **revision 单源** `MaskSpec.swift:388-391,409-411`：`bumpContentRevision()`（nil→0 折叠 + overflow precondition）+ `matchesExpected` 单谓词。
7. **sidecar 载体** `SidecarLayerStack.swift:62-63,87-88,95-96`：`deletionProtected`/`contentRevision` additive optionals + capture/restore 各一行，decodeIfPresent/encodeIfPresent 零漂移语义与首验一致。
8. **edgeMap 段位** `PipeCacheKey.swift:90,100-101,108-121,171`：`edgeMapPosition = -4`（:44-45 注记 -3 实占勘误）+ `edgeMapNamespaceID` + `edgeMapKey` + `layerTier` 一行 `.maskPlane` 分支——E2 勘误落实亲证。

### 3. 证据核对（probe.log + incident.log）— ✅

- **probe.log**（`evidence/m2-7-3/probe/probe.log`，48 行亲读）：`WARM empty=82/100 avgPts=0.2`（:4）；8 SCENE 景盒（A/A2/A3/B/B2/B3/C/C2）× 2 阈值全部 `n≤3`（最大 n=3 仅 A 系，:8-37）；auto-seed 行同分布；`DIAG` 四组 `functionalChains=0/3`（场 1024/2560 × 步 1.5/0.75，:42-45）；`FIELD max=0.4941 mean=0.01801 p99=0.1808`（:2）；`COLD median 6.3ms min 6.1 max 7.3`（:3）；`FULL 73.7ms`（:47）。**全部与 M2-7-3-ACCEPTANCE §二①引数逐值一致**（F1 勘误后真值）；与 AGENTS.md M2-7 节「≤3 点链 / 0/3 功能链」措辞一致。证据 dir 另有 ev_A/B/B2/C + field_vis + plane_dump + GUI 两张 + probe 三源码共 16 文件（`find` 清单亲核），无缺失。
- **all_run_incident.log**（9 行亲读）：`TOTAL|2179/16/0|764s`，`IOPParity 16/3/0` 截断（16+346=362 闭合），其余六 bundle `467/1、298/3、430/4、279/4、260/1、429/0`——与首验 §二③引数逐值一致。
- **教训登记**：`AGENTS.md:325` 测试宿主进程清理教训行亲读在位（含 `ps -o ppid` parentage + 留证重跑口径）——首验 F2 修复亲证落地。

### 4. 定向测试（Layers 域，2 类亲跑）— ✅ 0 fail

| 类 | 命令 | 结果 |
|---|---|---|
| FollowEdgesTests | `caffeinate -dis Scripts/test-direct.sh --bundle Layers FollowEdgesTests` | `BUNDLE\|Layers\|8/0/0\|peakRSS=193MB` + `TOTAL\|8/0/0` OK |
| MaskFeatherAlignTests | `caffeinate -dis Scripts/test-direct.sh --bundle Layers MaskFeatherAlignTests` | `BUNDLE\|Layers\|9/0/0\|peakRSS=196MB` + `TOTAL\|9/0/0` OK |

计数与首验申报（P1 FollowEdgesTests 8 法 / MaskFeatherAlignTests 9 法）精确一致；禁全套纪律遵守（未跑 `--all`）。

### 5. git 机检（2 commits --stat 对照）— ✅（1 minor：正本 SHA 已过期，见 §三）

- `59ac74f chore(m2-7): follow edges default to snap mode`：`--stat` = `LayerEditingState.swift` 单文件 6+/2-——与 P3 SUMMARY 申报「UI 默认值一行 + 注记四行」**精确吻合**（6+/2- = 1 功能行 + 4 注记行 + 上下文行调整）。
- `8d67b5d feat(core): follow edges walker with edge map cache key`：`--stat` = FollowEdges.swift + MaskEdgeKernels.metal + PipeCacheKey.swift + FollowEdgesTests.swift + Project.swift + BUNDLE-MAP 六文件——与 P1 T6 SUMMARY 申报交付面**精确吻合**。

### 6. zh 对账 — ✅ 52/52 全族在册

- 抽查 3 键：`mask_follow_mode_streamline`→「流线」、`mask_groups_empty_hint`→「还没有调色图层——添加后即可绘制蒙版」、`mask_command_duplicateAndInvert`→「复制并反转」——键存在且 zh 非空。
- 加深：按 P2 DECISIONS §五 52 键清单全族机检 `Resources/Localizable.xcstrings` 现态（catalog 共 1822 键）=`total 52 missing [] emptyzh []`。首验「39 MISSING + 13 动态 = 52 全族」结论在现态 catalog 下**完全成立**。
- 另亲核 `settings_behavior_mask_hint` 沿复用语义（零新设置键），与 DECISIONS §五一致。

### 7. 加深核对（自选 2 项）— ✅

1. **E5 快照时点 + 校验次序**：`MaskOverlayHost.swift:765`（appendForm 内 press 段写毕后 `expectedRevision = layer.mask?.contentRevision`）+ `:787-788`（mutate 首改兜底）+ `:830-831`（endInteraction 先 `matchesExpected` 门）→ 相等路径 `:860` bump 后 commit；失配 + append 型 `:832-851` 重放（dedup + bump + 恰 1 item + toast）；失配 + mutate-only `:853-857` 拒绝（零 history 零 bump + toast）——与 M2-7-2-ACCEPTANCE §二②逐段吻合。
2. **bump 全仓 8 处归因**（P1 首验 4 处 → 现 HEAD 8 处，增量 4 处全部归 P2 申报面）：`EditorState.swift:691`（commitMaskEdit 统一缝 = 写点⑤，头注 :682-686 明示 bump 归缝）、`LayerEditingState.swift:514/544`（add/removeMaskItem 各自 commit 前恰一次）、`MaskOverlayHost.swift:843`（P2 T3 重放臂）、另 `:860`（P1 原 endInteraction 相等路径）+ `AIMaskEditing.swift:185`（P1 AI install）+ `LayerEditingState.swift:406/429`（P1 duplicateAndInvert/fill 前向携带）= 8 处全归因，**零申报外写点**。live 腿（appendForm/mutateForm 函数体）亲核零 bump——P1「bump 只挂提交腿」纪律在 P2 后仍成立。

## 三、与首验分歧点

- **实质分歧：无。** 熔断态语义、内核数学、revision 纪律、证据数字、测试计数、zh 族账、commit 文件集七面全部与正本材料一致。
- **minor × 1（文档时效，非交付缺陷）**：正本三 ACCEPTANCE/SUMMARY 引用的执行期短 SHA（`d6de037`/`cb3b3ea`/`7b88bbb`/`bf2a4db`/`066423f`/`60582c3` 等）经 `git cat-file -t` 亲跑**全部已不可解析**（公开仓压缩重写历史所致，全仓 log 现为 `8d67b5d`/`59ac74f` 等新 SHA 体系）。影响 = 后续回溯者无法按正本 SHA 直达 commit，需经 subject 检索映射（如本报告 §二-5 所示映射成立）。不触交付态、不改任何结论；是否在 phase 目齿补 SHA 映射表由 orchestrator 定（本验收只读纪律，不补）。

## 四、会话卫生

- 只读验收遵守：除本报告文件外零写入；`git status` 显示的 `M OMP-RETRO-QUEUE.md` 与 4 项 untracked 均为本会话进入前已存状态（M2-7-3-ACCEPTANCE §四已登记 Resilio 噪声两枚；另两项非本 phase 产物），本会话未触碰、未 push。
- 测试纪律：仅跑 Layers 域 2 类定向（8/0/0 + 9/0/0），未跑全套 `--all`。

OMP-VERDICT: PASS
