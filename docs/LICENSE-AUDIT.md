# LICENSE-AUDIT — 许可证与依赖审计表

> **免责：这是工程核查，不是法律意见。** 结论来自对仓库文件与上游原文的逐项核对；真正的法律判断请咨询律师。

> 核查基线（2026-11-26，lane A1）：
> - 本仓库 HEAD = `a97cd47af6f550009d9bc29a7e61cbc2cbed9b74`（`git rev-parse HEAD` 亲核；计划落盘基线 `1f9c1adb` 已是三提交之前）。
> - 上游参考树 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master` HEAD = `679d594f5d`（= `release-5.7.0-2234`），A-1 之后参数/顺序/版本一律钉它。
> - rawspeed 钉 `0c16fee7772594e98897bded01fc31bc3409b4cb`（A-6；`git ls-tree HEAD src/external/rawspeed` 亲核与 A-6 一致）。
> - spike 工作区（只读）：`/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/Cargo.toml`（Apple 能力）与 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/viewport/Cargo.toml`（视口）；仓内锁表 `.work/gsd/phases/rust-core/SPIKE-RUST-APPLE-src/Cargo.lock` 与 `.work/gsd/phases/gpui-viewport/src/Cargo.lock` 经逐项比对与外部工作区**零差集**（§4.1）。
> - 本项目许可证：`GPL-3.0-or-later`，版权持有人 2026-11-26 确认（A-3）。

---

## §1 本项目许可政策

1. **项目许可证**：`GPL-3.0-or-later`。`LICENSE` = GPLv3 全文；每个源文件头 SPDX `GPL-3.0-or-later`；第三方署名集中在 `NOTICE`。
2. **允许清单**：`Scripts/licenses-allow.txt`（36 种 license 字符串，精确匹配 `cargo metadata` 的 `license` 字段）。新增依赖的 license 必须命中清单，否则不能进 `Cargo.lock`。
3. **例外**：以下情况可走例外清单 `Scripts/licenses-exceptions.txt`：① 双许可/多许可 crate，取其中与 GPL-3.0 兼容的分支（如 E1）；② 本项目自有包暂时缺 `license` 字段（W 类，字段补齐即退役）；③ 弱 copyleft（MPL-2.0 等）的新变体经核查确认兼容；④ C/C++ 库与数据包（不在 cargo 元数据里，按 §3/§6 登记，不进例外清单）。
   例外条目必须 pin「包名 + license 字符串」并写理由与退役条件；license 变更即失效重审。
4. **例外谁批**：用户（唯一版权人）。lane 在 issue #32 留记录；A 阶段连跑期间由 orchestrator 代记、用户事后过目。
5. **移植文件的义务**：每个从 darktable（或其它 GPL 上游）移植的源文件：保留原版权头逐字；追加一行 `Modified for Lightamer: <date> <what>`；SPDX 保持 `GPL-3.0-or-later`；有实质改写的在 `NOTICE` 登记出处与改动。
6. **机检**：`Scripts/check-licenses.sh [WORKSPACE]`，退出 0 方可合入；根工作区由 A2 建立，此前对 spike 工作区传路径检查。

---

## §2 darktable 源码（移植源）

| 项目 | 结论 |
|---|---|
| 版本 | `679d594f5d`（A-1 钉点）；`release-5.7.0` tag 仅作对照包（A5），license 同变体 |
| 许可证 | `GPL-3.0-or-later` |
| 证据 | `LICENSE` = GPLv3 全文（首行 `GNU GENERAL PUBLIC LICENSE / Version 3, 29 June 2007`）；`src/iop/exposure.c:1-17` 头部 `either version 3 of the License, or (at your option) any later version`；`release-5.7.0` 的同文件头逐字相同（`Copyright (C) 2009-2026 darktable developers`） |
| 链接方式 | 源码级移植（逐模块转写 Rust，不链接 dt 二进制） |
| 义务 | 保留原版权头 + 逐文件 `Modified for Lightamer` 标注 + `NOTICE` 登记 |
| 兼容性 | 与本项目同变体，无冲突 |

---

## §3 rawspeed（三问）

钉住提交 `0c16fee77`（`Merge pull request #995`）。本地仓库原在 `718eae2`（spike 实验用），本波经 `git fetch origin 0c16fee7772594e98897bded01fc31bc3409b4cb` 直连取到（HTTPS 200，无需代理），以下均引该提交原文。

### Q1：到底是 LGPL-2.1-only、LGPL-2.1-or-later，还是 LGPL-3.0？

**结论：LGPL-2.1 系、or-later（记 `LGPL-2.1-or-later`）。T1 与 CORE-DESIGN 里「LGPL-3.0」一说在此提交上被证伪。**

- `LICENSE`（502 行）= LGPL Version 2.1（1999）全文，无它版。
- `README.rst:35`：`open source under the LGPL v2 license`，链接指向 `choosealicense.com/licenses/lgpl-2.1`。
- 源码头全树统计（`git grep`）：244 个文件 `version 2 of the License, or (at your option) any later version`（= LGPL-2.0-or-later 表述，涵盖 2.1）；8 个文件（`decompressors/` 下 Fuji/PanasonicV6/V7/V8 各 .cpp/.h）`version 2.1 … or (at your option) any later version`；全树**零** `version 3` 的 LGPL 声明。
- 唯一例外 `src/utilities/identify/rawspeed-identify.cpp` 是 GPL-3.0-or-later 的 darktable 自有文件（随工具链，非解码库；我们不编译 `utilities/`，无影响）。
- **不一致如实记录**：`LICENSE` 文件是 2.1 文本，多数源码头写的是 `version 2`（2.0 时代表述）；两者都是 or-later，升级路径一致，不影响结论。另：上游 master 今日是否已换 LGPL-3.0 本波未核——以钉住提交为准，不追最新。

### Q2：GPL-3.0-or-later 项目怎样合规使用？

- **静态链接（我们的方式，同 darktable）**：or-later 允许把 rawspeed 按 GPL-3.0 分发（LGPL-2.1 §3 转 GPL 选项，或直接取 later 版本），整体按 GPL-3.0-or-later 分发即合规。义务 = GPL-3.0 本体的义务：保留版权与许可声明、提供对应源码（含 rawspeed 钉住提交的源码可得性，submodule pin 即满足）。LGPL-2.1 §6 的重链接条款在转 GPL 分发后不再单独适用。
- **动态链接（备用分支，未采用）**：同样可整体按 GPL-3.0 分发；若按 LGPL-2.1 本体合规，则用共享库机制满足 §6。仅记录，不实施。

### Q3：darktable 自己怎样链接，在文档里怎么说？

- **静态编入**：`src/external/CMakeLists.txt:60` `add_subdirectory(rawspeed …)`；rawspeed 自身 `CMakeLists.txt:203` `rawspeed_add_library(rawspeed STATIC)`；`src/CMakeLists.txt:1309-1311` 经 `lib_darktable_imageio_rawspeed` 静态链入 `lib_darktable`。另 `src/external/CMakeLists.txt:63-66` 把 `data/cameras.xml` + `showcameras.xsl` 拷进 `datadir/darktable/rawspeed/`（数据文件随包分发）。
- **书面说法**：darktable 无针对 rawspeed 的单独许可声明（`README.md` 无 license 节；`LICENSE` = GPLv3 全文；各源文件头 or-later）——即以**整体 GPL-3.0-or-later 分发**涵盖 rawspeed。这正是 or-later 升级路径的实证。

### 推荐

**静态链接 + 整体 GPL-3.0-or-later，与 darktable 同构。** 理由：① or-later 升级干净，无 GPL-2.0-only 式死结；② 与上游实践一致，对照与合规论证最简；③ 薄 C ABI（`rs_open/rs_decode/rs_free`）不改变链接性质。`NOTICE` 登记条目 + 随包保留 rawspeed `LICENSE` 文本 + pin 提交可得（见 §8）。

---

## §4 spike 锁表（双工作区并集 854 项）

### §4.1 方法与计数

- 命令（只读元数据，不构建）：
  - `cargo metadata --locked --offline --format-version 1 --manifest-path …/Lightamer-rust-spike/Cargo.toml` → 103 包
  - `cargo metadata --locked --offline --format-version 1 --manifest-path …/Lightamer-gpui-spike/viewport/Cargo.toml` → 814 包
- 仓内锁与外部工作区逐 `(name, version)` 比对：两边差集都为 0。并集 854，交集 63。
- 来源：914 个非自有条目全部 `registry+https://github.com/rust-lang/crates.io-index`（crates.io），3 个自有包无 source。
- 下表证据列 `A:<行>` = Apple 锁行号，`V:<行>` = 视口锁行号（`[[package]]` 节起始行）。
- 义务码：`P` 宽松许可（NOTICE 署名即可）；`P-isc` 同左（ISC）；`PD` 公有领域类（CC0/0BSD/Unlicense/MIT-0）；`M` MPL-2.0（见 §4.2）；`U` Unicode 数据许可（见 §4.2）；`E1` 自例外（self_cell，见 §4.2）；`W` 自有包例外（见 §4.2）。链接列：registry 包一律纯 Rust 静态编入最终二进制。

