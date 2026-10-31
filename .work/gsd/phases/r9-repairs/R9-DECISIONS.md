# R9 DECISIONS（M-1 调查批；issue #17）

## D-R9-1：R8 M-1 表型翻案（三件套逐项推翻）

1. **「视口全黑」→ 爆色 + 灰占位 + 自恢复**。本轮同供件同链复现：
   启用胶片即 posterize（`31-film-enabled.png` R8/R9 双轮一致，先于几何）；
   CW90 后灰占位 5 分钟后自行恢复渲染（oslog `pixelpipe output ready:
   PREVIEW bucket 1480px (3 hits / 50 misses, 26 planes)`）。
   灰占位 = 新 session 纹理缺席面（`displayTexture` 未推送），非黑帧。
2. **「胶片卡三值 NaN」→ 从未存在**。`34b`/`34-history` solve readout
   `M 18.3 · Y 16.7 · ×1.00` 全程正常；R8 `34b` 同值——R8 系误读。
   solve 面纯函数无 NaN 源（`percentileBin` total=0 保底 0；
   `exposureGain` p50Linear>0 守卫；`contentAdaptiveShift` log2 有限域）。
3. **「持久坏态」→ 冷 build 窗瞬态**。5 分钟 = 光谱 tc 拟合 LM 全网格冷 build
   （C200 278s / portra 269s；sample 栈 `SpectralTcFit.levenbergMarquardt`）。
   R8「35s 不恢复」= 观察窗短于 build 窗。

## D-R9-2：几何面脱罪（film×几何交集逐位正确）

机检矩阵 4+2 全绿（§二表）。pointwise 契约（CW90 映射值差 < 0.02）
在 flat/composite × film-off/on 四腿 + flat film-on 双臂上成立；
solve 输入二分 identity vs CW90 逐位相同。R8 假说「film leg 的 walked 帧
转置行为仍错」在机检面不成立。候选逐一排除：
① seed/键含帧形假设 — seed 四项（recordHash/tag/solvedPackHash/upstream）
无帧形维（`FilmTailPolicy.swift:150-164`），排除；
② solve 缓存转置撞键 — 键 = fnv(pair⊕stats⊕mode)，转置不改计数直方图
（instrument 双跑 statsHash 一致），排除；
③ film 腿起步平面形错配 — R8 同族腿；机检转置帧 32×48 断言全绿 + precondition
零触发，排除；
④ solve 转置产 NaN — NaN 从未在屏在值（D-R9-1② + nanCount 零命中），排除。

## D-R9-3：定罪转移 — C200 材料对光谱中性求解 Y 钳制（issue #17 本体）

