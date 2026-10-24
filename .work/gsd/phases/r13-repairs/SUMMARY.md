# R13 修复批 SUMMARY（双流）

> 2026-10-24。基线 HEAD = `88bdb9fb`（图库批收口），起跑 = r12/lumen-culling 双验收挂账。
> 执行 = zcode executor 单人批；红线携带：FIX2③（LibraryProjectController 零 diff）/封存面/
> xcstrings D6 文本级块编辑/LocalizationValue 禁形/L057/tuist generate 免触发（未新增测试文件登记）。

## 流一：Link 导入四连零行（lumen-culling omp major-1）——归因不可复现 + 观测性补洞 + 回归钉死

**结论：HEAD 上整链健康，omp 表型不可复现；唯一结构性缺口 = 逐文件吞错无日志（omp 报告自列首要嫌疑），已补；行为由两个 integration 测试钉死。**

- **静态全链复导**（`ImportService.executeLink → ImageLinker.record → LibraryStore.insertImage →
  ExifSearchIndexer.fillMetadata → 批尾 rebuildFTS`）：insertImage 为 mode 无关共享缝（Copy 同缝 8/8）；
  `ImageLinker.record` 不 throw；fillMetadata 对不可读文件返回 false 不 throw；迁移面全 additive
  （v1→v6 逐臂核）；`removeImage(id:)` 生产零调用点；`create()` 拒绝已存在文件、`open()` 无重建臂
  ——**代码面不存在「行先插入后被删」的路径**。
- **AI-ask 反证**：`runImport` 的 AI ask 出现 = `newImageIDs` 非空 = `outcome.imported > 0` = 行曾提交。
  omp 流程描述（AI ask 出现过）与「零行」在代码面互斥，进一步指向环境型一次性因素。
- **实证复现 ×2（全绿）**：
  1. DEBUG 探针 `-la_editor_probe /tmp/r13-link/fx`（8 张合成 TIFF）：8/8 行、网格达、编辑器逐张
     loaded/rendered（`evidence/gui-probe-link-import.log`）。
  2. **完整 GUI sheet 流（AX 驱动，与 omp 同配方）**：新建项目（保存面板）→ ⌘I → 选 fx 文件夹 →
     「链接」段 → 导入 → AI ask 出现 → 暂不 → 退出 → `sqlite3 COUNT(*) = 8`（kind1 volume-relative
     逐行正确）。截图 = `evidence/gui-import-dialog-link.png` / `gui-sheet-flow-8rows.png`。
- **修复（`d2bcaf06`）**：`ImportService.importFolder` 逐文件 `catch` 不再静默——os_log error
  （mode + 源路径 + 底层 error，category `import`）。此后任何环境变体下的 link 腿 typed 失败必留
  Console 痕迹（omp 表型不可能再现为「无日志」）。
- **回归（同 commit）**：`ImportServiceTests` +2（Library bundle 13/0/0 全绿）：
  - `testLinkImportTiffThroughDoubleOnMaskLandsRowsAndAIPrecondition`——omp fx 形（8 TIFF、双开掩码）
    → 8/8 行、全 kind1、逐行 `ImageLinker.resolve` 命中原文件、AI-tail 前置查询返回全集；
  - `testLinkImportAfterCopyBatchAddsRowsWithoutDisturbingCopyRows`——omp 会话序列（先 Copy 8/8 再
    Link 同源）→ Link 批净增 8 行（共 16）、Copy 行 kind0 不动、AI-tail 前置恰见 Link delta。
- **红线注记**：omp 报告的另一嫌疑点（`runImport` 入口 guard 静默 return：`importProgress != nil`
  卡死场景）位于 FIX2③ 冻结的 `LibraryProjectController.swift`，零 diff 红线下不加日志——若omp
  表型复发，Core 侧新日志 + watchdog 日志联合可定位（DECISIONS §2）。

## 流二：F-2 显式形全族转换（账面 27 处 → 实抓 46 处 / 21 文件）——`b0690452`

- **花名册扩容（实抓为账面 1.7 倍）**：单行扫描 28 处 + 宽版式重扫
  （`String(\n localized: "…\(x)"` 布局）再 +18 处 = **46 处**；全部为「格式串带参数形」，
  零「有限枚举形」（r12 gamma 已由 `856f2396 fix(r3)` 先修，任务书信息滞后）。分类逐处核过：
  `defaultValue:` 内插值 / 静态键 + 字符串拼接（AIMaskEditing:390 等 5 处）为合法形不转。
- **转换形**：`String(format: String(localized: "静态键"), args)`——目录键已全部以 `%lld/%@`
  形在册（29+12 键逐一机检），**键值零迁移**；46/46 全清（宽版式扫描机检零残留）。
- **真 bug 顺带修复**：`mcp_launcher_launch_failed` 只以裸键在册（%@ 在值内）→ 运行时键
  `…failed %@` 查表 MISS = 启动失败提示恒渲染裸键——转换后指向裸键，正确渲染「启动失败：<原因>」。
- **xcstrings diff = 纯删三块（51 行纯删除）**：三个孤儿裸键孪生
  （`edr_headroom_label` / `settings_displays_overridden` / `softproof_active_label`，值与 `%@`
  孪生逐字节相同，转换后失去唯一消费者）。文本级块编辑，D6 混合格式约束守住（其余 2032 键字节不动）。
- **验证**：
  - `zh-audit --check` **PASS**（1720 source keys / 2035 catalog keys / specifier 深检 0 失配）
    + `--self-test` **PASS**（V17 golden 八例）；
  - build-for-testing 全 target 绿；
  - **渲染抽验**：①Settings LCR 页真机 AX 读出 `语义 · 512 维 · Apache-2.0 · 88 MB`（tier_detail +
    dim_semantic 两键 zh 实渲染）；②bundle 直载渲染机 8 键（lut_rescan/catalog_reconcile/
    import_partial/skin_yaw/mcp_launch_failed/burst_index/export_targets/stack_members）格式替换
    正确零裸键（DECISIONS §5 注：bundle 机 locale 强制 zh 未生效，读数为 en 表——en/zh 值域由
    zh-audit zh-completeness + 目录 dump 双背书）。

## 测试与对账

- 定向轮：Library bundle `ImportServiceTests` 13/0/0（含 +2 新测试）。
- 全套 `--all` 一轮（guard 后 nohup，锁纪律同前）：日志 `all-runs/all-r1.log`，结果见文末追记。
- 基线 `4204/41/0`（`88bdb9fb` 收口轮）；本批 ΔN = **+2**（Link 回归测试），预期 `4206/41/0`。

## 文档同步

- 本文件 + `DECISIONS.md` 同批落盘；issues：#2（Link 导入零行挂账转正）、#3（F-2 家族转换）。

---

## 追记：全套 --all 结果（`all-runs/all-r1.log`，2226s，零 MEMFAIL，exit OK）

| bundle | 本轮 | 峰值 RSS |
|---|---|---|
| IOP | 771/5/0 | 4777MB |
| IOPParity | 478/6/0 | 3338MB |
| Layers | 502/6/0 | 802MB |
| Library | 778/4/0 | 980MB |
| Sessions | 285/9/0 | 1168MB |
| Export | 385/5/0 | 3707MB |
| App | 1007/6/0 | 2581MB |
| **TOTAL** | **4206/41/0** | 2226s |

- 对账：基线 `4204/41/0`（`88bdb9fb` 收口轮）+ ΔN **2**（Link 回归测试 ×2，Library bundle
  742→778 的其余增量属 lumen 批已入基线后的批间差，与 r12→收口轮的批间漂移一致）= **4206 精确**；
  skip 41 逐值一致；七 bundle 计数向量全 0 failed；峰值 RSS 全在 8G 门内。
- git 收口：tracked 零残留（`git status --porcelain` 仅 .work/gsd 内部产物）。
