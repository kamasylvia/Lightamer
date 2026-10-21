# LENS-01 第二路独立验收报告(对抗错位路线;2026-10-20)

**结论:PASS(修复本体三笔全成立)/ 1 blocking + 0 major + 1 minor + 6 obs**

- 对象:修复三笔 `30fb152f`(B-1 isNeutral 语义扩展)/`ea269dcb`(M-1 fisheye
  重转录)/`8873a84d`(docs+minors),主树 HEAD `8873a84d` 亲核零漂移;执行链
  25 commits(`7f80f82a..8873a84d`)全链密封面复核。
- 方法:零源码改动;B-1/M-1 修复本体逐行对照产线源 + Alcedo 上游源 +
  独立数值复算(Python 直算生产公式,不经测试基建);消自消 golden 亲跑
  **两遍**(定向轮 + 全套轮,双轮全绿);全套 `--all` 独立一轮。
- 全套独立复跑:**`TOTAL|4093/40/0|` rc=0 零 MEMFAIL**——注意 4093 = 4088
  (修复前四轮同值)+ **5** 新 golden(IOP +1 / IOPParity +4),修复批只跑过
  定向轮、**本轮 = 修复后首个全套轮**;派发预期「4088」为修复前口径。
  逐 bundle:IOP 753/5/0(峰 7615MB)+ IOPParity 478/6/0(6354MB)+ Layers
  494/5/0 + Library 738/4/0 + Sessions 284/9/0 + Export 385/5/0 + App
  961/6/0;skip 40 = 37 基线 + probe 3(修复批零新 skip——旧 T2 的 GPU
  XCTSkipIf 随重建摘除,本机有 GPU 本就不触发);对账 4088+5=4093 精确。
- 定向三 bundle 独立复跑:IOP **753/5/0** + IOPParity **478/6/0** + App
  **961/6/0**——与修复批申报逐值一致(峰 7435/6369/2832MB 全门内)。

---

## 1. Blocking(B-2,第二路新发现;非修复笔缺陷)

### B-2 — lensfun 校正的**写入路径在产线端到端不可达**:`IOPModule.reloadDefaults` 全仓零生产调用点,自动应用/EXIF 解析输入/快照 bake/detected 确认门运行时全部死路

- **机检事实(穷尽 grep + git 考古)**:`reloadDefaults` 的全部调用点 =
  **17 处测试**(LensAutoApplyTests/LensMatchHardeningTests/FlipParity/
  CropParity/PipeCache/ROINegotiation/DenoiseProfile 族);App/LightamerCore/
  LightamerIOP 产线代码**只有协议声明(IOPModule.swift:59)与各模块 witness,
  无一调用**。`git log -S ".reloadDefaults(image" --all -- App LightamerCore`
  = 零命中——**该 seam 自 Phase 02 引入以来从未被产线接线过**。
- **对 lens 批的杀伤链(逐条产线源码亲核)**:
  1. **auto-apply(LENS-02 T2)死路**:唯一生效点 `LensModule.reloadDefaults`
     (LensModule.swift:326)无调用者;`lensfun.autoApply` 键 + 硬守卫 +
     注入式 reader 全部就位但运行时无人读。面板 toggle 只写键。
  2. **EXIF 解析输入永为 nil**:`Params.focalLength/cameraMaker/cameraModel/
     imageCrop/embeddedGeometry` 的唯一生产写入点 = reloadDefaults;镜头
     实例经 EditorState.templateInstance(:1044 附近,`LensModule.Params()`
     静态默认)入链,EXIF 字段全 nil。`LensfunMatch.matchCommitted`
     `guard focal > 0 else { return .missingFocal }`(:833 附近)→ 恒 miss。
  3. **browser 选型在产线 = identity +「无镜头信息」**:commitSelection
     (LensPanelView.swift:582)→ bakeCommitted → matchOutcome = missingFocal
     → bake nil → 落无快照 params → 渲染 isNeutral 探针同 miss → identity;
     readout 刷成 `.idle` + "此照片无镜头信息"。用户无任何手动输入焦距的
     UI(滑杆只是手动系数)。**「选型即校正」在产线交付面不成立**。
  4. **detected 确认门(D-LENS-2)永不触发**:`needsConfirmation(embedded:)`
     只对 `.detected` 为真;embeddedGeometry 产线恒 nil → false → RAW 文档
     选型不经确认(实际无害:第 3 条使一切 inert)。
  5. **快照 bake 的 auto 臂(LENS-04 T1)死路**:reloadDefaults 内同步 bake
     无调用者;唯一活 bake 点 = browser 选型(第 3 条使其恒 nil)。
