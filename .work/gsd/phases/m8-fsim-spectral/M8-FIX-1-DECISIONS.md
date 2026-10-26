# M8-FIX-1-DECISIONS — omp 终审 M-1 修复批执行期裁决（2026-10-26）

> 正本关系：缺陷正本 = `ACCEPTANCE-OMP.md` §二 M-1；执行申报 = 本文（诊断
> 节 = T1 实证定罪，修复节 = T2 缝位裁决，回归节 = T3）。基线 HEAD =
> `c0f1e5a1`。本文由 executor 维护，逐任务 commit。

## 一、T1 诊断节：双候选均证伪，真根因 = 第三机制（closeEditor 载体丢弃击穿 mint）

### 1.1 实证方法

诊断构建 = HEAD 产品码 + 五处临时 stderr 插桩（`restoreProcessVersion` /
`setProcessVersion` / `dropSessionProcessVersions` / `filmRecordDidChange`
读腿 / `makeSidecarDocument` 写腿），跑完即弃（零入仓）。驱动 = probe 缝
`-la_film_probe /tmp/m8fix-probe`（干净 fixture 域，`sidecar=no` 实证）+
pyobjc AX 驱动（AI 分析 sheet 关闭 → 按 AXTitle 定位「启用胶片模拟」按钮 →
CGEvent 真实点击）。

### 1.2 复现 A（干净对照路径）：omp 表型不可复现

```
[editor-probe] row id=1 file=float32-gradient.tif sidecar=no
[m8fix-diag] restoreProcessVersion v=2 map=…float32-gradient.tif=2   ← mint 落地
[editor-probe] load file=… loaded=yes rendered=yes                    ← 无直调自愈
[m8fix-diag] filmRecordDidChange docProcess=2 …                       ← 启用时 carrier = current
```

启用后 `FilmMigrationAction.evaluate(2, true, false)` = `.alreadyCurrent` →
**迁移行隐藏**。omp 候选①（probe mint 未执行）**证伪**——mint 在 probe 路径
与正常路径同构落地（同一 `PipeCoordinator.load` pristine 分支，App/
Sources/Lightamer/State/PipeCoordinator.swift:1262）。

### 1.3 复现 B（疾病路径）：omp 表型逐项复现

「返回图库」（WorkspaceTopBar onCloseEditor → `closeEditor`）后再启用：

```
[m8fix-diag] restoreProcessVersion v=2            ← 载入 mint
[m8fix-diag] dropSessionProcessVersions count=1   ← 关图丢弃（mint 唯一副本）
[m8fix-diag] filmRecordDidChange docProcess=0     ← 关图后启用：carrier 缺席 = legacy
```

截图（`/tmp/m8fix-s2.png`，即弃）与 omp-01/02 **逐像素同构**：图库面 +
Film 面板共存（`filmPageActive` 为 InspectorState 全局态，面板跨 phase
存活；enable 按钮经 AXTitle 在图库态可点）。omp 候选②（carrier 缺席读腿）
方向正确但非根因本体——读腿按契约行事（缺席 = legacy），**缺席本身是
closeEditor 制造的**。

### 1.4 根因锚点（file:line）

- **丢弃点**：`App/Sources/Lightamer/UI/Shell/WorkspaceModel.swift` —
  `closeEditor()` 内 `dropSessionProcessVersions()`（M6-2-01 T3 注册的
  「the process carrier rides the close」）。无 sidecar 新档的 mint 仅存于
  carrier（首次提交编辑才写盘），关图即孤儿化。
- **零 heal 缝**：同图重开**不跑任何载入腿**——`EditorWorkspaceShellView
  .loadCurrentImage` 的 `loadedImageURL != url` 守卫（EditorWorkspaceShellView.swift:193）
  + `PipeCoordinator.load` 的 `historyLoadedURL != url` 守卫（PipeCoordinator.swift:1210）
  双双跳过（EditorState/coordinator 状态跨 close 存活，close 只翻 phase +
  drop 载体）。process 载体又无 film/drt 式的 history re-sync 腿（process
  无 history 槽位——M8-3-DECISIONS 二裁定）→ 丢弃后无任何路径重建。
- **缺陷表达**：drop 后的首次提交（omp = Film 面板启用）只经
  `syncFilmCarrierWithHistory` 重建 film 载体；process 载体缺席 →
  ①`documentProcessVersion` = legacy → 迁移行可见；②渲染链
  `processVersion(for:) ?? .legacy` → 密度臂；③写腿
  `processCarrier.rawValue == 0 ? nil`（PipeCoordinator.swift:1605）→
  sidecar `filmRecord` 在而 `process` 键缺席——omp 三项物证逐项吻合。
- **omp S1 会话还原**：其合成输入环境在启用前发生过 phase 回跳（obs-5
  强制退出窗自现 + obs-6 sheet 遮挡 = 同环境杂扰面），启用发生在 close 后
  的图库态面板上 = 复现 B 的链。omp S2（omp-07 编辑器面正常）与 executor
  walk-02（「mint process=2」注记，其走查流含迁移步 = 落盘 process:2 的
  假 mint 实证）不矛盾。

### 1.5 正常用户路径同病判定（omp 挂账问题的回答）

