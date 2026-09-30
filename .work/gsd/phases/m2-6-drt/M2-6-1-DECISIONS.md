# M2-6-1 DECISIONS — 执行期签注（悬决点终式 + 容差谱 + 偏离声明）

> 每条对应 plan「执行期精读悬决点」/KD 必答/执行期发现；正本 = M2-6-1-PLAN.md（905e979）。

## §D1 rawValue 终式（KD-1 工作假设的订正）

工作假设「hpp 枚举名 snake_case 直译」**错**；以 `drt_node_model.cpp` ToJson（:23-74）实读钉死：

- method：`aces_2_0` / `open_drt`（非 aces20/opendrt）
- 空间：`rec709` / `rec2020` / `p3_d65`（非 p3d65）
- EOTF：`linear` / `st2084` / `hlg` / `gamma_2_6` / `bt1886` / `gamma_2_2` / `gamma_1_8`

超出 hpp 值域的扩展（m4 偏离声明，禁谎称照抄）：Alcedo `DrtColorSpace` 仅 3 值（Rec709/Rec2020/P3D65，hpp:29-33）。`DrtEncodingSpace` 六值 / `DrtLimitingSpace` 七值中，`p3_d60`/`p3_dci` 按 cpp 命名惯例类推，`xyz`/`pro_photo`/`adobe_rgb` 自拟——无 ToJson 对照源。Alcedo 序列化的 `open_drt` 嵌套层是 Alcedo 文件格式细节，Lightamer record 直接平铺（record 即 payload）。测试逐值 pin（DrtRecordTests）。

## §D2 EOTF 常数终式（KD-2：BT.1886 黑位 + HLG OOTF 简化式 + PQ 锚点精度）

- **BT.1886**：Lb=0 → β=0 → 纯 2.4 幂。依据：dctl 参考即裸 2.4（`eotf_p = 2 + eotf*0.2`）；真 BT.1886 黑位抬升属显示端校准，内容编码侧无 Lb 可抬。
- **HLG OOTF**：BT.2100 reference 环境 γ=1.2 固定（1000-nit 参考），不做 Table 5 环境光调制（dctl 同型）。**峰值域修正**：OOTF 在绝对 1000-nit 域上做，peak 换算只在域进出边界一次（encode ×peak/1000 进、decode ×1000/peak 出）——任意峰值 round-trip 精确（首版把换算混进幂项，非参考峰值失败，已修）。
- **PQ 锚点精度订正**：100 nits = 0.50808（表值 0.5081 四位，1e-4 带成立）；**1000 nits = 0.751827**（表值引 0.752 仅三位 → 锚点带 1e-3，plan 的「≤1e-4 对 0.7520」对三位表值过紧）；10000 nits = 1.0 精确。HLG 0.75 → scene 0.264963（plan 引 0.264 三位舍入）。
- **st2084 decode 值域分级（KD-8 升级评估点唯一动用项）**：p99.9 = 2.9e-5 超 1e-5 带 → 签注终谱 **5e-5**。上界来源：decode 分母 `c2 − c3·e^(1/m2)` 灾难性消去（18.85−18.67，丢约 2 位）+ 外层 `^(1/m1=6.28)` 放大 ~6 倍 → float32 固有 ~4e-5 包络（numpy float32 仿算复现同量级；公式忠实 BT.2100/dctl，不重结合）。encode 向与其余六函数 decode 保持 1e-5 带。max ≤5e-5 硬顶全程未破。
- PQ(0) = 7.3e-7（公式地板，dctl 同值，ITU 表舍入为 0）——断言 ≤1e-6。
- input 域：encode 前 [0,1] clamp（SDR=PQ=HLG；D-COL4 clamp 家园随 DRT 尾迁移）；`.linear` = 无 clamp 恒等（EDR headroom 腿，字节不变红线）。

## §D3 ts_dsc 峰值归一分离（KD-3/KD-4 补钉）

dctl `ts_dsc` 按 EOTF 三态（SDR `100/tn_Lp` / PQ `0.01` / HLG `0.1`）。本计划 DrtMethodBox **恒输出 SDR 形**（1.0 = peak nits），per-EOTF 变体折叠进 EotfBox 的峰值归一（PQ ×peak/10000、HLG ×peak/1000）。数学等价证明：两者乘积 `ts_y1 × ts_dsc` 恒等（PQ bin 实测：ts_y1=10, ts_dsc=0.01 ↔ 我方 0.1@peak1000 同 placement）。surround（tn_su）由 (space,eotf) 按 dctl display_encoding_preset 表（:858-902）派生：rec709+bt1886=1(dim)、rec709/gamma22=2(bright)、p3d65+gamma22=2、p3d65+st2084=0(dark, dolby)、p3d60/p3dci/xyz+gamma26=0、rec2020+st2084/hlg=0；ts_p = tn_con/(1+tn_su×0.05)。

## §D4 容差谱终版（KD-8 逐断言签注）

