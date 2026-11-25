# PLAN-TABLES — 分波开发计划的长表（正文见 PLAN.md）

口径与证据：本文件所有上游事实可复现。仓库 HEAD = `1f9c1adb83399b5e403a8419d5fc65859c9f5a2f`（本 lane 亲核）。
上游参考树 = `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master`，`HEAD` = `679d594f5d`，`git describe` = **`release-5.7.0-2234-g679d594f5d`**。
**因此 master 不是发布版**：凡参数布局、modversion、顺序表，本计划一律钉 `release-5.7.0` tag（`git show release-5.7.0:<file>`，本地已有，不需要下载）；master 只用于已完成的调研对照。
「推断」= 无实测证据；「估算」= 按 lane 口径折算。

---

## T1 依赖与许可证（A1 的输入表，逐项待核实）

| 依赖 | 用途 | 来源/版本 | 许可证（待 A1 以实际文件核实） | 链接方式 | 义务 | 处置 |
|---|---|---|---|---|---|---|
| rawspeed | RAW 解包（P0 主路径） | dt 5.7.0 的 `src/external/rawspeed` gitlink（本机未 checkout，需 `git submodule update` 一次拿 LICENSE） | 调研写 LGPL-2.1；上游近年版本为 LGPL-3.0 —— **两说冲突，A1 以 gitlink 提交的 LICENSE 为准** | 静态链接进 `dt-decode`（C ABI shim） | 若 LGPL-3.0：LGPLv3 = GPLv3 + 附加许可，可整体按 GPL-3.0 分发，无重链接义务，保留声明；若 LGPL-2.1-or-later：同样可升到 GPL-3.0 | A1 定论并写入 NOTICE |
| lensfun | lens 模块的畸变/TCA/暗角 | dt 5.7.0 同级 external；数据文件独立授权 | 代码 LGPL-3.0；数据库 CC BY-SA（待核） | 动态或静态链接 | 代码同 rawspeed；**数据**保留原许可与署名，独立文件分发，不并入 GPL 代码 | A1 把代码/数据分开登记 |
| lcms2 | colorin/temperature/colorout 的 ICC 变换 | 系统/源码包 | MIT | 静态链接 | 保留版权与许可文本 | 直接可用 |
| libpng / libtiff / libjpeg | colorin 读取内嵌 ICC / 导出 | 可用纯 Rust 替代（`png`/`tiff`/`jpeg-encoder`） | MIT/Apache-2.0 | 纯 Rust | 无 | 优先纯 Rust，避开 C 依赖 |
| exiv2 | dt 用它读写 XMP/EXIF | 不采用（我们自选 XMP 库） | — | — | — | 见 T6 |
| XMP 库 | 历史读写 | 三候选见 T6 | 见 T6 | 见 T6 | 见 T6 | A4a 定 |
| SQLite | 图库数据库 | `rusqlite`（bundled） | SQLite public domain；rusqlite MIT | 静态 | 无 | 直接可用 |
| gpui / gpui-kit / gpui-fast | 界面 | `gpui-kit 0.11.0`（features `gpui-fast` → `gpui-fast 0.1.19`） | Apache-2.0（`gpui-spike/STATUS.md` 已更正 crates.io 空字段） | 静态 | 保留 NOTICE | **版本锁死**，升级要重跑视口 spike |
| objc2 / objc2-app-kit / objc2-quartz-core / metal | Apple 模块 | `objc2 0.6.5`、`objc2-*-0.3.2`、`metal 0.29` | MIT / Apache-2.0 | 静态 | 保留 NOTICE | 只允许出现在 `dt-apple` |
| image / jpeg-encoder / png / tiff / flate2 / zune-jpeg | 栅格与导出 | crates.io | MIT / Apache-2.0 | 纯 Rust | 保留 NOTICE | A1 逐条登记 |
| rayon / serde / crossbeam / parking_lot / bytemuck / thiserror / clap / tracing | 基础设施 | crates.io | MIT / Apache-2.0 | 纯 Rust | 保留 NOTICE | A1 逐条登记 |
| darktable 源码（移植） | 21→93 个模块（基线）+ 基线外 spektrafilm 等 | `release-5.7.0` tag；基线外取 master 并钉提交 | GPL-3.0-or-later | 源码级移植 | 保留原版权头 + 逐文件标注 `Modified for Lightamer: <date> <what>` + NOTICE | 每 wave 的 DoD |

