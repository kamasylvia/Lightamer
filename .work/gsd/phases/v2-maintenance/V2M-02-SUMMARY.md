# V2M-02 SUMMARY（波 2 清算批 V17 + Manual-Only GUI + S 件 + EXPORT-PRESET-01，2026-10-16 夜间批）

> 结论头：**PASS / 0 error + 0 minor（批内窗口；T2 通道受阻按纪律收兵登记，
> 非产物缺陷）**。T1/T3/T4/T5 五 commit 链 + 定向轮 + 全套对账闭合；T2 走查批
> 三条独立通道受阻（D-6 新缺陷登记），可达行集缩水为零如实登记。**ACCEPTANCE
> 不写**（按派发令）；**翻账不做**（闭环批统一，§六申报建议翻账点）。

## 一、任务逐个完成态与 ΔN 记账

| 任务 | 内容 | commit | ΔN | 验收要点实测 |
|---|---|---|---|---|
| T1 | V17 zh-audit 门扩展（specifier 深检 + Text 族 + 跨行族合门，八例 golden）+ 活体清偿 `catalog_session_remove_confirm_body %@` | `2ba1d1fe` | **0**（脚本侧非 XCT） | `--self-test` PASS（八例）；`--check` PASS（38 interp keys variant-PRESENT + spec-matched）；xcstrings 17 行尾块纯插入；SidebarView 零 diff；首跑分诊 transcript 在案（`evidence/v2m-02-t1/`） |
| T2 | Manual-Only GUI 走查批 | **无 commit**（local-only） | 0 | 通道受阻收兵——D-6/D-7/D-8 登记、四 V2M 行（E2-1）Blocked-Channel 保持、m6-closeout 余行逐行终态；证据 = `.work/gui-acceptance/v2m/`（t2-spin.sample.txt + diag-*.png + d3_cycle.py） |
| T3 | PATCH-LIVEPLANE（余量非零 → 修复臂：eager 释放双点 + 装载门 + stamp 同源） | `4914619c` | **+2**（`testLayerSelectReleasesHeldPatchFace` / `testMidFlightImageSwitchLeavesNoSessionFace`） | `--bundle App` 820/4/0（818+2）；既有四法不红 |
| T4 | RELEASE-DIRECT-INJECT（防御脚本形态） | `4ca893cb` | **0** | 直启探针 **PROBE PASS**（rc=0 + 主窗 up）；余量盘点 = 当前债形态已消（WebP 静态内联，PackageFrameworks 目录不存在）；产线源码零 diff；transcript = `evidence/v2m-02-t4/` |
| T5 | EXPORT-PRESET-01（命名预设层：值面捕获 + 纯函数投影 + 7 键 + 管理 UI） | `de786663` | **+4**（`ExportPresetTests` 四法） | `--bundle App` 824/4/0（820+4）；xcstrings 119 行尾块纯插入；zh-audit PASS；封存面零 diff |
| T6 | 条件任务（D-5 并入）+ 收口 | 本批 | — | D-5 波 1 已清 → **零动作**；Export 定向轮 379/5/0（波 1 同值）；全套见 §三 |

**ΔN₂ = +6**（T3 +2 + T5 +4 = 预期带 +2..6 的上界，逐任务如实记账；V17/T4
脚本侧非 XCT 记 0）。

## 二、T2 走查批：通道受阻定案与四 V2M 行处置（E2-1 硬义务）

**正本 = `.work/gui-acceptance/v2m/MANIFEST.md`「V2M-02 T2 走查批」节**
（local-only）。要点：

- **新缺陷 D-6（error 级候选，登记不修）**：重开项目态编辑器不可用——视口
  legacy 空态卡/黑 + filmstrip 24 步循环全部零响应 + 主线程 SwiftUI
  AttributeGraph spin（CPU 99.9%，sample 全框架帧零 app 帧）。触发 =
  进程重启后重开项目（波 1 同会话新建路径健康）。
- **D-7**（导入停滞，波 1 疑点同面复现）+ **D-8**（legacy 会话建立不可达）
  注记在案。
- **四 V2M 专属行**（V2M-T1-02 / V2M-D3-01 / V2M-D4-01 / V2M-D5-01）：
  **Blocked-Channel 保持**。D-4「快照上移」返工预案**不触发**——触发条件
  （复验仍见 0 张）要求对话框实际呈现，通道不可达 ≠ 复验见 0；裁定与证据
  链 = `V2M-02-DECISIONS.md` D-V2M2-2，**返工与否上报 orchestrator 裁定**。
- m6-closeout 余行（03/05/06/07/08 复查、16-19、26、32/33、34-38、39、40）
  逐行终态在 MANIFEST：26 = Blocked-Env（UltraHDR 供件缺口）、39 = Env
  （随 30/31 供件族）、余 = Blocked-Channel（D-6/D-7/D-8 阻断面）。C 类
  硬锁行（24/25/27/28/29）不入波（plan 条款）。30 行显式排除（SAM 资产
  供件族）维持。
- 供件缺口清单（不变项）：UltraHDR JPEG 样张 / SAM layer B 资产 / 真多人
  照片 / HDR 显示器。

