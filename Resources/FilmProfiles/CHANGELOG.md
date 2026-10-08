# FilmProfiles changelog

All notable changes to the `Resources/FilmProfiles/` asset set. The profile
files themselves are unmodified verbatim copies of upstream spektrafilm
assets; this log records which upstream snapshot is vendored (per the
upstream license's request that changes to profiles and LUTs be tracked in
a changelog file shipped alongside the license).

The format follows the upstream request: one entry per vendored snapshot,
never in-place edits of the profile bytes.

## 2026-10-07 — import spektrafilm 0.3.2

- Vendored the spektrafilm profile set, version **0.3.2**
  (`metadata.version` of every profile; upstream import snapshot
  2026-05-28 era, copied from the local SpektraLab working checkout at
  `engine/resources/`).
- Contents: 28 profile JSON files under `profiles/` (22 film stocks,
  6 paper stocks by `info.support`) plus the neutral print-filter
  measurement table `neutral_print_filters.json` (TH-KG3 enlarger head,
  8 paper stocks × film stocks, 160 measured `[C, M, Y]` CC triplets).
- `LICENSE` = verbatim upstream `SPEKTRAFILM_LICENSE.txt`
  (CC BY-SA 4.0 legal text + attribution preamble v1.1).
- `NOTICE` = attribution, citation transcription, and the consumption
  disclosure (density-domain consumption only; no spectral replay).
- `MANIFEST.sha256` = SHA-256 of `LICENSE` + all 29 asset files; a unit
  test reconciles the manifest against this tree on every run.
- Files are consumed by `FilmMaterialStore` (LightamerCore) through the
  typed loader; the JSON on disk is never rewritten by the app.
