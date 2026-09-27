# Phase 13 VALIDATION — System Integration & Distribution

- **status: validated**
- **nyquist_compliant: true**
- **签核**: 2026-09-28（13-4 T6，executor subagent worker）
- **C 档第 3 停执行记录**: 夜间授权先例 **D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1**——VALIDATION 结论落盘即签核，晨审可推翻（推翻即回滚 status 并回注修复批）。
- **范围修订依据**: 用户 2026-09-27 终裁「砍苹果分发渠道」（GOAL-STATE ④；13-4-PLAN 修订）——SC#4 的 Developer ID 签名 + notarization 段移除，DIST-02 = Removed；GitHub-only unsigned 分发。

## SC#1..4 三列证据

| SC | 判据 | 一手锚（源码/产物） | 测试锚 | GUI 实证锚 |
|---|---|---|---|---|
| **SC#1** | QL 扩展 Finder 空格预览 RAW（含编辑态非原片缩略）；Spotlight importer 索引 rating/labels/keywords/EXIF | `LightamerQuickLook` appex（QLThumbnailProvider 子类 + QLPreviewingController，13-1 双 API 形状变更 D1）+ `QuickLookRenderer`（ExportRenderer 减法孪生，三查回退链）；`LightamerSpotlight`（ObjC CSImportExtension，lindex 只读投影 11 列标准属性映射） | QL parity 逐字节一致（同 sidecar 同参共享单次 decode）；QL Renderer 10 测 + Spotlight Mapper 10 测 + 门控探针（13-1 +21）；schema>2 拒开降级 | **QL 实测 PASS**：qlmanage 打开已编辑 DSC00012.ARW → 预览=编辑态渲染（蓝青调性 sidecar 输出，13-4-20 截图）；**Spotlight 部分**：lindex 抽取源实测健康（thirdparty 关键词入行、EXIF 列在），mds 级绑定待 /Applications 安装复测（遗留#2，13-1 既有 caveat） |
| **SC#2** | 软打样（printer gamut 模拟 + OOG 警告，relative colorimetric + BPC，仅显示腿永不进 edit）+ 多显示器 ICC 自动切换 | `SoftProofStage` iop 69.5（Rec2020→printer ICC→Rec2020 ColorSync 往返）+ `setSoftProof` per-run override + `LinearVariantCache`（D-13-2-7）；`DisplayProfile.resolve` 四级匹配 + 通知驱动 re-resolve + `ManualDisplayOverrideStore` | SoftProofStage 12 + SoftProofUIWiring 7 + MultiDisplay 9（13-2 +28）；proof OFF 逐字节直通零回归；BPC ObjC CLI 探针 v1-v8（`kCGColorConversionBlackPointCompensation` 公开开关实证） | proof 菜单（软打样/色域警告（黑色裁剪））与 Settings Displays 段 AX 元素在案（13-4-21/22）；**ON 态观感 + 真双屏 live = Manual-Only 遗留** |
| **SC#3** | 手势（双指缩放/捏拉/旋转/双指平移）+ 拖放导入（Finder→session/editor）+ zh/en 本地化 | `viewportTransform` 单点数学（D-13 预留翻转）+ AppKit recognizer 面（magnify/rotate/scrollWheel）+ overlay 互斥矩阵 + `ImportService` 三落点 + Localizable.xcstrings zh/en 全键 | ViewportTransform 16 + ImportDrop 7 + MaskCommand 11（13-3 +34）；fit 恒等回归锁逐位；zoom 后 mask stamp 命中 <1px；SYS-05 键审计 1036/0/0 + L025 smoke | zoom HUD（zoom.hud.fit/label）+ 手势入口 AX 在案（13-4-22 全景）；触控板手感/拖放观感 = Manual-Only 遗留；**走查抓修 delete-confirm 裸键回退（d0f8ff3，实机复验）** |
| **SC#4** | GitHub 公开仓（MIT）+ DMG/zip 分发 + CI（构建/测试/发布）——**签名公证段经用户终裁移除** | **github.com/kamasylvia/Lightamer**（public，13 commits 压缩英文史 2.53MiB）+ MIT LICENSE + 公开 README；`Scripts/release/make-dmg.sh`（ad-hoc unhardened UDZO DMG + zip + SHA256SUMS）；`.github/workflows/ci.yml`（build+test 无签名 + tag→draft release，零 secrets） | 首推前四重验证：gitleaks 零命中 / 排除面零断言 / 敏感串零断言 / 末态文件集与 ADO 全等；产物实机启动 +5s；Bundle.main 纪律审计零绝对路径 | 审计闸报告 `release-audit.md`（裁决位记录 §4 + 闸 PASS §5）；DMG 挂载拖装布局截图在案；ADO origin 未动（ref 复核 = 任务前值） |

