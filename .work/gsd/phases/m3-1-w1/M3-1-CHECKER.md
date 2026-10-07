# M3-1 W1 checker 报告（执行前质量门）

> checker：ZCode subagent，2026-10-08。对象 = `M3-1-01/02/03-PLAN.md`（9ca0920）+ 交叉锚
> （CONTEXT 裁决记录 / RESEARCH-NOTES / ROADMAP §M3 / REQUIREMENTS :278/:392 / M2-9 与
> M2-11 正本 / m2-5 增量）。源码断言全部亲核（我方 HEAD `9ca0920` + Alcedo `f1fae5d`）。
> 裁决记录（七项生效值）逐条对 AC；40 张补标例外核验 = generation-log.json 全 40 行
> input AWG4 / output Rec.709 Gamma 2.4 零例外（「逐条断言」成立）。

## 结论

**FAIL / 3 error + 7 minor**（均在 M3-1-01；02 一 minor；03 一 minor。修复处方见各条，
修后无需全量 recheck，按条复核即可）。

---

## Error（派发前必修）

### E1 — 01 KD-3/KD-6 + CONTEXT D-3：复合烘焙方向命名与 Alcedo 正本相反

- **亲核**：Alcedo `lut_bake.cpp:273`（`Compose`）=
  `LutOutputToAcescc(SampleLutTable(source, AcesccToLutInput(node)))`：
  - 输入臂 `AcesccToLutInput`（:246-260）= working 解码→gamut 矩阵（AP1→input gamut）
    → **`CeEncode`/`DisplayEncode`**（把 working 值**编码**进 LUT 的 input encoding 作为
    采样位）；
  - 输出臂 `LutOutputToAcescc`（:262-279）= **`CeDecode`/`DisplayDecode`**（把源表结果从
    output encoding **解码**回光）→ gamut 矩阵→编码回 working。
- plan KD-3/CONTEXT D-3/RESEARCH §1.3 写作「`inputDecode(voxel) → 源表采样 →
  outputEncode`」——两臂命名**双双颠倒**（input 臂实为 Encode、output 臂实为 Decode）。
  执行者按 plan 字面实现 = 烘出方向相反的复合表；而 KD-6 的「复合表 vs Float64 CPU 参考」
  属自参照对照（CPU 参考若同误解则同错同绿），**现有 AC 抓不住**。
- **处方**：KD-3 钉死方向，用 Alcedo 函数名 + 具体算例（内置集对）：working voxel →
  M(Rec2020→AWG4) → LogC4 **encode** → 采样源表 → BT.1886 **decode** →
  M(Rec709→Rec2020) → 复合值。KD-6 增一条**方向探测 golden**：合成「log 域恒等表」
  （table[i]=i 的 LogC4 域表）+ 补标对 → 期望输出 = LogC4_encode∘BT1886_decode 闭式
  （与烘焙实现独立推导），倒置即红。同时写明中介换算适配（Alcedo 中介 = display light
  1.0=100 nits；`DrtEotfMath` = peak-normalized——薄适配 = ×peak/100 单一换算，KD-2
  落一处注记防双重换算）。

### E2 — 01 front-matter/纪律 3/T3 AC/T6：`LutLibraryStoreTests` bundle 归属错（IOP → Library）

- **亲核**：`Project.swift` — `LightamerTestsLibrary`（:493）sources 含
  `LutLibraryStoreTests.swift`（:531）；BUNDLE-MAP :301 = `LIB 10
  LutLibraryStoreTests.swift`；test-direct.sh BUNDLES = (IOP IOPParity Layers **Library**
  Sessions Export App)。
- plan 四处写 IOP：front-matter 文件注记「修改（IOP）」、front-matter
  `test_bundles: [IOP, IOPParity, App]`（缺 Library）、纪律 3「既有文件原地扩（IOP）」、
  T3 AC「`--bundle IOP LutLibraryStoreTests` 零改用例全绿」、T6「定向轮 IOP + IOPParity +
  App」（缺 Library）。`--bundle IOP LutLibraryStoreTests` = IOP bundle 内 0 命中——
  L041/L055 假绿家族正中靶心，T3 验收轮无意义。
- **处方**：五处 IOP→Library；test_bundles 与 T6 定向轮补 Library。

### E3 — 01 KD-5/OQ-4①：补标机制锚错——`seedBuiltIns` 不写 registry 行

- **亲核**：`LutLibraryStore.seedBuiltIns`（:474-501）= **static 纯文件拷贝**（bundle
  `LUTs/` → `root/BuiltIn/`，count+size 哨兵），**无 registry 访问**；registry 行由
  init→`rescan()`（:197）→`adopt()`（:262-285）构建。KD-5「`seedBuiltIns`（:474）对 40
  张的 registry 行写入 rememberedEncodings」按字面不可实现；「seeder 幂等（二次 seed 不
  覆写）」AC 载体随之落空。
