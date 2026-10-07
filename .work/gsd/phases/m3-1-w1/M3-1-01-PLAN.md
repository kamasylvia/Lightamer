---
phase: m3-1
plan: "M3-1-01"
title: "M2GRADE-08 LUT 作者编码建模（wave 1）——编码目录 17 条表驱动（scene log 10 + display 7，OQ-2①）+ 传递曲线 Float64 正逆函数族 + Params additive 编码对（nil = working 直通逐字节保现状，OQ-1①）+ 宿主侧复合表重烘焙（零新 kernel，OQ-3①）+ 库内逐 LUT 记忆三层序 + 内置 40 张 seeder 补标 AWG4/Rec709g24（OQ-4①）+ 面板双 Picker（基于 a81483d 后状态）+ log 域 golden 全链对照"
wave: 1
depends_on: []
autonomous: true
requirements: [M2GRADE-08]
estimated_tests: "+10..14"
test_bundles: [IOP, IOPParity, App]   # 归属按 BUNDLE-MAP 域模式判定（见 T1/T2/T4 注），front-matter 仅声明涉及面
files_modified:
  - LightamerIOP/Sources/Lut3d/LutEncodingCatalog.swift   # 新建：编码目录 17 条 + gamut primaries 表 + 查找/typed 校验
  - LightamerIOP/Sources/Lut3d/LutTransferMath.swift      # 新建：传递曲线 Float64 正逆族（ACEScc/cct、LogC4/LogC3、S-Log3、C-Log3、F-Log、V-Log、N-Log、Apple Log、sRGB；PQ/HLG/BT.1886 复用 DrtEotfMath）
  - LightamerIOP/Sources/Lut3d/Lut3dModule.swift          # 修改：Params additive 编码对 + commitParams 烘焙插入 + 模块内 LRU 16 + 烘焙计数器（L069 stateLock 纪律）
  - LightamerIOP/Sources/Lut3d/LutLibraryStore.swift      # 修改：InstalledLut.rememberedEncodings additive + 三层读取序 + 记住写回面 + seedBuiltIns 补标
  - App/Sources/Lightamer/UI/Inspector/LutPanelView.swift # 修改：encoding 双 Picker（scene/display 分组）+ 记住编码 Toggle——**基于 a81483d 后状态**（FINDING-F 修复批 owned 面已释放，git log 已复核）
  - Resources/Localizable.xcstrings                       # 修改：新键块 append 尾部（历史键字节与顺序零触碰）
  - Tests/LightamerTests/Lut3dEncodingTests.swift         # 新建（IOPP——`Lut3d*` 域模式）：曲线往返 + 标准表 golden 向量 + 矩阵正交/白点保持 + 烘焙参考 + 快路径/计数/LRU + 三层序 + seeder 幂等 + 旧档零漂移
  - Tests/LightamerTests/Lut3dGoldenImageTests.swift      # 修改（IOPP）：内置集抽样 LogC4→LUT→Rec709g24 全链 golden（补标前后对照）
  - Tests/LightamerTests/LutLibraryStoreTests.swift       # 修改（IOP）：记忆对持久化字节零漂移 + persistRegistry 面扩测
  - Tests/LightamerTests/LutEncodingPanelTests.swift      # 新建（App——App 级面板实态）：双 Picker 分组/选择写 params/记住 Toggle 回写
  - Project.swift                                         # 修改：新测试文件登记（显式清单，L041 generate 恒批尾）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # 修改：增行登记（同 commit 闭环，E2）
  - .work/gsd/phases/m3-1-w1/M3-1-01-SUMMARY.md           # 新建（收口任务）
  - .work/gsd/phases/m3-1-w1/M3-1-01-DECISIONS.md         # 新建（收口任务）
  - .work/gsd/REQUIREMENTS.md                             # 修改：M2GRADE-08 勾选 + Delivered 注记（T6）
  - .work/GOAL-STATE.md                                   # 修改：续接点追加（追加式）
  - .work/LESSONS.md                                      # 如踩坑
---

# Plan M3-1-01 — M2GRADE-08 LUT 作者编码建模

