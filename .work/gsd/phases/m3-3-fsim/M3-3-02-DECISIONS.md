# M3-3-02-DECISIONS — FSIM 管线批（wave 2）

> 执行：2026-10-08/09 夜间（executor subagent，夜间全自动授权在案）。
> commits：T1+T3 `feat(core): film sub-run seam…` → T4 `feat(iop): filmPlacement…`
> → T2 `feat(core): print bake and fused film kernel…` → T5 `feat(app): film
> record persistence legs…` → T6 `feat(export): job film tail…` → T7 本批
> （docs）。执行序 = m9 预授权的修正式 T 序（T1→T3→T4→T2→T5→T6→T7）；断点
> 条款未触发（T1+T2 未超支 ~2×，T6 留在批内交付）。
> 本文 = KD-1..7 执行期裁决正本；checker 回注（E1/E3/E4/m4/m7/m8/m9）全部落地。

## §1 KD-1 film sub-run 缝 —— 按处方落地 + 三项执行期定形

- 3×2 交互矩阵（E4 语义声明）：`.sdrGamma` 行 film 激活时降出**整个终端驻留
  集**（colorout/borders/watermark/gamma）并按 v50 序重放；`.edrLinear` 行
  colorout 随 film 臂加入降出（重放仅 colorout，gamma 恒不重放）；`.drt` 行
  降出集零改。六格断言齐（off 三格 = 既有族全绿 + FilmLegTests 零路径 byte
  门；on 三格 = FilmLegTests 4/5/6）。
- **`runTerminalTails` 收口形**：run()/runSub() 两处尾调用点收敛为一个共享
  sequencing 体（film → DRT tail → display replay；nil filmTail 返回 nil =
  零路径逐位现状）。DRT 交接 = 数源替换（upstream 值换 film 输出 hash），
  `DrtTailAssembly.seed(upstream:)` 签名零改（亲核）。
- **FilmMethodBox 双态**：payload 缺席（材料未解析）= T1 routed-blit 恒等
  载体（byte-exact，cache-neutral）；payload 在 = `film_subrun` fused kernel
  单 pass（负片段查表→base→滤色→印相 LUT 四面体→log 域强度混，零中间平面
  落显存）。GPU 载体 = run-scoped `FilmGPUPayloads`（curve buffer + texture3d
  rgba32Float 表——半精度禁于 scene-linear 输出面——+ uniforms），经
  `FilmMethodBox.runContext`（nonisolated(unsafe) + 腿内 set/clear，单写者
  同步窗）注入；测试注入走 `assemblyContextForTesting`。
- 印相 LUT 输入域 = 归一化负片密度立方（KD-3 裁定兑现）；立方域界 = film
  密度域 + base − 滤色头量（per-channel：R 无、G 100CC×s_m、B 100CC×s_y），
  随表携带（FilmPrintTable.domainLo/Hi）。

## §2 KD-2 运行期统计腿 —— 缓存面分半 + 三条定形

- **缓存分半（AUTO core vs RECORD 层）**：`FilmSolveCache` 只缓存 AUTO 核
  （中性包 M0/Y0 + 自动曝光 gain + content-adaptive 投影），键 =
  `fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`；手动 Y/M shift + exposureEv 是
  CONSUMPTION 层叠加，**不入缓存键**（KD-2 裁定原文：record 字段走
  recordHash——首版实现误把它们折进缓存值，测试逮住后按裁定改分半形）。
  solvedPackHash = 终值 (M,Y,gain) 的 bit-pattern FNV（入 seed；手动变更
  翻 seed 的另一通道，与 recordHash 折叠一致）。
- **曝光归一目标 = 0.184 有原理依据**（非假设）：印相段 K 标定（§3）把
  session 中灰放在相纸 mid-density 上 →「相纸 mid-density 对应目标 EV」恒等
  0 EV → gain = 0.184/P50。P50 = 整数秩分位（256-bin 累积计数，钉死的 ramp
  断言）。
- **per-ROI 红线的结构性兑现**：模式 tag 无 ROI 项 + film box
  tileWorkingSetBytesPerPixel = 0（永不入 tile 驱动）→ 一次 run 恰一次全幅
  统计（测试钉：tag 相等 + box 两 erased 面恒 0）。
- 统计面跨框架缝 = `FilmStatsSeam`（LayerCompositeSeam 先例：Core 持值类型
  + holder，IOP 在 populate 装 ScopeReduce 桥；未装 = 确定性的手动-only 面）。