**同病**。疾病链不需要 probe：新图开图（mint，零编辑）→ ⌘W/返回图库 →
图库态 Film 面板启用 → 同 omp 表型。重开同图再操作则被零载入守卫遮蔽成
「关图前的旧状态」——close 与首次提交之间没有任何 heal 机会是通用的。

### 1.6 同根姐妹缺口登记（不在本批修复面，挂 M8-3+ 账）

film/DRT/rawOverrides 三载体同受关图丢弃 + 同图重开零载入：已启用胶片的
图 close→reopen（无载入）后，渲染门 `filmTailPolicy` 读空 carrier → 胶片
腿静默失效，直到下次 film commit 的 `syncFilmCarrierWithHistory` 重建。
面板读腿（history 优先）掩盖观感（面板显示控制项而渲染不跑胶片）。process
之所以单独出缺陷 = 其值不在 history 投影域（无 re-sync 源）。三载体的
修复（close 保留或 reopen 时 re-sync）= 独立批裁决面，本批不扩面。

## 二、T2 修复节：process 载体免除关图丢弃（KD-3 家族形的注册偏离）

### 2.1 缝位裁决

**修复 = `WorkspaceModel.closeEditor` 不再 drop process 载体**（删除
`dropSessionProcessVersions()` 调用与函数本体）。备选否决：

- **读腿回落 current**（omp 候选②处方）：被任务书铁律否决——判定键必须
  是创建代际，「键缺席」裸判会把 sidecar 无键的老档误判 current；按创建代
  际判定需新持久面（零 sidecar 新键红线）。且根因在丢弃不在读法，读腿
  改法治标。
- **commit 时 re-mint**：第三写腿，违反 M6-2 OQ-5 零自动迁移纪律（值只在
  载入双腿 + 显式迁移落位）；且需文件 IO 探测 sidecar 在否。否决。
- **close 时强制写盘**：pristine 零编辑档凭空生成 .lra，违反「默认不入
  map 不写 sidecar」家族语义。否决。

### 2.2 保留的安全性审计

- **老档零误判**：legacy 档 carrier 恒缺席（`restoreProcessVersion(.legacy)`
  即 remove），v1 档 restore=1——保留语义不触碰任何迁移判定键；「新档 =
  current」由 mint 值真实存活达成，非缺席裸判（语义铁律兑现）。
- **零新写腿**：OQ-5 纪律维持（载入双腿 + 显式迁移，close 保留只是不丢）。
- **sidecar/schema 零触**：写腿、LightamerSidecar、HistoryStack、
  HistoryHash 零 diff。
- **陈旧条目惰性**：条目 per-path、值 Int；载入腿每次真载入覆盖；读面仅
  当前文档渲染/写盘/面板三处——跨 close 保留无越图泄漏。
- **film/drt/raw 载体不动**：close 丢弃语义对本批仅豁免 process（2.1 的
  唯一正缝论证见 1.6——process 无 history 源，drop 即真丢；其余三载体有
  re-sync 源，drop 的伤害形状不同，归姐妹缺口批）。

### 2.3 契约修订登记面

- `WorkspaceModel.swift`：`processVersions` doc 注释 + `closeEditor` doc
  注释（M8-FIX-1 偏离申报 + 动机）。
- `AGENTS.md` 架构索引「process version」不变量行：追加 close-保留注记。
- `.work/ARCHITECTURE-ARCHIVE.md` M6-2 节 App 面行（「关图丢弃」）：追加
  勘误行（历史行不改写惯例）。

## 三、T3 回归节

- **#7 改写**：`testCloseDropsAndReopenRestoresTheCarrierIdempotently` →
  `testCloseKeepsTheCarrierAndReopensStayIdempotent`（close 保留 + 同会话
  重开读保留值 + 新装配重开从文件恢复 + **legacy 判别腿**：无键档跨 close
  恒缺席 = OQ-1 不被动升级在 close 域的延伸）。
- **#9 新增**：`testEnableAfterCloseWithoutReloadKeepsTheMintedGeneration`
  ——omp M-1 链的端到端反转，透过生产缝（`FilmPanelModel.enableFilm` =
  FilmPanelView 按钮的真实路径，非内部载体面直调）：①`documentProcess ==
  current` ②`migrationAction == .alreadyCurrent`（行隐藏）③flush 后
  sidecar **同时**含 `filmRecord` 与 `process: 2`（omp 物证反转）④判别力
  腿 = v1 孪生仍 `migrate`（行判别力未被修复盲化）。测试增量 ΔN =
  +1 新法（#7 改写 = 既有法语义改写零增量）；带 [+3..+8] 下限修正申报见
  SUMMARY。

## 四、观察项与申报

- `(deviation)` T3 ΔN = +1（任务书预估 +3..+8 按「新增法数」读法落
  下限外——疾病链回归以单法承载四面断言，与 FilmPanelSpectralUITests
  端到端先例同形态；#7 改写为零增量语义移动）。
- `(measured)` T1 诊断轮：干净路径 mint v=2 + 启用 docProcess=2（复现 A）；
  close 后启用 docProcess=0（复现 B）；插桩五处即弃零入仓。
- `(measured)` omp 截图布局（图库面 + Film 面板）由复现 B 截图逐像素同构
  佐证——omp S1 = close 后启用态。
- 姐妹缺口（film/DRT/raw 载体 close 丢弃 × 零载入重开）= M8-3+ 挂账
  （1.6 节）。
