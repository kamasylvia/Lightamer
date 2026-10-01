# M2-7-1 ACCEPTANCE — 数据与内核（双羽化 + 换算钉 + mask 级属性 + sidecar 载体 + revision 写点 + Follow Edges）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 7 commits（`d6de037`..`cb3b3ea`，
> 正本 = checker 修正版 `7b88bbb`：E2 edgeMapPosition -4 / E3 写点终表五处 / E5 bump 挂
> 提交腿 / E7 双 nil 谓词 / M1 翻面收窄，全部落地）。方式 = AC 12 条逐条核对 + 六重点
> 定向抽查（实现亲验 + 测试真伪判读 + grep/git 机检 + GPL 参考源并读）+ 两域独立复跑。
> **结论头：PASS / 0 error + 0 minor。**

## 一、复跑 vs 声明

build-for-testing @ HEAD（`cb3b3ea`）exit 0（执行方遗留产物早于 T7 的 3 行 AI 改动，
验收前重建对齐），两域定向独立复跑（`Scripts/test-direct.sh` 直启）：

| 域 | 声明 | 本轮独立复跑 | 判定 |
|---|---|---|---|
| Layers | 285/3/0 | **285/3/0**（19s，peakRSS 1042MB） | ✅ 逐值一致 |
| App | 410/0/0 | **410/0/0**（167s，peakRSS 1242MB） | ✅ 逐值一致 |
| 全套 | 2493/16/0（基线 2464+29，873s EXIT=0） | 两域实测（含全部 29 新增测试 + 两域既有 695）+ 其余五域零 diff 文件面（T1–T7 不触 IOP/Library/Sessions/Export/IOPParity 源） | ✅ 覆盖变更面，与声明对账一致 |

skip 持平 3（Layers 既有）；MEMFAIL 未触发（两域峰值 <8G）。

## 二、六重点核查结论

### ① E7 双 nil 谓词（checker 回注实现亲验）

**判定：按正本字面落地，单源成立。**

- kernel 腿分流（`MaskRasterKernels.metal:171`）：`if (u.form2.z != 0.0)` → Alcedo
  线性带腿；否则旧二次腿**逐 token 未动**（diff 评审亲核：`f = clamp((k2−q)/(k2−1))`,
  `f*f`、border ≤1e-6 硬边 guard 全保留）。分流按 mode 旗标**而非按值**——双 nil 恒走
  旧腿，与值无关。
- 打包（`DrawnMaskRasterizer.swift:100-102`）：`innerFeather ?? 0, outerFeather ?? 0,
  hasDualFeather ? 1 : 0`——腿内 nil→0 补缺、modeFlag = `hasDualFeather`（任一非 nil）。
  非 ellipse 形态 form2 = (0,0,0,0) 不受影响。
- **双 0 显式 = Alcedo 腿硬边不回落**测试格在案（`MaskFeatherAlignTests:268-290`，
  `testExplicitZeroPairIsAlcedoHardEdge` 族）——E7 补格兑现。
- facade mode-aware 单源（`MaskSpec.swift:161-162`）：
  `resolvedOuterFeather = outerFeather ?? (innerFeather != nil ? 0 : border)` 亲验逐字；
  `hasDualFeather` 头注明言「THE single predicate」禁第二 nil-check。

### ② E5 bump 提交腿（live tick 零 bump 真伪读码）

**判定：bump 只挂 history 提交腿，代码级实证。**

- 全仓 `bumpContentRevision` 生产调用点 grep = **恰 4 处**：`MaskOverlayHost.swift:597`
  （endInteraction commit 腿，dirty 门 + defer 恒复位，commit 前恰一次）、
  `AIMaskEditing.swift:185`（install 提交前）、`LayerEditingState.swift:292`
  （duplicateAndInvert 提交值）、`LayerEditingState.swift:315`（fill 前向携带 +1）。
  **appendForm/mutateForm 函数体亲读零 bump 调用**——live 腿 revision 恒不变，非仅测试
  断言。
