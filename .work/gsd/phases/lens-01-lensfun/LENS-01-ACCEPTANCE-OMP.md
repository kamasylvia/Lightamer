# LENS-01-ACCEPTANCE-OMP — Lensfun 落地终审（dual_acceptance 终审眼，computer-use 实机）

> **PASS / 0 blocking + 1 major + 3 minor + 4 obs。**
> 验收窗：2026-10-23 09:35–10:20。验收对象 = LENS-01 执行链 + 修复三笔
> （B-1 `30fb152f` / M-1 `ea269dcb` / minors `8873a84d`）+ B-2 接线
> `7d3c2274`——审验 SHA 定 `7d3c2274`（`7d3c2274..f64fc9ff` 产品差 =
> r12-repairs 批 36 文件，**Lens/Lensfun/Projection 文件零触碰**亲核）。
> 方法 = 零源码改动 + 独立 worktree @`7d3c2274` + 独立 DerivedData 自建二进制
> （BUILD SUCCEEDED，strings 亲证 LensDefaultsWiring/LensPanelReadout 在位，
> bundle 内 56 xml + Licenses/Lensfun 四件亲核）+ 四探针实例 computer-use 实机
> （a/b/c/d/e 五项全做）+ 零残留收尾（worktree + 容器拆除，自出 pid
> 20684/23459/26078/26853 全部亲手 kill，终核 `pgrep Lightamer.app` 零残留；
> `lensfun.autoApply` 键测后删复原 absent）。
> 前置双路结论：一路 PASS+1B（渲染门 no-op，已修）+1M（fisheye 误标，已修）；
> 二路 PASS+1B（reloadDefaults 零接线 = B-2，已修）+ B-2 补验 PASS。
> 本轮 = 终审眼独立复验。
> 证据卷 = `.work/gui-acceptance/lens-01/omp/`（~50 截图/crop + 4 探针 stderr +
> 2 sample + sidecar + lens-params + dbtag-manifest）。

## 0. 结论头

**PASS / 0 blocking + 1 major + 3 minor + 4 obs**——五项实机抽验：

- a) LensPanelView 三态 readout：DNG（厂商 RAW 无 opcode）→ unknown
  「内嵌校正状态不可探测（厂商 RAW）——确认厂商校正不存在后再启用 Lensfun」；
  TIFF（raster）→ notApplicable「不适用：栅格图像无内嵌镜头几何概念——
  可放心使用 Lensfun」；detected 态无 opcode-DNG 供件未亲证（obs-1）。
  面板五段（§1 三态+匹配机/§2 手动滑杆+enable/四 toggle/§2.5 scale/
  §3 投影 picker/§4 browser/§5 Settings 段）逐段截图在位。**✓（2/3 亲证）**
- b) browser 选型 → 渲染面实际变化：DNG 面搜 "16mm" → 候选行
  （Canon RF 16mm 60 分等）→ 点选 → §1 翻「匹配到配置 · 105」+
  sidecar 落 `source=.lensfun` + 快照 bake（含 dbTag/matchScore/标定行）+
  画布差分 max 448/meandiff 0.61/1702px>30——**选型即校正成立**，
  B-1 修复价值主张 + B-2 接线缝②端到端亲证。**✓**
- c) auto-apply：键 `lensfun.autoApply=1` 下新开 TIFF（零焦距 EXIF）→
  恒等降级诚实面（notApplicable + 「无镜头信息」，无误应用）；toggle
  ON 态与键一致；EXIF 完备 raster 的自动命中因无供件未亲证（minor-2）。
  RAW 守卫面（detected/unknown 不自动）由 DNG 面行为一致佐证。**✓（降级臂亲证）**
- d) Settings Lens Data 段：Cache 页「镜头数据」段 dbTag
  `f220184e3903d245` 非空 + 手动更新钮 + CC-BY-SA-3.0 钉版文案；
  dbTag 与独立重算（seeded 56 xml 排序 manifest SHA-256 前 16 hex）**逐字一致**；
  首启 seeder 56 文件落盘亲证（一路行为级再证）。**✓**
- e) 主链 + 静置 CPU：探针冷启动→导入→双 rendered=yes→编辑器面→
  filmstrip 切图（TIFF/DNG 双向）→⌘E 图库/编辑往返全活；静置两窗
  （0.3×6 连平 / 1.7→1.3 单调衰减）+ 主线程 2327/2329·2388/2389 泊
  mach_msg + _PIPE_ 符号零命中——壳交接持续性无 churn。**✓**

