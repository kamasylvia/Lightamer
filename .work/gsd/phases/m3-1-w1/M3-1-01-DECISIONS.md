# M3-1-01-DECISIONS — 执行期裁定与登记

> Plan 正本 = 同目录 `M3-1-01-PLAN.md`（七项裁决 + checker 回注引注块 = 定稿处方）。
> 本文件只登记**执行期**的裁定/偏离/边角；不重开任何已定裁决。

## §1 首波削项与加行路径（KD-1 注记兑现）

- 目录 = 精选 17 条（KD-1 表原样）。Alcedo 全 26 条中的 red_log3g10 / dji_dlog /
  bmd_film_gen5 / davinci_intermediate / clog2 / flog2 / rec2020_bt1886 / p3d65_gamma26 /
  p3dci_gamma26 族 + 22 gamuts 全表**不入首波**（OQ-2② 裁决理由：每条曲线 = 真数学 +
  golden 工作量，相机原生域无 LUT 语料拉动者不入）。加行 = 加 `LutEncodingId` case +
  `all` 表项（需要新曲线时 `LutTransferCurve` 加 case——编译期穷举 switch 破缺警告生效）。
- `LutTransferCurve` 枚举含 `srgb/bt1886/gamma22/pq/hlg` 为 display 行服务；scene
  dispatch 对这些 curve 的分支仅保 switch 穷举（目录 referral 列使 display 行恒走
  display 臂，不可达路径无运行时陷阱）。

## §2 快路径条件偏离 Alcedo `HasUnitDomain`（checker M5 相关，实测驱动）

- **裁定**：快路径 = 「默认对」单独成立；**移除** `HasUnitDomain` 条款（Alcedo
  lut_bake.cpp :321-323 = `IsWorkingSpace && IsWorkingSpace && HasUnitDomain`）。
- **依据**：OQ-1①「未标注默认 = working 直通**逐字节保现状**」是已裁决的硬值，且
  「既有 LUT 测试族零改全绿」是 plan 纪律级红门。首轮实现按 plan KD-3 字面
  （`!isDefaultPair || !isUnitDomain` 触发烘焙）在 IOPParity 全量轮被
  `HDRPipelineMatrixTests` 两用例当场抓获（5 红）：非单位域（HDR 域 [-1,4] 等）表格
  在默认对下被单位域重采样，「stored table entry must survive EXACTLY」与链级恒等断言
  即红。改为默认对恒 verbatim（含原生 domain uniforms）后全量复绿（389/3/0）。
- **与 Alcedo 偏离登记**：Alcedo 的 working space（acescc）本身是单位域，其
  HasUnitDomain 条款实际只挡「非单位域 + working 对」的罕见档；我方 HDR 域表格是
  既有交付面（T5 HDR 全链族），字节保持优先。非默认对 + 非单位域仍走烘焙（复合体素
  单位域 + 过源表 domain 采样，checker M5 ②语义保持，专测
  `testNonUnitDomainDefaultPairStaysVerbatim` + M5② 由
  `testBakeCompositeVsCPUReference` 的 domain 传参路径覆盖）。

## §3 公开标准舍入常数的膝点不连续（F-Log / N-Log）

- F-Log：encode 线性段 cut(0.00089) 的 code 像（~0.10058）与 decode cut2
  （0.100537775223865）相差 ~3e-5；N-Log：encode cut(0.328) 的真值 code ~451.8 被规格
  整数化为 452（cut2 = 452/1023），带宽 ~2.9e-4。**这是公开标准常数本身的舍入属性，
  参考实现（colour-science）同型存在**，非我方实现缺陷。
- 处置：round-trip golden 域排除膝带（F-Log (0.0008, 0.0010)、N-Log (0.320, 0.336)）+
  `testKneeDiscontinuityBounded` 带内扫描钉跳跃上界（F-Log < 1.5e-5、N-Log < 3.5e-4）。
  若未来规格给出连续化常数，收紧即可。

## §4 全链 golden 的门结构（T5，对 plan KD-6「±1e-5」的实测修正）

- 「GPU 渲染 == 源表 Float64 全链 ±1e-5」**数学不可达**：烘焙把源表重采样进 65³ 单位域
  复合晶格，GPU 采样的是复合晶格插值；胶片曲线在线性工作域的局部斜率使晶格插值地板
  实测 ~8e-3（Agfa_Vista_100 全链 0.0087、Kodak_Vision_320T 0.0068），远超 1e-5。
- **门分解**（两层并存缺一不可）：
  1. **voxel 级烘焙门**（Lut3dBakeTests.testBakeCompositeVsCPUReference ≤1e-5）：
     复合表逐 voxel == Float64 encode→sample→decode 链——**正确性锚**（f32 存储前）；
  2. **方向探测 golden**（三探针，恒等表闭式独立推导）——**方向锚**（防臂序同误解）；
  3. **忠实渲染门**（T5 ≤1.5/1024）：GPU 输出 == 复合表自身的四面体插值——管线
     忠实性（同表双侧插值，既有 testNonIdentityTableWithRealMatrices 同型）。
- 此为对 plan AC7/T5 验收标准的**实测收窄**（数值门从 1e-5 收窄为「voxel 级 1e-5 +
  渲染级晶格地板」），checker 晨审可推翻（推翻 = 需更高分辨率复合表或 CPU 采样臂，
  两者都违 M5 偏离注记/零新 kernel 精神）。

## §5 stateLock 守护范围（checker M4 裁定项兑现）