- 构建探针值（同二进制同链）：C200 solvedPrintCC=(0,108.3,**250.0=钳制**），
  灰误差 3%；portra (0,33.1,26.8），灰误差精确 0。M8-2 Newton 梯
  （`SpectralBuildEngine.swift:708-750`，32 轮 seed 50,50，钳制域 [0,250]）
  在 C200 对上 Y 撞上限——中性平衡未收敛，print/scan 表在偏色工作点构建。
- 实测锚佐证：C200 [0,85.9,108.3] vs portra [0,51.6,52.5]
  （`neutral_print_filters.json`）——C200 的 Y 需求本就 ~2× portra，
  自近似 dichroic 下的自求解走得更远，撞墙。
- 归属：M8 光谱核材料覆盖面缺口 = M8 obs-1（v2 白场）在真照片上的首次实证。
  路由 M8-3+（求解器加固或材料对白名单）；本批不修（需 M8 档立项）。
- 连带：默认启用对 = 首排序对（`filmStocks/paperStocks` stock-id 排序，
  `FilmMaterialStore.swift:104-115`）= 恰 C200 对——新用户启用即中奖，
  加重路由优先级。

## D-R9-4：测试读回竞态（L014）— 红转绿的机理

- 原红 maxΔ 0.73/0.86 + 翻转/flaky（film-off 腿亦曾红 Δ1.0）= `expandToFloats`
  无 fence 直读在途平面（L014 违反）。fence 内移（`rawBytes` 先例，
  `LayerCompositeTests.swift:96-110`）后 18/0/0 全绿。
- 量级论证（防「fence 掩盖真缺陷」）：真 pointwise 缺陷应稳定复现且与 fence
  无关；本轮红具有翻转性（同测前后轮绿/红互换）+ 跨腿传染性（film-off 腿红）
  落地形态：`FilmLegM1DissectTests/testM1DissectCompositeLegsUnderCW90`（leg-by-leg
  重演 A/L/T2/T/F）；其运行日志（`/tmp/la-direct-tests-Layers.log` 10:57 轮）
  与本 lane 的 `layers-fenced-green.log` 结论一致（分层腿恒等式成立）。
  并行 lane 的存在由 `layers-fenced-green.log:7` 行交错 + 本文件 mtime 双源佐证。

## D-R9-8：自审回注闭环（R1：`PASS / 0 error + 6 minor`）

- m-1（证据错配+缺失）✓：33 重引为占位帧（vpmean 172.8 平坦裁片 `33-vp.png`；
  恢复帧正名为 `32c` 转置爆色帧）；「5 分钟」降为「时序未精确计时」；
  回填 `probe-verdict.txt` + `oslog-render-lines.txt` + `spectral-tcfit.sample.txt`
  + `32c-vp/33-vp` 裁片。
- m-2（覆盖洞）→ 本批闭环中：追加 v3×默认外观层腿
  （`testCompositeFilmTransposedFrameMatchesTheUntransposedLookupV3`，
  process 3 × exposure1.5/contrast15/saturation1.3），全套预期升为 **4443/34/0**。
- m-3（因果缺口）→ M8-3+ 立项消化：Y 钳制独立成缺（路由安全），
  但「3% 灰误差 → posterize」机制链（scan 表退化/LUT 级联）待 M8 档补像素值证据；
  M/Y 巧合（108.3 vs 108.32）待 verdict 复核；真照片 portra 对照腿缺失。
- m-4（断言无源）✓：四腿打印 `R9MARGIN|<leg>|maxDelta=`（单行 log，非断言）；
  film-off Δ1.0 红轮无日志——该轮日志已被后轮覆盖，注记为 L014 竞态族先例，
  不补（后轮 fenced 绿为结论承载）。
- m-5（测试卫生）✓：空栈腿补 NaN 计数；`expandToFloats` 加 bgra8 precondition。
- m-6（走查尾巴）：①undo 腿未重走（R8 `36b` 仅理论解释，挂账——冷 build 窗理论
  可解释但无新观测）；②并行 lane 行交错已注记（D-R9-6）；③R8「启用胶片 2 分钟
  未落盘」降为 obs（R9 侧落盘正常 items 3；疑 R8 轮去抖/时序观测问题）。
## D-R9-5：交付形 — 零产品代码改动 + 5 回归

- 唯一 diff：`Tests/LightamerTests/LayerCompositeTests.swift` +~390 行
  （5 测试 + helper；全加法；本文件即 Layers 域，BUNDLE-MAP/Project.swift
  零登记变更——新测试落域规则满足于「同文件同域」）。
- 封存面 17 件零 diff；App/Core/IOP/Scripts 零触；zh-audit 不适用。
- 全套预期 4443/34/0（4438/34/0 ⊕ 5；m-2 腿追加后）。

## D-R9-6：并行 lane 外来 diff 处置

- 10:35 发现 `Tests/LightamerTests/FilmLegTests.swift` 被未知并行 lane 写入
  172 行（4 测试 `testCompositeFilmTransposedV1FullLayer` 等；本 lane 未写、
  git 无归属、stash 空）。处置：完整 diff 存档
  （`omp-evidence/foreign-filleg-diff-1042.log`）后 revert——不合入、不认领、
  不删除证据。若 orchestrator 确认系本轮阵容内 lane 产物，可凭存档重放。
- 同源游离宿主红（Δ0.86，`layers-composite-red.log`）系该外来测试在本 lane
  的测试二进制构建前运行——其红与本 lane 复现红（Δ0.73）同属 L014 读回竞态族，
  不另立。
- 并行 lane 的 dissect 腿（`FilmLegM1DissectTests/testM1DissectCompositeLegsUnderCW90`，
  `layers-foreign-dissect.log`）**绿**：A/L/T2/T 四腿 maxΔ=0.0/nan=0/hot=0（271s）——
  第三方独立重演与本 lane 结论一致（分层腿恒等式成立），几何脱罪得外部佐证。

## D-R9-7：机器纪律追记（G4 透明越门）

- guard 全程 BLOCK G4（Data 20-21G < 25GB）。越门依据：free 73%（`memory_pressure`
  system-wide free）无 swap 压力；G1 heavy=0/GUI 单实例；本轮构建全增量
  （build-for-testing 复用容器，无 SPM 拉取，离线 flag 全程）。
- 起跑前卫生：清 /tmp sample/ips + `/tmp/r8omp` 440M；`--monitor 21600` 伴跑零 kill。
- 收口前清：`library.recentProjects` 探针路径 + `/tmp/editor-probe-*.lalb`
  （复核 `defaults read` 缺席）。
