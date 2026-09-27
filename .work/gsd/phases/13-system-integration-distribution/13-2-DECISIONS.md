# 13-2 DECISIONS — 执行期决策清单

> Plan 13-2（色彩完备 COLOR-02/03）执行期决策全录。纪律：RESEARCH/CONTEXT 未覆盖细节不臆造，探针/实测先行。
> 编号注：源码注释与 commit message 已引用 `D-13-2-7` 与 `D-13-2-OOG`，编号排布与其对齐。

## D-13-2-1 BPC 探针结论 = 「公开开关直用 + CMYK 降级注记」组合（T1，管线形状判定）

探针全录见 `13-2-probes.md`（v1-v8 迭代）。三选一判定：

1. **BPC：直接开关**。`kCGColorConversionBlackPointCompensation`（macOS 10.12+，
   CGColorConversionInfo.h:93）被 ColorSync 消费可证（非零黑点 ICC 对 on/off 输出分化锚，
   probes §3.2）——不做手做黑点补偿 LUT，不为 BPC 自建路径。
2. **CMYK printer ICC 判死**：四条 CG 数据转换通道（ConvertData 全合法布局 / vImage /
   CIContext render / CGBitmapContext）全部 FAILED 或语义不可信（probes §2）→ v1 软打样
   仅接受 RGB printer profile（`CGColorSpaceGetNumberOfComponents == 3` 构造期拒绝），
   CMYK 降级 + UI 注记。v2 若 ColorSync 数据通道开放 CMYK 再议（TODO 遗留对表）。
3. **引擎通道**：`CGColorConversionInfoConvertData`（macOS 15+，float32 premulLast +
   32Little；src/dst bitmapInfo 必须同 alpha/byteOrder 语义——v3 全失败的根因）。

## D-13-2-2 rendering intent v1 = relativeColorimetric-only（Swift 桥不可达 C varargs）

intent 选择性构造器 `CGColorConversionInfoCreateFromList` 是 **C varargs 函数，Swift 桥
不能调用**（probes §1；探针走 ObjC CLI 可达）。Swift 侧 proof 段只能拿默认 intent 路径 +
公开 BPC 开关。处置：`SoftProofProfile.Intent` 枚举四值全保留（持久化/UI 面前向兼容），
但构造期对非 `.relativeColorimetric` **typed 拒绝**（静默错误的模拟比拒绝更糟）——
软打样标准本就是相对比色，v1 无功能损失。saturation 在无 saturation 表的 profile 上
本就退化为 relative（probes §3.3），注记为已知限制。

## D-13-2-3 proof 段装配形状：coordinator-minted 非 registry 模块（iopOrder 69.5）

- `SoftProofStage` **不进模块注册表**（`opName = "lightamer_softproof"` 永不注册；手写
  sidecar 若携带此 op 走标准 unknown-op 降级——结构即证明）。测试
  `testStageIsNotARegistryModule` 钉死。
- 插入位 = v50 gap **69.5**（编辑 iop 群与 colorout 70.0 terminal floor 之间）——复合
  driver 的 base chain 自动落位，display 腿（colorout+gamma）零改。
- box params 恒空；profile 骑 `softProofOverride`（per-run data，L013），仅 stableID 折叠
  commit hash → 翻转只影响 proof 位及下游键，上游平面存活。
- L031 复核：无 Metal kernel、无新 GPU 提交面（ICC 变换 CPU 侧 ColorSync；纹理读写走
  标准队列 fence 后 `getBytes`/`replace`，`convertTexture` 模式；`makeRoutedCommandBuffer()`
  红线零触碰）。

## D-13-2-4 proof UI 面：视口悬浮胶囊 + View 菜单 ⌥⌘P（T4 执行期三裁决）

1. **入口** = 视口 top-trailing 悬浮胶囊（非 StatusBar）：proof ON 时塌缩面显示激活
   printer 名 + OOG 警示行，常驻可见不抢焦点；展开面 = toggle / printer picker（已装
   档案 + 最近优先）/ gamut check 开关。
2. **快捷键** = `⌥⌘P`（View 菜单同路由）：裸 `P` 已被 flag picker 占用，`⌥⌘` 组合在
   既有键位表全空闲（实测核对）。
3. **状态语义**：proofing 不自动选 printer（模拟哪台打印机是用户决定）；状态**不跨启动
   恢复**（视图模式默认 OFF）；recency 记忆去重 + 5 条上限（UserDefaults）。typed 拒绝
   （CMYK 条目 / 无选择 toggle）走 status toast，不打断已激活 proof。文案纪律：只说
   显示模拟，绝不暗示已存编辑被改变。

## D-13-2-OOG gamut check = 往返 delta 阈值判定 + 黑裁剪（T3）

- **判定形状**（probes §3.1 数值依据）：域内往返 delta ≤1e-4、超域 clip delta ≥0.066 →
  阈值取 **1e-3**（中间护栏带）。`gamutCheck` 开启时对 proof 变换后像素做工作空间→
  printer→工作空间往返比对，任一 RGB 通道 delta 超阈 = 超域，渲染黑（dt softproof
  gamut check 同语义）；域内像素保持 proof 值不动（clip 碰不到可再现色）。
- **golden 样本构成** = T1 探针锚集复用：Rec2020 primaries（R/G/B，对 AdobeRGB 超域）
  + 域内样本（black/near-black/white/midgray/greenish/skin）。ON：超域三元 →(0,0,0,1)、
  域内样本与 check-OFF proof 值逐位一致；OFF 对照：超域色**显示** proof 值（clip 是模拟，
  黑是警告）。

