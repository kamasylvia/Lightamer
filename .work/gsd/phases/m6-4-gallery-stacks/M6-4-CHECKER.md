# M6-4-CHECKER — 修订版两 plan 独立反向核（2026-10-13）

> checker = 独立反向核路（对修订版 plan 反向核，非对 review 复读）。审查对象
> = 修订后 `M6-4-01-PLAN.md` + `M6-4-02-PLAN.md`（**commit `d1a87117`** 面）；
> 判据正本 = `M6-4-PLANS-REVIEW.md` findings（2 error + 7 minor + 9 建议）+
> `M6-4-CONTEXT.md` 七 OQ 生效值（不重开）+ `M6-4-RESEARCH.md` + 源码亲核
> （ImportService / LibraryQueries / LibrarySchemaTests / Project.swift /
> AIMaskService / RasterMaskStore / AIMaskEditing / LayerEditingState /
> MaskToolbarView / xcstrings 全部 checker 自查，非转引 fixer）。本批 =
> fixer + checker 合批 worker，checker 捕获项回注 fixer 批（amend 同
> commit），批内角色分账在下文「三、checker 捕获回注」。

## 结论

- **Plan 01 = 放行**（修订版达成面 A goal 的可执行形态；E1/M1-M4/S1-S6
  全部落位且自洽；无 error 级残留；3 项观察项随执行顺带，见 §四）。
- **Plan 02 = 放行**（修订版达成面 B goal 的可执行形态；E2/M5-M7/S6'-S8
  全部落位且自洽；无 error 级残留；2 项观察项随执行顺带）。
- 七项 OQ 生效值（D-M6-4-1..7 全 A）零触碰——修订全部落在 plan 机制层，
  裁决面零重开。✓

---

## 一、Goal-backward 反向核

### 面 A（stacks + auto-stack 落地）

- **goal 分解**：`.lalb` 手动堆叠（封面/展开/收起 + 徽章 UI）+ auto-stack
  （LightCraft 全套语义）+ schema v4→v5 additive 迁移。验收形态 = 迁移 +
  round-trip + 聚类 golden。
- **反向走查**：goal 五件 → 任务映射 T1（schema v5，8 法）/T2（CRUD，
  16 法）/T3（聚类，8 法）/T4（分页谓词，9 法）/T5（导入缝，5 法）/
  T6（App 模型，10 法）/T7（UI + 文档）/T8（收口）——**无 SC→任务映射
  缺口**（56 = 8+16+8+9+5+10 逐文件复算闭合）；AC1-8 与 T 一一挂账无
  漂移。
- **M1 偏离后的 goal 完整性**：RESEARCH A1 的 LightCraft「顶图被滤首可见
  成员顶替」语义在纯谓词裁决（D-M6-4-3）下降格为 DECISIONS 登记 + V2
  候选——这是 goal 内「LightCraft 全套语义」的**已申报有界偏离**（auto-
  stack 聚类语义本身 = OQ-2 生效值原样），phase goal 的主体（堆叠落地 +
  迁移 + golden）不受扰。登记链完整（KD-7 亲核论证 → KD-5 口径申报 →
  风险节 → T8 DECISIONS → AC4），**零字静默形态已消除**。✓
- **判定：修订版 01 可达 goal。**

### 面 B（AI 分割蒙版原生 spike 判据核验）

- **goal 分解**：原生零模型成本路达标即收——点击精修（07-3 已交付回归）+
  hi-res patch 组装 + Edge 羽化参数化 + 人物实例入口；Describe 不可达
  收口挂账 V2。
- **反向走查**：KD-4 五行判据全落双轨（行 1 回归绿 / 行 2 patch golden /
  行 3 羽化 golden + 参数面 / 行 4 人物实例单测 + GUI 轮 / 行 5 文档
  收口）→ T1-T7 映射完整；SC 24 = 9+6+5+4 闭合。**E2 修订使判据行 4 的
  可机检面前移**：提取腿钉死标签合成 + 合成 label-buffer fixture 后，
  人物实例的单测面不再依赖 GUI 轮才暴露提取 API 破损（原 plan 的爆炸点
  推迟形态已消除）——goal 的「判据核验」更早闭合。✓
- **判定：修订版 02 可达 goal。**

---

## 二、五处核心修订自我一致性复验（逐项）

### 1. E1 匹配算法 ↔ T5 测试口径（01）

- KD-6 四步规则：①后缀主式（`hasSuffix("/" + relPath)` 语义，SQL =
  参数化 `LIKE '%' || ?` + ESCAPE）②多命中 → 批内 folderName 候选消歧
  ③零命中 → folderName 候选 → stem 唯一命中兜底 ④失败/歧义未消 → 整组
  skip（`mergeStacksSkipped`）。
