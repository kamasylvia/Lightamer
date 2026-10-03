# M2-10-01 SUMMARY — 模型资产管线（清单/锁定/下载/内置打包/转换 spike）

> 执行 worker 收口（2026-10-03 夜）。三个功能提交 + 本收口提交；
> 裁决与偏离正本 = `M2-10-01-DECISIONS.md`；spike 数字正本 =
> `M2-10-01-SPIKE.md`。

## 提交账

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `2d897ad` | ModelAssetCatalog 五档位 + Digests 缝（全 nil 哨兵）+ ModelLocator + CatalogTests 13 法 + 提前接线（.keep/.gitignore/folderReference/LIB 登记，DECISIONS §5.1） |
| T3 | `6a7e81e` | ModelAssetStore 状态机 actor + StoreTests 12 法（URLProtocol mock + 真 SHA-256）；**先于 T2 提交**（DECISIONS §5.2） |
| T2 | `318a473` | 转换脚本族三件 + README + chain-7 全绿执行 + digests 重写（bundled 两档非 nil）+ SPIKE.md + tree-hash 拼写修复（DECISIONS §4/§5.3） |
| T4 | 本提交 | AC 机检 + 终跑对账 + SUMMARY/DECISIONS/GOAL-STATE/LESSONS + diff 边界 |

## 测试数字（基线 2693/16skip/0fail）

- **全套 --all 终跑：`TOTAL|2718/16/1|1098s`**——执行数 = 2693 + 25 精确对账
  （+13 CatalogTests / +12 StoreTests，BUNDLE-MAP 行）；App bundle 内
  `SidecarV5Tests.testWriteLegPersistsOverridesIntoTheSidecarFile` 1 fail =
  **在案环境型 flake**（decode 超时紧邻 ANE `MILCompilerForANE` 编译失败，
  M2-8-2 验收批同形态在案）；隔离复跑 SidecarV5Tests 11/0/0 + **App 全 bundle
  复跑 512/0/0** → 终账 **2718/16/0**。
- 七 bundle 逐值：IOP 467/1/0、IOPParity 362/3/0、Layers 298/3/0、
  Library 462/4/0（+25）、Sessions 279/4/0、Export 338/1/0（红线门零漂移）、
  App 512/0/0（复跑）；peakRSS 最大 IOPParity 5989MB < 8G，零 MEMFAIL。
- 定向轮：CatalogTests 13/0/0（资源门激活态）+ StoreTests 12/0/0。

## 交付物

- **清单**：`ModelAssetCatalog` 五档位（bundled = chinese-clip-vitb16-int8 +
  realesr-general-x4v3-fp16；release = jina-clip-v2-int8 +
  real-esrgan-x4plus-fp16 + drunet-color-fp16，releaseTag `ai-models-v1`）；
  revision 双 pin（CLIP `36e679e6…` / jina `e10d47f5…`）；inputSize 唯一常量源
  （E4 实证 224；SR tile 基准 256）。
- **digest 锁**：bundled 两档非 nil（img 92,558,991B `f3edaccb…` + txt/vocab
  aux；general 2,494,268B `2f4838ec…`）；release 三档 nil = fail-closed；
  Python/Swift 双侧同构 tree-hash 互验通过（真 bundle 上）。
- **Store**：resolve/download/verify/activate actor——三源次序
  （Release→hf-mirror→HF）、流式 SHA-256、同目录 tmp 晋升（L009）、取消清
  tmp、corrupt 自愈、progress 回调（64KB 块）；typed error 全失败路径。
- **内置打包**：`Resources/AIModels/`（仓根，E1）≈193MB——CLIP 双塔
  int8（88+103MB）+ vocab.txt 108KB + general-x4v3 fp16（2.4MB）+ prototypes
  占位；folder reference 随 build 入 app（资源门测试在真 bundle 上验证通过）。
- **脚本族**：`Scripts/ai-models/`（convert_chinese_clip.py /
  convert_real_esrgan.py / build_default_bundle.sh / README.md）——复现链
  chain-7 全绿（12 分钟热）。

## Spike 结论（详见 SPIKE.md）

①E4 输入尺寸 = **224²**（config.json + preprocessor 双证）；②CLIP int8 延迟
image 16.21ms / text 5.59ms（ANE 档，20 次中位）；③x4plus A/B **平级**
（62.83 vs 62.35ms，#2545 未复现）→ 打包格式裁 **mlprogram**；④质量抽查
合成线稿 **inconclusive**（诚实记账）→ 真图相对序归 M2-10-02 golden。

## 阻塞节

无 E3 阻塞。网络直连实测：hf-mirror.com 全程可用（CLIP 权重 753MB 经
mirror）；github.com release 直连可用（x4plus/general 权重）；huggingface.co
与 github.com 首探各一次超时/404 后恢复（重试即过）。测试环境 flake 一宗
（上述 SidecarV5，在案）。

## AC 总表

| # | AC | 结果 |
|---|---|---|
| 1 | Catalog 五档位不变量 | ✅ CatalogTests 13 法（唯一性/bundled 恰二/releaseTag 互斥/许可名/E4 pins） |
| 2 | Digests fail-closed + bundled 盘上一致 | ✅ StoreTests testDigestUnpublishedFailClosed + CatalogTests 资源门激活态互验（真 bundle） |
| 3 | 三源次序 + SHA 不符删 tmp + 晋升终态 + 取消无残留 | ✅ StoreTests（URLProtocol 请求序断言 + 文件系统终态断言） |
| 4 | 脚本可复现 + SPIKE 四项 + bundled 资产在场 | ✅ chain-7 端到端全绿 + Resources/AIModels 五件套 + prototypes 占位 |
| 5 | 体积红线 | ✅ `git ls-files` 零模型字节 + check-ignore 命中 + .keep 在场 |
| 6 | 全套 0 fail | ✅ 2718/16/0（flake 隔离复跑定案，见上） |
| 7 | 登记闭环 | ✅ 两测试文件 × Project.swift + BUNDLE-MAP 双命中（git grep） |
| 8 | diff 边界 == 申报文件集 | ✅ 见下节机检 |

## diff 边界机检（纪律 8）

四提交合计改动 = front-matter 申报集全量（ModelAssetCatalog/Digests/Locator/
Store 四 Core 文件 + 两测试文件 + Project.swift + .gitignore + .keep +
Scripts/ai-models 四件 + SPIKE/SUMMARY/DECISIONS/GOAL-STATE/LESSONS +
BUNDLE-MAP）；`ModelAssetStore.swift`/`ModelAssetCatalogTests.swift` 的 T2 批
功能性改动 = DECISIONS §4/§5.3 申报。零 front-matter 外源码文件。

## 交接（下游 plan 读 DECISIONS §8 消费契约）

M2-10-02：tokenizer 自实现（vocab.txt 随包）+ 4D 展开 mask + mean/std 归一化
契约 + 嵌入 L2 已收图；M2-10-03：prototypes 占位目录；M2-10-06：tile 基准 =
manifest.inputSize=256，格式裁决 mlprogram（§1）；M2-10-07：LCR 下载入口对
digest-nil 档显「待发布」；维护者上架清单 = DECISIONS §6。
