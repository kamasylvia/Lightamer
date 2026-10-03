# M2-10-06 DECISIONS — AI 出片可编辑副本（执行期裁决与偏离正本）

> 执行 worker 收口（2026-10-04 夜）。四个功能提交：`dba72ce`（T1）/ `b4d13d6`
> （T2）/ `7786ff8`（T3）/ 本收口提交。晨审可推翻；推翻即记 LESSONS 并开修复波。

## §1 16-bit 容器规则签注（KD-3 授权的晨审点）

「随原格式」收窄为**「能无损承载 16-bit 的同格式，否则 TIFF 16-bit」**：

| 原片 | 输出 | 依据 |
|---|---|---|
| 16-bit PNG | PNG 16-bit（`.png`） | 同格式无损 |
| 16-bit TIFF | TIFF 16-bit（`.tif`） | 同格式无损（默认腿） |
| RAW（一切） | TIFF 16-bit | RAW 容器不可写是硬约束 |
| 8-bit JPEG/WebP/HEIF/TIFF/PNG | TIFF 16-bit | 8-bit 容器回写 = 位深损失，违背 M2AI-09「16-bit」目标 |
| 不可解码源（合成字节/冷门 RAW） | TIFF 16-bit + 空 EXIF 继承 | RAW 等价腿，测试免真 RAW fixture（合成字节裁决） |

JPEG 原片出 `.tif` = 本规则的**有意偏离**（M2AI-09 字面「随原格式」收窄）。

## §2 EXIF/GPS 继承签注

exif/tiff/iptc 字典原样继承；**orientation 烘焙进像素后强制 1**（渲染契约：帧到
writer 手上已是显示正向）；**GPS 跟随原片保留**（个人工具语义）。

## §3 operation 枚举定稿

`AIProvenanceOperation: String = "upscale" | "denoise"`（D-3 六字段拼写的 operation
槽）。**未知 raw 值 = 整文档 decode 失败**（冻结值空间：真 writer 只产两值；手改文件
= 损坏，不静默重型；SidecarV8Tests 钉死）。

## §4 tile 形状族终值 + 静态资产的实测消解

- family 常量 = `{256, 512}`（TilePlanner.shapeFamily 登记；256 = manifest.inputSize
  基准）。**planner 网格基准 = 最小 supported edge**——当前静态资产下恒 256；512 =
  未来 flexible 资产的大 tile 杠杆，当前路径不消费。
- **实测消解**（plan 起草时假设 per-shape 重编译可达，M2-10-01 转换实测为静态
  1×3×256×256）：静态 mlpackage 不可重整形 → 「LRU 4 形状」不可达。落地形态 =
  **capability discovery**：worker open 从模型描述**发现** supported edges（enumerated
  square shapes → 静态 range（min==max）→ manifest fallback 三级），engine 只在
  supported 集内 plan；run 时 feed 不在集内 = typed 拒绝。未来 flexible 资产落地时
  (profile, units, shape) 会话键已有位（EnhancementSession 按 (profile, units) 持有 +
  run 时 feed 验证）。
- **sub-tile 输入（< 256）= pad-to-fit**（edge-replicate 到最小 supported edge，引擎
  裁回 valid 区）：**系统唯一 padding**——DRUNet 内部 pad-and-crop 先例（Lumen
  MODEL.md 1.1）；「不补边」指网格不补（align-last-to-edge 已保证长轴全 exact tile）。
- **金样锚**：64² 合成图 → x4 → 256² 输出走的就是 pad-to-fit 腿（真模型 golden 验证）。

## §5 400MP 预算口径（plan 算术修正）

cap 作用在**输出像素域**（Lumen `validate_size` 同型：(h·scale, w·scale) 对
400,000,000）。plan「100MP ×4 = 4 亿贴线」是像素域误读——×4 线性 = ×16 像素：
×4 实际容纳 ~25MP 输入，100MP 走 ×2 恰贴线。Typed 拒绝 + 文案已按此实现
（TileInferenceTests 钉 10001²@×2 拒 / 10000²@×2 过）。

## §6 denoise 强度语义

DRUNet 转换无强度输入 → **worker 侧 output/input 线性插值**（strength 0 = identity、
100 = 全模型输出；`AITileParameters.amount` 承载，worker blend 后写 tile）——业界惯例，
plan 风险节预告口径。upscale 恒 nil。

## §7 副本 .lra mint 形态

pristine 文档（空 history、**自有 UUID imageID**、decode hash 种子 0 中性——coordinator
首次真实编辑时重灌种）+ `aiProvenance` 单写，经 SidecarStore scheduleWrite+flushNow
原子写（L009 同目录 tmp 晋升）。D-3：原图 sidecar 零触碰（测试断言原字节 + 原无
.lra 不产生）。

## §8 importFile 孪生落位（KD-4 半句替代）