> **性质**：M3 首个功能 plan——修「胶片 LUT 作于 log 域而我方按 working space 直套」系统性偏差
> （FSIM-01 软前置基建）。上游对表正本 = Alcedo `c740f7b`（`RESEARCH-NOTES.md` §一 file:line
> 实测）：目录行集与字段形对表、**数学零复制**（GPL-3.0——传递曲线数学自各公开标准白皮书/
> ITU/SMPTE 文档，gamut 矩阵自 primaries_xy 经标准 Bradford 色适应公式自算）。
>
> **隔离前提已核**（planner 2026-10-08 亲核 git log）：修复批两腿均已落——FINDING-F
> `a81483d`（LutPanelView 导入取消腿，`Task { importLut() }` 已在场）+ ToneEqual
> `08dd061`（stateLock 守护 + 回归测试）。本 plan 对 `LutPanelView.swift` 的全部改动
> **基于 `a81483d` 后状态**（本文件行号锚 = 修复后当日实测）；导入取消腿零触碰。

## 已定裁决（七项生效值，硬约束，不得重开）

> 裁决正本 = `M3-1-CONTEXT.md` §六 + 文末裁决记录（用户回批 2026-10-08「OQ-M3-1-1..7
> 全部按推荐」）。本 plan 承载 OQ-1..4；OQ-5/6/7 归 02/03 plan。

- **OQ-1① 未标注默认 = working space 双端直通**：`Params.inputEncoding/outputEncoding`
  additive optional，nil = 默认对 `{linear_rec2020, linear_rec2020}`（id 拼写随目录集定）
  ——**现行 working space 直套行为逐字节保持**。拒绝 sRGB 假设方案（翻全部旧档渲染 = 违约）。
- **OQ-2② 编码目录 = 精选 14-18 条表驱动**（KD-1 定 17 条）：scene log 10 条 + display 7 条；
  内置 40 张的对（arri_logc4_awg4 / rec709_bt1886）必在集内。加行 = 加 case（编译期穷举
  switch 破缺警告）。色域维既有 `LutColorspace` Picker 不动不吸收（零破坏旧档）。
- **OQ-3① LMT 生效 = 宿主侧复合表重烘焙**（Alcedo `lut_bake.cpp:317-352` 同形）：逐 voxel
  `inputDecode → 源表采样 → outputEncode` 烘进表本体，Float64 数学，**零新 kernel**
  （`Lut3dKernels.metal` 零 diff）；`paramsHash` 随编码对自动变化 → PipeCacheKey 免费失效；
  模块内 LRU 16 张（对表 `CompositeCache :117-158`）防切档抖动。
- **OQ-4① 内置 40 张 seeder 自动补标**：`seedBuiltIns`（`LutLibraryStore.swift:474`）写入
  记忆对 `{arri_logc4_awg4, rec709_bt1886}`（生成参数有案 =
  `phases/m2-5-color-grade/evidence/spectral-film-lut-license.md:150-152`）；既有已选文档按
  三层序停在默认对（旧渲染逐字节不变，非破坏性红线）；**交付注记声明「新选档观感变化 =
  修正非回归」**（T6 落 SUMMARY + VALIDATION-INPUT 注记）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 编码目录行集（17 条 = OQ-2① 上限内）

| # | id | referral | transfer | gamut | peak nits |
|---|---|---|---|---|---|
| 1 | `acescc` | scene | ACEScc | AP1 | 0 |
| 2 | `acescct` | scene | ACEScct | AP1 | 0 |
| 3 | `arri_logc4_awg4` | scene | ARRI LogC4 | AWG4 | 0 |
| 4 | `arri_logc3_awg3` | scene | ARRI LogC3 | AWG3 | 0 |
| 5 | `sony_slog3` | scene | Sony S-Log3 | S-Gamut3 | 0 |
| 6 | `canon_clog3` | scene | Canon C-Log3 | Cinema Gamut | 0 |
| 7 | `fuji_flog` | scene | Fuji F-Log | FilmLG | 0 |
| 8 | `panasonic_vlog` | scene | Panasonic V-Log | V-Gamut | 0 |
| 9 | `nikon_nlog` | scene | Nikon N-Log | N-Gamut | 0 |
| 10 | `apple_log` | scene | Apple Log | Apple Log Gamut(Rec2020 原色) | 0 |
| 11 | `linear_rec2020` | scene | linear（恒等） | Rec2020 | 0 |
| 12 | `rec709_bt1886` | display | BT.1886（= 纯 γ2.4，Lb0——与 M2-6 EOTF 同语义） | Rec709 | 0（SDR） |
| 13 | `rec709_srgb` | display | sRGB 分段 | Rec709 | 0（SDR） |
| 14 | `rec709_gamma22` | display | 纯 γ2.2 | Rec709 | 0（SDR） |
| 15 | `displayp3_srgb` | display | sRGB 分段 | Display P3 | 0（SDR） |
| 16 | `rec2100_pq1000` | display | PQ (ST 2084) | Rec2020 | 1000 |
| 17 | `rec2100_hlg1000` | display | HLG（含参考显示器 OOTF） | Rec2020 | 1000 |