**本项目的许可证变体裁定**：`GPL-3.0-or-later`（与 darktable 同变体，避免任何「3.0-only 能否吃 or-later 代码」的争论）。`LICENSE` = GPLv3 全文；`NOTICE` = 上游署名 + 修改声明 + 全部第三方依赖；每个源文件 SPDX 头 `GPL-3.0-or-later`。

---

## T2 仓库布局与体积/时间预算（A2）

```text
crates/
  dt-api/         # 命令/查询/事件 + CoreHandle（UI 唯一入口，零平台类型）
  dt-core/        # Frame/Roi/tiling/缓存/调度/PipeError（零平台相关）
  dt-iop-traits/  # ModuleDesc/IopModule/Params/Piece/ModuleFlags/Cst
  dt-registry/    # 顺序计算（raw/jpg 两链）+ 描述聚合 + 探针测试
  dt-iop-raw/     # rawprepare hotpixels demosaic rawdenoise demosaicscale rawoverexposed rasterfile
  dt-iop-geom/    # lens cacorrect cacorrectrgb ashift flip crop rotatepixels scalepixels enlargecanvas
  dt-iop-color/   # temperature colorin colorout lut3d spektrafilm channelmixer* colorbalance* colorzones …
  dt-iop-display/ # exposure highlights rgbcurve rgblevels tonecurve finalscale gamma dither overexposed …
  dt-decode/      # rawspeed C ABI shim + 栅格解码
  dt-color/       # lcms2 腿 + 矩阵数学
  dt-blend/       # 蒙版栅格化 + 混合
  dt-history/     # XMP 读写 + 参数布局 + 迁移 + 栈
  dt-library/     # SQLite 图库 + 导入 + 缩略图
  dt-export/      # 编码器与导出队列
  dt-apple/       # ★ 仅 macOS：CIRAW/ColorSync/Vision/ImageIO/Metal
  dt-app/         # 装配：按 target 与能力表选腿
  dt-cli/         # 命令行 + oracle 对照工具 + perf 探针
  dt-gpui/        # 界面（gpui 族）
  dt-lightamer/   # 独有功能：全景/焦点/HDR 合成、节点 DRT、版本分支、AI
Scripts/          # guard.sh build.sh test.sh oracle.sh perf.sh budget.sh
fixtures/         # dt-order-5.7.0.json、params 布局夹具、oracle XMP、CC0 样张路径清单
vendor/dt-5.7.0/  # 逐字拷贝的 params 结构体头 + 出处（不含整棵上游树）
```

| 预算项 | 门 | 判定命令 |
|---|---|---|
| 冷构建（空工作区→可跑测试） | ≤ 6 min | `time Scripts/build.sh --cold` |
| 增量构建单 crate | ≤ 40 s | `time cargo check -p dt-iop-color` |
| 全量测试（Phase 0 规模） | ≤ 3 min | `time Scripts/test.sh` |
| UI release 二进制 | ≤ 80 MB | `stat -f%z target/release/dt-gpui`（或 app 内主二进制） |
| app bundle 总计 | ≤ 200 MB（含 lensfun 数据） | `du -sk build/Lightamer.app` |
| `target/` 体积 | > 20 GB 触发清理 | `Scripts/budget.sh` |
| 机器守卫 | 每个重活前 PASS | `Scripts/guard.sh`（包住既有 `Scripts/machine-guard.sh`） |

---

## T3 模块描述字段（A3 的规格草案）

```rust
pub struct ModuleDesc {
    pub id: &'static str,              // darktable op 名，如 "temperature"；历史映射的唯一键
    pub display_key: &'static str,     // i18n 键（面板标题）
    pub group: Group,                  // darktable modulegroups: Base/Tone/Color/Correction/Effects
    pub order: OrderKeys,              // 见下：raw 与 jpg 两套，各带 tie 序
    pub params: ParamsDesc,            // struct 名 / 字节数 / 当前 modversion / 迁移函数指针
    pub flags: Flags,                  // tiling / blend / distort / hidden / deprecated
    pub colorspaces: ColorReq,         // default / input / output（dt 的 cst 枚举）
    pub panel: &'static [Control],     // 面板控件描述（界面生成用，见 §2.5）
    pub history: HistoryKeys,          // 别名、是否允许多实例、是否文档级（DT 的 doc 级模块）
}
pub struct OrderKeys { pub raw: (f32, u16), pub jpg: (f32, u16) } // (dt 优先级, 表内序)
```

