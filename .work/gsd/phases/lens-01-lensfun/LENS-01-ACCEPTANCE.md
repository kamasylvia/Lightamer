# LENS-01 验收报告 — 第一路独立验收(plan 忠实路线;2026-10-20)

**结论:PASS / 1 blocking + 1 major + 4 minor + 7 obs**

- 对象:22 commits 执行链(`7f80f82a..16030b8b`,HEAD `16030b8b` 亲核零漂移)+
  CONTEXT/4 PLAN(checker `cb2cb5e8` 放行版)/ LENS-PLAN-REVIEW(1B+6M+10m)/
  四 DECISIONS+SUMMARY / 全套四轮 --all 日志 / evidence repo。
- 方法:零源码改动;全部结论以产线源码 + 机器执行亲验为准(22 commits 逐
  diff --stat、密封面全仓 numstat、grep 门逐条、测试方法 99 法全列 + ~12 法
  深读、全套 --all 独立复跑一轮、GUI 实机启动走查)。
- 全套独立复跑:**`TOTAL|4088/40/0|` rc=0**(与申报三轮同值,第四轮;IOP
  752/5/0 peak 6509MB + IOPParity 474/6/0 5856MB + Layers 494/5/0 812MB +
  Library 738/4/0 626MB + Sessions 284/9/0 1203MB + Export 385/5/0 4957MB +
  App 961/6/0 2832MB;峰值 max 6509MB < 8G 门,零 MEMFAIL,skip 40 = 37 基线
  + probe 3;对账 3991+97=4088 精确)。

---

## 1. Blocking

### B-1 — `isNeutral` 渲染门使本批全部主交付面在 App 内对零滑杆 lensfun 文档不可达(渲染恒 identity)

- **机理链(全部产线源码亲核)**:
  1. `LensModule.isNeutral`(:382)= **只看手动滑杆存储**(distortionK1/K2/
     tcaR/tcaB/vk1..3 全零 = neutral;`source` 与 `snapshot` 均不参与判定)。
  2. `process()`(:742)首先 `if isNeutral(committed) { blitIdentity; return }`
     ——**纯 lensfun 文档(滑杆全零)恒走 identity blit**,`resolveUniforms`
     的 lensfun 臂(snapshot 消费/memo live resolve)、scale、投影、ROI union
     全部不可达;`modifyROIIn`(:522)与 `pointMapSegment`(:617)同门。
  3. 本批三条主写入路径全部**不写滑杆**:browser 选型
     (`LensProfileBrowser.selectedParams` 只置 source+lensKey)、auto-apply
     (`reloadDefaults` 只置 source+lensKey+resolve 输入)、快照 bake
     (`bakeCommitted` 只置 snapshot+sourceProjection)——选型/自动应用/快照
     齐备后渲染仍是 identity。
- **测试为何全绿(自消结构,m8 同型)**:全部 lensfun 渲染断言要么**直接调
  `resolveUniforms`**(绕过 process 门:LensSnapshotTests H-L2 门、
  LensScaleGolden/LensProjectionGolden 直传 uniforms)、要么**手工置非零滑杆**
  (LensParityTests unified-exit 的 vigLens/vigManual 两门都抄入 resolved vk)、
  要么**渲染产物被丢弃**(`LensParityTests:363` `_ = (via, man)` ——纯
  lensfun 零滑杆门的 render `via` 无任何断言);T2 union 测试双臂在
  isNeutral 门下同为 verbatim ROI,三断言(`<= w+2` / `>= w-4` / 面积
  `> (w-1)(h-1)`)在 verbatim==verbatim 时**同样全绿**——false-green 构造。
- **继承性裁定**:该门 04-04 即在(cb2cb5e8 同形 isNeutral + process 门),
  非本批回归;但 04-04 的已验收面是「滑杆非零 + source=.lensfun」混合流,
  **本批三交付物(auto-apply / browser 选型 / H-L2 快照)的目标人群恰是零滑
  杆文档**——批价值主张(选型即校正)在 App 渲染面为静默 no-op。GUI
  MANIFEST W3/W6/W7/W8 的渲染变化行对该人群全部不成立(执行批内这些行标注
  Manual-Only 留真机,等价面全部是门下测试——与 B-1 自消结构一致)。