- **字段形对表** Alcedo `kEncodings :139-172`：`{id, gamut, transfer, referral, peakNits,
  displayName}`；行集为精选子集非 26 条全镜像（OQ-2② 裁决理由：每条曲线 = 真数学 +
  golden 工作量；camera 原生域无 LUT 语料拉动者不入首波）。`linear_rec2020` = working
  space 行（对表 `IsWorkingSpace :33-35` 以 id 判定 + 默认对双端命中）。
- **首波削项注记**（DECISIONS 登记即可，非重开）：Alcedo 的 red_log3g10/dji_dlog/
  bmd_film_gen5/davinci_intermediate/clog2/flog2/rec2020_bt1886/p3_gamma26 族 + 22 gamuts
  全表不入首波；后续加行 = 加 case 加行（表驱动，无结构改动）。

### KD-2 传递函数数学落笔（`LutTransferMath.swift`，Float64 正逆双落笔）

- **复用优先**：PQ/HLG/BT.1886 直接调 `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift` 的
  `DrtEotfMath.st2084EncodeY/DecodeY(:110/:121)`、`hlgEncode/hlgDecode(:149/:161，含
  peak OOTF)`、`powerEncode/powerDecode(:172/:177)`——**该文件零 diff**（只 import 调用，
  GPU contract 面不触碰）。display 臂中介语义对表 `DisplayDecode/DisplayEncode :60-108`：
  display light（1.0 = 100 nits）为中介，peak 换算 `peak/100`；codes 越界 clamp。
- **新写曲线**（每条 encode + decode 一对，Float64，公开标准为源）：
  ACEScc/ACEScct（SMPTE ST 2065-1 / ACES 文档附精确表值 = golden 向量源）、ARRI LogC4
  （ARRI 白皮书 A0042 样点表 = golden 源）、LogC3（ARRI A0011/A0125）、S-Log3（Sony
  技术文档）、C-Log3（Canon 白皮书）、F-Log（Fujifilm 规格）、V-Log（Panasonic 规格）、
  N-Log（Nikon 规格）、Apple Log（Apple 白皮书 2023）、sRGB 分段（IEC 61966-2-1）。
  golden 向量禁取 Alcedo 测试文件（GPL）——取各标准白皮书公开表值。
- **gamut 矩阵**：`kGamuts` 对表字段形 `{id, name, primaries_xy[8], 白点}`；矩阵 =
  primaries_xy → working Rec2020 linear 的 3×3，经标准 Bradford 色适应公式在 init 时
  自算（非手抄上游矩阵常量）；golden = 正逆乘积 ≈ 单位阵 + 白点映射保持（D65/D60 白点
  常量对表公开色度学数值）。AP1 白点 = ACES ~0.32168/0.33767，其余 D65。

### KD-3 Params additive + 快路径 + 烘焙生效点（`Lut3dModule.swift`）

- **Params 扩展**：`inputEncoding/outputEncoding: LutEncoding?`（`LutEncoding: String` raw
  enum = KD-1 行集，CaseIterable）。**Codable 容错解码**：自定义 `init(from:)` 缺键 =
  nil（= 默认对，对表 Alcedo `ReadEncoding :36-44` 缺键默认），未知 rawValue = nil
  （typed degrade，不崩旧档读新档场景的反向兼容）。**hash 零漂移约束**：
  `ParamsCoding.encode`（sortedKeys，`ParamsCoding.swift:17`）对 nil optional 走
  synthesized `encodeIfPresent` 缺席 → 既有档 encoded bytes 逐位不变 → paramsHash 不变
  → PipeCacheKey 零失效。AC 有专测（`StableHash.hash(ParamsCoding.encode(Params()))`
  前后逐位一致）。