**为什么 tie 序是字段**：v50 表在 `28.5` 有 6 个模块（channelmixerrgb/diffuse/censorize/negadoctor/blurs/primaries），dt 的顺序是表行序而非字母序；只靠优先级无法复现。（`contrastntexture` 也在 28.5，但它是 5.7.0 之后才加入的，不在本计划的基线里。）tie 序是模块自己的数据（它在 dt 表里的行序），不是核心里的槽号。
**raw 与 jpg 两套是必须的**：`release-5.7.0` 的 v50 与 v50_jpg 名集相同、**24 个模块优先级不同**（如 denoiseprofile 9.0 vs 28.0、lens 13.0 vs 28.0）。复现命令：

```bash
cd /Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master
for t in v50_order v50_jpg_order; do
  git show release-5.7.0:src/common/iop_order.c |
    sed -n "/const dt_iop_order_entry_t $t\[\]/,/^};/p" | grep -c '"'
done   # 两表各 94 行（93 个具名 + 尾哨兵）
```

---

## T4 自动发现与注册：三方案的坑与裁决（A3）

| 方案 | 机制 | 加一个模块要改什么 | 坑（已读代码/已知事实） | 裁决 |
|---|---|---|---|---|
| A. 每模块一 crate + `linkme`/`ctr` 分布式切片 | 链接器按 section 收集 `&ModuleDesc` | 新 crate **+ 聚合 crate 的 Cargo.toml 加一行依赖**（Cargo 无 glob 依赖） | 没有依赖边就被链接器丢（需 `#[used]`）；macOS `dead_strip` 与 section 名分平台；ctor 顺序未定义；`gpui-fast` 生态之外再添一个「未定义行为边缘」的宏 crate | 不取 |
| B. 域 crate 内 `build.rs` 扫目录生成 `mod` 与注册表 | 目录即模块，代码生成进 `OUT_DIR` 再 `include!` | **只加一个目录**（`crates/dt-iop-<域>/src/modules/<id>/mod.rs`） | 目录内任何改动会重编整个域 crate（缓解：4 个域 crate + `cargo check -p` 定向；实测代价待 A3 记录）；`rerun-if-changed` 必须指向目录本身才会递归监听 | **采用** |
| C. 构建期生成清单提交入库 + CI diff 校验 | 生成文件是唯一事实源 | 加目录 + 跑生成器 | 两份真相源，忘记重跑就静默漏模块 | 不取（可作 B 的兜底检查） |

**加目录即被发现**的机检（A3 交付物）：

```bash
# 1) 造一个探针模块目录
mkdir -p crates/dt-iop-display/src/modules/zz_probe
printf 'pub fn desc() -> ModuleDesc { ModuleDesc { id: "zz_probe", .. } }\n' > crates/dt-iop-display/src/modules/zz_probe/mod.rs
cargo test -p dt-registry --test discovery_probe   # 断言 registry 含 "zz_probe"
rm -rf crates/dt-iop-display/src/modules/zz_probe   # 复原
```
域 crate 固定为 4 个（raw/geom/color/display），这是架构分层，不是模块名单；钉住基线（`release-5.7.0`）的 93 个 op 名一个都不出现在核心代码里。

---

## T5 默认顺序夹具（A3 的验收数据）

- 夹具文件：`fixtures/dt-order-5.7.0.json`（**93 个具名条目 + 1 个哨兵**；每条 = `{name, raw_prio, raw_tie, jpg_prio, jpg_tie}`）。
- 生成命令（一次性、随夹具记录）：`git show release-5.7.0:src/common/iop_order.c` 解析 `v50_order[]` 与 `v50_jpg_order[]`，按行序写 tie。
- 测试：`cargo test -p dt-registry` 两条 —— ① `raw_chain == fixture.raw`（93 名逐位）；② `jpg_chain == fixture.jpg`。另加负测：把两个模块的 tie 互换，测试必须失败。
- 第 0 期 21 模块的 row（与 `CORE-DESIGN-TABLES.md` T2 一致，已复核）：

