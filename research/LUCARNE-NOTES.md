# Lucarne 调研（2026-10-17，用户给小红书笔记）

> 笔记：「Lightroom 的免费平替」——lucarneapp.com。三问：是否开源 / 可否加入参考项目 / 借鉴意义。

## ① 是否开源：**否（闭源免费软件）**

证据链：
- 官网 lucarneapp.com 全站无源码链接 / license 声明 / 仓库指引；仅 beta 下载（1.6.2 Beta，18.3MB，macOS 26 floor，Apple Silicon）+ Terms of use + Disclaimer。
- WebSearch 无 GitHub 仓库痕迹（"Lucarne" 精确检索零命中；GitHub raw-photo-editor topic 页无此项目）。
- 页脚版权 = **「© 2026 Xxxxxxx Systems」（匿名化的占位名）**——个人/小团队刻意匿名。
- 结论：gratis（免费下载）非 libre（开源）。**无源码可读，GPL/MIT 参考纪律无从谈起。**

## ② 可否加入参考项目：**可以，但只能实机对照形态**

本仓参考项目先例：Alcedo 既有源码参考也有 `/Applications/AlcedoStudio.app` 实机对照。Lucarne 无源码 → 只能走实机对照形态（跑 beta 看行为/UI 面），价值密度低于源码型参考。下载 beta 与实机走查待用户定（第三方 beta 装机由用户手动或明确授权）。

## ③ 借鉴意义：**中等——四条 V2 候选 + 竞争定位价值；零架构级启发**

### 功能面 vs 我方 parity map（docs/parity-checklist.md 136 行）

**Lucarne 有、我方缺（V2 候选）：**
1. **批量套用时 AI 蒙版逐张重找**（"masks included, with AI masks found again on every photo"）——批量 sync/preset 时 AI 选区在新照片上重新推理而非原样搬运。我方 M6-4 分割蒙版在库，批量臂逐张重算未在 map。**真工作流缺口，最值得借鉴的一条。**
2. **Retouch 族（heal / clone / AI removal + loupe 放大镜）**——dt `retouch.c` 同域（我方 key files 列过未交付）；M2AI 推理基建可复用。
3. **导出根 allowlist + MCP read-only 模式 + 无删除面**（"exports only into folders you allow / no way to remove photos"）——MCP 安全面模式，我方 requiresControl/openReadOnly 已有，**export-root allowlist 是补强点，量级小**。
4. **LCP（Adobe 镜头 profile）导入**——复活我方 deferred 的镜头数据面（research STACK「What NOT to Use」曾裁 lensfun-data 只读 XML 路线；LCP 同形态）。

**UX 池（低优先）：** 画拉参考线自动摆正（guides straighten）、⌘K 命令面板、图库地图 + 时间轴浏览、超分三档（Classic/Efficient/High Quality + detail 滑杆，对照 M2AI-09 UX）。

**行为对照（无源码只能看宣传语义）：** 胶片模拟「exposed, developed, printed」物理建模 + 20 胶卷/8 相纸/halation/画幅选择——M8 光谱升维 research 时作行为基准对照点之一。

**我方领先面（竞争定位）：** MCP 深度（32 工具五域 + turn-taking vs 其 demo 约 7 动词单 turn）、CLIP 语义检索（其无）、AI 图库全家桶（打标/评片/出片副本）、全景/HDR 合并、100MP 性能目标、DRT/ACES 显示链、开源本身。**它验证了「macOS 原生 + 端侧 AI + MCP 一等公民」赛道成立（同 niche 免费竞品），也反证我方差异化方向（性能上限 + 语义检索 + 合成族 + 开源）站得住。**

### 处置建议
- AGENTS.md 参考项目节加 Lucarne 条目（**实机对照型，无源码；beta 路径待用户装机后挂**）。
- 四条 V2 候选入 `research/UPSTREAM-QUEUE.md` 池（编号 UQ-LC*）。
- 源码型参考清单**不加**（无从读起）。
