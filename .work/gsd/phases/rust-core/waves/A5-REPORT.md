# A5-REPORT — Oracle Acceptance Tool (dt-cli + oracle.sh)

> 结论：对照路已成一条命令。`Scripts/oracle.sh selftest` 退出 0，五组断言全过，数字与 spike 逐位一致；
> 差异报告覆盖 21 模块，夹具按 5.6.2 布局写。工作区测试 91 → 117，全绿。

## How to use

```bash
Scripts/oracle.sh fetch                                  # 取 5.6.2 包并校验（只留一个 dmg）
Scripts/oracle.sh render --image IN.ARW [--xmp IN.xmp] --out OUT.png --backend cpu|opencl
Scripts/oracle.sh selftest                               # 8 轮全分辨率渲染 + 五组断言（不进 ci-lite）
```

另：`Scripts/oracle.sh cmp A.png B.png [--max-mean F --min-in-tol F]`（越门退出 1）；
`Scripts/oracle.sh emit-xmp --image IN.ARW [--exposure-ev F] [--flip-x]`（默认写 `IN.ARW.xmp`）。
```
repeat g0-cpu vs g0-cpu-r2: mean_lsb=0.0000 max_lsb=0.0000 in_tol=1.00000000
repeat g1-cpu vs g1-cpu-r2: mean_lsb=0.0000 max_lsb=0.0000 in_tol=1.00000000
cpu-vs-cl g0: mean_lsb=0.0132 max_lsb=842.0000 beyond_samples=10 beyond_pixels=9
cpu-vs-cl g1: mean_lsb=0.0137 max_lsb=904.0000 beyond_samples=11 beyond_pixels=10
cpu-vs-cl g2: mean_lsb=0.0137 max_lsb=904.0000 beyond_samples=11 beyond_pixels=10
exposure-effect g0 vs g1: mean_lsb=2600.8714 max_lsb=10562.0000 in_tol=0.01953888
flip-plain g1 vs g2: mean_lsb=7747.8168 in_tol=0.02992269
mirror g1-cpu vs g2-cpu: mean_lsb=0.0000 max_lsb=0.0000
mirror g1-cl vs g2-cl: mean_lsb=0.0000 max_lsb=0.0000
prefs identical=true bytes=1726
hygiene mounts-clean=true
hygiene no-own-darktable-cli-procs=true
hygiene no-stale-tmp=true
selftest: PASS
selftest: workdir removed
```

命令：`Scripts/oracle.sh selftest` → `rc=0`，墙钟 9m54s。五组断言：①两组重复渲染
max=0；②三组 cpu/cl 平均差 <0.05、出界采样 ≤100（实测 0.0132/10、0.0137/11、0.0137/11，
与 spike 的 0.013/~10 逐位一致；「不同的像素」按出界采样计——全图约 1.3% 采样差恰 1 LSB
属容差内噪声，见 RESULTS.md 口径）；③曝光 mean=2600.9 >> 噪声；④双后端镜像 max=0
（零偏移；不镜像 mean=7747.8）；⑤偏好 1726B 逐字节相同。后端证据：cpu 腿日志
`device 'Apple Apple M4' id=0: NOT utilized`（5 轮），opencl 腿 `161/161`（2 轮）与
`162/162 events were successful`（g2 多 flip 一核）。
（首轮数字与上逐位相同，唯进程卫生探针误报并行 lane 进程与 launcher 自身，见修订记录 R1。）

## Baseline diff conclusion

官方包 5.6.2，钉点 `master 679d594f5d`，21 模块（T2 去 `clipping`）：17 个三版本版本号与
params 结构体逐字节相同；4 个只在 master 变——temperature v4→v5（20B→24B，加
`late_correction`）、highlights v4→v5（48B→40B，删未用 `blendL/blendC`）、demosaic v6→v8
（48B→60B，加 moire 双字段 + DNG GainMap）、colorin v7→v8（1044B→1048B，加 `output_rgb`）；
5.6.2 ≡ 5.7.0 在全部 21 个的版本与结构体上。默认值真变化三处：demosaic `cs_radius`
0.0→0.5、exposure 的 DNG 基线（ARW 不变）、crop 的机内画幅自动启用。结论：**夹具按 5.6.2
布局写**（读夹具的二进制按 `modversion == version() && len == params_size` 判）；本波两模块
三版本全同（exposure v7/28B、flip v2/4B）。全文见 `docs/ORACLE-BASELINE.md`。

