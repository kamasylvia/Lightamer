---
phase: 12
plan: "12-5"
title: "LUT + Phase 收口签核：.cube 解析器（1D/3D/DOMAIN remap——超 dt 能力面正向扩展 + 八类 typed throw + 真实脏样本采集预案）+ tetrahedral texture3d rgba16Float kernel（lut3d.cl:29-60 verbatim + L031 路由红线）+ 1D kernel（texture2d 宽条回退案）+ 应用色彩空间选择器 + LUT 导入库 + Inspector 面板 + 12-VALIDATION/移交清单/翻账/TODO/GOAL-STATE 收口（C 档第 3 停）"
wave: 4
depends_on: ["12-1", "12-2", "12-3", "12-4"]
autonomous: true
requirements: [IOP-COLOR-08, PRES-03]
files_modified:
  - LightamerIOP/Sources/Lut3d/CubeLutParser.swift                 # 新建：.cube 纯 Swift 解析器（typed throw 八类）
  - LightamerIOP/Sources/Lut3d/Lut3dModule.swift                   # 新建：lut3d iop（V50 36.0；params = lutName/colorspace/interpolation）
  - LightamerIOP/Sources/Lut3d/Lut3dKernels.metal                  # 新建：tetrahedral + trilinear + 1D kernel（texture3d/texture1d）
  - LightamerIOP/Sources/Lut3d/LutLibraryStore.swift               # 新建：LUTs/ 导入库（FNV-1a 内容查重 + 启动重扫 + 缺失降级）
  - LightamerIOP/Sources/Registry.swift                            # LightamerIOPRegistry.populate 注册 lut3d
  - App/Sources/Lightamer/UI/Inspector/LutPanelView.swift          # 新建：LUT 面板（导入/库列表/色彩空间 picker/插值 picker）
  - App/Sources/Lightamer/UI/Inspector/IOPPanelProvider.swift      # 面板体系一席注册
  - Tests/LightamerTests/CubeLutParserTests.swift                  # 新建：解析 golden + 八类 throw + 角点锁序
  - Tests/LightamerTests/Lut3dKernelTests.swift                    # 新建：tetrahedral vs CPU float64 + DOMAIN remap + 色彩空间回环
  - Tests/LightamerTests/Lut3dGoldenImageTests.swift               # 新建：dt 参考输出 golden-image 对照（CONVENTIONS 纪律）
  - Tests/LightamerTests/LutLibraryStoreTests.swift                # 新建：导入查重/缺失降级/重扫
  - .planning/phases/12-metadata-presets-lut/12-5-SUMMARY.md
  - .planning/phases/12-metadata-presets-lut/12-5-DECISIONS.md
  - .planning/phases/12-metadata-presets-lut/12-VALIDATION.md      # Phase 12 签核（SC#1-4 三列证据）
  - .planning/phases/12-metadata-presets-lut/12-DISCUSSION-LOG.md  # 追加终节（Phase 13 移交清单 + 遗留对表）
  - .planning/REQUIREMENTS.md                                      # META-01..06/PRES-01..04/IOP-COLOR-08 翻账
  - TODO.md                                                        # 12-5 勾选 + Phase 12 收口
  - .work/GOAL-STATE.md                                            # Phase 12 闭环翻账 + 续接点更新
  - LESSONS.md                                                     # 如踩坑
---

# Plan 12-5 — LUT iop + Phase 收口签核（W4，GPU 腿独立 + 全 Phase 收口）

> 背景：IOP-COLOR-08 = PRES-03 同一次交付（ROADMAP Notes locked）。三条腿（RESEARCH §6
> 正本）：① 解析器支持 DOMAIN remap = **超出 dt 能力面**（F4：dt `lut3d.c:782-791` 只支持
> DOMAIN 0..1，DOMAIN_MIN≠0/DOMAIN_MAX≠1 直接拒绝）——正向扩展非移植缺口，remap 公式与
> 精度论证 research §6.3/§6.4 已补齐；② kernel = tetrahedral verbatim 移植 +
> `texture3d rgba16Float` + DOMAIN remap uniform（避免 host 预缩放破坏 float32 域精度）；
> ③ 库引用保预设
> 可移植（iop params 存库内名，原始路径即弃）。**落位修正（入 DECISIONS）**：RESEARCH §6.5
> 字面路径 `LightamerCore/Sources/Pipe/IOP/Lut3d/` 按既有 iop 文件对惯例正本落
> `LightamerIOP/Sources/Lut3d/`（research 同节自述「骨架 = 既有 iop 文件对惯例」；YiyinFontStore
> 先例亦在 LightamerIOP；Tests target 已依赖 LightamerIOP 可单测）。**L031 红线**：新 iop 的
> identity/blit 一律走 `makeRoutedCommandBuffer()` 路由点（`LightamerCore/Sources/Pipe/PixelPipe.swift:466`）。
> 本 plan 兼 Phase 收口：VALIDATION + 移交清单 + 翻账 + C 档第 3 停。

