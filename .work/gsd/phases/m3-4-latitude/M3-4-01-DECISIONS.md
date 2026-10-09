# M3-4-01-DECISIONS — FSIM-02 宽容度面板代码波（wave 1）

> 执行：2026-10-09/10 夜间（executor subagent worker，夜间全自动授权在案）。
> commits：`a3a34af` fix(iop) exact landing → `383d829` feat(core) descriptor
> runtime → T3 feat(app) latitude panel → T4 feat(app) bypass entry + mount fix
> → T5 docs。本文 = KD-1..5 执行期裁决正本（plan checker 回注 E1/E2/m1/m2/m4/m6
> 的执行期转录随批落账）。

## §1 KD-1 精确锚替换（T1）——数学正本转录 + 执行期复算

- **§6.4 参考向量独立复算（执行期亲算，uv/Python）**：四行 8 值全部命中（±5e-4，
  3 位小数 published 精度）：N=(3.90,2.80)→(K_h,K_s)=(+2.2783,−2.7033)、
  (4.05,2.95)→(+1.2313,−1.7833)、(4.50,2.95)→(−1.0111,−1.7833)、
  (4.05,3.40)→(+1.2313,+0.2661)；第五行交叉对 (4.50,3.40)→K_s=+0.2661>K_h=−1.0111
  = typed 拒绝 ✓。产线 solver 与文件内参考 solver 一致 ≤1e-8；落点 = a∓N 精确
  （1e-8）。golden 反向钉死三件（向量 + K_s<K_h 排序门 + 交叉拒绝 + 域守卫）在册。
