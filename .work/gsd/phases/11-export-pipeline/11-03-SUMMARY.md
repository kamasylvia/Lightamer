# Plan 11-03 — SUMMARY（渲染腿：EXPORT 材料化 + 队列路由 + 无头 ExportRenderer + yiyin 导出 E2E，W3）

> 执行：2026-09-26，ZCode executor subagent worker（11-01/11-02 同款协议）。
> 基线全 suite **1220/6skip/0fail** → 终轮 **1235/6skip/0fail**（314.1s，净增 15）。
> 未 push；每任务边界检查 `.work/config.toml [gsd]`（全程 auto=true/paused=false）；
> 构建 `caffeinate -dis` 包裹 + 新文件 `tuist generate` 后入构建；单测全走
> `Scripts/test-direct.sh`（零弹窗）。

## 任务表

| 任务 | 交付 | commit | 证据 |
|---|---|---|---|
| T1 队列基建 | `MetalContext.exportCommandQueue`（NEW property，D-15 兑现）+ `@TaskLocal routesToExportQueue` + `makeCommandBuffer` 单点路由 + `PixelPipe.blit` 收编 routed seam + `ExportPipeTests` 队列段 | `0ec8f7e` | 3 tests：双队列不同实例（`!==` 身份）+ 包裹/解包裹/退域三态 buffer 队列身份（`makeRoutedCommandBuffer` seam）+ **结构化子任务传播**（`Task {}` 继承 TaskLocal；`Task.detached` 不继承——语义钉，11-04 runner 用结构化树）；编辑路径零染 |
| T2 导出链组装 | `ColorOutModule` additive `adobeRGB/proPhoto/rec2020` + `exportTargetOverride` 插座 + `CIContextPool.convertToEncodedTexture`（L029 行序修复版）+ `MetalContext.exportPool`（R8）+ `ExportChainBuilder`（gamma 必剔 + colorout 改写） | `afb8b3f` | 3 tests：gamma 剔除精确（含禁用 record）+ record 集合保序 + override 空间双态（display-TRC / linear 变体 + 无线性 ICC typed error）+ **sRGB 0.5→187-188 已知点**（测试侧矩阵+TRC 参考数学 ±2.5/255）+ 五色域中性恒中性 + 32f 线性变体 1e-5 不弯 + 管尾 float32（编辑链 .bgra8 对照）；全套回归绿 |
| T3 .export 激活 | 双 stub 删除（`run`/`runSub`）+ 输入面（line 0）export 零缓存旁路（`renderInputPlane` 提取共享）+ `LayerCachePolicy.export` + uncached final 非 float 尾格式新分配 | `5f261ef` | 2 tests：尺寸五向量（长边/短边折算/原尺寸/永不放大/nil）+ 共享缓存 totalBytes 恒 0 + misses==0（walk 不 probe）+ FULL 同缓存输入面仍入缓存（对照）+ 梯度角点内容 + **composite 激活**（+1EV 调整图层 runSub @ .export，缓存仍 0）；`MultiResolutionTests` stub 契约翻转（`testExportRunsActivatedAndCachesNothing`）；全套 1228 绿 |
| T4 无头 ExportRenderer | `ExportRenderer.swift`（sidecar 读盘→chain→boxes→override→yiyin 注入缝→routed render→出口→量化→编码→原子晋升→取消清理）+ `ExportChainBuilder.coloroutOverridden` + `debugFenceQueue` seam + **管线 scratch 尺寸缺陷修复** | `fb5b044` | 5 tests：全链 round-trip（48×32/ICC sRGB/DPI 300/**sidecar 被消费**【+1EV vs pristine 逐字节不同】）+ resize 五模式向量（E2）+ 取消删净（typed .cancelled + 无半成品）+ R8 队列身份（pool fence == exportCommandQueue）+ E3 双态出口锚（恒等 ±1e-6 vs working-space 转换 0.7354 反向） |
| T5 yiyin 导出 E2E | `ExportRendererE2ETests` yiyin 段（注入器 = YiyinE2ETests.wireYiyinContext 镜像） | `fb5b044`（与 T4 同批） | 2 tests：**双尺寸（2560/4096）归一化布局记录相等**（20+ 字段真比较：canvas/origin/offset 2px 带 + 行字段 32px 带【绝对 30px pad quirk 量化边界】+ 主图 aspect/画布主图比/行数/内容高/offset 比例 1.6）+ **4 态矩阵**（双关 == 基线逐字节；仅框画布增长 + band 暗底 + 无白字；仅水印主图 targetSize + 字节异基线；双开 band 上白字 ≥30px 经编码→解码存活） |
| T6 收尾 | 本文件 + DECISIONS(12) + TODO + PROGRESS log + LESSONS L030 | T6 本提交 | 全 suite **1235/6skip/0fail**（314.1s） |

## Verification 对照

| 验收面 | 判据 | 结果 |
|---|---|---|
| 队列基建 | `Scripts/test-direct.sh 'ExportPipeTests'` | ✅ |
| 导出链组装 | 同上（T2 段） | ✅ |
| .export 激活 | 同上（T3 段）+ `MultiResolutionTests` | ✅ 6/6 |
| 无头全链 | `Scripts/test-direct.sh 'ExportRendererE2ETests'` | ✅ |
| yiyin E2E | 同上（yiyin 段） | ✅ 7/7 |
| 回归 | 全 suite 0 fail（1220 → N） | ✅ **1235/6skip/0fail** |

## 执行期发现（新知，均已入 DECISIONS/LESSONS）

1. **管线 scratch 复用缺陷（L030，本波最大收获）**：`nextScratchPlane` 两槽
   无条件复用——画布增长模块（borders）在 uncached 腿把输出截断成主图尺寸；
   FULL 增画布为同型潜伏（两波未暴露：yiyin E2E 全走 PREVIEW 缓存管线）。
   修复 = 尺寸感知复用 + ping-pong 交替保留 + 前置断言诊断增强。
2. **TaskLocal 与 `Task.detached`**：路由不跨 detached（Swift 语义正确）——
   11-04 job runner 必须结构化并发包裹（D1）。
3. **`tuist generate` 每波新文件必须重跑**（glob 在 generate 期固化）——T1 首
   轮 0 tests 假绿假象（旧容器）即此因。
4. **主图尺寸与 settings floor 的 1px 分歧**：`targetSize` 向下取整 vs pipe
   round 数学在奇数分数短边差 1px → borders `sourceImageSize` guard 会优雅
   降级（band 缺失）→ renderer 侧以 pipe 同款数学复算 mainImageSize（D6）。
5. **yiyin 行布局绝对 30px pad**（08-3 已知 quirk）在非整数倍双尺寸（1.6×）
   下进入归一化比较——行字段独立容差（32px）+ 其余 2px 带的分层口径（D12）。
6. **测试侧出口路径冲突**：五态渲染同 stem 同目录互相覆盖（ExportNamer 零
   撞名 = 行为正确）——E2E 落点隔离由调用方负责（与 11-04 的 occupiedNames
   目录枚举对齐）。

## AC 自检（plan 验收标准逐条）

- [x] exportCommandQueue = NEW property（D-15 兑现，`!==` 身份锚）+ TaskLocal 路由**零 iop 调用点改动**（makeCommandBuffer 单点 + blit 收编同一 seam；queue: 备选未触发，R7 关闭，DECISIONS D1）；编辑队列零染断言（解包裹三态）
- [x] gamma 必剔（含禁用 record 精确断言）+ colorout 保留 target 覆写（OQ-11-2）：五色域 display-TRC 版 + TIFF 32f 线性变体（线性不弯 1e-5）；转换恰一次（出口 identity 消费 + working-space 双态反向锚 + 矩阵/TRC 参考数学 ±2.5/255）
- [x] PixelPipe .export 双 stub 激活：entry scale = targetSize 长边（永不放大五向量）+ no caching 语义（totalBytes 恒 0 含输入面 + composite policy.export + walk 不 probe）+ 三既有管线零回归（全套绿 + FULL 输入面缓存对照）
- [x] 无头 ExportRenderer：disk sidecar→instances（09-4 读盘法）→yiyin 无头注入→渲染→出口→编码→tmp 同目录原子晋升全链；取消 typed .cancelled 删净；decode leg 缝可注入（dual-size 用例注入 4320×2880 合成图）
- [x] yiyin 双尺寸（2560/4096）归一化布局相等（20+ 字段，行字段带 30px pad 容差）+ 4 态矩阵（双关==基线逐字节红红落实）+ 有印框全链 round-trip（渲染→出口→编码→解码 band/白字像素断言）
- [x] 全 suite 0 fail（1235/6skip）；每任务独立提交（T4/T5 合并批，见偏离）+ 边界查 config 开关 ×6；不 push；SUMMARY + DECISIONS 落盘

## 新增测试计数

ExportPipeTests 8（队列 3 + 组装 3 + 激活 2）+ ExportRendererE2ETests 7 + MultiResolutionTests 净 0（stub 契约原地翻转）= **15**（1220 → 1235）。

## 遗留 / 移交下波（非阻塞）

- **11-04 接线清单**：`ExportQueue` actor 实现件消费 `ExportRenderer.render`（结构化并发包裹 `withValue(true)`，D1）；生产 yiyin 注入器（App 侧 `injectYiyinRunContext` 语义镜像 + YiyinLogoStore faces，D7）；`occupiedNames` = 落点目录枚举（E2E 冲突教训）；`ExportRenderArtifact` 真载荷。
- **Phase 15 perf 清算**：双尺寸导出耗时未记（plan 只记不设门口径，本轮未落 perf.md——4320×2880 双渲染 ≈10s/两尺寸 Debug 实测量级）。
- **convertTexture 休眠镜像**（11-02 L029 移交项）：本轮 export 腿用新
  `convertToEncodedTexture` 完全绕开，11-05 收口批处置不变。
- **模糊腿 Release 复测**（08-3 遗留 #5）：维持 11-05/Phase 15 记录口径。
