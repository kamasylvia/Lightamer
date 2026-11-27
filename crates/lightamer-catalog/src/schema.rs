// SPDX-License-Identifier: GPL-3.0-or-later
//! Schema v1 (PLAN-B-TABLES.md T-B1) plus the single writers of the storage
//! settings and the `_meta` mirror.
//!
//! Invariant: the storage pragmas (`journal_mode`, `synchronous`,
//! `foreign_keys`) are written only by [`apply_pragmas`], and the schema
//! version (`PRAGMA user_version` plus the `_meta` mirror row) only by
//! [`set_schema_version`]. Both are driven only from the migrate path, so a
//! fresh database and an adopted one converge on the same settings.

use rusqlite::Connection;

use crate::error::CatalogError;

/// The newest schema this build understands (`PRAGMA user_version`).
pub const SCHEMA_VERSION: i64 = 1;

/// `_meta` key mirroring [`SCHEMA_VERSION`].
pub const META_SCHEMA_VERSION: &str = "schema_version";
/// `_meta` key holding the session UUID (v4, text).
pub const META_SESSION_UUID: &str = "session_uuid";
/// `_meta` key holding who created the database (`<program> <version>`).
pub const META_CREATED_BY: &str = "created_by";
/// `_meta` key holding the creation time (Unix seconds, decimal text).
pub const META_CREATED_AT: &str = "created_at";
/// `_meta` key holding the session-level display-assist parameters (JSON
/// text; may be absent). Writers store it verbatim; readers treat absent as
/// empty and unparseable as empty-plus-corrupt (see [`display_aux_read`]).
pub const META_DISPLAY_AUX: &str = "display_aux";

/// Schema v1 DDL, verbatim from PLAN-B-TABLES.md T-B1.
///
/// Two tower rulings are baked into this shape: `snapshots` holds only the
/// key and the content (no reference count; orphans are found by query), and
/// the snapshot key defaults to the decimal `hash64` of the canonical JSON
/// with a suffix on hash collision (checked by byte comparison on write).
pub const SCHEMA_V1_DDL: &str = r##"
CREATE TABLE _meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
); -- 行：schema_version | 1, session_uuid | <uuid4>, created_by | <app+版本>, created_at | <unix>, display_aux | <JSON，可缺省，显示辅助阈值（B6 行为与命令，B12′ 持久化）>

CREATE TABLE photos (
  id                  INTEGER PRIMARY KEY,
  uuid                TEXT NOT NULL UNIQUE,      -- 跨库引用稳定标识
  path                TEXT NOT NULL,             -- kind=0 会话内相对（Capture/…），=1 外部绝对
  path_kind           INTEGER NOT NULL CHECK (path_kind IN (0, 1)),
  file_name           TEXT NOT NULL,             -- 展示与命名模板用
  width               INTEGER,                   -- 解码/B15 回填前可空
  height              INTEGER,
  file_size           INTEGER,
  captured_at         INTEGER,                   -- EXIF 拍摄时间，无则 NULL
  imported_at         INTEGER NOT NULL,
  camera              TEXT,                      -- EXIF 检索列（可空，下同）
  lens                TEXT,
  iso                 INTEGER,
  focal_mm            REAL,
  aperture            REAL,
  shutter_s           REAL,
  rating              INTEGER NOT NULL DEFAULT 0 CHECK (rating BETWEEN 0 AND 5),
  label               INTEGER NOT NULL DEFAULT 0, -- 色标 0=无，1..N 调色板位
  flag                INTEGER NOT NULL DEFAULT 0 CHECK (flag BETWEEN -1 AND 1), -- -1 拒绝，1 挑选
  process             INTEGER NOT NULL DEFAULT 1, -- 当前步快照 process 的镜像（§1.2）
  cursor              INTEGER NOT NULL DEFAULT 0, -- 游标（history_steps.idx）
  current_hash        TEXT NOT NULL,             -- 当前快照的键（缺省 = hash64_decimal，见 snapshots）
  trash_original_path TEXT,                      -- 在 Trash 内才非空
  trash_original_kind INTEGER CHECK (trash_original_kind IN (0, 1)),
  missing             INTEGER NOT NULL DEFAULT 0, -- 引用式文件失联标记
  is_export           INTEGER NOT NULL DEFAULT 0  -- 导出产物标记（A-18：导出作业完成时登记；1 = 导出产物，见 PLAN-B §1.1）
);
CREATE INDEX idx_photos_path ON photos (path_kind, path);
CREATE INDEX idx_photos_rating ON photos (rating);
CREATE INDEX idx_photos_flag ON photos (flag);
CREATE INDEX idx_photos_process ON photos (process);
CREATE INDEX idx_photos_captured ON photos (captured_at);

CREATE TABLE snapshots (
  hash TEXT PRIMARY KEY,  -- 快照的键：缺省 = PhotoSettings::hash64_decimal；哈希碰撞时加 "#2" 一类后缀（PLAN-B §1.2）
  json TEXT NOT NULL      -- 规范 JSON（含 format_version 与 process）。键命中后必须和它逐字节比对，相同才复用
);
-- 不存引用计数：没有步引用、也不是任何照片当前行的快照就是孤儿，一条查询查得出来。

