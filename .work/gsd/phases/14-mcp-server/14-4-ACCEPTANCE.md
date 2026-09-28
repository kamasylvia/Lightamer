# Plan 14-4 Acceptance Report — launcher + closeout sign-off (W3)

**Verdict: PASS / 0 error + 1 minor** (the one minor was fixed by the acceptor, commit `fab5fdc`)
**Acceptor:** ZCode acceptance subagent · **Date:** 2026-09-28
**Plan:** `.work/gsd/phases/14-mcp-server/14-4-PLAN.md`
**Scope note:** the 2026-09-27 project redefinition (Alcedo clone) does not downgrade any AC here — all verdicts are against the plan text as written. No semantic conflict between the plan and the new direction was found within this plan's scope (the MCP server is a retained asset).

## Independent test re-run (fresh build, direct-launch harness)

| Suite | Declared | Re-run |
|---|---|---|
| Full suite (`caffeinate -dis Scripts/test-direct.sh`) | 1881 executed / 11 skipped / 0 failures (780.3s) | **1881 executed / 11 skipped / 0 failures (704.0s), TEST_EXIT=0** |
| `McpLauncherTests` | 10/0 | **10/0 (0.13s)** |
| `McpLauncherSentinelTests` | 9/0 | **9/0 (5.16s)** |
| `McpFinalSnapshotTests` | 6/0 | **6/0 (0.20s)** — per-test lines confirm all six ran, incl. `testSC7LauncherChainEndToEndWithDualEntry` passed (0.107s, real loopback chain) |
| `McpHostTests` | 18/0 | **18/0 (0.75s)** |

Counts match the declaration exactly. Arithmetic check: baseline 1857 + 26 new − 2 probe retirement = 1881. No flake (LayerE2E / ToneEqual / QuickLook) appeared; no attribution entries needed. No enrollment dialogs (direct-launch harness held).

## Pre-checks

- **4 commits verified via `git show --stat`** — content boundaries match the declared task split:
  - T1 `e4f80f7` (10 files: McpLauncher.swift new + controller/Settings/app/catalog + 3 test files) — launcher core + Settings MCP section + probe retirement + culling union assembly
  - T2 `4f5d547` (8 files: panel new + registry counter seam + sentinel tests) — log panel + sentinel trio + write-call counter
  - T3 `23928ec` (6 files: FinalSnapshotTests new + tool descriptions + README + PROJECT.md) — final snapshot freeze + SC#7 chain + doc closure
  - T4 `24e6078` (8 files: VALIDATION/SUMMARY/DECISIONS + REQUIREMENTS/GOAL-STATE/TODO/PROGRESS/LESSONS) — sign-off batch
- **`git status`**: no 14-4 source leftovers in the worktree. Remaining dirt belongs to parallel sessions / known-untracked dirs only (`.work/gui-acceptance/*`, `.work/culling-cli/`, `.work/debug-flaky/`, `.work/matrix/`, `.work/tmp-public/`, `.reasonix/`) — untouched per acceptance boundaries.
- Not pushed (verified: no push performed; remote state untouched).

## Acceptance-criteria checklist (plan §Acceptance, evidence per item)

