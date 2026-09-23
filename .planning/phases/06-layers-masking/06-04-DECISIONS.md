# Plan 06-04 Decisions（执行期裁决记录）

> 授权模式同 06-CONTEXT：推荐可逆 + RESEARCH/plan 已论证即执行，逐条记录理由与可逆性。

## D-06-04-T1-1：blendif 单 kernel 覆盖全通道族（域字段仅 UI 声明）

- **裁决**：`mask_blendif` 按 dt `blendif_factor_rgb_jzczhz`（blendop.cl:329-408）原样移植——body 内同时支持 gray（Rec2020 Y 行）/RGB 直读/JzCzhz 三族共 14 个 slot；`ParametricMask.domain`（luma|jzczhz）只是 UI 呈现声明（D-06-CONTEXT-3 的单域指 UI），kernel 参与由 per-channel bitmask 决定，与 dt `blendif` 位字同构。
- **理由**：一个 kernel 覆盖两域免去域分派；dt RGB_SCENE 的 GUI 本就同屏暴露 gray/RGB/JzCzhz 通道，双域 UI 是 Lab 历史包袱。
- **Reversibility**: reversible——未来 UI 双域化只是面板拆分，数据/kernel 不动。

## D-06-04-T1-2：invert_mask 三元方向（平场门抓出的真 bug 记录）

- **事实**：初版 kernel 与 float64 参考同时把 dt 的 `(INCL ? RGB_MASK : 0)` 写反成 `(INCL ? 0 : RGB_MASK)`——两份同错导致 sweep parity 全绿，**平场二元门抓出**（dt 平场 probe 的价值实证）。
- **修复**：`invert_mask = (blendif>>16) ^ (INCL ? RGB_MASK : 0)`（blendop.cl:402 正本方向）；NORM_EXCL（v1 默认）下只有显式 invert 通道反转。
- **教训入账**：同源双实现（kernel + 参考）能对齐彼此的错误；**常数/平场门是唯一能戳破「两份镜像同错」的探针**——后续所有 parity 任务保留平场/二元门。

## D-06-04-T1-3：jzczhz ramp 腿容差校准（5e-4）

- **裁决**：mask 值门 = 平腿（factor∈{0,1}）与全部 luma 通道 <1e-5（plan 门）；jzczhz 通道 ramp 腿 <5e-4。
- **依据（实测非放宽）**：ramp 段误差 = 斜率 × 感知链 float32 噪声。cz 测试窗宽 0.004 → 斜率 250，06-02 已实测 pow-chain 地板 abs 5e-4；平腿无放大，维持 1e-5 严门钉住 trapezoid 逻辑本体。maxAbs 逐 case 打进 run log。

## D-06-04-T2-1：feather v1 = 单通道 Gaussian（非 dt guided filter）

- **裁决**：feather 与 blur 共用单通道 Deriche（σ=featherRadius），不做 dt 的 image-guided filter（blend.c:385-405 `guided_filter`）。
- **理由**：plan T2 明示「feather：blend.c:664-710 单通道 Gaussian 直译（featherRadius 参数化）」；guided filter 是 Phase 6 后续升级缝（kernel 已按 buffer 双平面纪律成形，替换点收敛在 `MaskCombiner.postProcess` 一处）。
- **Reversibility**: reversible——换核不换链，组装序与门控不动。
- **附带裁决**：feather_in/out（guide 前/后 + guide 图像源）在 v1 退化为「after-blur 默认序」（blur → feather → tone curve，blend.c:330-341）；in/out 双侧枚举随 guided filter 一并升级。

## D-06-04-T3-1：reduce 首项安装语义（dt 零种子的可达态归一化）

