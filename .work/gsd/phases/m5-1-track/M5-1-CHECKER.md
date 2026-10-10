# M5-1 CHECKER — TRACK 追色族三 plan 从严审查（2026-10-11）

> Checker = ZCode subagent（从严档）。输入 = `M5-1-0{1,2,3}-PLAN.md` + `M5-1-CONTEXT.md`
> （含用户回批 2026-10-11 八项生效值）+ `RESEARCH-NOTES.md` 九节 + `.work/config.toml`
> `[gsd]`（dual_acceptance = true 亲读）。全部源码锚 HEAD 亲核（`71d0648`）。
> 结论头：**FAIL / 7 error + 7 minor**——修复处方逐条在案；E1（S1 数学公式）为灵魂级
> 缺陷，必须在执行前改 plan 正本，不允许 executor 现场自救。

---

## 结论

**FAIL / 7 error + 7 minor**

- 三 plan 的**结构面、裁决映射、先例锚定、红线纪律、dual_acceptance 编排**总体扎实
  （亲证清单见 §5）；八项生效值到 AC 的分账无遗漏（§2）。
- 但 **E1 = S1 Gaussian OT 闭式公式数学错误**（KD-3 合成式不满足 OT 定义约束、与自身
  「S3 = S1 关协方差特例」主张矛盾、与 RESEARCH §1.2 正确形式相悖）——这是本 phase
  全部数学的地基，G3 恢复门按此公式写必炸或假绿。
- E2/E3 = **两批未申报的既有测试钉死面**（IopCatalog 18-pin 族 + 19-tool 冻结快照族），
  照单执行会在各 plan 自身的定向轮里翻红，且 P1 有一个 AC（add 菜单可见）会静默落空。
- 修复批 = 改三份 PLAN（file:line 级）+ 补申报文件；不触 CONTEXT/RESEARCH 正文
  （RESEARCH §1.2 本来就是对的形式）。

---

## 1. 裁决一致性（八项生效值 → AC 映射）

| 生效值 | P1 | P2 | P3 | 判定 |
|---|---|---|---|---|
| ① 三档全交付（S1/S2/S3，Sinkhorn 否） | S1+S3（AC1） | S2（AC1） | solver enum 三值 | ✅ 分账完整 |
| ② 统计域 Oklab / 应用域恒等直出 | AC2 | AC2（bake 域） | — | ✅ |
| ③ 独立 op + 线性臂 params 直存 / LUT 臂 .cube 资产不进 paramsData | AC3（线性臂半） | AC3（.cube 半 + paramsData 上界断言） | attach 返回面 | ✅（但见 m4/E2 目录面） |
| ④ 65³ + 1%/99% 截尾 + 平台面 / 矩阵臂全定义域 | AC4（截尾+矩阵臂半） | AC4（65³+平台面半） | — | ✅ |
| ⑤ 多参考统计级加权矩池化 | — | AC5（公式逐字对裁决） | KD-1 fan-out 消费池化 | ✅（公式亲验正确，§3.3） |
| ⑥ match_color 最小面（微调/验收/元数据走既有三工具） | — | — | AC1 + 零新面机检 | ✅（但见 E6/m6） |
| ⑦ grade 层蒙版自动可用 + 参考侧全图 | AC5（AC 序号 5） | AC6 | — | ✅（但见 E2：add 菜单落空风险） |
| ⑧ 五门 | G1/G2/G3/G5 | G 门扩展 + G3 目测走查 | G4 + 台账收口 | ✅ 五波落位完备、GATE-LEDGER 为 VALIDATION 输入件 |

八项裁决在 CONTEXT「裁决记录（用户回批 2026-10-11）」逐条可溯；三 plan 的
「已定裁决（生效值，硬约束）」节均正确引用且未重开。**此项 PASS。**

---

## 2. Error（7 项，逐条带处方）

### E1（P1 KD-3，灵魂级）：S1 Gaussian OT 闭式公式数学错误