1 major = browser 搜索触发面缺陷（major-1，旧查询粘滞返回，新行为）；
3 minor = 供件/显示小项；4 obs = 方法学与让渡注记。
**签核放行**：major-1 属 browser 交互层单点缺陷，不触渲染正确性/数据面，
路由修复队列不阻断收口（§六）。

## 一、抽验 b) browser 选型 → 渲染变化（W13 核心链亲证）

链路（probe4 `fx/` 双行，DNG 行 EXIF 70mm/f2.8）：

1. browser 搜 "16mm"（粘贴+回车，onSubmit 单触发）→ 候选行实 list：
   「Canon Canon RF 16mm F2.8 STM · 60」+「Fujifilm XF16mmF1.4 R WR · 60」
   （omp-41；与离线复算 17 命中·60 分档一致，`modelScore` contains 臂）。
2. 点选首行（坐标 1323,780 精算点击；AX 树候选行为 StaticText，
   Button 父缺席——SwiftUI `.buttonStyle(.plain)` 内 Text 直挂，
   坐标点击为唯一驱动面）→ 无确认 alert（unknown 态直 commit，
   D-LENS-2 门正确）→ §1 readout 翻转（AX 亲读）：
   `匹配到配置` + `Canon Canon RF 16mm F2.8 STM · 105`
   （105 = matchHardened 全参分，≠ browser 60 搜索分——双分制如设计）。
3. sidecar `probe-b.dng.lra`（schema 11）落两 lens item + 活实例：
   `source=.lensfun` / `lensKey=Canon RF 16mm F2.8 STM` /
   EXIF 六字段全携（focal 70/aperture 2.8/maker+model Canon…/
   embedded=unknown）/ **snapshot 在位**（dbTag=`f220184e3903d245` +
   matchScore 105 + profileMaker/Model + distortion/tca/vignette/
   realFocal 标定行 + aspectRatio/entryCrop/profileCrop）。
   滑杆七系数全零——**零滑杆 lensfun 档 live + snapshot 全套**，
   B-2 缝②（exifRefreshed 六字段白名单 + rematch fresh bake）端到端成立。
4. 画布差分（选型前后同框裁剪 680×720）：maxdiff **448** /
   meandiff 0.61 / px>30 **1702**/489600——渲染面真实变化，
   **B-1「选型即校正」价值主张实机闭环**（对照：TIFF 零选型前后帧
   差分 meandiff 8.51 系跨面误比已作废，见 obs-3）。
5. 无 DB 缺席面（hasData 真，browser 段渲染非下载臂）；
   无报错弹窗；undo/redo 对称未点验（时间窗，obs-4）。

判定：**W13（B-2 语义）PASS**——选型→commit→bake→渲染→readout 五跳全活。

## 二、抽验 a) 三态 readout + 面板五段（W1/W2 面）

- unknown：DNG（Canon 5D3 无 opcode tag → `.unknown`，D-L1-3 保守桶）
  readout = 「内嵌校正状态不可探测（厂商 RAW）——
  确认厂商校正不存在后再启用 Lensfun」+ match「置信度阈值内无匹配镜头配置」
  （选型前，omp-14）。**✓**
- notApplicable：TIFF（RasterDecoder 腿恒 `.notApplicable`）
  readout = 「不适用：栅格图像无内嵌镜头几何概念——可放心使用 Lensfun」
  + 「此照片无镜头信息——下方手动滑块仍可用」（omp-18）。**✓**
- detected：无 opcode-DNG 供件（两枚证据 DNG 皆无 51008-10 tag 面，
  行内 DNG 落 unknown 佐证探针保守语义），W9 确认 alert 未亲证。obs-1。
- 面板五段逐段截图：§1（omp-14/18）/ §2 七滑杆全零 + 启用 + 畸变/TCA/
  渐晕四 toggle 全 ON（omp-10/11）/ §2.5 auto-scale ON + 手动 1.000 +
  解析 1.0000 + 接力钮灰（omp-12）/ §3 目标投影「直线（无）」+
  §4 browser 搜索框 + 空态文案（omp-13/19）/ §5 见 §四。**✓**
- 导入过滤副证：`probe-a.jpg` 不进库（ImportFilter 白名单仅 RAW+TIFF），
  raster 供件改 sips 转 TIFF（9504×6336，EXIF 焦距未幸存——
  转制丢 EXIF，c) 降级臂供件恰用此特性）。

