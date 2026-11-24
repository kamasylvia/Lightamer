#!/bin/bash
# Restore preference state for the darktable GUI-timing lane. Reads run-before records only.
set -u
G=/Users/Shared/lightamer-gui-test/darktable
echo "== domains now vs before =="
defaults domains | tr ',' '\n' | sed 's/^ *//' | sort > "$G/domains-after.txt"
comm -13 "$G/domains-before.txt" "$G/domains-after.txt" > "$G/domains-new.txt"
cat "$G/domains-new.txt"
echo "== restoring org.darktable from exported plist =="
defaults import org.darktable "$G/prefs-backup-org.darktable.plist" && echo "imported"
echo "== new Library top-level entries (name-matched only) =="
for d in "Application Support" Preferences Caches Containers "Saved Application State" HTTPStorages Logs; do
  ls -1 "$HOME/Library/$d" 2>/dev/null | sed "s|^|$d\t|"
done | sort > "$G/lib-after.txt"
# snapshot-before format: "## <dir>" headers followed by names
python3 - "$G/snap-before.txt" "$G/lib-after.txt" <<'PY'
import sys
before=set(); cur=sys.argv[1]
sec=None
for line in open(sys.argv[1]):
    line=line.rstrip('\n')
    if line.startswith('## '): sec=line[3:]; continue
    if sec and line: before.add(sec+'\t'+line)
for line in open(sys.argv[2]):
    key=line.rstrip('\n')
    if key not in before:
        dirname,name=key.split('\t',1)
        if 'darktable' in name.lower() or name.lower().startswith('org.darktable'):
            print('NEW:', key)
PY
