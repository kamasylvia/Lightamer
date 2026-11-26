# A6 Report — Apple Module Boundary (lane A6, omp)

结论：边界、能力表、四条机检、链接门、文档全落地，§11 验收全绿。
工作区 116 → 132 测试（+16），零失败。冷构建 17s（门 360s）。
起始 HEAD `04c84b8d`（亲核一致）；详见下。

## 1. `dt-apple` 的结构与后端选择

四文件（`crates/dt-apple/src/`）：`lib.rs`（ lint 根 + 重导出）、
`capabilities.rs`（公开类型 + 选择点 + `OnceLock` 缓存）、`empty.rs`
（空后端，全平台编译）、`macos.rs`（macOS 后端，
`#[cfg(target_os = "macos")]` 模块）。

- 对外接口各平台一致：`Backend`、`Capabilities`、`ImageFormat`、
  `VisionRequests`、`StandardSpaces`、`capabilities()`；只有标准库类型
  与本 crate 类型，无框架类型。
- 全 crate 唯一选择点（`capabilities.rs`）：
  ```rust
  #[cfg(target_os = "macos")]
  fn selected_backend() -> &'static dyn BackendProbe { &super::macos::MacOsBackend }
  #[cfg(not(target_os = "macos"))]
  fn selected_backend() -> &'static dyn BackendProbe { &super::empty::EmptyBackend }
  ```
  私有 trait `BackendProbe`（`pub(crate)`，不导出），其余源码零散 `target_os`
  cfg 为零（`mod macos` 的门是模块级例外；另有一处常规 `#[cfg(test)]`）。
- 绑定依赖只在 `[target.'cfg(target_os = "macos")'.dependencies]`（8 条，
  版本钉 spike 锁表：`objc2 =0.6.5` + 七个 `=0.3.2` 框架绑定），普通
  `[dependencies]` 为空。
- `unsafe` 只在 `macos.rs`：顶部 `#![allow(unsafe_code)]` +
  `#![deny(unsafe_op_in_unsafe_fn)]` +
  `#![deny(clippy::undocumented_unsafe_blocks)]`；三处 `unsafe` 块各带
  `SAFETY` 说明（读两个框架常量、取格式列表、数组元素类型断言）。
- Lint：根部拒下标/`unwrap`/`expect`/`panic!`/`todo!`/`unimplemented!`
  （A4b 规矩）；测试模块放开前三条；另有两处注明理由的 allow
  （`struct_excessive_bools` 于 `VisionRequests`；macOS 下 `EmptyBackend`
  仅测试构造的 `dead_code`）。

## 2. 能力表字段与本机值

`dt_apple::capabilities()` 首调探一次、之后返回同一份（`OnceLock`；
`std::ptr::eq` 单测钉死）。只放平台事实。`target/debug/dt-cli
capabilities`（默认 feature，Apple M4 / macOS 27.3）：

```text
backend=macos
metal.device=Apple M4
imageio.jpeg=true
imageio.png=true
imageio.tiff=true
imageio.heic=true
imageio.avif=true
imageio.webp=false
ciraw.available=true
vision.face_rectangles=true
vision.face_landmarks=true
vision.rectangles=true
vision.horizon=true
vision.person_segmentation=true
colorspace.srgb=true
colorspace.display_p3=true
```

探法：Metal 建默认设备读名；ImageIO 问 `type_identifiers` 列表取六种
UTI 交集（`org.webp` 不在列表，如实 false）；`CIRAWFilter` 与 Vision
五类查运行时类表（`AnyClass::get`，无 panic 路径；CoreImage/Vision 各一
静态符号地址作链接钉，防链接器丢框架致假阴性）；ColorSync 用 `with_name`
建 sRGB/Display P3。不解码、不读样张、不开窗口。

`dt-cli` 经默认开的 `apple` feature 依赖 `dt-apple`；`--no-default-features`
构建打印同样 16 个键，`backend=empty`、`metal.device=none`、其余 false。

## 3. 机检与链接门