- **处方(修复批)**:①`isNeutral` 增 source==.lensfun 臂(snapshot≠nil ∨
  DB 可解析命中 → 非 neutral;.off/manual 语义不变,红线 12 默认中性不受
  扰);②补**全管线纯 lensfun 非恒等 golden**(process 级,非
  resolveUniforms 级)+ T2 union 测试改双臂可比形;③GUI MANIFEST W3/W8
  重配 方,修复后真机复走;④B-1 修复属渲染行为变化面,按 RenderProcess
  bump 纪律补一条裁决记录(预期「缺陷修复原位收」,同 L4 裁决表第 7 行先例)。

## 2. Major

### M-1 — fisheye-from-equirect 转录错:Lightamer 的 ERect→Fisheye 臂是 Alcedo 的 Stereographic 公式

- **证据(Alcedo `lens_calib.metal` 与产线逐行对照)**:
  - Alcedo `ApplyProjectionERectFishEye`(:219-237)= theta 反射 + 等距
    (equidistant)径向式;Alcedo `ApplyProjectionERectStereographic`
    (:304-309)= `ksp = 2/(1+cosφ·cos x)`。
  - Lightamer `LensProjection.fromEquirect(.fisheye)`(:147-150)与 Metal
    `projFromERect` kFisheye 臂(LensKernels.metal)写的就是 **ksp 立体式
    公式**——与自家 kStereographic 臂**逐字相同**,注释却标 "Alcedo
    ApplyProjectionERectFishEye"。toEquirect 四型转录全部正确(逐行核)。
- **后果**:fisheye-source 折叠(defish 用例:lensfun entry
  `<type>fisheye</type>` + target rectilinear——本特性主用例)采样按立体
  式反演,径向误差随角度放大:y=0.5rad → +2.1%、y=1.0 → +9.3%、y=1.4 →
  +21%。正确臂可与自己 toEquirect 往返恒等(Alcedo 原式验证 ≈0),错臂
  往返残差即上值——**往返恒等是修复后的判据 golden**。
- **为何 golden 没抓到(与 B-1 同型的自消)**:LensProjectionGolden 的 CPU
  twin = 「同源公式 Double 版」——Swift CPU 面与 Metal kernel 同错同源,
  kernel==twin 恒真;唯一真独立对账(RawLab 抽查)延后供件(见 o-5)。
  `testFisheyeToRectilinearFoldDirection` 只验方向不验值。
- **处方**:①Swift + Metal 双侧按 Alcedo 原式重转录;②补等距真值/往返恒
  等 golden(门沿 D-L3-4 分层:折叠域 2e-3);③o-5 的 RawLab 抽查补做时
  把 fisheye 对列入抽样点。

## 3. Minor

- **m-1**:`LensKernels.metal` 头注释 :53-55 的 SCALE 段未随 L3 修订——仍写
  「×1/scale 施于映射后采样偏移(after distortion/TCA)…×1/scale last」,
  与 L3 实码(:247-249 scale→projection 先于畸变半径)及 D-L3-3 裁定直接
  矛盾。L3 T1 action 2 明文「头注释钉死求值序修订」——修订只落在行内注释
  与 commit message,头注释漏改。修复批顺路改 4 行。
- **m-2**:`Resources/Licenses` folderReference 缺席——plan L3 T5 明文
  「Resources 两条 folderReference」,Project.swift 只加了 Lensfun 一条;
  许可文本(51KB)在库不在 bundle,bundle 级归属面缺角(GitHub 源分发形
  下 repo 文件仍满足归属,但与 plan 文面不符)。补一条 folderReference 或
  DECISIONS 显式降范围。
