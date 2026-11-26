# Apple 边界（`dt-apple`）

> A6 交付。中文正文，标识符英文。规则正文在这里，机检在
> `crates/xtask/src/apple_boundary.rs`，链接门在
> `Scripts/rust-apple-boundary.sh`。

## 1. 规则与理由

用户裁决：Apple 能力独占一个模块，只在 macOS 构建里存在（PLAN §1.1）。
落点如下，每条都有机检或构建门，不靠自觉。

1. **只有 `dt-apple` 碰 Apple 框架。** 其它 crate 不直接依赖 Apple 绑定
   crate（名单见机检规则 1），源码里不出现桥接 token 与 target-OS `cfg`
   （规则 3）。理由：跨平台 port 时只需换这一个 crate；散落的 `cfg` 是
   移植时最先烂掉的东西。
2. **核心和界面只读能力表。** `dt_apple::capabilities()` 返回平台事实，
   调用方不写任何 `cfg`。理由：把「平台有没有」和「功能做没做」分成两
   层；这一波表里只有平台事实（见 §3）。
3. **`dt-apple` 每个平台都编译，接口各平台一致。** 空后端在全平台参与
   编译（含 macOS），选用哪个后端全 crate 只有一处（两个完整 `cfg`
   块，`crates/dt-apple/src/capabilities.rs` 的 `selected_backend`）。
   理由：空后端的正确性在本机就能查；选择点唯一，grep 即得。
4. **接口里没有框架类型。** `CIImage`、`MTLDevice`、`CGColorSpace` 等只
   存在于 `macos.rs` 内部；对外只有标准库类型和本 crate 类型。理由：
   调用方不被框架类型污染，换后端不改调用方。
5. **绑定依赖只在 macOS 目标表。** 普通 `[dependencies]` 为空（规则 2
   查）。理由：非 macOS 解析出零第三方依赖（链接门第 2 步查）。
6. **`unsafe` 只在 `macos.rs` 内。** 模块外保持 `unsafe_code = "deny"`；
   模块内每处 `unsafe` 带 `SAFETY` 说明，并拒绝
   `unsafe_op_in_unsafe_fn` 与 `clippy::undocumented_unsafe_blocks`。
   理由：内存安全审计面收敛到一个文件。

## 2. 新增一项 Apple 能力的步骤

1. **依赖**：加到 `crates/dt-apple/Cargo.toml` 的
   `[target.'cfg(target_os = "macos")'.dependencies]`。普通
   `[dependencies]` 不许加（规则 2 会报）。版本先与 spike 锁表对齐；
   新 crate 先过 A1（许可证检查）。
2. **代码**：探针与调用放 `src/macos.rs`；对外类型放
   `src/capabilities.rs`（只用标准库类型 + 本 crate 类型）；空后端在
   `src/empty.rs` 给同一字段的诚实空值。禁止新增第二处后端选择。
3. **能力表**：只放平台事实。若新字段是「功能是否实现」，不许进表。
4. **测试**：`capabilities.rs` 的 tests 里给空后端加断言（新字段的空值），
   并更新穷举解构测试 `capability_table_has_every_field`；macOS 真值走
   `dt-cli capabilities` 人工/脚本核，不进单元断言（环境相关）。
5. **机检名单**：若新依赖的 crate 名不在规则 1 名单里，把它加进
   `APPLE_EXACT`（改这一处），并给规则 1 加一个单元用例。
6. **文档**：本文件 §3 加一行字段说明；`docs/LICENSE-AUDIT.md` 按 A5
   先例追加采用记录。

## 3. 能力表字段

`dt_apple::capabilities()` 首次调用探一次（`OnceLock`），之后返回同一份。
探针只做：查类、建一个设备对象、问格式列表、建两个色彩空间。不解码、
不读样张、不开窗口。

