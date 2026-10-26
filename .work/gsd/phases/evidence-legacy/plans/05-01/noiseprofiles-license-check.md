# noiseprofiles.json 数据文件许可证核对报告（05-08 发布门阻塞项）

- **日期**:2026-10-25
- **核对范围**:dt `data/noiseprofiles.json` → 本仓 `LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json` 的再分发许可状态
- **核对方法**:纯文献/考证(本仓 + 本地 darktable 克隆 git 史逐 commit 追溯 + 文件级一致性机检),无构建/GUI/网络

## 结论

**档位 (b):限制部分解除。**

一句话依据:**GPL-3.0 切换(`4071402d`,2026-10-20)已消解跨许可再分发的主障碍**——上游数据为 GPL-3.0-or-later(darktable 源文件头声明),我方同许可注入完全兼容;**但 NOTICE 尚无该数据文件的 attribution 条目、LICENSE-NOTES.md 状态行仍为「尚未完成」**——两处文档义务补齐后即可解除「核对完成前不对外分发 release」发布门。许可本体层面无任何新障碍(无 incompatible 贡献、无 CLA 约束、无宽松许可特例需要逐条剥离)。

---

## 一、我方在库事实

| 项 | 事实 | 证据 |
|---|---|---|
| 数据文件落位 | `LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json`(2,602,949 字节) | `find` 机检 |
| 引入 commit | `99809210`(2026-09-21,"feat(denoise): add NoiseProfileStore with normalized bundle profiles",Laniakea Kamasylvia) | `git show -s 99809210` |
| 读取代码 | `LightamerIOP/Sources/Common/NoiseProfileStore.swift`(bundle 懒加载 + maker 子串匹配 + ISO 线性插值,直译 dt `noiseprofiles.c` 语义;头注已声明数据来源与转换脚本) | `NoiseProfileStore.swift:7-13` |
| 转换脚本 | `input/golden/fixtures/gen_noise_profiles.py`(构建期规范化:makers/models 字典序、ISO 升序、浮点显式、skip 档保留、version 保留) | `gen_noise_profiles.py:7-13` |
| 既有登记 | `LightamerIOP/Resources/NoiseProfiles/LICENSE-NOTES.md`(05-01 落;数据来源/转换/语义均已登记,**许可核对状态 = 「尚未完成」**) | `LICENSE-NOTES.md:13-20` |
| 根许可面 | `LICENSE` = GPL-3.0 全文;`NOTICE` = 208 行,含 GPL 切换声明 + OpenDRT/aces-core/darktable-spektrafilm/RawLab/Lumen 等 provenance 条目,**无 noiseprofiles 条目** | `grep -in noiseprofile NOTICE` 零命中 |
| 上游基准树 | `dc58cf0ba1`(2026-08-02,LICENSE-NOTES.md:5 登记) | 同上 |

## 二、上游 provenance(darktable 本地克隆逐 commit 追溯)

数据文件的完整历史链(`git log --follow -- data/noiseprofiles.json`):

| commit | 日期 | 作者 | 事件 |
|---|---|---|---|
| `d770677b691` | 2012-11-14 | johannes hanika | denoise profiled 模块首次提交(数据最初随 iop 入库) |
| `eff9e743c61` | 2013-01-04 | johannes hanika | 数据抽出为 `src/common/noiseprofiles.h`("factored the profile data out into a new header") |
| `91b989c7d69` | 2015-02-19 | Tobias Ellinghaus | 迁出为 `data/noiseprofiles.json`("Move noiseprofiles to external JSON file") |
| 2015→2026 | — | 数百社区贡献者 | 逐相机 profile 贡献 commit(如 `bd05eb42d8` ILCE-7RM6、`71ff469fd9` 7D Mark II 等);贡献者署名内嵌于 JSON `comment` 字段("contributed by X") |

**许可声明证据:**

1. dt 仓根 `LICENSE` = **GPL-3.0 全文**(head 逐行核对)。
2. `src/common/noiseprofiles.c` 文件头(数据加载器正本):
   - `Copyright (C) 2015-2023 darktable developers`
   - `version 3 of the License, or (at your option) any later version` → **GPL-3.0-or-later**
3. JSON 数据文件内无独立版权注(纯数据 + `comment` 署名字段)。
4. README.md / CONTRIBUTING.md **无单独 license 节、无 CLA、无 DCO**(ls 机检零命中)——贡献按项目整体许可入库,抽查 commit message(如 `bd05eb42d8`"Contributed by interru")无任何特殊许可声明。

## 三、一致性机检(署名零丢失实证)

以 LICENSE-NOTES.md 登记的基准树 `dc58cf0ba1` 为准,Python JSON 结构化比对:

| 指标 | dt `dc58cf0ba1` 快照 | 我方文件 | 一致 |
|---|---|---|---|
| `"comment"` 条目数 | 433 | 433 | ✓ |
| `"contributed by"` 署名数 | 358 | 358 | ✓ |
| maker/model 集合(433 models) | — | — | ✓ 逐 key 相等 |
| per-model profile 数(合计 8538 档) | — | — | ✓ 逐 model 相等 |

(dtt HEAD 比 `dc58cf0ba1` 新增 4 条 comment 的差异系上游后续 commit,与我方转换基准无关。)

**修改内容** = 纯规范化(键排序/ISO 升序/浮点格式显式化),语义零改动(gen_noise_profiles.py 自校验声明 + 本核对比对佐证)。

## 四、法律形态分析(文献级,非法律意见书)

### ① 数据文件的 GPL「对应源码」界定

