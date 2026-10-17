---
name: lightamer-mcp
description: Use when driving the Lightamer photo editor over MCP — finding a session (GUI endpoint discovery file or the headless stdio/http flags), respecting the tool domain boundaries, handing over the GUI control correctly (acquire before state-changing calls, Stop/resume semantics), reading the typed error codes, and interpreting render_preview output and parameter units.
---

# Lightamer MCP

Lightamer is a macOS RAW/photo editor. One MCP server kernel serves three
host forms: the GUI-embedded HTTP endpoint, a headless stdio fork, and a
headless HTTP daemon — all exposing the same closed face of 32 tools in five
domains. This skill covers how to connect, which domain does what, how the
GUI control hand-off works, and where the details live.

## 1. Installation & session start

**GUI arm.** Start Lightamer and enable its MCP server (Settings). The
server writes a discovery file, `mcp-endpoint.json`, schema v1:

| field | meaning |
| --- | --- |
| `schemaVersion` | `1` |
| `transport` | `streamable-http` |
| `host` | `127.0.0.1` on the loopback default; the LAN address when non-loopback exposure is on |
| `port` | the bound port |
| `pid` | the serving process id |
| `startedAt` | RFC 3339 UTC |
| `serverName` / `serverVersion` | `lightamer` / the app bundle version |
| `auth` | `none` (loopback default — zero-token) or `bearer` (non-loopback exposure mandates a token) |

Point your MCP client at `http://<host>:<port>/mcp` (Streamable HTTP). The
loopback default carries no token. On non-loopback exposure a Bearer token
is required; its body never appears in the discovery file (the app keeps it
in the keychain or a 0600 fallback file).

**Headless arms.** The same binary forks headless on argv:

```sh
Lightamer --mcp-stdio              # MCP over stdio (no discovery file)
Lightamer --mcp-http               # MCP over HTTP, loopback, writes the discovery file
Lightamer --project <path.lalb>    # with project arbitration: writer arm serves, held-by-other arm serves read-only
```

**Launcher templates.** The GUI's launcher panel runs a user-supplied shell
template in which `{{LIGHTAMER_MCP}}` expands to the discovery-file path and
`{{PROMPT}}` to the user's prompt text. Any prompt-style rules for a given
workflow belong in that template, not in this skill.

## 2. Turn-taking (GUI control)

On a GUI-backed session, 13 of the 32 tools change session state
(`load_image`, `apply_params`, `paste_adjustments`, `export_image`,
`set_rating`, `set_flag`, `set_color_label`, `append_note`, `set_keywords`,
`apply_preset`, `match_color`, `project_open`, `project_create`) and refuse
with `controlNotHeld` until THIS agent session holds the control:

1. Call `control_acquire` with your holder name before any state-changing
   call. While the user is mid-edit (a slider drag), the acquire waits,
   bounded, for the editor input to seal; on timeout it answers
   `controlBusy` with the unsealed semantics.
2. Each held session's state-changing call passes the control gate (the
   activity card shows the command).
3. The user may press Stop on the activity card — that returns the control
   to the user immediately and further commands answer
   `controlRevokedByUser`. The same holder re-acquiring resumes the SAME
   task (the activity history continues). Re-acquire after asking the user
   how to proceed.
4. If the editor input seals and a user Stop land in the same poll window,
   `control_acquire` answers `controlRevokedByUser` rather than granting
   silently — treat it as the Stop face above, not as an error to retry
   blindly. Likewise, if another holder completed its acquire while you were
   waiting, the acquire answers `controlBusy` carrying the holder.
5. The three control tools (`control_acquire` / `control_release` /
   `control_get`) never ride the gate. `control_release` is the polite exit;
   a release is terminal for the task row (a later acquire by anyone mints a
   new task).

**Headless arms**: the control face answers the always-held constant
(`held: true`, `holder: ""`) and every state-changing tool passes — there is
no human to hand the control back to.

## 3. Tool domains

32 tools across five domains. The machine-checked per-tool reference (names,
domain sections, hints, verbatim schemas with per-field argument semantics)
lives in [references/tools.md](references/tools.md); the domain boundaries
are:

- **editing (9)** — the pixel-session face. `load_image` / `apply_params` /
  `render_preview` / `export_image` change or produce pixels;
  `list_iops` / `list_luts` / `copy_adjustments` / `paste_adjustments` /
  `match_color` inspect and transfer edits. An open GUI session (or a
  headless `--project` arm's session face) is required; without one the
  session-bound tools answer `notSessionMember`.
- **culling (14)** — library inspection and metadata write-back
  (`list_photos`, `list_presets`, `apply_preset`, `diff_presets`,
  `get_thumbnails`, `get_contact_sheet`, `get_detail_crop`, `list_bursts`,
  `get_face_regions`, plus rating/flag/label/note/keywords writers). These
  need an open project or session; the metadata writers are the
  state-changing subset.
- **searchstate (3)** — `search_photos` (semantic/fulltext search),
  `get_history` (edit history), `get_state` (the whole live-state snapshot
  including the control face). All read-only.
- **project (3)** — `project_open` / `project_create` / `list_versions`:
  the `.lalb` package face. Opening/creating rides the control gate on a
  GUI session and the writer lock elsewhere.
- **control (3)** — the turn-taking face (§2). Read-only with respect to
  pixels; changing the control IS the control.

## 4. Error codes

All failures are typed snake_case codes on the tool error text — 19 codes,
each with its meaning and recovery action in
[references/errors.md](references/errors.md). Match on the code token, not
on the prose.

## 5. render_preview semantics

`render_preview` renders the SAVED edit state (the disk sidecar), not the
GUI's live viewport:

- The output is an inline sRGB-encoded JPEG of the EDIT state — no yiyin
  frame/watermark (those are an export-page feature in the GUI), and not the
  GUI's EDR display domain. It reflects the last save; GUI-side saves ride a
  ~2s debounce.
- `compare: root` (the default) rides the pristine (edit-free) render along:
  content order is `[current, root, text]` — a built-in before/after pair.
- `region` is a normalized 0..1 `{x,y,w,h}` ROI relative to the RENDERED
  output frame, cropped AFTER the render (decoupled from `longEdge`);
  `get_detail_crop` is the different thing — an absolute-pixel ROI at native
  source resolution.
- Bounds: `longEdge` 1...2048 (default 1024), `quality` 1...90 (default 85).
  For anything larger, or for files on disk, use `export_image`.

## 6. UI units

The GUI sliders store RAW parameter values — the on-screen range and unit
suffix (EV, percent, pixels) are display affinities; the wire value is the
same number the readout shows, with no UI-side scaling. `list_iops` is the
agent-facing schema channel: per operation it returns the parameter keys,
types, the applicable source domain, and the params-shape `version` (bump it
when a params shape migrates — re-read the catalog when it changes). Ops
with nested payloads that the catalog does not annotate take full-JSON
replaces through `apply_params`; the catalog is the key reference, not a
whitelist.

## 7. Known surface asymmetries

`get_state`'s `project` object is not byte-identical across the host arms:
the headless liveState carries `project.heldByOther` (the arbitration box
truth) next to `path`/`readOnly`, while the GUI arm's project object carries
only `path`/`readOnly`. Treat key presence as informational, not part of the
contract; the `control.agent` sub-object and the `server` object are stable
across arms.
