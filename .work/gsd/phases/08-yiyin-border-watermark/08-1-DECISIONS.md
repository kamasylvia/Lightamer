# Plan 08-1 Decisions（执行期决策记录）

> 依据 plan 纪律：RESEARCH/CONTEXT 未覆盖的实现细节一律标注**执行期决策**落本文件，不臆造。
> 每条含：决策 + 依据 + 影响。编号 D-08-1-N（代码注释引用同名）。

## D-08-1-1: 联合布局记录协议缝 = 模块侧惰性纯函数计算 + override 注入缝

**决策**：08-1 不做「终端段子 run 组装时统一计算一次」的协调器；`BordersModule.process/modifyROI*` 从 `piece.dscIn` + committed params + 空 rows **就地调用** `YiyinLayout.layout`（纯函数，O(1) 算术，无 IO），另留 `jointLayoutOverride: YiyinLayoutRecord?` 注入口（8-2 段内组装时可注入联合计算结果；sourceImageSize 不匹配 dscIn 时丢弃回退本地计算）。
**依据**：布局数学是几十次浮点运算，「每段一次」的协调器在 8-1（rows 恒空）无收益；两模块各自从 dscIn+params 推导的结果天然一致（同一纯函数）。
**影响**：8-2 激活 rows 时要么继续各自计算（watermark rows 由其自身注入 override），要么起用 override 缝——接口已就位，无破坏。

## D-08-1-2: 种子恒等 = 参数谓词直判，绝不走 yiyin 公式

**决策**：`isNeutral(Params)`（rate≥100 / margin 0 / aspect nil / !landscape / radius≤0 / shadow≤0）直接命中 blit 恒等路径；`modifyROIOut` 在 neutral 时原样返回。布局公式本身**逐字保留 yiyin 的 ceil 语义**（含其浮点 quirk）。
**依据**：yiyin 公式在 rate=100 也可能扩画布（实测 58×7 → ceil(7×(58/7)/7) 边界样本 → canvas 59——node harness `tiny_ceil_quirk_58x7` 钉）；种子恒等（轨 B 逐字节）不能依赖公式巧合。
**影响**：`YiyinLayoutTests.testYiyinCeilQuirkIsPreserved` 在纯函数层钉公式保真；模块层由参数谓词保证恒等。非 neutral 但几何巧合恒等的输入也由 `isIdentityRender(record)`（记录级真值）兜底 blit。

## D-08-1-3: borders 永不分块（tileHalo = tileWorkingSetBytesPerPixel = 0）

**决策**：显式声明两项为 0（协议扩展默认值，覆写仅为钉住决策）。
**依据**：borders 是**画布扩张**型终端模块——tile 驱动的同尺寸 read/write 契约无法表达画布扩张（每个 tile 会整支重跑 proxy+blur 腿）；其辅助工作集（proxy 2048 长边 + IIR planes ≈ 数百 MB 瞬时）**自限于 proxy 长边**，与输出幅面无关，不满足「按输出像素计费」的分块判据。plan 的「proxy 平面与模糊中间面折进 borders piece 辅助平面记账」以「记账声明为 0 + 理由文档」兑现。
**影响**：FULL 全幅带印框时 borders 整支执行——窗口化渲染（生产常态）有界；全幅 FULL 的内存/耗时档案入 8-3 perf.md 观察项。

## D-08-1-4: 投影 σ 映射 = shadowBlurPx × 0.5

**决策**：σ_shadow = 0.5 × ceil(mainH) × shadow%/100。
**依据**：yiyin 网屏 canvas 的 `shadowBlur` 语义 ≈ 2σ（CSS 规范的阴影高斯 σ = blur/2）；×0.5 与 D-08-CONTEXT-6 的模糊腿定标同族（同为 CSS/盒模糊→高斯 σ 的线性换算）。yiyin shadowColor = rgba(0,0,0,1)（全强度黑），合成以 alpha=模糊 SDF 覆盖度压暗。
**影响**：`testShadowBandDecaysMonotonically` 钉方向；观感档位 8-3 GUI 轮复核。

## D-08-1-5: 模糊腿 proxy 形制 = 等比降采样 + 归一化上采样；σ 的 proxy 折算取纵向比例

**决策**：proxy = 输入平面等比降采样（长边 2048，`proxyDims`，小于 proxy 不放大）；合成 kernel 以**归一化坐标**采样 proxy（线性滤波，clamp_to_edge）铺满画布。σ_proxy = σ_canvas × (proxyH / canvasH)（纵向映射）。
**依据**：yiyin 原实现是 `fit:'fill'` **拉伸到 3025² 方形**再 boxblur 再拉伸回画布——方形拉伸是其实现 quirk 而非视觉规格；等比 proxy + 归一化采样在重度模糊下观感等价（L017 分流：模糊背景不做位图 parity）。aspect reset 使画布与主图纵横比不同 → 上下采样各向异性，取纵向比例（bgH 参与定标式）为记录在案的近似。
**影响**：DC 增益=1 平场门不受影响；观感容差带项，Manual-Only 表登记（8-3）。

## D-08-1-6: 亮度统计 = CPU 读回 16×16 盒平均（同步 fence）；档位映射先编码后平均