| op | raw prio | jpg prio | modversion @5.7.0 | T2 字节数 | 5.7.0 结构体手算 | 备注 |
|---|---:|---:|---:|---:|---:|---|
| rawprepare | 1.0 | 1.0 | 2 | 32 | 32 | ✓ |
| temperature | 3.0 | 3.0 | **4** | 24 | **20** | ✗ T2/HISTORY 取的是 master 的 v5（多 `late_correction`） |
| highlights | 4.0 | 4.0 | 4 | 40 | **48** | ✗ T2 为 v3 尺寸（缺 `solid_color`） |
| cacorrect | 5.0 | 5.0 | 2 | 8 | 待夹具 | |
| hotpixels | 6.0 | 6.0 | 1 | 16 | 待夹具 | |
| demosaic | 8.0 | 8.0 | 6 | 60 | **48** | ✗ 5.7.0 结构体 12 个 4B 字段 |
| lens | 13.0 | 28.0 | 10 | 356 | 待夹具 | 26 字段按 LP64 展开 |
| cacorrectrgb | 13.5 | 28.0 | 1 | 20 | 待夹具 | |
| ashift | 15.0 | 28.0 | 5 | 892 | 待夹具 | |
| flip | 16.0 | 28.0 | 2 | 4 | 4 | |
| exposure | 21.0 | 28.0 | 7 | 28 | 28 | ✓ |
| crop | 24.5 | 28.0 | 3 | 24 | 24 | ✓ |
| colorin | 28.0 | 28.0 | **7** | 1048 | **1044** | ✗ T2/HISTORY 取的是 master 的 v8 |
| rgbcurve | 42.0 | 42.0 | 1 | 516 | 待夹具 | |
| rgblevels | 43.0 | 43.0 | 1 | 44 | 待夹具 | |
| tonecurve | 48.0 | 48.0 | 5 | 520 | 待夹具 | |
| finalscale | 69.4 | 69.5 | 1 | 4 | 4 | |
| colorout | 70.0 | 70.0 | 5 | 520 | 520 | ✓ |
| overexposed | 73.0 | 73.0 | 无 params | 0 | 0 | |
| dither | 75.0 | 75.0 | 2 | 32 | 待夹具 | |
| gamma | 78.0 | 78.0 | 1 | 8 | 8 | |

**结论（写进 A4b 的红线）**：T2 的字节数**不是实现规格**，其中至少 4 处是 master 值、与 `release-5.7.0` 二进制不符。唯一真值 = 用 clang 对 `vendor/dt-5.7.0/` 的逐字结构体跑 `sizeof/offsetof` 生成的 JSON 夹具，再与 oracle 生成的 XMP 里每条 `modversion` + `params` 十六进制长度**双向对照**。

---

## T6 XMP 库三候选与三条测试（A4a）

| 候选 | 语言/构建 | 保留未知 key 的把握 | 许可 | 主要风险 | 备注 |
|---|---|---|---|---|---|
| `xmp_toolkit` | 绑 Adobe XMP Toolkit SDK（C++，需 cmake） | 高（Adobe 的 RDF/XML 实现，语义最全） | Adobe BSD 类（GPL 兼容，待 A1） | 引入 C++ 构建；macOS 上 cmake 工具链；包维护活跃度 | 首选**若**三测全过 |
| `xmpkit` | 纯 Rust，年轻 | 未知（需读源码验证 unknown-key 路径） | 待核 | 成熟度；RDF/XML 边界 | 次选 |
| XML 直改（`quick-xml`） | 纯 Rust | 只改我们命名空间节点，其余字节不动 | MIT/Apache | 必须自己实现 RDF 容器语义、hex/gz、数组项；写回可能重排属性 | 兜底 |

三条测试（同一 lane，按序跑，全过才可选）：

1. **读**：读一份 darktable 真写的 XMP（oracle 产出，含 3 个模块 + 1 个多实例），断言 41 个已知 key 中出现的那些、每条历史的 10 个属性、`history_end`、`iop_order_version/list` 全部解析正确；参数 blob 与 oracle 的十六进制逐字节相等。
2. **写保真**：加上我们的命名空间（`lightamer:history`）写回，断言原文件除我们的节点外**语义等价**（解析后的 key→值集合不变；用 canonical XML 比较，不比较字节）。
3. **交叉重写**：让 darktable 对该图再写一次 sidecar，断言我们的命名空间节点与全部条目仍在，且 darktable 的历史未被破坏。