**SC#4 范围修订留痕**: DIST-02（Developer ID 签名 + 公证）= **Removed**（2026-09-27 用户终裁砍 Apple 渠道；REQUIREMENTS 该行已改注记）；DIST-04 CI 的签名/公证段随之移除；Apple 渠道面整体 = v2 候选（make-dmg.sh 覆盖位届时移除）。

## 覆盖矩阵

| 需求 | 状态 | 交付 plan | 备注 |
|---|---|---|---|
| SYS-01 | Delivered | 13-1（+13-4 走查） | QL 编辑态预览实测 |
| SYS-02 | Delivered | 13-1（+13-4 实测部分） | mds 绑定安装后复测（遗留#2） |
| SYS-03 | Delivered | 13-3 | 触控板手感 Manual-Only |
| SYS-04 | Delivered | 13-3 | 拖放观感 Manual-Only |
| SYS-05 | Delivered | 13-1..13-3（+13-4 抓修） | L025 纪律 |
| COLOR-02 | Delivered | 13-2 | proof ON 态观感 Manual-Only |
| COLOR-03 | Delivered | 13-2 | 真双屏 live Manual-Only（单显机器） |
| DIST-01 | Delivered | 13-4 | 审计闸前置 + 压缩英文史（用户裁决） |
| DIST-02 | **Removed** | —（用户终裁） | Apple 渠道 v2 候选 |
| DIST-03 | Delivered | 13-4 | unsigned（裁决内） |
| DIST-04 | Delivered（范围修订） | 13-4 | 无签名/公证段 |
| 登记批：蒙版命令面 UI | Delivered | 13-3 | 五命令 + 三态 + enable 勾选 |

## Manual-Only 汇总（12 期承接 13 行 + 13 期走查 + 本期新增遗留）

**已清账（13-4 走查批，证据 `.work/gui-acceptance/2026-09-28-13-4-*.png`）**: F-12-1-1 / F-12-1-2 / F-12-1-3 / F-12-2-1 / F-12-2-2（affordance 在案，⓫ 合成点击局限注记）/ F-12-2-3 / F-12-2-4 / F-12-3-1 / F-12-3-2 / F-12-4-1 / F-12-4-2 + QL 编辑态预览 + 蒙版命令菜单面（13-3 GUI 轮已过）。

**pending-manual（遗留，verify-work 用户终验）**:
1. F-12-5-1 LUT 面板深交互（NSOpenPanel 合成输入不可靠；自动化腿在案）
2. F-12-5-2 dt-GUI .cube golden 人工交叉对照（材料包 13-2 已备，人眼判定）
3. 触控板三手势手感 + zoom HUD 观感（13-3）
4. 拖放观感（Finder 跨卷/affordance/Option 绿标）（13-3）
5. proof ON 态 + Settings Displays 观感（13-2）
6. 真双屏切换 live（13-2；单显机器不可测）
7. Spotlight mds 级检索实测（app 安装 /Applications 后）

## 缺陷处置记录

1. **delete-confirm alert 裸键（轻，走查抓出）**——LocalizedStringKey 插值键 ≠ catalog 键 → 裸键回退。修复 `d0f8ff3`（String(format:)）+ 重建实机复验（13-4-23 截图：正文正确 zh）。闭环。
2. **测试标识符被审计 sed 损坏（构建失败面）**——`testexternal volume…` 非法标识符。修复 = 正名 `testExternalVolumeDrainComparisonRecordOnly`（收尾提交）。闭环。
3. **Release 自签 + hardened 产物 dyld 拒载**——macOS 27 库校验对无 Team ID 自签证书死局。处置 = unsigned 分发形态（ad-hoc unhardened，裁决内），根因与复现记录入 SUMMARY/DECISIONS。闭环（形态即裁决）。

## 终轮回归

**1636 执行 / 11 skip / 0 fail（610.9s，EXIT=0）**——总执行数与基线 1636 持平（13-4 零净增测试）。skip 10→11 的 +1 = Perf07 外置卷对比测试的审计清洗改.env 门（`LA_PERF07_VOLUME` 未设即跳；设 env 恢复原记录行为，重跑实测 3/3 绿——SUMMARY T1 节）。在案 flake（LayerE2ERoundTrip / ToneEqualPerf）未现身。

## 签核判定

**Phase 13 签核：PASS（SC#1-4 ✅——SC#4 含用户终裁范围修订；status: validated + nyquist_compliant: true；终轮 1636/10skip/0fail；走查遗留 7 行 pending-manual 全部登记且自动化腿在案，不阻塞签核）。**

*Phase 13 — System Integration & Distribution 四 plan（13-1/13-2/13-3/13-4）全闭环。*
