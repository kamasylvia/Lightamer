# Xcode 27 内置 Agent Skills — 获取登记与分诊（2026-10-17）

> 用户指令：获取 Xcode 27 内置 skills。正本 = Apple 随 Xcode 27 分发的 Agent Skills（供 AI coding agent 使用）。
> **⚠️ 2026-10-17 晚更新：用户开启 Xcode External Agent Access 后官方导出成功，正本已切换为本地官方 10-skill 导出；下文镜像节保留为历史记录。**

## 正本（v2，官方本地导出）

- **来源**:`xcrun agent skills export`(前置条件 = Xcode Settings 里 **External Agent Access** 开启——首次挂起即缺此开关,用户开启后 exit 0)。
- **10 skill**(本地 Xcode 27.0 27A266a,与我们构建 SDK 逐字对应):swiftui-specialist / swiftui-whats-new-27 / building-document-based-swiftui-applications / app-intents-specialist / app-intents-whats-new-27 / modernize-tests / adopt-c-bounds-safety / uikit-app-modernization / device-interaction / audit-xcode-security-settings。1.1MB。
- **落位**:①仓内 `.work/xcode27-skills/`(git 排除,登记正本)②全局 `~/.agents/skills/`(拷贝非软链,USB 卷不挂载不影响;跨 agent 共享扫描路径,新会话自动发现)。
- **与镜像的差异**:全部 7 个重叠 skill 内容有 diff;官方为重组版——document-based apps 独立成专门 skill、c-bounds-safety→`adopt-c-bounds-safety`、test-modernizer→`modernize-tests`;镜像多出的 deprecations.md/document-based-apps.md 两 reference 属旧版结构已被官方重组取代。**镜像(`superagents-lab/xcode27-skills@6f9ff8d5`)退役,不再使用。**

## 七 skill 清单与本项目分诊

| Skill | 内容 | Lightamer 相关度 |
|---|---|---|
| **swiftui-specialist** | 结构/数据流/environment/ForEach/modifier/本地化/动画/软废弃 API(9 篇 references,~3500 行) | **高** — 全项目 SwiftUI;`soft-deprecated-apis`/`environment`(938 行)/`dataflow`(756 行)值得全套消读;D-6(macOS 27 SwiftUI framework 缺陷)背景下面层知识有用 |
| **swiftui-whats-new-27** | SDK 27 新 API/行为/废弃:@State wrapper→**macro** 迁移(编译错误三签名+"reordering init 就是错的"陷阱)、reorderable/swipeActions 全容器、toolbar overflow/visibilityPriority、sheet(item:) optional binding、AsyncImage 缓存 | **高** — 我们就在 macOS 27 SDK;@State macro 陷阱直接关联存量代码;toolbar/sheet(item:) 族对应 D-4 同族修复面 |
| **building-document-based-swiftui-applications** | DocumentGroup/文件读写/自动保存/进度上报官方专项(官方重组后新增) | **中低** — 我们用自定义项目文件(.lalb),DocumentGroup 不采用;autosave 性能与文件 URL 直通节有参考价值 |
| **app-intents-specialist / app-intents-whats-new-27** | App Intents 全套(Siri/Shortcuts/Spotlight 集成,官方重组后新增,~3000 行) | **中低** — Lightamer 暂无 App Intents 面;未来 Spotlight/快捷指令集成(MCP CLI 化之后)可回看 |
| **modernize-tests**(原镜像名 test-modernizer) | XCTest↔Swift Testing 迁移与现代特性 | **中** — 全套 XCTest + test-direct.sh 直启;新测试选型参考 |
| **adopt-c-bounds-safety**(原镜像名 c-bounds-safety) | C `-fbounds-safety` 扩展 | **低** — 纯 Swift 零 C 代码 |
| **device-interaction** | iOS 真机/模拟器截图+UI 层级+触控走查 | **低** — 我们 GUI 验收 = macOS 真机 screencapture/cliclick/AX;方法论可对照,平台不同 |
| **uikit-app-modernization** | UIKit 多窗口/scene 生命周期现代化 | **低** — SwiftUI 项目,AppKit 仅桥接缝 |
| **audit-xcode-security-settings** | 安全向构建设置审计(编译警告/static analyzer/Enhanced Security) | **中低** — 已裁 unsigned 分发;纯 Swift 项目面窄;analyzer/warnings 部分可选读 |

## 使用计划

1. **subagent 参考层**:SwiftUI 相关 plan 的 executor/acceptance prompt 参考节加本地指针(全局安装后亦可依赖自动发现),自 M7-6 起按需挂;**不进 AGENTS.md 主约束**(零代码强制面)。
2. **提炼纪律**:不整篇入仓;需要时把适用条目以自写表述落 `research/` 笔记并标注 Apple skill 出处。
3. **升级跟随**:Xcode 升级后重跑 `xcrun agent skills export` 对账本地正本与全局副本(官方导出已验证可用,秒级完成)。

## 历史记录(v1,镜像获取——已被上节取代)

- 官方导出通道首试挂起(缺 External Agent Access);改用社区镜像 `superagents-lab/xcode27-skills`(`6f9ff8d5`,Apple 原作 7 skill)落位并装全局。镜像仓明示"内容作者 = Apple,无再分发许可"。
- **许可姿态(仍适用)**:Apple 版权内容,**本地参考、不入仓**(公开 MIT 仓零污染);提炼条目须用我们自己的表述改写(比 GPL 纪律更严——专有内容连文本引用都只限出处标注)。本地丢失重取:`xcrun agent skills export`(需 External Agent Access 开启)。

## 与 M7-6 的关系

M7-6 的 SKILLS-01(skills 文档仓)= **我们自家 CLI/MCP 的 agent 使用文档**(Alcedo parity Block 3),与本次获取的 Apple skill **两回事**;但 swiftui-specialist/whats-new-27 可顺路喂给 M7-6 起 SwiftUI 编码面的 subagent 参考层。
