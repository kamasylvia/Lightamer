# fixtures/oracle — 官方对照夹具（A5）

`emit-xmp` 写给 darktable 5.6.2 官方包读的 XMP。单向：只写不读（A-12）。

## 文件

- `expected-g1-exposure.xmp`：曝光 +1EV 单条历史（逐字节拷自 spike 探针
  `decode-oracle-evidence/g1m-exposure.xmp`，5.6.2 实渲验证过）。
- `expected-g2-exposure-flip.xmp`：曝光 +1EV + 水平翻转两条（同上拷自 `g2m`）。
- 本说明：两模块的参数布局。`lightamer-cli` 的 `emit_xmp` 单元测试断言输出与上二者逐字节相同。

## XMP 规则（spike 实证）

- 最小历史（只写改过的模块）+ `auto_presets_applied="0"` + `xmp_version="4"`；
  darktable 按本机逐项补默认。`iop_order_version` 可省略。
- **禁 XML 注释**：前导 `<!-- … -->` 致整读失败（`probe-comment.xmp` 复现）。
- 参数 hex 小写直写（≤100B 不压缩）；blend 整块沿用
  `blendop_version="10"` + `blendop_params="gz14eJxjYIAACQYYOOHEgAYY0QVwggZ7CB6pfNoAAEkgGQQ="`。

## exposure：`dt_iop_exposure_params_t`，modversion 7，28 字节 LE

出自上游 `src/iop/exposure.c`，三版本（`release-5.6.2` @ `908607e556`、
`release-5.7.0` @ `e5330da743`、`master` @ `679d594f5d`）结构体逐字节相同，
+1EV 夹具值见右列（`emit-xmp --exposure-ev 1` 写法）：

| 偏移 | 字段 | C 类型 | 字节 | 夹具值 |
|---|---|---|---:|---|
| 0 | `mode` | `dt_iop_exposure_mode_t`（enum = int32） | 4 | 0 = `EXPOSURE_MODE_MANUAL` |
| 4 | `black` | float | 4 | 0.0 |
| 8 | `exposure` | float | 4 | 1.0 |
| 12 | `deflicker_percentile` | float | 4 | 50.0 |
| 16 | `deflicker_target_level` | float | 4 | −4.0 |
| 20 | `compensate_exposure_bias` | gboolean（int32） | 4 | 0 = FALSE |
| 24 | `compensate_hilite_pres` | gboolean（int32） | 4 | 1 = TRUE |

`sizeof`/`offsetof` 经 clang 实测（LP64，见 `docs/ORACLE-BASELINE.md` §方法）；
+1EV 整块 hex：`00000000 00000000 0000803f 00004842 000080c0 00000000 01000000`。

## flip：`dt_iop_flip_params_t`，modversion 2，4 字节 LE

出自上游 `src/iop/flip.c`，三版本结构体逐字节相同：

| 偏移 | 字段 | C 类型 | 字节 | 夹具值 |
|---|---|---|---:|---|
| 0 | `orientation` | `dt_image_orientation_t`（enum = int32，定义在 `src/common/image.h`） | 4 | 2 = `ORIENTATION_FLIP_X`（水平翻转） |

## 加新模块（以后每移植一波）

在 `apps/lightamer-cli/src/xmp.rs` 给该模块加一个 `DtParamsEncoder`（strongly typed
参数 → darktable LE 字节），`operation()`/`modversion()` 按**官方包版本**
（现 5.6.2，见 `Scripts/oracle.lock` 与 `docs/ORACLE-BASELINE.md` 结论）写，
并在本目录追加布局表 + golden XMP。
