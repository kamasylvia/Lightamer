# HISTORY-COMPAT-TABLES — 长表（HISTORY-COMPAT.md 的附表）

> 基线：`dt-master` = `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master` @ `679d594f5d`（2026-11-22）。
> 下表路径均相对该树。行数命令：`wc -l <文件>`；key 计数：`sed -n '447,467p' src/common/exif.cc | grep -o 'Xmp\.[^"]*' | wc -l` = 41。

## Table 1 — `dt_xmp_keys` 全表（exif.cc:447-467，读/写位置）

历史相关：

| key | 类型 | 读位置 | 写位置 |
|---|---|---|---|
| `Xmp.darktable.xmp_version` | int（恒 5） | exif.cc:4953 | exif.cc:6098 / 导出 6261 |
| `Xmp.darktable.history`（Seq of struct） | 见 Table 2 | `_read_history_v2` exif.cc:4425 | `_set_xmp_dt_history` exif.cc:5576-5737（history 循环 5687-5720） |
| `Xmp.darktable.history_end` | int | exif.cc:5402-5406 findKey，`set_history_end` :5414（缺省回退 `MAX(num)+1` :5415-5437） | exif.cc:5736 |
| `Xmp.darktable.iop_order_version` | int（enum 0-6） | exif.cc:5009（v4/5）/ 5027（v3） | exif.cc:6107 / 导出 6270 |
| `Xmp.darktable.iop_order_list` | string（仅 custom/多实例） | exif.cc:5015 | exif.cc:6108-6109（条件 6041-6049） |
| `Xmp.darktable.masks_history`（Seq of struct） | 见 Table 5 | `_read_masks_v3` exif.cc:4671 | exif.cc:5611-5639 |
| `Xmp.darktable.raw_params` | int32（含 user_flip） | exif.cc:4968-4977 | exif.cc:6099 / 导出 6262 |
| `Xmp.darktable.auto_presets_applied` | int 0/1 | exif.cc:4982-5000 | exif.cc:6100-6103 / 导出 6263-6266 |
| `Xmp.darktable.history_basic_hash` | blob 编码 | exif.cc:5501-5521 | exif.cc:6117-6136 |
| `Xmp.darktable.history_auto_hash` | blob 编码 | 同上 | 同上 |
| `Xmp.darktable.history_current_hash` | blob 编码 | 同上 | 同上 |
| 旧平行数组 `history_operation/history_params/history_modversion/history_enabled/blendop_params/blendop_version/multi_priority/multi_name` | Seq/Bag | `_read_history_v1` exif.cc:4313-4423（仅 xmp v1） | 不写 |
| 旧平行数组 `mask/mask_src/mask_name/mask_type/mask_version/mask_id/mask_nb` | Seq/Bag | `_read_masks` exif.cc:4590-4669（仅 xmp<3） | 不写 |
| `history[n]/darktable:iop_order` | double | exif.cc:4536-4544（仅 xmp<4 兼容） | 永不写 |

非历史：

| key | 类型 | 读位置 | 写位置 |
|---|---|---|---|
| `Xmp.xmp.Rating` | int | exif.cc:685-695 | exif.cc:6058 / 导出 6213 |
| `Xmp.xmp.Label` | string（五色→0-4） | exif.cc:698-711（优先于 colorlabels） | 不写 |
| `Xmp.darktable.colorlabels` | int Seq | exif.cc:713-720 | exif.cc:5979-5994 |
| `Xmp.lr.hierarchicalSubject` / `Xmp.dc.subject` | string Bag（前者优先） | exif.cc:726-734 | exif.cc:6085/6094；导出 6241/6255 |
| `Xmp.dc.title/description/creator/rights/publisher`、`Xmp.acdsee.notes`、`Xmp.xmpMM.PreservedFileName`、`darktable:version_name` | string（meta_data 表驱动） | exif.cc:655-676 | exif.cc:5935-5966 |
| `Xmp.exif.GPSLatitude/GPSLongitude` | string（度分+方向） | exif.cc:737-745 | exif.cc:5884-5933 |
| `Xmp.exif.GPSAltitude` + `GPSAltitudeRef` | 有理数 + 0/1 | exif.cc:747-761 | exif.cc:5926-5931 |
| `Xmp.exif.DateTimeOriginal`（备选 `Xmp.photoshop.DateCreated`） | EXIF 日期串 | exif.cc:780-786 | exif.cc:6053 / 导出 6208 |
| `Xmp.exifEX.LensModel` | string | exif.cc:764-778 | 查不到写入 |
| `Xmp.xmpMM.DerivedFrom` | string（原文件名） | 查不到读取 | exif.cc:6061 / 导出 6216 |
| `darktable:import/change/export/print_timestamp` | int64 | exif.cc:5813-5845（不读 import） | exif.cc:5740-5776 |
| `darktable:harmony_guide_type/rotation/width` | int | exif.cc:5847-5865 | exif.cc:5778-5797 |
| `darktable:neural_restore` | string（`"raw-denoise"`） | exif.cc:678-682 | 导出链路 exif.cc:3442-3450（非 sidecar 写） |

