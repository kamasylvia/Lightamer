# Phase 8: HDR/Stacking & Effects iops — Research Questions

**Created:** 2026-09-27（discuss 环起草；给 research 环的问题清单，答案落 `08-RESEARCH.md`）
**输入:** `08-CONTEXT.md`（D-08-CONTEXT-1..12 + Phase Boundary）+ ROADMAP §Phase 8 + REQUIREMENTS IOP-HDR-01..05 / IOP-FX-01..05 / RAW-03
**约定:** 每条 RQ 给「问题 / 为什么 / 验证方法 / 关联裁决」。P0 = 阻塞 plan 划界的答案；P1 = plan 内可并行解决。带 ★ 的 = research 环应跑的低成本探针（本 discuss 环按纪律未跑构建/探针，零预置数字）。

---

## A. 合并/堆栈簇（P0——08-1/08-3 划界输入）

### RQ-08-1 HDR merge 数学落地细节（Robertson 权重 + 线性化前提）
- **问题**: ①权重函数终形——曝光差高斯权 σ 取值（ΔEV 域）+ 噪声帽权（帽沿位置随 ISO/快门？固定域？）；②**响应函数问题是否真不存在**——RAW 解码输出即物理线性（`RAWDecoder.swift:158-161` 保深直通），但 CIRAW 输出是否含 tone/增益预修饰（ProRAW/boost 因子）需实测确认，若含则权重域失真；③权重归一化在欠曝/过曝全零区的退化行为（全源无有效值的像素 = 信息洞，输出语义：黑 + weight-map 供 ghost/信息洞提示？）。
- **验证**: ★ 合成 bracket 探针——已知线性场景渲染 N 档 ΔEV synthetic TIFF（float32，RAW-03 读面），跑权重数学 CPU 原型，断言解析已知值容差；CIRAW 输出线性性用已知灰卡 RAW 实测两点标定。
- **关联**: D-08-CONTEXT-1、SC#1。

### RQ-08-2 MTB 对齐落地与性能（★ 关键路径探针）
- **问题**: ①MTB 位图层级与位移搜索范围（±N px、倾转 ±θ 粒度）在 100MP 的分层降采样策略（常用 8 层金字塔）；②★ 100MP 三张 bracket 的对齐全程耗时（GPU 位图生成 + 位移搜索 CPU/GPU 分工）——决定合并操作「后台批处理」还是「可等待」的产品预期；③对齐失败的判定与降级（位移超界/低纹理——报错 vs 不对齐直合并，hdrmerge 惯例对照）；④EXIF 一致性预检的豁免面（手动拍光圈漂移 bracket 是否放行 + 警告）。
- **验证**: ★ 探针——真实 bracket 样张（无则 synthetic 位移图）× 100MP 合成图，秒表 + 位移命中断言；性能数字入 perf.md。
- **关联**: D-08-CONTEXT-1、SC#1/#2（对齐是两簇共用关键路径）。

### RQ-08-3 合并产物落位与浏览可见性（P0 头项）
- **问题**: ①落位目录终判——会话根（进浏览集零疑义但污染根目录）vs `Capture/`（C1 惯例但 D-09-CONTEXT-2 排除语义下不进 grid）vs 新保留子目录（如 `.lightamer/stacks/`——不进 grid 需显式收录，违背「普通文档」语义）；②产物命名防撞（`<base>_hdr.tif` 遇同名——序号递增 vs 时间戳）；③provenance sidecar 字段终表（源路径相对化、源 StableHash 集、算法 kind/参数快照、schemaVersion）；④源文件被删/被改的产物行为（provenance 标脏 + 重合并入口 vs 只读降级）；⑤重复合并幂等（同源同参重跑 = 新文件 or 拒绝）。
- **验证**: 代码走查 `SessionTreeScanner.isExcludedDirectory` 谓词逐分支对照三种落位的 grid 可见性推演表；sidecar 字段表对照 `LightamerSidecar` additive 模式（12-1 v3 五字段先例）；无探针必要。
- **关联**: D-08-CONTEXT-11、D-09-CONTEXT-2、SC#1「continue through the normal edit pipeline」。