## read_first

1. `.planning/phases/12-metadata-presets-lut/12-RESEARCH.md` §6（解析器/kernel/remap/精度/V50/色彩空间/导入库全套规格）、§7 T8、§8.2（12-5 验收草案）、§8.4（脏样本留缝）
2. `.planning/phases/12-metadata-presets-lut/12-CONTEXT.md` D-12-CONTEXT-6（LUT 裁决全套）、验证红线节（LUT golden）
3. dt 移植正本（本地 `/Volumes/UNITEK/Documents/Development/darktable`）：`data/kernels/lut3d.cl:29-60`（tetrahedral verbatim 正本）、`src/iop/lut3d.c`（解析器 `:701-751` tokenizer 容错 / `:782-791` DOMAIN 0..1 边界 / `:1020` 插值枚举 / `:1029-1031` lut_profile↔work_profile）
4. `LightamerCore/Sources/Foundation/V50Order.swift:126`（`("lut3d", 36.0)` 已预留；`terminalTailFloor` 70.0 层内合法性）
5. iop 文件对惯例正本：`LightamerIOP/Sources/Sharpen/SharpenModule.swift`（头注结构/INTENTIONAL DIVERGENCES 写法/neutral=blit-identity 快路径）+ `LightamerIOP/Sources/Registry.swift`（`LightamerIOPRegistry.populate` 注册位）
6. **L031 红线正本**：`LESSONS.md` L031 + `LightamerCore/Sources/Pipe/PixelPipe.swift:466`（`makeRoutedCommandBuffer()` 唯一路由获取点——identity blit 硬编队列 = 跨队列竞速假非确定）
7. 色彩空间系数资产：`LightamerCore/Sources/Pipe/Terminal/ColorInModule.swift` + `ColorOutModule.swift`（矩阵同源单实现，不新增 ICC 面）
8. `LightamerCore/Sources/Export/ExportRecipe.swift:105`（12-4 已挂 exportRecipe——LUT 预设引用例外对表）
9. `LightamerIOP/Sources/Yiyin/YiyinFontStore.swift`（导入库三拆模式范本）
10. 收口正本：`.planning/phases/11-export-pipeline/11-VALIDATION.md`（VALIDATION 体例）+ `11-DISCUSSION-LOG.md` 终节（移交清单/遗留对表格式）+ `.work/GOAL-STATE.md`（翻账格式）+ `11-05-PLAN.md` T5（收口批先例）
11. `LESSONS.md` L009/L013/L014（GPU 读回 fence）/L019b/L020/L025/L031
12. `AGENTS.md`（Phase 执行模型 + 暂停机制 + C 档门控）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建；单测 = `Scripts/test-direct.sh '<Class>'`（**判据 = Executed 行 + failures 行，非宿主退出态**；Executed 0 = 失败防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**；零新 SPM 依赖（解析器/kernel 全自建——继承定案）；无 /tmp 产物入工作区（**脏样本 fixture 落 Tests fixtures 入仓**，网络采集临时文件不入仓）；fixture 禁 UNITEK 盘（L009）。
- **L031 红线（本 plan 新增 iop 强制）**：lut3d 的 identity/blit 与一切 GPU 提交走 `makeRoutedCommandBuffer()` 路由点；禁硬编队列。
- **管线契约不动**：LUT iop 是常规 v50 实例——`LayerCompositeDriver.terminalTailFloor=70.0`、`injectYiyinRunContext`、split 语义零改动。
- **T5 为 GUI 任务：需解锁控制台（Manual-Only 候补）**。
- **脏样本风险预案（写死）**：真实 `.cube` 变体网络采集 1 次预算（`px --up` 代理流程 → 采集 → **`px --stop`**）；失败/超时 = 合成脏样本替代（畸形行/负值/科学计数法/CRLF 混合自造 fixture），**不阻塞**。
- **C 档第 3 停（本 plan T6）**：VALIDATION 产出后按夜间授权先例（D-07-3-T5-1 / D-09-05-T1-1 + 11-05 D1）先翻账、晨审追认。
- RESEARCH 未覆盖细节（TITLE 超长截断/1D 输出域声明缺省面/面板布局细节）标注**执行期决策**入 `12-5-DECISIONS.md`。