## Table 2 — history 条目字段（`history_entry_t` exif.cc:4225-4244，读 4496-4560 / 写 5687-5724）

| XMP 属性 | C 类型 | DB 列 | 说明 |
|---|---|---|---|
| `num` | int | `history.num` | 0-based 序号；v1 XMP 无此字段，读时 BIND num（exif.cc:5223）+ 循环 `num++`（:5281） |
| `operation` | string（≤19+`\0`，op 名） | `history.operation` | 缺失则整批历史丢弃（exif.cc:4566-4578） |
| `enabled` | int→bool | `history.enabled` | |
| `modversion` | int | `history.module` | 缺失则整批丢弃；注意列名叫 `module` |
| `params` | blob 编码 | `history.op_params` | 缺失则整批丢弃 |
| `multi_name` | string（≤127+`\0`） | `history.multi_name` | 可空，仅显示 |
| `multi_name_hand_edited` | int 0/1 | `history.multi_name_hand_edited` | |
| `multi_priority` | int | `history.multi_priority` | 多实例稳定键（与 operation 组合） |
| `blendop_version` | int（缺省 1） | `history.blendop_version` | 仅 blendop 非空写 |
| `blendop_params` | blob 编码 | `history.blendop_params` | 仅 blendop 非空写 |

## Table 3 — DB 表（现行 schema，`database.c:3442-3546`）

| 表 | 列 |
|---|---|
| `main.history`（:3499-3504） | `imgid, num, module(=modversion), operation, op_params BLOB, enabled, blendop_params BLOB, blendop_version, multi_priority, multi_name, multi_name_hand_edited`；索引 `(imgid,operation)`、`(imgid,num DESC)` |
| `main.history_hash`（:3540-3546） | `imgid PK, basic_hash, auto_hash, current_hash, mipmap_hash`（均为 BLOB） |
| `main.images` 历史相关列（:3442-3462） | `version, max_version, write_timestamp, history_end, import/change/export/print_timestamp, thumb_timestamp` |
| `main.masks_history`（:3508-3512） | `imgid, num, formid, form, name, version, points BLOB, points_count, source BLOB`；索引 `(imgid,num)` |
| `main.module_order`（:3537-3538） | `imgid PK, version, iop_list VARCHAR` |
| `main.color_labels` / `main.meta_data` / `main.tagged_images` | 评分色标/元数据/标签（非历史，列略） |

## Table 4 — 第 0 期 9 模块参数（`version()` = `DT_MODULE_INTROSPECTION(N)` 行；sizeof = LP64 字段推算，未编译验证）

| 模块 | 结构体位置 | sizeof | version | legacy 覆盖（函数行） |
|---|---|---|---|---|
| exposure | iop/exposure.c:66-76 | 28 | 7（:47） | :157：2/3/4/5→6，6→7 |
| temperature | iop/temperature.c:66-75 | 24 | 5（:45） | :119：2→3，3→4，4→5 |
| tonecurve | iop/tonecurve.c:102-113（node :81-85 = 8B ×20×3） | 520 | 5（:50） | :191：1→5，2→失败，3→5，4→5 |
| clipping | iop/clipping.c:58-81 | 84 | 5（:43） | :101：2→5，3→5，4→5 |
| lens | iop/lens.cc:118-160 | 356 | 10（:65） | :430：2..9 全→10（v4/5/6 在 modified==0 时返 -1 要 auto_init） |
| colorin | iop/colorin.c:83-94（ICC_LEN=512 :64） | 1048 | 8（:70） | :368：1..6→7，7→8 |
| colorout | iop/colorout.c:89-94（ICC_LEN=512 :44） | 520 | 5（:49） | :161：2/3→5，4→5（旧 ICC_LEN=100） |
| filmicrgb | iop/filmicrgb.c:168-199 | 116 | 6（:67） | :436：1..5→6 |
| crop | iop/crop.c:60-68 | 24 | 3（:43） | :169：1→2，2→3 |