- **为什么 B-1 修复仍正确且必要**:修复笔的谓词扩展对「可达的写入路径」
  语义正确、测试反自消成立(§2);B-2 是**同一价值主张的另一半缺口**——
  一路验收 B-1 封的是「渲染门吞掉校正」,本路封的是「写入路径造不出校正」。
  一路验收把 auto-apply/browser/快照 bake 当作活写入路径(其 B-1 机理链
  第 3 步),未追调用链;修复批 commit message 同口径。**按一路自己的
  分级标准(价值主张静默 no-op = blocking),B-2 为签核前置**。
- **定性**:继承性基础设施缺口(非本批回归;TemperatureModule 等
  reloadDefaults 的 dt reload_defaults 同样从未接线),lens 批把批价值
  建在未接线 seam 上而 plan 全程模块级 scope(T2 SC = reloadDefaults 臂 +
  表驱动测试,无 App 侧接线任务)——执行对 plan 忠实,**plan/批价值面
  缺口**。修复方向二选一:①补接线任务(图库打开/加模块时以 DecodedImage
  调 reloadDefaults 单点注入,`makeDefaultInstances` 同型);②显式降范围
  (auto-apply 值主张挂账,MANIFEST W13 行改口径)。
- **旁证**:修复批 MANIFEST 补录 W13(「browser 选型 → 渲染立即变化」)
  留人工真机——按本路代码链,该行真机走查**必然不成立**;W13b/W14 同。

## 2. 面一:B-1 修复语义攻击(修复本体 = PASS)

- **六臂 truth table 亲核(LensModule.swift:393-410 逐行)**:`enabled==false`
  臂最前(:394)→ 手动七系数 eps(1e-6)全零判定(:396-402)→ 非 `.lensfun`
  落中性(:404)→ snapshot ≠ nil 非中性(:405)→ live resolve 64×64 探针
  命中非中性/miss 中性(:409)。六臂 = `.off` 中性 / `.manual` 零滑杆中性
  (非零 → :403 非中性)/ `.lensfun`+snapshot 非中性(零 DB)/ `.lensfun`
  live 命中非中性 / live miss 中性 / enabled-off 恒中性(压过一切,含
  snapshot 在场)。`testNeutralPredicateReadsActivatedLensfun` 六断言与
  源码逐臂对应,定向轮 + 全套轮两遍绿。
- **resolve miss = 静默 identity 降级的边界**:修复批**有意保留**(DECISIONS
  F-1「免逐帧 warning 刷屏」)+ 渲染级钉死
  (`testLensfunResolveMissKeepsSilentIdentityFace`:无 DB 时 isNeutral 真
  **且**真 pipe 渲染逐字节 = 输入)。**UX 谎报面核**:`isNeutral` 与面板
  readout 同读 `matchOutcome` 单源(LensfunMatch.swift:734),miss 各面
  (noDatabase/noLens/ambiguous/missingFocal/rematch_miss)readout 全部
  如实呈现——**除一个面**:matched + 非 rectilinear entry + target 未设 =
  resolveCommitted 保守拒(nil :895-899)→ 渲染 identity,readout 仍示
  「匹配到配置」;无「需选 target 投影」提示键(xcstrings 56 键无此文案)。
  登记为 **o-B**(LENS-03 T1 既定保守拒设计,非本批回归);连同 B-2 修复
  时顺路补提示文案最省。
- **enabled==false × auto-apply**:enabled = per-document 参数,新图恒 nil
  (=true);auto-apply 写入(reloadDefaults)不读 enabled 但两者无交叉窗口
  (先写后可关;关闭 → :394 臂 identity;重开 → snapshot 臂恢复渲染;
  paramsHash 含 enabled → 缓存隔离,LENS-04 T3 钉死)。**见 B-2:该交互
  目前学术化(auto-apply 死路)**。