- **烘焙插入点**：`commitParams`（:139-143 一带）在 `resolver.lut(named:)` 取得源
  `CubeLut` 之后、纹理上传之前：对 = 默认双端 且 域单位 [0,1] → 源表原样直通（快路径，
  对表 `:321-323` + `HasUnitDomain :195-203`）；否则逐 voxel
  `inputDecode(voxel) → CPU 参考采样源表 → outputEncode` 产出复合表（尺寸 = 源表尺寸，
  65³ ≈ 4.4MiB 对表；Float64 通道数学），复合表域 = 单位域；uniforms 域随表。
  CPU 采样器 = golden 测试既有 CPU 参考 sampler 同源（M2-5 惯例）；切片 =
  `DispatchQueue.concurrentPerform`（对表 Alcedo 线程池 :300-313，按 voxel 索引确定性
  归并，无 await）。
- **LRU + 计数器**：模块内 LRU 16 张，键 = `{源表 StableHash(data+domain), inputID,
  outputID}`（对表 `CompositeKey :88-101`）；命中 = 零重烘焙。`bakeCount` 可观测
  （对表 `g_bake_count :354-356`，instance 级 internal 读口供测试断言：默认对零烘焙 /
  换对恰一次 / LRU 命中零次）。**L069 纪律**：LRU/committed 等新引用态窗口入既有
  stateLock 式守护（`08dd061` 先例——重叠 run 并发 process 的引用态撕裂前车），锁内零 await。
- **1D 边界**：编码对 v1 只适用 3D 表；`is1D` 时编码对不参与烘焙（面板同步隐藏，KD-4）。
  DECISIONS 注记（对表 Alcedo LMT 亦为 3D 面）。
- **tiling 零触碰**：烘焙发生在表装配（commitParams），非 per-tile；`.allowTiling` flags
  不动。

### KD-4 面板（`LutPanelView.swift`，基于 a81483d 后状态）

- **增量位**：encoding 双 Picker 插既有 colorspace Picker（:66-71）邻位（库树 :56-64
  之后）；条目按 **scene / display 两组**（对表 `editor_lut_encoding_model.cpp:23-40`
  groupLabel Tr("Scene")/Tr("Display")——SwiftUI Picker Section + zh 键
  `panel_lut_group_scene`/`panel_lut_group_display`）。显示条件 = `lutName != nil &&
  !is1D`（与 interpolation Picker 同款隐藏面）。
- **三层读取序**（对表 `lut_library_controller.cpp:320-324` `value_or(默认对)`）：
  ①库行选择 → entry 有记忆对 → 记忆对写 params（与 lutName 同一次 applyDiscrete，
  单 commit）；无记忆对 → 编码字段保持 nil（= 默认对语义，不显式写值）。
  ②用户改 Picker → applyDiscrete 写 params（每 Picker 一次 discrete commit，D-H1 惯例，
  沿 :186-190 `applyDiscrete` 既有通道）。
  ③「记住编码到库」Toggle（session 级，默认 ON）：ON 且 entry 已注册 → Picker 变更
  回写库条目（`LutLibraryStore` 新写回面 → `persistRegistry`（:287））；entry 缺席 =
  typed no-op。对表 `setRememberEncodings :333-339`。
- **零 diff 面**：colorspace Picker（:66-71）/ interpolation（:73-81）/ 库树 / 导入按钮
  （:41-51 含 a81483d 的 `Task { importLut() }` hop）/ `importLut()`（:163-183）——
  全部不动。AX id：`inspector.picker.lut.encoding.input` / `.output` /
  `inspector.toggle.lut.remember-encodings`。
- **D-H4 hash 联动免费失效**：编码对入 params → paramsHash 变 → PipeCacheKey 链自动
  miss（KD-3），面板零额外失效逻辑。

### KD-5 seeder 补标（`LutLibraryStore.swift`）

- `seedBuiltIns`（:474）对 40 张内置 spectral film LUT 的 registry 行写入
  `rememberedEncodings = {input: arri_logc4_awg4, output: rec709_bt1886}`。
- **幂等哨兵**：已有记忆对的条目不覆写（重装/升级重 seed 幂等）；**无记忆档字节零漂移**
  = additive optional `encodeIfPresent`（对表 Alcedo 写侧 :172-179 仅非空写字段；
  M2-5 `relativePath` additive 先例同款）。
- `InstalledLut` 扩展 = `rememberedEncodings: RememberedEncodings?`（单 struct 原子对，
  `{input, output}` 两字段——禁两独立 optional 防半对态）；synthesized decode 宽容。
