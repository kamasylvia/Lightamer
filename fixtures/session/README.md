# fixtures/session — 会话库夹具（B12′-a）

三个很小的库文件，直接进 git。测试把它们拷进临时目录再打开，从不原地写。

| 文件 | 大小 | sha256 | 里面有什么 |
|---|---|---|---|
| `v0-legacy.lmsessiondb` | 8192 B | `3feb5db848b8e77cc0c17554ce21f6822a0e32d9dc38f1f49464454d141f13a6` | `user_version = 0`；表 `legacy_notes(id, body)` 三行 `alpha/beta/gamma`；无 v1 表。打开后应迁移到 v1、旧行保留、留下 `.pre-migrate.0-1.bak`。 |
| `future-v999.lmsessiondb` | 12288 B | `8d29e68e017cbe85e775d1790c837870b25b133f7b9062651fbe1e941807044d` | `user_version = 999`；`_meta.schema_version = '999'`。打开必须被拒且文件逐字节不变。 |
| `corrupt.lmsessiondb` | 256 B | `0257b6edb86189edebe6d580add8fe1f506f855fe9c22af43eb2dbd7cf5ce58c` | 256 字节随机数，不是数据库。打开报数据库错误；`verify` 检出是下一波的事。 |

重造（仓库根，`sqlite3` 是 macOS 自带的 `/usr/bin/sqlite3`）：

```sh
rm -f fixtures/session/*.lmsessiondb
sqlite3 fixtures/session/v0-legacy.lmsessiondb \
  "PRAGMA user_version = 0; CREATE TABLE legacy_notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL); INSERT INTO legacy_notes (body) VALUES ('alpha'), ('beta'), ('gamma');"
sqlite3 fixtures/session/future-v999.lmsessiondb \
  "PRAGMA user_version = 999; CREATE TABLE _meta (key TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT INTO _meta (key, value) VALUES ('schema_version', '999');"
head -c 256 /dev/urandom > fixtures/session/corrupt.lmsessiondb
shasum -a 256 fixtures/session/*.lmsessiondb
```

注意：`corrupt.lmsessiondb` 每次重造的字节都不同，sha 随之变，属预期行为；
前两个是确定性的（同一 `sqlite3` 版本下逐字节相同，本批用 3.54.0）。
