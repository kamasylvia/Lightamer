# Plan 13-4 SUMMARY — 分发收口（W3）

- **日期**: 2026-09-27/28 夜间，executor subagent worker
- **修订依据**: 用户 2026-09-27 终裁（GOAL-STATE ④ + orchestrator 派工书）——**砍苹果分发渠道**：Developer ID 签名 / notarytool / AC API key / hardened-runtime 切换整段移除；13-4 缩减为 T1 审计闸 → T2 GitHub 仓 → T3 载体 → T4 CI → T5 走查 → T6 签核。

## 任务战果

### T1 敏感审计闸 ✅（commit `8bdad6e`）

- **全历史扫描**: gitleaks 8.30.1 扫 695 commits（pack 1.60 GiB）→ **4 命中全部 false positive 且全部位于排除面**（darktablerc 的 `secret=` 配置键名 ×3 + .ips 崩溃报告 crashReporterKey ×1）。
- **人工三分类**: 内部域名（ts.net/qnap/ADO/infisical）在公开候选树零命中；token 模式零命中；个人标识面 = `com.kamasylvia.*` bundle-id 命名空间（D-05 one-way 锁，豁免）。
- **绝对路径命中 11 文件 → 全部清洗**: 注释改引 GitHub 正源（darktable/yiyin 上游 URL）；三处代码硬编改环境变量（`YIYIN_ROOT` / `LA_PERF07_VOLUME` / `DT_JSON`+PATH 探测 `DT`），回退语义逐处保持（Perf07 类 3/3 复跑绿）。
- **公开树策略**: 排除 `.work/`（1.2 GiB 相机样张版权/隐私 + 内部 GSD 流程文档）与 `AGENTS.md`（本机 agent 运维文档）；保留全部源码 + 小型 fixtures + 脚本 + README/LICENSE。
- **裁决位记录**: 用户 2026-09-27 终裁「commits 压缩后上传 + 全英文」→ 执行形态 = Phase 里程碑快照压缩史（13 commits），非增量直推非单点 squash。
- **闸判定 = PASS**，解锁公开仓操作。正本: `release-audit.md` + `release-audit-gitleaks.json`。

### T2 GitHub 公开仓 + 压缩英文史首推 ✅

- **LICENSE（MIT）+ README 公开版重写**（commit `66e7d8d`）——移除已废止的 Developer ID/notarization 表述；补 Build/Test/Sample-images/Provenance 节。
- **压缩史构造**: 13 个 Phase 里程碑快照（P1→P2→P3→P4→P5→P6→P7→P8→P9→P11→P12→P16→P13），逐快照 git archive（allowed-tops 过滤）+ 路径/品牌名 sanitizer + 原始作者日期保留 + 英文 what+why 正文。边界 = 各 phase 签核/收口 commit（572487e/865f5f0/3dffd8b/6505858/4cd9a4e/fcc0d6d/58d456f/64c1820/2bb0f84/4ce5113/407efde/51423a2/HEAD）。
- **首推前四重验证全过**: gitleaks（no leaks）+ 排除面断言（零 .work/AGENTS.md 进任何 commit）+ 敏感串断言（/Volumes/UNITEK/ts.net/qnap/dev.azure/infisical = 0）+ **末态文件集与 ADO HEAD 过滤树 diff 全等**。pack 仅 2.53 MiB（大体积全在排除面）。
- **仓库**: https://github.com/kamasylvia/Lightamer （public，main = 13 commits，描述/topics 已设）。**ADO origin 未动**（私有全历史保留；origin/main SHA 复核 = 任务前值）。
- 后续 T3/T4/修复 commit 经 format-patch 重放到公开仓并 push（`ff7bf4f..cab90d9`）。

### T3 DMG/zip 双载体 ✅（commit `87b323b`）

- `Scripts/release/make-dmg.sh`：自包含（构建 + 打包）——Release 构建以 **ad-hoc + unhardened** 覆盖（见 DECISIONS D3），hdiutil UDZO 拖装布局（app + /Applications 软链）+ ditto zip + SHA256SUMS.txt，版本取自构建产物 Info.plist（0.1.0）。
- **产物**: `build/release/Lightamer-0.1.0.dmg`（7.4M）+ `.zip`（6.5M）+ `SHA256SUMS.txt`（`7a58a626…`/`cef095d6…`）。验证: DMG 挂载布局正确、zip 完整性绿、**解包 app 实机启动 +5s**。
- **根因记录（重要）**: 初版（Lightamer Dev 自签 + hardened runtime）产物 **dyld 拒载**——"mapping process and mapped file have different Team IDs"（macOS 27 库校验对无 Team ID 自签证书 + hardened 的死局，清洁重建不解）。ad-hoc + unhardened = unsigned 分发形态的正解（hardened 本服务于已砍的公证面）。
- **Bundle.main 纪律审计（DIST-2）**: 零绝对路径字面量（/Users、/etc、~/ = 0）；metal 库全走 `Bundle(for: Marker.self)` 锚；数据资产走 bundle `forResource:` 查找；用户文件走 Application Support/用户域。PASS。

