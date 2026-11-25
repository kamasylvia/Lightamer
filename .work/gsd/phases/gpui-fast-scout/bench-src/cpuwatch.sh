#!/bin/bash
# cpuwatch.sh <pid> <seconds> <label>
# Exact CPU utilisation from cputime deltas, plus RSS. Prints one line.
set -u
PID=$1; SECS=$2; LABEL=${3:-run}
read_cpu() { ps -o cputime= -p "$PID" 2>/dev/null | tr -d ' '; }
to_s() { echo "$1" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }'; }
C0=$(read_cpu); [ -z "$C0" ] && { echo "$LABEL dead"; exit 1; }
S0=$(to_s "$C0")
R0=$(ps -o rss= -p "$PID" | tr -d ' ')
T0=$(python3 -c 'import time;print(time.time())')
sleep "$SECS"
C1=$(read_cpu); [ -z "$C1" ] && { echo "$LABEL died during window"; exit 1; }
S1=$(to_s "$C1")
R1=$(ps -o rss= -p "$PID" | tr -d ' ')
T1=$(python3 -c 'import time;print(time.time())')
python3 - "$LABEL" "$S0" "$S1" "$T0" "$T1" "$R0" "$R1" <<'EOF'
import sys
label, s0, s1, t0, t1, r0, r1 = sys.argv[1:8]
s0, s1, t0, t1 = float(s0), float(s1), float(t0), float(t1)
r0, r1 = int(r0) / 1024, int(r1) / 1024
wall = t1 - t0
print(f"{label} cpu={(s1-s0)/wall*100:.1f}% over {wall:.2f}s rss={r0:.0f}->{r1:.0f}MB")
EOF
