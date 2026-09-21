# 05-03-DECISIONS.md — channelmixerrgb + channelmixer legacy + colorcontrast 决策记录

> T1–T4 决策由执行轮落账；T5（面板/GUI/轨 B/SUMMARY）由收尾轮补记。

## D1: seed 三分——channelmixerrgb DISABLED / legacy+contrast ENABLED-neutral（T2/T3）

- 论证：channelmixerrgb 默认参数（D illuminant @5003K + CAT16）施加真实色适应，
  不存在零参数恒等式 → seed DISABLED（dt `default_enabled = FALSE`，
  channelmixerrgb.c:3886；colorbalancergb D1 同处置）。
- legacy channelmixer 默认（identity RGB + v2，无 HSL/gray mix）选
  OPERATION_MODE_RGB + 单位矩阵 → 非负内容恒等；colorcontrast 默认
  （steepness 1/offset 0）→ Lab 恒等 → 两件 seed ENABLED-neutral
 （exposure-0EV 式，面板有实例可驱，轨 B 缓存中性）。
- in-gamut 恒等门未设：channelmixerrgb 的 D-白适应连中性灰都搬移（相对 D50
  锚），任何 fixture 都不恒等 ——恒等语义只经 disabled piece 成立。

## D2: D65-native 矩阵链（05-02 D2 沿用，T2）

- RGB⇄XYZ 用 LabRoundTrip.rec2020ToXYZ/xyzToRec2020 DIRECT（kernel 硬编码同对，
  经 LabMath.h）——无 D50 ICC 迂回。
- 中腿向 dt 固定 D50 LMS 锚（Bradford/CAT16/XYZ 目标白 verbatim）做相对适应；
  腿被管线矩阵对称包裹，锚在 D65 管线仍有效。`p` 保留 dt D50 蓝参考 0.818155。
- L023 半边契约教训落实：uniforms 只 carry 半边（rgbToLMS/mixToXYZ/xyzToLMS/
  lmsToXYZ），管线矩阵驻 kernel；测试钉 FULL 往返（track-A 端到端），不钉半边。

## D3: 单 kernel 运行时 5 路（非 dt 5-kernel unswitch，T2）

- dt 为 OpenCL 手工 unswitch 成 5 kernel（channelmixer.cl 注释明示 copy-paste）；
  MSL 用单 kernel + adaptation 运行时分支（数学逐路径同构，5× PSO 条目省去，
  5 矩阵路径照常可测——T2 非单位矩阵门逐路径覆盖）。
- linear-Bradford 腿无 Y 下/上缩放（dt chroma_adapt_bradford full=FALSE），
  full-Bradford/CAT16/XYZ 腿有（downscale/adapt/upscale）；RGB 腿纯 MIX。

## D4: camera illuminant commit 期回落（divergence #1，T2）

- dt 在 process 期读 RAW EXIF WB 系数反解 CCT；commit 无管线 WB 通道，故
  `.camera` 回落 daylight 模型 @params temperature（D→BB→custom fallthrough
  语义），面板注记。params 位保留 camera/detect（resolver 对 detect 返回 nil
  → 面板隐藏/禁用 + 注记，D-05-CONTEXT-5）。
- `_check_if_close_to_daylight`（daylight-GUI 人机工学开关）不移植：面板常显
  温度滑块，无消费者；其喂给的 camera-adaptation 覆盖一并跳过（用户 adaptation
  保留）。

## D5: color-checker 零移植证据（T4）

- `grep colorchecker LightamerIOP/Sources/ChannelMixerRGB/` 仅命中两处头注
  （NOT PORTED 声明），无 `_extract_color_checker`/`run_profile`/`colorchecker.h`
  代码。`grep -rn "colorchecker.h\|_extract_color_checker\|run_profile"`
  同上为零。
- AI WB（`#ifdef AI_ACTIVATED`，DETECT_*）一行不移植：illuminantToXY 对
  detect 返回 nil（T1 单测钉死）。

## D6: 矩阵交叉门限 float32-fair（T4）

- Swift derive() 折叠 Float params（6 位小数），Python 持全 double：
  实测 rgbToLMS 5e-8 / mixToXYZ 1e-7 / p 1.4e-7 → 门设 10× 观测
  （5e-7/1e-6/1e-6）。公式相等由 track-A 端到端（<1e-5，双链同跑）钉死，
  矩阵交叉只防常量转录错。
- 同理 T1 Bradford/CAT16 往返门 5e-4（dt 只发布 4 位小数，B·B⁻¹ 自残差
  [1][1]=1.00010082 实测）——常量精度界，非代码错。

## D7: legacy mixer XMP blob 投影注记（T4）

- dt v2 blob（52B）只 carry 每通道前 4 系数；Params 7 通道中 gray/HSL 行的
  后 3 列投影区本轮 3 case 全零 → blob 与 Params 一一对应；非零 gray/HSL 的
  XMP 由面板语义保证（cases 生成器断言 52B）。
## D8: cc_default/cb_default refs 同 hash（T4 备注）

- 四 fixture（ramp/flat/gray）上逐字节同 hash：恒等参数经 Lab 往返精确
  （flat_0ev 5d3098d9b2949609）。来源不同（Lab 链 vs Yrg/LMS2006 链），
  门各自独立，双记保留。

## D9: 面板行标签补齐 + 旧 sidecar 不补 seed 行（T5）

- Inspector `localizedLabel` 对新 op 曾回落裸 opName（英文小写行）→ 补
  `history_*` 中文显示名（色彩校准/通道混合/色彩对比；附带 colorbalancergb）。
  commit `777599a` fix(inspector)。
- 旧 `.lra` 恢复不补新 seed 行（23 实例恢复 → 新三件缺席；删 sidecar 后 26 行
  全现）。02-06 persisted-only 恢复语义，非回归；既有图收不到新模块行——
  Phase 6+ 可议 seed 迁移策略（FINDINGS 登记，不立号）。

## D10: GUI 走查口径（T5，与 05-02 同）

- AX `set value` 只走 live 预览分支；commit 通路由 PanelWiring +4（6 ticks→
  恰 1 commit）证明；CGEvent 真拖拽仍 BLOCKED（L011）。
- 色彩对比 a 陡度 1→3：视口块 meanAbsDiff 3.575/frac>8 0.1435；撤销逐位一致
  0.0000；布局红线（1440×816）不破。行圈 toggle 与 label 分离（圈=启用、
  label=选中，04-08-T4 GUI-5 语义）——走查先点圈误触，后改点 label 选中。
- 轨 B/PERF：零代码增量论证（disabled 直通 + enabled-neutral 缓存中性；
  显式腿恒真故不加）+ `.work/05-03/perf.md`；终轮轨 B 双判据全绿。