`cargo xtask check-apple-boundary`（`crates/xtask/src/apple_boundary.rs`，
`layers.rs` 同形：`cargo metadata --no-deps` + 自研微型 JSON 解析，零依赖）：

1. 名单依赖隔离：除 `dt-apple` 外直接依赖禁名单 crate（`APPLE_EXACT`
   14 名 + `OBJC2_PREFIX` 前缀族，增删改这一处）；报错带 crate 与依赖名。
2. `dt-apple` 目标表：名单依赖须挂 macOS 目标表；报错带依赖名与实际 gate。
3. 源码扫描：`crates/`、`apps/` 下 `.rs`，除 `crates/dt-apple/` 外禁五种
   token（桥接 crate 名、Core Foundation/Graphics 下划线名、两种
   target-OS `cfg` 写法）；报错带文件与行号。
4. 元数据不可读则非零退出并说明原因，不当通过。

检查器自宿主：被查 token 在其源码（含注释、单测）中用 `concat!` 拼装，
裸 `rg` 门干净；拼装正确性的行为证据是活体负测（§6）。

`Scripts/rust-apple-boundary.sh`（六步，任败即非零；不进总检查）：机检 +
linux 树单行 + mac 树含 objc2 族 + 无 feature 二进制双零（`otool -L` 框架
行 0、`nm -u` 新 pattern 行 0）+ 空后端输出 + 默认重建真值。旧 pattern
（`-iE 'objc|CoreImage|ColorSync|Vision'`）作对照数记录，本机为 0。

## 4. 冷构建

`Scripts/rust-budget.sh --cold`（删 `target/` 后全量，`-j6`）：

```text
rust-budget: cold-build = 17s (gate <=360s) PASS
rust-budget: check dt-iop-color = 0s (gate <=40s) PASS
rust-budget: release dt-gpui = N/A (no UI binary at A2) PASS
rust-budget: target/ = 480MB (492220KB, gate <=20GB)
rust-budget: overall PASS
```

objc2 族进树后冷构建仍远低于门，无需绕行。

## 5. 新增依赖与允许清单

直接 8（见 §1）+ 传递 11（`block2 0.6.2`、`dispatch2 0.3.1`、
`libc 0.2.191`、`objc2-encode 4.1.0`、`objc2-av-foundation 0.3.2`、
`objc2-core-audio 0.3.2`、`objc2-core-audio-types 0.3.2`、
`objc2-core-media 0.3.2`、`objc2-core-ml 0.3.2`、`objc2-core-video 0.3.2`、
`objc2-io-surface 0.3.2`；`bitflags 2.13.2` 已在 A5 登记）。19 个（名，
版本）全部已在 `docs/LICENSE-AUDIT.md` §4 登记且逐字相同，无需加行；
许可证表达式（`MIT` / `Zlib OR Apache-2.0 OR MIT` / `MIT OR Apache-2.0`）
全部已在 `Scripts/licenses-allow.txt`，未动该文件。
`Scripts/check-licenses.sh`：`allow=69 exception=0 fail=0`，退出 0。
审计表追加 §10 采用记录（append-only）；`crates/README.md` 只改
`dt-apple`、`dt-cli` 两行。

## 6. 两次活体负测

负测 1（源码 token）：`crates/dt-history/src/lib.rs` 尾临时加两行：

```text
#[cfg(target_os = "macos")]
fn a6_live_probe() {}
```

`cargo xtask check-apple-boundary` → 退出 1：

