# M8-1A-SUMMARY — FSIM 数学核-数据面执行摘要（2026-10-25）

> 执行正本 = `M8-1A-PLAN.md`（checker `40bccfd3` + fixer `dd9490fe` 后 HEAD；
> plan 起点 commit = `547a266a`）。C 档停位：本 plan 执行+验收闭环后停汇报，
> M8-1b 未启动。

## 逐任务记账

| 任务 | commit | 产物 | 测试增量 |
|---|---|---|---|
| T1 谱面 additive 解码 | `a44758b0` | FilmProfile.swift 六字段 + 投影 face 家族 + FilmProfileTests 重编码 face 更新（deviation①） | +3 |
| T2 常量资产五件 | `6455bb6d` | SpectralConstantsData.swift（generated 25KB）+ SpectralConstants.swift + 生成脚本与 log（evidence 仓 `75298b9`） | +4 |
| T3 tc 自拟合器 | `0ca04055` | SpectralTcFit.swift（sigmoid-quadratic + 13-seed 多起点 LM + ridge + sanitize） | +5 |
| T4 构建期引擎全链 | `47090c82` | SpectralBuildEngine.swift（tc 展开/remap 预折/中性 CC 自解/33³ PCHIP/常量块/runtime 参照面）+ golden 六测试（evidence 仓 `2b48924`） | +6 |
| T5 收口 | 本 commit | Project.swift 四行入域 + BUNDLE-MAP 四行 + tuist generate + 28-pair 冒烟 | +1 |
| **合计** | | | **+19**（预算带 +18..24 ✓） |

## 定向轮实测（Scripts/test-direct.sh，guard 记录在案）

| bundle | 结果 | 说明 |
|---|---|---|
| Layers | **502/6/0**（179s） | FilmProfile 回归面（含更新后的重编码 face 测试）零回归 |
| IOP | **783/5/0**（726s，最终轮） | 三谱面套件入域；中途两轮失败均已修复（落域纠错 + 远壳 locus 过滤），最终轮零失败 |
| IOPParity | **485/6/0**（1066s） | golden 全门 + 28-pair 冒烟（317.8s，Debug 口径） |

- 全套 `--all` 不在本 plan（归 M8-3 收口轮统一对账）；skip 零新增（6/5/6 =
  既有 LIGHTAMER_PERF_PROBE 族）。
- ΔN 记账：新测试方法 **19**（3+4+5+6+1）∈ [+18, +24]；T5 行按 plan 记 +2、
  实际 +1（evidence 登记面 = 文件非测试，差 1 申报）。全套预期 4225（4206+19）
  ∈ [4224, 4230] ✓。

## 验收判定（逐条 SC）

- T1：构建绿 ✓；FilmProfile.swift 恰一产线文件 ✓；缺键零漂移专测在册 ✓；
  28 张全量冒烟（null-aware 计数带 15-78/243、5-26/81）✓；既有 FilmProfile
  侧测试零回归（Layers 502/0）✓。
- T2：恰两新产线文件 ✓；provenance 头在库 ✓；dt pack 零字节（生成脚本 =
  colour-science 公开表，dt 仅值域参照）✓；白点积分散 ≤1e-6（实测 0，与
  colour-science 官方表 bit 级一致）✓。
- T3：恰一新产线文件 ✓；双跑逐位恒等 ✓；质量门三件（覆盖率 0 NaN/发散、
  平滑度实测带、白点 ≤1e-6）✓。
- T4：恰一新产线文件 ✓；golden 五门（expose 独立复算 ≤1e-6 实测 ~4e-9；
  PCHIP 分级带 print 2.19e-3/scan <5e-5；中灰闭合实测 0；白点 ≤1e-6；端到端
  逐位）✓；evidence 目录（numpy PASS + dt 转录件）✓；表体积 442,368 B 恰 +
  束 5,620,928 B（RESEARCH §4.1 ~5.5MB 量级 ✓）。
- T5：Project.swift 恰四行插入（其中三行经历一次落域纠错——deviation⑤）；
  BUNDLE-MAP 四行在库；tuist generate 恒末位（两次触发，均在该批文件落盘
  之后）；无生成物入 git（.xcodeproj ignored）；SUMMARY/DECISIONS 在库；
  冒烟在册 ✓。

## 红线机检（plan 红线 17 条对照）

- FIX2③：`App/Sources/Lightamer/Library/LibraryProjectController.swift` 零
  diff ✓（git diff 547a266a..HEAD 零命中）；McpServerController.swift 零 diff ✓。
- 封存面：DrtRecord/TerminalTailPolicy/DrtTailAssembly/DrtPanelModel/
  DrtPanelView/DrtEotf/Lut3dKernels.metal/ExportQueueContract/六格式导出矩阵/
  NodeGraphCommand/LightamerSidecar（v11 零 bump）/HistoryStack/HistoryHash/
  PipelineDocument/V50Order/GradeCatalog/Registry/ModuleInstance 全零 diff ✓；
  FilmSubRunKernels.metal 零 diff ✓；零新 .metal ✓；PixelPipe/RenderProcess/
  FilmTailPolicy/FilmPrintBake 零 diff（film 自有面本 plan 未触——纯数据面）✓。
- 零 FilmRecord 字段 / 零 sidecar 键 / 零 UserDefaults 新键 ✓。
- xcstrings 零触碰（无 UI 面）✓；LocalizationValue 禁形零命中 ✓。
- Resources/FilmProfiles 字节原样（MANIFEST.sha256 对账测试在库通过）✓。
- machine-guard：全部 xcodebuild/tuist/test-direct 前置 `--wait 1800`，无
  并发重活 ✓；只杀自出 PID（零 kill）✓。
- GPL 纪律：dt 读解 = 定位引用（evidence 转录件含出处行号）；上游表/常量
  零字节进仓（CAT16/CAT02/OkLab = 公开发表值 + colour-science 核验）✓；
  GPL fallback 未触发（自拟合达标）✓。
- C 档门控：本汇报后停 ✓。

## 关键实测值（DECISIONS 正本见 M8-1A-DECISIONS.md）

- 谱面：28/28 张 null 实测（channel 15-78/243、midscale 5-26/81）、
  log_sensitivity 全集带 [-13.59, 1.63]（gate ±20）。
- tc 拟合（192²，-O 单次 ~17.5s / Debug ~90s）：工作壳（白距 ≤0.2）
  ≤2.1e-4 绝对色度（plan 带 1e-3 ✓）；远壳（in-locus）实测 5.6e-1 → 声明
  ≤0.6；白点 ≤1e-6；双跑逐位；构建成本由引擎 memoization 消解。
- 中性配平：构建期 2D Newton 自解 CC，链头通道散 **0**（gate ≤2e-3）；
  solvedPrintCC 随表（M8-2 solve seed）。
- PCHIP：exact 臂对拍 print 2.19e-3 / scan <5e-5（200 样本 Debug 口径）。
- 载体：tc_lut 442,368 B 恰；束 5,620,928 B（packed face 口径）。

## 遗留与移交（M8-1b/M8-2 消费面）

- `SpectralFilmRuntime`（Float64 参照面：Mitchell gather/expose/曲线查表/
  PCHIP eval）= M8-1b kernel 的黄金对照 + 三板斧 host 侧形态已预埋
  （invLeStep host-double→float）。
- `sharedCoefficientTable` memo = X7 缓存 face 的构建期侧；运行期 per-pair
  LRU 归 M8-2 T3。
- 平表 gather 常量性专项断言挂账 M8-1b（dt 单测同款；本 plan 无 gather
  实机面）。
- M8-2 solve face 消费 `solvedPrintCC` 为种子；密度域 neutral_print_filters
  表保持 M3 路径不动。