P1 KD-3 原文：`M = Σt^{1/2} · A · Σs^{−1/2}`，`A = (Σs^{−1/2} Σt Σs^{−1/2})^{1/2}`。

**三重证伪**：
1. **定义约束不满足**：OT 映射须 `M Σs Mᵀ = Σt`。对角情形代入得
   `M = diag(tᵢ/sᵢ)` → `MΣsM = diag(tᵢ²/sᵢ) ≠ Σt`。
2. **对角归约错误**：高斯 OT 的正确对角形 = `diag(√(tᵢ/sᵢ))`（标准差比）。plan 公式
   给方差比（平方量级、过冲一倍）。
3. **与自身主张矛盾**：KD-3 同时声称「S3 = diag(σt/σs) 是 S1 关协方差特例」——按
   plan 公式 S1 对角 = diag((σt/σs)²) ≠ S3，特例关系断裂；且与 `RESEARCH-NOTES.md`
   §1.2 的正确形式（`M = Σt^{1/2}·U·Σs^{−1/2}`，**U = SVD 极因子**，对角下 U = I →
   归约正确）相悖——plan 把「极因子 U」偷换成了「SPD 矩阵平方根 A」仍套进极因子
   三明治，双重计了平方根。

**处方**：KD-3 改为两者之一（等价）：
- `M = (Σs^{−1/2} Σt Σs^{−1/2})^{1/2}`（A 单独即全式，无外层三明治）；或
- `M = Σt^{1/2} · U · Σs^{−1/2}`，U = `Σt^{1/2}Σs^{−1/2}` 极因子（一次 SVD，RESEARCH
  §1.2 原形）。
并在 T4 golden 补两条结构断言：①**定义约束断言** `M·Σs·Mᵀ ≈ Σt`（≤容差入
DECISIONS）；②**S1 对角 ≡ S3 断言**（Σs/Σt 取对角矩阵，两求解器输出逐位或 ≤1e-6
同值）——此断言同时防未来回归。SPD 平方根唯一性/Jacobi 阶梯/ε 正则/秩亏回落 S3
的其余设计**保留不动**（该部分亲验正确）。

### E2（P1，未申报文件簇）：IopCatalog/add-face 既有钉死面 5 文件缺失申报

P1 T5 加 colormatch 的 IopCatalog 行 + GradeCatalog 第 20 行后，以下既有断言**全部翻红**，
但 `files_modified` 均未申报：

| 文件 | 钉死点（HEAD 亲核） | 后果 |
|---|---|---|
| `App/Sources/Lightamer/State/EditorState.swift` | `templateInstance(for:)` 穷举 switch `default: nil`（≈:933-985）——add-face 枚举 `gradeScopeEntries()` 经 `compactMap` 静默丢行 | **不补 case 则 add 菜单不出现 colormatch → AC9/「生产行为唯一可见变化」静默落空**（编译不报错，最阴险） |
| `Tests/LightamerTests/CatalogAddFaceTests.swift` | `testGradeScopeAddFaceEnumeratesTheCatalogMatrix`（:226-248）钉死 13 catalog id 精确列表 + 模板 paramsData == identityJSON 逐字节 | 加行即红；列表须 +`"colormatch"` |
| `Tests/LightamerTests/McpEditingToolsetTests.swift` | `:476 checked == 18` + `:490 ops.count == 18`（反射 guard 收口钉数） | 19 即红 |
| `Tests/LightamerTests/DefaultFaceTests.swift` | `:365 IopCatalog.ops.count == 18` | 19 即红（IOP bundle——与 E7 叠加，定向轮还看不见） |
| `Tests/LightamerTests/McpHostTests.swift` | `expectedListIopsText()`（:723 起）= 18-op 规范 list_iops 文本，三宿主形态一致性比对 | 目录 +1 行文本变即红 |

