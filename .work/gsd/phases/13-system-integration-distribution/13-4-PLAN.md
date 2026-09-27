---
phase: 13
plan: "13-4"
title: "分发收口（DIST-01..04）：敏感审计闸前置（git 全历史凭证/域名/路径扫描报告落档 + 全历史 vs squash 用户裁决位显式问询）+ Developer ID 切换（凭据供件检查点，缺位即阻塞登记停）+ 深签级联校验（app+framework+appex 逐个）+ notarytool 公证（warnings=errors + staple + quarantine 实测）+ DMG/zip 双载体 + GitHub 公开仓（MIT LICENSE）+ GitHub Actions CI（PR 无签名构建测试 / tag 完整发布链）+ Manual-Only 承接走查批（12 期剩余行 + GUI-20 复验 + 本 Phase 新面走查）+ VALIDATION 签核（C 档第 3 停）"
wave: 3
depends_on: ["13-1", "13-2", "13-3"]
autonomous: false
requirements: [DIST-01, DIST-02, DIST-03, DIST-04]
files_modified:
  - Project.swift                                                     # Release 配置 CODE_SIGN_IDENTITY → Developer ID Application（Debug 保 "Lightamer Dev" L011 不动；:33 注释预告兑现）
  - LICENSE                                                           # 新建：MIT
  - README.md                                                         # 开源面（项目简介/构建方式/许可；如已有则更新分发节）
  - Scripts/release/notarize.sh                                       # 新建：notarytool 公证 + staple + 零 warning 处置（warnings=errors）
  - Scripts/release/make-dmg.sh                                       # 新建：hdiutil UDZO DMG + zip 双载体
  - Scripts/release/codesign-verify.sh                                # 新建：codesign -v 级联校验清单（app + 每 framework + 每 appex）
  - .github/workflows/ci.yml                                          # 新建：PR/push = 构建 + 测试（无签名）；tag = 构建→测试→签名→公证→DMG/zip→GitHub Release
  - .gitignore                                                        # 按公开仓需要修订（凭证/产物排除面复核）
  - .work/gsd/phases/13-system-integration-distribution/release-audit.md  # 新建：敏感审计报告（全历史扫描工具+规则+命中+处置）+ 裁决位记录（全历史 vs squash）
  - .work/gsd/phases/13-system-integration-distribution/13-4-SUMMARY.md
  - .work/gsd/phases/13-system-integration-distribution/13-4-DECISIONS.md
  - .work/gsd/phases/13-system-integration-distribution/13-VALIDATION.md  # 签核（T7；签核前停 = C 档第 3 停）
  - TODO.md                                                           # 13-4 勾选 + SYS/DIST/COLOR 翻账 + Manual-Only 承接行关闭
  - .work/gsd/REQUIREMENTS.md                                         # SYS-01..05 / DIST-01..04 / COLOR-02/03 翻账 Delivered（T7）
  - .work/GOAL-STATE.md                                               # Phase 13 收口 + 阻塞节清理（T7）
  - LESSONS.md                                                        # 如踩坑
---

# Plan 13-4 — 分发收口（W3，收口 + 签核）

> 背景：从 dev 自签证书到 Developer ID 的整机切换 + 项目首次公开（D-13-CONTEXT-8）。`Project.swift:27-35` 注释钉死本次切换；当前 remote = Azure DevOps 私有仓（无 LICENSE、无 `.github/`），GitHub 公开仓 = 新 remote，**敏感审计是前置闸**。
> **用户 2026-09-27 裁决：砍苹果分发渠道**——Developer ID 签名/公证/notarytool/AC API key **整段移除**（不做 Apple notarization）；SC#4 修订 = GitHub 公开仓 + CI(build+test 无签名) + 可选 unsigned DMG/zip；T2/T3 缩减为：T2 = 敏感审计后仓创建+首推 / T3 = DMG/zip unsigned + CI。原签名公证面记 v2（如未来需要 Apple 渠道再启）。

