# Xcode 27 内置 Agent Skills — 获取登记与分诊（2026-10-17）

> 用户指令：获取 Xcode 27 内置 skills。正本 = Apple 随 Xcode 27 分发的 Agent Skills（供 AI coding agent 使用）。

## 来源与落位

- **本机 Xcode**:27.0 (27A266a),`/Volumes/UNITEK/Applications/Xcode.app`。
- **官方导出通道**:`xcrun agent skills export`(Xcode `Contents/Developer/usr/bin/agent`,mcpbridge)。本机实测**挂起**(stdout 空 4+ 分钟,疑似需 Xcode AI 功能登录态或 27.1),已停;**改用社区镜像**:
  - `git@github.com:superagents-lab/xcode27-skills.git` HEAD `6f9ff8d5` (2026-06-09,README 明示 "exported from Xcode 27",内容作者 = Apple)。
  - 浅克隆 → 7 skill 目录拷入 **`.work/xcode27-skills/`**(660KB),`.git/info/exclude` 已排除。
- **许可姿态**:Apple 版权内容,镜像仓明示"无再分发许可"→ **本地参考、不入仓**(公开 MIT 仓零污染);提炼条目须用我们自己的表述改写(同 darktable GPL 纪律,且更严——专有内容连文本引用都只限出处标注)。本地丢失重取:`git clone git@github.com:superagents-lab/xcode27-skills.git`。

## 七 skill 清单与本项目分诊

| Skill | 内容 | Lightamer 相关度 |
|---|---|---|
| **swiftui-specialist** | 结构/数据流/environment/ForEach/modifier/本地化/动画/软废弃 API(9 篇 references,~3500 行) | **高** — 全项目 SwiftUI;`soft-deprecated-apis`/`environment`(938 行)/`dataflow`(756 行)值得全套消读;D-6(macOS 27 SwiftUI framework 缺陷)背景下面层知识有用 |
| **swiftui-whats-new-27** | SDK 27 新 API/行为/废弃:@State wrapper→**macro** 迁移(编译错误三签名+"reordering init 就是错的"陷阱)、reorderable/swipeActions 全容器、toolbar overflow/visibilityPriority、sheet(item:) optional binding、DocumentGroup、AsyncImage 缓存 | **高** — 我们就在 macOS 27 SDK;@State macro 陷阱直接关联存量代码;toolbar/sheet(item:) 族对应 D-4 同族修复面;document-basedapps 参考面(我们自定义项目文件) |
| **test-modernizer** | XCTest↔Swift Testing 迁移与现代特性 | **中** — 全套 XCTest + test-direct.sh 直启;新测试选型参考 |
| **audit-xcode-security-settings** | 安全向构建设置审计(编译警告/static analyzer/Enhanced Security:stack 零初化/pointer auth/HMAC) | **中低** — 已裁 unsigned 分发;纯 Swift 项目面窄;analyzer/warnings 部分可选读 |
| **device-interaction** | iOS 真机/模拟器截图+UI 层级+触控走查 | **低** — 我们 GUI 验收 = macOS 真机 screencapture/cliclick/AX;方法论可对照,平台不同 |
| **uikit-app-modernization** | UIKit 多窗口/scene 生命周期现代化 | **低** — SwiftUI 项目,AppKit 仅桥接缝 |
| **c-bounds-safety** | C `-fbounds-safety` 扩展 | **低** — 纯 Swift 零 C 代码 |

## 使用计划

1. **subagent 参考层**:SwiftUI 相关 plan 的 executor/acceptance prompt 参考节加本地指针(如 `.work/xcode27-skills/swiftui-whats-new-27/references/state-macro.md`),自 M7-6 起按需挂;**不进 AGENTS.md 主约束**(零代码强制面)。
2. **提炼纪律**:不整篇入仓;需要时把适用条目以自写表述落 `research/` 笔记并标注 Apple skill 出处。
3. **官方导出复查**:Xcode 升 27.1 或 AI 登录态就绪后可重试 `xcrun agent skills export` 对账镜像一致性(低优先)。

## 与 M7-6 的关系

M7-6 的 SKILLS-01(skills 文档仓)= **我们自家 CLI/MCP 的 agent 使用文档**(Alcedo parity Block 3),与本次获取的 Apple skill **两回事**;但 swiftui-specialist/whats-new-27 可顺路喂给 M7-6 起 SwiftUI 编码面的 subagent 参考层。