- **F'(K*) 独立复算（checker m1 勘误值亲证，公式 `F'(K) =
  1−(1+w)^−(m+1)/m·(1+w^((m+1)/m))`，w=((a−K)/(C−K))^m）**：highlights
  m=1/2/4/8 = **0.3188 / 0.1672 / 0.0869 / 0.0447**；shadows m=1/2 =
  **0.3493 / 0.1873**（§6.1 锚 a=8/C=4.2/a_s=−7/C_s=−4.3，N=(4.05,2.95)）——
  与 plan checker 复算值逐位吻合；「正下界存在、二分必收敛」结论不变。
- **执行期勘误①（F 单调方向）**：M3-3-03 产线注释称「F strictly decreasing +
  切点 F'→0」——那是**简化臂**的病理；exact 形 F 严格**递增**（本文公式 >0）。
  产线注释已按 exact 形改正（solveKnee doc comment）。
- **执行期勘误②（m=2 多项式 bracketing 机理措辞，checker m2）**：简化臂 t=C−N
  下 m=2 的多项式 fq(v) 独立复算——自然域端点同号（fq(0)=+0.90 /
  fq(50)=+6.1×10⁶，bracketing 无法起步）+ (0,2) 内增外根 v≈0.1254 截胡（含它的
  括弧收敛于增根）+ 真根 v*=2.9687 两侧正常变号（fq(2.90)=−3.2 / fq(3.00)=+1.6）。
  「对多项式套 bracketing 必错根」的机理按此转录；**产线从不解多项式**（直接对
  F 二分），此面仅为 DECISIONS 誊写。
- **执行期发现③（深膝 bracket 扩张）**：exact 形高 m 深拉时根深远超出朴素界
  （m=8/N=8 @§6.1 锚 根 ≈−60，朴素 bracket −29 不含根）——solveKnee 增确定性
  几何扩张（`while F(lo)≥0: lo −= max(16,|lo|/2)`，纯函数 bit-确定），文件内
  参考 solver 同形。F 递增 ⇒ 扩张终止有保证（渐近斜率 = 1−(1+(C/A)^m)^−1/m > 0）。
- **clamped() 膝点穿透**：clamped 重建 Params 最初丢 knees（T1 首轮 IOPP 3 红
  根因）——已改为 8 字段全传（knees = wire state 非 clamped 输入）。
- **域守卫终形**：`solveKnee -> KneeSolution?`，nil = typed invalidDemand；
  守卫面 = 落点距边界 < `landingRoomFloor`（1e-3 stop）；N=0 保持 inactive
  （非 nil）。可选化选型按「调用面最小扰动」（DECISIONS 登记）。
- **v1 typed degrade**：nil knees + 非零 pull-backs → commit 不打包 uniforms +
  placementGain 恒等（裁决 4）；v1 零档 wire 字节不加四键（encodeIfPresent，
  测试钉死）。真实面为零断言未被推翻（未发现真实非零 v1 档）。
- **哨兵核验**：`FilmDeterminismTests.testFilmOutputPlaneHashMatchesTheGolden
  Sentinel` 于 LAYERS 终轮亲跑绿（哨兵 14_365_179_805_968_017_957 未翻）——
  **placement 不在哨兵链的预判成立**，零重钉。

## §2 KD-2 descriptor 运行时（T2）——E1/E2 修正判据落定 + scan seam

- **ISO 6846 判据式（E1 修正形，实测实现）**：`useful_highlight_ev` = 首个
  `Y ≥ Y_black + 0.9·(Y_white−Y_black)` 的 E；`useful_shadow_ev` = 升序**最后
  一个** `D ≥ 0.9·D_black` 的 E（`D = −log10(clamp(Y/Y_white, ≤ε))`，ε=1e-6）。
  旧文「首个 D ≤ D_black+0.04」为常函数退化（D ≤ D_black 恒真）——弃用。
  等价式（首个 Y ≥ Y_white·10^(−0.9·D_black)）与直接读法差 ≤ 一网格步（测试钉）。
- **本引擎实测值（portra_400 × portra_endura，真链 probe）**：useful pair =
  **[−1.4663, +4.4485]，宽 5.9148 stop**；`reference_ev` = **+0.0676**。上游对照
  锚 = RFC-023 §15.2 实测窗 [−3.18, +2.49] / 5.66（ISO 判据）——本引擎宽
  +0.25 stop（染料近似链 toe 携带略多），sanity 带 [4.0, 7.5] 内。
- **E2 带锚转录**：带套 useful（ISO）对、锚 5.66、初带 [4.0,7.5]——执行期实测
  5.9148 落带内；未收窄（单材料对证据不足，留多对采样后收窄）。
- **scan seam（本波最大执行期发现，§8.1 纪律的边界裁定）**：film 腿输出 =
  scene-referred 10^e（bake step 6），其白端携带胶片肩部全程（10^3.87）——
  **descriptor 需要的介质面是 print reflectance**。修法 = 链自身输出的逆映射
  过**链自身的前向面**：`R = 10^(−FilmPrintBake.systemDensity(e=log10(out)))`，
  会话项（base 投影/逐通道 Dmin/K 标定/中性包）与 bake 同函数单源——
  「inverse∘forward 于产线函数」，零第二套链实现。判据：上游 probe 读同一域
  （§15.2 print [0.00443, 0.7051]）。若直接以 10^e 面做 ISO 归约，白端 Y_white
  ≈10^4 使穿越点跑到 E≈+9.8（对照锚 +2.49 全盘失配）——scan 面为唯一正解。
- **单调带（T(E) 门实测标定）**：真链 T(E) 在 toe（E≈−6.5）有 ~3e-4 绝对凹陷
  （纸 toe 样本过晶格反转）、中段 ~1.25e-3（65³ 四面体地板在 reflectance 域的
  表达，与 golden 门 1b 的 6.2e-3 密度域同源）、白端 plateau（R≥0.9）抖动
  ≤0.06（LUT 白端病态角）。门终形 = **highlight 边界以下非降（band 2e-3，
  实测×1.5 头寸，E5 标定式）**；边界以上 = plateau 面（不塌黑即可）。真实
  探针缺陷为量级级反转，门语义保持。
- **PixelPipe factory 抽取（零行为门兑现）**：`assembleFilmLeg` internal static
  （histogram 取数留 call site）——film 腿既有测试（FilmLegTests/FilmDeterminism
  Tests）零改全绿；probe 与产线腿同一构造路径。
- **缓存**：`FilmDescriptorCache` key = fnv(pairHash ⊕ probeTag "lightamer.
  film.descriptor.probe.v1")，NSLock + LRU 4 + invalidateAll；exact-FNV 双写
  测试钉死（FilmDeterminismTests 同款）。

## §3 KD-3 宽容度面板 + 置位编辑面（T3）——标定值与规则终形

- **直方图轴（checker m4）**：原生可绘跨度 = **[−6.5578, +2.4394]**（256 bins ×
  [0,1] 线性过 binEV 公式；±12 为 descriptor ramp 域不混用）——常量入
  FilmPanelModel（latitudeAxisMin/MaxEV），测试钉死。
- **占比分类**：整 bin 归类——bin 全域低于阈 → 低于、全域高于 → 高于、跨界 →
  内容（≤1 bin 容差，DECISIONS 登记）；手算向量两形（单跨界 + 双端跨界）钉死。
- **有效性规则三条终形（checker E3/m6）**：
  ①滑杆动态最小值 = 侧别显式 `max(0,(a−C)+margin)`（margin=0.25）；
  ②`K_s<K_h` 违反 = typed `.kneeOrder` 拒绝**点名滑杆**（红行「膝点交叉——恒等
  核塌缩：请减小高光回退或阴影回退。」）+ 滑杆回弹（拒绝 tick 不写真相）；
  ③`H_min = 3.0 stop`（0.8587/3.0 ≈ 0.286 = mapper 峰量级锚，§6.1 峰 0.289）=
  **Fit 建议面守卫**：推荐对任一活动侧 room < 3.0 → 收回推荐 + 橙色提示行，
  手动 N 不拒不钳——§6.4 四行在 T3 有效性面全部可写入（E3 门，测试钉死）。
- **Fit 终形（§9.3）**：`N = 侧边距 + 0.25`；`a ≤ C` 侧 → off（0）；交叉 →
  比例保持 λ 二分（40 步确定性）分摊，λ→0 = 双侧 off 简并 + 报告；H_min 越限
  → 收回推荐 + 提示。**m=3 最小交叉例亲证**：§6.1 锚 margin fit @m=3 →
  K_h=−0.6021 / K_s=−0.2933（与 plan 独立复算 −0.602/−0.293 逐位命中）→ 交叉
  成立；λ 分摊在全域无解（m=3 交叉为 m 效应非 N 超额）→ 诚实落点 = 双侧 off
  简并 + sharedDeficit 报告（DECISIONS 登记，测试钉死）。
- **H_min 守卫的实机形态**：§6.1 旗舰场景 margin fit @m=2 → rooms
  (2.969, 2.517) 双双 < 3.0 → **推荐收回**（该场景 Fit 恒拒 = 注册行为，
  §7.3「lets the Fit refuse」原义）；宽房间场景（a=10/C=4.2）→ 落地（测试钉）。
- **端点斜率**：`f'(a∓) = (1+w)^−(m+1)/m`（§5.4 g'_Δ 面）——§6.4 row 2 发布值
  0.0648/0.0820 逐位命中（测试钉）。