**处方**：P1 `files_modified` 补上述 5 文件 + T5 验收面加两条：①templateInstance 补
`case ColormatchModule.opName`（Params() 模板，与 identityJSON 同字节——filmPlacement
先例同形注释）；②CatalogAddFaceTests 精确列表更新（13→14）+ DECISIONS 记 unique-op
计数演变。**附带钉死面决策**（同批 DECISIONS）：colormatch Params 的 optional 字段
（sourceStatsHash/referenceStatsHash/effectiveSolver）入目录则反射 guard 比的是「默认
编码键集」——`encodeIfPresent` nil 缺席时目录含它反而 guard 红、不含则 apply_params
按「cataloged op 未知键拒绝」拒设。二选一并记 DECISIONS：**推荐 optional 字段显式
编码（nil → null）进目录**（agent 至少看得见键；P3 attach=false 参数组可回灌，联动 m4）。

### E3（P3，未申报文件簇）：19-tool 冻结快照族 5 文件缺失申报

match_color = MCP 第 20 个工具，以下**冻结计数/逐字快照断言**全部翻红，`files_modified`
均未申报：

- `Tests/LightamerTests/McpRegistrySnapshotTests.swift:186`（`names.count == 19`，
  security face 注记「adding/removing/changing a tool …asserted VERBATIM」）
- `Tests/LightamerTests/McpLauncherTests.swift:200`（`names.count == 19`）
- `Tests/LightamerTests/McpHostTests.swift:242、:694`（19-tool face ×2）
- `Tests/LightamerTests/McpFinalSnapshotTests.swift:165、:193`（**frozen 19-tool 表逐字
  断言**——match_color 的 descriptor/inputSchema 须入该表）

**处方**：P3 `files_modified` 补 4 文件（McpRegistrySnapshotTests/McpLauncherTests/
McpHostTests/McpFinalSnapshotTests），T1 验收面加「快照族 19→20 全量更新 + match_color
descriptor 入 McpFinalSnapshotTests 冻结表」；`McpRenderParityTests.swift:564` 亲核为
注释级引用，不动。工具名快照属 security face——更新必须显式而非 executor 顺手改数。

### E4（P1 KD-2）：statsHash「直方图即分布的充分统计面」对矩族求解器为假命题

KD-2 钉死 statsHash 覆盖 = 直方图计数 + sampleCount（矩不入哈希）。但 S1/S3 的 μ/Σ
按 KD-2 自身规则**从原始样本 Float64 累积**（子 bin 精度），不是直方图的函数——两组
不同样本集可有逐字节相同的 256-bin 直方图而矩不同。后果：求解缓存键
`fnv(srcStatsHash ⊕ refStatsHash ⊕ solverTag)` 在此类碰撞下**返回他解**（确定性系统
的正确性洞，概率低但违反本项目 bit-identity 教义）；statsHash 同时是 params 持久身份
与重解漂移判据，同样受染。

**处方**：statsHash 折叠面改为「直方图计数 + sampleCount + **μ/Σ Float32 位模式 +
支撑域界**」（FNV 规范序不变，FilmPrintBake/FilmStatsSeam 体例）；「充分统计面」措辞
从 KD-2 摘除，改为「直方图（S2 的完全输入）+ 矩位模式（S1/S3 的完全输入）」。
T2 的「字段敏感（改一计数翻哈希）」验收相应加「改一矩位翻哈希」。

### E5（P2 KD-6）：源统计平面未钉死 → 重解反馈回路

KD-6 源统计 = 「PREVIEW 完成面 readback」（活编辑器 PREVIEW = 含当前全部编辑的渲染）。
参考侧显式 pristine（THUMBNAIL pristine 渲染），**源侧无 pristine/前置平面限定**：
首次求解时 colormatch 实例尚不存在 → 无污染；但 **Solve 重解缝**（P2 T6/KD-6 + P1
缓存 invalidateAll 消费点）在实例已激活时，源统计包含 colormatch 自身输出 →
统计≈参考 → 新解 ≈ 恒等 → 再按一次 Solve 效果向恒等塌缩（用户可见行为缺陷，
非理论角案）。