KD-4「拷入 Media/」由 **reserve_copy 直接以终名 O_EXCL 落 Media/** 替代（writer 写终
位，零二次搬移）→ twin = **注册半边**：复用 `insertRow`（row + EXIF backfill，同一内
部函数，folder 三 transport 均经它）+ 可选 album + 可选 .lra mint。零复制粘贴达成；
`insertRow` 加 `@discardableResult -> Int64`（行为零改，ImportServiceTests 10 全绿证）。
Media/ 外文件 = typed `adoptTargetOutsideMedia` 拒绝。

## §9 front-matter 外文件申报（4 个，计划正文授权 vs 清单漏列）

| 文件 | 改动 | 授权出处 |
|---|---|---|
| `LightamerCore/Sources/AI/AIWorkerProtocol.swift` | `AITileParameters` 加 height/width/amount；`AIWorkerResult` 加 tileEdges/scale（全 optional additive，帧形状零动） | plan 正文 KD-1「帧协议 `tile:{h,w}` 字段承载」+ T3 AC「worker 协议若需 tile 形状字段 = additive 且 05 测试零 diff」——越界线 = 帧级形状改动（未越；05 的 27 测试零 diff 全绿） |
| `App/Sources/Lightamer/AI/AIWorkerClient.swift` | `openEnhancement` / `enhanceTile` additive 方法 + open 响应的 facts 记账（teardown 清位） | 同上（tile 通道消费面，plan T3 action 1「worker tile 通道消费」） |
| `App/Sources/Lightamer/AI/AIWorkerMain.swift` | open 增强 leg（05 的「opens via the M2-10-06 leg」占位 error 分支退役——plan 载明 06 落地即此）+ run 分发增强会话 + stop 清会话 | M2-10-05 SUMMARY 交接节明文：「06 落地 = AIWorkerMain 增强腿 + InProcessMLModelRunner 单资产形态扩展」 |
| `App/Sources/Lightamer/AI/AIWorkerEnhancement.swift`（新建） | worker 侧 EnhancementSession（解析/编译缓存/IO 发现/tile run + TIFF16 codec） | 上行同一交接授权；headless 纪律（零 SwiftUI/AppKit import）同 AIWorkerMain |

front-matter 清单未列四者 = 起草缺口（正文与交接均授权）；改动半径各 additive，
晨审可推翻。

## §10 预览一致性 + 金样

中央 192² 预览 = 同引擎同模型单 tile（确定性一致，Lumen MODEL.md:9 数值等价依据）。
真模型 golden = **64² → 256²**（pad-to-fit 腿）经**真 worker 子进程**：tileEdges
`[256]` / scale `4` 于 open 时发现（断言）；两次运行逐元素差 ≤ 1/255；端到端 2.7s
（spawn + open + 两轮 engine + stop；编译缓存热，2.4MB mlpackage 冷编译亚秒）。
tile 推理量级正本仍 = M2-10-01 转换基准 20.55ms/tile（256²）。

## §11 M4 消歧的执行落点

AC#4「version_ref 零触碰」按 checker 消歧执行：断言对象 = **原图链零增量**（原图
字节 + 原图 sidecar 面不动，EnhanceCopyTests 断言）+ **VersionCoordinator 机制面
diff = 0**（机检：`git diff` 零 version/VersionCoordinator 文件）。副本经正常
sidecar→library 同步自有单版本行——本 plan 未触同步机制，该行为自然发生。

## §12 内存纪律的落地形态 + 100MP 风险状态

KD-2 pin（输入释放后再起 tile 循环）落地为：输入 fp32 RGBA **一次性转 uint16 RGB
工作缓冲**（模型输入域本就要 16-bit 量化）→ onInputConsumed 后才进 tile 循环；循环
持有 = uint16 输入（fp32 的 ~1/2）+ 当前 tile 帧 + **fp32 输出整帧**。100MP×4 的
fp32 输出 ≈ 6.4GB 贴 8G 门的风险维持 plan 申报；「输出按 tile 顺序直写 16-bit TIFF」
流水线化 = **E3 后手**（本波测试域全小图，MEMFAIL 门未触发；挂账 Maintenance）。
输出 TIFF 编码现走整帧 Data（`CGImageDestinationCreateWithURL` 直接写终名）。

## §13 测试宿主观察（非缺陷）

首轮 EnhanceDialogTests 全类跑出现一次宿主 mid-run `terminated abnormally`
（DrtPersistenceTests 域，AGX texture assertion 刷屏伴生）——隔离复跑 + 全类复跑
+ 全套 --all 三轮全绿，归环境型（M2-10-04/05 崩溃家族同口径）。

## §14 M-1 修复追记（验收后专项波，2026-10-04 夜间授权）

> 验收 M-1「内存姿态两处口径差」的专项修复正本。单笔
> `fix(M2-10-06)` 提交；金样链与全部 AC 语义零回归。

### 两处根因的确认（与验收口径逐条对上）

1. **fp32 输入释放 pin inert**：`runFullCopy` 传 `onInputConsumed: nil`
   且 `run(input:)` 的 `input` 参数（struct 持数组引用）在 callee 帧
   存活至返回——caller 置 nil 也释放不了，fp32 全程驻留（Debug 语义
   确定性；语言级无保证）。
2. **终段双缓冲**：归一段 `output`（RGB fp32，12 B/输出 px）与
   `rgba`（RGBA fp32，16 B/输出 px）共存 → 28 B/px；叠加 writer 的
   uint16 编码缓冲 + `Data($0)` 全帧拷贝，编码腿瞬时实达 32 B/px。

### 修复落点（a + b + c 全做）

- **a（pin 结构性生效）**：engine API 拆两阶段——`prepareInput(_:)` 
  （static，自有帧：量化完返回即 engine 侧 fp32 归零）+
  `run(prepared:)`（只持 uint16 输入 + 单缓冲累加器）。生产
  `runFullCopy` 用立即调用 `@Sendable` 闭包把 fp32 帧 + prepared 双双
  scope 在块内（闭包非隔离，量化循环不占主线程）；`onInputConsumed`
  回调迁到 `prepareInput`（语义保留：量化完即触发）。旧
  `run(input:)` 整体退役（测试 4 调用点同步改造）。
- **b（双缓冲消除）**：blend 直接累加进 stride-4 RGBA 单缓冲（16
  B/px），归一在原缓冲 in-place 除权重 + 写 alpha——RGB+RGBA 共存
  不复存在。writer 侧 `makeImage` 弃 `Data($0)` 全帧拷贝，改
  `CGDataProvider(dataInfo:releaseData:)` 所有权移交（PixelBufferContext
  box：provider 持 retain，release 回调释放堆缓冲）——编码腿 32 →
  24 B/px 瞬时上界。
- **c（大图防御）**：新 typed 错误 `memoryBudgetExceeded`，engine 在
  plan 后、**任何输出级分配前**核验
  `estimatedPeakBytes = outputPx×24 + inputPx×6`（诚实上界：16 累加器
  + 8 编码瞬时 + 6 工作缓冲），超 `memoryBudgetBytes`（默认 6 GiB =
  8192 MB 运行门 − ~2 GB 头寸）即拒——不给 OOM 炸弹按钮。400MP
  planner 上限保持绝对界，本门在其下。预算经 init 注入（测试用微型
  预算钉 typed 行为）。对话框映射诚实文案
  `memoryBudgetMessage`（预计峰值 GB vs 上限 GB + 降倍率/裁切指引）。
  **直白后果**：100MP@×2（400M 输出，est ≈ 9.6 GB > 6 GiB）在流式
  直写（E3）落地前被 typed 拒绝——验收 M-1 的「粗算 >285M 输出越 8G」
  修正为「>~268M 输出越 6 GiB 预算」（~67MP@×2 / ~16MP@×4 为当前
  准入包络）；解锁靠 E3 流水线化，不靠放水。

### footprint 实测（identity stub，12MP@×2 = 48M 输出 px，物理采样 2ms）

| 指标 | 修复前（HEAD `bbb22d1`） | 修复后 | 变化 |
|---|---|---|---|
| run 稳态 Δfootprint | 1572 MB（32.7 B/px） | **834 MB（17.4 B/px）** | −47%，与公式吻合（16 累加器 + 6×¼ 工作缓冲） |
| 全程峰值 Δfootprint | **1939 MB（42 B/px）** | **1201 MB（26 B/px）** | **−38%**；26 = 公式 24 + 分配器 slack |
| 峰值所在腿 | 归一双缓冲段 | 编码填充腿（16+8） | 与设计一致 |
| 宿主 peakRSS（App bundle 单类） | 2130 MB | 1424 MB | 含框架地板 |

探针 = 临时测试（mach_footprint 采样），数字入账后已删——本文件为
数字正本。

### 回归

- 金样 `testRealModelGolden64SquaredTo256SquaredThroughWorker` 激活态
  过（逐元素 ≤1/255 不变——stride-3→4 换道不触任何浮点数值路径）；
  身份多 tile / pad-to-fit 预览 / 取消扫描 / 进度端点全绿。
- 新增 3 永久测试：pin 触发序（`prepareInput` 回调 + 量化钳制契约）、
  typed 门先于任何 tile I/O（微型注入预算 + 零 executor 调用 + tmp
  终态空）、footprint 公式锚（常量 + 默认预算 < 8G 门 + 400M 输出
  被拒算术）。既有 EnhanceDialogTests 10 + TileInferenceTests 13 +
  EnhanceCopyTests 8 + SidecarV8Tests 5 零语义改动（engine 调用点
  机械适配）。

### 剩余挂账（E3，Maintenance）

- 输出行/块直写 TIFF 流水线化——当前 24 B/px 上界下 100MP@×2 /
  大图@×4 档仍被 typed 门拒绝；流式直写落地后同步上调
  `memoryBudgetBytes` 并放宽文案。挂 M2AI-09 Delivered 注记同源。