## New dependencies

- 直接：`png 0.18.1`（唯一，`cmp` 解 16 位 PNG）。
- 传递 10 个：`adler2 2.0.1`、`bitflags 2.13.2`、`cfg-if 1.0.5`、`crc32fast 1.5.6`、
  `fdeflate 0.3.7`、`flate2 1.1.11`、`miniz_oxide 0.8.9/0.9.1`、`simd-adler32 0.3.10`、
  `zlib-rs 0.6.9`。
- 11 个（名，版本）全已在 `docs/LICENSE-AUDIT.md` §4 登记且版本逐字相同，无新增 license
  字符串；`Scripts/check-licenses.sh` → `allow=50 exception=0 fail=0`，退出 0。
  采用记录追加为审计表 §9（append-only）；`crates/README.md` 的 `dt-cli` 行已改。

## Acceptance (§10, command + output each)

1. `Scripts/oracle.sh selftest` → `rc=0`，打印上节五组数字（墙钟 9m54s）。
2. 坏包拒绝：在 `/tmp/dt-badcache/` 放 1000B 假 dmg，
   `./target/debug/dt-cli render --image … --out … --cache-dir /tmp/dt-badcache` →
   `refusing to run: … size mismatch … got 1000, want 88884896 …坏文件已删`，`rc=1`，
   事后该目录空（`total 0`）。
3. `cmp` 单元测试（测试内生成小图）：`identical_images_are_all_zero`（全 0）、
   `known_diffs_match_hand_math`（mean 252.5/max 1000/in_tol 4/6 与手算一致）、
   `gates_fire_on_breach`（两门各一违）、`mirror_x_compares_flipped`；
   CLI 越门：`cmp g0 g1 --max-mean 1 --min-in-tol 0.9999` → `gates FAIL…`，`rc=1`，
   `cmp g0 g0-r2` 同门 → `gates PASS`，`rc=0`。
4. `emit-xmp`：`g1/g2_matches_golden_byte_for_byte`（与 spike 探针逐字节相同）+
   `output_has_no_xml_comments`；CLI 冒烟 `cmp e2e 输出 golden` → `EMIT-BYTE-IDENTICAL-TO-GOLDEN`。
5. `cargo test -p dt-cli --locked` → `26 passed; 0 failed`。
6. 渲染卫生：单轮冒烟后 `hdiutil info | grep -ci darktable` → `0`，
   `pgrep -f "dt-oracle-run.*darktable-cli"` → 无命中，
   `$TMPDIR/dt-oracle-run-*` 无残留；selftest 内三项 hygiene 全 `true`。
   （注：无作用域的 `pgrep -f darktable-cli` 在本机永不干净——launcher 自身 watchdog 行
   含该字串 + 并行 lane 在跑官方 `darktable-cli`；探针已收窄到自家挂载路径，见 R1。）
7. 缓存：`ls ~/Library/Caches/lightamer-oracle/` → 仅 `darktable-5.6.2-arm64.dmg`
   88,884,896 B，与 `Scripts/oracle.lock` 的 `size_bytes/sha256` 一致（`fetch` 重验）。
8. `cargo xtask layers` → `OK: 28 crates, no layering violations`；
   `check-order-sync` → `OK (97 modules…)`；`check-no-iop-names` → `OK (97 names…)`。
9. `Scripts/check-licenses.sh`（无参数）→ `allow=50 exception=0 fail=0`，`rc=0`。
10. `cargo test --workspace --locked -j6` → 全绿，`passed=116`（= 91 基线 + 25 新增，
    `dt-cli` 1 → 26）。
11. `Scripts/rust-ci-lite.sh` → `ALL GREEN`，`rc=0`（内含 fmt/clippy 全工作区）。
12. `git status --short -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures` → 空；
    提交后 `git diff --stat 74f96797 HEAD -- …` → 空（见 Commit 节）。
13. `docs/ORACLE-BASELINE.md` §2 总表 21 模块 ×（5.6.2/5.7.0/master 三版本 + 默认值列）。
14. `git show --name-only HEAD` 仅允许路径（见 Commit 节）。

## Commit

message：`feat(oracle): one-command dt 5.6.2 render-compare rig` + body（`refs #32`）。
hash 见本 lane 最终 stdout（报告文件无法自含其所在提交的哈希；stat 下为提交前
`git diff --cached --stat`，与提交后 `git show --stat HEAD` 同一树跃迁）：

