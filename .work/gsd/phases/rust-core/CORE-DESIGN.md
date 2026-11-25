# CORE-DESIGN — Rust 核心设计调研（含 C3/C4 双 spike）

日期 2026-11-25 夜；机器 Apple M4 / macOS 27.3 / 10 核 / 16GB；rustc 1.100.0。
上游读数口径：refs/dt-master @ 679d594f5d。长表见 CORE-DESIGN-TABLES.md（T1–T8）。
证据：decode-oracle-evidence/（C4）与 decode-spike-src/（C3）。
机器守卫（构建前原样）：`GUARD PASS (heavy=0 free=61% swap=?M disk=?GB)`。

## §0 一页纸（Rust trait / 模块数行数 / 解码结论 / 对照命令 / GPU 推荐 / lane 估算）

- trait 形：`IopModule`（op_name/flags/commit/process/roi 对/tiling/colorspace）+
  `Params: Default+Serialize` + `PieceData`（commit 产物）+ `Pipeline`（13 步调度，
  缓存/tiling 在管线层）。同步 fn，CPU 切片并行在调用方（rayon）；错误 `PipeError`
  非 panic。方法↔回调映射见 §1。
- 第 0 期 21 模块（去 deprecated clipping），顶层文件 C/C++ 37,561 行（+demosaicing/ 7,722+ashift 求解器 2,703 = 全量 47,986）；20/21 有 OpenCL 双版
  （gamma CPU-only）；外部依赖仅 lcms2（temperature/colorin/colorout 间接）、
  lensfun（lens）、cairo（overexposed 显示）；CPU/GPU 差异注释零命中。
- 解码：rawspeed 无 Bayer 去马赛克（仅 Canon sRAW 插值器）。起步 = rawspeed 解码
  （~46ms）+ 移植 RCD（MHC 基线 43ms/61MP 为量级参考，RCD 估算偏上）；Apple 模块提供可选 CIRAW
  路径（DNG 桥已验证快 2.4x，但偏色 22.8 未解，只作兼容腿）。
- 对照命令：`darktable-cli IN [XMP] OUT.png`（5.6.2 官方包，sha 见证据 SOURCES.md），
  HOME/CFFIXED_USER_HOME 隔离 + 预置 darktablerc（opencl 开关/png bpp=16）。
  噪声底线：重复轮像素逐位同；CPU-OpenCL mean ≈0.014 LSB16，max ≈900 LSB 仅 ~10 px。
- GPU：WGSL+wgpu 为底，P0 先 CPU；Metal 快路径只进 Apple 模块。basic.cl 整文
  移植否，按 P0 核裁剪约 6000 行 OM（估算）。Lightamer 73 .metal 命中 P0 仅 6 个。
- lane：模块 38 + infra 14 = P0 ≈ 52 lane（估算，1 lane ≈ 1–2h/千行带测）。

## §1 C1 管线与模块接口 → Rust trait（读源码）

darktable 模块回调共 57 个（`src/iop/iop_api.h`，全表 T1；另 process_plain 系 imageop.h 非表成员）：REQUIRED 仅 3
（name/default_colorspace/process），DEFAULT 约 20（含 commit_params/roi 对/
tiling/colorspace），OPTIONAL 约 30（GUI/事件/legacy/mask 变形等）。
P0 需要 13 个：name、flags、operation_tags（DISTORT 位）、default/input/output
colorspace、tiling_callback、init（Params::default 代）、init_pipe+commit_params
（合并为 commit）、modify_roi_in/out（默认恒等）、process、process_tiling
（默认分块器）。blend_colorspace 预留（P0 默认关短路）。

管线 13 步（`src/develop/pixelpipe_hb.c`）：建图→提交→前推几何→查缓存→反推 ROI→
定格式→mask 旁路→tiling 决策→进变换→直方图/拾色→process→出变换→blend→写缓存。
P0 跳过 S6/S9（blend mask 旁路/拾色），S12 blend 只做 DISABLED 短路 + 均匀不透明度。

五类管线（pixelpipe.h:40-63）：EXPORT/FULL/PREVIEW/THUMBNAIL/PREVIEW2，同构不同配额
（full 64 行缓存，preview 12，export 预分配整帧）。三者关系 = 同一结构体不同实例，
各持 nodes/cache/backbuf；P0 取 FULL + EXPORT 两实例（preview 复 FULL 降采样）。