## 三、抽验 c) auto-apply（W13c/W4 面）

- 键 `lensfun.autoApply=1`（defaults 直写）→ 面板 toggle ON
  「新栅格图像自动应用匹配（需手动开启）」（omp-39，键↔面一致）。**✓**
- 新开 TIFF（focal=0 缺焦距）→ §1 = notApplicable + 「无镜头信息」，
  无 source 翻转、无误应用、无报错——**miss 恒等降级诚实面亲证**
  （缝① `injectedLensSeed` 经真 reloadDefaults：EXIF 快照随行 D6 +
  硬守卫 miss → 保留携 EXIF 的 `.off`，与 B-2 补验 §一缝①语义一致）。**✓**
- EXIF 完备 raster 的自动命中（载入缝 source=.lensfun + 同步 bake）
  无供件未亲证 → minor-2（机检等价面
  `testCoordinatorLoadSeedsLensThroughRealLoadChain` 8/8 已绿，
  真机行留人工：带镜头 EXIF 的 TIFF 一张即可）。
- RAW 守卫：DNG 面（unknown）同键下选型前无自动应用行为，
  与 D-LENS-1 生效域（notApplicable only）一致。**✓**

## 四、抽验 d) Settings Lens Data 段（W11 面）

- Settings > 缓存页「镜头数据」段（omp-30）：数据库标识
  `f220184e3903d245` + 「检查数据库更新」钮 + 钉版归属 hint
  （随包快照/CC-BY-SA-3.0/手动 SHA 更新语）。**✓**
- dbTag 独立重算：seeded 56 xml 按名排序 `name:sha256` manifest →
  SHA-256 前 16 hex = `f220184e3903d245`**逐字一致**
  （omp-dbtag-manifest.txt）。**✓**
- 首启 seeder：审前删 seeded 目录 → 探针启动后 56 文件落盘，
  一路行为级再证。**✓**
- 更新通道（断网 failed 行）未点验（需断网窗，obs-4 同项）。

## 五、抽验 e) 主链 + 静置 CPU（壳交接持续性）

- 主链：四探针实例冷启动→项目创建→导入（DNG 单行/TIFF+DNG 双行/
  TIFF 单行）→ 逐行 loaded/rendered=yes → 编辑器面渲染 →
  filmstrip 点击切图双向（omp-15→17）→ ⌘W 图库（2 张）→ ⌘E 返编辑器
  全活；Settings ⌘, 开/关存活。**✓**
- 静置 CPU：probe1 窗（DNG 单行，settle 10min）**0.3×6 连平**
  （RSS 162MB）；probe3 窗（TIFF，settle ~2min）1.7→1.3 单调衰减
  （RSS 1.1GB=100MP TIFF 解码态常驻）——衰减曲线 = `ps %cpu`
  指数平均残留热（F0P 终审 minor-1 同构），非 churn。
- 主线程 sample：probe1 2327/2329 + probe3 2388/2389 泊
  `mach_msg`（CFRunLoopServiceMachPort）；Pipe/render/decode 符号零命中。
  D-6 绝对门（<10%）余量充足。**✓**

## 六、分级残留清单

**major（1，本轮新发现）**

1. **browser 搜索框：已提交查询粘滞，换词回车返回旧结果**
   （`LensProfileBrowserView.rescore` 面）：TIFF 面“16mm”回车后恒
   「无匹配配置」（复现 5 次：粘贴/键入/cliclick/AX 双回车面一致），
   切 DNG 面同串回车即出候选。排除 DB 未装（dbTag 非空 + Settings 段活 +
   同实例 DNG 面命中 + 56 xml 可解析 1571 lens/1057 camera 离线亲证）与
   打分面（离线复算 "16mm" 17 命中 60 分档；单测
   `testStoreFaceScoresTheInstalledLibrary` 同串断言 1 行 60 分）。
   最简机理 = `rescore()` 的 `guard term == search else { return }` +
   Task 体读 `search`（`let raw = candidateRows(search: term)` 用 term
   正确，但 `scoring`/`candidates` 状态机与 TextField 提交时序竞合）或
   SwiftUI onSubmit 在该面未送达——**定位待修批二分**，本轮不定根因。
   影响：browser 可用性（换词需切文档/重进面板刷新）；渲染/数据面零触；
   W8 排序/置顶行因此未全验（首行 60 分在位，排序多行未验）。
   **路由修复队列，不阻断签核**（batch 价值主张 b) 已在 DNG 面闭环；
   修复后补 W8 全行 + 本 major 回归）。