**处方**：KD-6 钉死源统计平面 = **colormatch 实例输入平面**（统计提取期间旁路
colormatch 实例，或取实例入点 tap——照 FilmStatsSeam 的 PREVIEW 完成点 tap 体例，
提取适配器声明 bypass 集）；T6 验收加「solve-twice 稳定断言：上游不变时重解产物与
首解逐字节同」（入 G1 全链）。

### E6（P3 KD-1/红线）：非打开目标图的批量面机制缺口 + 「零新提取路径」红线自相矛盾

OQ-6 裁决字面含 `targets` 数组批量（逐目标独立求解）。P2 ColorMatchService 的提取面
绑定**活编辑器 PREVIEW 完成点**（GUI 会话态）；MCP 会话可全无头（Phase 14 测试即
无头 store 面），非打开目标图既无 PREVIEW 完成点也无 GUI attach 面。P3 红线又写
「源统计/参考统计提取 = M5-1-02 ColorMatchService 既有面复用，**零新提取路径**」——
照 P2 现文案，批量目标语义与该红线不可同时成立。

**处方**（二选一，两 plan 同批改）：
- **推荐**：P2 KD-6 把 ColorMatchService 提取面定义为**管线级 API**
  （`extractStats(document:bucket:)` = in-pipe 无头渲染到 PREVIEW/THUMBNAIL 桶 +
  readback + P1 纯函数；GUI 侧 PREVIEW 完成点只是其一个调用点）——P3 红线照旧成立；
  attach 走 store 级实例投影（apply_params `projectInstances` 同缝，非 GUI
  addAdjustmentLayer）。P2 T6/P3 T1 各补一条无头提取验收。
- 或：P3 v1 targets 收窄为「当前图 + 已打开会话图」并在工具 doc 声明——但这是对
  OQ-6 裁决字面的收窄，须 DECISIONS 显式申报不得静默。

### E7（P1 T9）：验收定向轮 bundle 集漏 IOP

front-matter `test_bundles: [LAYERS, IOP, IOPParity, APP]`，且 T8 声称「定向轮
IOP/IOPParity 全量逐位基线零漂移」，但 **T9 验收只跑 `--bundle LAYERS/IOPParity/APP`**。
而本 plan 修改的 `V50OrderTests.swift`（106→107）按 BUNDLE-MAP 属 **IOP bundle**
（M2-4-0-BUNDLE-MAP.txt:189），DefaultFaceTests（E2 波及）亦在 IOP（:131）——照 T9
清单，**本 plan 自己改的计数断言在验收轮根本不会跑**，漂移藏到 M5-1-03 收口轮才炸。

**处方**：T9 定向轮改 `--bundle LAYERS/IOP/IOPParity/APP`；T8 与 T9 的 bundle 口径
对齐。

---

## 3. 数学审计细则（E1 外的其余项）

- **S3 Reinhard 对角**：`M = diag(σtᵢ/σsᵢ)` + ε 地板 + 同式 offset ✅（= 对角 OT 正形；
  E1 修复后 S1 特例关系成立）。
- **strength 语义**：`out = (1−α)x + α(M(x−μs)+μt)`，Oklab 域，α 不入解 ✅。KD-6 的
  α-lerp 展开 `x + α((M−I)x + (μt−Mμs))` 代数亲验正确 ✅；`c = μt−Mμs` 与 α 无关、
  uniform 携 M−I + c + α 共 13 floats ✅（「乘加 6 次」计数措辞松，不 load-bearing）。
- **池化公式（OQ-5）**：`Σ_pool = Σ wᵢΣᵢ + Σ wᵢ(μᵢ−μ_pool)(μᵢ−μ_pool)ᵀ` = 全协方差
  公式（law of total covariance）亲验正确 ✅；直方图 `round(Σ wᵢhᵢ)` + 固定序求和 +
  归一化入口 + N=1 恒退化 ✅；按 referenceStatsHash 升序规范化——同哈希重复参考互
  相加可交换 ✅（值相同，序无关成立）。
