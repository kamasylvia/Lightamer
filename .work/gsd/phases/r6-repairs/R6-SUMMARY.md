# R6 修复批 — SUMMARY（2026-10-26/27）

基线 = `29be5cba`（全套 4287/39/0）。批 = T1 导入零行真修 + T2 omp
obs-3 消费 + T3 姐妹载体三件 + T4 收口。裁决正本 = `R6-DECISIONS.md`。

## 一、战果

### T1 导入零行真修（issue #4，commit `363e4387`）

- **归因锚点**：run tail `importProgress = nil` 直写
  （`LibraryProjectController.swift:459`）× coalescer 排队交付 job
  （terminal bypass `Task { @MainActor flushTerminal() }`，:810-814）
  的 main-queue 交错——nil 先落、交付后到 = 终态被复活且无后继写者 →
  `ImportProgressModifier` 的 nil-finish 分支
  （`WorkspaceHostView.swift:1119-1143`，grid 行到达发布的唯一触发）
  永不触发。DB 行恒在、grid 永零行、线程 idle——R5-2/obs-4 表型全
  解释；负载敏感 + 低载 2/5 = 纯调度竞态。
- **修法**：`ImportProgressCoalescer.invalidate()`（三面锁内失效检查，
  已交付不回撤）；run tail nil 直写前调用——nil 恒为终写者。
- **回归**：+3 法（机制面确定性交错 2 + 生产缝 runImport 终态稳定 1，
  发布断言非时间窗轮询，阈值申报见 DECISIONS §1.3）。

### T2 omp obs-3（产线零 diff，文档化出口）

- **实测扩面**：GUI 探针实锤 id 覆盖为**列级系统行为**——Inspector
  列全部无显式容器化控件（迁移按钮 + close/双 picker/四 slider/
  toggle/solve）AXIdentifier 均被 `InspectorView.swift:133` 祖先覆盖；
  仅 latitude/placement 两显式 contain section 存活。
- **出口**：文档化（`.work/gui-acceptance/r6-axpress/
  Synthetic-Input-AXPress-Notes.md`）——单点修触碰 frozen inventory +
  `.ignore` 形态可能吞 title 反杀 by-title AXPress 通道；走查工具面
  统一 AXPress（role+title 寻址）。系统性列级容器化留独立批。

### T3 姐妹载体三件（issue #5/#6/#7，commit `95729b14`/`f77d3488`/`eba66447`）

- **判定**：重开同图 load 链全跳（`EditorWorkspaceShellView.swift:193`
  的 loadedImageURL guard + `PipeCoordinator.swift:1210` 的
  historyLoadedURL guard；restore/sync 腿唯一触发 = 真 load 与
  history 导航，重开后均无）→ **三载体（DRT/film/raw）全部同病，
  无一走「不修」分支**。
- **修法**：M8-FIX-1 同款——closeEditor 三 drop 调用行 + 三 drop
  函数本体删除，载体 doc 偏离申报；closeEditor doc 重写为家族全员
  豁免 + 各病链表型；processVersions doc 勘误句。
- **判别腿**：DRT 改写（close 后 terminalTailPolicy 两读面答保留值）/
  film 改写 + 新真渲染门腿（filmTailPolicy(.preview) close 后仍非
  nil）/ raw 新法（双 url overrides 经 close 存活）。

### T4 收口

- 封存面 15 项零 diff 核验在案（Core/IOP 自基线零 diff；WorkspaceModel
  逐 hunk 申报 = 载体族区段例外，见 DECISIONS §四）。
- 全套 `Scripts/test-direct.sh --all`（guard --wait + ps 清零 +
  `--monitor 21600` 伴跑 + nohup disown），4060s：

**全套终值 = 4292/35/0**（基线 4287/39/0 + Δ5）

- Δ executed = **+5 精确吻合新增测试法数**（Coalescing +2 /
  CompletionRegression +1 / FilmCoordinator +1 / SidecarV5 +1）；
- skip 39→35（-4）= 宿主态族波动（M8-FIX-ACCEPTANCE obs-1 同族：
  SkinRegionGeometryTests 等宿主 Vision 态条件 skip 的环境面），
  本批零 skip 变更（新法全 executed、改写法零 skip），零失败；
- per-bundle：IOP 788/1/0（RSS 5702MB）· IOPParity 529/11/0（4256MB）
  · Layers 507/5/0（850MB）· Library 779/4/0（761MB）· Sessions
  285/4/0（1208MB）· Export 385/4/0（4244MB）· App 1019/6/0（2832MB）
  ——全部 <8G MEMFAIL 门，IOPParity 529/11 与 M8-FIX 登记值逐位同。

## 二、commit 列表

| commit | 内容 | issue |
|---|---|---|
| `363e4387` | fix(r6): quiesce import coalescer before the nil terminal (zero-row) | #4 |
| `95729b14` | fix(r6): keep the DRT carrier across editor close (M8-FIX-1 sister) | #5 |
| `f77d3488` | fix(r6): keep the film carrier across editor close (M8-FIX-1 sister) | #6 |
| `eba66447` | fix(r6): keep the RAW overrides carrier across editor close (last sister) | #7 |
| （收口） | docs(r6): R6 ledger — summary + decisions | — |

## 三、卫生

- GUI 探针（T2 film probe，pid 22313）用后 quit→kill 清零复核
  （parentage 核验后处置）；全套起跑前 ps 零 Lightamer 实例验证。
- defaults 零触碰（探针 fixture 走 /tmp throwaway 项目）；
  `/tmp/r6-t2-probe`（v1 老档副本）+ `/tmp/r6-ax-probe.swift` 留存
  下轮复用；未 checkout 任何参考仓；`.work/gsd/research/` 与参考仓
  路径零触碰。
- px 代理：gh 建单期开（订阅超时一次，清死代理残留后成功）；全套
  收口后 `px --stop`。