| 名称 | 版本 | 锁 | 许可证 | 证据 | 来源 | 链接 | 义务 |
|---|---|---|---|---|---|---|---|
| accesskit | 0.24.1 | V | MIT OR Apache-2.0 | V:5 | https://github.com/AccessKit/accesskit | 纯 Rust 静态链接 | P |
| accesskit_atspi_common | 0.19.1 | V | MIT OR Apache-2.0 | V:15 | https://github.com/AccessKit/accesskit | 纯 Rust 静态链接 | P |
| accesskit_consumer | 0.38.0 | V | MIT OR Apache-2.0 | V:29 | https://github.com/AccessKit/accesskit | 纯 Rust 静态链接 | P |
| accesskit_macos | 0.26.3 | V | MIT OR Apache-2.0 | V:39 | https://github.com/AccessKit/accesskit | 纯 Rust 静态链接 | P |
| accesskit_unix | 0.22.1 | V | MIT OR Apache-2.0 | V:53 | https://github.com/AccessKit/accesskit | 纯 Rust 静态链接 | P |
| accesskit_windows | 0.34.0 | V | MIT OR Apache-2.0 | V:71 | https://github.com/AccessKit/accesskit | 纯 Rust 静态链接 | P |
| addr2line | 0.27.1 | V | Apache-2.0 OR MIT | V:85 | https://github.com/gimli-rs/addr2line | 纯 Rust 静态链接 | P |
| adler2 | 2.0.1 | V | 0BSD OR MIT OR Apache-2.0 | V:94 | https://github.com/oyvindln/adler2 | 纯 Rust 静态链接 | PD |
| aes | 0.8.4 | V | MIT OR Apache-2.0 | V:100 | https://github.com/RustCrypto/block-ciphers | 纯 Rust 静态链接 | P |
| ahash | 0.8.13 | V | MIT OR Apache-2.0 | V:112 | https://github.com/tkaitchuck/ahash | 纯 Rust 静态链接 | P |
| ahash | 0.8.14 | L | MIT OR Apache-2.0 | L:112 | https://github.com/tkaitchuck/ahash | 纯 Rust 静态链接 | P |
| aho-corasick | 1.1.5 | V | Unlicense OR MIT | V:127 | https://github.com/BurntSushi/aho-corasick | 纯 Rust 静态链接 | PD |
| aligned | 0.4.3 | V | MIT OR Apache-2.0 | V:136 | https://github.com/rust-embedded-community/aligned | 纯 Rust 静态链接 | P |
| aligned-vec | 0.6.4 | V | MIT | V:145 | https://github.com/sarah-ek/aligned-vec/ | 纯 Rust 静态链接 | P |
| allocator-api2 | 0.2.21 | V | MIT OR Apache-2.0 | V:154 | https://github.com/zakarumych/allocator-api2 | 纯 Rust 静态链接 | P |
| android_system_properties | 0.1.6 | V | MIT OR Apache-2.0 | V:160 | https://github.com/nical/android_system_properties | 纯 Rust 静态链接 | P |
| annotate-snippets | 0.12.18 | V | MIT OR Apache-2.0 | V:169 | https://github.com/rust-lang/annotate-snippets-rs | 纯 Rust 静态链接 | P |
| anstyle | 1.0.14 | AV | MIT OR Apache-2.0 | A:5 V:180 | https://github.com/rust-cli/anstyle.git | 纯 Rust 静态链接 | P |
| anyhow | 1.0.105 | AV | MIT OR Apache-2.0 | A:11 V:186 | https://github.com/dtolnay/anyhow | 纯 Rust 静态链接 | P |
| arbitrary | 1.5.0 | V | MIT OR Apache-2.0 | V:192 | https://github.com/rust-fuzz/arbitrary/ | 纯 Rust 静态链接 | P |
| arc-swap | 1.9.5 | V | MIT OR Apache-2.0 | V:198 | https://github.com/vorner/arc-swap | 纯 Rust 静态链接 | P |
| arg_enum_proc_macro | 0.3.4 | V | MIT | V:207 | https://github.com/lu-zero/arg_enum_proc_macro | 纯 Rust 静态链接 | P |
| arraydeque | 0.5.1 | V | MIT/Apache-2.0 | V:218 | https://github.com/andylokandy/arraydeque | 纯 Rust 静态链接 | P |
| arrayref | 0.3.9 | V | BSD-2-Clause | V:224 | https://github.com/droundy/arrayref | 纯 Rust 静态链接 | P |
| arrayvec | 0.7.8 | V | MIT OR Apache-2.0 | V:230 | https://github.com/bluss/arrayvec | 纯 Rust 静态链接 | P |
| as-raw-xcb-connection | 1.0.1 | V | MIT OR Apache-2.0 | V:236 | https://github.com/psychon/as-raw-xcb-connection | 纯 Rust 静态链接 | P |
| as-slice | 0.2.1 | V | MIT OR Apache-2.0 | V:242 | https://github.com/japaric/as-slice | 纯 Rust 静态链接 | P |
| ash | 0.38.0+1.3.281 | V | MIT OR Apache-2.0 | V:251 | https://github.com/ash-rs/ash | 纯 Rust 静态链接 | P |
| ashpd | 0.13.13 | V | MIT | V:260 | https://github.com/bilelmoussaoui/ashpd | 纯 Rust 静态链接 | P |
| askama | 0.16.1 | A | MIT OR Apache-2.0 | A:17 | https://github.com/askama-rs/askama | 纯 Rust 静态链接 | P |
| askama_derive | 0.16.1 | A | MIT OR Apache-2.0 | A:30 | https://github.com/askama-rs/askama | 纯 Rust 静态链接 | P |
| askama_macros | 0.16.1 | A | MIT OR Apache-2.0 | A:48 | https://github.com/askama-rs/askama | 纯 Rust 静态链接 | P |
| askama_parser | 0.16.1 | A | MIT OR Apache-2.0 | A:57 | https://github.com/askama-rs/askama | 纯 Rust 静态链接 | P |
| async-broadcast | 0.7.2 | V | MIT OR Apache-2.0 | V:278 | https://github.com/smol-rs/async-broadcast | 纯 Rust 静态链接 | P |
| async-channel | 2.5.0 | V | Apache-2.0 OR MIT | V:290 | https://github.com/smol-rs/async-channel | 纯 Rust 静态链接 | P |
| async-executor | 1.14.1 | V | Apache-2.0 OR MIT | V:302 | https://github.com/smol-rs/async-executor | 纯 Rust 静态链接 | P |
| async-fs | 2.2.0 | V | Apache-2.0 OR MIT | V:316 | https://github.com/smol-rs/async-fs | 纯 Rust 静态链接 | P |
| async-io | 2.6.0 | V | Apache-2.0 OR MIT | V:327 | https://github.com/smol-rs/async-io | 纯 Rust 静态链接 | P |
| async-lock | 3.5.0 | V | Apache-2.0 OR MIT | V:345 | https://github.com/smol-rs/async-lock | 纯 Rust 静态链接 | P |
| async-net | 2.0.0 | V | Apache-2.0 OR MIT | V:356 | https://github.com/smol-rs/async-net | 纯 Rust 静态链接 | P |
| async-process | 2.5.0 | V | Apache-2.0 OR MIT | V:367 | https://github.com/smol-rs/async-process | 纯 Rust 静态链接 | P |
| async-recursion | 1.2.0 | V | MIT OR Apache-2.0 | V:385 | https://github.com/dcchut/async-recursion | 纯 Rust 静态链接 | P |
| async-signal | 0.2.14 | V | Apache-2.0 OR MIT | V:396 | https://github.com/smol-rs/async-signal | 纯 Rust 静态链接 | P |
| async-task | 4.7.1 | V | Apache-2.0 OR MIT | V:414 | https://github.com/smol-rs/async-task | 纯 Rust 静态链接 | P |
| async-trait | 0.1.92 | V | MIT OR Apache-2.0 | V:420 | https://github.com/dtolnay/async-trait | 纯 Rust 静态链接 | P |
| atomic-waker | 1.1.2 | V | Apache-2.0 OR MIT | V:431 | https://github.com/smol-rs/atomic-waker | 纯 Rust 静态链接 | P |
| atspi | 0.29.0 | V | Apache-2.0 OR MIT | V:437 | https://github.com/odilia-app/atspi | 纯 Rust 静态链接 | P |
| atspi-common | 0.13.0 | V | Apache-2.0 OR MIT | V:447 | https://github.com/odilia-app/atspi | 纯 Rust 静态链接 | P |
| atspi-proxies | 0.13.0 | V | Apache-2.0 OR MIT | V:463 | https://github.com/odilia-app/atspi | 纯 Rust 静态链接 | P |
| autocfg | 1.5.1 | AV | Apache-2.0 OR MIT | A:70 V:474 | https://github.com/cuviper/autocfg | 纯 Rust 静态链接 | P |
| av-scenechange | 0.14.1 | V | MIT | V:480 | https://github.com/rust-av/av-scenechange | 纯 Rust 静态链接 | P |
| av1-grain | 0.2.5 | V | BSD-2-Clause | V:500 | https://github.com/rust-av/av1-grain | 纯 Rust 静态链接 | P |
| avif-serialize | 0.8.9 | V | BSD-3-Clause | V:514 | https://github.com/kornelski/avif-serialize | 纯 Rust 静态链接 | P |
| backtrace | 0.3.77 | V | MIT OR Apache-2.0 | V:523 | https://github.com/rust-lang/backtrace-rs | 纯 Rust 静态链接 | P |
| base62 | 2.2.6 | V | MIT | V:538 | https://github.com/fbernier/base62 | 纯 Rust 静态链接 | P |
| base64 | 0.22.1 | V | MIT OR Apache-2.0 | V:544 | https://github.com/marshallpierce/rust-base64 | 纯 Rust 静态链接 | P |
| base64 | 0.23.1 | V | MIT OR Apache-2.0 | V:550 | https://github.com/marshallpierce/rust-base64 | 纯 Rust 静态链接 | P |
| basic-toml | 0.1.10 | A | MIT OR Apache-2.0 | A:76 | https://github.com/dtolnay/basic-toml | 纯 Rust 静态链接 | P |
| bit-set | 0.10.0 | V | Apache-2.0 OR MIT | V:556 | https://github.com/contain-rs/bit-set | 纯 Rust 静态链接 | P |
| bit-vec | 0.9.1 | V | Apache-2.0 OR MIT | V:565 | https://github.com/contain-rs/bit-vec | 纯 Rust 静态链接 | P |
| bit_field | 0.10.4 | V | MIT OR Apache-2.0 | V:571 | https://github.com/phil-opp/rust-bit-field | 纯 Rust 静态链接 | P |
| bitflags | 1.3.2 | V | MIT/Apache-2.0 | V:577 | https://github.com/bitflags/bitflags | 纯 Rust 静态链接 | P |
| bitflags | 2.13.2 | AV | MIT OR Apache-2.0 | A:85 V:583 | https://github.com/bitflags/bitflags | 纯 Rust 静态链接 | P |
| bitstream-io | 4.10.0 | V | MIT/Apache-2.0 | V:589 | https://github.com/tuffy/bitstream-io | 纯 Rust 静态链接 | P |
| block | 0.1.6 | V | MIT | V:598 | http://github.com/SSheldon/rust-block | 纯 Rust 静态链接 | P |
| block-buffer | 0.10.4 | V | MIT OR Apache-2.0 | V:604 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| block-buffer | 0.12.1 | V | MIT OR Apache-2.0 | V:613 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| block-padding | 0.3.3 | V | MIT OR Apache-2.0 | V:622 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| block2 | 0.5.1 | V | MIT | V:631 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| block2 | 0.6.2 | AV | MIT | A:91 V:640 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| blocking | 1.7.0 | V | Apache-2.0 OR MIT | V:649 | https://github.com/smol-rs/blocking | 纯 Rust 静态链接 | P |
| bstr | 1.14.0 | V | MIT OR Apache-2.0 | V:662 | https://github.com/BurntSushi/bstr | 纯 Rust 静态链接 | P |
| built | 0.8.1 | V | MIT | V:673 | https://github.com/lukaslueg/built | 纯 Rust 静态链接 | P |
| bumpalo | 3.20.4 | V | MIT OR Apache-2.0 | V:679 | https://github.com/fitzgen/bumpalo | 纯 Rust 静态链接 | P |
| bytemuck | 1.25.2 | V | Zlib OR Apache-2.0 OR MIT | V:685 | https://github.com/Lokathor/bytemuck | 纯 Rust 静态链接 | P |
| bytemuck_derive | 1.12.1 | V | Zlib OR Apache-2.0 OR MIT | V:694 | https://github.com/Lokathor/bytemuck | 纯 Rust 静态链接 | P |
| byteorder | 1.5.0 | V | Unlicense OR MIT | V:705 | https://github.com/BurntSushi/byteorder | 纯 Rust 静态链接 | PD |
| byteorder-lite | 0.1.0 | V | Unlicense OR MIT | V:711 | https://github.com/image-rs/byteorder-lite | 纯 Rust 静态链接 | PD |
| bytes | 1.12.2 | AV | MIT | A:100 V:717 | https://github.com/tokio-rs/bytes | 纯 Rust 静态链接 | P |
| calloop | 0.14.5 | V | MIT | V:723 | https://github.com/Smithay/calloop | 纯 Rust 静态链接 | P |
| calloop-wayland-source | 0.4.1 | V | MIT | V:735 | https://github.com/smithay/calloop-wayland-source | 纯 Rust 静态链接 | P |
| camino | 1.2.6 | A | MIT OR Apache-2.0 | A:106 | https://github.com/camino-rs/camino | 纯 Rust 静态链接 | P |
| cargo-platform | 0.3.3 | A | MIT OR Apache-2.0 | A:115 | https://github.com/rust-lang/cargo | 纯 Rust 静态链接 | P |
| cargo_metadata | 0.23.1 | A | MIT | A:125 | https://github.com/oli-obk/cargo_metadata | 纯 Rust 静态链接 | P |
| cbc | 0.1.2 | V | MIT OR Apache-2.0 | V:747 | https://github.com/RustCrypto/block-modes | 纯 Rust 静态链接 | P |
| cbindgen | 0.28.0 | V | MPL-2.0 | V:756 | https://github.com/mozilla/cbindgen | 纯 Rust 静态链接 | M |
| cc | 1.11.3 | AV | MIT OR Apache-2.0 | A:139 V:774 | https://github.com/rust-lang/cc-rs | 纯 Rust 静态链接 | P |
| cfg-if | 1.0.5 | AV | MIT OR Apache-2.0 | A:149 V:786 | https://github.com/rust-lang/cfg-if | 纯 Rust 静态链接 | P |
| cfg_aliases | 0.2.2 | V | MIT | V:792 | https://github.com/katharostech/cfg_aliases | 纯 Rust 静态链接 | P |
| chacha20 | 0.10.2 | V | MIT OR Apache-2.0 | V:798 | https://github.com/RustCrypto/stream-ciphers | 纯 Rust 静态链接 | P |
| chrono | 0.4.45 | V | MIT OR Apache-2.0 | V:809 | https://github.com/chronotope/chrono | 纯 Rust 静态链接 | P |
| cipher | 0.4.4 | V | MIT OR Apache-2.0 | V:823 | https://github.com/RustCrypto/traits | 纯 Rust 静态链接 | P |
| clap | 4.6.10 | A | MIT OR Apache-2.0 | A:155 | https://github.com/clap-rs/clap | 纯 Rust 静态链接 | P |
| clap_builder | 4.6.10 | A | MIT OR Apache-2.0 | A:165 | https://github.com/clap-rs/clap | 纯 Rust 静态链接 | P |
| clap_derive | 4.6.9 | A | MIT OR Apache-2.0 | A:176 | https://github.com/clap-rs/clap | 纯 Rust 静态链接 | P |
| clap_lex | 1.1.2 | A | MIT OR Apache-2.0 | A:188 | https://github.com/clap-rs/clap | 纯 Rust 静态链接 | P |
| cocoa | 0.25.0 | V | MIT OR Apache-2.0 | V:834 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| cocoa-foundation | 0.1.2 | V | MIT OR Apache-2.0 | V:850 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| codespan-reporting | 0.13.1 | V | Apache-2.0 | V:864 | https://github.com/brendanzab/codespan | 纯 Rust 静态链接 | P |
| color_quant | 1.1.0 | V | MIT | V:875 | https://github.com/image-rs/color_quant.git | 纯 Rust 静态链接 | P |
| concurrent-queue | 2.5.0 | V | Apache-2.0 OR MIT | V:881 | https://github.com/smol-rs/concurrent-queue | 纯 Rust 静态链接 | P |
| console_error_panic_hook | 0.1.7 | V | Apache-2.0/MIT | V:890 | https://github.com/rustwasm/console_error_panic_hook | 纯 Rust 静态链接 | P |
| const-oid | 0.10.3 | V | Apache-2.0 OR MIT | V:900 | https://github.com/RustCrypto/formats | 纯 Rust 静态链接 | P |
| const-random | 0.1.20 | V | MIT OR Apache-2.0 | V:906 | https://github.com/tkaitchuck/constrandom | 纯 Rust 静态链接 | P |
| const-random-macro | 0.1.18 | V | MIT OR Apache-2.0 | V:915 | https://github.com/tkaitchuck/constrandom | 纯 Rust 静态链接 | P |
| convert_case | 0.10.0 | V | MIT | V:925 | https://github.com/rutrum/convert-case | 纯 Rust 静态链接 | P |
| core-foundation | 0.10.1 | V | MIT OR Apache-2.0 | V:944 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-foundation | 0.9.4 | V | MIT OR Apache-2.0 | V:934 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-foundation-sys | 0.8.7 | V | MIT OR Apache-2.0 | V:954 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-graphics | 0.23.2 | V | MIT OR Apache-2.0 | V:960 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-graphics | 0.24.0 | V | MIT OR Apache-2.0 | V:973 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-graphics-helmer-fork | 0.24.0 | V | MIT OR Apache-2.0 | V:986 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-graphics-types | 0.1.3 | V | MIT OR Apache-2.0 | V:999 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-graphics-types | 0.2.0 | V | MIT OR Apache-2.0 | V:1010 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core-text | 21.0.0 | V | MIT OR Apache-2.0 | V:1021 | https://github.com/servo/core-foundation-rs | 纯 Rust 静态链接 | P |
| core_detect | 1.0.0 | V | MIT/Apache-2.0 | V:1033 | https://github.com/thomcc/core_detect | 纯 Rust 静态链接 | P |
| core_maths | 0.1.1 | V | MIT | V:1039 | https://github.com/robertbastian/core_maths | 纯 Rust 静态链接 | P |
| cosmic-text | 0.19.0 | V | MIT OR Apache-2.0 | V:1048 | https://github.com/pop-os/cosmic-text | 纯 Rust 静态链接 | P |
| cpufeatures | 0.2.17 | V | MIT OR Apache-2.0 | V:1072 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| cpufeatures | 0.3.1 | V | MIT OR Apache-2.0 | V:1081 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| crc32fast | 1.5.6 | V | MIT OR Apache-2.0 | V:1090 | https://github.com/srijs/rust-crc32fast | 纯 Rust 静态链接 | P |
| crossbeam-deque | 0.8.8 | V | MIT OR Apache-2.0 | V:1099 | https://github.com/crossbeam-rs/crossbeam | 纯 Rust 静态链接 | P |
| crossbeam-epoch | 0.9.21 | V | MIT OR Apache-2.0 | V:1109 | https://github.com/crossbeam-rs/crossbeam | 纯 Rust 静态链接 | P |
| crossbeam-utils | 0.8.23 | V | MIT OR Apache-2.0 | V:1118 | https://github.com/crossbeam-rs/crossbeam | 纯 Rust 静态链接 | P |
| crunchy | 0.2.4 | V | MIT | V:1124 | https://github.com/eira-fransham/crunchy | 纯 Rust 静态链接 | P |
| crypto-common | 0.1.7 | V | MIT OR Apache-2.0 | V:1130 | https://github.com/RustCrypto/traits | 纯 Rust 静态链接 | P |
| crypto-common | 0.2.2 | V | MIT OR Apache-2.0 | V:1140 | https://github.com/RustCrypto/traits | 纯 Rust 静态链接 | P |
| ctor | 1.0.14 | V | Apache-2.0 OR MIT | V:1149 | https://github.com/mmastrac/linktime | 纯 Rust 静态链接 | P |
| data-url | 0.3.2 | V | MIT OR Apache-2.0 | V:1159 | https://github.com/servo/rust-url | 纯 Rust 静态链接 | P |
| deranged | 0.5.9 | V | MIT OR Apache-2.0 | V:1165 | https://github.com/jhpratt/deranged | 纯 Rust 静态链接 | P |
| derive_more | 2.1.1 | V | MIT | V:1171 | https://github.com/JelteF/derive_more | 纯 Rust 静态链接 | P |
| derive_more-impl | 2.1.1 | V | MIT | V:1180 | https://github.com/JelteF/derive_more | 纯 Rust 静态链接 | P |
| digest | 0.10.7 | V | MIT OR Apache-2.0 | V:1193 | https://github.com/RustCrypto/traits | 纯 Rust 静态链接 | P |
| digest | 0.11.3 | V | MIT OR Apache-2.0 | V:1204 | https://github.com/RustCrypto/traits | 纯 Rust 静态链接 | P |
| dirs | 5.0.1 | V | MIT OR Apache-2.0 | V:1215 | https://github.com/soc/dirs-rs | 纯 Rust 静态链接 | P |
| dirs | 6.0.0 | V | MIT OR Apache-2.0 | V:1224 | https://github.com/soc/dirs-rs | 纯 Rust 静态链接 | P |
| dirs-sys | 0.4.1 | V | MIT OR Apache-2.0 | V:1233 | https://github.com/dirs-dev/dirs-sys-rs | 纯 Rust 静态链接 | P |
| dirs-sys | 0.5.0 | V | MIT OR Apache-2.0 | V:1245 | https://github.com/dirs-dev/dirs-sys-rs | 纯 Rust 静态链接 | P |
| dispatch | 0.2.0 | V | MIT | V:1257 | http://github.com/SSheldon/rust-dispatch | 纯 Rust 静态链接 | P |
| dispatch2 | 0.3.1 | AV | Zlib OR Apache-2.0 OR MIT | A:194 V:1263 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| displaydoc | 0.2.7 | V | MIT OR Apache-2.0 | V:1274 | https://github.com/yaahc/displaydoc | 纯 Rust 静态链接 | P |
| dlib | 0.5.3 | V | MIT | V:1285 | https://github.com/elinorbgr/dlib | 纯 Rust 静态链接 | P |
| document-features | 0.2.12 | V | MIT OR Apache-2.0 | V:1294 | https://github.com/slint-ui/document-features | 纯 Rust 静态链接 | P |
| downcast-rs | 1.2.1 | V | MIT/Apache-2.0 | V:1303 | https://github.com/marcianx/downcast-rs | 纯 Rust 静态链接 | P |
| dunce | 1.0.5 | V | CC0-1.0 OR MIT-0 OR Apache-2.0 | V:1309 | https://gitlab.com/kornelski/dunce | 纯 Rust 静态链接 | PD |
| dwrote | 0.11.5 | V | MPL-2.0 | V:1315 | https://github.com/servo/dwrote-rs | 纯 Rust 静态链接 | M |
| dyn-clone | 1.0.20 | V | MIT OR Apache-2.0 | V:1327 | https://github.com/dtolnay/dyn-clone | 纯 Rust 静态链接 | P |
| either | 1.19.0 | V | MIT OR Apache-2.0 | V:1333 | https://github.com/rayon-rs/either | 纯 Rust 静态链接 | P |
| embed-resource | 3.0.12 | V | MIT | V:1339 | https://github.com/nabijaczleweli/rust-embed-resource | 纯 Rust 静态链接 | P |
| encoding_rs | 0.8.44 | V | (Apache-2.0 OR MIT) AND BSD-3-Clause | V:1353 | https://github.com/hsivonen/encoding_rs | 纯 Rust 静态链接 | P |
| encoding_rs_io | 0.1.8 | V | MIT OR Apache-2.0 | V:1367 | https://github.com/BurntSushi/encoding_rs_io | 纯 Rust 静态链接 | P |
| endi | 1.1.1 | V | MIT | V:1376 | https://github.com/zeenix/endi | 纯 Rust 静态链接 | P |
| enum-iterator | 2.3.0 | V | 0BSD | V:1382 | https://github.com/stephaneyfx/enum-iterator.git | 纯 Rust 静态链接 | PD |
| enum-iterator-derive | 1.5.0 | V | 0BSD | V:1391 | https://github.com/stephaneyfx/enum-iterator.git | 纯 Rust 静态链接 | PD |
| enumflags2 | 0.7.12 | V | MIT OR Apache-2.0 | V:1402 | https://github.com/meithecatte/enumflags2 | 纯 Rust 静态链接 | P |
| enumflags2_derive | 0.7.12 | V | MIT OR Apache-2.0 | V:1412 | https://github.com/meithecatte/enumflags2 | 纯 Rust 静态链接 | P |
| enumn | 0.1.14 | V | MIT OR Apache-2.0 | V:1423 | https://github.com/dtolnay/enumn | 纯 Rust 静态链接 | P |
| equator | 0.4.2 | V | MIT | V:1434 | https://github.com/sarah-ek/equator/ | 纯 Rust 静态链接 | P |
| equator-macro | 0.4.2 | V | MIT | V:1443 | https://github.com/sarah-ek/equator/ | 纯 Rust 静态链接 | P |
| equivalent | 1.0.3 | AV | Apache-2.0 OR MIT | A:204 V:1454 | https://github.com/indexmap-rs/equivalent | 纯 Rust 静态链接 | P |
| errno | 0.3.15 | AV | MIT OR Apache-2.0 | A:210 V:1460 | https://github.com/lambda-fairy/rust-errno | 纯 Rust 静态链接 | P |
| etagere | 0.2.15 | V | MIT/Apache-2.0 | V:1470 | https://github.com/nical/etagere | 纯 Rust 静态链接 | P |
| euclid | 0.22.14 | V | MIT OR Apache-2.0 | V:1480 | https://github.com/servo/euclid | 纯 Rust 静态链接 | P |
| event-listener | 5.4.2 | V | Apache-2.0 OR MIT | V:1489 | https://github.com/smol-rs/event-listener | 纯 Rust 静态链接 | P |
| event-listener-strategy | 0.5.4 | V | Apache-2.0 OR MIT | V:1499 | https://github.com/smol-rs/event-listener-strategy | 纯 Rust 静态链接 | P |
| exr | 1.74.3 | V | BSD-3-Clause | V:1509 | https://github.com/johannesvollmer/exrs | 纯 Rust 静态链接 | P |
| fastrand | 2.5.0 | AV | Apache-2.0 OR MIT | A:220 V:1525 | https://github.com/smol-rs/fastrand | 纯 Rust 静态链接 | P |
| fax | 0.2.7 | V | MIT | V:1531 | https://github.com/pdf-rs/fax | 纯 Rust 静态链接 | P |
| fdeflate | 0.3.7 | V | MIT OR Apache-2.0 | V:1537 | https://github.com/image-rs/fdeflate | 纯 Rust 静态链接 | P |
| filedescriptor | 0.8.3 | V | MIT | V:1546 | https://github.com/wezterm/wezterm | 纯 Rust 静态链接 | P |
| find-msvc-tools | 0.1.15 | AV | MIT OR Apache-2.0 | A:226 V:1557 | https://github.com/rust-lang/cc-rs | 纯 Rust 静态链接 | P |
| flate2 | 1.1.11 | V | MIT OR Apache-2.0 | V:1563 | https://github.com/rust-lang/flate2-rs | 纯 Rust 静态链接 | P |
| float-cmp | 0.9.0 | V | MIT | V:1574 | https://github.com/mikedilger/float-cmp | 纯 Rust 静态链接 | P |
| float-ord | 0.3.2 | V | MIT / Apache-2.0 | V:1580 | https://github.com/notriddle/rust-float-ord | 纯 Rust 静态链接 | P |
| fluent-uri | 0.1.4 | V | MIT | V:1586 | https://github.com/yescallop/fluent-uri-rs | 纯 Rust 静态链接 | P |
| flume | 0.12.0 | V | Apache-2.0/MIT | V:1595 | https://github.com/zesterer/flume | 纯 Rust 静态链接 | P |
| fnv | 1.0.7 | V | Apache-2.0 / MIT | V:1606 | https://github.com/servo/rust-fnv | 纯 Rust 静态链接 | P |
| foldhash | 0.2.0 | V | Zlib | V:1612 | https://github.com/orlp/foldhash | 纯 Rust 静态链接 | P |
| font-types | 0.11.3 | V | MIT OR Apache-2.0 | V:1618 | https://github.com/googlefonts/fontations | 纯 Rust 静态链接 | P |
| font-types | 0.12.7 | V | MIT OR Apache-2.0 | V:1627 | https://github.com/googlefonts/fontations | 纯 Rust 静态链接 | P |
| fontconfig-parser | 0.5.8 | V | MIT | V:1636 | https://github.com/Riey/fontconfig-parser | 纯 Rust 静态链接 | P |
| fontdb | 0.23.0 | V | MIT | V:1645 | https://github.com/RazrFalcon/fontdb | 纯 Rust 静态链接 | P |
| foreign-types | 0.5.0 | V | MIT/Apache-2.0 | V:1659 | https://github.com/sfackler/foreign-types | 纯 Rust 静态链接 | P |
| foreign-types-macros | 0.2.4 | V | MIT/Apache-2.0 | V:1669 | https://github.com/sfackler/foreign-types | 纯 Rust 静态链接 | P |
| foreign-types-shared | 0.3.1 | V | MIT/Apache-2.0 | V:1680 | https://github.com/sfackler/foreign-types | 纯 Rust 静态链接 | P |
| form_urlencoded | 1.2.3 | V | MIT OR Apache-2.0 | V:1686 | https://github.com/servo/rust-url | 纯 Rust 静态链接 | P |
| freetype-sys | 0.20.1 | V | MIT | V:1695 | https://github.com/PistonDevelopers/freetype-sys.git | 纯 Rust 静态链接 | P |
| fs-err | 3.3.2 | A | MIT OR Apache-2.0 | A:232 | https://github.com/andrewhickman/fs-err | 纯 Rust 静态链接 | P |
| futf | 0.1.5 | V | MIT / Apache-2.0 | V:1706 | https://github.com/servo/futf | 纯 Rust 静态链接 | P |
| futures | 0.3.34 | V | MIT OR Apache-2.0 | V:1716 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-channel | 0.3.34 | V | MIT OR Apache-2.0 | V:1731 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-core | 0.3.34 | V | MIT OR Apache-2.0 | V:1741 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-executor | 0.3.34 | V | MIT OR Apache-2.0 | V:1747 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-io | 0.3.34 | V | MIT OR Apache-2.0 | V:1758 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-lite | 2.6.1 | V | Apache-2.0 OR MIT | V:1764 | https://github.com/smol-rs/futures-lite | 纯 Rust 静态链接 | P |
| futures-macro | 0.3.34 | V | MIT OR Apache-2.0 | V:1777 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-sink | 0.3.34 | V | MIT OR Apache-2.0 | V:1788 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-task | 0.3.34 | V | MIT OR Apache-2.0 | V:1794 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| futures-util | 0.3.34 | V | MIT OR Apache-2.0 | V:1800 | https://github.com/rust-lang/futures-rs | 纯 Rust 静态链接 | P |
| generic-array | 0.14.7 | V | MIT | V:1817 | https://github.com/fizyk20/generic-array.git | 纯 Rust 静态链接 | P |
| gethostname | 1.1.0 | V | Apache-2.0 | V:1827 | https://codeberg.org/swsnr/gethostname.rs.git | 纯 Rust 静态链接 | P |
| getrandom | 0.2.17 | V | MIT OR Apache-2.0 | V:1837 | https://github.com/rust-random/getrandom | 纯 Rust 静态链接 | P |
| getrandom | 0.3.4 | V | MIT OR Apache-2.0 | V:1850 | https://github.com/rust-random/getrandom | 纯 Rust 静态链接 | P |
| getrandom | 0.4.3 | AV | MIT OR Apache-2.0 | A:241 V:1864 | https://github.com/rust-random/getrandom | 纯 Rust 静态链接 | P |
| gif | 0.13.3 | V | MIT OR Apache-2.0 | V:1878 | https://github.com/image-rs/image-gif | 纯 Rust 静态链接 | P |
| gif | 0.14.2 | V | MIT OR Apache-2.0 | V:1888 | https://github.com/image-rs/image-gif | 纯 Rust 静态链接 | P |
| gimli | 0.34.0 | V | MIT OR Apache-2.0 | V:1898 | https://github.com/gimli-rs/gimli | 纯 Rust 静态链接 | P |
| gl_generator | 0.14.0 | V | Apache-2.0 | V:1904 | https://github.com/brendanzab/gl-rs/ | 纯 Rust 静态链接 | P |
| glob | 0.3.4 | AV | MIT OR Apache-2.0 | A:252 V:1915 | https://github.com/rust-lang/glob | 纯 Rust 静态链接 | P |
| globset | 0.4.22 | V | Unlicense OR MIT | V:1921 | https://github.com/BurntSushi/ripgrep/tree/master/crates/globset | 纯 Rust 静态链接 | PD |
| globwalk | 0.8.1 | V | MIT | V:1934 | https://github.com/gilnaa/globwalk | 纯 Rust 静态链接 | P |
| glow | 0.17.0 | V | MIT OR Apache-2.0 OR Zlib | V:1945 | https://github.com/grovesNL/glow | 纯 Rust 静态链接 | P |
| glutin_wgl_sys | 0.6.1 | V | Apache-2.0 | V:1957 | https://github.com/rust-windowing/glutin | 纯 Rust 静态链接 | P |
| goblin | 0.8.2 | A | MIT | A:258 | https://github.com/m4b/goblin | 纯 Rust 静态链接 | P |
| gpu-allocator | 0.28.0 | V | MIT OR Apache-2.0 | V:1966 | https://github.com/Traverse-Research/gpu-allocator | 纯 Rust 静态链接 | P |
| gpui-base | 0.11.0 | V | Apache-2.0 | V:1980 | https://github.com/longbridge/gpui-kit | 纯 Rust 静态链接 | P |
| gpui-component | 0.11.0 | V | Apache-2.0 | V:2024 | https://github.com/longbridge/gpui-kit | 纯 Rust 静态链接 | P |
| gpui-component-macros | 0.11.0 | V | Apache-2.0 | V:2072 | (none) | 纯 Rust 静态链接 | P |
| gpui-fast | 0.1.19 | V | Apache-2.0 | V:2084 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-apple | 0.1.19 | V | Apache-2.0 | V:2151 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-linux | 0.1.19 | V | Apache-2.0 | V:2191 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-macos | 0.1.19 | V | Apache-2.0 | V:2236 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-macros | 0.1.19 | V | Apache-2.0 | V:2278 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-platform | 0.1.19 | V | Apache-2.0 | V:2290 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-scheduler | 0.1.19 | V | Apache-2.0 | V:2306 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-web | 0.1.19 | V | Apache-2.0 | V:2322 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-wgpu | 0.1.19 | V | Apache-2.0 | V:2352 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-fast-windows | 0.1.19 | V | Apache-2.0 | V:2380 | https://github.com/longbridge/gpui-fast | 纯 Rust 静态链接 | P |
| gpui-kit | 0.11.0 | V | Apache-2.0 | V:2410 | https://github.com/longbridge/gpui-kit | 纯 Rust 静态链接 | P |
| gpui-kit-assets | 0.11.0 | V | Apache-2.0 | V:2428 | https://github.com/longbridge/gpui-kit | 纯 Rust 静态链接 | P |
| gpui-pre | 0.3.14 | V | Apache-2.0 | V:2444 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-apple | 0.3.14 | V | Apache-2.0 | V:2511 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-collections | 0.3.14 | V | Apache-2.0 | V:2551 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-derive-refineable | 0.3.14 | V | Apache-2.0 | V:2562 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-http-client | 0.3.14 | V | Apache-2.0 | V:2573 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-ios | 0.3.14 | V | Apache-2.0 | V:2591 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-linux | 0.3.14 | V | Apache-2.0 | V:2613 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-macos | 0.3.14 | V | Apache-2.0 | V:2658 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-macros | 0.3.14 | V | Apache-2.0 | V:2700 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-platform | 0.3.14 | V | Apache-2.0 | V:2713 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-refineable | 0.3.14 | V | Apache-2.0 | V:2729 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-reqwest | 0.12.15 | V | MIT OR Apache-2.0 | V:2738 | https://github.com/seanmonstar/reqwest | 纯 Rust 静态链接 | P |
| gpui-pre-scheduler | 0.3.14 | V | Apache-2.0 | V:2788 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-shared-string | 0.3.14 | V | Apache-2.0 | V:2805 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-sum-tree | 0.3.14 | V | Apache-2.0 | V:2816 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-util | 0.3.14 | V | Apache-2.0 | V:2828 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-web | 0.3.14 | V | Apache-2.0 | V:2839 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-wgpu | 0.3.14 | V | Apache-2.0 | V:2869 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-windows | 0.3.14 | V | Apache-2.0 | V:2897 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-ztracing | 0.3.14 | V | Apache-2.0 | V:2927 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-pre-ztracing-macro | 0.3.14 | V | Apache-2.0 | V:2937 | https://github.com/zed-industries/zed | 纯 Rust 静态链接 | P |
| gpui-viewport-spike | 0.1.0 | V | (empty) | V:2943 | (workspace) | 项目源码 | W |
| granit-parser | 1.3.0 | V | MIT OR Apache-2.0 | V:2959 | https://github.com/bourumir-wyngs/granit-parser | 纯 Rust 静态链接 | P |
| h2 | 0.4.21 | V | MIT | V:2969 | https://github.com/hyperium/h2 | 纯 Rust 静态链接 | P |
| half | 2.7.1 | V | MIT OR Apache-2.0 | V:2988 | https://github.com/VoidStarKat/half-rs | 纯 Rust 静态链接 | P |
| harfrust | 0.5.2 | V | MIT | V:3000 | https://github.com/harfbuzz/harfrust | 纯 Rust 静态链接 | P |
| hash32 | 0.3.1 | V | MIT OR Apache-2.0 | V:3013 | https://github.com/japaric/hash32 | 纯 Rust 静态链接 | P |
| hashbrown | 0.14.5 | V | MIT OR Apache-2.0 | V:3022 | https://github.com/rust-lang/hashbrown | 纯 Rust 静态链接 | P |
| hashbrown | 0.16.1 | V | MIT OR Apache-2.0 | V:3028 | https://github.com/rust-lang/hashbrown | 纯 Rust 静态链接 | P |
| hashbrown | 0.17.2 | AV | MIT OR Apache-2.0 | A:269 V:3039 | https://github.com/rust-lang/hashbrown | 纯 Rust 静态链接 | P |
| heapless | 0.9.4 | V | MIT OR Apache-2.0 | V:3048 | https://github.com/rust-embedded/heapless | 纯 Rust 静态链接 | P |
| heck | 0.4.1 | V | MIT OR Apache-2.0 | V:3058 | https://github.com/withoutboats/heck | 纯 Rust 静态链接 | P |
| heck | 0.5.0 | AV | MIT OR Apache-2.0 | A:275 V:3064 | https://github.com/withoutboats/heck | 纯 Rust 静态链接 | P |
| hermit-abi | 0.5.3 | V | MIT OR Apache-2.0 | V:3070 | https://github.com/hermit-os/hermit-rs | 纯 Rust 静态链接 | P |
| hex | 0.4.3 | V | MIT OR Apache-2.0 | V:3076 | https://github.com/KokaKiwi/rust-hex | 纯 Rust 静态链接 | P |
| hkdf | 0.12.4 | V | MIT OR Apache-2.0 | V:3082 | https://github.com/RustCrypto/KDFs/ | 纯 Rust 静态链接 | P |
| hmac | 0.12.1 | V | MIT OR Apache-2.0 | V:3091 | https://github.com/RustCrypto/MACs | 纯 Rust 静态链接 | P |
| html5ever | 0.27.0 | V | MIT OR Apache-2.0 | V:3100 | https://github.com/servo/html5ever | 纯 Rust 静态链接 | P |
| http | 1.5.0 | V | MIT OR Apache-2.0 | V:3114 | https://github.com/hyperium/http | 纯 Rust 静态链接 | P |
| http-body | 1.1.0 | V | MIT | V:3124 | https://github.com/hyperium/http-body | 纯 Rust 静态链接 | P |
| http-body-util | 0.1.5 | V | MIT | V:3134 | https://github.com/hyperium/http-body | 纯 Rust 静态链接 | P |
| httparse | 1.10.1 | V | MIT OR Apache-2.0 | V:3147 | https://github.com/seanmonstar/httparse | 纯 Rust 静态链接 | P |
| hybrid-array | 0.4.15 | V | MIT OR Apache-2.0 | V:3153 | https://github.com/RustCrypto/hybrid-array | 纯 Rust 静态链接 | P |
| hyper | 1.13.0 | V | MIT | V:3162 | https://github.com/hyperium/hyper | 纯 Rust 静态链接 | P |
| hyper-rustls | 0.27.10 | V | Apache-2.0 OR ISC OR MIT | V:3183 | https://github.com/rustls/hyper-rustls | 纯 Rust 静态链接 | P-isc |
| hyper-util | 0.1.21 | V | MIT | V:3199 | https://github.com/hyperium/hyper-util | 纯 Rust 静态链接 | P |
| iana-time-zone | 0.1.65 | V | MIT OR Apache-2.0 | V:3220 | https://github.com/strawlab/iana-time-zone | 纯 Rust 静态链接 | P |
| iana-time-zone-haiku | 0.1.2 | V | MIT OR Apache-2.0 | V:3235 | https://github.com/strawlab/iana-time-zone | 纯 Rust 静态链接 | P |
| icu_collections | 2.4.0 | V | Unicode-3.0 | V:3244 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_locale_core | 2.4.0 | V | Unicode-3.0 | V:3258 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_locale_fallback | 2.4.0 | V | Unicode-3.0 | V:3272 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_locale_fallback_data | 2.4.0 | V | Unicode-3.0 | V:3286 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_normalizer | 2.4.0 | V | Unicode-3.0 | V:3292 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_normalizer_data | 2.4.0 | V | Unicode-3.0 | V:3306 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_properties | 2.4.0 | V | Unicode-3.0 | V:3312 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_properties_data | 2.4.0 | V | Unicode-3.0 | V:3327 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_provider | 2.4.0 | V | Unicode-3.0 | V:3333 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_segmenter | 2.4.0 | V | Unicode-3.0 | V:3350 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| icu_segmenter_data | 2.4.0 | V | Unicode-3.0 | V:3367 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| idna | 1.1.0 | V | MIT OR Apache-2.0 | V:3373 | https://github.com/servo/rust-url/ | 纯 Rust 静态链接 | P |
| idna_adapter | 1.2.2 | V | Apache-2.0 OR MIT | V:3384 | https://github.com/hsivonen/idna_adapter | 纯 Rust 静态链接 | P |
| ignore | 0.4.35 | V | Unlicense OR MIT | V:3394 | https://github.com/BurntSushi/ripgrep/tree/master/crates/ignore | 纯 Rust 静态链接 | PD |
| image | 0.25.10 | V | MIT OR Apache-2.0 | V:3410 | https://github.com/image-rs/image | 纯 Rust 静态链接 | P |
| image-webp | 0.2.4 | V | MIT OR Apache-2.0 | V:3433 | https://github.com/image-rs/image-webp | 纯 Rust 静态链接 | P |
| imagesize | 0.13.0 | V | MIT | V:3443 | https://github.com/Roughsketch/imagesize | 纯 Rust 静态链接 | P |
| imagesize | 0.14.0 | V | MIT | V:3449 | https://github.com/Roughsketch/imagesize | 纯 Rust 静态链接 | P |
| imgref | 1.12.3 | V | CC0-1.0 OR Apache-2.0 | V:3455 | https://github.com/kornelski/imgref | 纯 Rust 静态链接 | PD |
| indexmap | 2.14.2 | AV | Apache-2.0 OR MIT | A:281 V:3461 | https://github.com/indexmap-rs/indexmap | 纯 Rust 静态链接 | P |
| inotify | 0.11.5 | V | ISC | V:3473 | https://github.com/hannobraun/inotify-rs | 纯 Rust 静态链接 | P-isc |
| inotify-sys | 0.1.8 | V | ISC | V:3484 | https://github.com/hannobraun/inotify-sys | 纯 Rust 静态链接 | P-isc |
| inout | 0.1.4 | V | MIT OR Apache-2.0 | V:3493 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| instant | 0.1.13 | V | BSD-3-Clause | V:3503 | https://github.com/sebcrozet/instant | 纯 Rust 静态链接 | P |
| interpolate_name | 0.2.4 | V | MIT | V:3515 | https://github.com/lu-zero/interpolate_name | 纯 Rust 静态链接 | P |
| inventory | 0.3.25 | V | MIT OR Apache-2.0 | V:3526 | https://github.com/dtolnay/inventory | 纯 Rust 静态链接 | P |
| ipnet | 2.12.2 | V | MIT OR Apache-2.0 | V:3535 | https://github.com/krisprice/ipnet | 纯 Rust 静态链接 | P |
| is-docker | 0.2.0 | V | MIT | V:3541 | https://github.com/TheLarkInn/is-docker | 纯 Rust 静态链接 | P |
| is-wsl | 0.4.0 | V | MIT | V:3550 | https://github.com/TheLarkInn/is-wsl | 纯 Rust 静态链接 | P |
| itertools | 0.11.0 | V | MIT OR Apache-2.0 | V:3560 | https://github.com/rust-itertools/itertools | 纯 Rust 静态链接 | P |
| itertools | 0.13.0 | V | MIT OR Apache-2.0 | V:3569 | https://github.com/rust-itertools/itertools | 纯 Rust 静态链接 | P |
| itertools | 0.14.0 | V | MIT OR Apache-2.0 | V:3578 | https://github.com/rust-itertools/itertools | 纯 Rust 静态链接 | P |
| itoa | 1.0.19 | AV | MIT OR Apache-2.0 | A:293 V:3587 | https://github.com/dtolnay/itoa | 纯 Rust 静态链接 | P |
| jiff | 1.0.3 | V | Unlicense OR MIT | V:3593 | https://github.com/BurntSushi/jiff | 纯 Rust 静态链接 | PD |
| jiff-core | 1.0.2 | V | Unlicense OR MIT | V:3611 | https://github.com/BurntSushi/jiff | 纯 Rust 静态链接 | PD |
| jiff-static | 1.0.3 | V | Unlicense OR MIT | V:3620 | https://github.com/BurntSushi/jiff | 纯 Rust 静态链接 | PD |
| jiff-tzdb | 1.0.0 | V | Unlicense OR MIT | V:3632 | https://github.com/BurntSushi/jiff | 纯 Rust 静态链接 | PD |
| jiff-tzdb-platform | 1.0.0 | V | Unlicense OR MIT | V:3638 | https://github.com/BurntSushi/jiff | 纯 Rust 静态链接 | PD |
| jni-sys | 0.3.1 | V | MIT OR Apache-2.0 | V:3647 | https://github.com/jni-rs/jni-sys | 纯 Rust 静态链接 | P |
| jni-sys | 0.4.1 | V | MIT OR Apache-2.0 | V:3656 | https://github.com/jni-rs/jni-sys | 纯 Rust 静态链接 | P |
| jni-sys-macros | 0.4.1 | V | MIT OR Apache-2.0 | V:3665 | https://github.com/jni-rs/jni-sys | 纯 Rust 静态链接 | P |
| jobserver | 0.1.35 | V | MIT OR Apache-2.0 | V:3675 | https://github.com/rust-lang/jobserver-rs | 纯 Rust 静态链接 | P |
| js-sys | 0.3.107 | V | MIT OR Apache-2.0 | V:3685 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/js-sys | 纯 Rust 静态链接 | P |
| khronos-egl | 6.0.0 | V | MIT/Apache-2.0 | V:3696 | https://github.com/timothee-haudebourg/khronos-egl | 纯 Rust 静态链接 | P |
| khronos_api | 3.1.0 | V | Apache-2.0 | V:3707 | https://github.com/brendanzab/gl-rs/ | 纯 Rust 静态链接 | P |
| kqueue | 1.2.1 | V | MIT | V:3713 | https://gitlab.com/rust-kqueue/rust-kqueue | 纯 Rust 静态链接 | P |
| kqueue-sys | 1.1.2 | V | MIT | V:3723 | https://gitlab.com/rust-kqueue/rust-kqueue-sys | 纯 Rust 静态链接 | P |
| kurbo | 0.11.3 | V | Apache-2.0 OR MIT | V:3733 | https://github.com/linebender/kurbo | 纯 Rust 静态链接 | P |
| kurbo | 0.13.1 | V | Apache-2.0 OR MIT | V:3744 | https://github.com/linebender/kurbo | 纯 Rust 静态链接 | P |
| lazy_static | 1.5.1 | V | MIT OR Apache-2.0 | V:3756 | https://github.com/rust-lang-nursery/lazy-static.rs | 纯 Rust 静态链接 | P |
| lebe | 0.5.3 | V | BSD-3-Clause | V:3762 | https://github.com/johannesvollmer/lebe | 纯 Rust 静态链接 | P |
| libc | 0.2.191 | AV | MIT OR Apache-2.0 | A:299 V:3768 | https://github.com/rust-lang/libc | 纯 Rust 静态链接 | P |
| libfuzzer-sys | 0.4.13 | V | (MIT OR Apache-2.0) AND NCSA | V:3774 | https://github.com/rust-fuzz/libfuzzer | 纯 Rust 静态链接 | P |
| libloading | 0.8.9 | V | ISC | V:3784 | https://github.com/nagisa/rust_libloading/ | 纯 Rust 静态链接 | P-isc |
| libm | 0.2.16 | V | MIT | V:3794 | https://github.com/rust-lang/compiler-builtins | 纯 Rust 静态链接 | P |
| libredox | 0.1.25 | V | MIT | V:3800 | https://gitlab.redox-os.org/redox-os/libredox.git | 纯 Rust 静态链接 | P |
| lightamer-bridge | 0.1.0 | A | (empty) | A:305 | (workspace) | 项目源码 | W |
| lightamer-rust-spike | 0.1.0 | A | (empty) | A:316 | (workspace) | 项目源码 | W |
| linebender_resource_handle | 0.1.1 | V | Apache-2.0 OR MIT | V:3809 | https://github.com/linebender/raw_resource_handle | 纯 Rust 静态链接 | P |
| link-section | 0.19.4 | V | Apache-2.0 OR MIT | V:3815 | https://github.com/mmastrac/linktime | 纯 Rust 静态链接 | P |
| linktime-proc-macro | 0.2.3 | V | Apache-2.0 OR MIT | V:3821 | https://github.com/mmastrac/linktime | 纯 Rust 静态链接 | P |
| linux-raw-sys | 0.12.1 | AV | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | A:333 V:3827 | https://github.com/sunfishcode/linux-raw-sys | 纯 Rust 静态链接 | P |
| litemap | 0.8.3 | V | Unicode-3.0 | V:3833 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| litrs | 1.1.0 | V | MIT OR Apache-2.0 | V:3839 | https://github.com/LukasKalbertodt/litrs | 纯 Rust 静态链接 | P |
| lock_api | 0.4.14 | V | MIT OR Apache-2.0 | V:3845 | https://github.com/Amanieu/parking_lot | 纯 Rust 静态链接 | P |
| log | 0.4.35 | AV | MIT OR Apache-2.0 | A:339 V:3854 | https://github.com/rust-lang/log | 纯 Rust 静态链接 | P |
| loop9 | 0.1.5 | V | MIT | V:3863 | https://gitlab.com/kornelski/loop9.git | 纯 Rust 静态链接 | P |
| lru-slab | 0.1.3 | V | MIT OR Apache-2.0 OR Zlib | V:3872 | https://github.com/Ralith/lru-slab | 纯 Rust 静态链接 | P |
| lsp-types | 0.97.0 | V | MIT | V:3878 | https://github.com/gluon-lang/lsp-types | 纯 Rust 静态链接 | P |
| lyon_geom | 1.0.20 | V | MIT OR Apache-2.0 | V:3891 | https://github.com/nical/lyon | 纯 Rust 静态链接 | P |
| lyon_path | 1.0.19 | V | MIT OR Apache-2.0 | V:3902 | https://github.com/nical/lyon | 纯 Rust 静态链接 | P |
| mac | 0.1.1 | V | MIT/Apache-2.0 | V:3912 | https://github.com/reem/rust-mac.git | 纯 Rust 静态链接 | P |
| mac-notification-sys | 0.6.15 | V | MIT/Apache-2.0 | V:3918 | https://github.com/h4llow3En/mac-notification-sys | 纯 Rust 静态链接 | P |
| mach2 | 0.6.0 | V | BSD-2-Clause OR MIT OR Apache-2.0 | V:3932 | https://github.com/JohnTitor/mach2 | 纯 Rust 静态链接 | P |
| malloc_buf | 0.0.6 | V | MIT | V:3938 | https://github.com/SSheldon/malloc_buf | 纯 Rust 静态链接 | P |
| markdown | 1.0.0 | V | MIT | V:3947 | https://github.com/wooorm/markdown-rs | 纯 Rust 静态链接 | P |
| markup5ever | 0.12.1 | V | MIT OR Apache-2.0 | V:3957 | https://github.com/servo/html5ever | 纯 Rust 静态链接 | P |
| markup5ever_rcdom | 0.3.0 | V | MIT OR Apache-2.0 | V:3971 | https://github.com/servo/html5ever | 纯 Rust 静态链接 | P |
| maybe-rayon | 0.1.1 | V | MIT | V:3983 | https://github.com/shssoichiro/maybe-rayon | 纯 Rust 静态链接 | P |
| md-5 | 0.10.6 | V | MIT OR Apache-2.0 | V:3993 | https://github.com/RustCrypto/hashes | 纯 Rust 静态链接 | P |
| memchr | 2.8.3 | AV | Unlicense OR MIT | A:345 V:4003 | https://github.com/BurntSushi/memchr | 纯 Rust 静态链接 | PD |
| memmap2 | 0.9.12 | V | MIT OR Apache-2.0 | V:4009 | https://github.com/RazrFalcon/memmap2-rs | 纯 Rust 静态链接 | P |
| memoffset | 0.9.1 | V | MIT | V:4018 | https://github.com/Gilnaa/memoffset | 纯 Rust 静态链接 | P |
| metal | 0.29.0 | V | MIT OR Apache-2.0 | V:4027 | https://github.com/gfx-rs/metal-rs | 纯 Rust 静态链接 | P |
| mime | 0.3.18 | V | MIT OR Apache-2.0 | V:4042 | https://github.com/hyperium/mime | 纯 Rust 静态链接 | P |
| mime_guess | 2.0.5 | V | MIT | V:4048 | https://github.com/abonander/mime_guess | 纯 Rust 静态链接 | P |
| minimal-lexical | 0.2.1 | A | MIT/Apache-2.0 | A:351 | https://github.com/Alexhuszagh/minimal-lexical | 纯 Rust 静态链接 | P |
| miniz_oxide | 0.8.9 | V | MIT OR Zlib OR Apache-2.0 | V:4058 | https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide | 纯 Rust 静态链接 | P |
| miniz_oxide | 0.9.1 | V | MIT OR Zlib OR Apache-2.0 | V:4068 | https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide | 纯 Rust 静态链接 | P |
| mio | 1.2.5 | V | MIT | V:4078 | https://github.com/tokio-rs/mio | 纯 Rust 静态链接 | P |
| moxcms | 0.8.1 | V | BSD-3-Clause OR Apache-2.0 | V:4090 | https://github.com/awxkee/moxcms.git | 纯 Rust 静态链接 | P |
| multiversion | 0.8.1 | V | MIT OR Apache-2.0 | V:4100 | https://github.com/calebzulawski/multiversion | 纯 Rust 静态链接 | P |
| multiversion-macros | 0.8.1 | V | MIT OR Apache-2.0 | V:4110 | https://github.com/calebzulawski/multiversion | 纯 Rust 静态链接 | P |
| multiversion_no_op | 1.0.0 | V | Apache-2.0 OR MIT | V:4122 | https://github.com/hsivonen/multiversion_no_op | 纯 Rust 静态链接 | P |
| naga | 30.0.2 | V | MIT OR Apache-2.0 | V:4128 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| naga-types | 30.0.2 | V | MIT OR Apache-2.0 | V:4154 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| ndk-sys | 0.6.0+11769913 | V | MIT OR Apache-2.0 | V:4166 | https://github.com/rust-mobile/ndk | 纯 Rust 静态链接 | P |
| new_debug_unreachable | 1.0.6 | V | MIT | V:4175 | https://github.com/mbrubeck/rust-debug-unreachable | 纯 Rust 静态链接 | P |
| no_std_io2 | 0.9.4 | V | Apache-2.0 OR MIT | V:4181 | https://github.com/wcampbell0x2a/no-std-io2 | 纯 Rust 静态链接 | P |
| nohash-hasher | 0.2.0 | V | Apache-2.0 OR MIT | V:4190 | https://github.com/paritytech/nohash-hasher | 纯 Rust 静态链接 | P |
| nom | 7.1.3 | A | MIT | A:357 | https://github.com/Geal/nom | 纯 Rust 静态链接 | P |
| nom | 8.0.0 | V | MIT | V:4196 | https://github.com/rust-bakery/nom | 纯 Rust 静态链接 | P |
| noop_proc_macro | 0.3.0 | V | MIT | V:4205 | https://github.com/lu-zero/noop_proc_macro | 纯 Rust 静态链接 | P |
| normpath | 1.5.2 | V | MIT OR Apache-2.0 | V:4211 | https://github.com/dylni/normpath | 纯 Rust 静态链接 | P |
| notify | 8.2.2 | V | CC0-1.0 | V:4220 | https://github.com/notify-rs/notify.git | 纯 Rust 静态链接 | PD |
| notify-rust | 4.19.0 | V | MIT OR Apache-2.0 | V:4239 | https://github.com/hoodie/notify-rust | 纯 Rust 静态链接 | P |
| notify-types | 2.3.1 | V | MIT OR Apache-2.0 | V:4253 | https://github.com/notify-rs/notify.git | 纯 Rust 静态链接 | P |
| ntapi | 0.4.3 | V | Apache-2.0 OR MIT | V:4262 | https://github.com/MSxDOS/ntapi | 纯 Rust 静态链接 | P |
| num | 0.4.3 | V | MIT OR Apache-2.0 | V:4271 | https://github.com/rust-num/num | 纯 Rust 静态链接 | P |
| num-bigint | 0.4.8 | V | MIT OR Apache-2.0 | V:4285 | https://github.com/rust-num/num-bigint | 纯 Rust 静态链接 | P |
| num-bigint-dig | 0.9.1 | V | MIT/Apache-2.0 | V:4295 | https://github.com/dignifiedquire/num-bigint | 纯 Rust 静态链接 | P |
| num-complex | 0.4.6 | V | MIT OR Apache-2.0 | V:4312 | https://github.com/rust-num/num-complex | 纯 Rust 静态链接 | P |
| num-conv | 0.2.2 | V | MIT OR Apache-2.0 | V:4321 | https://github.com/jhpratt/num-conv | 纯 Rust 静态链接 | P |
| num-derive | 0.4.2 | V | MIT OR Apache-2.0 | V:4327 | https://github.com/rust-num/num-derive | 纯 Rust 静态链接 | P |
| num-integer | 0.1.47 | V | MIT OR Apache-2.0 | V:4338 | https://github.com/rust-num/num-integer | 纯 Rust 静态链接 | P |
| num-iter | 0.1.46 | V | MIT OR Apache-2.0 | V:4347 | https://github.com/rust-num/num-iter | 纯 Rust 静态链接 | P |
| num-rational | 0.4.2 | V | MIT OR Apache-2.0 | V:4357 | https://github.com/rust-num/num-rational | 纯 Rust 静态链接 | P |
| num-traits | 0.2.19 | V | MIT OR Apache-2.0 | V:4368 | https://github.com/rust-num/num-traits | 纯 Rust 静态链接 | P |
| num_cpus | 1.17.0 | V | MIT OR Apache-2.0 | V:4378 | https://github.com/seanmonstar/num_cpus | 纯 Rust 静态链接 | P |
| objc | 0.2.7 | V | MIT | V:4388 | http://github.com/SSheldon/rust-objc | 纯 Rust 静态链接 | P |
| objc-foundation | 0.1.1 | V | MIT | V:4398 | http://github.com/SSheldon/rust-objc-foundation | 纯 Rust 静态链接 | P |
| objc-sys | 0.3.5 | V | MIT | V:4409 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2 | 0.5.3 | V | MIT | V:4415 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2 | 0.6.5 | AV | MIT | A:367 V:4425 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-app-kit | 0.2.2 | V | MIT | V:4434 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-app-kit | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4450 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-av-foundation | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:376 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-cloud-kit | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4472 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-audio | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:386 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-audio-types | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:398 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-data | 0.2.2 | V | MIT | V:4483 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-data | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4495 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-foundation | 0.3.2 | AV | Zlib OR Apache-2.0 OR MIT | A:408 V:4506 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-graphics | 0.3.2 | AV | Zlib OR Apache-2.0 OR MIT | A:421 V:4519 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-image | 0.2.2 | V | MIT | V:4535 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-image | 0.3.2 | AV | Zlib OR Apache-2.0 OR MIT | A:437 V:4547 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-media | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:453 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-ml | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:468 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-services | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4557 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-text | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4567 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-core-video | 0.3.2 | AV | Zlib OR Apache-2.0 OR MIT | A:478 V:4579 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-encode | 4.1.0 | AV | MIT | A:491 V:4593 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-foundation | 0.2.2 | V | MIT | V:4599 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-foundation | 0.3.2 | AV | MIT | A:497 V:4611 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-image-io | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:510 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-io-surface | 0.3.2 | AV | Zlib OR Apache-2.0 OR MIT | A:522 V:4624 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-metal | 0.2.2 | V | MIT | V:4635 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-metal | 0.3.2 | AV | Zlib OR Apache-2.0 OR MIT | A:533 V:4647 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-quartz-core | 0.2.2 | V | MIT | V:4660 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-quartz-core | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4673 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-security | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4690 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-ui-kit | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4699 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-uniform-type-identifiers | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4713 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-user-notifications | 0.3.2 | V | Zlib OR Apache-2.0 OR MIT | V:4723 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc2-vision | 0.3.2 | A | Zlib OR Apache-2.0 OR MIT | A:547 | https://github.com/madsmtm/objc2 | 纯 Rust 静态链接 | P |
| objc_exception | 0.1.2 | V | MIT | V:4735 | http://github.com/SSheldon/rust-objc-exception | 纯 Rust 静态链接 | P |
| objc_id | 0.1.1 | V | MIT | V:4744 | http://github.com/SSheldon/rust-objc-id | 纯 Rust 静态链接 | P |
| object | 0.40.0 | V | Apache-2.0 OR MIT | V:4753 | https://github.com/gimli-rs/object | 纯 Rust 静态链接 | P |
| once_cell | 1.21.4 | AV | MIT OR Apache-2.0 | A:566 V:4762 | https://github.com/matklad/once_cell | 纯 Rust 静态链接 | P |
| oo7 | 0.6.0 | V | MIT | V:4768 | https://github.com/linux-credentials/oo7 | 纯 Rust 静态链接 | P |
| open | 5.4.5 | V | MIT | V:4803 | https://github.com/Byron/open-rs | 纯 Rust 静态链接 | P |
| openssl-probe | 0.2.2 | V | MIT OR Apache-2.0 | V:4813 | https://github.com/rustls/openssl-probe | 纯 Rust 静态链接 | P |
| option-ext | 0.2.0 | V | MPL-2.0 | V:4819 | https://github.com/soc/option-ext.git | 纯 Rust 静态链接 | M |
| ordered-float | 5.5.1 | V | MIT | V:4825 | https://github.com/reem/rust-ordered-float | 纯 Rust 静态链接 | P |
| ordered-stream | 0.2.0 | V | MIT OR Apache-2.0 | V:4834 | https://github.com/danieldg/ordered-stream | 纯 Rust 静态链接 | P |
| parking | 2.2.1 | V | Apache-2.0 OR MIT | V:4844 | https://github.com/smol-rs/parking | 纯 Rust 静态链接 | P |
| parking_lot | 0.12.5 | V | MIT OR Apache-2.0 | V:4850 | https://github.com/Amanieu/parking_lot | 纯 Rust 静态链接 | P |
| parking_lot_core | 0.9.12 | V | MIT OR Apache-2.0 | V:4860 | https://github.com/Amanieu/parking_lot | 纯 Rust 静态链接 | P |
| paste | 1.0.15 | V | MIT OR Apache-2.0 | V:4873 | https://github.com/dtolnay/paste | 纯 Rust 静态链接 | P |
| pastey | 0.1.1 | V | MIT OR Apache-2.0 | V:4879 | https://github.com/as1100k/pastey | 纯 Rust 静态链接 | P |
| pathfinder_geometry | 0.5.1 | V | MIT/Apache-2.0 | V:4885 | https://github.com/servo/pathfinder | 纯 Rust 静态链接 | P |
| pathfinder_simd | 0.5.7 | V | MIT OR Apache-2.0 | V:4895 | https://github.com/servo/pathfinder | 纯 Rust 静态链接 | P |
| pbkdf2 | 0.12.2 | V | MIT OR Apache-2.0 | V:4904 | https://github.com/RustCrypto/password-hashes/tree/master/pbkdf2 | 纯 Rust 静态链接 | P |
| percent-encoding | 2.3.2 | AV | MIT OR Apache-2.0 | A:572 V:4914 | https://github.com/servo/rust-url/ | 纯 Rust 静态链接 | P |
| phf | 0.11.3 | V | MIT | V:4920 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf | 0.13.1 | V | MIT | V:4929 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf_codegen | 0.11.3 | V | MIT | V:4940 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf_generator | 0.11.3 | V | MIT | V:4950 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf_generator | 0.13.1 | V | MIT | V:4960 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf_macros | 0.13.1 | V | MIT | V:4970 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf_shared | 0.11.3 | V | MIT | V:4983 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| phf_shared | 0.13.1 | V | MIT | V:4992 | https://github.com/rust-phf/rust-phf | 纯 Rust 静态链接 | P |
| pico-args | 0.5.0 | V | MIT | V:5001 | https://github.com/RazrFalcon/pico-args | 纯 Rust 静态链接 | P |
| pin-project | 1.2.0 | V | Apache-2.0 OR MIT | V:5007 | https://github.com/taiki-e/pin-project | 纯 Rust 静态链接 | P |
| pin-project-internal | 1.2.0 | V | Apache-2.0 OR MIT | V:5016 | https://github.com/taiki-e/pin-project | 纯 Rust 静态链接 | P |
| pin-project-lite | 0.2.18 | V | Apache-2.0 OR MIT | V:5027 | https://github.com/taiki-e/pin-project-lite | 纯 Rust 静态链接 | P |
| piper | 0.2.5 | V | MIT OR Apache-2.0 | V:5033 | https://github.com/smol-rs/piper | 纯 Rust 静态链接 | P |
| pkg-config | 0.3.34 | V | MIT OR Apache-2.0 | V:5044 | https://github.com/rust-lang/pkg-config-rs | 纯 Rust 静态链接 | P |
| plain | 0.2.3 | A | MIT/Apache-2.0 | A:578 | https://github.com/randomites/plain | 纯 Rust 静态链接 | P |
| png | 0.17.16 | V | MIT OR Apache-2.0 | V:5050 | https://github.com/image-rs/image-png | 纯 Rust 静态链接 | P |
| png | 0.18.1 | V | MIT OR Apache-2.0 | V:5063 | https://github.com/image-rs/image-png | 纯 Rust 静态链接 | P |
| polling | 3.11.0 | V | Apache-2.0 OR MIT | V:5076 | https://github.com/smol-rs/polling | 纯 Rust 静态链接 | P |
| pollster | 0.4.0 | V | Apache-2.0/MIT | V:5090 | https://github.com/zesterer/pollster | 纯 Rust 静态链接 | P |
| polycool | 0.4.0 | V | MIT OR Apache-2.0 | V:5096 | https://github.com/linebender/kurbo | 纯 Rust 静态链接 | P |
| portable-atomic | 1.15.0 | V | Apache-2.0 OR MIT | V:5105 | https://github.com/taiki-e/portable-atomic | 纯 Rust 静态链接 | P |
| portable-atomic-util | 0.2.8 | V | Apache-2.0 OR MIT | V:5111 | https://github.com/taiki-e/portable-atomic-util | 纯 Rust 静态链接 | P |
| potential_utf | 0.1.6 | V | Unicode-3.0 | V:5120 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| powerfmt | 0.2.1 | V | MIT OR Apache-2.0 | V:5131 | https://github.com/jhpratt/powerfmt | 纯 Rust 静态链接 | P |
| ppv-lite86 | 0.2.21 | V | MIT OR Apache-2.0 | V:5137 | https://github.com/cryptocorrosion/cryptocorrosion | 纯 Rust 静态链接 | P |
| precomputed-hash | 0.1.1 | V | MIT | V:5146 | https://github.com/emilio/precomputed-hash | 纯 Rust 静态链接 | P |
| presser | 0.3.1 | V | MIT OR Apache-2.0 | V:5152 | https://github.com/EmbarkStudios/presser | 纯 Rust 静态链接 | P |
| proc-macro-crate | 3.5.0 | V | MIT OR Apache-2.0 | V:5158 | https://github.com/bkchr/proc-macro-crate | 纯 Rust 静态链接 | P |
| proc-macro2 | 1.0.107 | AV | MIT OR Apache-2.0 | A:584 V:5167 | https://github.com/dtolnay/proc-macro2 | 纯 Rust 静态链接 | P |
| profiling | 1.0.18 | V | MIT OR Apache-2.0 | V:5176 | https://github.com/aclysma/profiling | 纯 Rust 静态链接 | P |
| profiling-procmacros | 1.0.18 | V | MIT OR Apache-2.0 | V:5185 | https://github.com/aclysma/profiling | 纯 Rust 静态链接 | P |
| pxfm | 0.1.30 | V | BSD-3-Clause OR Apache-2.0 | V:5195 | https://github.com/awxkee/pxfm | 纯 Rust 静态链接 | P |
| qoi | 0.4.1 | V | MIT/Apache-2.0 | V:5201 | https://github.com/aldanor/qoi-rust | 纯 Rust 静态链接 | P |
| quick-error | 2.0.1 | V | MIT/Apache-2.0 | V:5210 | http://github.com/tailhook/quick-error | 纯 Rust 静态链接 | P |
| quick-xml | 0.41.0 | V | MIT | V:5216 | https://github.com/tafia/quick-xml | 纯 Rust 静态链接 | P |
| quinn | 0.11.12 | V | MIT OR Apache-2.0 | V:5225 | https://github.com/quinn-rs/quinn | 纯 Rust 静态链接 | P |
| quinn-proto | 0.11.19 | V | MIT OR Apache-2.0 | V:5245 | https://github.com/quinn-rs/quinn | 纯 Rust 静态链接 | P |
| quinn-udp | 0.5.16 | V | MIT OR Apache-2.0 | V:5267 | https://github.com/quinn-rs/quinn | 纯 Rust 静态链接 | P |
| quote | 1.0.47 | AV | MIT OR Apache-2.0 | A:593 V:5281 | https://github.com/dtolnay/quote | 纯 Rust 静态链接 | P |
| r-efi | 5.3.0 | V | MIT OR Apache-2.0 OR LGPL-2.1-or-later | V:5290 | https://github.com/r-efi/r-efi | 纯 Rust 静态链接 | P |
| r-efi | 6.0.0 | AV | MIT OR Apache-2.0 OR LGPL-2.1-or-later | A:602 V:5296 | https://github.com/r-efi/r-efi | 纯 Rust 静态链接 | P |
| rand | 0.10.4 | V | MIT OR Apache-2.0 | V:5323 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand | 0.8.8 | V | MIT OR Apache-2.0 | V:5302 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand | 0.9.5 | V | MIT OR Apache-2.0 | V:5313 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand_chacha | 0.3.1 | V | MIT OR Apache-2.0 | V:5334 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand_chacha | 0.9.0 | V | MIT OR Apache-2.0 | V:5344 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand_core | 0.10.1 | V | MIT OR Apache-2.0 | V:5372 | https://github.com/rust-random/rand_core | 纯 Rust 静态链接 | P |
| rand_core | 0.6.4 | V | MIT OR Apache-2.0 | V:5354 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand_core | 0.9.5 | V | MIT OR Apache-2.0 | V:5363 | https://github.com/rust-random/rand | 纯 Rust 静态链接 | P |
| rand_pcg | 0.10.3 | V | MIT OR Apache-2.0 | V:5378 | https://github.com/rust-random/rngs | 纯 Rust 静态链接 | P |
| range-alloc | 0.1.5 | V | MIT OR Apache-2.0 | V:5387 | https://github.com/gfx-rs/range-alloc | 纯 Rust 静态链接 | P |
| rangemap | 1.9.0 | V | MIT/Apache-2.0 | V:5393 | https://github.com/jeffparsons/rangemap | 纯 Rust 静态链接 | P |
| rav1e | 0.8.1 | V | BSD-2-Clause | V:5399 | https://github.com/xiph/rav1e/ | 纯 Rust 静态链接 | P |
| ravif | 0.13.0 | V | BSD-3-Clause | V:5434 | https://github.com/kornelski/cavif-rs | 纯 Rust 静态链接 | P |
| raw-window-handle | 0.6.2 | V | MIT OR Apache-2.0 OR Zlib | V:5449 | https://github.com/rust-windowing/raw-window-handle | 纯 Rust 静态链接 | P |
| raw-window-metal | 1.1.0 | V | MIT OR Apache-2.0 | V:5455 | https://github.com/rust-windowing/raw-window-metal | 纯 Rust 静态链接 | P |
| rayon | 1.12.0 | V | MIT OR Apache-2.0 | V:5467 | https://github.com/rayon-rs/rayon | 纯 Rust 静态链接 | P |
| rayon-core | 1.13.0 | V | MIT OR Apache-2.0 | V:5477 | https://github.com/rayon-rs/rayon | 纯 Rust 静态链接 | P |
| read-fonts | 0.37.0 | V | MIT OR Apache-2.0 | V:5487 | https://github.com/googlefonts/fontations | 纯 Rust 静态链接 | P |
| read-fonts | 0.41.0 | V | MIT OR Apache-2.0 | V:5498 | https://github.com/googlefonts/fontations | 纯 Rust 静态链接 | P |
| redox_syscall | 0.5.18 | V | MIT | V:5509 | https://gitlab.redox-os.org/redox-os/syscall | 纯 Rust 静态链接 | P |
| redox_users | 0.4.6 | V | MIT | V:5518 | https://gitlab.redox-os.org/redox-os/users | 纯 Rust 静态链接 | P |
| redox_users | 0.5.3 | V | MIT | V:5529 | https://gitlab.redox-os.org/redox-os/users | 纯 Rust 静态链接 | P |
| ref-cast | 1.0.27 | V | MIT OR Apache-2.0 | V:5539 | https://github.com/dtolnay/ref-cast | 纯 Rust 静态链接 | P |
| ref-cast-impl | 1.0.27 | V | MIT OR Apache-2.0 | V:5548 | https://github.com/dtolnay/ref-cast | 纯 Rust 静态链接 | P |
| regex | 1.13.2 | V | MIT OR Apache-2.0 | V:5559 | https://github.com/rust-lang/regex | 纯 Rust 静态链接 | P |
| regex-automata | 0.4.19 | V | MIT OR Apache-2.0 | V:5571 | https://github.com/rust-lang/regex | 纯 Rust 静态链接 | P |
| regex-syntax | 0.8.12 | V | MIT OR Apache-2.0 | V:5582 | https://github.com/rust-lang/regex | 纯 Rust 静态链接 | P |
| renderdoc-sys | 1.1.0 | V | MIT OR Apache-2.0 | V:5588 | https://github.com/ebkalderon/renderdoc-rs | 纯 Rust 静态链接 | P |
| resvg | 0.45.1 | V | Apache-2.0 OR MIT | V:5594 | https://github.com/linebender/resvg | 纯 Rust 静态链接 | P |
| resvg | 0.46.0 | V | Apache-2.0 OR MIT | V:5611 | https://github.com/linebender/resvg | 纯 Rust 静态链接 | P |
| rgb | 0.8.53 | V | MIT | V:5628 | https://github.com/kornelski/rust-rgb | 纯 Rust 静态链接 | P |
| ring | 0.17.14 | V | Apache-2.0 AND ISC | V:5637 | https://github.com/briansmith/ring | 纯 Rust 静态链接 | P-isc |
| ropey | 2.0.0-beta.1 | V | MIT OR Apache-2.0 | V:5651 | https://github.com/cessen/ropey | 纯 Rust 静态链接 | P |
| roxmltree | 0.20.0 | V | MIT OR Apache-2.0 | V:5660 | https://github.com/RazrFalcon/roxmltree | 纯 Rust 静态链接 | P |
| roxmltree | 0.21.2 | V | MIT OR Apache-2.0 | V:5666 | https://github.com/RazrFalcon/roxmltree | 纯 Rust 静态链接 | P |
| rust-embed | 8.14.0 | V | MIT | V:5675 | https://pyrossh.dev/repos/rust-embed | 纯 Rust 静态链接 | P |
| rust-embed-impl | 8.14.0 | V | MIT | V:5686 | https://pyrossh.dev/repos/rust-embed | 纯 Rust 静态链接 | P |
| rust-embed-utils | 8.14.0 | V | MIT | V:5701 | https://pyrossh.dev/repos/rust-embed | 纯 Rust 静态链接 | P |
| rust-i18n | 4.2.4 | V | MIT | V:5712 | https://github.com/longbridge/rust-i18n | 纯 Rust 静态链接 | P |
| rust-i18n-macro | 4.2.4 | V | MIT | V:5725 | https://github.com/longbridge/rust-i18n | 纯 Rust 静态链接 | P |
| rust-i18n-support | 4.2.4 | V | MIT | V:5740 | https://github.com/longbridge/rust-i18n | 纯 Rust 静态链接 | P |
| rustc-demangle | 0.1.28 | V | MIT/Apache-2.0 | V:5760 | https://github.com/rust-lang/rustc-demangle | 纯 Rust 静态链接 | P |
| rustc-hash | 1.1.0 | V | Apache-2.0/MIT | V:5766 | https://github.com/rust-lang-nursery/rustc-hash | 纯 Rust 静态链接 | P |
| rustc-hash | 2.1.3 | AV | Apache-2.0 OR MIT | A:608 V:5772 | https://github.com/rust-lang/rustc-hash | 纯 Rust 静态链接 | P |
| rustc_version | 0.4.1 | V | MIT OR Apache-2.0 | V:5778 | https://github.com/djc/rustc-version-rs | 纯 Rust 静态链接 | P |
| rustix | 1.1.6 | AV | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | A:614 V:5787 | https://github.com/bytecodealliance/rustix | 纯 Rust 静态链接 | P |
| rustls | 0.23.46 | V | Apache-2.0 OR ISC OR MIT | V:5800 | https://github.com/rustls/rustls | 纯 Rust 静态链接 | P-isc |
| rustls-native-certs | 0.8.5 | V | Apache-2.0 OR ISC OR MIT | V:5814 | https://github.com/rustls/rustls-native-certs | 纯 Rust 静态链接 | P-isc |
| rustls-pemfile | 2.2.0 | V | Apache-2.0 OR ISC OR MIT | V:5826 | https://github.com/rustls/pemfile | 纯 Rust 静态链接 | P-isc |
| rustls-pki-types | 1.16.0 | V | MIT OR Apache-2.0 | V:5835 | https://github.com/rustls/pki-types | 纯 Rust 静态链接 | P |
| rustls-webpki | 0.103.17 | V | ISC | V:5845 | https://github.com/rustls/webpki | 纯 Rust 静态链接 | P-isc |
| rustversion | 1.0.23 | V | MIT OR Apache-2.0 | V:5856 | https://github.com/dtolnay/rustversion | 纯 Rust 静态链接 | P |
| rustybuzz | 0.20.1 | V | MIT | V:5862 | https://github.com/harfbuzz/rustybuzz | 纯 Rust 静态链接 | P |
| ryu | 1.0.23 | V | Apache-2.0 OR BSL-1.0 | V:5880 | https://github.com/dtolnay/ryu | 纯 Rust 静态链接 | P |
| same-file | 1.0.6 | V | Unlicense/MIT | V:5886 | https://github.com/BurntSushi/same-file | 纯 Rust 静态链接 | PD |
| schannel | 0.1.30 | V | MIT | V:5895 | https://github.com/steffengy/schannel-rs | 纯 Rust 静态链接 | P |
| schemars | 1.2.3 | V | MIT | V:5904 | https://github.com/GREsau/schemars | 纯 Rust 静态链接 | P |
| schemars_derive | 1.2.3 | V | MIT | V:5918 | https://github.com/GREsau/schemars | 纯 Rust 静态链接 | P |
| scoped-tls | 1.0.1 | V | MIT/Apache-2.0 | V:5930 | https://github.com/alexcrichton/scoped-tls | 纯 Rust 静态链接 | P |
| scopeguard | 1.2.0 | V | MIT OR Apache-2.0 | V:5936 | https://github.com/bluss/scopeguard | 纯 Rust 静态链接 | P |
| screencapturekit | 0.2.8 | V | MIT OR Apache-2.0 | V:5942 | https://github.com/svtlabs/screencapturekit-rs/tree/main/screencapturekit | 纯 Rust 静态链接 | P |
| screencapturekit-sys | 0.2.8 | V | MIT OR Apache-2.0 | V:5951 | https://github.com/svtlabs/screencapturekit-rs/tree/main/screencapturekit-sys | 纯 Rust 静态链接 | P |
| scroll | 0.12.0 | A | MIT | A:627 | https://github.com/m4b/scroll | 纯 Rust 静态链接 | P |
| scroll_derive | 0.12.1 | A | MIT | A:636 | https://github.com/m4b/scroll | 纯 Rust 静态链接 | P |
| seahash | 4.1.0 | V | MIT | V:5965 | https://gitlab.redox-os.org/redox-os/seahash | 纯 Rust 静态链接 | P |
| security-framework | 3.7.0 | V | MIT OR Apache-2.0 | V:5971 | https://github.com/kornelski/rust-security-framework | 纯 Rust 静态链接 | P |
| security-framework-sys | 2.17.0 | V | MIT OR Apache-2.0 | V:5984 | https://github.com/kornelski/rust-security-framework | 纯 Rust 静态链接 | P |
| self_cell | 1.3.0 | V | Apache-2.0 OR GPL-2.0-only | V:5994 | https://github.com/Voultapher/self_cell | 纯 Rust 静态链接 | E1 |
| semver | 1.0.28 | AV | MIT OR Apache-2.0 | A:647 V:6000 | https://github.com/dtolnay/semver | 纯 Rust 静态链接 | P |
| serde | 1.0.229 | AV | MIT OR Apache-2.0 | A:657 V:6010 | https://github.com/serde-rs/serde | 纯 Rust 静态链接 | P |
| serde-saphyr | 1.3.0 | V | MIT OR Apache-2.0 | V:6020 | https://github.com/bourumir-wyngs/serde-saphyr | 纯 Rust 静态链接 | P |
| serde_bytes | 0.11.19 | V | MIT OR Apache-2.0 | V:6037 | https://github.com/serde-rs/bytes | 纯 Rust 静态链接 | P |
| serde_core | 1.0.229 | AV | MIT OR Apache-2.0 | A:667 V:6047 | https://github.com/serde-rs/serde | 纯 Rust 静态链接 | P |
| serde_derive | 1.0.229 | AV | MIT OR Apache-2.0 | A:676 V:6056 | https://github.com/serde-rs/serde | 纯 Rust 静态链接 | P |
| serde_derive_internals | 0.30.0 | V | MIT OR Apache-2.0 | V:6067 | https://github.com/serde-rs/serde | 纯 Rust 静态链接 | P |
| serde_json | 1.0.154 | AV | MIT OR Apache-2.0 | A:687 V:6078 | https://github.com/serde-rs/json | 纯 Rust 静态链接 | P |
| serde_repr | 0.1.21 | V | MIT OR Apache-2.0 | V:6093 | https://github.com/dtolnay/serde-repr | 纯 Rust 静态链接 | P |
| serde_spanned | 0.6.9 | V | MIT OR Apache-2.0 | V:6104 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| serde_spanned | 1.1.3 | AV | MIT OR Apache-2.0 | A:700 V:6113 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| serde_urlencoded | 0.7.1 | V | MIT/Apache-2.0 | V:6122 | https://github.com/nox/serde_urlencoded | 纯 Rust 静态链接 | P |
| sha1_smol | 1.0.1 | V | BSD-3-Clause | V:6134 | https://github.com/mitsuhiko/sha1-smol | 纯 Rust 静态链接 | P |
| sha2 | 0.10.9 | V | MIT OR Apache-2.0 | V:6140 | https://github.com/RustCrypto/hashes | 纯 Rust 静态链接 | P |
| sha2 | 0.11.1 | V | MIT OR Apache-2.0 | V:6151 | https://github.com/RustCrypto/hashes | 纯 Rust 静态链接 | P |
| sha2 | 0.11.2 | L | MIT OR Apache-2.0 | L:6382 | https://github.com/RustCrypto/hashes | 纯 Rust 静态链接 | P |
| shellexpand | 3.1.2 | V | MIT/Apache-2.0 | V:6162 | https://gitlab.com/ijackson/rust-shellexpand | 纯 Rust 静态链接 | P |
| shlex | 2.0.1 | AV | MIT OR Apache-2.0 | A:709 V:6171 | https://github.com/comex/rust-shlex | 纯 Rust 静态链接 | P |
| signal-hook-registry | 1.4.8 | V | MIT OR Apache-2.0 | V:6177 | https://github.com/vorner/signal-hook | 纯 Rust 静态链接 | P |
| simd-adler32 | 0.3.10 | V | MIT | V:6187 | https://github.com/mcountryman/simd-adler32 | 纯 Rust 静态链接 | P |
| simd_helpers | 0.1.1 | V | MIT | V:6193 | https://github.com/lu-zero/simd_helpers | 纯 Rust 静态链接 | P |
| simdutf8 | 0.1.5 | V | MIT OR Apache-2.0 | V:6199 | https://github.com/rusticstuff/simdutf8 | 纯 Rust 静态链接 | P |
| similar | 2.7.0 | V | Apache-2.0 | V:6205 | https://github.com/mitsuhiko/similar | 纯 Rust 静态链接 | P |
| simplecss | 0.2.2 | V | Apache-2.0 OR MIT | V:6215 | https://github.com/linebender/simplecss | 纯 Rust 静态链接 | P |
| siphasher | 1.0.4 | AV | MIT OR Apache-2.0 | A:715 V:6224 | https://github.com/jedisct1/rust-siphash | 纯 Rust 静态链接 | P |
| skrifa | 0.40.0 | V | MIT OR Apache-2.0 | V:6230 | https://github.com/googlefonts/fontations | 纯 Rust 静态链接 | P |
| skrifa | 0.44.0 | V | MIT OR Apache-2.0 | V:6240 | https://github.com/googlefonts/fontations | 纯 Rust 静态链接 | P |
| slab | 0.4.12 | V | MIT | V:6250 | https://github.com/tokio-rs/slab | 纯 Rust 静态链接 | P |
| slotmap | 1.1.1 | V | Zlib | V:6256 | https://github.com/orlp/slotmap | 纯 Rust 静态链接 | P |
| smallvec | 1.16.6 | V | MIT OR Apache-2.0 | V:6265 | https://github.com/smallvec/smallvec | 纯 Rust 静态链接 | P |
| smawk | 0.3.3 | A | MIT | A:721 | https://github.com/mgeisler/smawk | 纯 Rust 静态链接 | P |
| smol | 2.0.2 | V | Apache-2.0 OR MIT | V:6271 | https://github.com/smol-rs/smol | 纯 Rust 静态链接 | P |
| smol_str | 0.3.7 | V | MIT OR Apache-2.0 | V:6288 | https://github.com/rust-lang/rust-analyzer/tree/master/lib/smol_str | 纯 Rust 静态链接 | P |
| socket2 | 0.6.5 | V | MIT OR Apache-2.0 | V:6297 | https://github.com/rust-lang/socket2 | 纯 Rust 静态链接 | P |
| spin | 0.10.1 | V | MIT | V:6316 | https://github.com/mvdnes/spin-rs.git | 纯 Rust 静态链接 | P |
| spin | 0.9.9 | V | MIT | V:6307 | https://github.com/mvdnes/spin-rs.git | 纯 Rust 静态链接 | P |
| spirv | 0.4.0+sdk-1.4.341.0 | V | Apache-2.0 | V:6325 | https://github.com/gfx-rs/rspirv | 纯 Rust 静态链接 | P |
| stable_deref_trait | 1.2.1 | V | MIT OR Apache-2.0 | V:6334 | https://github.com/storyyeller/stable_deref_trait | 纯 Rust 静态链接 | P |
| static_assertions | 1.1.0 | AV | MIT OR Apache-2.0 | A:727 V:6340 | https://github.com/nvzqz/static-assertions-rs | 纯 Rust 静态链接 | P |
| str_indices | 0.4.4 | V | MIT OR Apache-2.0 | V:6346 | https://github.com/cessen/str_indices | 纯 Rust 静态链接 | P |
| strict-num | 0.1.1 | V | MIT | V:6352 | https://github.com/RazrFalcon/strict-num | 纯 Rust 静态链接 | P |
| string_cache | 0.8.9 | V | MIT OR Apache-2.0 | V:6361 | https://github.com/servo/string-cache | 纯 Rust 静态链接 | P |
| string_cache_codegen | 0.5.4 | V | MIT OR Apache-2.0 | V:6374 | https://github.com/servo/string-cache | 纯 Rust 静态链接 | P |
| strsim | 0.11.1 | A | MIT | A:733 | https://github.com/rapidfuzz/strsim-rs | 纯 Rust 静态链接 | P |
| strum | 0.28.0 | V | MIT | V:6386 | https://github.com/Peternator7/strum | 纯 Rust 静态链接 | P |
| strum_macros | 0.28.0 | V | MIT | V:6395 | https://github.com/Peternator7/strum | 纯 Rust 静态链接 | P |
| subtle | 2.6.1 | V | BSD-3-Clause | V:6407 | https://github.com/dalek-cryptography/subtle | 纯 Rust 静态链接 | P |
| svg_fmt | 0.4.5 | V | MIT/Apache-2.0 | V:6413 | https://github.com/nical/rust_debug | 纯 Rust 静态链接 | P |
| svgtypes | 0.15.3 | V | Apache-2.0 OR MIT | V:6419 | https://github.com/linebender/svgtypes | 纯 Rust 静态链接 | P |
| svgtypes | 0.16.2 | V | Apache-2.0 OR MIT | V:6429 | https://github.com/linebender/svgtypes | 纯 Rust 静态链接 | P |
| swash | 0.2.10 | V | Apache-2.0 OR MIT | V:6439 | https://github.com/dfrg/swash | 纯 Rust 静态链接 | P |
| syn | 2.0.119 | AV | MIT OR Apache-2.0 | A:739 V:6450 | https://github.com/dtolnay/syn | 纯 Rust 静态链接 | P |
| syn | 3.0.10 | AV | MIT OR Apache-2.0 | A:750 V:6461 | https://github.com/dtolnay/syn | 纯 Rust 静态链接 | P |
| sync_wrapper | 1.0.2 | V | Apache-2.0 | V:6472 | https://github.com/Actyx/sync_wrapper | 纯 Rust 静态链接 | P |
| synstructure | 0.14.0 | V | MIT | V:6481 | https://github.com/mystor/synstructure | 纯 Rust 静态链接 | P |
| sys-locale | 0.3.2 | V | MIT OR Apache-2.0 | V:6492 | https://github.com/1Password/sys-locale | 纯 Rust 静态链接 | P |
| sysinfo | 0.31.4 | V | MIT | V:6501 | https://github.com/GuillaumeGomez/sysinfo | 纯 Rust 静态链接 | P |
| system-configuration | 0.6.1 | V | MIT OR Apache-2.0 | V:6515 | https://github.com/mullvad/system-configuration-rs | 纯 Rust 静态链接 | P |
| system-configuration-sys | 0.6.0 | V | MIT OR Apache-2.0 | V:6526 | https://github.com/mullvad/system-configuration-rs | 纯 Rust 静态链接 | P |
| taffy | 0.15.1 | V | MIT | V:6536 | https://github.com/DioxusLabs/taffy | 纯 Rust 静态链接 | P |
| tao-core-video-sys | 0.2.0 | V | MIT | V:6547 | (none) | 纯 Rust 静态链接 | P |
| target-features | 0.1.6 | V | MIT OR Apache-2.0 | V:6559 | https://github.com/calebzulawski/target-features | 纯 Rust 静态链接 | P |
| tauri-winrt-notification | 0.8.1 | V | MIT OR Apache-2.0 | V:6565 | https://github.com/tauri-apps/winrt-notification | 纯 Rust 静态链接 | P |
| tempfile | 3.27.0 | AV | MIT OR Apache-2.0 | A:761 V:6576 | https://github.com/Stebalien/tempfile | 纯 Rust 静态链接 | P |
| tendril | 0.4.3 | V | MIT/Apache-2.0 | V:6589 | https://github.com/servo/tendril | 纯 Rust 静态链接 | P |
| termcolor | 1.4.1 | V | Unlicense OR MIT | V:6600 | https://github.com/BurntSushi/termcolor | 纯 Rust 静态链接 | PD |
| textwrap | 0.16.4 | A | MIT | A:774 | https://github.com/mgeisler/textwrap | 纯 Rust 静态链接 | P |
| thiserror | 1.0.69 | V | MIT OR Apache-2.0 | V:6609 | https://github.com/dtolnay/thiserror | 纯 Rust 静态链接 | P |
| thiserror | 2.0.21 | AV | MIT OR Apache-2.0 | A:784 V:6618 | https://github.com/dtolnay/thiserror | 纯 Rust 静态链接 | P |
| thiserror-impl | 1.0.69 | V | MIT OR Apache-2.0 | V:6627 | https://github.com/dtolnay/thiserror | 纯 Rust 静态链接 | P |
| thiserror-impl | 2.0.21 | AV | MIT OR Apache-2.0 | A:793 V:6638 | https://github.com/dtolnay/thiserror | 纯 Rust 静态链接 | P |
| tiff | 0.11.3 | V | MIT | V:6649 | https://github.com/image-rs/image-tiff | 纯 Rust 静态链接 | P |
| time | 0.3.55 | V | MIT OR Apache-2.0 | V:6663 | https://github.com/time-rs/time | 纯 Rust 静态链接 | P |
| time-core | 0.1.9 | V | MIT OR Apache-2.0 | V:6676 | https://github.com/time-rs/time | 纯 Rust 静态链接 | P |
| tiny-keccak | 2.0.2 | V | CC0-1.0 | V:6682 | (none) | 纯 Rust 静态链接 | PD |
| tiny-skia | 0.11.4 | V | BSD-3-Clause | V:6691 | https://github.com/RazrFalcon/tiny-skia | 纯 Rust 静态链接 | P |
| tiny-skia-path | 0.11.4 | V | BSD-3-Clause | V:6706 | https://github.com/RazrFalcon/tiny-skia/tree/master/path | 纯 Rust 静态链接 | P |
| tinystr | 0.8.5 | V | Unicode-3.0 | V:6717 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| tinyvec | 1.13.3 | V | Zlib OR Apache-2.0 OR MIT | V:6728 | https://github.com/Lokathor/tinyvec | 纯 Rust 静态链接 | P |
| tokio | 1.54.1 | V | MIT | V:6734 | https://github.com/tokio-rs/tokio | 纯 Rust 静态链接 | P |
| tokio-rustls | 0.26.6 | V | MIT OR Apache-2.0 | V:6748 | https://github.com/rustls/tokio-rustls | 纯 Rust 静态链接 | P |
| tokio-socks | 0.5.3 | V | MIT | V:6758 | https://github.com/sticnarf/tokio-socks | 纯 Rust 静态链接 | P |
| tokio-util | 0.7.20 | V | MIT | V:6770 | https://github.com/tokio-rs/tokio | 纯 Rust 静态链接 | P |
| toml | 0.8.23 | V | MIT OR Apache-2.0 | V:6784 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml | 1.2.3+spec-1.1.0 | AV | MIT OR Apache-2.0 | A:804 V:6796 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_datetime | 0.6.11 | V | MIT OR Apache-2.0 | V:6811 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_datetime | 1.1.3+spec-1.1.0 | AV | MIT OR Apache-2.0 | A:819 V:6820 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_edit | 0.22.27 | V | MIT OR Apache-2.0 | V:6829 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_edit | 0.25.21+spec-1.1.0 | V | MIT OR Apache-2.0 | V:6843 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_parser | 1.1.7+spec-1.1.0 | AV | MIT OR Apache-2.0 | A:828 V:6855 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_write | 0.1.2 | V | MIT OR Apache-2.0 | V:6864 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| toml_writer | 1.2.0+spec-1.1.0 | AV | MIT OR Apache-2.0 | A:837 V:6870 | https://github.com/toml-rs/toml | 纯 Rust 静态链接 | P |
| tower | 0.5.3 | V | MIT | V:6876 | https://github.com/tower-rs/tower | 纯 Rust 静态链接 | P |
| tower-layer | 0.3.3 | V | MIT | V:6891 | https://github.com/tower-rs/tower | 纯 Rust 静态链接 | P |
| tower-service | 0.3.3 | V | MIT | V:6897 | https://github.com/tower-rs/tower | 纯 Rust 静态链接 | P |
| tracing | 0.1.44 | V | MIT | V:6903 | https://github.com/tokio-rs/tracing | 纯 Rust 静态链接 | P |
| tracing-attributes | 0.1.31 | V | MIT | V:6915 | https://github.com/tokio-rs/tracing | 纯 Rust 静态链接 | P |
| tracing-core | 0.1.36 | V | MIT | V:6926 | https://github.com/tokio-rs/tracing | 纯 Rust 静态链接 | P |
| triomphe | 0.1.17 | V | MIT OR Apache-2.0 | V:6935 | https://github.com/Manishearth/triomphe | 纯 Rust 静态链接 | P |
| try-lock | 0.2.5 | V | MIT | V:6946 | https://github.com/seanmonstar/try-lock | 纯 Rust 静态链接 | P |
| ttf-parser | 0.25.1 | V | MIT OR Apache-2.0 | V:6952 | https://github.com/harfbuzz/ttf-parser | 纯 Rust 静态链接 | P |
| typenum | 1.20.1 | V | MIT OR Apache-2.0 | V:6961 | https://github.com/paholg/typenum | 纯 Rust 静态链接 | P |
| uds_windows | 1.2.1 | V | MIT | V:6967 | https://github.com/haraldh/rust_uds_windows | 纯 Rust 静态链接 | P |
| unicase | 2.10.0 | V | MIT OR Apache-2.0 | V:6978 | https://github.com/seanmonstar/unicase | 纯 Rust 静态链接 | P |
| unicode-bidi | 0.3.18 | V | MIT OR Apache-2.0 | V:6984 | https://github.com/servo/unicode-bidi | 纯 Rust 静态链接 | P |
| unicode-bidi-mirroring | 0.4.0 | V | MIT/Apache-2.0 | V:6990 | https://github.com/RazrFalcon/unicode-bidi-mirroring | 纯 Rust 静态链接 | P |
| unicode-ccc | 0.4.0 | V | MIT/Apache-2.0 | V:6996 | https://github.com/RazrFalcon/unicode-ccc | 纯 Rust 静态链接 | P |
| unicode-id | 0.3.7 | V | MIT OR Apache-2.0 | V:7002 | https://github.com/Boshen/unicode-id | 纯 Rust 静态链接 | P |
| unicode-ident | 1.0.27 | AV | (MIT OR Apache-2.0) AND Unicode-3.0 | A:843 V:7008 | https://github.com/dtolnay/unicode-ident | 纯 Rust 静态链接 | U |
| unicode-linebreak | 0.1.5 | V | Apache-2.0 | V:7014 | https://github.com/axelf4/unicode-linebreak | 纯 Rust 静态链接 | P |
| unicode-properties | 0.1.5 | V | (MIT OR Apache-2.0) AND Unicode-3.0 | V:7020 | https://github.com/unicode-rs/unicode-properties | 纯 Rust 静态链接 | U |
| unicode-script | 0.5.9 | V | MIT OR Apache-2.0 | V:7026 | https://github.com/unicode-rs/unicode-script | 纯 Rust 静态链接 | P |
| unicode-segmentation | 1.13.3 | V | MIT OR Apache-2.0 | V:7032 | https://github.com/unicode-rs/unicode-segmentation | 纯 Rust 静态链接 | P |
| unicode-vo | 0.1.0 | V | MIT/Apache-2.0 | V:7038 | https://github.com/RazrFalcon/unicode-vo | 纯 Rust 静态链接 | P |
| unicode-width | 0.2.3 | AV | MIT OR Apache-2.0 | A:849 V:7044 | https://github.com/unicode-rs/unicode-width | 纯 Rust 静态链接 | P |
| uniffi | 0.32.2 | A | MPL-2.0 | A:855 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_bindgen | 0.32.2 | A | MPL-2.0 | A:871 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_core | 0.32.2 | A | MPL-2.0 | A:897 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_internal_macros | 0.32.2 | A | MPL-2.0 | A:909 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_macros | 0.32.2 | A | MPL-2.0 | A:922 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_meta | 0.32.2 | A | MPL-2.0 | A:939 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_pipeline | 0.32.2 | A | MPL-2.0 | A:951 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| uniffi_udl | 0.32.2 | A | MPL-2.0 | A:964 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | M |
| untrusted | 0.9.0 | V | ISC | V:7050 | https://github.com/briansmith/untrusted | 纯 Rust 静态链接 | P-isc |
| url | 2.5.9 | V | MIT OR Apache-2.0 | V:7056 | https://github.com/servo/rust-url | 纯 Rust 静态链接 | P |
| usvg | 0.45.1 | V | Apache-2.0 OR MIT | V:7068 | https://github.com/linebender/resvg | 纯 Rust 静态链接 | P |
| usvg | 0.46.0 | V | Apache-2.0 OR MIT | V:7095 | https://github.com/linebender/resvg | 纯 Rust 静态链接 | P |
| utf-8 | 0.7.6 | V | MIT OR Apache-2.0 | V:7122 | https://github.com/SimonSapin/rust-utf8 | 纯 Rust 静态链接 | P |
| utf8_iter | 1.1.0 | V | Apache-2.0 OR MIT | V:7128 | https://github.com/hsivonen/utf8_iter | 纯 Rust 静态链接 | P |
| utf_types | 1.0.0 | V | Apache-2.0 OR MIT | V:7137 | https://github.com/hsivonen/utf_types | 纯 Rust 静态链接 | P |
| uuid | 1.29.3 | V | Apache-2.0 OR MIT | V:7143 | https://github.com/uuid-rs/uuid | 纯 Rust 静态链接 | P |
| v_frame | 0.3.9 | V | BSD-2-Clause | V:7156 | https://github.com/rust-av/v_frame | 纯 Rust 静态链接 | P |
| version_check | 0.9.5 | V | MIT/Apache-2.0 | V:7167 | https://github.com/SergioBenitez/version_check | 纯 Rust 静态链接 | P |
| vswhom | 0.1.0 | V | MIT | V:7173 | https://github.com/nabijaczleweli/vswhom.rs | 纯 Rust 静态链接 | P |
| vswhom-sys | 0.1.3 | V | MIT | V:7183 | https://github.com/nabijaczleweli/vswhom-sys.rs | 纯 Rust 静态链接 | P |
| waker-fn | 1.2.0 | V | Apache-2.0 OR MIT | V:7193 | https://github.com/smol-rs/waker-fn | 纯 Rust 静态链接 | P |
| walkdir | 2.5.1 | V | Unlicense/MIT | V:7199 | https://github.com/BurntSushi/walkdir | 纯 Rust 静态链接 | PD |
| want | 0.3.2 | V | MIT | V:7209 | https://github.com/seanmonstar/want | 纯 Rust 静态链接 | P |
| wasi | 0.11.1+wasi-snapshot-preview1 | V | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | V:7218 | https://github.com/bytecodealliance/wasi | 纯 Rust 静态链接 | P |
| wasip2 | 1.0.4+wasi-0.2.12 | V | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | V:7224 | https://github.com/bytecodealliance/wasi-rs | 纯 Rust 静态链接 | P |
| wasm-bindgen | 0.2.130 | V | MIT OR Apache-2.0 | V:7233 | https://github.com/wasm-bindgen/wasm-bindgen | 纯 Rust 静态链接 | P |
| wasm-bindgen-futures | 0.4.80 | V | MIT OR Apache-2.0 | V:7245 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/futures | 纯 Rust 静态链接 | P |
| wasm-bindgen-macro | 0.2.130 | V | MIT OR Apache-2.0 | V:7256 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/macro | 纯 Rust 静态链接 | P |
| wasm-bindgen-macro-support | 0.2.130 | V | MIT OR Apache-2.0 | V:7266 | https://github.com/wasm-bindgen/wasm-bindgen/tree/main/crates/macro-support | 纯 Rust 静态链接 | P |
| wasm-bindgen-shared | 0.2.130 | V | MIT OR Apache-2.0 | V:7279 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/shared | 纯 Rust 静态链接 | P |
| wasm-streams | 0.4.2 | V | MIT OR Apache-2.0 | V:7288 | https://github.com/MattiasBuelens/wasm-streams/ | 纯 Rust 静态链接 | P |
| wasm_thread | 0.3.3 | V | Apache-2.0 OR MIT | V:7301 | https://github.com/chemicstry/wasm_thread | 纯 Rust 静态链接 | P |
| wayland-backend | 0.3.17 | V | MIT | V:7313 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-client | 0.31.15 | V | MIT | V:7328 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-cursor | 0.31.14 | V | MIT | V:7340 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-protocols | 0.32.13 | V | MIT | V:7351 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-protocols-plasma | 0.3.12 | V | MIT | V:7363 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-protocols-wlr | 0.3.12 | V | MIT | V:7376 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-scanner | 0.31.11 | V | MIT | V:7389 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| wayland-sys | 0.31.11 | V | MIT | V:7400 | https://github.com/smithay/wayland-rs | 纯 Rust 静态链接 | P |
| web-sys | 0.3.107 | V | MIT OR Apache-2.0 | V:7412 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/web-sys | 纯 Rust 静态链接 | P |
| web-time | 1.1.0 | V | MIT OR Apache-2.0 | V:7422 | https://github.com/daxpedda/web-time | 纯 Rust 静态链接 | P |
| weedle2 | 5.0.0 | A | MIT | A:976 | https://github.com/mozilla/uniffi-rs | 纯 Rust 静态链接 | P |
| weezl | 0.1.12 | V | MIT OR Apache-2.0 | V:7432 | https://github.com/image-rs/weezl | 纯 Rust 静态链接 | P |
| wgpu | 30.0.1 | V | MIT OR Apache-2.0 | V:7438 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-core | 30.0.2 | V | MIT OR Apache-2.0 | V:7468 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-core-deps-apple | 30.0.2 | V | MIT OR Apache-2.0 | V:7503 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-core-deps-emscripten | 30.0.2 | V | MIT OR Apache-2.0 | V:7512 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-core-deps-wasm | 30.0.2 | V | MIT OR Apache-2.0 | V:7521 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-core-deps-windows-linux-android | 30.0.2 | V | MIT OR Apache-2.0 | V:7530 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-hal | 30.0.2 | V | MIT OR Apache-2.0 | V:7539 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-naga-bridge | 30.0.2 | V | MIT OR Apache-2.0 | V:7595 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| wgpu-types | 30.0.2 | V | MIT OR Apache-2.0 | V:7605 | https://github.com/gfx-rs/wgpu | 纯 Rust 静态链接 | P |
| which | 8.0.6 | V | MIT | V:7621 | https://github.com/harryfei/which-rs.git | 纯 Rust 静态链接 | P |
| winapi | 0.3.9 | V | MIT/Apache-2.0 | V:7630 | https://github.com/retep998/winapi-rs | 纯 Rust 静态链接 | P |
| winapi-i686-pc-windows-gnu | 0.4.0 | V | MIT/Apache-2.0 | V:7640 | https://github.com/retep998/winapi-rs | 纯 Rust 静态链接 | P |
| winapi-util | 0.1.11 | V | Unlicense OR MIT | V:7646 | https://github.com/BurntSushi/winapi-util | 纯 Rust 静态链接 | PD |
| winapi-x86_64-pc-windows-gnu | 0.4.0 | V | MIT/Apache-2.0 | V:7655 | https://github.com/retep998/winapi-rs | 纯 Rust 静态链接 | P |
| windows | 0.57.0 | V | MIT OR Apache-2.0 | V:7661 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows | 0.58.0 | V | MIT OR Apache-2.0 | V:7671 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows | 0.61.3 | V | MIT OR Apache-2.0 | V:7681 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows | 0.62.2 | V | MIT OR Apache-2.0 | V:7694 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-capture | 1.5.0 | V | MIT | V:7706 | https://github.com/NiiightmareXD/windows-capture | 纯 Rust 静态链接 | P |
| windows-collections | 0.2.0 | V | MIT OR Apache-2.0 | V:7719 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-collections | 0.3.2 | V | MIT OR Apache-2.0 | V:7728 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-core | 0.57.0 | V | MIT OR Apache-2.0 | V:7737 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-core | 0.58.0 | V | MIT OR Apache-2.0 | V:7749 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-core | 0.61.2 | V | MIT OR Apache-2.0 | V:7762 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-core | 0.62.2 | V | MIT OR Apache-2.0 | V:7775 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-future | 0.2.1 | V | MIT OR Apache-2.0 | V:7788 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-future | 0.3.2 | V | MIT OR Apache-2.0 | V:7799 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-implement | 0.57.0 | V | MIT OR Apache-2.0 | V:7810 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-implement | 0.58.0 | V | MIT OR Apache-2.0 | V:7821 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-implement | 0.60.2 | V | MIT OR Apache-2.0 | V:7832 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-interface | 0.57.0 | V | MIT OR Apache-2.0 | V:7843 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-interface | 0.58.0 | V | MIT OR Apache-2.0 | V:7854 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-interface | 0.59.3 | V | MIT OR Apache-2.0 | V:7865 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-link | 0.1.3 | V | MIT OR Apache-2.0 | V:7876 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-link | 0.2.1 | AV | MIT OR Apache-2.0 | A:985 V:7882 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-numerics | 0.2.0 | V | MIT OR Apache-2.0 | V:7888 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-numerics | 0.3.1 | V | MIT OR Apache-2.0 | V:7898 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-registry | 0.4.0 | V | MIT OR Apache-2.0 | V:7908 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-registry | 0.6.1 | V | MIT OR Apache-2.0 | V:7919 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-result | 0.1.2 | V | MIT OR Apache-2.0 | V:7930 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-result | 0.2.0 | V | MIT OR Apache-2.0 | V:7939 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-result | 0.3.4 | V | MIT OR Apache-2.0 | V:7948 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-result | 0.4.1 | V | MIT OR Apache-2.0 | V:7957 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-strings | 0.1.0 | V | MIT OR Apache-2.0 | V:7966 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-strings | 0.3.1 | V | MIT OR Apache-2.0 | V:7976 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-strings | 0.4.2 | V | MIT OR Apache-2.0 | V:7985 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-strings | 0.5.1 | V | MIT OR Apache-2.0 | V:7994 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-sys | 0.48.0 | V | MIT OR Apache-2.0 | V:8003 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-sys | 0.52.0 | V | MIT OR Apache-2.0 | V:8012 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-sys | 0.61.2 | AV | MIT OR Apache-2.0 | A:991 V:8021 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-targets | 0.48.5 | V | MIT OR Apache-2.0 | V:8030 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-targets | 0.52.6 | V | MIT OR Apache-2.0 | V:8045 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-targets | 0.53.5 | V | MIT OR Apache-2.0 | V:8061 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-threading | 0.1.0 | V | MIT OR Apache-2.0 | V:8078 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-threading | 0.2.1 | V | MIT OR Apache-2.0 | V:8087 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows-version | 0.1.7 | V | MIT OR Apache-2.0 | V:8096 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_aarch64_gnullvm | 0.48.5 | V | MIT OR Apache-2.0 | V:8105 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_aarch64_gnullvm | 0.52.6 | V | MIT OR Apache-2.0 | V:8111 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_aarch64_gnullvm | 0.53.1 | V | MIT OR Apache-2.0 | V:8117 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_aarch64_msvc | 0.48.5 | V | MIT OR Apache-2.0 | V:8123 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_aarch64_msvc | 0.52.6 | V | MIT OR Apache-2.0 | V:8129 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_aarch64_msvc | 0.53.1 | V | MIT OR Apache-2.0 | V:8135 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_gnu | 0.48.5 | V | MIT OR Apache-2.0 | V:8141 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_gnu | 0.52.6 | V | MIT OR Apache-2.0 | V:8147 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_gnu | 0.53.1 | V | MIT OR Apache-2.0 | V:8153 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_gnullvm | 0.52.6 | V | MIT OR Apache-2.0 | V:8159 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_gnullvm | 0.53.1 | V | MIT OR Apache-2.0 | V:8165 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_msvc | 0.48.5 | V | MIT OR Apache-2.0 | V:8171 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_msvc | 0.52.6 | V | MIT OR Apache-2.0 | V:8177 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_i686_msvc | 0.53.1 | V | MIT OR Apache-2.0 | V:8183 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_gnu | 0.48.5 | V | MIT OR Apache-2.0 | V:8189 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_gnu | 0.52.6 | V | MIT OR Apache-2.0 | V:8195 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_gnu | 0.53.1 | V | MIT OR Apache-2.0 | V:8201 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_gnullvm | 0.48.5 | V | MIT OR Apache-2.0 | V:8207 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_gnullvm | 0.52.6 | V | MIT OR Apache-2.0 | V:8213 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_gnullvm | 0.53.1 | V | MIT OR Apache-2.0 | V:8219 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_msvc | 0.48.5 | V | MIT OR Apache-2.0 | V:8225 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_msvc | 0.52.6 | V | MIT OR Apache-2.0 | V:8231 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| windows_x86_64_msvc | 0.53.1 | V | MIT OR Apache-2.0 | V:8237 | https://github.com/microsoft/windows-rs | 纯 Rust 静态链接 | P |
| winnow | 0.7.15 | V | MIT | V:8243 | https://github.com/winnow-rs/winnow | 纯 Rust 静态链接 | P |
| winnow | 1.0.5 | AV | MIT | A:1000 V:8252 | https://github.com/winnow-rs/winnow | 纯 Rust 静态链接 | P |
| winreg | 0.56.0 | V | MIT | V:8261 | https://github.com/gentoo90/winreg-rs | 纯 Rust 静态链接 | P |
| wio | 0.2.2 | V | MIT/Apache-2.0 | V:8271 | https://github.com/retep998/wio-rs | 纯 Rust 静态链接 | P |
| wit-bindgen | 0.57.1 | V | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | V:8280 | https://github.com/bytecodealliance/wit-bindgen | 纯 Rust 静态链接 | P |
| writeable | 0.6.4 | V | Unicode-3.0 | V:8286 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| x11 | 2.21.0 | V | MIT | V:8292 | https://github.com/AltF02/x11-rs.git | 纯 Rust 静态链接 | P |
| x11rb | 0.13.2 | V | MIT OR Apache-2.0 | V:8302 | https://github.com/psychon/x11rb | 纯 Rust 静态链接 | P |
| x11rb-protocol | 0.13.2 | V | MIT OR Apache-2.0 | V:8316 | https://github.com/psychon/x11rb | 纯 Rust 静态链接 | P |
| xcb | 1.7.1 | V | MIT | V:8322 | https://github.com/rust-x-bindings/rust-xcb | 纯 Rust 静态链接 | P |
| xcursor | 0.3.11 | V | MIT | V:8334 | https://github.com/esposm03/xcursor-rs | 纯 Rust 静态链接 | P |
| xim-ctext | 0.3.0 | V | MIT | V:8340 | https://github.com/Riey/xim-rs | 纯 Rust 静态链接 | P |
| xim-parser | 0.2.2 | V | MIT | V:8349 | https://github.com/Riey/xim-rs | 纯 Rust 静态链接 | P |
| xkbcommon | 0.8.0 | V | MIT | V:8358 | https://github.com/rust-x-bindings/xkbcommon-rs | 纯 Rust 静态链接 | P |
| xkeysym | 0.2.1 | V | MIT OR Apache-2.0 OR Zlib | V:8370 | https://github.com/notgull/xkeysym | 纯 Rust 静态链接 | P |
| xml-rs | 0.8.29 | V | MIT | V:8376 | https://github.com/kornelski/xml-rs | 纯 Rust 静态链接 | P |
| xml5ever | 0.18.1 | V | MIT OR Apache-2.0 | V:8382 | https://github.com/servo/html5ever | 纯 Rust 静态链接 | P |
| xmlwriter | 0.1.0 | V | MIT | V:8393 | https://github.com/RazrFalcon/xmlwriter | 纯 Rust 静态链接 | P |
| y4m | 0.8.0 | V | MIT | V:8399 | https://github.com/image-rs/y4m.git | 纯 Rust 静态链接 | P |
| yazi | 0.2.2 | V | Apache-2.0 OR MIT | V:8405 | https://github.com/dfrg/yazi | 纯 Rust 静态链接 | P |
| yeslogic-fontconfig-sys | 6.0.1 | V | MIT | V:8411 | https://github.com/yeslogic/fontconfig-rs | 纯 Rust 静态链接 | P |
| yoke | 0.8.4 | V | Unicode-3.0 | V:8422 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| yoke-derive | 0.8.4 | V | Unicode-3.0 | V:8433 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| zbus | 5.19.0 | V | MIT | V:8445 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zbus | 6.5.0 | V | MIT | V:8480 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zbus-lockstep | 0.5.2 | V | MIT | V:8507 | https://github.com/luukvanderduim/zbus-lockstep | 纯 Rust 静态链接 | P |
| zbus-lockstep-macros | 0.5.2 | V | MIT | V:8517 | https://github.com/luukvanderduim/zbus-lockstep | 纯 Rust 静态链接 | P |
| zbus_macros | 5.19.0 | V | MIT | V:8531 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zbus_macros | 6.5.0 | V | MIT | V:8546 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zbus_names | 4.3.5 | V | MIT | V:8558 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zbus_utils | 6.1.0 | V | MIT | V:8569 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zbus_xml | 5.2.1 | V | MIT | V:8582 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zcheapstr | 1.4.0 | V | MIT | V:8594 | https://github.com/z-galaxy/zcheapstr/ | 纯 Rust 静态链接 | P |
| zed-font-kit | 0.14.1-zed | V | MIT OR Apache-2.0 | V:8603 | https://github.com/servo/font-kit | 纯 Rust 静态链接 | P |
| zed-scap | 0.0.8-zed | V | MIT | V:8628 | https://github.com/helmerapp/scap | 纯 Rust 静态链接 | P |
| zed-xim | 0.4.0-zed | V | MIT | V:8650 | https://github.com/Riey/xim-rs | 纯 Rust 静态链接 | P |
| zeno | 0.3.3 | V | Apache-2.0 OR MIT | V:8664 | https://github.com/dfrg/zeno | 纯 Rust 静态链接 | P |
| zerocopy | 0.8.65 | V | BSD-2-Clause OR Apache-2.0 OR MIT | V:8670 | https://github.com/google/zerocopy | 纯 Rust 静态链接 | P |
| zerocopy | 0.8.66 | L | BSD-2-Clause OR Apache-2.0 OR MIT | L:8905 | https://github.com/google/zerocopy | 纯 Rust 静态链接 | P |
| zerocopy-derive | 0.8.65 | V | BSD-2-Clause OR Apache-2.0 OR MIT | V:8679 | https://github.com/google/zerocopy | 纯 Rust 静态链接 | P |
| zerocopy-derive | 0.8.66 | L | BSD-2-Clause OR Apache-2.0 OR MIT | L:8914 | https://github.com/google/zerocopy | 纯 Rust 静态链接 | P |
| zerofrom | 0.1.8 | V | Unicode-3.0 | V:8690 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| zerofrom-derive | 0.1.8 | V | Unicode-3.0 | V:8699 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| zeroize | 1.9.2 | V | Apache-2.0 OR MIT | V:8711 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| zeroize_derive | 1.5.0 | V | Apache-2.0 OR MIT | V:8720 | https://github.com/RustCrypto/utils | 纯 Rust 静态链接 | P |
| zerotrie | 0.2.5 | V | Unicode-3.0 | V:8731 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| zerovec | 0.11.9 | V | Unicode-3.0 | V:8743 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| zerovec-derive | 0.11.7 | V | Unicode-3.0 | V:8755 | https://github.com/unicode-org/icu4x | 纯 Rust 静态链接 | U |
| zlib-rs | 0.6.9 | V | Zlib | V:8766 | https://github.com/trifectatechfoundation/zlib-rs | 纯 Rust 静态链接 | P |
| zmij | 1.0.23 | AV | MIT | A:1009 V:8772 | https://github.com/dtolnay/zmij | 纯 Rust 静态链接 | P |
| zruntime | 0.2.4 | V | MIT | V:8778 | https://github.com/z-galaxy/zruntime | 纯 Rust 静态链接 | P |
| zune-core | 0.4.12 | V | MIT OR Apache-2.0 OR Zlib | V:8791 | (none) | 纯 Rust 静态链接 | P |
| zune-core | 0.5.3 | V | MIT OR Apache-2.0 OR Zlib | V:8797 | https://github.com/etemesi254/zune-image | 纯 Rust 静态链接 | P |
| zune-inflate | 0.2.54 | V | MIT OR Apache-2.0 OR Zlib | V:8803 | (none) | 纯 Rust 静态链接 | P |
| zune-jpeg | 0.4.21 | V | MIT OR Apache-2.0 OR Zlib | V:8812 | https://github.com/etemesi254/zune-image/tree/dev/crates/zune-jpeg | 纯 Rust 静态链接 | P |
| zune-jpeg | 0.5.15 | V | MIT OR Apache-2.0 OR Zlib | V:8821 | https://github.com/etemesi254/zune-image/tree/dev/crates/zune-jpeg | 纯 Rust 静态链接 | P |
| zvariant | 5.15.1 | V | MIT | V:8830 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zvariant_derive | 5.15.1 | V | MIT | V:8846 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |
| zvariant_utils | 4.2.0 | V | MIT | V:8859 | https://github.com/z-galaxy/zbus/ | 纯 Rust 静态链接 | P |

