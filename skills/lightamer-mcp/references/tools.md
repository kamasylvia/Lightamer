# Tools reference

GENERATED FILE — `SkillsReferenceTests.renderToolsReference()` renders
the live registry and byte-compares this file on every suite run
(OQ-M7-6-3: the test IS the gate). Edit the toolset sources, not this
file; a registration change lands here through the snapshot tests.

34 tools across five domains
editing (11) / culling (14) / searchstate (3) / project (3) / control (3).
Hints mirror the `tools/list` annotation columns (`readOnlyHint`,
`destructiveHint`); the schema is the verbatim `inputSchema` JSON
(its per-field descriptions are the English argument semantics).
The registry's tool-level descriptions are zh-catalog text (the
zh localization family) — they stay OUT of this reference: the
skill docs are en-only by decision (OQ-M7-6-2), and the domain
boundaries in SKILL.md §3 carry the English semantics.

## editing (11 tools)

### apply_params

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"ops":{"type":"array","minItems":1,"description":"Module-level upserts","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer","default":0},"params":{"type":"object","description":"Partial params JSON overlaid on the instance (keys per list_iops)"},"enabled":{"type":"boolean"},"remove":{"type":"boolean","default":false}},"required":["opName"]}},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to the history commit (distinct from the document-level note set via append_note)"}},"required":["relPath","ops"]}
```

### copy_adjustments

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath"}},"required":["source"]}
```

### export_image

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"format":{"type":"string","enum":["jpeg","png","tiff","heic","avif","webp"],"default":"jpeg"},"quality":{"type":"integer","minimum":1,"maximum":100,"default":90,"description":"Lossy formats only"},"sizing":{"type":"object","properties":{"mode":{"type":"string","enum":["original","longEdge","shortEdge"],"default":"original"},"px":{"type":"integer","minimum":1,"description":"Required for longEdge/shortEdge"}}},"colorSpace":{"type":"string","enum":["sRGB","displayP3","adobeRGB","proPhoto","rec2020"],"default":"sRGB"},"yiyin":{"type":"boolean","default":false,"description":"Render through the image's existing yiyin frame/watermark configuration"}},"required":["relPath"]}
```

### get_schema

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{},"required":[]}
```

### list_iops

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{},"required":[]}
```

### list_luts

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{},"required":[]}
```

### load_image

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"}},"required":["relPath"]}
```

### match_color

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","properties":{"reference":{"type":"string","description":"Reference image: a library image id (digits) or an open-session relPath"},"targets":{"oneOf":[{"type":"string"},{"type":"array","items":{"type":"string"}}],"maxItems":30,"description":"Target relPath(s) relative to the session root; default = the editor's current image"},"strength":{"type":"number","minimum":0,"maximum":1,"default":1,"description":"The solve/identity blend"},"solver":{"type":"string","enum":["gaussian-ot","reinhard","cdf"],"default":"gaussian-ot"},"attach":{"type":"boolean","default":true,"description":"false = return the params for apply_params instead of writing"}},"required":["reference"]}
```

### paste_adjustments

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath (the copy_adjustments addressing)"},"targets":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":1000,"description":"Open-session relPaths to paste onto"},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to each history commit (distinct from the document-level note set via append_note)"},"include":{"type":"array","items":{"type":"string","format":"uuid"},"description":"instanceId subset from copy_adjustments (default: every transferable instance)"},"includeDrt":{"type":"boolean","default":true,"description":"false drops the source's DRT row"},"version":{"type":"string","description":"A copy_adjustments versions[] id (default: the active chain)"}},"required":["source","targets"]}
```

### refine_masks

- readOnlyHint: false
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root — MUST be the editor's current image"},"maskIds":{"type":"array","items":{"type":"string","description":"The owning layer's UUID"},"minItems":1,"maxItems":30,"description":"Layer UUIDs whose AI raster masks to refine"}},"required":["relPath","maskIds"]}
```

### render_preview

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"},"region":{"type":"object","properties":{"x":{"type":"number","minimum":0,"maximum":1},"y":{"type":"number","minimum":0,"maximum":1},"w":{"type":"number","exclusiveMinimum":0,"maximum":1},"h":{"type":"number","exclusiveMinimum":0,"maximum":1}},"required":["x","y","w","h"],"description":"Normalized 0..1 ROI {x,y,w,h} relative to the RENDERED output frame (orientation already normalized); cropped after the render, decoupled from longEdge"},"compare":{"type":"string","enum":["none","root"],"default":"root","description":"none = the edited image only; root (default) = the pristine (edit-free) image rides along for the before/after loop"}},"required":["relPath"]}
```

## culling (14 tools)

### append_note

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","required":["relPaths","note"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"note":{"type":"string","minLength":1,"description":"Appended as one line (a newline is inserted after an existing note)"}}}
```

### apply_preset

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","required":["presetID","relPaths"],"properties":{"presetID":{"type":"string"},"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"mode":{"enum":["overwrite","merge"],"description":"Paste mode (default merge)"},"selection":{"type":"array","description":"Partial-apply subset of instances","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer"},"multiName":{"type":"string"}},"required":["opName","multiPriority","multiName"]}}}}
```

### diff_presets

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","required":["presetIDA","presetIDB"],"properties":{"presetIDA":{"type":"string"},"presetIDB":{"type":"string"}}}
```