- **S2 CDF 分位对齐**：src 累积占比 p → ref 域首达 bin → 阶梯曲线，整数秩无插值、
  端平台、同分布→恒等曲线 ✅；曲线不持久化（重解闭合）✅。
- **Oklab 变换**：公开解析式自写 + 常数来源注释单源 + Float32/Float64 孪生 + 往返门
  ✅。但 **m1**：Ottosson 公开 M1 是 linear-sRGB→LMS；working 域是 linear Rec2020，
  plan 未写明组合链（M1·M(2020→sRGB) 或 XYZ 路）；且 Rec2020 色域角/管线负值可产生
  负 LMS——`pow(neg, 1/3) = NaN`，MSL 侧必须符号保持 cbrt（CPU 侧 T1 已有负分量
  断言，MSL 镜像未申明）。处方：KD-1 补组合链常数 + MSL 符号保持 cbrt 注记，G2
  驱动集加负值/超域探针（HDR 直通断言已有，负值路径补）。
- **Jacobi/SPD 平方根唯一性**：主平方根值唯一 + 固定扫描序阶梯 → bit-identity 可达 ✅；
  ε = 1e-12·trace + 秩亏门 1e-9·trace → S3 回落确定 ✅；「同矩阵不同特征基路径同根」
  断言（T3）✅。
- **G2 parity 带**：p99.9 ≤1e-5 目标 + 实测收窄钉门 + L048 + 「kernel 展开式与 CPU
  参考逐项同步（防同值异式假 parity）」✅——最后这条是 M3-3 教训的正确转写。
- **65³ bake/体素门/平台面**：FilmPrintBake 亲核（level 65 / Float64 /
  concurrentPerform 晶格切片 / LRU 16 / 双 bake BIT-IDENTICAL 先例注记）与 P2 KD-3
  同构 ✅；α 折入 bake + bakeKey 含 α 位模式 + 资产 commit 才落盘 ✅；超预算降级路径
  显式申报 ✅。

---

## 4. Minor（7 项，带处方）

- **m1**（P1）：Oklab Rec2020 组合链 + MSL 负 LMS 符号保持未申明（详见 §3 末条）。
- **m2**（P1）：KD-3「`effectiveSolver = .reinhardFallback` 记录」与 KD-5
  「`ColorMatchSolverKind` 枚举本轮两值」矛盾（`.reinhardFallback` 非 case）。处方：
  二选一钉死（推荐 effectiveSolver 记 `.reinhard` + DECISIONS 注记回落语义；或 P1 就
  三值枚举并同步改 KD-5 文案）。
- **m3**（P1）：红线自证清单列了 `NodeGraphCommand` 零触碰，但 T9 的 `git diff`
  路径集未含其所在目录——零 diff 自证覆盖面与红线清单对齐（补路径或注明该面本批
  无文件路径级断言）。
- **m4**（P2/P3 联动）：`attach=false` + solver=cdf 时返回的参数组含 `assetRef`——
  colormatch 若入目录（E2），apply_params 对 cataloged op 未知键拒绝 → agent 回灌被
  拒。处方：与 E2 的 optional 编码决策同批落（显式 null 编码进目录后此路自通）；
  P3 T1 加「attach=false 参数组经 apply_params 回灌成功」一条端到端断言（KD-2 的
  apply_params 闭环只测了 strength 微调）。
- **m5**（P2）：`.cube` 「最短往返表示法序列化」须钉死具体格式器（Swift `String(Float)`
  最短往返 + locale 不变——小数点恒 `.`）+ 读回端为 colormatch 自有 reader
  （CubeLutParser 零触碰红线正确，写读自洽即可）；KD-4 补一句钉死。