| 字段 | 探法 | 本机值（Apple M4 / macOS 27.3） |
|---|---|---|
| `backend` | 选择点 | `macos`（空构建为 `empty`） |
| `metal_device_name` | `MTLCreateSystemDefaultDevice` + `name` | `Apple M4` |
| `writable_image_formats` | `CGImageDestination::type_identifiers` 问列表，只认 JPEG/PNG/TIFF/HEIC/AVIF/WebP 六种 UTI | 除 WebP 全有（`org.webp` 不在列表） |
| `ci_raw_filter` | `CIRAWFilter` 类在不在 | 有 |
| `vision_requests` | 五个请求类（face_rectangles/face_landmarks/rectangles/horizon/person_segmentation）在不在 | 全有 |
| `standard_spaces` | `CGColorSpace::with_name` 建 sRGB 与 Display P3 | 都建成 |

`CIRAWFilter` 与 Vision 五类用运行时类表查（`AnyClass::get`），无 panic
路径。为防链接器丢掉「只被类表查」的框架，探针先对 CoreImage、Vision
各取一个静态符号地址作链接钉（`linkage_pins`，见源码注释），再查类。

## 4. 机检四条

`cargo xtask check-apple-boundary`（与 `layers.rs` 同形：读
`cargo metadata --format-version 1 --no-deps`，规则引擎可单测）：

1. **依赖名单**：除 `dt-apple` 外，工作区 crate 的直接依赖不许出现名单
   crate。名单常量 `APPLE_EXACT` + `OBJC2_PREFIX` 前缀族（`objc2` 开头
   全部），增删改这一处。报错带 crate 名与依赖名。
2. **`dt-apple` 目标表**：名单依赖必须挂 macOS 目标表下。报错带依赖名
   与实际 gate（`None` 即普通表）。
3. **源码扫描**：`crates/`、`apps/` 下 `.rs`（源码、构建脚本、测试），除
   `crates/dt-apple/` 外，不许出现五种 token（桥接 crate 名、Core
   Foundation/Graphics 下划线名、两种 target-OS `cfg` 写法）。报错带
   文件与行号。说明文档不扫描。
4. **读不到元数据就失败**：`cargo metadata` 失败或输出解析失败时非零
   退出并说明原因，不当通过。

链接门（`Scripts/rust-apple-boundary.sh`，不进 `rust-ci-lite.sh`，因它要
换 feature 重建）：四条机检 + linux 目标树单行 + mac 目标树含 objc2 族 +
无 feature 二进制的 `otool -L`/`nm -u` 双零 + 空后端输出 + 默认重建真值。
旧写法（`nm -u | grep -iE 'objc|…'`）只作对照数记录：`-i` + `vision` 会被
`Revision` 类符号误伤，且框架链接信息比符号名猜测可靠。

## 5. Lint 放行

- `dt-apple` 根部拒绝：下标索引、`unwrap`、`expect`、`panic!`、`todo!`、
  `unimplemented!`（A4b 在 `dt-history` 立的规矩）；测试模块内放开前三条。
- `unsafe`：仅 `src/macos.rs` 顶部 `#![allow(unsafe_code)]`，且该文件内再
  `#![deny(unsafe_op_in_unsafe_fn)]` +
  `#![deny(clippy::undocumented_unsafe_blocks)]`；每处 `unsafe` 块上方有
  `SAFETY` 说明（共三处：读两个框架常量、取格式列表、数组元素类型断言）。
- `struct_excessive_bools` 在 `VisionRequests` 上 allow：五个独立探针
  事实，位标记会藏名。
- 检查器自宿主：`apple_boundary.rs` 自身受规则 3 与裸 `rg` 门约束，被查
  token 在源码里用 `concat!` 拼装（编译期零代价），注释里也不出现字面。
  拼装正确性的行为证据是 §8 活体负测（真拼写能报出来），不是单测里的
  字面量。

## 6. 本机验证与未验证

已验证（命令与输出见 `waves/A6-REPORT.md`）：默认构建 `capabilities`
打印上表真值；`--no-default-features` 构建键相同、值全空；链接门六步全
绿（框架行 0、符号行 0）；两次活体负测（源码 token、目标表挪位）检查均
非零报出且撤除后工作区干净；`cargo tree` 两目标输出符合预期。

已关闭（2026-11-26）：本机已装 `x86_64-unknown-linux-gnu` 目标（A-18），
`cargo check -p dt-apple --target x86_64-unknown-linux-gnu --locked` 通过；
A7b 起该命令接进 `Scripts/rust-apple-boundary.sh`（目标缺席则打印跳过），
每波必查。替代证据（锁解析层零依赖 + 空后端全平台编译）仍然有效。