### §4.2 特殊许可证点评

- **MPL-2.0（11 包）**：`uniffi*` 8 包（apple 锁，`uniffi 0.32.2` 全家）+ `cbindgen 0.28.0`、`dwrote 0.11.5`、`option-ext 0.2.0`（gpui 锁；cbindgen 系构建依赖，dwrote/option-ext 系 Windows 平台依赖）。MPL-2.0 与 GPL-3.0 兼容（MPL §3.3 次级许可）；义务是文件级 copyleft：这 11 个包的源码保持可得（crates.io + Cargo.lock pin 即满足），修改其中文件需标注。结论：允许清单收录，无需例外。
- **Unicode-3.0（22 包）+ `(MIT OR Apache-2.0) AND Unicode-3.0`（2 包）**：icu/unicode 数据表。Unicode 数据许可宽松（保留声明即可）。注：全树无 `Unicode-DFS-2016` 字符串，特此记录。允许清单收录。
- **CC0-1.0**：`notify 8.2.2`、`tiny-keccak 2.0.2`；另 `imgref`（CC0 OR Apache-2.0）、`dunce`（CC0 OR MIT-0 OR Apache-2.0）取宽松分支。公有领域，无义务。允许清单收录。
- **ISC**：`inotify 0.11.5`、`inotify-sys 0.1.8`、`libloading 0.8.9`、`rustls-webpki 0.103.17`、`untrusted 0.9.0` + `ring`（Apache-2.0 AND ISC）+ rustls 四件套析取分支。ISC = 简化 BSD 系，宽松。允许清单收录。
- **0BSD**：`enum-iterator 2.3.0`、`enum-iterator-derive 1.5.0`、`adler2`（0BSD OR MIT OR Apache-2.0）。无义务。允许清单收录。
- **Unlicense**：`memchr`、`byteorder*`、`ignore`、`globset`、`walkdir`、`same-file`、`termcolor`、`winapi-util`、`jiff*` 五件套等（`OR MIT` / `/MIT` 析取）。公有领域，允许清单收录。
- **`(MIT OR Apache-2.0) AND NCSA`**：`libfuzzer-sys 0.4.13`（仅 fuzz 构建依赖）。NCSA = 伊利诺伊大学/NCSA 开源许可（BSD 系），合取两边都宽松。允许清单收录。
- **Apache-2.0 OR BSL-1.0**：`ryu 1.0.23`（BSL = Boost 软件许可，宽松）。允许清单收录。
- **MIT OR Apache-2.0 OR LGPL-2.1-or-later**：`r-efi 5.3.0/6.0.0`。取 MIT/Apache 分支，不触发 LGPL 义务。允许清单收录。
- **Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT**：`cbindgen` 依赖链等。LLVM 例外只放宽，允许清单收录。
- **Zlib 族**：objc2 0.3 系（`Zlib OR Apache-2.0 OR MIT`）、`bytemuck`、`dispatch2`、`zune-jpeg`（三向析取）、`Zlib` 单项。宽松，允许清单收录。
- **BSD 族**：`BSD-2/3-Clause` 及与 Apache/MIT 的析取合取共 6 种。宽松，允许清单收录。
- **E1 — `self_cell 1.3.0`（`Apache-2.0 OR GPL-2.0-only`）**：全树唯一含 GPL 的第三方 crate。GPL-2.0-only 与 GPL-3.0 不兼容，但析取允许我们只取 Apache-2.0 分支；**永不取 GPL-2.0-only 分支**。因「含不兼容分支」不进允许清单，走例外清单 pin 包名+license（`licenses-exceptions.txt` 第 1 条有效行）。
- **W — 自有包（3 个，license 为空）**：`lightamer-rust-spike`、`lightamer-bridge`、`gpui-viewport-spike`。项目代码本身 GPL-3.0-or-later，仅缺 `license` 字段；脚本对空字段按 FAIL 处理，故走例外清单 pin `(empty)`；产品工作区建好、字段补齐后退役。

