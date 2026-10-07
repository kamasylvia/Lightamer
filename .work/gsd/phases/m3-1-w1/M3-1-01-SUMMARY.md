# M3-1-01-SUMMARY — M2GRADE-08 LUT 作者编码建模（W1 plan 1）

> 执行：2026-10-08 夜间（executor subagent，夜间全自动授权在案）。
> 基线：`a81483d` + `08dd061`（修复批已落 HEAD 前驱）+ plan 批 docs `9072f93`。
> 产出 commits：T1 `e274cc0` → T2 `4f48d04` → T3 `a1e7d56` → T4 `9ab0193` → T5 `5c6291c` → T6 本批（docs）。
> **未 push**（纪律）。

## 一、交付面（对表 plan front-matter files_modified）

| 文件 | 变更 | commit |
|---|---|---|
| `LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift` | 新建：17 行编码目录 + 9 gamuts（Bradford 自算矩阵）+ typed 查找 | `e274cc0` |
| `LightamerIOP/Sources/Lut3d/LutTransferMath.swift` | 新建：10 camera log + sRGB 新写正逆（Float64）+ PQ/HLG/BT.1886/γ2.2 经 `DrtEotfMath` 复用 + display 100-nit 中介适配 | `e274cc0` |
| `LightamerIOP/Sources/Lut3d/Lut3dModule.swift` | Params additive 编码对 + 容错 Codable + commitParams 烘焙 + concurrentPerform 切片 + LRU 16 + bakeCount + **新增 stateLock** | `4f48d04` |
| `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift` | `RememberedEncodings` + `InstalledLut.rememberedEncodings` additive + adoption 路径补标盖章 + `updateRememberedEncodings` 写回面 | `a1e7d56` |
| `App/Sources/Lightamer/UI/Inspector/LutPanelView.swift` | 双 Picker（scene/display 分组）+ 记住 Toggle + 三层序接线 + 逻辑 helper 提取（**纯增量 118 行零删除**——四既有面含 a81483d Task hop 字节零触碰） | `9ab0193` |
| `Resources/Localizable.xcstrings` | 5 新键纯尾块 append（历史键字节与顺序零触碰） | `9ab0193` |
| `Tests/LightamerTests/Lut3dEncodingTests.swift` | 新建：Lut3dEncodingTests 14 + Lut3dBakeTests 10 | `e274cc0`/`4f48d04` |
| `Tests/LightamerTests/LutLibraryStoreTests.swift` | 原地扩 +6（LIB） | `a1e7d56` |
| `Tests/LightamerTests/LutEncodingPanelTests.swift` | 新建（APP）5 | `9ab0193` |
| `Tests/LightamerTests/Lut3dGoldenImageTests.swift` | 扩 +2（Lut3dFullChainEncodingTests） | `5c6291c` |
| `Project.swift` | 显式清单登记（IOPParity + App 两行） | 随各任务 |
| `M2-4-0-BUNDLE-MAP.txt` | 增行 + 计数勘误（同 commit 闭环，E2） | 随各任务 |
| `.work/gsd/REQUIREMENTS.md` | M2GRADE-08 引入 `- [x] Delivered` 形态 + 交付注记 | 本批 |
| `.work/GOAL-STATE.md` | 续接点追加 | 本批 |

## 二、关键实现语义（细节正本 = DECISIONS）

- **编码目录 17 条**（KD-1）：scene 11（acescc/acescct/logc4/logc3/slog3/clog3/flog/vlog/nlog/apple_log + linear_rec2020）+ display 6（rec709_bt1886/rec709_srgb/rec709_gamma22/displayp3_srgb/rec2100_pq1000/rec2100_hlg1000）。F-Log/N-Log/Apple Log gamut 复用 `rec2020`（checker M2，厂规格原文）。SDR 行 peak=100、PQ/HLG=1000（checker M3，零特判分支）。
- **传递曲线**：公式源 = 各公开标准（S-2014-004/ST 2065-1、ARRI A0042/A0011、Sony/Canon/Fujifilm/Panasonic/Nikon/Apple 规格、IEC 61966-2-1）；golden 向量取公开参考实现 doctest 全精度值（GPL 零复制）；gamut 矩阵 = primaries_xy 经标准 Bradford **计算**（rec709 对与 ITU-R BT.2087 公表矩阵逐值吻合 ≤2e-4——独立数值锚）。**GPL 零命中**（Alcedo 源码/测试零字节零数值）。
- **烘焙**（KD-3 + checker E1 正本方向）：`Compose` :273 同构——输入臂 working→AWG4 矩阵→LogC4 **encode**、输出臂 BT.1886 **decode**→Rec709→Rec2020 矩阵；Float64 通道数学；复合 voxel 单位域枚举、尺寸=源表（checker M5 ①②偏离）；烘焙臂 uniforms 恒单位域（M5 ③）。零新 kernel（`Lut3dKernels.metal` 零 diff 机检通过）。
- **hash 零漂移**：`ParamsCoding.encode(Params())` 逐字节 == 旧两键 JSON 专测钉死（AC#3）；`encodeIfPresent` 惯例 nil 键缺席。
- **补标**（KD-5 + checker E3）：adoption 路径（rescan→adopt）对 `BuiltIn/` 前缀行盖 `{arri_logc4_awg4, rec709_bt1886}` 章；drift 再采纳重盖；40/40 逐条断言。
- **stateLock**（checker M4，08dd061 同款）：守护 commitParams 变更窗 + process 引用提取 + 共享 uniform buffer 盖章窗；锁内零 await。GPU 读序残留 = M4 coordinator 专项（同 ToneEqual 既有 defer）。