- **stats 投递（checker m5 机制 (b)+(c)）**：(b) Registry 适配器闭包保留
  LastValue 快照（`FilmStatsSnapshot.last`，IOP 侧，front-matter 补列文件）；
  (c) coordinator PREVIEW 渲染完成点镜像进 `filmStatsSnapshot` @Observable 面
  + `filmDescriptor` cache-first 消费面。PixelPipe 零触（factory 外）。
- **挂载修复（T3 走查前置发现，见 §5）**：置位参数写路径 = M2-5 per-op provider
  形态（InspectorEditSession + PanelEditing），**路由宿主层**（addModuleToLayer
  落 adjustment layer 链 = ACEScc envelope 唯一包裹面；layerScope 路由提交）。

## §4 KD-4 走查（T4）——菜单旁路 + 实机证据 + 两项结构发现

- **旁路命令**：View 菜单「显示胶片面板」静态无门项（menu_show_sidebar 先例；
  零 MenuCommandID/零快捷键 ⇒ MenuCommandSet/AppPreferences/WorkspaceRouting
  Tests 三电路零触，11/0/0 亲跑）。卡 tap 双入口并存零触。
- **合成激活限制（环境级，如实登记）**：菜单命令合成激活三路皆惰（AXPress/
  CGEvent 真击/System Events），同屏对照 = 既有「显示侧边栏」命令同惰 ⇒ 非本批
  缺陷；DEBUG 探针缝 `-la_film_probe`（WorkspaceHostView #if DEBUG）为走查页面
  开启通道。菜单命令可达性 = Manual-Only（人工真机：显示 → 显示胶片面板）。
