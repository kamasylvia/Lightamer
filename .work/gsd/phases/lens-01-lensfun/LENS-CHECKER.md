# LENS-01 fixer 后 checker 复核（2026-10-20）

**结论：放行 / 0 residual + 3 note**

- 对象：`CONTEXT.md` + `LENS-01/02/03/04-PLAN.md`（fixer `4ce68882` 后
  HEAD）vs 评审正本 `LENS-PLAN-REVIEW.md`（`72e60114`）17 条处方。
- 方法：纯只读；fixer diff（5 文件 +304/−174）逐 hunk 对处方归因；B1/M6
  及 fixer 新事实主张逐条对照产线源码亲核；数字链 grep 机检。
- 判定：17 条全部按处方落地且可机检；fixer 零发明（无评审外新方案）；
  3 条 note 均为继承性/信息级，不阻塞 LENS-01 起跑。

---

## 1. 17 条逐条对账（全部 ✓）

**B1（blocking，处方①..⑤全落）**：
- ① T1 整体改写 = 复用既有字段 + 接线断言（LENS-01-PLAN :99-134）——
  「零产线 diff 为预期 + 防御补线例外申报」门在案；**禁新增字段声明**
  入 action 与回滚要求。
- ② 拼写/出处统一：X4 勘误段（CONTEXT :250-264）明写 `focalLength35mm`
  （:58）+ `lensMake`（:78）+ 主 EXIF dict `kCGImagePropertyExifLensMake`
  + aux 回落；T1 grep 门「`focalLengthIn35mm` 零命中——重名禁」
  （:127）；T3 测试行用既有字段拼写（:209）。
- ③ ΔN 下修链：T1 +2..4 → **+1..2**，plan +14..20 → **+13..18**，
  分账和 +60..90 → **+59..88**，终值带 4051..4081 → **4050..4079**
  （CONTEXT :54-58 勘误③注记 + 四 plan front-matter/ΔN 表/expected_all
  全链同步，见 §2）。
- ④ 勘误③入 CONTEXT §转写勘误（:347-356），RESEARCH §Auto-Detection
  EXIF 缺口段作废声明在案（沿勘误①「正文不返工」先例）。
- ⑤ files_modified：`CaptureMetadata.swift` 已撤出；`RAWDecoder.swift`
  保留但注记显式改属 T2 构造点赋值（M6 域）+「T1 零产线 diff——勘误③」
  （:20）——非 B1 残留。
- **源码亲核**：`CaptureMetadata.swift:58/:78` 两声明精确在位（:49-84
  追加尾段，源注释自证 08-2 声明 / 08-3 T2 walk 填充拆分）；
  `RAWDecoder.swift:550`（`kCGImagePropertyExifFocalLenIn35mmFilm`）/
  :564-577（主 EXIF dict 读入 :570 + aux 回落 :576-577 + **PLAN
  CORRECTION (D-08-3-T2-1)** 纠正注记原文在源）——plan 措辞与源逐点
  吻合，不再失实。

**M1+M2 组合（X3 钉死形态，三处一致）**：CONTEXT X3「写入点恰二处 =
auto-apply 命中 / browser 选型（含 detected 确认选型——同一 browser
缝）；Apply 已于 LENS-02 T4 退役」（:239-242）↔ LENS-02 T4 退役终形 +
detected 确认文案（action 4 + 验收「未确认不置 source」断言）↔ LENS-04
T1 bake 恰二处 grep 门 +「Apply 旧 action 零残留」——两 plan 间引用
零矛盾；detected 覆盖面属主 = LENS-02 T4 在 D-LENS-2/X6/已定裁决 6
四处同音；D-LENS-1「显式 Apply」退役前词汇已纠（:69-70）。

**M3**：LENS-04 T2 裁决表六→七项（SC :9 + action 2 :198-205 + 验收
:213），第七项含机理（snapshot nil 恒走 live resolve）与预期裁决
（缺陷修复原位收 + Re-match 提示；look-change 则 bump 全套）；LENS-01
风险节补 legacy `.lensfun` 档叙事并回指「归 LENS-04 T2 裁决表第七项」
（:331-334）——双向引用闭合。

