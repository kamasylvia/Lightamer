# M3-1-01-ACCEPTANCE — M2GRADE-08 LUT 作者编码建模（W1 plan 1）独立验收

> 验收方：独立验收 subagent（零共享上下文，实测核验不轻信；夜间全自动授权在案）。
> 验收对象：T1 `e274cc0` / T2 `4f48d04` / T3 `a1e7d56` / T4 `9ab0193` / T5 `5c6291c` / T6 `74e14a4`（基线 `a81483d`+`08dd061`+plan docs `9072f93`）。
> 方法：定向亲跑 + 全量亲跑 + 独立数学复算（uv python3 + colour-science 0.4.7 BSD 参考实现，numpy 独立重写 Swift 公式）+ 逐 commit diff 边界机检 + 测试读码 + 破自参照推演实测。

## 结论

**PASS / 0 error + 1 minor + 2 observation**

- AC 总表 8/8 全绿（机检通道逐条亲核，见 §三）。
- 数学审计全 PASS（§四）：**10 条 camera log + sRGB 与 colour-science 零误差**（max err = 0.000e+00，含 LogC4/C-Log3/AppleLog/NLog 四条无 colour-science 旧面的曲线经 0.4.7 新面逐点精确）；Bradford 自算矩阵独立复算 vs ITU-R BT.2087 公表对 = 4.0e-5 / 5.0e-5（申报 ≤2e-4 成立）；方向探测 golden 经倒置推演实测**真破自参照**（倒置复合 vs 探针闭式偏差 1302，探针必红）。
- 两收窄（§2 快路径 / §4 门结构）均裁定**成立**（§五），非降门。
- hash 零漂移红线专测读码 + 通道核验通过（§六）。

## 一、亲跑数字对账

| 轮 | 申报 | 亲跑 | 判定 |
|---|---|---|---|
| IOPParity 全量 | 389/3/0 | **389/3/0**（405s，peakRSS 3438MB，无 MEMFAIL） | ✓ 逐位一致 |
| Lut3dEncodingTests 定向（IOPP） | 14/0/0 | **14/0/0**（6s，181MB） | ✓ |
| Library 全量 | 587/4/0 | （见 §七 环境注记） | 见 §七 |
| App 全量 | 635/0/0 | （见 §七 环境注记） | 见 §七 |
| IOP 全量（零漂移基线） | 471/1/0 | 未亲跑（非验收程序必跑项） | — |

四族归属：Lut3dEncodingTests.swift 两类 24 + Lut3dGoldenImageTests 7（含 FullChain 2）= IOPParity 全量轮内已亲跑；LutLibraryStoreTests 16 = LIB；LutEncodingPanelTests 5 = APP（后两族亲跑状态见 §七）。

测试读码另证（非执行路径，实现语义级）：24/7/16/5 方法清单与 BUNDLE-MAP 行值、Project.swift 显式清单三方逐位一致（`grep -c "func test"` 亲跑 = 24/7/16/5）。

## 二、逐 commit 边界与红线机检

- `git diff --name-only 9072f93..74e14a4` = 申报集（五源文件 + 四测试文件 + Project.swift + xcstrings + BUNDLE-MAP + REQUIREMENTS + GOAL-STATE + SUMMARY/DECISIONS + .gitignore 两个 chore）。
- 红线域机检零命中：`Lut3dKernels.metal` / `DrtEotf.swift` / `DrtOutputColorSpace` / `PixelPipe` / `PipeCacheKey` / `V50Order` / `ModuleRegistry` / 六格式编码器 / `WebPEncoder` / `NLMeansModule` 全 range diff 零命中（亲跑）。
- 六提交边界与申报一一对应（T1 仅目录+曲线+注册；T2 仅 Module+测试扩；T3 仅 Store+LIB 扩；T4 仅面板+xcstrings+APP 注册；T5 仅 golden +2；T6 纯 docs）。LutPanelView diff = 纯增量 118 行零删除（四既有面含 a81483d Task hop 字节零触碰，亲读 diff 证实）。
- **O-1（observation）**：T5 与 T6 之间夹两个 .gitignore chore 提交（`c9e19b0`/`e77db5c`）+ T6 后一个 docs 提交（`86c2e61` .work README）——零产线文件触碰、各自独立成提交，不违边界纪律；理想形态是执行申报中列明，记 observation 不计缺陷。
- stateLock 守护范围与 DECISIONS §5 裁定逐窗一致（commitParams 全部引用态变更窗 / process 引用提取 / 共享 uniform buffer 盖章窗 setTexture+setBuffer+dispatch+endEncoding；encoder session 的 await 在锁外；锁内零 await——亲读 4f48d04 diff 证实）。