- **m6**（P3）：`reference` = 「库内 image id 或路径（load_image 语义同源）」——
  load_image 实为 relPath 解析；**id → URL** 的解析缝（库查询走哪条 seam）未指名。
  处方：KD-1 钉死 id 解析机制（或 v1 收窄为仅路径 + DECISIONS 申报）。
- **m7**（P3）：REQUIREMENTS TRACK-03 原文含「**内嵌 LUT** + tetrahedral 插值 kernel」，
  裁决生效值 = `.cube` 派生资产（OQ-3 显式推翻内嵌）。KD-4 翻账处方补一句：勾选
  注记**显式记录该偏差**（「内嵌 → 派生资产，OQ-M5-1-3 裁决 2026-10-11」），防
  VALIDATION 期对表困惑。

---

## 5. 亲核锚记录（全部 HEAD `71d0648` 实证，非凭 plan 转述）

| 锚 | 亲核结果 |
|---|---|
| V50Order 36.5 空隙 | ✅ `lut3d 36.0`（:166）与 dt verbatim `colortransfer 37.0`/`colormapping 38.0`（:110-111）之间无 36.x 占位；表头 add-only 纪律注记在位 |
| V50OrderTests 106 | ✅ `entries.count == 106`（:20 消息串）；106→107 申报正确 |
| colortransfer/colormapping 未注册 | ✅ Registry register 清单（46 处）无此二 op——P1「verbatim 行零触碰、保持未注册」与现状一致 |
| Registry seed ABSENT | ✅ filmPlacement（:107-117）/CAT02（:118-124）两先例注记在位；colormatch seed ABSENT 同形可行 |
| GradeCatalog 行数 | ✅ 现存 **19 行**（「The 19 catalogs」:169 + items 数遍历），colormatch = 第 20 行正确；GradeCatalogTests `:37/:48 count==19` 双断言（P1 已申报该文件 ✅） |
| Lut3dModule 适配面 | ✅ iopOrder 36.0 / flags [.supportsBlending,.allowTiling]（:107-109）/ `init(device:resolver:)`（:344）/ 表纹理 **rgba32Float**（:485）/ lutName nil → makeRoutedCommandBuffer blit（:368,:630）——P1 孪生声明与 P2 resolver 注入缝全部可行 |
| `lut3d_tetrahedral` 签名复用可行性 | ✅ `(in, out, clut:texture3d<read>, constant Lut3dUniforms&, gid)`；`Lut3dUniforms.fwd[9]/inv[9]` 恒等矩阵 + domain 0..1 + level 65 即纯表采样——**P2 KD-5 的 identity-uniform 适配路径亲证可行**，uniform 盒子在 colormatch 侧、kernel 文件零 diff 可达；「不可适配停手上报」条款保留为保险 |
| FilmSolveCache LRU 8 | ✅ FilmTailPolicy.swift:419-453（NSLock + 插入序 LRU 8 + 小端 fnv 折叠键 + `shared`）——P1 缓存同构声明成立 |
| FilmStatsSeam 整数秩 | ✅ :391-401（256-bin×4 通道 + statsHash FNV-1a 字节面）；:528 整数秩分位——P1 引用行窗 :380-500 基本准 |
| FilmPrintBake | ✅ 65³/Float64/concurrentPerform/LRU 16/双 bake BIT-IDENTICAL 头注全文在位 |
| EditingToolset.register | ✅ :132 `static func register(into:seams:) async`——P3 一行 diff 结构成立；apply_params upsert（:431 起 + `overlayParams` :696 模块 Codable 解码校验）；render gate `withRenderGate`（:394） |
| IopCatalog guard | ✅ 手写表 + 「catalogKeys == 默认编码键集 + version/iopOrder pin」双断言（McpEditingToolsetTests:452-477）——E2 的依据 |
| 19-tool 冻结面 | ✅ McpRegistrySnapshotTests:186 / McpLauncherTests:200 / McpHostTests:242,:694 / McpFinalSnapshotTests:165,:193 ——E3 的依据 |
| Phase 14 SC#3 | ✅ 14-2-SUMMARY（载入→apply→render_preview 与本地渲染字节级一致→双宿主）——G4 同型引用成立 |
| MCP-09 研究项 C | ✅ REQUIREMENTS:619（match_color 工具位 + 签名预留 + 依赖 TRACK colormatch） |
| PanelPresentation | ✅ `App/Sources/Lightamer/UI/PanelPresentation.swift` 在位；P2 L057 runModal 禁令机检入 T9 ✅ |
| FilmPanelModel 孪生源 | ✅ `App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift`；ColorMatchPanel* 同目录落位正确 |
| RasterMaskStore | ✅ `.lra.masks/` 兄弟目录惯例（:44-48）+ `LoadResult.degraded(reason)`（:39-41）——P2 `.lra.colormatch/` + degrade 值形态孪生成立 |
| add-face 枚举 | ✅ `EditorState.addFaceEntries`/`gradeScopeEntries`/`templateInstance`（穷举 switch default nil）+ CatalogAddFaceTests 精确列表——**E2 的核心依据** |
| BackgroundTaskHosting | ✅ `App/Sources/Lightamer/Library/BackgroundTaskHosting.swift` |
| 测试基线链 | ✅ 3335/16/0（M4-1-VALIDATION `TOTAL|3335/16/0|1604s` 亲证）→ M4-3 +31（M4-3-VALIDATION:21-35 双路 grep 亲数）→ 3366 推算未跑 `--all`——P1 基线段陈述逐位属实 |
| dual_acceptance | ✅ config.toml `[gsd] dual_acceptance = true` + 三 plan 收口任务均写明「zcode PASS → 串行 omp 二次验收（严禁并发）+ 结论落 ACCEPTANCE.md」——编排合规 |
| 测试增量对账 | ✅ 34..42 + 38..48 + 10..16 = +82..106，与任务书一致；P2/P3 基线「P1 验收后实测值」滚动口径正确 |