CREATE TABLE history_steps (
  photo_id      INTEGER NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  idx           INTEGER NOT NULL,  -- 步序，0 起；与 HistoryStack 步序一致
  label         TEXT NOT NULL,     -- 提交命令的标识（如 develop.set）
  snapshot_hash TEXT NOT NULL REFERENCES snapshots (hash),  -- 快照的键
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (photo_id, idx)
);
CREATE INDEX idx_steps_hash ON history_steps (snapshot_hash);

CREATE TABLE keywords (
  id   INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);
CREATE TABLE photo_keywords (
  photo_id   INTEGER NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  keyword_id INTEGER NOT NULL REFERENCES keywords (id) ON DELETE CASCADE,
  PRIMARY KEY (photo_id, keyword_id)
);

CREATE TABLE albums (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('album', 'smart', 'project', 'group')),
  rules_json TEXT,             -- kind='smart' 才非空；查询时求值
  created_at INTEGER NOT NULL
);
CREATE TABLE album_photos (
  album_id INTEGER NOT NULL REFERENCES albums (id) ON DELETE CASCADE,
  photo_id INTEGER NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  position INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (album_id, photo_id)
);
CREATE INDEX idx_album_pos ON album_photos (album_id, position);

CREATE TABLE favorites (
  id        INTEGER PRIMARY KEY,
  path      TEXT NOT NULL UNIQUE,
  path_kind INTEGER NOT NULL CHECK (path_kind IN (0, 1)),
  name      TEXT NOT NULL
);
"##;

/// Applies the storage pragmas: WAL journal, `FULL` synchronous (every
/// commit is synced: committed commands survive a crash and a power cut),
/// foreign keys on.
///
/// This is the only function that writes these three settings.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses a pragma, or
/// [`CatalogError::Setup`] when the journal mode does not stick to WAL.
pub fn apply_pragmas(conn: &Connection) -> Result<(), CatalogError> {
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "synchronous", "FULL")?;
    conn.pragma_update(None, "foreign_keys", 1)?;
    let mode: String = conn.pragma_query_value(None, "journal_mode", |row| row.get(0))?;
    if !mode.eq_ignore_ascii_case("wal") {
        return Err(CatalogError::Setup(format!(
            "journal_mode is {mode}, expected WAL"
        )));
    }
    Ok(())
}

/// Writes the schema version to both places at once: `PRAGMA user_version`
/// and the `_meta` mirror row.
///
/// This is the only function that writes either. Callers run it inside the
/// migration transaction of the step that reaches `version`.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the write.
pub fn set_schema_version(conn: &Connection, version: i64) -> Result<(), CatalogError> {
    conn.pragma_update(None, "user_version", version)?;
    meta_set(conn, META_SCHEMA_VERSION, &version.to_string())?;
    Ok(())
}

/// Reads `PRAGMA user_version` (0 for a database that predates versioning).
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn user_version(conn: &Connection) -> Result<i64, CatalogError> {
    Ok(conn.query_row("PRAGMA user_version", [], |row| row.get(0))?)
}

/// Reads one `_meta` row: `None` when the key is absent.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn meta_get(conn: &Connection, key: &str) -> Result<Option<String>, CatalogError> {
    match conn.query_row("SELECT value FROM _meta WHERE key = ?1", [key], |row| {
        row.get(0)
    }) {
        Ok(value) => Ok(Some(value)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(other) => Err(CatalogError::from(other)),
    }
}

/// Writes one `_meta` row, creating or replacing it.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the write.
pub fn meta_set(conn: &Connection, key: &str, value: &str) -> Result<(), CatalogError> {
    conn.execute(
        "INSERT INTO _meta (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [key, value],
    )?;
    Ok(())
}

/// What [`display_aux_read`] found.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DisplayAuxRead {
    /// The stored JSON text verbatim; empty when the key is absent or the
    /// stored text does not parse.
    pub json: String,
    /// True only when the key is present but the stored text does not parse
    /// as JSON. Callers treat that as empty and surface this flag (reset to
    /// the default and report, never silently keep the bad text).
    pub corrupt: bool,
}

/// Reads the `display_aux` row: verbatim JSON when it parses, empty when the
/// key is absent, empty-plus-corrupt when the stored text does not parse.
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the read.
pub fn display_aux_read(conn: &Connection) -> Result<DisplayAuxRead, CatalogError> {
    let Some(text) = meta_get(conn, META_DISPLAY_AUX)? else {
        return Ok(DisplayAuxRead {
            json: String::new(),
            corrupt: false,
        });
    };
    if serde_json::from_str::<serde_json::Value>(&text).is_ok() {
        Ok(DisplayAuxRead {
            json: text,
            corrupt: false,
        })
    } else {
        Ok(DisplayAuxRead {
            json: String::new(),
            corrupt: true,
        })
    }
}

/// Stores the `display_aux` row verbatim (no validation on write; what was
/// written is what [`display_aux_read`] parses back).
///
/// # Errors
///
/// [`CatalogError::Sql`] when SQLite refuses the write.
pub fn display_aux_write(conn: &Connection, json: &str) -> Result<(), CatalogError> {
    meta_set(conn, META_DISPLAY_AUX, json)
}