- **结构发现 A（已修）：胶片页默认面不可达**——InspectorView（film 分支宿主）
  在 gate-false 面只挂于 `.inspector(isPresented: exportPageActive)`；
  filmPageActive 翻真无宿主（编辑器右列 = 调整栈）。修复 = binding 扩
  `exportPageActive || filmPageActive`（dismiss 双关；present 侧 no-op——
  SwiftUI 呈现回声不得盖写活动页，首次挂载尝试曾把 export 页武装）。证据链 =
  film-fixed-crop.png（修复后首挂）→ w1..w7 全链。
- **实机证据（MANIFEST 十项）**：挂载/启用/Solve 读数（M 18.3·Y 16.7·×1.00）/
  双黄虚线 + 占比（descriptor 实机落地）/置位节全件/N_h 拖拽 2.12 EV（readouts
  实时：落点 +0.32 = a−N 精确、核宽 0.27、斜率 0.435）/⌘Z 恰一回退/Fit 落地
  N_s=5.15 + 高光侧 §9.3 简并关闭/**typed 拒绝行实机上屏**（红字点名滑杆 +
  真相回弹双证据）。Manual-Only 四行（菜单合成激活/m 步进驱动/材料切换/占比
  随图）配方在册。
- **会话卫生**：throwaway 项目（/tmp editor-probe-*.lalb）已清（含 WAL/SHM）；
  实例已 quit；defaults 零触碰；AI 弹窗「暂不」关闭。

## §5 声明外扩面（front-matter 之外，如实申报）

1. `Tests/LightamerTests/FilmPlacementTests.swift` / `FilmPlacementKernelTests.
   swift`——landing/N 值夹具为旧语义钉，等强度重钉（exact 形 + 有效 N）；
   golden 门 3 的语义孪生，不修必红。
2. `App/Sources/Lightamer/UI/ContentView.swift`——§4 结构发现 A 的 binding 修复
   （film 页默认面可达性的最小修）。
3. `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`——DEBUG 探针缝
   `-la_film_probe`（#if DEBUG 块内，生产面零触）。
4. `LightamerCore/Sources/Pipe/Film/FilmDescriptorProbe.swift` 的 scan-face 依
   赖 `FilmPrintBake.systemDensity`（internal 同模块，零 API 扩）。
5. PixelPipe factory 抽取 = front-matter 预申报唯一增量（兑现，film 腿测试零改）。

## §6 标定值汇总（执行期终值）

| 项 | 终值 | 依据 |
|---|---|---|
| landingRoomFloor | 1e-3 stop | 域守卫 floor（row-1 裕度 0.1 的 1/100） |
| H_min | 3.0 stop | 0.8587/3.0 ≈ 0.286 = mapper 峰量级锚（§6.1 峰 0.289） |
| Fit margin | 0.25 stop | §9.3 政策值 |
| useful pair 带 | [4.0, 7.5]，锚 5.66 | E2 处方；实测 5.9148 落带内 |
| reference_ev 带 | \|·\| ≤ 0.5，公式 = mid 锚读法 | K 标定；实测 +0.0676 |
| 单调带 | highlight 边界下 2e-3 绝对 | 晶格地板实测 1.25e-3 × 1.5（E5 式） |
| 直方图轴 | [−6.5578, +2.4394] | 256 bins × [0,1] 过 binEV（m4） |
| 占比容差 | ≤1 bin（跨界归内侧） | 整 bin 分类，手算向量钉死 |
| 交叉阈值 | m≥3（§6.1 锚 margin fit） | 独立复算 −0.602/−0.293 亲证（m6） |
| descriptor 实测 | pair 5.9148 / ref +0.0676 | portra×endura 真链 probe |