- 「正常笔画恰 +1 不走重放」：MaskRevisionTests 全程模拟 press→appendForm→live ticks
  mutateForm→endInteraction——commit 恰 1、live tick 间 revision 不变、总 delta 恰 +1。
- 三命令无 bump 载体裁决复核：duplicate（revision 原值随迁，内容搬运）/resetEdits（实现
  核验只写 `chain = []`，mask 不动）/clear（记录消失无生产目标）——与 E3 裁决一致，
  理由 DECISIONS §七在案。
- overlay 腿 expectedRevision 参数面**未引入**（AI 侧 `expectedRevision: Int? = nil` 默认
  参数除外）——P2 接线边界遵守。

### ③ E2 edgeMapPosition = -4 + tier additive

**判定：勘误正确落实，段位无冲突。**

- `PipeCacheKey.swift` grep 实证段位表：composite -1 / mask -2 / **retouch -3（:81 实占，
  06-07 stroke-leg 输出槽）** / **edgeMap -4（:90）**——checker E2 勘误（原拟 -3 撞车）
  修正到位。
- `layerTier` 一行 additive 分支 `-4 → .maskPlane`（:166），既有分支（sentinel/mask/
  composite）逐行未动；既有键函数零 diff。
- additive 第四件 `edgeMapNamespaceID`（固定 UUID）自洽：base sentinel 会在 tier 首行
  短路返 nil，edge map 需独立 namespace 承载「不挂 layer」语义——DECISIONS §八声明，
  属键函数实现细节非新 API 面，验收认可。

### ④ D-5 修复（挂账兑现真伪 + 翻面零漂移族）

**判定：挂账真兑现，翻面范围合规。**

- sibling 保真构造 diff 亲核：`var spec = layer.mask ?? MaskSpec(); spec.drawn = drawn;
  layer.mask = spec`——旧 `MaskSpec(drawn:)` 重建（抹 parametric/raster/
  deletionProtected/contentRevision 四 sibling）在 appendForm/mutateForm 两 live 腿均已
  消除；`MaskOverlayRecord` 抽取（同文件，View 持 @State 委托，手势/几何零动）使写点
  契约可单测——属申报文件内结构重组，非越界。
- 揭穿测试真伪：带 parametric+raster+锁的层画一笔后四字段存活断言——旧代码该测试必红
  （重建即抹），**能揭穿原缺陷**，非摆设。
- SidecarV5Tests 翻面 = **仅 `:204` 一条**（缺口钉 `XCTAssertNil(mask.deletionProtected,
  …)` → 双向真断言 `deletionProtected == true` + `contentRevision == 7`，setup 增一行）；
  `:111/:119/:164` 零漂移族 diff 亲核零 touch——checker M1 收窄口径兑现。

### ⑤ Alcedo 线性带 MSL 数学等价（GPL 只读取数）

**判定：逐式等价。**

并读 `grade_mask_coverage.cpp:150-153`（Radial）与 `MaskRasterKernels.metal:173-176`：

| Alcedo cpp | 我方 MSL | 等价 |
|---|---|---|
| `rho = sqrt(rx*rx + ry*ry)`（旋转在半径除法前） | `rho = sqrt(q)`，`q = dx²/rx² + dy²/ry²`（dx/dy 已旋转） | ✅ |
| `inner = max(0, 1 − inner_feather)` | `inner = max(0.0, 1.0 − u.form2.x)` | ✅ 逐字 |
| `outer = 1 + outer_feather` | `outer = 1.0 + max(0.0, u.form2.y)` | ✅（MSL 多 `max(0,·)` 防负——合理防御，语义域 outerFeather ≥ 0） |
| `1 − clamp((rho−inner)/max(outer−inner, ε), 0, 1)` | 同式（ε=1e-6 vs kAnalyticEpsilon 同量级） | ✅ |