- **既有文档不受扰**：三层序①优先 params 显式值、②库记忆、③默认对——已选内置 LUT 的
  旧档 params 无编码字段 = 默认对 = 旧渲染逐字节。AC 有专测。

### KD-6 golden 与验收锚（OQ 上下文 §七.1 兑现）

- **曲线层**：每条新曲线 encode∘decode 在梯度采样上 ≈ 恒等（p99.9 ≤ 1e-5 分级容差，
  M2-5 golden 惯例）；标准表值 golden 向量逐点（ACEScc/LogC4 等白皮书公开表）。
- **烘焙层**：合成 log 编码梯度表（已知逆变换）+ 已知对（logc4→bt1886）复合表 vs
  Float64 CPU 参考逐 voxel 对照（p99.9 ≤ 1e-5）；计数断言三态（KD-3）。
- **全链层**：内置集抽样 3 张（确定性命名）以补标对走 LogC4 进 → 源表 → BT.1886 出的
  GPU 全链 golden，**补标前后对照**（默认对 = 直通快路径渲染 vs 补标对 = 复合烘焙渲染，
  两者差异非零且有向 = 偏差修正生效的直接证据；补标后输出 vs CPU 参考 = 正确性）。
  读回前 `drain()` fence（**L014**）。
- **快路径回归**：既有 LUT 测试族（`Lut3dKernelTests` / `CubeLutParserTests` /
  `LutLibraryStoreTests` / `BuiltInLutSetTests` / `Lut3dGoldenImageTests` 既有用例）
  零改全绿。

## read_first

1. `.work/gsd/phases/m3-1-w1/M3-1-CONTEXT.md`——D-M3-1-CONTEXT-1..5 + 裁决记录 +
   §五隔离前提（`LutPanelView` 交叉注记）。
2. `.work/gsd/phases/m3-1-w1/RESEARCH-NOTES.md` §一/§三.1/§三.2/§三.7——Alcedo
   `c740f7b` file:line 全套对表锚 + 我方底座行号 + 内置集生成参数。
3. `LightamerIOP/Sources/Lut3d/Lut3dModule.swift`——Params（:53-72）/ LutResolving
   （:93-96）/ commitParams 装配缝（:139-215）/ colorspace 矩阵消费（:194）。
4. `LightamerIOP/Sources/Lut3d/LutLibraryStore.swift`——InstalledLut（:52-80，additive
   optional 先例 :61/:64）/ seedBuiltIns（:474）/ persistRegistry（:287）。
5. `App/Sources/Lightamer/UI/Inspector/LutPanelView.swift`——**a81483d 后状态**：
   导入按钮 Task hop（:41-51）/ 库树（:56-64）/ colorspace Picker（:66-71）/
   applyDiscrete（:186-190）。
6. `LightamerCore/Sources/Pipe/Drt/DrtEotf.swift`——`DrtEotfMath` 复用面（st2084/hlg/
   power，:75-250）+ GPU contract 零 diff 红线。
7. `LightamerCore/Sources/Foundation/ParamsCoding.swift`——sortedKeys 正本（hash 零漂移
   论证依据）+ `Tests/LightamerTests/Lut3dGoldenImageTests.swift`——CPU 参考 sampler 与
   分级容差惯例。

## 纪律（强制）

1. **零新 kernel**：`Lut3dKernels.metal` 零 diff；`DrtEotf.swift` / `DrtOutputColorSpace`
   / `PixelPipe.swift` / `PipeCacheKey` / `V50Order` / `ModuleRegistry` / 六格式矩阵编码器
   / `WebPEncoder` / `NLMeansModule` 全红线域零命中（`git diff --name-only` 机检）。
2. **改码半径**：产线 diff = 上列 files_modified 前五个源文件；`LutColorspace` enum 与
   colorspace Picker 语义零 diff（面板既有 Picker 不吸收不重排——CONTEXT D-1 正交维裁定）。
3. **测试登记纪律**：新测试文件同 commit 登记 Project.swift 显式清单 + BUNDLE-MAP 增行
   （E2）；`tuist generate` 恒为该批最后一个动作（**L041**）。域归属：`Lut3d*` 模式 →
   IOPParity（D5 拆分规则）；`LutLibraryStoreTests` 既有文件原地扩（IOP）；App 级面板
   实态测试 → App target。