### §4.3 gpui 族（版本钉死）

`gpui-kit 0.11.0` + `gpui-fast 0.1.19` 全家 + `gpui-pre 0.3.14` 全家（zed 上游包改名，`repository = github.com/zed-industries/zed`）+ `gpui-component/gpui-base` 0.11.0，license 字段实测全部为 `Apache-2.0`**非空**——T1 转述的「crates.io 空字段」注记已过时，以本次实测为准。版本锁死：升级任一 gpui 包必须重跑视口 spike 并更新本表（T1 处置沿用）。

### §4.4 objc2 / metal（Apple 模块预备）

`objc2 0.6.5` MIT；`objc2-* 0.3.2` 全家 `Zlib OR Apache-2.0 OR MIT`（另有 0.2.2/0.5.3 双版本并存，MIT，系 gpui-pre 依赖链带入）；`metal 0.29.0` MIT OR Apache-2.0。A6 落地时只允许出现在 `lightamer-apple`（T1 处置沿用）。

---

## §5 未来依赖登记（只登记许可证，不做取舍）

证据 = crates.io API `GET /api/v1/crates/<name>/<version>` 的 `license` 字段（2026-11-26 实测，需 `User-Agent` 头，直连经既有代理环境 200）。

| 依赖 | 版本（max_version） | 许可证 | 来源 | 备注 |
|---|---|---|---|---|
| `rusqlite` | 0.43.0 | MIT | github.com/rusqlite/rusqlite | T1 口径 bundled：SQLite 本体公有领域，crate 层 MIT；静态链接无义务 |
| `libsqlite3-sys` | 0.40.0 | MIT | github.com/rusqlite/rusqlite | rusqlite 的 bundled 后端，登记以备 A2 |
| `jpeg-encoder` | 0.7.1 | (MIT OR Apache-2.0) AND IJG | github.com/vstroebel/jpeg-encoder | **合取含 IJG**（Independent JPEG Group 许可，需保留其声明）；已预收进允许清单 |
| `xmp_toolkit` | 1.12.1 | MIT OR Apache-2.0 | github.com/adobe/xmp-toolkit-rs | 注意：crate 许可之外，底层 Adobe XMP SDK（C++）另有 BSD 类许可，A4a 定案时以实际构建核 |
| `xmpkit` | 0.1.6 | MIT OR Apache-2.0 | github.com/cavivie/xmpkit | 年轻纯 Rust 包，A4a 三测 |
| XML 直改（不引入库） | — | —（用已在锁中的 `quick-xml 0.41.0`，MIT） | 见 §4.1 表 | 无新增许可 |
| `crossbeam` / `crossbeam-channel` | 0.8.5 / 0.5.17 | MIT OR Apache-2.0 | github.com/crossbeam-rs/crossbeam | 锁中暂无，先登记 |
| `gpui`（zed 原版） | 0.2.2 | Apache-2.0 | github.com/zed-industries/zed | 仅登记；实际用 longbridge 系（§4.3），不取舍 |
| `image` / `png` / `tiff` / `flate2` / `zune-jpeg` | 见锁（0.25.10 / 0.17.16+0.18.1 / 0.11.3 / 1.1.11 / 0.4.21+0.5.15） | MIT（tiff）/ MIT OR Apache-2.0（其余，zune-jpeg 另 OR Zlib） | 见 §4.1 表 | 已在锁中，不复述证据 |
| `rayon` / `serde` / `parking_lot` / `bytemuck` / `thiserror` / `clap` / `tracing` | 见锁 | MIT OR Apache-2.0（bytemuck 另 OR Zlib；tracing MIT） | 见 §4.1 表 | 已在锁中 |