## 三、AC 总表逐条核验

| # | AC | 核验 |
|---|---|---|
| 1 | 目录 17 条（scene 11 + display 6；三指定 id 在集；加行 = 加 case） | 源码读码 17 case 枚举 + `all` 表逐行 + 测试 `testCatalogRowCounts`（17/11/6 显式计数）+ 面板测试分组计数断言；`LutTransferCurve` 穷举 switch 无 default（读码）✓ |
| 2 | 曲线往返 + 标准表向量 + 矩阵 golden（p99.9 ≤1e-5） | IOPParity 全量轮绿 + **独立复算全绿**（§四，零误差级）✓ |
| 3 | 默认对 = 双端直通：快路径零烘焙 + paramsHash 逐位零漂移 + 旧档渲染逐字节不变 | `testBakeCountThreeStatesAndLRU`（fast path 0）+ `testParamsEncodingZeroDrift`（legacy JSON 逐字节 + hash 相等）+ `testNonUnitDomainDefaultPairStaysVerbatim`（verbatim + 原生域 uniforms）+ 既有 HDR storage 族/Lut3dKernelTests 零改全绿（IOPParity 全量轮亲证）✓ |
| 4 | 烘焙 vs Float64 CPU 参考 ≤1e-5 + 方向探针双方向绿 + bakeCount 三态 + stateLock 范围 = DECISIONS | `testBakeCompositeVsCPUReference` + 三探针 + 三态/LRU 断言亲跑绿；CPU 参考核验 = 测试侧独立 sampler（Lut3dKernelTests.cpuLut3d）非 bake 自身 `sampleTable`，非同源 ✓；探针破自参照独立推演 PASS（§四.4）✓ |
| 5 | 三层序 + 补标幂等（drift 重盖）+ 40 张逐条 + 无记忆档字节零漂移 | 测试读码（LutLibraryStoreTests 6 新法逐一对题）+ adoption 路径源码核（rescan hash 命中不重 adopt → 用户对存活；drift → adopt 整行重建 → BuiltIn 重盖/External 清除 = DECISIONS §7 登记态）✓ |
| 6 | 面板双 Picker + 单 commit + 记住回写 + 1D 隐藏 + AX 三枚 + colorspace 零 diff | 源码读码（AX id 三枚拼写 = KD-4）+ 库树选择腿 memory 同一 `applyDiscrete` + `test1DSkipsEncodingBake` + 面板逻辑 `LutEncodingPanelLogic` 纯函数提取可测形态 ✓（App bundle 亲跑见 §七） |
| 7 | 全链 golden：补标前后对照（差异非零有向）+ fence | `testBuiltInSampleRememberedPairFullChain`（3 张确定性抽样、drain fence 后 getBytes）+ `testRememberedPairRenderingDiffersFromDefaultPair`（>0.01 非零）亲跑绿（IOPParity 全量轮内）✓ |
| 8 | 登记闭环三方逐位 + L041 批尾 + 红线零命中 | grep=24/7/16/5 = BUNDLE-MAP = Project.swift（亲跑三方对表）；红线机检 §二 ✓ |

## 四、数学审计（独立复算，非轻信测试）

### 4.1 传递曲线 vs colour-science（BSD-3 参考实现）

方法：将 Swift `LutTransferMath` 公式逐条以 numpy 重写（读源码转录，非复制测试值），对梯度样点 vs colour-science 0.4.7 参考函数对表：

| 曲线 | colour-science 面 | max err |
|---|---|---|
| ACEScc | `log_encoding_ACEScc` | **0.000e+00** |
| ACEScct | `log_encoding_ACEScct` | **0.000e+00** |
| LogC3 EI800 | `log_encoding_ARRILogC3` | **0.000e+00** |
| LogC4 | `log_encoding_ARRILogC4` | **0.000e+00** |
| S-Log3 | `log_encoding_SLog3` | **0.000e+00** |
| V-Log | `log_encoding_VLog` | **0.000e+00** |
| F-Log | `log_encoding_FLog` | **0.000e+00** |
| C-Log3 | `log_encoding_CanonLog3`（/0.9 reflection 惯例同时精确命中） | **0.000e+00** |
| N-Log | `log_encoding_NLog` | **0.000e+00** |
| Apple Log | `log_encoding_AppleLogProfile` | **0.000e+00** |
| sRGB | `cctf_encoding` | **0.000e+00** |

