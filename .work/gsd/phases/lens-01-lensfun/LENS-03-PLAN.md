---
phase: lens-01-lensfun
plan: "LENS-03"
title: "plan L3 — projection（Alcedo 四型移植 + 枚举 8 槽 + 非 rectilinear 硬拒解除）+ TCA ROI 三通道 union 放宽 + 数据分发硬化（随包钉版快照 + seeder + 手动检查更新）+ NOTICE/许可全套（T1 投影移植与 kernel / T2 TCA ROI / T3 数据分发 / T4 NOTICE 与许可 / T5 收口）"
wave: 3
depends_on: ["LENS-02"]
autonomous: true
requirements: ["charter = UQ-R4（8bd94370）——FEAT-DEV-07 的 projection + profile database（数据面）收口波", "research 正本 = phases/lens-01-lensfun/RESEARCH.md（b2b31909）§Route Matrix 吸收件 1/§Upstream Facts/§Plan Split L3 行", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LENS-6/-8 + X7/X8 + hazards H-L3 + 红线 15 条）", "基线 3991/37/0 + LENS-01/02 终态（对账式）；本 plan 分账 +16..26", "C 档停位 = 与 LENS-04 并行波各自闭环后一并汇报停", "H-L3 不可延后件：NOTICE/许可归属随本 plan 落地，禁延后"]
success_criteria: "SC 全可机检——T1：LensProjection（8 槽枚举 + 四型激活 fisheye/equisolid/stereographic/orthographic + rectilinear 恒等基态；Alcedo GPL 移植 + 版权头）+ LensKernels.metal 投影数学（source/target 投影段）+ Params additive（targetProjection/sourceProjection，默认 rectilinear 恒等）+ resolve() 非 rectilinear 硬拒解除（target 未设维持保守）+ 面板 target picker + projection golden（Alcedo 同源对表数值入 evidence）；T2：modifyROIIn resolved-XML 路径真三通道 union（D7 注记兑现，纯 CPU 边框映射）；T3：Resources/Lensfun 钉版快照 + README（来源+SHA+日期+unmodified）+ folderReference + seeder（哨兵字节等跳过）+ 优先序 customPath > 种子 > 下载 > absent + 设置面手动检查更新（tar.bz2 + SHA 校验失败拒绝 + L057 缝）+ SHA/优先序单测；T4：NOTICE 三条目（lensfun CC-BY-SA + Alcedo + RawLab）+ Resources/Licenses/Lensfun 全套文本 + fixtures README 一致性复核"
estimated_tests: "+16..26（T1 +9..14〔投影 golden 四型 + 恒等负测 + 硬拒解除回归〕/ T2 +1..2 / T3 +5..8〔SHA/seeder/优先序〕/ T4 0 docs；越带申报理由）"
test_bundles: [IOP, IOPParity, APP]
baseline: "3991/37/0 + LENS-01/02 终态（对账式）"
expected_all: "LENS-02 终态 + ΔN（LENS-03 分账 +16..26；全套对账归 LENS-04 收口轮）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 15 条；本 plan 特别面 = LensKernels.metal 投影段为第二处 kernel 触碰（L2 scale 之外唯一）；LensProjection.swift/LensAutoCrop.swift 双移植件 GPL 头三件套（NOTICE 条目 = T4 汇总兑现）。"
  - "H-L3 硬门：T4 NOTICE/许可面与 T3 数据分发同批落地——T3 落而 T4 缺 = 流程违规（share-alike 归属不可延后）；T4 docs-only 但机检必过（NOTICE 含三条目 grep）。"
  - "投影默认恒等门：targetProjection 默认 rectilinear = 全链零行为（默认中性零行为门红线 12——非投影用户文档逐字节不变）；非 rectilinear entry + target 未设 = 保守拒绝维持现状。"
  - "数据资产纪律：钉版快照 SHA-256 校验失败拒绝安装（禁静默装入未知数据）；无自动更新（D-LENS-6）；customPath 既有语义零改。"
  - "TCA ROI 放宽仅 CPU 边框映射（D7 注记域）——kernel 零触（T2 与 T1 分 commit）。"
files_modified:
  - LightamerIOP/Sources/Lens/LensProjection.swift            # T1：新建——投影枚举 8 槽 + 四型数学参数面（Alcedo 移植 + GPL 头）
  - LightamerIOP/Sources/Lens/LensKernels.metal               # T1：投影数学段（source/target 投影；与 T3 scale 段分 commit）
  - LightamerIOP/Sources/Lens/LensModule.swift                # T1：Params additive targetProjection/sourceProjection + uniforms 折入 + T2 modifyROIIn 三通道 union
  - LightamerIOP/Sources/Lens/LensfunMatch.swift              # T1：resolve() 非 rectilinear 硬拒解除（entry type → sourceProjection 折入）
  - App/Sources/Lightamer/UI/Inspector/LensPanelView.swift    # T1：§3 投影 picker（target 四型 + rectilinear 基态）+ T3：§5 数据管理段（版本/SHA readout + 检查更新按钮）
  - App/Sources/Lightamer/Session/LensfunDataDistribution.swift # T3：新建——seeder + 更新通道（下载 + SHA 校验 + 安装）
  - App/Sources/Lightamer/Session/LensfunDownloadService.swift # T3：优先序接线（customPath > 种子 > 下载 > absent；legacy 下载路径保留降级臂）
  - App/Sources/Lightamer/UI/Shell/LightamerShell.swift       # T3：启动装臂接 seeder（:920-927 邻域——种子优先于下载）
  - Resources/Lensfun/                                        # T3：新建——钉版 version_1 xml 集 + README（来源/SHA/日期/unmodified）
  - Resources/Licenses/Lensfun/                               # T4：新建——cc-by-sa-3.0.txt + 数据库归属 README
  - NOTICE                                                    # T4：三条目（lensfun 数据 CC-BY-SA-3.0 / Alcedo 投影 / RawLab auto-crop）
  - Resources/Localizable.xcstrings                           # T1/T3：投影 picker + 数据管理新键尾块纯插入
  - Tests/LightamerTests/LensProjectionGoldenTests.swift      # T1：新建（IOPParity——四型 golden + 恒等负测）
  - Tests/LightamerTests/LensProjectionResolveTests.swift     # T1：新建（IOP——硬拒解除/枚举槽位/params 折入）
  - Tests/LightamerTests/LensfunDistributionTests.swift       # T3：新建（IOP——SHA 校验/优先序/seeder 哨兵）
  - Project.swift                                             # T5：Resources/Lensfun + Licenses folderReference + 三个新测试文件入数组
  - .work/gsd/phases/lens-01-lensfun/LENS-03-SUMMARY.md       # T5
  - .work/gsd/phases/lens-01-lensfun/LENS-03-DECISIONS.md     # T5（对表数值来源 + 键清单 + 偏差）
---

# Plan LENS-03 — plan L3：projection + 数据分发硬化 + NOTICE/许可

> **裁决正本** = `CONTEXT.md`（D-LENS-6/-8 + X7/X8 + H-L3）；规格正本 =
> `RESEARCH.md`（§Route Decision Matrix 吸收件 1 / §Upstream Facts /
> §Plan Split L3 行「projection 可拆独立波；NOTICE/许可件不可延后」）。
>
> **并行注记**：本 plan 与 LENS-04 并行（触碰面不相交：本 plan =
> kernel 投影数学 + 数据分发 + NOTICE；04 = params 持久化 + 验收面）；
> **C 档停 = 两 plan 各自闭环后一并汇报**。两 plan 串行执行机（单重活
> 制）下按 orchestrator 排程交错，产物面互不阻塞。
>
> **裁定权归属钉**：无用户裁决分支；扩面触发（8 型全量激活 / CIRCLE /
> 自动更新 / 链库 lensfun）= 停手上报。
>
> **执行序**：T1 → T2 → T3 → T4 → T5（T3/T4 硬绑同批闭环）。

## ΔN 预算表（逐任务，LENS-03 分账带 +16..26；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 投影移植 | **+9..14** | 四型 golden + rectilinear 恒等 + 硬拒解除 + 枚举槽位 + params 折入 | IOPParity + IOP |
| T2 TCA ROI union | **+1..2** | 三通道 union 边框断言 | IOP |
| T3 数据分发 | **+5..8** | SHA 校验/优先序/seeder 哨兵/更新失败降级 | IOP（纯面）+ App |
| T4 NOTICE/许可 | **0** | docs-only（机检 = grep 三条目） | — |
| T5 收口 | **0** | docs + Project.swift + tuist generate | — |
| **合计** | **+16..26** | 起算基 = LENS-02 终态 | 三新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **四型起步 + 8 槽枚举预留**（D-LENS-8）：激活 = fisheye/equisolid/
   stereographic/orthographic；panoramic/equirectangular/thoby 槽位编译
   期穷举指向（未激活 = unreachable 臂 + 注记）。
2. **随包钉版 + 手动检查更新 + 无自动更新**（D-LENS-6）。
3. **NOTICE 三条目不可延后**（H-L3）。
4. **targetProjection 默认 rectilinear = 恒等**（D-LENS-8 + 红线 12）。
5. **TCA ROI 放宽 = 纯 CPU 边框映射**（RESEARCH §Geometry Seam D7 注记
   ——kernel 零触）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lens-01-lensfun/CONTEXT.md`（D-LENS-6/-8 + X7/X8 +
  hazards + 红线）
- `.work/gsd/phases/lens-01-lensfun/RESEARCH.md` §Upstream Facts /
  §Route Decision Matrix 吸收件 1 / §Plan Split L3 行
- Alcedo `lens_calib_runtime.hpp:29-119`（GPU 参数全型——移植对照正本）
  + `metal/shader/lens_calib.metal`（投影数学移植体）+
  `lens_calibration_resolver.cpp:218-296`（hugin 重标对照）
- RawLab `RawLabMac/build.sh:63-65` + `third_party/lensfun/README.md`
  （打包/钉版形）+ `lutools/third_party/lensfun/`（许可文本全套样例）
- LutLibraryStore seeder 先例（AGENTS.md M2-5 节：哨兵 = 存在且字节数相
  等跳过 + folderReference 纪律）+ L057 节（面板缝）
- `.work/LESSONS.md` L041 + AGENTS.md M2-5 KD-4/KD-3（可配根/注入面先例）

---

## T1 — projection（Alcedo 四型移植，D-LENS-8，X8）

> 本 plan 唯一 kernel 大触碰：投影数学段（source/target 投影）；
> `LensfunMatch.resolve():199-201` 非 rectilinear 硬拒随之解除。

**read_first**：`RESEARCH.md` §Route Matrix 吸收件 1 + §OQ-8；Alcedo
`lens_calib.metal` 全文（移植体——GPL，同源对表合法）+
`lens_calib_runtime.hpp:35-45,:53-119`（枚举/参数结构）；`LensfunMatch
.swift:194-210`（resolve 硬拒现状）；`LensKernels.metal:20-50`（半径约
定/求值序——投影段插入位面核）；CONTEXT §X8（合规三件套）。

- **action**：
  1. GPL 移植 `LensProjection.swift`（IOP）：投影枚举 8 槽（
     rectilinear/fisheye/panoramic/equirectangular/orthographic/
     stereographic/equisolid/thoby）+ 四激活型参数面（各自映射函数 CPU
     侧形式，供 golden 与 ROI 用）+ rectilinear 恒等基态；文件头 =
     Alcedo 版权 + 修改标注 + NOTICE 指针（§X8 三件套）。
  2. `LensKernels.metal` 投影数学段：source/target 投影映射（Alcedo
     metal 同源对表移植；求值序 = source 投影归一 → 畸变/TCA/渐晕既有
     段 → target 投影——与 Alcedo 语义对齐，头注释钉死求值序修订）。
  3. `Params` additive：`targetProjection: String?`（nil = rectilinear
     恒等）+ `sourceProjection: String?`（resolve 时自 entry `<type>`
     折入）；encodeIfPresent 零漂移专测随批。
  4. `resolve()` 硬拒解除：非 rectilinear entry + targetProjection 已
     设 → entry type 折 sourceProjection 继续解析；target 未设 → 维持
     现状拒绝（blit identity + log）。
  5. 面板 target picker（§3 段尾追加：rectilinear 基态 + 四激活型；
     预留槽不可选或隐藏——DECISIONS 申报终形）。
  6. 测试：四型 golden（IOPParity——合成参考 = Alcedo metal 数学同源对
     表，对表数值来源入 DECISIONS；门 1e-5 warp 级）+ rectilinear 恒
     等负测（默认/显式基态逐字节）+ 硬拒解除双臂（target 设/未设）+
     枚举穷举编译面（未激活槽 switch unreachable 断言）+ params 零漂
     移负测。
- **验收标准（机检）**：
  - 构建绿；LensProjection.swift 版权头三件套 grep 在位。
  - 四型 golden 在册且对表数值来源落 DECISIONS；rectilinear 默认恒等
    （默认中性零行为门）。
  - grep：投影枚举恰 8 case；未激活 3 槽有显式注记；`resolve()` 拒绝
    臂带 target 未设条件。
  - `--bundle IOPParity` + `--bundle IOP` 定向零回归。
- **commit**: `feat(lens03): port alcedo projection math for four fisheye types`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（默认 rectilinear =
  零行为差）；偏差（求值序微调/对表数值采样点）= DECISIONS 申报；
  **禁激活预留 3 槽**（D-LENS-8）；**禁透视/keystone 混入**（ashift 族
  15.0 域，RESEARCH §Seam 既定分工）；**禁改既有畸变/TCA/渐晕段数学**
  （投影段纯增量）。

## T2 — TCA ROI 三通道 union 放宽（D7 注记兑现）

**read_first**：`RESEARCH.md` §Geometry Seam TCA 行；`LensModule.swift
:251-295`（modifyROIIn G 通道 + 2px 现状 + AABB/clamp 纪律）；04-04
DECISIONS D7 注记。

- **action**：resolved-XML 路径（lensfun source）边框映射放宽为真三通
  道 union（R/G/B 各自 forwardPoint 取包络；手动路径维持 G 通道近似——
  手动滑杆 TCA 幅度小，DECISIONS 申报维持理由）；2px 插值边距与 clamp
  序零改。
- **验收标准（机检）**：构建绿；union 路径测试（TCA 大系数 fixture 的
  ROI 覆盖断言——R/B 通道越出 G 包络例）；手动路径行为不变负测。
- **commit**: `fix(lens03): widen resolved tca roi to per-channel union`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 G 通道近似）；
  偏差（手动路径维持近似）= DECISIONS 申报；**禁改 kernel**（本任务零
  metal diff——红线 5 特别面）。

## T3 — 数据分发硬化（D-LENS-6，X7）

> master.zip 不钉版 = 不可复现（缺口表 profile database 行）——随包钉
> 版 + SHA 校验更新通道。

**read_first**：`RESEARCH.md` §Upstream Facts（更新通道/许可双轨/体积）
+ §OQ-6；RawLab `build.sh:63-65` + third_party README（钉版形）；LutLibraryStore
seeder（AGENTS.md M2-5）；`LensfunDownloadService.swift` 全文（优先序
现状）；`LightamerShell.swift:920-927`（启动装臂）；CONTEXT §X7 + L057
红线 13。

- **action**：
  1. 检取钉版快照：官方 `version_1.tar.bz2`（RESEARCH 登记通道）→ 解包
     xml 集 + 计 SHA-256 → `Resources/Lensfun/`（xml 集 + `README.md`：
     来源 URL + SHA-256 + 检取日期 + unmodified 声明）——检取动作本身
     = 执行批网络操作（machine-guard + 代理纪律按 §6；失败 = 停手上报
     供件，禁用 master.zip 替代）。
  2. `Project.swift` App target resources += `folderReference(path:
     "Resources/Lensfun")`（:179-192 先例形——裸目录字符串禁）。
  3. `LensfunDataDistribution.swift`（App）：seeder（首装拷入支持目录
     + 哨兵字节等跳过/漂移重拷）+ `LensfunDataLocation` 优先序接线 =
     customPath > 随包种子 > 已下载 > absent + `dbTag`（SHA 前 16 hex）
     读出面（LENS-04 快照消费预备）。
  4. 设置面手动「检查更新」：下载官方 tar.bz2 → SHA-256 校验（与 README
     登记值不符 = 拒绝安装 + 错误 toast）→ 安装为已下载副本；L057 缝
     （Task hop + PanelPresentation/picker 面）；无自动更新。
  5. `LensfunDownloadService.resolveAndInstall` 优先序接入种子臂
     （master.zip legacy 路径保留为无种子时降级）。
  6. 测试：SHA 校验（正/篡改负例）+ 优先序四态 + seeder 哨兵（等/漂/
     缺三例）+ 更新失败降级（断网形态 = 既有数据不动）。
- **验收标准（机检）**：
  - 构建绿；`Resources/Lensfun/README.md` 含 SHA-256 + 日期 + unmodified
    声明（grep 三件）。
  - 优先序测试四态在册；SHA 篡改拒绝测试在册；seeder 三例在册。
  - grep：`folderReference(path: "Resources/Lensfun")` 恰一处；
    customPathKey 零改（键名 diff 零命中）。
  - `--bundle IOP` 定向零回归。
- **commit**: `feat(lens03): bundle pinned lensfun snapshot with sha-verified update channel`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回下载态）；偏差
  （支持目录布局/更新 UI 落点）= DECISIONS 申报；**禁自动更新/后台拉取**
  （D-LENS-6）；**禁 SHA 不符静默安装**；**禁把 xml 拆分裁剪**（整库随
  包——子集化 = 复现性破坏）。

## T4 — NOTICE 与许可全套（H-L3，X8；docs-only 不可延后）

- **action**：
  1. `NOTICE` 第三方 provenance 节新增三目：lensfun 校准数据（CC-BY-SA
     -3.0——来源 URL + 钉版 SHA-256 + unmodified 快照声明 + 指向
     Resources/Licenses/Lensfun/）；Alcedo Studio（LensProjection +
     lens_calib.metal 移植段，GPL-3.0，保留版权 + 修改标注声明）；RawLab
     （LensAutoCrop 二分移植 + 状态机语义参照，GPL-3.0）。
  2. `Resources/Licenses/Lensfun/`：cc-by-sa-3.0.txt 全文 + 数据库归属
     README（与 Resources/Lensfun/README.md 一致性）。
  3. fixtures 侧复核：`input/golden/fixtures/lensfun/README.md` 现有
     CC-BY-SA 声明与 NOTICE 新条目口径一致（差异 = 修正 fixtures README
     措辞，历史声明不删）。
  4. LENS-02 预登记的移植件清单（LensAutoCrop）+ 本 plan LensProjection
     汇总对账（移植件 ↔ NOTICE 条目一一对应）。
- **验收标准（机检）**：grep NOTICE 含 `lensfun`/`CC-BY-SA`/`Alcedo`/
  `RawLab` 各 ≥1 命中；许可文本文件在库（字节数 > 0）；fixtures README
  与 NOTICE 无口径冲突（面核记录入 DECISIONS）。
- **commit**: `docs(lens03): attribute lensfun data and gpl ported math in notice`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；零偏差面；**禁漏条
  目**（H-L3 硬门——T3 已落而本任务缺 = 流程违规）。

## T5 — 收口（Project.swift + tuist generate + docs）

- **action**：三个新测试文件入数组（IOPParity ×1 / IOP ×2）+
  Resources 两条 folderReference；`tuist generate` 恒末位；定向 bundle
  全绿（IOP/IOPParity/App——App 因 §5 数据管理段）；ΔN 对账（+16..26）
  ；SUMMARY/DECISIONS 落盘；与 LENS-04 一并 **C 档停汇报**。
- **验收标准（机检）**：定向 bundle 全绿；Project.swift diff = 恰测试
  三行 + resources 两行；SUMMARY/DECISIONS 在库。
- **commit**: `test(lens03): register projection and distribution suites and close out l3`
- **回滚与偏差申报要求**：ΔN 越带 = SUMMARY 申报；禁漏 tuist generate；
  xcstrings 新键（T1/T3 面板面）随批尾块插入 + 双 PASS（并入 T5 收口
  核）。

---

## 风险与回退

- **投影求值序与既有段交互**：投影归一在畸变/TCA/渐晕之前还是之后 =
  语义分叉——以 Alcedo lens_calib.metal 实序为准移植并头注释钉死；对
  表 golden 是唯一裁决面（发现歧义 = 停手上报，禁自裁选序）。
- **对表数值可得性**：Alcedo metal 数学同源对表需采样点选择一致——采
  样点/输入域入 DECISIONS；对不上（>1e-5）= 先查采样域差再查实现，禁
  放宽门。
- **快照检取网络依赖**：执行批检取 tar.bz2 失败 = 供件缺口停手上报
  （orchestrator 供件通道）；禁 master.zip 替代（不可复现）。
- **seeder 漂移重拷**：随包数据升级（未来快照更新）触发整目录重拷——
  哨兵按文件字节比对，部分漂移部分拷；测试覆盖混合态。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH 缺口表「projection/profile database」两
   行 ↔ T1/T3+T4；H-L3 ↔ T4。
2. **OQ 兑现核**：D-LENS-8（四型 + 8 槽 + 硬拒解除双臂）/ D-LENS-6
   （SHA 校验拒绝 + 无自动更新 + customPath 零改）。
3. **红线核**：LensProjection/LensAutoCrop 版权头三件套 ↔ NOTICE 三条
   目一一对应；rectilinear 默认恒等 golden；T2 零 metal diff；xcstrings
   尾块 + 双 PASS。
4. **SC 可机检性**：同前例；T4 docs-only 也有 grep 机检（NOTICE 三条
   目），非「目测合规」。