### RQ-08-4 ghost mask 自动生成与用户编辑闭环
- **问题**: ①共识偏离阈值的域（线性亮度域 or 权重域）+ 膨胀核尺寸默认；②自动 ghost mask 的持久化形态——是否落 `RasterMaskRef` 旁挂 PNG（`.lra.masks/` 面，Phase 7 移交①形态）vs 仅 sidecar 参数（重算可重现性 vs 磁盘占用）；③用户编辑入口——ghost mask 进 Phase 6 蒙版面（可反选/羽化/组合）的装配路径（合并文档的层栈初始态 vs 独立 mask 资产）；④de-ghost 关闭档（无运动场景零开销）。
- **验证**: 设计推演 + `RasterMaskRef`/`MaskCombiner.effectivePlane` 消费面代码走查（07 移交②）；合成运动目标 fixture 的检出率断言测试设计。
- **关联**: D-08-CONTEXT-1③、Phase 7 移交①②。

### RQ-08-5 focus stacking 度量与融合参数
- **问题**: ①焦点度量终选（modified Laplacian vs SML vs tenengrad）+ 邻域窗口尺寸；②金字塔层数/融合权平滑曲线；③对焦轨微位移的缩放差容忍（微距场景近焦源放大率略异——MTB 位移对齐是否足够，需否 homography 级）；④焦点度量读回的 L014 fence 形态（N 源度量图全驻留 vs 行流式）。
- **验证**: ★ 合成「前后景清晰度交替」fixture（两平面图合成 + 已知清晰区）跑度量 CPU 原型，断言融合结果清晰区归属；性能秒表。
- **关联**: D-08-CONTEXT-2、SC#2。

### RQ-08-6 N 源大图内存形态（★ 划界前提）
- **问题**: ①合并全程的峰值内存终形——5×100MP float32 全驻 ~8GB 不可行，行流式/分块（TilingPlan 复用面）vs 降采样中间态；②median/sigma-clipped 的排序/统计在流式下的可行形状（滑动窗口 vs 两遍）；③preview 桶先行策略（合并先在 preview 分辨率出预览文档？还是全幅一次出）——交互响应 vs 简单性。
- **验证**: ★ 内存探针——CPU 原型按流式/全驻两形态跑 5×100MP synthetic，峰值 RSS 秒表；TilingPlan 既有脚手架（Phase 3 toneequal 实战面）复用边界走查。
- **关联**: D-08-CONTEXT-10、RQ-08-12；16-2 内存事件备忘同源警戒。

## B. EDR 显示（P0——08-4 划界输入）

### RQ-08-7 EDR 显示腿形状与 SDR 不变断言
- **问题**: ①rgba16Float 切换的管线形状——终端 gamma/SDR 钳制段旁路后，display tint/D-COL2 色彩空间挂接（`EditorMTKView.swift:336-339`）在 EDR 色彩空间下的处理（extendedLinearSRGB vs 显示器原生 EDR 色彩空间的择优，13-2 LinearVariantCache 复用面）；②headroom 查询与视图失效联动（窗口跨屏拖动/EDR headroom 变化通知面）；③非 XDR 屏（headroom=1.0）开启 HDR toggle 的行为（自动回落 SDR vs 保持 float16 直通）；④「SDR off == 既有输出逐字节」断言的实现位（blit 前 texture 对比 or 渲染图快照对比）。
- **验证**: ★ 最小 MTKView EDR spike——rgba16Float + wantsExtendedDynamicRangeContent + >1.0 值直通，XDR 实屏目检 + headroom 数值打印（XDR + 外接各一次）；13-2 色彩批参考环境同源。
- **关联**: D-08-CONTEXT-12、SC#3、COLOR-4。

## C. 效果簇（P1——08-2/08-5 plan 内解决）

### RQ-08-8 grain 确定性种子与缓存键交互
- **问题**: ①seed 派生式终表（`StableHash(params ⊕ image stable id)` 中 image id 的精确键——文件 hash or stableId？换图同参 grain 图案应异）；②PipeCacheKey 是否纳 seed 派生值（漏钉 = 同参数跨图缓存假命中）；③白噪声谱形移植正本核验（`grain.c:312` 的 [-1,1] 缩放 + `noise_generator.h` 分布类型）与 midtones_bias 数学。
- **验证**: `noise_generator.h` 逐行对照 + seed 碰撞/跨图差异单测设计；缓存键假命中反例测试（同参异图 grain 输出必异断言）。
- **关联**: D-08-CONTEXT-6、L013、缓存键纪律。