- **裁决**：`MaskCombiner.reduce` 首项以 union 语义安装到零种子（= max(0, opacity·(±1−s))），后续项按各自 op。
- **依据**：dt `_group_get_mask_roi` 零种子 + 逐项 op；首项 op=union/sum 时与安装完全等价（dt GUI 的 group 根项恒为 USE|UNION，可遭遇态只有这一种）；首项 intersect/difference 在 dt 会退化成全 0 蒙版（不可达的病态）。归一化使嵌套组根项天然可用。
- **Reversibility**: reversible——把安装步换回「按首项 op」即回到 dt 病态语义，一行改动。

## D-06-04-T3-2：reduce 上界 4 = 抛错（非 trap）

- **裁决**：>4 项 reduce 抛 `AppError.unsupportedFile`（提示 nest groups），不用 precondition。
- **理由**：用户文档可达路径（sidecar 手编/未来 UI），trap 会杀宿主；上界保 ping-pong 深度有界，嵌套组承载更大 N。

## D-06-04-T4-1：raster 烘焙分辨率政策 = 当前合成窗口

- **裁决**：bake 以消费时的合成窗口为准（窗口化架构下窗口有界，16-bit 灰度 PNG 最坏几十 MB）；不做全解码帧重烘焙默认。
- **配套**：加载端分辨率失配走 **nearest 重采样**到消费窗口（`mask_resample` kernel，中心采样映射）——dt `dt_dev_get_raster_mask` per-scale 再生的同构简化。该腿由 render-identity 测试抓出的真缺口驱动补上（24×16 bake vs 48×32 预览窗）。
- **Reversibility**: reversible——bilinear 升级只换 `mask_resample` 采样式。

## D-06-04-T4-2：raster 失配/缺失降级语义（不静默吞）

- **裁决**：缺文件 / PNG 损坏 / hash 失配 → 降级 = **窗口尺寸全 1 平面 + reason 字符串透出**（driver 走 error log；effectivePlane 返回 reason 位供 UI 标记与 reconcile 提示）。内容上 `min(effective, 1) = effective`，intersect 链内容中性。
- **依据**：plan T4「不静默吞 + UI 标记 + reconcile 提示位，Phase 9 口径对齐」；测试以真实构造文件覆盖三失败腿（换 PNG→hash 腿；截断后重哈希→decode 腿；缺失文件）。
- **UI 标记落地**：Phase 6-5（本 plan 只到 log + 返回值）。

## D-06-04-T5-1：三类装配 = drawn ⊗ parametric ⊓ raster

- **裁决**：drawn ⊕ parametric 走 dt 精确语义（`form·conditional`，NORM_EXCL；INCL/INV 位在 kernel 内保留可路由）；raster 以 **intersect（min）** 加入有效平面（opacity 1）。
- **理由**：dt 中 raster 模式互斥（blend.c:517 `else if(raster)` 独占分支），三类同启在 dt 无定义；plan 指示三类各自出平面再合成单一平面。选 min：与 drawn⊗parametric 的乘法链在二值极限等价、属 dt 五式体系、灰度蒙版下是标准交集语义。
- **Reversibility**: reversible——join op 是 `combinePair` 的一个参数。

## D-06-04-T5-2：gopacity（层不透明度）全程折叠恰好一次

- **裁决**：装配序列中 06-3 单形态路径已在平面内预乘 layerOpacity → blendif 腿 gopacity=1；无 drawn 平面时 blendif 腿 gopacity=layerOpacity；raster-only 安装与嵌套组平面经 `scale`（union-onto-zero 恒等式 max(0,v·op)=v·op）补乘；tone curve 的 gopacity 参考值 = layerOpacity（与 dt 的 mask 生成值同口径）。composite 消费端零改动（红通道即最终有效 opacity）。
- **验证**：三类装配测试 + 三 payload round-trip 渲染逐字节 + 双向记账测试。

## D-06-04-T6-1：golden 轨注记（L017）

mask/blendif 为 dt-cli 不可达对象（不落盘、无独立 blob）——manifest mask 节以 **float64 解析参考常驻回归**替代轨 A 三证据；每行注明直译正本 file:line 与测试锚。见 `input/golden/manifest.md`「mask golden 总账」。
