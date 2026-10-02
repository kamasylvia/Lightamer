# M2-9-02 DECISIONS — 执行期裁决与平台发现签注（2026-10-03 夜间批）

> 正本 = M2-9-02-PLAN.md（checker 回注版，E7/E8 处方在案）。本文件签注执行期
> 悬决点 + 平台实测发现。晨审可推翻；推翻项隔离在单一决策点（各条注明回改位）。

## §1 KD-1 的 CalibratedRGB 面死亡 → 自建 ICC 字节路径（plan 机制替换，语义保持）

KD-1 原文「`CGColorSpaceCreateCalibratedRGB`（primaries 表 + gamma 分量）」在
macOS 27 实测**不可用**（L053①）：生成 profile 非合规（wtpt=原始色度而非 D50
PCS 三刺激 / bXYZ=(32768,1,-32768) / 三 TRC 同偏移），CI/ColorSync 转换全坏
（probe2-probe8：sRGB 灰 → 0 或补色；ICC hexdump 确认）。替换实现保持 plan 的
**语义**（primaries 按 space + 幂 gamma 按 EOTF + D50 PCS）：自建 ICC v4
matrix-shaper 字节（Bradford 原白→D50 适配 + chad + curv-1 TRC）→
`CGColorSpace(iccProfileData:)`（deprecated 警告在案、行为正常，13-2
exact-TRC parser 同款依赖）。plan 自己的备选面「ICC 数据路径」的启用。

- **锚值**：rec709 臂 rXYZ=(0.436035, 0.222488, 0.013916)——与 Alcedo 自带
  `rec709_bt1886.icc`（GPL 只读行为对标）**逐位一致**，p3_d60 臂同样逐位一致；
  与 Apple 系统 sRGB profile 常数 (0.4360747…) 差 4e-5（双方 Bradford 常数精
  度差，测试锚用前者 + s15Fixed16 半 LSB 容差）。
- **TRC 取式**：`para` fn=0 被 ColorSync 误解析（跨 profile 转换塌缩 0/1，
  probe13 对照矩阵），改 `curv` count=1（u8Fixed8，2.2→563/2.4→614/2.6→666
  原码钉死）；TRC 解码行为六臂实测精确（0.7297^γ 逐臂 ≤1e-3 命中）。
- **KD-1 bt1886 取式裁决**（plan 预留）：Lb=0 → 纯 2.4 幂（M2-6-1 DECISIONS
  §D2 终式；u8Fixed8 载体量化 2.39844 为 ICC 格式地板）。
- **xyz+gamma26 裁决**（plan「xyz→XYZ primaries 常量」）：R=X/G=Y/B=Z 基在
  **矩阵面**恒可表达（= 单位矩阵 + E 白 Bradford 适配）；退化的只是 xy 色度
  表示（CalibratedRGB 构造器路径，probe2 实测腐蚀）。自建字节路径下 plan 原文
  可实现且已实现——锚 XYZ=(0.997787, -0.009750, -0.007431) 等。viewport 面
  （m2-6-3 D2 的 Rec709 降级近似）与本面偏差如实并存（DECISIONS 记录，不改
  viewport 字节冻结面）。
- **KD-1 linear 条目裁决**：linear/gamma18 不在任何 legalEOTFs 集 → typed
  拒绝（T1 测试规格「legal 集 = 成功 + 非法组合 typed」+ 穷举纪律括注的直读）；
  KD-1「linear：各 space 的线性变体」条目按**未激活配方**记录在案（13-2
  linearCGColorSpace 同族，V2 若开放 DRT-linear 导出即取此式）。回改点：
  DrtOutputColorSpace.swift 各 space 的 linear 臂。
- **测试容差勘误**：plan「primaries 读回 ≤1e-6」在 s15Fixed16 存储地板
  （1/65536≈1.5e-5）上不可达；测试改为对**量化后常数**以半 LSB（7.6e-6→取
  1/65536/2）容差断言，语义等价（存储精度 = 断言精度）。

## §2 peak-ICC 边界（KD-1 v1 面）

peakLuminance 不入 ICC：渲染消费在 EotfBox record 内、入队校验归 M2-9-03；
ICC 标注只承 space+TRC。真 HDR 容器（peak 注记）= V2 UltraHDR（ALCE-02）。
DrtOutputColorSpace 无 peak 参数位（有意缺席，非遗漏）。

## §3 TIFF 32f DRT 档语义边界（KD-2）

「输出编码即 DRT 编码」字面执行：DRT 联动档 TIFF 32f = **DRT EOTF 编码值
float32**（PQ/γ2.2 编码值，非 legacy 档的 scene-linear）。scene-referred
TIFF 手作需求 = legacy 五空间档保留可达（drtOutput=nil）。E2E 钉：
testHDRDrtExportClampsToUnitRangeThroughTIFFFloat32（PQ 值域 [0,1] 钳）+
testDrtExportSDRToTIFF32fIsFullPrecision（非 8-bit 格栅 = 尾平面 float32）。