- **pointMapSegment 零系数守卫(:640-641)亲核**:第二 guard
  `distortionK1 != 0 || distortionK2 != 0` 使零滑杆 lensfun 文档(第一
  guard 已放行)落 nil = 蒙版 1:1 保持——B-1 不下放蒙版面,lensfun-warp
  蒙版映射 = 注释登记后续面 ✓。手动 TCA/vignette-only 档(distortion 零)
  由旧「零系数段」改 nil = 同为恒等、语义更诚实 ✓。非零滑杆 lensfun 混合
  档蒙版走手动系数(段只拼手动系数 = 既有限制,注释在位)——与渲染面的
  lensfun 系数错位为**既有限制非新缺陷**,既有注记覆盖。
- **64×64 探针尺寸无关性亲核**:`LensfunMatch.resolve` 的 nil 返回点全枚举
  = ①target 未设保守拒(:430-434)②poly3/ptlens df 简并(:452/:462)③
  `haveAny` 标定行缺席(:488)——三者均与 width/height 无关;宽高只进
  NS·HW 折叠与 center 像素换算(骑非 nil 结果)。探针取 64×64 合法 ✓。
- **消自消 golden 亲跑两遍**:`testPureLensfunZeroSliderDocRendersThroughProcessGate`
  (真 pipe process 面,零滑杆渲染 ≠ 输入 `>1e-3` + 同系数手动门逐字节
  `=0±1e-6`)+ `testUnifiedExitMatchesManual` 原丢弃臂真断言——定向轮
  (IOPParity 478/6/0)与全套轮(IOPParity 478/6/0)**双轮各跑一遍全绿**;
  反自消咬合亲核:若谓词仍吞门,door-1 渲染=输入 → viaMaxDiff=0 即 FAIL,
  无恒真式。旧 T2 union 测试重建为三臂模块级可比形(window 子窗 + verbatim
  锚 + 严格加宽断言),verbatim 锚断言消 verbatim==verbatim 假绿带 ✓。

## 3. 面二:M-1 修复独立性(修复本体 = PASS)

- **Alcedo 逐行对照**:`lens_calib.metal:219-238`
  `ApplyProjectionERectFishEye` = theta 反射骨架(±π 反射 + x+=π 双分支)+
  `s/vx/vy/r` + `theta=atan2(r, s·cos x)` + `inv_r = r<=eps?0:1/r`。Lightamer
  Metal `projFromERect kFisheye`(LensKernels.metal:164-176)与 Swift
  `fromEquirect(.fisheye)`(LensProjection.swift:156-166)**逐式同构**
  (theta2 命名替代原地重赋值,Double/float 各侧;`kProjEps=1e-8` 与
  Alcedo kEps 同量级;slot id 2 对齐)。 stereographic 臂保持 ksp 原式
  (:253-257),两臂现互异。GPL 归属:文件头 Portions Copyright + 源路径 +
  case 行注释三处在位 ✓。
- **独立数值复算(Python 直算生产式,不经测试基建)**:修复臂轴上
  r(θ)=θ 精确(1e-16 级);equirect→fisheye→equirect 往返残差 ≤2.2e-16
  (commit 申报 1.3e-15 同量级);**旧臂**(ksp 式)轴上半径实测
  +2.1%@y=0.5 / +9.3%@1.0 / +20.3%@1.4——与一路验收误差曲线一致(申报
  「+21%@1.4」为四舍五入,o-D 记差);旧臂 y=1.0 半径 1.092605 =
  2·tan(0.5) 精确值——**铁证旧臂就是 stereographic 公式逐字重复**。
- **新 golden 独立性成色**:两法均**非同源 twin**——①等距定义绝对真值
  (轴上 r=θ 含 y=1.0;离轴球面恒等式 atan2(hypot(X,Y),Z) 半径+方向)
  + stereographic 2·tan(θ/2) 对照断言(同笔转录复发即双破);②往返恒等
  双向网格(门 1e-9;错臂残差 +2.1/+9.3/+20.3% 必红)。同笔转录复发
  防线 = 绝对真值(防「错得一致」)+ 往返(防「两臂不合」)+ 既有
  kernel-vs-CPU twin(防 Swift/Metal 漂移)三层,成色充分。golden 亲跑
  两遍绿(定向 + 全套)。