## 7. Spike 最小调用对照

只抄探针需要的行，不解码（spike 源码
`.work/gsd/phases/rust-core/SPIKE-RUST-APPLE-src/`）：

| 能力 | spike 文件 | 抄的行 |
|---|---|---|
| Metal 设备 | `src/s1/main.rs`、`src/s4/main.rs` | `MTLCreateSystemDefaultDevice` + `device.name()` |
| ImageIO 格式 | `src/s3/main.rs`（编码三格式）+ ImageIO 列表 API | 本波用 `type_identifiers` 问列表（spike 只编码不断言列表） |
| CIRAW 类 | `src/s1/main.rs`（`CIRAWFilter::filterWithImageURL`） | 本波只查类在不在，不建 filter |
| Vision 类 | `src/s2/main.rs`（请求 + 回调通道） | 本波只查五个请求类在不在，不跑请求 |
| 色彩空间 | `src/s1/main.rs`（`CGColorSpaceCreateWithName` 扩展线性）、`src/s3/main.rs`（ICC 建空间） | 本波用 `with_name` 建 sRGB/Display P3 命名空间 |

依赖版本与 spike `Cargo.lock` 一致：`objc2 0.6.5`、七个框架绑定
`0.3.2`（foundation/core-foundation/core-graphics/metal/core-image/
image-io/vision）；spike 的 `block2`/`libc`/`cc`/`uniffi` 本波不用
（无回调、无 C 构建、无跨语言桥），`block2`/`dispatch2`/`libc` 仅作
传递依赖进入。

## 8. 管辖边界

本规则管：我们自己写的代码，以及我们直接写进清单的依赖名。不管：界面
框架（gpui 族）自带的平台代码——那是第三方 crate 内部实现，不在直接依赖
名单里查，也不扫它的源码。

A7b 裁定（§7 遗留问题的答案）：规则的管辖止于我们自己的代码与直接依赖。
框架内部的平台代码是它自己的事；从我们这边过去的只有一个整数（原生表面
句柄），除此之外界面 crate 不知平台为何物。指针事件与图层句柄只在同一个
进程、同一个地址空间里有效，不做跨进程传递，不做序列化。

## 9. A7b 视口（`dt-apple` 内，`dt-gpui` 外）

`dt-apple` 新增视口模块（A7b）：对外只有本 crate 类型（`ViewportRect` /
`ViewportGeom` / `FrameReport` / `NativePointerEvent` / `ViewportError` /
`ViewportHandle`）与标准库类型；macOS 后端在 `macos.rs` 内实现（沿用第 6
条：`unsafe` 不出该文件，每处带 `SAFETY` 说明），空后端在 `empty.rs` 对同
一接口诚实返回 `Unsupported`。

- **接缝是一个整数**：`attach_viewport(native_handle: usize, rect)` 与
  `attach_viewport_with_input(native_handle, rect, sink)`。`dt-gpui` 从框架
  拿到整数，原样交过来；它自己的源码里不出现任何桥接 token（机检规则 3
  与裸 `rg` 门双重覆盖）。
- **后端选择仍是一处**：`BackendProbe` trait 多了一个方法，`selected_backend`
  照旧是全 crate 唯一的 `cfg` 选择点；视口经它分发，不新增第二处选择。
- **能力表不动**：视口有无由 `backend` 字段推导（`MacOs` 才试 attach，失败
  则占位），不新增字段（§2 第 3 条：功能是否实现不进表）。
- **新增依赖**：`objc2-app-kit =0.3.2`、`objc2-quartz-core =0.3.2`，macOS
  目标表下（第 5 条照旧：普通表为空，非 macOS 解析出零第三方依赖）。
  spike 另用的 `metal` 与 `core-graphics-types` 未引入：渲染走既有的
  `objc2-metal`，几何类型走既有的 `objc2-core-foundation`。
- **路径乙的子类视图**是后端的内部实现细节：对外只交付
  `NativePointerEvent` 数据，不暴露视图类型。