## Tasks

### T1 CubeLutParser（.cube 纯 Swift 解析器）

- **action**
  1. `CubeLutParser.swift`（新建，LightamerIOP/Lut3d）：识别键全集（RESEARCH §6.1 verbatim）——`TITLE`（**含空格整行取值**存显示名，dt 只跳过不取值=我方差异）、`LUT_3D_SIZE` / `LUT_1D_SIZE`（互斥）、`DOMAIN_MIN`/`DOMAIN_MAX`（1 float 广播三通道**或** 3 floats 两形态）、`LUT_1D_INPUT_RANGE`（2 floats）、`#` 注释（CRLF `\r` 残留剥离——dt tokenizer 容错同款）、空行容忍、数据行 2-3 floats（1D）/ 3 floats（3D）。
  2. typed throw 八类：`missingSize / conflictingSizes / sizeOutOfRange(>129 防御) / dataCountMismatch(expected:actual:) / nonNumericToken(line:) / domainInvalid(min>=max) / emptyFile / titleAfterData(容忍但记 warning)`。
  3. 3D 数据序 = **red fastest**（文件顺序 r 内层）——golden 用已知 2³ cube 断言角点位置锁序（对齐 kernel 索引 `r + g*L + b*L²`，`lut3d.cl:45`）。
  4. **脏样本预案**：真实 `.cube` 变体网络采集（1 次预算，px 代理流程，入仓 fixtures）；失败 = 合成脏样本替代（不阻塞）。
- **证据**：`CubeLutParserTests`——1D/3D/DOMAIN 单值与三值/LUT_1D_INPUT_RANGE/CRLF/注释/TITLE 取值 golden + 八类 throw 逐类向量 + 2³ 角点锁序 + 脏样本 fixtures 全过。

### T2 Lut3dModule + tetrahedral kernel（L031 红线）

- **action**
  1. `Lut3dModule.swift`（新建）：`opName "lut3d"` + `iopOrder 36.0`（V50Order :126 已有 entry——注册经 `LightamerIOPRegistry.populate` 一行）；params Codable = `lutName: String?`（库内名；nil = 未载入恒等直通）+ `colorspace: LutColorspace`（默认 sRGB）+ `interpolation: .tetrahedral|.trilinear`（**默认 .tetrahedral**——SC#4「tetrahedral as default」字面）；neutral（lutName nil）= blit-identity 快路径（SharpenModule 先例）。
  2. `Lut3dKernels.metal`：`lut3d.cl:29-60` verbatim 移植——level-1 缩放 → `convert_int` clamp → rgbd 分数部 → 八角点索引 → 三分数比较六分支四面体重心权值（P000-P111）；`texture3d<float, access::read>` rgba16Float（**不用 sampler/不用 hardware filter**——`read(ushort3(p))` 手动八角点，规避 float32 纹理不可 filter 限制，与 CL buffer 语义等价）；**DOMAIN remap uniform 在索引数学之前**：`v' = (clamp(v,domMin,domMax)-domMin)/(domMax-domMin)*(L-1)`（默认 (0,1)）；trilinear 第二态（8 角点等权，~15 行）。
  3. **L031**：identity/blit 与一切 GPU 提交走 `makeRoutedCommandBuffer()`（PixelPipe.swift:466 唯一路由点）。
  4. golden：tetrahedral 已知点 vs CPU float64 参考实现（同 kernel 数学逐行双写；**阈值 ≤1/1024 绝对差**——超差升 rgba32Float = 执行期决策入 DECISIONS，`access::read` 手动插值下升格零重写）；DOMAIN remap 已知点（DOMAIN_MAX>1 HDR 域 + DOMAIN_MIN<0 域）；trilinear vs tetrahedral 对照点。