**裁决规则**：候选必须三条全过；`xmp_toolkit` 与 `xmpkit` 都过则选构建更简单的；都不过则 XML 直改，并把测试 2 的 canonical 比较降级为「已知 key 集合 + 历史条目逐字节」。

---

## T7 第 0 期 21 模块清单（版本 = `release-5.7.0`，lane = 估算）

| # | 模块 | 源文件 | 行数 | .cl 来源 | lane | 外部依赖 | 难点 |
|---|---|---|---:|---|---:|---|---|
| 1 | rawprepare | `iop/rawprepare.c` | 1,112 | basic.cl | 1 | 无 | 黑电平/白点、flat field 枚举 |
| 2 | temperature | `iop/temperature.c` | 2,385 | basic.cl | 2 | lcms2 | as-shot WB + CCT↔xy 数学 |
| 3 | highlights | `iop/highlights.c` | 1,451 | basic.cl | 2 | 无 | 4 种模式 + 小波重建 |
| 4 | cacorrect | `iop/cacorrect.c` | 1,806 | cacorrect.cl | 2 | 无 | 迭代寻边 |
| 5 | hotpixels | `iop/hotpixels.c` | 588 | basic.cl | 1 | 无 | 3×3 检测 + 插值 |
| 6 | demosaic | `iop/demosaic.c` + `demosaicing/` | 2,244 + 7,722 | rcd/ppg/vng/markesteijn/amaze/lmmse | 4 | 无 | **RCD 移植 + 回退语义** |
| 7 | lens | `iop/lens.cc` | 5,209 | basic.cl | 3 | lensfun | 数据库接入 + 三种校正 |
| 8 | cacorrectrgb | `iop/cacorrectrgb.c` | 953 | cacorrectrgb.cl | 2 | 无 | 三通道径向 |
| 9 | ashift | `iop/ashift.c` + 求解器 | 6,280 + 2,703 | basic.cl | 3 | 无 | 自动求解器裁剪（P0 只做手动参数） |
| 10 | flip | `iop/flip.c` | 631 | basic.cl | 1 | 无 | 方向枚举 |
| 11 | exposure | `iop/exposure.c` | 1,392 | basic.cl | 1 | 无 | deflicker 三模式 |
| 12 | crop | `iop/crop.c` | 2,035 | copy | 2 | 无 | ROI 语义 + 比例 |
| 13 | colorin | `iop/colorin.c` | 2,622 | basic.cl | 2 | lcms2 | 相机矩阵 + 工作空间 |
| 14 | rgbcurve | `iop/rgbcurve.c` | 1,958 | rgbcurve.cl | 2 | 无 | 曲线插值 |
| 15 | rgblevels | `iop/rgblevels.c` | 1,529 | rgblevels.cl | 2 | 无 | 同上 |
| 16 | tonecurve | `iop/tonecurve.c` | 1,987 | basic.cl | 2 | 无 | 三通道 + 单色 |
| 17 | finalscale | `iop/finalscale.c` | 270 | 公共 | 1 | 无 | 缩放 |
| 18 | colorout | `iop/colorout.c` | 1,532 | basic.cl | 2 | lcms2 | 输出 ICC + intent |
| 19 | overexposed | `iop/overexposed.c` | 442 | basic.cl | 1 | cairo（GUI） | P0 只做像素标注，不做 cairo 叠加 |
| 20 | dither | `iop/dither.c` | 788 | extended.cl | 1 | 无 | 两种抖动 |
| 21 | gamma | `iop/gamma.c` | 347 | CPU-only | 1 | 无 | 8/16 位输出 |

合计 **38 lane**（与 `CORE-DESIGN.md` §7 同数），顶层 C/C++ 37,561 行、全量 47,986 行（含 demosaicing/ 与 ashift 求解器）。
**P0 明确不做**：AMaZE/LMMSE/Markesteijn/VNG/PPG 的算法菜单（只留 RCD + passthrough）、ashift 自动求解器（只做手动参数）、cairo 叠加层、OpenCL/WGSL 版。

---

## T8 波次与 lane 汇总（估算）

