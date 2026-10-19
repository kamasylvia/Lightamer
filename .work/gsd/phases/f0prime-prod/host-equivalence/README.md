# F0P-02 T5 — direct-launch host equivalence (Library bundle, two rounds)

| round | binary shape | build | Library | peakRSS |
|---|---|---|---|---|
| A | pre-flip (P1 T1 commit `907c373d`, SwiftUI lifecycle entry) | worktree `/private/tmp/f0p2-wt-eq` + tuist generate + default-DD build-for-testing | **738/4/0** | 615MB |
| B | post-flip (HEAD `53f43c4b`, LightamerShellMain entry) | main tree rebuild (newest-mtime container) | **738/4/0** | 615MB |

Executed/failed/skip identical (738/4/0), peakRSS identical (615MB) —
the shell handover has zero observable effect on the direct-launch test
host. PASS = the --all gate (T6) is released.

Supplies (the m-omp-6 step): `input/` (314MB) + `Resources/AIModels`
(194MB) copied into the worktree before the build (the AR-02-03
audit-repair recipe).

Build notes (M7-1 SPM proxy trap, extended): github.com was unreachable
both direct AND via the (idle) proxy daemon — the worktree's fresh
DerivedData could not clone the libwebp submodule. Resolution = copy the
main container's resolved `SourcePackages/` (156MB, incl. the libwebp
submodule checkout) into the worktree's default DerivedData container
before `tuist generate` + build; xcodebuild then reused the checkouts
with zero network. The worktree built with its OWN default container
(the mtime-glob picks the newest at run time — round B required
rebuilding the main tree first so its container became newest again).
