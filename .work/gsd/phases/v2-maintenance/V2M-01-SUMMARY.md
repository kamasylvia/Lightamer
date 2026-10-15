# V2M-01 SUMMARY（波 1 缺陷修复批 D-1..D-5，2026-10-15/16 夜间批）

> 结论头：**PASS / 0 error + 0 minor（批内窗口）**。五缺陷代码面全部落地，
> 五 commit 链 + 定向轮 + 全套 `--all` 对账精确闭合；GUI 走查四项 Blocked-Env
> 如实登记（不硬造判定），批外疑点两笔原样上报。**ACCEPTANCE 不写**（按派发令）。

## 一、任务逐个完成态与 ΔN 记账

| 任务 | 内容 | commit | ΔN | 验收要点实测 |
|---|---|---|---|---|
| T1 | D-1 追色按钮零响应：params 快照去热观察读取 + updateInstance 钩子兑现 + view 级 `.onChange(of: instance)` seam（C-1 非 nil 作用域）+ Film/Drt 三分裁定（健康，两文件零 diff） | `54124c7e` | **+2**（`testSnapshotRefreshFollowsTheCommittedRecord` / `testLiveWindowOverridesTheSnapshotUntilCommit`，两具名测试均落地） | grep 机检：params/currentRecord getter 体 `pipeCoordinator` 零命中（remaining 触达全在 hasImage/solve/refresh 动作上下文）；D-H1 既有法不红（`testStrengthDragCommitsExactlyOneItem` 绿）；`--bundle App` 818/4/0 |
| T2 | D-2 视口绿染：七步 bisect（配方 1-7 照跑，⑤不适用⑥被探针升级替代⑦证人换 Preview）→ automatic 收紧恒 v8 → 回归钉双法 | `5567b56c` | **+1**（`testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace`，供件级 untracked 样张 `input/RAW/GREENCAST-7RM5.ARW`） | transcript + 探针源/输出 = `evidence/V2M-01/d2-bisect/`（local-only）；正例对照：修前 spread 0.742 应红 / 修后 0.062 绿；`--bundle IOP` 687/5/0 |
| T3 | D-3 filmstrip 换图钉序：`switchCurrent(to:)` 单一换图通道收敛 + `loadCurrentImage` await 后取消检查点（陈旧任务写陈旧 projection/load 的竞态封闭） | `83f48bbb` | **+0**（视图级 seam 不可纯函数化，DECISIONS 记账） | `--bundle Library` FilmstripModelTests 6/0/0；A/B 字节相同副本亲证「未换」观感假象来源 |
| T4 | D-4 合并对话框「0 张」：三计数对话框改 `.sheet(item:)` payload（`MergeDialogCount` arm 时随 item 进闭包，两候选下都鲁棒形） | `e74be37b` | **+0** | grep：`pendingTargets.count` 文件内零命中；三标题行读 `dialog.count`；`--bundle Sessions` 284/9/0 |
| T5 | D-5 toast 裸键名：调用点 `Int((holeFraction * 100).rounded())` 对齐在册 `%lld` 变体 | `8133726e` | **+0** | grep：命中行含 Int(...rounded()) 形态；`zh-audit --check` PASS（1682/1929/30）；xcstrings 零 diff |
| T6 | 收口：定向轮 + 全套 + 文档 | 本批 | — | 见 §三/§五 |

**ΔN₁ = +3**（预期带 +3..5 内；T3 的 +0..1、T2 的供件级 +1..2 均按实记账）。

## 二、D-2 bisect 裁定结论（三段式验收第一段）

**毒化腿 = CI 色管理转换 × RAW 9 (v9 CoreML) 输出**——同文件 v9/v8 输出在
unmanaged 渲染下像素近同且平衡，经 CIContextPool 形态（working=output=
linear Rec2020）转换后 v9 通道倾斜（线性 G/R≈3.9，即绿染）而 v8 中性
（≈1.06）；对照文件（他 Sony 机身，v8）同 Display-P3 标签转换中性；
Preview.app 同文件正常。**裁定 = automatic 收紧**（`.automatic` 恒 v8；
v9 经面板显式 forceV9 可达），选择理由与遗留面（forceV9 显式档、重入口
条件、decodeParamsHash 一次性漂移注记）全文见 `V2M-01-DECISIONS.md` +
`evidence/V2M-01/d2-bisect/TRANSCRIPT.md`。

## 三、定向轮 + 全套终值（T6）

- 定向轮（受影响 bundle，终码态）：`App 818/4/0`（373s，peak 2832MB）/
  `Sessions 284/9/0`（66s）/ `IOP 687/5/0`（423s，贴线 7467MB→全套轮
  7546MB）/ `Library 729/4/0`（82s）——全绿。
