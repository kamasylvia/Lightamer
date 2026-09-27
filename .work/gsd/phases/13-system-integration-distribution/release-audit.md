# Release Sensitive-Audit Report（13-4 T1 审计闸）

- **日期**: 2026-09-27（executor subagent worker，plan 13-4 W3）
- **范围**: git 全历史 **695 commits**（`git rev-list --count HEAD`），pack 1.60 GiB
- **触发**: GitHub 公开仓首推前的强制前置闸（D-13-CONTEXT-8②；plan 13-4 内部序 T1 → T5）

## 1. 工具与规则

| 工具 | 版本 | 规则面 |
|---|---|---|
| gitleaks | 8.30.1（Homebrew） | 内置全规则集（token/key/私钥块/通用凭证模式），`--redact` 输出 |
| 人工复核 ① | git grep 全跟踪面 | 内部域名：`*.ts.net` / `qnap` / `dev.azure.com` / `infisical` |
| 人工复核 ② | git grep 全跟踪面 | 绝对路径：`/Volumes/` / `/Users/kamasylvia` |
| 人工复核 ③ | git grep 全跟踪面 | 个人标识面：`kamasylvia`（bundle-id 命名空间之外） |
| 人工复核 ④ | 逐命中目检 | token 模式（AKIA/ghp_/PRIVATE KEY/xox/sk- 等）+ 版权/隐私资产 |

机器可读证据：`release-audit-gitleaks.json`（本目录，redacted）。

## 2. 命中清单与处置

### 2.1 gitleaks 全历史扫描 —— 4 命中，全部 false positive 且全部位于排除面

| # | Rule | 文件 | 定性 | 处置 |
|---|---|---|---|---|
| 1 | generic-api-key | `.work/plans/05-08/adoption/conf/darktablerc` | darktable pwstorage 配置的**键名** `secret=`（值为 keychain 后端名，无凭证值） | 误报；文件在排除面 |
| 2 | generic-api-key | `.work/plans/05-06/adoption/Lightamer-*.ips` | Apple 崩溃报告 `crashReporterKey`（设备匿名化键，非凭证） | 误报；文件在排除面 |
| 3 | generic-api-key | `.work/plans/05-06/adoption/conf/darktablerc` | 同 #1 | 同 #1 |
| 4 | generic-api-key | `.work/plans/05-07/adoption/conf/darktablerc` | 同 #1 | 同 #1 |

### 2.2 内部域名 —— 公开候选树零命中

`*.ts.net` / `qnap` / `dev.azure.com` / `infisical` 在**排除 `.work/` 与 `AGENTS.md` 后的跟踪面零命中**（内部基建名只出现在 `.work/` 流程文档内）。

### 2.3 绝对路径 —— 11 文件命中，全部清洗（本次提交执行）

| 文件 | 性质 | 处置 |
|---|---|---|
| `LightamerCore/Sources/Decode/YiyinExifFormat.swift` | 注释 | → `https://github.com/kamasylvia/yiyin` |
| `LightamerCore/Sources/Foundation/V50Order.swift` | 注释 | → `https://github.com/darktable-org/darktable` |
| `LightamerCore/Sources/Catalog/CatalogRebuilder.swift` | 注释（卷名 UNITEK） | → 泛化措辞 "external archive volume" |
| `LightamerIOP/Sources/Yiyin/BordersModule.swift` | 注释 | → yiyin GitHub URL |
| `LightamerIOP/Sources/Yiyin/YiyinLayout.swift` | 注释 | → yiyin GitHub URL |
| `Scripts/yiyin-logo-convert/main.swift` | 注释 | → yiyin GitHub URL |
| `Scripts/yiyin-ref-harness.mjs` | 注释 + **代码**（createRequire 硬编路径） | 代码改 `YIYIN_ROOT` 环境变量（未设 = 原有 catch 降级路径，行为保持） |
| `Tests/LightamerTests/Perf07MassApplyTests.swift` | **代码**（`/Volumes/UNITEK` 硬编） | 改 `LA_PERF07_VOLUME` 环境变量门 + 双 XCTSkip（未设/卷缺失均跳）——本机复跑设 `export LA_PERF07_VOLUME=/Volumes/UNITEK` 恢复原记录行为 |
| `input/golden/fixtures/gen_noise_profiles.py` | **代码**（DEFAULT_DT 硬编） | 改 `DT_JSON` 环境变量 + 未设即显式退出 |
| `input/golden/regenerate.sh` | **代码**（DT 硬编） | 改 PATH 探测 + 缺失显式报错 |
| `input/golden/manifest.md` | 历史溯源行 | → 泛化措辞（dt commit 行保留） |