- **m-3**:BUNDLE-MAP 逐文件方法数与套件终态漂移(LensAutoCropTests 行 6
  vs 实 7、LensScaleGolden 3 vs 4、LensProfileBrowser 8 vs 7、
  LensfunDistribution 7 vs 6、LensDefaultNeutral 2 vs 3)——17 文件全部在
  册(防孤儿目标达成),仅计数 stale;后批触碰时顺路同步。
- **m-4**:LENS-02 T5+T6 并入单 commit(`cfb048c5`,plan 为 T5 docs + T6
  test 收口两 commit)——红线 15「每任务独立 commit」轻微偏离;两任务均
  docs-only,实害低,登记备查。

## 4. Observations(偏差判等 + 审查结论)

- **o-1 D-L4-2 快照形态 = 标定提取(判:等价或更优)**:偏离 X3 字面形态
  (15 float kernel-ready)。X3 字面形态自相矛盾——kernel-ready 系数含
  NS·HW 分辨率相关折叠(M4 自家分析),跨平面尺寸必错渲;提取形态才同时
  满足 H-L2 与尺寸无关。已声明、推理充分、配套 Codable 化已核。
- **o-2 D-L3-3 求值序 + D-L3-4 分层门(判:合法,头注释欠账记 m-1)**:
  求值序按 plan 自带风险节裁决器(「以 Alcedo 实序为准」)落 Alcedo 实序,
  与 action 2 字面序的冲突是 plan 内部张力,执行选择了 plan 钦定的裁决器并
  申报;分层门(投影折 2e-3 vs plan 1e-5)是明文「禁放宽」下的申报放宽,
  机理(erect↔rect/tan 链一阶导放大 float 噪声,实测 2.07e-4)+ 判据(残差
  随 tan 梯度缩放)成立,接受;但 M-1 证明该门对「转录错」不设防——门只
  防实现错不防转录错,与 m8 预判一致。
- **o-3 D-L2-1 autoScale 默认 nil=false(判:正确)**:plan 字面 nil=true 与
  红线 12 + L4 T2「scale 默认 1.0」不可同真;执行取中性默认并留了执行中
  nil=true 实测 pincushion golden max-rel 1507 红的实证。申报规范。
- **o-4 D-L4-4 G3 放行 + D-L4-5 flake 作废(判:等价终形)**:G3(swap
  5.0G≥4G 门)放行有 orchestrator 预授权 + MEMFAIL 兜底 + 三轮全门内
  (7657MB)实证;我的独立轮 swap 3.95G 在门内,无需放行。Library flake
  作废轮:与本批零域交集亲核(22 commits 无 Library 域文件)、单测 3x 复
  绿、弃残轮取净轮——M2-11 恢复协议同形。注:SUMMARY 轮次标签与日志文件
  名不精确(净轮实为 092311/103359/111404,作废轮 100303;SUMMARY 写
  101717/113746)——记账噪音,数字本身四轮一致。
- **o-5 RawLab 延后供件(判:申报诚实,非静默跳过)**:ENVIRONMENT-GAP 记
  录在 evidence repo(`lightamer-evidence/lens-01-lensfun/
  rawlab-sampling-ENVIRONMENT-GAP.md`),尝试链(host libraw 0.22.1<0.22.2、
  pinned 源缺席、brew upgrade 越权不做)+ 复跑配方可操作;落点从 plan 的
  主仓 evidence/ 改 evidence repo(已声明)。**m8 预警已应验**:同笔转录
  自消风险兑现为 M-1——供件到达后 fisheye 对必须入抽样。
- **o-6 越带 +9 审查(判:申报理由成立,非虚胖)**:预算 4050..4079 → 实
  4088(+97:L1 36/L2 33/L3 20/L4 8)。99 法全清单 + ≥30 法抽查(深读
  ~12 法):crop gate 双臂、m5 相机 crop 位级回归、40/60 分档词子集构造、
  memo 尺寸无关(scanCounter)、H-L2 卸载位恒等、strip-on-hash 带标定漂移
  阳性对照、GPU 逐字节默认中性——每方法单断言面、零恒真式;越带集中于
  评审追加矩阵(M6 四构造点、m10 容错、m5 回归),预算线低估而非灌水。
  L3 带内(20∈16..26);L2/L4 分账张力已在 L4 DECISIONS 申报(归属约定,
  批总量精确)。