**M4**：LENS-01 T4 memo 改缓存**匹配结果**（entry 身份 + score + 失败
状态），键 = 匹配输入 stableHash + DB 实例身份，显式「无 width/height
项」SC（:253-256）+ 跨尺寸同参命中测试（:251）；read_first 引
normScale/center 分辨率强相关面为依据——处方 (a) 完整采纳。

**M5**：LENS-03 T1 action 6 投影×auto-crop 接线 + golden 一例 + 验收
行（:129-132,:136-137,:144-145）；LENS-02 T3 采样语义注「投影侧折叠序
= LENS-03 T1 钉死」；LENS-04 T2 action 1 交叉收口核验（未折入 = 停回
L3 T1 补线，禁带缺口裁决）；CONTEXT 编排总纲 M5 交叉收口点（:38-40）
——四点闭环。

**M6**：X1/T2 改「构造点全 4 处」：RAW :236（内含 DNG/非 DNG 分支）/
:358 退役 decodeRaster 腿（**notApplicable 同步赋值**，不赋 = 禁 +
退役腿处置入 DECISIONS）/ RasterDecoder :121/:138；grep 门改「
`DecodedImage(` 构造点 4 处均带 `embeddedGeometry:` 实参」。**源码亲
数**：全仓 `DecodedImage(` 构造点恰 4 处（RAWDecoder:236/:358 +
RasterDecoder:121/:138），plan 拓扑与源完全一致。

**10 minors 全落**：m1 104 字节 stride 112（X5 + L2 红线；对照
`LensWarpUniforms` 源 4×SIMD4+4×SIMD2+SIMD2<Int32> = 104/对齐 16 →
112，数字正确）/ m2 strip-on-hash 机制 + 动机 + 防御性断言定位（X3
:243-247 + L4 T1/裁决 3）/ m3 LensfunDistributionTests 落 App bundle
（L3 四处一致）/ m4 BUNDLE-MAP 四 plan 全登记 + L2 补 AGENTS.md 行 /
m5 resolve crop 实参 = 相机 imageCrop 回归 + `crop: entry.cropfactor`
相悖实参零残留 grep 门（源亲核 :421-422 现状与 :193 注释自述相悖，处
方事实成立）/ m6 scale 施于映射后采样偏移 + 方向 golden 钉死 / m7
「并行排程但串行交错执行 + 相交文件清单」（CONTEXT + L3 头）/ m8
同笔转录注记 + 延后供件禁静默跳过维持（X8 + L4 T4）/ m9 perf 门带值
+ 绝对 ms + 相对倍率 + 禁「同阶」事后解释（L4 T5）/ m10 seek 式有界
读 + `RasterIccParser.tiffEmbeddedICCData` :320-360 先例亲核在位 +
Data 分片语义注明（L1 T2）。

## 2. 数字一致性（grep 机检）

- 全链同步：CONTEXT :54-58（+59..88 → 4050..4079 + 四分账）/ LENS-01
  front-matter :8、estimated_tests :10、expected_all :13（4004..4009）、
  ΔN 表 :61/:71 / LENS-02 +18..28 / LENS-03 +16..26 / LENS-04 :13
  expected_all「3991 + 59..88 = 4050..4079」——**分账和精确闭合**
  （13+18+16+12=59；18+28+26+16=88）。
- 旧值残留：`+60..90` / `4051..4081` / `+14..20` 仅存 CONTEXT §转写勘误
  ②③历史注记（显式「批时原值」框架）+ RESEARCH.md:153（上游正本，勘误
  ②已声明不返工）——合规。plan 面零 stale 值。
- 退役措辞零残留：「恰三处」「补两字段」「80-byte」全部仅存勘误/处方
  语境（「为退役前口径」「前提作废」「注释即错」）；「三腿」零命中。