| 阶段 | 波数 | lane | lane 墙钟（1.5h/lane） | 说明 |
|---|---:|---:|---:|---|
| A 地基 | 9 | 17 | **43.5 h** | A1/A2/A3/A4a/A4b/A5/A6/A7a/A7b（按卡片 2–3 h/lane） |
| B 第 0 期 | 20 | 76 | **208 h** | 模块 38 + 管线/解码 5 + 历史 6 + 蒙版 5 + 图库 4 + 导出 3 + UI 15 |
| **A+B** | **29** | **93** | **251.5 h** | 含域内自审与修订再 +20% ≈ 302 h ≈ 38 个 8h 工作日（单机、一次一个重活） |
| C 第 1 期 | ≈22 波 | ≈130 | ≈325 h | 50 个模块 + 9 个功能面（不展开；按 2.5 h/lane 估） |
| D 第 2 期 | ≈10 波 | ≈60 | ≈150 h | 20 个长尾模块 + 6 个非暗房域（不展开；按 2.5 h/lane 估） |

**与 `CORE-DESIGN.md` 的 52 lane 对账**：那 52 = 模块 38 + infra 14（pipe 3、decode 2、blend/mask 2、色彩显示 2、导出 2、导入图库历史 3）；本计划 B 的 76 = 模块 38 + 管线/解码 5 + 历史 6 + 蒙版 5 + 图库 4 + 导出 3 + UI 15 —— 差额 24 lane 是 `CORE-DESIGN.md` 明确不含的界面（15）、历史读写（6）、蒙版上调（3）。

校准口径：调研 lane 实测 1 条 1–2 h 交付约 1,000 行带测试的代码；**实现卡片的单 lane 按 2–3 h 记**（含 golden 与修订），故本表与卡片逐波相加一致（A 43.5 + B 208 = 251.5 h）。**这是估算**；模块 lane 数高的是移植面（demosaic 4、lens 3、ashift 3），不是难点未知。
**机器约束**：机器级单重活 —— lane 不是并行数。编译一律共享 target 目录 + `flock`，同一时刻只有一份 `cargo`；显示为「lane 墙钟」而非「日历时间」。

---

## T9 73 个 Metal 着色器的处置（P0 = 第 0 期可直接参考）

| 分类 | 数量 | 名单 | 怎么用 |
|---|---:|---|---|
| P0 直接参考 | 19 | ExposureKernels, TemperatureKernels, LensKernels, FlipKernels, AshiftKernels, ToneCurveKernels, LevelsKernels, WhiteBlack, BlendOpKernels, MaskCombineKernels, MaskRasterKernels, ParametricMaskKernels, MaskEdgeKernels, MaskPostProcessKernels, HistogramReduceKernels, ScopeReduceKernels, GaussianBlurKernels, LabKernels, Cat02WB | 交叉核对 Rust CPU 实现的公式与 uniform 布局；**不当作移植源**（真源是 dt 的 `.cl`/`.c`） |
| P1 参考（dt 全量调色/细节） | 35 | ColorBalanceRGBKernels, ColorWheels, ColorZonesKernels, Hls, Saturation, Tint, Contrast, ColisaKernels, ChannelMixerKernels, ChannelMixerRGBKernels, ColorContrastKernels, FilmicRGBKernels, SigmoidKernels, AgXKernels, VelviaKernels, VibranceKernels, Lut3dKernels, GrainKernels, SharpenKernels, ToneEqualKernels, EqualizerKernels, DenoiseProfileKernels, NLMeansKernels, BilateralKernels, BilateralGrid3DKernels, LiquifyKernels, RetouchKernels, VignetteKernels, SoftenKernels, BloomKernels, HighpassKernels, LocalContrastKernels, ShadhiKernels, DehazeKernels, MonochromeKernels | 同上；这些是 Lightamer 对 dt 模块的自研移植，公式可参考、常数不可照抄（它们的参数范围按旧管线调过） |
| 独有功能参考（P1） | 10 | Aces2Kernels, OpenDrtKernels, DrtEotfKernels, TerminalKernels, ACESccConvert, ACESccMath, FilmPlacementKernels, FilmSubRunKernels, SpectralFilmKernels, SpectralSpatialKernels | 只服务「保留的 Lightamer 独有功能」（节点式 DRT、版本分支）；**胶片模拟改用 dt 的 `spektrafilm`，这 10 个不是它的源** |
| 用不上 | 9 | YiyinKernels, TextOverlayKernels, EditorBlitShader, StackKernels, RasterInputKernels, Passthrough, TestGain, SkinSmoothKernels, ColorMatchKernels | EditorBlitShader = 旧视口 blit（被 gpui 视口取代）；Stack/RasterInput/TestGain/Passthrough = 测试脚手架；SkinSmooth = 人像三件不排期；ColorMatch = 不在保留清单；Yiyin/TextOverlay = 印框的文字层（P1 的 borders/watermark 以 darktamer 的 `borders.c` 为源，不以这两个 kernel 为源） |

