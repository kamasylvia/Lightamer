# Plan 12-5 DECISIONS（执行期决策，RESEARCH 未覆盖细节裁决）

## D1 — 1D 尺寸防御上限单独 65536（plan 字面「>129 防御」的 1D 例外）

plan T1 字面「sizeOutOfRange(>129 防御)」未分 1D/3D。3D 上限 129 落字面（129³ rgba32Float
= 34MB，research 内存天花板）；1D 真实 ramp 常见 1024-4096 行，129 上限会拒绝合法文件 →
1D 上限 65536（字节 786KB 无压力）。同一错误 case 参数化，测试双向锁定（129 对 1D 合法 /
65537 拒 / 3D 130 拒）。

## D2 — TITLE 值剥成对首尾引号

`TITLE "My LUT"` 的引号非显示名一部分（Adobe 惯例包裹）；剥**一对**匹配引号，不成对保留。
dt 不取 TITLE（只跳过）——取值本身即 divergence 1，引号处理是我方显示面裁量。

## D3 — DOMAIN/浮点键解析严格度对齐 dt：NaN/Inf 拒绝 = nonNumericToken

`Double("nan")` 原生解析成功——dt `:855` 显式 isnan 拒绝；同姿态：解析成功但 isFinite 失败
→ `.nonNumericToken(line:)`。科学计数法 `Double` 原生支持（research §6.1 在案）。

## D4 — 1D 2-float 行变体 = 首值灰度广播（无标准语义，我方定义）

plan/RESEARCH 要求 1D 数据行接受 2-3 floats。Adobe spec 1D 行 = 3 floats（RGB）；2-float
变体无标准语义（wild 观察为 value+secondary 形态）。裁决：2-float 行 = `R=G=B=value[0]`
（首值灰度广播，第二值忽略）——dt 对 1D 整体不支持（lut3d.c:808 硬拒），本就无正本可依；
测试 `testParse1DTwoFloatVariant` 锁定行为。同键异值重复 → conflictingSizes（dt 静默覆盖，
我方 typed 从严——八名 throw 面的要求）。

## D5 — 脏样本预案执行记录：真实采集失败 → 合成替代落账（plan 写死分支）

真实 `.cube` 变体网络采集 1 次预算消耗记录：`px --up` 失败（update 步依赖代理自身，
127.0.0.1:10809 daemon 未跑 = 鸡生蛋链）；unset 代理直连 GitHub API 探测两样本库
（Pantarheon/koliba 树 + freliba submodule）未命中 .cube 文件 → 预算耗尽。按 plan 写死
分支合成替代：`input/cube/` 三 fixture（CRLF+CR+LF 混合换行/tab 分隔/行内注释/科学计数/
负值 HDR DOMAIN/TITLE 尾置）入仓。**执行期附带发现**：Swift `"A\r\nB".split` 中 `\r\n`
是单个 Character（grapheme cluster）——`$0 == "\n" || $0 == "\r"` 谓词静默漏切 CRLF 行，
`Character.isNewline` 是唯一正确切分器（教训候选，未达 LESSONS 立案阈值——单点 API 事实）。

## D6 — 1D 表被 3D 槽引用 = 降级恒等（kind 不匹配同 missing 姿态）

lut3d params 无 kind 字段（lutName 单引用键）；commit 时 `case .lut3d` 匹配失败（引用了
1D 表）走 data-nil 降级路径。用户修法 = 重新选择正确表（面板库列表按引用键解析，1D/3D
自愈于再次选择）。1D 面板提示位（1D hint）由 T5 面板 entry.is1D 驱动。

## D7 — rgba16Float → rgba32Float 升格触发（RESEARCH §6.4 预案正身兑现）

§6.4 预写「golden 超差（tetrahedral vs float64 阈值 ≤1/1024）时升 rgba32Float——access::read
手动插值下两格式 kernel 同源，升格零重写」。实测：HDR 随机表（值域 ±2.8）half 表征误差
≈2.8/2¹¹ ≈ 1.37e-3 > 9.77e-4 → 触发升格。`pixelFormat = .rgba32Float`（module + test 双处
+ 字节 stride 16）。内存：33³ 460KB / 129³ 34MB——v1 预算无压力。display 域量级（≤1）表
half 本可过关（§6.4 论证成立），升格 = HDR 面的确定性选择而非 half 不足论。

## D8 — 1D texture1d 主案成立，texture2d 宽条回退案未触发

plan 写死两案验收锚。实测 texture1d integer read（uint 坐标，无 filter）无组合问题——
回退案不触发。裁决：texture1d rgba32Float 主案，回退案弃用（记录于 kernel 头注 +
`test1DRamp` 锚）。

## D9 — dt golden-image 参考形态 = CPU float64 双写（L017 route ①先例援引）

CONVENTIONS「iop 移植必须有 golden-image」的参考源裁决：dt-cli float export 本 host
空间损坏在案（SharpenParityTests L017 provenance + darktable-cli CrashReporter 记录）；
lut3d XMP params-v3 二进制构造（12.9KB struct + 版本校验 + lut_root_folder pref）超执行
预算。参考 = dt lut3d.cl 数学逐行双写（float64）+ 权重表 verbatim 人工核对；dt-GUI 人工
交叉对照挂 Manual-Only F-12-5-2。与 Sharpen/Ashift 等 L017 先例同一 provenance 形态。

## D10 — 色彩空间矩阵落位：LutColorspaceMatrices 单文件资产（非 ColorOut 扩展）

plan「矩阵走 colorin/colorout 既有系数资产（同源单实现，不新增 ICC 面）」落位裁量：矩阵
常量放 `Lut3d/LutColorspaceMatrices.swift`（非 ColorOutModule 扩展）——理由：① lut3d 需
inv 矩阵与 ProPhoto 态（ColorOut 只有 fwd 两态无逆）；② 「同源单实现」以**逐位一致测试**
兑现（`testSRGBAndP3MatchColorOutAsset` 对 ColorOut 头注公布系数 1e-9 断言）而非物理
同文件；③ rec2020 = identity / ProPhoto = Bradford D65→D50 适应（ICC 相对比色数学，
numpy 推导值打印于头注，白点映射测试锚定）。零新 ICC/ColorSync 依赖 ✓ 字面达成。
