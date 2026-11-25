# A1-REPORT — License and Dependency Audit (lane A1)

结论头：
- 审计表覆盖 854 个 crate（双 spike 并集）+ T1 全 13 项 + rawspeed/lensfun/lcms2/数据包/未来候选；例外 4 条（E1 自例外 + W 自有包 3）。
- rawspeed = LGPL-2.1-or-later（证伪 LGPL-3.0 说法），静态链接整体 GPL-3.0，与 darktable 同构；lensfun 代码 LGPL-3.0 / 数据 CC-BY-SA-3.0；lcms2 MIT。
- 脚本正例双 0、负例/非法数据双 1；`bash -n` 过；本机无 shellcheck（`command -v` 亲核）。

## 1. 基线

- 本仓库 HEAD（执行前亲核）：`a97cd47af6f550009d9bc29a7e61cbc2cbed9b74`
  （计划落盘基线 `1f9c1adb` 已是三提交之前；命令 `git rev-parse HEAD`）。
- 上游参考树 `Lightamer-rust-spike/refs/dt-master` HEAD = `679d594f5d`（`git describe` = `release-5.7.0-2234-g679d594f5d`）。
- rawspeed gitlink：`git ls-tree HEAD src/external/rawspeed` = `160000 commit 0c16fee7772594e98897bded01fc31bc3409b4cb`，与 A-6 一致。
- 锁一致性：仓内两锁与外部两工作区 `cargo metadata` 逐 `(name, version)` 比对，差集双 0；并集 854，交集 63。
- 墙钟：约 07:40–09:10（含自审），150 分钟预算内。

## 2. 审计覆盖

- `docs/LICENSE-AUDIT.md` §4.1：854 行（机检：行数 854、零畸形、零重名；命令见 §5）。
- §4.2 点名：MPL-2.0（11 包）、Unicode-3.0（22+2，无 Unicode-DFS-2016）、CC0（2+2）、ISC（5+5）、0BSD（2+1）、Unlicense 族、NCSA 合取、BSL 析取、IJG 合取（未来）。
- T1 全 13 项对账见审计表 §7；两处更正：① rawspeed 非 LGPL-3.0；② gpui 族 license 字段实测非空。
- 未来依赖：`rusqlite`/`libsqlite3-sys` MIT、`jpeg-encoder` (MIT OR Apache-2.0) AND IJG、`xmp_toolkit`/`xmpkit` MIT OR Apache-2.0、XML 直改无新增（§5，只登记不取舍）。
- 数据包：lensfun DB = CC-BY-SA-3.0 独立分发；rawspeed `cameras.xml` 随包（dt 同款）。

## 3. rawspeed 三问答案

1. **LGPL-2.1-or-later**：`LICENSE` = 2.1 全文（502 行）；244 头 `version 2 … or any later`、8 头 `version 2.1 … or any later`；`README.rst:35` LGPL v2→2.1 链接；全树零 LGPL-3.0 声明。不一致：LICENSE 系 2.1 文本而多数头写 `version 2`（2.0 时代表述），同为 or-later，不影响结论。
2. **静态链接**：or-later 升整体 GPL-3.0 分发（LGPL-2.1 §3），义务 = GPL-3.0 本体（保留声明 + 源码可得），无额外重链接义务。动态分支仅记录。
3. **darktable**：静态编入（`src/external/CMakeLists.txt:60` + rawspeed `CMakeLists.txt:203 STATIC` + `src/CMakeLists.txt:1309-1311`）；无单独声明，以整体 GPL-3.0-or-later 涵盖。
4. **推荐**：静态链接 + 整体 GPL-3.0-or-later（同 dt），NOTICE 登记 + 保留 LICENSE 文本 + pin 可得。

## 4. C 库

- lensfun：代码 LGPL-3.0（only 口径：手册页 + GH API `LGPL-3.0` + 头无 or-later 语）；数据 CC-BY-SA-3.0；dt 不钉版本（`FindLensFun.cmake` 40 行无版本要求）；纯 Rust 替换无 T1 候选，保留，评估留 lens 波。
- lcms2：MIT（`mm2/Little-CMS` LICENSE + GH API）；静态链接保留声明；无成熟纯 Rust ICC 候选，保留。
- libpng/libtiff/libjpeg：不引入 C 库（纯 Rust 已登记）；exiv2 不采用。