```text
1 violation(s):
  - crates/dt-history/src/lib.rs:51: forbidden Apple token `cfg(target_os`
```

撤除（`git checkout --`），该路径 `git status` 干净。

负测 2（目标表挪位）：`crates/dt-apple/Cargo.toml` 把 `objc2-metal`
从目标表挪到普通 `[dependencies]` → 退出 1：

```text
1 violation(s):
  - dt-apple: Apple binding `objc2-metal` must sit under the macOS target table (found: plain [dependencies])
```

挪位前后 `Cargo.lock` sha256 相同（`73545876…c18c9db`），确如任务书不断
言：挪位不改锁。撤除后检查回 `OK`，工作区只剩本波改动。

## 7. §11 验收（命令与输出）

- `cargo build -p dt-apple --locked`：绿，无警告。
  `cargo test -p dt-apple --locked`：4 单测
  （`empty_backend_reports_nothing` /
  `empty_backend_is_selected_somewhere` /
  `capability_table_has_every_field` / `capabilities_returns_same_table`）
  + 1 doctest，全过。
- 默认 `target/debug/dt-cli capabilities`：§2 真值。`--no-default-features`
  构建：同 16 键、`backend=empty`（§2 末）。
- `Scripts/rust-apple-boundary.sh`：退出 0，`ALL GREEN`；框架行 0、符号
  行 0、对照旧 pattern 数 0；`otool -L` 仅 `libSystem.B.dylib`；末尾
  `target/debug/dt-cli` 为默认 feature 构建。
- 活体负测：见 §6（两次均非零点名，撤除干净）。
- `cargo test -p xtask`：32 通过（本波 +9：规则 1×2、规则 2、规则 3、
  规则 4、元数据形态、名单语义、拼装自检、JSON 转义）。
- 裸 `rg` 门（任务书原命令）：无输出（退出 1）。
- `rg -n 'unsafe' crates/dt-apple/src`：6 命中全在 `macos.rs`（3 属性 +
  3 `unsafe` 块）。
- `cargo xtask layers` / `check-order-sync` / `check-no-iop-names`：全过
  （`no layering violations` / `97 modules` / `97 names, 4 roots clean`）。
- `Scripts/check-licenses.sh`：退出 0（见 §5）。
- `cargo test --workspace --locked`：132 通过、0 失败（116 + 16：
  dt-apple 净 +4 含 doctest、dt-cli +3、xtask +9）。
- `Scripts/rust-ci-lite.sh`：退出 0，`ALL GREEN`，日志含
  `no Apple-boundary violations`。
- `git diff --stat 04c84b8d HEAD -- 'crates/dt-iop-*/src/modules'
  crates/dt-registry/fixtures`：无输出（提交后复核，见 stdout）。
- `target/debug/dt-cli help`：`fetch`/`render`/`cmp`/`emit-xmp`/
  `selftest` 全在，另有 `capabilities`。
- `git show --name-only HEAD`：只含纪律允许路径（提交后见 stdout）。

通用纪律：`cargo fmt --all --check` 干净；
`cargo clippy --workspace --all-targets -- -D warnings` 绿；
构建前 `Scripts/machine-guard.sh` 通过（`GUARD PASS (heavy=0 free=72% …)`，
链接门内另过两次）；并行 `-j6`；未用 `caffeinate`。

## 8. 提交

hash 见本 lane 最终 stdout（报告文件无法自含其所在提交的哈希；stat 下为
提交前 `git diff --stat` 内容，提交后由 `git show --stat` 复核，见 stdout）。
Conventional Commits，`refs #32`，逐路径 `git add`，零 push。

## 9. 未做 / 未验

未做：无。本波 10 节全做完；CIRAW 解码、渲染、窗口本就不在本波（C 期 / 后续波）。

未验：非 macOS 真编译（本机无其它目标且按纪律不装）。替代证据：linux
目标 `cargo tree` 单行（解析层零依赖）+ 空后端全平台编译且在 macOS 被单
测实际执行过。真验命令：
`rustup target add x86_64-unknown-linux-gnu && cargo check -p dt-apple --target x86_64-unknown-linux-gnu --locked`。

## 10. 修订记录（自审回注）

自审（独立 `omp -p` 实例，`A6-review.log`）：`PASS / 0 error + 1 minor`。
回注 M1（措辞）：§1「零散 `cfg` 为零」改为「零散 `target_os` cfg 为零」并注明
`#[cfg(test)]` 例外。无代码改动；本节为唯一修订。
