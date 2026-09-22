#!/usr/bin/env python3
"""05-08 bilateral dt-cli adoption driver — the 05-06/05-07 flow replicated:
per case {dt-cli flat_0ev.exr + XMP → export EXR | -d params | fresh library}
then ① loader line ② params v.1 version-ok ③ DB hex vs XMP blob (20B)
④ flat probe (flat in → identity out for both legs)."""
import re, sqlite3, subprocess, sys, os

ROOT = "/Volumes/UNITEK/Documents/Development/Lightamer"
DT = "/Volumes/UNITEK/Documents/Development/darktable/build/bin/darktable-cli"
ADOPT = os.path.join(ROOT, ".work/plans/05-08/adoption")
CONF = os.path.join(ADOPT, "conf")
CASES = ("bilat_direct_small", "bilat_boundary", "bilat_grid_large")
FLAT = os.path.join(ROOT, "input/golden/fixtures/flat_0ev.exr")
sys.path.insert(0, os.path.join(ROOT, "input/golden/fixtures"))
import gen_fixtures as G  # noqa: E402

os.makedirs(CONF, exist_ok=True)
results, adopted = [], 0
for case in CASES:
    xmp = os.path.join(ROOT, f"input/golden/cases/{case}.xmp")
    out = os.path.join(ADOPT, f"{case}.exr")
    log = os.path.join(ADOPT, f"adopt_{case}.log")
    db = os.path.join(CONF, f"{case}.db")
    for stale in (db, out):
        if os.path.exists(stale):
            os.remove(stale)
    xmp_hex = re.search(
        r"<darktable:params>([0-9a-f]+)</darktable:params>",
        open(xmp).read()).group(1)
    cmd = [DT, FLAT, xmp, out, "--library", db,
           "--apply-custom-presets", "0",
           "--core", "--configdir", CONF, "-d", "params"]
    with open(log, "w") as lf:
        subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, cwd=ADOPT, check=False)
    text = open(log, errors="replace").read()
    loaded = "successfully loaded module bilateral from history" in text
    vok = bool(re.search(r"params v\. 1:\s*version ok\s*params ok", text))
    db_hex = None
    if os.path.exists(db):
        try:
            rows = sqlite3.connect(db).execute(
                "SELECT hex(op_params) FROM history WHERE operation='bilateral'"
            ).fetchall()
            db_hex = rows[0][0] if rows else None
        except Exception as exc:  # noqa: BLE001
            print(f"{case}: DB read error {exc}")
    identical = bytes.fromhex(db_hex) == bytes.fromhex(xmp_hex)
    # flat probe: EXR float32 — flat in → identity out (domain-constant)
    max_dev = None
    if os.path.exists(out):
        _w, _h, rgb = G.read_exr_rgb(out)
        devs = [abs(v - 0.5) for ch in rgb for v in ch]
        max_dev = max(devs)
    ok = loaded and vok and identical
    adopted += 1 if ok else 0
    results.append((case, loaded, vok, identical, db_hex, max_dev))
    print(f"{case}: loader={loaded} v1ok={vok} hex_identical={identical} "
          f"blob_len={len(xmp_hex)//2}B flat_max_dev={max_dev}")

print(f"ADOPTION {adopted}/{len(CASES)}")