清洗后复扫：`/Volumes/|/Users/kamasylvia` 在公开候选树**零残留**（`AGENTS.md` 见 §3 排除面）。

### 2.4 个人标识面 —— 1 类，豁免

- `com.kamasylvia.lightamer.*` bundle-id 命名空间（D-05 **one-way 锁**，Phase 2 定案）：`kamasylvia` = 开发者 GitHub 公开 handle（本仓 owner），个人开源项目以自有 handle 作 bundle-id 命名空间为通行实践。**豁免**。命名空间之外零命中（已 grep 证实）。

### 2.5 版权/隐私资产（人工复核 ④ 追加面）

- `.work/` 内跟踪了 **~1.2 GiB 相机样张**：①raw.pixls.us 等下载的厂商样张（版权）；②开发者个人照片（DSC/IMG 原片，隐私）。**全部在排除面**，不入公开仓。
- 商标面：13 品牌水印 logo + README 商标声明节已在案（Plan 08-2 D-08-CONTEXT-5，README「Trademarks」节）——豁免维持。

## 3. 公开树策略（排除面）

**公开仓内容 = 跟踪树 − `.work/` − `AGENTS.md`**：

| 排除 | 理由 |
|---|---|
| `.work/`（1109 跟踪文件） | ①相机样张版权/隐私（§2.5）；②内部 GSD 流程文档（含内部主机名/本机布局/验收截图人脸等）；③1.6 GiB pack 的体积主体 |
| `AGENTS.md` | 本机 agent 运维文档（GSD 工作流强制/本地路径引用/内部流程），非产品文档；其内的 darktable/yiyin 本地路径引用随排除一并消解 |

保留面：`App/ LightamerCore/ LightamerIOP/ Tests/ Resources/ Scripts/ input/golden + input/cube（小型测试 fixtures）/ Project.swift Tuist.swift .package.resolved .gitignore README.md LICENSE` + 本 plan 新增 `.github/ Scripts/release/`。

## 4. 用户裁决位记录（「全历史 vs squash」问询）

- **plan 期默认**: 全历史推送（D-13-CONTEXT-8②），显式问询待用户答复。
- **用户裁决（2026-09-27 终裁，GOAL-STATE ④ 项 + orchestrator 派工书转达）**: **「commits 压缩后上传 + 全英文」——全历史压缩为英文精炼 commits 后首推**（既非 695 commit 增量直推，也非单点 squash）。
- **执行形态**: 新 orphan 历史按 **Phase 里程碑快照**压缩（P1→P2→P3→P4→P5→P6→P7→P8→P9→P11→P12→P16→P13 ≈ 13 个英文 commit，逐 phase 一条 what+why 正文），末态 = 当前树 + 本 plan 产物。快照逐点套用 §3 排除面 + §2.3 清洗后内容。
- **依据**: 全局 AGENTS.md §2.2「公开仓上传前按逻辑主题压缩，公开历史精炼」+ 用户 2026-09-27 二次确认「砍苹果渠道、只传 GitHub」。ADO origin（私有）保持全历史不动。

## 5. 闸判定

**PASS（附条件，条件已于本次提交兑现）**：
1. gitleaks 4 命中 = 误报且全在排除面 ✅
2. 绝对路径 11 处清洗完毕、复扫零残留 ✅
3. 排除面策略定案（`.work/` + `AGENTS.md` 不入公开树）✅
4. 裁决位已获用户答复并记录（§4）✅

→ **解锁 T2 公开仓操作**（建仓/推送仅走新 GitHub remote；ADO origin 不动）。