代码零拷贝入库（GPL 只读公式数值参考），红线合规。

### ⑥ 8 条偏差合理性

**判定：全部合理，无一需推翻。**

1. **T2 goldens 随 T1 commit**：单文件承载两组 golden，拆分需同文件两轮 generate 零收益
   ——纪律 2 分批选择，T2 commit 语义仍独立（常量单源 + 测试改挂）。
2. **方向锚 +90**（golden 否决 plan「−90」示例文字）：plan 映射表公式 `atan2(nx, ny)` 给
   (1,0) → +90，示例文字与公式自相矛盾；plan 明文「执行时以 golden 采样对验证符号」即
   此案；方向语义自洽（−(sin rot, cos rot) = −n̂ ⟹ rot = atan2(nx, ny)）。
3. **MaskOverlayRecord 抽取 + defer 微修**：测试可达性必需（@Environment 视图构造即
   fatal）；defer 恒复位消除幽灵提交路径（顺手正确性修复，正常流不可观测）。
4. **fill 前向携带 +1**（非归 1）：防更早 epoch 的 expected=1 陈旧写在 fill 后复活——
   「单调」语义与穿越写防护自洽。
5. **AI gate 后置 bake + invalidInput 复用**：gate 读 post-await live spec 才能抓 await
   窗口内穿插写（前置会漏检）；不加新 error case 避免触非申报文件 AIMaskTypes.swift。
6. **edgeMapNamespaceID additive 第四件**：见 ③，自洽。
7. **AC1「逐位零漂移」等效承载**：pre-change kernel 无法同场物理复现位级比对——以
   06-03 goldens 零改动复跑 + 旧腿 float64 parity（gate 5e-6 沿 06-03 先例，实测
   1.13e-6）+ 「Alcedo-zeros 误路由」反证（差距 >0.1）+ kernel diff 评审合成证，诚实
   且充分。
8. **应用序探针重设计**：原机制（feather/invert 调换输出必变）在线性算子下**数学不可
   达**（Deriche blur 线性 + invert 仿射 + opacity 标量乘，单条目严格可交换）——重设计
   为双条目非线性 combine 构造（feather-after-combine 在 difference 切口泄漏 ~0.3，
   正确序恒 0）+ inverted+feathered 轮廓锚 + 门阈值 0.1/0.11 三件，探针实质非空转。

## 三、12 条 AC 逐条判定

| # | AC | 判定 | 证据 |
|---|---|---|---|
| 1 | 双腿 parity ≤1e-6 + 三锚点 + nil 零漂移 + 回落矩阵（含双 0 格） | ✅ | MaskFeatherAlignTests 在 Layers 285/3/0 内全绿；:268-290 亲验；§二① |
| 2 | gradient 换算 golden 两档 + 方向/起止锚；compression_default Core 单源 | ✅ | MaskGradientDefaults.swift 单源；测试挂常量；偏差-1 有据 |
| 3 | item feather 腿 + 应用序非空转探针 + 门阈值边界 | ✅ | MaskCombiner feather 腿 additive（enabled/五式/reduce 零 diff）；探针重设计合理；0.1/0.11 边界格在案 |
| 4 | facade 三 setter + 嵌套递归寻址 + miss 静默 | ✅ | MaskItemSemanticsTests +5 全绿；递归 walk 头注首中语义 |
| 5 | sidecar 双向 capture/restore + nil 零漂移保持 | ✅ | SidecarV5Tests 11/0/0；§二④ 翻面范围亲核 |
| 6 | 写点终表五处 + 三命令零 delta + 恰 +1 不重放 + AI 拒装 + undo 穿越拒 | ✅ | grep 4 生产点实证；MaskRevisionTests 6 全绿；§二② |
| 7 | D-5 揭穿测试 sibling 全存活 | ✅ | §二④ 真伪判读通过 |
| 8 | Follow Edges 三景 golden + snap 降级 + 空链 + 纯函数；Mode 穷举零 default | ✅ | FollowEdgesTests 8/0/0；`grep "default:" FollowEdges.swift` 零命中亲跑 |
| 9 | 边缘图缓存键 additive + stamping/五式 parity 复跑 | ✅ | PipeCacheKey diff additive-only 亲核；DrawnMaskRasterTests 8/0/0、PipeCacheTests/LayerCacheTests 全绿 |
| 10 | 全套回归 0 fail ≈ 2464+29 | ✅ | 两域复跑逐值一致 + 五域零 diff 文件面；执行方 --all TOTAL 2493/16/0 |
| 11 | diff 边界 == 申报文件集 | ✅ | 7 commits 逐 `--stat` 核对全命中、无越界（T7 的 AIMaskEditing 3 行在申报集内） |
| 12 | 三新测试文件登记闭环 | ✅ | Project.swift :448/:460/:689 + BUNDLE-MAP 三行，grep 双命中亲跑 |