```rust
// P0 trait 设计（无界面；同步；错误显式）
pub trait IopModule: Send + Sync {
    type Params: Default + Serialize + DeserializeOwned;
    type Piece: Send;                       // commit_params 产物 ≈ piece->data
    fn op_name(&self) -> &'static str;      // name
    fn flags(&self) -> ModuleFlags;         // flags（tiling/blend/distort 子集）
    fn colorspaces(&self) -> (Cst, Cst);    // input/output_colorspace
    fn commit(&self, p: &Self::Params, img: &ImageInfo) -> Result<Self::Piece, PipeError>;
    fn roi_out(&self, d: &Self::Piece, rin: Roi) -> Roi;   // modify_roi_out，默认恒等
    fn roi_in(&self, d: &Self::Piece, rout: Roi) -> Roi;   // modify_roi_in，默认恒等
    fn tiling(&self) -> TilingReq;          // tiling_callback（默认 factor=2/overlap=0）
    fn process(&self, d: &Self::Piece, input: &Frame, output: &mut Frame,
               rin: Roi, rout: Roi) -> Result<(), PipeError>;  // process
    // 可选：reload_defaults（temperature/exposure 类）、distort_*（lens/crop 类）
}
pub enum PipeError { InvalidParams(String), RoiMismatch, UnsupportedFormat, Backend(String) }
```

Frame = float32 RGBA 连续缓冲 + Roi（x/y/w/h/scale，对应 dt_iop_roi_t）。
并行：模块内用 rayon 切行（对应 OpenMP 范式，不写 intrinsics，intrinsics 留给
wgpu 后端）；跨模块串行（对应 pixelpipe 递归）。缓存/tiling/色彩变换在 Pipeline 层，
不对模块可见（对应 S3/S7/S8/S11 由管线驱动）。多实例：op_name + instance id；
顺序：v50 表常量（order 值见 T2）。

## §2 C2 第 0 期模块清单（读源码，全表 T2）

21 模块 v50 顺序：rawprepare → temperature → highlights → cacorrect → hotpixels →
demosaic → lens → cacorrectrgb → ashift → flip → exposure → crop → colorin →
rgbcurve → rgblevels → tonecurve → finalscale → colorout → overexposed → dither → gamma。
顶层文件总量 37,561 行 C/C++（最大 ashift 6280，最小 finalscale 270；
demosaicing/ 子目录 7,722 + ashift 求解器 2,703，全量 47,986）；params 最大 colorin 1048B（含 2x512 ICC 路径），最小 flip/finalscale 4B。

关键裁决事实：clipping deprecated 不取（crop 承接）；WB=temperature；
lens=几何+TCA+暗角一体（lensfun）；rgbcurve/rgblevels/tonecurve 默认全关且分处三处；
overexposed 无 params（HIDDEN 显示辅助）；gamma CPU-only。外部依赖面极窄（见 §0），
lcms2 进入 temperature/colorin/colorout 三处——Rust 侧对应 lcms2-sys 或 Apple ColorSync 腿。
OpenCL：20/21 双版，但 CPU/GPU 差异注释零命中——移植期 CPU 为准、无历史包袱。

## §3 C3 rawspeed 解码路径（spike，程序+输出见 decode-spike-src/）

R1 rawspeed 去马赛克算法：**没有**。`interpolators/` 唯一文件是 Canon sRAW YCbCr 插值器，
Bayer/X-Trans 去马赛克不在 rawspeed 职责内（darktable 的 demosaic.c 承担）。
任务预设的“分别用这些算法”为空集——转做两条自写基线标定时钟（A7R5 9568x6376，
OpenMP 默认 10 线程，5 次中位，`steady_clock` 墙钟，checksum 跨构建逐位复现）：
bilinear 27.8ms，MHC-5x5 43.4ms；rawspeed 解码段 ~46ms（50.7/41.1 两轮）。

R2 三项元数据对照（rawspeed 实测 vs CIRAW）：
黑电平 rawspeed blackLevel=512（2x2 全 512）/ white=15360，CIRAW 内部不暴露；
WB rawspeed wbCoeffs=(2536,1024,1778) G-pin，CIRAW ARW 路 neutral=(0.345350,0.362652)，
DNG 路 T0=(0.335336,0.356312)；
矩阵 rawspeed cameras.xml XYZ→camera verbatim（T4b），CIRAW ARW 路用 Apple 内置 profile，
DNG 路读 ColorMatrix1 verbatim。
线性对比（MHC 转储 + WB + 逆矩阵 + D65 标准矩阵→sRGB，中对齐 9504x6336）：
RAW mean 0.169 / max 8.19；gain 拟合 0.7125 后 mean 0.140 / max 5.55；
通道均值 ours (0.446,0.110,0.102) vs cir (0.245,0.381,0.096)——R/G 失衡，
1/8 降采样试验证无-WB 版最近（0.1285 vs 0.1699；脚本 compare_down8.py + down8.log 已归档），WB 处理是主色偏源。
差源分解：全局尺度（基线曝光+影调）、WB/光源约定、去马赛克算法差、
几何裁剪差（64x40）、CIRAW 默认影调。结论：不对齐是预期的，差已定位到项。

