# M2-9-02 SUMMARY — ICC=DRT 强制联动渲染链（wave 2a）

**Status:** COMPLETE（2026-10-03 夜间；执行 = ZCode subagent worker，
`[gsd]` `paused=false / auto=true` 全程未动——每任务边界复查）
**提交链:** `e87b25e`(T1 ICC 映射) → `951d85c`(mluc strOff 小修复，申报见
DECISIONS §1/§9) → `48a7136`(T2 chain/renderer/queue 载体) → `ef3a70b`(T3
尾格式覆写缝) → `4ceee3b`(T4 yiyin×DRT E2E)。**不 push。**
**对账底稿:** 同目录 `M2-9-02-DECISIONS.md`（CalibratedRGB 平台缺陷证据链 /
E7 哑值 / TaskLocal 递缝 / runDrtTailLeg 增补 hunk / iCCP 重序列化发现）。

## 数字对账表

| 项 | 基线（M2-9-01 终态） | 本波终态 | Δ |
|---|---|---|---|
| Export bundle | 288/1/0 | **311/1/0**（192s，peakRSS 6747MB < 8G 门） | +23（10+9+3+1） |
| Layers bundle（管线消费面门） | 298/3/0 | **298/3/0**（22s）零漂移 | 0 |
| 全套推算 | 2611/16/0 | 2611 + 23 = **2634/16/0**（未跑全套——T 门 = Export + 管线消费面 Layers；IOP/IOPParity/Library/Sessions/App 零源码触碰〔PixelPipe 增参全默认实参 = 编译兼容零路径〕，对账留验收批） | +23 |

- **测试增量 23 vs front-matter 预估 25**（-2，偏差入 DECISIONS §9）。
- 定向轮逐次：T1 `DrtOutputColorSpaceTests 10/0/0`；T2 `ExportDrtChainTests
  5/0/0` + `ExportDrtTailE2ETests 4/0/0`（后 4 轮复跑稳定）；T3
  `ExportDrtTailE2ETests 7/0/0` + DrtTailTests `12/0/0` +
  AIMaskPlaneFormatTests `3/0/0`（display 零漂移门）；T4
  `ExportDrtTailE2ETests 8/0/0`×4。
- 每任务边界 `[gsd]` 开关复查 = 全程 `paused=false / auto=true` 无变更。

## 任务逐条（commit × 验收）

| 任务 | commit | 交付 | AC 覆盖 |
|---|---|---|---|
| T1 | `e87b25e` | `DrtOutputColorSpace`（穷举无 default 映射 + Bradford D50 自建 ICC v4 写出器 + 实例缓存；HDR 系统名三臂；legal 集 = legalEOTFs 精确镜像）+ 10 测试 | AC3/5 铺底 |
| — | `951d85c` | mluc strOff 28 修复（T2 profile 名 round-trip 断言抓出；转换面不受影响） | — |
| T2 | `48a7136` | `exportDrtChain`（verbatim records + identity 面 + E7 哑值/`drtEncoding` 载体）+ Request.`drtTail`/`jobDrtTail` TaskLocal 递缝 + ExportJob/enqueue 载体 + renderStage 分派（step4 切换/step6 terminalTail/step7 identity/step8 零动）+ 9 测试 | AC2/4/7 |
| T3 | `ef3a70b` | `tailFormatFloatOverride` 缝（PixelPipe 属性 + consult 一行 + runDrtTailLeg 传递 + RenderPipeline 两入口 + LayerCompositeDriver 透传——checker E8 第四处）+ ExportRenderer 接线 + 3 测试 | AC6 |
| T4 | `4ceee3b` | yiyin×DRT 并存 E2E（HDR record 下 band=post-EOTF 白/内容=PQ 码/canvas ×2 宽/ICC 仍 DRT）+ iCCP 重序列化发现入账 | AC4 |
| 收口 | 本文 + DECISIONS + LESSONS L053 + GOAL-STATE | 机检 + 三件套 | AC1/2/8 |

## 双登记闭环（AC8）

- `Project.swift`：`DrtOutputColorSpaceTests` / `ExportDrtChainTests` /
  `ExportDrtTailE2ETests` → `LightamerTestsExport`（3 行）。
- `M2-4-0-BUNDLE-MAP.txt`：同批三行（EXPORT 10/5/8）+ M2-9-02 增行记录注
  （运行期总数基线上移至 2634；对账以各行 method 数为准）。
- 新 Core 源文件 1（DrtOutputColorSpace）走 `LightamerCore/Sources/**` glob；
  新测试文件落盘后 `tuist generate`（L041 顺序纪律）。

## AC 逐条（8/8 机检）