- **顺手 m-1(kernle 头注释 SCALE 段)**:LensKernels.metal:53-59 已改
  D-L3-3 求值序(×1/scale 先于投影折,L2 旧面退役注记)——plan T1
  action 2 欠账清 ✓。

## 4. 面三:全套 + 定向复跑

- **guard 偏差申报(D-L4-4 同形)**:`machine-guard.sh --wait 1800` 满窗
  超时(exit 2)——G3 swap 4274MB ≥ 4GB 恒静(冷页残留,30 分钟零衰减);
  G2 可用内存 83%、G1 零并发重活亲核(无 Lightamer/xcodebuild/测试宿主
  残留)、`/usr/bin/time` ru_maxrss 机检 MEMFAIL 兜底在岗,全程峰值
  7615MB < 8G 门。与 D-L4-4(执行批 5.0G 放行)及修复批 GUI 记录
  (5.1G 同形申报)一致,放行正当。
- 构建:`xcodebuild build-for-testing` rc=0(env -u proxy 四连,SPM 解析
  坑规避);测试轮 nohup+disown+caffeinate,日志
  `acc2/targeted-round.log` + `acc2/all-run-acc2.log`;终了零进程残留
  (ps 亲核)。
- **全套轮为修复后首个 --all**:4093 = 4088(修复前四轮同值)+ 5 新
  golden,skip 40 零漂移,七 bundle 分账精确(§结论头);修复批「全套
  三轮 4088」申报 = 修复前面,如实不虚(修复批只申报定向轮,未 rerun
  全套——记 o-E 注记:修复批后未补全套轮,本路补上)。
- zh-audit `--check` PASS(1705 source keys;修复批零键变更亲核)。

## 5. 面四:bump 裁决对抗(row 9 审计 = 成立)

- **RenderProcess 零 diff 亲证**:`git diff 7f80f82a~1..HEAD` 于
  RenderProcess.swift / PixelPipe.swift / Sidecar 目录 = **零命中**;
  全链 numstat 唯一产线触碰 = Lens 族 + Decode 四件(L1 申报面)+
  SettingsPages/Shell(lensfun 设置与装 DB 路径换 seed 优先)+ Project.swift
  + BUNDLE-MAP——密封面全批(含修复笔)零越权 ✓。
- **「改动面从未生效」论据审**:
  1. 非零滑杆 + lensfun 组合:新旧 isNeutral 对该组合**同为非中性**
     (:403 guard manualNeutral else return false 两代同形)——渲染行为
     零变化,该组合存在与否不影响 bump 裁决。
  2. 真正变化类 = 零滑杆 lensfun 激活档:产线侧**双重不可达**(渲染门
     identity blit + B-2 写入路径死路)——「从未渲染过」在产线为字面真;
     开发机侧批内未签核、无冻结义务。M-1 臂同理(target/source 投影
     仅批内可达)。
  3. 缺陷修复律第三问(渲染前原位修)+ 第 7 行先例适用;row 9 裁决
     表述与机检一致。**裁决成立,维持不 bump**。

## 6. 面五:ROI 新观察复核(插桩结论亲核 = 成立,定性准确)

- **代码亲核**:roiHint 路径 `run()` :895-899 hint∩entry 后
  `forwardWalk(entry:hinted, frame:frameROI全帧)`;:983
  `dscIn = IOPBufferDesc(walked.width/height)`——**hint 下 lens 收到
  窗口尺寸 dscIn**;而 ROI 坐标系保持 entry(全帧)相对原点(窗口 x/y
  随 hint 保留)——「窗口尺寸 dscIn + 全帧坐标 roiOut」混基成立。lens
  center = dscIn/2(:uniforms bufW/2 兜底)→ 窗口锚定,与帧心错位。
- **定性判定:准确**。今日**产线零非 nil roiHint 调用点**(App 全部
  调用点传 nil;唯一 plumbing = LayerCompositeDriver)→ 现状 = 记账/
  注记级失真,零渲染影响;未来任何 hint 消费者(区域渲染/1:1 窗)落地
  时 = warp 中心锚错(**渲染正确性风险**)。附带发现:LensModule.swift
  :46-51 头注释「center stays exact under roiHint sub-windows too」对
  hint-entry 情形**不成立**(对 crop-downstream 情形成立——dscIn 恒
  全帧)——注释误导面随另案一并修。**另案立项建议成立**:登记为
  seam 前置条件(首个非 nil hint 消费者必须先修 lens 帧锚语义:
  经 piece 传全帧尺寸或新 desc 字段)。