四条主线：① **敏感审计闸**——git 全历史凭证/token/内部域名/绝对路径扫描报告落档，命中处置后才许任何公开仓操作；「全历史 vs squash 起点」二选一 = **用户裁决位**（晨审特别提请——plan 期不得自选，默认全历史但须显式问询并记录）。② **签名公证链**——Developer ID 切换 + 逐嵌套 binary 深签 + notarytool（warnings=errors）+ staple + quarantine 实测。**凭据 = 人工阻塞项**：Developer ID 证书与私钥 / AC API key / GitHub 仓创建与公开时机 / Secrets 配置——T2 开工前检查点，缺位即 GOAL-STATE 阻塞节登记并停（不得 ad-hoc 蒙混）。③ **载体与 CI**——DMG（hdiutil UDZO）+ zip 双产物 + GitHub Actions（PR/push 无签名构建测试，tag 完整发布链）。④ **收口走查与签核**——Manual-Only 13 行承接（F-12-5-2 已由 13-2 关闭）+ GUI-20 复验（TODO :27，dev-signed 层 B 资产供给 → Developer ID 复验；checker M3 锚点校正）+ 本 Phase 新面走查（QL 空格/Spotlight 检索/手势/proof 面板/蒙版命令/双屏）+ VALIDATION 签核（**签核前停 = C 档第 3 停**）。内部序刚性：T1 审计闸 → T2 签名 → T3 公证 → T4 载体 → T5 仓/CI → T6 走查 → T7 签核。

## read_first

1. `.work/gsd/phases/13-system-integration-distribution/13-CONTEXT.md`——D-13-CONTEXT-8（分发链七裁决：MIT/新仓全历史+审计闸/Developer ID 切换/notarytool warnings=errors/DMG+zip/CI tag 流水/凭据人工项）、Boundary 事实 2（非沙盒延伸+逐嵌套 binary 深签）、验证红线（分发链专项 + 敏感审计闸——逐条为本 plan AC 正本）、specifics 节（审计闸第一任务/裁决位问询/凭据早登记三强调）
2. `.work/gsd/ROADMAP.md` §Phase 13 Notes——DIST-1（deep-sign every embedded binary + warnings as errors）/ DIST-2（Bundle.main 纪律——Gatekeeper translocation）/ DIST-3（扩展独立 entitlements 非沙盒解耦）/ :232 蒙版批（T6 走查项）；`TODO.md` :296（GUI-20 复验 + GUI-19）/ :302 v2 排除表
3. `.work/gsd/phases/12-metadata-presets-lut/12-VALIDATION.md:84-101`——Manual-Only 汇总表 13 行（F-12-4-3 已关、F-12-5-2 由 13-2 关；剩余行 = T6 承接清单）
4. `Project.swift`——:27-35 Manual signing 注释 + Developer ID 切换预告正本 / :45-48 per-config hardened / T1 产物结构（深签对象清单：app + LightamerCore/LightamerIOP framework + 两 appex）
5. `.work/gsd/phases/13-system-integration-distribution/13-1-SUMMARY.md`（appex 签名链/@rpath 形状验证结论——深签清单输入）+ `13-2-SUMMARY.md` / `13-3-SUMMARY.md`（Manual-Only 候补行汇总）
6. `LESSONS.md` L011（测试授权三件套——Debug 签名身份不动）/ L009（产物落盘纪律）+ `AGENTS.md`（Phase 执行模型 + 暂停机制——本 plan autonomous=false 全程用户在场点：凭据供件/裁决位/签核停）+ `.work/GOAL-STATE.md`（阻塞节——凭据供件登记/清理位）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。**公开仓敏感面例外**：T1 审计报告、LICENSE、CI workflow 等入库面正常提交；**推送 GitHub = 仅 T5 在审计闸过 + 裁决位记录后执行，推新 GitHub remote，不动 ADO origin**；其余任务不 push。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**；本 plan 另有**人工在场点三处**（T1 裁决位问询 / T2 凭据检查点 / T7 签核停）——任一未获用户答复即停，不得代答。
- **构建纪律**：勿加 `-derivedDataPath`（SPM submodule 坑）；T2 修改 Project.swift 及新建 `Scripts/release/` 后跑 `tuist generate` 一次（checker M1 补点）。
- **回归基线 = 1553/9skip/0fail + 13-1/13-2/13-3 新增**；发布前全 suite 终轮 0 fail。**flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 隔离 ×3 归因单列，不计违约。
- **凭据纪律（最高优先）**：Developer ID 证书/私钥/AC API key 只经临时环境变量与 GitHub Secrets 传递，**永不入仓/入日志/入产物/入 SUMMARY 截图**；T2 开工前检查点缺件 → GOAL-STATE 阻塞节登记并停；CI 零凭据泄漏扫描（secrets 不入日志/产物）是发布链 AC。
- **审计闸硬序**：T1 报告落档 + 命中处置完成 + 裁决位记录之前，**禁止任何公开仓操作**（建仓/推送/公开切换）。
- **公证红线**：notarization log 任何 warning 按 error 处置（ROADMAP DIST-1 字面）；处置记录入 SUMMARY；未 staple 不算发布产物。
- **GUI 走查标注**：quarantine 首启实测、GUI-20 复验、QL/Spotlight/手势/proof/蒙版命令/双屏走查均**需解锁控制台（Manual-Only）**——本 plan 走查批即其归宿。
- **Bundle.main 纪律走查**（DIST-2）：资源路径解析全走 `Bundle.main`（Gatekeeper translocation 防护），走查输出贴 SUMMARY。
- **L031 声明**：本 plan 无新 Metal 面——`makeRoutedCommandBuffer()` 红线不适用；如执行中发现需要即停下报告。
- RESEARCH/CONTEXT 未覆盖细节（DMG 卷名/卷面文案、CI runner 镜像选型 macos-15/26、tag 命名规约、Release 草稿 vs 直发、README 分发节措辞）标注**执行期决策**入 `13-4-DECISIONS.md`，不臆造。

