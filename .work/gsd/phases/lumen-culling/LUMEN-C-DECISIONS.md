# LUMEN-C DECISIONS — 蒙版精细化(LU5)裁定与偏差记录

> 执行批 = LUMEN-C-PLAN.md(checker `75678937` + fixer `a0e43b44` 后 HEAD;批起点
> = LUMEN-B 终态 `8896a46e`)。执行窗 = 2026-10-24。本文件 = 裁定正本
> (grow/shrink 终值 + LightamerShell refineMasks 装配 diff 申报 + 各偏差 +
> 键登记——review M-4 判据改);逐任务记账正本 = 同目录 `LUMEN-C-SUMMARY.md`。

## §1 grow/shrink 参数终值(plan 风险节预留的 execute 期裁定)

- **默认 face(自动触发 + 手动入口)= grow .05 / shrink .05**——Lumen
  `selection.py fine()` 自身缺省值,直译标准位。网络像素 `networkPx = 320`
  (Lumen `NETWORK` 三种 kind 的公值;我方 Vision 快速蒙版无 320² 语义,取
  直译常量作不确定带宽度标定——band = max(3, round((maxEdge/320)·0.75),
  4096 档下 ≈10px,与 Lumen 33MP 语义同带)。
- **sky 特化 .3/.02 不采用**:Lumen 的 sky 臂是其样张标定(`refine_fine`
  per-kind);我方蒙版无 kind 区分(AIMaskSource 五前缀均同一 face),单一
  默认 face。若未来按来源分档,走 `AIMaskSource` 映射(预留,零代码)。
- 算法钳制边界(T1 钉死)与参数值解耦:测试 `testGrowShrinkClampBoundaries`
  钉的是 per-pixel 上界式 `rise ≤ (1−c)·min(1, c/grow)` / `fall ≤
  c·min(1, (1−c)/shrink)`,与具体 grow/shrink 值无关——换终值零测试改。

## §2 LightamerShell refineMasks 装配 diff 申报(review M-4 判据改)

- 供给形 = **GUI post-assignment 恰一行赋值**:`editingSeams.refineMasks =
  { [weak maskRefineCoordinator] ids in … }`,紧跟既有
  `editingSeams.projectWriteProbe = projectWriteProbe`(:1126 先例同位)。
- **McpServerController 零 diff 面核**:`git diff 8896a46e..HEAD --
  …/McpServerController.swift` 空(批终态复核在 SUMMARY §红线核);FIX2③
  零例外兑现。
- 闭包体 = 三行(coordinator 取还 + typed 错误映射
  `MaskRefineError → McpToolError.invalidParams`)。映射落装配点理由:协调器
  是 App 域件,不 import MCP 类型(依赖方向单向);映射面恰一处。
- `grep refineMasks` 供给面恰两处 = Seams 声明(EditingToolset)+ Shell 赋值
  (SUMMARY §红线核引行号);工具体(`refineMasksBody`)与协调器方法
  (`refineMasksForMCP`)非供给面。

## §3 偏差与边界申报(全部行内 `(deviation)` 级,无 blocking)

1. **批内多蒙版 = per-mask commit(N 步 undo),非 Lumen 的单批一步**
   (coordinator 头注 (a)):Lumen `replace_rasters` 一批蒙版一次 commit;
   我方 `commitLayerEdit` 是 per-layer 缝,批级单 item 需新 history item
   类型 = 封存面禁区(红线 2)。自动路径(99% 场景)单蒙版 = 一步,语义同
   Lumen;MCP 多 id 场景每蒙版独立可撤销(可辩护 UX)。deviation 接受。
2. **re-bake featherRadius 恒 0**(coordinator 头注 (b)):Edge 正羽化在
   bake 时已固化进 PNG 像素(`RasterMaskStore.bake` 前置 Deriche 预通),
   精细化把「含羽化的存储面」当快速 alpha 输入;re-bake 再施羽化 = 双羽化
   (X8 两缝正交的忠实读法)。负腿 logit-gain 同理是存储像素重映射。代价:
   用户改羽化 percent 需重新生成/重打补丁才落到存储面——现状交互本就如此
   (percent 是「下次 bake」语义,featherSection 注记),非本批新引入。
   AIMaskFeather.swift 全程零 diff ✓。
3. **guide 腿 = 盘真相显影态**(`QuickLookRenderer.renderedPlane`,
   pristineOnly: false):X8「显影后显示域 ≤4096px」的等价落地;活会话未
   落盘的滑杆实时态不在 guide 里(2s debounce 窗)。蒙版语义锚定 decode
   frame(D-07 继承定案),guide 只是质量辅助——注册接受。触点最小化:
   零新渲染代码,复用 14-2 的 headless 链。
4. **erode/dilate = chamfer 距离 / 分离运行最大值形**,非 cv2 椭圆栅格:
   vImage 无椭圆 morphology;band 边界 ±1px 级差异,golden 带吸收(实测
   mean 2.8e-3 / max 6.4e-2,带 0.02/0.15)。`_blur` 大 σ = Lumen 自身的
   reduced-copy 技巧直译;Gaussian 半径取 3σ 解析式(cv2 ksize 公式的
   ±1 径差,同类吸收)。
5. **auto 触发挂 patchRebake commit 也再点火**(hook 不区分 patch):
   与 Lumen 不同(其 fine 按钮无此通道)——我方 patch 重烘焙会置换已精细化
   的 raster,再点火 = **自愈**(settle 后精细化面被重新施用);debounce
   1.2s > patch 1.2s 链确保 patch 先落。会话 livePlane 陈旧边界:下一次
   tap 从会话面组合再重触发——同自愈逻辑收敛,无永久性覆盖。
6. **skip +1(Layers 套件)**:LU5 时长探针(`testRefineDurationProbe`,
   红线 14 族)默认 skip(LIGHTAMER_PERF_PROBE=1 才跑);红线 14 的「实机
   样张」形态挂 validate 道。基线 skip 40 → 预期 41。
7. **xcstrings 键入 T2 commit 的文件带 T3 的工具描述键**:同文件两次纯
   插入不可拆分 staging;4+3 键两次尾插,`git diff --stat` 各自留证
   (48 行/48 行),B 批 T5/T7 同款。

## §4 键登记(AGENTS.md 键族节随批)

- **UserDefaults 恰一键 `mask.fineAuto`**(Bool 默认 true;typed 读 +
  注入式 defaults;全仓字面量恰一处 = `MaskRefineCoordinator.fineAutoKey`,
  Settings 行经 AppPreferences alias 消费;body 零直读)。
- **xcstrings 键族(7 键,两次尾插,历史键字节零触碰)**:
  `ai_mask_refine` / `ai_mask_refine_failed` / `history_mask_refine`(T2)+
  `mcp_tool_desc_refine_masks`(T3)+ `settings_maskrefine_auto` /
  `settings_maskrefine_hint` / `settings_maskrefine_section`(T4)。
  zh-audit `--check` + `--self-test` 双 PASS(1719 source / 2038 catalog)。
- **MCP 注册面**:33 工具闭集(M7-5-01 的 32 → 本批 33);culling 域
  14 工具与 McpCullingContext 零触(D-LU-8)。