位域 grep（`: \d+;`）在 9 模块 params 内零命中；类型仅 float/int/enum/gboolean/定长 char/定长数组。
指针/变长抽查（全定长 POD，无反例）：spots（iop/spots.c:39-43，512B）/ retouch（iop/retouch.c:99-119，300 定长 forms）/ liquify（iop/liquify.c:255-258，100 节点；节点含 C `float complex` = 2×f32，:222-236）。

## Table 5 — 蒙版在历史里的表示

| 蒙版类 | XMP 条目 | DB | 参数结构 |
|---|---|---|---|
| 绘制蒙版 shapes | `masks_history[n]`: `mask_num/mask_id/mask_type/mask_name/mask_version/mask_points/mask_nb/mask_src`（读 exif.cc:4742-4777，写 :5611-5639） | `masks_history` 全行 | `dt_masks_form_t`（develop/masks.h:514-528）；点 `dt_masks_point_{circle,ellipse,path,brush,gradient,object}_t`（masks.h:232-297）；`DEVELOP_MASKS_VERSION 7`（masks.h:31） |
| 参数化蒙版（经典） | 内嵌于 history 条目 `blendop_params` | `history.blendop_params` | `blendif + blendif_parameters[64] + blendif_boost_factors[16]`（blend.h:205/230-231） |
| 参数化蒙版（flexi） | 同上 masks_history points | 同上 | `dt_masks_point_parametric_t`（blend.h:241-258）「后续」 |
| 栅格蒙版 | blend 四字段 + flexi 点 | `history.blendop_params` + masks | `raster_mask_source/instance/id/invert`（blend.h:232-235）+ `dt_masks_point_raster_t`（blend.h:282-288）「后续」 |
| 引用关系 | — | `blendop.mask_id` → `masks_history.formid` | `dt_mask_id_t=int32_t`，`NO_MASKID=0`，有效 = `>0`（common/darktable.h:202-207） |

`mask_mode` 位（blend.h:100-109）：DISABLED / ENABLED / MASK（绘制） / CONDITIONAL（参数） / RASTER / FLEXI(1<<4）。

## Table 6 — Q8 样例逐字节（`src/tests/masking/flexi/xmps/G1_bare_uniform.xmp:66-74`，exposure，`modversion=6`）

`params="00000000000000000000a04000004842000080c000000000"`（48 hex = 24B，无 `gz` 前缀 = hex 直存）。
对照 `dt_iop_exposure_params_v6_t`（iop/exposure.c:164-172），小端：

| offset | size | bytes（LE） | 值 | 字段 |
|---|---|---|---|---|
| 0 | 4 | `00 00 00 00` | i32 0 = MANUAL | `mode` |
| 4 | 4 | `00 00 00 00` | 0.0 | `black` |
| 8 | 4 | `00 00 a0 40` | 5.0 | `exposure`（测试故意 +5EV） |
| 12 | 4 | `00 00 48 42` | 50.0 | `deflicker_percentile` |
| 16 | 4 | `00 00 80 c0` | -4.0 | `deflicker_target_level` |
| 20 | 4 | `00 00 00 00` | FALSE | `compensate_exposure_bias` |

v6→v7 迁移（exposure.c:289-304）：前 6 字段原样拷，`compensate_hilite_pres=FALSE`（注意≠新鲜 v7 默认 TRUE）。

## Table 7 — darktamer 对历史格式的改动（`git -C …/darktable diff github/master..HEAD`）

| 文件 | 改动 | 历史兼容影响 |
|---|---|---|
| `src/common/iop_order.c` | +11 行：`skinmask` 3.3 进 5 表；`reshape`（60.3/66.3）与 `skinsmooth`（60.5/66.5）只进 legacy/v30/v50，jpg 两表无 | 仅新增 op 的排位；旧条目顺序号不变 |
| `src/common/exif.cc` | 仅 `Exif.Image.Software` 写 darktamer release/creator（约 :3820） | 导出元数据，不碰历史 |
| `src/common/database.c` | 仅对话框文案 darktable→Darktamer | 无 |
| `src/common/history.c/h`、`src/develop/blend.*` | 零改动 | 无 |