## 5. 验收命令与输出

```
$ bash -n Scripts/check-licenses.sh && echo BASH-N-OK
BASH-N-OK
$ command -v shellcheck || echo CONFIRMED-NO-SHELLCHECK
CONFIRMED-NO-SHELLCHECK
$ ./Scripts/check-licenses.sh /Volumes/UNITEK/Documents/Development/Lightamer-rust-spike
exit=0  allow=101 exception=2 fail=0 total=103
$ ./Scripts/check-licenses.sh /Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/viewport
exit=0  allow=812 exception=2 fail=0 total=814
$ <负例：AGPL-3.0-only 包 + 无 license 包>/tmp/lic-neg
exit=1  allow=0 exception=0 fail=2 total=2（两包皆 FAIL）
$ <允许清单追加非法行 'BAD | LINE'>
exit=1  check-licenses: ERROR: .../licenses-allow.txt:61: '|' not allowed in allow list（测后恢复，cmp 一致）
$ ./Scripts/check-licenses.sh   # 无参数：根尚无工作区
exit=1  check-licenses: ERROR: no Cargo.toml in workspace dir（符合预期，A2 建工作区后即通）
$ python3 表自检：crate rows 854，malformed 0，dup 0
```

中途修复一记：gpui 元数据 4.2MB 经 argv 传参报 `Argument list too long`（exit=126），改临时文件传参后双绿。

- Hash（终审基线）：`b75404b0c3602c4e58e7e0ef40b3a14ff0edc94e`

- `git show --stat`（终审基线，粘贴）：
```
 .work/gsd/phases/rust-core/waves/A1-REPORT.md |   81 ++
 NOTICE                                        |   45 ++
 README.md                                     |    6 +-
 Scripts/check-licenses.sh                     |  123 +++
 Scripts/licenses-allow.txt                    |   60 ++
 Scripts/licenses-exceptions.txt               |   13 +
 docs/LICENSE-AUDIT.md                         | 1037 +++++++++++++++++++++++++
 7 files changed, 1363 insertions(+), 2 deletions(-)
```
- 终审修订差集（`git diff <基线> HEAD --name-only`，终审后填；若 PASS 无修订则写"无修订，终版 = 基线"）：
```
终审 PASS（0 error + 0 minor，见 A1-review.log），产品文件零修订。
基线之后仅两处收尾改动（amend 并入同一 commit，不另起提交）：
  M .work/gsd/phases/rust-core/waves/A1-REPORT.md（回填 §6 基线 hash 与 stat）
  A .work/gsd/phases/rust-core/waves/A1-review.log（复审输出落盘，40 行）
```
- 终版 hash = 最终 amend 后 `git rev-parse HEAD`（提交后亲核，stdout 末尾给出；REPORT 入库故不可预写本 hash）。

## 7. 未做 / 未验

**未做**：① 上游 rawspeed master 最新许可未核（以钉住提交为准即可）；② lensfun/lcms2 具体版本号未定（A2 定版时补）；③ `xmp_toolkit` 底层 Adobe XMP SDK 许可未核（A4a 定案时核）；④ 自有包 3 个的 `license` 字段未补（属 spike 外部仓，只读；产品工作区建好后退役 W 例外）；⑤ 允许清单未来项仅预收 IJG 合取一种，其余未来依赖进锁时再议。

**未验**：① shellcheck（本机无）；② 根工作区无参数正向路径（根尚无 Cargo 工作区，A2 后复验）；③ `NOTICE` 条目数机检对账（A1 卡片第 5 条的"脚本比对条目数"——本波脚本输出 `total=` 供人工对账，全自动比对待 A2 工作区就位后补）；④ 域内自审结论见 `A1-review.log`（若 error 则修订记录附 §8）。

## 8. 终审修订记录

终审 PASS（0 error + 0 minor），产品文件零修订，无回注。复审独立验证点：义务码分布
P=783/U=24/PD=22/M=11/P-isc=10/W=3/E1=1；仓内/外部双锁各 IDENTICAL（V 8870 行、A 1013 行）。