| # | AC | Verdict | Evidence |
|---|---|---|---|
| 1 | Settings MCP section: server toggle wired to the 14-1 start/stop hooks + template/prompt fields (omp/pi placeholder examples) + explicit LAN toggle (0.0.0.0 + Bearer forced + risk copy) + zh/en keys | PASS | `SettingsView.swift:156-238` (toggle → `startEmbeddedServer`/`stopEmbeddedServer`; LAN toggle restarts host on change; risk copy `settings_mcp_lan_risk` = the plan-mandated sentence verbatim); `McpServerController.swift:285-324` (`.lan` branch binds `lanHost = "0.0.0.0"`, Bearer mandated); zh catalog spot-check (1146/1146 keys carry `zh`, L025-compliant, no zh-Hans) |
| 2 | Launcher: placeholder verbatim + `{{PROMPT}}` single-quote escape round trip + `/bin/zsh -c` + serial gate + SIGTERM→5s→SIGKILL only-registered-pid + non-zero-exit red face + honest no-write-back face + EXP-08 dual-trail | PASS | `McpLauncher.swift` (render w/ `'`→`'\''`; `shellPath="/bin/zsh"` default; slot taken before `run()` w/ rollback; `killGrace = 5`; `stop(pid:)` refuses foreign pid with `.notOurs`); tests `testPromptMetaCharactersSurviveZshRoundTrip` (real zsh: quotes/backticks/`$()`/`$HOME` byte-for-byte), `testSerialGateRejectsSecondStartWhileInFlight`, `testMissingExecutableFailsLaunchAndKeepsSlotFree`, `testNonZeroExitSurfacesThroughOnExit` (127 face); panel red `.failed(code:)` (`McpLauncherPanelView.swift:245-247`); EXP-08 dual comments (`McpLauncher.swift:10-17` + `PostExportActions.swift:115-120`) + doc trail (CONTEXT D-14-CONTEXT-10③, SUMMARY T1) |
| 3 | Log panel: 2000-line ring / pause-scroll / copy-to-clipboard | PASS | `McpLauncherLogBuffer` ring drop-from-head (McpLauncher.swift:96-103); panel follow-toggle freezes viewport, copy = full ring to pasteboard (McpLauncherPanelView.swift:144-148, 284-288); tests `testLogRingTruncatesFromHead`, `testCopyLogPastesFullRingToPasteboard`, `testFollowToggleDrivesScrollFollowFlag` |
| 4 | Probe retirement + final 19-tool closed-set freeze (§A verbatim + 20th-tool negative + annotations) | PASS | `McpServerController.swift:13-16,137-139` (probe pair retired); `McpFinalSnapshotTests`: 19 descriptors vs research §A table (row-by-row: 5 editing + 14 culling; 8 destructive / 11 read sets asserted equal); `testTwentiethToolIsWhitelistNegative` (match_color/delete_file/run_shell → typed `[internalError] unknownTool`; tools/list still 19); `testProbeFaceRetiredFromEveryRegistry` |
| 5 | SC#7 launcher end-to-end (launch → agent writes via endpoint → sidecar + GUI-visible stale face → log capture) + dual entry coexistence | PASS | `testSC7LauncherChainEndToEndWithDualEntry` passed (0.107s): real child over `/bin/zsh -c` + curl (Streamable HTTP + JSON-RPC), endpoint read from discovery file, initialize→list_photos→get_thumbnails (stale:true off a real tier-B cache image)→set_rating; sidecar rating=4 + index row rating=4 asserted; log ring captures `agent: discovered/listed` + `AGENT-DONE`; `stop()` → `.notRunning`; direct SDK client (entry 1, pre-connected) observes the agent's write via rating=4 filter — dual entry proven |
| 6 | Security walkthrough five items green, output in SUMMARY | PASS | SUMMARY §安全走查 items 1-5 verified against source: loopback constant `McpHTTPHost.loopbackHost="127.0.0.1"` (no setter key); `constantTimeCompare` + truth-table test; Origin/Host pipeline = SDK default valves + Bearer appended last, 403/421 matrix test in place; whitelist negative (AC#4); public-repo specials (endpoint schema v1 keys test, auth field carries only `none`/`bearer` markers, token in keychain/0600, no token in logger paths) |
| 7 | PROJECT.md dependency drift fix (16-phase precedent style) | PASS | `.work/gsd/PROJECT.md:71` — explicit three-item SPM enumeration (Swift-WebP → swift-sdk/NIO → swift-nio/system direct) + libavif removal note; README gains the MCP section (Origin-with-port example, render_preview honesty clause, headless flags) |
| 8 | VALIDATION (SC#1-7 three-column + coverage matrix + Manual-Only) + ledger flips (REQUIREMENTS/GOAL-STATE/TODO) + C-tier 3rd-stop trail + full suite 0 fail + per-task commits + boundary switch checks + no push + SUMMARY/DECISIONS on disk | PASS | `14-VALIDATION.md` `status: validated` + `nyquist_compliant: true` + C-tier 3rd-stop record citing the night-authorization precedents; REQUIREMENTS MCP-01..10 → Delivered (2026-09-28, checklist boxes [x], traceability count 10/10); GOAL-STATE continuation point updated; TODO Phase 14 closed; 4 per-task commits verified; `config.toml [gsd]` auto=true/paused=false (healthy); SUMMARY + DECISIONS (16 entries) on disk |

## Findings

| # | Severity | Finding | Disposition |
|---|---|---|---|
| F1 | **minor** (doc drift, fixed) | `.work/TODO.md` 14-4 entry claimed "14 条入 14-4-DECISIONS" with a 14-item list, but the DECISIONS file registers 16 (D-14-4-T3-4 face-regions timeout and D-14-4-T4-1 StoreProvider seam removal were missing from both count and list). | **Fixed by acceptor**: count corrected 14→16, both missing items appended to the list. Commit `fab5fdc` `fix(14-4): correct the decision count in the TODO 14-4 entry`. Root cause: entry drafted before the T4-batch decisions were appended, never recounted. |
| N1 | note (doc nit, not fixed) | SUMMARY line 5 wording "4 tasks / 4 commits + 1 收尾提交" arithmetically implies 5 commits; the actual 14-4 chain is exactly 4 (T4 IS the closing commit, as the SUMMARY's own commit-chain diagram shows). SUMMARY is off-limits to the acceptor; recorded here for the record. | Leave as-is (unambiguous in context). |
| N2 | note | Plan says "TextEditor" for the log pane; implementation is ScrollView+Text with `.textSelection` (read-only display + select/copy). Functionally equivalent for the AC (ring/pause/copy all present) and registered as D-14-4 (panel ScrollView+Text). | No action. |
| N3 | note | SC#7 chain pins the stale face (stale row + `stale:true` served from a real tier-B cache image); the stale→regenerate-through-provider-queue leg remains covered by the 14-3 suite (VALIDATION SC#7 row states this split). The plan AC's "GUI stale 再生同步可见" is satisfied by the stale-row + index-row assertions plus the 14-3 regenerate tests. | No action. |
| N4 | note | `McpLauncher.stop()` reads the registered pid under lock but sends SIGKILL after unlock; a millisecond-scale pid-reuse window exists if the child exits between the last poll and the kill. Inherent macOS pid-reuse hazard; the pid comes from the launcher's own registration and the window is negligible for v1. | No action (v1 acceptable; revisit if a kill-audit need ever appears). |
| N5 | note | Research-item C / redefinition cross-check: the whitelist negative pins `match_color` as zero-occupancy; nothing in the plan conflicts with the Alcedo redefinition within 14-4 scope. | No action. |

## Acceptor-introduced changes

- `fab5fdc` fix(14-4): correct the decision count in the TODO 14-4 entry (F1).
- This report file (committed separately after the fix).

## Verdict rationale

Every plan AC has direct code-level or test-level evidence; the executor's declared numbers (1881/11skip/0fail, per-class counts, commit boundaries) reproduce exactly under independent re-run. The single minor is a documentation count drift, fixed in-place. The VALIDATION sign-off (C-tier 3rd stop) followed the registered night-authorization precedent and is reviewable per that clause. **Plan 14-4 acceptance: PASS.**