R3 偏色查因：writer tag 对照 DNG 1.4 CFA 必需项齐全（T5），Linearization 缺席正确，
故偏色非 writer 合规问题。垫片副本加 `--neutral` 做两轮诊断（bench cmp 2560 档）：
T0 基线复现 22.784；T1 unit-neutral 恶化到 55.935 且 R 通道归零（neutral 极敏感）；
T2 按通道均值比拟合 23.275（不改善→残差非 WB 可缩放）。根因判定（推断，有证据支撑）：
cameras.xml 校准数据 vs Apple 内置 A7R5 profile 的数据源差异；真修需色卡标定或实测矩阵，
超出本 lane。查到：tag 层 + 两轮诊断数字。

结论：非 Apple 路径起步算法 = 移植 RCD（darktable 默认，X-Trans/单色有回退语义；
MHC 43ms 证明 CPU 全分辨率去马赛克在 50ms 量级，RCD 预计同量级偏上，估算）。
Apple 模块提供可选 CIRAW 路径：DNG 桥（上一轮快 2.4x）作兼容腿，但偏色未解，
P0 默认关闭、仅作“疑难机型回退”。

## §4 C4 验收对照工具（spike，命令/脚本/输出见 decode-oracle-evidence/）

官方包 5.6.2（88,884,896 B，sha256 6ff88e58…def0c，URL 见 SOURCES.md），只挂载不安装，
从卷内直调 darktable-cli。隔离：HOME+CFFIXED_USER_HOME 双变量指向临时目录；
pref 保护：首跑前 `defaults export` exit 0（域存在，已存 before.plist），
完工比对后按需还原，禁 cfprefsd。
配置：`--core --conf` 运行期生效但不写回 darktablerc（自审指正并自验证：bpp=8 覆盖预置 16 生效，文件仍 16；初稿曾误判“不生效”）。推荐预置 darktablerc（持久、可审计）：
opencl=true/false 切后端（`-d opencl` 日志 respectively “161/161 events”+RCD tiled 行 /
“NOT utilized”），png/bpp=16 出 16 位（IHDR bitdepth=16 逐文件验）。
XMP 规则：最小历史 + auto_presets_applied=0 + xmp_version=4，由 darktable 补默认
（跨相机全量拷贝错裁剪）；iop_order_version 可省略（4/5 均接受，自审 6 变体实证）；
sidecar 禁 XML 注释（前导注释致整读失败，probe-comment.xmp 复现——初稿曾误归因版本 5）；
曝光 +1EV/flip 参数 hex 见 CMDS.md。

三组×双后端（全分辨率 PNG16 ~311MB/张，17–21s/轮）：
重复轮像素逐位相同（PNG 字节不同=元数据；dither 确定性，推断固定种子）；
CPU-OpenCL mean ≈0.013–0.014 LSB16，max 842–904 LSB，in_tol(1/255)≥0.99999994
（约 10 px）。跨组：曝光 mean 差 2600.9 LSB；flip 三通道均值逐位相等。
1600px 探针附带发现：--width 缩放路 flip 引入 1px 横向偏移（全分辨率无），
对照一律用全分辨率。噪声底线与通过阈见 RESULTS.md。
比对脚本 cmp16.py（cv2 读 16 位 RGB；Pillow 会截断到 8 位，已实证）输出 mean/max/
in_tol/通道均值，可选 ±1px shift 搜索。

## §5 C5 GPU 后端选型（设计，给推荐）