---

## §6 其它 C 库与数据包

### lensfun（代码与数据双许可）

| 项目 | 结论 |
|---|---|
| 代码（`libs/`） | `LGPL-3.0`（按 only 口径执行）。证据：① 官方手册 `lensfun.github.io/manual/latest/license.html`：`licensed under the terms of the GNU Lesser General Public License, version 3`，全文无 or-later 表述；② GitHub API `repos/lensfun/lensfun` 的 `license.spdx_id = LGPL-3.0`；③ 源码头（如 `libs/lensfun/modifier.cpp`）仅版权声明、无 or-later 授权语 |
| 应用（`apps/`） | GPL-3.0（我们不用 apps，只用 libs） |
| 测试/工具 | 公有领域（`tests/`/`tools/`） |
| 数据库（`data/`） | `CC-BY-SA-3.0`，与代码分离。证据：同手册页 `The lens database is licensed under the Creative Commons Attribution-Share Alike 3.0 license`。**代码与数据是两个许可证**：数据独立文件分发、保留署名与原许可，不并入 GPL 代码 |
| darktable 钉的版本 | **dt 不钉版本**：`cmake/modules/FindLensFun.cmake`（40 行）无版本要求，走系统库（pkg-config `lensfun`）。「以 dt 钉住版本为准」一条无 pin 可取——我们采用系统/源码包最新稳定版 + 本表登记，A2 定版时补版本号 |
| 链接与义务 | LGPLv3 §4 + 整体 GPL-3.0 分发（LGPLv3 = GPLv3 + 附加许可，可升 GPL-3.0）。动态或静态均可；静态时整体 GPL-3.0 即合规。数据文件署名 + CC-BY-SA 保留 |
| 纯 Rust 替换 | **无 T1 登记的候选，保留 C 库**。替换评估（自研求解/读 DB）留待 lens 移植波（T7 #7），本波不断言有无第三方 Rust 实现 |