## §3 KD-3 印相段 bake —— K 标定（本批最大的模型补全，D-5a 的必要完成项）

- **印相段 per-pair 曝光标定 K（enlarger time）**：滤色拨盘只解决通道均衡，
  不解决整体曝光水平——裸系统下负片密度（≥ ~0.5 + base 0.6）把印相曝光压在
  相纸 toe，纸的中等密度物理不可达（数值证伪在案：裸 K=0 时 mid-gray 目标
  1.03 > SysC max 0.68）。K = 公共印相曝光加项（三通道同值），标定 =
  `paperCurve_G(−(curve_G(e_mid)+base_G−kM) + K) = paperMid_G`（session 操作
  点 = **pack 后**密度；先按未 pack 密度标定的首版被测试逮住——pack 把操作点
  推出系统可达域，B 通道 floor）。K 烘进表内容，kernel 零改动。
- **反演 = session 系统反演**（pack 在内）：`SysC_c(e) =
  paperCurve_c(−(curve_c(e)+base_c−k_c) + K) − Dmin_c` 逐通道有界二分反演
  （固定 60 梯子）→ out = 10^e。灰阶误差恰 0 的机理：pack 使三通道在中灰处
  印相等（01 求解器语义），session 系统逐通道反演在 P* 处各自回到 e_mid →
  三通道 out 恒等 0.184（测试钉）。
- 串扰矩阵：**常量起步 = 恒等矩阵**（D-5d 双向登记的兑现点：本批 kernel/
  参考链恒等串扰；per-profile 拟合挂 M4+）。回填义务随 golden 批（03）复核。
- `LutEncodingCatalog` 零触碰 ✓（机检）。

## §4 KD-5 filmPlacement —— 简化臂的膝点标定 + 与 RFC-023 的两处显式偏离

- **膝点解算 = 拨入深度语义（简化臂）**：pull-back N = 落点在介质边界内侧
  的深度（t_h = C_h − N / t_s = C_s + N），非 RFC §9.2 的 t = a − N——后者
  需要实测场景极值 a（descriptor 面）;分支渐近线 = 介质边界（f(a) ≤ C 结构
  性），「从场景顶下拉 N」无 a 不可表达。锚点：a_h = +7 / C_h = +4 /
  a_s = −7.5 / C_s = −4.5（DECISIONS 登记常量；M3-4 FSIM-02 的 descriptor 臂
  恢复 §9.2 精确形）。有效性规则 1（N ≥ a−C）在该语义下自然消解。
- **m=1 闭式 + m≥2 有界二分 + 括号守护牛顿**：F(K) 的根是切点（F' → 0，
  C^m 接触的数学面），裸牛顿发散——守护 = 步出括号或 |F| 不降即回落二分。
  阴影侧残差镜像符号（F = K − g；导数两侧同形 `1 − (g'_Δ + g'_H)`）。
- 域 = ACEScc（envelope 20.5–69.9 内，Contrast/Cat02 kernel 先例）；标量取
  **power norm**（RFC §15.5 建议：Y 低估双零通道像素）；delta 形 + 双零
  pull-back 早退拷贝 = 恒等 bit-exact（GradeCatalog identityJSON 的 no-op
  点；kernel 在核内直接返回原始 texel）。
- 登记闭环（m8 清单 + 两处同面外延）：GradeCatalogTests 18/14/17→19/15/18 +
  catalog/owner/seed-deferred 列表 + filmPlacement 20.8 pin；V50OrderTests
  105→106 + native 剥离集 + 槽位约束测试；**CatalogAddFaceTests 枚举
  12→13**（add face 经 19 行 catalog 自动枚举——m4 可加不可编裁定的面板）+
  EditorState.templateInstance 第 19 case（identity 模板）。V50OrderTests 的
  计数闭合 = m8 同类（add-only 行插入的登记面，非行为断言）。

## §5 KD-6 coordinator 四件 —— 零偏离 + 两处补线

- carrier/写腿/恢复腿/`filmTailPolicy(for:)` 全按 DRT 四件套孪生落位；
  `terminalTailPolicy` 零 diff；恢复腿挂 load 链 DRT 腿之后。