推荐：**WGSL + wgpu 为唯一管线着色器底座；Metal 快路径只存在于 Apple 模块内，
P0 先全 CPU**。依据：① P0 21 模块 20 个已有 OpenCL 双版，GPU 需求是未来式不是当下式，
P0 用 CPU 即达正确性（对照噪声底已证 CPU/CL 同构）；② 裁决“Apple 能力只在 macOS
模块”要求核心零 Metal 符号——wgpu 是唯一跨平台且 Rust 原生的底；③ OpenCL→WGSL 是
逐核机械移植（地址空间/屏障/向量类型一一对应），无语义鸿沟。
工作量：P0 需移植核 ≈ 6000 行 OM（basic.cl 按核裁剪 + cacorrect 对 + rgbcurve 对 +
rcd.cl + dither 系；basic.cl 整文 4618 行含大量 P0 外核，不可整取），估算。
Lightamer 现有 73 产品 .metal 命中 P0 仅 6（Temperature/Exposure/Lens/Flip/Ashift/
ToneCurve），Exposure 系逐字移植可直接参考，其余 15 模块无资产——Metal 存量不是
选 Metal 的理由，反而证明缺口在模块覆盖而非后端。
数据量：61MP float32 RGBA 单缓冲 ~976MB；管线常驻 2–3 缓冲 + tiling overlap
（RCD overlap=10 行已在 CL 日志实证），显存/CPU 内存预算按 4GB 配。

## §6 C6 仓库布局（cargo 工作区设计）

```text
crates/
  dt-core/        # Frame/Roi/缓存/tiling/调度/PipeError（零平台相关）
  dt-iop-traits/  # IopModule/Params/Piece/ModuleFlags/Cst（C1 trait 落处）
  dt-iop-<name>/  # 每模块一 crate（params+commit+process+单测；或按域合包，见下）
  dt-decode/      # RawDecoder trait + rawspeed 腿（C++ 静态链接，cmake 配方沿用）
  dt-color/       # 色彩变换 trait + lcms2 腿（跨平台默认）
  dt-mask-blend/  # 蒙版栅格化+混合（P0：短路+均匀op）
  dt-apple/       # ★ 仅 macOS：CIRAW 腿/ColorSync 腿/Metal 快路径/Vision 腿
  dt-app/         # 装配层：按 target + 运行时探测选择腿
  dt-gpui/        # 界面（gpui 族；只经 dt-app 的能力 handle 拿纹理/事件）
  dt-cli/         # 命令行 + 对照工具（oracle 导出/cmp）
  dt-lightamer/   # Lightamer 独有功能（全景/焦点/HDR/DRT/版本库/AI 选片），复用 dt-core
```

门控（Cargo 语义修正版，自审 E3）：`dt-apple` 恒为 workspace 成员（path 依赖自动成成员，
条件 members 不存在）；crate 根 `#![cfg(target_os = "macos")]` 把非 macOS 编成空壳
（无符号、无 Apple 依赖——其自身 objc2/Metal 依赖亦放 target 表下）；
消费侧 `dt-app` 用 `[target.'cfg(target_os = "macos")'.dependencies] dt-apple` 按需链接。
界面侧：`dt-app::capabilities() -> Capabilities`
（decode_backends: Vec<DecodeBackend> {RawSpeed, CiRaw?}、gpu: {Cpu, Wgpu, Metal?}…），
UI 只读该结构渲染可用项，不做 `cfg!` 判断——编译期门控 + 运行时能力表双保险。
模块 crate 粒度推荐按域合包（dt-iop-raw/demosaic 前段、dt-iop-geom、dt-iop-color、
dt-iop-display 四包），21 小 crate 的版本/编译负担不值；合包内每模块独立文件+独立单测。
GPL：dt-apple 调 Apple 框架属系统库例外常规做法（同 darktable 链接 Apple 框架），
许可证维持 GPL-3.0 不变（法务复核仍建议，见 §9）。

## §7 C7 移植做法与量级（设计+估算）

单模块移植 6 步：① 建 crate/文件骨架 + Params 结构（serde，版本=1，不做 legacy 迁移）；
② commit（参数校验+预计算表，如 tone curve LUT 化；对应 commit_params）；
③ process CPU 版（C→Rust 逐行，OpenMP→rayon 行并行；对应 process）；
④ roi 对（几何类；默认恒等）；⑤ golden 测试（对照 C4 oracle：无历史+单模块 XMP，
阈值 mean<1 LSB16 且 in_tol>0.9999；几何类加 ±1px shift 容限）；⑥ 版权头
（保留 darktable Copyright + GPL-3.0 声明，追加 `Modified for Lightamer:
<date> <what>` 行；NOTICE 登记）。
OpenCL 核此时不移植（P0 CPU），但 commit 需把 uniforms 抽成结构体（WGSL 移植时直用）。