### lcms2

| 项目 | 结论 |
|---|---|
| 许可证 | `MIT`。证据：`github.com/mm2/Little-CMS` 的 `LICENSE` 首行 `MIT License`（Copyright Marti Maria）；GitHub API `license.spdx_id = MIT` |
| darktable 用法 | 系统库（`cmake/modules/FindLCMS2.cmake`），无版本 pin |
| 链接与义务 | 静态链接，保留版权与许可文本 |
| 纯 Rust 替换 | **无成熟候选，保留**。ICC CMM 无 T1 登记的纯 Rust 实现；替换评估留待 colorin 移植波，本波不推荐 |

### 不引入的 C 库

- `libpng/libtiff/libjpeg`：不引入 C 库，用纯 Rust `png`/`tiff`/`jpeg-encoder`（§4.1/§5）。
- `exiv2`：不采用（XMP 选型见 T6/A4a）。

---

## §7 T1 逐项对账

| T1 行 | 结论 | 位置 |
|---|---|---|
| rawspeed | `LGPL-2.1-or-later`（证伪 LGPL-3.0 说法）；静态链接整体 GPL-3.0 | §3 |
| lensfun | 代码 LGPL-3.0（only 口径）/ 数据 CC-BY-SA-3.0；dt 无版本 pin | §6 |
| lcms2 | MIT | §6 |
| libpng/libtiff/libjpeg | 纯 Rust 替代，许可已登记 | §4.1/§5/§6 |
| exiv2 | 不采用 | §6 |
| XMP 库 | 三候选许可已登记，不取舍 | §5 |
| SQLite | rusqlite MIT + bundled 公有领域 | §5 |
| gpui 族 | Apache-2.0，字段非空（更正空字段注记），版本钉死 | §4.3 |
| objc2/metal | MIT / Zlib OR Apache-2.0 OR MIT / MIT OR Apache-2.0 | §4.4 |
| image 编解码组 | 全登记（含 jpeg-encoder 的 IJG 合取） | §4.1/§5 |
| 基础设施组 | 全登记（crossbeam 系 crates.io 补登记） | §4.1/§5 |
| darktable 移植 | GPL-3.0-or-later，同变体 | §2 |