```
.work/gsd/phases/rust-core/waves/A5-REPORT.md  | (本文件)
.work/gsd/phases/rust-core/waves/A5-review.log | 130 ++++++
Cargo.lock                                     |  95 +++++
Scripts/oracle.lock                            |   8 +
Scripts/oracle.sh                              |  22 +
apps/dt-cli/Cargo.toml                         |   4 +
apps/dt-cli/src/cmp.rs                         | 454 +++++++++++++++++++++
apps/dt-cli/src/fetch.rs                       | 296 ++++++++++++++
apps/dt-cli/src/lib.rs                         |  12 +
apps/dt-cli/src/main.rs                        | 318 ++++++++++++++-
apps/dt-cli/src/render.rs                      | 540 +++++++++++++++++++++++++
apps/dt-cli/src/selftest.rs                    | 400 ++++++++++++++++++
apps/dt-cli/src/util.rs                        | 179 ++++++++
apps/dt-cli/src/xmp.rs                         | 264 ++++++++++++
crates/README.md                               |   2 +-
docs/LICENSE-AUDIT.md                          |  12 +
docs/ORACLE-BASELINE.md                        | 125 ++++++
fixtures/oracle/README.md                      |  52 +++
fixtures/oracle/expected-g1-exposure.xmp       |  35 ++
fixtures/oracle/expected-g2-exposure-flip.xmp  |  45 +++
20 files changed（含本文件）
```

`git show --name-only HEAD` 仅上列 20 路径（提交后复核，见 stdout）。
`git diff --stat 74f96797 HEAD -- 'crates/dt-iop-*/src/modules' crates/dt-registry/fixtures`
→ 空（提交后复核，见 stdout）。零 push。

## Cache and temp cleanup

- 缓存：`~/Library/Caches/lightamer-oracle/` 恰一个 `darktable-5.6.2-arm64.dmg`
 （88,884,896 B，sha256 `6ff88e58…def0c`，与锁文件一致）。
- 临时：每次渲染的 `$TMPDIR/dt-oracle-run-*`（home+mnt）随跑随删；selftest 默认临时
  workdir 跑完删（`selftest: workdir removed`）；冒烟与取证目录 `/tmp/dt-smoke`、
  `/tmp/dt-selftest-keep`、`/tmp/dt-badcache` 取数后手动删。
- 用户偏好：`defaults export org.darktable` 前后逐字节相同（1726 B），零 `import`、零 `killall`。

## Not done / not verified

- 未做：`cmp` 的 ±1px shift 搜索（`cmp16.py` 的 `--shift`；几何模块波需要时再加）；
  `render` 失败路径不做 prefs-after 对照（selftest 的全局前后照覆盖）；
  `NOTICE` 未同步（不在本波允许路径内）。
- 未验：OpenCL 腿在非 Apple Silicon 上的行为（本机 M4 实测通过）；
  `--width` 缩放路（spike 已证有 1px 伪影，对照恒用全分辨率）。

## Revision notes (self-review feedback)

R1（自查发现，提交前已修）：首轮 selftest 五组数字全绿但 `FAIL: darktable-cli process
left behind`——无作用域的 `pgrep -f darktable-cli` 在本机永不干净：launcher 自身 watchdog
命令行含 `pgrep -fl darktable-cli` 字串（`ps -o command= -p 31456` 实证），且并行 lane
正跑官方 `darktable-cli`（PID 40858 他人渲染）。修法：进程探针收窄为
`pgrep -f "dt-oracle-run.*darktable-cli"`（自家挂载路径），挂载探针收窄为 hdiutil 含
`dt-oracle-run`，并加 stale-tmp 探针。重跑 8 轮 → `PASS`，数字与首轮逐位相同。
R2（域内自审）：独立 `task` 实例 `A5Reviewer` 只读复审，`PASS / 0 error + 0 minor`
（见 `A5-review.log`）：独立重跑 `selftest` rc=0 且五组数字逐位相同；prefs 前后 cmp 无差异；
`cargo test -p dt-cli` 26 passed；temperature/highlights/demosaic/colorin/exposure
三版本源码抽查命中；两夹具与 spike 黄金逐字节相同；fmt/clippy 通过；路径审计 clean。
自审在提交前完成（`A5-review.log` 与产物同属一个 commit，核的是 `git status` 而非
`git show`，等价）。
