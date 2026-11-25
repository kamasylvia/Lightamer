# HISTORY-COMPAT — darktable/darktamer 编辑历史兼容调研（只读 lane）

> 日期 2026-11-25。基线 `dt-master` = `…/Lightamer-rust-spike/refs/dt-master` @ `679d594f5d`（2026-11-22）。
> 口径：只读源码 + git diff；零构建、零测试、零 commit。长表见 `HISTORY-COMPAT-TABLES.md`。
> darktamer 差异经 `git -C …/darktable diff github/master..HEAD` 核对：历史格式零改动（iop 顺序表 +11 行：skinmask 进 5 表，reshape/skinsmooth 只进 3 非 jpg 表，Table 7）。

## §0 One page（11 行）

- 历史两处存：DB（`library.db` 的 `history`/`masks_history`/`module_order`/`history_hash` 表 + `images.history_end`）与原图旁 `<file>[ _NN].xmp`。
- 写时机三档（pref `write_sidecar_files`，默认 `on import`）：never 只存 DB；after edit 首改后建 XMP；on import 建 XMP 并随改随写。
- XMP 历史 = `darktable:history` 结构数组（每条 10 属性：num/operation/enabled/modversion/params/multi 三件/blendop 两件）+ `history_end` + `iop_order_version/list` + `masks_history` + 3 个 hash + `xmp_version`=5。
- 参数打包通用规则：整块 POD 内存镜像（`params_size` 字节）→ DB BLOB → XMP hex 直写（>100B 且 pref 允许则 zlib+base64 加 `gz` 前缀）。无逐字段、无端序处理、无 packed。
- Rust 必复刻 6 件事：① LE 下 C 自然对齐布局逐模块复刻；② `modversion`→`legacy_params` 链式迁移；③ `multi_priority` 实例键；④ iop 顺序表（V50/V50_JPG 默认）+ custom 文本反序列化；⑤ blend v15 整块 + 旧版迁移链；⑥ 写回保留未知 XMP key。
- 版本判别：`modversion==version() && len==params_size` 才 memcpy，否则迁移；失败丢该条。
- 未知模块：XMP→DB 照存不校验；DB→内存跳过该条（打印日志，不断链）；`modversion` 超前用默认参数保留条目。
- 未知 XMP key：读忽略、写保留（decode→删已知→叠加 DB→encode）。Lightamer 独有功能可安全存同一份历史，但须用自有命名空间 + 自有 DB 列/表。
- 冲突：无自动裁决。crawler 以 `write_timestamp` vs XMP mtime（容差 2s）检出，用户四选一（XMP→DB / DB→XMP / 新盖旧 / 旧盖新）。

## §1 Q1 — Where history lives

- XMP 放原图旁：`dt_image_full_path`（common/image.c:416）+ 版本后缀 `_%02d`（:930-951）+ `.xmp`（写盘 :3486-3488；发现 :2026-2090 支持 `file.ext.xmp`、`file_NN.ext.xmp`）。无集中目录。
- 三档 pref：`write_sidecar_files`（data/darktableconfig.xml.in:372-384）→ `dt_image_get_xmp_mode`（image.c:360-389）→ `DT_WRITE_XMP_{NEVER,LAZY,ALWAYS}`（image.h:46-51）。
- 门控 `dt_image_write_sidecar_file`（image.c:3459-3520）：ALWAYS 总写；LAZY 仅改过才写、未改删 XMP；内容级 MD5 去重（exif.cc:6949-7011）。后台队列经 `src/control/jobs/sidecar_jobs.c`，`NEVER` 时各处短路。
- DB 表见 Table 3。注意 `history.module` 列存的是 modversion（非模块 id），多实例靠 `operation+multi_priority` 区分。
- 冲突解决在 `src/control/crawler.c`：检出 `_crawler_examine`（:219-342，skew 2s :43），四动作 `:1181-1376`。crawler 触发的 `dt_history_load_and_apply` 用 RELAXED 锁避免回写 XMP（history.c:191-210）。