- **证据**：`Lut3dKernelTests` 全绿 + identity/blit 路由断言（无硬编队列——grep + 构建走查）+ rgba16Float 精度阈值内结论入 DECISIONS。

### T3 1D LUT kernel（texture1d + 回退案）

- **action**
  1. per-channel 分段线性独立轻 kernel：`floor`/`frac` 两点插值；`texture1d<float>` R16Float；`LUT_1D_INPUT_RANGE` remap 同 §6.3 公式；无域声明键默认 sRGB gamma 面（.cube 1D 惯例）——文档化 + UI 提示位（T5 面板）。
  2. **回退案两案写死**（CONTEXT specifics 执行期决策位）：若 `texture1d` filter/read 组合不称手 → `texture2d` 宽条（1×N）同数学替换——两案的验收锚相同（已知点插值值断言 + 与 CPU 参考全等），裁决入 DECISIONS。
- **证据**：`Lut3dKernelTests`（1D 段）——分段线性已知点/INPUT_RANGE remap/端点 clamp/与 CPU 参考全等；回退裁决（若走）入 DECISIONS。

### T4 应用色彩空间选择器 + dt golden-image

- **action**
  1. 色彩空间枚举四态：`sRGB / displayP3 / rec2020 / proPhotoLinear`（默认 **sRGB**；dt 六态收窄——INTEROP-2/3 防呆正主）；应用序 = working（linear Rec2020）→ 矩阵转换到 LUT 域 → tetrahedral 采样 → LUT 域 → 矩阵回 working；矩阵走 colorin/colorout 既有系数资产（同源单实现，不新增 ICC 面）。
  2. **色度恒等回环已知点**：选择器矩阵往返（working→域→working 不经采样）恒等/近恒等断言；LUT 恒等表（identity cube）经全链 = 输入恒等。
  3. **dt golden-image 对照**（CONVENTIONS 纪律：iop 移植必须有 golden-image）：dt 参考输出 fixture（同 .cube 输入 + 同色彩空间设定）→ 像素级容差对照（容差口径执行期决策，参照既有 ParityGate 实践）。
- **证据**：`Lut3dGoldenImageTests`——回环已知点 + identity cube 全链恒等 + dt golden-image 对照全绿。

### T5 LUT 导入库 + Inspector 面板（GUI，需解锁控制台（Manual-Only 候补））

- **action**
  1. `LutLibraryStore.swift`（新建）：`~/Library/Application Support/Lightamer/LUTs/`；导入 = 拷贝 + **FNV-1a 64 内容查重**（同哈希改名不重拷）；iop params 存库内**文件名**（相对，原始路径即弃——引用不腐烂）；启动重扫自愈（YiyinFontStore 三拆）；**库缺失降级**：preset/实例引用不存在的 lutName → iop 恒等直通 + toast（unknown-op 同款姿态）。
  2. `LutPanelView.swift`（新建，Inspector 一席）：导入按钮（NSOpenPanel → 库）/ 库列表选择（→ lutName）/ 色彩空间 picker（四态）/ 插值 picker（tetrahedral 默认/trilinear）/ 1D 无域声明提示；面板四件套 + 280pt + zh catalog（L025）。
  3. 与 12-4 联动验证：含 LUT 实例的 develop 预设 save→apply round-trip（本机库在位）；库移除后 apply → 降级恒等 + toast。
- **证据**：`LutLibraryStoreTests`——导入/查重/重扫/缺失降级向量；GUI 走查（导入→应用→面板参数联动→预设 round-trip→删库降级 toast）；Manual-Only 未尽项登记。

### T6 Phase 收口批：回归终轮 + VALIDATION + 移交清单 + 翻账（C 档第 3 停）