4. **golden 纪律**：分级容差 p99.9 ≤ 1e-5（M2-5 惯例）；GPU 读回前 fence（**L014**）；
   golden 向量源 = 公开标准白皮书（**GPL 零复制**——Alcedo 测试/源码只对表行为与行集，
   数值禁抄）。
5. **提交纪律**：每任务独立提交（Conventional Commits 英文，body 写 what+why，不 push，
   `-F` 写 message）；本 plan 收口跑定向轮 `--bundle IOP` + `--bundle IOPParity` + 
   `--bundle App`，全套 `--all` 留 03 收口 plan 终验（报备制）。
6. **checker 四条**：①真链（烘焙走真 CubeLut/真纹理上传，golden 走真 GPU 渲染，禁 mock
   计时/对照）；②登记闭环（E2 三方对表：`grep -c "func test"` = BUNDLE-MAP 行 =
   Project.swift 清单）；③可观测（bakeCount 断言 + golden 表逐值对账）；④边界核对
   （T6 `git diff --stat` 对表申报集，零命中红线域）。

## Tasks

### T1 编码目录 + 传递函数族（KD-1/KD-2）

- **read_first**：上列 1/2/6/7。
- **action**：新建 `LutEncodingCatalog.swift`（17 行表 + gamut primaries + Bradford 自算
  矩阵 + `find(id:)` 未知 typed nil）+ `LutTransferMath.swift`（新写曲线正逆 +
  DrtEotfMath 复用薄适配）。
- **验收标准**
  - [ ] `Lut3dEncodingTests`：逐曲线 encode∘decode 梯度往返 ≈ 恒等（p99.9 ≤ 1e-5）；
        标准表值 golden 向量逐点；gamut 矩阵正逆乘积 ≈ 单位阵 + 白点保持；未知 id
        typed 拒绝。
  - [ ] `--bundle IOPParity Lut3dEncodingTests` 绿；两新文件登记 Project.swift +
        BUNDLE-MAP + generate（L041）。

### T2 Params additive + 快路径 + 烘焙 + LRU（KD-3）

- **read_first**：上列 3/7。
- **action**：`Lut3dModule.swift` 扩展（Params 两 optional + 容错 Codable + commitParams
  烘焙插入 + concurrentPerform 切片 + LRU 16 + bakeCount + L069 stateLock 纪律）。
- **验收标准**
  - [ ] `Lut3dEncodingTests` 扩：默认对快路径零烘焙（bakeCount == 0）/ 换对恰一次 /
        LRU 命中零次；复合表 vs Float64 CPU 参考逐 voxel（p99.9 ≤ 1e-5）；
        `StableHash.hash(ParamsCoding.encode(Params()))` 扩展前后逐位一致（hash 零漂移）；
        未知 id decode = nil 不崩。
  - [ ] 既有 `Lut3dKernelTests` / `CubeLutParserTests` 零改全绿（定向轮）。

### T3 库内记忆三层序 + seeder 补标（KD-5）

- **read_first**：上列 4。
- **action**：`InstalledLut.rememberedEncodings` additive + `seedBuiltIns` 补标 +
  `updateRememberedEncodings` 写回面（persistRegistry 复用）。
- **验收标准**
  - [ ] `Lut3dEncodingTests` + `LutLibraryStoreTests` 扩：三层序
        （params 显式 > 库记忆 > 默认）；seeder 幂等（二次 seed 不覆写）；无记忆档
        registry JSON 字节零漂移；40 张补标对逐条断言（arri_logc4_awg4/rec709_bt1886）。
  - [ ] `--bundle IOP LutLibraryStoreTests` 零改用例全绿。

### T4 面板双 Picker + 记住 Toggle（KD-4）

- **read_first**：上列 5（**a81483d 后状态**）+ `Tests/LightamerTests/PanelWiringTests.swift`
  （面板实态测试惯例）。
- **action**：`LutPanelView.swift` 增量 hunk（双 Picker 分组 + Toggle + 三层序接线 +
  zh 键块 append xcstrings 尾部）；AX id 三枚（KD-4 拼写）。
- **验收标准**
  - [ ] `LutEncodingPanelTests`（App）：分组条目数 = 目录 17；选库行载入记忆对进
        params（单 commit）；Picker 变更写 params（discrete 单 commit）+ Toggle ON 回写
        store、entry 缺席 no-op；1D 时双 Picker 隐藏。
  - [ ] colorspaces/interpolation/库树/导入按钮四既有面零 diff；`--bundle App` 定向绿。