合计 19+35+10+9 = **73**（`find . -name '*.metal' -not -path './.work/*' | wc -l` = 73，逐名核对）。

---

## T10 阶段 C / D 的模块划分（第 0 期之外的 77 个）

| 归属 | 数量 | 模块 |
|---|---:|---|
| C 第 1 期 | 50 | filmicrgb, sigmoid, agx, colorbalance, colorbalancergb, colorzones, colorequal, colorharmonizer, colorcontrast, velvia, vibrance, primaries, channelmixer, channelmixerrgb, lut3d, colorchecker, colormapping, colortransfer, toneequal, equalizer, levels, shadhi, denoiseprofile, nlmeans, bilateral, atrous, sharpen, diffuse, defringe, hazeremoval, retouch, spots, liquify, rotatepixels, scalepixels, rawdenoise, rawoverexposed, colorreconstruct, borders, watermark, blurs, lowpass, highpass, soften, bloom, grain, vignette, monochrome, colorize, splittoning |
| D 第 2 期 | 20 | invert, tonemap, graduatednd, profile_gamma, basecurve, filmic, negadoctor, zonesystem, globaltonemap, relight, colisa, bilat, colorcorrection, basicadj, lowlight, clahe, censorize, enlargecanvas, overlay, rasterfile |
| 永不实现 | 2 | clipping（上游已 deprecated，crop + ashift + rotatepixels 覆盖）, useless（上游测试模块） |
| 第 0 期内部占位 | 1 | mask_manager（无 params、无处理；只为历史条目里的 `mask_manager` 能原样保留） |
| 合计 | 73 | 50+20+2+1 = 73 = **72 个 v50 余量**（93 − 21）+ `useless`（不在 v50 表） |

**基线之外（`release-5.7.0` 没有，master 才有）**：`contrastntexture`、`demosaicscale`、`satcurvergb`、`spektrafilm`、`neutral` 五个。其中 **`spektrafilm` 是用户要求的功能**，但 5.7.0 发布版没有它 —— 处置见 PLAN.md §1.3 与 §6.1 R11（C 期从 master 取源，**无 oracle 对照**，验收降为往返 + 目视 + 参数自洽）。另外四个随 C/D 顺路，同样从 master 取源并标注。

C/D 的分界标准：C = 日常或专业工作流会用到的（含全部调色、细节、降噪、局部修饰、几何补充、darktamer 的边框/水印）；D = 被其它模块实质替代（basecurve/filmic→filmicrgb/agx、zonesystem/globaltonemap→toneequal）、依赖旧范式（profile_gamma/basicadj/invert/rasterfile）、或纯长尾（negadoctor/colorize/splittoning/lowlight/clahe/censorize/enlargecanvas/overlay/relight/colisa/colorcorrection/bilat/tonemap/graduatednd）。

---

## T11 性能基线（#26 实测，作为第 0 期的对照与门）

| 指标 | darktable 5.6.2 实测口径 | 值 | 我们的第 0 期门（估算目标） |
|---|---|---:|---|
| 冷开（进程起→视口稳定） | GUI，A7R5 | 6.24 s（其中启动 4.45 s） | ≤ 4.0 s（含启动） |
| 首图（窗口出现→预览就绪） | GUI | 1.79 s | ≤ 1.2 s（fitted 2560） |
| 编辑等待 M2 | 曝光 ±0.5 EV→位图 | 0.680 s 中位 | ≤ 0.20 s p50（fitted，CPU 全链） |
| 缩略图 | 单线程 crawler | 80 ms/张 | ≥ 15 张/s（并行后） |
| 批量粘贴 101 张 | GUI | ≈2 s | ≤ 2 s（DB-only 任务） |
| 导入 101 张 | GUI | < 4.7 s（窗口出现前完成） | ≤ 4.0 s |

门的性质：前两列是**实测**；右列是**目标**，第一次由 `Scripts/perf.sh` 测出后改为实测并写进 issue（#26）。