## §2 Q2 — What's in the XMP

- 版本 `DT_XMP_EXIF_VERSION 5`（exif.cc:83）。只写 v5；读兼容 v1（平行数组 `_read_history_v1` :4313）与 v2-v5（结构数组 `_read_history_v2` :4425），其他拒读（:5113-5124）。
- 已知 key 41 个（`dt_xmp_keys` exif.cc:447-467）。历史相关 12 行 + 非历史 13 行，全表见 Table 1；条目字段见 Table 2。
- 无 `history_order` key（全文 grep 不存在）；顺序由 `iop_order_version` + `iop_order_list` 承载。`history[n]:iop_order` 只读 xmp<4 兼容，永不写。
- 渲染全局项**不在 XMP 里**：demosaic/highlights 方法无 pref、默认值硬编码在各模块 `reload_defaults`（demosaic.c:1842-1869、highlights.c:1281-1339），最终值随 params 进 XMP。`dt_conf` 里影响像素的只有 `plugins/darkroom/demosaic/fdc_xover_iso`（默认 1600，读于 xtrans.c:1132，X-Trans 切换阈值）；`plugins/darkroom/workflow` 与 basecurve per-camera 只决定新图 auto-apply，物化为 history 后才进 XMP。

## §3 Q3 — How params are packed

- 整块规则：DB 写 `BIND_BLOB(h->params, params_size)` + `version()`（develop.c:1235-1236）；读 `modversion==version() && len==params_size` 则 memcpy（:2707-2773），否则 `dt_iop_legacy_params` 链式迁移（imageop.c:1594-1643，返 1 丢条目、返 -1 成功但需 auto_init）。XMP 读写只是该 blob 的编解码（exif.cc:5684 / :4384/5237），XMP→DB 不做版本转换。
- `version()` 即 `DT_MODULE_INTROSPECTION(N)` 的 N（common/darktable.h:230-246 → module_api.h:51）。`legacy_params` 签名见 iop/iop_api.h:244-249。
- 编码：hex 小写默认；`compress_xmp_tags`=`always` 或（`only large entries` 且 >100B）时 zlib+base64 加 `gz`+两位因子前缀（exif.cc:3972-4070；解码 :4071-4154 按 `gz` 前缀区分）。
- 9 模块例见 Table 4（exposure v7/28B、temperature v5/24B、tonecurve v5/520B、clipping v5/84B、lens v10/356B、colorin v8/1048B、colorout v5/520B、filmicrgb v6/116B、crop v3/24B）。9 个 params 内位域零命中；spots/retouch/liquify 抽查均为定长 POD（liquify 节点含 C `float complex` = 2×f32）。
- 端序 grep（endian/bswap/htons 等）扫 exif.cc/develop.c/history.c/imageop.c 仅 1 条无关命中：**无端序处理**，blob = 本机端序 + 编译器自然对齐（无 packed）。跨 ABI 不保证互读。

## §4 Q4 — Module order

- 默认表编译在源码：`legacy_order`/`v30_order`/`v50_order`/`v30_jpg_order`/`v50_jpg_order`（iop_order.c:81/183/306/430/556），枚举 `DT_IOP_ORDER_{CUSTOM,LEGACY,V30,V30_JPG,V50,V50_JPG,LAST}` = 0-6（iop_order.h:130-136），默认 RAW=V50、JPG=V50_JPG（:139-140）。`#define DT_IOP_ORDER_VERSION 5`（iop_order.c:31）零引用死宏。
- 运行时顺序号是 int（100 起步长 100，:1266-1278）；entry union 的 double 只为 DB 迁移兼容（iop_order.h:143-152）。查无返回 `INT_MAX`（:897-916）。
- 自定义顺序：仅 custom 或含多实例才存 `module_order.iop_list` 文本（写 :1071-1116），格式 `"op,instance,..."`（序列化 :2654-2672，反序列化 :2708-2760，sanity 首 rawprepare 尾 gamma :2681-2706）。XMP 恒写 version、条件写 list（exif.cc:6039-6049/6107-6109；读 :5007-5045）。
- 多实例同 op 相邻仍判内置版本（:965-1005）；内存按 int 排序（:1948-1956）。