机检补充：AC6 单源 grep `contentRevision ?? 0` 全仓仅 MaskSpec.swift 3 处（bump 折叠/
文档注释/原语行），App/Sources 零命中（T7 批消除 AI 错误消息同拼写插值——行为不变）。

## 四、Findings

0 error + 0 minor。无 ≤20 行可修项。

备注（非缺陷，留档）：执行方遗留的 build 产物早于 T7 最后 3 行改动，验收前
build-for-testing 重建对齐 HEAD 后复跑——不影响交付态判定。

## 五、翻账清单

`​.work/gsd/REQUIREMENTS.md`（本批同 commit）：

- M2MASK-01 ✅ Delivered 数据/内核（双羽化双腿 + mode-aware 单源 + 回落矩阵；锚 `d6de037`）
- M2MASK-02 ✅ Delivered 换算钉（compression = τ/(2√2) + 方向 atan2 + 常量单源；锚 `3ab8aad`）
- M2MASK-03 ✅ Delivered revision/并发面（CONTEXT-2 收敛口径，指向 M2MASK-07）
- M2MASK-04 ✅ Delivered（item feather + 应用序探针 + 三 setter + 递归 walk + sidecar 载体；锚 `1a038a5`/`7231c14`）
- M2MASK-05 ⏸ 部分交付注记（Follow Edges 内核已交付——kernel/缓存键/walker/熔断预埋；接线归 P2 M2-7-2；Luminance/Color Range 与 AI Subject 未动；锚 `066423f`）
- M2MASK-06 留 P2（M2-7-2 地盘，注记 UI 零触碰）
- M2MASK-07 ✅ Delivered（contentRevision 终表 + matchesExpected 单源 + D-5 兑现；锚 `768d5e3`，验收本文件）

## 六、验收方式与范围声明

- 复跑命令：`caffeinate -dis xcodebuild build-for-testing …` + `caffeinate -dis
  Scripts/test-direct.sh --bundle Layers|--bundle App`（L028 双读判据）。
- 实现亲验文件：`MaskSpec.swift` / `MaskRasterKernels.metal` / `DrawnMaskRasterizer.swift`
  / `MaskOverlayHost.swift` / `AIMaskEditing.swift` / `LayerEditingState.swift` /
  `PipeCacheKey.swift` / `SidecarLayerStack.swift`（经 diff）。
- 测试真伪判读文件：`MaskFeatherAlignTests.swift` / `MaskRevisionTests.swift` /
  `SidecarV5Tests.swift`（diff 级）。
- GPL 参考并读：`AlcedoStudio/alcedo_studio/src/edit/mask/grade_mask_coverage.cpp:130-160`
  （只读，零拷贝核验）。
- 未覆盖声明：IOP/IOPParity/Library/Sessions/Export 五域未独立复跑（本 plan T1–T7 零
  触及该五域源文件，`--stat` 逐 commit 核对为证）；全套 --all 数字采用执行方声明对账。
