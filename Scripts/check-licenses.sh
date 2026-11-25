#!/bin/bash
# check-licenses.sh — cargo 工作区许可证检查（A1 交付）
#
# 用法：Scripts/check-licenses.sh [WORKSPACE_DIR]
#   无参数时检查仓库根目录的工作区（根 Cargo.toml 不存在则报错）。
#   只读元数据：cargo metadata --locked --offline，不构建。
#
# 数据文件（与本脚本同目录）：
#   licenses-allow.txt      允许清单，一行一个 license 字符串（精确匹配）
#   licenses-exceptions.txt 例外清单，<包名> | <license 或 (empty)> | <理由>
# 任一数据文件格式非法 → 报错退出 1。
# 退出码：全部通过 0；有包两边都不在（或空 license 无例外）1。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOW_FILE="$SCRIPT_DIR/licenses-allow.txt"
EXC_FILE="$SCRIPT_DIR/licenses-exceptions.txt"

err() { echo "check-licenses: ERROR: $*" >&2; }

# --- 参数 ---
WS="${1:-$SCRIPT_DIR/..}"
if [ ! -f "$WS/Cargo.toml" ]; then
  err "no Cargo.toml in workspace dir: $WS"
  exit 1
fi
if [ ! -f "$ALLOW_FILE" ]; then err "missing data file: $ALLOW_FILE"; exit 1; fi
if [ ! -f "$EXC_FILE" ]; then err "missing data file: $EXC_FILE"; exit 1; fi
command -v cargo >/dev/null 2>&1 || { err "cargo not found in PATH"; exit 1; }
command -v python3 >/dev/null 2>&1 || { err "python3 not found in PATH"; exit 1; }

# --- 取元数据（只读，不构建；落临时文件，避开 argv 长度上限） ---
META_TMP="$(mktemp -t check-licenses-meta.XXXXXX)"
trap 'rm -f "$META_TMP" /tmp/check-licenses-meta.err' EXIT
cargo metadata --locked --offline --format-version 1 \
  --manifest-path "$WS/Cargo.toml" >"$META_TMP" 2>/tmp/check-licenses-meta.err || {
  err "cargo metadata failed for $WS/Cargo.toml:"
  sed 's/^/  /' /tmp/check-licenses-meta.err >&2
  exit 1
}

# --- 对照（python3 做 JSON 解析与清单校验） ---
export ALLOW_FILE EXC_FILE
python3 - "$META_TMP" <<'PYEOF'
import json, os, re, sys

def load_allow(path):
    allowed = set()
    with open(path, encoding="utf-8") as f:
        for i, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # 非注释行必须是非空许可表达式（不含 '|'，那是例外清单的分隔符）
            if "|" in line:
                print(f"check-licenses: ERROR: {path}:{i}: '|' not allowed in allow list",
                      file=sys.stderr)
                sys.exit(1)
            allowed.add(line)
    if not allowed:
        print(f"check-licenses: ERROR: {path}: allow list is empty", file=sys.stderr)
        sys.exit(1)
    return allowed

def load_exceptions(path):
    exc = {}  # (name, license) -> reason
    name_re = re.compile(r"^[A-Za-z0-9_.\-]+$")
    with open(path, encoding="utf-8") as f:
        for i, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 3 or not parts[0] or not parts[1] or not parts[2]:
                print(f"check-licenses: ERROR: {path}:{i}: bad format, "
                      f"want '<name> | <license> | <reason>'", file=sys.stderr)
                sys.exit(1)
            if not name_re.match(parts[0]):
                print(f"check-licenses: ERROR: {path}:{i}: bad package name "
                      f"'{parts[0]}'", file=sys.stderr)
                sys.exit(1)
            exc[(parts[0], parts[1])] = parts[2]
    return exc

allowed = load_allow(os.environ["ALLOW_FILE"])
exc = load_exceptions(os.environ["EXC_FILE"])

with open(sys.argv[1], encoding="utf-8") as f:
    meta = json.load(f)
pkgs = sorted(meta["packages"], key=lambda p: (p["name"], p["version"]))

n_allow = n_exc = n_fail = 0
fails = []
print(f"{'package':42s} {'version':12s} {'verdict':9s} license")
for p in pkgs:
    name, ver = p["name"], p["version"]
    lic = (p.get("license") or "").strip()
    key = lic if lic else "(empty)"
    if lic and lic in allowed:
        verdict = "ALLOW"
        n_allow += 1
    elif (name, key) in exc:
        verdict = "EXCEPT"
        n_exc += 1
    else:
        verdict = "FAIL"
        n_fail += 1
        fails.append((name, ver, key))
    print(f"{name:42s} {ver:12s} {verdict:9s} {key}")

print(f"---\nallow={n_allow} exception={n_exc} fail={n_fail} total={len(pkgs)}")
for name, ver, key in fails:
    print(f"FAIL {name} {ver}: license '{key}' not in allow list and no exception")
if exc:
    print("--- exceptions applied:")
    seen = {(n, k) for (n, v, k) in
            [(p["name"], p["version"], ((p.get("license") or '').strip() or "(empty)"))
             for p in pkgs]}
    for (name, key), reason in sorted(exc.items()):
        status = "HIT" if (name, key) in seen else "UNUSED"
        print(f"  [{status}] {name} | {key} | {reason}")
sys.exit(1 if n_fail else 0)
PYEOF