| 断言 | 终带 | 依据 |
|---|---|---|
| Float64 规范锚点（PQ100/HLG/gamma 族） | ≤1e-4（gamma 族闭合式 1e-9） | 表值精度 |
| PQ1000 锚点 | ≤1e-3 | 表值三位（§D2） |
| Float64 往返（七函数） | ≤1e-6 | 实测 ≤1e-9 |
| GPU EOTF encode（七函数） | p99.9≤1e-5 + max≤5e-5 | 实测 max≤7.3e-6 |
| GPU st2084 decode | **p99.9≤5e-5** + max≤5e-5 | 灾难性消去+幂放大（§D2；唯一升带项，numpy 仿算佐证） |
| GPU HLG/gamma decode | p99.9≤1e-5 | 实测 max≤2.5e-6 |
| OpenDRT kernel golden（3 探针 × 4 参数点） | p99.9≤1e-5 + max≤5e-5 | **实测 worst p99.9=5.4e-7 / max=6.9e-7**——升级协议未动用 |
| golden 输入对齐 | 参考消费 float32 量化后输入 | 陡峭 PQ 斜率放大共享输入错配 ~1e3×（golden 对齐原则：两侧同字节输入） |
| IEEE | -0/+0 相等；NaN/Inf 恒 fail | 全 AC 口径 |

## §D5 结构图头注终版 + enable→value 映射

- KD-3 预勘 21 阶段骨架与 dctl 实读有出入（hue contrast 位于 hyperbolic 之后；purity limit low/high 与 mid-purity 为独立三段；display_gamut_whitepoint 为独立函数）——以 dctl 为准重排为 **[0]–[24] 25 阶段**，`OpenDrtReference.swift` 头注即终版，逐段行号清单见 SUMMARY。
- **enable→value 投影**：53 参数模型无 enable 位。逐 preset 核对：全部 look 分支的 enable=0 项携带中性值（行为等价）；**唯一陷阱 = tsprst11（ACES-2.0 tonescale，dctl:818）**：`tn_hcon=1.0`/`tn_lcon=1.0` 且 enable=0（行为关断）→ 我们的表存 0（DrtPresetsTests pin）。stickshift 自定义语义：enable→值≠0。

## §D6 预设枚举真值清单（悬决点②终式 + m3 勘误落地）

dctl `tonescale_preset` 实枚举 **14 项**（tsprst0..13 = USE LOOK PRESET + 13 具名），REQUIREMENTS 记 15 系多计——与 m3 附注一致，勘误注记于此（REQUIREMENTS 原文不改）。字符串 rawValue 按 Alcedo QML 拼写（`aces_1_x`/`aces_2_0`/`marvelous_tonscape`/`dagrinchi_tonegroan`…，EditorDisplayTransformPanel.qml:342-357）；look 7（standard/arriba/sylvan/colorful/aery/dystopic/umbra）+ custom（派生 UI 态，不入枚举）；creative white 7（use_look_preset + d93..d50）。look 的 cwp：standard/arriba/sylvan/colorful=D65(2)、aery=D75(1)、dystopic=D60(3)、umbra=D50(5)。

## §D7 数值抽检结论（KD-7：Alcedo expected bins，一次性，不入测试）

`tests/resources/expected_parameters/drt/cuda_opendrt_*.bin`（GPL 资产只读）= `CudaDrtGpuParams` 打包（15×int32 enable/上下文 + 53×float + 14×float 派生 tonescale 常数）。对照结果：

- **standard + arriba：53/53 逐位一致**（同一十进制字面量的 float32 表示）。
- **派生常数 14/14 公式一致**（float32 舍入内）：ts_x1=128、ts_y1、ts_x0=0.19、ts_y0、ts_s0=0.1618034、ts_p=0.9545454（surround=bright 独立印证）、ts_s10/ts_m1/ts_m2/ts_s、s_lp100=1.5126863、ts_s1。
- **PQ 行 ts_dsc 差异 = §D3 已文档化折叠**：bin ts_dsc=0.01（其 ts_y1=10）；我方 0.1@peak1000——placement 恒等。
- creative_white/surround int 字段独立印证（arriba=2/2）。
- GPL bins 不入 CI、不进断言（KD-7 边界）；本节即一次性记录。

## §D8 执行期实现裁决（半径内）

1. **尾段全平面显示格式**：resident watermark/borders 交接含 blit（`blitIdentity`）——blit 不能跨像素格式转换；尾段每个平面按 EOTF 族携带显示格式。SDR：8bit unorm 量化即最终量化（与直写同字节）；16F/float32 无损。
2. **walk skip 一致性**：skipped 模块的 `modifyROIOut` 同步跳过（否则 borders 画布协商进主链，尾段二次扩张）。
3. **尾段键**：sub-run decodeHash = FNV(levelHash[top] ⊕ recordHash ⊕ policyTag)（L013 折叠序）；resident boxes 原样复用（paramsHash 随 materialize 继承）。
4. **borders/watermark 工作上下文**：joint layout 注入（`jointLayoutOverride`/`jointContext`）由调用方设置——生产 = coordinator injector，测试 = YiyinE2ETests.wireYiyinContext 同款（T7 测试已镜像）；E2 guard 断言 = 画布带 display-white（1.0）后画 + 图区保持 PQ 编码，序 = 装配序测试（74→75→76→77，watermark 后无 tone map 段）。
5. **版本 pin 机械同步**（T6 申报）：SidecarV5Tests:193 → schemaVersionCurrent；SidecarMetadataV3Tests byte golden 与 v2-upgrade diff 字面量 5→6——断言零弱化（golden 重钉同一形状的新当前版本）。

## §D9 遗留（P3/P2 面，本计划不追）

- 尾段 borders 的 display-referred 强度标定 + Post 四件 = M2-6-3 T5（插槽序已锁）。
- aces20 = `isRenderImplemented` false + typed refusal；P2 翻面 + NOTICE 条目 2。
- drt_opendrt 首编译耗时可观测行未单独计时（无 >2s E3 触发）；100MP bench 行挂 M2-11 60fps 复验。