---

## §8 再生成方法

- 本表 §4.1 由 `cargo metadata --locked --offline` 生成（命令见 §4.1），锁更新后重跑 `Scripts/check-licenses.sh <workspace>`；新增 license 字符串先过 §1 政策再进允许清单。
- C 库/数据包无 cargo 元数据，版本变更时人工更新 §3/§6 并在 `NOTICE` 同步。
- `NOTICE` 的第三方 crate 清单 = 本表 §4.1 + §5 的发布态摘要，由脚本输出再生成（条目数对账：`check-licenses.sh` 的 `total=` 与表行数一致）。

---

## §9 A5 新增依赖采用记录（2026-11-26，lane A5，append-only）

- `lightamer-cli` 新增直接依赖 `png 0.18.1`（16 位 PNG 解码，`cmp` 用；纯 Rust，无系统库）。
- 传递引入 10 个 crate：`adler2 2.0.1`、`bitflags 2.13.2`、`cfg-if 1.0.5`、`crc32fast 1.5.6`、
  `fdeflate 0.3.7`、`flate2 1.1.11`、`miniz_oxide 0.8.9`、`miniz_oxide 0.9.1`、
  `simd-adler32 0.3.10`、`zlib-rs 0.6.9`（`cargo tree -p lightamer-cli` 实测）。