## D-13-2-6 多显示器事件面 = 零新代码（T5 golden 钉既有底座）

执行复核证实 D-13-CONTEXT-5 判断：通知（`NSApplicationDidChangeScreenParameters
Notification`）+ window↔screen 追踪 + per-window resolve 在 02-04 底座已全部落地，本
plan 增量 = **golden 套件钉死全行为**（4 条：profile 切换仅重渲 colorout+gamma 两平面
而上游平面缓存存活 / 双窗双屏不同 terminal hash 互不污染 / proof override 同纪律独立 /
双屏事件信号 + 窗口所在屏优先的源级接线锚）。真双屏切换实测 = Manual-Only 候补，归
13-4 走查批（需解锁控制台）。

## D-13-2-7 exact-TRC render leg 回退 deferred（T6 后 forensics，重要）

**现象**：T6 兑现 fallback 腿 exact-TRC（`linearVariantIfMatrixShaper` 重建 calibrated
linear variant 消费进 render leg）后，逐字节渲染 golden 套件出现**间歇性全黑平面
flake**，且引发 CullingPipeline 崩塌（collapse）。

**归因**（forensics 结论，源码注释正本）：colorout fallback 腿**每次 render**咨询
`linearVariantIfMatrixShaper`——无缓存时对相同 ICC 字节**每次铸造新 `CGColorSpace`
实例**；CI 腿（CIContext render）按 space **实例**键其内部状态，共享空间实例与 CI 腿的
交互被证明 **order-sensitive**；每 render 实例 churn 翻转了字节精确套件的稳定性。基线
（系统 `extendedLinearSRGB` **单例**）恒稳。

**处置**（三件，WIP 修复批落盘）：

1. `LinearVariantCache`：per-ICC-byte-hash（`StableHash.hash`）缓存解析产物与 nil
   判定（每 profile 恰一次解析、恰一个 space 实例；CG 类型不可变线程安全，NSLock 守护）。
2. render leg 回退系统 singleton workalike（`extendedLinearSRGB`）——`DisplayProfile.
   linearCGColorSpace` 与 `ColorOutModule` fallback 腿同步回退，doc comment 显式记
   deferred 理由。
3. exact-primaries 变体保留为 **parser 的 pinned capability**（XYZType 布局含 4 字节
   type signature + 4 保留字节的解析已测钉），render 集成 **deferred 至专门验证批**
   （需要 CI 腿实例语义的专项验证，非本 plan 范围可安全携带）。

**AC 降格注记**：plan T6 AC「`.colorSyncFallback` exact-TRC 兑现（ICC 字节 identity）」
——resolve **产物**携带手选 ICC 字节的 identity 断言仍钉死
（`testManualOverrideCarriesExactICCBytes`，字节身份纪律不回退）；回退的仅是 **render
消费端**的 linear 变体接线（`testManualOverrideFallbackLegIsByteExact` 同步改钉
workalike 基线）。手动覆盖的全部其它语义（precedence/clear/graceful degradation/
未覆盖屏不受扰）不受影响。

## D-13-2-8 F-12-5-2 处置 = 对照材料包备齐 + 人眼判定归 13-4 走查批（偏离 plan 原文）

plan T7 原文 =「dt-GUI 对照关闭（截图 + 台账行）」。执行修订：

- **自动替判不采**（假关闭风险）：dt-GUI 观感一致确认本质是人工对照（12 移交原意），
  无控制台解锁 + GUI 操作的自动化替身 = 假关闭。材料包备齐转移：
  `.work/gui-acceptance/13-2-f12-5-2/`（README 对照规程 5 步 + `identity.cube`/
  `gain2.cube` + `gain2-expected-linear.txt` CPU float64 期望表 + `probe-in.png`
  4×4 色块图）。
- **环境现状核查**（本批实测）：dt-cli（5.5.0+755）PNG 导出路径可跑零崩溃——L017
  损坏域为 float 导出（TIFF 32f）；dt-cli + LUT 经 XMP history 自动对照因 iop params
  base64 blob（`dt_exif_xmp_encode`）逆向成本超预算，不立。
- 12-VALIDATION Manual-Only 表 F-12-5-2 行**不改判**，转移注记归 13-4 走查批执行
  （TODO 台账同步）。Lightamer 侧数值锚（Lut3dKernelTests/Golden 12-5 已钉）免重跑。

## D-13-2-9 zh 键同批 = 14 键（L025）

T4 softproof_* 8 键 + T6 settings_displays_* 6 键，同批入 `Localizable.xcstrings`；
`SoftProofUIWiringTests` 含 L025 en/zh smoke（family 级）。文案边界：软打样/覆盖页
均为显示语义，不暗示改编辑。

## D-13-2-10 凭据阻塞项提醒（义务履行，延续 13-1 登记）

Developer ID 证书与私钥 / App Store Connect API key / GitHub 公开仓时机——13-4 排期前
必须由用户供件（本 plan 零触碰凭据面；GOAL-STATE 阻塞节由 orchestrator 汇总时同步）。

## 附：测试日志 grep 教训候选（收尾轮观察）

直启宿主全套日志含 GPU 测试的原始字节输出（`file` 判 data 混 UTF-8），BSD grep 对
binary 判定文件 `grep -c` 返 0 而非计数（`grep -a` 恢复正常：3204 Test Case 行）。
`test-direct.sh` 的 Executed 判据 grep 本轮工作正常（Executed 行成功匹配），但人工
forensic grep 必须带 `-a`。LESSONS 候选，待 orchestrator 评估立项。