- **处方**：补标落点改 adoption 路径——init seed 后（或 rescan 采纳 `BuiltIn/` 行时）对
  记忆对缺席的 `BuiltIn/` 行盖 `rememberedEncodings` 章（nil-guard 哨兵 = 用户对已保留），
  一次 `persistRegistry()` 收口。**必须同批处理 drift 再采纳**：文件漂移 → `adopt()` 重建
  行会抹掉记忆对——`BuiltIn/` 行再采纳后重盖章（用户对被External漂移清除的边角在
  DECISIONS 登记）。KD-5 措辞与 T3 AC 同步改。

---

## Minor

### M1 — 01 KD-1/标题/AC1：17 条分组计数不一致（scene 11 + display 6 ≠ 「scene log 10 + display 7」）
表内 `linear_rec2020` referral=scene（row 11），display 实为 6 行（rows 12-17）。标题、
AC1「scene 10 + display 7」与裁决引语（CONTEXT OQ-2① 把 linear 归 display 侧）三处口径
漂移。**处方**：统一为「scene 11（camera log 10 + linear working 1）+ display 6」，T4
面板测试分组断言写显式计数（scene 11 / display 6 / 总 17）。

### M2 — 01 KD-1 rows 7/9：F-Log/N-Log 的 gamut 数据源风险（FilmLG / N-Gamut 为无出处名）
Alcedo 目录（`fujifilm_flog_fgamut`→G::Rec2020、`nikon_nlog_rec2020`→G::Rec2020；注释
:135-137 引厂规格）与厂规格一致：**F-Gamut/N-Log 均复用 BT.2020 原色**。plan 写
「FilmLG」「N-Gamut」有诱导执行者自造 primaries 的风险（KD-2 Bradford 自算拿错输入）。
**处方**：rows 7/9 gamut 改「Rec2020 原色（F-Gamut/N-Log 厂规格复用 BT.2020 primaries）」，
gamut id 相应命名。

### M3 — 01 KD-1 SDR display 行 peak=0 与 Alcedo 行值 100 偏离
Alcedo `kEncodings`：rec709_bt1886/srgb/gamma22 + displayp3_srgb 全部 peak **100.0**（p3
gamma26 行 48）。我方写 0 = 引入「peak==0 → 不换算」特判分支，偏离「行集/字段形对表」
声明（peak=100 时 Alcedo 公式 to_peak=from_peak=1 自然恒等，零分支）。**处方**：四行
SDR 改 peak=100（推荐，真对表）；或保留 0 但把特判升入 DECISIONS 显式登记。现「风险」节
的说明保留。

### M4 — 01 KD-3：「既有 stateLock 式守护」措辞失准 + 守护范围裁定缺位
Lut3dModule **现无任何 stateLock**（08dd061 只给 ToneEqualModule 加了）；且其**存量**可变
引用态（uniformBuffer/clutTexture/resolvedDevice/committed + process :329-332 对共享
uniform buffer 的 per-run 盖章）与 L069 根因同型（同实例跨 run 并发 commitParams/process）。
**处方**：措辞改「新增 stateLock（08dd061 同款）」；DECISIONS 显式裁定守护范围——推荐
顺带覆盖 commitParams + process 盖章窗（本就要改 commitParams，边成本低、同族隐患消），
不扩则明确登记 defer。

### M5 — 01 KD-3：复合表尺寸/域三处含混（尺寸=源表尺寸 vs Alcedo 定长 65 单位域；uniforms 域；源表域映射）
Alcedo 复合表恒 `kLmtCompositeEdge=65` 单位域；plan 改「尺寸=源表尺寸」可行但属偏离
（DECISIONS 应记偏离+理由）；「复合表域=单位域；uniforms 域随表」对照现状代码有歧义：
现 uniforms.domain* = 源表 domainMin/Max（Lut3dModule :186-193），烘焙臂必须**覆写为单位
域**；且源表非单位域时 CPU 采样须过源表 domain 映射（对表 Alcedo `SampleLutTable`，
CompositeKey 含 domain 即此因）。**处方**：KD-3 增一枚 bullet：复合体素在单位域枚举
（尺寸=源表尺寸，DECISIONS 记偏离）；源表采样过源域映射；烘焙臂 uniforms 域=单位域。

### M6 — 03 KD-3/AC3：「FULL 桶零变化」与风险节自相矛盾 + 旁路键控面
若旁路 = 改共享 live 投影实例，拖动窗内 FULL/导出渲染读到 bypassed 实例——AC3「FULL 桶
零变化」按字面不可测（风险节又明文接受该窗口）。**处方**：AC3 定义改「params/history/
旁路标志不进 FULL 判定面（拖动窗外 FULL 渲染逐字节不变）」，拖动窗内并发缺 denoise 归
DECISIONS 已登记风险；旁路键控 = **被拖实例身份**（非 opName 全局——layer 内嵌 nlmeans
不得被连带）。

### M7 — 02 KD-1：px 界移植的非对称后果未申报（height 上限 560 = 现默认高）
width 可长到 720（>默认 420），height 上限 560 = 现默认 ⇒ **高度只能缩不能增**（大屏上
先撞 px 帽）。KD-1 只要求对表出处注记。**处方**：KD-1/风险补一句显式裁定（高度帽=默认值
系有意——sheet 是控制面板；或改用仅比例域上限），防验收期扯皮。