## 三、定向轮 + 全套终值（T6）

- 定向轮（本批实触 bundle，终码态）：`App 824/4/0`（386s，peak 2832MB）/
  `Export 379/5/0`（211s，peak 6584MB）——全绿（Export = 波 1 终值同值，
  封存面零触佐证）。
- **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all` →
  **`TOTAL|3857/35/0|2047s` exit 0**（OK direct launch）；0 fail / 0 MEMFAIL /
  七 bundle 全 8G 门内（IOP 8062 / IOPParity 8111 贴线带内〔波 1 7966 ±3% =
  7727..8205〕/ Export 6883 / Sessions 1665 / App 2832 / Layers 808 /
  Library 621 MB）。
- **对账**：3851（波 1 终值）+ ΔN₂ 6 = **3857 精确**；逐 bundle
  executed Δ：App +6（T3 +2 / T5 +4）/ 其余六 bundle 逐值与波 1 终值相同
  = 段和 687+460+494+729+284+379+824 = 3857 闭合。
- skip 对账：35 = 波 1 同值（真 RAW 样张域缺席族 11 + 基线恒有 24；本批
  零新 skip、供件域未变）。

## 四、红线自检（T6 收口核对）

- 全部 `*.metal` 零 diff ✓；`LightamerIOP/` 全域零 diff ✓；
  `LightamerCore/Sources/Export/`（六格式矩阵/ExportQueueContract）零
  diff ✓；`LightamerSidecar.swift` 零 diff ✓；V50Order/GradeCatalog/
  Registry/HistoryStack 封存面零 diff ✓。
- `Project.swift` = 恰一行测试登记（dependencies 块零 diff、零新 SPM）✓；
  新测试文件 `ExportPresetTests.swift` = Project.swift + BUNDLE-MAP 同批
  登记 + `tuist generate` 恒末位 ✓（L041）。
- `*.xcstrings` = T1 清偿键 17 行 + T5 预设键族 119 行，两批**尾块纯插入**
  （diff 全 `+`，历史键字节与顺序零触碰）✓；`zh-audit --check`（V17 新门）
  PASS + `--self-test` PASS ✓。
- UserDefaults：唯一新键 `export.presets`（AGENTS 已登记）；既有 `export.*`
  六键零触 ✓。
- `\.runModal(` App/Sources 零命中 ✓；`String.LocalizationValue("` 插值禁形
  代码行零命中（唯一命中 = LightamerApp.swift:2069 doc comment 注记字面，
  注释免疫豁免锚）✓。
- T2 时窗源码零 diff（走查批无 commit；`git status` 全程仅 .work 文档域）✓；
  工作树零新增 untracked 源文件（T4 探针/走查产物全落 /tmp 即弃域与
  gitignored 证据域）✓。
- 构建 `caffeinate -dis` 包裹；单测走 test-direct（零 xcodebuild test）✓。

## 五、批外疑点与新缺陷上报（未动手）

1. **D-6（error 级候选）**：重开项目态编辑器不可用 + 主线程 spin——建议
   独立修复批（sample + 复现配方 = `gui-acceptance/v2m/` t2 证据族；波 1
   D-1 修复不经过该面，与 `hasImage` 批外疑点①疑同域）。
2. **D-7**：导入停滞（M2-9 F-1 家族疑似）本批再复现一次——独立排查建议
   维持（波 1 SUMMARY 批外疑点②同条）。
3. **D-8**：legacy 会话建立通道——`LIGHTAMER_LEGACY_LIBRARY=1` 面的
   文件>打开/Import Folder 腿无响应；V2 #4（SESSION-LEGACY-READONLY）若
   立项应先修通道。

## 六、翻账建议（闭环批统一执行，本批不动账面）

1. **m6-closeout MANIFEST 行翻账**：03/05/08（D-1 修复后屏面证据仍挂——
   D-6 阻断，修复 D-6 后随走查批复走翻 Executed）；06/07 同；16-19/32-40
   Blocked 终态如实保持；26/39 Blocked-Env 保持。
2. **TODO**：V2M-02 五任务条目 → 翻「代码面 closed（commit 链 2ba1d1fe..
   de786663）」；D-6/D-7/D-8 → 新增缺陷登记行（修复批入口）。
3. **GOAL-STATE 续接点** → 波 2 closed（待 ACCEPTANCE/双验收）→
   VALIDATION/收尾批（V2M-01+02 两波合并 red_lines 总核对 + 翻账）。
4. **AGENTS「V2-Maintenance 架构增量」节**：本批已登记四行（V17 门 /
   PATCH-LIVEPLANE / EXPORT-PRESET-01 / RELEASE-DIRECT-INJECT）+ 全套终值
   行待回填（T6 docs commit）。
5. **make-dmg.sh embed 缺口**：分发脚本在 make-release-direct-launchable.sh
   先行跑过时产物自足；建议分发批把 embed 腿并入 make-dmg（或前置调用）。
6. **zh-audit V17 红线电池口径**：后续批 red_lines 引用形 = `--check` PASS
   （ABSENT/MISMATCH 零命中）+ `--self-test` PASS（AGENTS 已登记）。
