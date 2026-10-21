# Lensfun calibration database — pinned snapshot

This directory carries an **UNMODIFIED offline snapshot** of the Lensfun
calibration database (`version_1/`, 56 XML files, ~5.1 MB), copied on
**2026-10-21** from the official snapshot archive:

- Source: `https://lensfun.github.io/db/version_1.tar.bz2`
- Archive SHA-256: `97c9f8059accae0128a413bc610a04a4548e8da2764a6d3d60d82bf917639457`
- Snapshot provenance: byte-identical to the RawLab project's pinned copy
  (`RawLab/lutools/third_party/lensfun/version_1/`, checked out from the
  same 2026-10-12 archive; the per-file SHA-256 manifest is
  `version_1.SHA256SUMS` next to this README)
- License: **CC-BY-SA-3.0** (the database is data, NOT the LGPL-3.0
  library — see `Resources/Licenses/Lensfun/` for the full texts and the
  NOTICE entry)

Discipline (plan LENS-03 T3, D-LENS-6):

- The snapshot ships **pinned** — database updates are explicit source
  changes (a new pinned snapshot + a fresh SHA + a new date here), never
  a background download.
- The manual "check for updates" face downloads the official archive,
  verifies its SHA-256 against THIS README's registered value, and
  refuses to install on any mismatch.
- `LensfunDataDistribution` (App) seeds the snapshot into the support
  directory on first run and resolves the active database with the
  priority: custom path > bundled seed > downloaded copy > absent.