lane 估算（估算，口径 1 lane≈1–2h/千行带测）：模块 38（T2 末列：8 个 1-lane，
10 个 2-lane，lens/ashift 各 3，demosaic 4）；infra 14（pipe-core 3，decode 2，
blend/mask 2，色彩显示 2，导出 2，导入图库历史 3）。P0 ≈ 52 lane。
最大三项：demosaic（RCD 起步 + 回退语义 + golden）、lens（lensfun 数据库接入+
畸变/TCA/暗角三合一）、ashift（求解器移植 + 交互参数面裁剪）。
以上均不含 UI、不含 review 修订轮。

## §8 裁决点清单

1. demosaic 起步只做 RCD？选项 A 只 RCD（+passthrough 调试），B 再加 PPG 兜底。
   推荐 A：RCD 是 darktable 默认且有 X-Trans/单色回退，AMaZE/LMMSE 后续加。
   依据 C3 时钟（CPU 全帧 50ms 量级可行）+ T2（demosaic 4 lane 已按单算法估）。
2. P0 是否含 cacorrect（Bayer 横向 CA）与 cacorrectrgb（后段）两个？选项 A 都含，
   B 只留 cacorrectrgb。推荐 A：两者座位不同（5.0 vs 13.5），lensfun 会重引入 CA，
   去一则画质链断环。依据 v50 注释（iop_order.c:319-323）。
3. Apple 模块 CIRAW 腿 P0 默认开/关？选项 A 关（疑难机型手动开），B 开。
   推荐 A：偏色 22.8 未解，默认开等于默认错色。依据 C3-T5。
4. GPU：P0 全 CPU，P1 上 wgpu？选项 A 是，B P0 即上 wgpu。推荐 A：
   对照噪声底已证 CPU 路径与 CL 同构，P0 先闭环正确性。依据 C4/C5。
5. 模块 crate 按域合包（4 包）还是每模块一包（21 包）？推荐合包（§6），
   理由编译负担；若追求极致隔离可选 21 包（代价：52 lane 外加约 5 lane 基建）。

## §9 没验证的

- RCD/AMaZE 真实移植耗时与画质（只测了 MHC 量级参考，RCD 估算偏上，未动手）。
- 色卡标定（偏色真修需 ColorChecker 实拍，不在本 lane）。
- 无-WB 链为何最近的完整解释（现象已记 T4，机理推断，未深究）。
- `--core --conf` 不写回的内部覆盖序（运行期生效已验证；持久化语义未深究，不影响对照用法）。
- 翻译层（OpenCL→WGSL 自动）未评估，默认手写移植。
- UniFFI/gpui 与 dt-app 能力表的实际接线（只读了 scout 结论，未动手）。
- 法务：GPL-3.0 + Apple 系统库 + rawspeed LGPL-2.1（静态链接可重链接义务）未做合规复核。
- 非 A7R5 机型、X-Trans、非 RGGB 全部未测；Windows/Linux 构建零证据。

## §10 复审修订记录（对照 core-design-review.log，双份独立复审）

Review A（首发 nohup，00:15 完成）：`PASS / 3 error + 11 minor`。
Review B（harness，00:11 先交付，23.8 分钟）：`PASS / 1 error + 10 minor`。
两份核心数字全部复跑通过（C3 checksum 逐位同、中位同量级 ±10%；
DNG 三轮 22.784/55.935/23.275 两份逐位同；C4 探针复跑出图 16 位；
噪声底/跨组/表抽查全对；§0 18 行内容）。统一修订（A/B 重叠项合并）：
E1(XMP 版本规则错→重写；真因是前导 XML 注释，probe-comment.xmp 自验证复现)；
A-E1(--conf 运行期生效不写回，自验证 bpp=8 覆盖；初稿“不生效”错)；
A-E3(C6 Cargo 门控重写：dt-apple 恒成员+空壳+target 依赖)；
M1(回调 57+1 重编号；23/31 精确数见 T1)；M2(P0 13 个)；
M3(37,561 加顶层口径，全量 47,986)；M4(2 次样本全列)；
M5(全分辨率镜像 0.0000/0.0000 入 fullres-mirror.log)；
M6(CMDS 补探针/计时前缀+before.plist 入库)；M7(三轮 bench cmp 日志入库)；
M8(T5 补推断；“上界”→“量级参考”)；M9(compare_down8.py+down8.log 精确复现归档)；
A-M3(CMDS 补 C3-DNG 节)；A-M4(cmp16-full.log 入库+stray 注+g1 sha)；
A-M9(S6 措辞/D65 标准矩阵/内存 typo)；A-M10(字段·字节/clipping 引文/roi_in:2575/grep 模式)；
A-M11(库锁坑注记)。两份复审日志合档 core-design-review.log。