| # | AC | 机检结果 |
|---|---|---|
| 1 | 既有测试族零修改全绿 | `git diff 30d9bbf..HEAD -- Tests/` = 恰 3 个新文件零既有改动；Export 311/1/0 + Layers 298/3/0 全绿 |
| 2 | Quantizer/Contract/exportChain 体零 diff | Quantizer/Contract `git diff` = 空；ExportChainBuilder 全 diff **零 `-` 行**（纯 additive） |
| 3 | 穷举无 default + 非法 typed | DrtOutputColorSpace `grep "default:"` = 0；accept-set==legalEOTFs 全域测试（42 组合） |
| 4 | 四景出图 | SDR/HDR/TIFF32f/yiyin 并存四测试 + queue 递缝 parity 全绿 |
| 5 | HDR 值域 [0,1] | testHDRDrtExportClampsToUnitRange（min≥0/max≤1/finite/非退化） |
| 6 | 覆写缝 additive + display 零漂移 | PixelPipe 7 hunks（属性/consult/runDrtTailLeg 传递/两签名——DECISIONS §7 申报第 4 hunk）+ Driver 2 hunks；DrtTailTests/AIMaskPlaneFormatTests 零改全绿 |
| 7 | 队列引擎体零 diff | ExportQueue 4 hunks = Job 字段/enqueue 增参/循环头/execute TaskLocal wrapper（pump/cancel/retry/generation 零触碰——DECISIONS §6） |
| 8 | 0 fail + 双登记 | 311/1/0；Project.swift 3 行 + BUNDLE-MAP 3 行 + 增行注 |

## 偏差与发现（全部入 DECISIONS，逐条有据）

1. **CalibratedRGB 平台缺陷**（DECISIONS §1，L053①）：macOS 27 生成的 ICC
   非合规、转换全坏——KD-1 的机制面替换为自建 ICC v4 字节（Bradford D50 +
   curv-1 TRC），锚值与 Alcedo 资产逐位一致；`para` fn=0 被 ColorSync 误解析
   （同矩阵 curv 对照精确）→ TRC 全走 curv count=1。
2. **mluc strOff 小修复**（`951d85c`）：T1 写出器的 desc 字符串偏移错位
   （20→28），T2 的 ICC 名 round-trip 断言抓出；转换面无影响，单文件一行。
3. **队列递缝 = TaskLocal**（DECISIONS §6）：Contract 零 diff 红线下 per-job
   载体唯一通道；execute 一处 wrapper hunk 申报（AC7 枚举面零触碰）。
4. **runDrtTailLeg 传递 = AC6 枚举增补**（DECISIONS §7）：第 4 hunk（尾管道
   产出终平面，不传则缝死），与 terminalTail copy 同类 additive。
5. **iCCP 重序列化**（DECISIONS §8，L053③）：自建 ICC 嵌入写出文件字节跨渲
   染不稳（时敏）→ 队列递缝证明 = 像素 parity + profile 名；字节恒等断言只在
   系统 profile 面保留。
6. **yiyin 测试两处修正**：sidecar 漏写（pristine 面，disk-truth 语义抓出）+
   band 断言换 HDR record（SDR γ2.2 编码白 ≡ 显示白，无法证明 post-EOTF；
   PQ 下 tone-map 白 ≈0.75 码 vs paint 白 1.0 可分辨——与 DrtTailTests 同法）。
7. **xyz+gamma26 落地**：plan 的「XYZ primaries 常量」在矩阵面实现（单位矩阵
   + E 白适配；xy 色度面才退化）——D2 viewport 先例的降级近似未被导出面跟随
   （两 face 偏差如实并存，DECISIONS §1）。

## 交接（M2-9-03/04 消费缝）

- `ExportRenderer.Request.drtTail`（直接渲染面）+ `ExportQueue.enqueue(
  drtTails:)`（队列面，per-image 索引）——04 装配点构造 `DrtTailParams(
  record: effectiveDrtRecord, postOpNames: NodeOwnershipCatalog.drtPostOpNames
  ∩ 启用集)` 后任选一面；queue 面经 `jobDrtTail` TaskLocal 完整可达（像素
  parity 证）。
- `Built.drtEncoding` / `exportTargetOverride`——03 的元数据腿（EMBED=嵌入
  该 ICC / OMIT=后处理剥离）与命名腿接线；`ExportVariant.embedICC` 消费在 03。
- `variant.drtOutput` 非 nil = 强制联动开关（02 已按 `drtTail` 载体消费，
  04 装配时两者同 record 注入）。
- **未跑全套**：IOP/IOPParity/Library/Sessions/App 零源码触碰（PixelPipe 增
  参全默认实参，编译已过；Layers 全量零漂移佐证零路径），全套对账留验收批
  （推算 2634/16/0）。