## §5 Q5 — Multi-instance, blend, masks

- 多实例键 = `operation + multi_priority`（稳定），`multi_name[128]` 仅显示（develop.h:36-52、imageop.h:294-296）。DB→内存按 op+priority 找模块，`priority>0` 未命中新建实例（develop.c:2614-2690）。
- blend：`dt_develop_blend_params_t`（blend.h:187-236），`DEVELOP_BLEND_VERSION 15`（blend.h:31），迁移 if 链 1→15（blend.c:2458-3016）。关键字段：`mask_mode/mask_id/blend_mask_id/raster_mask_{source,instance,id,invert}/blendif(+64 参+16 boost)`。
- 蒙版三类见 Table 5。第 0 期：多实例 + 不透明度混合（`mask_mode` ENABLED/DISABLED + `opacity` 语义）在读路径上就是整块 blendop + 跳过 mask 引用；参数化/绘制/栅格/flexi 全标「后续」。

## §6 Q6 — Unknown entries

- 未知 op：XMP→DB **不校验直接 INSERT**（exif.cc:5209-5285；仅缺 operation/params/modversion 才整批丢 :4566-4578）；DB→内存跳过该条：`iop_order==INT_MAX`（develop.c:2614-2625）、无 `.so`（:2675-2683）、`NO_HISTORY_STACK`（:2691-2696）均为 `continue`；`modversion` 超前用默认参数**保留条目** + 警告（:2769-2782）；`legacy_params` 失败丢该条（:2786-2804）。
- 未知 XMP key：读只 `findKey` 已知键，非 dt 命名空间则 `xmp_version=-1` 忽略扩展（:4958-4964）；写是 exiv2 全文档 decode→`_remove_known_keys` 只删 41 已知（:530-564）→叠加 DB→encode，未知 key 全程保留（:6933-7044）。

## §7 Q7 — Entry points

- DB→内存：`dt_dev_read_history`（develop.c:2930）→ `dt_dev_read_history_ext`（:2437，纯逻辑+DB）→ 默认模块/预设/merge（:2098/2309）→ 按 `history_end` 逐条建 pipeline。GUI 触点仅刷新 `dt_dev_reload_history_items`（:1730）。
- XMP→DB：`dt_exif_xmp_read`（exif.cc:4924，纯逻辑+Exiv2）→ 事务内删/插 history（:5124/5209；xmp<4 补 mask_manager 条目 :5377）+ masks 经 `_add_mask_entry_to_db`（:4790，INSERT :4804）→ `dt_image_set_history_end`（:5414）。上层 `dt_history_load_and_apply`（history.c:176）带 GUI（undo/mipmap/signal）。
- DB→XMP：`dt_image_write_sidecar_file`（image.c:3459）→ `dt_exif_xmp_write`（exif.cc:6933，纯逻辑+Exiv2；`_exif_xmp_read_data` :5999 组装）。
- 内存→DB：`dt_dev_write_history`（develop.c:2047）→ `dt_dev_write_history_ext`（:2011，纯逻辑）→ `_cleanup_history` + 逐条 `_dev_write_history_item`（:1202）→ history_end + iop_order + hash。
- Hash 状态机 `DT_HISTORY_HASH_{BASIC,AUTO,CURRENT,MIPMAP}`（history.h:37-44），读写 `dt_history_hash_*`（history.c:1954-2140，纯逻辑）。

## §8 Q8 — Worked sample

- 样例 `src/tests/masking/flexi/xmps/G1_bare_uniform.xmp`（`xmp_version=5`、`history_end=5`、5 条历史；benchmark 的 null 样例无 exposure 故不用）。
- exposure 条目（:66-74，`modversion=6`）params 48 hex = 24B，逐字节对照 v6 结构体见 Table 6：mode=0、black=0.0、exposure=5.0、percentile=50.0、target=-4.0、bias=FALSE。
- v6→v7 迁移（exposure.c:289-304）补 `compensate_hilite_pres=FALSE`（≠新鲜 v7 默认 TRUE）——迁移语义以 legacy 分支为准。