## 3. 行内标记完整性

- 标记总量 84 处（75 行；任务书面 79 处为约数），17 条处方 ref 全在册
  （B1×4 / M1×4 / M2×9 / M3×4 / M4×7 / M5×7 / M6×9 / m1..m10 全覆盖）。
- 抽核 20+ 处标记与内容逐一一致（含 M2 属主、M4 memo、m5 实参回归、
  m6 采样语义、m7 清单、m8 独立性、m9 带值、m10 有界读）。
- **无标记改动扫描**：fixer diff 逐 hunk 归因——全部实质内容可溯源至
  评审处方文本或其证据段；新事实主张抽查（08-2/08-3 批次归属、
  D-08-3-T2-1 注记在源、:58/:78/:550/:563-577 坐标、:422/:193、
  :54-55 注释、104/112 算术、4 构造点、RasterIccParser 先例）全部对照
  源码属实。**零发明**。

## 4. 可执行性终判

- **B1 改写后 T1 仍闭环**：复用字段（零产线 diff 为预期态）→ 接线断言
  测试（合成 EXIF fixture 非 nil 正例 + 旧档零漂移负测）→ grep/diff
  --stat/定向 bundle 三重机检 + decodeParamsHash 核验结论二值落
  DECISIONS（未覆盖 = 停手上报，X2 边界不越）——验收标准全可机检。
- **M1/M2 组合跨 plan 一致**（§1）；红线 15 条自洽（恰一键在 L1 零触/
  L2 落地的分账、kernel 触碰预算 L2 一处 + L3 一处互恰、封存面清单
  含 LightamerSidecar 与 X3 快照骑 paramsData 相容）；晨审推翻点索引
  8 D + X1 在案且与各 D 条内嵌推翻点一致。
- **起跑条件满足**：评审放行条件 1/2 全数闭合，条件 3（minors 顺路）
  已前置落入 plan 文本，无悬空裁决。

## 5. 回归面（fixer +304/−174）

未发现评审清单外新事实主张或新方案（§3）；diff 中非处方文字均为同一
处方在多文件的同步面（勘误③四处、M2 属主四处、m4 登记行四处）——属
一致性同步非扩权。commit message 主张（「grep gates consistent with
final design」等）与文面相符。

---

## 6. Note 清单（不阻塞，逐条附建议归属）

- **N1 m7 相交文件清单仍欠二文件**：CONTEXT/LENS-03 的相交清单 =
  LensPanelView / xcstrings / Project.swift（忠实转录评审 m7 原文），
  但 LENS-03 ∩ LENS-04 files_modified 实还共含 `LensModule.swift`、
  `LensfunMatch.swift`、`M2-4-0-BUNDLE-MAP.txt`（评审时点即如此，评审
  清单自身漏列；fixer 照方抓药无责）。串行交错强制下无实害（单重活机
  物理串行 + L4 T2 交叉收口门覆盖语义序），信息面建议下批文档顺路补
  两行（或 LENS-04 DECISIONS 预登记交叉文件终表）。
- **N2 子任务 ΔN 带与 plan 带松耦合（继承性）**：LENS-01 子任务和
  13..**21** vs 带顶 18（fix 前 14..23 vs 20 同构，fixer 只按处方平移
  -1..-2）；LENS-03 子任务和 15..24 vs 16..26；LENS-04 10..16 vs
  12..16（min 侧）。plan 级闭合（被评审与处方的对象）精确；「越带申
  报理由」使执行契约无歧义——记录在案，不要求本批返工。
- **N3 D-LENS-4 保留概念级拼写**：`FocalLengthIn35mm/focal（RawLab
  式）`为 EXIF tag/RawLab 公式名引用，与 X4 钉死的 Swift 字段拼写
  `focalLength35mm` 分属两个语域，X4 显式禁 `focalLengthIn35mm` 新声
  明——无冲突面，仅存拼写双形，微记。

（复核完；本文件为唯一产出，零源码触碰。）