- **o-7 GUI 行为级(环境受限,可核面已核)**:实机启动构建产物 ✓;bundle
  携带钉版快照(folderReference 纪律在构建产物中兑现)✓;**首启 seeder
  实跑落盘 56 xml 5.1MB、SHA 与仓 pin 抽样一致**(`~/Library/Application
  Support/com.kamasylvia.lightamer/Lensfun/version_1-seeded`)——L3 T3
  行为级 ✓。面板/Settings 交互 = 本环境点击全惰(M3-3-03 §6 三路对照 +
  M7-1 AX 限制双先例在案;AI-sheet 点击、System Events 面板导航均不动),
  W1..W12 Manual 行留人工;B-1 修复后 W3/W6/W7/W8 需按新基线重配。

## 5. 逐任务判定(22 commits 机器检全过)

| 任务 | commit | 判定 | 关键机检 |
|---|---|---|---|
| L1-T1 | `7f80f82a` | PASS | 勘误③零产线 diff(CaptureMetadata 全批零触);`focalLength35mm`/`lensMake` 恰一声明;`focalLengthIn35mm` 零命中;decodeParamsHash 覆盖结论对照 HistoryHash:148-175 属实 |
| L1-T2 | `00a6ac5e` | PASS | 恰四产线文件;EmbeddedGeometryState Core 单源;四构造点全带实参(RAW 条件分支/退役腿+TIFF 两腿 notApplicable);探针有界 walk(depth1/4096/8)+ 双入口 + 窗口语义 + 容错不 throw;`isDNGUTI` 无-tag 桶落 unknown(D-L1-3 合 X1 保守语义) |
| L1-T3 | `1d961771` | PASS | 阈值 60 单声明;`crop: entry.cropfactor` 零残留,resolve 实参=相机 imageCrop(m5 回归位级);uniqueCameraCrop 唯一命中;X4 优先链(f35/focal f>0 守卫>camera>nil);零漂移负测;(超面触碰 DNGOpcodeProbe String-Codable 已申报) |
| L1-T4 | `e9d9ecb7` | PASS | memo 键=匹配输入 FNV-1a(无宽高)、LRU 32、stamp 失效、打分锁外;跨尺寸命中测试 |
| L1-T5 | `ed059c6e` | PASS | stub 零残留;LensPanelReadout 静态键状态机含 nil-未判定 + 冻结键集;body 纯(task(id:));(超面 LensMatchedProfile public 化已申报 D-L1-7) |
| L1-T6 | `6108b1d9` | PASS | docs + BUNDLE-MAP;数组登记随批落(红线 5 同批要求) |
| L2-T1 | `cc58d643` | PASS | gated 单点;中性谓词 enable 臂;零漂移负测;toggle 不触滑杆存储 |
| L2-T2 | `a5d22c70` | PASS | 恰一键 lensfun.autoApply + AGENTS.md 登记;typed 缺席=false;注入式 reader 恰一消费;notApplicable 唯一生效域双负例 |
| L2-T3 | `5a406820`+`99e40c88` | PASS | LensAutoCrop GPL 三件套;kernel 单处 diff + 半径约定注释零改;scale=1 逐字节恒等 golden;yM 回归修复且有 62×62 钉死测试两度拦截(D-L3-2);crop_bounds/CIRCLE 零命中 |
| L2-T4 | `895fa64f` | PASS | Apply 退役零残留;detected 确认门(取消零变);低置信 40 档不自动入选维持;browser 打分模型层缓存 + 去抖 |
| L2-T5/T6 | `cfb048c5` | PASS(带 m-4) | zh-audit 双 PASS(本验收复跑仍 PASS);AGENTS.md 键登记行在 |
| L3-T1 | `5ed54541` | PASS(带 M-1/m-1) | 8 槽枚举 3 预留显式;硬拒解除双臂(target 未设保守维持);投影×auto-crop 折入 edgeSample(M5 收口);CPU golden + coincident 恒等;**fisheye 臂转录错 = M-1** |
| L3-T2 | `fd1618e0` | PASS(带 B-1 注) | resolved 面三通道 union 实现正确(edgeSample R/G/B AABB union);manual 面维持理由申报;**union 面对纯 lensfun 文档被 B-1 门拦,测试 false-green** |
| L3-T3 | `091e2ac9` | PASS | 56 xml + README(SHA/日期/unmodified)+ per-file manifest;folderReference 构建产物亲核;优先序四态;SHA 篡改拒;customPathKey 零改;**seeder 行为级亲验(实机首启 56 文件落盘 SHA 一致)** |
| L3-T4 | `00204d4f` | PASS | NOTICE N/O/P 三条目;许可文本 50.9KB;fixtures README 交叉链接;(Licenses 不入 bundle = m-2) |
| L3-T5 | `626c0e09` | PASS | docs;三测试文件落域正确(m3 处方:Distribution 落 App) |
| L4-T1 | `87ca36c1` | PASS(带 B-1 注) | bake 恰二处(reloadDefaults :355 / browser :585)+ Re-match 单入口;strip-on-hash 带阳性对照;H-L2 卸载恒等(门下);LightamerSidecar 零 diff;(LensfunDB Codable 化已申报 D-L4-2) |
| L4-T3 | `be85ec89` | PASS | on/off 翻转 + nudge + dbTag 不翻 + 无关 iop 负例 |
| L4-T2 | `aff1269b` | PASS | 八项×三问裁决表含 M3 第七项;不 bump 机检 = RenderProcess 全批零 diff(亲核);默认中性 GPU 逐字节 golden 对 |
| L4-T5 | `ef6c8ca2` | PASS | probe 族 skip 3 申报;绝对 ms + 相对倍率(distortion 32.7ms/projection 15.5ms 0.47x/memo 200x);--all 四轮同值(含我独立轮) |
| L4-T6 | `16030b8b` | PASS | ΔN 总账 97 精确;偏差汇编完整 |