## §9 Decisions

1. **XMP 解析库**：A 用 exiv2（与 dt 同语义，C++ 依赖）/ B 用 Rust xmp crate 自研（含未知 key 保留逻辑）。推荐 A 起步：写回保留未知 key 是兼容底线，自研易丢。
2. **DB 复用口径**：A 复用 dt 表结构（history/masks/module_order/history_hash 同形）/ B 自有库 + 仅 XMP 互通。推荐 A：DB 互通是「修过的图拿来打开」的最低成本路。
3. **params 布局**：A bindgen 逐模块生成 + golden 钉 sizeof / B 手写 repr(C)。推荐 A（布局漂移编译期可检），liquify 复数对与 lens/colorin 大结构体手工复核。
4. **`legacy_params` 移植范围**：A 全版本链 / B 仅近 2 版 + 旧版丢条目（dt 行为即丢条目，不断链）。推荐 B 起步：行为与 dt 一致且工作量收敛。
5. **blend 版本**：A 只读 v15 + 旧版走迁移链 / B 只读 v15、旧版丢 blend。推荐 A：迁移链是纯函数，转写成本低；B 会静默改观感。
6. **端序**：只支持 LE（dt 本身无端序处理）。无选项，文档记死。
7. **写模式默认**：沿用 `on import`。无选项。
8. **darktamer 3 模块**（skinmask/reshape/skinsmooth）：第 0 期不读（未知 op 跳过已有语义），条目保留。推荐：读跳过 + 写回原样保留（当未知 op 处理）。

## §10 Not found

- ~~`memory.history` 建表位置~~ 复审纠正：`CREATE TABLE memory.history` 在 `src/common/database.c:3722`（UNIQUE (operation, multi_priority)）；使用者 develop.c + iop_order.c:1037 + presets.c:1860。撤出 not-found。
- `dt_conf` 后端 = `src/control/conf.c`（`dt_conf_init` :530；darktablerc-common 继承 :502-504）。仓库无 `darktablerc` 样例。默认值在 `data/darktableconfig.xml.in`。不影响 XMP 兼容结论。
- `sizeof` 9 模块值为 LP64 字段推算（禁构建未跑编译器）；`gboolean`=4B 由 glib 定义 + 24B 反推佐证。
- `Xmp.exifEX.LensModel` 只读不写、`Xmp.xmpMM.DerivedFrom` 只写不读：grep 全文确认单向，无对称点。
- v1 XMP 样例：树内样例全是 v5（G1 `:11`）；v1/v2 读分支只对代码、无样例可跑。

## §11 Review revisions（复审 `3 error + 13 minor`，2026-11-25）

- E1 Table 7「5 表各+3」→ legacy/v30/v50 各+3、jpg 两表各+1（仅 skinmask），共 11 行；头注同改。
- E2 §10 memory.history not-found 撤回：建表 database.c:3722。
- E3 §7 hash 枚举 history.h:18-28 → :37-44。
- m4/m5/m6/m7/m9/m11 行号范围修正（4313-4423 / 4590-4669 / 4071-4154 / 2458-3016 / 5576-5737 / 5611-5639）。
- m8/m14 §7：set_history_end → :5414；5377 改标为 mask_manager 第二 INSERT，masks 插入改引 :4790/:4804。
- m10 §2 非历史计数 17 组 → 13 行；m12 conf.c 路径；m13 crawler 尾 342；m15 Table 2 v1 赋值 → 5223/5281；m16 补目录前缀 + module_api.h:51。
- 复算无误：9 sizeof / 9 版本号 / 9 legacy 覆盖 / Table 6 hex→float / 41 key / §0 11 行 / Table 3 列名 / endian 与位域结论。±10 行漂移注记 20 处，不修。
