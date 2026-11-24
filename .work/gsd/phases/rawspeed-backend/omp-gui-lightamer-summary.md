# GUI timing — Lightamer（CIRAW 路径）lane 总结

- 构建：HEAD `beaac01a947246ad674b0e5118c345b147e30ea8`，Release adhoc（`xcodebuild` + `make-release-direct-launchable.sh --skip-build`，571 s）；二进制 SHA256 `c3293ec7…a3e84f21`。
- 隔离：`$G/home`（HOME+CFFIXED_USER_HOME）；真实 `~/Library/.../Library.lalb` mtime 未变（1793619957）。
- 样张：7RM5 ARW 86MB / GFX100S RAF 210MB / Z8 NEF 61MB（CC0 硬链接）。A7R5 可解（CIRAW v8）。

## 关键数字

| 指标 | 7RM5 | GFX100S | Z8 |
|---|---|---|---|
| M1 冷：launch→首图（n=5 中位） | **2.13 s** | **2.40 s** | **1.82 s** |
| 其中 点击→preview（中位） | 1.57 s | 1.71 s | 1.33 s |
| M1 热 | 未取得（脚本缺陷，无效值作废） | — | — |
| M2 编辑（曝光；输入平面复用 + 30 IOP 平面） | 快拖 live 0.11 s / commit 0.41 s（−44% vs spike 738 ms）；慢拖总 1.39 s、松手后 ≈0.67 s（n=2） | 未测 | 未测 |
| M3a 批量粘贴 | 默认项目面**无批量粘贴**；Core/MCP 存在（sidecar-only）；实测未取得（会话成员/503） | | |
| M3b 缩略图刷新 | legacy 面：stale 标记 + 按需队列（2 并发，tier B = 全尺寸 decode）；项目面：编辑不失效（pristine 腿） | | |

## 判定句

CIRAW 批量修图**不需要长时间挂起**（粘贴 sidecar-only；编辑=输入平面复用+30 平面链，快拖 commit 0.41 s）。长等待风险 = **每张首次全尺寸解码**（打开 1.82–2.40 s/张，其中 decode+CI render 占 45–62%；360 px 缩略图也做全尺寸 decode → 强制刷新 10k ≈ 1.4–2.4 h 线性模型）。架构/代码面另有两条：项目面**无批量粘贴路由**、项目面**编辑不刷新缩略图**；再加每次编辑 30 平面全 miss 的过度重渲。

## 删除与审计

- `$G/lightamer/` 已删（app 583MB + 10k 硬链接 + 隔离 HOME + 帧）；进程清零；`df` 38GB avail。
- 偏好 `com.kamasylvia.lightamer` 键已清（空域壳 `{}` 残留，无键）。
- **错误**：清理早于审计，`snap/` 快照随目录删除 → 「运行前不存在条目」的逐条比对无法完成；现有系统容器类条目未动并上报。

## 自审

- omp 独立自审结论头：`PASS / 4 error + 7 minor`。4 error（hot CSV 的 0.31 引用、spike M2 机制误判、加速倍数丢慢拖、解码占比 85–100%）+ 7 minor 已全部修正（报告 §0/§4/§5/§8/§9 与图片组件表）；修正明细见 `evidence/gui/lightamer-SELFREVIEW.md`。

## 未验项

M1 热（脚本缺陷）；M2 n=2；M3a/M3b/M3c 未实测——已定位 10k 目录会话的索引是渐进的（20.9 s 只到部分成员，40 s 时 img_00004 仍 notSessionMember）+ MCP 会话上限 4（503）；项目面 10k 导入未试。