### T4 GitHub Actions CI ✅（commit `9278695`）

- `.github/workflows/ci.yml`：**build-and-test**（push/PR，macos-27 runner = Xcode 27 SDK floor；Tuist install+generate；Debug build-for-testing ad-hoc+unhardened；`Scripts/test-direct.sh` 全套；Release 形状编译）+ **release**（v* tag → make-dmg.sh → artifact 上传 + **Draft** GitHub Release，人工发布）。**零 secrets**（无证书/无签名身份/无 Apple 凭据）。
- 已推送 GitHub（cab90d9）。CI 首跑结果 = 执行期未观测项（runner 镜像 beta、Metal toolchain 问题 #14548 在案）——见「遗留」。

### T5 走查批 ✅（12+ 行证据，2 缺陷抓出 1 已修）

**12-VALIDATION Manual-Only 13 行承接**（控制台解锁实机走查，截图 `.work/gui-acceptance/2026-09-28-13-4-*.png`）：

| 行 | 结果 | 证据 |
|---|---|---|
| F-12-1-1 ⇧多选批量 | **PASS** | 02/02b——⇧ 范围选 + ⌘ 加减选事件序与终态 {1,3} 一致（终态截图差一帧重绘） |
| F-12-1-2 右键追加关键词 alert | **PASS** | 03→04→04b→05；alert 输入（剪贴板粘贴）→ 好 → **双 sidecar 落盘 grep 命中** |
| F-12-1-3 对比态双格 | **PASS** | 06/06b——双格并排，第二格 100MP 渲染中（错峰 culling 管线在飞） |
| F-12-2-1 `/` 聚焦快速过滤 | **PASS** | 07——字段获得焦点环 |
| F-12-2-2 chips ⓧ | **PASS（部分）** | 09/10——active chip + ⓧ affordance 在案；ⓧ 合成点击不命中 = 驱动局限（L032 族），删除语义由 12-2 自动化腿钉 |
| F-12-2-3 日期区间 sheet | **PASS** | 12——双 DatePicker（起/止 stepper）+ 取消/应用 |
| F-12-2-4 智能相册 rename/delete alert | **PASS + 抓修** | 13/14/23——rename alert（预填名）+ delete confirm；**delete confirm 正文裸键缺陷（见下）已修并实机复验** |
| F-12-3-1 第三方 .xmp 导入 | **PASS** | 15——toolbar 导入菜单 → NSOpenPanel → 导入成功：sidecar mtime 推进 + `thirdparty` 关键词入 sidecar 且进 lindex 行 |
| F-12-3-2 typed 错误 alert | **PASS** | 16——损坏 .xmp → 「XMP 导入失败 / 该文件不是可解析的 XMP 数据包。」zh 文案正确 |
| F-12-4-1 管理器重命名 alert | **PASS** | 19——管理器窗 + 重命名 alert（预填名）+ 坏预设 footer 自愈面；临时预设已删净 |
| F-12-4-2 部分粘贴全链 | **PASS** | 17/18——复制调整 → 部分粘贴对话框（合并/覆盖 + 曝光勾选）→ 粘贴 → **9991 sidecar mtime 推进 + exposure/temperature instance 落盘** |
| F-12-5-1 LUT 面板深交互 | **遗留** | 合成输入无法可靠驱动 NSOpenPanel 文件选择；12-5 自动化腿（store 10 测 + wiring + 降级链）在案 |
| F-12-5-2 dt-GUI golden 人工对照 | **遗留（人眼判定）** | 材料包 13-2 已备（D-13-2-8 五步规程）；人眼判定归 verify-work 用户终验 |

