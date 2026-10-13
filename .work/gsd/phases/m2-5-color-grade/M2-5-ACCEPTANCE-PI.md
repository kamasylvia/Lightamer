# M2-5-ACCEPTANCE-PI — 「调色」回溯二次验收报告（PI 独立）

> 验收员：PI / 日期：2026-10-10 / HEAD：`0f6bdcd7` / 方法：正本亲读 + 上一轮抽查点独立重验（file:line、git/grep 机检、定向双类复跑）。

## 结论头

**PASS / 0 error + 1 minor**

- M2-5 三 plan 交付面经独立复核全部成立；抽查点 1–5 逐项亲证，无实质分歧。
- 唯一新发现 = M2-5-1 ACESccInModule 注释异字（minor，零语义影响，与 omp R2 同见）。
- 定向复跑：`GradeCatalogTests` 15/0/0 + `LutLibraryRecursionTests` 16/1/0，0 fail。

## 抽查点证据

### 1. GradeCatalog 18 目录注册表 + V50Order 十位 + ACEScc envelope（读码）

- `NodeOwnershipCatalog.swift:145-267` 前 18 行顺序与 M2-5-1 SUMMARY 七件终位表一致（cat02WhiteBalance/exposure/contrast/white/black/shadows/highlights/curve/hls/saturation/vibrance/colorWheel/lmt/tint/clarity/sharpen/halation/filmGrain）；第 19 行 `filmPlacement`（M3-3-02）、第 20 行 `colormatch`（M5-1-01）为 M2-5 后演进，不记账。
- `defaultLook` 三 entry 仍在 `NodeOwnershipCatalog.swift:305-317`（+1.5/+15/1.3），唯一来源未变。
- V50Order 十位确认：`LightamerCore/Sources/Foundation/V50Order.swift:82-83` acesccIn 20.5；:158 colorWheels 41.0；:165 cat02WhiteBalance 41.4；:171 contrast 41.6；:176 white 41.8；:181 black 41.95；:189 saturation 42.2；:190 tint 42.4；:191 hls 42.6；:248 acesccOut 69.9。后演进行 `filmPlacement` 20.8（:86）、`colormatch` 36.5（:202）已标注。
- `ACESccInModule.swift:124-141`：`needsEnvelope` 走 `GradeCatalog.item(opName:)` 查询面；`wrap` 首尾包夹；`install()` 注入 `LayerCompositeSeam.acesccEnvelope`（Core 不可 import IOP 的合法缝）。

### 2. LutLibraryStore 键升级 + shared holder + 切根（读码）

- 键 = 根相对 POSIX 路径：`LutLibraryStore.swift:192-193` `installed`/`parsed` 字典键；`adopt(data:relativePath:)`（:260）以 relativePath 写入；根下文件 key 退化为文件名（兼容旧行语义）。
- 旧档 fallback：`resolvedKey(for:)`（:355-365）= 精确命中 → 唯一尾段匹配 → 歧义 nil；`lut(named:)` nil = 缺席（:400-405），缺席走 blit identity。
- shared holder：`LutLibraryStore.swift:105-109` `private static var sharedInstance` + NSLock；getter 锁内读（:112-117）；`replaceShared(_:)` 原子换（:120-124）；`SharedForwardingResolver`（:127-134）长寿命转发；`Registry.swift:421` 注册行消费 `sharedResolver`。
- 切根：`validateRoot`（:155-164）= isDirectory + 写探针（`.lightamer-lut-probe-<uuid>` 即建即删），注释 :153-154 明载不建 bookmark。
- 递归收录：`rescan()`（:222-258）用 `enumerator(at:)` + `.skipsHiddenFiles`；`.cube` 过滤天然跳过 `registry.json`。

### 3. 内置 LUT 许可红线（机检）

- `Resources/LUTs/` = 42 项（40 `.cube` + LICENSE + NOTICE，`ls | wc -l` 实测）。
- 40/40 全部含 `LUT_3D_SIZE 65`：`rg -L "LUT_3D_SIZE 65" Resources/LUTs/*.cube | wc -l` = 40（即零脱漏）。
- 零 Alcedo 字节：`rg -F "D:\\Projects" Resources/LUTs/*.cube` = 0 命中；`rg -i -F "alcedo" Resources/LUTs/*.cube` = 0 命中；BW 片 `Kodak_5222.cube` 样本 RGB 三列相等（head/tail/mid 抽查）。
- LICENSE 头 = `MIT License / Copyright (c) 2026 Jan Lohse`；NOTICE 载上游 URL、v0.18.2、commit SHA `42f4f3f…ce5f`、65³/BW 2302 两偏差、零 GPL 声明。

### 4. 定向测试复跑（独立 derivedDataPath /tmp/la-retro-dd-pi）

- `--bundle App GradeCatalogTests` → `BUNDLE|App|15/0/0|peakRSS=200MB|0s` EXIT=0。
- `--bundle IOPParity LutLibraryRecursionTests` → `BUNDLE|IOPParity|16/1/0|peakRSS=470MB|50s` EXIT=0；1 skip = 万文件探针环境门控，与首验/R2 逐值一致。
- BUNDLE-MAP 对账：`GradeCatalogTests.swift` APP 15（`M2-4-0-BUNDLE-MAP.txt:243`）、`LutLibraryRecursionTests.swift` IOPP 16（:106）与复跑计数精确一致。

### 5. seeder + 键拼写机检

- folderReference：`Project.swift:179` `.folderReference(path: "Resources/LUTs")`。
- 键单源：`"lut.library.root"` 全仓唯一字面定义 = `LutLibraryStore.swift:145`；消费点 `LutLibraryStore.swift:196` + `SettingsPagesTests.swift:234` 拼写断言。

## 分歧项

- **实质分歧：无**。三 plan PASS 结论、测试计数链、许可门 MIT 结论、键语义，本批独立亲证全部成立。
- **口径注记（非分歧）**：
  1. HEAD `0f6bdcd7` 下 `GradeCatalog.items` 已增至 20 行（M2-5 的 18 行 + M3-3-02 `filmPlacement` + M5-1-01 `colormatch`），`V50Order` 同步增至 106 行；后两行属 M2-5 之后演进，M2-5 交付面 18 行/十位不受影晌，不记账。
  2. omp R2 已提的 `ACESccInModule.swift:118` 注释异字「`boxes and铸 a fresh`」仍在位；本批独立确认，性质同前（minor，零语义影响）。
  3. omp R2 注记的 `GradeCatalogTests` 方法名含 `Eighteen`/`Fourteen` 字面问题在 HEAD 下未复见（当前方法名未在抽查中命中该形态），可能已后续演进改名或不在当前 15 法范围内；不构成本批分歧。

## FAIL 明细与可修性

无。

---

只读纪律：除本报告外未修改/删除仓库文件；测试未触发 GUI 宿主残留；`git status` 未见本批新变更。

PI-VERDICT: PASS
