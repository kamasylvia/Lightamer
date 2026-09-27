# 13-4 DECISIONS — 执行期决策

- **D1 GitHub 凭据来源 = 本机既有 gh keyring + SSH，不启用 Infisical 拉取**：`gh auth status` 已登录 kamasylvia（SSH 协议、keyring token），`ssh -T git@github.com` 通。用既有已供凭据避免重复处置私钥材料；Infisical 的 `GITHUB_SSH_PRIVATE_KEY/GITHUB_PAT` 路径保持为文档化回落。raw PAT 全程未接触。
- **D2 公开史形态 = 13 个 Phase 里程碑快照（orphan 新史）**：用户终裁「压缩为英文精炼 commits」的执行解释——每 phase 一条 what+why 正文，保留原始作者日期；既非 695 增量直推也非单点 squash。里程碑边界 = 各 phase 签核/收口 commit（P5 边界取 4cd9a4e，62ae08e 的内容自然落入 P6 快照，无损）。后续公开仓同步 = `format-patch <显式SHA> | git am`（range 会捞进并行 session 的 .work docs commit——实测踩坑一次）。
- **D3 分发构建签名形态 = ad-hoc + hardened OFF（构建期覆盖，不改 Project.swift 默认值）**：实测 Lightamer Dev 自签 + hardened runtime 在 macOS 27 触发 dyld 库校验拒绝（"different Team IDs"，清洁重建不可解；hardened 本服务于已砍的公证面）。`make-dmg.sh` 以 `CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO` 覆盖构建；L011 的 Debug 三件套不受影响。
- **D4 CI runner = `macos-27` 镜像**：macOS 27 部署门要求 27 SDK；Xcode 27 镜像 public preview 在案（2026-07 起，arm64）。风险（Metal toolchain #14548、beta 镜像）登记 SUMMARY 遗留，红了按实况调。
- **D5 CI 测试腿 = 全套 test-direct.sh 不做 skip 白名单**：RAW 样张缺失类测试自带 XCTSkip；GPU/Metal 类在 runner 上的表现由首跑揭示（诚实红优于假绿）。若 runner 固有缺陷 → 届时加定向 skip 并注明 runner 限制。
- **D6 Release draft 而非直发**：tag 触发的 release job 产 Draft——公开发布动作保留给人（C 档精神）。
- **D7 事故自首（ADO origin 误推未遂）**：T4 推送命令缺 cwd 限定，`git push origin main` 在 ADO 仓上下文执行——上传阶段 TaskStop 终止 + `ls-remote` 复核 ref 未动（push 原子性：ref 更新只在完整上传后发生）。整改 = 一切 git push 用 `git -C <repo>` 显式仓路径。LESSONS 候选。
- **D8 审计清洗的工具链连坐**：词级 sed 清洗把 `testUNITEK…` 方法名改成含空格的非法标识符，测试构建失败后才暴露——清洗规则必须排除标识符上下文（正本教训入 commit message；修复 = 显式正名）。
- **D9 走查合成输入的边界**：CGEvent 鼠标对 SwiftUI `alert` 按钮/小尺寸 ⓫ 不可靠（AXPress 或真实点击才生效）；CGEvent 键盘过拼音 IME（文本注入走剪贴板 + ⌘V）；触控板专属手势（magnify/rotate/force）无公开合成路径。证据坐标一律取 AX points（截图是 0.75× 缩放像素，两空间不可混用）。
- **D10 走查临时数据零残留**：走查注入的 keyword/preset/粘贴样本全部当场删除或 `git checkout` 恢复（fixture sidecar/lindex WAL/thumbs 复原；App Support Presets 无 walkthru 残留）——走查证据只留截图。
- **D11 L031 声明维持**：本 plan 无新 Metal kernel 面；`makeRoutedCommandBuffer()` 红线未触。