## Tasks

### T1 敏感审计闸 + 公开裁决位问询（第一任务，前置闸）

- **action**
  1. **全历史扫描**：gitleaks 类工具全量 git 历史扫描（凭证/token/私钥块）+ 人工复核三类（内部域名——`*.ts.net`/Infisical/QNAP/ADO 主机名、绝对路径——`/Volumes/UNITEK`/用户名、个人标识面）。
  2. 报告落档 `release-audit.md`：工具与规则版本 + 扫描范围 + 命中清单 + 逐项处置（清洗/豁免理由）。
  3. **用户裁决位（显式问询，不得自选）**：「全历史推送 vs squash 起点」——按 D-13-CONTEXT-8 默认全历史提问，用户答复与依据**记录入 release-audit.md**；命中需清洗而用户仍选全历史时，先清洗再推。
  4. 审计闸判定行：PASS（零命中或处置完毕）才解锁 T5 公开仓操作。
- **证据**：release-audit.md（扫描输出 + 处置表 + 裁决记录 + 闸判定行）。

### T2 Developer ID 切换 + 深签级联校验

- **action**
  1. **凭据检查点（人工在场点）**：Developer ID Application 证书 + 私钥就位确认；缺件 → GOAL-STATE 阻塞节登记（用户供件）并停，**不得用 ad-hoc/dev 证书蒙混**。
  2. `Project.swift`：Release 配置 `CODE_SIGN_IDENTITY` → `Developer ID Application`（Debug 保 `Lightamer Dev`——L011 测试授权三件套不动；hardened runtime Release 已开 `:48` 不动）。
  3. 新建 `Scripts/release/codesign-verify.sh`：级联校验清单——app 本体 + 每 framework（LightamerCore/LightamerIOP/libwebp 面）+ 每 appex（QuickLook/Spotlight）逐个 `codesign -v --deep-strict` + authority 链断言（Developer ID Application → Apple-certified）。