- 「colour-science doctest 引用真实性」成立：申报的 golden 向量来源可复现（参考实现全精度值，非 Alcedo 数值）。SUMMARY §九 许可口径（BSD-3 数学事实、无成段移植）与实测一致。
- 公开锚点抽验：S-Log3 18% → **420.000**（Sony 公表 10-bit 码值精确命中）、90% → 597.9 ≈ 598；Apple Log 白皮书五常量（σ=47.28711236 / β=0.00964052 / γ=0.08550479 / δ=0.69336945 / R0=−0.05641088）经 web 独立核对白皮书文本一致。
- 膝点不连续（DECISIONS §3）：N-Log/F-Log 舍入常数属性确认（round-trip 域排除 + 跳跃钉界处置合理，colour-science 同型常量同缺陷）。

### 4.2 Bradford gamut 矩阵独立复算

以自写 Bradford（标准 MB 锥响应）从公表 primaries 重算 rec709↔rec2020 两向矩阵，对 ITU-R BT.2087 公表 4dp 值：**max err 4.04e-5（709→2020）/ 4.99e-5（2020→709）**，申报 ≤2e-4 成立且方向/表号（Table 8/9）引用正确（测试锚与公表方向逐位一致，验收方首轮脚本方向笔误已排除，非实现缺陷）。AP1 primaries vs colour-science ACEScg = 0 误差。

### 4.3 方向探测 golden「破自参照」推演（本波灵魂）

- 恒等表性质数学核：多线性/四面体插值对仿射函数精确 → 恒等表采样臂输出 ≡ 采样位（float 误差级），输出只剩两臂方向信息——「吃掉采样臂」成立。
- 倒置推演实测：以 numpy 独立实现「CONTEXT D-3 旧字面」（input **decode** 臂 + output **encode** 臂）复合，与探针闭式比对 = **偏差 1302**（≫1e-5 门）→ 若实现按旧字面反向，三探针必红。探针非同误解自参照，判定**真破自参照**。
- 三探针闭式与 bake 实现独立（测试内从 KD-2 曲线函数直算，未经 bake 代码路径）；voxel 级 CPU 对照（Lut3dBakeTests）与探针并存缺一不可的结构与 plan KD-6 checker E1 要求一致。

### 4.4 §4 晶格地板主张独立实测

DECISIONS §4 申报「65³ 复合晶格插值地板 ~8e-3」——独立实测脚本就绪（numpy 重建 bake + 四面体采样 verbatim 移植，Agfa_Vista_100，4000 随机点，`/tmp/m31_lattice_floor.py`），因 §七 shell 故障未能执行；补录槽见 §八。**该主张的合理性经结构论证独立成立**：复合表存储的是 decode 回线性 working 域的值，胶片输出在线性域动态范围大、65³ 晶格单格跨度 ~1/64，阴影高斜率区线性插值绝对误差达 1e-3~1e-2 量级属表驱动烘焙的固有属性（Alcedo 自家 65³ `kLmtCompositeEdge` 同理），且「GPU==源表 Float64 ±1e-5」在**任何**尺寸≈65³ 的复合晶格下都不可能达到 1e-5——§4 收窄的数学论证不依赖该实测值成立。

## 五、两收窄裁定

### §2 快路径偏离 Alcedo `HasUnitDomain` —— **裁定成立**

- OQ-1① 原文（CONTEXT §六）：「默认对 = working space 双端直通（**= 现行为逐字节保持**）」——用户裁决硬值（「OQ 全部按推荐」在案），plan 头部列明「硬约束，不得重开」。
- CONTEXT D-M3-1-CONTEXT-2 的快路径行（「双端 working + 表域 [0,1] 单位域 → 直通」）是对 Alcedo `:321-323` 的**镜像描述**；plan KD-3 落笔照抄三条件——与 OQ-1① 在「非单位域 + 默认对」档直接冲突（该档按 KD-3 字面会重采样翻字节）。
- 实测驱动证据链完整：首轮 IOPParity 全量 `HDRPipelineMatrixTests` 5 红（非单位域表格 verbatim + 原生域 uniforms 被翻）→ 收窄为「默认对单独成立」→ 全量复绿 389/3/0（本轮亲跑证实）。plan 纪律级红门「既有 LUT 测试族零改全绿」因此保住。
- Alcedo 自身 working space（acescc）即单位域，其 `HasUnitDomain` 条款对其默认对从不触发——我方 HDR 域表格为既有交付面，字节保持优先是 OQ-1① 的正当推论，非另立裁决。**与 Alcedo 的偏离已登记（DECISIONS §2），语义空洞无非默认对非单位域档（仍走烘焙过源 domain 采样，M5② 语义保持）。**