### get_contact_sheet

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":30},"filter":{"type":"object","description":"FilterPredicateGroup JSON (same shape as list_photos.filter)"},"sort":{"type":"object","description":"Row order when filter is used (same shape as list_photos.sort)"},"cols":{"type":"integer","minimum":1,"maximum":6},"rows":{"type":"integer","minimum":1,"maximum":5}},"oneOf":[{"required":["relPaths"]},{"required":["filter"]}]}
```

### get_detail_crop

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","required":["relPath","roi"],"properties":{"relPath":{"type":"string"},"roi":{"type":"object","properties":{"x":{"type":"integer","minimum":0},"y":{"type":"integer","minimum":0},"w":{"type":"integer","exclusiveMinimum":0},"h":{"type":"integer","exclusiveMinimum":0}},"required":["x","y","w","h"]},"longEdge":{"type":"integer","minimum":64,"maximum":1536,"description":"Output long edge (default 1024)"}}}
```

### get_face_regions

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"includeLandmarks":{"type":"boolean","description":"Also return per-face landmark point sets (default false)"}}}
```

### get_thumbnails

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"regenerate":{"type":"boolean","description":"Re-render stale thumbnails before returning (default false — stale rows are only marked)"}}}
```

### list_bursts

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"gapSeconds":{"type":"number","exclusiveMinimum":0,"description":"Max gap between consecutive shots of one burst (default 2.0)"}}}
```

### list_photos

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"cursor":{"type":"string","description":"Opaque nextCursor token from the previous page"},"filter":{"type":"object","description":"FilterPredicateGroup JSON: {schemaVersion:1, match:"all"|"any", rules:[{field, op, value:{kind, ...}}]}"},"limit":{"type":"integer","minimum":1,"maximum":1000,"description":"Rows per page (default 200)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength|scanEpoch, ascending: bool}"}}}
```

### list_presets

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"kind":{"enum":["develop","export"],"description":"Filter by preset kind"}}}
```

### set_color_label

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","required":["relPaths","color"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"color":{"type":["integer","null"],"minimum":0,"maximum":6,"description":"0-6, or null to clear"}}}
```

### set_flag

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","required":["relPaths","flag"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"flag":{"type":["integer","null"],"minimum":0,"maximum":2,"description":"0 none / 1 pick / 2 reject, or null to clear"}}}
```

### set_keywords

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","required":["relPaths","keywords"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"keywords":{"type":["array","null"],"items":{"type":"string"},"description":"Whole-group replacement; empty array = cleared state, null = never-tagged; entries must not contain '|'"}}}
```

### set_rating

- readOnlyHint: false
- destructiveHint: true

Schema (verbatim):

```json
{"type":"object","required":["relPaths","rating"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"rating":{"type":["integer","null"],"minimum":0,"maximum":5,"description":"0-5, or null to clear"}}}
```

## searchstate (3 tools)

### get_history

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeParams":{"type":"boolean","default":false,"description":"Add the per-item params face"},"limit":{"type":"integer","minimum":1,"maximum":500,"description":"Item cap (default 500); truncation keeps the NEWEST end — position/itemCount stay the true values, so truncation is detectable"}},"required":["image"]}
```

### get_state

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{},"required":[]}
```

### search_photos

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"query":{"type":"string","minLength":1,"description":"The search query (the EXIF grammar: plain words + structured tokens like iso800, f/2.8, 2024-06..2024-08)"},"mode":{"type":"string","enum":["exif","clip","fulltext"],"default":"exif","description":"The route (default exif)"},"limit":{"type":"integer","minimum":1,"maximum":500,"description":"Rows per call (exif default 200; clip/fulltext caps 256/500)"},"cursor":{"type":"string","description":"Opaque nextCursor token — EXIF mode ONLY (a token is only valid for its issuing sort and this tool)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength, ascending: bool} — EXIF mode ONLY; default filename ascending"}},"required":["query"]}
```

## project (3 tools)

### list_versions

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeItems":{"type":"boolean","default":false,"description":"Attach each version's own item list (capped at the 500 NEWEST; the truncated flag rides per version)"}},"required":["image"]}
```

### project_create

- readOnlyHint: false
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"folder":{"type":"string","description":"An EXISTING directory the package is created in"},"name":{"type":"string","minLength":1,"description":"The package name (folder/<name>.lalb; no path separators / colons / leading dots)"}},"required":["folder","name"]}
```

### project_open

- readOnlyHint: false
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"path":{"type":"string","description":"The absolute path of the .lalb package to open"}},"required":["path"]}
```

## control (3 tools)

### control_acquire

- readOnlyHint: false
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{"holder_name":{"type":"string","description":"Session label for this holder (default agent)"}}}
```

### control_get

- readOnlyHint: true
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{}}
```

### control_release

- readOnlyHint: false
- destructiveHint: false

Schema (verbatim):

```json
{"type":"object","properties":{}}
```