**决策**：模糊模式且 `adaptiveBackdrop` 开时，对输入平面做 16×16 盒平均降采样，commit 后 `waitUntilCompleted` 同步 fence（测试 harness 同款 drain 模式），CPU 读回求 RGB 均值；均值经 sRGB OETF 编码回 0-255 尺度后查四档表（yiyin `:31-42` 逐字阈值）；档位灰度再 linearize 到显示域以 alpha 0.2 叠加（线性域合成）。
**依据**：yiyin 的均值在 8-bit **编码域**逐像素 (r+g+b)/3——线性平面无法逐像素等价，取「均值后编码」近似（均值对 ULP 噪声稳定，1024 样本平均）；Metal reduce 方案（另一候选）省一次 GPU→CPU 同步但多一套 reduce 基建，v1 不引入。**已知代数差**：yiyin 是「编码域上 mix」，我们是「线性域上 mix」——重度模糊背景下差异在观感容差带（Manual-Only）。
**影响**：`testOverlayTierBoundaries` 表驱动钉档位；`testAdaptiveOverlayLightensDarkBackdrop` 全管线钉数值预测（0.0592）。

## D-08-1-7: 模糊 proxy/成品的缓存键 = 输入纹理对象身份（ObjectIdentifier）

**决策**：proxy 缓存键 = `ObjectIdentifier(输入纹理)`；成品（模糊平面）键 = 同一身份 ⊕ σ bits。**不**做像素内容摘要。
**依据**（实测迭代过程）：初版对 16×16 探针做量化桶 FNV 摘要，实测同一 CIImage 的两次渲染在桶边界上翻样本（CI 渲染 ULP/dither 抖动，GUI-22 同族），键跨 run 翻转 → 假 MISS；而假 HIT（内容变更键不变）在任何量化粒度下都是正确性风险。改用纹理对象身份后语义**精确**：管线自身缓存保证「上游不变 ⇒ 同一缓存平面对象」（PREVIEW 政策缓存中间平面；测试以共享 PipeCache + 稳定 imageID 复现生产形态），参数编辑恰是命中面；新图 = 新 imageID = 新平面对象 = 必然重建。失败方向安全：身份不匹配只造成一次多余重建。
**影响**：`testContentAddressedProxyCache` 以生产缓存形态钉语义（参数编辑双命中、换图重建）；跨 imageID 的内容去重（同内容不同图）不在此层做（管线级 GUI-22 memo 域）。

## D-08-1-8: 大 σ 模糊 = √N 多 pass 分解（σ/pass ≤ 50）

**决策**：`passes = ceil(σ_proxy / 50)`，每 pass σ = σ/√N，ping-pong 于 proxy/blurred 两平面；总 σ 严格等于定标式输出（方差可加：N×(σ/√N)² = σ²）。
**依据**：D-08-CONTEXT-6 定标式在 amount=100 时给出 σ ≈ 0.5×bgHeight（2560 画布 → σ 1280），远超 Deriche IIR 的验证包络（dt 消费者上限 radius 500 → σ ≈ 85，shadhi.c:69）；超大 σ 单 pass 实测病态（初测 blur 腿 23.8s）。分解后每 pass 落在包络内，总模糊量不变。
**影响**：初测 blur 腿仍重（Debug 全链 ~7-9s/帧级数字见 SUMMARY——含 PSO 冷与 CI 解码干扰，正式 benchmark 在 8-3 perf.md）；观感微调（含公式系数复核）按 D-08-CONTEXT-6 的「观感 benchmark 微调允许」在 8-3 进行。

## D-08-1-9: 层内几何纪律的实现口径 = 现有机制 + 提取保证 + L021 背板

**决策**：不改 `layerGeometryViolation` 的槽位集合（13/15/16/17，plan 纪律「不新增机制」）；钉一条测试证明 borders 在 base 链合法且槽位拒绝器未变。「borders 仅允许终端段/base」由三重既有机制保证：① 终端段提取（`splitTerminal`）把 borders 从一切层面向的链中移除（T1 路由测试）；② 层子 run 的 L021 ROI 一致性 precondition 会在画布扩张进入层链时立即触发（防静默错绘）；③ UI 层链编辑器本就不提供 borders（8-2 面板同样不提供）。
**影响**：如未来需在层链优雅拒绝 borders（报错而非崩溃），在 8-2/后续把 borders 槽并入拒绝集合——一处改动，机制不变。

## D-08-1-10: 编辑种子含 borders（与 D-08-CONTEXT-4 的调和）

**决策**：`editingDefaultInstances()` 加入 `BordersModule.Params.neutralSeed`（enabled，identity 参数）。
**依据**：plan T1 action 5 明示「编辑种子（identity 参数）」；D-08-CONTEXT-4「新图不自动挂默认印框」禁止的是**自动施加印框观感**（yiyin 的 iot 启动即生效语义）——identity 种子渲染逐字节等于无实例（轨 B 测试钉），不施加任何观感，仅为 8-2 面板提供可驱动实例（exposure-0EV 惯例，与 skinSmooth/liquify 同构）。
**影响**：无——默认链观感零变化；面板（8-2）驱动该实例即为「用户显式添加」语义的载体。

## 执行期实测备注（非决策，供 8-2/8-3 消费）

- **PREVIEW 拖动初测**（Debug、1706×2560 合成图、首次 PSO 冷、含每迭代 UUID 全 miss 的管线重建——数字只记不设门）：solid ≈ 247-267ms；radius+shadow ≈ 278-378ms；blur+overlay 首测 23.8s → √N 分解后仍 ~160s（Debug 全链含 CI 解码干扰 + 21-pass；模块腿级分解：proxy+blur ≈ 7.3s、composite ≈ 1.8s @ 5.4Mpx 画布）。**正式 benchmark + 观感定标在 8-3 perf.md**；SC 门 = 真机拖动。
- **CI 渲染平面 ULP 抖动**（GUI-22 同族）实测再次确认：同 CIImage 两次渲染的逐样本桶哈希会翻边界样本——任何内容级统计键都须平均化或干脆不用（D-08-1-7 即此教训的产物）。