## §4 HDR 系统空间实测选择（KD-1 预留执行裁决）

- rec2020+st2084/hlg → `kCGColorSpaceITUR_2100_PQ`/`_HLG`（系统名探针 OK，
  ICC 13300/7156B，identity 转换通过）。
- p3d65+st2084 → `kCGColorSpaceDisplayP3_PQ`（可用；m2-6-3 D2 viewport 先例
  同选）。p3d65+hlg 不在 legal 集（legalEOTFs）→ typed 拒绝。
- 系统profile desc 名实测："Rec. ITU-R BT.2100 PQ"（E2E ICC 名断言锚）。

## §5 E7 哑值语义签注

`Built.target` 在 DRT 腿 = `.sRGB` 座位填充（ExportColorSpace 枚举体零臂）；
真实编码消费以 `Built.drtEncoding`（新载体，tuple `(space, eotf)?`，默认 nil
= legacy 面）与 `exportTargetOverride` 为准。既有 `target` 消费点（日志/诊断
面）在 DRT 档读到哑值——无生产消费者读它做色彩决策（exit 腿走
coloroutOverridden + exportTargetOverride）。

## §6 队列递缝 = TaskLocal（contract 零 diff 约束下的唯一 per-job 通道）

ExportQueueContract.swift 文件级零 diff（红线）⇒ `ExportJobContext`/
`ExportJobSnapshot` 均不可加字段 ⇒ per-image `drtTails` 无法经 leg 参数面
`(snapshot, context)` 送达默认生产腿。落地 = `ExportRenderer.jobDrtTail`
（@TaskLocal，`routesToExportQueue` 同款零缺省姿势）：actor `execute` 在 leg
派发**内侧**包一层 `withValue(queued.drtTail)`（detached task 不继承
TaskLocal，必须在派发内），renderStage 以 `request.drtTail ?? jobDrtTail`
消费（显式字段优先）。**AC7 枚举面（pump/cancel/retry/generation/concurrency）
零触碰**——execute 的 wrapper 是载体递送接线非引擎语义；M2-9-04 的
`queue.enqueue(drtTails:)` 由此面完整可达（T2 queue E2E 以像素 parity 证）。
回改点：若晨审偏好 contract 加字段（放弃零 diff）可换 ExportJobContext 载体。

## §7 runDrtTailLeg 旗标传递 = PixelPipe 第 4 hunk（AC6 枚举增补申报）

KD-3 四处 additive 之外，`runDrtTailLeg` 需把 `tailFormatFloatOverride` 拷给
尾管道（tailPipe 自建、产出终平面；`tailPixelFormat` 在**尾管道**上求值）——
不传递则缝死。与既有 `tailPipe.terminalTail = .drt(params)` /
`isDrtTailLeg = true` 同类 additive 接线，同文件同函数；AC6 的「仅 additive
属性 + 一行 consult + 签名增参」枚举以此增补为四处→五 hunk（全部 PixelPipe
文件内，front-matter 在册）。

## §8 E2E 文件字节不稳发现（→LESSONS L053③）

ImageIO/ColorSync 对**自建**嵌入 profile 的写出重序列化：同渲染两次像素逐字
节相同而 PNG 文件不同（iCCP 块内等长早偏移漂移、时敏——4 轮复现 1 次）。队列
递缝证明改为**像素 parity（maxDiff==0）+ profile 名恒等**；ICC 载体字节确定
性由 T1 纯函数层钉（copyICCData 相等断言）。文件字节恒等断言只对系统 profile
嵌入面使用（nil-carrier 测试保持字节稳定断言，sRGB 系统面实测稳定）。

## §9 测试增量 23 vs front-matter 预估 25（-2 偏差）

T1=10（42 组合行为合并进 2 法：legal 集解析 + accept-set==legalEOTFs 全域
对表）、T2=9（builder 5 + E2E 4）、T3=3、T4=1。断言数远超方法数（42 组合、
六臂 TRC、primaries 3×3 锚各自并入复合方法）。BUNDLE-MAP 行：10/5/8（文件
method 数终态）。

## §10 工作区滞留（非本批）

`.work/gui-acceptance/09-3-tiers-*.jpg` 两文件改动 = 前波遗留（M2-8-3 收口
已在案），本批零触碰不提交。活体夹具 `input/RAW/DSC00012.ARW.lra` 本批未消费
（全部 E2E 用合成 decodeLeg 或自写 sidecar），零相关故障。
