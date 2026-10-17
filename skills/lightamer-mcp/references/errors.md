# Error codes

All Lightamer MCP tool failures surface a stable snake_case code token at
the head of the error text (19 codes, a closed table — new codes appear only
through a deliberate toolset change). Match on the code token; the prose
after it carries the specifics. The three `control*` codes are the GUI
turn-taking faces (see SKILL.md §2); `controlNotHeld` ≙ an acquire-gated
refusal, `controlRevokedByUser` ≙ a user Stop, `controlBusy` ≙ a contention
or unsealed-editor face.

| code | meaning | recovery |
| --- | --- | --- |
| `unknownOp` | the op name in an edit payload is not a registered module | read `list_iops`; use a cataloged op name |
| `invalidParams` | an argument is missing, mistyped, or outside its documented range | fix the argument per the tool schema |
| `imageLiveInEditor` | the requested image is the live editor document and the command needs it quiescent | retry after the GUI closes/switches the document, or address a non-live image |
| `notSessionMember` | the addressed image/path is not a member of the open session/project, or no project is open | open a session/project first or address an existing member |
| `serverReadOnly` | this host holds no writer right (another Lightamer instance is the writer) | connect to the holder's endpoint (see `mcp-endpoint.json` guidance) instead of writing here |
| `renderFailed` | the render pipeline failed on this input | read the detail; adjust the request or the edit state |
| `renderTimeout` | the render exceeded the 30 s window | reduce `longEdge`/quality or split the request; retry once after the load settles |
| `exportFailed` | the export pipeline failed (encoding/destination) | read the detail; fix the destination or format options |
| `invalidFilter` | a search filter expression is malformed | fix the filter syntax |
| `roiOutOfBounds` | an ROI rect exceeds the frame bounds | clamp the rect to the documented 0..1 (region) or image-pixel (detail crop) domain |
| `keywordContainsSeparator` | a keyword carries the reserved separator | remove the separator character and retry |
| `exportPresetNotApplicable` | the preset does not apply to this image/format combination | pick an applicable preset or export without it |
| `unknownPreset` | the preset name is not registered | read `list_presets`; use a listed name |
| `projectReadOnly` | the open project is read-only (another instance holds the write right) | work read-only or take over the writer lock through the GUI |
| `internalError` | an unexpected server-side failure (including unknown tool names) | read the detail; report if reproducible — not a caller-fixable face |
| `modelUnavailable` | the semantic runtime cannot serve this query (assets missing or the AI worker unavailable) | no parameter change helps; install/repair the AI assets or retry later |
| `controlNotHeld` | a state-changing command arrived without this session holding the GUI control | call `control_acquire` first |
| `controlRevokedByUser` | the user stopped the agent (the activity card Stop), or the Stop landed in the acquire wait window | stop working; ask the user, then `control_acquire` again (the same holder resumes the task) |
| `controlBusy` | another holder holds the control (the message carries it), or the acquire wait timed out on an unsealed editor input | wait for the holder to release or the editor input to seal; retry `control_acquire` |