**minor（3）**

1. **候选行名「Canon Canon RF 16mm…」maker 重复**（displayName =
   maker + model，model 串自含 maker）：显示层小瑕，与一路 o-D 同族
   记账噪音；修批顺路去重（model 去 maker 前缀或 model 原样 single 源）。
2. **c) 自动命中臂缺真机行**：EXIF 完备 raster 供件缺席，
   载入缝自动 source 翻转 + 同步 bake 仅机检绿（WiringTests 8/8），
   真机行留人工（配方：一张带镜头 EXIF 的 TIFF + 键开 → §1 Matched）。
3. **渐晕 label 识图「渐量/渐晕」摇摆**：omp-11 读「渐量 k2/k3」，
   omp-53 读「渐晕 k1」——截图字号小致模型误读，非定论缺陷；
   修批 grep 确认 xcstrings 真值（一行命令成本）。

**obs（4）**

1. **detected 三态 + W9 确认 alert 缺供件**：需 opcode-DNG
   （51008-10 tag）；机检面（DNGOpcodeProbe 12 法 + needsConfirmation 臂）
   已绿，真机行留人工。
2. **o-B 让渡再确认**：matched + 非 rectilinear entry + target 未设 =
   保守拒 identity 而 readout「匹配到配置」（本轮 Canon RF 16mm 系
   rectilinear entry 未触发此面；二路 o-B + B-2 批 o-B 让渡维持，
   UX 轮补「需选 target」提示）。
3. **TIFF 跨面差分误比作废**：omp-33/34 差分 meandiff 144.8 系 after 帧
   误触进图库面所致，已用 ⌘E 返编辑器帧重比（maxdiff 84/meandiff 8.51/
   1850px——残差 = 面板滚动区 + 画布位移，非渲染变化；该 TIFF 从未选型，
   恒等为正确面）。方法学注记：跨截图画布差分前必先确认同面。
4. **未点验行**：undo/redo 对称（W13 后半）/ W13b 卸 DB 面 /
   更新通道断网行 / W6 接力 crop 点击 / W7 fisheye 拉直——
   时间窗 + 供件所限；机检等价面全绿，真机行按 MANIFEST 留人工。

**双路遗留路由追认**：B-1/M-1/m-1..m-3 修复本体（二路已 PASS，本轮 b)
行为级再证）/ B-2 三缝接线（补验 PASS，本轮 sidecar 快照 + readout 翻转
再证）/ m-5 手动臂 raws（补验 PASS，本轮未触投影面，不重验）/
row 9 不 bump 裁决（二路对抗成立，本轮渲染变化面 = 新激活行为非旧行为变更，
裁决不受扰）/ RawLab fisheye 抽样（一路 o-5 义务，到位后补）——
按既有路由生效。

## 七、验收轮痕迹与还原

- 主树 HEAD = `f64fc9ff` 零改动（本报告 + 证据卷唯一写产物，不 commit）；
  审验对象锁定 B-2 收口 `7d3c2274`（`7d3c2274..f64fc9ff` 产品差亲核 =
  r12-repairs 批，Lens 族零触）。
- defaults `lensfun.autoApply` 测后删除复原（终核 absent）；seeder 目录保留
  （首启行为产物，用户态合法面）；fx 夹具全在 /tmp，已随容器拆除。
- 构建：worktree `/tmp/lens01-omp/wt` @`7d3c2274` + 独立 DerivedData
  `/tmp/lens01-omp/dd`（Debug BUILD SUCCEEDED；SPM 在线解析一次，
  后续零网络）。
- 进程：自出 pid 20684/23459/26078/26853 亲手 kill（kill 前 ps 确认
  ppid=本 omp 进程 + 命令行独立容器路径）；终核零残留。
- GUI 独占：运行窗内零他路 Lightamer 实例（ps 亲核）；重活前 guard PASS
  （G1/G2/G4 全绿，G3 已撤 v1.3）；滚动条轨道点击翻页为本轮新探针手法
  （CGEvent 滚轮/SwiftUI ScrollView 不吃合成事件，AX ScrollBar press
  不可达——M7-1 AX 限制第三先例，手法记 LESSONS 候选）。