---

## 6. 体例对表（m4-1/m3-3 正本）

front-matter 七件（phase/plan/title/wave/depends_on/autonomous/requirements/
estimated_tests/test_bundles/files_modified）齐整；read_first 带行窗；纪律节
（L041 tuist 尾闸 / L014 fence / L048 比较域 / E2 BUNDLE-MAP 同 commit / 资源监控 /
中文标注）三 plan 一致；AC 总表 ↔ 任务序 ↔ 【T#】标注齐；提交约定全英文 Conventional
Commits 不 push ✅。G3 自然样张目测挂 gui-acceptance Manual-Only（OQ-8 备选 A 默认
形态）与 M3-4 先例同形 ✅。

---

## 7. 修复批验收清单（orchestrator 回注用）

1. [ ] P1 KD-3 公式改写（E1）+ T4 加定义约束断言 + S1 对角≡S3 断言。
2. [ ] P1 files_modified 补 5 文件（E2）+ templateInstance case + CatalogAddFaceTests
       列表更新 + optional 字段编码决策 DECISIONS 化。
3. [ ] P1 KD-2 statsHash 折叠面扩矩位模式（E4）+ T2 断言同步。
4. [ ] P1 T9 定向轮补 IOP bundle（E7）+ T8/T9 口径对齐。
5. [ ] P2 KD-6 源统计平面钉死 colormatch 输入平面 + solve-twice 稳定断言（E5）。
6. [ ] P2/P3 批量目标提取面管线级化或显式收窄申报（E6，二选一）。
7. [ ] P3 files_modified 补 4 快照测试文件 + 冻结表更新（E3）+ attach=false 回灌断言（m4）。
8. [ ] m1/m2/m3/m5/m6/m7 按 §4 处方落 KD 文案。

全部落毕重提 checker 复核（本轮 FAIL 不阻塞 P1 修复批先行——E1/E2/E4/E7 全在 P1，
可先行改版后再复核 P2/P3 联动项）。