- 上述 11 个（名，版本）**全部已在 §4.1 登记且版本逐字相同**（`png 0.18.1` 见 V:5063 行等），
  无需追加表行；`Scripts/check-licenses.sh` 实测 `allow=50 exception=0 fail=0`，退出 0，
  无新增 license 字符串（`MIT OR Apache-2.0` / `MIT` / `Zlib` / `0BSD OR MIT OR Apache-2.0` 均在允许清单）。

---

## §10 A6 新增依赖采用记录（2026-11-26，lane A6，append-only）

- `lightamer-apple` 在 `[target.'cfg(target_os = "macos")'.dependencies]` 新增 8 个直接依赖
  （版本钉 spike 锁表逐字）：`objc2 0.6.5`、`objc2-foundation 0.3.2`、
  `objc2-core-foundation 0.3.2`、`objc2-core-graphics 0.3.2`、`objc2-metal 0.3.2`、
  `objc2-core-image 0.3.2`、`objc2-image-io 0.3.2`、`objc2-vision 0.3.2`
  （`cargo tree -p lightamer-apple --target aarch64-apple-darwin` 实测）。
- 传递引入 11 个 crate：`block2 0.6.2`、`dispatch2 0.3.1`、`libc 0.2.191`、
  `objc2-encode 4.1.0`、`objc2-av-foundation 0.3.2`、`objc2-core-audio 0.3.2`、
  `objc2-core-audio-types 0.3.2`、`objc2-core-media 0.3.2`、`objc2-core-ml 0.3.2`、
  `objc2-core-video 0.3.2`、`objc2-io-surface 0.3.2`（`cargo metadata` 实测；
  `bitflags 2.13.2` 已在 A5 登记，不计入）。
- 上述 19 个（名，版本）**全部已在 §4 登记且版本逐字相同**（`objc2 0.6.5`、
  各 `0.3.2` 绑定、`block2 0.6.2`、`dispatch2 0.3.1`、`libc 0.2.191` 均见 §4 表），
  无需追加表行；`Scripts/check-licenses.sh` 实测 `allow=69 exception=0 fail=0`，退出 0，
  无新增 license 字符串（`MIT` / `Zlib OR Apache-2.0 OR MIT` / `MIT OR Apache-2.0` 均在允许清单）。

---

## §11 A7a 新增依赖采用记录（2026-11-26，lane A7a，append-only）

- `lightamer-engine` 新增 5 个直接依赖（`cargo tree -p lightamer-engine --depth 1` 实测）：
  工作区内 `lightamer-history`、`lightamer-iop-traits`、`lightamer-registry`，外部 `serde 1.0.229`、
  `serde_json 1.0.154`；`lightamer-cli` 新增 2 个直接依赖（同命令对 `lightamer-cli` 实测）：
  工作区内 `lightamer-engine`，外部 `serde_json 1.0.154`。
- 上述外部（名，版本）**全部已在 §4 登记且版本逐字相同**（`serde 1.0.229` 见 A:657 行等，
  `serde_json 1.0.154` 见 A:687 行等；A4b 已采用，锁文件只增依赖边、无新增 crate），
  无需追加表行；`Scripts/check-licenses.sh` 实测退出 0，
  无新增 license 字符串（`MIT OR Apache-2.0` 在允许清单）。

---

## §12 A7b 新增依赖采用记录（2026-11-26，lane A7b，append-only）

- `lightamer-gpui` 新增 3 个直接依赖（`cargo tree -p lightamer-gpui --depth 1` 实测）：
  工作区内 `lightamer-apple`、`lightamer-engine`，外部 `gpui-kit =0.11.0`（`gpui-fast` 特性，
  解析出 `gpui-fast 0.1.19` 一族，与 gpui-viewport spike 钉死的版本逐字相同）。
- `lightamer-apple` 在 `[target.'cfg(target_os = "macos")'.dependencies]` 新增 2 个直接依赖：
  `objc2-app-kit =0.3.2`、`objc2-quartz-core =0.3.2`（与既有七个框架绑定同 0.3.2 线；
  传递引入 `objc2-cloud-kit 0.3.2`、`objc2-core-data 0.3.2`、`objc2-core-text 0.3.2`）。
  spike 另用的 `metal 0.29` 与 `core-graphics-types 0.1.3` 本波未引入（渲染走既有的
  `objc2-metal`，几何类型走既有的 `objc2-core-foundation`）。
- 本仓锁共 848 包，其中第三方 819 个（`cargo metadata` 实测；检查总数此前为 69）；与 §4 表逐 `(名，版本)`
  比对，仅 4 个未登记（全是版本漂移，名已在册）：`ahash 0.8.14`（spike 锁 0.8.13）、
  `sha2 0.11.2`（在册 0.10.9/0.11.1）、`zerocopy 0.8.66` 与 `zerocopy-derive 0.8.66`
  （在册 0.8.65）。上述 4 个已按表列格式追加表行（锁列记 `L`，证据列 `L:<行>` 指本仓
  `Cargo.lock` 的 `[[package]]` 起始行；`L` 记法自本节起生效，不改 §4.1 既有行）。
- 4 个新行许可证（`MIT OR Apache-2.0` / `BSD-2-Clause OR Apache-2.0 OR MIT`）逐条核过，
  全部已在 `Scripts/licenses-allow.txt`；`Scripts/check-licenses.sh` 实测
  `allow=847 exception=1 fail=0`（exception 是沿用的 E1 `self_cell`），退出 0。
