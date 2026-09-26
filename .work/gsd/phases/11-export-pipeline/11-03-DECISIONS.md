# Plan 11-03 — 执行决策（DECISIONS）

> 执行期决策边界（plan 纪律）：RESEARCH 未覆盖 / API 事实与 plan 字面冲突 /
> 实测暴露的实现细节在此登记。编号 D1..D12 按产生顺序；体例照 11-01/11-02。
> 全部为 11-03 范围内决策（标注可逆性）。执行日 = 2026-09-26（macOS 27.0 / M4）。

## D1: TaskLocal 路由选定（queue: 备选未触发）；`Task.detached` 不继承 = 11-04 约束

R7 备选判定：`@TaskLocal` 挂 actor 静态 + `nonisolated makeCommandBuffer` 组合
**零障碍**（3 测试钉：包裹/解包裹/退域三态队列身份 + 结构化子任务传播），
`queue:` 参数方案不启用——iop 调用点与 dispatch 签名双双零改动。
**语义钉**：TaskLocal 随结构化子任务（`Task {}`）传播，**不跨 `Task.detached`**
（detached 设计如此）——11-04 导出 job runner 的渲染任务树必须结构化包裹，
detached 提交 = 静默回落编辑队列（测试已反向锚编辑路径身份）。
附带收编：`PixelPipe.blit` 是 dispatch 面外唯一直取 `commandQueue` 的点，改走
同一 routed seam（tile 驱动 FULL-only，但路由在类型层保持为真）。
Reversibility: 高（TaskLocal 关闭即全量回编辑队列）。

## D2: colorout 覆写插座 = 实例级 per-run DATA（`exportTargetOverride: CGColorSpace?`），双 fold 入 hash

「导出组装器改写 record target，不改参数 schema」的落地形态分两层：
① **record 层**（配置）：`OutputProfile` additive 三 case，paramsData 决定
hash 主身——gamut 身份入链；
② **socket 层**（per-run DATA，L013「注入非配置」）：`exportTargetOverride`
携带**精确 CGColorSpace**（display-TRC 变体或 linear 变体——同一 gamut 两种
TRC 风味无法用 record 单值表达，由 variant 位深决定）。
precedence = export override > displayProfileOverride > params（导出渲染永不
跟随屏幕）。hash fold 两次（resolvedTarget stableID + override 自身 stableID
【ICC 字节/名字】），linear/display 风味切换必翻 keys。socket 在 `apply` 之后
设置并 re-commit（renderer/测试同款形状——与 coordinator 的 displayProfileOverride
时序约定一致）。
Reversibility: 高（socket 独立成员）。

## D3: export colorout 转换 = 新 `convertToEncodedTexture`（L029 修复版姊妹），绝不消费 `convertTexture`

L029（11-02）：`CIImage(mtlTexture:)` 底向上读 → 裸 CI 腿垂直镜像；
`convertTexture`（显示 fallback 腿）同病未修（11-02 D6 移交）。导出链禁入
→ 新姊妹腿 `convertToEncodedTexture`：同 fence 纪律 + `.oriented(.downMirrored)`
行序复位 + 任意目标空间（display-TRC / linear 变体一腿通吃）。显示腿
`.colorSyncFallback` 分支原样未动（零回归红线；其 sRGB workalike 语义是
显示域契约，导出域不共享）。
Reversibility: 高（新函数，旧函数未触碰）。

## D4: additive OutputProfile 三 case 走 ColorSync 精确路径；不加 Metal 矩阵族；空间映射复用 `ExportColorSpaceMapper` 单点

RESEARCH §3.2 裁决维持：导出全色域走 ColorSync（任意 profile 免手写矩阵，
10-30ms@2560 导出可接受）。`.adobeRGB/.proPhoto/.rec2020` record case 无
override 时也解析为各自 display-TRC 空间（record 单独使用语义自洽）。
`ColorOutModule.displayTRCSpace` 直接复用 `ExportColorSpaceMapper`（五空间表
单一事实源；Terminal→Export 文件级引用同模块可接受，避免第二张表漂移）。
Reversibility: 高。

## D5: 无 colorout record 的非标链 = 出口腿全权转换（`coloroutOverridden` 旗标）

裁剪 record 集合可能无 colorout（自造 seed）。此时 pipe 输出 = working space
线性 Rec2020，出口腿若仍恒等（source==target）会把线性值当编码值嵌错 ICC
= 系统性色偏。`Built.coloroutOverridden` 旗标驱动 renderer 的
sourceColorSpace 选择：有覆写 = target（恒等，E3 消费面）；无 = WorkingSpace
（11-02 默认出口面）。E2E 以 pristine 导出（override 空 records）实证。
Reversibility: 高。

## D6: yiyin mainImageSize = renderer 侧以 pipe 同款 round 数学复算，不用 settings targetSize 直传