---

## 观察项（不阻塞，不计数）

- **O-1** RESEARCH §3.5「`downgraded(57 passes) 26.5 ms`」：26.5ms 实为 29 趟档（perf.md
  表），「57 passes」是 perf.md :64 在案的标签滞后 bug——结论（引擎级无档达 16.6ms）不受
  扰；顺手指正即可，不改 plan。
- **O-2** `M2GRADE-08` 在 REQUIREMENTS :392 为无 checkbox 行（M2GRADE-01..07 均为
  `- [x] … Delivered` 形态）——01 T6 翻账需在该行**引入** checkbox+Delivered 形态，非
  「翻勾」。
- **O-3** 第三处动态键位 `ExportInspectorView.swift:369`（`"export_format_" +
  kind.rawValue` 串接形）＝M2-9-05 F-2 同族；当前键在册含 zh 值、`zh-audit --check` 现态
  PASS（实测 1505/1753 零红），用户可见面无伤——不入 V14 两处清算范围合理；V15 提取器
  硬化可选顺带覆盖串接形（规则 c 扩展），plan 未列不算缺。
- **O-4** 01 `estimated_tests: +10..14` 偏保守（曲线向量+烘焙三态+三层序+面板+golden 实际
  约 20+）；无害——对账以 BUNDLE-MAP 登记值为准（03 KD-5 禁凑数）。

## 已验证成立的关键断言（抽列）

- 七项裁决逐条有 AC 承载：OQ-1①→AC3+KD-3；OQ-2①→AC1（计数措辞 M1）；OQ-3①→AC4；
  OQ-4①→AC5 + T6「观感变化=修正非回归」交付注记在任务 action 内；OQ-5①→02 全 AC；
  OQ-6①→03 KD-3；OQ-7①→03 plan 结构。40 张补标零例外（generation-log 全查）。
- **hash 零漂移可测**：`ParamsCoding` sortedKeys（:17-26）+ synthesized
  `encodeIfPresent` nil 缺席；自定义 `init(from:)` 不影响 encode 合成——KD-3 论证成立，
  AC3 专测在。
- **DrtEotfMath 复用面属实**：`st2084EncodeY/DecodeY`（:110/:121，peak 形参 normalized
  域）、`hlgEncode/hlgDecode`（:149/:161，OOTF 在）、`powerEncode/powerDecode`
  （:172/:177，2.4/2.2 幂族；sRGB 分段确需新写——KD-2 归类正确）。全 public，文件零 diff
  可守。
- 面板/烘焙插点行号锚：`Lut3dModule` Params :53-72 / commitParams :139-217 / 矩阵消费
  :194；`LutLibraryStore` InstalledLut :52-80 / persistRegistry :287 / adopt :262；
  `LutPanelView`（a81483d 后）导入 Task hop :47 / 库树 :56-64 / colorspace Picker :66-71 /
  applyDiscrete :186-190；`YiyinTopBarSheet` :1216-1285、固定 frame :1273、AX 两枚在案；
  sheet 挂载 :201-204。
- 冲突档：`ExportState.enqueueExportM2` 形参 :472 默认 `.increment` **已就位**（03 KD-1
  「透传即接入」成立）；`testDefaultOverloadEqualsIncrementTier`（ExportCollisionPolicyTests
  :31，Export bundle）与 `testFailPolicyFailsQueueJobWithoutWriting`（ExportNamingE2ETests
  :366）在册；03 test_bundles [App, Export] 正确。
- peak-ICC：`M2-9-02-DECISIONS` §2（:41-45）边界正本属实；`isHdrEncoding` 单源在
  `DrtRecord.swift:456`；drtReadout :339-354 锚属实。
- denoise：`NLMeansPanelView` :14-15「exactly ONE history commit per drag」在案；四滑杆
  :32/:41/:54/:63 属实；`commitContinuousEdit`（PipeCoordinator 面）在 EditorState :168
  注记可循；perf.md :43-64 decimate 三档 revert 在案。
- zh：11 键（rating_1..5/color_0..5）**在册含 zh 值**实测确认；动态键位恰两处
  （LightamerApp :1490/:1518，ForEach 1...5 / 0..<6）；zh-audit.py form 1b 在头注 :15；
  现态 `--check` PASS。
- 波次/对账：01→02→03 串行链成立（共享写点 xcstrings/BUNDLE-MAP/Project.swift/
  GOAL-STATE/AGENTS 串行无冲突）；基线 2962 = 2961（M2-11-05 终验）+ 08dd061 +1
  （IOPParity 363=362+1 实锤）成立；03 全套 `--all` 报备制与 AGENTS 资源规则一致。
- 隔离前提：`a81483d`（LutPanelView Task hop 在场）+ `08dd061`（ToneEqual stateLock）均
  在 HEAD 祖先，01「基于 a81483d 后状态」成立；GOAL-STATE :11 修复批 owned 面已释放。

---

*checker：2026-10-08。3 error 全部集中在 M3-1-01（方向命名 / bundle 归属 / 补标机制锚）；
修复后按条复核，无需整轮 recheck。*
