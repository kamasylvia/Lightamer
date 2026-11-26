# Order fixture

Upstream: /Volumes/UNITEK/Documents/Development/Lightamer/../Lightamer-rust-spike/refs/dt-master
Commit: 679d594f5d93cde043703ba8ff26873d0e475905 (short 679d594f5d)

Regenerate with (from the workspace root):

cargo run -p xtask -- gen-iop-stubs

Add `--upstream PATH` to parse another checkout.

`dt-order-679d594f5d.json`: one row per named module of `v50_order` and
`v50_jpg_order` in `src/common/iop_order.c` at that commit, in raw-table
order. Each row:

{"name": "<op>", "raw_prio": <f>, "raw_tie": <u>, "jpg_prio": <f>, "jpg_tie": <u>}

- `raw_prio` / `jpg_prio`: priority verbatim from C (never with the `f`
suffix; integral values gain `.0` so JSON and Rust both read floats).
- `raw_tie` / `jpg_tie`: 0-based row index among named rows of that
table; the sentinel `""` row is dropped and never counted.

`check-order-sync` re-parses the upstream tables and compares them with
this fixture and with the stub directories; any drift fails the check.