## 7. 分级清单(第二路新发现)

### Blocking

- **B-2**(§1)lensfun 写入路径产线端到端不可达(reloadDefaults 零生产
  调用点;auto-apply/EXIF 输入/快照 bake/detected 门全死;browser 选型 =
  identity +「无镜头信息」)。修复方向二选一:接线任务或显式降范围 +
  MANIFEST W13/W13b/W14 行改口径。**签核前置**。

### Minor

- **m-5**(新)**手动门投影折叠缺席**:resolveUniforms 手动臂
  (LensModule.swift:702-708)不设 `targetProjectionRaw/sourceProjectionRaw`
  → 手动滑杆文档选 target 投影 = 渲染/ROI 面静默不折;而面板 scale
  readout 的手动臂(resolvedScalePreview :482-485)**显式设 raws 会折**
  ——同文档 readout 与渲染可能分叉(B-1 同族静默 no-op,combo 窄:
  手动系数 + 投影选型)。plan T1 SC 只承诺 resolve() 面(lensfun),
  手动门属 plan 缺角。修复二选一:手动臂补 raws 折叠,或 picker 按
  source 门控/提示。

### Observations(第二路新增)

- **o-A** isNeutral live 探针成本:零滑杆 lensfun 活解析档每次渲染最多
  3 次(resolve 无 memo,match 有 memo LRU 32)——微秒~亚毫秒级,非
  每像素,可接受;未来 mask 映射面接线时一并计。
- **o-B** matched + 非 rectilinear entry + target 未设 = readout「匹配到
  配置」而渲染 identity,无「需选 target」提示(§2;既定保守拒,文案
  缺角;B-2 修复批顺路补)。
- **o-C** DB 换装缓存陈旧(既有):活解析档渲染依赖 DB 内容而 PipeCache
  键只含 paramsHash——会话内换 DB 失效 match memo 但不失效平面缓存;
  04-04 既有语义,非本批面,登记备查。
- **o-D** 误差曲线舍入:申报「+21%@1.4」实测 +20.3%(独立复算);记账
  噪音不改判定。
- **o-E** 修复批未补修复后全套轮(申报的三轮 4088 = 修复前);本路
  4093 全套轮补位,ΔN=5 与新 golden 精确对账。
- **o-F** LensProjectionGoldenTests 文件头(:9-18)仍写「自消风险仅由
  方向断言 + RawLab 供件缓解」——M-1 修复后该风险已由等距真值 + 往返
  golden 实质缓解,头注释欠更新(cosmetic;RawLab fisheye 抽样义务不变)。

## 8. 与一路验收的分歧清单

1. **B-1 机理链第 3 步口径**:一路称「本批三条主写入路径全部不写滑杆」
   (隐含路径活)——本路修正:路径自身在产线不可达(B-2);B-1 的渲染门
   缺陷判定与修复处方**不受影响**,修复本体本路全盘认可。
2. **全套预期 4088**:为修复前口径;修复后正确值 4093(ΔN=5),本路
   亲跑证实。
3. 其余零分歧:四 minor 中 m-1/m-2/m-3 修复亲核到位(m-1 头注释 :53-59 ✓、
   m-2 folderReference Project.swift:202 ✓、m-3 BUNDLE-MAP 八行计数与
   `func test` 实数逐一相符 ✓),m-4 按登记不动 ✓;一路 obs 面无翻案。

## 9. 放行建议

1. **B-2 处置批**(签核前置):reloadDefaults 接线或显式降范围 + W13
   行为行改口径;顺路 o-B 提示文案 + m-5 手动门投影二选一。修复后
   定向 IOP/App + GUI W13/W13b/W14 真机走查(browser 选型 → 渲染变化
   应当成立)。
2. 修复本体三笔(B-1/M-1/m-1..m-3)**验收通过**;bump 裁决(row 9)
   本路对抗后**维持成立**;面五另案立项建议采纳。
3. RawLab 供件到达后 fisheye 对入抽样(一路 o-5 义务不变)。

(第二路验收完;本文件为唯一产出,零源码触碰,不 commit。)