- T5 五法逐条对表：①规范流正测（真 `importFolder` session 树，禁手拼
  image_path）→ 打规则 1 的生产路径真实性；②匹配细则表（后缀命中/
  folderName 消歧/回落名/stem 撞名 skip）→ 规则 1-3 全分支；④
  `mergeStacksSkipped` 计数 → 规则 4；⑤零触 + 零漂移。**每条规则恰有
  断言落点，无断言悬空、无规则无测。**
- 风险节公式勘误核对：`Media/<folderName>/<relPath>` 与
  `ImportService.swift:220-228`（folderName 无条件前缀）+:579-583
  （`Media/` 前缀）亲证同式——**原公式两处（KD-6/风险节）已同步，无
  残留旧式**（grep 零命中）。
- **判定：一致。**

### 2. E2 提取腿 ↔ 单测 fixture（02）

- KD-2 提取腿 = `allInstancesMask` 标签合成（`labelCompositeMask`
  :211-243 参数化，输入 = 标签图 `CVPixelBuffer` + `IndexSet`）+
  `generateScaledMask` 禁用注记（:176-183 双损坏头注引证）+ grep 机检。
- T3 fixture：合成 label-buffer 四件（单实例/多实例/未知标签域/零覆盖）
  ——helper 输入即 CVPixelBuffer → **测试面与生产提取面的接缝恰在
  buffer 层**：零 Observation 依赖零 entitlement 自洽（R4 延伸成立）；
  零覆盖件钉 `covered == 0 → invalidMask` typed 分支（labelCompositeMask
  :236-239 既有抛点）。
- 机检措辞核对：「全仓**新增 diff** 零命中」精确——存量
  `scaledMask`（:190-198，layer A 已登记升级缝）保留不动，新增代码零
  调用点，两说并存不冲突。✓
- **判定：一致**（fixture 计数四/三失配为 checker 捕获项，已回注，见 §三）。

### 3. M5 羽化缝落点全局唯一（02）

- 正腿唯一非零源 = MaskToolbarView 滑杆 → `AIMaskEditing` 单接线点 →
  `commitRasterMask(featherRadius: sigma)`（GPU Deriche，bake 内，门
  > 0.1，0 = 字节恒等——`RasterMaskStore.swift:88-99` 头注亲证）；
  负腿 = CPU `applyFeatherNegative` + **恒传 featherRadius = 0**；
  0 = 两面全零。四既有 `commitRasterMask` 调用点缺省 0（review §4 亲证）
  ——**双羽化在数据流上不可能**（两臂互斥 + 0 门 + 单一非零源）。
- 机检面核对：`.metal` 零 diff + `MaskCombiner.swift` **与
  `RasterMaskStore.swift`**（正腿复用面）整文件零 diff——checker 关注点 1
  已扩。T4② 参数面断言（正腿 sigma 穿线 / 负腿恒 0）为唯一性 supplement。
- **判定：缝落点全局唯一成立。**

### 4. M3 AC7 表述（01）

- 风险节指名两法（`testPackageTablesCreated` :149 + extras allowlist
  :163-169；`testFreshCreateStampsUserVersionFour...` :181 + :187 的
  `== 4`）——与 checker 亲读源码逐位一致（allowlist subtracting 数组 +
  user_version 断言均亲证在位）。
- AC7 = 「既有 Library/Import 测试族**除指名定向更新点外**原样绿」——
  「原样绿」与「定向更新」的原矛盾消除；T8 DECISIONS 申报项 + T1 冻结面
  断言（⑥ PRAGMA verbatim）不与之冲突（冻结面 = schema 侧，指名两法 =
  测试文件侧）。✓
- **判定：一致。**

### 5. 02 预期带机制（S8）

- 四处同式：plan 头基线段 / T7 验收 / AC8 / checker 关注点 7 均为
  「**plan 01 实际收口 `TOTAL|<n>/24/0|` + 21..25**（起草时预测
  3832..3842 挂重算机制）」——01 出带时的连带更新有唯一机制出处，无第二
  数字真相。对账链机械闭合：01 带 52..58 + 02 带 21..25 两段滑差独立。
- **判定：一致。**

---

## 三、独立猎残

### checker 捕获并已回注（三处，amend 入 `d1a87117`）

1. **02 KD-2「四 fixture」vs T3「三 fixture」失配**（修订自引入）→ 对齐
   四件（零覆盖件 = typed invalidMask 分支钉死，见 §二.2）。
2. **01 read_first 8「LibraryGridModelTests.swift（APP 级注入形）」**——
   S3 聚拢后域归属表述悬空 → 改「App 模型注入形——LIB 域，BUNDLE-MAP
   :356 先例 = S3 聚拢同域依据」。
3. **01 front-matter xcstrings「清单见 T5」**——键清单实际在 KD-8（前版
   悬空指针，评审未列）→ 改「清单见 KD-8」。

### 修订引入矛盾清查