- **证据**：切换后 Release 构建产物全清单校验输出（脚本 + 逐 binary verdict 贴 SUMMARY）；Debug 测试授权回归（全套 suite 照常绿——L011 不被扰动）。

### T3 notarytool 公证（warnings=errors）+ quarantine 实测

- **action**
  1. 新建 `Scripts/release/notarize.sh`：notarytool（AC API key 认证——keychain profile 或环境变量注入，凭据纪律节）提交 → wait → **log 任何 warning 按 error 处置**（失败即修：常见项 hardened 违规/未深签嵌套 binary/非 LLVM noruntime 段）→ `stapler staple` 后置。
  2. **quarantine 实测**：发布产物注入 `com.apple.quarantine` xattr → 首启 Gatekeeper 放行验证（`spctl -a -vv` + 真机双击首启走查）——**需解锁控制台（Manual-Only）**。
- **证据**：notarization log 零 warning 处置记录 + staple 回执 + spctl verdict + 首启走查截图（凭据/账号信息脱敏）。

### T4 DMG/zip 双载体 + Bundle.main 走查

- **action**
  1. 新建 `Scripts/release/make-dmg.sh`：`hdiutil` UDZO 素面 DMG（拖安装布局：app → Applications 软链；create-dmg 美化 deferred）+ `ditto` zip 双产物；产物命名含版本（tag 派生，执行期决策定规约）。
  2. **Bundle.main 资源路径纪律走查**（DIST-2）：全仓 grep 资源路径解析面（Localizable/lut 固定资产/字体/logo），断言零硬编绝对路径、全走 `Bundle.main`；translocation 场景（下载目录首启）产物可启动。
- **证据**：双产物生成 + 校验和；走查输出贴 SUMMARY；DMG 挂载拖装验证（Manual-Only 候补）。

### T5 GitHub 公开仓 + LICENSE + CI（审计闸 + 裁决位 + 凭据之后）

- **action**
  1. **前置确认三闸**：T1 闸 PASS + 裁决位记录在案 + GitHub 凭据/Secrets 就位（检查点，缺件即停——人工在场点）。
  2. `LICENSE`（MIT）+ README 分发/构建节 + `.gitignore` 复核修订。
  3. **建新 GitHub 公开仓**：按裁决位执行推送（全历史 → 现历史直推新 remote；squash → 单根新历史），**不动 ADO origin**；`git remote add github …` + 推送 + 公开切换（时机 = 用户裁决输入）。
  4. 新建 `.github/workflows/ci.yml`：PR/push = 无签名构建 + 测试（runner 上无证书也绿）；tag = 完整链 构建→测试→签名→公证→DMG/zip→GitHub Release（Secrets：AC API key + 证书 p12 + 密码；**零凭据泄漏扫描**——secrets 不入日志/产物断言）。runner 镜像选型（macos-15/26，CIRAW-2 per-OS 矩阵注记）执行期决策。
- **证据**：远端可见性/private 状态截图（公开前）→ 公开后 URL；CI PR 跑绿 + tag 触发链全绿回执（凭据脱敏）；泄漏扫描输出。

### T6 Manual-Only 承接走查批 + GUI-20 复验

- **action**
  1. **Manual-Only 13 行承接**（12-VALIDATION:84-101 汇总表；F-12-5-2 已由 13-2 关闭）：剩余行逐条真机走查批量确认（⇧ 多选/chips 长按/alert 流/IME 键/深交互观感等）——全部**需解锁控制台（Manual-Only）**。
  2. **GUI-20 复验**（TODO :296）：dev-signed 层 B 资产供给问题在 Developer ID 签名下复验。
  3. **本 Phase 新面走查批**：QL 空格预览（编辑态 + 三查回退观感）/ Spotlight 系统检索实测（评级/关键字命中）/ 手势与 zoom HUD 观感 / 拖放导入观感 / proof 面板与 OOG 黑裁剪观感 / 蒙版命令操作流 / 真双屏切换——13-1/13-2/13-3 各 SUMMARY 的 Manual-Only 候补行逐条清账。
  4. 走查发现非阻断观感项 → 登记进 SUMMARY 遗留；阻断项 → 回注修复批后复走。