- **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all` →
  **`TOTAL|3851/35/0|2047s` exit 0**；0 fail、0 MEMFAIL、七 bundle 全 8G 门内
  （IOP 7546 / IOPParity 6669 / Export 6400 / App 2832 / Sessions 1627 /
  Library 621 / Layers 806 MB）。
- **对账**：3848（M6-5 T9 基线）+ ΔN₁ 3 = **3851 精确**。逐 bundle
  executed Δ：IOP +1（T2）/ App +2（T1）/ 其余 0 = 段和闭合。
- **skip 对账**：35 = 基线 24 + 11；+11 全部 = 真 RAW 样张域缺席族
  （IOP RAWDecoderTests×4 / Sessions SessionThumbnailProvider+Catalog×5 /
  Layers testRealRAWRoundTrip×1 / Export testRealRAWWalk×1）——环境漂移非
  本批所致（本批 T2 时点的类过滤轮即已 4 skip，先于 T3/T4/T5 任何变更）；
  供件 = Plan-05 samples 域缺席，`LIGHTAMER_RAW_SAMPLES_DIR` 未指。
- **GrainTests 单 flake 事件**（前置 IOP 定向轮 1 failure）：同码 T2 轮全绿 +
  单类复测 8/0/0 + diff 窗口不含 grain/seed/identity → GPU 状态序漂移
  （M2-7-3 先例族）；全套净轮未复现，终值取净轮，处置符合先例。

## 四、GUI 走查证据与 Blocked-Env 登记（正本 = `gui-acceptance/v2m/MANIFEST.md`）

- **DONE**：D-2 基线复现（step1-editor-A.png）+ 修后视口复验（walk-0-grid.png，
  legacy 面自然色）+ Preview.app 交叉证人（step7-preview-witness.png）；
  T1 面板挂载 + 参考图添加部分面（walk-9/10/15，三段 picker + 参考行 +
  权重 1.00 全数在位）。
- **Blocked-Env 四项**：D-1 三零消除点击（项目面 solve 按钮 AX 触发不达 +
  hasImage 面板级异常疑点；legacy 面恢复会话宿主旧 InspectorView 无 tab
  rail）/ D-3 加固循环（项目重开路径 menu-item 合成点击被菜单追踪吞）/
  D-4 标题计数（CGEvent cmd+click 旗标不生效——m6-closeout「多选清选不可靠」
  同款；Edit>全选未达 browser model）/ D-5 toast（依赖 D-4 同一动作）。
  单测/机检面已闭合，屏面证据随 V2M-02 T2 Manual-Only 走查批（建议 omp
  computer-use 通道）复走。
- **Registered-obs**：导入进度条停滞（Media 拷贝完成后 >10min 未发布完成态，
  主线程活跃非挂死——import-stall-sample.txt；疑 M2-9 F-1 家族，批外）。

## 五、红线自检（T6 收口核对，全部 PASS）

- `git diff 7b252db1..HEAD` 全批 = 9 文件（App 面板/视图 ×4 + Core/Decode
  RAWDecoder + Tests ×3 + LightamerApp + SessionBrowserView），337+/75-。
- `LightamerIOP/` 零 diff ✓；全部 `*.metal` 零 diff ✓（D-2 修订口未行使）；
  `Project.swift` 零 diff ✓（零新 SPM、零新测试文件、tuist generate 未触）；
  `*.xcstrings` 零 diff ✓（D-5 主形态，翻案口未行使）；sidecar/schema/
  Pipe/History/V50Order/DrtRecord/GradeCatalog/Registry/六格式矩阵封存面
  零 diff ✓。
- `\.runModal(` App/Sources 零命中 ✓；`String.LocalizationValue("…\(x)…")`
  插值禁形代码行零命中（唯一命中 = LightamerApp.swift:2069 doc comment
  注记字面，注释免疫豁免锚；拼接形豁免锚 ExportInspectorView.swift:433
  原位未触）✓。
- UserDefaults 零新键 ✓（diff 面零命中）；`zh-audit --check` PASS ✓；
  工作树零新增 untracked 源文件 ✓（探针/走查产物全落 /tmp 即弃域与
  gitignored 证据域；`input/RAW/GREENCAST-7RM5.ARW` = untracked 样张域，
  gitignore 在册）。
- UserDefaults 既有键零触；构建 `caffeinate -dis` 包裹；单测走
  test-direct（零 xcodebuild test）。

## 六、翻账建议（闭环批统一执行，本批不动账面）

1. **GUI-M6C 四行解锁状态申报**：03/05/08（Blocked-Defect → **代码面已清**，
   屏面证据待 V2M-02 T2 走查批复走后翻 Executed）；06 数值面本批未走
   （依赖 solve 点击，同批）；D-2 色彩目测解锁声明 = **已解锁**
   （V2M-D2-02 视口复验 PASS + Preview 证人；06/07/26 行的色彩目测前提恢复）。
2. TODO「M6 收口走查缺陷登记」D-1..D-5 五行 → 翻「代码面 fixed（commit 链），
   屏面证据挂 V2M-02 T2」；GOAL-STATE 续接点 → 波 1 closed（待 ACCEPTANCE/
   双验收）→ 波 2 `V2M-02` 开工。
3. AGENTS「V2-Maintenance 架构增量」节：五修法形态 + ΔN₁=+3 + 全套终值
   3851/35/0 + RAW 9 automatic 收紧语义（v9 显式档语义 + 重入口条件）+
   `.sheet(item:)` payload 形（三对话框）+ 换图单通道 `switchCurrent` +
   loadCurrentImage 取消检查点约定。
4. **批外疑点上报（未动手）**：①项目面 colormatch 面板 `hasImage` 为 nil
   （`pipeCoordinator.liveImageURL` 在该面面板读 nil 而渲染链活跃）——疑环境
   注入或载入时序面，D-1 修复不经过该读法的正确性不受扰（单测+App 定向轮
   佐证），建议独立排查；②导入进度条停滞（Registered-obs，M2-9 F-1 家族
   疑似）；③真 RAW 样张域缺席（+11 skip 的环境因，供件由 orchestrator/用户
   备料后 3851 基线可再收敛 skip 面）。