- **导航面补线**：undo/redo/jumpToHistory 三处补 `syncFilmCarrierWithHistory`
  （DRT twin 只在 undo/redo/jump 有 sync 调用点——测试逮住 undo 后 carrier
  未清，按 twin 形补齐）。
- **成对写入兑现**（01 移交第 1 条）：makeSidecarDocument 的 historyHash 尾
  位折入 `effectiveFilmRecord()` + `filmRecord` 字段同批写入。
- store 装配：LightamerApp 组成根注入 `Bundle.main.resourceURL/
  FilmProfiles/profiles`；坏目录 typed 降级（film 面暗 + 一条
  `toast_film_store_unavailable`，新增 xcstrings 键——append 式，历史键零触）。
- **T6 carrier-walk 边界**：M2 导出批的 filmTails 数组只有**已加载图**带
  carrier（`filmTailPolicy(for: .export)`），批内其他图 nil = legacy 面。边界
  注记：film 无编辑面板（M3-4 前），用户可见行为零影响；grid-only 图的 disk
  sidecar filmRecord 消费面挂 M3-4 导出 UI（DECISIONS 登记即止）。

## §6 KD-7 导出递缝 —— E1 三编辑点亲核 + 双载体纪律

- ExportQueue 三编辑点全落：Job.filmTail（:60 drtTail 旁）/ enqueue
  `filmTails:` + precondition / 腿内 `$jobFilmTail.withValue`（$jobDrtTail
  外层再嵌套，值域互不干扰）。`ExportQueueContract.swift` 零 diff（机检：
  `git diff d68ebf8..HEAD -- …Contract` 空）。
- ExportRenderer：`$jobFilmTail` TaskLocal + `Request.filmTail`（additive）
  + consult = `request.filmTail ?? jobFilmTail`（drtTail twin）；两个 pipe
  调用点传 filmTail（film 与 DRT 独立开关，物理序恒 film 前 DRT 后）。

## §7 执行期发现与偏差（全部已处置，无阻塞）

1. **replay filter 的 v50 序**：首版按 caller 输入序过滤——重放序错
   （colorout→gamma→borders→watermark），测试逮住（byte 相等系 fixture 巧合：
   白边框在水印下无差异）——修为 `(iopOrder, multiPriority)` 排序（KD-1 处方
   原文「按 v50 序重放」的兑现）。
2. **planesRendered 只计主管线**（既有语义）：sub-run 平面（film/replay/DRT
   tail）只经共享 cache 的 hit/miss 可观测——测试改断言 misses（DrtTailTests
   时代的既有口径，非本批引入；DECISIONS 备案）。
3. **膝点牛顿在切点发散**：F 的根是切点（F'→0）——守护形牛顿（步出括号/
   |F| 不增即回落二分）；「二分+牛顿」计划面以守护形兑现。
4. **K 标定两连修**（§3）：未 pack 密度标定 → session 点标定；反演漏 pack →
   session 系统反演。三处皆测试逮住、同批修正。
5. **BUNDLE-MAP 基线校正**：全套实测 3125/16/0 = 实际基线 3085 + 本批 +40
   （M3-3-01 obs-2 的 3081 推算值在此以首个全套轮实测校正；+40 =
   FilmLegTests 9 + FilmPlacementTests 7 + FilmPlacementKernelTests 3 +
   FilmPlacementDriverTests 4 + FilmPrintBakeTests 7 + FilmCoordinatorTests 5
   + ExportFilmChainTests 4 + V50OrderTests +1）。

## §8 密封面机检对表（`git diff d68ebf8..HEAD`）

- `ExportQueueContract.swift` / `DrtEotf.swift` / `Lut3dKernels.metal` /
  `LightamerSidecar.swift` / `HistoryStack.swift` / `HistoryHash.swift` /
  `ModuleInstance.swift`：**零 diff**。
- `TerminalTailPolicy`/`DrtTailParams`/`DrtTailAssembly`/`policyTag
  "lightamer.drt"`：PixelPipe diff 内零命中（seed 签名零改亲核）。
- `defaultFaceDisabledOpNames`：Registry diff 零命中（19 行注册 + prewarm +
  FilmStatsSeam 装配为仅有的 additive 面）。
- V50Order：entry 数组 add-only（filmPlacement 20.8 单行 + 注释；既有行
  零动，测试 pin）。
- 六格式导出矩阵（ExportFormatSpec/ImageIOEncoders/WebPEncoder）：零 diff。