- 01：SC 数字五处（头基线段/AC8/T8/checker 6/front-matter 注）全部为
  56/0/52..58 同式，无 45/10 残留（grep 亲证）；「APP bundle 贴线」风险
  行已被 bundle 分账行替换；键名 %lld 两处（KD-8 清单 + 徽章 accessibility
  行）同改，无 `_fmt` 残留。✓
- 02：键族五键全部 `ai_mask_*`（front-matter/红线段/KD-5/T7/风险节五处
  同步，`mask_tool_person`/`mask_feather` 等旧拼 grep 零命中）；KD-3
  重写后 `applyFeather(` 旧签名零残留（新名 `applyFeatherNegative`）；
  「计划 23/19 法」零残留（24/20 同式五处）。✓
- 两 plan 交接：01 的 LIB 聚拢不扰 02（02 测试域 LAYERS/APP 不变）；
  02 的 S8 重算依赖 01 收口值——串行序 01→02 维持，无批序冲突。✓

### 依赖序

- 01 内部：T1（schema）→ T2（store）→ T3（聚类）→ T4（查询）→ T5（导入
  缝，依赖 T2 stackWith + T4 memberships 面）/T6（模型，依赖 T4）→ T7 →
  T8——无循环、无前向依赖。✓
- 02 内部：T1（纯函数）→ T2（segmentPatch + 羽化）→ T3（实例 + UI）→
  T4（接线）→ T5（GUI 轮，R4 资产依赖独立轮）→ T6/T7——原序维持。✓

### 不可机检项清单（全部有申报归宿，零悬空）

| plan | 项 | 归宿 |
|---|---|---|
| 01 | M1 收起态无顶替偏离 + 计数口径分裂 | KD-7/KD-5 → DECISIONS（T8） |
| 01 | link 模式不自动成栈 | KD-6/风险节 → DECISIONS |
| 01 | 匹配细则版本化条款（含 LIKE ESCAPE 细节） | KD-6 → DECISIONS |
| 02 | LightCraft 符号语义核对 | KD-3 → DECISIONS |
| 02 | person 标签编号域探针出入 | KD-2 → DECISIONS |
| 02 | GUI 轮五行（patch 真图/多人实例/羽化走查） | T5 → MANIFEST |
| 02 | livePlane 驻留姿态与释放点 | KD-1 → DECISIONS + 风险节 |
| 02 | spike 五行判定 + V2 挂账 | T6/T7 → SUMMARY §spike |

### 数字对账复算（checker 独立重算）

- 01：8+16+8+9+5+10 = **56** ∈ +52..58 ✓；3759 + 52..58 = **3811..3817** ✓。
- 02：9+6+5+4 = **24** ∈ +21..25 ✓；带 = 01 收口实测 + 21..25（机制化）✓。
- 文件数：01 六新 LIB 文件（Project.swift LIB 数组登记六行）/ 02 三
  LAYERS + 一 APP（四行）——与 front-matter files_modified 一一对应。✓

---

## 四、残留观察项（不阻断，执行期顺带）

- **O-1（01）**：后缀匹配的 LIKE 元字符转义实现细节（转义字符选择、
  relPath 含 `%`/`_` 的极端面）——KD-6 已指派 DECISIONS 版本化条款，
  T5② 细则表覆盖命中面；执行期落条款时补一条转义单测断言即可。
- **O-2（02）**：`livePlane` 的分辨率记账（pre-upsample quality-tier
  平面 vs decode 全分辨率平面——composer 输入口径）——已由「layer B ROI
  产物分辨率未知」风险行 + 探针申报义务覆盖；执行期在 DECISIONS 一并
  申报 livePlane 口径。
- **O-3（01）**：fixup 变换宿主 = App 侧模型（KD-7）而 T4⑦ 以 LIB 测试
  ——review §2 已亲证 LIB target 依赖 Lightamer App 模块
  （Project.swift :646-652），不矛盾；执行方**勿新开 Core fixup 文件**
  （files_modified 无此行——保持 additive 申报纪律），T4⑦ 断言经
  LIB import App 模块面落。
- **O-4（02）**：T2③「percent 0 同引用返回」在新缝形下为 CPU 函数自身
  契约的防御断言（接线层 percent 0 不达 CPU 面而由 bake 缺省 0 承担）
  ——两处字节恒等（AC2「双保险」）语义已写明，执行期勿把 ③ 误实现为
  接线层断言。

---

## 五、checker 表态

- **Plan 01：放行**（可开工；T1-T5 按任务序，T5 fixture 纪律为硬门）。
- **Plan 02：放行**（可开工；T1/T2 纯函数面先行，T3 提取腿按 KD-2 钉死
  形，T5 GUI 轮维持 R4 形态）。
- 执行串行 01→02 不变；七 OQ 生效值零触碰；本 checker 对修订版的定向
  复核覆盖 review「处置摘要 2」要求的 E1/E2/M1/M5 四节 + 全部 minor/
  建议落点。