### RQ-08-9 bloom 线性域阈值映射与 blur 实现择优
- **问题**: ①dt threshold（0-100 显示域习惯）→ 线性 luminance 阈值的换算曲线与默认值（无现成对照，需实测手感 + 数值锚双定）；②大核 Gaussian 实现——多 pass 可分离 vs 降采样级联（downsample→blur→upsample）在 100MP 的性能/内存权衡（MPS `MPSImageGaussianBlur` vs 手写 kernel 择优，STACK.md「MPS selective use」条款的适用判定）；③screen blend 在 >1.0 值源的语义（HDR 文档上 bloom 的行为定义）。
- **验证**: ★ blur 两实现 100MP 秒表对比；默认值手感入 Manual-Only 观感轮预定项。
- **关联**: D-08-CONTEXT-7、SC#4。

### RQ-08-10 dehaze 参数面与 scene-referred 域适配
- **问题**: ①`hazeremoval.c` 参数面终表（strength/distance/大气光自动估计开关）在 14.0 槽位（几何/色彩校正前段）的值域语义（dt 同位先例）；②box 滤波半径档位与图像分辨率的比例约定；③透射率图在 scene-referred 线性域的直接适用性（dt 原实现域对照）。
- **验证**: `hazeremoval.c` 全文走查 + kernel 表逐 kernel 对照（移植表纪律）；合成雾 fixture（已知大气光/透射率）数值 golden 设计。
- **关联**: D-08-CONTEXT-8、SC#4。

### RQ-08-11 text overlay 槽位与渲染管线
- **问题**: ①新槽位终值（66.x 段候选，避开 skinSmooth 66.5 与既有行；strip-to-93 钉测试同步扩行）；②CoreText 渲染 → 纹理的路径——`YiyinTextRenderer` 复用面核对（灰度 AA/COLOR-2 float[9] 矩阵惯例 08-2 先例）vs 独立轻渲染器；③参数面 v1 边界（描边/阴影进不进——SC#4 无字面要求，additive 位）；④挂层蒙版的合成路径验证（非终端段 + blendTriple 既有面）。
- **验证**: V50Order 全表空隙扫描 + YiyinTextRenderer 复用面代码走查；无探针必要。
- **关联**: D-08-CONTEXT-9、FX-05、SC#4。

### RQ-08-12 合并服务运行形态与队列关系
- **问题**: ①后台 Task 形态——独立 `MTLCommandQueue` 低优先级（Phase 11 export queue 惯例复用）vs 独立服务 actor；进度/取消面 API（Phase 11 队列 progress/cancel/retry 三件套同构）；②合并期间源图在编辑器打开的互斥语义（源可否同时编辑——产物与源解耦，理论上无冲突，但缓存压力面）；③失败重试语义（对齐失败 vs 解码失败分型）。
- **验证**: Phase 11 ExportQueue 惯例代码走查；流程推演即可。
- **关联**: D-08-CONTEXT-11④、D-08-CONTEXT-10。

### RQ-08-13 HDR-04 验证矩阵 + LUT 精度结论（12 移交消费）
- **问题**: ①验证矩阵终表——合并文档 × {exposure, filmicrgb, sigmoid, toneequal, lut3d} 的全链数值 parity 用例集（HDR stack torture 图 + 合成 float32 文档双源）；②preview float32 平面内存预算实测（2560px ~70MB/平面注记 vs enforceBudget 五档实测余量）；③**Phase 12 移交④/遗留#4 消费**——HDR 域 `.cube`（DOMAIN_MIN/MAX >1.0）在 rgba16Float texture3d 的精度是否达标（12-5 D7 rgba32Float 升格预案的启用判定），结论落档。
- **验证**: 测试矩阵设计 + 预算实测秒表；LUT 精度用 12-5 既有 tetrahedral kernel 对 HDR 域样本点误差测量（12-5 Golden 测试面扩展）。
- **关联**: D-08-CONTEXT-4、12-DISCUSSION-LOG 移交④/遗留#4、SC#1。

---

## P0/P1 汇总

| 级别 | RQ | 阻塞面 |
|---|---|---|
| P0 | RQ-08-1（权重数学）/ 08-2（MTB 对齐+性能★）/ 08-3（落位可见性）/ 08-4（ghost mask 闭环）/ 08-6（内存形态★）/ 08-7（EDR 腿★） | 08-1 / 08-3 / 08-4 plan 划界 |
| P1 | RQ-08-5（焦点度量★）/ 08-8（grain 种子）/ 08-9（bloom 映射★）/ 08-10（dehaze）/ 08-11（text overlay）/ 08-12（队列形态）/ 08-13（验证矩阵+LUT 精度） | 对应 plan 内并行解决 |

> ★ 探针五项（08-2 性能 / 08-5 度量 / 08-6 内存 / 08-7 EDR spike / 08-9 blur 择优）= research 环首批执行序；数字直接回填 plan 划界与 perf.md 基线。