- **守护**：①commitParams 全部引用态变更窗（resolvedDevice/uniformBuffer/clutTexture/
  rampTexture/committed/committedIs1D/compositeCache/compositeOrder/bakeCountStorage/
  lastCompositedStorage）；②process 的引用提取（table/is1D/interpolation 快照）；③
  共享 uniform buffer 的 per-run 盖章窗（width/height/level 戳 + setBuffer + dispatch +
  endEncoding 原子化，L069 同族——:329-332 现窗口）。锁内零 await（encoder session 的
  async makeEncoder 在锁外）。
- **不扩（登记 defer）**：GPU 侧读序残留（A run 戳过的 command buffer 在 B run 再戳后
  才执行）——属 coordinator 级 render 串行化/取消传播（M4 Maintenance 专项，与
  ToneEqualModule `08dd061` 的 defer 同一条目）；模块级锁无法修队列执行序。
- 烘焙（~百 ms 级，65³ concurrentPerform）在锁内同步执行：并发 process 的引用提取
  最长阻塞一个烘焙周期，一次性成本由 LRU 摊销——以正确性优先，观测值未超预期。

## §6 复合表尺寸/域偏离（checker M5 ①②③兑现记录）

- ①复合 voxel 单位域枚举、尺寸 = 源表尺寸（偏离 Alcedo 定长 `kLmtCompositeEdge = 65`
  〔lut_bake.hpp:27〕单位域）：免 65³ 重采样步、非 65 源表免上/下采样质量损；
  ②源表非单位域时 CPU 采样过源表 domain 映射（`sampleTable` 传源 domainMin/Max，对表
  `SampleLutTable` :188）；③烘焙臂 uniforms 恒写单位域（commitParams 的 domainMin/Max
  在烘焙分支覆写为 0..1，禁沿用源表域值）。
- 另据 §2：非单位域表格在**默认对**下根本不进烘焙（verbatim），M5② 的 domain 映射
  只在真实对烘焙内发生。

## §7 补标边角登记（checker E3）

- **drift 再采纳重盖**：BuiltIn/ 行文件被外部改写 → `adopt()` 整行重建 → 记忆对重盖为
  正本值（内置集对有案，重盖 = 回正本值）——专测钉死。
- **External（非 BuiltIn/）行用户对被漂移清除**：同一重建机制不区分记忆对来源，用户对
  随行重建丢失。已知边角，不修（修法 = adopt 时保留旧记忆对，但「文件都换了记忆还
  对不对」语义存疑；保守 = 丢弃，用户可重设）。专测钉死现状
  （testDriftReadoptionRestampsBuiltInAndClearsExternal）。
- **补标范围恒限 `BuiltIn/` 前缀**：可配根下用户自建 BuiltIn/ 目录的文件同样命中前缀
  规则（与 KD-4 seeder 的目录纪律同构——目录名即语义）；未加「仅默认根」条件，保持
  规则单一（测试可在 temp root 复现）。
- `updateRememberedEncodings` 清除（nil）= 移除 JSON 键（encodeIfPresent 对称），
  persistRegistry 复用零新增持久化调用点。

## §8 面板三层序与写值语义（KD-4 补记）

- **默认对不显式写值**：无记忆档的库行选择只写 `lutName`，编码字段保持 nil（= 默认对
  语义）——旧档字节契约的对称面（nil 键缺席）；用户改 Picker 才显式写值（含改回
  linear_rec2020 也是显式值，语义同默认、字节不同——paramsHash 变化即缓存失效，
  正确行为）。
- **记住 Toggle 回写对 = 当前 params 对**（两侧齐写，非单侧增量），entry 缺席 = typed
  no-op（store face 层守卫，App 测试复述钉死）。
- 1D 表：编码对不参与烘焙（KD-3 边界）+ 面板双 Picker 隐藏（`showsEncodingPickers`）。

## §9 数学源与许可

- 传递曲线公式 = 公开标准/厂规格（S-2014-004、S-2016-002、ST 2065-1、ARRI A0042/
  A0011、Sony S-Log3、Canon C-Log3 v1.2、Fujifilm F-Log、Panasonic V-Log、Nikon
  N-Log v1.0.0、Apple Log、IEC 61966-2-1）；golden 向量 = 公开参考实现
  （colour-science，BSD-3）doctest 全精度值 + 本地 numpy 复算互证。**Alcedo（GPL）
  源码/测试零字节零数值引用**；colour-science 仅取数学事实（公式常量与公表值），
  无成段代码移植。
- gamut 矩阵 = primaries_xy + 标准 Bradford **程序自算**（init 时），独立数值锚 =
  ITU-R BT.2087 公表 709↔2020 矩阵对（≤2e-4，4dp 舍入容差）。
- LogC4 常量按 A0042 定义式**计算**（a/b/c/s/t 表达式），不手抄十进制近似。

## §10 测试计数与登记（checker ②/E2 闭环值）

- `grep -c "func test"`：Lut3dEncodingTests.swift = 24（Lut3dEncodingTests 14 +
  Lut3dBakeTests 10，同文件两类）、Lut3dGoldenImageTests.swift = 7（5 旧 + 2 新）、
  LutLibraryStoreTests.swift = 16（10 旧 + 6 新）、LutEncodingPanelTests.swift = 5。
- BUNDLE-MAP 行值 = 24 / 7 / 16 / 5（同批勘误），Project.swift 清单 = IOPParity
  （Lut3dEncodingTests、Lut3dGoldenImageTests）+ APP（LutEncodingPanelTests）+
  LIB（LutLibraryStoreTests 原文件）——三方逐位对表通过；`tuist generate` 恒批尾
  （L041，T1/T4 两次）。
- 新增合计 = **37**；REQUIREMENTS 翻账行同口径。