`YiyinExportSettings.targetSize` 短边 `.rounded(.down)` vs `PixelPipe.run`/
`renderToTexture(longEdge:)` 的 `.rounded()`：奇数分数（如 2880×2560/4320）
下短边差 1px → borders `sourceImageSize == size` guard 失配 → 联合布局优雅
降级（band 预留丢失，08-3 移交项 #1 的导出触发面）。renderer 用与
`injectYiyinRunContext` 逐字相同的 `min(le/fw, le/fh, 1.0)` + `.rounded()`
复算入口平面（coordinator 镜像语义，plan「严格镜像 entry scale」的字面兑现）。
Reversibility: 高（纯计算点单处）。

## D7: yiyin 注入 = `ExportYiyinInjector` 闭包缝（Core 不 import IOP——D-03 边界）

`injectYiyinRunContext` 生产实现依赖 `ModuleBox<WatermarkModule>` 具型 +
`YiyinLogoStore` faces——LightamerCore 无法命名（Core 零 IOP 依赖红线）。
renderer 定义 Core-only 注入缝（boxes + records + mainImageSize + capture →
Void；ModuleBoxing 全 Core 面），`variant.yiyin && injector == nil` 抛
typed invalidParameter（静默丢印框 = 最恶性静默失败，显式报错）。测试供
YiyinE2ETests.wireYiyinContext 镜像；**生产注入器 = 11-04 App 接线**
（EXIF/logo provider/联合上下文逐件镜像 coordinator）。
Reversibility: 中（缝形状冻结后 11-04 只是实现件）。

## D8: `LayerCachePolicy.export = (false, false)`——composite 全链零缓存补全

实测发现：`.fullColdLayer` 缓存 composite prefix（256 长边小图即 +24KB，
全幅导出即 GB 级驻留）——违反「导出面缓存 totalBytes 恒 0」红线。新增
export policy（prefix/layerOutputs 双 false）供 `processComposite(.export)`
使用；PREVIEW/FULL policy 未动。
Reversibility: 高（新常量）。

## D9: 管线 scratch 复用缺陷修复（`nextScratchPlane` 尺寸感知）——FULL 同型潜伏一并消除

见 LESSONS L030。两槽 ping-pong 无条件复用 → 画布增长模块（borders）输出被
旧尺寸槽位截断（negotiated-ROI 前置断言在 watermark 位 trap）。修复 = 复用
判据含尺寸（不匹配重分配该槽）+ `scratchFlip` 交替语义保留（输出永不别名
上游刚返回平面）。FULL + 增画布模块（zoom/全幅出片）为同型潜伏——08-1 起
未暴露因 yiyin E2E 全走 PREVIEW 缓存管线。前置断言补 opName + roiOut/roiIn/
upstream 形状三元组诊断（本轮定位提速的关键）。
Reversibility: 无关（纯缺陷修复，行为面 = 契约面）。

## D10: `MultiResolutionTests.testExportThrowsTyped` 契约翻转 = stub 激活的计划内代价

Phase 2 钉的「EXPORT run 抛 .notImplemented」测试在 T3 激活后两 XCTFail 双红。
原测试的存活不变量（export attempt 缓存零驻留）保留并升级：改写为
`testExportRunsActivatedAndCachingNothing`——真渲染（16×16 + 全幅两腿）后
`totalBytes == 0`。同一文件原地翻转，计数净 0，历史契约由本文件注释 +
11-03-SUMMARY 追溯。
Reversibility: 无关（契约随 plan 演进）。

## D11: E3 双态锚落 renderer 测试批（恒等消费面 + 反向可检性同框）

11-02 契约「11-03 传目标 colorSpace = 恒等」的兑现验证：同一 0.5 灰纹理，
`source==target==sRGB` → 字节保持 ±1e-6；`source==WorkingSpace` → 0.7354
（±0.002）。反向断言两态差 >0.2（双重编码 = 色偏可检）。消费选择错误
（恒等态传 working）被 11-02 双态测试 + 本测试双向夹死。
Reversibility: 无关（测试口径）。

## D12: 双尺寸归一化容差分层——行字段 32px 带（绝对 30px pad quirk），其余 2px 带

08-3 归一化相等在 2×（整数倍）下 2px 带成立；导出双尺寸 2560/4096（1.6×）下
yiyin 行渲染器的**绝对 30px pad**（08-3 在案、不随分辨率缩放）进入行
left/width 字段 → 归一化差 ≈30px 级，击穿 2px 带（实测 0.0036 vs 0.0012）。
分层口径：canvas/origin/offset/比例字段保持 2px 舍入带；行字段用
`32px/小尺度画布宽` 的 pad 感知带；另加 aspect/画布主图比/行数/内容高/
offset 比例（1.6）等 20+ 字段防审计空转。非放宽：比例无关性主体
（canvas 比例、origin 比例、行位比例）仍在紧带内成立。
Reversibility: 无关（测试口径，pad quirk 若 Phase 12 修正可收紧）。