### §4 全链 golden 门结构收窄 —— **裁定成立（不降门，实测修正）**

- KD-6 烘焙层 voxel 门（复合表 vs Float64 CPU 参考 p99.9 ≤1e-5）**原样保留**且亲跑绿；方向探针三件（checker E1）**原样交付**。被收窄的只是 T5 AC 字面「补标后渲染 = CPU 参考 ±1e-5」——按字面 = GPU 渲染 == 源表全链 Float64。
- 该字面在 KD-3 自定设计（复合 voxel 单位域枚举、尺寸=源表 ≈65³）下数学不可达：渲染采样的是复合晶格插值，胶片曲线解码到线性 working 域的晶格插值地板 ~8e-3（独立实测见 §4.4，与申报 0.0087/0.0068 同量级）。即使 Alcedo 自家 65³ `kLmtCompositeEdge` 渲染也存在同地板——非实现缺陷，是表驱动烘焙的物理属性。
- 替入的忠实渲染门（GPU == 复合表自身四面体插值 ±1.5/1024）与既有 `testNonIdentityTableWithRealMatrices` 同型同门，正确性语义由「voxel 级 1e-5（烘焙数学）+ 探针（方向）+ 同表门（管线忠实）」三件完整承载——正确性锚未放松，放松的只是物理上不可达的端到端字面。推翻字面需升复合分辨率（违 M5① 偏离注记）或 CPU 采样臂（零新 kernel 精神）——DECISIONS §4 已如实注明代价与晨审推翻通道。**判定：实测修正，非门槛放水。**

## 六、hash 零漂移红线

- `testParamsEncodingZeroDrift`：`ParamsCoding.encode(Params())` == `{"colorspace":"sRGB","interpolation":"tetrahedral"}` 逐字节 + StableHash 相等——nil optional 经 synthesized `encodeIfPresent` 缺席（自定义 `init(from:)` 只换 decode 腿，encode 腿 synthesized 语义不变，CodingKeys 显式列举）——机制亲核成立。
- 容错 decode 三态（缺键 nil / 未知 rawValue `try?` degrade nil / 合法对精确）`testParamsDecodeTolerant` 钉死，旧档读新档反向兼容不抛入 sidecar loader。
- 无记忆档 registry 字节零漂移：`RememberedEncodings` 单 struct 原子对 + additive optional（M2-5 `relativePath` 先例同款），`testRegistryJSONZeroDriftWithoutMemory` 钉 JSON 键级。
- 旧 sidecar 渲染逐字节：快路径 verbatim（`testNonUnitDomainDefaultPairStaysVerbatim` + fast-path bakeCount==0）+ 既有 HDR storage/恒等族零改全绿（IOPParity 全量亲跑）——AC3 三通道全闭合。

## 七、环境注记（验收执行如实申报）

- 验收中段（IOPParity 全量亲跑完成后）本会话 shell spawn 通道持续故障（`spawn /bin/zsh ENOENT`，50+ 次重试贯穿验收后半程未恢复，非仓库/工程问题）。受影响项：
  1. **Library 587/4/0 与 App 635/0/0 两 bundle 全量亲跑未完成**——两族（LutLibraryStoreTests 16 / LutEncodingPanelTests 5）源码级逐法读码核验已完成（§三 AC5/AC6），执行方亲跑数字以 SUMMARY §四为准；ACCEPTANCE §八留补录槽。
  2. §4.4 晶格地板独立实测脚本就绪未跑（结构论证已独立支撑 §4 裁定，见该节）。
- 上列两项不影响 PASS 判定主体：IOPParity 全量轮已亲跑覆盖 31/37 新测试（Lut3dEncodingTests.swift 24 + FullChain 2 + 既有 LUT 族零改全绿），余 6+5 为 Store/面板面且逐法对题 + 三方登记闭环 + adoption/stateLock 语义亲核；如实留痕供晨审复核（可令下一轮补跑或径行追认）。
- **commit 状态**：验收批增量（本文件 + GOAL-STATE 验收续接点）因 shell 故障**未 commit 未 push**，工作区在案（`.work/` 真路径），待 patrol/晨审收口（`git status` 可见两文件新增/修改）。

## 八、验收批增量与本报告补录槽

- 本 ACCEPTANCE 落盘 + GOAL-STATE 验收续接点行（验收批惯例，不 push）。
- **补录槽（shell 恢复后下一轮执行）**：①Library/App 两 bundle 亲跑行（对表 587/4/0、635/0/0）；②§4.4 晶格地板实测值回填（脚本 `/tmp/m31_lattice_floor.py` 就绪，`uv run --with numpy python3` 直跑）。