**13-1 QL/Spotlight 实测**:
- **QL 空格预览 PASS**（20）——qlmanage 打开已编辑 DSC00012.ARW → 预览窗显示**编辑态渲染**（蓝青调性 = sidecar 管线输出，非原图缩略）；SYS-01「含调整后预览」黑体实机证实。
- **Spotlight 部分**——`mdimport -t -d3` 由系统 Image.mdimporter 接管（DerivedData Debug app 的 appex 未进 pluginkit 注册）；**lindex 抽取源实测健康**（34 列活、thirdparty 关键词已入行、EXIF 列在）；importer 映射由 13-1 单测钉死。**mds 级实测遗留**：需 app 安装 /Applications 后复测（13-1 SUMMARY 既有 caveat）。

**13-2/13-3 新面**: proof 菜单（软打样/色域警告（黑色裁剪））与 zoom HUD（zoom.hud.fit/label）AX 元素在案（21/22）；ON 态观感、真双屏（单显示器机器不可测）、触控板手感、拖放观感 → 遗留（自动化腿各自在案）。

**走查抓出缺陷 1（已修 + 实机复验）**:
- **删除智能相册 alert 正文裸键**——`Text("smart_album_delete_confirm_body \(album.name)")` 的 LocalizedStringKey 插值查找键 `smart_album_delete_confirm_body %@` ≠ catalog 键 → 裸键回退。修 = `String(format: String(localized:))`（commit `d0f8ff3`）；重建后实机复验：正文正确显示「删除「高分组」？规则文件将被移除；照片本身不受影响。」（证据 23）。
- **连带发现并修复**: 审计词级 sed 把 Perf07 测试方法名改出非法标识符（空格入名）→ 测试构建失败；正名 `testExternalVolumeDrainComparisonRecordOnly`（commit 本轮收口提交）。

### T6 全量回归 + 翻账 + 签核

- 终轮全 suite：见本文末「终轮计数」（实测数为准）。
- 翻账：REQUIREMENTS SYS-01..05 / DIST-01..04 / COLOR-02/03 → Delivered；TODO Phase 13 收口；GOAL-STATE 阻塞节清理（Apple 渠道项随终裁作废；GitHub 供件已消费）+ Phase 13 收口行。
- `13-VALIDATION.md`：SC#1-4 三列证据 + status: validated（**C 档第 3 停 = 夜间授权先例 D-07-3-T5-1/D-09-05-T1-1/11-05 D1 执行，晨审可推翻**）。

## 终轮计数

（终轮实测：**Executed 1636 tests, with 11 skips and 0 failures（610.9s），SUITE_EXIT=0**。总执行数与基线 1636 持平——13-4 零净增测试；skip 10→11 = Perf07 外置卷对比测试改 `LA_PERF07_VOLUME` env 门后本轮未设 env（按设计跳过；供 env 时 3/3 绿已实测）。13-4 无新增测试面。）

## 凭据与纪律

- 凭据零入仓/入日志/入产物/入文档；GitHub 使用本机既有 gh keyring + SSH（Infisical 供件路径未启用，见 DECISIONS D1）；审计报告与 gitleaks 证据 redacted。
- 每任务独立提交（8bdad6e / 66e7d8d / f54a629 / fa0f859 / 87b323b / 9278695 / d0f8ff3 / 本收尾提交）；`caffeinate -dis` 包裹构建；每任务边界查 `.work/config.toml [gsd]`（auto=true/paused=false 全程）。
- **纪律违反自首**: T4 推送时一次 `git push origin main` 因 cwd 未切换误指 ADO origin——于上传阶段即时 TaskStop 终止，`ls-remote` 复核 ADO ref = 任务前值（8c74c82d），远端零变更（push 原子性保证）。教训记 DECISIONS D7 + LESSONS 候选。

## 遗留（登记，非阻塞）

1. **CI 首跑观测**: macos-27 镜像 public preview + Metal toolchain issue（actions/runner-images#14548）——若 build/test 红，按 runner 实况调 skip 面或等镜像 GA。
2. **Spotlight mds 级实测**: app 安装 /Applications 后 `mdimport -t -d3` 复测（数据源 lindex 已实测健康）。
3. **F-12-5-1 LUT 面板深交互 / F-12-5-2 dt-GUI 人眼对照 / 触控板手感 / 拖放观感 / proof ON 态 / 真双屏**: 待用户 verify-work 走查（自动化腿全部在案）。
4. **签名升级**: 若未来重启 Apple 渠道 → Developer ID + notarization 面 v2（`Scripts/release/make-dmg.sh` 的 ad-hoc/unhardened 覆盖届时移除）。