**密封面全批零 diff 亲核**:FIX2③ McpServerController / RenderProcess(=
不 bump 机检)/ LightamerSidecar / DrtPanelModel·View·Record / TerminalTail
Policy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / 导出
矩阵三件 / NodeGraphCommand / HistoryStack·Hash / PipelineDocument /
V50Order / GradeCatalog / Registry / ModuleInstance / CaptureMetadata(勘误
③)——全仓 numstat 唯一 kernel 触碰 = LensKernels.metal(L2 scale + L3 投
影两处申报面)。

## 6. 复跑与环境记录

- 独立 --all 轮:guard PASS(swap 3.95G 门内)→ build-for-testing(rc=0,
  与 HEAD 同源核验:最后源码 mtime < 二进制 mtime)→ test-direct --all,
  nohup+disown,日志 `.work/gsd/phases/lens-01-lensfun/acc1-all-run.log`,
  PID 全程自持、终了零残留。
- zh-audit `--check` + `--self-test` 双 PASS(HEAD 复跑)。
- GUI:构建产物实机启动;AI-sheet/菜单导航 = 环境级点击惰(先例在案),
  零杀非自出进程;探针 app 实例已清理。

## 7. 放行建议

1. **B-1 + M-1 修复批**(可同批:B-1 isNeutral 臂 + 全管线 golden +
   bump 裁决注记;M-1 双侧重转录 + 往返恒等 golden)→ 修复后定向
   IOP/IOPParity + GUI W3/W6/W7/W8 真机复走 + RawLab 供件到位补 fisheye
   抽样。
2. m-1..m-4 随修复批顺路;obs 面无需动作。
3. 本批 22 commits 的逐任务 SC 面全部机器达标、越带申报成立、密封面零越
   权——**除 B-1/M-1 外可签核**;B-1 为签核前置(渲染主价值静默 no-op),
   M-1 为签核前置质量缺陷(主用例数学错误)。

(验收完;本文件为唯一产出,零源码触碰,不 commit。)