### T5 全链 golden + 快路径回归（KD-6）

- **read_first**：上列 7。
- **action**：`Lut3dGoldenImageTests` 扩全链用例（内置抽样 3 张补标前后对照 + GPU vs
  CPU 参考）；定向轮 IOP + IOPParity 全量。
- **验收标准**
  - [ ] 全链 golden 绿（fence 后读回）；补标对渲染 ≠ 默认对渲染（差异非零）且 =
        CPU 参考（±1e-5 分级）；既有 golden 用例零改全绿。

### T6 收口

- **action**：SUMMARY（含「观感变化 = 修正非回归」交付注记段落）/ DECISIONS（首波削项
  注记 + 1D 边界 + 默认 nil 不显式写值裁定）/ REQUIREMENTS M2GRADE-08 翻账 + Delivered
  注记（FSIM-01 软前置交付物声明：目录 + 曲线族即 M3-3 消费面）/ GOAL-STATE 续接点追加；
  `git diff --stat` 对表。
- **验收标准**
  - [ ] AC 总表全绿；diff 边界 == 申报集；红线域 `git diff --name-only` 零命中；
        定向三 bundle 绿（计数对账 = 登记值）。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 目录 17 条表驱动（scene 10 + display 7；arri_logc4_awg4/rec709_bt1886/linear_rec2020 在集），加行 = 加 case 穷举警告生效 | T1 测试 + `grep -c "case" LutEncodingCatalog.swift` |
| 2 | 曲线正逆往返 + 标准表向量 + 矩阵正交/白点 golden 全绿（p99.9 ≤ 1e-5 分级） | T1 测试日志 |
| 3 | 默认对 = working 双端直通：快路径零烘焙 + 旧档 paramsHash 逐位零漂移 + 旧 sidecar 解码渲染逐字节不变 | T2/T3 专项断言 |
| 4 | 烘焙复合表 vs Float64 CPU 参考 p99.9 ≤ 1e-5；bakeCount 三态断言（0/1/LRU 0）；L069 stateLock 纪律在位 | T2 测试 + 代码审 |
| 5 | 三层读取序单测（params > 库记忆 > 默认）；seeder 幂等；40 张补标对逐条在场；无记忆档字节零漂移 | T3 测试 |
| 6 | 面板双 Picker 分组/单 commit 写值/记住回写/1D 隐藏 + AX 三枚 + colorspace Picker 零 diff | T4 App 测试 + diff 核 |
| 7 | 全链 golden：内置抽样补标前后对照（差异非零有向 + 补标后 = CPU 参考）；fence 在位 | T5 测试日志 |
| 8 | 登记闭环：Project.swift/BUNDLE-MAP = 测试 func 数逐位；L041 generate 批尾；红线域零命中 | 三方对表 + `git diff --name-only` |

## 风险与边界

- **相机 log 曲线白皮书数值源**：Apple Log / N-Log 等部分规格公开度有限——golden 向量取
  已发表表值；取不到精确表值的曲线退化为往返恒等 + 端点/中灰有向断言，DECISIONS 登记
  （禁以 Alcedo 数值充源）。
- **烘焙耗时**：65³ Float64 concurrentPerform 预估百 ms 内（一次性，LRU 摊销）；若实测
  显著超预期 → DECISIONS 登记观测值（禁为此改 kernel 或降 Float32 精度）。
- **display 臂 peak 语义**：SDR 行 peak=0（无 peak 换算，1.0 = 100 nits 中介恒等）；
  PQ/HLG peak=1000 换算走 DrtEotfMath 既有 peak 形参——与 M2-6 EOTF 语义一致性由复用
  保证。
- **`LutPanelView` 并发窗口**：修复批 owned 面已释放（git log 亲核）；若派发前 GOAL-STATE
  出现该文件新在飞批次（M5 面板族加固专项等），orchestrator 协调顺序后再派本 plan。

## 提交约定

- T1 `feat(iop): lut encoding catalog with transfer curve math`
- T2 `feat(iop): bake input/output encoding into lut3d composite table`
- T3 `feat(iop): per-lut remembered encodings and builtin reseeding`
- T4 `feat(app): lut panel encoding pickers with remember toggle`
- T5 `test(iop): full-chain log-domain lut golden against cpu reference`
- T6 `docs(m3-1): close out plan 1 encoding modeling batch`
- 全英文 Conventional Commits；不 push。