## 三、方向探测 golden 证据（checker E1 专设，防同误解自参照）

恒等表（table 值 = 编码值本身，吃掉采样臂）+ 三探针，期望闭式 = KD-2 曲线函数在测试内独立直算：

| 探针 | 对 | 期望闭式 | 结果 |
|---|---|---|---|
| input encode 臂 | logc4 → linear | `LogC4_encode(FromRec2020(AWG4)·v)` | 绿 ≤1e-5 |
| output decode 臂 | linear → bt1886 | `ToRec2020(Rec709)·pow(v, 2.4)` | 绿 ≤1e-5 |
| 全对 | logc4 → bt1886 | `ToRec2020(Rec709)·pow(LogC4_encode(FromRec2020(AWG4)·v), 2.4)` | 绿 ≤1e-5 |

臂序倒置（按 CONTEXT D-3 旧字面「inputDecode → 采样 → outputEncode」实现）即红——三探针与 voxel 级烘焙对照（Lut3dBakeTests ≤1e-5）并存缺一不可。

## 四、测试数字 vs 基线

| bundle | 本 plan 后 | 基线（对账） |
|---|---|---|
| IOP | **471/1/0** | 471/1/0（`08dd061` 逐位基线，零漂移） |
| IOPParity | **389/3/0**（363 基线 + 24 Lut3dEncodingTests/Lut3dBakeTests + 2 FullChain） | 363/3/0 |
| Library | **587/4/0**（LutLibraryStoreTests 10→16） | 581/4/0 |
| App | **635/0/0**（630 基线 + 5 LutEncodingPanelTests） | 630/0/0 |

新增 **37** 测试（Lut3dEncodingTests.swift 两类共 24 + Lut3dGoldenImageTests +2 + LutLibraryStoreTests +6 + LutEncodingPanelTests 5）；BUNDLE-MAP 各行 = 24/7/16/5 已三方对表（`grep -c "func test"` = 行值 = Project.swift 清单）。

**MEMFAIL**：全程零（IOPParity 全量峰值 244MB-5788MB 带 < 8192 门）。

## 五、交付注记（用户可见观感变化 = 修正非回归，OQ-4① obligate）

> **新选档观感变化声明**：内置 40 张 spectral film LUT 的作者编码对有案（input ARRI Wide Gamut 4 / output Rec.709 + Gamma 2.4，`phases/m2-5-color-grade/evidence/spectral-film-lut-license.md:150-152`）。补标后**新选**这些 LUT 即走 LogC4/AWG4 进 → 表 → BT.1886 出的正确管线——渲染结果与 M3-1-01 之前**不同，该差异 = 所修系统性偏差的消除**（此前 = log 域表按线性 working space 直套），**非回归**。既有已选文档按三层读取序停在默认对（旧渲染逐字节不变，非破坏性红线；专测在案）。用户重选 LUT 或手动改编码即迁移。

## 六、定向轮与全套边界

- 定向四 bundle（本 plan 纪律 5）：`--bundle IOP` ✓ / `--bundle IOPParity` ✓ / `--bundle Library` ✓ / `--bundle App` ✓（全量数见 §四运行记录）。
- 全套 `--all` 留 03 收口 plan 终验（报备制，plan 原文）。
- 红线机检：`git diff --name-only` 对 Lut3dKernels.metal / DrtEotf.swift / DrtOutputColorSpace / PixelPipe / PipeCacheKey / V50Order / ModuleRegistry / 六格式编码器 / WebPEncoder / NLMeansModule **零命中**（T2 提交前机检留痕）。

## 七、执行期发现（细节归档 DECISIONS）

1. **acescc 中段切点**：初版误用 2^-16，S-2014-004 正本 = 2^-15（half-stop piece 覆盖 (0, 2^-15)）——round-trip 测试抓出（1.5e-5 离群），已修正。
2. **快路径条件收窄偏离**（Alcedo `HasUnitDomain` 条款）：非单位域 + 默认对**不烘焙**（逐字节保现状优先）——IOPParity 全量首轮抓出 HDR 域存储测试 5 红（`HDRPipelineMatrixTests` 两用例钉死非单位域表格 verbatim 上传 + 原生 domain uniforms），改为「快路径 = 默认对单独成立」，全量复绿。DECISIONS §2。
3. **F-Log/N-Log 膝点不连续**：公开标准舍入常数的固有属性（N-Log 451.8 → 整数 452）——round-trip 域排除膝带 + 跳跃幅度钉界，DECISIONS §3。
4. **全链 golden 容差结构**：「GPU vs 源表 Float64 链 ±1e-5」数学不可达（65³ 复合晶格对胶片曲线在线性域的插值地板实测 ~8e-3）——分解为 voxel 级烘焙门（≤1e-5）+ 忠实渲染门（同表插值 ±1.5/1024），DECISIONS §4。
5. 测试计数口径：正本 = **+37**（§四），BUNDLE-MAP 行值已同批勘误对表。

## 八、续接

- GOAL-STATE 续接点已追加（本批）。下一 plan = M3-1 W1 余量（YIYIN-09 sheet 拖拽 / 小件族合并 plan / V14+V15 zh 清算，编排随 orchestrator）。
- `--bundle IOP LutLibraryStoreTests` = 0 命中假绿教训（checker E2）已在 BUNDLE-MAP 增行记录中留痕。