- **action**
  1. 全 suite 终轮：基线 **1260/6skip/0fail** + Phase 12 全部新增，0 fail；测试计数演变入 SUMMARY。
  2. `12-VALIDATION.md`：SC#1-4 逐条三列证据（一手代码锚/测试锚/GUI 实证锚，体例照 11-VALIDATION）；**SC#2 三列证据须显式声明排序键口径 = D-12-CONTEXT-7 六键（filename/rating/capture_date/iso/focal_length/scan_epoch）——SC 字面「sort by label/keyword/camera/lens」以过滤面 16 字段全覆盖解释，排序窄面为 D-7 裁决内行为**（checker W-2 可追溯性）；Manual-Only 汇总表（四 plan 登记合并）；`status` + `nyquist_compliant` frontmatter。
  3. `12-DISCUSSION-LOG.md` 追加终节：**Phase 13 移交清单**（DB v2 34 列 = Spotlight 索引源；XMP 例外集复审位[HEIF/AVIF/WebP，Phase 14 同批]；Quick Filter/谓词翻译层 = Phase 14 MCP 筛选工具直接消费面；`.lightamer-preset` = MCP-09 preset 三件套上游；Manual-Only 承接）+ **遗留对表**（各 plan SUMMARY 遗留合并，零静默）。
  4. 翻账：`REQUIREMENTS.md` META-01..06 / PRES-01..04 / IOP-COLOR-08 → Delivered（+ 映射表 Pending→Delivered）；`TODO.md` Phase 12 收口；`.work/GOAL-STATE.md` Phase 12 闭环记录 + 续接点更新（Phase 12 verify-work 待办 + 下一 phase 指针）。
  5. **C 档第 3 停**：VALIDATION 产出后按夜间授权先例（D-07-3-T5-1 / D-09-05-T1-1 + 11-05 D1）执行翻账收口，晨审追认——用户晨间可推翻（推翻 = 回注修复批）。
- **证据**：VALIDATION frontmatter + 终节落盘 + 三处翻账 diff 干净（只翻本 Phase 行）+ 终轮计数 0 fail。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 解析器 | golden + 八类 throw + 角点锁序 + 脏样本 | `Scripts/test-direct.sh 'CubeLutParserTests'` |
| 3D kernel | tetrahedral vs CPU float64 + DOMAIN remap + L031 路由 | `Scripts/test-direct.sh 'Lut3dKernelTests'` |
| golden-image | 色彩空间回环 + identity 恒等 + dt 对照 | `Scripts/test-direct.sh 'Lut3dGoldenImageTests'` |
| 导入库 | 查重/重扫/缺失降级 + 预设联动 | `Scripts/test-direct.sh 'LutLibraryStoreTests'` |
| GUI | 面板四件套 + 导入/应用/降级 toast 走查 + zh | 手动走查记录 + Manual-Only 登记 |
| 回归 | 全 suite 0 fail（基线 1260+全 Phase 新增） | `Scripts/test-direct.sh`（全套） |
| 收口 | VALIDATION/移交清单/翻账/GOAL-STATE 落盘 | 文件核验 + 翻账 diff |

## 验收标准（Acceptance）

- [ ] 解析器：识别键全集（TITLE 取值差异/DOMAIN 双形态/LUT_1D_INPUT_RANGE/CRLF 容错）+ 八类 typed throw + red-fastest 角点锁序 golden + 脏样本 fixtures（真实采集或合成替代，预案落账）
- [ ] kernel：tetrahedral verbatim + texture3d rgba16Float 手动八角点（无 sampler）+ DOMAIN remap uniform（超 dt 能力面文档化）+ trilinear 第二态 + 1D kernel（回退案裁决入 DECISIONS）+ **identity/blit 走 `makeRoutedCommandBuffer()`**（L031）+ neutral = 恒等零管线行为
- [ ] 精度：tetrahedral vs CPU float64 ≤1/1024（超差升 32F 决策在账）；rgba16Float 默认结论入 DECISIONS
- [ ] 色彩空间选择器：四态默认 sRGB + 矩阵同源（colorin/colorout 资产）+ 回环恒等 + identity cube 全链恒等 + dt golden-image 对照全绿
- [ ] 导入库：LUTs/ 目录 + FNV-1a 查重 + 库内名引用（引用不腐烂）+ 缺失降级恒等 + toast + 预设联动 round-trip；GUI 面板四件套 + zh catalog（L025）
- [ ] 收口：终轮 0 fail（1260+新增）+ 12-VALIDATION（SC#1-4 三列证据 + Manual-Only 汇总）+ DISCUSSION-LOG 终节（Phase 13 移交清单 + 遗留对表零静默）+ REQUIREMENTS/TODO/GOAL-STATE 三处翻账 + C 档第 3 停按夜间授权先例执行
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查 config 开关；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘
