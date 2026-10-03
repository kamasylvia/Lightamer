# M2-10-01 ACCEPTANCE — 模型资产管线（清单/锁定/下载/内置打包/转换 spike）

> 验收 subagent（零共享上下文，实测核验不轻信）。验收对象 = 四提交
> `2d897ad` / `6a7e81e` / `318a473` / `ec7d9dc`（HEAD `ec7d9dc`，未 push）。
> 正本输入 = PLAN（含 checker 回注 E1/E4）+ SUMMARY + DECISIONS + SPIKE。
> 验收日期 2026-10-03。

## 结论

**PASS / 0 error + 1 minor(已修) + 1 observation** —— AC 8/8 全过；全套独立
复跑单轮干净绿 `TOTAL|2718/16/0|938s EXIT=0`；spike 证据链复核成立。

## 全套独立复跑（对账 2718/16/0）

`caffeinate -dis xcodebuild build-for-testing` 重建（DerivedData 容器
`Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`，HEAD `ec7d9dc`）→
`caffeinate -dis Scripts/test-direct.sh --all`：

| bundle | 本轮 | 执行批申报 | 判定 |
|---|---|---|---|
| IOP | 467/1/0（peak 6554MB） | 467/1/0 | 零漂移 |
| IOPParity | 362/3/0（5983MB） | 362/3/0（5989MB） | 零漂移（RSS 方差内） |
| Layers | 298/3/0（1050MB） | 298/3/0 | 零漂移 |
| Library | 462/4/0（595MB） | 462/4/0（+25） | 零漂移 |
| Sessions | 279/4/0（1644MB） | 279/4/0 | 零漂移 |
| Export | 338/1/0（5957MB） | 338/1/0 | 零漂移（红线门） |
| App | 512/0/0（1305MB） | 512/0/0（复跑账） | 零漂移，**一轮过** |
| **TOTAL** | **2718/16/0，938s，EXIT=0** | 2718/16/0 | **精确对账** |

- 对账：2693（M2-9 签核基线）+ 25（CatalogTests 13 + StoreTests 12，
  BUNDLE-MAP :394-395 行值逐一对上）= 2718 ✓；skip 16 = 基线 16（资源门
  用例在模型在场环境全激活、零新增 skip）✓。
- **SidecarV5 ANE flake 本轮未复现**（App 512/0/0 单轮干净）——执行批
  `TOTAL|2718/16/1` 的隔离复跑口径无需启用，终账 2718/16/0 由本轮直接亲证。
- 零 MEMFAIL：最大 IOP 6554MB < 8192 门。

## 逐 commit 边界（纪律 8）

| commit | 文件集 | 判定 |
|---|---|---|
| T1 `2d897ad` | Catalog/Digests/Locator + CatalogTests + Project.swift + .gitignore + .keep + BUNDLE-MAP（3 行） | == 申报（T4 接线提前 = DECISIONS §5.1 在案） |
| T3 `6a7e81e` | Store + StoreTests + Project.swift + BUNDLE-MAP（1 行） | == 申报 |
| T2 `318a473` | 脚本四件 + SPIKE + Digests 重写 + Store 修正 + CatalogTests 改造 | == 申报（§4/§5.3 在案） |
| T4 `ec7d9dc` | SUMMARY/DECISIONS/GOAL-STATE/LESSONS | == 申报 |

四提交合计 == front-matter files_modified 全量，**零越界**。工作区滞留
（IMG_3061..3063.ARW、gui-acceptance 遗留）= DECISIONS §10 申报的非本批文件，
未触碰。

## 机检亲跑记录

1. **体积红线**：`git ls-files Resources/AIModels/` = 仅 `.keep`；
   `git check-ignore Resources/AIModels/test.mlpackage` 命中 `.gitignore:53`；
   盘上产物（chinese-clip 192M + general 2.4M）零跟踪；digests 文件 3,972 B
   小文本；仓内 >1MB 文件全为既有 fixtures（非本批）。
2. **digest 独立真算**（shasum 手搓 canonical tree hash，不经脚本不经
   Swift）：img `f3edaccb…77c7`/92,558,991B、txt `aaa9fae5…4c32`/108,474,128B、
   vocab `45bbac6b…b91c`/109,540B、general `2f4838ec…7a21`/2,494,268B——
   与 `ModelAssetDigests.generated.swift` 四组全对（Python/Swift/验收侧
   三方同构互证）。
3. **fail-closed**：digests 文件 release 三档 `= nil`；StoreTests
   `testDigestUnpublishedFailClosed`（status 面 + typed 拒绝 + tmp 不建）
   与 CatalogTests `testReleaseDigestsUnpublishedFailClosed` 全绿。
4. **E4 双证独立复核**：读 HF 缓存 `config.json` →
   `vision_config.image_size = 224, patch_size = 16`；
   `preprocessor_config.json` → `{height:224, width:224}`——SPIKE ⓪ 与
   Catalog `inputSize = 224` 实证成立；grep Core/App 源码零 CLIP-256 误写
  （命中全为 `sha256Hex` 标识符）；转换脚本带 E4 守卫（config 值与
   `--input-size` 不符即 SystemExit）。
5. **打包探针**：构建产物
   `Lightamer.app/Contents/Resources/AIModels/` = 两档 profile 目录 194MB
   在场——folder reference 随 build 打包实证（`.keep` 兜底形态由
   gitignore 机检 + 空目录构建路径覆盖）。
6. **登记闭环**：Project.swift :184 folderReference（仓根 E1）+ :528-529
   两测试文件；BUNDLE-MAP :393-395 增行；`git grep` 双命中成立。
7. **L039 双斜杠修复亲验**：复跑宿主进程命令行实测含
   `Debug//Lightamer.app` 双斜杠形态；`ModelAssetStore.artifactTreeEntries`
   `collapse()`（`//+` 正则折叠 + 尾斜杠剥除）prefix/physicalPrefix 双侧
   归一 + lastPathComponent 兜底；资源门激活态测试（真 bundle tree-hash
   互验）在全套中 13/13 绿即端到端实证。LESSONS L039 增补段（:236）在案。

## 重点读码抽查

- **ModelAssetStore**：三源次序固定（Release→hf-mirror→HF）、流式 SHA-256
  （64KB 块，834MB 不整载）、同目录 tmp 晋升（L009）、取消/失败 defer 清
  tmp、corrupt 自愈（(path,size,mtime) memo）、typed error 全失败路径、
  并发重下 typed 拒绝——与 KD-3 逐条对上。
- **URLProtocol mock per-instance 修复**：`wasStopped` = 实例态 + NSLock；
  static 仅 per-test handler/requestOrder（setUpWithError `reset()`）——
  「404 体遗弃触发 stopLoading 毒化后续任务」根因修复成立，无共享态残留。
- **StoreTests 12 法**：真实 CryptoKit SHA-256 digest（E1 零 mock 哈希）、
  请求序断言（`requestHosts()` 数组）、文件系统终态断言（tmp 消失/终名
  在场）——语义断言落在可观测级（E3/E4 满足）。
- **CatalogTests 13 法**：五档位不变量/E4 pins/fail-closed 面/locator 注入
  round-trip/L009 tmp 同父断言——与 AC #1/#2 对上。
- **转换脚本族**：CLIP 腿 E4 守卫 + torch trace（DECISIONS §2 偏离签注）
  + int8 per_block 权重量化 + mask 展开 [1,1,52,52] 图内 `>0.5` + L2 收图；
  ESRGAN 腿三架构纯 torch 重实现（BSD-3/MIT attribution 头注）+
  `--format both` A/B + nn 腿 legacy target + nbits16 后处理——与 SPIKE
  「转换注意」三条一致。
- **revision 双 pin**：Catalog CLIP `36e679e6…` / jina `e10d47f5…` 与
  SPIKE/DECISIONS §7/README REV 变量四方一致。

## Spike 复核节

- ⓪ **E4 = 224²**：双证独立复核成立（见机检 4）。
- ① **CLIP int8 延迟**（image 16.21ms / text 5.59ms ALL 档）：脚本
  benchmark 实现核可（20 次中位、3 次预热）；数字不可零成本复算，脚本
  与记录形态自洽，采信（M2-10-02 golden 将实质消费）。
- ② **A/B 平级**（mlprogram 62.83 vs neuralnetwork 62.35ms，差 0.8%）：
  `--format both` 腿在案可复现；「#2545 未复现 → 裁 mlprogram」推理链与
  DECISIONS §1 签注一致，且留有重转换逃生口（本轮 minor 修复后真正可一键）。
- ③ **质量抽查 inconclusive**：合成线稿平票带 0.32-0.35、脚本如实打印
  全分数（含「汽车」查询 car/cat 同分 0.332 的 max 取先），诚实记账成立；
  真图相对序归 M2-10-02 golden（DECISIONS §9）。

## FINDING

- **minor M-1（已修，验收批 `fix(M2-10-01)`）**：
  `build_default_bundle.sh` digest 重写 pattern 只匹配 `= nil` 哨兵——
  哨兵翻非 nil 后重跑必 `SystemExit`，而 DECISIONS §1 明确预设了
  M2-10-06 重转换场景（「重转换 = 单脚本一次」）。修 = pattern 放宽为整条
  声明值（nil 或既有 literal 至空行，`re.DOTALL`）；回归 = 修复后
  `--skip-convert` 幂等重跑亲测通过（非 nil 哨兵成功重写、SHA-256 同值
  重算一致、diff 仅 generatedAt 时间戳；digests 文件时间戳已还原不入
  commit）。
- **observation O-1**：README「复现步骤」为首跑视角，未提重跑前置——
  M-1 修复后重跑已无前置（幂等），README 无需改；仅记录在案。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | Catalog 五档位不变量 | ✅ CatalogTests 13 法全绿（全套亲证） |
| 2 | Digests fail-closed + bundled 盘上一致 | ✅ typed 拒绝测试绿 + 四组 digest 独立真算全对 |
| 3 | 三源次序 + SHA 不符删 tmp + 晋升终态 + 取消无残留 | ✅ StoreTests 12 法全绿（请求序 + 终态断言） |
| 4 | 脚本可复现 + SPIKE 四项 + bundled 资产在场 | ✅ 链路读码核可 + E4/A-B/质量三项复核成立 + 盘上两档五件套在场（M-1 幂等修复后重转换路径可一键） |
| 5 | 体积红线 | ✅ `git ls-files` 零模型字节 + check-ignore 命中 + .keep 在场（亲跑） |
| 6 | 全套 0 fail | ✅ 独立复跑 `2718/16/0|938s EXIT=0` 单轮干净 |
| 7 | 登记闭环 | ✅ Project.swift + BUNDLE-MAP 双命中（亲跑 git grep） |
| 8 | diff 边界 == 申报文件集 | ✅ 四提交逐 commit 对表零越界（亲跑） |

## 翻账

- REQUIREMENTS `M2AI-01`：追记模型资产半边注记（五档位定型/体积/许可/
  E4=224/mlprogram 裁决），**不翻勾**（嵌入存储/检索/推理消费归
  M2AI-02/03/06/07 后续波）。
- GOAL-STATE：本验收续接点追加。
- 工作区增量：`Scripts/ai-models/build_default_bundle.sh`（M-1 修复，
  fix commit）；`.work/gsd/phases/m2-10-ai-library/M2-10-01-ACCEPTANCE.md`
  （本报告）；REQUIREMENTS/GOAL-STATE 翻账行。**未 push。**