- **证据**：走查台账（逐行 PASS/遗留）入 SUMMARY；GUI-20 复验结论 + TODO 行关闭。

### T7 全量回归 + 翻账 + VALIDATION 签核（C 档第 3 停）

- **action**
  1. 全 suite 发布前终轮（基线 **1553 + 13-1/13-2/13-3 新增**，0 fail）。
  2. 翻账：`.work/gsd/REQUIREMENTS.md` SYS-01..05 / DIST-01..04 / COLOR-02/03 → Delivered（附证据锚）；TODO.md Phase 13 勾选收口；GOAL-STATE 阻塞节清理（凭据项已消费）+ Phase 13 收口行。
  3. `13-VALIDATION.md`：SC#1-4 三列证据（一手锚/测试锚/GUI 实证锚）+ 覆盖矩阵 + Manual-Only 汇总（12 期承接行 + 13 期走查行全闭合）+ 缺陷处置记录。**签核前停 = C 档第 3 停**：VALIDATION 结论先呈用户过目，用户签认后方落 `status: validated`（夜间授权先例可用但晨审可推翻）。
- **证据**：终轮计数；三处翻账 diff；VALIDATION 落盘（含签核停记录）。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 审计闸 | 全历史扫描报告 + 处置 + 裁决记录 + 闸 PASS 行 | release-audit.md 评审 |
| 签名 | 级联校验全绿（app+framework+appex × Developer ID 链） | `Scripts/release/codesign-verify.sh` |
| 公证 | log 零 warning + staple 回执 + quarantine 放行 | `Scripts/release/notarize.sh` + spctl + 走查（Manual-Only） |
| 载体 | DMG+zip 产物 + 校验和 + Bundle.main 走查零硬编路径 | `Scripts/release/make-dmg.sh` + grep 审计 |
| 仓/CI | LICENSE/公开仓/CI PR 绿 + tag 链绿 + 零凭据泄漏 | GitHub Actions 回执 + 泄漏扫描 |
| 走查 | Manual-Only 承接行 + GUI-20 + 新面批逐条清账 | 人工走查台账（SUMMARY） |
| 签核 | 终轮 0 fail + 三翻账 + VALIDATION（签核停记录） | `caffeinate -dis Scripts/test-direct.sh`（全套）+ 13-VALIDATION |

## 验收标准（Acceptance）

- [ ] 敏感审计闸：全历史扫描报告落档（工具/规则/命中/处置）+ 「全历史 vs squash」用户裁决显式记录 + 闸 PASS 后才公开仓操作
- [ ] Developer ID：Release 切换（Debug/L011 不动）+ 级联深签校验清单全绿（app + 每 framework + 每 appex）+ 凭据检查点记录（缺件即阻塞登记停）
- [ ] 公证：notarytool log 零 warning（warning=error 处置记录）+ staple + quarantine xattr 首启 Gatekeeper 放行实测
- [ ] 载体：DMG（UDZO 拖装布局）+ zip 双产物 + 校验和 + Bundle.main 纪律走查（零硬编资源路径）
- [ ] GitHub：MIT LICENSE + 新公开仓（裁决位执行）+ ADO origin 不动 + CI（PR 无签名绿 / tag 完整链绿 / Secrets 配置 / 零凭据泄漏扫描）
- [ ] 走查收口：Manual-Only 13 行承接清账（F-12-5-2 除外已关）+ GUI-20 复验关闭 + 本 Phase 新面走查批清账
- [ ] 签核：发布前全 suite 终轮 0 fail + REQUIREMENTS/TODO/GOAL-STATE 三翻账 + `13-VALIDATION.md` 三列证据 + **签核前停（C 档第 3 停）记录在案**
- [ ] 凭据纪律：证书/密钥零入仓/入日志/入产物/入文档（SUMMARY 截图脱敏）；每任务独立提交；人工在场点三处有问询记录