JSON 文件在 dt 仓内随程序以 GPL 分发,属**程序组成部分**(bundle 资源),非独立于程序的数据产品。GPL-3.0 §1 "Source Code" = "the preferred form of the work for making modifications to it"——JSON 数据文件本身即 preferred form(可直接编辑),再分发时随程序附带本文件即满足 §6 Corresponding Source 义务。事实性拟合系数(a/b 数值)本身版权厚度低(数据薄保护原则),但结构化编排 + 贡献者注释具表达性;既然我方同为 GPL,**无需依赖「数据薄版权」抗辩,按 GPL 合规路径处理即最稳**,该分析仅作冗余保险记录。

### ② 同许可再分发义务清单(GPL-3.0)

| 义务 | 状态 |
|---|---|
| a. 保留版权与许可声明 | **部分缺**——NOTICE 无 darktable/noiseprofiles attribution 条目(唯一硬缺口);JSON 内 433 条 comment 署名已原样保留 ✓ |
| b. 标注修改(mark modifications) | ✓ 已满足——LICENSE-NOTES.md 记录转换细节 + NoiseProfileStore.swift 头注声明来源;建议 NOTICE 条目中一并声明(见草案) |
| c. 随程序提供对应源码 | ✓ 开源仓本身即满足(GPL-3.0 §6) |
| d. 不得施加额外限制(§10) | ✓ 无 |

### ③ 许可版本兼容方向

- dt 数据侧:GPL-3.0-or-later(源文件头)→ 接受者可选 **3.0**;
- 我方:GPL-3.0(root `LICENSE` + NOTICE 声明,2026-10-20 `4071402d` 切换);
- **单向注入完全兼容**:or-later 授权选择 3.0,我方以 3.0 整体再分发无障碍。原 2026-09-28 时的「MIT 仓收 GPL 数据」障碍已随换牌消解——MIT→GPL 方向曾是问题,GPL→GPL 不是。

### ④ CC0/公有领域贡献者特例

**不存在。** dt git 史逐 commit 审:全部 profile 贡献经 GitHub PR / commit 入 dt 主线,以 dt 整体许可(GPL-3.0-or-later)入库;无 CLA/DCO 文件、无 per-file 宽松声明、commit message 无许可声明;`comment` 字段仅有署名("contributed by X")无许可意图表示。故不存在可剥离的宽松许可子集,整文件按 GPL-3.0-or-later 处理,与我方同许可。

## 五、义务清单(发布门前待办)

1. **NOTICE 补条目**(必做,唯一硬缺口):在 "Third-party provenance" 增补 darktable noiseprofiles attribution 条目(草案见 §六)。
2. **LICENSE-NOTES.md 状态翻账**(必做):`:13-20` 的「尚未完成」状态行更新为本报告结论,引用本报告路径。
3. **维护性义务**(已在位,持续保持):JSON 内 comment 贡献者署名原样保留(后续从 dt 同步新相机 profile 时勿丢);转换脚本与基准树 SHA 登记(CI 化或手工同步时更新 LICENSE-NOTES.md 的树 SHA)。
4. 上述 1-2 完成后,发布门可解除;分发形态(开源 zip/DMG)天然满足源码可获义务,无附加动作。

## 六、NOTICE 修订草案(供 orchestrator 审后落笔)

```markdown
N. darktable noiseprofiles (camera noise profile dataset — Plan 05-01)

   Upstream: darktable data/noiseprofiles.json
   https://github.com/darktable-org/darktable
   Snapshot: tree dc58cf0ba1 (2026-08-02); data lineage since 2012-11
   (commits d770677b691 → eff9e743c61 → 91b989c7d69) with per-camera
   community contributions credited in the file's "comment" fields.
   License: GPL-3.0-or-later (c) 2012-2026 darktable developers and
   profile contributors.

   LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json is normalized
   from the upstream snapshot by input/golden/fixtures/gen_noise_profiles.py
   (alphabetical key ordering, ISO-ascending profiles, explicit float
   formatting; semantic values unchanged). Contributor credits in the
   "comment" fields are preserved verbatim. Modifications are marked per
   GPL-3.0. This file is GPL-3.0 as part of Lightamer.
```

LICENSE-NOTES.md 状态行草案(替换 `:15-17`):

```markdown
- darktable 主体与 `noiseprofiles.json` 数据均为 GPL-3.0-or-later(源文件
  头声明;贡献无 CLA/无宽松许可特例)。本仓 2026-10-20 切 GPL-3.0
  (`4071402d`)后同许可再分发合规;修改 = 规范化转换(已标注)。核对结论
  = 限制部分解除,NOTICE 补 attribution 条目后可对外分发。正本 =
  `.work/gsd/phases/evidence-legacy/plans/05-01/noiseprofiles-license-check.md`。
```

## 七、证据文件索引

- 我方数据文件:`LightamerIOP/Resources/NoiseProfiles/noiseprofiles.json`
- 我方读取代码:`LightamerIOP/Sources/Common/NoiseProfileStore.swift`
- 我方转换脚本:`input/golden/fixtures/gen_noise_profiles.py`
- 我方既有登记:`LightamerIOP/Resources/NoiseProfiles/LICENSE-NOTES.md`
- 我方根许可:`LICENSE` / `NOTICE`(208 行,无 noiseprofiles 条目)
- 我方引入 commit:`99809210`;换牌 commit:`4071402d`;TODO 登记:`.work/TODO.md:220`
- 上游正本:`/Volumes/UNITEK/Documents/Development/darktable/data/noiseprofiles.json`
- 上游许可:`/Volumes/UNITEK/Documents/Development/darktable/LICENSE`(GPL-3.0 全文)+ `src/common/noiseprofiles.c:2-5`(GPL-3.0-or-later 头注)
- 上游 provenance commits:`d770677b691`(2012-11-14)/ `eff9e743c61`(2013-01-04)/ `91b989c7d69`(2015-02-19)/ 基准树 `dc58cf0ba1`(2026-08-02)
